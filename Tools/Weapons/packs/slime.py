"""SLIME PACK (Oozark, floor 1): see-through green jelly with a dark core and a
glowing heart, like Oozark itself; acid for the rarer ones; Oozark's crown of
broken stone on the Secret. Weapon space and voxels: see voxel.py."""
import math

from voxel import Mat, glow, shade, hsh
from kit import (E32, square, rounded_box, grip, blade, taper, drips, drips_up, bubbles,
                 speckle, edges, eye, paint_on)

SLIME = (105, 210, 70)   # Oozark's slime (Config.Bosses: Color)
DEEP = (46, 120, 40)     # deeper in its body
CORE = (26, 38, 22)      # the hollow thing inside
HEART = (214, 255, 120)  # its glowing heart
EYE = (236, 255, 170)

P = {}
for m in (
    Mat('goo', SLIME, alpha=0.35), Mat('goo_l', shade(SLIME, 1.4), alpha=0.35),
    Mat('goo_d', DEEP, alpha=0.3),
    Mat('slime', SLIME), Mat('slime_l', shade(SLIME, 1.3)), Mat('slime_d', DEEP),
    Mat('core', CORE),
    Mat('bubble', (235, 255, 225), alpha=0.5),
    glow('heart', HEART), glow('acid', (120, 255, 60)), glow('eyeglow', EYE),
    Mat('eye', E32['white']), Mat('pupil', E32['ink']),
    Mat('wood', E32['dkbrown'], role='grip'), Mat('wood_l', E32['brown'], role='grip'),
    Mat('grip', (30, 80, 40), role='grip'), Mat('grip_l', DEEP, role='grip'),
    Mat('steel', E32['steel'], role='metal'), Mat('steel_l', E32['silver'], role='metal'),
    Mat('steel_d', E32['slate'], role='metal'),
    Mat('iron', E32['dkslate'], role='metal'), Mat('iron_d', E32['night'], role='metal'),
    Mat('gold', E32['gold'], role='trim'), Mat('gold_l', E32['yellow'], role='trim'),
    Mat('stone', (128, 124, 116)), Mat('stone_d', (88, 86, 82)),
    Mat('bone', E32['sand']),
    Mat('obsid', E32['teal'], role='metal'), Mat('obsid_l', (44, 104, 96), role='metal'),
    Mat('obsid_d', (14, 30, 28), role='metal'),
):
    P[m.key] = m


# ----------------------------------------------------------------------
# COMMON - Goo Gloves (Fists): a fist of solid slime in a wobbly jelly
# coat, knuckles showing through, two Oozlet eyes on the back of the hand
# and goo dripping off the knuckles
# ----------------------------------------------------------------------
def goo_gloves(v, pal):
    rounded_box(v, -5, 5, -5, 5, -3, 6, 'slime', cut=2)
    # the knuckles: four bumps along the top edge on the back of the hand
    for x0 in (-5, -2, 1, 4):
        v.box(x0, x0 + 1, -5, -3, 7, 7, 'slime_l')
    # the jelly coat, one voxel round everything
    rounded_box(v, -6, 6, -6, 6, -4, 8, 'goo', cut=2, keep=True)
    # the cuff: a thick darker band, its rim lighter
    rounded_box(v, -6, 6, -6, 6, -8, -5, 'slime_d', cut=1)
    v.box(-6, 6, -6, 6, -5, -5, 'slime', only={'slime_d'})
    edges(v, 'slime_d', 'core', min_open=3)
    # two eyes on the back of the hand (-Y), looking up the arm of the punch
    eye(v, '-y', -3, 2, 'eye', 'pupil', r=1.6, look=(0, 1))
    eye(v, '-y', 3, 2, 'eye', 'pupil', r=1.6, look=(0, 1))
    # goo running off the knuckles (+Z: down, when your arm hangs)
    drips_up(v, [(-5, -4, 8), (2, -6, 7), (5, 2, 8)], 'goo', seed=4, longest=2)
    bubbles(v, 'goo', 'bubble', chance=0.07, seed=2, deep_only=False)
    return {'smear': ((0, 0, -0.4), (0, 0, 0.9))}


