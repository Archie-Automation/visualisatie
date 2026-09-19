import { logger } from "./logger";
import { dispatch } from "./commands";
import {
  findRoom,
  findScene,
  getConfig,
  updateConfig
} from "./config";
import {
  configuredSceneAddressesForRoom,
  decodeSceneRecallByte,
  encodeSceneByte,
  extractSceneControlByte,
  isTrustedSceneGa,
  matchSceneLearnAddress,
  normalizeIndividualAddress,
  parseSceneLearnAddresses,
  valuePreview,
  type SceneLearnAddress
} from "./knxScene";
import type { KnxBus, KnxTelegram } from "./knxBus";
import type { Device, HouseConfig, Scene, GA } from "./types";

const LISTEN_MS = 20_000;
const SENTINEL_SETTLE_MS = 700;
const RECALL_WINDOW_MS = 1500;
const RECALL_IGNORE_MS = 180;
const BETWEEN_PASSES_MS = 400;

export type LearnedMember = {
  deviceId: string;
  name: string;
  type: string;
  kind: "light" | "shading";
  confirmed: boolean;
  on?: boolean;
  percent?: number;
  position?: number;
  noFeedback?: boolean;
};

export type SceneHeardPayload = {
  roomId: string;
  ga: string;
  number: number;
  trusted: boolean;
  memberIds?: string[];
  members?: LearnedMember[];
  existingId?: string;
  existingName?: string;
  timeout?: boolean;
  reason?: string;
  phase?: string;
  src?: string;
  switchName?: string;
  buttonName?: string;
  sceneName?: string;
};

type ListenPhase = "wait_button" | "busy";

type ListenSession = {
  roomId: string;
  userId: string;
  timer: ReturnType<typeof setTimeout>;
  watch: Set<string>;
  sceneGas: Set<string>;
  phase: ListenPhase;
  seen: number;
  ignoredSrc: number;
  shadeSnap: Map<string, number | undefined>;
};

export type ListenStart = {
  watching: string[];
  unknownFallback: boolean;
};

export type ListenStatus = ListenStart & {
  listening: boolean;
  heard: SceneHeardPayload | null;
  phase?: ListenPhase;
};

let busRef: KnxBus | null = null;
let broadcastHeard: ((p: SceneHeardPayload) => void) | null = null;
let listen: ListenSession | null = null;
let lastHeard: SceneHeardPayload | null = null;
let unsubTelegram: (() => void) | null = null;

export function attachKnxSceneLearn(
  bus: KnxBus,
  broadcast: (p: SceneHeardPayload) => void
): void {
  busRef = bus;
  broadcastHeard = broadcast;
  unsubTelegram?.();
  const onTelegram = (info: KnxTelegram) => onBusTelegram(info);
  bus.on("telegram", onTelegram);
  unsubTelegram = () => bus.off("telegram", onTelegram);
}

function isGroupRead(evt: string): boolean {
  return /GroupValue[_]?Read/i.test(evt);
}

function emitHeard(payload: SceneHeardPayload): void {
  logger.info(
    { ga: payload.ga, number: payload.number, timeout: payload.timeout, members: payload.memberIds?.length },
    "knx scene listen heard"
  );
  lastHeard = payload;
  stopListen();
  broadcastHeard?.(payload);
}

function findRoomKnxScene(
  cfg: HouseConfig,
  roomId: string,
  ga: string,
  number: number
): Scene | undefined {
  const room = findRoom(cfg, roomId);
  return room?.scenes?.find((s) => s.knx?.ga === ga && s.knx?.number === number);
}

function onBusTelegram(info: KnxTelegram): void {
  if (!listen || listen.phase !== "wait_button") return;
  if (info.self) return;
  const evt = String(info.evt ?? "");
  if (isGroupRead(evt)) return;
  const ga = String(info.ga ?? "").trim();
  if (!ga || !listen.sceneGas.has(ga)) return;
  const byte = extractSceneControlByte(info.value);
  const number = byte === null ? null : decodeSceneRecallByte(byte);
  listen.seen += 1;
  const matched = matchSceneLearnAddress(
    getConfig(),
    listen.roomId,
    ga,
    info.src
  );
  logger.info(
    {
      ga,
      src: info.src,
      matched: Boolean(matched),
      evt,
      byte,
      number,
      value: valuePreview(info.value)
    },
    "knx scene listen telegram"
  );
  if (byte === null || number === null) return;
  if (!matched) {
    listen.ignoredSrc += 1;
    logger.info(
      { ga, src: info.src, roomId: listen.roomId },
      "knx scene listen ignored: fysiek adres hoort niet bij deze kamer"
    );
    return;
  }
  listen.phase = "busy";
  const roomId = listen.roomId;
  const t0 = info.ts || Date.now();
  void runWizardAfterButton(roomId, ga, number, t0, info.src, matched).catch(async (err) => {
    logger.warn({ err, ga, number }, "knx scene wizard failed");
    emitHeard({
      roomId,
      ga: "",
      number: 0,
      trusted: false,
      timeout: true,
      reason: "wizard_failed"
    });
    await recoverBusIfDropped("scene wizard");
  });
}

