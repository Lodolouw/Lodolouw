"""The other weapon types' animations - gauntlets (Fists), Hammer, Daggers,
Scythe and Katana - made exactly the way the sword's are (combo.py, anims.py:
POSING BY DIRECTION). Space: the character's own - x right, y up, -z forward
(the enemy).

Every swing travels round a SWING PLANE: the weapon's angle round it (phi:
0 at the hit, pointing at the enemy; minus before, plus after) follows the
sword's timing curve - a quick coil back, held for a heartbeat, a whip
through that's fastest as it lands on the game's hit moment (Lock x Contact
in Config.Weapons.Types), and a follow-through that carries on round the
body. The chest turns a little ahead of the weapon, the arm leads it, the
feet step and pivot. What each type adds:
  * TWO HANDS (hammer, scythe, katana): the left hand goes on the handle,
    `two` studs along it from the right hand (+ towards the head / blade,
    - behind). R6 arms don't bend, so in wide swings it gets as close as a
    straight arm can.
  * THE LEFT HAND'S BLOWS (the gauntlets' hook, a dagger stab): the left arm
    travels round the plane instead, the right one keeps its guard.
  * BOTH AT ONCE (the daggers' crossing slash): the left arm mirrors the
    right one.
  * THE STRIKING SIDE: a blade's edge (its +Y) faces the way it travels; a
    hammer's head and a scythe's blade (their +X) lead the swing.

    python3 export_types.py     -> ReplicatedStorage/WeaponClips.lua (baked, played by WeaponFX)
                                   and ServerStorage/WeaponAnimations.rbxmx (to publish, if you like)
    python3 preview_types.py    -> contact sheets and videos to look at
"""
import math
import numpy as np

import anims
import r6
from anims import DirAnim, mix_dir, ease, slerp, unit

# the hit moments (seconds after the press) and when you can swing again -
# straight from Config.Weapons.Types (Lock x Contact, Lock)
TIMING = {
    'Fists': [(0.171, 0.38), (0.171, 0.38), (0.275, 0.55)],
    'Hammer': [(0.4125, 0.75), (0.4125, 0.75), (0.6, 1.0)],
    'Daggers': [(0.135, 0.3), (0.135, 0.3), (0.135, 0.3), (0.25, 0.5)],
    'Scythe': [(0.325, 0.65), (0.325, 0.65), (0.495, 0.9)],
    'Katana': [(0.16, 0.4), (0.16, 0.4), (0.27, 0.6)],
}

# the second one in the left hand (gauntlets, daggers): how it's held - the
# same numbers go in WeaponFX.OFFHAND. In line with the arm, so it points
# wherever the arm does.
OFFHAND = {'Fists': (-90.0, 0.0), 'Daggers': (-90.0, 0.0)}

LEG = {  # (left, right): where each leg points, hip to foot
    'square': ((-0.22, -1, -0.10), (0.22, -1, 0.10)),
    'back': ((-0.30, -1, -0.40), (0.30, -1, 0.22)),
    'lunge': ((-0.22, -1, -0.62), (0.32, -1, 0.55)),
    'pivot': ((-0.24, -1, -0.62), (0.06, -1, 0.52)),
    'wide': ((-0.36, -1, -0.30), (0.36, -1, 0.30)),
    'deep': ((-0.30, -1, -0.70), (0.34, -1, 0.62)),
    'tuck': ((-0.15, -1, -0.20), (0.15, -1, 0.10)),
    'crouch': ((-0.32, -1, -0.35), (0.34, -1, 0.30)),
}
AHEAD = (0, -0.08, -1)
DOWN = (0, -0.25, -1)


ARM_LEN = math.hypot(0.5, 1.5)  # (from the shoulder joint to the hand, a straight R6 arm)


