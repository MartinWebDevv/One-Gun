"""Generate the three One Gun menu-hub backdrop renders.

Run with Blender in background mode:
    blender --background --python tools/blender/generate_menu_hub_backdrops.py

The .blend source contains one scene per menu. Runtime only needs the three
PNG renders, keeping the full-screen presentation inexpensive on Low.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "UI" / "assets" / "menu_hubs"
SOURCE_DIR = ROOT / "art_src" / "menu_hubs"
BLEND_PATH = SOURCE_DIR / "one_gun_menu_hubs.blend"

WIDTH = 1600
HEIGHT = 900


def material(name: str, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if emission_input is not None:
            emission_input.default_value = (*emission, 1.0)
        strength_input = bsdf.inputs.get("Emission Strength")
        if strength_input is not None:
            strength_input.default_value = strength
    return mat


def set_mat(obj, mat):
    obj.data.materials.append(mat)
    return obj


def box(scene, name, location, dimensions, mat, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_mat(obj, mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft machined edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    scene.collection.objects.link(obj) if obj.name not in scene.collection.objects else None
    return obj


def cylinder(scene, name, location, radius, depth, mat, rotation=(math.pi / 2, 0.0, 0.0), vertices=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    set_mat(obj, mat)
    return obj


def sphere(scene, name, location, radius, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    set_mat(obj, mat)
    return obj


def torus(scene, name, location, major_radius, minor_radius, mat):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=72,
        minor_segments=12,
        location=location,
        rotation=(math.pi / 2, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    set_mat(obj, mat)
    return obj


def star(scene, name, location, outer_radius, inner_radius, mat):
    vertices = []
    for index in range(10):
        angle = math.pi / 2.0 + math.pi * index / 5.0
        radius = outer_radius if index % 2 == 0 else inner_radius
        vertices.append((math.cos(angle) * radius, 0.0, math.sin(angle) * radius))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], [list(range(10))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    scene.collection.objects.link(obj)
    set_mat(obj, mat)
    solidify = obj.modifiers.new("Pressed metal depth", "SOLIDIFY")
    solidify.thickness = 0.10
    bevel = obj.modifiers.new("Rounded star edge", "BEVEL")
    bevel.width = 0.035
    bevel.segments = 2
    return obj


def text_object(scene, name, body, location, size, mat, extrude=0.035):
    curve = bpy.data.curves.new(f"{name}Curve", "FONT")
    curve.body = body
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = 0.008
    obj = bpy.data.objects.new(name, curve)
    obj.location = location
    obj.rotation_euler.x = math.pi / 2.0
    scene.collection.objects.link(obj)
    set_mat(obj, mat)
    return obj


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def area_light(scene, name, location, color, energy, size, target=(0.0, 0.0, 4.0)):
    data = bpy.data.lights.new(name, "AREA")
    data.color = color
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    scene.collection.objects.link(obj)
    look_at(obj, target)
    return obj


def point_light(scene, name, location, color, energy, radius):
    data = bpy.data.lights.new(name, "POINT")
    data.color = color
    data.energy = energy
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    scene.collection.objects.link(obj)
    return obj


def configure_scene(name: str, world_color):
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = 1.0
    scene.render.pixel_aspect_y = 1.0
    scene.render.use_file_extension = True
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.compression = 38
    scene.world = bpy.data.worlds.new(f"{name}World")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (*world_color, 1.0)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.16
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass

    camera_data = bpy.data.cameras.new(f"{name}Camera")
    camera = bpy.data.objects.new(f"{name}Camera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0.0, -20.5, 5.3)
    camera_data.lens = 43.0
    look_at(camera, (0.0, 1.4, 4.6))
    scene.camera = camera
    return scene


NAVY = material("Deep Navy Lacquer", (0.010, 0.020, 0.050), 0.15, 0.34)
NAVY_RAISED = material("Raised Navy Metal", (0.025, 0.050, 0.105), 0.48, 0.26)
BLACK_METAL = material("Blackened Metal", (0.009, 0.012, 0.020), 0.72, 0.25)
GOLD = material("Antique Gold", (0.64, 0.34, 0.055), 0.82, 0.22)
GOLD_DARK = material("Dark Brass", (0.21, 0.095, 0.018), 0.72, 0.34)
GOLD_GLOW = material("Warm Marquee", (0.95, 0.43, 0.055), 0.25, 0.22, (1.0, 0.25, 0.018), 8.0)
CYAN_GLOW = material("Locker Cyan", (0.025, 0.33, 0.78), 0.28, 0.22, (0.015, 0.30, 1.0), 7.0)
BLUE_METAL = material("Locker Blue Metal", (0.018, 0.085, 0.19), 0.68, 0.25)
TEAL = material("Record Hall Teal", (0.018, 0.16, 0.18), 0.55, 0.30)
RED = material("Banner Red", (0.34, 0.025, 0.030), 0.12, 0.48)
CREAM = material("Warm Cream", (0.82, 0.65, 0.32), 0.35, 0.30)
WOOD = material("Prize Booth Wood", (0.13, 0.045, 0.015), 0.0, 0.46)
PURPLE = material("Prize Purple", (0.19, 0.035, 0.32), 0.24, 0.36)


def build_common_room(scene, wall_mat, accent_mat):
    box(scene, "Back wall", (0.0, 3.7, 4.4), (24.0, 0.55, 10.4), wall_mat, 0.10)
    box(scene, "Floor", (0.0, 2.0, -0.35), (25.0, 14.0, 0.70), BLACK_METAL, 0.12)
    box(scene, "Ceiling beam", (0.0, 2.8, 9.05), (24.0, 1.1, 0.55), BLACK_METAL, 0.09)
    for x in (-10.6, -8.1, 8.1, 10.6):
        box(scene, f"Wall rib {x}", (x, 3.22, 4.4), (0.18, 0.28, 9.2), accent_mat, 0.035)
    for x in (-8.6, -4.3, 0.0, 4.3, 8.6):
        box(scene, f"Floor stripe {x}", (x, -0.4, -0.005), (0.075, 8.0, 0.025), accent_mat, 0.0)


def build_prize_counter():
    scene = configure_scene("PrizeCounterBackdrop", (0.004, 0.006, 0.014))
    build_common_room(scene, WOOD, GOLD_DARK)
    box(scene, "Prize canopy", (0.0, 1.75, 8.05), (17.6, 1.2, 0.70), GOLD_DARK, 0.18)
    box(scene, "Prize canopy face", (0.0, 1.05, 7.78), (15.7, 0.18, 0.72), NAVY_RAISED, 0.14)
    text_object(scene, "Prize ghost lettering", "PRIZE COUNTER", (0.0, 0.92, 7.83), 0.72, GOLD, 0.022)

    for index in range(17):
        x = -7.55 + index * 0.945
        sphere(scene, f"Marquee bulb {index}", (x, 0.73, 8.28), 0.105, GOLD_GLOW)
    for x in (-9.4, 9.4):
        box(scene, f"Prize pillar {x}", (x, 2.0, 4.15), (0.82, 1.05, 8.0), GOLD_DARK, 0.16)
        for z in (1.0, 2.45, 3.9, 5.35, 6.8):
            sphere(scene, f"Pillar bulb {x} {z}", (x, 1.32, z), 0.095, GOLD_GLOW)

    # Deep shelves and toy-like prize silhouettes sit at the edges so the UI
    # can occupy the center without fighting the backdrop.
    for side in (-1, 1):
        center_x = side * 8.15
        box(scene, f"Shelf case {side}", (center_x, 2.65, 4.05), (3.7, 1.0, 6.65), NAVY, 0.14)
        for z in (1.45, 3.25, 5.05, 6.85):
            box(scene, f"Shelf lip {side} {z}", (center_x, 1.94, z), (3.45, 0.22, 0.16), GOLD, 0.025)
        star(scene, f"Prize star {side}", (center_x - side * 0.72, 1.76, 5.82), 0.58, 0.25, GOLD)
        sphere(scene, f"Prize ball {side}", (center_x + side * 0.72, 1.72, 5.70), 0.47, PURPLE if side < 0 else BLUE_METAL)
        cylinder(scene, f"Prize token {side}", (center_x, 1.69, 2.45), 0.58, 0.16, GOLD)
        text_object(scene, f"Token OG {side}", "OG", (center_x, 1.56, 2.45), 0.34, NAVY, 0.012)

    box(scene, "Counter base", (0.0, 1.0, 0.68), (15.9, 2.15, 1.25), NAVY_RAISED, 0.20)
    box(scene, "Counter gold rail", (0.0, -0.10, 1.27), (16.5, 0.24, 0.20), GOLD, 0.05)
    star(scene, "Counter crest", (0.0, -0.27, 0.72), 0.52, 0.22, GOLD)
    area_light(scene, "Prize warm wash", (-4.5, -5.5, 8.0), (1.0, 0.38, 0.08), 930.0, 5.5)
    area_light(scene, "Prize cool fill", (6.5, -2.0, 5.2), (0.16, 0.32, 0.72), 560.0, 4.5)
    point_light(scene, "Prize marquee glow", (0.0, -0.2, 8.15), (1.0, 0.28, 0.035), 620.0, 1.2)
    return scene


def build_locker():
    scene = configure_scene("LockerBackdrop", (0.002, 0.008, 0.020))
    build_common_room(scene, BLUE_METAL, CYAN_GLOW)
    for side in (-1, 1):
        for index in range(3):
            x = side * (7.6 + index * 1.15)
            box(scene, f"Locker door {side} {index}", (x, 2.92, 4.05), (0.98, 0.58, 7.25), NAVY_RAISED, 0.095)
            for vent in range(4):
                box(scene, f"Locker vent {side} {index} {vent}", (x, 2.56, 6.20 - vent * 0.16), (0.58, 0.035, 0.045), CYAN_GLOW, 0.01)
            box(scene, f"Locker handle {side} {index}", (x + side * -0.28, 2.48, 3.65), (0.07, 0.05, 0.52), GOLD, 0.018)

    torus(scene, "Loadout halo outer", (-3.4, 2.70, 4.25), 3.15, 0.085, CYAN_GLOW)
    torus(scene, "Loadout halo inner", (-3.4, 2.64, 4.25), 2.72, 0.035, GOLD_GLOW)
    cylinder(scene, "Loadout platform", (-3.4, 1.55, 0.55), 2.65, 0.70, BLUE_METAL, rotation=(0.0, 0.0, 0.0))
    cylinder(scene, "Platform light ring", (-3.4, 1.47, 0.94), 2.42, 0.12, CYAN_GLOW, rotation=(0.0, 0.0, 0.0))
    star(scene, "Loadout star", (-3.4, 1.36, 0.97), 0.62, 0.27, GOLD)

    box(scene, "Armory rail", (4.5, 2.62, 6.75), (5.7, 0.25, 0.20), GOLD_DARK, 0.05)
    for x in (2.3, 3.75, 5.20, 6.65):
        box(scene, f"Gear hanger {x}", (x, 2.47, 4.75), (0.08, 0.08, 3.85), CYAN_GLOW, 0.015)
        box(scene, f"Gear plate {x}", (x, 2.32, 4.45), (0.78, 0.22, 1.18), NAVY_RAISED, 0.09)
    text_object(scene, "Locker ghost mark", "LOADOUT  /  OG", (3.95, 2.18, 7.55), 0.46, CREAM, 0.018)
    area_light(scene, "Locker key", (-4.0, -4.0, 7.7), (0.18, 0.48, 1.0), 850.0, 5.0)
    area_light(scene, "Locker warm rim", (5.8, -2.5, 6.0), (1.0, 0.48, 0.12), 500.0, 4.0)
    point_light(scene, "Locker halo fill", (-3.4, 0.0, 4.2), (0.04, 0.34, 1.0), 530.0, 1.4)
    return scene


def build_profile():
    scene = configure_scene("ProfileBackdrop", (0.004, 0.007, 0.015))
    build_common_room(scene, NAVY, GOLD_DARK)
    box(scene, "Record hall arch", (0.0, 2.55, 8.05), (16.8, 0.65, 0.55), GOLD_DARK, 0.18)
    torus(scene, "Record crest ring", (-4.5, 2.78, 4.8), 2.65, 0.11, GOLD)
    star(scene, "Record crest star", (-4.5, 2.58, 4.8), 1.48, 0.63, GOLD)
    text_object(scene, "Record crest OG", "OG", (-4.5, 2.39, 2.65), 0.70, CREAM, 0.03)

    for side in (-1, 1):
        x = side * 8.7
        box(scene, f"Hall banner {side}", (x, 2.86, 5.2), (2.0, 0.20, 6.7), RED if side < 0 else BLUE_METAL, 0.10)
        star(scene, f"Banner star {side}", (x, 2.70, 5.6), 0.74, 0.31, GOLD)
        box(scene, f"Banner point {side}", (x, 2.82, 1.88), (1.25, 0.18, 0.52), GOLD_DARK, 0.06)

    # A shallow trophy archive on the right reads clearly through gaps around
    # the Profile panels without requiring transparent glass or particles.
    for column in range(3):
        x = 2.5 + column * 2.1
        box(scene, f"Archive case {column}", (x, 2.92, 4.25), (1.65, 0.42, 5.45), TEAL, 0.11)
        box(scene, f"Archive rim top {column}", (x, 2.60, 6.85), (1.70, 0.14, 0.12), GOLD, 0.03)
        cylinder(scene, f"Trophy stem {column}", (x, 2.53, 3.25), 0.14, 1.15, GOLD, rotation=(0.0, 0.0, 0.0), vertices=32)
        cylinder(scene, f"Trophy base {column}", (x, 2.53, 2.55), 0.52, 0.18, GOLD_DARK, rotation=(0.0, 0.0, 0.0), vertices=48)
        sphere(scene, f"Trophy cup {column}", (x, 2.53, 4.0), 0.48, GOLD)
        star(scene, f"Archive medal {column}", (x, 2.39, 5.55), 0.42, 0.18, GOLD)

    for index in range(11):
        x = -7.25 + index * 1.45
        sphere(scene, f"Hall light {index}", (x, 1.15, 8.25), 0.085, GOLD_GLOW)
    text_object(scene, "Profile ghost title", "COMPETITOR RECORDS", (3.95, 2.26, 7.62), 0.42, CREAM, 0.018)
    area_light(scene, "Profile gold key", (-4.4, -4.2, 7.8), (1.0, 0.45, 0.10), 850.0, 5.0)
    area_light(scene, "Profile teal fill", (5.5, -3.2, 6.5), (0.04, 0.42, 0.55), 570.0, 4.2)
    point_light(scene, "Profile crest glow", (-4.5, 0.2, 4.8), (1.0, 0.32, 0.04), 480.0, 1.5)
    return scene


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Materials are recreated after factory reset.
    global NAVY, NAVY_RAISED, BLACK_METAL, GOLD, GOLD_DARK, GOLD_GLOW
    global CYAN_GLOW, BLUE_METAL, TEAL, RED, CREAM, WOOD, PURPLE
    NAVY = material("Deep Navy Lacquer", (0.010, 0.020, 0.050), 0.15, 0.34)
    NAVY_RAISED = material("Raised Navy Metal", (0.025, 0.050, 0.105), 0.48, 0.26)
    BLACK_METAL = material("Blackened Metal", (0.009, 0.012, 0.020), 0.72, 0.25)
    GOLD = material("Antique Gold", (0.64, 0.34, 0.055), 0.82, 0.22)
    GOLD_DARK = material("Dark Brass", (0.21, 0.095, 0.018), 0.72, 0.34)
    GOLD_GLOW = material("Warm Marquee", (0.95, 0.43, 0.055), 0.25, 0.22, (1.0, 0.25, 0.018), 8.0)
    CYAN_GLOW = material("Locker Cyan", (0.025, 0.33, 0.78), 0.28, 0.22, (0.015, 0.30, 1.0), 7.0)
    BLUE_METAL = material("Locker Blue Metal", (0.018, 0.085, 0.19), 0.68, 0.25)
    TEAL = material("Record Hall Teal", (0.018, 0.16, 0.18), 0.55, 0.30)
    RED = material("Banner Red", (0.34, 0.025, 0.030), 0.12, 0.48)
    CREAM = material("Warm Cream", (0.82, 0.65, 0.32), 0.35, 0.30)
    WOOD = material("Prize Booth Wood", (0.13, 0.045, 0.015), 0.0, 0.46)
    PURPLE = material("Prize Purple", (0.19, 0.035, 0.32), 0.24, 0.36)

    original = bpy.context.scene
    scenes = [
        (build_prize_counter(), OUTPUT_DIR / "prize_counter_backdrop.png"),
        (build_locker(), OUTPUT_DIR / "locker_backdrop.png"),
        (build_profile(), OUTPUT_DIR / "profile_backdrop.png"),
    ]
    # Blender refuses to remove the final scene, so keep the factory scene
    # until all three authored scenes exist.
    bpy.data.scenes.remove(original)
    for scene, output in scenes:
        bpy.context.window.scene = scene
        scene.render.filepath = str(output)
        bpy.ops.render.render(write_still=True)
        print(f"Rendered {scene.name}: {output}")

    bpy.context.window.scene = scenes[0][0]
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"Saved editable source: {BLEND_PATH}")


if __name__ == "__main__":
    main()
