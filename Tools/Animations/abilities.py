"""The weapon abilities' animations (ReplicatedStorage/Moves: what each ability
does, step by step) - made the way the types' swings are (weapon_types.py:
posing by direction, swings round a plane). Each one is timed to its move:
its big moment lands exactly when the move's hit (or effect) is due, and it
lasts the move's Time.

    python3 abilities.py                  -> abilities/<weapon>.rbxmx (one animation each,
                                             for Tools/Upload/upload_assets.bat)
    python3 abilities.py preview [pack]   -> ../../Docs/animations/<pack>_abilities.mp4 and .png
                                             (slime - the default -, knight or speedway)

The Slime, Knight and Speedway packs so far; the others come with their weapons.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anims  # noqa: E402
import combo  # noqa: E402
import weapon_types as wt  # noqa: E402
from anims import DirAnim, slerp, unit  # noqa: E402
from weapon_types import K, TypeSwing, two_hand  # noqa: E402

ABILITIES = {}  # weapon id -> (its type, its animation)

AHEAD, DOWN = wt.AHEAD, wt.DOWN


def pose(root, legs, arm, larm=None, look=AHEAD, hop=0.0, lfwd=None):
    p = {'root': root, 'legs': wt.LEG[legs] if isinstance(legs, str) else legs, 'arm': arm, 'look': look, 'hop': hop}
    if larm is not None:
        p['larm'] = unit(larm)
    if lfwd is not None:
        p['lfwd'] = lfwd
    return p


def fist(d):
    """a gauntlet's arm: the fist is the weapon, so it points where the arm does"""
    d = unit(d)
    return (d, d, (0, 1, 0))


# ======================================================================
# SLIME
# ======================================================================
# GOO GLOVES - Sticky Fists: fling both fists out wide, then CLAP them
# together in front of your chest (the goo splats at 0.18), press them there,
# and let go
ABILITIES['GooGloves'] = ('Fists', DirAnim('GooGlovesAbility', [
    (0.00, pose((8, 0, -16), 'back', fist((-0.28, 0.2, -1.0)), (0.30, 0.16, -1.0), lfwd=(0, 1, 0)), 'linear'),
    (0.09, pose((-6, 0, 0), 'square', fist((0.92, 0.38, -0.30)), (-0.92, 0.38, -0.30), look=(0, 0.1, -1), lfwd=(0, 1, 0)), 'out'),
    (0.18, pose((14, 0, 0), 'lunge', fist((-0.56, 0.12, -0.82)), (0.56, 0.12, -0.82), lfwd=(0, 1, 0)), 'in2'),
    (0.32, pose((16, 0, 0), 'lunge', fist((-0.54, 0.16, -0.83)), (0.54, 0.16, -0.83), lfwd=(0, 1, 0)), 'out'),
    (0.55, pose((6, 0, -8), 'back', fist((0.12, -0.92, -0.35)), (-0.12, -0.92, -0.35), lfwd=(0.3, 0, -1)), 'inout'),
], priority='Action3'))

# JELLYBLADE - Wobble Guard: the blade snaps up in front of you, flat to the
# enemy, the free hand braced on it (the jelly bubble pops up at 0.15);
# hold, then back to the stance
S_IDLE = combo.IDLE
J_GUARD = pose((4, 0, -2), 'back', (unit((-0.48, -0.26, -0.84)), unit((0.0, 1.0, 0.06)), (1.0, 0.0, 0.0)),
               (0.46, 0.20, -0.87), look=AHEAD, lfwd=(0.9, 0.3, 0.2))
J_GUARD2 = pose((6, 0, -4), 'back', (unit((-0.46, -0.22, -0.86)), unit((0.02, 1.0, 0.08)), (1.0, 0.0, 0.0)),
                (0.44, 0.24, -0.87), look=AHEAD, lfwd=(0.9, 0.3, 0.2))
ABILITIES['Jellyblade'] = ('Sword', DirAnim('JellybladeAbility', [
    (0.00, S_IDLE, 'linear'),
    (0.15, J_GUARD, 'snap'),
    (0.45, J_GUARD2, 'inout'),
    (0.60, S_IDLE, 'inout'),
], priority='Action3'))

# GELATIN HAMMER - Goo Slam: up with the hop, the hammer high behind your
# head - and down it slams (0.42, the splat), sinking into it
ABILITIES['GelatinHammer'] = ('Hammer', TypeSwing(
    'GelatinHammerAbility', u=(0.0, -0.62, -0.8), w=(0.0, -0.8, 0.62), start=wt.H_IDLE, idle=wt.H_IDLE, settle=1.0,
    hit=0.42, lock=0.78, edge='X', two=(-0.6, 2.4), turn=(-4, 0.02), arm_to=(-0.35, -0.30, -0.9), arm_mix=0.35,
    trail=(0.30, 0.50), priority='Action3',
    keys=[
        K(0.16, -176, 'out', lean=-16, delta=20, legs='tuck', look=(0, 0.25, -1), hop=0.6),
        K(0.30, -184, 'inout', lean=-19, delta=26, legs='tuck', look=(0, 0.15, -1), hop=0.8),
        K(0.42, 0, 'in2', lean=36, delta=0, legs='deep', look=DOWN, hop=0.0),
        K(0.60, 12, 'out2', lean=38, delta=-6, legs='deep', look=DOWN),
        K(0.78, 12, 'linear', lean=34, delta=-5, legs='deep', look=DOWN),
    ]))

# OOZE DAGGERS - Slime Trail: drop low with both blades crossed, dash through
# like that (0.1 to 0.38), then rip them out wide in an X (0.4, the cut)
ABILITIES['OozeDaggers'] = ('Daggers', TypeSwing(
    'OozeDaggersAbility', u=(-0.10, -0.12, -1.0), w=(1.0, 0.0, 0.25), start=wt.D_IDLE, idle=wt.D_IDLE, settle=0.75,
    hit=0.40, lock=0.60, hand='both', turn=(-2, 0.05), arm_to=(0.05, -0.25, -1.0), arm_mix=0.30,
    trail=(0.36, 0.50), priority='Action3',
    keys=[
        K(0.07, -72, 'out', lean=30, delta=8, legs='crouch'),
        K(0.12, -82, 'inout', lean=36, delta=10, legs='deep'),
        K(0.36, -86, 'hold', lean=38, delta=10, legs='deep'),
        K(0.40, 0, 'in2', lean=24, delta=0, legs='lunge'),
        K(0.50, 72, 'out2', lean=18, delta=-10, legs='lunge'),
        K(0.60, 76, 'linear', lean=16, delta=-8, legs='back'),
    ]))

