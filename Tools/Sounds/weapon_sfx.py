"""The weapons' sound effects: every weapon type's swing and hit, the Slime
pack's goo (the swings of the rarer ones, the splats, the Secret's jelly), and
the Slime abilities. Made from code like the rest (make_sfx.py's building
blocks: squares, noise, sweeps), a bit rounder and wetter for the goo.

Then the later packs', the same way (their swings, what the swings throw off
and hit, and their abilities):
  * the Knight pack (Knight Burrowmore): a heavy shovel's swish and clang,
    dirt clods, gold chimes and coins, a pogo's boing, anchors on chains,
    armour cracking into gold and a meteor
  * the Speedway pack (Speedy Revvington): tyres, sparks, flames, engines
    revving, nitro, pistons, a horn, and the race's start lights and
    finish-line fanfare
  * the Jungle pack (Kongo): leaves and vines, wooden barrels with iron
    bands (swung, rolled, burst and blown up), a banana's boing-bonk, ape
    grunts, a roar and chest thumps, jungle drums, and gold for his crown
    and the giant fist that falls out of the sky
  * the Canvas pack (Scribble): a paintbrush, ink splats, an eraser's
    squeak, a pencil sharpener and scribbles, and the computer he lives in -
    keys clicking, copy and paste, pixels popping, glitches, and a DELETE
    that shatters everything

    python3 weapon_sfx.py              -> out/weapons/<Name>.ogg (and .wav)
    python3 weapon_sfx.py Knight Goo   ...only the Knight pack's and the ones
                                          starting with "Goo"

(Each .ogg made is written afresh, and a fresh one's bytes differ even when
its sound hasn't changed - the uploader would take it for a new sound - so
make only the ones you've changed.)

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


# ======================================================================
# THE JUNGLE AND CANVAS PACKS (made like Knight's and Speedway's: each
# sound with its own noise, the same finish)
# ======================================================================
# more overtones of things that ring (times the note, loudness)
WOOD = ((1, 1.0), (2.29, 0.45), (3.98, 0.2), (6.13, 0.08))  # a plank, a stave: dull, the high ones gone at once
BARREL = ((1, 1.0), (1.58, 0.7), (2.15, 0.45), (2.85, 0.3), (3.71, 0.15))  # a barrel's hollow body
HOOP = ((1, 1.0), (2.13, 0.7), (3.34, 0.5), (4.61, 0.35), (6.05, 0.2), (7.66, 0.1))  # the iron band round it


def knock(freq, seconds=0.1, vol=1.0):
    """wood knocking: the tick of the hit and a dull wooden tock"""
    return mix(strike(0.004, 900, 7000, 0.4), metal(freq, seconds, WOOD, 1.0, int(S.rng.integers(1 << 30)))) * vol


def swoop(seconds, lo, hi, curve=2.0, tail=0.012):
    """air rushing in: a swell up to `seconds` (its filter opening from `lo`
    to `hi`), then gone at once - the rush into a hit"""
    n = n_of(seconds + 4 * tail)
    t = np.arange(n) / RATE
    k = np.minimum(t / seconds, 1)
    return A.sweep_lp(noise(n), lo + (hi - lo) * k ** 2) * np.where(t < seconds, k ** curve, np.exp(-(t - seconds) / tail))


def leaves(seconds, rate, vol=1.0, lo=1800, hi=8000, shape=None):
    """leaves rustling: crisp little crackles (`rate` a second, most of them
    faint) over the grainy hush of leaves brushing, coming in flurries
    (`shape`: a loudness for each sample); `vol` at the loudest"""
    n = n_of(seconds)
    r = S.rng
    flurry = np.abs(band(noise(n), hi=25))
    flurry = 0.15 + 0.85 * (flurry / (np.max(flurry) + 1e-9)) ** 1.5
    if shape is not None:
        flurry = flurry * shape
    grain = np.abs(band(noise(n), hi=250))
    hush = band(noise(n), lo, hi) * (grain / (np.max(grain) + 1e-9)) ** 2.5
    hits = (r.random(n) < rate / RATE) * r.uniform(0, 1, n) ** 2
    m = n_of(0.0012)
    crackle = band(np.convolve(hits, r.uniform(-1, 1, m) * np.exp(-5 * np.arange(m) / m))[:n], lo, hi)
    x = (hush / (np.max(np.abs(hush)) + 1e-9) + 1.5 * crackle / (np.max(np.abs(crackle)) + 1e-9)) * flurry
    return x / (np.max(np.abs(x)) + 1e-9) * vol


def pat(vol=1.0, up=1.0):
    """something soft landing (a leaf, a banana): a little dull pat"""
    body = sine(sweep(240 * up, 110 * up, 0.06)) * env(n_of(0.06), 0.003, 0.06, 2.4)
    thup = band(noise(n_of(0.035)), 250, 1600) * env(n_of(0.035), 0.002, 0.035, 2.5) * 0.7
    return mix(body, thup) * vol


VOWELS = {  # an ape's vowels: (formants, their loudness)
    'u': ((320, 760, 2300), (1.0, 0.3, 0.08)),
    'o': ((500, 850, 2400), (1.0, 0.5, 0.12)),
    'a': ((780, 1180, 2500), (1.0, 0.6, 0.2)),
}


def ape(freq, vowels, growl=0.0, breath=0.15, duty=0.35):
    """a cartoon ape's voice, at full loudness: an 8-bit buzz (`freq`: one a
    sample) shaped into its vowels, gliding from one to the next (('u', 'a'):
    "hoo-ah"); `growl` roughens it, `breath` puts air in it"""
    n = len(freq)
    t = np.arange(n) / RATE
    if growl:
        jitter = band(noise(n), hi=50)
        freq = freq * (1 + growl * (0.04 * np.sin(2 * np.pi * 29 * t) + 0.05 * jitter / (np.max(np.abs(jitter)) + 1e-9)))
    src = pulse(freq, n, duty) * (1 + growl * 0.6 * np.sin(2 * np.pi * 31 * t))
    out = np.zeros(n)
    pos = np.linspace(0, len(vowels) - 1, n)
    for i, v in enumerate(vowels):
        fr, gain = VOWELS[v]
        out += sum(band(src, f * 0.8, f * 1.25) * g for f, g in zip(fr, gain)) * np.clip(1 - np.abs(pos - i), 0, 1)
    out = out / (np.max(np.abs(out)) + 1e-9) + band(noise(n), 500, 3500) * breath
    return out / (np.max(np.abs(out)) + 1e-9)


def drum(freq, seconds=0.3, vol=1.0, slap=0.5):
    """a jungle drum: the skin's thump, its note sagging as it settles, and
    the slap of the hand"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    ph = np.cumsum(freq * (1 + 0.4 * np.exp(-t / 0.02))) / RATE
    skin = (np.tanh(1.8 * sine(ph)) / np.tanh(1.8) + 0.3 * sine(1.5 * ph) * np.exp(-t / 0.05)) * env(n, 0.001, seconds, 2.6)
    return mix(skin, strike(0.02, 500, 5000, slap)) * vol


