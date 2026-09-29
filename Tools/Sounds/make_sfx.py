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

# ----------------------------------------------------------------------
# GRIDLOCK (floor 6, the level-maker's cube): bright chiptune blips, all
# squares and noise, on the beat
# ----------------------------------------------------------------------
def tone(freq, seconds, duty=0.5, vol=0.5, curve=2.0, attack=0.003):
    n = int(seconds * RATE)
    return square(np.cumsum(np.full(n, float(freq))) / RATE, duty) * env(n, attack, seconds, curve) * vol


def arp(notes, step, duty=0.5, vol=0.45, curve=1.5):
    return np.concatenate([tone(f, step, duty, vol, curve) for f in notes])


def gd_wake():  # the level starts: a rising arpeggio and a chord
    return mix(arp([262, 330, 392, 523, 659, 784], 0.07, 0.25), at(tone(523, 0.5, 0.5, 0.35, 1.2), 0.42),
               at(tone(659, 0.5, 0.25, 0.3, 1.2), 0.42), at(tone(784, 0.5, 0.125, 0.25, 1.2), 0.42))


def gd_hop():  # a hop: a quick upward chirp
    s = 0.12
    return square(sweep(300, 900, s), 0.25) * env(int(s * RATE), 0.002, s, 2) * 0.5


def gd_slam():  # landing hard: a low thump and a crunch
    s = 0.25
    n = int(s * RATE)
    return mix(tri(sweep(160, 40, s)) * env(n, 0.002, s, 2.5) * 0.9, crush(noise(n) * env(n, 0.001, 0.12, 4), 6) * 0.5)


def gd_spike():  # tiles spiking up: a sharp rising zip
    s = 0.18
    n = int(s * RATE)
    return mix(square(sweep(200, 1600, s), 0.125) * env(n, 0.002, s, 1.5) * 0.4, crush(noise(n) * env(n, 0.001, 0.06, 3), 4) * 0.3)


def gd_portal():  # changing form: a warbling whoosh up and down
    s = 0.6
    t = t_of(s)
    f = 400 + 500 * np.sin(np.pi * t / s) + 60 * np.sin(2 * np.pi * 18 * t)
    return square(np.cumsum(f) / RATE, 0.5) * env(len(t), 0.03, s, 1.2) * 0.4


def gd_ship():  # flying: a buzzing engine (loops well)
    s = 0.8
    t = t_of(s)
    f = 90 + 8 * np.sin(2 * np.pi * 6 * t)
    return mix(square(np.cumsum(f) / RATE, 0.3) * 0.35, crush(noise(len(t)), 5) * 0.08)


def gd_bomb():  # a bomb bursting: a noise pop with a falling tone
    s = 0.4
    n = int(s * RATE)
    return mix(crush(noise(n), 5) * env(n, 0.001, s, 3) * 0.7, square(sweep(500, 60, 0.3), 0.5) * env(int(0.3 * RATE), 0.001, 0.3, 2) * 0.4)


def gd_dive():  # the swoop: a long falling sweep
    s = 0.45
    return square(sweep(1400, 150, s), 0.25) * env(int(s * RATE), 0.01, s, 1.2) * 0.45


def gd_burst():  # a UFO hop: a springy double blip
    return mix(tone(660, 0.06, 0.25, 0.45), at(tone(990, 0.08, 0.25, 0.45), 0.06))


def gd_orb():  # an orb landing: a bright ping
    return mix(tone(1320, 0.25, 0.5, 0.4, 3), tone(1980, 0.18, 0.125, 0.2, 3))


def gd_zoom():  # the zig-zag: a fast up-down trill
    s = 0.5
    t = t_of(s)
    f = 600 + 400 * np.sign(np.sin(2 * np.pi * 14 * t))
    return square(np.cumsum(f) / RATE, 0.25) * env(len(t), 0.005, s, 1.3) * 0.35


def gd_build():  # the music building up: a rising stepped riser and a snare roll
    notes = [196, 220, 247, 262, 294, 330, 349, 392, 440, 494, 523, 587, 659, 698, 784, 880]
    rise = arp(notes, 0.11, 0.5, 0.3, 0.8)
    roll = np.concatenate([crush(noise(int(r * RATE)), 5) * env(int(r * RATE), 0.001, r, 3) * 0.25
                           for r in np.linspace(0.18, 0.04, 22)])
    return mix(rise, roll)


