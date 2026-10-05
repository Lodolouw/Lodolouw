"""
Feed the Thing in the Basement - the Thinglets and the egg, made in Blender.

Used by build_props.py: they go into the same FBX as the truck (one upload).

Every creature is about 1 stud tall, faces -Z, and stands on its pivot
(<Kind>_Origin, with <Kind>_MarkX 10 studs along +X for the size). It's
made of a few single-colour objects named <Kind>_<Role>_<RRGGBB>:
    Body    takes the mutation colours (Frozen, Gold...)
    Eye     the face: eyes, mouth, blush, shines - never recoloured
    Accent  leaves, stems, spots - glow when the Thinglet is Glowing
    Glow    always glowing Neon in that colour (flames, antennae)
The game colours each object from its name, so there are no textures and
mutations can recolour them freely. Positions are in Roblox coordinates
(X right, Y up, Z back), like build_map.py.
"""

import math

import build_map as K
from build_map import at, new_mesh

INK = "2B1B3D"  # pupils and mouths: a deep purple-black (softer than pure black)
WHITE = "FFFFFF"
BLUSH = "FF8FA8"
LEAF = "5DBB46"
CREATURES = []  # (kind, mesh names) - for the post-processing in finish()


class Creature:
    def __init__(self, kind, ox):
        self.kind = kind
        self.base = at(ox, 0, 0)
        self.meshes = {}
        CREATURES.append(self)
        o = new_mesh(f"{kind}_Origin")
        o.box(at(ox, 0, 0), (0.05, 0.05, 0.05), "white")
        x = new_mesh(f"{kind}_MarkX")
        x.box(at(ox + 10, 0, 0), (0.05, 0.05, 0.05), "white")

    def mesh(self, role, hex_color):
        key = (role, hex_color)
        if key not in self.meshes:
            self.meshes[key] = new_mesh(f"{self.kind}_{role}_{hex_color}", texture=None)
        return self.meshes[key]

    # an ellipsoid of `size` centred at `pos` (creature space), turned by yaw/pitch/roll
    def blob(self, role, hex_color, pos, size, yaw=0.0, pitch=0.0, roll=0.0, detail=2):
        self.mesh(role, hex_color).blob(self.base * at(*pos, yaw, pitch, roll), size, "white", detail=detail)

    # a blob that comes to a point at the top (a flame)
    def flame(self, role, hex_color, pos, size, point=0.85, lean=0.0, detail=2):
        m = self.mesh(role, hex_color)
        before = len(m.verts)
        centre = self.base.point(pos)
        m.blob(at(*centre), size, "white", detail=detail)
        half = size[1] / 2
        for i in range(before, len(m.verts)):
            x, y, z = m.verts[i]
            h = max(0.0, (y - centre[1]) / half)  # 0 at the middle .. 1 at the top
            k = 1 - point * h ** 1.5
            m.verts[i] = (centre[0] + (x - centre[0]) * k, y, centre[2] + (z - centre[2]) * k + lean * h * half)

    # a tube of radius r along a path of points, rounded at both ends
    def tube(self, role, hex_color, points, r, sides=7, r_end=None):
        m = self.mesh(role, hex_color)
        pts = [self.base.point(p) for p in points]
        n = len(pts)
        radii = [r + ((r_end if r_end is not None else r) - r) * i / (n - 1) for i in range(n)]
        rings = []
        for i, p in enumerate(pts):
            a, b = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
            t = norm(K.sub(b, a))
            side = norm(K.cross(t, (0, 1, 0))) if abs(t[1]) < 0.95 else norm(K.cross(t, (1, 0, 0)))
            up = K.cross(side, t)
            ring = []
            for k in range(sides):
                ang = 2 * math.pi * k / sides
                d = tuple(math.cos(ang) * side[j] + math.sin(ang) * up[j] for j in range(3))
                ring.append(tuple(p[j] + d[j] * radii[i] for j in range(3)))
            rings.append((p, ring))
        for (pa, ra), (pb, rb) in zip(rings, rings[1:]):
            for k in range(sides):
                k2 = (k + 1) % sides
                quad = [ra[k], ra[k2], rb[k2], rb[k]]
                mid = tuple(sum(q[j] for q in quad) / 4 for j in range(3))
                centre = tuple((pa[j] + pb[j]) / 2 for j in range(3))
                m.poly(quad, "white", K.sub(mid, centre), smooth=True)
        for p, ring, other, radius in ((rings[0][0], rings[0][1], pts[1], radii[0]), (rings[-1][0], rings[-1][1], pts[-2], radii[-1])):
            t = norm(K.sub(p, other))
            tip = tuple(p[j] + t[j] * radius * 0.9 for j in range(3))
            for k in range(sides):
                m.poly([ring[k], ring[(k + 1) % sides], tip], "white", t, smooth=True)

    # --- the face kit ---
    def eye(self, x, y, z, s, look=(0.0, 0.0), sclera=WHITE, pupil=INK, pupil_size=0.62):
        """A big cartoon eye of diameter s whose front is at about z (on the body)."""
        z += s * 0.22  # sink it into the body a little
        self.blob("Eye", sclera, (x, y, z), (s, s * 1.12, s * 0.55))
        px, py = look
        if pupil:
            self.blob("Eye", pupil, (x + px * s * 0.14, y + py * s * 0.14 - s * 0.04, z - s * 0.2),
                      (s * pupil_size, s * pupil_size * 1.12, s * 0.3))
        # two shines: they make the eye look wet and alive
        self.blob("Eye", WHITE, (x - s * 0.13, y + s * 0.13, z - s * 0.36), (s * 0.22, s * 0.24, s * 0.08), detail=1)
        self.blob("Eye", WHITE, (x + s * 0.12, y - s * 0.1, z - s * 0.33), (s * 0.09, s * 0.09, s * 0.05), detail=1)

    def smile(self, cx, cy, width, sag, r, body, hex_color=INK, tilt=0.0, steps=9):
        """A curved mouth on the front of `body` (centre, semi-axes)."""
        pts = []
        for i in range(steps):
            t = -1 + 2 * i / (steps - 1)
            x = cx + t * width / 2
            y = cy - sag * (1 - t * t) + tilt * t
            pts.append((x, y, surface(body, x, y) - r * 0.2))
        self.tube("Eye", hex_color, pts, r)

    def blush(self, x, y, body, size=0.15):
        self.blob("Eye", BLUSH, (x, y, surface(body, x, y) + 0.015), (size, size * 0.55, 0.05), detail=1)


