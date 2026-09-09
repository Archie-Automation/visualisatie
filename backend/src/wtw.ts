import type {
  WtwZehnderComfoConnect,
  WtwZehnderLogic,
  WtwZehnderStandId
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
