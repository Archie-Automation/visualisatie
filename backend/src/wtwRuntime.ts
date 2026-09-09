import { getConfig, walkDevices } from "./config";
import type { KnxBus } from "./knxBus";
import { logger } from "./logger";
import type {
  Device,
  DucoStandId,
  GAState,
  WtwDevice,
  WtwDucoConnectivityBoard,
  WtwDucoLogic,
  WtwZehnderComfoConnect,
  WtwZehnderLogic,
  WtwZehnderStandId,
  WtwLogicClause,
  WtwLogicJoin,
  WtwTempRiseTrigger
} from "./types";
import {
  asGa,
  bitOn,
  collectDucoSubscriptions,
  ducoLogics,
  DUCO_STAND_BYTE,
  pressDucoStand,
  pressZehnderStand,
  readBoostMinutes,
  readDucoActiveStand,
  readZehnderActiveStand,
  writeBoostMinutes,
  writeZehnderAuto,
  zehnderAutoIsOn,
  zehnderLogics
} from "./wtw";

export interface WtwLogicStatus {
  deviceId: string;
  logicId: string;
  label: string;
  standId: string;
  end: "duration" | "untilStatus";
  /** Epoch ms waarop de huidige timer eindigt; null = actief zonder afteller. */
  untilMs: number | null;
  /** Boost-einde (zelfde als app-timer); null = geen boost van deze logica. */
  boostUntilMs: number | null;
}

type BoostRestore = {
  deviceId: string;
  timer: ReturnType<typeof setTimeout>;
};

type LogicRun = {
  deviceId: string;
  logicId: string;
  label: string;
  standId: string;
  end: "duration" | "untilStatus";
  restoreStand: WtwZehnderStandId;
  after: string;
  restoreBoostMinutes: number | null;
  untilMs: number | null;
  boostUntilMs: number | null;
  untilTimer?: ReturnType<typeof setTimeout>;
  durationTimer?: ReturnType<typeof setTimeout>;
};

type LogicListener = (runs: WtwLogicStatus[]) => void;

function asWtw(d: Device): WtwDevice | null {
  return d.type === "wtw" ? d : null;
}

function logicEnabled(l: WtwZehnderLogic): boolean {
  return l.enabled !== false;
}

function wantedValue(
  raw: unknown,
  equals: boolean | undefined,
  defaultOn: boolean
): unknown {
  if (raw != null && String(raw).trim() !== "") return raw;
  if (typeof equals === "boolean") return equals;
  return defaultOn;
}

function valueMatches(actual: unknown, want: unknown): boolean {
  if (typeof want === "boolean") return want ? bitOn(actual) : !bitOn(actual);
  const wantStr = String(want).trim();
  if (wantStr === "") return false;
  const lower = wantStr.toLowerCase();
  if (lower === "true" || lower === "on") return bitOn(actual);
  if (lower === "false" || lower === "off") return !bitOn(actual);
  if (wantStr === "1" || wantStr === "0") {
    const bitLike =
      typeof actual === "boolean" ||
      actual === 0 ||
      actual === 1 ||
      actual === "0" ||
      actual === "1";
    if (bitLike) return wantStr === "1" ? bitOn(actual) : !bitOn(actual);
  }
  const wantNum = Number(wantStr.replace(",", "."));
  const actualNum =
    typeof actual === "number" ? actual : Number(String(actual).replace(",", "."));
  if (Number.isFinite(wantNum) && Number.isFinite(actualNum)) {
    return Math.abs(actualNum - wantNum) < 1e-6;
  }
  return String(actual).trim().toLowerCase() === lower;
}

function triggerWant(logic: WtwZehnderLogic): unknown {
  return wantedValue(logic.triggerValue, logic.triggerEquals, true);
}

function untilWant(logic: WtwZehnderLogic): unknown {
  return wantedValue(logic.untilValue, logic.untilEquals, false);
}

function orWant(logic: WtwZehnderLogic): unknown {
  return wantedValue(logic.orValue, logic.orEquals, true);
}

function clauseWant(c: WtwLogicClause, defaultOn: boolean): unknown {
  return wantedValue(c.value, c.equals, defaultOn);
}

function joinOf(raw: WtwLogicJoin | undefined): WtwLogicJoin {
  return raw === "and" ? "and" : "or";
}

type TriggerArm = {
  suffix: string;
  ga: string;
  want: unknown;
  minutes: number;
};

