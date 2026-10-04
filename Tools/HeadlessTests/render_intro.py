"""Draws the intro from the snapshots intro_snaps.luau prints (every part
you'd see at four moments, on the real lobby, with the real intro running):
the parts lit by one sun with thin dark edges like the game's 8-bit look,
and what's on the screen on top - the big words in pixel letters, the small
how-to line, Oozlet's bar and the arrow over it. Four pictures in a grid.

    luau intro_snaps.luau > intro_snaps.txt
    python3 render_intro.py intro_snaps.txt ../../Docs/intro_preview.png [--size 800,450]
"""
import json, math, argparse
import numpy as np
from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument('snaps')
ap.add_argument('out')
ap.add_argument('--size', default='800,450')
ap.add_argument('--fov', type=float, default=70)
args = ap.parse_args()
W, H = [int(v) for v in args.size.split(',')]
SS = 2

# ----------------------------------------------------------------------
# the snapshots
# ----------------------------------------------------------------------
snaps = []
cur = None
for line in open(args.snaps):
    if line.startswith('SNAP '):
        bits = line.split()
        cur = {'name': bits[1], 'eye': np.array([float(v) for v in bits[2:5]]),
               'look': np.array([float(v) for v in bits[5:8]]), 'parts': [], 'screen': None}
        snaps.append(cur)
    elif line.startswith('{') and cur is not None:
        cur['parts'].append(json.loads(line))
    elif line.startswith('SCREEN ') and cur is not None:
        words, color, hint, bar, arrow = line[7:].rstrip('\n').split('|')
        cur['screen'] = {
            'words': words, 'color': tuple(int(float(v)) for v in color.split(',')), 'hint': hint,
            'bar': float(bar), 'arrow': np.array([float(v) for v in arrow.split(',')]) if arrow else None,
        }
    elif line.startswith('JUICE ') and cur is not None:
        # the combo counter, and the comic words popping off the slime
        combo, word, pows = (line[6:].rstrip('\n').split('|') + ['', '', ''])[:3]
        cur['juice'] = {'combo': combo, 'word': word, 'pows': []}
        for item in filter(None, pows.split(';')):
            text, col, pos = item.split('@')
            cur['juice']['pows'].append((text, tuple(int(v) for v in col.split(',')),
                                         np.array([float(v) for v in pos.split(',')])))

