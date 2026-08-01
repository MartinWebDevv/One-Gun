"""Build the Blue Cat Section 4 v002 organic sculpt source.

This rebuild deliberately avoids the rejected voxel-union construction.  The
body is formed as one smooth implicit sculpt volume; ears, facial regions, and
surface patches remain editable subtools.  Section 5 topology/UV/LOD work is
not created here.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bc_highres as base


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "art_src/mascots/blue_cat/blend/BC_HighRes_v002.blend"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
QA = ROOT / "art_src/mascots/blue_cat/qa"


def meta_ellipsoid(meta: bpy.types.MetaBall, co, dimensions, stiffness: float = 2.0):
    element = meta.elements.new()
    element.type = "ELLIPSOID"
    element.co = co
    element.radius = 2.0
    # At radius 2 and threshold 0.6 Blender's isolated metaball surface is
    # approximately 2.293 times each size axis.
    element.size_x = dimensions[0] / 2.293
    element.size_y = dimensions[1] / 2.293
    element.size_z = dimensions[2] / 2.293
    element.stiffness = stiffness
    return element


def implicit_sculpt(name, elements, material, collection, resolution=0.007):
    meta = bpy.data.metaballs.new(f"{name}_Implicit")
    meta.resolution = resolution
    meta.render_resolution = resolution
    meta.threshold = 0.62
    obj = bpy.data.objects.new(name, meta)
    collection.objects.link(obj)
    for co, dimensions, stiffness in elements:
        meta_ellipsoid(meta, co, dimensions, stiffness)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.shade_smooth()
    polish = obj.modifiers.new(f"{name}_SurfacePolish", "SMOOTH")
    polish.factor = 0.42
    polish.iterations = 20
    bpy.ops.object.modifier_apply(modifier=polish.name)
    subdivision = obj.modifiers.new(f"{name}_ReviewSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1
    base.assign(obj, material)
    base.RENDER_OBJECTS.append(obj)
    return obj


def ellipse_rim(name, x, y, z, rx, rz, bevel, material, collection):
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 24
    curve.bevel_depth = bevel
    curve.bevel_resolution = 5
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    count = 48
    spline.points.add(count - 1)
    for index, point in enumerate(spline.points):
        angle = math.tau * index / count
        point.co = (x + rx * math.cos(angle), y, z + rz * math.sin(angle), 1.0)
    spline.use_cyclic_u = True
    spline.order_u = 3
    spline.use_endpoint_u = False
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    base.assign(obj, material)
    base.RENDER_OBJECTS.append(obj)
    return obj


def rounded_ear(name, location, sign, blue, pink, collection):
    outer = base.tapered_ear(
        f"{name}_Outer",
        location,
        0.168,
        0.112,
        0.232,
        blue,
        collection,
        False,
        math.radians(sign * 4.0),
        14,
        40,
    )
    bevel = outer.modifiers.new(f"{name}_OuterSoftness", "BEVEL")
    bevel.width = 0.011
    bevel.segments = 4
    bevel.limit_method = "ANGLE"
    inner = base.tapered_ear(
        f"{name}_Inner",
        (location[0], location[1] - 0.061, location[2] + 0.003),
        0.100,
        0.018,
        0.160,
        pink,
        collection,
        False,
        math.radians(sign * 4.0),
        12,
        36,
    )
    return outer, inner


def build_body_elements():
    elements = [
        # One cohesive padded head with cheek emphasis and a restrained face
        # projection.  These volumes blend implicitly with no boolean seams.
        ((0.000, 0.018, 1.055), (0.575, 0.455, 0.430), 2.0),
        ((-0.145, -0.005, 0.985), (0.320, 0.440, 0.275), 2.0),
        ((0.145, -0.005, 0.985), (0.320, 0.440, 0.275), 2.0),
        ((0.000, 0.012, 0.755), (0.270, 0.245, 0.145), 2.0),
        # Pear torso and pelvis.
        ((0.000, 0.010, 0.555), (0.365, 0.320, 0.370), 2.0),
        ((0.000, 0.020, 0.405), (0.425, 0.360, 0.315), 2.0),
    ]

    # Continuous organic arm trunks.  Dense overlap produces one clean limb,
    # not visible bead segments.
    for sign in (-1.0, 1.0):
        arm_points = [
            (0.175, 0.010, 0.640, 0.205),
            (0.225, 0.004, 0.610, 0.180),
            (0.275, -0.002, 0.555, 0.158),
            (0.320, -0.008, 0.495, 0.145),
            (0.360, -0.014, 0.425, 0.134),
            (0.395, -0.018, 0.350, 0.126),
        ]
        for x, y, z, diameter in arm_points:
            elements.append(((sign * x, y, z), (diameter, diameter * 0.92, diameter * 1.08), 2.0))

        # Mitten hand with a tapered palm and understated fingers.
        elements.append(((sign * 0.418, -0.022, 0.283), (0.155, 0.128, 0.180), 2.0))
        for offset in (-0.040, 0.0, 0.040):
            elements.append(((sign * 0.418 + offset, -0.025, 0.220), (0.054, 0.060, 0.070), 2.0))
        elements.append(((sign * 0.362, -0.043, 0.286), (0.074, 0.070, 0.092), 2.0))

        # Broad thigh-to-ankle trunk and stable foot.
        elements.extend(
            [
                ((sign * 0.132, 0.018, 0.305), (0.225, 0.215, 0.275), 2.0),
                ((sign * 0.145, 0.005, 0.205), (0.200, 0.195, 0.245), 2.0),
                ((sign * 0.150, -0.040, 0.078), (0.270, 0.285, 0.135), 2.0),
            ]
        )

    # Only the buried anatomical root belongs to the implicit body.  The
    # visible tail is a clean swept subtool so its arc cannot inherit a chain
    # of metaball bulges.
    elements.append(((0.055, 0.100, 0.320), (0.205, 0.190, 0.185), 2.0))
    return elements


def build_scene():
    base.CONSTRUCTION.clear()
    base.RENDER_OBJECTS.clear()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    scene = bpy.context.scene
    scene.name = "BC_HighRes_S4_v002"
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"
    scene.render.dither_intensity = 1.0
    scene.render.film_transparent = False
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.012, 0.016, 0.024, 1.0)
    background.inputs["Strength"].default_value = 0.28
    scene.view_settings.look = "AgX - Medium High Contrast"

    sculpt_col = bpy.data.collections.new("BC_S4_v002_SculptSubtools")
    detail_col = bpy.data.collections.new("BC_S4_v002_Details")
    camera_col = bpy.data.collections.new("BC_S4_v002_Cameras")
    studio_col = bpy.data.collections.new("BC_S4_v002_Studio")
    scene.collection.children.link(sculpt_col)
    scene.collection.children.link(detail_col)
    scene.collection.children.link(camera_col)
    scene.collection.children.link(studio_col)

    mats = {
        "blue": base.material("BC_S4_v002_Blue", base.rgba("#2F6FB4"), 0.64, 0.18),
        "blue_dark": base.material("BC_S4_v002_LidBlue", base.rgba("#1E4F88"), 0.68, 0.15),
        "cream": base.material("BC_S4_v002_Cream", base.rgba("#D7D3C8"), 0.66, 0.18),
        "pink": base.material("BC_S4_v002_Pink", base.rgba("#D66F8E"), 0.62, 0.18),
        "green": base.material("BC_S4_v002_Iris", base.rgba("#72A936"), 0.48, 0.22),
        "dark": base.material("BC_S4_v002_Dark", base.rgba("#050707"), 0.42, 0.22),
        "white": base.material("BC_S4_v002_Highlight", base.rgba("#FCFAF3"), 0.38, 0.22),
        "floor": base.material("BC_S4_v002_Floor", (0.030, 0.040, 0.060, 1.0), 0.84, 0.12),
    }

    root = bpy.data.objects.new("BC_HighRes_v002_ROOT", None)
    sculpt_col.objects.link(root)
    root["production_section"] = 4
    root["source_blockout"] = "BC_Blockout_v001.blend"
    root["rebuild_reason"] = "organic sculpt replacement for rejected v001"

    body = implicit_sculpt("BC_v002_BodySculpt", build_body_elements(), mats["blue"], sculpt_col, 0.006)

    tail_points = [
        (0.045, 0.060, 0.325),
        (0.060, 0.145, 0.300),
        (0.085, 0.235, 0.282),
        (0.120, 0.325, 0.282),
        (0.165, 0.415, 0.310),
        (0.210, 0.495, 0.365),
        (0.252, 0.545, 0.430),
    ]
    tail = base.tube_curve(
        "BC_v002_TailSculpt",
        tail_points,
        [1.55, 1.40, 1.22, 1.08, 0.98, 0.89, 0.82],
        0.060,
        mats["blue"],
        sculpt_col,
        False,
    )
    tail.data.resolution_u = 36
    tail.data.bevel_resolution = 10
    tail.data.use_fill_caps = True

    rounded_ear("BC_v002_Ear_L", (-0.218, 0.010, 1.270), -1.0, mats["blue"], mats["pink"], detail_col)
    rounded_ear("BC_v002_Ear_R", (0.218, 0.010, 1.270), 1.0, mats["blue"], mats["pink"], detail_col)

    # Three small tapered hair tufts replace the rejected ball-like crown.
    for name, x, z, tilt in (
        ("L", -0.035, 1.312, -12),
        ("C", 0.000, 1.320, 0),
        ("R", 0.035, 1.312, 12),
    ):
        tuft = base.tapered_ear(
            f"BC_v002_Tuft_{name}",
            (x, 0.000, z),
            0.050,
            0.052,
            0.080,
            mats["blue"],
            detail_col,
            False,
            math.radians(tilt),
            10,
            28,
        )
        bevel = tuft.modifiers.new(f"BC_v002_Tuft_{name}_Softness", "BEVEL")
        bevel.width = 0.006
        bevel.segments = 3

    # Shallow eye caps.  Most of each white is inside the head; the blue rim is
    # a surface-level line rather than a protruding torus.
    for label, x in (("L", -0.100), ("R", 0.100)):
        base.sphere(f"BC_v002_EyeWhite_{label}", (x, -0.238, 1.055), (0.092, 0.018, 0.116), mats["cream"], detail_col, False, 64, 32)
        ellipse_rim(f"BC_v002_Eyelid_{label}", x, -0.247, 1.055, 0.097, 0.121, 0.0040, mats["blue_dark"], detail_col)
        base.sphere(f"BC_v002_Iris_{label}", (x, -0.254, 1.055), (0.049, 0.0022, 0.068), mats["green"], detail_col, False, 48, 24)
        base.sphere(f"BC_v002_Pupil_{label}", (x, -0.257, 1.055), (0.021, 0.0018, 0.047), mats["dark"], detail_col, False, 40, 20)
        base.sphere(f"BC_v002_EyeGlint_{label}", (x - 0.013, -0.260, 1.084), (0.010, 0.0015, 0.015), mats["white"], detail_col, False, 24, 12)

    # Unified implicit muzzle, never two intersecting sphere props.
    muzzle_elements = [
        ((-0.052, -0.245, 0.895), (0.155, 0.105, 0.125), 2.0),
        ((0.052, -0.245, 0.895), (0.155, 0.105, 0.125), 2.0),
        ((0.000, -0.230, 0.842), (0.145, 0.085, 0.085), 2.0),
    ]
    implicit_sculpt("BC_v002_MuzzleSculpt", muzzle_elements, mats["cream"], detail_col, 0.0045)
    base.rounded_nose("BC_v002_Nose", (0.0, -0.309, 0.925), 0.082, 0.038, 0.055, mats["dark"], detail_col)
    base.line_curve("BC_v002_Mouth_L", [(0.0, -0.313, 0.892), (-0.018, -0.315, 0.862), (-0.052, -0.310, 0.852)], 0.005, mats["dark"], detail_col)
    base.line_curve("BC_v002_Mouth_R", [(0.0, -0.313, 0.892), (0.018, -0.315, 0.862), (0.052, -0.310, 0.852)], 0.005, mats["dark"], detail_col)

    for label, x, angle in (("L", -0.132, -10), ("R", 0.132, 10)):
        brow = base.sphere(f"BC_v002_Brow_{label}", (x, -0.225, 1.190), (0.058, 0.013, 0.016), mats["cream"], detail_col, False, 36, 18)
        brow.rotation_euler[1] = math.radians(angle)

    # Surface-seated belly and palm markings.
    base.sphere("BC_v002_BellyPatch", (0.0, -0.168, 0.490), (0.137, 0.020, 0.185), mats["cream"], detail_col, False, 56, 28)
    for label, sign in (("L", -1.0), ("R", 1.0)):
        # A paper-thin dome sits just above the evaluated hand surface.  Its
        # back remains buried, but the perimeter cannot be cut by the blue
        # sculpt or read as a hovering solid pad.
        base.sphere(f"BC_v002_PalmPatch_{label}", (sign * 0.418, -0.0885, 0.288), (0.042, 0.0035, 0.050), mats["cream"], detail_col, False, 40, 20)
        for index, offset in enumerate((-0.052, 0.0, 0.052), 1):
            base.sphere(f"BC_v002_Toe_{index}_{label}", (sign * 0.150 + offset, -0.169, 0.072), (0.040, 0.018, 0.036), mats["cream"], detail_col, False, 32, 16)

    # Tail tip overlaps the last blue implicit volume by half its length.
    tail_tip = base.sphere("BC_v002_TailTip", (0.252, 0.545, 0.430), (0.062, 0.062, 0.090), mats["cream"], detail_col, False, 48, 24)
    tail_tip.rotation_euler[0] = math.radians(-22)

    for sign, label in ((-1.0, "L"), (1.0, "R")):
        for index, zoff in enumerate((0.028, 0.0, -0.028), 1):
            base.line_curve(
                f"BC_v002_Whisker_{index}_{label}",
                [(sign * 0.135, -0.266, 0.910 + zoff), (sign * 0.200, -0.272, 0.915 + zoff), (sign * 0.255, -0.255, 0.922 + zoff * 0.7)],
                0.0045,
                mats["cream"],
                detail_col,
            )

    for obj in base.RENDER_OBJECTS:
        obj.parent = root
    for mesh in bpy.data.meshes:
        for uv_layer in list(mesh.uv_layers):
            mesh.uv_layers.remove(uv_layer)

    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.006))
    floor = bpy.context.object
    floor.name = "BC_S4_v002_StudioFloor"
    base.move(floor, studio_col)
    base.assign(floor, mats["floor"])
    for uv_layer in list(floor.data.uv_layers):
        floor.data.uv_layers.remove(uv_layer)

    base.area_light("BC_S4_v002_Key", (-3.0, -4.0, 4.0), 680.0, 4.0, (1.0, 0.92, 0.84), studio_col)
    base.area_light("BC_S4_v002_Fill", (3.4, -2.0, 2.8), 390.0, 3.2, (0.72, 0.84, 1.0), studio_col)
    base.area_light("BC_S4_v002_Rim", (0.5, 3.8, 3.0), 560.0, 2.6, (0.62, 0.78, 1.0), studio_col)
    base.area_light("BC_S4_v002_Top", (0.0, 0.0, 5.0), 280.0, 2.0, (1.0, 1.0, 1.0), studio_col)

    cameras = {
        "front": base.camera("CAM_S4_v002_FRONT", (0.0, -5.0, 0.70), (0.0, 0.0, 0.70), 1.70, camera_col),
        "side": base.camera("CAM_S4_v002_SIDE", (-5.0, 0.0, 0.70), (0.0, 0.0, 0.70), 1.70, camera_col),
        "back": base.camera("CAM_S4_v002_BACK", (0.0, 5.0, 0.70), (0.0, 0.0, 0.70), 1.70, camera_col),
        "three_quarter": base.camera("CAM_S4_v002_3Q", (3.8, -3.8, 0.80), (0.0, 0.0, 0.70), 1.72, camera_col),
        "face": base.camera("CAM_S4_v002_FACE", (0.0, -3.0, 1.04), (0.0, 0.0, 1.04), 0.72, camera_col),
        "hand": base.camera("CAM_S4_v002_HAND", (0.418, -2.5, 0.285), (0.418, 0.0, 0.285), 0.40, camera_col),
        "tail": base.camera("CAM_S4_v002_TAIL", (-2.8, 0.0, 0.355), (0.08, 0.36, 0.350), 0.70, camera_col),
    }
    scene["section_4_status"] = "v002_organic_sculpt_early_review"
    scene["no_uvs"] = True
    scene["no_rig"] = True
    return scene, mats, cameras, root, floor, body


def render_early(scene, cameras):
    RENDERS.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    for key, filename in {
        "front": "S4_BlueCat_OrganicClay_Front_v002.png",
        "side": "S4_BlueCat_OrganicClay_Side_v002.png",
        "three_quarter": "S4_BlueCat_OrganicClay_ThreeQuarter_v002.png",
        "face": "S4_BlueCat_OrganicClay_Face_v002.png",
        "hand": "S4_BlueCat_OrganicClay_Hand_v002.png",
        "tail": "S4_BlueCat_OrganicClay_Tail_v002.png",
    }.items():
        scene.camera = cameras[key]
        scene.render.filepath = str(RENDERS / filename)
        bpy.ops.render.render(write_still=True)
        print(f"RENDERED: {scene.render.filepath}")


def audit(body):
    points = []
    for obj in base.RENDER_OBJECTS:
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    body.data.calc_loop_triangles()
    print(f"V002_HEIGHT_M={max(p.z for p in points) - min(p.z for p in points):.4f}")
    print(f"V002_BODY_VERTS={len(body.data.vertices)} V002_BODY_TRIS={len(body.data.loop_triangles)}")
    print(f"V002_VISIBLE_OBJECTS={len(base.RENDER_OBJECTS)}")
    print(f"V002_UV_LAYERS={sum(len(mesh.uv_layers) for mesh in bpy.data.meshes)}")
    print(f"V002_ARMATURES={sum(1 for obj in bpy.data.objects if obj.type == 'ARMATURE')}")


def main():
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    scene, mats, cameras, root, floor, body = build_scene()
    audit(body)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    print(f"SAVED: {BLEND_PATH}")
    render_early(scene, cameras)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)


if __name__ == "__main__":
    main()
