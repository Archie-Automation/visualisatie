import { z } from "zod";
import type { Device, HouseConfig, UniversalAction, FireplacePulseChannel, Rgb232Triplet, ShadingDevice, PositionActuatorDevice } from "./types";
import type { KnxBus } from "./knxBus";
import type { MediaManager } from "./media/manager";
import type { LutronIntegrationManager } from "./lutron/manager";
import { resolveLutronLoadOutput } from "./lutron/resolve";
import { walkDevices } from "./config";
import { hvacSwitchLock } from "./hvacSwitchLock";
import { fireplaceVirtual } from "./fireplaceVirtual";
import { pulseKnxGa } from "./fireplacePulse";

type PositionControllableDevice = ShadingDevice | PositionActuatorDevice;

function isPositionControllable(device: Device): device is PositionControllableDevice {
  return device.type === "shading" || device.type === "position_actuator";
}

type FlameStepRange = { min: number; max: number; write?: number | null };

function flameWritePercentForStep(ranges: FlameStepRange[], step1Based: number): number {
  const i = Math.max(0, Math.min(ranges.length - 1, step1Based - 1));
  const r = ranges[i];
  if (r.write !== undefined && r.write !== null) {
    return Math.max(0, Math.min(100, Math.round(Number(r.write))));
  }
  return Math.max(
    0,
    Math.min(100, Math.round((Number(r.min) + Number(r.max)) / 2))
  );
}

/** Accept standnummer (1..N), schrijf-% of bus-% uit oudere clients. */
function resolveFlameStep1Based(ranges: FlameStepRange[], cmdValue: number): number {
  const v = Math.round(cmdValue);
  if (v >= 1 && v <= ranges.length) return v;
  for (let i = 0; i < ranges.length; i++) {
    if (v === flameWritePercentForStep(ranges, i + 1)) return i + 1;
  }
  for (let i = 0; i < ranges.length; i++) {
    const min = Math.round(Number(ranges[i].min));
    const max = Math.round(Number(ranges[i].max));
    if (v >= min && v <= max) return i + 1;
  }
  let best = 1;
  let bestDist = Number.POSITIVE_INFINITY;
  for (let i = 0; i < ranges.length; i++) {
    const mid = flameWritePercentForStep(ranges, i + 1);
    const d = Math.abs(v - mid);
    if (d < bestDist) {
      bestDist = d;
      best = i + 1;
    }
  }
  return best;
}

/**
 * A high-level intent coming from the app. Decoupled from KNX so the
 * UI never needs to know group-address numerology.
 */
