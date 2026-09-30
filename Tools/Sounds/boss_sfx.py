"""THE LAST FOUR BOSSES' SOUND EFFECTS, made from code like the rest: every
sound Kongo (floor 7), Petalina (floor 8), Scribble (floor 9) and King
Gavelgrunt (floor 10) ask for in Config.Bosses[n].Sounds, under exactly
those names. (Their songs come from elsewhere.) Cartoony and a little
8-bit: thumps, roars and voices made from shaped tones, wood and metal
from ringing overtones, goo from wet squelches.

    python3 boss_sfx.py              -> out/bosses/<Name>.ogg (and .wav)
    python3 boss_sfx.py Kongo Barrel ...only the ones starting with those
    python3 boss_sfx.py --demo       ...and Docs/boss_sounds.mp3, all of them
                                        one after another, to listen to

Tools/Upload/upload_assets.bat uploads out/bosses/*.ogg with everything else;
ServerScriptService/SoundLoader puts each in SoundService under its name
("Kongo_Roar" -> "Kongo Roar"), which is what each boss plays.
"""
import os
import subprocess
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_sfx as S  # noqa: E402
import weapon_sfx as W  # noqa: E402
import arcade_sfx as A  # noqa: E402
from make_sfx import RATE, env, square, tri, mix, at  # noqa: E402
from arcade_sfx import n_of, shape, place, reverb, soft_limit, trim, adsr, midi  # noqa: E402

OUT = os.path.join(HERE, 'out', 'bosses')
rng = np.random.default_rng(1)


def noise(n):
    return rng.uniform(-1, 1, n)


def sweep(f0, f1, seconds):
    """the running phase of a tone sliding from f0 to f1 (n_of(seconds) long)"""
    n = n_of(seconds)
    k = np.arange(n) / max(n, 1)
    return np.cumsum(f0 * (f1 / f0) ** k) / RATE


def sine(ph):
    return np.sin(2 * np.pi * ph)


def buf(seconds):
    return np.zeros(n_of(seconds))


def contour(points, n):
    """a pitch (or anything) moving through `points` [(0..1, value), ...]"""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return np.interp(np.linspace(0, 1, n), xs, ys)


# ----------------------------------------------------------------------
# building blocks
# ----------------------------------------------------------------------
VOWELS = {  # (formant frequencies, their strengths)
    'a': ((800, 1200, 2500), (1.0, 0.6, 0.25)),
    'o': ((500, 850, 2400), (1.0, 0.5, 0.15)),
    'u': ((330, 780, 2300), (1.0, 0.35, 0.1)),
    'e': ((480, 1800, 2500), (1.0, 0.55, 0.25)),
    'i': ((300, 2200, 2900), (1.0, 0.45, 0.25)),
}


def voice(pitch, seconds, vowel='a', vol=1.0, rough=0.0, breath=0.0, vib=0.02, a=0.02, r=0.08, formant_shift=1.0):
    """a cartoon voice: a buzzing tone (its pitch: a number or [(0..1, hz)])
    shaped into a vowel. `rough`: a growl; `breath`: air in it"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = contour(pitch, n) if isinstance(pitch, (list, tuple)) else np.full(n, float(pitch))
    f = f * (1 + vib * np.sin(2 * np.pi * 5.5 * t))
    if rough:
        f = f * (1 + rough * 0.15 * np.sin(2 * np.pi * 31 * t) + rough * 0.05 * noise(n))
    ph = np.cumsum(f) / RATE
    src = 0.6 * (2 * (ph % 1.0) - 1) + 0.4 * square(ph, 0.3)
    if rough:
        src *= 1 + rough * 0.6 * np.sin(2 * np.pi * 27 * t)
    out = np.zeros(n)
    freqs, gains = VOWELS[vowel]
    for fr, g in zip(freqs, gains):
        fr *= formant_shift
        out += shape(src, lo=fr * 0.8, hi=fr * 1.25)[:n] * g
    if breath:
        out += shape(noise(n), lo=500, hi=3500)[:n] * breath
    return out * adsr(n, a, 0.2, 0.85, r) * vol


def syllables(pitches, gap, length, vowel='a', vol=1.0, h=0.3, **kw):
    """a run of voice syllables ("ha ha ha"): each starts with a breathy h"""
    out = buf(len(pitches) * gap + length + 0.1)
    for i, p in enumerate(pitches):
        place(out, voice(p, length, vowel, vol, breath=0.1, **kw), i * gap)
        if h:
            hn = n_of(0.05)
            place(out, shape(noise(hn), lo=800, hi=4000)[:hn] * env(hn, 0.005, 0.05, 1.5) * h * vol, i * gap - 0.02 if i * gap > 0.02 else 0)
    return out


def thud(f0=110, f1=40, seconds=0.35, vol=1.0, click=0.4):
    n = n_of(seconds)
    body = sine(sweep(f0, f1, seconds)) * env(n, 0.002, seconds, 2.2)
    knock = shape(noise(n), hi=1200)[:n] * env(n, 0.001, 0.04, 3) * click
    return np.tanh(2.2 * (body + knock)) * vol


def crack(seconds=0.12, vol=1.0, lo=1500, hi=9000):
    n = n_of(seconds)
    return shape(noise(n), lo=lo, hi=hi)[:n] * env(n, 0.001, seconds, 4) * vol


def rumble(seconds, vol=1.0, hi=250, wobble=5):
    n = n_of(seconds)
    t = np.arange(n) / RATE
    x = shape(noise(n), hi=hi)[:n] * (0.6 + 0.4 * np.sin(2 * np.pi * wobble * t + np.sin(t * 3)))
    return x / (np.max(np.abs(x)) + 1e-9) * env(n, seconds * 0.15, seconds, 1.2) * vol


def wood(freq=420, seconds=0.18, vol=1.0):
    """a wooden knock"""
    return mix(A.ping(freq, seconds, ((1, 1.0), (2.3, 0.45), (3.9, 0.2)), vol), crack(0.02, vol * 0.4, 800, 5000))


def metal(freq=900, seconds=1.2, vol=1.0):
    """something metal ringing"""
    return A.ping(freq, seconds, ((1, 1.0), (2.76, 0.6), (5.4, 0.35), (8.9, 0.15)), vol)


def slide_whistle(f0, f1, seconds, vol=1.0):
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = contour([(0, f0), (1, f1)], n) * (1 + 0.02 * np.sin(2 * np.pi * 6 * t))
    return sine(np.cumsum(f) / RATE) * adsr(n, 0.03, 0.3, 0.9, 0.1) * vol


def blip(freq, seconds=0.06, duty=0.25, vol=1.0):
    return A.pulse_note(freq, seconds, duty, a=0.002, d=seconds / 2, s=0.5, r=0.01) * vol


def finish(x, hi=9000, room=0.0, drive=1.3):
    """soft top end, a little room, a gentle limit - and the deep part given
    some growl (overtones) so a phone's small speaker still plays the hit"""
    n = len(x)
    x = shape(x, lo=45, hi=hi)[:n]  # (nothing below 45 Hz: nobody hears it)
    low = shape(x, hi=180)[:n]
    m = np.max(np.abs(low)) + 1e-9
    x = x + 0.8 * (np.tanh(3.5 * low / m) * m - low)
    x = x + 0.35 * shape(np.tanh(3.5 * low / m) * m, lo=180, hi=1500)[:n]
    x = x - 0.55 * shape(x, hi=120)[:n]  # (and the deepest part turned down, so the rest carries)
    if room:
        x = reverb(x, 0.8, room)
    return trim(soft_limit(x, drive))


