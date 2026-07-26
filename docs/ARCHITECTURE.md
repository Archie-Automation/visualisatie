# Architecture

## 1. Tree model

The entire installation is represented as one JSON document:

```
Project
├── knx         (gateway, physical address)
├── floors[]
│   └── rooms[]
│       └── devices[]   (typed: light_switch, light_dimmer, shading, climate,
│                        media_sonos, camera, intercom)
└── users[]     (permissions on floor/room level)
```

Each device references **KNX group addresses (GAs)** by role, never by a raw numeric blob. Example for a dimmer:

```json
{
  "type": "light_dimmer",
  "ga": {
    "switch":        "1/1/12",
    "switch_status": "1/3/12",
    "dim_value":     "1/2/12",
    "dim_status":    "1/4/12"
  }
}
```

The backend knows per device type which GAs are mandatory, which DPT (Datapoint Type) each has, and how to translate a user action ("set 60%") into a bus telegram.

## 2. State cache

- On boot the backend reads `config/house.json`, enumerates every GA referenced and subscribes to bus events.
- Every received telegram updates an in-memory `Map<GA, {value, ts, dpt}>`.
- A "read request" is fired on start-up for every *_status GA so the cache is primed without waiting for the first user action.
- The cache is exposed to clients via WebSocket (delta updates) and REST (`GET /api/state` for the full snapshot).

## 3. Transport

- **REST** for everything non-realtime (config, login, commands issued by the app).
- **WebSocket** for push: state changes, alarms, Sonos now-playing.
- All endpoints sit behind a JWT; the admin endpoints additionally require role `admin`.

## 4. Remote access

**Fase 1 (nu):** bereik de stack op het LAN via `http://<nuc-ip>:4000/`. Zie [DEPLOY.md](./DEPLOY.md).

**Later:** Cloudflare Tunnel naar een domein (bijv. `home.archie.cloud`) + optioneel TURN voor WebRTC/intercom buitenshuis. Directe internet-exposure zonder tunnel blijft afgeraden.

## 5. Deployment

**Server:** één Docker-image (`docker/Dockerfile`) met Flutter web UI + Node API + **go2rtc** + **ffmpeg**. Start met `docker/install.sh` (seedt leeg huis alleen als `house.json` ontbreekt). Zie [DEPLOY.md](./DEPLOY.md).

**Ontwikkeling:** backend met `npm run dev`; optioneel `GO2RTC_AUTO_START=1` als go2rtc lokaal op PATH staat.

## 6. UX principles

- Bang & Olufsen inspired: generous whitespace, monochrome with a single warm accent.
- Typography: Inter (primary) + Lexend Deca (numerals).
- Motion: 250–400 ms Hero transitions, no bounce, cubic `easeOutCubic`.
- Room cards show *aggregated* status ("2 on, 19.5 °C"), never raw GA values.
