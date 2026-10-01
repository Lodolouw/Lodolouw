"""GRIDLOCK'S SONG, made from code: an original chiptune for floor 6, "The
Final Beat" - 128 beats a minute, so it fits his fight beat for beat
(Config.Bosses[6].Bpm). Everything he does lands on a beat, and the song
starts the moment he wakes up (BossClient starts it where the level is),
so the tiles, his hops and the music all hit together.

It is exactly 64 bars long (120.000 s) and loops with no seam: notes and
echoes ringing past the end carry on at the start, so a long fight never
hears a join. In E minor, in stereo.

    bars  1-4   LEVEL START   the crash as "ATTEMPT 1" comes up, the beat in
    bars  5-20  A             the main tune (twice: the second time with an
                              echo and a harmony)
    bars 21-28  B             higher and brighter
    bars 29-32  BREAKDOWN     the drums drop out, a taste of the drop's tune,
                              then the build (a snare roll and a riser)
    bars 33-48  THE DROP      the heaviest part: pumping bass, chord stabs,
                              the hook in octaves
    bars 49-56  C             the soaring part over a fast counter-tune
    bars 57-64  TURNAROUND    the hook answers itself, then a build that
                              runs straight back into bar 1

Two versions: "Gridlock Theme" (round 1) and "Gridlock Theme Flip" (round 2,
after GRAVITY FLIP!): the same song, bar for bar, played harder - 16th hats
all the way, a higher, doubled arpeggio, rolling bass in the drop, extra
kicks and a sparkle on top. Both are the same length, so when round 2 starts
the game swaps one for the other at the same spot and the beat never slips.

    python3 music_gridlock.py           -> out/bosses/Gridlock_Theme.ogg and
                                           Gridlock_Theme_Flip.ogg (and .wav)
    python3 music_gridlock.py --demo    ...and Docs/music/gridlock_theme.mp3:
                                           round 1 once, then into round 2 at
                                           the drop (to listen to)

Tools/Upload/upload_assets.bat uploads out/bosses/*.ogg; SoundLoader puts
them in SoundService as "Gridlock Theme" and "Gridlock Theme Flip", which is
what his Config plays (Music, Round2Music).
"""
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import arcade_sfx as A  # noqa: E402
from make_sfx import RATE  # noqa: E402

OUT = os.path.join(HERE, 'out', 'bosses')
BPM = 128
BEAT = 60 / BPM
STEP = BEAT / 4  # a 16th
BAR = BEAT * 4
BARS = 64
N = int(round(BARS * BAR * RATE))  # 5,292,000 samples: exactly 120 s

# ----------------------------------------------------------------------
# the harmony: one chord a bar
# ----------------------------------------------------------------------
TONES = {  # (the arpeggio's notes)
    'Em': [64, 67, 71, 76], 'C': [60, 64, 67, 72], 'G': [62, 67, 71, 74],
    'D': [62, 66, 69, 74], 'B': [63, 66, 71, 75], 'Am': [60, 64, 69, 72],
}
BASS = {'Em': 40, 'C': 36, 'G': 43, 'D': 38, 'B': 35, 'Am': 45}
STAB = {  # (the drop's chord stabs, a little lower)
    'Em': [59, 64, 67, 71], 'C': [60, 64, 67, 72], 'G': [59, 62, 67, 71],
    'D': [57, 62, 66, 69], 'B': [59, 63, 66, 71], 'Am': [57, 60, 64, 69],
}

INTRO = ['Em', 'C', 'G', 'D']
A_CH = ['Em', 'C', 'G', 'D', 'Em', 'C', 'G', 'B']
B_CH = ['C', 'D', 'Em', 'Em', 'C', 'D', 'B', 'B']
BRK_CH = ['Em', 'C', 'D', 'B']
DROP_CH = ['Em', 'C', 'G', 'D', 'Em', 'C', 'D', 'B']
TURN_CH = ['Em', 'C', 'G', 'D', 'Em', 'C', 'D', 'B']

