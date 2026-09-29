"""Paints screens (ScreenGuis) from a test's snapshots (gui_snap.luau): each
SNAP is one panel - its boxes, borders, gradients and words where the game
puts them on a 1280x720 screen - laid out in a grid with captions.

    luau test_arcade_client.luau -a snaps > snaps.txt
    python3 render_gui.py snaps.txt ../../Docs/arcade_screens.png \
        --bg arcade_inside.png --cols 2 --title "THE ARCADE"

  --bg FILE      a picture of the world behind the screen (else dark)
  --font FILE    the game's font (FredokaOne); DejaVu Sans Bold if not given
  --extra FILE "CAPTION"   one more panel: a ready-made picture
  --only N,M     just those snapshots (1 = the first)
A ViewportFrame with a "SnapImage" attribute gets that weapon's picture from
Docs/weapons/<pack>.png (the Slime pack's so far).
"""
import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ap = argparse.ArgumentParser()
ap.add_argument("snaps")
ap.add_argument("out")
ap.add_argument("--bg", default="")
ap.add_argument("--font", default="")
ap.add_argument("--cols", type=int, default=2)
ap.add_argument("--panel", type=int, default=800)  # each panel's width in the picture
ap.add_argument("--title", default="")
ap.add_argument("--extra", nargs=2, action="append", default=[])
ap.add_argument("--only", default="")
args = ap.parse_args()

SW, SH = 1280, 720
SS = 2  # drawn this much bigger, then shrunk (smooth edges)
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT = args.font if args.font and os.path.exists(args.font) else BOLD

_fonts = {}


def font(path, size):
    key = (path, int(size))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, max(1, int(size)))
    return _fonts[key]


# which letters the game font has (the rest are drawn in DejaVu)
_has = {}


def has_glyph(ch):
    if FONT == BOLD:
        return True
    if ch not in _has:
        f = font(FONT, 40)

        def look(c):
            m = f.getmask(c)
            return (m.size, bytes(m))

        _has[ch] = ch.isspace() or look(ch) != look(chr(0xFFFF))
    return _has[ch]


def runs(text):
    out = []
    for ch in text:
        path = FONT if has_glyph(ch) else BOLD
        if out and out[-1][0] == path:
            out[-1][1] += ch
        else:
            out.append([path, ch])
    return out


def text_width(text, size):
    return sum(font(p, size).getlength(t) for p, t in runs(text))


def wrap(text, size, width):
    lines = []
    for para in text.split("\n"):
        words, line = para.split(" "), ""
        for w in words:
            test = (line + " " + w) if line else w
            if text_width(test, size) <= width or not line:
                line = test
            else:
                lines.append(line)
                line = w
        lines.append(line)
    return lines


def fit(text, box, size, wrapped):
    """(font size, lines) so the words fit the box (TextScaled when size is None)"""
    w, h = box[2] - box[0], box[3] - box[1]
    if size is not None:
        return size, (wrap(text, size, w) if wrapped else text.split("\n"))
    lo, hi, best = 4, max(4, int(h * 1.02)), (4, [text])
    while lo <= hi:
        mid = (lo + hi) // 2
        lines = wrap(text, mid, w) if wrapped else text.split("\n")
        tall = len(lines) * mid * 1.05
        wide = max(text_width(l, mid) for l in lines)
        if tall <= h and wide <= w:
            best = (mid, lines)
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def gradient_image(size, keys, rot):
    """an RGBA picture of a UIGradient's colours across `size`"""
    w, h = max(1, int(size[0])), max(1, int(size[1]))
    keys = sorted(keys, key=lambda k: k[0])
    strip_len = 256
    strip = Image.new("RGB", (strip_len, 1))
    px = strip.load()
    for i in range(strip_len):
        t = i / (strip_len - 1)
        a, b = keys[0], keys[-1]
        for j in range(len(keys) - 1):
            if keys[j][0] <= t <= keys[j + 1][0]:
                a, b = keys[j], keys[j + 1]
                break
        span = max(1e-6, b[0] - a[0])
        u = min(1, max(0, (t - a[0]) / span))
        px[i, 0] = tuple(int(a[c + 1] + (b[c + 1] - a[c + 1]) * u) for c in range(3))
    img = strip.resize((w, h)) if int(rot) % 180 == 0 else strip.resize((h, w)).rotate(-90, expand=True).resize((w, h))
    return img.convert("RGBA")


def colour(c, alpha=1.0):
    return (c[0], c[1], c[2], int(255 * max(0.0, min(1.0, alpha))))


def is_axis(pts):
    return abs(pts[0][1] - pts[1][1]) < 0.5 and abs(pts[1][0] - pts[2][0]) < 0.5


