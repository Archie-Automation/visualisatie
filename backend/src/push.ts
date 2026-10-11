/**
 * Push naar telefoons waarvan de app dicht is (deurbel).
 *
 * De NUC bewaart alleen device-tokens (`data/push.json`). Het versturen loopt
 * via de push-relay op Archie Cloud (`PUSH_RELAY_URL`, standaard de wg-hub),
 * zodat de Firebase-servicesleutel niet op elke NUC staat. De relay herkent de
 * NUC aan zijn WireGuard-adres.
 *
 * Zonder relay (geen Archie Cloud) doet dit niets: de app rinkelt dan alleen
 * zolang hij open staat (WebSocket).
 */
import fs from "node:fs";
import path from "node:path";
import { getConfig } from "./config";
import { logger } from "./logger";
import { remoteUrl, serverId, wgAddress } from "./remoteAccess";
import { listSessions } from "./sessions";

export type PushPlatform = "android" | "ios";

export interface PushToken {
  token: string;
  platform: PushPlatform;
  userId: string;
  /** Sessie (refresh) van het apparaat; afgemeld apparaat = token weg. */
  sessionId?: string;
  updatedAt: string;
}

interface PushStore {
  tokens: PushToken[];
}

const MAX_AGE_DAYS = 400;

function storePath(): string {
  const fromEnv = process.env.PUSH_STORE_PATH?.trim();
  if (fromEnv) return path.resolve(fromEnv);
  const sess = process.env.SESSIONS_STORE_PATH?.trim();
  if (sess) return path.join(path.dirname(path.resolve(sess)), "push.json");
  return path.join(process.cwd(), "data", "push.json");
}

let cache: PushStore | null = null;

function load(): PushStore {
  if (cache) return cache;
  try {
    const parsed = JSON.parse(fs.readFileSync(storePath(), "utf-8")) as PushStore;
    cache = { tokens: Array.isArray(parsed.tokens) ? parsed.tokens : [] };
  } catch {
    cache = { tokens: [] };
  }
  return cache;
}

