"""Checks the game page thumbnails (Docs/icon/thumb_*.png) before they go
up on Roblox, and draws what they look like where players see them.

    python3 check_thumbs.py [--dir ../../Docs/icon]

The checks (each prints PASS / FAIL):
  * 1920 x 1080 (16:9 - Roblox crops anything else), PNG, RGB (no
    see-through: Roblox shows transparency as black or white)
  * well under the upload size limit (kept below 10 MB)
  * bright and punchy enough to stand out (average brightness, contrast)
  * nothing important hugging the edges: the outer 4% is mostly background
    (the game page's arrows and rounded corners sit there)

The picture (thumb_check.png): each thumbnail as a phone shows it on the game
page (390 wide) and as small as Roblox ever shows one (240 wide), and at full
size with the edge band marked in red - if the words read at 240, they read
everywhere.
"""
import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument('--dir', default=os.path.join(here, '..', '..', 'Docs', 'icon'))
args = ap.parse_args()

paths = sorted(glob.glob(os.path.join(args.dir, 'thumb_[0-9].png')))
if not paths:
    raise SystemExit('no thumbnails in ' + args.dir)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
f_big, f_small = ImageFont.truetype(FONT, 22), ImageFont.truetype(FONT, 15)
failed = 0


def check(ok, what):
    global failed
    print(('PASS  ' if ok else 'FAIL  ') + what)
    failed += 0 if ok else 1


rows = []
for p in paths:
    name = os.path.basename(p)
    im = Image.open(p)
    print('--', name)
    check(im.size == (1920, 1080), '%s: 1920 x 1080 (it is %d x %d)' % (name, im.width, im.height))
    check(im.format == 'PNG' and im.mode == 'RGB', '%s: a PNG with no transparency (%s %s)' % (name, im.format, im.mode))
    mb = os.path.getsize(p) / 1e6
    check(mb < 10, '%s: %.1f MB (under 10 MB)' % (name, mb))
    g = np.asarray(im.convert('L'), np.float32)
    check(g.mean() > 70, '%s: bright enough (average %.0f of 255)' % (name, g.mean()))
    check(g.std() > 40, '%s: punchy contrast (spread %.0f)' % (name, g.std()))
    # the edge band: how much of it is busy detail (edges) compared with the middle
    e = np.abs(np.diff(g, axis=1))[:-1, :] + np.abs(np.diff(g, axis=0))[:, :-1]
    h, w = e.shape
    m = int(min(h, w) * 0.04)
    band = np.concatenate([e[:m, :].ravel(), e[-m:, :].ravel(), e[:, :m].ravel(), e[:, -m:].ravel()])
    mid = e[m:-m, m:-m]
    check(band.mean() < mid.mean() * 1.6, '%s: the edges stay calm (edge detail %.1f vs middle %.1f)' % (name, band.mean(), mid.mean()))
    rows.append((name, im.convert('RGB')))

# the picture
pad, fw, fh = 20, 640, 360
W = pad + fw + pad + 390 + pad + 240 + pad
H = pad + len(rows) * (fh + 40 + pad)
out = Image.new('RGB', (W, H), (25, 27, 31))
d = ImageDraw.Draw(out)
for i, (name, im) in enumerate(rows):
    y = pad + i * (fh + 40 + pad)
    full = im.resize((fw, fh), Image.LANCZOS)
    fd = ImageDraw.Draw(full)
    m = int(fh * 0.04)
    for r in [(0, 0, fw, m), (0, fh - m, fw, fh), (0, 0, m, fh), (fw - m, 0, fw, fh)]:
        fd.rectangle(r, outline=(255, 60, 60), width=1)
    out.paste(full, (pad, y + 30))
    out.paste(im.resize((390, 219), Image.LANCZOS), (pad + fw + pad, y + 30))
    out.paste(im.resize((240, 135), Image.LANCZOS), (pad + fw + pad + 390 + pad, y + 30))
    d.text((pad, y), name, font=f_big, fill=(235, 235, 240))
    d.text((pad + fw + pad, y + 6), 'phone game page (390)', font=f_small, fill=(150, 152, 160))
    d.text((pad + fw + pad + 390 + pad, y + 6), 'smallest (240)', font=f_small, fill=(150, 152, 160))
out.save(os.path.join(args.dir, 'thumb_check.png'))
print('saved', os.path.join(args.dir, 'thumb_check.png'))
print('ALL PASS' if not failed else '%d FAILED' % failed)
raise SystemExit(1 if failed else 0)
