"""Films KING GAVELGRUNT's BIG GULP: every frame gavelgrunt_cutscene.luau
printed (the real Throne Summit, his real body and poses, the player), shot
by a moving camera - dragged along just in front of the player as they run
for it and the wind hauls them back, tilting up as they're lifted into his
mouth; up close on his face as he chews (GULP! CHOMP); and back on the
player's spot as he spits them out at us (PTOO!) and the BURP flings them the
rest of the way in slow motion, face first along the floor - the stars, and
the look back as he opens his mouth again (NOT AGAIN!) - with the hook on
top the whole way (THE FINAL BOSS ATE ME), pops, flashes and camera shake.
It LOOPS: the last frame runs straight into the first. And the game's own
sound effects, mixed in quietly under whatever music goes on top (they wrap
round the loop too). 1080 x 1920 (a YouTube Short), 30 frames a second.

    luau gavelgrunt_cutscene.luau > gulp.txt
    python3 render_gavelgrunt_cutscene.py gulp.txt ../../Docs/youtube/gavelgrunt_gulp.mp4
    python3 render_gavelgrunt_cutscene.py gulp.txt sheet.png --sheet     (9 frames in a 3 x 3 contact sheet)
    python3 render_gavelgrunt_cutscene.py gulp.txt strip.png --strip --at 0.5,1.6   (just those moments)
    python3 render_gavelgrunt_cutscene.py gulp.txt seam.png --seam       (the last frames and the first: the loop)
    python3 render_gavelgrunt_cutscene.py gulp.txt thumb.png --poster    (the Short's thumbnail)
    python3 render_gavelgrunt_cutscene.py gulp.txt sound.wav --sound     (just the sound effects)

The drawing is render_cutscene.py's (flat colours lit by one sun, thin dark
edges: the game's 8-bit look), under the summit's storm-grey sky. Roblox
draws particles itself; the pretend Roblox can't, so the scene writes down
every puff BossClient emits (BURST) and they're drawn here as little blocks.
The sounds are Tools/Sounds/out/bosses' (the ones uploaded for the game:
Big Inhale, Gulp, Munching, Spit Out, Royal Burp) plus a few soft ones made
here (the wind, a whoosh, a thud, a scrape, the dizzy twinkle).
"""
import json, math, os, sys, argparse, wave, subprocess, tempfile
import numpy as np
from PIL import Image, ImageDraw

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, '..', '..', 'Docs', 'youtube'))
from pixel_art import text_image, INK, YEL, WHITE, RED, GREEN  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('out')
ap.add_argument('--strip', action='store_true', help='just a strip of a few frames (a PNG)')
ap.add_argument('--sheet', action='store_true', help='a 3 x 3 contact sheet of frames across the film (a PNG)')
ap.add_argument('--seam', action='store_true', help='the last few frames and the first few, in a row (a PNG): the loop')
ap.add_argument('--at', default='', help='with --strip / --sheet: the moments to show (seconds, comma separated)')
ap.add_argument('--thumb', type=int, default=270, help='with --strip / --seam: how wide each frame is (pixels)')
ap.add_argument('--workers', type=int, default=4)
ap.add_argument('--scale', type=int, default=2, help='draw at 1/scale size, then blow up (chunkier, faster)')
ap.add_argument('--poster', action='store_true', help="the Short's thumbnail (a PNG)")
ap.add_argument('--sound', action='store_true', help='just the sound effects (a WAV)')
ap.add_argument('--silent', action='store_true', help='the video without the sound effects')
args = ap.parse_args()

OUT_W, OUT_H, FPS = 1080, 1920, 30
W, H = OUT_W // args.scale, OUT_H // args.scale
SS = 2
RATE = 44100

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
        cur = {'i': int(bits[1]), 't': float(bits[2]), 'g': float(bits[3]), 'c': float(bits[4]), 'parts': [], 'over': {},
               'aim': None, 'head': None, 'mouth': None, 'bar': None, 'state': None}
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
    elif line.startswith('MOUTH ') and cur is not None:
        cur['mouth'] = np.array([float(x) for x in line.split()[1:4]])
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
for fr in frames:
    # (BossClient's shader warm-up: specks you can't see, in front of its own camera)
    fr['parts'] = [p for p in fr['parts'] if p['n'] != 'Warm']


