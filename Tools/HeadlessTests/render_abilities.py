"""Films the weapon abilities: every frame abilities_film.luau printed (the real
MoveFX effects, played out), with the player drawn posed by each ability's own
animation (Tools/Animations/abilities.py) holding its weapon (the blocky
stand-in), in the game's look (film_draw.py). 960 x 540, 30 frames a second,
the ability's name across the top.

    luau abilities_film.luau > abilities_film.txt
    python3 render_abilities.py abilities_film.txt ../../Docs/animations/slime_abilities_fx.mp4
    python3 render_abilities.py abilities_film.txt sheet.png --sheet     (key frames of each, a PNG)
"""
import json
import math
import os
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ANIM = os.path.join(HERE, '..', 'Animations')
sys.path.insert(0, ANIM)
import film_draw as fd  # noqa: E402
import r6  # noqa: E402
import abilities  # noqa: E402
import preview_types as pv  # noqa: E402
import anims  # noqa: E402

abilities.sword_pieces(pv)

BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
OUT_W, OUT_H = 960, 540
fd.W, fd.H, fd.SS = OUT_W, OUT_H, 1
fd.args.scale = 1

NAMES = {
    'GooGloves': ('Goo Gloves', 'Sticky Fists'), 'Jellyblade': ('Jellyblade', 'Wobble Guard'),
    'GelatinHammer': ('Gelatin Hammer', 'Goo Slam'), 'OozeDaggers': ('Ooze Daggers', 'Slime Trail'),
    'AcidScythe': ('Acid Scythe', 'Acid Rain'), 'GelatinousEdge': ('Gelatinous Edge', "Oozark's Jaw"),
}
RARITY = {'GooGloves': ('COMMON', (235, 235, 240)), 'Jellyblade': ('RARE', (0, 153, 219)), 'GelatinHammer': ('EPIC', (170, 100, 255)),
          'OozeDaggers': ('LEGENDARY', (254, 174, 52)), 'AcidScythe': ('MYTHIC', (255, 0, 68)), 'GelatinousEdge': ('SECRET', (255, 255, 255))}


def load(path):
    static, frames = [], []
    cur, mode = None, None
    for line in open(path):
        if line.startswith('STATIC'):
            mode = 'static'
        elif line.startswith('FRAME '):
            b = line.split()
            cur = {'t': float(b[1]), 'id': b[2], 'since': float(b[3]), 'root': [float(v) for v in b[4:7]], 'yaw': float(b[7]),
                   'parts': [], 'text': [], 'flash': None}
            frames.append(cur)
            mode = 'frame'
        elif line.startswith('END'):
            mode = None
        elif line.startswith('{'):
            (static if mode == 'static' else cur['parts']).append(json.loads(line))
        elif line.startswith('TEXT ') and cur is not None:
            b = line.rstrip('\n').split(' ', 9)
            cur['text'].append(([float(v) for v in b[1:4]], tuple(int(v) for v in b[4:7]), float(b[7]), float(b[8]), b[9]))
        elif line.startswith('FLASH ') and cur is not None:
            b = line.split()
            cur['flash'] = (tuple(int(v) for v in b[1:4]), float(b[4]))
    return static, frames


def part_of(m, size, col, neon=False, t=0.0):
    c = m[:3, 3]
    R = m[:3, :3]
    return {'cf': list(c) + list(R.reshape(-1)), 's': list(size), 'col': list(col), 't': t, 'm': 'Neon' if neon else 'Plastic',
            'sh': 'Block', 'c': 'Part'}


SKIN, SHIRT, PANTS = (245, 205, 48), (13, 105, 172), (40, 127, 71)


