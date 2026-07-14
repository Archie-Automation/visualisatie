"""Satel mock server — gebruik dit om de UI te testen zonder echt alarmpaneel.

Start:
    uvicorn satel.mock_server:app --host 0.0.0.0 --port 8001 --reload

Ga naar http://localhost:8001 voor de bedieningspagina.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Literal

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Persistent partition config
# ---------------------------------------------------------------------------

_CONFIG_PATH = Path(__file__).parent / "mock_config.json"
_VALID_STATES = ("Disarmed", "Armed", "Exit_Delay", "Entry_Delay")

_DEFAULT_ARM_MODES: list[dict] = [
    {"mode": 0, "name": "Volledig"},
    {"mode": 1, "name": "Nacht"},
]

_DEFAULT_PARTITIONS: list[dict] = [
    {"number": 1, "name": "Geheel huis", "state": "Disarmed", "mode": 0,
     "arm_modes": [dict(m) for m in _DEFAULT_ARM_MODES]},
    {"number": 2, "name": "Garage",      "state": "Disarmed", "mode": 0,
     "arm_modes": [{"mode": 0, "name": "Volledig"}]},
]


def _load_partitions() -> list[dict]:
    """Load partition names + arm modes from disk; defaults on first run."""
    if _CONFIG_PATH.exists():
        try:
            data = json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
            parts = data.get("partitions", [])
            if parts:
                # Ensure runtime 'state'/'mode' fields are present.
                return [
                    {
                        "number": p["number"],
                        "name": p["name"],
                        "state": "Disarmed",
                        "mode": 0,
                        "arm_modes": p.get("arm_modes",
                                           [{"mode": 0, "name": "Volledig"}]),
                    }
                    for p in parts
                ]
        except Exception:
            pass
    return [dict(p) for p in _DEFAULT_PARTITIONS]


def _load_integration_key() -> str:
    if _CONFIG_PATH.exists():
        try:
            data = json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
            return str(data.get("integration_key", ""))
        except Exception:
            pass
    return ""


def _load_zone_mapping() -> list[dict]:
    """Load the configured zone mapping from disk (empty on first run)."""
    if _CONFIG_PATH.exists():
        try:
            data = json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
            return list(data.get("zone_mapping", []))
        except Exception:
            pass
    return []


def _save_config() -> None:
    """Persist partition names + zone mapping to disk (runtime state excluded)."""
    _CONFIG_PATH.write_text(
        json.dumps(
            {
                "partitions": [
                    {"number": p["number"], "name": p["name"],
                     "arm_modes": p.get("arm_modes", [])}
                    for p in _PARTITIONS
                ],
                "zone_mapping": _ZONE_MAPPING,
                "integration_key": _INTEGRATION_KEY,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


_PARTITIONS: list[dict] = _load_partitions()
_ZONE_MAPPING: list[dict] = _load_zone_mapping()
_INTEGRATION_KEY: str = _load_integration_key()
_BYPASSED: set[int] = set()

# Demo zones used only when no zone mapping has been configured yet.
_MOCK_ZONES = [
    {"zone_number": 1, "name": "Voordeur",           "room": "Hal",        "room_id": None, "device_type": "magneetcontact", "violated": False},
    {"zone_number": 2, "name": "Achterdeur",          "room": "Keuken",     "room_id": None, "device_type": "magneetcontact", "violated": False},
    {"zone_number": 3, "name": "Woonkamer beweging",  "room": "Woonkamer",  "room_id": None, "device_type": "pir_beweging",   "violated": False},
    {"zone_number": 4, "name": "Slaapkamer beweging", "room": "Slaapkamer", "room_id": None, "device_type": "pir_beweging",   "violated": False},
    {"zone_number": 5, "name": "Rookmelder hal",      "room": "Hal",        "room_id": None, "device_type": "rookmelder",     "violated": False},
    {"zone_number": 6, "name": "Watermelder kelder",  "room": "Kelder",     "room_id": None, "device_type": "watermelder",    "violated": False},
    {"zone_number": 7, "name": "Raam woonkamer",      "room": "Woonkamer",  "room_id": None, "device_type": "trilcontact",    "violated": False},
    {"zone_number": 8, "name": "Paniekknop slaap",    "room": "Slaapkamer", "room_id": None, "device_type": "paniekknop",     "violated": False},
]


def _get_partition(number: int) -> dict | None:
    return next((p for p in _PARTITIONS if p["number"] == number), None)


def _build_status() -> dict:
    # Use the configured zone mapping when present; otherwise demo zones.
    if _ZONE_MAPPING:
        zones = [
            {
                "zone_number": z.get("zone_number"),
                "name":        z.get("name", ""),
                "room":        z.get("room", ""),
                "room_id":     z.get("room_id"),
                "device_type": z.get("device_type", "magneetcontact"),
                "violated":    False,
                "bypassed":    z.get("zone_number") in _BYPASSED,
            }
            for z in _ZONE_MAPPING
        ]
    else:
        zones = [dict(z) for z in _MOCK_ZONES]
        for z in zones:
            z["bypassed"] = z["zone_number"] in _BYPASSED

    # Mark the first zone as violated when any partition is armed/entry.
    any_active = any(p["state"] in ("Armed", "Entry_Delay") for p in _PARTITIONS)
    if any_active and zones:
        zones[0]["violated"] = True

    by_room: dict[str, list] = {}
    for z in zones:
        by_room.setdefault(z["room"], []).append(z)

    rooms = [
        {"room": room, "violated": any(z["violated"] for z in sensors), "sensors": sensors}
        for room, sensors in sorted(by_room.items())
    ]

    return {
        "connected": True,
        "partitions": [
            {"number": p["number"], "name": p["name"], "state": p["state"]}
            for p in _PARTITIONS
        ],
        "rooms":     rooms,
        "all_zones": zones,
    }


# ---------------------------------------------------------------------------
# FastAPI
# ---------------------------------------------------------------------------

app = FastAPI(title="Satel Mock Server")


@app.get("/satel/status")
async def get_status():
    return _build_status()


@app.get("/satel/config")
async def get_config():
    return {
        "host": "mock",
        "port": 8001,
        "partitions": [
            {"number": p["number"], "name": p["name"],
             "arm_modes": p.get("arm_modes", [{"mode": 0, "name": "Volledig"}])}
            for p in _PARTITIONS
        ],
        "zone_mapping": _ZONE_MAPPING,
        "has_pin": True,  # mock always reports PIN as set
        "has_encryption": bool(_INTEGRATION_KEY),
    }


class _ActionBody(BaseModel):
    partition: int = 1
    mode: int = 0           # arm mode 0-3
    pin: str | None = None  # accepted but not validated in mock


@app.post("/satel/arm", status_code=204)
async def arm(body: _ActionBody):
    p = _get_partition(body.partition)
    if p:
        p["state"] = "Armed"
        p["mode"] = body.mode


@app.post("/satel/disarm", status_code=204)
async def disarm(body: _ActionBody):
    p = _get_partition(body.partition)
    if p:
        p["state"] = "Disarmed"


class _ConfigBody(BaseModel):
    partitions: list[dict] | None = None
    zone_mapping: list[dict] | None = None
    integration_key: str | None = None
    host: str | None = None
    port: int | None = None


@app.post("/satel/config", status_code=204)
async def set_config(body: _ConfigBody):
    """Update the partition list and/or zone mapping and persist to disk.

    Omitted fields (null) keep the existing value, matching the real service.
    """
    global _INTEGRATION_KEY
    if body.partitions is not None:
        _PARTITIONS.clear()
        for p in body.partitions:
            _PARTITIONS.append({
                "number": int(p.get("number", 1)),
                "name":   str(p.get("name", "")),
                "state":  "Disarmed",
                "mode":   0,
                "arm_modes": p.get("arm_modes",
                                   [{"mode": 0, "name": "Volledig"}]),
            })
    if body.zone_mapping is not None:
        _ZONE_MAPPING.clear()
        for z in body.zone_mapping:
            _ZONE_MAPPING.append({
                "zone_number": int(z.get("zone_number", 1)),
                "name":        str(z.get("name", "")),
                "room":        str(z.get("room", "")),
                "room_id":     z.get("room_id"),
                "device_type": str(z.get("device_type", "magneetcontact")),
            })
    if body.integration_key is not None:
        _INTEGRATION_KEY = body.integration_key
    _save_config()


class _BypassBody(BaseModel):
    zones: list[int] = []
    bypass: bool = True
    pin: str | None = None


@app.post("/satel/bypass", status_code=204)
async def bypass(body: _BypassBody):
    """Bypass / unbypass zones (mock: just toggles the in-memory set)."""
    for z in body.zones:
        if body.bypass:
            _BYPASSED.add(z)
        else:
            _BYPASSED.discard(z)


@app.post("/satel/pin", status_code=204)
async def set_pin(body: dict = {}):
    pass  # mock: PIN is always "set"


class _MockBody(BaseModel):
    partition: int = 1
    state: Literal["Disarmed", "Armed", "Exit_Delay", "Entry_Delay"]


@app.post("/satel/mock/state", status_code=204)
async def set_mock_state(body: _MockBody):
    p = _get_partition(body.partition)
    if p:
        p["state"] = body.state


# ---------------------------------------------------------------------------
# HTML control page
# ---------------------------------------------------------------------------

_HTML = """<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Satel Mock</title>
  <style>
    body { font-family:sans-serif; max-width:560px; margin:40px auto; padding:0 16px; }
    h1   { font-size:1.4rem; }
    p    { color:#555; font-size:.9rem; }
    .part { border:1px solid #ddd; border-radius:12px; padding:16px; margin-bottom:14px; }
    .part h2 { margin:0 0 12px; font-size:1rem; }
    .grid { display:grid; grid-template-columns:1fr 1fr; gap:8px; }
    button { padding:12px; border:none; border-radius:9px; font-size:.9rem;
             font-weight:600; cursor:pointer; transition:opacity .15s; }
    button:hover { opacity:.8; }
    .d { background:#e8f5e9; color:#2e7d32; }
    .a { background:#ffebee; color:#c62828; }
    .x { background:#fff3e0; color:#e65100; }
    .e { background:#fce4ec; color:#ad1457; }
    #status { margin-top:16px; background:#f5f5f5; padding:14px;
              border-radius:10px; font-size:.9rem; white-space:pre; }
  </style>
</head>
<body>
  <h1>🔒 Satel Mock</h1>
  <p>Klik per partitie de gewenste staat om de Flutter-app te testen.</p>
  <div id="partitions"></div>
  <pre id="status">laden…</pre>

  <script>
    async function setState(partition, state) {
      await fetch('/satel/mock/state', {
        method:'POST',
        headers:{'content-type':'application/json'},
        body: JSON.stringify({partition, state})
      });
      poll();
    }

    async function poll() {
      const r = await fetch('/satel/status');
      const d = await r.json();
      const el = document.getElementById('partitions');
      el.innerHTML = d.partitions.map(p => `
        <div class="part">
          <h2>${p.name} (partitie ${p.number}) — <b>${p.state}</b></h2>
          <div class="grid">
            <button class="d" onclick="setState(${p.number},'Disarmed')">✅ Uitgeschakeld</button>
            <button class="a" onclick="setState(${p.number},'Armed')">🔴 Ingeschakeld</button>
            <button class="x" onclick="setState(${p.number},'Exit_Delay')">🟠 Uitlooptijd</button>
            <button class="e" onclick="setState(${p.number},'Entry_Delay')">🚨 Inlooptijd</button>
          </div>
        </div>`).join('');

      const violated = d.all_zones.filter(z=>z.violated).map(z=>z.name).join(', ');
      document.getElementById('status').textContent =
        d.partitions.map(p=>`${p.name}: ${p.state}`).join('\\n') +
        (violated ? '\\nActief: '+violated : '');
    }

    poll();
    setInterval(poll, 1500);
  </script>
</body>
</html>"""


@app.get("/", response_class=HTMLResponse)
async def root():
    return _HTML
