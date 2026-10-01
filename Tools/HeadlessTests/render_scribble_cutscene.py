"""Films SCRIBBLE's ERASER: every frame scribble_cutscene.luau printed (the
real Canvas, his real body and moves, the player, and the camera - he's a
drawing, so he turns to face whatever camera looks at him, and the scene
works out the camera itself). On top: the hook the whole way (I MADE A BOSS
THAT ERASES YOU), the pops (WHOOSH!, SPLAT!, CTRL+C... CTRL+V!, RUN!,
PHEW..., ?!, NO NO NO, the DELETED stamp, HA HA HA), flashes and camera
shake. It LOOPS: the last frame runs straight into the first. And the game's
own sound effects mixed in quietly (peaks at -8 dB) under whatever music goes
on top, wrapping round the loop. 1080 x 1920 (a YouTube Short), 30 fps.

    luau scribble_cutscene.luau > scribble.txt
    python3 render_scribble_cutscene.py scribble.txt ../../Docs/animations/scribble_short.mp4
    python3 render_scribble_cutscene.py scribble.txt sheet.png --sheet     (a 3 x 3 contact sheet)
    python3 render_scribble_cutscene.py scribble.txt strip.png --strip --at 0.5,9.2
    python3 render_scribble_cutscene.py scribble.txt seam.png --seam       (the loop: last frames, first frames)
    python3 render_scribble_cutscene.py scribble.txt thumb.png --poster    (the thumbnail)
    python3 render_scribble_cutscene.py scribble.txt sound.wav --sound

The drawing is render_gavelgrunt_cutscene.py's (flat colours lit by one sun,
thin dark edges), under the bright sky inside the computer. Particles
(BURST) are drawn as little blocks. The sounds are Tools/Sounds/out/bosses'
Scribble ones (Pencil Scratch, Ink Dash, Ink Skid, Paint Splash, Copy Paste,
Eraser Rub, Scribble Laugh) plus a few soft ones made here (a whoosh, a
thud, pops for the crumbs, the dizzy twinkle).
"""
import json, math, os, sys, argparse, wave, subprocess, tempfile
import numpy as np
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, '..', '..', 'Docs', 'youtube'))
from pixel_art import text_image, YEL, WHITE, RED  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('out')
ap.add_argument('--strip', action='store_true', help='just a strip of a few frames (a PNG)')
ap.add_argument('--sheet', action='store_true', help='a 3 x 3 contact sheet of frames across the film (a PNG)')
ap.add_argument('--seam', action='store_true', help='the last few frames and the first few, in a row (a PNG): the loop')
ap.add_argument('--at', default='', help='with --strip / --sheet: the moments to show (film seconds, comma separated)')
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
static, frames, bursts, kicks, events = [], [], [], [], {}
cur = None
mode = None
for line in open(args.src):
    if line.startswith('STATIC'):
        mode = 'static'
    elif line.startswith('ENDSTATIC'):
        mode = None
    elif line.startswith('FRAME '):
        bits = line.split()
        cur = {'i': int(bits[1]), 't': float(bits[2]), 'g': float(bits[3]), 's': float(bits[4]), 'parts': [], 'over': {},
               'aim': None, 'head': None}
        frames.append(cur)
        mode = 'frame'
    elif line.startswith('CAM ') and cur is not None:
        v = [float(x) for x in line.split()[1:8]]
        cur['eye'], cur['look'], cur['fov'] = np.array(v[0:3]), np.array(v[3:6]), v[6]
    elif line.startswith('POS ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['boss'], cur['player'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('AIM ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['aim'], cur['head'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('BURST '):
        b = [float(x) for x in line.split()[1:]]
        bursts.append({'g': b[0], 'pos': np.array(b[1:4]), 'col': (int(b[4]), int(b[5]), int(b[6])), 'n': int(b[7]),
                       'speed': (b[8], b[9]), 'size': (b[10], b[11]), 'life': (b[12], b[13]), 'spread': b[14],
                       'acc': b[15], 'drag': b[16]})
    elif line.startswith('KICK '):
        b = line.split()
        kicks.append((float(b[1]), float(b[2])))
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
    fr['parts'] = [p for p in fr['parts'] if p['n'] != 'Warm']


def ev(name, k=0):
    return events[name][k][0]


def ev_nums(name, k=0):
    return [float(x) for x in events[name][k][1]]


N_FRAMES, GAME_LEN, SLOW_AT, SLOW_GAME, SLOW_RATE = ev_nums('loop')
N_FRAMES = int(N_FRAMES)
PAINT, FLOOD, COPY, CLONES, CALM, ERASE, RUB, PASS1, PASS2, PASS3, PASS4, LAUGH, DASH2, REDRAW0 = ev_nums('times')
PASSES = (PASS1, PASS2, PASS3, PASS4)
MID = np.array(ev_nums('stage')[0:3])
FLOOR = MID[1]
SLOW_FROM = ev_nums('slow')[0]
SLOW_TO = ev_nums('fast')[0]
LENGTH = N_FRAMES / FPS
G_OFF = frames[0]['g'] - frames[0]['s']  # (game clock = s + this, outside the slow motion)
assert len(frames) == N_FRAMES, (len(frames), N_FRAMES)
print('scene:', len(static), 'arena parts,', len(frames), 'frames,', len(bursts), 'bursts,', '%.2f s' % LENGTH)


def film_time(s):
    """When scene time s is on screen (seconds of film), slow motion and all;
    before 0 is the same moment of the loop's next go."""
    if s < -1e-9:
        s += GAME_LEN
    if s < SLOW_FROM:
        return s
    if s < SLOW_TO:
        return SLOW_FROM + (s - SLOW_FROM) / SLOW_RATE
    return SLOW_FROM + (SLOW_TO - SLOW_FROM) / SLOW_RATE + (s - SLOW_TO)


# ----------------------------------------------------------------------
# the particles, and the drawing (render_gavelgrunt_cutscene.py's)
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
# the drawing (render_cutscene.py's, under a bright sky)
# ----------------------------------------------------------------------
LIGHT = np.array([-0.45, 0.8, 0.35])
LIGHT /= np.linalg.norm(LIGHT)
NEAR = 0.5
SKY_TOP, SKY_LOW = np.array([150, 200, 255], dtype=np.float32), np.array([225, 238, 255], dtype=np.float32)  # (inside the computer)


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
# the camera: the scene's own (CAM), shaken
# ----------------------------------------------------------------------
def ease(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def V(x, y, z):
    return np.array([float(x), float(y), float(z)])


def spot(x, z, y=0.0):
    return V(MID[0] + x, FLOOR + y, MID[2] + z)


# camera shake: (scene time, how hard, how long) - the game's own knocks
# (KICK) and the film's moments
SHAKES = [(g - G_OFF, 0.25 + 0.5 * k, 0.3) for g, k in kicks if g - G_OFF > -0.5] + \
    [(0.45, 0.6, 0.35), (FLOOD + 0.5, 0.4, 0.2)] + [(p, 0.35, 0.2) for p in PASSES[:3]] + [(PASS4, 0.9, 0.45)]


def shake(s):
    amp = 0.0
    for at, strength, length in SHAKES:
        for a in (at, at + GAME_LEN, at - GAME_LEN):
            if a <= s < a + length:
                amp = max(amp, strength * (1 - (s - a) / length))
    if RUB <= s < PASS4 + 0.5:  # (the eraser rumbling)
        amp = max(amp, 0.06)
    if amp <= 0:
        return np.zeros(3)
    r = np.random.default_rng(int(round(s * 1200)) + 7)
    return (r.random(3) - 0.5) * 2 * amp


# ----------------------------------------------------------------------
# on top: the hook, the words, flashes
# ----------------------------------------------------------------------
PINK = (246, 117, 122)
INKBLUE = (0, 153, 219)


def pop(t, start, steps):
    if t < start:
        return 0
    return steps[min(int((t - start) * FPS), len(steps) - 1)]


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


CAP_TOP = 110
WORDS_TOP = 380
_band = {}


def top_band():
    if 'img' not in _band:
        a = np.zeros((OUT_H, OUT_W), dtype=np.uint8)
        for y in range(0, 480):
            a[y, :] = int(175 * (1 - y / 480) ** 1.3)
        band = Image.new('RGBA', (OUT_W, OUT_H), (12, 10, 26, 0))
        band.putalpha(Image.fromarray(a))
        _band['img'] = band
    return _band['img']


def hook(img, s=None):
    """I MADE A BOSS THAT / ERASES YOU: on top the whole way. ERASES YOU
    rubs itself out letter by letter while the player is rubbed out... and
    comes back as they're drawn back in."""
    img.alpha_composite(top_band())
    cx = OUT_W / 2
    paste_text(img, "I MADE A BOSS THAT", cx, CAP_TOP, 7, fill=WHITE, shadow=(30, 30, 60))
    paste_text(img, "ERASES YOU", cx, CAP_TOP + 78, 13, fill=PINK, shadow=(120, 30, 50))


def clamp_x(x, margin):
    return min(max(x, margin), OUT_W - margin)


def words_on_top(img, fr, to_screen, s):
    P = fr['player']
    ft = film_time(s)

    def over(pt, dy=-120, margin=260):
        q = to_screen(pt)
        if q is None:
            return None
        return clamp_x(q[0], margin), max(WORDS_TOP, q[1] + dy)
    # WHOOSH! (him rocketing down the line at us)
    t = s - 0.45
    if 0 <= t < 0.6:
        paste_text(img, "WHOOSH!", OUT_W / 2 + 120, 1250 - t * 120, pop(t, 0, [6, 12, 15, 13, 13]), fill=WHITE, shadow=INKBLUE,
                   alpha=1 - max(0.0, (t - 0.45) / 0.15))
    # SPLAT! (the paint flood flinging them)
    t = s - FLOOD
    if 0 <= t < 0.8:
        q = over(P + V(0, 2, 0), -140, 260)
        x, y = q if q else (OUT_W / 2, 1000)
        paste_text(img, "SPLAT!", x, y - t * 60, pop(t, 0, [7, 14, 17, 15, 15]), fill=(255, 90, 90), shadow=(90, 20, 30),
                   alpha=1 - max(0.0, (t - 0.65) / 0.15))
    # CTRL+C... CTRL+V! (his shouts: on screen they're BillboardGuis, drawn here)
    head = fr['head'] if fr['head'] is not None else spot(0, 0, 14)
    for at, words, fill, dx in ((COPY + 0.05, "CTRL+C", WHITE, -150), (COPY + 0.72, "CTRL+V!", YEL, 150)):
        t = s - at
        if 0 <= t < (CLONES + 0.4 - at):
            q = over(head + V(0, 2, 0), -90, 300)
            x, y = q if q else (OUT_W / 2, 700)
            paste_text(img, words, clamp_x(x + dx, 300), y + (90 if dx > 0 else 0), pop(t, 0, [5, 10, 12, 11, 11]), fill=fill,
                       shadow=(20, 40, 90))
    # RUN! (running from the clones)
    if CLONES + 0.2 <= s < CALM - 0.1 and int(s * 8) % 2 == 0:
        q = over(P + V(0, 3.4, 0), -140, 200)
        if q:
            paste_text(img, "RUN!", q[0], q[1], 10, fill=WHITE, shadow=RED)
    # PHEW...
    t = s - CALM - 0.15
    if 0 <= t < 0.65:
        q = over(P + V(0, 3.4, 0), -130, 260)
        if q:
            paste_text(img, "PHEW...", q[0], q[1], pop(t, 0, [4, 8, 9]), fill=WHITE, shadow=(30, 30, 60))
    # ?! (the pink under their feet)
    t = s - (RUB - 0.45)
    if 0 <= t < 0.5:
        q = over(P + V(0, 3.4, 0), -150, 200)
        if q:
            paste_text(img, "?!", q[0], q[1], pop(t, 0, [7, 15, 18, 16]), fill=YEL, shadow=RED)
    # NO NO NO (just a head, the eraser coming)
    if PASS3 + 0.25 <= s < PASS4 - 0.02:
        q = over(P + V(0, 0, 0), -300, 330)
        if q:
            jit = 6 * math.sin(s * 70)
            paste_text(img, "NO NO NO", q[0] + jit, q[1], 9, fill=WHITE, shadow=RED)
    # DELETED (the stamp), after the last pass
    t = ft - film_time(PASS4)
    if 0.1 <= t < film_time(LAUGH) - film_time(PASS4):
        tt = t - 0.1
        sc = pop(tt, 0, [30, 22, 17, 15, 16, 16])
        stamp = text_image("DELETED", fill=(255, 70, 70), shadow=(80, 10, 20))
        big = stamp.resize((stamp.width * sc, stamp.height * sc), Image.NEAREST).rotate(8, expand=True, resample=Image.NEAREST)
        img.paste(big, (int(OUT_W / 2 - big.width / 2), int(1180 - big.height / 2)), big)
    # HA HA HA (him, laughing)
    for i, at in enumerate((LAUGH + 0.1, LAUGH + 0.35, LAUGH + 0.6)):
        t = s - at
        if 0 <= t < DASH2 - 0.25 - at:
            x = OUT_W / 2 + (-250, 230, -120)[i]
            paste_text(img, "HA", x, 1350 - i * 210 - t * 60, pop(t, 0, [6, 11, 13, 12]), fill=INKBLUE, shadow=(10, 40, 80))


def frame_image(index):
    fr = frames[index]
    s = fr['s']
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts'] \
        + puffs(fr['g'])
    jolt = shake(s)
    img, to_screen = render(parts, fr['eye'] + jolt, fr['look'] + jolt * 0.6, fr['fov'])
    img = img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGBA')
    words_on_top(img, fr, to_screen, s)
    hook(img, s)
    img = img.convert('RGB')
    # white snaps: the flood, the last pass
    for at, strength in ((FLOOD, 0.25), (PASS4, 0.45)):
        if at <= s < at + 0.12 * (SLOW_RATE if at == PASS4 else 1):
            k = (s - at) / (0.12 * (SLOW_RATE if at == PASS4 else 1))
            img = Image.blend(img, Image.new('RGB', img.size, (255, 255, 255)), strength * (1 - k))
    return img


# ----------------------------------------------------------------------
# the sound effects: quiet, under the music - and round the loop
# ----------------------------------------------------------------------
SOUNDS = os.path.join(here, '..', 'Sounds', 'out', 'bosses')


def load(name):
    """A game sound (Tools/Sounds/out/bosses, .wav or .ogg), mono floats."""
    import imageio_ffmpeg
    for ext in ('.wav', '.ogg'):
        path = os.path.join(SOUNDS, name + ext)
        if os.path.exists(path):
            break
    raw = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-loglevel', 'error', '-i', path, '-f', 's16le', '-ac', '1', '-ar',
                          str(RATE), '-'], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768


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


def whoosh(seconds, seed=3):
    n = int(seconds * RATE)
    x = noise(seconds, seed)
    t = np.arange(n) / RATE
    hi, lo = lowpass(x, 1600), lowpass(x, 300)
    k = t / seconds
    return (hi * (1 - k) + lo * k) * np.sin(np.pi * np.clip(k, 0, 1)) ** 0.8 * 1.6


def thud():
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    f = 95 * np.exp(-t * 9) + 45
    body = np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t * 14)
    slap = lowpass(noise(0.35, 11), 2500) * np.exp(-t * 60) * 0.6
    return (body + slap).astype(np.float32)


def blip(f0, f1, seconds=0.12):
    """A little pitched pop (the bits of them coming off)."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    f = f0 + (f1 - f0) * (t / seconds)
    return (np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t * 22)).astype(np.float32)


def twinkle(seconds):
    n = int(seconds * RATE)
    out = np.zeros(n, dtype=np.float32)
    for i, at in enumerate(np.arange(0.0, seconds - 0.1, 0.16)):
        freq = (2093, 2637, 3136)[i % 3]
        m = int(0.09 * RATE)
        tt = np.arange(m) / RATE
        b = np.sin(2 * math.pi * freq * tt) * np.exp(-tt * 40)
        s = int(at * RATE)
        out[s:s + m] += b[:max(0, min(m, n - s))]
    return out


def fade_out(x, seconds):
    n = min(len(x), int(seconds * RATE))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n, dtype=np.float32)
    return x


def trim(x, seconds, fade=0.06):
    return fade_out(x[:int(seconds * RATE)], fade)


def stretch(x, rate):
    idx = np.arange(0, len(x) - 1, rate)
    return np.interp(idx, np.arange(len(x)), x).astype(np.float32)


def looped(x, seconds):
    """x over and over for `seconds` (the eraser rubbing back and forth)."""
    n = int(seconds * RATE)
    reps = int(math.ceil(n / max(1, len(x)))) + 1
    return fade_out(np.tile(x, reps)[:n], 0.15)


def sound_track():
    n = int(round(LENGTH * RATE))
    mix = np.zeros(n, dtype=np.float32)

    def put(x, s, gain):
        """A sound starting when scene time s is on screen, wrapping round the loop."""
        at = int(round(film_time(s) * RATE)) % n
        x = x * gain
        i = 0
        while i < len(x):
            m = min(len(x) - i, n - at)
            mix[at:at + m] += x[i:i + m]
            i += m
            at = 0
    lead = GAME_LEN - DASH2  # (the dash's line is drawn this long before the first frame)
    put(trim(load('Pencil_Scratch'), 0.9), DASH2, 0.5)
    put(load('Ink_Dash'), DASH2 + lead, 0.85)  # (= 0.45 s in, round the loop)
    put(whoosh(0.4, seed=5), DASH2 + lead, 0.2)
    put(load('Ink_Skid'), 0.9, 0.5)
    put(thud(), 0.42, 0.35)  # (the dive landing)
    put(load('Pencil_Scratch'), PAINT, 0.25)
    put(load('Paint_Splash'), FLOOD, 0.9)
    put(thud(), FLOOD + 0.5, 0.6)
    put(twinkle(COPY - FLOOD - 0.9), FLOOD + 0.6, 0.12)
    put(load('Copy_Paste'), COPY + 0.72, 0.8)
    put(blip(500, 1400, 0.16), RUB - 0.45, 0.18)  # (?!)
    rub = load('Eraser_Rub')
    put(looped(rub, PASS4 + 0.4 - RUB), RUB, 0.55)
    for i, p in enumerate(PASSES):
        put(blip(900 - 120 * i, 300, 0.14), p, 0.22)
    put(stretch(rub, 0.5)[:int(1.2 * RATE)], PASS4 - 0.1, 0.45)  # (slowed: the last pass, deep)
    put(whoosh((SLOW_TO - SLOW_FROM) / SLOW_RATE + 0.1, seed=9), SLOW_FROM, 0.2)
    put(load('Scribble_Laugh'), LAUGH - 0.05, 0.9)
    put(trim(load('Pencil_Scratch'), 0.5), REDRAW0, 0.3)  # (sketching them back in)
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
# the thumbnail: the eraser coming for what's left of them
# ----------------------------------------------------------------------
def poster_image():
    index = min(range(len(frames)), key=lambda i: abs(frames[i]['s'] - (PASS3 + 0.75)))
    fr = frames[index]
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts']
    img, to_screen = render(parts, fr['eye'], fr['look'], fr['fov'])
    img = img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGBA')
    words_on_top(img, fr, to_screen, fr['s'])
    hook(img, fr['s'])
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
            default = (0.1, 0.5, 2.9, 5.5, 6.5, 8.5, 9.4, 11.2, 12.8)
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
