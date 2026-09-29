"""JUNGLE PACK (Kongo, floor 7): Kongo the Jungle Brawler is a silverback ape -
charcoal fur, a pale grey face and hands, a silver saddle on his back, a gold
chain with a banana medallion - and he throws barrels. So: ape fists, wooden
barrels with iron hoops, bamboo, vines and big leaves, an ivory fang, tribal
carved stone, and a gold crown for the Secret. Weapon space and voxels: see
voxel.py."""
import math

from voxel import Mat, glow, shade, hsh
from kit import E32, square, rounded_box, grip, blade, speckle, edges, paint_on

FUR = (70, 68, 82)        # Kongo's fur (Config.Bosses: Color)
FUR_D = (38, 36, 50)      # darker fur, his brow
FACE = (165, 160, 172)    # his pale grey face and hands
SADDLE = (170, 172, 186)  # the silver saddle on his back
GOLD = E32['gold']        # his chain
BANANA = E32['yellow']    # its banana medallion
ANGRY = E32['hot']        # round 2: his face and eyes go red
LEAF = E32['green']
BAMBOO = (184, 204, 92)

P = {}
for m in (
    Mat('fur', FUR), Mat('fur_d', FUR_D), Mat('fur_l', (104, 102, 120)),
    Mat('skin', FACE), Mat('skin_l', shade(FACE, 1.3)), Mat('skin_d', (116, 111, 128)),
    Mat('saddle', SADDLE), Mat('saddle_l', shade(SADDLE, 1.4)),
    Mat('leaf', LEAF), Mat('leaf_l', (170, 226, 96)), Mat('leaf_d', E32['dkgreen']),
    Mat('leaf_dd', E32['forest']),
    Mat('wood', E32['brown']), Mat('wood_l', E32['tan']), Mat('wood_d', E32['dkbrown']),
    Mat('bark', E32['dkbrown'], role='grip'), Mat('bark_l', E32['brown'], role='grip'),
    Mat('bark_d', E32['plum'], role='grip'),
    Mat('bamboo', BAMBOO, role='grip'), Mat('bamboo_l', shade(BAMBOO, 1.35), role='grip'),
    Mat('bamboo_d', shade(BAMBOO, 0.62), role='grip'),
    Mat('wrap', FUR, role='grip'), Mat('wrap_l', (104, 102, 120), role='grip'),
    Mat('iron', E32['dkslate'], role='metal'), Mat('iron_l', E32['slate'], role='metal'),
    Mat('iron_d', E32['night'], role='metal'),
    Mat('ivory', E32['sand']), Mat('ivory_l', (252, 246, 230)), Mat('ivory_d', (206, 182, 140)),
    Mat('root', E32['tan']), Mat('carve', E32['dkbrown']),
    Mat('stone', (104, 104, 100)), Mat('stone_l', (146, 146, 138)), Mat('stone_d', (66, 66, 66)),
    Mat('gold', GOLD, role='trim'), Mat('gold_l', BANANA, role='trim'),
    Mat('gold_d', (196, 122, 38), role='trim'),
    Mat('gem', (44, 190, 104), role='gem'), Mat('gem_l', (170, 255, 190), role='gem'),
    Mat('gem_d', E32['forest'], role='gem'), Mat('ruby', ANGRY, role='gem'),
    Mat('velvet', E32['wine']),
    Mat('petal', E32['pink']), Mat('petal_d', E32['magenta']),
    Mat('banana', BANANA), Mat('banana_d', (214, 168, 58)),
    glow('gglow', GOLD), glow('bglow', BANANA), glow('gemglow', (120, 255, 150)),
    glow('eyeglow', ANGRY),
):
    P[m.key] = m


# ----------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------
def _put(v, p, m, **kw):
    v.put(int(round(p[0])), int(round(p[1])), int(round(p[2])), m, **kw)


