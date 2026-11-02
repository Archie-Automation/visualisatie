import { parseEnergyZeroBody, type PriceSlot } from "./prices";

const ENDPOINT = "https://api.energyzero.nl/v1/energyprices";

/** 1 = electricity EUR/kWh, 3 = gas EUR/m³. Prices are requested excl. VAT. */
export async function fetchEnergyZeroPrices(input: {
  from: Date;
  till: Date;
  usageType: 1 | 3;
  fetchImpl?: typeof fetch;
}): Promise<PriceSlot[]> {
  const url = new URL(ENDPOINT);
  url.searchParams.set("fromDate", input.from.toISOString());
  url.searchParams.set("tillDate", input.till.toISOString());
  url.searchParams.set("interval", "4");
  url.searchParams.set("usageType", String(input.usageType));
  url.searchParams.set("inclBtw", "false");
  const fetchImpl = input.fetchImpl ?? fetch;
  const res = await fetchImpl(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) {
    throw new Error(`EnergyZero ${res.status}`);
  }
  const body: unknown = await res.json();
  const slots = parseEnergyZeroBody(body);
  if (slots.length === 0) throw new Error("EnergyZero gaf geen prijzen");
  return slots;
}
