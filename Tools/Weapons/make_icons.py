"""The weapons' ICONS, made from their real pictures.

make_models.py renders every weapon's model (out/tiles/<Key>.png, the pictures
on the pack sheets). This turns each one into a square icon: the weapon laid
corner to corner like an item icon (gauntlets stay upright), fitted into
256 x 256 on a see-through background with a dark outline so it reads on any
colour, saved as out/icons/<Key>.png. Tools/Upload/upload_assets.bat uploads
them; their ids go in ReplicatedStorage/AssetIds.lua (Icons), and the game
shows them on the Arcade's spinning strip, its menu and grid, and the
Weapons panel.

    python3 make_icons.py           every weapon that has a picture
    python3 make_icons.py --sheet   ...and Docs/weapons/icons.png, to look at

(Re-run it after make_models.py re-renders a weapon: the uploader only
uploads icons that changed.)
"""
import glob
import importlib
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
TILES = os.path.join(HERE, 'out', 'tiles')
ICONS = os.path.join(HERE, 'out', 'icons')
SIZE = 256
PAD = 12  # (pixels of air round the weapon, inside the outline)
OUTLINE = 5
INK = (24, 20, 37)
# how far each type is turned (degrees, clockwise): the long ones corner to corner
TILT = {'Sword': 45, 'Katana': 45, 'Daggers': 45, 'Scythe': 30, 'Hammer': 35, 'Fists': 0}
RARITY = {
    'Common': (192, 203, 220), 'Rare': (0, 153, 219), 'Epic': (181, 80, 136),
    'Legendary': (254, 174, 52), 'Mythic': (228, 59, 68), 'Secret': (255, 255, 255),
}
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


def weapons():
    """(key, title, type, rarity) for every weapon in the packs, made or draft"""
    out = []
    mods = ['packs.' + os.path.splitext(os.path.basename(p))[0] for p in sorted(glob.glob(os.path.join(HERE, 'packs', '*.py'))) if not p.endswith('__init__.py')]
    mods += ['packs.later.' + os.path.splitext(os.path.basename(p))[0] for p in sorted(glob.glob(os.path.join(HERE, 'packs', 'later', '*.py')))]
    for name in mods:
        try:
            pack = importlib.import_module(name).PACK
            for key, title, kind, rarity, _ in pack['weapons']:
                out.append((key, title, kind, rarity, pack.get('title', name)))
        except Exception:
            # (a draft that doesn't load on its own: read its weapon list as text)
            path = os.path.join(HERE, *name.split('.')) + '.py'
            text = open(path).read()
            for key, title, kind, rarity in re.findall(r"\(\s*'(\w+)',\s*'([^']+)',\s*'(\w+)',\s*'(\w+)',", text):
                if kind in TILT and rarity in RARITY:
                    out.append((key, title, kind, rarity, name))
    # the starter, not in a pack (its picture: out/tiles/IronSword.png, drawn by hand)
    out.append(('IronSword', 'Iron Sword', 'Sword', 'Common', 'Starter'))
    return out


def icon(key, kind):
    tile = os.path.join(TILES, key + '.png')
    if not os.path.exists(tile):
        return None
    img = Image.open(tile).convert('RGBA')
    img = img.crop(img.getbbox())
    tilt = TILT.get(kind, 0)
    if tilt:
        img = img.rotate(-tilt, resample=Image.BICUBIC, expand=True)
        img = img.crop(img.getbbox())
    room = SIZE - 2 * (PAD + OUTLINE)
    k = room / max(img.width, img.height)
    img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    canvas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(img, ((SIZE - img.width) // 2, (SIZE - img.height) // 2), img)
    # the dark outline: the weapon's shape, grown, underneath it
    alpha = canvas.getchannel('A').point(lambda a: 255 if a > 40 else 0)
    grown = alpha.filter(ImageFilter.MaxFilter(OUTLINE * 2 + 1)).filter(ImageFilter.GaussianBlur(0.8))
    out = Image.new('RGBA', (SIZE, SIZE), INK + (0,))
    out.putalpha(grown)
    out.alpha_composite(canvas)
    os.makedirs(ICONS, exist_ok=True)
    path = os.path.join(ICONS, key + '.png')
    out.save(path, optimize=True)
    return path


def sheet(made, path):
    cols = 6
    cell, gap = 200, 18
    rows = (len(made) + cols - 1) // cols
    W = cols * (cell + gap) + gap
    H = rows * (cell + 58 + gap) + 90
    img = Image.new('RGB', (W, H), (26, 24, 40))
    d = ImageDraw.Draw(img)
    d.text((W // 2, 42), 'WEAPON ICONS', font=ImageFont.truetype(BOLD, 36), fill=(254, 231, 97), anchor='mm')
    f = ImageFont.truetype(BOLD, 15)
    for i, (key, title, kind, rarity, pack, p) in enumerate(made):
        c, r = i % cols, i // cols
        x0, y0 = gap + c * (cell + gap), 80 + r * (cell + 58 + gap)
        col = RARITY.get(rarity, (255, 255, 255))
        d.rounded_rectangle((x0, y0, x0 + cell, y0 + cell), radius=14, fill=(24, 20, 37), outline=col, width=4)
        ic = Image.open(p).convert('RGBA').resize((cell - 20, cell - 20), Image.LANCZOS)
        img.paste(ic, (x0 + 10, y0 + 10), ic)
        d.text((x0 + cell // 2, y0 + cell + 16), title, font=f, fill=(255, 255, 255), anchor='mm')
        d.text((x0 + cell // 2, y0 + cell + 36), '%s  %s' % (rarity.upper(), kind.upper()), font=ImageFont.truetype(BOLD, 12), fill=col, anchor='mm')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print('saved', os.path.relpath(path, ROOT))


def main():
    made = []
    for key, title, kind, rarity, pack in weapons():
        p = icon(key, kind)
        if p:
            made.append((key, title, kind, rarity, pack, p))
        else:
            print('no picture for', key, '(run make_models.py first)')
    print('made %d icons in %s' % (len(made), os.path.relpath(ICONS, ROOT)))
    if '--sheet' in sys.argv[1:]:
        sheet(made, os.path.join(ROOT, 'Docs', 'weapons', 'icons.png'))


if __name__ == '__main__':
    main()
