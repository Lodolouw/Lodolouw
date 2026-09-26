"""Checks a lobby dump for building mistakes: parts floating in the air
touching nothing, objects (a torch, a banner) touching nothing outside
themselves, plants poking into fences, walls and buildings, small bits
lying on paths, and surfaces you can see lying exactly on each other (they
flicker in the game).

    luau lobby_dump.luau > lobby.jsonl
    python3 check_lobby.py lobby.jsonl

Some things it lists are on purpose (the Quest Board's "!" floats, the
lamps' bulbs hang inside their cages, the Spire's roots grow over its rocks,
RetroWorld's clouds and birds fly): read the list, don't just empty it."""
import json, math, collections, sys
import numpy as np

parts = [json.loads(l) for l in open(sys.argv[1] if len(sys.argv) > 1 else 'lobby.jsonl') if l.startswith('{')]
for i, p in enumerate(parts):
    p['i'] = i
    p['cls'] = p['c']  # (the class; 'c' becomes the centre below)
    c = np.array(p['cf'][0:3])
    R = np.array(p['cf'][3:12]).reshape(3, 3)
    s = np.array(p['s']) / 2
    if p['sh'] == 'Ball':
        r = min(p['s']) / 2
        half = np.array([r, r, r])
    elif p['sh'] == 'Cylinder':
        # axis along X: length s.x, diameter min(y, z)
        r = min(p['s'][1], p['s'][2]) / 2
        loc = np.array([s[0], r, r])
        half = np.abs(R) @ loc
    else:
        half = np.abs(R) @ s
    p['lo'] = c - half
    p['hi'] = c + half
    p['c'] = c

# spatial hash (4-stud cells) over the AABBs
CELL = 4.0
grid = collections.defaultdict(list)
for p in parts:
    if max(p['hi'] - p['lo']) > 60:
        continue  # (huge things - the island, the sea - are handled apart)
    a = np.floor(p['lo'] / CELL).astype(int)
    b = np.floor(p['hi'] / CELL).astype(int)
    for x in range(a[0], b[0] + 1):
        for y in range(a[1], b[1] + 1):
            for z in range(a[2], b[2] + 1):
                grid[(x, y, z)].append(p['i'])
big = [p for p in parts if max(p['hi'] - p['lo']) > 60]


def neighbours(p, pad=0.06):
    a = np.floor((p['lo'] - pad) / CELL).astype(int)
    b = np.floor((p['hi'] + pad) / CELL).astype(int)
    seen = set()
    for x in range(a[0], b[0] + 1):
        for y in range(a[1], b[1] + 1):
            for z in range(a[2], b[2] + 1):
                for j in grid.get((x, y, z), ()):
                    if j != p['i'] and j not in seen:
                        seen.add(j)
                        q = parts[j]
                        if np.all(p['lo'] - pad <= q['hi']) and np.all(q['lo'] - pad <= p['hi']):
                            yield q
    for q in big:
        if q['i'] != p['i'] and np.all(p['lo'] - pad <= q['hi']) and np.all(q['lo'] - pad <= p['hi']):
            yield q

# the ground height (the island's top is y = 0)
FLOAT_OK = {'SignAnchor', 'Sea', 'Cloud', 'Barrier', 'Bird', 'Gull', 'Sparkle', 'WaveCrest', 'Foam', 'Droplet',
            'Ripple', 'BowlRipple', 'RiverRipple', 'Spray', 'Mote', 'Part'}
floating = collections.defaultdict(list)
for p in parts:
    if p['t'] >= 0.98 or p['n'] in FLOAT_OK and not p['p'].startswith('RetroWorld/Detail'):
        continue
    if 'FX' in p['tags'] or 'Wave' in p['tags']:
        continue
    if p['lo'][1] <= 0.35 and p['hi'][1] > -40:
        continue  # (on the ground)
    touching = any(q['t'] < 0.98 for q in neighbours(p))
    if not touching:
        floating[(p['p'].split('/')[1] if '/' in p['p'] else p['p'], p['n'])].append(p)

