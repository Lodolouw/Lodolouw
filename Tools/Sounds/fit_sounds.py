"""FIT A BOSS'S SOUNDS TO HIS FIGHT: your own sound files, each made the
length the fight needs - a long one cut and faded out, a short one looped
(each repeat blended into the next) until it's long enough. The engine hum
is made into a seamless loop. Every one is levelled to the same loudness.

    put your files in Tools/Sounds/in/Revvington/ (any of .wav .mp3 .ogg
    .m4a .flac), named like the sound: "Engine Rev.wav", "big_honk.mp3",
    "BigHonk.ogg" all mean Big Honk (case, spaces, _ and - don't matter)

    python3 fit_sounds.py                 -> every Revvington sound found
    python3 fit_sounds.py Honk Rev        ...only the ones starting with those
    python3 fit_sounds.py --list          the sounds and lengths it wants

They come out in out/bosses/<Name>.ogg (and .wav), where
Tools/Upload/upload_assets.bat uploads them; SoundLoader then puts each in
SoundService under its name ("Big_Honk" -> "Big Honk"), which is what
Revvington plays (Config.Bosses[5].Sounds). Needs numpy and imageio-ffmpeg.
"""
import os
import re
import subprocess
import sys
import wave

import numpy as np

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out', 'bosses')

# name -> (seconds, how), from when each plays in his fight
# (ReplicatedStorage/BossBodies/Revvington.lua and his Config entry).
# how: 'once' = cut/loop to the length; 'loop' = a seamless loop (the engine)
BOSSES = {
    'Revvington': {
        'Revvington Wake': (1.2, 'once'),     # "Ka-VROOM!", 0.2 s before GO!
        'Start Beep': (0.35, 'once'),         # each start light, about 1 s apart
        'Start Go': (0.9, 'once'),            # GO!
        'Engine Rev': (0.9, 'once'),          # revving in a move's warning (0.7-1.0 s)
        'Revvington Charge': (1.4, 'once'),   # the charge's roar, down the lane and past you
        'Tire Skid': (1.2, 'once'),           # braking and skidding round
        'Revvington Crash': (1.0, 'once'),    # into the tyre wall
        'Tire Screech': (0.6, 'once'),        # the tail whip (0.35 s whip)
        'Suspension Slam': (0.7, 'once'),     # the wheelie coming down
        'Big Honk': (0.7, 'once'),            # HONK!! (also twice, 0.3 s apart, when he taunts)
        'Exhaust Backfire': (0.8, 'once'),    # BANG!
        'Car Bump': (0.45, 'once'),           # the side bump
        'Donut Screech': (2.2, 'once'),       # donuts last 2.2 s
        'Fire Whoosh': (1.5, 'once'),         # the burnout ring's flames catching
        'Revvington Turbo': (1.8, 'once'),    # TURBO! (the nitro blast)
        'Revvington Sputter': (2.0, 'once'),  # his engine giving out, before FINISH!
        'Checkered Flag': (1.6, 'once'),      # FINISH!
        'Crowd Cheer': (3.0, 'once'),         # the fans
        'Revvington Engine': (2.0, 'loop'),   # the hum under the whole fight (pitch follows his speed)
    },
}

EXTS = ('.wav', '.mp3', '.ogg', '.m4a', '.flac', '.aac', '.wma')
BLEND = 0.08    # seconds each loop repeat is blended into the next
FADE_MAX = 0.15  # the fade at the end of a cut sound (at most)
PEAK = 0.85


