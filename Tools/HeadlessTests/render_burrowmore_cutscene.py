"""Films KNIGHT BURROWMORE's cutscene: every frame burrowmore_cutscene.luau
printed (the real Glimmer Dig, his real body and poses, the player), shot by
a moving camera - low and close as he yanks his shovel out of the dirt,
twirls it and strikes his pose (his name slams on), behind the player as he
leaps, from the side as the red circle chases them and he slams down, over
the shoulder for the punches while his shovel's stuck, behind him down the
lane of his Charge Dash, from the edge of the dig as he thunders at us and
crashes, over the shoulder again as he sees stars, up close as his armour
cracks (NO QUARTER!), low as he rockets up into the sky, and wide as his
meteor's shadow grows - with the boss bar, his name, hit pops, "HIT HIM!",
the game's particle bursts, flashes and camera shake on top. It ends on a
freeze frame as he plunges out of the sky: CAN YOU BEAT BURROWMORE?
1080 x 1920 (a YouTube Short), 30 frames a second.

    luau burrowmore_cutscene.luau > burrowmore.txt
    python3 render_burrowmore_cutscene.py burrowmore.txt ../../Docs/youtube/burrowmore_cutscene.mp4
    python3 render_burrowmore_cutscene.py burrowmore.txt sheet.png --sheet      (9 frames in a 3 x 3 contact sheet)
    python3 render_burrowmore_cutscene.py burrowmore.txt strip.png --strip --at 2.9,5.2   (just those moments)
    python3 render_burrowmore_cutscene.py burrowmore.txt thumb.png --poster --scale 1     (the Short's thumbnail)
    python3 render_burrowmore_cutscene.py burrowmore.txt pick.png --poster --variants --scale 2   (camera choices)

The drawing is render_cutscene.py's (flat colours lit by one sun, thin dark
edges: the game's 8-bit look), so it shows the game's real shapes and
colours, not Roblox's own lighting. Roblox draws particles itself; the
pretend Roblox can't, so the scene writes down every puff BossClient emits
(BURST) and they're drawn here as little blocks of dirt, sparks and gold.
"""
import json, math, os, sys, argparse
import numpy as np
from PIL import Image, ImageDraw

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, '..', '..', 'Docs', 'youtube'))
from pixel_art import text_image, INK, YEL, WHITE, RED  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('out')
ap.add_argument('--strip', action='store_true', help='just a strip of a few frames (a PNG)')
ap.add_argument('--sheet', action='store_true', help='a 3 x 3 contact sheet of frames across the film (a PNG)')
ap.add_argument('--at', default='', help='with --strip / --sheet: the moments to show (seconds, comma separated)')
ap.add_argument('--thumb', type=int, default=270, help='with --strip: how wide each frame is (pixels)')
ap.add_argument('--workers', type=int, default=4)
ap.add_argument('--scale', type=int, default=2, help='draw at 1/scale size, then blow up (chunkier, faster)')
ap.add_argument('--poster', action='store_true', help="the Short's thumbnail: a hero shot of him with his name (a PNG)")
ap.add_argument('--variants', action='store_true', help='with --poster: every camera choice side by side')
ap.add_argument('--pick', type=int, default=2, help='with --poster: which camera choice')
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
        cur = {'i': int(bits[1]), 't': float(bits[2]), 'g': float(bits[3]), 'parts': [], 'over': {}, 'aim': None, 'head': None}
        frames.append(cur)
        mode = 'frame'
    elif line.startswith('POS ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['boss'], cur['player'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('STATE ') and cur is not None:
        bits = line.split()
        cur['state'], cur['hp'], cur['action'], cur['phase'] = bits[1], float(bits[2]), bits[3], int(bits[4])
    elif line.startswith('BAR ') and cur is not None:
        name, share, phase = line[4:].rstrip('\n').split('|')
        cur['bar'] = (name.upper(), float(share), int(phase))
    elif line.startswith('AIM ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['aim'], cur['head'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('BURST '):
        b = [float(x) for x in line.split()[1:]]
        bursts.append({'g': b[0], 'pos': np.array(b[1:4]), 'col': (int(b[4]), int(b[5]), int(b[6])), 'n': int(b[7]),
                       'speed': (b[8], b[9]), 'size': (b[10], b[11]), 'life': (b[12], b[13]), 'spread': b[14],
                       'acc': b[15], 'drag': b[16]})
    elif line.startswith('EVENT '):
        bits = line.split()
        events.setdefault(bits[1], []).append((float(bits[2]), bits[3:]))
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
HOME = np.array([frames[0]['boss'][0], FLOOR, frames[0]['boss'][2]])  # the middle of the dig, where he knelt
for fr in frames:
    # (BossClient's shader warm-up: specks you can't see, in front of its own camera)
    fr['parts'] = [p for p in fr['parts'] if p['n'] != 'Warm']


def ev(name, k=0):
    return events[name][k][0]


def ev_vec(name, k=0, first=0):
    bits = events[name][k][1]
    return np.array([float(bits[first]), float(bits[first + 1]), float(bits[first + 2])])


def frame_at(t):
    return frames[min(range(len(frames)), key=lambda i: abs(frames[i]['t'] - t))]


print('scene:', len(static), 'arena parts,', len(frames), 'frames,', len(bursts), 'bursts')

# ----------------------------------------------------------------------
# the particles: each burst's puffs, the same every frame they're drawn
# (a Roblox ParticleEmitter: out along a cone round straight up, slowed by
# its Drag, pulled by its Acceleration, growing and fading over its life)
# ----------------------------------------------------------------------


def rotation(a, b, c):
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rx = np.array([[1, 0, 0], [0, ca, -sa], [0, sa, ca]])
    ry = np.array([[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]])
    rz = np.array([[cc, -sc, 0], [sc, cc, 0], [0, 0, 1]])
    return rx @ ry @ rz


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
            # (Roblox lights its puffs up a little - LightEmission - so they show against the dirt)
            col = [min(255, int(x * 1.12 + 28)) for x in b['col']]
            out.append({'n': 'Puff', 'c': 'Part', 's': [size, size, size], 'cf': cf, 'col': col, 'm': 'SmoothPlastic',
                        'sh': 'Block', 't': min(0.97, 0.25 + 0.72 * u * u)})
    return out


# ----------------------------------------------------------------------
# the drawing (render_cutscene.py's, with the dig's bright afternoon sky)
# ----------------------------------------------------------------------
LIGHT = np.array([-0.45, 0.8, 0.35])
LIGHT /= np.linalg.norm(LIGHT)
NEAR = 0.5
SKY_TOP, SKY_LOW = np.array([110, 165, 255], dtype=np.float32), np.array([200, 225, 255], dtype=np.float32)


def render(parts, eye, look, fov, rng_limit=360):
    w, h = W * SS, H * SS
    fwd = look - eye
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (h / 2) / math.tan(math.radians(fov) / 2)
    color = np.zeros((h, w, 3), dtype=np.float32)
    # the sky by how far up each row looks (bluest high up, pale at the horizon)
    rows = (h / 2 - (np.arange(h) + 0.5)) / f
    ys = fwd[1] + rows * up[1]
    flat_len = np.sqrt(np.maximum((fwd[0] + rows * up[0]) ** 2 + (fwd[2] + rows * up[2]) ** 2, 1e-9))
    elev = np.degrees(np.arctan2(ys, flat_len))
    k = np.clip(elev / 40.0, 0, 1)[:, None]
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


UP = V(0, 1, 0)


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


# the scene's own moments (seconds of film)
T_POSE = ev('pose')
CUT_DROP = ev('drop')
T_TAKEOFF, T_LOCK, T_LAND = ev('takeoff'), ev('lock'), ev('land')
LAND = ev_vec('land')
LAND[1] = FLOOR
CUT_CHASE = T_TAKEOFF + 0.3  # (he's well up: over to the side, for the circle chasing the player)
CUT_PUNCH = T_LAND + 0.2
HITS = [(tt, int(bits[0]), np.array([float(x) for x in bits[1:4]])) for tt, bits in events['hit']]
CUT_DASH = ev('dash')
T_COMMIT = ev('commit')
LANE_FROM, LANE_TO = ev_vec('commit', 0, 0), ev_vec('commit', 0, 3)
LANE_FROM[1] = LANE_TO[1] = FLOOR
LANE_DIR = unit(flat(LANE_TO - LANE_FROM))
LANE_SIDE = np.cross(LANE_DIR, UP)  # (the side of the lane away from where the player rolls)
T_GO = ev('go')
CUT_CHARGE = T_GO - 0.1
T_CRASH = ev('crash')
CUT_DIZZY = T_CRASH + 0.22
T_BREAK = ev('break')
CUT_CRACK = T_BREAK + 0.1
T_PLATES = ev('plates')
CUT_METEOR = ev('meteor')
T_LAUNCH = ev('launch')
CUT_SKY = ev('sky')
CUT_SLOW = ev('slow')
SKY_OUT = unit(V(float(events['sky'][0][1][0]), 0, float(events['sky'][0][1][1])))
FREEZE = ev('freeze')
CUTS = [0.0, CUT_DROP, CUT_CHASE, CUT_PUNCH, CUT_DASH, CUT_CHARGE, CUT_DIZZY, CUT_CRACK, CUT_METEOR, CUT_SKY, CUT_SLOW, FREEZE]
# where the player stands for each set of punches (so those cameras hold still)
PUNCH1 = flat(frame_at(HITS[0][0])['player']) + V(0, FLOOR, 0)
PUNCH2 = flat(frame_at(HITS[3][0])['player']) + V(0, FLOOR, 0)
FACE2 = unit(flat(PUNCH2 - LANE_TO))  # (which way he faces, dazed, after the crash)
PSTART = flat(frames[0]['player']) + V(0, FLOOR, 0)  # (where the player watches him wake)


def body_point(fr, name):
    """Where one of his body's parts is drawn in this frame (exactly: the
    game's own aim point is smoothed, and trails him in a fast fall)."""
    for p in fr['parts']:
        if p['n'] == name:
            return np.array(p['cf'][0:3])
    return None


def shot_of(t):
    """Which shot the film is in at time t (effects don't carry over a cut)."""
    return max(i for i, c in enumerate(CUTS) if c <= t + 1e-6)


def shots(fr):
    """Where the camera is and what it looks at in frame `fr`, and its lens."""
    t = fr['t']
    B, P = fr['boss'], fr['player']
    b = V(B[0], FLOOR, B[2])
    head = fr['head'] if fr['head'] is not None else b + V(0, 15, 0)
    if t < CUT_DROP:  # 1) low and close in front of him: the yank, the twirl, the pose
        k = ease(t / CUT_DROP)
        eye = HOME + V(8.2, 3.0, 24.5) + V(-1.4, 0.4, -3.0) * k
        look = HOME + V(0.4, 10.4, 0)
        return eye, look, 56
    if t < CUT_CHASE:  # 2) low behind the player: he crouches... and leaps into the sky
        eye = PSTART + V(-2.0, 3.0, 15.0)
        look = V(HOME[0] + 4.0, max(9.0, head[1] - 4.0), HOME[2])
        return eye, look, 60
    if t < CUT_PUNCH:  # 3) from the side, a little above: the circle chasing the player, the roll, the slam
        k = ease((t - CUT_CHASE) / (CUT_PUNCH - CUT_CHASE))
        eye = HOME + V(17, 15, 66) + V(0, -1.5, -3) * k
        look = HOME + V(16.5, 9.5, 22)
        return eye, look, 62
    if t < CUT_DASH:  # 4) over the player's shoulder: HIT HIM! - three punches while his shovel's stuck
        k = ease((t - CUT_PUNCH) / (CUT_DASH - CUT_PUNCH))
        to_b = unit(flat(LAND - PUNCH1))
        side = np.cross(to_b, UP)
        eye = PUNCH1 - to_b * (15.5 - 1.5 * k) + side * 5.5 + V(0, 7.0, 0)
        look = LAND + V(0, 8.2, 0) - to_b * 2
        return eye, look, 60
    if t < CUT_CHARGE:  # 5) behind him, down the lane: he scrapes his shovel, the lane locks on
        k = ease((t - CUT_DASH) / (CUT_CHARGE - CUT_DASH))
        eye = LANE_FROM - LANE_DIR * (26 - 2 * k) + LANE_SIDE * 6 + V(0, 15, 0)
        look = LANE_FROM + LANE_DIR * 20 + V(0, 2.0, 0)
        return eye, look, 60
    if t < CUT_DIZZY:  # 6) from the edge of the dig: he thunders straight at us - and crashes
        eye = LANE_TO + LANE_DIR * 19 + LANE_SIDE * 3.5 + V(0, 12.5, 0)
        look = b + V(0, 5.5, 0)
        return eye, look, 60
    if t < CUT_CRACK:  # 7) over the player's shoulder: he's seeing stars - more punches
        k = ease((t - CUT_DIZZY) / (CUT_CRACK - CUT_DIZZY))
        to_b = unit(flat(LANE_TO - PUNCH2))
        side = np.cross(to_b, UP)
        eye = PUNCH2 - to_b * (15.5 - 1.5 * k) + side * 5.5 + V(0, 7.0, 0)
        look = LANE_TO + V(0, 8.2, 0) - to_b * 2
        return eye, look, 60
    if t < CUT_METEOR:  # 8) up close, low: NO QUARTER! his armour cracks, the plates fly off
        k = ease((t - CUT_CRACK) / (CUT_METEOR - CUT_CRACK))
        side = np.cross(FACE2, UP)
        eye = LANE_TO + FACE2 * (20.5 - 2 * k) + side * 9 + V(0, 2.8, 0)
        look = LANE_TO + V(0, 9.5, 0) + FACE2 * 1.5
        return eye, look, 56
    if t < CUT_SKY:  # 9) low in front of him: a deep crouch, and he rockets up out of sight
        side = np.cross(FACE2, UP)
        eye = LANE_TO + FACE2 * 21 - side * 7 + V(0, 1.8, 0)
        up_k = ease((t - T_LAUNCH) / 0.2)
        look = LANE_TO + V(0, 9 + 22 * up_k, 0)
        return eye, look, 62
    if t < CUT_SLOW:  # 10) wide, from outside the shadow: it grows, the player races for its edge
        k = ease((t - CUT_SKY) / max(CUT_SLOW - CUT_SKY, 0.1))
        eye = HOME + SKY_OUT * (63 - 2 * k) + V(0, 12, 0)
        low = HOME + SKY_OUT * 37 + V(0, -1.0, 0)
        high = HOME + V(0, 40, 0)
        look, fov = frame_both(eye, low, high, fov_min=56, margin=4)
        return eye, look, fov
    # 11) slow motion, low behind where the player's running to: the camera
    # tilts down with him as he plunges out of the sky like a meteor, fire
    # trailing, onto the shadow the player's racing out of (the freeze)
    tt = min(t, FREEZE)
    k = (tt - CUT_SLOW) / max(FREEZE - CUT_SLOW, 0.1)
    across = np.cross(SKY_OUT, UP)
    eye = HOME + SKY_OUT * (56 - 1.5 * k) + across * 5 + V(0, 4.5, 0)
    in_dir = unit(flat(HOME - eye))
    # (aimed so the middle of him sits a little above the middle of the picture,
    # under the boss bar - never lower than the last framing, player and all)
    aim = body_point(fr, 'Chest')
    if aim is None:
        aim = HOME + V(0, 30, 0)
    d = aim - eye
    aim_elev = math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
    elev = min(50.0, max(10.0, aim_elev - 9.8))
    look = eye + in_dir * 10 + V(0, 10 * math.tan(math.radians(elev)), 0)
    return eye, look, 60


# camera shake: (when, how hard, how long)
SHAKES = []
for tt, w, _ in HITS:
    SHAKES.append((tt, (0.18, 0.24, 0.45)[w - 1], 0.15 + 0.05 * w))
SHAKES += [(T_POSE + 0.03, 0.6, 0.35), (T_LAND, 1.5, 0.5), (T_GO, 0.35, 0.2), (T_CRASH, 1.3, 0.45),
           (T_PLATES, 1.2, 0.6), (T_LAUNCH, 0.9, 0.4)]


def shake(t):
    amp = 0.0
    for at, strength, length in SHAKES:
        if at <= t < at + length:
            amp = max(amp, strength * (1 - (t - at) / length))
    if CUT_SKY <= t < FREEZE:  # (the ground rumbling as he comes)
        amp = max(amp, 0.15 + 0.35 * (t - CUT_SKY) / max(FREEZE - CUT_SKY, 0.1))
    if amp <= 0:
        return np.zeros(3)
    r = np.random.default_rng(int(t * 1000))
    return (r.random(3) - 0.5) * 2 * amp


# ----------------------------------------------------------------------
# on top: the boss bar, the words, pops and flashes
# ----------------------------------------------------------------------
GOLD = (254, 174, 52)
CYAN = (44, 232, 245)
DEEP_BLUE = (18, 78, 137)


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


def boss_bar(img, name, hp, flash=0.0):
    d = ImageDraw.Draw(img)
    bw, x0, y0 = 860, (OUT_W - 860) // 2, 210
    label = text_image(name, fill=WHITE, shadow=None)
    label = label.resize((label.width * 5, label.height * 5), Image.NEAREST)
    img.paste(label, (x0, y0 - 58), label)
    share = max(0.0, min(1.0, hp))
    fill, light = (200, 36, 44), (240, 90, 90)
    if flash > 0:
        fill = tuple(int(lerp(c, 255, flash)) for c in fill)
        light = tuple(int(lerp(c, 255, flash)) for c in light)
    d.rectangle([x0 - 6, y0 - 6, x0 + bw + 6, y0 + 34], fill=INK)
    d.rectangle([x0, y0, x0 + bw, y0 + 28], fill=(40, 16, 22))
    if share > 0:
        d.rectangle([x0, y0, x0 + int(bw * share), y0 + 28], fill=fill)
        d.rectangle([x0, y0, x0 + int(bw * share), y0 + 6], fill=light)


def title(img, t):
    """His name, over the wake-up: KNIGHT... BURROWMORE slams on with his pose,
    THE HONOURABLE DIGGER under it."""
    if t >= CUT_DROP:
        return
    fade = 1 - max(0.0, min(1.0, (t - (CUT_DROP - 0.15)) / 0.15))
    cx = OUT_W / 2
    top = 1150
    paste_text(img, "KNIGHT", cx, top + 4 * math.sin(t * 9), 10, fill=WHITE, shadow=(30, 30, 60), alpha=fade)
    if t >= T_POSE:
        jolt = 12 * math.exp(-(t - T_POSE) * 9) * math.sin((t - T_POSE) * 40)
        col = WHITE if t - T_POSE < 0.07 else YEL
        paste_text(img, "BURROWMORE", cx + jolt, top + 125, pop(t, T_POSE, [7, 13, 17, 15, 15]), fill=col, shadow=DEEP_BLUE,
                   alpha=fade)
    if t >= T_POSE + 0.18:
        paste_text(img, "THE HONOURABLE DIGGER", cx, top + 275, 5, fill=GOLD, shadow=(30, 30, 60), alpha=fade)


def no_quarter(img, t):
    """NO QUARTER! slamming on as his shoulder plates fly off."""
    if not (T_PLATES <= t < CUT_METEOR):
        return
    u = t - T_PLATES
    fade = 1 - max(0.0, min(1.0, (t - (CUT_METEOR - 0.12)) / 0.12))
    jx = 10 * math.exp(-u * 7) * math.sin(u * 45)
    col = WHITE if u < 0.07 else GOLD
    paste_text(img, "NO", OUT_W / 2 + jx, 1120, pop(u, 0, [8, 16, 22, 19, 18]), fill=col, shadow=(110, 20, 30), alpha=fade)
    if u >= 0.1:
        paste_text(img, "QUARTER!", OUT_W / 2 - jx, 1290, pop(u, 0.1, [8, 16, 20, 18, 17]), fill=col if u > 0.17 else WHITE,
                   shadow=(110, 20, 30), alpha=fade)


def hint(img, fr, to_screen, t):
    """HIT HIM! flashing over his head while he's open (the stuck shovel, the stars)."""
    windows = [(T_LAND + 0.12, HITS[0][0]), (T_CRASH + 0.25, HITS[3][0])]
    if not any(a <= t < b for a, b in windows):
        return
    if int(t * 7) % 2:
        return
    head = fr['head'] if fr['head'] is not None else fr['boss'] + V(0, 15, 0)
    s = to_screen(head + V(0, 2.5, 0))
    if s is None:
        return
    y = max(300, s[1] - 110)
    paste_text(img, "HIT HIM!", min(max(s[0], 280), OUT_W - 280), y, 8, fill=YEL, shadow=(30, 30, 60))


def run_hint(img, fr, to_screen, t):
    """RUN! flashing over the player as the meteor's shadow grows round them."""
    if not (CUT_SKY + 0.08 <= t < CUT_SLOW) or int(t * 7) % 2:
        return
    s = to_screen(fr['player'] + V(0, 3.2, 0))
    if s is None:
        return
    paste_text(img, "RUN!", min(max(s[0], 200), OUT_W - 200), max(300, s[1] - 120), 9, fill=WHITE, shadow=RED)


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
    """The freeze frame: he's plunging out of the sky, the player racing the
    shadow - the picture darkens and creeps in, CAN YOU BEAT / BURROWMORE?
    slams on, then LIKE TO UNLOCK THE GAME!"""
    index = frame_near(FREEZE)
    if 'img' not in _frozen:
        im, _ = scene_image(index, FREEZE)
        fr = frames[index]
        if fr['bar']:
            boss_bar(im, fr['bar'][0], fr['bar'][1])
        _frozen['img'] = im.convert('RGB')
    base = _frozen['img']
    u = t - FREEZE
    zoom = 1 + 0.06 * ease(u / 0.9)
    cw, ch = OUT_W / zoom, OUT_H / zoom
    box = (int((OUT_W - cw) / 2), int((OUT_H - ch) * 0.5), int((OUT_W - cw) / 2 + cw), int((OUT_H - ch) * 0.5 + ch))
    img = base.crop(box).resize((OUT_W, OUT_H), Image.NEAREST)
    grey = img.convert('L').convert('RGB')
    img = Image.blend(img, grey, 0.35 * min(1, u / 0.25))
    img = Image.blend(img, Image.new('RGB', img.size, (10, 8, 24)), 0.42 * min(1, u / 0.25))
    img = img.convert('RGBA')
    paste_text(img, "CAN YOU BEAT", OUT_W / 2, 850, pop(u, 0.08, [4, 9, 13, 12, 12]))
    paste_text(img, "BURROWMORE?", OUT_W / 2, 995, pop(u, 0.24, [6, 11, 15, 14, 14]), fill=CYAN, shadow=DEEP_BLUE)
    if u > 0.5:
        paste_text(img, "LIKE TO UNLOCK THE GAME!", OUT_W / 2, 1165, 5, fill=WHITE, shadow=(30, 30, 60))
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
    hint(img, fr, to_screen, t)
    run_hint(img, fr, to_screen, t)
    # the bar and his name
    if fr['bar'] and fr['state'] in ('Waking', 'Fighting', 'Transition'):
        name, share, phase = fr['bar']
        flash = max(0.0, 1 - (t - T_PLATES) / 0.25) if t >= T_PLATES else 0.0
        boss_bar(img, name, share, flash)
    title(img, t)
    no_quarter(img, t)
    # the punches landing
    for tt, w, fist in HITS:
        if tt <= t < tt + 0.35 and shot_of(tt) == shot_of(t):
            s = to_screen(fist + np.array([0, 1.2, 0]))
            if s is None:
                continue
            big = w >= 3
            word = "WHAM!" if big else "HIT!"
            paste_text(img, word, s[0], s[1] - 150 - (t - tt) * 220, pop(t, tt, [4, 10, 8]) * (1.5 if big else 1),
                       fill=YEL if big else WHITE, shadow=RED)
    img = img.convert('RGB')
    # white flashes: the big punches, the slam, the crash, the armour bursting, the launch
    flashes = [(tt, 0.3) for tt, w, _ in HITS if w >= 3]
    flashes += [(T_LAND, 0.6), (T_CRASH, 0.5), (T_PLATES, 0.65), (T_LAUNCH, 0.3)]
    for at, strength in flashes:
        if at <= t < at + 0.14:
            img = Image.blend(img, Image.new('RGB', img.size, (255, 255, 255)), strength * (1 - (t - at) / 0.14))
    return img


# THE THUMBNAIL (like Oozark's): a close hero shot of him in his pose - low,
# looking up at his helmet and glowing eyes, the shovel raised - the boss bar
# on top and his name big in the lower third.
POSTER_CAMS = [  # (the camera, and where it looks, from his face: across, up, out; lens)
    ((3.5, -2.5, 17.5), (-1.5, -0.5, 0), 60),
    ((6.0, -1.5, 18.0), (-1.2, -0.8, 0), 58),
    ((2.5, -3.5, 16.0), (-1.2, -0.2, 0), 64),
    ((4.5, -2.0, 20.0), (-1.5, -1.0, 0), 54),
]


def poster_image(pick):
    t = T_POSE + 0.45
    index = frame_near(t)
    fr = frames[index]
    # (no particle puffs: on a still picture they read as smudges)
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts']
    # his face: between his glowing eyes (his parts near him - never the player's)
    B = fr['boss']
    eyes = [np.array(p['cf'][0:3]) for p in fr['parts'] if p['n'] == 'Eye' and np.linalg.norm(np.array(p['cf'][0:3]) - B) < 20]
    face = np.mean(eyes, axis=0) if eyes else V(B[0], FLOOR + 11, B[2])
    (ex, ey, ez), (lx, ly, lz), fov = POSTER_CAMS[pick]
    eye1, _, _ = shots(fr)
    toward = unit(flat(eye1 - face))  # (the way he faces the opening shot's camera)
    side = np.cross(UP, toward)
    eye = face + toward * ez + side * ex + V(0, ey, 0)
    look = face + toward * lz + side * lx + V(0, ly, 0)
    img, _ = render(parts, eye, look, fov)
    img = img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGB')
    # a dark fade up from the bottom, so his name stands out
    shade = Image.new('L', (OUT_W, OUT_H), 0)
    ds = ImageDraw.Draw(shade)
    for y in range(1260, OUT_H):
        ds.line([(0, y), (OUT_W, y)], fill=int(175 * min(1, (y - 1260) / 480)))
    img = Image.composite(Image.new('RGB', img.size, (10, 8, 24)), img, shade).convert('RGBA')
    if fr['bar']:
        boss_bar(img, fr['bar'][0], 1.0)
    cx = OUT_W / 2
    paste_text(img, "KNIGHT", cx, 1395, 10, fill=WHITE, shadow=(30, 30, 60))
    paste_text(img, "BURROWMORE", cx, 1520, 14, fill=YEL, shadow=DEEP_BLUE)
    paste_text(img, "THE HONOURABLE DIGGER", cx, 1672, 5.5, fill=GOLD, shadow=(30, 30, 60))
    return img.convert('RGB')


if __name__ == '__main__':
    import multiprocessing as mp
    if args.poster:
        if args.variants:
            with mp.Pool(args.workers) as pool:
                imgs = pool.map(poster_image, range(len(POSTER_CAMS)))
            tw, th, gap = 360, 640, 12
            sheet = Image.new('RGB', (len(imgs) * (tw + gap) + gap, th + 2 * gap), (15, 15, 15))
            for i, im in enumerate(imgs):
                sheet.paste(im.resize((tw, th), Image.LANCZOS), (gap + i * (tw + gap), gap))
            sheet.save(args.out)
        else:
            poster_image(args.pick).save(args.out)
        print('saved', args.out)
        sys.exit(0)
    if args.strip or args.sheet:
        default = (0.3, 1.1, 2.2, 2.95, 3.9, 4.9, 5.9, 6.9, 7.8, 8.8, 9.7, 10.6) if args.strip else \
            (0.3, 1.2, 2.2, 3.05, 3.95, 5.1, 5.95, 6.75, 7.75)
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
    # (crf 17: looks the same as the frames on flat pixel art, a few MB for 11 seconds)
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
