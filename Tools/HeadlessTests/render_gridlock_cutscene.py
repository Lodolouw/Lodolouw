"""Films GRIDLOCK, the Final Beat: every frame gridlock_cutscene.luau printed
(the real Final Beat level, his real body, moves, tiles and screen words, the
player, and the camera), in the game's look (film_draw.py) under the level's
purple void, with the neon glowing. On the player's screen, drawn from what
the real screen code put there: the big pixel words (ATTEMPT 847, DROP IN
3-2-1, DROP!), his word bubbles (SHIP!, CUBE!, HERE IT COMES..., CHECKERS!,
STUNNED! HIT HIM!), the boss bar and the level's % bar - blown up for a
phone. On top: the hook the whole way (THIS ROBLOX BOSS / FIGHTS ON THE
BEAT, pulsing on his beat), a few pops (RUN!, JUMP!, NOPE!, 99%!!, NOOO),
hit sparks, flashes and camera shake. It LOOPS: the clip at 99% cuts
straight to the first frame, the level starting again (a restart, like the
real thing). The sounds are the ones his screen code played (SOUND lines:
Tools/Sounds/out's Gridlock sounds), plus a punch for each hit and a soft
thud and pop when the player is clipped, mixed quietly (peaks at -8 dB)
under whatever music goes on top, wrapping round the loop. 1080 x 1920 (a
YouTube Short), 30 fps.

    luau gridlock_cutscene.luau > gridlock.txt
    python3 render_gridlock_cutscene.py gridlock.txt ../../Docs/animations/gridlock_short.mp4 \\
        --font FredokaOne.ttf --pixel-font PressStart2P.ttf
    ... sheet.png --sheet [--at 0.1,2,...]   (a 3 x 3 contact sheet of film seconds)
    ... seam.png --seam                      (the loop: last frames, first frames)
    ... sound.wav --sound

--font is the game's round font (FredokaOne: the hook and pops), --pixel-font
the game's pixel font (Press Start 2P: his screen words and the % bar);
without them DejaVu Sans Bold / DejaVu Sans Mono Bold stand in.
"""
import json, math, os, sys, argparse, wave, subprocess, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import film_draw as fd  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('out')
ap.add_argument('--sheet', action='store_true', help='a 3 x 3 contact sheet of frames across the film (a PNG)')
ap.add_argument('--seam', action='store_true', help='the last few frames and the first few, in a row (a PNG): the loop')
ap.add_argument('--at', default='', help='with --sheet: the moments to show (film seconds, comma separated)')
ap.add_argument('--frame', type=float, default=None, help='just one frame at this film second (a PNG, full size)')
ap.add_argument('--workers', type=int, default=4)
ap.add_argument('--scale', type=int, default=2, help='draw the world at 1/scale size, then blow it up')
ap.add_argument('--sound', action='store_true', help='just the sound effects (a WAV)')
ap.add_argument('--silent', action='store_true', help='the video without the sound effects')
ap.add_argument('--font', default='', help='FredokaOne.ttf (the hook and pops)')
ap.add_argument('--pixel-font', default='', help="PressStart2P.ttf (the game's screen words)")
args = ap.parse_args()

OUT_W, OUT_H, FPS = 1080, 1920, 30
W, H = OUT_W // args.scale, OUT_H // args.scale
fd.W, fd.H, fd.SS = W, H, 2
fd.args.scale = args.scale
# the Final Beat's purple void (gridlock_snaps.luau's SKY): dark up high, purple at the horizon
fd.SKY_TOP = np.array([24, 20, 37], dtype=np.float32)
fd.SKY_LOW = np.array([104, 56, 108], dtype=np.float32)
RATE = 44100

ROUND_FONT = args.font if args.font and os.path.exists(args.font) else '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
PIXEL_FONT = args.pixel_font if args.pixel_font and os.path.exists(args.pixel_font) else \
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
SERIF_FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'

