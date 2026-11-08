/**
 * Het publieke cloud-adres toont de app alleen aan een browser die een
 * koppellink heeft geopend. Die link wordt gemaakt op een ingelogd scherm
 * (thuis). Een vreemde ziet geen inlogformulier en kan geen wachtwoord proberen.
 *
 * De telefoon-app praat met een Bearer-token en heeft die cookie niet nodig.
 * Thuis (LAN-IP als TCP-peer) blijft de app open, anders kan niemand een
 * uitnodiging maken.
 */
import crypto from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { remoteUrl } from "./remoteAccess";
import { gateGrantLive, gateTicketValid, rememberGate } from "./sessions";

const COOKIE = "archie_gate";
const GATE_MAX_AGE_SEC = 400 * 24 * 60 * 60;

export function normalizeIp(raw: string | undefined | null): string {
  if (!raw) return "";
  let ip = raw.trim().toLowerCase();
  if (ip.startsWith("::ffff:")) ip = ip.slice(7);
  return ip;
}

/** Alleen processen op de NUC zelf. Niet het huis-LAN en niet de tunnel. */
export function isLoopbackAddress(ip: string | undefined | null): boolean {
  const n = normalizeIp(ip);
  return n === "127.0.0.1" || n === "::1";
}

/** Huis-LAN of deze machine. 10.80/16 is de WireGuard-tunnel naar de cloud, geen LAN. */
export function isLanAddress(ip: string): boolean {
  const n = normalizeIp(ip);
  if (n === "127.0.0.1" || n === "::1") return true;
  if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(n)) return true;
  const ten = /^10\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/.exec(n);
  if (ten && ten[1] !== "80") return true;
  const priv = /^172\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/.exec(n);
  if (priv) {
    const second = Number(priv[1]);
    if (second >= 16 && second <= 31) return true;
  }
  if (n.startsWith("fe80:")) return true;
  if (n.startsWith("fc") || n.startsWith("fd")) return true;
  return false;
}

/**
 * Verzoek komt niet van het huis-LAN. Alleen dan geldt de poort.
 * Beslist op het TCP-adres, niet op X-Forwarded-Host: die header kan een
 * bezoeker meesturen.
 */
export function isRemoteFacingPeer(peer: string | undefined | null, remoteConfigured: boolean): boolean {
  if (!remoteConfigured) return false;
  const ip = normalizeIp(peer);
  if (/^10\.80\.\d{1,3}\.\d{1,3}$/.test(ip)) return true;
  if (isLanAddress(ip)) return false;
  return true;
}

export function isRemoteFacing(req: Request): boolean {
  return isRemoteFacingPeer(req.socket?.remoteAddress, remoteUrl() != null);
}

function gateSecret(): string {
  return process.env.JWT_SECRET ?? "dev-secret-change-me";
}

export function signGate(secret: string, expSec: number, gid: string): string {
  const body = Buffer.from(JSON.stringify({ v: 1, exp: expSec, gid }), "utf8").toString("base64url");
  const mac = crypto.createHmac("sha256", secret).update(body).digest("base64url");
  return `${body}.${mac}`;
}

export function verifyGate(secret: string, token: string, nowSec: number): boolean {
  const dot = token.indexOf(".");
  if (dot <= 0) return false;
  const body = token.slice(0, dot);
  const mac = token.slice(dot + 1);
  const expected = crypto.createHmac("sha256", secret).update(body).digest("base64url");
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return false;
  try {
    const parsed = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as {
      exp?: unknown;
      gid?: unknown;
    };
    if (typeof parsed.exp !== "number" || parsed.exp <= nowSec) return false;
    return typeof parsed.gid === "string" && gateGrantLive(parsed.gid);
  } catch {
    return false;
  }
}

function readCookie(req: Request, name: string): string | null {
  const header = req.headers.cookie;
  if (!header) return null;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i < 0) continue;
    if (part.slice(0, i).trim() !== name) continue;
    try {
      return decodeURIComponent(part.slice(i + 1).trim());
    } catch {
      return null;
    }
  }
  return null;
}

