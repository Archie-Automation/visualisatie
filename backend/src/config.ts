// schema-reload: melding device type added
import fs from "node:fs";
import path from "node:path";
import { normalizeHouseCameras } from "./houseCameras";
import { normalizeHouseIntercoms } from "./houseIntercoms";
import { effectiveIntercomReleaseMode } from "./intercomReleaseMode";
import { logger } from "./logger";
import type { Device, HouseConfig, GA } from "./types";

let cached: HouseConfig | null = null;
let configVersion = 0;
const configPath = path.resolve(
  process.env.CONFIG_PATH ?? path.join(__dirname, "..", "..", "config", "house.json")
);

export function loadConfig(): HouseConfig {
  const raw = fs.readFileSync(configPath, "utf-8");
  const parsed = JSON.parse(raw) as HouseConfig;
  normalizeHouseCameras(parsed);
  normalizeHouseIntercoms(parsed);
  cached = parsed;
  configVersion++;
  logger.info(
    { file: configPath, floors: parsed.floors.length, version: configVersion },
    "House configuration loaded"
  );
  return parsed;
}

export function getConfig(): HouseConfig {
  if (!cached) return loadConfig();
  return cached;
}

/** Monotonic counter, bumped every time the config is (re)loaded or written. */
export function getConfigVersion(): number {
  return configVersion;
}

/**
 * Atomically persist a new config to disk. Writes to a temp file next to
 * the target and renames so an interrupted save never leaves a truncated
 * house.json – critical for a device the customer relies on nightly.
 */
