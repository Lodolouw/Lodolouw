"""THE MENU ICONS: pixel art for every button and tab of the new interface
(Previews/gui_windows_sketch.html) - 32 x 32, drawn in the game's look: bright
colours lit from the top left, a darker underside, and a thick dark outline,
blown up to 256 x 256 without smoothing.

    python3 make_ui_icons.py            -> out/ui/<Name>.png and Docs/ui_icons.png
    python3 make_ui_icons.py --sketch   -> also prints them as data URIs (for the sketch page)

Each icon is a few flat shapes (polygons, ellipses, rectangles) on a 32 x 32
grid; `shade` then lights them (a light rim top-left, a dark rim bottom-right)
and `outline` puts the ink round the outside. Upload the PNGs as decals with
Tools/Upload/upload_assets.ps1 when the new menus go in.
"""
import base64, io, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'out', 'ui')
N = 32
INK = (24, 20, 37, 255)

# the game's palette
RED, RED_D = (229, 59, 68), (158, 32, 48)
ORANGE = (247, 150, 50)
GOLD, GOLD_L, GOLD_D = (255, 182, 46), (255, 231, 120), (196, 112, 18)
YEL = (254, 231, 97)
GREEN, GREEN_L, GREEN_D = (82, 201, 90), (160, 240, 130), (40, 130, 60)
TEAL = (25, 179, 166)
BLUE, BLUE_L, BLUE_D = (79, 107, 255), (150, 175, 255), (44, 62, 170)
SKY = (70, 180, 255)
PURPLE, PURPLE_L, PURPLE_D = (141, 75, 255), (196, 150, 255), (86, 40, 170)
PINK, PINK_L = (255, 63, 164), (255, 160, 210)
WHITE, GREY, GREY_D = (255, 255, 255), (185, 190, 205), (120, 124, 145)
BROWN, BROWN_L, BROWN_D = (160, 100, 55), (205, 145, 85), (105, 62, 32)
STEEL, STEEL_L = (200, 210, 225), (245, 248, 255)
SKIN = (254, 213, 150)


class Canvas:
    """A 32 x 32 picture drawn in layers of flat colour."""

    def __init__(self):
        self.img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, c):
        self.d.polygon([(x, y) for x, y in pts], fill=(*c, 255))

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle([x0, y0, x1, y1], fill=(*c, 255))

    def oval(self, x0, y0, x1, y1, c):
        self.d.ellipse([x0, y0, x1, y1], fill=(*c, 255))

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=(*c, 255), width=w)

    def px(self, x, y, c):
        if 0 <= x < N and 0 <= y < N:
            self.img.putpixel((x, y), (*c, 255))


def lighten(c, k):
    return tuple(int(v + (255 - v) * k) for v in c[:3])


def darken(c, k):
    return tuple(int(v * (1 - k)) for v in c[:3])


def shade(img):
    """Light each flat colour region: its top-left edge lighter, its bottom-right
    edge darker (the sun's up and to the left, like the game's pixel art)."""
    a = np.array(img).astype(int)
    rgb, al = a[..., :3], a[..., 3]
    out = a.copy()
    same = lambda y, x, dy, dx: (0 <= y + dy < N and 0 <= x + dx < N and al[y + dy, x + dx] > 0
                                 and (rgb[y + dy, x + dx] == rgb[y, x]).all())
    for y in range(N):
        for x in range(N):
            if al[y, x] == 0:
                continue
            c = tuple(rgb[y, x])
            if c == INK[:3] or c == WHITE:
                continue
            if not same(y, x, -1, 0) or not same(y, x, 0, -1):
                out[y, x, :3] = lighten(c, 0.38)
            elif not same(y, x, 1, 0) or not same(y, x, 0, 1):
                out[y, x, :3] = darken(c, 0.28)
    return Image.fromarray(out.astype(np.uint8))


def outline(img, width=1):
    """Ink round everything (and a little drop shadow down and right)."""
    a = np.array(img)
    al = a[..., 3] > 0
    grow = al.copy()
    for _ in range(width):
        g = grow.copy()
        g[1:, :] |= grow[:-1, :]
        g[:-1, :] |= grow[1:, :]
        g[:, 1:] |= grow[:, :-1]
        g[:, :-1] |= grow[:, 1:]
        grow = g
    ring = grow & ~al
    a[ring] = INK
    return Image.fromarray(a)


