# The poses of the weapon types drawn in code (gauntlets, hammer, daggers,
# scythe, katana). This spec says, for each key pose, where the hands go and
# which way the weapon points (and its edge or blade), and how it travels
# there from the pose before (`via`: the way it points halfway - over the
# top, across the front...). posesolve.py finds R6 joint angles that do it,
# checking the in-between blends too (WeaponFX blends key poses joint by
# joint, so two poses far apart in angles swing the arm the wrong way round).
# The result goes into ReplicatedStorage/WeaponFX.lua between its GENERATED
# POSES markers (and its OFFHAND grips):
#   python3 genposes.py            prints the Lua and a report
#   python3 genposes.py --apply    writes them into WeaponFX.lua
# Space: the torso's own (+x its right, +y up, -z forward; shoulders at
# (+-1, 0.5, 0), the head at y 1.5, the hips at y -1). The body's lean and turn
# (Root), the legs, the neck and hops are set by hand in `body`.
import os, re, sys, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from posesolve import solve, unit, arc, kin, pack
WEAPONFX = os.path.join(HERE, "..", "..", "..", "ReplicatedStorage", "WeaponFX.lua")

def K(**kw):
    return kw

# R: right hand; d: the weapon's direction; up: its edge (local +Y); x: a
# scythe blade's direction (local +X); via: the direction halfway from the
# pose before. L: the left hand (a point; 'stance' = as in the stance; left
# out on a two-handed weapon = on the handle); ld / lvia: the left weapon's.
TYPES = {
 'Fists': dict(grip=(-90, 0), off=(-90, 0),
  stance=K(R=(0.55,0.85,-1.4), L=(-0.5,0.75,-1.35), body=dict(Root=(8,0,-15),RH=(0,0,-8),LH=(0,0,-16),Neck=(5,0,12))),
  swings=[
   [K(R=(0.95,0.45,-1.0), L=(-0.5,0.75,-1.35), body=dict(Root=(4,0,-28))),
    K(R=(0.6,0.62,-1.7), L=(-0.6,0.7,-1.3), body=dict(Root=(12,0,22),Neck=(5,0,-5))),
    K(R=(0.6,0.58,-1.66), L=(-0.6,0.7,-1.3), body=dict(Root=(14,0,26),Neck=(5,0,-8)))],
   [K(L=(-1.9,0.6,-0.7), R=(0.6,0.8,-1.35), body=dict(Root=(6,0,28))),
    K(L=(-0.3,0.6,-1.55), R=(0.6,0.8,-1.35), body=dict(Root=(12,0,-30),Neck=(5,0,25))),
    K(L=(0.2,0.5,-1.35), R=(0.6,0.8,-1.35), body=dict(Root=(12,0,-38),Neck=(5,0,30)))],
   [K(R=(1.2,-0.7,-0.9), L=(-0.5,0.75,-1.35), body=dict(Root=(22,0,-25),RH=(0,0,-30),LH=(0,0,-35))),
    K(R=(0.6,1.9,-0.8), L=(-0.5,0.75,-1.35), body=dict(Root=(-12,0,18),Neck=(-15,0,0),Hop=(0.6,))),
    K(R=(0.6,2.0,-0.6), L=(-0.5,0.75,-1.35), body=dict(Root=(-10,0,20),Neck=(-12,0,0),Hop=(0.3,)))],
  ]),
 'Hammer': dict(two=0.9,
  stance=K(R=(0.8,-0.5,-1.3), d=(-0.55,0.8,-0.25), body=dict(Root=(6,0,-15),RH=(-6,0,-10),LH=(-6,0,-18),Neck=(0,0,12))),
  swings=[
   [K(R=(1.0,1.7,-0.3), d=(0.3,0.55,0.78), body=dict(Root=(-10,0,-45),Neck=(0,0,35))),
    K(R=(0.4,-0.2,-1.5), d=(-0.25,-0.45,-0.86), via=(0.05,0.9,-0.4), body=dict(Root=(25,0,15),RH=(0,0,-32),LH=(0,0,-42))),
    K(R=(-0.1,-0.7,-1.2), d=(-0.65,-0.65,-0.4), body=dict(Root=(32,0,42),RH=(0,0,-32),LH=(0,0,-42),Neck=(0,0,-30)))],
   [K(R=(-0.2,0.3,-1.3), d=(-0.8,0.1,0.6), body=dict(Root=(10,0,50),Neck=(0,0,-35))),
    K(R=(0.5,0.2,-1.5), d=(0.15,0.05,-1), via=(-0.95,0.1,-0.2), body=dict(Root=(12,0,-10))),
    K(R=(1.5,0.3,-0.9), d=(0.8,0.1,0.55), via=(0.95,0.1,-0.2), body=dict(Root=(5,0,-58),Neck=(-5,0,38)))],
   [K(R=(0.6,2.0,-0.2), d=(0,0.45,0.9), body=dict(Root=(-20,0,-8),Neck=(-20,0,5),Hop=(0.7,))),
    K(R=(0.5,-0.3,-1.45), d=(0,-0.55,-0.84), via=(0,0.95,-0.3), body=dict(Root=(42,0,0),RH=(0,0,-42),LH=(0,0,-52),Neck=(15,0,0))),
    K(R=(0.5,-0.4,-1.4), d=(0,-0.65,-0.76), body=dict(Root=(36,0,0),RH=(0,0,-42),LH=(0,0,-52),Neck=(20,0,0)))],
  ]),
 'Daggers': dict(offsolve=True,
  stance=K(R=(0.9,0.0,-1.35), d=(0.1,0.45,-0.89), L=(-0.9,-0.1,-1.3), ld=(-0.1,0.45,-0.89), body=dict(Root=(14,0,-6),RH=(0,0,-18),LH=(0,0,-24),Neck=(-6,0,6))),
  swings=[
   [K(R=(1.35,-0.3,-0.6), d=(0,0.15,-1), L='stance', body=dict(Root=(10,0,-25))),
    K(R=(0.55,0.35,-1.62), d=(0,0.1,-1), L='stance', body=dict(Root=(18,0,18),Neck=(-6,0,-8))),
    K(R=(0.55,0.3,-1.6), d=(0,0.05,-1), L='stance', body=dict(Root=(18,0,20),Neck=(-6,0,-8)))],
   [K(L=(-1.35,-0.3,-0.6), ld=(0,0.15,-1), R=(1.2,-0.1,-1.0), d=(0.1,0.4,-0.9), body=dict(Root=(10,0,25))),
    K(L=(-0.55,0.35,-1.62), ld=(0,0.1,-1), R=(1.2,-0.1,-1.0), d=(0.1,0.4,-0.9), body=dict(Root=(18,0,-18),Neck=(-6,0,12))),
    K(L=(-0.55,0.3,-1.6), ld=(0,0.05,-1), R=(1.2,-0.1,-1.0), d=(0.1,0.4,-0.9), body=dict(Root=(18,0,-20),Neck=(-6,0,12)))],
   [K(R=(1.9,0.9,-0.5), d=(0.3,0.4,-0.87), L='stance', body=dict(Root=(8,0,-40),Neck=(-6,0,30))),
    K(R=(0.4,0.3,-1.55), d=(-0.5,0.1,-0.86), L='stance', body=dict(Root=(16,0,10))),
    K(R=(-0.4,0.0,-1.25), d=(-0.9,0,-0.4), L='stance', body=dict(Root=(18,0,40),Neck=(-6,0,-25)))],
   [K(R=(1.5,1.6,-0.5), d=(0.2,0.8,-0.5), L=(-1.5,1.6,-0.5), ld=(-0.2,0.8,-0.5), body=dict(Root=(0,0,0),Hop=(0.35,))),
    K(R=(0.15,-0.1,-1.5), d=(-0.4,-0.3,-0.87), via=(0,0.4,-0.9), L=(-0.15,-0.25,-1.45), ld=(0.4,-0.3,-0.87), lvia=(0,0.4,-0.9), body=dict(Root=(24,0,0),RH=(0,0,-30),LH=(0,0,-38))),
    K(R=(-0.5,-0.7,-1.1), d=(-0.6,-0.6,-0.5), L=(0.5,-0.7,-1.1), ld=(0.6,-0.6,-0.5), body=dict(Root=(24,0,0),RH=(0,0,-30),LH=(0,0,-38)))],
  ]),
 'Scythe': dict(roll=True, two=1.4,
  stance=K(R=(1.45,-0.3,-0.6), d=(0.05,0.97,-0.2), x=(0,0,-1), L=(-1.5,-0.95,-0.35), body=dict(Root=(4,0,-10),RH=(0,0,-8),LH=(0,0,-16),Neck=(0,0,8))),
  swings=[
   [K(R=(1.3,-0.2,-0.4), d=(0.85,-0.25,0.45), x=(0.45,0,-0.85), body=dict(Root=(0,0,-60),Neck=(0,0,40))),
    K(R=(0.6,-0.4,-1.4), d=(-0.1,-0.3,-0.95), x=(-1,0,0.1), via=(0.95,-0.28,-0.15), body=dict(Root=(12,0,0),RH=(0,0,-25),LH=(0,0,-32))),
    K(R=(-0.3,-0.3,-1.3), d=(-0.85,-0.25,0.4), x=(0.4,0,0.9), via=(-0.95,-0.28,-0.15), body=dict(Root=(16,0,62),RH=(0,0,-25),LH=(0,0,-32),Neck=(0,0,-35)))],
   [K(R=(-0.3,-0.2,-1.3), d=(-0.85,-0.25,0.45), body=dict(Root=(10,0,58),Neck=(0,0,-38))),
    K(R=(0.6,-0.4,-1.4), d=(0.1,-0.3,-0.95), via=(-0.95,-0.28,-0.15), body=dict(Root=(8,0,-5))),
    K(R=(1.4,-0.3,-0.6), d=(0.85,-0.25,0.4), via=(0.95,-0.28,-0.15), body=dict(Root=(2,0,-62),Neck=(0,0,40)))],
   [K(R=(1.3,-0.2,-0.4), d=(0.85,-0.25,0.45), x=(0.45,0,-0.85), body=dict(Root=(8,0,-90),Neck=(0,0,45))),
    K(R=(0.6,-0.4,-1.4), d=(-0.1,-0.3,-0.95), x=(-1,0,0.1), via=(0.95,-0.28,-0.15), body=dict(Root=(14,0,40),RH=(-8,0,-20),LH=(-8,0,-26))),
    K(R=(0.6,-0.4,-1.4), d=(-0.1,-0.3,-0.95), x=(-1,0,0.1), body=dict(Root=(16,0,160),RH=(-8,0,-20),LH=(-8,0,-26),Neck=(0,0,-40)))],
  ]),
 'Katana': dict(roll=True, two=-0.7,
  stance=K(R=(0.45,-0.35,-1.45), d=(0,0.35,-0.94), up=(0,0.94,0.35), body=dict(Root=(6,0,-8),RH=(0,0,-8),LH=(0,0,-18),Neck=(0,0,6))),
  swings=[
   [K(R=(1.1,1.3,-0.5), d=(0.55,0.35,0.75), up=(0.75,0,-0.55), via=(0.4,0.9,-0.1), body=dict(Root=(0,0,-45),Neck=(0,0,32))),
    K(R=(0.35,0.2,-1.55), d=(-0.5,0.05,-0.86), up=(-0.86,0,0.5), via=(0.9,0.2,-0.4), body=dict(Root=(14,0,12))),
    K(R=(-0.45,0.1,-1.3), d=(-0.9,0,0.35), up=(0.35,0,0.94), body=dict(Root=(18,0,45),Neck=(0,0,-30)))],
   [K(R=(-0.3,-0.65,-1.2), d=(-0.6,-0.55,0.55), up=(0.46,0.46,-0.75), body=dict(Root=(14,0,38),Neck=(0,0,-32))),
    K(R=(0.45,0.3,-1.5), d=(0.3,0.35,-0.89), up=(0.63,0.77,-0.14), via=(-0.25,-0.25,-0.93), body=dict(Root=(8,0,-8))),
    K(R=(1.1,1.35,-0.8), d=(0.5,0.8,0.3), up=(0.15,0.35,0.92), body=dict(Root=(-4,0,-45),Neck=(-8,0,35)))],
   [K(R=(0.75,0.0,-1.0), d=(0,0.05,-1), up=(0,1,0), via=(0.45,0.75,-0.5), body=dict(Root=(-5,0,-20),RH=(0,0,10))),
    K(R=(0.4,0.35,-1.6), d=(0,0.05,-1), up=(0,1,0), body=dict(Root=(32,0,0),RH=(0,0,-45),LH=(0,0,-55),Neck=(10,0,0))),
    K(R=(0.4,0.3,-1.58), d=(0,0,-1), up=(0,1,0), body=dict(Root=(26,0,8),RH=(0,0,-45),LH=(0,0,-55),Neck=(10,0,0)))],
  ]),
}

