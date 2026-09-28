"""Draws the hit reactions: a Colosseum straw dummy taking a light hit (it
flashes white and tips away, then is knocked back a little) and a finisher
(sent flying, landing well back), from the real ColosseumService's poses.

    luau test_colosseum.luau -a react 3 snap > react.txt
    python3 render_react.py react.txt ../../Docs/hit_reactions.png

The react scenario prints the dummy's parts at a few moments (RSNAP lines,
then one JSON line per part, then FEET x y z); this adds the sand, a mark
where the dummy stood, and a player with the sword, and hands the scene to
render_snaps.py.
"""
import json, os, subprocess, sys

src, out = sys.argv[1], sys.argv[2]
frames, cur = [], None
for line in open(src):
    if line.startswith('RSNAP '):
        cur = {'name': line.split()[1], 'parts': [], 'feet': None}
        frames.append(cur)
    elif line.startswith('{') and cur is not None:
        cur['parts'].append(json.loads(line))
    elif line.startswith('FEET ') and cur is not None:
        cur['feet'] = [float(v) for v in line.split()[1:4]]
if not frames:
    sys.exit('no RSNAP frames in ' + src)

start = frames[0]['feet']
x0, y0, z0 = start

def box(name, size, pos, color, mat='SmoothPlastic', t=0.0, shape='Block', rot=(1, 0, 0, 0, 1, 0, 0, 0, 1)):
    # (render_snaps.py's part format: name, class, size, CFrame, colour, material, shape, transparency)
    return {'n': name, 'c': 'Part', 's': list(size), 'cf': list(pos) + list(rot), 'col': list(color), 'm': mat, 'sh': shape, 't': t}

SKIN, SHIRT, PANTS = (245, 205, 48), (13, 105, 172), (40, 127, 71)
STEEL, GOLD, GLOW, GRIP = (192, 203, 220), (254, 231, 97), (200, 240, 255), (115, 62, 57)

def player(swinging):
    """A blocky player on the left, facing the dummy (+x): the sword held low
    and ready, or thrust out at the dummy mid-cut."""
    px, pz = x0 - 6.5, z0
    parts = [
        box('LeftLeg', (1, 2, 1), (px, 1, pz - 0.5), PANTS),
        box('RightLeg', (1, 2, 1), (px, 1, pz + 0.5), PANTS),
        box('Torso', (1, 2, 2), (px, 3, pz), SHIRT),
        box('Head', (1.2, 1.2, 1.2), (px, 4.6, pz), SKIN),
        box('LeftArm', (1, 2, 1), (px, 3, pz - 1.5), SKIN),
    ]
    if swinging:
        # the sword arm straight out at the dummy, the blade carrying on past the fist
        parts += [
            box('RightArm', (2, 1, 1), (px + 1.2, 3.5, pz + 1.5), SKIN),
            box('Handle', (0.9, 0.35, 0.35), (px + 2.6, 3.5, pz + 1.5), GRIP),
            box('Guard', (0.36, 0.36, 1.5), (px + 3.1, 3.5, pz + 1.5), GOLD),
            box('Blade', (4, 0.8, 0.3), (px + 5.2, 3.5, pz + 1.5), STEEL),
            box('Edge', (3.8, 0.14, 0.32), (px + 5.2, 3.84, pz + 1.5), GLOW, 'Neon'),
        ]
    else:
        # the arm down, the blade low and forward (the stance)
        parts += [
            box('RightArm', (1, 2, 1), (px, 3, pz + 1.5), SKIN),
            box('Handle', (0.9, 0.35, 0.35), (px + 0.5, 1.9, pz + 1.5), GRIP),
            box('Guard', (0.36, 0.36, 1.5), (px + 1.0, 1.9, pz + 1.5), GOLD),
            box('Blade', (3.6, 0.3, 0.8), (px + 2.8, 1.35, pz + 1.5), STEEL, rot=(0.96, 0.28, 0, -0.28, 0.96, 0, 0, 0, 1)),
        ]
    return parts

CAPTIONS = {
    'ready': 'A STRAW DUMMY, READY',
    'hit': 'A HIT LANDS: IT FLASHES WHITE AND TIPS AWAY',
    'knocked': 'KNOCKED BACK A LITTLE, THEN IT WOBBLES UPRIGHT',
    'flying': 'THE FINISHER SENDS IT FLYING',
    'landed': 'IT LANDS 7 STUDS BACK',
}

scene = src + '.scene.txt'
with open(scene, 'w') as f:
    f.write('SKY 120,170,230|200,225,245\n')
    for fr in frames:
        name = fr['name']
        eye = (x0 + 1.5, y0 + 6, z0 + 23)
        look = (x0 + 1.5, y0 + 2.6, z0)
        f.write('SNAP %s %.2f %.2f %.2f %.2f %.2f %.2f 52\n' % ((name,) + eye + look))
        f.write('CAPTION %s %s\n' % (name, CAPTIONS.get(name, name.upper())))
        scene_parts = [box('Sand', (70, 1, 40), (x0 + 4, y0 - 0.5, z0 - 4), (228, 196, 140))]
        if name != 'ready':
            # where it stood before it was hit
            scene_parts.append(box('Mark', (0.1, 3.2, 3.2), (x0, y0 + 0.06, z0), (24, 20, 37), t=0.55, shape='Cylinder',
                                   rot=(0, -1, 0, 1, 0, 0, 0, 0, 1)))
        scene_parts += player(name in ('hit', 'flying'))
        for p in scene_parts + fr['parts']:
            f.write(json.dumps(p) + '\n')

here = os.path.dirname(os.path.abspath(__file__))
subprocess.check_call([sys.executable, os.path.join(here, 'render_snaps.py'), scene, out, '--cols', '2',
                       '--title', 'HIT REACTIONS|DUMMIES FLASH, TIP OVER AND GET KNOCKED BACK|BOSSES JOLT BACK FROM EVERY BLOW'])
