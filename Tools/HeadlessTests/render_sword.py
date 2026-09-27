# Draws the Iron Sword's stance, its three swings (chained, as you'd play them)
# and the Whirlwind from the real code's poses
# (ReplicatedStorage/WeaponFX, run by test_weaponfx.luau):
#   luau test_weaponfx.luau -a poses > s.txt
#   python3 render_sword.py s.txt ../../Docs/sword_preview.png
# PIECE lines are the sword's blocks (size, colour, where each sits on the
# handle); POSE lines are the right shoulder's and the root joint's Transform
# and the sword's grip (all like CFrame:GetComponents()) at a moment. Each
# moment is drawn from the front and the side, as a blocky R6 character with
# every joint (both arms and legs, the neck, the body lean and turn).
import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def cf(comps):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = comps
    M = np.eye(4)
    M[:3, :3] = [[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]]
    M[:3, 3] = [x, y, z]
    return M


def T(x, y, z):
    M = np.eye(4)
    M[:3, 3] = [x, y, z]
    return M


def Rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


pieces, poses = [], []
for line in open(src):
    p = line.split()
    if not p:
        continue
    if p[0] == "PIECE":
        pieces.append((p[1], tuple(float(v) for v in p[2:5]), tuple(int(v) for v in p[5:8]), cf([float(v) for v in p[8:20]])))
    elif p[0] == "POSE":
        parts = [s.strip() for s in line[5:].split("|")]
        joints = {}
        for chunk in parts[1:-1]:
            bits = chunk.split()
            joints[bits[0]] = cf([float(v) for v in bits[1:13]])
        poses.append((parts[0], joints, parts[-1] == "smear"))

SC0 = cf([1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0])
SC1 = cf([-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0])
RC = cf([0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0])
inv = np.linalg.inv
SKIN, SHIRT, PANTS, INK = (245, 205, 48), (13, 105, 172), (40, 127, 71), (24, 20, 37)


def box(M, size, color):
    sx, sy, sz = [s / 2 for s in size]
    P = [(M @ np.array([x, y, z, 1.0]))[:3] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    return [([P[i] for i in f], color) for f in faces]


LC0 = cf([-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0])
LC1 = cf([0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0])
RHC0 = cf([1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0])
RHC1 = cf([0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0])
LHC0 = cf([-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0])
LHC1 = cf([-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0])
NC0 = cf([0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0])
NC1 = cf([0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0])


def character(j):
    polys = []
    torso = RC @ j["Root"] @ inv(RC)  # the whole body, turned and leaned by the root joint
    polys += box(torso, (2, 2, 1), SHIRT)
    polys += box(torso @ LC0 @ j["LS"] @ inv(LC1), (1, 2, 1), SKIN)
    polys += box(torso @ RHC0 @ j["RH"] @ inv(RHC1), (1, 2, 1), PANTS)
    polys += box(torso @ LHC0 @ j["LH"] @ inv(LHC1), (1, 2, 1), PANTS)
    A = torso @ SC0 @ j["RS"] @ inv(SC1)
    polys += box(A, (1, 2, 1), SKIN)
    H = torso @ NC0 @ j["Neck"] @ inv(NC1)
    polys += box(H, (1.25, 1.2, 1.2), SKIN)
    for ex in (-0.26, 0.26):
        polys += box(H @ T(ex, 0.12, -0.61), (0.14, 0.24, 0.02), INK)
    polys += box(H @ T(0, -0.25, -0.61), (0.4, 0.08, 0.02), INK)
    handle = A @ j["Grip"]
    for name, size, color, off in pieces:
        polys += box(handle @ off, size, color)
    tipAt = (handle @ np.array([0, 0, -5, 1.0]))[:3]
    return polys, tipAt


def project(V, p, size, scale):
    q = V @ p
    return (size / 2 - q[0] * scale, size * 0.55 - q[1] * scale), q[2]


def render(polys, yaw, pitch, size, label, trailPts=None):
    img = Image.new("RGB", (size, size), (58, 68, 102))
    d = ImageDraw.Draw(img, "RGBA")
    V = Rx(math.radians(-pitch)) @ Ry(math.radians(yaw))
    light = np.array([0.4, 0.8, -0.5])
    light /= np.linalg.norm(light)
    scale = size / 10.5
    # the swing's arc so far (the trail), drawn under the body
    if trailPts and len(trailPts) > 1:
        pts = [project(V, p, size, scale)[0] for p in trailPts]
        d.line(pts, fill=(255, 255, 255, 170), width=6)
    items = []
    for pts, col in polys:
        Q = [V @ p for p in pts]
        n = np.cross(Q[1] - Q[0], Q[2] - Q[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9:
            continue
        items.append((np.mean([q[2] for q in Q]), Q, col, n / nn))
    items.sort(key=lambda it: -it[0])
    for _, Q, col, n in items:
        shade = 0.55 + 0.45 * abs(np.dot(n, V @ light))
        d.polygon([(size / 2 - q[0] * scale, size * 0.55 - q[1] * scale) for q in Q],
                  fill=tuple(int(c * shade) for c in col), outline=INK)
    f = ImageFont.truetype(BOLD, 17)
    d.text((10, 8), label, font=f, fill=(192, 203, 220))
    return img


size = 260
# one row per move: the stance and the slash, the backhand, the leap, the Whirlwind
rows, order = {}, []
for label, joints, smearOn in poses:
    group = label.split(":")[0].split(" ")[0]
    key = "SLASH" if group == "STANCE" else group
    if key not in rows:
        rows[key] = []
        order.append(key)
    rows[key].append((label, joints, smearOn, group))
cols = max(len(r) for r in rows.values())
cellH = 2 * size + 6 + 52
sheet = Image.new("RGB", (cols * size + (cols + 1) * 10, 110 + len(order) * (cellH + 16)), (24, 20, 37))
d = ImageDraw.Draw(sheet)
d.text((sheet.width // 2, 36), "THE IRON SWORD  -  WIND UP, HOLD, SNAP, RIP THROUGH", font=ImageFont.truetype(BOLD, 38),
       fill=(254, 231, 97), anchor="mm")
d.text((sheet.width // 2, 76), "the swings chained as you'd play them: each one starts from the last one's follow-through",
       font=ImageFont.truetype(BOLD, 18), fill=(192, 203, 220), anchor="mm")
cf_ = ImageFont.truetype(BOLD, 17)
for r, key in enumerate(order):
    y0 = 110 + r * (cellH + 16)
    trail, lastGroup = [], None
    for c, (label, joints, smearOn, group) in enumerate(rows[key]):
        if group != lastGroup:
            trail, lastGroup = [], group
        polys, tipAt = character(joints)
        if smearOn or group == "WHIRLWIND":
            trail.append(tipAt)
        x = 10 + c * (size + 10)
        for k, word in enumerate(label.split(": ")):
            d.text((x + size // 2, y0 + 12 + k * 20), word, font=cf_, fill=(255, 255, 255), anchor="mm")
        sheet.paste(render(polys, -25, 8, size, "front", trail[:]), (x, y0 + 52))
        sheet.paste(render(polys, 90, 4, size, "side", trail[:]), (x, y0 + 52 + size + 6))
sheet.save(out)
print("wrote", out, len(poses), "moments")
