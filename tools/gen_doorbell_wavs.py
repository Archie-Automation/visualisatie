import math
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(r"C:\Users\gebruiker\KNX app\app\android\app\src\main\res\raw")


def clamp(x: float) -> int:
    v = int(round(x * 32767.0))
    return max(-32767, min(32767, v))


def write_wav(name: str, samples: list[float]) -> None:
    peak = max((abs(s) for s in samples), default=1.0)
    gain = 0.72 / peak if peak > 0 else 1.0
    path = OUT / name
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", clamp(s * gain)) for s in samples)
        w.writeframes(frames)
    print(f"{path.name} {path.stat().st_size} bytes {len(samples) / SR:.2f}s")


def silence(ms: int) -> list[float]:
    return [0.0] * int(SR * ms / 1000)


def bell(
    freq: float,
    ms: int,
    amp: float,
    *,
    decay: float,
    inharmonic: float = 0.0,
    brightness: float = 1.0,
    wooden: bool = False,
) -> list[float]:
    n = int(SR * ms / 1000)
    out = [0.0] * n
    partials = [
        (1.0, 1.0),
        (2.01, 0.38 * brightness),
        (2.76 if inharmonic else 3.01, 0.16 * brightness),
        (4.07 if inharmonic else 4.02, 0.09 * brightness),
        (5.43 if inharmonic else 5.04, 0.045 * brightness),
        (6.79 if inharmonic else 6.05, 0.02 * brightness),
    ]
    if wooden:
        partials = [
            (1.0, 1.0),
            (2.0, 0.22),
            (3.01, 0.08),
            (4.2, 0.03),
        ]
        decay *= 1.35
    for i in range(n):
        t = i / SR
        env = math.exp(-t * decay)
        # strike click
        click = math.exp(-t * 90.0) * 0.12 * brightness
        s = click * math.sin(2 * math.pi * freq * 8 * t)
        for k, a in partials:
            f = freq * k * (1.0 + inharmonic * 0.004 * k)
            s += a * math.sin(2 * math.pi * f * t)
        out[i] = amp * env * s
    return out


def mix(*parts: list[float]) -> list[float]:
    n = sum(len(p) for p in parts)
    out: list[float] = []
    for p in parts:
        out.extend(p)
    assert len(out) == n
    return out


def classic_ding_dong() -> list[float]:
    # Warm G5 then E5, studio-clean two-tone.
    return mix(
        bell(783.99, 520, 0.95, decay=3.6, brightness=1.05),
        silence(90),
        bell(659.25, 1100, 1.0, decay=2.8, brightness=0.95),
        silence(1600),
    )


def modern_chime() -> list[float]:
    # Soft double ping, smart-home UI.
    ping = lambda f, a: bell(f, 220, a, decay=9.5, brightness=0.55, wooden=False)
    return mix(
        ping(987.77, 0.7),
        silence(70),
        ping(1174.66, 0.62),
        silence(1800),
    )


def mechanical_brass() -> list[float]:
    # Resonant brass ding-dong, inharmonic bell metal.
    return mix(
        bell(698.46, 480, 1.0, decay=3.1, inharmonic=1.0, brightness=1.25),
        silence(80),
        bell(523.25, 1400, 1.05, decay=2.4, inharmonic=1.15, brightness=1.1),
        silence(1400),
    )


def friendly_melody() -> list[float]:
    # Three-note wooden C5–E5–G5.
    note = lambda f, ms, a: bell(f, ms, a, decay=4.8, brightness=0.7, wooden=True)
    return mix(
        note(523.25, 280, 0.78),
        silence(40),
        note(659.25, 280, 0.82),
        silence(40),
        note(783.99, 700, 0.88),
        silence(1500),
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write_wav("doorbell_chime.wav", classic_ding_dong())
    write_wav("doorbell_modern.wav", modern_chime())
    write_wav("doorbell_brass.wav", mechanical_brass())
    write_wav("doorbell_melody.wav", friendly_melody())
    # Keep legacy raw name so older R.raw.doorbell still packs.
    write_wav("doorbell.wav", classic_ding_dong())


if __name__ == "__main__":
    main()
