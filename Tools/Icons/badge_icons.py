"""BADGE PICTURES (the 512 x 512 image each badge needs on
create.roblox.com): the same 8-bit look as the Game Pass pictures
(pass_icons.py - its drawing kit is reused here): a picture on a 64 x 64
grid blown up 8x, a banded, rayed background, a fat pixel-font label.
Roblox shows badges cut to a circle, so everything sits inside it.

    python3 badge_icons.py [--font PressStart2P.ttf] [--out ../../Docs/badges]

Writes badge_<Key>.png for every badge in Config.Badges (Welcome,
SlimeSlayer, FirstSpin, ColosseumChampion, OozarkDown, SpireConqueror)
plus badge_sheet.png. Needs numpy and Pillow.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if '--out' not in sys.argv:
    sys.argv += ['--out', os.path.join(HERE, '..', '..', 'Docs', 'badges')]
from pass_icons import (Image, L, S, Sprite, GOLD, GOLD_HI, GOLD_LO, WHITE, args, background, circle, disc,
                        drop, glow, label, poly, rect, ring, sparkle, star_pts)

SLIME, SLIME_HI, SLIME_LO = (99, 199, 77), (190, 250, 160), (40, 120, 50)
PINK, PINK_HI, PINK_LO = (255, 63, 164), (255, 190, 225), (170, 20, 100)
STONE, STONE_HI, STONE_LO = (192, 203, 220), (240, 245, 255), (110, 120, 150)


def spire(sp, gold=False):
    body, hi, lo = (GOLD, GOLD_HI, GOLD_LO) if gold else (STONE, STONE_HI, STONE_LO)
    sp.paint(poly([(24, 56), (40, 56), (36, 18), (28, 18)]), body, hi, lo)
    sp.paint(rect(21, 52, 43, 58), body, hi, lo)
    for y in (26, 36, 46):
        sp.paint(rect(30, y, 34, y + 4), (60, 40, 90), shade=False)  # windows
    sp.paint(poly([(26, 18), (38, 18), (32, 6)]), PINK, PINK_HI, PINK_LO)


def welcome():
    sp = Sprite()
    spire(sp)
    sparkle(sp, 12, 14, 2)
    sparkle(sp, 52, 20, 2)
    sparkle(sp, 50, 46, 1)
    return sp.image()


def slime(sp, cx, cy, w, h, crown=True, dead=False):
    body = disc(cx, cy, h) & rect(cx - w, cy - h, cx + w + 1, cy + h)
    body |= rect(cx - w, cy, cx + w, cy + h * 0.6)
    sp.paint(body, SLIME, SLIME_HI, SLIME_LO)
    ey = int(cy - h * 0.15)
    for ex in (int(cx - w * 0.4), int(cx + w * 0.4)):
        if dead:  # X eyes
            sp.dots([(ex - 1, ey - 1), (ex + 1, ey - 1), (ex, ey), (ex - 1, ey + 1), (ex + 1, ey + 1)], (24, 14, 34))
        else:
            sp.paint(rect(ex - 1, ey - 2, ex + 2, ey + 2), WHITE, shade=False)
            sp.dots([(ex, ey)], (24, 14, 34))
    if crown:
        top = int(cy - h) - 1
        sp.paint(poly([(cx - 6, top), (cx - 6, top - 6), (cx - 3, top - 3), (cx, top - 8), (cx + 3, top - 3),
                       (cx + 6, top - 6), (cx + 6, top)]), GOLD, GOLD_HI, GOLD_LO)


def slime_slayer():
    sp = Sprite()
    slime(sp, 32, 36, 15, 14, crown=True, dead=True)
    sparkle(sp, 10, 12, 2)
    sparkle(sp, 54, 14, 1)
    return sp.image()


def token(sp, cx, cy, r):
    sp.paint(disc(cx, cy, r), PINK, PINK_HI, PINK_LO)
    sp.paint(ring(cx, cy, r - 4, r - 3), (200, 30, 120), shade=False)
    sp.paint(poly(star_pts(cx, cy, r * 0.25, r * 0.55)), GOLD, GOLD_HI, GOLD_LO)


def first_spin():
    sp = Sprite()
    token(sp, 32, 30, 20)
    sparkle(sp, 8, 10, 2)
    sparkle(sp, 56, 12, 2)
    sparkle(sp, 54, 50, 1)
    return sp.image()


def trophy():
    sp = Sprite()
    cup = poly([(16, 10), (48, 10), (44, 30), (36, 36), (28, 36), (20, 30)])
    sp.paint(ring(16, 18, 4, 7) & rect(0, 0, 18, 64), GOLD, GOLD_HI, GOLD_LO)
    sp.paint(ring(48, 18, 4, 7) & rect(46, 0, 64, 64), GOLD, GOLD_HI, GOLD_LO)
    sp.paint(cup, GOLD, GOLD_HI, GOLD_LO)
    sp.paint(rect(29, 36, 35, 44), (232, 160, 30), GOLD_HI, GOLD_LO)
    sp.paint(rect(22, 44, 42, 50), (150, 90, 60), (210, 150, 110), (90, 50, 40))
    sp.paint(poly(star_pts(32, 21, 3, 7)), WHITE, shade=False)
    sparkle(sp, 8, 40, 2)
    sparkle(sp, 56, 40, 1)
    return sp.image()


def oozark_down():
    sp = Sprite()
    slime(sp, 32, 38, 20, 16, crown=True, dead=True)
    # a sword stuck in the top of him
    sp.paint(poly([(44, 4), (48, 8), (38, 24), (35, 21)]), (220, 230, 245), WHITE, (120, 130, 160))
    sp.paint(rect(33, 20, 40, 23), GOLD, GOLD_HI, GOLD_LO)
    sparkle(sp, 10, 12, 2)
    return sp.image()


def conqueror():
    sp = Sprite()
    spire(sp, gold=True)
    # a flag on the very top
    sp.paint(rect(31, 0, 33, 8), (90, 60, 40), shade=False)
    sp.paint(poly([(33, 0), (44, 2), (33, 5)]), (228, 59, 68), (255, 150, 150), (150, 20, 40))
    sparkle(sp, 10, 16, 2)
    sparkle(sp, 54, 22, 2)
    sparkle(sp, 12, 46, 1)
    sparkle(sp, 52, 48, 1)
    return sp.image()


BADGES = {
    # key: (background inner, outer, glow, picture, label, label top/bottom)
    'Welcome': ((60, 150, 255), (16, 30, 100), (170, 220, 255), welcome, 'WELCOME', (255, 255, 255), (170, 220, 255)),
    'SlimeSlayer': ((80, 200, 90), (14, 70, 40), (190, 255, 170), slime_slayer, 'SLAYER', (230, 255, 210), (120, 240, 120)),
    'FirstSpin': ((190, 70, 230), (50, 12, 92), (255, 160, 220), first_spin, '1ST SPIN', (255, 230, 245), (255, 120, 200)),
    'ColosseumChampion': ((255, 150, 40), (130, 40, 10), (255, 230, 120), trophy, 'CHAMPION', (255, 248, 170), (255, 196, 40)),
    'OozarkDown': ((60, 170, 120), (20, 40, 60), (200, 255, 170), oozark_down, 'OOZARK', (230, 255, 210), (140, 240, 140)),
    'SpireConqueror': ((150, 70, 230), (30, 8, 70), (255, 220, 110), conqueror, 'CONQUEROR', (255, 248, 170), (255, 190, 40)),
}


def make(key):
    inner, outer, gcol, pic, text, top, bottom = BADGES[key]
    img = glow(background(inner, outer), gcol)
    shifted = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    shifted.alpha_composite(pic(), (0, -18))
    img = drop(img, shifted)
    img = label(img, text, S * 0.77, 80 if len(text) <= 6 else 56, top, bottom)
    return img.convert('RGB')


if __name__ == '__main__':
    os.makedirs(args.out, exist_ok=True)
    made = []
    for key in BADGES:
        im = make(key)
        im.save(os.path.join(args.out, f'badge_{key}.png'))
        made.append(im)
        print('   badge_' + key + '.png')
    big, small, pad = 256, 100, 24
    w = pad + len(made) * (big + pad)
    out = Image.new('RGBA', (w, pad * 3 + big + small), (25, 27, 31, 255))
    for i, im in enumerate(made):
        x = pad + i * (big + pad)
        out.alpha_composite(circle(im, big), (x, pad))
        out.alpha_composite(circle(im, small), (x + (big - small) // 2, pad * 2 + big))
    out.convert('RGB').save(os.path.join(args.out, 'badge_sheet.png'))
    print('   badge_sheet.png')
