"""The weapons' sound effects: every weapon type's swing and hit, the Slime
pack's goo (the swings of the rarer ones, the splats, the Secret's jelly), and
the Slime abilities. Made from code like the rest (make_sfx.py's building
blocks: squares, noise, sweeps), a bit rounder and wetter for the goo.

    python3 weapon_sfx.py          -> out/weapons/<Name>.ogg (and .wav)

Tools/Upload/upload_assets.bat uploads out/weapons/*.ogg with the models;
ServerScriptService/SoundLoader puts each in SoundService under its name
("Goo_Splat" -> "Goo Splat"), which is what the game asks for.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_sfx as S  # noqa: E402
from make_sfx import RATE, t_of, env, sweep, square, tri, noise, lowpass, crush, mix, at  # noqa: E402

OUT = os.path.join(HERE, 'out', 'weapons')


def sine(phase):
    return np.sin(2 * np.pi * phase)


def n_of(seconds):
    return len(t_of(seconds))


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def whoosh(seconds, lo, hi, vol=1.4, curve=1.5):
    """air rushing past: noise through a filter that opens and closes"""
    n = n_of(seconds)
    shape = np.sin(np.linspace(0, np.pi, n))
    return lowpass(noise(n), lo + (hi - lo) * shape) * env(n, seconds * 0.3, seconds, curve) * vol


def squelch(seconds=0.18, f0=260, f1=70, vol=1.0):
    """wet goo: a falling rounded thump with a smacking bit of noise"""
    n = n_of(seconds)
    body = sine(sweep(f0, f1, seconds)) * env(n, 0.002, seconds, 2.2)
    smack = lowpass(noise(n), np.linspace(2600, 400, n)) * env(n, 0.001, seconds * 0.5, 4) * 0.8
    return (body + smack) * vol


def bloop(seconds=0.3, f0=220, f1=520, wobble=16, depth=0.08, vol=0.8):
    """a jelly bloop: a rising tone that wobbles"""
    t = t_of(seconds)
    n = len(t)
    f = f0 * (f1 / f0) ** (t / seconds) * (1 + depth * np.sin(2 * np.pi * wobble * t))
    return sine(np.cumsum(f) / RATE) * env(n, 0.01, seconds, 1.8) * vol


def fizz(seconds, vol=0.6):
    """acid: bright hissing noise with crackles"""
    n = n_of(seconds)
    hiss = highpass(noise(n), 3500) * env(n, 0.02, seconds, 1.4)
    crackle = (np.random.default_rng(3).random(n) > 0.9985) * np.random.default_rng(4).uniform(-1, 1, n) * 3
    return (hiss + lowpass(crackle, 5000)) * vol


def ring(freq, seconds, vol=0.25):
    """a blade's ring: a high square that fades, with a shimmer"""
    t = t_of(seconds)
    n = len(t)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 9 * t)
    return (square(np.cumsum(np.full(n, freq) * vib) / RATE, 0.25) + 0.5 * square(np.cumsum(np.full(n, freq * 1.5)) / RATE, 0.5)) \
        * env(n, 0.001, seconds, 2.5) * vol


def sparkle(start, count, gap=0.05, base=2600, vol=0.12):
    return mix(*[at(square(sweep(base + 350 * (i % 4), base, 0.05), 0.5) * env(n_of(0.05), 0.001, 0.05, 2) * vol, start + i * gap)
                 for i in range(count)])


# ----------------------------------------------------------------------
# the weapon types
# ----------------------------------------------------------------------
def hammer_swing():
    # a heavy, slow rush of air with a low hum under it
    s = 0.38
    hum = tri(sweep(70, 110, s)) * env(n_of(s), 0.12, s, 1.5) * 0.35
    return mix(whoosh(s, 150, 1600, 1.6), hum)


def hammer_hit():
    s = 0.4
    n = n_of(s)
    boom = tri(sweep(150, 45, s)) * env(n, 0.001, s, 2.6)
    crunch = lowpass(noise(n), np.linspace(3000, 300, n)) * env(n, 0.001, 0.25, 3) * 1.3
    clank = square(sweep(420, 260, 0.1), 0.5) * env(n_of(0.1), 0.001, 0.1, 3) * 0.35
    return crush(mix(boom, crunch, clank), 22)


