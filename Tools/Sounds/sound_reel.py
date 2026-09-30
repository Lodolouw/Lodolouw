"""A LISTEN to a pack's weapon sounds: each one played in turn, its name, what
it's for and its waveform on screen - a little video to look through before
uploading them.

    python3 weapon_sfx.py Knight Speedway   (first: makes the sounds)
    python3 sound_reel.py Knight Speedway   -> Docs/sounds/knight_speedway_sounds.mp4

(It plays the .ogg files, the ones that get uploaded. Needs imageio-ffmpeg,
like make_sfx.py.)
"""
import os
import subprocess
import sys
import tempfile

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SOUNDS = os.path.join(HERE, 'out', 'weapons')
sys.path.insert(0, HERE)
from weapon_sfx import PACKS  # noqa: E402

RATE = 44100
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
W, H = 1280, 720
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
PLAIN = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BG, INK, DIM = (26, 24, 40), (255, 255, 255), (150, 146, 178)
LOOK = {
    'Knight': ('KNIGHT PACK - BURROWMORE', (254, 174, 52)),
    'Speedway': ('SPEEDWAY PACK - REVVINGTON', (247, 118, 34)),
}
# where each is heard in the game
FOR = {
    'Shovel Swish': 'a swing: the Knight Epic and Legendary',
    'Dirt Splat': 'a dirt clod landing',
    'Clang Hit': 'a hit: the Knight Epic to Mythic',
    'Chain Swish': 'a swing: Anchor Fists (Mythic)',
    'Gold Swing': 'a swing: No Quarter (Secret)',
    'Gold Chop': 'a hit: No Quarter',
    'Coin Spill': "No Quarter's coins landing",
    'Spade Dig': 'Shovel Hammer - Dig Slam',
    'Treasure Glint': "Relic Daggers - Treasure Eye; Burrowmore's visor",
    'Coin Ding': "Relic Daggers - a crit's coins",
    'Dirt Spin': 'Spade Scythe - Dirt Spin',
    'Pogo Boing': 'Honour Blade - BOING!',
    'Pogo Clang': 'Honour Blade - each plunge',
    'Anchor Hurl': 'Anchor Fists - the anchor thrown',
    'Chain Reel': 'Anchor Fists - reeled in',
    'Anchor Slam': 'Anchor Fists - the slam',
    'Plate Crack': 'No Quarter - the armour cracks; the gold crack',
    'Meteor Fall': 'No Quarter - the meteor falling',
    'Meteor Impact': 'No Quarter - the meteor landing',
    'Tyre Swish': 'a swing: the Speedway Epic and Legendary',
    'Spark Skitter': 'sparks skittering on the floor',
    'Spark Hit': 'a hit: the Speedway Epic and Legendary',
    'Flame Swish': 'a swing: Wheelie Wrecker (Mythic)',
    'Flame Burst': 'fire landing; a hit: Wheelie Wrecker',
    'Victory Swing': 'a swing: Victory Lap (Secret)',
    'Checker Pop': 'confetti; a hit: Victory Lap',
    'Nitro Rev': 'Tyre Scythe - Burnout',
    'Tyre Screech': 'Burnout; Pit Stop Sabre - Skid Spin',
    'Nitro Boost': 'Nitro Katana - Nitro',
    'Piston Pump': 'Piston Punchers - the pump',
    'Piston Punch': 'Piston Punchers - the punch',
    'Tyre Bounce': "Pit Stop Sabre - the spare tyres bouncing",
    'Wheel Roll': 'Wheelie Wrecker - the flaming wheel',
    'Wheelie Slam': 'Wheelie Wrecker - the slam',
    'Race Go': 'Victory Lap - GO!',
    'Finish Line': 'Victory Lap - FINISH!; the chequered flag',
    'Horn Honk': "Victory Lap - Revvington's eyes; the finish",
}


def load(name):
    """an .ogg as mono floats at RATE"""
    path = os.path.join(SOUNDS, name.replace(' ', '_') + '.ogg')
    raw = subprocess.run([FFMPEG, '-v', 'quiet', '-i', path, '-f', 's16le', '-ac', '1', '-ar', str(RATE), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(float) / 32767


def card(title, color, name=None, note=None, wave=None):
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 12), fill=color)
    d.text((W // 2, 70), title, font=ImageFont.truetype(BOLD, 34), fill=color, anchor='mm')
    if name:
        d.text((W // 2, 250), name.upper(), font=ImageFont.truetype(BOLD, 78), fill=INK, anchor='mm')
        d.text((W // 2, 330), note or '', font=ImageFont.truetype(PLAIN, 30), fill=DIM, anchor='mm')
    if wave is not None and len(wave):
        top, bot, x0, x1 = 420, 640, 100, W - 100
        mid = (top + bot) // 2
        cols = x1 - x0
        step = max(1, len(wave) // cols)
        for i in range(cols):
            chunk = wave[i * step:(i + 1) * step]
            if not len(chunk):
                break
            a = float(np.max(np.abs(chunk)))
            h = max(1, int(a * (bot - top) / 2))
            d.line((x0 + i, mid - h, x0 + i, mid + h), fill=color)
        d.text((x1, bot + 30), '%.2f s' % (len(wave) / RATE), font=ImageFont.truetype(PLAIN, 22), fill=DIM, anchor='rm')
    return img


def main():
    want = sys.argv[1:] or list(PACKS)
    tmp = tempfile.mkdtemp()
    audio, lines, n = [], [], 0

    def add(img, seconds, sound=None):
        nonlocal n
        n += 1
        path = os.path.join(tmp, '%03d.png' % n)
        img.save(path)
        lines.append("file '%s'\nduration %.3f\n" % (path, seconds))
        k = int(round(seconds * RATE))
        clip = np.zeros(k)
        if sound is not None:
            s = sound[:k - int(0.25 * RATE)]
            clip[int(0.25 * RATE):int(0.25 * RATE) + len(s)] = s
        audio.append(clip)
        return path

    for pack in want:
        title, color = LOOK.get(pack, (pack.upper(), (200, 240, 255)))
        add(card(title, color, name=pack + ' sounds', note='%d of them' % len(PACKS[pack])), 1.6)
        for name in PACKS[pack]:
            s = load(name)
            add(card(title, color, name, FOR.get(name, ''), s), 0.25 + len(s) / RATE + 0.55, s)
    last = add(card('', BG), 0.5)
    lines.append("file '%s'\n" % last)  # (the concat list needs its last picture twice)
    pcm = os.path.join(tmp, 'audio.raw')
    (np.clip(np.concatenate(audio), -1, 1) * 32767).astype(np.int16).tofile(pcm)
    lst = os.path.join(tmp, 'list.txt')
    with open(lst, 'w') as f:
        f.writelines(lines)
    out = os.path.join(ROOT, 'Docs', 'sounds', '_'.join(p.lower() for p in want) + '_sounds.mp4')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst,
                    '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', pcm,
                    '-vf', 'fps=15,format=yuv420p', '-c:v', 'libx264', '-crf', '28', '-c:a', 'aac', '-b:a', '128k',
                    '-shortest', out], check=True)
    print('saved', os.path.relpath(out, ROOT))


if __name__ == '__main__':
    main()
