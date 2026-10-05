"""
Feed the Thing in the Basement - the neighbourhood map, built in Blender.

Run it with Blender (any 4.x/5.x):
    blender --background --python build_map.py
or with the `bpy` Python module:
    python build_map.py

It writes, next to this file:
    Map.blend                     the scene: open it in Blender to look or edit
    Export/FeedTheThing_Map.fbx   import this into Roblox Studio (textures inside)
    Textures/*.png                the stud textures and the colour palette
    Previews/*.png                rendered previews

Units: 1 Blender unit = 1 Roblox stud. The scene's unit scale is 0.01
(centimetres), so the FBX comes out at 1 unit per stud. The game also lines
the map up by three marker blocks (MapOrigin, MapMarkX, MapMarkZ), so a
different import scale or position is corrected automatically.

All positions below are written in ROBLOX coordinates (X right, Y up, Z
towards the back) and converted to Blender's (Z up) at the end. They must
match Config.World in ReplicatedStorage/Config.lua.
"""

import math
import os
import sys

import bpy
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
TEX_DIR = os.path.join(HERE, "Textures")
EXPORT_DIR = os.path.join(HERE, "Export")
PREVIEW_DIR = os.path.join(HERE, "Previews")
FONT_PATH = os.path.join(HERE, "FredokaOne-Regular.ttf")
for d in (TEX_DIR, EXPORT_DIR, PREVIEW_DIR):
    os.makedirs(d, exist_ok=True)

RENDER = "--no-render" not in sys.argv

# ---------------------------------------------------------------------------
# Layout (keep in step with Config.World)
# ---------------------------------------------------------------------------
PLOTS_PER_SIDE = 4
PLOT_SPACING = 80
PLOT_ORDER = [(1, 2), (-1, 2), (1, 3), (-1, 3), (1, 1), (-1, 1), (1, 4), (-1, 4)]
ROAD_W = 24
SIDEWALK_W = 6
FRONT_YARD = 2
PLOT_W, PLOT_D = 70, 100
PIT, PIT_DEPTH = 14, 9
HATCH = (0, 21)  # plot-local x, z
HOUSE = (0, 42)
PLANT_SPOTS = [(-13, 16), (13, 16), (-13, 26), (13, 26), (-21, 16), (21, 16),
               (-21, 26), (21, 26), (-29, 21), (29, 21)]
WALL_H = 24
WALL_TILE = 10
ROAD_PAST_PLOTS = 10
PLAZA_LENGTH = 50
PLAZA_HALF_WIDTH = 40
BACK_YARD = 15
TUNNEL_R = 13          # a tunnel into the wall at each end of the street (Config.World.TunnelRadius)
TUNNEL_SPRING = 9      # how high its straight sides go before the arch starts
TUNNEL_DEPTH = 40      # how far it goes back into the dark
TUNNEL_SEGMENTS = 9    # blocks round the arch
TUNNEL_BANDS = [0, 2, 5, 9, 14, 21, 30, TUNNEL_DEPTH]   # it gets darker band by band
TUNNEL_SHADES = [0.8, 0.55, 0.36, 0.22, 0.12, 0.06, 0.03]
STAND_Z = -28          # the seed stand, beside the west tunnel (Config.World.StandZ)

HALF_ROAD = ROAD_W / 2
SIDEWALK_OUT = HALF_ROAD + SIDEWALK_W            # 18
PLOT_FRONT = SIDEWALK_OUT + FRONT_YARD           # 20
PLOT_BACK = PLOT_FRONT + PLOT_D                  # 120
MAP_Z = PLOT_BACK + BACK_YARD                    # 135 (walls)
STREET_X = (PLOTS_PER_SIDE - 1) / 2 * PLOT_SPACING + PLOT_W / 2   # 155: last plot's far edge
ROAD_X = STREET_X + ROAD_PAST_PLOTS              # 165: the road ends at the plazas
MAP_X = ROAD_X + PLAZA_LENGTH                    # 215 (walls)
PLAZA_Z = PLAZA_HALF_WIDTH


def plot_frame(i):
    """(centre x, centre z, yaw) of plot i (1-based), like Rules.plotCFrame."""
    side, column = PLOT_ORDER[i - 1]
    x = (column - (PLOTS_PER_SIDE + 1) / 2) * PLOT_SPACING
    z = side * (PLOT_FRONT + PLOT_D / 2)
    yaw = 0.0 if side == 1 else math.pi  # every plot faces the road (local -Z)
    return x, z, yaw


# ---------------------------------------------------------------------------
# Colours. Flat colours live in one small palette image; every face is
# UV-mapped onto its colour's swatch, so the whole kit shares one texture.
# ---------------------------------------------------------------------------
PALETTE = {
    "asphalt": (66, 68, 78), "line_yellow": (255, 205, 40), "line_white": (245, 245, 245),
    "pit": (14, 8, 22), "pit_wall": (30, 20, 40),
    "wood": (175, 100, 50), "wood_dark": (110, 65, 40), "post": (80, 55, 50),
    "dirt_frame": (150, 90, 45),
    "stone": (170, 170, 178), "stone_dark": (120, 120, 130),
    "white": (250, 248, 240), "glass": (150, 210, 255), "door": (120, 70, 45), "gold": (255, 200, 50),
    "brick": (185, 80, 65), "brick_dark": (140, 55, 45), "foundation": (140, 140, 150),
    "mail_blue": (60, 120, 230), "flag_red": (230, 50, 50),
    "lamp_pole": (55, 60, 75), "lamp_head": (40, 45, 60),
    "trunk": (120, 75, 40), "leaf": (70, 175, 50), "leaf_light": (105, 205, 60), "hedge": (60, 150, 45),
    "hydrant": (225, 45, 45),
    "awning_red": (230, 60, 60), "awning_white": (250, 250, 250),
    "crate": (190, 135, 70), "tomato": (235, 60, 50), "chili": (215, 30, 30), "melon": (200, 245, 190),
    "pumpkin": (255, 140, 30), "berry": (80, 100, 230), "shroom": (60, 220, 210), "leafy": (80, 170, 60),
    "sign_purple": (75, 40, 110), "sign_purple_dark": (45, 25, 70), "letter_yellow": (255, 215, 60),
    "letter_lime": (190, 255, 70), "pillar": (225, 160, 95), "pillar_dark": (190, 125, 70),
    "bench": (160, 95, 50), "bench_leg": (60, 60, 70),
}
HOUSE_COLORS = [(255, 120, 120), (90, 170, 255), (255, 200, 70), (120, 210, 120),
                (190, 130, 255), (255, 150, 70), (80, 210, 200), (255, 140, 200)]
