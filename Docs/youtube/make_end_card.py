"""The end card for the "not releasing my game until..." Shorts: 3 seconds,
1080 x 1920 (a Short), in the game's pixel style. Oozlet drops in and bounces,
LIKE TO UNLOCK THE GAME! pops up, a goal bar with a padlock fills a little,
and SUBSCRIBE / DAY 2 TOMORROW! come in last. Everything that matters stays
clear of where YouTube puts its own buttons (down the right side) and the
video's title (along the bottom).

    python3 make_end_card.py                 -> end_card_day2.mp4 and .png
    python3 make_end_card.py --day 3         -> for day 2's video (DAY 3 TOMORROW!)
    python3 make_end_card.py --goal 1K       -> a different likes goal
    python3 make_end_card.py --subs          -> end_card_10k_subs.mp4: the reusable
        2-second card (SUBSCRIBE TO UNLOCK THE GAME!, GOAL: 10K SUBS, no day on it)

Needs Pillow and numpy; the video also needs imageio-ffmpeg
(pip install imageio-ffmpeg) - without it you just get the picture.
"""
import argparse, math, os
import numpy as np
from PIL import Image
from pixel_art import (text_image, oozlet, sparkle, INK, GREEN, LIGHT, YEL, ORANGE, WHITE, RED,
                       DARK_RED, SHADOW, BG1, BG2, BG3)

ap = argparse.ArgumentParser()
ap.add_argument('--day', type=int, default=2, help='the day the card promises for tomorrow')
ap.add_argument('--goal', default='10K', help='the likes goal on the bar')
ap.add_argument('--fill', type=float, default=0.12, help='how full the goal bar ends up (0-1)')
ap.add_argument('--subs', action='store_true', help='the reusable card: a subscribers goal, no day, 2 seconds')
ap.add_argument('--seconds', type=float, default=None, help='how long the video is (3, or 2 with --subs)')
ap.add_argument('--out', default=os.path.dirname(os.path.abspath(__file__)))
ap.add_argument('--preview', default=None, help='also save a strip of frames here (to check it)')
args = ap.parse_args()

W, H, FPS, SECONDS = 1080, 1920, 30, 3.0  # (SECONDS: how long the animation is, in its own time)
LENGTH = args.seconds or (2.0 if args.subs else SECONDS + 0.5)  # how long the video is
# (a shorter video plays the animation faster, finishing a third of a second before the end)
SPEED = max(1.0, SECONDS / max(LENGTH - 0.35, 0.1))
CELL = 12  # the background's pixels
GW, GH = W // CELL, H // CELL
MID = (540, 790)  # Oozlet's middle, and the middle of the rays
SIZE = 18  # Oozlet's pixels


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def ease_out(t):
    t = clamp(t)
    return 1 - (1 - t) ** 3


def pop_scale(t, start, steps):
    """A chunky 8-bit pop: size jumps through `steps`, one every frame, from `start`."""
    if t < start:
        return 0
    i = int((t - start) * FPS)
    return steps[min(i, len(steps) - 1)]


def paste(frame, img, cx, top, scale=1.0, anchor='top'):
    """Paste an RGBA pixel image scaled (nearest, so pixels stay crisp),
    centred on x = cx, with its top (or bottom) edge at y = top."""
    if scale <= 0:
        return
    w, h = max(1, int(round(img.width * scale))), max(1, int(round(img.height * scale)))
    big = img.resize((w, h), Image.NEAREST)
    y = top if anchor == 'top' else top - h
    frame.paste(big, (int(round(cx - w / 2)), int(round(y))), big)


# ----------------------------------------------------------------------
# the pieces, drawn once
# ----------------------------------------------------------------------
yy, xx = np.mgrid[0:GH, 0:GW]
dx, dy = xx + 0.5 - MID[0] / CELL, yy + 0.5 - MID[1] / CELL
ANG, RAD = np.arctan2(dy, dx), np.hypot(dx, dy)
SHADE = np.clip(1.0 - np.maximum(0, (yy - GH * 0.8) / (GH * 0.2)) * 0.35, 0.6, 1.0)[..., None]  # darker at the bottom


def background(t):
    spin = t * 0.35
    ray = ((((ANG + spin + math.pi) % (2 * math.pi)) / (2 * math.pi) * 16).astype(int) % 2) == 0
    near = RAD < 20
    img = np.zeros((GH, GW, 3), float)
    img[:] = BG1
    img[ray & ~near] = BG2
    img[~ray & near] = BG2
    img[ray & near] = BG3
    fade = clamp(t / 0.25)  # (it comes up out of the dark)
    img = (np.array(INK) * (1 - fade) + img * fade) * SHADE
    bg = Image.fromarray(img.astype(np.uint8), 'RGB')
    # sparkles twinkling round the edges
    for i, (sx, sy) in enumerate([(8, 30), (80, 26), (6, 70), (84, 64), (12, 104), (82, 98), (20, 12), (70, 10), (44, 44), (30, 150)]):
        s = math.sin(2 * math.pi * (t * 1.4 + i * 0.37))
        if t > 0.2 and s > 0.1:
            sparkle(bg, sx, sy, big=s > 0.75)
    return bg.resize((W, H), Image.NEAREST)


