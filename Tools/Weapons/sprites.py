"""The weapons' pixel sprites - each drawn in code, pointing straight up, one
character per pixel (see PALETTE) - and what each colour is made of when
make_weapons.py turns the sprite into a 3D model: how thick it is (a blade's
edge thin, its spine thicker, the guard and pommel chunky) and whether it
glows (those pixels become a separate "Glow" mesh the game makes Neon).

All designs are this game's own. The style borrows ideas, never art: bold
Terraria-mod-style silhouettes with glowing cracks and edges, and grounded,
worn Deepwoken-style metals and leather.
"""
import math

# char: (name, (r, g, b), role). Roles set the thickness (in pixels) in make_weapons.py.
PALETTE = {
    # steel
    'K': ('steel outline', (46, 50, 64), 'edge'),
    'k': ('steel dark', (92, 100, 120), 'body'),
    'm': ('steel mid', (150, 160, 178), 'body'),
    's': ('steel light', (200, 208, 222), 'body'),
    'w': ('steel shine', (240, 244, 250), 'edge'),
    'f': ('fuller', (112, 122, 142), 'fuller'),
    # iron, brass, leather
    'i': ('iron dark', (58, 52, 50), 'guard'),
    'I': ('iron', (96, 88, 84), 'guard'),
    'b': ('brass dark', (150, 100, 40), 'guard'),
    'B': ('brass', (214, 160, 64), 'guard'),
    'y': ('brass shine', (250, 214, 120), 'guard'),
    'l': ('leather dark', (78, 46, 30), 'grip'),
    'L': ('leather', (130, 82, 50), 'grip'),
    'P': ('pommel brass', (214, 160, 64), 'pommel'),
    'p': ('pommel dark', (150, 100, 40), 'pommel'),
    # obsidian and fire
    'o': ('obsidian', (34, 26, 34), 'body'),
    'O': ('obsidian mid', (62, 46, 56), 'body'),
    'q': ('obsidian shine', (104, 80, 92), 'edge'),
    'e': ('ember', (255, 120, 30), 'glow'),
    'E': ('ember hot', (255, 214, 90), 'glow'),
    'r': ('red wrap', (120, 28, 30), 'grip'),
    'R': ('red wrap light', (178, 48, 44), 'grip'),
    'h': ('horn', (48, 36, 40), 'guard'),
    'H': ('horn light', (88, 66, 70), 'guard'),
    # deep sea
    'd': ('abyss', (16, 52, 74), 'body'),
    'D': ('sea', (34, 110, 140), 'body'),
    't': ('tide', (70, 176, 196), 'body'),
    'T': ('foam', (176, 242, 240), 'edge'),
    'c': ('cyan glow', (80, 255, 240), 'glow'),
    'n': ('coral', (232, 110, 110), 'guard'),
    'N': ('coral dark', (160, 60, 72), 'guard'),
    'a': ('pearl', (240, 236, 228), 'gem'),
    'A': ('pearl shade', (190, 180, 176), 'gem'),
    'g': ('kelp', (30, 70, 58), 'grip'),
    'G': ('kelp light', (52, 110, 84), 'grip'),
    # void
    'v': ('void', (40, 16, 70), 'body'),
    'V': ('violet', (100, 40, 160), 'body'),
    'u': ('magenta', (200, 70, 200), 'body'),
    'U': ('pink', (255, 150, 230), 'edge'),
    'z': ('star', (255, 255, 255), 'glow'),
    'Z': ('star pink', (255, 170, 250), 'glow'),
    'x': ('night', (22, 16, 36), 'guard'),
    'X': ('night light', (60, 46, 92), 'guard'),
    'j': ('void gem', (160, 255, 255), 'glowgem'),
}


def blank(w, h):
    return [['.'] * w for _ in range(h)]


def put(grid, x, y, ch):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]) and ch != '.':
        grid[y][x] = ch


def clear(grid, x, y):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = '.'


def stamp(grid, x0, y0, rows):
    """hand-drawn bits (a guard, a pommel) dropped in with their top-left at x0, y0"""
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            put(grid, x0 + dx, y0 + dy, ch)


