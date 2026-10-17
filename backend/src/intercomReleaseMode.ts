import type { IntercomDevice, IntercomDoorbirdConfig } from "./types";

export type EffectiveReleaseMode = "knx" | "doorbird" | "http" | "dtmf";

function hasHttp(ic: IntercomDevice): boolean {
  return !!ic.intercom.httpRelease?.url?.trim();
}

function hasKnx(ic: IntercomDevice): boolean {
  return !!ic.intercom.release?.ga;
}

/** RTSP-login van een DoorBird is dezelfde HTTP-API-gebruiker als open-door.cgi. */
export function credentialsFromRtsp(
  rtsp: string | undefined
): { host: string; username: string; password: string } | null {
  const raw = (rtsp ?? "").trim();
  if (!raw) return null;
  try {
    const u = new URL(raw);
    if (!u.hostname || !u.username) return null;
    const username = decodeURIComponent(u.username);
    const password = decodeURIComponent(u.password);
    if (!username || !password) return null;
    return { host: u.hostname, username, password };
  } catch {
    return null;
  }
}

/**
 * DoorBird LAN-API: expliciet blok, anders user/wachtwoord/host uit de RTSP-URL.
 * SIP-wachtwoord is een ander account — niet gebruiken.
 */
export function resolvedDoorbird(
  ic: IntercomDevice
): IntercomDoorbirdConfig | null {
  const db = ic.intercom.doorbird;
  const fromRtsp = credentialsFromRtsp(ic.intercom.rtsp);
  const host = db?.host?.trim() || fromRtsp?.host || "";
  const username = db?.username?.trim() || fromRtsp?.username || "";
  const password =
    db?.password != null && String(db.password).length > 0
      ? String(db.password)
      : (fromRtsp?.password ?? "");
  if (!host || !username || !password) return null;
  return {
    host,
    username,
    password,
    port: db?.port,
    useTls: db?.useTls,
    insecureTls: db?.insecureTls,
    relay: db?.relay
  };
}

function hasDoorbird(ic: IntercomDevice): boolean {
  return resolvedDoorbird(ic) != null;
}

/** SIP-deurstation: DTMF tijdens het gesprek (DoorBird-standaard `#`). */
function hasDtmf(ic: IntercomDevice): boolean {
  return !!ic.intercom.sipExt?.trim();
}

export function intercomDtmfDigit(ic: IntercomDevice): string {
  const d = (ic.intercom.dtmfDigit ?? "#").trim();
  return d || "#";
}

/**
 * Hoe de app de deur ontgrendelt.
 * Expliciete modus wint alleen als die ook écht is ingevuld. Anders
 * `releaseMode: knx` zonder GA (de installer-default) de knop en de
 * DTMF-weg van een SIP-DoorBird.
 */
export function effectiveIntercomReleaseMode(
  d: IntercomDevice
): EffectiveReleaseMode {
  const want = d.intercom.releaseMode;
  if (want === "http" && hasHttp(d)) return "http";
  if (want === "doorbird" && hasDoorbird(d)) return "doorbird";
  if (want === "knx" && hasKnx(d)) return "knx";
  if (hasHttp(d)) return "http";
  if (hasKnx(d)) return "knx";
  if (hasDoorbird(d)) return "doorbird";
  if (hasDtmf(d)) return "dtmf";
  if (want === "http") return "http";
  if (want === "doorbird") return "doorbird";
  return "knx";
}

export function intercomSupportsRelease(ic: IntercomDevice): boolean {
  const mode = effectiveIntercomReleaseMode(ic);
  if (mode === "knx") return hasKnx(ic);
  if (mode === "http") return hasHttp(ic);
  if (mode === "doorbird") return hasDoorbird(ic);
  return mode === "dtmf";
}