# ACID SCYTHE - Acid Rain: coil, then the whole body spins right round with
# the blade out flat (0.22, the sweep) and the acid flies off it (0.3)
ABILITIES['AcidScythe'] = ('Scythe', TypeSwing(
    'AcidScytheAbility', u=(-0.15, -0.20, -1.0), w=(-1.0, 0.0, 0.15), start=wt.S_IDLE, idle=wt.S_IDLE, settle=1.0,
    hit=0.22, lock=0.62, edge='X', two=(-0.7, 2.0), turn=(6, 1.0), arm_to=(-0.30, -0.45, -0.80), arm_mix=0.36,
    trail=(0.14, 0.50), priority='Action3',
    keys=[
        K(0.08, -110, 'out', lean=4, delta=22, legs='back', spin=0.0),
        K(0.14, -122, 'inout', lean=2, delta=26, legs='back', hop=0.15, spin=0.3),
        K(0.22, 0, 'in2', lean=10, delta=0, legs='wide', spin=1.0),
        K(0.45, 310, 'out2', lean=12, delta=-18, legs='wide', spin=1.0),
        K(0.62, 318, 'linear', lean=10, delta=-14, legs='wide', spin=1.0),
    ]))

# GELATINOUS EDGE - Oozark's Jaw: a quick-draw. Crouch with your hand on the
# hilt at your left hip, the blade still "sheathed" behind you, and hold
# still while the jaw opens (0.3) - then a flash of a draw straight across
# (0.68, the chomp) and the blade out to the right
ABILITIES['GelatinousEdge'] = ('Katana', TypeSwing(
    'GelatinousEdgeAbility', u=(0.0, 0.08, -1.0), w=(1.0, 0.0, 0.10), start=wt.K_IDLE, idle=wt.K_IDLE, settle=1.1,
    hit=0.68, lock=0.92, turn=(8, 0.25), arm_to=(0.10, -0.20, -1.0), arm_mix=0.30,
    trail=(0.62, 0.80), priority='Action3',
    keys=[
        K(0.10, -150, 'out', lean=18, delta=62, legs='crouch', larm=(0.25, -0.9, -0.25), look=AHEAD),
        K(0.58, -156, 'hold', lean=22, delta=64, legs='crouch', larm=(0.28, -0.9, -0.22), look=AHEAD),
        K(0.68, 0, 'in2', lean=10, delta=0, legs='lunge', larm=(-0.4, -0.85, 0.2), look=AHEAD),
        K(0.80, 112, 'out2', lean=6, delta=-12, legs='lunge', larm=(-0.45, -0.85, 0.25), look=AHEAD),
        K(0.92, 116, 'linear', lean=4, delta=-10, legs='lunge', larm=(-0.45, -0.85, 0.25), look=AHEAD),
    ]))


# ======================================================================
# KEY POSES (the Knight and Speedway packs): a Poses animation keys whole
# poses, the weapons held with the helpers below
# ======================================================================
LFWD = (0.3, 0.0, -1.0)  # (dir_transforms' own twist for the left arm, when a pose gives none)


def carry(d0, f0, d1):
    """f0 (a direction across d0) turned along with d0 onto d1 the shortest way"""
    d0, d1, f0 = unit(d0), unit(d1), np.asarray(f0, float)
    ax = np.cross(d0, d1)
    s, c = np.linalg.norm(ax), float(d0 @ d1)
    if s < 1e-9:
        return f0
    ax = ax / s
    return f0 * c + np.cross(ax, f0) * s + ax * (ax @ f0) * (1 - c)


def turned(p, yaw):
    """a direction pose with the whole body turned round by yaw degrees (+ to
    the left), rigidly: the chest (leaning and all), the arms, the weapon, the
    look and the legs all go round together (the legs hang off the chest, so
    they come round with it)"""
    if not yaw:
        return p
    import r6
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    rot = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    p = dict(p)
    p['arm'] = tuple(rot @ np.asarray(v, float) for v in p['arm'])
    for k in ('larm', 'lfwd', 'look'):
        if k in p:
            p[k] = rot @ np.asarray(p[k], float)
    # (the chest: turned as a whole, then back into the root's lean, tilt and
    # turn - CFrame.Angles' X, Y, Z in the root joint's own frame)
    r0 = r6.JOINTS['RootJoint'][3][:3, :3]
    n = r0.T @ rot @ chest_rot(p['root']) @ r0
    p['root'] = (math.degrees(math.atan2(-n[1, 2], n[2, 2])), math.degrees(math.asin(float(np.clip(n[0, 2], -1, 1)))),
                 math.degrees(math.atan2(-n[0, 1], n[0, 0])))
    return p


class Poses(DirAnim):
    """key poses (a DirAnim) with what the swings have too: `two` keeps the left
    hand on the handle every frame (studs along it, as two_hand; a key's `grip`
    0 lets go - a one-handed stance), `hit` is the big moment (its marker),
    `trail` the smear (Cut, Through) - or `marks`, all its moments (name,
    time). A key pose's `yaw` turns the whole body round (a spin: 360 is right
    round to the left, -360 to the right) - the rest of it is posed as if
    facing forward"""

    def __init__(self, name, keys, two=None, hit=None, trail=None, marks=None):
        keys = [(t, dict(p), e) for t, p, e in keys]
        # (a free left arm's twist, where a key doesn't give one: carried on
        # from the key before along the shortest turn, so it never twists
        # round on its own - the stances at the ends keep theirs)
        for i, (t, p, e) in enumerate(keys):
            if 'larm' in p and 'lfwd' not in p:
                if i in (0, len(keys) - 1) or (two is not None and p.get('grip', 1.0) > 0):
                    p['lfwd'] = LFWD
                else:
                    before = keys[i - 1][1]
                    p['lfwd'] = tuple(carry(before['larm'], before['lfwd'], p['larm']))
        if two is not None:
            keys = [(t, two_hand(p, two) if p.get('grip', 1.0) > 0 else p, e) for t, p, e in keys]
        DirAnim.__init__(self, name, keys, priority='Action3')
        self.two, self.hit, self.trail = two, hit, trail
        if marks is not None:
            self.marks = marks

    def at(self, t):
        p = DirAnim.at(self, t)
        yaw, grip = p.pop('yaw', 0.0), p.pop('grip', 1.0)
        if self.two is not None and grip > 0:
            held = two_hand(p, self.two)
            for k in ('larm', 'lfwd'):
                p[k] = slerp(p.get(k, held[k]), held[k], grip) if grip < 1 else held[k]
        return turned(p, yaw)


def shown(anim, *moments):
    """the moments the preview's sheet shows: (time, what's happening)"""
    anim.show = list(moments)
    return anim


def chest_rot(root):
    """the chest's rotation for a root (lean, tilt, turn), as dir_transforms has it"""
    import r6
    _, _, _, c0, c1 = r6.JOINTS['RootJoint']
    return (c0 @ r6.transforms({'Root': tuple(root)})['RootJoint'] @ r6.inv(c1))[:3, :3]


def planted(root, legs):
    """legs (a LEG name, or (left, right)) pointing where they're told in the
    character's own space whatever the chest does - dir_transforms hangs them
    off the chest (they lean and turn with it), so that's taken back off"""
    legs = wt.LEG[legs] if isinstance(legs, str) else legs
    back = chest_rot(root).T
    return tuple(tuple(back @ unit(v)) for v in legs)


