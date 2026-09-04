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
  /** pubspec version baked into this APK (release title), if known. */
  version?: string;
}

export interface GithubLatestInfo extends AppVersionInfo {
  tag: string;
  htmlUrl: string | null;
  source: "release" | "tag" | "branch";
  checkedAt: string;
  androidApk: GithubAndroidApkInfo | null;
}

type Cache = {
  atMs: number;
  value: GithubLatestInfo | null;
  error?: string;
};

const CACHE_MS = 2 * 60 * 1000; // 2 min — a git push must show up on the tablet quickly
const ANDROID_LATEST_TAG = "android-latest";
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
  let res = await fetch(url, { headers: headers() });

  // If the token caused a 401/403, retry without auth (for public repos or
  // when the stored token is expired). A missing token is the most common
  // cause of "GitHub ophalen mislukt" on an otherwise healthy network.
  if ((res.status === 401 || res.status === 403) && githubToken()) {
    logger.warn(
      { status: res.status, url },
      "GitHub token geweigerd – opnieuw zonder token (publieke repo)"
    );
    const anonHeaders: Record<string, string> = {
      Accept: "application/vnd.github+json",
      "User-Agent": "archie-os-version-check",
      "X-GitHub-Api-Version": "2022-11-28"
    };
    res = await fetch(url, { headers: anonHeaders });
  }

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
    apks.find((a) => /archie|luxe|knx|app-release|release/i.test(a.name)) ??
    apks[0];
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

function versionRawFromRelease(b: Record<string, unknown>): string | null {
  const name = typeof b.name === "string" ? b.name.trim() : "";
  const tag = typeof b.tag_name === "string" ? b.tag_name.trim() : "";
  const notes = typeof b.body === "string" ? b.body.trim() : "";
  if (/^v?\d+\.\d+/i.test(name)) return stripV(name);
  const embedded =
    name.match(/(\d+\.\d+\.\d+\+\d+)/) ?? notes.match(/(\d+\.\d+\.\d+\+\d+)/);
  if (embedded) return embedded[1];
  if (/^v?\d+\.\d+/i.test(tag)) return stripV(tag);
  return null;
}

function infoFromRelease(
  b: Record<string, unknown>,
  source: GithubLatestInfo["source"]
): GithubLatestInfo | null {
  const raw = versionRawFromRelease(b);
  if (!raw) return null;
  const tag =
    (typeof b.tag_name === "string" && b.tag_name.trim()) || raw;
  const htmlUrl = typeof b.html_url === "string" ? b.html_url : null;
  const parsed = parseVersion(raw);
  return {
    ...parsed,
    tag,
    htmlUrl,
    source,
    checkedAt: new Date().toISOString(),
    androidApk: pickAndroidApk(b.assets)
  };
}

function pickNewer(
  a: GithubLatestInfo | null,
  b: GithubLatestInfo | null
): GithubLatestInfo | null {
  if (!a) return b;
  if (!b) return a;
  return compareVersion(a, b) < 0 ? b : a;
}

async function fetchBranchPubspec(repo: string): Promise<GithubLatestInfo | null> {
  for (const ref of ["main", "master"] as const) {
    const url = `https://api.github.com/repos/${repo}/contents/app/pubspec.yaml?ref=${ref}`;
    const res = await fetch(url, {
      headers: { ...headers(), Accept: "application/vnd.github.raw" }
    });
    if (!res.ok) continue;
    const text = await res.text();
    const m = text.match(/^version:\s*(\S+)/m);
    if (!m) continue;
    const parsed = parseVersion(m[1]);
    logger.info({ version: parsed.version, ref }, "github: pubspec op default branch");
    return {
      ...parsed,
      tag: parsed.version,
      htmlUrl: `https://github.com/${repo}/blob/${ref}/app/pubspec.yaml`,
      source: "branch",
      checkedAt: new Date().toISOString(),
      androidApk: null
    };
  }
  return null;
}

async function fetchReleaseByTag(
  repo: string,
  tag: string
): Promise<GithubLatestInfo | null> {
  const rel = await ghJson(
    `https://api.github.com/repos/${repo}/releases/tags/${encodeURIComponent(tag)}`
  );
  if (!rel.ok || !rel.body || typeof rel.body !== "object") return null;
  const body = rel.body as Record<string, unknown>;
  const apk = pickAndroidApk(body.assets);
  const parsed = infoFromRelease(body, "release");
  if (parsed) return { ...parsed, androidApk: apk };
  if (!apk) return null;
  const htmlUrl = typeof body.html_url === "string" ? body.html_url : null;
  return {
    ...parseVersion("0.0.0"),
    tag,
    htmlUrl,
    source: "release",
    checkedAt: new Date().toISOString(),
    androidApk: apk
  };
}