def two_hand(pose, reach, rounds=4):
    """the left arm pointed so its hand lands on the handle. `reach` is where
    along the weapon (studs from the right hand: + towards the head or blade,
    - behind it): one spot, or a stretch (lo, hi) - then the hand takes the
    spot on it a straight arm reaches best, the way a grip slides along a
    handle (a little in favour of the stretch's middle, so it doesn't jump)"""
    p = dict(pose)
    p.setdefault('larm', (-0.3, -0.9, -0.3))
    lo, hi = (reach, reach) if isinstance(reach, (int, float)) else reach
    _, _, _, lc0, lc1 = r6.JOINTS['Left Shoulder']
    for _ in range(rounds):
        tr = anims.dir_transforms(p)
        world = r6.solve(tr)
        arm = world['Right Arm']
        hand = (arm @ np.array([0, -1.0, 0, 1]))[:3]
        handle = arm @ r6.JOINTS['Grip'][3] @ tr['Grip']
        blade = handle[:3, :3] @ np.array([0, 0, -1.0])
        joint = (world['Torso'] @ lc0)[:3, 3]
        rs = np.linspace(lo, hi, 25) if hi > lo else np.array([lo])
        pts = hand[None, :] + rs[:, None] * blade[None, :]
        miss = np.abs(np.linalg.norm(pts - joint, axis=1) - ARM_LEN) + 0.08 * np.abs(rs - (lo + hi) / 2)
        r = rs[int(np.argmin(miss))]
        target = hand + blade * r
        left = world['Left Arm']
        lhand = (left @ np.array([0, -1.0, 0, 1]))[:3]
        # (aim the arm from the shoulder at the target, nudged by where the hand
        # really ended up: the hand sits half a stud off the arm's line)
        cur = unit(np.asarray(p['larm'], float))
        want = unit(target - joint)
        p['larm'] = tuple(unit(slerp(cur, want, 0.7) + (target - lhand) * 0.35))
        # (its front along the handle, so the knuckles wrap it)
        p['lfwd'] = tuple(unit(blade * (1 if r >= 0 else -1) + np.array([0, 0.2, 0])))
    return p


def mix_extras(a, b, k):
    """mix_dir, plus the guard arm of a left-hand blow (a (d, b, e) triple)"""
    ra, rb = a.get('rarm'), b.get('rarm')
    out = mix_dir({x: v for x, v in a.items() if x != 'rarm'}, {x: v for x, v in b.items() if x != 'rarm'}, k)
    if ra is not None or rb is not None:
        ra, rb = ra or rb, rb or ra
        out['rarm'] = tuple(slerp(p, q, k) for p, q in zip(ra, rb))
    return out


def mirror(v):
    return (-v[0], v[1], v[2])


class TypeSwing:
    """A swing round a plane (see combo.PlaneSwing): u = where the weapon points
    at the hit, w = the way it's travelling then. keys: [(time, phi, easing,
    extras)] - extras: lean, tilt, delta (how far the arm is ahead of the
    weapon round the plane), legs, larm (or rarm, for a left-hand blow), look,
    hop, spin. Before the first key it swings in from `start`; after the last
    it settles into `idle` by `settle`.
      hand   'R' (the weapon arm), 'L' (a left-hand blow) or 'both' (the left
             arm mirrors the right)
      edge   'Y' (a blade's edge leads), 'X' (a hammer head / scythe blade
             leads) or 'arm' (a gauntlet: the fist is the weapon)
      two    two hands on the handle: the left hand this far along it"""

    def __init__(self, name, u, w, keys, start, idle, turn, settle, hit, lock, hand='R', edge='Y', two=None,
                 lead=0.025, arm_to=(0.1, -0.45, -1.0), arm_mix=0.35, trail=None, priority='Action'):
        self.name, self.keys, self.start, self.idle, self.settle = name, keys, start, idle, settle
        self.u = unit(u)
        w = np.asarray(w, dtype=float)
        self.w = unit(w - (w @ self.u) * self.u)
        self.turn, self.lead = turn, lead
        self.arm_to, self.arm_mix = unit(arm_to), arm_mix
        self.hand, self.edge, self.two = hand, edge, two
        self.hit, self.lock = hit, lock
        self.length, self.loop, self.priority = settle, False, priority
        self.trail = trail

    def _key(self, t):
        ks = self.keys
        if t <= ks[0][0]:
            return ks[0][1], dict(ks[0][3])
        for (t0, p0, _, x0), (t1, p1, e, x1) in zip(ks, ks[1:]):
            if t <= t1:
                k = ease(e, (t - t0) / (t1 - t0))
                return p0 + (p1 - p0) * k, mix_extras(x0, x1, k)
        return ks[-1][1], dict(ks[-1][3])

    def _dir(self, phi_deg):
        p = math.radians(phi_deg)
        return math.cos(p) * self.u + math.sin(p) * self.w

    def on_plane(self, t):
        phi, x = self._key(t)
        b = self._dir(phi)
        travel = self._dir(phi + 90)
        d = slerp(self._dir(phi + x.get('delta', 0)), self.arm_to, self.arm_mix)
        lead_phi, _ = self._key(t + self.lead)
        turn = self.turn[0] + self.turn[1] * lead_phi
        pose = {k: v for k, v in x.items() if k not in ('lean', 'tilt', 'delta', 'spin', 'rarm')}
        pose['root'] = (x.get('lean', 0), x.get('tilt', 0), turn)
        if x.get('spin'):
            pose['legspin'] = turn * x['spin']
        if self.edge == 'arm':
            b = d  # (a gauntlet: the fist is the weapon, the glove along the arm)
        if self.edge == 'X':
            e = np.cross(-b, travel)  # (so the weapon's +X leads)
        else:
            e = travel
        if self.hand == 'L':
            # the left arm travels round the plane; the right keeps its guard
            pose['larm'] = tuple(d)
            pose['lfwd'] = tuple(travel)
            pose['arm'] = x.get('rarm', self.idle['arm'])
        else:
            pose['arm'] = (d, b, e)
            if self.hand == 'both':
                pose['larm'] = mirror(d)
                pose['lfwd'] = mirror(travel)
        if self.two is not None:
            pose = two_hand(pose, self.two)
        return pose

    def at(self, t):
        first, last = self.keys[0][0], self.keys[-1][0]
        if t < first:
            return mix_dir(self.start, self.on_plane(first), ease('out', t / first))
        if t <= last:
            return self.on_plane(t)
        end = self.on_plane(last)
        lean, tilt, turn = end['root']
        while turn > 180:
            turn -= 360
            if 'legspin' in end:
                end['legspin'] -= 360
        end['root'] = (lean, tilt, turn)
        return mix_dir(end, dict(self.idle, legspin=0.0), ease('inout', (t - last) / (self.settle - last)))


