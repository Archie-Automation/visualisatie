import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { rewriteHlsPlaylist } from "./hlsRewrite";

const client = "https://huis.archie-cloud.com";
const cam = "dev-cam-1";

describe("rewriteHlsPlaylist", () => {
  it("zet de master-regel om inclusief het id", () => {
    const body = [
      "#EXTM3U",
      '#EXT-X-STREAM-INF:BANDWIDTH=192000,CODECS="avc1.640029"',
      "hls/playlist.m3u8?id=4cr6nHHe"
    ].join("\n");
    const out = rewriteHlsPlaylist(
      body,
      cam,
      client,
      "http://127.0.0.1:1984/api/stream.m3u8?src=dev-cam-1"
    );
    assert.match(
      out,
      /https:\/\/huis\.archie-cloud\.com\/api\/cameras\/dev-cam-1\/hls-seg\/hls\/playlist\.m3u8\?id=4cr6nHHe$/m
    );
  });

  it("zet segmenten om relatief aan de media-playlist", () => {
    const body = [
      "#EXTM3U",
      "#EXTINF:0.500,",
      "segment.ts?id=4cr6nHHe&n=0"
    ].join("\n");
    const out = rewriteHlsPlaylist(
      body,
      cam,
      client,
      "http://127.0.0.1:1984/api/hls/playlist.m3u8?id=4cr6nHHe"
    );
    assert.match(
      out,
      /\/hls-seg\/hls\/segment\.ts\?id=4cr6nHHe&n=0$/m
    );
  });
});