def bounds(pts):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def shape_mask(size, pts, radius, grow=0.0, width=0):
    """a mask of the box (or its outline, `width` wide) in picture pixels"""
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    s = [(x * SS, y * SS) for x, y in pts]
    if is_axis(pts):
        x0, y0, x1, y1 = bounds(s)
        g = grow * SS
        box = [x0 - g, y0 - g, x1 + g, y1 + g]
        r = max(0, (radius + grow) * SS)
        if width:
            d.rounded_rectangle(box, radius=r, outline=255, width=max(1, int(width * SS)))
        else:
            d.rounded_rectangle(box, radius=r, fill=255)
    else:
        if width:
            d.line(s + [s[0]], fill=255, width=max(1, int(width * SS)), joint="curve")
        else:
            d.polygon(s, fill=255)
    return m


ICON_IDS = {}  # asset id -> a weapon's key (the test's "ICONMAP id key" lines)
ICON_DIR = os.path.join(REPO, "Tools", "Weapons", "out", "icons")
PACK_PICTURE = {}  # weapon id -> (picture, box) from Docs/weapons


def weapon_picture(wid):
    if not PACK_PICTURE:
        # the Slime pack's sheet: 3 x 2 cards, Common to Secret, left to right
        sheet = os.path.join(REPO, "Docs", "weapons", "slime.png")
        order = ["GooGloves", "Jellyblade", "GelatinHammer", "OozeDaggers", "AcidScythe", "GelatinousEdge"]
        if os.path.exists(sheet):
            img = Image.open(sheet).convert("RGBA")
            for i, key in enumerate(order):
                col, row = i % 3, i // 3
                x0, y0 = 40 + col * 520, 118 + row * 770
                PACK_PICTURE[key] = img.crop((x0 + 10, y0 + 10, x0 + 490, y0 + 680))
    return PACK_PICTURE.get(wid)


def draw_text(layer, item):
    box = [v * SS for v in item["box"]]
    size = item.get("size")
    size = size * SS if size is not None else None
    fsize, lines = fit(item["s"], box, size, item.get("wrap", False))
    line_h = fsize * 1.05
    total = line_h * len(lines)
    ya = item.get("ya", "C")
    y = box[1] if ya == "T" else (box[3] - total if ya == "B" else (box[1] + box[3]) / 2 - total / 2)
    alpha = 1 - item.get("t", 0)
    outline = item.get("outline")
    grad = item.get("grad")
    mask = Image.new("L", layer.size, 0) if grad else None
    d = ImageDraw.Draw(layer)
    md = ImageDraw.Draw(mask) if mask else None
    for line in lines:
        wide = text_width(line, fsize)
        xa = item.get("xa", "C")
        x = box[0] if xa == "L" else (box[2] - wide if xa == "R" else (box[0] + box[2]) / 2 - wide / 2)
        for path, part in runs(line):
            f = font(path, fsize)
            top = y + (fsize * 0.05)
            if outline:
                sw = max(1, int(round(outline[1] * SS)))
                oa = 1 - (outline[2] if len(outline) > 2 and outline[2] is not None else 0)
                d.text((x, top), part, font=f, fill=colour(outline[0], alpha * oa), stroke_width=sw, stroke_fill=colour(outline[0], alpha * oa))
            if md:
                md.text((x, top), part, font=f, fill=int(255 * alpha))
            else:
                d.text((x, top), part, font=f, fill=colour(item["c"], alpha))
            x += f.getlength(part)
        y += line_h
    if mask is not None:
        bx = mask.getbbox()
        if bx:
            g = gradient_image((bx[2] - bx[0], bx[3] - bx[1]), grad["keys"], 0)
            full = Image.new("RGBA", layer.size, (0, 0, 0, 0))
            full.paste(g, (bx[0], bx[1]))
            layer.paste(full, (0, 0), mask)


def clipped(layer, it):
    """cuts a drawn layer to the item's clip box (a scrolling list, a window)"""
    c = it.get("clip")
    if not c:
        return layer
    m = Image.new("L", layer.size, 0)
    ImageDraw.Draw(m).rectangle([c[0] * SS, c[1] * SS, c[2] * SS - 1, c[3] * SS - 1], fill=255)
    a = layer.getchannel("A")
    layer.putalpha(Image.composite(a, Image.new("L", layer.size, 0), m))
    return layer


