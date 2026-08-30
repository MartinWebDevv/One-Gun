"""Generate the short captionless startup cinematic rock cue.

This is deterministic and uses full-resolution PCM synthesis: double-tracked
distorted power chords, electric-bass harmonics, kick, snare, hats, toms, and a
final crash. It intentionally leaves the five-shot montage region sparse so the
runtime gunshots provide the dominant rhythmic accents.
"""

from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


RATE = 44_100
DURATION = 6.6
FRAMES = int(RATE * DURATION)
OUTPUT = Path(__file__).resolve().parents[1] / "audio" / "ui" / "startup_five_shot_rock.wav"
RNG = np.random.default_rng(17491)

left = np.zeros(FRAMES, dtype=np.float64)
right = np.zeros(FRAMES, dtype=np.float64)


def _range(start: float, duration: float) -> tuple[int, np.ndarray]:
    first = max(0, int(start * RATE))
    count = min(int(duration * RATE), FRAMES - first)
    return first, np.arange(count, dtype=np.float64) / RATE


def _add_stereo(start: float, signal_l: np.ndarray, signal_r: np.ndarray) -> None:
    first = max(0, int(start * RATE))
    count = min(len(signal_l), len(signal_r), FRAMES - first)
    if count <= 0:
        return
    left[first : first + count] += signal_l[:count]
    right[first : first + count] += signal_r[:count]


def _cabinet(signal: np.ndarray) -> np.ndarray:
    # Short asymmetric FIR: removes brittle synthesized highs while retaining
    # the pick edge and distorted midrange of a small guitar cabinet.
    kernel = np.array([0.05, 0.09, 0.14, 0.18, 0.19, 0.15, 0.10, 0.06, 0.025])
    return np.convolve(signal, kernel, mode="same")


def add_power_chord(start: float, root: float, duration: float,
                    amplitude: float, palm_muted: bool = False) -> None:
    _, t = _range(start, duration)
    if not len(t):
        return

    def track(detune: float, seed_shift: int) -> np.ndarray:
        frequencies = (root, root * 1.5, root * 2.0)
        raw = np.zeros_like(t)
        for note_index, frequency in enumerate(frequencies):
            frequency *= detune
            phase = (note_index * 0.73) + seed_shift * 0.19
            # A harmonic-rich string signal before the amp stage.
            for harmonic in range(1, 10):
                weight = (1.0 / harmonic) * (0.92 ** harmonic)
                raw += np.sin(2.0 * math.pi * frequency * harmonic * t + phase) * weight
        pick = RNG.normal(0.0, 1.0, len(t)) * np.exp(-t * 54.0) * 0.22
        envelope = np.minimum(t / 0.006, 1.0)
        if palm_muted:
            envelope *= np.exp(-t * 8.2)
        else:
            envelope *= np.clip(1.0 - t / max(duration * 1.55, 0.01), 0.0, 1.0) ** 0.44
        driven = np.tanh((raw * 0.42 + pick) * 3.6)
        return _cabinet(driven) * envelope

    guitar_l = track(0.996, 0)
    guitar_r = track(1.004, 1)
    # Double tracking is separated, not hard-panned, so it stays substantial
    # on laptop speakers and survives mono playback.
    _add_stereo(start, guitar_l * amplitude, guitar_r * amplitude)


def add_bass(start: float, frequency: float, duration: float, amplitude: float) -> None:
    _, t = _range(start, duration)
    envelope = np.minimum(t / 0.008, 1.0) * np.exp(-t * 1.35)
    string = (
        np.sin(2.0 * math.pi * frequency * t)
        + np.sin(2.0 * math.pi * frequency * 2.0 * t) * 0.34
        + np.sin(2.0 * math.pi * frequency * 3.0 * t) * 0.13
    )
    string = np.tanh(string * 1.45) * envelope * amplitude
    _add_stereo(start, string, string)


def add_kick(start: float, amplitude: float = 1.0) -> None:
    _, t = _range(start, 0.30)
    phase = 2.0 * math.pi * (48.0 * t + 56.0 * (1.0 - np.exp(-t * 30.0)) / 30.0)
    body = np.sin(phase) * np.exp(-t * 14.0)
    click = RNG.normal(0.0, 1.0, len(t)) * np.exp(-t * 85.0) * 0.20
    signal = (body + click) * amplitude * 0.72
    _add_stereo(start, signal, signal)