def ev(name, k=0):
    return events[name][k][0]


def ev_nums(name, k=0):
    return [float(x) for x in events[name][k][1]]


N_FRAMES, G, LOOP_AT, SLOW_RATE = ev_nums('loop')
N_FRAMES = int(N_FRAMES)
PULL0, LIFT, GULP, SPIT, BURP, LAND, REST, UP0, UP1, LOOK0, LOOK1 = ev_nums('times')
st = ev_nums('stage')
HOME = np.array(st[0:3])
D_REST, D_LIFT, D_LAND, BOSS_SIZE = st[3:7]
FLOOR = HOME[1]
SLOW_FROM = ev_nums('slow')[0]
SLOW_TO = ev_nums('fast')[0]
LENGTH = N_FRAMES / FPS
assert len(frames) == N_FRAMES, (len(frames), N_FRAMES)
print('scene:', len(static), 'arena parts,', len(frames), 'frames,', len(bursts), 'bursts,', '%.2f s' % LENGTH)


def film_time(c):
    """When cycle time c is on screen (seconds of film): the inverse of the
    scene's clock, slow motion and all. A moment before the loop point (the
    first Big Gulp's start, off screen) is the same moment of the second one."""
    if c < LOOP_AT - 1e-9:
        c += G
    if c < SLOW_FROM:
        return c - LOOP_AT
    if c < SLOW_TO:
        return (SLOW_FROM - LOOP_AT) + (c - SLOW_FROM) / SLOW_RATE
    return (SLOW_FROM - LOOP_AT) + (SLOW_TO - SLOW_FROM) / SLOW_RATE + (c - SLOW_TO)


def cyc(fr):
    return fr['c']


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
            # (Roblox lights its puffs up a little - LightEmission - so they show)
            col = [min(255, int(x * 1.12 + 28)) for x in b['col']]
            out.append({'n': 'Puff', 'c': 'Part', 's': [size, size, size], 'cf': cf, 'col': col, 'm': 'SmoothPlastic',
                        'sh': 'Block', 't': min(0.97, 0.25 + 0.72 * u * u)})
    return out


# ----------------------------------------------------------------------
# the drawing (render_cutscene.py's, under the summit's storm)
# ----------------------------------------------------------------------
LIGHT = np.array([-0.45, 0.8, 0.35])
LIGHT /= np.linalg.norm(LIGHT)
NEAR = 0.5
SKY_TOP, SKY_LOW = np.array([58, 66, 98], dtype=np.float32), np.array([139, 155, 180], dtype=np.float32)


def render(parts, eye, look, fov, rng_limit=360):
    w, h = W * SS, H * SS
    fwd = look - eye
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (h / 2) / math.tan(math.radians(fov) / 2)
    color = np.zeros((h, w, 3), dtype=np.float32)
    # the sky by how far up each row looks (darkest high up, pale at the horizon)
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
# the camera
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


def along(d, y=0.0, x=0.0):
    """A spot on the line straight out in front of him: d studs south of his
    middle, y up off the floor, x across (east)."""
    return V(HOME[0] + x, FLOOR + y, HOME[2] + d)


def cycle_u(c):
    """Seconds into whichever Big Gulp is on (the second begins at G)."""
    return c - G if c >= G else c


def drag_d(u):
    """Where the wind has dragged the player to, u seconds into a Big Gulp
    (the scene's own sum)."""
    k = min(1.0, max(0.0, (u - PULL0) / (LIFT - PULL0)))
    return D_REST - (D_REST - D_LIFT) * k ** 2.2


