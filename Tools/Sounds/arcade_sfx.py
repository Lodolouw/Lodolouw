"""THE ARCADE's music and sounds, made from code like the rest (8-bit squares
and triangles for the music; real-sounding glass, bells and coins for the
jackpots, so they jump out):

  * Arcade Theme       its own song: a bright 8-bit loop (32 bars, 136 bpm,
                       C major) that plays in the Arcade. The game speeds it
                       up while the strip spins, like a slot machine's.
  * Spin Riser         the build-up under a spin: a drum roll that gets faster
                       and a sweep that climbs, ending as everything drops out
  * Heartbeat          what you hear in the silence when it's landing on a
                       Legendary or better: four beats, faster and louder
  * Token Clunk        a token dropping into the machine
  * Roll Tick          each tile going past (soft, a peg clicking)
  * Win Common / Win Rare / Win Epic      the landings, bigger each time
  * Jackpot Legendary  GLASS SMASHING, a brass fanfare, an alarm bell ringing
                       and a shower of coins
  * Jackpot Mythic     a bigger smash and a boom, a casino siren wailing, a
                       heavier fanfare, bells and more coins
  * Jackpot Secret     a swell that sucks everything in (it starts 0.6 s early,
                       so it hits right on the landing), then TWO panes
                       shattering, a bass drop, a choir chord, cascading bells
                       and a rain of coins

    python3 arcade_sfx.py            -> out/arcade/<Name>.ogg (and .wav)
    python3 arcade_sfx.py Jackpot    ...only the ones starting with "Jackpot"

Tools/Upload/upload_assets.bat uploads out/arcade/*.ogg with everything else;
ServerScriptService/SoundLoader puts each in SoundService under its name
("Jackpot_Secret" -> "Jackpot Secret"), which is what ArcadeClient plays.
(The song is saved without the little silences the others get at each end,
so it loops without a gap.)
"""
import os
import subprocess
import sys
import wave
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_sfx as S  # noqa: E402
from make_sfx import RATE, env, sweep, square, tri, mix, at  # noqa: E402

OUT = os.path.join(HERE, 'out', 'arcade')
rng = np.random.default_rng(21)


# ----------------------------------------------------------------------
# building blocks (on top of make_sfx's)
# ----------------------------------------------------------------------
def n_of(seconds):
    return int(round(seconds * RATE))


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def noise(n):
    return rng.uniform(-1, 1, n)


def sine(phase):
    return np.sin(2 * np.pi * phase)


def phase_of(freq, n):
    f = np.broadcast_to(np.asarray(freq, float), (n,))
    return np.cumsum(f) / RATE


def shape(x, hi=None, lo=None, order=2, loop=False):
    """a smooth low-pass (above `hi` fades out) and/or high-pass (below `lo`),
    done in one go with an FFT. A loop is filtered round its seam; anything
    else gets room for its tail first."""
    n = len(x)
    pad = 0 if loop else n_of(0.25)
    y = np.concatenate([x, np.zeros(pad)])
    f = np.fft.rfftfreq(len(y), 1 / RATE)
    h = np.ones_like(f)
    if hi:
        h /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        h /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    y = np.fft.irfft(np.fft.rfft(y) * h, len(y))
    return y if not loop else y[:n]


def sweep_lp(x, cutoff):
    """a low-pass whose cutoff moves (an array, one per sample): made by
    blending a few fixed ones, which is quick and smooth enough"""
    cutoff = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    bank = np.geomspace(max(100, cutoff.min()), min(16000, cutoff.max()) + 1, 7)
    versions = [shape(x, hi=c)[:len(x)] for c in bank]
    pos = np.interp(np.log(cutoff), np.log(bank), np.arange(len(bank)))
    lo_i = np.clip(np.floor(pos).astype(int), 0, len(bank) - 2)
    w = pos - lo_i
    out = np.zeros_like(x)
    for i in range(len(bank) - 1):
        here = lo_i == i
        out[here] = versions[i][here] * (1 - w[here]) + versions[i + 1][here] * w[here]
    return out


def adsr(n, a=0.005, d=0.08, s=0.7, r=0.03):
    """attack, a fall to `s`, and a short release at the very end (no clicks)"""
    t = np.arange(n) / RATE
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    return e * np.clip((n / RATE - t) / max(r, 1e-4), 0, 1)


def place(buf, x, seconds, loop=False):
    """adds x into buf at `seconds` (round the end and back to the start, for a loop)"""
    i = n_of(seconds)
    if loop:
        i %= len(buf)
        k = min(len(x), len(buf) - i)
        buf[i:i + k] += x[:k]
        rest = x[k:]
        while len(rest):
            m = min(len(rest), len(buf))
            buf[:m] += rest[:m]
            rest = rest[m:]
        return
    if i >= len(buf):
        return
    k = min(len(x), len(buf) - i)
    buf[i:i + k] += x[:k]


