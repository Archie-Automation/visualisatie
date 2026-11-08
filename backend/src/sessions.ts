/**
 * Koppelcodes en refresh-tokens.
 *
 * - Een ingelogde gebruiker (of het wandpaneel) maakt een koppelcode (10 min,
 *   eenmalig). De QR/koppelcode zet een telefoon zonder wachtwoord op dit huis.
 * - Bij claim krijgt de telefoon een kort access-JWT (24 u) plus een opaque
 *   refresh-token (1 jaar, schuivend). Alleen de sha256 van het refresh-token
 *   staat op schijf; intrekken kan per apparaat.
 *
 * Bestaande 365-dagen-login-tokens blijven werken; dit komt ernaast.
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import jwt from "jsonwebtoken";
import { getConfig } from "./config";
import { logger } from "./logger";
import { isUserEnabled, normalizeRole, type AppRole } from "./roles";
import type { TokenPayload } from "./auth";
import type { User } from "./types";

const SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";
const ACCESS_TTL = process.env.ACCESS_TOKEN_TTL ?? "24h";
const REFRESH_DAYS = Number(process.env.REFRESH_TOKEN_DAYS ?? 365);
const PAIR_TTL_MS = 10 * 60_000;

export interface SessionRecord {
  id: string;
  userId: string;
  username: string;
  tokenHash: string;
  device: string;
  createdAt: string;
  lastUsedAt: string;
  expiresAt: string;
  revoked?: boolean;
  /** Cloud-uitnodiging die dit apparaat openzette. Weg bij afmelden. */
  gateId?: string;
}

interface SessionStore {
  sessions: SessionRecord[];
  gates: string[];
}

interface PairCode {
  code: string;
  userId: string;
  createdBy: string;
  expiresAt: number;
  /** Sha256 van het ticket in de koppellink. Opent het cloud-adres in de browser. */
  gateTicketHash?: string;
  /** Zelfde apparaat meenemen naar het cloudadres. Geen tweede sessie. */
  transferSessionId?: string;
}

const pairCodes = new Map<string, PairCode>();

function storePath(): string {
  const fromEnv = process.env.SESSIONS_STORE_PATH?.trim();
  if (fromEnv) return path.resolve(fromEnv);
  return path.join(process.cwd(), "data", "sessions.json");
}

let cache: SessionStore | null = null;

function load(): SessionStore {
  if (cache) return cache;
  try {
    const raw = fs.readFileSync(storePath(), "utf-8");
    const parsed = JSON.parse(raw) as SessionStore;
    const gates = Array.isArray(parsed.gates)
      ? parsed.gates.filter((g): g is string => typeof g === "string" && g.length > 0)
      : [];
    cache = { sessions: Array.isArray(parsed.sessions) ? parsed.sessions : [], gates };
  } catch {
    cache = { sessions: [], gates: [] };
  }
  return cache;
}