# ----------------------------------------------------------------------
# FLOOR 7: KONGO, the jungle gorilla
# ----------------------------------------------------------------------
def kongo_roar():
    x = mix(voice([(0, 95), (0.2, 120), (0.7, 110), (1, 80)], 1.5, 'a', 1.0, rough=1.0, breath=0.3),
            voice([(0, 190), (0.2, 240), (1, 160)], 1.5, 'o', 0.35, rough=0.8), rumble(1.5, 0.5))
    return finish(x, 6000, 0.15, 1.6)


def kongo_chest_pound():
    out = buf(1.1)
    for i in range(6):
        place(out, thud(130 if i % 2 else 115, 70, 0.22, 0.9, 1.2), i * 0.14)
        place(out, A.ping(260 if i % 2 else 230, 0.18, ((1, 1.0), (1.6, 0.4)), 0.5), i * 0.14)  # (the hollow chest)
    return finish(out, 3000)


def kongo_wind_up():
    x = mix(W.whoosh(0.9, 200, 1800, 1.0, 1.0), voice([(0, 90), (1, 150)], 0.9, 'u', 0.6, rough=0.6))
    return finish(x, 5000)


def kongo_giant_punch():
    out = buf(1.4)
    place(out, W.whoosh(0.2, 400, 4000, 1.0, 2.0), 0)
    place(out, A.boom(120, 30, 1.1, 1.0), 0.16)
    place(out, crack(0.25, 0.9, 400, 6000), 0.16)
    place(out, rumble(1.0, 0.4), 0.2)
    return finish(out, 7000, 0.1, 1.8)


def kongo_slap():
    return finish(mix(crack(0.08, 1.2, 1000, 8000), thud(160, 60, 0.3, 0.8)), 8000)


def kongo_roll():
    n = n_of(1.3)
    t = np.arange(n) / RATE
    x = rumble(1.3, 1.0, 180, 7) + shape(noise(n), lo=150, hi=900)[:n] * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t) ** 2) * 0.4
    return finish(x * env(n, 0.1, 1.3, 1.0), 2500)


def kongo_spin():
    x = W.whoosh(1.3, 300, 3000, 1.4, 1.0)
    t = np.arange(len(x)) / RATE
    x = x * (0.45 + 0.55 * np.sin(2 * np.pi * 6 * t) ** 2)
    return finish(x, 6000)


def kongo_headbutt():
    return finish(mix(thud(180, 60, 0.35, 1.0), wood(260, 0.3, 0.7), at(A.ping(1400, 0.5, ((1, 1), (2.1, 0.3)), 0.25), 0.02)), 6000)


def kongo_grab():
    return finish(mix(W.whoosh(0.25, 400, 3500, 1.0), at(voice([(0, 130), (1, 100)], 0.3, 'u', 0.8, rough=0.8), 0.12), at(thud(140, 70, 0.2, 0.5), 0.2)), 6000)


def kongo_pant():
    out = buf(1.4)
    for i in range(3):
        n = n_of(0.3)
        place(out, shape(noise(n), lo=300, hi=2200)[:n] * env(n, 0.05, 0.3, 1.5) * 0.9 + voice(110, 0.3, 'a', 0.25, rough=0.5, a=0.05), i * 0.45)
    return finish(out, 5000)


