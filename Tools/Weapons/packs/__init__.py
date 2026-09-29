"""The weapon packs: one file per Arcade Machine pack, each a PACK = {id,
title, accent, palette, weapons}. Each weapon is (key, name, type, rarity,
build) where build(voxels, palette) builds it (see voxel.py for weapon
space) and may return extras: {'smear': (from, to), 'smear_wide': ...,
'glow': (r, g, b), 'view': (x, y, z)} - weapon space, studs."""
