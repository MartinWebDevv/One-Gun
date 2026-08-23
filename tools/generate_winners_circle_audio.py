"""Generate One Gun's retired prototype Winners Circle ceremony sting.

The cue is intentionally synthetic and lightweight: a mysterious 90s-arcade
bed, short left/right placement reveals, a rising champion orbit, and a final
rock-influenced Trophy impact. It is deterministic so the WAV can be rebuilt.
This script is retained for provenance and no longer writes over the approved
Ceremony March default.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from array import array
from pathlib import Path


SAMPLE_RATE = 44_100
DURATION = 10.0
FRAME_COUNT = int(SAMPLE_RATE * DURATION)
OUTPUT_PATH = (
    Path(__file__).resolve().parents[1]
    / "art_src"
    / "audio"
    / "winners_circle"
    / "retired_arcade_rock.wav"
)

left = array("f", [0.0]) * FRAME_COUNT
right = array("f", [0.0]) * FRAME_COUNT
random_source = random.Random(0x0E6A17)


def _pan_gains(pan: float) -> tuple[float, float]:
    angle = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi * 0.25
    return math.cos(angle), math.sin(angle)


def _envelope(time: float, duration: float, attack: float, release: float) -> float:
    if time < 0.0 or time >= duration:
        return 0.0
    attack_gain = min(time / max(attack, 0.0001), 1.0)
    release_gain = min((duration - time) / max(release, 0.0001), 1.0)
    return attack_gain * release_gain


def add_tone(
    start: float,
    duration: float,
    frequency: float,
    amplitude: float,
    *,
    pan: float = 0.0,
    attack: float = 0.015,
    release: float = 0.18,
    color: str = "arcade",
    bend: float = 0.0,
) -> None:
    first = max(0, int(start * SAMPLE_RATE))
    last = min(FRAME_COUNT, int((start + duration) * SAMPLE_RATE))
    left_gain, right_gain = _pan_gains(pan)
    phase = 0.0
    for frame in range(first, last):
        local_time = frame / SAMPLE_RATE - start
        progress = local_time / max(duration, 0.0001)
        current_frequency = frequency * (2.0 ** (bend * progress / 12.0))
        phase += math.tau * current_frequency / SAMPLE_RATE
        sine = math.sin(phase)
        if color == "bass":
            sample = sine + 0.24 * math.sin(phase * 2.0)
        elif color == "bell":
            sample = (
                0.68 * sine
                + 0.22 * math.sin(phase * 2.01)
                + 0.10 * math.sin(phase * 3.98)
            )
        else:
            sample = (
                0.72 * sine
                + 0.19 * math.sin(phase * 2.0)
                + 0.09 * math.sin(phase * 3.0)
            )
        value = sample * amplitude * _envelope(local_time, duration, attack, release)
        left[frame] += value * left_gain
        right[frame] += value * right_gain


def add_chord(
    start: float,
    duration: float,
    frequencies: tuple[float, ...],
    amplitude: float,
    *,
    pan: float = 0.0,
    attack: float = 0.035,
    release: float = 0.35,
) -> None:
    per_note = amplitude / math.sqrt(len(frequencies))
    spread = 0.16 if len(frequencies) > 1 else 0.0
    for index, frequency in enumerate(frequencies):
        note_pan = pan + (index - (len(frequencies) - 1) * 0.5) * spread
        add_tone(
            start,
            duration,
            frequency,
            per_note,
            pan=note_pan,
            attack=attack,
            release=release,
        )


def add_kick(start: float, amplitude: float = 0.34, pan: float = 0.0) -> None:
    duration = 0.42
    first = max(0, int(start * SAMPLE_RATE))
    last = min(FRAME_COUNT, int((start + duration) * SAMPLE_RATE))
    left_gain, right_gain = _pan_gains(pan)
    phase = 0.0
    for frame in range(first, last):
        local_time = frame / SAMPLE_RATE - start
        frequency = 118.0 * math.exp(-local_time * 9.5) + 42.0
        phase += math.tau * frequency / SAMPLE_RATE
        value = math.sin(phase) * math.exp(-local_time * 10.5) * amplitude
        left[frame] += value * left_gain
        right[frame] += value * right_gain


def add_snare(start: float, amplitude: float = 0.11, pan: float = 0.0) -> None:
    duration = 0.22
    first = max(0, int(start * SAMPLE_RATE))
    last = min(FRAME_COUNT, int((start + duration) * SAMPLE_RATE))
    left_gain, right_gain = _pan_gains(pan)
    previous = 0.0
    for frame in range(first, last):
        local_time = frame / SAMPLE_RATE - start
        noise = random_source.uniform(-1.0, 1.0)
        bright = noise - previous * 0.72
        previous = noise
        body = math.sin(math.tau * 176.0 * local_time) * 0.26
        value = (bright * 0.74 + body) * math.exp(-local_time * 18.0) * amplitude
        left[frame] += value * left_gain
        right[frame] += value * right_gain


def add_whoosh(start: float, duration: float, amplitude: float, pan_start: float, pan_end: float) -> None:
    first = max(0, int(start * SAMPLE_RATE))
    last = min(FRAME_COUNT, int((start + duration) * SAMPLE_RATE))
    low_pass = 0.0
    for frame in range(first, last):
        local_time = frame / SAMPLE_RATE - start
        progress = local_time / duration
        noise = random_source.uniform(-1.0, 1.0)
        alpha = 0.025 + 0.32 * math.sin(progress * math.pi) ** 2
        low_pass += (noise - low_pass) * alpha
        shaped = noise - low_pass * (0.72 - progress * 0.22)
        gain = math.sin(progress * math.pi) ** 1.4
        left_gain, right_gain = _pan_gains(pan_start + (pan_end - pan_start) * progress)
        value = shaped * gain * amplitude
        left[frame] += value * left_gain
        right[frame] += value * right_gain


def add_metal_hit(start: float, amplitude: float = 0.20) -> None:
    for frequency, weight, pan in (
        (530.0, 1.0, -0.12),
        (811.0, 0.68, 0.12),
        (1289.0, 0.38, 0.0),
        (2039.0, 0.22, 0.18),
    ):
        add_tone(
            start,
            1.65,
            frequency,
            amplitude * weight,
            pan=pan,
            attack=0.001,
            release=1.5,
            color="bell",
        )


# Quiet ominous arcade bed under the full camera move.
for frequency in (82.41, 123.47, 164.81):
    add_tone(0.0, 9.75, frequency, 0.032, attack=0.30, release=0.80, color="bass")

# Third place: bronze pulse from the right side of the stage.
add_chord(0.05, 2.0, (164.81, 196.00, 246.94), 0.18, pan=0.34)
for time in (0.10, 0.95, 1.75):
    add_kick(time, 0.26, 0.28)
for index, frequency in enumerate((329.63, 392.00, 493.88, 587.33, 493.88)):
    add_tone(0.35 + index * 0.32, 0.42, frequency, 0.055, pan=0.30, color="bell")

# Fast camera swish into second place, followed by a silver chord on the left.
add_whoosh(1.96, 0.76, 0.105, 0.75, -0.78)
add_kick(2.60, 0.32, -0.26)
add_chord(2.61, 1.95, (146.83, 196.00, 246.94, 293.66), 0.20, pan=-0.34)
add_snare(3.18, 0.10, -0.28)
add_kick(3.72, 0.24, -0.22)
for index, frequency in enumerate((293.66, 392.00, 440.00, 493.88)):
    add_tone(2.83 + index * 0.34, 0.45, frequency, 0.048, pan=-0.30, color="bell")

# Champion orbit: a rising arcade-rock build that moves toward center stage.
add_whoosh(4.18, 1.05, 0.082, -0.62, 0.12)
orbit_notes = (164.81, 196.00, 246.94, 329.63, 392.00, 493.88, 659.25, 783.99)
for index, frequency in enumerate(orbit_notes):
    note_time = 4.30 + index * 0.43
    note_pan = -0.42 + index * 0.12
    add_tone(note_time, 0.52, frequency, 0.060, pan=note_pan, color="arcade")
for time in (4.35, 5.20, 6.05, 6.90, 7.56):
    add_kick(time, 0.26)
for time in (4.78, 5.63, 6.48, 7.33):
    add_snare(time, 0.095)

# Trophy drop and champion hero shot at the eight-second mark.
add_whoosh(7.52, 0.50, 0.070, 0.0, 0.0)
add_kick(7.98, 0.50)
add_metal_hit(8.00, 0.17)
add_chord(7.98, 1.82, (82.41, 164.81, 196.00, 246.94, 329.63), 0.30)
for index, frequency in enumerate((987.77, 1174.66, 1318.51, 1567.98, 1975.53)):
    add_tone(
        8.12 + index * 0.28,
        0.78,
        frequency,
        0.045 - index * 0.004,
        pan=(-0.45 + index * 0.22),
        attack=0.002,
        release=0.68,
        color="bell",
    )

# Gentle stereo echo taps make the final hit feel larger without a reverb asset.
for delay, scale in ((0.12, 0.35), (0.24, 0.20), (0.38, 0.11)):
    offset = int(delay * SAMPLE_RATE)
    for frame in range(offset, FRAME_COUNT):
        left[frame] += right[frame - offset] * scale
        right[frame] += left[frame - offset] * scale * 0.92

# Fade cleanly, soft-limit, and normalize to a conservative peak.
peak = 0.0
for frame in range(FRAME_COUNT):
    master_fade = min(1.0, frame / (SAMPLE_RATE * 0.02))
    remaining = (FRAME_COUNT - frame) / SAMPLE_RATE
    if remaining < 0.42:
        master_fade *= max(0.0, remaining / 0.42)
    left[frame] = math.tanh(left[frame] * 1.18) * master_fade
    right[frame] = math.tanh(right[frame] * 1.18) * master_fade
    peak = max(peak, abs(left[frame]), abs(right[frame]))

normalization = 0.91 / max(peak, 0.0001)
OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUTPUT_PATH), "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(SAMPLE_RATE)
    frames = bytearray()
    for frame in range(FRAME_COUNT):
        sample_left = int(max(-1.0, min(1.0, left[frame] * normalization)) * 32767.0)
        sample_right = int(max(-1.0, min(1.0, right[frame] * normalization)) * 32767.0)
        frames.extend(struct.pack("<hh", sample_left, sample_right))
    output.writeframes(frames)

print(f"WINNERS_CIRCLE_AUDIO={OUTPUT_PATH}")
print(f"DURATION_SECONDS={DURATION:.2f}")
print(f"SAMPLE_RATE={SAMPLE_RATE}")
