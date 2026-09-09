import { getConfig, walkDevices } from "./config";
import type { KnxBus } from "./knxBus";
import { logger } from "./logger";
import type {
  Device,
  GAState,
  WtwDevice,
  WtwZehnderComfoConnect,
  WtwZehnderLogic,
  WtwZehnderStandId
} from "./types";
import {
  asGa,
  bitOn,
  pressZehnderStand,
  readZehnderActiveStand,
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
  untilMs: number | null;
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

function valueIs(actual: unknown, wantOn: boolean): boolean {
  return wantOn ? bitOn(actual) : !bitOn(actual);
}

function clampInt(n: unknown, fallback: number, min: number, max: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.min(max, Math.max(min, Math.round(v)));
}

class WtwRuntime {
  private bus: KnxBus | null = null;
  private unsub: (() => void) | null = null;
  private prev = new Map<string, unknown>();
  private boostRestore = new Map<string, BoostRestore>();
  private logicRuns = new Map<string, LogicRun>();
  private triggerTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private listeners = new Set<LogicListener>();

  attach(bus: KnxBus): void {
    this.detach();
    this.bus = bus;
    const onState = (state: GAState) => this.onBusState(state);
    bus.on("stateChanged", onState);
    this.unsub = () => bus.off("stateChanged", onState);
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
    this.prev.clear();
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
        untilMs
      });
    }
    return out;
  }

  private emit(): void {
    const all = this.getAll();
    for (const fn of this.listeners) fn(all);
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
    if (!t) return;
    clearTimeout(t);
    this.triggerTimers.delete(key);
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

  private onBusState(state: GAState): void {
    const prev = this.prev.get(state.ga);
    this.prev.set(state.ga, state.value);
    const cfg = getConfig();
    walkDevices(cfg, (d) => {
      const w = asWtw(d);
      if (!w?.wtw.zehnder) return;
      const z = w.wtw.zehnder;
      this.onBoostStatus(w.id, z, state, prev);
      this.onLogicTelegram(w, z, state, prev);
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
    for (const logic of zehnderLogics(z)) {
      if (!logicEnabled(logic) || !logic.id) continue;
      const triggerGa = asGa(logic.triggerGa);
      if (triggerGa && state.ga === triggerGa) {
        this.tickTrigger(device, z, logic, state.value, prev);
      }
      if (logic.end === "untilStatus") {
        const untilGa = asGa(logic.untilGa) ?? triggerGa;
        if (untilGa && state.ga === untilGa) {
          this.tickUntilHold(device.id, logic, state.value);
        }
      }
    }
  }

  private tickTrigger(
    device: WtwDevice,
    z: WtwZehnderComfoConnect,
    logic: WtwZehnderLogic,
    value: unknown,
    prev: unknown
  ): void {
    const key = this.logicKey(device.id, logic.id);
    if (this.logicRuns.has(key)) return;
    const want = logic.triggerEquals !== false;
    if (!valueIs(value, want)) {
      this.clearTrigger(key);
      return;
    }
    const holdMin = clampInt(logic.triggerMinutes, 0, 0, 1440);
    if (holdMin <= 0) {
      if (prev !== undefined && !valueIs(prev, want)) {
        void this.startLogic(device, z, logic);
      }
      return;
    }
    if (this.triggerTimers.has(key)) return;
    this.triggerTimers.set(
      key,
      setTimeout(() => {
        this.triggerTimers.delete(key);
        const live = this.logicOf(device.id, logic.id);
        if (!live || !logicEnabled(live.logic)) return;
        const bus = this.bus;
        const ga = asGa(live.logic.triggerGa);
        if (!bus || !ga) return;
        const st = bus.getState(ga);
        if (!st || !valueIs(st.value, live.logic.triggerEquals !== false)) return;
        void this.startLogic(live.device, live.z, live.logic);
      }, holdMin * 60_000)
    );
  }

  private tickUntilHold(
    deviceId: string,
    logic: WtwZehnderLogic,
    value: unknown
  ): void {
    const key = this.logicKey(deviceId, logic.id);
    const run = this.logicRuns.get(key);
    if (!run) return;
    const want = logic.untilEquals === true;
    if (valueIs(value, want)) {
      if (run.untilTimer) return;
      const minutes = clampInt(logic.untilMinutes ?? logic.minutes, 5, 1, 1440);
      run.untilMs = Date.now() + minutes * 60_000;
      run.untilTimer = setTimeout(() => {
        void this.endLogic(deviceId, logic.id, "until");
      }, minutes * 60_000);
      this.emit();
    } else if (run.untilTimer) {
      clearTimeout(run.untilTimer);
      run.untilTimer = undefined;
      run.untilMs = null;
      this.emit();
    }
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
    this.clearTrigger(key);

    const restoreStand = readZehnderActiveStand(bus, z);
    const minutes = clampInt(logic.minutes, 15, 1, 1440);
    const cmd: { buttonId: WtwZehnderStandId; minutes?: number; on?: boolean } = {
      buttonId: stand,
      on: true
    };
    if (stand === "boost") cmd.minutes = minutes;

    try {
      await pressZehnderStand(z, bus, cmd);
    } catch (err) {
      logger.warn({ err, deviceId: device.id, logicId: logic.id }, "WTW-logica stand mislukt");
      return;
    }

    const end = logic.end === "untilStatus" ? "untilStatus" : "duration";
    const run: LogicRun = {
      deviceId: device.id,
      logicId: logic.id,
      label: (logic.label ?? "").trim(),
      standId: stand,
      end,
      restoreStand,
      after: logic.after ?? "previous",
      untilMs: null
    };
    this.logicRuns.set(key, run);
    if (end !== "untilStatus") {
      run.untilMs = Date.now() + minutes * 60_000;
      run.durationTimer = setTimeout(() => {
        void this.endLogic(device.id, logic.id, "duration");
      }, minutes * 60_000);
    } else {
      const untilGa = asGa(logic.untilGa) ?? asGa(logic.triggerGa);
      if (untilGa) {
        const st = bus.getState(untilGa);
        if (st) this.tickUntilHold(device.id, logic, st.value);
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
        on: true
      });
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
