"""Draws the Colosseum's DIFFICULTY board where LobbyBuilder puts it: beside
the exit gate, seen from behind a player who has just arrived. The board's
parts come from `test_builder.luau -a dump` (the real LobbyBuilder code); the
arena around it is a simple model (sand, the stands with their gap at the
gate, the gatehouse and its door). The words on the plaques, the floating
sign and the "E" prompt are drawn on top, where they'd show.

    luau test_builder.luau -a dump | grep ^BOARD > board.txt
    python3 render_board.py board.txt out.png [--font PressStart2P.ttf]
"""
import json, math, argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument('board')
ap.add_argument('out')
ap.add_argument('--font', default='PressStart2P.ttf')
ap.add_argument('--size', default='1280,720')
ap.add_argument('--picked', default='Normal')  # which plaque says PICKED
ap.add_argument('--locked', default='Nightmare')  # which say LOCKED (comma list)
args = ap.parse_args()

line = open(args.board).read().strip()
head, rest = line.split(' [', 1)
_, sx, sy, sz = head.split()
parts = json.loads('[' + rest)
CENTER = np.array([-2600.0, 0, 0])
S = 2.6
DOOR_Z = CENTER[2] + (-42 + 3.05) * S  # the exit door, on the inside of the gatehouse
spawn = np.array([float(sx), -0.78, float(sz)])  # (the gate's floor is the mound, a touch lower)

W, H = [int(v) for v in args.size.split(',')]
SS = 2
w, h = W * SS, H * SS
# the camera: behind the player (towards the door), looking past them at the board
board = np.mean([np.array(p['cf'][0:3]) for p in parts if p['name'] == 'Plaque'], axis=0)
eye = spawn + np.array([-11, 10.5, -3])
look = spawn * 0.45 + board * 0.55 + np.array([0, 2.4, 0])
fwd = look - eye
fwd /= np.linalg.norm(fwd)
right = np.cross(fwd, [0, 1, 0])
right /= np.linalg.norm(right)
up = np.cross(right, fwd)
f = (h / 2) / math.tan(math.radians(70) / 2)
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


def part(center, R, size, col, t=0.0, neon=False):
    for n, q in box_faces(center, R, size):
        if (q[0] - eye) @ n >= 0:
            continue
        c = shade(col, n, neon)
        fidc[0] += 1
        if t <= 0.001:
            for i in range(1, len(q) - 1):
                raster(q[0], q[i], q[i + 1], c, fidc[0])
        else:
            transparent.append((float(np.linalg.norm(np.mean(q, axis=0) - eye)), q, c, 1 - t))


I = np.eye(3)
# ---- the arena near the gate (s = 2.6): the sand, the mound by the gate
for gx in range(-12, 12):
    for gz in range(-12, 12):
        cx, cz = CENTER[0] + gx * 10 + 5, CENTER[2] + gz * 10 + 5
        d = math.hypot(cx - CENTER[0], cz - CENTER[2])
        if d < 91:
            part(np.array([cx, -0.5, cz]), I, (10, 1, 10), (216, 156, 106))
        elif d < 118:
            part(np.array([cx, -1.28, cz]), I, (10, 1, 10), (234, 212, 170))
# the stands (three tiers with a crowd), with their gap at the gate, and the wall
rng = np.random.default_rng(3)
N = 32
for i in range(N):
    a = (i + 0.5) / N * 2 * math.pi
    dirv = np.array([math.sin(a), 0, math.cos(a)])
    at_gate = dirv @ np.array([0, 0, -1]) > math.cos(math.radians(14))
    Rm = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    if not at_gate:
        for k in range(1, 4):
            r = (42 - 1.6 - k * 2.4) * S
            hgt = (1 + (4 - k) * 2.2) * S
            part(CENTER + dirv * r + np.array([0, hgt / 2 - 0.8, 0]), Rm, (2 * math.pi * r / N + 0.6, hgt, 2.4 * S),
                 (184, 111, 80) if k % 2 == 0 else (200, 140, 96))
            if rng.random() < 0.7:
                colr = [(228, 59, 68), (254, 174, 52), (99, 199, 77), (0, 153, 219), (255, 255, 255), (181, 80, 136)][rng.integers(0, 6)]
                part(CENTER + dirv * r + np.array([0, hgt + 1.3, 0]), Rm, (2.2, 3, 1.8), colr)
                part(CENTER + dirv * r + np.array([0, hgt + 3.6, 0]), Rm, (1.8, 1.8, 1.8), (255, 214, 170))
        part(CENTER + dirv * 42 * S + np.array([0, 7 * S - 3.4, 0]), Rm, (2 * math.pi * 42 * S / N + 1, 12 * S, 3.2 * S), (228, 166, 114))
