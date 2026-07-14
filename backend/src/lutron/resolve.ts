import type {
  Device,
  HouseConfig,
  LightDimmerDevice,
  LightSwitchDevice,
  LutronLoadOutputBinding,
  ShadingDevice
} from "../types";

/** Slot-id van de centrale Lutron-telnet in house.json (`lutron`). */
export const HOUSE_LUTRON_SLOT_ID = "house";

export function inferLutronLoadType(
  device: LightSwitchDevice | LightDimmerDevice | ShadingDevice
): LutronLoadOutputBinding["loadType"] {
  if (device.type === "shading") return "shade";
  if (device.type === "light_dimmer") return "dimmer";
  return "switch";
}

export function resolveLutronLoadOutput(
  device: Device
): LutronLoadOutputBinding | undefined {
  if (
    device.type !== "light_switch" &&
    device.type !== "light_dimmer" &&
    device.type !== "shading"
  ) {
    return undefined;
  }
  if (device.control !== "lutron") return undefined;

  const legacy = device.lutronOutput;
  const fromField = device.lutronIntegrationId;
  const integrationId =
    fromField != null && Number.isFinite(Number(fromField))
      ? Math.round(Number(fromField))
      : legacy?.integrationId != null
        ? Math.round(Number(legacy.integrationId))
        : undefined;

  if (integrationId == null || integrationId < 1) return undefined;

  const loadType = legacy?.loadType ?? inferLutronLoadType(device);
  return {
    integrationId,
    loadType,
    fadeSeconds: legacy?.fadeSeconds,
    homeworksDeviceId: legacy?.homeworksDeviceId
  };
}

export function houseLutronTelnetHost(cfg: HouseConfig): string {
  const hl = cfg.lutron;
  if (!hl) return "";
  return (hl.telnet?.host ?? hl.bridgeHost ?? "").trim();
}

export function houseLutronEnabled(cfg: HouseConfig): boolean {
  const hl = cfg.lutron;
  if (!hl?.telnet?.enabled) return false;
  return houseLutronTelnetHost(cfg).length > 0;
}
