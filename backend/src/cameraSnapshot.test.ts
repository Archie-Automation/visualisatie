import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SNAP_FREEZE_COOLDOWN_MS,
  SNAP_FREEZE_MS,
  classifyFrozenSnapshot,
  noteSnapshotFrame
} from "./cameraSnapshot";

describe("snapshot freeze", () => {
  it("wacht tot hetzelfde beeld lang genoeg stilstaat", () => {
    const t0 = 1_000_000;
    let noted = noteSnapshotFrame(undefined, "aaa", t0);
    assert.equal(noted.probe, false);

    noted = noteSnapshotFrame(noted.state, "aaa", t0 + 30_000);
    assert.equal(noted.probe, false);

    noted = noteSnapshotFrame(noted.state, "aaa", t0 + SNAP_FREEZE_MS);
    assert.equal(noted.probe, true);
    assert.equal(noted.state.kickedAt, t0 + SNAP_FREEZE_MS);
  });

  it("begint opnieuw als het beeld verandert", () => {
    const t0 = 1_000_000;
    let noted = noteSnapshotFrame(undefined, "aaa", t0);
    noted = noteSnapshotFrame(noted.state, "aaa", t0 + 30_000);
    noted = noteSnapshotFrame(noted.state, "bbb", t0 + SNAP_FREEZE_MS);
    assert.equal(noted.probe, false);
    assert.equal(noted.state.hits, 1);
  });

  it("probeert niet opnieuw binnen de cooldown", () => {
    const t0 = 1_000_000;
    let noted = noteSnapshotFrame(undefined, "aaa", t0);
    noted = noteSnapshotFrame(noted.state, "aaa", t0 + 30_000);
    noted = noteSnapshotFrame(noted.state, "aaa", t0 + SNAP_FREEZE_MS);
    assert.equal(noted.probe, true);

    noted = noteSnapshotFrame(
      noted.state,
      "aaa",
      t0 + SNAP_FREEZE_MS + SNAP_FREEZE_COOLDOWN_MS - 1
    );
    assert.equal(noted.probe, false);
  });

  it("een ander direct frame is een vastgelopen go2rtc-sessie", () => {
    assert.equal(classifyFrozenSnapshot("live", "stuck"), "stale-session");
    assert.equal(classifyFrozenSnapshot("stuck", "stuck"), "source-frozen");
    assert.equal(classifyFrozenSnapshot(null, "stuck"), "direct-failed");
  });
});