function armsFromClauses(
  clauses: WtwLogicClause[] | undefined,
  prefix: string,
  defaultOn: boolean,
  minutesFallback: number,
  minutesMin: number
): TriggerArm[] {
  if (!Array.isArray(clauses)) return [];
  const out: TriggerArm[] = [];
  clauses.forEach((c, i) => {
    const ga = asGa(c.ga);
    if (!ga) return;
    out.push({
      suffix: `${prefix}${i}`,
      ga,
      want: clauseWant(c, defaultOn),
      minutes: clampInt(c.minutes, minutesFallback, minutesMin, 1440)
    });
  });
  return out;
}

function whenArms(logic: WtwZehnderLogic): TriggerArm[] {
  const fromList = armsFromClauses(logic.when, "w", true, 0, 0);
  if (fromList.length > 0) return fromList;
  const out: TriggerArm[] = [];
  const ga = asGa(logic.triggerGa);
  if (ga) {
    out.push({
      suffix: "main",
      ga,
      want: triggerWant(logic),
      minutes: clampInt(logic.triggerMinutes, 0, 0, 1440)
    });
  }
  const orGa = asGa(logic.orGa);
  if (orGa) {
    out.push({
      suffix: "or",
      ga: orGa,
      want: orWant(logic),
      minutes: clampInt(logic.orMinutes, 0, 0, 1440)
    });
  }
  return out;
}

function untilArms(logic: WtwZehnderLogic): TriggerArm[] {
  const fromList = armsFromClauses(logic.untilWhen, "u", false, 5, 1);
  if (fromList.length > 0) return fromList;
  const ga = asGa(logic.untilGa) ?? asGa(logic.triggerGa);
  if (!ga) return [];
  return [
    {
      suffix: "u0",
      ga,
      want: untilWant(logic),
      minutes: clampInt(logic.untilMinutes ?? logic.minutes, 5, 1, 1440)
    }
  ];
}

function clampInt(n: unknown, fallback: number, min: number, max: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.min(max, Math.max(min, Math.round(v)));
}

/* ---------- temperature rate-of-change buffer ------------------------- */

type TempSample = { value: number; ts: number };

/** Ring buffer per GA; keeps samples within the largest configured window. */
class TempHistory {
  private samples = new Map<string, TempSample[]>();
  private maxWindow = new Map<string, number>();

  register(ga: string, windowSec: number): void {
    const cur = this.maxWindow.get(ga) ?? 0;
    if (windowSec > cur) this.maxWindow.set(ga, windowSec);
  }

  push(ga: string, value: number): void {
    if (!this.maxWindow.has(ga)) return;
    const now = Date.now();
    const list = this.samples.get(ga) ?? [];
    list.push({ value, ts: now });
    const cutoff = now - (this.maxWindow.get(ga)! + 2) * 1000;
    while (list.length > 0 && list[0].ts < cutoff) list.shift();
    this.samples.set(ga, list);
  }

  /** Returns the minimum value seen in the last `windowSec` seconds. */
  minInWindow(ga: string, windowSec: number): number | null {
    const list = this.samples.get(ga);
    if (!list || list.length === 0) return null;
    const cutoff = Date.now() - windowSec * 1000;
    let min: number | null = null;
    for (const s of list) {
      if (s.ts >= cutoff && (min === null || s.value < min)) min = s.value;
    }
    return min;
  }

  /** Latest sample value. */
  latest(ga: string): number | null {
    const list = this.samples.get(ga);
    if (!list || list.length === 0) return null;
    return list[list.length - 1].value;
  }

  clear(): void {
    this.samples.clear();
    this.maxWindow.clear();
  }
}

class WtwRuntime {
  private bus: KnxBus | null = null;
  private unsub: (() => void) | null = null;
  private prev = new Map<string, unknown>();
  private boostRestore = new Map<string, BoostRestore>();
  private logicRuns = new Map<string, LogicRun>();
  private triggerTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private triggerHeld = new Set<string>();
  private listeners = new Set<LogicListener>();
  private tempHistory = new TempHistory();

  attach(bus: KnxBus): void {
    this.detach();
    this.bus = bus;
    this.registerTempRiseGAs();
    const onState = (state: GAState) => this.onBusState(state);
    bus.on("stateChanged", onState);
    this.unsub = () => bus.off("stateChanged", onState);
  }

