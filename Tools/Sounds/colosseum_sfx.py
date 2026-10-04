"""THE COLOSSEUM'S SOUNDS, made from code (so they're ours, not someone
else's private uploads - Roblox plays those silently):

  * "Colosseum Theme" - the arena's song: an original, heroic battle march in
    D major, 140 beats a minute, 48 bars (82.29 s) that loop with no seam.
    The singing 8-bit brass of the Spire's songs (music_gridlock.py's
    instruments) over strings, a running bass and arena drums - and in the
    middle the crowd joins in: STOMP STOMP CLAP.

        bars  1-4   FANFARE    brass calls over orchestra hits and a tom roll
        bars  5-20  THEME      the tune: a bold leap up, a strut back down
        bars 21-28  THE CROWD  half-time: stomp stomp clap, low brass, the
                               tune's answer climbing to the top
        bars 29-44  THEME, FULL  octaves, echoes, the counter-voice, stabs
        bars 45-48  TURNAROUND falling back into the fanfare

  * "Victory Fanfare" - the sting when you beat a boss (every Spire boss and
    the Straw King play it): a triplet call, a climb, and a huge held chord
    with a timpani roll, a crash and a long hall tail. 5.5 s.

  * "Straw King Stomp" - the Giant Straw King landing from a leap: a deep
    boom you feel, a thud, the crunch of straw and the patter of bits
    falling back down. 1.4 s.

    python3 colosseum_sfx.py          -> out/colosseum/<name>.ogg (and .wav)
    python3 colosseum_sfx.py --demo   ...and Docs/music/colosseum_sounds.mp3

Tools/Upload/upload_assets.bat uploads out/colosseum/*.ogg; SoundLoader puts
them in SoundService as "Colosseum Theme", "Victory Fanfare" and "Straw King
Stomp" - the first names on Config's lists (Colosseum.Music, King.Sounds,
every boss's VictorySound), ahead of the old private ones.
"""
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import arcade_sfx as A  # noqa: E402
import music_gridlock as G  # noqa: E402  (the instruments; its timing is set below)
from make_sfx import RATE  # noqa: E402

OUT = os.path.join(HERE, 'out', 'colosseum')
BPM = 140
BEAT = 60 / BPM
STEP = BEAT / 4
BAR = BEAT * 4
BARS = 48
N = int(round(BARS * BAR * RATE))  # 3,628,800 samples: 82.286 s exactly

D_MAJOR = {2, 4, 6, 7, 9, 11, 1}


def use_timing(step, n):
    """the borrowed instruments read their timing from music_gridlock"""
    G.STEP, G.BEAT, G.BAR, G.N = step, step * 4, step * 16, n
    G.D_MINOR = D_MAJOR  # (trills and grace notes: the next note up the scale)


tune = G.tune
with_pos = G.with_pos
chord_notes = G.chord_notes
bass_root = G.bass_root
n_of = G.n_of
midi = G.midi

# ----------------------------------------------------------------------
# the tunes (all original)
# ----------------------------------------------------------------------
FANFARE_CH = ['D', 'C', 'G', 'A']
FANFARE = [tune(t) for t in [
    'A4:2 A4:1 A4:1 /D5:6 r:6',
    'G4:2 G4:1 G4:1 /C5:6 r:6',
    'B4:2 B4:1 B4:1 D5:4 /G5:4 r:4',
    '~A5:8 E5:1 F#5:1 G5:1 G#5:1 A5:4',
]]
FANFARE_HITS = [[0, 6], [0, 6], [0, 4, 8], [0]]

