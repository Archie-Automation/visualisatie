import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import type { NextFunction, Request, Response } from "express";
import type { User } from "./types";
import { getConfig } from "./config";
import { logger } from "./logger";
import {
  isInstallerRole,
  isStaffRole,
  isUserEnabled,
  normalizeRole,
  type AppRole
} from "./roles";

const SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";
const TTL = process.env.TOKEN_TTL ?? "12h";

export interface TokenPayload {
  sub: string;
  username: string;
  role: AppRole;
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
  if (!isUserEnabled(user)) return null;
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
    const live = (getConfig().users ?? []).find((u) => u.id === decoded.sub);
    if (live && !isUserEnabled(live)) {
      return res.status(401).json({ error: "account disabled" });
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

/** @deprecated Use requireInstaller. Kept so old call sites keep compiling. */
export const requireAdmin = requireInstaller;

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
  const acl = u.access?.canRelease;
  if (acl === "*") return true;
  if (Array.isArray(acl)) return acl.includes(intercomId);
  return false;
}

/** Can this authenticated caller view/answer the given intercom? */
export function canViewIntercom(
  req: AuthedRequest,
  intercomId: string
): boolean {
  const u = currentUser(req);
  if (!u) return isStaffRole(req.user?.role);
  if (isStaffRole(u.role)) return true;
  const acl = u.access?.talkIntercoms;
  if (acl === undefined) return true;
  if (acl === "*") return true;
  return acl.includes(intercomId);
}

/** Can this caller create / rename / delete scenes?
 *  Installer and superuser always. Users unless `access.editScenes === false`. */
export function canEditScenes(req: AuthedRequest): boolean {
  if (isStaffRole(req.user?.role)) return true;
  const u = currentUser(req);
  if (!u) return false;
  return u.access?.editScenes !== false;
}
