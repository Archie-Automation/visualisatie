/**
 * Alarm op KNX-sensoren. Naast Satel: aanwezig of afwezig, code, overbruggen,
 * sirene, inloop en uitloop. De code staat alleen als hash in house.json.
 */
import bcrypt from "bcryptjs";
import { getConfig, getConfigVersion } from "./config";
import type { KnxBus } from "./knxBus";
import { logger } from "./logger";
import type { GA, KnxAlarmSensor } from "./types";

export type KnxAlarmPhase = "off" | "exit" | "armed" | "entry" | "alarm";
export type KnxAlarmMode = "aanwezig" | "afwezig";

export type KnxAlarmSensorState = {
  id: string;
  name: string;
  ga: string;
  kind?: string;
  aanwezig: boolean;
  afwezig: boolean;
  inloop: boolean;
  open: boolean;
  bypassed: boolean;
};

export type KnxAlarmPublic = {
  enabled: boolean;
  pinSet: boolean;
  phase: KnxAlarmPhase;
  mode: KnxAlarmMode | null;
  deadlineMs: number | null;
  siren: boolean;
  exitSeconds: number;
  entrySeconds: number;
  sensors: KnxAlarmSensorState[];
};

type Listener = (status: KnxAlarmPublic) => void;

const listeners = new Set<Listener>();
const bypassed = new Set<string>();
const openById = new Map<string, boolean>();

let busRef: KnxBus | null = null;
let phase: KnxAlarmPhase = "off";
let mode: KnxAlarmMode | null = null;
let deadlineMs: number | null = null;
let sirenOn = false;
let seenVersion = -1;
let configChanged = false;
let fails = 0;
let lockedUntil = 0;
let started = false;

export function onKnxAlarm(cb: Listener): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function knxAlarmStatus(): KnxAlarmPublic {
  ensureFresh();
  return snapshot();
}

export function attachKnxAlarm(bus: KnxBus): void {
  if (started) return;
  started = true;
  busRef = bus;
  bus.on("stateChanged", (state: { ga?: string; value?: unknown }) => {
    if (!state.ga) return;
    onGa(state.ga, state.value);
  });
  setInterval(() => tick(), 250);
  tick();
  void silenceSirenOnBoot();
}

export type KnxAlarmResult =
  | { ok: true; status: KnxAlarmPublic }
  | { ok: false; statusCode: number; error: string; message: string };

export async function knxAlarmArm(
  nextMode: KnxAlarmMode,
  pin: string
): Promise<KnxAlarmResult> {
  ensureFresh();
  const cfg = readCfg();
  if (!cfg.enabled) return fail(409, "disabled", "KNX-alarm staat uit.");
  const pinErr = await checkPin(pin);
  if (pinErr) return pinErr;
  if (phase !== "off") {
    return fail(409, "busy", "Het alarm staat al aan. Schakel het eerst uit.");
  }
  const blocking = [
    ...sensorsFor(nextMode).filter(
      (s) => s.open && !s.bypassed && !s.inloop && s.kind !== "sabotage"
    ),
    ...openSabotage()
  ];
  if (blocking.length > 0) {
    const names = blocking.map((s) => s.name).join(", ");
    return fail(409, "zone_open", `Nog open: ${names}. Overbruggen of sluiten.`);
  }
  mode = nextMode;
  const exitSec = clampSeconds(cfg.exitSeconds, 30);
  if (exitSec <= 0) {
    becomeArmed();
  } else {
    phase = "exit";
    deadlineMs = Date.now() + exitSec * 1000;
  }
  emit();
  return { ok: true, status: snapshot() };
}

export async function knxAlarmDisarm(pin: string): Promise<KnxAlarmResult> {
  ensureFresh();
  const cfg = readCfg();
  if (!cfg.enabled) return fail(409, "disabled", "KNX-alarm staat uit.");
  const pinErr = await checkPin(pin);
  if (pinErr) return pinErr;
  phase = "off";
  mode = null;
  deadlineMs = null;
  bypassed.clear();
  sabotageHoldingSiren = false;
  await setSiren(false);
  emit();
  return { ok: true, status: snapshot() };
}