function save(store: PushStore): void {
  const p = storePath();
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const tmp = `${p}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2) + "\n", "utf-8");
  fs.renameSync(tmp, p);
  cache = store;
}

export function relayUrl(): string | null {
  const explicit = process.env.PUSH_RELAY_URL?.trim();
  if (explicit) return explicit.replace(/\/+$/, "");
  // Standaard: de enroll/push-service op de wg-hub, alleen bereikbaar via de tunnel.
  if (wgAddress()) return "http://10.80.0.1:8090";
  return null;
}

export function pushEnabled(): boolean {
  return relayUrl() != null;
}

export function registerToken(input: {
  token: string;
  platform: PushPlatform;
  userId: string;
  sessionId?: string;
}): void {
  const store = load();
  const now = new Date().toISOString();
  const token = input.token.trim();
  if (!token) return;
  const existing = store.tokens.find((t) => t.token === token);
  if (existing) {
    existing.platform = input.platform;
    existing.userId = input.userId;
    existing.sessionId = input.sessionId ?? existing.sessionId;
    existing.updatedAt = now;
  } else {
    store.tokens.push({ token, platform: input.platform, userId: input.userId, sessionId: input.sessionId, updatedAt: now });
  }
  // Eén token hoort bij één sessie: oude registraties van hetzelfde apparaat opruimen.
  if (input.sessionId) {
    store.tokens = store.tokens.filter((t) => t.token === token || t.sessionId !== input.sessionId);
  }
  save(store);
}

export function unregisterToken(token: string, userId: string | null): boolean {
  const store = load();
  const before = store.tokens.length;
  store.tokens = store.tokens.filter((t) => !(t.token === token.trim() && (userId === null || t.userId === userId)));
  if (store.tokens.length === before) return false;
  save(store);
  return true;
}

export function removeTokens(tokens: string[]): void {
  if (tokens.length === 0) return;
  const set = new Set(tokens);
  const store = load();
  const before = store.tokens.length;
  store.tokens = store.tokens.filter((t) => !set.has(t.token));
  if (store.tokens.length !== before) save(store);
}

/** Alleen tokens van actieve sessies, van ingeschakelde gebruikers die de bel niet stil hebben. */
function activeTokens(userFilter: Set<string> | null): PushToken[] {
  const store = load();
  const cfg = getConfig();
  const sessions = new Set(listSessions(null).map((s) => s.id));
  const now = Date.now();
  const cutoff = now - MAX_AGE_DAYS * 86_400_000;
  const users = new Map((cfg.users ?? []).map((u) => [u.id, u]));
  const out: PushToken[] = [];
  const stale: string[] = [];
  for (const t of store.tokens) {
    if (new Date(t.updatedAt).getTime() < cutoff) {
      stale.push(t.token);
      continue;
    }
    if (t.sessionId && !sessions.has(t.sessionId)) {
      stale.push(t.token);
      continue;
    }
    const u = users.get(t.userId);
    if (!u || u.enabled === false) continue;
    if (userFilter && !userFilter.has(t.userId)) continue;
    const muted = u.doorbellMutedUntil ? Date.parse(u.doorbellMutedUntil) > now : false;
    if (muted) continue;
    out.push(t);
  }
  if (stale.length) removeTokens(stale);
  return out;
}

export interface RingPush {
  intercomId: string;
  name: string;
  ts: number;
  /** Alleen deze gebruikers (belgroep); null = iedereen. */
  userIds?: Set<string> | null;
}

async function send(data: Record<string, string>, userIds: Set<string> | null, ttlSeconds: number): Promise<void> {
  const relay = relayUrl();
  if (!relay) return;
  const tokens = activeTokens(userIds);
  if (tokens.length === 0) return;
  const body = {
    serverId: serverId(),
    ttl: ttlSeconds,
    tokens: tokens.map((t) => ({ token: t.token, platform: t.platform })),
    data
  };
  try {
    const res = await fetch(`${relay}/push/send`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(8000)
    });
    if (!res.ok) {
      logger.warn({ status: res.status, text: (await res.text()).slice(0, 200) }, "push-relay weigerde");
      return;
    }
    const out = (await res.json()) as { sent?: number; invalid?: string[] };
    if (out.invalid?.length) removeTokens(out.invalid);
    logger.info({ type: data["type"], sent: out.sent ?? 0, invalid: out.invalid?.length ?? 0 }, "push verstuurd");
  } catch (err) {
    logger.warn({ err }, "push-relay niet bereikbaar");
  }
}

/** Deurbel: app dicht → CallKit-scherm via push. */
export function pushRing(ring: RingPush): void {
  void send(
    {
      type: "intercom.ring",
      intercomId: ring.intercomId,
      name: ring.name,
      ts: String(ring.ts),
      serverId: serverId() ?? "",
      remoteUrl: remoteUrl() ?? ""
    },
    ring.userIds ?? null,
    30
  );
}

/** Opgenomen/afgebroken: CallKit-scherm op de andere telefoons weghalen. */
export function pushCleared(intercomId: string): void {
  void send({ type: "intercom.cleared", intercomId, serverId: serverId() ?? "" }, null, 20);
}

/** Publieke Firebase-clientconfig voor de app (geen geheim; staat in elke APK). */
let clientConfigCache: { at: number; value: Record<string, string> | null } | null = null;
export async function pushClientConfig(): Promise<Record<string, string> | null> {
  const fromEnv = process.env.FCM_CLIENT_CONFIG?.trim();
  if (fromEnv) {
    try {
      return JSON.parse(fromEnv) as Record<string, string>;
    } catch {
      logger.warn("FCM_CLIENT_CONFIG is geen geldige JSON");
    }
  }
  const relay = relayUrl();
  if (!relay) return null;
  if (clientConfigCache && Date.now() - clientConfigCache.at < 10 * 60_000) return clientConfigCache.value;
  try {
    const res = await fetch(`${relay}/push/config`, { signal: AbortSignal.timeout(5000) });
    const value = res.ok ? ((await res.json()) as Record<string, string>) : null;
    clientConfigCache = { at: Date.now(), value };
    return value;
  } catch {
    clientConfigCache = { at: Date.now(), value: null };
    return null;
  }
}

export function pushTokenCount(): number {
  return load().tokens.length;
}