SPRITE = oozlet().resize((50 * SIZE, 50 * SIZE), Image.NEAREST)
BLINK = oozlet(blink=True).resize((50 * SIZE, 50 * SIZE), Image.NEAREST)
FEET = MID[1] + (43 - 27) * SIZE  # where the bottom of his skirt sits


def shadow_image(width_cells):
    img = Image.new("RGBA", (width_cells, 5), (0, 0, 0, 0))
    px = img.load()
    for y in range(5):
        for x in range(width_cells):
            if ((x + 0.5 - width_cells / 2) / (width_cells / 2)) ** 2 + ((y + 0.5 - 2.5) / 2.5) ** 2 <= 1:
                px[x, y] = SHADOW + (190,)
    return img


def goal_bar(fill):
    """The goal bar, in 10-pixel cells: an ink frame, dark inside, green filling up."""
    cw, ch = 70, 9
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    px = img.load()
    for y in range(ch):
        for x in range(cw):
            edge = x == 0 or y == 0 or x == cw - 1 or y == ch - 1
            px[x, y] = (INK if edge else (20, 22, 48)) + (255,)
    filled = int(round((cw - 2) * clamp(fill)))
    for x in range(1, 1 + filled):
        for y in range(1, ch - 1):
            px[x, y] = (LIGHT if y == 1 else GREEN) + (255,)
    for x in range(8, cw - 1, 8):  # little ticks along it
        px[x, ch - 2] = (INK if x > filled else (45, 105, 60)) + (255,)
    return img


