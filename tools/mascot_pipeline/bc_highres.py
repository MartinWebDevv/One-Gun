"""Create the Blue Cat Section 4 high-quality rounded source model.

Run with Blender 5.1+:
    blender --background --factory-startup --python tools/mascot_pipeline/bc_highres.py

This is the high-resolution form stage. It intentionally does not create the
Section 5 real-time topology, UVs, LODs, rig, skinning, or Godot export.
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
BLEND_PATH = BLEND_DIR / "BC_HighRes_v001.blend"

CONSTRUCTION: list[bpy.types.Object] = []
RENDER_OBJECTS: list[bpy.types.Object] = []


def srgb_channel(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def rgba(hex_value: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = hex_value.lstrip("#")
    srgb = [int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return (*(srgb_channel(channel) for channel in srgb), alpha)


def material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float = 0.52,
    specular: float = 0.32,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in principled.inputs:
        principled.inputs["Specular IOR Level"].default_value = specular
    return mat


def wire_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("BC_S4_WirePreview")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    wire = nodes.new("ShaderNodeWireframe")
    mix = nodes.new("ShaderNodeMixRGB")
    wire.inputs["Size"].default_value = 0.65
    wire.use_pixel_size = True
    mix.blend_type = "MIX"
    mix.inputs[1].default_value = rgba("#111824")
    mix.inputs[2].default_value = rgba("#59D7FF")
    shader.inputs["Roughness"].default_value = 0.72
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.15
    links.new(wire.outputs["Fac"], mix.inputs[0])
    links.new(mix.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return mat


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    data = getattr(obj, "data", None)
    if data is not None and hasattr(data, "materials"):
        data.materials.clear()
        data.materials.append(mat)


def move(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def add_construction(obj: bpy.types.Object, collection: bpy.types.Collection, mat: bpy.types.Material) -> bpy.types.Object:
    move(obj, collection)
    assign(obj, mat)
    CONSTRUCTION.append(obj)
    return obj


def add_render_object(obj: bpy.types.Object, collection: bpy.types.Collection, mat: bpy.types.Material) -> bpy.types.Object:
    move(obj, collection)
    assign(obj, mat)
    RENDER_OBJECTS.append(obj)
    return obj


def sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    construction: bool = False,
    segments: int = 64,
    rings: int = 32,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.shade_smooth()
    if construction:
        return add_construction(obj, collection, mat)
    return add_render_object(obj, collection, mat)


def sphere_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radii: tuple[float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    construction: bool = False,
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    direction = b - a
    obj = sphere(name, tuple((a + b) * 0.5), (radii[0], radii[1], direction.length * 0.56), mat, collection, construction, 48, 24)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def tube_curve(
    name: str,
    points: list[tuple[float, float, float]],
    radii: list[float],
    bevel: float,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    construction: bool = False,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 20
    curve.bevel_depth = bevel
    curve.bevel_resolution = 6
    # Voxel remesh needs a closed construction volume.  Uncapped bevel curves
    # are open tubes, which can produce broken strip-like surfaces after the
    # arm, leg, and tail forms are fused into the high-resolution body shell.
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co, radius in zip(spline.bezier_points, points, radii):
        point.co = co
        point.radius = radius
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    assign(obj, mat)
    if construction:
        CONSTRUCTION.append(obj)
    else:
        RENDER_OBJECTS.append(obj)
    return obj


def line_curve(
    name: str,
    points: list[tuple[float, float, float]],
    bevel: float,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = bevel
    curve.bevel_resolution = 5
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    assign(obj, mat)
    RENDER_OBJECTS.append(obj)
    return obj


def tapered_ear(
    name: str,
    location: tuple[float, float, float],
    width: float,
    depth: float,
    height: float,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
    construction: bool = False,
    tilt_y: float = 0.0,
    rings: int = 10,
    sides: int = 32,
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for ring in range(rings + 1):
        t = ring / rings
        falloff = max(0.018, (1.0 - t) ** 0.72)
        rx = width * 0.5 * falloff
        ry = depth * 0.5 * max(0.025, (1.0 - t) ** 0.88)
        z = -height * 0.5 + height * t
        for side in range(sides):
            angle = math.tau * side / sides
            vertices.append((rx * math.cos(angle), ry * math.sin(angle), z))
    for ring in range(rings):
        base = ring * sides
        nxt = (ring + 1) * sides
        for side in range(sides):
            n = (side + 1) % sides
            faces.append((base + side, base + n, nxt + n, nxt + side))
    faces.append(tuple(reversed(tuple(range(sides)))))
    faces.append(tuple(rings * sides + side for side in range(sides)))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.rotation_euler[1] = tilt_y
    collection.objects.link(obj)
    assign(obj, mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    if construction:
        CONSTRUCTION.append(obj)
    else:
        RENDER_OBJECTS.append(obj)
    return obj


def rounded_nose(
    name: str,
    location: tuple[float, float, float],
    width: float,
    depth: float,
    height: float,
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    w, d, h = width / 2, depth / 2, height / 2
    verts = [
        (-w, -d, h), (w, -d, h), (0.0, -d, -h),
        (-w, d, h), (w, d, h), (0.0, d, -h),
    ]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    collection.objects.link(obj)
    assign(obj, mat)
    bevel = obj.modifiers.new("BC_NoseSoftness", "BEVEL")
    bevel.width = min(width, height) * 0.22
    bevel.segments = 5
    bevel.limit_method = "ANGLE"
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    RENDER_OBJECTS.append(obj)
    return obj


def torus_lid(
    name: str,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        align="WORLD",
        major_segments=64,
        minor_segments=16,
        location=location,
        rotation=(math.pi / 2, 0.0, 0.0),
        major_radius=0.100,
        minor_radius=0.012,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = (1.0, 1.25, 1.0)  # Local Y becomes world Z after rotation.
    bpy.ops.object.shade_smooth()
    return add_render_object(obj, collection, mat)


def duplicate_as_mesh(source: bpy.types.Object, collection: bpy.types.Collection) -> bpy.types.Object:
    duplicate = source.copy()
    duplicate.data = source.data.copy()
    collection.objects.link(duplicate)
    bpy.context.view_layer.objects.active = duplicate
    duplicate.select_set(True)
    if duplicate.type == "CURVE":
        bpy.ops.object.convert(target="MESH")
        duplicate = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    duplicate.select_set(False)
    return duplicate


def fuse_blue_shell(
    sources: list[bpy.types.Object],
    collection: bpy.types.Collection,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    duplicates = [duplicate_as_mesh(source, collection) for source in sources]
    for duplicate in duplicates:
        duplicate.select_set(True)
    bpy.context.view_layer.objects.active = duplicates[0]
    bpy.ops.object.join()
    shell = bpy.context.object
    shell.name = "BC_HighRes_BodyShell"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Section 4 is the sculpt-quality source, so favor a fine voxel field over
    # the eventual game budget.  Section 5 will build the controlled LOD0.
    shell.data.remesh_voxel_size = 0.0065
    shell.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    bpy.ops.object.shade_smooth()
    smooth = shell.modifiers.new("BC_FormRelax", "LAPLACIANSMOOTH")
    # The voxel union establishes a watertight continuous shell, then a firm
    # volume-preserving relaxation removes voxel terraces and boolean ridges.
    # This is the polish pass that keeps the character toy-smooth at review
    # distance while retaining the approved large forms.
    smooth.iterations = 10
    smooth.lambda_factor = 0.40
    smooth.use_volume_preserve = True
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    # A second, dense-mesh relaxation removes the remaining voxel ribs from
    # long cylindrical forms (especially the arm trunks and tail).  At this
    # source density forty local iterations polish the surface without moving
    # the approved silhouette or erasing the simplified fingers.
    surface_polish = shell.modifiers.new("BC_SurfacePolish", "SMOOTH")
    surface_polish.factor = 0.65
    surface_polish.iterations = 40
    bpy.ops.object.modifier_apply(modifier=surface_polish.name)
    subdivision = shell.modifiers.new("BC_MenuRenderSubdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 1
    assign(shell, mat)
    RENDER_OBJECTS.append(shell)
    return shell


def fuse_detail(
    name: str,
    sources: list[bpy.types.Object],
    collection: bpy.types.Collection,
    mat: bpy.types.Material,
    voxel: float,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    duplicates = [duplicate_as_mesh(source, collection) for source in sources]
    for duplicate in duplicates:
        duplicate.select_set(True)
    bpy.context.view_layer.objects.active = duplicates[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.remesh_voxel_size = voxel
    obj.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    bpy.ops.object.shade_smooth()
    smooth = obj.modifiers.new(f"{name}_Relax", "SMOOTH")
    smooth.factor = 0.22
    smooth.iterations = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    assign(obj, mat)
    RENDER_OBJECTS.append(obj)
    return obj


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def camera(
    name: str,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    ortho: float,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    data = bpy.data.cameras.new(f"{name}_Data")
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    data.type = "ORTHO"
    data.ortho_scale = ortho
    look_at(obj, target)
    return obj


def area_light(name, location, energy, size, color, collection) -> bpy.types.Object:
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


def build_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.name = "BC_HighRes_S4"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"
    scene.render.dither_intensity = 1.0
    scene.render.film_transparent = False
    scene.render.fps = 24
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.014, 0.019, 0.031, 1.0)
    background.inputs["Strength"].default_value = 0.24
    scene.view_settings.look = "AgX - Medium High Contrast"

    construction_col = bpy.data.collections.new("BC_S4_EditableConstruction")
    model_col = bpy.data.collections.new("BC_S4_HighResModel")
    camera_col = bpy.data.collections.new("BC_S4_Cameras")
    studio_col = bpy.data.collections.new("BC_S4_Studio")
    scene.collection.children.link(construction_col)
    scene.collection.children.link(model_col)
    scene.collection.children.link(camera_col)
    scene.collection.children.link(studio_col)

    mats = {
        "blue": material("BC_S4_Blue", rgba("#386CA8"), 0.62, 0.22),
        "blue_dark": material("BC_S4_DeepBlue", rgba("#274B7A"), 0.54),
        "cream": material("BC_S4_Cream", rgba("#C4C5BD"), 0.58),
        "pink": material("BC_S4_Pink", rgba("#C65C7A"), 0.54),
        "green": material("BC_S4_IrisGreen", rgba("#57852D"), 0.36),
        "green_lit": material("BC_S4_IrisHighlight", rgba("#8ABF45"), 0.32),
        "dark": material("BC_S4_Dark", rgba("#040802"), 0.30),
        "white": material("BC_S4_EyeHighlight", rgba("#F5F3E8"), 0.28),
        "floor": material("BC_S4_StudioFloor", (0.035, 0.045, 0.065, 1.0), 0.82),
        "wire": wire_material(),
    }

    root = bpy.data.objects.new("BC_HighRes_ROOT", None)
    model_col.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root["production_section"] = 4
    root["source_blockout"] = "BC_Blockout_v001.blend"
    root["approved_height_m"] = 1.40
    root["form_requirement"] = "continuous rounded premium-toy surfaces"

    # --- Editable blue construction sources ---------------------------------
    blue_sources: list[bpy.types.Object] = []
    # Padded cheek construction: main cranium plus lower side volumes.
    blue_sources.append(sphere("SRC_HeadCore", (0.0, 0.005, 1.025), (0.330, 0.305, 0.275), mats["blue"], construction_col, True, 48, 24))
    blue_sources.append(sphere("SRC_Cheek_L", (-0.155, -0.018, 0.955), (0.220, 0.285, 0.205), mats["blue"], construction_col, True, 40, 20))
    blue_sources.append(sphere("SRC_Cheek_R", (0.155, -0.018, 0.955), (0.220, 0.285, 0.205), mats["blue"], construction_col, True, 40, 20))
    blue_sources.append(sphere("SRC_NeckBridge", (0.0, 0.010, 0.715), (0.170, 0.155, 0.095), mats["blue"], construction_col, True, 32, 16))

    # Soft tapered ears and crown tufts are fused into the shell.
    blue_sources.append(tapered_ear("SRC_Ear_L", (-0.225, 0.002, 1.265), 0.190, 0.145, 0.270, mats["blue"], construction_col, True, math.radians(-5)))
    blue_sources.append(tapered_ear("SRC_Ear_R", (0.225, 0.002, 1.265), 0.190, 0.145, 0.270, mats["blue"], construction_col, True, math.radians(5)))
    for name, loc, scale, angle in (
        ("SRC_Tuft_L", (-0.046, -0.005, 1.310), (0.034, 0.042, 0.052), -18),
        ("SRC_Tuft_C", (0.000, -0.012, 1.320), (0.032, 0.042, 0.058), 0),
        ("SRC_Tuft_R", (0.046, -0.005, 1.310), (0.034, 0.042, 0.052), 18),
    ):
        tuft = sphere(name, loc, scale, mats["blue"], construction_col, True, 32, 16)
        tuft.rotation_euler[1] = math.radians(angle)
        blue_sources.append(tuft)

    # Pear torso and pelvis masses overlap for a single continuous body.
    blue_sources.append(sphere("SRC_UpperTorso", (0.0, 0.005, 0.545), (0.205, 0.190, 0.205), mats["blue"], construction_col, True, 40, 20))
    blue_sources.append(sphere("SRC_LowerTorso", (0.0, 0.012, 0.410), (0.225, 0.205, 0.190), mats["blue"], construction_col, True, 40, 20))

    # One continuous curved trunk per arm; no bead-joint construction.
    for label, sign in (("L", -1.0), ("R", 1.0)):
        blue_sources.append(
            sphere(
                f"SRC_ShoulderBlend_{label}",
                (sign * 0.175, 0.005, 0.610),
                (0.128, 0.105, 0.120),
                mats["blue"],
                construction_col,
                True,
                36,
                18,
            )
        )
        arm = tube_curve(
            f"SRC_ArmTrunk_{label}",
            [
                # Begin inside the torso volume so the shoulder reads as one
                # continuous fleshy transition, never as a socket or gap.
                (sign * 0.140, 0.005, 0.645),
                (sign * 0.235, 0.000, 0.585),
                (sign * 0.325, -0.005, 0.480),
                (sign * 0.395, -0.010, 0.365),
            ],
            [1.28, 1.10, 0.97, 0.88],
            0.070,
            mats["blue"],
            construction_col,
            True,
        )
        blue_sources.append(arm)

        # Palm, three fingers, and thumb overlap into one fused grip-capable hand.
        hand_x = sign * 0.420
        blue_sources.append(sphere(f"SRC_Palm_{label}", (hand_x, -0.010, 0.300), (0.078, 0.068, 0.086), mats["blue"], construction_col, True, 36, 18))
        offsets = (-0.038, 0.0, 0.038)
        for index, offset in enumerate(offsets, 1):
            finger = sphere(
                f"SRC_Finger{index}_{label}",
                (hand_x + offset, -0.012, 0.238),
                (0.032, 0.039, 0.060),
                mats["blue"],
                construction_col,
                True,
                28,
                14,
            )
            blue_sources.append(finger)
        thumb = sphere(
            f"SRC_Thumb_{label}",
            (sign * 0.360, -0.035, 0.285),
            (0.042, 0.046, 0.060),
            mats["blue"],
            construction_col,
            True,
            28,
            14,
        )
        thumb.rotation_euler[1] = math.radians(sign * 34)
        blue_sources.append(thumb)

        # Continuous leg trunk and broad stable foot.
        blue_sources.append(
            sphere(
                f"SRC_HipBlend_{label}",
                (sign * 0.135, 0.010, 0.300),
                (0.125, 0.112, 0.130),
                mats["blue"],
                construction_col,
                True,
                36,
                18,
            )
        )
        leg = tube_curve(
            f"SRC_LegTrunk_{label}",
            [(sign * 0.135, 0.012, 0.315), (sign * 0.150, 0.008, 0.225), (sign * 0.150, -0.005, 0.130)],
            [1.10, 1.03, 0.92],
            0.096,
            mats["blue"],
            construction_col,
            True,
        )
        blue_sources.append(leg)
        foot = sphere(f"SRC_Foot_{label}", (sign * 0.150, -0.045, 0.075), (0.140, 0.150, 0.075), mats["blue"], construction_col, True, 48, 24)
        blue_sources.append(foot)

    # The root begins deep inside the rear pelvis and passes through a broad
    # blend mass before emerging.  This prevents a pinched, pasted-on tail
    # connection while keeping the approved rest direction.
    blue_sources.append(
        sphere(
            "SRC_TailRootBlend",
            (0.070, 0.125, 0.310),
            (0.115, 0.115, 0.105),
            mats["blue"],
            construction_col,
            True,
            36,
            18,
        )
    )
    tail_points = [
        (0.055, 0.060, 0.325),
        (0.075, 0.190, 0.285),
        (0.115, 0.315, 0.270),
        (0.175, 0.455, 0.305),
        (0.225, 0.535, 0.365),
        (0.255, 0.555, 0.435),
    ]
    tail = tube_curve("SRC_Tail", tail_points, [1.60, 1.38, 1.16, 1.0, 0.90, 0.82], 0.058, mats["blue"], construction_col, True)
    blue_sources.append(tail)

    shell = fuse_blue_shell(blue_sources, model_col, mats["blue"])

    # Hide the still-editable construction sources from review renders.
    construction_col.hide_render = True
    construction_col.hide_viewport = True

    # --- Intentional region forms and face ----------------------------------
    # Inner-ear volumes leave a broad rounded blue rim.
    tapered_ear("BC_InnerEar_L", (-0.225, -0.078, 1.270), 0.112, 0.018, 0.185, mats["pink"], model_col, False, math.radians(-5), 8, 28)
    tapered_ear("BC_InnerEar_R", (0.225, -0.078, 1.270), 0.112, 0.018, 0.185, mats["pink"], model_col, False, math.radians(5), 8, 28)

    # Separate rounded eyeballs, recessed into the face.  The blue socket/lid
    # rim sits behind the cream white, and the iris/pupil layers project only
    # a few millimeters so the side view reads as one seated eye assembly.
    for label, x in (("L", -0.115), ("R", 0.115)):
        sphere(f"BC_Eyeball_{label}", (x, -0.278, 1.045), (0.101, 0.038, 0.130), mats["cream"], model_col, False, 64, 32)
        torus_lid(f"BC_EyelidSocket_{label}", (x, -0.276, 1.045), mats["blue_dark"], model_col)
        sphere(f"BC_Iris_{label}", (x, -0.314, 1.045), (0.054, 0.004, 0.077), mats["green"], model_col, False, 48, 24)
        sphere(f"BC_Pupil_{label}", (x, -0.319, 1.045), (0.023, 0.0028, 0.053), mats["dark"], model_col, False, 36, 18)
        sphere(f"BC_EyeHighlightBig_{label}", (x - 0.015, -0.324, 1.080), (0.011, 0.0022, 0.017), mats["white"], model_col, False, 24, 12)
        sphere(f"BC_EyeHighlightSmall_{label}", (x + 0.018, -0.324, 1.012), (0.006, 0.0020, 0.009), mats["green_lit"], model_col, False, 20, 10)

    # One fused cream muzzle pad prevents the pasted-pair look.
    muzzle_sources = [
        sphere("SRC_Muzzle_L", (-0.065, -0.335, 0.875), (0.112, 0.070, 0.082), mats["cream"], construction_col, True, 40, 20),
        sphere("SRC_Muzzle_R", (0.065, -0.335, 0.875), (0.112, 0.070, 0.082), mats["cream"], construction_col, True, 40, 20),
        sphere("SRC_MuzzleChin", (0.0, -0.325, 0.820), (0.092, 0.052, 0.055), mats["cream"], construction_col, True, 36, 18),
    ]
    fuse_detail("BC_MuzzlePad", muzzle_sources, model_col, mats["cream"], 0.0055)
    rounded_nose("BC_Nose", (0.0, -0.414, 0.910), 0.092, 0.055, 0.062, mats["dark"], model_col)
    line_curve("BC_Mouth_L", [(0.0, -0.416, 0.875), (-0.018, -0.418, 0.845), (-0.055, -0.414, 0.838)], 0.006, mats["dark"], model_col)
    line_curve("BC_Mouth_R", [(0.0, -0.416, 0.875), (0.018, -0.418, 0.845), (0.055, -0.414, 0.838)], 0.006, mats["dark"], model_col)

    # Cream brows, belly, palms, toes, and tail tip are intentional broad forms.
    for label, x, angle in (("L", -0.135, -12), ("R", 0.135, 12)):
        brow = sphere(f"BC_Brow_{label}", (x, -0.321, 1.188), (0.060, 0.018, 0.018), mats["cream"], model_col, False, 32, 16)
        brow.rotation_euler[1] = math.radians(angle)
    sphere("BC_BellyPad", (0.0, -0.207, 0.485), (0.140, 0.030, 0.190), mats["cream"], model_col, False, 56, 28)
    for label, sign in (("L", -1.0), ("R", 1.0)):
        # The flattened pad is mostly buried in the palm.  Only its shallow
        # dome is exposed, so the perimeter is seated instead of hovering.
        sphere(f"BC_PalmPad_{label}", (sign * 0.420, -0.0725, 0.295), (0.050, 0.0065, 0.058), mats["cream"], model_col, False, 36, 18)
        foot_x = sign * 0.150
        for index, offset in enumerate((-0.055, 0.0, 0.055), 1):
            sphere(
                f"BC_ToePad{index}_{label}",
                (foot_x + offset, -0.184, 0.072),
                (0.042, 0.022, 0.040),
                mats["cream"],
                model_col,
                False,
                28,
                14,
            )
    tangent = Vector(tail_points[-1]) - Vector(tail_points[-2])
    tail_tip = sphere("BC_TailTip", tail_points[-1], (0.068, 0.068, 0.100), mats["cream"], model_col, False, 48, 24)
    tail_tip.rotation_mode = "QUATERNION"
    tail_tip.rotation_quaternion = tangent.to_track_quat("Z", "Y")

    # Three bold whiskers per cheek, modeled as rounded curves.
    for sign, label in ((-1.0, "L"), (1.0, "R")):
        start_x = sign * 0.145
        for index, zoff in enumerate((0.030, 0.0, -0.030), 1):
            line_curve(
                f"BC_Whisker{index}_{label}",
                [(start_x, -0.340, 0.895 + zoff), (sign * 0.205, -0.350, 0.900 + zoff), (sign * 0.265, -0.330, 0.910 + zoff * 0.7)],
                0.005,
                mats["cream"],
                model_col,
            )

    # Parent every final review form to a clean turntable root.
    for obj in RENDER_OBJECTS:
        obj.parent = root

    # No UV work is allowed in Section 4, including default primitive UV maps.
    for mesh in bpy.data.meshes:
        for uv_layer in list(mesh.uv_layers):
            mesh.uv_layers.remove(uv_layer)

    # Neutral studio.
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.006))
    floor = bpy.context.object
    floor.name = "BC_S4_StudioFloor"
    move(floor, studio_col)
    assign(floor, mats["floor"])
    for uv_layer in list(floor.data.uv_layers):
        floor.data.uv_layers.remove(uv_layer)
    area_light("BC_S4_Key", (-3.0, -4.0, 4.2), 720.0, 4.0, (1.0, 0.91, 0.82), studio_col)
    area_light("BC_S4_Fill", (3.6, -2.0, 2.8), 430.0, 3.2, (0.72, 0.84, 1.0), studio_col)
    area_light("BC_S4_Rim", (0.7, 3.8, 3.2), 620.0, 2.5, (0.60, 0.75, 1.0), studio_col)
    area_light("BC_S4_Top", (0.0, 0.0, 5.0), 320.0, 2.0, (1.0, 1.0, 1.0), studio_col)

    cameras = {
        "front": camera("CAM_S4_FRONT", (0.0, -5.0, 0.70), (0.0, 0.0, 0.70), 1.70, camera_col),
        "side": camera("CAM_S4_SIDE", (-5.0, 0.0, 0.70), (0.0, 0.0, 0.70), 1.70, camera_col),
        "back": camera("CAM_S4_BACK", (0.0, 5.0, 0.70), (0.0, 0.0, 0.70), 1.70, camera_col),
        "three_quarter": camera("CAM_S4_3Q", (3.8, -3.8, 0.80), (0.0, 0.0, 0.70), 1.72, camera_col),
        "face": camera("CAM_S4_FACE", (0.0, -3.0, 1.04), (0.0, 0.0, 1.04), 0.72, camera_col),
        "hand": camera("CAM_S4_HAND", (0.420, -2.5, 0.285), (0.420, 0.0, 0.285), 0.42, camera_col),
        "feet": camera("CAM_S4_FEET", (0.0, -2.5, 0.125), (0.0, 0.0, 0.125), 0.54, camera_col),
        "shoulders": camera("CAM_S4_SHOULDERS", (0.0, -2.5, 0.610), (0.0, 0.0, 0.610), 0.68, camera_col),
        "tail": camera("CAM_S4_TAIL", (-2.8, 0.0, 0.360), (0.08, 0.36, 0.350), 0.72, camera_col),
    }
    scene["section_4_status"] = "highres_model_review"
    scene["official_height_m"] = 1.40
    scene["body_shell"] = shell.name
    scene["no_uvs"] = True
    scene["no_rig"] = True
    return scene, mats, cameras, root, floor, construction_col


def set_render(scene: bpy.types.Scene, width: int, height: int) -> None:
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"
    scene.render.film_transparent = False


def render(scene: bpy.types.Scene, camera_obj: bpy.types.Object, path: Path) -> None:
    scene.camera = camera_obj
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED: {path}")


def render_media(scene, mats, cameras, root, floor):
    RENDERS.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    set_render(scene, 1024, 1024)
    root.rotation_euler = (0.0, 0.0, 0.0)
    scene.frame_set(1)

    for key, filename in {
        "front": "S4_BlueCat_HighRes_Front_v001.png",
        "side": "S4_BlueCat_HighRes_Side_v001.png",
        "back": "S4_BlueCat_HighRes_Back_v001.png",
        "three_quarter": "S4_BlueCat_HighRes_ThreeQuarter_v001.png",
        "face": "S4_BlueCat_Closeup_Face_v001.png",
        "hand": "S4_BlueCat_Closeup_Hand_v001.png",
        "feet": "S4_BlueCat_Closeup_Feet_v001.png",
        "shoulders": "S4_BlueCat_Closeup_Shoulders_v001.png",
        "tail": "S4_BlueCat_Closeup_Tail_v001.png",
    }.items():
        render(scene, cameras[key], RENDERS / filename)

    # Transparent passes for exact reference alignment and silhouette creation.
    floor.hide_render = True
    scene.render.film_transparent = True
    render(scene, cameras["front"], QA / "S4_BlueCat_HighRes_FrontAlpha_v001.png")
    render(scene, cameras["side"], QA / "S4_BlueCat_HighRes_SideAlpha_v001.png")
    scene.render.film_transparent = False

    # Wire preview uses a pixel-size wire shader and restores every material.
    stored: list[tuple[bpy.types.Object, list[bpy.types.Material]]] = []
    for obj in RENDER_OBJECTS:
        data = getattr(obj, "data", None)
        if obj.type == "MESH" and data is not None and hasattr(data, "materials"):
            stored.append((obj, list(data.materials)))
            data.materials.clear()
            data.materials.append(mats["wire"])
    render(scene, cameras["front"], RENDERS / "S4_BlueCat_HighRes_WireFront_v001.png")
    render(scene, cameras["three_quarter"], RENDERS / "S4_BlueCat_HighRes_WireThreeQuarter_v001.png")
    for obj, materials in stored:
        obj.data.materials.clear()
        for mat in materials:
            obj.data.materials.append(mat)
    floor.hide_render = False

    # 48 unique turntable views; workspace Python packages them as WebP.
    root.rotation_mode = "XYZ"
    driver = root.driver_add("rotation_euler", 2).driver
    driver.type = "SCRIPTED"
    driver.expression = "2*pi*(frame-1)/48"
    scene.frame_start = 1
    scene.frame_end = 48
    scene.camera = cameras["three_quarter"]
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    frame_dir = QA / "s4_turntable_frames_v001"
    frame_dir.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(frame_dir / "S4_BlueCat_Turntable_")
    bpy.ops.render.render(animation=True)
    print(f"RENDERED: {frame_dir} (48 PNG frames)")
    scene.frame_set(1)
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.camera = cameras["front"]


def print_audit():
    zs: list[float] = []
    xs: list[float] = []
    ys: list[float] = []
    for obj in RENDER_OBJECTS:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            xs.append(world.x)
            ys.append(world.y)
            zs.append(world.z)
    triangles = 0
    for obj in RENDER_OBJECTS:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
    print(f"S4_BOUNDS x={min(xs):.4f}..{max(xs):.4f} y={min(ys):.4f}..{max(ys):.4f} z={min(zs):.4f}..{max(zs):.4f}")
    print(f"S4_HEIGHT_M={max(zs)-min(zs):.4f}")
    print(f"S4_BASE_TRIANGLES={triangles}")
    print(f"S4_RENDER_OBJECTS={len(RENDER_OBJECTS)}")


def main():
    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    RENDERS.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    scene, mats, cameras, root, floor, construction = build_scene()
    print_audit()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    print(f"SAVED: {BLEND_PATH}")
    render_media(scene, mats, cameras, root, floor)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    print(f"SAVED FINAL: {BLEND_PATH}")


if __name__ == "__main__":
    main()