# ----------------------------------------------------------------------
# pixel letters (5 x 7)
# ----------------------------------------------------------------------
FONT = {
    'A': [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    'B': ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    'C': [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
    'D': ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    'E': ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    'F': ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    'G': [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
    'H': ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    'I': ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
    'J': ["  ###", "   # ", "   # ", "   # ", "#  # ", "#  # ", " ##  "],
    'K': ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
    'L': ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    'M': ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    'N': ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    'O': [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    'P': ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    'Q': [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
    'R': ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    'S': [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    'T': ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    'U': ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    'V': ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    'W': ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"],
    'X': ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    'Y': ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
    'Z': ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    '0': [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    '1': ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    '2': [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    '3': ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
    '4': ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    '5': ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    '6': [" ### ", "#    ", "#    ", "#### ", "#   #", "#   #", " ### "],
    '7': ["#####", "    #", "   # ", "  #  ", "  #  ", "  #  ", "  #  "],
    '8': [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    '9': [" ### ", "#   #", "#   #", " ####", "    #", "    #", " ### "],
    '!': ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "],
    '.': ["     ", "     ", "     ", "     ", "     ", "     ", "  #  "],
    "'": ["  #  ", "  #  ", " #   ", "     ", "     ", "     ", "     "],
    ':': ["     ", "  #  ", "     ", "     ", "     ", "  #  ", "     "],
    '+': ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    '-': ["     ", "     ", "     ", "#####", "     ", "     ", "     "],
    ' ': ["     "] * 7,
}


def text_width(s, px):
    return len(s) * 6 * px - px


def pixel_text(d, s, x, y, px, color, shadow=None, outline=(24, 20, 37)):
    """s drawn with its top-left at (x, y), each letter-pixel px screen pixels"""
    layers = []
    if outline:
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
            layers.append((ox, oy, outline))
    if shadow:
        layers.insert(0, (2, 2, shadow))
    layers.append((0, 0, color))
    for ox, oy, col in layers:
        cx = x
        for ch in s:
            rows = FONT.get(ch.upper(), FONT[' '])
            for ry, row in enumerate(rows):
                for rx, c in enumerate(row):
                    if c == '#':
                        X0 = cx + (rx + ox * 0.35) * px
                        Y0 = y + (ry + oy * 0.35) * px
                        d.rectangle([X0, Y0, X0 + px - 1, Y0 + px - 1], fill=col)
            cx += 6 * px


# ----------------------------------------------------------------------
# drawing the world (the same as render_lobby.py)
# ----------------------------------------------------------------------
LIGHT = np.array([-0.45, 0.8, 0.35])
LIGHT /= np.linalg.norm(LIGHT)
NEAR = 0.5


def render(snap, sky, rng_limit):
    w, h = W * SS, H * SS
    eye, look = snap['eye'], snap['look']
    fwd = look - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = (h / 2) / math.tan(math.radians(args.fov) / 2)
    color = np.zeros((h, w, 3), dtype=np.float32)
    if sky:
        top, bottom = np.array([110, 165, 255]), np.array([200, 225, 255])
        for y in range(h):
            k = min(1, y / (h * 0.6))
            color[y, :, :] = top * (1 - k) + bottom * k
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

    def cyl_faces(c, R, s, sides=24):
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

    for p in snap['parts']:
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
            lim = z * math.tan(math.radians(args.fov) / 2) * (w / h) * 1.05
            if sx > lim or sy > z * math.tan(math.radians(args.fov) / 2) * 1.05:
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
        (sx_, sy_), sz = project(pt)
        return (sx_ / SS, sy_ / SS) if sz > 0 else None
    return img, to_screen


# ----------------------------------------------------------------------
# what's on the screen
# ----------------------------------------------------------------------
PURPLE, INK, WHITE, YELLOW = (104, 56, 108), (24, 20, 37), (255, 255, 255), (254, 231, 97)


def overlay(img, snap, to_screen, caption):
    d = ImageDraw.Draw(img)
    sc = snap['screen']
    if sc and sc['words'].strip():
        px = max(3, min(int(H * 0.085 / 7), int(W * 0.9 / (len(sc['words']) * 6))))
        tw = text_width(sc['words'], px)
        pixel_text(d, sc['words'], (W - tw) / 2, H * 0.22 - 3.5 * px, px, sc['color'],
                   shadow=INK if sc['color'] != YELLOW else PURPLE)
    if sc and sc['hint']:
        px = 2
        tw = text_width(sc['hint'], px)
        pixel_text(d, sc['hint'], (W - tw) / 2, H * 0.31, px, WHITE)
    if sc and sc['bar'] >= 0:
        bw, bh = 300, 44
        x0, y0 = (W - bw) / 2, 14
        d.rectangle([x0, y0, x0 + bw, y0 + bh], fill=(0, 0, 0), outline=WHITE, width=3)
        pixel_text(d, 'OOZLET', x0 + 10, y0 + 7, 2, WHITE, outline=None)
        d.rectangle([x0 + 10, y0 + 26, x0 + bw - 10, y0 + 36], fill=(162, 38, 51))
        d.rectangle([x0 + 10, y0 + 26, x0 + 10 + (bw - 20) * sc['bar'], y0 + 36], fill=(99, 199, 77))
    if sc and sc['arrow'] is not None:
        at = to_screen(sc['arrow'] + np.array([0, 0.6, 0]))
        if at:
            ax, ay = at
            rows = ["#######", " ##### ", "  ###  ", "   #   "]
            p = 4
            for ry, row in enumerate(rows):
                for rx, c in enumerate(row):
                    if c == '#':
                        X0, Y0 = ax + (rx - 3.5) * p, ay + (ry - 2) * p
                        d.rectangle([X0, Y0, X0 + p - 1, Y0 + p - 1], fill=YELLOW)
    j = snap.get('juice')
    if j:
        for text, col, pos in j['pows']:
            at = to_screen(pos)
            if at:
                px = 5 if 'CRIT' in text else 4
                tw = text_width(text, px)
                pixel_text(d, text, at[0] - tw / 2, at[1] - 3.5 * px, px, col, shadow=INK)
        if j['combo']:
            px = 9
            tw = text_width(j['combo'], px)
            pixel_text(d, j['combo'], W * 0.84 - tw / 2, H * 0.36, px, YELLOW, shadow=PURPLE)
            px = 3
            tw = text_width(j['word'], px)
            pixel_text(d, j['word'], W * 0.84 - tw / 2, H * 0.36 + 9 * 8, px, WHITE)
    # the caption strip
    d.rectangle([0, H - 30, W, H], fill=INK)
    pixel_text(d, caption, 12, H - 22, 2, WHITE, outline=None)
    return img


CAPTIONS = {
    'dark': '1  YOU WAKE UP IN THE DARK',
    'roll': '2  THE LESSON: ROLL OUT OF THE RED!',
    'combo': '2B  EVERY PUNCH: POW! COINS! COMBO!',
    'reveal': '3  IT POPS - THE MIST ROLLS BACK',
    'spire': '4  THE SPIRE RISES: OOZARK AWAITS',
}
panels = []
for snap in snaps:
    name = snap['name']
    sky = name == 'spire'
    limit = {'dark': 90, 'roll': 90, 'reveal': 320, 'spire': 800}.get(name, 300)
    img, to_screen = render(snap, sky, limit)
    panels.append(overlay(img, snap, to_screen, CAPTIONS.get(name, name.upper())))
    print('drew', name, len(snap['parts']), 'parts')

cols = 2
rows = (len(panels) + cols - 1) // cols
gap = 6
sheet = Image.new('RGB', (cols * W + (cols + 1) * gap, rows * H + (rows + 1) * gap), (0, 0, 0))
for i, pimg in enumerate(panels):
    r, c = divmod(i, cols)
    sheet.paste(pimg, (gap + c * (W + gap), gap + r * (H + gap)))
sheet.save(args.out)
print('saved', args.out)
