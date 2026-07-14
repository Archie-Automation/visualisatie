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
export const SNAP_FRESH_MS = 3_000;
/** Return stale frames while a slow refresh is in-flight. */
export const SNAP_STALE_MS = 120_000;

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
      "-rtsp_transport",
      "tcp",
      "-i",
      rtspUrl,
      "-frames:v",
      "1",
      ...(scaleWidth ? ["-vf", `scale=${width}:-1`] : []),
      "-q:v",
      "8",
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
    let buf: Buffer | null = null;

    // Synology NVR streams are more reliable via direct ffmpeg than go2rtc's
    // ffmpeg wrapper (Voordeur often fails there entirely).
    if (kind === "camera" && rtsp) {
      const width =
        target.type === "camera" ? snapshotScaleWidth(target.camera) : 720;
      buf = await captureSnapshotFfmpeg(rtsp, { width });
    }

    if (!buf) {
      const p = cameraPath(target);
      const url = `${mediaBase}/api/frame.jpeg?src=${encodeURIComponent(p)}`;
      buf = await fetchSnapshotFromGo2rtc(url, 10_000);
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
        await new Promise<void>((r) => setTimeout(r, 1_500));
      }
    }

    if (!stopped) {
      timer = setTimeout(() => void tick(), 8_000);
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
  res.setHeader("cache-control", age < SNAP_FRESH_MS ? "public, max-age=2" : "no-store");
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

/** Keep go2rtc producers warm so opening live view does not wait on cold RTSP. */
export function startGo2rtcStreamKeeper(
  getConfig: () => HouseConfig,
  mediaBase: () => string
): () => void {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | null = null;

  const tick = async () => {
    if (stopped) return;
    const base = mediaBase();
    for (const cam of collectCameras(getConfig())) {
      if (stopped) break;
      const p = cameraPath(cam);
      await warmGo2rtcProducer(base, p, { retries: 2, timeoutMs: 15_000 }).catch(
        () => false
      );
      await new Promise<void>((r) => setTimeout(r, 2_500));
    }
    if (!stopped) timer = setTimeout(() => void tick(), 15_000);
  };

  timer = setTimeout(() => void tick(), 3_000);

  return () => {
    stopped = true;
    if (timer) clearTimeout(timer);
  };
}