print('=== FLOATING (touching nothing, off the ground) ===')
for k, lst in sorted(floating.items(), key=lambda kv: -len(kv[1])):
    ex = lst[0]
    print(f"{k[0]:16s} {k[1]:18s} x{len(lst):4d}   e.g. at ({ex['c'][0]:.1f}, {ex['c'][1]:.1f}, {ex['c'][2]:.1f}) size {ex['s']}")


# ---------------------------------------------------------------- objects
def obb(p):
    c = p['c']
    R = np.array(p['cf'][3:12]).reshape(3, 3)
    s = np.array(p['s']) / 2
    if p['sh'] == 'Ball':
        r = min(p['s']) / 2
        s = np.array([r, r, r]) * 0.85
    elif p['sh'] == 'Cylinder':
        r = min(p['s'][1], p['s'][2]) / 2
        s = np.array([s[0], r * 0.9, r * 0.9])
    return c, R, s


def sat_depth(p, q):
    """How deep two boxes overlap (0 if they don't), by the separating-axis test."""
    ca, Ra, sa = obb(p)
    cb, Rb, sb = obb(q)
    axes = [Ra[:, i] for i in range(3)] + [Rb[:, i] for i in range(3)]
    for i in range(3):
        for j in range(3):
            a = np.cross(Ra[:, i], Rb[:, j])
            n = np.linalg.norm(a)
            if n > 1e-6:
                axes.append(a / n)
    d = cb - ca
    best = math.inf
    for ax in axes:
        ra = sum(sa[k] * abs(Ra[:, k] @ ax) for k in range(3))
        rb = sum(sb[k] * abs(Rb[:, k] @ ax) for k in range(3))
        o = ra + rb - abs(d @ ax)
        if o <= 0:
            return 0
        best = min(best, o)
    return best


groups = collections.defaultdict(list)
for p in parts:
    if p['mid']:
        groups[p['mid']].append(p)
print()
print('=== OBJECTS TOUCHING NOTHING OUTSIDE THEMSELVES (off the ground) ===')
lost = collections.Counter()
lostEx = {}
for mid, lst in groups.items():
    name = lst[0]['p'].split('/')[-1]
    if name in ('PalmCrownSway', 'QuestMark', 'MillSails') or lst[0]['p'].startswith('RetroWorld'):
        continue
    if any(p['lo'][1] <= 0.35 for p in lst if p['t'] < 0.98):
        continue
    ok = False
    for p in lst:
        for q in neighbours(p, 0.08):
            if q['mid'] != mid and q['t'] < 0.98:
                ok = True
                break
        if ok:
            break
    if not ok:
        lost[lst[0]['p']] += 1
        lostEx[lst[0]['p']] = lst[0]
for k, v in lost.most_common():
    e = lostEx[k]
    print(f"{k:45s} x{v:3d}  e.g. {e['n']} at ({e['c'][0]:.1f}, {e['c'][1]:.1f}, {e['c'][2]:.1f})")

# ---------------------------------------------------------------- poking
VEG = {'Canopy', 'CanopyTop', 'CanopyCrown', 'CanopyLump', 'CanopyLight', 'Trunk', 'Branch', 'Root', 'Bush', 'Leaf',
       'Frond', 'FrondTip', 'PalmTrunk', 'Coconut', 'LeafClump', 'TreeTrunk', 'TreeBranch'}
STRUCT_WORDS = ('Fence', 'Wall', 'Curb', 'Post', 'Lantern', 'Foot', 'Collar', 'Roof', 'Timber', 'Beam', 'Door', 'Window',
                'Tower', 'Body', 'Band', 'Ledge', 'Merlon', 'Plate', 'Bracket', 'Stick', 'Head', 'Rod', 'Cloth', 'Gate',
                'Stair', 'Step', 'Hall', 'Keep', 'Counter', 'Awning', 'Sign', 'Bench', 'Barrel', 'Crate', 'Rim', 'Plinth',
                'Arch', 'Pillar', 'Column', 'Bridge', 'Rail', 'House', 'Stall', 'Board', 'Frame', 'Leg', 'Shelf')
