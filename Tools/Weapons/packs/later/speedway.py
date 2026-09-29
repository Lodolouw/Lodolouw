"""SPEEDWAY PACK (Speedy Revvington, King of the Speedway, floor 5): a cocky
cartoon race car's shiny orange paint (deeper orange in its shadows), two white
racing stripes, black tyres on silver rims, big green eyes and a grille full of
teeth; blue nitro, pistons, exhausts and flames for the rarer ones, and a
checkered flag and a trophy on the Secret. Weapon space and voxels: see
voxel.py."""
import math

from voxel import Mat, glow, shade
from kit import E32, square, rounded_box, grip, blade, edges, paint_on

PAINT = (247, 118, 34)   # Revvington's paint (Config.Bosses: Color)
DEEP = (190, 74, 40)     # the paint in shadow (DeepColor)
INK = (24, 20, 37)       # tyres, grille, his mouth (CoreColor)
EYES = (99, 199, 77)     # his big green eyes (EyeColor)
FLAME = (255, 128, 30)
NITRO = E32['cyan']      # his nitro flames

P = {}
for m in (
    Mat('paint', PAINT), Mat('paint_l', shade(PAINT, 1.3)), Mat('paint_d', DEEP),
    Mat('stripe', E32['white'], role='trim'),
    Mat('tyre', INK), Mat('tyre_l', E32['night']),
    Mat('chrome', E32['silver'], 'Foil', role='metal'),
    Mat('chrome_l', (236, 241, 250), 'Foil', role='metal'),
    Mat('chrome_d', E32['steel'], 'Foil', role='metal'),
    Mat('steel_d', E32['slate'], role='metal'), Mat('iron', E32['dkslate'], role='metal'),
    Mat('grip', INK, role='grip'), Mat('grip_l', E32['dkslate'], role='grip'),
    Mat('check_w', E32['white']), Mat('check_k', INK),
    Mat('nitro', E32['blue']), Mat('nitro_d', E32['navy']), Mat('nitro_l', (120, 205, 245)),
    glow('nitroglow', NITRO),
    glow('flame', FLAME), glow('flame_y', E32['yellow']), glow('flame_r', (255, 56, 40)),
    glow('edgeglow', (250, 100, 20)), glow('checkglow', E32['white']),
    Mat('gold', E32['gold'], role='trim'), Mat('gold_l', E32['yellow'], role='trim'),
    Mat('gold_d', (208, 124, 42), role='trim'),
    Mat('iris', EYES, role='gem'), glow('gem', EYES, role='gem'),
):
    P[m.key] = m


# ----------------------------------------------------------------------
# shared bits: tyres, chrome rods, eyes, flames
# ----------------------------------------------------------------------
def disc(cx, cz, r):
    """the (x, z) cells of a disc round (cx, cz)"""
    n = int(math.ceil(r)) + 1
    return [(x, z) for x in range(cx - n, cx + n + 1) for z in range(cz - n, cz + n + 1)
            if (x - cx) ** 2 + (z - cz) ** 2 <= r * r + 1e-6]


def tyre_y(v, cx, cz, R, r_in, hw, blocks=16, band=None):
    """a chunky tyre, its axle along Y at (cx, cz): outer radius R, its hole
    r_in, tread from y -hw to hw. Tread blocks stagger across the running face
    (notched between them, its shoulders left whole so it looks round from the
    side), a lighter bead rings the hole, and band = (radius, material) lays a
    dashed ring of lettering on both sidewalls"""
    for x, z in disc(cx, cz, R):
        d = math.hypot(x - cx, z - cz)
        if d <= r_in:
            continue
        a = math.atan2(z - cz, x - cx)
        w = hw - 1 if d > R - 0.55 else hw
        for y in range(-w, w + 1):
            m = 'tyre'
            if d > R - 1.0 and y != 0 and abs(y) < w:
                k = int(math.floor(a / math.tau * blocks + (0.5 if y > 0 else 0.0)))
                if k % 2 == 0:
                    continue  # (a notch between tread blocks)
            if abs(y) == w and d <= r_in + 1.0:
                m = 'tyre_l'
            if band and abs(y) == w and abs(d - band[0]) < 0.55:
                if int(math.floor(a / math.tau * 22)) % 4 != 3:
                    m = band[1]
            v.set(x, y, z, m)


