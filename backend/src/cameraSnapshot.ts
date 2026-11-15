import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { logger } from "./logger";
import type { CameraDevice, IntercomDevice } from "./types";
import { cameraPath, collectCameras, collectIntercoms } from "./cameras";
import { snapshotRtspForCamera, snapshotScaleWidth } from "./cameraSource";
import type { HouseConfig } from "./types";

export type SnapshotCacheEntry = { buf: Buffer; ts: number };

export const snapshotCache = new Map<string, SnapshotCacheEntry>();

/** Serve cached JPEG without re-fetching from upstream. */
export const SNAP_FRESH_MS = 10_000;
/** Return stale frames while a slow refresh is in-flight. */
export const SNAP_STALE_MS = 120_000;
/** Same JPEG this many times, and at least SNAP_FREEZE_MS apart, before we probe. */
export const SNAP_FREEZE_HITS = 3;
/** go2rtc can keep serving one keyframe while the camera's own app is still live. */
export const SNAP_FREEZE_MS = 90_000;
/** Don't open a second RTSP session again until this long after a probe. */
export const SNAP_FREEZE_COOLDOWN_MS = 5 * 60_000;

export type SnapshotFreeze = {
  hash: string;
  since: number;
  hits: number;
  kickedAt: number;
};

/**
 * Identical bytes across several refreshes means go2rtc is repeating one
 * keyframe. A static live scene can do that too, so this only decides when
 * to spend one direct RTSP grab as a second opinion.
 */
export function noteSnapshotFrame(
  state: SnapshotFreeze | undefined,
  hash: string,
  now: number
): { state: SnapshotFreeze; probe: boolean } {
  if (state && state.hash === hash) {
    const hits = state.hits + 1;
    const probe =
      hits >= SNAP_FREEZE_HITS &&
      now - state.since >= SNAP_FREEZE_MS &&
      now - state.kickedAt >= SNAP_FREEZE_COOLDOWN_MS;
    return {
      state: {
        hash,
        since: state.since,
        hits,
        kickedAt: probe ? now : state.kickedAt
      },
      probe
    };
  }
  return {
    state: { hash, since: now, hits: 1, kickedAt: state?.kickedAt ?? 0 },
    probe: false
  };
}

/**
 * A new direct RTSP frame that differs from the repeated JPEG proves the
 * go2rtc session is stale. The same bytes from a fresh connection means the
 * source itself is still on that picture, so restarting the session won't help.
 */
export function classifyFrozenSnapshot(
  directHash: string | null,
  cachedHash: string
): "stale-session" | "source-frozen" | "direct-failed" {
  if (!directHash) return "direct-failed";
  if (directHash !== cachedHash) return "stale-session";
  return "source-frozen";
}

const freezeState = new Map<string, SnapshotFreeze>();

function hashSnapshot(buf: Buffer): string {
  return createHash("sha1").update(buf).digest("hex");
}

const refreshInFlight = new Set<string>();

/** Resolve ffmpeg binary (same search order as go2rtc yaml generation). */
export function resolveFfmpegBin(): string | null {
  const raw =
    process.env.FFMPEG_PATH?.trim() ||
    process.env.GO2RTC_FFMPEG_BIN?.trim();
  if (raw) {
    const abs = path.isAbsolute(raw) ? raw : path.resolve(process.cwd(), raw);
    if (fs.existsSync(abs)) return abs;
  }
  const toolsGuess = path.resolve(
    process.cwd(),
    "..",
    "tools",
    process.platform === "win32" ? "ffmpeg.exe" : "ffmpeg"
  );
  if (fs.existsSync(toolsGuess)) return toolsGuess;
  const usrBin = "/usr/bin/ffmpeg";
  if (fs.existsSync(usrBin)) return usrBin;
  return null;
}

