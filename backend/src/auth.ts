import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import type { NextFunction, Request, Response } from "express";
import type { User } from "./types";
import { getConfig } from "./config";
import { logger } from "./logger";

const SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";
const TTL = process.env.TOKEN_TTL ?? "12h";

export interface TokenPayload {
  sub: string;
  username: string;
  role: "admin" | "user";
}

export interface AuthedRequest extends Request {
  user?: TokenPayload;
}

export async function authenticate(
  username: string,
  password: string
): Promise<{ token: string; user: Omit<User, "passwordHash"> } | null> {
  const users = getConfig().users ?? [];
  const user = users.find((u) => u.username === username);
  if (!user) return null;
  const ok = await bcrypt.compare(password, user.passwordHash).catch(() => false);

  // Bootstrap convenience: if the hash is the placeholder, accept "admin"/"admin".
  const isBootstrap =
    user.passwordHash.includes("REPLACE_ME") &&
    ((user.role === "admin" && password === "admin") ||
      (user.role === "user" && password === "guest"));

  if (!ok && !isBootstrap) return null;
  if (isBootstrap) {
    logger.warn({ username }, "Bootstrap credentials used – replace the hash!");
  }

  const payload: TokenPayload = {
    sub: user.id,
    username: user.username,
    role: user.role
  };
  const token = jwt.sign(payload, SECRET, { expiresIn: TTL as jwt.SignOptions["expiresIn"] });
  const { passwordHash: _ph, ...publicUser } = user;
  return { token, user: publicUser };
}

export function requireAuth(
  req: AuthedRequest,
  res: Response,
  next: NextFunction
) {
  const hdr = req.header("authorization");
  if (!hdr?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "missing token" });
  }
  try {
    const decoded = jwt.verify(hdr.slice(7), SECRET) as TokenPayload;
    req.user = decoded;
    next();
  } catch {
    return res.status(401).json({ error: "invalid token" });
  }
}

export function requireAdmin(
  req: AuthedRequest,
  res: Response,
  next: NextFunction
) {
  if (req.user?.role !== "admin") {
    return res.status(403).json({ error: "admin only" });
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
  // Service token / non-resolvable users: admins always, everyone else no.
  if (!u) return req.user?.role === "admin";
  const acl = u.access?.canRelease;
  if (acl === "*") return true;
  if (Array.isArray(acl)) return acl.includes(intercomId);
  // Unset → inherit from role.
  return u.role === "admin";
}

/** Can this authenticated caller view/answer the given intercom? */
export function canViewIntercom(
  req: AuthedRequest,
  intercomId: string
): boolean {
  const u = currentUser(req);
  if (!u) return req.user?.role === "admin";
  const acl = u.access?.talkIntercoms;
  if (acl === undefined) return true; // no explicit restriction
  if (acl === "*") return true;
  return acl.includes(intercomId);
}

/** Can this caller create / rename / delete scenes?
 *  Admins always. Users get true unless explicitly denied via
 *  `access.editScenes === false`. */
export function canEditScenes(req: AuthedRequest): boolean {
  if (req.user?.role === "admin") return true;
  const u = currentUser(req);
  if (!u) return false;
  return u.access?.editScenes !== false;
}
