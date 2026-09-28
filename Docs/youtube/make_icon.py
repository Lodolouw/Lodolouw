"""The channel icon: Oozlet on the navy burst of rays, 800 x 800, with a thin
gold ring just inside the circle YouTube crops a profile picture to.

    python3 make_icon.py                -> oozlet_icon.png
"""
import os
from PIL import Image, ImageDraw
from pixel_art import rays, sparkle, oozlet, SHADOW, YEL, INK

here = os.path.dirname(os.path.abspath(__file__))
N, S = 50, 16
img = rays(N, N, 24.5, 25.5)
for (x, y) in [(7, 9), (42, 7), (44, 30), (5, 33), (12, 43), (39, 43), (9, 20), (41, 18)]:
    sparkle(img, x, y)
px = img.load()
for y in range(41, 45):  # his shadow
    for x in range(N):
        if ((x - 24.5) / 15) ** 2 + ((y - 42.5) / 2.2) ** 2 <= 1:
            px[x, y] = SHADOW
sprite = oozlet()
img.paste(sprite, (0, 0), sprite)
big = img.resize((N * S, N * S), Image.NEAREST)
d = ImageDraw.Draw(big)
d.ellipse((14, 14, 786, 786), outline=YEL, width=10)
d.ellipse((24, 24, 776, 776), outline=INK, width=6)
big.save(os.path.join(here, "oozlet_icon.png"))
print("saved oozlet_icon.png")
