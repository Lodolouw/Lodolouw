"""Draws one wide, cinematic banner picture of a boss (the Arcade menu's
banner at the top of each machine): one snapshot from a snapshot file (or one
moment of a cutscene file), drawn with render_snaps.py's drawing at twice the
size and shrunk, no caption and no boss bar, then made dramatic: a light
burst and speed lines behind the boss, dust and sparks, a colour grade in the
boss's colours, a darker left side (the game writes the machine's name
there), a vignette and a little film grain. 1024 x 320.

    luau kongo_snaps.luau -a poses > kongo_poses.txt
    python3 render_banner.py kongo_poses.txt mad Banner_Jungle.png --tint 255,120,60

The camera can be moved from the snapshot's own (all of the scene is in the
file, not just what its camera saw): --orbit turns it round the boss
(degrees), --dist and --height put it that far from / above the point it
looks at (the snapshot's look point, raised by --look-dy). The boss's point
lands at --place x,y of the picture (0.66,0.5: right of the middle, the left
side left calm for the words). The game crops the banner to about 1012 x 200,
so keep his face between y 0.2 and 0.8.

A cutscene file (oozark_cutscene.luau's) works too: --cutscene <seconds>
picks the frame and the snap name is ignored; the camera then starts in front
of the boss (--orbit 0 is from the pit's front, where the player walks in).

make_banners.sh makes all ten.
"""
import json, math, argparse
import numpy as np
from PIL import Image, ImageFilter
import render_snaps as rs

OUT_W, OUT_H = 1024, 320
UP = np.array([0.0, 1.0, 0.0])

# the player's blocky figure in the snapshot scripts (--hide-player takes it out)
PLAYER_LIMBS = {'Torso', 'Head', 'LeftArm', 'RightArm', 'LeftLeg', 'RightLeg'}
PLAYER_COLOURS = {(0, 153, 219), (254, 231, 97), (62, 137, 72)}


def vec(s):
    return np.array([float(v) for v in s.split(',')])


def flat_unit(v):
    v = np.array([v[0], 0.0, v[2]])
    n = np.linalg.norm(v)
    return v / n if n > 1e-6 else np.array([0.0, 0.0, 1.0])


def rot_y(v, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c])


def load_cutscene(path, t):
    """One frame of a cutscene file as a snapshot (the arena, with that frame's changes, and the moving parts)."""
    static, frames, cur, mode = {}, [], None, None
    for line in open(path):
        if line.startswith('STATIC'):
            mode = 'static'
        elif line.startswith('ENDSTATIC'):
            mode = None
        elif line.startswith('FRAME '):
            bits = line.split()
            cur = {'t': float(bits[2]), 'parts': [], 'over': {}}
            frames.append(cur)
            mode = 'frame'
        elif line.startswith('POS ') and cur is not None:
            v = [float(x) for x in line.split()[1:7]]
            cur['boss'], cur['player'] = np.array(v[0:3]), np.array(v[3:6])
        elif line.startswith('ENDFRAME'):
            mode = None
        elif line.startswith('{'):
            p = json.loads(line)
            if mode == 'static':
                static[p['i']] = p
            elif mode == 'frame':
                if 'i' in p:
                    cur['over'][p['i']] = p
                else:
                    cur['parts'].append(p)
    fr = min(frames, key=lambda f: abs(f['t'] - t))
    parts = [fr['over'].get(i, p) for i, p in static.items()] + [p for p in fr['parts'] if p['n'] != 'Warm']
    b = fr['boss']
    return {'name': 't%.2f' % fr['t'], 'eye': b + np.array([0, 4, 36]), 'look': b + np.array([0, 4, 0]),
            'parts': parts, 'bar': None, 'fov': 62}, (np.array([46., 54, 88]), np.array([112., 128, 160]))


