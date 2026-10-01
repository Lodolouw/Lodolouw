"""Makes the voxel weapons (packs/*.py, built with voxel.py) into Roblox models
with Blender, renders a preview of each pack, and writes the list the game
reads (ReplicatedStorage/WeaponModelInfo.lua).

    python3 make_models.py                      every pack: models, previews, list
    python3 make_models.py --pack Slime         just one pack (the list is always all)
    python3 make_models.py --only GooGloves     just one weapon
    python3 make_models.py --no-render          models and list, no pictures
    python3 make_models.py --quick              quick, grainier pictures (for trying things)

(Blender's Python module: `pip install bpy` - Blender 4.2 needs Python 3.11.)

Out:
    out/models/<Key>.fbx      one per weapon: a mesh per material + three tiny
                              markers (GripMark, TipMark, UpMark) that tell the
                              game exactly how it's held. Uploaded by
                              Tools/Upload/upload_assets.bat (Open Cloud) - or
                              import one by hand with Studio's 3D Importer into
                              ReplicatedStorage > WeaponModels (a Folder).
    out/tiles/<Key>.png       each weapon on its own
    ../../Docs/weapons/<pack>.png   each pack's sheet
    ../../Docs/weapons/all.png      every weapon (once there's more than one pack)
    ../../ReplicatedStorage/WeaponModelInfo.lua   what the game needs to know
                              about each model: its parts' colours and
                              materials, its smears, its glow
"""
import importlib
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import voxel as V  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'out')
MODELS = os.path.join(OUT, 'models')
TILES = os.path.join(OUT, 'tiles')
DOCS = os.path.join(ROOT, 'Docs', 'weapons')
MANIFEST = os.path.join(ROOT, 'ReplicatedStorage', 'WeaponModelInfo.lua')
# the packs being made (the other launch packs are drafts in packs/later: we're
# doing one pack at a time - see packs/later/README.md)
PACKS = ['slime', 'knight', 'speedway', 'jungle', 'canvas']

RARITY = {
    'Common': (235, 235, 240), 'Rare': (0, 153, 219), 'Epic': (170, 100, 255),
    'Legendary': (254, 174, 52), 'Mythic': (255, 0, 68), 'Secret': (255, 255, 255),
}
TIP, UP, MARK = 1.0, 1.0, 0.08  # where the markers are (studs from the grip) and how big


def load_packs():
    packs = []
    for name in PACKS:
        if not os.path.exists(os.path.join(HERE, 'packs', name + '.py')):
            continue  # (not made yet)
        mod = importlib.import_module('packs.' + name)
        packs.append(mod.PACK)
    return packs


def build(weapon, pack):
    """the voxels, the palette, and the weapon's extras (smear, glow) for one weapon"""
    key, title, kind, rarity, fn = weapon
    vox = V.Voxels()
    mats = dict(pack['palette'])
    extra = fn(vox, mats) or {}
    missing = sorted(set(vox.v.values()) - set(mats))
    if missing:
        raise SystemExit('%s: materials not in its palette: %s' % (key, missing))
    return vox, mats, extra


def check_size(key, kind, vox):
    lo, hi = vox.bounds()
    r = V.RES
    down, up = -(lo[2] - 0.5) * r, (hi[2] + 0.5) * r
    across = max((hi[0] - lo[0] + 1), (hi[1] - lo[1] + 1)) * r
    want = V.TYPE_SIZE[kind]
    notes = []
    if up > want['up'] * 1.25:
        notes.append('tall (%.1f up, a %s is about %.1f)' % (up, kind, want['up']))
    if down > want['down'] * 1.6 + 0.2:
        notes.append('long below the grip (%.1f)' % down)
    if across > want['across'] * 1.35:
        notes.append('wide (%.1f across, a %s is about %.1f)' % (across, kind, want['across']))
    return down, up, across, notes


