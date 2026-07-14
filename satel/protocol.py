"""Low-level async TCP client for the Satel ETHM-1 / INT-ETHER module.

Protocol reference: "ETHM-1 Plus – integration protocol" (Satel) and the
well-tested ``satel_integra`` library. Frames are:

    0xFE 0xFE <CMD> [data…] <CRC_H> <CRC_L> 0xFE 0x0D

with 0xFE inside the payload escaped as 0xFE 0xF0. Multi-byte state bitmasks
are LITTLE-endian (byte 0 = items 1-8, bit 0 = item 1).

Optionally the whole framed message is wrapped in an AES-encrypted PDU when an
integration key is configured (see encryption.py). Encryption is optional: with
no key the plain-text transport is used.

Read commands (queried every poll cycle):
  0x00  Zones violated            (128 bits / 16 bytes)
  0x06  Zones bypassed            (128 bits / 16 bytes)
  0x0A  Partitions armed mode 0   (away / full)        32 bits / 4 bytes
  0x2A  Partitions armed mode 1
  0x0B  Partitions armed mode 2
  0x0C  Partitions armed mode 3
  0x0E  Partitions with entry time
  0x0F  Partitions exit countdown > 10 s
  0x10  Partitions exit countdown < 10 s

Write commands:
  0x80-0x83  Arm partitions in mode 0-3   payload: usercode(8) + partitions(4)
  0x84       Disarm partitions            payload: usercode(8) + partitions(4)
  0x86       Bypass zones                 payload: usercode(8) + zones(16)
  0x87       Unbypass zones               payload: usercode(8) + zones(16)
"""

from __future__ import annotations

import asyncio
import logging
import struct

from .encryption import EncryptedCommunicationHandler

log = logging.getLogger("satel.protocol")

# ---------------------------------------------------------------------------
# Frame helpers
# ---------------------------------------------------------------------------

_START = bytes([0xFE, 0xFE])
_END   = bytes([0xFE, 0x0D])


def _crc(data: bytes) -> int:
    """Satel CRC-16 (custom polynomial 0x1021, seed 0x147A)."""
    crc = 0x147A
    for b in data:
        crc = ((crc << 1) & 0xFFFF) | (crc >> 15)  # rotate left 1
        crc ^= 0xFFFF
        crc = (crc + (crc >> 8) + b) & 0xFFFF
    return crc


def _escape(data: bytes) -> bytes:
    return data.replace(b'\xfe', b'\xfe\xf0')


def _unescape(data: bytes) -> bytes:
    return data.replace(b'\xfe\xf0', b'\xfe')


def _build_frame(cmd: int, payload: bytes = b'') -> bytes:
    body = bytes([cmd]) + payload
    crc  = _crc(body)
    raw  = body + struct.pack('>H', crc)
    return _START + _escape(raw) + _END


def _parse_frames(buf: bytearray) -> tuple[list[bytes], bytearray]:
    """Extract complete frames from a raw receive buffer.

    Returns (list_of_command_bodies, remaining_buffer).
    """
    frames: list[bytes] = []
    while True:
        start = buf.find(b'\xfe\xfe')
        if start == -1:
            buf = bytearray()
            break
        if start > 0:
            del buf[:start]

        end = buf.find(b'\xfe\x0d', 2)
        if end == -1:
            break

        raw_escaped = bytes(buf[2:end])
        raw = _unescape(raw_escaped)
        del buf[:end + 2]

        if len(raw) < 3:          # cmd + 2 crc bytes minimum
            continue
        body    = raw[:-2]
        got_crc = struct.unpack('>H', raw[-2:])[0]
        if _crc(body) != got_crc:
            log.warning("CRC mismatch – frame discarded")
            continue
        frames.append(body)       # body[0] = cmd, body[1:] = payload

    return frames, buf


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

CMD_ZONES_VIOLATED        = 0x00
CMD_ZONES_BYPASSED        = 0x06
CMD_PART_ARMED_MODE0      = 0x0A   # away / full arm
CMD_PART_ARMED_MODE1      = 0x2A
CMD_PART_ARMED_MODE2      = 0x0B
CMD_PART_ARMED_MODE3      = 0x0C
CMD_PART_ENTRY_TIME       = 0x0E
CMD_PART_EXIT_OVER_10     = 0x0F
CMD_PART_EXIT_UNDER_10    = 0x10
CMD_NEW_DATA              = 0xEF   # RESULT / command response

# Arm-mode write command per mode index (0-3).
CMD_ARM_MODE = {0: 0x80, 1: 0x81, 2: 0x82, 3: 0x83}
CMD_DISARM        = 0x84
CMD_ZONES_BYPASS  = 0x86
CMD_ZONES_UNBYP   = 0x87

# Full query list we send after every successful connection / poll cycle.
_QUERY_CMDS = [
    CMD_ZONES_VIOLATED,
    CMD_ZONES_BYPASSED,
    CMD_PART_ARMED_MODE0,
    CMD_PART_ARMED_MODE1,
    CMD_PART_ARMED_MODE2,
    CMD_PART_ARMED_MODE3,
    CMD_PART_ENTRY_TIME,
    CMD_PART_EXIT_OVER_10,
    CMD_PART_EXIT_UNDER_10,
]