KEYS = ['Root', 'RS', 'LS', 'RH', 'LH', 'Neck', 'Grip', 'Hop']
out, report = {}, []

def handle_point(sol, reach):
    return np.array(sol['hand']) + np.array(sol['dir']) * reach

for kind, T in TYPES.items():
    roll = T.get('roll', False)
    offGrip = T.get('off')
    chain = [('stance', T['stance'])]
    for n, sw in enumerate(T['swings']):
        for i, p in enumerate(sw):
            chain.append((f"swing{n+1}.{['coil','cut','follow'][i]}", p))
    sols = {}
    prevR = prevL = None
    for label, p in chain:
        # the right arm (and the weapon's grip)
        if 'grip' in T:  # gauntlets: the grip never changes
            r = solve('R', prevR and pack(prevR, 3) if prevR else [0, 0, 90], target=p['R'], fixedGrip=T['grip'],
                      prev=pack(prevR, 3) if prevR else None, reg=0.05, wide=prevR is None)
            r['t'], r['r'] = T['grip']
        else:
            seed = pack(prevR, 5) if prevR else [0, 0, 60, -60, 0]
            path = arc(prevR['dir'], p['d'], p.get('via')) if prevR else None
            pathUp = arc(prevR['up'], p['up']) if (prevR and p.get('up') is not None) else None
            r = solve('R', seed, target=p['R'], dirT=p['d'], upT=p.get('up'), xT=p.get('x'), freeRoll=roll,
                      prev=seed if prevR else None, pathDir=path, pathUp=pathUp, wide=prevR is None)
        # the left arm
        Lp = p.get('L')
        if Lp == 'stance':
            l = sols['stance'][1]
        elif Lp is None and 'two' in T:
            # on the handle - and staying on it through the blend from the pose before
            tgt = handle_point(r, T['two'])
            ph = None
            if prevR is not None and 'grip' not in T:
                k = 5 if roll else 4
                a0, a1 = pack(prevR, k), pack(r, k)
                def ph(u, a0=a0, a1=a1):
                    pu = a0 + u * (a1 - a0)
                    h, d, _, _ = kin('R', pu[None, :3], np.array([pu[3]]), np.array([pu[4] if len(pu) > 4 else 0.0]))
                    return h[0] + d[0] * T['two']
            seedL = pack(prevL, 3) if prevL else [0, 0, -60]
            l = solve('L', seedL, target=tgt.tolist(), prev=seedL if prevL else None, pathHand=ph, wide=prevL is None)
        elif T.get('offsolve') and p.get('ld') is not None:
            seedL = pack(prevL, 3) if prevL else [0, 0, -60]
            if offGrip is None:  # the left weapon's grip, fixed from the stance on
                l = solve('L', seedL + [-60], target=Lp, dirT=p['ld'], wide=True)
                offGrip = (l['t'], 0)
            else:
                path = arc(prevL['dir'], p['ld'], p.get('lvia')) if prevL else None
                l = solve('L', seedL, target=Lp, dirT=p['ld'], fixedGrip=offGrip, prev=seedL if prevL else None, pathDir=path)
        else:
            seedL = pack(prevL, 3) if prevL else [0, 0, -60]
            start = np.array(prevL['hand']) if prevL else None
            ph = (lambda u, a=start, b=np.array(Lp): a + (b - a) * u) if prevL else None
            l = solve('L', seedL, target=Lp, fixedGrip=offGrip, prev=seedL if prevL else None, pathHand=ph, wide=prevL is None)
            if offGrip:
                l['t'], l['r'] = offGrip
        sols[label] = (r, l)
        prevR, prevL = r, l
        report.append(f"{kind:8s} {label:14s} R err {r['err']:.3f} hand {r['hand']} dir {r['dir']} | L err {l['err']:.3f} hand {l['hand']}")
    # build the poses
    stBody = T['stance']['body']
    poses = {}
    for label, p in chain:
        r, l = sols[label]
        pose = {'RS': r['a'], 'LS': l['a'], 'Grip': [r['t'], r['r']]}
        for k in ['Root', 'RH', 'LH', 'Neck']:
            pose[k] = list(p['body'].get(k, stBody.get(k, (0, 0, 0))))
        pose['Hop'] = list(p['body'].get('Hop', (0,)))
        poses[label] = pose
    out[kind] = {'stance': poses['stance'],
                 'swings': [[poses[f"swing{n+1}.{w}"] for w in ('coil', 'cut', 'follow')] for n in range(len(T['swings']))],
                 'off': offGrip}