def K(t, phi, e, lean=0, delta=0, legs='back', larm=None, look=AHEAD, hop=0.0, tilt=0, spin=0, rarm=None):
    x = {'lean': lean, 'tilt': tilt, 'delta': delta, 'legs': LEG[legs] if isinstance(legs, str) else legs,
         'look': look, 'hop': hop, 'spin': spin}
    if larm is not None:
        x['larm'] = larm
    if rarm is not None:
        x['rarm'] = rarm
    return (t, phi, e, x)


def idle_anim(name, idle, breathe):
    return DirAnim(name, [(0, idle, 'linear'), (1.2, breathe, 'inout'), (2.4, idle, 'inout')], loop=True, priority='Idle')


def breathe(idle, lean=1.5, arm=None):
    b = dict(idle)
    lean0, tilt0, turn0 = idle['root']
    b['root'] = (lean0 + lean, tilt0, turn0 + 1)
    if arm is not None:
        b['arm'] = arm
    return b


ANIMS = {}   # name -> animation (idle loops and swings)
STRINGS = {}  # type -> [idle name, swing names...]


def add(kind, idle, swings):
    ANIMS[kind + 'Idle'] = idle
    for s in swings:
        ANIMS[s.name] = s
    STRINGS[kind] = [kind + 'Idle'] + [s.name for s in swings]


def T(kind, n):
    return TIMING[kind][n - 1]


# ======================================================================
# GAUNTLETS (Fists): a boxer's guard, a right jab, a left hook, a rising
# uppercut. The fists are the weapons: each arm points where its fist goes.
# ======================================================================
F_R = unit((-0.28, 0.20, -1.0))   # the right fist up in front of the chin
F_L = unit((0.30, 0.16, -1.0))    # the left one a little further out
F_IDLE = {
    'root': (8, 0, -16),
    'legs': ((-0.26, -1, -0.34), (0.28, -1, 0.30)),
    'arm': (F_R, F_R, (0, 1, 0)),
    'larm': F_L,
    'lfwd': (0, 1, 0),
    'look': AHEAD,
    'hop': 0.0,
}
F_BREATHE = breathe(F_IDLE, 1.5, arm=(unit(F_R + np.array([0, 0.05, 0])), unit(F_R + np.array([0, 0.05, 0])), (0, 1, 0)))
hit, lock = T('Fists', 1)
F1 = TypeSwing(  # the jab: the right fist snaps straight out at the enemy's chin, the shoulder turning into it
    'FistsSwing1', u=(-0.05, 0.12, -1.0), w=(0.0, 1.0, 0.15), start=F_IDLE, idle=F_IDLE, settle=0.62, hit=hit, lock=lock,
    edge='arm', turn=(-6, 0.45), arm_mix=0.0, trail=(0.10, 0.24),
    keys=[
        K(0.06, -38, 'out', lean=6, legs='back', larm=F_L, look=AHEAD),
        K(0.10, -42, 'inout', lean=6, legs='back', larm=F_L, look=AHEAD),
        K(hit, 0, 'in2', lean=14, legs='lunge', larm=unit((0.34, 0.10, -1.0)), look=AHEAD),
        K(0.26, 6, 'out2', lean=15, legs='lunge', larm=unit((0.34, 0.08, -1.0)), look=AHEAD),
        K(lock, 4, 'linear', lean=12, legs='lunge', larm=unit((0.32, 0.10, -1.0)), look=AHEAD),
    ])