# the plan, bar by bar: (section, chord, bar within its section)
PLAN = ([('intro', c, i) for i, c in enumerate(INTRO)]
        + [('A', c, i) for i, c in enumerate(A_CH * 2)]
        + [('B', c, i) for i, c in enumerate(B_CH)]
        + [('brk', c, i) for i, c in enumerate(BRK_CH)]
        + [('drop', c, i) for i, c in enumerate(DROP_CH * 2)]
        + [('C', c, i) for i, c in enumerate(A_CH)]
        + [('turn', c, i) for i, c in enumerate(TURN_CH)])
assert len(PLAN) == BARS

# ----------------------------------------------------------------------
# the tunes: (midi note or None for a rest, length in 16ths), 16 a bar
# ----------------------------------------------------------------------
E4, Fs4, G4, A4, B4 = 64, 66, 67, 69, 71
C5, D5, Ds5, E5, Fs5, G5, A5, B5 = 72, 74, 75, 76, 78, 79, 81, 83
C6, D6, Ds6, E6 = 84, 86, 87, 88

MEL_A = [  # the main tune: that 3-3-2 push
    [(E5, 3), (B4, 3), (E5, 2), (Fs5, 2), (G5, 4), (Fs5, 2)],
    [(E5, 3), (C5, 3), (E5, 2), (G5, 4), (E5, 2), (D5, 2)],
    [(D5, 3), (B4, 3), (D5, 2), (G5, 2), (Fs5, 2), (G5, 2), (A5, 2)],
    [(Fs5, 6), (A5, 2), (D5, 4), (Fs5, 4)],
    [(E5, 3), (B4, 3), (E5, 2), (Fs5, 2), (G5, 4), (A5, 2)],
    [(B5, 3), (A5, 3), (G5, 2), (E5, 4), (G5, 2), (A5, 2)],
    [(B5, 4), (A5, 2), (G5, 2), (Fs5, 4), (D5, 4)],
    [(Ds5, 6), (Fs5, 2), (B5, 8)],
]
MEL_B = [  # higher and brighter
    [(G5, 4), (E5, 4), (G5, 4), (C6, 4)],
    [(A5, 4), (Fs5, 4), (A5, 4), (D6, 4)],
    [(B5, 6), (A5, 2), (G5, 4), (Fs5, 4)],
    [(E5, 8), (B4, 4), (E5, 4)],
    [(G5, 4), (E5, 4), (G5, 4), (C6, 4)],
    [(D6, 4), (C6, 4), (B5, 4), (A5, 4)],
    [(B5, 6), (A5, 2), (Fs5, 4), (Ds5, 4)],
    [(Fs5, 8), (B5, 8)],
]
MEL_DROP = [  # THE HOOK: chopped, in octaves
    [(E5, 2), (E5, 1), (G5, 1), (B5, 2), (A5, 2), (G5, 2), (E5, 2), (D5, 2), (E5, 2)],
    [(E5, 2), (E5, 1), (G5, 1), (C6, 2), (B5, 2), (G5, 2), (E5, 2), (G5, 2), (A5, 2)],
    [(B5, 2), (B5, 1), (A5, 1), (G5, 2), (D5, 2), (G5, 2), (B5, 2), (D6, 2), (B5, 2)],
    [(A5, 4), (Fs5, 2), (D5, 2), (Fs5, 2), (A5, 2), (D6, 4)],
    [(E5, 2), (E5, 1), (G5, 1), (B5, 2), (A5, 2), (G5, 2), (E5, 2), (D5, 2), (E5, 2)],
    [(E5, 2), (E5, 1), (G5, 1), (C6, 2), (B5, 2), (G5, 2), (E5, 2), (G5, 2), (A5, 2)],
    [(A5, 2), (A5, 1), (B5, 1), (A5, 2), (Fs5, 2), (D5, 2), (Fs5, 2), (A5, 2), (D6, 2)],
    [(Ds6, 4), (B5, 2), (Fs5, 2), (Ds5, 2), (Fs5, 2), (B5, 4)],
]
MEL_C = [  # soaring
    [(E5, 4), (G5, 4), (B5, 6), (A5, 2)],
    [(G5, 4), (E5, 4), (C6, 6), (B5, 2)],
    [(B5, 4), (G5, 4), (D6, 6), (C6, 2)],
    [(A5, 8), (Fs5, 4), (A5, 4)],
    [(B5, 4), (G5, 4), (E6, 6), (D6, 2)],
    [(C6, 4), (B5, 4), (G5, 4), (E5, 4)],
    [(D6, 4), (B5, 4), (G5, 4), (B5, 4)],
    [(Ds6, 8), (B5, 4), (Fs5, 4)],
]
MEL_TURN = [  # the hook calls, the tune answers
    MEL_DROP[0][:6] + [(None, 6)],
    [(None, 8), (G5, 2), (A5, 2), (B5, 4)],
    MEL_DROP[2][:6] + [(None, 6)],
    [(None, 8), (Fs5, 2), (A5, 2), (D6, 4)],
    MEL_DROP[0],
    MEL_DROP[1],
    [(A5, 4), (B5, 4), (D6, 4), (Fs5, 4)],
    [(B5, 12), (None, 4)],
]
INTRO_RUN = [(None, 8), (D5, 1), (E5, 1), (Fs5, 1), (A5, 1), (B5, 1), (D6, 1), (Ds6, 2)]

