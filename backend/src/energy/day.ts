import type { HouseConfig, HouseEnergyConfig } from "../types";
import { addLocalDays, startOfLocalDay } from "./localDay";
import { configuredEnergyPoints, energyScale, type EnergyPointKey } from "./points";
import {
  MAX_DAY_GAS_M3,
  MAX_DAY_KWH,
  MAX_HOUR_KWH,
  consumerPrice,
  moneyFromSlots,
  type PriceSlot,
  type TariffSpec
} from "./prices";

export interface EnergyPriceHour {
  from: number;
  till: number;
  importEur: number | null;
  exportEur: number | null;
}

export interface EnergyDay {
  todayImportKwh: number | null;
  todayExportKwh: number | null;
  todaySolarKwh: number | null;
  todayGasM3: number | null;
  todayImportPartial: boolean;
  todayExportPartial: boolean;
  todaySolarPartial: boolean;
  todayGasPartial: boolean;
  todayImportEstimated: boolean;
  todayExportEstimated: boolean;
  todaySolarEstimated: boolean;
  todayCostEur: number | null;
  todayFeedInEur: number | null;
  todayGasCostEur: number | null;
  todayNetEur: number | null;
  openHourImportEur: number | null;
  openHourFeedInEur: number | null;
  openHourGasEur: number | null;
  importPriceEurPerKwh: number | null;
  exportPriceEurPerKwh: number | null;
  gasPriceEurPerM3: number | null;
  /** Positive = paying for import. Negative = earning on export. A rate, not a day total. */
  tempoEurPerHour: number | null;
  priceStale: boolean;
  priceHours: EnergyPriceHour[];
  /** Meter deltas that were dropped because they went backwards or jumped. */
  rejectedTotals: string[];
}

export interface MeterSample {
  ts: number;
  value: number;
}

export function emptyEnergyDay(): EnergyDay {
  return {
    todayImportKwh: null,
    todayExportKwh: null,
    todaySolarKwh: null,
    todayGasM3: null,
    todayImportPartial: false,
    todayExportPartial: false,
    todaySolarPartial: false,
    todayGasPartial: false,
    todayImportEstimated: false,
    todayExportEstimated: false,
    todaySolarEstimated: false,
    todayCostEur: null,
    todayFeedInEur: null,
    todayGasCostEur: null,
    todayNetEur: null,
    openHourImportEur: null,
    openHourFeedInEur: null,
    openHourGasEur: null,
    importPriceEurPerKwh: null,
    exportPriceEurPerKwh: null,
    gasPriceEurPerM3: null,
    tempoEurPerHour: null,
    priceStale: false,
    priceHours: [],
    rejectedTotals: []
  };
}

interface CounterResult {
  delta: number | null;
  partial: boolean;
  estimated: boolean;
  rejected: boolean;
}

/** Last sample at or before `ts`. `samples` must be sorted by time. */
export function heldValue(samples: MeterSample[], ts: number): number | null {
  let last: number | null = null;
  for (const sample of samples) {
    if (sample.ts > ts) break;
    if (Number.isFinite(sample.value)) last = sample.value;
  }
  return last;
}

export function meterWindowDelta(input: {
  samples: MeterSample[];
  scale: number;
  from: number;
  to: number;
  maxDelta: number;
  /** When true, a baseline after `from` still counts and is marked partial. */
  allowPartial: boolean;
}): { delta: number | null; partial: boolean; rejected: boolean } {
  const samples = [...input.samples].sort((a, b) => a.ts - b.ts);
  const endRaw = heldValue(samples, input.to);
  if (endRaw == null) return { delta: null, partial: false, rejected: false };
  let baseline = heldValue(samples, input.from);
  let partial = false;
  if (baseline == null) {
    if (!input.allowPartial) return { delta: null, partial: false, rejected: false };
    const first = samples.find((s) => s.ts > input.from && s.ts <= input.to);
    if (!first) return { delta: null, partial: false, rejected: false };
    baseline = first.value;
    partial = true;
  }
  const delta = round3((endRaw - baseline) * input.scale);
  if (!Number.isFinite(delta) || delta < 0 || delta > input.maxDelta) {
    return { delta: null, partial, rejected: true };
  }
  return { delta, partial, rejected: false };
}

/**
 * Piecewise-constant integral of watts. Samples are held until the next one.
 * Returns kWh. `pick` drops the direction that does not belong to this total.
 */