hit, lock = T('Fists', 2)
F2 = TypeSwing(  # the hook: the left fist swings round flat from the side, the whole body turning behind it
    'FistsSwing2', u=(0.05, 0.10, -1.0), w=(1.0, 0.0, 0.15), start=F1.at(F1.lock), idle=F_IDLE, settle=0.66, hit=hit, lock=lock,
    hand='L', edge='arm', turn=(4, -0.55), arm_mix=0.0, trail=(0.10, 0.26),
    keys=[
        K(0.07, -80, 'out', lean=8, legs='lunge', rarm=(F_R, F_R, (0, 1, 0))),
        K(0.11, -86, 'inout', lean=8, legs='lunge', rarm=(F_R, F_R, (0, 1, 0))),
        K(hit, 0, 'in2', lean=12, legs='pivot', rarm=(F_R, F_R, (0, 1, 0))),
        K(0.28, 55, 'out2', lean=12, legs='pivot', rarm=(F_R, F_R, (0, 1, 0))),
        K(lock, 60, 'linear', lean=10, legs='pivot', rarm=(F_R, F_R, (0, 1, 0))),
    ])
hit, lock = T('Fists', 3)
F3 = TypeSwing(  # the uppercut: dip low, then drive up off the floor, the right fist rising through the chin
    'FistsSwing3', u=(-0.1, 0.55, -0.85), w=(0.0, 0.85, 0.55), start=F2.at(F2.lock), idle=F_IDLE, settle=0.95, hit=hit, lock=lock,
    edge='arm', turn=(-4, 0.25), arm_mix=0.0, trail=(0.18, 0.36),
    keys=[
        K(0.12, -95, 'out', lean=24, legs='crouch', larm=F_L, look=AHEAD),
        K(0.18, -100, 'inout', lean=26, legs='crouch', larm=F_L, look=AHEAD),
        K(hit, 0, 'in2', lean=-8, legs='tuck', larm=F_L, look=(0, 0.25, -1), hop=0.55),
        K(0.42, 40, 'out2', lean=-10, legs='tuck', larm=F_L, look=(0, 0.35, -1), hop=0.3),
        K(lock, 44, 'linear', lean=-6, legs='back', larm=F_L, look=AHEAD, hop=0.0),
    ])
add('Fists', idle_anim('FistsIdle', F_IDLE, F_BREATHE), [F1, F2, F3])

# ======================================================================
# HAMMER: two hands, heavy. A diagonal chop from over the right shoulder,
# a flat backhand, and an overhead slam off a little leap (the shockwave).
# The head's face (its +X) leads every swing.
# ======================================================================
H_IDLE = {
    'root': (6, 0, -20),
    'legs': ((-0.32, -1, -0.34), (0.34, -1, 0.32)),
    # held across the body: hands low on the right, the head up at the left
    'arm': (unit((-0.30, -0.75, -0.60)), unit((-0.55, 0.78, -0.30)), (0.0, 0.3, -1.0)),
    'look': AHEAD,
    'hop': 0.0,
}
H_IDLE = two_hand(H_IDLE, (0.3, 2.4))
H_BREATHE = two_hand(breathe(H_IDLE, 1.5), (0.3, 2.4))
hit, lock = T('Hammer', 1)
H1 = TypeSwing(  # the heavy diagonal: wound up high behind the right shoulder, over the top and down across
    'HammerSwing1', u=(-0.25, -0.55, -1.0), w=(-0.4, -1.0, 0.35), start=H_IDLE, idle=H_IDLE, settle=1.3, hit=hit, lock=lock,
    edge='X', two=(-0.6, 2.4), turn=(4, 0.30), arm_to=(-0.35, -0.40, -0.85), arm_mix=0.40, trail=(0.30, 0.56),
    keys=[
        K(0.20, -165, 'out', lean=-6, delta=25, legs='back', look=AHEAD),
        K(0.30, -172, 'inout', lean=-8, delta=32, legs='back', look=AHEAD),
        K(hit, 0, 'in2', lean=22, delta=0, legs='deep', look=DOWN),
        K(0.60, 60, 'out2', lean=26, delta=-18, legs='deep', look=DOWN),
        K(lock, 64, 'linear', lean=22, delta=-15, legs='deep', look=AHEAD),
    ])
