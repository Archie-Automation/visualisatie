"""AES encryption for the Satel ETHM-1 / INT-ETHER integration protocol.

Encryption is OPTIONAL: it is only used when an integration key is configured
in DLOADX ("Encrypted integration"). With no key the plain-text transport is
used instead (see protocol.py).

The algorithm is the one published by Satel and is a faithful port of the
well-tested ``satel_integra`` reference library (MIT). Do not "simplify" it:
the panel will reject any deviation.

  * Key: the ASCII integration key is expanded to a 24-byte AES-192 key:
        key[i] = key[i + 12] = key_ascii[i]  (missing chars padded with 0x20)
  * Cipher: AES-192 in ECB mode, wrapped in a custom CBC-like chaining.
  * PDU: a 6-byte header (2 random, 2 rolling counter, id_s, id_r) is prepended
    to the message, the whole thing is encrypted, and on the wire it is sent as
    ``<1-byte length> <encrypted pdu>``.
"""

from __future__ import annotations

import os

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

BLOCK_LENGTH = 16


class SatelEncryption:
    """Low-level encrypt/decrypt for the Satel integration protocol."""

    def __init__(self, integration_key: str) -> None:
        encryption_key = self.integration_key_to_encryption_key(integration_key)
        self.cipher = Cipher(algorithms.AES(encryption_key), modes.ECB())

    @classmethod
    def integration_key_to_encryption_key(cls, integration_key: str) -> bytes:
        """Expand the ASCII integration key to the 24-byte AES-192 key."""
        key_bytes = bytes(integration_key, "ascii")
        key = [0] * 24
        for i in range(12):
            key[i] = key[i + 12] = key_bytes[i] if len(key_bytes) > i else 0x20
        return bytes(key)

    @staticmethod
    def _blocks(message: bytes, block_len: int) -> list[bytes]:
        return [message[i:i + block_len] for i in range(0, len(message), block_len)]

    def encrypt(self, data: bytes) -> bytes:
        if len(data) < BLOCK_LENGTH:
            data += b"\x00" * (BLOCK_LENGTH - len(data))
        out: list[int] = []
        encryptor = self.cipher.encryptor()
        cv = list(encryptor.update(bytes([0] * BLOCK_LENGTH)))
        for block in self._blocks(data, BLOCK_LENGTH):
            p = list(block)
            if len(block) == BLOCK_LENGTH:
                p = [a ^ b for a, b in zip(p, cv)]
                p = list(encryptor.update(bytes(p)))
                cv = list(p)
            else:
                cv = list(encryptor.update(bytes(cv)))
                p = [a ^ b for a, b in zip(p, cv)]
            out += p
        return bytes(out)

    def decrypt(self, data: bytes) -> bytes:
        out: list[int] = []
        encryptor = self.cipher.encryptor()
        decryptor = self.cipher.decryptor()
        cv = list(encryptor.update(bytes([0] * BLOCK_LENGTH)))
        for block in self._blocks(data, BLOCK_LENGTH):
            temp = list(block)
            c = list(block)
            if len(block) == BLOCK_LENGTH:
                c = list(decryptor.update(bytes(c)))
                c = [a ^ b for a, b in zip(c, cv)]
                cv = list(temp)
            else:
                cv = list(encryptor.update(bytes(cv)))
                c = [a ^ b for a, b in zip(c, cv)]
            out += c
        return bytes(out)


class EncryptedCommunicationHandler:
    """Wraps/unwraps Satel messages in encrypted PDUs with rolling counters."""

    next_id_s: int = 0

    def __init__(self, integration_key: str) -> None:
        self._rolling_counter: int = 0
        self._id_s: int = EncryptedCommunicationHandler.next_id_s
        EncryptedCommunicationHandler.next_id_s += 1
        self._id_r: int = 0
        self._enc = SatelEncryption(integration_key)

    def _prepare_header(self) -> bytes:
        header = (
            os.urandom(2)
            + self._rolling_counter.to_bytes(2, "big")
            + self._id_s.to_bytes(1, "big")
            + self._id_r.to_bytes(1, "big")
        )
        self._rolling_counter = (self._rolling_counter + 1) & 0xFFFF
        self._id_s = header[4]
        return header

    def prepare_pdu(self, message: bytes) -> bytes:
        """Return the encrypted PDU for a (plain, framed) message."""
        return self._enc.encrypt(self._prepare_header() + message)

    def extract_data_from_pdu(self, pdu: bytes) -> bytes:
        """Decrypt a PDU and return the framed message (header stripped)."""
        decrypted = self._enc.decrypt(pdu)
        header = decrypted[:6]
        data = decrypted[6:]
        self._id_r = header[4]
        if (self._id_s & 0xFF) != decrypted[5]:
            raise RuntimeError(
                f"Incorrect ID_S: received 0x{decrypted[5]:02x}, "
                f"expected 0x{self._id_s & 0xFF:02x} "
                "(wrong integration key or encryption mismatch?)"
            )
        return bytes(data)
