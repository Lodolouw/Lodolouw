"""Shared parts for the voxel weapons (see voxel.py for weapon space and how
voxels work): grips, guards, blades, drips, bubbles, eyes, edge highlights.
Every function takes the Voxels first and voxel numbers (inclusive).

The colours are the game's palette (Endesga 32: every boss and the UI use
it), so the weapons sit in the same world.
"""
import math

from voxel import hsh

# the game's palette
E32 = {
    'rust': (190, 74, 47), 'clay': (215, 118, 67), 'sand': (234, 212, 170), 'tan': (228, 166, 114),
    'brown': (184, 111, 80), 'dkbrown': (115, 62, 57), 'plum': (62, 39, 49), 'wine': (162, 38, 51),
    'red': (228, 59, 68), 'orange': (247, 118, 34), 'gold': (254, 174, 52), 'yellow': (254, 231, 97),
    'green': (99, 199, 77), 'dkgreen': (62, 137, 72), 'forest': (38, 92, 66), 'teal': (25, 60, 62),
    'navy': (18, 78, 137), 'blue': (0, 153, 219), 'cyan': (44, 232, 245), 'white': (255, 255, 255),
    'silver': (192, 203, 220), 'steel': (139, 155, 180), 'slate': (90, 105, 136), 'dkslate': (58, 68, 102),
    'night': (38, 43, 68), 'ink': (24, 20, 37), 'hot': (255, 0, 68), 'purple': (104, 56, 108),
    'magenta': (181, 80, 136), 'pink': (246, 117, 122), 'skin': (232, 183, 150), 'skin2': (194, 133, 105),
}


def square(v, z0, z1, r, mat, cx=0, cy=0, **kw):
    """a square rod along Z, (2r+1) voxels a side"""
    v.box(cx - r, cx + r, cy - r, cy + r, z0, z1, mat, **kw)


def rounded_box(v, x0, x1, y0, y1, z0, z1, mat, cut=1, **kw):
    """a box with its long edges cut off (cut voxels deep)"""
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                dx = min(x - x0, x1 - x)
                dy = min(y - y0, y1 - y)
                dz = min(z - z0, z1 - z)
                # how many sides it's near
                near = sorted([dx, dy, dz])
                if near[0] + near[1] < cut:
                    continue
                v.put(x, y, z, mat, **kw)


def grip(v, z0, z1, mat, wrap=None, r=1, style='band', step=2, cx=0, cy=0):
    """a handle along Z: a (2r+1)-wide rod of `mat`, with `wrap` laid over it -
    'band' (stripes round it every `step`), 'spiral' (a wrap winding up it) or
    'diamond' (a katana's criss-cross wrap)"""
    square(v, z0, z1, r, mat, cx, cy)
    if not wrap:
        return
    for z in range(z0, z1 + 1):
        for x in range(cx - r, cx + r + 1):
            for y in range(cy - r, cy + r + 1):
                if max(abs(x - cx), abs(y - cy)) != r:
                    continue  # (only the outside)
                u = (x - cx) + (y - cy) if abs(x - cx) == r else (y - cy) - (x - cx)
                if style == 'band':
                    on = (z - z0) % step == 0
                elif style == 'spiral':
                    # round the rod: which face and where along it
                    k = _around(x - cx, y - cy, r)
                    on = (z - z0 + k) % (step * 2) < step
                else:  # diamond
                    k = _around(x - cx, y - cy, r)
                    on = ((z - z0 + k) % (step * 2) == 0) or ((z - z0 - k) % (step * 2) == 0)
                if on:
                    v.set(x, y, z, wrap)


def _around(x, y, r):
    """how far round a square rod's outside a voxel is (0 .. 8r)"""
    if y == -r:
        return x + r
    if x == r:
        return 2 * r + (y + r)
    if y == r:
        return 4 * r + (r - x)
    return 6 * r + (r - y)


def blade(v, z0, z1, width, mat, thick=None, curve=None, plane='yz', **kw):
    """a blade up Z: width(z) -> (lo, hi) across it (Y for 'yz', X for 'xz'),
    or None; curve(z) -> how far its middle has bent (added to lo and hi);
    thick(z, w, lo, hi) -> half thickness (default: 1 in the middle, 0 at the
    edges - a lens); mat(z, w, t, lo, hi) -> material"""
    def edges(z):
        e = width(z)
        if not e:
            return None
        off = curve(z) if curve else 0
        return (e[0] + off, e[1] + off)

    def lens(z, w, lo, hi):
        mid = (lo + hi) / 2
        half = max((hi - lo) / 2, 0.5)
        return 1 if abs(w - mid) < half * 0.55 else 0
    v.profile(z0, z1, edges, thick or lens, mat, plane=plane, **kw)


def taper(half, z0, z1, tip_from, tip_to=None):
    """a straight blade half-width `half` from z0, pointed from tip_from to z1
    (returns width(z) for blade())"""
    tip_to = tip_to or z1

    def width(z):
        if z < z0 or z > z1:
            return None
        h = half
        if z >= tip_from:
            f = (tip_to - z) / max(1, tip_to - tip_from)
            h = half * max(0.0, f)
        return (-h, h)
    return width


