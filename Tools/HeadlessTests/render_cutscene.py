"""Films the Oozark cutscene: every frame oozark_cutscene.luau printed (the
real arena, Oozark's real body and poses, the player), shot by a moving
camera - a crane down into the pit, low behind the player as he rises, his
face as he roars, from above for his lunge, over the shoulder for the
punches, wide for the slam, and low as the wave comes - with the boss bar,
his name, hit pops, flashes and camera shake on top. It ends on a freeze
frame as the player jumps the wave: CAN YOU BEAT HIM? 1080 x 1920 (a
YouTube Short), 30 frames a second.

    luau oozark_cutscene.luau > cutscene.txt
    python3 render_cutscene.py cutscene.txt ../../Docs/youtube/oozark_cutscene.mp4
    python3 render_cutscene.py cutscene.txt strip.png --strip      (a few frames, to check)
    python3 render_cutscene.py cutscene.txt strip.png --strip --at 5.2,5.8   (just those moments)

The drawing is render_snaps.py's (flat colours lit by one sun, thin dark
edges: the game's 8-bit look), so it shows the game's real shapes and
colours, not Roblox's own lighting or its particles.
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
ap.add_argument('--at', default='', help='with --strip: the moments to show (seconds, comma separated)')
ap.add_argument('--workers', type=int, default=4)
ap.add_argument('--scale', type=int, default=2, help='draw at 1/scale size, then blow up (chunkier, faster)')
args = ap.parse_args()

OUT_W, OUT_H, FPS = 1080, 1920, 30
W, H = OUT_W // args.scale, OUT_H // args.scale
SS = 2

# ----------------------------------------------------------------------
# what the scene printed
# ----------------------------------------------------------------------
static, frames = [], []
cur = None
mode = None
for line in open(args.src):
    if line.startswith('STATIC'):
        mode = 'static'
    elif line.startswith('ENDSTATIC'):
        mode = None
    elif line.startswith('FRAME '):
        bits = line.split()
        cur = {'i': int(bits[1]), 't': float(bits[2]), 'parts': [], 'over': {}}
        frames.append(cur)
        mode = 'frame'
    elif line.startswith('POS ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['boss'], cur['player'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('STATE ') and cur is not None:
        bits = line.split()
        cur['state'], cur['hp'], cur['action'] = bits[1], float(bits[2]), bits[3]
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
HOME = np.array([frames[0]['boss'][0], FLOOR, frames[0]['boss'][2]])  # the middle of the pit, on the floor
for fr in frames:
    # (BossClient's shader warm-up: specks you can't see, in front of its own camera)
    fr['parts'] = [p for p in fr['parts'] if p['n'] != 'Warm']
print('scene:', len(static), 'arena parts,', len(frames), 'frames')

# ----------------------------------------------------------------------
# the drawing (render_snaps.py's, for any size and camera)
# ----------------------------------------------------------------------
LIGHT = np.array([-0.45, 0.8, 0.35])
LIGHT /= np.linalg.norm(LIGHT)
NEAR = 0.5
SKY_TOP, SKY_BOTTOM = np.array([46, 54, 88], dtype=np.float32), np.array([112, 128, 160], dtype=np.float32)


def render(parts, eye, look, fov, rng_limit=320):
    w, h = W * SS, H * SS
    fwd = look - eye
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (h / 2) / math.tan(math.radians(fov) / 2)
    color = np.zeros((h, w, 3), dtype=np.float32)
    k = np.clip(np.arange(h) / (h * 0.7), 0, 1)[:, None]
    color[:] = (SKY_TOP * (1 - k) + SKY_BOTTOM * k)[:, None, :]
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


# the freeze frame: the player at the top of their jump, the wave right under them
FREEZE = 9.0333


def shots(fr):
    """Where the camera is and what it looks at in frame `fr`, and its lens."""
    t = fr['t']
    B, P = fr['boss'], fr['player']
    toBoss = unit(flat(B - P))
    side = unit(np.cross(toBoss, [0, 1, 0]))  # (to the player's right as they face him)
    b = V(B[0], FLOOR, B[2])  # (him, on the floor)
    p = V(P[0], FLOOR, P[2])  # (them, on the floor)
    if t < 2.35:  # 1) a crane down into the pit as the player walks in
        k = ease(t / 2.35)
        eye = lerp(HOME + V(22, 54.5, 150), HOME + V(10, 25.5, 96), k)
        look = lerp(HOME + V(0, 6.5, 30), HOME + V(0, 13.5, 0), k)
        return eye, look, 60
    if t < 3.55:  # 2) behind and above the player (the game's own camera): the pool heaves and he rises out of it
        k = ease((t - 2.35) / 1.2)
        rise = ease((t - 2.8) / 0.8)
        eye = p + V(2.5, 8.5, 17) + V(-0.5, -1.5, -5) * k
        look = HOME + V(0, 6 + 5 * rise, 0)
        return eye, look, 62
    if t < 5.0:  # 3) his face, from low down, as his eyes open and he roars
        k = ease((t - 3.55) / 1.45)
        eye = HOME + V(-5, 3.5, 36) + V(1.5, 0, -4) * k
        look = HOME + V(0, 8, 4)
        return eye, look, 62
    if t < 6.05:  # 4) from high behind the player: he hurls himself down the pit at them
        k = ease((t - 5.0) / 1.05)
        roll = ease((t - 5.6) / 0.45)  # (following them as they roll clear)
        eye = HOME + V(-3, 31, 73) + V(1, -3, -3) * k + V(3, 2, 2) * roll
        look = HOME + V(4, 1, 25) + V(0, 0, 6) * k + V(5, 0, 0) * roll
        return eye, look, 58
    if t < 7.02:  # 5) over their shoulder for the punches
        k = ease((t - 6.05) / 0.97)
        eye = p - toBoss * (15 - 2 * k) + side * 5.5 + V(0, 7, 0)
        look = b - toBoss * 10 + V(0, 5.5, 0)  # (his face: the side of him they're hitting)
        return eye, look, 62
    if t < 7.95:  # 6) wide and low: he rears up and slams, they roll toward us, the ring races after them
        eye = HOME + V(47, 5, 57)
        look = HOME + V(9, 13, 44)
        return eye, look, 62
    # 7) behind them and off to one side as he flattens and the wave comes: they jump it
    tt = min(t, FREEZE)
    k = ease((tt - 7.95) / (FREEZE - 7.95))
    eye = p - toBoss * (22 - 2 * k) - side * 7.5 + V(0, 4.8, 0)
    look = b + V(0, 10.3, 0) + side * 2
    return eye, look, 62


def shake(t):
    """Camera shake: when he wakes roaring, on each punch, and hard as he slams down."""
    amp = 0.0
    for at, strength, length in ((3.98, 0.7, 0.6), (6.03, 0.5, 0.3), (6.27, 0.22, 0.15), (6.55, 0.25, 0.15), (6.85, 0.45, 0.25),
                                 (7.62, 1.3, 0.55), (8.7, 0.4, 0.3)):
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


def paste_text(img, words, cx, top, scale, fill=YEL, shadow=(160, 80, 40)):
    if scale <= 0:
        return
    ti = text_image(words, fill=fill, shadow=shadow)
    big = ti.resize((max(1, int(ti.width * scale)), max(1, int(ti.height * scale))), Image.NEAREST)
    img.paste(big, (int(cx - big.width / 2), int(top)), big)


def boss_bar(img, hp):
    d = ImageDraw.Draw(img)
    bw, x0, y0 = 860, (OUT_W - 860) // 2, 210
    label = text_image("OOZARK", fill=WHITE, shadow=None)
    label = label.resize((label.width * 5, label.height * 5), Image.NEAREST)
    img.paste(label, (x0, y0 - 58), label)
    d.rectangle([x0 - 6, y0 - 6, x0 + bw + 6, y0 + 34], fill=INK)
    d.rectangle([x0, y0, x0 + bw, y0 + 28], fill=(40, 16, 22))
    d.rectangle([x0, y0, x0 + int(bw * max(0.0, min(1.0, hp))), y0 + 28], fill=(200, 36, 44))
    d.rectangle([x0, y0, x0 + int(bw * max(0.0, min(1.0, hp))), y0 + 6], fill=(240, 90, 90))


HITS = [(6.27, "HIT!", 360, 700), (6.55, "HIT!", 720, 640), (6.85, "WHAM!", 540, 560)]  # (when, word, where on screen)
_frozen = {}


def scene_image(index, t):
    """The 3D picture of frame `index` (the camera at time t), at full size."""
    fr = frames[index]
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts']
    eye, look, fov = shots(fr)
    jolt = shake(t) if t < FREEZE else np.zeros(3)
    img, to_screen = render(parts, eye + jolt, look + jolt * 0.6, fov)
    return img.resize((OUT_W, OUT_H), Image.NEAREST).convert('RGBA'), to_screen


def ending(t):
    """The freeze frame: the player hangs over the wave, the picture darkens and
    creeps in, CAN YOU / BEAT HIM? slams on, then LIKE TO UNLOCK THE GAME!"""
    index = min(range(len(frames)), key=lambda i: abs(frames[i]['t'] - FREEZE))
    if 'img' not in _frozen:
        _frozen['img'] = scene_image(index, FREEZE)[0].convert('RGB')
    base = _frozen['img']
    u = t - FREEZE
    zoom = 1 + 0.06 * ease(u / 0.9)
    cw, ch = OUT_W / zoom, OUT_H / zoom
    box = (int((OUT_W - cw) / 2), int((OUT_H - ch) * 0.4), int((OUT_W - cw) / 2 + cw), int((OUT_H - ch) * 0.4 + ch))
    img = base.crop(box).resize((OUT_W, OUT_H), Image.NEAREST)
    # darker, a little washed of colour, so the words read
    grey = img.convert('L').convert('RGB')
    img = Image.blend(img, grey, 0.35 * min(1, u / 0.25))
    img = Image.blend(img, Image.new('RGB', img.size, (10, 8, 24)), 0.42 * min(1, u / 0.25))
    img = img.convert('RGBA')
    paste_text(img, "CAN YOU", OUT_W / 2, 230, pop(u, 0.08, [6, 13, 21, 19, 18]))
    paste_text(img, "BEAT HIM?", OUT_W / 2, 420, pop(u, 0.24, [6, 13, 21, 19, 18]))
    if u > 0.5:
        paste_text(img, "LIKE TO UNLOCK THE GAME!", OUT_W / 2, 1300, 6, fill=WHITE, shadow=(30, 30, 60))
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
    # the words
    paste_text(img, "FLOOR 1", OUT_W / 2, 330, pop(t, 0.3, [4, 9, 15, 14, 13]) if t < 2.1 else 0)
    if 0.6 <= t < 2.1:
        paste_text(img, "OOZARK'S HOLLOW", OUT_W / 2, 470, 6, fill=WHITE, shadow=(30, 30, 60))
    if fr['state'] in ('Waking', 'Fighting') and t >= 3.0:
        boss_bar(img, fr['hp'])
    if 3.98 <= t < 5.0:
        paste_text(img, "OOZARK", OUT_W / 2, 1230, pop(t, 3.98, [6, 14, 22, 20, 19]))
        if t >= 4.2:
            paste_text(img, "THE GELATINOUS TYRANT", OUT_W / 2, 1410, 6, fill=WHITE, shadow=(30, 30, 60))
    for at, word, x, y in HITS:
        if at <= t < min(at + 0.35, 7.02):  # (gone with the cut to the slam)
            big = word == "WHAM!"
            paste_text(img, word, x, y - (t - at) * 200, pop(t, at, [4, 10, 8]) * (1.5 if big else 1),
                       fill=WHITE if not big else YEL, shadow=RED)
    img = img.convert('RGB')
    # white flashes: the big punch, and the slam hitting the floor
    for at, strength in ((6.85, 0.35), (7.62, 0.6)):
        if at <= t < at + 0.14:
            img = Image.blend(img, Image.new('RGB', img.size, (255, 255, 255)), strength * (1 - (t - at) / 0.14))
    return img


if __name__ == '__main__':
    import multiprocessing as mp
    if args.strip:
        moments = [float(x) for x in args.at.split(',')] if args.at else (1.0, 3.0, 4.3, 5.75, 6.6, 7.66, 8.8, 9.6)
        picks = [min(len(frames) - 1, int(round(x * FPS))) for x in moments]
        with mp.Pool(args.workers) as pool:
            imgs = pool.map(frame_image, picks)
        thumbs = [im.resize((270, 480), Image.LANCZOS) for im in imgs]
        strip = Image.new('RGB', (len(thumbs) * 280 + 10, 490), (15, 15, 15))
        for i, th in enumerate(thumbs):
            strip.paste(th, (10 + i * 280, 5))
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
