import type { HouseConfig, IntercomDevice } from "./types";

/**
 * Verplaats elke `intercom` uit kamers naar `intercoms` op projectniveau
 * (deduplicate op id). Na JSON-parse / installer-save.
 */
export function normalizeHouseIntercoms(cfg: HouseConfig): void {
  if (!cfg.intercoms) cfg.intercoms = [];
  const list = cfg.intercoms;
  const seen = new Set(list.map((c) => c.id));

  for (const floor of cfg.floors) {
    for (const room of floor.rooms) {
      const next: typeof room.devices = [];
      for (const d of room.devices) {
        if (d.type === "intercom") {
          if (!seen.has(d.id)) {
            list.push(d as IntercomDevice);
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
export function normalizeHouseIntercomsRaw(raw: unknown): void {
  if (typeof raw !== "object" || raw === null) return;
  const cfg = raw as Record<string, unknown>;
  const floors = cfg.floors;
  if (!Array.isArray(floors)) return;

  const ics: unknown[] = Array.isArray(cfg.intercoms) ? [...cfg.intercoms] : [];
  cfg.intercoms = ics;

  const seen = new Set<string>();
  for (const x of ics) {
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
          (d as { type?: string }).type === "intercom"
        ) {
          const id = String((d as { id?: string }).id ?? "");
          if (id && !seen.has(id)) {
            ics.push(d);
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
