"""Generate the live-instrument-style arena-chase startup cue.

The deterministic PCM arrangement uses distorted double-tracked guitars,
electric bass, kick, snare, toms, hats and cymbal crashes. There are no chip
oscillators or retro-game melody voices. Runtime gunshots occupy the deliberate
gaps in the arrangement and remain the strongest action transients.
"""

from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


RATE = 44_100
DURATION = 12.2
FRAMES = int(RATE * DURATION)
OUTPUT = Path(__file__).resolve().parents[1] / "audio" / "ui" / "startup_arena_chase_rock.wav"
RNG = np.random.default_rng(918247)
LEFT = np.zeros(FRAMES, dtype=np.float64)
RIGHT = np.zeros(FRAMES, dtype=np.float64)


def timeline(start: float, duration: float) -> np.ndarray:
    first = max(0, int(start * RATE))
    count = min(int(duration * RATE), FRAMES - first)
    return np.arange(max(count, 0), dtype=np.float64) / RATE


def add(start: float, signal_l: np.ndarray, signal_r: np.ndarray) -> None:
    first = max(0, int(start * RATE))
    count = min(len(signal_l), len(signal_r), FRAMES - first)
    if count > 0:
        LEFT[first:first + count] += signal_l[:count]
        RIGHT[first:first + count] += signal_r[:count]


def cabinet(signal: np.ndarray) -> np.ndarray:
    kernel = np.array([0.035, 0.075, 0.13, 0.18, 0.20, 0.17, 0.11, 0.065, 0.035])
    return np.convolve(signal, kernel, mode="same")


def power_chord(start: float, root: float, duration: float,
                level: float, muted: bool = False) -> None:
    t = timeline(start, duration)
    if not len(t):
        return

    def guitar(detune: float, phase_shift: float) -> np.ndarray:
        raw = np.zeros_like(t)
        for note_index, frequency in enumerate((root, root * 1.5, root * 2.0)):
            for harmonic in range(1, 10):
                weight = (0.93 ** harmonic) / harmonic
                raw += np.sin(2.0 * math.pi * frequency * detune * harmonic * t
                              + phase_shift + note_index * 0.68) * weight
        pick = RNG.normal(0.0, 1.0, len(t)) * np.exp(-t * 58.0) * 0.19
        envelope = np.minimum(t / 0.006, 1.0)
        envelope *= np.exp(-t * 8.4) if muted else np.clip(
            1.0 - t / max(duration * 1.55, 0.01), 0.0, 1.0) ** 0.40
        return cabinet(np.tanh((raw * 0.42 + pick) * 3.7)) * envelope

    add(start, guitar(0.996, 0.0) * level, guitar(1.004, 0.23) * level)


def bass(start: float, frequency: float, duration: float, level: float) -> None:
    t = timeline(start, duration)
    envelope = np.minimum(t / 0.008, 1.0) * np.exp(-t * 1.28)
    tone = (np.sin(2.0 * math.pi * frequency * t)
            + 0.34 * np.sin(2.0 * math.pi * frequency * 2.0 * t)
            + 0.12 * np.sin(2.0 * math.pi * frequency * 3.0 * t))
    signal = np.tanh(tone * 1.42) * envelope * level
    add(start, signal, signal)


def kick(start: float, level: float = 1.0) -> None:
    t = timeline(start, 0.30)
    phase = 2.0 * math.pi * (47.0 * t + 58.0 * (1.0 - np.exp(-t * 30.0)) / 30.0)
    body = np.sin(phase) * np.exp(-t * 14.0)
    click = RNG.normal(0.0, 1.0, len(t)) * np.exp(-t * 88.0) * 0.18
    signal = (body + click) * level * 0.70
    add(start, signal, signal)


def snare(start: float, level: float = 1.0) -> None:
    t = timeline(start, 0.29)
    noise = np.concatenate(([0.0], np.diff(RNG.normal(0.0, 1.0, len(t)))))
    wire = noise * np.exp(-t * 15.0) * 0.33
    shell = np.sin(2.0 * math.pi * 181.0 * t) * np.exp(-t * 18.5) * 0.34
    signal = (wire + shell) * level
    add(start, signal * 0.94, signal)