# ---------------------------------------------------------------------------
# State snapshot
# ---------------------------------------------------------------------------

class SatelState:
    __slots__ = (
        "zones_violated",
        "zones_bypassed",
        "partitions_armed",
        "partitions_entry",
        "partitions_exit",
    )

    def __init__(self) -> None:
        self.zones_violated:   set[int] = set()   # 1-indexed zone numbers
        self.zones_bypassed:   set[int] = set()
        self.partitions_armed: set[int] = set()   # union of all arm modes
        self.partitions_entry: set[int] = set()
        self.partitions_exit:  set[int] = set()

    def partition_state(self, partition: int) -> str:
        """Return a human-readable state string for a single partition."""
        if partition in self.partitions_exit:
            return "Exit_Delay"
        if partition in self.partitions_entry:
            return "Entry_Delay"
        if partition in self.partitions_armed:
            return "Armed"
        return "Disarmed"


def _bits_to_set(data: bytes, offset: int = 1) -> set[int]:
    """Convert a little-endian bitmask payload to a set of 1-indexed numbers.

    Satel sends LSB first: byte 0 = items 1-8, bit 0 = item 1.
    """
    result: set[int] = set()
    for byte_idx, byte in enumerate(data):
        for bit in range(8):
            if byte & (1 << bit):
                result.add(byte_idx * 8 + bit + offset)
    return result


def _le_bitmask(numbers: list[int], nbytes: int) -> bytes:
    """Encode 1-indexed numbers as a little-endian bitmask of nbytes."""
    value = 0
    for n in numbers:
        value |= 1 << (n - 1)
    return value.to_bytes(nbytes, "little")


# ---------------------------------------------------------------------------
# Async client
# ---------------------------------------------------------------------------

_POLL_INTERVAL  = 3.0   # seconds between full query cycles
_CONNECT_RETRY  = 5.0   # seconds before reconnect after failure
_READ_TIMEOUT   = 10.0  # seconds before assuming connection is dead


def _encode_user_code(pin: str) -> bytes:
    """Encode a numeric PIN (4-8 digits) as an 8-byte Satel user code.

    Codes are BCD, LEFT-aligned, padded on the right with 0xF nibbles.
    Example: "1234" -> 12 34 FF FF FF FF FF FF
    """
    digits = ''.join(ch for ch in pin if ch.isdigit())[:16]
    padded = digits.ljust(16, 'F')
    return bytes(int(padded[i:i + 2], 16) for i in range(0, 16, 2))