ROOF_COLORS = [(170, 40, 50), (30, 80, 170), (190, 110, 30), (40, 120, 60),
               (100, 50, 160), (170, 70, 30), (20, 110, 110), (170, 50, 120)]
for k, c in enumerate(HOUSE_COLORS):
    PALETTE[f"house{k + 1}"] = c
    PALETTE[f"house{k + 1}_dark"] = tuple(int(v * 0.8) for v in c)
for k, c in enumerate(ROOF_COLORS):
    PALETTE[f"roof{k + 1}"] = c
    PALETTE[f"roof{k + 1}_dark"] = tuple(int(v * 0.75) for v in c)
# colours for the props (build_props.py). Added after the others, so the
# map's swatches never move.
PALETTE.update({
    "truck_red": (230, 55, 50), "truck_red_dark": (170, 35, 35), "cargo": (255, 245, 225),
    "cargo_stripe": (80, 200, 70), "tire": (35, 35, 40), "hub": (200, 205, 215), "chrome": (225, 230, 240),
    "cardboard": (205, 150, 90), "cardboard_dark": (165, 115, 65), "tape": (235, 205, 140),
    "roof_light": (255, 170, 40), "headlight": (255, 245, 200),
})
# the tunnels' insides, fading to black
PALETTE.update({f"tunnel_wall{k}": tuple(int(v * f) for v in (150, 135, 175)) for k, f in enumerate(TUNNEL_SHADES)})
PALETTE.update({f"tunnel_floor{k}": tuple(int(v * f) for v in (66, 68, 78)) for k, f in enumerate(TUNNEL_SHADES)})
PALETTE["tunnel_end"] = (3, 2, 5)

SWATCH = 32
PAL_N = 16  # 16 x 16 swatches of 32 px = a 512 px image (big swatches don't bleed at a distance)
assert len(PALETTE) <= PAL_N * PAL_N
PAL_KEYS = list(PALETTE.keys())


def palette_uv(key):
    i = PAL_KEYS.index(key)
    col, row = i % PAL_N, i // PAL_N
    return ((col + 0.5) / PAL_N, 1 - (row + 0.5) / PAL_N)


# ---------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------
def save_palette():
    img = Image.new("RGB", (PAL_N * SWATCH, PAL_N * SWATCH), (255, 0, 255))
    d = ImageDraw.Draw(img)
    for i, key in enumerate(PAL_KEYS):
        col, row = i % PAL_N, i // PAL_N
        d.rectangle([col * SWATCH, row * SWATCH, col * SWATCH + SWATCH - 1, row * SWATCH + SWATCH - 1], fill=PALETTE[key])
    path = os.path.join(TEX_DIR, "palette.png")
    img.save(path)
    return path


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def stud_texture(name, base, studs=4, size=256, checker=None, seam=True):
    """A tile of LEGO-style studs. `checker` = (colourA, colourB, squares per tile)."""
    s = 4  # supersample, then shrink for smooth circles
    big = size * s
    img = Image.new("RGB", (big, big), base)
    d = ImageDraw.Draw(img)
    if checker:
        a, b, n = checker
        q = big // n
        for cy in range(n):
            for cx in range(n):
                d.rectangle([cx * q, cy * q, cx * q + q - 1, cy * q + q - 1], fill=a if (cx + cy) % 2 == 0 else b)
    cell = big / studs
    for cy in range(studs):
        for cx in range(studs):
            ox, oy = cx * cell, cy * cell
            colour = img.getpixel((int(ox + cell / 2), int(oy + cell / 2)))
            r = cell * 0.30
            mx, my = ox + cell / 2, oy + cell / 2
            off = cell * 0.05
            # soft shadow, the stud, a lit rim and a shine
            d.ellipse([mx - r + off, my - r + off * 1.6, mx + r + off, my + r + off * 1.6], fill=shade(colour, 0.78))
            d.ellipse([mx - r, my - r, mx + r, my + r], fill=shade(colour, 1.0))
            d.ellipse([mx - r * 0.86, my - r * 0.86, mx + r * 0.86, my + r * 0.86], fill=shade(colour, 1.07))
            d.arc([mx - r * 0.7, my - r * 0.7, mx + r * 0.7, my + r * 0.7], 200, 290, fill=shade(colour, 1.25), width=int(cell * 0.06))
    if seam:
        w = max(2, int(big * 0.006))
        dark = shade(base, 0.85)
        d.rectangle([0, 0, big - 1, w], fill=dark)
        d.rectangle([0, 0, w, big - 1], fill=dark)
    img = img.resize((size, size), Image.LANCZOS)
    path = os.path.join(TEX_DIR, name + ".png")
    img.save(path)
    return path


# ---------------------------------------------------------------------------
# Mesh building. Everything is placed in Roblox space and converted at the
# end: Roblox (x, y, z) -> Blender (x, -z, y). That's a rotation, so face
# winding (which side is the front) is kept.
# ---------------------------------------------------------------------------
def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def apply(m, v):
    return tuple(m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] for i in range(3))


IDENTITY = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


class Frame:
    """A position + rotation in Roblox space (like a CFrame)."""

    def __init__(self, pos=(0, 0, 0), rot=IDENTITY):
        self.pos = tuple(pos)
        self.rot = rot

    def __mul__(self, other):
        return Frame(tuple(a + b for a, b in zip(self.pos, apply(self.rot, other.pos))), mat_mul(self.rot, other.rot))

    def point(self, v):
        return tuple(a + b for a, b in zip(self.pos, apply(self.rot, v)))


def at(x, y, z, yaw=0.0, pitch=0.0, roll=0.0):
    return Frame((x, y, z), mat_mul(rot_y(yaw), mat_mul(rot_x(pitch), rot_z(roll))))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