def smoothstep(a, b, x):
    k = np.clip((x - a) / (b - a), 0, 1)
    return k * k * (3 - 2 * k)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('snaps')
    ap.add_argument('snap', help='the snapshot\'s name (ignored with --cutscene)')
    ap.add_argument('out')
    ap.add_argument('--cutscene', type=float, default=None, help='the snapshot file is a cutscene: this moment (seconds)')
    ap.add_argument('--orbit', type=float, default=0, help='turn the camera round the boss (degrees, + is to his left)')
    ap.add_argument('--dist', type=float, default=None, help='the camera this far (flat) from the look point')
    ap.add_argument('--height', type=float, default=None, help='the camera this high over the look point')
    ap.add_argument('--look-dy', type=float, default=0, help='raise the look point (the boss\'s middle) this much')
    ap.add_argument('--fov', type=float, default=34, help='the picture\'s field of view, top to bottom (degrees)')
    ap.add_argument('--roll', type=float, default=0, help='a Dutch tilt (degrees)')
    ap.add_argument('--place', default='0.66,0.5', help='where the look point lands (fractions of width, height)')
    ap.add_argument('--radius', type=float, default=8, help='about how big the boss is (studs): the light goes behind that')
    ap.add_argument('--burst', default='0,0', help='move the light burst\'s middle (fractions of width, height)')
    ap.add_argument('--tint', default='255,190,90', help='the boss\'s colour: the light and the highlights')
    ap.add_argument('--shade', default='40,20,70', help='the shadows\' colour')
    ap.add_argument('--strength', type=float, default=1.0, help='how strong the light burst and speed lines are')
    ap.add_argument('--dust', default='255,220,160', help='the dust / sparks\' colour')
    ap.add_argument('--dust-count', type=int, default=90)
    ap.add_argument('--hide-player', action='store_true', help='take the player\'s blocky figure out')
    ap.add_argument('--sky', default=None, help='the sky\'s colours top|bottom (r,g,b|r,g,b), instead of the file\'s')
    ap.add_argument('--seed', type=int, default=7)
    args = ap.parse_args()

    if args.cutscene is not None:
        snap, sky = load_cutscene(args.snaps, args.cutscene)
    else:
        snaps, _, sky = rs.load_snaps(args.snaps)
        found = [s for s in snaps if s['name'] == args.snap]
        if not found:
            raise SystemExit('no snapshot called %s (there are: %s)' % (args.snap, ' '.join(s['name'] for s in snaps)))
        snap = found[0]
    if args.sky:
        top, bottom = args.sky.split('|')
        sky = (vec(top), vec(bottom))
    if args.hide_player:
        snap['parts'] = [p for p in snap['parts'] if not (p['n'] in PLAYER_LIMBS and tuple(p['col']) in PLAYER_COLOURS)]

    # the camera: round the boss's point, then aimed so the point lands at --place
    target = snap['look'] + np.array([0, args.look_dy, 0])
    d0 = flat_unit(snap['eye'] - snap['look'])
    dist = args.dist if args.dist is not None else float(np.linalg.norm((snap['eye'] - snap['look']) * [1, 0, 1]))
    height = args.height if args.height is not None else float(snap['eye'][1] - snap['look'][1])
    eye = target + rot_y(d0, args.orbit) * dist + np.array([0, height, 0])

    # (drawn bigger round the point, so the point is in the middle, then cut: a shifted lens, verticals stay upright)
    px, py = vec(args.place)
    SCALE = 2  # twice the size, then shrunk
    W2, H2 = OUT_W * SCALE, OUT_H * SCALE
    rw = int(math.ceil(2 * max(px, 1 - px) * W2 / 2)) * 2
    rh = int(math.ceil(2 * max(py, 1 - py) * H2 / 2)) * 2
    fov = math.degrees(2 * math.atan(math.tan(math.radians(args.fov) / 2) * rh / H2))
    x0 = min(max(0, int(round(rw / 2 - px * W2))), rw - W2)
    y0 = min(max(0, int(round(rh / 2 - py * H2))), rh - H2)
    rs.W, rs.H, rs.SS, rs.SKY = rw, rh, 1, sky
    view = dict(snap, eye=eye, look=target, fov=fov)
    img, _ = rs.render(view, True, 900)
    img = img.crop((x0, y0, x0 + W2, y0 + H2))
    depth = view['_depth'][y0:y0 + H2, x0:x0 + W2]
    with np.errstate(divide='ignore'):
        z = np.where(np.isfinite(depth) & (depth > 0), 1.0 / np.maximum(depth, 1e-9), 1e9)
    if args.roll:
        img = img.rotate(args.roll, resample=Image.BICUBIC, expand=False, center=(px * W2, py * H2))
        zi = Image.fromarray(np.minimum(z, 1e6).astype(np.float32)).rotate(args.roll, resample=Image.NEAREST, center=(px * W2, py * H2), fillcolor=1e6)
        z = np.array(zi)
        # (the rotation leaves corners empty: zoom in a touch so they're filled)
        zoom = 1 + abs(math.sin(math.radians(args.roll))) * (W2 / H2) * 0.5
        cx, cy = px * W2, py * H2
        box = (cx - cx / zoom, cy - cy / zoom, cx + (W2 - cx) / zoom, cy + (H2 - cy) / zoom)
        img = img.resize((W2, H2), Image.BICUBIC, box=box)
        z = np.array(Image.fromarray(z.astype(np.float32)).resize((W2, H2), Image.NEAREST, box=box))

    col = np.asarray(img).astype(np.float32) / 255.0
    Hh, Ww = col.shape[:2]
    ys, xs = np.mgrid[0:Hh, 0:Ww].astype(np.float32)
    rng = np.random.default_rng(args.seed)
    tint = vec(args.tint) / 255.0
    shade = vec(args.shade) / 255.0
    zb = float(np.linalg.norm(eye - target))
    behind = smoothstep(zb + args.radius * 0.6, zb + args.radius * 2.0, z)  # 1: well behind the boss (and the sky)

    # --- the light burst behind him: a glow and rays out of his middle
    bx, by = vec(args.burst)
    cx, cy = (px + bx) * Ww, (py + by) * Hh
    dx, dy = xs - cx, ys - cy
    r = np.sqrt(dx * dx + dy * dy) / Hh
    ang = np.arctan2(dy, dx)
    bins = 1440
    ray = rng.random(bins)
    ray = np.convolve(np.concatenate([ray[-6:], ray, ray[:6]]), np.ones(7) / 7, mode='same')[6:-6]
    ray = np.clip((ray - 0.45) * 3.2, 0, 1) ** 1.5
    rays = ray[((ang + math.pi) / (2 * math.pi) * bins).astype(int) % bins]
    glow = np.exp(-(r / 0.55) ** 2)
    left_calm = 0.35 + 0.65 * smoothstep(0.15, 0.5, xs / Ww)
    burst = (0.75 * glow + 0.55 * rays * np.exp(-r / 1.1)) * behind * args.strength
    light = np.clip(tint * 0.75 + 0.35, 0, 1)
    Lb = (col @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    col = col + burst[..., None] * light * 0.85 * (1 - 0.7 * Lb)  # (softer over what's already bright: no white-out)

    # --- speed lines: thin streaks out of his middle, not over him
    lines = np.zeros(bins * 4, dtype=np.float32)
    starts = np.zeros(bins * 4, dtype=np.float32)
    for _ in range(170):
        k = rng.integers(0, bins * 4)
        lines[k] = rng.uniform(0.35, 1.0)
        lines[(k + 1) % (bins * 4)] = lines[k] * 0.5
        starts[k] = starts[(k + 1) % (bins * 4)] = rng.uniform(0.45, 1.3)
    li = ((ang + math.pi) / (2 * math.pi) * bins * 4).astype(int) % (bins * 4)
    streak = lines[li] * smoothstep(0, 0.35, r - starts[li]) * smoothstep(0.3, 1.2, r)
    near = z < zb - args.radius * 1.2  # (the floor right in front of us: lines there too)
    streak_mask = np.maximum(behind, near.astype(np.float32) * 0.6) * left_calm
    col = col + (streak * streak_mask * args.strength * 0.55)[..., None] * np.clip(light + 0.25, 0, 1)

    # --- dust and sparks: blurred specks, a few streaked out from him
    dust = Image.new('RGB', (Ww, Hh), (0, 0, 0))
    from PIL import ImageDraw
    dd = ImageDraw.Draw(dust)
    dcol = tuple(int(v) for v in vec(args.dust))
    for i in range(args.dust_count):
        a = rng.uniform(-math.pi, math.pi)
        rr = rng.uniform(0.25, 1.6) * Hh
        x = cx + math.cos(a) * rr * 1.2
        y = cy + math.sin(a) * rr * 0.75 + Hh * 0.12
        if not (0 <= x < Ww and 0 <= y < Hh):
            continue
        s = rng.uniform(1.0, 4.5) * SCALE
        br = rng.uniform(0.3, 1.0)
        c = tuple(int(v * br) for v in dcol)
        if i % 4 == 0:  # a spark, streaked away from him
            L = rng.uniform(10, 34) * SCALE
            dd.line([x, y, x + math.cos(a) * L, y + math.sin(a) * L * 0.75], fill=c, width=max(1, int(s * 0.5)))
        else:
            dd.ellipse([x - s, y - s, x + s, y + s], fill=c)
    dust = np.asarray(dust.filter(ImageFilter.GaussianBlur(1.2 * SCALE))).astype(np.float32) / 255.0
    col = col + dust * 0.9

    # --- the colour grade: contrast, saturation, shadows to --shade, highlights to --tint
    col = np.clip(col, 0, 1.4)
    L = (col @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    col = L + (col - L) * 1.22
    col = np.clip(col, 0, 1)
    s_curve = col * col * (3 - 2 * col)
    col = col * 0.45 + s_curve * 0.55
    L = (col @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    col = col * (1 - (1 - L) ** 2 * 0.45) + shade * (1 - L) ** 2 * 0.45
    col = col * (1 - L ** 2 * 0.2) + col * tint * L ** 2 * 0.2 * 1.6

    # --- the left side darker, for the machine's name
    fx = xs / Ww
    left = 0.2 + 0.8 * smoothstep(0.02, 0.5, fx)
    col = col * left[..., None] + shade * (1 - left[..., None]) * 0.5

    # --- vignette (round his side of the picture) and a touch of top/bottom
    vx = (xs / Ww - 0.6) / 0.75
    vy = (ys / Hh - 0.5) / 0.75
    vig = 1 - 0.55 * np.clip(vx * vx + vy * vy, 0, 1.6) ** 1.3
    edge = 1 - 0.18 * (smoothstep(0.25, 0.0, ys / Hh) + smoothstep(0.75, 1.0, ys / Hh))
    col = col * (vig * edge)[..., None]

    # --- film grain
    col = col + rng.normal(0, 0.018, (Hh, Ww, 1)).astype(np.float32)
    out = Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8))
    out = out.resize((OUT_W, OUT_H), Image.LANCZOS)
    out.save(args.out)
    print('saved', args.out, out.size, 'camera', ' '.join('%.2f' % v for v in eye), 'look', ' '.join('%.2f' % v for v in target))


if __name__ == '__main__':
    main()