hit, lock = T('Hammer', 2)
H2 = TypeSwing(  # the backhand: from wound round the left hip, a flat sweep across the front at chest height
    'HammerSwing2', u=(0.2, -0.08, -1.0), w=(1.0, 0.05, 0.2), start=H1.at(H1.lock), idle=H_IDLE, settle=1.3, hit=hit, lock=lock,
    edge='X', two=(-0.6, 2.4), turn=(-6, -0.45), arm_to=(-0.35, -0.40, -0.85), arm_mix=0.40, trail=(0.30, 0.56),
    keys=[
        K(0.20, -140, 'out', lean=14, delta=25, legs='pivot', look=AHEAD),
        K(0.30, -146, 'inout', lean=14, delta=32, legs='pivot', look=AHEAD),
        K(hit, 0, 'in2', lean=12, delta=0, legs='lunge', look=AHEAD),
        K(0.60, 125, 'out2', lean=8, delta=-22, legs='back', look=AHEAD),
        K(lock, 130, 'linear', lean=6, delta=-20, legs='back', look=AHEAD),
    ])
hit, lock = T('Hammer', 3)
H3 = TypeSwing(  # the overhead slam: up with a little leap, the hammer high behind the head - and down it comes
    'HammerSwing3', u=(0.0, -0.62, -0.8), w=(0.0, -0.8, 0.62), start=H2.at(H2.lock), idle=H_IDLE, settle=1.65, hit=hit, lock=lock,
    edge='X', two=(-0.6, 2.4), turn=(-4, 0.02), arm_to=(-0.35, -0.30, -0.9), arm_mix=0.35, trail=(0.46, 0.72),
    keys=[
        K(0.30, -175, 'out', lean=-16, delta=20, legs='tuck', look=(0, 0.2, -1), hop=0.6),
        K(0.46, -182, 'inout', lean=-18, delta=26, legs='tuck', look=(0, 0.15, -1), hop=0.8),
        K(hit, 0, 'in2', lean=34, delta=0, legs='deep', look=DOWN, hop=0.0),
        K(0.80, 12, 'out2', lean=36, delta=-6, legs='deep', look=DOWN),
        K(lock, 12, 'linear', lean=32, delta=-5, legs='deep', look=DOWN),
    ])
add('Hammer', idle_anim('HammerIdle', H_IDLE, H_BREATHE), [H1, H2, H3])

# ======================================================================
# DAGGERS: one in each hand, low and coiled. A right stab, a left stab, a
# right slash across, and both blades crossing down off a hop.
# ======================================================================
D_R = unit((0.15, -0.55, -1.0))
D_L = unit((-0.15, -0.60, -1.0))
D_IDLE = {
    'root': (14, 0, -6),
    'legs': ((-0.28, -1, -0.40), (0.32, -1, 0.34)),
    'arm': (D_R, unit((0.05, 0.25, -1.0)), (0.0, 1.0, 0.0)),
    'larm': D_L,
    'lfwd': (0, 1, 0),
    'look': AHEAD,
    'hop': 0.0,
}
D_BREATHE = breathe(D_IDLE, 1.2)
hit, lock = T('Daggers', 1)
D1 = TypeSwing(  # a right stab: the blade drives straight at the enemy's chest
    'DaggersSwing1', u=(-0.05, 0.05, -1.0), w=(0.0, 1.0, 0.1), start=D_IDLE, idle=D_IDLE, settle=0.5, hit=hit, lock=lock,
    turn=(-8, 0.55), arm_to=(0.05, 0.0, -1.0), arm_mix=0.55, trail=(0.08, 0.2),
    keys=[
        K(0.05, -55, 'out', lean=10, legs='back', larm=D_L),
        K(0.08, -58, 'inout', lean=10, legs='back', larm=D_L),
        K(hit, 0, 'in2', lean=20, legs='lunge', larm=unit((-0.2, -0.7, -0.8))),
        K(0.22, 6, 'out2', lean=21, legs='lunge', larm=unit((-0.2, -0.7, -0.8))),
        K(lock, 5, 'linear', lean=18, legs='lunge', larm=unit((-0.2, -0.7, -0.8))),
    ])
