"""Generate Carrom Duo's original, sample-free music and effects (CC0).

Run with Python 3; no third-party packages or downloaded samples are used.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "CarromDuo" / "Audio"
TAU = math.tau


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def note(freq, seconds, kind="wood", seed=0):
    rng = random.Random(seed)
    values = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        attack = min(1, t / 0.004)
        release = min(1, (seconds - t) / 0.04)
        if kind == "wood":
            value = (math.sin(TAU * freq * t) * math.exp(-5 * t)
                     + 0.28 * math.sin(TAU * freq * 2.76 * t) * math.exp(-12 * t)
                     + 0.12 * math.sin(TAU * freq * 4.1 * t) * math.exp(-22 * t))
        elif kind == "bass":
            value = math.sin(TAU * freq * t) * math.exp(-3.5 * t)
        elif kind == "shaker":
            value = rng.uniform(-1, 1) * math.exp(-55 * t) * 0.4
        elif kind == "kick":
            value = math.sin(TAU * (52 * t + 1.4 * (1 - math.exp(-35 * t)))) * math.exp(-22 * t)
        elif kind == "fall":
            value = (math.sin(TAU * freq * (t - 0.28 * t * t))
                     + 0.3 * math.sin(TAU * freq * 1.5 * t)) * math.exp(-3 * t)
        else:
            value = math.sin(TAU * freq * t) * math.exp(-6 * t)
        values.append(value * attack * max(0, release))
    return values


def mix(buffer, sound, at, gain=1, pan=0, loop=False):
    start = round(at * RATE)
    frames = len(buffer) // 2
    left, right = math.sqrt((1 - pan) / 2), math.sqrt((1 + pan) / 2)
    for index, value in enumerate(sound):
        frame = start + index
        if loop:
            frame %= frames
        elif frame >= frames:
            break
        buffer[frame * 2] += value * gain * left
        buffer[frame * 2 + 1] += value * gain * right


def save(name, buffer, peak=0.8):
    maximum = max(abs(x) for x in buffer) or 1
    scale = peak / maximum
    pcm = bytearray()
    for value in buffer:
        pcm.extend(struct.pack("<h", round(value * scale * 32767)))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


def theme(name, bpm, energetic):
    beat = 60 / bpm
    buffer = [0.0] * (round(32 * beat * RATE) * 2)
    roots = [48, 53, 57, 55, 48, 53, 50, 55]
    melody = [0, 7, 12, 4, 7, 16, 12, 7]
    for bar, root in enumerate(roots):
        for position in range(8):
            time = (bar * 4 + position * 0.5) * beat
            if energetic or position % 2 == 0:
                pitch = root + 12 + melody[(position + bar * 3) % len(melody)]
                mix(buffer, note(hz(pitch), 0.8), time, 0.19, (-1) ** position * 0.35, True)
            mix(buffer, note(1, 0.13, "shaker", bar * 8 + position), time, 0.035 if energetic else 0.018, 0.4, True)
        for position in [0, 2]:
            time = (bar * 4 + position) * beat
            mix(buffer, note(hz(root - 12), 0.9, "bass"), time, 0.19, -0.1, True)
            mix(buffer, note(1, 0.25, "kick"), time, 0.08 if energetic else 0.035, 0, True)
        for offset in [0, 4, 7]:
            mix(buffer, note(hz(root + offset), 1.5), bar * 4 * beat, 0.055, -0.45, True)
    save(name, buffer, 0.68)


def effect(name, events, duration):
    buffer = [0.0] * (round(duration * RATE) * 2)
    for time, pitch, length, kind, gain in events:
        mix(buffer, note(hz(pitch), length, kind, pitch), time, gain)
    save(name, buffer)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    theme("home_music", 92, False)
    theme("match_music", 108, True)
    effect("disc_hit", [(0, 76, 0.10, "wood", 1), (0, 12, 0.04, "shaker", 0.6)], 0.14)
    effect("cushion_hit", [(0, 48, 0.16, "wood", 1), (0, 10, 0.05, "shaker", 0.4)], 0.2)
    effect("coin_score", [(0, 76, 0.3, "wood", 0.7), (0.075, 83, 0.4, "wood", 1)], 0.55)
    effect("opponent_coin", [(0, 67, 0.3, "wood", 1), (0.14, 60, 0.4, "wood", 1)], 0.6)
    effect("striker_foul", [(0, 53, 0.55, "fall", 1), (0.08, 46, 0.6, "fall", 0.7)], 0.8)
    effect("opponent_disaster", [(0, 48, 0.8, "fall", 0.8), (0.13, 42, 0.9, "fall", 0.9),
                                  (0.32, 36, 0.7, "wood", 0.9)], 1.2)
    effect("queen_covered", [(i * 0.10, p, 0.5, "wood", 0.8) for i, p in enumerate([72, 76, 79, 84])], 0.95)
    effect("victory", [(i * 0.13, p, 0.7, "wood", 0.9) for i, p in enumerate([72, 76, 79, 84, 79, 84, 88])]
           + [(0.78, p, 1.1, "bass", 0.55) for p in [48, 55, 60]], 2.1)
    effect("defeat", [(i * 0.22, p, 0.85, "fall", 0.8) for i, p in enumerate([67, 63, 60, 48])], 1.75)


if __name__ == "__main__":
    main()