# ----------------------------------------------------------------------
# the list the game reads
# ----------------------------------------------------------------------
def lua_num(x):
    s = '%.3f' % x
    s = s.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def default_smear(kind, vox):
    """where the smear runs if the weapon doesn't say (weapon space, studs)"""
    lo, hi = vox.bounds()
    r = V.RES
    top = (hi[2] + 0.5) * r
    if kind == 'Hammer':
        # round the head: across its faces (X)
        zc = top - 0.7
        return (((lo[0] - 0.5) * r, 0, zc), ((hi[0] + 0.5) * r, 0, zc))
    if kind == 'Scythe':
        zc = top - 0.5
        return ((0, 0, zc), ((hi[0] + 0.5) * r * 0.95, 0, zc - 0.6))
    if kind == 'Fists':
        return ((0, 0, -0.6), (0, 0, 0.8))
    return ((0, 0, top * 0.28), (0, 0, top))


def manifest_entry(weapon, pack, vox, mats, extra):
    key, title, kind, rarity, fn = weapon
    used = sorted(set(vox.v.values()))
    lo, hi = vox.bounds()
    r = V.RES
    smear = extra.get('smear') or default_smear(kind, vox)
    wide = extra.get('smear_wide') or smear
    glow = extra.get('glow')
    if glow is None:
        for m in used:
            if mats[m].glow:
                glow = mats[m].rgb
                break
    if glow is None:
        glow = pack['accent']
    lines = ['\t%s = {' % key]
    lines.append('\t\tName = "%s", Type = "%s", Pack = "%s", Rarity = "%s",' % (title, kind, pack['id'], rarity))
    lines.append('\t\tTip = %s, Up = %s, -- (the markers: studs from the grip, up the weapon and to its front)' % (lua_num(TIP), lua_num(UP)))
    size = [(hi[i] - lo[i] + 1) * r for i in range(3)]
    lines.append('\t\tSize = { %s, %s, %s }, -- (studs: across X, across Y, its length)' % tuple(lua_num(s) for s in size))
    lines.append('\t\tGlow = { %d, %d, %d },' % tuple(glow))

    def vec(p):
        h = V.to_handle(p)
        return '{ %s, %s, %s }' % tuple(lua_num(c) for c in h)
    lines.append('\t\tSmear = { %s, %s }, -- (the handle\'s own space: -Z up the weapon)' % (vec(smear[0]), vec(smear[1])))
    lines.append('\t\tSmearWide = { %s, %s },' % (vec(wide[0]), vec(wide[1])))
    top = (hi[2] + 0.5) * r
    head = extra.get('head') or ((0, 0, top - 0.7) if kind == 'Hammer' else (0, 0, 0.6) if kind == 'Fists' else (0, 0, top))
    lines.append('\t\tHead = %s, -- (the business end: a hammer\'s head, a blade\'s tip)' % vec(head))
    if extra.get('hold'):
        lines.append('\t\tHold = "%s",' % extra['hold'])
    lines.append('\t\tParts = {')
    for m in used:
        mm = mats[m]
        lines.append('\t\t\t%s = { Color = { %d, %d, %d }, Material = "%s", Transparency = %s, Role = "%s" },' % (
            m, mm.rgb[0], mm.rgb[1], mm.rgb[2], mm.material, lua_num(mm.alpha), mm.role))
    lines.append('\t\t},')
    lines.append('\t},')
    return '\n'.join(lines)


def write_manifest(entries):
    head = [
        '-- GENERATED by Tools/Weapons/make_models.py from Tools/Weapons/packs - change',
        "-- the weapons there and run it again; don't edit this by hand.",
        '--',
        '-- The voxel weapons\' 3D models: each one is a mesh per material (a',
        '-- MeshPart named after it) plus three markers - GripMark (the middle of',
        '-- the grip), TipMark (Tip studs up the weapon) and UpMark (Up studs to',
        '-- its front: the handle\'s +Y) - so the game holds it exactly like the',
        '-- blocky stand-in. The models themselves come in by upload',
        '-- (Tools/Upload/upload_assets.bat: their ids go in ReplicatedStorage/AssetIds,',
        '-- and the server loads them into ReplicatedStorage > WeaponModels) or by',
        '-- hand (Studio\'s 3D Importer, into that WeaponModels folder).',
        '-- Parts: how each mesh is coloured (Role "metal" turns gold when the',
        '-- weapon awakens at mastery 100, "glow" is Neon in the smear\'s colour).',
        'return {',
    ]
    with open(MANIFEST, 'w') as f:
        f.write('\n'.join(head + entries + ['}']) + '\n')
    print('saved', os.path.relpath(MANIFEST, ROOT))


