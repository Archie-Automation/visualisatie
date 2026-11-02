import { getConfig } from "../config";
import type { KnxBus } from "../knxBus";
import { logger } from "../logger";
import type { LogStore } from "../logStore";
import type { GAState } from "../types";
import { buildEnergyDay, emptyEnergyDay, type MeterSample } from "./day";
import { fetchEnergyZeroPrices } from "./energyzero";
import { addLocalDays, startOfLocalDay } from "./localDay";
import { configuredEnergyPoints } from "./points";
import {
  ENERGY_PRICE_ELECTRICITY,
  ENERGY_PRICE_GAS,
  slotsFromReadings,
  type PriceSlot
} from "./prices";
import {
  buildEnergySnapshot,
  emptyEnergySnapshot,
  type EnergySnapshot
} from "./snapshot";

type Listener = (snapshot: EnergySnapshot) => void;

const PRICE_POLL_MS = 30 * 60 * 1000;

/**
 * Folds KNX cache values into one energy snapshot. The Flutter client does
 * not recompute this. Offline keeps the last numbers and sets `stale`.
 * Day totals come from logged meter samples. Prices come from EnergyZero.
 */
class EnergyRuntime {
  private bus: KnxBus | null = null;
  private logStore: LogStore | null = null;
  private snapshot: EnergySnapshot = emptyEnergySnapshot();
  private watched = new Set<string>();
  private readonly listeners = new Set<Listener>();
  private electricity: PriceSlot[] = [];
  private gas: PriceSlot[] = [];
  private priceStale = false;
  private priceKey = "";
  private priceFlight: Promise<void> | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private readonly loggedReject = new Set<string>();

  attach(bus: KnxBus, logStore: LogStore): void {
    if (this.bus) return;
    this.bus = bus;
    this.logStore = logStore;
    bus.on("stateChanged", (state: GAState) => {
      if (!this.watched.has(state.ga)) return;
      this.refresh();
    });
    bus.on("connected", () => this.refresh());
    bus.on("disconnected", () => this.refresh());
    this.timer = setInterval(() => {
      void this.refreshPrices();
    }, PRICE_POLL_MS);
    this.timer.unref?.();
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
    const live = buildEnergySnapshot({
      energy: cfg.energy,
      values,
      busConnected: this.bus?.connected ?? false
    });
    const priceKey =
      JSON.stringify(cfg.energy?.prices ?? null) +
      String(cfg.energy?.enabled === true);
    if (priceKey !== this.priceKey) {
      this.priceKey = priceKey;
      void this.refreshPrices();
    }
    const tz = cfg.project?.timezone || "Europe/Amsterdam";
    const now = Date.now();
    let day = emptyEnergyDay();
    if (this.logStore && cfg.energy?.enabled === true) {
      const from = startOfLocalDay(new Date(now), tz).getTime();
      const till = addLocalDays(new Date(now), 2, tz).getTime();
      if (
        cfg.energy.prices?.enabled === true &&
        this.electricity.length === 0
      ) {
        this.loadCachedPrices(from - 36 * 3_600_000, till);
      }
      try {
        const cache = new Map<string, MeterSample[]>();
        day = buildEnergyDay({
          energy: cfg.energy,
          now,
          tz,
          gridPowerW: live.gridPowerW,
          series: (ga) => {
            let hit = cache.get(ga);
            if (!hit) {
              hit = this.logStore!.series(ga, from, now);
              cache.set(ga, hit);
            }
            return hit;
          },
          electricity: this.electricity,
          gas: this.gas,
          priceStale: this.priceStale
        });
      } catch (err) {
        logger.warn({ err }, "energy: dagtotaal berekenen mislukt");
      }
    }
    for (const reason of day.rejectedTotals) {
      if (this.loggedReject.has(reason)) continue;
      this.loggedReject.add(reason);
      logger.warn({ reason }, "energy: dagtotaal genegeerd (negatief of te groot)");
    }
    const next: EnergySnapshot = { ...live, ...day };
    if (JSON.stringify(next) === JSON.stringify(this.snapshot)) return;
    this.snapshot = next;
    for (const fn of this.listeners) fn(next);
  }

  private loadCachedPrices(from: number, to: number): void {
    if (!this.logStore) return;
    const slots = (ga: string): PriceSlot[] =>
      slotsFromReadings(
        this.logStore!.series(ga, from, to).map((row) => ({
          at: row.ts,
          price: row.value
        }))
      );
    if (this.electricity.length === 0) {
      this.electricity = slots(ENERGY_PRICE_ELECTRICITY);
    }
    if (this.gas.length === 0) this.gas = slots(ENERGY_PRICE_GAS);
  }

  private async refreshPrices(): Promise<void> {
    if (this.priceFlight) return this.priceFlight;
    this.priceFlight = this.fetchPrices().finally(() => {
      this.priceFlight = null;
    });
    return this.priceFlight;
  }

  private async fetchPrices(): Promise<void> {
    const cfg = getConfig();
    if (cfg.energy?.enabled !== true || cfg.energy.prices?.enabled !== true) {
      this.electricity = [];
      this.gas = [];
      this.priceStale = false;
      this.refresh();
      return;
    }
    const tz = cfg.project?.timezone || "Europe/Amsterdam";
    const now = new Date();
    const from = startOfLocalDay(now, tz);
    const till = addLocalDays(now, 2, tz);
    try {
      const [electricity, gas] = await Promise.all([
        fetchEnergyZeroPrices({ from, till, usageType: 1 }),
        fetchEnergyZeroPrices({ from, till, usageType: 3 })
      ]);
      this.electricity = electricity;
      this.gas = gas;
      this.priceStale = false;
      if (this.logStore) {
        for (const slot of electricity) {
          this.logStore.putAt(ENERGY_PRICE_ELECTRICITY, slot.from, slot.market);
        }
        for (const slot of gas) {
          this.logStore.putAt(ENERGY_PRICE_GAS, slot.from, slot.market);
        }
      }
    } catch (err) {
      logger.warn({ err }, "energy: EnergyZero niet bereikbaar, laatste curve blijft");
      this.priceStale = true;
      this.loadCachedPrices(from.getTime() - 36 * 3_600_000, till.getTime());
    }
    this.refresh();
  }
}

export const energyRuntime = new EnergyRuntime();

export function attachEnergyRuntime(bus: KnxBus, logStore: LogStore): void {
  energyRuntime.attach(bus, logStore);
}