# ----------------------------------------------------------------------
# RARE - Jellyblade (Sword): a blade of green jelly with a bone core you can
# see through it, bubbles caught inside, a slime-blob guard with eyes
# ----------------------------------------------------------------------
def jellyblade(v, pal):
    grip(v, -6, 5, 'grip', wrap='grip_l', style='spiral', step=2)
    # the pommel: a drop of goo with Oozark's heart glowing in it
    v.sphere((0, 0, -9), 2.5, 'goo')
    v.box(0, 0, 0, 0, -10, -8, 'heart')
    v.box(0, 0, -1, 1, -9, -9, 'heart')
    # the guard: a slime blob across the blade, big eyes on both flats
    v.ellipsoid((0, 0, 7), (2.6, 7.6, 2.8), 'slime')
    edges(v, 'slime', 'slime_l', min_open=3)
    for face in ('+x', '-x'):
        eye(v, face, -3, 7, 'eye', 'pupil', r=1.8, look=(0, 1))
        eye(v, face, 3, 7, 'eye', 'pupil', r=1.8, look=(0, 1))
    # the blade: wide jelly with wobbly edges, lighter at the edges, a bone
    # spine inside and bubbles caught in it
    base = taper(4.4, 10, 47, 37)

    def width(z):
        e = base(z)
        if not e:
            return None
        wob = 0.45 * math.sin(z * 0.9)
        return (e[0] + wob, e[1] + wob * 0.6)

    def thick(z, w, lo, hi):
        mid = (lo + hi) / 2
        half = max((hi - lo) / 2, 0.5)
        return 1 if abs(w - mid) < half * 0.7 else 0

    def mat(z, w, t, lo, hi):
        if w == 0 and t == 0 and z <= 42:
            return 'bone'
        if w <= lo + 0.9 or w >= hi - 0.9:
            return 'goo_l'
        return 'goo'
    blade(v, 10, 47, width, mat, thick=thick)
    bubbles(v, 'goo', 'bubble', chance=0.1, seed=5, deep_only=False)
    # goo dripping off the guard
    drips(v, [(0, -7, 6), (1, 5, 5), (0, 7, 6)], 'goo', seed=7, longest=2)
    return {'smear': ((0, 0, 1.2), (0, 0, 4.6)), 'smear_wide': ((0, 0, 0.9), (0, 0, 4.8))}


# ----------------------------------------------------------------------
# EPIC - Gelatin Hammer (Hammer): a wobbly jelly block with a darker core and
# a glowing heart, an Oozlet face on each end (the end that hits you), a
# steel band where the handle goes in, goo running down the wooden handle
# ----------------------------------------------------------------------
def gelatin_hammer(v, pal):
    grip(v, -9, 31, 'wood', wrap='wood_l', style='band', step=3)
    rounded_box(v, -2, 2, -2, 2, -12, -9, 'slime_d', cut=1)
    # the head: jelly across X (its ends hit)
    rounded_box(v, -12, 12, -7, 7, 31, 45, 'goo', cut=2)
    edges(v, 'goo', 'goo_l', min_open=2)
    # the core and its heart
    rounded_box(v, -8, 8, -3, 3, 35, 41, 'goo_d', cut=1)
    v.sphere((0, 0, 38), 2.0, 'heart')
    # the band round its middle, with rivets
    for x in range(-2, 3):
        for y in range(-8, 9):
            for z in range(30, 47):
                if abs(y) == 8 or z in (30, 46):
                    if not ((abs(y) == 8) and z in (30, 46)):
                        v.set(x, y, z, 'steel')
    for y in (-8, 8):
        for z in (33, 38, 43):
            v.set(0, y, z, 'steel_l')
    edges(v, 'steel', 'steel_d', min_open=3)
    # a face on each end
    for face, s in (('+x', 1), ('-x', -1)):
        eye(v, face, -3, 40, 'eye', 'pupil', r=1.8, look=(0, -1))
        eye(v, face, 3, 40, 'eye', 'pupil', r=1.8, look=(0, -1))
        mouth = [(y, 35) for y in range(-2, 3)] + [(-3, 36), (3, 36)]
        paint_on(v, face, mouth, 'core')
    # goo running down the handle
    drips(v, [(-2, -1, 30), (1, 2, 30), (2, -2, 30), (-1, 2, 29)], 'goo', seed=3, longest=5)
    drips(v, [(-9, -5, 30), (8, 4, 30), (11, -3, 30), (-12, 2, 30)], 'goo', seed=9, longest=3)
    bubbles(v, 'goo', 'bubble', chance=0.05, seed=11, deep_only=False)
    return {'smear': ((-1.3, 0, 3.8), (1.3, 0, 3.8)), 'smear_wide': ((-1.5, 0, 3.8), (1.5, 0, 3.8))}


