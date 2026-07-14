"""Pydantic models for the Satel integration configuration."""

from __future__ import annotations

from enum import Enum
from typing import Annotated

from pydantic import BaseModel, Field, model_validator


class DeviceType(str, Enum):
    magneetcontact = "magneetcontact"   # Door / window contact
    pir_beweging   = "pir_beweging"     # PIR motion sensor
    trilcontact    = "trilcontact"      # Vibration / shock
    glasbreuk      = "glasbreuk"        # Glass break
    rookmelder     = "rookmelder"       # Smoke detector
    watermelder    = "watermelder"      # Water leakage
    gasmelder      = "gasmelder"        # Gas leak
    paniekknop     = "paniekknop"       # Panic / holdup button


class ZoneMapping(BaseModel):
    zone_number: Annotated[int, Field(ge=1, le=128, description="Satel zone number (1-128)")]
    name:        str        = Field(..., description="Human-readable sensor name")
    # Display label kept for the alarm-page grouping and backwards-compat.
    room:        str        = Field("", description="Room display name (label / grouping)")
    # Stable app room id — used to couple the zone to the correct room even
    # when the room is later renamed. Null when not assigned to a room.
    room_id:     str | None = Field(None, description="App room id used for matching")
    device_type: DeviceType


class ArmModeConfig(BaseModel):
    """A single arm mode offered to the user for a partition.

    `mode` is the Satel arm mode (0 = full/away, 1-3 = installer-defined
    partial modes). `name` is the label shown in the app, chosen to match the
    installer's programming and the users' wishes (e.g. "Volledig", "Nacht").
    """
    mode: Annotated[int, Field(ge=0, le=3)] = Field(
        0, description="Satel arm mode (0-3)"
    )
    name: str = Field(..., description="Label shown in the app")


def _default_arm_modes() -> list["ArmModeConfig"]:
    return [ArmModeConfig(mode=0, name="Volledig")]


class PartitionConfig(BaseModel):
    """A single INTEGRA partition that the app can arm/disarm."""
    number: Annotated[int, Field(ge=1, le=32)] = Field(
        ..., description="Partition number (1–32)"
    )
    name: str = Field(..., description="Display name shown in the app")
    arm_modes: list[ArmModeConfig] = Field(
        default_factory=_default_arm_modes,
        description="Arm modes the user can choose for this partition.",
    )


class SatelConfig(BaseModel):
    host:         str = Field(..., description="ETHM-1 / INT-ETHER IP address")
    port:         int = Field(7094, ge=1, le=65535)
    password:     str = Field("", description="Integration password (hex string, leave empty if not set)")
    # AES integration key (DLOADX "Encrypted integration"). Empty = plain-text
    # connection (encryption is fully optional).
    integration_key: str = Field("", description="AES integration key; empty = no encryption")
    # User code used by the app to arm/disarm the panel.
    # Stored server-side; never returned via the API (write-only).
    pin:          str | None = Field(None, description="Arm/disarm user code (write-only, never returned by API)")
    partitions:   list[PartitionConfig] = Field(
        default_factory=lambda: [PartitionConfig(number=1, name="Geheel huis")],
        description="One or more partitions to monitor and control.",
    )
    zone_mapping: list[ZoneMapping] = Field(default_factory=list)

    @model_validator(mode="before")
    @classmethod
    def _migrate_legacy_partition(cls, data: dict) -> dict:
        """Accept old configs that only have `partition: int`."""
        if isinstance(data, dict) and "partition" in data and "partitions" not in data:
            data["partitions"] = [{"number": data.pop("partition"), "name": "Geheel huis"}]
        return data
