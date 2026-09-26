"""Renders a snapshot from the Colosseum test (every part in the arena at one
moment) inside a simple model of the arena, the way the game builds it:
blocks and cylinders, see-through and glowing parts, flat 8-bit colours.

    python3 render2.py snaps.txt NAME out.png [--cam-back 30] [--cam-up 16] [--side 0]
"""
import json, math, sys, argparse
import numpy as np
from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument('snaps')
ap.add_argument('name')
ap.add_argument('out')
ap.add_argument('--cam-back', type=float, default=34)
ap.add_argument('--cam-up', type=float, default=18)
ap.add_argument('--side', type=float, default=0)
ap.add_argument('--fov', type=float, default=55)
ap.add_argument('--look-up', type=float, default=7)
ap.add_argument('--toward', default='king')  # what the camera looks at: king | mid
ap.add_argument('--size', default='1280,720')
ap.add_argument('--caption', default='')
args = ap.parse_args()

snap = None
for line in open(args.snaps):
    if line.startswith('SNAP ' + args.name + ' '):
        head, rest = line.split(' [', 1)
        _, name, x, y, z = head.split()
        snap = (np.array([float(x), float(y), float(z)]), json.loads('[' + rest.strip()))
        break
if snap is None:
    sys.exit('no snapshot ' + args.name)
player, parts = snap
CENTER = np.array([-2600.0, 0, 0])

W, H = [int(v) for v in args.size.split(',')]
SS = 2
w, h = W * SS, H * SS
king = [p for p in parts if p['name'] == 'Torso' and p['size'][0] > 8]
kpos = np.array(king[0]['cf'][0:3]) if king else CENTER
d = player - kpos
d[1] = 0
d = d / (np.linalg.norm(d) + 1e-9)
side = np.cross([0, 1, 0], d)
eye = player + d * args.cam_back + np.array([0, args.cam_up, 0]) + side * args.side
look = (kpos if args.toward == 'king' else (player + kpos) / 2) + np.array([0, args.look_up, 0])
fwd = look - eye
fwd /= np.linalg.norm(fwd)
right = np.cross(fwd, [0, 1, 0])
right /= np.linalg.norm(right)
up = np.cross(right, fwd)
f = (h / 2) / math.tan(math.radians(args.fov) / 2)
LIGHT = np.array([-0.4, 0.85, -0.3])
LIGHT /= np.linalg.norm(LIGHT)

color = np.zeros((h, w, 3), dtype=np.float32)
top, bottom = np.array([110, 165, 255]), np.array([200, 225, 255])
for y in range(h):
    k = min(1, y / (h * 0.6))
    color[y, :, :] = top * (1 - k) + bottom * k
depth = np.full((h, w), -np.inf, dtype=np.float32)
ids = np.full((h, w), -1, dtype=np.int32)
transparent = []


def project(p):
    q = p - eye
    z = q @ fwd
    return np.array([w / 2 + f * (q @ right) / z, h / 2 - f * (q @ up) / z]), z


def raster(p0, p1, p2, col, fid, alpha=1.0):
    (a, za), (b, zb), (c, zc) = project(p0), project(p1), project(p2)
    if min(za, zb, zc) <= 0.2:
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
    region = color[ymin:ymax + 1, xmin:xmax + 1]
    if alpha >= 0.999:
        sub[m] = iz[m]
        region[m] = col
        ids[ymin:ymax + 1, xmin:xmax + 1][m] = fid
    else:
        region[m] = region[m] * (1 - alpha) + np.array(col) * alpha


fidc = [0]


def shade(col, n, neon):
    if neon:
        return np.clip(np.array(col, dtype=np.float32) * 1.12 + 12, 0, 255)
    return np.clip(np.array(col, dtype=np.float32) * (0.62 + 0.38 * max(0.0, float(n @ LIGHT))), 0, 255)


def emit_faces(faces, col, alpha, neon):
    for n, q in faces:
        if (q[0] - eye) @ n >= 0:
            continue
        c = shade(col, n, neon)
        fidc[0] += 1
        if alpha >= 0.999:
            for i in range(1, len(q) - 1):
                raster(q[0], q[i], q[i + 1], c, fidc[0])
        else:
            dist = float(np.linalg.norm(np.mean(q, axis=0) - eye))
            transparent.append((dist, q, c, alpha))


def box_faces(center, R, size):
    hx, hy, hz = np.array(size) / 2
    axes = [R[:, 0], R[:, 1], R[:, 2]]
    out = []
    for ax, hs, oa, ob, ha, hb in ((0, hx, 1, 2, hy, hz), (1, hy, 0, 2, hx, hz), (2, hz, 0, 1, hx, hy)):
        for sgn in (1, -1):
            n = axes[ax] * sgn
            cc = center + n * hs
            A, B = axes[oa] * ha, axes[ob] * hb
            out.append((n, [cc - A - B, cc + A - B, cc + A + B, cc - A + B]))
    return out


