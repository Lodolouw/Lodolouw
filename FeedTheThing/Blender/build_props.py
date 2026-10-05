"""
Feed the Thing in the Basement - props made in Blender: the seed delivery
truck and the seed package it throws onto your lawn.

Run:  blender --background --python build_props.py   (or: python build_props.py)
Writes Props.blend, Export/FeedTheThing_Props.fbx and Previews/props_*.jpg.

Every prop is a set of objects named <Prop>_<Part> plus two marker blocks,
<Prop>_Origin (the prop's base, at its centre) and <Prop>_MarkX (10 studs
along +X). The game (ReplicatedStorage/Assets.lua) uses the markers to put
each prop together at the right size, whatever the import did. Props face
-Z (Roblox's "forward"). Shares the palette and helpers with build_map.py.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402

import build_map as K  # noqa: E402
from build_map import at, new_mesh  # noqa: E402

RENDER = "--no-render" not in sys.argv


def markers(name, ox):
    o = new_mesh(f"{name}_Origin")
    o.box(at(ox, 0, 0), (0.2, 0.2, 0.2), "white")
    x = new_mesh(f"{name}_MarkX")
    x.box(at(ox + 10, 0, 0), (0.2, 0.2, 0.2), "white")


def build_truck(ox):
    """A chunky cartoon box truck, about 12 studs long. Front = -Z."""
    o = at(ox, 0, 0)
    body = new_mesh("Truck_Body")
    # chassis and the red cab with a rounded nose
    body.box(o * at(0, 1.9, 0.3), (5.4, 0.9, 11.2), "tire")
    body.box(o * at(0, 4.3, -3.8), (6, 4.8, 3.8), "truck_red", keys={"top": "truck_red_dark"})
    body.blob(o * at(0, 3.1, -5.5), (5.9, 2.8, 1.8), "truck_red", detail=1)
    body.box(o * at(0, 5.2, -5.72), (4.8, 2.0, 0.3), "glass")
    for sx in (-1, 1):
        body.box(o * at(sx * 3.02, 5.2, -3.7), (0.15, 1.9, 2.6), "glass")
        body.box(o * at(sx * 3.05, 3.0, -3.8), (0.3, 0.6, 3.4), "truck_red_dark")  # front wheel arch
        body.box(o * at(sx * 3.15, 2.9, 3.6), (0.3, 0.6, 3.4), "truck_red_dark")  # back wheel arch
        body.box(o * at(sx * 3.3, 5.6, -2.4), (0.5, 0.9, 0.3), "chrome")  # mirrors
    body.box(o * at(0, 1.6, -6.25), (6.4, 0.9, 0.8), "chrome")  # bumper
    body.box(o * at(0, 2.75, -6.35), (3.0, 1.0, 0.25), "hub")  # grille
    body.box(o * at(0, 6.95, -3.8), (2.4, 0.5, 1.0), "roof_light")
    # the cargo box: cream, green stripe, SEEDS on both sides, doors at the back
    body.box(o * at(0, 5.0, 2.4), (6.2, 6.0, 7.6), "cargo")
    for sx in (-1, 1):
        body.box(o * at(sx * 3.13, 2.65, 2.4), (0.08, 0.7, 7.6), "cargo_stripe")
        body.box(o * at(sx * 3.13, 7.65, 2.4), (0.08, 0.7, 7.6), "cargo_stripe")
    body.box(o * at(0, 5.0, 6.23), (0.15, 5.4, 0.08), "hub")
    for sx in (-1.6, 1.6):
        body.box(o * at(sx, 4.6, 6.25), (0.3, 1.4, 0.1), "chrome")  # door handles
    for sx in (-2.6, 2.6):
        body.box(o * at(sx, 2.4, 6.3), (0.8, 0.5, 0.2), "flag_red")  # tail lights
    letters = new_mesh("Truck_Letters")
    for sx in (-1, 1):
        side = o * at(sx * 3.12, 0, 2.4, -sx * math.pi / 2)  # the frame's -Z faces out of this side
        letters.text(side * at(0, 4.4, -0.05), "SEEDS", 1.9, 0.3, "truck_red")
        # a tomato logo above the letters
        letters.blob(side * at(0, 6.6, -0.1), (1.6, 1.4, 0.4), "tomato", detail=1)
        letters.blob(side * at(0, 7.35, -0.15), (0.8, 0.25, 0.3), "leafy", detail=1)
    # four wheels, each its own object so the game can spin them
    for name, (wx, wz) in {"FL": (-2.85, -3.8), "FR": (2.85, -3.8), "BL": (-2.95, 3.6), "BR": (2.95, 3.6)}.items():
        wheel = new_mesh(f"Truck_Wheel{name}")
        axle = o * at(wx, 1.55, wz) * at(0, 0, 0, 0, 0, math.pi / 2)  # cylinder axis along X
        wheel.cylinder(axle * at(0, -0.55, 0), 1.55, 1.1, "tire", sides=14, top=True, bottom=True)
        wheel.cylinder(axle * at(0, -0.62, 0), 0.75, 1.24, "hub", sides=10, top=True, bottom=True)
        wheel.cylinder(axle * at(0, -0.68, 0), 0.25, 1.36, "chrome", sides=8, top=True, bottom=True)
    glow = new_mesh("Truck_Glow_FFF2C0")
    for sx in (-2.1, 2.1):
        glow.blob(o * at(sx, 3.0, -6.15), (1.1, 0.9, 0.5), "white", detail=1)
    markers("Truck", ox)


def build_package(ox):
    """The cardboard seed package (about 2.6 studs). Front = -Z."""
    o = at(ox, 0, 0)
    box = new_mesh("Package_Box")
    box.box(o * at(0, 1.2, 0), (2.6, 2.4, 2.6), "cardboard", keys={"top": "cardboard"})
    box.box(o * at(0, 2.42, 0), (2.62, 0.05, 0.6), "tape")
    for sz in (-1, 1):
        box.box(o * at(0, 1.8, sz * 1.31), (0.6, 1.25, 0.04), "tape")
    box.box(o * at(0, 2.43, 0), (0.06, 0.06, 2.62), "cardboard_dark")  # the flap seam
    for sx in (-1, 1):  # a sprout on the sides
        side = o * at(sx * 1.31, 0, 0, -sx * math.pi / 2)
        box.blob(side * at(-0.25, 1.15, -0.02), (0.55, 0.3, 0.1), "cargo_stripe", detail=0)
        box.blob(side * at(0.25, 1.3, -0.02), (0.55, 0.3, 0.1), "cargo_stripe", detail=0)
        box.box(side * at(0, 0.8, -0.02), (0.12, 0.7, 0.05), "leafy")
    markers("Package", ox)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    K.setup_scene()
    textures = {"palette": K.save_palette()}
    build_truck(0)
    build_package(30)
    # a bit of ground for the previews
    floor = new_mesh("PreviewFloor", texture="studs_lawn", tile=8)
    floor.box(at(15, -0.25, 0), (80, 0.5, 40), faces={"top"})
    textures["studs_lawn"] = K.stud_texture("studs_lawn", (135, 225, 55))
    print("Objects:")
    K.build_objects(textures)
    floor_obj = bpy.data.objects["PreviewFloor"]
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(K.HERE, "Props.blend"))
    # export everything except the preview floor
    for obj in bpy.data.objects:
        obj.select_set(obj.type == "MESH" and obj != floor_obj)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(K.EXPORT_DIR, "FeedTheThing_Props.fbx"),
        use_selection=True, object_types={"MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_NONE", global_scale=1.0,
        axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True,
    )
    print("Exported FeedTheThing_Props.fbx")
    if RENDER:
        K.render_preview("props_truck", (-13, 9, -14), (0, 3.5, 0), lens=35)
        K.render_preview("props_truck_side", (16, 6, 6), (0, 4, 1), lens=35)
        K.render_preview("props_package", (25, 4, -5), (30, 1.2, 0), lens=45)


if __name__ == "__main__":
    main()