# ----------------------------------------------------------------------
# what the scene printed
# ----------------------------------------------------------------------
static, frames, bursts, kicks, events, sounds = [], [], [], [], {}, []
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
               'big': None, 'pct': None, 'bb': []}
        frames.append(cur)
        mode = 'frame'
    elif line.startswith('CAM ') and cur is not None:
        v = [float(x) for x in line.split()[1:8]]
        cur['eye'], cur['look'], cur['fov'] = np.array(v[0:3]), np.array(v[3:6]), v[6]
    elif line.startswith('POS ') and cur is not None:
        v = [float(x) for x in line.split()[1:7]]
        cur['boss'], cur['player'] = np.array(v[0:3]), np.array(v[3:6])
    elif line.startswith('STATE ') and cur is not None:
        b = line.split()
        cur['action'], cur['form'] = b[3], b[4]
    elif line.startswith('BAR ') and cur is not None:
        b = line[4:].strip().split('|')
        cur['hp'] = float(b[1])
    elif line.startswith('BIG ') and cur is not None:
        b = line[4:].rstrip('\n').split('|')
        cur['big'] = {'text': b[0], 'col': tuple(int(x) for x in b[1].split(',')), 'sub': b[2],
                      'subcol': tuple(int(x) for x in b[3].split(',')), 'y': float(b[4]), 'size': int(b[5])}
    elif line.startswith('PCT ') and cur is not None:
        b = line[4:].strip().split('|')
        cur['pct'] = {'text': b[0], 'fill': float(b[1]), 'col': tuple(int(x) for x in b[2].split(','))}
    elif line.startswith('BB ') and cur is not None:
        b = line[3:].rstrip('\n').split('|')
        cur['bb'].append({'name': b[0], 'text': b[1], 'col': tuple(int(x) for x in b[2].split(',')),
                          'stroke': tuple(int(x) for x in b[3].split(',')) if b[3] else None,
                          'pos': np.array([float(x) for x in b[4].split()])})
    elif line.startswith('SOUND '):
        b = line[6:].strip()
        g, rest = b.split(' ', 1)
        name, vol = rest.rsplit('|', 1)
        sounds.append((float(g), name, float(vol)))
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


def ev(name, k=0):
    return events[name][k][0]


def ev_nums(name, k=0):
    return [float(x) for x in events[name][k][1]]


N_FRAMES, GAME_LEN, SLOW_AT, SLOW_GAME, SLOW_RATE, CUT_FROM, CUT_TO, BEAT = ev_nums('loop')
N_FRAMES = int(N_FRAMES)
HOP, HOP_LAND, RING, PORTAL, SWOOP, DROP, DROP_HIT, CHECK, CLIP = ev_nums('times')
MID = np.array(ev_nums('stage')[0:3])
FLOOR = MID[1]
LENGTH = N_FRAMES / FPS
G0 = frames[0]['g'] - frames[0]['s']  # (game clock = s + this)
HITS = [(ev_nums('hit', k)[0], np.array(ev_nums('hit', k)[1:4]), events['hit'][k][0]) for k in range(len(events['hit']))]
CLIP_FILM = ev('clip')
CLIP_POS = np.array(ev_nums('clip')[0:3])
assert len(frames) == N_FRAMES, (len(frames), N_FRAMES)
print('scene:', len(static), 'level parts,', len(frames), 'frames,', len(bursts), 'bursts,', len(sounds), 'sounds,',
      '%.2f s' % LENGTH)


def film_of_s(s):
    """The film second scene time s is on screen (None inside the jump cut)."""
    best = None
    for fr in frames:
        if fr['s'] <= s + 1e-6:
            best = fr['t'] + (s - fr['s'])
        else:
            break
    if CUT_FROM - 1e-6 <= s < CUT_TO - 1e-6:
        return None
    return best if best is not None else s


def frame_at(t):
    return min(N_FRAMES - 1, max(0, int(round(t * FPS))))


# ----------------------------------------------------------------------
# the particles (little blocks), as render_scribble_cutscene.py
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
            col = [min(255, int(x * 1.12 + 28)) for x in b['col']]
            out.append({'n': 'Puff', 'c': 'Part', 's': [size, size, size], 'cf': cf, 'col': col, 'm': 'Neon',
                        'sh': 'Block', 't': min(0.97, 0.2 + 0.72 * u * u)})
    return out


# ----------------------------------------------------------------------
# the camera shake: the game's own knocks (KICK, game time) and the film's
# ----------------------------------------------------------------------
SHAKES = [(g, min(1.0, 0.2 + 0.5 * k), 0.3) for g, k in kicks] + [(G0 + CLIP, 0.6, 0.4)]


