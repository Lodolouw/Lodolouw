"""GRIDLOCK'S SONG, made from code: an original chiptune boss theme for floor
6, "The Final Beat" - in the spirit of the great RPG final-boss themes (a
heroic, aching minor-key tune, 8-bit brass that SINGS, strings under it, a
running bass, pounding drums, a key change for the last stand) with a tune
of its own. 128 beats a minute, so it fits his fight beat for beat
(Config.Bosses[6].Bpm): the song starts the moment he wakes up (BossClient
starts it where the level is), so the tiles, his hops and the music hit
together.

What makes it sing rather than tick: every note of the tune has a loudness
of its own (louder up high and on the strong beats), slides into the notes
it leans on, a vibrato that blooms on long notes, a tone that opens and
closes as it's held, trills and grace notes on the big moments; a second
voice moves against the tune (not just a copy of it); strings hold the
chords, each voice moving the shortest way to the next; the drums are
played a hair loose, with ghost notes and fills that change.

It is exactly 96 bars long (180.000 s) and loops with no seam: notes and
echoes ringing past the end carry on at the start. D minor, in stereo.

    bars  1-4   THE HITS      ominous orchestra hits as "ATTEMPT 1" comes up
    bars  5-20  THEME         the tune: a yearning leap up, a sigh down
    bars 21-28  MARCH         half-time, low brass, triplet arpeggios
    bars 29-32  GLITCH        the theme starts... stutters, tape-stops dead,
                              and REBOOTS
    bars 33-48  THEME, FULL   the counter-voice, octaves, echoes, double kicks
    bars 49-56  MUSIC BOX     everything drops away: the tune on a bell, slow,
                              over strings; then a heartbeat and the build
    bars 57-72  THE CHASE     fast runs, a brass line over them, call and
                              answer with the bass, the band in unison
    bars 73-76  STOP          stabs and silence... a fake-out stop... then
    bars 77-92  LAST STAND    the theme a key HIGHER (E minor), everything on
    bars 93-96  TURNAROUND    falling back down into bar 1's hits

Two versions: "Gridlock Theme" (round 1) and "Gridlock Theme Flip" (round 2,
after GRAVITY FLIP!): the same song, bar for bar, played harder - double
kicks, 32nd-note arpeggios, the counter-voice from the start, a sparkle on
top. Both are the same length, so the game swaps one for the other at the
same spot and the beat never slips.

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
QUALITY = {'': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10], 'sus': [0, 5, 7]}
D_MINOR = {2, 4, 5, 7, 9, 10, 0}  # (for trills: the next note up the scale)


def note(s):
    """'C#5' -> 73"""
    name, octave = (s[:2], s[2:]) if len(s) > 2 and s[1] in '#b' else (s[:1], s[1:])
    return 12 * (int(octave) + 1) + PC[name]


def tune(text):
    """'A4:2 /D5:2 ~F5:4 *G5:2 r:4' -> [(midi or None, 16ths, flags)].
    Flags: / slide in from the note before, ~ trill on the second half,
    * a grace note a step above, just before it."""
    out = []
    for tok in text.split():
        flags = ''
        while tok[0] in '/~*':
            flags += tok[0]
            tok = tok[1:]
        n, d = tok.split(':')
        out.append((None if n == 'r' else note(n), float(d), flags))
    return out


def with_pos(mel):
    pos = 0.0
    for m, d, fl in mel:
        yield m, d, pos, fl
        pos += d


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


def step_up(m, shift=0):
    """the next note up the scale (D minor, or shifted for the last stand)"""
    return m + 1 if ((m + 1 - shift) % 12) in D_MINOR else m + 2


# ----------------------------------------------------------------------
# the tunes (all original)
# ----------------------------------------------------------------------
THEME_CH = ['Dm', 'Bb', 'Gm', 'A', 'Dm', 'Bb', 'C', 'A', 'F', 'C', 'Bb', 'A', 'Dm', 'Gm', 'A7', 'Dm']
THEME = [tune(t) for t in [
    # the call: a yearning leap up a sixth, then a sigh back down
    'A4:3 /F5:5 E5:2 D5:2 E5:2 F5:2',
    '*G5:6 F5:2 E5:2 D5:2 C5:2 D5:2',
    'Bb4:3 /G5:5 F5:2 E5:2 F5:2 G5:2',
    'A5:8 G5:2 F5:2 E5:2 C#5:2',
    'A4:3 /F5:5 E5:2 D5:2 E5:2 F5:2',
    '/D6:6 C6:2 Bb5:2 A5:2 G5:2 F5:2',
    'E5:3 G5:3 *C6:4 Bb5:2 A5:2 G5:2',
    '~A5:10 G5:2 F5:2 E5:2',
    # the answer: brighter (F, C), then the big climb and the fall to home
    '/C6:6 A5:2 F5:4 G5:2 A5:2',
    '/G5:6 E5:2 C5:4 D5:2 E5:2',
    'F5:3 /D6:5 C6:2 Bb5:2 A5:2 Bb5:2',
    'A5:6 G5:2 F5:2 E5:2 D5:2 C#5:2',
    'D5:3 /A5:5 G5:2 F5:2 E5:2 F5:2',
    'G5:3 /D6:5 C6:2 Bb5:2 A5:2 G5:2',
    '*E6:6 D6:2 C#6:4 Bb5:2 G5:2',
    '~D6:12 r:4',
]]
MARCH_CH = ['Dm', 'Dm', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A']
MARCH = [tune(t) for t in [
    'D4:6 E4:2 F4:4 A4:4', '/D5:6 C5:2 A4:4 F4:4', 'F4:6 G4:2 Bb4:4 D5:4', '/F5:6 D5:2 Bb4:4 F4:4',
    'G4:6 A4:2 Bb4:4 D5:4', '/G5:6 F5:2 D5:4 Bb4:4', 'C#5:8 /E5:8', '~A5:16',
]]
INTRO_CH = ['Dm', 'Bb', 'C', 'A']
INTRO = [tune(t) for t in ['D4:16', 'F4:8 D4:8', 'E4:6 /G4:10', 'A4:4 r:8 E4:1 F4:1 G4:1 G#4:1']]
INTRO_HITS = [[0], [0], [0, 6], [0, 4, 8]]
CALM_CH = ['Dm', 'Dm', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A']
CHASE_CH = ['Dm', 'C', 'Bb', 'A'] * 4
RUNS = [tune(t) for t in [
    'D5:1 F5:1 A5:1 D6:1 C6:1 A5:1 F5:1 A5:1 D6:1 A5:1 F5:1 D5:1 F5:2 A5:2',
    'C5:1 E5:1 G5:1 C6:1 Bb5:1 G5:1 E5:1 G5:1 C6:1 G5:1 E5:1 C5:1 E5:2 G5:2',
    'Bb4:1 D5:1 F5:1 Bb5:1 A5:1 F5:1 D5:1 F5:1 Bb5:1 F5:1 D5:1 Bb4:1 D5:2 F5:2',
    'A4:1 C#5:1 E5:1 A5:1 G5:1 E5:1 C#5:1 E5:1 A5:4 C#6:4',
]]
CHASE_BRASS = [tune(t) for t in ['~D6:16', '/E6:8 C6:8', '/D6:8 Bb5:8', 'C#6:8 /E6:8']]
CHASE_CALL = [tune(t) for t in [
    'D6:2 C6:1 A5:1 F5:4 r:8', 'C6:2 Bb5:1 G5:1 E5:4 r:8', 'Bb5:2 A5:1 F5:1 D5:4 r:8',
    'A5:2 G5:1 E5:1 C#5:4 E5:2 G5:2 A5:2 C#6:2',
]]
CHASE_UNISON = [tune(t) for t in [
    'D6:2 C6:2 Bb5:2 A5:2 G5:2 F5:2 E5:2 D5:2', 'E5:2 F5:2 G5:2 A5:2 Bb5:2 C6:2 D6:2 E6:2',
    '~F6:8 D6:4 Bb5:4', 'A5:4 C#6:4 /E6:8',
]]
STOP_CH = ['Bb', 'C', 'D', 'B7']
STOP_HITS = [[0, 3, 6, 10, 12], [0, 3, 6, 10, 12], [0, 3, 6], [0]]
OUTRO_CH = ['Em', 'C', 'Bb', 'A']
OUTRO = [tune(t) for t in ['~E6:8 D6:4 B5:4', '/C6:8 G5:4 E5:4', '/F5:8 D5:4 Bb4:4', 'A4:4 C#5:4 E5:4 G5:2 A5:2']]

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
# instruments (band-limited: clean 8-bit, no fizz)
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
    """a pulse wave; `duty` may change over the note (an array)"""
    f = np.broadcast_to(np.asarray(freq, float), (n,)).astype(float)
    duty = np.broadcast_to(np.asarray(duty, float), (n,))
    dt = np.clip(f / RATE, 1e-6, 0.45)
    ph = np.cumsum(dt) % 1.0
    y = np.where(ph < duty, 1.0, -1.0)
    y += _blep(ph, dt)
    y -= _blep((ph - duty) % 1.0, dt)
    return y


def saw(freq, n):
    f = np.broadcast_to(np.asarray(freq, float), (n,)).astype(float)
    dt = np.clip(f / RATE, 1e-6, 0.45)
    ph = np.cumsum(dt) % 1.0
    return 2 * ph - 1 - _blep(ph, dt)


def tri_steps(freq, n):
    """the NES triangle: 16 steps (warm, a little buzzy)"""
    ph = np.cumsum(np.full(n, freq / RATE)) % 1.0
    return np.round((4 * np.abs(ph - 0.5) - 1) * 7.5) / 7.5


def brass(m, steps, vel=1.0, glide=None, trill=None, legato=0.97):
    """the singing 8-bit brass: a slide in from `glide` (or a small scoop),
    a vibrato that blooms on held notes, a tone that opens and closes as it's
    held (the pulse's width moving), a swell on the long ones, and a trill to
    `trill` over the second half if asked"""
    dur = steps * STEP * legato
    n = n_of(dur)
    t = np.arange(n) / RATE
    if glide is not None:
        semis = (glide - m) * np.exp(-t / 0.05)
    else:
        semis = -0.6 * np.exp(-t / 0.028)
    if trill is not None:
        rate = 1 / (STEP / 2)  # 32nds
        on = (t > dur * 0.4) & (np.floor(t * rate) % 2 == 1)
        semis = semis + np.where(on, trill - m, 0.0)
    if steps >= 3:
        depth = 0.28 * np.clip((t - 0.16) / 0.5, 0, 1)
        semis = semis + depth * np.sin(2 * np.pi * (5.4 + 0.3 * np.sin(2 * np.pi * 0.7 * t)) * t)
    f = midi(m) * 2 ** (semis / 12)
    duty = 0.5 - 0.22 * np.clip(t / 0.45, 0, 1) + 0.08 * np.clip((t - 0.6) / 0.6, 0, 1)
    x = 0.6 * pulse(f, n, duty) + 0.4 * (0.55 + 0.45 * vel) * pulse(f * 1.004, n, 0.25)
    e = A.adsr(n, 0.012, 0.25, 0.82, 0.05)
    if steps >= 6:
        e = e * (0.82 + 0.18 * np.clip(t / (dur * 0.6), 0, 1))
    return x * e * (0.55 + 0.45 * vel)


def lead2(m, steps, vel=1.0, glide=None, trill=None):
    """the second voice: a thinner pulse, gentler"""
    n = n_of(steps * STEP * 0.95)
    t = np.arange(n) / RATE
    semis = (glide - m) * np.exp(-t / 0.06) if glide is not None else 0.0
    semis = semis + 0.18 * np.clip((t - 0.25) / 0.5, 0, 1) * np.sin(2 * np.pi * 5.1 * t)
    f = midi(m) * 2 ** (semis / 12)
    return pulse(f, n, 0.25) * A.adsr(n, 0.02, 0.3, 0.75, 0.06) * (0.6 + 0.4 * vel)


def chip(m, length, duty=0.125):
    """a short arpeggio blip"""
    n = n_of(length)
    return pulse(midi(m), n, duty) * A.adsr(n, 0.002, 0.04, 0.35, 0.01)


def runner(m, steps, vel=1.0, glide=None, trill=None):
    """the chase's fast runs: bright, punchy blips"""
    return chip(m, steps * STEP * 0.9, 0.25) * 1.6 * (0.7 + 0.3 * vel)


def bass(m, steps, sustain=0.75, slide=None):
    n = n_of(steps * STEP * 0.9)
    t = np.arange(n) / RATE
    f = midi(m) * (2 ** ((slide - m) * np.exp(-t / 0.04) / 12) if slide is not None else 1.0)
    f = np.broadcast_to(np.asarray(f, float), (n,))
    ph = np.cumsum(f / RATE) % 1.0
    tri = np.round((4 * np.abs(ph - 0.5) - 1) * 7.5) / 7.5
    x = tri + 0.38 * pulse(f, n, 0.5)
    return x * A.adsr(n, 0.003, 0.1, sustain, 0.012)


def strings(voicing, seconds, attack=0.25):
    """warm strings: three slightly detuned saws per note, a slow vibrato"""
    n = n_of(seconds)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for k, m in enumerate(voicing):
        for d in (-0.06, 0.0, 0.07):
            f = midi(m) * 2 ** (d / 12) * (1 + 0.003 * np.sin(2 * np.pi * (4.7 + 0.4 * k) * t + k))
            x += saw(f, n)
    e = np.clip(t / attack, 0, 1) ** 1.5 * np.clip((seconds - t) / 0.3, 0, 1)
    return x * e / (3 * len(voicing))


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
        x += 0.5 * saw(midi(m) * 1.002, n)
    x = A.shape(x / 5 * np.exp(-t / 0.25) * np.clip(t / 0.003, 0, 1), hi=3200)[:n]
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
    def __init__(self, seed):
        self.bus = {}
        self.rng = np.random.default_rng(seed)
        self.voicing = None  # the strings' last chord (each voice moves the shortest way)
        self.counter = 62  # the counter-voice's last note

    def put(self, name, x, step, loose=0.0):
        """add x into a bus at a 16th (round the end and back to the start);
        `loose` = how far off the grid a player might be (in 16ths)"""
        b = self.bus.get(name)
        if b is None:
            b = self.bus[name] = np.zeros(N)
        if loose:
            step += self.rng.uniform(-loose, loose)
        A.place(b, x, step * STEP, loop=True)

    def melody(self, name, mel, s0, vol, voice=brass, octave=False, echo=False, shift=0, prev=None):
        """a bar of a tune, sung: louder up high and on the strong beats,
        sliding where it's marked, trills and grace notes where asked"""
        notes = [m for m, _, _ in mel if m is not None]
        lo, hi = (min(notes), max(notes)) if notes else (0, 1)
        for m, d, pos, fl in with_pos(mel):
            if m is None:
                prev = None
                continue
            m += shift
            vel = 0.78 + 0.16 * ((m - shift - lo) / max(1, hi - lo)) + (0.06 if pos % 4 == 0 else 0.0)
            vel *= self.rng.uniform(0.95, 1.03)
            glide = prev if ('/' in fl and prev is not None) else None
            trill = step_up(m, shift) if '~' in fl else None
            x = voice(m, d, vel, glide, trill)
            self.put(name, x * vol, s0 + pos, 0.02)
            if '*' in fl:  # a grace note just before
                self.put(name, voice(step_up(m, shift), 0.5, vel * 0.8) * vol * 0.8, s0 + pos - 0.5)
            if octave:
                self.put(name, lead2(m - 12, d, vel, None if glide is None else glide - 12) * vol * 0.42, s0 + pos)
            if echo:  # a dotted-8th echo, bouncing right then left
                self.put('echoR', x * vol * 0.26, s0 + pos + 3)
                self.put('echoL', x * vol * 0.13, s0 + pos + 6)
            prev = m
        return prev

    def chords(self, chord_name, s0, steps, vol, attack=0.25):
        """strings: the chord, each voice moving the shortest way from the last"""
        pcs = chord_pcs(chord_name)
        cands = [m for m in range(50, 77) if m % 12 in pcs]
        if self.voicing is None:
            v = chord_notes(chord_name, 55, 4)
        else:
            v = []
            for old in self.voicing:
                best = min((c for c in cands if c not in v), key=lambda c: (abs(c - old), c))
                v.append(best)
            v.sort()
        self.voicing = v
        self.put('str', strings(v, steps * STEP * 0.99, attack) * vol, s0)

    def counterline(self, chord_name, mel, s0, vol, shift=0):
        """the second voice: two notes a bar, chord notes in the middle, moving
        against the tune (down when it climbs, up when it falls)"""
        pcs = chord_pcs(chord_name)
        for half in (0, 8):
            here = [m for m, d, pos, fl in with_pos(mel) if m is not None and half <= pos < half + 8]
            rising = len(here) >= 2 and here[-1] > here[0]
            cands = [c for c in range(55, 70) if c % 12 in pcs]
            def cost(c):
                move = c - self.counter
                against = (move < 0) if rising else (move > 0)
                return abs(move) + (0 if against or move == 0 else 2.5)
            c = min(cands, key=cost)
            self.put('counter', lead2(c, 8, 0.8, self.counter if abs(c - self.counter) <= 4 else None) * vol, s0 + half, 0.02)
            self.counter = c


def drums(S, sec, i, bar, s0, flip):
    """the beat for one bar, played a hair loose"""
    def k(st, v=0.7):
        S.put('kick', kick(v * S.rng.uniform(0.94, 1.02)), s0 + st, 0.012)

    def sn(st, v=0.42, s=0.15):
        S.put('snare', snare(v * S.rng.uniform(0.92, 1.04), s), s0 + st, 0.018)

    def hat(st, v=0.05, s=0.03):
        if v > 0:
            S.put('hats', A.hat(v * S.rng.uniform(0.8, 1.1), s), s0 + st, 0.02)

    def crash(st=0, v=0.2):
        S.put('cym', A.crash(v, 1.8), s0 + st)

    def fill(kind):
        if kind == 0:  # toms down
            for j, f in enumerate((220, 180, 140, 105)):
                S.put('toms', tom(f, 0.45), s0 + 12 + j, 0.015)
        elif kind == 1:  # a snare run
            for j in range(4):
                sn(12 + j, 0.22 + 0.06 * j, 0.08)
        else:  # snare and toms, 16th triplets feel
            for j, (f, isn) in enumerate(((0, True), (200, False), (0, True), (150, False), (110, False), (0, True))):
                if isn:
                    sn(12 + j * 2 / 3, 0.3, 0.08)
                else:
                    S.put('toms', tom(f, 0.45), s0 + 12 + j * 2 / 3, 0.01)

    if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
        big = sec in ('power', 'final')
        for st in (0, 6, 8):  # the rock beat: 1, the and of 2, 3
            k(st, 0.72 if big else 0.66)
        if flip or big:
            k(10, 0.45)
        sn(4)
        sn(12)
        for st in (7, 15) if not big else (7, 11, 15):
            sn(st, 0.07, 0.06)  # ghost notes
        for st in range(16):
            v = (0.06 if st % 2 == 0 else 0.035) if (big or flip) else (0.05 if st % 2 == 0 else 0.018)
            hat(st, v)
        S.put('hats', A.hat(0.08, 0.12), s0 + 14, 0.02)  # (an open hat)
        if i % 4 == 3:
            if big or flip:
                for st in (12, 13, 14, 15):
                    k(st, 0.5)  # double kicks
            fill((bar // 4) % 3)
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
            sn(st, 0.08, 0.06)  # (a drag)
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
            fill((bar // 4) % 3)
    elif sec == 'stop':
        for st in STOP_HITS[i]:
            k(st, 0.75)
            sn(st, 0.35)
        if i == 0:
            crash()
        if i == 2:
            for j, f in enumerate((250, 220, 190, 160, 140, 120, 100, 90)):
                S.put('toms', tom(f, 0.5), s0 + 8 + j, 0.01)
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


def theme_bass(S, root, nxt, s0, running):
    """the bass under the theme: running 16ths when it's flat out, otherwise
    a driving rhythm with octave pops - both leading into the next chord"""
    approach = nxt - 1 if nxt > root else nxt + 1
    if running:
        for st in range(16):
            base = root if st < 14 else approach if st == 15 else root + (12 if nxt > root else 0)
            S.put('bass', bass(base + (12 if st % 2 and st < 14 else 0), 1) * 0.62, s0 + st, 0.01)
    else:
        pattern = [(0, root, 1.8), (2, root, 1), (3, root + 12, 1), (4, root, 1.8), (6, root + 12, 1.8),
                   (8, root, 1.8), (10, root, 1), (11, root + 12, 1), (12, root + 7, 1.8), (14, root + 12, 1),
                   (15, approach, 1)]
        for st, m, d in pattern:
            S.put('bass', bass(m, d) * 0.7, s0 + st, 0.012)


def render(flip=False):
    S = Song(7 if not flip else 8)
    pump_beats = []
    prev = None
    for bar, (sec, ch, i) in enumerate(PLAN):
        s0 = bar * 16
        drums(S, sec, i, bar, s0, flip)
        root = bass_root(ch)
        nxt = bass_root(PLAN[(bar + 1) % BARS][1])
        tones = chord_notes(ch, 62, 4)

        # ---- the hits -------------------------------------------------------
        if sec == 'intro':
            for st in INTRO_HITS[i]:
                S.put('hit', big_hit(ch, 0.42 if st == 0 else 0.3), s0 + st)
                if st == 0:
                    S.put('cym', A.crash(0.22, 2.0), s0)
            for j in range(32):  # a low tremolo growling under it
                S.put('bass', bass(root, 0.5, 0.9) * (0.18 + 0.004 * j + 0.04 * i), s0 + j * 0.5)
            S.chords(ch, s0, 16, 0.06 + 0.02 * i, 0.6)
            prev = S.melody('lead', INTRO[i], s0, 0.16, prev=prev)
            continue
        if sec == 'stop':
            for st in STOP_HITS[i]:
                S.put('hit', stab(ch, 55, 2) * 0.5, s0 + st)
                S.put('bass', bass(root, 2) * 0.8, s0 + st)
                S.put('lead', brass(chord_notes(ch, 74, 1)[0], 2) * 0.2, s0 + st)
            if i == 3:
                S.put('hit', big_hit(ch, 0.4), s0)
                prev = S.melody('lead', tune('r:12 B4:1 D#5:1 F#5:1 A5:1'), s0, 0.18)
                for j, m in enumerate((47, 51, 54, 57)):
                    S.put('bass', bass(m, 1) * 0.85, s0 + 12 + j)
            else:
                prev = None
            continue

        # ---- bass -----------------------------------------------------------
        if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
            theme_bass(S, root, nxt, s0, running=flip or sec in ('power', 'final'))
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
                    S.put('bass', bass(root + (12 if st % 2 else 0), 1) * 0.6, s0 + st, 0.01)
                scale = [0, 2, 3, 5, 7, 8, 10, 12] if 'm' in ch else [0, 2, 4, 5, 7, 9, 10, 12]
                for j, d in enumerate(scale):
                    S.put('bass', bass(root + 12 + d, 1) * 0.75, s0 + 8 + j, 0.01)
            else:
                for st in range(16):  # a gallop
                    m = root + (12 if st % 4 in (1, 2) else 0) + (7 if st % 8 == 6 else 0)
                    S.put('bass', bass(m, 1) * 0.62, s0 + st, 0.01)
            pump_beats += [s0, s0 + 4, s0 + 8, s0 + 12]

        # ---- arpeggios --------------------------------------------------------
        if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
            if flip or sec in ('power', 'final'):  # 32nds: the shimmer
                for j in range(32):
                    m = tones[[0, 1, 2, 3, 2, 1][j % 6]] + 12
                    S.put('arpL' if j % 2 == 0 else 'arpR', chip(m, STEP * 0.45) * 0.04, s0 + j * 0.5)
            else:
                for st, kk in enumerate([0, 1, 2, 3, 2, 1, 0, 1] * 2):
                    S.put('arpL' if st % 2 == 0 else 'arpR', chip(tones[kk], STEP * 0.85) * 0.045, s0 + st)
        elif sec == 'march':
            for beat in range(4):  # triplets
                for j in range(3):
                    m = tones[(beat + j) % 4]
                    S.put('arpL' if j % 2 == 0 else 'arpR', chip(m, BEAT / 3 * 0.85, 0.25) * 0.045,
                          s0 + beat * 4 + j * 4 / 3)
        elif sec == 'calm':
            for st in range(0, 16, 4):  # a slow bell arpeggio
                S.put('bell', A.bell(midi(tones[(st // 4) % 4] + 12), 1.2, 0.04), s0 + st)
        elif sec == 'chase':
            up = 24 if flip else 12
            for j in range(16):
                S.put('arpL' if j % 2 == 0 else 'arpR', chip(tones[j % 4] + up, STEP * 0.5) * 0.028, s0 + j)
        if flip and sec in ('power', 'final', 'chase'):
            for j in range(16):
                S.put('spark', chip(tones[(j * 3) % 4] + 24, STEP * 0.4) * 0.016, s0 + j + 0.5)

        # ---- chords: strings and stabs ------------------------------------------
        if sec in ('theme', 'glitch', 'power', 'final', 'outro'):
            S.chords(ch, s0, 16, 0.05 if sec in ('theme', 'glitch') else 0.065, 0.12)
        elif sec == 'march':
            S.chords(ch, s0, 16, 0.075, 0.3)
        elif sec == 'calm':
            S.chords(ch, s0, 16, 0.11, 0.5)
        elif sec == 'chase' and i >= 4:
            S.chords(ch, s0, 16, 0.05, 0.1)
        if sec in ('power', 'final', 'chase'):
            for st in (2, 6, 10, 14):
                S.put('stabL', stab(ch, 55, 1.5, 0.997) * 0.1, s0 + st, 0.01)
                S.put('stabR', stab(ch, 55, 1.5, 1.003) * 0.1, s0 + st, 0.01)

        # ---- the tunes ------------------------------------------------------------
        if sec == 'theme':
            prev = S.melody('lead', THEME[i], s0, 0.21, echo=flip or i >= 8, prev=prev)
            if flip or i >= 8:
                S.counterline(ch, THEME[i], s0, 0.06)
        elif sec == 'glitch':
            prev = S.melody('lead', THEME[i], s0, 0.21, octave=True, prev=prev)
        elif sec == 'power':
            prev = S.melody('lead', THEME[i], s0, 0.22, octave=True, echo=True, prev=prev)
            S.counterline(ch, THEME[i], s0, 0.075)
        elif sec == 'final':
            prev = S.melody('lead', THEME[i], s0, 0.23, octave=True, echo=True, shift=2, prev=prev)
            S.counterline(ch, [(None if m is None else m + 2, d, fl) for m, d, fl in THEME[i]], s0, 0.08)
        elif sec == 'march':
            prev = S.melody('lead', MARCH[i], s0, 0.19, prev=prev)
            if flip:
                S.melody('lead', MARCH[i], s0, 0.07, lead2)
        elif sec == 'calm':
            # the theme on a bell, half speed: one bar of the tune every two bars
            if i % 2 == 0:
                for m, d, pos, fl in with_pos(THEME[i // 2]):
                    if m is not None:
                        v = 0.12 + 0.03 * (pos % 8 == 0)
                        S.put('bell', A.bell(midi(m), max(0.8, d * 2 * STEP * 1.6), v), s0 + pos * 2, 0.03)
            if i == 6:
                S.put('fx', riser(BAR * 2, 0.3), s0)
            prev = None
        elif sec == 'chase':
            q = i // 4
            if q == 0:
                S.melody('lead', RUNS[i % 4], s0, 0.14, runner)
            elif q == 1:
                S.melody('lead', RUNS[i % 4], s0, 0.09, runner)
                prev = S.melody('lead', CHASE_BRASS[i % 4], s0, 0.2, prev=prev)
                S.counterline(ch, CHASE_BRASS[i % 4], s0, 0.06)
            elif q == 2:
                prev = S.melody('lead', CHASE_CALL[i % 4], s0, 0.22, octave=True, echo=True, prev=prev)
            else:
                prev = S.melody('lead', CHASE_UNISON[i % 4], s0, 0.22, octave=True, prev=prev)
                for m, d, pos, fl in with_pos(CHASE_UNISON[i % 4]):
                    if m is not None:
                        S.put('bass', bass(m - 36, d) * 0.5, s0 + pos)  # (the bass in unison too)
        elif sec == 'outro':
            prev = S.melody('lead', OUTRO[i], s0, 0.22, octave=True, echo=True, prev=prev)

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

    lead = A.shape(get('lead'), hi=7000 if flip else 6400, loop=True)
    counter = A.shape(get('counter'), hi=4000, loop=True)
    echoR = A.shape(get('echoR'), hi=3200, loop=True)
    echoL = A.shape(get('echoL'), hi=2600, loop=True)
    arpL = A.shape(get('arpL'), hi=6000, loop=True)
    arpR = A.shape(get('arpR'), hi=6000, loop=True)
    spark = A.shape(get('spark'), hi=9000, loop=True)
    bass_b = A.shape(get('bass'), hi=1500, lo=30, loop=True)
    strs = A.shape(get('str'), hi=2800, lo=90, loop=True)
    bell, hit, cym, snare_b, toms, fx = (get(k) for k in ('bell', 'hit', 'cym', 'snare', 'toms', 'fx'))
    stabL = A.shape(get('stabL'), hi=4200, loop=True)
    stabR = A.shape(get('stabR'), hi=4200, loop=True)
    hats = A.shape(get('hats'), hi=11000, loop=True)
    kick_b = A.shape(get('kick'), lo=28, loop=True)

    def pan(x, p):
        a = (p + 1) * np.pi / 4
        return x * np.cos(a) * np.sqrt(2), x * np.sin(a) * np.sqrt(2)

    L = np.zeros(N)
    R = np.zeros(N)
    # the strings wide: a little more of the high voices left, the low right
    for x, p in ((lead, 0), (counter, -0.3), (echoR, 0.55), (echoL, -0.55), (arpL, -0.5), (arpR, 0.5),
                 (spark, 0.25), (bass_b, 0), (strs, 0.0), (bell, -0.15), (stabL, -0.6), (stabR, 0.6),
                 (hit, 0), (hats, 0.2), (cym, -0.15), (kick_b, 0), (snare_b, 0.05), (toms, -0.1), (fx, 0)):
        l, r = pan(x, p)
        L += l
        R += r
    # a hall round the tune, the voices, the strings, the bells and the hits
    send = lead * 0.6 + counter + arpL + arpR + strs * 0.8 + bell * 1.5 + stabL + stabR + snare_b * 0.4 + hit * 0.5
    L += room(send, 1.9, 11) * 0.26
    R += room(send, 1.9, 12) * 0.26

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
    ir[:n_of(0.018)] = 0
    ir = A.shape(ir, hi=4200)[:n_ir]
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