def paint(items, bg):
    size = (SW * SS, SH * SS)
    img = bg.copy() if bg else Image.new("RGBA", size, (24, 20, 37, 255))
    for it in items:
        kind = it["k"]
        if kind in ("rect", "stroke"):
            layer = Image.new("RGBA", size, (0, 0, 0, 0))
            if kind == "rect":
                m = shape_mask(size, it["pts"], it.get("r", 0))
            else:
                w = it.get("w", 1)
                m = shape_mask(size, it["pts"], it.get("r", 0), grow=w / 2, width=w)
            alpha = 1 - it.get("t", 0)
            if it.get("grad"):
                x0, y0, x1, y1 = m.getbbox() or (0, 0, 1, 1)
                g = gradient_image((x1 - x0, y1 - y0), it["grad"]["keys"], it["grad"].get("rot", 0))
                fill = Image.new("RGBA", size, (0, 0, 0, 0))
                fill.paste(g, (x0, y0))
            else:
                fill = Image.new("RGBA", size, colour(it["c"]))
            m = m.point(lambda v: int(v * alpha))
            layer.paste(fill, (0, 0), m)
            img = Image.alpha_composite(img, clipped(layer, it))
        elif kind == "text":
            layer = Image.new("RGBA", size, (0, 0, 0, 0))
            draw_text(layer, it)
            img = Image.alpha_composite(img, clipped(layer, it))
        elif kind == "img":
            import re
            m = re.search(r"id=(\d+)", it.get("src", ""))
            key = m and ICON_IDS.get(m.group(1))
            path = key and os.path.join(ICON_DIR, key + ".png")
            if path and os.path.exists(path):
                pic = Image.open(path).convert("RGBA")
                x0, y0, x1, y1 = [v * SS for v in bounds(it["pts"])]
                k = min((x1 - x0) / pic.width, (y1 - y0) / pic.height)
                p = pic.resize((max(1, int(pic.width * k)), max(1, int(pic.height * k))), Image.LANCZOS)
                layer = Image.new("RGBA", size, (0, 0, 0, 0))
                layer.paste(p, (int((x0 + x1) / 2 - p.width / 2), int((y0 + y1) / 2 - p.height / 2)), p)
                img = Image.alpha_composite(img, clipped(layer, it))
        elif kind == "image":
            pic = weapon_picture(it["name"])
            if pic:
                x0, y0, x1, y1 = [v * SS for v in bounds(it["pts"])]
                k = min((x1 - x0) / pic.width, (y1 - y0) / pic.height)
                p = pic.resize((max(1, int(pic.width * k)), max(1, int(pic.height * k))), Image.LANCZOS)
                layer = Image.new("RGBA", size, (0, 0, 0, 0))
                layer.paste(p, (int((x0 + x1) / 2 - p.width / 2), int((y0 + y1) / 2 - p.height / 2)), p)
                img = Image.alpha_composite(img, clipped(layer, it))
    return img


# the snapshots
snaps = []
for line in open(args.snaps, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("ICONMAP "):
        _, aid, key = line.split()
        ICON_IDS[aid] = key
    elif line.startswith("SNAP "):
        snaps.append({"caption": line[5:], "items": []})
    elif line.startswith("{") and snaps:
        try:
            snaps[-1]["items"].append(json.loads(line))
        except json.JSONDecodeError:
            pass
if args.only:
    keep = [int(v) for v in args.only.split(",")]
    snaps = [s for i, s in enumerate(snaps, 1) if i in keep]

bg = None
if args.bg:
    bg = Image.open(args.bg).convert("RGBA").resize((SW * SS, SH * SS), Image.LANCZOS)

panels = []
for s in snaps:
    panels.append((s["caption"], paint(s["items"], bg).resize((SW, SH), Image.LANCZOS)))
for path, caption in args.extra:
    panels.append((caption, Image.open(path).convert("RGBA").resize((SW, SH), Image.LANCZOS)))

PW = args.panel
PH = int(PW * SH / SW)
CAP = 64
PAD = 24
TOP = 90 if args.title else PAD
cols = max(1, args.cols)
rows = (len(panels) + cols - 1) // cols
out = Image.new("RGBA", (PAD + cols * (PW + PAD), TOP + rows * (PH + CAP + PAD)), (18, 14, 30, 255))
d = ImageDraw.Draw(out)
if args.title:
    tf = font(FONT, 46)
    d.text((out.width / 2 - text_width(args.title, 46) / 2, 22), args.title, font=tf, fill=(254, 231, 97))
for i, (caption, pic) in enumerate(panels):
    col, row = i % cols, i // cols
    x = PAD + col * (PW + PAD)
    y = TOP + row * (PH + CAP + PAD)
    out.paste(pic.resize((PW, PH), Image.LANCZOS), (x, y))
    d.rectangle([x - 2, y - 2, x + PW + 1, y + PH + 1], outline=(58, 68, 102), width=2)
    head, _, sub = caption.partition("|")
    d.text((x, y + PH + 8), head, font=font(FONT, 26), fill=(255, 255, 255))
    if sub:
        d.text((x, y + PH + 38), sub, font=font(BOLD, 17), fill=(160, 170, 195))
out.convert("RGB").save(args.out)
print("wrote", args.out, out.size)