PATHS = {'PathToGate', 'StairLanding', 'PathEastWest', 'PathToForge', 'PathForgeSide', 'PathToYard', 'PlazaOuter',
         'PlazaMid', 'PlazaInner'}


def is_struct(q):
    if q['n'] in VEG or q['p'].startswith('RetroWorld') or q['t'] >= 0.98:
        return False
    return any(w in q['n'] for w in STRUCT_WORDS)


print()
print('=== PLANTS POKING INTO THINGS (deeper than 0.4 studs) ===')
hits = collections.defaultdict(list)
for p in parts:
    if p['n'] not in VEG or p['t'] >= 0.98:
        continue
    for q in neighbours(p, 0):
        if q['mid'] == p['mid'] and p['mid'] != 0:
            continue
        struct = is_struct(q)
        onPath = q['n'] in PATHS and p['n'] in ('Trunk', 'Root', 'Bush', 'Leaf', 'PalmTrunk', 'TreeTrunk')
        if not (struct or onPath):
            continue
        dep = sat_depth(p, q)
        if dep > 0.4:
            hits[(p['p'], q['p'] + ':' + q['n'])].append((p, q, dep))
for (a, b), lst in sorted(hits.items(), key=lambda kv: -max(x[2] for x in kv[1])):
    p, q, dep = max(lst, key=lambda x: x[2])
    print(f"{a:34s} into {b:44s} x{len(lst):3d} deepest {dep:4.1f} at ({p['c'][0]:.0f}, {p['c'][1]:.0f}, {p['c'][2]:.0f}) [{p['n']}]")

# ---------------------------------------------------------------- bits on paths
print()
print('=== SMALL BITS LYING ON PATHS ===')
slabs = [p for p in parts if p['n'] in PATHS]
onpath = collections.Counter()
onEx = {}
for p in parts:
    if p['t'] >= 0.98 or max(p['s']) > 3 or p['n'] in PATHS:
        continue
    if p['p'].startswith('RetroWorld/Detail') and p['s'][1] <= 0.09:
        continue  # (the cobbles themselves)
    for sl in slabs:
        top = sl['hi'][1]
        if sl['lo'][0] < p['c'][0] < sl['hi'][0] and sl['lo'][2] < p['c'][2] < sl['hi'][2] and abs(p['lo'][1] - top) < 0.5:
            if sl['n'].startswith('Plaza'):
                dx, dz = p['c'][0] - sl['c'][0], p['c'][2] - sl['c'][2]
                if math.hypot(dx, dz) > min(sl['s'][1], sl['s'][2]) / 2:
                    continue
            k = (p['p'], p['n'], sl['n'])
            onpath[k] += 1
            onEx[k] = p
            break
for k, v in onpath.most_common(40):
    e = onEx[k]
    print(f"{k[0]:30s} {k[1]:16s} on {k[2]:14s} x{v:3d}  e.g. ({e['c'][0]:.1f}, {e['c'][1]:.2f}, {e['c'][2]:.1f}) size {e['s']} col {e['col']}")

# ---------------------------------------------------------------- flicker
# Faces in the same plane, facing the same way, overlapping, in different
# colours - only where you can SEE them (the shared patch is sampled, and a
# point counts only if nothing else sits just in front of it). Faces facing
# straight down are left out (you hardly ever see them).
boxes = []
for i, p in enumerate(parts):
    R = np.array(p['cf'][3:12]).reshape(3, 3)
    c = np.array(p['cf'][0:3])
    s = np.array(p['s']) / 2
    if p['sh'] == 'Ball':
        r = min(p['s']) / 2 * 0.8
        half = np.array([r, r, r])
    elif p['sh'] == 'Cylinder':
        r = min(p['s'][1], p['s'][2]) / 2 * 0.8
        half = np.abs(R) @ np.array([s[0], r, r])
    else:
        half = np.abs(R) @ s
    axis_aligned = p['sh'] == 'Block' and np.all((np.abs(R) < 1e-3) | (np.abs(np.abs(R) - 1) < 1e-3))
    boxes.append((c - half, c + half, axis_aligned, p['t'] < 0.5))