def reverb(x, seconds=1.2, wet=0.2, loop=False, dark=5000):
    """a room: the sound, plus a soft decaying wash of itself"""
    n_ir = n_of(seconds)
    t = np.arange(n_ir) / RATE
    ir = np.random.default_rng(5).uniform(-1, 1, n_ir) * np.exp(-t * 6.9 / seconds)
    ir[:n_of(0.012)] = 0  # (a moment before the walls answer)
    ir = shape(ir, hi=dark)[:n_ir]
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    if loop:
        k = np.zeros(len(x))
        k[:min(n_ir, len(x))] = ir[:len(x)]
        tail = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(k), len(x))
        return x * (1 - wet * 0.5) + tail * wet
    m = len(x) + n_ir
    tail = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)
    return np.concatenate([x, np.zeros(n_ir)]) * (1 - wet * 0.5) + tail * wet


def soft_limit(x, drive=1.6):
    x = x / (np.max(np.abs(x)) + 1e-9)
    return np.tanh(x * drive) / np.tanh(drive)


def trim(x, floor=0.0015):
    """cuts off the silent end (after a short fade)"""
    loud = np.nonzero(np.abs(x) > floor * np.max(np.abs(x)))[0]
    end = min(len(x), (loud[-1] if len(loud) else len(x)) + n_of(0.05))
    x = x[:end].copy()
    f = min(len(x), n_of(0.04))
    x[-f:] *= np.linspace(1, 0, f)
    return x


# ----------------------------------------------------------------------
# instruments
# ----------------------------------------------------------------------
def pulse_note(freq, seconds, duty=0.25, vib=0.0, a=0.005, d=0.1, s=0.7, r=0.03):
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = np.full(n, float(freq))
    if vib:
        f *= 1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.14) / 0.12, 0, 1)
    return square(phase_of(f, n), duty) * adsr(n, a, d, s, r)


def nes_tri(freq, seconds, r=0.02):
    """the NES triangle: a triangle in 16 steps (buzzy, warm)"""
    n = n_of(seconds)
    return np.round(tri(phase_of(freq, n)) * 7.5) / 7.5 * adsr(n, 0.003, 0.2, 0.85, r)


def kick(vol=1.0):
    s = 0.16
    n = n_of(s)
    body = sine(sweep(170, 45, s)) * env(n, 0.001, s, 2.4)
    click = shape(noise(n_of(0.006)), hi=3000)[:n_of(0.006)] * 0.5
    return mix(body, click) * vol


def snare(vol=1.0, s=0.13):
    n = n_of(s)
    rattle = shape(noise(n), lo=1500, hi=9000)[:n] * env(n, 0.001, s, 3)
    tone = tri(sweep(220, 150, s)) * env(n, 0.001, 0.06, 3) * 0.5
    return S.crush(mix(rattle, tone), 10) * vol


def hat(vol=1.0, s=0.03):
    n = n_of(s)
    return shape(noise(n), lo=6000, hi=12000)[:n] * env(n, 0.001, s, 3) * vol


def crash(vol=1.0, s=1.2):
    n = n_of(s)
    return shape(noise(n), lo=3000, hi=11000)[:n] * env(n, 0.002, s, 2.2) * vol