THEME_CH = ['D', 'C', 'G', 'D', 'Bm', 'G', 'A', 'A', 'D', 'C', 'G', 'D', 'G', 'A', 'D', 'D']
THEME = [tune(t) for t in [
    # the call: bold, up the chord and a strut back down
    'D5:4 A4:2 D5:2 /F#5:4 E5:2 D5:2',
    'E5:6 /G5:2 E5:4 C5:4',
    'D5:4 B4:2 D5:2 /G5:4 F#5:2 G5:2',
    '~A5:12 F#5:2 G5:2',
    'B5:4 A5:2 F#5:2 D5:4 F#5:4',
    'G5:4 F#5:2 E5:2 D5:4 B4:4',
    'C#5:4 E5:2 A5:2 G5:4 E5:4',
    'A5:8 B5:2 A5:2 G5:2 E5:2',
    # the answer: up an octave, to the top and home
    'F#5:4 A5:2 D6:2 /F#6:6 E6:2',
    'E6:4 D6:2 C6:2 G5:4 E5:4',
    'G5:4 B5:2 D6:2 /G6:4 F#6:2 E6:2',
    'F#6:8 E6:2 D6:2 A5:4',
    'B5:4 C#6:2 D6:2 E6:4 D6:2 B5:2',
    'C#6:4 B5:2 A5:2 /E6:4 C#6:4',
    '*E6:4 D6:4 A5:4 F#5:4',
    '~D6:12 r:4',
]]
CROWD_CH = ['Bm', 'G', 'D', 'A', 'Bm', 'G', 'Em', 'A']
CROWD = [tune(t) for t in [
    'B4:6 C#5:2 D5:4 F#5:4',
    'G5:6 F#5:2 D5:4 B4:4',
    'A4:6 B4:2 D5:4 F#5:4',
    '/E5:12 r:4',
    'B4:6 C#5:2 D5:4 F#5:4',
    'G5:6 A5:2 B5:4 D6:4',
    '/E6:6 D6:2 B5:4 G5:4',
    'C#6:4 E6:4 A5:4 C#6:2 E6:2',
]]
OUTRO_CH = ['G', 'A', 'Bm', 'A7']
OUTRO = [tune(t) for t in [
    'D6:4 B5:4 G5:4 B5:4',
    'C#6:4 A5:4 E5:4 A5:4',
    'D6:4 F#6:4 B5:4 D6:4',
    '~E6:8 C#6:4 A5:4',
]]

PLAN = ([('fanfare', c, i) for i, c in enumerate(FANFARE_CH)]
        + [('theme', c, i) for i, c in enumerate(THEME_CH)]
        + [('crowd', c, i) for i, c in enumerate(CROWD_CH)]
        + [('full', c, i) for i, c in enumerate(THEME_CH)]
        + [('outro', c, i) for i, c in enumerate(OUTRO_CH)])
assert len(PLAN) == BARS


# ----------------------------------------------------------------------
# arena percussion
# ----------------------------------------------------------------------
def clap(vol=1.0, seed=0):
    """a crowd's clap: a few hands, not quite together"""
    rng = np.random.default_rng(seed)
    n = n_of(0.22)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for k in range(5):
        d = n_of(rng.uniform(0, 0.012))
        burst = A.shape(rng.uniform(-1, 1, n), hi=rng.uniform(2600, 4200), lo=700)[:n]
        e = np.exp(-np.clip(t - d / RATE, 0, None) / rng.uniform(0.025, 0.05)) * (t >= d / RATE)
        x += burst * e * rng.uniform(0.6, 1.0)
    return x / 3 * vol


def stomp(vol=1.0):
    """a crowd's stomp on wooden stands: low, round, a little hollow"""
    n = n_of(0.3)
    t = np.arange(n) / RATE
    f = 70 * (1 + 1.2 * np.exp(-t / 0.02))
    body = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.09)
    wood = A.shape(A.noise(n), hi=900, lo=120)[:n] * np.exp(-t / 0.03) * 0.5
    return np.tanh(1.5 * (body + wood)) * vol