function save(store: SessionStore): void {
  const p = storePath();
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const tmp = `${p}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2) + "\n", "utf-8");
  fs.renameSync(tmp, p);
  cache = store;
}

function sha256(s: string): string {
  return crypto.createHash("sha256").update(s).digest("hex");
}

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function randomCode(): string {
  const bytes = crypto.randomBytes(8);
  let s = "";
  for (let i = 0; i < 8; i++) s += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return `${s.slice(0, 4)}-${s.slice(4)}`;
}

function normalizeCode(raw: string): string {
  const s = raw.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (s.length !== 8) return raw.trim().toUpperCase();
  return `${s.slice(0, 4)}-${s.slice(4)}`;
}

function pruneCodes(): void {
  const now = Date.now();
  for (const [k, v] of pairCodes) if (v.expiresAt < now) pairCodes.delete(k);
}

/** Koppelcode voor [userId], aangemaakt door [createdBy]. */
export function createPairCode(
  userId: string,
  createdBy: string,
  transferSessionId?: string
): { code: string; expiresAt: number; gateTicket: string } {
  pruneCodes();
  let code = randomCode();
  while (pairCodes.has(code)) code = randomCode();
  const expiresAt = Date.now() + PAIR_TTL_MS;
  const gateTicket = crypto.randomBytes(32).toString("base64url");
  pairCodes.set(code, {
    code,
    userId,
    createdBy,
    expiresAt,
    gateTicketHash: sha256(gateTicket),
    transferSessionId
  });
  return { code, expiresAt, gateTicket };
}

/** Ticket uit een koppellink, geldig zolang die code nog niet ingewisseld of verlopen is. */
export function gateTicketValid(ticket: string): boolean {
  if (!ticket || ticket.length < 20) return false;
  pruneCodes();
  const h = sha256(ticket);
  for (const pc of pairCodes.values()) {
    if (pc.gateTicketHash === h) return true;
  }
  return false;
}

function findUser(userId: string): User | undefined {
  return (getConfig().users ?? []).find((u) => u.id === userId);
}

function signAccess(user: User, sessionId: string): string {
  const payload: TokenPayload = {
    sub: user.id,
    username: user.username,
    role: normalizeRole(user.role) as AppRole,
    sid: sessionId
  };
  return jwt.sign(payload, SECRET, { expiresIn: ACCESS_TTL as jwt.SignOptions["expiresIn"] });
}

const revokedListeners = new Set<(ids: string[]) => void>();

/** Websocket sluit de verbinding van een afgemeld apparaat meteen. */
export function onSessionsRevoked(fn: (ids: string[]) => void): void {
  revokedListeners.add(fn);
}

function emitRevoked(ids: string[]): void {
  if (!ids.length) return;
  for (const fn of revokedListeners) fn(ids);
}

/** Cookie-id van een geopende koppellink. Zonder dit blijft het cloudadres dicht. */
export function rememberGate(gid: string): void {
  if (!gid) return;
  const store = load();
  if (store.gates.includes(gid)) return;
  store.gates.push(gid);
  save(store);
}

export function gateGrantLive(gid: string | undefined | null): boolean {
  if (!gid) return false;
  return load().gates.includes(gid);
}

export function forgetGate(gid: string): void {
  const store = load();
  const next = store.gates.filter((g) => g !== gid);
  if (next.length === store.gates.length) return;
  store.gates = next;
  save(store);
}

function releaseGate(store: SessionStore, gid: string | undefined): void {
  if (!gid) return;
  const still = store.sessions.some((s) => !s.revoked && s.gateId === gid);
  if (still) return;
  store.gates = store.gates.filter((g) => g !== gid);
}

/** Access-token hoort bij een levende sessie. Oude tokens zonder sessie zijn dicht. */
export function sessionLive(sessionId: string | undefined | null): boolean {
  if (!sessionId) return false;
  const rec = load().sessions.find((s) => s.id === sessionId);
  if (!rec || rec.revoked) return false;
  return new Date(rec.expiresAt).getTime() > Date.now();
}

function publicUser(user: User): Omit<User, "passwordHash"> {
  const { passwordHash: _ph, ...rest } = user;
  return { ...rest, role: normalizeRole(user.role), enabled: isUserEnabled(user) };
}

export interface IssuedSession {
  accessToken: string;
  refreshToken: string;
  user: Omit<User, "passwordHash">;
  sessionId: string;
}

function issue(user: User, device: string, gateId?: string): IssuedSession {
  const store = load();
  const refreshToken = crypto.randomBytes(32).toString("base64url");
  const now = new Date();
  const rec: SessionRecord = {
    id: crypto.randomBytes(6).toString("hex"),
    userId: user.id,
    username: user.username,
    tokenHash: sha256(refreshToken),
    device: device.slice(0, 64),
    createdAt: now.toISOString(),
    lastUsedAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + REFRESH_DAYS * 86_400_000).toISOString(),
    gateId: gateId || undefined
  };
  store.sessions.push(rec);
  // Oude/ingetrokken sessies opruimen.
  const cutoff = Date.now();
  store.sessions = store.sessions.filter(
    (s) => !s.revoked && new Date(s.expiresAt).getTime() > cutoff
  );
  save(store);
  return {
    accessToken: signAccess(user, rec.id),
    refreshToken,
    user: publicUser(user),
    sessionId: rec.id
  };
}

/** Zelfde sessie naar het cloudadres. Geen tweede apparaat in de lijst. */
function adoptSession(sessionId: string, device: string, gateId?: string): IssuedSession | null {
  const store = load();
  const rec = store.sessions.find((s) => s.id === sessionId && !s.revoked);
  if (!rec || new Date(rec.expiresAt).getTime() <= Date.now()) return null;
  const user = findUser(rec.userId);
  if (!user || !isUserEnabled(user)) return null;
  const previousGate = rec.gateId;
  const refreshToken = crypto.randomBytes(32).toString("base64url");
  const now = new Date();
  rec.tokenHash = sha256(refreshToken);
  rec.lastUsedAt = now.toISOString();
  rec.expiresAt = new Date(now.getTime() + REFRESH_DAYS * 86_400_000).toISOString();
  const nextDevice = device.trim().slice(0, 64);
  if (nextDevice) rec.device = nextDevice;
  if (gateId) rec.gateId = gateId;
  if (previousGate && previousGate !== rec.gateId) releaseGate(store, previousGate);
  save(store);
  return {
    accessToken: signAccess(user, rec.id),
    refreshToken,
    user: publicUser(user),
    sessionId: rec.id
  };
}

/** Koppelcode inwisselen. Null = ongeldig/verlopen/gebruiker uit. */
export function claimPairCode(rawCode: string, device: string, gateId?: string): IssuedSession | null {
  pruneCodes();
  const code = normalizeCode(rawCode ?? "");
  const pc = pairCodes.get(code);
  if (!pc) return null;
  pairCodes.delete(code);
  if (pc.transferSessionId) {
    const moved = adoptSession(pc.transferSessionId, device || "telefoon", gateId);
    if (moved) logger.info({ user: moved.user.username, device, session: moved.sessionId }, "cloudadres geopend");
    return moved;
  }
  const user = findUser(pc.userId);
  if (!user || !isUserEnabled(user)) return null;
  logger.info({ user: user.username, device, by: pc.createdBy }, "telefoon gekoppeld");
  return issue(user, device || "telefoon", gateId);
}

/** Sessie na wachtwoord-login (zelfde refresh-mechanisme als koppelen). */
export function issueSessionForUser(userId: string, device: string, gateId?: string): IssuedSession | null {
  const user = findUser(userId);
  if (!user || !isUserEnabled(user)) return null;
  return issue(user, device || "app", gateId);
}

/** Nieuw access-token op een geldig refresh-token; verlengt de sessie schuivend. */
export function refreshAccess(
  refreshToken: string,
  device?: string
): { accessToken: string; user: Omit<User, "passwordHash">; sessionId: string } | null {
  if (!refreshToken || refreshToken.length < 20) return null;
  const store = load();
  const h = sha256(refreshToken);
  const rec = store.sessions.find((s) => s.tokenHash === h && !s.revoked);
  if (!rec) return null;
  if (new Date(rec.expiresAt).getTime() < Date.now()) return null;
  const user = findUser(rec.userId);
  if (!user || !isUserEnabled(user)) return null;
  const now = new Date();
  rec.lastUsedAt = now.toISOString();
  rec.expiresAt = new Date(now.getTime() + REFRESH_DAYS * 86_400_000).toISOString();
  const nextDevice = device?.trim().slice(0, 64);
  if (nextDevice) rec.device = nextDevice;
  save(store);
  return { accessToken: signAccess(user, rec.id), user: publicUser(user), sessionId: rec.id };
}

export function revokeRefreshToken(refreshToken: string): boolean {
  const store = load();
  const h = sha256(refreshToken);
  const rec = store.sessions.find((s) => s.tokenHash === h);
  if (!rec || rec.revoked) return false;
  rec.revoked = true;
  releaseGate(store, rec.gateId);
  save(store);
  emitRevoked([rec.id]);
  return true;
}

export function revokeSession(sessionId: string, userId: string | null): boolean {
  const store = load();
  const rec = store.sessions.find((s) => s.id === sessionId && (userId === null || s.userId === userId));
  if (!rec || rec.revoked) return false;
  rec.revoked = true;
  releaseGate(store, rec.gateId);
  save(store);
  emitRevoked([rec.id]);
  return true;
}

/**
 * Alle apparaten van een gebruiker afmelden (wachtwoord gewijzigd, gebruiker
 * verwijderd). [keepSessionId] blijft staan, zodat wie zijn eigen wachtwoord
 * wijzigt niet van zijn huidige telefoon wordt gegooid.
 */
export function revokeAllForUser(userId: string, keepSessionId?: string | null): number {
  const store = load();
  const ids: string[] = [];
  for (const s of store.sessions) {
    if (s.userId !== userId || s.revoked) continue;
    if (keepSessionId && s.id === keepSessionId) continue;
    s.revoked = true;
    ids.push(s.id);
  }
  if (!ids.length) return 0;
  for (const s of store.sessions) {
    if (ids.includes(s.id)) releaseGate(store, s.gateId);
  }
  save(store);
  emitRevoked(ids);
  return ids.length;
}

export function listSessions(userId: string | null): Array<Omit<SessionRecord, "tokenHash">> {
  const store = load();
  return store.sessions
    .filter((s) => !s.revoked && (userId === null || s.userId === userId))
    .map(({ tokenHash: _h, ...rest }) => rest);
}