  private registerTempRiseGAs(): void {
    const cfg = getConfig();
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (!w) return;
      const allLogics: Array<WtwZehnderLogic | WtwDucoLogic> = [
        ...(w.wtw.zehnder ? zehnderLogics(w.wtw.zehnder) : []),
        ...(w.wtw.duco ? ducoLogics(w.wtw.duco) : [])
      ];
      for (const logic of allLogics) {
        if (logic.triggerMode === "tempRise" && logic.tempRise) {
          const ga = asGa(logic.tempRise.ga);
          if (ga) this.tempHistory.register(ga, logic.tempRise.windowSec);
        }
      }
    });
  }

  detach(): void {
    this.unsub?.();
    this.unsub = null;
    this.bus = null;
    for (const row of this.boostRestore.values()) clearTimeout(row.timer);
    this.boostRestore.clear();
    for (const run of this.logicRuns.values()) this.clearRunTimers(run);
    this.logicRuns.clear();
    for (const t of this.triggerTimers.values()) clearTimeout(t);
    this.triggerTimers.clear();
    this.triggerHeld.clear();
    this.prev.clear();
    this.tempHistory.clear();
    this.emit();
  }

  onChange(fn: LogicListener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  getAll(): WtwLogicStatus[] {
    const now = Date.now();
    const out: WtwLogicStatus[] = [];
    for (const run of this.logicRuns.values()) {
      const untilMs =
        run.untilMs != null && run.untilMs <= now ? null : run.untilMs;
      out.push({
        deviceId: run.deviceId,
        logicId: run.logicId,
        label: run.label,
        standId: run.standId,
        end: run.end,
        untilMs,
        boostUntilMs:
          run.boostUntilMs != null && run.boostUntilMs > now
            ? run.boostUntilMs
            : null
      });
    }
    return out;
  }

  private emit(): void {
    const all = this.getAll();
    for (const fn of this.listeners) fn(all);
  }

  async pressDuco(
    device: WtwDevice,
    bus: KnxBus,
    cmd: { buttonId: string; on?: boolean }
  ): Promise<void> {
    const d = device.wtw.duco;
    if (!d) throw new Error("Duco-config ontbreekt");
    this.cancelDeviceLogics(device.id);
    await pressDucoStand(d, bus, cmd);
  }

  async press(
    device: WtwDevice,
    bus: KnxBus,
    cmd: { buttonId: string; minutes?: number; on?: boolean }
  ): Promise<void> {
    const z = device.wtw.zehnder;
    if (!z) throw new Error("WTW-config ontbreekt");

    if (cmd.buttonId !== "boost" || cmd.on === false) {
      this.cancelBoostRestore(device.id);
    }
    if (
      cmd.buttonId === "stand1" ||
      cmd.buttonId === "stand2" ||
      cmd.buttonId === "stand3" ||
      cmd.buttonId === "away" ||
      cmd.buttonId === "auto" ||
      cmd.buttonId === "boost"
    ) {
      this.cancelDeviceLogics(device.id);
    }

    const restoreAuto =
      cmd.buttonId === "boost" &&
      cmd.on !== false &&
      zehnderAutoIsOn(bus, z);

    await pressZehnderStand(z, bus, cmd);

    if (restoreAuto) {
      const minutes = cmd.minutes ?? z.minutes ?? 30;
      this.armBoostRestore(device.id, minutes);
      logger.info(
        { deviceId: device.id, minutes },
        "WTW boost vanuit Auto — na afloop terug naar Auto"
      );
    }
  }

  private armBoostRestore(deviceId: string, minutes: number): void {
    this.cancelBoostRestore(deviceId);
    const ms = Math.min(1440, Math.max(1, minutes)) * 60_000 + 1500;
    const timer = setTimeout(() => {
      void this.finishBoostRestore(deviceId, "timer");
    }, ms);
    this.boostRestore.set(deviceId, { deviceId, timer });
  }

  private cancelBoostRestore(deviceId: string): void {
    const row = this.boostRestore.get(deviceId);
    if (!row) return;
    clearTimeout(row.timer);
    this.boostRestore.delete(deviceId);
  }

  private async finishBoostRestore(
    deviceId: string,
    reason: "timer" | "status"
  ): Promise<void> {
    if (!this.boostRestore.has(deviceId)) return;
    this.cancelBoostRestore(deviceId);
    const bus = this.bus;
    const z = this.zehnderOf(deviceId);
    if (!bus || !z) return;
    const ok = await writeZehnderAuto(z, bus, true);
    logger.info({ deviceId, reason, wrote: ok }, "WTW boost klaar — Auto weer aan");
  }

  private logicKey(deviceId: string, logicId: string): string {
    return `${deviceId}:${logicId}`;
  }

  private cancelDeviceLogics(deviceId: string): void {
    for (const [key, run] of [...this.logicRuns]) {
      if (run.deviceId !== deviceId) continue;
      this.logicRuns.delete(key);
      this.clearRunTimers(run);
    }
    for (const [key, t] of [...this.triggerTimers]) {
      if (!key.startsWith(`${deviceId}:`)) continue;
      clearTimeout(t);
      this.triggerTimers.delete(key);
    }
    for (const key of [...this.triggerHeld]) {
      if (key.startsWith(`${deviceId}:`)) this.triggerHeld.delete(key);
    }
    this.emit();
  }

  private clearRunTimers(run: LogicRun): void {
    if (run.untilTimer) clearTimeout(run.untilTimer);
    if (run.durationTimer) clearTimeout(run.durationTimer);
    run.untilTimer = undefined;
    run.durationTimer = undefined;
  }

  private clearTrigger(key: string): void {
    const t = this.triggerTimers.get(key);
    if (t) {
      clearTimeout(t);
      this.triggerTimers.delete(key);
    }
    this.triggerHeld.delete(key);
  }

  private clearLogicTriggers(deviceId: string, logicId: string): void {
    const base = this.logicKey(deviceId, logicId);
    this.clearTrigger(base);
    for (const key of [...this.triggerTimers.keys()]) {
      if (key.startsWith(`${base}:`)) this.clearTrigger(key);
    }
    for (const key of [...this.triggerHeld]) {
      if (key === base || key.startsWith(`${base}:`)) this.triggerHeld.delete(key);
    }
  }

  private clauseKey(deviceId: string, logicId: string, suffix: string): string {
    return `${this.logicKey(deviceId, logicId)}:${suffix}`;
  }

  private allArmsReady(
    bus: KnxBus,
    deviceId: string,
    logicId: string,
    arms: TriggerArm[]
  ): boolean {
    if (arms.length === 0) return false;
    for (const arm of arms) {
      const st = bus.getState(arm.ga);
      if (!st || !valueMatches(st.value, arm.want)) return false;
      if (arm.minutes > 0 && !this.triggerHeld.has(this.clauseKey(deviceId, logicId, arm.suffix))) {
        return false;
      }
    }
    return true;
  }

  private zehnderOf(deviceId: string): WtwZehnderComfoConnect | null {
    const cfg = getConfig();
    let found: WtwZehnderComfoConnect | null = null;
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (w && w.id === deviceId) found = w.wtw.zehnder ?? null;
    });
    return found;
  }

  private logicOf(
    deviceId: string,
    logicId: string
  ): { device: WtwDevice; z: WtwZehnderComfoConnect; logic: WtwZehnderLogic } | null {
    const cfg = getConfig();
    let found: { device: WtwDevice; z: WtwZehnderComfoConnect; logic: WtwZehnderLogic } | null =
      null;
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (!w || w.id !== deviceId || !w.wtw.zehnder) return;
      const logic = zehnderLogics(w.wtw.zehnder).find((l) => l.id === logicId);
      if (logic) found = { device: w, z: w.wtw.zehnder, logic };
    });
    return found;
  }

  private ducoOf(deviceId: string): WtwDucoConnectivityBoard | null {
    const cfg = getConfig();
    let found: WtwDucoConnectivityBoard | null = null;
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (w && w.id === deviceId) found = w.wtw.duco ?? null;
    });
    return found;
  }

  private ducoLogicOf(
    deviceId: string,
    logicId: string
  ): { device: WtwDevice; duco: WtwDucoConnectivityBoard; logic: WtwDucoLogic } | null {
    const cfg = getConfig();
    let found: { device: WtwDevice; duco: WtwDucoConnectivityBoard; logic: WtwDucoLogic } | null =
      null;
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (!w || w.id !== deviceId || !w.wtw.duco) return;
      const logic = ducoLogics(w.wtw.duco).find((l) => l.id === logicId);
      if (logic) found = { device: w, duco: w.wtw.duco, logic };
    });
    return found;
  }

  private onBusState(state: GAState): void {
    const prev = this.prev.get(state.ga);
    this.prev.set(state.ga, state.value);
    const cfg = getConfig();
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (!w) return;
      if (w.wtw.zehnder) {
        this.onBoostStatus(w.id, w.wtw.zehnder, state, prev);
        this.onLogicTelegram(w, w.wtw.zehnder, state, prev);
      }
      if (w.wtw.duco) {
        this.onDucoLogicTelegram(w, w.wtw.duco, state, prev);
      }
    });
  }

  private onBoostStatus(
    deviceId: string,
    z: WtwZehnderComfoConnect,
    state: GAState,
    prev: unknown
  ): void {
    const ga = asGa(z.boostStatusGa);
    if (!ga || state.ga !== ga) return;
    if (!this.boostRestore.has(deviceId)) return;
    if (prev === undefined) return;
    if (bitOn(prev) && !bitOn(state.value)) {
      void this.finishBoostRestore(deviceId, "status");
    }
  }

  private onLogicTelegram(
    device: WtwDevice,
    z: WtwZehnderComfoConnect,
    state: GAState,
    prev: unknown
  ): void {
    const bus = this.bus;
    if (!bus) return;
    // Feed temperature history for any GA that has a tempRise config.
    if (typeof state.value === "number") {
      this.tempHistory.push(state.ga, state.value);
    }
    for (const logic of zehnderLogics(z)) {
      if (!logicEnabled(logic) || !logic.id) continue;
      if (logic.triggerMode === "tempRise") {
        this.tickTempRise(device, z, logic, state);
      } else {
        for (const arm of whenArms(logic)) {
          if (state.ga === arm.ga) {
            this.tickTrigger(device, z, logic, arm, state.value, prev);
          }
        }
      }
      if (logic.end === "untilStatus") {
        for (const arm of untilArms(logic)) {
          if (state.ga === arm.ga) {
            this.tickUntil(device.id, logic, arm, state.value);
          }
        }
      }
    }
  }

  private tickTempRise(
    device: WtwDevice,
    z: WtwZehnderComfoConnect,
    logic: WtwZehnderLogic,
    state: GAState
  ): void {
    const tr = logic.tempRise;
    if (!tr) return;
    const ga = asGa(tr.ga);
    if (!ga || state.ga !== ga) return;
    const runKey = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(runKey)) return;
    const current = typeof state.value === "number" ? state.value : null;
    if (current === null) return;
    const minVal = this.tempHistory.minInWindow(ga, tr.windowSec);
    if (minVal === null) return;
    const delta = current - minVal;
    if (delta >= tr.deltaDeg) {
      const live = this.logicOf(device.id, logic.id);
      if (!live || !logicEnabled(live.logic)) return;
      logger.info(
        {
          deviceId: device.id,
          logicId: logic.id,
          ga,
          delta: Math.round(delta * 10) / 10,
          deltaDeg: tr.deltaDeg,
          windowSec: tr.windowSec,
          current,
          minVal
        },
        "WTW tempRise trigger"
      );
      void this.startLogic(live.device, live.z, live.logic);
    }
  }

  /* ===== Duco logic handlers ========================================= */

  private onDucoLogicTelegram(
    device: WtwDevice,
    duco: WtwDucoConnectivityBoard,
    state: GAState,
    prev: unknown
  ): void {
    const bus = this.bus;
    if (!bus) return;
    if (typeof state.value === "number") {
      this.tempHistory.push(state.ga, state.value);
    }
    for (const logic of ducoLogics(duco)) {
      if (!logicEnabled(logic) || !logic.id) continue;
      if (logic.triggerMode === "tempRise") {
        this.tickDucoTempRise(device, duco, logic, state);
      } else {
        for (const arm of whenArms(logic)) {
          if (state.ga === arm.ga) {
            this.tickDucoTrigger(device, duco, logic, arm, state.value, prev);
          }
        }
      }
      if (logic.end === "untilStatus") {
        for (const arm of untilArms(logic)) {
          if (state.ga === arm.ga) {
            this.tickDucoUntil(device.id, logic, arm, state.value);
          }
        }
      }
    }
  }

  private tickDucoTempRise(
    device: WtwDevice,
    duco: WtwDucoConnectivityBoard,
    logic: WtwDucoLogic,
    state: GAState
  ): void {
    const tr = logic.tempRise;
    if (!tr) return;
    const ga = asGa(tr.ga);
    if (!ga || state.ga !== ga) return;
    const runKey = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(runKey)) return;
    const current = typeof state.value === "number" ? state.value : null;
    if (current === null) return;
    const minVal = this.tempHistory.minInWindow(ga, tr.windowSec);
    if (minVal === null) return;
    const delta = current - minVal;
    if (delta >= tr.deltaDeg) {
      const live = this.ducoLogicOf(device.id, logic.id);
      if (!live || !logicEnabled(live.logic)) return;
      logger.info(
        { deviceId: device.id, logicId: logic.id, delta: Math.round(delta * 10) / 10 },
        "Duco tempRise trigger"
      );
      void this.startDucoLogic(live.device, live.duco, live.logic);
    }
  }

  private tickDucoTrigger(
    device: WtwDevice,
    duco: WtwDucoConnectivityBoard,
    logic: WtwDucoLogic,
    arm: TriggerArm,
    value: unknown,
    prev: unknown
  ): void {
    const runKey = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(runKey)) return;
    const timerKey = this.clauseKey(device.id, logic.id, arm.suffix);
    const join = joinOf(logic.whenJoin);
    if (!valueMatches(value, arm.want)) {
      this.clearTrigger(timerKey);
      return;
    }
    const fire = (): void => {
      const live = this.ducoLogicOf(device.id, logic.id);
      if (!live || !logicEnabled(live.logic)) return;
      const bus = this.bus;
      if (!bus) return;
      const arms = whenArms(live.logic);
      if (joinOf(live.logic.whenJoin) === "and") {
        if (this.allArmsReady(bus, device.id, logic.id, arms)) {
          void this.startDucoLogic(live.device, live.duco, live.logic);
        }
        return;
      }
      void this.startDucoLogic(live.device, live.duco, live.logic);
    };
    if (arm.minutes <= 0) {
      const rising = prev !== undefined && !valueMatches(prev, arm.want);
      if (join === "or") {
        if (rising) fire();
        return;
      }
      if (rising || prev === undefined) fire();
      return;
    }
    if (this.triggerTimers.has(timerKey) || this.triggerHeld.has(timerKey)) return;
    this.triggerTimers.set(
      timerKey,
      setTimeout(() => {
        this.triggerTimers.delete(timerKey);
        const bus = this.bus;
        if (!bus) return;
        const st = bus.getState(arm.ga);
        if (!st || !valueMatches(st.value, arm.want)) return;
        this.triggerHeld.add(timerKey);
        fire();
      }, arm.minutes * 60_000)
    );
  }

  private tickDucoUntil(
    deviceId: string,
    logic: WtwDucoLogic,
    arm: TriggerArm,
    value: unknown
  ): void {
    const key = this.logicKey(deviceId, logic.id);
    const run = this.logicRuns.get(key);
    if (!run) return;
    const timerKey = this.clauseKey(deviceId, logic.id, arm.suffix);
    const join = joinOf(logic.untilJoin);
    if (!valueMatches(value, arm.want)) {
      this.clearTrigger(timerKey);
      if (run.untilTimer && join === "and") {
        clearTimeout(run.untilTimer);
        run.untilTimer = undefined;
        run.untilMs = null;
        this.emit();
      }
      return;
    }
    const maybeEnd = (): void => {
      const live = this.ducoLogicOf(deviceId, logic.id);
      if (!live) return;
      const bus = this.bus;
      if (!bus) return;
      const arms = untilArms(live.logic);
      if (joinOf(live.logic.untilJoin) === "and") {
        if (!this.allArmsReady(bus, deviceId, logic.id, arms)) return;
      }
      void this.endDucoLogic(deviceId, logic.id, "until");
    };
    if (arm.minutes <= 0) {
      maybeEnd();
      return;
    }
    if (this.triggerTimers.has(timerKey) || this.triggerHeld.has(timerKey)) return;
    const untilMs = Date.now() + arm.minutes * 60_000;
    if (join === "or" || run.untilMs == null || untilMs < run.untilMs) {
      run.untilMs = untilMs;
    }
    this.triggerTimers.set(
      timerKey,
      setTimeout(() => {
        this.triggerTimers.delete(timerKey);
        const bus = this.bus;
        if (!bus) return;
        const st = bus.getState(arm.ga);
        if (!st || !valueMatches(st.value, arm.want)) return;
        this.triggerHeld.add(timerKey);
        maybeEnd();
      }, arm.minutes * 60_000)
    );
    this.emit();
  }

  private async startDucoLogic(
    device: WtwDevice,
    duco: WtwDucoConnectivityBoard,
    logic: WtwDucoLogic
  ): Promise<void> {
    const bus = this.bus;
    if (!bus) return;
    const stand = logic.standId;
    if (!stand) return;
    const key = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(key)) return;
    this.clearLogicTriggers(device.id, logic.id);

    const restoreStand = readDucoActiveStand(bus, duco) as string;
    const minutes = clampInt(logic.minutes, 15, 1, 1440);
    const end = logic.end === "untilStatus" ? "untilStatus" : "duration";

    try {
      await pressDucoStand(duco, bus, { buttonId: stand });
    } catch (err) {
      logger.warn({ err, deviceId: device.id, logicId: logic.id }, "Duco-logica stand mislukt");
      return;
    }

    const run: LogicRun = {
      deviceId: device.id,
      logicId: logic.id,
      label: (logic.label ?? "").trim(),
      standId: stand,
      end,
      restoreStand: restoreStand as WtwZehnderStandId,
      after: logic.after ?? "previous",
      restoreBoostMinutes: null,
      untilMs: null,
      boostUntilMs: null
    };
    this.logicRuns.set(key, run);
    if (end !== "untilStatus") {
      run.untilMs = Date.now() + minutes * 60_000;
      run.durationTimer = setTimeout(() => {
        void this.endDucoLogic(device.id, logic.id, "duration");
      }, minutes * 60_000);
    } else {
      for (const arm of untilArms(logic)) {
        const st = bus.getState(arm.ga);
        if (st) this.tickDucoUntil(device.id, logic, arm, st.value);
      }
    }
    this.emit();
    logger.info(
      { deviceId: device.id, logicId: logic.id, stand, end, restoreStand, minutes },
      "Duco-logica gestart"
    );
  }

  private async endDucoLogic(
    deviceId: string,
    logicId: string,
    reason: "duration" | "until"
  ): Promise<void> {
    const key = this.logicKey(deviceId, logicId);
    const run = this.logicRuns.get(key);
    if (!run) return;
    this.logicRuns.delete(key);
    this.clearRunTimers(run);
    this.clearLogicTriggers(deviceId, logicId);
    this.emit();
    const others = [...this.logicRuns.values()].some((r) => r.deviceId === deviceId);
    if (others) {
      logger.info({ deviceId, logicId, reason }, "Duco-logica klaar; andere logica nog actief");
      return;
    }
    const bus = this.bus;
    const duco = this.ducoOf(deviceId);
    if (!bus || !duco) return;
    const target = run.after === "previous" || !run.after ? run.restoreStand : run.after;
    try {
      await pressDucoStand(duco, bus, { buttonId: target });
      logger.info({ deviceId, logicId, reason, target }, "Duco-logica klaar — terug naar stand");
    } catch (err) {
      logger.warn({ err, deviceId, logicId, target }, "Duco-logica terugzetten mislukt");
    }
  }

  /* ===== Zehnder logic handlers ====================================== */

  private tickTrigger(
    device: WtwDevice,
    z: WtwZehnderComfoConnect,
    logic: WtwZehnderLogic,
    arm: TriggerArm,
    value: unknown,
    prev: unknown
  ): void {
    const runKey = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(runKey)) return;
    const timerKey = this.clauseKey(device.id, logic.id, arm.suffix);
    const join = joinOf(logic.whenJoin);
    if (!valueMatches(value, arm.want)) {
      this.clearTrigger(timerKey);
      return;
    }
    const fire = (): void => {
      const live = this.logicOf(device.id, logic.id);
      if (!live || !logicEnabled(live.logic)) return;
      const bus = this.bus;
      if (!bus) return;
      const arms = whenArms(live.logic);
      if (joinOf(live.logic.whenJoin) === "and") {
        if (this.allArmsReady(bus, device.id, logic.id, arms)) {
          void this.startLogic(live.device, live.z, live.logic);
        }
        return;
      }
      void this.startLogic(live.device, live.z, live.logic);
    };
    if (arm.minutes <= 0) {
      const rising = prev !== undefined && !valueMatches(prev, arm.want);
      if (join === "or") {
        if (rising) fire();
        return;
      }
      if (rising || prev === undefined) fire();
      return;
    }
    if (this.triggerTimers.has(timerKey) || this.triggerHeld.has(timerKey)) return;
    this.triggerTimers.set(
      timerKey,
      setTimeout(() => {
        this.triggerTimers.delete(timerKey);
        const bus = this.bus;
        if (!bus) return;
        const st = bus.getState(arm.ga);
        if (!st || !valueMatches(st.value, arm.want)) return;
        this.triggerHeld.add(timerKey);
        fire();
      }, arm.minutes * 60_000)
    );
  }

  private tickUntil(
    deviceId: string,
    logic: WtwZehnderLogic,
    arm: TriggerArm,
    value: unknown
  ): void {
    const key = this.logicKey(deviceId, logic.id);
    const run = this.logicRuns.get(key);
    if (!run) return;
    const timerKey = this.clauseKey(deviceId, logic.id, arm.suffix);
    const join = joinOf(logic.untilJoin);
    if (!valueMatches(value, arm.want)) {
      this.clearTrigger(timerKey);
      if (run.untilTimer && join === "and") {
        clearTimeout(run.untilTimer);
        run.untilTimer = undefined;
        run.untilMs = null;
        this.emit();
      }
      return;
    }
    const maybeEnd = (): void => {
      const live = this.logicOf(deviceId, logic.id);
      if (!live) return;
      const bus = this.bus;
      if (!bus) return;
      const arms = untilArms(live.logic);
      if (joinOf(live.logic.untilJoin) === "and") {
        if (!this.allArmsReady(bus, deviceId, logic.id, arms)) return;
      }
      void this.endLogic(deviceId, logic.id, "until");
    };
    if (arm.minutes <= 0) {
      maybeEnd();
      return;
    }
    if (this.triggerTimers.has(timerKey) || this.triggerHeld.has(timerKey)) return;
    const untilMs = Date.now() + arm.minutes * 60_000;
    if (join === "or" || run.untilMs == null || untilMs < run.untilMs) {
      run.untilMs = untilMs;
    }
    this.triggerTimers.set(
      timerKey,
      setTimeout(() => {
        this.triggerTimers.delete(timerKey);
        const bus = this.bus;
        if (!bus) return;
        const st = bus.getState(arm.ga);
        if (!st || !valueMatches(st.value, arm.want)) return;
        this.triggerHeld.add(timerKey);
        maybeEnd();
      }, arm.minutes * 60_000)
    );
    this.emit();
  }

  private async startLogic(
    device: WtwDevice,
    z: WtwZehnderComfoConnect,
    logic: WtwZehnderLogic
  ): Promise<void> {
    const bus = this.bus;
    if (!bus) return;
    const stand = logic.standId;
    if (!stand) return;
    const key = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(key)) return;
    this.clearLogicTriggers(device.id, logic.id);

    const restoreStand = readZehnderActiveStand(bus, z);
    const minutes = clampInt(logic.minutes, 15, 1, 1440);
    const end = logic.end === "untilStatus" ? "untilStatus" : "duration";
    const cmd: { buttonId: WtwZehnderStandId; minutes?: number; on?: boolean } = {
      buttonId: stand,
      on: true
    };
    let restoreBoostMinutes: number | null = null;
    let boostUntilMs: number | null = null;
    if (stand === "boost") {
      restoreBoostMinutes = readBoostMinutes(bus, z);
      cmd.minutes = end === "untilStatus" ? 180 : minutes;
      boostUntilMs = Date.now() + cmd.minutes * 60_000;
      if (!asGa(z.boostTimeGa)) {
        logger.warn(
          { deviceId: device.id, logicId: logic.id },
          "WTW-logica boost zonder boostTimeGa — toestel gebruikt de laatst gezette tijd"
        );
      }
    }

    try {
      await pressZehnderStand(z, bus, cmd);
    } catch (err) {
      logger.warn({ err, deviceId: device.id, logicId: logic.id }, "WTW-logica stand mislukt");
      return;
    }

    const run: LogicRun = {
      deviceId: device.id,
      logicId: logic.id,
      label: (logic.label ?? "").trim(),
      standId: stand,
      end,
      restoreStand,
      after: logic.after ?? "previous",
      restoreBoostMinutes,
      untilMs: null,
      boostUntilMs
    };
    this.logicRuns.set(key, run);
    if (end !== "untilStatus") {
      run.untilMs = Date.now() + minutes * 60_000;
      run.durationTimer = setTimeout(() => {
        void this.endLogic(device.id, logic.id, "duration");
      }, minutes * 60_000);
    } else {
      for (const arm of untilArms(logic)) {
        const st = bus.getState(arm.ga);
        if (st) this.tickUntil(device.id, logic, arm, st.value);
      }
    }
    this.emit();
    logger.info(
      {
        deviceId: device.id,
        logicId: logic.id,
        stand,
        end,
        after: run.after,
        restoreStand,
        minutes
      },
      "WTW-logica gestart"
    );
  }

  private async endLogic(
    deviceId: string,
    logicId: string,
    reason: "duration" | "until"
  ): Promise<void> {
    const key = this.logicKey(deviceId, logicId);
    const run = this.logicRuns.get(key);
    if (!run) return;
    this.logicRuns.delete(key);
    this.clearRunTimers(run);
    this.clearLogicTriggers(deviceId, logicId);
    this.emit();
    const others = [...this.logicRuns.values()].some((r) => r.deviceId === deviceId);
    if (others) {
      logger.info({ deviceId, logicId, reason }, "WTW-logica klaar; andere logica nog actief");
      return;
    }
    const bus = this.bus;
    const z = this.zehnderOf(deviceId);
    if (!bus || !z) return;
    const target =
      run.after === "previous" || !run.after ? run.restoreStand : run.after;
    try {
      await pressZehnderStand(z, bus, {
        buttonId: target,
        on: true,
        minutes: target === "boost" ? run.restoreBoostMinutes ?? undefined : undefined
      });
      if (run.restoreBoostMinutes != null && target !== "boost") {
        await writeBoostMinutes(z, bus, run.restoreBoostMinutes);
      }
      logger.info(
        { deviceId, logicId, reason, target },
        "WTW-logica klaar — terug naar stand"
      );
    } catch (err) {
      logger.warn({ err, deviceId, logicId, target }, "WTW-logica terugzetten mislukt");
    }
  }
}

export const wtwRuntime = new WtwRuntime();

export function attachWtwRuntime(bus: KnxBus): void {
  wtwRuntime.attach(bus);
}
