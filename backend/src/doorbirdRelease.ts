import http from "node:http";
import https from "node:https";
import { resolvedDoorbird } from "./intercomReleaseMode";
import { logger } from "./logger";
import type { IntercomDevice } from "./types";

/**
 * Triggers DoorBird `open-door.cgi` (LAN API). Uses `http-user` / `http-password`
 * query parameters as documented for third-party integrations (DoorBird LAN API).
 */
export async function releaseDoorViaDoorbird(ic: IntercomDevice): Promise<void> {
  const db = resolvedDoorbird(ic);
  if (!db) throw new Error("DoorBird: host, gebruiker of wachtwoord ontbreekt");

  const useTls = db.useTls === true;
  const port = db.port ?? (useTls ? 443 : 80);
  const relay = (db.relay?.trim() && db.relay.trim().length > 0) ? db.relay.trim() : "1";
  const host = db.host.trim();

  const qs = new URLSearchParams({
    "http-user": db.username.trim(),
    "http-password": String(db.password),
    r: relay
  });
  const path = `/bha-api/open-door.cgi?${qs.toString()}`;

  const status = await new Promise<number>((resolve, reject) => {
    const opts: http.RequestOptions = {
      hostname: host,
      port,
      path,
      method: "GET",
      timeout: 15_000
    };
    const mod = useTls ? https : http;
    if (useTls) {
      (opts as https.RequestOptions).rejectUnauthorized = db.insecureTls !== false;
    }
    const req = mod.request(opts, (res) => {
      res.resume();
      resolve(res.statusCode ?? 0);
    });
    req.on("timeout", () => {
      req.destroy(new Error("DoorBird: timeout"));
    });
    req.on("error", reject);
    req.end();
  });

  if (status === 204) {
    throw new Error(
      "DoorBird weigerde (204): geen rechten — zet in de DoorBird-app 'Altijd live bekijken' aan, of bel eerst aan (API vereist recent bel-event of watch-always)."
    );
  }
  if (status < 200 || status >= 300) {
    throw new Error(`DoorBird open-door mislukt (HTTP ${status})`);
  }

  logger.info(
    { id: ic.id, host, port, relay, tls: useTls },
    "intercom: deur open via DoorBird"
  );
}

/**
 * De DoorBird neemt een INVITE niet op. `makecall` laat het toestel zelf
 * het paneel bellen; dat gesprek staat dan meteen open.
 */
export async function doorbirdMakeCall(
  ic: IntercomDevice,
  sipUrl: string
): Promise<void> {
  const db = resolvedDoorbird(ic);
  if (!db) {
    throw new Error(
      "DoorBird: host, gebruiker of wachtwoord ontbreekt. Zelf bellen kan dan niet."
    );
  }
  const qs = new URLSearchParams({
    "http-user": db.username.trim(),
    "http-password": String(db.password),
    action: "makecall"
  });
  // De DoorBird-voorbeelden laten de sip-url ongecodeerd. %40 pakt het toestel niet.
  const status = await doorbirdGet(
    db,
    `/bha-api/sip.cgi?${qs.toString()}&url=${sipUrl}`
  );
  if (status === 401) {
    throw new Error(
      "De DoorBird-gebruiker mag geen gesprek starten. Zet in de DoorBird-app de rechten op API-operator."
    );
  }
  if (status === 503) {
    throw new Error("De DoorBird is al in gesprek.");
  }
  if (status < 200 || status >= 300) {
    throw new Error(`DoorBird bellen mislukt (HTTP ${status}).`);
  }
  logger.info({ id: ic.id, sipUrl }, "intercom: DoorBird start gesprek");
}

async function doorbirdGet(
  db: NonNullable<ReturnType<typeof resolvedDoorbird>>,
  path: string
): Promise<number> {
  const useTls = db.useTls === true;
  const port = db.port ?? (useTls ? 443 : 80);
  return new Promise<number>((resolve, reject) => {
    const opts: http.RequestOptions = {
      hostname: db.host.trim(),
      port,
      path,
      method: "GET",
      timeout: 15_000
    };
    const mod = useTls ? https : http;
    if (useTls) {
      (opts as https.RequestOptions).rejectUnauthorized = db.insecureTls !== false;
    }
    const req = mod.request(opts, (res) => {
      res.resume();
      resolve(res.statusCode ?? 0);
    });
    req.on("timeout", () => {
      req.destroy(new Error("DoorBird: timeout"));
    });
    req.on("error", reject);
    req.end();
  });
}