def kongo_hoot():
    out = buf(1.0)
    place(out, voice([(0, 260), (1, 420)], 0.34, 'u', 1.0, vib=0.03), 0)
    place(out, voice([(0, 300), (1, 480)], 0.38, 'u', 1.0, vib=0.03), 0.42)
    return finish(out, 5000, 0.12)


def kongo_rage():
    out = buf(2.2)
    place(out, kongo_roar() * 0.9, 0)
    for i in range(6):
        place(out, thud(130 if i % 2 else 110, 65, 0.2, 0.7, 0.7), 1.2 + i * 0.13)
    return finish(out, 6000, 0.1, 1.6)


def kongo_death():
    out = buf(2.2)
    place(out, voice([(0, 140), (0.5, 110), (1, 60)], 1.6, 'o', 1.0, rough=0.7, breath=0.3), 0)
    place(out, thud(90, 30, 0.8, 1.0, 0.8), 1.5)
    place(out, rumble(0.7, 0.4), 1.5)
    return finish(out, 5000, 0.12, 1.5)


def barrel_throw():
    out = buf(0.8)
    place(out, W.whoosh(0.45, 300, 2500, 1.2), 0)
    for i in range(3):
        place(out, wood(300 + 40 * i, 0.12, 0.35), 0.05 + i * 0.07)
    return finish(out, 6000)


def barrel_break():
    out = buf(1.2)
    place(out, crack(0.2, 1.2, 600, 7000), 0)
    place(out, thud(150, 60, 0.3, 0.8), 0)
    r = np.random.default_rng(4)
    for i in range(10):
        place(out, wood(r.uniform(250, 700), r.uniform(0.08, 0.2), r.uniform(0.2, 0.6)), 0.03 + r.exponential(0.15))
    return finish(out, 7000, 0.1)


def tnt_boom():
    out = buf(2.0)
    place(out, A.boom(110, 25, 1.8, 1.0), 0)
    n = n_of(1.5)
    place(out, shape(noise(n), hi=4000)[:n] * env(n, 0.002, 1.5, 2.5) * 1.2, 0)
    r = np.random.default_rng(5)
    for i in range(18):
        place(out, crack(0.03, r.uniform(0.2, 0.5), 1500, 7000), 0.1 + r.exponential(0.35))
    return finish(out, 6000, 0.15, 1.8)


# ----------------------------------------------------------------------
# FLOOR 8: PETALINA, the flower
# ----------------------------------------------------------------------
def flytrap_chomp():
    return finish(mix(crack(0.04, 1.0, 1500, 7000), at(W.squelch(0.2, 400, 90, 0.9), 0.01), at(wood(500, 0.1, 0.4), 0.0)), 7000)


def flytrap_sprout():
    n = n_of(0.5)
    rustle = shape(noise(n), lo=2000, hi=7000)[:n] * env(n, 0.05, 0.5, 1.5) * 0.3
    return finish(mix(W.bloop(0.45, 180, 700, 14, 0.12, 0.9), rustle), 6000)


def petal_throw():
    flutter = W.whoosh(0.6, 600, 3500, 0.9)
    t = np.arange(len(flutter)) / RATE
    flutter = flutter * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t) ** 2)
    return finish(mix(flutter, A.sparkle(0.1, 4, 0.08, vol=0.12)), 5500)


def petalina_chomp():
    return finish(mix(crack(0.05, 1.0, 1200, 6000), W.squelch(0.35, 300, 60, 1.0), at(thud(120, 50, 0.3, 0.6), 0.02), at(W.squelch(0.15, 500, 150, 0.4), 0.15)), 6000)


def petalina_evil_laugh():
    x = syllables([(0, 420), (1, 380)] if False else [360, 340, 320, 300, 280], 0.2, 0.17, 'a', 1.0, vib=0.04, rough=0.2)
    return finish(x, 6000, 0.18)


def petalina_giggle():
    x = syllables([620, 660, 700, 740, 800], 0.1, 0.08, 'i', 0.9, h=0.4, vib=0.05)
    return finish(x, 7000, 0.12)


def petalina_hum():
    out = buf(1.9)
    for i, m in enumerate([72, 76, 79, 76, 81, 79]):
        place(out, voice(midi(m), 0.3, 'u', 0.8, vib=0.03, a=0.04, r=0.1), i * 0.28)
    return finish(out, 5000, 0.2)


def petalina_stretch():
    n = n_of(0.8)
    t = np.arange(n) / RATE
    f = contour([(0, 120), (1, 520)], n) * (1 + 0.1 * np.sin(2 * np.pi * 12 * t))
    x = (sine(np.cumsum(f) / RATE) + 0.3 * square(np.cumsum(f) / RATE, 0.5)) * adsr(n, 0.05, 0.3, 0.9, 0.1)
    return finish(mix(x * 0.8, W.whoosh(0.8, 300, 2000, 0.4)), 5000)


def petalina_wilt():
    x = mix(slide_whistle(900, 250, 1.3, 0.8), voice([(0, 330), (1, 180)], 1.3, 'o', 0.35, vib=0.05))
    return finish(x, 5000, 0.15)


def pollen_puff():
    n = n_of(0.6)
    puff = shape(noise(n), lo=300, hi=2500)[:n] * env(n, 0.01, 0.6, 2.5)
    return finish(mix(puff, A.sparkle(0.12, 5, 0.07, vol=0.1)), 7000, 0.1)


