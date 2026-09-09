import type {
  WtwZehnderComfoConnect,
  WtwZehnderLogic,
  WtwZehnderStandId,
  WtwDucoConnectivityBoard,
  WtwDucoLogic,
  DucoStandId,
  WtwMvConfig,
  WtwMvLogic,
  WtwModel
} from "./types";
import type { KnxBus } from "./knxBus";

export const ZEHN_STANDS: ReadonlyArray<{
  id: WtwZehnderStandId;
  ga: keyof WtwZehnderComfoConnect;
  status: keyof WtwZehnderComfoConnect;
}> = [
  { id: "stand1", ga: "stand1Ga", status: "stand1StatusGa" },
  { id: "stand2", ga: "stand2Ga", status: "stand2StatusGa" },
  { id: "stand3", ga: "stand3Ga", status: "stand3StatusGa" },
  { id: "auto", ga: "autoGa", status: "autoStatusGa" },
  { id: "away", ga: "awayGa", status: "awayStatusGa" },
  { id: "boost", ga: "boostGa", status: "boostStatusGa" }
];

const MANUAL_STANDS = new Set<string>([
  "stand1",
  "stand2",
  "stand3",
  "away",
  "boost"
]);

/** ComfoConnect moet Auto-uit hebben verwerkt voordat een handmatige stand pakt. */
const AUTO_OFF_SETTLE_MS = 200;

export function asGa(v: unknown): string | undefined {
  const s = typeof v === "string" ? v.trim() : "";
  return s || undefined;
}

