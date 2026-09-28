"""The sword animations for the R6 character: key poses (r6.py explains how a
pose is written), when each one is hit, and how the body gets from one to
the next - baked into a pose every frame, with the feet kept planted.

Timed to the game's swings (Config.Weapons.Types.Sword): swings 1 and 2
land their hit 0.2 s after the press (Lock 0.5 x Contact 0.4), the
finisher 0.34 s after (Lock 0.75 x Contact 0.45) - the moment the server
cuts - so the blade must be at its fastest, right in front, exactly then.
"""
import math
import numpy as np

import r6


# ----------------------------------------------------------------------
# easing: how a move gets from one key pose to the next
# ----------------------------------------------------------------------
def ease(kind, u):
    u = min(1.0, max(0.0, u))
    if kind == 'linear':
        return u
    if kind == 'out':  # fast, then slowing into the pose (a snap that settles)
        return 1 - (1 - u) ** 3
    if kind == 'in':  # slow, then faster and faster (the strike: fastest at the end)
        return u ** 3
    if kind == 'inout':
        return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2
    if kind == 'hold':  # barely moves (a held moment, drifting)
        return 0.25 * u
    if kind == 'snap':  # almost all of it in the first third (a whip)
        return 1 - (1 - u) ** 6
    if kind == 'in2':  # speeding up the whole way (a strike: fastest as it lands)
        return u * u
    if kind == 'out2':  # fast, then slowing (a follow-through carrying on)
        return 1 - (1 - u) * (1 - u)
    raise ValueError(kind)


KEYS = ('Root', 'RS', 'LS', 'RH', 'LH', 'Neck', 'Grip')


def mix(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k), b.get(k)
        if va is None:
            va = vb
        if vb is None:
            vb = va
        if isinstance(va, (int, float)):
            out[k] = va + (vb - va) * t
        else:
            out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out


class Anim:
    """keys: [(time, pose, easing into it)], looped or not"""

    def __init__(self, name, keys, loop=False, priority='Action'):
        self.name, self.keys, self.loop, self.priority = name, keys, loop, priority
        self.length = keys[-1][0]

    def at(self, t):
        keys = self.keys
        if self.loop:
            t = t % self.length
        if t <= keys[0][0]:
            return dict(keys[0][1])
        for (t0, p0, _), (t1, p1, e) in zip(keys, keys[1:]):
            if t <= t1:
                u = (t - t0) / max(1e-9, t1 - t0)
                return mix(p0, p1, ease(e, u))
        return dict(keys[-1][1])


def plant(tr):
    """the legs keep the angles they were given relative to the ground, not the
    torso: however the body leans or turns, it's taken back off at the hips"""
    _, _, _, c0r, c1r = r6.JOINTS['RootJoint']
    torso = c0r @ tr['RootJoint'] @ r6.inv(c1r)
    rt = torso[:3, :3]
    for hip in ('Right Hip', 'Left Hip'):
        _, _, _, c0, c1 = r6.JOINTS[hip]
        want = c0[:3, :3] @ tr[hip][:3, :3] @ c1[:3, :3].T
        m = np.eye(4)
        m[:3, :3] = c0[:3, :3].T @ rt.T @ want @ c1[:3, :3]
        tr[hip] = m
    return tr


def pose_transforms(pose, planted=True):
    """a pose's Motor6D.Transforms, legs planted and the body raised or lowered
    so the lowest foot is on the floor (plus any `hop`)"""
    p = dict(pose)
    hop = p.pop('hop', 0.0)
    p['lift'] = 0.0
    tr = r6.transforms(p)
    if planted:
        tr = plant(tr)
    low = r6.feet_low(r6.solve(tr))
    p['lift'] = -low + hop  # (the floor is y = 0)
    tr2 = r6.transforms(p)
    for hip in ('Right Hip', 'Left Hip'):
        tr2[hip] = tr[hip]
    return tr2


def bake(anim, fps=60):
    n = int(round(anim.length * fps))
    frames = []
    for i in range(n + (0 if anim.loop else 1)):
        t = i / fps
        frames.append((t, pose_transforms(anim.at(t))))
    return frames


# ----------------------------------------------------------------------
# THE OLD POSES (ReplicatedStorage/WeaponFX.lua, as the game has them now),
# to look at side by side with the new ones
# ----------------------------------------------------------------------
OLD_STANCE = {'Root': (4, 0, -12), 'RS': (-10, -5, 25), 'LS': (-8, 10, -12), 'RH': (0, 0, -6), 'LH': (0, 0, -12),
              'Neck': (0, 0, 10), 'Grip': (-35, -10)}
