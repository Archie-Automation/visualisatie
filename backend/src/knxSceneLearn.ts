import { logger } from "./logger";
import { dispatch } from "./commands";
import {
  findRoom,
  findScene,
  getConfig,
  updateConfig,
  walkDevices
} from "./config";
import {
  decodeSceneRecallByte,
  encodeSceneByte,
  extractSceneControlByte,
  isTrustedSceneGa,
  valuePreview
} from "./knxScene";
import type { KnxBus, KnxTelegram } from "./knxBus";
import type { Device, HouseConfig, Scene, GA } from "./types";

const LISTEN_MS = 20_000;
/** Scene-GA zit typisch pal vóór de eerste status van een kamer-apparaat. */
const SCENE_BEFORE_MS = 800;
const SCENE_AFTER_MS = 250;
const BURST_QUIET_MS = 800;
const SENTINEL_SETTLE_MS = 700;
const RECALL_WINDOW_MS = 1500;
const RECALL_IGNORE_MS = 180;
const BETWEEN_PASSES_MS = 400;

export type SceneHeardPayload = {
  roomId: string;
  ga: string;
  number: number;
  trusted: boolean;
  memberIds?: string[];
  timeout?: boolean;
  reason?: string;
};

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

type SceneCandidate = { ga: string; number: number; ts: number };

type ListenSession = {
  roomId: string;
  userId: string;
  timer: ReturnType<typeof setTimeout>;
  settle: ReturnType<typeof setTimeout> | null;
  watch: Set<string>;
  roomGas: Set<string>;
  gaToDevice: Map<string, string>;
  lastScene: SceneCandidate | null;
  firstMemberTs: number | null;
  memberIds: Set<string>;
  unknownFallback: boolean;
  seen: number;
};

export type ListenStart = {
  watching: string[];
  unknownFallback: boolean;
};

