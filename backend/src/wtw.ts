import type { WtwZehnderComfoConnect, WtwZehnderStandId } from "./types";

export const ZEHN_STANDS: ReadonlyArray<{
  id: WtwZehnderStandId;
  ga: keyof WtwZehnderComfoConnect;
  status: keyof WtwZehnderComfoConnect;
}> = [
  { id: "away", ga: "awayGa", status: "awayStatusGa" },
  { id: "stand1", ga: "stand1Ga", status: "stand1StatusGa" },
  { id: "stand2", ga: "stand2Ga", status: "stand2StatusGa" },
  { id: "stand3", ga: "stand3Ga", status: "stand3StatusGa" },
  { id: "auto", ga: "autoGa", status: "autoStatusGa" },
  { id: "boost", ga: "boostGa", status: "boostStatusGa" }
];

function asGa(v: unknown): string | undefined {
  const s = typeof v === "string" ? v.trim() : "";
  return s || undefined;
}

export function zehnderWriteGa(
  z: WtwZehnderComfoConnect,
  id: string
): string | undefined {
  const row = ZEHN_STANDS.find((s) => s.id === id);
  return row ? asGa(z[row.ga]) : undefined;
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