OLD = [
    {'coil': {'Root': (-8, 0, -45), 'RS': (-45, -60, 140), 'LS': (-30, 0, -60), 'RH': (0, 0, -20), 'LH': (0, 0, -25), 'Neck': (0, 0, 35), 'Grip': (-115, 0)},
     'cut': {'Root': (15, 0, 10), 'RS': (0, 15, 95), 'LS': (-15, 0, 40), 'RH': (0, 0, -35), 'LH': (0, 0, -45), 'Neck': (0, 0, -5), 'Grip': (-75, 0)},
     'follow': {'Root': (25, 0, 45), 'RS': (10, 60, 55), 'LS': (-20, 0, 60), 'RH': (0, 0, -35), 'LH': (0, 0, -45), 'Neck': (0, 0, -35), 'Grip': (-75, 20)}},
    {'coil': {'Root': (15, 0, 40), 'RS': (15, 70, 45), 'LS': (-15, 0, 30), 'RH': (0, 0, 5), 'LH': (0, 0, -20), 'Neck': (0, 0, -35), 'Grip': (-70, 30)},
     'cut': {'Root': (10, 0, -5), 'RS': (-10, -10, 105), 'LS': (-20, 0, -40), 'RH': (0, 0, 35), 'LH': (0, 0, 25), 'Neck': (0, 0, 5), 'Grip': (-75, 0)},
     'follow': {'Root': (-5, 0, -50), 'RS': (-5, -20, 120), 'LS': (-25, 0, -70), 'RH': (0, 0, 35), 'LH': (0, 0, 25), 'Neck': (-10, 0, 40), 'Grip': (-60, -10)}},
    {'coil': {'Root': (-18, 0, -20), 'RS': (-10, 0, 200), 'LS': (15, 0, -170), 'RH': (0, 0, -10), 'LH': (0, 0, -30), 'Neck': (-20, 0, 15), 'Grip': (-60, 0), 'hop': 0.8},
     'cut': {'Root': (38, 0, 0), 'RS': (0, 5, 95), 'LS': (15, 0, -95), 'RH': (0, 0, -40), 'LH': (0, 0, -50), 'Neck': (15, 0, 0), 'Grip': (-75, 0)},
     'follow': {'Root': (32, 0, 0), 'RS': (0, 5, 78), 'LS': (10, 0, -60), 'RH': (0, 0, -40), 'LH': (0, 0, -50), 'Neck': (20, 0, 0), 'Grip': (-60, 0)}},
]


# ----------------------------------------------------------------------
# POSING BY DIRECTION (the new animations)
# ----------------------------------------------------------------------
# Instead of raw joint angles, a key pose says where things POINT, in the
# character's own space (HumanoidRootPart: x right, y up, -z forward - the
# enemy is at -z):
#   root   (lean, tilt, turn) degrees, as WeaponFX's Root: lean + forward,
#          turn + = the chest turns left
#   hop    studs off the ground (the rest of the height is worked out so the
#          lowest foot is on the floor)
#   arm    (d, b, e): the sword arm points along d (shoulder to fist), the
#          blade along b, its cutting edge faces e - solved into the right
#          shoulder and the grip (tilt, roll)
#   larm   where the left arm points
#   legs   (left, right): where each leg points, hip to foot (they don't turn
#          with the body: that's what keeps them planted)
#   look   where the head looks
# Between key poses the directions swing round in arcs (slerp), so a blade
# sweeps along a curve and never flips over.
def unit(v):
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def slerp(a, b, t):
    a, b = unit(a), unit(b)
    d = float(np.clip(a @ b, -1.0, 1.0))
    if d > 0.9995:
        return unit(a + (b - a) * t)
    if d < -0.9995:  # (opposite: go round through something perpendicular)
        p = unit(np.cross(a, [0, 1, 0]) if abs(a[1]) < 0.9 else np.cross(a, [1, 0, 0]))
        return slerp(slerp(a, p, 1.0), b, t) if t > 0.5 else slerp(a, p, t * 2)
    w = math.acos(d)
    return (math.sin((1 - t) * w) * a + math.sin(t * w) * b) / math.sin(w)


def frame_from(down, forward):
    """a part's rotation (columns X, Y, Z) with its -Y along `down` and its -Z as
    close to `forward` as it can be"""
    y = -unit(down)
    zn = unit(np.asarray(forward, float) - (np.asarray(forward, float) @ -y) * -y)
    if np.linalg.norm(zn) < 1e-6:
        zn = unit(np.cross(y, [1, 0, 0]))
    z = -zn
    x = np.cross(y, z)
    return np.column_stack([x, y, z])