def chrome_rod(v, z0, z1, r=1, cx=0, cy=0, base='chrome', lit='chrome_l', dark='chrome_d'):
    """a chrome rod along Z, (2r+1) square: a bright streak down the corner that
    faces the light, its far corner darker"""
    square(v, z0, z1, r, base, cx, cy)
    for z in range(min(z0, z1), max(z0, z1) + 1):
        v.set(cx - r, cy - r, z, lit)
        v.set(cx + r, cy + r, z, dark)


def round_shade(v, cx, cy, z0, z1, base, lit, dark, towards=(-0.5, -0.87)):
    """shade a round thing along Z: its side facing `towards` lighter, the far
    side darker"""
    for (x, y, z), m in list(v.v.items()):
        if m != base or not (z0 <= z <= z1):
            continue
        dx, dy = x - cx, y - cy
        n = math.hypot(dx, dy)
        if n < 0.5 or not v.exposed(x, y, z, dirs=((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0))):
            continue
        c = (dx * towards[0] + dy * towards[1]) / n
        if c > 0.8:
            v.v[(x, y, z)] = lit
        elif c < -0.45:
            v.v[(x, y, z)] = dark


def car_eye(v, face, ca, cb, r=2.2, look=(0, 1), white='stripe', iris='iris', pupil='tyre', glint='stripe'):
    """one of Revvington's eyes, painted on the surface seen from `face`: a white,
    a green iris, an ink pupil and a glint"""
    R = int(math.ceil(r))
    cells = {}
    for i in range(-R, R + 1):
        for k in range(-R, R + 1):
            if i * i + k * k > r * r + 0.3:
                continue
            m = white
            di, dk = i - look[0], k - look[1]
            if di * di + dk * dk <= (r * 0.62) ** 2 + 0.3:
                m = iris
            if di * di + dk * dk <= 0.3:
                m = pupil
            cells[(ca + i, cb + k)] = m
    cells[(ca + look[0] - 1, cb + look[1] + 1)] = glint
    paint_on(v, face, list(cells), lambda a, b: cells[(a, b)])


def flames_y(v, cx, cz, R, tongues, hw):
    """tongues of fire licking out of a wheel's tread (its axle along Y at
    (cx, cz), radius R): tongues [(angle, length, half width, bend)] - degrees
    (0 = +X, 90 = up) and voxels; yellow at the root, red at the tip"""
    n = int(math.ceil(R + max(t[1] for t in tongues))) + 2
    for x in range(cx - n, cx + n + 1):
        for z in range(cz - n, cz + n + 1):
            d = math.hypot(x - cx, z - cz)
            out = d - R + 0.6
            if out < 0:
                continue
            a = math.degrees(math.atan2(z - cz, x - cx))
            for ang, L, half, bend in tongues:
                f = out / L
                if f > 1:
                    continue
                c = ang + bend * f * f
                off = math.radians(abs((a - c + 180) % 360 - 180)) * d
                if off > half * (1 - f) + 0.4:
                    continue
                m = 'flame_y' if f < 0.36 else ('flame' if f < 0.72 else 'flame_r')
                wy = int(round(hw * (1 - 0.75 * f)))
                for y in range(-wy, wy + 1):
                    v.put(x, y, z, m, keep=True)
                break