class Mesh:
    """Collects faces for one Blender object (one material)."""

    def __init__(self, name, texture="palette", tile=None, smooth=False):
        self.name = name
        self.texture = texture
        self.tile = tile  # studs per texture tile, for planar-mapped stud textures
        self.smooth = smooth
        self.verts, self.faces, self.uvs, self.smooth_flags = [], [], [], []

    # a polygon in world (Roblox) space; `outward` makes sure it faces that way
    def poly(self, points, key=None, outward=None, smooth=False):
        if outward is not None:
            n = cross(sub(points[1], points[0]), sub(points[2], points[0]))
            if dot(n, outward) < 0:
                points = list(reversed(points))
        base = len(self.verts)
        self.verts.extend(points)
        self.faces.append(list(range(base, base + len(points))))
        self.smooth_flags.append(smooth)
        if self.tile:
            n = cross(sub(points[1], points[0]), sub(points[2], points[0]))
            ax = max(range(3), key=lambda k: abs(n[k]))  # project along the face's main axis
            a, b = {0: (2, 1), 1: (0, 2), 2: (0, 1)}[ax]
            self.uvs.append([(p[a] / self.tile, p[b] / self.tile) for p in points])
        else:
            u, v = palette_uv(key or "white")
            self.uvs.append([(u, v)] * len(points))

    def box(self, frame, size, key=None, faces="all", keys=None):
        """A box of `size` centred on `frame`. faces: 'all' or a set like {'top','+x'}."""
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
        c = lambda x, y, z: frame.point((x * sx, y * sy, z * sz))
        sides = {
            "top": ([c(-1, 1, -1), c(-1, 1, 1), c(1, 1, 1), c(1, 1, -1)], (0, 1, 0)),
            "bottom": ([c(-1, -1, -1), c(1, -1, -1), c(1, -1, 1), c(-1, -1, 1)], (0, -1, 0)),
            "+x": ([c(1, -1, -1), c(1, 1, -1), c(1, 1, 1), c(1, -1, 1)], (1, 0, 0)),
            "-x": ([c(-1, -1, -1), c(-1, -1, 1), c(-1, 1, 1), c(-1, 1, -1)], (-1, 0, 0)),
            "+z": ([c(-1, -1, 1), c(1, -1, 1), c(1, 1, 1), c(-1, 1, 1)], (0, 0, 1)),
            "-z": ([c(-1, -1, -1), c(-1, 1, -1), c(1, 1, -1), c(1, -1, -1)], (0, 0, -1)),
        }
        for name, (pts, normal) in sides.items():
            if faces != "all" and name not in faces:
                continue
            self.poly(pts, (keys or {}).get(name, key), apply(frame.rot, normal))

    def cylinder(self, frame, radius, height, key, sides=10, top=True, bottom=False, radius_top=None, smooth=False):
        """Upright cylinder (or cone) standing on `frame` (frame = bottom centre)."""
        rt = radius if radius_top is None else radius_top
        ring_b = [frame.point((math.cos(t) * radius, 0, math.sin(t) * radius)) for t in (2 * math.pi * k / sides for k in range(sides))]
        ring_t = [frame.point((math.cos(t) * rt, height, math.sin(t) * rt)) for t in (2 * math.pi * k / sides for k in range(sides))]
        centre = frame.point((0, height / 2, 0))
        for k in range(sides):
            k2 = (k + 1) % sides
            pts = [ring_b[k], ring_b[k2], ring_t[k2], ring_t[k]] if rt > 0.001 else [ring_b[k], ring_b[k2], ring_t[k]]
            mid = tuple(sum(p[i] for p in pts) / len(pts) for i in range(3))
            self.poly(pts, key, sub(mid, centre), smooth)
        if top and rt > 0.001:
            self.poly(ring_t, key, apply(frame.rot, (0, 1, 0)))
        if bottom:
            self.poly(list(reversed(ring_b)), key, apply(frame.rot, (0, -1, 0)))

    def blob(self, frame, size, key, detail=1, smooth=True):
        """A low-poly ellipsoid (icosphere) of `size` centred on `frame`."""
        t = (1 + 5 ** 0.5) / 2
        vs = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
              (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
        fs = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
              (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
              (8, 6, 7), (9, 8, 1)]
        vs = [tuple(c / math.sqrt(sum(x * x for x in v)) for c in v) for v in vs]
        for _ in range(detail):
            cache, new = {}, []

            def midpoint(a, b):
                key2 = (min(a, b), max(a, b))
                if key2 not in cache:
                    m = tuple((vs[a][i] + vs[b][i]) / 2 for i in range(3))
                    l = math.sqrt(sum(x * x for x in m))
                    vs.append(tuple(x / l for x in m))
                    cache[key2] = len(vs) - 1
                return cache[key2]

            for a, b, c in fs:
                ab, bc, ca = midpoint(a, b), midpoint(b, c), midpoint(c, a)
                new += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            fs = new
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
        world = [frame.point((v[0] * sx, v[1] * sy, v[2] * sz)) for v in vs]
        for a, b, c in fs:
            pts = [world[a], world[b], world[c]]
            mid = tuple(sum(p[i] for p in pts) / 3 for i in range(3))
            self.poly(pts, key, sub(mid, frame.pos), smooth)

    def prism(self, frame, width, height, depth, key):
        """A triangular prism (a gable end): width along X, peak up, depth along Z."""
        w, h, d = width / 2, height, depth / 2
        p = lambda x, y, z: frame.point((x, y, z))
        front = [p(-w, 0, -d), p(w, 0, -d), p(0, h, -d)]
        back = [p(-w, 0, d), p(w, 0, d), p(0, h, d)]
        self.poly(front, key, apply(frame.rot, (0, 0, -1)))
        self.poly(back, key, apply(frame.rot, (0, 0, 1)))
        self.poly([front[0], front[2], back[2], back[0]], key, apply(frame.rot, (-h, w, 0)))
        self.poly([front[1], back[1], back[2], front[2]], key, apply(frame.rot, (h, w, 0)))

    def text(self, frame, body, size, depth, key, align="CENTER"):
        """3D letters (Fredoka One) standing up, facing -Z of `frame`, baseline at frame."""
        curve = bpy.data.curves.new(name="txt", type="FONT")
        curve.body = body
        curve.font = bpy.data.fonts.load(FONT_PATH, check_existing=True)
        curve.size = size
        curve.extrude = depth / 2
        curve.align_x = align
        curve.resolution_u = 4
        obj = bpy.data.objects.new("txt", curve)
        bpy.context.scene.collection.objects.link(obj)
        dg = bpy.context.evaluated_depsgraph_get()
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        # Blender text lies in its XY plane, read from +Z. Turned 180 degrees
        # about Y it faces Roblox-local -Z and reads left to right from there.
        for poly in mesh.polygons:
            pts = [frame.point((-mesh.vertices[i].co.x, mesh.vertices[i].co.y, -mesh.vertices[i].co.z)) for i in poly.vertices]
            n = poly.normal
            self.poly(pts, key, apply(frame.rot, (-n.x, n.y, -n.z)))
        bpy.data.objects.remove(obj)
        bpy.data.curves.remove(curve)
        bpy.data.meshes.remove(mesh)

    def triangles(self):
        return sum(len(f) - 2 for f in self.faces)


MESHES = []


def new_mesh(*args, **kwargs):
    m = Mesh(*args, **kwargs)
    MESHES.append(m)
    return m


# ---------------------------------------------------------------------------
# The ground
# ---------------------------------------------------------------------------
def top_rect(mesh, x0, x1, z0, z1, y):
    mesh.poly([(x0, y, z0), (x0, y, z1), (x1, y, z1), (x1, y, z0)], outward=(0, 1, 0))


def build_ground():
    grass = new_mesh("Grass", texture="studs_grass", tile=8)
    plot_xs = sorted(set(plot_frame(i)[0] for i in range(1, 9)))
    gaps, prev = [], -MAP_X
    for x in plot_xs:
        gaps.append((prev, x - PLOT_W / 2))
        prev = x + PLOT_W / 2
    gaps.append((prev, MAP_X))
    bands = [(-MAP_Z, -PLOT_BACK, None), (-PLOT_BACK, -PLOT_FRONT, gaps), (-PLOT_FRONT, PLOT_FRONT, None),
             (PLOT_FRONT, PLOT_BACK, gaps), (PLOT_BACK, MAP_Z, None)]
    for z0, z1, splits in bands:
        for x0, x1 in (splits or [(-MAP_X, MAP_X)]):
            if x1 - x0 > 0.01:
                top_rect(grass, x0, x1, z0, z1, 0)

    # plot lawns, with a hole for each hatch pit
    lawn = new_mesh("Lawn", texture="studs_lawn", tile=8)
    for i in range(1, 9):
        cx, cz, yaw = plot_frame(i)
        f = at(cx, 0, cz, yaw)
        hx, hz = HATCH
        h = PIT / 2
        hw, hd = PLOT_W / 2, PLOT_D / 2
        for (x0, x1, z0, z1) in [(-hw, hx - h, -hd, hd), (hx + h, hw, -hd, hd), (hx - h, hx + h, -hd, hz - h), (hx - h, hx + h, hz + h, hd)]:
            pts = [f.point((x0, 0, z0)), f.point((x0, 0, z1)), f.point((x1, 0, z1)), f.point((x1, 0, z0))]
            lawn.poly(pts, outward=(0, 1, 0))


def build_street():
    road = new_mesh("Road")
    # the road runs on across the plazas and into the tunnels in the end walls
    road.box(at(0, 0.05, 0), (MAP_X * 2, 0.3, ROAD_W), "asphalt", faces={"top"})
    lines = new_mesh("RoadLines")
    # dashed yellow middle line, white edges, three crossings
    x = -MAP_X + 2
    while x < MAP_X - 6:
        lines.box(at(x + 3, 0.21, 0), (6, 0.02, 0.7), "line_yellow", faces={"top"})
        x += 13
    for z in (-HALF_ROAD + 1, HALF_ROAD - 1):
        lines.box(at(0, 0.21, z), (MAP_X * 2, 0.02, 0.5), "line_white", faces={"top"})
    for cx in (-ROAD_X + 8, 0, ROAD_X - 8):
        for k in range(7):
            z = -HALF_ROAD + 2.2 + k * 3.27
            lines.box(at(cx, 0.22, z), (8, 0.02, 1.6), "line_white", faces={"top"})

    side = new_mesh("Sidewalk", texture="studs_sidewalk", tile=4)
    for s in (1, -1):
        side.box(at(0, 0.1, s * (HALF_ROAD + SIDEWALK_W / 2)), (ROAD_X * 2, 0.6, SIDEWALK_W), faces={"top", "+z" if s < 0 else "-z"})

    plaza = new_mesh("Plaza", texture="studs_plaza", tile=4)
    for s in (1, -1):
        x0 = s * ROAD_X
        x1 = s * (MAP_X - 1)
        cx, w = (x0 + x1) / 2, abs(x1 - x0)
        for sz in (1, -1):  # either side of the road
            cz, d = sz * (HALF_ROAD + PLAZA_Z) / 2, PLAZA_Z - HALF_ROAD
            plaza.box(at(cx, 0.0, cz), (w, 0.4, d), faces={"top", "+z" if sz > 0 else "-z", "-x" if s > 0 else "+x"})


def build_walls():
    wall = new_mesh("Wall", texture="studs_wall", tile=WALL_TILE * 2)
    top = new_mesh("WallTop", texture="studs_walltop", tile=4)
    t = 2
    # inner faces of the four walls (the outside is never seen)
    for s in (1, -1):
        wall.box(at(0, WALL_H / 2, s * (MAP_Z + t / 2)), (MAP_X * 2 + t * 2, WALL_H, t), faces={"-z" if s > 0 else "+z"})
        # the end walls, with a hole for the tunnel (the arch of blocks round it hides the edge)
        f = tunnel_frame(s)
        face = apply(f.rot, (0, 0, -1))
        hole = TUNNEL_R + 2.5
        for side in (1, -1):
            wall.poly([f.point((side * hole, 0, 0)), f.point((side * MAP_Z, 0, 0)),
                       f.point((side * MAP_Z, WALL_H, 0)), f.point((side * hole, WALL_H, 0))], outward=face)
        rim = arch_points(hole)
        for (xa, ya), (xb, yb) in zip(rim, rim[1:]):
            pts = clean([(xa, min(ya, WALL_H)), (xb, min(yb, WALL_H)), (xb, WALL_H), (xa, WALL_H)])
            if len(pts) >= 3:
                wall.poly([f.point((x, y, 0)) for x, y in pts], outward=face)
        # the tunnel behind the wall gets a grassy lid and sides, so it looks
        # like solid ground from above (zoomed-out cameras peek over the wall)
        hw, back, lid = TUNNEL_R + 4, TUNNEL_DEPTH + 1, WALL_H + 1.5
        top.box(f * at(0, lid - 0.75, (t + 0.5 + back) / 2), (hw * 2, 1.5, back - t - 0.5), faces={"top"})
        for side in (1, -1):
            wall.box(f * at(side * hw, lid / 2, (t + back) / 2), (0.01, lid, back - t), faces={"+x" if side > 0 else "-x"})
        wall.box(f * at(0, lid / 2, back), (hw * 2, lid, 0.01), faces={"+z"})
        top.box(at(0, WALL_H + 0.75, s * (MAP_Z + t / 2)), (MAP_X * 2 + t * 2 + 1, 1.5, t + 1), faces={"top", "-z" if s > 0 else "+z"})
        top.box(at(s * (MAP_X + t / 2), WALL_H + 0.75, 0), (t + 1, 1.5, MAP_Z * 2 + 1), faces={"top", "-x" if s > 0 else "+x"})


# ---------------------------------------------------------------------------
# A plot: hatch pit, fence, planters, stepping stones, mailbox, house
# ---------------------------------------------------------------------------
def fence_line(mesh, f, x0, z0, x1, z1):
    """An X-braced wooden fence from (x0,z0) to (x1,z1), plot-local."""
    length = math.hypot(x1 - x0, z1 - z0)
    yaw = math.atan2(-(z1 - z0), x1 - x0)  # local +X runs along the fence
    base = f * at(x0, 0, z0, yaw)
    segs = max(1, round(length / 10))
    seg = length / segs
    h0, h1 = 0.7, 3.1  # between the rails
    for k in range(segs + 1):
        mesh.box(base * at(k * seg, 1.9, 0), (0.8, 3.8, 0.8), "post")
    for y in (h0, h1):
        mesh.box(base * at(length / 2, y, 0), (length, 0.45, 0.35), "wood")
    brace = math.hypot(seg, h1 - h0)
    angle = math.atan2(h1 - h0, seg)
    for k in range(segs):
        mid = base * at(k * seg + seg / 2, (h0 + h1) / 2, 0)
        mesh.box(mid * at(0, 0, 0, 0, 0, angle), (brace, 0.4, 0.25), "wood")
        mesh.box(mid * at(0, 0, 0, 0, 0, -angle), (brace, 0.4, 0.25), "wood")


def build_house(mesh, f, n):
    hx, hz = HOUSE
    b = f * at(hx, 0, hz)
    W, H, D = 24, 12, 14
    wall, wall_dark, roof, roof_dark = f"house{n}", f"house{n}_dark", f"roof{n}", f"roof{n}_dark"
    mesh.box(b * at(0, 0.5, 0), (W + 0.6, 1, D + 0.6), "foundation")
    mesh.box(b * at(0, 1 + (H - 1) / 2, 0), (W, H - 1, D), wall)
    for sx in (-1, 1):
        for sz in (-1, 1):
            mesh.box(b * at(sx * (W / 2 - 0.2), H / 2 + 0.5, sz * (D / 2 - 0.2)), (0.8, H - 1, 0.8), "white")
    mesh.box(b * at(0, H - 0.3, 0), (W + 0.4, 0.6, D + 0.4), "white")
    # gable roof: two slabs and the triangles at the ends
    rise, over = 5.5, 1.2
    half = D / 2 + over
    slope = math.atan2(rise, D / 2)
    slab = math.hypot(half, rise * half / (D / 2))
    for s in (-1, 1):
        cz = s * half / 2
        mesh.box(b * at(0, H + rise / 2 + 0.2, cz, 0, s * slope, 0), (W + 2 * over, 0.8, slab), roof,
                 keys={"top": roof, "bottom": roof_dark})
    for sx in (-1, 1):
        mesh.prism(b * at(sx * (W / 2 - 0.2), H, 0, math.pi / 2), D, rise, 0.6, wall_dark)
    mesh.box(b * at(0, H + rise + 0.45, 0), (W + 2 * over + 0.2, 0.5, 0.9), roof_dark)
    # chimney
    mesh.box(b * at(7, H + 4, 3), (2.6, 7, 2.6), "brick")
    mesh.box(b * at(7, H + 7.7, 3), (3.2, 0.6, 3.2), "brick_dark")
    # the front (-Z) faces the hatch and the road
    fz = -D / 2
    mesh.box(b * at(0, 1 + 3.6, fz - 0.15), (5.4, 7.6, 0.3), "white")
    mesh.box(b * at(0, 1 + 3.5, fz - 0.3), (4.2, 7, 0.3), "door")
    mesh.blob(b * at(1.4, 4.4, fz - 0.55), (0.5, 0.5, 0.5), "gold", detail=0)
    mesh.box(b * at(0, 9.2, fz - 1.4), (7, 0.5, 3), roof)
    for sx in (-2.8, 2.8):
        mesh.box(b * at(sx, 5, fz - 2.5), (0.5, 8.5, 0.5), "white")
    mesh.box(b * at(0, 0.35, fz - 1.8), (7, 0.7, 3.6), "stone")
    for sx in (-7.5, 7.5):
        mesh.box(b * at(sx, 6.5, fz - 0.15), (5, 4.4, 0.3), "white")
        mesh.box(b * at(sx, 6.5, fz - 0.25), (4, 3.4, 0.3), "glass")
        mesh.box(b * at(sx, 6.5, fz - 0.35), (0.3, 3.4, 0.2), "white")
        for s2 in (-1, 1):
            mesh.box(b * at(sx + s2 * 3.1, 6.5, fz - 0.25), (1, 4.4, 0.3), wall_dark)
        mesh.box(b * at(sx, 4.1, fz - 0.6), (5.4, 0.4, 1), "white")
    for sx in (-1, 1):  # side windows
        mesh.box(b * at(sx * (W / 2 + 0.15), 6.5, 0), (0.3, 4.4, 5), "white")
        mesh.box(b * at(sx * (W / 2 + 0.25), 6.5, 0), (0.3, 3.4, 4), "glass")


def build_plot(i, kit, houses):
    cx, cz, yaw = plot_frame(i)
    f = at(cx, 0, cz, yaw)
    hx, hz = HATCH
    h = PIT / 2

    # the pit: dark walls and floor, a wooden frame round the opening
    pit = f * at(hx, 0, hz)
    for (pos, size, inward) in [
        ((0, -PIT_DEPTH / 2, -h), (PIT, PIT_DEPTH, 0.01), (0, 0, 1)),
        ((0, -PIT_DEPTH / 2, h), (PIT, PIT_DEPTH, 0.01), (0, 0, -1)),
        ((-h, -PIT_DEPTH / 2, 0), (0.01, PIT_DEPTH, PIT), (1, 0, 0)),
        ((h, -PIT_DEPTH / 2, 0), (0.01, PIT_DEPTH, PIT), (-1, 0, 0)),
    ]:
        face = {(0, 0, 1): "+z", (0, 0, -1): "-z", (1, 0, 0): "+x", (-1, 0, 0): "-x"}[inward]
        kit.box(pit * at(*pos), size, "pit_wall", faces={face})
    kit.box(pit * at(0, -PIT_DEPTH, 0), (PIT, 0.01, PIT), "pit", faces={"top"})
    fw = 1.4
    for (pos, size) in [((0, 0.3, -(h + fw / 2)), (PIT + fw * 2, 0.6, fw)), ((0, 0.3, h + fw / 2), (PIT + fw * 2, 0.6, fw)),
                        ((-(h + fw / 2), 0.3, 0), (fw, 0.6, PIT)), ((h + fw / 2, 0.3, 0), (fw, 0.6, PIT))]:
        kit.box(pit * at(*pos), size, "wood_dark")
    for sx in (-1, 1):
        for sz in (-1, 1):
            kit.box(pit * at(sx * (h + fw / 2), 0.65, sz * (h + fw / 2)), (fw + 0.2, 0.15, fw + 0.2), "lamp_head")

    # fence: sides, back, and the front either side of a wide gate
    hw, hd = PLOT_W / 2 - 0.5, PLOT_D / 2 - 0.5
    fence_line(kit, f, -hw, -hd, -hw, hd)
    fence_line(kit, f, hw, hd, hw, -hd)
    fence_line(kit, f, -hw, hd, hw, hd)
    fence_line(kit, f, -hw, -hd, -14, -hd)
    fence_line(kit, f, 14, -hd, hw, -hd)
    for sx in (-14, 14):  # gate posts
        kit.box(f * at(sx, 2.6, -hd), (1.4, 5.2, 1.4), "post")
        kit.blob(f * at(sx, 5.6, -hd), (1.6, 1.2, 1.6), "wood", detail=0)

    # planter boxes round each garden spot (the dirt inside is drawn by the game)
    for (px, pz) in PLANT_SPOTS:
        p = f * at(px, 0, pz)
        o, t, hgt = 7.2, 0.6, 0.9
        for (pos, size) in [((0, hgt / 2, -(o / 2 - t / 2)), (o, hgt, t)), ((0, hgt / 2, o / 2 - t / 2), (o, hgt, t)),
                            ((-(o / 2 - t / 2), hgt / 2, 0), (t, hgt, o - 2 * t)), ((o / 2 - t / 2, hgt / 2, 0), (t, hgt, o - 2 * t))]:
            kit.box(p * at(*pos), size, "dirt_frame", faces={"top", "+x", "-x", "+z", "-z"})

    # stepping stones from the gate to the hatch
    z = -46
    while z < hz - h - 3:
        kit.cylinder(f * at(0, 0, z), 1.6, 0.18, "stone", sides=8)
        z += 4.5

    # mailbox by the sidewalk
    m = f * at(-19, 0, -PLOT_D / 2 - 1.1)
    kit.box(m * at(0, 1.6, 0), (0.45, 3.2, 0.45), "wood_dark")
    kit.box(m * at(0, 3.6, 0), (1.3, 1.1, 2), "mail_blue")
    kit.cylinder(m * at(0, 4.15, -1) * at(0, 0, 0, 0, math.pi / 2, 0), 0.65, 2, "mail_blue", sides=8, top=True, bottom=True)
    kit.box(m * at(0.75, 4.2, 0.3), (0.12, 1.2, 0.35), "flag_red")

    build_house(houses, f, i)


# ---------------------------------------------------------------------------
# Street furniture, trees, the seed stand and the tunnels
# ---------------------------------------------------------------------------
def build_props():
    props = new_mesh("StreetProps")
    glow = new_mesh("Glow_FFE8A6")  # the game turns this one into glowing Neon
    plot_xs = sorted(set(plot_frame(i)[0] for i in range(1, 9)))
    lamp_xs = [-ROAD_X + 5] + [(a + b) / 2 for a, b in zip(plot_xs, plot_xs[1:])] + [ROAD_X - 5]
    for x in lamp_xs:
        for s in (1, -1):
            z = s * (SIDEWALK_OUT - 1.2)
            props.cylinder(at(x, 0.4, z), 0.6, 0.6, "lamp_pole", sides=8)
            props.cylinder(at(x, 0.4, z), 0.35, 12, "lamp_pole", sides=8)
            arm = at(x, 12.2, z - s * 1.6)
            props.box(arm, (0.4, 0.4, 3.6), "lamp_pole")
            props.box(at(x, 12, z - s * 3.2), (1.6, 0.8, 2.2), "lamp_head")
            glow.box(at(x, 11.45, z - s * 3.2), (1.2, 0.3, 1.8), "white")
    # fire hydrants
    for x in (-120, 40):
        for s in (1, -1):
            hz = s * (SIDEWALK_OUT - 1.2)
            hx = x + 6 * s
            props.cylinder(at(hx, 0.4, hz), 0.5, 1.6, "hydrant", sides=8)
            props.blob(at(hx, 2.0, hz), (1.0, 0.8, 1.0), "hydrant", detail=0)
            props.box(at(hx, 1.3, hz), (1.4, 0.35, 0.35), "hydrant")
    # benches on the plazas
    for s in (1, -1):
        for bz in (-24, 24):
            if s < 0 and bz == -24:
                continue  # the seed stand is there
            b = at(s * (ROAD_X + 22), 0.2, bz, math.pi / 2 if s > 0 else -math.pi / 2)
            props.box(b * at(0, 1.4, 0), (5, 0.35, 1.6), "bench")
            props.box(b * at(0, 2.5, 0.7), (5, 1.2, 0.3), "bench")
            for lx in (-2, 2):
                props.box(b * at(lx, 0.7, 0), (0.3, 1.4, 1.4), "bench_leg")

    trees = new_mesh("Trees")
    spots = []
    gaps = [(a + PLOT_W / 2 + b - PLOT_W / 2) / 2 for a, b in zip(plot_xs, plot_xs[1:])]
    for gx in gaps:
        for s in (1, -1):
            for tz in (35, 70, 105):
                spots.append((gx, s * tz, 1.0))
    for s in (1, -1):
        for tz in (55, 85, 115):
            spots.append((s * (MAP_X - 25), tz, 1.2))
            spots.append((s * (MAP_X - 25), -tz, 1.2))
            spots.append((s * (STREET_X + 15), tz + 8, 1.0))
            spots.append((s * (STREET_X + 15), -tz - 8, 1.0))
    for (x, z, k) in spots:
        trees.cylinder(at(x, 0, z), 0.9 * k, 6 * k, "trunk", sides=7)
        trees.blob(at(x, 8 * k, z), (8 * k, 6.5 * k, 8 * k), "leaf", detail=1)
        trees.blob(at(x + 1.5 * k, 10.5 * k, z - 1 * k), (5.5 * k, 4.5 * k, 5.5 * k), "leaf_light", detail=1)

    hedges = new_mesh("Hedges")
    for s in (1, -1):
        x = -MAP_X + 8
        while x < MAP_X - 6:
            hedges.blob(at(x, 1.6, s * (MAP_Z - 3)), (9, 4, 4.5), "hedge", detail=1)
            x += 8.5


def build_seed_stand():
    stand = new_mesh("SeedStand")
    letters = new_mesh("SeedStandSign")
    base = at(-(MAP_X - 16), 0.2, STAND_Z, -math.pi / 2)  # faces +X: down the street
    stand.box(base * at(0, 1.8, 0), (16, 3.6, 4), "wood", keys={"top": "wood_dark"})
    stand.box(base * at(0, 3.7, 0), (16.6, 0.3, 4.6), "wood_dark")
    for sx in (-7.6, 7.6):
        for sz in (-1.6, 3.2):
            stand.box(base * at(sx, 4.5, sz), (0.6, 9, 0.6), "post")
    stand.box(base * at(0, 4.5, 3.4), (16, 9, 0.4), "wood_dark")
    # striped awning
    stripes = 8
    for k in range(stripes):
        sx = -8 + (k + 0.5) * 16 / stripes
        stand.box(base * at(sx, 9.6, 1, 0, -0.35, 0), (16 / stripes, 0.4, 6.4), "awning_red" if k % 2 == 0 else "awning_white")
    for k in range(stripes):
        sx = -8 + (k + 0.5) * 16 / stripes
        stand.box(base * at(sx, 8.1, -2.1), (16 / stripes, 1.2, 0.3), "awning_red" if k % 2 == 0 else "awning_white")
    # crates of produce on the counter
    produce = ["tomato", "chili", "berry", "shroom", "pumpkin", "melon"]
    for k, key in enumerate(produce):
        sx = -6.5 + k * 2.6
        stand.box(base * at(sx, 4.4, -0.5), (2.3, 1.1, 2.3), "crate")
        for (ox, oz) in [(-0.5, -0.4), (0.5, -0.4), (0, 0.4)]:
            stand.blob(base * at(sx + ox, 5.25, -0.5 + oz), (0.9, 0.8, 0.9), key, detail=1)
    # sign on top
    stand.box(base * at(0, 12.6, 1.2), (12, 3.6, 0.6), "sign_purple")
    stand.box(base * at(0, 12.6, 1.4), (12.8, 4.4, 0.4), "sign_purple_dark")
    letters.text(base * at(0, 11.6, 0.7), "SEEDS", 2.8, 0.5, "letter_yellow")
    # a giant tomato on the roof
    stand.blob(base * at(0, 16.6, 1.2), (4, 3.6, 4), "tomato", detail=2)
    stand.blob(base * at(0, 18.5, 1.2), (2.2, 0.6, 2.2), "leafy", detail=1)


def tunnel_frame(s):
    """The tunnel in the east (s = 1) or west (s = -1) wall. Local -Z faces up
    the street, z = 0 is the wall's face and the tunnel runs off into +Z."""
    return at(s * MAP_X, 0, 0, s * math.pi / 2)


def arch_points(r, n=TUNNEL_SEGMENTS):
    """(x, y) round the top of a tunnel of radius r, from its right side to its left."""
    return [(r * math.cos(math.pi * k / n), TUNNEL_SPRING + r * math.sin(math.pi * k / n)) for k in range(n + 1)]


def clean(points):
    """Drops repeated corners (so a squashed quad becomes a triangle)."""
    out = []
    for p in points:
        if not out or abs(p[0] - out[-1][0]) > 1e-6 or abs(p[1] - out[-1][1]) > 1e-6:
            out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) < 1e-6 and abs(out[0][1] - out[-1][1]) < 1e-6:
        out.pop()
    return out