# ----------------------------------------------------------------------
# Blender
# ----------------------------------------------------------------------
def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def blender_material(bpy, mm):
    m = bpy.data.materials.new(mm.key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    col = tuple(srgb_to_lin(c) for c in mm.rgb) + (1.0,)
    bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = 0.5
    if mm.role == 'metal' or mm.material in ('Foil', 'Metal', 'DiamondPlate'):
        bsdf.inputs['Metallic'].default_value = 0.35
        bsdf.inputs['Roughness'].default_value = 0.32
    if mm.glow:
        bsdf.inputs['Emission Color'].default_value = col
        bsdf.inputs['Emission Strength'].default_value = 2.2
    if mm.clear:
        bsdf.inputs['Alpha'].default_value = max(0.15, 1 - mm.alpha)
        try:
            m.blend_method = 'BLEND'
        except Exception:
            pass
    return m


def make_objects(bpy, key, vox, mats):
    quads = V.faces(vox, mats)
    objs = []
    tris = 0
    for mk, qs in sorted(quads.items()):
        verts, polys = [], []
        for q in qs:
            b = len(verts)
            verts.extend(q)
            polys.append((b, b + 1, b + 2, b + 3))
        me = bpy.data.meshes.new(mk)
        me.from_pydata(verts, [], polys)
        me.update()
        me.materials.append(blender_material(bpy, mats[mk]))
        ob = bpy.data.objects.new(mk, me)
        bpy.context.scene.collection.objects.link(ob)
        objs.append(ob)
        tris += 2 * len(polys)
        if 2 * len(polys) > 18000:
            print('  WARNING %s: %s has %d triangles (Roblox allows 20000 a mesh)' % (key, mk, 2 * len(polys)))
    return objs, tris


def make_markers(bpy):
    out = []
    for name, loc in (('GripMark', (0, 0, 0)), ('TipMark', (0, 0, TIP)), ('UpMark', (0, -UP, 0))):
        h = MARK / 2
        x, y, z = loc
        verts = [(x + sx * h, y + sy * h, z + sz * h) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        faces_ = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces_)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        out.append(ob)
    return out


def clear_scene(bpy):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(coll):
            coll.remove(item)


def export_fbx(bpy, key, objs):
    os.makedirs(MODELS, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(MODELS, key + '.fbx')
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={'MESH'},
        mesh_smooth_type='FACE', add_leaf_bones=False, use_mesh_modifiers=False,
        axis_forward='-Z', axis_up='Y')
    return path


# how each type is looked at in its picture (weapon space: a direction to the camera)
VIEW = {
    'Sword': (1.0, -0.42, 0.22), 'Katana': (1.0, -0.42, 0.22), 'Daggers': (1.0, -0.5, 0.3),
    'Hammer': (0.5, -1.0, 0.28), 'Scythe': (0.3, -1.0, 0.22), 'Fists': (0.75, -1.0, 0.55),
}


def setup_render(bpy, quick):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 16 if quick else 64
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.film_transparent = True
    scene.render.resolution_x = 520
    scene.render.resolution_y = 700
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    try:
        scene.view_settings.view_transform = 'Standard'
    except Exception:
        pass
    world = bpy.data.worlds.new('World')
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.35, 0.38, 0.5, 1)
    bg.inputs['Strength'].default_value = 0.45


