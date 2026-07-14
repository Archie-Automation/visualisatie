import { logger } from "../logger";
import type { KnxBus } from "../knxBus";
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
  "scene_number",
  "setpoint",
  "position"
]);

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

  const pulse =
    knx.pulseMs != null &&
    knx.pulseMs > 0 &&
    (role === "switch" || role === "bit");

  if (pulse) {
    const on =
      typeof knx.value === "boolean"
        ? knx.value
        : typeof knx.value === "number"
          ? knx.value !== 0
          : true;
    await bus.write(knx.ga, role, on);
    await sleep(Math.min(3000, Math.max(50, knx.pulseMs ?? 250)));
    await bus.write(knx.ga, role, !on);
    return;
  }

  const scalar = coerceScalar(role, knx.value);
  await bus.write(knx.ga, role, scalar);
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