class SatelClient:
    """Manages a persistent async TCP connection to an ETHM-1 module.

    After ``start()`` the client polls continuously and keeps ``state``
    up-to-date. It reconnects automatically on TCP errors. When
    ``integration_key`` is set, all traffic is AES-encrypted.
    """

    def __init__(self, host: str, port: int, password: str = "",
                 integration_key: str = "") -> None:
        self.host            = host
        self.port            = port
        self.password        = password
        self.integration_key = integration_key or ""

        self.state = SatelState()
        self._connected = False
        self._task: asyncio.Task | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._crypto: EncryptedCommunicationHandler | None = None
        self._io_lock = asyncio.Lock()   # serialise request/response exchanges
        self._buf = bytearray()          # plaintext receive buffer
        # Per-mode armed/exit sets so the union stays accurate across modes.
        self._armed_by_cmd: dict[int, set[int]] = {}
        self._exit_by_cmd: dict[int, set[int]] = {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._run(), name="satel-client")

    def stop(self) -> None:
        if self._task:
            self._task.cancel()

    @property
    def connected(self) -> bool:
        return self._connected

    async def arm(self, pin: str, partition: int, mode: int = 0) -> bool:
        """Arm a partition in the given mode (0-3). Returns True if sent."""
        cmd = CMD_ARM_MODE.get(mode, CMD_ARM_MODE[0])
        payload = _encode_user_code(pin) + _le_bitmask([partition], 4)
        return await self._send_action(cmd, payload)

    async def disarm(self, pin: str, partition: int) -> bool:
        """Disarm a partition. Returns True if sent."""
        payload = _encode_user_code(pin) + _le_bitmask([partition], 4)
        return await self._send_action(CMD_DISARM, payload)

    async def bypass(self, pin: str, zones: list[int], on: bool) -> bool:
        """Bypass (on=True) or unbypass (on=False) the given zones."""
        cmd = CMD_ZONES_BYPASS if on else CMD_ZONES_UNBYP
        payload = _encode_user_code(pin) + _le_bitmask(zones, 16)
        return await self._send_action(cmd, payload)

    async def _send_action(self, cmd: int, payload: bytes) -> bool:
        if self._writer is None or not self._connected:
            log.warning("Satel: cannot send cmd 0x%02X – not connected", cmd)
            return False
        try:
            async with self._io_lock:
                if self._crypto is not None:
                    # Encrypted: strict request → single response exchange.
                    await self._exchange_encrypted(cmd, payload)
                else:
                    self._writer.write(_build_frame(cmd, payload))
                    await self._writer.drain()
            log.info("Satel: sent cmd 0x%02X", cmd)
            return True
        except Exception as exc:
            log.warning("Satel: failed to send cmd 0x%02X: %s", cmd, exc)
            return False

    # ------------------------------------------------------------------
    # Internal loop
    # ------------------------------------------------------------------

    async def _run(self) -> None:
        while True:
            try:
                await self._session()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                log.warning("Satel connection lost: %s – retrying in %.0fs",
                            exc, _CONNECT_RETRY)
            finally:
                self._connected = False
                self._crypto = None
                self._writer = None
                self._reader = None
            await asyncio.sleep(_CONNECT_RETRY)

    async def _session(self) -> None:
        log.info("Connecting to Satel %s:%s%s …", self.host, self.port,
                 " (encrypted)" if self.integration_key else "")
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(self.host, self.port),
            timeout=_CONNECT_RETRY,
        )
        self._reader = reader
        self._writer = writer
        self._buf = bytearray()
        self._armed_by_cmd.clear()
        self._exit_by_cmd.clear()
        # A fresh encryption handler per connection (rolling counter resets).
        self._crypto = (
            EncryptedCommunicationHandler(self.integration_key)
            if self.integration_key else None
        )
        self._connected = True
        log.info("Satel connected.")

        try:
            if self._crypto is not None:
                await self._poll_encrypted()
            else:
                await self._poll_plain()
        finally:
            self._writer = None
            self._reader = None
            self._crypto = None
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    # --- Plain-text polling -------------------------------------------------

    async def _poll_plain(self) -> None:
        assert self._reader and self._writer
        reader, writer = self._reader, self._writer
        loop = asyncio.get_event_loop()
        while True:
            async with self._io_lock:
                for cmd in _QUERY_CMDS:
                    writer.write(_build_frame(cmd))
                await writer.drain()

            deadline = loop.time() + _POLL_INTERVAL
            while loop.time() < deadline:
                try:
                    chunk = await asyncio.wait_for(
                        reader.read(512),
                        timeout=max(0.1, deadline - loop.time()),
                    )
                except asyncio.TimeoutError:
                    break
                if not chunk:
                    raise ConnectionResetError("EOF from Satel module")
                self._buf.extend(chunk)
                frames, self._buf = _parse_frames(self._buf)
                for frame in frames:
                    self._handle_frame(frame)

    # --- Encrypted polling --------------------------------------------------

    async def _poll_encrypted(self) -> None:
        while True:
            for cmd in _QUERY_CMDS:
                async with self._io_lock:
                    await self._exchange_encrypted(cmd)
            await asyncio.sleep(_POLL_INTERVAL)

    async def _exchange_encrypted(self, cmd: int, payload: bytes = b'') -> None:
        """Send one encrypted frame and read its single response PDU.

        Must be called while holding ``self._io_lock`` (mutates crypto state).
        """
        assert self._reader and self._writer and self._crypto
        reader, writer, crypto = self._reader, self._writer, self._crypto

        pdu = crypto.prepare_pdu(_build_frame(cmd, payload))
        writer.write(len(pdu).to_bytes(1, "big") + pdu)
        await writer.drain()

        len_byte = await asyncio.wait_for(reader.readexactly(1), _READ_TIMEOUT)
        data = await asyncio.wait_for(
            reader.readexactly(len_byte[0]), _READ_TIMEOUT)
        decrypted = crypto.extract_data_from_pdu(data)
        frames, _ = _parse_frames(bytearray(decrypted))
        for frame in frames:
            self._handle_frame(frame)

    # --- Frame handling -----------------------------------------------------

    def _handle_frame(self, body: bytes) -> None:
        if not body:
            return
        cmd     = body[0]
        payload = body[1:]

        if cmd == CMD_ZONES_VIOLATED:
            self.state.zones_violated = _bits_to_set(payload)
        elif cmd == CMD_ZONES_BYPASSED:
            self.state.zones_bypassed = _bits_to_set(payload)
        elif cmd in (CMD_PART_ARMED_MODE0, CMD_PART_ARMED_MODE1,
                     CMD_PART_ARMED_MODE2, CMD_PART_ARMED_MODE3):
            self._update_armed(cmd, _bits_to_set(payload))
        elif cmd == CMD_PART_ENTRY_TIME:
            self.state.partitions_entry = _bits_to_set(payload)
        elif cmd in (CMD_PART_EXIT_OVER_10, CMD_PART_EXIT_UNDER_10):
            self._update_exit(cmd, _bits_to_set(payload))
        elif cmd == CMD_NEW_DATA:
            pass  # command result / ack
        else:
            log.debug("Unhandled Satel cmd 0x%02X", cmd)

    def _update_armed(self, cmd: int, value: set[int]) -> None:
        self._armed_by_cmd[cmd] = value
        union: set[int] = set()
        for s in self._armed_by_cmd.values():
            union |= s
        self.state.partitions_armed = union

    def _update_exit(self, cmd: int, value: set[int]) -> None:
        self._exit_by_cmd[cmd] = value
        union: set[int] = set()
        for s in self._exit_by_cmd.values():
            union |= s
        self.state.partitions_exit = union
