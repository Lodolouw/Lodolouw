"""The weapons' sound effects: every weapon type's swing and hit, the Slime
pack's goo (the swings of the rarer ones, the splats, the Secret's jelly), and
the Slime abilities. Made from code like the rest (make_sfx.py's building
blocks: squares, noise, sweeps), a bit rounder and wetter for the goo.

Then the next two packs', the same way (their swings, what the swings throw
off and hit, and their abilities):
  * the Knight pack (Knight Burrowmore): a heavy shovel's swish and clang,
    dirt clods, gold chimes and coins, a pogo's boing, anchors on chains,
    armour cracking into gold and a meteor
  * the Speedway pack (Speedy Revvington): tyres, sparks, flames, engines
    revving, nitro, pistons, a horn, and the race's start lights and
    finish-line fanfare

    python3 weapon_sfx.py              -> out/weapons/<Name>.ogg (and .wav)
    python3 weapon_sfx.py Knight Goo   ...only the Knight pack's and the ones
                                          starting with "Goo"

Tools/Upload/upload_assets.bat uploads out/weapons/*.ogg with the models;
ServerScriptService/SoundLoader puts each in SoundService under its name
("Goo_Splat" -> "Goo Splat"), which is what the game asks for.
"""
import os
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_sfx as S  # noqa: E402
import arcade_sfx as A  # noqa: E402
from make_sfx import RATE, t_of, env, sweep, square, tri, noise, lowpass, crush, mix, at  # noqa: E402
from arcade_sfx import midi  # noqa: E402

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


# ======================================================================
# THE KNIGHT AND SPEEDWAY PACKS
# ======================================================================
def own_noise(name):
    """each of these packs' sounds gets its own noise, so it comes out the
    same whichever ones are made (the sounds above share make_sfx's noise in
    order, as they always have - so these are made after them)"""
    s = zlib.crc32(name.encode())
    S.rng = np.random.default_rng(s)
    A.rng = np.random.default_rng(s + 1)


def band(x, lo=None, hi=None, order=2):
    """a clean filter (arcade_sfx's): cuts what's below `lo` and/or above `hi`"""
    return A.shape(x, hi=hi, lo=lo, order=order)[:len(x)]


