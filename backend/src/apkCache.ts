/**
 * Local APK cache so tablets download from the NUC, not GitHub, after the
 * first successful fetch. GitHub-before-headers is what closed the Android
 * HTTP client ("Connection closed before full header was received").
 */
import fs from "node:fs";
import path from "node:path";
import { logger } from "./logger";

function cacheDir(): string {
  return process.env.APK_CACHE_DIR?.trim() || "/data/apk-cache";
}

export function apkCacheFile(assetId: number): string {
  return path.join(cacheDir(), `asset-${assetId}.apk`);
}

export function ensureApkCacheDir(): void {
  fs.mkdirSync(cacheDir(), { recursive: true });
}

/** Return a complete cached APK path, or null. */
export function readCachedApk(
  assetId: number,
  sizeBytes: number
): string | null {
  const file = apkCacheFile(assetId);
  try {
    const st = fs.statSync(file);
    if (!st.isFile() || st.size < 1024) return null;
    if (sizeBytes > 0 && st.size !== sizeBytes) return null;
    return file;
  } catch {
    return null;
  }
}

export function pruneApkCache(keepAssetId: number): void {
  let dir: string;
  try {
    dir = cacheDir();
    const names = fs.readdirSync(dir);
    for (const name of names) {
      if (!/^asset-\d+\.apk(\.part)?$/.test(name)) continue;
      if (name.startsWith(`asset-${keepAssetId}.`)) continue;
      try {
        fs.unlinkSync(path.join(dir, name));
      } catch {
        /* ignore */
      }
    }
  } catch (err) {
    logger.warn({ err }, "APK-cache opruimen mislukt");
  }
}
