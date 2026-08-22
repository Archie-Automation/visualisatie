import type { Device, HouseConfig, User } from "./types";
import { isInstallerRole, isStaffRole, normalizeRole } from "./roles";

export const HOUSE_FUNCTION_SLUGS = [
  "verlichting",
  "klimaat",
  "zonwering",
  "ventilatie",
  "openhaard",
  "cameras",
  "intercom",
  "audio",
  "meldingen",
  "diverse",
  "alarm"
] as const;

export type HouseFunctionSlug = (typeof HOUSE_FUNCTION_SLUGS)[number];

export function functionSlugForDeviceType(type: string): HouseFunctionSlug {
  switch (type) {
    case "light_switch":
    case "light_dimmer":
    case "rgbw_ww":
    case "lutron_homeworks":
      return "verlichting";
    case "climate":
    case "ac":
      return "klimaat";
    case "shading":
      return "zonwering";
    case "fan":
    case "wtw":
      return "ventilatie";
    case "fireplace":
      return "openhaard";
    case "camera":
      return "cameras";
    case "intercom":
      return "intercom";
    case "media_sonos":
    case "media_bluesound":
      return "audio";
    case "melding":
      return "meldingen";
    default:
      return "diverse";
  }
}

export function aclAllows(
  list: "*" | string[] | undefined,
  id: string
): boolean {
  if (list === undefined || list === "*") return true;
  return list.includes(id);
}

function functionsForRoom(
  access: NonNullable<User["access"]>,
  roomId: string | null
): "*" | string[] {
  if (roomId) {
    const rf = access.roomFunctions?.[roomId];
    if (rf !== undefined) return rf;
  }
  return access.functions ?? "*";
}

export function functionAllowed(
  access: NonNullable<User["access"]> | undefined,
  roomId: string | null,
  deviceType: string
): boolean {
  if (!access) return true;
  const fns = functionsForRoom(access, roomId);
  if (fns === "*") return true;
  return fns.includes(functionSlugForDeviceType(deviceType));
}

export function houseFunctionAllowed(
  access: NonNullable<User["access"]> | undefined,
  slug: string
): boolean {
  if (!access) return true;
  const fns = access.functions;
  if (fns === undefined || fns === "*") return true;
  return fns.includes(slug);
}

type DevicePlace = {
  device: Device;
  floorId: string;
  roomId: string;
};

function locateDevice(cfg: HouseConfig, deviceId: string): DevicePlace | null {
  for (const floor of cfg.floors) {
    for (const room of floor.rooms) {
      const device = room.devices.find((d) => d.id === deviceId);
      if (device) return { device, floorId: floor.id, roomId: room.id };
    }
  }
  const global = (cfg.devices ?? []).find((d) => d.id === deviceId);
  if (global) return { device: global, floorId: "", roomId: "" };
  const cam = (cfg.cameras ?? []).find((d) => d.id === deviceId);
  if (cam) return { device: cam, floorId: "", roomId: "" };
  const ic = (cfg.intercoms ?? []).find((d) => d.id === deviceId);
  if (ic) return { device: ic, floorId: "", roomId: "" };
  return null;
}

/** Staff bypass ACL. Regular users need floor/room/function grants. */
export function userMayUseDevice(
  user: User | undefined,
  role: string | undefined,
  cfg: HouseConfig,
  deviceId: string
): boolean {
  if (isStaffRole(role) || isStaffRole(user?.role)) return true;
  const hit = locateDevice(cfg, deviceId);
  if (!hit) return false;
  const access = user?.access;
  if (!access) return true;
  if (hit.floorId && !aclAllows(access.floors, hit.floorId)) return false;
  if (hit.roomId && !aclAllows(access.rooms, hit.roomId)) return false;
  return functionAllowed(access, hit.roomId || null, hit.device.type);
}

export function filterConfigForUser(cfg: HouseConfig, user: User): HouseConfig {
  const access = user.access;
  if (!access) return cfg;

  const filterDevices = (
    devices: Device[],
    roomId: string | null
  ): Device[] =>
    devices.filter((d) => functionAllowed(access, roomId, d.type));

  const floors = cfg.floors
    .filter((f) => aclAllows(access.floors, f.id))
    .map((f) => {
      const rooms = f.rooms
        .filter((r) => aclAllows(access.rooms, r.id))
        .map((r) => {
          const devices = filterDevices(r.devices, r.id);
          const fullyGranted =
            functionsForRoom(access, r.id) === "*";
          if (!fullyGranted && devices.length === 0) return null;
          return { ...r, devices };
        })
        .filter((r): r is NonNullable<typeof r> => r != null);
      if (rooms.length === 0 && access.floors !== "*" && access.floors) {
        return { ...f, rooms };
      }
      if (rooms.length === 0 && access.functions && access.functions !== "*") {
        return null;
      }
      return { ...f, rooms };
    })
    .filter((f): f is NonNullable<typeof f> => f != null);

  const cameras = houseFunctionAllowed(access, "cameras")
    ? cfg.cameras
    : [];
  const intercoms = houseFunctionAllowed(access, "intercom")
    ? cfg.intercoms
    : [];
  const devices = filterDevices(cfg.devices ?? [], null);

  let satel = cfg.satel;
  if (satel && !houseFunctionAllowed(access, "alarm")) {
    satel = { ...satel, enabled: false };
  }

  return {
    ...cfg,
    floors,
    devices,
    cameras,
    intercoms,
    satel
  };
}

export function canonicalizeStoredUser(u: User): User {
  return {
    ...u,
    role: normalizeRole(u.role),
    enabled: u.enabled !== false
  };
}

/**
 * Super user may create/edit user + superuser, and may only toggle
 * `enabled` on installer accounts. Installer may edit everyone.
 */
export function assertUsersMutation(
  actor: User,
  previous: User[],
  next: User[]
): string | null {
  const actorRole = normalizeRole(actor.role);
  if (actorRole === "user") return "geen toegang tot gebruikersbeheer";

  const prevById = new Map(previous.map((u) => [u.id, u]));
  const nextIds = new Set(next.map((u) => u.id));

  if (!nextIds.has(actor.id)) {
    return "je kunt je eigen account niet verwijderen";
  }

  const names = next.map((u) => u.username.trim().toLowerCase());
  if (new Set(names).size !== names.length) {
    return "gebruikersnaam moet uniek zijn";
  }

  if (actorRole === "installer") return null;

  // Super user constraints.
  for (const n of next) {
    const role = normalizeRole(n.role);
    const prev = prevById.get(n.id);
    if (!prev) {
      if (role === "installer") {
        return "super user mag geen installer-account aanmaken";
      }
      continue;
    }
    if (isInstallerRole(prev.role) || isInstallerRole(n.role)) {
      if (!isInstallerRole(prev.role) || normalizeRole(n.role) !== "installer") {
        return "super user mag niemand tot installer promoveren";
      }
      n.username = prev.username;
      n.role = "installer";
      n.passwordHash = prev.passwordHash;
      n.access = prev.access;
    }
  }

  for (const p of previous) {
    if (isInstallerRole(p.role) && !nextIds.has(p.id)) {
      return "super user mag een installer niet verwijderen — blokkeer het account";
    }
  }

  return null;
}
