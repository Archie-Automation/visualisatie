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
  restoreAuto: boolean;
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

function clampMinutes(n: unknown, fallback: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.min(1440, Math.max(1, Math.round(v)));
}

class WtwRuntime {
  private bus: KnxBus | null = null;
  private unsub: (() => void) | null = null;
  private prev = new Map<string, unknown>();
  private boostRestore = new Map<string, BoostRestore>();
  private logicRuns = new Map<string, LogicRun>();
  private logicRestoreAuto = new Set<string>();
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
    this.prev.clear();
    this.logicRestoreAuto.clear();
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
      this.cancelDeviceLogics(device.id, { restore: false });
      this.logicRestoreAuto.delete(device.id);
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

  private cancelDeviceLogics(
    deviceId: string,
    opts: { restore: boolean }
  ): void {
    for (const [key, run] of [...this.logicRuns]) {
      if (run.deviceId !== deviceId) continue;
      this.logicRuns.delete(key);
      this.clearRunTimers(run);
      if (opts.restore && run.restoreAuto) {
        const bus = this.bus;
        const z = this.zehnderOf(deviceId);
        if (bus && z) void writeZehnderAuto(z, bus, true);
      }
    }
    this.emit();
  }

  private clearRunTimers(run: LogicRun): void {
    if (run.untilTimer) clearTimeout(run.untilTimer);
    if (run.durationTimer) clearTimeout(run.durationTimer);
    run.untilTimer = undefined;
    run.durationTimer = undefined;
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
        const want = logic.triggerEquals !== false;
        if (prev !== undefined && !valueIs(prev, want) && valueIs(state.value, want)) {
          void this.startLogic(device, z, logic);
        }
        if (logic.end === "untilStatus") {
          const untilGa = asGa(logic.untilGa) ?? triggerGa;
          if (untilGa === triggerGa) this.tickUntilHold(device.id, logic, state.value);
        }
      } else if (logic.end === "untilStatus") {
        const untilGa = asGa(logic.untilGa);
        if (untilGa && state.ga === untilGa) {
          this.tickUntilHold(device.id, logic, state.value);
        }
      }
    }
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
      const minutes = clampMinutes(logic.minutes, 5);
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
    if (zehnderAutoIsOn(bus, z)) this.logicRestoreAuto.add(device.id);
    const restoreAuto = this.logicRestoreAuto.has(device.id);
    const key = this.logicKey(device.id, logic.id);
    const existing = this.logicRuns.get(key);
    if (existing) this.clearRunTimers(existing);

    const minutes = clampMinutes(logic.minutes, 15);
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
      restoreAuto,
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
        end: logic.end ?? "duration",
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
    const restoreAuto = this.logicRestoreAuto.has(deviceId) || run.restoreAuto;
    this.logicRestoreAuto.delete(deviceId);
    if (!restoreAuto) {
      logger.info({ deviceId, logicId, reason }, "WTW-logica klaar");
      return;
    }
    const bus = this.bus;
    const z = this.zehnderOf(deviceId);
    if (!bus || !z) return;
    await writeZehnderAuto(z, bus, true);
    logger.info({ deviceId, logicId, reason }, "WTW-logica klaar — Auto weer aan");
  }
}

export const wtwRuntime = new WtwRuntime();

export function attachWtwRuntime(bus: KnxBus): void {
  wtwRuntime.attach(bus);
}
