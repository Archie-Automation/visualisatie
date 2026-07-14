import { getConfig, walkDevices } from "./config";
import type { KnxBus } from "./knxBus";
import { fireplaceVirtual } from "./fireplaceVirtual";
import type { GA, HouseConfig } from "./types";

/** DPT1 pulse: true, pause, false (many haard-actoren verwachten een korte puls). */
export async function pulseKnxGa(
  bus: KnxBus,
  ga: GA,
  pulseMs?: number
): Promise<void> {
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
