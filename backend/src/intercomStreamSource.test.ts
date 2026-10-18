import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { IntercomDevice } from "./types";
import { intercomGo2rtcSources, intercomPublicAspect } from "./cameras";

function ic(intercom: IntercomDevice["intercom"]): IntercomDevice {
  return {
    id: "dev-ic",
    name: "Voordeur",
    type: "intercom",
    intercom
  };
}

describe("intercomGo2rtcSources", () => {
  it("passes DoorBird H.264 through without a transcode", () => {
    const d = ic({
      rtsp: "rtsp://192.168.1.102/live#backchannel=1",
      kind: "doorbird"
    });
    assert.deepEqual(intercomGo2rtcSources(d, "/usr/bin/ffmpeg"), [
      "rtsp://192.168.1.102/live#media=video"
    ]);
  });

  it("drops backchannel when ffmpeg is missing", () => {
    const d = ic({ rtsp: "rtsp://192.168.1.102/live", kind: "doorbird" });
    assert.deepEqual(intercomGo2rtcSources(d, null), [
      "rtsp://192.168.1.102/live#media=video"
    ]);
  });

  it("keeps ONVIF backchannel for other intercoms", () => {
    const d = ic({ rtsp: "rtsp://192.168.1.50/stream", kind: "twoN" });
    assert.deepEqual(intercomGo2rtcSources(d, "/usr/bin/ffmpeg"), [
      "rtsp://192.168.1.50/stream#backchannel=1"
    ]);
  });
});

describe("intercomPublicAspect", () => {
  it("defaults a DoorBird to 16:9 and keeps an explicit aspect", () => {
    assert.equal(
      intercomPublicAspect(ic({ rtsp: "rtsp://x", kind: "doorbird" })),
      "16:9"
    );
    assert.equal(
      intercomPublicAspect(
        ic({ rtsp: "rtsp://x", kind: "doorbird", aspect: "4:3" })
      ),
      "4:3"
    );
    assert.equal(
      intercomPublicAspect(ic({ rtsp: "rtsp://x", kind: "twoN" })),
      "4:3"
    );
  });
});