def root_burst():
    out = buf(1.2)
    place(out, rumble(0.5, 0.6), 0)
    place(out, crack(0.2, 1.0, 400, 5000), 0.35)
    place(out, thud(130, 45, 0.5, 1.0), 0.35)
    r = np.random.default_rng(7)
    for i in range(8):
        place(out, crack(0.03, r.uniform(0.2, 0.4), 800, 4000), 0.4 + r.exponential(0.2))
    return finish(out, 6000)


def seed_land():
    return finish(mix(wood(700, 0.06, 0.6), thud(200, 90, 0.1, 0.4, 0.3)), 7000)


def seed_rain():
    out = buf(1.5)
    r = np.random.default_rng(8)
    for i in range(24):
        place(out, wood(r.uniform(500, 900), 0.05, r.uniform(0.2, 0.6)), r.uniform(0, 1.3))
    return finish(out, 7000)


def seed_spit():
    return finish(mix(crack(0.03, 0.8, 800, 4000), W.bloop(0.12, 400, 900, 20, 0.05, 0.6), at(W.whoosh(0.2, 600, 4000, 0.7), 0.04)), 7000)


def thorn_ring():
    n = n_of(0.9)
    scrape = shape(noise(n), lo=2500, hi=8000)[:n] * env(n, 0.01, 0.4, 2) * 0.6
    return finish(mix(scrape, W.ring(1600, 0.9, 0.35), W.whoosh(0.5, 500, 3000, 0.6)), 8000, 0.15)


def thorns_spread():
    out = buf(1.5)
    r = np.random.default_rng(9)
    for i in range(20):
        tt = i * 0.06 + r.uniform(0, 0.03)
        place(out, crack(0.04, 0.3 + 0.03 * i, 1500, 7000), tt)
        place(out, wood(r.uniform(300, 600), 0.06, 0.2), tt)
    place(out, rumble(1.3, 0.3), 0)
    return finish(out, 7000)


def vine_burst():
    out = buf(0.9)
    place(out, crack(0.05, 1.2, 1500, 9000), 0)  # (the whip)
    place(out, W.whoosh(0.25, 800, 5000, 0.8), 0)
    n = n_of(0.6)
    place(out, shape(noise(n), lo=1500, hi=6000)[:n] * env(n, 0.02, 0.6, 1.5) * 0.3, 0.05)
    place(out, thud(140, 60, 0.3, 0.7), 0.02)
    return finish(out, 8000)


# ----------------------------------------------------------------------
# FLOOR 9: SCRIBBLE, the drawing that got into the computer
# ----------------------------------------------------------------------
def bar_whip():
    return finish(mix(W.whoosh(0.18, 800, 5000, 0.8), at(crack(0.05, 1.3, 2000, 9000), 0.15), at(blip(midi(84), 0.05, 0.5, 0.3), 0.15)), 8000)


def clone_swipe():
    out = buf(0.9)
    sw = W.whoosh(0.25, 600, 4500, 1.0)
    for i in range(3):
        place(out, S.crush(sw, 8 - i * 2) * (0.9 - 0.25 * i), i * 0.12)
    return finish(out, 8000)


def copy_paste():
    return finish(mix(blip(midi(84), 0.05, 0.25, 0.8), at(blip(midi(91), 0.05, 0.25, 0.8), 0.07), at(blip(midi(79), 0.06, 0.5, 0.8), 0.25), at(thud(300, 120, 0.1, 0.4), 0.25)), 7000)


def delete_warning():
    out = buf(1.2)
    for i in range(4):
        place(out, blip(880 if i % 2 == 0 else 660, 0.2, 0.5, 0.8), i * 0.26)
    return finish(out, 5000)


def eraser_rub():
    n = n_of(0.9)
    t = np.arange(n) / RATE
    x = shape(noise(n), lo=400, hi=3000)[:n] * (0.3 + 0.7 * np.abs(np.sin(2 * np.pi * 4 * t))) * env(n, 0.03, 0.9, 1.0)
    return finish(x, 5000)


def error_pop():
    return finish(mix(blip(midi(76), 0.12, 0.5, 0.8), at(blip(midi(69), 0.25, 0.5, 0.8), 0.12), thud(200, 90, 0.15, 0.4)), 5000)


def ink_dash():
    return finish(mix(W.whoosh(0.3, 500, 4000, 1.1), at(W.squelch(0.2, 300, 80, 0.8), 0.18)), 7000)


def ink_skid():
    n = n_of(0.6)
    t = np.arange(n) / RATE
    f = contour([(0, 1400), (1, 900)], n) * (1 + 0.03 * np.sin(2 * np.pi * 40 * t))
    squeak = square(np.cumsum(f) / RATE, 0.4) * env(n, 0.02, 0.6, 1.2) * 0.3
    return finish(mix(shape(squeak, hi=3000)[:n], W.squelch(0.3, 250, 70, 0.5)), 5000)


def key_pop():
    return finish(mix(crack(0.015, 0.9, 2000, 8000), wood(1100, 0.05, 0.5)), 8000)


def lag_glitch():
    out = buf(0.9)
    tone = blip(midi(76), 0.08, 0.5, 1.0)
    for i, tt in enumerate([0, 0.08, 0.16, 0.2, 0.24, 0.26, 0.28, 0.42, 0.5, 0.55]):
        place(out, S.crush(tone[:n_of(0.04 + 0.02 * (i % 3))], 4 + i % 3), tt)
    n = n_of(0.9)
    place(out, S.crush(noise(n) * env(n, 0.01, 0.9, 2), 3) * 0.2, 0)
    return finish(out, 6000)


