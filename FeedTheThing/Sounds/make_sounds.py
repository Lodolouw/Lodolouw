"""
Feed the Thing in the Basement - every sound effect, made from scratch in code
(so they're 100% ours: no licences, no copyright claims).

    python make_sounds.py          (needs: pip install numpy scipy soundfile)

Writes one .ogg per sound next to this file. The names match the ones the
game plays (UI.sound("Chomp") etc). Upload them (Asset Manager > bulk import,
or Tools/upload_assets.py with an Open Cloud key) and put the ids in
Config.Sounds.
"""

import os

import numpy as np
import soundfile as sf
from scipy.signal import butter, lfilter

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)


# ---------------------------------------------------------------------------
# building blocks
# ---------------------------------------------------------------------------
def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def tone(freq, seconds, kind="sine", phase=0.0):
    """freq may be a number or an array (a sweep)."""
    t = t_axis(seconds)
    f = np.broadcast_to(np.asarray(freq, dtype=float), t.shape)
    ph = 2 * np.pi * np.cumsum(f) / RATE + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "square":
        return np.sign(np.sin(ph)) * 0.6
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if kind == "triangle":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1) - 1) - 1
    raise ValueError(kind)


def sweep(f0, f1, seconds, curve=1.0):
    k = np.linspace(0, 1, int(seconds * RATE)) ** curve
    return f0 + (f1 - f0) * k


def noise(seconds):
    return rng.uniform(-1, 1, int(seconds * RATE))


def env(n, attack=0.005, decay=0.2, sustain=0.0, release=0.05, hold=0.0):
    """attack / hold / exponential decay to `sustain` / release, n samples long."""
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.where(t < attack + hold, 1.0, sustain + (1 - sustain) * np.exp(-(t - attack - hold) / max(decay, 1e-4)))
    r = np.clip((n / RATE - t) / max(release, 1e-4), 0, 1)
    return a * d * r


def bell(freq, seconds, decay=0.3, partials=((1, 1.0), (2.0, 0.35), (3.01, 0.15), (4.2, 0.08))):
    out = np.zeros(int(seconds * RATE))
    for mult, amp in partials:
        out += amp * tone(freq * mult, seconds) * env(len(out), 0.002, decay / mult ** 0.5)
    return out


def lowpass(x, cutoff, order=2):
    b, a = butter(order, cutoff / (RATE / 2), "low")
    return lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = butter(order, cutoff / (RATE / 2), "high")
    return lfilter(b, a, x)


def bandpass(x, low, high, order=2):
    b, a = butter(order, [low / (RATE / 2), high / (RATE / 2)], "band")
    return lfilter(b, a, x)