export async function startListen(roomId: string, userId: string): Promise<ListenStart> {
  if (!findRoom(getConfig(), roomId)) throw new Error("unknown room");
  stopListen();
  lastHeard = null;
  const cfg = getConfig();
  const sceneGas = configuredSceneAddressesForRoom(cfg, roomId);
  if (sceneGas.length === 0) {
    throw new Error(
      "geen scene-adres voor deze kamer. Koppel een scene-GA aan deze ruimte in de installer (KNX)."
    );
  }
  const bus = busRef;
  if (!bus) throw new Error("KNX bus niet klaar");
  if (!bus.connected) throw new Error("KNX niet verbonden");
  const inRooms = devicesInRoom(cfg, roomId);
  const lights = inRooms.filter(isLightCandidate);
  const shades = inRooms.filter(isShadeCandidate);
  const foreignGas = foreignLightControlGas(cfg, roomId);
  logger.info(
    {
      roomId,
      lights: lights.map((d) => d.id),
      skippedShared: lights.filter((d) => !canWriteSentinel(d, foreignGas)).map((d) => d.id)
    },
    "scene listen: alleen lampen in deze kamer"
  );
  try {
    for (const d of lights) {
      try {
        await setLightSentinel(d, cfg, bus, 0, foreignGas);
      } catch (err) {
        logger.warn({ err, id: d.id }, "scene wizard sentinel 0 failed");
      }
    }
    await sleep(SENTINEL_SETTLE_MS);
    await requestStatuses(bus, lights);
    await sleep(SENTINEL_SETTLE_MS);
  } catch (err) {
    await recoverBusIfDropped("scene listen start");
    throw err;
  }
  const shadeSnap = new Map<string, number | undefined>();
  for (const d of shades) shadeSnap.set(d.id, shadePosition(d, bus));

  logger.info(
    { roomId, watching: sceneGas.length, sample: sceneGas.slice(0, 24) },
    "knx scene listen start (configured scene GAs)"
  );
  listen = {
    roomId,
    userId,
    watch: new Set(sceneGas),
    sceneGas: new Set(sceneGas),
    phase: "wait_button",
    seen: 0,
    ignoredSrc: 0,
    shadeSnap,
    timer: setTimeout(() => {
      if (!listen || listen.phase !== "wait_button") return;
      logger.info(
        { roomId, seen: listen.seen, ignoredSrc: listen.ignoredSrc },
        "knx scene listen timeout"
      );
      emitHeard({
        roomId,
        ga: "",
        number: 0,
        trusted: false,
        timeout: true,
        reason: listen.ignoredSrc > 0 ? "wrong_switch" : "timeout"
      });
    }, LISTEN_MS)
  };
  return { watching: sceneGas, unknownFallback: false };
}

export function getListenStatus(roomId: string): ListenStatus {
  const watching = listen?.roomId === roomId ? [...listen.watch] : [];
  return {
    listening: listen?.roomId === roomId,
    watching,
    unknownFallback: watching.length === 0,
    heard: lastHeard?.roomId === roomId ? lastHeard : null,
    phase: listen?.roomId === roomId ? listen.phase : undefined
  };
}

export function stopListen(): void {
  if (!listen) return;
  clearTimeout(listen.timer);
  listen = null;
}

