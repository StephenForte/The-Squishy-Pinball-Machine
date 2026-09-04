#!/usr/bin/env python3
"""Generate committed SFX WAVs: 22050 Hz, 16-bit mono, stdlib wave+math only."""

from __future__ import annotations

import math
import os
import wave

RATE = 22050
AMP = 0.58


def _pcm16(sample: float) -> bytes:
    clamped = max(-1.0, min(1.0, sample))
    value = int(round(clamped * 32767.0))
    if value > 32767:
        value = 32767
    if value < -32767:
        value = -32767
    return value.to_bytes(2, "little", signed=True)


def _envelope(index: int, count: int, attack: float, release: float) -> float:
    if count <= 1:
        return 0.0
    t = index / RATE
    dur = count / RATE
    if t < attack:
        return t / attack if attack > 0.0 else 1.0
    remaining = dur - t
    if remaining < release:
        return remaining / release if release > 0.0 else 0.0
    return 1.0


def _sine(phase: float) -> float:
    return math.sin(phase)


def _triangle(phase: float) -> float:
    unit = (phase / (2.0 * math.pi)) % 1.0
    if unit < 0.5:
        return unit * 4.0 - 1.0
    return 3.0 - unit * 4.0


def _render(
    duration: float,
    wave_fn,
    freq_start: float,
    freq_end: float,
    amp: float = AMP,
    attack: float = 0.008,
    release: float = 0.045,
) -> list[float]:
    count = int(round(duration * RATE))
    samples: list[float] = []
    phase = 0.0
    dt = 1.0 / RATE
    for i in range(count):
        mix = i / (count - 1) if count > 1 else 0.0
        freq = freq_start + (freq_end - freq_start) * mix
        phase += 2.0 * math.pi * freq * dt
        env = _envelope(i, count, attack, release)
        samples.append(wave_fn(phase) * amp * env)
    return samples


def _silence(duration: float) -> list[float]:
    return [0.0] * int(round(duration * RATE))


def _write(path: str, samples: list[float]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = bytearray()
    for sample in samples:
        frames.extend(_pcm16(sample))
    with wave.open(path, "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(bytes(frames))


def _flipper() -> list[float]:
    return _render(0.09, _triangle, 190.0, 320.0, amp=0.50, attack=0.004, release=0.03)


def _bumper() -> list[float]:
    return _render(0.14, _sine, 210.0, 340.0, amp=0.62, attack=0.006, release=0.05)


def _target() -> list[float]:
    return _render(0.11, _sine, 520.0, 780.0, amp=0.48, attack=0.004, release=0.04)


def _all_targets() -> list[float]:
    notes = [
        _render(0.08, _sine, 392.0, 392.0, amp=0.46, attack=0.005, release=0.02),
        _silence(0.012),
        _render(0.08, _sine, 494.0, 494.0, amp=0.46, attack=0.005, release=0.02),
        _silence(0.012),
        _render(0.12, _sine, 587.0, 740.0, amp=0.50, attack=0.005, release=0.05),
    ]
    out: list[float] = []
    for part in notes:
        out.extend(part)
    return out


def _drain() -> list[float]:
    return _render(0.22, _triangle, 280.0, 90.0, amp=0.42, attack=0.01, release=0.07)


def _game_over() -> list[float]:
    head = _render(0.16, _sine, 330.0, 196.0, amp=0.40, attack=0.012, release=0.04)
    tail = _render(0.22, _triangle, 196.0, 98.0, amp=0.36, attack=0.008, release=0.08)
    return head + _silence(0.02) + tail


def _big_score() -> list[float]:
    notes = [
        _render(0.09, _sine, 392.0, 440.0, amp=0.44, attack=0.006, release=0.025),
        _silence(0.01),
        _render(0.09, _sine, 494.0, 523.0, amp=0.46, attack=0.006, release=0.025),
        _silence(0.01),
        _render(0.16, _sine, 587.0, 784.0, amp=0.50, attack=0.006, release=0.06),
    ]
    out: list[float] = []
    for part in notes:
        out.extend(part)
    return out


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "sfx")
    sounds = {
        "flipper": _flipper(),
        "bumper": _bumper(),
        "target": _target(),
        "all_targets": _all_targets(),
        "drain": _drain(),
        "game_over": _game_over(),
        "big_score": _big_score(),
    }
    for name, samples in sounds.items():
        path = os.path.join(out_dir, "%s.wav" % name)
        _write(path, samples)
        nbytes = os.path.getsize(path)
        if nbytes >= 100 * 1024:
            raise SystemExit("%s is %d bytes; must be under 100 KB" % (path, nbytes))
        print("wrote %s bytes=%d samples=%d" % (path, nbytes, len(samples)))


if __name__ == "__main__":
    main()