hit, lock = T('Daggers', 2)
D2 = TypeSwing(  # a left stab: the other blade, the body turning round behind it
    'DaggersSwing2', u=(0.05, 0.05, -1.0), w=(0.0, 1.0, 0.1), start=D1.at(D1.lock), idle=D_IDLE, settle=0.5, hit=hit, lock=lock,
    hand='L', turn=(6, -0.55), arm_to=(-0.05, 0.0, -1.0), arm_mix=0.55, trail=(0.08, 0.2),
    keys=[
        K(0.05, -55, 'out', lean=12, legs='lunge', rarm=(unit((0.3, -0.7, -0.6)), unit((0.1, 0.3, -1)), (0, 1, 0))),
        K(0.08, -58, 'inout', lean=12, legs='lunge', rarm=(unit((0.3, -0.7, -0.6)), unit((0.1, 0.3, -1)), (0, 1, 0))),
        K(hit, 0, 'in2', lean=20, legs='pivot', rarm=(unit((0.35, -0.8, -0.3)), unit((0.1, 0.4, -1)), (0, 1, 0))),
        K(0.22, 6, 'out2', lean=21, legs='pivot', rarm=(unit((0.35, -0.8, -0.3)), unit((0.1, 0.4, -1)), (0, 1, 0))),
        K(lock, 5, 'linear', lean=18, legs='pivot', rarm=(unit((0.35, -0.8, -0.3)), unit((0.1, 0.4, -1)), (0, 1, 0))),
    ])
hit, lock = T('Daggers', 3)
D3 = TypeSwing(  # a right slash across: from out wide on the right, flat through and round to the left
    'DaggersSwing3', u=(-0.3, 0.0, -1.0), w=(-1.0, -0.05, 0.3), start=D2.at(D2.lock), idle=D_IDLE, settle=0.55, hit=hit, lock=lock,
    turn=(4, 0.45), arm_to=(0.1, -0.3, -1.0), arm_mix=0.35, trail=(0.07, 0.22),
    keys=[
        K(0.05, -110, 'out', lean=12, delta=20, legs='back', larm=D_L),
        K(0.08, -115, 'inout', lean=12, delta=25, legs='back', larm=D_L),
        K(hit, 0, 'in2', lean=16, delta=0, legs='lunge', larm=unit((-0.4, -0.8, 0.3))),
        K(0.24, 95, 'out2', lean=16, delta=-18, legs='pivot', larm=unit((-0.4, -0.8, 0.3))),
        K(lock, 100, 'linear', lean=14, delta=-15, legs='pivot', larm=unit((-0.4, -0.8, 0.3))),
    ])
hit, lock = T('Daggers', 4)
D4 = TypeSwing(  # both blades crossing: up off a hop, arms high and wide, and down through in an X
    'DaggersSwing4', u=(-0.35, -0.45, -1.0), w=(-0.45, -1.0, 0.3), start=D3.at(D3.lock), idle=D_IDLE, settle=0.85, hit=hit, lock=lock,
    hand='both', turn=(-4, 0.05), arm_to=(0.0, -0.3, -1.0), arm_mix=0.25, trail=(0.16, 0.34),
    keys=[
        K(0.10, -120, 'out', lean=-4, delta=15, legs='tuck', hop=0.35),
        K(0.16, -126, 'inout', lean=-6, delta=20, legs='tuck', hop=0.45),
        K(hit, 0, 'in2', lean=26, delta=0, legs='deep', hop=0.0, look=DOWN),
        K(0.38, 40, 'out2', lean=28, delta=-10, legs='deep', look=DOWN),
        K(lock, 42, 'linear', lean=24, delta=-8, legs='deep', look=AHEAD),
    ])
add('Daggers', idle_anim('DaggersIdle', D_IDLE, D_BREATHE), [D1, D2, D3, D4])

