"""GRIDLOCK'S SONG, made from code: an original chiptune boss theme for floor
6, "The Final Beat" - in the spirit of the great RPG final-boss themes (a
heroic minor-key march, 8-bit brass, a running bass, pounding drums, a key
change for the last stand) with a tune of its own. 128 beats a minute, so it
fits his fight beat for beat (Config.Bosses[6].Bpm): the song starts the
moment he wakes up (BossClient starts it where the level is), so the tiles,
his hops and the music hit together.

It is exactly 96 bars long (180.000 s) and loops with no seam: notes and
echoes ringing past the end carry on at the start. D minor, in stereo.

    bars  1-4   THE HITS      ominous orchestra hits as "ATTEMPT 1" comes up
    bars  5-20  THEME         the heroic main tune over a rock beat
    bars 21-28  MARCH         half-time, low brass, triplet arpeggios
    bars 29-32  GLITCH        the theme starts... stutters, tape-stops dead,
                              and REBOOTS
    bars 33-48  THEME, FULL   harmony, octaves, echoes, double kicks
    bars 49-56  MUSIC BOX     everything drops away: the tune on a bell, slow;
                              then a heartbeat and the build
    bars 57-72  THE CHASE     fast runs, a brass line over them, call and
                              answer with the bass, the band in unison
    bars 73-76  STOP          stabs and silence... a fake-out stop... then
    bars 77-92  LAST STAND    the theme a key HIGHER (E minor), everything on
    bars 93-96  TURNAROUND    falling back down into bar 1's hits

Two versions: "Gridlock Theme" (round 1) and "Gridlock Theme Flip" (round 2,
after GRAVITY FLIP!): the same song, bar for bar, played harder - double
kicks, 32nd-note arpeggios, harmony from the start, a sparkle on top. Both
are the same length, so the game swaps one for the other at the same spot
and the beat never slips.

    python3 music_gridlock.py           -> out/bosses/Gridlock_Theme.ogg and
                                           Gridlock_Theme_Flip.ogg (and .wav)
    python3 music_gridlock.py --demo    ...and Docs/music/gridlock_theme.mp3:
                                           round 1, then round 2 from THE
                                           CHASE, then the loop seam

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
BARS = 96
N = int(round(BARS * BAR * RATE))  # 7,938,000 samples: exactly 180 s

# ----------------------------------------------------------------------
# notes and chords
# ----------------------------------------------------------------------
PC = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6,
      'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}
NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
QUALITY = {'': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10]}


def note(s):
    """'C#5' -> 73"""
    name, octave = (s[:2], s[2:]) if len(s) > 2 and s[1] in '#b' else (s[:1], s[1:])
    return 12 * (int(octave) + 1) + PC[name]


def tune(text):
    """'A4:2 D5:2 r:4' -> [(57, 2), (62, 2), (None, 4)] (lengths in 16ths)"""
    out = []
    for tok in text.split():
        n, d = tok.split(':')
        out.append((None if n == 'r' else note(n), float(d)))
    return out


def split_chord(name):
    root = name[:2] if len(name) > 1 and name[1] in '#b' else name[:1]
    return PC[root], name[len(root):]


def chord_pcs(name):
    root, q = split_chord(name)
    return [(root + i) % 12 for i in QUALITY[q]]


def chord_notes(name, lo, count):
    """the chord's notes from `lo` upward, `count` of them"""
    pcs = chord_pcs(name)
    out, m = [], lo
    while len(out) < count:
        if m % 12 in pcs:
            out.append(m)
        m += 1
    return out


def bass_root(name):
    return 36 + split_chord(name)[0]  # C2..B2


def transpose(name, k):
    root, q = split_chord(name)
    return NAMES[(root + k) % 12] + q


def harmony(m, chord):
    """the highest note of the chord at least a third under the tune's note"""
    pcs = chord_pcs(chord)
    for k in range(3, 13):
        if (m - k) % 12 in pcs:
            return m - k
    return m - 12


def with_pos(mel):
    pos = 0.0
    for m, d in mel:
        yield m, d, pos
        pos += d