def dagger_swing():
    # quick and light: a thin zip of air
    s = 0.1
    n = n_of(s)
    x = lowpass(noise(n), np.linspace(3500, 9000, n))
    zip_ = square(sweep(2200, 3800, s), 0.125) * 0.12
    return (x + zip_) * env(n, 0.004, s, 2) * 1.3


def scythe_swing():
    # a long wide sweep with a thin whistle riding on it
    s = 0.42
    whistle = sine(sweep(1100, 620, s)) * env(n_of(s), 0.12, s, 1.6) * 0.18
    return mix(whoosh(s, 250, 3200, 1.5), whistle)


def katana_swing():
    # a fast, sharp cut and the blade ringing after it ("shing")
    s = 0.16
    return mix(whoosh(s, 900, 7000, 1.4, 2.0), at(ring(2600, 0.35, 0.16), 0.05))


def whirlwind():
    # spinning round: a whoosh that pulses as the blade comes round
    s = 0.75
    t = t_of(s)
    pulse = 0.55 + 0.45 * np.sin(2 * np.pi * 9 * t) ** 2
    return whoosh(s, 300, 3600, 1.6, 1.2) * pulse


# ----------------------------------------------------------------------
# the Slime pack's swings (the rarer ones), the goo landing, hits
# ----------------------------------------------------------------------
def goo_swish():
    # a swing that flings goo: a whoosh and a wet flick at the end
    return mix(whoosh(0.22, 500, 4200, 1.3), at(squelch(0.12, 520, 180, 0.55), 0.12))


def goo_splat():
    return squelch(0.14, 300, 60, 1.0)


def acid_swish():
    return mix(whoosh(0.24, 700, 5200, 1.2), at(fizz(0.3, 0.5), 0.08))


def acid_hiss():
    return mix(fizz(0.5, 0.8), squelch(0.08, 400, 150, 0.35))


def jelly_swing():
    # the Secret: a deep whoosh, a big wobbly bloop and a sparkle
    s = 0.34
    return mix(whoosh(s, 200, 3000, 1.3), at(bloop(0.3, 180, 460, 14, 0.12, 0.7), 0.06),
               sparkle(0.12, 5, 0.035, 3000, 0.1), at(squelch(0.12, 500, 160, 0.4), 0.22))


def jelly_wave():
    # the jelly wave flying out: a wobbling "wub" and a rush
    s = 0.6
    t = t_of(s)
    n = len(t)
    f = (90 + 150 * (t / s)) * (1 + 0.18 * np.sin(2 * np.pi * 11 * t))
    wub = (sine(np.cumsum(f) / RATE) + 0.35 * square(np.cumsum(f) / RATE, 0.5)) * env(n, 0.02, s, 1.6) * 0.7
    return mix(wub, whoosh(s, 200, 1800, 0.9))


def eye_pop():
    # an eye popping out (a blip), then bursting (a squelch)
    blip = sine(sweep(500, 1300, 0.06)) * env(n_of(0.06), 0.002, 0.06, 1.5) * 0.6
    return mix(blip, at(squelch(0.12, 700, 200, 0.8), 0.07), at(squelch(0.1, 400, 120, 0.5), 0.13))


def goo_hit():
    # a slimy weapon landing: a crack and a big wet splat
    s = 0.3
    n = n_of(s)
    crack = lowpass(noise(n), 3200) * env(n, 0.001, 0.06, 5) * 1.0
    thud = tri(sweep(200, 70, s)) * env(n, 0.001, s, 3) * 0.6
    return mix(crack, thud, at(squelch(0.2, 320, 60, 0.9), 0.02))


# ----------------------------------------------------------------------
# the Slime abilities
# ----------------------------------------------------------------------
def goo_clap():
    # the gloves clapping together: a sharp smack and goo bursting out
    s = 0.08
    smack = lowpass(noise(n_of(s)), 6000) * env(n_of(s), 0.001, s, 5) * 1.4
    return mix(smack, at(squelch(0.25, 240, 50, 1.0), 0.01), at(bloop(0.18, 400, 700, 20, 0.1, 0.3), 0.08))


def jelly_wobble():
    # the jelly bubble going up and wobbling: a boing that settles
    s = 0.8
    t = t_of(s)
    n = len(t)
    f = 190 * (1 + 0.25 * np.sin(2 * np.pi * 7 * t) * np.exp(-3 * t))
    return (sine(np.cumsum(f) / RATE) + 0.25 * square(np.cumsum(f * 2) / RATE, 0.5)) * env(n, 0.01, s, 1.8) * 0.8


