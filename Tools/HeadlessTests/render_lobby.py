"""Draws the lobby from any camera, from a dump made by lobby_dump.luau (every
part the real LobbyBuilder builds, plus the detail RetroWorld adds on your
screen, in its palette colours). Blocks, cylinders, balls and wedges, lit
by one sun, with thin dark edges like the game's 8-bit look.

    luau lobby_dump.luau > lobby.jsonl
    python3 render_lobby.py lobby.jsonl out.png --eye -38,16,6 --look -30,4,-50
      [--fov 70] [--size 1280,720] [--range 260] [--mark x,y,z,...]
"""
import json, math, argparse
import numpy as np
from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument('dump')
ap.add_argument('out')
ap.add_argument('--eye', default='-38,16,6')
ap.add_argument('--look', default='-30,4,-50')
ap.add_argument('--fov', type=float, default=70)
ap.add_argument('--size', default='1280,720')
ap.add_argument('--range', type=float, default=260)
ap.add_argument('--skip', default='')  # part names to leave out (comma list)
ap.add_argument('--mark', default='')  # points to circle in red: x,y,z;x,y,z
ap.add_argument('--caption', default='')
args = ap.parse_args()

parts = [json.loads(l) for l in open(args.dump) if l.startswith('{')]
skip = set(s for s in args.skip.split(',') if s)
W, H = [int(v) for v in args.size.split(',')]
SS = 2
w, h = W * SS, H * SS
eye = np.array([float(v) for v in args.eye.split(',')])
look = np.array([float(v) for v in args.look.split(',')])
fwd = look - eye
fwd /= np.linalg.norm(fwd)
right = np.cross(fwd, [0, 1, 0])
right /= np.linalg.norm(right)
up = np.cross(right, fwd)
f = (h / 2) / math.tan(math.radians(args.fov) / 2)
LIGHT = np.array([-0.45, 0.8, 0.35])
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
    return np.array([w / 2 + f * (q @ right) / max(z, 1e-6), h / 2 - f * (q @ up) / max(z, 1e-6)]), z


def raster(p0, p1, p2, col, fid, alpha=1.0):
    (a, za), (b, zb), (c, zc) = project(p0), project(p1), project(p2)
    if min(za, zb, zc) <= NEAR * 0.99:
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
        return np.clip(np.array(col, dtype=np.float32) * 1.1 + 14, 0, 255)
    return np.clip(np.array(col, dtype=np.float32) * (0.6 + 0.4 * max(0.0, float(n @ LIGHT))), 0, 255)


NEAR = 0.5


def clip(q):
    """The polygon cut off where it goes behind the camera (so a huge face,
    like the island's grass, still draws when part of it is behind you)."""
    out = []
    n = len(q)
    for i in range(n):
        a, b = q[i], q[(i + 1) % n]
        za, zb = (a - eye) @ fwd, (b - eye) @ fwd
        if za >= NEAR:
            out.append(a)
        if (za >= NEAR) != (zb >= NEAR):
            t = (NEAR - za) / (zb - za)
            out.append(a + (b - a) * t)
    return out


def emit(faces, col, alpha, neon):
    for n, q in faces:
        if (q[0] - eye) @ n >= 0:
            continue
        q = clip(q)
        if len(q) < 3:
            continue
        c = shade(col, n, neon)
        fidc[0] += 1
        if alpha >= 0.999:
            for i in range(1, len(q) - 1):
                raster(q[0], q[i], q[i + 1], c, fidc[0])
        else:
            transparent.append((float(np.linalg.norm(np.mean(q, axis=0) - eye)), q, c, alpha))


def box_faces(c, R, s):
    hx, hy, hz = np.array(s) / 2
    axes = [R[:, 0], R[:, 1], R[:, 2]]
    out = []
    for ax, hs, oa, ob, ha, hb in ((0, hx, 1, 2, hy, hz), (1, hy, 0, 2, hx, hz), (2, hz, 0, 1, hx, hy)):
        for sgn in (1, -1):
            n = axes[ax] * sgn
            cc = c + n * hs
            A, B = axes[oa] * ha, axes[ob] * hb
            out.append((n, [cc - A - B, cc + A - B, cc + A + B, cc - A + B]))
    return out


