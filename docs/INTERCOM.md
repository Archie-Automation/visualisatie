# Intercom (door station) integration

The intercom is a first-class device type, distinct from a camera. Where a camera is view-only, an intercom always has:

- Video + audio **down** (visitor → phone)
- Audio **up** (phone → visitor speaker, via ONVIF backchannel)
- A **doorbell event** surfaced to every logged-in device as an incoming-call overlay
- An optional **door release** action that pulses a KNX group address

```
 Doorbell                ┌─ HTTP release ─► KNX electric strike (optional)
 button (KNX 1-bit) ─────┤
                         └─ WS intercom.ring ─► every app → full-screen overlay

 Door station  ─RTSP/ONVIF(#backchannel=1)─►  go2rtc  ─WebRTC(sendrecv)─►  Flutter
```

Two-way audio is handled entirely by go2rtc: when we tag the source URL with `#backchannel=1`, go2rtc negotiates the ONVIF audio backchannel with the camera and exposes it as a regular sendrecv audio channel on WebRTC. Flutter attaches the mic, the rest is plumbing.

## Declaring an intercom

```json
{
  "id": "dev-hall-intercom",
  "type": "intercom",
  "name": "Voordeur",
  "favorite": true,
  "intercom": {
    "rtsp": "rtsp://user:pass@192.168.1.50:554/stream1",
    "path": "front-door",
    "aspect": "4:3",
    "codec": "h264",
    "doorbell": { "ga": "5/1/1" },
    "release":  { "ga": "5/2/1", "pulseMs": 1500 }
  }
}
```

| field | effect |
|---|---|
| `rtsp` | Source URL. Must support ONVIF Profile T backchannel for talk-back. `#backchannel=1` is appended automatically. |
| `path`, `aspect`, `codec`, `sources` | Same semantics as a camera. |
| `doorbell.ga` | 1-bit KNX GA that goes **true** when the visitor presses the button. A rising edge triggers the ring flow. |
| `release.ga` | 1-bit KNX GA that controls the electric strike. Backend pulses it true → false. |
| `release.pulseMs` | Pulse length. Default 1500 ms. |

Typical compatible hardware:

- **Doorbells / door stations**: DoorBird, Akuvox, 2N, BTicino Classe 300X, Hikvision DS-KV8… / DS-KD8…, Dahua VTO, Reolink Video Doorbell.
- **KNX doorbell button**: any binary input actor – the push button writes `1` to the chosen GA.
- **Electric strike**: driven by a KNX binary output; the intercom's own relay contact is fine too, just expose it as a KNX output so the app can pulse it.

## API

- `GET /api/intercoms`, `GET /api/intercoms/:id`
- `GET /api/intercoms/:id/snapshot` – JPEG, same 2 s cache as cameras.
- `POST /api/intercoms/:id/webrtc` – SDP signalling. No filtering: a sendrecv audio m-line is expected.
- `POST /api/intercoms/:id/release` – pulses the release GA. Returns `{ok:true}`.
- WebSocket event `{"type":"intercom.ring","payload":{"intercomId","name","ts"}}` – emitted on the rising edge of `doorbell.ga`.

## UI flow

1. A visitor rings the bell. The KNX coupler telegrams the configured GA → backend → all connected WebSockets.
2. Every app displays the luxe full-width **incoming-call banner** at the top of the screen: `VOORDEUR · Opnemen / Afwijzen`.
3. Tapping *Opnemen* routes to `/intercom/:id`, opens the WebRTC session with mic permission already granted (the mic track starts disabled).
4. The operator sees live video. **Push-and-hold** the brass mic button to speak; release to stop. Short-tap toggles.
5. The **DEUR OPEN** button fires a backend pulse. Haptic feedback and a transient "Deur geopend" message confirm.
6. *OPHANGEN* tears the session down and pops the route.

## Per-user ACL

The backend ships two intercom-specific ACL knobs inside `users[].access`:

```json
{
  "id": "usr-owner",
  "role": "user",
  "access": {
    "canRelease": ["dev-hall-intercom"],
    "talkIntercoms": "*"
  }
}
```

| field | type | semantics |
|---|---|---|
| `canRelease` | `"*"` / `string[]` / (unset) | Whitelist of intercom IDs the user may open the door on. Unset falls back to role: admins yes, users no. `[]` = never. |
| `talkIntercoms` | `"*"` / `string[]` / (unset) | Whitelist of intercoms the user may view/answer at all. Unset = any. |

