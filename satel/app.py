"""FastAPI service for the Satel INTEGRA alarm integration.

Endpoints
---------
GET  /satel/config       — Return current configuration (password + PIN excluded).
POST /satel/config       — Store a new config and hot-reload.
POST /satel/pin          — Set or overwrite the stored arm/disarm PIN (write-only).
GET  /satel/status       — Partition states, room sensors, zone list.
POST /satel/arm          — Arm one partition   (body: {partition}).
POST /satel/disarm       — Disarm one partition (body: {partition}).

Run with:
    uvicorn satel.app:app --host 0.0.0.0 --port 8001 --reload
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

from .config_schema import ArmModeConfig, PartitionConfig, SatelConfig, ZoneMapping
from .protocol import SatelClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
log = logging.getLogger("satel.app")

_HERE       = Path(__file__).parent
CONFIG_FILE = _HERE / "config.json"

_client: SatelClient | None = None
_config: SatelConfig | None = None

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------


def _load_config() -> SatelConfig | None:
    if not CONFIG_FILE.exists():
        return None
    try:
        return SatelConfig.model_validate(
            json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        )
    except Exception as exc:
        log.error("Failed to load config.json: %s", exc)
        return None


def _save_config(cfg: SatelConfig) -> None:
    CONFIG_FILE.write_text(cfg.model_dump_json(indent=2), encoding="utf-8")


def _apply_config(cfg: SatelConfig) -> None:
    global _client, _config
    if _client is not None:
        _client.stop()
        _client = None
    _config = cfg
    _client = SatelClient(
        host=cfg.host, port=cfg.port, password=cfg.password,
        integration_key=cfg.integration_key,
    )
    _client.start()
    log.info(
        "Satel client (re)started → %s:%s  partitions=%s  pin=%s  encryption=%s",
        cfg.host, cfg.port,
        [p.number for p in cfg.partitions],
        "set" if cfg.pin else "not set",
        "on" if cfg.integration_key else "off",
    )


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    cfg = _load_config()
    if cfg:
        _apply_config(cfg)
    else:
        log.warning("No config.json – POST /satel/config to configure.")
    yield
    if _client:
        _client.stop()


app = FastAPI(title="Satel INTEGRA Integration", version="2.1.0", lifespan=lifespan)


# ---------------------------------------------------------------------------
# GET /satel/config
# ---------------------------------------------------------------------------


class PartitionOut(BaseModel):
    number:    int
    name:      str
    arm_modes: list[ArmModeConfig]


class ConfigOut(BaseModel):
    host:           str
    port:           int
    partitions:     list[PartitionOut]
    zone_mapping:   list[ZoneMapping]
    has_pin:        bool  # True when a PIN has been configured; the PIN itself is never returned.
    has_encryption: bool  # True when an integration key is set; the key itself is never returned.


@app.get("/satel/config", response_model=ConfigOut,
         summary="Return current config (password, PIN and key excluded).")
async def get_config() -> ConfigOut:
    if _config is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Not configured yet.")
    return ConfigOut(
        host=_config.host,
        port=_config.port,
        partitions=[PartitionOut(number=p.number, name=p.name,
                                 arm_modes=list(p.arm_modes))
                    for p in _config.partitions],
        zone_mapping=list(_config.zone_mapping),
        has_pin=bool(_config.pin),
        has_encryption=bool(_config.integration_key),
    )


# ---------------------------------------------------------------------------
# POST /satel/config
# ---------------------------------------------------------------------------


class _ConfigIn(BaseModel):
    """Accepted body for updating the configuration.

    All fields are optional so callers can do partial updates:
      * ``host="keep"`` (or omit) keeps the existing host/port.
      * ``pin`` omitted / null keeps the existing PIN; ``""`` clears it.
      * ``integration_key`` omitted / null keeps it; ``""`` disables encryption.
      * ``partitions`` / ``zone_mapping`` omitted (null) keeps the existing list.
    """
    host:            str | None = None
    port:            int | None = None
    password:        str | None = None
    pin:             str | None = None              # None = keep existing; "" = clear
    integration_key: str | None = None             # None = keep; "" = disable encryption
    partitions:      list[PartitionConfig] | None = None   # None = keep existing
    zone_mapping:    list[ZoneMapping] | None = None       # None = keep existing


@app.post("/satel/config", status_code=status.HTTP_204_NO_CONTENT,
          summary="Store a new Satel configuration and reconnect immediately.")
async def post_config(body: _ConfigIn) -> None:
    existing = _config

    # Host: "keep" or omitted → preserve existing host/port.
    if body.host is None or body.host == "keep":
        host = existing.host if existing else ""
        port = existing.port if existing else 7094
    else:
        host = body.host
        port = body.port if body.port is not None else 7094

    password = body.password if body.password is not None else (
        existing.password if existing else "")

    # PIN: None keeps existing; "" clears it.
    new_pin = body.pin if body.pin is not None else (
        existing.pin if existing else None)

    # Integration key: None keeps existing; "" disables encryption.
    integration_key = body.integration_key if body.integration_key is not None else (
        existing.integration_key if existing else "")

    # Partitions / zone_mapping: None keeps existing.
    partitions = body.partitions if body.partitions is not None else (
        list(existing.partitions) if existing
        else [PartitionConfig(number=1, name="Geheel huis")])
    zone_mapping = body.zone_mapping if body.zone_mapping is not None else (
        list(existing.zone_mapping) if existing else [])

    cfg = SatelConfig(
        host=host,
        port=port,
        password=password,
        pin=new_pin,
        integration_key=integration_key,
        partitions=partitions,
        zone_mapping=zone_mapping,
    )
    _save_config(cfg)
    asyncio.create_task(_reload_task(cfg))


async def _reload_task(cfg: SatelConfig) -> None:
    await asyncio.sleep(0.05)
    _apply_config(cfg)


# ---------------------------------------------------------------------------
# POST /satel/pin  — set or overwrite the stored user code
# ---------------------------------------------------------------------------


class _PinBody(BaseModel):
    pin: str = Field(..., pattern=r'^\d{4,8}$',
                     description="New arm/disarm PIN (4–8 digits).")


@app.post("/satel/pin", status_code=status.HTTP_204_NO_CONTENT,
          summary="Set or overwrite the stored arm/disarm PIN (write-only).")
async def post_pin(body: _PinBody) -> None:
    global _config
    if _config is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Satel not configured yet.")
    # Update only the PIN field, keep everything else.
    updated = _config.model_copy(update={"pin": body.pin})
    _save_config(updated)
    _config = updated
    log.info("Arm/disarm PIN updated.")


# ---------------------------------------------------------------------------
# GET /satel/status
# ---------------------------------------------------------------------------


class ZoneStatus(BaseModel):
    zone_number: int
    name:        str
    room:        str
    room_id:     str | None = None
    device_type: str
    violated:    bool
    bypassed:    bool = False


class RoomStatus(BaseModel):
    room:     str
    violated: bool
    sensors:  list[ZoneStatus]


class PartitionStatus(BaseModel):
    number: int
    name:   str
    state:  str   # "Disarmed" | "Armed" | "Exit_Delay" | "Entry_Delay"


class StatusResponse(BaseModel):
    connected:  bool
    partitions: list[PartitionStatus]
    rooms:      list[RoomStatus]
    all_zones:  list[ZoneStatus]


@app.get("/satel/status", response_model=StatusResponse,
         summary="Current partition states and per-zone sensor statuses.")
async def get_status() -> StatusResponse:
    if _config is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Satel not configured yet.")

    bus_state = _client.state if _client else None
    violated_zones: set[int] = bus_state.zones_violated if bus_state else set()
    bypassed_zones: set[int] = bus_state.zones_bypassed if bus_state else set()

    # Per-partition state
    partitions = [
        PartitionStatus(
            number=p.number,
            name=p.name,
            state=bus_state.partition_state(p.number) if bus_state else "Disarmed",
        )
        for p in _config.partitions
    ]

    # Zones
    all_zones = [
        ZoneStatus(
            zone_number=zm.zone_number,
            name=zm.name,
            room=zm.room,
            room_id=zm.room_id,
            device_type=zm.device_type.value,
            violated=zm.zone_number in violated_zones,
            bypassed=zm.zone_number in bypassed_zones,
        )
        for zm in _config.zone_mapping
    ]

    # Group by room
    room_map: dict[str, list[ZoneStatus]] = defaultdict(list)
    for z in all_zones:
        room_map[z.room].append(z)

    rooms = sorted(
        [
            RoomStatus(
                room=room,
                violated=any(s.violated for s in sensors),
                sensors=sensors,
            )
            for room, sensors in room_map.items()
        ],
        key=lambda r: r.room,
    )

    return StatusResponse(
        connected=bool(_client and _client.connected),
        partitions=partitions,
        rooms=rooms,
        all_zones=all_zones,
    )


# ---------------------------------------------------------------------------
# POST /satel/arm  /  POST /satel/disarm
# ---------------------------------------------------------------------------


class _ActionBody(BaseModel):
    partition: int = Field(1, ge=1, le=32,
                           description="Partition number to arm/disarm.")
    mode: int = Field(0, ge=0, le=3,
                      description="Arm mode 0-3 (ignored for disarm).")
    pin: str | None = Field(
        None,
        description=(
            "User's arm/disarm code entered in the app. "
            "If omitted, the server-side stored PIN is used as fallback."
        ),
    )


def _resolve_pin(body_pin: str | None) -> str:
    """Return the PIN to use: prefer the client-supplied PIN, then the stored one."""
    effective = body_pin or (_config.pin if _config else None)
    if not effective:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Geen code opgegeven. Voer een code in of stel er een in via de technische configuratie.",
        )
    return effective


@app.post("/satel/arm", status_code=status.HTTP_204_NO_CONTENT,
          summary="Arm a partition. Client PIN takes priority; falls back to server-stored PIN.")
async def post_arm(body: _ActionBody) -> None:
    if _config is None or _client is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Satel not configured.")
    pin = _resolve_pin(body.pin)
    if not await _client.arm(pin, body.partition, body.mode):
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Satel not connected.")


@app.post("/satel/disarm", status_code=status.HTTP_204_NO_CONTENT,
          summary="Disarm a partition. Client PIN takes priority; falls back to server-stored PIN.")
async def post_disarm(body: _ActionBody) -> None:
    if _config is None or _client is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Satel not configured.")
    pin = _resolve_pin(body.pin)
    if not await _client.disarm(pin, body.partition):
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Satel not connected.")


# ---------------------------------------------------------------------------
# POST /satel/bypass  — bypass / unbypass one or more zones
# ---------------------------------------------------------------------------


class _BypassBody(BaseModel):
    zones:  list[Annotated[int, Field(ge=1, le=128)]] = Field(
        ..., description="Zone numbers to (un)bypass.")
    bypass: bool = Field(True, description="True = bypass, False = unbypass.")
    pin: str | None = Field(
        None, description="User code; falls back to the stored PIN if omitted.")


@app.post("/satel/bypass", status_code=status.HTTP_204_NO_CONTENT,
          summary="Bypass or unbypass zones. Client PIN takes priority.")
async def post_bypass(body: _BypassBody) -> None:
    if _config is None or _client is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Satel not configured.")
    if not body.zones:
        return
    pin = _resolve_pin(body.pin)
    if not await _client.bypass(pin, body.zones, body.bypass):
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Satel not connected.")