def blade(grid, cx, top, length, half, shades, tip=4, curve=None):
    """A blade from `top` down `length` rows, centred on cx (plus curve(k) sideways,
    k = 0 at the tip .. 1 at the guard). half(k) = its half-width in pixels.
    shades = (outline, dark side, core, light side, shine, fuller or None)."""
    out, dark, core, light, shine, fuller = shades
    for r in range(length):
        k = r / max(1, length - 1)
        w = half(k)
        if r < tip:  # the point
            w = max(0, round(w * (r + 1) / (tip + 1)))
        off = round(curve(k)) if curve else 0
        c = cx + off
        for x in range(c - w, c + w + 1):
            if x == c - w or x == c + w:
                ch = out
            elif x == c - w + 1:
                ch = shine
            elif x < c:
                ch = light
            elif x == c and fuller and r > tip + 1 and k < 0.97:
                ch = fuller
            elif x == c:
                ch = core
            else:
                ch = dark
            put(grid, x, top + r, ch)
        if w == 0:
            put(grid, c, top + r, shine)


def grip(grid, cx, top, length, a, b, half=1):
    for r in range(length):
        for x in range(cx - half, cx + half + 1):
            put(grid, x, top + r, a if (r + (x - cx)) % 2 == 0 else b)


# ----------------------------------------------------------------------
# 1) IRON WARDEN - a plain, honest arming sword: worn steel, a brass-capped
#    iron crossguard, a wrapped leather grip, a round brass pommel.
# ----------------------------------------------------------------------
def iron_warden():
    W, H = 15, 50
    g = blank(W, H)
    cx = 7
    blade(g, cx, 0, 35, lambda k: 3, ('K', 'k', 'm', 's', 'w', 'f'), tip=4)
    stamp(g, 1, 35, [
        "yBiIIIIIIIiBy",
        "bBIiiiiiiiIBb",
        ".b.iIiiiIi.b.",
    ])
    grip(g, cx, 38, 8, 'L', 'l')
    stamp(g, cx - 2, 46, [
        ".pPp.",
        "pPyPp",
        "pPPPp",
        ".ppp.",
    ])
    return g