def level(root, legs, rounds=16):
    """legs (in the character's own space) with the lower foot's leg spread
    out until both feet are on the floor - a low or tilted stance keeps both
    feet down instead of one hanging in the air"""
    import r6
    legs = [unit(v) for v in (wt.LEG[legs] if isinstance(legs, str) else legs)]
    still = ((0.0, -1.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0))
    for _ in range(rounds):
        w = r6.solve(anims.dir_transforms({'root': root, 'legs': planted(root, legs), 'arm': still, 'larm': (0, -1, 0)}))
        low = [min((w[leg] @ np.array([sx, -1.0, sz, 1.0]))[1] for sx in (-0.5, 0.5) for sz in (-0.5, 0.5))
               for leg in ('Left Leg', 'Right Leg')]
        gap = low[1] - low[0]
        if abs(gap) < 0.01:
            break
        i = 0 if gap > 0 else 1  # (the lower foot: spread its leg so it comes up)
        v = legs[i] / -legs[i][1]
        v[[0, 2]] *= 1 + 0.6 * abs(gap)
        legs[i] = unit(v)
    return tuple(tuple(v) for v in legs)


def feet_of(p):
    """where a pose's legs really point, in the character's own space (for
    planted: to keep a stance's feet where they are)"""
    rot = chest_rot(p['root'])
    return tuple(tuple(rot @ unit(v)) for v in p['legs'])


def key(root, legs, arm, larm=None, look=AHEAD, hop=0.0, lfwd=None, yaw=None):
    """a key pose like pose(), its legs planted (planted) - and `yaw`, the
    whole body turned round (see Poses)"""
    p = pose(root, planted(root, legs), arm, larm, look=look, hop=hop, lfwd=lfwd)
    if yaw is not None:
        p['yaw'] = yaw
    return p


def hands(root, at, b, e):
    """the weapon arm pointed so the right hand lands `at` - studs from the
    middle of the chest, in the chest's own space (x right, y up, -z forward) -
    holding the weapon along b, its front towards e. Two hands only meet near
    the middle (R6 arms don't bend): in front of the chest or the face"""
    rot = chest_rot(root)
    b = unit(b)
    joint = np.array([1.0, 0.5, 0.0])  # (the right shoulder, on the chest)
    d = unit(np.asarray(at, float) - joint)
    for _ in range(8):
        # (the hand hangs half a stud off the arm's line, to its side)
        dr = rot @ d
        side = rot.T @ np.cross(dr, unit(b - (b @ dr) * dr))
        d = unit(np.asarray(at, float) - joint - 0.5 * side)
    return (rot @ d, b, unit(e))


def chop(root, at, b):
    """a hammer in both hands (see hands), its head's face (+X: the Shovel
    Hammer's spade) leading a chop round the body's left-right axis - the
    handle's +Y along that axis - so the face turns with it, never flips"""
    return hands(root, at, b, (1.0, 0.0, 0.0))


def hammer(root, legs, at, b, look=AHEAD, hop=0.0):
    """a key pose with the hammer in both hands, chopping (see chop)"""
    return key(root, legs, chop(root, at, b), look=look, hop=hop)


def scythe(root, at, b, v):
    """a scythe's arm (see hands): its pole along b, its blade (+X) out towards v"""
    b = unit(b)
    return hands(root, at, b, np.cross(unit(v), b))


def katana(root, legs, at, b, e=None, look=AHEAD, hop=0.0):
    """the katana in both hands (the left one on the hilt below the right); its
    edge turns with the blade round the body's left-right axis unless told"""
    b = unit(b)
    if e is None:
        e = np.cross((1.0, 0.0, 0.0), b)  # (up when it points ahead, as in the stance)
    return key(root, legs, hands(root, at, b, e), look=look, hop=hop)


def blade(d, b):
    """a one-handed blade: its edge turns with it round the body's left-right
    axis (up when it points ahead, as in the stance) - the wrist never quite
    straight, so the grip's twist is always settled"""
    b = unit(b)
    e = np.cross((1.0, 0.0, 0.0), b)
    return (unit(d), b, unit(e) if np.linalg.norm(e) > 0.2 else (0.0, 1.0, 0.0))


def gauntlets(root, legs, right, left, look=AHEAD, hop=0.0):
    """both fists (the gauntlets are the weapons: see fist), the left arm's
    twist turning with it round the body's left-right axis"""
    left = unit(left)
    return key(root, legs, fist(right), left, look=look, hop=hop,
               lfwd=unit(np.cross((1.0, 0.0, 0.0), left) + (0, 0.05, 0)))


# ======================================================================
# KNIGHT
# ======================================================================
# SHOVEL HAMMER - Dig Slam: heave it up over your head, chop the spade down
# into the ground in front of you (0.28, the dirt bursts), lever it and toss
# the dirt back over your right shoulder
H_FEET = feet_of(wt.H_IDLE)
DIG_FEET = ((-0.30, -1, -0.62), (0.30, -1, 0.50))  # (stepped in, the weight over the front foot)
ABILITIES['ShovelHammer'] = ('Hammer', shown(Poses('ShovelHammerAbility', [
    (0.00, dict(wt.H_IDLE, grip=0.0), 'linear'),
    (0.12, hammer((-10, 0, -6), H_FEET, (0.1, 1.40, -0.95), (0.03, 0.92, 0.40), look=(0, 0.35, -1), hop=0.06), 'out'),
    (0.19, hammer((-20, 0, -4), H_FEET, (0.1, 1.45, -0.95), (0.03, 0.64, 0.77), look=(0, 0.4, -1), hop=0.1), 'inout'),
    (0.245, hammer((10, 0, -4), 'lunge', (0.1, 0.60, -1.25), (0.0, 0.85, -0.52), look=AHEAD), 'in'),
    (0.28, hammer((32, 0, -4), DIG_FEET, (0.1, -0.80, -0.75), (-0.08, -0.60, -0.80), look=DOWN), 'linear'),
    (0.34, hammer((35, 0, -4), DIG_FEET, (0.1, -0.85, -0.70), (-0.08, -0.66, -0.75), look=DOWN), 'out'),
    (0.40, hammer((18, 0, -8), DIG_FEET, (0.1, -0.85, -0.75), (-0.10, -0.35, -0.93), look=DOWN), 'inout'),
    (0.44, hammer((2, 0, -14), DIG_FEET, (0.2, 0.50, -1.2), (0.10, 0.95, -0.30), look=AHEAD), 'in'),
    (0.49, hammer((-18, 0, -28), 'back', (0.45, 1.30, -0.85), (0.35, 0.40, 0.85), look=(0, 0.3, -1), hop=0.06), 'out'),
    (0.60, dict(wt.H_IDLE, grip=0.0), 'inout'),
], two=(-0.8, -0.3), hit=0.28, trail=(0.22, 0.30)),
    (0.0, 'STANCE'), (0.19, 'HEAVED UP'), (0.28, 'DIG'), (0.34, 'DUG IN'), (0.40, 'LEVER'), (0.49, 'TOSS')))

# RELIC DAGGERS - Treasure Eye: both blades snap up crossed in an X in front
# of your eyes (0.12, the golden glint), then a cocky twirl of the right one
# and back to the stance
D_FEET = feet_of(wt.D_IDLE)
D_X = key((-6, 0, 0), D_FEET, hands((-6, 0, 0), (0.50, 0.98, -1.05), (-0.70, 0.70, -0.12), (0.70, 0.70, 0.0)),
          (0.40, 0.40, -0.82), look=(0, 0.0, -1), lfwd=(-0.70, 0.70, 0.0))