# ----------------------------------------------------------------------
# LEGENDARY - Ooze Daggers (Daggers): wavy dark blades with a glowing ooze
# channel down the middle, glowing drops falling off their edges, a bubble
# for a pommel
# ----------------------------------------------------------------------
def ooze_daggers(v, pal):
    grip(v, -3, 3, 'obsid_d', wrap='acid', style='spiral', step=2)
    v.sphere((0, 0, -5), 1.8, 'goo')
    v.set(0, 0, -5, 'heart')
    # the guard: a dark bar with glowing tips
    v.box(-1, 1, -4, 4, 4, 5, 'obsid_d')
    v.box(-1, 1, -5, -5, 4, 6, 'acid')
    v.box(-1, 1, 5, 5, 4, 6, 'acid')
    # the blade: wavy, dark, a glowing channel, lighter edges
    width = taper(2.6, 6, 25, 17)

    def curve(z):
        return 0.9 * math.sin((z - 6) / 19.0 * math.pi * 1.5)

    def mat(z, w, t, lo, hi):
        mid = (lo + hi) / 2
        if abs(w - mid) < 0.6 and z <= 21:
            return 'acid'
        if w <= lo + 0.9 or w >= hi - 0.9:
            return 'obsid_l'
        return 'obsid'
    blade(v, 6, 25, width, mat, curve=curve)
    # glowing drops off its edges
    for z, side in ((10, -1), (14, 1), (18, -1), (12, 1)):
        e = width(z)
        off = curve(z)
        y = int(round((e[0] if side < 0 else e[1]) + off)) + side
        drips(v, [(0, y, z)], 'acid', seed=z, longest=2)
    return {'smear': ((0, 0, 0.6), (0, 0, 2.5)), 'smear_wide': ((0, 0, 0.4), (0, 0, 2.6))}


# ----------------------------------------------------------------------
# MYTHIC - Acid Scythe (Scythe): a big corroded blade split by glowing acid
# cracks, its edge burning green, acid dripping off it; a slime vine up the
# pole and a glowing acid orb on top
# ----------------------------------------------------------------------
def acid_scythe(v, pal):
    grip(v, -10, 50, 'iron')
    # the slime vine winding up the pole (round the outside of it, once
    # every 16 voxels up)
    ring = ([(x, -2) for x in range(-2, 2)] + [(2, y) for y in range(-2, 2)] +
            [(x, 2) for x in range(2, -2, -1)] + [(-2, y) for y in range(2, -2, -1)])
    for z in range(-9, 46):
        for k in (0, 1):
            x, y = ring[(z + k) % len(ring)]
            v.put(x, y, z, 'slime_l' if k == 0 else 'slime', keep=True)
    # the butt: a slime drop with the heart in it
    v.ellipsoid((0, 0, -12), (1.8, 1.8, 2.2), 'goo')
    v.set(0, 0, -12, 'heart')
    # the collar where the blade joins
    rounded_box(v, -2, 2, -2, 2, 46, 54, 'iron_d', cut=1)
    v.box(-2, 2, -2, 2, 48, 48, 'steel_l', only={'iron_d'})
    v.box(-2, 2, -2, 2, 52, 52, 'steel_l', only={'iron_d'})
    # the acid orb on top, in a jelly shell
    v.sphere((0, 0, 57), 2.9, 'goo')
    v.sphere((0, 0, 57), 1.8, 'acid')

    # the blade: out along +X, curving down to its point
    def spine(x):
        return 55.0 - 16.0 * (x / 40.0) ** 2

    def width_at(x):
        return 1.0 + 9.0 * (1 - (x / 40.0) ** 1.4)

    for x in range(2, 41):
        top = spine(x)
        bot = top - width_at(x)
        for z in range(int(math.floor(bot)), int(math.ceil(top)) + 1):
            if z > top + 0.3 or z < bot - 0.3:
                continue
            depth = z - bot  # how far up from the cutting edge
            half = 1 if depth > 2.2 and top - z > 0.8 else 0
            for y in range(-half, half + 1):
                if depth < 1.2:
                    m = 'acid'  # the burning edge
                else:
                    crack = top - width_at(x) * 0.5 + 1.8 * math.sin(x * 0.55)
                    crack2 = top - width_at(x) * 0.8 + 1.2 * math.sin(x * 0.9 + 1.0)
                    if (abs(z - crack) < 0.55 and x < 36) or (abs(z - crack2) < 0.5 and 8 < x < 30):
                        m = 'acid'
                    elif top - z < 1.0:
                        m = 'steel_l'
                    else:
                        m = 'steel_d' if hsh(x, y, z, 21) < 0.35 else 'steel'
                v.set(x, y, z, m)
    # acid dripping off the edge
    spots = []
    for x in (6, 13, 19, 26, 33):
        bot = spine(x) - width_at(x)
        spots.append((x, 0, int(math.floor(bot + 0.5))))
    drips(v, spots, 'acid', seed=13, longest=3)
    return {'smear': ((0.4, 0, 5.2), (3.9, 0, 4.0)), 'smear_wide': ((0.2, 0, 5.4), (4.1, 0, 3.9)), 'glow': (120, 255, 60)}