def render_tile(bpy, key, kind, vox, extra, quick):
    scene = bpy.context.scene
    for name, rot, strength, color in (
        ('Key', (48, 0, -40), 3.4, (1.0, 0.95, 0.88)),
        ('Rim', (62, 0, 150), 2.6, (0.6, 0.75, 1.0)),
        ('Fill', (75, 0, 55), 0.9, (0.9, 0.9, 1.0)),
    ):
        ld = bpy.data.lights.new(name, 'SUN')
        ld.energy = strength
        ld.color = color
        ld.angle = math.radians(6)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)
    # an orthographic camera looking at the middle of it, fitted round it
    lo, hi = vox.bounds()
    r = V.RES
    corners = [((x + s * 0.5) * r, (y + t * 0.5) * r, (z + u * 0.5) * r)
               for x, s in ((lo[0], -1), (hi[0], 1)) for y, t in ((lo[1], -1), (hi[1], 1)) for z, u in ((lo[2], -1), (hi[2], 1))]
    centre = [sum(c[i] for c in corners) / 8 for i in range(3)]
    d = extra.get('view') or VIEW[kind]
    n = math.sqrt(sum(c * c for c in d))
    d = [c / n for c in d]
    cam_data = bpy.data.cameras.new('Cam')
    cam_data.type = 'ORTHO'
    cam = bpy.data.objects.new('Cam', cam_data)
    scene.collection.objects.link(cam)
    import mathutils
    loc = mathutils.Vector(centre) + mathutils.Vector(d) * 30
    cam.location = loc
    look = (mathutils.Vector(centre) - loc).normalized()
    cam.rotation_euler = look.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    # fit: the corners in the camera's view
    inv = cam.matrix_world.inverted()
    pts = [inv @ mathutils.Vector(c) for c in corners]
    w = max(p.x for p in pts) - min(p.x for p in pts)
    h = max(p.y for p in pts) - min(p.y for p in pts)
    aspect = scene.render.resolution_x / scene.render.resolution_y
    # (ortho_scale spans the picture's longer side: here its height)
    cam_data.ortho_scale = max(h, w / aspect, 0.5) * 1.12
    # the middle of the picture on the middle of what's seen
    mid = mathutils.Vector(((max(p.x for p in pts) + min(p.x for p in pts)) / 2, (max(p.y for p in pts) + min(p.y for p in pts)) / 2, 0))
    cam.location = cam.matrix_world @ mathutils.Vector((mid.x, mid.y, 0))
    scene.camera = cam
    os.makedirs(TILES, exist_ok=True)
    path = os.path.join(TILES, key + '.png')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# ----------------------------------------------------------------------
# the sheets
# ----------------------------------------------------------------------
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


