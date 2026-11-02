import type { EnergyKnxPoint, HouseEnergyConfig } from "../types";
import { emptyEnergyDay, type EnergyDay } from "./day";
import {
  ENERGY_POINT_KEYS,
  ENERGY_POWER_KEYS,
  energyScale,
  type EnergyPointKey
} from "./points";

/**
 * Live energy view derived from already-decoded KNX values.
 *
 * Sign convention:
 *   gridPowerW    > 0 import, < 0 export
 *   solarPowerW   production
 *   batteryPowerW > 0 discharging, < 0 charging
 *   housePowerW   = grid + solar + battery
 *
 * A configured point without a numeric telegram stays null. It is never
 * coerced to 0. House load stays null until every configured power point
 * has a value. Unconfigured power points are left out of the sum.
 */
export interface EnergySnapshot extends EnergyDay {
  enabled: boolean;
  stale: boolean;
  gridPowerW: number | null;
  solarPowerW: number | null;
  batteryPowerW: number | null;
  batterySoc: number | null;
  housePowerW: number | null;
  importEnergyKwh: number | null;
  exportEnergyKwh: number | null;
  solarEnergyKwh: number | null;
  gasM3: number | null;
}

export function emptyEnergySnapshot(): EnergySnapshot {
  return {
    enabled: false,
    stale: false,
    gridPowerW: null,
    solarPowerW: null,
    batteryPowerW: null,
    batterySoc: null,
    housePowerW: null,
    importEnergyKwh: null,
    exportEnergyKwh: null,
    solarEnergyKwh: null,
    gasM3: null,
    ...emptyEnergyDay()
  };
}

function lookup(
  values: ReadonlyMap<string, unknown> | Record<string, unknown>,
  ga: string
): unknown {
  if (values instanceof Map) return values.get(ga);
  return (values as Record<string, unknown>)[ga];
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

function readPoint(
  point: EnergyKnxPoint | undefined,
  values: ReadonlyMap<string, unknown> | Record<string, unknown>
): { configured: boolean; value: number | null } {
  const ga = point?.ga?.trim() ?? "";
  if (!point || !ga) return { configured: false, value: null };
  const scale = energyScale(point.scale);
  if (scale == null) return { configured: true, value: null };
  const raw = lookup(values, ga);
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    return { configured: true, value: null };
  }
  return { configured: true, value: round3(raw * scale) };
}

export function buildEnergySnapshot(input: {
  energy: HouseEnergyConfig | undefined;
  values: ReadonlyMap<string, unknown> | Record<string, unknown>;
  busConnected: boolean;
}): EnergySnapshot {
  if (input.energy?.enabled !== true) return emptyEnergySnapshot();

  const knx = input.energy.knx ?? {};
  const reads = {} as Record<EnergyPointKey, { configured: boolean; value: number | null }>;
  for (const key of ENERGY_POINT_KEYS) {
    reads[key] = readPoint(knx[key], input.values);
  }

  const power = ENERGY_POWER_KEYS.map((key) => reads[key]);
  const anyPower = power.some((p) => p.configured);
  const powerIncomplete = power.some((p) => p.configured && p.value == null);
  const housePowerW =
    !anyPower || powerIncomplete
      ? null
      : round3(power.reduce((sum, p) => sum + (p.value ?? 0), 0));

  return {
    enabled: true,
    stale: !input.busConnected,
    gridPowerW: reads.gridPowerW.value,
    solarPowerW: reads.solarPowerW.value,
    batteryPowerW: reads.batteryPowerW.value,
    batterySoc: reads.batterySoc.value,
    housePowerW,
    importEnergyKwh: reads.importEnergyKwh.value,
    exportEnergyKwh: reads.exportEnergyKwh.value,
    solarEnergyKwh: reads.solarEnergyKwh.value,
    gasM3: reads.gasM3.value,
    ...emptyEnergyDay()
  };
}