def cyl_faces(center, R, size, sides=28):
    # a Roblox cylinder: its axis is the part's X, diameter the smaller of Y and Z
    L = size[0] / 2
    r = min(size[1], size[2]) / 2
    ax, u, v = R[:, 0], R[:, 1], R[:, 2]
    ring = [u * math.cos(2 * math.pi * i / sides) * r + v * math.sin(2 * math.pi * i / sides) * r for i in range(sides)]
    out = [(ax, [center + ax * L + p for p in ring]), (-ax, [center - ax * L + p for p in reversed(ring)])]
    for i in range(sides):
        p0, p1 = ring[i], ring[(i + 1) % sides]
        n = (p0 + p1)
        n = n / (np.linalg.norm(n) + 1e-9)
        out.append((n, [center - ax * L + p0, center - ax * L + p1, center + ax * L + p1, center + ax * L + p0]))
    return out


def part(center, R, size, col, t=0.0, shape='Block', neon=False):
    faces = cyl_faces(center, R, size) if shape == 'Cylinder' else box_faces(center, R, size)
    emit_faces(faces, col, 1 - t, neon)


I = np.eye(3)
# ---- the arena, roughly as LobbyBuilder makes it (s = 2.6)
S = 2.6
# the sand, in tiles (so nothing sits behind the camera)
for gx in range(-12, 12):
    for gz in range(-12, 12):
        cx, cz = CENTER[0] + gx * 10 + 5, CENTER[2] + gz * 10 + 5
        if math.hypot(cx - CENTER[0], cz - CENTER[2]) < 112:
            part(np.array([cx, -0.5, cz]), I, (10, 1, 10), (216, 156, 106))
ring_R = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], dtype=float)  # (x axis up: a flat disc)
part(CENTER + np.array([0, 0.26, 0]), ring_R, (0.52, 31.2, 31.2), (190, 128, 88), shape='Cylinder')
# the stands (three tiers with a crowd) and the wall
rng = np.random.default_rng(3)
N = 48
for i in range(N):
    a = (i + 0.5) / N * 2 * math.pi
    dirv = np.array([math.sin(a), 0, math.cos(a)])
    Rm = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    for k in range(1, 4):
        r = (42 - 1.6 - k * 2.4) * S
        hgt = (1 + (4 - k) * 2.2) * S
        part(CENTER + dirv * r + np.array([0, hgt / 2 - 0.5, 0]), Rm, (2 * math.pi * r / N + 0.5, hgt, 2.4 * S),
             (184, 111, 80) if k % 2 == 0 else (200, 140, 96))
        if rng.random() < 0.7:
            colr = [(228, 59, 68), (254, 174, 52), (99, 199, 77), (0, 153, 219), (255, 255, 255), (181, 80, 136)][rng.integers(0, 6)]
            part(CENTER + dirv * r + np.array([0, hgt + 1.3, 0]), Rm, (2.2, 3, 1.8), colr)
            part(CENTER + dirv * r + np.array([0, hgt + 3.6, 0]), Rm, (1.8, 1.8, 1.8), (255, 214, 170))
    part(CENTER + dirv * 42 * S + np.array([0, 7 * S, 0]), Rm, (2 * math.pi * 42 * S / N + 1, 12 * S, 3.2 * S), (228, 166, 114))

# ---- the snapshot's parts
for p in parts:
    cf = p['cf']
    part(np.array(cf[0:3]), np.array(cf[3:12]).reshape(3, 3), p['size'], p['color'], t=p['t'], shape=p['shape'], neon=p['mat'] == 'Neon')

# ---- the player (a blocky figure)
px, py, pz = player
face = kpos - player
yaw = math.atan2(face[0], face[2])
Rp = np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]])
skin = (255, 204, 153)
for (cx, cy, cz), sz, col in (((-0.5, 1, 0), (0.95, 2, 1), (40, 90, 200)), ((0.5, 1, 0), (0.95, 2, 1), (40, 90, 200)),
                               ((0, 3, 0), (2, 2, 1), (99, 199, 77)), ((-1.5, 3, 0), (0.95, 2, 1), skin), ((1.5, 3, 0), (0.95, 2, 1), skin),
                               ((0, 4.6, 0), (1.2, 1.2, 1.2), skin)):
    part(np.array([px, py, pz]) + Rp @ np.array([cx, cy, cz]), Rp, sz, col)

# see-through parts last, far to near
transparent.sort(key=lambda x: -x[0])
for _, q, c, alpha in transparent:
    for i in range(1, len(q) - 1):
        raster(q[0], q[i], q[i + 1], c, -2, alpha)

edge = np.zeros((h, w), dtype=bool)
edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
edge &= ids >= 0
color[edge] *= 0.6
img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
if args.caption:
    dr = ImageDraw.Draw(img)
    dr.rectangle([0, H - 40, W, H], fill=(24, 20, 37))
    dr.text((14, H - 28), args.caption, fill=(255, 255, 255))
img.save(args.out)
print('saved', args.out)