# ----------------------------------------------------------------------
# COMMON - Tyre Scythe (Scythe): an exhaust pipe for a pole with a rubber
# grip, a little tyre on a silver rim for its collar, and an orange blade in
# Revvington's paint: a wide white racing stripe and a pinstripe along it,
# a steel edge
# ----------------------------------------------------------------------
def tyre_scythe(v, pal):
    # the pole: a chrome exhaust pipe, pipe clamps up it
    chrome_rod(v, -10, 46)
    for z0 in (19, 33):
        v.cyl('z', (0, 0), 2.3, z0, z0 + 1, 'steel_d')
        v.box(3, 3, 0, 0, z0, z0 + 1, 'chrome_d')
    # the rubber grip where the hands go, a flange at each end
    grip(v, -7, 7, 'grip', wrap='grip_l', style='band', step=2)
    for z in (-8, 8):
        v.cyl('z', (0, 0), 2.3, z, z, 'grip')
    # the butt: the exhaust's tip, flared, sooty inside
    v.cyl('z', (0, 0), 2.3, -13, -11, 'chrome')
    v.cyl('z', (0, 0), 2.3, -11, -11, 'chrome_l')
    v.cyl('z', (0, 0), 2.3, -13, -13, 'chrome_d')
    v.box(-1, 1, -1, 1, -13, -12, 'tyre')

    # the blade: out along +X from the collar, curving down to its point. Its
    # bands run along it a whole voxel each (counted from its spine and its
    # edge), so they follow its outline cleanly
    def spine(x):
        return 57.0 - 17.0 * (x / 40.0) ** 2

    def width_at(x):
        return 1.2 + 10.5 * (1 - (x / 40.0) ** 1.3)

    for x in range(3, 41):
        top = int(math.floor(spine(x) + 0.3))
        bot = int(math.ceil(spine(x) - width_at(x) - 0.3))
        for z in range(bot, top + 1):
            up, down = z - bot, top - z   # from the edge, from the spine
            half = 1 if up >= 2 and down >= 1 else 0
            if up == 0:
                m = 'chrome_l'   # the edge
            elif up == 1:
                m = 'chrome'
            elif down == 0:
                m = 'paint_l'
            elif up == 2:
                m = 'paint_d'
            elif down in (2, 3) or down == 5:
                m = 'stripe'
            else:
                m = 'paint'
            for y in range(-half, half + 1):
                v.set(x, y, z, m)
    # the collar: a little tyre on a silver rim, the blade and pole in behind it
    cx, cz = 0, 51
    tyre_y(v, cx, cz, 6.3, 3.6, 2, blocks=16)
    for x, z in disc(cx, cz, 3.6):
        d = math.hypot(x - cx, z - cz)
        for y in range(-2, 3):
            v.set(x, y, z, None)
        if d > 2.6:
            for y in range(-1, 2):
                v.set(x, y, z, 'chrome_l' if abs(y) == 1 else 'chrome')
        elif d > 1.3:
            if x == cx or z == cz:
                for y in range(-1, 2):
                    v.set(x, y, z, 'chrome')
            else:
                v.set(x, 0, z, 'tyre')
        else:
            for y in range(-2, 3):
                v.set(x, y, z, 'stripe' if (x, z) != (cx, cz) else 'chrome_l')
    return {'smear': ((0.5, 0, 5.1), (4.0, 0, 3.95)), 'smear_wide': ((0.3, 0, 5.3), (4.1, 0, 3.85)),
            'glow': (255, 160, 80)}


# ----------------------------------------------------------------------
# RARE - Nitro Katana (Katana): a blue nitro bottle for a handle (a white
# label, a rounded shoulder, a chrome valve), the valve's wheel in
# Revvington's orange for its guard; a chrome blade with blue nitro flames
# licking up it from the guard and a glowing nitro edge
# ----------------------------------------------------------------------
def nitro_katana(v, pal):
    # the bottle: a rounded foot, its body, a rounded shoulder
    v.cyl('z', (0, 0), 1.5, -9, -9, 'nitro')
    v.cyl('z', (0, 0), 2.3, -8, 3, 'nitro')
    v.cyl('z', (0, 0), 2.0, 4, 4, 'nitro')
    v.cyl('z', (0, 0), 1.5, 5, 5, 'nitro')
    # its label: white, an orange band round it
    v.cyl('z', (0, 0), 2.3, -4, -1, 'stripe')
    v.cyl('z', (0, 0), 2.3, -3, -2, 'paint')
    round_shade(v, 0, 0, -9, 5, 'nitro', 'nitro_l', 'nitro_d')
    round_shade(v, 0, 0, -9, 5, 'paint', 'paint_l', 'paint_d')
    # the valve, and its wheel for a guard
    v.box(-1, 1, -1, 1, 6, 6, 'chrome')
    v.cyl('z', (0, 0), 3.6, 7, 8, 'paint')
    for x, y in disc(0, 0, 3.6):
        if x * x + y * y > 7.5 and (x + y) % 2 == 0:
            v.set(x, y, 7, 'paint_d')
            v.set(x, y, 8, 'paint_d')
    v.box(-1, 1, -1, 1, 8, 8, 'chrome_l')
    # the collar
    v.box(-1, 1, -2, 2, 9, 10, 'chrome')
    v.box(-1, 1, -2, 2, 10, 10, 'chrome_l')

    # the blade: curving back (+Y), its edge -Y
    def width(z):
        if z < 11 or z > 56:
            return None
        lo, hi = -2.2, 3.2
        if z >= 51:
            lo = -2.2 + (z - 51) / 5.0 * 5.2
        return (lo, hi)

    def curve(z):
        return 2.2 * ((z - 11) / 45.0) ** 2

    # the flames: how high each column burns (from the edge back), and its core
    fire = [0, 9, 15, 10, 13, 7]
    core = [0, 4, 9, 5, 7, 3]

    def mat(z, w, t, lo, hi):
        col = int(math.floor(w - curve(z) + 0.5)) + 2
        if w <= lo + 0.9:
            return 'nitroglow'
        if 1 <= col < len(fire) and z <= 11 + fire[col]:
            return 'nitro_l' if z <= 11 + core[col] else 'nitro'
        if w >= hi - 0.9:
            return 'chrome_d'
        if w <= lo + 1.9:
            return 'chrome_l'
        return 'chrome'
    blade(v, 11, 56, width, mat, curve=curve)
    return {'smear': ((0, 0, 1.4), (0, 0, 5.5)), 'smear_wide': ((0, 0, 1.0), (0, 0, 5.7)), 'glow': NITRO}


