"""
Draws GUI/studs.png: one stud, see-through around it, that the game tiles
over panels and buttons (the "stud GUI" look). It's only light and shadow,
so it works on any colour. Needs Pillow:  python make_studs.py
upload.bat uploads it; the id goes into Config.AssetIds.
"""

import os

from PIL import Image, ImageDraw, ImageFilter

S = 4  # drawn 4x bigger, then shrunk, for smooth edges
N = 64 * S
HERE = os.path.dirname(os.path.abspath(__file__))


def layer():
    return Image.new("RGBA", (N, N), (0, 0, 0, 0))


img = layer()
c, r = N / 2, 20 * S
# a soft shadow down and to the right
shadow = layer()
ImageDraw.Draw(shadow).ellipse([c - r + 3 * S, c - r + 5 * S, c + r + 3 * S, c + r + 5 * S], fill=(0, 0, 0, 95))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(2.5 * S)))
# the stud: a dark rim, lit from the top left
stud = layer()
d = ImageDraw.Draw(stud)
d.ellipse([c - r, c - r, c + r, c + r], fill=(0, 0, 0, 70))
d.ellipse([c - r + 1.5 * S, c - r + 1.5 * S, c + r - 3.5 * S, c + r - 3.5 * S], fill=(255, 255, 255, 85))
d.ellipse([c - r + 4 * S, c - r + 4 * S, c + r - 4 * S, c + r - 4 * S], fill=(255, 255, 255, 30))
img.alpha_composite(stud)
img.resize((64, 64), Image.LANCZOS).save(os.path.join(HERE, "studs.png"))
print("wrote studs.png")