D_X2 = key((-9, 3, 2), D_FEET, hands((-9, 3, 2), (0.50, 1.02, -1.03), (-0.68, 0.72, -0.10), (0.72, 0.68, 0.0)),
           (0.40, 0.42, -0.81), look=(0.08, 0.1, -1), lfwd=(-0.70, 0.70, 0.0))


def twirl(b, e):
    """the right dagger spinning round the fist, the arm out to the side"""
    return key((-4, 3, -6), D_FEET, (unit((0.45, -0.25, -0.86)), unit(b), unit(e)), (-0.15, -0.60, -1.0),
               look=(0.12, 0.05, -1), lfwd=(0, 1, 0))


ABILITIES['RelicDaggers'] = ('Daggers', shown(Poses('RelicDaggersAbility', [
    (0.00, wt.D_IDLE, 'linear'),
    (0.12, D_X, 'snap'),
    (0.21, D_X2, 'inout'),
    (0.26, twirl((0, 1, 0), (1, 0, 0)), 'inout'),
    (0.30, twirl((1, 0, 0), (0, -1, 0)), 'linear'),
    (0.34, twirl((0, -1, 0), (-1, 0, 0)), 'linear'),
    (0.38, twirl((-1, 0, 0), (0, 1, 0)), 'linear'),
    (0.42, twirl((0, 1, 0), (1, 0, 0)), 'out'),
    (0.50, wt.D_IDLE, 'inout'),
], hit=0.12), (0.0, 'STANCE'), (0.12, 'GLINT'), (0.21, 'HOLD'), (0.30, 'TWIRL'), (0.38, 'TWIRL'), (0.5, 'STANCE')))

# SPADE SCYTHE - Dirt Spin: drop low, wound round to the left, then the whole
# body spins right round the other way with the blade skimming the ground
# (0.24), flinging the dirt (0.3) - finishing wide and low, and up it scoops
# into the stance
LOW = ((-0.55, -1, -0.30), (0.55, -1, 0.30))  # (feet wide apart: the hips drop)


def reap(root, at, b, v, legs=LOW, look=DOWN, yaw=0.0):
    """the scythe in both hands, its blade (+X) out towards v"""
    return key(root, legs, scythe(root, at, b, v), look=look, yaw=yaw)


S_SWEEP = dict(at=(0.35, -0.45, -1.0), b=(0.10, -0.46, -0.88), v=(1.0, 0.0, 0.12))  # (low in front, going right)
ABILITIES['SpadeScythe'] = ('Scythe', shown(Poses('SpadeScytheAbility', [
    (0.00, dict(wt.S_IDLE, grip=0.0), 'linear'),
    (0.10, reap((26, 0, 22), yaw=45, **S_SWEEP), 'out'),
    (0.17, reap((30, 0, 26), yaw=58, **S_SWEEP), 'inout'),
    (0.24, reap((30, 0, 0), yaw=0, **S_SWEEP), 'in'),
    (0.30, reap((30, 0, -4), yaw=-95, **S_SWEEP), 'linear'),
    (0.46, reap((27, 0, -6), yaw=-318, **S_SWEEP), 'out2'),
    (0.62, reap((16, 0, -10), (0.45, -0.30, -1.0), (0.55, -0.30, -0.78), (0.80, 0.0, 0.60), legs='wide', look=AHEAD,
                yaw=-340), 'out'),
    (0.90, dict(wt.S_IDLE, yaw=-360, grip=0.0), 'inout'),
], two=(-0.9, -0.3), hit=0.24, marks=[('Cut', 0.17), ('Hit', 0.24), ('Clods', 0.30), ('Through', 0.46)]),
    (0.0, 'STANCE'), (0.17, 'LOW, WOUND'), (0.24, 'SPIN HIT'), (0.30, 'CLODS'), (0.46, 'ROUND'), (0.62, 'WIDE')))

# HONOUR BLADE - Pogo Drop: crouch, spring up, and by the top of the leap the
# blade points straight down under you like a pogo stick; land blade-first on
# them (0.58), bounce straight up with it still under you (0.62), and plunge
# again (1.04)
def pogo(root, legs, at, b=(0.0, -1.0, 0.04), look=DOWN, hop=0.0):
    """the katana held blade-down under you in both hands (its edge forward)"""
    return katana(root, legs, at, b, look=look, hop=hop)


K_FEET = feet_of(wt.K_IDLE)
FROG = ((-0.55, -0.72, -0.42), (0.55, -0.72, -0.42))  # (tucked in the air: knees up and wide, the blade between)
FROG2 = ((-0.60, -0.62, -0.50), (0.60, -0.62, -0.50))
LAND = ((-0.55, -1, -0.40), (0.55, -1, 0.30))  # (landed wide and low)
ABILITIES['HonourBlade'] = ('Katana', shown(Poses('HonourBladeAbility', [
    (0.00, dict(wt.K_IDLE, grip=0.0), 'linear'),
    (0.06, katana((24, 0, -6), 'crouch', (0.1, 0.0, -1.15), (0.0, 0.55, -0.83)), 'out'),
    (0.15, katana((-8, 0, 0), 'tuck', (0.1, 1.30, -0.95), (0.0, 1.0, 0.12), look=(0, 0.35, -1), hop=0.5), 'out'),
    (0.25, katana((0, 0, 0), FROG, (0.1, 0.45, -1.25), (0.0, 0.05, -1.0), look=AHEAD, hop=0.8), 'inout'),
    (0.35, pogo((6, 0, 0), FROG, (0.1, -0.25, -1.1), hop=0.95), 'out'),
    (0.49, pogo((3, 0, 0), FROG2, (0.1, -0.15, -1.1), hop=0.85), 'inout'),
    (0.58, pogo((36, 0, 0), LAND, (0.1, -0.85, -0.85), (0.0, -1.0, -0.15)), 'in2'),
    (0.62, pogo((30, 0, 0), LAND, (0.1, -0.75, -0.92), (0.0, -1.0, -0.12)), 'out'),
    (0.70, pogo((-2, 0, 0), 'tuck', (0.1, -0.20, -1.1), look=AHEAD, hop=0.45), 'out'),
    (0.80, pogo((6, 0, 0), FROG2, (0.1, -0.20, -1.1), hop=0.95), 'out'),
    (0.96, pogo((3, 0, 0), FROG, (0.1, -0.15, -1.1), hop=0.85), 'inout'),
    (1.04, pogo((42, 0, 0), LAND, (0.1, -0.90, -0.80), (0.0, -1.0, -0.18)), 'in2'),
    (1.16, pogo((44, 0, 0), LAND, (0.1, -0.92, -0.78), (0.0, -1.0, -0.18)), 'out'),
    (1.30, katana((16, 0, -8), K_FEET, (0.1, 0.10, -1.2), (0.0, 0.30, -1.0)), 'inout'),
    (1.45, dict(wt.K_IDLE, grip=0.0), 'inout'),
], two=(-0.75, -0.3), hit=0.58, marks=[('Hit', 0.58), ('Bounce', 0.62), ('Hit', 1.04)]),
    (0.06, 'CROUCH'), (0.15, 'SPRING'), (0.35, 'POGO'), (0.58, 'PLUNGE'), (0.80, 'BOUNCE'), (1.04, 'PLUNGE 2')))

