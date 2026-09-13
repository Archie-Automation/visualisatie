import { logger } from "./logger";
import { dispatch } from "./commands";
import {
  collectAllGAs,
  findRoom,
  findScene,
  getConfig,
  updateConfig,
  walkDevices
} from "./config";
import {
  decodeSceneRecallByte,
  encodeSceneByte,
  extractSceneByte,
  isTrustedSceneGa,
  valuePreview,
  watchSceneAddresses
} from "./knxScene";
import type { KnxBus, KnxTelegram } from "./knxBus";
import type { Device, HouseConfig, Scene, GA } from "./types";

const LISTEN_MS = 20_000;
const SENTINEL_SETTLE_MS = 700;
const RECALL_WINDOW_MS = 1500;
const RECALL_IGNORE_MS = 180;
const BETWEEN_PASSES_MS = 400;

export type SceneHeardPayload = {
  roomId: string;
  ga: string;
  number: number;
  trusted: boolean;
  timeout?: boolean;
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

type ListenSession = {
  roomId: string;
  userId: string;
  timer: ReturnType<typeof setTimeout>;
  watch: Set<string>;
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

function collectWatchList(cfg: HouseConfig): string[] {
  const seen = new Set(watchSceneAddresses(cfg));
  walkDevices(cfg, (d) => {
    if (d.type !== "universal") return;
    for (const b of d.universal.buttons) {
      for (const a of [b.action, b.actionOff, b.actionLong]) {
        if (a?.role === "scene" && a.ga?.trim()) seen.add(a.ga.trim());
      }
    }
  });
  return [...seen];
}

function onBusTelegram(info: KnxTelegram): void {
  if (!listen) return;
  if (info.self) return;
  const evt = String(info.evt ?? "");
  if (/GroupValue[_]?Read/i.test(evt)) return;
  const ga = String(info.ga ?? "").trim();
  if (!ga) return;
  const onWatch = listen.watch.has(ga);
  const skipKnown = !onWatch && isKnownNonSceneGa(ga);
  const byte = extractSceneByte(info.value);
  const number = byte === null ? null : decodeSceneRecallByte(byte);
  listen.seen += 1;
  if (listen.seen <= 80 || onWatch || (!skipKnown && number !== null)) {
    logger.info(
      {
        ga,
        src: info.src,
        evt,
        onWatch,
        skipKnown,
        byte,
        number,
        roles: busRef?.getGaRoles(ga).map((r) => r.role) ?? [],
        value: valuePreview(info.value)
      },
      "knx scene listen telegram"
    );
  }
  if (skipKnown) return;
  if (byte === null || number === null) return;
  const cfg = getConfig();
  const trusted = onWatch || isTrustedSceneGa(ga, cfg);
  const payload: SceneHeardPayload = {
    roomId: listen.roomId,
    ga,
    number,
    trusted
  };
  logger.info(payload, "knx scene listen heard");
  lastHeard = payload;
  stopListen();
  broadcastHeard?.(payload);
}

export function startListen(roomId: string, userId: string): ListenStart {
  if (!findRoom(getConfig(), roomId)) throw new Error("unknown room");
  stopListen();
  lastHeard = null;
  const watching = collectWatchList(getConfig());
  const unknownFallback = watching.length === 0;
  logger.info(
    { roomId, watching: watching.length, unknownFallback, sample: watching.slice(0, 20) },
    "knx scene listen start"
  );
  void busRef?.refreshGroupAddresses(collectAllGAs(getConfig())).catch((err) => {
    logger.warn({ err }, "knx scene listen GA refresh failed");
  });
  listen = {
    roomId,
    userId,
    watch: new Set(watching),
    unknownFallback,
    seen: 0,
    timer: setTimeout(() => {
      logger.info({ roomId, seen: listen?.seen ?? 0 }, "knx scene listen timeout");
      const payload: SceneHeardPayload = {
        roomId,
        ga: "",
        number: 0,
        trusted: false,
        timeout: true
      };
      lastHeard = payload;
      if (broadcastHeard) broadcastHeard(payload);
      stopListen();
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

export async function learnKnxScene(opts: {
  roomId: string;
  ga: string;
  number: number;
  extraRoomIds?: string[];
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
