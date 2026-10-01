"""Draws swing_snaps.luau's snapshots - what flies off each weapon's swing a
moment after a cut - side by side, in the game's look (film_draw.py).

    luau swing_snaps.luau > swings.txt
    python3 render_swings.py swings.txt ../../Docs/weapons/swing_effects.png

    (other weapons, a title for them, and --behind to look from behind you,
    the way the game's camera does - the Secrets' faces look at you:)
    luau swing_snaps.luau -a BarrelDaggers,BarrelHammer,KongsCrown,DoodleKatana,CopyPasteScythe,DeleteKey > swings.txt
    python3 render_swings.py swings.txt ../../Docs/weapons/swing_effects_jungle_canvas.png "JUNGLE AND CANVAS" --behind
"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import film_draw as fd

BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
TW, TH = 640, 400
fd.W, fd.H, fd.SS = TW, TH, 2
NAMES = {
    'HonourBlade': ('Honour Blade', 'LEGENDARY', 'dirt clods and gold glints'),
    'AnchorFists': ('Anchor Fists', 'MYTHIC', 'iron chips and gold sparks'),
    'NoQuarter': ('No Quarter', 'SECRET', "coins, a crack of gold, Burrowmore's visor"),
    'PitStopSabre': ('Pit Stop Sabre', 'LEGENDARY', 'sparks and tyre smoke'),
    'WheelieWrecker': ('Wheelie Wrecker', 'MYTHIC', 'fire that lands and burns'),
    'VictoryLap': ('Victory Lap', 'SECRET', "confetti, a chequered flag, Revvington's eyes"),
    'BarrelDaggers': ('Barrel Daggers', 'LEGENDARY', 'jungle leaves and a banana now and then'),
    'BarrelHammer': ('Barrel Hammer', 'MYTHIC', 'splinters, iron chips and sawdust'),
    'KongsCrown': ("Kong's Crown", 'SECRET', "gold bananas, a lashing vine, Kongo's glare"),
    'DoodleKatana': ('Doodle Katana', 'LEGENDARY', 'ink drops that splat, scraps of paper'),
    'CopyPasteScythe': ('Copy-Paste Scythe', 'MYTHIC', 'pixels copied off the cut, blinking out'),
    'DeleteKey': ('Delete Key', 'SECRET', "glitching pixels, the arc breaking up, Scribble's face"),
}
RCOL = {'COMMON': (235, 235, 240), 'RARE': (0, 153, 219), 'EPIC': (170, 100, 255), 'LEGENDARY': (254, 174, 52),
        'MYTHIC': (255, 0, 68), 'SECRET': (255, 255, 255)}
FLOOR = {'cf': [0, -0.5, -4, 1, 0, 0, 0, 1, 0, 0, 0, 1], 's': [60, 1, 60], 'col': [88, 96, 120], 't': 0, 'm': 'Plastic',
         'sh': 'Block', 'c': 'Part'}


def load(path):
    snaps, cur = [], None
    for line in open(path):
        if line.startswith('SNAP '):
            cur = {'id': line.split()[1], 'parts': [FLOOR]}
            snaps.append(cur)
        elif line.startswith('END'):
            cur = None
        elif line.startswith('{') and cur is not None:
            cur['parts'].append(json.loads(line))
    return snaps


def main():
    behind = '--behind' in sys.argv
    argv = [a for a in sys.argv if a != '--behind']
    snaps = load(argv[1])
    cols = 3
    rows = (len(snaps) + cols - 1) // cols
    sheet = Image.new('RGB', (TW * cols, (TH + 60) * rows + 70), (24, 20, 37))
    d = ImageDraw.Draw(sheet)
    packs = argv[3] if len(argv) > 3 else 'KNIGHT AND SPEEDWAY'
    d.text((sheet.width // 2, 36), 'WHAT FLIES OFF THE SWINGS - ' + packs, font=ImageFont.truetype(BOLD, 30),
           fill=(254, 231, 97), anchor='mm')
    for i, s in enumerate(snaps):
        eye, look = np.array([7.5, 8.5, -13.0]), np.array([0.0, 1.8, -4.0])
        if behind:
            eye, look = np.array([3.5, 7.0, 9.5]), np.array([0.0, 2.2, -4.0])
        img, _ = fd.render(s['parts'], eye, look, 50)
        img = img.convert('RGB').resize((TW, TH), Image.LANCZOS)
        x, y = (i % cols) * TW, 70 + (i // cols) * (TH + 60)
        sheet.paste(img, (x, y))
        name, rarity, what = NAMES.get(s['id'], (s['id'], '', ''))
        d.text((x + TW // 2, y + TH + 18), '%s  -  %s' % (name, rarity), font=ImageFont.truetype(BOLD, 20),
               fill=RCOL.get(rarity, (255, 255, 255)), anchor='mm')
        d.text((x + TW // 2, y + TH + 42), what, font=ImageFont.truetype(BOLD, 15), fill=(170, 166, 198), anchor='mm')
    sheet.save(argv[2])
    print('saved', argv[2])


if __name__ == '__main__':
    main()