CELL = 4.0
grid = collections.defaultdict(list)
for i, (lo, hi, aa, solid) in enumerate(boxes):
    if not solid or not aa or np.max(hi - lo) > 600:
        continue
    a = np.floor(lo / CELL).astype(int)
    b = np.floor(hi / CELL).astype(int)
    if np.prod(b - a + 1) > 20000:
        continue
    for x in range(a[0], b[0] + 1):
        for y in range(a[1], b[1] + 1):
            for z in range(a[2], b[2] + 1):
                grid[(x, y, z)].append(i)
bigs = [i for i, (lo, hi, aa, solid) in enumerate(boxes) if solid and aa and np.max(hi - lo) > 600]


def covered(pt, skip):
    k = tuple(np.floor(pt / CELL).astype(int))
    for j in list(grid.get(k, ())) + bigs:
        if j in skip:
            continue
        lo, hi, aa, solid = boxes[j]
        if np.all(pt > lo + 1e-4) and np.all(pt < hi - 1e-4):
            return True
    return False


faces = collections.defaultdict(list)
for i, p in enumerate(parts):
    lo, hi, aa, solid = boxes[i]
    if p['t'] >= 0.98 or not aa or p['cls'] != 'Part':
        continue
    for ax in range(3):
        for sg in (1, -1):
            plane = hi[ax] if sg > 0 else lo[ax]
            o = [k for k in range(3) if k != ax]
            faces[(ax, sg, round(plane * 50))].append(((lo[o[0]], hi[o[0]], lo[o[1]], hi[o[1]]), i))
found = collections.defaultdict(float)
ex = {}
for key, lst in faces.items():
    if len(lst) < 2:
        continue
    ax, sg, pl = key
    if ax == 1 and sg < 0:
        continue
    o = [k for k in range(3) if k != ax]
    for a_ in range(len(lst)):
        for b_ in range(a_ + 1, len(lst)):
            (A, i), (B, j) = lst[a_], lst[b_]
            p, q = parts[i], parts[j]
            if p['col'] == q['col']:
                continue
            x0, x1 = max(A[0], B[0]), min(A[1], B[1])
            z0, z1 = max(A[2], B[2]), min(A[3], B[3])
            if x1 - x0 < 0.05 or z1 - z0 < 0.05:
                continue
            # sample the shared patch, just in front of the face
            vis = 0
            n = 0
            for u in np.linspace(x0, x1, 5)[1:-1] if x1 - x0 > 0.2 else [(x0 + x1) / 2]:
                for v in np.linspace(z0, z1, 5)[1:-1] if z1 - z0 > 0.2 else [(z0 + z1) / 2]:
                    pt = np.zeros(3)
                    pt[ax] = pl / 50 + sg * 0.03
                    pt[o[0]], pt[o[1]] = u, v
                    n += 1
                    if not covered(pt, {i, j}):
                        vis += 1
            if vis == 0:
                continue
            area = (x1 - x0) * (z1 - z0) * vis / n
            k = tuple(sorted([p['p'] + ':' + p['n'], q['p'] + ':' + q['n']]))
            found[k] += area
            ex[k] = (p, key)
print()
print('=== SURFACES YOU CAN SEE LYING ON EACH OTHER (they flicker) ===')
for k, area in sorted(found.items(), key=lambda kv: -kv[1])[:45]:
    p, key = ex[k]
    if 'RetroWorld/Motes' in k[0]:
        continue
    print(f"{k[0]:42s} | {k[1]:42s} visible area {area:7.2f}  {'+' if key[1] > 0 else '-'}{'XYZ'[key[0]]} at {key[2] / 50:.2f} near ({p['cf'][0]:.0f}, {p['cf'][1]:.1f}, {p['cf'][2]:.0f})")