def pitch_look(eye, pitch, toward=None, yaw_off=0.0):
    """A point to look at: along the floor toward `toward` (his middle), turned
    `yaw_off` degrees, tipped up `pitch` degrees."""
    d = unit(flat((toward if toward is not None else HOME) - eye))
    if yaw_off:
        a = math.radians(yaw_off)
        d = V(d[0] * math.cos(a) - d[2] * math.sin(a), 0, d[0] * math.sin(a) + d[2] * math.cos(a))
    return eye + d * 10 + V(0, 10 * math.tan(math.radians(pitch)), 0)


def elev_to(eye, pt):
    d = pt - eye
    return math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))


# shot A, "THE DRAG": the camera just in front of the player (they're running
# straight at us), dragged in with them as the wind hauls them back - so he
# looms bigger and bigger. It holds when their feet leave the floor and tips
# up after them into his mouth. The same framing, held still, for the spit
# (they come flying out of his mouth straight at us), the burp (a punch in,
# and slow motion as it flings them) and the landing - so where the film ends
# is where it starts.
A_BACK, A_HIGH, A_ACROSS, A_FOV, A_PITCH = 24.0, 8.0, 3.0, 80.0, 7.0
A_FOLLOW = 0.6  # (how much of the player's drag the camera goes along with)
# shot B, "THE FACE": close on his face, at eye level, off to one side: the
# gulp and the chewing (cheeks full), until he spits
B_EYE = (12.0, 38.0, 64.0)  # (across, up, out in front of him)
B_LOOK = (0.0, 35.5, 8.0)
B_FOV = 46.0
CUT_FACE = GULP + 0.1  # (a moment on the gulp itself, then the close-up)


def shot(fr):
    """Where the camera is, what it looks at and its lens in frame `fr`."""
    c = cyc(fr)
    if CUT_FACE <= c < SPIT:
        # THE FACE: pushing in slowly as he chews
        k = ease((c - CUT_FACE) / (SPIT - CUT_FACE))
        ex, ey, ez = B_EYE
        eye = along(ez - 7.0 * k, ey, ex - 1.5 * k)
        look = along(B_LOOK[2], B_LOOK[1], B_LOOK[0])
        return eye, look, B_FOV
    u = cycle_u(c)
    if SPIT <= c < G:
        d = D_REST  # (held still: the spit at us, the burp, the landing, getting up)
    elif u < LIFT:
        d = drag_d(u)
    else:
        d = D_LIFT
    eye = along(D_REST + A_BACK - A_FOLLOW * (D_REST - d), A_HIGH, A_ACROSS)
    pitch = A_PITCH
    if LIFT <= c < CUT_FACE:
        # (tipping up after them, into his mouth)
        k = ease((c - LIFT) / (GULP - LIFT))
        m = fr['mouth'] if fr['mouth'] is not None else along(7, 34)
        pitch = lerp(A_PITCH, elev_to(eye, m) - 8.0, k)
    look = pitch_look(eye, pitch, along(0, 0, 0))
    fov = A_FOV
    if BURP <= c < BURP + 0.9:
        # (a punch in on the burp, easing back out)
        t = c - BURP
        fov -= 9.0 * (t / 0.06 if t < 0.06 else math.exp(-(t - 0.06) * 5.0))
    return eye, look, fov


# camera shake: (when, how hard, how long) - in cycle time (so it slows down
# with the slow motion, like everything else in the picture)
SHAKES = [(GULP, 0.25, 0.25), (SPIT, 0.3, 0.2), (BURP, 1.1, 0.5), (LAND, 0.5, 0.3)]


def shake(c):
    amp = 0.0
    for at, strength, length in SHAKES:
        if at <= c < at + length:
            amp = max(amp, strength * (1 - (c - at) / length))
    u = cycle_u(c)
    if PULL0 <= u < GULP:  # (the wind rumbling)
        amp = max(amp, 0.05 + 0.1 * (u - PULL0) / (GULP - PULL0))
    if amp <= 0:
        return np.zeros(3)
    r = np.random.default_rng(int(round(c * 1200)))
    return (r.random(3) - 0.5) * 2 * amp


