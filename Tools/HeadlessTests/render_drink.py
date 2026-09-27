# Draws the drink (CombatClient's "The drink, as everyone sees it") from the
# real code's joint poses:
#   luau test_drink.luau -a poses > d.txt
#   python3 render_drink.py d.txt ../../Docs/drink_preview.png
# BIT lines are the potion's pieces (size, colour, where they're welded on the
# right arm); POSE lines are the right shoulder's and the neck's Transform
# (x y z and the 3x3 turn, like CFrame:GetComponents()) at a moment of the
# drink. Each moment is drawn from the front and from the side, as a blocky
# R6 character (with the potion when it's out).
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


bits, poses = [], []
for line in open(src):
    p = line.split()
    if not p:
        continue
    if p[0] == "BIT":
        size = tuple(float(v) for v in p[2:5])
        color = tuple(int(v) for v in p[5:8])
        bits.append((p[1], size, color, cf([float(v) for v in p[8:20]])))
    elif p[0] == "POSE":
        t = float(p[1])
        rest = line.split(None, 2)[2]
        arm_s, neck_s, pot = [s.strip() for s in rest.split("|")]
        poses.append((t, cf([float(v) for v in arm_s.split()]), cf([float(v) for v in neck_s.split()]), pot == "potion"))

# Roblox's R6 joints
SC0 = cf([1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0])
SC1 = cf([-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0])
NC0 = cf([0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0])
NC1 = cf([0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0])
inv = np.linalg.inv
SKIN, SHIRT, PANTS, INK = (245, 205, 48), (13, 105, 172), (40, 127, 71), (24, 20, 37)


def box(M, size, color):
    sx, sy, sz = [s / 2 for s in size]
    P = [(M @ np.array([x, y, z, 1.0]))[:3] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    return [([P[i] for i in f], color) for f in faces]


def character(armT, neckT, withPotion):
    polys = []
    polys += box(np.eye(4), (2, 2, 1), SHIRT)
    polys += box(T(-1.5, 0, 0), (1, 2, 1), SKIN)
    polys += box(T(-0.5, -2, 0), (1, 2, 1), PANTS)
    polys += box(T(0.5, -2, 0), (1, 2, 1), PANTS)
    A = SC0 @ armT @ inv(SC1)
    polys += box(A, (1, 2, 1), SKIN)
    H = NC0 @ neckT @ inv(NC1)
    polys += box(H, (1.25, 1.2, 1.2), SKIN)
    for ex in (-0.26, 0.26):
        polys += box(H @ T(ex, 0.12, -0.61), (0.14, 0.24, 0.02), INK)
    polys += box(H @ T(0, -0.25, -0.61), (0.4, 0.08, 0.02), INK)
    if withPotion:
        for name, size, color, c0 in bits:
            polys += box(A @ c0, size, color)
    return polys


def render(polys, yaw, pitch, size, label):
    img = Image.new("RGB", (size, size), (58, 68, 102))
    d = ImageDraw.Draw(img)
    V = Rx(math.radians(-pitch)) @ Ry(math.radians(yaw))
    light = np.array([0.4, 0.8, -0.5])
    light /= np.linalg.norm(light)
    items = []
    for pts, col in polys:
        Q = [V @ p for p in pts]
        n = np.cross(Q[1] - Q[0], Q[2] - Q[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9:
            continue
        items.append((np.mean([q[2] for q in Q]), Q, col, n / nn))
    items.sort(key=lambda it: -it[0])
    s = size / 7.2
    for _, Q, col, n in items:
        shade = 0.55 + 0.45 * abs(np.dot(n, V @ light))
        d.polygon([(size / 2 - q[0] * s, size * 0.56 - q[1] * s) for q in Q],
                  fill=tuple(int(c * shade) for c in col), outline=INK)
    f = ImageFont.truetype(BOLD, 18)
    d.text((10, 8), label, font=f, fill=(192, 203, 220))
    return img


CAPTIONS = ["START", "UP TO THE CHIN", "HOLD", "TIP IT BACK", "BOTTOMS UP", "GULP", "PUT AWAY"]
size = 300
cols = len(poses)
sheet = Image.new("RGB", (cols * size + (cols + 1) * 12, 2 * size + 150), (24, 20, 37))
d = ImageDraw.Draw(sheet)
d.text((sheet.width // 2, 40), "DRINKING A FLASK", font=ImageFont.truetype(BOLD, 44), fill=(254, 231, 97), anchor="mm")
cf_ = ImageFont.truetype(BOLD, 22)
for i, (t, armT, neckT, pot) in enumerate(poses):
    x = 12 + i * (size + 12)
    name = CAPTIONS[i] if i < len(CAPTIONS) else ""
    d.text((x + size // 2, 96), "%s  (%.2fs)" % (name, t), font=cf_, fill=(255, 255, 255), anchor="mm")
    polys = character(armT, neckT, pot)
    sheet.paste(render(polys, -25, 8, size, "front"), (x, 120))
    sheet.paste(render(polys, 90, 4, size, "side"), (x, 120 + size + 6))
sheet.save(out)
print("wrote", out, cols, "moments")
