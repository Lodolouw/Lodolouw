"""Voxel weapons: a weapon built out of little cubes in code, then turned into
a Roblox-ready 3D model with Blender (make_models.py does the turning).

WEAPON SPACE - how every weapon is built (studs; Blender's Z is up):
  * the ORIGIN is the middle of the grip (where the hand holds it; for
    gauntlets, the middle of the fist)
  * +Z points to the tip / the head (a sword stands on its pommel, a
    gauntlet's knuckles point up)
  * -Y is the handle frame's +Y: a katana's cutting EDGE, the flat of a
    sword blade's width runs along Y, a gauntlet's back-of-hand plate
  * +X: the way a scythe's blade sweeps out; a hammer head's faces are +-X
(make_models.py marks this frame with three tiny marker meshes, GripMark,
TipMark and UpMark, so the game holds the model exactly the way the blocky
stand-ins in WeaponFX are held - the uploaded swing animations were made
for those.)

VOXELS: one voxel is RES studs (0.1). Voxel (x, y, z) - whole numbers - has
its CENTRE at (x, y, z) * RES, so a shape 2n+1 voxels wide from -n to n sits
exactly on the axis. Every shape below takes voxel numbers, inclusive.

MATERIALS: a palette of Mat(key, (r, g, b), ...). One mesh is made per
material (the game colours each one: Color, Material, Transparency), so no
textures are needed. Glowing materials become Neon.
"""
import math

RES = 0.1  # studs per voxel

DIRS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))


class Mat:
    """a material: its colour, and how Roblox should show it
      material  a Roblox Material name (SmoothPlastic, Neon, Glass, Foil, Metal...)
      alpha     Roblox Transparency (0 solid, 0.3 see-through jelly)
      role      what it is, for the game: 'metal' (turns gold when the weapon
                awakens), 'glow' (the smear's colour), 'grip', 'trim', 'gem', 'body'
    """

    def __init__(self, key, rgb, material='SmoothPlastic', alpha=0.0, role='body'):
        self.key = key
        self.rgb = tuple(int(c) for c in rgb)
        self.material = material
        self.alpha = alpha
        self.role = role

    @property
    def glow(self):
        return self.material == 'Neon'

    @property
    def clear(self):
        return self.alpha > 0.01


def glow(key, rgb, role='glow'):
    return Mat(key, rgb, 'Neon', 0.0, role)


def shade(rgb, f):
    """darker (f < 1) or lighter (f > 1) - lighter mixes towards white"""
    if f <= 1:
        return tuple(int(c * f) for c in rgb)
    t = min(1.0, f - 1)
    return tuple(int(c + (255 - c) * t) for c in rgb)


def ramp(key, rgb, material='SmoothPlastic', role='body', alpha=0.0, dark=0.62, light=1.35):
    """three materials from one colour: key_d (shadow), key, key_l (highlight)"""
    return {
        key + '_d': Mat(key + '_d', shade(rgb, dark), material, alpha, role),
        key: Mat(key, rgb, material, alpha, role),
        key + '_l': Mat(key + '_l', shade(rgb, light), material, alpha, role),
    }