def hold(x, every):
    """x at a lower sample rate: each sample held for `every` (a number, or
    one a sample) - the crunch of a cheap old computer"""
    n = len(x)
    k = np.floor(np.cumsum(1.0 / np.broadcast_to(np.asarray(every, float), (n,)))).astype(int)
    first = np.r_[0, np.nonzero(np.diff(k))[0] + 1]
    return x[np.repeat(first, np.diff(np.r_[first, n]))]


def stutter(x, start, chunk, times, fall=1.0):
    """a glitch: the bit of x at `start` (`chunk` long) caught and played
    `times` over in its own place, each `fall` times as loud as the last"""
    x = x.copy()
    i, m = n_of(start), n_of(chunk)
    piece = x[i:i + m].copy()
    r = min(len(piece) // 2, n_of(0.001))
    piece[:r] *= np.linspace(0, 1, r)
    piece[len(piece) - r:] *= np.linspace(1, 0, r)
    for j in range(times):
        a = i + j * m
        k = min(len(piece), len(x) - a)
        if k <= 0:
            break
        x[a:a + k] = piece[:k] * fall ** j
    b = i + times * m
    x[b:b + r] *= np.linspace(0, 1, len(x[b:b + r]))
    return x


def gate(n, spans, ramp=0.0015):
    """on during each (start, end) in seconds, off between - the corners
    rounded so it doesn't click"""
    g = np.zeros(n)
    for a, b in spans:
        g[n_of(a):n_of(b)] = 1
    return smooth(g, ramp)


def drip(freq, vol=1.0, seconds=0.04):
    """a drop of ink landing: a little "plip" (a bubble's note jumping up)"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    return sine(np.cumsum(freq * (2.2 - 1.2 * np.exp(-t / 0.008))) / RATE) * env(n, 0.001, seconds, 2.5) * vol


def pop(f0=300, f1=1500, seconds=0.06, vol=1.0):
    """a cartoon pop (a cork, a bubble): a tone jumping up, a puff of air"""
    puff = band(noise(n_of(0.015)), 400, 5000) * env(n_of(0.015), 0.0005, 0.015, 3) * 0.6
    return mix(sine(sweep(f0, f1, seconds)) * env(n_of(seconds), 0.001, seconds, 2.5), puff) * vol


def key(vol=1.0, pitch=1.0):
    """a keyboard key pressed: the plastic click, the thock of it bottoming out"""
    thock = metal(620 * pitch, 0.05, ((1, 1.0), (2.45, 0.4), (4.1, 0.15)), 0.6, int(S.rng.integers(1 << 30)))
    body = band(noise(n_of(0.015)), 250, 2500) * env(n_of(0.015), 0.0005, 0.015, 3) * 0.5
    return mix(strike(0.003, 2500, 11000, 0.7), at(thock, 0.002), at(body, 0.002)) * vol


def scratch(seconds, rate, vol=1.0, lo=1500, hi=6500):
    """a pencil scribbling: graphite rasping on paper, back and forth about
    `rate` strokes a second"""
    n = n_of(seconds)
    wob = band(noise(n), hi=8)
    ph = np.cumsum(rate * (1 + 0.3 * wob / (np.max(np.abs(wob)) + 1e-9))) / RATE
    paper = band(noise(n), hi=400)
    rasp = band(noise(n), lo, hi) * (1 + 0.6 * paper / (np.max(np.abs(paper)) + 1e-9))
    return (rasp + grit(seconds, 900, lo, hi * 1.2, 0.4, grain=0.001)) * np.abs(np.sin(np.pi * ph)) ** 1.5 * vol


# ----------------------------------------------------------------------
# THE JUNGLE PACK (Kongo, the gorilla king of the jungle: leaves, vines,
# bananas, wooden barrels with iron bands, jungle drums, gold for his crown)
# ----------------------------------------------------------------------
def leaf_swish():
    # a swing through leaves: an airy swish, the leaves rustling all along it
    # (the swish kept soft on top, so the leaves are what you hear up there)
    s = 0.3
    t = np.arange(n_of(s)) / RATE
    air = band(whoosh(s, 300, 2400, 1.3, 1.5), hi=2200)
    hum = tri(sweep(90, 130, s)) * env(n_of(s), 0.1, s, 1.6) * 0.18
    rustle = leaves(s, 1200, 1.5, shape=np.sin(np.pi * t / s) ** 1.5)
    return master(mix(air / np.max(np.abs(air)), hum, rustle), drive=1.5)


def leaf_rustle():
    # leaves and bananas landing: a soft pat-pat and a little rustle (gentle
    # and short: lots land)
    s = 0.14
    pats = mix(pat(0.8), at(pat(0.45, 1.2), 0.05), at(pat(0.25, 0.9), 0.09))
    return master(mix(pats, leaves(s, 500, 0.5, shape=env(n_of(s), 0.004, s, 1.4))), lo=80, hi=8000)


def bark_thwack():
    # a hit: a woody THWACK - the crack of it, a hollow tock ringing, bits
    # of bark flying off
    tock = mix(metal(300, 0.34, WOOD, 0.8, 11), metal(470, 0.2, WOOD, 0.5, 12), metal(760, 0.12, WOOD, 0.3, 10))
    knock_ = tri(sweep(240, 95, 0.12)) * env(n_of(0.12), 0.001, 0.12, 2.6) * 0.7
    hit = crushed(mix(strike(0.03, 600, 9000), knock_, tock * 0.6), 22)
    bark = grit(0.3, 200, 900, 5500, 0.35, grain=0.003, shape=env(n_of(0.3), 0.01, 0.3, 1.6))
    return master(mix(hit * 0.7, tock * 0.6, at(bark, 0.015)), drive=1.5)


def barrel_swing():
    # the barrel hammer swung: a deep, heavy wooden whoosh, its staves
    # knocking and its iron bands rattling
    s = 0.42
    r = S.rng
    hum = tri(sweep(58, 88, s)) * env(n_of(s), 0.12, s, 1.5) * 0.35
    staves = mix(*[at(knock(r.uniform(240, 380), 0.07, v), tt) for tt, v in ((0.08, 0.14), (0.16, 0.22), (0.24, 0.2), (0.31, 0.12))])
    bands = mix(*[at(metal(r.uniform(1000, 1500), 0.08, HOOP[:3], 0.06 * np.sin(np.pi * tt / s), int(r.integers(1 << 30))), tt)
                  for tt in np.sort(r.uniform(0.08, 0.36, 6))])
    return master(mix(whoosh(s, 130, 1700, 1.6, 1.4), hum, staves, bands))


def splinter_crack():
    # wood splintering: a dry little snap and the splinters ticking down
    # (gentle and short: lots land)
    r = S.rng
    snap = mix(strike(0.006, 1800, 9000, 0.6), metal(1350, 0.05, WOOD, 0.45, 13))
    ticks, tt = [], 0.025
    for i in range(6):
        ticks.append(at(knock(r.uniform(900, 2300), 0.035, 0.35 * (1 - i / 7)), tt))
        tt += r.uniform(0.015, 0.035)
    crackle = grit(0.15, 350, 1500, 7000, 0.3, grain=0.0015, shape=env(n_of(0.15), 0.002, 0.15, 1.8))
    return master(mix(snap, crackle, *ticks), lo=150, hi=10000)


def barrel_thud():
    # a heavy hit: a deep, hollow barrel THUD, its iron band ringing
    body = band(noise(n_of(0.12)), 150, 1200) * env(n_of(0.12), 0.001, 0.12, 3) * 0.6
    hit = crushed(mix(thump(125, 50, 0.42, 0.8, 2.2), strike(0.03, 400, 6000, 0.8), body), 24)
    hoop = mix(metal(540, 0.45, HOOP, 0.4, 16), metal(1220, 0.3, HOOP, 0.15, 17))
    return master(mix(hit * 0.8, metal(175, 0.4, BARREL, 0.7, 15), at(hoop, 0.004)), lo=50, drive=1.4)


def crown_swing():
    # the Secret's swing: a big whoosh, a harp-quick run up golden chimes,
    # and a regal chord shimmering after it
    run = mix(*[at(chime(midi(m), 0.24, 0.16), 0.06 + i * 0.022) for i, m in enumerate((74, 78, 81, 86, 90, 93))])
    cs = 0.3
    t = np.arange(n_of(cs)) / RATE
    chord = sum(chip(midi(m), cs, 0.5, 1.0, a=0.02, d=0.1, s=0.7, r=0.12, vib=0.004) for m in (81, 86, 90)) / 3
    chord = band(chord, hi=5000) * (1 + 0.4 * np.sin(2 * np.pi * 12 * t)) * 0.16
    return master(mix(whoosh(0.34, 220, 3300, 1.4, 1.5), run, at(chord, 0.16), glints(0.2, 5, 0.045, 0.07, (98, 102, 105, 110))))


def banana_bounce():
    # a banana bouncing: a cartoon boing-bonk (gentle and short: lots land)
    s = 0.12
    n = n_of(s)
    t = np.arange(n) / RATE
    f = (330 + 450 * (t / s) ** 0.8) * (1 + 0.12 * np.sin(2 * np.pi * 32 * t) * np.exp(-t / 0.06))
    boing = band(0.5 * pulse(f, n, 0.25) + 0.5 * tri(np.cumsum(f / 2) / RATE), hi=4000) * env(n, 0.003, s, 1.6)
    bonk = mix(sine(sweep(700, 480, 0.1)) * env(n_of(0.1), 0.001, 0.1, 2.2), metal(560, 0.09, WOOD, 0.4, 14), strike(0.006, 800, 5000, 0.3))
    return master(mix(boing * 0.7, at(bonk, 0.12)), lo=120, hi=8000)


def gold_thump():
    # the Secret's hit: a heavy THUMP, a golden chime ringing out of it
    body = band(noise(n_of(0.15)), 120, 1500) * env(n_of(0.15), 0.001, 0.15, 2.8) * 0.5
    hit = crushed(mix(thump(118, 46, 0.38, 0.85, 2.2), strike(0.04, 500, 8000, 0.9), body), 24)
    gold = mix(chime(midi(86), 0.5, 0.34), chime(midi(93), 0.42, 0.2), at(chime(midi(98), 0.3, 0.12), 0.03))
    return master(mix(hit * 0.8, at(gold, 0.008), glints(0.1, 4, 0.06, 0.08, (98, 102, 105))), lo=50, drive=1.2)


def vine_whip():
    # a vine lashing out: a swish speeding up, a sharp CRACK, the leaves
    # shaking after it
    s = 0.24
    n = n_of(s)
    k = np.arange(n) / n
    lash = swoop(s, 500, 7000, 1.6) * 0.9
    sing = sine(sweep(600, 2400, s)) * k ** 2.6 * 0.12
    sing[-n_of(0.005):] *= np.linspace(1, 0, n_of(0.005))
    crack = crushed(mix(strike(0.006, 1500, 11000, 1.3), strike(0.035, 700, 6000, 0.45), thump(180, 90, 0.08, 0.25, 2.0)), 16)
    shake = leaves(0.26, 550, 0.5, shape=env(n_of(0.26), 0.004, 0.26, 1.7))
    return master(mix(lash, sing, at(crack * 0.9, s), at(shake, s + 0.008)), hi=10000, drive=1.4)


def ape_grunt():
    # a funny little gorilla grunt: "uh-HOO!" (round and buzzy, not scary)
    n1, n2 = n_of(0.09), n_of(0.28)
    uh = ape(np.geomspace(150, 125, n1), ('o',), 0.4, 0.08) * A.adsr(n1, 0.008, 0.05, 0.7, 0.03)
    t = np.arange(n2) / RATE
    hoo = ape(smooth(np.interp(t, [0, 0.1, 0.28], [175, 300, 235]), 0.02), ('u', 'o'), 0.25, 0.1) * A.adsr(n2, 0.015, 0.1, 0.55, 0.07)
    huff = band(noise(n_of(0.05)), 600, 3500) * env(n_of(0.05), 0.005, 0.05, 1.5) * 0.25
    return master(crushed(mix(uh * 0.6, at(huff, 0.085), at(hoo, 0.1)), 24), lo=70, hi=7000)


def ape_roar():
    # the Roar: a big, chunky cartoon gorilla ROAR (buzzy, a bit crunchy -
    # fun, not scary)
    s = 0.9
    n = n_of(s)
    t = np.arange(n) / RATE
    f = smooth(np.interp(t, [0, 0.08, 0.22, 0.65, 0.9], [105, 155, 145, 135, 92]), 0.02)
    voice = ape(f, ('o', 'a', 'a', 'o'), 1.0, 0.3) + 0.35 * ape(2 * f, ('a', 'a', 'o'), 0.6, 0.0)
    rumble = band(noise(n), 40, 220)
    x = crushed(voice, 18) + rumble / (np.max(np.abs(rumble)) + 1e-9) * env(n, 0.08, s, 1.2) * 0.3
    return master(x * A.adsr(n, 0.03, 0.25, 0.85, 0.18), lo=55, drive=1.4)


def chest_thump():
    # three quick, hollow chest pounds: thump-thump-THUMP
    def pound(f, v, s=0.18):
        chest = metal(f * 2.1, s, ((1, 1.0), (1.62, 0.45), (2.43, 0.2)), 0.8, int(f))
        slap = band(noise(n_of(0.035)), 300, 3000) * env(n_of(0.035), 0.0005, 0.035, 3) * 0.7
        return mix(thump(f, f * 0.6, s, 0.7, 2.4), chest, slap) * v
    return master(mix(pound(135, 0.75), at(pound(145, 0.8), 0.17), at(pound(128, 1.0, 0.26), 0.34)), lo=60, drive=1.3)


def fang_snap():
    # a bite: the jaws snapping shut (a rush, the teeth clacking) and a
    # little sting ringing after it
    s = 0.07
    clack = mix(strike(0.004, 2500, 11000, 0.9), metal(1900, 0.03, ((1, 1.0), (2.6, 0.5)), 0.5, 21),
                at(strike(0.003, 3000, 11000, 0.6), 0.011), thump(240, 110, 0.07, 0.4, 2.0))
    sting = chip(np.geomspace(2600, 3300, n_of(0.17)), 0.17, 0.125, 0.18, d=0.04, s=0.4, r=0.08, vib=0.01)
    return master(mix(swoop(s, 1500, 6500) * 0.4, at(crushed(clack, 22), s), at(sting, s + 0.02), at(metal(3100, 0.2, BAR, 0.08, 22), s + 0.015)),
                  drive=1.4)


def vine_creak():
    # swinging on a vine: the rope creaking taut, then the whoosh of the swing
    cs = 0.34
    n = n_of(cs)
    t = np.arange(n) / RATE
    wob = band(noise(n), hi=30)
    rate = np.interp(t, [0, 0.12, cs], [38, 95, 55]) * (1 + 0.25 * wob / (np.max(np.abs(wob)) + 1e-9))
    ph = np.cumsum(rate) / RATE
    hits = (np.diff(np.floor(ph), prepend=0) > 0) * S.rng.uniform(0.5, 1.0, n)
    kt = np.arange(n_of(0.014)) / RATE
    rope = (sine(620 * kt) + 0.6 * sine(1450 * kt + 0.3) + 0.3 * sine(2600 * kt + 0.7)) * np.exp(-kt / 0.0035)
    creak = band(np.convolve(hits, rope)[:n], 250, 5000) * np.sin(np.pi * t / cs) ** 0.7
    return master(mix(creak / (np.max(np.abs(creak)) + 1e-9) * 0.7, at(whoosh(0.42, 180, 2400, 1.4, 1.3), 0.18)))


def leaf_sweep():
    # a big sweeping whoosh full of leaves
    s = 0.52
    n = n_of(s)
    t = np.arange(n) / RATE
    air = band(whoosh(s, 220, 2600, 1.5, 1.3), hi=2400)
    swirl = band(noise(n), 60, 320) * env(n, 0.18, s, 1.5) * 0.3
    rustle = leaves(s, 1500, 1.6, shape=np.sin(np.pi * t / s) ** 1.2)
    return master(mix(air / np.max(np.abs(air)), swirl, rustle), drive=1.5)


def barrel_curl():
    # a barrel closing round you: a quick wooden swoop, then a hollow kl-CLONK
    clonk = crushed(mix(metal(310, 0.26, BARREL, 1.0, 18), thump(165, 80, 0.16, 0.7, 2.0), strike(0.01, 600, 5000, 0.6)), 24)
    return master(mix(swoop(0.09, 500, 3000) * 0.45, at(knock(470, 0.05, 0.35), 0.065), at(clonk, 0.09), at(metal(820, 0.2, HOOP, 0.12, 19), 0.095)),
                  drive=1.3)


def barrel_rumble():
    # a barrel rolling fast along the ground: a rumbling roll, its staves
    # knocking round and round, the grit crunching under it
    s = 0.6
    n = n_of(s)
    t = np.arange(n) / RATE
    r = S.rng
    roll = band(noise(n), 40, 400) * (0.55 + 0.45 * np.sin(2 * np.pi * 11 * t) ** 2) * 1.8
    times = np.arange(0.012, s - 0.04, 1 / 22)
    staves = mix(*[at(knock(r.uniform(190, 280), 0.05, r.uniform(0.12, 0.22)), tt + r.uniform(-0.005, 0.005)) for tt in times])
    crunch = grit(s, 160, 600, 4000, 0.35, grain=0.004)
    grow = np.clip(t / 0.06, 0, 1) * np.clip((s - t) / 0.12, 0, 1)
    return master(mix(roll, staves, crunch)[:n] * grow, lo=45, drive=1.4)


def barrel_burst():
    # a barrel bursting apart: a splintering CRASH, staves clattering down,
    # an iron band ringing off
    crunch = band(noise(n_of(0.25)), 250, 4500) * env(n_of(0.25), 0.001, 0.25, 2.6) * 0.8
    crash = crushed(mix(strike(0.05, 500, 10000, 1.2), thump(140, 58, 0.3, 0.7, 2.0), crunch), 22)
    splinters = grit(0.35, 500, 1200, 8000, 0.45, grain=0.002, shape=env(n_of(0.35), 0.002, 0.35, 1.8))
    r = S.rng
    staves, tt = [], 0.04
    for i in range(13):
        staves.append(at(knock(r.uniform(240, 800), r.uniform(0.06, 0.12), r.uniform(0.4, 0.8) * (1 - i / 15)), tt))
        tt += r.uniform(0.015, 0.05)
    hoop = mix(at(metal(470, 0.45, HOOP, 0.22, 20), 0.05), at(metal(690, 0.35, HOOP, 0.12, 21), 0.21))
    return master(mix(crash, splinters, *staves, hoop), lo=50, drive=1.4)


def barrel_bat():
    # a big BONK: the hammer batting a barrel away (and off it flies)
    bonk = mix(sine(sweep(620, 390, 0.16)) * env(n_of(0.16), 0.001, 0.16, 2.0) * 0.8, metal(400, 0.25, BARREL, 0.7, 22),
               thump(160, 70, 0.2, 0.6, 2.0), strike(0.015, 600, 7000, 0.9))
    blip = chip(np.geomspace(520, 300, n_of(0.1)), 0.1, 0.5, 0.18, d=0.04, s=0.3, r=0.03)
    return master(mix(crushed(bonk, 22), blip, at(whoosh(0.28, 300, 2400, 0.6, 1.3), 0.07)), drive=1.4)


def barrel_blast():
    # a barrel exploding: a BOOM, wood flying everywhere and pattering down
    s = 0.7
    n = n_of(s)
    blast = A.sweep_lp(noise(n), np.geomspace(6000, 300, n)) * env(n, 0.002, s, 2.2)
    crunch = band(noise(n_of(0.2)), 300, 4000) * env(n_of(0.2), 0.001, 0.2, 2.6) * 0.8
    hit = crushed(mix(thump(110, 40, 0.6, 0.9, 2.5), strike(0.06, 300, 10000, 1.0), blast, crunch), 22)
    r = S.rng
    debris = mix(*[at(knock(r.uniform(260, 1000), r.uniform(0.05, 0.1), r.uniform(0.3, 0.6) * min(1, tt / 0.15) * np.exp(-tt / 0.4)), tt)
                   for tt in 0.04 + np.minimum(r.exponential(0.22, 18), 0.55)])
    splinters = grit(0.75, 260, 1000, 7000, 0.5, grain=0.002, shape=env(n_of(0.75), 0.01, 0.75, 1.6))
    return master(mix(hit, debris, splinters), lo=50, drive=1.5)


def crown_call():
    # calling the sky fist: jungle drums (ba-da-da-BOOM) and a short golden fanfare
    out = np.zeros(n_of(1.05))
    for t0, f, v in ((0.0, 210, 0.55), (0.08, 210, 0.45), (0.16, 160, 0.6), (0.28, 105, 1.0)):
        A.place(out, drum(f, 0.5 if f < 150 else 0.3, v), t0)
    horns = np.zeros(n_of(1.05))
    for t0, d, chord in ((0.36, 0.08, (79, 74)), (0.46, 0.08, (79, 74)), (0.56, 0.42, (86, 83, 79))):
        for j, m in enumerate(chord):
            A.place(horns, A.brass(midi(m), d, 0.32 if j == 0 else 0.2), t0)
    A.place(out, band(horns, hi=4000), 0)
    A.place(out, chime(midi(98), 0.4, 0.2), 0.56)
    A.place(out, glints(0, 6, 0.06, 0.08, (98, 102, 105, 110)), 0.6)
    return master(out, lo=50, hi=9000)


def sky_whoosh():
    # something huge falling out of the sky: a deep whoosh sweeping down,
    # the rush of it growing and growing
    s = 0.8
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    air = band(A.sweep_lp(noise(n), 4000 * (350 / 4000) ** k), 120) * 1.2
    rumble = band(noise(n), 35, 160) * k ** 1.5 * 1.5
    tone = band(pulse(hold(900 * (150 / 900) ** k, n_of(1 / 30)), n, 0.5), hi=3000) * 0.1
    grow = (0.12 + 0.88 * k ** 1.7) * np.clip(t / 0.03, 0, 1) * np.clip((s - t) / 0.02, 0, 1)
    return master(mix(air, rumble, tone) * grow)


def fist_smash():
    # the giant fist smashing the ground: a huge, crunchy BOOM, rocks flying
    # and tumbling
    crunch = band(noise(n_of(0.35)), 200, 3500) * env(n_of(0.35), 0.001, 0.35, 2.6) * 1.1
    dust = band(noise(n_of(1.0)), 60, 1000) * env(n_of(1.0), 0.003, 1.0, 1.8) * 0.5
    hit = crushed(mix(thump(100, 38, 0.85, 1.0, 2.6), strike(0.08, 300, 9000, 1.1), crunch, dust), 20)
    r = S.rng
    rocks = []
    for i in range(12):
        tt = 0.06 + 0.66 * r.random() ** 1.8
        v = r.uniform(0.5, 1.0) * np.exp(-tt / 0.6)
        rocks.append(at(mix(strike(0.012, 700, 5000, 0.8), thump(r.uniform(170, 320), 80, 0.07, 0.5, 2.0)) * v, tt))
    rubble = grit(0.95, 150, 250, 3000, 1.0, grain=0.008, shape=env(n_of(0.95), 0.02, 0.95, 1.6))
    return master(mix(hit, rubble, *rocks), lo=55, drive=1.3)


# ----------------------------------------------------------------------
# THE CANVAS PACK (Scribble, a living doodle: pencils, paper, erasers, ink
# and paint - and the computer he lives in: keys, copy and paste, pixels,
# glitches, DELETE)
# ----------------------------------------------------------------------
def brush_swish():
    # a swing: a paintbrush swished - the air, the bristles' soft "shhk",
    # a flick of ink off the end
    s = 0.28
    n = n_of(s)
    fl = np.abs(band(noise(n), hi=120))
    bristles = band(noise(n), 2500, 9000) * (fl / (np.max(fl) + 1e-9)) ** 1.5 * env(n, 0.06, s, 1.8)
    air = whoosh(s, 450, 3800, 1.2, 1.6)
    return master(mix(air / np.max(np.abs(air)), bristles / (np.max(np.abs(bristles)) + 1e-9) * 0.5,
                      at(squelch(0.08, 700, 260, 0.35), 0.17), at(drip(1300, 0.25), 0.205)))


def ink_splat():
    # a little wet splat of ink (gentle and short: lots land)
    smack = band(noise(n_of(0.015)), 700, 5000) * env(n_of(0.015), 0.0005, 0.015, 3) * 0.5
    return master(mix(squelch(0.15, 430, 100, 0.9), smack, at(drip(1100, 0.2), 0.05), at(drip(1500, 0.12), 0.09), at(drip(1250, 0.07), 0.13)),
                  lo=80, hi=9000)


def ink_thwack():
    # a hit: an inky slap - a crack and a thud, a wet splat, drops flying
    knock_ = tri(sweep(210, 80, 0.12)) * env(n_of(0.12), 0.001, 0.12, 3) * 0.6
    slap = crushed(mix(strike(0.025, 800, 9000), knock_), 22)
    r = S.rng
    drops = mix(*[at(drip(r.uniform(900, 1800), r.uniform(0.12, 0.25) * (1 - i / 6)), 0.06 + i * 0.05 + r.uniform(0, 0.02)) for i in range(5)])
    return master(mix(slap * 0.8, at(squelch(0.3, 330, 60, 0.9), 0.01), drops), drive=1.3)


def copy_swish():
    # the Mythic's swing: a swish, and a digital copy of it right behind -
    # lower-res and crunchier - and a fainter copy of the copy
    sw = whoosh(0.2, 500, 4300, 1.3, 1.5)
    sw = sw / np.max(np.abs(sw))
    copy = band(crushed(hold(sw, 5), 10), hi=7000) * 0.55
    copy2 = band(crushed(hold(sw, 9), 6), hi=5000) * 0.25
    blip = chip(midi(91), 0.05, 0.25, 0.12, d=0.03, s=0.4, r=0.015)
    return master(mix(sw, at(copy, 0.14), at(blip, 0.14), at(copy2, 0.28)))


def pixel_pop():
    # pixels popping: a tiny digital blip, up a step (gentle and short: lots pop)
    tick = sine(sweep(600, 1500, 0.015)) * env(n_of(0.015), 0.0005, 0.015, 2) * 0.45
    a = chip(midi(88), 0.04, 0.5, 0.4, d=0.012, s=0.15, r=0.01)
    b = chip(midi(95), 0.08, 0.5, 0.4, d=0.015, s=0.06, r=0.04)
    return master(band(mix(tick, a, at(b, 0.035)), hi=5000), hi=9000)


def paste_hit():
    # the Mythic's hit: an inky thwack, the digital "paste" bleep (bl-ip!)
    # and a crunchy copy of the hit landing on it
    knock_ = tri(sweep(220, 85, 0.12)) * env(n_of(0.12), 0.001, 0.12, 3) * 0.6
    slap = crushed(mix(strike(0.025, 800, 9000), knock_, squelch(0.15, 340, 80, 0.6)), 20)
    bleep = mix(chip(midi(84), 0.05, 0.25, 0.3, d=0.03, s=0.6, r=0.01), at(chip(midi(91), 0.26, 0.25, 0.3, d=0.06, s=0.3, r=0.14), 0.05))
    echo = band(crushed(hold(slap, 6), 8), hi=6000) * 0.35
    echo2 = band(crushed(hold(slap, 11), 5), hi=4500) * 0.18
    return master(mix(slap * 0.6, at(bleep, 0.03), at(echo, 0.11), at(echo2, 0.22)))


def glitch_swing():
    # the Secret's swing: a swish that glitches - it catches and stutters,
    # drops to a crunchy low resolution, catches again
    s = 0.42
    n = n_of(s)
    sw = whoosh(s, 400, 4800, 1.3, 1.4)
    x = stutter(stutter(sw / np.max(np.abs(sw)), 0.1, 0.022, 3), 0.27, 0.016, 4, 0.85)
    low = gate(n, [(0.17, 0.24), (0.34, 0.39)])
    x = x * (1 - low) + band(crushed(hold(x, 7), 7), hi=8000) * low
    blips = mix(at(chip(midi(96), 0.03, 0.5, 0.15, d=0.02, s=0.5, r=0.005), 0.1), at(chip(midi(89), 0.03, 0.5, 0.12, d=0.02, s=0.5, r=0.005), 0.27))
    return master(mix(x, blips))


def glitch_hit():
    # the Secret's hit: a crunchy impact that glitches - the hit caught and
    # played again, cruder each time, digital noise spitting after it
    body = band(noise(n_of(0.15)), 150, 3000) * env(n_of(0.15), 0.001, 0.15, 2.8) * 0.7
    hit = crushed(mix(thump(130, 55, 0.3, 0.6, 2.4), strike(0.03, 500, 9000, 1.0), body * 1.3), 16)
    m = n_of(0.028)
    caught = hit[:m] * np.minimum(1, np.minimum(np.arange(m), m - 1 - np.arange(m)) / n_of(0.001))
    again = [at(band(crushed(hold(caught, e), q), hi=9000) * v, t0) for t0, e, q, v in ((0.05, 3, 8, 0.7), (0.078, 6, 6, 0.5), (0.106, 10, 4, 0.35))]
    n = n_of(0.25)
    spit = crushed(hold(noise(n), 12), 4) * gate(n, [(0.0, 0.03), (0.06, 0.08), (0.13, 0.15), (0.2, 0.21)]) * env(n, 0.001, 0.25, 1.2) * 0.25
    bwoop = chip(np.geomspace(900, 140, n_of(0.26)), 0.26, 0.5, 0.15, d=0.06, s=0.5, r=0.06)
    return master(mix(hit, *again, at(spit, 0.14), at(bwoop, 0.04)), drive=1.4)


def glitch_wave():
    # a wave of glitch: a sweep of digital noise swelling up and away,
    # stuttering and stepping as it goes
    s = 0.6
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    r = S.rng
    swell = np.sin(np.pi * k ** 0.7) ** 2.5
    hiss = A.sweep_lp(hold(noise(n), np.interp(k, [0, 0.4, 1], [14, 2, 10])), 700 + 6500 * swell)
    spans, tt = [], 0.0
    while tt < s:
        on = r.uniform(0.012, 0.045)
        spans.append((tt, tt + on))
        tt += on + r.uniform(0.004, 0.02)
    tone = band(pulse(hold(300 * 6 ** swell, n_of(1 / 40)), n, 0.25), hi=4000) * 0.2
    return master(crushed(mix(hiss, tone) * gate(n, spans) * swell, 14))


def doodle_pop():
    # a doodle popping into being: a quick scribble, a cartoon POP, a happy
    # little "ta-da"
    tada = mix(*[at(chip(midi(m), ln, 0.25, 0.4, d=0.04, s=0.4, r=0.02 if i < 2 else 0.05), i * 0.045)
                 for i, (m, ln) in enumerate(((84, 0.05), (88, 0.05), (91, 0.12)))])
    sketch = scratch(0.08, 30, 0.5) * env(n_of(0.08), 0.01, 0.08, 1.0)
    return master(mix(sketch, at(pop(260, 1400, 0.06, 0.7), 0.07), at(tada, 0.12)))


def eraser_squeak():
    # rubbing out with an eraser: squeak-squeak-squeak, the rubber dragging
    # back and forth over the paper
    out = np.zeros(n_of(0.42))
    for t0, d, f0, f1 in ((0.0, 0.12, 1500, 1900), (0.14, 0.12, 1850, 1450), (0.28, 0.13, 1550, 2000)):
        n = n_of(d)
        t = np.arange(n) / RATE
        wob = band(noise(n), hi=60)
        ph = np.cumsum(np.geomspace(f0, f1, n) * (1 + 0.03 * wob / (np.max(np.abs(wob)) + 1e-9))) / RATE
        squeak = (sine(ph) + 0.35 * sine(2 * ph) + 0.12 * sine(3 * ph)) * (0.55 + 0.45 * np.sin(2 * np.pi * 38 * t) ** 2)
        rub = band(noise(n), 500, 3200)
        A.place(out, (0.5 * squeak + 0.5 * rub / (np.max(np.abs(rub)) + 1e-9)) * A.adsr(n, 0.015, 0.05, 0.8, 0.03), t0)
    return master(out, hi=8000)


def erase_poof():
    # something rubbed out: a soft poof, a little shimmer as it goes
    s = 0.36
    n = n_of(s)
    puff = A.sweep_lp(noise(n), np.geomspace(3000, 300, n)) * env(n, 0.012, s, 2.2)
    body = band(noise(n_of(0.15)), 150, 900) * env(n_of(0.15), 0.01, 0.15, 2.0) * 0.5
    return master(mix(puff, body, glints(0.05, 6, 0.045, 0.12, (103, 100, 98, 96, 93, 91), climb=True)), hi=10000)


def pencil_sharpen():
    # a pencil sharpener grinding: the blade shaving the wood round and
    # round - crunchy and rasping
    s = 0.6
    n = n_of(s)
    t = np.arange(n) / RATE
    turns = np.abs(np.sin(np.pi * 7 * t)) ** 0.6
    rasp = band(noise(n), 900, 6000) * (0.35 + 0.65 * turns)
    crunch = grit(s, 1500, 1000, 7000, 0.6, grain=0.0012, shape=0.3 + 0.7 * turns)
    wob = band(noise(n), hi=40)
    chatter = band(pulse(210 * (1 + 0.1 * wob / (np.max(np.abs(wob)) + 1e-9)), n, 0.3), 300, 2500) * turns * 0.15
    return master(mix(rasp, crunch, chatter) * A.adsr(n, 0.03, 0.1, 1.0, 0.06), hi=10000)


def ink_splosh():
    # the ink splash: a heavy, wet SPLOSH slamming down, a spray of ink and
    # drops raining after it
    spray = band(noise(n_of(0.4)), 500, 6000) * env(n_of(0.4), 0.003, 0.4, 2.4) * 0.5
    slam = crushed(mix(thump(120, 44, 0.5, 0.9, 2.2), strike(0.04, 400, 8000, 0.9)), 22)
    r = S.rng
    drops = mix(*[at(drip(r.uniform(800, 2000), r.uniform(0.1, 0.3) * (1 - i / 16)), 0.12 + i * 0.033 + r.uniform(0, 0.025)) for i in range(14)])
    return master(mix(slam * 0.8, squelch(0.45, 300, 48, 1.0), at(squelch(0.18, 560, 150, 0.45), 0.06), at(spray, 0.01), drops), lo=45, drive=1.4)


def scribble_slash():
    # the doodle's dash-slash: a pencil scratching furiously back and forth,
    # and the cut through the air
    s = 0.38
    return master(mix(whoosh(0.3, 700, 6000, 0.6, 1.8), scratch(s, 26, 1.0) * env(n_of(s), 0.01, s, 1.5)), drive=1.1)


def redraw_swish():
    # redrawn: a quick swish played backwards - the pencil strokes sucked
    # back in with a rewinding chirp - snapping back into place
    s = 0.36
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    strokes = scratch(s, 22, 0.6)[::-1] * k ** 1.5
    strokes[-n_of(0.006):] *= np.linspace(1, 0, n_of(0.006))
    f = 2400 * (500 / 2400) ** k * (1 + 0.25 * np.sign(np.sin(2 * np.pi * 28 * t)))
    chirp = band(pulse(f, n, 0.5), hi=4000) * np.sin(np.pi * k) * 0.12
    return master(mix(swoop(s, 600, 6600, 2.5), strokes, chirp, at(knock(1300, 0.04, 0.4), s - 0.004)))


def copy_click():
    # ctrl+C: two keys clicking down (ctrl, then C) and a blip - copied
    return master(mix(key(0.8), at(key(1.0, 1.08), 0.07), at(chip(midi(88), 0.13, 0.25, 0.3, d=0.04, s=0.4, r=0.06), 0.12)), hi=10000)


def paste_pop():
    # ctrl+V: the keys clicking down, then a bright POP as it's pasted in
    bright = mix(chip(midi(96), 0.04, 0.25, 0.3, d=0.03, s=0.5, r=0.01), at(chip(midi(103), 0.1, 0.25, 0.28, d=0.04, s=0.3, r=0.04), 0.035))
    return master(mix(key(0.8), at(key(1.0, 1.12), 0.06), at(pop(300, 1700, 0.05, 1.0), 0.1), at(bright, 0.12), glints(0.16, 2, 0.05, 0.08)),
                  hi=11000, drive=1.5)


def glitch_buzz():
    # the computer glitching: a harsh error buzz cutting in and out, getting
    # stuck, spitting digital noise, then dying away
    s = 0.8
    n = n_of(s)
    t = np.arange(n) / RATE
    f = 110 * np.where(t < 0.6, 1.0, (40 / 110) ** ((t - 0.6) / 0.2))
    buzz = band(crushed(0.5 * pulse(f, n, 0.5) + 0.35 * pulse(f * 1.06, n, 0.25) + 0.25 * pulse(f * 2.01, n, 0.125), 8), hi=4000)
    whine = band(pulse(3100, n, 0.5), hi=6000) * 0.05
    g = gate(n, [(0, 0.12), (0.15, 0.2), (0.235, 0.255), (0.29, 0.44), (0.47, 0.5), (0.52, s)])
    spit = crushed(hold(noise(n), 10), 4) * gate(n, [(0.12, 0.15), (0.2, 0.235), (0.44, 0.47)]) * 0.45
    x = stutter((buzz + whine) * g + spit, 0.33, 0.025, 4)
    return master(x * A.adsr(n, 0.005, 0.1, 1.0, 0.05), lo=55, hi=9000)


def delete_shatter():
    # DELETE: the key slammed down, a big crunchy digital smash, and
    # everything shattering into pixels that rain away
    s = 1.0
    n = n_of(s)
    t = np.arange(n) / RATE
    r = S.rng
    crunch = crushed(hold(noise(n_of(0.5)), 6), 6) * env(n_of(0.5), 0.001, 0.5, 2.4)
    smash = crushed(mix(thump(110, 38, 0.6, 1.0, 2.5), strike(0.05, 400, 10000, 1.2), crunch * 0.6), 12)
    pixels = np.zeros(n)
    notes = (84, 86, 88, 91, 93, 96, 98, 100, 103, 105, 108)
    tt = 0.0
    while tt < 0.88:
        u = tt / 0.88
        ln = r.uniform(0.02, 0.06)
        f = midi(notes[int(r.integers(len(notes)))]) * np.geomspace(1, r.uniform(0.7, 0.95), n_of(ln))
        A.place(pixels, chip(f, ln, (0.125, 0.25, 0.5)[int(r.integers(3))], r.uniform(0.4, 1.0) * (1 - 0.8 * u), d=0.01, s=0.3, r=0.005), tt)
        tt += r.exponential(0.006 + 0.04 * u ** 1.5)
    fall = band(pulse(hold(1400 * (70 / 1400) ** (t / 0.8), n_of(1 / 60)), n, 0.5), hi=3500) * env(n, 0.005, 0.8, 1.2) * 0.25
    return master(mix(key(0.9, 0.9), at(smash, 0.035), at(band(pixels, hi=9000) * 0.3, 0.035), at(fall, 0.035)), lo=45, drive=1.5)


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
    'Jungle': {
        # the swings, what they throw off and what they hit (and the
        # Secret's vine lashing out, and Kongo popping out of it)
        'Leaf Swish': leaf_swish,
        'Leaf Rustle': leaf_rustle,
        'Bark Thwack': bark_thwack,
        'Barrel Swing': barrel_swing,
        'Splinter Crack': splinter_crack,
        'Barrel Thud': barrel_thud,
        'Crown Swing': crown_swing,
        'Banana Bounce': banana_bounce,
        'Gold Thump': gold_thump,
        'Vine Whip': vine_whip,
        'Ape Grunt': ape_grunt,
        # the abilities: Roar, Fang, Vine Swing, Barrel Roll, Barrel Toss, Sky Fist
        'Ape Roar': ape_roar,
        'Chest Thump': chest_thump,
        'Fang Snap': fang_snap,
        'Vine Creak': vine_creak,
        'Leaf Sweep': leaf_sweep,
        'Barrel Curl': barrel_curl,
        'Barrel Rumble': barrel_rumble,
        'Barrel Burst': barrel_burst,
        'Barrel Bat': barrel_bat,
        'Barrel Blast': barrel_blast,
        'Crown Call': crown_call,
        'Sky Whoosh': sky_whoosh,
        'Fist Smash': fist_smash,
    },
    'Canvas': {
        # the swings, what they throw off and what they hit (and the
        # Secret's glitch wave, and a doodle popping out of it)
        'Brush Swish': brush_swish,
        'Ink Splat': ink_splat,
        'Ink Thwack': ink_thwack,
        'Copy Swish': copy_swish,
        'Pixel Pop': pixel_pop,
        'Paste Hit': paste_hit,
        'Glitch Swing': glitch_swing,
        'Glitch Hit': glitch_hit,
        'Glitch Wave': glitch_wave,
        'Doodle Pop': doodle_pop,
        # the abilities: Erase, Sharpen, Ink Splash, Doodle Clone, Copy-Paste, DELETE
        'Eraser Squeak': eraser_squeak,
        'Erase Poof': erase_poof,
        'Pencil Sharpen': pencil_sharpen,
        'Ink Splosh': ink_splosh,
        'Scribble Slash': scribble_slash,
        'Redraw Swish': redraw_swish,
        'Copy Click': copy_click,
        'Paste Pop': paste_pop,
        'Glitch Buzz': glitch_buzz,
        'Delete Shatter': delete_shatter,
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