def gd_drop():  # THE DROP: a huge bass hit and a crash
    s = 1.0
    n = int(s * RATE)
    return mix(square(sweep(110, 45, s), 0.5) * env(n, 0.002, s, 1.8) * 0.8, crush(noise(n), 4) * env(n, 0.001, 0.6, 2.5) * 0.5,
               arp([523, 392, 262], 0.08, 0.25, 0.3))


def gd_stun():  # stunned: a wobbly, dizzy falling tone
    s = 0.9
    t = t_of(s)
    f = np.linspace(700, 250, len(t)) * (1 + 0.08 * np.sin(2 * np.pi * 9 * t))
    return square(np.cumsum(f) / RATE, 0.5) * env(len(t), 0.01, s, 1.2) * 0.35


def gd_flip():  # the gravity flip: a sweep that turns over itself
    return mix(square(sweep(200, 1200, 0.25), 0.25) * env(int(0.25 * RATE), 0.005, 0.25, 1) * 0.4,
               at(square(sweep(1200, 200, 0.25), 0.25) * env(int(0.25 * RATE), 0.005, 0.25, 1.5) * 0.4, 0.22))


def gd_pad():  # a jump pad: a boingy spring
    s = 0.3
    t = t_of(s)
    f = 250 + 700 * (t / s) + 120 * np.sin(2 * np.pi * 30 * t)
    return square(np.cumsum(f) / RATE, 0.125) * env(len(t), 0.002, s, 1.5) * 0.45


def gd_break():  # GRAVITY FLIP at half health: an alarm arpeggio and a flip
    alarm = np.concatenate([tone(880 if i % 2 == 0 else 660, 0.09, 0.5, 0.4, 0.8) for i in range(6)])
    return mix(alarm, at(gd_flip(), 0.5))


def gd_death():  # he shatters into cubes: a crash and falling blips
    s = 0.5
    n = int(s * RATE)
    parts = [crush(noise(n), 4) * env(n, 0.001, s, 2.5) * 0.6]
    for i, f in enumerate([1200, 980, 800, 640, 520, 420, 330, 260]):
        parts.append(at(tone(f, 0.07, 0.25, 0.35), 0.1 + i * 0.07))
    return mix(*parts)


def gd_attempt():  # "ATTEMPT 1": three countdown beeps and a go
    return mix(tone(440, 0.1, 0.5, 0.4), at(tone(440, 0.1, 0.5, 0.4), 0.3), at(tone(440, 0.1, 0.5, 0.4), 0.6),
               at(tone(880, 0.3, 0.5, 0.45, 1.2), 0.9))


def gd_complete():  # LEVEL COMPLETE!: a little victory jingle
    melody = [(523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.25), (784, 0.1), (1047, 0.45)]
    out = np.concatenate([tone(f, d, 0.25, 0.4, 1.0) for f, d in melody])
    bass = np.concatenate([tone(f, d, 0.5, 0.25, 1.0) for f, d in [(131, 0.3), (196, 0.35), (262, 0.45)]])
    return mix(out, bass)


SOUNDS = {
    'Sword Swing': sword_swing,
    'Sword Hit': sword_hit,
    'Hammer Slam': hammer_slam,
    'Dagger Slash': dagger_slash,
    'Token Clunk': coin_clunk,
    'Roll Tick': roll_tick,
    'Legendary Reveal': legendary_reveal,
    'Ability Aura': ability_aura,
    # Gridlock (floor 6): the names his Config.Bosses[6].Sounds asks for
    'Gridlock Wake': gd_wake,
    'Cube Hop': gd_hop,
    'Cube Slam': gd_slam,
    'Spikes Up': gd_spike,
    'Portal Whoosh': gd_portal,
    'Ship Thrust': gd_ship,
    'Bomb Drop': gd_bomb,
    'Ship Dive': gd_dive,
    'UFO Burst': gd_burst,
    'Orb Land': gd_orb,
    'Wave Zoom': gd_zoom,
    'Drop Build': gd_build,
    'The Drop': gd_drop,
    'Gridlock Stun': gd_stun,
    'Gravity Flip': gd_flip,
    'Jump Pad': gd_pad,
    'Gridlock Break': gd_break,
    'Gridlock Shatter': gd_death,
    'Attempt Start': gd_attempt,
    'Level Complete': gd_complete,
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
    import sys
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:]  # (optional: only names starting with these, e.g. Gridlock Cube)
    for name, fn in SOUNDS.items():
        if not want or any(name.startswith(w) for w in want):
            save(name, fn())
