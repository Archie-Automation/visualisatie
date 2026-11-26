import { logger } from "../logger";
import type { KnxBus } from "../knxBus";
import { encodeSceneByte } from "../knxScene";
import type { LutronButtonFunction, LutronKnxBinding, Rgb232Triplet } from "../types";

const ALLOWED_ROLES = new Set([
  "switch",
  "dim_value",
  "byte",
  "percent",
  "temperature",
  "bit",
  "rgb232",
  "raw_bytes",
  "scene",
  "scene_number",
  "setpoint",
  "position",
  "dim_control",
  "up_down",
  "stop_step"
]);

export type PlannedLutronWrite =
  | { kind: "once"; value: number | boolean }
  | { kind: "pulse"; on: number | boolean; off: number | boolean; ms: number }
  | { kind: "scene"; byte: number }
  | { kind: "dim"; increase: boolean; step: number }
  | { kind: "shadeStop"; ga: string };

/** Indrukken start, loslaten stopt. Geldt voor 4-bit dimmen en zonwering op/neer. */
export function lutronKnxIsHold(knx: LutronKnxBinding): boolean {
  return knx.role === "dim_control" || knx.role === "up_down";
}

export type LutronGesture = Exclude<LutronButtonFunction, "moment">;

const GESTURES = new Set<string>(["dim_1", "dim_2", "shade_1", "shade_2"]);

/** Tastfunctie die korte druk, vasthouden en loslaten zelf afhandelt, of null bij één moment. */
export function lutronGesture(map: { function?: string }): LutronGesture | null {
  const fn = map.function;
  return fn && GESTURES.has(fn) ? (fn as LutronGesture) : null;
}

/** Actienummers: 3 = indrukken, 4 = loslaten. */
export function lutronMappingHandles(
  map: { actionNumber?: number; function?: string; knx: LutronKnxBinding },
  action: number
): boolean {
  if (lutronGesture(map)) return action === 3 || action === 4 || action === 5;
  if (lutronKnxIsHold(map.knx)) return action === 3 || action === 4;
  if (map.actionNumber != null && map.actionNumber !== action) return false;
  return true;
}

export type LutronButtonPhase = "press" | "release";

/** Oude koppelingen zonder `send` maar mét pulsduur op een bit blijven een puls. */
export function lutronSendMode(knx: LutronKnxBinding): "value" | "toggle" | "pulse" | "hold" {
  if (lutronKnxIsHold(knx)) return "hold";
  if (knx.send === "value" || knx.send === "toggle" || knx.send === "pulse") return knx.send;
  const pulseBit =
    knx.pulseMs != null &&
    knx.pulseMs > 0 &&
    (knx.role === "switch" || knx.role === "bit");
  return pulseBit ? "pulse" : "value";
}

export function planLutronKnxWrite(knx: LutronKnxBinding, current: unknown): PlannedLutronWrite {
  if (knx.role === "scene") {
    const n = Math.min(64, Math.max(1, Math.round(Number(knx.value) || 1)));
    return { kind: "scene", byte: encodeSceneByte(n, false) };
  }
  const on = coerceScalar(knx.role, knx.value);
  const mode = lutronSendMode(knx);
  if (mode === "pulse") {
    const off = typeof on === "boolean" ? !on : 0;
    return {
      kind: "pulse",
      on,
      off: coerceScalar(knx.role, off),
      ms: Math.min(3000, Math.max(50, knx.pulseMs ?? 250))
    };
  }
  if (mode === "toggle") {
    const off =
      knx.valueOff == null
        ? coerceScalar(knx.role, typeof on === "boolean" ? !on : 0)
        : coerceScalar(knx.role, knx.valueOff);
    return { kind: "once", value: sameKnxValue(current, on) ? off : on };
  }
  return { kind: "once", value: on };
}

/**
 * 4-bit dimmen: stapcode 1 is het hele bereik, de actor loopt tot het break-telegram.
 * Zonwering: DPT 1.008 op indrukken (0 = omhoog), DPT 1.007 stop op loslaten.
 */
export function planLutronHold(knx: LutronKnxBinding): {
  start: PlannedLutronWrite;
  stop: PlannedLutronWrite;
} {
  if (knx.role === "dim_control") {
    const increase = knx.value === true || knx.value === 1;
    return {
      start: { kind: "dim", increase, step: 1 },
      stop: { kind: "dim", increase: false, step: 0 }
    };
  }
  if (knx.role === "up_down") {
    const down = knx.value === true || knx.value === 1;
    const stopGa = knx.stopGa?.trim() ?? "";
    if (!stopGa) throw new Error("zonwering vasthouden vereist een stop-groepsadres");
    return {
      start: { kind: "once", value: down },
      stop: { kind: "shadeStop", ga: stopGa }
    };
  }
  throw new Error("vasthouden is alleen voor dimmen of zonwering");
}