# the gatehouse, its door (the way out), banners and torches
gz = CENTER[2] - 42 * S
part(np.array([CENTER[0], 9 * S - 3.4, gz]), I, (14 * S, 16 * S, 6 * S), (228, 166, 114))
part(np.array([CENTER[0], 3 * S - 3.4, DOOR_Z]), I, (3 * S, 4 * S, 0.4 * S), (24, 20, 37))
part(np.array([CENTER[0], 5.4 * S - 3.4, DOOR_Z + 0.1]), I, (4.4 * S, 0.8 * S, 0.5 * S), (234, 212, 170))
for sx_ in (-1, 1):
    part(np.array([CENTER[0] + sx_ * 4.6 * S, 10 * S - 3.4, DOOR_Z + 0.3]), I, (2.6 * S, 7 * S, 0.3 * S), (170, 45, 50))
    part(np.array([CENTER[0] + sx_ * 4.6 * S, 6.7 * S - 3.4, DOOR_Z + 0.35]), I, (2.6 * S, 0.5 * S, 0.35 * S), (254, 174, 52))
    part(np.array([CENTER[0] + sx_ * 2.8 * S, 6.1 * S - 3.4, DOOR_Z + 0.9]), I, (0.7 * S, 0.7 * S, 0.7 * S), (254, 174, 52), neon=True)

# ---- the board (the real LobbyBuilder parts)
plaques = []
sign = None
for p in parts:
    cf = p['cf']
    R = np.array(cf[3:12]).reshape(3, 3)
    c = np.array(cf[0:3])
    if p['name'] == 'SignAnchor':
        sign = (c, p['diff'])
        continue
    part(c, R, p['size'], p['color'], t=p['t'], neon=p['mat'] == 'Neon')
    if p['name'] == 'Plaque':
        plaques.append((c, R, p['size'], p['diff']))
face_part = [p for p in parts if p['name'] == 'DifficultyFace'][0]

# ---- the player: a blocky figure at the spawn, facing the board
face = board - spawn
yaw = math.atan2(face[0], face[2])
Rp = np.array([[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]])
skin = (255, 204, 153)
for (cx, cy, cz), sz_, col in (((-0.5, 1, 0), (0.95, 2, 1), (40, 90, 200)), ((0.5, 1, 0), (0.95, 2, 1), (40, 90, 200)),
                               ((0, 3, 0), (2, 2, 1), (99, 199, 77)), ((-1.5, 3, 0), (0.95, 2, 1), skin), ((1.5, 3, 0), (0.95, 2, 1), skin),
                               ((0, 4.6, 0), (1.2, 1.2, 1.2), skin)):
    part(spawn + Rp @ np.array([cx, cy, cz]), Rp, sz_, col)

transparent.sort(key=lambda x: -x[0])
for _, q, c, alpha in transparent:
    for i in range(1, len(q) - 1):
        raster(q[0], q[i], q[i + 1], c, -2, alpha)
edge = np.zeros((h, w), dtype=bool)
edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
edge &= ids >= 0
color[edge] *= 0.6
img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8))

# ---- the words on each plaque (its SurfaceGui), warped onto its front face
INK = (24, 20, 37)


def font(size):
    return ImageFont.truetype(args.font, size)


def plaque_face(diff_id, col):
    pw, ph = 380, 560
    im = Image.new('RGBA', (pw, ph), tuple(col) + (255,))
    d = ImageDraw.Draw(im)
    names = {'Normal': ('NORMAL', 1, 'x1'), 'Hard': ('HARD', 2, 'x2'), 'Nightmare': ('NIGHTMARE', 3, 'x3.5')}
    name, pips, pay = names.get(diff_id, (diff_id.upper(), 1, 'x1'))
    fs = 50 if len(name) <= 6 else 36
    d.text((pw / 2, 70), name, font=font(fs), fill=(255, 255, 255), anchor='mm', stroke_width=5, stroke_fill=INK)
    for k in range(pips):
        x = pw / 2 + (k - (pips - 1) / 2) * 76
        d.rectangle([x - 26, 150, x + 26, 182], fill=(255, 255, 255), outline=INK, width=5)
    d.text((pw / 2, 290), pay, font=font(96), fill=(254, 231, 97), anchor='mm', stroke_width=7, stroke_fill=INK)
    d.text((pw / 2, 395), 'COINS & XP', font=font(26), fill=(255, 255, 255), anchor='mm', stroke_width=4, stroke_fill=INK)
    status = 'PICKED' if diff_id == args.picked else ('LOCKED' if diff_id in args.locked.split(',') else '')
    if status:
        d.text((pw / 2, 482), status, font=font(40), fill=(139, 155, 180) if status == 'LOCKED' else (255, 255, 255),
               anchor='mm', stroke_width=5, stroke_fill=INK)
    return im