# ----------------------------------------------------------------------
# SECRET - Gelatinous Edge (Katana): a clear jelly blade with Oozark's heart
# glowing all the way up its middle, a burning green edge and a wavy hamon;
# its guard is Oozark's crown of broken stone, glowing eyes in it; gold and
# green wrap
# ----------------------------------------------------------------------
def gelatinous_edge(v, pal):
    grip(v, -7, 6, 'grip', wrap='gold', style='diamond', step=2)
    v.box(-1, 1, -1, 1, -9, -8, 'gold')
    v.set(0, 0, -9, 'gold_l')
    # the guard: a dark disc, a ring of stone, the crown's broken points
    v.cyl('z', (0, 0), 3.7, 7, 8, 'core')
    v.tube('z', (0, 0), 3.7, 2.8, 7, 8, 'stone')
    for i in range(6):
        a = i / 6.0 * math.tau + 0.3
        x, y = int(round(3.1 * math.cos(a))), int(round(3.1 * math.sin(a)))
        n = 3 + (i % 3)
        for k in range(n):
            v.set(x, y, 9 + k, 'stone' if k < n - 1 else 'stone_d')
    # its eyes, glowing out of the dark on both sides
    for s in (-1, 1):
        v.set(s * 1, -3, 8, 'eyeglow')
        v.set(s * 1, 3, 8, 'eyeglow')
    # the collar
    v.box(-1, 1, -2, 2, 9, 10, 'gold')
    v.box(-1, 1, -2, 2, 10, 10, 'gold_l', only={'gold'})

    # the blade: clear jelly, curving back (+Y); its edge is -Y
    def width(z):
        if z < 11 or z > 56:
            return None
        lo, hi = -2.2, 2.2
        if z >= 51:
            lo = -2.2 + (z - 51) / 5.0 * 4.2  # the point: the edge sweeps up to the back
        return (lo, hi)

    def curve(z):
        return 2.4 * ((z - 11) / 45.0) ** 2

    def mat(z, w, t, lo, hi):
        mid = (lo + hi) / 2
        if t == 0 and abs(w - mid) < 0.6 and z <= 52:
            return 'heart'  # the glowing heart up its middle, inside
        if w <= lo + 0.9:
            return 'acid'   # the edge
        if w >= hi - 0.9:
            return 'goo_d'  # the back
        hamon = lo + 1.4 + 0.5 * math.sin(z * 0.8)
        if abs(w - hamon) < 0.5:
            return 'goo_l'
        return 'goo'
    blade(v, 11, 56, width, mat, curve=curve)
    bubbles(v, 'goo', 'bubble', chance=0.08, seed=17, deep_only=False)
    drips(v, [(0, 3, 13), (0, 3, 19)], 'goo', seed=19, longest=2)
    return {'smear': ((0, 0, 1.4), (0, 0, 5.5)), 'smear_wide': ((0, 0, 1.0), (0, 0, 5.7)), 'glow': (120, 255, 60)}


PACK = {
    'id': 'Slime', 'title': 'Slime pack - Oozark', 'accent': (110, 230, 90),
    'palette': P,
    'weapons': [
        ('GooGloves', 'Goo Gloves', 'Fists', 'Common', goo_gloves),
        ('Jellyblade', 'Jellyblade', 'Sword', 'Rare', jellyblade),
        ('GelatinHammer', 'Gelatin Hammer', 'Hammer', 'Epic', gelatin_hammer),
        ('OozeDaggers', 'Ooze Daggers', 'Daggers', 'Legendary', ooze_daggers),
        ('AcidScythe', 'Acid Scythe', 'Scythe', 'Mythic', acid_scythe),
        ('GelatinousEdge', 'Gelatinous Edge', 'Katana', 'Secret', gelatinous_edge),
    ],
}