def solve_arm(d, b, e):
    """the sword arm's rotation (world) and the grip's (tilt, roll) in degrees so the
    arm points along d, the blade along b and its edge faces e"""
    d, b = unit(d), unit(b)
    zn = b - (b @ d) * d
    if np.linalg.norm(zn) < 1e-4:  # (the blade straight along the arm: any twist)
        zn = np.cross(d, [1, 0, 0])
    zn = unit(zn)
    r = frame_from(d, zn)
    tilt = math.atan2(-(b @ d), b @ zn)
    xh = r[:, 0]
    yh = r @ np.array([0, math.cos(tilt), math.sin(tilt)])
    ep = np.asarray(e, float) - (np.asarray(e, float) @ b) * b
    roll = math.atan2(-(ep @ xh), ep @ yh) if np.linalg.norm(ep) > 1e-6 else 0.0
    return r, math.degrees(tilt), math.degrees(roll)


def rel(joint, parent_world_rot, child_world_rot):
    """the Motor6D.Transform (a rotation) that gives a child part this rotation"""
    _, _, _, c0, c1 = r6.JOINTS[joint]
    m = np.eye(4)
    m[:3, :3] = c0[:3, :3].T @ parent_world_rot.T @ child_world_rot @ c1[:3, :3]
    return m


def dir_transforms(p):
    """a direction pose's Motor6D.Transforms (feet on the floor)"""
    lean, tilt, turn = p.get('root', (0, 0, 0))
    tr = {}
    tr['RootJoint'] = r6.transforms({'Root': (lean, tilt, turn)})['RootJoint']
    _, _, _, c0r, c1r = r6.JOINTS['RootJoint']
    torso_rot = (c0r @ tr['RootJoint'] @ r6.inv(c1r))[:3, :3]
    hrp_rot = np.eye(3)
    # the sword arm and the grip
    d, b, e = p['arm']
    arm_rot, g_tilt, g_roll = solve_arm(d, b, e)
    tr['Right Shoulder'] = rel('Right Shoulder', torso_rot, arm_rot)
    tr['Grip'] = r6.angles(math.radians(g_tilt), 0, 0) @ r6.angles(0, 0, math.radians(g_roll))
    # the free arm (its palm-side facing forward-ish)
    tr['Left Shoulder'] = rel('Left Shoulder', torso_rot, frame_from(p['larm'], p.get('lfwd', (0.3, 0, -1))))
    # the legs, toes forward (the back foot a little out)
    left, right = p['legs']
    tr['Left Hip'] = rel('Left Hip', hrp_rot, frame_from(left, (-0.1, 0, -1)))
    tr['Right Hip'] = rel('Right Hip', hrp_rot, frame_from(right, (0.35, 0, -1)))
    # the head, looking where it's told (never twisted past what a neck can do)
    look = unit(p.get('look', (0, -0.1, -1)))
    chest = -torso_rot[:, 2]  # (where the chest faces)
    turn = math.degrees(math.acos(float(np.clip(chest @ look, -1, 1))))
    if turn > 55:  # (a neck turns only so far: past that the head goes with the chest)
        look = slerp(chest, look, 55 / turn)
    down = np.array([0.0, -1.0, 0.0])
    head_rot = frame_from(unit(down - (down @ look) * look), look)
    tr['Neck'] = rel('Neck', torso_rot, head_rot)
    # the height: the lowest foot on the floor, plus any hop
    low = r6.feet_low(r6.solve(tr))
    tr['RootJoint'] = r6.cf(0, 0, -low + p.get('hop', 0.0)) @ tr['RootJoint']
    return tr


def mix_dir(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, b.get(k)), b.get(k, a.get(k))
        if k in ('root',):
            out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
        elif isinstance(va, (int, float)):
            out[k] = va + (vb - va) * t
        elif k == 'arm':
            out[k] = tuple(slerp(x, y, t) for x, y in zip(va, vb))
        elif k == 'legs':
            out[k] = tuple(slerp(x, y, t) for x, y in zip(va, vb))
        else:
            out[k] = slerp(va, vb, t)
    return out


class DirAnim(Anim):
    def at(self, t):
        keys = self.keys
        if self.loop:
            t = t % self.length
        if t <= keys[0][0]:
            return dict(keys[0][1])
        for (t0, p0, _), (t1, p1, e) in zip(keys, keys[1:]):
            if t <= t1:
                u = (t - t0) / max(1e-9, t1 - t0)
                return mix_dir(p0, p1, ease(e, u))
        return dict(keys[-1][1])


def bake_dir(anim, fps=60):
    n = int(round(anim.length * fps))
    return [(i / fps, dir_transforms(anim.at(i / fps))) for i in range(n + (0 if anim.loop else 1))]
