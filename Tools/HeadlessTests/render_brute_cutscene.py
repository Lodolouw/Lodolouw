"""Films THE BRUTE's cutscene: every frame brute_cutscene.luau printed (the
real Sunken Dunes, Tuber's real body and poses, the player), shot by a moving
camera - over the shoulder as little Tuber gets punched, wide and high as the
desert flies to him, up at his head as the crown drops, low behind the player
as he roars, at his roots as they rip up, up at the sky as he leaps, low and
wide for the slam, then over the shoulder and from the side as the player
punches back - with the boss bar, his name's letters swapping (TUBER ->
BRUTE, then THE slams down: his body file's title, on the film's clock), hit
pops, his word bubbles, the game's particle bursts, flashes and camera shake
on top. It ends on a freeze frame as his spines blast the player away: CAN
YOU BEAT THE BRUTE? 1080 x 1920 (a YouTube Short), 30 frames a second.

    luau brute_cutscene.luau > brute.txt
    python3 render_brute_cutscene.py brute.txt ../../Docs/youtube/brute_cutscene.mp4
    python3 render_brute_cutscene.py brute.txt strip.png --strip      (a few frames, to check)
    python3 render_brute_cutscene.py brute.txt strip.png --strip --at 2.9,5.2   (just those moments)
    python3 render_brute_cutscene.py brute.txt sheet.png --sheet      (9 frames in a 3 x 3 contact sheet)

The drawing is render_cutscene.py's (flat colours lit by one sun, thin dark
edges: the game's 8-bit look), so it shows the game's real shapes and
colours, not Roblox's own lighting. Roblox draws particles itself; the
pretend Roblox can't, so the scene writes down every puff BossClient emits
(BURST) and they're drawn here as little blocks of sand, cactus and spark.
"""
import json, math, os, sys, argparse
import numpy as np
from PIL import Image, ImageDraw

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, '..', '..', 'Docs', 'youtube'))
from pixel_art import text_image, INK, YEL, WHITE, RED, GREEN, ORANGE  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('out')
ap.add_argument('--strip', action='store_true', help='just a strip of a few frames (a PNG)')
ap.add_argument('--sheet', action='store_true', help='a 3 x 3 contact sheet of frames across the film (a PNG)')
ap.add_argument('--at', default='', help='with --strip / --sheet: the moments to show (seconds, comma separated)')
ap.add_argument('--thumb', type=int, default=270, help='with --strip: how wide each frame is (pixels)')
ap.add_argument('--workers', type=int, default=4)
ap.add_argument('--scale', type=int, default=2, help='draw at 1/scale size, then blow up (chunkier, faster)')
args = ap.parse_args()

OUT_W, OUT_H, FPS = 1080, 1920, 30
W, H = OUT_W // args.scale, OUT_H // args.scale
SS = 2

