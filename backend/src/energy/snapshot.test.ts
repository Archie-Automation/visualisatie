import assert from "node:assert/strict";
import test from "node:test";
import type { HouseEnergyConfig } from "../types";
import { buildEnergySnapshot } from "./snapshot";

const base: HouseEnergyConfig = {
  enabled: true,
  knx: {
    gridPowerW: { ga: "1/1/1", dpt: "float4" },
    solarPowerW: { ga: "1/1/2", dpt: "float4" },
    batteryPowerW: { ga: "1/1/3", dpt: "float4" }
  }
};

test("disabled energy publishes no numbers", () => {
  const snap = buildEnergySnapshot({
    energy: { enabled: false, knx: base.knx },
    values: { "1/1/1": 500 },
    busConnected: false
  });
  assert.equal(snap.enabled, false);
  assert.equal(snap.stale, false);
  assert.equal(snap.gridPowerW, null);
  assert.equal(snap.housePowerW, null);
});

test("a configured point without a telegram stays null and blocks house load", () => {
  const snap = buildEnergySnapshot({
    energy: base,
    values: { "1/1/1": 500, "1/1/3": 0 },
    busConnected: true
  });
  assert.equal(snap.gridPowerW, 500);
  assert.equal(snap.solarPowerW, null);
  assert.equal(snap.batteryPowerW, 0);
  assert.equal(snap.housePowerW, null);
  assert.equal(snap.stale, false);
});

test("unconfigured solar is left out of the sum", () => {
  const snap = buildEnergySnapshot({
    energy: {
      enabled: true,
      knx: { gridPowerW: { ga: "1/1/1", dpt: "float4" } }
    },
    values: { "1/1/1": 500 },
    busConnected: true
  });
  assert.equal(snap.housePowerW, 500);
  assert.equal(snap.solarPowerW, null);
});

test("house load follows grid + solar + battery, including real zero", () => {
  const snap = buildEnergySnapshot({
    energy: base,
    values: { "1/1/1": -2000, "1/1/2": 3000, "1/1/3": 0 },
    busConnected: true
  });
  assert.equal(snap.gridPowerW, -2000);
  assert.equal(snap.solarPowerW, 3000);
  assert.equal(snap.batteryPowerW, 0);
  assert.equal(snap.housePowerW, 1000);
});

test("scale converts kW to W and can invert sign", () => {
  const snap = buildEnergySnapshot({
    energy: {
      enabled: true,
      knx: {
        gridPowerW: { ga: "1/1/1", dpt: "float2", scale: 1000 },
        batteryPowerW: { ga: "1/1/3", dpt: "int16", scale: -1 }
      }
    },
    values: { "1/1/1": 1.2, "1/1/3": 400 },
    busConnected: true
  });
  assert.equal(snap.gridPowerW, 1200);
  assert.equal(snap.batteryPowerW, -400);
  assert.equal(snap.housePowerW, 800);
});

test("non-numeric and zero scale do not become 0 W", () => {
  const boolSnap = buildEnergySnapshot({
    energy: base,
    values: { "1/1/1": true, "1/1/2": 1000, "1/1/3": 0 },
    busConnected: true
  });
  assert.equal(boolSnap.gridPowerW, null);
  assert.equal(boolSnap.housePowerW, null);

  const zeroScale = buildEnergySnapshot({
    energy: {
      enabled: true,
      knx: { gridPowerW: { ga: "1/1/1", dpt: "float4", scale: 0 } }
    },
    values: { "1/1/1": 500 },
    busConnected: true
  });
  assert.equal(zeroScale.gridPowerW, null);
  assert.equal(zeroScale.housePowerW, null);
});

test("disconnect keeps the last numbers and marks them stale", () => {
  const snap = buildEnergySnapshot({
    energy: base,
    values: { "1/1/1": 500, "1/1/2": 100, "1/1/3": -50 },
    busConnected: false
  });
  assert.equal(snap.stale, true);
  assert.equal(snap.gridPowerW, 500);
  assert.equal(snap.housePowerW, 550);
});
