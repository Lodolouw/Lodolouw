"""The GAME ICON (the Roblox game's square icon), drawn from the real game:
the bosses as game_icon.luau printed them (the real BossService, BossClient
and BossBodies, held in a pose) and the classic blocky noob (yellow head,
blue torso, green legs, as the snaps' player), each drawn in the game's look
(film_draw.py) on its own layer, then put together like a chart-topping
icon: one huge face, a tiny noob, a burst of rays, thick dark outlines, a
rim light, a glow and "+1" pops.

    (after python3 build_sources.py)
    luau game_icon.luau -a gridlock roar > icon_gridlock.txt
    luau game_icon.luau -a gavelgrunt laugh,smash:0.85 > icon_gavelgrunt.txt
    luau game_icon.luau -a kongo wake:0.8,mad > icon_kongo.txt
    luau game_icon.luau -a revvington wake:1.0 > icon_revvington.txt
    luau game_icon.luau -a oozark wake:1.0 > icon_oozark.txt
    python3 render_game_icon.py --scenes . --out ../../Docs/icon \\
        --font FredokaOne.ttf --pixel-font PressStart2P.ttf [--only A,B]

The icons: A GIANT FACE (Gridlock's roar over a tiny shocked noob), B THE
PUNCH (the noob punching King Gavelgrunt, his health bar nearly empty), C
BEAT THEM ALL (five bosses crowding round the noob), D VS SPLASH (the noob
against Kongo going bananas), E GROW (the noob a giant over a tiny boss).
Round 2 (the game is a boss-rush now; the icon must say "boss fight" at
150 px): F THE DODGE (King Gavelgrunt's Royal Smash wound up over its red
zone, the noob diving out, his boss bar), G BRAINROT (a meme mash-up boss:
Revvington with Kongo's arms and the king's crown, a popping-eyed noob,
BOSS???), H THE SPIRE (the tower of bosses, floor 1 to FLOOR 10, the noob
at its foot). The review sheet shows SHEET (F, G, H).
Kaze, Burrowmore, Petalina, Scribble and Tuber are left off: their looks
sit closest to the characters they parody (the handoff's Copyright rule).

Every icon is 512 x 512 (icon_A.png ...), plus icon_sheet.png: every icon at
512 and at 150 (the size a phone shows it) on the dark of the Charts page.
--preview draws each boss pose alone, framed on his face (a contact sheet),
for picking cameras.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import film_draw as fd  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--scenes', default='.', help='where the icon_<boss>.txt files are')
ap.add_argument('--out', default=os.path.join(here, '..', '..', 'Docs', 'icon'))
ap.add_argument('--font', default='', help='FredokaOne.ttf')
ap.add_argument('--pixel-font', default='', help='PressStart2P.ttf')
ap.add_argument('--only', default='', help='just these icons (A,B,...)')
ap.add_argument('--preview', action='store_true', help='every boss pose alone (a contact sheet)')
ap.add_argument('--size', type=int, default=512)
args = ap.parse_args()

SIZE = args.size
K = SIZE / 512.0  # (every number below is for a 512 icon)
ROUND_FONT = args.font if args.font and os.path.exists(args.font) else '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
PIXEL_FONT = args.pixel_font if args.pixel_font and os.path.exists(args.pixel_font) else \
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
INK = (24, 20, 37)


# ----------------------------------------------------------------------
# the scenes
# ----------------------------------------------------------------------
def load_poses(boss):
    """{pose: (feet, facing, parts)} from icon_<boss>.txt (his drawn body only)."""
    path = os.path.join(args.scenes, 'icon_%s.txt' % boss)
    out, cur = {}, None
    for line in open(path):
        if line.startswith('POSE '):
            b = line.split()
            cur = (np.array([float(x) for x in b[2:5]]), np.array([float(b[5]), 0.0, float(b[6])]), [])
            out[b[1]] = cur
        elif line.startswith('{') and cur is not None:
            p = json.loads(line)
            if p['n'] != 'Shadow' and p['g'] not in ('Warm', 'Afterimage'):
                cur[2].append(p)
        elif line.startswith('ERROR'):
            print(boss, line.rstrip())
    return out


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / (np.linalg.norm(v) + 1e-9)


def bbox(parts):
    pts = np.array([p['cf'][0:3] for p in parts])
    return pts.min(axis=0), pts.max(axis=0)


# ----------------------------------------------------------------------
# the noob: the snaps' blocky player (Torso 2x2x1, Head 1.2, arms and legs
# 1x2x1), posed, with a face
# ----------------------------------------------------------------------
YELLOW, BLUE, GREEN = (254, 231, 97), (0, 153, 219), (62, 137, 72)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def part(c, R, s, col, m='SmoothPlastic', n='p'):
    return {'cf': list(c) + list(R.reshape(-1)), 's': list(s), 'col': list(col), 't': 0, 'm': m, 'sh': 'Block',
            'c': 'Part', 'n': n}


def noob(pose='shock', yaw=0.0, head=1.2, turn=0.0):
    """The noob at the origin (feet on y=0), facing -z rotated by yaw (so a
    camera on -z sees his face). pose: shock (arms flung up, mouth an O),
    punch (right fist thrust forward, left pulled back), flex (both arms up)."""
    Rb = rot_y(yaw)
    out = []
    hip = np.array([0, 2.0, 0])

    def put(local_c, R_local, s, col, n):
        out.append(part(Rb @ local_c, Rb @ R_local, s, col, n=n))

    def limb(shoulder, ax, az, s, col, n, ay=0.0):
        # a limb hanging from `shoulder` (its top), swung ax about x (forward is -x... ) and az about z
        R = rot_y(ay) @ rot_z(az) @ rot_x(ax)
        c = shoulder + R @ np.array([0, -s[1] / 2, 0])
        put(c, R, s, col, n)

    torso_c = hip + np.array([0, 1.0, 0])
    put(torso_c, np.eye(3), (2, 2, 1), BLUE, 'Torso')
    head_c = torso_c + np.array([0, 1.0 + head / 2, 0])
    Rh = rot_y(turn)  # the head turned `turn` from the body (towards the camera)

    def put_head(off, R_local, s, col, n):
        put(head_c + Rh @ off, Rh @ R_local, s, col, n)
    put_head(np.zeros(3), np.eye(3), (head, head, head), YELLOW, 'Head')
    sh_l, sh_r = torso_c + np.array([-1.5, 1.0, 0]), torso_c + np.array([1.5, 1.0, 0])
    fz = -head / 2 - 0.02  # the face (on -z)
    whites = []
    if pose == 'shock':
        limb(sh_l, 0.25, -2.5, (1, 2, 1), YELLOW, 'LeftArm')
        limb(sh_r, 0.25, 2.5, (1, 2, 1), YELLOW, 'RightArm')
        limb(hip + np.array([-0.5, 0, 0]), 0, -0.18, (1, 2, 1), GREEN, 'LeftLeg')
        limb(hip + np.array([0.5, 0, 0]), 0, 0.18, (1, 2, 1), GREEN, 'RightLeg')
        eyes = [(-0.28, 0.13, 0.22, 0.32), (0.28, 0.13, 0.22, 0.32)]
        mouth = (0, -0.3, 0.3, 0.3)
        brows = [(-0.3, 0.42, 0.3, 0.07, 14), (0.3, 0.42, 0.3, 0.07, -14)]
    elif pose == 'punch':
        # the near arm (his right, which faces the camera when he faces
        # right) thrust out level, the other pulled back, a lunge
        put(sh_r + np.array([0.0, -0.35, -1.1]), rot_x(math.radians(-90)), (1, 2, 1), YELLOW, 'RightArm')
        limb(sh_l, math.radians(-28), -0.15, (1, 2, 1), YELLOW, 'LeftArm')
        limb(hip + np.array([-0.5, 0, 0]), math.radians(35), 0, (1, 2, 1), GREEN, 'LeftLeg')
        limb(hip + np.array([0.5, 0, 0]), math.radians(-30), 0, (1, 2, 1), GREEN, 'RightLeg')
        eyes = [(-0.27, 0.08, 0.2, 0.2), (0.27, 0.08, 0.2, 0.2)]
        mouth = (0, -0.27, 0.44, 0.16)
        brows = [(-0.28, 0.3, 0.34, 0.09, -22), (0.28, 0.3, 0.34, 0.09, 22)]
    elif pose == 'roll':
        # tucked into a dodge roll: arms hugging the knees, legs folded up
        limb(sh_l, math.radians(-100), 0.1, (1, 2, 1), YELLOW, 'LeftArm')
        limb(sh_r, math.radians(-100), -0.1, (1, 2, 1), YELLOW, 'RightArm')
        limb(hip + np.array([-0.5, 0, 0]), math.radians(-115), 0, (1, 2, 1), GREEN, 'LeftLeg')
        limb(hip + np.array([0.5, 0, 0]), math.radians(-95), 0, (1, 2, 1), GREEN, 'RightLeg')
        eyes = [(-0.28, 0.1, 0.22, 0.3), (0.28, 0.1, 0.22, 0.3)]
        mouth = (0, -0.28, 0.4, 0.2)
        brows = [(-0.3, 0.38, 0.32, 0.08, 18), (0.3, 0.38, 0.32, 0.08, -18)]
    elif pose == 'dive':
        # diving out of the way: arms thrown forward, legs kicked back
        limb(sh_l, math.radians(-165), -0.12, (1, 2, 1), YELLOW, 'LeftArm')
        limb(sh_r, math.radians(-150), 0.12, (1, 2, 1), YELLOW, 'RightArm')
        limb(hip + np.array([-0.5, 0, 0]), math.radians(25), 0, (1, 2, 1), GREEN, 'LeftLeg')
        limb(hip + np.array([0.5, 0, 0]), math.radians(-10), 0, (1, 2, 1), GREEN, 'RightLeg')
        eyes = [(-0.28, 0.12, 0.22, 0.32), (0.28, 0.12, 0.22, 0.32)]
        mouth = (0, -0.3, 0.42, 0.22)
        brows = [(-0.3, 0.42, 0.32, 0.08, 18), (0.3, 0.42, 0.32, 0.08, -18)]
    elif pose == 'meme':
        # the meme reaction: hands on the cheeks, eyes popping, jaw dropped
        limb(sh_l, math.radians(-150), -0.55, (1, 2, 1), YELLOW, 'LeftArm')
        limb(sh_r, math.radians(-150), 0.55, (1, 2, 1), YELLOW, 'RightArm')
        limb(hip + np.array([-0.5, 0, 0]), 0, -0.25, (1, 2, 1), GREEN, 'LeftLeg')
        limb(hip + np.array([0.5, 0, 0]), 0, 0.25, (1, 2, 1), GREEN, 'RightLeg')
        whites = [(-0.27, 0.16, 0.42, 0.46), (0.27, 0.16, 0.42, 0.46)]
        eyes = [(-0.24, 0.12, 0.1, 0.1), (0.3, 0.2, 0.1, 0.1)]
        mouth = (0, -0.34, 0.4, 0.34)
        brows = [(-0.28, 0.48, 0.34, 0.08, -20), (0.28, 0.48, 0.34, 0.08, 20)]
    else:  # flex
        limb(sh_l, 0, -2.2, (1, 2, 1), YELLOW, 'LeftArm')
        limb(sh_r, 0, 2.2, (1, 2, 1), YELLOW, 'RightArm')
        limb(hip + np.array([-0.5, 0, 0]), 0, -0.12, (1, 2, 1), GREEN, 'LeftLeg')
        limb(hip + np.array([0.5, 0, 0]), 0, 0.12, (1, 2, 1), GREEN, 'RightLeg')
        eyes = [(-0.27, 0.15, 0.2, 0.24), (0.27, 0.15, 0.2, 0.24)]
        mouth = (0, -0.24, 0.56, 0.18)
        brows = []
    k = head / 1.2
    for (x, y, w, h) in whites:
        put_head(np.array([x * k, y * k, fz + 0.01]), np.eye(3), (w * k, h * k, 0.03), (255, 255, 255), 'Eye')
    for (x, y, w, h) in eyes:
        put_head(np.array([x * k, y * k, fz]), np.eye(3), (w * k, h * k, 0.04), INK, 'Eye')
    x, y, w, h = mouth
    put_head(np.array([x * k, y * k, fz]), np.eye(3), (w * k, h * k, 0.04), INK, 'Mouth')
    for (x, y, w, h, ang) in brows:
        put_head(np.array([x * k, y * k, fz]), rot_z(math.radians(ang)), (w * k, h * k, 0.04), INK, 'Eye')
    return out


def moved(parts, offset):
    out = []
    for p in parts:
        q = dict(p)
        q['cf'] = list(np.array(p['cf'][0:3]) + offset) + list(p['cf'][3:12])
        out.append(q)
    return out


# ----------------------------------------------------------------------
# drawing a layer: the game's look, cut out (drawn on black and on white:
# the difference is how see-through each pixel is)
# ----------------------------------------------------------------------
def layer(parts, eye, look, fov, size=SIZE):
    fd.W, fd.H, fd.SS = size, size, 2
    fd.args.scale = 1
    # a key light from over the camera's left shoulder (the faces lit, like a
    # studio shot) instead of the game's sun
    fwd = unit(np.asarray(look, float) - np.asarray(eye, float))
    right = unit(np.cross(fwd, [0, 1, 0]))
    fd.LIGHT = unit(-fwd * 0.8 + np.array([0, 0.9, 0]) - right * 0.45)
    shots = []
    for bg in (0.0, 255.0):
        fd.SKY_TOP = np.array([bg, bg, bg], dtype=np.float32)
        fd.SKY_LOW = np.array([bg, bg, bg], dtype=np.float32)
        img, to_screen = fd.render(parts, np.asarray(eye, float), np.asarray(look, float), fov)
        shots.append(np.asarray(img, dtype=np.float32))
    black, white = shots
    alpha = np.clip(1 - (white - black).mean(axis=2) / 255.0, 0, 1)
    rgb = np.where(alpha[..., None] > 1e-3, black / np.maximum(alpha[..., None], 1e-3), 0)
    out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA'), to_screen


def face_camera(feet, facing, at_h, dist, side=0.0, rise=0.0, pan=0.0):
    """A camera in front of him (facing), `side` across, `rise` up, looking
    at `at_h` up his body; `pan` slides the whole camera across (he moves
    the other way in the picture)."""
    f = unit([facing[0], 0, facing[2]])
    s = np.cross(f, [0, 1, 0])
    look = feet + np.array([0, at_h, 0]) + s * pan
    eye = look + f * dist + s * side + np.array([0, rise, 0])
    return eye, look


# ----------------------------------------------------------------------
# the icon look: saturated, outlined, rim lit, glowing
# ----------------------------------------------------------------------
def punch_up(img, sat=1.25, con=1.08, bright=1.04):
    a = img.getchannel('A')
    rgb = np.asarray(img.convert('RGB'), dtype=np.float32) / 255.0
    grey = rgb.mean(axis=2, keepdims=True)
    rgb = grey + (rgb - grey) * sat
    rgb = (rgb - 0.5) * con + 0.5
    rgb = np.clip(rgb * bright, 0, 1)
    out = Image.fromarray((rgb * 255).astype(np.uint8), 'RGB')
    out.putalpha(a)
    return out


def dilate(mask, r):
    r = max(1, int(round(r)))
    return mask.filter(ImageFilter.MaxFilter(2 * r + 1)) if r <= 3 else \
        mask.filter(ImageFilter.GaussianBlur(r * 0.55)).point(lambda v: 255 if v > 18 else int(v * 255 / 18))


def outlined(img, width=7, color=INK, rim=None, rim_dir=(-1, -1), rim_w=4, glow=None, glow_r=18):
    """The layer with a thick dark outline, an optional rim light (a bright
    edge on the side the light comes from) and an optional soft glow behind."""
    w, h = img.size
    a = img.getchannel('A')
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    if glow is not None:
        g = dilate(a, glow_r * 0.4).filter(ImageFilter.GaussianBlur(glow_r))
        gl = Image.new('RGBA', (w, h), glow + (0,))
        gl.putalpha(g.point(lambda v: int(v * 0.9)))
        out = Image.alpha_composite(out, gl)
    ring = dilate(a, width)
    ol = Image.new('RGBA', (w, h), color + (255,))
    ol.putalpha(ring)
    out = Image.alpha_composite(out, ol)
    body = img.copy()
    if rim is not None:
        dx, dy = int(rim_dir[0] * rim_w), int(rim_dir[1] * rim_w)
        shifted = ImageChops.offset(a, -dx, -dy)
        edge = ImageChops.subtract(a, shifted).filter(ImageFilter.GaussianBlur(1.2))
        rl = Image.new('RGBA', (w, h), rim + (0,))
        rl.putalpha(ImageChops.multiply(edge, a).point(lambda v: int(min(255, v * 0.85))))
        body = Image.alpha_composite(body, rl)
    out = Image.alpha_composite(out, body)
    return out


def rays_bg(size, c_in, c_out, ray, n=18, center=(0.5, 0.5), turn=0.0, ray_alpha=0.22, vignette=0.45):
    """A radial gradient (c_in in the middle to c_out at the edge) with a
    burst of n rays (the colour `ray`), and a dark vignette."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) + 0.5
    cx, cy = center[0] * size, center[1] * size
    dx, dy = xs - cx, ys - cy
    r = np.sqrt(dx * dx + dy * dy) / (size * 0.75)
    t = np.clip(r, 0, 1)[..., None]
    col = np.array(c_in, np.float32) * (1 - t) + np.array(c_out, np.float32) * t
    ang = np.arctan2(dy, dx) + turn
    on = (np.sin(ang * n) > 0).astype(np.float32)
    # soften the ray edges a touch
    on = np.asarray(Image.fromarray((on * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    k = (on * ray_alpha * np.clip(1.2 - r * 0.6, 0, 1))[..., None]
    col = col * (1 - k) + np.array(ray, np.float32) * k
    v = np.clip((r - 0.55) / 0.6, 0, 1)[..., None] * vignette
    col = col * (1 - v)
    return Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')


def font(path, px):
    return ImageFont.truetype(path, max(6, int(px)))


def pop_text(canvas, text, cx, cy, px, top=(255, 245, 120), bottom=(255, 170, 40), stroke=None, angle=0.0,
             shadow=True, path=None):
    """Chunky pop words: a gradient fill, a thick dark stroke, a drop shadow,
    tilted by `angle` degrees, centred on (cx, cy)."""
    f = font(path or ROUND_FONT, px)
    sw = stroke if stroke is not None else max(2, int(px * 0.13))
    pad = sw * 3 + int(px * 0.3)
    l, t, r, b = f.getbbox(text, stroke_width=sw)
    w, h = r - l + pad * 2, b - t + pad * 2
    ox, oy = pad - l, pad - t
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).text((ox, oy), text, font=f, fill=255)
    smask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(smask).text((ox, oy), text, font=f, fill=255, stroke_width=sw, stroke_fill=255)
    grad = np.zeros((h, w, 3), np.float32)
    tt = np.clip((np.arange(h)[:, None] - (oy + t * 0)) / max(1, b - t), 0, 1)[..., None]
    grad[:] = np.array(top, np.float32) * (1 - tt) + np.array(bottom, np.float32) * tt
    fill = Image.fromarray(grad.astype(np.uint8), 'RGB').convert('RGBA')
    fill.putalpha(mask)
    # a glossy band across the top half of the letters
    gloss = Image.new('RGBA', (w, h), (255, 255, 255, 0))
    gm = np.zeros((h, w), np.float32)
    gm[: oy + int((b - t) * 0.42) + t, :] = 0.35
    gloss.putalpha(ImageChops.multiply(mask, Image.fromarray((gm * 255).astype(np.uint8))))
    tile = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    if shadow:
        sh = Image.new('RGBA', (w, h), INK + (0,))
        sh.putalpha(smask.point(lambda v: int(v * 0.55)))
        tile = Image.alpha_composite(tile, ImageChops.offset(sh, int(sw * 0.4), int(sw * 0.9)))
    st = Image.new('RGBA', (w, h), INK + (0,))
    st.putalpha(smask)
    tile = Image.alpha_composite(tile, st)
    tile = Image.alpha_composite(tile, fill)
    tile = Image.alpha_composite(tile, gloss)
    if angle:
        tile = tile.rotate(angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(tile, (int(cx - tile.width / 2), int(cy - tile.height / 2)))


def star_burst(canvas, cx, cy, r_out, r_in, n=12, fill=(255, 255, 255), outline=INK, width=5, turn=0.0):
    pts = []
    for i in range(n * 2):
        a = math.pi * i / n + turn
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d = ImageDraw.Draw(canvas)
    d.polygon(pts, fill=fill + (255,), outline=outline + (255,), width=width)


def sparkle(canvas, cx, cy, r, col=(255, 255, 255)):
    d = ImageDraw.Draw(canvas)
    w = max(1, r * 0.28)
    d.polygon([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w), (cx, cy + r), (cx - w, cy + w),
               (cx - r, cy), (cx - w, cy - w)], fill=col + (255,))


def health_bar(canvas, x, y, w, h, share, name=None):
    d = ImageDraw.Draw(canvas)
    o = max(2, int(h * 0.22))
    d.rectangle((x - o, y - o, x + w + o, y + h + o), fill=INK + (255,))
    d.rectangle((x, y, x + w, y + h), fill=(70, 20, 34, 255))
    fw = int(w * share)
    d.rectangle((x, y, x + fw, y + h), fill=(229, 59, 68, 255))
    d.rectangle((x, y, x + fw, y + int(h * 0.35)), fill=(255, 120, 120, 255))
    if name:
        f = font(PIXEL_FONT, h * 0.9)
        d.text((x + 2, y - o - h * 1.25), name, font=f, fill=(255, 255, 255, 255), stroke_width=max(1, int(h * 0.18)),
               stroke_fill=INK + (255,))


def place(canvas, layer_img, x, y):
    canvas.alpha_composite(layer_img, (int(x), int(y)))


def finish(canvas):
    """The last touch: Roblox rounds the corners itself, so the square stays
    square; a thin dark inner frame keeps the edge crisp on any page."""
    return canvas.convert('RGB')


# ----------------------------------------------------------------------
# --preview: every boss pose alone, from the front, whole
# ----------------------------------------------------------------------
BOSSES = ['gridlock', 'gavelgrunt', 'kongo', 'revvington', 'oozark', 'kaze', 'burrowmore', 'petalina', 'scribble',
          'tuber']


def preview():
    tiles = []
    for boss in BOSSES:
        if not os.path.exists(os.path.join(args.scenes, 'icon_%s.txt' % boss)):
            continue
        for pose, (feet, facing, parts) in load_poses(boss).items():
            parts = body_only(parts)
            lo, hi = bbox(parts)
            hgt = max(hi[1] - feet[1], 4)
            eye, look = face_camera(feet, facing, hgt * 0.55, hgt * 1.9, side=hgt * 0.35, rise=hgt * 0.1)
            img, _ = layer(parts, eye, look, 40, size=256)
            bg = Image.new('RGBA', img.size, (90, 120, 200, 255))
            bg.alpha_composite(img)
            ImageDraw.Draw(bg).text((4, 4), '%s %s' % (boss, pose), fill=(255, 255, 255, 255))
            tiles.append(bg)
            print(boss, pose, 'height %.1f' % hgt, 'parts', len(parts))
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 256, rows * 256), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t.convert('RGB'), ((i % cols) * 256, (i // cols) * 256))
    os.makedirs(args.out, exist_ok=True)
    sheet.save(os.path.join(args.out, 'preview.png'))


if __name__ == '__main__' and args.preview:
    preview()
    sys.exit(0)


# ----------------------------------------------------------------------
# the icons
# ----------------------------------------------------------------------
_poses = {}


def body_only(parts):
    return [p for p in parts if p['g'].endswith('Body')]


def boss_layer(boss, pose, at_h, dist, side=0.0, rise=0.0, fov=40, size=SIZE, roll=0.0, pan=0.0):
    """Him alone, from in front: the camera `dist` away, looking at `at_h` up
    his body (studs), `side` across and `rise` up; tilted `roll` degrees."""
    if boss not in _poses:
        _poses[boss] = load_poses(boss)
    feet, facing, parts = _poses[boss][pose]
    parts = body_only(parts)
    eye, look = face_camera(feet, facing, at_h, dist, side, rise, pan)
    img, _ = layer(parts, eye, look, fov, size=size)
    if roll:
        img = img.rotate(roll, resample=Image.BICUBIC)
    return img


def noob_layer(pose, yaw=0.0, size=256, fov=30, dist=16, rise=1.0, at_h=3.4, side=0.0, color=None, head=1.2,
               turn=0.0):
    parts = noob(pose, yaw, head=head, turn=turn)
    if color:
        for p in parts:
            if p['n'] not in ('Eye', 'Mouth'):
                p['col'] = list(color.get(p['n'], p['col']))
    look = np.array([0, at_h, 0.0])
    eye = look + np.array([side, rise, -dist])
    img, _ = layer(parts, eye, look, fov, size=size)
    return img


def crop_to_content(img, pad=48):
    box = img.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    if not box:
        return img
    l, t, r, b = box
    out = Image.new('RGBA', (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    out.alpha_composite(img.crop((l, t, r, b)), (pad, pad))
    return out


def scaled(img, h):
    k = h / img.height
    return img.resize((max(1, int(img.width * k)), max(1, int(h))), Image.LANCZOS)


def soft_light(canvas, cx, cy, rx, ry, col=(255, 255, 220), strength=0.85):
    """A soft pool of light (an ellipse, blurred), to lift what stands in it."""
    m = Image.new('L', canvas.size, 0)
    ImageDraw.Draw(m).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=int(255 * strength))
    m = m.filter(ImageFilter.GaussianBlur(max(rx, ry) * 0.45))
    lt = Image.new('RGBA', canvas.size, col + (0,))
    lt.putalpha(m)
    canvas.alpha_composite(lt)


def icon_A():
    """A GIANT FACE: Gridlock's neon demon-cube roar filling the square,
    looming over a tiny shocked noob, +1s flying."""
    S = SIZE
    c = rays_bg(S, (200, 60, 180), (40, 14, 70), (255, 150, 235), n=16, center=(0.5, 0.42), ray_alpha=0.3)
    face = boss_layer('gridlock', 'roar', at_h=6.2, dist=24, side=2.0, rise=-3.5, fov=40, roll=-5)
    face = punch_up(face, 1.2, 1.1)
    face = outlined(face, width=8 * K, rim=(255, 230, 255), rim_dir=(-1, -1), rim_w=5 * K, glow=(255, 60, 170),
                    glow_r=30 * K)
    place(c, face, 0, -24 * K)
    soft_light(c, S * 0.49, S * 0.86, 120 * K, 70 * K, (255, 250, 210), 0.75)
    n = crop_to_content(noob_layer('shock', yaw=math.radians(25), size=int(420 * K), fov=26, dist=18, rise=1.0, head=1.4))
    n = punch_up(scaled(n, 236 * K), 1.15, 1.05)
    n = outlined(n, width=6 * K, rim=(255, 255, 255), rim_dir=(1, -1), rim_w=3 * K, glow=(255, 255, 255), glow_r=12 * K)
    place(c, n, S * 0.5 - n.width / 2 - 6 * K, S - n.height + 34 * K)
    for (x, y, r) in [(150, 330, 9), (372, 318, 11), (60, 160, 8), (468, 150, 10)]:
        sparkle(c, x * K, y * K, r * K)
    for (x, y, px, ang) in [(92, 408, 96, 12), (424, 400, 86, -12), (452, 258, 54, -8), (62, 262, 50, 8)]:
        pop_text(c, '+1', x * K, y * K, px * K, top=(205, 255, 130), bottom=(40, 205, 85), angle=ang)
    return finish(c)


def icon_B():
    """THE PUNCH: the noob mid-punch into King Gavelgrunt, a white impact
    star, +1s bursting off, his health bar up top."""
    S = SIZE
    c = rays_bg(S, (140, 220, 255), (25, 90, 200), (255, 255, 255), n=20, center=(0.44, 0.52), ray_alpha=0.28)
    king = boss_layer('gavelgrunt', 'laugh', at_h=40, dist=62, side=-14, rise=3, fov=40, size=int(620 * K), pan=3)
    king = punch_up(king, 1.25, 1.08)
    king = outlined(king, width=8 * K, rim=(255, 240, 180), rim_dir=(1, -1), rim_w=5 * K, glow=(255, 255, 255),
                    glow_r=18 * K)
    place(c, king, 0, 10 * K)
    n = crop_to_content(noob_layer('punch', yaw=math.radians(86), turn=math.radians(-50), size=int(460 * K), fov=26, dist=18, rise=1.5,
                                   head=1.4))
    n = punch_up(scaled(n, 290 * K), 1.15, 1.05)
    n = outlined(n, width=6 * K, rim=(255, 255, 255), rim_dir=(-1, -1), rim_w=3 * K, glow=(255, 255, 255), glow_r=12 * K)
    nx, ny = -20 * K, S - n.height + 30 * K
    hx, hy = nx + n.width * 0.86, ny + n.height * 0.36  # where the fist lands
    soft_light(c, hx, hy, 70 * K, 70 * K, (255, 255, 230), 0.5)
    star_burst(c, hx, hy, 84 * K, 42 * K, n=11, fill=(255, 255, 255), width=int(6 * K), turn=0.2)
    star_burst(c, hx, hy, 52 * K, 28 * K, n=11, fill=(255, 225, 70), outline=(255, 225, 70), width=1, turn=0.5)
    star_burst(c, hx, hy, 26 * K, 14 * K, n=8, fill=(255, 140, 40), outline=(255, 140, 40), width=1, turn=0.1)
    place(c, n, nx, ny)
    pop_text(c, '+1', 170 * K, 150 * K, 104 * K, angle=-10)
    pop_text(c, '+1', 300 * K, 92 * K, 60 * K, angle=10)
    pop_text(c, '+1', 66 * K, 250 * K, 56 * K, angle=-4)
    health_bar(c, 40 * K, 26 * K, 432 * K, 22 * K, 0.18)
    return finish(c)


def head_of(boss, pose, at_h, dist, side, rise, fov, w, roll=0.0, glow=None, rim=(255, 255, 255)):
    img = crop_to_content(boss_layer(boss, pose, at_h, dist, side, rise, fov, size=int(512 * K), roll=roll))
    img = punch_up(img, 1.25, 1.08)
    k = w / (img.width - 96)
    img = img.resize((int(img.width * k), int(img.height * k)), Image.LANCZOS)
    return outlined(img, width=6 * K, rim=rim, rim_dir=(-1, -1), rim_w=4 * K, glow=glow, glow_r=12 * K)


def icon_C():
    """BEAT THEM ALL: the Spire's bosses crowding in behind the noob."""
    S = SIZE
    c = rays_bg(S, (255, 175, 90), (120, 30, 130), (255, 240, 170), n=20, center=(0.5, 0.78), ray_alpha=0.25)
    ooz = head_of('oozark', 'wake:1.0', 9, 44, 4, 4, 40, 150 * K)
    place(c, ooz, -36 * K, -26 * K)
    car = head_of('revvington', 'wake:1.0', 3, 26, -8, 4, 40, 170 * K)
    place(c, car, S - car.width + 36 * K, -10 * K)
    grid = head_of('gridlock', 'roar', 6.2, 26, 0, -2, 40, 230 * K, glow=(255, 60, 160))
    place(c, grid, S / 2 - grid.width / 2, -30 * K)
    king = head_of('gavelgrunt', 'laugh', 44, 56, -8, 6, 40, 260 * K)
    place(c, king, -76 * K, S - king.height + 50 * K)
    kong = head_of('kongo', 'mad', 10.5, 18, 3, 1, 40, 250 * K)
    place(c, kong, S - kong.width + 76 * K, S - kong.height + 50 * K)
    n = crop_to_content(noob_layer('flex', yaw=math.radians(0), size=int(420 * K), fov=26, dist=18, rise=1.0, head=1.4))
    n = punch_up(scaled(n, 230 * K), 1.15, 1.05)
    n = outlined(n, width=6 * K, rim=(255, 255, 255), rim_dir=(-1, -1), rim_w=3 * K, glow=(255, 255, 255), glow_r=16 * K)
    place(c, n, S / 2 - n.width / 2, S - n.height + 30 * K)
    return finish(c)


def icon_D():
    """VS: the boss intro splash - the noob against Kongo going bananas, a
    jagged split, a big VS."""
    S = SIZE
    left = rays_bg(S, (90, 200, 255), (20, 70, 190), (255, 255, 255), n=16, center=(0.2, 0.75), ray_alpha=0.22)
    right = rays_bg(S, (255, 110, 90), (150, 20, 50), (255, 220, 160), n=16, center=(0.8, 0.3), ray_alpha=0.22)
    split = Image.new('L', (S, S), 0)
    pts = [(S * 0.62, 0), (S, 0), (S, S), (S * 0.30, S), (S * 0.50, S * 0.58), (S * 0.40, S * 0.52)]
    ImageDraw.Draw(split).polygon(pts, fill=255)
    c = Image.composite(right, left, split)
    kong = boss_layer('kongo', 'mad', at_h=10.0, dist=20, side=4, rise=0.5, fov=46, size=int(720 * K), pan=-0.6, roll=-6)
    kong = outlined(punch_up(kong, 1.25, 1.08), width=8 * K, rim=(255, 230, 200), rim_dir=(1, -1), rim_w=5 * K)
    ImageDraw.Draw(c).line([pts[0], pts[5], pts[4], pts[3]], fill=(255, 255, 255, 255), width=int(12 * K), joint='curve')
    place(c, kong, -60 * K, -60 * K)
    n = crop_to_content(noob_layer('punch', yaw=math.radians(86), turn=math.radians(-50), size=int(500 * K), fov=26, dist=18, rise=1.5,
                                   head=1.4))
    n = punch_up(scaled(n, 330 * K), 1.15, 1.05)
    n = outlined(n, width=7 * K, rim=(255, 255, 255), rim_dir=(-1, -1), rim_w=3 * K, glow=(255, 255, 255), glow_r=12 * K)
    place(c, n, -10 * K, S - n.height + 50 * K)
    pop_text(c, 'VS', 258 * K, 300 * K, 120 * K, top=(255, 250, 170), bottom=(255, 150, 30), angle=8)
    return finish(c)


def icon_E():
    """GROW: the noob towering like a giant over a tiny boss, +1s flying."""
    S = SIZE
    c = rays_bg(S, (255, 225, 100), (235, 95, 30), (255, 255, 220), n=18, center=(0.5, 0.42), ray_alpha=0.3)
    n = crop_to_content(noob_layer('flex', yaw=math.radians(-12), size=int(700 * K), fov=44, dist=10, rise=-4.5,
                                   at_h=3.6, head=1.4))
    n = punch_up(scaled(n, 470 * K), 1.15, 1.05)
    n = outlined(n, width=9 * K, rim=(255, 255, 255), rim_dir=(-1, -1), rim_w=5 * K, glow=(255, 255, 200),
                 glow_r=30 * K)
    place(c, n, S / 2 - n.width / 2, S - n.height + 40 * K)
    tiny = head_of('gridlock', 'roar', 6.2, 26, 0, -2, 40, 104 * K, glow=(255, 60, 160))
    place(c, tiny, 340 * K, S - tiny.height + 14 * K)
    for (x, y, px, ang) in [(84, 120, 92, 10), (432, 112, 76, -10), (70, 310, 56, -6)]:
        pop_text(c, '+1', x * K, y * K, px * K, top=(190, 255, 120), bottom=(40, 200, 80), angle=ang)
    return finish(c)


# ----------------------------------------------------------------------
# round 2: icons that say "boss fight game" at a glance
# ----------------------------------------------------------------------
def transformed(parts, R, pivot, to):
    """Parts turned by R about `pivot`, then moved so the pivot lands on `to`."""
    out = []
    pivot, to = np.asarray(pivot, float), np.asarray(to, float)
    for p in parts:
        q = dict(p)
        c = np.array(p['cf'][0:3])
        Rp = np.array(p['cf'][3:12]).reshape(3, 3)
        q['cf'] = list(R @ (c - pivot) + to) + list((R @ Rp).reshape(-1))
        out.append(q)
    return out


def floor_tiles(center, half, tile, cols=((168, 176, 196), (148, 156, 178)), y=0.0, gap=0.12):
    """A checker of flat stone tiles (the Throne Summit's courtyard look)."""
    out = []
    n = int(half // tile)
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            c = (center[0] + i * tile, y - 0.25, center[2] + j * tile)
            out.append(part(c, np.eye(3), (tile - gap, 0.5, tile - gap), cols[(i + j) % 2], n='Tile'))
    return out


def disc(center, r, col, t=0.0, y=0.05, m='Neon', n='Zone'):
    return {'cf': [center[0], y, center[2], 0, -1, 0, 1, 0, 0, 0, 0, 1], 's': [0.1, 2 * r, 2 * r], 'col': list(col),
            't': t, 'm': m, 'sh': 'Cylinder', 'c': 'Part', 'n': n}


def world_layers(layers, eye, look, fov, size=SIZE):
    """Several groups of parts drawn from one camera, each on its own layer
    (so each can be outlined on its own and still line up)."""
    return [layer(parts, eye, look, fov, size=size)[0] for parts in layers]


def screen_of(pt, eye, look, fov, size=SIZE):
    fwd = unit(np.asarray(look, float) - np.asarray(eye, float))
    right = unit(np.cross(fwd, [0, 1, 0]))
    up = np.cross(right, fwd)
    q = np.asarray(pt, float) - np.asarray(eye, float)
    z = q @ fwd
    f = (size / 2) / math.tan(math.radians(fov) / 2)
    return size / 2 + f * (q @ right) / z, size / 2 - f * (q @ up) / z


def vgrad(size, top, bottom):
    t = np.linspace(0, 1, size)[:, None, None]
    col = np.array(top, np.float32) * (1 - t) + np.array(bottom, np.float32) * t
    return Image.fromarray(np.repeat(col, size, axis=1).astype(np.uint8), 'RGB').convert('RGBA')


def lightning(canvas, x0, y0, x1, y1, seed=3, width=8, col=(235, 240, 255)):
    rng = np.random.default_rng(seed)
    pts = [(x0, y0)]
    nseg = 7
    for i in range(1, nseg):
        t = i / nseg
        pts.append((x0 + (x1 - x0) * t + rng.uniform(-1, 1) * 28 * K, y0 + (y1 - y0) * t))
    pts.append((x1, y1))
    glow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(pts, fill=(170, 190, 255, 200), width=int(width * 3 * K))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10 * K)))
    ImageDraw.Draw(canvas).line(pts, fill=col + (255,), width=int(width * K), joint='curve')


def boss_bar(canvas, name, share, y=18):
    """The game's boss bar, blown up: his name in the pixel font over a fat
    red bar across the top."""
    S = canvas.width
    x, w, h = 22 * K, S - 44 * K, 26 * K
    f = font(PIXEL_FONT, 20 * K)
    d = ImageDraw.Draw(canvas)
    d.text((S / 2, y * K), name, font=f, fill=(255, 255, 255, 255), anchor='mt', stroke_width=int(5 * K),
           stroke_fill=INK + (255,))
    by = y * K + 31 * K
    o = 5 * K
    d.rectangle((x - o, by - o, x + w + o, by + h + o), fill=INK + (255,))
    d.rectangle((x, by, x + w, by + h), fill=(64, 18, 32, 255))
    fw = w * share
    d.rectangle((x, by, x + fw, by + h), fill=(229, 59, 68, 255))
    d.rectangle((x, by, x + fw, by + h * 0.38), fill=(255, 130, 120, 255))
    d.rectangle((x + fw, by, x + fw + 10 * K, by + h), fill=(255, 235, 180, 255))  # the chunk just lost


KING_H, KING_DX = 318, -50
NOOB_YAW, NOOB_PITCH = 38, -34


def icon_F():
    """THE DODGE: King Gavelgrunt winding up his ROYAL SMASH - the gavel
    up behind his head, the red zone on the floor in front of him - and the
    noob dodge-rolling out of it at the last moment (a dust trail, motion
    lines), his boss bar across the top. (The floor, the king and the noob
    are each shot with their own camera, like a poster, so each is big.)"""
    S = SIZE
    feet, facing, parts = load_poses('gavelgrunt')['smash:0.85']
    f = unit([facing[0], 0, facing[2]])
    sidev = np.cross(f, [0, 1, 0])
    ring = [p for p in parts if p['g'] == 'RingPiece']
    rc = np.mean([p['cf'][0:3] for p in ring], axis=0)
    rr = np.mean([np.linalg.norm(np.array(p['cf'][0:3])[[0, 2]] - rc[[0, 2]]) for p in ring])
    zone = [disc(rc, rr + 0.6, (229, 59, 68), t=0.3, y=0.04), disc(rc, rr * 0.55, (255, 110, 110), t=0.5, y=0.06)]
    for p in ring:  # (the game's ring of red bits, fatter and brighter for a phone)
        q = dict(p)
        q['s'] = [p['s'][0] * 1.3, 0.35, p['s'][2] * 2.4]
        q['col'] = [255, 70, 80]
        q['t'] = 0
        zone.append(q)
    floor = floor_tiles(rc, 96, 8)
    # 1) the floor and the zone, from above and in front
    eye = rc + f * 21 + sidev * 3 + np.array([0, 9, 0])
    look = rc + f * -9 + np.array([0, 7.0, 0])
    floor_img, zone_img = world_layers([floor, zone], eye, look, 70)
    zl, zt, zr, zb = zone_img.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
    c = vgrad(S, (30, 26, 96), (196, 96, 170))
    lightning(c, 70 * K, 0, 30 * K, 280 * K, seed=4)
    lightning(c, 480 * K, 0, 505 * K, 240 * K, seed=9, width=6)
    c.alpha_composite(floor_img)
    haze = Image.new('RGBA', (S, S), (140, 110, 185, 0))
    hy = screen_of(rc - f * 150, eye, look, 70)[1]
    hm = Image.new('L', (S, S), 0)
    ImageDraw.Draw(hm).rectangle((0, hy - 50 * K, S, hy + 40 * K), fill=220)
    haze.putalpha(hm.filter(ImageFilter.GaussianBlur(30 * K)))
    c.alpha_composite(haze)
    c.alpha_composite(zone_img.filter(ImageFilter.GaussianBlur(12 * K)))
    c.alpha_composite(zone_img)
    zcx, zcy = (zl + zr) / 2, (zt + zb) / 2
    rng = np.random.default_rng(7)
    d = ImageDraw.Draw(c)
    for i in range(9):  # the floor already cracking under the blow to come
        a = 2 * math.pi * i / 9 + rng.uniform(-0.2, 0.2)
        pts = [(zcx, zcy)]
        r = 0
        while r < 0.95:
            r += rng.uniform(0.18, 0.3)
            aa = a + rng.uniform(-0.25, 0.25)
            pts.append((zcx + math.cos(aa) * r * (zr - zl) / 2, zcy + math.sin(aa) * r * (zb - zt) / 2))
        d.line(pts, fill=(90, 14, 30, 255), width=int(4 * K), joint='curve')
    # 2) the king, three-quarters on, the gavel up behind him
    kcam = dict(at_h=33, dist=50, side=46, rise=2, fov=50, size=int(640 * K))
    raw = boss_layer('gavelgrunt', 'smash:0.85', **kcam)
    # where his gavel head is in that shot (drawn alone with the same camera)
    gpts = [p for p in body_only(parts) if p['n'].startswith('Gavel')]
    gfeet = load_poses('gavelgrunt')['smash:0.85'][0]
    geye, glook = face_camera(gfeet, facing, kcam['at_h'], kcam['dist'], kcam['side'], kcam['rise'])
    gimg = layer(gpts, geye, glook, kcam['fov'], size=kcam['size'])[0]
    l, t, r, b = raw.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    gl, gt, gr, gb = gimg.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    king = crop_to_content(raw)
    k = KING_H * K / (king.height - 96)
    king = king.resize((int(king.width * k), int(king.height * k)), Image.LANCZOS)
    king = outlined(punch_up(king, 1.25, 1.08), width=7 * K, rim=(255, 225, 160), rim_dir=(1, -1), rim_w=5 * K,
                    glow=(255, 70, 90), glow_r=18 * K)
    feet_y = zt + 30 * K
    kx, ky = (zl + zr) / 2 - king.width / 2 + KING_DX * K, feet_y - king.height + 48 * k
    gx = kx + (48 + (gl + gr) / 2 - l) * k
    gy = ky + (48 + (gt + gb) / 2 - t) * k
    # a glow round the raised gavel (its runes lit), then the king
    soft_light(c, gx - 20 * K, gy - 14 * K, 80 * K, 80 * K, (255, 236, 140), 1.0)
    place(c, king, kx, ky)
    # 3) the noob, tumbling out over the zone's left edge towards us
    nb = noob('dive', 0.0, head=1.4)
    nb = transformed(nb, rot_y(math.radians(NOOB_YAW)) @ rot_x(math.radians(NOOB_PITCH)), (0, 2.6, 0), (0, 3.4, 0))
    ncam = (np.array([0, 5.0, -16.0]), np.array([0, 2.6, 0]))
    kid = crop_to_content(layer(nb, ncam[0], ncam[1], 32, size=int(460 * K))[0])
    kid = punch_up(scaled(kid, 250 * K), 1.15, 1.05)
    nx, ny = 408 * K, 392 * K  # where he lands in the picture (his middle)
    d = ImageDraw.Draw(c)
    # the dust trail back into the zone, and speed lines
    for k_, (dx, dy, r) in enumerate([(70, -8, 30), (130, -20, 24), (182, -30, 19), (226, -38, 14)]):
        px, py = nx - dx * K, ny + 40 * K + dy * K
        d.ellipse((px - r * K, py - r * K * 0.62, px + r * K, py + r * K * 0.62), fill=(238, 228, 216, 235),
                  outline=INK + (255,), width=int(4 * K))
    for (oy, x0, ln) in [(-46, 70, 150), (-18, 92, 190), (10, 84, 160), (38, 74, 110)]:
        d.line((nx - x0 * K, ny + oy * K, nx - (x0 + ln) * K, ny + (oy - ln * 0.16) * K), fill=(255, 255, 255, 240),
               width=int(7 * K))
    kid = outlined(kid, width=6 * K, rim=(255, 255, 255), rim_dir=(1, -1), rim_w=3 * K, glow=(255, 255, 255),
                   glow_r=12 * K)
    place(c, kid, nx - kid.width / 2, ny - kid.height / 2)
    boss_bar(c, 'KING GAVELGRUNT', 0.42)
    return finish(c)


def local_frame(feet, facing):
    """His own axes: x across (the camera's right as we face him), y up,
    z forward."""
    f = unit([facing[0], 0, facing[2]])
    sv = np.cross(f, [0, 1, 0])
    return np.asarray(feet, float), np.stack([sv, [0, 1, 0], f], axis=1)


def grafted(parts, src, dst, offset=(0, 0, 0), scale=1.0, R=np.eye(3)):
    """Parts taken off one boss (src frame) and put on another (dst frame):
    turned by R and scaled in his own axes, then moved by `offset` (dst axes)."""
    (o1, B1), (o2, B2) = src, dst
    out = []
    for p in parts:
        q = dict(p)
        c = B1.T @ (np.array(p['cf'][0:3]) - o1)
        Rp = B1.T @ np.array(p['cf'][3:12]).reshape(3, 3)
        c = R @ c * scale + np.asarray(offset, float)
        q['cf'] = list(o2 + B2 @ c) + list((B2 @ R @ Rp).reshape(-1))
        q['s'] = [v * scale for v in p['s']]
        out.append(q)
    return out


def named(parts, names):
    return [p for p in parts if p['n'] in names]


def deep_fry(img, sat=1.7, con=1.35, noise=10, sharpen=2):
    """The meme look: colours turned up too far, crunchy contrast, a little grain."""
    img = punch_up(img.convert('RGBA'), sat, con, 1.03)
    for _ in range(sharpen):
        img = img.filter(ImageFilter.SHARPEN)
    arr = np.asarray(img.convert('RGB'), np.float32)
    arr += np.random.default_rng(5).normal(0, noise, arr.shape)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')


def meme_text(canvas, text, cx, cy, px, angle=0.0, fill=(255, 255, 255), stroke=12):
    """Meme caps: white with a fat black stroke (the round font stands in)."""
    pop_text(canvas, text, cx, cy, px, top=fill, bottom=fill, stroke=int(stroke * K), angle=angle)


MASH = {'arms': (0.6, -7.0, 0.5, 1.2, 48), 'crown': (-1.4, 0.62)}


def mashup():
    """THE MASH-UP: Speedy Revvington with Kongo's gorilla arms and King
    Gavelgrunt's crown on his roof."""
    car_feet, car_face, car = load_poses('revvington')['wake:1.0']
    kf, kface, kong = load_poses('kongo')['wake:0.8']
    gf, gface, king = load_poses('gavelgrunt')['laugh']
    car = body_only(car)
    dst = local_frame(car_feet, car_face)
    roof_y = max(p['cf'][1] + p['s'][1] / 2 for p in car if p['n'] in ('Roof', 'Cabin')) - car_feet[1]
    arms = named(body_only(kong), {'Shoulder', 'UpperArm', 'ForeArm', 'Hand'})
    out = list(car)
    src = local_frame(kf, kface)
    o1, B1 = src
    ax, ay, az, asc, tilt = MASH['arms']
    for side in (-1, 1):  # each arm bolted to a side of the car, swung up and out
        mine = [p for p in arms if (B1.T @ (np.array(p['cf'][0:3]) - o1))[0] * side > 0]
        sh = np.array([3.9 * side, 9.2, 0.0])  # (his shoulder, in his own axes)
        R = rot_z(math.radians(tilt * side)) @ rot_y(math.radians(90 * side))
        moved_in = []
        for p in mine:
            q = dict(p)
            c = B1.T @ (np.array(p['cf'][0:3]) - o1)
            q['cf'] = list(o1 + B1 @ (R @ (c - sh) + sh)) + list((B1 @ R @ B1.T @ np.array(p['cf'][3:12]).reshape(3, 3)).reshape(-1))
            moved_in.append(q)
        out += grafted(moved_in, src, dst, offset=(ax * side, ay, az), scale=asc)
    crown = named(body_only(king), {'Crown', 'CrownPoint', 'CrownGem'})
    cz, csc = MASH['crown']
    cy = min(p['cf'][1] for p in crown) - gf[1]
    out += grafted(crown, local_frame(gf, gface), dst, offset=(0, roof_y - cy * csc - 0.2, cz), scale=csc)
    return car_feet, car_face, out


def icon_G():
    """BRAINROT: a meme-style mash-up boss - Revvington the car with Kongo's
    arms and King Gavelgrunt's crown - over a noob with a huge popping-eyed
    reaction face, clashing colours, deep-fried, BOSS??? in fat caps."""
    S = SIZE
    c = rays_bg(S, (190, 255, 60), (255, 40, 170), (255, 255, 120), n=14, center=(0.6, 0.4), ray_alpha=0.45,
                vignette=0.2)
    feet, face, parts = mashup()
    eye, look = face_camera(feet, face, 5.5, 26, side=-9, rise=4)
    mon = crop_to_content(layer(parts, eye, look, 44, size=int(560 * K))[0])
    mon = outlined(punch_up(scaled(mon, 420 * K), 1.3, 1.1), width=8 * K, rim=(255, 255, 255), rim_dir=(-1, -1),
                   rim_w=5 * K, glow=(255, 255, 255), glow_r=14 * K)
    mx, my = S - mon.width + 60 * K, 0
    place(c, mon, mx, my)
    mcx, mcy = mx + mon.width / 2, my + mon.height / 2
    n = crop_to_content(noob_layer('meme', yaw=math.radians(-18), size=int(520 * K), fov=26, dist=15, rise=0.5,
                                   head=1.9, at_h=4.2))
    n = punch_up(scaled(n, 330 * K), 1.2, 1.08)
    n = outlined(n, width=7 * K, rim=(255, 255, 255), rim_dir=(1, -1), rim_w=3 * K)
    place(c, n, -50 * K, S - n.height + 70 * K)
    c = deep_fry(c)
    d = ImageDraw.Draw(c)
    r = 150 * K
    d.ellipse((mcx - r * 1.1, mcy - r - 10 * K, mcx + r * 1.1, mcy + r - 10 * K), outline=(255, 20, 20, 255),
              width=int(9 * K))
    meme_text(c, 'BOSS???', S / 2, 450 * K, 92 * K, angle=-4)
    return finish(c)


def spire_parts(tiers=4, tier_h=11.0, w0=28.0, w1=16.0, roof=False):
    """THE SPIRE as blocks: stone tiers getting narrower as they go up, each
    with a ledge, battlements and a glowing window - the game's chunky look."""
    out = []
    y = 0.0
    stone = [(86, 98, 136), (104, 116, 156)]
    for i in range(tiers):
        w = w0 + (w1 - w0) * i / max(1, tiers - 1)
        out.append(part((0, y + tier_h / 2, 0), np.eye(3), (w, tier_h, w), stone[i % 2], n='Tier'))
        # bands of darker blocks (masonry)
        for k in range(1, 3):
            out.append(part((0, y + tier_h * k / 3, -w / 2 - 0.05), np.eye(3), (w + 0.1, 0.35, 0.2), (58, 68, 102),
                            n='Band'))
        ledge = w + 3.0
        out.append(part((0, y + tier_h + 0.5, 0), np.eye(3), (ledge, 1.0, ledge), (139, 155, 180), n='Ledge'))
        n = 5
        for j in range(n):  # battlements along the front edge
            x = -ledge / 2 + ledge * (j + 0.5) / n
            out.append(part((x, y + tier_h + 1.6, -ledge / 2 + 0.6), np.eye(3), (ledge / n * 0.55, 1.4, 1.2),
                            (139, 155, 180), n='Merlon'))
        out.append(part((0, y + tier_h * 0.45, -w / 2 - 0.1), np.eye(3), (w * 0.22, tier_h * 0.45, 0.2),
                        (254, 231, 97), m='Neon', n='Window'))
        y += tier_h + 1.0
    if roof:  # the tip: a red roof spike
        out.append(part((0, y + 4, 0), np.eye(3), (w1 * 0.7, 8, w1 * 0.7), (162, 38, 51), n='Roof'))
    return out, tier_h + 1.0


def floor_badge(canvas, text, cx, cy, px, col=(255, 255, 255), bg=INK):
    f = font(PIXEL_FONT, px)
    d = ImageDraw.Draw(canvas)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    w, h = r - l, b - t
    pad = px * 0.45
    d.rounded_rectangle((cx - w / 2 - pad, cy - h / 2 - pad, cx + w / 2 + pad, cy + h / 2 + pad), px * 0.35,
                        fill=bg + (255,), outline=(255, 255, 255, 255), width=max(2, int(px * 0.16)))
    d.text((cx - w / 2 - l, cy - h / 2 - t), text, font=f, fill=col + (255,))


def cutout(boss, pose, at_h, dist, side, rise, fov, h, glow=None, rim=(255, 255, 255)):
    img = crop_to_content(boss_layer(boss, pose, at_h, dist, side, rise, fov, size=int(512 * K)))
    k = h / (img.height - 96)
    img = img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)
    img = punch_up(img, 1.25, 1.08)
    return outlined(img, width=6 * K, rim=rim, rim_dir=(-1, -1), rim_w=4 * K, glow=glow, glow_r=12 * K), 48 * k


SPIRE_LOOK, SPIRE_FOV = 40.2, 12.9


def icon_H():
    """THE SPIRE: the tower of bosses, each floor scarier and bigger than the
    last - Oozark on floor 1, Revvington on 5, Kongo on 7, King Gavelgrunt
    on top at 10 in the storm - and the tiny noob at its foot looking up."""
    S = SIZE
    c = vgrad(S, (46, 30, 92), (255, 150, 80))
    rays = rays_bg(S, (255, 235, 180), (255, 235, 180), (255, 255, 255), n=14, center=(0.5, 0.12), ray_alpha=1.0,
                   vignette=0)
    rm = np.asarray(rays.convert('L'), np.float32)
    rm = ((rm > 250) * 60).astype(np.uint8)
    rl = Image.new('RGBA', (S, S), (255, 240, 200, 0))
    rl.putalpha(Image.fromarray(rm))
    c.alpha_composite(rl)
    lightning(c, 60 * K, 0, 110 * K, 170 * K, seed=2, width=6)
    lightning(c, 470 * K, 0, 420 * K, 150 * K, seed=8, width=6)
    tower, step_h = spire_parts()
    eye, look = np.array([0, 8.0, -300.0]), np.array([0, SPIRE_LOOK, 0])
    fov = SPIRE_FOV
    t_img = layer(tower, eye, look, fov)[0]
    t_img = outlined(punch_up(t_img, 1.15, 1.05), width=6 * K)
    c.alpha_composite(t_img)
    # the bosses on their floors, bigger and scarier as they go up
    tiers = [(1, 'oozark', 'wake:1.0', (9, 44, 4, 4, 40), 78, '1', -112),
             (2, 'revvington', 'wake:1.0', (3, 24, -6, 4, 40), 80, '5', 104),
             (3, 'kongo', 'mad', (8, 26, 5, 2, 40), 112, '7', -118),
             (4, 'gavelgrunt', 'laugh', (34, 70, -12, 4, 40), 175, '10', 0)]
    for (i, boss, pose, cam, h, label, dx) in tiers:
        ledge_y = i * step_h + 1.0
        x, y = screen_of((0, ledge_y, -10 + i * 0.8), eye, look, fov)
        img, pad = cutout(boss, pose, *cam, h * K, glow=(255, 80, 90) if boss == 'gavelgrunt' else None)
        dx *= K
        top = y - img.height + pad
        if boss == 'gavelgrunt':
            top = max(top, 34 * K - pad)
        place(c, img, x - img.width / 2 + dx, top)
        if boss == 'gavelgrunt':
            floor_badge(c, 'FLOOR 10', x, y + 30 * K, 17 * K, col=(255, 231, 97), bg=(162, 38, 51))
        else:
            bx = x + dx + (img.width / 2 - 40 * K) * (-1 if dx <= 0 else 1)
            floor_badge(c, label, bx, top + pad + 6 * K, 15 * K)
    n = crop_to_content(noob_layer('shock', yaw=math.radians(160), size=int(360 * K), fov=26, dist=18, rise=-2.0,
                                   head=1.4))
    n = punch_up(scaled(n, 140 * K), 1.15, 1.05)
    n = outlined(n, width=5 * K, rim=(255, 255, 255), rim_dir=(1, -1), rim_w=3 * K, glow=(255, 255, 255), glow_r=10 * K)
    place(c, n, S / 2 - n.width / 2, S - n.height + 30 * K)
    return finish(c)


ICONS = {'A': icon_A, 'B': icon_B, 'C': icon_C, 'D': icon_D, 'E': icon_E, 'F': icon_F, 'G': icon_G, 'H': icon_H}
SHEET = ['F', 'G', 'H']  # the icons the review sheet features (round 2)
NAMES = {'A': 'GIANT FACE', 'B': 'THE PUNCH', 'C': 'BEAT THEM ALL', 'D': 'VS SPLASH', 'E': 'GROW', 'F': 'THE DODGE',
         'G': 'BRAINROT', 'H': 'THE SPIRE'}


def rounded(img, r):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), r, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    return out