# ----------------------------------------------------------------------
# on top: the hook, the words, flashes
# ----------------------------------------------------------------------
BURP_GREEN = (150, 230, 80)
SKULL = [" ### ", "#####", "# # #", "#####", "## ##", " ### ", " # # "]


def pop(t, start, steps):
    if t < start:
        return 0
    return steps[min(int((t - start) * FPS), len(steps) - 1)]


def glyph_image(rows, fill, shadow=(160, 80, 40)):
    """One 5 x 7 picture (the skull) drawn like the letters: outline, shadow."""
    import pixel_art
    pixel_art.FONT['@'] = rows
    return text_image('@', fill=fill, shadow=shadow)


def paste_img(img, pic, cx, top, scale, alpha=1.0):
    if scale <= 0 or alpha <= 0:
        return 0
    big = pic.resize((max(1, int(pic.width * scale)), max(1, int(pic.height * scale))), Image.NEAREST)
    if alpha < 1:
        a = big.getchannel('A').point(lambda v: int(v * alpha))
        big.putalpha(a)
    img.paste(big, (int(cx - big.width / 2), int(top)), big)
    return big.width


def paste_text(img, words, cx, top, scale, fill=YEL, shadow=(160, 80, 40), alpha=1.0):
    return paste_img(img, text_image(words, fill=fill, shadow=shadow), cx, top, scale, alpha)


CAP_TOP = 100
WORDS_TOP = 360  # (nothing else goes above this: the hook's there)


_band = {}


def top_band():
    """A dark fade down from the top of the picture, behind the hook."""
    if 'img' not in _band:
        a = np.zeros((OUT_H, OUT_W), dtype=np.uint8)
        for y in range(0, 470):
            a[y, :] = int(170 * (1 - y / 470) ** 1.3)
        band = Image.new('RGBA', (OUT_W, OUT_H), (12, 10, 26, 0))
        band.putalpha(Image.fromarray(a))
        _band['img'] = band
    return _band['img']


def hook(img):
    """THE FINAL BOSS / ATE ME (and a skull): on top the whole way, so it's the
    first thing you read - and it's there on every loop."""
    img.alpha_composite(top_band())
    cx = OUT_W / 2
    paste_text(img, "THE FINAL BOSS", cx, CAP_TOP, 8, fill=WHITE, shadow=(30, 30, 60))
    words = text_image("ATE ME", fill=YEL, shadow=(150, 40, 40))
    skull = glyph_image(SKULL, WHITE, shadow=(150, 40, 40))
    s = 14
    gap = 3
    total = (words.width + gap + skull.width) * s
    x0 = cx - total / 2
    paste_img(img, words, x0 + words.width * s / 2, CAP_TOP + 86, s)
    paste_img(img, skull, x0 + (words.width + gap) * s + skull.width * s / 2, CAP_TOP + 86, s)


def clamp_x(x, margin):
    return min(max(x, margin), OUT_W - margin)