export type ListenStatus = ListenStart & {
  listening: boolean;
  heard: SceneHeardPayload | null;
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

function isKnownNonSceneGa(ga: string): boolean {
  const roles = busRef?.getGaRoles(ga) ?? [];
  if (roles.length === 0) return false;
  return roles.every((r) => r.role !== "scene");
}

function isGroupRead(evt: string): boolean {
  return /GroupValue[_]?Read/i.test(evt);
}

function pickScene(s: ListenSession): SceneCandidate | null {
  if (!s.lastScene) return null;
  if (s.firstMemberTs == null) return s.lastScene;
  const dt = s.firstMemberTs - s.lastScene.ts;
  if (dt >= 0 && dt <= SCENE_BEFORE_MS) return s.lastScene;
  if (dt < 0 && -dt <= SCENE_AFTER_MS) return s.lastScene;
  return null;
}

function emitHeard(payload: SceneHeardPayload): void {
  logger.info(payload, "knx scene listen heard");
  lastHeard = payload;
  stopListen();
  broadcastHeard?.(payload);
}

function tryFinishBurst(fromTimeout: boolean): void {
  if (!listen) return;
  const scene = pickScene(listen);
  const members = [...listen.memberIds];
  if (scene && members.length > 0) {
    const cfg = getConfig();
    emitHeard({
      roomId: listen.roomId,
      ga: scene.ga,
      number: scene.number,
      trusted: isTrustedSceneGa(scene.ga, cfg),
      memberIds: members
    });
    return;
  }
  if (!fromTimeout) return;
  emitHeard({
    roomId: listen.roomId,
    ga: "",
    number: 0,
    trusted: false,
    timeout: true,
    reason: members.length > 0 ? "no_scene_byte" : "timeout",
    memberIds: members
  });
}

function armSettle(): void {
  if (!listen) return;
  if (listen.settle) clearTimeout(listen.settle);
  listen.settle = setTimeout(() => tryFinishBurst(false), BURST_QUIET_MS);
}

function onBusTelegram(info: KnxTelegram): void {
  if (!listen) return;
  if (info.self) return;
  const evt = String(info.evt ?? "");
  if (isGroupRead(evt)) return;
  const ga = String(info.ga ?? "").trim();
  if (!ga) return;
  const now = info.ts || Date.now();
  const isRoom = listen.roomGas.has(ga);
  const byte = extractSceneControlByte(info.value);
  const number = byte === null ? null : decodeSceneRecallByte(byte);
  listen.seen += 1;
  if (listen.seen <= 80 || isRoom || number !== null) {
    logger.info(
      {
        ga,
        src: info.src,
        evt,
        isRoom,
        byte,
        number,
        roles: busRef?.getGaRoles(ga).map((r) => r.role) ?? [],
        value: valuePreview(info.value)
      },
      "knx scene listen telegram"
    );
  }
  if (isRoom) {
    const deviceId = listen.gaToDevice.get(ga);
    if (deviceId) listen.memberIds.add(deviceId);
    if (listen.firstMemberTs == null) listen.firstMemberTs = now;
    armSettle();
    return;
  }
  if (byte === null || number === null) return;
  if (isKnownNonSceneGa(ga)) return;
  if (listen.firstMemberTs == null) {
    listen.lastScene = { ga, number, ts: now };
    return;
  }
  if (now - listen.firstMemberTs <= SCENE_AFTER_MS) {
    const existing = listen.lastScene;
    const stale =
      !existing ||
      Math.abs(listen.firstMemberTs - existing.ts) > SCENE_BEFORE_MS;
    if (stale) listen.lastScene = { ga, number, ts: now };
    armSettle();
  }
}

export function startListen(roomId: string, userId: string): ListenStart {
  if (!findRoom(getConfig(), roomId)) throw new Error("unknown room");
  stopListen();
  lastHeard = null;
  const { roomGas, gaToDevice } = collectRoomMonitor(getConfig(), roomId);
  const watching = [...roomGas];
  const unknownFallback = watching.length === 0;
  logger.info(
    { roomId, watching: watching.length, sample: watching.slice(0, 24) },
    "knx scene listen start (room device GAs)"
  );
  listen = {
    roomId,
    userId,
    watch: new Set(watching),
    roomGas,
    gaToDevice,
    lastScene: null,
    firstMemberTs: null,
    memberIds: new Set(),
    settle: null,
    unknownFallback,
    seen: 0,
    timer: setTimeout(() => {
      logger.info(
        {
          roomId,
          seen: listen?.seen ?? 0,
          members: listen ? listen.memberIds.size : 0,
          hasScene: Boolean(listen?.lastScene)
        },
        "knx scene listen timeout"
      );
      tryFinishBurst(true);
    }, LISTEN_MS)
  };
  return { watching, unknownFallback };
}

export function getListenStatus(roomId: string): ListenStatus {
  const watching = listen?.roomId === roomId ? [...listen.watch] : [];
  const unknownFallback =
    listen?.roomId === roomId ? listen.unknownFallback : watching.length === 0;
  return {
    listening: listen?.roomId === roomId,
    watching,
    unknownFallback,
    heard: lastHeard?.roomId === roomId ? lastHeard : null
  };
}

export function stopListen(): void {
  if (!listen) return;
  clearTimeout(listen.timer);
  if (listen.settle) clearTimeout(listen.settle);
  listen = null;
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
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

function devicesInRooms(cfg: HouseConfig, roomIds: Set<string>): Device[] {
  const out: Device[] = [];
  walkDevices(cfg, (d, roomId) => {
    if (roomIds.has(roomId)) out.push(d);
  });
  return out;
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

function monitorGas(d: Device): GA[] {
  const ga = (d as { ga?: Record<string, string | undefined> }).ga ?? {};
  const extra: GA[] = [];
  if (d.type === "shading" || d.type === "position_actuator") {
    extra.push(
      ...[ga.up_down, ga.stop_step, ga.slat, ga.slat_status, ga.moving].filter(
        (x): x is string => Boolean(x)
      )
    );
  }
  return [...new Set([...statusGas(d), ...extra])];
}

function collectRoomMonitor(
  cfg: HouseConfig,
  roomId: string
): { roomGas: Set<string>; gaToDevice: Map<string, string> } {
  const roomGas = new Set<string>();
  const gaToDevice = new Map<string, string>();
  for (const d of devicesInRooms(cfg, new Set([roomId]))) {
    if (!isLightCandidate(d) && !isShadeCandidate(d)) continue;
    for (const g of monitorGas(d)) {
      roomGas.add(g);
      gaToDevice.set(g, d.id);
    }
  }
  return { roomGas, gaToDevice };
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

async function requestStatuses(bus: KnxBus, devices: Device[]): Promise<void> {
  for (const d of devices) {
    for (const ga of statusGas(d)) bus.requestRead(ga);
  }
}

async function setLightSentinel(
  d: Device,
  cfg: HouseConfig,
  bus: KnxBus,
  level: 0 | 100
): Promise<void> {
  if (d.type === "light_switch") {
    await dispatch({ kind: "light.switch", deviceId: d.id, on: level > 0 }, cfg, bus);
    return;
  }
  if (d.type === "light_dimmer") {
    if (level === 0) {
      await dispatch({ kind: "light.switch", deviceId: d.id, on: false }, cfg, bus);
    } else {
      await dispatch({ kind: "light.dim", deviceId: d.id, percent: 100 }, cfg, bus);
    }
    return;
  }
  if (d.type !== "rgbw_ww") return;
  const ga = d.ga;
  const v = level > 0 ? 255 : 0;
  if (ga.on) await bus.write(ga.on, "bit", level > 0);
  if (ga.rgb232) {
    await bus.write(ga.rgb232, "rgb232", { red: v, green: v, blue: v });
  }
  const chans = ["r", "g", "b", "w", "ww", "cw"] as const;
  for (const ch of chans) {
    if (ga[ch]) {
      await dispatch(
        { kind: "rgbw_ww.channel", deviceId: d.id, channel: ch, value: v },
        cfg,
        bus
      );
    }
  }
  if (ga.bright) await bus.write(ga.bright, "byte", v);
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
  bus: KnxBus
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
        percent: lv.percent
      });
    }
  }
  return out;
}