export function integrateWattsKwh(input: {
  samples: MeterSample[];
  scale: number;
  from: number;
  to: number;
  pick: (watts: number) => number;
  maxKwh: number;
}): { kwh: number | null; partial: boolean; rejected: boolean } {
  const samples = [...input.samples]
    .filter((s) => Number.isFinite(s.value))
    .sort((a, b) => a.ts - b.ts);
  if (input.to <= input.from) return { kwh: null, partial: false, rejected: false };
  let value = heldValue(samples, input.from);
  let cursor = input.from;
  let partial = false;
  if (value == null) {
    const first = samples.find((s) => s.ts > input.from && s.ts <= input.to);
    if (!first) return { kwh: null, partial: false, rejected: false };
    value = first.value;
    cursor = first.ts;
    partial = true;
  }
  let wh = 0;
  for (const sample of samples) {
    if (sample.ts <= cursor || sample.ts > input.to) continue;
    wh += input.pick(value * input.scale) * ((sample.ts - cursor) / 3_600_000);
    cursor = sample.ts;
    value = sample.value;
  }
  if (cursor < input.to) {
    wh += input.pick(value * input.scale) * ((input.to - cursor) / 3_600_000);
  }
  const kwh = round3(wh / 1000);
  if (!Number.isFinite(kwh) || kwh < 0 || kwh > input.maxKwh) {
    return { kwh: null, partial, rejected: true };
  }
  return { kwh, partial, rejected: false };
}

function tariffOf(
  surcharge: number | undefined,
  vat: boolean | undefined
): TariffSpec {
  return {
    surcharge: typeof surcharge === "number" && Number.isFinite(surcharge) ? surcharge : 0,
    vat: vat === true
  };
}

function priceAt(slots: PriceSlot[], ts: number): PriceSlot | null {
  for (const slot of slots) {
    if (ts >= slot.from && ts < slot.till) return slot;
  }
  return null;
}