def drums(S, sec, i, s0):
    rng = S.rng
    if sec == 'fanfare':
        for st in (0, 8):
            S.put('kick', G.kick(0.8), s0 + st)
        if i == 3:  # a tom roll into the theme
            for j, f in enumerate([180, 170, 160, 150, 140, 130, 120, 110] * 2):
                S.put('toms', G.tom(f, 0.25 + 0.03 * j), s0 + j, 0.02)
        else:
            S.put('snare', G.snare(0.35, 0.2), s0 + 12)
        return
    if sec == 'crowd':
        # STOMP STOMP CLAP, twice a bar - the whole arena
        for half in (0, 8):
            S.put('stomp', stomp(0.75), s0 + half, 0.03)
            S.put('stomp', stomp(0.7), s0 + half + 2, 0.03)
            S.put('clap', clap(0.8, seed=bar_seed(s0, half)), s0 + half + 4, 0.02)
            S.put('kick', G.kick(0.55), s0 + half)
            S.put('kick', G.kick(0.5), s0 + half + 2)
        for st in range(0, 16, 4):
            S.put('hats', A.hat(0.12, 0.05), s0 + st + 2, 0.02)
        if i == 7:  # snare build into the full theme
            for j in range(8):
                S.put('snare', G.snare(0.12 + 0.04 * j, 0.06), s0 + 8 + j, 0.01)
        return
    full = sec in ('full', 'outro')
    # the march: kick on 1 and 3 (and a push before 3), snare on 2 and 4
    for st in (0, 8):
        S.put('kick', G.kick(0.85), s0 + st, 0.01)
    S.put('kick', G.kick(0.5), s0 + 6, 0.01)
    if full:
        S.put('kick', G.kick(0.45), s0 + 14, 0.01)
    for st in (4, 12):
        S.put('snare', G.snare(0.42, 0.16), s0 + st, 0.01)
    if rng.random() < 0.5:
        S.put('snare', G.snare(0.08, 0.05), s0 + 15, 0.02)  # a ghost note
    for st in range(0, 16, 1 if full else 2):
        v = (0.12 if st % 4 == 2 else 0.07) if full else 0.1
        S.put('hats', A.hat(v * rng.uniform(0.85, 1.1), 0.03), s0 + st, 0.02)
    if i % 4 == 3:  # a fill on the 4th bar of each phrase
        for j, f in enumerate((200, 170, 145, 120)):
            S.put('toms', G.tom(f, 0.3), s0 + 12 + j, 0.02)
    if i == 0:
        S.put('cym', A.crash(0.2, 1.8), s0)


def bar_seed(s0, half):
    return int(s0 * 3 + half)