# ----------------------------------------------------------------------
# EPIC - Piston Punchers (Fists): a gauntlet that's a little Revvington -
# orange bodywork with his bonnet stripes over the top, his big green eyes on
# the back of the hand and his grille grinning under them, a chrome bumper for
# knuckles, a chrome piston pumping down each side and two exhausts out of the
# cuff blowing flames
# ----------------------------------------------------------------------
def piston_punchers(v, pal):
    # the hand: orange bodywork, deeper orange underneath (the palm)
    rounded_box(v, -6, 6, -6, 5, -4, 7, 'paint', cut=2)
    v.recolor('paint', 'paint_d', where=lambda x, y, z: y >= 3 or z <= -3)
    edges(v, 'paint', 'paint_l', min_open=3)
    # his bonnet stripes, back over the top of the fist
    paint_on(v, '+z', [(x, y) for x in (-2, -1, 1, 2) for y in range(-6, 6)], 'stripe')
    # the windscreen on the back of the hand, his eyes on it looking up the punch
    for x in range(-5, 6):
        for z in range(0, 7):
            if abs(x) == 5 and z in (0, 6):
                continue
            v.set(x, -6, z, 'tyre')
    car_eye(v, '-y', -3, 3, r=2.2, look=(0, 1))
    car_eye(v, '-y', 3, 3, r=2.2, look=(0, 1))
    # his grin: the grille, a row of teeth
    mouth = [(x, -2) for x in range(-4, 5)] + [(x, -3) for x in range(-3, 4)] + [(-5, -1), (5, -1)]
    paint_on(v, '-y', mouth, 'tyre')
    paint_on(v, '-y', [(x, -2) for x in range(-3, 4)], 'stripe')
    # the knuckles: a chrome bumper along the top of the back of the hand
    rounded_box(v, -6, 6, -7, -4, 7, 8, 'chrome', cut=1)
    v.box(-6, 6, -7, -4, 8, 8, 'chrome_l', only={'chrome'})
    for x in (-3, 0, 3):
        v.box(x, x, -7, -7, 7, 8, 'chrome_d')
    # a piston down each side: a fat finned cylinder, a shiny rod pumping up
    # out of it into a joint on the fist
    v.box(6, 8, -1, 1, -5, 0, 'chrome_d')
    v.box(6, 8, -1, -1, -5, 0, 'chrome')
    v.box(8, 8, -1, -1, -5, 0, 'chrome_l')
    for z in (-5, -3, -1):
        v.box(7, 8, -2, 2, z, z, 'steel_d')
    v.box(7, 7, 0, 0, 1, 5, 'chrome_l')
    v.box(7, 7, -1, -1, 1, 5, 'chrome')
    v.box(6, 8, -1, 1, 6, 7, 'chrome')
    v.box(8, 8, -1, 1, 6, 7, 'chrome_d')
    v.box(8, 8, 0, 0, 6, 7, 'steel_d')
    # the cuff: black rubber with tread round it, a chrome ring on top
    rounded_box(v, -6, 6, -6, 6, -8, -5, 'tyre', cut=1)
    for (x, y, z), m in list(v.v.items()):
        if m == 'tyre' and z == -7 and (x + y) % 2 == 0 and abs(y) <= 6 and \
                v.exposed(x, y, z, dirs=((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0))):
            v.v[(x, y, z)] = 'tyre_l'
    v.box(-6, 6, -6, 6, -5, -5, 'chrome', only={'tyre'})
    # two exhausts out of the back of the cuff, flames roaring out of them
    v.box(2, 4, -8, -7, -8, -5, 'chrome')
    v.box(2, 2, -8, -7, -8, -5, 'chrome_l')
    v.box(4, 4, -7, -7, -8, -5, 'chrome_d')
    v.box(1, 5, -9, -6, -9, -9, 'chrome_d')
    v.box(1, 5, -9, -9, -9, -9, 'chrome')
    v.box(2, 4, -8, -7, -9, -9, 'tyre')
    fire = {-10: ((1, 5), 'flame_y'), -11: ((2, 4), 'flame'), -12: ((2, 4), 'flame'), -13: ((3, 3), 'flame_r')}
    for z, ((x0, x1), m) in fire.items():
        v.box(x0, x1, -8, -7, z, z, m)
    v.box(4, 4, -8, -7, -12, -12, 'flame_r')
    v.mirror_x()
    return {'smear': ((0, 0, -0.4), (0, 0, 0.9)), 'glow': FLAME}


