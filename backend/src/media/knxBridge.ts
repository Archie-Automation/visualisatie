import { getConfig, getConfigVersion, walkDevices } from "../config";
import type { KnxBus } from "../knxBus";
import { logger } from "../logger";
import type {
  Device,
  GA,
  GAState,
  HouseConfig,
  MediaKnxAction,
  MediaKnxConfig
} from "../types";
import type { MediaManager } from "./manager";

const VOLUME_STEP = 5;
const VOLUME_HOLD_MS = 250;

export type DimCommand = { stop: true } | { stop: false; increase: boolean; step: number };

export interface MediaKnxBinding {
  deviceId: string;
  action: MediaKnxAction;
  volumeAffectsGroup: boolean;
}

type MediaKnxListKey = Exclude<keyof MediaKnxConfig, "volumeAffectsGroup">;

const LIST_KEYS: Array<{ key: MediaKnxListKey; action: MediaKnxAction }> = [
  { key: "playPause", action: "playPause" },
  { key: "volumeDim", action: "volumeDim" },
  { key: "next", action: "next" },
  { key: "previous", action: "previous" }
];

export function mediaKnxOf(d: Device): MediaKnxConfig | undefined {
  if (d.type !== "media_sonos" && d.type !== "media_bluesound") return undefined;
  return d.knx;
}

export function isBitHigh(value: unknown): boolean {
  return value === true || value === 1 || value === "1" || value === "true";
}

export function isRisingEdge(prev: unknown, now: unknown): boolean {
  return isBitHigh(now) && !isBitHigh(prev);
}

/** Wall rockers send 1 on press and 0 on release. Toggle on the rising 1; ignore 0. */
export function playPauseToggleAction(playing: boolean): "play" | "pause" {
  return playing ? "pause" : "play";
}

export function asGaList(raw: unknown): string[] {
  if (typeof raw === "string") {
    const s = raw.trim();
    return s ? [s] : [];
  }
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const item of raw) {
    const s = String(item ?? "").trim();
    if (s) out.push(s);
  }
  return out;
}

export function decodeDimControl(value: unknown): DimCommand | null {
  if (value == null || typeof value === "boolean") return null;
  if (typeof value === "object") {
    const o = value as Record<string, unknown>;
    const stepRaw = o.data ?? o.step;
    if (stepRaw == null && o.decr_incr == null && o.increase == null) return null;
    const increase =
      o.decr_incr != null
        ? Number(o.decr_incr) !== 0
        : Boolean(o.increase);
    const step = Number(stepRaw ?? 0) & 7;
    if (step === 0) return { stop: true };
    return { stop: false, increase, step };
  }
  if (typeof value === "string") {
    if (value.trim() === "") return null;
    const n = Number(value);
    if (!Number.isFinite(n)) return null;
    return decodeDimControl(n);
  }
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const nibble = value & 15;
  const step = nibble & 7;
  const increase = (nibble & 8) !== 0;
  if (step === 0) return { stop: true };
  return { stop: false, increase, step };
}

export function nextVolume(current: number | undefined, increase: boolean, step = VOLUME_STEP): number {
  const base = typeof current === "number" && Number.isFinite(current) ? current : 0;
  return Math.max(0, Math.min(100, Math.round(base + (increase ? step : -step))));
}

export function resolveVolumeTarget(opts: {
  zoneVolume?: number;
  groupVolume?: number;
  increase: boolean;
  volumeAffectsGroup: boolean;
  grouped: boolean;
}): { kind: "zone" | "group"; next: number } {
  const useGroup = opts.volumeAffectsGroup && opts.grouped;
  const current = useGroup
    ? (opts.groupVolume ?? opts.zoneVolume)
    : opts.zoneVolume;
  return {
    kind: useGroup ? "group" : "zone",
    next: nextVolume(current, opts.increase)
  };
}

