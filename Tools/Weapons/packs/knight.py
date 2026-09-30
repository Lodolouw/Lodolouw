"""KNIGHT PACK (Knight Burrowmore, the Honourable Digger, floor 3): his blue
plate armour with its deep blue shadow side and cyan shine, the dark behind
his visor and the yellow glow in its slit, his curly gold horns and gold trim,
the gold spade of his shovel, his red cape. Shovels and spades, dirt, dug-up
relics and treasure, rivets, crests and knightly honour. Weapon space and
voxels: see voxel.py."""
import math

from voxel import Mat, glow, shade, hsh
from kit import E32, rounded_box, grip, blade, speckle, edges, paint_on

# Burrowmore's colours (Config.Bosses) and the ones his body adds
# (ReplicatedStorage/BossBodies/Burrowmore.lua)
ARMOUR = (0, 153, 219)   # his armour
DEEP = (18, 78, 137)     # its shadowed side
CORE = (24, 20, 37)      # the dark behind his visor
EYE = (254, 231, 97)     # the glow in the visor's slit
TRIM = (254, 174, 52)    # gold: his trim, his horns, his shovel's blade
CAPE = (228, 59, 68)     # his cape
SHINE = (44, 232, 245)   # the shine on his chest plate
HORN = (247, 118, 34)    # every other block of his horns, so the curl reads
WOOD = (115, 62, 57)     # his shovel's handle
LEATHER = (62, 39, 49)   # his belt
DIRT = (194, 133, 105)   # the dirt he flings
DIRT_DARK = (184, 111, 80)

P = {}
for m in (
    Mat('blue', ARMOUR, role='metal'), Mat('blue_l', SHINE, role='metal'),
    Mat('blue_d', DEEP, role='metal'), Mat('blue_dd', shade(DEEP, 0.62), role='metal'),
    Mat('ink', CORE), glow('eye', EYE), glow('seam', TRIM),
    Mat('gold', TRIM, role='trim'), Mat('gold_l', EYE, role='trim'), Mat('gold_d', HORN, role='trim'),
    Mat('cape', CAPE, role='grip'), Mat('cape_d', E32['wine'], role='grip'),
    Mat('wood', WOOD, role='grip'), Mat('wood_l', E32['brown'], role='grip'),
    Mat('leather', LEATHER, role='grip'),
    Mat('dirt', DIRT), Mat('dirt_d', DIRT_DARK), Mat('dirt_dd', E32['dkbrown']),
    Mat('steel', E32['steel'], role='metal'), Mat('steel_l', E32['silver'], role='metal'),
    Mat('steel_d', E32['slate'], role='metal'),
    Mat('iron', E32['dkslate'], role='metal'), Mat('iron_d', E32['night'], role='metal'),
    Mat('bronze', E32['clay'], role='metal'), Mat('bronze_l', E32['tan'], role='metal'),
    Mat('bronze_d', E32['rust'], role='metal'), Mat('patina', (76, 160, 140), role='metal'),
    Mat('ruby', E32['hot'], role='gem'), Mat('ruby_l', E32['pink'], role='gem'),
    Mat('ruby_d', E32['wine'], role='gem'), glow('rubyglow', E32['hot']),
    Mat('gem', SHINE, role='gem'), glow('gemglow', SHINE),
):
    P[m.key] = m

# a card spade, pixel art (the pack's mark: Burrowmore's the knight of spades)
SPADE7 = ['...#...',
          '..###..',
          '.#####.',
          '#######',
          '#######',
          '##.#.##',
          '...#...',
          '..###..']