/** Per koppeling: dimt of loopt er iets, en welke richting was de laatste. */
export type LutronGestureState = { active?: boolean; lastUp?: boolean };

export type LutronGestureWrite =
  | { kind: "switch"; ga: string; value: boolean }
  | { kind: "dim"; ga: string; increase: boolean; step: number }
  | { kind: "move"; ga: string; down: boolean }
  | { kind: "stop"; ga: string; down: boolean };

/**
 * Telegrammen voor een tastfunctie. 3 = korte druk (pas na loslaten, de
 * detector wacht bij deze knoppen), 5 = vasthouden, 4 = loslaten.
 * `switchedOn` is de status van de lamp; onbekend = undefined.
 */
export function planLutronGesture(
  fn: LutronGesture,
  knx: LutronKnxBinding,
  action: number,
  state: LutronGestureState,
  switchedOn: boolean | undefined
): LutronGestureWrite[] {
  const ga = knx.ga?.trim() ?? "";
  const fixedUp = fn === "shade_2" ? !(knx.value === true || knx.value === 1) : knx.value === true || knx.value === 1;

  if (fn === "dim_1" || fn === "dim_2") {
    const dimGa = knx.dimGa?.trim() ?? "";
    if (action === 3) {
      const on = fn === "dim_1" ? !(switchedOn ?? false) : fixedUp;
      state.lastUp = on;
      return ga ? [{ kind: "switch", ga, value: on }] : [];
    }
    if (action === 5) {
      const up =
        fn === "dim_2" ? fixedUp : switchedOn === false ? true : state.lastUp === undefined ? false : !state.lastUp;
      state.lastUp = up;
      state.active = true;
      return dimGa ? [{ kind: "dim", ga: dimGa, increase: up, step: 1 }] : [];
    }
    if (action === 4 && state.active) {
      state.active = false;
      return dimGa ? [{ kind: "dim", ga: dimGa, increase: state.lastUp ?? false, step: 0 }] : [];
    }
    return [];
  }

  const stopGa = knx.stopGa?.trim() ?? "";
  if (action === 5) {
    const up = fn === "shade_2" ? fixedUp : state.lastUp === undefined ? false : !state.lastUp;
    state.lastUp = up;
    return ga ? [{ kind: "move", ga, down: !up }] : [];
  }
  if (action === 3) {
    const down = fn === "shade_2" ? !fixedUp : !(state.lastUp ?? true);
    return stopGa ? [{ kind: "stop", ga: stopGa, down }] : [];
  }
  return [];
}

export function describeLutronGestureWrite(w: LutronGestureWrite): string {
  switch (w.kind) {
    case "switch":
      return `${w.ga} ${w.value ? "aan" : "uit"}`;
    case "dim":
      return w.step === 0 ? `${w.ga} dimmen stop` : `${w.ga} ${w.increase ? "helderder" : "donkerder"}`;
    case "move":
      return `${w.ga} ${w.down ? "neer" : "op"}`;
    case "stop":
      return `${w.ga} stop/lamel`;
  }
}

export async function executeLutronGestureWrite(bus: KnxBus, w: LutronGestureWrite): Promise<void> {
  switch (w.kind) {
    case "switch":
      await bus.write(w.ga, "switch", w.value);
      return;
    case "dim":
      await bus.writeDimControl(w.ga, w.increase, w.step);
      return;
    case "move":
      await bus.write(w.ga, "up_down", w.down);
      return;
    case "stop":
      await bus.write(w.ga, "stop_step", w.down);
      return;
  }
}

/** Status van een lamp als aan/uit; onbekend = undefined. */
export function knxSwitchedOn(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value > 0;
  return undefined;
}

function sameKnxValue(current: unknown, expected: number | boolean): boolean {
  if (typeof expected === "boolean") {
    return current === expected || current === (expected ? 1 : 0);
  }
  if (current === expected) return true;
  if (expected === 0 && current === false) return true;
  if (expected === 1 && current === true) return true;
  return typeof current === "number" && Math.abs(current - expected) < 0.05;
}

function clampByte(n: number): number {
  return Math.max(0, Math.min(255, Math.round(n)));
}

