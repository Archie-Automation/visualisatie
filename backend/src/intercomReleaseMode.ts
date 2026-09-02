import type { IntercomDevice } from "./types";

/** Hoe de app de deur ontgrendelt (KNX-puls, DoorBird, of generieke HTTP). */
export function effectiveIntercomReleaseMode(
  d: IntercomDevice
): "knx" | "doorbird" | "http" {
  if (d.intercom.releaseMode === "http") return "http";
  if (d.intercom.releaseMode === "doorbird") return "doorbird";
  if (d.intercom.releaseMode === "knx") return "knx";
  if (d.intercom.httpRelease?.url?.trim()) return "http";
  if (d.intercom.release?.ga) return "knx";
  const db = d.intercom.doorbird;
  if (db?.host?.trim() && db.username?.trim()) return "doorbird";
  return "knx";
}

export function intercomSupportsRelease(ic: IntercomDevice): boolean {
  const mode = effectiveIntercomReleaseMode(ic);
  if (mode === "knx") return !!ic.intercom.release?.ga;
  if (mode === "http") return !!ic.intercom.httpRelease?.url?.trim();
  const db = ic.intercom.doorbird;
  return !!(
    db?.host?.trim() &&
    db.username?.trim() &&
    db.password != null &&
    String(db.password).length > 0
  );
}