export async function learnKnxScene(opts: {
  roomId: string;
  ga: string;
  number: number;
  extraRoomIds?: string[];
  memberIds?: string[];
}): Promise<{ scene: Scene; members: LearnedMember[] }> {
  const bus = busRef;
  if (!bus) throw new Error("KNX bus niet klaar");
  const cfg = getConfig();
  const room = findRoom(cfg, opts.roomId);
  if (!room) throw new Error("unknown room");
  const number = Math.min(64, Math.max(1, Math.round(opts.number)));
  const ga = opts.ga.trim();
  if (!ga) throw new Error("geen groepsadres");

  const roomIds = new Set<string>([opts.roomId, ...(opts.extraRoomIds ?? [])]);
  const inRooms = devicesInRooms(cfg, roomIds);

  if (opts.memberIds && opts.memberIds.length > 0) {
    const scene = upsertRoomScene(opts.roomId, ga, number, opts.memberIds);
    return { scene, members: learnedFromIds(inRooms, opts.memberIds, bus) };
  }
  const lights = inRooms.filter(isLightCandidate);
  const shades = inRooms.filter(isShadeCandidate);

  const members = new Set<string>();
  const noFeedback = new Set<string>();
  const shadeHits = new Set<string>();

  const shadeSnap = new Map<string, number | undefined>();
  for (const d of shades) shadeSnap.set(d.id, shadePosition(d, bus));

  for (const d of lights) {
    try {
      await setLightSentinel(d, cfg, bus, 0);
    } catch (err) {
      logger.warn({ err, id: d.id }, "scene learn sentinel 0 failed");
    }
  }
  await sleep(SENTINEL_SETTLE_MS);
  await requestStatuses(bus, lights);
  await sleep(SENTINEL_SETTLE_MS);

  const canPass: Device[] = [];
  for (const d of lights) {
    const lv = lightLevel(d, bus);
    if (!atSentinel(lv, 0)) {
      noFeedback.add(d.id);
      continue;
    }
    canPass.push(d);
  }

  const t0 = Date.now();
  await recallScene(bus, ga, number);
  await sleep(RECALL_IGNORE_MS);
  await requestStatuses(bus, [...canPass, ...shades]);
  await sleep(RECALL_WINDOW_MS);

  const remaining: Device[] = [];
  for (const d of canPass) {
    const lv = lightLevel(d, bus);
    const ts = cacheTs(bus, statusGas(d));
    const inWindow = ts > t0 && ts <= t0 + RECALL_WINDOW_MS + 200;
    if (inWindow && !atSentinel(lv, 0)) members.add(d.id);
    else remaining.push(d);
  }
  for (const d of shades) {
    const before = shadeSnap.get(d.id);
    const after = shadePosition(d, bus);
    const ts = cacheTs(bus, statusGas(d));
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
      await setLightSentinel(d, cfg, bus, 100);
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
    const ts = cacheTs(bus, statusGas(d));
    const inWindow = ts > t1 && ts <= t1 + RECALL_WINDOW_MS + 200;
    if (inWindow && !atSentinel(lv, 100)) members.add(d.id);
  }

  const memberIds = [...members, ...shadeHits];
  const learned: LearnedMember[] = [];
  const byId = new Map(inRooms.map((d) => [d.id, d]));
  for (const id of memberIds) {
    const d = byId.get(id);
    if (!d) continue;
    if (isShadeCandidate(d)) {
      learned.push({
        deviceId: d.id,
        name: d.name,
        type: d.type,
        kind: "shading",
        confirmed: false,
        position: shadePosition(d, bus)
      });
    } else {
      const lv = lightLevel(d, bus);
      learned.push({
        deviceId: d.id,
        name: d.name,
        type: d.type,
        kind: "light",
        confirmed: true,
        on: lv.on,
        percent: lv.percent,
        noFeedback: noFeedback.has(d.id)
      });
    }
  }

  const scene = upsertRoomScene(opts.roomId, ga, number, memberIds);
  return { scene, members: learned };
}

