"""GAME PASS PICTURES (the 512 x 512 image each Game Pass needs on
create.roblox.com): an 8-bit picture of what the pass gives (drawn on a
64 x 64 grid, then blown up 8x so the pixels stay sharp) on a banded,
rayed background, with a fat pixel-font label. Roblox shows pass pictures
cut to a circle, so everything that matters sits inside it.

    python3 pass_icons.py [--font PressStart2P.ttf] [--out ../../Docs/passes]

Writes pass_<Key>.png for every pass in Config.Shop.Passes (VIP, DoubleXP,
DoubleCoins, Luck1, Luck2, Luck3, InstantTen) plus pass_sheet.png (all of
them, cut to the circle, at full size and at 100 px as the Store tab
shows them). Needs numpy and Pillow.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument('--font', default='', help='PressStart2P.ttf (else a bold system font)')
ap.add_argument('--out', default=os.path.join(HERE, '..', '..', 'Docs', 'passes'))
args = ap.parse_args()

L = 64           # the pixel grid
K = 8            # blown up this much
S = L * K        # 512
OUTLINE = (24, 14, 34)
FONT = args.font if args.font and os.path.exists(args.font) else \
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


# ---- the pixel grid -------------------------------------------------------
def grid():
    yy, xx = np.mgrid[0:L, 0:L]
    return xx + 0.5, yy + 0.5


def poly(points):
    m = Image.new('L', (L, L), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return np.array(m) > 127


def disc(cx, cy, r):
    x, y = grid()
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ring(cx, cy, r0, r1):
    x, y = grid()
    d = (x - cx) ** 2 + (y - cy) ** 2
    return (d <= r1 * r1) & (d > r0 * r0)


def rect(x0, y0, x1, y1):
    x, y = grid()
    return (x >= x0) & (x < x1) & (y >= y0) & (y < y1)


def shift(m, dx, dy):
    out = np.zeros_like(m)
    h, w = m.shape
    ys = slice(max(0, dy), h + min(0, dy))
    yd = slice(max(0, -dy), h + min(0, -dy))
    xs = slice(max(0, dx), w + min(0, dx))
    xd = slice(max(0, -dx), w + min(0, -dx))
    out[ys, xs] = m[yd, xd]
    return out


class Sprite:
    """layers painted in order; each one shaded (a light top-left edge, a
    dark bottom-right edge); one dark outline round the lot"""

    def __init__(self):
        self.rgb = np.zeros((L, L, 3), np.uint8)
        self.mask = np.zeros((L, L), bool)

    def paint(self, m, base, hi=None, lo=None, shade=True):
        hi = hi or tuple(min(255, int(c + (255 - c) * 0.55)) for c in base)
        lo = lo or tuple(int(c * 0.62) for c in base)
        self.rgb[m] = base
        if shade:
            light = m & ~(shift(m, 1, 1) & shift(m, 1, 0) & shift(m, 0, 1))
            dark = m & ~(shift(m, -1, -1) & shift(m, -1, 0) & shift(m, 0, -1))
            self.rgb[dark] = lo
            self.rgb[light & ~dark] = hi
        self.mask |= m

    def dots(self, pts, col):
        for x, y in pts:
            self.rgb[y, x] = col
            self.mask[y, x] = True

    def image(self):
        edge = np.zeros_like(self.mask)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            edge |= shift(self.mask, dx, dy)
        edge &= ~self.mask
        a = np.zeros((L, L, 4), np.uint8)
        a[self.mask, :3] = self.rgb[self.mask]
        a[self.mask, 3] = 255
        a[edge] = OUTLINE + (255,)
        return Image.fromarray(a, 'RGBA').resize((S, S), Image.NEAREST)


def sparkle(sp, cx, cy, size, col=(255, 255, 255)):
    pts = [(cx, cy)]
    for i in range(1, size + 1):
        pts += [(cx + i, cy), (cx - i, cy), (cx, cy + i), (cx, cy - i)]
    sp.dots(pts, col)


# ---- the background -------------------------------------------------------
def background(inner, outer, rays=16, spin=0.0):
    x, y = grid()
    cx = cy = L / 2
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (L * 0.72)
    t = np.clip(np.floor(d * 6) / 6, 0, 1)[..., None]          # bands, 8-bit
    a = (np.arctan2(y - cy, x - cx) + spin) % (2 * math.pi)
    ray = (np.floor(a / (2 * math.pi) * rays) % 2 == 0)[..., None]
    inner, outer = np.array(inner, float), np.array(outer, float)
    col = inner * (1 - t) + outer * t
    col = np.where(ray, col * 1.12 + 6, col)
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), 'RGB')
    return img.resize((S, S), Image.NEAREST).convert('RGBA')


def glow(img, col, r=150, cy=None):
    g = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cy = S * 0.42 if cy is None else cy
    ImageDraw.Draw(g).ellipse((S / 2 - r, cy - r, S / 2 + r, cy + r), fill=col + (150,))
    return Image.alpha_composite(img, g.filter(ImageFilter.GaussianBlur(50)))


def drop(img, layer, off=12):
    a = layer.split()[3]
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sh.putalpha(a.point(lambda v: v * 0.45))
    sh = Image.composite(Image.new('RGBA', (S, S), (10, 0, 20, 255)), sh, sh)
    sh.putalpha(a.point(lambda v: int(v * 0.45)))
    img.alpha_composite(sh, (off, off))
    img.alpha_composite(layer)
    return img


# ---- the label ------------------------------------------------------------
def label(img, text, cy, px, top, bottom, stroke=None):
    """pixel-font text: a top-to-bottom two-tone fill, a fat dark stroke and
    a drop shadow, centred at height cy"""
    f = ImageFont.truetype(FONT, px)
    stroke = stroke or max(6, px // 6)
    d0 = ImageDraw.Draw(img)
    l, t, r, b = d0.textbbox((0, 0), text, font=f, stroke_width=stroke)
    while r - l > S * 0.80:                       # keep it in the circle
        px -= 4
        f = ImageFont.truetype(FONT, px)
        stroke = max(6, px // 6)
        l, t, r, b = d0.textbbox((0, 0), text, font=f, stroke_width=stroke)
    x = S / 2 - (r - l) / 2 - l
    y = cy - (b - t) / 2 - t
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x + 10, y + 10), text, font=f, fill=(10, 0, 20, 140),
                                stroke_width=stroke, stroke_fill=(10, 0, 20, 140))
    img.alpha_composite(shadow)
    ImageDraw.Draw(img).text((x, y), text, font=f, fill=OUTLINE + (255,),
                             stroke_width=stroke, stroke_fill=OUTLINE + (255,))
    m = Image.new('L', (S, S), 0)
    ImageDraw.Draw(m).text((x, y), text, font=f, fill=255)
    gl, gt, gr, gb = m.getbbox()
    fill = Image.new('RGBA', (S, S))
    gd = ImageDraw.Draw(fill)
    mid = gt + (gb - gt) * 0.5
    gd.rectangle((0, 0, S, mid), fill=top + (255,))
    gd.rectangle((0, mid, S, S), fill=bottom + (255,))
    img.paste(fill, (0, 0), m)
    return img


# ---- the pictures ---------------------------------------------------------
GOLD = (255, 200, 40)
GOLD_HI = (255, 244, 170)
GOLD_LO = (196, 112, 18)
WHITE = (255, 255, 255)


def crown():
    sp = Sprite()
    body = poly([(11, 16), (20, 27), (32, 11), (44, 27), (53, 16), (50, 40), (14, 40)])
    sp.paint(body, GOLD, GOLD_HI, GOLD_LO)
    sp.paint(rect(13, 38, 51, 44), (232, 160, 30), GOLD_HI, GOLD_LO)
    for cx, cy in ((11, 15), (32, 10), (53, 15)):
        sp.paint(disc(cx, cy, 3.2), GOLD, GOLD_HI, GOLD_LO)
    sp.paint(disc(32, 31, 4.2), (60, 140, 255))
    sp.paint(disc(21, 33, 2.8), (240, 50, 70))
    sp.paint(disc(43, 33, 2.8), (240, 50, 70))
    sp.dots([(17, 40), (23, 40), (29, 40), (35, 40), (41, 40), (47, 40)], GOLD_HI)
    sparkle(sp, 56, 26, 2)
    sparkle(sp, 8, 30, 1)
    return sp.image()


def star_pts(cx, cy, r0, r1, n=5, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r0
        a = rot + i * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def xp_star():
    sp = Sprite()
    sp.paint(poly(star_pts(32, 27, 10, 22)), (90, 230, 255), (220, 255, 255), (30, 130, 210))
    sp.paint(poly(star_pts(32, 28, 5, 11)), (170, 248, 255), shade=False)
    # an up arrow beside it: XP goes up
    sp.paint(poly([(50, 30), (58, 38), (54, 38), (54, 48), (46, 48), (46, 38), (42, 38)]),
             (90, 240, 110), (210, 255, 200), (30, 150, 60))
    sparkle(sp, 10, 14, 2)
    sparkle(sp, 12, 44, 1)
    return sp.image()


def coin(sp, cx, cy, r):
    sp.paint(disc(cx, cy, r), GOLD, GOLD_HI, GOLD_LO)
    sp.paint(ring(cx, cy, r - 4, r - 3), (214, 140, 22), shade=False)
    # a big C on it
    c = ring(cx, cy, r * 0.32, r * 0.55) & ~poly([(cx, cy), (cx + r, cy - r * 0.5), (cx + r, cy + r * 0.5)])
    sp.paint(c, (214, 140, 22), shade=False)


def coins():
    sp = Sprite()
    # a stack behind
    for i in range(4):
        y = 44 - i * 4
        sp.paint(rect(38, y, 56, y + 4) | disc(38, y + 2, 2) | disc(56, y + 2, 2), GOLD, GOLD_HI, GOLD_LO)
    coin(sp, 26, 28, 17)
    coin(sp, 47, 22, 10)
    sparkle(sp, 12, 12, 2)
    sparkle(sp, 58, 8, 1)
    return sp.image()


def clover(gold=False, sparkles=0):
    sp = Sprite()
    if gold:
        leaf, hi, lo = GOLD, GOLD_HI, GOLD_LO
    else:
        leaf, hi, lo = (70, 210, 90), (190, 255, 170), (24, 120, 50)
    # the stem
    sp.paint(poly([(31, 30), (35, 30), (40, 50), (36, 51)]), lo, leaf, (16, 80, 34) if not gold else (150, 80, 10))
    cx, cy = 32, 25
    for ang in (0, 90, 180, 270):
        a = math.radians(ang + 45)
        ox, oy = math.cos(a) * 10, math.sin(a) * 10
        # a heart leaf: two discs and a point at the middle
        b = math.radians(ang + 45 + 90)
        bx, by = math.cos(b) * 4, math.sin(b) * 4
        m = disc(cx + ox + bx, cy + oy + by, 5.2) | disc(cx + ox - bx, cy + oy - by, 5.2)
        m |= poly([(cx + ox * 0.15, cy + oy * 0.15), (cx + ox + bx * 2.2, cy + oy + by * 2.2),
                   (cx + ox - bx * 2.2, cy + oy - by * 2.2)])
        sp.paint(m, leaf, hi, lo)
    sp.paint(disc(cx, cy, 2.2), lo, shade=False)
    spots = [(10, 12, 2), (54, 14, 2), (8, 40, 1), (56, 42, 1), (20, 4, 1), (46, 52, 1)]
    for x, y, s in spots[:sparkles]:
        sparkle(sp, x, y, s, GOLD_HI if gold else WHITE)
    return sp.image()


def bolt():
    sp = Sprite()
    sp.paint(poly([(38, 4), (16, 34), (30, 34), (24, 58), (48, 24), (34, 24), (42, 4)]),
             (255, 230, 60), (255, 255, 210), (220, 130, 20))
    sparkle(sp, 12, 14, 2)
    sparkle(sp, 52, 44, 2)
    sparkle(sp, 54, 10, 1)
    return sp.image()


def rainbow_ring(img):
    cols = [(255, 70, 80), (255, 160, 40), (255, 230, 60), (90, 220, 100), (60, 170, 255), (170, 90, 255)]
    x, y = grid()
    a = (np.arctan2(y - 27, x - 32) + math.pi) / (2 * math.pi)
    m = ring(32, 27, 24, 28)
    arr = np.zeros((L, L, 4), np.uint8)
    idx = (a * len(cols) * 2).astype(int) % len(cols)
    for i, c in enumerate(cols):
        sel = m & (idx == i)
        arr[sel] = c + (200,)
    layer = Image.fromarray(arr, 'RGBA').resize((S, S), Image.NEAREST)
    img.alpha_composite(layer)
    return img


PASSES = {
    # key: (background inner, outer, glow, picture, label, label colours top/bottom)
    'VIP': ((150, 70, 230), (46, 12, 92), GOLD, crown, 'VIP', (255, 244, 150), (255, 186, 30)),
    'DoubleXP': ((40, 150, 255), (10, 30, 110), (120, 240, 255), xp_star, '2x XP', (200, 255, 255), (80, 220, 255)),
    'DoubleCoins': ((255, 170, 40), (140, 50, 10), (255, 230, 120), coins, '2x COINS', (255, 248, 170), (255, 196, 40)),
    'Luck1': ((60, 190, 110), (10, 70, 40), (170, 255, 170), lambda: clover(False, 2), '+50%', (220, 255, 200), (120, 240, 120)),
    'Luck2': ((30, 200, 190), (10, 60, 90), (170, 255, 230), lambda: clover(False, 4), '+100%', (220, 255, 240), (90, 240, 200)),
    'Luck3': ((120, 60, 220), (30, 10, 70), (255, 220, 110), lambda: clover(True, 6), '+200%', (255, 248, 170), (255, 190, 40)),
    'InstantTen': ((255, 90, 60), (110, 10, 30), (255, 220, 90), bolt, 'x10', (255, 250, 190), (255, 200, 50)),
}


TOP = {'Luck1': 'LUCK', 'Luck2': 'LUCK', 'Luck3': 'LUCK', 'InstantTen': 'INSTANT'}


def make(key):
    inner, outer, gcol, pic, text, top, bottom = PASSES[key]
    img = background(inner, outer, spin={'Luck3': 0.2, 'InstantTen': 0.1}.get(key, 0.0))
    img = glow(img, gcol)
    if key == 'Luck3':
        img = rainbow_ring(img)
    sprite = pic()
    # the picture sits a little high, the label under it; the ones with a
    # word on top too are drawn smaller (still whole pixels: 6 px a dot)
    shifted = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    if key in TOP:
        n = L * 6
        sprite = sprite.resize((L, L), Image.NEAREST).resize((n, n), Image.NEAREST)
        shifted.alpha_composite(sprite, ((S - n) // 2, int(S * 0.47 - n * 0.45)))
    else:
        shifted.alpha_composite(sprite, (0, -16))
    img = drop(img, shifted)
    px = 92 if len(text) <= 4 else 70
    img = label(img, text, S * 0.80, px, top, bottom)
    if key in TOP:
        img = label(img, TOP[key], S * 0.17, 40, (255, 255, 255), (255, 236, 170) if key in ('Luck3', 'InstantTen') else (220, 255, 220))
    return img.convert('RGB')


def circle(img, size):
    im = img.resize((size, size), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    im.putalpha(m.resize((size, size), Image.LANCZOS))
    return im


def sheet(imgs):
    big, small, pad = 256, 100, 24
    n = len(imgs)
    w = pad + n * (big + pad)
    h = pad + big + pad + small + pad
    out = Image.new('RGBA', (w, h), (25, 27, 31, 255))
    for i, im in enumerate(imgs):
        x = pad + i * (big + pad)
        out.alpha_composite(circle(im, big), (x, pad))
        out.alpha_composite(circle(im, small), (x + (big - small) // 2, pad * 2 + big))
    return out.convert('RGB')


if __name__ == '__main__':
    os.makedirs(args.out, exist_ok=True)
    made = []
    for key in PASSES:
        im = make(key)
        path = os.path.join(args.out, f'pass_{key}.png')
        im.save(path)
        made.append(im)
        print('  ', os.path.relpath(path))
    sheet(made).save(os.path.join(args.out, 'pass_sheet.png'))
    print('   pass_sheet.png')