# ----------------------------------------------------------------------
# the song
# ----------------------------------------------------------------------
def theme_song():
    use_timing(STEP, N)
    S = G.Song(21)
    pump = []
    prev = None
    for bar, (sec, ch, i) in enumerate(PLAN):
        s0 = bar * 16
        drums(S, sec, i, s0)
        root = bass_root(ch)
        nxt = bass_root(PLAN[(bar + 1) % BARS][1])
        tones = chord_notes(ch, 62, 4)

        if sec == 'fanfare':
            for st in FANFARE_HITS[i]:
                S.put('hit', G.big_hit(ch, 0.4 if st == 0 else 0.28), s0 + st)
            for j in range(16):  # a low tremolo under the calls
                S.put('bass', G.bass(root, 1, 0.9) * (0.22 + 0.01 * j), s0 + j)
            S.chords(ch, s0, 16, 0.07 + 0.015 * i, 0.4)
            prev = S.melody('lead', FANFARE[i], s0, 0.2, octave=True, prev=prev)
            if i == 0:
                S.put('cym', A.crash(0.24, 2.2), s0)
            continue

        # bass
        if sec == 'crowd':
            for st, m in ((0, root), (2, root), (8, root), (10, root + 7)):
                S.put('bass', G.bass(m, 2, 0.85) * 0.75, s0 + st)
        else:
            running = sec in ('full', 'outro')
            for st in range(0, 16, 2 if running else 4):
                m = root + (12 if (st // 2) % 2 == 1 and running else 0)
                if st == 14 and nxt != root:  # walk into the next chord
                    m = nxt - 1 if nxt > root else nxt + 2
                S.put('bass', G.bass(m, 2 if running else 4, 0.8) * 0.72, s0 + st, 0.01)
            pump += [s0, s0 + 8]

        # arpeggios
        if sec in ('theme', 'full', 'outro'):
            fast = sec != 'theme'
            for j in range(16 if not fast else 32):
                m = tones[[0, 1, 2, 3, 2, 1, 0, 1][j % 8]] + (12 if fast else 0)
                S.put('arpL' if j % 2 == 0 else 'arpR', G.chip(m, STEP * (0.85 if not fast else 0.45)) * 0.04,
                      s0 + j * (1 if not fast else 0.5))
        else:  # the crowd section: slow bells on the beat
            for st in range(0, 16, 4):
                S.put('bell', A.bell(midi(tones[(st // 4) % 4] + 12), 1.0, 0.03), s0 + st)

        # chords
        S.chords(ch, s0, 16, {'theme': 0.055, 'crowd': 0.08, 'full': 0.065, 'outro': 0.07}[sec], 0.15)
        if sec in ('full', 'outro'):
            for st in (2, 6, 10, 14):
                S.put('stabL', G.stab(ch, 55, 1.5, 0.997) * 0.09, s0 + st, 0.01)
                S.put('stabR', G.stab(ch, 55, 1.5, 1.003) * 0.09, s0 + st, 0.01)

        # the tunes
        if sec == 'theme':
            prev = S.melody('lead', THEME[i], s0, 0.21, echo=i >= 8, prev=prev)
            if i >= 8:
                S.counterline(ch, THEME[i], s0, 0.055)
        elif sec == 'crowd':
            prev = S.melody('lead', CROWD[i], s0, 0.2, octave=i < 4, prev=prev)
            if i >= 4:
                S.counterline(ch, CROWD[i], s0, 0.06)
        elif sec == 'full':
            prev = S.melody('lead', THEME[i], s0, 0.22, octave=True, echo=True, prev=prev)
            S.counterline(ch, THEME[i], s0, 0.075)
        else:
            prev = S.melody('lead', OUTRO[i], s0, 0.22, octave=True, echo=True, prev=prev)

        if i == 0 and sec in ('theme', 'crowd', 'full'):
            S.put('hit', G.big_hit(ch, 0.32), s0)
    return mix(S, pump, N)


def mix(S, pump_beats, n, loop=True):
    pump = np.ones(n)
    dur = n_of(0.18)
    curve = 1 - 0.3 * (1 - np.linspace(0, 1, dur)) ** 2
    for st in pump_beats:
        i0 = n_of(st * STEP) % n
        k = min(dur, n - i0)
        pump[i0:i0 + k] = np.minimum(pump[i0:i0 + k], curve[:k])
    for name in ('stabL', 'stabR', 'arpL', 'arpR'):
        if name in S.bus:
            S.bus[name] *= pump

    def get(k):
        return S.bus.get(k, np.zeros(n))

    def sh(k, hi=None, lo=None):
        return A.shape(get(k), hi=hi, lo=lo, loop=loop)[:n]

    lead, counter = sh('lead', hi=6600), sh('counter', hi=4000)
    echoR, echoL = sh('echoR', hi=3200), sh('echoL', hi=2600)
    arpL, arpR = sh('arpL', hi=6000), sh('arpR', hi=6000)
    bass_b = sh('bass', hi=1500, lo=30)
    strs = sh('str', hi=3000, lo=90)
    stabL, stabR = sh('stabL', hi=4200), sh('stabR', hi=4200)
    hats = sh('hats', hi=11000)
    kick_b = sh('kick', lo=28)
    bell, hit, cym, snare_b, toms, clap_b, stomp_b = (get(k) for k in
                                                      ('bell', 'hit', 'cym', 'snare', 'toms', 'clap', 'stomp'))

    def pan(x, p):
        a = (p + 1) * np.pi / 4
        return x * np.cos(a) * np.sqrt(2), x * np.sin(a) * np.sqrt(2)

    L, R = np.zeros(n), np.zeros(n)
    for x, p in ((lead, 0), (counter, -0.3), (echoR, 0.55), (echoL, -0.55), (arpL, -0.5), (arpR, 0.5),
                 (bass_b, 0), (strs, 0), (bell, -0.15), (stabL, -0.6), (stabR, 0.6), (hit, 0),
                 (hats, 0.2), (cym, -0.15), (kick_b, 0), (snare_b, 0.05), (toms, -0.1),
                 (clap_b * 0.6, -0.35), (clap_b * 0.6, 0.35), (stomp_b, 0)):
        l, r = pan(x, p)
        L += l
        R += r
    # a big hall: it's an arena (the crowd's claps ring round the stands)
    send = lead * 0.6 + counter + arpL + arpR + strs * 0.8 + bell * 1.5 + stabL + stabR \
        + snare_b * 0.5 + hit * 0.5 + clap_b * 1.2 + toms * 0.4
    L += room(send, 2.3, 31, loop) * 0.28
    R += room(send, 2.3, 32, loop) * 0.28
    # (the 8-bit pulses lean to one side: take that offset out, so the master
    # has all its headroom and nothing clicks)
    L = A.shape(L, lo=24, loop=loop)[:n]
    R = A.shape(R, lo=24, loop=loop)[:n]
    return master(L, R)


def room(x, seconds, seed, loop=True):
    if loop:
        return G.room(x, seconds, seed)
    pad = n_of(seconds)  # (a one-shot: its tail mustn't wrap round to the start)
    y = G.room(np.concatenate([x, np.zeros(pad)]), seconds, seed)
    return y[:len(x)]


def master(L, R, drive=1.6, ceiling=0.9):
    peak = max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-9)
    L, R = L / peak, R / peak
    L = np.tanh(L * drive) / np.tanh(drive)
    R = np.tanh(R * drive) / np.tanh(drive)
    g = ceiling / max(np.max(np.abs(L)), np.max(np.abs(R)))
    return L * g, R * g


# ----------------------------------------------------------------------
# the victory fanfare
# ----------------------------------------------------------------------
def victory_fanfare():
    step = 60 / 120 / 4  # 120 beats a minute
    n = n_of(5.5)
    use_timing(step, n)
    S = G.Song(5)

    def put(bus, x, st):
        b = S.bus.setdefault(bus, np.zeros(n))
        i = n_of(st * step)
        if i < n:
            b[i:i + len(x)] += x[:n - i]

    # the call: a triplet, a climb... and the top held
    third = 4 / 3
    melody = [(69, third, 0), (69, third, third), (69, third, 2 * third),
              (74, 2, 4), (78, 2, 6), (81, 2, 8), (78, 1, 10), (81, 1, 11), (86, 20, 12)]
    harmony = [(66, third, 0), (66, third, third), (66, third, 2 * third),
               (69, 2, 4), (74, 2, 6), (78, 2, 8), (74, 1, 10), (78, 1, 11), (81, 20, 12)]
    for (m, d, st), (h, _, _) in zip(melody, harmony):
        held = d >= 8
        put('lead', G.brass(m, d, 1.0, None, None, 0.99 if held else 0.92) * 0.24, st)
        put('lead', G.lead2(m - 12, d, 0.9) * 0.1, st)
        put('counter', G.lead2(h, d, 0.85) * 0.12, st)
    # the band under it: a pickup, then the big D major
    put('bass', G.bass(45, 4) * 0.6, 0)
    put('bass', G.bass(50, 8, 0.85) * 0.7, 4)
    put('bass', G.bass(38, 20, 0.9) * 0.8, 12)
    put('hit', G.big_hit('D', 0.5), 12)
    put('hit', G.big_hit('A', 0.3), 4)
    put('str', G.strings([62, 66, 69, 74, 78], step * 26, 0.5) * 0.12, 10)
    for j in range(14):  # a timpani roll into the top, growing
        put('toms', A.timpani(midi(38), 0.4, 0.08 + 0.025 * j), 9 + j * 0.25)
    put('toms', A.timpani(midi(38), 1.6, 0.6), 12)
    put('cym', A.crash(0.4, 3.0), 12)
    put('snare', G.snare(0.4, 0.2), 4)
    for j in range(4):
        put('snare', G.snare(0.18 + 0.06 * j, 0.06), 10 + j * 0.5)
    put('kick', G.kick(0.9), 12)
    for st in (4, 8):
        put('kick', G.kick(0.6), st)
    # a sparkle on top as it lands
    for j, m in enumerate((86, 90, 93, 98, 102)):
        put('bell', A.bell(midi(m), 1.4, 0.035), 12.5 + j * 0.5)

    L, R = mix(S, [], n, loop=False)
    f = n_of(0.6)  # (the hall's tail fades out cleanly at the very end)
    L[-f:] *= np.linspace(1, 0, f) ** 2
    R[-f:] *= np.linspace(1, 0, f) ** 2
    return L, R


# ----------------------------------------------------------------------
# the Straw King's landing
# ----------------------------------------------------------------------
def straw_king_stomp():
    n = n_of(1.4)
    t = np.arange(n) / RATE
    rng = np.random.default_rng(4)
    x = np.zeros(n)
    # the boom you feel: a sine dropping from 90 to 28 Hz
    f = 28 + 62 * np.exp(-t / 0.08)
    boom = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.35) * np.clip(t / 0.002, 0, 1)
    x += np.tanh(2.2 * boom) * 0.9
    # the thud of a huge body on packed sand
    thud = A.shape(rng.uniform(-1, 1, n), hi=380, lo=40)[:n] * np.exp(-t / 0.07)
    x += thud * 1.4
    # the straw crunching: a crackly burst, bright but not harsh
    crunch = A.shape(rng.uniform(-1, 1, n), hi=5200, lo=1200)[:n]
    crackle = (rng.random(n) < 0.02) * rng.uniform(-1, 1, n)
    crackle = A.shape(crackle, hi=6000, lo=900)[:n] * 3
    x += (crunch * 0.35 + crackle) * np.exp(-t / 0.16) * np.clip(t / 0.004, 0, 1)
    # bits of straw and grit falling back down: a patter of little ticks
    for _ in range(26):
        at = rng.uniform(0.12, 0.85)
        i = n_of(at)
        k = n_of(0.02)
        tick = A.shape(rng.uniform(-1, 1, k), hi=rng.uniform(3000, 6000), lo=800)[:k] * np.exp(-np.arange(k) / RATE / 0.004)
        x[i:i + k] += tick[:n - i] * rng.uniform(0.05, 0.16) * (1 - at)
    # a puff of air pushed out from under him
    air = A.shape(rng.uniform(-1, 1, n), hi=700, lo=90)[:n] * np.exp(-t / 0.22) * np.clip(t / 0.01, 0, 1)
    x += air * 0.5
    # in stereo: the ticks and crunch a little wide, the low end centred
    wide = A.shape(x, lo=1200)[:n]
    L = x + 0.25 * wide
    R = x - 0.25 * wide
    L += room(x * 0.6, 0.9, 41, False) * 0.12
    R += room(x * 0.6, 0.9, 42, False) * 0.12
    f = n_of(0.15)
    L[-f:] *= np.linspace(1, 0, f)
    R[-f:] *= np.linspace(1, 0, f)
    return master(L, R, drive=1.8, ceiling=0.95)


# ----------------------------------------------------------------------
def save(name, L, R):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name.replace(' ', '_'))
    G.write_wav(path + '.wav', L, R)
    import imageio_ffmpeg
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', path + '.wav',
                    '-c:a', 'libvorbis', '-q:a', '7', path + '.ogg'], check=True)
    print('saved', path + '.ogg', f'({len(L) / RATE:.3f} s)')


def demo(parts):
    """the song twice round (the loop seam in the middle), then the sting and the stomp"""
    gap = np.zeros(n_of(0.8))
    song, sting, stomp_ = parts
    L = np.concatenate([song[0], song[0][:n_of(16 * BAR)], gap, sting[0], gap, stomp_[0], gap, stomp_[0]])
    R = np.concatenate([song[1], song[1][:n_of(16 * BAR)], gap, sting[1], gap, stomp_[1], gap, stomp_[1]])
    out_dir = os.path.join(ROOT, 'Docs', 'music')
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(out_dir, '_demo.wav')
    G.write_wav(tmp, L, R)
    import imageio_ffmpeg
    mp3 = os.path.join(out_dir, 'colosseum_sounds.mp3')
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', tmp,
                    '-c:a', 'libmp3lame', '-b:a', '192k', mp3], check=True)
    os.remove(tmp)
    print('saved', mp3)


if __name__ == '__main__':
    song = theme_song()
    save('Colosseum Theme', *song)
    sting = victory_fanfare()
    save('Victory Fanfare', *sting)
    thud = straw_king_stomp()
    save('Straw King Stomp', *thud)
    if '--demo' in sys.argv:
        demo((song, sting, thud))