SCALE = [4, 6, 7, 9, 11, 0, 2]  # E natural minor (D# borrowed for the B chord)


def harmony(m, chord):
    """the highest note of the chord at least a third under the tune's note
    (so the harmony always sits in the chord)"""
    pcs = {t % 12 for t in STAB[chord]}
    for k in range(3, 13):
        if (m - k) % 12 in pcs:
            return m - k
    return m - 12


def third_below(m):
    pc, octv = m % 12, m // 12
    if pc == 3:  # D# -> B
        return m - 4
    i = SCALE.index(pc) if pc in SCALE else 0
    j = i - 2
    return m - ((pc - SCALE[j % 7]) % 12)


# ----------------------------------------------------------------------
# instruments (band-limited pulses: clean 8-bit, no fizz)
# ----------------------------------------------------------------------
def n_of(seconds):
    return int(round(seconds * RATE))


def _blep(t, dt):
    y = np.zeros_like(t)
    a = t < dt
    x = t[a] / dt[a]
    y[a] = x + x - x * x - 1
    b = t > 1 - dt
    x = (t[b] - 1) / dt[b]
    y[b] = x * x + x + x + 1
    return y


def pulse(freq, n, duty=0.5):
    f = np.broadcast_to(np.asarray(freq, float), (n,)).astype(float)
    dt = np.clip(f / RATE, 1e-6, 0.45)
    ph = np.cumsum(dt) % 1.0
    y = np.where(ph < duty, 1.0, -1.0)
    y += _blep(ph, dt)
    y -= _blep((ph - duty) % 1.0, dt)
    return y


def tri_steps(freq, n):
    """the NES triangle: 16 steps (warm and a little buzzy)"""
    ph = np.cumsum(np.full(n, freq / RATE)) % 1.0
    return np.round((4 * np.abs(ph - 0.5) - 1) * 7.5) / 7.5


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def lead(m, steps, duty=0.25, bright=1.0):
    n = n_of(steps * STEP * 0.94)
    t = np.arange(n) / RATE
    f = np.full(n, midi(m))
    if steps >= 4:  # a vibrato creeping into the long ones
        f *= 1 + 0.006 * np.sin(2 * np.pi * 5.8 * t) * np.clip((t - 0.16) / 0.14, 0, 1)
    f *= 2 ** ((-0.35 * np.exp(-t / 0.02)) / 12)  # (a tiny scoop up into each note)
    x = pulse(f, n, duty) + 0.3 * bright * pulse(f * 1.0035, n, 0.125)
    return x * A.adsr(n, 0.004, 0.14, 0.72, 0.03)