def lua(p):
    return '{ ' + ', '.join(f"{k} = {{ {', '.join(str(int(round(v))) if k != 'Hop' else str(v) for v in p[k])} }}" for k in KEYS) + ' }'

print("\n".join(report), file=sys.stderr)
L = ["WeaponFX.STANCES = {"]
for kind in TYPES:
    L.append(f"\t{kind} = {lua(out[kind]['stance'])},")
L.append("}")
names = {'Fists': ['a right jab', 'a left hook', 'the uppercut: dip, then drive up off the floor'],
 'Hammer': ['a heavy diagonal: from high over the right shoulder, over the top and down across', 'a sweeping backhand at chest height, across the front', 'the overhead slam: up with a little leap, and everything comes down with it'],
 'Daggers': ['a right stab', 'a left stab', 'a right slash across', 'both blades crossing, with a hop in'],
 'Scythe': ['a wide sweep, right to left, blade low', 'sweeping back, left to right', 'a full turn with the blade out'],
 'Katana': ['a fast flat cut, right to left', 'a rising cut, low left to high right', 'the dashing thrust']}
for kind in TYPES:
    L.append(f"WeaponFX.POSES.{kind} = {{")
    for n, keys in enumerate(out[kind]['swings']):
        L.append(f"\t{{ -- {names[kind][n]}")
        for i, key in enumerate(['coil', 'cut', 'follow']):
            L.append(f"\t\t{key} = {lua(keys[i])},")
        L.append("\t},")
    L.append("}")
offs = {k: out[k]['off'] for k in TYPES if out[k]['off']}
offLine = "WeaponFX.OFFHAND = { " + ", ".join(f"{k} = {{ {int(round(v[0]))}, {int(round(v[1]))} }}" for k, v in offs.items()) + " }"
block = "\n".join(L)
if "--apply" in sys.argv:
    src = open(WEAPONFX).read()
    a = src.index("\n", src.index("-- BEGIN GENERATED POSES")) + 1
    b = src.index("-- END GENERATED POSES")
    src = src[:a] + block + "\n" + src[b:]
    src = re.sub(r"WeaponFX\.OFFHAND = \{[^\n]*\}", offLine, src)
    open(WEAPONFX, "w").write(src)
    print("wrote", os.path.normpath(WEAPONFX))
else:
    print(block)
    print(offLine)
