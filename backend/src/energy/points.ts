import type {
  EnergyKnxPoint,
  EnergyPointDpt,
  HouseConfig
} from "../types";

/** Live power inputs. Unconfigured points count as absent, not as 0 W. */
export const ENERGY_POWER_KEYS = [
  "gridPowerW",
  "solarPowerW",
  "batteryPowerW"
] as const;

export const ENERGY_POINT_KEYS = [
  "gridPowerW",
  "solarPowerW",
  "batteryPowerW",
  "batterySoc",
  "importEnergyKwh",
  "exportEnergyKwh",
  "solarEnergyKwh",
  "gasM3"
] as const;

export type EnergyPointKey = (typeof ENERGY_POINT_KEYS)[number];

const DPT_ROLE: Record<EnergyPointDpt, string> = {
  float2: "energy_float2",
  float4: "energy_float4",
  int16: "energy_int16",
  uint16: "energy_uint16",
  int32: "energy_int32",
  uint32: "energy_uint32",
  percent: "energy_percent"
};

export function energyActive(cfg: HouseConfig): boolean {
  return cfg.energy?.enabled === true;
}

export function energyDptRole(dpt: string): string | null {
  if (!Object.prototype.hasOwnProperty.call(DPT_ROLE, dpt)) return null;
  return DPT_ROLE[dpt as EnergyPointDpt];
}

export function configuredEnergyPoints(
  cfg: HouseConfig
): Array<{ key: EnergyPointKey; point: EnergyKnxPoint }> {
  if (!energyActive(cfg)) return [];
  const knx = cfg.energy?.knx;
  if (!knx) return [];
  const out: Array<{ key: EnergyPointKey; point: EnergyKnxPoint }> = [];
  for (const key of ENERGY_POINT_KEYS) {
    const point = knx[key];
    const ga = point?.ga?.trim();
    if (!point || !ga) continue;
    if (!energyDptRole(point.dpt)) continue;
    out.push({ key, point: { ...point, ga } });
  }
  return out;
}