export function bitOn(value: unknown): boolean {
  return value === true || value === 1 || value === "1" || value === "true";
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function zehnderAutoIsOn(
  bus: KnxBus,
  z: WtwZehnderComfoConnect
): boolean {
  const ga = asGa(z.autoStatusGa);
  if (!ga) return false;
  const st = bus.getState(ga);
  if (!st) return false;
  return bitOn(st.value);
}

/** Actieve stand; Auto wint als die aan is, ook als een snelheid-bit nog 1 is. */
export function readZehnderActiveStand(
  bus: KnxBus,
  z: WtwZehnderComfoConnect
): WtwZehnderStandId {
  if (zehnderAutoIsOn(bus, z)) return "auto";
  for (const s of ZEHN_STANDS) {
    if (s.id === "auto") continue;
    const ga = asGa(z[s.status]);
    if (!ga) continue;
    if (bitOn(bus.getState(ga)?.value)) return s.id;
  }
  return "auto";
}

export function zehnderWriteGa(
  z: WtwZehnderComfoConnect,
  id: string
): string | undefined {
  const row = ZEHN_STANDS.find((s) => s.id === id);
  return row ? asGa(z[row.ga]) : undefined;
}

export async function writeBoostMinutes(
  z: WtwZehnderComfoConnect,
  bus: KnxBus,
  minutes: number
): Promise<boolean> {
  const ga = asGa(z.boostTimeGa);
  if (!ga) return false;
  const clamped = Math.min(180, Math.max(1, Math.round(minutes)));
  await bus.write(ga, "uint16", Math.min(65535, clamped * 60));
  return true;
}

/** Ingestelde boostduur in minuten (status-GA, anders set-GA, anders config). */
export function readBoostMinutes(
  bus: KnxBus,
  z: WtwZehnderComfoConnect
): number {
  for (const key of ["boostTimeStatusGa", "boostTimeGa"] as const) {
    const ga = asGa(z[key]);
    if (!ga) continue;
    const raw = bus.getState(ga)?.value;
    const n = typeof raw === "number" ? raw : Number(raw);
    if (!Number.isFinite(n) || n <= 0) continue;
    if (n >= 60) return Math.min(180, Math.max(1, Math.round(n / 60)));
    return Math.min(180, Math.max(1, Math.round(n)));
  }
  return Math.min(180, Math.max(1, z.minutes ?? 30));
}

export async function writeZehnderAuto(
  z: WtwZehnderComfoConnect,
  bus: KnxBus,
  on: boolean
): Promise<boolean> {
  const ga = asGa(z.autoGa);
  if (!ga) return false;
  await bus.write(ga, "bit", on);
  return true;
}

/**
 * Handmatige stand (1/2/3, afwezig, boost): altijd eerst Auto uit, daarna de stand.
 * Auto zelf is alleen aan/uit.
 */
export async function pressZehnderStand(
  z: WtwZehnderComfoConnect,
  bus: KnxBus,
  cmd: { buttonId: string; minutes?: number; on?: boolean }
): Promise<void> {
  const ga = zehnderWriteGa(z, cmd.buttonId);
  if (!ga) throw new Error("onbekende of lege WTW-stand");

  if (cmd.buttonId === "auto") {
    await bus.write(ga, "bit", cmd.on === false ? false : true);
    return;
  }

  if (MANUAL_STANDS.has(cmd.buttonId) && asGa(z.autoGa)) {
    await writeZehnderAuto(z, bus, false);
    await delay(AUTO_OFF_SETTLE_MS);
  }

  if (cmd.buttonId === "boost" && cmd.on !== false) {
    await writeBoostMinutes(z, bus, cmd.minutes ?? z.minutes ?? 30);
  }
  await bus.write(ga, "bit", cmd.on === false ? false : true);
}

export function zehnderLogics(
  z: WtwZehnderComfoConnect
): WtwZehnderLogic[] {
  return Array.isArray(z.logics) ? z.logics : [];
}

export function collectZehnderSubscriptions(z: WtwZehnderComfoConnect): Array<{
  ga: string;
  role: string;
}> {
  const out: Array<{ ga: string; role: string }> = [];
  const add = (raw: unknown, role: string) => {
    const ga = asGa(raw);
    if (ga) out.push({ ga, role });
  };
  for (const s of ZEHN_STANDS) {
    add(z[s.ga], "bit");
    add(z[s.status], "bit");
  }
  add(z.boostTimeGa, "uint16");
  add(z.boostTimeStatusGa, "uint16");
  add(z.faultGa, "bit");
  add(z.filterGa, "bit");
  add(z.filterDaysGa, "uint16");
  for (const logic of zehnderLogics(z)) {
    add(logic.triggerGa, "bit");
    add(logic.orGa, "bit");
    add(logic.untilGa, "bit");
    for (const c of logic.when ?? []) add(c.ga, "bit");
    for (const c of logic.untilWhen ?? []) add(c.ga, "bit");
    if (logic.triggerMode === "tempRise" && logic.tempRise) {
      add(logic.tempRise.ga, "temperature");
    }
  }
  return out;
}

/* ===================================================================== */
/*  Duco Connectivity Board (Modbus TCP via KNX)                         */
/* ===================================================================== */

/** Byte-waarde per stand. */
export const DUCO_STAND_BYTE: Record<DucoStandId, number> = {
  auto: 0,
  away: 7,
  stand1: 8,
  stand2: 9,
  stand3: 10
};

/** Omgekeerde lookup: byte → stand. */
const DUCO_BYTE_STAND = new Map<number, DucoStandId>(
  Object.entries(DUCO_STAND_BYTE).map(([id, byte]) => [byte, id as DucoStandId])
);

/** Lees de actieve stand van het status-GA (byte). */
export function readDucoActiveStand(bus: KnxBus, d: WtwDucoConnectivityBoard): DucoStandId {
  const ga = asGa(d.statusGa);
  if (!ga) return "auto";
  const raw = bus.getState(ga)?.value;
  const n = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isFinite(n)) return "auto";
  return DUCO_BYTE_STAND.get(Math.round(n)) ?? "auto";
}

/** Schrijf stand naar het command-GA. */
export async function pressDucoStand(
  d: WtwDucoConnectivityBoard,
  bus: KnxBus,
  cmd: { buttonId: string; on?: boolean }
): Promise<void> {
  const ga = asGa(d.commandGa);
  if (!ga) throw new Error("Duco command-GA ontbreekt");
  const standId = cmd.buttonId as DucoStandId;
  const byte = DUCO_STAND_BYTE[standId];
  if (byte === undefined) throw new Error(`Onbekende Duco-stand: ${cmd.buttonId}`);
  await bus.write(ga, "byte", byte);
}

export function ducoLogics(d: WtwDucoConnectivityBoard): WtwDucoLogic[] {
  return Array.isArray(d.logics) ? d.logics : [];
}

export function collectDucoSubscriptions(d: WtwDucoConnectivityBoard): Array<{
  ga: string;
  role: string;
}> {
  const out: Array<{ ga: string; role: string }> = [];
  const add = (raw: unknown, role: string) => {
    const ga = asGa(raw);
    if (ga) out.push({ ga, role });
  };
  add(d.commandGa, "byte");
  add(d.statusGa, "byte");
  add(d.faultGa, "bit");
  add(d.filterGa, "bit");
  add(d.filterDaysGa, "uint16");
  for (const logic of ducoLogics(d)) {
    add(logic.triggerGa, "bit");
    add(logic.orGa, "bit");
    add(logic.untilGa, "bit");
    for (const c of logic.when ?? []) add(c.ga, "bit");
    for (const c of logic.untilWhen ?? []) add(c.ga, "bit");
    if (logic.triggerMode === "tempRise" && logic.tempRise) {
      add(logic.tempRise.ga, "temperature");
    }
  }
  return out;
}