def finish(cv, edge=True):
    img = shade(cv.img)
    return outline(img) if edge else img


# ----------------------------------------------------------------------
# the icons
# ----------------------------------------------------------------------
def icon_shop():
    cv = Canvas()
    cv.poly([(3, 7), (8, 7), (10, 11), (29, 11), (26, 22), (11, 22)], RED)       # basket
    for x in (15, 19, 23):
        cv.line([(x, 12), (x - 1, 21)], RED_D)
    cv.line([(12, 16), (27, 16)], RED_D)
    cv.rect(1, 5, 7, 7, GREY)                                                    # handle
    cv.line([(11, 22), (9, 25), (26, 25)], GREY_D, 2)                             # frame
    cv.oval(9, 25, 14, 30, INK[:3]); cv.oval(10, 26, 13, 29, GREY)                # wheels
    cv.oval(21, 25, 26, 30, INK[:3]); cv.oval(22, 26, 25, 29, GREY)
    cv.rect(13, 6, 18, 10, GOLD); cv.rect(19, 4, 24, 10, GREEN)                  # goods poking out
    cv.rect(14, 7, 17, 8, GOLD_L)
    return finish(cv)


def icon_bag():
    cv = Canvas()
    cv.oval(10, 2, 21, 11, BROWN_D)                                              # top loop
    cv.oval(13, 5, 18, 10, (0, 0, 0))
    cv.poly([(6, 12), (10, 8), (22, 8), (26, 12), (27, 28), (5, 28)], BROWN)     # body, rounded top
    cv.poly([(7, 12), (11, 9), (21, 9), (25, 12), (25, 18), (7, 18)], BROWN_L)   # flap
    cv.rect(9, 20, 23, 27, BROWN_D)                                              # front pocket
    cv.rect(10, 21, 22, 22, BROWN)
    cv.rect(14, 16, 17, 20, GOLD)                                                # buckle
    cv.rect(15, 17, 16, 19, GOLD_D)
    cv.rect(3, 15, 5, 27, BROWN_D); cv.rect(27, 15, 29, 27, BROWN_D)             # straps
    d = np.array(cv.img); sub = d[5:11, 13:19]; sub[(sub[..., :3] == 0).all(-1) & (sub[..., 3] > 0)] = 0
    cv.img = Image.fromarray(d)
    return finish(cv)


def icon_arcade():
    cv = Canvas()
    cv.poly([(7, 3), (24, 3), (25, 7), (25, 29), (6, 29), (6, 7)], PURPLE)        # cabinet
    cv.rect(8, 4, 23, 7, PINK)                                                   # marquee
    cv.rect(9, 9, 22, 18, INK[:3])                                               # screen
    cv.rect(10, 10, 21, 17, (40, 30, 90))
    for i, c in enumerate((GOLD, PINK, SKY)):                                    # three reels
        cv.rect(11 + i * 4, 12, 13 + i * 4, 15, c)
    cv.poly([(5, 19), (26, 19), (27, 23), (4, 23)], PURPLE_D)                    # control deck
    cv.rect(9, 20, 10, 21, INK[:3]); cv.oval(8, 17, 11, 20, RED)                 # joystick
    cv.oval(15, 20, 17, 22, YEL); cv.oval(19, 20, 21, 22, GREEN)
    cv.rect(13, 25, 18, 27, INK[:3]); cv.rect(15, 25, 16, 27, GOLD)              # coin slot
    return finish(cv)


def icon_index():
    cv = Canvas()
    cv.poly([(4, 5), (15, 7), (15, 28), (4, 26)], PURPLE)                        # left page block
    cv.poly([(16, 7), (27, 5), (27, 26), (16, 28)], PURPLE_D)
    cv.poly([(6, 7), (14, 9), (14, 26), (6, 24)], WHITE)                         # pages
    cv.poly([(17, 9), (25, 7), (25, 24), (17, 26)], (236, 230, 255))
    for y in (12, 15, 18, 21):
        cv.line([(7, y), (12, y + 1)], GREY)
    star = [(21, 9), (22, 13), (25, 13), (23, 15), (24, 19), (21, 17), (18, 19), (19, 15), (17, 13), (20, 13)]
    cv.poly(star, GOLD)
    cv.rect(15, 5, 16, 29, INK[:3])                                              # spine
    return finish(cv)


