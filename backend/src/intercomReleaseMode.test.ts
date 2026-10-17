import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { IntercomDevice } from "./types";
import {
  effectiveIntercomReleaseMode,
  intercomSupportsRelease
} from "./intercomReleaseMode";

function ic(intercom: IntercomDevice["intercom"]): IntercomDevice {
  return {
    id: "dev-ic",
    name: "Voordeur",
    type: "intercom",
    intercom
  };
}

describe("effectiveIntercomReleaseMode", () => {
  it("negeert default knx zonder GA en valt terug op SIP-DTMF", () => {
    const d = ic({
      rtsp: "rtsp://x",
      releaseMode: "knx",
      sipExt: "900",
      sipPassword: "x"
    });
    assert.equal(effectiveIntercomReleaseMode(d), "dtmf");
    assert.equal(intercomSupportsRelease(d), true);
  });

  it("houdt knx aan als er een GA is", () => {
    const d = ic({
      rtsp: "rtsp://x",
      releaseMode: "knx",
      release: { ga: "1/2/3" },
      sipExt: "900"
    });
    assert.equal(effectiveIntercomReleaseMode(d), "knx");
    assert.equal(intercomSupportsRelease(d), true);
  });

  it("zonder GA en zonder SIP: geen deuropen", () => {
    const d = ic({ rtsp: "rtsp://x", releaseMode: "knx" });
    assert.equal(effectiveIntercomReleaseMode(d), "knx");
    assert.equal(intercomSupportsRelease(d), false);
  });

  it("haalt DoorBird-HTTP uit de RTSP-URL als het deurblok leeg is", () => {
    const d = ic({
      kind: "doorbird",
      rtsp: "rtsp://apiuser:s3cret@192.168.1.172:554/mpeg/media.amp",
      releaseMode: "knx",
      sipExt: "900"
    });
    assert.equal(effectiveIntercomReleaseMode(d), "doorbird");
    assert.equal(intercomSupportsRelease(d), true);
  });
});