def sheet(pack, tiles, path):
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    tw, th = 520, 700
    cols = 3
    rows = (len(tiles) + cols - 1) // cols
    W, H = cols * tw + 60, rows * (th + 70) + 140
    accent = pack['accent']
    img = Image.new('RGB', (W, H), (26, 24, 40))
    d = ImageDraw.Draw(img)
    # a soft glow in the pack's colour behind each weapon
    for i, (weapon, tile) in enumerate(tiles):
        c, r = i % cols, i // cols
        x0, y0 = 30 + c * tw, 110 + r * (th + 70)
        glow = Image.new('RGBA', (tw, th), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse((tw * 0.12, th * 0.12, tw * 0.88, th * 0.88), fill=accent + (70,))
        glow = glow.filter(ImageFilter.GaussianBlur(60))
        img.paste(glow, (x0, y0), glow)
        # the plinth line
        d.rounded_rectangle((x0 + 8, y0 + 4, x0 + tw - 8, y0 + th + 56), radius=18, outline=(58, 54, 84), width=3)
    title_font = ImageFont.truetype(BOLD, 44)
    d.text((W // 2, 56), pack['title'].upper(), font=title_font, fill=(254, 231, 97), anchor='mm')
    name_font = ImageFont.truetype(BOLD, 26)
    small = ImageFont.truetype(BOLD, 18)
    for i, (weapon, tile) in enumerate(tiles):
        key, title, kind, rarity, fn = weapon
        c, r = i % cols, i // cols
        x0, y0 = 30 + c * tw, 110 + r * (th + 70)
        if tile and os.path.exists(tile):
            t = Image.open(tile).convert('RGBA')
            # a shadow under it
            sh = Image.new('RGBA', t.size, (0, 0, 0, 0))
            sh.putalpha(t.split()[3].point(lambda a: int(a * 0.45)))
            sh = sh.filter(ImageFilter.GaussianBlur(10))
            img.paste((10, 8, 20), (x0 + 10, y0 + 14), sh)
            img.paste(t, (x0, y0), t)
        col = RARITY[rarity]
        d.text((x0 + tw // 2, y0 + th + 14), title, font=name_font, fill=(255, 255, 255), anchor='mm')
        d.text((x0 + tw // 2, y0 + th + 42), '%s  %s' % (rarity.upper(), kind.upper()), font=small, fill=col, anchor='mm')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print('saved', os.path.relpath(path, ROOT))


def overview(packs, path):
    from PIL import Image, ImageDraw, ImageFont
    tw, th = 260, 350
    cols = 6
    W = cols * tw + 40
    H = len(packs) * (th + 60) + 110
    img = Image.new('RGB', (W, H), (26, 24, 40))
    d = ImageDraw.Draw(img)
    count = sum(len(p['weapons']) for p in packs)
    d.text((W // 2, 48), 'THE %d WEAPONS SO FAR' % count, font=ImageFont.truetype(BOLD, 40), fill=(254, 231, 97), anchor='mm')
    f = ImageFont.truetype(BOLD, 15)
    for r, pack in enumerate(packs):
        y0 = 100 + r * (th + 60)
        d.text((20, y0 - 4), pack['title'].upper(), font=ImageFont.truetype(BOLD, 20), fill=pack['accent'])
        for c, weapon in enumerate(pack['weapons']):
            key, title, kind, rarity, fn = weapon
            x0 = 20 + c * tw
            tile = os.path.join(TILES, key + '.png')
            if os.path.exists(tile):
                t = Image.open(tile).convert('RGBA').resize((tw, th))
                img.paste(t, (x0, y0 + 18), t)
            d.text((x0 + tw // 2, y0 + th + 24), title, font=f, fill=RARITY[rarity], anchor='mm')
    img.save(path)
    print('saved', os.path.relpath(path, ROOT))


def main():
    args = sys.argv[1:]
    render = '--no-render' not in args
    quick = '--quick' in args
    only = args[args.index('--only') + 1] if '--only' in args else None
    pack_want = args[args.index('--pack') + 1].lower() if '--pack' in args else None
    packs = load_packs()
    entries = []
    todo = []
    for pack in packs:
        for weapon in pack['weapons']:
            vox, mats, extra = build(weapon, pack)
            down, up, across, notes = check_size(weapon[0], weapon[2], vox)
            entries.append(manifest_entry(weapon, pack, vox, mats, extra))
            wanted = (only == weapon[0]) if only else (pack_want is None or pack_want == pack['id'].lower())
            if wanted:
                todo.append((pack, weapon, vox, mats, extra))
                print('%-18s %-8s %5d voxels  %.1f down %.1f up %.1f across %s' % (
                    weapon[0], weapon[2], vox.count(), down, up, across, ('  <- ' + '; '.join(notes)) if notes else ''))
    write_manifest(entries)
    if not todo:
        return
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_render(bpy, quick)
    tiles = {}
    for pack, weapon, vox, mats, extra in todo:
        key = weapon[0]
        clear_scene(bpy)
        objs, tris = make_objects(bpy, key, vox, mats)
        marks = make_markers(bpy)
        export_fbx(bpy, key, objs + marks)
        for mk in marks:
            bpy.data.objects.remove(mk, do_unlink=True)
        print('  %s: %d meshes, %d triangles' % (key, len(objs), tris))
        if render:
            tiles[key] = render_tile(bpy, key, weapon[2], vox, extra, quick)
    if render:
        for pack in packs:
            ws = [(w, tiles.get(w[0]) or os.path.join(TILES, w[0] + '.png')) for w in pack['weapons']]
            if any(w[0] in tiles for w in pack['weapons']):
                sheet(pack, ws, os.path.join(DOCS, pack['id'].lower() + '.png'))
        if len(packs) > 1:
            overview(packs, os.path.join(DOCS, 'all.png'))


if __name__ == '__main__':
    main()