# ======================================================================
# SCYTHE: the long pole in both hands, the blade low. A wide sweep right to
# left, one back left to right, and a full turn with the blade out. The
# blade (its +X) leads, like a reaper's.
# ======================================================================
S_IDLE = {
    'root': (4, 0, -12),
    'legs': ((-0.28, -1, -0.30), (0.30, -1, 0.28)),
    # the pole upright at your right side, the blade high over your head
    'arm': (unit((0.35, -0.9, -0.25)), unit((0.02, 1.0, -0.12)), (1.0, 0.0, 0.0)),
    'larm': (-0.3, -0.95, -0.05),
    'lfwd': (0.3, 0, -1),
    'look': AHEAD,
    'hop': 0.0,
}
S_BREATHE = breathe(S_IDLE, 1.2)
hit, lock = T('Scythe', 1)
S1 = TypeSwing(  # the wide sweep: coiled round to the right, the blade low - a long flat reap right round to the left
    'ScytheSwing1', u=(-0.15, -0.30, -1.0), w=(-1.0, 0.0, 0.15), start=S_IDLE, idle=S_IDLE, settle=1.15, hit=hit, lock=lock,
    edge='X', two=(-0.7, 2.0), turn=(4, 0.50), arm_to=(-0.30, -0.50, -0.80), arm_mix=0.38, trail=(0.22, 0.48),
    keys=[
        K(0.16, -150, 'out', lean=4, delta=25, legs='back'),
        K(0.24, -156, 'inout', lean=4, delta=32, legs='back'),
        K(hit, 0, 'in2', lean=14, delta=0, legs='lunge', look=DOWN),
        K(0.50, 140, 'out2', lean=16, delta=-24, legs='pivot', look=AHEAD),
        K(lock, 146, 'linear', lean=14, delta=-20, legs='pivot', look=AHEAD),
    ])
hit, lock = T('Scythe', 2)
S2 = TypeSwing(  # sweeping back: from round on the left, a flat reap back across to the right
    'ScytheSwing2', u=(0.15, -0.30, -1.0), w=(1.0, 0.0, 0.15), start=S1.at(S1.lock), idle=S_IDLE, settle=1.15, hit=hit, lock=lock,
    edge='X', two=(-0.7, 2.0), turn=(-4, -0.50), arm_to=(-0.30, -0.50, -0.80), arm_mix=0.38, trail=(0.22, 0.48),
    keys=[
        K(0.16, -140, 'out', lean=14, delta=25, legs='pivot'),
        K(0.24, -146, 'inout', lean=14, delta=32, legs='pivot'),
        K(hit, 0, 'in2', lean=14, delta=0, legs='lunge', look=DOWN),
        K(0.50, 135, 'out2', lean=10, delta=-24, legs='back', look=AHEAD),
        K(lock, 140, 'linear', lean=8, delta=-20, legs='back', look=AHEAD),
    ])
hit, lock = T('Scythe', 3)
S3 = TypeSwing(  # the full turn: wound right round, then the whole body spins with the blade out flat
    'ScytheSwing3', u=(-0.15, -0.20, -1.0), w=(-1.0, 0.0, 0.15), start=S2.at(S2.lock), idle=S_IDLE, settle=1.45, hit=hit, lock=lock,
    edge='X', two=(-0.7, 2.0), turn=(6, 1.0), arm_to=(-0.30, -0.45, -0.80), arm_mix=0.36, trail=(0.36, 0.80),
    keys=[
        K(0.24, -120, 'out', lean=4, delta=22, legs='back', spin=0.0),
        K(0.36, -128, 'inout', lean=2, delta=28, legs='back', hop=0.2, spin=0.3),
        K(hit, 0, 'in2', lean=10, delta=0, legs='wide', spin=1.0),
        K(0.80, 300, 'out2', lean=12, delta=-18, legs='wide', spin=1.0),
        K(lock, 306, 'linear', lean=10, delta=-14, legs='wide', spin=1.0),
    ])
add('Scythe', idle_anim('ScytheIdle', S_IDLE, S_BREATHE), [S1, S2, S3])