def norm(v):
    length = math.sqrt(sum(c * c for c in v)) or 1
    return tuple(c / length for c in v)


def surface(body, x, y):
    """z of the front (-Z) surface of an ellipsoid body = ((cx, cy, cz), (sx, sy, sz)) at x, y."""
    (cx, cy, cz), (sx, sy, sz) = body
    a, b, c = sx / 2, sy / 2, sz / 2
    k = 1 - ((x - cx) / a) ** 2 - ((y - cy) / b) ** 2
    return cz - c * math.sqrt(max(0.0, k))


# ---------------------------------------------------------------------------
# The eight Thinglets
# ---------------------------------------------------------------------------
def blorp(ox):
    """Common - tomato. A squishy red jelly with one big eye and a leaf."""
    c = Creature("Blorp", ox)
    body = ((0, 0.43, 0), (1.0, 0.86, 0.95))
    c.blob("Body", "E84A4A", *body)
    for sx in (-1, 1):
        c.blob("Body", "C23434", (sx * 0.24, 0.05, -0.14), (0.26, 0.13, 0.3))  # little feet
    c.eye(0, 0.56, surface(body, 0, 0.56), 0.44, look=(0, -0.2))
    c.smile(0, 0.27, 0.24, 0.06, 0.028, body)
    for sx in (-1, 1):
        c.blush(sx * 0.31, 0.36, body)
    c.blob("Eye", "FFD3D3", (-0.28, 0.72, surface(body, -0.28, 0.72) + 0.03), (0.14, 0.1, 0.06), detail=1)  # jelly shine
    c.tube("Accent", "4E8F33", [(0.02, 0.84, 0.02), (0.03, 0.95, 0.03)], 0.03)  # stem
    c.blob("Accent", LEAF, (0.15, 0.95, 0.02), (0.3, 0.07, 0.16), roll=0.3, yaw=0.3)
    c.blob("Accent", LEAF, (-0.1, 0.94, 0.05), (0.24, 0.06, 0.13), roll=-0.35, yaw=-0.4)