export function gateCookieValid(req: Request, nowSec = Math.floor(Date.now() / 1000)): boolean {
  const raw = readCookie(req, COOKIE);
  if (!raw) return false;
  return verifyGate(gateSecret(), raw, nowSec);
}

/** Id van de cloud-uitnodiging in deze browser, of null. */
export function invitedGateId(req: Request): string | null {
  const raw = readCookie(req, COOKIE);
  if (!raw || !verifyGate(gateSecret(), raw, Math.floor(Date.now() / 1000))) return null;
  const dot = raw.indexOf(".");
  if (dot <= 0) return null;
  try {
    const parsed = JSON.parse(Buffer.from(raw.slice(0, dot), "base64url").toString("utf8")) as {
      gid?: unknown;
    };
    return typeof parsed.gid === "string" ? parsed.gid : null;
  } catch {
    return null;
  }
}

function setGateCookie(res: Response): void {
  const gid = crypto.randomBytes(16).toString("base64url");
  rememberGate(gid);
  const exp = Math.floor(Date.now() / 1000) + GATE_MAX_AGE_SEC;
  const value = encodeURIComponent(signGate(gateSecret(), exp, gid));
  res.append(
    "Set-Cookie",
    `${COOKIE}=${value}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${GATE_MAX_AGE_SEC}`
  );
}

function queryTicket(req: Request): string {
  const t = req.query["ticket"];
  if (typeof t === "string") return t;
  if (Array.isArray(t) && typeof t[0] === "string") return t[0];
  return "";
}

function bearerPresent(req: Request): boolean {
  const h = req.headers.authorization;
  const v = Array.isArray(h) ? h[0] : h;
  return typeof v === "string" && /^Bearer\s+\S{20,}/.test(v);
}

/** API die zonder cookie moet blijven werken: app-probe, koppelcode, bel, Spotify. */
export function remoteApiAllowed(method: string, pathname: string): boolean {
  const p = pathname.split("?")[0];
  if (
    method === "GET" &&
    (p === "/api/health" || p === "/api/version" || p === "/api/app/android.apk" || p === "/api/media-art")
  ) {
    return true;
  }
  if (
    method === "POST" &&
    (p === "/api/auth/pair/claim" || p === "/api/auth/refresh" || p === "/api/auth/logout")
  ) {
    return true;
  }
  if ((method === "GET" || method === "POST") && p.startsWith("/api/webhooks/ring/")) return true;
  if (method === "GET" && (p === "/api/media/spotify/callback" || p === "/api/media/spotify/tls-ok")) {
    return true;
  }
  return false;
}

function closedPage(_req: Request, res: Response): void {
  res.status(404);
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.send(`<!doctype html><html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Niet beschikbaar</title>
<style>body{font-family:system-ui,sans-serif;background:#f4f1ea;color:#1c1915;
display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{max-width:26rem;padding:2rem;text-align:center}h1{font-size:1.15rem;font-weight:600;margin:0 0 .6rem}
p{margin:0;line-height:1.45;color:#5c564c}</style></head>
<body><div class="card"><h1>Deze pagina is niet openbaar</h1>
<p>Open de uitnodiging die je hebt gekregen.</p></div></body></html>`);
}

export function remoteGate(req: Request, res: Response, next: NextFunction): void {
  if (!isRemoteFacing(req)) return next();
  const path = (req.originalUrl || req.url || "/").split("?")[0] || "/";
  const cookieOk = gateCookieValid(req);

  if (path.startsWith("/api")) {
    if (path === "/api/auth/login") {
      if (!cookieOk) {
        res.status(403).json({ error: "remote_closed" });
        return;
      }
      return next();
    }
    if (cookieOk || bearerPresent(req) || remoteApiAllowed(req.method, path)) return next();
    res.status(404).json({ error: "not found" });
    return;
  }

  if (path === "/ws") return next();

  if (path === "/pair" && gateTicketValid(queryTicket(req))) {
    setGateCookie(res);
    return next();
  }
  if (cookieOk) return next();
  closedPage(req, res);
}