/** Grab one scaled JPEG frame straight from RTSP. */
export async function captureSnapshotFfmpeg(
  rtspUrl: string,
  opts: { width?: number; timeoutMs?: number } = {}
): Promise<Buffer | null> {
  const ffmpegBin = resolveFfmpegBin();
  if (!ffmpegBin) return null;

  const width = opts.width ?? 720;
  const timeoutMs = opts.timeoutMs ?? 12_000;
  const scaleWidth = width > 0;

  return new Promise((resolve) => {
    const args = [
      "-hide_banner",
      "-loglevel",
      "error",
      "-fflags",
      "+genpts+nobuffer+discardcorrupt",
      "-flags",
      "low_delay",
      "-analyzeduration",
      "500000",
      "-probesize",
      "500000",
      "-rtsp_transport",
      "tcp",
      "-i",
      rtspUrl,
      "-an",
      "-frames:v",
      "1",
      ...(scaleWidth ? ["-vf", `scale=${width}:-1`] : []),
      "-q:v",
      "5",
      "-f",
      "image2",
      "pipe:1"
    ];
    const proc = spawn(ffmpegBin, args, { windowsHide: true });
    const chunks: Buffer[] = [];
    let settled = false;
    const finish = (buf: Buffer | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(buf);
    };
    const timer = setTimeout(() => {
      try {
        proc.kill("SIGTERM");
      } catch {
        /* ignore */
      }
      finish(null);
    }, timeoutMs);

    proc.stdout?.on("data", (c: Buffer) => chunks.push(c));
    proc.on("close", (code) => {
      if (code !== 0 || chunks.length === 0) return finish(null);
      finish(Buffer.concat(chunks));
    });
    proc.on("error", () => finish(null));
  });
}

async function fetchSnapshotFromGo2rtc(
  url: string,
  timeoutMs: number
): Promise<Buffer | null> {
  try {
    const upstream = await fetch(url, {
      signal: AbortSignal.timeout(timeoutMs)
    });
    if (!upstream.ok) return null;
    const buf = Buffer.from(await upstream.arrayBuffer());
    return buf.length > 0 ? buf : null;
  } catch {
    return null;
  }
}