def sizzle(ox):
    """Common - chili. A little fire lizard with a flame on its head."""
    c = Creature("Sizzle", ox)
    skin, dark = "F0602E", "C9461F"
    head = ((0, 0.55, -0.36), (0.64, 0.58, 0.56))
    c.blob("Body", skin, (0, 0.3, 0.14), (0.66, 0.5, 0.95))
    c.blob("Body", skin, *head)
    c.blob("Body", "FFB37A", (0, 0.22, -0.06), (0.44, 0.24, 0.5))  # pale belly
    c.tube("Body", skin, [(0, 0.3, 0.55), (0, 0.36, 0.78), (0.05, 0.5, 0.92), (0.12, 0.62, 0.9)], 0.12, r_end=0.04)
    for sx in (-1, 1):
        for sz in (-0.14, 0.4):
            c.blob("Body", dark, (sx * 0.25, 0.07, sz), (0.18, 0.14, 0.22))
    for sx in (-1, 1):
        c.eye(sx * 0.15, 0.62, surface(head, sx * 0.15, 0.62), 0.24, look=(sx * -0.2, 0))
        c.blush(sx * 0.24, 0.48, head, 0.11)
    c.smile(0, 0.45, 0.22, 0.05, 0.022, head)
    c.flame("Glow", "FF9A1F", (0, 0.9, -0.36), (0.3, 0.5, 0.3), lean=0.12)  # the flame
    c.flame("Glow", "FFE45C", (0, 0.86, -0.42), (0.16, 0.3, 0.16), lean=0.08)
    c.flame("Glow", "FF9A1F", (0.12, 0.68, 0.9), (0.13, 0.22, 0.13), lean=0.06)  # tail tip


def peeper(ox):
    """Rare - eyeberry. A fuzzy blue ball that looks at everything, three times."""
    c = Creature("Peeper", ox)
    body = ((0, 0.5, 0), (1.0, 1.0, 0.98))
    c.blob("Body", "5F73EB", *body)
    for sx in (-1, 1):
        c.blob("Body", "4556C4", (sx * 0.22, 0.04, -0.12), (0.24, 0.12, 0.28))
    c.eye(0, 0.66, surface(body, 0, 0.66), 0.36)
    c.eye(-0.28, 0.42, surface(body, -0.28, 0.42), 0.22, look=(0.3, 0.2))
    c.eye(0.29, 0.4, surface(body, 0.29, 0.4), 0.2, look=(-0.3, 0.2))
    c.smile(0, 0.2, 0.14, 0.035, 0.022, body)
    for sx in (-1, 1):
        c.blush(sx * 0.37, 0.27, body, 0.12)
    for (x, y, z, s) in [(0.1, 1.0, 0.0, 0.2), (-0.04, 1.04, 0.05, 0.16), (0.2, 0.96, 0.08, 0.13)]:
        c.blob("Accent", "96A5FF", (x, y, z), (s, s * 1.3, s))  # fluffy tuft


