/**
 * Fetch the newest software stand from GitHub (Releases, else Tags).
 * Cached in-memory so clients polling /api/version do not hit GitHub every time.
 */
import { logger } from "./logger";
import {
  appVersionInfo,
  parseVersion,
  type AppVersionInfo
} from "./version";

/** Android APK attached to a GitHub Release (private-repo safe via API URL). */
export interface GithubAndroidApkInfo {
  id: number;
  name: string;
  sizeBytes: number;
  /** GitHub API asset URL — requires Accept: application/octet-stream + token. */
  apiUrl: string;
}

export interface GithubLatestInfo extends AppVersionInfo {
  tag: string;
  htmlUrl: string | null;
  source: "release" | "tag";
  checkedAt: string;
  androidApk: GithubAndroidApkInfo | null;
}

type Cache = {
  atMs: number;
  value: GithubLatestInfo | null;
  error?: string;
};

const CACHE_MS = 60 * 60 * 1000; // 1 hour
let cache: Cache | null = null;
let inflight: Promise<GithubLatestInfo | null> | null = null;

function githubRepo(): string {
  return (
    process.env.GITHUB_REPO?.trim() ||
    "Archie-Automation/visualisatie"
  );
}

function githubToken(): string | undefined {
  const t = process.env.GITHUB_TOKEN?.trim();
  return t || undefined;
}

function headers(): Record<string, string> {
  const h: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "archie-os-version-check",
    "X-GitHub-Api-Version": "2022-11-28"
  };
  const token = githubToken();
  if (token) h.Authorization = `Bearer ${token}`;
  return h;
}

function stripV(tag: string): string {
  return tag.trim().replace(/^v/i, "");
}

async function ghJson(url: string): Promise<{ ok: boolean; status: number; body: unknown }> {
  const res = await fetch(url, { headers: headers() });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { ok: res.ok, status: res.status, body };
}

function pickAndroidApk(assets: unknown): GithubAndroidApkInfo | null {
  if (!Array.isArray(assets)) return null;
  const apks: GithubAndroidApkInfo[] = [];
  for (const item of assets) {
    if (!item || typeof item !== "object") continue;
    const a = item as Record<string, unknown>;
    const name = typeof a.name === "string" ? a.name : "";
    if (!name.toLowerCase().endsWith(".apk")) continue;
    const id = typeof a.id === "number" ? a.id : Number(a.id);
    const apiUrl = typeof a.url === "string" ? a.url : "";
    const sizeBytes =
      typeof a.size === "number" ? a.size : Number(a.size) || 0;
    if (!Number.isFinite(id) || !apiUrl) continue;
    apks.push({ id, name, sizeBytes, apiUrl });
  }
  if (apks.length === 0) return null;
  const preferred =
    apks.find((a) => /luxe|knx|app-release|release/i.test(a.name)) ?? apks[0];
  return preferred;
}

function infoFromTag(
  tag: string,
  htmlUrl: string | null,
  source: "release" | "tag",
  androidApk: GithubAndroidApkInfo | null = null
): GithubLatestInfo {
  const parsed = parseVersion(stripV(tag));
  return {
    ...parsed,
    tag,
    htmlUrl,
    source,
    checkedAt: new Date().toISOString(),
    androidApk
  };
}