def mouse_click():
    return finish(mix(crack(0.01, 1.0, 2500, 9000), at(crack(0.01, 0.6, 2000, 8000), 0.06), wood(1600, 0.03, 0.3)), 9000)


def paint_splash():
    return finish(mix(W.squelch(0.35, 350, 60, 1.0), at(W.squelch(0.2, 600, 150, 0.5), 0.05), crack(0.06, 0.5, 1500, 5000)), 7000)


def paper_crumple():
    out = buf(0.9)
    r = np.random.default_rng(10)
    for i in range(30):
        place(out, crack(r.uniform(0.01, 0.04), r.uniform(0.2, 0.8), 900, 5000), r.uniform(0, 0.75))
    return finish(out, 5500)


def pencil_scratch():
    n = n_of(0.8)
    t = np.arange(n) / RATE
    strokes = (np.sin(2 * np.pi * 7 * t) > -0.2).astype(float)
    x = shape(noise(n), lo=1200, hi=5000)[:n] * shape(strokes, hi=40)[:n] * (1 + 0.3 * noise(n))
    return finish(x * env(n, 0.02, 0.8, 1), 5500)


def scribble_crash():
    out = buf(1.3)
    place(out, thud(150, 40, 0.6, 1.0), 0)
    place(out, crack(0.2, 0.8, 500, 6000), 0)
    place(out, lag_glitch() * 0.6, 0.05)
    n = n_of(0.8)
    place(out, S.crush(noise(n), 3) * env(n, 0.01, 0.8, 2) * 0.25, 0.1)
    return finish(out, 7000)


def scribble_dizzy():
    out = buf(1.6)
    for i in range(8):  # little birds tweeting round his head
        f = [1800, 2100, 1900, 2300][i % 4]
        place(out, A.pulse_note(f, 0.07, 0.5, a=0.003, d=0.03, s=0.5, r=0.02) * 0.3, i * 0.18)
    place(out, voice([(0, 300), (0.5, 220), (1, 280)], 1.4, 'o', 0.4, vib=0.08), 0.05)
    return finish(out, 5000, 0.1)


def scribble_glitch():
    out = buf(0.7)
    r = np.random.default_rng(11)
    for i in range(14):
        place(out, blip(r.choice([220, 440, 880, 1320, 330]), r.uniform(0.02, 0.06), r.choice([0.125, 0.5]), r.uniform(0.3, 0.8)), r.uniform(0, 0.6))
    n = n_of(0.7)
    place(out, S.crush(noise(n) * env(n, 0.005, 0.7, 2), 2) * 0.25, 0)
    return finish(out, 6000)


def scribble_laugh():
    x = syllables([300, 330, 310, 340, 320, 350], 0.13, 0.1, 'e', 0.9, h=0.3, vib=0.05)
    return finish(S.crush(x / (np.max(np.abs(x)) + 1e-9), 10), 6000, 0.08)


def scribble_rip():
    n = n_of(0.6)
    t = np.arange(n) / RATE
    tear = shape(noise(n), lo=500, hi=4500)[:n] * (0.5 + 0.5 * (np.random.default_rng(12).random(n) > 0.6)) * contour([(0, 0.3), (0.8, 1), (1, 0)], n)
    return finish(tear, 7000)


def undo_rewind():
    n = n_of(0.7)
    t = np.arange(n) / RATE
    f = contour([(0, 1600), (1, 200)], n) * (1 + 0.3 * np.sign(np.sin(2 * np.pi * 30 * t)))
    x = square(np.cumsum(f) / RATE, 0.5) * env(n, 0.02, 0.7, 1.2) * 0.4
    return finish(mix(shape(x, hi=3000)[:n], W.whoosh(0.7, 300, 2500, 0.4)), 5000)


# ----------------------------------------------------------------------
# FLOOR 10: KING GAVELGRUNT, the walrus king
# ----------------------------------------------------------------------
def belly_bounce():
    n = n_of(0.7)
    t = np.arange(n) / RATE
    f = 90 * (1 + 0.4 * np.sin(2 * np.pi * 8 * t) * np.exp(-4 * t))
    boing = np.tanh(2 * sine(np.cumsum(f) / RATE)) * env(n, 0.005, 0.7, 1.8)
    boing2 = np.tanh(2 * sine(np.cumsum(f * 2.5) / RATE)) * env(n, 0.005, 0.5, 2.2) * 0.45
    return finish(mix(boing, boing2, thud(120, 60, 0.25, 0.6)), 3000)


def big_inhale():
    n = n_of(1.5)
    k = np.arange(n) / n
    x = A.sweep_lp(noise(n), 400 + 3000 * k) * (k ** 1.5) * 0.9
    return finish(mix(x, voice([(0, 90), (1, 130)], 1.5, 'o', 0.15, breath=0.3)), 5000)


def chain_rattle():
    out = buf(1.0)
    r = np.random.default_rng(13)
    for i in range(14):
        place(out, metal(r.uniform(1200, 2600), 0.15, r.uniform(0.2, 0.5)), r.uniform(0, 0.8))
    return finish(out, 8000)


def choke_cough():
    out = buf(1.4)
    for i in range(3):
        n = n_of(0.22)
        place(out, shape(noise(n), lo=300, hi=2500)[:n] * env(n, 0.005, 0.22, 2.5) + voice(130, 0.22, 'a', 0.5, rough=0.8, a=0.005), i * 0.35)
    return finish(out, 5000)