# ----------------------------------------------------------------------
# LEGENDARY - Pit Stop Sabre (Sword): a curved chrome sabre with a
# checkered strip down it and a glowing orange edge; its knuckle guard is a
# spanner (its open jaw up by the blade, its ring down by the pommel, a
# glowing groove down it) and its pommel a lug nut
# ----------------------------------------------------------------------
def pit_stop_sabre(v, pal):
    grip(v, -6, 6, 'grip', wrap='paint_d', style='spiral', step=2)
    # the pommel: a chrome lug nut on a washer, its corners cut
    v.box(-2, 2, -2, 2, -10, -8, 'chrome')
    for x in (-2, 2):
        for y in (-2, 2):
            v.box(x, x, y, y, -10, -8, None)
    v.box(-2, -2, -1, 1, -10, -8, 'chrome_l')
    v.box(-1, 1, -2, -2, -10, -8, 'chrome_l')
    v.cyl('z', (0, 0), 2.3, -7, -7, 'chrome_d')
    # the crossguard, a bolt head on its end
    v.box(-1, 1, -8, 5, 7, 8, 'chrome')
    v.box(-1, 1, -8, 5, 8, 8, 'chrome_l')
    v.box(-2, 2, 5, 7, 6, 9, 'chrome_d')
    v.box(-2, 2, 6, 7, 7, 8, 'steel_d')
    # the collar at the blade's foot, in Revvington's orange
    v.box(-1, 1, -3, 3, 9, 10, 'paint')
    v.box(-1, 1, -3, 3, 10, 10, 'paint_l')
    # the knuckle guard: a spanner - its open jaw up by the blade...
    jaw = ['##...##',
           '##...##',
           '###.###',
           '#######',
           '.#####.',
           '..###..']
    v.sprite(jaw, {'#': 'chrome'}, (0, -12, 13), plane='yz', depth={'#': (-1, 1)})
    # ...its shaft down beside the grip, a glowing groove along it...
    v.box(-1, 1, -10, -8, -4, 7, 'chrome')
    v.box(-1, 1, -9, -9, -3, 6, 'edgeglow')
    v.box(0, 0, -9, -9, -3, 6, 'chrome_d')
    # ...and its ring end down by the pommel, joined on
    ring = ['.###.',
            '##.##',
            '#...#',
            '##.##',
            '.###.']
    v.sprite(ring, {'#': 'chrome'}, (0, -11, -5), plane='yz', depth={'#': (-1, 1)})
    v.box(-1, 1, -6, -3, -8, -7, 'chrome')
    edges(v, 'chrome', 'chrome_l', min_open=3)

    # the blade: a sabre, curving back (+Y), its edge -Y
    def width(z):
        if z < 11 or z > 46:
            return None
        lo, hi = -3.2, 3.2
        if z >= 37:
            lo = -3.2 + (z - 37) / 9.0 * 6.0
        if z >= 43:
            hi = 3.2 - (z - 43) / 3.0 * 0.8
        return (lo, hi)

    def curve(z):
        return 1.8 * ((z - 11) / 35.0) ** 2

    def mat(z, w, t, lo, hi):
        col = int(math.floor(w - curve(z) + 0.5)) + 3
        if w <= lo + 0.9:
            return 'edgeglow'
        if 3 <= col <= 4 and z <= 38:
            return 'check_w' if (col + z) % 2 == 0 else 'check_k'
        if w >= hi - 0.9:
            return 'chrome_d'
        if w <= lo + 1.9:
            return 'chrome_l'
        return 'chrome'
    blade(v, 11, 46, width, mat, curve=curve)
    return {'smear': ((0, 0, 1.2), (0, 0, 4.6)), 'smear_wide': ((0, 0, 0.9), (0, 0, 4.8)), 'glow': (250, 110, 30)}


