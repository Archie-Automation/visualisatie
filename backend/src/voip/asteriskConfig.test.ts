import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { HouseConfig, IntercomDevice } from "../types";
import { buildDoorRingContext } from "./asteriskConfig";

const door = {
  id: "dev-ic-1",
  name: "Poort",
  intercom: { kind: "doorbird", sipExt: "900", sipPassword: "geheim", ringGroupId: "grp-1" }
} as unknown as IntercomDevice;

describe("buildDoorRingContext", () => {
  it("rings the panels even when the group has no SIP phones", () => {
    const cfg = {
      intercoms: [door],
      voip: { enabled: true, groups: [{ id: "grp-1", name: "Huis", ext: "901", memberIds: [] }], endpoints: [] }
    } as unknown as HouseConfig;
    const ctx = buildDoorRingContext(cfg, door) ?? "";
    assert.match(ctx, /\[ring-dev-ic-1\]/);
    assert.match(ctx, /UserEvent\(Archie,Kind: ring,IntercomId: dev-ic-1\)/);
    assert.doesNotMatch(ctx, /Dial\(/);
    assert.match(ctx, /exten => _X\.,1,Goto\(s,1\)/);
    assert.match(ctx, /exten => h,1,UserEvent\(Archie,Kind: cleared/);
  });

  it("dials the group members when there are phones", () => {
    const cfg = {
      intercoms: [door],
      voip: {
        enabled: true,
        groups: [{ id: "grp-1", name: "Huis", ext: "901", memberIds: ["ep-1"] }],
        endpoints: [{ id: "ep-1", ext: "201", name: "Paneel", password: "x", type: "panel" }]
      }
    } as unknown as HouseConfig;
    const ctx = buildDoorRingContext(cfg, door) ?? "";
    assert.match(ctx, /Dial\(PJSIP\/201,30/);
    assert.match(ctx, /GroupId: grp-1/);
  });
});