def _line(v, pts, mat, step=0.3, **kw):
    """single voxels along a polyline of float points"""
    for a, b in zip(pts, pts[1:]):
        d = [b[i] - a[i] for i in range(3)]
        n = max(1, int(math.sqrt(sum(c * c for c in d)) / step))
        for i in range(n + 1):
            t = i / float(n)
            _put(v, [a[k] + d[k] * t for k in range(3)], mat, **kw)


def _ovate(peak=0.38):
    """a leaf's outline: 0 at its stalk, widest at `peak`, pointed at its tip"""
    def f(s):
        if s <= 0 or s >= 1:
            return 0.0
        if s < peak:
            return math.sin(s / peak * math.pi / 2) ** 0.8
        return ((1 - s) / (1 - peak)) ** 0.85
    return f


def _leaf(v, base, du, dw, length, width, keys=('leaf', 'leaf_l', 'leaf_d'), shape=None,
          bend=None, step=0.3, **kw):
    """a flat leaf in the plane of unit vectors du (stalk to tip) and dw (across),
    from `base`: half-width width * shape(s) at s = 0..1 along it; bend(s) ->
    (dx, dy, dz) curls it; keys: (blade, midrib, rim)"""
    body, mid, rim = keys
    shape = shape or _ovate()
    best = {}
    n = int(length / step) + 1
    for i in range(n + 1):
        s = i / float(n)
        hw = width * shape(s)
        off = bend(s) if bend else (0.0, 0.0, 0.0)
        m = int(hw / step) + 1
        for j in range(-m, m + 1):
            w = j * step
            if abs(w) > hw + 1e-6:
                continue
            p = tuple(int(round(base[k] + du[k] * s * length + dw[k] * w + off[k])) for k in range(3))
            if abs(w) < 0.4 and s < 0.85:
                pr, key = 2, mid
            elif hw - abs(w) < 0.55:
                pr, key = 1, rim
            else:
                pr, key = 0, body
            if p not in best or best[p][0] < pr:
                best[p] = (pr, key)
    for p, (pr, key) in best.items():
        v.put(p[0], p[1], p[2], key, **kw)


def _dirs(a, e):
    """unit vectors for a leaf pointing out at angle a round Z, e up from flat:
    (along it, across it)"""
    return ((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)),
            (-math.sin(a), math.cos(a), 0.0))


def _bamboo(v, z0, z1, nodes, r=1, cx=0, cy=0):
    """a bamboo cane along Z: a (2r+1) rod, a paler stripe up it, dark nodes
    that stand out a little"""
    square(v, z0, z1, r, 'bamboo', cx, cy)
    for z in range(z0, z1 + 1):
        v.set(cx + r, cy, z, 'bamboo_l')
        v.set(cx, cy - r, z, 'bamboo_l')
    for n in nodes:
        for x in range(cx - r - 1, cx + r + 2):
            for y in range(cy - r - 1, cy + r + 2):
                if abs(x - cx) == r + 1 and abs(y - cy) == r + 1:
                    continue
                v.set(x, y, n, 'bamboo_d')
        if n + 1 <= z1:
            v.box(cx - r, cx + r, cy - r, cy + r, n + 1, n + 1, 'bamboo_l')


