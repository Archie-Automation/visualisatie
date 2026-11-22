"""Alarmpiepen op 4100 Hz.

Langzaam: één piep per seconde. Snel: vier piepen per seconde.
Uitschakelen: twee piepen. Ingeschakeld na uitloop: twee seconden aan één stuk.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import wave

import numpy as np
from imageio_ffmpeg import get_ffmpeg_exe

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSET_DIR = os.path.join(ROOT, "assets", "sounds")
RAW_DIR = os.path.join(ROOT, "android", "app", "src", "main", "res", "raw")
SR = 44100
FREQ = 4100.0


def _tone(seconds: float) -> np.ndarray:
    n = int(round(seconds * SR))
    t = np.arange(n, dtype=np.float32) / SR
    # Vierkant-achtig, niet een dunne sinus. Zelfde grondtoon.
    wave_sq = np.tanh(6.0 * np.sin(2.0 * np.pi * FREQ * t))
    attack = int(0.006 * SR)
    release = int(0.025 * SR)
    env = np.ones(n, dtype=np.float32)
    if attack > 0:
        env[:attack] = np.linspace(0.0, 1.0, attack, dtype=np.float32)
    if release > 0 and release < n:
        env[-release:] *= np.linspace(1.0, 0.0, release, dtype=np.float32)
    return wave_sq * env * 0.9


def _loop(beep: float, period: float) -> np.ndarray:
    clip = np.zeros(int(round(period * SR)), dtype=np.float32)
    tone = _tone(beep)
    clip[: len(tone)] = tone
    return clip


def _double() -> np.ndarray:
    beep = _tone(0.18)
    gap = np.zeros(int(round(0.14 * SR)), dtype=np.float32)
    return np.concatenate([beep, gap, beep])


def _write_wav(path: str, clip: np.ndarray) -> None:
    pcm = np.clip(clip, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())


def _mp3(wav_path: str, mp3_path: str) -> None:
    ffmpeg = get_ffmpeg_exe()
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-i",
            wav_path,
            "-codec:a",
            "libmp3lame",
            "-q:a",
            "2",
            mp3_path,
        ],
        check=True,
        capture_output=True,
    )


def main() -> None:
    os.makedirs(ASSET_DIR, exist_ok=True)
    os.makedirs(RAW_DIR, exist_ok=True)
    outputs = {
        "alarm_delay_slow.mp3": _loop(0.22, 1.0),
        "alarm_delay_fast.mp3": _loop(0.16, 0.25),
        "alarm_ack_double.mp3": _double(),
        "alarm_armed_tone.mp3": _tone(2.0),
    }
    tmp = os.path.join(ASSET_DIR, "_tmp.wav")
    for name, clip in outputs.items():
        _write_wav(tmp, clip)
        asset = os.path.join(ASSET_DIR, name)
        _mp3(tmp, asset)
        shutil.copy2(asset, os.path.join(RAW_DIR, name))
        print(f"{name} {len(clip) / SR:.3f}s")
    os.remove(tmp)


if __name__ == "__main__":
    main()