/**
 * Voert één KNX-schrijf uit zoals geconfigureerd bij een Lutron→KNX mapping.
 * Rollen zijn beperkt tot gangbare bus-rollen (zelfde als universeel/scenes).
 */
export async function executeLutronToKnx(
  bus: KnxBus,
  knx: LutronKnxBinding,
  phase?: LutronButtonPhase
): Promise<void> {
  const role = knx.role;
  if (!ALLOWED_ROLES.has(role)) {
    throw new Error(`KNX-rol niet toegestaan vanuit Lutron: ${role}`);
  }

  if (role === "raw_bytes") {
    if (!Array.isArray(knx.value)) throw new Error("raw_bytes vereist number[]");
    const buf = Buffer.from(knx.value.map((x) => clampByte(Number(x))));
    await bus.writeRaw(knx.ga, buf, buf.length * 8);
    return;
  }

  if (role === "rgb232") {
    const triplet = normalizeRgb232(knx.value);
    await bus.write(knx.ga, "rgb232", triplet);
    return;
  }

  if (lutronKnxIsHold(knx)) {
    const held = planLutronHold(knx);
    if (phase === "release") {
      await runLutronPlan(bus, knx, held.stop);
      return;
    }
    if (phase === "press") {
      await runLutronPlan(bus, knx, held.start);
      return;
    }
    await runLutronPlan(bus, knx, held.start);
    await sleep(400);
    await runLutronPlan(bus, knx, held.stop);
    return;
  }

  const statusGa = knx.statusGa?.trim() || knx.ga;
  const plan = planLutronKnxWrite(knx, bus.getState(statusGa)?.value);
  if (plan.kind === "scene") {
    await bus.writeRaw(knx.ga, Buffer.from([plan.byte]), 8);
    return;
  }
  await runLutronPlan(bus, knx, plan);
}

async function runLutronPlan(
  bus: KnxBus,
  knx: LutronKnxBinding,
  plan: PlannedLutronWrite
): Promise<void> {
  const role = knx.role;
  if (plan.kind === "scene") {
    await bus.writeRaw(knx.ga, Buffer.from([plan.byte]), 8);
    return;
  }
  if (plan.kind === "dim") {
    await bus.writeDimControl(knx.ga, plan.increase, plan.step);
    return;
  }
  if (plan.kind === "shadeStop") {
    await bus.write(plan.ga, "stop_step", true);
    return;
  }
  if (plan.kind === "pulse") {
    await bus.write(knx.ga, role, plan.on);
    await sleep(plan.ms);
    await bus.write(knx.ga, role, plan.off);
    return;
  }
  await bus.write(knx.ga, role, plan.value);
}

function normalizeRgb232(
  v: number | boolean | number[] | Rgb232Triplet
): Rgb232Triplet {
  if (Array.isArray(v) && v.length >= 3) {
    return {
      red: clampByte(Number(v[0])),
      green: clampByte(Number(v[1])),
      blue: clampByte(Number(v[2]))
    };
  }
  if (typeof v === "object" && v !== null && !Array.isArray(v) && "red" in v) {
    const o = v as Rgb232Triplet;
    return {
      red: clampByte(Number(o.red)),
      green: clampByte(Number(o.green)),
      blue: clampByte(Number(o.blue))
    };
  }
  throw new Error("rgb232 verwacht [r,g,b] of {red,green,blue}");
}

function coerceScalar(
  role: string,
  v: number | boolean | number[] | Rgb232Triplet
): number | boolean {
  if (Array.isArray(v) || (typeof v === "object" && v !== null && "red" in v)) {
    throw new Error("ongeldige scalar value voor rol");
  }
  if (role === "switch" || role === "bit" || role === "stop_step" || role === "up_down") {
    if (typeof v === "boolean") return v;
    return v !== 0;
  }
  if (typeof v === "boolean") return v ? 1 : 0;
  if (role === "percent" || role === "dim_value" || role === "position") {
    return Math.max(0, Math.min(100, Math.round(Number(v))));
  }
  if (role === "scene_number") {
    return Math.max(0, Math.min(63, Math.round(Number(v))));
  }
  if (role === "byte") {
    return clampByte(Number(v));
  }
  if (role === "temperature" || role === "setpoint") {
    return Math.max(5, Math.min(35, Number(v)));
  }
  return Number(v);
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export function logLutronKnx(deviceName: string, mappingLabel: string, knx: LutronKnxBinding): void {
  logger.info(
    { device: deviceName, mapping: mappingLabel, ga: knx.ga, role: knx.role },
    "Lutron → KNX"
  );
}