# ANCHOR FISTS - Anchor Pull: wind up and hurl the anchor overhand with the
# right fist (let go at 0.25), get reeled in along the chain gripping it with
# both fists, leaning hard into the pull, then a double axe-handle: both
# fists up and SLAM down into the ground (0.66)
BACK = ((-0.30, -1, -0.40), (0.30, -1, 0.22))  # (the weight on the back foot)
DRAG = ((-0.25, -1, -0.38), (0.30, -1, 0.80))  # (dragged along: the back foot trailing)
WIDE_LOW = ((-0.62, -1, -0.35), (0.62, -1, 0.30))
ABILITIES['AnchorFists'] = ('Fists', shown(Poses('AnchorFistsAbility', [
    (0.00, wt.F_IDLE, 'linear'),
    (0.12, gauntlets((-12, 0, -36), BACK, (0.35, 0.75, 0.55), (0.10, 0.12, -1.0)), 'out'),
    (0.19, gauntlets((-15, 0, -40), BACK, (0.28, 0.60, 0.75), (0.12, 0.14, -1.0)), 'inout'),
    (0.25, gauntlets((20, 0, 18), 'lunge', (0.0, 0.12, -1.0), (-0.30, -0.60, 0.70)), 'in2'),
    (0.31, gauntlets((26, 0, 20), 'lunge', (-0.10, -0.35, -0.93), (-0.35, -0.65, 0.65)), 'out'),
    (0.38, gauntlets((34, 0, 0), DRAG, (-0.22, 0.02, -1.0), (0.22, 0.02, -1.0), hop=0.08), 'inout'),
    (0.50, gauntlets((38, 0, 0), DRAG, (-0.20, -0.02, -1.0), (0.20, -0.02, -1.0), hop=0.12), 'linear'),
    (0.60, gauntlets((-12, 0, 0), 'tuck', (-0.28, 0.92, -0.25), (0.28, 0.92, -0.25), look=(0, 0.1, -1), hop=0.35), 'out'),
    (0.66, gauntlets((48, 0, 0), WIDE_LOW, (-0.26, -0.82, -0.51), (0.26, -0.82, -0.51), look=DOWN), 'in2'),
    (0.82, gauntlets((51, 0, 0), WIDE_LOW, (-0.26, -0.86, -0.44), (0.26, -0.86, -0.44), look=DOWN), 'out'),
    (1.15, wt.F_IDLE, 'inout'),
], hit=0.66, marks=[('Throw', 0.25), ('Reel', 0.32), ('Hit', 0.66)]),
    (0.19, 'WIND UP'), (0.25, 'THROW'), (0.38, 'REELED IN'), (0.60, 'FISTS UP'), (0.66, 'SLAM'), (0.82, 'SLAM')))

# NO QUARTER - a quick gather, then he bursts up: chest out, sword thrust at
# the sky, the free fist clenched, while his armour cracks gold; the sword
# snaps down to point straight at the enemy, the fist raised (0.6: the
# meteor's called down) - and he braces, crouched, sword forward, as it hits
# (1.15)
BRACE = ((-0.40, -1, -0.45), (0.40, -1, 0.42))
ABILITIES['NoQuarter'] = ('Sword', shown(Poses('NoQuarterAbility', [
    (0.00, S_IDLE, 'linear'),
    (0.08, key((22, 0, -22), 'crouch', blade((0.35, -0.90, -0.20), (0.12, -0.70, -0.70)), (0.35, -0.55, -0.76),
               look=DOWN), 'out'),
    (0.26, key((-18, 0, -4), 'wide', blade((0.12, 0.96, -0.25), (0.0, 1.0, 0.10)), (-0.42, -0.84, 0.34),
               look=(0, 0.8, -1), hop=0.1), 'out'),
    (0.34, key((-15, 0, -2), 'wide', blade((0.10, 0.96, -0.26), (0.03, 1.0, 0.08)), (-0.40, -0.85, 0.36),
               look=(0, 0.75, -1), hop=0.06), 'inout'),
    (0.42, key((-19, 0, -6), 'wide', blade((0.13, 0.95, -0.24), (-0.02, 1.0, 0.12)), (-0.44, -0.83, 0.33),
               look=(0, 0.8, -1), hop=0.09), 'inout'),
    (0.50, key((-16, 0, -8), 'wide', blade((0.14, 0.94, -0.30), (0.0, 1.0, 0.05)), (-0.40, -0.80, 0.40),
               look=(0, 0.7, -1), hop=0.05), 'inout'),
    (0.60, key((8, 0, -34), 'lunge', blade((0.05, -0.10, -1.0), (0.0, 0.14, -1.0)), (-0.58, 0.76, 0.28),
               look=AHEAD), 'out'),
    (0.95, key((11, 0, -36), 'lunge', blade((0.05, -0.12, -1.0), (0.0, 0.12, -1.0)), (-0.60, 0.72, 0.32),
               look=AHEAD), 'hold'),
    (1.01, key((10, 0, -30), 'lunge', blade((0.10, -0.30, -0.95), (0.02, 0.18, -1.0)), (-0.62, 0.15, 0.55),
               look=AHEAD, hop=0.03), 'inout'),
    (1.08, key((10, 0, -24), BRACE, blade((0.20, -0.55, -0.80), (0.03, 0.25, -1.0)), (-0.45, -0.60, 0.65),
               look=AHEAD, hop=0.06), 'inout'),
    (1.15, key((20, 0, -20), BRACE, blade((0.22, -0.70, -0.68), (0.04, 0.12, -1.0)), (-0.42, -0.80, 0.45),
               look=AHEAD), 'in2'),
    (1.20, S_IDLE, 'out'),
], hit=1.15, marks=[('Meteor', 0.60), ('Hit', 1.15)]),
    (0.08, 'GATHER'), (0.26, 'POWER UP'), (0.42, 'CRACKING GOLD'), (0.60, 'METEOR CALLED'), (1.08, 'BRACING'),
    (1.15, 'IMPACT')))


# ======================================================================
# SPEEDWAY
# ======================================================================
# TYRE SCYTHE - Burnout: the scythe dropped low in front, the free fist
# twisting a throttle, and the body bounces twice like a revving engine
# (0.1, the rev: knees pumping, shoulders shaking) - then leans forward,
# ready to run
def burn(root, legs, lfwd, hop=0.0, larm=(0.20, -0.20, -1.0), look=AHEAD):
    """the scythe low in front of the right hip, the blade flat on the ground
    ahead, the left fist on its throttle (lfwd: its twist)"""
    return key(root, legs, scythe(root, (0.85, -0.60, -0.60), (0.15, -0.50, -0.85), (1.0, 0.0, 0.15)), larm,
               look=look, hop=hop, lfwd=lfwd)


