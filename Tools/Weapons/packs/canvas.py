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
# facets stamped HB, a doodled face on one, the sharpener's scallops, bare
# wood and a graphite point with a drop of glowing ink on it - a ribbed
# ferrule for a guard, a pink eraser for a pommel, a grip wound in blue tape
# ----------------------------------------------------------------------
def pencil_sword(v, pal):
    grip(v, -6, 5, 'grip', wrap='grip_l', style='diamond', step=2)
    # the pommel: a pink eraser in a ribbed ferrule
    for z, m in ((-7, 'steel_d'), (-8, 'steel_l'), (-9, 'steel')):
        v.box(-2, 2, -2, 2, z, z, m)
    rounded_box(v, -2, 2, -2, 2, -13, -10, 'rubber', cut=1)
    v.box(-2, 2, -2, 2, -13, -13, 'rubber_d', only={'rubber'})
    edges(v, 'rubber', 'rubber_l', min_open=3)
    # the guard: the ferrule's ribbed rings, wider than the pencil
    for z, m in ((6, 'steel_d'), (7, 'steel'), (8, 'steel_l'), (9, 'steel'), (10, 'steel_d')):
        for x in range(-3, 4):
            for y in range(-5, 6):
                if abs(x) + abs(y) * 0.6 <= 5.2:
                    v.set(x, y, z, m)
    for y in (-5, 5):
        v.box(-1, 1, y, y, 7, 9, 'steel_l')
    # the pencil: six sides (seen end on: hexw), painted yellow, lit on +X
    H, T = 3.4, 2.3
    Z0, Z1, TIP = 11, 38, 47

    def facet(x, y, t):
        if abs(y) <= H / 2.0:
            return 'pencil_l' if x > 0 else 'pencil_d'
        return 'pencil'
    for z in range(Z0, Z1 + 1):
        for y in range(-4, 5):
            t = hexw(y, H, T)
            if t is None:
                continue
            n = int(round(t))
            for x in range(-n, n + 1):
                m = facet(x, y, t)
                if abs(x) == n and abs(y) == 2:
                    m = 'pencil_d'   # (the ridges between the faces)
                v.set(x, y, z, m)
    # the sharpened end: the cone of bare wood, the paint's scallops round
    # its foot, the graphite point, a drop of glowing ink on the tip
    for z in range(Z1 + 1, TIP + 1):
        f = (z - Z1) / float(TIP - Z1)
        R = 4.0 * (1 - f) + 0.3
        for y in range(-4, 5):
            for x in range(-3, 4):
                d = math.hypot(x * 1.45, y)
                if d > R:
                    continue
                if z >= TIP - 2:
                    m = 'lead_l' if x > 0 and y < 0 else 'lead'
                else:
                    scallop = Z1 + 1.6 + 0.9 * math.cos(math.atan2(y, x) * 6)
                    if z < scallop and d > R - 1.2:
                        m = facet(x, y, 0)
                    else:
                        m = 'wood_l' if x > 0 else ('wood_d' if x < 0 and y > 0 else 'wood')
                v.set(x, y, z, m)
    v.set(0, 0, TIP + 1, 'inkglow')
    v.set(0, 0, TIP + 2, 'inkglow_l')
    # HB stamped on the lit face, in dark letters
    rows = text_rows('HB')
    v.sprite(rows, {'#': 'line'}, (2, -3, 18), plane='yz')
    v.sprite(rows, {'#': 'line'}, (-2, 3, 18), plane='yz', flip=True)
    # a little doodled face on its side, and a pen scribble spiralling
    doodle_face(v, '+y', 0, 30, 'line', 'line', w=3)
    doodle_face(v, '-y', 0, 30, 'line', 'line', w=3)
    for z in range(22, 27):
        v.put(0, 4 if z % 2 else -4, z, 'pen', only={'pencil', 'pencil_d', 'pencil_l'})
    return {'smear': ((0, 0, 1.2), (0, 0, 4.7)), 'smear_wide': ((0, 0, 0.9), (0, 0, 4.9)), 'glow': PENCIL}


