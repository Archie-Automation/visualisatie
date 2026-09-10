import { getConfig, walkDevices } from "./config";
import type { KnxBus } from "./knxBus";
import { fireplaceVirtual } from "./fireplaceVirtual";
import type { FireplaceConfig, GA, HouseConfig } from "./types";

/** Planika: app schrijft alleen 1; de actor maakt de puls zelf. */
export function fireplaceIsPlanika(fp: FireplaceConfig): boolean {
  if (fp.protocol === "planika") return true;
  return fp.controlMode === "discrete" && fp.statusBits != null;
}

function gaIsPlanikaCommand(ga: GA, cfg?: HouseConfig): boolean {
  let house: HouseConfig;
  try {
    house = cfg ?? getConfig();
  } catch {
    return false;
  }
  let hit = false;
  walkDevices(house, (d) => {
    if (d.type !== "fireplace") return;
    if (!fireplaceIsPlanika(d.fireplace)) return;
    const dl = d.fireplace.discreteLevel;
    if (!dl) return;
    for (const k of ["on", "off", "up", "down"] as const) {
      if (dl[k]?.ga === ga) hit = true;
    }
  });
  return hit;
}

/** DPT1 pulse: true, pause, false — behalve Planika (alleen true). */
export async function pulseKnxGa(
  bus: KnxBus,
  ga: GA,
  pulseMs?: number
): Promise<void> {
  if (gaIsPlanikaCommand(ga)) {
    await bus.write(ga, "switch", true);
    return;
  }
  const ms = Math.min(3000, Math.max(50, pulseMs ?? 250));
  await bus.write(ga, "switch", true);
  await new Promise<void>((r) => setTimeout(r, ms));
  await bus.write(ga, "switch", false);
}

/** Houd virtuele aan/uit-status gelijk met discrete puls-contacten. */
export function syncFireplaceVirtualForDiscreteGa(
  ga: GA,
  cfg: HouseConfig = getConfig()
): void {
  walkDevices(cfg, (d) => {
    if (d.type !== "fireplace") return;
    if (d.fireplace.controlMode !== "discrete") return;
    const dl = d.fireplace.discreteLevel;
    if (!dl) return;
    if (dl.on?.ga === ga) fireplaceVirtual.set(d.id, true);
    if (dl.off?.ga === ga) fireplaceVirtual.set(d.id, false);
  });
}