def add_snare(start: float, amplitude: float = 1.0) -> None:
    _, t = _range(start, 0.28)
    noise = RNG.normal(0.0, 1.0, len(t))
    # First difference removes low-frequency rumble from the noise component.
    noise = np.concatenate(([0.0], np.diff(noise)))
    wire = noise * np.exp(-t * 15.5) * 0.34
    shell = np.sin(2.0 * math.pi * 184.0 * t) * np.exp(-t * 19.0) * 0.33
    signal = (wire + shell) * amplitude
    _add_stereo(start, signal * 0.94, signal)


def add_hat(start: float, open_hat: bool = False, amplitude: float = 1.0) -> None:
    duration = 0.25 if open_hat else 0.075
    _, t = _range(start, duration)
    noise = RNG.normal(0.0, 1.0, len(t))
    high = np.concatenate(([0.0], np.diff(noise)))
    decay = 18.0 if open_hat else 58.0
    signal = high * np.exp(-t * decay) * amplitude * 0.12
    _add_stereo(start, signal * 0.72, signal)


def add_tom(start: float, frequency: float, amplitude: float = 1.0) -> None:
    _, t = _range(start, 0.34)
    pitch_fall = frequency * t + 19.0 * (1.0 - np.exp(-t * 17.0)) / 17.0
    signal = np.sin(2.0 * math.pi * pitch_fall) * np.exp(-t * 11.0) * amplitude * 0.46
    _add_stereo(start, signal, signal * 0.95)


def add_crash(start: float, amplitude: float = 1.0) -> None:
    _, t = _range(start, 1.45)
    noise = RNG.normal(0.0, 1.0, len(t))
    high = np.concatenate(([0.0], np.diff(noise)))
    metallic = (
        np.sin(2.0 * math.pi * 3_117.0 * t)
        + np.sin(2.0 * math.pi * 4_903.0 * t) * 0.7
        + np.sin(2.0 * math.pi * 6_317.0 * t) * 0.45
    )
    signal = (high * 0.23 + metallic * 0.08) * np.exp(-t * 2.7) * amplitude
    _add_stereo(start, signal, signal * 0.92)


# 150 BPM opening riff: low, palm-muted, and increasingly assertive while Blue
# moves toward the gun.
riff = [
    (0.00, 82.41), (0.40, 82.41), (0.80, 98.00), (1.20, 110.00),
    (1.60, 82.41), (2.00, 123.47),
]
for index, (start, root) in enumerate(riff):
    add_power_chord(start, root, 0.34, 0.18 + index * 0.012, palm_muted=True)
    add_bass(start, root / 2.0, 0.34, 0.25)

# Sparse sustained bed beneath the elimination montage. The runtime gunshots are
# intentionally allowed to become the strongest transients in this section.
add_power_chord(2.32, 82.41, 1.86, 0.13, palm_muted=False)
add_bass(2.32, 41.205, 1.70, 0.22)

# Blue-alone build and final logo chord.
add_power_chord(4.20, 98.00, 0.42, 0.20, palm_muted=True)
add_power_chord(4.60, 110.00, 0.42, 0.22, palm_muted=True)
add_power_chord(5.02, 82.41, 1.52, 0.31, palm_muted=False)
add_bass(5.02, 41.205, 1.44, 0.31)

# A humanized rock pulse. The shot accents are reinforced by low toms rather
# than synthetic beeps or melody notes.
for step in range(29):
    position = step * 0.20 + RNG.uniform(-0.005, 0.005)
    add_hat(position, open_hat=(step in (7, 19, 27)), amplitude=0.70 + RNG.uniform(-0.08, 0.08))
for position in (0.0, 0.8, 1.6, 2.0, 4.2, 5.02):
    add_kick(position, 0.95)
for position in (0.4, 1.2, 2.0, 4.6):
    add_snare(position, 0.82)
for index, position in enumerate((2.46, 2.88, 3.26, 3.60, 3.94)):
    add_tom(position, 116.0 - index * 7.5, 0.66 + index * 0.025)
add_kick(5.02, 1.15)
add_snare(5.02, 0.70)
add_crash(5.02, 0.78)

# Gentle crossfeed and soft limiting preserve punch without clipping.
mixed_l = left * 0.93 + right * 0.07
mixed_r = right * 0.93 + left * 0.07
peak = max(float(np.max(np.abs(mixed_l))), float(np.max(np.abs(mixed_r))), 1e-9)
gain = min(0.88 / peak, 1.0)
mixed = np.column_stack((mixed_l * gain, mixed_r * gain))
pcm = np.asarray(np.clip(mixed, -1.0, 1.0) * 32767.0, dtype="<i2")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUTPUT), "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(RATE)
    output.writeframes(pcm.tobytes())

print(f"Wrote {OUTPUT} ({DURATION:.1f}s, peak={peak:.3f}, gain={gain:.3f})")
