/** Vergrendeling na omschakelen koel/verwarm — gedeeld over alle clients. */

import fs from "node:fs";
import path from "node:path";
import { logger } from "./logger";

export interface HvacLockEntry {
  deviceId: string;
  untilMs: number;
}

type HvacLockListener = (entry: HvacLockEntry) => void;

/** Parse `u:mm` (bijv. `4:00`, `0:05`) naar milliseconden; 0 bij ontbrekend/0:00. */
export function parseHvacSwitchLockMs(raw?: string): number {
  if (!raw?.trim()) return 0;
  const parts = raw.trim().split(":");
  if (parts.length !== 2) return 0;
  const h = Number.parseInt(parts[0]!, 10);
  const m = Number.parseInt(parts[1]!, 10);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return 0;
  return ((Math.max(0, h) * 60) + Math.max(0, m)) * 60 * 1000;
}

function lockStorePath(): string {
  const fromEnv = process.env.HVAC_LOCK_STORE_PATH?.trim();
  if (fromEnv) return path.resolve(fromEnv);
  return path.join(process.cwd(), "data", "hvac-locks.json");
}

function loadFromDisk(): Map<string, number> {
  const file = lockStorePath();
  try {
    if (!fs.existsSync(file)) return new Map();
    const raw = JSON.parse(fs.readFileSync(file, "utf-8")) as {
      locks?: HvacLockEntry[];
    };
    const now = Date.now();
    const map = new Map<string, number>();
    for (const entry of raw.locks ?? []) {
      if (
        typeof entry.deviceId === "string" &&
        typeof entry.untilMs === "number" &&
        entry.untilMs > now
      ) {
        map.set(entry.deviceId, entry.untilMs);
      }
    }
    if (map.size > 0) {
      logger.info({ file, count: map.size }, "HVAC-vergrendelingen geladen");
    }
    return map;
  } catch (err) {
    logger.warn({ err, file }, "HVAC-lock bestand kon niet worden geladen");
    return new Map();
  }
}

function persistToDisk(locks: Map<string, number>): void {
  const file = lockStorePath();
  const now = Date.now();
  const active = [...locks.entries()]
    .filter(([, untilMs]) => untilMs > now)
    .map(([deviceId, untilMs]) => ({ deviceId, untilMs }));

  try {
    if (active.length === 0) {
      if (fs.existsSync(file)) fs.unlinkSync(file);
      return;
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ locks: active }, null, 2), "utf-8");
    fs.renameSync(tmp, file);
  } catch (err) {
    logger.warn({ err, file }, "HVAC-lock opslaan mislukt");
  }
}

class HvacSwitchLockService {
  private locks = loadFromDisk();
  private listeners = new Set<HvacLockListener>();

  onChange(fn: HvacLockListener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  /** Zet vergrendeling; retourneert untilMs of null als geen lock geconfigureerd. */
  arm(deviceId: string, durationRaw?: string): number | null {
    const ms = parseHvacSwitchLockMs(durationRaw);
    if (ms <= 0) return null;
    const untilMs = Date.now() + ms;
    this.locks.set(deviceId, untilMs);
    this.persist();
    const entry = { deviceId, untilMs };
    for (const fn of this.listeners) fn(entry);
    return untilMs;
  }

  getUntil(deviceId: string): number | null {
    const untilMs = this.locks.get(deviceId);
    if (untilMs == null) return null;
    if (untilMs <= Date.now()) {
      this.locks.delete(deviceId);
      this.persist();
      return null;
    }
    return untilMs;
  }

  getAll(): HvacLockEntry[] {
    const now = Date.now();
    const out: HvacLockEntry[] = [];
    let pruned = false;
    for (const [deviceId, untilMs] of this.locks) {
      if (untilMs > now) out.push({ deviceId, untilMs });
      else {
        this.locks.delete(deviceId);
        pruned = true;
      }
    }
    if (pruned) this.persist();
    return out;
  }

  clearAll(): void {
    this.locks.clear();
    this.persist();
  }

  private persist(): void {
    persistToDisk(this.locks);
  }
}

export const hvacSwitchLock = new HvacSwitchLockService();
