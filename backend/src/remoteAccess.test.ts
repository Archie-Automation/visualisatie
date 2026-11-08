import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import { extraGo2rtcCandidates } from "./remoteAccess";

const keys = ["WG_ADDRESS", "TURN_HOST", "GO2RTC_RELAY_CANDIDATE"] as const;
const saved: Partial<Record<(typeof keys)[number], string>> = {};
for (const key of keys) {
  const value = process.env[key];
  if (value !== undefined) saved[key] = value;
}

afterEach(() => {
  for (const key of keys) {
    const value = saved[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

describe("extraGo2rtcCandidates", () => {
  it("adverteert geen publieke turn:8555", () => {
    process.env.WG_ADDRESS = "10.80.0.2";
    process.env.TURN_HOST = "turn.example";
    delete process.env.GO2RTC_RELAY_CANDIDATE;
    assert.deepEqual(extraGo2rtcCandidates(), ["10.80.0.2:8555"]);
  });

  it("neemt een expliciete relay-candidate wel mee", () => {
    process.env.WG_ADDRESS = "10.80.4.8/32";
    process.env.TURN_HOST = "turn.example";
    process.env.GO2RTC_RELAY_CANDIDATE = "203.0.113.10:40012";
    assert.deepEqual(extraGo2rtcCandidates(), [
      "10.80.4.8:8555",
      "203.0.113.10:40012"
    ]);
  });

  it("is leeg zonder WireGuard en zonder relay", () => {
    delete process.env.WG_ADDRESS;
    delete process.env.TURN_HOST;
    delete process.env.GO2RTC_RELAY_CANDIDATE;
    assert.deepEqual(extraGo2rtcCandidates(), []);
  });
});
