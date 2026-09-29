"""Draws the weapon types' animations (weapon_types.py) so they can be judged
by eye before they go in the game: a blocky R6 character (flat colours, one
sun, thin dark edges - the game's look) holding the type's blocky weapon.

    python3 preview_types.py sheet out.png [Kind ...]    key moments of each string, front and side
    python3 preview_types.py video out.mp4 [Kind ...]    each string, full speed then half speed

The weapons' blocks come from weapon_pieces.txt: made by the game's own
WeaponFX (Tools/HeadlessTests: luau test_weapontypes.luau -a poses > ...).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anims  # noqa: E402
import r6  # noqa: E402
import weapon_types as wt  # noqa: E402

BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
INK = (24, 20, 37)
SKIN, SHIRT, PANTS = (245, 205, 48), (13, 105, 172), (40, 127, 71)
BG = (58, 68, 102)


def load_pieces(path):
    kinds = {}
    cur = None
    for line in open(path):
        p = line.split()
        if not p:
            continue
        if p[0] == 'TYPE':
            cur = kinds.setdefault(p[1], {'main': [], 'off': []})
        elif p[0] in ('PIECE', 'OFFPIECE') and cur is not None:
            c = [float(v) for v in p[8:20]]
            m = r6.cf(c[0], c[1], c[2], c[3:12])
            cur['main' if p[0] == 'PIECE' else 'off'].append(
                (p[1], tuple(float(v) for v in p[2:5]), tuple(int(v) for v in p[5:8]), m))
    return kinds


PIECES = load_pieces(os.path.join(HERE, 'weapon_pieces.txt'))


def grip_at(tilt, roll):
    return r6.cf(0, -1, 0) @ r6.angles(math.radians(tilt), 0, 0) @ r6.angles(0, 0, math.radians(roll))


def box(M, size, color):
    sx, sy, sz = [s / 2 for s in size]
    P = [(M @ np.array([x, y, z, 1.0]))[:3] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    return [([P[i] for i in f], color) for f in faces]


def figure(kind, pose):
    """the character and its weapon for a direction pose: polygons, and where the
    weapon's tip is (for the trail)"""
    tr = anims.dir_transforms(pose)
    world = r6.solve(tr)
    polys = []
    polys += box(world['Torso'], (2, 2, 1), SHIRT)
    polys += box(world['Right Arm'], (1, 2, 1), SKIN)
    polys += box(world['Left Arm'], (1, 2, 1), SKIN)
    polys += box(world['Right Leg'], (1, 2, 1), PANTS)
    polys += box(world['Left Leg'], (1, 2, 1), PANTS)
    H = world['Head']
    polys += box(H, (1.25, 1.2, 1.2), SKIN)
    for ex in (-0.26, 0.26):
        polys += box(H @ r6.cf(ex, 0.12, -0.61), (0.14, 0.24, 0.02), INK)
    polys += box(H @ r6.cf(0, -0.25, -0.61), (0.4, 0.08, 0.02), INK)
    pieces = PIECES.get(kind, {'main': [], 'off': []})
    handle = world['Right Arm'] @ r6.JOINTS['Grip'][3] @ tr['Grip']
    far = np.array([0, 0, 0, 1.0])
    reach = 0
    for name, size, color, off in pieces['main']:
        polys += box(handle @ off, size, color)
        z = -off[2, 3] + size[2] / 2
        if z > reach:
            reach, far = z, np.array([0, 0, -z, 1.0])
    if kind in wt.OFFHAND and pieces['off']:
        oh = world['Left Arm'] @ grip_at(*wt.OFFHAND[kind])
        for name, size, color, off in pieces['off']:
            polys += box(oh @ off, size, color)
    return polys, (handle @ far)[:3]


def Rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def render(polys, yaw, pitch, size, trail=None, center=(0, 3.2, 0), scale=None, label=None):
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img, "RGBA")
    V = Rx(math.radians(-pitch)) @ Ry(math.radians(yaw))
    c = np.array(center, float)
    scale = scale or size / 11.0
    light = np.array([0.4, 0.8, -0.5])
    light /= np.linalg.norm(light)

    def proj(p):
        q = V @ (np.asarray(p, float) - c)
        return (size / 2 - q[0] * scale, size * 0.5 - q[1] * scale), q[2]

    # the floor line
    fl = [proj(np.array([x, 0.0, z]))[0] for x, z in ((-7, 0), (7, 0))] if abs(yaw) < 45 else \
        [proj(np.array([0, 0.0, z]))[0] for z in (-7, 7)]
    d.line(fl, fill=(90, 100, 140, 255), width=2)
    if trail and len(trail) > 1:
        d.line([proj(p)[0] for p in trail], fill=(255, 255, 255, 170), width=5)
    items = []
    for pts, col in polys:
        Q = [V @ (p - c) for p in pts]
        n = np.cross(Q[1] - Q[0], Q[2] - Q[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9:
            continue
        items.append((np.mean([q[2] for q in Q]), Q, col, n / nn))
    items.sort(key=lambda it: -it[0])
    for _, Q, col, n in items:
        shade = 0.55 + 0.45 * abs(np.dot(n, V @ light))
        d.polygon([(size / 2 - q[0] * scale, size * 0.5 - q[1] * scale) for q in Q],
                  fill=tuple(int(cc * shade) for cc in col), outline=INK)
    if label:
        d.text((8, 6), label, font=ImageFont.truetype(BOLD, 15), fill=(230, 232, 245))
    return img


def moments(kind):
    """the stance, then each swing wound up, at the hit, and following through"""
    string = wt.String(kind)
    out = [('STANCE', 0.05, False)]
    for n, (t0, s) in enumerate(string.parts):
        coil = s.keys[1][0]
        out += [('#%d WOUND UP' % (n + 1), t0 + coil, False), ('#%d HIT' % (n + 1), t0 + s.hit, True),
                ('#%d THROUGH' % (n + 1), t0 + s.keys[3][0], True)]
    return string, out


def sheet(path, kinds):
    size = 190
    rows = []
    for kind in kinds:
        string, ms = moments(kind)
        cells = []
        for label, t, _ in ms:
            # the trail: the weapon's tip over the last 0.12 s of cutting
            trail = []
            for k in range(14):
                tt = t - k * 0.01
                if string.cutting(tt):
                    trail.append(figure(kind, string.at(tt))[1])
            polys, _ = figure(kind, string.at(t))
            cells.append((label, render(polys, 0, 8, size, trail), render(polys, 90, 4, size, trail)))
        rows.append((kind, cells))
    cols = max(len(c) for _, c in rows)
    W = cols * (size + 6) + 6
    Hh = len(rows) * (2 * size + 60) + 90
    img = Image.new("RGB", (W, Hh), (24, 20, 37))
    d = ImageDraw.Draw(img)
    d.text((W // 2, 30), "THE WEAPON TYPES - MADE LIKE THE SWORD (swing planes, 60 fps)", font=ImageFont.truetype(BOLD, 30),
           fill=(254, 231, 97), anchor="mm")
    d.text((W // 2, 62), "top: from the front (their right hand on your left)   bottom: from their right side (facing right)",
           font=ImageFont.truetype(BOLD, 16), fill=(192, 203, 220), anchor="mm")
    for r, (kind, cells) in enumerate(rows):
        y0 = 90 + r * (2 * size + 60)
        d.text((8, y0), kind.upper(), font=ImageFont.truetype(BOLD, 22), fill=(255, 255, 255))
        for c, (label, front, side) in enumerate(cells):
            x = 6 + c * (size + 6)
            d.text((x + size // 2, y0 + 38), label, font=ImageFont.truetype(BOLD, 13), fill=(200, 205, 225), anchor="mm")
            img.paste(front, (x, y0 + 48))
            img.paste(side, (x, y0 + 48 + size + 4))
    img.save(path)
    print('saved', path)


def video(path, kinds, fps=30):
    import imageio_ffmpeg
    size = 540
    W, H = size * 2, size + 60
    writer = imageio_ffmpeg.write_frames(path, (W, H), fps=fps, quality=None, codec='libx264', macro_block_size=1,
                                         output_params=['-crf', '20', '-preset', 'medium', '-movflags', '+faststart'])
    writer.send(None)
    for kind in kinds:
        _film(writer, kind, size, W, H, fps)
    writer.close()
    print('saved', path)


def _film(writer, kind, size, W, H, fps):
    string = wt.String(kind)
    font = ImageFont.truetype(BOLD, 26)
    for speed, label in ((1.0, 'FULL SPEED'), (0.5, 'HALF SPEED')):
        n = int(string.length / speed * fps)
        tips = []
        for i in range(n):
            t = i / fps * speed
            polys, tip = figure(kind, string.at(t))
            if string.cutting(t):
                tips.append(tip)
                tips = tips[-8:]
            else:
                tips = []
            front = render(polys, -25, 8, size, tips)
            side = render(polys, 90, 4, size, tips)
            frame = Image.new("RGB", (W, H), (24, 20, 37))
            frame.paste(front, (0, 60))
            frame.paste(side, (size, 60))
            ImageDraw.Draw(frame).text((W // 2, 30), '%s - %s' % (kind.upper(), label), font=font,
                                       fill=(254, 231, 97), anchor="mm")
            writer.send(np.asarray(frame).tobytes())


if __name__ == '__main__':
    mode, out = sys.argv[1], sys.argv[2]
    kinds = sys.argv[3:] or list(wt.STRINGS)
    if mode == 'sheet':
        sheet(out, kinds)
    else:
        video(out, kinds)
