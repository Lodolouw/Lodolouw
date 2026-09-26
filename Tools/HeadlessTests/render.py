"""A tiny software renderer for Roblox-style blocks (flat colours, z-buffer,
edge lines), used to preview what the game code builds.

    python3 render.py parts.json out.png [--cam x,y,z] [--look x,y,z] [--fov deg]
"""
import json, math, sys, argparse
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument('parts')
ap.add_argument('out')
ap.add_argument('--cam', default='-30,26,-64')
ap.add_argument('--look', default='0,12,0')
ap.add_argument('--fov', type=float, default=40)
ap.add_argument('--size', default='1200,900')
ap.add_argument('--ground', default='214,152,102')
ap.add_argument('--ground-size', type=float, default=400)
ap.add_argument('--sky', default='120,170,255')
ap.add_argument('--player', default='')  # x,z of a player-sized figure for scale
ap.add_argument('--title', default='')
args = ap.parse_args()

W, H = [int(v) for v in args.size.split(',')]
SS = 2  # supersampling
w, h = W * SS, H * SS
eye = np.array([float(v) for v in args.cam.split(',')])
look = np.array([float(v) for v in args.look.split(',')])
fwd = look - eye
fwd /= np.linalg.norm(fwd)
right = np.cross(fwd, [0, 1, 0])
right /= np.linalg.norm(right)
up = np.cross(right, fwd)
f = (h / 2) / math.tan(math.radians(args.fov) / 2)
LIGHT = np.array([-0.45, 0.8, -0.35])
LIGHT /= np.linalg.norm(LIGHT)

color = np.zeros((h, w, 3), dtype=np.float32)
sky = np.array([float(v) for v in args.sky.split(',')])
for y in range(h):
    k = y / h
    color[y, :, :] = sky * (1 - 0.35 * k) + np.array([230, 240, 255]) * 0.35 * k
depth = np.full((h, w), -np.inf, dtype=np.float32)  # 1/z, bigger = closer
ids = np.full((h, w), -1, dtype=np.int32)


def project(p):
    d = p - eye
    z = d @ fwd
    x = d @ right
    yv = d @ up
    return np.array([w / 2 + f * x / z, h / 2 - f * yv / z]), z


def tri(p0, p1, p2, col, fid):
    (a, za), (b, zb), (c, zc) = project(p0), project(p1), project(p2)
    if min(za, zb, zc) <= 0.1:
        return
    xmin = int(max(0, math.floor(min(a[0], b[0], c[0]))))
    xmax = int(min(w - 1, math.ceil(max(a[0], b[0], c[0]))))
    ymin = int(max(0, math.floor(min(a[1], b[1], c[1]))))
    ymax = int(min(h - 1, math.ceil(max(a[1], b[1], c[1]))))
    if xmin > xmax or ymin > ymax:
        return
    xs, ys = np.meshgrid(np.arange(xmin, xmax + 1) + 0.5, np.arange(ymin, ymax + 1) + 0.5)
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-9:
        return
    l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
    l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
    l2 = 1 - l0 - l1
    inside = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
    iz = l0 / za + l1 / zb + l2 / zc
    sub = depth[ymin:ymax + 1, xmin:xmax + 1]
    m = inside & (iz > sub)
    sub[m] = iz[m]
    color[ymin:ymax + 1, xmin:xmax + 1][m] = col
    ids[ymin:ymax + 1, xmin:xmax + 1][m] = fid


fid = [0]


def box(center, R, size, col, alpha=1.0):
    hx, hy, hz = np.array(size) / 2
    axes = [R[:, 0], R[:, 1], R[:, 2]]
    faces = []
    for ax, hs, oa, ob, ha, hb in ((0, hx, 1, 2, hy, hz), (1, hy, 0, 2, hx, hz), (2, hz, 0, 1, hx, hy)):
        for sgn in (1, -1):
            n = axes[ax] * sgn
            cc = center + n * hs
            A, B = axes[oa] * ha, axes[ob] * hb
            faces.append((n, [cc - A - B, cc + A - B, cc + A + B, cc - A + B]))
    for n, q in faces:
        if (q[0] - eye) @ n >= 0:
            continue  # facing away
        lit = 0.62 + 0.38 * max(0.0, float(n @ LIGHT))
        c = np.clip(np.array(col, dtype=np.float32) * lit, 0, 255)
        fid[0] += 1
        tri(q[0], q[1], q[2], c, fid[0])
        tri(q[0], q[2], q[3], c, fid[0])


parts = json.load(open(args.parts))
# the ground
g = args.ground_size
gc = [float(v) for v in args.ground.split(',')]
box(np.array([0, -0.5, 0]), np.eye(3), (g, 1, g), gc)
for p in parts:
    if p.get('t', 0) >= 0.99:
        continue
    cf = p['cf']
    center = np.array(cf[0:3])
    R = np.array(cf[3:12]).reshape(3, 3)
    box(center, R, p['size'], p['color'])

if args.player:
    px, pz = [float(v) for v in args.player.split(',')]
    I = np.eye(3)
    skin = (255, 204, 153)
    for (cx, cy, cz), s, col in (
        ((0, 1, 0), (0.95, 2, 1), (40, 90, 200)), ((0, 1, 0), (0.95, 2, 1), (40, 90, 200)),
        ((-0.5, 1, 0), (0.95, 2, 1), (40, 90, 200)), ((0.5, 1, 0), (0.95, 2, 1), (40, 90, 200)),
        ((0, 3, 0), (2, 2, 1), (230, 60, 60)), ((-1.5, 3, 0), (0.95, 2, 1), skin), ((1.5, 3, 0), (0.95, 2, 1), skin),
        ((0, 4.6, 0), (1.2, 1.2, 1.2), skin),
    ):
        box(np.array([px + cx, cy, pz + cz]), I, s, col)

# edge lines between faces (a crisp, blocky look)
edge = np.zeros((h, w), dtype=bool)
edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
edge &= (ids >= 0)
color[edge] *= 0.55
img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
if args.title:
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 34], fill=(24, 20, 37))
    d.text((12, 10), args.title, fill=(255, 255, 255))
img.save(args.out)
print('saved', args.out)