def hat(start: float, level: float = 1.0, open_hat: bool = False) -> None:
    t = timeline(start, 0.24 if open_hat else 0.075)
    noise = np.concatenate(([0.0], np.diff(RNG.normal(0.0, 1.0, len(t)))))
    signal = noise * np.exp(-t * (18.0 if open_hat else 60.0)) * level * 0.105
    add(start, signal * 0.74, signal)


def tom(start: float, frequency: float, level: float = 1.0) -> None:
    t = timeline(start, 0.36)
    fall = frequency * t + 20.0 * (1.0 - np.exp(-t * 16.0)) / 16.0
    signal = np.sin(2.0 * math.pi * fall) * np.exp(-t * 10.5) * level * 0.46
    add(start, signal, signal * 0.95)


def crash(start: float, level: float = 1.0) -> None:
    t = timeline(start, 1.55)
    high = np.concatenate(([0.0], np.diff(RNG.normal(0.0, 1.0, len(t)))))
    metal = (np.sin(2.0 * math.pi * 3117.0 * t)
             + 0.70 * np.sin(2.0 * math.pi * 4903.0 * t)
             + 0.44 * np.sin(2.0 * math.pi * 6317.0 * t))
    signal = (high * 0.22 + metal * 0.075) * np.exp(-t * 2.55) * level
    add(start, signal, signal * 0.92)


# 136 BPM. The opening palm-muted chase riff expands into sustained chords as
# the survivors reach the weapon lanes.
beat = 60.0 / 136.0
roots = [82.41, 82.41, 98.00, 110.00, 82.41, 123.47, 110.00, 98.00]
for index in range(20):
    start = index * beat * 0.5
    root = roots[index % len(roots)]
    power_chord(start, root, beat * 0.43, 0.16 + 0.012 * min(index, 7), muted=True)
    bass(start, root / 2.0, beat * 0.48, 0.23)

# Weapon-lane reveal and three duel phrases. Short spaces at 2.65, 4.75, 7.05,
# 8.25 and 9.45 seconds leave the actual gunshots exposed.
for start, root, duration, level in (
    (4.15, 82.41, 0.82, 0.20),
    (5.05, 98.00, 0.74, 0.20),
    (5.86, 110.00, 0.72, 0.22),
    (6.42, 82.41, 0.46, 0.23),
    (7.42, 98.00, 0.46, 0.24),
    (8.61, 110.00, 0.46, 0.25),
    (9.82, 82.41, 0.52, 0.27),
    (10.38, 82.41, 1.72, 0.34),
):
    power_chord(start, root, duration, level, muted=duration < 0.55)
    bass(start, root / 2.0, min(duration, 1.35), level + 0.06)

# Humanized drums stay energetic without competing with the five shots.
shot_gaps = (2.55, 4.80, 7.08, 8.30, 9.51, 11.08)
for step in range(52):
    position = step * beat * 0.5 + RNG.uniform(-0.006, 0.006)
    if all(abs(position - gap) > 0.12 for gap in shot_gaps):
        hat(position, 0.66 + RNG.uniform(-0.07, 0.08), open_hat=step in (15, 31, 47))
for position in np.arange(0.0, 11.2, beat * 2.0):
    kick(float(position), 0.92)
for position in np.arange(beat, 10.8, beat * 2.0):
    snare(float(position), 0.78)
for index, position in enumerate((4.18, 4.40, 4.62, 6.58, 6.78, 6.96, 10.42, 10.64, 10.86)):
    tom(position, 126.0 - (index % 3) * 12.0, 0.62 + (index % 3) * 0.04)
kick(10.38, 1.12)
snare(10.38, 0.76)
crash(10.38, 0.82)

# Crossfeed, conservative peak, and 16-bit stereo PCM for direct Godot import.
mixed_l = LEFT * 0.93 + RIGHT * 0.07
mixed_r = RIGHT * 0.93 + LEFT * 0.07
peak = max(float(np.max(np.abs(mixed_l))), float(np.max(np.abs(mixed_r))), 1e-9)
gain = min(0.86 / peak, 1.0)
mixed = np.column_stack((mixed_l * gain, mixed_r * gain))
pcm = np.asarray(np.clip(mixed, -1.0, 1.0) * 32767.0, dtype="<i2")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUTPUT), "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(RATE)
    output.writeframes(pcm.tobytes())

print(f"Wrote {OUTPUT} ({DURATION:.1f}s, peak={peak:.3f}, gain={gain:.3f})")

