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

export interface GithubLatestInfo extends AppVersionInfo {
  tag: string;
  htmlUrl: string | null;
  source: "release" | "tag";
  checkedAt: string;
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
    "User-Agent": "luxe-knx-version-check",
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

function infoFromTag(
  tag: string,
  htmlUrl: string | null,
  source: "release" | "tag"
): GithubLatestInfo {
  const parsed = parseVersion(stripV(tag));
  return {
    ...parsed,
    tag,
    htmlUrl,
    source,
    checkedAt: new Date().toISOString()
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
      return infoFromTag(tag, htmlUrl, "release");
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
