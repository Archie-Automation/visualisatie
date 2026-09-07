import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { MediaPreset, MediaState } from "../types";
import {
  isRadioPlayback,
  matchPresetIndex,
  radioFavoriteRing,
  resolveMediaSkip,
  resolvePresetCycle
} from "./skipLogic";

const radios: MediaPreset[] = [
  { id: "NPO 1", name: "NPO 1", uri: "x-sonosapi-stream:s1234?sid=254" },
  { id: "NPO 2", name: "NPO 2", uri: "x-sonosapi-stream:s5678?sid=254" },
  { id: "3FM", name: "3FM", uri: "x-rincon-mp3radio://stream.example/3fm" }
];

const mixed: MediaPreset[] = [
  ...radios,
  { id: "Avond", name: "Avond", uri: "x-rincon-queue:RINCON_ABC" },
  { id: "Hits", name: "Hits", uri: "x-sonos-spotify:spotify:playlist:abc" }
];

function state(partial: Partial<MediaState>): MediaState {
  return {
    deviceId: "z",
    brand: "sonos",
    online: true,
    transport: "playing",
    presets: radios,
    ...partial
  };
}

describe("isRadioPlayback", () => {
  it("treats Sonos radio URIs as radio and Spotify/queue as tracks", () => {
    assert.equal(
      isRadioPlayback({ currentUri: "x-sonosapi-stream:s1234?sid=254" }),
      true
    );
    assert.equal(
      isRadioPlayback({ currentUri: "x-rincon-queue:RINCON_ABC#0" }),
      false
    );
    assert.equal(
      isRadioPlayback({ currentUri: "x-sonos-spotify:spotify:playlist:abc" }),
      false
    );
    assert.equal(isRadioPlayback({ source: "TuneIn" }), true);
  });
});

describe("radioFavoriteRing", () => {
  it("keeps only radio items when URIs exist, else the whole Bluesound list", () => {
    assert.equal(radioFavoriteRing(mixed).length, 3);
    assert.deepEqual(
      radioFavoriteRing([{ id: "1", name: "Slot 1" }, { id: "2", name: "Slot 2" }]).map(
        (p) => p.id
      ),
      ["1", "2"]
    );
  });
});

describe("matchPresetIndex", () => {
  it("matches session URIs by stripping query, ICY titles, and hint URIs", () => {
    assert.equal(
      matchPresetIndex(
        { currentUri: "x-sonosapi-stream:s1234?sid=254&sn=9" },
        radios
      ),
      0
    );
    assert.equal(
      matchPresetIndex({ title: "NPO 2 - Nieuws", source: "Radio" }, radios),
      1
    );
    assert.equal(
      matchPresetIndex({ currentUri: "hls://other" }, radios, radios[2]!.uri),
      2
    );
  });
});

describe("resolveMediaSkip", () => {
  it("skips tracks in a playlist / queue", () => {
    const r = resolveMediaSkip(
      state({
        currentUri: "x-rincon-queue:RINCON_ABC#0",
        source: "Wachtrij",
        presets: mixed
      }),
      1
    );
    assert.equal(r.kind, "track");
  });

  it("steps to the next radio favorite and wraps", () => {
    const next = resolveMediaSkip(
      state({ currentUri: radios[0]!.uri, source: "Radio" }),
      1
    );
    assert.equal(next.kind, "preset");
    if (next.kind === "preset") assert.equal(next.preset.id, "NPO 2");

    const wrap = resolveMediaSkip(
      state({ currentUri: radios[2]!.uri, source: "Radio" }),
      1
    );
    assert.equal(wrap.kind, "preset");
    if (wrap.kind === "preset") assert.equal(wrap.preset.id, "NPO 1");

    const prev = resolveMediaSkip(
      state({ currentUri: radios[0]!.uri, source: "Radio" }),
      -1
    );
    assert.equal(prev.kind, "preset");
    if (prev.kind === "preset") assert.equal(prev.preset.id, "3FM");
  });

  it("does not jump to a playlist favorite while radio is playing", () => {
    const r = resolveMediaSkip(
      state({ currentUri: radios[1]!.uri, source: "Radio", presets: mixed }),
      1
    );
    assert.equal(r.kind, "preset");
    if (r.kind === "preset") assert.equal(r.preset.id, "3FM");
  });
});

describe("resolvePresetCycle", () => {
  it("walks the full list including playlists and wraps", () => {
    const playing = state({
      currentUri: radios[1]!.uri,
      source: "Radio",
      presets: mixed
    });
    assert.equal(resolvePresetCycle(playing, 1)?.id, "3FM");
    assert.equal(resolvePresetCycle(playing, -1)?.id, "NPO 1");

    const last = state({
      currentUri: mixed[4]!.uri,
      source: "Spotify",
      presets: mixed
    });
    assert.equal(resolvePresetCycle(last, 1)?.id, "NPO 1");
    assert.equal(resolvePresetCycle(last, -1)?.id, "Avond");
  });

  it("starts at first/last when the current item is not in the list", () => {
    const unknown = state({
      currentUri: "spotify:track:xyz",
      source: "Spotify",
      presets: mixed
    });
    assert.equal(resolvePresetCycle(unknown, 1)?.id, "NPO 1");
    assert.equal(resolvePresetCycle(unknown, -1)?.id, "Hits");
  });

  it("returns null when there are no presets", () => {
    assert.equal(resolvePresetCycle(state({ presets: [] }), 1), null);
    assert.equal(resolvePresetCycle(undefined, 1), null);
  });
});