def coin_pickup():
    return finish(mix(A.coin(2800, 0.8, 21), at(blip(midi(88), 0.12, 0.5, 0.3), 0.03), at(blip(midi(95), 0.18, 0.5, 0.3), 0.1)), 7000)


def coin_rain():
    return finish(A.coin_shower(2.0, rate=30, seed=22, vol=1.0), 8000, 0.1)


def coin_vacuum():
    out = buf(1.4)
    n = n_of(1.2)
    k = np.arange(n) / n
    place(out, A.sweep_lp(noise(n), 300 + 4000 * k) * k ** 1.2 * 0.8, 0)
    place(out, A.coin_shower(1.0, rate=25, seed=23, vol=0.6)[::-1][:n_of(1.0)], 0.2)
    return finish(out, 7000)


def crown_clang():
    return finish(mix(metal(740, 1.4, 1.0), metal(1110, 1.0, 0.5), crack(0.03, 0.6, 2000, 8000)), 8000, 0.15)


def earthquake():
    out = buf(2.6)
    place(out, rumble(2.6, 1.0, 160, 3), 0)
    r = np.random.default_rng(14)
    for i in range(10):
        place(out, crack(0.05, r.uniform(0.2, 0.4), 500, 3000), r.uniform(0.2, 2.2))
    return finish(out, 3500)


def gavel_hit(size=1.0):
    out = buf(1.2 + size)
    place(out, wood(300 / size, 0.4, 1.0), 0)
    place(out, thud(160 / size, 40 / size ** 0.5, 0.5 + 0.3 * size, 1.0, 0.8), 0)
    place(out, crack(0.08, 0.7, 700, 6000), 0)
    return out


def final_gavel():
    out = buf(3.0)
    place(out, W.whoosh(0.35, 200, 2500, 1.2), 0)
    place(out, gavel_hit(2.0), 0.3)
    place(out, A.boom(90, 25, 2.0, 1.0), 0.3)
    place(out, thunder_crack() * 0.8, 0.35)
    return finish(out, 6000, 0.2, 1.8)


def gavel_guilty():
    out = buf(1.6)
    place(out, gavel_hit(1.0), 0)
    place(out, gavel_hit(1.0) * 0.8, 0.28)
    return finish(out, 6000, 0.25)


def gavel_smash():
    return finish(mix(gavel_hit(1.3), at(rumble(0.7, 0.4), 0.05)), 6000, 0.12, 1.6)


def gavel_swing():
    return finish(mix(W.whoosh(0.45, 150, 1800, 1.5), voice([(0, 80), (1, 100)], 0.45, 'u', 0.2, rough=0.5)), 5000)


def gavel_transform():
    out = buf(1.6)
    n = n_of(1.0)
    k = np.arange(n) / n
    place(out, A.sweep_lp(noise(n), 500 + 6000 * k) * k ** 2 * 0.6, 0)
    place(out, A.sparkle(0.1, 10, 0.08, vol=0.12), 0)
    place(out, metal(520, 1.0, 1.0), 1.0)
    place(out, thud(120, 50, 0.4, 0.8), 1.0)
    return finish(out, 7000, 0.15)


def gavelgrunt_laugh():
    x = syllables([130, 120, 112, 105], 0.28, 0.24, 'o', 1.0, h=0.4, rough=0.5, vib=0.03)
    return finish(x, 5000, 0.15, 1.5)


def giant_gavel():
    return finish(mix(gavel_hit(1.8), A.boom(80, 25, 1.6, 0.9), at(rumble(1.2, 0.5), 0.05)), 6000, 0.15, 1.8)


def giant_land():
    return finish(mix(A.boom(90, 25, 1.4, 1.0), crack(0.2, 0.7, 300, 4000), at(rumble(1.1, 0.5), 0.05)), 5000, 0.1, 1.8)


def giant_stomp():
    return finish(mix(thud(110, 30, 0.7, 1.0, 0.8), crack(0.1, 0.5, 300, 3000), at(rumble(0.6, 0.3), 0.03)), 4000, 0.08, 1.7)


def giant_trip():
    out = buf(2.0)
    place(out, voice([(0, 150), (1, 260)], 0.3, 'o', 0.7, rough=0.3), 0)
    place(out, slide_whistle(1200, 300, 0.7, 0.6), 0.25)
    place(out, giant_land(), 0.9)
    return finish(out, 6000)


def guard_jab():
    return finish(mix(W.whoosh(0.12, 1000, 6000, 1.0, 2.0), at(metal(1800, 0.25, 0.4), 0.1)), 8000)


def gulp():
    return finish(mix(W.bloop(0.25, 420, 150, 10, 0.05, 1.0), at(thud(160, 80, 0.1, 0.4), 0.18)), 4000)


def hammer_spin():
    x = W.whoosh(1.4, 200, 2400, 1.5, 1.0)
    t = np.arange(len(x)) / RATE
    return finish(x * (0.4 + 0.6 * np.sin(2 * np.pi * 4 * t) ** 2), 5000)


def king_fall():
    out = buf(2.2)
    place(out, slide_whistle(1400, 200, 1.1, 0.7), 0)
    place(out, W.whoosh(1.1, 200, 1500, 0.6), 0)
    place(out, A.boom(80, 22, 1.2, 1.0), 1.05)
    place(out, rumble(1.0, 0.5), 1.1)
    return finish(out, 5000, 0.1, 1.7)


