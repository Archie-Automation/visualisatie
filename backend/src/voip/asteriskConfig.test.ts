import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { HouseConfig, IntercomDevice } from "../types";
import { buildAsteriskFiles, buildDoorRingContext } from "./asteriskConfig";

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
    const answerAt = ctx.indexOf("Answer()");
    const dialAt = ctx.indexOf("Dial(");
    assert.ok(answerAt >= 0 && answerAt < dialAt);
    const monitorAt = ctx.indexOf("exten => 201,1,NoOp(Monitor 201)");
    const monitorAnswer = ctx.indexOf("Answer()", monitorAt);
    const monitorDial = ctx.indexOf("Dial(PJSIP/201,45,tT)");
    const catchAll = ctx.indexOf("exten => _X.,1,Goto(s,1)");
    assert.ok(monitorAt >= 0 && monitorAt < monitorAnswer);
    assert.ok(monitorAnswer < monitorDial && monitorDial < catchAll);
  });

  it("dials the door as pbx so the DoorBird accepts the invite", () => {
    const cfg = {
      intercoms: [door],
      voip: {
        enabled: true,
        host: "192.168.1.50",
        groups: [{ id: "grp-1", name: "Huis", ext: "901", memberIds: ["ep-1"] }],
        endpoints: [{ id: "ep-1", ext: "201", name: "Paneel", password: "x", type: "panel" }]
      }
    } as unknown as HouseConfig;
    const files = buildAsteriskFiles(cfg);
    assert.match(files["pjsip.conf"], /from_user=pbx/);
    assert.match(files["pjsip.conf"], /from_domain=192.168.1.50/);
    assert.match(files["extensions.conf"], /exten => 900,1,NoOp\(Bel deur 900\)/);
    assert.match(files["extensions.conf"], /Set\(CALLERID\(num\)=pbx\)/);
    assert.match(files["extensions.conf"], /Dial\(PJSIP\/900,45,r\)/);
  });
});
