"""The weapon abilities' animations (ReplicatedStorage/Moves: what each ability
does, step by step) - made the way the types' swings are (weapon_types.py:
posing by direction, swings round a plane). Each one is timed to its move:
its big moment lands exactly when the move's hit (or effect) is due, and it
lasts the move's Time.

    python3 abilities.py            -> abilities/<weapon>.rbxmx (one animation each,
                                       for Tools/Upload/upload_assets.bat)
    python3 abilities.py preview    -> ../../Docs/animations/<pack>_abilities.mp4 and .png

The Slime pack for now; the other packs' come when their weapons do.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import combo  # noqa: E402
import weapon_types as wt  # noqa: E402
from anims import DirAnim, unit  # noqa: E402
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
        path = os.path.join(out, wid + '.rbxmx')
        with open(path, 'w') as f:
            f.write(head + '\n' + ex.sequence_xml(anim, 1) + '\n</roblox>\n')
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
        # its key moments
        moments = [0.0]
        hit = getattr(anim, 'hit', None)
        keys = [k[0] for k in anim.keys]
        moments += [k for k in keys if 0 < k < anim.length]
        if hit is not None and all(abs(hit - m) > 0.01 for m in moments):
            moments.append(hit)
        moments = sorted(set(round(m, 3) for m in moments))[:6]
        cells = []
        for m in moments:
            polys, _ = pv.figure(kind, anim.at(m))
            views = Image.new('RGB', (220, 440), (24, 20, 37))
            views.paste(pv.render(polys, -30, 8, 220), (0, 0))
            views.paste(pv.render(polys, 90, 4, 220), (0, 220))
            cells.append(('%.2fs%s' % (m, ' HIT' if hit is not None and abs(m - hit) < 0.01 else ''), views))
        sheet_rows.append((wid, cells))
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
        preview()
    else:
        export()