/* ===================================================================== */
/*  MV — Mechanische Ventilatie                                          */
/* ===================================================================== */

export function mvLogics(mv: WtwMvConfig): WtwMvLogic[] {
  return Array.isArray(mv.logics) ? mv.logics : [];
}

function readMv1ContactStand(bus: KnxBus, mv: WtwMvConfig): string {
  const ga = asGa(mv.switchStatusGa);
  if (!ga) return "low";
  return bitOn(bus.getState(ga)?.value) ? "high" : "low";
}

function readMv0_10vStand(bus: KnxBus, mv: WtwMvConfig): string {
  const ga = asGa(mv.statusGa);
  if (!ga || !mv.stands?.length) return "";
  const raw = bus.getState(ga)?.value;
  const n = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isFinite(n)) return mv.stands[0]?.id ?? "";
  const pct = Math.round((n / 255) * 100);
  let best = mv.stands[0];
  let bestDist = Math.abs(pct - (best?.percent ?? 0));
  for (const s of mv.stands) {
    const dist = Math.abs(pct - s.percent);
    if (dist < bestDist) { best = s; bestDist = dist; }
  }
  return best?.id ?? "";
}

export function readMvActiveStand(
  model: WtwModel,
  bus: KnxBus,
  mv: WtwMvConfig
): string {
  if (model === "mv_1contact") return readMv1ContactStand(bus, mv);
  if (model === "mv_0_10v") return readMv0_10vStand(bus, mv);
  return "";
}

export async function pressMvStand(
  model: WtwModel,
  mv: WtwMvConfig,
  bus: KnxBus,
  standId: string
): Promise<void> {
  if (model === "mv_1contact") {
    const ga = asGa(mv.switchGa);
    if (!ga) throw new Error("MV switchGa ontbreekt");
    await bus.write(ga, "bit", standId === "high");
    return;
  }
  if (model === "mv_scene") {
    const ga = asGa(mv.sceneGa);
    if (!ga) throw new Error("MV sceneGa ontbreekt");
    const sceneNum =
      standId === "low" ? mv.sceneLow :
      standId === "mid" ? mv.sceneMid :
      standId === "high" ? mv.sceneHigh : undefined;
    if (sceneNum == null) throw new Error(`MV scene-nummer voor '${standId}' ontbreekt`);
    await bus.write(ga, "scene_number", sceneNum);
    return;
  }
  if (model === "mv_0_10v") {
    const ga = asGa(mv.commandGa);
    if (!ga) throw new Error("MV commandGa ontbreekt");
    const stand = (mv.stands ?? []).find((s) => s.id === standId);
    if (!stand) throw new Error(`MV stand '${standId}' niet gevonden`);
    const byte = Math.round((stand.percent / 100) * 255);
    await bus.write(ga, "byte", Math.min(255, Math.max(0, byte)));
    return;
  }
  throw new Error(`Onbekend MV-model: ${model}`);
}

export function collectMvSubscriptions(
  model: WtwModel,
  mv: WtwMvConfig
): Array<{ ga: string; role: string }> {
  const out: Array<{ ga: string; role: string }> = [];
  const add = (raw: unknown, role: string) => {
    const ga = asGa(raw);
    if (ga) out.push({ ga, role });
  };
  if (model === "mv_1contact") {
    add(mv.switchGa, "bit");
    add(mv.switchStatusGa, "bit");
  }
  if (model === "mv_scene") {
    add(mv.sceneGa, "scene_number");
  }
  if (model === "mv_0_10v") {
    add(mv.commandGa, "byte");
    add(mv.statusGa, "byte");
  }
  add(mv.faultGa, "bit");
  add(mv.filterGa, "bit");
  add(mv.filterDaysGa, "uint16");
  for (const logic of mvLogics(mv)) {
    add(logic.triggerGa, "bit");
    add(logic.orGa, "bit");
    add(logic.untilGa, "bit");
    for (const c of logic.when ?? []) add(c.ga, "bit");
    for (const c of logic.untilWhen ?? []) add(c.ga, "bit");
    if (logic.triggerMode === "tempRise" && logic.tempRise) {
      add(logic.tempRise.ga, "temperature");
    }
  }
  return out;
}