# ----------------------------------------------------------------------
# what the scene printed
# ----------------------------------------------------------------------
static, frames, bursts, events = [], [], [], {}
cur = None
mode = None
for line in open(args.src):
    if line.startswith('STATIC'):
        mode = 'static'
    elif line.startswith('ENDSTATIC'):
        mode = None
    elif line.startswith('FRAME '):
        bits = line.split()
        cur = {'i': int(bits[1]), 't': float(bits[2]), 'g': float(bits[3]), 'parts': [], 'over': {}, 'shouts': [],
               'hints': [], 'big': None, 'anchor': None, 'gamecam': None}
        frames.append(cur)
        mode = 'frame'
    elif line.startswith('POS ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['boss'], cur['player'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('STATE ') and cur is not None:
        bits = line.split()
        cur['state'], cur['hp'], cur['action'], cur['form'] = bits[1], float(bits[2]), bits[3], bits[4]
    elif line.startswith('BAR ') and cur is not None:
        name, share, phase = line[4:].rstrip('\n').split('|')
        cur['bar'] = (name.upper(), float(share), int(phase))
    elif line.startswith('ANCHOR ') and cur is not None:
        cur['anchor'] = np.array([float(x) for x in line.split()[1:4]])
    elif line.startswith('GAMECAM ') and cur is not None:
        cur['gamecam'] = [float(x) for x in line.split()[1:8]]
    elif line.startswith('SHOUT ') and cur is not None:
        bits = line.rstrip('\n').split(' ', 7)
        cur['shouts'].append(((int(bits[1]), int(bits[2]), int(bits[3])), np.array([float(x) for x in bits[4:7]]), bits[7]))
    elif line.startswith('HINT ') and cur is not None:
        bits = line.rstrip('\n').split(' ', 7)
        cur['hints'].append(((int(bits[1]), int(bits[2]), int(bits[3])), np.array([float(x) for x in bits[4:7]]), bits[7]))
    elif line.startswith('BIG ') and cur is not None:
        bits = line.rstrip('\n').split(' ', 4)
        cur['big'] = ((int(bits[1]), int(bits[2]), int(bits[3])), bits[4])
    elif line.startswith('BURST '):
        b = [float(x) for x in line.split()[1:]]
        bursts.append({'g': b[0], 'pos': np.array(b[1:4]), 'col': (int(b[4]), int(b[5]), int(b[6])), 'n': int(b[7]),
                       'speed': (b[8], b[9]), 'size': (b[10], b[11]), 'life': (b[12], b[13]), 'spread': b[14],
                       'acc': b[15], 'drag': b[16]})
    elif line.startswith('EVENT '):
        bits = line.split()
        events.setdefault(bits[1], []).append((float(bits[2]), [float(x) for x in bits[3:]]))
    elif line.startswith('ENDFRAME'):
        mode = None
    elif line.startswith('{'):
        p = json.loads(line)
        if mode == 'static':
            static.append(p)
        elif mode == 'frame':
            if 'i' in p:
                cur['over'][p['i']] = p
            else:
                cur['parts'].append(p)
    elif line.startswith('ERROR'):
        print(line.rstrip())
static_by_index = {p['i']: p for p in static}
FLOOR = frames[0]['player'][1] - 3  # (the player's middle is 3 studs over the floor)
HOME = np.array([frames[0]['boss'][0], FLOOR, frames[0]['boss'][2]])  # little Tuber's garden, the middle of the bowl
for fr in frames:
    # (BossClient's shader warm-up: specks you can't see, in front of its own camera)
    fr['parts'] = [p for p in fr['parts'] if p['n'] != 'Warm']


def ev(name, k=0):
    return events[name][k][0]


LAND = None
for fr in frames:
    if fr['t'] >= ev('land') + 0.05:
        LAND = np.array([fr['boss'][0], FLOOR, fr['boss'][2]])  # where his hop came down
        break
print('scene:', len(static), 'arena parts,', len(frames), 'frames,', len(bursts), 'bursts')

# ----------------------------------------------------------------------
# the particles: each burst's puffs, the same every frame they're drawn
# (a Roblox ParticleEmitter: out along a cone round straight up, slowed by
# its Drag, pulled by its Acceleration, growing and fading over its life)
# ----------------------------------------------------------------------


def puffs(g):
    out = []
    for bi, b in enumerate(bursts):
        age0 = g - b['g']
        if age0 < 0 or age0 > b['life'][1]:
            continue
        rng = np.random.default_rng(1000 + bi)
        n = b['n']
        theta = np.radians(rng.random(n) * b['spread'])
        phi = rng.random(n) * 2 * math.pi
        speed = b['speed'][0] + rng.random(n) * (b['speed'][1] - b['speed'][0])
        life = b['life'][0] + rng.random(n) * (b['life'][1] - b['life'][0])
        spin = rng.random((n, 3)) * 2 * math.pi
        for i in range(n):
            if age0 > life[i]:
                continue
            u = age0 / life[i]
            d = np.array([math.sin(theta[i]) * math.cos(phi[i]), math.cos(theta[i]), math.sin(theta[i]) * math.sin(phi[i])])
            k = b['drag'] * math.log(2)
            travel = (1 - math.exp(-k * age0)) / k if k > 0 else age0
            p = b['pos'] + d * speed[i] * travel + np.array([0, 0.5 * b['acc'] * age0 * age0, 0])
            p[1] = max(p[1], FLOOR + 0.2)
            size = (b['size'][0] + (b['size'][1] - b['size'][0]) * u) * 0.75
            a, bb, c = spin[i] + age0 * 2
            R = rotation(a, bb, c)
            cf = list(p) + list(R.reshape(-1))
            # (Roblox lights its smoke puffs up a little - LightEmission - so they show against the sand)
            col = [min(255, int(x * 1.12 + 28)) for x in b['col']]
            out.append({'n': 'Puff', 'c': 'Part', 's': [size, size, size], 'cf': cf, 'col': col, 'm': 'SmoothPlastic',
                        'sh': 'Block', 't': min(0.97, 0.25 + 0.72 * u * u)})
    return out


def rotation(a, b, c):
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rx = np.array([[1, 0, 0], [0, ca, -sa], [0, sa, ca]])
    ry = np.array([[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]])
    rz = np.array([[cc, -sc, 0], [sc, cc, 0], [0, 0, 1]])
    return rx @ ry @ rz


# ----------------------------------------------------------------------
# the drawing (render_cutscene.py's, with the dunes' hot afternoon sky)
# ----------------------------------------------------------------------
LIGHT = np.array([-0.45, 0.8, 0.35])
LIGHT /= np.linalg.norm(LIGHT)
NEAR = 0.5
SKY_TOP, SKY_LOW = np.array([0, 153, 219], dtype=np.float32), np.array([150, 200, 225], dtype=np.float32)


def render(parts, eye, look, fov, rng_limit=340):
    w, h = W * SS, H * SS
    fwd = look - eye
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (h / 2) / math.tan(math.radians(fov) / 2)
    color = np.zeros((h, w, 3), dtype=np.float32)
    # the sky by how far up each row looks (bluest straight up, hazy at the horizon)
    rows = (h / 2 - (np.arange(h) + 0.5)) / f
    ys = fwd[1] + rows * up[1]
    flat_len = np.sqrt(np.maximum((fwd[0] + rows * up[0]) ** 2 + (fwd[2] + rows * up[2]) ** 2, 1e-9))
    elev = np.degrees(np.arctan2(ys, flat_len))
    k = np.clip(elev / 38.0, 0, 1)[:, None]
    color[:] = (SKY_LOW * (1 - k) + SKY_TOP * k)[:, None, :]
    depth = np.full((h, w), -np.inf, dtype=np.float32)
    ids = np.full((h, w), -1, dtype=np.int32)
    transparent = []
    fidc = [0]

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
        xs, ys_ = np.meshgrid(np.arange(xmin, xmax + 1) + 0.5, np.arange(ymin, ymax + 1) + 0.5)
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            return
        l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys_ - c[1])) / den
        l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys_ - c[1])) / den
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

    def shade(col, n, neon):
        if neon:
            return np.clip(np.array(col, dtype=np.float32) * 1.1 + (14 if sum(col) > 0 else 0), 0, 255)
        return np.clip(np.array(col, dtype=np.float32) * (0.6 + 0.4 * max(0.0, float(n @ LIGHT))), 0, 255)

    def clip(q):
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

    tan_half = math.tan(math.radians(fov) / 2)
    for p in parts:
        if p['t'] >= 0.98:
            continue
        cf = p['cf']
        c = np.array(cf[0:3])
        s = p['s']
        rad = 0.5 * math.sqrt(s[0] ** 2 + s[1] ** 2 + s[2] ** 2)
        q = c - eye
        z = q @ fwd
        if np.linalg.norm(q) - rad > rng_limit or z < -rad:
            continue
        if z > 0:
            sx = abs(q @ right) - rad
            sy = abs(q @ up) - rad
            if sx > z * tan_half * (w / h) * 1.05 or sy > z * tan_half * 1.05:
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

    def to_screen(pt):
        (sx_, sy_), sz = project(np.asarray(pt, dtype=float))
        return (sx_ / SS * args.scale, sy_ / SS * args.scale) if sz > 0 else None
    return img, to_screen