def words_on_top(img, fr, to_screen, c):
    """The pops: HELP! over the player being dragged and lifted, GULP!, CHOMP,
    PTOO!, the BUUURP, and NOT AGAIN! as they look back at his open mouth."""
    u = cycle_u(c)
    P = fr['player']
    # HELP! (flashing over them as they're dragged in and lifted)
    if 1.35 <= u < GULP - 0.05 and c < G + GULP and int(c * 8) % 2 == 0:
        s = to_screen(P + V(0, 3.4, 0))
        if s is not None:
            paste_text(img, "HELP!", clamp_x(s[0], 220), max(WORDS_TOP, s[1] - 120), 9, fill=WHITE, shadow=RED)
    m = fr['mouth'] if fr['mouth'] is not None else along(8, 32)
    if GULP <= c < CUT_FACE + 0.45:
        s = to_screen(m + V(0, 3, 0))
        x, y = (s[0], s[1] - 120) if (s is not None and c < CUT_FACE) else (OUT_W / 2 - 170, 1290)
        jolt = 10 * math.exp(-(c - GULP) * 10) * math.sin((c - GULP) * 50)
        paste_text(img, "GULP!", clamp_x(x + jolt, 260), max(WORDS_TOP, y), pop(c, GULP, [6, 13, 16, 14, 14]), fill=WHITE,
                   shadow=RED)
    for at, dx in ((CUT_FACE + 0.12, -170), (CUT_FACE + 0.36, 190)):
        if at <= c < at + 0.2:
            paste_text(img, "CHOMP", OUT_W / 2 + dx, 1120 - (c - at) * 250, pop(c, at, [5, 10, 9]), fill=YEL, shadow=(110, 60, 30))
    if SPIT <= c < BURP:
        t = film_time(c) - film_time(SPIT)
        s = to_screen(m + V(0, 4, 0))
        x, y = (s[0] + 150, s[1] - 150) if s is not None else (OUT_W / 2 + 150, 420)
        paste_text(img, "PTOO!", clamp_x(x, 280), max(WORDS_TOP, y) - t * 40, pop(t, 0, [7, 13, 16, 14, 14]), fill=WHITE,
                   shadow=RED)
    tb = film_time(c) - film_time(BURP)  # (words keep film time, through the slow motion)
    if BURP <= c < G and tb < 1.3:
        t = tb
        wob = 14 * math.sin(t * 38) * math.exp(-t * 3)
        fade = 1 - max(0.0, (t - 1.1) / 0.2)
        paste_text(img, "BUUURP!", OUT_W / 2 + wob, WORDS_TOP + 40 - t * 20, pop(t, 0, [8, 14, 18, 16, 16]), fill=BURP_GREEN,
                   shadow=(30, 70, 20), alpha=fade)
    if LOOK1 <= c < LOOK1 + 0.5:
        t = c - LOOK1
        fade = 1 - max(0.0, (t - 0.38) / 0.1)
        s = to_screen(P + V(0, 3.6, 0))
        if s is not None:
            paste_text(img, "NOT AGAIN!", clamp_x(s[0], 330), max(WORDS_TOP, s[1] - 130), pop(t, 0, [4, 8, 10, 9, 9]), fill=WHITE,
                       shadow=RED, alpha=fade)


def frame_image(index):
    fr = frames[index]
    c = cyc(fr)
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts'] \
        + puffs(fr['g'])
    eye, look, fov = shot(fr)
    jolt = shake(c)
    img, to_screen = render(parts, eye + jolt, look + jolt * 0.6, fov)
    img = img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGBA')
    words_on_top(img, fr, to_screen, c)
    hook(img)
    img = img.convert('RGB')
    # white snaps: the gulp, the burp
    for at, strength in ((GULP, 0.3), (BURP, 0.3)):
        if at <= c < at + 0.12:
            img = Image.blend(img, Image.new('RGB', img.size, (255, 255, 255)), strength * (1 - (c - at) / 0.12))
    return img


# ----------------------------------------------------------------------
# the sound effects: quiet, under the music - and round the loop
# ----------------------------------------------------------------------
SOUNDS = os.path.join(here, '..', 'Sounds', 'out', 'bosses')


def load(name):
    w = wave.open(os.path.join(SOUNDS, name + '.wav'))
    assert w.getframerate() == RATE and w.getsampwidth() == 2
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    if w.getnchannels() == 2:
        x = x.reshape(-1, 2).mean(axis=1)
    return x


def lowpass(x, cutoff):
    a = math.exp(-2 * math.pi * cutoff / RATE)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s = (1 - a) * v + a * s
        y[i] = s
    return y


def noise(seconds, seed):
    return np.random.default_rng(seed).standard_normal(int(seconds * RATE)).astype(np.float32)


