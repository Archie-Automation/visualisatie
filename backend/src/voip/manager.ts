import { collectIntercoms } from "../cameras";
import { getConfig, persistConfig } from "../config";
import { effectiveIntercomReleaseMode } from "../intercomReleaseMode";
import { releaseDoor } from "../intercoms";
import type { KnxBus } from "../knxBus";
import { logger } from "../logger";
import type { HouseConfig, VoipEndpoint } from "../types";
import type { WsHub } from "../ws";
import { AmiClient, type AmiFields } from "./ami";
import { doorContextName, groupDial, writeAsteriskConfig } from "./asteriskConfig";
import { removeLegacyAsteriskContainer } from "./asteriskDocker";
import { ensureAsteriskProcess, stopAsteriskProcess } from "./asteriskProcess";
import { normalizeVoip } from "./normalize";
import { intercomRingTargets } from "./ringTargets";
import {
  clearDoorChannel,
  recordDoorChannel,
  setDtmfAmiGetter
} from "./dtmfRelease";
import { intercomLines, type IntercomLinePhase } from "./lineState";
import { astSafe } from "./secrets";

let hub: WsHub | null = null;
let bus: KnxBus | null = null;
let ami: AmiClient | null = null;
let amiTimer: ReturnType<typeof setInterval> | null = null;
const registered = new Set<string>();
const channelIntercom = new Map<string, string>();
/** Alleen het kanaal van het deurstation, niet de panelen die meebellen. */
const doorChannels = new Map<string, Set<string>>();
let lastRingIntercomId: string | null = null;
let answeredBroadcastFor: string | null = null;

export function setVoipHub(h: WsHub): void {
  hub = h;
}

export function setVoipBus(b: KnxBus): void {
  bus = b;
}

export function voipRegisteredExts(): string[] {
  return [...registered];
}

export interface VoipCallEvent {
  at: string;
  event: string;
  detail: string;
}

const callLog: VoipCallEvent[] = [];

function logCall(event: string, detail: string): void {
  callLog.push({ at: new Date().toISOString(), event, detail });
  while (callLog.length > 12) callLog.shift();
}

/** Laatste bel-gebeurtenissen (zonder nummers of namen) voor diagnose. */
export function voipRecentCalls(): VoipCallEvent[] {
  return [...callLog];
}

export function voipAmiUp(): boolean {
  return ami?.connected === true;
}

export function intercomLinePhase(intercomId: string): IntercomLinePhase {
  return intercomLines.phase(intercomId);
}

/** Paneel belt zelf naar de deur. Mislukt als er al gerinkeld of gepraat wordt. */
export function claimIntercomLine(intercomId: string, holder: string): boolean {
  const ok = intercomLines.claim(intercomId, holder);
  if (ok) publishLine(intercomId, "dialing");
  return ok;
}

export function releaseIntercomLine(intercomId: string, holder: string): boolean {
  const ok = intercomLines.release(intercomId, holder);
  if (ok) publishLine(intercomId, "idle");
  return ok;
}

function publishLine(intercomId: string, phase: IntercomLinePhase): void {
  hub?.broadcastIntercomLine(intercomId, phase);
}

function pjsipExt(channel: string | undefined): string | null {
  if (!channel) return null;
  const m = /^PJSIP\/([^-\/;]+)/i.exec(channel);
  return m?.[1] ?? null;
}

function intercomIdForExt(ext: string | null): string | null {
  if (!ext) return null;
  const ic = collectIntercoms(getConfig()).find(
    (i) => (i.intercom.sipExt ?? "").trim() === ext
  );
  return ic?.id ?? null;
}

function noteDoorChannel(intercomId: string, channel: string | undefined): void {
  const ch = channel?.trim();
  if (!intercomId || !ch) return;
  if (intercomIdForExt(pjsipExt(ch)) !== intercomId) return;
  let set = doorChannels.get(intercomId);
  if (!set) {
    set = new Set();
    doorChannels.set(intercomId, set);
  }
  set.add(ch);
}

function forgetDoorChannel(intercomId: string, channel: string | undefined): boolean {
  const set = doorChannels.get(intercomId);
  if (!set) return false;
  if (channel) set.delete(channel.trim());
  if (set.size > 0) return false;
  doorChannels.delete(intercomId);
  return true;
}

function idleLine(intercomId: string): void {
  doorChannels.delete(intercomId);
  if (intercomLines.phase(intercomId) === "idle") return;
  intercomLines.onIdle(intercomId);
  publishLine(intercomId, "idle");
}

/**
 * Installer test: overlay + SIP ring of a belgroep, same as pressing the
 * door button. Uses the live (saved) house.json — unsaved wizard edits
 * are invisible to Asterisk.
 */