def key(s):
    return re.sub(r'[\s_\-]', '', s).lower()


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def load(path):
    raw = subprocess.run([ffmpeg(), '-loglevel', 'error', '-i', path, '-f', 'f32le', '-ac', '1',
                          '-ar', str(RATE), '-'], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim_silence(x, floor=0.01):
    """drop the quiet bits at the start and end (so loops don't stutter)"""
    loud = np.where(np.abs(x) > floor * max(1e-9, np.max(np.abs(x))))[0]
    if len(loud) == 0:
        return x
    return x[max(0, loud[0] - int(0.003 * RATE)):loud[-1] + 1]


def blend(a, b, n):
    """b joined onto a, the last n samples of a fading into the first n of b"""
    n = min(n, len(a), len(b))
    if n <= 0:
        return np.concatenate([a, b])
    t = np.linspace(0, 1, n)
    # equal-power, so the join doesn't dip
    mid = a[-n:] * np.cos(t * np.pi / 2) + b[:n] * np.sin(t * np.pi / 2)
    return np.concatenate([a[:-n], mid, b[n:]])


def fit_once(x, seconds):
    want = int(seconds * RATE)
    if len(x) >= want:
        x = x[:want].copy()
        how = 'cut'
    else:
        n = int(BLEND * RATE)
        n = min(n, len(x) // 3)
        out = x.copy()
        while len(out) < want:
            out = blend(out, x, n)
        x = out[:want].copy()
        how = 'looped'
    fade = min(int(FADE_MAX * RATE), len(x) // 4)
    if fade > 0:
        x[-fade:] *= np.linspace(1, 0, fade) ** 2
    return x, how


def fit_loop(x, seconds):
    """a seamless loop: the end blends round into the start"""
    n = min(int(0.12 * RATE), len(x) // 4)
    longer, how = (x, 'cut') if len(x) >= int(seconds * RATE) + n else (None, 'looped')
    if longer is None:
        m = min(int(BLEND * RATE), len(x) // 3)
        longer = x.copy()
        while len(longer) < int(seconds * RATE) + n:
            longer = blend(longer, x, m)
    y = longer[:int(seconds * RATE) + n].copy()
    t = np.linspace(0, 1, n)
    head = y[:n] * np.sin(t * np.pi / 2) + y[-n:] * np.cos(t * np.pi / 2)
    return np.concatenate([head, y[n:-n]]), how + ', seamless'


def save(name, x):
    x = x / max(1e-9, np.max(np.abs(x))) * PEAK
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name.replace(' ', '_'))
    with wave.open(path + '.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run([ffmpeg(), '-y', '-loglevel', 'error', '-i', path + '.wav',
                    '-c:a', 'libvorbis', '-q:a', '6', path + '.ogg'], check=True)
    return path + '.ogg'


def main(argv):
    boss = 'Revvington'
    sounds = BOSSES[boss]
    if '--list' in argv:
        for name, (sec, how) in sounds.items():
            print(f'  {name:<22} {sec:>4.2f} s{"  (seamless loop)" if how == "loop" else ""}')
        return
    only = [a.lower() for a in argv if not a.startswith('-')]
    folder = os.path.join(HERE, 'in', boss)
    files = {}
    if os.path.isdir(folder):
        for f in os.listdir(folder):
            stem, ext = os.path.splitext(f)
            if ext.lower() in EXTS:
                files[key(stem)] = os.path.join(folder, f)
    missing = []
    for name, (sec, how) in sounds.items():
        if only and not any(key(name).startswith(key(o)) for o in only):
            continue
        path = files.pop(key(name), None)
        if not path:
            missing.append(name)
            continue
        x = trim_silence(load(path))
        was = len(x) / RATE
        y, did = fit_loop(x, sec) if how == 'loop' else fit_once(x, sec)
        out = save(name, y)
        print(f'  {name:<22} {was:5.2f} s -> {len(y) / RATE:4.2f} s  ({did})  {os.path.relpath(out, HERE)}')
    if missing:
        print('\nnot found in', os.path.relpath(folder, HERE) + ':', ', '.join(missing))
    if files and not only:
        print('\nfiles that match no sound (check the name):', ', '.join(os.path.basename(p) for p in files.values()))


if __name__ == '__main__':
    main(sys.argv[1:])