def build_tunnel(s):
    """A tunnel into the end wall, where the seed truck comes and goes. The east
    one wears the FEED THE THING sign (with the eyes peeking out of a hatch),
    the west one the SEED EXPRESS sign."""
    f = tunnel_frame(s)
    out = lambda n: apply(f.rot, n)
    P = lambda x, y, z: f.point((x, y, z))
    name = "East" if s > 0 else "West"
    tunnel = new_mesh("Tunnel" + name)
    letters = new_mesh("TunnelSign" + name)
    R = TUNNEL_R

    # pillars either side of the opening
    for side in (1, -1):
        p = f * at(side * (R + 2), 0, -1.5)
        tunnel.box(p * at(0, TUNNEL_SPRING / 2, 0), (4, TUNNEL_SPRING, 3), "pillar", keys={"top": "pillar_dark"})
        tunnel.box(p * at(0, 0.6, 0), (5, 1.2, 3.6), "pillar_dark")
    # the arch: chunky blocks in two colours
    inner, outer = arch_points(R), arch_points(R + 3)
    for k in range(TUNNEL_SEGMENTS):
        key = "pillar" if k % 2 == 0 else "pillar_dark"
        (xi0, yi0), (xi1, yi1) = inner[k], inner[k + 1]
        (xo0, yo0), (xo1, yo1) = outer[k], outer[k + 1]
        mid = math.pi * (k + 0.5) / TUNNEL_SEGMENTS
        tunnel.poly([P(xi0, yi0, -2), P(xi1, yi1, -2), P(xo1, yo1, -2), P(xo0, yo0, -2)], key, out((0, 0, -1)))
        tunnel.poly([P(xo0, yo0, -2), P(xo1, yo1, -2), P(xo1, yo1, 0), P(xo0, yo0, 0)], key, out((math.cos(mid), math.sin(mid), 0)))
        tunnel.poly([P(xi0, yi0, -2), P(xi1, yi1, -2), P(xi1, yi1, 0), P(xi0, yi0, 0)], "pillar_dark", out((-math.cos(mid), -math.sin(mid), 0)))

    # the inside: walls, roof and road, darker and darker the further in
    section = [(R, 0)] + inner + [(-R, 0)]
    for b, (za, zb) in enumerate(zip(TUNNEL_BANDS, TUNNEL_BANDS[1:])):
        for (xa, ya), (xb, yb) in zip(section, section[1:]):
            inward = (-(xa + xb) / 2, TUNNEL_SPRING - (ya + yb) / 2, 0)
            tunnel.poly([P(xa, ya, za), P(xb, yb, za), P(xb, yb, zb), P(xa, ya, zb)], f"tunnel_wall{b}", out(inward))
        tunnel.poly([P(R, 0.2, za), P(-R, 0.2, za), P(-R, 0.2, zb), P(R, 0.2, zb)], f"tunnel_floor{b}", out((0, 1, 0)))
    # the end, as triangles (no many-sided faces, in case Roblox's importer trips on them)
    for (xa, ya), (xb, yb) in zip(section[1:], section[2:]):
        tunnel.poly([P(*section[0], TUNNEL_DEPTH), P(xa, ya, TUNNEL_DEPTH), P(xb, yb, TUNNEL_DEPTH)], "tunnel_end", out((0, 0, -1)))

    # the sign over it
    width = 45
    sign_y = TUNNEL_SPRING + R + 3 + 3
    tunnel.box(f * at(0, sign_y, -1.6), (width + 2, 7, 1.2), "sign_purple")
    tunnel.box(f * at(0, sign_y, -0.9), (width + 3, 8, 1.4), "sign_purple_dark")
    badge = f * at(-(width / 2) + 4.5, sign_y, -2.25)
    if s > 0:
        letters.text(f * at(3, sign_y - 1.6, -2.3), "FEED THE THING", 3.8, 0.6, "letter_lime")
        # a little hatch with two glowing eyes peeking out
        eyes = new_mesh("Glow_D7FF5A")
        tunnel.box(badge, (5, 5, 0.2), "pit")
        tunnel.box(badge * at(0, 2.7, 0), (5.6, 0.5, 0.4), "wood")
        tunnel.box(badge * at(0, -2.7, 0), (5.6, 0.5, 0.4), "wood")
        for sx in (-1, 1):
            tunnel.box(badge * at(sx * 2.7, 0, 0), (0.5, 5.6, 0.4), "wood")
            eyes.blob(badge * at(sx * 1.1, 0.2, -0.2), (1.2, 1.5, 0.6), "white", detail=1)
    else:
        letters.text(f * at(3, sign_y - 1.4, -2.3), "SEED EXPRESS", 3.4, 0.6, "letter_yellow")
        # a big tomato for a logo
        tunnel.blob(badge * at(0, -0.3, -0.3), (4.4, 4.0, 1.6), "tomato", detail=2)
        tunnel.blob(badge * at(0, 1.8, -0.5), (2.4, 0.7, 1.0), "leafy", detail=1)


