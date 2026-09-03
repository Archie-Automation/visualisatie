// Resolves which logs exist and which group addresses they cover.
//
// Two sources:
//   1. Every climate/thermostat device gets an automatic log of its measured
//      temperature + setpoint (no configuration needed).
//   2. Installer-defined custom logs in house.json (`logs: [...]`), each a
//      named set of arbitrary group addresses.
//
// Shared by the sampler (to know which GAs to record) and the API (to list
// logs and resolve a log id to its series).

import { walkDevices } from "./config";
import { isStaffRole } from "./roles";
import type { GA, HouseConfig, User } from "./types";
import { userMayUseDevice } from "./userAccess";

export interface LogSeriesDef {
  ga: GA;
  label: string;
  unit?: string;
  /**
   * Semantic role for the client:
   *   'measured' = gemeten temperatuur, 'setpoint' = ingestelde temperatuur,
   *   'mode'     = verwarmen/koelen-status (1 = verwarmen, 0 = koelen).
   * Undefined for generic custom-log series.
   */
  role?: "measured" | "setpoint" | "mode";
}

export interface LogDefResolved {
  id: string;
  name: string;
  kind: "thermostat" | "custom";
  series: LogSeriesDef[];
  visibleToUsers?: boolean;
}

/** All logs available for the current config (thermostats + custom). */
export function listLogDefs(cfg: HouseConfig): LogDefResolved[] {
  const out: LogDefResolved[] = [];

  walkDevices(cfg, (d) => {
    if (d.type !== "climate") return;
    const ga = d.ga;
    const actual = ga.actual_temp;
    const setpoint = ga.setpoint_status ?? ga.setpoint;
    const mode = ga.hvac_mode_status ?? ga.hvac_mode;
    const series: LogSeriesDef[] = [];
    if (actual) {
      series.push({ ga: actual, label: "Gemeten", unit: "°C", role: "measured" });
    }
    if (setpoint) {
      series.push({
        ga: setpoint,
        label: "Ingesteld",
        unit: "°C",
        role: "setpoint"
      });
    }
    // Verwarmen/koelen-status: niet als lijn getekend maar als kleurbalk.
    if (mode) series.push({ ga: mode, label: "Modus", role: "mode" });
    if (series.length === 0) return;
    out.push({
      id: `thermostat-${d.id}`,
      name: d.name,
      kind: "thermostat",
      series
    });
  });

  for (const log of cfg.logs ?? []) {
    const series: LogSeriesDef[] = [];
    for (const entry of log.entries ?? []) {
      if (!entry.ga?.trim()) continue;
      series.push({
        ga: entry.ga.trim(),
        label: entry.label?.trim() || entry.ga.trim(),
        unit: entry.unit?.trim() || undefined
      });
    }
    if (series.length === 0) continue;
    out.push({
      id: `custom-${log.id}`,
      name: log.name?.trim() || log.id,
      kind: "custom",
      visibleToUsers: log.visibleToUsers === true,
      series
    });
  }

  return out;
}

/** Resolve a single log by its public id. */
export function findLogDef(
  cfg: HouseConfig,
  id: string
): LogDefResolved | undefined {
  return listLogDefs(cfg).find((l) => l.id === id);
}

/** Logs this login may list and open. Staff sees all; users only opted-in
 *  custom graphs plus thermostat logs of devices they may use. */
export function viewerLogDefs(
  cfg: HouseConfig,
  user: User | undefined,
  role: string | undefined
): LogDefResolved[] {
  const all = listLogDefs(cfg);
  if (isStaffRole(role) || isStaffRole(user?.role)) return all;
  return all.filter((d) => {
    if (d.kind === "custom") return d.visibleToUsers === true;
    if (!d.id.startsWith("thermostat-")) return false;
    return userMayUseDevice(user, role, cfg, d.id.slice("thermostat-".length));
  });
}

export function viewerCanSeeLog(
  cfg: HouseConfig,
  id: string,
  user: User | undefined,
  role: string | undefined
): boolean {
  return viewerLogDefs(cfg, user, role).some((l) => l.id === id);
}

/** Union of every group address covered by any log — the sampler's watch set. */
export function computeTrackedGas(cfg: HouseConfig): Set<GA> {
  const set = new Set<GA>();
  for (const def of listLogDefs(cfg)) {
    for (const s of def.series) set.add(s.ga);
  }
  return set;
}