export function buildEnergyDay(input: {
  energy: HouseEnergyConfig | undefined;
  now: number;
  tz: string;
  gridPowerW: number | null;
  series: (ga: string) => MeterSample[];
  electricity: PriceSlot[];
  gas: PriceSlot[];
  priceStale: boolean;
}): EnergyDay {
  const day = emptyEnergyDay();
  if (input.energy?.enabled !== true) return day;
  const now = input.now;
  const dayFrom = startOfLocalDay(new Date(now), input.tz).getTime();
  const dayTill = addLocalDays(new Date(now), 1, input.tz).getTime();
  const points = new Map(
    configuredEnergyPoints({ energy: input.energy } as HouseConfig).map((p) => [
      p.key,
      p.point
    ])
  );

  const counter = (
    key: EnergyPointKey,
    maxDelta: number,
    powerKey: EnergyPointKey | null,
    pick: ((watts: number) => number) | null
  ): CounterResult => {
    const point = points.get(key);
    if (point) {
      const scale = energyScale(point.scale);
      if (scale == null) return { delta: null, partial: false, estimated: false, rejected: false };
      const meter = meterWindowDelta({
        samples: input.series(point.ga),
        scale,
        from: dayFrom,
        to: now,
        maxDelta,
        allowPartial: true
      });
      return {
        delta: meter.delta,
        partial: meter.partial,
        estimated: false,
        rejected: meter.rejected
      };
    }
    if (!powerKey || !pick) {
      return { delta: null, partial: false, estimated: false, rejected: false };
    }
    const power = points.get(powerKey);
    if (!power) return { delta: null, partial: false, estimated: false, rejected: false };
    const scale = energyScale(power.scale);
    if (scale == null) return { delta: null, partial: false, estimated: false, rejected: false };
    const integrated = integrateWattsKwh({
      samples: input.series(power.ga),
      scale,
      from: dayFrom,
      to: now,
      pick,
      maxKwh: maxDelta
    });
    return {
      delta: integrated.kwh,
      partial: integrated.partial,
      estimated: integrated.kwh != null,
      rejected: integrated.rejected
    };
  };

  const imported = counter("importEnergyKwh", MAX_DAY_KWH, "gridPowerW", (w) => (w > 0 ? w : 0));
  const exported = counter("exportEnergyKwh", MAX_DAY_KWH, "gridPowerW", (w) => (w < 0 ? -w : 0));
  const solar = counter("solarEnergyKwh", MAX_DAY_KWH, "solarPowerW", (w) => (w > 0 ? w : 0));
  const gas = counter("gasM3", MAX_DAY_GAS_M3, null, null);
  day.todayImportKwh = imported.delta;
  day.todayExportKwh = exported.delta;
  day.todaySolarKwh = solar.delta;
  day.todayGasM3 = gas.delta;
  day.todayImportPartial = imported.partial;
  day.todayExportPartial = exported.partial;
  day.todaySolarPartial = solar.partial;
  day.todayGasPartial = gas.partial;
  day.todayImportEstimated = imported.estimated;
  day.todayExportEstimated = exported.estimated;
  day.todaySolarEstimated = solar.estimated;
  for (const [name, row] of [
    ["afname", imported],
    ["teruglevering", exported],
    ["pv", solar],
    ["gas", gas]
  ] as const) {
    if (row.rejected) day.rejectedTotals.push(name);
  }

  const prices = input.energy.prices;
  const pricesOn = prices?.enabled === true;
  day.priceStale = pricesOn && input.priceStale;
  if (!pricesOn) return day;

  const importTariff = tariffOf(prices?.importSurchargeEurPerKwh, prices?.importVat);
  const exportMode = prices?.exportMode;
  const exportTariff =
    exportMode === "market"
      ? tariffOf(prices?.exportSurchargeEurPerKwh, prices?.exportVat)
      : exportMode === "fixed"
        ? tariffOf(0, prices?.exportVat)
        : null;
  const exportFixed =
    exportMode === "fixed" &&
    typeof prices?.exportFixedEurPerKwh === "number" &&
    Number.isFinite(prices.exportFixedEurPerKwh)
      ? prices.exportFixedEurPerKwh
      : null;
  const gasTariff = tariffOf(prices?.gasSurchargeEurPerM3, prices?.gasVat);

  const quantity = (key: EnergyPointKey, maxHour: number) => {
    const point = points.get(key);
    if (!point) return () => null;
    const scale = energyScale(point.scale);
    if (scale == null) return () => null;
    const samples = input.series(point.ga);
    return (from: number, to: number) =>
      meterWindowDelta({
        samples,
        scale,
        from,
        to,
        maxDelta: maxHour,
        allowPartial: false
      }).delta;
  };

  const importQty = points.has("importEnergyKwh")
    ? quantity("importEnergyKwh", MAX_HOUR_KWH)
    : null;
  const exportQty = points.has("exportEnergyKwh")
    ? quantity("exportEnergyKwh", MAX_HOUR_KWH)
    : null;
  const gasQty = points.has("gasM3") ? quantity("gasM3", MAX_DAY_GAS_M3) : null;

  if (importQty) {
    const money = moneyFromSlots({
      slots: input.electricity,
      now,
      dayFrom,
      dayTill,
      tariff: importTariff,
      quantity: importQty
    });
    day.todayCostEur = money.completedEur;
    day.openHourImportEur = money.openEur;
  }
  if (exportQty && exportTariff && (exportMode !== "fixed" || exportFixed != null)) {
    const money = moneyFromSlots({
      slots: input.electricity,
      now,
      dayFrom,
      dayTill,
      tariff: exportTariff,
      fixedMarket: exportMode === "fixed" ? exportFixed : null,
      quantity: exportQty
    });
    day.todayFeedInEur = money.completedEur;
    day.openHourFeedInEur = money.openEur;
  }
  if (gasQty) {
    const money = moneyFromSlots({
      slots: input.gas,
      now,
      dayFrom,
      dayTill,
      tariff: gasTariff,
      quantity: gasQty
    });
    day.todayGasCostEur = money.completedEur;
    day.openHourGasEur = money.openEur;
  }
  if (day.todayCostEur != null || day.todayFeedInEur != null) {
    day.todayNetEur = round3((day.todayCostEur ?? 0) - (day.todayFeedInEur ?? 0));
  }

  const nowSlot = priceAt(input.electricity, now);
  const gasSlot = priceAt(input.gas, now);
  if (nowSlot) day.importPriceEurPerKwh = consumerPrice(nowSlot.market, importTariff);
  if (exportTariff && exportMode === "market" && nowSlot) {
    day.exportPriceEurPerKwh = consumerPrice(nowSlot.market, exportTariff);
  } else if (exportTariff && exportFixed != null) {
    day.exportPriceEurPerKwh = consumerPrice(exportFixed, exportTariff);
  }
  if (gasSlot) day.gasPriceEurPerM3 = consumerPrice(gasSlot.market, gasTariff);

  const gridW = input.gridPowerW;
  if (gridW != null && gridW > 30 && day.importPriceEurPerKwh != null) {
    day.tempoEurPerHour = round4((gridW / 1000) * day.importPriceEurPerKwh);
  } else if (gridW != null && gridW < -30 && day.exportPriceEurPerKwh != null) {
    day.tempoEurPerHour = round4((gridW / 1000) * day.exportPriceEurPerKwh);
  }

  const horizon = addLocalDays(new Date(now), 2, input.tz).getTime();
  day.priceHours = input.electricity
    .filter((slot) => slot.till > dayFrom && slot.from < horizon)
    .map((slot) => ({
      from: slot.from,
      till: slot.till,
      importEur: consumerPrice(slot.market, importTariff),
      exportEur:
        exportTariff == null
          ? null
          : exportMode === "fixed" && exportFixed != null
            ? consumerPrice(exportFixed, exportTariff)
            : exportMode === "market"
              ? consumerPrice(slot.market, exportTariff)
              : null
    }));
  return day;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

function round4(n: number): number {
  return Math.round(n * 10_000) / 10_000;
}
