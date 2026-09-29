"""CANVAS PACK (Scribble, the 4th-Dimensional Doodle, floor 9): a living
doodle - blue pen ink, red marker in round 2, a pencil behind his ear, pink
eraser, dark eyes and a grin on white paper. So: pencils (yellow facets, bare
wood, graphite, a metal ferrule, a pink eraser), ink drips, ballpoint
scribbles and sketchy dark outlines on white, scissors and a marching-ants
selection, and a glitching DEL key. Weapon space and voxels: see voxel.py."""
import math

from voxel import Mat, glow, shade, hsh
from kit import E32, square, rounded_box, grip, blade, taper, edges, paint_on

INK = E32['blue']        # his blue pen ink
DEEP = E32['navy']       # deeper ink
MARKER = E32['red']      # round 2: red marker
MARKER_D = E32['wine']
PENCIL = E32['gold']     # the pencil behind his ear
RUBBER = E32['pink']     # eraser rubber
DARK = E32['ink']        # his eyes and grin, and every outline
PAPER = E32['white']

P = {}
for m in (
    # the pencil: painted facets, bare wood, graphite
    Mat('pencil', PENCIL), Mat('pencil_l', E32['yellow']), Mat('pencil_d', shade(PENCIL, 0.78)),
    Mat('pgrip', PENCIL, role='grip'), Mat('pgrip_l', E32['yellow'], role='grip'),
    Mat('pgrip_d', shade(PENCIL, 0.78), role='grip'),
    Mat('wood', E32['tan']), Mat('wood_l', E32['sand']), Mat('wood_d', E32['brown']),
    Mat('lead', E32['dkslate']), Mat('lead_l', E32['slate']), Mat('lead_d', E32['night']),
    # metal: the ferrule, the scissors
    Mat('steel', E32['steel'], role='metal'), Mat('steel_l', E32['silver'], role='metal'),
    Mat('steel_d', E32['slate'], role='metal'), Mat('chrome', shade(E32['silver'], 1.5), role='metal'),
    # the eraser
    Mat('rubber', RUBBER), Mat('rubber_l', shade(RUBBER, 1.3)), Mat('rubber_d', shade(RUBBER, 0.78)),
    # paper, pen and ink
    Mat('paper', PAPER), Mat('paper_d', E32['silver']),
    Mat('line', DARK, role='trim'),
    Mat('pen', INK), Mat('pen_l', shade(INK, 1.45)), Mat('pen_d', DEEP),
    Mat('clone', INK, alpha=0.45), Mat('clone_l', shade(INK, 1.5), alpha=0.35),
    glow('inkglow', INK), glow('inkglow_l', E32['cyan']),
    # red marker and glitches
    Mat('marker', MARKER), Mat('marker_l', shade(MARKER, 1.35)), Mat('marker_d', MARKER_D),
    glow('redglow', E32['hot']), glow('whiteglow', PAPER),
    # a keyboard key
    Mat('key', E32['night']), Mat('key_l', E32['dkslate']), Mat('key_d', DARK),
    # grips
    Mat('grip', DEEP, role='grip'), Mat('grip_l', INK, role='grip'),
    Mat('grip_k', DARK, role='grip'), Mat('grip_w', PAPER, role='grip'),
):
    P[m.key] = m


# ----------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------
FONT = {  # 5 tall pixel letters
    'D': ('DD.', 'D.D', 'D.D', 'D.D', 'DD.'),
    'E': ('EE', 'E.', 'EE', 'E.', 'EE'),
    'L': ('L.', 'L.', 'L.', 'L.', 'LL'),
    'H': ('H.H', 'H.H', 'HHH', 'H.H', 'H.H'),
    'B': ('BB.', 'B.B', 'BB.', 'B.B', 'BB.'),
}


def text_rows(s, gap=1):
    """a word as sprite rows ('#' the ink)"""
    rows = [''] * 5
    for i, ch in enumerate(s):
        for r in range(5):
            rows[r] += ''.join('#' if c != '.' else '.' for c in FONT[ch][r])
            if i < len(s) - 1:
                rows[r] += '.' * gap
    return rows


def hexw(y, H, T):
    """a pencil's six-sided body seen end on: how thick (half, across X) it is
    at y, for half-width H (across Y) and half-thickness T"""
    a = abs(y)
    if a > H + 1e-6:
        return None
    if a <= H / 2.0:
        return T
    return T * (H - a) / (H / 2.0)