# ----------------------------------------------------------------------
# the tunes (all original)
# ----------------------------------------------------------------------
THEME_CH = ['Dm', 'Bb', 'C', 'A', 'Dm', 'F', 'Gm', 'A', 'Bb', 'C', 'Dm', 'A7', 'Bb', 'Gm', 'A7', 'Dm']
THEME = [tune(t) for t in [
    # the call: up the chord to a held note, then the same a step higher
    'A4:2 D5:2 F5:2 A5:6 G5:2 F5:2',
    'Bb5:3 A5:3 F5:2 D5:4 C5:2 D5:2',
    'E5:2 G5:2 C6:6 Bb5:2 A5:2 G5:2',
    'A5:6 G5:1 F5:1 E5:4 C#5:4',
    'A4:2 D5:2 F5:2 A5:6 G5:2 A5:2',
    'C6:3 A5:3 F5:2 C6:4 D6:2 C6:2',
    'Bb5:2 A5:2 G5:2 F5:2 D5:4 G5:4',
    'A5:10 E5:2 F5:2 G5:2',
    # the answer: falling from the top, climbing to the cadence
    'D6:3 C6:3 Bb5:2 F5:4 Bb5:4',
    'C6:3 Bb5:3 A5:2 E5:4 C6:4',
    'D6:4 A5:2 F5:2 D5:4 F5:2 A5:2',
    'G5:2 F5:2 E5:2 C#5:2 E5:4 A5:4',
    'D6:3 C6:3 Bb5:2 F5:4 G5:2 A5:2',
    'Bb5:3 A5:3 G5:2 D5:4 G5:4',
    'E5:2 F5:2 G5:2 A5:2 C#6:4 E6:4',
    'D6:12 r:4',
]]
MARCH_CH = ['Dm', 'Dm', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A']
MARCH = [tune(t) for t in [
    'D4:6 E4:2 F4:4 A4:4', 'D5:6 C5:2 A4:4 F4:4', 'F4:6 G4:2 Bb4:4 D5:4', 'F5:6 D5:2 Bb4:4 F4:4',
    'G4:6 A4:2 Bb4:4 D5:4', 'G5:6 F5:2 D5:4 Bb4:4', 'C#5:8 E5:8', 'A5:16',
]]
INTRO_CH = ['Dm', 'Bb', 'C', 'A']
INTRO = [tune(t) for t in ['D4:16', 'F4:8 D4:8', 'E4:6 G4:10', 'A4:4 r:8 E4:1 F4:1 G4:1 G#4:1']]
INTRO_HITS = [[0], [0], [0, 6], [0, 4, 8]]
CALM_CH = ['Dm', 'Dm', 'Bb', 'Bb', 'C', 'C', 'A', 'A']
CHASE_CH = ['Dm', 'C', 'Bb', 'A'] * 4
RUNS = [tune(t) for t in [
    'D5:1 F5:1 A5:1 D6:1 C6:1 A5:1 F5:1 A5:1 D6:1 A5:1 F5:1 D5:1 F5:2 A5:2',
    'C5:1 E5:1 G5:1 C6:1 Bb5:1 G5:1 E5:1 G5:1 C6:1 G5:1 E5:1 C5:1 E5:2 G5:2',
    'Bb4:1 D5:1 F5:1 Bb5:1 A5:1 F5:1 D5:1 F5:1 Bb5:1 F5:1 D5:1 Bb4:1 D5:2 F5:2',
    'A4:1 C#5:1 E5:1 A5:1 G5:1 E5:1 C#5:1 E5:1 A5:4 C#6:4',
]]
CHASE_BRASS = [tune(t) for t in ['D6:16', 'E6:8 C6:8', 'D6:8 Bb5:8', 'C#6:8 E6:8']]
CHASE_CALL = [tune(t) for t in [
    'D6:2 C6:1 A5:1 F5:4 r:8', 'C6:2 Bb5:1 G5:1 E5:4 r:8', 'Bb5:2 A5:1 F5:1 D5:4 r:8',
    'A5:2 G5:1 E5:1 C#5:4 E5:2 G5:2 A5:2 C#6:2',
]]
CHASE_UNISON = [tune(t) for t in [
    'D6:2 C6:2 Bb5:2 A5:2 G5:2 F5:2 E5:2 D5:2', 'E5:2 F5:2 G5:2 A5:2 Bb5:2 C6:2 D6:2 E6:2',
    'F6:8 D6:4 Bb5:4', 'A5:4 C#6:4 E6:8',
]]
STOP_CH = ['Bb', 'C', 'D', 'B7']
STOP_HITS = [[0, 3, 6, 10, 12], [0, 3, 6, 10, 12], [0, 3, 6], [0]]
OUTRO_CH = ['Em', 'C', 'Bb', 'A']
OUTRO = [tune(t) for t in ['E6:8 D6:4 B5:4', 'C6:8 G5:4 E5:4', 'F5:8 D5:4 Bb4:4', 'A4:4 C#5:4 E5:4 G5:2 A5:2']]

# the plan, bar by bar: (section, chord, bar within its section)
PLAN = ([('intro', c, i) for i, c in enumerate(INTRO_CH)]
        + [('theme', c, i) for i, c in enumerate(THEME_CH)]
        + [('march', c, i) for i, c in enumerate(MARCH_CH)]
        + [('glitch', c, i) for i, c in enumerate(THEME_CH[:4])]
        + [('power', c, i) for i, c in enumerate(THEME_CH)]
        + [('calm', c, i) for i, c in enumerate(CALM_CH)]
        + [('chase', c, i) for i, c in enumerate(CHASE_CH)]
        + [('stop', c, i) for i, c in enumerate(STOP_CH)]
        + [('final', transpose(c, 2), i) for i, c in enumerate(THEME_CH)]
        + [('outro', c, i) for i, c in enumerate(OUTRO_CH)])
assert len(PLAN) == BARS
START = {}
for _b, (_s, _c, _i) in enumerate(PLAN):
    START.setdefault(_s, _b)


# ----------------------------------------------------------------------
# instruments (band-limited pulses: clean 8-bit, no fizz)
# ----------------------------------------------------------------------
def n_of(seconds):
    return int(round(seconds * RATE))


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


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
    """the NES triangle: 16 steps (warm, a little buzzy)"""
    ph = np.cumsum(np.full(n, freq / RATE)) % 1.0
    return np.round((4 * np.abs(ph - 0.5) - 1) * 7.5) / 7.5


def brass(m, steps, legato=0.96):
    """the 8-bit brass lead: two pulses, a scoop up into each note, a
    vibrato creeping into the long ones"""
    n = n_of(steps * STEP * legato)
    t = np.arange(n) / RATE
    f = np.full(n, midi(m)) * 2 ** ((-0.8 * np.exp(-t / 0.03)) / 12)
    if steps >= 3:
        f *= 1 + 0.0075 * np.sin(2 * np.pi * 5.7 * t) * np.clip((t - 0.18) / 0.2, 0, 1)
    x = 0.62 * pulse(f, n, 0.5) + 0.38 * pulse(f * 1.004, n, 0.25)
    return x * A.adsr(n, 0.01, 0.22, 0.8, 0.04)


def lead2(m, steps):
    """the harmony / counter voice: a thinner pulse"""
    n = n_of(steps * STEP * 0.94)
    t = np.arange(n) / RATE
    f = np.full(n, midi(m)) * (1 + 0.005 * np.sin(2 * np.pi * 5.4 * t) * np.clip((t - 0.2) / 0.2, 0, 1))
    return pulse(f, n, 0.25) * A.adsr(n, 0.008, 0.2, 0.7, 0.03)


def chip(m, length, duty=0.125):
    """a short arpeggio blip"""
    n = n_of(length)
    return pulse(midi(m), n, duty) * A.adsr(n, 0.002, 0.04, 0.35, 0.01)


def runner(m, steps):
    """the chase's fast runs: bright, punchy blips"""
    return chip(m, steps * STEP * 0.9, 0.25) * 1.6


def bass(m, steps, sustain=0.75):
    n = n_of(steps * STEP * 0.9)
    x = tri_steps(midi(m), n) + 0.38 * pulse(midi(m), n, 0.5)
    return x * A.adsr(n, 0.003, 0.1, sustain, 0.012)


def stab(chord_name, lo=55, length=2.0, spread=1.0):
    """a band stab: the chord, short"""
    n = n_of(STEP * length)
    x = np.zeros(n)
    for m in chord_notes(chord_name, lo, 4):
        x += 0.6 * pulse(midi(m) * spread, n, 0.5) + 0.4 * pulse(midi(m) * spread * 1.003, n, 0.25)
    return x * A.adsr(n, 0.004, 0.12, 0.55, 0.03) / 4


def tom(f, vol=1.0):
    s = 0.24
    n = n_of(s)
    t = np.arange(n) / RATE
    fr = f * (1.6 * np.exp(-t / 0.03) + 1)
    x = np.sin(2 * np.pi * np.cumsum(fr) / RATE) * np.exp(-t / 0.09)
    x += A.shape(A.noise(n), hi=2500)[:n] * np.exp(-t / 0.02) * 0.3
    return np.tanh(1.4 * x) * vol


def kick(vol=1.0):
    k = A.kick(1.0)
    b = A.boom(130, 45, 0.2, 0.45)
    x = np.zeros(max(len(k), len(b)))
    x[:len(k)] += k
    x[:len(b)] += b
    return np.tanh(1.4 * x) * vol


def snare(vol=1.0, s=0.15):
    return A.snare(vol, s)


def big_hit(chord_name, vol=1.0):
    """an orchestra hit: the chord wide and low, a timpani, a boom"""
    s = 0.9
    n = n_of(s)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for m in chord_notes(chord_name, 50, 5):
        x += 0.55 * pulse(midi(m), n, 0.5) + 0.45 * pulse(midi(m) * 1.004, n, 0.25)
    x = A.shape(x / 5 * np.exp(-t / 0.22) * np.clip(t / 0.003, 0, 1), hi=3200)[:n]
    for y in (A.timpani(midi(bass_root(chord_name)), 0.9, 0.9), A.boom(95, 32, 0.9, 0.6)):
        k = min(n, len(y))
        x[:k] += y[:k]
    return x * vol


def reboot(vol=1.0):
    """the level rebooting: a fast climbing 8-bit arpeggio"""
    out = np.zeros(n_of(BEAT * 1.05))
    seq = [50, 53, 57, 62, 65, 69, 74, 77, 81, 86, 89, 93]
    for k, m in enumerate(seq):
        y = chip(m, BEAT / 12 * 0.9, 0.25)
        i = n_of(k * BEAT / 12)
        out[i:i + len(y)] += y[:len(out) - i]
    return out * vol


def riser(seconds, vol=1.0):
    n = n_of(seconds)
    t = np.arange(n) / RATE
    u = t / seconds
    nz = A.sweep_lp(A.noise(n), 300 * (45 ** u)) * (u ** 1.6)
    tone = pulse(midi(50) * (2 ** (2 * u)), n, 0.25) * 0.22 * u ** 2
    x = (nz * 0.8 + tone) * vol
    f = n_of(0.012)
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

    def melody(self, name, mel, s0, vol, voice=brass, harm_chord=None, octave=False, echo=False):
        for m, d, pos in with_pos(mel):
            if m is None:
                continue
            x = voice(m, d)
            self.put(name, x * vol, s0 + pos)
            if octave:
                self.put(name, lead2(m - 12, d) * vol * 0.45, s0 + pos)
            if harm_chord:
                self.put('harm', lead2(harmony(m, harm_chord), d) * vol * 0.42, s0 + pos)
            if echo:
                self.put('echo', x * vol * 0.28, s0 + pos + 3)


def drums(S, sec, i, s0, flip):
    """the beat for one bar"""
    def k(st, v=0.7):
        S.put('kick', kick(v), s0 + st)

    def sn(st, v=0.42, s=0.15):
        S.put('snare', snare(v, s), s0 + st)

    def hat(st, v=0.05, s=0.03):
        if v > 0:
            S.put('hats', A.hat(v, s), s0 + st)

    def crash(st=0, v=0.2):
        S.put('cym', A.crash(v, 1.8), s0 + st)

    def fill():
        for j, f in enumerate((220, 180, 140, 105)):
            S.put('toms', tom(f, 0.45), s0 + 12 + j)

    if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
        big = sec in ('power', 'final')
        for st in (0, 6, 8):  # the rock beat: 1, the and of 2, 3
            k(st, 0.72 if big else 0.66)
        if flip or big:
            k(10, 0.45)
        sn(4)
        sn(12)
        for st in range(16):
            hat(st, (0.06 if st % 2 == 0 else 0.035) if (big or flip) else (0.05 if st % 2 == 0 else 0.0))
        S.put('hats', A.hat(0.08, 0.12), s0 + 14)  # (an open hat)
        if i % 4 == 3:
            if big or flip:
                for st in (12, 13, 14, 15):
                    k(st, 0.5)  # double kicks
            fill()
        if i % 8 == 0:
            crash()
        if sec == 'outro' and i == 3:
            for j in range(8):
                sn(8 + j, 0.2 + 0.03 * j, 0.08)
    elif sec == 'march':
        k(0, 0.7)
        k(10, 0.5)
        sn(8, 0.48)  # half time: the snare on 3
        for st in (13, 14, 15):
            sn(st, 0.08, 0.06)  # (ghost notes)
        for st in range(0, 16, 1 if flip else 2):
            hat(st, 0.045)
        if flip:
            k(6, 0.45)
        if i in (0, 4):
            crash(0, 0.16)
        if i == 7:
            for j in range(16):
                sn(j, 0.1 + 0.02 * j, 0.06)
    elif sec == 'calm':
        if i >= 6:  # a heartbeat, then the build
            for st in (0, 2, 8, 10):
                k(st, 0.5 if st % 8 == 0 else 0.35)
            if i == 7:
                for j in range(8):
                    sn(j, 0.12 + 0.02 * j, 0.07)
                for j in range(16):
                    sn(8 + j * 0.5, 0.25 + 0.012 * j, 0.05)
    elif sec == 'chase':
        for st in range(0, 16, 1 if flip else 2):
            k(st, 0.62 if st % 4 == 0 else 0.45)
        sn(4, 0.45)
        sn(12, 0.45)
        for st in range(16):
            hat(st, 0.055 if st % 2 == 0 else 0.04)
        if i % 4 == 0:
            crash()
        if i % 4 == 3:
            fill()
    elif sec == 'stop':
        for st in STOP_HITS[i]:
            k(st, 0.75)
            sn(st, 0.35)
        if i == 0:
            crash()
        if i == 2:
            for j, f in enumerate((250, 220, 190, 160, 140, 120, 100, 90)):
                S.put('toms', tom(f, 0.5), s0 + 8 + j)
        if i == 3:
            for j in range(4):
                sn(12 + j, 0.3 + 0.06 * j, 0.07)
    elif sec == 'intro':
        if flip:
            for st in range(0, 16, 2):
                k(st, 0.3)
        if i == 3:
            for j in range(8):
                sn(8 + j * 0.5, 0.12 + 0.03 * j, 0.05)
            for j in range(8):
                sn(12 + j * 0.5, 0.36 + 0.02 * j, 0.05)


def render(flip=False):
    S = Song()
    pump_beats = []
    for bar, (sec, ch, i) in enumerate(PLAN):
        s0 = bar * 16
        drums(S, sec, i, s0, flip)
        root = bass_root(ch)
        tones = chord_notes(ch, 62, 4)

        # ---- the hits -------------------------------------------------------
        if sec == 'intro':
            for st in INTRO_HITS[i]:
                S.put('hit', big_hit(ch, 0.42 if st == 0 else 0.3), s0 + st)
                if st == 0:
                    S.put('cym', A.crash(0.22, 2.0), s0)
            for j in range(32):  # a low tremolo growling under it
                S.put('bass', bass(root, 0.5, 0.9) * (0.18 + 0.004 * j + 0.04 * i), s0 + j * 0.5)
            S.melody('lead', INTRO[i], s0, 0.16)
            continue
        if sec == 'stop':
            for st in STOP_HITS[i]:
                S.put('hit', stab(ch, 55, 2) * 0.5, s0 + st)
                S.put('bass', bass(root, 2) * 0.8, s0 + st)
                S.put('lead', brass(chord_notes(ch, 74, 1)[0], 2) * 0.2, s0 + st)
            if i == 3:
                S.put('hit', big_hit(ch, 0.4), s0)
                S.melody('lead', tune('r:12 B4:1 D#5:1 F#5:1 A5:1'), s0, 0.18)
                for j, m in enumerate((47, 51, 54, 57)):
                    S.put('bass', bass(m, 1) * 0.85, s0 + 12 + j)
            continue

        # ---- bass -----------------------------------------------------------
        if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
            # running octaves in 16ths, walking to the next bar on the last beat
            nxt = bass_root(PLAN[(bar + 1) % BARS][1])
            for st in range(16):
                base = root if st < 12 else int(round(root + (nxt - root) * (st - 11) / 5))
                S.put('bass', bass(base + (12 if st % 2 else 0), 1) * 0.62, s0 + st)
            pump_beats += [s0, s0 + 8]
        elif sec == 'march':
            for st, m in ((0, root), (8, root + 7), (12, root + 12)):
                S.put('bass', bass(m, 8 if st == 0 else 4, 0.85) * 0.78, s0 + st)
        elif sec == 'calm':
            if i % 2 == 0:
                S.put('bass', bass(root, 32, 0.9) * 0.4, s0)
        elif sec == 'chase':
            if 8 <= i < 12:  # the bass answers the call: up the scale
                for st in range(8):
                    S.put('bass', bass(root + (12 if st % 2 else 0), 1) * 0.6, s0 + st)
                scale = [0, 2, 3, 5, 7, 8, 10, 12] if 'm' in ch else [0, 2, 4, 5, 7, 9, 10, 12]
                for j, d in enumerate(scale):
                    S.put('bass', bass(root + 12 + d, 1) * 0.75, s0 + 8 + j)
            else:
                for st in range(16):  # a gallop
                    m = root + (12 if st % 4 in (1, 2) else 0) + (7 if st % 8 == 6 else 0)
                    S.put('bass', bass(m, 1) * 0.62, s0 + st)
            pump_beats += [s0, s0 + 4, s0 + 8, s0 + 12]

        # ---- arpeggios --------------------------------------------------------
        if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
            if flip or sec in ('power', 'final'):  # 32nds: the shimmer
                for j in range(32):
                    m = tones[[0, 1, 2, 3, 2, 1][j % 6]] + 12
                    S.put('arpL' if j % 2 == 0 else 'arpR', chip(m, STEP * 0.45) * 0.045, s0 + j * 0.5)
            else:
                for st, kk in enumerate([0, 1, 2, 3, 2, 1, 0, 1] * 2):
                    S.put('arpL' if st % 2 == 0 else 'arpR', chip(tones[kk], STEP * 0.85) * 0.055, s0 + st)
        elif sec == 'march':
            for beat in range(4):  # triplets
                for j in range(3):
                    m = tones[(beat + j) % 4]
                    S.put('arpL' if j % 2 == 0 else 'arpR', chip(m, BEAT / 3 * 0.85, 0.25) * 0.05,
                          s0 + beat * 4 + j * 4 / 3)
        elif sec == 'calm':
            for st in range(0, 16, 4):  # a slow bell arpeggio
                S.put('bell', A.bell(midi(tones[(st // 4) % 4] + 12), 1.2, 0.05), s0 + st)
            if i % 2 == 0:
                S.put('pad', A.choir(chord_notes(ch, 55, 4), BAR * 2 * 0.98, 0.1), s0)
        elif sec == 'chase':
            up = 24 if flip else 12
            for j in range(16):
                S.put('arpL' if j % 2 == 0 else 'arpR', chip(tones[j % 4] + up, STEP * 0.5) * 0.03, s0 + j)
        if flip and sec in ('power', 'final', 'chase'):
            for j in range(16):
                S.put('spark', chip(tones[(j * 3) % 4] + 24, STEP * 0.4) * 0.018, s0 + j + 0.5)

        # ---- chords -------------------------------------------------------------
        if sec in ('power', 'final', 'chase'):
            for st in (2, 6, 10, 14):
                S.put('stabL', stab(ch, 55, 1.5, 0.997) * 0.12, s0 + st)
                S.put('stabR', stab(ch, 55, 1.5, 1.003) * 0.12, s0 + st)
        if sec == 'march' and i % 2 == 0:
            S.put('pad', A.choir(chord_notes(ch, 50, 4), BAR * 2 * 0.98, 0.07), s0)

        # ---- the tunes ------------------------------------------------------------
        if sec == 'theme':
            S.melody('lead', THEME[i], s0, 0.2, harm_chord=ch if (flip and i >= 8) else None, echo=flip)
        elif sec == 'glitch':
            S.melody('lead', THEME[i], s0, 0.2, octave=True)
        elif sec == 'power':
            S.melody('lead', THEME[i], s0, 0.21, harm_chord=ch, octave=True, echo=True)
        elif sec == 'final':
            mel = [(None if m is None else m + 2, d) for m, d in THEME[i]]
            S.melody('lead', mel, s0, 0.22, harm_chord=ch, octave=True, echo=True)
        elif sec == 'march':
            S.melody('lead', MARCH[i], s0, 0.19)
            if flip:
                S.melody('lead', MARCH[i], s0, 0.07, lead2)
        elif sec == 'calm':
            # the theme on a bell, half speed: one bar of the tune every two bars
            if i % 2 == 0:
                for m, d, pos in with_pos(THEME[i // 2]):
                    if m is not None:
                        S.put('bell', A.bell(midi(m), max(0.8, d * 2 * STEP * 1.5), 0.14), s0 + pos * 2)
            if i == 6:
                S.put('fx', riser(BAR * 2, 0.3), s0)
        elif sec == 'chase':
            q = i // 4
            if q == 0:
                S.melody('lead', RUNS[i % 4], s0, 0.15, runner)
            elif q == 1:
                S.melody('lead', RUNS[i % 4], s0, 0.1, runner)
                S.melody('lead', CHASE_BRASS[i % 4], s0, 0.2, harm_chord=ch)
            elif q == 2:
                S.melody('lead', CHASE_CALL[i % 4], s0, 0.22, octave=True, echo=True)
            else:
                S.melody('lead', CHASE_UNISON[i % 4], s0, 0.22, octave=True)
                for m, d, pos in with_pos(CHASE_UNISON[i % 4]):
                    if m is not None:
                        S.put('bass', bass(m - 36, d) * 0.5, s0 + pos)  # (the bass in unison too)
        elif sec == 'outro':
            S.melody('lead', OUTRO[i], s0, 0.21, octave=True, echo=True)

        # big hits where big things begin
        if i == 0 and sec in ('power', 'final', 'chase'):
            S.put('hit', big_hit(ch, 0.35 if sec != 'chase' else 0.3), s0)

    return mix(S, pump_beats, flip)


def mix(S, pump_beats, flip):
    # the pump: the stabs and arpeggios duck a little under the downbeats
    pump = np.ones(N)
    dur = n_of(0.2)
    curve = 1 - 0.35 * (1 - np.linspace(0, 1, dur)) ** 2
    for st in pump_beats:
        i0 = n_of(st * STEP) % N
        k = min(dur, N - i0)
        pump[i0:i0 + k] = np.minimum(pump[i0:i0 + k], curve[:k])
    for name in ('stabL', 'stabR', 'arpL', 'arpR'):
        if name in S.bus:
            S.bus[name] *= pump

    def get(k):
        return S.bus.get(k, np.zeros(N))

    lead = A.shape(get('lead'), hi=7000 if flip else 6200, loop=True)
    harm = A.shape(get('harm'), hi=4800, loop=True)
    echo = A.shape(get('echo'), hi=3200, loop=True)
    arpL = A.shape(get('arpL'), hi=6000, loop=True)
    arpR = A.shape(get('arpR'), hi=6000, loop=True)
    spark = A.shape(get('spark'), hi=9000, loop=True)
    bass_b = A.shape(get('bass'), hi=1500, lo=30, loop=True)
    pad, bell, hit, cym, snare_b, toms, fx = (get(k) for k in ('pad', 'bell', 'hit', 'cym', 'snare', 'toms', 'fx'))
    stabL = A.shape(get('stabL'), hi=4200, loop=True)
    stabR = A.shape(get('stabR'), hi=4200, loop=True)
    hats = A.shape(get('hats'), hi=11000, loop=True)
    kick_b = A.shape(get('kick'), lo=28, loop=True)

    def pan(x, p):
        a = (p + 1) * np.pi / 4
        return x * np.cos(a) * np.sqrt(2), x * np.sin(a) * np.sqrt(2)

    L = np.zeros(N)
    R = np.zeros(N)
    for x, p in ((lead, 0), (harm, -0.3), (echo, 0.45), (arpL, -0.5), (arpR, 0.5), (spark, 0.25),
                 (bass_b, 0), (pad, 0), (bell, -0.15), (stabL, -0.6), (stabR, 0.6), (hit, 0),
                 (hats, 0.2), (cym, -0.15), (kick_b, 0), (snare_b, 0.05), (toms, -0.1), (fx, 0)):
        l, r = pan(x, p)
        L += l
        R += r
    # a hall round the tune, the arpeggios, the chords and the hits (a different one each ear)
    send = lead * 0.5 + harm + arpL + arpR + pad + bell * 1.5 + stabL + stabR + snare_b * 0.4 + hit * 0.5
    L += room(send, 1.6, 11) * 0.24
    R += room(send, 1.6, 12) * 0.24

    L, R = glitch(L, R)
    # master: a soft limit (warm, loud, never clipping)
    peak = max(np.max(np.abs(L)), np.max(np.abs(R)))
    L, R = L / peak, R / peak
    L = np.tanh(L * 1.6) / np.tanh(1.6)
    R = np.tanh(R * 1.6) / np.tanh(1.6)
    g = 0.9 / max(np.max(np.abs(L)), np.max(np.abs(R)))
    return L * g, R * g


def _i(step):
    return n_of(step * STEP)


def glitch(L, R):
    """THE GLITCH (bars 29-32): the theme starts, stutters (each repeat
    shorter and higher), crunches, tape-stops dead... and reboots"""
    g0 = START['glitch'] * 16
    bar3, bar4 = g0 + 32, g0 + 48
    fade = n_of(0.002)
    out = []
    for x in (L, R):
        y = x.copy()
        idx = np.arange(len(x))

        def slice_to(dst, src, length, rate=1.0):
            n = _i(length)
            sl = np.interp(_i(src) + np.arange(n) * rate, idx, x)
            sl[:fade] *= np.linspace(0, 1, fade)
            sl[-fade:] *= np.linspace(1, 0, fade)
            y[_i(dst):_i(dst) + n] = sl

        for r in range(2):  # beat 2: the first 8th, twice
            slice_to(bar3 + 4 + 2 * r, bar3, 2)
        for r in range(4):  # beat 3: the first 16th, four times
            slice_to(bar3 + 8 + r, bar3, 1)
        for r in range(8):  # beat 4: 32nds, climbing in pitch
            slice_to(bar3 + 12 + r * 0.5, bar3, 0.5, 1 + r * 0.12)
        a, b = _i(bar3 + 8), _i(bar3 + 16)  # the crunch: fewer bits, held samples
        held = np.repeat(y[a:b][::6], 6)[:b - a]
        y[a:b] = np.round(held * 10) / 10
        # the last bar: the tape stops over two beats, then silence
        a, n = _i(bar4), _i(8)
        k = np.arange(n)
        sl = np.interp(a + k - k * k / (2 * n), idx, x) * np.linspace(1, 0.2, n)
        sl[-fade * 4:] *= np.linspace(1, 0, fade * 4)
        y[a:a + n] = sl
        y[a + n:_i(bar4 + 16)] = 0
        out.append(y)
    L, R = out
    # ...and the reboot, with a snare flam into the slam
    adds = [(reboot(0.3), bar4 + 12)] + [(snare(0.3 + 0.08 * j, 0.06), bar4 + 12 + j) for j in range(4)]
    for sound, st in adds:
        i = _i(st)
        for x in (L, R):
            x[i:i + len(sound)] += sound[:len(x) - i]
    return L, R


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


def write_wav(path, L, R):
    st = np.empty(2 * len(L))
    st[0::2], st[1::2] = L, R
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(st, -1, 1) * 32767).astype(np.int16).tobytes())


def save(name, L, R):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name.replace(' ', '_'))
    write_wav(path + '.wav', L, R)
    import imageio_ffmpeg
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', path + '.wav',
                    '-c:a', 'libvorbis', '-q:a', '6', path + '.ogg'], check=True)
    print('saved', path + '.ogg', f'({N / RATE:.3f} s)')


def demo(r1, r2):
    """round 1 from the top, a swap to round 2 at THE CHASE (as the game swaps
    at the same spot), round 2 to the end, then round 1's first 8 bars again"""
    swap = n_of(START['chase'] * BAR)
    tail = n_of(8 * BAR)
    L = np.concatenate([r1[0][:swap], r2[0][swap:], r1[0][:tail]])
    R = np.concatenate([r1[1][:swap], r2[1][swap:], r1[1][:tail]])
    out_dir = os.path.join(ROOT, 'Docs', 'music')
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, '_demo.wav')
    write_wav(tmp, L, R)
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
