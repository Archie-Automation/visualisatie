import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { collectIntercoms } from "./cameras";
import { refreshSnapshotCache } from "./cameraSnapshot";
import { getConfig } from "./config";
import { logger } from "./logger";

export const MAX_INTERCOM_CAPTURES = 10;
const RING_COOLDOWN_MS = 8_000;

export type CaptureSource = "ring" | "manual";

export interface IntercomCaptureMeta {
  id: string;
  intercomId: string;
  name: string;
  ts: number;
  source: CaptureSource;
}

function dataDir(): string {
  const fromEnv = process.env.LOG_STORE_PATH?.trim();
  if (fromEnv) return path.dirname(path.resolve(fromEnv));
  return path.join(process.cwd(), "data");
}

function mediaBase(): string {
  return (process.env.MEDIA_BASE_URL ?? "http://localhost:1984").replace(
    /\/+$/,
    ""
  );
}

function safeId(raw: string): string {
  return raw.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function dirFor(intercomId: string): string {
  return path.join(dataDir(), "intercom-captures", safeId(intercomId));
}

function indexPath(intercomId: string): string {
  return path.join(dirFor(intercomId), "index.json");
}

function readIndex(intercomId: string): IntercomCaptureMeta[] {
  try {
    const parsed = JSON.parse(fs.readFileSync(indexPath(intercomId), "utf8"));
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (row): row is IntercomCaptureMeta =>
        row != null &&
        typeof row === "object" &&
        typeof row.id === "string" &&
        typeof row.ts === "number"
    );
  } catch {
    return [];
  }
}

function writeIndex(intercomId: string, items: IntercomCaptureMeta[]): void {
  fs.mkdirSync(dirFor(intercomId), { recursive: true });
  fs.writeFileSync(indexPath(intercomId), JSON.stringify(items, null, 2));
}

const lastRingCaptureAt = new Map<string, number>();

export function listIntercomCaptures(intercomId: string): IntercomCaptureMeta[] {
  return readIndex(intercomId).slice(0, MAX_INTERCOM_CAPTURES);
}

export function readIntercomCaptureJpeg(
  intercomId: string,
  captureId: string
): Buffer | null {
  const id = safeId(captureId);
  if (!id) return null;
  const file = path.join(dirFor(intercomId), `${id}.jpg`);
  if (!fs.existsSync(file)) return null;
  return fs.readFileSync(file);
}

export async function captureIntercomStill(opts: {
  intercomId: string;
  source: CaptureSource;
}): Promise<IntercomCaptureMeta | null> {
  const ic = collectIntercoms(getConfig()).find((i) => i.id === opts.intercomId);
  if (!ic) return null;

  if (opts.source === "ring") {
    const prev = lastRingCaptureAt.get(opts.intercomId) ?? 0;
    if (Date.now() - prev < RING_COOLDOWN_MS) return null;
    lastRingCaptureAt.set(opts.intercomId, Date.now());
  }

  const buf = await refreshSnapshotCache("intercom", ic, mediaBase());
  if (!buf) {
    logger.warn({ id: opts.intercomId }, "intercom capture: geen frame");
    return null;
  }

  const id = randomUUID().replace(/-/g, "").slice(0, 16);
  const dir = dirFor(opts.intercomId);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${id}.jpg`), buf);

  const meta: IntercomCaptureMeta = {
    id,
    intercomId: opts.intercomId,
    name: ic.name,
    ts: Date.now(),
    source: opts.source
  };
  const next = [meta, ...readIndex(opts.intercomId)].slice(
    0,
    MAX_INTERCOM_CAPTURES
  );
  const keep = new Set(next.map((m) => m.id));
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith(".jpg")) continue;
    const cid = name.slice(0, -4);
    if (!keep.has(cid)) {
      try {
        fs.unlinkSync(path.join(dir, name));
      } catch {
        /* ignore */
      }
    }
  }
  writeIndex(opts.intercomId, next);
  logger.info(
    { id: opts.intercomId, captureId: id, source: opts.source },
    "intercom still saved"
  );
  return meta;
}

/** Fire-and-forget still on doorbell / SIP ring. Deduped per intercom. */
export function captureOnIntercomRing(intercomId: string): void {
  void captureIntercomStill({ intercomId, source: "ring" }).catch((err) => {
    logger.warn({ err, id: intercomId }, "intercom ring capture failed");
  });
}
