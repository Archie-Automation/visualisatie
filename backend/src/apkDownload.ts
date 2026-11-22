/**
 * Eén GitHub-download voor alle tablets. De response krijgt bytes zodra ze
 * op schijf staan, en een volgende installatie leest de cache.
 * Geen tweede lezer op dezelfde GitHub-stream: dat laat chunks vallen.
 */
import fs from "node:fs";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import type { Response } from "express";
import {
  apkCacheFile,
  ensureApkCacheDir,
  pruneApkCache,
  readCachedApk
} from "./apkCache";
import { apkVersionLabel, readApkIdentity } from "./apkIdentity";
import { fetchAndroidApkFromGithub, getGithubLatest } from "./githubLatest";
import type { UpdateChannel } from "./githubLatest";
import { logger } from "./logger";

type Job = {
  id: number;
  name: string;
  sizeBytes: number;
  tmp: string;
  dest: string;
  received: number;
  lastByteAt: number;
  ok: boolean;
  failed: boolean;
  settled: boolean;
};

let job: Job | null = null;
const versionMemo = new Map<string, string | null>();

/** Versie uit de bytes op schijf. Geen cache-hit: nog niet bekend, niet gokken. */
export function cachedApkVersionLabel(
  assetId: number,
  sizeBytes: number
): string | null {
  const key = `${assetId}:${sizeBytes}`;
  if (versionMemo.has(key)) return versionMemo.get(key) ?? null;
  const file = readCachedApk(assetId, sizeBytes);
  if (!file) return null;
  try {
    const id = readApkIdentity(fs.readFileSync(file));
    const label = id ? apkVersionLabel(id) : null;
    if (!label) logger.warn({ assetId }, "APK-versie niet leesbaar uit het bestand");
    else logger.info({ assetId, version: label }, "APK-versie uit het bestand");
    versionMemo.set(key, label);
    return label;
  } catch (err) {
    logger.warn({ err, assetId }, "APK-versie lezen mislukt");
    versionMemo.set(key, null);
    return null;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function warmAndroidApk(channel: UpdateChannel): void {
  void (async () => {
    const latest = await getGithubLatest(false, channel);
    const meta = latest?.androidApk;
    if (!meta) return;
    if (readCachedApk(meta.id, meta.sizeBytes)) return;
    startJob(meta.id, meta.name, meta.sizeBytes, channel);
  })().catch((err) => {
    logger.warn({ err }, "APK-voorraad starten mislukt");
  });
}

function startJob(
  id: number,
  name: string,
  sizeBytes: number,
  channel: UpdateChannel
): Job {
  if (job && job.id === id && !job.settled) return job;
  ensureApkCacheDir();
  pruneApkCache(id);
  const dest = apkCacheFile(id);
  const tmp = `${dest}.part`;
  try {
    fs.unlinkSync(tmp);
  } catch {
    /* ignore */
  }
  const created: Job = {
    id,
    name,
    sizeBytes,
    tmp,
    dest,
    received: 0,
    lastByteAt: Date.now(),
    ok: false,
    failed: false,
    settled: false
  };
  job = created;
  void runJob(created, channel);
  return created;
}

async function runJob(created: Job, channel: UpdateChannel): Promise<void> {
  const fileOut = fs.createWriteStream(created.tmp);
  try {
    const result = await fetchAndroidApkFromGithub(channel);
    if (!result.ok || result.id !== created.id) {
      throw new Error(result.ok ? "apk asset wisselde" : result.error);
    }
    if (result.sizeBytes > 0) created.sizeBytes = result.sizeBytes;
    const github = Readable.fromWeb(result.body);
    const count = new Transform({
      transform(chunk: Buffer, _enc, cb) {
        created.received += chunk.length;
        created.lastByteAt = Date.now();
        cb(null, chunk);
      }
    });
    created.lastByteAt = Date.now();
    const stall = setInterval(() => {
      if (created.settled) return;
      if (Date.now() - created.lastByteAt < 45_000) return;
      github.destroy(new Error("apk stream stalled"));
    }, 5_000);
    try {
      await pipeline(github, count, fileOut);
    } finally {
      clearInterval(stall);
    }
    if (created.sizeBytes > 0 && created.received !== created.sizeBytes) {
      throw new Error(
        `apk onvolledig ${created.received}/${created.sizeBytes}`
      );
    }
    fs.renameSync(created.tmp, created.dest);
    created.ok = true;
  } catch (err) {
    created.failed = true;
    logger.warn({ err, assetId: created.id }, "APK-voorraad mislukt");
    try {
      fileOut.destroy();
    } catch {
      /* ignore */
    }
    try {
      fs.unlinkSync(created.tmp);
    } catch {
      /* ignore */
    }
  } finally {
    created.settled = true;
    if (!created.ok) {
      fileOut.destroy();
    }
  }
}

function sendHeaders(res: Response, name: string, size: number): void {
  res.setHeader("Content-Type", "application/vnd.android.package-archive");
  res.setHeader(
    "Content-Disposition",
    `attachment; filename="${name.replace(/"/g, "")}"`
  );
  if (size > 0) res.setHeader("Content-Length", String(size));
  res.flushHeaders();
}

async function pipeFile(res: Response, file: string, name: string, size: number): Promise<void> {
  sendHeaders(res, name, size);
  await new Promise<void>((resolve, reject) => {
    const stream = fs.createReadStream(file);
    const fail = (err: Error) => reject(err);
    stream.on("error", fail);
    res.on("error", fail);
    res.on("finish", () => resolve());
    stream.pipe(res);
  });
}

async function readSlice(file: string, start: number, end: number): Promise<Buffer> {
  const fh = await fs.promises.open(file, "r");
  try {
    const len = end - start + 1;
    const buf = Buffer.alloc(len);
    const { bytesRead } = await fh.read(buf, 0, len, start);
    return buf.subarray(0, bytesRead);
  } finally {
    await fh.close();
  }
}

function fileSize(file: string): number {
  try {
    return fs.statSync(file).size;
  } catch {
    return 0;
  }
}

async function tailJob(res: Response, created: Job): Promise<void> {
  const started = Date.now();
  while (created.received === 0 && !created.ok && !created.failed) {
    if (Date.now() - started > 90_000) {
      res.status(504).json({ error: "github_apk_timeout" });
      return;
    }
    await sleep(200);
  }
  if (created.failed && !fs.existsSync(created.dest)) {
    res.status(502).json({ error: "apk_download_failed" });
    return;
  }

  let closed = false;
  res.on("close", () => {
    closed = true;
  });
  sendHeaders(res, created.name, created.sizeBytes);
  let offset = 0;
  let lastSentAt = Date.now();
  while (!closed) {
    const path = fs.existsSync(created.dest) ? created.dest : created.tmp;
    const size = fileSize(path);
    if (size > offset) {
      const chunk = await readSlice(path, offset, size - 1);
      if (chunk.length === 0) {
        await sleep(150);
        continue;
      }
      offset += chunk.length;
      lastSentAt = Date.now();
      const ok = res.write(chunk);
      if (!ok) {
        await new Promise<void>((resolve) => res.once("drain", () => resolve()));
      }
    }
    const complete =
      created.ok &&
      fs.existsSync(created.dest) &&
      offset >= fileSize(created.dest) &&
      (created.sizeBytes <= 0 || offset >= created.sizeBytes);
    if (complete) {
      res.end();
      return;
    }
    if (created.failed && offset >= created.received) {
      res.destroy();
      return;
    }
    if (!created.ok && Date.now() - lastSentAt > 45_000 && size <= offset) {
      logger.warn({ offset, assetId: created.id }, "APK naar tablet stilgevallen");
      res.destroy();
      return;
    }
    if (Date.now() - started > 10 * 60 * 1000) {
      res.destroy();
      return;
    }
    await sleep(200);
  }
}

export async function sendAndroidApk(res: Response, channel: UpdateChannel): Promise<void> {
  const latest = await getGithubLatest(false, channel);
  const meta = latest?.androidApk;
  if (!meta) {
    res.status(404).json({ error: "no_android_apk_on_latest_release" });
    return;
  }
  const downloadName = `archie-os-${meta.id}.apk`;
  const cached = readCachedApk(meta.id, meta.sizeBytes);
  if (cached) {
    await pipeFile(res, cached, downloadName, fs.statSync(cached).size);
    return;
  }
  const created = startJob(meta.id, downloadName, meta.sizeBytes, channel);
  await tailJob(res, created);
}
