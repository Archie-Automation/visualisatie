import type { WtwZehnderComfoConnect, WtwZehnderStandId } from "./types";
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

/** ComfoConnect moet Auto uit hebben voordat een handmatige stand pakt. */
const AUTO_OFF_SETTLE_MS = 150;

function asGa(v: unknown): string | undefined {
  const s = typeof v === "string" ? v.trim() : "";
  return s || undefined;
}

function bitOn(value: unknown): boolean {
  return value === true || value === 1 || value === "1";
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** `undefined` = geen status (nog) bekend — behandel als mogelijk aan. */
function autoIsOff(bus: KnxBus, z: WtwZehnderComfoConnect): boolean {
  const ga = asGa(z.autoStatusGa);
  if (!ga) return false;
  const st = bus.getState(ga);
  if (!st) return false;
  return !bitOn(st.value);
}

export function zehnderWriteGa(
  z: WtwZehnderComfoConnect,
  id: string
): string | undefined {
  const row = ZEHN_STANDS.find((s) => s.id === id);
  return row ? asGa(z[row.ga]) : undefined;
}

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

  const autoGa = asGa(z.autoGa);
  if (autoGa && !autoIsOff(bus, z)) {
    await bus.write(autoGa, "bit", false);
    await delay(AUTO_OFF_SETTLE_MS);
  }

  if (cmd.buttonId === "boost" && cmd.on !== false && z.boostTimeGa) {
    const minutes = cmd.minutes ?? z.minutes ?? 30;
    await bus.write(
      z.boostTimeGa,
      "uint16",
      Math.min(65535, Math.max(1, minutes * 60))
    );
  }
  await bus.write(ga, "bit", cmd.on === false ? false : true);
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
  return out;
}