def build_markers():
    marks = {"MapOrigin": (0, -30, 0), "MapMarkX": (100, -30, 0), "MapMarkZ": (0, -30, 100)}
    for name, (x, y, z) in marks.items():
        m = new_mesh(name)
        m.box(at(x, y, z), (1, 1, 1), "white")


# ---------------------------------------------------------------------------
# Turn the collected meshes into Blender objects, materials, export, render
# ---------------------------------------------------------------------------
def make_material(name, image_path):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.75
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    if image_path:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image_path, check_existing=True)
        tex.interpolation = "Closest" if name == "palette" else "Linear"
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (1, 0.95, 0.7, 1)
        bsdf.inputs["Emission Color"].default_value = (1, 0.95, 0.7, 1)
        bsdf.inputs["Emission Strength"].default_value = 3
    return mat


def to_blender(p):
    return (p[0], -p[2], p[1])


def build_objects(textures):
    materials = {}
    for m in MESHES:
        if not m.faces:
            continue
        mesh = bpy.data.meshes.new(m.name)
        mesh.from_pydata([to_blender(v) for v in m.verts], [], m.faces)
        uv = mesh.uv_layers.new(name="UVMap")
        k = 0
        for face_uvs in m.uvs:
            for u, v in face_uvs:
                uv.data[k].uv = (u, v)
                k += 1
        mesh.polygons.foreach_set("use_smooth", m.smooth_flags)
        mesh.validate()
        obj = bpy.data.objects.new(m.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        marker = m.name.startswith("Map") or m.name.endswith("_Origin") or m.name.endswith("_MarkX")
        if "Glow_" in m.name or marker:
            key = m.name  # no texture: the game colours these itself
            if key not in materials:
                materials[key] = make_material(key, None)
        else:
            key = m.texture
            if key not in materials:
                materials[key] = make_material(key, textures[key])
        mesh.materials.append(materials[key])
        if marker:
            obj.hide_render = True
        print(f"  {m.name:16s} {m.triangles():6d} triangles")
        assert m.triangles() < 20000, m.name + " has too many triangles for one Roblox MeshPart"


def setup_scene():
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 0.01  # 1 unit = 1 cm in the FBX = 1 stud in Roblox
    sc.unit_settings.length_unit = "CENTIMETERS"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.42, 0.68, 1.0, 1)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(35))
    sc.collection.objects.link(sun)
    sc.view_settings.view_transform = "Standard"
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    try:
        sc.eevee.taa_render_samples = 16
    except AttributeError:
        pass