def _barrel(v, axis, c, lo, hi, r_mid, r_end, staves=12, hoops=(), seam_off=0.5,
            stave='wood', seam='wood_d', lid='wood', lid_seam='wood_d', rim='wood_l',
            grain='wood_l', grain_seed=7, plank=3, proud=0.9, sunk=True):
    """a wooden barrel lying along `axis` ('x', 'y' or 'z'; c = its middle in
    the other two axes, as for Voxels.cyl), lo..hi long, bulging from r_end
    at its ends to r_mid; its ends are lids of planks sunk inside a rim.
    hoops: [(t, material, rivet material or None), ...] bands round it,
    standing `proud` voxels out of the staves"""
    mid = (lo + hi) / 2.0
    half = max((hi - lo) / 2.0, 1.0)
    a, b = c

    def rad(t):
        f = (t - mid) / half
        return r_end + (r_mid - r_end) * (1 - f * f)

    def at(t, i, j):
        if axis == 'x':
            return (t, a + i, b + j)
        if axis == 'y':
            return (a + i, t, b + j)
        return (a + i, b + j, t)

    for t in range(lo, hi + 1):
        r = rad(t)
        R = int(math.ceil(r)) + 1
        for i in range(-R, R + 1):
            for j in range(-R, R + 1):
                d2 = i * i + j * j
                if d2 > r * r + 0.5:
                    continue
                outer = d2 > (r - 1.0) ** 2
                inner_end = (t in (lo + 1, hi - 1)) if sunk else (t in (lo, hi))
                if sunk and t in (lo, hi):
                    if not outer:
                        continue  # (the lid sits one in)
                    m = rim
                elif inner_end and not outer:
                    m = lid_seam if i % plank == 0 else lid
                else:
                    k = (math.atan2(j, i) / math.tau * staves + seam_off) % 1.0
                    if k < 0.18:
                        m = seam
                    elif hsh(t // 3, i, j, grain_seed) < 0.12:
                        m = grain
                    else:
                        m = stave
                x, y, z = at(t, i, j)
                v.set(x, y, z, m)
    for t, hm, rivet in hoops:
        r = rad(t) + proud
        R = int(math.ceil(r)) + 1
        for i in range(-R, R + 1):
            for j in range(-R, R + 1):
                d2 = i * i + j * j
                if (rad(t) - 1.2) ** 2 <= d2 <= r * r + 0.5:
                    x, y, z = at(t, i, j)
                    v.set(x, y, z, hm)
        if rivet:
            for k in range(6):
                ang = k / 6.0 * math.tau + 0.3
                x, y, z = at(t, int(round(r * math.cos(ang))), int(round(r * math.sin(ang))))
                if v.get(x, y, z) == hm:
                    v.set(x, y, z, rivet)
    return rad


# ----------------------------------------------------------------------
# COMMON - Chest Pound Fists (Fists): Kongo's own fist - a block of
# charcoal fur, pale grey fingers curled over the top with big knuckles,
# the wrist wrapped in green leaves that cross over the back of the hand
# ----------------------------------------------------------------------
def chest_pound_fists(v, pal):
    # the hand
    rounded_box(v, -6, 6, -5, 5, -3, 7, 'fur', cut=2)
    # fur: darker streaks, lighter tips
    for (x, y, z), m in list(v.v.items()):
        if hsh(x, y, z // 2, 6) < 0.22:
            v.set(x, y, z, 'fur_d')
        elif hsh(x, y, z, 8) < 0.1:
            v.set(x, y, z, 'fur_l')
    # the fingers, curled: their first joints make the top (the knuckles,
    # +Z), their tips tuck down the palm side (+Y); creases between them
    for x0, x1 in ((1, 3), (5, 6)):
        v.box(x0, x1, -3, 5, 7, 8, 'skin')
        v.box(x0, x1, 4, 6, 0, 8, 'skin')
        v.set(x1, 6, 8, None)
        v.box(x0, x1, -3, -2, 9, 9, 'skin_l')   # the knuckle
        v.box(x0, x1, 3, 3, 8, 8, 'skin_d')      # the next joint
        v.box(x0, x1, 6, 6, 4, 4, 'skin_d')
    for x in (0, 4):
        v.box(x, x, -3, 5, 7, 7, 'skin_d')
        v.box(x, x, 4, 5, 0, 7, 'skin_d')
    # leaf strips crossing over the back of the hand (-Y)
    for x in range(0, 7):
        for z in range(-3, 8):
            for zc in (2 + x * 5 / 6.0, 2 - x * 5 / 6.0):
                d = abs(z - zc)
                if d <= 1.25:
                    v.set(x, -6, z, 'leaf' if d <= 0.6 else 'leaf_d')
    v.set(0, -6, 2, 'leaf_l')
    # the wrap round the wrist, and leaf tips poking up out of it
    rounded_box(v, -6, 6, -6, 6, -8, -4, 'leaf', cut=1)
    for (x, y, z), m in list(v.v.items()):
        if m == 'leaf' and z <= -4 and v.exposed(x, y, z):
            u = x if abs(y) == 6 else y
            if (2 * z + abs(u)) % 5 == 0:
                v.set(x, y, z, 'leaf_d')
    v.box(-6, 6, -6, 6, -4, -4, 'leaf_l', only={'leaf', 'leaf_d'})
    v.box(-6, 6, -6, 6, -8, -8, 'leaf_dd', only={'leaf', 'leaf_d'})
    for x, y in ((3, -6), (6, -3), (6, 2), (3, 6)):
        v.box(x - 1, x + 1, y, y, -3, -3, 'leaf_l') if abs(y) == 6 else v.box(x, x, y - 1, y + 1, -3, -3, 'leaf_l')
        v.set(x, y, -2, 'leaf_l')
    v.mirror_x()
    return {'smear': ((0, 0, -0.4), (0, 0, 0.9))}


# ----------------------------------------------------------------------
# RARE - Jungle Fang (Katana): a long curved ivory fang for a blade, carved
# with tribal bands at its root, set in a gold collar on a guard of leaves,
# and a bamboo grip
# ----------------------------------------------------------------------
def jungle_fang(v, pal):
    _bamboo(v, -7, 6, (-3, 2))
    v.box(-1, 1, -1, 1, -9, -8, 'gold')
    v.box(-1, 1, -1, 1, -9, -9, 'gold_d')
    # the guard: a disc of dark wood with five leaves round it
    v.cyl('z', (0, 0), 3.2, 7, 7, 'wood_d')
    for k in range(5):
        a = k / 5.0 * math.tau + 0.35
        du, dw = _dirs(a, 0.22)
        _leaf(v, (1.6 * math.cos(a), 1.6 * math.sin(a), 7.4), du, dw, 4.0, 1.7,
              keys=('leaf', 'leaf_l', 'leaf_d'))
    # the collar
    v.box(-2, 2, -3, 3, 8, 10, 'gold')
    v.box(-2, 2, -3, 3, 10, 10, 'gold_l', only={'gold'})
    v.box(-2, 2, -3, 3, 8, 8, 'gold_d', only={'gold'})

    # the fang: swelling at its root, curving back (+Y), its edge (-Y) white;
    # both sides close in to a fang's point
    def width(z):
        if z < 11 or z > 56:
            return None
        s = (z - 11) / 45.0
        lo, hi = -2.5, 2.0
        if z < 16:
            f = (16 - z) / 5.0
            lo -= 0.8 * f
            hi += 0.5 * f
        if s > 0.7:
            f = (s - 0.7) / 0.3
            lo += 2.9 * f ** 1.2
            hi -= 1.6 * f ** 2
        return (lo, hi)

    def curve(z):
        return 2.8 * ((z - 11) / 45.0) ** 2

    def thick(z, w, lo, hi):
        mid = (lo + hi) / 2
        half = max((hi - lo) / 2, 0.5)
        d = abs(w - mid) / half
        if z < 17 and d < 0.4:
            return 2
        return 1 if d < 0.65 else 0

    def mat(z, w, t, lo, hi):
        if z <= 12:
            return 'root'
        if w <= lo + 0.9:
            return 'ivory_l'
        if w >= hi - 0.9:
            return 'ivory_d'
        n = int(round(thick(z, w, lo, hi)))
        if abs(t) == n and w > lo + 1.4 and w < hi - 1.2:
            if z in (15, 19) or (z == 17 and w % 2 == 0):
                return 'carve'
        if z <= 13:
            return 'ivory_d'
        return 'ivory'
    blade(v, 11, 56, width, mat, thick=thick, curve=curve)
    return {'smear': ((0, 0, 1.3), (0, 0, 5.6)), 'smear_wide': ((0, 0, 1.1), (0, 0, 5.7)),
            'glow': (236, 226, 190)}


# ----------------------------------------------------------------------
# EPIC - Vine Scythe (Scythe): a gnarled branch with a vine winding up it,
# a huge drooping jungle leaf for a blade, a flower where it grows from the
# pole and a fern curl on top
# ----------------------------------------------------------------------
def vine_scythe(v, pal):
    square(v, -10, 54, 1, 'bark')
    for (x, y, z), m in list(v.v.items()):
        if hsh(x, y, z // 5 + x * 3, 5) < 0.3:
            v.set(x, y, z, 'bark_d')
        elif hsh(x, y, z // 3, 9) < 0.1:
            v.set(x, y, z, 'bark_l')
    # knots
    for z, s in ((6, 1), (29, -1)):
        v.box(2 * s, 2 * s, -1, 1, z, z + 1, 'bark')
        v.set(2 * s, 0, z, 'bark_d')
    # the butt: a knot of root
    v.ellipsoid((0, 0, -11), (2.0, 2.0, 2.0), 'bark')
    v.box(-1, 1, -2, -2, -12, -10, 'bark_d', only={'bark'})
    # the vine winding up the pole
    ring = ([(x, -2) for x in range(-2, 2)] + [(2, y) for y in range(-2, 2)] +
            [(x, 2) for x in range(2, -2, -1)] + [(-2, y) for y in range(2, -2, -1)])
    for z in range(-8, 50):
        for k in (0, 1):
            x, y = ring[(z + k) % len(ring)]
            v.put(x, y, z, 'leaf_d' if k == 0 else 'leaf_dd', keep=True)
    # leaves off it
    for z in (0, 13, 26, 39):
        x, y = ring[z % len(ring)]
        a = math.atan2(y, x)
        du, dw = _dirs(a, 0.75)
        _leaf(v, (x, y, z), du, dw, 5.0, 1.7, keys=('leaf', 'leaf_l', 'leaf_d'), keep=True)
    # the collar: the leaf's stalk wound round the top of the pole
    rounded_box(v, -2, 2, -2, 2, 49, 55, 'leaf_d', cut=1)
    for z in (50, 52, 54):
        v.box(-2, 2, -2, 2, z, z, 'leaf', only={'leaf_d'})
    # a fern curl on top
    curl = [
        '.VVV.',
        'V...V',
        'V.V.V',
        'V.VV.',
        'V....',
    ]
    v.sprite(curl, {'V': 'leaf_l'}, (-2, 0, 60), plane='xz')

    # the blade: a huge leaf out along +X, drooping to its point, a pale
    # midrib and veins, its cutting edge the lower side
    def spine(x):
        return 55.0 - 17.0 * (x / 40.0) ** 2

    def deep(x):
        s = (x - 2) / 38.0
        if s < 0.2:
            return 8.0 + 4.0 * math.sin(s / 0.2 * math.pi / 2)
        return max(0.8, 12.0 * ((1 - s) / 0.8) ** 0.8)

    for x in range(2, 41):
        top = spine(x)
        bot = top - deep(x)
        midrib = top - deep(x) * 0.42
        for z in range(int(math.floor(bot)), int(math.ceil(top)) + 1):
            if z > top + 0.3 or z < bot - 0.3:
                continue
            d = z - midrib
            if abs(d) < 0.6 and x < 38:
                v.box(x, x, -1, 1, z, z, 'leaf_l')
                continue
            if z - bot < 1.0:
                m = 'leaf_l'   # the cutting edge
            elif top - z < 1.0:
                m = 'leaf_d'
            elif ((x - abs(d) * 1.1) % 6) < 1.0:
                m = 'leaf_d'   # the veins
            else:
                m = 'leaf'
            v.set(x, 0, z, m)
    # a split in the leaf, like a banana leaf's
    for x0 in (21,):
        for x in range(x0 - 3, x0 + 1):
            for z in range(int(spine(x)) - 4, int(spine(x)) + 2):
                if spine(x) - z < 3.2 - (x0 - x) * 0.9 and z - (spine(x) - 3.4) > (x0 - x) * -0.2:
                    v.set(x, 0, z, None)
    # the flower where the leaf meets the pole
    flower = [
        '.PP...PP.',
        'PppP.PppP',
        'PpppPpppP',
        '.PpYYYpP.',
        '..PYGYP..',
        '.PpYYYpP.',
        'PpppPpppP',
        'PppP.PppP',
        '.PP...PP.',
    ]
    for y in (-2, 2):
        v.sprite(flower, {'P': 'petal', 'p': 'petal_d', 'Y': 'banana', 'G': 'bglow'}, (0, y, 54), plane='xz')
    return {'smear': ((0.4, 0, 5.3), (3.9, 0, 3.9)), 'smear_wide': ((0.2, 0, 5.5), (4.1, 0, 3.8))}


# ----------------------------------------------------------------------
# LEGENDARY - Barrel Daggers (Daggers): little barrels for a guard and a
# pommel (staves, iron hoops, glowing banana bungs), a blade of dark carved
# stone with a glowing tribal zigzag up it
# ----------------------------------------------------------------------
def barrel_daggers(v, pal):
    grip(v, -2, 4, 'wrap', wrap='gold', style='spiral', step=2)
    # the pommel: a little barrel stood on end, hoops at its rims
    _barrel(v, 'z', (0, 0), -7, -3, 2.5, 1.9, staves=8, sunk=False, proud=0.6,
            hoops=((-7, 'iron', None), (-3, 'iron', None)))
    # the guard: a barrel lying across the blade, its ends -+Y
    _barrel(v, 'y', (0, 6), -5, 5, 2.7, 2.1, staves=8, hoops=((-3, 'iron', None), (3, 'iron', None)))
    v.set(0, -5, 6, 'bglow')
    v.set(0, 5, 6, 'bglow')

    # the blade: dark stone, a pale knapped edge, a glowing zigzag
    def width(z):
        if z < 9 or z > 25:
            return None
        s = (z - 9) / 16.0
        if s < 0.3:
            h = 2.2 + 0.8 * s / 0.3
        else:
            h = 3.0 * ((1 - s) / 0.7) ** 0.75
        return (-h, h)

    zig = [0, 1, 1, 0, -1, -1]

    def mat(z, w, t, lo, hi):
        if 10 <= z <= 21 and w == zig[(z - 10) % 6]:
            return 'bglow'
        if w <= lo + 0.9 or w >= hi - 0.9:
            return 'stone_l'
        return 'stone'
    blade(v, 9, 25, width, mat)
    return {'smear': ((0, 0, 0.9), (0, 0, 2.5)), 'smear_wide': ((0, 0, 0.7), (0, 0, 2.6)),
            'glow': BANANA}


# ----------------------------------------------------------------------
# MYTHIC - Barrel Hammer (Hammer): the head is one of Kongo's barrels - oak
# staves, iron hoops at its ends and glowing gold ones round it, his gold
# chain and banana medallion hung across it, glowing bungs in its lids - on
# a bamboo handle that pokes out of the top in a sprout of leaves
# ----------------------------------------------------------------------
def barrel_hammer(v, pal):
    _bamboo(v, -9, 48, (-2, 5, 12, 19, 26, 47))
    # the grip: dark leather with gold bands; a gold butt cap
    grip(v, -9, 2, 'bark', wrap='gold', style='band', step=4)
    rounded_box(v, -2, 2, -2, 2, -12, -10, 'gold', cut=1)
    v.box(-2, 2, -2, 2, -10, -10, 'gold_l', only={'gold'})
    # the head: the barrel, its axis along X (its lids are what hit)
    rad = _barrel(v, 'x', (0, 38), -13, 13, 7.4, 6.0, staves=14,
                  hoops=((-12, 'iron', 'iron_l'), (12, 'iron', 'iron_l'), (-6, 'gglow', None), (6, 'gglow', None)))
    # glowing bungs in the lids
    for s in (-1, 1):
        v.box(s * 13, s * 13, -1, 1, 37, 39, 'iron')
        v.set(s * 13, 0, 38, 'bglow')
    # iron straps where the handle goes in
    v.box(-2, 2, -2, 2, 28, 31, 'iron')
    v.box(-2, 2, -2, 2, 28, 28, 'iron_l', only={'iron'})
    # the chain hung across its front and back, the medallion at the bottom
    for s in (-1, 1):
        for x in range(-5, 6):
            z = 35.0 + (abs(x) / 5.0) ** 1.6 * 8.5
            zi = int(round(z))
            r2 = rad(x) ** 2 - (zi - 38) ** 2
            if r2 < 0:
                continue
            y = s * (int(math.sqrt(r2)) + 1)
            v.set(x, y, zi, 'gold' if x % 2 == 0 else 'gold_d')
            v.set(x, y, zi + 1, 'gold_d' if x % 2 == 0 else 'gold')
        # the medallion
        v.cyl('y', (0, 33), 3.2, s * 8, s * 9, 'gold')
        v.cyl('y', (0, 33), 2.2, s * 9, s * 9, 'fur_d')
        for (x, z) in ((1, 35), (1, 34), (1, 33), (0, 32), (-1, 32), (-2, 33)):
            v.set(x, s * 9, z, 'bglow')
        v.set(1, s * 9, 36, 'gold_d')
    # a sprout of bamboo leaves out of the top
    for a, e in ((0.3, 0.45), (2.5, 0.6), (4.3, 0.4)):
        du, dw = _dirs(a, e)
        _leaf(v, (0, 0, 47), du, dw, 7.0, 1.7, keys=('leaf', 'leaf_l', 'leaf_d'), keep=True)
    return {'smear': ((-1.4, 0, 3.8), (1.4, 0, 3.8)), 'smear_wide': ((-1.6, 0, 3.8), (1.6, 0, 3.8)),
            'glow': GOLD}


# ----------------------------------------------------------------------
# SECRET - Kong's Crown (Sword): a broad golden blade with a leaf of jade
# inlaid up it, its veins glowing, and a vine winding round it, rising out
# of Kongo's crown - gold points, rubies, a big green gem, a red velvet cap;
# his banana medallion for a pommel
# ----------------------------------------------------------------------
def kongs_crown(v, pal):
    grip(v, -4, 5, 'wrap', wrap='gold', style='diamond', step=2)
    v.box(-1, 1, -1, 1, -5, -5, 'gold_d')
    # the pommel: the banana medallion, facing -+X
    v.cyl('x', (0, -8), 3.2, -1, 1, 'gold')
    v.cyl('x', (0, -8), 2.2, -1, 1, 'fur_d')
    banana = [(1, -5 - 1), (1, -7), (1, -8), (0, -9), (-1, -9), (-2, -8)]
    for x in (-1, 1):
        for y, z in banana:
            v.set(x, y, z, 'bglow')
        v.set(x, 1, -5, 'gold_d')

    # the crown: an oval gold band round the blade's root, with points
    rx, ry = 5.0, 8.4
    for x in range(-6, 7):
        for y in range(-9, 10):
            o = (x / rx) ** 2 + (y / ry) ** 2
            i = (x / (rx - 1.5)) ** 2 + (y / (ry - 1.5)) ** 2
            if o <= 1.0:
                if i > 1.0:
                    v.box(x, x, y, y, 5, 9, 'gold')
                    v.set(x, y, 9, 'gold_l')
                    v.set(x, y, 5, 'gold_d')
                else:
                    v.set(x, y, 6, 'velvet')
    for a, h in ((0, 6), (math.pi, 6), (math.pi / 2, 5), (-math.pi / 2, 5),
                 (0.8, 3), (-0.8, 3), (math.pi - 0.8, 3), (math.pi + 0.8, 3)):
        x, y = rx * 0.92 * math.cos(a), ry * 0.92 * math.sin(a)
        tx, ty = -math.sin(a), math.cos(a)
        for dz in range(h):
            half = 1 if dz < h - 2 else 0
            for s in range(-half, half + 1):
                _put(v, (x + tx * s, y + ty * s, 10 + dz), 'gold')
        _put(v, (x, y, 10 + h), 'gold_l')
    # the big green gem at its front and back, rubies round the band
    for s in (-1, 1):
        v.box(s * 5, s * 5, -1, 1, 6, 8, 'gem_d')
        v.box(s * 6, s * 6, -1, 1, 6, 8, 'gem')
        v.set(s * 6, 0, 7, 'gemglow')
        v.set(s * 6, -1, 8, 'gem_l')
        for y in (-5, 5):
            _put(v, (s * (rx * math.sqrt(1 - (y / ry) ** 2) + 0.3), y, 7), 'ruby')

    # the blade: broad, a little wider toward its point
    def width(z):
        if z < 7 or z > 49:
            return None
        if z <= 37:
            h = 4.2 + 0.9 * (z - 7) / 30.0
        else:
            h = 5.1 * ((49 - z) / 12.0) ** 0.8
        return (-h, h)

    def thick(z, w, lo, hi):
        half = max((hi - lo) / 2, 0.5)
        return 1 if abs(w) < half * 0.72 else 0

    inlay = _ovate(0.4)

    def mat(z, w, t, lo, hi):
        half = (hi - lo) / 2
        if abs(w) >= half - 0.9:
            return 'gold_l'
        s = (z - 13) / 28.0
        if 0 <= s <= 1:
            iw = 2.7 * inlay(s)
            if abs(w) <= iw + 0.5:
                if abs(w) > iw - 0.5:
                    return 'gold_d'
                if w == 0 or (z - 13 - abs(w)) % 5 == 0:
                    return 'bglow'
                return 'gem'
        return 'gold'
    blade(v, 7, 49, width, mat, thick=thick)
    # a vine winding round the lower blade, with leaves
    pts = []
    for i in range(80):
        t = i / 79.0
        z = 10 + 16 * t
        a = t * math.tau * 1.25 + 0.4
        h = 4.2 + 0.9 * (z - 7) / 30.0
        pts.append((2.2 * math.cos(a), (h + 0.8) * math.sin(a), z))
    _line(v, pts, 'leaf_d', step=0.2)
    for i in (18, 46, 74):
        x, y, z = pts[i]
        sy = 1 if y > 0 else -1
        _leaf(v, (x, y, z), (0.0, 0.7 * sy, 0.7), (0.0, -0.7, 0.7 * sy), 4.0, 1.4,
              keys=('leaf', 'leaf_l', 'leaf_d'))
    return {'smear': ((0, 0, 1.2), (0, 0, 4.9)), 'smear_wide': ((0, 0, 0.9), (0, 0, 5.0)), 'glow': GOLD}


PACK = {
    'id': 'Jungle', 'title': 'Jungle pack - Kongo', 'accent': (96, 196, 82),
    'palette': P,
    'weapons': [
        ('ChestPoundFists', 'Chest Pound Fists', 'Fists', 'Common', chest_pound_fists),
        ('JungleFang', 'Jungle Fang', 'Katana', 'Rare', jungle_fang),
        ('VineScythe', 'Vine Scythe', 'Scythe', 'Epic', vine_scythe),
        ('BarrelDaggers', 'Barrel Daggers', 'Daggers', 'Legendary', barrel_daggers),
        ('BarrelHammer', 'Barrel Hammer', 'Hammer', 'Mythic', barrel_hammer),
        ('KongsCrown', "Kong's Crown", 'Sword', 'Secret', kongs_crown),
    ],
}