def shake(g):
    amp = 0.0
    for at, strength, length in SHAKES:
        if at <= g < at + length:
            amp = max(amp, strength * (1 - (g - at) / length))
    if amp <= 0:
        return np.zeros(3)
    r = np.random.default_rng(int(round(g * 1200)) % 100000 + 7)
    return (r.random(3) - 0.5) * 2 * amp


# ----------------------------------------------------------------------
# the neon glow: the brightest, most coloured pixels, blurred and added
# ----------------------------------------------------------------------
def glow(img):
    a = np.asarray(img).astype(np.float32)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    k = np.clip((mx - 150) / 90, 0, 1) * np.clip((mx - mn) / 120 + 0.25, 0, 1)
    src = Image.fromarray(np.clip(a * k[:, :, None], 0, 255).astype(np.uint8))
    b1 = np.asarray(src.filter(ImageFilter.GaussianBlur(4 / args.scale * 2))).astype(np.float32)
    b2 = np.asarray(src.filter(ImageFilter.GaussianBlur(14 / args.scale * 2))).astype(np.float32)
    out = a + b1 * 0.55 + b2 * 0.45
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


# ----------------------------------------------------------------------
# words
# ----------------------------------------------------------------------
_fonts = {}
_texts = {}


def font(path, size):
    key = (path, int(size))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, max(4, int(size)))
    return _fonts[key]