# ----------------------------------------------------------------------
# MYTHIC - Wheelie Wrecker (Hammer): the head's a big flaming wheel - a
# chunky racing tyre (its tread hits) with white lettering, on a five-spoke
# chrome rim with an orange hub cap and a brake caliper peeping through - on a
# gear stick of a handle: an orange knob with the gear pattern on it for a
# pommel, a rubber boot where it meets the wheel
# ----------------------------------------------------------------------
def wheelie_wrecker(v, pal):
    cx, cz, R, rim = 0, 37, 12, 8
    # the gear stick: the knob, the grip, the chrome shaft, the rubber boot
    v.sphere((0, 0, -10), 2.7, 'paint')
    round_shade(v, 0, 0, -13, -7, 'paint', 'paint_l', 'paint_d')
    paint_on(v, '-y', [(-2, -9), (0, -9), (2, -9), (-2, -10), (-1, -10), (0, -10), (1, -10), (2, -10),
                       (-2, -11), (0, -11), (2, -11)], 'stripe')
    v.box(-1, 1, -1, 1, -7, -7, 'chrome')
    grip(v, -6, 10, 'grip', wrap='grip_l', style='band', step=3)
    chrome_rod(v, 11, cz)
    for i, z in enumerate(range(15, 23)):
        v.cyl('z', (0, 0), 1.6 + 0.3 * i + (0.7 if i % 2 else 0), z, z, 'tyre' if i % 2 else 'tyre_l')
    v.cyl('z', (0, 0), 2.3, 23, 24, 'chrome')
    v.cyl('z', (0, 0), 2.3, 24, 24, 'chrome_l')
    # the wheel
    tyre_y(v, cx, cz, R, rim, 5, blocks=22, band=(10.2, 'stripe'))
    for x, z in disc(cx, cz, rim):
        d = math.hypot(x - cx, z - cz)
        a = math.atan2(z - cz, x - cx)
        for y in range(-5, 6):
            v.set(x, y, z, None)
        if d > rim - 1.0:
            for y in range(-4, 5):
                v.set(x, y, z, 'chrome_l' if abs(y) == 4 else 'chrome')
            continue
        if d <= 2.6:
            for y in range(-4, 5):
                v.set(x, y, z, 'chrome')
            continue
        spoke = False
        for k in range(5):
            sa = -math.pi / 2 + k * math.tau / 5
            diff = abs((a - sa + math.pi) % math.tau - math.pi)
            if diff < math.pi / 2 and d * math.sin(diff) <= 0.7 + 0.8 * d / rim:
                spoke = True
        if spoke:
            for y in range(-3, 4):
                v.set(x, y, z, 'chrome_l' if abs(y) == 3 else 'chrome')
        else:
            v.box(x, x, -1, 1, z, z, 'tyre')
    # the shaft runs up the bottom spoke into the hub (it IS that spoke)
    chrome_rod(v, cz - rim, cz)
    # a brake caliper, orange, peeping through the top gap
    v.box(-2, 2, -2, 2, cz + 5, cz + 6, 'paint')
    v.box(-2, 2, -2, -2, cz + 6, cz + 6, 'paint_l')
    # the hub cap: orange, a chrome nut in the middle
    for x, z in disc(cx, cz, 1.6):
        for s in (-1, 1):
            v.set(x, s * 5, z, 'paint' if (x, z) != (cx, cz) else 'chrome_l')
    edges(v, 'chrome', 'chrome_l', min_open=3)
    # flames licking up off the tread
    tongues = [(20, 4, 2.2, 10), (48, 5, 2.4, 12), (74, 4, 2.2, 8), (90, 3, 2.0, 0),
               (106, 4, 2.2, -8), (132, 5, 2.4, -12), (160, 4, 2.2, -10)]
    flames_y(v, cx, cz, R, tongues, 3)
    return {'smear': ((-1.3, 0, 3.7), (1.3, 0, 3.7)), 'smear_wide': ((-1.5, 0, 3.7), (1.5, 0, 3.7)), 'glow': FLAME}


