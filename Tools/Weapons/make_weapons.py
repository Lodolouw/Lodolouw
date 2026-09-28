"""Turns the weapons' pixel sprites (sprites.py) into 3D models with Blender,
exports them for Roblox Studio's 3D Importer, and renders a preview.

    <python with Blender's bpy module> make_weapons.py [--no-render]

(Blender's Python module: `pip install bpy` - it needs the Python version
Blender was built for, 3.11 for Blender 5.0.)

How a sprite becomes a model: every pixel becomes a block, 0.1 studs square,
as thick as what it's made of (PALETTE's role in sprites.py): a blade is
lens-shaped - thin at its edges, thickest down its middle - and the guard,
grip and pommel are chunky, so it reads as a real object from the side but
keeps the 8-bit look. Faces hidden between blocks are left out. Each weapon
is two meshes: <Name> (everything that doesn't glow, coloured by a small
palette texture) and <Name>Glow (the glowing pixels, one colour per face, for
the game to make Neon). Out:
    out/<Name>.fbx        both meshes, for Studio's 3D Importer (Avatar ->
                          Import 3D, or File -> Import 3D)
    out/palette.png       the colours (embedded in the .fbx as well)
    ../../Docs/weapons_preview.png   the four weapons, rendered
"""
import os
import sys
import math

import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sprites import PALETTE, WEAPONS  # noqa: E402

OUT = os.path.join(HERE, 'out')
PREVIEW = os.path.join(HERE, '..', '..', 'Docs', 'weapons_preview.png')
PIXEL = 0.1  # studs per pixel
# thickness by role, in pixels (a blade's roles are shaped further: see depth())
THICK = {'edge': 0.45, 'body': 1.0, 'fuller': 0.7, 'glow': 1.05, 'guard': 1.9,
         'grip': 1.35, 'pommel': 1.8, 'gem': 2.0, 'glowgem': 2.0}
BLADE_ROLES = ('edge', 'body', 'fuller', 'glow')

os.makedirs(OUT, exist_ok=True)

# ----------------------------------------------------------------------
# the palette texture: every colour a 4 x 4 square in one row, so a face's
# UVs can all sit in the middle of its colour (no bleeding between colours)
# ----------------------------------------------------------------------
CHARS = sorted(PALETTE)
CELL = 4
TEX_W, TEX_H = CELL * len(CHARS), CELL


