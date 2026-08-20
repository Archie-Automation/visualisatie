# Media speakers — Sonos & Bluesound

Het systeem kan Sonos- en Bluesound (BluOS) spelers aansturen
als gewone "devices" in `house.json`. Ze krijgen dezelfde luxe tegel
als lichten/klimaat en een volledig full-screen speler.

## Wat kan er?

- Play / pauze / stop / volgende / vorige
- Volume & mute
- Nu-speelt (titel, artiest, album, artwork)
- Favorieten / presets (Sonos favourites, Bluesound preset-slots)
- Online-status per speler

Live updates via WebSocket: zodra de backend merkt dat het nummer
verandert of iemand via de Sonos-app pauzeert, zie je dat direct
in de tegel.

## Sonos instellen

```json
{
  "id": "dev-living-sonos",
  "type": "media_sonos",
  "name": "Sonos Woonkamer",
  "sonos": {
    "host": "192.168.1.50",
    "port": 1400,
    "room": "Woonkamer"
  }
}
```

- `host` — IP of hostname van de zone-coordinator (**aan te raden**).
  Standaard reserveert u dit via een DHCP-reservering.
- `port` — optioneel, default `1400` (SOAP-poort van Sonos).
- `room` — optioneel. Als `host` ontbreekt gebruikt de backend SSDP-
  discovery en kiest de zone met deze naam. Werkt alleen als de
  backend en Sonos op hetzelfde subnet staan.

Favorieten worden geladen via `getFavorites()`. In de speler zie je
ze onderaan; tikken speelt de favoriet af.

## Bluesound instellen

```json
{
  "id": "dev-studio-bluesound",
  "type": "media_bluesound",
  "name": "Bluesound Studio",
  "bluesound": {
    "host": "192.168.1.60",
    "port": 11000
  }
}
```

- `host` — **verplicht**. IP/hostname van de BluOS-speler.
- `port` — optioneel, default `11000`.

De driver polt `/Status` (elke 3 s) en gebruikt `/Presets` voor de
preset-lijst. Alle acties worden via plain HTTP verstuurd; er is dus
geen extra pairing of token nodig.

## Commands (backend API)

Alle media-commando's gaan via `POST /api/command`:

```jsonc
// transport
{ "kind": "media.transport", "deviceId": "...", "action": "play" }
{ "kind": "media.transport", "deviceId": "...", "action": "pause" }
{ "kind": "media.transport", "deviceId": "...", "action": "stop" }
{ "kind": "media.transport", "deviceId": "...", "action": "next" }
{ "kind": "media.transport", "deviceId": "...", "action": "previous" }

// volume & mute
{ "kind": "media.volume", "deviceId": "...", "value": 35 }
{ "kind": "media.mute",   "deviceId": "...", "muted": true }
{ "kind": "media.group.volume", "deviceId": "...", "value": 40 }

// preset / favoriet
{ "kind": "media.preset", "deviceId": "...", "presetId": "Jazz FM" }
```

### State endpoints

| Endpoint              | Beschrijving                              |
| --------------------- | ----------------------------------------- |
| `GET /api/media`      | Alle speler-states (snapshot)             |
| `GET /api/media/:id`  | State voor één speler                     |

Over het WS-kanaal stuurt de backend:

- `media.snapshot` — bij connect, lijst van alle states
- `media.state`    — per speler zodra er iets verandert

Shape (verkort):

```ts
{
  deviceId: string;
  brand: "sonos" | "bluesound";
  online: boolean;
  transport: "playing" | "paused" | "stopped" | "buffering";
  title?: string; artist?: string; album?: string;
  albumArt?: string; source?: string;
  volume?: number; muted?: boolean;
  groupVolume?: number;
  groupRole?: "coordinator" | "member" | "standalone";
  groupMemberIds?: string[];
  groupCoordinatorId?: string;
  position?: number; duration?: number;
  presets?: { id: string; name: string; image?: string }[];
}
```

## Architectuur in één oogopslag

```
┌──────────────────────────────────────────────────────────────┐
│                      MediaManager                            │
│  ┌──────────────┐     ┌───────────────────┐                  │
│  │ SonosDriver  │──→  │   sonos (npm)     │ → UPnP/SOAP :1400│
│  └──────────────┘     └───────────────────┘                  │
│  ┌────────────────┐   ┌──────────────────────────────────┐   │
│  │ BluesoundDriver│→  │  fetch("http://host:11000/...")  │   │
│  └────────────────┘   └──────────────────────────────────┘   │
│                                                              │
│  • poll elke 3s         • commands via dispatch(…)           │
│  • emit stateChanged    • gecached per deviceId              │
└──────────────────────────────────────────────────────────────┘
                 │
                 ▼  (stateChanged)
         attachWebSocket → `media.state` broadcast
                 │
                 ▼
           Flutter client
       ┌─────────────────┐
       │ mediaStateProvider│  ← tegels, speler
       └─────────────────┘
```

## Toekomst

- Scène-integratie: `SceneAction` met `kind: "media"` zodat
  "Welkom thuis" zachtjes Jazz FM opzet in de hal.
- Spotify-Connect / Tidal directe handoff (nu werkt dat via de
  native app — de tegel laat wél het nummer zien dat speelt).