export async function knxAlarmBypass(
  id: string,
  bypass: boolean,
  pin: string
): Promise<KnxAlarmResult> {
  ensureFresh();
  const cfg = readCfg();
  if (!cfg.enabled) return fail(409, "disabled", "KNX-alarm staat uit.");
  const sensor = (cfg.sensors ?? []).find((s) => s.id === id);
  if (!sensor) return fail(404, "unknown_sensor", "Die sensor bestaat niet.");
  if (phase !== "off") {
    const pinErr = await checkPin(pin);
    if (pinErr) return pinErr;
  }
  if (bypass) bypassed.add(id);
  else bypassed.delete(id);
  if (phase === "armed" || phase === "entry") reactToOpenSensors();
  void syncSabotageSiren();
  emit();
  return { ok: true, status: snapshot() };
}

function fail(
  statusCode: number,
  error: string,
  message: string
): KnxAlarmResult {
  return { ok: false, statusCode, error, message };
}

function alarmPinHashes(): string[] {
  const cfg = getConfig();
  const hashes: string[] = [];
  const house = cfg.knxAlarm?.pinHash?.trim();
  if (house) hashes.push(house);
  for (const user of cfg.users ?? []) {
    if (user.enabled === false) continue;
    const pin = user.alarmPinHash?.trim();
    if (pin) hashes.push(pin);
  }
  return hashes;
}

async function checkPin(pin: string): Promise<KnxAlarmResult | null> {
  if (Date.now() < lockedUntil) {
    return fail(429, "locked", "Te vaak een verkeerde code. Wacht een minuut.");
  }
  const hashes = alarmPinHashes();
  if (hashes.length === 0) {
    return fail(409, "no_pin", "Er is nog geen alarmcode ingesteld.");
  }
  const typed = pin.trim();
  let ok = false;
  for (const hash of hashes) {
    if (await bcrypt.compare(typed, hash).catch(() => false)) {
      ok = true;
      break;
    }
  }
  if (!ok) {
    fails += 1;
    if (fails >= 8) {
      fails = 0;
      lockedUntil = Date.now() + 60_000;
    }
    return fail(401, "bad_pin", "Code onjuist.");
  }
  fails = 0;
  return null;
}

function readCfg(): {
  enabled: boolean;
  pinHash?: string;
  exitSeconds?: number;
  entrySeconds?: number;
  sirenGa?: GA;
  sensors: KnxAlarmSensor[];
} {
  const raw = getConfig().knxAlarm;
  return {
    enabled: raw?.enabled === true,
    pinHash: raw?.pinHash,
    exitSeconds: raw?.exitSeconds,
    entrySeconds: raw?.entrySeconds,
    sirenGa: raw?.sirenGa,
    sensors: raw?.sensors ?? []
  };
}

function clampSeconds(value: number | undefined, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(0, Math.min(600, Math.round(value)));
}

function ensureFresh(): void {
  const version = getConfigVersion();
  if (version === seenVersion) return;
  seenVersion = version;
  configChanged = true;
  const cfg = readCfg();
  const ids = new Set((cfg.sensors ?? []).map((s) => s.id));
  for (const id of [...bypassed]) {
    if (!ids.has(id)) bypassed.delete(id);
  }
  for (const id of [...openById.keys()]) {
    if (!ids.has(id)) openById.delete(id);
  }
  for (const sensor of cfg.sensors ?? []) {
    const cached =
      busRef?.getState(sensor.ga)?.value ??
      busRef?.getState(sensor.ga.trim())?.value;
    if (cached !== undefined) openById.set(sensor.id, isOpen(sensor, cached));
  }
  if (!cfg.enabled && phase !== "off") {
    phase = "off";
    mode = null;
    deadlineMs = null;
    void setSiren(false);
  }
}

function snapshot(): KnxAlarmPublic {
  const cfg = readCfg();
  return {
    enabled: cfg.enabled,
    pinSet: Boolean(cfg.pinHash),
    phase: cfg.enabled ? phase : "off",
    mode: cfg.enabled ? mode : null,
    deadlineMs: cfg.enabled ? deadlineMs : null,
    siren: cfg.enabled && sirenOn,
    exitSeconds: clampSeconds(cfg.exitSeconds, 30),
    entrySeconds: clampSeconds(cfg.entrySeconds, 30),
    sensors: (cfg.sensors ?? []).map((s) => ({
      id: s.id,
      name: s.name || s.ga,
      ga: s.ga,
      kind: s.kind,
      aanwezig: s.aanwezig === true,
      afwezig: s.afwezig === true,
      inloop: s.inloop === true,
      open: openById.get(s.id) === true,
      bypassed: bypassed.has(s.id)
    }))
  };
}

function emit(): void {
  const status = snapshot();
  for (const cb of listeners) {
    try {
      cb(status);
    } catch (err) {
      logger.warn({ err }, "KNX-alarm luisteraar mislukt");
    }
  }
}

