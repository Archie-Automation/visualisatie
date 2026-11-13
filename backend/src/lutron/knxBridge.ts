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
  "position"
]);

export type PlannedLutronWrite =
  | { kind: "once"; value: number | boolean }
  | { kind: "pulse"; on: number | boolean; off: number | boolean; ms: number }
  | { kind: "scene"; byte: number };

/** Oude koppelingen zonder `send` maar mét pulsduur op een bit blijven een puls. */
export function lutronSendMode(knx: LutronKnxBinding): "value" | "toggle" | "pulse" {
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
export async function executeLutronToKnx(bus: KnxBus, knx: LutronKnxBinding): Promise<void> {
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

  const statusGa = knx.statusGa?.trim() || knx.ga;
  const plan = planLutronKnxWrite(knx, bus.getState(statusGa)?.value);
  if (plan.kind === "scene") {
    await bus.writeRaw(knx.ga, Buffer.from([plan.byte]), 8);
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
  if (role === "switch" || role === "bit") {
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