def drips(v, spots, mat, seed=0, longest=4):
    """drops hanging down (-Z) from spots [(x, y, z)]: a column and a fatter end"""
    for i, (x, y, z) in enumerate(spots):
        n = 1 + int(hsh(x, y, z, seed + i) * longest)
        for k in range(1, n + 1):
            v.put(x, y, z - k, mat, keep=True)
        v.put(x, y, z - n - 1, mat, keep=True)
        if n >= 2:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if hsh(x + dx, y + dy, z, seed) > 0.5:
                    v.put(x + dx, y + dy, z - n, mat, keep=True)


def drips_up(v, spots, mat, seed=0, longest=4):
    """drops running up (+Z) - for things held upside down (a gauntlet's cuff)"""
    for i, (x, y, z) in enumerate(spots):
        n = 1 + int(hsh(x, y, z, seed + i) * longest)
        for k in range(1, n + 1):
            v.put(x, y, z + k, mat, keep=True)


def bubbles(v, inside, bubble, chance=0.06, seed=1, deep_only=True):
    """sprinkle bubbles into the voxels of `inside` (a see-through material)"""
    inside = set([inside] if isinstance(inside, str) else inside)
    for (x, y, z), m in list(v.v.items()):
        if m in inside and hsh(x, y, z, seed) < chance:
            if deep_only and v.exposed(x, y, z):
                continue
            v.set(x, y, z, bubble)


def speckle(v, mat, to, chance=0.12, seed=3, where=None):
    """scatter a second colour through a material (wear, rust, sparkle)"""
    for (x, y, z), m in list(v.v.items()):
        if m == mat and hsh(x, y, z, seed) < chance and (where is None or where(x, y, z)):
            v.set(x, y, z, to)


def edges(v, mat, to, min_open=2):
    """voxels of `mat` on a corner or edge (open on min_open sides) become `to` -
    a bevel's highlight"""
    hits = []
    for (x, y, z), m in v.v.items():
        if m != mat:
            continue
        n = 0
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            if (x + d[0], y + d[1], z + d[2]) not in v.v:
                n += 1
        if n >= min_open:
            hits.append((x, y, z))
    for p in hits:
        v.v[p] = to


def surface(v, face, a, b):
    """the outermost voxel seen from `face` ('+x', '-x', '+y', '-y', '+z', '-z')
    at (a, b) - the other two axes in order (x: (y, z), y: (x, z), z: (x, y)) -
    or None"""
    axis = 'xyz'.index(face[1])
    sign = 1 if face[0] == '+' else -1
    best = None
    for (x, y, z) in v.v:
        p = (x, y, z)
        o = [p[i] for i in range(3) if i != axis]
        if o[0] == a and o[1] == b:
            if best is None or p[axis] * sign > best[axis] * sign:
                best = p
    return best


def paint_on(v, face, cells, mat, depth=0):
    """recolour the outermost voxel (and `depth` more under it) seen from
    `face` at each (a, b) in cells; mat: a key or fn(a, b) -> key/None"""
    axis = 'xyz'.index(face[1])
    sign = 1 if face[0] == '+' else -1
    # (one pass over the voxels: the outermost per line)
    want = set(cells)
    top = {}
    for p in v.v:
        o = tuple(p[i] for i in range(3) if i != axis)
        if o in want and (o not in top or p[axis] * sign > top[o][axis] * sign):
            top[o] = p
    for o, p in top.items():
        m = mat(*o) if callable(mat) else mat
        if m is None:
            continue
        for k in range(depth + 1):
            q = list(p)
            q[axis] -= sign * k
            q = tuple(q)
            if q in v.v:
                v.v[q] = m


def eye(v, face, ca, cb, white, pupil, r=1.6, look=(0, 0), shine=None, lid=None):
    """a round cartoon eye painted onto the surface seen from `face`, round
    (ca, cb) in the other two axes (see surface()); look: where the pupil
    sits (voxels); shine: a highlight pixel's material; lid: a material for
    its top row (a sleepy or angry eye)"""
    R = int(math.ceil(r))
    cells = {}
    for i in range(-R, R + 1):
        for k in range(-R, R + 1):
            if i * i + k * k <= r * r + 0.3:
                m = white
                if (i - look[0]) ** 2 + (k - look[1]) ** 2 <= (r * 0.5) ** 2 + 0.3:
                    m = pupil
                if shine and (i, k) == (look[0] - 1, look[1] + 1):
                    m = shine
                if lid and k >= R - 0 and i * i + k * k <= r * r + 0.3:
                    m = lid
                cells[(ca + i, cb + k)] = m
    paint_on(v, face, list(cells), lambda a, b: cells[(a, b)])


def ring_band(v, z0, z1, r_out, r_in, mat, axis='z', c=(0, 0)):
    v.tube(axis, c, r_out, r_in, z0, z1, mat)
