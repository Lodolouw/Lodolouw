"""The Roblox R6 character, exactly: its parts, its Motor6D joints (C0, C1)
and what a pose does to them - in Roblox's own coordinates (Y up, the body
facing -Z), so a pose here is the very Motor6D.Transform an uploaded
animation sets.

    Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()

A pose is written the way ReplicatedStorage/WeaponFX.lua writes them: each
joint turned by CFrame.Angles(x, y, z) in degrees (its Transform):
  Root   the whole body (HumanoidRootPart -> Torso): x leans it forward,
         z turns it (+ = the chest turns left); `lift` raises it (studs)
  RS/LS  the right / left arm at the shoulder: RS z swings the right arm
         forward and up, y sweeps it across the body (+ = further left),
         x (-) lifts it out to the side; LS is the mirror (- z is forward)
  RH/LH  the legs at the hips: RH z + swings the right leg forward, LH z -
         the left one
  Neck   the head: x + looks down, z + turns it left
  Grip   the sword in the right hand (a Motor6D "Grip", Right Arm -> Handle,
         C0 = 1 stud down the arm): { tilt, roll } - 0 tilt, the blade points
         straight out the front of the fist; -90, in line with the arm
"""
import math
import numpy as np


def cf(x=0.0, y=0.0, z=0.0, r=None):
    """a CFrame as a 4 x 4 matrix; r = the 9 rotation numbers, row by row
    (CFrame.new(x, y, z, R00, R01, R02, R10, ...))"""
    m = np.eye(4)
    if r is not None:
        m[:3, :3] = np.array(r, dtype=float).reshape(3, 3)
    m[:3, 3] = (x, y, z)
    return m


def angles(x, y, z):
    """CFrame.Angles(x, y, z) (radians): X, then Y, then Z, in the frame's own axes"""
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    m = np.eye(4)
    m[:3, :3] = rx @ ry @ rz
    return m


def inv(m):
    r = m[:3, :3].T
    out = np.eye(4)
    out[:3, :3] = r
    out[:3, 3] = -r @ m[:3, 3]
    return out


# the parts: size (studs) and colour (the classic blocky look)
PARTS = {
    'HumanoidRootPart': ((2, 2, 1), None),
    'Torso': ((2, 2, 1), (40, 90, 200)),
    'Head': ((2, 1, 1), (245, 205, 48)),
    'Right Arm': ((1, 2, 1), (245, 205, 48)),
    'Left Arm': ((1, 2, 1), (245, 205, 48)),
    'Right Leg': ((1, 2, 1), (75, 151, 75)),
    'Left Leg': ((1, 2, 1), (75, 151, 75)),
}

# the joints: name -> (pose key, Part0, Part1, C0, C1) - Roblox's own R6 numbers
_R = (-1, 0, 0, 0, 0, 1, 0, 1, 0)
JOINTS = {
    'RootJoint': ('Root', 'HumanoidRootPart', 'Torso', cf(0, 0, 0, _R), cf(0, 0, 0, _R)),
    'Neck': ('Neck', 'Torso', 'Head', cf(0, 1, 0, _R), cf(0, -0.5, 0, _R)),
    'Right Shoulder': ('RS', 'Torso', 'Right Arm', cf(1, 0.5, 0, (0, 0, 1, 0, 1, 0, -1, 0, 0)), cf(-0.5, 0.5, 0, (0, 0, 1, 0, 1, 0, -1, 0, 0))),
    'Left Shoulder': ('LS', 'Torso', 'Left Arm', cf(-1, 0.5, 0, (0, 0, -1, 0, 1, 0, 1, 0, 0)), cf(0.5, 0.5, 0, (0, 0, -1, 0, 1, 0, 1, 0, 0))),
    'Right Hip': ('RH', 'Torso', 'Right Leg', cf(1, -1, 0, (0, 0, 1, 0, 1, 0, -1, 0, 0)), cf(0.5, 1, 0, (0, 0, 1, 0, 1, 0, -1, 0, 0))),
    'Left Hip': ('LH', 'Torso', 'Left Leg', cf(-1, -1, 0, (0, 0, -1, 0, 1, 0, 1, 0, 0)), cf(-0.5, 1, 0, (0, 0, -1, 0, 1, 0, 1, 0, 0))),
    'Grip': ('Grip', 'Right Arm', 'Handle', cf(0, -1, 0), cf()),
}
ORDER = ['RootJoint', 'Neck', 'Right Shoulder', 'Left Shoulder', 'Right Hip', 'Left Hip', 'Grip']
GROUND = -3.0  # the floor, below the HumanoidRootPart's middle (the feet at rest)


def transforms(pose):
    """the Motor6D.Transform of every joint for a pose (see the top)"""
    rad = math.radians
    out = {}
    for name in ORDER:
        key = JOINTS[name][0]
        a = pose.get(key, (0, 0, 0))
        if key == 'Grip':
            tilt, roll = a[0], (a[1] if len(a) > 1 else 0)
            out[name] = angles(rad(tilt), 0, 0) @ angles(0, 0, rad(roll))
        elif key == 'Root':
            # (the RootJoint's frame has Z pointing up: a lift goes along it)
            out[name] = cf(0, 0, pose.get('lift', 0.0)) @ angles(rad(a[0]), rad(a[1]), rad(a[2]))
        else:
            out[name] = angles(rad(a[0]), rad(a[1]), rad(a[2]))
    return out


def solve(transforms_by_joint, hrp=None):
    """every part's CFrame (world) from the joints' Transforms, the
    HumanoidRootPart at `hrp` (default: standing at the origin, feet on y = 0)"""
    if hrp is None:
        hrp = cf(0, -GROUND, 0)
    world = {'HumanoidRootPart': hrp}
    for name in ORDER:
        key, p0, p1, c0, c1 = JOINTS[name]
        world[p1] = world[p0] @ c0 @ transforms_by_joint[name] @ inv(c1)
    return world


def feet_low(world):
    """the lowest point of either foot (the bottom corners of the legs)"""
    low = math.inf
    for leg in ('Right Leg', 'Left Leg'):
        m = world[leg]
        for sx in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                p = m @ np.array([sx, -1.0, sz, 1.0])
                low = min(low, p[1])
    return low
