import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import type { NextFunction, Request, Response } from "express";
import type { User } from "./types";
import { getConfig, updateConfig } from "./config";
import { aclAllows } from "./userAccess";
import { logger } from "./logger";
import {
  isInstallerRole,
  isStaffRole,
  isUserEnabled,
  normalizeRole,
  type AppRole
} from "./roles";
import { sessionLive } from "./sessions";

const SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";
if (
  SECRET === "dev-secret-change-me" &&
  process.env.NODE_ENV === "production"
) {
  throw new Error(
    "JWT_SECRET env niet gezet — weiger te starten in production. " +
      "Stel JWT_SECRET in als Docker env of in .env."
  );
}
const TTL = process.env.TOKEN_TTL ?? "365d";

export interface TokenPayload {
  sub: string;
  username: string;
  role: AppRole;
  /** Sessie die dit token mag gebruiken. Zonder geldige sessie is het token dood. */
  sid?: string;
}

export interface AuthedRequest extends Request {
  user?: TokenPayload;
}

/**
 * Vanaf het cloud-adres: fabriekswachtwoord en het placeholder-hash werken niet.
 * Thuis blijven ze werken tot het wachtwoord echt gezet is.
 */
export function remoteLoginBlocked(username: string, password: string, passwordHash: string): boolean {
  if (username.trim().toLowerCase() === "admin" && password === "admin") return true;
  if (passwordHash.includes("REPLACE_ME")) return true;
  return false;
}

/** Nog het meegeleverde placeholder-hash. admin/admin (of guest) werkt tot het vervangen is. */
export function factoryPasswordActive(passwordHash: string | undefined): boolean {
  return !!passwordHash && passwordHash.includes("REPLACE_ME");
}

/** Geweigerd wachtwoord, of null als het opgeslagen mag worden. */
export function rejectedLoginPassword(username: string, password: string): string | null {
  if (password.length < 8) return "Kies minstens 8 tekens.";
  const low = password.trim().toLowerCase();
  if (low === "admin" || low === "guest" || low === "gast") {
    return "Dit wachtwoord is niet toegestaan.";
  }
  if (low.length > 0 && low === username.trim().toLowerCase()) {
    return "Het wachtwoord mag niet gelijk zijn aan de gebruikersnaam.";
  }
  return null;
}

export async function setOwnPassword(
  userId: string,
  password: string
): Promise<{ ok: true } | { ok: false; error: string }> {
  const me = (getConfig().users ?? []).find((u) => u.id === userId);
  if (!me) return { ok: false, error: "onbekend account" };
  const reason = rejectedLoginPassword(me.username, password);
  if (reason) return { ok: false, error: reason };
  const passwordHash = await bcrypt.hash(password, 10);
  updateConfig((draft) => {
    const user = draft.users?.find((u) => u.id === userId);
    if (user) user.passwordHash = passwordHash;
  });
  return { ok: true };
}

export async function authenticate(
  username: string,
  password: string,
  opts?: { remote?: boolean }
): Promise<{
  token: string;
  user: Omit<User, "passwordHash">;
  mustChangePassword: boolean;
} | null> {
  const users = getConfig().users ?? [];
  const user = users.find((u) => u.username === username);
  if (!user) return null;
  if (!isUserEnabled(user)) return null;
  if (opts?.remote && remoteLoginBlocked(username, password, user.passwordHash)) return null;
  const ok = await bcrypt.compare(password, user.passwordHash).catch(() => false);

  const role = normalizeRole(user.role);
  // Bootstrap convenience: placeholder hash accepts admin/admin (installer) or guest.
  const isBootstrap =
    user.passwordHash.includes("REPLACE_ME") &&
    ((role === "installer" && password === "admin") ||
      (role === "user" && password === "guest"));

  if (!ok && !isBootstrap) return null;
  if (isBootstrap) {
    logger.warn({ username }, "Bootstrap credentials used – replace the hash!");
  }

  const payload: TokenPayload = {
    sub: user.id,
    username: user.username,
    role
  };
  const token = jwt.sign(payload, SECRET, { expiresIn: TTL as jwt.SignOptions["expiresIn"] });
  const { passwordHash: _ph, ...rest } = user;
  const publicUser: Omit<User, "passwordHash"> = {
    ...rest,
    role,
    enabled: isUserEnabled(user)
  };
  return {
    token,
    user: publicUser,
    mustChangePassword: factoryPasswordActive(user.passwordHash)
  };
}

/** Geldige Bearer, of null. Faalt zacht: health blijft bruikbaar zonder login. */
const SESSION_COOKIE = "archie_session";

function readSessionCookie(req: Request): string | null {
  const header = req.headers.cookie;
  if (!header) return null;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i < 0) continue;
    if (part.slice(0, i).trim() !== SESSION_COOKIE) continue;
    try {
      const value = decodeURIComponent(part.slice(i + 1).trim());
      return value || null;
    } catch {
      return null;
    }
  }
  return null;
}