export async function testRingGroup(opts: {
  groupId: string;
  intercomId: string;
}): Promise<{ overlay: boolean; sip: boolean; error?: string }> {
  const cfg = getConfig();
  const ic = collectIntercoms(cfg).find((i) => i.id === opts.intercomId);
  if (!ic) {
    return {
      overlay: false,
      sip: false,
      error:
        "Intercom staat nog niet op de server. Sla de configuratie eerst op."
    };
  }
  const group = (cfg.voip?.groups ?? []).find((g) => g.id === opts.groupId);
  if (!group) {
    return {
      overlay: false,
      sip: false,
      error:
        "Belgroep staat nog niet op de server. Sla de configuratie eerst op."
    };
  }

  lastRingIntercomId = ic.id;
  answeredBroadcastFor = null;
  hub?.broadcastIntercomRing(ic.id, group.id);

  if (!cfg.voip?.enabled) {
    return {
      overlay: true,
      sip: false,
      error:
        "VoIP staat uit — alleen het paneel toont de oproep, geen SIP-rinkelen."
    };
  }

  const dial = groupDial(cfg, group.id);
  if (!dial) {
    return {
      overlay: true,
      sip: false,
      error:
        "Geen toestellen in deze belgroep op de server. Sla eerst op en vink gebruikers aan."
    };
  }

  const timeoutSec = Math.max(5, dial.timeout);
  const doorTargets = intercomRingTargets(ic);
  const onDoor = doorTargets.some((t) => t.ringGroupId === group.id);
  const defaultGroupId = (ic.intercom.ringGroupId ?? "").trim();
  const groupExt = astSafe(group.ext);
  const useDefaultDoor = onDoor && group.id === defaultGroupId;
  if (!useDefaultDoor && !groupExt) {
    return {
      overlay: true,
      sip: false,
      error:
        "Belgroep heeft nog geen intern nummer. Sla de configuratie eerst op."
    };
  }
  const channel = useDefaultDoor
    ? `Local/s@${doorContextName(ic)}`
    : onDoor
      ? `Local/${groupExt}@${doorContextName(ic)}`
      : `Local/${groupExt}@from-internal`;
  const callerName = ic.name.replace(/[\r\n"]/g, " ").trim() || "Intercom";
  const callerExt = (ic.intercom.sipExt ?? "test").replace(/[<>\r\n]/g, "");

  try {
    await ensureAmi();
    if (!ami?.connected) {
      return {
        overlay: true,
        sip: false,
        error:
          "Asterisk is niet bereikbaar — het paneel toont de oproep, tablets rinkelen niet via SIP."
      };
    }
    const evs = await ami.send(
      {
        Action: "Originate",
        Channel: channel,
        Application: "Wait",
        Data: String(timeoutSec),
        CallerID: `"${callerName}" <${callerExt}>`,
        Async: "true",
        Timeout: String((timeoutSec + 8) * 1000),
        Variable: `INTERCOM_ID=${ic.id}`
      },
      10_000
    );
    const ok = evs[0]?.Response === "Success";
    if (!ok) {
      return {
        overlay: true,
        sip: false,
        error: evs[0]?.Message || "SIP-oproep starten mislukt."
      };
    }
    return { overlay: true, sip: true };
  } catch (err) {
    logger.warn(
      { err, groupId: group.id, intercomId: ic.id },
      "test-ring originate mislukt"
    );
    return {
      overlay: true,
      sip: false,
      error: "SIP-oproep starten mislukt. Het paneel toont de oproep wel."
    };
  }
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
  const wasEnabled = cfg.voip?.enabled === true;
  normalizeVoip(cfg);
  if (!wasEnabled && cfg.voip?.enabled === true) {
    persistConfig(cfg);
  }
  const dir = writeAsteriskConfig(cfg);
  logger.info({ dir, enabled: cfg.voip?.enabled === true }, "Asterisk-config geschreven");
  if (!cfg.voip?.enabled) {
    ami?.close();
    ami = null;
    setDtmfAmiGetter(() => null);
    stopAsteriskProcess();
    return;
  }
  if (!legacyRemoved) {
    legacyRemoved = true;
    await removeLegacyAsteriskContainer();
  }
  const state = ensureAsteriskProcess(dir);
  // Net gestart proces heeft een paar seconden nodig voor poort 5038.
  await amiReload(state === "started" ? 15 : 1);
}

let legacyRemoved = false;

async function amiReload(attempts = 1): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      await ensureAmi();
      await ami?.command("core reload");
      return;
    } catch (err) {
      ami?.close();
      ami = null;
      logger.warn({ err, attempt }, "Asterisk reload mislukt (PBX nog niet draaiend?)");
      if (attempt < attempts) {
        await new Promise((r) => setTimeout(r, 1000));
      }
    }
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
    setDtmfAmiGetter(() => ami);
    logger.info({ host, port }, "AMI verbonden");
    void syncRegisteredContacts(client);
  } catch (err) {
    client.close();
    throw err;
  }
}