def env(n, attack, release, curve=1.0):
    t = np.arange(n) / RATE
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.clip((n / RATE - t) / max(release, 1e-4), 0, 1) ** curve
    return e.astype(np.float32)


def wind(seconds):
    """The suction: a breathy rush, swelling as he breathes in harder."""
    n = int(seconds * RATE)
    x = lowpass(noise(seconds, 7), 900) - lowpass(noise(seconds, 7), 120)
    t = np.arange(n) / RATE
    swell = (t / seconds) ** 1.5
    wob = 1 + 0.25 * np.sin(2 * math.pi * 3.1 * t)
    return x * env(n, 0.25, 0.15) * (0.35 + 0.65 * swell) * wob * 2.2


def whoosh(seconds, seed=3):
    """Slow motion: a low, falling whoosh."""
    n = int(seconds * RATE)
    x = noise(seconds, seed)
    t = np.arange(n) / RATE
    out = np.zeros(n, dtype=np.float32)
    # (a lowpass sweeping down: two passes blended by time)
    hi, lo = lowpass(x, 1600), lowpass(x, 300)
    k = t / seconds
    out = hi * (1 - k) + lo * k
    return out * np.sin(np.pi * np.clip(k, 0, 1)) ** 0.8 * 1.6


def thud():
    """Landing on their face: a soft body-thump and a little slap."""
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    f = 95 * np.exp(-t * 9) + 45
    body = np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t * 14)
    slap = lowpass(noise(0.35, 11), 2500) * np.exp(-t * 60) * 0.6
    return (body + slap).astype(np.float32)


def scrape(seconds):
    """Sliding along the flagstones."""
    n = int(seconds * RATE)
    x = lowpass(noise(seconds, 13), 1800) - lowpass(noise(seconds, 13), 400)
    return x * env(n, 0.02, seconds * 0.8, 1.5) * 1.4


def twinkle(seconds):
    """Dizzy stars: three little high blips going round."""
    n = int(seconds * RATE)
    out = np.zeros(n, dtype=np.float32)
    for i, at in enumerate(np.arange(0.0, seconds - 0.1, 0.16)):
        freq = (2093, 2637, 3136)[i % 3]
        m = int(0.09 * RATE)
        tt = np.arange(m) / RATE
        blip = np.sin(2 * math.pi * freq * tt) * np.exp(-tt * 40)
        s = int(at * RATE)
        out[s:s + m] += blip[:max(0, min(m, n - s))]
    return out


def boing():
    """The look back: a little rising "!" blip."""
    n = int(0.16 * RATE)
    t = np.arange(n) / RATE
    f = 600 + 900 * (t / 0.16)
    return (np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t * 18)).astype(np.float32)


def fade_out(x, seconds):
    n = min(len(x), int(seconds * RATE))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n, dtype=np.float32)
    return x


def trim(x, seconds, fade=0.06):
    return fade_out(x[:int(seconds * RATE)], fade)


def stretch(x, rate):
    """Played at `rate` speed (lower and longer when slowed: the slow motion)."""
    idx = np.arange(0, len(x) - 1, rate)
    return np.interp(idx, np.arange(len(x)), x).astype(np.float32)


