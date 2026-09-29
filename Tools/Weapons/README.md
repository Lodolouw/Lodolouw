# The weapons' 3D models (Blender)

Every weapon is built out of little cubes (0.1 studs each) in Python, then
Blender turns it into a Roblox-ready model. No textures: one mesh per colour,
and the game colours each mesh itself.

- `voxel.py` - the cube toolkit: boxes, cylinders, tubes, blobs, outlines,
  painting and mirroring, plus **weapon space** (how every weapon is built: the
  grip at the origin, +Z up to the tip, -Y the cutting edge) and `Mat` (a
  colour with its Roblox material, see-through-ness and ROLE: `metal` turns
  gold when the weapon is awakened, `glow` is Neon and colours the smear).
- `kit.py` - shared parts: the palette, grips, blades, drips, bubbles, eyes,
  edges.
- `packs/<pack>.py` - each pack's weapons, one function each. **Only the Slime
  pack is being made for now** (Goo Gloves, Jellyblade, Gelatin Hammer, Ooze
  Daggers, Acid Scythe, Gelatinous Edge); the other four launch packs are
  drafts in `packs/later` (see its README to bring one in).
- `make_models.py` - builds every pack's weapons, exports each one as a model,
  renders a sheet of each pack and writes the list the game reads.
- `make_weapons.py` + `sprites.py` - the older pixel-sprite swords (Iron
  Warden, Ember Cleaver, Tidefang, Voidstar), in `out/`.

```
python3 make_models.py                    # everything (needs Blender's Python module: pip install bpy, Python 3.11)
python3 make_models.py --only GooGloves   # just one weapon
python3 make_models.py --quick            # grainier pictures, much faster (for trying things)
python3 make_models.py --no-render        # models and the list, no pictures
```

What it makes:

- `out/models/<Key>.fbx` - one per weapon: a mesh per material (named after
  it) plus three tiny markers, `GripMark`, `TipMark` and `UpMark`, that tell
  the game exactly how it's held, whatever the importer does to it.
- `Docs/weapons/<pack>.png` - the pack's sheet, to look at.
- `ReplicatedStorage/WeaponModelInfo.lua` - what the game needs to know about
  each model: every mesh's colour, material, see-through-ness and role, its
  size, glow and where its smear runs. Generated: don't edit it by hand.

It warns when a weapon comes out much bigger than its type's blocky stand-in
(`TYPE_SIZE` in `voxel.py`: a katana about 5.6 studs above the grip, daggers
2.55...), since the swings were made for those sizes.

## Into the game

1. **Upload them** with `Tools/Upload/upload_assets.bat` (double-click it on
   Windows; see `Tools/Upload/README.md`). It uploads the models and the
   abilities' animations in one go, then copies all their IDs to your
   clipboard. Paste them to Claude, and they go into
   `ReplicatedStorage/AssetIds.lua`.
2. **The server loads them** when the game starts
   (`ServerScriptService/WeaponModelLoader`) into ReplicatedStorage >
   WeaponModels. Only models owned by the game's owner load, so upload them
   with that account.
3. **Every screen holds them** (`ReplicatedStorage/WeaponFX`, "buildVoxel"):
   lined up by the markers (which are then removed), scaled back to true size,
   coloured from the list, one in each hand for gauntlets and daggers, metal
   gone gold when awakened. Until a model arrives, the weapon is the blocky one
   made in code, and the real one swaps in the moment it's there.

Or by hand: import an `.fbx` with Studio's 3D Importer into ReplicatedStorage >
WeaponModels (a Folder), named after its weapon key (`GooGloves`...). The
loader leaves models that are already there alone.

Test: `Tools/HeadlessTests/test_voxelhold.luau` (a model imported turned and
scaled any old way is still held exactly where the markers say).
