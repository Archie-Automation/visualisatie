import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  climateBusRole,
  decodeShift6,
  encodeShift6,
  setpointControlOf,
  setpointLimits,
  setpointWriteRole
} from "./climateSetpoint";
import type { ClimateDevice } from "./types";

function climate(partial?: ClimateDevice["climate"]): ClimateDevice {
  return {
    id: "t",
    name: "Woonkamer",
    type: "climate",
    ga: { actual_temp: "1/1/1", setpoint: "1/1/2" },
    climate: partial
  };
}

describe("setpoint shift encoding", () => {
  it("maps 0.1 K steps onto a signed byte", () => {
    assert.equal(encodeShift6(0), 0);
    assert.equal(encodeShift6(1.5), 15);
    assert.equal(encodeShift6(-0.5), -5);
    assert.equal(encodeShift6(12.74), 127);
    assert.equal(encodeShift6(-12.84), -128);
    assert.equal(decodeShift6(15), 1.5);
    assert.equal(decodeShift6(-5), -0.5);
    assert.equal(decodeShift6(encodeShift6(1.54)), 1.5);
  });
});

describe("setpoint control", () => {
  it("defaults to absolute DPT 9.001", () => {
    const d = climate();
    assert.equal(setpointControlOf(d), "absolute");
    assert.equal(setpointWriteRole(setpointControlOf(d)), "setpoint");
    assert.equal(climateBusRole(d, "setpoint_status"), "setpoint_status");
    assert.deepEqual(setpointLimits(d), { min: 5, max: 35 });
  });

  it("selects DPT 6.010 or 9.002 and keeps other GA roles", () => {
    const six = climate({ setpointControl: "relative_6.010" });
    assert.equal(climateBusRole(six, "setpoint"), "setpoint_shift_6");
    assert.equal(climateBusRole(six, "setpoint_status"), "setpoint_shift_6_status");
    assert.equal(climateBusRole(six, "actual_temp"), "actual_temp");
    assert.deepEqual(setpointLimits(six), { min: -5, max: 5 });

    const nine = climate({ setpointControl: "relative_9.002", minTemp: -2, maxTemp: 3 });
    assert.equal(setpointWriteRole(setpointControlOf(nine)), "setpoint_shift_9");
    assert.deepEqual(setpointLimits(nine), { min: -2, max: 3 });
  });

  it("clamps DPT 6.010 to the bus range", () => {
    const d = climate({
      setpointControl: "relative_6.010",
      minTemp: -20,
      maxTemp: 20
    });
    assert.deepEqual(setpointLimits(d), { min: -12.8, max: 12.7 });
  });
});