def brass(freq, seconds, vol=1.0):
    """an 8-bit brass note: two pulses a hair apart, a scoop up into it and a
    vibrato on the long ones"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = freq * 2 ** ((-0.7 * np.exp(-t / 0.035)) / 12)
    f = f * (1 + 0.007 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.2) / 0.25, 0, 1))
    ph = np.cumsum(f) / RATE
    x = 0.6 * square(ph, 0.5) + 0.4 * square(ph * 1.004, 0.25)
    return x * adsr(n, 0.012, 0.18, 0.78, 0.06) * vol


def timpani(freq, seconds=0.7, vol=1.0):
    n = n_of(seconds)
    body = sine(sweep(freq * 1.06, freq, seconds)) * env(n, 0.002, seconds, 2.0)
    body += 0.35 * sine(sweep(freq * 2.12, freq * 2, seconds)) * env(n, 0.002, seconds * 0.5, 2.5)
    head = shape(noise(n), hi=1500)[:n] * env(n, 0.001, 0.05, 3) * 0.5
    return np.tanh(1.6 * (body + head)) * vol


def boom(f0=100, f1=32, seconds=0.9, vol=1.0):
    """a deep hit (a little driven, so small speakers still feel it)"""
    n = n_of(seconds)
    x = sine(sweep(f0, f1, seconds)) * env(n, 0.002, seconds, 1.8)
    return np.tanh(2.2 * x) * vol


def ping(freq, seconds, partials=((1, 1.0), (2.41, 0.5), (3.93, 0.25)), vol=1.0, seed=0):
    """a small hard thing ringing (glass, metal): a few out-of-tune overtones"""
    r = np.random.default_rng(seed)
    n = n_of(seconds)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for k, (p, a) in enumerate(partials):
        if freq * p < 17000:
            x += a * np.sin(2 * np.pi * freq * p * t + r.uniform(0, 6.28)) * np.exp(-t / (seconds / (2.5 + 1.5 * k)))
    return x * vol


def bell(freq, seconds, vol=1.0):
    """a proper bell: a strike and a long shimmering ring"""
    return ping(freq, seconds, ((0.5, 0.35), (1, 1.0), (1.19, 0.4), (1.5, 0.3), (2.0, 0.45), (2.52, 0.2), (3.0, 0.15)), vol)


# ----------------------------------------------------------------------
# the casino pieces
# ----------------------------------------------------------------------
def glass_smash(size=1.0, tune=(0, 4, 7), seed=1):
    """GLASS SMASHING: the hit, the burst of breaking, then hundreds of shards
    ringing - most at once, then fewer as they fall and bounce. Half the
    shards ring in tune (the notes of the chord that follows), so the smash
    flows straight into the music."""
    r = np.random.default_rng(seed)
    s = 1.8 * size
    n = n_of(s)
    out = np.zeros(n)
    # the hit: a sharp crack and a thud
    m = n_of(0.05)
    crack = r.uniform(-1, 1, m) * np.exp(-np.arange(m) / RATE / 0.005)
    place(out, crack * 1.4, 0)
    place(out, sine(sweep(130 / size, 48, 0.18)) * env(n_of(0.18), 0.001, 0.18, 3) * 0.9, 0)
    # the burst of breaking: bright rushing noise, falling away
    m = n_of(0.7 * size)
    burst = shape(r.uniform(-1, 1, m), lo=1600, hi=11000)[:m] * np.exp(-np.arange(m) / RATE / (0.09 * size))
    place(out, burst * 0.9, 0.002)
    # the crunch: a grainy crackle as the pane falls apart
    m = n_of(0.45 * size)
    grains = (r.random(m) > 0.992) * r.uniform(-1, 1, m) * np.exp(-np.arange(m) / RATE / (0.12 * size))
    place(out, shape(grains, lo=1200, hi=9000)[:m] * 3.0, 0.01)
    # the shards
    for i in range(int(190 * size)):
        early = r.random() < 0.78
        when = r.exponential(0.1 * size) if early else r.uniform(0.18, 1.3 * size)
        if tune and r.random() < 0.5:
            f = midi(84 + r.choice(tune) + 12 * r.integers(0, 2))  # (the chord's notes, 1 to 4 kHz)
        else:
            f = r.uniform(2300, 8500)
        dur = r.uniform(0.04, 0.22 if early else 0.12)
        amp = r.uniform(0.2, 1.0) * (0.55 if early else 0.3)
        place(out, ping(f, dur, vol=amp, seed=int(r.integers(1 << 30))), when)
    return shape(out, hi=12000)[:n]


def coin(freq, vol=1.0, seed=None):
    """one coin landing: a clink with a quick bright ring"""
    r = np.random.default_rng(seed)
    dur = r.uniform(0.07, 0.16)
    x = ping(freq, dur, ((1, 1.0), (2.76, 0.6), (5.4, 0.25)), 1.0, seed)
    tick = r.uniform(-1, 1, n_of(0.003)) * 0.4
    return mix(tick, x) * vol


def coin_shower(seconds, rate=30, seed=3, vol=1.0):
    """a jackpot pouring out: coins landing (some bouncing once), thickest at
    the start, and the tray's rattle under them"""
    r = np.random.default_rng(seed)
    out = np.zeros(n_of(seconds + 0.3))
    t = 0.0
    while t < seconds:
        k = t / seconds
        f = r.uniform(1900, 4300)
        v = r.uniform(0.35, 1.0) * (1 - 0.6 * k)
        place(out, coin(f, v, int(r.integers(1 << 30))), t)
        if r.random() < 0.45:  # (a bounce)
            place(out, coin(f * r.uniform(0.97, 1.03), v * 0.45, int(r.integers(1 << 30))), t + r.uniform(0.04, 0.09))
        t += r.exponential(1.0 / (rate * (1 - 0.7 * k) + 1))
    m = len(out)
    rattle = shape(r.uniform(-1, 1, m), lo=2500, hi=7000)[:m]
    flutter = 0.5 + 0.5 * np.sin(2 * np.pi * 23 * np.arange(m) / RATE) ** 2
    rattle *= flutter * np.clip(1 - np.arange(m) / RATE / seconds, 0, 1) * 0.06
    return (out + rattle) * vol


