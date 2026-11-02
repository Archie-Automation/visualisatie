/** Dutch household energy VAT. Applied only when the installer turns the flag on. */
export const NL_ENERGY_VAT = 0.21;

export const ENERGY_PRICE_ELECTRICITY = "energyzero:electricity";
export const ENERGY_PRICE_GAS = "energyzero:gas";

/** A house will not move this much in a day. Larger jumps are a reset or a bad decode. */
export const MAX_DAY_KWH = 5000;
export const MAX_HOUR_KWH = 400;
export const MAX_DAY_GAS_M3 = 200;

export interface PriceSlot {
  from: number;
  till: number;
  /** EnergyZero price with inclBtw=false. EUR/kWh or EUR/m³. */
  market: number;
}

export interface TariffSpec {
  surcharge: number;
  vat: boolean;
}

export function consumerPrice(market: number, spec: TariffSpec): number | null {
  if (!Number.isFinite(market)) return null;
  const surcharge = Number.isFinite(spec.surcharge) ? spec.surcharge : 0;
  const net = market + surcharge;
  const gross = spec.vat ? net * (1 + NL_ENERGY_VAT) : net;
  if (!Number.isFinite(gross)) return null;
  return round4(gross);
}

export function slotsFromReadings(
  readings: Array<{ at: number; price: number }>
): PriceSlot[] {
  const sorted = readings
    .filter((r) => Number.isFinite(r.at) && Number.isFinite(r.price))
    .sort((a, b) => a.at - b.at);
  const out: PriceSlot[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const from = sorted[i].at;
    const till = i + 1 < sorted.length ? sorted[i + 1].at : from + 3_600_000;
    if (till <= from) continue;
    out.push({ from, till, market: sorted[i].price });
  }
  return out;
}

export function parseEnergyZeroBody(body: unknown): PriceSlot[] {
  if (!body || typeof body !== "object") return [];
  const prices = (body as { Prices?: unknown }).Prices;
  if (!Array.isArray(prices)) return [];
  const readings: Array<{ at: number; price: number }> = [];
  for (const row of prices) {
    if (!row || typeof row !== "object") continue;
    const rec = row as { readingDate?: unknown; price?: unknown };
    const at = Date.parse(typeof rec.readingDate === "string" ? rec.readingDate : "");
    const price = rec.price;
    if (!Number.isFinite(at) || typeof price !== "number" || !Number.isFinite(price)) {
      continue;
    }
    readings.push({ at, price });
  }
  return slotsFromReadings(readings);
}

export interface HourMoney {
  /** Sum over hours that have already ended. Null when no hour had both a delta and a price. */
  completedEur: number | null;
  /** The hour that contains `now`. Labeled as an estimate by the UI. */
  openEur: number | null;
  /** True when a priced hour in the day had no usable meter delta. */
  partial: boolean;
}

/**
 * Completed hours only go into `completedEur`. The open hour is separate.
 * A missing delta is skipped, never written as 0 kWh.
 */
export function moneyFromSlots(input: {
  slots: PriceSlot[];
  now: number;
  dayFrom: number;
  dayTill: number;
  tariff: TariffSpec | null;
  /** Fixed price ignores the market number. Used for a feed-in fee. */
  fixedMarket?: number | null;
  quantity: (from: number, to: number) => number | null;
}): HourMoney {
  if (!input.tariff && input.fixedMarket == null) {
    return { completedEur: null, openEur: null, partial: false };
  }
  let completed = 0;
  let completedN = 0;
  let open = 0;
  let openN = 0;
  let partial = false;
  for (const slot of input.slots) {
    const from = Math.max(slot.from, input.dayFrom);
    const till = Math.min(slot.till, input.dayTill, input.now);
    if (till <= from) continue;
    const market = input.fixedMarket != null ? input.fixedMarket : slot.market;
    const price = input.tariff ? consumerPrice(market, input.tariff) : null;
    const qty = input.quantity(from, till);
    if (price == null || qty == null) {
      partial = true;
      continue;
    }
    const eur = qty * price;
    const isOpen = input.now < slot.till && input.now < input.dayTill;
    if (isOpen) {
      open += eur;
      openN += 1;
    } else {
      completed += eur;
      completedN += 1;
    }
  }
  return {
    completedEur: completedN > 0 ? round4(completed) : null,
    openEur: openN > 0 ? round4(open) : null,
    partial
  };
}

function round4(n: number): number {
  return Math.round(n * 10_000) / 10_000;
}