for c, R, size, diff_id in plaques:
    hx, hy, hz = np.array(size) / 2
    ax, ay, az = R[:, 0], R[:, 1], R[:, 2]
    fc = c + az * hz  # the front (local +Z)
    # seen from the front, local -X is on the left (the plaque's right is your left)
    tl, tr = fc - ax * hx + ay * hy, fc + ax * hx + ay * hy
    bl, br = fc - ax * hx - ay * hy, fc + ax * hx - ay * hy
    quad = [project(q)[0] for q in (tl, tr, br, bl)]
    col = [p['color'] for p in parts if p['name'] == 'Plaque' and p['diff'] == diff_id][0]
    src = plaque_face(diff_id, col)
    # the perspective transform: output pixels -> the plaque picture
    A, B = [], []
    for (x, y), (u, v) in zip(quad, ((0, 0), (src.width, 0), (src.width, src.height), (0, src.height))):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); B.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); B.append(v)
    coeffs = np.linalg.solve(np.array(A, dtype=float), np.array(B, dtype=float))
    warped = src.transform((w, h), Image.PERSPECTIVE, tuple(coeffs), Image.BICUBIC)
    img.paste(warped, (0, 0), warped)

d = ImageDraw.Draw(img)
# ---- the floating sign (a billboard: always faces you)
if sign:
    (sx2, sy2), z = project(sign[0])
    bw = f * 12.4 / z
    bh = bw * 0.22
    d.rectangle([sx2 - bw / 2, sy2 - bh / 2, sx2 + bw / 2, sy2 + bh / 2], fill=(12, 10, 20), outline=(255, 255, 255), width=6)
    fs = int(bh * 0.55)
    while fs > 8 and d.textlength(sign[1], font=font(fs)) > bw * 0.88:
        fs -= 2
    d.text((sx2, sy2), sign[1], font=font(fs), fill=(254, 174, 52), anchor='mm', stroke_width=4, stroke_fill=INK)
# ---- the EXIT sign over the door (LobbyBuilder's, 10 x 2.6 studs up)
(ex, ey), ez = project(np.array([CENTER[0], 26 - 3.4, DOOR_Z]))
if ez > 0.5:
    ebw = f * 160 * (14 / 340) / ez
    ebh = ebw * 0.22
    d.rectangle([ex - ebw / 2, ey - ebh / 2, ex + ebw / 2, ey + ebh / 2], fill=(12, 10, 20), outline=(255, 255, 255), width=5)
    efs = int(ebh * 0.55)
    while efs > 8 and d.textlength('EXIT', font=font(efs)) > ebw * 0.85:
        efs -= 2
    d.text((ex, ey), 'EXIT', font=font(efs), fill=(255, 255, 255), anchor='mm', stroke_width=3, stroke_fill=INK)
# ---- the "E" prompt (Roblox's own look), under the board's plaques
(px, py), _ = project(np.array(face_part['cf'][0:3]) + np.array([0, -5.2, 0]))
d.rounded_rectangle([px - 170, py - 50, px + 170, py + 50], radius=18, fill=(25, 25, 25))
d.rounded_rectangle([px - 150, py - 34, px - 82, py + 34], radius=12, fill=(255, 255, 255))
d.text((px - 116, py), 'E', font=font(34), fill=(25, 25, 25), anchor='mm')
d.text((px - 62, py - 16), 'Difficulty', font=font(18), fill=(200, 200, 200), anchor='lm')
d.text((px - 62, py + 16), 'Choose', font=font(26), fill=(255, 255, 255), anchor='lm')
img = img.resize((W, H), Image.LANCZOS)
img.save(args.out)
print('saved', args.out)
