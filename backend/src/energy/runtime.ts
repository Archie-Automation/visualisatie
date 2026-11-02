import { getConfig } from "../config";
import type { KnxBus } from "../knxBus";
import type { GAState } from "../types";
import { configuredEnergyPoints } from "./points";
import {
  buildEnergySnapshot,
  emptyEnergySnapshot,
  type EnergySnapshot
} from "./snapshot";

type Listener = (snapshot: EnergySnapshot) => void;

/**
 * Folds KNX cache values into one energy snapshot. The Flutter client does
 * not recompute this. Offline keeps the last numbers and sets `stale`.
 */
class EnergyRuntime {
  private bus: KnxBus | null = null;
  private snapshot: EnergySnapshot = emptyEnergySnapshot();
  private watched = new Set<string>();
  private readonly listeners = new Set<Listener>();

  attach(bus: KnxBus): void {
    if (this.bus) return;
    this.bus = bus;
    bus.on("stateChanged", (state: GAState) => {
      if (!this.watched.has(state.ga)) return;
      this.refresh();
    });
    bus.on("connected", () => this.refresh());
    bus.on("disconnected", () => this.refresh());
    this.refresh();
  }

  onChange(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  getSnapshot(): EnergySnapshot {
    return this.snapshot;
  }

  /** Re-read config + cache. Call after house.json is saved. */
  refresh(): void {
    const cfg = getConfig();
    const points = configuredEnergyPoints(cfg);
    this.watched = new Set(points.map((p) => p.point.ga));
    const values = new Map<string, unknown>();
    if (this.bus) {
      for (const ga of this.watched) {
        const state = this.bus.getState(ga);
        if (state) values.set(ga, state.value);
      }
    }
    const next = buildEnergySnapshot({
      energy: cfg.energy,
      values,
      busConnected: this.bus?.connected ?? false
    });
    if (JSON.stringify(next) === JSON.stringify(this.snapshot)) return;
    this.snapshot = next;
    for (const fn of this.listeners) fn(next);
  }
}

export const energyRuntime = new EnergyRuntime();

export function attachEnergyRuntime(bus: KnxBus): void {
  energyRuntime.attach(bus);
}
