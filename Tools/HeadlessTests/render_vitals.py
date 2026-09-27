# Draws the heart, the potion and the bolt from test_vitals.luau's snapshots:
#   luau test_vitals.luau -a snaps > v.txt
#   python3 render_vitals.py v.txt ../../Docs/vitals_preview.png
# Each SNAP is one panel: every square the real module drew (QUAD lines: four
# corners on a 1920x1000 screen, a colour and how see-through it is) and its
# words (TEXT lines), cropped to the bottom middle of the screen, with Hud's
# level bar drawn underneath for context.
#   --cols N     panels per row (2)       --title "..."  the heading
#   --tight      just the three pictures (for the drink, moment by moment)
import sys
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
opts = sys.argv[3:]
cols = int(opts[opts.index("--cols") + 1]) if "--cols" in opts else 2
title = opts[opts.index("--title") + 1] if "--title" in opts else "THE HEART, THE POTION AND THE BOLT"
X0, X1, Y0, Y1 = 600, 1320, 836, 1000  # the part of the screen we show
if "--tight" in opts:
    X0, X1 = 684, 1236  # just the three pictures and their words
SCALE = 2
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

snaps = []
for line in open(src):
    parts = line.rstrip("\n").split(" ")
    if parts[0] == "SNAP":
        snaps.append({"caption": line[5:].strip(), "quads": [], "texts": []})
    elif parts[0] == "QUAD" and snaps:
        n = [float(v) for v in parts[1:9]]
        r, g, b = int(parts[9]), int(parts[10]), int(parts[11])
        snaps[-1]["quads"].append((n, (r, g, b), float(parts[12])))
    elif parts[0] == "TEXT" and snaps:
        x0, y0, x1, y1 = (float(v) for v in parts[1:5])
        size = int(parts[5])
        color = (int(parts[6]), int(parts[7]), int(parts[8]))
        align = parts[9]
        words = " ".join(parts[10:])
        snaps[-1]["texts"].append((x0, y0, x1, y1, size, color, align, words))


def panel(snap):
    w, h = (X1 - X0) * SCALE, (Y1 - Y0) * SCALE
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    # a dim arena floor behind the screen
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(58 + 30 * t), int(52 + 22 * t), int(70 + 10 * t)))
    # Hud's level bar underneath (not part of Vitals - just so you can see where it sits)
    bx0, bx1, by0, by1 = (960 - 320 - X0) * SCALE, (960 + 320 - X0) * SCALE, (1000 - 62 - Y0) * SCALE, (1000 - 16 - Y0) * SCALE
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=8, fill=(46, 38, 22), outline=(24, 20, 37), width=6)
    d.rounded_rectangle([bx0 + 6, by0 + 6, bx0 + int((bx1 - bx0) * 0.62), by1 - 6], radius=6, fill=(254, 174, 52))
    if "--tight" not in opts:
        f = ImageFont.truetype(BOLD, 20 * SCALE // 2 + 6)
        d.text((bx0 + 24, (by0 + by1) // 2), "Beat Floor 3", font=f, fill=(255, 255, 255), anchor="lm", stroke_width=4, stroke_fill=(24, 20, 37))
        d.text((bx1 - 24, (by0 + by1) // 2), "62%", font=f, fill=(255, 255, 255), anchor="rm", stroke_width=4, stroke_fill=(24, 20, 37))
    # every square, see-through ones blended in
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for n, color, see in snap["quads"]:
        pts = [((n[i] - X0) * SCALE, (n[i + 1] - Y0) * SCALE) for i in range(0, 8, 2)]
        over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(over).polygon(pts, fill=color + (int(255 * (1 - see)),))
        layer = Image.alpha_composite(layer, over)
    img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
    d = ImageDraw.Draw(img)
    for x0, y0, x1, y1, size, color, align, words in snap["texts"]:
        font = ImageFont.truetype(BOLD, int(size * SCALE * 0.82))
        cy = ((y0 + y1) / 2 - Y0) * SCALE
        segs = []
        # {RRGGBB}text = a coloured piece (the yellow "HP")
        rest = words
        while rest.startswith("{"):
            hexc, rest = rest[1:7], rest[8:]
            piece, _, rest = rest.partition(" ")
            segs.append((piece + " ", tuple(int(hexc[i:i + 2], 16) for i in (0, 2, 4))))
        segs.append((rest, color))
        total = sum(d.textlength(s, font=font) for s, _ in segs)
        if align == "R":
            x = (x1 - X0) * SCALE - total
        elif align == "L":
            x = (x0 - X0) * SCALE
        else:
            x = ((x0 + x1) / 2 - X0) * SCALE - total / 2
        for s, c in segs:
            d.text((x, cy), s, font=font, fill=c, anchor="lm", stroke_width=5, stroke_fill=(24, 20, 37))
            x += d.textlength(s, font=font)
    return img


pw, ph = (X1 - X0) * SCALE, (Y1 - Y0) * SCALE
cap = 64
rows = (len(snaps) + cols - 1) // cols
head = 110
sheet = Image.new("RGB", (cols * pw + (cols + 1) * 24, head + rows * (ph + cap + 24) + 24), (24, 20, 37))
d = ImageDraw.Draw(sheet)
tf = ImageFont.truetype(BOLD, 52)
d.text((sheet.width // 2, 58), title, font=tf, fill=(254, 231, 97), anchor="mm")
cf = ImageFont.truetype(BOLD, 30)
sf = ImageFont.truetype(BOLD, 24)
for i, snap in enumerate(snaps):
    c, r = i % cols, i // cols
    x = 24 + c * (pw + 24)
    y = head + r * (ph + cap + 24)
    title, _, sub = snap["caption"].partition("|")
    d.text((x + 4, y + 18), title, font=cf, fill=(255, 255, 255), anchor="lm")
    d.text((x + 4 + d.textlength(title + "   ", font=cf), y + 20), sub, font=sf, fill=(192, 203, 220), anchor="lm")
    sheet.paste(panel(snap), (x, y + cap - 20))
sheet.save(out)
print("wrote", out, len(snaps), "panels")
