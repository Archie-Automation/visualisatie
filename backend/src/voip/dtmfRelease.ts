import type { IntercomDevice } from "../types";
import { logger } from "../logger";
import { intercomDtmfDigit } from "../intercomReleaseMode";
import type { AmiClient } from "./ami";

const doorChannelByIntercom = new Map<string, string>();

let getAmi: () => AmiClient | null = () => null;

export function setDtmfAmiGetter(fn: () => AmiClient | null): void {
  getAmi = fn;
}

export function recordDoorChannel(intercomId: string, channel: string): void {
  const ch = channel.trim();
  if (!intercomId || !ch) return;
  doorChannelByIntercom.set(intercomId, ch);
}

export function clearDoorChannel(intercomId: string, channel?: string): void {
  if (!intercomId) return;
  if (channel && doorChannelByIntercom.get(intercomId) !== channel) return;
  doorChannelByIntercom.delete(intercomId);
}

export function doorChannelFor(intercomId: string): string | undefined {
  return doorChannelByIntercom.get(intercomId);
}

/** DTMF naar het deurstation in een lopend SIP-gesprek (AMI PlayDTMF). */
export async function releaseDoorViaDtmf(ic: IntercomDevice): Promise<void> {
  const ami = getAmi();
  if (!ami?.connected) {
    throw new Error("PBX niet verbonden — DTMF-deuropen kan niet.");
  }
  const channel = doorChannelByIntercom.get(ic.id);
  if (!channel) {
    throw new Error(
      "Geen actief gesprek. Neem eerst op, of stel KNX / DoorBird-HTTP in."
    );
  }
  const digit = intercomDtmfDigit(ic);
  const evs = await ami.send({
    Action: "PlayDTMF",
    Channel: channel,
    Digit: digit,
    Duration: "300"
  });
  const ok = evs[0]?.Response === "Success";
  if (!ok) {
    throw new Error(evs[0]?.Message || "DTMF naar deurstation mislukt");
  }
  logger.info({ id: ic.id, digit }, "intercom door release (DTMF)");
}