def arp_note(m, duty=0.125, length=0.85):
    n = n_of(STEP * length)
    return pulse(midi(m), n, duty) * A.adsr(n, 0.002, 0.05, 0.35, 0.012)


def bass_note(m, steps, punch=True):
    n = n_of(steps * STEP * 0.88)
    sub = tri_steps(midi(m), n)
    top = pulse(midi(m), n, 0.5) * 0.35
    e = A.adsr(n, 0.003, 0.12 if punch else 0.3, 0.75, 0.015)
    return (sub + top) * e


def pad(chord, seconds, attack=0.25):
    n = n_of(seconds)
    x = np.zeros(n)
    for m in chord:
        for d in (0.997, 1.003):
            x += pulse(midi(m) * d, n, 0.5)
    t = np.arange(n) / RATE
    e = np.clip(t / attack, 0, 1) * np.clip((seconds - t) / 0.15, 0, 1)
    return x * e / (2 * len(chord))


def stab(chord, spread):
    """a chord stab, one ear a hair sharp of the other"""
    n = n_of(STEP * 1.6)
    x = np.zeros(n)
    for m in chord:
        x += pulse(midi(m) * spread, n, 0.5)
    return x * A.adsr(n, 0.002, 0.08, 0.25, 0.03) / len(chord)


def heavy_kick(vol=1.0):
    k = A.kick(1.0)
    b = A.boom(120, 40, 0.28, 0.6)
    n = max(len(k), len(b))
    x = np.zeros(n)
    x[:len(k)] += k
    x[:len(b)] += b
    return np.tanh(1.3 * x) * vol


def clap(vol=1.0):
    """a snare with a clap's flams on it"""
    s = A.snare(1.0, 0.16)
    x = np.zeros(len(s) + n_of(0.03))
    for i, g in enumerate((0.5, 0.6, 1.0)):
        o = n_of(0.01 * i)
        x[o:o + len(s)] += s * g
    return x * vol / 1.6


