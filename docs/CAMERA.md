# Cameras (view-only)

Cameras in this system are **passive surveillance devices**. They never have a microphone uplink and the backend actively rejects any SDP offer that tries to enable one on the `/cameras/:id/webrtc` endpoint. Anything with a speak-back function belongs to the [intercom](./INTERCOM.md) flow.

```
 IP Camera / NVR  ─RTSP─►  go2rtc  ─┬─ WebRTC    (ultra-low-latency live, preferred)
                                    ├─ HLS       (fallback via backend proxy)
                                    └─ JPEG      (dashboard thumbnails, direct ffmpeg)
```

## Source profiles (automatic)

The backend detects a **source profile** from the RTSP URL and applies sensible live defaults. Manual flags in `house.json` override the profile when set.

| Profile | Typical URL | Live defaults |
|---|---|---|
| `synology_ss` | `rtsp://…/Sms=7.unicast` (Synology Surveillance Station share path) | FFmpeg transcode to H.264, short GOP, video-only |
| `nvr_recorder` | Generic NVR / recorder RTSP (Dahua, Hikvision, Reolink hub, …) | FFmpeg + H.264 when needed, video-only |
| `direct_camera` | Direct IP camera RTSP | Native passthrough when possible; FFmpeg only if forced |

Detection runs on every backend start and when go2rtc YAML is regenerated. You normally do **not** need `go2rtcFfmpeg` or `go2rtcVideoOnly` in config — leave them unset and let the profile decide.

## Declaring a camera

```json
{
  "id": "dev-hall-cam-garden",
  "type": "camera",
  "name": "Tuin",
  "camera": {
    "rtsp": "rtsp://user:pass@192.168.1.51:554/stream1",
    "previewRtsp": "rtsp://user:pass@192.168.1.51:554/stream2",
    "path": "garden",
    "aspect": "16:9"
  }
}
```

Fields:

| field | effect |
|---|---|
| `rtsp` | Main stream URL for **live** (WebRTC/HLS). Never shipped to clients. |
| `previewRtsp` | Optional sub-stream for **thumbnails only** (lower resolution, less CPU). Snapshots use this when set; live stays on `rtsp`. |
| `path` | Stable stream name. Derived from `id` if omitted. |
| `aspect` | Tile aspect ratio hint. |
| `codec` | Force a codec for go2rtc's transcoder. Set to `h264` for iOS compatibility. |
| `republish` | Set `false` to skip go2rtc entirely (direct HLS only). |
| `directHls` | Alternative: point at a camera/NVR that already speaks HLS. |
| `sources` | Extra source URLs used as fall-backs / substreams. |
| `go2rtcFfmpeg` | **Manual override:** force FFmpeg transcode for live (overrides profile). |
| `go2rtcVideoOnly` | **Manual override:** strip audio on the RTSP source (`#video=only`). |
| `go2rtcBackchannel0` | Disable RTSP backchannel (`#backchannel=0`) on glitchy NVR two-way-audio. |

### Synology Surveillance Station

Use the SS share-path RTSP URL as `rtsp`:

```
rtsp://user:pass@192.168.1.22:554/Sms=7.unicast
```

Recommended SS settings for smooth tablet live:

- Main stream: **H.264**, 1080p or 720p, **15–20 fps**, **GOP / I-frame interval 15–30** (1 s at 15 fps).
- Sub-stream (optional `previewRtsp`): **640×360 or 704×576**, H.264, 5–10 fps — used only for dashboard tiles.
- Enable RTSP on the SS server; avoid HTTPS-only or WebRTC-only camera paths for this integration.

If live stutters after SS changes, restart the backend so go2rtc YAML is regenerated with the new profile.

### Dual-stream (main + preview)

Many cameras and NVRs expose a high-res main stream and a low-res sub-stream:

```json
"camera": {
  "rtsp": "rtsp://cam/main",
  "previewRtsp": "rtsp://cam/sub"
}
```

- **Live** always uses `rtsp` (via go2rtc → WebRTC/HLS).
- **Snapshots** prefer `previewRtsp` when present (scaled to ~640 px width, cached).
- Reduces ffmpeg load on the server and speeds up tile refresh.

## API

- `GET /api/cameras`, `GET /api/cameras/:id` — list/view (credentials scrubbed)
- `GET /api/cameras/:id/snapshot` — JWT-guarded JPEG (direct ffmpeg, stale-while-revalidate cache)
- `GET /api/cameras/:id/hls.m3u8` — HLS playlist proxied through backend (for clients that cannot reach go2rtc)
- `POST /api/cameras/:id/webrtc` — SDP offer → answer, **video receive-only**. Offers with send-capable audio are rejected with 403.
- `POST /api/installer/camera-probe` — stream test (installer auth). Body: `{ "rtsp": "…", "previewRtsp": "…?" }`. Returns latency, JPEG dimensions, and profile recommendation.

### Camera probe (installer)

Use during setup to verify RTSP URLs before saving `house.json`:

```json
POST /api/installer/camera-probe
{
  "rtsp": "rtsp://user:pass@192.168.1.22:554/Sms=7.unicast",
  "previewRtsp": "rtsp://user:pass@192.168.1.22:554/Sms=8.unicast"
}
```

Response includes per-URL: reachable, latency ms, snapshot width/height, detected profile, and suggested flags.

## UI behaviour

- `CameraTile` in a room shows a crossfading JPEG snapshot every few seconds (cheap, always works).
- Tapping opens the `/camera/:id` fullscreen view: **WebRTC first**, HLS fallback via backend proxy.
- Audio is always receive-only; there is no "talk" control on a camera.
- Installer house editor: RTSP fields, optional preview stream, **Stream test** panel calling the probe API.

## iOS & Android manifest bits

iOS `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Voor toegang tot bewakingscamera's.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key><true/>
</dict>
```

Android `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

(No `RECORD_AUDIO` – cameras never ask for the mic.)

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Tile shows videocam-off | Wrong RTSP URL or credentials. Test with probe API. For SS, check `Sms=N.unicast` index. |
| Thumbnails OK, live stutters | Main stream GOP too long or bitrate too high. Shorten I-frame interval in camera/SS; ensure profile uses FFmpeg + H.264. |
| WebRTC black screen, HLS works | Audio on RTSP breaking WebRTC — profile sets `videoOnly`; or force `go2rtcVideoOnly: true`. |
| WebRTC never connects, HLS works | UDP/8555 blocked or no ICE candidates. Add STUN in go2rtc template; use HLS fallback. |
| HLS has 10+ s latency | Normal for vanilla HLS. Prefer WebRTC for live. |
| Live OK on phone, slow on tablet | Tablet may fall back to HLS; check WebRTC ICE. Ensure backend proxy HLS is used, not direct localhost:1984. |
