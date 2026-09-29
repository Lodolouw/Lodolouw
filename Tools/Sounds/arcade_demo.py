"""A listen to THE ARCADE's music, put together the way the game plays it
(the same timings as StarterPlayerScripts/ArcadeClient): the song, then four
spins - a Rare, a Legendary, a Mythic and a Secret - each with the song
speeding up, the drum roll, the ticks, the silence (the heartbeat before
the big ones) and the landing, and the song coming back after.

    python3 arcade_sfx.py      (first: makes the sounds)
    python3 arcade_demo.py     -> Docs/arcade_sounds.mp3

(Roblox speeds a sound up by playing it faster, which also raises its pitch -
so does this.)
"""
import os
import subprocess
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SOUNDS = os.path.join(HERE, 'out', 'arcade')
RATE = 44100

# ArcadeClient's numbers
SPIN_SPEED = 1.25
SONG_VOLUME = 0.6
RISER_LENGTH, QUIET, HEART, SECRET_LEAD = 3.3, 0.45, 1.6, 0.6
LAND = {'Rare': 'Win_Rare', 'Legendary': 'Jackpot_Legendary', 'Mythic': 'Jackpot_Mythic', 'Secret': 'Jackpot_Secret'}
LAND_VOLUME = {'Common': 0.7, 'Rare': 0.8, 'Epic': 0.9, 'Legendary': 1, 'Mythic': 1, 'Secret': 1}
LAND_HOLD = {'Common': 0.7, 'Rare': 1.2, 'Epic': 1.8, 'Legendary': 3.6, 'Mythic': 4.4, 'Secret': 5.8}
TILE, GAP = 150, 12


def load(name):
    with wave.open(os.path.join(SOUNDS, name + '.wav')) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32767


def main():
    song = load('Arcade_Theme')
    parts = {n: load(n) for n in ['Spin_Riser', 'Heartbeat', 'Token_Clunk', 'Roll_Tick'] + list(LAND.values())}
    total = 70.0
    n = int(total * RATE)
    out = np.zeros(n)

    def put(name, at, volume=1.0, start=0.0, pitch=1.0, stop=None):
        x = parts[name][int(start * RATE):]
        if pitch != 1.0:
            idx = np.arange(0, len(x) - 1, pitch)
            x = np.interp(idx, np.arange(len(x)), x)
        if stop is not None:
            keep = int(max(0.0, stop - at) * RATE)
            x = x[:keep].copy()
            fade = min(len(x), int(0.06 * RATE))
            if fade:
                x[-fade:] *= np.linspace(1, 0, fade)
        i = int(at * RATE)
        k = min(len(x), n - i)
        if k > 0:
            out[i:i + k] += x[:k] * volume * 0.6  # (SoundLoader's Volume)

    # the spins: (when the button's pressed, the rarity, ten at once?)
    spins = [(6.0, 'Rare'), (19.0, 'Legendary'), (33.0, 'Mythic'), (48.0, 'Secret')]
    # the song's loudness and speed, moment by moment (as ArcadeClient's Heartbeat loop)
    dt = 1 / 60
    level, speed = 0.0, 1.0
    steps = int(total / dt)
    lv = np.zeros(steps)
    sp = np.zeros(steps)
    events = []
    for t0, rarity in spins:
        land = t0 + 0.35 + 3.8
        big = rarity in ('Legendary', 'Mythic', 'Secret')
        quiet = HEART if big else QUIET
        events.append((t0, land, rarity, big, quiet))
        put('Token_Clunk', t0)
        run = 3.8 - quiet
        put('Spin_Riser', t0 + 0.35, 0.7, max(0.0, RISER_LENGTH - run), stop=land - quiet + 0.06)
        if big:
            put('Heartbeat', land - HEART, 1.0)
        lead = SECRET_LEAD if rarity == 'Secret' else 0.0
        put(LAND[rarity], land - lead, LAND_VOLUME[rarity])
        # the ticks: a tile passing under the marker (the strip eases out: 1 - (1 - u)^4)
        centre_off = 2 * (TILE + GAP) + TILE / 2
        span = (40 - 1) * (TILE + GAP) + TILE / 2 - centre_off
        last = None
        for j in range(int(3.8 / dt) + 1):
            u = min(1.0, j * dt / 3.8)
            k = 1 - (1 - u) ** 4
            under = int((centre_off + span * k) // (TILE + GAP)) + 1
            if under != last:
                last = under
                put('Roll_Tick', t0 + 0.35 + j * dt, 0.5, pitch=0.9 + 0.4 * u)
    for s in range(steps):
        t = s * dt
        want = t < total - 3
        spinning = cut = False
        quiet_until = 0
        for t0, land, rarity, big, quiet in events:
            if t0 + 0.35 <= t < land:
                spinning = True
                cut = t >= land - quiet
            if land <= t < land + LAND_HOLD[rarity]:
                quiet_until = land + LAND_HOLD[rarity]
        silent = cut or t < quiet_until
        goal = 1.0 if (want and not silent) else 0.0
        rate = 1.2 if goal > level else (12 if silent else 1.6)
        level += (goal - level) * min(1, dt * rate)
        if silent:
            speed = 1.0
        else:
            fast = SPIN_SPEED if spinning else 1.0
            speed += (fast - speed) * min(1, dt * 3)
        lv[s], sp[s] = level, speed
    # the song, read faster or slower as its speed changes
    tt = np.arange(n) / RATE
    level_s = np.interp(tt, np.arange(steps) * dt, lv)
    speed_s = np.interp(tt, np.arange(steps) * dt, sp)
    pos = np.cumsum(speed_s) % len(song)
    music = np.interp(pos, np.arange(len(song)), song)
    out += music * level_s * SONG_VOLUME * 0.6 * 0.7  # (its Volume, SoundLoader's, the music group's)
    out = out / max(1e-6, np.max(np.abs(out))) * 0.9
    wav = os.path.join(HERE, 'out', 'arcade_demo.wav')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((out * 32767).astype(np.int16).tobytes())
    mp3 = os.path.join(ROOT, 'Docs', 'arcade_sounds.mp3')
    import imageio_ffmpeg
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libmp3lame', '-b:a', '112k', mp3], check=True)
    print('saved', os.path.relpath(mp3, ROOT))
    for t0, land, rarity, big, quiet in events:
        print('  %5.1f s  a %s spin (it lands at %.1f s)' % (t0, rarity, land))


if __name__ == '__main__':
    main()