def ellipse_xy(v, cx, cy, rx, ry, z0, z1, m, **kw):
    """an oval slab lying flat (across X and Y), z0..z1 thick"""
    for z in range(z0, z1 + 1):
        for x in range(int(math.floor(cx - rx)), int(math.ceil(cx + rx)) + 1):
            for y in range(int(math.floor(cy - ry)), int(math.ceil(cy + ry)) + 1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0 + 1e-6:
                    v.put(x, y, z, m(x, y, z) if callable(m) else m, **kw)


def pencil_rod(v, z0, z1, r, flat, lit, ridge):
    """a pencil's painted body along Z: a (2r+1) rod with its corners cut; the
    flats `flat` (the +X one `lit`), the ridges between them `ridge`"""
    for z in range(z0, z1 + 1):
        for x in range(-r, r + 1):
            for y in range(-r, r + 1):
                if abs(x) == r and abs(y) == r:
                    continue
                m = flat
                if abs(x) == r or abs(y) == r:
                    other = y if abs(x) == r else x
                    if other != 0:
                        m = ridge
                    elif x == r:
                        m = lit
                v.set(x, y, z, m)


def toon_box(v, x0, x1, y0, y1, z0, z1, fill, line, cut=2, **kw):
    """a rounded box with a dark line along its edges - drawn like a cartoon"""
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                near = sorted([min(x - x0, x1 - x), min(y - y0, y1 - y), min(z - z0, z1 - z)])
                s = near[0] + near[1]
                if s < cut:
                    continue
                m = line if (s == cut and near[0] >= cut // 2 and line) else fill
                v.put(x, y, z, m, **kw)


def doodle_face(v, face, ca, cb, eye, mouth, w=5):
    """Scribble's face doodled onto a surface: two dark eyes and a big grin,
    round (ca, cb) in the face's two axes (see kit.surface)"""
    h = w // 2
    cells = {}
    for s in (-1, 1):
        for k in (0, 1):
            cells[(ca + s * (h - 1), cb + 1 + k)] = eye
    for a in range(-h + 1, h):
        cells[(ca + a, cb - 2)] = mouth
    cells[(ca - h, cb - 1)] = mouth
    cells[(ca + h, cb - 1)] = mouth
    paint_on(v, face, list(cells), lambda a, b: cells[(a, b)])


# ----------------------------------------------------------------------
# COMMON - Eraser Hammer (Hammer): a yellow pencil for a handle, sharpened
# to a point at the bottom; a big pink eraser for a head, held in a ribbed
# silver ferrule, its ends grey from rubbing out; Scribble's grin and a
# heart doodled on it in pen
# ----------------------------------------------------------------------
def eraser_hammer(v, pal):
    pencil_rod(v, -8, 26, 2, 'pgrip', 'pgrip_l', 'pgrip_d')
    # the sharpened end: the paint's scallops, bare wood, the lead
    for x in range(-2, 3):
        for y in range(-2, 3):
            if abs(x) == 2 and abs(y) == 2:
                continue
            flat = (abs(x) == 2 and y == 0) or (abs(y) == 2 and x == 0)
            v.set(x, y, -9, 'pgrip' if flat else 'wood')
            if abs(x) + abs(y) <= 2:
                v.set(x, y, -10, 'wood')
    v.box(-1, 1, -1, 1, -11, -11, 'wood')
    for x, y in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        v.set(x, y, -12, 'lead')
    v.set(0, 0, -13, 'lead')
    # the ferrule where the pencil meets the eraser: ribbed rings
    for z in range(27, 32):
        m = {27: 'steel_d', 28: 'steel_l', 29: 'steel', 30: 'steel_l', 31: 'steel'}[z]
        for x in range(-3, 4):
            for y in range(-3, 4):
                if abs(x) + abs(y) <= 5:
                    v.set(x, y, z, m)
    # the head: a chunky eraser across X (its ends hit)
    rounded_box(v, -12, 12, -6, 6, 32, 44, 'rubber', cut=2)
    edges(v, 'rubber', 'rubber_l', min_open=2)
    v.paint(lambda x, y, z, m: 'rubber_d' if m in ('rubber', 'rubber_l') and z <= 33 else None)
    # its ends, grey from rubbing out pencil
    for face in ('+x', '-x'):
        cells = []
        for y in range(-6, 7):
            for z in range(32, 45):
                d = (z - 35) - 0.6 * y
                if abs(d) < 1.6 and hsh(y, z, 1, 3 if face == '+x' else 4) < 0.75:
                    cells.append((y, z))
                elif abs(d) < 2.8 and hsh(y, z, 2, 5) < 0.25:
                    cells.append((y, z))
        paint_on(v, face, cells, 'lead_l')
    # the ferrule's band round its middle, with rows of crimps
    for x in range(-3, 4):
        for y in range(-7, 8):
            for z in range(31, 46):
                if abs(y) == 7 or z == 45:
                    if abs(y) == 7 and z == 45:
                        continue
                    m = 'steel_d' if abs(x) == 3 else ('steel_l' if abs(x) == 2 else 'steel')
                    v.set(x, y, z, m)
    for y in (-7, 7):
        for z in (34, 38, 42):
            v.set(0, y, z, 'steel_d')
    # doodled on it: Scribble's grin at one end, a pen heart at the other
    for face in ('-y', '+y'):
        doodle_face(v, face, 7, 38, 'line', 'line', w=5)
        heart = ['.##.##.', '#######', '#######', '.#####.', '..###..', '...#...']
        cells = [(-10 + c, 41 - r) for r, row in enumerate(heart) for c, ch in enumerate(row) if ch == '#']
        paint_on(v, face, cells, 'pen')
    return {'smear': ((-1.3, 0, 3.8), (1.3, 0, 3.8)), 'smear_wide': ((-1.5, 0, 3.8), (1.5, 0, 3.8)),
            'glow': RUBBER}


# ----------------------------------------------------------------------
# RARE - Pencil Sword (Sword): a giant sharpened pencil for a blade - yellow
# facets stamped HB, the sharpener's scallops, bare wood and a graphite
# point with a drop of glowing ink on it - a ribbed ferrule for a guard, a
# pink eraser for a pommel
# ----------------------------------------------------------------------
# EPIC - Ink Fists (Fists): a cartoon's white glove, drawn with a dark
# outline, dipped knuckles-first in blue ink - and the ink's alive: Scribble's
# dark eyes and grin look out of it, and it runs down the hand in drips
# ----------------------------------------------------------------------
# LEGENDARY - Doodle Katana (Katana): a katana drawn in pen - white paper
# inside a dark outline, blue ballpoint shading strokes, its edge glowing
# blue; a doodled guard with a pen spiral, a criss-cross wrap, doodle
# sparkles by its point (and the outline overshoots it, like a sketch)
# ----------------------------------------------------------------------
def doodle_katana(v, pal):
    grip(v, -7, 6, 'grip_w', wrap='grip_k', style='diamond', step=2)
    v.box(-1, 1, -1, 1, -9, -8, 'line')
    v.set(0, 0, -9, 'inkglow')
    # the guard: a disc drawn in outline, a pen spiral on it
    v.cyl('z', (0, 0), 3.7, 7, 9, 'paper')
    v.tube('z', (0, 0), 3.7, 2.8, 7, 7, 'line')
    v.tube('z', (0, 0), 3.7, 2.8, 9, 9, 'line')
    for i in range(12):
        a = i * 0.8
        r = 0.5 + i * 0.2
        v.set(int(round(r * math.cos(a))), int(round(r * math.sin(a))), 9, 'pen')
    v.box(-1, 1, -2, 2, 10, 11, 'pen_d')

    def width(z):
        if z < 12 or z > 56:
            return None
        lo, hi = -2.6, 2.6
        if z >= 50:
            lo = -2.6 + (z - 50) / 6.0 * 5.0
        return (lo, hi)

    def curve(z):
        return 2.3 * ((z - 12) / 44.0) ** 2

    def thick(z, w, lo, hi):
        mid = (lo + hi) / 2
        half = max((hi - lo) / 2, 0.5)
        return 1 if abs(w - mid) < half * 0.62 else 0

    # the shading: short diagonal pen strokes in three bunches
    strokes = set()
    for c in (15, 29, 41):
        for s in (0, 3, 6):
            for d in range(2, 6):
                strokes.add((c + s + d, d))

    def mat(z, w, t, lo, hi):
        e0, e1 = int(math.floor(lo + 0.5)), int(math.floor(hi + 0.5))
        d = w - e0
        if d <= 0:
            return 'inkglow'   # the glowing edge
        if w >= e1 or d == 1:
            return 'line'      # the pen's outline
        if (z, d) in strokes and (t != 0 or thick(z, w, lo, hi) == 0):
            return 'pen'
        return 'paper'
    blade(v, 12, 56, width, mat, thick=thick, curve=curve)
    # the outline carries on round the point, and overshoots it
    top = max(z for (x, y, z) in v.v)
    for (x, y, z), m in list(v.v.items()):
        if z >= 50 and m in ('paper', 'pen') and (x, y, z + 1) not in v.v:
            v.v[(x, y, z)] = 'line'
    yt = max(y for (x, y, z) in v.v if z == top)
    v.set(0, yt, top + 1, 'line')
    v.set(0, yt + 1, top + 2, 'line')
    v.set(0, yt, top + 2, 'line')
    # doodle sparkles by its point
    for (y, z) in ((6, 48), (5, 40)):
        for dy, dz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            v.set(0, y + dy, z + dz, 'inkglow_l')
    return {'smear': ((0, 0, 1.4), (0, 0, 5.5)), 'smear_wide': ((0, 0, 1.0), (0, 0, 5.7)), 'glow': INK}


# ----------------------------------------------------------------------
# MYTHIC - Copy-Paste Scythe (Scythe): one half of a giant pair of scissors
# on a wooden ruler - its red finger loop, the pivot screw, a long steel
# blade - and a see-through copy of the blade pasted just above it, a
# glowing marching-ants selection round the copy; a glue stick for a butt
# ----------------------------------------------------------------------
# SECRET - Delete Key (Daggers): a red pixel blade glitching - its colours
# split (cyan down one edge, hot red down the other), slices of it slipped
# sideways, pixels breaking off - out of a keyboard's DEL key, its letters
# and the light under it glowing; a window's close button for a pommel
# ----------------------------------------------------------------------
def delete_key(v, pal):
    grip(v, -3, 1, 'grip_k', wrap='marker_d', style='spiral', step=2)
    # the pommel: the close button, a white x on red
    v.box(-2, 2, -2, 2, -7, -3, 'marker')
    edges(v, 'marker', 'marker_d', min_open=3)
    for face in ('+x', '-x', '+y', '-y'):
        paint_on(v, face, [(-1, -6), (1, -6), (0, -5), (-1, -4), (1, -4)], 'paper')
    # the guard: the DEL key - a dark keycap, lit from under
    v.box(-2, 2, -5, 5, 2, 8, 'key_d')
    v.box(-3, 3, -4, 4, 3, 7, 'key')
    for y in range(-5, 6):
        for z in range(2, 9):
            if abs(y) == 5 or z in (2, 8):
                v.set(0, y, z, 'redglow')
    rows = text_rows('DEL')
    v.sprite(rows, {'#': 'whiteglow'}, (3, -4, 7), plane='yz')
    v.sprite(rows, {'#': 'whiteglow'}, (-3, 4, 7), plane='yz', flip=True)
    # the blade: a dagger, its colours split, a few slices slipped sideways
    width = taper(2.6, 9, 25, 17)
    slip = {12: 1, 15: -1, 16: -1, 19: 2, 22: -1}
    for z in range(9, 26):
        e = width(z)
        if not e:
            continue
        lo, hi = e
        o = slip.get(z, 0)
        w0, w1 = int(math.floor(lo + 0.5)), int(math.floor(hi + 0.5))
        for w in range(w0, w1 + 1):
            half = 1 if abs(w) < (hi - lo) / 2 * 0.6 else 0
            for t in range(-half, half + 1):
                if w0 == w1:
                    m = 'marker_l'
                elif w == w0:
                    m = 'inkglow_l'
                elif w == w1:
                    m = 'redglow'
                elif w == 0:
                    m = 'marker_l'
                elif w < 0:
                    m = 'marker'
                else:
                    m = 'marker_d'
                v.set(t, w + o, z, m)
        if o:
            # where the slice was, a ghost of its edge is left behind
            v.set(0, (w0 if o > 0 else w1), z, 'inkglow_l' if o > 0 else 'redglow')
    # pixels breaking off
    for (y, z) in ((-5, 13), (5, 17), (-5, 20), (4, 23), (-3, 27)):
        v.set(0, y, z, 'redglow' if y > 0 else 'inkglow_l')
    return {'smear': ((0, 0, 0.9), (0, 0, 2.5)), 'smear_wide': ((0, 0, 0.7), (0, 0, 2.6)), 'glow': E32['hot']}


PACK = {
    'id': 'Canvas', 'title': 'Canvas pack - Scribble', 'accent': (0, 153, 219),
    'palette': P,
    'weapons': [
        ('EraserHammer', 'Eraser Hammer', 'Hammer', 'Common', eraser_hammer),
        ('PencilSword', 'Pencil Sword', 'Sword', 'Rare', pencil_sword),
        ('InkFists', 'Ink Fists', 'Fists', 'Epic', ink_fists),
        ('DoodleKatana', 'Doodle Katana', 'Katana', 'Legendary', doodle_katana),
        ('CopyPasteScythe', 'Copy-Paste Scythe', 'Scythe', 'Mythic', copy_paste_scythe),
        ('DeleteKey', 'Delete Key', 'Daggers', 'Secret', delete_key),
    ],
}