def icon_gift():
    cv = Canvas()
    cv.rect(5, 14, 26, 28, RED)                                                  # box
    cv.rect(3, 10, 28, 15, RED_D)                                                # lid
    cv.rect(14, 10, 17, 28, GOLD)                                                # ribbon
    cv.rect(3, 12, 28, 13, GOLD)
    cv.poly([(15, 10), (8, 3), (6, 6), (9, 10)], GOLD)                           # bow
    cv.poly([(16, 10), (23, 3), (25, 6), (22, 10)], GOLD)
    cv.rect(14, 8, 17, 10, GOLD_D)
    return finish(cv)


def icon_rewards():
    cv = Canvas()
    cv.rect(4, 7, 27, 28, WHITE)                                                 # page
    cv.rect(4, 7, 27, 12, GREEN)                                                 # header
    cv.rect(8, 4, 10, 9, GREY_D); cv.rect(21, 4, 23, 9, GREY_D)                  # rings
    for r in range(3):
        for c in range(4):
            x, y = 7 + c * 5, 15 + r * 4
            cv.rect(x, y, x + 2, y + 2, GREY if (r, c) != (2, 3) else GOLD)
    for r, c in ((0, 0), (0, 1), (0, 2), (0, 3), (1, 0)):                         # ticks
        x, y = 7 + c * 5, 15 + r * 4
        cv.rect(x, y, x + 2, y + 2, GREEN)
    cv.poly([(22, 22), (29, 22), (29, 29), (22, 29)], GOLD)                      # day-7 star box
    cv.poly([(25, 23), (26, 25), (28, 25), (26, 26), (27, 28), (25, 27), (23, 28), (24, 26), (22, 25), (24, 25)], WHITE)
    return finish(cv)


def icon_settings():
    cv = Canvas()
    cx, cy = 16, 16
    pts = []
    for i in range(16):
        a = i * math.pi / 8
        r = 13 if i % 2 == 0 else 10
        for da in (-0.17, 0.17):
            pts.append((cx + r * math.cos(a + da), cy + r * math.sin(a + da)))
    cv.poly(pts, GREY)
    cv.oval(7, 7, 25, 25, GREY)
    cv.oval(11, 11, 21, 21, GREY_D)
    cv.oval(13, 13, 19, 19, (0, 0, 0))
    d = np.array(cv.img); yy, xx = np.mgrid[0:N, 0:N]; d[(xx - 16) ** 2 + (yy - 16) ** 2 <= 8] = 0
    cv.img = Image.fromarray(d)
    return finish(cv)


def icon_featured():
    cv = Canvas()
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 14 if i % 2 == 0 else 6
        pts.append((16 + r * math.cos(a), 17 + r * math.sin(a)))
    cv.poly(pts, GOLD)
    cv.poly([(16, 6), (19, 13), (16, 18), (13, 13)], GOLD_L)
    return finish(cv)


def icon_ticket():
    cv = Canvas()
    cv.poly([(2, 10), (27, 4), (28, 10), (26, 13), (29, 17), (30, 23), (5, 29), (4, 23), (6, 20), (3, 16)], YEL)
    cv.poly([(19, 7), (20, 7), (24, 25), (23, 25)], GOLD_D)                      # tear line
    for i in range(4):
        cv.px(21, 9 + i * 4, GOLD_D)
    star = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 6 if i % 2 == 0 else 2.6
        star.append((11.5 + r * math.cos(a), 17.5 + r * math.sin(a)))
    cv.poly(star, RED)
    return finish(cv)


def icon_token():
    cv = Canvas()
    for y in range(N):
        for x in range(N):
            dx, dy = x + 0.5 - 16, y + 0.5 - 16
            d = math.hypot(dx, dy)
            if d <= 13:
                if d > 9.5:
                    h = (math.atan2(dy, dx) / (2 * math.pi)) % 1
                    import colorsys
                    c = tuple(int(v * 255) for v in colorsys.hsv_to_rgb(h, 0.75, 1))
                else:
                    c = PURPLE if d > 7 else PINK
                cv.px(x, y, c)
    cv.poly([(16, 9), (18, 14), (23, 16), (18, 18), (16, 23), (14, 18), (9, 16), (14, 14)], WHITE)
    return finish(cv)