def sprite_cells(rows, cx, top, ch='#'):
    """(x, z) of every `ch` in pixel art centred on x = cx, its top row at z = top"""
    w = len(rows[0])
    return [(cx - w // 2 + c, top - r) for r, row in enumerate(rows) for c, k in enumerate(row) if k == ch]


def around(cells, diag=True):
    """the cells touching a set of (a, b) cells, not in it (a one-voxel rim)"""
    cells = set(cells)
    d = [(1, 0), (-1, 0), (0, 1), (0, -1)] + ([(1, 1), (1, -1), (-1, 1), (-1, -1)] if diag else [])
    return {(a + i, b + j) for (a, b) in cells for (i, j) in d} - cells


def dirt_clod(v, c, r, seed):
    """a lumpy clod of dirt round c: lighter on top, darker underneath"""
    cx, cy, cz = c
    R = int(math.ceil(r)) + 1
    for x in range(cx - R, cx + R + 1):
        for y in range(cy - R, cy + R + 1):
            for z in range(cz - R, cz + R + 1):
                d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2)
                if d <= r + 0.35 * (hsh(x, y, z, seed) - 0.3):
                    m = 'dirt' if z > cz or hsh(x, y, z, seed + 1) < 0.35 else 'dirt_d'
                    if z < cz - r * 0.4:
                        m = 'dirt_dd'
                    v.put(x, y, z, m, keep=True)


# ----------------------------------------------------------------------
# COMMON - Shovel Hammer (Hammer): half hammer, half shovel. A block of his
# blue armour steel with a flared, blunt face on one end and his gold spade on
# the other (still dirty from the dig), a riveted gold band where the handle
# goes in; the wooden handle of his shovel, a red leather grip and a spade's
# D-grip at the bottom
# ----------------------------------------------------------------------
def shovel_hammer(v, pal):
    grip(v, -8, 31, 'wood')
    edges(v, 'wood', 'wood_l', min_open=2)
    grip(v, -5, 5, 'cape_d', wrap='cape', style='spiral', step=2)
    for z in (-6, 6, 29, 30):
        v.box(-2, 2, -2, 2, z, z, 'gold')
    # the D-grip, like a spade's
    v.sprite(['.GGGGG.',
              '.WW.WW.',
              'WW...WW',
              'WW...WW',
              '.WWWWW.'], {'G': 'gold', 'W': 'wood_l'}, (-3, 0, -9), plane='xz',
             depth={'G': (-2, 2), 'W': (-1, 1)})
    # the head's block, long along X
    rounded_box(v, -10, 1, -5, 5, 31, 45, 'blue', cut=1)
    edges(v, 'blue', 'blue_l', min_open=2)
    v.box(-10, 1, -5, 5, 31, 31, 'blue_d', only={'blue', 'blue_l'})
    # a gold spade on each side of it (he's the knight of spades)
    for (x, z) in sprite_cells(SPADE7, -5, 42):
        v.put(x, -5, z, 'gold')
        v.put(x, 5, z, 'gold')
    # the blunt end: a flared face with a rim
    rounded_box(v, -12, -9, -6, 6, 30, 46, 'blue_d', cut=2)
    edges(v, 'blue_d', 'blue', min_open=3)
    v.box(-12, -12, -4, 4, 32, 44, 'steel_d')
    # the band round its middle, riveted
    for x in range(-1, 2):
        for y in range(-6, 7):
            for z in range(30, 47):
                if (abs(y) == 6 or z in (30, 46)) and not (abs(y) == 6 and z in (30, 46)):
                    v.set(x, y, z, 'gold')
    for y in (-6, 6):
        for z in (34, 38, 42):
            v.set(0, y, z, 'gold_l')

    # the spade: his shovel's gold blade out along +X, a rounded point
    def half(x):
        if x <= 4:
            return 6.6 if x >= 3 else 3.2
        u = (x - 3) / 13.0
        return 6.6 * max(0.0, 1 - u ** 2.4) ** 0.8

    cells = {(x, z) for x in range(2, 17) for z in range(30, 47) if abs(z - 38) <= half(x) + 0.01}
    for (x, z) in cells:
        inner = all((x + i, z + j) in cells for i in (-1, 0, 1) for j in (-1, 0, 1))
        thick = 2 if x in (3, 4) else (1 if inner else 0)
        for y in range(-thick, thick + 1):
            m = 'gold'
            if x == 2:
                m = 'gold_d'
            elif x in (3, 4):
                m = 'gold_d' if abs(y) == 2 else 'gold'   # the step (its rolled top edge)
            elif not inner:
                m = 'gold_l' if z > 38 else 'gold_d'
            v.set(x, y, z, m)
    # the socket running down its middle (the frog), riveted
    for x in range(5, 11):
        for y in (-2, 2):
            v.set(x, y, 38, 'gold_d')
    for y in (-2, 2):
        v.set(6, y, 38, 'steel_l')
        v.set(9, y, 38, 'steel_l')
    # a shine down it, like his shovel's
    for (x, z) in ((7, 41), (7, 42), (8, 42), (8, 43)):
        for y in (-1, 1):
            v.put(x, y, z, 'gold_l', only={'gold'})
    # dirt still stuck on it from the dig
    dirt_clod(v, (14, -1, 35), 1.3, 3)
    dirt_clod(v, (12, 1, 33), 1.1, 4)
    dirt_clod(v, (15, 1, 37), 0.9, 5)
    return {'smear': ((-1.2, 0, 3.8), (1.6, 0, 3.8)), 'smear_wide': ((-1.3, 0, 3.8), (1.7, 0, 3.8)),
            'glow': TRIM}


# ----------------------------------------------------------------------
# RARE - Relic Daggers (Daggers): treasure dug out of his hoard. A leaf-shaped
# bronze blade, old and tarnished, a gold rib down it with a gem at its foot
# and a glint of gold near its point; a gold guard whose ends curl up like his
# horns, a gem set in it; a grip of his belt leather wound with gold wire; a
# ruby for a pommel
# ----------------------------------------------------------------------
def relic_daggers(v, pal):
    import os
    variant = os.environ.get('RELIC', 'A')
    BL = {'A': ('bronze', 'bronze_l', 'bronze_d', 'patina'),
          'B': ('steel', 'steel_l', 'steel_d', None),
          'C': ('gold', 'gold_l', 'gold_d', None)}[variant]
    body, edge, dark, spot = BL
    grip(v, -3, 3, 'leather', wrap='gold', style='band', step=2)
    # the pommel: a ruby in gold claws
    v.box(-1, 1, -2, 2, -4, -4, 'gold')
    v.box(-1, 1, -1, 1, -6, -5, 'ruby')
    for x in (-1, 1):
        v.set(x, 1, -5, 'ruby_l')
    for y in (-2, 2):
        v.set(0, y, -5, 'gold')
    # the guard: its ends curl up and in, like his horns
    v.sprite(['L.........L',
              'G.........G',
              'GG.......GG',
              'GDDDGGGDDDG',
              '.GGGGGGGGG.'], {'G': 'gold', 'D': 'gold_d', 'L': 'gold_l'}, (0, -5, 8), plane='yz',
             depth={'G': (-1, 1), 'D': (-1, 1), 'L': (0, 0)})
    v.box(-2, 2, -1, 1, 4, 5, 'gold')
    for s in (-2, 2):
        v.box(s, s, 0, 0, 4, 5, 'gemglow')
    # the blade: a leaf, widest a third of the way up
    halfw = {6: 1, 7: 2, 8: 2, 9: 3, 10: 3, 11: 3, 12: 3, 13: 3, 14: 3, 15: 3, 16: 2, 17: 2,
             18: 2, 19: 2, 20: 1, 21: 1, 22: 1, 23: 0, 24: 0}

    def width(z):
        h = halfw.get(z)
        return None if h is None else (-h - 0.2, h + 0.2)

    def thick(z, w, lo, hi):
        return 1 if abs(w) < max(1, halfw[z]) else 0

    def mat(z, w, t, lo, hi):
        h = halfw[z]
        if w == 0 and z <= 21:
            return ('gold_d' if variant == 'C' else 'gold') if t != 0 else body
        if abs(w) == h:
            return edge
        return body
    blade(v, 6, 24, width, mat, thick=thick)
    if spot:
        speckle(v, body, spot, chance=0.16, seed=8)
    else:
        speckle(v, body, dark, chance=0.1, seed=8)
    # a gem at the foot of the rib
    for x in (-1, 1):
        v.set(x, 0, 7, 'ruby')
    # nicks in its old edges
    v.set(0, -3, 12, None)
    v.set(0, 2, 18, None)
    # a glint of gold on each flat
    for x in (-1, 1):
        for (y, z) in ((0, 17), (1, 17), (-1, 17), (0, 16), (0, 18)):
            v.put(x, y, z, 'eye', only={body, edge, dark, 'gold', 'gold_d', spot})
    return {'smear': ((0, 0, 0.6), (0, 0, 2.4)), 'smear_wide': ((0, 0, 0.4), (0, 0, 2.5)), 'glow': TRIM}


# ----------------------------------------------------------------------
# EPIC - Spade Scythe (Scythe): a hooked blade of blue steel with his gold
# rolled edge along its back and a card spade cut right through it; a gold
# spade on top of the pole with a gem glowing in it, a gold point at its butt;
# the pole is his shovel's wood, gold rings, a red grip
# ----------------------------------------------------------------------
def spade_scythe(v, pal):
    grip(v, -10, 50, 'wood')
    edges(v, 'wood', 'wood_l', min_open=2)
    grip(v, -4, 4, 'cape_d', wrap='cape', style='spiral', step=2)
    for z in (-6, 6, 24):
        v.box(-2, 2, -2, 2, z, z, 'gold')
    # the butt: a spade's point
    v.box(-2, 2, -2, 2, -11, -11, 'gold')
    v.box(-1, 1, -1, 1, -12, -13, 'gold_d')
    v.set(0, 0, -14, 'gold_l')
    # the collar where the blade joins
    rounded_box(v, -2, 2, -2, 2, 46, 54, 'blue_d', cut=1)
    v.box(-2, 2, -2, 2, 47, 47, 'gold', only={'blue_d'})
    v.box(-2, 2, -2, 2, 53, 53, 'gold', only={'blue_d'})
    # the spade on top
    for (x, z) in sprite_cells(SPADE7, 0, 62):
        for y in (-1, 0, 1):
            v.set(x, y, z, 'gold')
    edges(v, 'gold', 'gold_l', min_open=3)
    for y in (-2, -1, 1, 2):
        v.set(0, y, 58, 'gemglow')

    # the blade: out along +X, hooking down to its point
    def spine(x):
        return 55.0 - 20.0 * (x / 40.0) ** 2.5

    def width_at(x):
        return 1.0 + 10.5 * (1 - x / 40.0) ** 0.8

    hole = set(sprite_cells(SPADE7, 8, 53))
    rim = around(hole)
    for x in range(3, 41):
        top = spine(x)
        bot = top - width_at(x)
        for z in range(int(math.floor(bot)), int(math.ceil(top)) + 1):
            if z > top + 0.3 or z < bot - 0.3 or (x, z) in hole:
                continue
            depth = z - bot  # how far up from the cutting edge
            half = 1 if (depth > 2.2 and top - z > 0.8) or (x, z) in rim else 0
            for y in range(-half, half + 1):
                if (x, z) in rim:
                    m = 'gold'
                elif top - z < 1.0:
                    m = 'gold'       # his rolled gold edge along its back
                elif depth < 1.2:
                    m = 'steel_l'    # the cutting edge
                elif depth < 2.4:
                    m = 'blue_l'
                else:
                    m = 'blue'
                v.set(x, y, z, m)
    return {'smear': ((0.4, 0, 5.2), (3.9, 0, 3.8)), 'smear_wide': ((0.2, 0, 5.4), (4.1, 0, 3.6)), 'glow': TRIM}


# ----------------------------------------------------------------------
# LEGENDARY - Honour Blade (Katana): a knight's katana. Blue steel with a
# bright edge and a line of gold glowing up its back; a gold knight's cross
# for a guard, flared at its ends, his visor's glow in its middle; a red and
# blue wrap
# ----------------------------------------------------------------------
def honour_blade(v, pal):
    grip(v, -7, 5, 'cape', wrap='blue_d', style='diamond', step=2)
    v.box(-1, 1, -1, 1, -9, -8, 'gold')
    v.set(0, 0, -9, 'gold_l')
    # the guard: a knight's cross, flared at its ends
    v.sprite(['GG.......GG',
              'GGGGGGGGGGG',
              'GGGGGGGGGGG',
              'GG.......GG'], {'G': 'gold'}, (0, -5, 8), plane='yz', depth={'G': (-1, 1)})
    v.box(-2, 2, -1, 1, 5, 8, 'gold')
    edges(v, 'gold', 'gold_l', min_open=3)
    for s in (-2, 2):
        v.box(s, s, 0, 0, 6, 7, 'eye')
    # the collar
    v.box(-1, 1, -2, 2, 9, 10, 'gold')
    v.box(-1, 1, -2, 2, 10, 10, 'gold_l')

    def width(z):
        if z < 11 or z > 55:
            return None
        lo, hi = -2.2, 2.2
        if z >= 50:
            lo = -2.2 + (z - 50) / 5.0 * 4.2
        return (lo, hi)

    def curve(z):
        return 2.4 * ((z - 11) / 44.0) ** 2

    def mat(z, w, t, lo, hi):
        if w <= lo + 0.9:
            return 'steel_l'   # the edge
        if w >= hi - 0.9:
            return 'blue_d'    # the back
        if hi - w < 1.9:
            return 'eye' if t != 0 and z <= 49 else 'blue'   # the gold line
        if w - lo < 1.9 and math.sin(z * 0.75) > 0.2:
            return 'blue_l'    # the temper line, waving
        return 'blue'
    blade(v, 11, 55, width, mat, curve=curve)
    return {'smear': ((0, 0, 1.3), (0, 0, 5.5)), 'smear_wide': ((0, 0, 1.0), (0, 0, 5.6)), 'glow': EYE}


# ----------------------------------------------------------------------
# MYTHIC - Anchor Fists (Fists): his plate gauntlet, heavy as an anchor: a
# gold anchor across the back of the hand, gold knuckles, a chain wound round
# the flared iron cuff, gold rivets glowing all over it
# ----------------------------------------------------------------------
def anchor_fists(v, pal):
    rounded_box(v, -6, 6, -5, 5, -3, 7, 'blue', cut=2)
    edges(v, 'blue', 'blue_l', min_open=3)
    # the fingers: dark seams between them over the top and down the front,
    # and the joint across them
    for x in (-3, 0, 3):
        for y in range(-3, 6):
            for z in range(-3, 8):
                if v.get(x, y, z) and v.exposed(x, y, z):
                    v.set(x, y, z, 'blue_dd')
    paint_on(v, '+y', [(x, 2) for x in range(-6, 7)], 'blue_dd')
    # the knuckles: four gold studs along the top
    for x0 in (-5, -2, 1, 4):
        v.box(x0, x0 + 1, -5, -2, 8, 8, 'gold')
        v.box(x0, x0 + 1, -5, -5, 8, 8, 'gold_l')
    # the sides: a darker plate, glowing rivets
    for s in (-1, 1):
        paint_on(v, '+x' if s > 0 else '-x', [(y, z) for y in range(-3, 4) for z in range(-1, 6)
                                              if y in (-3, 3) or z in (-1, 5)], 'blue_d')
        for (y, z) in ((-2, 0), (2, 0), (-2, 4), (2, 4)):
            paint_on(v, '+x' if s > 0 else '-x', [(y, z)], 'seam')
    # the back plate
    v.box(-6, 6, -6, -6, -2, 7, 'blue_d')
    for (x, z) in ((-6, -2), (6, -2), (-6, 7), (6, 7)):
        v.set(x, -6, z, None)
    # the anchor
    anchor = ['.....GGG.....',
              '....G...G....',
              '....G...G....',
              '.....GGG.....',
              '..GGGGGGGGG..',
              '......G......',
              '......G......',
              'F.....G.....F',
              'FF....G....FF',
              '.GG...G...GG.',
              '..GGGGGGGGG..']
    v.sprite(anchor, {'G': 'gold', 'F': 'gold_d'}, (-6, -7, 8), plane='xz')
    # rivets glowing in the corners of the plate
    for (x, z) in ((-5, -1), (5, -1), (-5, 6), (5, 6)):
        v.set(x, -7, z, 'seam')
    # the cuff: flared dark iron, a gold rim with glowing rivets
    rounded_box(v, -6, 6, -6, 6, -8, -4, 'iron', cut=1)
    rounded_box(v, -7, 7, -7, 7, -8, -8, 'iron_d', cut=0)
    v.box(-6, 6, -6, 6, -4, -4, 'gold', only={'iron'})
    for x in (-3, 3):
        v.set(x, -6, -4, 'seam')
        v.set(x, 6, -4, 'seam')
    # the chain wound round it: flat links and links on edge, in turn
    path = ([(x, -7, 0, -1) for x in range(0, 7)] + [(7, y, 1, 0) for y in range(-7, 8)] +
            [(x, 7, 0, 1) for x in range(6, -1, -1)])
    for i, (x, y, nx, ny) in enumerate(path):
        k = i % 5
        if k in (4, 0, 1):
            v.set(x, y, -5, 'steel')
            v.set(x, y, -7, 'steel')
            if k != 0:
                v.set(x, y, -6, 'steel')
        else:
            v.set(x, y, -6, 'steel_d')
            v.set(x + nx, y + ny, -6, 'steel_d')
    v.mirror_x()
    return {'smear': ((0, 0, -0.4), (0, 0, 0.9)), 'glow': TRIM}


def crack_lines(trunks, z_top, halfw, seed):
    """cracks up a blade: each trunk (w, z) wanders up to z_top, zig-zagging
    (a staircase where it steps across, so it stays joined), now and then
    splitting off a short branch toward the nearer edge. halfw(z) -> how far
    across the blade reaches there. Returns {(w, z): 'trunk' or 'branch'}"""
    out = {}
    for k, (w, z) in enumerate(trunks):
        d, run, i = 0, 0, 0
        while z <= z_top:
            lim = halfw(z)
            if lim is None:
                break
            out[(w, z)] = 'trunk'
            i += 1
            if run <= 0:
                r = hsh(k, i, z, seed)
                d = -1 if r < 0.36 else (1 if r > 0.64 else 0)
                run = 2 + int(hsh(i, k, z, seed + 1) * 3)
            run -= 1
            nw = w + d
            if abs(nw) > lim - 1.8:
                d = -d
                nw = w + d
            if nw != w:
                out[(nw, z)] = 'trunk'
                w = nw
            z += 1
            if hsh(z, k, 7, seed) < 0.17:
                bd = 1 if w > 0 else (-1 if w < 0 else (1 if hsh(z, 1, k, seed) < 0.5 else -1))
                bw, bz = w, z
                for j in range(3 + int(hsh(z, k, 8, seed) * 4)):
                    bw += bd
                    lim = halfw(bz)
                    if lim is None or abs(bw) > lim - 1.2:
                        break
                    out.setdefault((bw, bz), 'branch')
                    if j % 2 == 1:
                        bz += 1
                        out.setdefault((bw, bz), 'branch')
    return out


# ----------------------------------------------------------------------
# SECRET - No Quarter (Sword): his armour cracks gold. A broad greatsword of
# dark blue steel split by glowing gold cracks; its guard is Burrowmore's own
# helm - the T visor on both flats with his eyes glowing in the slit, his
# curly gold horns sweeping out and up for quillons; a red grip and a big ruby
# pommel in gold claws
# ----------------------------------------------------------------------
SPADE_TIP = True


def no_quarter(v, pal):
    grip(v, -6, 3, 'cape', wrap='cape_d', style='spiral', step=2)
    # the pommel: a big ruby in gold claws
    v.box(-2, 2, -2, 2, -7, -7, 'gold')
    for z, r in ((-8, 2), (-9, 2), (-10, 2), (-11, 1)):
        for x in range(-r, r + 1):
            for y in range(-r, r + 1):
                if r == 2 and abs(x) == 2 and abs(y) == 2:
                    continue
                v.set(x, y, z, 'ruby')
    v.box(-1, 1, -1, 1, -12, -12, 'ruby')
    for s in (-1, 1):
        v.box(2 * s, 2 * s, -1, 1, -9, -10, 'rubyglow')
        v.set(0, 2 * s, -9, 'ruby_l')
        v.box(2 * s, 2 * s, -2, -2, -8, -8, 'gold')
        v.box(2 * s, 2 * s, 2, 2, -8, -8, 'gold')
    # the guard: his helm
    rounded_box(v, -3, 3, -5, 5, 4, 13, 'blue', cut=2)
    edges(v, 'blue', 'blue_l', min_open=3)
    v.box(-3, 3, -5, 5, 12, 13, 'blue_d', only={'blue', 'blue_l'})
    for face in ('+x', '-x'):
        paint_on(v, face, [(y, z) for y in range(-4, 5) for z in (8, 9)], 'ink')   # the slit
        paint_on(v, face, [(0, z) for z in range(5, 8)], 'ink')                     # the T's stem
        paint_on(v, face, [(-3, 9), (-2, 9), (2, 9), (3, 9)], 'eye')                # his eyes
    # his horns, a shade deeper every other block so the curl reads
    pts = [(5.0, 10.0, 1.8), (6.6, 11.0, 1.7), (7.9, 12.6, 1.5), (8.6, 14.7, 1.35),
           (8.5, 16.8, 1.15), (7.6, 18.3, 0.95), (6.4, 18.8, 0.7)]
    for s in (-1, 1):
        for i in range(len(pts) - 1):
            (y0, z0, r0), (y1, z1, r1) = pts[i], pts[i + 1]
            for k in range(5):
                f = k / 5.0
                y, z, r = y0 + (y1 - y0) * f, z0 + (z1 - z0) * f, r0 + (r1 - r0) * f
                m = 'gold' if i % 2 == 0 else 'gold_d'
                v.ellipsoid((0, s * y, z), (min(r, 1.2), r, r), m)
    # the collar where the blade leaves the helm
    v.box(-1, 1, -5, 5, 14, 14, 'gold')

    # the blade: broad, dark blue steel
    def halfw(z):
        if z < 15 or z > 49:
            return None
        if z <= 17:
            return 4.4
        if SPADE_TIP:
            if z <= 33:
                return 5.4
            if z <= 38:
                return 5.4 + (z - 33) / 5.0 * 1.0   # the spade's shoulders
            return 6.4 * max(0.0, (49.6 - z) / 11.6) ** 0.75
        if z <= 38:
            return 5.4
        return 5.4 * max(0.0, (49.6 - z) / 11.6) ** 0.8

    def width(z):
        h = halfw(z)
        return None if h is None else (-h, h)

    def thick(z, w, lo, hi):
        half = max((hi - lo) / 2, 0.5)
        return 1 if abs(w) < half * 0.62 else 0

    def mat(z, w, t, lo, hi):
        if w <= lo + 0.9 or w >= hi - 0.9:
            return 'blue_l'
        if w <= lo + 1.9 or w >= hi - 1.9:
            return 'blue'
        return 'blue_d'
    blade(v, 15, 49, width, mat, thick=thick)
    # the cracks: gold glowing through it, from the helm up
    cracks = crack_lines([(-1, 15), (2, 15)], 44, halfw, 31)
    for (w, z), kind in cracks.items():
        for x in (-1, 0, 1):
            v.put(x, w, z, 'seam', only={'blue', 'blue_d', 'blue_l'})
    for (w, z) in around(set(cracks), diag=False):
        for x in (-1, 1):
            if hsh(w, z, x, 9) < 0.5:
                v.put(x, w, z, 'ink', only={'blue_d'})
    return {'smear': ((0, 0, 1.6), (0, 0, 4.9)), 'smear_wide': ((0, 0, 1.3), (0, 0, 5.0)), 'glow': TRIM}


PACK = {
    'id': 'Knight', 'title': 'Knight pack - Burrowmore', 'accent': ARMOUR,
    'palette': P,
    'weapons': [
        ('ShovelHammer', 'Shovel Hammer', 'Hammer', 'Common', shovel_hammer),
        ('RelicDaggers', 'Relic Daggers', 'Daggers', 'Rare', relic_daggers),
        ('SpadeScythe', 'Spade Scythe', 'Scythe', 'Epic', spade_scythe),
        ('HonourBlade', 'Honour Blade', 'Katana', 'Legendary', honour_blade),
        ('AnchorFists', 'Anchor Fists', 'Fists', 'Mythic', anchor_fists),
        ('NoQuarter', 'No Quarter', 'Sword', 'Secret', no_quarter),
    ],
}