def king_roar():
    x = mix(voice([(0, 70), (0.25, 90), (0.8, 85), (1, 60)], 1.7, 'o', 1.0, rough=1.0, breath=0.3),
            voice([(0, 140), (0.3, 180), (1, 120)], 1.7, 'a', 0.3, rough=0.8), rumble(1.7, 0.5))
    return finish(x, 5000, 0.15, 1.6)


def munching():
    out = buf(1.4)
    for i in range(6):
        place(out, mix(W.squelch(0.12, 280, 90, 0.7), crack(0.02, 0.3, 800, 3000)), i * 0.2 + (0.03 if i % 2 else 0))
    return finish(out, 5000)


def pillar_crumble():
    out = buf(1.8)
    place(out, crack(0.3, 1.0, 300, 4000), 0)
    place(out, thud(90, 35, 0.6, 0.8), 0)
    r = np.random.default_rng(15)
    for i in range(16):
        tt = r.exponential(0.4)
        place(out, thud(r.uniform(150, 300), 60, 0.15, r.uniform(0.2, 0.5), 0.8), tt)
        place(out, crack(0.04, r.uniform(0.1, 0.3), 500, 3500), tt)
    return finish(out, 5000, 0.1)


def piston_hiss():
    n = n_of(0.8)
    hiss = shape(noise(n), lo=3000, hi=9000)[:n] * env(n, 0.01, 0.8, 1.5) * 0.7
    return finish(mix(metal(300, 0.4, 0.6), thud(140, 70, 0.2, 0.6), at(hiss, 0.05)), 8000)


def rocket_hammer():
    n = n_of(1.4)
    t = np.arange(n) / RATE
    roar = shape(noise(n), hi=2500)[:n] * (0.8 + 0.2 * np.sin(2 * np.pi * 30 * t)) * adsr(n, 0.15, 0.3, 0.8, 0.3)
    return finish(mix(crack(0.06, 0.8, 500, 5000), roar, W.whoosh(1.4, 300, 3000, 0.6)), 5000)


def royal_burp():
    n = n_of(0.9)
    t = np.arange(n) / RATE
    f = contour([(0, 95), (0.5, 80), (1, 70)], n) * (1 + 0.25 * np.sin(2 * np.pi * 23 * t))
    x = voice([(0, 95), (1, 70)], 0.9, 'o', 1.0, rough=1.2, breath=0.2, a=0.01)
    x += np.tanh(2 * sine(np.cumsum(f) / RATE)) * adsr(n, 0.01, 0.3, 0.8, 0.1) * 0.4
    return finish(x, 3500)


def royal_feast():
    out = buf(1.6)
    place(out, A.bell(midi(84), 0.9, 0.5), 0)
    for i, m in enumerate([72, 76, 79, 84]):
        place(out, A.brass(midi(m), 0.16 if i < 3 else 0.6, 0.35), 0.15 + i * 0.13)
    return finish(shape(out, hi=4000)[:len(out)], 5000, 0.15)


def royal_roll():
    n = n_of(1.5)
    t = np.arange(n) / RATE
    x = rumble(1.5, 1.0, 160, 4) + shape(noise(n), lo=100, hi=600)[:n] * (0.5 + 0.5 * np.sin(2 * np.pi * 5 * t) ** 2) * 0.5
    return finish(x * env(n, 0.1, 1.5, 1.0), 2500)


def royal_trumpet():
    x = A.fanfare([(0.0, 0.12, [67, 64]), (0.14, 0.12, [67, 64]), (0.28, 0.12, [67, 64]), (0.42, 0.8, [72, 67, 64])], 1.0)
    return finish(x, 5000, 0.2)


def spit_out():
    return finish(mix(crack(0.04, 0.8, 600, 4000), voice([(0, 200), (1, 120)], 0.15, 'u', 0.6, breath=0.5), at(W.whoosh(0.3, 400, 3000, 0.8), 0.05), at(W.squelch(0.2, 300, 80, 0.6), 0.3)), 6000)


def throne_crash():
    out = buf(1.8)
    place(out, A.boom(100, 30, 1.2, 0.9), 0)
    place(out, crack(0.25, 1.0, 400, 6000), 0)
    r = np.random.default_rng(16)
    for i in range(8):
        place(out, wood(r.uniform(200, 500), 0.15, r.uniform(0.3, 0.6)), r.exponential(0.2))
    for i in range(4):
        place(out, metal(r.uniform(600, 1200), 0.6, 0.3), r.exponential(0.25))
    return finish(out, 6000, 0.12, 1.7)


def thunder_crack():
    out = buf(2.8)
    place(out, crack(0.12, 1.4, 800, 9000), 0)
    place(out, crack(0.3, 0.8, 300, 5000), 0.02)
    place(out, rumble(2.6, 0.9, 200, 2), 0.1)
    place(out, A.boom(70, 25, 1.5, 0.6), 0.05)
    return finish(out, 6000, 0.2, 1.7)


def toe_ouch():
    return finish(mix(thud(200, 80, 0.2, 0.8), wood(400, 0.1, 0.5), at(voice([(0, 180), (0.3, 420), (1, 350)], 0.5, 'o', 0.9, vib=0.05), 0.12)), 6000)