function upsertRoomScene(
  roomId: string,
  ga: string,
  number: number,
  memberIds: string[]
): Scene {
  let saved: Scene | undefined;
  updateConfig((draft) => {
    for (const f of draft.floors) {
      for (const r of f.rooms) {
        if (r.id !== roomId) continue;
        const scenes = r.scenes ?? [];
        let sc = scenes.find((s) => s.knx?.ga === ga && s.knx?.number === number);
        if (!sc) {
          sc = {
            id: `scn-knx-${roomId}-${ga.replace(/\//g, "-")}-${number}`,
            name: `Scene ${number}`,
            actions: [],
            knx: { ga, number },
            members: memberIds
          };
          scenes.push(sc);
          r.scenes = scenes;
        } else {
          sc.knx = { ga, number };
          sc.members = memberIds;
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
  memberIds?: string[]
): Promise<void> {
  const knx = scene.knx;
  if (!knx?.ga) throw new Error("geen KNX-scene");
  if (memberIds) {
    updateConfig((draft) => {
      const hit = findScene(draft, scene.id);
      if (hit) hit.scene.members = memberIds;
    });
  }
  await bus.writeRaw(knx.ga, Buffer.from([encodeSceneByte(knx.number, true)]), 8);
}

export async function recallKnxBinding(scene: Scene, bus: KnxBus): Promise<void> {
  const knx = scene.knx;
  if (!knx?.ga) throw new Error("geen KNX-scene");
  await recallScene(bus, knx.ga, knx.number);
}
