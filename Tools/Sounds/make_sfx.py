"""The game's sound effects, made from code: retro 8-bit style (square waves,
noise, pitch sweeps), so they suit the pixel look and are all our own.

    python3 make_sfx.py            -> out/<name>.ogg (and .wav) for every sound below

Needs numpy; the .ogg files also need imageio-ffmpeg. Upload the .ogg files to
Roblox and give them the names in the list (e.g. "Sword Swing").
"""
import os, subprocess, wave
import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
rng = np.random.default_rng(7)


def t_of(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(n, attack=0.005, decay=None, curve=3.0):
    """A quick attack, then a fall away (curve: bigger = snappier)."""
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    length = decay or (n / RATE)
    d = np.clip(1 - (t - attack) / max(length - attack, 1e-4), 0, 1) ** curve
    return a * d


def sweep(f0, f1, seconds, shape='exp'):
    t = t_of(seconds)
    k = t / seconds
    f = f0 * (f1 / f0) ** k if shape == 'exp' else f0 + (f1 - f0) * k
    return np.cumsum(f) / RATE


def square(phase, duty=0.5):
    return np.where((phase % 1.0) < duty, 1.0, -1.0)


def tri(phase):
    return 4 * np.abs((phase % 1.0) - 0.5) - 1


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, cutoff):
    """A one-pole low-pass; `cutoff` can be a number or an array (a sweep)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def crush(x, steps=16):
    """8-bit grit: fewer loudness steps."""
    return np.round(x * steps) / steps


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, seconds):
    return np.concatenate([np.zeros(int(seconds * RATE)), x])


# ----------------------------------------------------------------------
# the sounds
# ----------------------------------------------------------------------
def sword_swing():
    s = 0.22
    n = len(t_of(s))
    x = lowpass(noise(n), np.linspace(900, 5200, n) * np.sin(np.linspace(0, np.pi, n)) + 300)
    return x * env(n, 0.03, s, 1.5) * 1.6


def sword_hit():
    s = 0.25
    n = len(t_of(s))
    ping = square(sweep(1400, 700, s), 0.25) * env(n, 0.001, 0.12, 4) * 0.35
    crack = lowpass(noise(n), 3500) * env(n, 0.001, 0.07, 5) * 1.2
    thud = tri(sweep(220, 80, s)) * env(n, 0.001, s, 3) * 0.7
    return crush(mix(ping, crack, thud), 24)


def hammer_slam():
    s = 0.6
    n = len(t_of(s))
    boom = tri(sweep(140, 38, s)) * env(n, 0.002, s, 2.5)
    dust = lowpass(noise(n), np.linspace(2500, 200, n)) * env(n, 0.003, 0.45, 2) * 1.4
    crack = square(sweep(300, 60, 0.12), 0.5) * env(len(t_of(0.12)), 0.001, 0.12, 3) * 0.4
    return crush(mix(boom, dust, crack), 20) * 0.9


def dagger_slash():
    s = 0.12
    n = len(t_of(s))
    x = lowpass(noise(n), np.linspace(3000, 8000, n))
    zip_ = square(sweep(1800, 3200, s), 0.125) * 0.15
    return (x + zip_) * env(n, 0.005, s, 2) * 1.3


def coin_clunk():
    # a token going into the arcade machine: a clunk, a rattle, a ding
    clunk = tri(sweep(180, 90, 0.1)) * env(len(t_of(0.1)), 0.001, 0.1, 3)
    rattle = mix(*[at(lowpass(noise(len(t_of(0.02))), 4000) * 0.4, 0.06 + i * 0.045) for i in range(4)])
    ding = square(sweep(1318, 1318, 0.35), 0.5) * env(len(t_of(0.35)), 0.002, 0.35, 2) * 0.25
    return crush(mix(clunk, rattle, at(ding, 0.26)), 20)


def roll_tick():
    s = 0.04
    n = len(t_of(s))
    return square(sweep(2200, 1800, s), 0.25) * env(n, 0.001, s, 3) * 0.35


def legendary_reveal():
    # a rising arpeggio and a shimmering chord (the full-screen reveal)
    notes = [523, 659, 784, 1046, 1318, 1568]
    parts = []
    for i, f in enumerate(notes):
        s = 0.12
        parts.append(at(square(sweep(f, f, s), 0.25) * env(len(t_of(s)), 0.002, s, 1.5) * 0.3, i * 0.07))
    chord_s = 1.1
    n = len(t_of(chord_s))
    chord = sum(square(sweep(f * (1 + 0.004 * np.sin(k)), f, chord_s), 0.5) for k, f in enumerate([1046, 1318, 1568])) / 3
    vib = 1 + 0.3 * np.sin(2 * np.pi * 7 * t_of(chord_s))
    parts.append(at(chord * vib * env(n, 0.01, chord_s, 1.8) * 0.35, 0.42))
    sparkle = mix(*[at(square(sweep(3000 + 400 * (i % 3), 3000, 0.05), 0.5) * env(len(t_of(0.05)), 0.001, 0.05, 2) * 0.12,
                       0.45 + i * 0.09) for i in range(8)])
    return crush(mix(*parts, sparkle), 24)


def ability_aura():
    # a buff turning on: a rising whoosh with a hum
    s = 0.5
    n = len(t_of(s))
    rise = lowpass(noise(n), np.linspace(300, 4000, n)) * env(n, 0.25, s, 1.2) * 0.9
    hum = square(sweep(110, 220, s), 0.5) * env(n, 0.05, s, 1.5) * 0.2
    return mix(rise, hum)


SOUNDS = {
    'Sword Swing': sword_swing,
    'Sword Hit': sword_hit,
    'Hammer Slam': hammer_slam,
    'Dagger Slash': dagger_slash,
    'Token Clunk': coin_clunk,
    'Roll Tick': roll_tick,
    'Legendary Reveal': legendary_reveal,
    'Ability Aura': ability_aura,
}


def save(name, x):
    x = x / max(1e-6, np.max(np.abs(x))) * 0.85
    x = np.concatenate([np.zeros(int(0.005 * RATE)), x, np.zeros(int(0.02 * RATE))])
    path = os.path.join(OUT, name.replace(' ', '_'))
    with wave.open(path + '.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    try:
        import imageio_ffmpeg
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', path + '.wav',
                        '-c:a', 'libvorbis', '-q:a', '6', path + '.ogg'], check=True)
    except Exception as e:  # (no ffmpeg: the .wav is still there)
        print('no .ogg for', name, e)
    print('saved', path)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, fn in SOUNDS.items():
        save(name, fn())