/** Rolling `android-latest` is the only APK channel. Official GitHub
 *  "latest" often still has an old debug-signed build (downgrade +
 *  signature mismatch → Android "App niet geïnstalleerd"). */
function apkFromRolling(
  rolling: GithubLatestInfo | null
): GithubAndroidApkInfo | null {
  const apk = rolling?.androidApk;
  if (!apk) return null;
  const labeled =
    rolling && rolling.semver !== "0.0.0"
      ? { ...apk, version: rolling.version }
      : apk;
  if (labeled.version) {
    const ver = parseVersion(labeled.version);
    if (compareVersion(ver, appVersionInfo) < 0) {
      logger.warn(
        { apk: labeled.version, running: appVersionInfo.version },
        "APK op GitHub is ouder dan de server — niet aanbieden"
      );
      return null;
    }
  }
  return labeled;
}

async function fetchLatestUncached(): Promise<GithubLatestInfo | null> {
  const repo = githubRepo();
  if (!repo || !repo.includes("/")) {
    logger.warn({ repo }, "GITHUB_REPO ongeldig — GitHub-versiecheck uit");
    return null;
  }

  const branch = await fetchBranchPubspec(repo);
  const rolling = await fetchReleaseByTag(repo, ANDROID_LATEST_TAG);

  const releaseUrl = `https://api.github.com/repos/${repo}/releases/latest`;
  const rel = await ghJson(releaseUrl);
  let official: GithubLatestInfo | null = null;
  if (rel.ok && rel.body && typeof rel.body === "object") {
    official = infoFromRelease(rel.body as Record<string, unknown>, "release");
  } else if (rel.status !== 404) {
    logger.warn(
      { status: rel.status, repo },
      "GitHub releases/latest mislukt"
    );
  } else if (!githubToken()) {
    logger.info(
      { repo },
      "Geen GitHub release (404). Bij privé-repo: zet GITHUB_TOKEN in docker/.env"
    );
  }

  const newest = pickNewer(pickNewer(branch, official), rolling);
  if (!newest) {
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
      if (!/^v?\d+\.\d+/i.test(name.trim())) continue;
      const cand = infoFromTag(
        name,
        `https://github.com/${repo}/releases/tag/${encodeURIComponent(name)}`,
        "tag"
      );
      best = pickNewer(best, cand);
    }
    return best;
  }

  // Offer the newest APK even if CI lags a git push. Hiding it left tablets
  // stuck on an old build (e.g. +186) while the NUC already ran a newer pubspec.
  const apkUsable = apkFromRolling(rolling);

  return {
    ...newest,
    androidApk: apkUsable,
    checkedAt: new Date().toISOString()
  };
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
      const msg = err instanceof Error ? err.message : String(err);
      const isNetworkErr =
        msg.includes("ENOTFOUND") ||
        msg.includes("ECONNREFUSED") ||
        msg.includes("fetch failed") ||
        msg.includes("network");
      logger.warn(
        { err, hint: isNetworkErr ? "netwerk" : "onbekend" },
        isNetworkErr
          ? "GitHub latest ophalen mislukt – geen netwerktoegang tot api.github.com"
          : "GitHub latest ophalen mislukt – onbekende fout"
      );
      cache = {
        atMs: Date.now(),
        value: cache?.value ?? null,
        error: msg
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

  const apkHeaders = {
    ...headers(),
    Accept: "application/octet-stream"
  };
  let res = await fetch(apk.apiUrl, { headers: apkHeaders, redirect: "follow" });

  // Expired / wrong token → retry anonymously (only works for public repos).
  if ((res.status === 401 || res.status === 403) && githubToken()) {
    logger.warn(
      { status: res.status, assetId: apk.id, name: apk.name },
      "GitHub APK-download: token geweigerd – opnieuw zonder token"
    );
    res = await fetch(apk.apiUrl, {
      headers: { Accept: "application/octet-stream", "User-Agent": "archie-os-version-check" },
      redirect: "follow"
    });
  }

  if (!res.ok || !res.body) {
    const hint =
      res.status === 401 || res.status === 403
        ? "Controleer GITHUB_TOKEN in docker/.env (token verlopen of onvoldoende rechten)"
        : res.status === 404
        ? "APK-asset niet gevonden op release 'android-latest'"
        : undefined;
    logger.warn(
      { status: res.status, assetId: apk.id, name: apk.name, hint },
      "GitHub APK-download mislukt"
    );
    return {
      ok: false,
      status: res.status === 404 ? 404 : 502,
      error: hint
        ? `github_apk_download_failed_${res.status}: ${hint}`
        : `github_apk_download_failed_${res.status}`
    };
  }

  return {
    ok: true,
    name: apk.name,
    sizeBytes: apk.sizeBytes,
    body: res.body as ReadableStream<Uint8Array>
  };
}
