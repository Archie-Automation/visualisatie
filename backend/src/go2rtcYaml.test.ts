import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildGo2rtcYaml } from "./cameras";
import type { CameraDevice } from "./types";

function cam(id: string, rtsp: string): CameraDevice {
  return {
    id,
    name: id,
    type: "camera",
    camera: { rtsp, go2rtcVideoOnly: true }
  };
}

describe("go2rtc yaml", () => {
  it("houdt elke stream open via preload", () => {
    const yaml = buildGo2rtcYaml(
      [cam("tuin", "rtsp://user:pw@192.168.1.40:554/stream1")],
      [],
      null
    );
    assert.match(yaml, /^ {2}tuin: /m);
    assert.match(yaml, /^preload:\n {2}tuin: ""$/m);
  });
});
