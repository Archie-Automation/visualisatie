import { logger } from "../logger";
import type { KnxBus } from "../knxBus";
import { encodeSceneByte } from "../knxScene";
import type { LutronKnxBinding, Rgb232Triplet } from "../types";

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

/** Actienummers: 3 = indrukken, 4 = loslaten. */
export function lutronMappingHandles(
  map: { actionNumber?: number; knx: LutronKnxBinding },
  action: number
): boolean {
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