# ----------------------------------------------------------------------
# the camera: one shot after another
# ----------------------------------------------------------------------
def ease(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def flat(v):
    return np.array([v[0], 0.0, v[2]])


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-6 else np.array([0.0, 0.0, -1.0])


def V(x, y, z):
    return np.array([float(x), float(y), float(z)])


# the cuts (seconds of film) - the scene's own moments where it has them
CUT_FLY = ev('fly')
CUT_CROWN = ev('crown')
CUT_ROAR = ev('roar')
CUT_HOP = ev('hop')
T_TAKEOFF, T_LAND = ev('takeoff'), ev('land')
CUT_LEAP = T_TAKEOFF + 0.02
CUT_SLAM = T_LAND - 0.02
CUT_BACK = ev('cornered') + 0.05
CUT_SIDE = ev('hit', 6) - 0.12  # (between the third punch of the fight back and the fourth)
T_BLAST = ev('blast')
FREEZE = T_BLAST + 0.034  # the freeze frame: a frame into the blast - his arms thrown wide, the player just blown off his spines
FACE_B = unit(V(0.34, 0, 1))  # (how the Brute stands for the fight back: the scene's faceB)
RIGHT_B = np.cross(FACE_B, [0, 1, 0])
PUNCH_DIR = unit(FACE_B * 5.0 - RIGHT_B * 2.5)  # (from him to where the player stands to punch: the scene's punchSpot)
CUTS = [0.0, CUT_FLY, CUT_CROWN, CUT_ROAR, CUT_HOP, CUT_LEAP, CUT_SLAM, CUT_BACK, CUT_SIDE, FREEZE]


def shot_of(t):
    """Which shot the film is in at time t (effects don't carry over a cut)."""
    return max(i for i, c in enumerate(CUTS) if c <= t + 1e-6)


def frame_both(eye, low, high, fov_min=58.0, margin=5.0):
    """A look point and lens that keep everything from `low` up to `high` (two
    world points) in the picture: aimed between them, the lens wide enough."""
    def elev(pt):
        d = pt - eye
        return math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
    e0, e1 = elev(low), elev(high)
    mid = (e0 + e1) / 2
    fov = max(fov_min, (e1 - e0) + 2 * margin)
    az = unit(flat((low + high) / 2 - eye))
    look = eye + az * 10 + V(0, 10 * math.tan(math.radians(mid)), 0)
    return look, fov


def shots(fr):
    """Where the camera is and what it looks at in frame `fr`, and its lens."""
    t = fr['t']
    B, P = fr['boss'], fr['player']
    p = V(P[0], FLOOR, P[2])  # (the player, on the floor)
    if t < CUT_FLY:  # 1) from high over the player's right shoulder (a pushover's angle): little Tuber gets punched, and flops
        k = ease(t / CUT_FLY)
        eye = HOME + V(8.0, 11.0, 24) + V(-0.8, -0.6, -2.5) * k
        look = HOME + V(0.6, 3.2, 2.5)
        return eye, look, 52
    if t < CUT_CROWN:  # 2) wide and high, swinging round: the cacti rip out and fly to him, the golem slams together
        # (a crane down, swinging round him - where the game's own camera swings, 58 studs out and 30 up)
        k = ease((t - CUT_FLY) / (CUT_CROWN - CUT_FLY))
        ang = lerp(0.1, 0.5, k)
        dist, height = lerp(58, 40, k), lerp(30, 11, k)
        eye = HOME + V(math.sin(ang) * dist, height, math.cos(ang) * dist)
        look = HOME + V(0, lerp(2, 7.5, k), 0)  # (low: the golem above the letters)
        return eye, look, 64
    if t < CUT_ROAR:  # 3) up at his head: the crown drops on
        k = ease((t - CUT_CROWN) / (CUT_ROAR - CUT_CROWN))
        eye = HOME + V(11, 14, 36) + V(-1, 0.5, -3) * k
        look = HOME + V(0.8, 21.5, 0)
        return eye, look, 50
    if t < CUT_HOP:  # 4) low behind the player: he towers over them and ROARS
        k = ease((t - CUT_ROAR) / (CUT_HOP - CUT_ROAR))
        eye = HOME + V(-7.5, 1.6, 41) + V(0.8, 0.2, -3.0) * k
        look = HOME + V(-0.6, 13.0, 0)
        return eye, look, 64
    if t < CUT_LEAP:  # 5) low at his feet: the roots rip up out of the sand, he crouches...
        k = ease((t - CUT_HOP) / (CUT_LEAP - CUT_HOP))
        eye = HOME + V(15, 2.4, 36) + V(-1, 0.2, -2) * k
        look = HOME + V(0, 11, 0)
        return eye, look, 58
    if t < CUT_SLAM:  # 6) behind the player, looking up: he leaps across the sky at them
        eye = LAND + V(8.0, 4.0, 23)
        low = p + V(0, -0.5, 0)
        top = fr['anchor'] if fr['anchor'] is not None else B + V(0, 28, 0)
        high = top + V(0, 4, 0)
        look, fov = frame_both(eye, low, high, fov_min=60, margin=5)
        # (a little of the frame's top is the boss bar's: aim a touch higher)
        look = look + V(0, 0.9, 0)
        return eye, look, fov
    if t < CUT_BACK:  # 7) low and wide from the side: the slam, the ring of sand, the roll through it
        k = ease((t - CUT_SLAM) / (CUT_BACK - CUT_SLAM))
        side = unit(FACE_B * 0.9 - RIGHT_B * 0.6)  # (his front left, up high: the ring of sand shows on the floor)
        eye = LAND + side * (50 - 3 * k) + V(0, 15, 0)
        look = LAND + FACE_B * 4 + V(0, 10.0, 0)
        return eye, look, 56
    if t < CUT_SIDE:  # 8) from his front right (his face three-quarters on, their punches side on): he panics, they punch
        k = ease((t - CUT_BACK) / (CUT_SIDE - CUT_BACK))
        side = unit(FACE_B * 0.5 + RIGHT_B * 1.0)
        eye = LAND + side * (40 - 3 * k) + V(0, 6.0, 0)
        look = LAND + FACE_B * 4.0 + V(0, 12.0, 0)
        return eye, look, 60
    # 9) behind the player, low (the way the blast will throw them: at us):
    # more punches... his spines bristle, the red ring... BLAST (the freeze)
    tt = min(t, FREEZE)
    k = ease((tt - CUT_SIDE) / (FREEZE - CUT_SIDE))
    eye = LAND + PUNCH_DIR * (37 - 3 * k) + V(0, 3.2, 0)
    look = LAND + V(0, 16.5, 0) + PUNCH_DIR * 2.0
    return eye, look, 62


# camera shake: (when, how hard, how long) - the game's own knocks where it
# makes one (the rumble, THE, the roar, the landing, the blast), and the punches
SHAKES = []


def add_shakes():
    for tt, extra in events.get('hit', []):
        w = extra[0] if extra else 1
        SHAKES.append((tt, (0.18, 0.24, 0.45)[int(w) - 1], 0.15 + 0.05 * w))
    for k in range(4):  # the ground rumbling as the desert rips up
        SHAKES.append((CUT_FLY + k * 0.2, 0.35, 0.22))
    SHAKES.append((CUT_CROWN + 0.55, 0.9, 0.4))  # the crown lands - THE slams down
    SHAKES.append((CUT_ROAR + 0.2, 1.1, 0.9))  # the roar
    SHAKES.append((T_LAND, 1.6, 0.55))  # the slam
    SHAKES.append((T_BLAST, 0.8, 0.3))  # the blast


add_shakes()


def shake(t):
    amp = 0.0
    for at, strength, length in SHAKES:
        if at <= t < at + length:
            amp = max(amp, strength * (1 - (t - at) / length))
    if amp <= 0:
        return np.zeros(3)
    r = np.random.default_rng(int(t * 1000))
    return (r.random(3) - 0.5) * 2 * amp


# ----------------------------------------------------------------------
# on top: the boss bar, the words, pops and flashes
# ----------------------------------------------------------------------
def pop(t, start, steps):
    if t < start:
        return 0
    return steps[min(int((t - start) * FPS), len(steps) - 1)]


def paste_text(img, words, cx, top, scale, fill=YEL, shadow=(160, 80, 40), alpha=1.0):
    if scale <= 0 or alpha <= 0:
        return
    ti = text_image(words, fill=fill, shadow=shadow)
    big = ti.resize((max(1, int(ti.width * scale)), max(1, int(ti.height * scale))), Image.NEAREST)
    if alpha < 1:
        a = big.getchannel('A').point(lambda v: int(v * alpha))
        big.putalpha(a)
    img.paste(big, (int(cx - big.width / 2), int(top)), big)


def boss_bar(img, name, hp, phase):
    d = ImageDraw.Draw(img)
    bw, x0, y0 = 860, (OUT_W - 860) // 2, 210
    label = text_image(name, fill=WHITE, shadow=None)
    label = label.resize((label.width * 5, label.height * 5), Image.NEAREST)
    img.paste(label, (x0, y0 - 58), label)
    fill, light, back = ((99, 199, 77), (170, 235, 130), (20, 40, 26)) if phase < 2 else ((200, 36, 44), (240, 90, 90), (40, 16, 22))
    share = max(0.0, min(1.0, hp))
    d.rectangle([x0 - 6, y0 - 6, x0 + bw + 6, y0 + 34], fill=INK)
    d.rectangle([x0, y0, x0 + bw, y0 + 28], fill=back)
    if share > 0:
        d.rectangle([x0, y0, x0 + int(bw * share), y0 + 28], fill=fill)
        d.rectangle([x0, y0, x0 + int(bw * share), y0 + 6], fill=light)


# THE LETTERS: BossBodies/Tuber's title (TUBER, bouncy and green... shaking,
# going red... sliding into new places: BRUTE... THE slams down), on the
# film's clock instead of the power-up's
L_SHAKE, L_SWAP = CUT_FLY, CUT_FLY + 0.3
L_SNAP = CUT_CROWN - 0.02
L_THE = CUT_CROWN + 0.55  # (with the crown landing on his head)
L_KING = CUT_ROAR + 0.3
L_OUT = CUT_HOP - 0.25
SWAP = (3, 2, 0, 4, 1)  # (T U B E R -> B R U T E: the slot each letter goes to)
LETTER = 20  # pixels per letter pixel
SLOT = 6 * LETTER
TITLE_TOP = 1180
GREEN_C, RED_C, HOT_C = np.array((99, 199, 77)), np.array((228, 59, 68)), (255, 0, 68)


def spring(t, freq, damp):
    return math.exp(-damp * t * 0.25) * math.sin(freq * t)


def mix(a, b, k):
    k = max(0.0, min(1.0, k))
    return tuple(int(x) for x in (np.array(a) * (1 - k) + np.array(b) * k))


def title(img, t):
    if t >= CUT_HOP:
        return
    fade = 1 - max(0.0, min(1.0, (t - L_OUT) / 0.25))
    cx = OUT_W / 2
    for i, ch in enumerate('TUBER'):
        x0 = cx + (i - 2) * SLOT
        x, y, s = x0, 0.0, 1.0
        col = tuple(GREEN_C)
        shadow = (30, 70, 40)
        if t < L_SHAKE:
            y = math.sin(t * 9 + i * 1.3) * 7  # (bouncy, each letter bobbing)
        elif t < L_SWAP:
            k = (t - L_SHAKE) / (L_SWAP - L_SHAKE)
            x += math.sin(t * 70 + i * 3) * 9 * k
            y = math.cos(t * 63 + i * 5) * 9 * k
            col = mix(GREEN_C, RED_C, k * 0.6)
        elif t < L_SNAP:
            u = ease((t - L_SWAP) / (L_SNAP - L_SWAP))
            x = lerp(x0, cx + (SWAP[i] - 2) * SLOT, u)
            # (letters going right pass over, letters going left under - the
            # further they go, the higher the arc - so none runs into another)
            moves = SWAP[i] - i
            y = -math.sin(u * math.pi) * (25 + 90 * abs(moves)) * (1 if moves > 0 else -1)
            col = mix(GREEN_C, RED_C, 0.6 + 0.4 * u)
            s = 1 + math.sin(u * math.pi) * 0.25
        else:
            x = cx + (SWAP[i] - 2) * SLOT
            s = 1.08 + 0.2 * max(0.0, spring(t - L_SNAP, 18, 7))
            col = WHITE if t - L_SNAP < 0.1 else HOT_C
            shadow = (110, 20, 30)
            if L_THE <= t < L_THE + 0.25:
                y = math.sin((t - L_THE) / 0.25 * math.pi) * 14  # (THE lands: everything jumps)
        paste_text(img, ch, x, TITLE_TOP + y - (s - 1) * 60, LETTER * s, fill=col, shadow=shadow, alpha=fade)
    # THE: drops from the top of the screen and SLAMS down, over the B
    if t >= L_THE - 0.18:
        u = min(1.0, (t - (L_THE - 0.18)) / 0.18)
        y = lerp(-300, TITLE_TOP - 135, u * u)
        sq = max(0.0, spring(t - L_THE, 16, 6)) if t >= L_THE else 0
        col = WHITE if L_THE <= t < L_THE + 0.08 else HOT_C
        paste_text(img, "THE", cx - 2 * SLOT + 0.5 * 6 * 12 + 30, y, 12 * (1 + 0.25 * sq), fill=col, shadow=(110, 20, 30),
                   alpha=fade)
    # the words under it
    if t < L_SHAKE:
        paste_text(img, "EASIEST BOSS EVER?", cx, TITLE_TOP + 225, 7, fill=WHITE, shadow=(30, 30, 60))
    elif t >= L_KING:
        paste_text(img, "THE CACTUS KING", cx, TITLE_TOP + 225, pop(t, L_KING, [3, 6, 9, 8, 8]), fill=(254, 174, 52),
                   shadow=(110, 20, 30), alpha=fade)


def bubble(img, pos, text, color, scale=6):
    """One of his word bubbles (BossClient's shout: black box, coloured edge, pixel words)."""
    ti = text_image(text, fill=color, outline=None, shadow=None)
    big = ti.resize((ti.width * scale, ti.height * scale), Image.NEAREST)
    pad = 18
    x0, y0 = int(pos[0] - big.width / 2 - pad), int(pos[1] - big.height / 2 - pad)
    d = ImageDraw.Draw(img)
    d.rectangle([x0 - 6, y0 - 6, x0 + big.width + 2 * pad + 6, y0 + big.height + 2 * pad + 6], fill=color)
    d.rectangle([x0, y0, x0 + big.width + 2 * pad, y0 + big.height + 2 * pad], fill=(0, 0, 0))
    img.paste(big, (x0 + pad, y0 + pad), big)


def sandstorm(img, t, strength):
    """The power-up's sandstorm (ArenaAmbience draws it in the game): a sandy
    haze and streaks of sand blowing across."""
    if strength <= 0:
        return img
    img = Image.blend(img, Image.new('RGB', img.size, (226, 190, 130)), 0.18 * strength)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(7)
    for i in range(70):
        y = rng.random() * OUT_H
        speed = 1400 + rng.random() * 1400
        length = 40 + rng.random() * 90
        x = (rng.random() * (OUT_W + 400) + t * speed) % (OUT_W + 400) - 200
        thick = 4 if rng.random() < 0.7 else 8
        col = (240, 212, 160) if i % 3 else (204, 166, 108)
        d.rectangle([x, y + (x * 0.12), x + length, y + (x * 0.12) + thick], fill=col)
    return img


_frozen = {}


def scene_image(index, t):
    """The 3D picture of frame `index` (the camera at time t), at full size."""
    fr = frames[index]
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts'] + puffs(fr['g'])
    eye, look, fov = shots(fr)
    jolt = shake(t) if t < FREEZE else np.zeros(3)
    img, to_screen = render(parts, eye + jolt, look + jolt * 0.6, fov)
    return img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGBA'), to_screen


def frame_near(t):
    return min(range(len(frames)), key=lambda i: abs(frames[i]['t'] - t))


def ending(t):
    """The freeze frame: the player blown off his spines, the picture darkens
    and creeps in, CAN YOU BEAT / THE BRUTE? slams on, then LIKE TO UNLOCK THE GAME!"""
    index = frame_near(FREEZE)
    if 'img' not in _frozen:
        im, to_screen = scene_image(index, FREEZE)
        im = im.convert('RGB')
        _frozen['img'] = im
    base = _frozen['img']
    u = t - FREEZE
    zoom = 1 + 0.06 * ease(u / 0.9)
    cw, ch = OUT_W / zoom, OUT_H / zoom
    box = (int((OUT_W - cw) / 2), int((OUT_H - ch) * 0.45), int((OUT_W - cw) / 2 + cw), int((OUT_H - ch) * 0.45 + ch))
    img = base.crop(box).resize((OUT_W, OUT_H), Image.NEAREST)
    grey = img.convert('L').convert('RGB')
    img = Image.blend(img, grey, 0.35 * min(1, u / 0.25))
    img = Image.blend(img, Image.new('RGB', img.size, (10, 8, 24)), 0.42 * min(1, u / 0.25))
    img = img.convert('RGBA')
    paste_text(img, "CAN YOU BEAT", OUT_W / 2, 120, pop(u, 0.08, [4, 9, 15, 14, 13]))
    paste_text(img, "THE BRUTE?", OUT_W / 2, 270, pop(u, 0.24, [6, 11, 18, 17, 16]), fill=HOT_C, shadow=(110, 20, 30))
    if u > 0.5:
        paste_text(img, "LIKE TO UNLOCK THE GAME!", OUT_W / 2, 452, 5, fill=WHITE, shadow=(30, 30, 60))
    img = img.convert('RGB')
    if u < 0.12:  # (a white snap as it freezes)
        img = Image.blend(img, Image.new('RGB', img.size, (255, 255, 255)), 0.7 * (1 - u / 0.12))
    return img


def frame_image(index):
    fr = frames[index]
    t = fr['t']
    if t >= FREEZE - 1e-6:
        return ending(t)
    img, to_screen = scene_image(index, t)
    # the power-up's sandstorm
    storm = 0.0
    if CUT_FLY <= t < CUT_ROAR:
        storm = min(1.0, (t - CUT_FLY) / 0.25) * (1.0 if t < CUT_CROWN else 0.6)
    if storm > 0:
        img = sandstorm(img.convert('RGB'), t, storm).convert('RGBA')
    # his word bubbles and the hint over him (the game's own)
    # (kept below the boss bar, and on the screen)
    for col, pos, text in fr['shouts']:
        s = to_screen(pos)
        if s and text.strip():
            x, y = s[0], s[1] - 40
            if y < 400:  # (no room over his head under the bar: beside it)
                x, y = s[0] - 260, max(400, s[1] + 60)
            bubble(img, (min(max(x, 160), OUT_W - 160), y), text, col)
    for col, pos, text in fr['hints']:
        s = to_screen(pos)
        if s and int(t * 6) % 2 == 0:
            x, y = s[0], s[1] - 60
            if y < 330:  # (no room over his head under the bar: beside it, in the sky)
                x, y = s[0] + 300, max(330, s[1] + 40)
            paste_text(img, text, min(max(x, 260), OUT_W - 260), y, 7, fill=col, shadow=(30, 30, 60))
    # the bar and his name
    if fr['bar'] and fr['state'] in ('Waking', 'Fighting', 'Transition'):
        name, share, phase = fr['bar']
        boss_bar(img, name, share, phase)
    title(img, t)
    # the punches landing
    for tt, extra in events.get('hit', []):
        if tt <= t < tt + 0.35 and shot_of(tt) == shot_of(t):
            w = int(extra[0])
            s = to_screen(np.array(extra[1:4]) + np.array([0, 1.2, 0]))
            if s is None:
                continue
            big = w >= 3
            word = "WHAM!" if big else "HIT!"
            paste_text(img, word, s[0], s[1] - 150 - (t - tt) * 220, pop(t, tt, [4, 10, 8]) * (1.5 if big else 1),
                       fill=YEL if big else WHITE, shadow=RED)
    img = img.convert('RGB')
    # white flashes: the big punches, THE slamming down, the slam, the blast
    flashes = [(tt, 0.3) for tt, extra in events.get('hit', []) if extra and extra[0] >= 3]
    flashes += [(L_THE, 0.55), (T_LAND, 0.7)]  # (the blast's flash is the freeze frame's white snap)
    for at, strength in flashes:
        if at <= t < at + 0.14:
            img = Image.blend(img, Image.new('RGB', img.size, (255, 255, 255)), strength * (1 - (t - at) / 0.14))
    return img


if __name__ == '__main__':
    import multiprocessing as mp
    if args.strip or args.sheet:
        default = (0.25, 0.8, 1.5, 2.3, 3.2, 4.4, 5.25, 6.1, 7.2, 8.5, 9.6) if args.strip else \
            (0.2, 1.6, 2.45, 3.3, 5.2, 6.15, 7.1, 8.6, 9.7)
        moments = [float(x) for x in args.at.split(',')] if args.at else default
        picks = [min(len(frames) - 1, int(round(x * FPS))) for x in moments]
        with mp.Pool(args.workers) as pool:
            imgs = pool.map(frame_image, picks)
        if args.sheet:
            tw, th, gap = 360, 640, 12
            cols = 3
            rows = (len(imgs) + cols - 1) // cols
            sheet = Image.new('RGB', (cols * (tw + gap) + gap, rows * (th + gap) + gap), (15, 15, 15))
            for i, im in enumerate(imgs):
                sheet.paste(im.resize((tw, th), Image.LANCZOS), (gap + (i % cols) * (tw + gap), gap + (i // cols) * (th + gap)))
            sheet.save(args.out)
        else:
            tw = args.thumb
            th_ = tw * 16 // 9
            thumbs = [im.resize((tw, th_), Image.LANCZOS) for im in imgs]
            strip = Image.new('RGB', (len(thumbs) * (tw + 10) + 10, th_ + 10), (15, 15, 15))
            for i, th in enumerate(thumbs):
                strip.paste(th, (10 + i * (tw + 10), 5))
            strip.save(args.out)
        print('saved', args.out)
        sys.exit(0)
    import imageio_ffmpeg
    # (crf 17: looks the same as the frames on flat pixel art, a few MB for 10 seconds)
    writer = imageio_ffmpeg.write_frames(args.out, (OUT_W, OUT_H), fps=FPS, quality=None, codec='libx264', macro_block_size=1,
                                         output_params=['-crf', '17', '-preset', 'slow', '-movflags', '+faststart'])
    writer.send(None)
    with mp.Pool(args.workers) as pool:
        for i, img in enumerate(pool.imap(frame_image, range(len(frames)), chunksize=2)):
            writer.send(np.asarray(img).tobytes())
            if i % 30 == 0:
                print('frame', i, flush=True)
    writer.close()
    print('saved', args.out)
