"""Films KAZE, the Headband Hero: every frame kaze_cutscene.luau printed (the
real Rooftop Dojo, his real body, moves and screen words, the player, and
the camera), in the game's look (film_draw.py) under the dojo's sunset sky,
with the ki glowing. On the player's screen, drawn from what the real screen
code put there: the big pixel words (ROUND 1, FIGHT!, ROUND 2, SUPER! / HIDE
BEHIND A PILLAR!), his word bubbles (HAH!, KAZE-BLAST!, CANCEL!, RISING
DRAGON!, HAAAAA!!, *pant* *pant*, HAAAAAA!!) and the hint over his head
(TIRED! HIT HIM!), the boss bar, his KI METER with its cancel diamonds and
the MAX! that pops beside it, and the white flashes (the Super, the beam) -
blown up for a phone. On top: the hook the whole way (ROBLOX BOSS / BUT IT'S
A FIGHTING GAME), a few pops (ROLL!, 1 HIT LEFT!!, K.O.!, HE HAD 1 HIT
LEFT), hit sparks and camera shake. It LOOPS: the beam catching the player
at 2% cuts straight to the first frame, ROUND 1 again (the fight starting
over). The sounds are the ones his screen code played (SOUND lines), mixed
from Tools/Sounds/out: his own sounds aren't made in this repo (they're
uploaded from elsewhere, and the announcer's stay quiet until added), so each
plays the nearest of the game's own sounds (STAND_INS below); plus a punch
for each hit, a whoosh for each roll and a thud when the beam gets them,
mixed quietly (peaks at -8 dB) under whatever music goes on top, wrapping
round the loop. 1080 x 1920 (a YouTube Short), 30 fps.

    luau kaze_cutscene.luau > kaze.txt
    python3 render_kaze_cutscene.py kaze.txt ../../Docs/animations/kaze_short.mp4 \\
        --font FredokaOne.ttf --pixel-font PressStart2P.ttf
    ... sheet.png --sheet [--at 0.1,2,...]   (a 3 x 3 contact sheet of film seconds)
    ... seam.png --seam                      (the loop: last frames, first frames)
    ... sound.wav --sound

--font is the game's round font (FredokaOne: the hook and pops), --pixel-font
the game's pixel font (Press Start 2P: his screen words and the meter);
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
# the dojo's sunset (kaze_snaps.luau's SKY): pink up high, gold at the horizon
fd.SKY_TOP = np.array([246, 117, 122], dtype=np.float32)
fd.SKY_LOW = np.array([254, 231, 97], dtype=np.float32)
RATE = 44100

ROUND_FONT = args.font if args.font and os.path.exists(args.font) else '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
PIXEL_FONT = args.pixel_font if args.pixel_font and os.path.exists(args.pixel_font) else \
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
SERIF_FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'


def rgb(s):
    return tuple(int(x) for x in s.split(','))


# ----------------------------------------------------------------------
# what the scene printed
# ----------------------------------------------------------------------
static, frames, bursts, kicks, events, sounds, flashes, kipops = [], [], [], [], {}, [], [], []
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
               'big': None, 'ki': None, 'bb': [], 'barname': ''}
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
        cur['state'], cur['action'] = b[1], b[3]
    elif line.startswith('BAR ') and cur is not None:
        b = line[4:].strip('\n').split('|')
        cur['barname'], cur['hp'] = b[0], float(b[1])
    elif line.startswith('BIG ') and cur is not None:
        b = line[4:].rstrip('\n').split('|')
        cur['big'] = {'text': b[0], 'col': rgb(b[1]), 'sub': b[2], 'subcol': rgb(b[3]), 'y': float(b[4]), 'size': int(b[5])}
    elif line.startswith('KI ') and cur is not None:
        b = line[3:].rstrip('\n').split('|')
        bars = []
        for seg in b[0].split(' '):
            f, c, st = seg.split(';')
            bars.append((float(f), rgb(c), rgb(st)))
        cur['ki'] = {'bars': bars, 'max': b[1] == '1', 'diamonds': [None if d == '-' else rgb(d) for d in b[2].split(' ')]}
    elif line.startswith('BB ') and cur is not None:
        b = line[3:].rstrip('\n').split('|')
        cur['bb'].append({'name': b[0], 'text': b[1], 'col': rgb(b[2]), 'stroke': rgb(b[3]) if b[3] else None,
                          'pos': np.array([float(x) for x in b[4].split()])})
    elif line.startswith('SOUND '):
        b = line[6:].strip()
        g, rest = b.split(' ', 1)
        name, vol = rest.rsplit('|', 1)
        sounds.append((float(g), name, float(vol)))
    elif line.startswith('FLASH '):
        b = line.split()
        flashes.append((float(b[1]), float(b[2]), float(b[3])))
    elif line.startswith('KIPOP '):
        b = line[6:].strip()
        g, rest = b.split(' ', 1)
        text, col = rest.split('|')
        kipops.append((float(g), text, rgb(col)))
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


N_FRAMES, SLOW_FROM, SLOW_TO, SLOW_RATE = ev_nums('loop')
N_FRAMES = int(N_FRAMES)
FILM_FROM, BLAST, STRING, BREAK, TIRED, FLARE, SUPER, FIRE = ev_nums('times')
MID = np.array(ev_nums('stage')[0:3])
FLOOR = MID[1]
LENGTH = N_FRAMES / FPS
G0 = frames[0]['g'] - frames[0]['s']  # (game clock = s + this)
HITS = [(ev_nums('hit', k)[0], np.array(ev_nums('hit', k)[1:4]), events['hit'][k][0]) for k in range(len(events['hit']))]
ROLLS = [(e[0], int(e[1][0])) for e in events.get('roll', [])]
CAUGHT_FILM = ev('caught')
CAUGHT_S = ev_nums('caught')[0]
assert len(frames) == N_FRAMES, (len(frames), N_FRAMES)
print('scene:', len(static), 'dojo parts,', len(frames), 'frames,', len(bursts), 'bursts,', len(sounds), 'sounds,',
      '%.2f s' % LENGTH)


def film_of_g(g, before=0.0):
    """The film second game moment g is on screen (None if a jump cut took
    it out); up to `before` seconds ahead of the first frame counts as it."""
    if g < frames[0]['g']:
        return 0.0 if g >= frames[0]['g'] - before else None
    for i in range(len(frames) - 1):
        a, b = frames[i], frames[i + 1]
        if a['g'] <= g < b['g']:
            span = b['s'] - a['s']
            if span > 0.1:  # (a jump cut: only what fits in one frame's time is shown)
                return a['t'] + (g - a['g']) if g - a['g'] < 1 / FPS else None
            return a['t'] + (b['t'] - a['t']) * (g - a['g']) / (b['g'] - a['g'])
    return frames[-1]['t'] if g < frames[-1]['g'] + 1 / FPS else None


def frame_at(t):
    return min(N_FRAMES - 1, max(0, int(round(t * FPS))))


# ----------------------------------------------------------------------
# the particles (little blocks), as render_gridlock_cutscene.py
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
# the camera shake: the game's own knocks (KICK, game time) and the beam's
# ----------------------------------------------------------------------
SHAKES = [(g, min(1.0, 0.2 + 0.5 * k), 0.3) for g, k in kicks] + [(G0 + CAUGHT_S, 0.7, 0.45)]


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
# the ki's glow: the brightest, most coloured pixels, blurred and added
# ----------------------------------------------------------------------
def glow(img):
    a = np.asarray(img).astype(np.float32)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    # (only the ki's cyan and white-hot glows: the sunset's gold and pink stay as they are)
    cyanish = np.clip((a[:, :, 2] - a[:, :, 0]) / 80, 0, 1)
    k = np.clip((mx - 170) / 70, 0, 1) * np.clip((mx - mn) / 120 + 0.2, 0, 1) * cyanish
    src = Image.fromarray(np.clip(a * k[:, :, None], 0, 255).astype(np.uint8))
    b1 = np.asarray(src.filter(ImageFilter.GaussianBlur(4 / args.scale * 2))).astype(np.float32)
    b2 = np.asarray(src.filter(ImageFilter.GaussianBlur(14 / args.scale * 2))).astype(np.float32)
    out = a + b1 * 0.55 + b2 * 0.5
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
WHITE, YELLOW, CYAN, RED, PINK = (255, 255, 255), (254, 231, 97), (44, 232, 245), (228, 59, 68), (246, 117, 122)
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
    sc = pop_scale(age, 1.8)  # (kit.bigText: UIScale 1.8 -> 1, Back)
    alpha = 1.0 if left > 0.3 or index >= N_FRAMES - 1 else max(0.0, left / 0.3)
    cy = big['y'] * OUT_H + 120
    size = min(big['size'] * UI * 0.85, 86 * UI)
    size = fit(big['text'], PIXEL_FONT, size, OUT_W * 0.9)
    pic = text_img(big['text'], PIXEL_FONT, size, big['col'], INK, stroke_w=max(4, int(size * 0.07)), shadow=INK)
    sc = min(sc, (OUT_W - 16) / pic.width)  # (never off the screen's edges)
    paste(img, pic, OUT_W / 2, cy, sc, alpha)
    if big['sub']:
        ssize = fit(big['sub'], PIXEL_FONT, 26 * UI * 0.85, OUT_W * 0.92)
        sp = text_img(big['sub'], PIXEL_FONT, ssize, big['subcol'], INK, stroke_w=max(3, int(ssize * 0.12)))
        paste(img, sp, OUT_W / 2, cy + pic.height * 0.5 + 50, min(sc, 1.3), alpha)


def draw_bubbles(img, index, to_screen):
    fr = frames[index]
    shown = {}
    for bb in fr['bb']:
        shown.setdefault(bb['text'], bb)  # (one of each)
    placed = []
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
        x = min(max(q[0], 270), OUT_W - 270)
        y = min(max(q[1], 780), OUT_H - 260)
        for py in placed:  # (two at once: one above the other)
            if abs(py - y) < 120:
                y = py - 130
        placed.append(y)
        if bb['name'] == 'KazeHint':
            # the hint: plain pixel words (flashing a little), no box
            size = fit(text, PIXEL_FONT, 30 * UI * 0.8, 300 * UI * 0.85)
            pic = text_img(text, PIXEL_FONT, size, YELLOW, INK, stroke_w=6)
            a = 1.0 if int(fr['g'] * 6) % 2 == 0 else 0.75
            paste(img, pic, x, y, 1.0, a)
            continue
        bw, bh = int(240 * 2.0 * s), int(58 * 2.0 * s)
        if bw < 4:
            continue
        box = Image.new('RGBA', (bw + 12, bh + 12), (0, 0, 0, 0))
        d = ImageDraw.Draw(box)
        d.rectangle([6, 6, bw + 5, bh + 5], fill=(0, 0, 0, 255), outline=(bb['stroke'] or WHITE) + (255,), width=6)
        size = fit(text, PIXEL_FONT, bh * 0.5, bw - 34)
        t = text_img(text, PIXEL_FONT, size, bb['col'], None, stroke_w=0)
        box.alpha_composite(t, (int((bw + 12 - t.width) / 2), int((bh + 12 - t.height) / 2)))
        paste(img, box, x, y)


def draw_hud(img, index):
    fr = frames[index]
    if not fr['barname']:
        return
    d = ImageDraw.Draw(img)
    # the boss bar (BossClient's: his name, a dark red bar)
    bw = int(320 * UI)
    x0 = (OUT_W - bw) // 2
    name = text_img(fr['barname'], SERIF_FONT, int(21 * UI * 0.8), (236, 226, 204), (40, 30, 30), stroke_w=3)
    img.alpha_composite(name, (x0 - 4, HUD_TOP - 10))
    by = HUD_TOP + int(28 * UI * 0.8)
    bh = int(11 * UI * 0.8)
    d.rectangle([x0 - 3, by - 3, x0 + bw + 3, by + bh + 3], fill=(118, 94, 60, 255))
    d.rectangle([x0, by, x0 + bw, by + bh], fill=(22, 14, 12, 255))
    hp = fr.get('hp', 1.0)
    if hp > 0:
        d.rectangle([x0, by, x0 + max(3, int(bw * hp)), by + bh], fill=(168, 26, 24, 255))
        d.rectangle([x0, by, x0 + max(3, int(bw * hp)), by + bh // 3], fill=(205, 70, 60, 255))
    # his KI METER (BossBodies/Kaze's: KI, three bars, MAX, the cancel diamonds), under the bar
    ki = fr['ki']
    if not ki:
        return
    mh = int(15 * UI)
    my = by + bh + int(14 * UI)
    kl = text_img('KI', PIXEL_FONT, int(mh * 0.95), CYAN, INK, stroke_w=4)
    img.alpha_composite(kl, (x0 - 6, my + (mh - kl.height) // 2))
    lab_w = int(32 * UI)
    span = int(bw * 0.74)
    for i, (fill, col, stroke) in enumerate(ki['bars']):
        bx0 = x0 + lab_w + int(span * i / 3) + i * 4
        bx1 = x0 + lab_w + int(span * (i + 1) / 3) + i * 4 - 10
        top, bot = my + 5, my + mh - 5
        d.rectangle([bx0 - 5, top - 5, bx1 + 5, bot + 5], fill=stroke + (255,))
        d.rectangle([bx0, top, bx1, bot], fill=INK + (255,))
        if fill > 0.002:
            d.rectangle([bx0, top, bx0 + int((bx1 - bx0) * fill), bot], fill=col + (255,))
    if ki['max']:
        ml = text_img('MAX', PIXEL_FONT, int(mh * 1.25), YELLOW, INK, stroke_w=5)
        paste(img, ml, x0 + lab_w + span / 2, my + mh / 2)
    # the cancel diamonds at the right end
    for i, dcol in enumerate(ki['diamonds']):
        if dcol is None:
            continue
        cx = x0 + bw - int(8 * UI) - (4 - i) * int(15 * UI)
        cy = my + mh // 2
        r = int(6.4 * UI)
        poly = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
        d.polygon(poly, fill=dcol + (255,), outline=INK + (255,))
        d.line(poly + [poly[0]], fill=INK + (255,), width=5)
    # the little +KI / -KI / MAX! that pops up beside the meter (0.7 s, rising)
    g = fr['g']
    for at, text, col in kipops:
        a = g - at
        if 0 <= a < 0.7:
            pic = text_img(text, PIXEL_FONT, int(mh * 1.5), col, INK, stroke_w=5)
            paste(img, pic, x0 + lab_w + 110, my - 18 - a * 12 * UI, 1.0, 1 - a / 0.7)


# ----------------------------------------------------------------------
# on top: the hook, the pops, sparks
# ----------------------------------------------------------------------
_band = {}


def top_band():
    if 'img' not in _band:
        a = np.zeros((OUT_H, OUT_W), dtype=np.uint8)
        for y in range(0, 600):
            a[y, :] = int(200 * (1 - y / 600) ** 1.2)
        band = Image.new('RGBA', (OUT_W, OUT_H), INK + (0,))
        band.putalpha(Image.fromarray(a))
        _band['img'] = band
    return _band['img']


def hook(img, t):
    """ROBLOX BOSS / BUT IT'S A FIGHTING GAME: on top the whole way, the big
    line kicking on every punch."""
    img.alpha_composite(top_band())
    l1 = text_img('ROBLOX BOSS', ROUND_FONT, 92, WHITE, INK, stroke_w=10)
    paste(img, l1, OUT_W / 2, 140)
    words = "BUT IT'S A FIGHTING GAME"
    size = fit(words, ROUND_FONT, 104, OUT_W - 60)
    k = 0.0
    for pct, pos, film in HITS:
        a = t - film
        if 0 <= a < 0.15:
            k = max(k, 1 - a / 0.15)
    l2 = text_img(words, ROUND_FONT, size, YELLOW, INK, stroke_w=11, shadow=(170, 30, 40))
    paste(img, l2, OUT_W / 2, 252, 1.0 + 0.05 * k)


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

    def over(pt, dy=-170):
        q = to_screen(pt)
        if q is None:
            return OUT_W / 2, OUT_H * 0.6
        return min(max(q[0], 230), OUT_W - 230), min(max(700, q[1] + dy), OUT_H - 300)
    P = fr['player']
    # ROLL! (straight through the ball of ki)
    for film, n in ROLLS:
        if n == 1:
            x, y = over(P + np.array([0, 3, 0]))
            pop_at(img, 'ROLL!', t, film + 0.05, 0.7, x, y, 104, WHITE, shadow=(0, 120, 200))
    # hit sparks on every punch
    for pct, pos, film in HITS:
        age = t - film
        if 0 <= age < 0.2:
            q = to_screen(pos)
            if q:
                spark(img, q[0], q[1], age)
    # 1 HIT LEFT!! (the last punch) ... until the beam
    last = [film for pct, pos, film in HITS if pct == max(h[0] for h in HITS)]
    if last:
        a = t - last[0]
        if 0 <= a and t < CAUGHT_FILM:
            sc = pop_scale(a, 2.2, 0.18) * (1 + 0.04 * math.sin(t * 16))
            pic = text_img('1 HIT LEFT!!', ROUND_FONT, 120, YELLOW, INK, stroke_w=12, shadow=(150, 60, 0))
            paste(img, pic, OUT_W / 2, 1660, sc)
    # K.O.! - HE HAD 1 HIT LEFT
    a = t - CAUGHT_FILM
    if a >= 0:
        sc = pop_scale(a, 1.7, 0.2)
        pic = text_img('K.O.!', ROUND_FONT, 210, RED, INK, stroke_w=18, shadow=(90, 0, 20))
        paste(img, pic, OUT_W / 2 + 10 * math.sin(t * 60) * max(0, 1 - a * 2), 1240, sc, 1.0, -5)
        if a > 0.3:
            pic = text_img('HE HAD 1 HIT LEFT', ROUND_FONT, fit('HE HAD 1 HIT LEFT', ROUND_FONT, 96, OUT_W - 80), WHITE, INK,
                           stroke_w=10, shadow=(200, 0, 40))
            sc2 = min(pop_scale(a - 0.3, 2.0, 0.16), (OUT_W - 16) / pic.width)
            paste(img, pic, OUT_W / 2, 1445, sc2, 1.0, 3 * math.sin(t * 40) * max(0, 1 - a))


def frame_image(index):
    fr = frames[index]
    g = fr['g']
    parts = [static_by_index[i] if i not in fr['over'] else fr['over'][i] for i in static_by_index] + fr['parts'] + puffs(g)
    jolt = shake(g)
    img, to_screen = fd.render(parts, fr['eye'] + jolt, fr['look'] + jolt * 0.6, fr['fov'], rng_limit=760)
    img = glow(img)
    img = img.resize((OUT_W, OUT_H), Image.BICUBIC).convert('RGBA')
    t = fr['t']
    dead = t >= CAUGHT_FILM + 0.15
    if dead:  # (caught: the picture goes a little grey and red)
        a = np.asarray(img).astype(np.float32)
        grey = a[:, :, :3].mean(axis=2, keepdims=True)
        a[:, :, :3] = a[:, :, :3] * 0.45 + grey * 0.55
        a[:, :, 0] = np.minimum(255, a[:, :, 0] * 1.15 + 12)
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')
    draw_bubbles(img, index, to_screen)
    hook(img, t)
    draw_hud(img, index)
    draw_big(img, index)
    img = img.convert('RGB')
    # the screen's white flashes (Body._flash: the Super, the beam), the beam
    # catching them (red), the fight starting over (a white blink)
    for at, alpha, length in flashes:
        if at <= g < at + length:
            img = Image.blend(img, Image.new('RGB', img.size, WHITE), alpha * (1 - (g - at) / length))
    for at, strength, col, length in ((CAUGHT_FILM, 0.35, (255, 40, 60), 0.2), (0.0, 0.35, (255, 255, 255), 0.12)):
        if at <= t < at + length:
            img = Image.blend(img, Image.new('RGB', img.size, col), strength * (1 - (t - at) / length))
    img = img.convert('RGBA')
    overlays(img, index, to_screen)
    return img.convert('RGB')


# ----------------------------------------------------------------------
# the sound effects: quiet, under the music - and round the loop
# ----------------------------------------------------------------------
SOUNDS = os.path.join(here, '..', 'Sounds', 'out')
# Kaze's own sounds aren't in this repo (Tools/Sounds makes the other bosses'):
# each plays the nearest of the game's own sounds. The announcer (Round One,
# Round Two, Fight, KO, Perfect) stays quiet, as in the game until it's added.
STAND_INS = {
    'Kaze Wake': ('weapons/Chest_Thump', 0.9), 'Kaze Punch': ('bosses/Guard_Jab', 1.0),
    'Kaze Heavy': ('weapons/Piston_Punch', 1.0), 'Kaze Blast': ('weapons/Flame_Burst', 1.0),
    'Kaze Dragon': ('weapons/Sky_Whoosh', 1.0), 'Kaze Tornado': ('weapons/Whirlwind', 1.0),
    'Kaze Charge': ('Drop_Build', 0.6), 'Kaze Cancel': ('weapons/Spark_Hit', 1.0), 'Kaze Dash': ('bosses/Ink_Dash', 0.8),
    'Kaze Land': ('Cube_Slam', 0.9), 'Kaze Focus': ('Ability_Aura', 1.0), 'Kaze Stagger': ('bosses/Scribble_Dizzy', 0.8),
    'Kaze Pant': ('bosses/Kongo_Pant', 0.9), 'Kaze Super': ('Legendary_Reveal', 0.9), 'Kaze Beam': ('The_Drop', 1.1),
    'Pillar Crumble': ('bosses/Barrel_Break', 1.0), 'Kaze Round Two': ('bosses/Kongo_Rage', 0.7),
}


def load(name):
    """A game sound (Tools/Sounds/out/<name>.ogg or .wav), mono floats."""
    import imageio_ffmpeg
    path = None
    for ext in ('.ogg', '.wav'):
        p = os.path.join(SOUNDS, name + ext)
        if os.path.exists(p):
            path = p
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
        stand = STAND_INS.get(name)
        if not stand:
            continue  # (the announcer: quiet until it's added)
        film = film_of_g(g, before=0.1)
        if film is None:
            continue
        put(snd(stand[0]), film, vol * stand[1])
    # the punches, the rolls, the beam getting them
    for pct, pos, film in HITS:
        put(snd('weapons/Fist_Smash'), film, 0.5 if pct < 98 else 0.75)
    for film, nroll in ROLLS:
        put(snd('bosses/Ink_Dash'), film, 0.45)
    put(thud(), CAUGHT_FILM, 0.8)
    put(snd('weapons/Glitch_Hit'), CAUGHT_FILM, 0.4)
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
            default = (0.05, 1.0, 2.3, 3.7, 4.6, 6.0, 7.6, 9.4, 10.6, 11.6, 12.6, 13.6, 14.4, 15.0)
            moments = [float(x) for x in args.at.split(',')] if args.at else default
            picks = [frame_at(x) for x in moments]
        with mp.Pool(args.workers) as pool:
            imgs = pool.map(frame_image, picks)
        if args.sheet:
            tw, th, gap = 360, 640, 12
            cols = 4 if len(imgs) > 9 else 3
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
