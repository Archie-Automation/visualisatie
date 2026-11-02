import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { LogStore } from "../logStore";
import { buildEnergyDay, meterWindowDelta } from "./day";
import { startOfLocalDay } from "./localDay";
import { parseEnergyZeroBody, slotsFromReadings } from "./prices";
import type { HouseEnergyConfig } from "../types";

const tz = "Europe/Amsterdam";

test("local midnight in November is CET, not UTC", () => {
  const noon = new Date("2026-11-02T12:00:00.000Z");
  const midnight = startOfLocalDay(noon, tz);
  assert.equal(midnight.toISOString(), "2026-11-01T23:00:00.000Z");
});

test("meter delta is the stand now minus the stand at midnight", () => {
  const from = Date.parse("2026-11-01T23:00:00.000Z");
  const to = from + 2 * 3_600_000;
  const delta = meterWindowDelta({
    samples: [
      { ts: from - 3_600_000, value: 100 },
      { ts: from + 3_600_000, value: 101.5 }
    ],
    scale: 1,
    from,
    to,
    maxDelta: 5000,
    allowPartial: true
  });
  assert.equal(delta.delta, 1.5);
  assert.equal(delta.partial, false);
  assert.equal(delta.rejected, false);
});

test("a counter that runs backwards is dropped, not clamped to zero", () => {
  const from = 1_000_000;
  const delta = meterWindowDelta({
    samples: [
      { ts: from - 1, value: 50 },
      { ts: from + 10, value: 40 }
    ],
    scale: 1,
    from,
    to: from + 20,
    maxDelta: 5000,
    allowPartial: true
  });
  assert.equal(delta.delta, null);
  assert.equal(delta.rejected, true);
});

test("without a midnight sample the day total is partial", () => {
  const from = 5_000_000;
  const delta = meterWindowDelta({
    samples: [
      { ts: from + 1_000, value: 10 },
      { ts: from + 5_000, value: 12 }
    ],
    scale: 1,
    from,
    to: from + 5_000,
    maxDelta: 5000,
    allowPartial: true
  });
  assert.equal(delta.delta, 2);
  assert.equal(delta.partial, true);
});

test("import price is market plus surcharge plus VAT, export stays its own tariff", () => {
  const from = Date.parse("2026-11-01T23:00:00.000Z");
  const hour = 3_600_000;
  const now = from + hour + 30 * 60_000;
  const samples = [
    { ts: from - 1, value: 10 },
    { ts: from + hour, value: 12 }
  ];
  const energy: HouseEnergyConfig = {
    enabled: true,
    prices: {
      enabled: true,
      importSurchargeEurPerKwh: 0.02,
      importVat: true,
      exportMode: "fixed",
      exportFixedEurPerKwh: 0.05
    },
    knx: {
      importEnergyKwh: { ga: "1/1/10", dpt: "float4" },
      exportEnergyKwh: { ga: "1/1/11", dpt: "float4" }
    }
  };
  const electricity = slotsFromReadings([
    { at: from, price: 0.1 },
    { at: from + hour, price: 0.2 }
  ]);
  const day = buildEnergyDay({
    energy,
    now,
    tz,
    gridPowerW: 2000,
    series: (ga) => (ga === "1/1/10" || ga === "1/1/11" ? samples : []),
    electricity,
    gas: [],
    priceStale: false
  });
  // Completed hour: 2 kWh * (0.10 + 0.02) * 1.21 = 0.2904
  assert.equal(day.todayCostEur, 0.2904);
  assert.equal(day.importPriceEurPerKwh, 0.2662);
  assert.equal(day.exportPriceEurPerKwh, 0.05);
  assert.notEqual(day.exportPriceEurPerKwh, day.importPriceEurPerKwh);
  // Open hour has no further meter movement, so the estimate is 0.
  assert.equal(day.openHourImportEur, 0);
  // Export meter moved too, paid at the fixed fee, not the import tariff.
  assert.equal(day.todayFeedInEur, 0.1);
  assert.equal(day.tempoEurPerHour, 0.5324);
});

test("without an export tariff, feed-in money stays empty", () => {
  const from = Date.parse("2026-11-01T23:00:00.000Z");
  const energy: HouseEnergyConfig = {
    enabled: true,
    prices: { enabled: true, importVat: false },
    knx: {
      importEnergyKwh: { ga: "1/1/10", dpt: "float4" },
      exportEnergyKwh: { ga: "1/1/11", dpt: "float4" }
    }
  };
  const day = buildEnergyDay({
    energy,
    now: from + 3_600_000,
    tz,
    gridPowerW: -1500,
    series: () => [
      { ts: from - 1, value: 0 },
      { ts: from + 3_600_000, value: 3 }
    ],
    electricity: slotsFromReadings([{ at: from, price: 0.2 }]),
    gas: [],
    priceStale: true
  });
  assert.equal(day.todayCostEur, 0.6);
  assert.equal(day.todayFeedInEur, null);
  assert.equal(day.exportPriceEurPerKwh, null);
  assert.equal(day.priceStale, true);
  assert.equal(day.todayNetEur, 0.6);
});

test("missing meter falls back to a held power integral and is marked as an estimate", () => {
  const from = Date.parse("2026-11-01T23:00:00.000Z");
  const energy: HouseEnergyConfig = {
    enabled: true,
    knx: { gridPowerW: { ga: "1/1/1", dpt: "float4" } }
  };
  const day = buildEnergyDay({
    energy,
    now: from + 2 * 3_600_000,
    tz,
    gridPowerW: 0,
    series: () => [
      { ts: from - 1, value: 1000 },
      { ts: from + 3_600_000, value: 0 }
    ],
    electricity: [],
    gas: [],
    priceStale: false
  });
  assert.equal(day.todayImportKwh, 1);
  assert.equal(day.todayImportEstimated, true);
  assert.equal(day.todayExportKwh, 0);
  assert.equal(day.todayCostEur, null);
});

test("EnergyZero hours keep a repeated price", () => {
  const slots = parseEnergyZeroBody({
    Prices: [
      { readingDate: "2026-11-02T00:00:00Z", price: 1.03 },
      { readingDate: "2026-11-02T01:00:00Z", price: 1.03 }
    ]
  });
  assert.equal(slots.length, 2);
  assert.equal(slots[0].market, 1.03);
  assert.equal(slots[1].market, 1.03);
  assert.equal(slots[0].till, Date.parse("2026-11-02T01:00:00Z"));
});

test("equal hourly prices are both stored", () => {
  const file = path.join(os.tmpdir(), `energy-prices-${Date.now()}-${Math.random()}.db`);
  const store = new LogStore(file);
  try {
    store.putAt("energyzero:gas", 0, 1.03);
    store.putAt("energyzero:gas", 3_600_000, 1.03);
    const rows = store.series("energyzero:gas", 0, 3_600_000);
    assert.equal(rows.length, 2);
    assert.equal(rows[0].value, 1.03);
    assert.equal(rows[1].value, 1.03);
  } finally {
    store.close();
    fs.rmSync(file, { force: true });
    fs.rmSync(`${file}-wal`, { force: true });
    fs.rmSync(`${file}-shm`, { force: true });
  }
});