export function persistConfig(next: HouseConfig): void {
  normalizeHouseCameras(next);
  normalizeHouseIntercoms(next);
  const tmp = `${configPath}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(next, null, 2), "utf-8");
  fs.renameSync(tmp, configPath);
  cached = next;
  configVersion++;
  logger.info(
    { file: configPath, version: configVersion },
    "House configuration persisted"
  );
}

/**
 * Read-modify-write helper. Pass a mutator that returns the new config
 * (or mutates a deep clone in place). The previous cached value is never
 * mutated directly – callers depending on referential equality stay safe.
 */
export function updateConfig(
  mutate: (draft: HouseConfig) => HouseConfig | void
): HouseConfig {
  const current = getConfig();
  // `structuredClone` keeps nested objects independent so mutation is safe.
  const draft: HouseConfig = structuredClone(current);
  const next = mutate(draft) ?? draft;
  persistConfig(next);
  return next;
}

/**
 * Visit every device in the tree.
 */
export function walkDevices(
  cfg: HouseConfig,
  fn: (device: Device, roomId: string, floorId: string) => void
) {
  for (const floor of cfg.floors) {
    for (const room of floor.rooms) {
      for (const device of room.devices) {
        fn(device, room.id, floor.id);
      }
    }
  }
  // Global (room-less) devices – roomId and floorId are empty strings.
  for (const device of cfg.devices ?? []) {
    fn(device, '', '');
  }
}

/**
 * Collect every GA mentioned anywhere in the config – lights, shading,
 * climate, intercom, new device types (fireplace/ac/fan/universal) and
 * scene actions. Used to bind KnxBus datapoints on startup so feedback
 * flows in for everything, not just the canonical `ga` bag.
 */
export function collectAllGAs(cfg: HouseConfig): GA[] {
  const out = new Set<GA>();
  const add = (ga?: GA) => {
    if (ga) out.add(ga);
  };

  walkDevices(cfg, (d) => {
    const ga = (d as { ga?: Record<string, string> }).ga;
    if (ga) for (const v of Object.values(ga)) add(v);

    if (d.type === "fireplace") {
      add(d.fireplace.onOff.ga);
      add(d.fireplace.onOff.statusGa);
      add(d.fireplace.flame?.ga);
      add(d.fireplace.flame?.statusGa);
      add(d.fireplace.safetyLockout?.ga);
      const dl = d.fireplace.discreteLevel;
      if (dl) {
        for (const k of ["on", "off", "up", "down"] as const) {
          add(dl[k]?.ga);
        }
      }
    }
    if (d.type === "ac") {
      add(d.ac.onOff.ga);
      add(d.ac.onOff.statusGa);
      add(d.ac.setpoint.ga);
      add(d.ac.setpoint.statusGa);
      add(d.ac.actualTemp?.ga);
      add(d.ac.mode?.ga);
      add(d.ac.mode?.statusGa);
      add(d.ac.fanSpeed?.ga);
      add(d.ac.fanSpeed?.statusGa);
    }
    if (d.type === "fan") {
      add(d.fan.onOff.ga);
      add(d.fan.onOff.statusGa);
      add(d.fan.speed?.ga);
      add(d.fan.speed?.statusGa);
      add(d.fan.oscillate?.ga);
      add(d.fan.oscillate?.statusGa);
      add(d.fan.direction?.ga);
      add(d.fan.direction?.statusGa);
    }
    if (d.type === "universal") {
      for (const b of d.universal.buttons) {
        add(b.action.ga);
        add(b.actionOff?.ga);
        add(b.statusGa);
      }
    }
    if (d.type === "wtw") {
      for (const b of d.wtw.buttons ?? []) {
        add(b.ga);
        add(b.statusGa);
      }
      for (const s of d.wtw.status ?? []) {
        add(s.ga);
      }
    }
    if (d.type === "melding") {
      for (const item of d.melding?.items ?? []) {
        add(item.ga);
      }
    }
  });

  for (const d of cfg.intercoms ?? []) {
    add(d.intercom.doorbell?.ga);
    if (effectiveIntercomReleaseMode(d) === "knx") {
      add(d.intercom.release?.ga);
    }
  }

  // Scenes
  for (const s of cfg.scenes ?? []) for (const a of s.actions) add(a.ga);
  for (const f of cfg.floors) {
    for (const r of f.rooms) {
      for (const s of r.scenes ?? []) for (const a of s.actions) add(a.ga);
    }
  }

  return [...out];
}

/**
 * Classify a group address by the device role it plays. Used to pick the
 * right DPT when encoding/decoding bus telegrams.
 */
export interface GARole {
  deviceId: string;
  deviceType: Device["type"];
  role: string;
}

function pushGA(
  index: Map<GA, GARole[]>,
  ga: GA | undefined,
  role: string,
  deviceId: string,
  deviceType: Device["type"]
) {
  if (!ga) return;
  const list = index.get(ga) ?? [];
  list.push({ deviceId, deviceType, role });
  index.set(ga, list);
}

/**
 * Map every GA we care about to config roles so inbound telegrams can be
 * decoded with the right DPT (see KnxBus + ROLE_DPT).
 */
export function buildGAIndex(cfg: HouseConfig): Map<GA, GARole[]> {
  const index = new Map<GA, GARole[]>();
  walkDevices(cfg, (d) => {
    const ga = (d as { ga?: Record<string, string> }).ga;
    if (ga) {
      for (const [role, address] of Object.entries(ga)) {
        if (!address) continue;
        pushGA(index, address, role, d.id, d.type);
      }
    }

    if (d.type === "fireplace") {
      const fp = d.fireplace;
      pushGA(index, fp.onOff.ga, "switch", d.id, d.type);
      pushGA(index, fp.onOff.statusGa, "switch_status", d.id, d.type);
      if (fp.flame) {
        const ranges = fp.flame.stepRanges;
        const usePctBands = ranges && ranges.length > 0;
        const useByteSteps = !!fp.flame.steps && !usePctBands;
        const cmdRole = useByteSteps ? "flame" : "percent";
        const statRole = useByteSteps ? "flame_status" : "percent";
        pushGA(index, fp.flame.ga, cmdRole, d.id, d.type);
        if (fp.flame.statusGa && fp.flame.statusGa !== fp.flame.ga) {
          pushGA(index, fp.flame.statusGa, statRole, d.id, d.type);
        }
      }
      pushGA(index, fp.safetyLockout?.ga, "bit", d.id, d.type);
      if (fp.discreteLevel) {
        for (const k of ["on", "off", "up", "down"] as const) {
          const ga = fp.discreteLevel[k]?.ga;
          pushGA(index, ga, "switch", d.id, d.type);
        }
      }
    }

    if (d.type === "ac") {
      const ac = d.ac;
      pushGA(index, ac.onOff.ga, "switch", d.id, d.type);
      pushGA(index, ac.onOff.statusGa, "switch_status", d.id, d.type);
      pushGA(index, ac.setpoint.ga, "setpoint", d.id, d.type);
      pushGA(index, ac.setpoint.statusGa, "setpoint_status", d.id, d.type);
      pushGA(index, ac.actualTemp?.ga, "actual_temp", d.id, d.type);
      pushGA(index, ac.mode?.ga, "mode", d.id, d.type);
      pushGA(index, ac.mode?.statusGa, "mode_status", d.id, d.type);
      pushGA(index, ac.fanSpeed?.ga, "fan_speed", d.id, d.type);
      pushGA(index, ac.fanSpeed?.statusGa, "fan_speed", d.id, d.type);
    }

    if (d.type === "fan") {
      const fan = d.fan;
      pushGA(index, fan.onOff.ga, "switch", d.id, d.type);
      pushGA(index, fan.onOff.statusGa, "switch_status", d.id, d.type);
      if (fan.speed) {
        const role = fan.speed.steps ? "byte" : "percent";
        pushGA(index, fan.speed.ga, role, d.id, d.type);
        if (fan.speed.statusGa && fan.speed.statusGa !== fan.speed.ga) {
          pushGA(index, fan.speed.statusGa, role, d.id, d.type);
        }
      }
      pushGA(index, fan.oscillate?.ga, "switch", d.id, d.type);
      pushGA(index, fan.oscillate?.statusGa, "switch_status", d.id, d.type);
      pushGA(index, fan.direction?.ga, "switch", d.id, d.type);
      pushGA(index, fan.direction?.statusGa, "switch_status", d.id, d.type);
    }

    if (d.type === "universal") {
      for (const b of d.universal.buttons) {
        pushGA(index, b.action.ga, b.action.role, d.id, d.type);
        if (b.actionOff?.ga) {
          pushGA(index, b.actionOff.ga, b.actionOff.role, d.id, d.type);
        }
        if (b.statusGa) {
          pushGA(index, b.statusGa, b.action.role, d.id, d.type);
        }
      }
    }
    if (d.type === "wtw") {
      for (const b of d.wtw.buttons ?? []) {
        const role = wtwDptToRoleConfig(b.dpt);
        pushGA(index, b.ga, role, d.id, d.type);
        if (b.statusGa) pushGA(index, b.statusGa, role, d.id, d.type);
      }
      for (const s of d.wtw.status ?? []) {
        const role = wtwDptToRoleConfig(s.dpt === "hex" ? "5.010" : s.dpt);
        pushGA(index, s.ga, role, d.id, d.type);
      }
    }
    if (d.type === "melding") {
      for (const item of d.melding?.items ?? []) {
        const role = wtwDptToRoleConfig(item.dpt === "hex" ? "5.010" : item.dpt);
        pushGA(index, item.ga, role, d.id, d.type);
      }
    }

  });

  for (const d of cfg.intercoms ?? []) {
    pushGA(index, d.intercom.doorbell?.ga, "switch", d.id, d.type);
    if (effectiveIntercomReleaseMode(d) === "knx") {
      pushGA(index, d.intercom.release?.ga, "switch", d.id, d.type);
    }
  }

  for (const s of cfg.scenes ?? []) {
    for (const a of s.actions) {
      pushGA(index, a.ga, a.role, `scene:${s.id}`, "light_switch");
    }
  }
  for (const f of cfg.floors) {
    for (const r of f.rooms) {
      for (const s of r.scenes ?? []) {
        for (const a of s.actions) {
          pushGA(index, a.ga, a.role, `scene:${r.id}:${s.id}`, "light_switch");
        }
      }
    }
  }

  return index;
}

/** Locate a scene by id anywhere in the tree. Returns the scene + scope. */
export function findScene(
  cfg: HouseConfig,
  id: string
): { scene: import("./types").Scene; scope: "global" | "room"; roomId?: string } | null {
  for (const s of cfg.scenes ?? []) {
    if (s.id === id) return { scene: s, scope: "global" };
  }
  for (const f of cfg.floors) {
    for (const r of f.rooms) {
      for (const s of r.scenes ?? []) {
        if (s.id === id) return { scene: s, scope: "room", roomId: r.id };
      }
    }
  }
  return null;
}

/** Maps a WTW DPT string to a KnxBus role string (mirrors commands.ts helper). */
function wtwDptToRoleConfig(dpt: string): string {
  if (dpt.startsWith("1.")) return "bit";
  if (dpt.startsWith("9.")) return "temperature"; // all DPT9.x share same 2-byte float encoding
  if (dpt.startsWith("14.")) return "float4byte";
  const map: Record<string, string> = {
    "5.001": "percent",
    "5.010": "byte",
    "6.001": "signed_byte",
    "7.001": "uint16",
    "8.001": "signed_2byte",
    "12.001": "uint32",
    "13.001": "int32",
  };
  return map[dpt] ?? "byte";
}

export function findRoom(
  cfg: HouseConfig,
  roomId: string
): import("./types").Room | null {
  for (const f of cfg.floors) {
    for (const r of f.rooms) if (r.id === roomId) return r;
  }
  return null;
}

