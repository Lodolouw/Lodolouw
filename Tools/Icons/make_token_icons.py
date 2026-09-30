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

def holo(t=0.0):
    """THE HOLO TOKEN: a rainbow rim that runs round it, a deep purple face,
    a glowing gold star with a gem in it. `t` (0 to 1) is where it is in its
    loop: the rainbow turns, a shine sweeps across, the sparkles twinkle."""
    img = blank()
    cx, cy, r = 24, 22, 19
    edge(img, cx, cy, r, 3, (70, 20, 90))
    for x, y, dx, dy, d in each(cx, cy, r):
        a = math.atan2(dy, dx)
        if d > 14.5:  # the rainbow rim, brighter to the top left
            lit = 0.75 + 0.25 * (-(dx + dy) / (d * 1.41))
            put(img, x, y, hue(a / (2 * math.pi) + 0.1 + t, 0.75, band(lit, [0.75, 0.9, 1.0])))
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
    # the shine: a bright diagonal band sweeping across (in the first half of the loop)
    sweep = -24 + t * 2 * 60
    for x, y, dx, dy, d in each(cx, cy, r):
        k = (dx + dy) - sweep
        if -2.2 < k < 2.2:
            c = img[y, x, :3].astype(float)
            put(img, x, y, c + (255 - c) * (0.75 if abs(k) < 1 else 0.4))
    outline(img)
    # the sparkles twinkle, each in its own time
    for (sx, sy, big, col, phase) in ((41, 6, 3, (255, 255, 255), 0.0), (6, 36, 2, (255, 240, 120), 0.35), (43, 38, 2, (140, 240, 255), 0.7)):
        w = math.sin((t + phase) * 2 * math.pi)
        if w > -0.2:
            sparkle(img, sx, sy, max(1, round(big * (0.5 + 0.5 * w))), col)
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

def coin(t=0.0):
    """THE COIN, alive: thick shining gold with our slime stamped on it. A
    soft shine sweeps across, the slime blinks, a glint twinkles (quieter
    than the token: the token's the special one)."""
    img = blank()
    cx, cy, r = 24, 22, 18
    edge(img, cx, cy, r, 3, (150, 70, 10))
    for x, y, dx, dy, d in each(cx, cy, r):
        k = (-(dx * 0.6 + dy * 0.8) / r + 1) / 2
        if d > 14.2:
            put(img, x, y, band(k, [(196, 106, 24), (240, 160, 34), (255, 212, 70), (255, 240, 160)]))
        elif d > 13:
            put(img, x, y, (160, 80, 16))
        else:
            put(img, x, y, band(k, [(214, 124, 26), (246, 170, 44), (255, 204, 74)]))
    # the slime stamp: a gooey blob with eyes (they blink in one frame of the loop)
    blink = 0.55 <= (t % 1) < 0.68
    slime = [
        "......####......",
        "....########....",
        "...##########...",
        "..############..",
        ".##############.",
        ".##WW######WW##.",
        "###WK######WK###",
        "###WK######WK###",
        "################",
        "################",
        ".##############.",
        "..############..",
    ]
    for j, row in enumerate(slime):
        for i, ch in enumerate(row):
            x, y = 16 + i, 15 + j
            if ch == '.':
                continue
            if ch == '#' or (blink and ch in 'WK'):
                c = (99, 199, 77) if j < 7 else (62, 150, 60)
                if blink and ch in 'WK':
                    c = (40, 110, 40) if ch == 'K' and j == 7 else (99, 199, 77)
                put(img, x + 1, y + 1, (150, 80, 16))
                put(img, x, y, c)
            elif ch == 'W':
                put(img, x, y, (255, 255, 255))
            elif ch == 'K':
                put(img, x, y, INK)
    for i in range(3):
        put(img, 19 + i, 16, (170, 240, 150))
    # the soft shine
    sweep = -24 + t * 2 * 60
    for x, y, dx, dy, d in each(cx, cy, r):
        k = (dx + dy) - sweep
        if -1.8 < k < 1.8:
            c = img[y, x, :3].astype(float)
            put(img, x, y, c + (255 - c) * (0.55 if abs(k) < 0.9 else 0.25))
    outline(img)
    w = math.sin((t + 0.2) * 2 * math.pi)
    if w > 0:
        sparkle(img, 40, 8, max(1, round(2 * w)))
    return img


def holo_loop(frames=8, scale=4):
    """the Holo token's loop: a sprite sheet for the game (4 across, 2 down,
    frames in reading order) and an animated picture to look at"""
    pics = [Image.fromarray(holo(i / frames), 'RGBA').resize((N * scale, N * scale), Image.NEAREST) for i in range(frames)]
    cols = 4
    sheet = Image.new('RGBA', (cols * N * scale, (frames // cols) * N * scale), (0, 0, 0, 0))
    for i, p in enumerate(pics):
        sheet.paste(p, ((i % cols) * N * scale, (i // cols) * N * scale))
    sheet.save(os.path.join(OUT, 'Token_Holo_Sheet.png'))
    # the preview: on the window look's purple, a gentle bob too (the game does that part in code)
    gif = []
    for j in range(frames * 3):
        i = j % frames
        bg = Image.new('RGBA', (320, 320), (116, 40, 232, 255))
        bob = round(math.sin(j / (frames * 3) * 2 * math.pi * 2) * 6)
        big = pics[i].resize((256, 256), Image.NEAREST)
        bg.alpha_composite(big, (32, 32 + bob))
        gif.append(bg.convert('P', palette=Image.ADAPTIVE))
    gif[0].save(os.path.join(ROOT, 'Docs', 'token_holo.gif'), save_all=True, append_images=gif[1:], duration=90, loop=0, disposal=2)
    print('saved the Holo loop')


def money_frames(frames=8, scale=4):
    """each living icon's frames on their own (the uploader uploads them; the
    game flips through them): out/money/Coin_1.png .. Token_8.png, and a
    preview of both side by side"""
    folder = os.path.join(OUT, 'money')
    os.makedirs(folder, exist_ok=True)
    sets = {'Coin': coin, 'Token': holo}
    pics = {}
    for name, fn in sets.items():
        pics[name] = []
        for i in range(frames):
            p = Image.fromarray(fn(i / frames), 'RGBA').resize((N * scale, N * scale), Image.NEAREST)
            p.save(os.path.join(folder, '%s_%d.png' % (name, i + 1)))
            pics[name].append(p)
    gif = []
    for j in range(frames * 3):
        i = j % frames
        bg = Image.new('RGBA', (600, 320), (116, 40, 232, 255))
        d = ImageDraw.Draw(bg)
        for x in range(0, 600, 64):
            d.line([(x, 0), (x, 320)], fill=(152, 94, 255), width=2)
        for y in range(0, 320, 64):
            d.line([(0, y), (600, y)], fill=(152, 94, 255), width=2)
        bob = round(math.sin(j / (frames * 3) * 2 * math.pi * 2) * 5)
        bg.alpha_composite(pics['Coin'][i].resize((240, 240), Image.NEAREST), (30, 40 - bob))
        bg.alpha_composite(pics['Token'][i].resize((240, 240), Image.NEAREST), (330, 40 + bob))
        gif.append(bg.convert('P', palette=Image.ADAPTIVE))
    gif[0].save(os.path.join(ROOT, 'Docs', 'money_icons.gif'), save_all=True, append_images=gif[1:], duration=90, loop=0, disposal=2)
    print('saved the money frames')


if __name__ == '__main__':
    main()
    holo_loop()
    money_frames()