function requestToken(req: Request): string | null {
  const hdr = req.header("authorization");
  if (hdr?.startsWith("Bearer ")) {
    const token = hdr.slice(7).trim();
    if (token) return token;
  }
  return readSessionCookie(req);
}

/** De videospeler in de browser kan geen Authorization-header sturen.
 *  Zelfde login, als cookie, zodat HLS op het cloudadres wel laadt. */
export function writeSessionCookie(req: Request, res: Response, token: string | null): void {
  const proto = String(req.headers["x-forwarded-proto"] || "").split(",")[0]?.trim();
  const secure = req.secure || proto === "https";
  const parts = [
    `${SESSION_COOKIE}=${token ? encodeURIComponent(token) : ""}`,
    "HttpOnly",
    "SameSite=Lax",
    "Path=/",
    `Max-Age=${token ? 24 * 60 * 60 : 0}`
  ];
  if (secure) parts.push("Secure");
  res.append("Set-Cookie", parts.join("; "));
}

export function peekToken(req: Request): TokenPayload | null {
  const token = requestToken(req);
  if (!token) return null;
  try {
    const decoded = jwt.verify(token, SECRET) as TokenPayload;
    if (!sessionLive(decoded.sid)) return null;
    return decoded;
  } catch {
    return null;
  }
}

export function requireAuth(
  req: AuthedRequest,
  res: Response,
  next: NextFunction
) {
  const token = requestToken(req);
  if (!token) {
    return res.status(401).json({ error: "missing token" });
  }
  try {
    const decoded = jwt.verify(token, SECRET) as TokenPayload;
    if (!sessionLive(decoded.sid)) {
      return res.status(401).json({ error: "session revoked" });
    }
    req.user = decoded;
    const live = (getConfig().users ?? []).find((u) => u.id === decoded.sub);
    if (live && !isUserEnabled(live)) {
      return res.status(401).json({ error: "account disabled" });
    }
    if (live && factoryPasswordActive(live.passwordHash)) {
      const path = req.originalUrl.split("?")[0];
      const allow =
        req.method === "POST" &&
        (path.endsWith("/auth/password") || path.endsWith("/auth/logout"));
      if (!allow) {
        return res.status(403).json({ error: "password_change_required" });
      }
    }
    next();
  } catch {
    return res.status(401).json({ error: "invalid token" });
  }
}

/** Technical configuration (KNX house editor, server update, …). */
export function requireInstaller(
  req: AuthedRequest,
  res: Response,
  next: NextFunction
) {
  if (!isInstallerRole(req.user?.role)) {
    return res.status(403).json({ error: "installer only" });
  }
  next();
}

/** Installer or super user (user management, full customer app). */
export function requireStaff(
  req: AuthedRequest,
  res: Response,
  next: NextFunction
) {
  if (!isStaffRole(req.user?.role)) {
    return res.status(403).json({ error: "staff only" });
  }
  next();
}

/** Look up the (scrubbed) user record from the active config. */
export function currentUser(req: AuthedRequest): User | undefined {
  if (!req.user) return undefined;
  return (getConfig().users ?? []).find((u) => u.id === req.user!.sub);
}

/** Can this authenticated caller open the door on the given intercom? */
export function canReleaseIntercom(
  req: AuthedRequest,
  intercomId: string
): boolean {
  const u = currentUser(req);
  if (!u) return isStaffRole(req.user?.role);
  if (!isUserEnabled(u)) return false;
  if (isStaffRole(u.role)) return true;
  if (!aclAllows(u.access?.devices, intercomId)) return false;
  const acl = u.access?.canRelease;
  if (acl === "*") return true;
  if (Array.isArray(acl)) return acl.includes(intercomId);
  // Unset: een gekoppeld SIP-paneel mag deuren openen die het mag zien.
  // Explict `[]` blijft weigeren. Er is geen installer-veld per intercom.
  const uid = u.id;
  const hasSip = (getConfig().voip?.endpoints ?? []).some(
    (e) => e.userId === uid || u.sipEndpointId === e.id
  );
  return hasSip;
}

/** Can this authenticated caller view/answer the given intercom? */
export function canViewIntercom(
  req: AuthedRequest,
  intercomId: string
): boolean {
  const u = currentUser(req);
  if (!u) return isStaffRole(req.user?.role);
  if (isStaffRole(u.role)) return true;
  if (!aclAllows(u.access?.devices, intercomId)) return false;
  const acl = u.access?.talkIntercoms;
  if (acl === undefined) return true;
  if (acl === "*") return true;
  return acl.includes(intercomId);
}

/** Can this caller inlezen / leren / KNX-store van hardware-scenes? */
export function canLearnKnxScenes(req: AuthedRequest): boolean {
  return isStaffRole(req.user?.role);
}

/** Can this caller create / rename / delete scenes?
 *  Installer and superuser always. Users unless `access.editScenes === false`. */
export function canEditScenes(req: AuthedRequest): boolean {
  if (isStaffRole(req.user?.role)) return true;
  const u = currentUser(req);
  if (!u) return false;
  return u.access?.editScenes !== false;
}
