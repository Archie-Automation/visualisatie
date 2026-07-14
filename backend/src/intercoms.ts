import { collectIntercoms } from "./cameras";
import { releaseDoorViaDoorbird } from "./doorbirdRelease";
import { effectiveIntercomReleaseMode } from "./intercomReleaseMode";
import { logger } from "./logger";
import type { HouseConfig, IntercomDevice } from "./types";
import type { KnxBus } from "./knxBus";

/** KNX-puls op deur-open-GA, of DoorBird LAN `open-door.cgi`. */
export async function releaseDoor(
  ic: IntercomDevice,
  bus: KnxBus
): Promise<void> {
  if (effectiveIntercomReleaseMode(ic) === "doorbird") {
    await releaseDoorViaDoorbird(ic);
    return;
  }

  const release = ic.intercom.release;
  if (!release?.ga) throw new Error("intercom has no release GA (releaseMode knx)");
  const pulseMs = release.pulseMs ?? 1500;

  logger.info(
    { id: ic.id, ga: release.ga, pulseMs },
    "intercom door release (KNX)"
  );

  await bus.write(release.ga, "switch", true);
  await new Promise((r) => setTimeout(r, pulseMs));
  await bus.write(release.ga, "switch", false);
}

/**
 * Build a fast lookup from doorbell-GA → intercom, used by the bus listener
 * to translate incoming 1-bit telegrams into high-level ring events.
 */
export function buildDoorbellIndex(
  cfg: HouseConfig
): Map<string, IntercomDevice> {
  const out = new Map<string, IntercomDevice>();
  for (const d of collectIntercoms(cfg)) {
    const ga = d.intercom.doorbell?.ga;
    if (ga) out.set(ga, d);
  }
  return out;
}