def text_img(words, path, size, fill, stroke=(24, 20, 37), stroke_w=None, shadow=None):
    """Words as an RGBA picture (outlined; a drop shadow if asked)."""
    key = (words, path, int(size), fill, stroke, stroke_w, shadow)
    if key in _texts:
        return _texts[key]
    f = font(path, size)
    sw = int(round(size * 0.09)) if stroke_w is None else stroke_w
    box = f.getbbox(words, stroke_width=sw)
    pad = sw + 6 + (int(size * 0.08) if shadow else 0)
    w, h = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    im = Image.new('RGBA', (max(1, w), max(1, h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if shadow:
        off = int(size * 0.08)
        d.text((pad - box[0] + off, pad - box[1] + off), words, font=f, fill=shadow + (255,), stroke_width=sw,
               stroke_fill=shadow + (255,))
    d.text((pad - box[0], pad - box[1]), words, font=f, fill=fill + (255,), stroke_width=sw,
           stroke_fill=(stroke + (255,)) if stroke else None)
    _texts[key] = im
    return im


def paste(img, pic, cx, cy, scale=1.0, alpha=1.0, angle=0.0):
    """A picture centred on (cx, cy), scaled, faded, turned."""
    if scale <= 0.01 or alpha <= 0.01:
        return
    if abs(scale - 1) > 1e-3:
        pic = pic.resize((max(1, int(pic.width * scale)), max(1, int(pic.height * scale))), Image.BICUBIC)
    if angle:
        pic = pic.rotate(angle, expand=True, resample=Image.BICUBIC)
    if alpha < 1:
        pic = pic.copy()
        pic.putalpha(pic.getchannel('A').point(lambda v: int(v * alpha)))
    img.alpha_composite(pic, (int(cx - pic.width / 2), int(cy - pic.height / 2)))


def fit(words, path, want, max_w):
    """The biggest size up to `want` at which the words fit in max_w."""
    size = want
    while size > 8 and font(path, size).getlength(words) > max_w:
        size -= 2
    return size


def back_ease(u):
    u = min(1.0, max(0.0, u))
    c = 1.70158
    return 1 + (c + 1) * (u - 1) ** 3 + c * (u - 1) ** 2


def pop_scale(age, big=1.8, length=0.22):
    """TweenService's Back ease from `big` to 1 (the game's pop-in)."""
    if age >= length:
        return 1.0
    return big + (1 - big) * back_ease(age / length)


# ----------------------------------------------------------------------
# the player's screen (as the game draws it, blown up for a phone: 2.6x)
# ----------------------------------------------------------------------
UI = 2.6
INK = (24, 20, 37)
WHITE, YELLOW, CYAN, HOT, MAGENTA = (255, 255, 255), (254, 231, 97), (44, 232, 245), (255, 0, 68), (232, 60, 200)
HUD_TOP = 352  # (the boss bar's top, under the hook)


def when_changed(index, key):
    """How long (film seconds) the screen thing `key` of frame `index` has
    looked as it does now (for its pop-in), and how long until it goes."""
    def sig(fr):
        v = fr.get(key)
        if v is None:
            return None
        return (v['text'], v.get('col'), v.get('sub'))
    me = sig(frames[index])
    i = index
    while i > 0 and sig(frames[i - 1]) == me:
        i -= 1
    j = index
    while j < N_FRAMES - 1 and sig(frames[j + 1]) == me:
        j += 1
    return (index - i) / FPS, (j - index) / FPS, i == 0


def draw_big(img, index):
    big = frames[index]['big']
    if not big:
        return
    age, left, first = when_changed(index, 'big')
    sc = pop_scale(age, 1.35)
    alpha = 1.0 if left > 0.3 or index >= N_FRAMES - 1 else max(0.0, left / 0.3)
    cy = big['y'] * OUT_H
    size = min(big['size'] * UI * 0.85, 86 * UI)
    size = fit(big['text'], PIXEL_FONT, size, OUT_W * 0.9)
    pic = text_img(big['text'], PIXEL_FONT, size, big['col'], INK, stroke_w=max(4, int(size * 0.07)), shadow=INK)
    sc = min(sc, (OUT_W - 16) / pic.width)  # (never off the screen's edges)
    paste(img, pic, OUT_W / 2, cy - 65 * UI * 0.55 + pic.height / 2 * 0.2, sc, alpha)
    if big['sub']:
        ssize = fit(big['sub'], PIXEL_FONT, 26 * UI * 0.85, OUT_W * 0.9)
        sp = text_img(big['sub'], PIXEL_FONT, ssize, big['subcol'], INK, stroke_w=max(3, int(ssize * 0.1)))
        paste(img, sp, OUT_W / 2, cy + 50 * UI * 0.55 + 30, sc, alpha)


def draw_bubbles(img, index, to_screen):
    fr = frames[index]
    shown = {}
    for bb in fr['bb']:
        shown.setdefault(bb['text'], bb)  # (one of each)
    for text, bb in shown.items():
        q = to_screen(bb['pos'])
        if q is None:
            continue
        # how long it's been up (its 0.12 s pop)
        i = index
        while i > 0 and any(b['text'] == text for b in frames[i - 1]['bb']):
            i -= 1
        age = (index - i) / FPS
        s = 0.2 + 0.8 * back_ease(age / 0.12) if age < 0.12 else 1.0
        x = min(max(q[0], 250), OUT_W - 250)
        y = min(max(q[1], 560), OUT_H - 200)
        if bb['name'] == 'GridlockHint':
            # the hint: plain pixel words (flashing a little), no box
            size = fit(text, PIXEL_FONT, 30 * UI * 0.8, 280 * UI * 0.8)
            pic = text_img(text, PIXEL_FONT, size, YELLOW, INK, stroke_w=6)
            a = 1.0 if int(fr['g'] * 6) % 2 == 0 else 0.8
            paste(img, pic, x, y, 1.0, a)
            continue
        bw, bh = int(240 * 2.0 * s), int(58 * 2.0 * s)
        if bw < 4:
            continue
        box = Image.new('RGBA', (bw + 12, bh + 12), (0, 0, 0, 0))
        d = ImageDraw.Draw(box)
        d.rectangle([6, 6, bw + 5, bh + 5], fill=(0, 0, 0, 255), outline=(bb['stroke'] or WHITE) + (255,), width=6)
        size = fit(text, PIXEL_FONT, bh * 0.55, bw - 30)
        t = text_img(text, PIXEL_FONT, size, bb['col'], None, stroke_w=0)
        box.alpha_composite(t, (int((bw + 12 - t.width) / 2), int((bh + 12 - t.height) / 2)))
        paste(img, box, x, y)


def pct_bump(index):
    """A little pop of the % bar when the number changes."""
    p = frames[index]['pct']
    if not p:
        return 1.0
    i = index
    while i > 0 and frames[i - 1]['pct'] and frames[i - 1]['pct']['text'] == p['text']:
        i -= 1
    if i == 0 or not frames[i - 1]['pct']:
        return 1.0
    age = (index - i) / FPS
    return 1.0 + 0.22 * max(0.0, 1 - age / 0.18)


def draw_hud(img, index):
    fr = frames[index]
    d = ImageDraw.Draw(img)
    # the boss bar (BossClient's: his name, a dark red bar)
    bw = int(320 * UI)
    x0 = (OUT_W - bw) // 2
    name = text_img('Gridlock, the Final Beat', SERIF_FONT, int(21 * UI * 0.8), (236, 226, 204), (40, 30, 30), stroke_w=3)
    img.alpha_composite(name, (x0 - 4, HUD_TOP - 10))
    by = HUD_TOP + int(28 * UI * 0.8)
    bh = int(11 * UI * 0.8)
    d.rectangle([x0 - 3, by - 3, x0 + bw + 3, by + bh + 3], fill=(118, 94, 60, 255))
    d.rectangle([x0, by, x0 + bw, by + bh], fill=(22, 14, 12, 255))
    hp = fr.get('hp', 1.0)
    if hp > 0:
        d.rectangle([x0, by, x0 + int(bw * hp), by + bh], fill=(168, 26, 24, 255))
        d.rectangle([x0, by, x0 + int(bw * hp), by + bh // 3], fill=(205, 70, 60, 255))
    # the level's % bar (BossBodies/Gridlock's: a white-edged bar, green fill, the number)
    p = fr['pct']
    if not p:
        return
    sc = pct_bump(index)
    hw, hh = int(320 * UI), int(18 * UI)
    holder = Image.new('RGBA', (hw + 20, hh + 20), (0, 0, 0, 0))
    hd = ImageDraw.Draw(holder)
    barw = hw - int(70 * UI)
    top = 10 + hh // 2 - int(5 * UI)
    hd.rectangle([10 - 5, top - 5, 10 + barw + 5, top + int(10 * UI) + 5], fill=WHITE + (255,))
    hd.rectangle([10, top, 10 + barw, top + int(10 * UI)], fill=INK + (255,))
    if p['fill'] > 0:
        hd.rectangle([10, top, 10 + int(barw * p['fill']), top + int(10 * UI)], fill=p['col'] + (255,))
    size = int(hh * 0.95)
    t = text_img(p['text'], PIXEL_FONT, size, WHITE, INK, stroke_w=4)
    holder.alpha_composite(t, (10 + hw - t.width + 6, 10 + (hh - t.height) // 2 + 2))
    paste(img, holder, OUT_W / 2, HUD_TOP + int((101 - 58) * UI) + hh / 2 + 10, sc)


# ----------------------------------------------------------------------
# on top: the hook, the pops, sparks, flashes
# ----------------------------------------------------------------------
_band = {}


def top_band():
    if 'img' not in _band:
        a = np.zeros((OUT_H, OUT_W), dtype=np.uint8)
        for y in range(0, 560):
            a[y, :] = int(190 * (1 - y / 560) ** 1.2)
        band = Image.new('RGBA', (OUT_W, OUT_H), INK + (0,))
        band.putalpha(Image.fromarray(a))
        _band['img'] = band
    return _band['img']


def beat_phase(s):
    x = s / BEAT
    return x - math.floor(x)


def hook(img, s):
    """THIS ROBLOX BOSS / FIGHTS ON THE BEAT: on top the whole way, the big
    line kicking on every beat of his."""
    img.alpha_composite(top_band())
    l1 = text_img('THIS ROBLOX BOSS', ROUND_FONT, 82, WHITE, INK, stroke_w=9)
    paste(img, l1, OUT_W / 2, 150)
    size = fit('FIGHTS ON THE BEAT', ROUND_FONT, 118, OUT_W - 70)
    k = (1 - beat_phase(s)) ** 4
    col = CYAN if int(math.floor(s / BEAT + 1e-6)) % 2 == 0 else (255, 92, 190)
    l2 = text_img('FIGHTS ON THE BEAT', ROUND_FONT, size, col, INK, stroke_w=11, shadow=(60, 10, 70))
    paste(img, l2, OUT_W / 2, 262, 1.0 + 0.07 * k)


def pop_at(img, words, t, start, length, x, y, size, fill, shadow=INK, rise=60, wobble=0.0):
    a = t - start
    if not (0 <= a < length):
        return
    sc = pop_scale(a, 2.0, 0.16)
    alpha = 1.0 - max(0.0, (a - (length - 0.15)) / 0.15)
    pic = text_img(words, ROUND_FONT, size, fill, INK, stroke_w=int(size * 0.11), shadow=shadow)
    paste(img, pic, x, y - rise * a, sc, alpha, wobble * math.sin(a * 40))


def spark(img, x, y, age, col=(255, 248, 200)):
    """A hit: a white star snapping out."""
    if not (0 <= age < 0.18):
        return
    u = age / 0.18
    r = 34 + 70 * u
    a = int(255 * (1 - u))
    d = ImageDraw.Draw(img)
    for i in range(8):
        ang = i * math.pi / 4 + 0.3
        r0 = r * (0.35 if i % 2 else 0.2)
        d.line([(x + math.cos(ang) * r0, y + math.sin(ang) * r0), (x + math.cos(ang) * r, y + math.sin(ang) * r)],
               fill=col + (a,), width=10 if i % 2 == 0 else 6)


def overlays(img, index, to_screen):
    fr = frames[index]
    t = fr['t']
    s = fr['s']

    def over(pt, dy=-150):
        q = to_screen(pt)
        if q is None:
            return OUT_W / 2, OUT_H * 0.55
        return min(max(q[0], 220), OUT_W - 220), max(600, q[1] + dy)
    P = fr['player']
    # RUN! (their tile lit under them)
    x, y = over(P + np.array([0, 3, 0]))
    pop_at(img, 'RUN!', s, 0.12 * BEAT, 0.75, x, y, 96, WHITE, shadow=HOT)
    # JUMP! (over the ring of spikes)
    pop_at(img, 'JUMP!', s, RING - 0.12, 0.6, x, y - 30, 104, YELLOW, shadow=HOT)
    # NOPE! (out of the swoop's lane)
    sw = SWOOP + 2 * BEAT
    pop_at(img, 'NOPE!', s, sw, 0.7, x, y, 104, WHITE, shadow=(160, 30, 140))
    # hit sparks on every punch
    for pct, pos, film in HITS:
        age = t - film
        if 0 <= age < 0.2:
            q = to_screen(pos)
            if q:
                spark(img, q[0], q[1], age)
    # 99%!! (the last punch) ... and NOOO as the spike gets them
    f99 = [film for pct, pos, film in HITS if pct == 99]
    if f99:
        a = t - f99[0]
        if 0 <= a and t < CLIP_FILM:
            sc = pop_scale(a, 2.2, 0.18) * (1 + 0.05 * math.sin(t * 18))
            pic = text_img('99%!!', ROUND_FONT, 150, YELLOW, INK, stroke_w=14, shadow=(150, 90, 0))
            paste(img, pic, OUT_W / 2, 1540, sc)
    a = t - CLIP_FILM
    if a >= 0:
        sc = pop_scale(a, 1.6, 0.2)
        pic = text_img('99%', ROUND_FONT, 170, (255, 70, 80), INK, stroke_w=16, shadow=(90, 0, 20))
        paste(img, pic, OUT_W / 2 + 8 * math.sin(t * 60) * max(0, 1 - a), 1500, sc, 1.0, -6)
        if a > 0.35:
            pic = text_img('NOOO', ROUND_FONT, 130, WHITE, INK, stroke_w=12, shadow=(200, 0, 40))
            paste(img, pic, OUT_W / 2, 1735, pop_scale(a - 0.35, 2.0, 0.16), 1.0, 4 * math.sin(t * 50))


def frame_image(index):
    fr = frames[index]
    s, g = fr['s'], fr['g']
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts'] + puffs(g)
    jolt = shake(g)
    img, to_screen = fd.render(parts, fr['eye'] + jolt, fr['look'] + jolt * 0.6, fr['fov'])
    img = glow(img)
    img = img.resize((OUT_W, OUT_H), Image.BICUBIC).convert('RGBA')
    draw_bubbles(img, index, to_screen)
    overlays(img, index, to_screen)
    hook(img, s)
    draw_hud(img, index)
    draw_big(img, index)
    img = img.convert('RGB')
    # flashes: THE DROP (white), the clip (red), the restart (a white blink on the first frames)
    t = fr['t']
    drop_film = film_of_s(DROP_HIT)
    for at, strength, col, length in ((drop_film, 0.45, (255, 255, 255), 0.15), (CLIP_FILM, 0.3, (255, 40, 60), 0.2),
                                      (0.0, 0.3, (255, 255, 255), 0.1)):
        if at is not None and at <= t < at + length:
            k = (t - at) / length
            img = Image.blend(img, Image.new('RGB', img.size, col), strength * (1 - k))
    if t >= CLIP_FILM + 0.2:  # (dead: the picture goes a little grey and red)
        a = np.asarray(img).astype(np.float32)
        grey = a.mean(axis=2, keepdims=True)
        a = a * 0.45 + grey * 0.55
        a[:, :, 0] = np.minimum(255, a[:, :, 0] * 1.15 + 12)
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        img = img.convert('RGBA')
        overlays(img, index, to_screen)  # (the words stay bright)
        hook(img, s)
        draw_hud(img, index)
        img = img.convert('RGB')
    return img


# ----------------------------------------------------------------------
# the sound effects: quiet, under the music - and round the loop
# ----------------------------------------------------------------------
SOUNDS = os.path.join(here, '..', 'Sounds', 'out')


def load(name):
    """A game sound (Tools/Sounds/out, or a subfolder: .ogg or .wav), mono floats."""
    import imageio_ffmpeg
    path = None
    for sub in ('', 'weapons', 'bosses'):
        for ext in ('.ogg', '.wav'):
            p = os.path.join(SOUNDS, sub, name + ext)
            if os.path.exists(p):
                path = p
                break
        if path:
            break
    if not path:
        print('no sound', name)
        return np.zeros(1, dtype=np.float32)
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


def thud():
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    f = 95 * np.exp(-t * 9) + 45
    body = np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t * 14)
    slap = lowpass(np.random.default_rng(11).standard_normal(n).astype(np.float32), 2500) * np.exp(-t * 60) * 0.6
    return (body + slap).astype(np.float32)


def blip(f0, f1, seconds=0.12):
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    f = f0 + (f1 - f0) * (t / seconds)
    return (np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t * 22)).astype(np.float32)


def sound_track():
    n = int(round(LENGTH * RATE))
    mix = np.zeros(n, dtype=np.float32)

    def put(x, film, gain):
        """A sound starting at film second `film`, wrapping round the loop."""
        at = int(round(film * RATE)) % n
        x = x * gain
        i = 0
        while i < len(x):
            m = min(len(x) - i, n - at)
            mix[at:at + m] += x[i:i + m]
            i += m
            at = 0
    cache = {}

    def snd(name):
        if name not in cache:
            cache[name] = load(name)
        return cache[name]
    # every sound his screen code played, when it played it
    for g, name, vol in sounds:
        film = film_of_s(g - G0)
        if film is None or g - G0 < -0.05:
            continue
        put(snd(name.replace(' ', '_')), film, vol)
    # ATTEMPT 847 (its sound played a moment before the first frame: here, on it)
    put(snd('Attempt_Start'), 0.0, 0.9)
    # the punches
    for pct, pos, film in HITS:
        put(snd('Fist_Smash'), film, 0.45 if pct < 99 else 0.7)
    # the clip: a thud, a pop
    put(thud(), CLIP_FILM, 0.7)
    put(blip(900, 200, 0.25), CLIP_FILM, 0.35)
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


if __name__ == '__main__':
    import multiprocessing as mp
    if args.sound:
        write_wav(args.out, sound_track())
        print('saved', args.out)
        sys.exit(0)
    if args.frame is not None:
        frame_image(frame_at(args.frame)).save(args.out)
        print('saved', args.out)
        sys.exit(0)
    if args.sheet or args.seam:
        if args.seam:
            picks = list(range(N_FRAMES - 4, N_FRAMES)) + list(range(0, 4))
        else:
            default = (0.1, 0.8, 1.6, 3.4, 4.8, 7.2, 8.0, 10.2, 12.4)
            moments = [float(x) for x in args.at.split(',')] if args.at else default
            picks = [frame_at(x) for x in moments]
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
            tw = 270
            th_ = tw * 16 // 9
            strip = Image.new('RGB', (len(imgs) * (tw + 10) + 10, th_ + 10), (15, 15, 15))
            for i, im in enumerate(imgs):
                strip.paste(im.resize((tw, th_), Image.LANCZOS), (10 + i * (tw + 10), 5))
            strip.save(args.out)
        print('saved', args.out)
        sys.exit(0)
    import imageio_ffmpeg
    silent = args.out if args.silent else os.path.join(tempfile.mkdtemp(), 'silent.mp4')
    writer = imageio_ffmpeg.write_frames(silent, (OUT_W, OUT_H), fps=FPS, quality=None, codec='libx264', macro_block_size=1,
                                         output_params=['-crf', '18', '-preset', 'slow', '-pix_fmt', 'yuv420p',
                                                        '-movflags', '+faststart'])
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
