import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { HouseConfig, SonosDevice } from "../types";
import {
  asGaList,
  buildMediaKnxIndex,
  decodeDimControl,
  isRisingEdge,
  nextVolume,
  playPauseToggleAction,
  resolveVolumeTarget
} from "./knxBridge";

describe("isRisingEdge", () => {
  it("fires only on 0→1 / false→true", () => {
    assert.equal(isRisingEdge(false, true), true);
    assert.equal(isRisingEdge(0, 1), true);
    assert.equal(isRisingEdge(undefined, 1), true);
    assert.equal(isRisingEdge("0", "1"), true);
    assert.equal(isRisingEdge(true, true), false);
    assert.equal(isRisingEdge(1, 0), false);
    assert.equal(isRisingEdge(0, 0), false);
    assert.equal(isRisingEdge(true, false), false);
  });
});

describe("playPauseToggleAction", () => {
  it("toggles from current transport so a 1-then-0 rocker does not pause immediately", () => {
    assert.equal(playPauseToggleAction(false), "play");
    assert.equal(playPauseToggleAction(true), "pause");
  });
});

describe("decodeDimControl", () => {
  it("treats step 0 as stop regardless of direction", () => {
    assert.deepEqual(decodeDimControl(0), { stop: true });
    assert.deepEqual(decodeDimControl(8), { stop: true });
    assert.deepEqual(decodeDimControl({ decr_incr: 1, data: 0 }), { stop: true });
    assert.deepEqual(decodeDimControl({ decr_incr: 0, data: 0 }), { stop: true });
  });

  it("decodes nibble and knx.js object as start up/down", () => {
    assert.deepEqual(decodeDimControl(9), { stop: false, increase: true, step: 1 });
    assert.deepEqual(decodeDimControl(1), { stop: false, increase: false, step: 1 });
    assert.deepEqual(decodeDimControl({ decr_incr: 1, data: 1 }), {
      stop: false,
      increase: true,
      step: 1
    });
    assert.deepEqual(decodeDimControl({ decr_incr: 0, data: 7 }), {
      stop: false,
      increase: false,
      step: 7
    });
  });

  it("ignores booleans (those are play/pause bits)", () => {
    assert.equal(decodeDimControl(true), null);
    assert.equal(decodeDimControl(false), null);
  });
});

describe("nextVolume", () => {
  it("steps 5% and clamps 0–100", () => {
    assert.equal(nextVolume(40, true), 45);
    assert.equal(nextVolume(40, false), 35);
    assert.equal(nextVolume(98, true), 100);
    assert.equal(nextVolume(2, false), 0);
    assert.equal(nextVolume(undefined, true), 5);
  });
});

describe("resolveVolumeTarget", () => {
  it("moves only the zone when the group switch is off", () => {
    const r = resolveVolumeTarget({
      zoneVolume: 20,
      groupVolume: 80,
      increase: true,
      volumeAffectsGroup: false,
      grouped: true
    });
    assert.equal(r.kind, "zone");
    assert.equal(r.next, 25);
  });

  it("scales the group only when grouped and the switch is on", () => {
    const grouped = resolveVolumeTarget({
      zoneVolume: 20,
      groupVolume: 80,
      increase: false,
      volumeAffectsGroup: true,
      grouped: true
    });
    assert.equal(grouped.kind, "group");
    assert.equal(grouped.next, 75);

    const standalone = resolveVolumeTarget({
      zoneVolume: 20,
      groupVolume: 80,
      increase: true,
      volumeAffectsGroup: true,
      grouped: false
    });
    assert.equal(standalone.kind, "zone");
    assert.equal(standalone.next, 25);
  });
});

describe("buildMediaKnxIndex", () => {
  it("indexes every listed GA and can attach one GA to multiple players", () => {
    const sonos = (id: string, knx: SonosDevice["knx"]): SonosDevice => ({
      id,
      name: id,
      type: "media_sonos",
      sonos: { host: "127.0.0.1" },
      knx
    });
    const cfg = {
      project: { id: "p", name: "t" },
      floors: [
        {
          id: "f",
          name: "F",
          rooms: [
            {
              id: "r",
              name: "R",
              devices: [
                sonos("a", {
                  playPause: ["1/1/1", ""],
                  volumeDim: ["1/1/2"],
                  next: ["1/1/3"],
                  previous: ["1/1/4"]
                }),
                sonos("b", {
                  playPause: ["1/1/1"],
                  volumeAffectsGroup: true
                })
              ]
            }
          ]
        }
      ]
    } as HouseConfig;

    const idx = buildMediaKnxIndex(cfg);
    assert.equal(idx.get("1/1/1")?.length, 2);
    assert.equal(idx.get("1/1/1")?.[0].deviceId, "a");
    assert.equal(idx.get("1/1/1")?.[1].volumeAffectsGroup, true);
    assert.equal(idx.get("1/1/2")?.[0].action, "volumeDim");
    assert.equal(idx.has(""), false);
  });

  it("accepts a single GA string instead of an array", () => {
    assert.deepEqual(asGaList("3/1/2"), ["3/1/2"]);
    assert.deepEqual(asGaList([" 3/1/2 ", ""]), ["3/1/2"]);
  });
});
