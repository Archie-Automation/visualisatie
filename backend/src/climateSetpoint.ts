import type { ClimateDevice, Device, HouseConfig } from "./types";

/**
 * Thermostaat-setpoint.
 *
 * Absoluut: DPT 9.001, gewenste temperatuur in °C.
 * Relatief: setpointverschuiving in kelvin. Twee busformaten:
 * - DPT 6.010 — 1 byte signed, resolutie 0,1 K, bereik −12,8…12,7.
 *   knx.js codeert DPT 6.010 als ruwe signed byte (geen 0,1-factor),
 *   dus 1,5 K gaat als 15 de bus op en komt als 15 terug.
 * - DPT 9.002 — dezelfde 2-byte float als DPT 9.001, eenheid K.
 */
export type SetpointControl = "absolute" | "relative_6.010" | "relative_9.002";

const SHIFT6 = { min: -12.8, max: 12.7 };
const SHIFT9 = { min: -50, max: 50 };

export function setpointControlOf(device: ClimateDevice): SetpointControl {
  const v = device.climate?.setpointControl;
  if (v === "relative_6.010" || v === "relative_9.002") return v;
  return "absolute";
}

export function setpointWriteRole(control: SetpointControl): string {
  switch (control) {
    case "relative_6.010":
      return "setpoint_shift_6";
    case "relative_9.002":
      return "setpoint_shift_9";
    default:
      return "setpoint";
  }
}

export function setpointStatusRole(control: SetpointControl): string {
  switch (control) {
    case "relative_6.010":
      return "setpoint_shift_6_status";
    case "relative_9.002":
      return "setpoint_shift_9_status";
    default:
      return "setpoint_status";
  }
}

/** Role key used in the GA index (and therefore ROLE_DPT) for a climate GA. */
export function climateBusRole(device: ClimateDevice, key: string): string {
  if (key === "setpoint") return setpointWriteRole(setpointControlOf(device));
  if (key === "setpoint_status") return setpointStatusRole(setpointControlOf(device));
  return key;
}

export function isShift6Role(role: string): boolean {
  return role === "setpoint_shift_6" || role === "setpoint_shift_6_status";
}

export interface SetpointLimits {
  min: number;
  max: number;
}

export function setpointLimits(device: ClimateDevice): SetpointLimits {
  const control = setpointControlOf(device);
  const cfg = device.climate;
  if (control === "absolute") {
    const min = finite(cfg?.minTemp, 5);
    const max = finite(cfg?.maxTemp, 35);
    if (min < max) return { min, max };
    return { min: 5, max: 35 };
  }
  const hard = control === "relative_6.010" ? SHIFT6 : SHIFT9;
  let min = finite(cfg?.minTemp, -5);
  let max = finite(cfg?.maxTemp, 5);
  if (!(min < max)) {
    min = -5;
    max = 5;
  }
  min = clamp(min, hard.min, hard.max);
  max = clamp(max, hard.min, hard.max);
  if (!(min < max)) return { min: hard.min, max: hard.max };
  return { min, max };
}

/** 1,5 K → raw byte 15. Clamped to the DPT 6.010 wire range. */
export function encodeShift6(kelvin: number): number {
  const raw = Math.round(kelvin * 10);
  return Math.max(-128, Math.min(127, raw));
}

/** Raw byte 15 → 1,5 K. */
export function decodeShift6(raw: number): number {
  return Math.round(raw) / 10;
}

export function roundTenth(value: number): number {
  return Math.round(value * 10) / 10;
}

export function findClimateBySetpointGa(
  cfg: HouseConfig,
  ga: string
): ClimateDevice | undefined {
  let hit: ClimateDevice | undefined;
  eachDevice(cfg, (d) => {
    if (d.type === "climate" && d.ga.setpoint === ga) hit = d;
  });
  return hit;
}

function eachDevice(cfg: HouseConfig, fn: (d: Device) => void): void {
  for (const floor of cfg.floors) {
    for (const room of floor.rooms) {
      for (const device of room.devices) fn(device);
    }
  }
  for (const device of cfg.devices ?? []) fn(device);
}

function finite(value: number | undefined, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}