REVVED = (-0.90, 0.40, 0.0)  # (the throttle twisted)
THROTTLE = (0.0, 1.0, 0.2)
CROUCH_WIDE = ((-0.62, -1, -0.35), (0.62, -1, 0.30))
ABILITIES['TyreScythe'] = ('Scythe', shown(Poses('TyreScytheAbility', [
    (0.00, wt.S_IDLE, 'linear'),
    (0.06, burn((24, 8, -8), CROUCH_WIDE, THROTTLE, look=(0, -0.25, -1)), 'out2'),
    (0.10, burn((0, -8, -12), 'tuck', REVVED, hop=0.34, look=(0, 0.12, -1)), 'out'),
    (0.16, burn((25, 7, -8), CROUCH_WIDE, THROTTLE, look=(0, -0.25, -1)), 'inout'),
    (0.22, burn((1, -7, -12), 'tuck', REVVED, hop=0.3, look=(0, 0.12, -1)), 'out'),
    (0.32, burn((28, 0, -6), 'lunge', (0.3, 0.0, -1.0), larm=(-0.20, -0.60, 0.75)), 'inout'),
    (0.37, burn((30, 0, -6), 'lunge', (0.3, 0.0, -1.0), larm=(-0.22, -0.58, 0.76)), 'hold'),
    (0.50, wt.S_IDLE, 'inout'),
], hit=0.10, marks=[('Rev', 0.10), ('Rev', 0.22)]), (0.06, 'DOWN'), (0.10, 'REV'), (0.16, 'DOWN'), (0.22, 'REV'),
    (0.32, 'READY'), (0.44, 'BACK UP')))


# NITRO KATANA - Nitro: snap into a rocket's lean, far forward, both arms
# swept back and the blade trailing low behind like an exhaust - a sharp
# jolt as the flame bursts out (0.08), hold it, and back to the guard
def rocket(root, legs, d, b, left, hop=0.0):
    """leaning into the boost: the katana in the right hand, trailing"""
    return key(root, legs, blade(d, b), left, look=(0, 0.15, -1) if root[0] > 30 else AHEAD, hop=hop)


SPRINT = ((-0.25, -1, -0.55), (0.30, -1, 0.80))
ABILITIES['NitroKatana'] = ('Katana', shown(Poses('NitroKatanaAbility', [
    (0.00, wt.K_IDLE, 'linear'),
    (0.03, rocket((20, 0, -8), K_FEET, (0.80, -0.55, -0.20), (0.95, 0.15, 0.25), (-0.60, -0.75, 0.25)), 'linear'),
    (0.06, rocket((40, 0, -6), SPRINT, (0.30, -0.70, 0.65), (0.12, -0.08, 1.0), (-0.30, -0.62, 0.72)), 'out'),
    (0.08, rocket((54, 0, -6), SPRINT, (0.30, -0.45, 0.84), (0.10, 0.18, 1.0), (-0.30, -0.36, 0.88), hop=0.12), 'snap'),
    (0.14, rocket((42, 0, -6), SPRINT, (0.30, -0.66, 0.69), (0.12, -0.04, 1.0), (-0.30, -0.58, 0.76), hop=0.02), 'out'),
    (0.34, rocket((43, 0, -6), SPRINT, (0.30, -0.64, 0.71), (0.12, -0.02, 1.0), (-0.30, -0.56, 0.77)), 'hold'),
    (0.42, rocket((22, 0, -8), K_FEET, (0.80, -0.55, -0.20), (0.95, 0.15, 0.25), (-0.55, -0.80, 0.20)), 'inout'),
    (0.50, wt.K_IDLE, 'inout'),
], hit=0.08, marks=[('Boost', 0.08)]), (0.0, 'STANCE'), (0.06, 'ROCKET LEAN'), (0.08, 'BOOST'), (0.14, 'HOLD'),
    (0.42, 'BACK'), (0.50, 'STANCE')))

# PISTON PUNCHERS - Piston Dash: cock the piston - right fist back at the
# hip, left out front, a small crouch; dash in leaning low (0.14 to 0.38),
# then a huge straight right, fully extended (0.4, the BOOM)
PUMP = ((-0.30, -1, -0.40), (0.32, -1, 0.32))
DASH = ((-0.25, -1, -0.55), (0.30, -1, 0.70))
DEEP = ((-0.30, -1, -0.70), (0.34, -1, 0.62))
ABILITIES['PistonPunchers'] = ('Fists', shown(Poses('PistonPunchersAbility', [
    (0.00, wt.F_IDLE, 'linear'),
    (0.08, gauntlets((14, 0, -32), PUMP, (0.30, -0.70, 0.65), (0.20, 0.05, -1.0)), 'out'),
    (0.14, gauntlets((16, 0, -34), PUMP, (0.30, -0.65, 0.70), (0.20, 0.06, -1.0)), 'inout'),
    (0.24, gauntlets((30, 0, -32), DASH, (0.30, -0.60, 0.75), (0.20, 0.0, -1.0), hop=0.1), 'out'),
    (0.36, gauntlets((34, 0, -38), DASH, (0.36, -0.48, 0.80), (0.22, 0.02, -1.0), hop=0.12), 'inout'),
    (0.40, gauntlets((28, 0, 30), DEEP, (-0.05, 0.12, -1.0), (0.30, -0.55, 0.78)), 'in2'),
    (0.48, gauntlets((31, 0, 34), DEEP, (-0.08, 0.08, -1.0), (0.30, -0.60, 0.74)), 'out'),
    (0.58, gauntlets((20, 0, 20), DEEP, (-0.10, 0.02, -1.0), (0.32, -0.40, 0.86)), 'inout'),
    (0.75, wt.F_IDLE, 'inout'),
], hit=0.40, marks=[('Dash', 0.14), ('Hit', 0.40)]), (0.08, 'PUMP'), (0.14, 'COCKED'), (0.24, 'DASH'),
    (0.36, 'DASH'), (0.40, 'BOOM'), (0.48, 'THROUGH')))


# PIT STOP SABRE - Skid Spin: crouched low, a full turn to the left with
# the sabre out flat at the waist (0.05 to 0.45; it sweeps past the enemy
# at 0.2, the tyres fly at 0.3), skidding round into a low drift, the free
# hand brushing the ground
def skid(root, legs, d, b, e, left, yaw, look=AHEAD):
    return key(root, legs, (unit(d), unit(b), unit(e)), left, look=look, yaw=yaw)