# ("Pillar Crumble" isn't here: Kaze's floor already has it, and one sound
# serves both; pillar_crumble() is kept in case it's ever wanted)
BOSSES = {
    'Kongo': {
        'Kongo Roar': kongo_roar, 'Kongo Chest Pound': kongo_chest_pound, 'Kongo Wind Up': kongo_wind_up,
        'Kongo Giant Punch': kongo_giant_punch, 'Kongo Slap': kongo_slap, 'Kongo Roll': kongo_roll,
        'Kongo Spin': kongo_spin, 'Kongo Headbutt': kongo_headbutt, 'Kongo Grab': kongo_grab,
        'Kongo Pant': kongo_pant, 'Kongo Hoot': kongo_hoot, 'Kongo Rage': kongo_rage, 'Kongo Death': kongo_death,
        'Barrel Throw': barrel_throw, 'Barrel Break': barrel_break, 'TNT Boom': tnt_boom,
    },
    'Petalina': {
        'Flytrap Chomp': flytrap_chomp, 'Flytrap Sprout': flytrap_sprout, 'Petal Throw': petal_throw,
        'Petalina Chomp': petalina_chomp, 'Petalina Evil Laugh': petalina_evil_laugh, 'Petalina Giggle': petalina_giggle,
        'Petalina Hum': petalina_hum, 'Petalina Stretch': petalina_stretch, 'Petalina Wilt': petalina_wilt,
        'Pollen Puff': pollen_puff, 'Root Burst': root_burst, 'Seed Land': seed_land, 'Seed Rain': seed_rain,
        'Seed Spit': seed_spit, 'Thorn Ring': thorn_ring, 'Thorns Spread': thorns_spread, 'Vine Burst': vine_burst,
    },
    'Scribble': {
        'Bar Whip': bar_whip, 'Clone Swipe': clone_swipe, 'Copy Paste': copy_paste, 'Delete Warning': delete_warning,
        'Eraser Rub': eraser_rub, 'Error Pop': error_pop, 'Ink Dash': ink_dash, 'Ink Skid': ink_skid, 'Key Pop': key_pop,
        'Lag Glitch': lag_glitch, 'Mouse Click': mouse_click, 'Paint Splash': paint_splash, 'Paper Crumple': paper_crumple,
        'Pencil Scratch': pencil_scratch, 'Scribble Crash': scribble_crash, 'Scribble Dizzy': scribble_dizzy,
        'Scribble Glitch': scribble_glitch, 'Scribble Laugh': scribble_laugh, 'Scribble Rip': scribble_rip,
        'Undo Rewind': undo_rewind,
    },
    'Gavelgrunt': {
        'Belly Bounce': belly_bounce, 'Big Inhale': big_inhale, 'Chain Rattle': chain_rattle, 'Choke Cough': choke_cough,
        'Coin Pickup': coin_pickup, 'Coin Rain': coin_rain, 'Coin Vacuum': coin_vacuum, 'Crown Clang': crown_clang,
        'Earthquake': earthquake, 'Final Gavel': final_gavel, 'Gavel Guilty': gavel_guilty, 'Gavel Smash': gavel_smash,
        'Gavel Swing': gavel_swing, 'Gavel Transform': gavel_transform, 'Gavelgrunt Laugh': gavelgrunt_laugh,
        'Giant Gavel': giant_gavel, 'Giant Land': giant_land, 'Giant Stomp': giant_stomp, 'Giant Trip': giant_trip,
        'Guard Jab': guard_jab, 'Gulp': gulp, 'Hammer Spin': hammer_spin, 'King Fall': king_fall, 'King Roar': king_roar,
        'Munching': munching, 'Piston Hiss': piston_hiss, 'Rocket Hammer': rocket_hammer,
        'Royal Burp': royal_burp, 'Royal Feast': royal_feast, 'Royal Roll': royal_roll, 'Royal Trumpet': royal_trumpet,
        'Spit Out': spit_out, 'Throne Crash': throne_crash, 'Thunder Crack': thunder_crack, 'Toe Ouch': toe_ouch,
    },
}


def seed(name):
    """the same sound every run, whichever ones are made"""
    global rng
    s = zlib.crc32(name.encode())
    rng = np.random.default_rng(s)
    A.rng = np.random.default_rng(s + 1)
    S.rng = np.random.default_rng(s + 2)


def demo(made):
    """all of them, one after another with a gap, as Docs/boss_sounds.mp3"""
    import wave
    parts = []
    for boss, names in made:
        parts.append(np.zeros(n_of(1.2)))
        for name in names:
            with wave.open(os.path.join(OUT, name.replace(' ', '_') + '.wav')) as w:
                x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32767
            parts.append(x * 0.8)
            parts.append(np.zeros(n_of(0.45)))
    x = np.concatenate(parts)
    tmp = os.path.join(HERE, 'out', 'boss_demo.wav')
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    import imageio_ffmpeg
    mp3 = os.path.join(HERE, '..', '..', 'Docs', 'boss_sounds.mp3')
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libmp3lame', '-b:a', '96k', mp3], check=True)
    print('saved Docs/boss_sounds.mp3 (%.0f s)' % (len(x) / RATE))


if __name__ == '__main__':
    S.OUT = OUT
    os.makedirs(OUT, exist_ok=True)
    args = sys.argv[1:]
    want = [a for a in args if not a.startswith('--')]
    made = []
    for boss, sounds in BOSSES.items():
        names = []
        for name, fn in sounds.items():
            if not want or any(name.startswith(w) or boss.startswith(w) for w in want):
                seed(name)
                S.save(name, fn())
                names.append(name)
        made.append((boss, names))
    if '--demo' in args:
        demo(made)