# ----------------------------------------------------------------------
# 2) EMBER CLEAVER - a heavy obsidian cleaver split by glowing cracks, its
#    cutting edge white-hot, horns for a guard, an ember in the pommel.
# ----------------------------------------------------------------------
def ember_cleaver():
    W, H = 17, 52
    g = blank(W, H)
    cx = 8
    top, length = 0, 36
    for r in range(5, length):
        k = r / (length - 1)
        # a wide cleaver: the spine (left) straight, the edge (right) bellied
        left = cx - 3
        right = cx + 3 + round(1.6 * math.sin(math.pi * min(1, k * 1.15)))
        for x in range(left, right + 1):
            if x == left:
                ch = 'q'
            elif x == right:
                ch = 'E'  # the white-hot edge
            elif x == right - 1:
                ch = 'e'
            elif x == left + 1:
                ch = 'O'
            else:
                ch = 'o'
            put(g, x, top + r, ch)
    # the clipped tip: the top edge slopes down from the spine to the white-hot edge
    stamp(g, cx - 3, 0, [
        "qe.......",
        "qOEe.....",
        "qOoOEe...",
        "qOoooOEe.",
        "qOooooeE.",
    ])
    # the cracks: a glowing zig-zag down the middle, and a few branches
    x = cx
    for r in range(4, length - 2):
        x += (1 if (r // 3) % 2 == 0 else -1) if r % 3 == 0 else 0
        x = max(cx - 1, min(cx + 2, x))
        put(g, x, r, 'e' if r % 5 else 'E')
        if r % 7 == 3:
            put(g, x - 1, r + 1, 'e')
        if r % 9 == 5:
            put(g, x + 1, r - 1, 'e')
    # horns for a guard (sweeping up and out), then the wrapped grip
    stamp(g, 0, 33, [
        "H...............H",
        "hH.............Hh",
        ".hH...........Hh.",
        ".hhHHhhhhhhhHHhh.",
        "..hhhhhOOOhhhhh..",
        "....hhhhhhhhh....",
    ])
    grip(g, cx, 39, 9, 'R', 'r')
    stamp(g, cx - 2, 48, [
        ".hhh.",
        "hhEhh",
        "heEeh",
        ".hhh.",
    ])
    return g


# ----------------------------------------------------------------------
# 3) TIDEFANG - a sabre of the deep: a curved blade shading from abyss to
#    foam, a glowing cyan edge, a hooked fang at the tip, a coral guard and
#    a pearl in the pommel.
# ----------------------------------------------------------------------
def tidefang():
    W, H = 19, 52
    g = blank(W, H)
    cx = 9
    length = 36

    def curve(k):  # sweeps back to the right toward the tip, like a sabre
        return 4.0 * (1 - k) ** 2

    def half(k):
        return 3

    blade(g, cx, 0, length, half, ('d', 'd', 'D', 't', 'T', None), tip=4, curve=curve)
    # the glowing edge along the outside of the curve (the right side)
    for r in range(3, length - 1):
        k = r / (length - 1)
        c = cx + round(curve(k))
        w = half(k)
        put(g, c + w, r, 'c')
    # a few bubbles of light rising through the blade
    for (r, dx) in ((9, 1), (15, 2), (22, 1), (28, 2)):
        put(g, cx + round(curve(r / (length - 1))) + dx, r, 'c')
    stamp(g, cx - 6, 35, [
        ".nN.......Nn.",
        "nNNnNNnNNnNNn",
        ".NnnNnnnNnnN.",
        "..N.......N..",
    ])
    grip(g, cx, 39, 8, 'G', 'g')
    stamp(g, cx - 2, 47, [
        ".NnN.",
        "NaaAN",
        "NaAAN",
        ".NNN.",
    ])
    return g


# ----------------------------------------------------------------------
# 4) VOIDSTAR - an endgame greatsword cut from the night sky: violet to
#    pink, starlight scattered through it, a hollow near the hilt with a
#    glowing star-gem floating in it, and wings for a guard.
# ----------------------------------------------------------------------
def voidstar():
    W, H = 21, 58
    g = blank(W, H)
    cx = 10
    length = 42

    def half(k):
        return 3 if k < 0.35 else 4

    blade(g, cx, 0, length, half, ('v', 'V', 'u', 'u', 'U', None), tip=5)
    # deeper colour down the middle
    for r in range(6, length):
        put(g, cx, r, 'V')
        put(g, cx + 1, r, 'v')
    # starlight
    stars = [(cx - 1, 9), (cx + 2, 13), (cx - 2, 18), (cx + 1, 22), (cx - 1, 27), (cx + 2, 30), (cx, 16)]
    for i, (x, y) in enumerate(stars):
        put(g, x, y, 'z' if i % 2 == 0 else 'Z')
    # the hollow near the hilt, and the star-gem floating in it
    for y in range(33, 40):
        for x in range(cx - 2, cx + 3):
            clear(g, x, y)
    for y in range(33, 40):
        put(g, cx - 3, y, 'U')
        put(g, cx + 3, y, 'v')
    stamp(g, cx - 1, 35, [
        ".j.",
        "jzj",
        ".j.",
    ])
    # wings for a guard
    stamp(g, 0, 41, [
        "X.......xXXXx.......X",
        "xX......xxxxx......Xx",
        ".xXX....xxUxx....XXx.",
        "..xxXXXxxxxxxxXXXxx..",
        "....xxxxxUzUxxxxx....",
        "......xxxxxxxxx......",
    ])
    grip(g, cx, 47, 7, 'X', 'x')
    stamp(g, cx - 2, 54, [
        ".xZx.",
        "xZzZx",
        ".xZx.",
        "..x..",
    ])
    return g


WEAPONS = [
    ('IronWarden', 'Iron Warden', iron_warden),
    ('EmberCleaver', 'Ember Cleaver', ember_cleaver),
    ('Tidefang', 'Tidefang', tidefang),
    ('Voidstar', 'Voidstar', voidstar),
]