# ----------------------------------------------------------------------
# SECRET - Victory Lap (Daggers): the whole hilt's a gold trophy - its
# plinth for a pommel, its stem the grip (checkered wrap), its cup (handles
# and all, Revvington's green eye set in it) the guard - and out of the cup
# rises a waving checkered flag of a blade, glowing, gold edged, speed
# streaks flying off its back
# ----------------------------------------------------------------------
def victory_lap(v, pal):
    # the plinth, a gold plate on its front
    v.box(-2, 2, -2, 2, -6, -5, 'tyre')
    v.box(-2, 2, -2, 2, -6, -6, 'tyre_l')
    v.box(-1, 1, -2, -2, -6, -5, 'gold')
    v.box(2, 2, -1, 1, -6, -5, 'gold')
    v.box(-1, 1, -1, 1, -4, -4, 'gold_d')
    # the stem: the grip, a checkered wrap
    grip(v, -3, 3, 'check_k', wrap='check_w', style='diamond', step=1)
    # the cup
    v.box(-1, 1, -1, 1, 4, 4, 'gold_d')
    v.cyl('z', (0, 0), 2.3, 5, 5, 'gold')
    v.cyl('z', (0, 0), 3.2, 6, 8, 'gold')
    v.tube('z', (0, 0), 3.7, 2.4, 9, 9, 'gold_l')
    v.cyl('z', (0, 0), 2.4, 9, 9, 'gold_d')
    round_shade(v, 0, 0, 4, 9, 'gold', 'gold_l', 'gold_d')
    handle = ['#.',
              '.#',
              '.#',
              '#.']
    v.sprite(handle, {'#': 'gold'}, (0, 4, 8), plane='yz')
    v.sprite(handle, {'#': 'gold'}, (0, -4, 8), plane='yz', flip=True)
    # a green gem in the cup: Revvington's eye
    v.box(3, 3, 0, 0, 6, 7, 'gem')
    v.box(-3, -3, 0, 0, 6, 7, 'gem')

    # the blade: a checkered flag, waving (its checks ripple)
    def width(z):
        if z < 10 or z > 26:
            return None
        h = 3.2
        if z >= 18:
            h = 3.2 * (26 - z) / 8.0
        return (-h, h)

    def curve(z):
        return 0.7 * math.sin((z - 10) / 16.0 * math.pi * 1.5)

    def mat(z, w, t, lo, hi):
        if w <= lo + 0.9 or w >= hi - 0.9:
            return 'gold_l'
        col = int(math.floor(w - curve(z) + 0.5)) + 4
        row = z - 10 + int(round(0.9 * math.sin(col * 1.3)))
        return 'checkglow' if ((col // 2) + (row // 2)) % 2 == 0 else 'check_k'
    blade(v, 10, 26, width, mat, curve=curve)
    # speed streaks flying off its back, fading out
    for z, n in ((13, 3), (17, 2)):
        e = width(z)
        y0 = int(round(e[1] + curve(z))) + 1
        for k in range(n):
            v.set(0, y0 + k, z, ('flame_y', 'flame', 'flame_r')[min(k, 2)])
        v.set(0, y0, z - 1, 'flame_y')
    return {'smear': ((0, 0, 1.0), (0, 0, 2.5)), 'smear_wide': ((0, 0, 0.8), (0, 0, 2.6)), 'glow': (255, 255, 255)}


PACK = {
    'id': 'Speedway', 'title': 'Speedway pack - Revvington', 'accent': PAINT,
    'palette': P,
    'weapons': [
        ('TyreScythe', 'Tyre Scythe', 'Scythe', 'Common', tyre_scythe),
        ('NitroKatana', 'Nitro Katana', 'Katana', 'Rare', nitro_katana),
        ('PistonPunchers', 'Piston Punchers', 'Fists', 'Epic', piston_punchers),
        ('PitStopSabre', 'Pit Stop Sabre', 'Sword', 'Legendary', pit_stop_sabre),
        ('WheelieWrecker', 'Wheelie Wrecker', 'Hammer', 'Mythic', wheelie_wrecker),
        ('VictoryLap', 'Victory Lap', 'Daggers', 'Secret', victory_lap),
    ],
}