def sound_track():
    n = int(round(LENGTH * RATE))
    mix = np.zeros(n, dtype=np.float32)

    def put(x, c, gain):
        """A sound starting when cycle time c is on screen, wrapping round the loop."""
        s = int(round(film_time(c) * RATE)) % n
        x = x * gain
        i = 0
        while i < len(x):
            m = min(len(x) - i, n - s)
            mix[s:s + m] += x[i:i + m]
            i += m
            s = 0
    slow_len = (SLOW_TO - SLOW_FROM) / SLOW_RATE
    put(load('Big_Inhale'), PULL0, 0.55)
    put(wind(GULP - PULL0), PULL0, 0.22)
    put(whoosh(0.6, seed=5), LIFT, 0.2)  # (whisked off their feet)
    put(load('Gulp'), GULP, 0.9)
    put(trim(load('Munching'), SPIT - GULP - 0.08), GULP + 0.08, 0.55)
    put(load('Spit_Out'), SPIT, 0.75)
    put(load('Royal_Burp'), BURP, 0.9)
    # (the slow motion: the same burp half speed underneath - an octave down, a long deep rumble)
    put(stretch(load('Royal_Burp'), 0.5), BURP, 0.45)
    put(whoosh(slow_len + 0.15), SLOW_FROM, 0.2)
    put(thud(), LAND, 0.6)
    put(scrape(REST - LAND + 0.05), LAND, 0.18)
    put(twinkle(LOOK0 - REST), REST + 0.05, 0.14)
    put(boing(), LOOK1 - 0.02, 0.16)
    # (quiet: peaks at -8 dB, so it sits under the music)
    peak = float(np.max(np.abs(mix))) or 1.0
    mix *= 10 ** (-8 / 20) / peak
    return mix


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


# ----------------------------------------------------------------------
# the thumbnail: the moment they're lifted toward his open mouth
# ----------------------------------------------------------------------
POSTER_AT = GULP - 0.1


def poster_image():
    """Closer than the film's own camera: his open mouth and the player about
    to go in, HELP! over them, the hook on top."""
    index = min(range(len(frames)), key=lambda i: abs(frames[i]['c'] - POSTER_AT))
    fr = frames[index]
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts']
    m = fr['mouth'] if fr['mouth'] is not None else along(8, 32)
    eye = along(60, 31, 10)
    look = m + V(0, -2, 0)
    img, to_screen = render(parts, eye, look, 46)
    img = img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGBA')
    s = to_screen(fr['player'] + V(0, -1.5, 0))
    if s is not None:
        paste_text(img, "HELP!", clamp_x(s[0], 300), s[1] + 40, 12, fill=WHITE, shadow=RED)  # (on his belly, under them)
    hook(img)
    return img.convert('RGB')


if __name__ == '__main__':
    import multiprocessing as mp
    if args.sound:
        write_wav(args.out, sound_track())
        print('saved', args.out)
        sys.exit(0)
    if args.poster:
        poster_image().save(args.out)
        print('saved', args.out)
        sys.exit(0)
    if args.strip or args.sheet or args.seam:
        if args.seam:
            picks = list(range(N_FRAMES - 4, N_FRAMES)) + list(range(0, 4))
        else:
            default = (0.0, 0.8, 1.45, 1.75, 2.1, 2.55, 3.1, 3.9, 4.9) if args.sheet else \
                (0.0, 0.6, 1.2, 1.6, 1.8, 2.2, 2.6, 3.0, 3.4, 3.7, 4.2, 4.8, 5.3)
            moments = [float(x) for x in args.at.split(',')] if args.at else default
            picks = [min(N_FRAMES - 1, int(round(x * FPS))) for x in moments]
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
    silent = args.out if args.silent else os.path.join(tempfile.mkdtemp(), 'silent.mp4')
    # (crf 17: looks the same as the frames on flat pixel art)
    writer = imageio_ffmpeg.write_frames(silent, (OUT_W, OUT_H), fps=FPS, quality=None, codec='libx264', macro_block_size=1,
                                         output_params=['-crf', '17', '-preset', 'slow', '-movflags', '+faststart'])
    writer.send(None)
    with mp.Pool(args.workers) as pool:
        for i, img in enumerate(pool.imap(frame_image, range(len(frames)), chunksize=2)):
            writer.send(np.asarray(img).tobytes())
            if i % 30 == 0:
                print('frame', i, flush=True)
    writer.close()
    if not args.silent:
        wav = os.path.join(os.path.dirname(silent), 'sound.wav')
        write_wav(wav, sound_track())
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-i', silent, '-i', wav, '-map', '0:v',
                        '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart',
                        args.out], check=True)
    print('saved', args.out)