def alarm_bell(seconds, freq=1170, rate=17, vol=1.0):
    """the casino's jackpot bell: a hammer hitting a bell 17 times a second"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    strike = np.exp(-((t * rate) % 1.0) / rate / 0.016)
    tone = np.zeros(n)
    for p, a in ((1, 1.0), (2.0, 0.45), (2.76, 0.3), (5.4, 0.1)):
        if freq * p < 16000:
            tone += a * np.sin(2 * np.pi * freq * p * t)
    return tone * (0.3 + 0.7 * strike) * env(n, 0.01, seconds, 1.1) * vol


def payout_dings(seconds, notes=(83, 88), rate=11, vol=1.0):
    """the 8-bit "ding ding ding ding" of a machine paying out"""
    out = np.zeros(n_of(seconds + 0.2))
    step = 1.0 / rate
    k, t = 0, 0.0
    while t < seconds:
        f = midi(notes[k % len(notes)])
        d = pulse_note(f, step * 0.9, 0.5, a=0.002, d=0.03, s=0.35, r=0.01) * 0.6 + \
            np.round(tri(phase_of(f, n_of(step * 0.9))) * 7.5) / 7.5 * adsr(n_of(step * 0.9), 0.002, 0.05, 0.4, 0.01) * 0.6
        place(out, d * (1 - 0.5 * t / seconds), t)
        k += 1
        t += step
    return shape(out, hi=5000)[:len(out)] * vol


def siren(seconds, lo=520, hi=1250, cycles=2.5, vol=1.0):
    """a jackpot siren wailing up and down"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    f = lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * cycles * t / seconds))
    ph = np.cumsum(f) / RATE
    x = 0.55 * square(ph, 0.5) + 0.45 * tri(ph)
    return shape(x, hi=3200)[:n] * env(n, 0.06, seconds, 0.9) * vol


def reel_stop(vol=1.0):
    """the strip clacking to a stop"""
    n = n_of(0.07)
    clack = shape(noise(n), lo=800, hi=6000)[:n] * env(n, 0.001, 0.03, 3)
    thunk = tri(sweep(320, 140, 0.07)) * env(n, 0.001, 0.07, 3) * 0.6
    return mix(clack, thunk) * vol


def fanfare(notes, vol=1.0, tempo=1.0):
    """notes: (start, length, [midi...]) played on the 8-bit brass"""
    end = max(s + d for s, d, _ in notes) * tempo + 0.3
    out = np.zeros(n_of(end))
    for s, d, chord in notes:
        for j, m in enumerate(chord):
            place(out, brass(midi(m), d * tempo, (1.0 if j == 0 else 0.6) / len(chord) ** 0.5), s * tempo)
    return shape(out, hi=3800)[:len(out)] * vol


def choir(chord, seconds, vol=1.0):
    """a big soft chord: stacked, slightly out-of-tune voices swelling in"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for m in chord:
        for det in (-0.006, 0.0, 0.007):
            f = midi(m) * (1 + det) * (1 + 0.004 * np.sin(2 * np.pi * (5 + det * 300) * t))
            ph = np.cumsum(f) / RATE
            out += 0.5 * (2 * (ph % 1.0) - 1) + 0.5 * square(ph, 0.5)
    e = np.clip(t / 0.35, 0, 1) ** 1.5 * np.clip((seconds - t) / 1.2, 0, 1)
    return shape(out, hi=2600)[:n] * e / len(chord) * vol


def reverse_swell(seconds=0.6, vol=1.0):
    """a cymbal played backwards: everything sucked in, then cut"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    k = t / seconds
    wash = sweep_lp(noise(n), 800 + 11000 * k ** 2) * k ** 3
    suck = sine(sweep(90, 900, seconds)) * k ** 2.5 * 0.5
    x = mix(wash, suck)
    x[-n_of(0.006):] *= np.linspace(1, 0, n_of(0.006))
    return x * vol


def sparkle(start, count, gap=0.06, notes=(96, 100, 103, 108), vol=0.2, seed=9):
    """tiny high glints"""
    r = np.random.default_rng(seed)
    parts = []
    for i in range(count):
        parts.append(at(ping(midi(r.choice(notes)), 0.18, ((1, 1.0), (2.0, 0.3)), vol * r.uniform(0.5, 1.0)), start + i * gap))
    return mix(*parts)


# ----------------------------------------------------------------------
# the sounds
# ----------------------------------------------------------------------
BPM = 136
SIX = 60 / BPM / 4  # a sixteenth note
BAR = 16 * SIX

SECTION_A = ['C', 'Am', 'F', 'G', 'C', 'Am', 'F', 'G']
SECTION_B = ['F', 'G', 'Em', 'Am', 'F', 'G', 'C', 'G7']
ROOT = {'C': 48, 'Am': 45, 'F': 41, 'G': 43, 'Em': 40, 'G7': 43}
TONES = {'C': [60, 64, 67, 72], 'Am': [57, 60, 64, 69], 'F': [53, 57, 60, 65], 'G': [55, 59, 62, 67],
         'Em': [52, 55, 59, 64], 'G7': [55, 59, 62, 65]}
