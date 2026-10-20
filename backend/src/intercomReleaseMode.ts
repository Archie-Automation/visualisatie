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

/** DoorBird RTSP: `/mpeg/media.amp` met een API-gebruiker als `abcdef0001`. */
const DOORBIRD_RTSP_PATH_RE = /\/mpeg\/media\.amp(\?|$)/i;
const DOORBIRD_API_USER_RE = /^[a-z0-9]{6}0{3}[0-9]$/i;

/**
 * Of dit toestel zich als DoorBird gedraagt (neemt geen INVITE op, belt zelf
 * via `sip.cgi?action=makecall`). Niet alleen `kind`: een DoorBird die als
 * "Overig SIP" is aangemaakt heeft dezelfde RTSP-URL en hetzelfde API-blok.
 */
export function isDoorbirdIntercom(ic: IntercomDevice): boolean {
  const i = ic.intercom;
  if (i.kind === "doorbird") return true;
  if (i.kind && i.kind !== "other" && i.kind !== "sip") return false;
  if (i.releaseMode === "doorbird") return true;
  if (i.doorbird?.host?.trim()) return true;
  const fromRtsp = credentialsFromRtsp(i.rtsp);
  if (!fromRtsp) return false;
  let path = "";
  try {
    path = new URL(i.rtsp.trim()).pathname;
  } catch {
    return false;
  }
  return (
    DOORBIRD_RTSP_PATH_RE.test(path) ||
    DOORBIRD_API_USER_RE.test(fromRtsp.username)
  );
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