export const CommandSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("light.switch"),
    deviceId: z.string(),
    on: z.boolean()
  }),
  z.object({
    kind: z.literal("light.dim"),
    deviceId: z.string(),
    percent: z.number().min(0).max(100)
  }),
  z.object({
    kind: z.literal("rgbw_ww.channel"),
    deviceId: z.string(),
    channel: z.enum(["r", "g", "b", "w", "ww", "cw"]),
    value: z.number().int().min(0).max(255)
  }),
  z.object({
    kind: z.literal("rgbw_ww.composite"),
    deviceId: z.string(),
    bytes: z.array(z.number().int().min(0).max(255)).min(1).max(14)
  }),
  z.object({
    kind: z.literal("rgbw_ww.rgb232"),
    deviceId: z.string(),
    red: z.number().int().min(0).max(255),
    green: z.number().int().min(0).max(255),
    blue: z.number().int().min(0).max(255)
  }),
  z.object({
    kind: z.literal("rgbw_ww.tunable_white"),
    deviceId: z.string(),
    /** 0–255 helderheid */
    brightness: z.number().int().min(0).max(255),
    /**
     * 0.0 = volledig warm (kelvinMin), 1.0 = volledig koud (kelvinMax).
     * De backend berekent de juiste ww/cw of kelvin-waarden.
     */
    warmCoolRatio: z.number().min(0).max(1)
  }),
  z.object({
    kind: z.literal("shading.move"),
    deviceId: z.string(),
    direction: z.enum(["up", "down", "stop"])
  }),
  z.object({
    kind: z.literal("shading.position"),
    deviceId: z.string(),
    percent: z.number().min(0).max(100)
  }),
  z.object({
    kind: z.literal("shading.slats"),
    deviceId: z.string(),
    percent: z.number().min(0).max(100)
  }),
  z.object({
    kind: z.literal("climate.setpoint"),
    deviceId: z.string(),
    celsius: z.number().min(5).max(35)
  }),
  z.object({
    kind: z.literal("climate.mode"),
    deviceId: z.string(),
    /** 1 = verwarmen, 0 = koelen (DPT 1.100). */
    heat: z.boolean()
  }),
  z.object({
    kind: z.literal("climate.opmode"),
    deviceId: z.string(),
    /** DPT 20.102: 1=Comfort 2=Standby 3=Economy 4=BuildingProtection */
    mode: z.number().int().min(1).max(4)
  }),

  /* ------------------------- Fireplace ---------------------------- */
  z.object({
    kind: z.literal("fireplace.on"),
    deviceId: z.string(),
    on: z.boolean()
  }),
  z.object({
    kind: z.literal("fireplace.flame"),
    deviceId: z.string(),
    value: z.number()
  }),
  z.object({
    kind: z.literal("fireplace.discrete"),
    deviceId: z.string(),
    action: z.enum(["on", "off", "up", "down"])
  }),

  /* ---------------------------- AC -------------------------------- */
  z.object({
    kind: z.literal("ac.on"),
    deviceId: z.string(),
    on: z.boolean()
  }),
  z.object({
    kind: z.literal("ac.setpoint"),
    deviceId: z.string(),
    celsius: z.number().min(5).max(35)
  }),
  z.object({
    kind: z.literal("ac.mode"),
    deviceId: z.string(),
    value: z.number().int().min(0).max(255)
  }),
  z.object({
    kind: z.literal("ac.fanSpeed"),
    deviceId: z.string(),
    value: z.number().int().min(0).max(255)
  }),

  /* --------------------------- Fan -------------------------------- */
  z.object({
    kind: z.literal("fan.on"),
    deviceId: z.string(),
    on: z.boolean()
  }),
  z.object({
    kind: z.literal("fan.speed"),
    deviceId: z.string(),
    value: z.number().int().min(0).max(255)
  }),
  z.object({
    kind: z.literal("fan.oscillate"),
    deviceId: z.string(),
    on: z.boolean()
  }),
  z.object({
    kind: z.literal("fan.direction"),
    deviceId: z.string(),
    reverse: z.boolean()
  }),

  /* ------------------------- Universal ---------------------------- */
  z.object({
    kind: z.literal("universal.press"),
    deviceId: z.string(),
    buttonId: z.string(),
    /** Optional explicit intent for on/off switches. When provided (and the
     *  button has an `actionOff`), the action is chosen directly from this
     *  value instead of being derived from the (possibly shared) status GA —
     *  this avoids feedback loops when send- and status-GA are identical. */
    on: z.boolean().optional()
  }),

  /* ----------------------------- WTW ------------------------------ */
  z.object({
    kind: z.literal("wtw.press"),
    deviceId: z.string(),
    buttonId: z.string()
  }),

  /* --------------------------- Media ------------------------------ */
  z.object({
    kind: z.literal("media.transport"),
    deviceId: z.string(),
    action: z.enum(["play", "pause", "stop", "next", "previous"])
  }),
  z.object({
    kind: z.literal("media.volume"),
    deviceId: z.string(),
    value: z.number().min(0).max(100)
  }),
  z.object({
    kind: z.literal("media.mute"),
    deviceId: z.string(),
    muted: z.boolean()
  }),
  z.object({
    kind: z.literal("media.preset"),
    deviceId: z.string(),
    presetId: z.string().min(1),
    uri: z.string().optional()
  }),
  z.object({
    kind: z.literal("media.playItem"),
    deviceId: z.string(),
    /** Brand-specific playable reference (Sonos URI or BluOS playURL). */
    ref: z.string().min(1),
    /** Optional metadata for artwork fallback while the stream starts. */
    title: z.string().optional(),
    image: z.string().optional()
  }),
  z.object({
    kind: z.literal("media.group.join"),
    deviceId: z.string(),
    coordinatorId: z.string().min(1)
  }),
  z.object({
    kind: z.literal("media.group.leave"),
    deviceId: z.string()
  }),

  z.object({
    kind: z.literal("lutron.fireMapping"),
    deviceId: z.string(),
    mappingId: z.string().min(1)
  })
]);

export type Command = z.infer<typeof CommandSchema>;

function findDevice(cfg: HouseConfig, id: string): Device | undefined {
  for (const c of cfg.cameras ?? []) {
    if (c.id === id) return c;
  }
  let found: Device | undefined;
  walkDevices(cfg, (d) => {
    if (d.id === id) found = d;
  });
  return found;
}

