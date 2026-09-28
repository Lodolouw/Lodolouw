"""Renders the R6 sword animations with Blender (Cycles - no graphics card
needed), so they can be looked at before they go anywhere near Roblox.

    <python with bpy> render_anims.py poses OUT.png [old|new]      key poses, a sheet
    <python with bpy> render_anims.py video OUT.mp4                 the combo: real speed, then slow

The character is the exact R6 rig (r6.py) in its classic colours, holding
the Iron Warden (Tools/Weapons), on a checked floor so steps and lunges read.
"""
import os
import sys
import math

import numpy as np
import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'Weapons'))
import r6  # noqa: E402
import anims  # noqa: E402
import sprites  # noqa: E402
import make_weapons as mw  # noqa: E402

# Roblox (x right, y up, the body facing -z) -> Blender (x right, y away, z up)
M4 = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], dtype=float)


def to_blender(w):
    return M4 @ w @ M4.T


def material(name, rgb, rough=0.6, emit=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get('Principled BSDF')
    lin = tuple((c / 255) ** 2.2 for c in rgb) + (1,)
    b.inputs['Base Color'].default_value = lin
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = lin
        b.inputs['Emission Strength'].default_value = emit
    return m


def box(name, size, rgb, offset=(0, 0, 0), bevel=0.05):
    """a box `size` (Roblox axes) around `offset` in its part's own frame"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        x, y, z = v.co
        rx, ry, rz = x * size[0] + offset[0], y * size[1] + offset[1], z * size[2] + offset[2]
        v.co = (rx, -rz, ry)  # (Roblox -> Blender, in the part's frame)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material(name + 'Mat', rgb))
    if bevel:
        mod = ob.modifiers.new('Bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    return ob


class Rig:
    def __init__(self, weapon='IronWarden'):
        self.parts = {}
        for name, (size, rgb) in r6.PARTS.items():
            if rgb is None:
                continue
            if name == 'Head':
                # the classic rounded head is a little bigger than its part
                ob = box(name, (1.25, 1.25, 1.25), rgb, bevel=0.22)
                self.face = [
                    box('EyeL', (0.14, 0.26, 0.06), (20, 20, 25), (-0.24, 0.14, -0.64), bevel=0),
                    box('EyeR', (0.14, 0.26, 0.06), (20, 20, 25), (0.24, 0.14, -0.64), bevel=0),
                    box('Mouth', (0.5, 0.08, 0.06), (20, 20, 25), (0, -0.22, -0.64), bevel=0),
                    box('MouthL', (0.08, 0.1, 0.06), (20, 20, 25), (-0.27, -0.16, -0.64), bevel=0),
                    box('MouthR', (0.08, 0.1, 0.06), (20, 20, 25), (0.27, -0.16, -0.64), bevel=0),
                ]
            else:
                ob = box(name, size, rgb)
            self.parts[name] = ob
        # the sword: the voxel Iron Warden, its grip's middle in the hand, the
        # blade along the handle's -Z, its edge along +Y (as WeaponFX holds one)
        img = mw.palette_image()
        grid = dict((k, fn) for k, _, fn in sprites.WEAPONS)[weapon]()
        body = mw.build_mesh(weapon, grid, False)
        body.data.materials.append(mw.material_palette(img))
        shine = mw.build_mesh(weapon + 'Glow', grid, True)
        if shine:
            shine.data.materials.append(mw.material_glow(img))
        grip_rows = [y for y, row in enumerate(grid) if any(sprites.PALETTE.get(c, ('', '', ''))[2] == 'grip' for c in row)]
        h = len(grid)
        grip_mid = (h - (min(grip_rows) + max(grip_rows) + 1) / 2) * mw.PIXEL
        # mesh (x across, y thick, z up) -> handle (Roblox): across -> Y, thick -> X, up -> -Z
        rm = np.array([[0, 1, 0, 0], [1, 0, 0, 0], [0, 0, -1, 0], [0, 0, 0, 1]], dtype=float)
        shift = np.eye(4)
        shift[2, 3] = -grip_mid
        fix = M4 @ rm @ shift
        from mathutils import Matrix
        for ob in (body, shine):
            if ob:
                ob.data.transform(Matrix(fix.tolist()))
        self.sword = [o for o in (body, shine) if o]

    def pose(self, tr, hrp=None):
        world = r6.solve(tr, hrp)
        from mathutils import Matrix
        for name, ob in self.parts.items():
            ob.matrix_world = Matrix(to_blender(world[name]).tolist())
        for ob in self.face:
            ob.matrix_world = Matrix(to_blender(world['Head']).tolist())
        for ob in self.sword:
            ob.matrix_world = Matrix(to_blender(world['Handle']).tolist())
        return world


def stage(res=(720, 720), samples=12):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    world = bpy.data.worlds.new('World')
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    world.node_tree.nodes.get('Background').inputs['Color'].default_value = (0.06, 0.07, 0.11, 1)
    for name, rot, strength, color in (
        ('Key', (48, 0, 145), 3.2, (1.0, 0.95, 0.88)),
        ('Rim', (60, 0, -20), 2.4, (0.55, 0.72, 1.0)),
        ('Fill', (75, 0, 250), 0.8, (0.85, 0.88, 1.0)),
    ):
        ld = bpy.data.lights.new(name, 'SUN')
        ld.energy, ld.color, ld.angle = strength, color, math.radians(6)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)
    # a checked floor
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new('Floor')
    try:
        fm.use_nodes = True
    except Exception:
        pass
    nt = fm.node_tree
    chk = nt.nodes.new('ShaderNodeTexChecker')
    chk.inputs['Scale'].default_value = 40
    chk.inputs['Color1'].default_value = (0.055, 0.06, 0.08, 1)
    chk.inputs['Color2'].default_value = (0.075, 0.08, 0.105, 1)
    nt.links.new(chk.outputs['Color'], nt.nodes.get('Principled BSDF').inputs['Base Color'])
    nt.nodes.get('Principled BSDF').inputs['Roughness'].default_value = 0.8
    floor.data.materials.append(fm)
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.image_settings.file_format = 'PNG'
    try:
        scene.view_settings.view_transform = 'AgX'
    except Exception:
        pass
    return scene


def camera(scene, eye, look, lens=40):
    cd = bpy.data.cameras.new('Cam')
    cd.lens = lens
    cam = bpy.data.objects.new('Cam', cd)
    scene.collection.objects.link(cam)
    from mathutils import Vector
    cam.location = eye
    d = Vector(look) - Vector(eye)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    return cam


def shoot(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def pose_sheet(out, which):
    """key poses, each from the front-right and the left, into one sheet"""
    from PIL import Image, ImageDraw
    scene = stage((460, 460), 10)
    rig = Rig()
    cam = camera(scene, (7.5, 9.5, 5.2), (0, 0, 2.6))
    if which == 'old':
        poses = [('STANCE', anims.OLD_STANCE)]
        for i, s in enumerate(anims.OLD):
            for k in ('coil', 'cut', 'follow'):
                poses.append(('%d %s' % (i + 1, k.upper()), s[k]))
    else:
        import combo
        poses = [(name, p) for name, p in combo.KEY_POSES]
    tiles = []
    tmp = os.path.join(os.path.dirname(os.path.abspath(out)), '_tile.png')
    views = (((7.5, 9.5, 5.2), (0, 0, 2.6)), ((-10.5, 2.0, 4.2), (0, 0, 2.4)))
    for label, p in poses:
        rig.pose(anims.pose_transforms(p) if which == 'old' else anims.dir_transforms(p))
        pair = []
        for eye, look in views:
            from mathutils import Vector
            cam.location = eye
            cam.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat('-Z', 'Y').to_euler()
            shoot(scene, tmp)
            pair.append(Image.open(tmp).convert('RGB'))
        tile = Image.new('RGB', (920, 490), (14, 14, 22))
        tile.paste(pair[0], (0, 30))
        tile.paste(pair[1], (460, 30))
        ImageDraw.Draw(tile).text((10, 8), label, fill=(255, 255, 255))
        tiles.append(tile)
    cols = 2
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 920, rows * 490), (0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * 920, (i // cols) * 490))
    sheet.save(out)
    print('saved', out)


def video(out, size=480, samples=8, fps=60):
    """the whole combo from behind you (the way you see yourself) and from the
    front, side by side: at real speed, then at a quarter speed"""
    from PIL import Image, ImageDraw
    import imageio_ffmpeg
    import combo
    scene = stage((size, size), samples)
    rig = Rig()
    cam = camera(scene, (0, 0, 0), (0, 0, 1))
    from mathutils import Vector
    views = (((4.5, -11.0, 5.6), (0.3, 1.5, 2.6)),  # behind, over the right shoulder (your camera)
             ((6.5, 10.0, 4.4), (0, 0, 2.4)))  # in front, from the right
    tmp = os.path.join(os.path.dirname(os.path.abspath(out)), '_frame.png')
    anim = combo.COMBO
    n = int(round(anim.length * fps))
    frames = []
    for i in range(n + 1):
        t = i / fps
        rig.pose(anims.dir_transforms(anim.at(t)))
        pair = []
        for eye, look in views:
            cam.location = eye
            cam.rotation_euler = (Vector(look) - Vector(eye)).to_track_quat('-Z', 'Y').to_euler()
            shoot(scene, tmp)
            pair.append(Image.open(tmp).convert('RGB'))
        im = Image.new('RGB', (size * 2, size), (0, 0, 0))
        im.paste(pair[0], (0, 0))
        im.paste(pair[1], (size, 0))
        frames.append(im)
        print('frame', i, '/', n, flush=True)
    def label(im, text):
        im = im.copy()
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 150, 22], fill=(0, 0, 0))
        d.text((8, 5), text, fill=(255, 255, 255))
        return im
    w = imageio_ffmpeg.write_frames(out, (size * 2, size), fps=30, macro_block_size=1,
                                    output_params=['-crf', '18', '-pix_fmt', 'yuv420p'])
    w.send(None)
    for im in frames[::2]:
        w.send(label(im, 'REAL SPEED').tobytes())
    for _ in range(15):
        w.send(label(frames[-1], 'REAL SPEED').tobytes())
    for im in frames:
        w.send(label(im, '1/2 SPEED').tobytes())
    w.close()
    print('saved', out)


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'poses':
        pose_sheet(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'new')
    elif mode == 'video':
        video(sys.argv[2])
