import type { CameraDevice, HouseConfig } from "./types";

/**
 * Move every `camera` device from rooms into the top-level `cameras` array,
 * deduplicated by id. Call after JSON parse (file load or installer body)
 * so schema/UX can treat cameras as project-level only.
 */
export function normalizeHouseCameras(cfg: HouseConfig): void {
  if (!cfg.cameras) cfg.cameras = [];
  const list = cfg.cameras;
  const seen = new Set(list.map((c) => c.id));

  for (const floor of cfg.floors) {
    for (const room of floor.rooms) {
      const next: typeof room.devices = [];
      for (const d of room.devices) {
        if (d.type === "camera") {
          if (!seen.has(d.id)) {
            list.push(d as CameraDevice);
            seen.add(d.id);
          }
        } else {
          next.push(d);
        }
      }
      room.devices = next;
    }
  }
}

/** Mutates a parsed JSON object before Ajv (unknown shape). */
export function normalizeHouseCamerasRaw(raw: unknown): void {
  if (typeof raw !== "object" || raw === null) return;
  const cfg = raw as Record<string, unknown>;
  const floors = cfg.floors;
  if (!Array.isArray(floors)) return;

  const cams: unknown[] = Array.isArray(cfg.cameras) ? [...cfg.cameras] : [];
  cfg.cameras = cams;

  const seen = new Set<string>();
  for (const x of cams) {
    if (x && typeof x === "object" && "id" in x) {
      seen.add(String((x as { id: unknown }).id));
    }
  }

  for (const f of floors) {
    if (typeof f !== "object" || f === null) continue;
    const rooms = (f as { rooms?: unknown }).rooms;
    if (!Array.isArray(rooms)) continue;
    for (const r of rooms) {
      if (typeof r !== "object" || r === null) continue;
      const devs = (r as { devices?: unknown }).devices;
      if (!Array.isArray(devs)) continue;
      const next: unknown[] = [];
      for (const d of devs) {
        if (
          d &&
          typeof d === "object" &&
          (d as { type?: string }).type === "camera"
        ) {
          const id = String((d as { id?: string }).id ?? "");
          if (id && !seen.has(id)) {
            cams.push(d);
            seen.add(id);
          }
        } else {
          next.push(d);
        }
      }
      (r as { devices: unknown[] }).devices = next;
    }
  }
}
