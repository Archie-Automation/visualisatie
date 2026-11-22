/**
 * Rookmelders en andere KNX-meldingen.
 * De eerste waarde van een punt wordt alleen onthouden. Een notificatie gaat
 * eruit als dat punt daarna van uit naar aan gaat, ook als de app dicht is.
 */
import { getConfig } from "./config";
import type { KnxBus } from "./knxBus";
import { logger } from "./logger";
import { pushMelding, pushMeldingClear } from "./push";
import { isStaffRole } from "./roles";
import type { Device, MeldingItem } from "./types";
import { houseFunctionAllowed } from "./userAccess";

interface Point {
  key: string;
  on: boolean;
  deviceId: string;
  itemId: string;
  title: string;
  body: string;
}

const known = new Map<string, boolean>();

function notifies(item: MeldingItem): boolean {
  if (typeof item.notify === "boolean") return item.notify;
  return item.urgency === "urgent";
}

function itemActive(item: MeldingItem, busVal: unknown): boolean {
  if (busVal == null) return false;
  const dpt = item.dpt || "1.001";
  if (dpt.startsWith("1.")) {
    const target = item.activeValue ?? 1;
    const wantOn = target === 1 || target === true;
    if (typeof busVal === "boolean") return busVal === wantOn;
    const n = Number(busVal);
    const t = item.activeValue == null ? 1 : Number(item.activeValue);
    return Number.isFinite(n) && Number.isFinite(t) && n === t;
  }
  const n = typeof busVal === "number" ? busVal : Number(busVal);
  if (!Number.isFinite(n)) return false;
  if (item.activeValue == null) return n !== 0;
  const t = Number(item.activeValue);
  if (!Number.isFinite(t)) return n !== 0;
  switch (item.activeCompare ?? "eq") {
    case "gt":
      return n > t;
    case "lt":
      return n < t;
    case "gte":
      return n >= t;
    case "lte":
      return n <= t;
    default:
      return n === t;
  }
}

function eachDevice(visit: (d: Device) => void): void {
  const cfg = getConfig();
  for (const d of cfg.devices ?? []) visit(d);
  for (const floor of cfg.floors) {
    for (const room of floor.rooms) {
      for (const d of room.devices) visit(d);
    }
  }
}

function picture(bus: KnxBus): Map<string, Point> {
  const out = new Map<string, Point>();
  eachDevice((d) => {
    if (d.type !== "melding") return;
    for (const item of d.melding?.items ?? []) {
      if (!notifies(item)) continue;
      const ga = (item.ga || "").trim();
      if (!ga) continue;
      const itemId = (item.id || ga).trim();
      const key = `${d.id}::${itemId}`;
      const title = (item.label || "").trim() || "Melding";
      const detail = (item.activeLabel || "").trim();
      out.set(key, {
        key,
        on: itemActive(item, bus.getState(ga)?.value),
        deviceId: d.id,
        itemId,
        title,
        body: detail || d.name || "Melding actief"
      });
    }
  });
  return out;
}

function recipients(): Set<string> {
  const ids = new Set<string>();
  for (const u of getConfig().users ?? []) {
    if (u.enabled === false) continue;
    if (isStaffRole(u.role) || houseFunctionAllowed(u.access, "meldingen")) {
      ids.add(u.id);
    }
  }
  return ids;
}

function onBus(bus: KnxBus): void {
  const now = picture(bus);
  const users = recipients();
  for (const [k, point] of now) {
    const prev = known.get(k);
    known.set(k, point.on);
    if (prev === undefined || prev === point.on) continue;
    if (point.on) {
      logger.info(
        { deviceId: point.deviceId, itemId: point.itemId, title: point.title },
        "melding actief"
      );
      if (users.size > 0) {
        pushMelding({
          deviceId: point.deviceId,
          itemId: point.itemId,
          title: point.title,
          body: point.body,
          userIds: users
        });
      }
    } else if (users.size > 0) {
      pushMeldingClear(point.deviceId, point.itemId, users);
    }
  }
  for (const k of [...known.keys()]) {
    if (now.has(k)) continue;
    const wasOn = known.get(k) === true;
    known.delete(k);
    const split = k.indexOf("::");
    if (!wasOn || split < 0 || users.size === 0) continue;
    pushMeldingClear(k.slice(0, split), k.slice(split + 2), users);
  }
}

export function attachMeldingNotify(bus: KnxBus): void {
  bus.on("stateChanged", () => onBus(bus));
}