function rawRtspUrl(d: CameraDevice | IntercomDevice): string | null {
  if (d.type === "camera") return snapshotRtspForCamera(d.camera);
  const rtsp = d.intercom.rtsp?.trim();
  if (!rtsp || !/^rtsps?:\/\//i.test(rtsp)) return null;
  return rtsp;
}

/** Fetch one snapshot for a camera/intercom and update the shared cache. */
export async function refreshSnapshotCache(
  kind: "camera" | "intercom",
  target: CameraDevice | IntercomDevice,
  mediaBase: string
): Promise<Buffer | null> {
  const cacheKey = `${kind}:${target.id}`;
  if (refreshInFlight.has(cacheKey)) return snapshotCache.get(cacheKey)?.buf ?? null;
  refreshInFlight.add(cacheKey);

  try {
    const rtsp = rawRtspUrl(target);
    const p = cameraPath(target);
    const url = `${mediaBase}/api/frame.jpeg?src=${encodeURIComponent(p)}`;
    const width =
      target.type === "camera" ? snapshotScaleWidth(target.camera) : 720;

    // Synology stuurt een keyframe eens per paar seconden. Eerder afkappen
    // start een tweede RTSP-kijker en maakt het juist trager.
    let buf = await fetchSnapshotFromGo2rtc(url, 6_000);
    // Een intercom (DoorBird) heeft vaak maar één RTSP-kijker. Een tweede
    // ffmpeg naast de live-stream duwt het beeld weg en maakt het traag.
    if (!buf && rtsp && target.type === "camera") {
      buf = await captureSnapshotFfmpeg(rtsp, { width, timeoutMs: 8_000 });
    }
    if (!buf) {
      buf = await fetchSnapshotFromGo2rtc(url, 8_000);
    }

    if (buf && target.type === "camera") {
      const now = Date.now();
      const hash = hashSnapshot(buf);
      const noted = noteSnapshotFrame(freezeState.get(cacheKey), hash, now);
      freezeState.set(cacheKey, noted.state);
      if (noted.probe && rtsp) {
        const live = await captureSnapshotFfmpeg(rtsp, { width, timeoutMs: 8_000 });
        const verdict = classifyFrozenSnapshot(
          live ? hashSnapshot(live) : null,
          hash
        );
        logger.warn(
          { cacheKey, verdict, hits: noted.state.hits },
          "camerabeeld staat stil"
        );
        if (verdict === "stale-session" && live) {
          buf = live;
          freezeState.set(cacheKey, {
            hash: hashSnapshot(live),
            since: now,
            hits: 1,
            kickedAt: now
          });
        }
        if (verdict !== "source-frozen") {
          void bounceGo2rtcPreload(mediaBase, p).catch((err) => {
            logger.warn({ err, cacheKey }, "go2rtc preload herstart mislukt");
          });
        }
      }
    }

    if (buf) {
      snapshotCache.set(cacheKey, { buf, ts: Date.now() });
    }
    return buf;
  } finally {
    refreshInFlight.delete(cacheKey);
  }
}

function scheduleSnapshotRefresh(
  kind: "camera" | "intercom",
  target: CameraDevice | IntercomDevice,
  mediaBase: string
): void {
  const cacheKey = `${kind}:${target.id}`;
  if (refreshInFlight.has(cacheKey)) return;
  void refreshSnapshotCache(kind, target, mediaBase).catch((err) => {
    logger.debug({ err, cacheKey }, "background snapshot refresh failed");
  });
}

/** Keep thumbnails warm so tablets never wait on a cold ffmpeg/go2rtc start. */
export function startCameraSnapshotWarmer(
  getConfig: () => HouseConfig,
  mediaBase: () => string
): () => void {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | null = null;

  const tick = async () => {
    if (stopped) return;
    const cfg = getConfig();
    const base = mediaBase();
    const targets: Array<{ kind: "camera" | "intercom"; d: CameraDevice | IntercomDevice }> =
      [
        ...collectCameras(cfg).map((d) => ({ kind: "camera" as const, d })),
        ...collectIntercoms(cfg).map((d) => ({ kind: "intercom" as const, d }))
      ];

    for (let i = 0; i < targets.length; i++) {
      if (stopped) break;
      const { kind, d } = targets[i]!;
      await refreshSnapshotCache(kind, d, base).catch(() => null);
      if (i + 1 < targets.length) {
        await new Promise<void>((r) => setTimeout(r, 2_500));
      }
    }

    if (!stopped) {
      timer = setTimeout(() => void tick(), 20_000);
    }
  };

  timer = setTimeout(() => void tick(), 2_000);

  return () => {
    stopped = true;
    if (timer) clearTimeout(timer);
  };
}

export function serveSnapshotFromCache(
  res: import("express").Response,
  _cacheKey: string,
  cached: SnapshotCacheEntry | undefined,
  now: number
): boolean {
  if (!cached) return false;
  const age = now - cached.ts;
  if (age >= SNAP_STALE_MS) return false;

  res.setHeader("content-type", "image/jpeg");
  res.setHeader("cache-control", age < SNAP_FRESH_MS ? "public, max-age=8" : "no-store");
  if (age >= SNAP_FRESH_MS) res.setHeader("x-snapshot-stale", "1");
  res.end(cached.buf);
  return true;
}

export function triggerBackgroundSnapshotRefresh(
  kind: "camera" | "intercom",
  target: CameraDevice | IntercomDevice,
  mediaBase: string,
  cached: SnapshotCacheEntry | undefined,
  now: number
): void {
  if (!cached || now - cached.ts >= SNAP_FRESH_MS) {
    scheduleSnapshotRefresh(kind, target, mediaBase);
  }
}

/**
 * Drop the keep-alive consumer and open it again. That closes a wedged RTSP
 * session so the next viewer gets a new one. go2rtc has no per-stream restart
 * that leaves the config alone; preload delete+put is the narrowest kick.
 */
export async function bounceGo2rtcPreload(
  mediaBase: string,
  streamPath: string
): Promise<void> {
  const base = mediaBase.replace(/\/+$/, "");
  const src = encodeURIComponent(streamPath);
  await fetch(`${base}/api/preload?src=${src}`, { method: "DELETE" }).catch(
    () => undefined
  );
  const res = await fetch(`${base}/api/preload?src=${src}`, { method: "PUT" });
  if (!res.ok) {
    throw new Error(`preload ${res.status}`);
  }
}

/** Warm a go2rtc producer via HLS manifest (less disruptive than frame.jpeg). */
export async function warmGo2rtcProducer(
  mediaBase: string,
  streamPath: string,
  opts: { retries?: number; timeoutMs?: number } = {}
): Promise<boolean> {
  const retries = opts.retries ?? 3;
  const timeoutMs = opts.timeoutMs ?? 20_000;
  const base = mediaBase.replace(/\/+$/, "");
  const url = `${base}/api/stream.m3u8?src=${encodeURIComponent(streamPath)}`;

  for (let attempt = 0; attempt < retries; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
      if (res.ok) {
        const body = await res.text();
        if (body.includes("#EXTM3U")) return true;
      }
    } catch {
      /* Synology SS may reject the first connect */
    }
    if (attempt + 1 < retries) {
      await new Promise<void>((r) => setTimeout(r, 2_000));
    }
  }
  return false;
}