# the tune: (note, sixteenths) per bar; None is a rest
MELODY_A = [
    [(67, 2), (72, 2), (76, 2), (79, 4), (76, 2), (79, 2), (81, 2)],
    [(79, 4), (76, 2), (72, 2), (69, 4), (72, 4)],
    [(69, 2), (72, 2), (77, 2), (81, 4), (79, 2), (77, 2), (76, 2)],
    [(74, 4), (79, 4), (77, 2), (76, 2), (74, 4)],
    [(67, 2), (72, 2), (76, 2), (79, 4), (76, 2), (79, 2), (84, 2)],
    [(83, 2), (81, 2), (76, 4), (81, 2), (83, 2), (84, 4)],
    [(81, 4), (77, 2), (81, 2), (84, 4), (81, 4)],
    [(83, 3), (81, 1), (79, 4), (74, 4), (None, 4)],
]
MELODY_B = [
    [(84, 2), (84, 2), (81, 2), (84, 4), (81, 2), (77, 4)],
    [(86, 2), (86, 2), (83, 2), (86, 4), (83, 2), (79, 4)],
    [(88, 2), (86, 2), (83, 2), (79, 4), (83, 2), (76, 4)],
    [(84, 2), (83, 2), (81, 2), (76, 4), (81, 2), (84, 4)],
    [(81, 2), (84, 2), (81, 2), (77, 2), (81, 2), (84, 2), (86, 4)],
    [(83, 2), (86, 2), (83, 2), (79, 2), (81, 2), (83, 2), (86, 4)],
    [(88, 4), (84, 4), (79, 4), (76, 4)],
    [(77, 2), (76, 2), (74, 2), (71, 2), (74, 2), (77, 2), (79, 4)],
]
SCALE = [0, 2, 4, 5, 7, 9, 11]