def hsh(x, y, z, seed=0):
    """a steady pseudo-random number 0..1 for a voxel (for speckles and wear)"""
    n = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
    n = (n ^ (n >> 13)) * 1274126177
    return ((n ^ (n >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


class Voxels:
    """a weapon's voxels: (x, y, z) -> material key"""

    def __init__(self):
        self.v = {}

    # ------------------------------------------------------------ basics
    def set(self, x, y, z, m):
        if m is None:
            self.v.pop((x, y, z), None)
        else:
            self.v[(x, y, z)] = m

    def get(self, x, y, z):
        return self.v.get((x, y, z))

    def bounds(self):
        if not self.v:
            return (0, 0, 0), (0, 0, 0)
        xs = [p[0] for p in self.v]
        ys = [p[1] for p in self.v]
        zs = [p[2] for p in self.v]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def put(self, x, y, z, m, only=None, keep=False):
        """set one voxel; only: just over these materials (None: anything);
        keep: don't overwrite what's already there"""
        cur = self.v.get((x, y, z))
        if keep and cur is not None:
            return
        if only is not None:
            if cur is None or cur not in only:
                return
        self.set(x, y, z, m)

    # ------------------------------------------------------------ shapes
    def box(self, x0, x1, y0, y1, z0, z1, m, **kw):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                for z in range(min(z0, z1), max(z0, z1) + 1):
                    self.put(x, y, z, m, **kw)

    def cyl(self, axis, c, r, lo, hi, m, **kw):
        """a cylinder along axis 'x', 'y' or 'z': c = its centre in the other two
        axes (in order: for 'z' it's (x, y)), r its radius, lo..hi its length"""
        a, b = c
        R = int(math.ceil(r)) + 1
        for t in range(min(lo, hi), max(lo, hi) + 1):
            for i in range(-R, R + 1):
                for j in range(-R, R + 1):
                    if (i) ** 2 + (j) ** 2 <= r * r + 1e-6:
                        p, q = int(round(a)) + i, int(round(b)) + j
                        if axis == 'z':
                            self.put(p, q, t, m, **kw)
                        elif axis == 'y':
                            self.put(p, t, q, m, **kw)
                        else:
                            self.put(t, p, q, m, **kw)

    def tube(self, axis, c, r_out, r_in, lo, hi, m, **kw):
        """a hollow cylinder (a ring, a band, a tyre)"""
        a, b = c
        R = int(math.ceil(r_out)) + 1
        for t in range(min(lo, hi), max(lo, hi) + 1):
            for i in range(-R, R + 1):
                for j in range(-R, R + 1):
                    d2 = i * i + j * j
                    if r_in * r_in - 1e-6 <= d2 <= r_out * r_out + 1e-6:
                        p, q = int(round(a)) + i, int(round(b)) + j
                        if axis == 'z':
                            self.put(p, q, t, m, **kw)
                        elif axis == 'y':
                            self.put(p, t, q, m, **kw)
                        else:
                            self.put(t, p, q, m, **kw)

    def ellipsoid(self, c, radii, m, **kw):
        cx, cy, cz = c
        rx, ry, rz = radii
        for x in range(int(math.floor(cx - rx)), int(math.ceil(cx + rx)) + 1):
            for y in range(int(math.floor(cy - ry)), int(math.ceil(cy + ry)) + 1):
                for z in range(int(math.floor(cz - rz)), int(math.ceil(cz + rz)) + 1):
                    if ((x - cx) / max(rx, 1e-6)) ** 2 + ((y - cy) / max(ry, 1e-6)) ** 2 + ((z - cz) / max(rz, 1e-6)) ** 2 <= 1.0 + 1e-6:
                        self.put(x, y, z, m, **kw)

    def sphere(self, c, r, m, **kw):
        self.ellipsoid(c, (r, r, r), m, **kw)

    def fill(self, lo, hi, fn, **kw):
        """call fn(x, y, z) -> material key or None for every voxel in the box
        lo..hi (inclusive corners); None leaves that voxel alone"""
        for x in range(lo[0], hi[0] + 1):
            for y in range(lo[1], hi[1] + 1):
                for z in range(lo[2], hi[2] + 1):
                    m = fn(x, y, z)
                    if m is not None:
                        self.put(x, y, z, m, **kw)

    def profile(self, z0, z1, edges, thick, mat, plane='yz', **kw):
        """a flat shape swept along Z, like a blade: for every z in z0..z1,
        edges(z) -> (lo, hi) floats across it (Y for plane 'yz', X for 'xz'),
        or None where there's nothing; thick(z, w, lo, hi) -> half its
        thickness at w (voxels, float; 0 = a single voxel layer); mat(z, w, t,
        lo, hi) -> material key (t = how far from the middle, voxels)"""
        for z in range(min(z0, z1), max(z0, z1) + 1):
            e = edges(z)
            if not e:
                continue
            lo, hi = e
            for w in range(int(math.floor(lo + 0.5)), int(math.floor(hi + 0.5)) + 1):
                ht = thick(z, w, lo, hi)
                if ht is None or ht < 0:
                    continue
                n = int(round(ht))
                for t in range(-n, n + 1):
                    m = mat(z, w, t, lo, hi)
                    if m is None:
                        continue
                    if plane == 'yz':
                        self.put(t, w, z, m, **kw)
                    else:
                        self.put(w, t, z, m, **kw)

    def sprite(self, rows, key, origin, plane='yz', depth=None, flip=False, **kw):
        """pixel art laid onto a plane: rows top to bottom, one character per
        voxel ('.' or ' ' is empty); key: char -> material key; origin: where
        the TOP-LEFT pixel goes (x, y, z); plane 'yz' (across Y, down Z - the
        flat of a sword), 'xz' (across X, down Z) or 'xy' (across X, down -Y);
        depth: char -> (from, to) layers through the plane (default (0, 0))"""
        ox, oy, oz = origin
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch in '. ':
                    continue
                m = key.get(ch)
                if m is None:
                    continue
                d0, d1 = (depth or {}).get(ch, (0, 0))
                cc = -c if flip else c
                for d in range(d0, d1 + 1):
                    if plane == 'yz':
                        self.put(ox + d, oy + cc, oz - r, m, **kw)
                    elif plane == 'xz':
                        self.put(ox + cc, oy + d, oz - r, m, **kw)
                    else:
                        self.put(ox + cc, oy - r, oz + d, m, **kw)

    # ------------------------------------------------------------ painting
    def paint(self, fn):
        """fn(x, y, z, m) -> a new material key, or None to keep it"""
        for p, m in list(self.v.items()):
            n = fn(p[0], p[1], p[2], m)
            if n is not None:
                self.v[p] = n

    def recolor(self, frm, to, where=None):
        for p, m in list(self.v.items()):
            if m == frm and (where is None or where(*p)):
                self.v[p] = to

    def exposed(self, x, y, z, dirs=DIRS):
        """is this voxel on the surface (an empty neighbour in any of dirs)?"""
        for dx, dy, dz in dirs:
            if (x + dx, y + dy, z + dz) not in self.v:
                return True
        return False

    def outline(self, mats, to, dirs=DIRS):
        """recolour the voxels of `mats` that touch empty space (in dirs) to `to`"""
        mats = set([mats] if isinstance(mats, str) else mats)
        hits = [p for p, m in self.v.items() if m in mats and self.exposed(*p, dirs=dirs)]
        for p in hits:
            self.v[p] = to

    def mirror_x(self):
        """copy everything at x > 0 onto x < 0 (a left-right symmetric weapon)"""
        for (x, y, z), m in list(self.v.items()):
            if x > 0:
                self.v[(-x, y, z)] = m

    def mirror_y(self):
        for (x, y, z), m in list(self.v.items()):
            if y > 0:
                self.v[(x, -y, z)] = m

    def remove(self, fn):
        for p in [p for p in self.v if fn(*p)]:
            del self.v[p]

    def translate(self, dx, dy, dz):
        self.v = {(x + dx, y + dy, z + dz): m for (x, y, z), m in self.v.items()}

    def count(self):
        return len(self.v)


# ----------------------------------------------------------------------
# meshing: every material becomes one mesh of its visible faces, with
# touching faces of the same material merged into big rectangles
# ----------------------------------------------------------------------
def faces(vox, mats):
    """{material key: [quad, ...]}, each quad four (x, y, z) corners in studs,
    wound so its front faces out. A face shows where the neighbour is empty,
    or see-through while this voxel isn't (or a different see-through one)."""
    groups = {}
    v = vox.v
    for (x, y, z), m in v.items():
        mm = mats[m]
        for d in DIRS:
            n = v.get((x + d[0], y + d[1], z + d[2]))
            if n is not None:
                nm = mats[n]
                if not nm.clear:
                    continue  # (covered by something solid)
                if mm.clear and (n == m or not nm.clear):
                    continue
                if n == m:
                    continue
            axis = 0 if d[0] else (1 if d[1] else 2)
            sign = d[axis]
            c = (x, y, z)[axis]
            u, w = [q for i, q in enumerate((x, y, z)) if i != axis]
            groups.setdefault((m, axis, sign, c), set()).add((u, w))
    out = {}
    h = RES / 2
    for (m, axis, sign, c), cells in groups.items():
        for (u0, u1, w0, w1) in _greedy(cells):
            plane = (c * RES) + sign * h
            a0, a1 = u0 * RES - h, u1 * RES + h
            b0, b1 = w0 * RES - h, w1 * RES + h
            corners = []
            for (a, b) in ((a0, b0), (a1, b0), (a1, b1), (a0, b1)):
                p = [0.0, 0.0, 0.0]
                others = [i for i in range(3) if i != axis]
                p[axis] = plane
                p[others[0]] = a
                p[others[1]] = b
                corners.append(tuple(p))
            # wind it so it faces out (along the axis, sign)
            e1 = [corners[1][i] - corners[0][i] for i in range(3)]
            e2 = [corners[3][i] - corners[0][i] for i in range(3)]
            nrm = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            if nrm[axis] * sign < 0:
                corners.reverse()
            out.setdefault(m, []).append(corners)
    return out


def _greedy(cells):
    """cover a set of (u, w) cells with rectangles (u0, u1, w0, w1)"""
    left = set(cells)
    rects = []
    for (u, w) in sorted(cells, key=lambda p: (p[1], p[0])):
        if (u, w) not in left:
            continue
        u1 = u
        while (u1 + 1, w) in left:
            u1 += 1
        w1 = w
        while all((k, w1 + 1) in left for k in range(u, u1 + 1)):
            w1 += 1
        for k in range(u, u1 + 1):
            for j in range(w, w1 + 1):
                left.discard((k, j))
        rects.append((u, u1, w, w1))
    return rects


# ----------------------------------------------------------------------
# the handle frame (what the game holds) from weapon space: handle = (x, -y, -z)
# ----------------------------------------------------------------------
def to_handle(p):
    x, y, z = p
    return (x, -y, -z)


# the types' sizes, from the blocky stand-ins in WeaponFX (weapon space,
# studs: how far down past the grip, and up to the tip) - a model should
# stay close to these so the swings look right
TYPE_SIZE = {
    'Sword': {'down': 0.9, 'up': 5.3, 'across': 1.6},
    'Katana': {'down': 0.8, 'up': 5.6, 'across': 0.9},
    'Hammer': {'down': 1.0, 'up': 4.6, 'across': 2.9},
    'Daggers': {'down': 0.45, 'up': 2.55, 'across': 0.95},
    'Scythe': {'down': 1.0, 'up': 5.5, 'across': 4.2},
    'Fists': {'down': 0.9, 'up': 0.9, 'across': 1.4},
}