def riser(seconds, vol=1.0):
    """noise opening up and a tone climbing: the build"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    u = t / seconds
    nz = A.sweep_lp(A.noise(n), 400 * (40 ** u)) * (u ** 1.5)
    tone = pulse(midi(52) * (2 ** (2 * u)), n, 0.25) * 0.25 * u ** 2
    x = (nz * 0.8 + tone) * vol
    f = n_of(0.012)  # (cut off clean, not with a click)
    x[-f:] *= np.linspace(1, 0, f)
    return x


# ----------------------------------------------------------------------
# the song
# ----------------------------------------------------------------------
class Song:
    def __init__(self):
        self.bus = {}

    def put(self, name, x, step):
        """add x into a bus at a 16th (round the end and back to the start)"""
        b = self.bus.get(name)
        if b is None:
            b = self.bus[name] = np.zeros(N)
        A.place(b, x, step * STEP, loop=True)


def sec_bar(bar):
    return bar * 16


def render(flip=False):
    S = Song()
    pump_beats = []  # beats the bass and chords duck under the kick (a pump)
    for bar, (sec, ch, i) in enumerate(PLAN):
        s0 = sec_bar(bar)
        tones = TONES[ch]
        root = BASS[ch]
        heavy = sec in ('drop', 'turn')
        second = (sec in ('A', 'drop')) and i >= 8  # the second time round

        # ---- drums ------------------------------------------------------
        if sec != 'brk':
            for beat in range(4):
                S.put('kick', heavy_kick(0.62) if heavy else A.kick(0.52), s0 + beat * 4)
                pump_beats.append(s0 + beat * 4)
            if flip and heavy:
                S.put('kick', A.kick(0.35), s0 + 14)  # (the and of 4)
            if not (sec == 'intro' and i == 0):
                for st in (4, 12):
                    S.put('snare', clap(0.42) if heavy else A.snare(0.34), s0 + st)
            if flip or heavy or second or sec == 'C':
                for st in range(16):
                    if st % 4 != 2:
                        S.put('hats', A.hat(0.05 if st % 2 else 0.035), s0 + st)
            for st in (2, 6, 10, 14):
                S.put('hats', A.hat(0.1, 0.07), s0 + st)
            if flip and sec in ('A', 'B', 'C'):
                S.put('snare', A.snare(0.09, 0.07), s0 + 7)  # (a ghost note)
        else:
            # the breakdown: hats only, then the build (a snare roll speeding up)
            for st in range(0, 16, 2):
                S.put('hats', A.hat(0.05, 0.05), s0 + st)
            if i == 2:
                for st in range(0, 16, 2):
                    S.put('snare', A.snare(0.07 + 0.01 * st, 0.08), s0 + st)
            if i == 3:
                for st in range(0, 8):
                    S.put('snare', A.snare(0.22 + 0.02 * st, 0.07), s0 + st)
                for k in range(12):  # 32nds
                    S.put('snare', A.snare(0.3 + 0.012 * k, 0.05), s0 + 8 + k * 0.5)
                S.put('fx', riser(BAR * 2 - STEP * 2, 0.32), s0 - 16)
        # the turnaround's build back into bar 1
        if sec == 'turn' and i == 7:
            for st in range(0, 8, 2):
                S.put('snare', A.snare(0.2, 0.07), s0 + st)
            for k in range(14):
                S.put('snare', A.snare(0.24 + 0.012 * k, 0.05), s0 + 8 + k * 0.5)
            S.put('fx', riser(BAR, 0.26), s0)
        if sec == 'intro' and i == 3:
            for k, st in enumerate((10, 12, 13, 14, 15)):
                S.put('snare', A.snare(0.22 + 0.04 * k, 0.07), s0 + st)
        # crashes where things begin
        if i in (0, 8) and sec in ('intro', 'A', 'B', 'drop', 'C', 'turn') or (sec == 'drop' and i % 4 == 0):
            S.put('cym', A.crash(0.2 if heavy or sec == 'intro' else 0.14, 1.6), s0)
        if (sec == 'intro' and i == 0) or (sec == 'drop' and i == 0):
            S.put('kick', A.boom(90, 30, 1.0, 0.5), s0)  # (the big one)

        # ---- bass ---------------------------------------------------------
        if sec == 'brk':
            S.put('bass', bass_note(root, 16 if i < 3 else 8, punch=False) * (0.45 + 0.1 * i), s0)
        elif heavy and flip:
            for st in range(16):  # rolling 16ths
                m = root + (12 if st % 2 else 0)
                S.put('bass', bass_note(m, 1) * 0.8, s0 + st)
        elif heavy:
            for st in range(0, 16, 2):
                m = root + (12 if st % 4 == 2 else 0)
                S.put('bass', bass_note(m, 2) * 0.9, s0 + st)
        else:
            for st in range(0, 16, 2):
                m = root + (12 if (st // 2) % 2 else 0)
                S.put('bass', bass_note(m, 2) * 0.85, s0 + st)

        # ---- arpeggio -------------------------------------------------------
        up = 12 if flip and sec in ('A', 'C', 'drop', 'turn') else 0
        if sec == 'brk':
            order = [0, 1, 2, 3, 2, 1, 2, 3] * 2
            lift = 12 * (i // 2)
            for st, k in enumerate(order):
                S.put('arpL' if st % 2 == 0 else 'arpR', arp_note(tones[k] + lift, 0.25) * 0.05, s0 + st)
        elif sec != 'B' or flip:
            order = [0, 1, 2, 3, 2, 3, 1, 2, 0, 1, 2, 3, 2, 3, 1, 3] if sec in ('C', 'drop') else [0, 1, 2, 3] * 4
            for st, k in enumerate(order):
                v = 0.06 if sec != 'C' else 0.075
                S.put('arpL' if st % 2 == 0 else 'arpR', arp_note(tones[k] + up) * v, s0 + st)
                if flip and sec in ('drop', 'C'):
                    S.put('spark', arp_note(tones[(k + 2) % 4] + 24, 0.125, 0.5) * 0.02, s0 + st)
        else:
            # B: a slower, wider pattern (8ths) so the tune can sing
            for st, k in enumerate([0, 2, 1, 3, 0, 2, 1, 3]):
                S.put('arpL' if st % 2 == 0 else 'arpR', arp_note(tones[k] + 12, 0.25, 1.6) * 0.05, s0 + st * 2)

        # ---- chords ---------------------------------------------------------
        if sec == 'brk' or sec == 'B':
            S.put('pad', pad(STAB[ch], BAR * 0.98, 0.3 if sec == 'brk' else 0.05) * (0.13 if sec == 'brk' else 0.12), s0)
        if heavy:
            for st in (2, 6, 10, 14):  # stabs on the off-beats
                S.put('stabL', stab(STAB[ch], 0.996) * 0.15, s0 + st)
                S.put('stabR', stab(STAB[ch], 1.004) * 0.15, s0 + st)
        if sec == 'intro' and i == 0:
            S.put('pad', pad(STAB[ch], BEAT * 2, 0.005) * 0.3, s0)  # (the hit)

        # ---- the tune -------------------------------------------------------
        mel, vol, duty, echo, harm, octave = None, 0.2, 0.25, flip, False, False
        if sec == 'A':
            mel = MEL_A[i % 8]
            echo = echo or second
            harm = second
        elif sec == 'B':
            mel, duty = MEL_B[i], 0.5
            vol = 0.17
            echo = True
        elif sec == 'brk' and i < 2:
            mel, vol, duty = MEL_DROP[i], 0.09, 0.5  # (a taste of the drop)
        elif sec == 'drop':
            mel = MEL_DROP[i % 8]
            octave = True
            harm = second
            echo = echo or second
        elif sec == 'C':
            mel, vol = MEL_C[i], 0.19
            echo = True
        elif sec == 'turn':
            mel = MEL_TURN[i]
            octave = i in (0, 2, 4, 5)
        elif sec == 'intro' and i == 3:
            mel, vol = INTRO_RUN, 0.15
        if mel:
            pos = 0
            for m, d in mel:
                if m is not None:
                    note = lead(m, d, duty)
                    S.put('lead', note * vol, s0 + pos)
                    if octave:
                        S.put('lead', lead(m - 12, d, 0.5, 0.0) * vol * 0.55, s0 + pos)
                    if harm:
                        S.put('harm', lead(harmony(m, ch), d, 0.5, 0.0) * vol * 0.4, s0 + pos)
                    if echo:
                        S.put('echo', note * vol * 0.3, s0 + pos + 3)
                pos += d

    # ---- the pump: chords and bass duck under each kick ---------------------
    pump = np.ones(N)
    dur = n_of(0.24)
    curve = 1 - 0.55 * (1 - np.linspace(0, 1, dur)) ** 2
    for st in pump_beats:
        i0 = n_of(st * STEP) % N
        k = min(dur, N - i0)
        pump[i0:i0 + k] = np.minimum(pump[i0:i0 + k], curve[:k])
        if k < dur:
            pump[:dur - k] = np.minimum(pump[:dur - k], curve[k:])
    for name in ('bass', 'stabL', 'stabR', 'pad', 'arpL', 'arpR'):
        if name in S.bus:
            S.bus[name] *= pump if name != 'bass' else (0.4 + 0.6 * pump)

    # ---- the mix ------------------------------------------------------------
    B = S.bus
    get = lambda k: B.get(k, np.zeros(N))  # noqa: E731
    lead_b = A.shape(get('lead'), hi=6500 if not flip else 7500, loop=True)
    harm_b = A.shape(get('harm'), hi=5000, loop=True)
    echo_b = A.shape(get('echo'), hi=3500, loop=True)
    arpL = A.shape(get('arpL'), hi=5500, loop=True)
    arpR = A.shape(get('arpR'), hi=5500, loop=True)
    spark = A.shape(get('spark'), hi=9000, loop=True)
    bass = A.shape(get('bass'), hi=1400, lo=28, loop=True)
    pad_b = A.shape(get('pad'), hi=3000, loop=True)
    stabL = A.shape(get('stabL'), hi=4000, loop=True)
    stabR = A.shape(get('stabR'), hi=4000, loop=True)
    hats = A.shape(get('hats'), hi=11000, loop=True)
    cym = get('cym')
    kick_b = A.shape(get('kick'), lo=25, loop=True)
    snare_b = get('snare')
    fx = get('fx')

    def pan(x, p):
        a = (p + 1) * np.pi / 4
        return x * np.cos(a) * np.sqrt(2), x * np.sin(a) * np.sqrt(2)

    L = np.zeros(N)
    R = np.zeros(N)
    for x, p in ((lead_b, 0), (harm_b, -0.25), (echo_b, 0.45), (arpL, -0.45), (arpR, 0.45), (spark, 0.2),
                 (bass, 0), (pad_b, 0), (stabL, -0.6), (stabR, 0.6), (hats, 0.15), (cym, -0.1),
                 (kick_b, 0), (snare_b, 0.05), (fx, 0)):
        l, r = pan(x, p)
        L += l
        R += r
    # a room round the tune, the arpeggio and the chords (a different one each ear)
    send = lead_b * 0.6 + harm_b + arpL + arpR + pad_b + stabL + stabR + snare_b * 0.4
    L += room(send, 1.4, 11) * 0.22
    R += room(send, 1.4, 12) * 0.22
    # master: a soft limit (warm, loud enough, no clipping)
    peak = max(np.max(np.abs(L)), np.max(np.abs(R)))
    L, R = L / peak, R / peak
    L = np.tanh(L * 1.5) / np.tanh(1.5)
    R = np.tanh(R * 1.5) / np.tanh(1.5)
    g = 0.9 / max(np.max(np.abs(L)), np.max(np.abs(R)))
    return L * g, R * g


def room(x, seconds, seed):
    """a decaying wash of the sound, round in a circle (the song loops)"""
    n_ir = n_of(seconds)
    t = np.arange(n_ir) / RATE
    ir = np.random.default_rng(seed).uniform(-1, 1, n_ir) * np.exp(-t * 6.9 / seconds)
    ir[:n_of(0.015)] = 0
    ir = A.shape(ir, hi=4500)[:n_ir]
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    k = np.zeros(len(x))
    k[:n_ir] = ir
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(k), len(x))


def save(name, L, R):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name.replace(' ', '_'))
    st = np.empty(2 * N)
    st[0::2], st[1::2] = L, R
    with wave.open(path + '.wav', 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(st, -1, 1) * 32767).astype(np.int16).tobytes())
    import imageio_ffmpeg
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', path + '.wav',
                    '-c:a', 'libvorbis', '-q:a', '6', path + '.ogg'], check=True)
    print('saved', path + '.ogg', f'({N / RATE:.3f} s)')
    return path


def demo(r1, r2):
    """round 1 from the top, and at the second drop's start (bar 41) a swap to
    round 2 at the same spot, as the game does - then round 2 to the end and
    round 1's first 8 bars again (the loop seam)"""
    swap = n_of(40 * BAR)
    one = np.concatenate([r1[0][:swap], r2[0][swap:], r1[0][:n_of(8 * BAR)]])
    two = np.concatenate([r1[1][:swap], r2[1][swap:], r1[1][:n_of(8 * BAR)]])
    out_dir = os.path.join(ROOT, 'Docs', 'music')
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, '_demo.wav')
    st = np.empty(2 * len(one))
    st[0::2], st[1::2] = one, two
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(st, -1, 1) * 32767).astype(np.int16).tobytes())
    import imageio_ffmpeg
    mp3 = os.path.join(out_dir, 'gridlock_theme.mp3')
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', tmp,
                    '-c:a', 'libmp3lame', '-b:a', '192k', mp3], check=True)
    os.remove(tmp)
    print('saved', mp3)


if __name__ == '__main__':
    r1 = render(False)
    save('Gridlock Theme', *r1)
    r2 = render(True)
    save('Gridlock Theme Flip', *r2)
    if '--demo' in sys.argv:
        demo(r1, r2)
