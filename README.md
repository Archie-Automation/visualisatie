# Luxe KNX Smart Home Ecosystem

A high-end, custom Smart Home platform for KNX installations with a Node.js backend running on an Intel NUC (Proxmox/Docker) and a Flutter client for iOS & Android.

The entire house is described by a single **JSON tree** (Project → Floors → Rooms → Devices). The backend reads that tree, opens a tunnel to the KNX IP gateway and maintains an in-memory cache of every group-address value. The Flutter app pulls the same tree and renders itself dynamically – no code changes when the installer adds a room or a dimmer.

```
┌─────────────────────┐         ┌──────────────────────────┐         ┌──────────────┐
│  Flutter app        │  REST   │  Node.js backend (NUC)   │  KNXnet │  KNX IP      │
│  iOS / Android      │◄──────► │  Express + WS + knx.js   │◄──────► │  Gateway     │
│                     │   WS    │  JSON config + state     │  /IP    │              │
└─────────────────────┘         └──────────────────────────┘         └──────────────┘
                                            │
                                            ├── Sonos (node-sonos)
                                            ├── Cameras & intercoms (go2rtc: HLS/WebRTC/talkback)
                                            └── Remote access (Gira S1 / ISE Connect)
```

## Repository layout

```
/config            Human-editable JSON house configuration
/backend           Node.js (TypeScript) server
/app               Flutter client
/docker            docker-compose + Dockerfiles for the NUC
/docs              Architecture notes
```

## Getting started (development)

1. **Backend**

   Install dependencies once:

   ```bash
   npm install --prefix backend
   ```

   Start the dev server from **repo root** or from **`backend/`**:

   ```bash
   npm run dev
   ```

   Or explicitly:

   ```bash
   cd backend
   cp .env.example .env      # fill in KNX gateway IP
   npm install
   npm run dev
   ```

   The server listens on `http://localhost:4000`.
   REST: `GET /api/config`, `GET /api/state`, `POST /api/command`.
   WebSocket: `ws://localhost:4000/ws` (real-time state updates).

2. **Flutter app**

   ```bash
   cd app
   flutter pub get
   flutter run --dart-define=API_BASE=http://<nuc-ip>:4000
   ```

3. **Production on the NUC**

   ```bash
   cd docker
   docker compose up -d
   ```

## Adding a room

Edit `config/house.json`. Restart the backend (or hit `POST /api/config/reload`). The app picks up the new structure on next refresh.

See `docs/ARCHITECTURE.md` for the full design rationale.