def glumcap(ox):
    """Rare - glowshroom. A sleepy mushroom with glowing spots."""
    c = Creature("Glumcap", ox)
    stalk = ((0, 0.33, 0), (0.56, 0.66, 0.54))
    c.blob("Body", "F0E6D2", *stalk)
    c.blob("Body", "3CBEBE", (0, 0.74, 0), (1.06, 0.5, 1.04), roll=0.1)  # the cap
    c.blob("Body", "2A8F8F", (0, 0.62, 0), (0.92, 0.14, 0.9), roll=0.1)  # gills under it
    for sx in (-1, 1):  # sleepy closed eyes: two little arcs
        x = sx * 0.11
        pts = []
        for i in range(6):
            t = -1 + 2 * i / 5
            px, py = x + t * 0.06, 0.4 - 0.025 * (1 - t * t)
            pts.append((px, py, surface(stalk, px, py) - 0.006))
        c.tube("Eye", INK, pts, 0.016)
        c.blush(sx * 0.18, 0.31, stalk, 0.09)
    c.blob("Eye", INK, (0, 0.27, surface(stalk, 0, 0.27) + 0.01), (0.07, 0.06, 0.04), detail=1)  # a tiny "o"
    for (x, y, z, s) in [(0.26, 0.93, -0.2, 0.15), (-0.3, 0.88, 0.08, 0.13), (0.04, 0.99, 0.22, 0.12),
                         (-0.12, 0.96, -0.3, 0.1), (0.36, 0.84, 0.22, 0.09)]:
        c.blob("Accent", "BEFFFA", (x, y, z), (s, s * 0.5, s), detail=1)


def gourdo(ox):
    """Epic - pumpkin. A round, happy pumpkin with a big grin."""
    c = Creature("Gourdo", ox)
    body = ((0, 0.46, 0), (1.04, 0.84, 0.98))
    for i, x in enumerate((-0.36, -0.18, 0.18, 0.36)):
        c.blob("Body", "F07E1C" if i % 3 == 0 else "FF8C23", (x, 0.46, 0), (0.46, 0.8, 0.86))
    c.blob("Body", "FF8C23", *body)
    for sx in (-1, 1):
        c.blob("Body", "C9631A", (sx * 0.26, 0.05, -0.12), (0.28, 0.12, 0.32))
    c.tube("Accent", "7A4E2D", [(0, 0.84, 0), (0.02, 0.98, 0.01), (0.07, 1.05, 0.03)], 0.06, r_end=0.045)
    vine = [(0.07, 0.95, 0.02)]
    for i in range(1, 9):  # a curly vine
        a = i * 0.8
        vine.append((0.07 + 0.08 * math.cos(a) * (1 - i / 12), 0.95 + i * 0.008, 0.02 + 0.08 * math.sin(a)))
    c.tube("Accent", LEAF, vine, 0.018)
    c.blob("Accent", LEAF, (-0.12, 0.9, 0.05), (0.26, 0.06, 0.16), roll=-0.3, yaw=0.5)
    for sx in (-1, 1):
        c.eye(sx * 0.19, 0.58, surface(body, sx * 0.19, 0.58), 0.26)
        c.blush(sx * 0.36, 0.42, body, 0.13)
    c.smile(0, 0.36, 0.42, 0.09, 0.03, body)
    c.blob("Eye", WHITE, (0.07, 0.29, surface(body, 0.07, 0.29) + 0.005), (0.07, 0.06, 0.04), detail=1)  # one tooth