SPIN_ARM = dict(d=(0.92, -0.35, -0.15), b=(0.75, -0.12, -0.65), e=(-0.65, 0.0, -0.75))  # (out flat at the waist)
SPUN = ((-0.62, -1, -0.30), (0.62, -1, 0.30))  # (low, the feet wide as it spins)
DRIFT = level((40, 34, 0), ((-0.60, -0.55, -0.45), (0.45, -0.55, 0.72)))  # (skidding: split low, both feet down)
ABILITIES['PitStopSabre'] = ('Sword', shown(Poses('PitStopSabreAbility', [
    (0.00, S_IDLE, 'linear'),
    (0.05, skid((22, 0, -16), SPUN, (0.55, -0.80, -0.20), (0.60, -0.15, -0.78), (0.0, 1.0, 0.0), (-0.55, -0.75, -0.35),
                yaw=-25), 'out'),
    (0.12, skid((20, 8, -6), SPUN, left=(-0.90, -0.35, 0.25), yaw=0, **SPIN_ARM), 'in'),
    (0.20, skid((20, 12, 0), SPUN, left=(-0.90, -0.35, 0.25), yaw=53, **SPIN_ARM), 'linear'),
    (0.30, skid((20, 12, 0), SPUN, left=(-0.90, -0.35, 0.25), yaw=165, **SPIN_ARM), 'linear'),
    (0.45, skid((26, 16, 0), SPUN, left=(-0.70, -0.70, 0.15), yaw=320, **SPIN_ARM), 'linear'),
    (0.55, skid((40, 34, 0), DRIFT, (0.90, -0.35, 0.20), (0.92, -0.05, -0.30), (-0.30, 0.0, -0.95), (-0.35, -0.90, -0.25),
                yaw=332, look=(-0.50, -0.05, -0.87)), 'out'),
    (0.75, skid((41, 35, 2), DRIFT, (0.90, -0.35, 0.22), (0.92, -0.05, -0.28), (-0.28, 0.0, -0.95), (-0.34, -0.90, -0.26),
                yaw=334, look=(-0.50, -0.05, -0.87)), 'hold'),
    (1.00, dict(S_IDLE, yaw=360), 'inout'),
], hit=0.20, marks=[('Cut', 0.12), ('Hit', 0.20), ('Tyres', 0.30), ('Through', 0.45)]), (0.05, 'CROUCH'),
    (0.20, 'SPIN HIT'), (0.30, 'TYRES'), (0.45, 'ROUND'), (0.55, 'DRIFT'), (0.75, 'DRIFT')))

# WHEELIE WRECKER - Wheelie: riding the flaming wheel - the hammer across in
# front like handlebars, leaning right back, knees bent, bouncing (0 to
# 0.95); haul it up high (0.8) and SLAM it down in front (1.02)
RIDE = ((-0.30, -1, -0.62), (0.30, -1, -0.42))  # (knees bent: the feet out ahead, the weight back)


def ride(lean, hop):
    """on the wheel: the hammer held across in front like handlebars, its
    head out to the right"""
    root = (lean, 0, -4)
    return key(root, RIDE, hands(root, (0.30, -0.60, -0.95), (1.0, 0.10, -0.12), (0.0, 0.0, -1.0)), look=(0, 0.15, -1),
               hop=hop)


ABILITIES['WheelieWrecker'] = ('Hammer', shown(Poses('WheelieWreckerAbility', [
    (0.00, dict(wt.H_IDLE, grip=0.0), 'linear'),
    (0.08, ride(-20, 0.06), 'inout'),
    (0.20, ride(-28, 0.18), 'inout'),
    (0.32, ride(-23, 0.04), 'inout'),
    (0.44, ride(-29, 0.18), 'inout'),
    (0.56, ride(-23, 0.04), 'inout'),
    (0.68, ride(-28, 0.16), 'inout'),
    (0.80, hammer((-18, 0, -4), 'square', (0.1, 1.10, -1.05), (0.0, 0.90, 0.42), look=(0, 0.3, -1), hop=0.12), 'inout'),
    (0.94, hammer((-22, 0, -4), 'square', (0.1, 1.40, -0.95), (0.03, 0.62, 0.78), look=(0, 0.35, -1), hop=0.2), 'out'),
    (0.985, hammer((8, 0, -4), 'lunge', (0.1, 0.60, -1.25), (0.0, 0.80, -0.60)), 'in'),
    (1.02, hammer((38, 0, -4), DIG_FEET, (0.1, -0.80, -0.75), (-0.05, -0.62, -0.78), look=DOWN), 'linear'),
    (1.12, hammer((40, 0, -4), DIG_FEET, (0.1, -0.85, -0.70), (-0.05, -0.68, -0.73), look=DOWN), 'out'),
    (1.35, dict(wt.H_IDLE, grip=0.0), 'inout'),
], two=(-1.0, -0.3), hit=1.02, marks=[('Hit', 0.50), ('Hit', 0.86), ('Hit', 1.02)]), (0.08, 'MOUNT'), (0.44, 'WHEELIE'),
    (0.68, 'WHEELIE'), (0.80, 'HAUL UP'), (0.94, 'OVERHEAD'), (1.02, 'SLAM')))

# VICTORY LAP - GO: both daggers flung up in a V over your head (0 to 0.2),
# then down into a sprinter's crouch and off (0.3 to 0.6), ready to run
BLOCKS = level((54, 0, -2), ((-0.20, -0.62, -0.72), (0.30, -0.55, 0.82)))  # (down in the blocks)
DRIVE = ((-0.25, -1, -0.60), (0.30, -1, 0.55))
ABILITIES['VictoryLap'] = ('Daggers', shown(Poses('VictoryLapAbility', [
    (0.00, wt.D_IDLE, 'linear'),
    (0.08, key((-14, 0, 0), 'square', (unit((0.50, 0.85, -0.15)), unit((0.35, 0.93, 0.10)), (0.93, -0.35, 0.0)),
               (-0.50, 0.85, -0.15), look=(0, 0.5, -1), hop=0.15), 'out'),
    (0.18, key((-16, 0, 0), 'square', (unit((0.46, 0.88, -0.12)), unit((0.32, 0.94, 0.12)), (0.94, -0.32, 0.0)),
               (-0.46, 0.88, -0.12), look=(0, 0.55, -1), hop=0.1), 'inout'),
    (0.30, key((54, 0, -2), BLOCKS, (unit((0.10, -0.95, -0.30)), unit((0.05, -0.30, -1.0)), (0.0, 1.0, 0.0)),
               (-0.10, -0.85, -0.52), look=(0, 0.3, -1)), 'inout'),
    (0.40, key((30, 0, 6), DRIVE, (unit((0.10, 0.10, -1.0)), unit((0.05, 0.50, -0.85)), (0.0, 0.85, 0.5)),
               (-0.30, -0.60, 0.75), look=AHEAD, hop=0.1), 'out'),
    (0.50, key((22, 0, 0), DRIVE, (unit((0.12, -0.20, -1.0)), unit((0.05, 0.30, -1.0)), (0.0, 1.0, 0.3)),
               (-0.25, -0.70, 0.40), look=AHEAD), 'inout'),
    (0.60, wt.D_IDLE, 'inout'),
], hit=0.0, marks=[('Go', 0.0)]), (0.0, 'STANCE'), (0.08, 'GO: THE V'), (0.18, 'V'), (0.30, 'CROUCH'), (0.40, 'LAUNCH'),
    (0.50, 'OFF')))


# which pack each weapon is from (the preview shows a pack at a time)
PACK = {
    'GooGloves': 'slime', 'Jellyblade': 'slime', 'GelatinHammer': 'slime',
    'OozeDaggers': 'slime', 'AcidScythe': 'slime', 'GelatinousEdge': 'slime',
    'ShovelHammer': 'knight', 'RelicDaggers': 'knight', 'SpadeScythe': 'knight',
    'HonourBlade': 'knight', 'AnchorFists': 'knight', 'NoQuarter': 'knight',
    'TyreScythe': 'speedway', 'NitroKatana': 'speedway', 'PistonPunchers': 'speedway',
    'PitStopSabre': 'speedway', 'WheelieWrecker': 'speedway', 'VictoryLap': 'speedway',
}


