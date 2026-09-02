import { collectIntercoms } from "../cameras";
import { getConfig } from "../config";
import { releaseDoor } from "../intercoms";
import type { KnxBus } from "../knxBus";
import { logger } from "../logger";
import type { HouseConfig, VoipEndpoint } from "../types";
import type { WsHub } from "../ws";
import { AmiClient, type AmiFields } from "./ami";
import { writeAsteriskConfig } from "./asteriskConfig";
import { normalizeVoip } from "./normalize";

let hub: WsHub | null = null;
let bus: KnxBus | null = null;
let ami: AmiClient | null = null;
let amiTimer: ReturnType<typeof setInterval> | null = null;
const registered = new Set<string>();
const channelIntercom = new Map<string, string>();
let lastRingIntercomId: string | null = null;
let answeredBroadcastFor: string | null = null;
let lastWrite = "";

export function setVoipHub(h: WsHub): void {
  hub = h;
}

export function setVoipBus(b: KnxBus): void {
  bus = b;
}

export function voipRegisteredExts(): string[] {
  return [...registered];
}

export function voipAmiUp(): boolean {
  return ami?.connected === true;
}

export function resolveUserEndpoint(
  cfg: HouseConfig,
  userId: string | undefined
): VoipEndpoint | null {
  const v = cfg.voip;
  if (!v?.enabled || !userId) return null;
  const eps = v.endpoints ?? [];
  const byUser = eps.find((e) => e.userId === userId);
  if (byUser) return byUser;
  const user = cfg.users?.find((u) => u.id === userId);
  if (!user?.sipEndpointId) return null;
  return eps.find((e) => e.id === user.sipEndpointId) ?? null;
}

export async function syncVoipFromConfig(cfg: HouseConfig): Promise<void> {
  normalizeVoip(cfg);
  const dir = writeAsteriskConfig(cfg);
  lastWrite = dir;
  logger.info({ dir, enabled: cfg.voip?.enabled === true }, "Asterisk-config geschreven");
  if (!cfg.voip?.enabled) {
    ami?.close();
    ami = null;
    return;
  }
  await amiReload();
}

async function amiReload(): Promise<void> {
  try {
    await ensureAmi();
    await ami?.command("core reload");
  } catch (err) {
    logger.warn({ err }, "Asterisk reload mislukt (PBX nog niet draaiend?)");
  }
}

async function ensureAmi(): Promise<void> {
  if (ami?.connected) return;
  const cfg = getConfig();
  const secret = cfg.voip?.amiSecret;
  if (!secret) return;
  const host = process.env.ASTERISK_AMI_HOST?.trim() || "127.0.0.1";
  const port = Number(process.env.ASTERISK_AMI_PORT ?? 5038);
  const client = new AmiClient(host, port);
  client.setEventHandler(onAmiEvent);
  try {
    await client.connect("archie", secret);
    ami = client;
    logger.info({ host, port }, "AMI verbonden");
  } catch (err) {
    client.close();
    throw err;
  }
}

function onAmiEvent(ev: AmiFields): void {
  const event = ev.Event;
  if (event === "UserEvent" && (ev.UserEvent === "Archie" || ev.Kind)) {
    const kind = (ev.Kind ?? "").toLowerCase();
    const id = ev.IntercomId;
    if (!id) return;
    if (kind === "ring") {
      lastRingIntercomId = id;
      answeredBroadcastFor = null;
      hub?.broadcastIntercomRing(id);
    }
    if (kind === "answered") {
      if (answeredBroadcastFor !== id) {
        answeredBroadcastFor = id;
        hub?.broadcastIntercomCleared(id);
      }
    }
    if (kind === "cleared") {
      if (lastRingIntercomId === id) lastRingIntercomId = null;
      hub?.broadcastIntercomCleared(id);
    }
    return;
  }
  if (event === "ContactStatus") {
    const aor = ev.AOR || ev.Peer || "";
    const status = (ev.ContactStatus || ev.Status || "").toLowerCase();
    if (!aor) return;
    if (status.includes("created") || status === "reachable" || status === "nonqualified") {
      registered.add(aor);
    }
    if (status.includes("removed") || status === "unreachable" || status === "unknown") {
      registered.delete(aor);
    }
    return;
  }
  if (event === "DialBegin") {
    const ic = ev.INTERCOM_ID || channelIntercom.get(ev.Linkedid || "") || channelIntercom.get(ev.Uniqueid || "");
    const uid = ev.DestUniqueid || ev.Uniqueid;
    if (ic && uid) channelIntercom.set(uid, ic);
    const linked = ev.Linkedid;
    if (ic && linked) channelIntercom.set(linked, ic);
    return;
  }
  if (event === "DialEnd") {
    const status = (ev.DialStatus || "").toUpperCase();
    if (status === "ANSWER" || status === "CANCEL") {
      const ic =
        ev.INTERCOM_ID ||
        channelIntercom.get(ev.Uniqueid || "") ||
        channelIntercom.get(ev.Linkedid || "") ||
        lastRingIntercomId;
      if (ic && answeredBroadcastFor !== ic) {
        answeredBroadcastFor = ic;
        hub?.broadcastIntercomCleared(ic);
      }
    }
    return;
  }
  if (event === "Hangup") {
    const uid = ev.Uniqueid;
    const ic = uid ? channelIntercom.get(uid) : undefined;
    if (uid) channelIntercom.delete(uid);
    if (ic) hub?.broadcastIntercomCleared(ic);
    return;
  }
  if (event === "DTMFEnd" || event === "DTMFBegin") {
    if (event === "DTMFBegin") return;
    const digit = ev.Digit ?? "";
    const uid = ev.Uniqueid || ev.Linkedid || "";
    const icId = ev.INTERCOM_ID || channelIntercom.get(uid) || lastRingIntercomId;
    if (!icId || !digit) return;
    const ic = collectIntercoms(getConfig()).find((i) => i.id === icId);
    if (!ic) return;
    const want = (ic.intercom.dtmfDigit ?? "#").trim();
    if (!want || digit !== want) return;
    if (!bus) return;
    void releaseDoor(ic, bus).catch((err) => {
      logger.warn({ err, id: icId }, "DTMF deuropen mislukt");
    });
  }
}

export function startVoipAmiWatch(): void {
  if (amiTimer) return;
  amiTimer = setInterval(() => {
    const cfg = getConfig();
    if (!cfg.voip?.enabled) return;
    if (ami?.connected) return;
    void ensureAmi().catch((err) => {
      logger.debug({ err }, "AMI reconnect");
    });
  }, 8000);
}

export { lastWrite };