def mishmash(ox):
    """Epic - a bit of everything. Patched together from the others."""
    c = Creature("Mishmash", ox)
    body = ((0, 0.45, 0), (1.0, 0.9, 0.95))
    c.blob("Body", "8A5CB8", *body)
    c.blob("Body", "6EC85A", (0.35, 0.33, surface(body, 0.35, 0.33) + 0.05), (0.3, 0.3, 0.1), yaw=-0.55)  # a patch
    for y in (0.25, 0.33, 0.41):  # stitches along its edge
        x = 0.2
        c.tube("Eye", INK, [(x - 0.035, y, surface(body, x - 0.035, y) - 0.008),
                            (x + 0.035, y, surface(body, x + 0.035, y) - 0.008)], 0.011)
    for sx in (-1, 1):
        c.blob("Body", "6B4492", (sx * 0.24, 0.05, -0.12), (0.26, 0.12, 0.3))
    c.eye(-0.17, 0.58, surface(body, -0.17, 0.58), 0.32, look=(0.2, 0))
    c.eye(0.21, 0.64, surface(body, 0.21, 0.64), 0.19, look=(-0.3, 0.3))
    c.smile(-0.07, 0.28, 0.24, 0.05, 0.024, body, tilt=0.025)
    c.blush(-0.33, 0.38, body, 0.12)
    c.blob("Accent", "3CBEBE", (0.06, 0.9, 0.02), (0.56, 0.24, 0.54), roll=-0.25)  # a little Glumcap hat
    c.blob("Accent", "BEFFFA", (0.18, 0.98, -0.1), (0.1, 0.05, 0.1), detail=1)
    c.blob("Accent", LEAF, (-0.3, 0.86, 0.05), (0.26, 0.06, 0.14), roll=0.5, yaw=0.4)  # a Blorp leaf
    c.flame("Glow", "FF9A1F", (0, 0.5, 0.52), (0.2, 0.36, 0.2), lean=0.15)  # a Sizzle flame for a tail


def moonmoth(ox):
    """Legendary - moon melon. A fluffy moth with glowing wings."""
    c = Creature("Moonmoth", ox)
    fuzz = "F5F0E1"
    head = ((0, 0.62, -0.36), (0.5, 0.48, 0.46))
    c.blob("Body", fuzz, (0, 0.48, 0.1), (0.44, 0.44, 0.82))
    c.blob("Body", fuzz, *head)
    c.blob("Body", "E6DFC8", (0, 0.5, -0.12), (0.56, 0.36, 0.3))  # fluffy collar
    for sx in (-1, 1):
        c.blob("Accent", "C8F0BE", (sx * 0.46, 0.74, 0.04), (0.86, 0.06, 0.68), roll=-sx * 0.42, yaw=sx * 0.12)
        c.blob("Accent", "C8F0BE", (sx * 0.34, 0.5, 0.3), (0.5, 0.05, 0.4), roll=-sx * 0.2, yaw=-sx * 0.3)
        c.blob("Glow", "8CF0AA", (sx * 0.56, 0.82, 0.04), (0.22, 0.04, 0.2), roll=-sx * 0.42, detail=1)
        c.blob("Glow", "8CF0AA", (sx * 0.36, 0.69, 0.1), (0.12, 0.04, 0.1), roll=-sx * 0.42, detail=1)
        c.tube("Body", "D9CFB4", [(sx * 0.08, 0.8, -0.42), (sx * 0.13, 0.98, -0.5), (sx * 0.2, 1.06, -0.62)], 0.018)
        c.blob("Glow", "FFF096", (sx * 0.2, 1.06, -0.63), (0.08, 0.08, 0.08), detail=1)
        c.eye(sx * 0.13, 0.66, surface(head, sx * 0.13, 0.66), 0.21, sclera="3A2450", pupil=None)
        c.blush(sx * 0.17, 0.53, head, 0.08)
        for sz in (-0.12, 0.1):  # little dangling legs (it hovers)
            c.tube("Body", "D9CFB4", [(sx * 0.12, 0.32, sz), (sx * 0.17, 0.2, sz - 0.03)], 0.025)
    c.smile(0, 0.55, 0.08, 0.02, 0.014, head)