def smooth(x, seconds):
    """x with its corners rounded off (an average over `seconds`)"""
    m = max(1, n_of(seconds))
    return np.convolve(np.pad(x, (m // 2, m - 1 - m // 2), mode='edge'), np.ones(m) / m, mode='valid')


def blep(t, dt):
    # (rounds off each jump of a pulse wave, so high notes don't fizz)
    out = np.zeros_like(t)
    a = t < dt
    u = t[a] / dt[a]
    out[a] = 2 * u - u * u - 1
    b = t > 1 - dt
    u = (t[b] - 1) / dt[b]
    out[b] = u * u + 2 * u + 1
    return out


def pulse(freq, n, duty=0.5):
    """a clean 8-bit pulse wave, n samples long (`freq`: a number, or one a
    sample), centred on zero (a narrow pulse would otherwise thump as it
    starts and stops)"""
    dt = np.broadcast_to(np.asarray(freq, float), (n,)) / RATE
    ph = np.cumsum(dt) % 1.0
    return np.where(ph < duty, 1.0, -1.0) + blep(ph, dt) - blep((ph - duty) % 1.0, dt) - (2 * duty - 1)


def chip(freq, seconds, duty=0.25, vol=1.0, a=0.002, d=0.08, s=0.6, r=0.02, vib=0.0, bend=0.0):
    """an 8-bit note: `bend` scoops up into it (semitones), `vib` a vibrato
    that comes in after the start"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = np.broadcast_to(np.asarray(freq, float), (n,)).copy()
    if bend:
        f *= 2 ** (-bend * np.exp(-t / 0.02) / 12)
    if vib:
        f *= 1 + vib * np.sin(2 * np.pi * 6 * t) * np.clip((t - 0.06) / 0.1, 0, 1)
    return pulse(f, n, duty) * A.adsr(n, a, d, s, r) * vol


# overtones of things that ring: (times the note, loudness)
PLATE = ((1, 1.0), (1.52, 0.8), (2.26, 0.6), (2.87, 0.45), (3.65, 0.3), (4.48, 0.2), (5.79, 0.12))  # armour
BAR = ((1, 1.0), (2.76, 0.6), (5.40, 0.3), (8.93, 0.12))  # a blade, a coin
IRON = ((1, 1.0), (1.93, 0.8), (2.71, 0.65), (3.52, 0.5), (4.66, 0.35), (5.83, 0.2), (7.31, 0.12))  # an anchor


def metal(freq, seconds, overtones, vol=1.0, k=0):
    """metal ringing: overtones out of tune with each other, the high ones
    dying first; all faded away by the end (`k` picks how they line up)"""
    r = np.random.default_rng(k)
    n = n_of(seconds)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for i, (p, a) in enumerate(overtones):
        if freq * p < 16000:
            x += a * np.sin(2 * np.pi * freq * p * t + r.uniform(0, 2 * np.pi)) * np.exp(-t * (5 + 3 * i) / seconds)
    return x * np.clip(t / 0.0005, 0, 1) * vol


def chime(freq, seconds, vol=1.0, buzz=0.2):
    """a golden chime: a bell-like ring with a little 8-bit square in it"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    ring = metal(freq, seconds, ((1, 1.0), (2.0, 0.3), (3.0, 0.1), (4.16, 0.06)), 1.0, int(freq))
    return (ring + band(pulse(freq, n, 0.5), hi=6000) * np.exp(-t * 8 / seconds) * buzz) * vol


def glints(start, count, gap, vol=0.1, notes=(96, 100, 103, 108), climb=False):
    """tiny golden glints, one every `gap` (up the notes, if `climb`)"""
    r = S.rng
    parts = []
    for i in range(count):
        m = notes[i % len(notes)] if climb else notes[int(r.integers(len(notes)))]
        parts.append(at(metal(midi(m), 0.14, ((1, 1.0), (2.0, 0.3)), vol * r.uniform(0.6, 1.0), i), start + i * gap))
    return mix(*parts)


def thump(f0, f1, seconds, vol=1.0, drive=2.0):
    """a deep hit: a falling tone, driven so a phone's small speaker still hears it"""
    n = n_of(seconds)
    x = sine(sweep(f0, f1, seconds)) * env(n, 0.002, seconds, 2.2)
    return np.tanh(drive * x) / np.tanh(drive) * vol


def strike(seconds, lo, hi, vol=1.0):
    """the crack of something hitting: a burst of noise, gone at once"""
    n = n_of(seconds)
    return band(noise(n), lo, hi) * env(n, 0.0003, seconds, 4) * vol


def grit(seconds, rate, lo=1200, hi=6000, vol=1.0, grain=0.003, shape=None):
    """gritty bits (dirt, gravel, sparks): tiny random clicks, `rate` a
    second, following `shape` (a loudness for each sample)"""
    n = n_of(seconds)
    r = S.rng
    hits = (r.random(n) < rate / RATE) * r.uniform(0.25, 1.0, n)
    if shape is not None:
        hits = hits * shape
    m = max(2, n_of(grain))
    kernel = r.uniform(-1, 1, m) * np.exp(-4 * np.arange(m) / m)
    return band(np.convolve(hits, kernel)[:n], lo, hi) * vol


def link(freq, vol=1.0):
    """a chain link knocking on the next: a tick and a quick ring"""
    tick = strike(0.003, 2500, 11000, 0.6)
    return mix(tick, metal(freq, 0.05, ((1, 1.0), (2.41, 0.5), (3.93, 0.3)), 1.0, int(S.rng.integers(1 << 30)))) * vol


def tink(freq, vol=1.0):
    """a little coin landing: a tick and a quick bright ring"""
    tick = strike(0.003, 3000, 11000, 0.5)
    return mix(tick, metal(freq, S.rng.uniform(0.08, 0.14), BAR, 1.0, int(S.rng.integers(1 << 30)))) * vol


def squeal(seconds, freq=1700, vol=1.0, wobble=0.035):
    """a tyre squealing: a high singing tone that wavers, and the scrub of
    the rubber (`freq`: a number, or one a sample)"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = freq * (1 + wobble * (0.6 * np.sin(2 * np.pi * 9 * t) + 0.4 * np.sin(2 * np.pi * 14.7 * t + 1.3)))
    ph = np.cumsum(f) / RATE
    tone = sine(ph) + 0.25 * sine(2 * ph) + 0.06 * sine(3 * ph)
    scrub = band(noise(n), np.min(f) * 0.7, np.max(f) * 1.8, order=3) * 1.2
    return (0.55 * tone + scrub) * vol


def fire(seconds, vol=1.0, lo=120, hi=1500):
    """flames: a rough roar that flickers, with crackles"""
    n = n_of(seconds)
    flick = band(noise(n), hi=18)
    flick = 0.6 + 0.4 * flick / (np.max(np.abs(flick)) + 1e-9)
    return (band(noise(n), lo, hi) * flick + grit(seconds, 45, 1500, 6000, 0.5)) * vol


def crushed(x, steps=24):
    """8-bit grit at a known strength (make_sfx's crush, on x scaled to full)"""
    return crush(x / (np.max(np.abs(x)) + 1e-9), steps)


def tight(x, floor=0.003, fade=0.012):
    """cuts off the silent end, fading out over the last few ms"""
    loud = np.nonzero(np.abs(x) > floor * np.max(np.abs(x)))[0]
    x = x[:loud[-1] + 1 if len(loud) else len(x)].copy()
    f = min(len(x), n_of(fade))
    x[-f:] *= np.linspace(1, 0, f) ** 2
    return x


def master(x, lo=40, hi=12000, drive=0.0):
    """the finish on each: nothing deeper than a speaker plays or harshly
    high, a gentle limit (`drive`) so a hit carries, and no silent tail"""
    x = band(x, lo, hi)
    if drive:
        x = A.soft_limit(x, drive)
    return tight(x)


# ----------------------------------------------------------------------
# THE KNIGHT PACK (Knight Burrowmore: blue armour and a golden shovel;
# dirt, gold treasure, honour, anchors on chains)
# ----------------------------------------------------------------------
def shovel_swish():
    # a heavy spade through the air, its edge ringing faintly at the end
    s = 0.28
    hum = tri(sweep(80, 120, s)) * env(n_of(s), 0.1, s, 1.6) * 0.3
    return master(mix(whoosh(s, 160, 2200, 1.5, 1.5), hum, at(metal(1900, 0.13, BAR, 0.1, 1), 0.17)))


def dirt_splat():
    # a clod landing: a dull, soft thud and a gritty crumble (quiet and
    # short: lots land at once)
    s = 0.15
    thud = sine(sweep(230, 90, 0.09)) * env(n_of(0.09), 0.004, 0.09, 2.2)
    thup = band(noise(n_of(0.06)), 180, 1100) * env(n_of(0.06), 0.003, 0.06, 2.5) * 0.9
    crumble = grit(s, 320, 1000, 5000, 0.6, grain=0.002, shape=env(n_of(s), 0.02, s, 1.3))
    return master(mix(thud, thup, crumble), lo=70, hi=6500)


def clang_hit():
    # the shovel hitting armour: a bright CLANG, ringing briefly
    ting = chip(np.geomspace(2350, 2250, n_of(0.18)), 0.18, 0.25, 0.2, d=0.04, s=0.25, r=0.08)
    knock = tri(sweep(220, 95, 0.1)) * env(n_of(0.1), 0.001, 0.1, 3) * 0.5
    hit = crushed(mix(strike(0.03, 2000, 11000), knock, ting), 20)  # (the 8-bit crack of it)
    return master(mix(hit * 0.7, metal(880, 0.36, PLATE, 0.45, 2), metal(2230, 0.2, BAR, 0.15, 3)), drive=1.3)


def chain_swish():
    # a whoosh with the chain's links rattling along it
    s = 0.34
    r = S.rng
    links = [at(link(r.uniform(1800, 4000), r.uniform(0.5, 1.0) * np.sin(np.pi * tt / s) * 0.4), tt)
             for tt in np.sort(r.uniform(0.02, s - 0.05, 16))]
    return master(mix(whoosh(s, 250, 2800, 1.3, 1.5), *links))


def gold_swing():
    # a big swing, and a shimmering golden chime trailing after it
    chimes = mix(*[at(chime(midi(m), 0.26, 0.2), 0.1 + i * 0.035) for i, m in enumerate((84, 88, 91, 96))])
    return master(mix(whoosh(0.3, 220, 3200, 1.4, 1.5), chimes, glints(0.14, 5, 0.05, 0.07)))


def gold_chop():
    # the golden shockwave off a chop: a deep boom, and a sparkle rising out of it
    s = 0.6
    n = n_of(s)
    t = np.arange(n) / RATE
    whump = band(noise(n_of(0.2)), 90, 1400) * env(n_of(0.2), 0.002, 0.2, 2.5) * 0.4
    rise = band(pulse(650 * 4 ** (t / s), n, 0.25), hi=5000) * (1 + 0.3 * np.sin(2 * np.pi * 12 * t)) * env(n, 0.2, s, 1.4) * 0.12
    climbing = glints(0.06, 10, 0.05, 0.2, (84, 86, 88, 91, 93, 96, 98, 100, 103, 105), climb=True)
    return master(mix(thump(115, 45, 0.32, 0.55, 1.4), whump, rise, climbing), lo=50)


def coin_spill():
    # a flurry of little coins spilling out, dinging and bouncing
    r = S.rng
    out = np.zeros(n_of(0.66))
    t = 0.0
    while t < 0.47:
        f = r.uniform(2300, 4300)
        v = r.uniform(0.45, 1.0) * (1 - 0.55 * t / 0.47)
        A.place(out, tink(f, v), t)
        if r.random() < 0.5:  # (a bounce)
            A.place(out, tink(f * r.uniform(0.98, 1.02), v * 0.4), t + r.uniform(0.04, 0.08))
        t += 0.012 + r.exponential(0.028)
    return master(out)


def spade_dig():
    # the spade stabbing into the earth (a crunch and a thunk), then
    # scooping it up (a scrape) and tossing it
    stab = mix(grit(0.08, 1100, 500, 4500, 1.1, shape=env(n_of(0.08), 0.001, 0.08, 2.0)), strike(0.012, 400, 5000, 0.6))
    n = n_of(0.19)
    k = np.arange(n) / n
    rough = np.abs(band(noise(n), hi=70))
    rough = 0.5 + 0.5 * rough / (np.max(rough) + 1e-9)
    scrape = band(A.sweep_lp(noise(n), 1200 + 2400 * k), 450) * rough * env(n, 0.05, 0.19, 1.3) * 0.9
    toss = grit(0.09, 260, 900, 5000, 0.35, shape=env(n_of(0.09), 0.01, 0.09, 1.5))
    return master(mix(stab, thump(220, 85, 0.12, 0.6, 2.0), at(scrape, 0.1), at(grit(0.19, 120, 1000, 5000, 0.3), 0.1),
                      at(toss, 0.26)), lo=60)


def treasure_glint():
    # finding treasure: a sharp 8-bit "ting-ting!" and a twinkle
    notes = ((0.0, 88, 0.07), (0.06, 95, 0.07), (0.12, 100, 0.26))  # (E, B, and the high E)
    tings = mix(*[at(chip(midi(m), d, 0.25, 0.35, d=0.06, s=0.1, r=0.05 if i == 2 else 0.015, vib=0.006 if i == 2 else 0), t0)
                  for i, (t0, m, d) in enumerate(notes)])
    return master(mix(tings, glints(0.16, 4, 0.05, 0.08)))


def coin_ding():
    # one coin: a clink and a bright, short ring
    blip = chip(midi(88), 0.2, 0.5, 0.3, d=0.05, s=0.05, r=0.05, bend=1)
    return master(mix(strike(0.003, 3000, 11000, 0.4), metal(2640, 0.24, BAR, 0.8, 5), blip), drive=1.3)


def dirt_spin():
    # a low spin: air whirling round, and a gritty spray of dirt flying off
    s = 0.5
    n = n_of(s)
    t = np.arange(n) / RATE
    whirl = whoosh(s, 140, 1500, 1.5, 1.2) * (0.45 + 0.55 * np.sin(2 * np.pi * 6.5 * t) ** 2)
    rumble = band(noise(n), 40, 260) * env(n, 0.12, s, 1.5) * 0.6
    spray = grit(s, 380, 900, 5500, 0.45, shape=np.sin(np.pi * t / s) ** 2)
    return master(mix(whirl, rumble, spray))


def pogo_boing():
    # the pogo's spring: a cartoon 8-bit BOING, rising and wobbling
    s = 0.36
    n = n_of(s)
    t = np.arange(n) / RATE
    f = (170 + 480 * (t / s) ** 0.8) * (1 + 0.14 * np.sin(2 * np.pi * 24 * t) * np.exp(-2 * t))
    x = 0.55 * pulse(f, n, 0.25) + 0.45 * tri(np.cumsum(f / 2) / RATE)
    return master(band(x, hi=4500) * env(n, 0.003, s, 1.4))


def pogo_clang():
    # landing blade-first: a thud, and a ringing clang of metal
    hit = crushed(mix(thump(160, 65, 0.18, 0.6, 2.0), strike(0.02, 1500, 9000, 0.9)), 24)
    return master(mix(hit * 0.7, metal(1150, 0.32, BAR, 0.55, 6), metal(1730, 0.22, PLATE, 0.2, 7)), lo=55, drive=1.3)


def anchor_hurl():
    # the anchor flung out: a heavy iron whoosh, the chain rattling out after it
    s = 0.42
    hum = tri(sweep(70, 100, s)) * env(n_of(s), 0.1, s, 1.5) * 0.3
    r = S.rng
    links = []
    tt = 0.06
    while tt < 0.47:
        u = (tt - 0.06) / 0.41
        links.append(at(link(r.uniform(1500, 3400) * (1 - 0.15 * u), r.uniform(0.5, 1.0) * 0.35 * np.sin(np.pi * u) ** 0.5), tt))
        tt += r.uniform(0.7, 1.3) / 40
    return master(mix(whoosh(s, 140, 1800, 1.5, 1.4), hum, *links))


def chain_reel():
    # the chain reeled in fast: a ratchet clicking quicker and quicker
    out = np.zeros(n_of(0.36))
    tt, gap, i = 0.0, 0.032, 0
    while tt < 0.32:
        A.place(out, link((2500 if i % 2 else 2150) * S.rng.uniform(0.97, 1.03), 0.5), tt)
        A.place(out, tri(sweep(420, 300, 0.015)) * env(n_of(0.015), 0.0005, 0.015, 3) * 0.35, tt)
        tt += gap
        gap = max(0.014, gap * 0.93)
        i += 1
    return master(mix(out, whoosh(0.34, 300, 2200, 0.6, 1.2)))


def anchor_slam():
    # the anchor landing: a huge iron CLANK with a boom under it, the chain settling
    dust = band(noise(n_of(0.45)), 120, 1800) * env(n_of(0.45), 0.003, 0.45, 2.5) * 0.4
    hit = crushed(mix(thump(105, 48, 0.5, 0.7, 2.0), strike(0.05, 800, 9000, 1.1), dust), 24)
    clank = mix(metal(330, 0.7, IRON, 1.0, 7), metal(745, 0.45, PLATE, 0.45, 8))
    r = S.rng
    settle = mix(*[at(link(r.uniform(1400, 3000), 0.3 * (1 - i / 7)), 0.12 + i * 0.05 + r.uniform(0, 0.02)) for i in range(7)])
    return master(mix(hit * 0.7, clank * 0.55, settle * 0.6), lo=55, drive=1.4)


def plate_crack():
    # the armour cracking open into gold: a sharp crack, then a chord
    # rising up and shimmering
    crack = mix(strike(0.05, 1500, 11000, 0.9), metal(1400, 0.2, PLATE, 0.3, 8))
    bits = grit(0.2, 350, 2000, 8000, 0.5, shape=env(n_of(0.2), 0.002, 0.2, 2))
    arp = mix(*[at(chip(midi(m), 0.09, 0.25, 0.4, d=0.05, s=0.3, r=0.02), 0.08 + i * 0.05) for i, m in enumerate((72, 76, 79, 84, 88))])
    cs = 0.64
    t = np.arange(n_of(cs)) / RATE
    chord = sum(chip(midi(m), cs, 0.5, 1.0, a=0.02, d=0.2, s=0.7, r=0.25, vib=0.004) for m in (84, 88, 91)) / 3
    chord = band(chord, hi=5000) * (1 + 0.35 * np.sin(2 * np.pi * 10 * t)) * 0.5
    rising = glints(0.38, 7, 0.07, 0.1, (84, 88, 91, 96, 100, 103, 108), climb=True)
    return master(mix(crack, bits, arp, at(chord, 0.34), at(chime(midi(96), 0.5, 0.25), 0.34), rising), drive=1.5)


def meteor_fall():
    # a meteor falling: a whistle sweeping down, the rush of it growing louder
    s = 0.6
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    f = 2300 * (430 / 2300) ** (k ** 0.85)
    whistle = sine(np.cumsum(f * (1 + 0.006 * np.sin(2 * np.pi * 7 * t))) / RATE) + 0.18 * band(pulse(f, n, 0.5), hi=4000)
    rush = A.sweep_lp(noise(n), 900 + 2500 * k) * 0.8
    grow = (0.2 + 0.8 * k ** 1.5) * np.clip(t / 0.03, 0, 1) * np.clip((s - t) / 0.02, 0, 1)
    return master(mix(whistle * 0.6, rush, grit(s, 80, 1500, 6000, 0.4, shape=k)) * grow)


def meteor_impact():
    # the meteor landing: a heavy boom, rubble flying, then a sparkle of gold
    dust = band(noise(n_of(0.6)), 80, 1200) * env(n_of(0.6), 0.003, 0.6, 2.2) * 0.45
    crunch = band(noise(n_of(0.25)), 250, 3000) * env(n_of(0.25), 0.001, 0.25, 2.8) * 0.8
    rubble = grit(0.5, 180, 300, 3500, 0.8, grain=0.006, shape=env(n_of(0.5), 0.01, 0.5, 1.8))
    hit = crushed(mix(thump(95, 40, 0.6, 0.9, 2.2), strike(0.07, 500, 9000, 1.0), crunch, dust, rubble), 24)
    gold = mix(*[at(chime(midi(m), 0.55, 0.22), 0.13 + i * 0.05) for i, m in enumerate((84, 88, 91, 96))], glints(0.2, 10, 0.06, 0.12))
    return master(mix(hit * 0.85, gold), lo=50, drive=1.3)


# ----------------------------------------------------------------------
# THE SPEEDWAY PACK (Speedy Revvington: a grinning orange race car;
# engines, tyres, nitro, exhaust flames, pit stops, chequered flags)
# ----------------------------------------------------------------------
def tyre_swish():
    # a rubbery whoosh, with a hint of tyre squeal in it
    s = 0.28
    wub = sine(sweep(110, 190, s)) * env(n_of(s), 0.06, s, 1.8) * 0.35
    sq = squeal(0.18, 1550, 0.12, 0.05) * A.adsr(n_of(0.18), 0.04, 0.1, 0.6, 0.08)
    return master(mix(whoosh(s, 350, 3200, 1.3, 1.5), wub, at(sq, 0.07)))


def spark_skitter():
    # sparks skittering over the floor: a short, bright crackle (soft: it plays a lot)
    s = 0.2
    crackle = grit(s, 320, 2000, 7500, 1.0, grain=0.0012, shape=env(n_of(s), 0.003, s, 1.3))
    r = S.rng
    tinks = mix(*[at(metal(r.uniform(4000, 6500), 0.03, ((1, 1.0),), 0.2, i), r.uniform(0, 0.13)) for i in range(5)])
    return master(mix(crackle, tinks), hi=10000, drive=1.6)


def spark_hit():
    # a metal hit that throws out a crackling spray of sparks
    knock = tri(sweep(200, 85, 0.12)) * env(n_of(0.12), 0.001, 0.12, 3) * 0.6
    hit = crushed(mix(strike(0.025, 1500, 10000), metal(720, 0.3, PLATE, 0.8, 9), knock), 28)
    spray = grit(0.33, 420, 2500, 10000, 0.8, grain=0.0015, shape=env(n_of(0.33), 0.01, 0.33, 1.6))
    return master(mix(hit, at(spray, 0.01)), drive=1.2)


def flame_swish():
    # a whoosh with a fiery roar in it
    s = 0.4
    return master(mix(whoosh(s, 250, 2600, 1.2, 1.4), fire(s, 0.9) * env(n_of(s), s * 0.3, s, 1.4)))


def flame_burst():
    # a small puff of fire: a soft WHUMP and a flicker
    s = 0.3
    n = n_of(s)
    whump = A.sweep_lp(noise(n), np.geomspace(3000, 300, n)) * env(n, 0.006, s, 2.0) * 1.2
    body = band(noise(n_of(0.15)), 150, 800) * env(n_of(0.15), 0.004, 0.15, 2.2) * 0.8
    flick = grit(s, 45, 1500, 6000, 0.35, shape=env(n, 0.02, s, 1.5))
    return master(mix(whump, body, thump(90, 50, 0.15, 0.3, 1.5), flick), lo=50, drive=1.2)


def victory_swing():
    # a fast swing with a race car zooming past in it: "neeeeowm"
    s = 0.45
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    past = 1 / (1 + np.exp(-(k - 0.42) * 14))
    f = (540 - 290 * past) * (1 + 0.015 * np.sin(2 * np.pi * 31 * t))
    engine = band(0.6 * pulse(f, n, 0.3) + 0.4 * pulse(f / 2, n, 0.5), hi=3200)
    near = np.exp(-((k - 0.42) / 0.25) ** 2) * np.clip(t / 0.02, 0, 1) * np.clip((s - t) / 0.03, 0, 1)
    return master(mix(engine * near * 0.55, at(whoosh(0.3, 500, 5000, 1.2, 1.6), 0.05)))


def checker_pop():
    # a party popper for the chequered flag: a quick POP, confetti
    # fluttering down, a tiny sparkle
    body = sine(sweep(520, 170, 0.05)) * env(n_of(0.05), 0.001, 0.05, 3) * 0.8
    confetti = grit(0.3, 220, 2500, 8000, 0.5, grain=0.006, shape=env(n_of(0.3), 0.01, 0.3, 1.5))
    return master(mix(strike(0.015, 400, 7000, 1.0), body, at(confetti, 0.02), glints(0.07, 3, 0.07, 0.15, (100, 103, 108))),
                  drive=1.6)


def nitro_rev():
    # the engine revving: vroom-VROOM, the second rev higher
    s = 0.8
    n = n_of(s)
    t = np.arange(n) / RATE
    f = smooth(np.interp(t, [0, 0.12, 0.32, 0.4, 0.58, 0.8], [60, 160, 80, 86, 260, 170]), 0.03)
    rpm = (f - 60) / (260 - 60)
    ph = np.cumsum(f) / RATE
    buzz = (0.5 * pulse(f, n, 0.3) + 0.2 * pulse(2 * f, n, 0.5) + 0.3 * tri(ph)) * (1 + 0.3 * sine(ph / 2))
    x = A.sweep_lp(crushed(buzz, 16), 900 + 3500 * rpm) + band(noise(n), 150, 1500) * 0.12
    return master(x * (0.2 + 0.8 * rpm) * A.adsr(n, 0.02, 0.1, 1.0, 0.08), lo=60)


def tyre_screech():
    # tyres screeching: a high squeal that wavers
    s = 0.6
    n = n_of(s)
    return master(squeal(s, np.linspace(1500, 1350, n), 1.0, 0.045) * A.adsr(n, 0.03, 0.2, 0.8, 0.15), hi=6000)


def nitro_boost():
    # nitro: a jet blast - a hissing whoosh opening up, a tone rising through it
    s = 0.7
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    roar = A.sweep_lp(noise(n), 700 + 5000 * k ** 0.6) * env(n, 0.015, s, 1.3)
    hiss = band(noise(n), 3000, 11000) * env(n, 0.03, s, 1.5) * 0.4
    f = 260 * (1100 / 260) ** k
    tone = band(0.5 * pulse(f, n, 0.5) + 0.5 * sine(np.cumsum(f) / RATE), hi=3500) * env(n, 0.08, s, 1.2) * 0.2
    return master(mix(thump(110, 55, 0.2, 0.6, 2.0), roar, hiss, tone), drive=1.2)


def piston_pump():
    # a piston pumping: a heavy mechanical CHUNK and a hiss of air
    chunk = mix(tri(sweep(260, 110, 0.07)) * env(n_of(0.07), 0.001, 0.07, 3),
                metal(520, 0.12, ((1, 1.0), (2.32, 0.5), (3.71, 0.3)), 0.35, 10), strike(0.012, 600, 4000, 0.8))
    n = n_of(0.24)
    hiss = band(A.sweep_lp(noise(n), np.geomspace(9000, 4000, n)), 2500) * env(n, 0.012, 0.24, 1.8) * 0.45
    return master(mix(crushed(chunk, 24), at(hiss, 0.05)))


def piston_punch():
    # a backfire: a BANG, then the exhaust popping
    def pop(v):
        return mix(strike(0.03, 250, 4000, 1.0), thump(200, 100, 0.05, 0.5, 2.0)) * v
    body = band(noise(n_of(0.12)), 150, 3000) * env(n_of(0.12), 0.001, 0.12, 3) * 0.7
    bang = mix(strike(0.06, 200, 9000, 1.3), body, thump(120, 50, 0.22, 0.6, 2.5))
    return master(crushed(mix(bang, at(pop(0.6), 0.17), at(pop(0.4), 0.26), at(pop(0.22), 0.33)), 20), lo=50, drive=1.4)


def tyre_bounce():
    # spare tyres thumping down and bouncing away: rubbery thumps, each smaller
    def bump(v, up=1.0):
        s = 0.13
        n = n_of(s)
        t = np.arange(n) / RATE
        f = (85 + 90 * np.exp(-t / 0.03)) * up * (1 + 0.06 * np.sin(2 * np.pi * 26 * t))
        body = np.tanh(2.2 * sine(np.cumsum(f) / RATE)) * env(n, 0.002, s, 2.0)
        return mix(body, strike(0.012, 200, 2500, 0.5)) * v
    return master(mix(bump(1.0), at(bump(0.6, 1.08), 0.19), at(bump(0.36, 1.15), 0.32), at(bump(0.2, 1.2), 0.41)))


def wheel_roll():
    # the flaming wheel charging up: a rolling roar and an engine note
    # building for 0.9 s
    s = 0.9
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    turn = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(6 + 12 * k) / RATE) ** 2
    f = 75 * (210 / 75) ** k
    engine = A.sweep_lp(0.6 * pulse(f, n, 0.3) + 0.4 * tri(np.cumsum(f / 2) / RATE), 700 + 2000 * k) * 0.5
    grow = (0.25 + 0.75 * k ** 1.3) * np.clip(t / 0.02, 0, 1) * np.clip((s - t) / 0.025, 0, 1)
    return master(mix(band(noise(n), 50, 500) * turn * 1.2, engine, fire(s, 0.5)) * grow)


def wheelie_slam():
    # slamming down off a wheelie: a heavy crash thump and metal clattering
    crash = band(noise(n_of(0.3)), 200, 7000) * env(n_of(0.3), 0.001, 0.3, 3) * 0.9
    r = S.rng
    clatter = mix(*[at(metal(r.uniform(700, 2600), r.uniform(0.12, 0.25), PLATE[:4], r.uniform(0.35, 0.6) * (1 - i / 13), 20 + i),
                       0.02 + i * 0.035 + r.uniform(0, 0.03)) for i in range(12)])
    return master(mix(crushed(mix(thump(110, 45, 0.4, 0.6, 2.0), crash), 22), clatter * 0.5), lo=55, drive=1.3)


def race_go():
    # the start lights: beep - beep - beep - BEEEP! (the last longer and higher)
    def beep(m, s, v):
        n = n_of(s)
        f = midi(m)
        tone = 0.6 * pulse(f, n, 0.5) + 0.4 * tri(np.arange(n) * f / RATE) + 0.15 * pulse(2 * f, n, 0.5)
        return tone * A.adsr(n, 0.003, 0.1, 0.85, 0.02) * v
    return master(mix(beep(76, 0.14, 0.4), at(beep(76, 0.14, 0.4), 0.3), at(beep(76, 0.14, 0.4), 0.6), at(beep(88, 0.42, 0.45), 0.9)),
                  hi=9000)


def finish_line():
    # crossing the line: a short, cheerful 8-bit victory fanfare
    lead = ((0.0, 79, 0.075), (0.08, 84, 0.075), (0.16, 88, 0.075), (0.24, 91, 0.15), (0.40, 88, 0.075), (0.48, 91, 0.7))
    out = np.zeros(n_of(1.3))
    for t0, m, d in lead:
        A.place(out, chip(midi(m), d, 0.25, 0.3, d=0.1, s=0.7, r=0.12 if d > 0.3 else 0.03, vib=0.006 if d > 0.3 else 0), t0)
    for t0, m, d in ((0.40, 84, 0.075), (0.48, 88, 0.7)):  # (a harmony under the last two)
        A.place(out, chip(midi(m), d, 0.5, 0.14, d=0.1, s=0.6, r=0.12 if d > 0.3 else 0.03), t0)
    for t0, m, d in ((0.0, 48, 0.2), (0.24, 55, 0.2), (0.48, 48, 0.7)):
        A.place(out, A.nes_tri(midi(m), d) * 0.3, t0)
    for t0 in (0.24, 0.40):
        A.place(out, A.snare(0.22, 0.1), t0)
    A.place(out, A.crash(0.12, 0.6), 0.48)
    return master(out, hi=9000)


def horn_honk():
    # a cartoon car horn: HONK-honk (two notes at once; the second honk
    # shorter and a little lower)
    def honk(s, v, shift=1.0):
        n = n_of(s)
        t = np.arange(n) / RATE
        bend = 2 ** ((-1.2 * np.exp(-t / 0.025) - 0.6 * np.clip((t - s + 0.05) / 0.05, 0, 1)) / 12)
        x = pulse(349 * shift * bend, n, 0.35) + 0.8 * pulse(440 * shift * bend, n, 0.35)
        return band(x, 250, 2800) * A.adsr(n, 0.01, 0.06, 0.85, 0.035) * v
    return master(mix(honk(0.22, 1.0), at(honk(0.19, 0.75, 0.94), 0.29)))


PACKS = {
    'Knight': {
        # the swings, what they throw off and what they hit
        'Shovel Swish': shovel_swish,
        'Dirt Splat': dirt_splat,
        'Clang Hit': clang_hit,
        'Chain Swish': chain_swish,
        'Gold Swing': gold_swing,
        'Gold Chop': gold_chop,
        'Coin Spill': coin_spill,
        # the abilities: Dig Slam, Treasure Eye, Dirt Spin, Pogo Drop, Anchor Pull, No Quarter
        'Spade Dig': spade_dig,
        'Treasure Glint': treasure_glint,
        'Coin Ding': coin_ding,
        'Dirt Spin': dirt_spin,
        'Pogo Boing': pogo_boing,
        'Pogo Clang': pogo_clang,
        'Anchor Hurl': anchor_hurl,
        'Chain Reel': chain_reel,
        'Anchor Slam': anchor_slam,
        'Plate Crack': plate_crack,
        'Meteor Fall': meteor_fall,
        'Meteor Impact': meteor_impact,
    },
    'Speedway': {
        # the swings, what they throw off and what they hit
        'Tyre Swish': tyre_swish,
        'Spark Skitter': spark_skitter,
        'Spark Hit': spark_hit,
        'Flame Swish': flame_swish,
        'Flame Burst': flame_burst,
        'Victory Swing': victory_swing,
        'Checker Pop': checker_pop,
        # the abilities: Burnout, Nitro, Piston Dash, Skid Spin, Wheelie, Victory Lap
        'Nitro Rev': nitro_rev,
        'Tyre Screech': tyre_screech,
        'Nitro Boost': nitro_boost,
        'Piston Pump': piston_pump,
        'Piston Punch': piston_punch,
        'Tyre Bounce': tyre_bounce,
        'Wheel Roll': wheel_roll,
        'Wheelie Slam': wheelie_slam,
        'Race Go': race_go,
        'Finish Line': finish_line,
        'Horn Honk': horn_honk,
    },
}


if __name__ == '__main__':
    S.OUT = OUT
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:]
    for name, fn in WEAPON_SOUNDS.items():
        if not want or any(name.startswith(w) for w in want):
            S.save(name, fn())
    for pack, sounds in PACKS.items():  # (after the ones above: see own_noise)
        for name, fn in sounds.items():
            if not want or any(name.startswith(w) or pack.startswith(w) for w in want):
                own_noise(name)
                S.save(name, fn())