def icon_daily():
    cv = Canvas()
    cv.oval(4, 4, 27, 27, BLUE)
    cv.oval(7, 7, 24, 24, WHITE)
    cv.line([(16, 16), (16, 9)], INK[:3], 2)
    cv.line([(16, 16), (21, 18)], INK[:3], 2)
    cv.poly([(22, 1), (29, 5), (23, 9)], GREEN)                                  # refresh arrow
    cv.poly([(9, 30), (2, 26), (8, 22)], GREEN)
    return finish(cv)


def icon_pass():
    cv = Canvas()
    cv.poly([(3, 8), (29, 8), (29, 25), (3, 25)], GOLD)
    cv.rect(3, 8, 29, 12, ORANGE)
    cv.rect(6, 15, 13, 22, WHITE)                                                # photo
    cv.oval(8, 16, 11, 19, SKIN); cv.rect(7, 20, 12, 22, BLUE)
    for y in (16, 19):
        cv.line([(16, y), (26, y)], GOLD_D, 2)
    cv.line([(16, 22), (22, 22)], GOLD_D, 2)
    cv.poly([(24, 3), (26, 7), (30, 7), (27, 10), (28, 14), (24, 12), (20, 14), (21, 10), (18, 7), (22, 7)], PINK)
    return finish(cv)


def icon_looks():
    cv = Canvas()
    cv.oval(3, 3, 28, 28, PINK_L)                                                # aura
    cv.oval(7, 7, 24, 24, PINK)
    def spark(x, y, r, c):
        cv.poly([(x, y - r), (x + r * 0.3, y - r * 0.3), (x + r, y), (x + r * 0.3, y + r * 0.3), (x, y + r),
                 (x - r * 0.3, y + r * 0.3), (x - r, y), (x - r * 0.3, y - r * 0.3)], c)
    spark(16, 16, 9, WHITE)
    spark(25, 7, 4, YEL)
    spark(7, 25, 3, YEL)
    return finish(cv)


def icon_sword():
    cv = Canvas()
    cv.poly([(26, 2), (29, 2), (29, 5), (13, 21), (10, 18)], STEEL)              # blade
    cv.poly([(27, 3), (28, 3), (12, 19), (11, 18)], STEEL_L)
    cv.poly([(6, 17), (9, 14), (17, 22), (14, 25)], GOLD)                        # guard
    cv.poly([(9, 21), (11, 23), (6, 28), (4, 26)], BROWN)                        # grip
    cv.oval(1, 27, 5, 31, GOLD)                                                  # pommel
    return finish(cv)


def icon_title():
    cv = Canvas()
    cv.poly([(2, 10), (24, 10), (30, 16), (24, 22), (2, 22)], TEAL)
    cv.oval(22, 14, 26, 18, WHITE)
    for y, w in ((13, 16), (16, 12), (19, 14)):
        cv.line([(5, y), (5 + w, y)], WHITE if y == 13 else (190, 240, 235), 2)
    return finish(cv)


def icon_crown():
    cv = Canvas()
    cv.poly([(3, 10), (9, 17), (16, 6), (23, 17), (29, 10), (27, 25), (5, 25)], GOLD)
    cv.rect(5, 22, 27, 26, GOLD_D)
    for x, c in ((10, RED), (16, BLUE), (22, GREEN)):
        cv.oval(x - 2, 21, x + 2, 25, c)
    for x, y in ((3, 9), (16, 5), (29, 9)):
        cv.oval(x - 2, y - 2, x + 2, y + 2, WHITE)
    return finish(cv)


def icon_trophy():
    cv = Canvas()
    cv.poly([(8, 4), (24, 4), (23, 14), (19, 18), (13, 18), (9, 14)], GOLD)      # cup
    cv.oval(2, 6, 10, 14, GOLD); cv.oval(4, 8, 8, 12, (0, 0, 0))                 # handles
    cv.oval(22, 6, 30, 14, GOLD); cv.oval(24, 8, 28, 12, (0, 0, 0))
    cv.rect(14, 18, 18, 22, GOLD_D)
    cv.rect(9, 22, 23, 28, BROWN)
    cv.rect(12, 24, 20, 26, GOLD)
    d = np.array(cv.img)
    for (x0, y0, x1, y1) in ((4, 8, 8, 12), (24, 8, 28, 12)):
        sub = d[y0:y1 + 1, x0:x1 + 1]; sub[(sub[..., :3] == 0).all(-1)] = 0
    cv.img = Image.fromarray(d); cv.d = ImageDraw.Draw(cv.img)
    cv.rect(8, 4, 24, 5, GOLD)
    return finish(cv)