export async function dispatch(
  cmd: Command,
  cfg: HouseConfig,
  bus: KnxBus,
  media?: MediaManager,
  lutron?: LutronIntegrationManager
): Promise<void> {
  const device = findDevice(cfg, cmd.deviceId);
  if (!device) throw new Error(`unknown device: ${cmd.deviceId}`);

  switch (cmd.kind) {
    case "light.switch": {
      if (device.type !== "light_switch" && device.type !== "light_dimmer" && device.type !== "rgbw_ww")
        throw new Error("device does not support switch");
      const lut = resolveLutronLoadOutput(device);
      if (lut) {
        if (!lutron) throw new Error("Lutron-integratie niet beschikbaar");
        lutron.setHomeworksOutputLevel(lut, cmd.on ? 100 : 0);
        return;
      }
      const switchGa = (device.ga as any).switch ?? (device.ga as any).on;
      if (!switchGa) throw new Error("no switch/on GA");
      await bus.write(switchGa, "switch", cmd.on);
      return;
    }
    case "light.dim": {
      if (device.type !== "light_dimmer") throw new Error("device not dimmable");
      const lut = resolveLutronLoadOutput(device);
      if (lut) {
        if (!lutron) throw new Error("Lutron-integratie niet beschikbaar");
        if (lut.loadType === "shade") {
          throw new Error("Lutron-shade: gebruik zonwering-bediening, geen dimmer");
        }
        lutron.setHomeworksOutputLevel(lut, cmd.percent);
        return;
      }
      if (cmd.percent > 0) {
        if (!device.ga.switch) throw new Error("no switch GA");
        await bus.write(device.ga.switch, "switch", true);
      }
      if (!device.ga.dim_value) throw new Error("no dim_value GA");
      await bus.write(device.ga.dim_value, "dim_value", cmd.percent);
      if (cmd.percent === 0) {
        if (!device.ga.switch) throw new Error("no switch GA");
        await bus.write(device.ga.switch, "switch", false);
      }
      return;
    }
    case "rgbw_ww.channel": {
      if (device.type !== "rgbw_ww") throw new Error("not an rgbw_ww device");
      if (device.rgbwWw.mode !== "channels") {
        throw new Error("rgbw_ww is not in channel mode");
      }
      const ga = device.ga[cmd.channel];
      if (!ga) throw new Error(`no GA for channel ${cmd.channel}`);
      await bus.write(ga, cmd.channel, cmd.value);
      return;
    }
    case "rgbw_ww.composite": {
      if (device.type !== "rgbw_ww") throw new Error("not an rgbw_ww device");
      if (device.rgbwWw.mode !== "composite") {
        throw new Error("rgbw_ww is not in composite mode");
      }
      const ga = device.ga.composite;
      if (!ga) throw new Error("no composite GA configured");
      const want = Math.min(14, Math.max(1, device.rgbwWw.payloadBytes ?? 14));
      const bytes = [...cmd.bytes];
      while (bytes.length < want) bytes.push(0);
      if (bytes.length > want) bytes.length = want;
      await bus.writeRaw(ga, Buffer.from(bytes), want * 8);
      return;
    }
    case "rgbw_ww.rgb232": {
      if (device.type !== "rgbw_ww") throw new Error("not an rgbw_ww device");
      if (device.rgbwWw.mode !== "rgb232") {
        throw new Error("rgbw_ww is not in rgb232 mode");
      }
      const ga = device.ga.rgb232;
      if (!ga) throw new Error("no rgb232 GA configured");
      const triplet: Rgb232Triplet = {
        red: cmd.red,
        green: cmd.green,
        blue: cmd.blue
      };
      await bus.write(ga, "rgb232", triplet);
      return;
    }
    case "rgbw_ww.tunable_white": {
      if (device.type !== "rgbw_ww") throw new Error("not an rgbw_ww device");
      const { brightness, warmCoolRatio } = cmd;
      const cfg = device.rgbwWw;
      const gaMap = device.ga;

      // Option A: ww + cw channels
      if (gaMap.ww || gaMap.cw) {
        const warm = Math.round(brightness * (1 - warmCoolRatio));
        const cool = Math.round(brightness * warmCoolRatio);
        if (gaMap.ww) await bus.write(gaMap.ww, "ww", warm);
        if (gaMap.cw) await bus.write(gaMap.cw, "cw", cool);
        return;
      }

      // Option B: bright + kelvin GAs
      if (gaMap.bright) {
        await bus.write(gaMap.bright, "r", brightness); // DPT 5.010
      }
      if (gaMap.kelvin) {
        const kMin = cfg.kelvinMin ?? 2700;
        const kMax = cfg.kelvinMax ?? 6500;
        const kelvinVal = Math.round(kMin + warmCoolRatio * (kMax - kMin));
        await bus.write(gaMap.kelvin, "temperature", kelvinVal);
      }
      return;
    }
    case "shading.move": {
      if (!isPositionControllable(device)) throw new Error("device not position-controllable");
      const lut = resolveLutronLoadOutput(device);
      if (lut) {
        if (!lutron) throw new Error("Lutron-integratie niet beschikbaar");
        if (lut.loadType !== "shade") {
          throw new Error("Lutron-load voor zonwering moet loadType \"shade\" hebben");
        }
        if (cmd.direction === "stop") lutron.shadeHomeworksStop(lut);
        else if (cmd.direction === "up") lutron.shadeHomeworksRaise(lut);
        else lutron.shadeHomeworksLower(lut);
        return;
      }
      if (cmd.direction === "stop") {
        if (!device.ga.stop_step) throw new Error("no stop_step GA");
        await bus.write(device.ga.stop_step, "stop_step", true);
      } else {
        const up = cmd.direction === "up";
        await bus.write(device.ga.up_down, "up_down", !up);
      }
      return;
    }
    case "shading.position": {
      if (!isPositionControllable(device)) throw new Error("device not position-controllable");
      const lut = resolveLutronLoadOutput(device);
      if (lut) {
        if (!lutron) throw new Error("Lutron-integratie niet beschikbaar");
        if (lut.loadType !== "shade") {
          throw new Error("Lutron-load voor zonwering moet loadType \"shade\" hebben");
        }
        lutron.setHomeworksOutputLevel(lut, cmd.percent);
        return;
      }
      if (!device.ga.position) throw new Error("no position GA");
      await bus.write(device.ga.position, "position", cmd.percent);
      if (
        device.ga.position_status &&
        device.ga.position_status !== device.ga.position
      ) {
        bus.reflectLocal(device.ga.position_status, cmd.percent, "position_status");
      }
      return;
    }
    case "shading.slats": {
      if (!isPositionControllable(device)) throw new Error("device not position-controllable");
      const lut = resolveLutronLoadOutput(device);
      if (lut) {
        if (!lutron) throw new Error("Lutron-integratie niet beschikbaar");
        const slatId =
          device.type === "shading" ? device.lutronSlatIntegrationId : undefined;
        if (!slatId || slatId < 1) {
          throw new Error(
            "Lutron-shade: stel lutronSlatIntegrationId in voor lamelbesturing"
          );
        }
        lutron.shadeHomeworksSetSlats(lut, slatId, cmd.percent);
        return;
      }
      if (!device.ga.slat) throw new Error("no slat GA");
      await bus.write(device.ga.slat, "position", cmd.percent);
      return;
    }
    case "climate.setpoint": {
      if (device.type !== "climate") throw new Error("device not a climate");
      await bus.write(device.ga.setpoint, "setpoint", cmd.celsius);
      return;
    }
    case "climate.mode": {
      if (device.type !== "climate") throw new Error("device not a climate");
      const ga = device.ga.hvac_mode;
      if (!ga) throw new Error("no hvac_mode GA configured");
      // DPT 1.100: 1 = heat, 0 = cool
      await bus.write(ga, "switch", cmd.heat);
      hvacSwitchLock.arm(device.id, device.climate?.hvacSwitchLockDuration);
      return;
    }
    case "climate.opmode": {
      if (device.type !== "climate") throw new Error("device not a climate");
      const ga = device.ga.mode;
      if (!ga) throw new Error("no mode GA configured");
      // DPT 20.102: 1=Comfort 2=Standby 3=Economy 4=BuildingProtection
      await bus.write(ga, "byte", cmd.mode);
      return;
    }

    /* ------------------------- Fireplace ---------------------------- */
    case "fireplace.on": {
      if (device.type !== "fireplace") throw new Error("not a fireplace");
      const fp = device.fireplace;
      const discreteMode = fp.controlMode === "discrete" && fp.discreteLevel;
      if (discreteMode) {
        const dl = fp.discreteLevel!;
        if (cmd.on && dl.on) {
          await pulseKnxGa(bus, dl.on.ga, dl.on.pulseMs);
          fireplaceVirtual.set(device.id, true);
          return;
        }
        if (!cmd.on && dl.off) {
          await pulseKnxGa(bus, dl.off.ga, dl.off.pulseMs);
          fireplaceVirtual.set(device.id, false);
          return;
        }
      }
      await bus.write(fp.onOff.ga, "switch", cmd.on);
      return;
    }
    case "fireplace.flame": {
      if (device.type !== "fireplace") throw new Error("not a fireplace");
      if (device.fireplace.controlMode === "discrete") {
        throw new Error("fireplace has no analog flame in discrete mode");
      }
      if (!device.fireplace.flame) throw new Error("no flame control");
      const flame = device.fireplace.flame;
      const ranges = flame.stepRanges;
      if (ranges && ranges.length > 0) {
        const step = resolveFlameStep1Based(ranges, cmd.value);
        const pct = flameWritePercentForStep(ranges, step);
        await bus.write(flame.ga, "percent", pct);
        if (flame.statusGa && flame.statusGa !== flame.ga) {
          bus.reflectLocal(flame.statusGa, pct, "percent");
        }
        return;
      }
      const steps = device.fireplace.flame.steps;
      const value = steps
        ? Math.max(1, Math.min(steps, Math.round(cmd.value)))
        : Math.max(0, Math.min(100, Math.round(cmd.value)));
      await bus.write(
        device.fireplace.flame.ga,
        steps ? "flame" : "percent",
        value
      );
      return;
    }
    case "fireplace.discrete": {
      if (device.type !== "fireplace") throw new Error("not a fireplace");
      if (device.fireplace.controlMode !== "discrete") {
        throw new Error("fireplace is not in discrete control mode");
      }
      const dl = device.fireplace.discreteLevel;
      if (!dl) throw new Error("no discreteLevel");
      let ch: FireplacePulseChannel | undefined;
      switch (cmd.action) {
        case "on":
          ch = dl.on;
          break;
        case "off":
          ch = dl.off;
          break;
        case "up":
          ch = dl.up;
          break;
        case "down":
          ch = dl.down;
          break;
        default:
          throw new Error("invalid discrete action");
      }
      if (!ch) throw new Error(`discreteLevel.${cmd.action} not configured`);
      await pulseKnxGa(bus, ch.ga, ch.pulseMs);
      if (cmd.action === "on") fireplaceVirtual.set(device.id, true);
      else if (cmd.action === "off") fireplaceVirtual.set(device.id, false);
      return;
    }

    /* ---------------------------- AC -------------------------------- */
    case "ac.on": {
      if (device.type !== "ac") throw new Error("not an ac");
      await bus.write(device.ac.onOff.ga, "switch", cmd.on);
      return;
    }
    case "ac.setpoint": {
      if (device.type !== "ac") throw new Error("not an ac");
      await bus.write(device.ac.setpoint.ga, "setpoint", cmd.celsius);
      return;
    }
    case "ac.mode": {
      if (device.type !== "ac") throw new Error("not an ac");
      if (!device.ac.mode) throw new Error("no mode control");
      await bus.write(device.ac.mode.ga, "ac_mode", cmd.value);
      return;
    }
    case "ac.fanSpeed": {
      if (device.type !== "ac") throw new Error("not an ac");
      if (!device.ac.fanSpeed) throw new Error("no fan control");
      await bus.write(device.ac.fanSpeed.ga, "fan_speed", cmd.value);
      return;
    }

    /* --------------------------- Fan -------------------------------- */
    case "fan.on": {
      if (device.type !== "fan") throw new Error("not a fan");
      await bus.write(device.fan.onOff.ga, "switch", cmd.on);
      return;
    }
    case "fan.speed": {
      if (device.type !== "fan") throw new Error("not a fan");
      if (!device.fan.speed) throw new Error("no speed control");
      const { steps, speedMode } = device.fan.speed;
      const mode = speedMode ?? (steps ? "steps" : "percent");
      let value: number;
      let role: string;
      if (mode === "steps") {
        const n = steps ?? 3;
        value = Math.max(0, Math.min(n, Math.round(cmd.value)));
        role = "byte";
      } else if (mode === "byte") {
        value = Math.max(0, Math.min(255, Math.round(cmd.value)));
        role = "byte";
      } else {
        // percent
        value = Math.max(0, Math.min(100, Math.round(cmd.value)));
        role = "percent";
      }
      await bus.write(device.fan.speed.ga, role, value);
      return;
    }
    case "fan.oscillate": {
      if (device.type !== "fan") throw new Error("not a fan");
      if (!device.fan.oscillate) throw new Error("no oscillate control");
      await bus.write(device.fan.oscillate.ga, "switch", cmd.on);
      return;
    }
    case "fan.direction": {
      if (device.type !== "fan") throw new Error("not a fan");
      if (!device.fan.direction) throw new Error("no direction control");
      await bus.write(device.fan.direction.ga, "switch", cmd.reverse);
      return;
    }

    /* --------------------------- Media ------------------------------ */
    case "media.transport": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.command(device.id, { action: cmd.action });
      return;
    }
    case "media.volume": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.command(device.id, { action: "volume", value: cmd.value });
      return;
    }
    case "media.mute": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.command(device.id, { action: "mute", value: cmd.muted });
      return;
    }
    case "media.preset": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.command(device.id, { action: "preset", presetId: cmd.presetId, uri: cmd.uri });
      return;
    }
    case "media.playItem": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.playItem(device.id, cmd.ref, { title: cmd.title, image: cmd.image });
      return;
    }
    case "media.group.join": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.group(device.id, cmd.coordinatorId);
      return;
    }
    case "media.group.leave": {
      assertMedia(device);
      if (!media) throw new Error("media manager unavailable");
      await media.ungroup(device.id);
      return;
    }

    /* ------------------------- Universal ---------------------------- */
    case "universal.press": {
      if (device.type !== "universal") throw new Error("not a universal panel");
      const btn = device.universal.buttons.find((b) => b.id === cmd.buttonId);
      if (!btn) throw new Error("unknown button");
      let action: UniversalAction = btn.action;
      if (btn.actionOff) {
        if (typeof cmd.on === "boolean") {
          // Explicit intent from an on/off switch — deterministic, no status
          // read. Prevents loops when send- and status-GA are the same.
          action = cmd.on ? btn.action : btn.actionOff;
        } else if (btn.statusGa) {
          // Tap-to-toggle: derive the next action from the current status.
          const current = bus.getState(btn.statusGa)?.value;
          const onValue = btn.statusOnValue ?? true;
          const isOn =
            typeof onValue === "boolean"
              ? current === onValue || current === (onValue ? 1 : 0)
              : current === onValue;
          action = isOn ? btn.actionOff : btn.action;
        }
      }
      await writeUniversalAction(action, bus);
      return;
    }

    case "wtw.press": {
      if (device.type !== "wtw") throw new Error("not a WTW device");
      const btn = (device.wtw.buttons ?? []).find((b) => b.id === cmd.buttonId);
      if (!btn) throw new Error("unknown WTW button");
      const role = wtwDptToRole(btn.dpt);
      let val: number | boolean = btn.value;
      if (role === "bit") val = typeof val === "boolean" ? val : val !== 0;
      await bus.write(btn.ga, role, val);
      return;
    }

    case "lutron.fireMapping": {
      if (!lutron) throw new Error("Lutron-integratie niet actief");
      if (device.type !== "lutron_homeworks") throw new Error("not a Lutron device");
      await lutron.fireMapping(cmd.deviceId, cmd.mappingId);
      return;
    }
  }
}

function assertMedia(d: Device): void {
  if (d.type !== "media_sonos" && d.type !== "media_bluesound") {
    throw new Error("device is not a media player");
  }
}

async function writeUniversalAction(a: UniversalAction, bus: KnxBus) {
  const role = a.role; // bit | byte | percent | temperature | raw_int
  let value: number | boolean = a.value;
  if (role === "bit") {
    value = typeof value === "boolean" ? value : value !== 0;
  } else if (typeof value === "boolean") {
    value = value ? 1 : 0;
  }
  await bus.write(a.ga, role, value);
}

/** Maps a WTW DPT string to a KnxBus role string. */
function wtwDptToRole(dpt: string): string {
  if (dpt.startsWith("1.")) return "bit";
  if (dpt.startsWith("9.")) return "temperature"; // all DPT9.x share the same 2-byte float encoding
  if (dpt.startsWith("14.")) return "float4byte";
  const map: Record<string, string> = {
    "5.001": "percent",
    "5.010": "byte",
    "6.001": "signed_byte",
    "7.001": "uint16",
    "8.001": "signed_2byte",
    "12.001": "uint32",
    "13.001": "int32",
  };
  return map[dpt] ?? "byte";
}