# ----------------------------------------------------------------------
# out: one .rbxmx per ability (a KeyframeSequence, 30 keyframes a second)
# ----------------------------------------------------------------------
def export():
    import export_rbxmx as ex
    ex.FPS = 30
    out = os.path.join(HERE, 'abilities')
    os.makedirs(out, exist_ok=True)
    head = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    for wid, (kind, anim) in ABILITIES.items():
        if kind == 'Fists':
            ex.NO_HANDLE.add(anim.name)  # (the gauntlets ride on the fists as the game holds them)
        if getattr(anim, 'hit', None) is not None:
            marks = [('Hit', anim.hit)]
            if getattr(anim, 'trail', None):
                marks = [('Cut', anim.trail[0]), ('Hit', anim.hit), ('Through', anim.trail[1])]
            ex.MARKERS[anim.name] = marks
        if hasattr(anim, 'marks'):  # (several big moments: each one a marker, so a keyframe lands right on it)
            ex.MARKERS[anim.name] = sorted(anim.marks, key=lambda m: m[1])
        length = anim.length
        frames = length * ex.FPS
        if PACK.get(wid) != 'slime' and abs(frames - round(frames)) > 1e-6:
            # (a Time that isn't a whole number of frames: a keyframe right on
            # the end and none after it, so it lasts exactly the move's Time -
            # the Slime pack's files are kept exactly as they were made)
            ex.MARKERS[anim.name] = ex.MARKERS.get(anim.name, []) + [('End', length)]
            anim.length = math.floor(frames) / ex.FPS
        path = os.path.join(out, wid + '.rbxmx')
        try:
            with open(path, 'w') as f:
                f.write(head + '\n' + ex.sequence_xml(anim, 1) + '\n</roblox>\n')
        finally:
            anim.length = length
        print('saved', os.path.relpath(path, os.path.join(HERE, '..', '..')), '%.2f s' % anim.length,
              os.path.getsize(path) // 1024, 'KB')


def sword_pieces(pv):
    """the sword isn't in weapon_pieces.txt: WeaponFX's blocky one, by hand"""
    import r6
    if 'Sword' not in pv.PIECES:
        I = np.eye(3).flatten()
        blocks = [('Handle', (0.35, 0.35, 0.9), (115, 62, 57), (0, 0, 0)), ('Pommel', (0.48, 0.48, 0.48), (254, 174, 52), (0, 0, 0.65)),
                  ('Guard', (1.5, 0.36, 0.36), (254, 174, 52), (0, 0, -0.62)), ('Blade', (0.3, 0.8, 4), (192, 203, 220), (0, 0, -2.8)),
                  ('Edge', (0.32, 0.14, 3.8), (200, 240, 255), (0, 0.34, -2.8)), ('Tip', (0.3, 0.5, 0.45), (192, 203, 220), (0, 0.1, -5.02))]
        pv.PIECES['Sword'] = {'main': [(n, sz, c, r6.cf(p[0], p[1], p[2], list(I))) for n, sz, c, p in blocks], 'off': []}


# ----------------------------------------------------------------------
# a preview: each ability at full speed then half speed, and a sheet of
# its key moments (the weapons as the blocky stand-ins)
# ----------------------------------------------------------------------
def preview(pack='slime'):
    import imageio_ffmpeg
    from PIL import Image, ImageDraw, ImageFont
    import preview_types as pv
    sword_pieces(pv)
    docs = os.path.join(HERE, '..', '..', 'Docs', 'animations')
    os.makedirs(docs, exist_ok=True)
    size = 460
    W, H = size * 2, size + 60
    path = os.path.join(docs, pack + '_abilities.mp4')
    writer = imageio_ffmpeg.write_frames(path, (W, H), fps=30, quality=None, codec='libx264', macro_block_size=1,
                                         output_params=['-crf', '20', '-preset', 'medium', '-movflags', '+faststart'])
    writer.send(None)
    font = ImageFont.truetype(pv.BOLD, 24)
    sheet_rows = []
    for wid, (kind, anim) in ABILITIES.items():
        if PACK.get(wid) != pack:
            continue
        for speed, label in ((1.0, 'FULL SPEED'), (0.4, 'SLOW')):
            n = int((anim.length + 0.25) / speed * 30)
            for i in range(n):
                t = min(anim.length, i / 30 * speed)
                polys, _ = pv.figure(kind, anim.at(t))
                front = pv.render(polys, -30, 8, size)
                side = pv.render(polys, 90, 4, size)
                frame = Image.new('RGB', (W, H), (24, 20, 37))
                frame.paste(front, (0, 60))
                frame.paste(side, (size, 60))
                ImageDraw.Draw(frame).text((W // 2, 30), '%s - %s  %.2fs' % (wid.upper(), label, t), font=font,
                                           fill=(254, 231, 97), anchor='mm')
                writer.send(np.asarray(frame).tobytes())
        # its key moments (the ones it names, or its keys)
        hit = getattr(anim, 'hit', None)
        if hasattr(anim, 'show'):
            moments = [(m, '%.2fs %s' % (m, what)) for m, what in anim.show]
        else:
            moments = [0.0]
            keys = [k[0] for k in anim.keys]
            moments += [k for k in keys if 0 < k < anim.length]
            if hit is not None and all(abs(hit - m) > 0.01 for m in moments):
                moments.append(hit)
            moments = [(m, '%.2fs%s' % (m, ' HIT' if hit is not None and abs(m - hit) < 0.01 else ''))
                       for m in sorted(set(round(m, 3) for m in moments))[:6]]
        cells = []
        for m, label in moments:
            polys, _ = pv.figure(kind, anim.at(m))
            views = Image.new('RGB', (220, 440), (24, 20, 37))
            views.paste(pv.render(polys, -30, 8, 220), (0, 0))
            views.paste(pv.render(polys, 90, 4, 220), (0, 220))
            cells.append((label, views))
        sheet_rows.append((wid, cells))
    if not sheet_rows:
        raise SystemExit('no abilities in the pack %r (%s)' % (pack, ', '.join(sorted(set(PACK.values())))))
    writer.close()
    print('saved', os.path.relpath(path, os.path.join(HERE, '..', '..')))
    cols = max(len(c) for _, c in sheet_rows)
    img = Image.new('RGB', (cols * 226 + 180, len(sheet_rows) * 470 + 20), (24, 20, 37))
    d = ImageDraw.Draw(img)
    small = ImageFont.truetype(pv.BOLD, 14)
    for r, (wid, cells) in enumerate(sheet_rows):
        y = 10 + r * 470
        d.text((10, y + 110), wid, font=ImageFont.truetype(pv.BOLD, 16), fill=(255, 255, 255))
        d.text((10, y + 140), '(top: front\n bottom: side,\n facing right)', font=ImageFont.truetype(pv.BOLD, 12), fill=(150, 155, 180))
        for c, (label, im) in enumerate(cells):
            x = 170 + c * 226
            img.paste(im, (x, y + 20))
            d.text((x + 110, y + 8), label, font=small, fill=(200, 205, 225), anchor='mm')
    spath = os.path.join(docs, pack + '_abilities.png')
    img.save(spath)
    print('saved', os.path.relpath(spath, os.path.join(HERE, '..', '..')))


if __name__ == '__main__':
    if 'preview' in sys.argv:
        rest = sys.argv[sys.argv.index('preview') + 1:]
        preview(rest[0].lower() if rest else 'slime')
    else:
        export()
