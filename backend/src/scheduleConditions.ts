import type { KnxBus } from "./knxBus";
import { findDevice } from "./config";
import type {
  Device,
  HouseConfig,
  Schedule,
  ScheduleCondition,
  SceneAction
} from "./types";

/** True when every condition matches current bus status. Missing status fails. */
export function scheduleConditionsMet(
  s: Schedule,
  bus: KnxBus,
  cfg: HouseConfig
): boolean {
  const items = s.conditions ?? [];
  if (items.length === 0) return true;
  for (const c of items) {
    if (!conditionMet(c, bus, cfg)) return false;
  }
  return true;
}

function conditionMet(
  c: ScheduleCondition,
  bus: KnxBus,
  cfg: HouseConfig
): boolean {
  const device = findDevice(cfg, c.deviceId);
  if (!device) return false;
  if (c.kind === "logic") return logicMet(device, c.buttonId, c.equals, bus);
  for (const action of c.actions) {
    const ga = statusGaFor(device, action.ga);
    const st = bus.getState(ga);
    if (!st || !valuesMatch(st.value, action.value, action.role)) return false;
  }
  return c.actions.length > 0;
}

function logicMet(
  device: Device,
  buttonId: string,
  equals: boolean,
  bus: KnxBus
): boolean {
  if (device.type !== "universal") return false;
  const btn = device.universal.buttons.find((b) => b.id === buttonId);
  if (!btn) return false;
  const ga = btn.statusGa ?? btn.action.ga;
  const st = bus.getState(ga);
  if (!st) return false;
  const onVal = btn.statusOnValue ?? true;
  const isOn = valuesMatch(st.value, onVal, "bit");
  return isOn === equals;
}

function statusGaFor(device: Device, writeGa: string): string {
  const bag = (device as { ga?: Record<string, string> }).ga ?? {};
  const mapped: Array<[string | undefined, string | undefined]> = [
    [bag.switch, bag.switch_status],
    [bag.dim_value, bag.dim_status],
    [bag.position, bag.position_status],
    [bag.slat, bag.slat_status],
    [bag.setpoint, bag.setpoint_status]
  ];
  for (const [write, status] of mapped) {
    if (write && write === writeGa && status) return status;
  }
  if (device.type === "fireplace") {
    if (device.fireplace.onOff.ga === writeGa) {
      return device.fireplace.onOff.statusGa ?? writeGa;
    }
    if (device.fireplace.flame?.ga === writeGa) {
      return device.fireplace.flame.statusGa ?? writeGa;
    }
  }
  if (device.type === "ac") {
    if (device.ac.onOff.ga === writeGa) return device.ac.onOff.statusGa ?? writeGa;
    if (device.ac.setpoint.ga === writeGa) {
      return device.ac.setpoint.statusGa ?? writeGa;
    }
  }
  if (device.type === "fan") {
    if (device.fan.onOff.ga === writeGa) return device.fan.onOff.statusGa ?? writeGa;
    if (device.fan.speed?.ga === writeGa) {
      return device.fan.speed.statusGa ?? writeGa;
    }
  }
  if (device.type === "universal") {
    for (const b of device.universal.buttons) {
      if (
        writeGa === b.action.ga ||
        writeGa === b.actionOff?.ga ||
        writeGa === b.statusGa
      ) {
        return b.statusGa ?? writeGa;
      }
    }
  }
  return writeGa;
}

function valuesMatch(
  actual: unknown,
  expected: SceneAction["value"],
  role: SceneAction["role"]
): boolean {
  if (typeof expected === "boolean" || role === "switch" || role === "bit") {
    return asBool(actual) === asBool(expected);
  }
  if (typeof expected === "number" && typeof actual === "number") {
    const tol = role === "temperature" || role === "setpoint" ? 0.4 : 1.5;
    return Math.abs(actual - expected) <= tol;
  }
  return actual === expected;
}

function asBool(v: unknown): boolean {
  if (v === true || v === 1 || v === "1") return true;
  if (v === false || v === 0 || v === "0") return false;
  return Boolean(v);
}
