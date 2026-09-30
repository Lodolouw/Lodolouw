"""The game's money icons, drawn as pixel art in code: COINS (gold) and
ARCADE TOKENS (the Arcade's spin money). A few designs of each, 32 x 32
pixels scaled up to 256 x 256 with a dark outline so they read on any colour.

    python3 make_currency_icons.py     -> out/<Name>.png and Docs/currency_icons.png
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'out')
N = 32
INK = (24, 20, 37)

def blank():
    return np.zeros((N, N, 4), np.uint8)

def put(img, x, y, c):
    if 0 <= x < N and 0 <= y < N:
        img[y, x] = (*c, 255)

def disc(img, cx, cy, r, shades, light=(-0.6, -0.8)):
    """a shaded disc: shades = (dark, mid, light), lit from the top left"""
    for y in range(N):
        for x in range(N):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d <= r:
                k = (dx * light[0] + dy * light[1]) / max(r, 1)
                c = shades[2] if k > 0.35 else (shades[0] if k < -0.35 else shades[1])
                put(img, x, y, c)

def ring(img, cx, cy, r0, r1, c):
    for y in range(N):
        for x in range(N):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if r0 <= d <= r1:
                put(img, x, y, c)

def star(img, cx, cy, r, c, inner=0.45):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    m = Image.new('L', (N * 8, N * 8), 0)
    ImageDraw.Draw(m).polygon([(x * 8, y * 8) for x, y in pts], fill=255)
    m = np.array(m.resize((N, N), Image.BOX))
    for y in range(N):
        for x in range(N):
            if m[y, x] > 110:
                put(img, x, y, c)

def pixels(img, x0, y0, rows, palette):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in palette:
                put(img, x0 + i, y0 + j, palette[ch])

def outline(img, c=INK):
    a = img[:, :, 3] > 0
    grow = a.copy()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        grow |= np.roll(np.roll(a, dy, 0), dx, 1)
    out = img.copy()
    edge = grow & ~a
    out[edge] = (*c, 255)
    return out

def shine(img, pts, c=(255, 255, 255)):
    for x, y in pts:
        put(img, x, y, c)

GOLD = ((196, 110, 30), (254, 174, 52), (254, 231, 97))
GOLD_RIM = (162, 84, 26)

# ---------------- coins ----------------
def coin_star():
    img = blank()
    disc(img, 16, 16, 13.5, GOLD)
    ring(img, 16, 16, 10.2, 11.2, GOLD_RIM)
    star(img, 16, 16.6, 7.5, (254, 231, 97))
    star(img, 16.6, 17.2, 7.5, GOLD_RIM)   # (its shadow)
    star(img, 16, 16.6, 7.5, (255, 243, 160))
    shine(img, [(8, 9), (9, 8), (8, 10), (10, 7)])
    return outline(img)

def coin_slime():
    img = blank()
    disc(img, 16, 16, 13.5, GOLD)
    ring(img, 16, 16, 10.2, 11.2, GOLD_RIM)
    # a little slime blob with two eyes, stamped on the coin
    pixels(img, 10, 10, [
        "....####....",
        "..########..",
        ".##########.",
        ".##WK##WK##.",
        "###WK##WK###",
        "############",
        "############",
        ".##########.",
    ], {'#': (99, 199, 77), 'W': (255, 255, 255), 'K': INK})
    shine(img, [(8, 9), (9, 8), (8, 10), (10, 7)])
    return outline(img)

def coin_stack():
    img = blank()
    for i, cy in enumerate((24, 19, 14)):
        for y in range(N):
            for x in range(N):
                dx, dy = (x + 0.5 - 16) / 11, (y + 0.5 - cy) / 4.2
                if dx * dx + dy * dy <= 1:
                    put(img, x, y, GOLD[1] if dy < 0.2 else GOLD[0])
        for x in range(6, 27):  # (each coin's rim)
            put(img, x, cy + 3, GOLD_RIM)
    disc(img, 16, 11, 9, GOLD)
    ring(img, 16, 11, 6.3, 7.2, GOLD_RIM)
    pixels(img, 14, 7, [".##.", "#..#", "..#.", ".#..", "####"], {'#': GOLD_RIM})
    shine(img, [(11, 6), (12, 5)])
    return outline(img)

# ---------------- arcade tokens ----------------
PURPLE = ((104, 56, 108), (181, 80, 136), (247, 118, 180))

def token_star():
    img = blank()
    disc(img, 16, 16, 14, GOLD)
    # the notches round the rim, like a real arcade token
    for i in range(12):
        a = i * math.pi / 6
        put(img, round(16 + math.cos(a) * 13.3 - 0.5), round(16 + math.sin(a) * 13.3 - 0.5), GOLD_RIM)
    disc(img, 16, 16, 10.5, PURPLE)
    star(img, 16.6, 17.2, 7, (70, 30, 80))
    star(img, 16, 16.6, 7, (254, 231, 97))
    shine(img, [(9, 8), (8, 9), (10, 7)])
    return outline(img)

def token_joystick():
    img = blank()
    disc(img, 16, 16, 14, ((0, 110, 160), (44, 170, 235), (140, 230, 255)))
    ring(img, 16, 16, 11.4, 12.4, (0, 80, 130))
    pixels(img, 10, 7, [
        "....RR....",
        "...RRRR...",
        "...RRRW...",
        "....RR....",
        ".....S....",
        ".....S....",
        ".....S....",
        "..BBBBBB..",
        ".BBBBBBBB.",
        ".BBBBBBBB.",
    ], {'R': (255, 0, 68), 'W': (255, 200, 210), 'S': (192, 203, 220), 'B': (24, 20, 37)})
    put(img, 13, 16, (254, 231, 97)); put(img, 18, 16, (99, 199, 77))
    shine(img, [(8, 8), (9, 7), (7, 9)])
    return outline(img)

def token_letter():
    img = blank()
    disc(img, 16, 16, 14, PURPLE)
    ring(img, 16, 16, 11.3, 12.6, (254, 174, 52))
    for i in range(16):
        a = i * math.pi / 8
        put(img, round(16 + math.cos(a) * 13.4 - 0.5), round(16 + math.sin(a) * 13.4 - 0.5), (70, 30, 80))
    pixels(img, 11, 9, [
        "..####..",
        ".######.",
        "##....##",
        "##....##",
        "########",
        "########",
        "##....##",
        "##....##",
        "##....##",
    ], {'#': (254, 231, 97)})
    pixels(img, 12, 10, ["..####..", ".#....#.", "#......#", "#......#", "........", "........", "#......#", "#......#", "#......#"], {})
    shine(img, [(9, 8), (8, 9)])
    return outline(img)

DESIGNS = [
    ('Coin_Star', 'COIN: a star', coin_star),
    ('Coin_Slime', 'COIN: a slime stamp', coin_slime),
    ('Coin_Stack', 'COIN: a stack', coin_stack),
    ('Token_Star', 'TOKEN: notched, a star', token_star),
    ('Token_Joystick', 'TOKEN: a joystick', token_joystick),
    ('Token_Letter', 'TOKEN: a big A', token_letter),
]

def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for key, title, fn in DESIGNS:
        big = Image.fromarray(fn(), 'RGBA').resize((256, 256), Image.NEAREST)
        path = os.path.join(OUT, key + '.png')
        big.save(path)
        made.append((key, title, big))
    font = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
    cols, cell = 3, 300
    sheet = Image.new('RGB', (cols * cell + 40, 2 * (cell + 90) + 90), (116, 40, 232))
    d = ImageDraw.Draw(sheet)
    for x in range(0, sheet.width, 64):
        d.line([(x, 0), (x, sheet.height)], fill=(152, 94, 255), width=2)
    for y in range(0, sheet.height, 64):
        d.line([(0, y), (sheet.width, y)], fill=(152, 94, 255), width=2)
    d.text((sheet.width // 2, 45), 'COIN & TOKEN ICONS  (pick one of each)', font=ImageFont.truetype(font, 34), fill=(255, 255, 255), anchor='mm', stroke_width=3, stroke_fill=INK)
    for i, (key, title, big) in enumerate(made):
        c, r = i % cols, i // cols
        x0, y0 = 20 + c * cell, 90 + r * (cell + 90)
        d.rectangle([x0 + 10, y0 + 10, x0 + cell - 10, y0 + cell - 10], fill=(232, 222, 255), outline=INK, width=4)
        sheet.paste(big, (x0 + 22, y0 + 22), big)
        small = big.resize((48, 48), Image.NEAREST)
        sheet.paste(small, (x0 + cell - 68, y0 + cell - 68), small)
        d.text((x0 + cell // 2, y0 + cell + 22), '%d. %s' % (i + 1, title), font=ImageFont.truetype(font, 20), fill=(255, 255, 255), anchor='mm', stroke_width=3, stroke_fill=INK)
    path = os.path.join(ROOT, 'Docs', 'currency_icons.png')
    sheet.save(path)
    print('saved', path)

if __name__ == '__main__':
    main()