def render_preview(name, eye, target, lens=24):
    """eye/target in Roblox coordinates."""
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.scene.collection.objects.link(cam)
    from mathutils import Vector
    e, t = Vector(to_blender(eye)), Vector(to_blender(target))
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = 88
    sc.render.filepath = os.path.join(PREVIEW_DIR, name + ".jpg")
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene()
    textures = {
        "palette": save_palette(),
        "studs_grass": stud_texture("studs_grass", (110, 205, 45)),
        "studs_lawn": stud_texture("studs_lawn", (135, 225, 55)),
        "studs_sidewalk": stud_texture("studs_sidewalk", (205, 205, 212)),
        "studs_plaza": stud_texture("studs_plaza", (200, 188, 165)),
        "studs_wall": stud_texture("studs_wall", (225, 160, 95), studs=8, checker=((225, 160, 95), (200, 135, 75), 2), seam=False),
        "studs_walltop": stud_texture("studs_walltop", (90, 210, 40)),
    }
    build_ground()
    build_street()
    build_walls()
    for i in range(1, 9):
        kit = new_mesh(f"Plot{i}")
        house = new_mesh(f"House{i}")
        build_plot(i, kit, house)
    build_props()
    build_seed_stand()
    for s in (1, -1):
        build_tunnel(s)
    build_markers()
    print("Objects:")
    build_objects(textures)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "Map.blend"))
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(EXPORT_DIR, "FeedTheThing_Map.fbx"),
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
    )
    print("Exported", os.path.join(EXPORT_DIR, "FeedTheThing_Map.fbx"))

    if RENDER:
        render_preview("overview", (-250, 230, 250), (0, 0, 0), lens=22)
        render_preview("street", (-150, 14, 0), (100, 4, 0), lens=24)
        render_preview("plot", (-40, 30, -35), (-40, 3, 45), lens=22)
        render_preview("stand", (-150, 12, 0), (-205, 8, -10), lens=26)
        render_preview("tunnel", (140, 12, 6), (215, 12, 0), lens=26)
        render_preview("tunnel_inside", (196, 5, 6), (240, 5, 6), lens=24)


if __name__ == "__main__":
    main()
