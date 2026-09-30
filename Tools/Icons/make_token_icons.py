"""SPECIAL ARCADE TOKEN designs: bigger pixel art (48 x 48, scaled to 256)
that pops - a thick coin edge, glowing colours, a rainbow rim, sparkles.

    python3 make_token_icons.py   -> out/Token_*.png and Docs/token_icons.png
"""
import colorsys, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'out')
N = 48
INK = (24, 20, 37)

def blank():
    return np.zeros((N, N, 4), np.uint8)

def put(img, x, y, c):
    if 0 <= x < N and 0 <= y < N:
        img[y, x] = (*[int(v) for v in c], 255)

def each(cx, cy, r):
    for y in range(N):
        for x in range(N):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d <= r:
                yield x, y, dx, dy, d

def band(v, levels):
    return levels[min(len(levels) - 1, max(0, int(v * len(levels))))]

def hue(h, s=0.85, v=1.0):
    return tuple(c * 255 for c in colorsys.hsv_to_rgb(h % 1, s, v))

def star_mask(cx, cy, r, inner=0.45, points=5, rot=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        a = rot + i * math.pi / points
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    m = Image.new('L', (N * 8, N * 8), 0)
    ImageDraw.Draw(m).polygon([(x * 8, y * 8) for x, y in pts], fill=255)
    return np.array(m.resize((N, N), Image.BOX)) > 110

def outline(img, c=INK, width=1):
    for _ in range(width):
        a = img[:, :, 3] > 0
        grow = a.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grow |= np.roll(np.roll(a, dy, 0), dx, 1)
        img[grow & ~a] = (*c, 255)
    return img

def sparkle(img, x, y, size, c=(255, 255, 255)):
    for i in range(-size, size + 1):
        put(img, x + i, y, c)
        put(img, x, y + i, c)

def edge(img, cx, cy, r, depth, dark):
    """the coin's thickness: its edge showing under it"""
    for k in range(depth, 0, -1):
        for x, y, *_ in each(cx, cy + k, r):
            put(img, x, y, dark)

def holo():
    """THE HOLO TOKEN: a rainbow rim that runs round it, a deep purple face,
    a glowing gold star with a gem in it"""
    img = blank()
    cx, cy, r = 24, 22, 19
    edge(img, cx, cy, r, 3, (70, 20, 90))
    for x, y, dx, dy, d in each(cx, cy, r):
        a = math.atan2(dy, dx)
        if d > 14.5:  # the rainbow rim, brighter to the top left
            lit = 0.75 + 0.25 * (-(dx + dy) / (d * 1.41))
            put(img, x, y, hue(a / (2 * math.pi) + 0.1, 0.75, band(lit, [0.75, 0.9, 1.0])))
        elif d > 13.2:
            put(img, x, y, (40, 12, 60))
        else:  # the face: deep purple to magenta
            k = (-(dx * 0.6 + dy * 0.8) / 13 + 1) / 2
            put(img, x, y, band(k, [(62, 18, 96), (104, 30, 150), (150, 50, 200), (190, 80, 230)]))
    # notches in the rim, like a real token
    for i in range(16):
        a = i * math.pi / 8
        for rr in (16.3, 17.3):
            put(img, round(cx + math.cos(a) * rr - 0.5), round(cy + math.sin(a) * rr - 0.5), (255, 255, 255))
    # the star: glow, body, light, and a gem in the middle
    glow = star_mask(cx, cy + 0.5, 11.5, 0.5)
    body = star_mask(cx, cy + 0.5, 10, 0.48)
    lit = star_mask(cx - 0.8, cy - 0.3, 8.2, 0.46)
    for y in range(N):
        for x in range(N):
            if glow[y, x] and not body[y, x]:
                put(img, x, y, (255, 120, 220))
            if body[y, x]:
                put(img, x, y, (230, 140, 20))
            if lit[y, x]:
                put(img, x, y, (254, 214, 70))
    for x, y, dx, dy, d in each(cx, cy + 1, 3.2):
        put(img, x, y, (0, 220, 255) if dy < 0 else (0, 150, 220))
    put(img, cx - 2, cy - 1, (255, 255, 255))
    # shine across the face
    for i in range(6):
        put(img, 11 + i, 12 - i // 2, (255, 255, 255))
    outline(img)
    sparkle(img, 41, 6, 3)
    sparkle(img, 6, 36, 2, (255, 240, 120))
    sparkle(img, 43, 38, 1, (140, 240, 255))
    return img

def jackpot():
    """THE JACKPOT TOKEN: thick shining gold, a ruby heart-shaped gem... a
    ruby 7 in the middle (the slot machine number), rays behind"""
    img = blank()
    cx, cy, r = 24, 22, 18
    # rays behind
    for i in range(12):
        a = i * math.pi / 6
        for rr in range(19, 23):
            put(img, round(cx + math.cos(a) * rr), round(cy + math.sin(a) * rr), (255, 230, 90))
    edge(img, cx, cy, r, 3, (150, 70, 10))
    for x, y, dx, dy, d in each(cx, cy, r):
        k = (-(dx * 0.6 + dy * 0.8) / r + 1) / 2
        if d > 13.5:
            put(img, x, y, band(k, [(200, 110, 20), (240, 160, 30), (255, 210, 60), (255, 245, 170)]))
        elif d > 12.3:
            put(img, x, y, (150, 70, 10))
        else:
            put(img, x, y, band(k, [(220, 120, 20), (250, 170, 40), (255, 205, 70)]))
    seven = [
        "##########",
        "##########",
        "#......###",
        ".......###",
        "......###.",
        ".....###..",
        "....###...",
        "...###....",
        "...###....",
        "..###.....",
        "..###.....",
        "..###.....",
    ]
    for j, row in enumerate(seven):
        for i, ch in enumerate(row):
            if ch == '#':
                put(img, 19 + i + 1, 16 + j + 1, (110, 0, 30))  # shadow
    for j, row in enumerate(seven):
        for i, ch in enumerate(row):
            if ch == '#':
                put(img, 19 + i, 16 + j, (255, 40, 80) if j < 2 or i < 5 else (220, 0, 50))
    for i in range(3):
        put(img, 20 + i, 16, (255, 190, 200))
    for i in range(5):
        put(img, 12 + i, 12 - i // 2, (255, 255, 255))
    outline(img)
    sparkle(img, 40, 7, 3)
    sparkle(img, 8, 38, 2)
    return img

def gem():
    """THE CRYSTAL TOKEN: a cut gem in a gold bezel, glowing cyan and pink"""
    img = blank()
    cx, cy = 24, 22
    edge(img, cx, cy, 19, 3, (120, 60, 10))
    for x, y, dx, dy, d in each(cx, cy, 19):
        k = (-(dx * 0.6 + dy * 0.8) / 19 + 1) / 2
        put(img, x, y, band(k, [(190, 100, 20), (240, 160, 30), (255, 220, 90)]))
    # the gem: an octagon cut into facets
    for x, y, dx, dy, d in each(cx, cy, 14.5):
        if abs(dx) + abs(dy) <= 19:
            a = math.atan2(dy, dx)
            facet = int(((a + math.pi) / (2 * math.pi)) * 8) % 8
            inner = max(abs(dx), abs(dy)) < 6.5
            if inner:
                c = (190, 255, 255) if dx + dy < 0 else (90, 220, 255)
            else:
                c = [(255, 120, 230), (200, 80, 240), (120, 90, 255), (60, 170, 255),
                     (60, 230, 255), (140, 255, 240), (255, 200, 250), (255, 150, 220)][facet]
            put(img, x, y, c)
    for i in range(4):
        put(img, 17 + i, 15 + i // 2, (255, 255, 255))
    outline(img)
    sparkle(img, 41, 7, 3)
    sparkle(img, 7, 7, 2, (255, 200, 250))
    sparkle(img, 42, 40, 2, (140, 240, 255))
    return img

DESIGNS = [('Token_Holo', 'HOLO', holo),
           ('Token_Jackpot', 'JACKPOT 7', jackpot),
           ('Token_Crystal', 'CRYSTAL', gem)]

def main():
    os.makedirs(OUT, exist_ok=True)
    font = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
    cell = 330
    sheet = Image.new('RGB', (3 * cell + 40, cell + 190), (116, 40, 232))
    d = ImageDraw.Draw(sheet)
    for x in range(0, sheet.width, 64):
        d.line([(x, 0), (x, sheet.height)], fill=(152, 94, 255), width=2)
    for y in range(0, sheet.height, 64):
        d.line([(0, y), (sheet.width, y)], fill=(152, 94, 255), width=2)
    d.text((sheet.width // 2, 45), 'SPECIAL ARCADE TOKENS', font=ImageFont.truetype(font, 36), fill=(255, 255, 255), anchor='mm', stroke_width=3, stroke_fill=INK)
    for i, (key, title, fn) in enumerate(DESIGNS):
        big = Image.fromarray(fn(), 'RGBA').resize((288, 288), Image.NEAREST)
        big.save(os.path.join(OUT, key + '.png'))
        x0, y0 = 20 + i * cell, 90
        d.rectangle([x0 + 8, y0 + 8, x0 + cell - 8, y0 + cell - 8], fill=(24, 20, 37), outline=(255, 255, 255), width=4)
        sheet.paste(big, (x0 + 21, y0 + 21), big)
        small = big.resize((54, 54), Image.NEAREST)
        sheet.paste(small, (x0 + cell - 70, y0 + cell - 70), small)
        d.text((x0 + cell // 2, y0 + cell + 30), '%d. %s' % (i + 1, title), font=ImageFont.truetype(font, 24), fill=(255, 255, 255), anchor='mm', stroke_width=3, stroke_fill=INK)
    path = os.path.join(ROOT, 'Docs', 'token_icons.png')
    sheet.save(path)
    print('saved', path)

if __name__ == '__main__':
    main()