def goo_slam():
    # the hammer landing in goo: a huge low boom and a big wet splat
    s = 0.7
    n = n_of(s)
    boom = sine(sweep(120, 32, s)) * env(n, 0.001, s, 2.2) * 1.1
    crunch = lowpass(noise(n), np.linspace(2400, 200, n)) * env(n, 0.001, 0.35, 2.5) * 0.9
    return mix(boom, crunch, at(squelch(0.35, 280, 50, 1.0), 0.01), at(squelch(0.15, 500, 150, 0.4), 0.18))


def slime_dash():
    # darting through: a fast rush and a wet slide
    s = 0.3
    slide = lowpass(noise(n_of(s)), 900) * env(n_of(s), 0.05, s, 1.5) * 0.6
    return mix(whoosh(s, 800, 6000, 1.4, 1.8), slide)


def acid_fling():
    # three globs flung off: blorps and a hiss
    blorps = mix(*[at(bloop(0.12, 300 + 60 * i, 150, 22, 0.1, 0.6), i * 0.06) for i in range(3)])
    return mix(blorps, at(fizz(0.35, 0.35), 0.05))


def acid_burst():
    return mix(squelch(0.2, 350, 70, 1.0), at(fizz(0.45, 0.6), 0.03))


def blade_draw():
    # the katana coming out: a scrape rising, then the ring
    s = 0.3
    n = n_of(s)
    scrape = highpass(noise(n), np.linspace(1500, 5000, n)) * env(n, s * 0.8, s, 1.2) * 0.8
    return mix(scrape, at(ring(1900, 0.6, 0.22), 0.26))


def jaw_open():
    # Oozark's jaw rising: a deep growl rumbling up
    s = 0.55
    t = t_of(s)
    n = len(t)
    f = 48 + 30 * (t / s)
    growl = (square(np.cumsum(f) / RATE, 0.3) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))) * env(n, 0.15, s, 1.4)
    rumble = lowpass(noise(n), 300) * env(n, 0.1, s, 1.5) * 1.2
    return crush(mix(lowpass(growl, 900) * 0.8, rumble), 24)


def jaw_chomp():
    # the jaw snapping shut: two heavy crunching thuds and goo
    s = 0.35
    n = n_of(s)
    thud = tri(sweep(160, 40, s)) * env(n, 0.001, s, 2.6)
    crunch = lowpass(noise(n), np.linspace(4000, 400, n)) * env(n, 0.001, 0.18, 3) * 1.3
    return crush(mix(thud, crunch, at(thud * 0.6, 0.07), at(squelch(0.3, 260, 50, 0.9), 0.03)), 22)


WEAPON_SOUNDS = {
    # the weapon types (Config.Weapons.Types: Sounds)
    'Sword Swing': S.sword_swing,
    'Sword Hit': S.sword_hit,
    'Hammer Swing': hammer_swing,
    'Hammer Hit': hammer_hit,
    'Dagger Swing': dagger_swing,
    'Scythe Swing': scythe_swing,
    'Katana Swing': katana_swing,
    'Whirlwind': whirlwind,
    # the Slime pack's swings, goo and hits (WeaponFX "Swing effects by rarity")
    'Goo Swish': goo_swish,
    'Goo Splat': goo_splat,
    'Acid Swish': acid_swish,
    'Acid Hiss': acid_hiss,
    'Jelly Swing': jelly_swing,
    'Jelly Wave': jelly_wave,
    'Eye Pop': eye_pop,
    'Goo Hit': goo_hit,
    # the Slime abilities (MoveFX)
    'Goo Clap': goo_clap,
    'Jelly Wobble': jelly_wobble,
    'Goo Slam': goo_slam,
    'Slime Dash': slime_dash,
    'Acid Fling': acid_fling,
    'Acid Burst': acid_burst,
    'Blade Draw': blade_draw,
    'Jaw Open': jaw_open,
    'Jaw Chomp': jaw_chomp,
}


if __name__ == '__main__':
    S.OUT = OUT
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:]
    for name, fn in WEAPON_SOUNDS.items():
        if not want or any(name.startswith(w) for w in want):
            S.save(name, fn())