# ======================================================================
# KATANA: two hands, a calm middle guard. A fast flat cut right to left, a
# rising cut low left to high right, and a dashing thrust. The edge leads.
# ======================================================================
K_IDLE = {
    'root': (6, 0, -10),
    'legs': ((-0.26, -1, -0.40), (0.30, -1, 0.34)),
    # middle guard: hands low in front, the blade pointing up at the enemy's throat
    'arm': (unit((-0.45, -0.55, -0.70)), unit((0.0, 0.40, -1.0)), (0.0, 1.0, 0.35)),
    'look': AHEAD,
    'hop': 0.0,
}
K_IDLE = two_hand(K_IDLE, (-0.75, -0.3))
K_BREATHE = two_hand(breathe(K_IDLE, 1.2), (-0.75, -0.3))
hit, lock = T('Katana', 1)
K1 = TypeSwing(  # the flat cut: cocked back over the right shoulder, a fast level cut right across to the left
    'KatanaSwing1', u=(-0.25, 0.02, -1.0), w=(-1.0, -0.05, 0.25), start=K_IDLE, idle=K_IDLE, settle=0.75, hit=hit, lock=lock,
    two=(-0.75, -0.3), turn=(6, 0.52), arm_to=(-0.45, -0.45, -0.77), arm_mix=0.45, trail=(0.10, 0.32),
    keys=[
        K(0.07, -150, 'out', lean=0, delta=30, legs='back'),
        K(0.10, -157, 'inout', lean=-1, delta=38, legs='back'),
        K(hit, 0, 'in2', lean=10, delta=0, legs='lunge'),
        K(0.30, 145, 'out2', lean=12, delta=-25, legs='pivot'),
        K(lock, 150, 'linear', lean=10, delta=-20, legs='pivot'),
    ])
hit, lock = T('Katana', 2)
K2 = TypeSwing(  # the rising cut: from low behind the left hip, up through the enemy and high over the right shoulder
    'KatanaSwing2', u=(0.35, 0.12, -1.0), w=(1.0, 0.70, 0.10), start=K1.at(K1.lock), idle=K_IDLE, settle=0.75, hit=hit, lock=lock,
    two=(-0.75, -0.3), turn=(-8, -0.5), arm_to=(-0.45, -0.45, -0.77), arm_mix=0.45, trail=(0.10, 0.32),
    keys=[
        K(0.07, -140, 'out', lean=15, delta=30, legs='pivot'),
        K(0.10, -146, 'inout', lean=15, delta=38, legs='pivot'),
        K(hit, 0, 'in2', lean=6, delta=0, legs='lunge'),
        K(0.30, 145, 'out2', lean=-4, delta=-25, legs='back'),
        K(lock, 150, 'linear', lean=-2, delta=-20, legs='back'),
    ])
hit, lock = T('Katana', 3)
K3 = TypeSwing(  # the dashing thrust: pulled back low by the right hip, then the blade drives straight out, a long lunge behind it
    'KatanaSwing3', u=(0.0, 0.04, -1.0), w=(0.0, 1.0, 0.05), start=K2.at(K2.lock), idle=K_IDLE, settle=1.0, hit=hit, lock=lock,
    two=(-0.75, -0.3), turn=(-10, 0.2), arm_to=(-0.40, -0.20, -0.90), arm_mix=0.55, trail=(0.18, 0.36),
    keys=[
        K(0.12, -16, 'out', lean=-4, delta=-22, legs='back'),
        K(0.18, -18, 'inout', lean=-6, delta=-25, legs='back'),
        K(hit, 0, 'in2', lean=30, delta=0, legs='deep'),
        K(0.45, 2, 'out2', lean=30, delta=0, legs='deep'),
        K(lock, 2, 'linear', lean=26, delta=0, legs='deep'),
    ])
add('Katana', idle_anim('KatanaIdle', K_IDLE, K_BREATHE), [K1, K2, K3])


# ----------------------------------------------------------------------
# how a type's whole string plays when you click through it (for previews)
# ----------------------------------------------------------------------
class String:
    def __init__(self, kind, lead_in=0.35, tail=0.35):
        names = STRINGS[kind]
        self.idle = ANIMS[names[0]]
        self.parts = []
        t = lead_in
        for name in names[1:]:
            s = ANIMS[name]
            self.parts.append((t, s))
            t += s.lock
        last_t, last = self.parts[-1]
        self.lead_in = lead_in
        self.length = last_t + last.settle + tail
        self.loop = False

    def at(self, t):
        if t < self.lead_in:
            return self.idle.at(t)
        for i, (t0, s) in enumerate(self.parts):
            nxt = self.parts[i + 1][0] if i + 1 < len(self.parts) else math.inf
            if t < nxt:
                return s.at(min(t - t0, s.settle))
        return self.idle.at(t)

    def cutting(self, t):
        for t0, s in self.parts:
            if s.trail and t0 + s.trail[0] <= t <= t0 + s.trail[1]:
                return True
        return False

    def hits(self):
        return [t0 + s.hit for t0, s in self.parts]