export function buildMediaKnxIndex(cfg: HouseConfig): Map<GA, MediaKnxBinding[]> {
  const index = new Map<GA, MediaKnxBinding[]>();
  walkDevices(cfg, (d) => {
    const knx = mediaKnxOf(d);
    if (!knx) return;
    const volumeAffectsGroup = knx.volumeAffectsGroup === true;
    for (const { key, action } of LIST_KEYS) {
      for (const ga of asGaList(knx[key])) {
        const bindings = index.get(ga) ?? [];
        bindings.push({ deviceId: d.id, action, volumeAffectsGroup });
        index.set(ga, bindings);
      }
    }
  });
  return index;
}

export function attachMediaKnxBridge(bus: KnxBus, media: MediaManager): { close(): void } {
  let idxVersion = -1;
  let index = new Map<GA, MediaKnxBinding[]>();
  const prevValues = new Map<GA, GAState["value"]>();
  const holds = new Map<string, { timer: ReturnType<typeof setInterval>; inflight: boolean }>();

  const rebuild = () => {
    const v = getConfigVersion();
    if (v === idxVersion) return;
    index = buildMediaKnxIndex(getConfig());
    idxVersion = v;
  };
  rebuild();

  const stopHold = (deviceId: string) => {
    const h = holds.get(deviceId);
    if (!h) return;
    clearInterval(h.timer);
    holds.delete(deviceId);
  };

  const applyVolume = async (binding: MediaKnxBinding, increase: boolean) => {
    const state = media.get(binding.deviceId);
    const grouped = state?.groupRole === "coordinator" || state?.groupRole === "member";
    const target = resolveVolumeTarget({
      zoneVolume: state?.volume,
      groupVolume: state?.groupVolume,
      increase,
      volumeAffectsGroup: binding.volumeAffectsGroup,
      grouped
    });
    try {
      if (target.kind === "group") {
        await media.setGroupVolume(binding.deviceId, target.next);
      } else {
        await media.command(binding.deviceId, { action: "volume", value: target.next });
      }
    } catch (err) {
      logger.warn(
        { err, id: binding.deviceId, kind: target.kind, next: target.next },
        "media KNX volume failed"
      );
    }
  };

  const startHold = (binding: MediaKnxBinding, increase: boolean) => {
    stopHold(binding.deviceId);
    const hold = { timer: undefined as unknown as ReturnType<typeof setInterval>, inflight: false };
    const tick = () => {
      if (hold.inflight) return;
      hold.inflight = true;
      void applyVolume(binding, increase).finally(() => {
        hold.inflight = false;
      });
    };
    tick();
    hold.timer = setInterval(tick, VOLUME_HOLD_MS);
    holds.set(binding.deviceId, hold);
  };

  const onBusState = (state: GAState) => {
    rebuild();
    const bindings = index.get(state.ga);
    if (!bindings || bindings.length === 0) return;

    const prev = prevValues.get(state.ga);
    prevValues.set(state.ga, state.value);

    for (const binding of bindings) {
      switch (binding.action) {
        case "playPause": {
          if (!isRisingEdge(prev, state.value)) break;
          const cur = media.get(binding.deviceId);
          const playing =
            cur?.transport === "playing" || cur?.transport === "buffering";
          const act = playPauseToggleAction(playing);
          void media.command(binding.deviceId, { action: act }).catch((err) => {
            logger.warn({ err, id: binding.deviceId, act }, "media KNX play/pause failed");
          });
          break;
        }
        case "next":
        case "previous": {
          if (!isBitHigh(state.value)) break;
          void media.command(binding.deviceId, { action: binding.action }).catch((err) => {
            logger.warn(
              { err, id: binding.deviceId, action: binding.action },
              "media KNX skip failed"
            );
          });
          break;
        }
        case "volumeDim": {
          const dim = decodeDimControl(state.value);
          if (!dim) break;
          if (dim.stop) {
            stopHold(binding.deviceId);
            break;
          }
          startHold(binding, dim.increase);
          break;
        }
      }
    }
  };

  bus.on("stateChanged", onBusState);

  return {
    close() {
      bus.off("stateChanged", onBusState);
      for (const id of [...holds.keys()]) stopHold(id);
    }
  };
}