function tick(): void {
  configChanged = false;
  const before = `${phase}|${deadlineMs}|${sirenOn}`;
  ensureFresh();
  if ((phase === "exit" || phase === "entry") && deadlineMs != null && Date.now() >= deadlineMs) {
    if (phase === "exit") becomeArmed();
    else triggerAlarm();
  }
  void syncSabotageSiren();
  const after = `${phase}|${deadlineMs}|${sirenOn}`;
  if (configChanged || before !== after) emit();
}

function onGa(ga: string, value: unknown): void {
  ensureFresh();
  const cfg = readCfg();
  let changed = false;
  for (const sensor of cfg.sensors ?? []) {
    if (!sameGa(sensor.ga, ga)) continue;
    const open = isOpen(sensor, value);
    if (openById.get(sensor.id) === open) continue;
    openById.set(sensor.id, open);
    changed = true;
  }
  if (!changed || !cfg.enabled) return;
  for (const sensor of cfg.sensors ?? []) {
    if (sensor.kind !== "sabotage") continue;
    if (openById.get(sensor.id) !== true) bypassed.delete(sensor.id);
  }
  if (phase === "armed" || phase === "entry") reactToOpenSensors();
  void syncSabotageSiren();
  emit();
}

function isOn(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) && value !== 0;
  if (typeof value === "string") {
    const s = value.trim().toLowerCase();
    if (s === "1" || s === "true" || s === "on" || s === "aan") return true;
    return false;
  }
  return false;
}

function sameGa(a: string, b: string): boolean {
  return a.trim().replace(/\s+/g, "") === b.trim().replace(/\s+/g, "");
}

function isOpen(sensor: KnxAlarmSensor, value: unknown): boolean {
  const on = isOn(value);
  return sensor.alarmOn === "0" ? !on : on;
}

function openSabotage(): KnxAlarmSensorState[] {
  return snapshot().sensors.filter(
    (s) => s.kind === "sabotage" && s.open && !s.bypassed
  );
}

let sabotageHoldingSiren = false;

/** Sirene alleen als het alarm aan staat én een sabotagecontact open is. */
async function syncSabotageSiren(): Promise<void> {
  if (!readCfg().enabled || phase === "alarm") {
    sabotageHoldingSiren = false;
    return;
  }
  const want = phase !== "off" && openSabotage().length > 0;
  if (want) {
    sabotageHoldingSiren = true;
    await setSiren(true);
    return;
  }
  if (!sabotageHoldingSiren) return;
  sabotageHoldingSiren = false;
  await setSiren(false);
}

function sensorsFor(which: KnxAlarmMode): KnxAlarmSensorState[] {
  return snapshot().sensors.filter((s) =>
    which === "aanwezig" ? s.aanwezig : s.afwezig
  );
}

function becomeArmed(): void {
  phase = "armed";
  deadlineMs = null;
  reactToOpenSensors();
  void syncSabotageSiren();
}

function reactToOpenSensors(): void {
  if (!mode || (phase !== "armed" && phase !== "entry")) return;
  const active = sensorsFor(mode).filter(
    (s) => s.open && !s.bypassed && s.kind !== "sabotage"
  );
  if (active.some((s) => !s.inloop)) {
    triggerAlarm();
    return;
  }
  // Dichtgaan stopt de inloop niet. Satel telt door tot de code of de sirene.
  if (phase === "armed" && active.some((s) => s.inloop)) startEntry();
}

function startEntry(): void {
  const sec = clampSeconds(readCfg().entrySeconds, 30);
  if (sec <= 0) {
    triggerAlarm();
    return;
  }
  phase = "entry";
  deadlineMs = Date.now() + sec * 1000;
}

function triggerAlarm(): void {
  phase = "alarm";
  deadlineMs = null;
  sabotageHoldingSiren = false;
  void setSiren(true);
}

async function setSiren(on: boolean): Promise<void> {
  if (sirenOn === on) return;
  sirenOn = on;
  const ga = readCfg().sirenGa;
  if (!ga || !busRef) return;
  try {
    await busRef.write(ga, "switch", on);
  } catch (err) {
    logger.warn({ err, ga, on }, "Sirene schrijven mislukt");
  }
}

async function silenceSirenOnBoot(): Promise<void> {
  const ga = readCfg().sirenGa;
  if (!ga || !busRef) return;
  try {
    await busRef.write(ga, "switch", false);
  } catch {
    /* bus nog niet klaar; een latere uitschakeling schrijft alsnog */
  }
}
