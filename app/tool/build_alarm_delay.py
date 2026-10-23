"""Rebuild the exit-delay beep: slow chirp, fast only in the last 3 seconds.

The source is a 7s clip that switches to continuous beeps after 4.4s.
This keeps one slow chirp as a seamless 1s loop and a 3s fast tail.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import wave

import miniaudio
import numpy as np
from imageio_ffmpeg import get_ffmpeg_exe

SRC = r"C:\Users\gebruiker\Downloads\alarm_in_uitloop.mp3"
BACKUP = r"C:\Users\gebruiker\Downloads\alarm_in_uitloop_origineel.mp3"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSET_DIR = os.path.join(ROOT, "assets", "sounds")
RAW_DIR = os.path.join(ROOT, "android", "app", "src", "main", "res", "raw")


def _decode() -> tuple[np.ndarray, int]:
    snd = miniaudio.decode_file(SRC)
    samples = np.frombuffer(snd.samples, dtype=np.int16).astype(np.float32)
    samples /= 32768.0
    if snd.nchannels == 2:
        samples = samples.reshape(-1, 2).mean(axis=1)
    return samples, snd.sample_rate


def _slice(samples: np.ndarray, sr: int, start: float, count: int) -> np.ndarray:
    i0 = int(round(start * sr))
    return samples[i0 : i0 + count].copy()


def _fade(clip: np.ndarray, sr: int) -> None:
    fade = int(0.004 * sr)
    ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)
    clip[:fade] *= ramp
    clip[-fade:] *= ramp[::-1]


def _write_wav(path: str, clip: np.ndarray, sr: int) -> None:
    pcm = np.clip(clip, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sr)
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
            "5",
            mp3_path,
        ],
        check=True,
        capture_output=True,
    )


def main() -> None:
    if not os.path.exists(BACKUP):
        shutil.copy2(SRC, BACKUP)

    samples, sr = _decode()
    slow = _slice(samples, sr, 0.90, sr)
    fast_unit = _slice(samples, sr, 4.366, sr // 2)
    fast = np.tile(fast_unit, 6)
    _fade(slow, sr)
    _fade(fast, sr)

    peak = max(float(np.max(np.abs(slow))), float(np.max(np.abs(fast))), 1e-6)
    gain = 0.85 / peak
    slow *= gain
    fast *= gain

    preview = np.concatenate([np.tile(slow, 5), fast])
    os.makedirs(ASSET_DIR, exist_ok=True)
    os.makedirs(RAW_DIR, exist_ok=True)

    tmp = os.path.join(ASSET_DIR, "_tmp.wav")
    outputs = {
        "alarm_delay_slow.mp3": slow,
        "alarm_delay_fast.mp3": fast,
    }
    for name, clip in outputs.items():
        _write_wav(tmp, clip, sr)
        asset = os.path.join(ASSET_DIR, name)
        raw = os.path.join(RAW_DIR, name)
        _mp3(tmp, asset)
        shutil.copy2(asset, raw)

    _write_wav(tmp, preview, sr)
    _mp3(tmp, SRC)
    os.remove(tmp)
    print(
        f"slow {len(slow) / sr:.3f}s fast {len(fast) / sr:.3f}s "
        f"preview {len(preview) / sr:.3f}s gain {gain:.1f}"
    )


if __name__ == "__main__":
    main()