def icon_revive():
    cv = Canvas()
    cv.poly([(2, 12), (8, 8), (11, 13), (7, 18)], WHITE)                         # wings
    cv.poly([(30, 12), (24, 8), (21, 13), (25, 18)], WHITE)
    cv.oval(6, 7, 17, 18, RED); cv.oval(15, 7, 26, 18, RED)                      # heart
    cv.poly([(7, 14), (25, 14), (16, 27)], RED)
    cv.rect(14, 10, 18, 21, WHITE); cv.rect(11, 13, 21, 17, WHITE)               # plus
    return finish(cv)


def icon_spin():
    cv = Canvas()
    cols = (RED, GOLD, GREEN, BLUE, PURPLE, PINK)
    for i, c in enumerate(cols):
        a0, a1 = i * 60 - 90, (i + 1) * 60 - 90
        cv.d.pieslice([3, 4, 29, 30], a0, a1, fill=(*c, 255))
    cv.oval(13, 14, 19, 20, WHITE)
    cv.poly([(13, 0), (19, 0), (16, 6)], INK[:3])
    cv.poly([(14, 1), (18, 1), (16, 4)], YEL)
    return finish(cv)


def icon_bossrush():
    cv = Canvas()
    for flip in (False, True):
        def P(x, y):
            return (31 - x, y) if flip else (x, y)
        cv.poly([P(25, 2), P(29, 2), P(29, 6), P(12, 22), P(9, 19)], STEEL)
        cv.poly([P(5, 18), P(8, 15), P(15, 22), P(12, 25)], GOLD if not flip else RED)
        cv.poly([P(8, 22), P(10, 24), P(5, 29), P(3, 27)], BROWN)
    return finish(cv)


def icon_clover():
    cv = Canvas()
    cv.line([(16, 18), (19, 24), (24, 30)], GREEN_D, 3)                          # stem
    for (x, y) in ((16, 9), (23, 16), (16, 23), (9, 16)):
        cv.oval(x - 6, y - 6, x + 6, y + 6, GREEN)                               # four round leaves
    for (x, y) in ((16, 9), (23, 16), (16, 23), (9, 16)):
        cv.line([(16, 16), (x, y)], GREEN_D)
    cv.oval(12, 4, 15, 7, GREEN_L)
    return finish(cv)


def icon_playtime():
    cv = Canvas()
    cv.rect(13, 1, 18, 4, GREY_D)
    cv.rect(24, 5, 27, 8, GREY_D)
    cv.oval(4, 5, 27, 29, GOLD)
    cv.oval(7, 8, 24, 26, WHITE)
    cv.d.pieslice([8, 9, 23, 25], -90, 30, fill=(*SKY, 255))
    cv.line([(16, 17), (16, 10)], INK[:3], 2)
    cv.line([(16, 17), (21, 19)], INK[:3], 2)
    return finish(cv)


def icon_friends():
    cv = Canvas()
    cv.oval(3, 7, 13, 17, SKIN); cv.poly([(1, 29), (2, 20), (8, 17), (14, 20), (15, 29)], TEAL)
    cv.oval(16, 4, 27, 15, YEL); cv.poly([(13, 29), (14, 18), (21, 15), (28, 18), (30, 29)], PINK)
    cv.rect(6, 11, 7, 12, INK[:3]); cv.rect(10, 11, 11, 12, INK[:3])
    cv.rect(19, 8, 20, 9, INK[:3]); cv.rect(23, 8, 24, 9, INK[:3])
    cv.line([(19, 12), (24, 12)], INK[:3])
    return finish(cv)


def icon_spire():
    cv = Canvas()
    cv.poly([(16, 1), (22, 12), (10, 12)], PURPLE_L)
    cv.poly([(11, 12), (21, 12), (23, 29), (9, 29)], PURPLE)
    cv.rect(7, 26, 25, 30, PURPLE_D)
    for y in (15, 20):
        cv.rect(14, y, 17, y + 3, YEL)
    cv.oval(14, 3, 18, 7, YEL)
    return finish(cv)