def palette_image():
    img = bpy.data.images.new('WeaponPalette', TEX_W, TEX_H, alpha=False)
    px = [0.0] * (TEX_W * TEX_H * 4)
    for i, ch in enumerate(CHARS):
        r, g, b = PALETTE[ch][1]
        # (an 8-bit image holds sRGB values, just as the palette is written)
        for y in range(TEX_H):
            for x in range(i * CELL, (i + 1) * CELL):
                k = (y * TEX_W + x) * 4
                px[k:k + 4] = [r / 255, g / 255, b / 255, 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(OUT, 'palette.png')
    img.file_format = 'PNG'
    img.save()
    return img


def uv_of(ch):
    i = CHARS.index(ch)
    return ((i * CELL + CELL / 2) / TEX_W, 0.5)


# ----------------------------------------------------------------------
# thickness: a blade thin at its edges, thickest down its middle
# ----------------------------------------------------------------------
def depth(grid, x, y):
    ch = grid[y][x]
    role = PALETTE[ch][2]
    d = THICK[role]
    if role in BLADE_ROLES:
        row = grid[y]
        # how far this pixel is from the blade's side, along its row
        left = 0
        while x - left - 1 >= 0 and row[x - left - 1] != '.' and PALETTE[row[x - left - 1]][2] in BLADE_ROLES:
            left += 1
        right = 0
        while x + right + 1 < len(row) and row[x + right + 1] != '.' and PALETTE[row[x + right + 1]][2] in BLADE_ROLES:
            right += 1
        inner = min(left, right)
        d = d * (0.5 + 0.5 * min(1.0, inner / 2.5))
    return d * PIXEL


def build_mesh(name, grid, want_glow):
    """the blocks for the pixels that glow (want_glow) or don't, faces between
    touching blocks left out where the neighbour covers them"""
    h, w = len(grid), len(grid[0])
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new('UVMap')
    col_layer = bm.loops.layers.color.new('Col')
    glowing = lambda ch: PALETTE[ch][2] in ('glow', 'glowgem')
    D = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if grid[y][x] != '.':
                D[y][x] = depth(grid, x, y)

    def same_set(x, y):
        if 0 <= x < w and 0 <= y < h and grid[y][x] != '.':
            return glowing(grid[y][x]) == want_glow
        return False

    cx = w / 2
    for y in range(h):
        for x in range(w):
            ch = grid[y][x]
            if ch == '.' or glowing(ch) != want_glow:
                continue
            d = D[y][x] / 2
            # studs: x across, z up (the tip at the top), y through its thickness
            x0, x1 = (x - cx) * PIXEL, (x + 1 - cx) * PIXEL
            z1, z0 = (h - y) * PIXEL, (h - y - 1) * PIXEL
            faces = [
                # front and back always show (the neighbours may be thinner)
                ((x0, -d, z0), (x1, -d, z0), (x1, -d, z1), (x0, -d, z1)),
                ((x1, d, z0), (x0, d, z0), (x0, d, z1), (x1, d, z1)),
            ]
            # the four sides: left out when a neighbour at least as thick covers them
            for (nx, ny, quad) in (
                (x - 1, y, ((x0, d, z0), (x0, -d, z0), (x0, -d, z1), (x0, d, z1))),
                (x + 1, y, ((x1, -d, z0), (x1, d, z0), (x1, d, z1), (x1, -d, z1))),
                (x, y - 1, ((x0, -d, z1), (x1, -d, z1), (x1, d, z1), (x0, d, z1))),
                (x, y + 1, ((x0, d, z0), (x1, d, z0), (x1, -d, z0), (x0, -d, z0))),
            ):
                if same_set(nx, ny) and D[ny][nx] / 2 >= d - 1e-6:
                    continue
                faces.append(quad)
            u, v = uv_of(ch)
            r, g, b = PALETTE[ch][1]
            lin = ((r / 255) ** 2.2, (g / 255) ** 2.2, (b / 255) ** 2.2, 1.0)
            for quad in faces:
                verts = [bm.verts.new(p) for p in quad]
                f = bm.faces.new(verts)
                for loop in f.loops:
                    loop[uv_layer].uv = (u, v)
                    loop[col_layer] = lin
    if len(bm.faces) == 0:
        bm.free()
        return None
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ----------------------------------------------------------------------
# materials: the palette (what gets exported), and a glowing one for renders
# ----------------------------------------------------------------------
def material_palette(img):
    m = bpy.data.materials.new('WeaponPalette')
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55
    bsdf.inputs['Metallic'].default_value = 0.15
    return m


def material_glow(img):
    m = bpy.data.materials.new('WeaponGlow')
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = 1.6
    return m


def main():
    render = '--no-render' not in sys.argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    img = palette_image()
    mat, glow = material_palette(img), material_glow(img)
    made = []
    for key, title, fn in WEAPONS:
        grid = fn()
        body = build_mesh(key, grid, False)
        shine = build_mesh(key + 'Glow', grid, True)
        body.data.materials.append(mat)
        if shine:
            shine.data.materials.append(glow)
        # export just this weapon (both meshes)
        bpy.ops.object.select_all(action='DESELECT')
        for ob in (body, shine):
            if ob:
                ob.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(OUT, key + '.fbx'), use_selection=True, object_types={'MESH'},
            path_mode='COPY', embed_textures=True, mesh_smooth_type='FACE', add_leaf_bones=False,
            axis_forward='-Z', axis_up='Y')
        h = len(grid) * PIXEL
        made.append((key, title, body, shine, h))
        print('made', key, 'faces', len(body.data.polygons) + (len(shine.data.polygons) if shine else 0),
              'height %.1f studs' % h)
    if render:
        render_preview(scene, made)


def render_preview(scene, made):
    # stand them in a row, turned a little so their thickness shows
    gap = 2.6
    for i, (key, title, body, shine, h) in enumerate(made):
        for ob in (body, shine):
            if ob:
                ob.location = ((i - (len(made) - 1) / 2) * gap, 0, 0)
                ob.rotation_euler = (0, 0, math.radians(-28))
    tallest = max(m[4] for m in made)
    cam_data = bpy.data.cameras.new('Cam')
    cam_data.lens = 50
    cam = bpy.data.objects.new('Cam', cam_data)
    scene.collection.objects.link(cam)
    cam.location = (1.2, -17.5, tallest * 0.62)
    cam.rotation_euler = (math.radians(88), 0, math.radians(4))
    scene.camera = cam
    # light: a warm key sun from the front left, a cool rim sun from behind,
    # a soft fill from the right (suns: the same strength wherever they are)
    for name, rot, strength, color in (
        ('Key', (50, 0, -35), 3.2, (1.0, 0.94, 0.86)),
        ('Rim', (60, 0, 160), 4.0, (0.55, 0.72, 1.0)),
        ('Fill', (80, 0, 60), 0.9, (0.85, 0.88, 1.0)),
    ):
        ld = bpy.data.lights.new(name, 'SUN')
        ld.energy = strength
        ld.color = color
        ld.angle = math.radians(8)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)
    world = bpy.data.worlds.new('World')
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.05, 0.055, 0.09, 1)
    bg.inputs['Strength'].default_value = 1.0
    # a floor to catch the glow
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.02))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new('Floor')
    try:
        fm.use_nodes = True
    except Exception:
        pass
    fb = fm.node_tree.nodes.get('Principled BSDF')
    fb.inputs['Base Color'].default_value = (0.05, 0.05, 0.075, 1)
    fb.inputs['Roughness'].default_value = 0.35
    floor.data.materials.append(fm)
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 64
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.filepath = os.path.abspath(PREVIEW)
    scene.render.image_settings.file_format = 'PNG'
    try:
        scene.view_settings.view_transform = 'AgX'
    except Exception:
        pass
    bpy.ops.render.render(write_still=True)
    print('rendered', os.path.abspath(PREVIEW))


if __name__ == '__main__':
    main()