The checks live in `backend/src/auth.ts` (`canReleaseIntercom`, `canViewIntercom`) and are enforced on:

- `GET /api/intercoms` (filters the list)
- `GET /api/intercoms/:id` (403 if denied)
- `GET /api/intercoms/:id/snapshot` (403 if denied)
- `POST /api/intercoms/:id/webrtc` (403 if denied)
- `POST /api/intercoms/:id/release` (403 if denied)

The Flutter UI hides the **DEUR OPEN** button for users whose `canRelease` check returns false, because the backend reports the effective capability on each `GET /api/intercoms/:id` response.

## Testing without a real bell

**In the app.** Go to `/admin`, expand the hall room, tap **TEST RING** on the intercom row. You'll see the in-app banner slide in, CallKit/ConnectionService fire the native call UI, and haptics buzz in a 1.2 s loop.

**From curl:**

```bash
curl -X POST http://localhost:4000/api/debug/ring/dev-hall-intercom \
  -H "authorization: Bearer $ADMIN_TOKEN"
```

The `/api/debug/ring/:id` endpoint is only mounted when `NODE_ENV !== "production"` and requires an admin token.

## Background ringing (CallKit / ConnectionService)

The app uses [`flutter_callkit_incoming`](https://pub.dev/packages/flutter_callkit_incoming) to present the native call UI. On iOS this means the full CallKit lock-screen overlay; on Android it's a high-priority call-style notification powered by ConnectionService.

### iOS setup

`ios/Runner/Info.plist` — add these (microphone permission is already listed in the camera docs):

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
  <string>voip</string>
  <string>remote-notification</string>
</array>
<key>NSMicrophoneUsageDescription</key>
<string>Om met de bezoeker aan de deur te kunnen spreken.</string>
```

For the call UI to appear while the app is terminated/backgrounded, you'll also need a PushKit VoIP push pipeline. That requires Apple Developer certificates + a backend dispatcher – out of scope for the LAN-only default, but the bridge is ready: wire `flutter_callkit_incoming`'s `onDidPushNotificationCallKitPushKit` handler to the same `IntercomRing` shape once the push is set up.

### Android setup

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.MANAGE_OWN_CALLS"/>
<uses-permission android:name="android.permission.READ_PHONE_NUMBERS"/>
```

Inside `<application>`:

```xml
<service
    android:name="com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver"
    android:exported="false"/>
```

`minSdkVersion` must be ≥ 24. On Android 13+ the app must request `POST_NOTIFICATIONS` at runtime; `permission_handler` is already bundled for this.

For true background delivery on Android (e.g. app was killed) you'll want FCM to deliver a data-only push that triggers `FlutterCallkitIncoming.showCallkitIncoming` from a background isolate. Again: not wired by default, because not every installation wants Firebase.

## iOS & Android manifest bits

**iOS `Info.plist`:**

```xml
<key>NSCameraUsageDescription</key>
<string>Voor toegang tot de deurcamera.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Om met de bezoeker aan de deur te kunnen spreken.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key><true/>
</dict>
```

**Android `AndroidManifest.xml`:**

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

`minSdkVersion 21` or higher (flutter_webrtc requirement).

## Troubleshooting

| Symptom | Probable cause |
|---|---|
| No talk, video works | Camera doesn't expose ONVIF Profile T backchannel, or vendor uses a proprietary SIP trunk instead. Check with `ffprobe "rtsp://…#backchannel=1"` – you should see an `Audio: pcm_mulaw` track going **up**. |
| Talk works one-way only (phone → door) | Phone's mic track is enabled (`SPREKEN` badge) but the door station has no inbound AEC. Short-press mode is usually better than long-press on cheap stations. |
| Echo on both sides | Echo cancellation in `getUserMedia` is disabled or the camera's own AEC is off. Enable both. |
| Ring overlay never appears | `doorbell.ga` not firing. Check `GET /api/state/<ga>` – the backend state should flip to `true` when the button is pressed. |
| Door release does nothing | KNX actor inverted. Try flipping the pulse polarity or double the `pulseMs` – some strikes need 2 s. |
| Incoming call deep-links to wrong route | `intercomId` in the `intercom.ring` payload must match the device's `id`. Check for typos in `house.json`. |
