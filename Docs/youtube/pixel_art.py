"""The game's pixel art for YouTube pictures and videos: its colours, its
5 x 7 pixel letters, and Oozlet (the intro's slime prince) as a sprite.

Used by make_icon.py (the channel icon) and make_end_card.py (the end card).
"""
import math
from PIL import Image

# the game's 8-bit palette
INK = (24, 20, 37)
GREEN = (99, 199, 77)
DEEP = (62, 137, 72)
DEEP2 = (45, 105, 60)
LIGHT = (160, 230, 120)
YEL = (254, 231, 97)
ORANGE = (247, 160, 60)
PINK = (246, 117, 122)
WHITE = (255, 255, 255)
RED = (229, 59, 68)
DARK_RED = (140, 30, 45)
SHADOW = (22, 24, 45)
BG1 = (38, 43, 78)
BG2 = (58, 68, 122)
BG3 = (90, 105, 170)

# 5 x 7 pixel letters (the same ones as the game's preview pictures)
FONT = {
    'A': [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    'B': ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    'C': [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
    'D': ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    'E': ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    'F': ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    'G': [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
    'H': ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    'I': ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
    'J': ["  ###", "   # ", "   # ", "   # ", "#  # ", "#  # ", " ##  "],
    'K': ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
    'L': ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    'M': ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    'N': ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    'O': [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    'P': ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    'Q': [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
    'R': ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    'S': [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    'T': ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    'U': ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    'V': ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    'W': ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"],
    'X': ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    'Y': ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
    'Z': ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    '0': [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    '1': ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    '2': [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    '3': ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
    '4': ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    '5': ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    '6': [" ### ", "#    ", "#    ", "#### ", "#   #", "#   #", " ### "],
    '7': ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
    '8': [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    '9': [" ### ", "#   #", "#   #", " ####", "    #", "    #", " ### "],
    '!': ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "],
    '.': ["     ", "     ", "     ", "     ", "     ", "     ", "  #  "],
    "'": ["  #  ", "  #  ", " #   ", "     ", "     ", "     ", "     "],
    ':': ["     ", "  #  ", "     ", "     ", "     ", "  #  ", "     "],
    '+': ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    '-': ["     ", "     ", "     ", "#####", "     ", "     ", "     "],
    '/': ["    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "],
    ',': ["     ", "     ", "     ", "     ", "     ", "  #  ", " #   "],
    '?': [" ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  "],
    ' ': ["     "] * 7,
}


def text_image(s, fill=YEL, outline=INK, shadow=(160, 80, 40), chars=None):
    """Words in pixel letters, one image pixel per letter pixel: filled, with a
    one-pixel dark outline and a drop shadow under it (all RGBA, the rest
    see-through). `chars` shows only the first so many letters (typing)."""
    shown = s if chars is None else s[:max(0, chars)]
    w = 6 * len(s) - 1 + 2
    h = 7 + 2 + 1
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    ink = set()
    for i, ch in enumerate(shown):
        glyph = FONT.get(ch.upper(), FONT[' '])
        for y, row in enumerate(glyph):
            for x, c in enumerate(row):
                if c == '#':
                    ink.add((1 + 6 * i + x, 1 + y))
    # the shadow (one down), then the outline all round, then the letters
    if shadow:
        for (x, y) in ink:
            for dx, dy in [(0, 2), (-1, 2), (1, 2)]:
                if 0 <= x + dx < w and 0 <= y + dy < h and (x + dx, y + dy) not in ink:
                    px[x + dx, y + dy] = shadow + (255,)
    if outline:
        for (x, y) in ink:
            for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)]:
                if 0 <= x + dx < w and 0 <= y + dy < h and (x + dx, y + dy) not in ink:
                    px[x + dx, y + dy] = outline + (255,)
    for (x, y) in ink:
        px[x, y] = fill + (255,)
    return img


def oozlet(blink=False):
    """Oozlet as a 50 x 50 sprite (see-through round it): a soft block of
    slime with a drippy skirt, big shiny eyes, rosy cheeks, a happy open
    smile, the glowing heart inside and his little crown."""
    N = 50
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    px = img.load()

    def put(x, y, c):
        if 0 <= x < N and 0 <= y < N:
            px[x, y] = c + (255,)

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                put(x, y, c)

    def at(x, y):
        return px[x, y][:3] if px[x, y][3] else None

    L, R, T, B = 11, 38, 17, 41

    def inside(x, y):
        if y < T or y > B:
            return False
        if y >= 36:  # the skirt, a bit wider
            return L - 1 <= x <= R + 1
        if x < L or x > R:
            return False
        # the top corners rounded
        for (ccx, ccy) in [(L + 4, T + 4), (R - 4, T + 4)]:
            if (x < L + 4 and ccx == L + 4 or x > R - 4 and ccx == R - 4) and y < T + 4:
                return (x - ccx) ** 2 + (y - ccy) ** 2 <= 4.6 ** 2
        return True

    body = set((x, y) for y in range(N) for x in range(N) if inside(x, y))
    for (x, h) in [(13, 2), (20, 1), (29, 2), (35, 1)]:  # drips off the skirt
        for k in range(1, h + 1):
            body.add((x, B + k))
            body.add((x + 1, B + k))
    for (x, y) in body:
        put(x, y, GREEN)
    for (x, y) in body:  # deeper down it's darker
        if y >= 33:
            put(x, y, DEEP)
        if y >= 38:
            put(x, y, DEEP2)
    for (x, y) in list(body):
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            if (x + dx, y + dy) not in body:
                put(x + dx, y + dy, INK)
    # the shine, top left
    rect(14, 19, 16, 19, WHITE)
    rect(13, 20, 13, 22, WHITE)
    rect(14, 20, 14, 20, LIGHT)
    put(18, 19, LIGHT)
    # the glowing heart inside, low down
    heart = ["01100110", "11111111", "11111111", "01111110", "00111100", "00011000"]
    hx, hy = 21, 33
    hs = set((hx + i, hy + j) for j, row in enumerate(heart) for i, ch in enumerate(row) if ch == "1")
    for (x, y) in hs:
        put(x, y, YEL)
    for (x, y) in list(hs):
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            if (x + dx, y + dy) not in hs:
                put(x + dx, y + dy, ORANGE)
    put(hx + 1, hy + 1, WHITE)
    # the eyes: big and shiny (or shut, blinking)
    for ex in (15, 28):
        if blink:
            rect(ex, 25, ex + 5, 26, INK)
        else:
            rect(ex, 22, ex + 5, 28, WHITE)
            for (x, y) in [(ex, 22), (ex + 5, 22), (ex, 28), (ex + 5, 28)]:
                put(x, y, GREEN)
            rect(ex + 2, 24, ex + 4, 28, INK)
            put(ex + 3, 25, WHITE)
            put(ex + 2, 24, WHITE)
            put(ex + 4, 27, (70, 70, 110))
    # the cheeks
    rect(12, 29, 14, 30, PINK)
    rect(35, 29, 37, 30, PINK)
    # a happy open smile
    rect(22, 29, 27, 29, INK)
    rect(23, 30, 26, 31, INK)
    rect(24, 31, 25, 31, RED)
    put(22, 30, INK)
    put(27, 30, INK)
    # the little crown
    cxL, cxR, cyT = 19, 30, 11
    rect(cxL, cyT + 3, cxR, cyT + 5, YEL)
    for x in [cxL, cxR]:
        rect(x, cyT, x, cyT + 2, YEL)
    rect(21, cyT + 1, 22, cyT + 2, YEL)
    rect(27, cyT + 1, 28, cyT + 2, YEL)
    rect(cxL, cyT + 1, cxL + 1, cyT + 2, YEL)
    rect(cxR - 1, cyT + 1, cxR, cyT + 2, YEL)
    rect(24, cyT - 2, 25, cyT + 2, YEL)
    rect(24, cyT + 3, 25, cyT + 4, RED)
    put(24, cyT + 3, (255, 160, 160))
    for x in range(cxL, cxR + 1):
        put(x, cyT + 5, ORANGE)
    crown = set((x, y) for y in range(N) for x in range(N)
                if at(x, y) in (YEL, RED, ORANGE, (255, 160, 160)) and cyT - 2 <= y <= cyT + 5 and cxL <= x <= cxR)
    for (x, y) in list(crown):
        for dx, dy in [(1, 0), (-1, 0), (0, -1)]:
            if (x + dx, y + dy) not in crown and y + dy < cyT + 6 and at(x + dx, y + dy) != INK:
                put(x + dx, y + dy, INK)
    return img


def rays(w, h, cx, cy, angle=0.0, spokes=16, inner=15, near=None, far=None):
    """The navy burst of rays behind everything (w x h pixels), turned by
    `angle` radians, brighter within `inner` pixels of the middle."""
    near = near or (BG3, BG2)
    far = far or (BG2, BG1)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx, dy = x - cx, y - cy
            a = math.atan2(dy, dx) + angle
            r = math.hypot(dx, dy)
            ray = int(((a + math.pi) % (2 * math.pi)) / (2 * math.pi) * spokes) % 2 == 0
            pair = near if r < inner else far
            px[x, y] = pair[0] if ray else pair[1]
    return img


def sparkle(img, x, y, big=False):
    """A little yellow sparkle (a plus sign with orange arms) on an RGB image."""
    px = img.load()
    w, h = img.size

    def put(a, b, c):
        if 0 <= a < w and 0 <= b < h:
            px[a, b] = c

    put(x, y, YEL)
    arm = 2 if big else 1
    for k in range(1, arm + 1):
        c = ORANGE if k == arm else YEL
        put(x - k, y, c)
        put(x + k, y, c)
        put(x, y - k, c)
        put(x, y + k, c)