def sheet(keys):
    """Every icon at 512 (top) and at 150 (below it: the size a phone's
    Charts page shows it), on the Charts page's dark, rounded like Roblox
    rounds them, the concept's name under each small one."""
    bg = (25, 27, 31)
    pad, big, small = 24, 512, 150
    w = pad + len(keys) * (big + pad)
    h = pad + big + pad + small + 70 + pad
    out = Image.new('RGBA', (w, h), bg + (255,))
    d = ImageDraw.Draw(out)
    f = font(ROUND_FONT, 22)
    f2 = font(ROUND_FONT, 15)
    for i, k in enumerate(keys):
        im = Image.open(os.path.join(args.out, 'icon_%s.png' % k)).convert('RGBA')
        x = pad + i * (big + pad)
        out.alpha_composite(rounded(im.resize((big, big), Image.LANCZOS), 24), (x, pad))
        sm = rounded(im.resize((small, small), Image.LANCZOS), 10)
        sx, sy = x + (big - small) // 2, pad + big + pad
        out.alpha_composite(sm, (sx, sy))
        d.text((sx, sy + small + 8), '%s  %s' % (k, NAMES.get(k, '')), font=f, fill=(235, 235, 240, 255))
        d.text((sx, sy + small + 36), 'icon_%s.png' % k, font=f2, fill=(150, 152, 160, 255))
    out.convert('RGB').save(os.path.join(args.out, 'icon_sheet.png'))


if __name__ == '__main__':
    os.makedirs(args.out, exist_ok=True)
    only = [s.strip() for s in args.only.split(',') if s.strip()] or list(ICONS)
    for key in only:
        img = ICONS[key]()
        path = os.path.join(args.out, 'icon_%s.png' % key)
        img.save(path)
        print('saved', path)
    keys = [k for k in SHEET if os.path.exists(os.path.join(args.out, 'icon_%s.png' % k))]
    sheet(keys)
    print('saved', os.path.join(args.out, 'icon_sheet.png'))
