import type { IntercomDevice } from "./types";

/** Hoe de app de deur ontgrendelt (KNX-puls of DoorBird LAN-API). */
export function effectiveIntercomReleaseMode(d: IntercomDevice): "knx" | "doorbird" {
  if (d.intercom.releaseMode === "doorbird") return "doorbird";
  if (d.intercom.releaseMode === "knx") return "knx";
  if (d.intercom.release?.ga) return "knx";
  const db = d.intercom.doorbird;
  if (db?.host?.trim() && db.username?.trim()) return "doorbird";
  return "knx";
}

export function intercomSupportsRelease(ic: IntercomDevice): boolean {
  if (effectiveIntercomReleaseMode(ic) === "knx") {
    return !!ic.intercom.release?.ga;
  }
  const db = ic.intercom.doorbird;
  return !!(
    db?.host?.trim() &&
    db.username?.trim() &&
    db.password != null &&
    String(db.password).length > 0
  );
}