def body_parts(wid, since, root, yaw):
    """the player posed by the ability's animation, where the film put them"""
    kind, anim = abilities.ABILITIES[wid]
    t = min(max(since, 0.0), anim.length)
    tr = anims.dir_transforms(anim.at(t))
    hrp = r6.cf(root[0], root[1], root[2]) @ r6.angles(0, yaw, 0)
    world = r6.solve(tr, hrp)
    out = []
    for name, col in (('Torso', SHIRT), ('Right Arm', SKIN), ('Left Arm', SKIN), ('Right Leg', PANTS), ('Left Leg', PANTS), ('Head', SKIN)):
        size = (1.25, 1.2, 1.2) if name == 'Head' else r6.PARTS[name][0]
        out.append(part_of(world[name], size, col))
    # eyes and a mouth on the face (the front is the head's -Z)
    H = world['Head']
    for ex in (-0.26, 0.26):
        out.append(part_of(H @ r6.cf(ex, 0.12, -0.61), (0.14, 0.24, 0.02), (24, 20, 37)))
    # the weapon (the blocky stand-in, as preview_types draws it)
    pieces = pv.PIECES.get(kind, {'main': [], 'off': []})
    if kind == 'Fists':
        handle = world['Right Arm'] @ pv.grip_at(-90, 0)  # (the game holds gauntlets on the fists)
    else:
        handle = world['Right Arm'] @ r6.JOINTS['Grip'][3] @ tr['Grip']
    for name, size, col, off in pieces['main']:
        out.append(part_of(handle @ off, size, col, neon=name in ('Edge', 'Knuckles', 'Band')))
    if kind in abilities.wt.OFFHAND and pieces['off']:
        oh = world['Left Arm'] @ pv.grip_at(*abilities.wt.OFFHAND[kind])
        for name, size, col, off in pieces['off']:
            out.append(part_of(oh @ off, size, col, neon=name in ('Edge', 'Knuckles', 'Band')))
    return out


def camera(wid):
    # three-quarters, from in front and to the right, the dummies in view
    eye = np.array([15.0, 9.5, 4.0])
    look = np.array([0.0, 2.8, -6.0])
    return eye, look, 52.0


def draw(job):
    static, fr = job
    eye, look, fov = camera(fr['id'])
    parts = list(static) + body_parts(fr['id'], fr['since'], fr['root'], fr['yaw']) + fr['parts']
    img, to_screen = fd.render(parts, eye, look, fov)
    img = img.convert('RGB')
    if fr['flash']:
        col, a = fr['flash']
        img = Image.blend(img, Image.new('RGB', img.size, col), min(0.8, a))
    d = ImageDraw.Draw(img)
    for (pos, col, scale, see, text) in fr['text']:
        sp = to_screen(np.array(pos))
        if not sp:
            continue
        size = int(34 * max(0.2, scale))
        f = ImageFont.truetype(BOLD, size)
        alpha = 1 - see
        if alpha <= 0.02:
            continue
        fill = tuple(int(c * alpha + 24 * (1 - alpha)) for c in col)
        d.text(sp, text, font=f, fill=fill, anchor='mm', stroke_width=max(2, size // 10), stroke_fill=(24, 20, 37))
    name, ability = NAMES.get(fr['id'], (fr['id'], ''))
    rarity, rcol = RARITY.get(fr['id'], ('', (255, 255, 255)))
    d.rectangle((0, 0, OUT_W, 64), fill=(24, 20, 37))
    d.text((OUT_W // 2, 22), ability.upper(), font=ImageFont.truetype(BOLD, 28), fill=(254, 231, 97), anchor='mm')
    d.text((OUT_W // 2, 50), '%s  -  %s' % (name, rarity), font=ImageFont.truetype(BOLD, 16), fill=rcol, anchor='mm')
    return np.asarray(img)


def main():
    src, out = sys.argv[1], sys.argv[2]
    static, frames = load(src)
    if '--sheet' in sys.argv:
        picks = []
        for wid in NAMES:
            fs = [f for f in frames if f['id'] == wid]
            if not fs:
                continue
            for want in (0.1, 0.3, 0.45, 0.7, 0.95, 1.4):
                picks.append(min(fs, key=lambda f: abs(f['since'] - want)))
        with Pool(4) as pool:
            imgs = pool.map(draw, [(static, f) for f in picks])
        tw, th = 480, 270
        sheet = Image.new('RGB', (tw * 6, th * (len(imgs) // 6)), (24, 20, 37))
        for i, im in enumerate(imgs):
            sheet.paste(Image.fromarray(im).resize((tw, th)), ((i % 6) * tw, (i // 6) * th))
        sheet.save(out)
        print('saved', out)
        return
    import imageio_ffmpeg
    writer = imageio_ffmpeg.write_frames(out, (OUT_W, OUT_H), fps=30, quality=None, codec='libx264', macro_block_size=1,
                                         output_params=['-crf', '21', '-preset', 'medium', '-movflags', '+faststart'])
    writer.send(None)
    with Pool(4) as pool:
        for im in pool.imap(draw, [(static, f) for f in frames], chunksize=4):
            writer.send(im.tobytes())
    writer.close()
    print('saved', out)


if __name__ == '__main__':
    main()