def third_below(m):
    pc, octave = m % 12, m // 12
    i = SCALE.index(pc) if pc in SCALE else 0
    j = i - 2
    return SCALE[j % 7] + 12 * (octave + (j // 7))


def arcade_theme():
    """32 bars: A B, then A B again with more going on (an echo on the tune,
    a harmony, busier drums and a higher arpeggio). Rendered round in a circle,
    so the notes ringing past the end carry on at the start: no seam."""
    sections = [('A', SECTION_A, MELODY_A, 1), ('B', SECTION_B, MELODY_B, 1),
                ('A', SECTION_A, MELODY_A, 2), ('B', SECTION_B, MELODY_B, 2)]
    total = n_of(32 * BAR)
    lead, arp, bass, drums, hats = (np.zeros(total) for _ in range(5))
    bar_no = 0
    for name, chords, melody, rnd in sections:
        for b, chord in enumerate(chords):
            t0 = bar_no * BAR
            # the tune
            pos = 0
            for m, six in melody[b]:
                if m is not None:
                    d = six * SIX * 0.92
                    note = pulse_note(midi(m), d, 0.25, vib=0.005 if six >= 4 else 0.0, a=0.004, d=0.1, s=0.72, r=0.03)
                    place(lead, note * 0.22, t0 + pos * SIX, loop=True)
                    if rnd == 2:
                        place(lead, note * 0.22 * 0.3, t0 + (pos + 3) * SIX, loop=True)  # (the echo)
                        if name == 'B':
                            h = pulse_note(midi(third_below(m)), d, 0.5, a=0.004, d=0.1, s=0.7, r=0.03)
                            place(lead, h * 0.085, t0 + pos * SIX, loop=True)
                pos += six
            # the arpeggio (16ths through the chord)
            tones = TONES[chord]
            order = [0, 1, 2, 3] * 4 if rnd == 1 else [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3]
            for i, k in enumerate(order):
                m = tones[k] + (12 if rnd == 2 else 0)
                place(arp, pulse_note(midi(m), SIX * 0.9, 0.125, a=0.002, d=0.05, s=0.3, r=0.01) * 0.065, t0 + i * SIX, loop=True)
            # the bass: bouncing octaves (walking up to C on the last bar)
            root = ROOT[chord]
            walk = [43, 55, 47, 59, 50, 62, 53, 65] if chord == 'G7' else [root, root + 12] * 4
            for i, m in enumerate(walk):
                place(bass, nes_tri(midi(m), 2 * SIX * 0.85) * 0.42, t0 + i * 2 * SIX, loop=True)
            # the drums: a kick on every beat, a snare on 2 and 4, open hats on
            # the off-beats (and 16th hats and fills the second time round)
            for step in (0, 4, 8, 12):
                place(drums, kick(0.45), t0 + step * SIX, loop=True)
            for step in (4, 12):
                place(drums, snare(0.24), t0 + step * SIX, loop=True)
            for step in (2, 6, 10, 14):
                place(hats, hat(0.085, 0.07), t0 + step * SIX, loop=True)
            if rnd == 2:
                for step in range(1, 16, 2):
                    place(hats, hat(0.045), t0 + step * SIX, loop=True)
                if b == 7:
                    for j, step in enumerate((13, 14, 15)):
                        place(drums, snare(0.14 + 0.05 * j, 0.09), t0 + step * SIX, loop=True)
            if b == 0:
                place(hats, crash(0.12 if rnd == 1 else 0.16), t0, loop=True)
            bar_no += 1
    lead = shape(lead, hi=6000, loop=True)
    arp = shape(arp, hi=4800, loop=True)
    bass = shape(bass, hi=2400, loop=True)
    hats = shape(hats, hi=10000, loop=True)
    x = lead + arp + bass + drums + hats
    x = reverb(x, 0.9, 0.14, loop=True)
    return soft_limit(x, 1.3) * 0.8


def spin_riser():
    """3.3 s: a snare roll getting faster and louder, a note climbing and a
    whoosh opening up; it stops dead (the silence before the landing)"""
    s = 3.3
    n = n_of(s)
    t = np.arange(n) / RATE
    k = t / s
    out = np.zeros(n)
    tt, gap = 0.0, 0.2
    while tt < s - 0.03:
        u = tt / s
        place(out, snare(0.3 + 0.55 * u ** 1.6, 0.07), tt)
        gap = max(0.03, gap * 0.9)
        tt += gap
    f = 150 * (1500 / 150) ** (k ** 1.3)
    ph = np.cumsum(f) / RATE
    climb = shape(0.6 * square(ph, 0.5) + 0.4 * tri(ph), hi=2800)[:n] * (0.08 + 0.2 * k ** 1.5)
    whoosh = sweep_lp(noise(n), 300 + 5000 * k ** 2) * 0.35 * k ** 2
    # kicks on the beat underneath, speeding up with the song
    for j, bt in enumerate(np.cumsum([0] + [0.44 * 0.93 ** i for i in range(12)])):
        if bt < s - 0.1:
            place(out, kick(0.35 + 0.03 * j), bt)
    x = shape(out + climb + whoosh, hi=8000)[:n]
    x[-n_of(0.008):] *= np.linspace(1, 0, n_of(0.008))
    return x


def heartbeat():
    """1.6 s: lub-dub four times, closer together and louder; the landing
    comes right after the last one"""
    beats = [(0.00, 0.55), (0.52, 0.7), (0.96, 0.85), (1.32, 1.0)]
    out = np.zeros(n_of(1.6))

    def thump(f0, f1, s, v):
        n = n_of(s)
        body = sine(sweep(f0, f1, s)) * env(n, 0.004, s, 2.2)
        knock = sine(sweep(f0 * 3, f1 * 2.5, s)) * env(n, 0.002, s * 0.35, 3) * 0.6
        chest = sine(sweep(260, 190, s)) * env(n, 0.002, 0.06, 2.5) * 0.9
        thud = shape(noise(n), lo=180, hi=900)[:n] * env(n, 0.002, 0.045, 3) * 1.2
        # (driven, so it has overtones a phone's speaker can play)
        return np.tanh(3.0 * (body + knock + chest + thud)) * v
    for t0, v in beats:
        place(out, thump(85, 45, 0.17, v), t0)
        place(out, thump(100, 52, 0.14, v * 0.72), t0 + 0.125)
    return shape(out, hi=2200)[:len(out)]


def token_clunk():
    """a token going in: it clinks on the slot, rattles down inside (muffled),
    the machine chunks, and a bright credit blip"""
    out = np.zeros(n_of(0.75))
    place(out, coin(3100, 0.8, 11), 0)
    for i, f in enumerate([2600, 2300, 2050, 1900]):
        place(out, shape(coin(f, 0.5 - 0.08 * i, 20 + i), hi=2500)[:n_of(0.2)], 0.07 + i * 0.05)
    n = n_of(0.12)
    chunk = mix(tri(sweep(190, 80, 0.12)) * env(n, 0.001, 0.12, 3), shape(noise(n), hi=1500)[:n] * env(n, 0.001, 0.05, 3) * 0.6)
    place(out, chunk * 0.9, 0.3)
    place(out, pulse_note(midi(83), 0.07, 0.5, a=0.002, d=0.04, s=0.5, r=0.01) * 0.3, 0.42)
    place(out, pulse_note(midi(88), 0.22, 0.5, a=0.002, d=0.08, s=0.4, r=0.05) * 0.3, 0.49)
    return shape(out, hi=7000)[:len(out)]


def roll_tick():
    """a peg clicking past: short, soft, woody"""
    n = n_of(0.035)
    click = shape(noise(n), lo=1500, hi=6000)[:n] * env(n, 0.0005, 0.012, 3)
    knock = tri(phase_of(1250, n)) * env(n, 0.001, 0.03, 3) * 0.45
    return mix(click, knock)


def win_common():
    """a clack and a friendly two-note plink"""
    out = np.zeros(n_of(0.6))
    place(out, reel_stop(0.8), 0)
    place(out, pulse_note(midi(79), 0.1, 0.5, a=0.003, d=0.05, s=0.5, r=0.02) * 0.3, 0.03)
    place(out, pulse_note(midi(84), 0.3, 0.5, a=0.003, d=0.1, s=0.4, r=0.1) * 0.3, 0.12)
    return shape(out, hi=4500)[:len(out)]


def win_rare():
    """a clack, a quick climb to a held note, a coin and a glint"""
    out = np.zeros(n_of(1.0))
    place(out, reel_stop(0.8), 0)
    for i, m in enumerate([72, 76, 79]):
        place(out, pulse_note(midi(m), 0.08, 0.25, a=0.003, d=0.05, s=0.6, r=0.02) * 0.28, 0.03 + i * 0.07)
    place(out, pulse_note(midi(84), 0.5, 0.25, vib=0.006, a=0.003, d=0.15, s=0.55, r=0.15) * 0.3, 0.24)
    place(out, pulse_note(midi(76), 0.5, 0.5, a=0.003, d=0.15, s=0.5, r=0.15) * 0.12, 0.24)
    place(out, coin(3000, 0.35, 4), 0.26)
    place(out, sparkle(0.35, 3, 0.07, vol=0.1), 0)
    return reverb(shape(out, hi=5500)[:len(out)], 0.8, 0.15)


def win_epic():
    """a whoosh up, a fast climb two octaves high, a chord stab that shimmers,
    and a handful of coins"""
    out = np.zeros(n_of(1.9))
    place(out, reel_stop(0.9), 0)
    n = n_of(0.3)
    place(out, sweep_lp(noise(n), np.linspace(500, 6000, n)) * env(n, 0.2, 0.3, 1) * 0.3, 0)
    for i, m in enumerate([72, 76, 79, 84, 88, 91]):
        place(out, pulse_note(midi(m), 0.07, 0.25, a=0.002, d=0.04, s=0.6, r=0.02) * 0.26, 0.04 + i * 0.05)
    for m, v in ((72, 0.2), (76, 0.16), (79, 0.16), (84, 0.2)):
        x = pulse_note(midi(m), 0.9, 0.5, vib=0.008, a=0.005, d=0.3, s=0.5, r=0.3)
        trem = 1 + 0.3 * np.sin(2 * np.pi * 9 * np.arange(len(x)) / RATE)
        place(out, x * trem * v, 0.36)
    place(out, timpani(midi(36), 0.6, 0.35), 0.36)
    place(out, coin_shower(0.8, rate=12, seed=7, vol=0.35), 0.38)
    place(out, sparkle(0.4, 6, 0.08, vol=0.12), 0)
    return reverb(shape(out, hi=6000)[:len(out)], 1.0, 0.18)


def jackpot_legendary():
    """GLASS SMASHES on the landing, a deep boom, then "ta-ta-ta-TAAA ... ta-ta
    TAAAA!" on the brass over an alarm bell ringing, the machine going ding-
    ding-ding and coins pouring out"""
    out = np.zeros(n_of(4.6))
    place(out, glass_smash(1.0, (0, 4, 7), seed=1) * 0.95, 0)
    place(out, boom(95, 34, 0.9, 0.8), 0)
    place(out, fanfare([
        (0.00, 0.11, [67, 64]), (0.12, 0.11, [67, 64]), (0.24, 0.11, [67, 64]), (0.36, 0.85, [72, 67, 64]),
        (1.30, 0.13, [74, 71]), (1.45, 0.13, [76, 72]), (1.60, 1.9, [79, 76, 72]),
    ], 0.62), 0.28)
    for tt, m in ((0.64, 36), (1.58, 43), (1.88, 36)):
        place(out, timpani(midi(m), 0.8, 0.45), tt)
    place(out, alarm_bell(2.6, 1170, 17, 0.1), 0.75)
    place(out, payout_dings(2.4, (83, 88), 11, 0.28), 0.7)
    place(out, coin_shower(2.8, rate=32, seed=3, vol=0.42), 0.45)
    place(out, sparkle(1.9, 10, 0.1, vol=0.1), 0)
    x = reverb(out, 1.4, 0.2)
    return trim(soft_limit(shape(x, hi=11000)[:len(x)], 1.5))


def jackpot_mythic():
    """a bigger, lower smash with a huge boom, a casino siren wailing, the
    heavier "Am - F - G - C" fanfare with drums on every chord, and bells and
    coins everywhere"""
    out = np.zeros(n_of(5.6))
    place(out, glass_smash(1.3, (9, 0, 4), seed=2) * 0.95, 0)
    place(out, boom(80, 28, 1.3, 1.0), 0)
    place(out, siren(2.4, 560, 1250, 2.5, 0.2), 0.12)
    place(out, fanfare([
        (0.00, 0.32, [69, 64, 60]), (0.36, 0.32, [69, 65, 60]), (0.72, 0.32, [71, 67, 62]), (1.08, 2.3, [72, 67, 64, 60]),
    ], 0.6), 0.32)
    place(out, fanfare([
        (0.00, 0.32, [81]), (0.36, 0.32, [81]), (0.72, 0.32, [83]), (1.08, 2.3, [84]),
    ], 0.3), 0.32)
    for tt, m in ((0.32, 33), (0.68, 29), (1.04, 31), (1.40, 36), (1.64, 36)):
        place(out, timpani(midi(m), 0.8, 0.5), tt)
    place(out, crash(0.35, 1.8), 1.4)
    place(out, alarm_bell(3.2, 1240, 18, 0.1), 1.4)
    place(out, payout_dings(3.0, (84, 88, 91), 13, 0.26), 1.45)
    place(out, coin_shower(3.8, rate=42, seed=5, vol=0.45), 0.4)
    place(out, sparkle(2.4, 14, 0.1, vol=0.1, seed=4), 0)
    x = reverb(out, 1.6, 0.22)
    return trim(soft_limit(shape(x, hi=11000)[:len(x)], 1.6))


SECRET_LEAD = 0.6  # (ArcadeClient starts it this long before the landing)


def jackpot_secret():
    """a backwards swell sucks everything in (0.6 s: it hits right on the
    landing), then TWO panes shatter, the bass drops, a huge choir chord
    swells, bells cascade down and up, the alarm bell, the payout dings and
    a long rain of coins, and a last shimmering chord"""
    L = SECRET_LEAD
    out = np.zeros(n_of(7.4))
    place(out, reverse_swell(L, 0.55), 0)
    place(out, glass_smash(1.5, (0, 4, 7, 11), seed=3) * 0.95, L)
    place(out, boom(110, 26, 1.8, 1.0), L)
    place(out, glass_smash(1.0, (7, 11, 2), seed=4) * 0.75, L + 0.24)
    place(out, choir([48, 60, 64, 67, 71, 74], 3.6, 0.7), L + 0.3)
    notes = [96, 91, 88, 84, 79, 76, 72, 76, 79, 84, 88, 91, 96]
    for i, m in enumerate(notes):
        place(out, bell(midi(m), 1.2, 0.2), L + 0.45 + i * 0.12)
    place(out, alarm_bell(3.4, 1170, 17, 0.09), L + 0.6)
    place(out, payout_dings(3.4, (84, 88, 91, 96), 14, 0.22), L + 1.9)
    place(out, coin_shower(4.8, rate=44, seed=6, vol=0.36), L + 0.4)
    place(out, fanfare([(0.0, 0.14, [79, 76]), (0.16, 0.14, [79, 76]), (0.32, 1.8, [84, 79, 76, 72])], 0.6), L + 3.0)
    n = n_of(2.6)
    shimmer = sum(pulse_note(midi(m), 2.6, 0.5, a=0.3, d=0.5, s=0.8, r=1.2) for m in (84, 88, 91, 96)) / 4
    shimmer *= 1 + 0.4 * np.sin(2 * np.pi * 10 * np.arange(n) / RATE)
    place(out, shape(shimmer, hi=5000)[:n] * 0.16, L + 3.4)
    place(out, sparkle(L + 0.5, 30, 0.13, vol=0.1, seed=8), 0)
    x = reverb(out, 1.8, 0.24)
    return trim(soft_limit(shape(x, hi=11000)[:len(x)], 1.6))


SOUNDS = {
    'Arcade Theme': arcade_theme,
    'Spin Riser': spin_riser,
    'Heartbeat': heartbeat,
    'Token Clunk': token_clunk,
    'Roll Tick': roll_tick,
    'Win Common': win_common,
    'Win Rare': win_rare,
    'Win Epic': win_epic,
    'Jackpot Legendary': jackpot_legendary,
    'Jackpot Mythic': jackpot_mythic,
    'Jackpot Secret': jackpot_secret,
}
LOOPS = {'Arcade Theme'}


def save_loop(name, x):
    """like make_sfx.save, but with no silence added at the ends (it loops)"""
    x = x / max(1e-6, np.max(np.abs(x))) * 0.85
    path = os.path.join(OUT, name.replace(' ', '_'))
    with wave.open(path + '.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    try:
        import imageio_ffmpeg
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', path + '.wav',
                        '-c:a', 'libvorbis', '-q:a', '5', path + '.ogg'], check=True)
    except Exception as e:  # (no ffmpeg: the .wav is still there)
        print('no .ogg for', name, e)
    print('saved', path)


if __name__ == '__main__':
    S.OUT = OUT
    os.makedirs(OUT, exist_ok=True)
    want = sys.argv[1:]
    for name, fn in SOUNDS.items():
        if not want or any(name.startswith(w) for w in want):
            rng = np.random.default_rng(zlib.crc32(name.encode()))  # (the same every run)
            (save_loop if name in LOOPS else S.save)(name, fn())
