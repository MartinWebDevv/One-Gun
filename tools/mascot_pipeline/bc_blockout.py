"""Build and render the Blue Cat Section 3 proportional blockout in Blender.

Run with Blender, not CPython:
    blender --background --factory-startup --python tools/mascot_pipeline/bc_blockout.py

This intentionally creates separate editable masses.  It does not create a
production topology, UVs, rig, textures, animations, or Godot export.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_DIR = ROOT / "art_src/mascots/blue_cat/blend"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
QA = ROOT / "art_src/mascots/blue_cat/qa"
BLEND_PATH = BLEND_DIR / "BC_Blockout_v001.blend"

VERSION = "v001"
MODEL_OBJECTS: list[bpy.types.Object] = []


def rgba(hex_value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = hex_value.lstrip("#")
    srgb = [int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    channels = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in srgb]
    return (*channels, alpha)


def make_material(name: str, color: tuple[float, float, float, float], roughness: float = 0.62) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = 0.0
    return mat


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    data = getattr(obj, "data", None)
    if data is not None and hasattr(data, "materials"):
        data.materials.clear()
        data.materials.append(material)


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def add_model_object(obj: bpy.types.Object, collection: bpy.types.Collection, material: bpy.types.Material) -> bpy.types.Object:
    move_to_collection(obj, collection)
    assign_material(obj, material)
    MODEL_OBJECTS.append(obj)
    return obj


def ellipsoid(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    segments: int = 64,
    rings: int = 32,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    return add_model_object(obj, collection, material)


def ellipsoid_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius_x: float,
    radius_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    vector = b - a
    obj = ellipsoid(name, tuple((a + b) * 0.5), (radius_x, radius_y, vector.length * 0.56), material, collection, 48, 24)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = vector.to_track_quat("Z", "Y")
    return obj


def rounded_wedge(
    name: str,
    location: tuple[float, float, float],
    width: float,
    depth: float,
    height: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    bevel: float,
    tilt: float = 0.0,
) -> bpy.types.Object:
    # Triangular prism, front at negative Y because the mascot faces -Y.
    w, d, h = width / 2, depth / 2, height / 2
    verts = [
        (-w, -d, -h), (w, -d, -h), (0.0, -d, h),
        (-w, d, -h), (w, d, -h), (0.0, d, h),
    ]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.rotation_euler[1] = tilt
    collection.objects.link(obj)
    assign_material(obj, material)
    MODEL_OBJECTS.append(obj)
    bevel_mod = obj.modifiers.new("Blockout_SoftEdges", "BEVEL")
    bevel_mod.width = bevel
    bevel_mod.segments = 4
    bevel_mod.limit_method = "ANGLE"
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def tail_curve(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = radius
    curve.bevel_resolution = 5
    curve.resolution_u = 20
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    assign_material(obj, material)
    MODEL_OBJECTS.append(obj)
    return obj


def look_at(camera: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def create_camera(name: str, location: tuple[float, float, float], collection: bpy.types.Collection) -> bpy.types.Object:
    data = bpy.data.cameras.new(f"{name}_Data")
    camera = bpy.data.objects.new(name, data)
    collection.objects.link(camera)
    camera.location = location
    data.type = "ORTHO"
    data.ortho_scale = 1.70
    data.lens = 70
    look_at(camera, (0.0, 0.0, 0.70))
    return camera


def create_area_light(
    name: str,
    location: tuple[float, float, float],
    energy: float,
    size: float,
    collection: bpy.types.Collection,
    color: tuple[float, float, float],
) -> bpy.types.Object:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    look_at(obj, (0.0, 0.0, 0.65))
    return obj


def setup_scene() -> tuple[bpy.types.Scene, dict[str, bpy.types.Material], dict[str, bpy.types.Object], bpy.types.Object, bpy.types.Object]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        # Only orphan cleanup from the factory scene; materials are created below.
        pass

    scene = bpy.context.scene
    scene.name = "BC_Blockout_S3"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.fps = 24
    scene.render.fps_base = 1.0
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_percentage = 100
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.022, 0.028, 0.045, 1.0)
    bg.inputs["Strength"].default_value = 0.28
    scene.view_settings.look = "AgX - Medium High Contrast"

    model_col = bpy.data.collections.new("BC_Blockout_Masses")
    camera_col = bpy.data.collections.new("BC_Blockout_Cameras")
    studio_col = bpy.data.collections.new("BC_Blockout_Studio")
    scene.collection.children.link(model_col)
    scene.collection.children.link(camera_col)
    scene.collection.children.link(studio_col)

    mats = {
        "blue": make_material("BC_Blockout_Blue", rgba("#386CA8"), 0.58),
        "blue_dark": make_material("BC_Blockout_DeepBlue", rgba("#274B7A"), 0.62),
        "cream": make_material("BC_Blockout_Cream", rgba("#C4C5BD"), 0.68),
        "pink": make_material("BC_Blockout_EarPink", rgba("#C65C7A"), 0.64),
        "green": make_material("BC_Blockout_EyeGreen", rgba("#57852D"), 0.42),
        "dark": make_material("BC_Blockout_Dark", rgba("#040802"), 0.38),
        "silhouette": make_material("BC_Blockout_Silhouette", (0.002, 0.002, 0.002, 1.0), 1.0),
        "floor": make_material("BC_Studio_Floor", (0.055, 0.065, 0.085, 1.0), 0.82),
    }

    root = bpy.data.objects.new("BC_Blockout_ROOT", None)
    model_col.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root["production_section"] = 3
    root["blockout_version"] = VERSION
    root["approved_height_m"] = 1.40
    root["approved_pose"] = "relaxed symmetric A-pose"
    root["source_record"] = "art_src/mascots/blue_cat/ref/BLUECAT_TURNAROUND_NOTES.md"

    # Primary silhouette masses. X=width, Y=depth, Z=height; the face looks -Y.
    ellipsoid("BC_HeadMass", (0.0, 0.0, 1.01), (0.375, 0.31, 0.29), mats["blue"], model_col)
    rounded_wedge("BC_Ear_L", (-0.225, 0.0, 1.265), 0.18, 0.14, 0.27, mats["blue"], model_col, 0.018, math.radians(-5))
    rounded_wedge("BC_Ear_R", (0.225, 0.0, 1.265), 0.18, 0.14, 0.27, mats["blue"], model_col, 0.018, math.radians(5))
    rounded_wedge("BC_InnerEar_L", (-0.225, -0.075, 1.265), 0.105, 0.012, 0.19, mats["pink"], model_col, 0.008, math.radians(-5))
    rounded_wedge("BC_InnerEar_R", (0.225, -0.075, 1.265), 0.105, 0.012, 0.19, mats["pink"], model_col, 0.008, math.radians(5))
    ellipsoid("BC_CrownTuft_L", (-0.043, -0.012, 1.302), (0.030, 0.038, 0.038), mats["blue_dark"], model_col, 32, 16)
    ellipsoid("BC_CrownTuft_C", (0.003, -0.020, 1.309), (0.028, 0.038, 0.043), mats["blue_dark"], model_col, 32, 16)
    ellipsoid("BC_CrownTuft_R", (0.049, -0.012, 1.302), (0.030, 0.038, 0.038), mats["blue_dark"], model_col, 32, 16)

    ellipsoid("BC_TorsoMass", (0.0, 0.005, 0.49), (0.235, 0.21, 0.245), mats["blue"], model_col)
    ellipsoid("BC_BellyGuide", (0.0, -0.196, 0.49), (0.142, 0.035, 0.195), mats["cream"], model_col, 48, 24)

    # Eyes and muzzle are major volume landmarks, not final facial topology.
    for side, x in (("L", -0.115), ("R", 0.115)):
        ellipsoid(f"BC_Eyeball_{side}", (x, -0.288, 1.035), (0.105, 0.052, 0.132), mats["cream"], model_col, 48, 24)
        ellipsoid(f"BC_IrisGuide_{side}", (x, -0.337, 1.035), (0.055, 0.014, 0.078), mats["green"], model_col, 40, 20)
        ellipsoid(f"BC_PupilGuide_{side}", (x, -0.349, 1.035), (0.024, 0.009, 0.054), mats["dark"], model_col, 32, 16)
    ellipsoid("BC_Muzzle_L", (-0.068, -0.319, 0.875), (0.105, 0.067, 0.078), mats["cream"], model_col, 48, 24)
    ellipsoid("BC_Muzzle_R", (0.068, -0.319, 0.875), (0.105, 0.067, 0.078), mats["cream"], model_col, 48, 24)
    ellipsoid("BC_ChinGuide", (0.0, -0.310, 0.815), (0.090, 0.045, 0.050), mats["cream"], model_col, 40, 20)
    ellipsoid("BC_NoseGuide", (0.0, -0.390, 0.915), (0.047, 0.030, 0.034), mats["dark"], model_col, 32, 16)

    # Approved relaxed A-pose. Separate limb masses keep Section 3 changes cheap.
    for label, sign in (("L", -1.0), ("R", 1.0)):
        shoulder = (sign * 0.195, 0.0, 0.645)
        elbow = (sign * 0.305, -0.005, 0.510)
        wrist = (sign * 0.395, -0.010, 0.365)
        ellipsoid_between(f"BC_UpperArm_{label}", shoulder, elbow, 0.080, 0.073, mats["blue"], model_col)
        ellipsoid_between(f"BC_Forearm_{label}", elbow, wrist, 0.070, 0.064, mats["blue"], model_col)
        ellipsoid(f"BC_HandMass_{label}", (sign * 0.425, -0.012, 0.305), (0.085, 0.075, 0.105), mats["blue"], model_col, 48, 24)
        ellipsoid(f"BC_PalmGuide_{label}", (sign * 0.425, -0.079, 0.305), (0.055, 0.018, 0.071), mats["cream"], model_col, 32, 16)
        ellipsoid(f"BC_ThumbMass_{label}", (sign * 0.370, -0.035, 0.315), (0.040, 0.045, 0.055), mats["blue"], model_col, 32, 16)

        leg_x = sign * 0.150
        ellipsoid(f"BC_LegMass_{label}", (leg_x, 0.010, 0.205), (0.105, 0.105, 0.125), mats["blue"], model_col, 48, 24)
        ellipsoid(f"BC_FootMass_{label}", (leg_x, -0.035, 0.080), (0.140, 0.150, 0.080), mats["blue"], model_col, 56, 28)
        ellipsoid(f"BC_ToeCapGuide_{label}", (leg_x, -0.171, 0.075), (0.105, 0.032, 0.055), mats["cream"], model_col, 40, 20)

    tail_points = [
        (0.075, 0.175, 0.285),
        (0.105, 0.295, 0.265),
        (0.145, 0.425, 0.285),
        (0.195, 0.520, 0.350),
        (0.245, 0.545, 0.435),
    ]
    tail_curve("BC_TailMass", tail_points, 0.055, mats["blue_dark"], model_col)
    tangent = Vector(tail_points[-1]) - Vector(tail_points[-2])
    tip = ellipsoid("BC_TailTipGuide", tail_points[-1], (0.068, 0.068, 0.095), mats["cream"], model_col, 48, 24)
    tip.rotation_mode = "QUATERNION"
    tip.rotation_quaternion = tangent.to_track_quat("Z", "Y")

    # Parent all editable masses to the turntable root without changing transforms.
    for obj in MODEL_OBJECTS:
        obj.parent = root

    # Blender primitives create UV maps by default. Section 3 explicitly has no
    # UV work, so remove every generated layer before the review file is saved.
    for mesh in bpy.data.meshes:
        for uv_layer in list(mesh.uv_layers):
            mesh.uv_layers.remove(uv_layer)

    # Neutral studio floor and lights.
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.006))
    floor = bpy.context.object
    floor.name = "BC_StudioFloor"
    move_to_collection(floor, studio_col)
    assign_material(floor, mats["floor"])
    create_area_light("BC_Key", (-3.0, -4.0, 4.5), 760.0, 4.0, studio_col, (1.0, 0.92, 0.82))
    create_area_light("BC_Fill", (3.8, -2.0, 2.6), 480.0, 3.0, studio_col, (0.72, 0.84, 1.0))
    create_area_light("BC_Rim", (0.5, 3.8, 3.3), 650.0, 2.5, studio_col, (0.65, 0.78, 1.0))
    create_area_light("BC_Top", (0.0, 0.0, 5.0), 350.0, 2.0, studio_col, (1.0, 1.0, 1.0))

    cameras = {
        "front": create_camera("CAM_BC_FRONT", (0.0, -5.0, 0.70), camera_col),
        "side": create_camera("CAM_BC_SIDE", (-5.0, 0.0, 0.70), camera_col),
        "back": create_camera("CAM_BC_BACK", (0.0, 5.0, 0.70), camera_col),
        "three_quarter": create_camera("CAM_BC_3Q", (3.8, -3.8, 0.80), camera_col),
    }

    # Stable scene metadata for later audit; this is not a rig or runtime contract.
    scene["section_3_status"] = "blockout_review"
    scene["official_height_m"] = 1.40
    scene["front_camera"] = cameras["front"].name
    scene["side_camera"] = cameras["side"].name
    scene["back_camera"] = cameras["back"].name
    return scene, mats, cameras, root, floor


def set_render(scene: bpy.types.Scene, width: int, height: int, samples: int = 32) -> None:
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_percentage = 100
    # Blender 5 Eevee sample property is on the scene.
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = samples


def render_still(scene: bpy.types.Scene, camera: bpy.types.Object, path: Path) -> None:
    scene.camera = camera
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED: {path}")


def render_review_media(
    scene: bpy.types.Scene,
    mats: dict[str, bpy.types.Material],
    cameras: dict[str, bpy.types.Object],
    root: bpy.types.Object,
    floor: bpy.types.Object,
) -> None:
    RENDERS.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    set_render(scene, 1024, 1024, 32)
    root.rotation_euler = (0.0, 0.0, 0.0)
    scene.frame_set(1)
    names = {
        "front": "S3_BlueCat_Blockout_Front_v001.png",
        "side": "S3_BlueCat_Blockout_Side_v001.png",
        "back": "S3_BlueCat_Blockout_Back_v001.png",
        "three_quarter": "S3_BlueCat_Blockout_ThreeQuarter_v001.png",
    }
    for key, filename in names.items():
        render_still(scene, cameras[key], RENDERS / filename)

    # Transparent front/side renders are QA intermediates for reference overlays.
    floor.hide_render = True
    scene.render.film_transparent = True
    render_still(scene, cameras["front"], QA / "S3_BlueCat_Blockout_FrontAlpha_v001.png")
    render_still(scene, cameras["side"], QA / "S3_BlueCat_Blockout_SideAlpha_v001.png")
    scene.render.film_transparent = False

    # Black-silhouette pass: every model mass receives one matte material.
    stored_materials: list[tuple[bpy.types.Object, list[bpy.types.Material]]] = []
    for obj in MODEL_OBJECTS:
        data = getattr(obj, "data", None)
        if data is not None and hasattr(data, "materials"):
            stored_materials.append((obj, list(data.materials)))
            data.materials.clear()
            data.materials.append(mats["silhouette"])
    bg = scene.world.node_tree.nodes.get("Background")
    old_color = tuple(bg.inputs["Color"].default_value)
    old_strength = bg.inputs["Strength"].default_value
    studio_lights = [obj for obj in bpy.data.objects if obj.type == "LIGHT"]
    old_light_visibility = {obj.name: obj.hide_render for obj in studio_lights}
    for light in studio_lights:
        light.hide_render = True
    bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    render_still(scene, cameras["front"], RENDERS / "S3_BlueCat_Blockout_BlackSilhouette_v001.png")
    for obj, materials in stored_materials:
        obj.data.materials.clear()
        for material in materials:
            obj.data.materials.append(material)
    bg.inputs["Color"].default_value = old_color
    bg.inputs["Strength"].default_value = old_strength
    for light in studio_lights:
        light.hide_render = old_light_visibility[light.name]
    floor.hide_render = False

    # 360-degree turntable animation. A driver is used instead of action
    # F-curves because Blender 5's layered Action API no longer exposes the
    # legacy ``action.fcurves`` collection. Forty-eight frames give unique
    # 7.5-degree views without duplicating the first frame at the end.
    root.rotation_mode = "XYZ"
    root.rotation_euler = (0.0, 0.0, 0.0)
    driver = root.driver_add("rotation_euler", 2).driver
    driver.type = "SCRIPTED"
    driver.expression = "2*pi*(frame-1)/48"
    scene.frame_start = 1
    scene.frame_end = 48
    scene.camera = cameras["three_quarter"]
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    # This Blender build has no FFmpeg output enum. Render a lossless sequence;
    # bc_blockout_review.py packages it into an animated WebP turntable.
    turntable_frames = QA / "turntable_frames_v001"
    turntable_frames.mkdir(parents=True, exist_ok=True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = str(turntable_frames / "S3_BlueCat_Turntable_")
    bpy.ops.render.render(animation=True)
    print(f"RENDERED: {turntable_frames} (48 PNG frames)")

    scene.frame_set(1)
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.camera = cameras["front"]


def print_bounds() -> None:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    zs: list[float] = []
    xs: list[float] = []
    ys: list[float] = []
    for obj in MODEL_OBJECTS:
        evaluated = obj.evaluated_get(depsgraph)
        for corner in evaluated.bound_box:
            world = evaluated.matrix_world @ Vector(corner)
            xs.append(world.x)
            ys.append(world.y)
            zs.append(world.z)
    print(f"BLOCKOUT_BOUNDS x={min(xs):.4f}..{max(xs):.4f} y={min(ys):.4f}..{max(ys):.4f} z={min(zs):.4f}..{max(zs):.4f}")
    print(f"BLOCKOUT_HEIGHT_M={max(zs) - min(zs):.4f}")


def main() -> None:
    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    RENDERS.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    scene, mats, cameras, root, floor = setup_scene()
    print_bounds()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    print(f"SAVED: {BLEND_PATH}")
    render_review_media(scene, mats, cameras, root, floor)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    print(f"SAVED FINAL: {BLEND_PATH}")


if __name__ == "__main__":
    main()