def icon_lock():
    cv = Canvas()
    cv.oval(8, 3, 23, 18, GREY)
    cv.oval(11, 6, 20, 15, (0, 0, 0))
    cv.rect(5, 13, 26, 29, GOLD)
    cv.oval(14, 17, 18, 21, INK[:3]); cv.rect(15, 20, 16, 25, INK[:3])
    d = np.array(cv.img); sub = d[6:16, 11:21]; sub[(sub[..., :3] == 0).all(-1) & (sub[..., 3] > 0)] = 0
    cv.img = Image.fromarray(d)
    return finish(cv)


def icon_codes():
    cv = Canvas()
    cv.oval(3, 3, 16, 16, GOLD); cv.oval(7, 7, 12, 12, (0, 0, 0))                # key ring
    cv.poly([(13, 12), (16, 15), (28, 27), (25, 30), (12, 17)], GOLD)             # shaft
    cv.poly([(20, 22), (23, 19), (26, 22), (23, 25)], GOLD_D)                     # teeth
    cv.poly([(24, 26), (27, 23), (29, 25), (26, 28)], GOLD_D)
    d = np.array(cv.img); sub = d[7:13, 7:13]; sub[(sub[..., :3] == 0).all(-1) & (sub[..., 3] > 0)] = 0
    cv.img = Image.fromarray(d)
    return finish(cv)


def icon_updates():
    cv = Canvas()
    cv.rect(3, 5, 25, 28, WHITE)
    cv.rect(25, 9, 29, 28, GREY)
    cv.rect(5, 7, 23, 11, RED)
    cv.rect(5, 13, 13, 20, SKY)
    for y in (13, 16, 19, 22, 25):
        cv.line([(15, y), (23, y)] if y < 22 else [(5, y), (23, y)], GREY_D)
    return finish(cv)


def icon_flask():
    cv = Canvas()
    cv.rect(13, 2, 18, 5, BROWN)                                                 # cork
    cv.rect(12, 5, 19, 11, (205, 225, 255))                                      # neck
    cv.oval(5, 9, 26, 30, (205, 225, 255))                                       # bottle
    cv.oval(7, 15, 24, 28, RED)                                                  # potion
    cv.rect(7, 15, 24, 19, (205, 225, 255))
    cv.oval(10, 13, 13, 16, WHITE)
    return finish(cv)


def icon_bolt():
    cv = Canvas()
    cv.poly([(19, 1), (6, 18), (15, 18), (11, 31), (26, 12), (17, 12), (22, 1)], YEL)
    cv.poly([(19, 3), (10, 15), (13, 15)], WHITE)
    return finish(cv)


ICONS = {
    'Shop': icon_shop, 'Bag': icon_bag, 'Arcade': icon_arcade, 'Index': icon_index, 'Gift': icon_gift,
    'Rewards': icon_rewards, 'Settings': icon_settings, 'Featured': icon_featured, 'Tickets': icon_ticket,
    'Tokens': icon_token, 'Daily': icon_daily, 'Passes': icon_pass, 'Looks': icon_looks, 'Weapons': icon_sword,
    'Titles': icon_title, 'Bosses': icon_crown, 'Goals': icon_trophy, 'Revive': icon_revive, 'Spin': icon_spin,
    'BossRush': icon_bossrush, 'Luck': icon_clover, 'Playtime': icon_playtime, 'Friends': icon_friends,
    'Spire': icon_spire, 'Lock': icon_lock, 'Codes': icon_codes, 'Updates': icon_updates,
    'Flask': icon_flask, 'Bolt': icon_bolt,
}


def big(img, size=256):
    return img.resize((size, size), Image.NEAREST)


def main():
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for name, fn in ICONS.items():
        img = fn()
        big(img).save(os.path.join(OUT, name + '.png'))
        made[name] = img
    # a contact sheet
    cols, cell = 7, 150
    rows = (len(made) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell, rows * (cell + 24)), (22, 18, 42))
    d = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(made.items()):
        x, y = (i % cols) * cell, (i // cols) * (cell + 24)
        sheet.paste(big(img, 128), (x + 11, y + 8), big(img, 128))
        d.text((x + 11, y + 140), name, fill=(230, 225, 250))
    sheet.save(os.path.join(ROOT, 'Docs', 'ui_icons.png'))
    print('saved', len(made), 'icons to', OUT, 'and Docs/ui_icons.png')
    if '--sketch' in sys.argv:
        for name, img in made.items():
            buf = io.BytesIO()
            big(img, 64).save(buf, 'PNG', optimize=True)
            print(name, 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode())


if __name__ == '__main__':
    main()
