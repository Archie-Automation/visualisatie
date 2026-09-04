import { randomUUID } from "node:crypto";
import type { HouseConfig, VoipCallGroup, VoipEndpoint } from "../types";
import { randomAmiSecret, randomSipPassword } from "./secrets";

function usedExts(cfg: HouseConfig): Set<string> {
  const used = new Set<string>();
  for (const ep of cfg.voip?.endpoints ?? []) {
    if (ep.ext) used.add(ep.ext);
  }
  for (const g of cfg.voip?.groups ?? []) {
    if (g.ext) used.add(g.ext);
  }
  for (const ic of cfg.intercoms ?? []) {
    const ext = ic.intercom.sipExt?.trim();
    if (ext) used.add(ext);
  }
  return used;
}

function nextExt(used: Set<string>, start: number): string {
  let n = start;
  while (used.has(String(n))) n += 1;
  const ext = String(n);
  used.add(ext);
  return ext;
}

/**
 * Indoor SIP is 1:1 with a house user. No shared "app" identity, no
 * auto-SIP for every login. Orphan endpoints (no valid user) are dropped.
 */
export function normalizeVoip(cfg: HouseConfig): void {
  if (!cfg.voip) cfg.voip = { enabled: false };
  const v = cfg.voip;
  if (v.enabled !== true) return;
  if (!v.endpoints) v.endpoints = [];
  if (!v.groups) v.groups = [];
  if (!v.amiSecret) v.amiSecret = randomAmiSecret();
  if (!v.sipPort) v.sipPort = 5060;
  if (!v.wsPort) v.wsPort = 8088;
  if (!v.wssPort) v.wssPort = 8089;
  if (!v.rtpStart) v.rtpStart = 10000;
  if (!v.rtpEnd) v.rtpEnd = 10100;

  for (const ep of v.endpoints) {
    if (!ep.id) ep.id = `ep-${randomUUID()}`;
    if (ep.type === "app") ep.type = "panel";
    if (!ep.type) ep.type = "panel";
    if (!ep.name?.trim()) ep.name = "Toestel";
  }

  const users = cfg.users ?? [];
  const userById = new Map(users.map((u) => [u.id, u]));

  for (const u of users) {
    const sid = u.sipEndpointId?.trim();
    if (!sid) continue;
    const ep = v.endpoints.find((e) => e.id === sid);
    if (!ep) {
      delete u.sipEndpointId;
      continue;
    }
    if (!ep.userId) ep.userId = u.id;
    else if (ep.userId !== u.id) delete u.sipEndpointId;
  }

  const seenUser = new Set<string>();
  const kept: VoipEndpoint[] = [];
  for (const ep of v.endpoints) {
    const uid = ep.userId?.trim();
    if (!uid || !userById.has(uid)) continue;
    if (seenUser.has(uid)) continue;
    seenUser.add(uid);
    kept.push(ep);
  }
  v.endpoints = kept;

  for (const u of users) delete u.sipEndpointId;
  for (const ep of kept) {
    const u = userById.get(ep.userId!);
    if (!u) continue;
    u.sipEndpointId = ep.id;
    if (!ep.name?.trim() || ep.name === "Toestel") {
      const label = u.displayName?.trim() || u.username?.trim();
      if (label) ep.name = label;
    }
  }

  const used = usedExts(cfg);

  for (const ep of v.endpoints) {
    if (!ep.ext?.trim()) ep.ext = nextExt(used, 201);
    if (!ep.password) ep.password = randomSipPassword();
  }

  const epIds = new Set(v.endpoints.map((e) => e.id));
  for (const g of v.groups) {
    if (!g.id) g.id = `grp-${randomUUID()}`;
    if (!g.name?.trim()) g.name = "Oproepgroep";
    if (!g.ext?.trim()) g.ext = nextExt(used, 900);
    if (!Array.isArray(g.memberIds)) g.memberIds = [];
    g.memberIds = g.memberIds.filter((id) => epIds.has(id));
    if (!g.timeoutSec || g.timeoutSec < 5) g.timeoutSec = 30;
  }

  if (v.groups.length === 0 && v.endpoints.length > 0) {
    const g: VoipCallGroup = {
      id: "grp-woning",
      name: "Woning",
      ext: nextExt(used, 900),
      memberIds: v.endpoints.map((e) => e.id),
      timeoutSec: 30
    };
    v.groups.push(g);
  }

  let doorExt = 101;
  for (const ic of cfg.intercoms ?? []) {
    const icfg = ic.intercom;
    if (!icfg.sipExt?.trim()) icfg.sipExt = nextExt(used, doorExt);
    doorExt = Math.max(doorExt, Number(icfg.sipExt) || 101);
    if (!icfg.sipPassword) icfg.sipPassword = randomSipPassword();
    if (!icfg.ringGroupId && v.groups[0]) icfg.ringGroupId = v.groups[0].id;
    if (icfg.dtmfDigit == null || !icfg.dtmfDigit.trim()) icfg.dtmfDigit = "#";
  }
}

export function mergeVoipSecrets(incoming: HouseConfig, previous: HouseConfig): void {
  const prevV = previous.voip;
  const nextV = incoming.voip;
  if (!nextV) return;

  if (!nextV.amiSecret && prevV?.amiSecret) {
    nextV.amiSecret = prevV.amiSecret;
  }

  const prevEp = new Map((prevV?.endpoints ?? []).map((e) => [e.id, e]));
  for (const ep of nextV.endpoints ?? []) {
    const prev = prevEp.get(ep.id);
    if ((!ep.password || ep.password.trim() === "") && prev?.password) {
      ep.password = prev.password;
    }
  }

  const prevIc = new Map((previous.intercoms ?? []).map((d) => [d.id, d]));
  for (const ic of incoming.intercoms ?? []) {
    const prev = prevIc.get(ic.id);
    if (!prev) continue;
    if ((!ic.intercom.sipPassword || ic.intercom.sipPassword.trim() === "") &&
      prev.intercom.sipPassword
    ) {
      ic.intercom.sipPassword = prev.intercom.sipPassword;
    }
    const sip = ic.intercom.sip;
    const prevSip = prev.intercom.sip;
    if (sip && prevSip && (!sip.password || sip.password.trim() === "") && prevSip.password) {
      sip.password = prevSip.password;
    }
    const db = ic.intercom.doorbird;
    const prevDb = prev.intercom.doorbird;
    if (db && prevDb && (!db.password || String(db.password).trim() === "") && prevDb.password) {
      db.password = prevDb.password;
    }
  }
}
