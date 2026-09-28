"""Writes the sword animations as Roblox KeyframeSequences (.rbxmx files you
insert into Studio: right-click in the Explorer -> Insert from File), baked
at 60 keyframes a second - every joint's Motor6D.Transform, exactly as
posed here - plus markers the game can listen for
(AnimationTrack:GetMarkerReachedSignal): "Cut" as the strike starts, "Hit"
the moment the blade lands (the server's hit), "Through" at the end of the
follow-through.

    python3 export_rbxmx.py          -> out/SwordAnimations.rbxmx (all of them, in a folder)

The sword is animated too: its Motor6D ("Grip": Right Arm -> the sword's
Handle, C0 = 1 stud down the arm) is posed as "Handle" under "Right Arm".
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anims  # noqa: E402
import combo  # noqa: E402
import r6  # noqa: E402

OUT = os.path.join(HERE, 'out')
FPS = 60
PRIORITY = {'Idle': 0, 'Movement': 1, 'Action': 2, 'Action2': 3, 'Action3': 4, 'Action4': 5}
# when each swing's markers fall (seconds): the strike starting, the hit, the end of the cut
MARKERS = {
    'SwordSwing1': [('Cut', 0.13), ('Hit', 0.20), ('Through', 0.36)],
    'SwordSwing2': [('Cut', 0.13), ('Hit', 0.20), ('Through', 0.36)],
    'SwordSwing3': [('Cut', 0.24), ('Hit', 0.3375), ('Through', 0.60)],
}

_ref = [0]


def ref():
    _ref[0] += 1
    return 'RBX%d' % _ref[0]


def num(x):
    s = '%.6f' % x
    s = s.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def cframe_xml(m):
    p = m[:3, 3]
    r = m[:3, :3]
    parts = ['<X>%s</X><Y>%s</Y><Z>%s</Z>' % (num(p[0]), num(p[1]), num(p[2]))]
    for i in range(3):
        for j in range(3):
            parts.append('<R%d%d>%s</R%d%d>' % (i, j, num(r[i, j]), i, j))
    return '<CoordinateFrame name="CFrame">%s</CoordinateFrame>' % ''.join(parts)


def pose_xml(name, m, children, indent):
    pad = '\t' * indent
    out = [pad + '<Item class="Pose" referent="%s">' % ref(),
           pad + '\t<Properties>',
           pad + '\t\t' + cframe_xml(m),
           pad + '\t\t<token name="EasingDirection">0</token>',
           pad + '\t\t<token name="EasingStyle">0</token>',
           pad + '\t\t<string name="Name">%s</string>' % name,
           pad + '\t\t<float name="Weight">1</float>',
           pad + '\t</Properties>']
    for c in children:
        out.append(c)
    out.append(pad + '</Item>')
    return '\n'.join(out)


def keyframe_xml(t, tr, markers, indent):
    """one keyframe: the pose tree HumanoidRootPart > Torso > (Head, arms, legs; the Handle under the right arm)"""
    I = r6.cf()
    d = indent + 3
    limbs = [
        pose_xml('Head', tr['Neck'], [], d + 1),
        pose_xml('Right Arm', tr['Right Shoulder'], [pose_xml('Handle', tr['Grip'], [], d + 2)], d + 1),
        pose_xml('Left Arm', tr['Left Shoulder'], [], d + 1),
        pose_xml('Right Leg', tr['Right Hip'], [], d + 1),
        pose_xml('Left Leg', tr['Left Hip'], [], d + 1),
    ]
    torso = pose_xml('Torso', tr['RootJoint'], limbs, d)
    root = pose_xml('HumanoidRootPart', I, [torso], indent + 2)
    pad = '\t' * indent
    out = [pad + '<Item class="Keyframe" referent="%s">' % ref(),
           pad + '\t<Properties>',
           pad + '\t\t<string name="Name">Keyframe</string>',
           pad + '\t\t<float name="Time">%s</float>' % num(t),
           pad + '\t</Properties>',
           root]
    for name in markers:
        out += [pad + '\t<Item class="KeyframeMarker" referent="%s">' % ref(),
                pad + '\t\t<Properties>',
                pad + '\t\t\t<string name="Name">%s</string>' % name,
                pad + '\t\t\t<string name="Value"></string>',
                pad + '\t\t</Properties>',
                pad + '\t</Item>']
    out.append(pad + '</Item>')
    return '\n'.join(out)


def sequence_xml(anim, indent=1):
    marks = MARKERS.get(anim.name, [])
    times = [i / FPS for i in range(int(round(anim.length * FPS)) + (0 if anim.loop else 1))]
    for _, mt in marks:
        if all(abs(mt - t) > 1e-6 for t in times):
            times.append(mt)
    times.sort()
    pad = '\t' * indent
    out = [pad + '<Item class="KeyframeSequence" referent="%s">' % ref(),
           pad + '\t<Properties>',
           pad + '\t\t<string name="Name">%s</string>' % anim.name,
           pad + '\t\t<bool name="Loop">%s</bool>' % ('true' if anim.loop else 'false'),
           pad + '\t\t<token name="Priority">%d</token>' % PRIORITY[anim.priority],
           pad + '\t</Properties>']
    for t in times:
        tr = anims.dir_transforms(anim.at(t))
        here = [name for name, mt in marks if abs(mt - t) < 1e-6]
        out.append(keyframe_xml(t, tr, here, indent + 1))
    out.append(pad + '</Item>')
    return '\n'.join(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    head = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
    body = ['\t<Item class="Folder" referent="%s">' % ref(),
            '\t\t<Properties>',
            '\t\t\t<string name="Name">SwordAnimations</string>',
            '\t\t</Properties>']
    for name in ('SwordIdle', 'SwordSwing1', 'SwordSwing2', 'SwordSwing3'):
        body.append(sequence_xml(combo.ANIMS[name], 2))
    body.append('\t</Item>')
    path = os.path.join(OUT, 'SwordAnimations.rbxmx')
    with open(path, 'w') as f:
        f.write(head + '\n' + '\n'.join(body) + '\n</roblox>\n')
    print('saved', path, os.path.getsize(path) // 1024, 'KB')


if __name__ == '__main__':
    main()
