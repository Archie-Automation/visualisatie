/**
 * Software version embedded at image/build time via APP_VERSION
 * (e.g. "0.2.0+48"). Falls back to package.json version when unset.
 */
import fs from "node:fs";
import path from "node:path";

export interface AppVersionInfo {
  /** Full string, e.g. "0.2.0+48" or "0.2.0". */
  version: string;
  /** Semantic part before '+', if present. */
  semver: string;
  /** Build counter after '+', or null when absent. */
  build: number | null;
}

export function parseVersion(raw: string): AppVersionInfo {
  const version = raw.trim() || "0.0.0";
  const plus = version.indexOf("+");
  if (plus < 0) {
    return { version, semver: version, build: null };
  }
  const semver = version.slice(0, plus);
  const buildRaw = version.slice(plus + 1);
  const build = /^\d+$/.test(buildRaw) ? Number(buildRaw) : null;
  return { version, semver, build };
}

function readPackageVersion(): string | null {
  try {
    const pkgPath = path.join(__dirname, "..", "package.json");
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf-8")) as {
      version?: string;
    };
    return pkg.version?.trim() || null;
  } catch {
    return null;
  }
}

function readVersionFile(): string | null {
  const p = process.env.APP_VERSION_FILE?.trim();
  if (!p) return null;
  try {
    return fs.readFileSync(p, "utf-8").trim() || null;
  } catch {
    return null;
  }
}

/** Resolved once at process start. */
export const appVersionInfo: AppVersionInfo = parseVersion(
  process.env.APP_VERSION?.trim() ||
    readVersionFile() ||
    readPackageVersion() ||
    "0.0.0"
);
