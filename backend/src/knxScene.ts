import type { HouseConfig, GA } from "./types";
import { loadGaCatalog } from "./knxImport";

/** DPT 18.001: bits 0–5 = scene−1 (0–63), bit7 = store. */
export function encodeSceneByte(sceneNumber: number, store: boolean): number {
  const n = Math.min(64, Math.max(1, Math.round(Number(sceneNumber) || 1)));
  return (n - 1) | (store ? 0x80 : 0);
}

/** Recall only (bit7 = 0). Returns UI number 1–64, or null. */
export function decodeSceneRecallByte(byte: number): number | null {
  const b = byte & 0xff;
  if (b & 0x80) return null;
  return (b & 0x3f) + 1;
}

export function extractSceneByte(value: unknown): number | null {
  // Alleen 1-byte payloads: een 2-byte temperatuur mag niet als scene tellen.
  if (Buffer.isBuffer(value)) {
    if (value.length !== 1) return null;
    return value[0] & 0xff;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    const n = Math.round(value);
    if (n >= 0 && n <= 255) return n;
  }
  return null;
}

export function knxSceneLearnEnabled(cfg: HouseConfig): boolean {
  return cfg.knxSceneLearn?.enabled === true;
}

function sceneNameHint(text: string): boolean {
  return /(scene|szene|scène)/i.test(text);
}

/** True when this GA is a known KNX scene control (catalog DPT/name or existing binding). */
export function isTrustedSceneGa(ga: GA, cfg: HouseConfig): boolean {
  const addr = ga.trim();
  if (!addr) return false;
  for (const s of cfg.scenes ?? []) {
    if (s.knx?.ga === addr) return true;
  }
  for (const f of cfg.floors) {
    for (const r of f.rooms) {
      for (const s of r.scenes ?? []) {
        if (s.knx?.ga === addr) return true;
      }
    }
  }
  try {
    for (const e of loadGaCatalog()) {
      if (e.address !== addr) continue;
      const dpt = (e.dpt ?? "").toLowerCase();
      if (dpt.includes("17.001") || dpt.includes("18.001") || dpt.includes("dpt17") || dpt.includes("dpt18")) {
        return true;
      }
      const blob = `${e.name} ${e.mainGroup ?? ""} ${e.middleGroup ?? ""}`;
      if (sceneNameHint(blob)) return true;
    }
  } catch {
    /* catalog optional */
  }
  return false;
}