def lilthing(ox):
    """Legendary secret - a tiny Thing: a shadow with glowing eyes, waving."""
    c = Creature("LilThing", ox)
    body = ((0, 0.42, 0), (0.72, 0.8, 0.7))
    c.blob("Body", "0A0510", (0, 0.02, 0), (1.0, 0.04, 0.92), detail=3)  # its own little puddle
    c.blob("Body", "1C1028", *body)
    c.blob("Body", "1C1028", (0.2, 0.1, -0.2), (0.24, 0.16, 0.24))  # drips
    c.blob("Body", "1C1028", (-0.22, 0.08, -0.12), (0.2, 0.12, 0.2))
    for sx in (-1, 1):
        c.blob("Glow", "D7FF5A", (sx * 0.13, 0.56, surface(body, sx * 0.13, 0.56) + 0.03), (0.15, 0.21, 0.08))
    c.smile(0, 0.36, 0.22, 0.05, 0.018, body, hex_color="D7FF5A")
    skin = "46235F"
    c.tube("Body", skin, [(-0.3, 0.45, -0.02), (-0.46, 0.6, -0.06), (-0.52, 0.8, -0.1)], 0.055, r_end=0.04)
    c.blob("Body", skin, (-0.53, 0.84, -0.11), (0.13, 0.13, 0.1))
    c.tube("Body", skin, [(0.3, 0.4, -0.02), (0.44, 0.32, -0.08), (0.5, 0.2, -0.12)], 0.055, r_end=0.04)
    c.blob("Body", skin, (0.51, 0.17, -0.13), (0.13, 0.13, 0.1))


def egg(ox):
    """The egg every Thinglet hatches from. Its spots take the rarity's colour."""
    c = Creature("Egg", ox)
    m = c.mesh("Body", "FAF5E6")
    # an egg: a ball that's narrower towards the top
    before = len(m.verts)
    m.blob(c.base * at(0, 0.5, 0), (0.78, 1.0, 0.78), "white", detail=3)
    for i in range(before, len(m.verts)):
        x, y, z = m.verts[i]
        h = (y - 0.5) / 0.5  # -1 bottom .. 1 top
        k = 1 - 0.16 * max(0.0, h) - 0.04 * h
        m.verts[i] = (ox + (x - ox) * k, y, z * k)
    shell = ((0, 0.5, 0), (0.78, 1.0, 0.78))
    spots = [(0.18, 0.62, 0.13), (-0.22, 0.4, 0.15), (0.05, 0.26, 0.12), (-0.08, 0.8, 0.09), (0.28, 0.36, 0.09)]
    for x, y, s in spots:
        z = surface(shell, x, y) * (1 - 0.16 * max(0.0, (y - 0.5) / 0.5)) + 0.02
        c.blob("Accent", WHITE, (x, y, z), (s, s, 0.05), detail=1)
    for x, y, s in spots[:3]:  # and on the back
        z = -surface(shell, -x, y) * (1 - 0.16 * max(0.0, (y - 0.5) / 0.5)) - 0.02
        c.blob("Accent", WHITE, (-x, y, z), (s, s, 0.05), detail=1)


ORDER = [blorp, sizzle, peeper, glumcap, gourdo, mishmash, moonmoth, lilthing, egg]


def build_all(start_x, spacing=2.0):
    for i, make in enumerate(ORDER):
        make(start_x + i * spacing)


def finish():
    """After build_objects: weld each object's pieces into smooth shapes and give the
    previews their real colours (the game colours them from the names anyway)."""
    import bmesh
    import bpy
    for creature in CREATURES:
        for (role, hex_color), m in creature.meshes.items():
            obj = bpy.data.objects.get(m.name)
            if not obj:
                continue
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bm.to_mesh(obj.data)
            bm.free()
            for poly in obj.data.polygons:
                poly.use_smooth = True
            obj.data.update()
            mat = bpy.data.materials.new(m.name)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            rgb = tuple(srgb_to_linear(int(hex_color[i:i + 2], 16) / 255) for i in (0, 2, 4))
            bsdf.inputs["Base Color"].default_value = (*rgb, 1)
            bsdf.inputs["Roughness"].default_value = 0.45
            if role == "Glow":
                bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
                bsdf.inputs["Emission Strength"].default_value = 2.5
            obj.data.materials.clear()
            obj.data.materials.append(mat)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
