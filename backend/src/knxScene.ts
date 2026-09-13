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

function sceneNameHint(text: string): boolean {
  return /(scene|szene|scène)/i.test(text);
}

function isCatalogSceneDpt(dpt: string): boolean {
  const d = dpt.toLowerCase();
  return (
    d.includes("17.001") ||
    d.includes("18.001") ||
    d.includes("dpt17") ||
    d.includes("dpt18")
  );
}

/** Scene-oproep GAs uit de ETS-catalogus (DPT 17/18 of naam scene/szene). */
export function catalogSceneAddresses(): GA[] {
  const out: GA[] = [];
  const seen = new Set<string>();
  try {
    for (const e of loadGaCatalog()) {
      if (!e.address || seen.has(e.address)) continue;
      const hit =
        isCatalogSceneDpt(e.dpt ?? "") ||
        sceneNameHint(`${e.name} ${e.mainGroup ?? ""} ${e.middleGroup ?? ""}`);
      if (!hit) continue;
      seen.add(e.address);
      out.push(e.address);
    }
  } catch {
    /* catalog optional */
  }
  return out;
}

function asScenePayloadBytes(value: unknown): Buffer | null {
  if (Buffer.isBuffer(value)) return value;
  if (value instanceof Uint8Array) return Buffer.from(value);
  if (Array.isArray(value) && value.every((x) => typeof x === "number")) {
    return Buffer.from(value as number[]);
  }
  if (
    value &&
    typeof value === "object" &&
    (value as { type?: string }).type === "Buffer" &&
    Array.isArray((value as { data?: unknown }).data)
  ) {
    return Buffer.from((value as { data: number[] }).data);
  }
  return null;
}

export function extractSceneByte(value: unknown): number | null {
  const buf = asScenePayloadBytes(value);
  if (buf) {
    if (buf.length === 1) return buf[0] & 0xff;
    if (buf.length === 2) return buf[1] & 0xff;
    return null;
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
  return catalogSceneAddresses().includes(addr);
}