function namesForHeard(
  roomId: string,
  ga: string,
  src: string | undefined,
  seed: SceneLearnAddress
): { switchName?: string; buttonName?: string; sceneName?: string } {
  const srcN = normalizeIndividualAddress(src || seed.physicalAddress);
  const rows = parseSceneLearnAddresses(getConfig()).filter((a) => {
    if (a.roomId !== roomId || a.ga !== ga) return false;
    if (!srcN || !a.physicalAddress) return true;
    return normalizeIndividualAddress(a.physicalAddress) === srcN;
  });
  const switchName = seed.switchName || rows.find((r) => r.switchName)?.switchName;
  const uniqueButtons = [
    ...new Set(rows.map((r) => r.buttonName).filter((n): n is string => Boolean(n)))
  ];
  const uniqueScenes = [
    ...new Set(rows.map((r) => r.name).filter((n): n is string => Boolean(n)))
  ];
  return {
    ...(switchName ? { switchName } : {}),
    ...(uniqueButtons.length === 1 ? { buttonName: uniqueButtons[0] } : {}),
    ...(uniqueScenes.length === 1 ? { sceneName: uniqueScenes[0] } : {})
  };
}

async function runWizardAfterButton(
  roomId: string,
  ga: string,
  number: number,
  t0: number,
  src?: string,
  matched?: SceneLearnAddress
): Promise<void> {
  const bus = busRef;
  if (!bus) throw new Error("KNX bus niet klaar");
  const cfg = getConfig();
  const inRooms = devicesInRoom(cfg, roomId);
  const shadeSnap = listen?.shadeSnap ?? new Map<string, number | undefined>();
  const result = await contrastAfterRecall(bus, cfg, inRooms, roomId, ga, number, {
    skipFirstRecall: true,
    t0,
    shadeSnap
  });
  const existing = findRoomKnxScene(cfg, roomId, ga, number);
  const names = matched ? namesForHeard(roomId, ga, src, matched) : {};
  emitHeard({
    roomId,
    ga,
    number,
    trusted: isTrustedSceneGa(ga, cfg),
    memberIds: result.memberIds,
    members: result.members,
    existingId: existing?.id,
    existingName: existing?.name,
    phase: "learned",
    ...(src ? { src } : {}),
    ...names
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function recoverBusIfDropped(reason: string): Promise<void> {
  const bus = busRef;
  if (!bus || bus.getStatus().simulate || bus.connected) return;
  logger.warn({ reason }, "KNX tunnel weg na scene-analyse — opnieuw verbinden");
  try {
    await bus.reconnect();
  } catch (err) {
    logger.warn({ err, reason }, "KNX reconnect na scene-analyse mislukt");
  }
}

function isLutronLight(d: Device): boolean {
  if (d.type !== "light_switch" && d.type !== "light_dimmer") return false;
  return d.control === "lutron";
}

function isLightCandidate(d: Device): boolean {
  if (isLutronLight(d)) return false;
  return (
    d.type === "light_switch" ||
    d.type === "light_dimmer" ||
    d.type === "rgbw_ww"
  );
}

function isShadeCandidate(d: Device): boolean {
  if ((d as { control?: string }).control === "lutron") return false;
  return d.type === "shading" || d.type === "position_actuator";
}

function devicesInRoom(cfg: HouseConfig, roomId: string): Device[] {
  const room = findRoom(cfg, roomId);
  if (!room) return [];
  const seen = new Set<string>();
  const out: Device[] = [];
  for (const d of room.devices ?? []) {
    if (!d?.id || seen.has(d.id)) continue;
    seen.add(d.id);
    out.push(d);
  }
  return out;
}

function lightControlGas(d: Device): GA[] {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  const pick = (...addrs: (string | undefined)[]) =>
    [...new Set(addrs.filter((x): x is string => Boolean(x)))];
  if (d.type === "light_switch") return pick(ga.switch);
  if (d.type === "light_dimmer") return pick(ga.dim_value, ga.switch);
  if (d.type === "rgbw_ww") {
    return pick(ga.on, ga.bright, ga.rgb232, ga.r, ga.g, ga.b, ga.w, ga.ww, ga.cw);
  }
  return [];
}

/** Stuur-GAs van lampen/gordijnen buiten deze kamer (niet aanschrijven). */
function foreignLightControlGas(cfg: HouseConfig, roomId: string): Set<string> {
  const out = new Set<string>();
  const addDevice = (d: Device) => {
    for (const ga of lightControlGas(d)) out.add(ga);
    if (!isShadeCandidate(d)) return;
    const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
    if (ga.position) out.add(ga.position);
    if (ga.up_down) out.add(ga.up_down);
  };
  for (const f of cfg.floors) {
    for (const r of f.rooms) {
      if (r.id === roomId) continue;
      for (const d of r.devices ?? []) addDevice(d);
    }
  }
  for (const d of cfg.devices ?? []) addDevice(d);
  return out;
}

function canWriteSentinel(d: Device, foreign: Set<string>): boolean {
  return lightControlGas(d).some((ga) => !foreign.has(ga));
}

function statusGas(d: Device): GA[] {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  if (d.type === "light_switch" || d.type === "light_dimmer") {
    return [ga.switch_status, ga.switch, ga.dim_status, ga.dim_value].filter(
      (x): x is string => Boolean(x)
    );
  }
  if (d.type === "rgbw_ww") {
    return [
      ga.on,
      ga.r,
      ga.g,
      ga.b,
      ga.w,
      ga.ww,
      ga.cw,
      ga.bright,
      ga.rgb232
    ].filter((x): x is string => Boolean(x));
  }
  if (d.type === "shading" || d.type === "position_actuator") {
    return [ga.position_status, ga.position].filter((x): x is string => Boolean(x));
  }
  return [];
}

/** Listen: alleen stuur en/of status, wat er is. Geen extra kanalen. */
function monitorGas(d: Device): GA[] {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  const pick = (...addrs: (string | undefined)[]) =>
    [...new Set(addrs.filter((x): x is string => Boolean(x)))];
  if (d.type === "light_switch") return pick(ga.switch, ga.switch_status);
  if (d.type === "light_dimmer") {
    const dim = pick(ga.dim_value, ga.dim_status);
    return dim.length ? dim : pick(ga.switch, ga.switch_status);
  }
  if (d.type === "rgbw_ww") {
    const level = pick(ga.bright, ga.on);
    return level.length ? level : pick(ga.rgb232);
  }
  if (d.type === "shading" || d.type === "position_actuator") {
    return pick(ga.position, ga.position_status);
  }
  return [];
}

function cacheNum(bus: KnxBus, ga?: string): number | boolean | undefined {
  if (!ga) return undefined;
  const v = bus.getState(ga)?.value;
  if (typeof v === "boolean" || typeof v === "number") return v;
  return undefined;
}

function lightLevel(d: Device, bus: KnxBus): { on: boolean; percent: number } {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  if (d.type === "light_switch") {
    const v = cacheNum(bus, ga.switch_status) ?? cacheNum(bus, ga.switch);
    const on = v === true || v === 1;
    return { on, percent: on ? 100 : 0 };
  }
  if (d.type === "light_dimmer") {
    const sw = cacheNum(bus, ga.switch_status) ?? cacheNum(bus, ga.switch);
    const dim = cacheNum(bus, ga.dim_status) ?? cacheNum(bus, ga.dim_value);
    const percent = typeof dim === "number" ? Math.round(dim) : sw === true || sw === 1 ? 100 : 0;
    const on = sw === true || sw === 1 || percent > 1;
    return { on, percent };
  }
  const onBit = cacheNum(bus, ga.on);
  const chans = [ga.r, ga.g, ga.b, ga.w, ga.ww, ga.cw, ga.bright]
    .map((g) => cacheNum(bus, g))
    .filter((v): v is number => typeof v === "number");
  const max = chans.length ? Math.max(...chans) : 0;
  const on = onBit === true || onBit === 1 || max > 8;
  return { on, percent: Math.round((max / 255) * 100) };
}

function shadePosition(d: Device, bus: KnxBus): number | undefined {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  const v = cacheNum(bus, ga.position_status) ?? cacheNum(bus, ga.position);
  return typeof v === "number" ? v : undefined;
}

function cacheTs(bus: KnxBus, gas: GA[]): number {
  let max = 0;
  for (const g of gas) {
    const ts = bus.getState(g)?.ts ?? 0;
    if (ts > max) max = ts;
  }
  return max;
}

/** Eén status-GA per apparaat — geen burst van switch+dim+rgb kanalen. */
function preferredStatusGa(d: Device): GA | undefined {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  if (d.type === "light_switch") return ga.switch_status || ga.switch;
  if (d.type === "light_dimmer") {
    return ga.dim_status || ga.switch_status || ga.dim_value || ga.switch;
  }
  if (d.type === "rgbw_ww") return ga.bright || ga.on || ga.rgb232;
  if (d.type === "shading" || d.type === "position_actuator") {
    return ga.position_status || ga.position;
  }
  return undefined;
}

async function requestStatuses(bus: KnxBus, devices: Device[]): Promise<void> {
  const seen = new Set<string>();
  for (const d of devices) {
    const ga = preferredStatusGa(d);
    if (!ga || seen.has(ga)) continue;
    seen.add(ga);
    bus.requestRead(ga);
  }
}

async function setLightSentinel(
  d: Device,
  cfg: HouseConfig,
  bus: KnxBus,
  level: 0 | 100,
  foreign: Set<string>
): Promise<void> {
  const unique = (ga?: string): ga is string =>
    typeof ga === "string" && ga.length > 0 && !foreign.has(ga);
  if (d.type === "light_switch") {
    const ga = d.ga.switch;
    if (!unique(ga)) {
      logger.warn({ id: d.id, ga }, "scene sentinel skip: switch-GA ook buiten deze kamer");
      return;
    }
    await dispatch({ kind: "light.switch", deviceId: d.id, on: level > 0 }, cfg, bus);
    return;
  }
  if (d.type === "light_dimmer") {
    const dim = d.ga.dim_value;
    const sw = d.ga.switch;
    if (unique(dim)) {
      await bus.write(dim, "dim_value", level);
      if (unique(sw)) await bus.write(sw, "switch", level > 0);
      return;
    }
    if (unique(sw)) {
      await dispatch({ kind: "light.switch", deviceId: d.id, on: level > 0 }, cfg, bus);
      return;
    }
    logger.warn(
      { id: d.id, dim, sw },
      "scene sentinel skip: dim/switch-GA ook buiten deze kamer"
    );
    return;
  }
  if (d.type !== "rgbw_ww") return;
  const ga = d.ga;
  const v = level > 0 ? 255 : 0;
  if (unique(ga.on)) {
    await bus.write(ga.on, "bit", level > 0);
    return;
  }
  if (unique(ga.bright)) {
    await bus.write(ga.bright, "byte", v);
    return;
  }
  if (unique(ga.rgb232)) {
    await bus.write(ga.rgb232, "rgb232", { red: v, green: v, blue: v });
    return;
  }
  const chans = ["r", "g", "b", "w", "ww", "cw"] as const;
  for (const ch of chans) {
    if (unique(ga[ch])) {
      await dispatch(
        { kind: "rgbw_ww.channel", deviceId: d.id, channel: ch, value: v },
        cfg,
        bus
      );
      return;
    }
  }
  logger.warn({ id: d.id }, "scene sentinel skip: rgbw-GA ook buiten deze kamer");
}

async function recallScene(bus: KnxBus, ga: string, number: number): Promise<void> {
  await bus.writeRaw(ga, Buffer.from([encodeSceneByte(number, false)]), 8);
}

function atSentinel(level: { on: boolean; percent: number }, target: 0 | 100): boolean {
  if (target === 0) return !level.on && level.percent <= 2;
  return level.percent >= 98 || (level.on && level.percent >= 90);
}

function learnedFromIds(
  inRooms: Device[],
  ids: string[],
  bus: KnxBus,
  noFeedback?: Set<string>
): LearnedMember[] {
  const byId = new Map(inRooms.map((d) => [d.id, d]));
  const out: LearnedMember[] = [];
  for (const id of ids) {
    const d = byId.get(id);
    if (!d) continue;
    if (isShadeCandidate(d)) {
      out.push({
        deviceId: d.id,
        name: d.name,
        type: d.type,
        kind: "shading",
        confirmed: false,
        position: shadePosition(d, bus)
      });
    } else {
      const lv = lightLevel(d, bus);
      out.push({
        deviceId: d.id,
        name: d.name,
        type: d.type,
        kind: "light",
        confirmed: true,
        on: lv.on,
        percent: lv.percent,
        noFeedback: noFeedback?.has(d.id)
      });
    }
  }
  return out;
}

async function contrastAfterRecall(
  bus: KnxBus,
  cfg: HouseConfig,
  inRooms: Device[],
  roomId: string,
  ga: string,
  number: number,
  opts: {
    skipFirstRecall: boolean;
    t0?: number;
    shadeSnap?: Map<string, number | undefined>;
  }
): Promise<{ memberIds: string[]; members: LearnedMember[] }> {
  const lights = inRooms.filter(isLightCandidate);
  const shades = inRooms.filter(isShadeCandidate);
  const foreign = foreignLightControlGas(cfg, roomId);
  const members = new Set<string>();
  const noFeedback = new Set<string>();
  const shadeHits = new Set<string>();
  const shadeSnap = opts.shadeSnap ?? new Map<string, number | undefined>();
  if (!opts.shadeSnap) {
    for (const d of shades) shadeSnap.set(d.id, shadePosition(d, bus));
  }

  let canPass: Device[] = [];
  if (!opts.skipFirstRecall) {
    for (const d of lights) {
      try {
        await setLightSentinel(d, cfg, bus, 0, foreign);
      } catch (err) {
        logger.warn({ err, id: d.id }, "scene learn sentinel 0 failed");
      }
    }
    await sleep(SENTINEL_SETTLE_MS);
    await requestStatuses(bus, lights);
    await sleep(SENTINEL_SETTLE_MS);
  }
  for (const d of lights) {
    const lv = lightLevel(d, bus);
    if (!atSentinel(lv, 0)) {
      noFeedback.add(d.id);
      continue;
    }
    canPass.push(d);
  }

  let t0 = opts.t0 ?? Date.now();
  if (!opts.skipFirstRecall) {
    t0 = Date.now();
    await recallScene(bus, ga, number);
    await sleep(RECALL_IGNORE_MS);
  }
  await requestStatuses(bus, [...canPass, ...shades]);
  await sleep(RECALL_WINDOW_MS);

  const remaining: Device[] = [];
  for (const d of canPass) {
    const lv = lightLevel(d, bus);
    const ts = cacheTs(bus, monitorGas(d).length ? monitorGas(d) : statusGas(d));
    const inWindow = ts > t0 && ts <= t0 + RECALL_WINDOW_MS + 400;
    if (inWindow && !atSentinel(lv, 0)) members.add(d.id);
    else remaining.push(d);
  }
  for (const d of shades) {
    const before = shadeSnap.get(d.id);
    const after = shadePosition(d, bus);
    const ts = cacheTs(bus, monitorGas(d).length ? monitorGas(d) : statusGas(d));
    const inWindow = ts > t0 && ts <= t0 + RECALL_WINDOW_MS + 400;
    if (
      inWindow &&
      after !== undefined &&
      before !== undefined &&
      Math.abs(after - before) >= 2
    ) {
      shadeHits.add(d.id);
    }
  }

  await sleep(BETWEEN_PASSES_MS);
  for (const d of remaining) {
    try {
      await setLightSentinel(d, cfg, bus, 100, foreign);
    } catch (err) {
      logger.warn({ err, id: d.id }, "scene learn sentinel 100 failed");
    }
  }
  await sleep(SENTINEL_SETTLE_MS);
  await requestStatuses(bus, remaining);
  await sleep(SENTINEL_SETTLE_MS);

  const still: Device[] = [];
  for (const d of remaining) {
    const lv = lightLevel(d, bus);
    if (!atSentinel(lv, 100)) {
      noFeedback.add(d.id);
      continue;
    }
    still.push(d);
  }

  const t1 = Date.now();
  await recallScene(bus, ga, number);
  await sleep(RECALL_IGNORE_MS);
  await requestStatuses(bus, still);
  await sleep(RECALL_WINDOW_MS);

  for (const d of still) {
    const lv = lightLevel(d, bus);
    const ts = cacheTs(bus, monitorGas(d).length ? monitorGas(d) : statusGas(d));
    const inWindow = ts > t1 && ts <= t1 + RECALL_WINDOW_MS + 200;
    if (inWindow && !atSentinel(lv, 100)) members.add(d.id);
  }

  const memberIds = [...members, ...shadeHits].filter((id) =>
    inRooms.some((d) => d.id === id)
  );
  const memberSet = new Set(memberIds);
  for (const d of lights) {
    if (memberSet.has(d.id)) continue;
    try {
      await setLightSentinel(d, cfg, bus, 0, foreign);
    } catch (err) {
      logger.warn({ err, id: d.id }, "scene wizard restore non-member failed");
    }
  }

  return {
    memberIds,
    members: learnedFromIds(inRooms, memberIds, bus, noFeedback)
  };
}

export async function learnKnxScene(opts: {
  roomId: string;
  ga: string;
  number: number;
  memberIds?: string[];
  name?: string;
  src?: string;
  switchName?: string;
  buttonName?: string;
}): Promise<{ scene: Scene; members: LearnedMember[] }> {
  const bus = busRef;
  if (!bus) throw new Error("KNX bus niet klaar");
  const cfg = getConfig();
  const room = findRoom(cfg, opts.roomId);
  if (!room) throw new Error("unknown room");
  const number = Math.min(64, Math.max(1, Math.round(opts.number)));
  const ga = opts.ga.trim();
  if (!ga) throw new Error("geen groepsadres");

  const inRooms = devicesInRoom(cfg, opts.roomId);
  const allowed = new Set(inRooms.map((d) => d.id));
  const memberIds = (opts.memberIds ?? []).filter((id) => allowed.has(id));
  const knxMeta = {
    src: opts.src?.trim() || undefined,
    switchName: opts.switchName?.trim() || undefined,
    buttonName: opts.buttonName?.trim() || undefined
  };

  if (opts.memberIds) {
    const scene = upsertRoomScene(
      opts.roomId,
      ga,
      number,
      memberIds,
      opts.name,
      knxMeta
    );
    return { scene, members: learnedFromIds(inRooms, memberIds, bus) };
  }
  const result = await contrastAfterRecall(bus, cfg, inRooms, opts.roomId, ga, number, {
    skipFirstRecall: false
  });
  const scene = upsertRoomScene(
    opts.roomId,
    ga,
    number,
    result.memberIds,
    opts.name,
    knxMeta
  );
  return { scene, members: result.members };
}

function upsertRoomScene(
  roomId: string,
  ga: string,
  number: number,
  memberIds: string[],
  name?: string,
  knxMeta?: { src?: string; switchName?: string; buttonName?: string }
): Scene {
  let saved: Scene | undefined;
  const label = name?.trim();
  const src = knxMeta?.src?.trim();
  const switchName = knxMeta?.switchName?.trim();
  const buttonName = knxMeta?.buttonName?.trim();
  updateConfig((draft) => {
    for (const f of draft.floors) {
      for (const r of f.rooms) {
        if (r.id !== roomId) continue;
        const scenes = r.scenes ?? [];
        let sc = scenes.find((s) => s.knx?.ga === ga && s.knx?.number === number);
        const knx = {
          ga,
          number,
          ...(src ? { src } : sc?.knx?.src ? { src: sc.knx.src } : {}),
          ...(switchName
            ? { switchName }
            : sc?.knx?.switchName
              ? { switchName: sc.knx.switchName }
              : {}),
          ...(buttonName
            ? { buttonName }
            : sc?.knx?.buttonName
              ? { buttonName: sc.knx.buttonName }
              : {})
        };
        if (!sc) {
          sc = {
            id: `scn-knx-${roomId}-${ga.replace(/\//g, "-")}-${number}`,
            name: label || `Scene ${number}`,
            actions: [],
            knx,
            members: memberIds
          };
          scenes.push(sc);
          r.scenes = scenes;
        } else {
          sc.knx = knx;
          sc.members = memberIds;
          if (label) sc.name = label;
        }
        saved = sc;
      }
    }
  });
  if (!saved) throw new Error("kamer niet gevonden");
  return saved;
}

export async function storeKnxScene(
  scene: Scene,
  bus: KnxBus,
  memberIds?: string[],
  name?: string
): Promise<void> {
  const knx = scene.knx;
  if (!knx?.ga) throw new Error("geen KNX-scene");
  if (memberIds || name?.trim()) {
    updateConfig((draft) => {
      const hit = findScene(draft, scene.id);
      if (!hit) return;
      if (memberIds) hit.scene.members = memberIds;
      if (name?.trim()) hit.scene.name = name.trim();
    });
  }
  await bus.writeRaw(knx.ga, Buffer.from([encodeSceneByte(knx.number, true)]), 8);
}

export async function recallKnxBinding(scene: Scene, bus: KnxBus): Promise<void> {
  const knx = scene.knx;
  if (!knx?.ga) throw new Error("geen KNX-scene");
  await recallScene(bus, knx.ga, knx.number);
}

/** Verwijdert alleen de app-inlezing. ETS-scene blijft bestaan. */
export function forgetKnxRoomScene(roomId: string, sceneId: string): void {
  let found = false;
  updateConfig((draft) => {
    for (const f of draft.floors) {
      for (const r of f.rooms) {
        if (r.id !== roomId) continue;
        const scenes = r.scenes ?? [];
        const hit = scenes.find((s) => s.id === sceneId);
        if (!hit?.knx?.ga) return;
        r.scenes = scenes.filter((s) => s.id !== sceneId);
        found = true;
      }
    }
  });
  if (!found) throw new Error("unknown knx scene");
}