async function fetchLatestUncached(): Promise<GithubLatestInfo | null> {
  const repo = githubRepo();
  if (!repo || !repo.includes("/")) {
    logger.warn({ repo }, "GITHUB_REPO ongeldig — GitHub-versiecheck uit");
    return null;
  }

  const releaseUrl = `https://api.github.com/repos/${repo}/releases/latest`;
  const rel = await ghJson(releaseUrl);
  if (rel.ok && rel.body && typeof rel.body === "object") {
    const b = rel.body as Record<string, unknown>;
    const tag = typeof b.tag_name === "string" ? b.tag_name : "";
    if (tag) {
      const htmlUrl = typeof b.html_url === "string" ? b.html_url : null;
      const androidApk = pickAndroidApk(b.assets);
      return infoFromTag(tag, htmlUrl, "release", androidApk);
    }
  }
  if (rel.status !== 404) {
    logger.warn(
      { status: rel.status, repo },
      "GitHub releases/latest mislukt — probeer tags"
    );
  } else {
    logger.info(
      { repo },
      "Geen GitHub release (404). Bij privé-repo: zet GITHUB_TOKEN in docker/.env"
    );
  }

  const tagsUrl = `https://api.github.com/repos/${repo}/tags?per_page=30`;
  const tags = await ghJson(tagsUrl);
  if (!tags.ok || !Array.isArray(tags.body)) {
    logger.warn(
      {
        status: tags.status,
        repo,
        hint:
          tags.status === 404
            ? "Repo privé of onbekend — GITHUB_TOKEN of GITHUB_REPO controleren"
            : undefined
      },
      "GitHub tags ophalen mislukt — geen latest-versie"
    );
    return null;
  }

  let best: GithubLatestInfo | null = null;
  for (const item of tags.body) {
    if (!item || typeof item !== "object") continue;
    const name = (item as { name?: string }).name;
    if (!name || typeof name !== "string") continue;
    // Skip non-semver-ish tags
    if (!/^v?\d+\.\d+/i.test(name.trim())) continue;
    const cand = infoFromTag(
      name,
      `https://github.com/${repo}/releases/tag/${encodeURIComponent(name)}`,
      "tag"
    );
    if (!best || compareVersion(best, cand) < 0) best = cand;
  }
  return best;
}

/** Positive if b is newer than a. */
export function compareVersion(a: AppVersionInfo, b: AppVersionInfo): number {
  const pa = a.semver.split(".").map((x) => parseInt(x, 10) || 0);
  const pb = b.semver.split(".").map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d > 0 ? 1 : -1;
  }
  const ab = a.build ?? 0;
  const bb = b.build ?? 0;
  if (ab === bb) return 0;
  return ab > bb ? 1 : -1;
}

export async function getGithubLatest(
  force = false
): Promise<GithubLatestInfo | null> {
  const now = Date.now();
  if (!force && cache && now - cache.atMs < CACHE_MS) {
    return cache.value;
  }
  if (!force && inflight) return inflight;

  inflight = (async () => {
    try {
      const value = await fetchLatestUncached();
      cache = { atMs: Date.now(), value };
      return value;
    } catch (err) {
      logger.warn({ err }, "GitHub latest ophalen mislukt");
      cache = {
        atMs: Date.now(),
        value: cache?.value ?? null,
        error: err instanceof Error ? err.message : String(err)
      };
      return cache.value;
    } finally {
      inflight = null;
    }
  })();

  return inflight;
}

export function isUpdateAvailableOnGithub(
  latest: GithubLatestInfo | null
): boolean {
  if (!latest) return false;
  return compareVersion(appVersionInfo, latest) < 0;
}

/** Stream the latest release APK from GitHub (uses GITHUB_TOKEN for private repos). */
export async function fetchAndroidApkFromGithub(): Promise<{
  ok: true;
  name: string;
  sizeBytes: number;
  body: ReadableStream<Uint8Array>;
} | { ok: false; status: number; error: string }> {
  const latest = await getGithubLatest();
  const apk = latest?.androidApk;
  if (!apk) {
    return { ok: false, status: 404, error: "no_android_apk_on_latest_release" };
  }

  const res = await fetch(apk.apiUrl, {
    headers: {
      ...headers(),
      Accept: "application/octet-stream"
    },
    redirect: "follow"
  });
  if (!res.ok || !res.body) {
    logger.warn(
      { status: res.status, assetId: apk.id, name: apk.name },
      "GitHub APK-download mislukt"
    );
    return {
      ok: false,
      status: 502,
      error: `github_apk_download_failed_${res.status}`
    };
  }

  return {
    ok: true,
    name: apk.name,
    sizeBytes: apk.sizeBytes,
    body: res.body as ReadableStream<Uint8Array>
  };
}