def cyl_faces(c, R, s, sides=20):
    L = s[0] / 2
    r = min(s[1], s[2]) / 2
    ax, u, v = R[:, 0], R[:, 1], R[:, 2]
    ring = [u * math.cos(2 * math.pi * i / sides) * r + v * math.sin(2 * math.pi * i / sides) * r for i in range(sides)]
    out = [(ax, [c + ax * L + p for p in ring]), (-ax, [c - ax * L + p for p in reversed(ring)])]
    for i in range(sides):
        p0, p1 = ring[i], ring[(i + 1) % sides]
        n = (p0 + p1)
        n = n / (np.linalg.norm(n) + 1e-9)
        out.append((n, [c - ax * L + p0, c - ax * L + p1, c + ax * L + p1, c + ax * L + p0]))
    return out


def ball_faces(c, R, s, seg=10, rings=6):
    r = min(s) / 2
    out = []
    for i in range(rings):
        t0, t1 = math.pi * i / rings - math.pi / 2, math.pi * (i + 1) / rings - math.pi / 2
        for j in range(seg):
            p0, p1 = 2 * math.pi * j / seg, 2 * math.pi * (j + 1) / seg

            def P(t, p):
                return c + r * np.array([math.cos(t) * math.cos(p), math.sin(t), math.cos(t) * math.sin(p)])
            q = [P(t0, p0), P(t0, p1), P(t1, p1), P(t1, p0)]
            n = np.mean(q, axis=0) - c
            n = n / (np.linalg.norm(n) + 1e-9)
            out.append((n, q))
    return out


def wedge_faces(c, R, s):
    # Roblox's WedgePart: full bottom, a tall back (+Z), the slope facing the front (-Z)
    hx, hy, hz = np.array(s) / 2
    X, Y, Z = R[:, 0], R[:, 1], R[:, 2]

    def P(x, y, z):
        return c + X * x + Y * y + Z * z
    b0, b1, b2, b3 = P(-hx, -hy, -hz), P(hx, -hy, -hz), P(hx, -hy, hz), P(-hx, -hy, hz)
    t2, t3 = P(hx, hy, hz), P(-hx, hy, hz)
    slope_n = (Y * (2 * hz) + Z * (-2 * hy))
    slope_n = slope_n / (np.linalg.norm(slope_n) + 1e-9)
    return [(-Y, [b0, b1, b2, b3]), (Z, [b3, b2, t2, t3]), (slope_n, [b0, t3, t2, b1]),
            (X, [b1, t2, b2]), (-X, [b0, b3, t3])]


drawn = 0
for p in parts:
    if p['n'] in skip or p['t'] >= 0.98:
        continue
    cf = p['cf']
    c = np.array(cf[0:3])
    s = p['s']
    rad = 0.5 * math.sqrt(s[0] ** 2 + s[1] ** 2 + s[2] ** 2)
    q = c - eye
    z = q @ fwd
    dist = np.linalg.norm(q)
    if dist - rad > args.range or z < -rad:
        continue
    # (outside the view, sideways?)
    if z > 0:
        sx = abs(q @ right) - rad
        sy = abs(q @ up) - rad
        lim = z * math.tan(math.radians(args.fov) / 2) * (w / h) * 1.05
        if sx > lim or sy > z * math.tan(math.radians(args.fov) / 2) * 1.05:
            continue
    R = np.array(cf[3:12]).reshape(3, 3)
    neon = p['m'] == 'Neon'
    if p['c'] == 'WedgePart':
        faces = wedge_faces(c, R, s)
    elif p['sh'] == 'Cylinder':
        faces = cyl_faces(c, R, s)
    elif p['sh'] == 'Ball':
        faces = ball_faces(c, R, s)
    else:
        faces = box_faces(c, R, s)
    emit(faces, p['col'], 1 - p['t'], neon)
    drawn += 1

transparent.sort(key=lambda x: -x[0])
for _, q, c, alpha in transparent:
    for i in range(1, len(q) - 1):
        raster(q[0], q[i], q[i + 1], c, -2, alpha)
edge = np.zeros((h, w), dtype=bool)
edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
edge &= ids >= 0
color[edge] *= 0.62
img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
d = ImageDraw.Draw(img)
for m in [x for x in args.mark.split(';') if x]:
    pt = np.array([float(v) for v in m.split(',')])
    (mx, my), mz = project(pt)
    if mz > 0:
        mx, my = mx / SS, my / SS
        d.ellipse([mx - 18, my - 18, mx + 18, my + 18], outline=(255, 0, 0), width=3)
if args.caption:
    d.rectangle([0, H - 40, W, H], fill=(24, 20, 37))
    d.text((14, H - 28), args.caption, fill=(255, 255, 255))
img.save(args.out)
print('saved', args.out, 'parts drawn', drawn)
