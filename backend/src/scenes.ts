import { logger } from "./logger";
import { dispatch } from "./commands";
import type { KnxBus } from "./knxBus";
import type { MediaManager } from "./media/manager";
import type { HouseConfig, Scene, SceneAction, SceneMediaAction } from "./types";
import { pulseKnxGa, syncFireplaceVirtualForDiscreteGa } from "./fireplacePulse";

/**
 * Execute a scene: fire every KNX and media action sequentially with any
 * per-action delay. Errors on individual steps are logged but do not abort
 * the rest of the scene.
 */
export async function runScene(
  scene: Scene,
  bus: KnxBus,
  cfg?: HouseConfig,
  media?: MediaManager
): Promise<void> {
  logger.info(
    {
      id: scene.id,
      name: scene.name,
      actions: scene.actions.length,
      mediaActions: scene.mediaActions?.length ?? 0
    },
    "scene run"
  );
  for (const action of scene.actions) {
    if (action.delayMs && action.delayMs > 0) {
      await delay(action.delayMs);
    }
    try {
      await writeSceneAction(action, bus);
    } catch (err) {
      logger.warn({ err, action }, "scene action failed");
    }
  }
  for (const action of scene.mediaActions ?? []) {
    if (action.delayMs && action.delayMs > 0) {
      await delay(action.delayMs);
    }
    try {
      await writeSceneMediaAction(action, cfg, bus, media);
    } catch (err) {
      logger.warn({ err, action }, "scene media action failed");
    }
  }
}

async function writeSceneMediaAction(
  a: SceneMediaAction,
  cfg: HouseConfig | undefined,
  bus: KnxBus,
  media: MediaManager | undefined
): Promise<void> {
  if (!cfg || !media) throw new Error("media manager unavailable");
  switch (a.kind) {
    case "transport":
      await dispatch(
        { kind: "media.transport", deviceId: a.deviceId, action: a.action },
        cfg,
        bus,
        media
      );
      return;
    case "volume":
      await dispatch(
        { kind: "media.volume", deviceId: a.deviceId, value: a.value },
        cfg,
        bus,
        media
      );
      return;
    case "mute":
      await dispatch(
        { kind: "media.mute", deviceId: a.deviceId, muted: a.muted },
        cfg,
        bus,
        media
      );
      return;
    case "preset":
      await dispatch(
        {
          kind: "media.preset",
          deviceId: a.deviceId,
          presetId: a.presetId,
          uri: a.uri
        },
        cfg,
        bus,
        media
      );
      return;
  }
}

async function writeSceneAction(a: SceneAction, bus: KnxBus): Promise<void> {
  if (a.role === "pulse") {
    await pulseKnxGa(bus, a.ga, a.pulseMs);
    syncFireplaceVirtualForDiscreteGa(a.ga);
    return;
  }
  if (a.role === "raw_bytes") {
    if (!Array.isArray(a.value)) throw new Error("raw_bytes action needs number[] value");
    const buf = Buffer.from(a.value.map((x) => clamp(Math.round(Number(x)), 0, 255)));
    await bus.writeRaw(a.ga, buf, buf.length * 8);
    return;
  }
  if (a.role === "rgb232") {
    const triplet = parseRgb232Value(a.value);
    await bus.write(a.ga, "rgb232", triplet);
    return;
  }
  const busRole = sceneRoleToBusRole(a.role);
  const value = coerceValue(a);
  await bus.write(a.ga, busRole, value);
}

function parseRgb232Value(
  v: SceneAction["value"]
): { red: number; green: number; blue: number } {
  if (Array.isArray(v) && v.length >= 3) {
    return {
      red: clamp(Math.round(Number(v[0])), 0, 255),
      green: clamp(Math.round(Number(v[1])), 0, 255),
      blue: clamp(Math.round(Number(v[2])), 0, 255)
    };
  }
  if (v != null && typeof v === "object" && !Array.isArray(v)) {
    const o = v as unknown as Record<string, unknown>;
    return {
      red: clamp(Math.round(Number(o.red)), 0, 255),
      green: clamp(Math.round(Number(o.green)), 0, 255),
      blue: clamp(Math.round(Number(o.blue)), 0, 255)
    };
  }
  throw new Error("rgb232 scene action needs [r,g,b] or {red,green,blue}");
}

function sceneRoleToBusRole(role: SceneAction["role"]): string {
  switch (role) {
    case "switch":
      return "switch";
    case "dim_value":
      return "dim_value";
    case "setpoint":
      return "setpoint";
    case "position":
      return "position";
    case "scene_number":
      return "scene_number";
    case "bit":
      return "bit";
    case "byte":
      return "byte";
    case "percent":
      return "percent";
    case "temperature":
      return "temperature";
    case "pulse":
    case "raw_bytes":
    case "rgb232":
      throw new Error("unreachable");
  }
}

function coerceValue(a: SceneAction): number | boolean {
  const v = a.value;
  if (Array.isArray(v) || (typeof v === "object" && v !== null)) {
    throw new Error("coerceValue: expected scalar value");
  }
  if (a.role === "switch" || a.role === "bit") {
    if (typeof v === "boolean") return v;
    return v !== 0;
  }
  if (typeof v === "boolean") return v ? 1 : 0;
  if (a.role === "percent" || a.role === "dim_value" || a.role === "position") {
    return clamp(v, 0, 100);
  }
  if (a.role === "scene_number") {
    return clamp(Math.round(v), 0, 63);
  }
  if (a.role === "byte") {
    return clamp(Math.round(v), 0, 255);
  }
  if (a.role === "temperature" || a.role === "setpoint") {
    return clamp(v, 5, 35);
  }
  return v;
}

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}