def padlock():
    """A gold padlock, shut (the game's locked until the goal)."""
    rows = [
        "....#####...",
        "...#ooooo#..",
        "..#o#...#o#.",
        "..#o#...#o#.",
        "..#o#...#o#.",
        ".##########.",
        ".#YYYYYYYY#.",
        ".#YwYYYYYY#.",
        ".#YYY##YYY#.",
        ".#YYY##YYY#.",
        ".#YYYY#YYY#.",
        ".#OOOOOOOO#.",
        ".##########.",
    ]
    col = {'#': INK, 'o': (200, 205, 215), 'Y': YEL, 'w': WHITE, 'O': ORANGE}
    img = Image.new("RGBA", (12, len(rows)), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in col:
                px[x, y] = col[c] + (255,)
    return img


def button():
    """The red SUBSCRIBE button, with a darker lip under it (in 10-pixel cells)."""
    cw, ch = 62, 13
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    px = img.load()
    for y in range(ch):
        for x in range(cw):
            corner = (x in (0, cw - 1)) and (y in (0, ch - 1))
            if corner:
                continue
            edge = x == 0 or y == 0 or x == cw - 1 or y == ch - 1
            if edge:
                px[x, y] = INK + (255,)
            elif y >= ch - 3:
                px[x, y] = DARK_RED + (255,)
            else:
                px[x, y] = (RED if y > 2 else (240, 110, 110)) + (255,)
    big = img.resize((cw * 10, ch * 10), Image.NEAREST)
    words = text_image("SUBSCRIBE", fill=WHITE, outline=INK, shadow=DARK_RED)
    words = words.resize((words.width * 8, words.height * 8), Image.NEAREST)
    big.paste(words, ((big.width - words.width) // 2, 18), words)
    return big


# where things sit, top to bottom (the Short's title and channel name cover
# the bottom ~300 pixels on YouTube, and its buttons the right edge)
BAR_Y = 1120
BUTTON_Y = 1390
LINE0 = "SUBSCRIBE TO" if args.subs else None
LINE1 = "UNLOCK" if args.subs else "LIKE TO UNLOCK"
LINE2 = "THE GAME!"
LABEL = "GOAL: %s %s" % (args.goal.upper(), "SUBS" if args.subs else "LIKES")
TOMORROW = None if args.subs else "DAY %d TOMORROW!" % args.day
TITLE0 = text_image(LINE0) if LINE0 else None
TITLE1, TITLE2 = text_image(LINE1), text_image(LINE2)
LOCK, BUTTON = padlock(), button()


def frame_at(t):
    frame = background(t).convert("RGBA")
    # Oozlet drops in, squashes on landing, then bobs gently (and blinks once)
    drop = clamp(t / 0.32)
    fall = -1100 * (1 - drop * drop)
    squash = 0.0
    if 0.32 <= t < 0.56:
        squash = math.sin(math.pi * (t - 0.32) / 0.24)
    bob = -12 * (1 - math.cos(2 * math.pi * max(0.0, t - 0.75) / 1.1)) / 2 if t > 0.75 else 0
    lift = -(fall + bob)
    width = int(34 - min(14, lift / 30))
    shadow = shadow_image(max(18, width)).resize((max(18, width) * SIZE, 5 * SIZE), Image.NEAREST)
    if t > 0.05:
        frame.alpha_composite(shadow, (MID[0] - shadow.width // 2, FEET - 40))
    sprite = BLINK if 2.05 <= t < 2.18 else SPRITE
    sx, sy = 1 + 0.12 * squash, 1 - 0.16 * squash
    w, h = int(sprite.width * sx), int(sprite.height * sy)
    body = sprite.resize((w, h), Image.NEAREST)
    bottom_of_sprite = FEET + (50 - 43) * SIZE * sy  # (the sprite goes a few rows below his feet)
    frame.alpha_composite(body, (MID[0] - w // 2, int(bottom_of_sprite - h + fall + bob)))
    # LIKE TO UNLOCK / THE GAME! (or SUBSCRIBE TO / UNLOCK / THE GAME!)
    if TITLE0:
        paste(frame, TITLE0, W / 2, 105, pop_scale(t, 0.2, [3, 7, 11, 10, 9]))
        paste(frame, TITLE1, W / 2, 205, pop_scale(t, 0.3, [4, 9, 14, 13, 12]))
        paste(frame, TITLE2, W / 2, 335, pop_scale(t, 0.42, [5, 11, 17, 15, 14]))
    else:
        paste(frame, TITLE1, W / 2, 170, pop_scale(t, 0.28, [3, 7, 12, 11, 10]))
        paste(frame, TITLE2, W / 2, 290, pop_scale(t, 0.42, [5, 11, 18, 16, 15]))
    # the goal bar wipes in and fills a little; the padlock drops onto its end
    if t >= 0.9:
        bar = goal_bar(args.fill * ease_out((t - 1.05) / 0.5)).resize((700, 90), Image.NEAREST)
        shown = int(700 * ease_out((t - 0.9) / 0.2))
        if shown > 0:
            frame.alpha_composite(bar.crop((0, 0, shown, 90)), (90, BAR_Y))
    if t >= 0.95:
        k = clamp((t - 0.95) / 0.18)
        drop_y = -300 * (1 - k * k)
        wiggle = 7 * math.sin((t - 1.5) * 40) if 1.5 <= t < 1.8 else 0
        paste(frame, LOCK, 842 + wiggle, BAR_Y - 30 + drop_y, 10)
    if t >= 1.1:
        label = text_image(LABEL, fill=WHITE, shadow=(30, 30, 60), chars=int((t - 1.1) / 0.03))
        paste(frame, label, 445, BAR_Y + 115, 7)
    # SUBSCRIBE pops in and then pulses
    scale = pop_scale(t, 1.45, [0.3, 0.8, 1.15, 1.05, 1.0])
    if t > 1.62:
        scale = 1 + 0.04 * math.sin(2 * math.pi * (t - 1.62) / 0.7)
    if scale > 0:
        paste(frame, BUTTON, 470, BUTTON_Y - BUTTON.height * scale / 2, scale)  # (centred on BUTTON_Y)
    if TOMORROW and t >= 1.7:
        tomorrow = text_image(TOMORROW, fill=YEL, chars=int((t - 1.7) / 0.035))
        paste(frame, tomorrow, 470, BUTTON_Y + 90, 7)
    return frame.convert("RGB")


frames = int(round(LENGTH * FPS))
base = os.path.join(args.out, ("end_card_%s_subs" % args.goal.lower()) if args.subs else ("end_card_day%d" % args.day))
last = frame_at(SECONDS)
last.save(base + ".png")
print("saved", base + ".png")

if args.preview:
    marks = [0.15, 0.36, 0.5, 1.0, 1.5, 3.0]
    thumbs = [frame_at(m).resize((270, 480), Image.LANCZOS) for m in marks]
    strip = Image.new("RGB", (len(thumbs) * 280 + 10, 490), (15, 15, 15))
    for i, th in enumerate(thumbs):
        strip.paste(th, (10 + i * 280, 5))
    strip.save(args.preview)
    print("saved", args.preview)

try:
    import imageio_ffmpeg
except ImportError:
    print("no imageio-ffmpeg: picture only (pip install imageio-ffmpeg for the video)")
else:
    # (1080 x 1920 exactly: both are even, which is all this video format needs)
    writer = imageio_ffmpeg.write_frames(base + ".mp4", (W, H), fps=FPS, quality=9, codec="libx264", macro_block_size=1,
                                         output_params=["-tune", "animation", "-movflags", "+faststart"])
    writer.send(None)
    for i in range(frames):  # (the animation sped up to fit, then the finished card held)
        writer.send(np.asarray(frame_at(min(SECONDS, i / FPS * SPEED))).tobytes())
    writer.close()
    print("saved", base + ".mp4")