/** ContactStatus komt alleen bij wijzigingen; registraties van vóór de AMI-login ophalen. */
async function syncRegisteredContacts(client: AmiClient): Promise<void> {
  try {
    const evs = await client.send({ Action: "PJSIPShowContacts" });
    registered.clear();
    for (const ev of evs) {
      if (ev.Event !== "ContactList") continue;
      const aor = ev.AOR || "";
      const status = (ev.Status || "").toLowerCase();
      if (aor && status !== "unreachable" && status !== "removed") registered.add(aor);
    }
  } catch (err) {
    logger.debug({ err }, "PJSIPShowContacts mislukt");
  }
}

function onAmiEvent(ev: AmiFields): void {
  const event = ev.Event;
  if (event === "UserEvent" && (ev.UserEvent === "Archie" || ev.Kind)) {
    const kind = (ev.Kind ?? "").toLowerCase();
    const id = ev.IntercomId;
    if (!id) return;
    logCall(`door.${kind}`, ev.GroupId ? "groep" : "alle panelen");
    if (kind === "ring") {
      lastRingIntercomId = id;
      answeredBroadcastFor = null;
      if (ev.Channel) recordDoorChannel(id, ev.Channel);
      const line = intercomLines.onRing(id);
      if (line === "ringing") publishLine(id, "ringing");
      hub?.broadcastIntercomRing(id, ev.GroupId);
    }
    if (kind === "answered") {
      intercomLines.onBusy(id);
      publishLine(id, "busy");
      if (answeredBroadcastFor !== id) {
        answeredBroadcastFor = id;
        hub?.broadcastIntercomCleared(id);
      }
    }
    if (kind === "cleared") {
      if (lastRingIntercomId === id) lastRingIntercomId = null;
      idleLine(id);
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
    logCall("dial.begin", (ev.DestChannel || "").split("/")[0] || "?");
    const ic = ev.INTERCOM_ID || channelIntercom.get(ev.Linkedid || "") || channelIntercom.get(ev.Uniqueid || "");
    const uid = ev.DestUniqueid || ev.Uniqueid;
    if (ic && uid) channelIntercom.set(uid, ic);
    const linked = ev.Linkedid;
    if (ic && linked) channelIntercom.set(linked, ic);
    const destIsDoor = intercomIdForExt(pjsipExt(ev.DestChannel)) === ic;
    const chanIsDoor = intercomIdForExt(pjsipExt(ev.Channel)) === ic;
    const doorLeg = destIsDoor ? ev.DestChannel : chanIsDoor ? ev.Channel : ev.Channel;
    if (ic && doorLeg) recordDoorChannel(ic, doorLeg);
    const doorDest = intercomIdForExt(pjsipExt(ev.DestChannel));
    const doorChan = intercomIdForExt(pjsipExt(ev.Channel));
    if (doorDest) noteDoorChannel(doorDest, ev.DestChannel);
    if (doorChan) noteDoorChannel(doorChan, ev.Channel);
    return;
  }
  if (event === "DialEnd") {
    const status = (ev.DialStatus || "").toUpperCase();
    logCall("dial.end", status || "?");
    const answeredDoor = intercomIdForExt(pjsipExt(ev.DestChannel));
    if (status === "ANSWER" && answeredDoor) {
      intercomLines.onBusy(answeredDoor);
      publishLine(answeredDoor, "busy");
    }
    // CANCEL van één toestel is geen einde van de bel: Dial() loopt door
    // tot timeoutSec. Alleen opnemen stopt de andere panelen hier.
    // Afronden komt via UserEvent cleared.
    if (status === "ANSWER") {
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
    logCall("hangup", `${ev.Cause ?? "?"} ${ev["Cause-txt"] ?? ""}`.trim());
    const uid = ev.Uniqueid;
    const linked = ev.Linkedid;
    const ic = uid ? channelIntercom.get(uid) : (linked ? channelIntercom.get(linked) : undefined);
    if (uid) channelIntercom.delete(uid);
    if (linked) channelIntercom.delete(linked);
    if (ic) {
      clearDoorChannel(ic, ev.Channel);
    }
    const doorId = intercomIdForExt(pjsipExt(ev.Channel));
    if (
      doorId &&
      forgetDoorChannel(doorId, ev.Channel) &&
      intercomLines.hasHolder(doorId)
    ) {
      idleLine(doorId);
    }
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
    // Eigen PlayDTMF naar de deur niet opnieuw als KNX/HTTP-deuropen.
    if (effectiveIntercomReleaseMode(ic) === "dtmf") return;
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

