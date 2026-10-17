import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { HouseConfig } from "../types";
import { hasConfiguredSipIntercom, normalizeVoip } from "./normalize";

function house(intercom?: { sipExt?: string; sipPassword?: string }): HouseConfig {
  return {
    project: { id: "p", name: "Huis" },
    floors: [],
    intercoms: intercom
      ? [
          {
            id: "dev-poort",
            name: "Poort",
            type: "intercom",
            intercom: {
              rtsp: "rtsp://192.168.1.172/mpeg/media.amp",
              ...intercom
            }
          }
        ]
      : []
  };
}

describe("normalizeVoip SIP intercom", () => {
  it("turns VoIP on when a door station has a SIP login", () => {
    const cfg = house({ sipExt: "900", sipPassword: "geheim" });
    assert.equal(hasConfiguredSipIntercom(cfg), true);
    normalizeVoip(cfg);
    assert.equal(cfg.voip?.enabled, true);
    assert.ok(cfg.voip?.amiSecret);
  });

  it("leaves VoIP off without a SIP password", () => {
    const cfg = house({ sipExt: "900" });
    normalizeVoip(cfg);
    assert.equal(cfg.voip?.enabled, false);
  });
});