# ----------------------------------------------------------------------
# EPIC - Ink Fists (Fists): a cartoon's white glove, drawn with a dark
# outline, dipped knuckles-first in blue ink - and the ink's alive:
# Scribble's eyes and grin look out of it, and it runs down the hand in
# drips; a puffy rolled cuff
# ----------------------------------------------------------------------
def ink_fists(v, pal):
    # the glove: white, outlined like a cartoon
    toon_box(v, -6, 6, -5, 5, -3, 7, 'paper', 'line', cut=2)
    # the fingers curled over the top: grooves between them
    for x in (-3, 0, 3):
        for y in range(-5, 6):
            for z in range(4, 8):
                if v.get(x, y, z) and v.exposed(x, y, z):
                    v.set(x, y, z, 'line')
    # dipped in ink: everything above a wavy line, the ink glossy on top
    for (x, y, z), m in list(v.v.items()):
        level = 3.2 + 0.8 * math.sin(x * 0.9 + y * 0.6)
        if z >= level:
            v.v[(x, y, z)] = 'pen_d' if m == 'line' else ('pen_l' if z >= 7 and (x + y) % 3 == 0 else 'pen')
    # drips running down the white glove from the ink
    for x, y, n in ((-5, -5, 3), (-2, -5, 2), (2, -5, 4), (5, -5, 2), (-6, 1, 3), (6, -2, 2), (1, 5, 3), (-4, 5, 2)):
        top = max((z for z in range(-3, 8) if v.get(x, y, z)), default=None)
        if top is None:
            continue
        lv = int(math.ceil(3.2 + 0.8 * math.sin(x * 0.9 + y * 0.6)))
        for k in range(1, n + 1):
            v.put(x, y, lv - k, 'pen', only={'paper', 'line'})
        v.put(x, y, lv - n - 1, 'pen_d', only={'paper', 'line'})
    # Scribble's face on the back of the hand: eyes and his big grin, in the ink
    for face in ('-y',):
        cells = {}
        for s in (-1, 1):
            for dz in (0, 1):
                cells[(s * 2, 5 + dz)] = 'whiteglow'
            cells[(s * 2, 5)] = 'line'
        for a in range(-3, 4):
            cells[(a, 1)] = 'line'
        cells[(-4, 2)] = 'line'
        cells[(4, 2)] = 'line'
        paint_on(v, face, list(cells), lambda a, b: cells[(a, b)])
    # the cuff: a puffy rolled band, outlined
    toon_box(v, -7, 7, -6, 6, -8, -4, 'paper', 'line', cut=2)
    v.box(-7, 7, -6, 6, -6, -6, 'paper_d', only={'paper'})
    v.mirror_x()
    return {'smear': ((0, 0, -0.4), (0, 0, 0.9)), 'glow': INK}


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
def copy_paste_scythe(v, pal):
    # the pole: a wooden ruler, its marks and numbers along its face
    v.box(-1, 1, -2, 2, -9, 50, 'wood')
    v.box(1, 1, -2, 2, -9, 50, 'wood_l')
    for z in range(-8, 50):
        if z % 2 == 0:
            n = 2 if z % 10 == 0 else 1
            v.box(1, 1, -2, -2 + n - 1, z, z, 'line')
            v.box(-1, -1, 2 - n + 1, 2, z, z, 'line')
    # the grip: blue tape wound round it
    for z in range(-6, 7):
        if z % 3 != 0:
            v.box(-1, 1, -2, 2, z, z, 'grip')
            v.box(1, 1, -2, 2, z, z, 'grip_l')
    # the butt: a glue stick - white tube, a purple label, an orange cap
    v.cyl('z', (0, 0), 2.6, -16, -10, 'paper')
    v.cyl('z', (0, 0), 2.6, -14, -12, 'marker')
    v.cyl('z', (0, 0), 2.6, -17, -17, 'rubber_d')
    v.box(-1, 1, -1, 1, -18, -18, 'rubber_d')
    # the scissors' finger loop behind the pole (-X), red, outlined
    loop = ['..####..',
            '.#....#.',
            '#......#',
            '#......#',
            '.#....#.',
            '..####..']
    v.sprite(loop, {'#': 'marker'}, (-11, 0, 58), plane='xz', depth={'#': (-1, 1)})
    v.box(-4, -2, -1, 1, 54, 55, 'marker')
    edges(v, 'marker', 'marker_d', min_open=4)
    # the pivot screw at the top of the pole
    v.cyl('y', (0, 53), 2.4, -2, 2, 'steel')
    v.cyl('y', (0, 53), 1.4, -3, 3, 'steel_l')
    v.box(0, 0, -3, 3, 52, 54, 'steel_d')

    # the blade: a scissor blade out along +X, nearly straight, tapering to
    # its point; its cutting edge underneath, bright
    def spine(x):
        return 56.0 - 9.0 * (x / 40.0) ** 2

    def width_at(x):
        return 1.0 + 7.0 * (1 - x / 41.0) ** 0.9

    blade_cells = {}
    for x in range(3, 41):
        top = spine(x)
        bot = top - width_at(x)
        for z in range(int(math.floor(bot)), int(math.ceil(top)) + 1):
            if z > top + 0.3 or z < bot - 0.3:
                continue
            up, down = z - bot, top - z
            if up < 1.0:
                m = 'chrome'
            elif down < 1.0:
                m = 'steel_d'
            elif up < 2.2:
                m = 'steel_l'
            else:
                m = 'steel'
            blade_cells[(x, z)] = m
            half = 1 if up > 1.5 and down > 1.0 else 0
            for y in range(-half, half + 1):
                v.set(x, y, z, m)
    # the pasted copy: see-through, a little above and along
    DX, DZ = 1, 9
    sel = []
    for (x, z), m in blade_cells.items():
        cx, cz = x + DX, z + DZ
        v.put(cx, 0, cz, 'clone_l' if m in ('chrome', 'steel_l') else 'clone', keep=True)
        sel.append((cx, cz))
    # the selection round the copy: marching ants, glowing
    x0 = min(x for x, z in sel) - 2
    x1 = max(x for x, z in sel) + 1
    z0 = min(z for x, z in sel) - 2
    z1 = max(z for x, z in sel) + 2
    k = 0
    for x in range(x0, x1 + 1):
        for z in (z0, z1):
            v.put(x, 0, z, 'whiteglow' if (x // 2) % 2 == 0 else 'inkglow', keep=True)
    for z in range(z0, z1 + 1):
        for x in (x0, x1):
            v.put(x, 0, z, 'whiteglow' if (z // 2) % 2 == 0 else 'inkglow', keep=True)
    # the little "CTRL+V" handle nub at the selection's corner
    v.box(x1 - 1, x1 + 1, 0, 0, z1 - 1, z1 + 1, 'whiteglow')
    return {'smear': ((0.4, 0, 5.4), (4.0, 0, 4.6)), 'smear_wide': ((0.2, 0, 5.6), (4.2, 0, 4.4)), 'glow': INK}


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