def moving_bandpass(x, centres, width=0.6, blocks=48):
    """A band-pass whose centre moves (for whooshes), done block by block."""
    out = np.zeros_like(x)
    edges = np.linspace(0, len(x), blocks + 1).astype(int)
    for i in range(blocks):
        a, b = edges[i], edges[i + 1]
        c = centres[min(len(centres) - 1, (a + b) // 2)]
        lo, hi = max(40, c * (1 - width)), min(RATE / 2 - 100, c * (1 + width))
        out[a:b] = bandpass(x[max(0, a - 512):b], lo, hi)[-(b - a):]
    return out


def place(*parts):
    """Mix (start_seconds, signal) pairs into one track."""
    end = max(int(s * RATE) + len(sig) for s, sig in parts)
    out = np.zeros(end)
    for s, sig in parts:
        i = int(s * RATE)
        out[i:i + len(sig)] += sig
    return out


def echo(x, delay=0.11, feedback=0.35, taps=4):
    out = np.copy(x)
    pad = np.zeros(int(delay * RATE * taps) + len(x))
    pad[:len(x)] = x
    for k in range(1, taps + 1):
        d = int(delay * RATE * k)
        pad[d:d + len(x)] += x * feedback ** k
    return pad if len(pad) > len(out) else out


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=float)
    x = x - np.mean(x)
    fade = min(len(x), int(0.01 * RATE))
    x[-fade:] *= np.linspace(1, 0, fade)
    m = np.max(np.abs(x)) or 1
    x = x / m * peak
    path = os.path.join(HERE, name + ".ogg")
    sf.write(path, x.astype(np.float32), RATE, format="OGG", subtype="VORBIS")
    print(f"  {name:10s} {len(x) / RATE:4.2f}s")


NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def note(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


# ---------------------------------------------------------------------------
# the sounds
# ---------------------------------------------------------------------------
def click():
    s = 0.06
    return tone(1500, s) * env(int(s * RATE), 0.001, 0.012) + 0.3 * highpass(noise(s), 3000) * env(int(s * RATE), 0.0005, 0.004)


def pop():
    s = 0.12
    body = tone(sweep(380, 1100, s, 0.6), s) * env(int(s * RATE), 0.002, 0.04)
    snap = 0.4 * highpass(noise(s), 2500) * env(int(s * RATE), 0.0005, 0.006)
    return body + snap


def coin():
    a = bell(note("B", 5), 0.12, 0.08)
    b = bell(note("E", 6), 0.5, 0.18)
    return place((0, a), (0.07, b))


def chomp():
    # two quick bites: a low thump and a crunchy burst each
    def bite(gain):
        s = 0.16
        thump = tone(sweep(130, 45, s, 0.5), s) * env(int(s * RATE), 0.002, 0.05)
        crunch = bandpass(noise(s), 900, 4200) * env(int(s * RATE), 0.001, 0.03)
        return gain * (0.9 * thump + 0.8 * crunch)
    return place((0, bite(1.0)), (0.11, bite(0.75)))


def throw():
    s = 0.32
    x = noise(s)
    centres = sweep(500, 2600, s, 0.7)
    w = moving_bandpass(x, centres, 0.5)
    return w * np.sin(np.linspace(0, np.pi, len(w))) ** 1.5


def perfect():
    notes = [note("C", 6), note("E", 6), note("G", 6), note("C", 7)]
    parts = [(i * 0.055, 0.8 * bell(f, 0.5, 0.2)) for i, f in enumerate(notes)]
    shimmer = 0.25 * highpass(noise(0.6), 6000) * env(int(0.6 * RATE), 0.05, 0.2)
    return place(*parts, (0.05, shimmer))


def combo():
    return place((0, bell(note("A", 5), 0.45, 0.16)), (0.03, 0.5 * bell(note("E", 6), 0.4, 0.14)))


def crack():
    parts = []
    for i in range(6):
        s = 0.03 + rng.uniform(0, 0.03)
        burst = highpass(noise(s), 1800) * env(int(s * RATE), 0.0005, 0.008)
        parts.append((i * 0.035 + rng.uniform(0, 0.015), burst * rng.uniform(0.5, 1)))
    return place(*parts)


def chord(notes, seconds, decay=0.6, spread=0.0):
    return place(*[(i * spread, bell(f, seconds, decay)) for i, f in enumerate(notes)])


def hatch():
    whoosh = 0.7 * throw()
    sparkle = chord([note("C", 5), note("E", 5), note("G", 5), note("C", 6)], 1.4, 0.5, 0.04)
    return echo(place((0, whoosh), (0.12, sparkle)), 0.12, 0.25, 3)


def hatch_rare():
    up = chord([note("G", 4), note("C", 5), note("E", 5), note("G", 5), note("C", 6), note("E", 6)], 1.0, 0.25, 0.07)
    hit = chord([note("C", 5), note("E", 5), note("G", 5), note("C", 6), note("E", 6)], 2.2, 0.9)
    shimmer = 0.3 * highpass(noise(1.6), 5000) * env(int(1.6 * RATE), 0.2, 0.6)
    return echo(place((0, 0.7 * up), (0.45, hit), (0.45, shimmer)), 0.13, 0.3, 4)


def size_up():
    s = 1.0
    rumble = lowpass(noise(s), 120, 4) * 3 + 0.5 * tone(42, s)
    rumble *= env(int(s * RATE), 0.2, 0.5)
    rise = 0.4 * tone(sweep(200, 900, 0.8, 1.6), 0.8, "triangle") * env(int(0.8 * RATE), 0.05, 0.6)
    fanfare = chord([note("C", 5), note("G", 5), note("C", 6), note("E", 6)], 1.8, 0.8)
    return echo(place((0, rumble), (0.35, rise), (1.05, fanfare)), 0.14, 0.25, 3)


def buy():
    clack = 0.6 * highpass(noise(0.05), 2000) * env(int(0.05 * RATE), 0.0005, 0.01)
    return place((0, clack), (0.03, bell(note("E", 6), 0.25, 0.1)), (0.12, bell(note("A", 6), 0.6, 0.22)))


def burp():
    s = 0.55
    f = 85 + 18 * np.sin(np.linspace(0, 9, int(s * RATE))) + sweep(20, -15, s)
    voice = tone(f, s, "saw")
    voice = lowpass(voice, 700, 2) + 0.4 * bandpass(voice, 300, 900)
    wobble = 0.65 + 0.35 * np.sin(np.linspace(0, 40, int(s * RATE)))
    return voice * wobble * env(int(s * RATE), 0.03, 0.3, 0.3, 0.12)


def error():
    a = tone(220, 0.12, "square") * env(int(0.12 * RATE), 0.002, 0.06)
    b = tone(165, 0.18, "square") * env(int(0.18 * RATE), 0.002, 0.09)
    return lowpass(place((0, a), (0.1, b)), 2500)


def announce():
    return echo(place((0, bell(note("G", 5), 0.6, 0.25)), (0.14, bell(note("D", 6), 0.9, 0.35))), 0.15, 0.2, 2)


def honk():
    s = 0.42
    bend = sweep(1.03, 0.98, s)
    a = tone(349 * bend, s, "square") + tone(440 * bend, s, "square")
    a = lowpass(a, 1800, 2) * env(int(s * RATE), 0.01, 0.4, 0.9, 0.06)
    return place((0, 0.8 * a[: int(0.16 * RATE)] * env(int(0.16 * RATE), 0.005, 0.2, 0.9, 0.03)), (0.2, a))


def thud():
    s = 0.25
    body = tone(sweep(95, 38, s, 0.4), s) * env(int(s * RATE), 0.001, 0.08)
    box = 0.5 * lowpass(noise(s), 600) * env(int(s * RATE), 0.001, 0.04)
    return body + box


def poof():
    s = 0.4
    puff = lowpass(noise(s), 1500) * env(int(s * RATE), 0.004, 0.09)
    sparkle = 0.25 * place(*[(0.05 + i * 0.04, bell(f, 0.25, 0.08)) for i, f in enumerate([note("E", 6), note("G", 6), note("C", 7)])])
    return place((0, puff), (0, sparkle))


SOUNDS = {
    "Click": click, "Pop": pop, "Coin": coin, "Chomp": chomp, "Throw": throw, "Perfect": perfect,
    "Combo": combo, "Crack": crack, "Hatch": hatch, "HatchRare": hatch_rare, "SizeUp": size_up,
    "Buy": buy, "Burp": burp, "Error": error, "Announce": announce, "Honk": honk, "Thud": thud, "Poof": poof,
}

if __name__ == "__main__":
    print("Sounds:")
    for name, make in SOUNDS.items():
        save(name, make())
