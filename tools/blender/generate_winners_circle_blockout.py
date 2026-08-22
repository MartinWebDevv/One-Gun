"""Generate the modular One Gun Winners Circle blockout in Blender.

Run with:
    blender.exe --background --python tools/blender/generate_winners_circle_blockout.py

The master .blend and three origin-aligned GLBs are deterministic outputs. The
Godot stage scene instances the GLBs separately so final art can replace the
shell, podiums, or decor without changing the runtime result/ready contract.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = PROJECT_ROOT / "art_src" / "winners_circle" / "blockout" / "winners_circle_blockout.blend"
EXPORT_DIR = PROJECT_ROOT / "models" / "winners_circle" / "blockout"
FONT_PATH = PROJECT_ROOT / "fonts" / "Fredoka-VariableFont_wdth,wght.ttf"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)
    base = bpy.data.collections.get("Collection")
    if base is not None:
        base.name = "WC_Shell"
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def collection(name: str) -> bpy.types.Collection:
    result = bpy.data.collections.get(name)
    if result is None:
        result = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(result)
    return result


def move_to_collection(obj: bpy.types.Object, target: bpy.types.Collection) -> None:
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    target.objects.link(obj)


def material(
    name: str,
    color: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.45,
    emission: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1.0)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission is not None:
            emission_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
            strength_input = bsdf.inputs.get("Emission Strength")
            if emission_input is not None:
                emission_input.default_value = (*emission, 1.0)
            if strength_input is not None:
                strength_input.default_value = emission_strength
    return mat


def apply_material(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    if hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)


def bevel(obj: bpy.types.Object, width: float, segments: int = 3) -> None:
    if width <= 0.0 or obj.type != "MESH":
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new(name="BlockoutBevel", type="BEVEL")
    modifier.width = width
    modifier.segments = segments
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    target: bpy.types.Collection,
    bevel_width: float = 0.06,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    apply_material(obj, mat)
    move_to_collection(obj, target)
    bevel(obj, bevel_width)
    return obj


def add_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    target: bpy.types.Collection,
    vertices: int = 48,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel_width: float = 0.04,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    apply_material(obj, mat)
    move_to_collection(obj, target)
    bevel(obj, bevel_width, 2)
    return obj


def add_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_material(obj, mat)
    move_to_collection(obj, target)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)
    return obj


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
    target: bpy.types.Collection,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=64,
        minor_segments=8,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    apply_material(obj, mat)
    move_to_collection(obj, target)
    return obj


def add_extruded_polygon(
    name: str,
    points: list[tuple[float, float]],
    location: tuple[float, float, float],
    depth: float,
    mat: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    half = depth * 0.5
    vertices = [(x, -half, z) for x, z in points] + [(x, half, z) for x, z in points]
    count = len(points)
    faces: list[tuple[int, ...]] = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    target.objects.link(obj)
    apply_material(obj, mat)
    bevel(obj, min(depth * 0.2, 0.035), 2)
    return obj


def add_star(
    name: str,
    location: tuple[float, float, float],
    outer_radius: float,
    inner_radius: float,
    depth: float,
    mat: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    points: list[tuple[float, float]] = []
    for index in range(10):
        angle = math.radians(90.0 + index * 36.0)
        radius = outer_radius if index % 2 == 0 else inner_radius
        points.append((math.cos(angle) * radius, math.sin(angle) * radius))
    return add_extruded_polygon(name, points, location, depth, mat, target)


def add_text(
    name: str,
    text: str,
    location: tuple[float, float, float],
    size: float,
    extrude: float,
    mat: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.object.text_add(location=location, rotation=(math.radians(90.0), 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = extrude
    obj.data.bevel_depth = min(extrude * 0.35, 0.025)
    obj.data.bevel_resolution = 2
    if FONT_PATH.exists():
        obj.data.font = bpy.data.fonts.load(str(FONT_PATH))
    apply_material(obj, mat)
    move_to_collection(obj, target)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    obj.select_set(False)
    return obj


def add_cable(
    name: str,
    points: list[tuple[float, float, float]],
    mat: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = 0.018
    curve.bevel_resolution = 2
    spline = curve.splines.new(type="POLY")
    spline.points.add(len(points) - 1)
    for point, value in zip(spline.points, points):
        point.co = (*value, 1.0)
    obj = bpy.data.objects.new(name, curve)
    target.objects.link(obj)
    apply_material(obj, mat)
    return obj


def add_reference_light(
    name: str,
    light_type: str,
    location: tuple[float, float, float],
    energy: float,
    color: tuple[float, float, float],
    target: bpy.types.Collection,
    size: float = 5.0,
) -> bpy.types.Object:
    data = bpy.data.lights.new(name=f"{name}Data", type=light_type)
    data.energy = energy
    data.color = color
    if light_type == "AREA":
        data.shape = "DISK"
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    target.objects.link(obj)
    return obj


def point_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_scene() -> dict[str, bpy.types.Collection]:
    reset_scene()
    shell = collection("WC_Shell")
    podiums = collection("WC_Podiums")
    decor = collection("WC_Decor")
    reference = collection("WC_Reference")

    navy = material("WC_Navy", (0.015, 0.025, 0.075), metallic=0.12, roughness=0.34)
    navy_mid = material("WC_NavyMid", (0.025, 0.055, 0.14), metallic=0.18, roughness=0.32)
    near_black = material("WC_Black", (0.006, 0.009, 0.018), metallic=0.1, roughness=0.38)
    wood = material("WC_Wood", (0.075, 0.028, 0.012), metallic=0.0, roughness=0.58)
    curtain = material("WC_Curtain", (0.10, 0.008, 0.018), metallic=0.0, roughness=0.72)
    gold = material("WC_Gold", (0.68, 0.34, 0.035), metallic=0.85, roughness=0.22)
    gold_dark = material("WC_GoldDark", (0.19, 0.075, 0.008), metallic=0.72, roughness=0.30)
    gold_glow = material(
        "WC_GoldGlow",
        (0.72, 0.28, 0.018),
        metallic=0.28,
        roughness=0.24,
        emission=(1.0, 0.22, 0.012),
        emission_strength=7.5,
    )
    hero_sign_glow = material(
        "WC_HeroSignGlow",
        (0.46, 0.16, 0.012),
        metallic=0.20,
        roughness=0.30,
        emission=(0.86, 0.13, 0.006),
        emission_strength=2.4,
    )
    bulb = material(
        "WC_BulbGlow",
        (0.95, 0.42, 0.08),
        roughness=0.18,
        emission=(1.0, 0.25, 0.02),
        emission_strength=12.0,
    )
    cable = material("WC_Cable", (0.012, 0.008, 0.006), roughness=0.8)
    silver = material("WC_Silver", (0.32, 0.40, 0.54), metallic=0.76, roughness=0.24)
    bronze = material("WC_Bronze", (0.34, 0.12, 0.035), metallic=0.74, roughness=0.27)
    green = material("WC_Green", (0.035, 0.18, 0.075), metallic=0.28, roughness=0.33)
    blue = material("WC_Blue", (0.025, 0.12, 0.36), metallic=0.30, roughness=0.31)
    red = material("WC_Red", (0.34, 0.025, 0.018), metallic=0.18, roughness=0.38)

    # Hero shell: circular stage, inset lighting, back wall, beams and curtains.
    add_cylinder("StageDisk", (0.0, 0.0, 0.16), 7.8, 0.32, navy, shell, vertices=64, bevel_width=0.08)
    add_cylinder("StageInnerDisk", (0.0, -0.12, 0.34), 6.65, 0.08, near_black, shell, vertices=64, bevel_width=0.02)
    add_torus("StageGoldRing", (0.0, -0.10, 0.40), 6.62, 0.075, gold_glow, shell)
    for index in range(24):
        angle = math.tau * index / 24.0
        add_box(
            f"FloorLight_{index:02d}",
            (math.cos(angle) * 6.15, math.sin(angle) * 6.15, 0.43),
            (0.34, 0.12, 0.035),
            gold_glow,
            shell,
            bevel_width=0.015,
            rotation=(0.0, 0.0, angle),
        )
    add_box("BackWall", (0.0, 3.20, 3.60), (15.8, 0.30, 7.2), near_black, shell, 0.05)
    add_box("TopBeam", (0.0, 2.82, 7.05), (15.8, 0.55, 0.42), wood, shell, 0.08)
    add_box("LeftBeam", (-7.48, 2.82, 3.75), (0.48, 0.55, 6.9), wood, shell, 0.08)
    add_box("RightBeam", (7.48, 2.82, 3.75), (0.48, 0.55, 6.9), wood, shell, 0.08)
    add_box("LeftCurtain", (-7.02, 2.58, 3.80), (0.75, 0.20, 6.55), curtain, shell, 0.10)
    add_box("RightCurtain", (7.02, 2.58, 3.80), (0.75, 0.20, 6.55), curtain, shell, 0.10)
    add_cylinder(
        "RearMedallion", (0.0, 2.72, 4.15), 3.75, 0.24, gold_dark, shell,
        vertices=64, rotation=(math.radians(90.0), 0.0, 0.0), bevel_width=0.05,
    )
    add_cylinder(
        "RearMedallionFace", (0.0, 2.56, 4.15), 3.48, 0.10, near_black, shell,
        vertices=64, rotation=(math.radians(90.0), 0.0, 0.0), bevel_width=0.03,
    )
    add_torus(
        "RearMedallionGlow", (0.0, 2.46, 4.15), 3.45, 0.055, hero_sign_glow, shell,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )

    # Shelves and low-cost toy-box silhouettes create the concept-art depth.
    for side_index, x in enumerate((-5.2, 5.2)):
        for shelf_index, z in enumerate((1.25, 2.55, 3.85)):
            add_box(f"Shelf_{side_index}_{shelf_index}", (x, 2.32, z), (3.0, 0.52, 0.16), wood, decor, 0.025)
        for prop_index in range(9):
            row = prop_index // 3
            column_index = prop_index % 3
            prop_x = x - 0.92 + column_index * 0.92
            prop_z = 1.57 + row * 1.30
            prop_mat = (blue, red, green, gold_dark)[(prop_index + side_index) % 4]
            if prop_index % 3 == 0:
                add_sphere(
                    f"ToyBall_{side_index}_{prop_index}",
                    (prop_x, 2.03, prop_z),
                    (0.25, 0.25, 0.25), prop_mat, decor,
                )
            else:
                add_box(
                    f"ToyCrate_{side_index}_{prop_index}",
                    (prop_x, 2.05, prop_z),
                    (0.50, 0.45, 0.48), prop_mat, decor, 0.055,
                )

    # Banners retain crisp real text and symbols rather than AI-generated type.
    banner_points = [(-0.92, 1.55), (0.92, 1.55), (0.92, -0.78), (0.0, -1.50), (-0.92, -0.78)]
    inner_points = [(-0.76, 1.38), (0.76, 1.38), (0.76, -0.68), (0.0, -1.25), (-0.76, -0.68)]
    for side_index, x in enumerate((-6.22, 6.22)):
        add_extruded_polygon(f"BannerGold_{side_index}", banner_points, (x, 2.26, 4.62), 0.12, gold, decor)
        add_extruded_polygon(f"BannerNavy_{side_index}", inner_points, (x, 2.10, 4.62), 0.08, navy_mid, decor)
        add_text(f"BannerOG_{side_index}", "OG", (x, 2.00, 5.30), 0.92, 0.035, gold_glow, decor)
        add_star(f"BannerStar_{side_index}", (x, 2.00, 3.98), 0.48, 0.22, 0.08, gold, decor)

    # Central sign hierarchy.
    add_text("OneGunSign", "ONE GUN", (0.0, 2.30, 4.05), 1.48, 0.075, hero_sign_glow, decor)
    add_text("WinnersCircleSign", "WINNERS CIRCLE", (0.0, 2.26, 6.18), 0.50, 0.050, gold, decor)
    add_star("SignStarLeft", (-3.10, 2.24, 6.18), 0.22, 0.10, 0.07, gold, decor)
    add_star("SignStarRight", (3.10, 2.24, 6.18), 0.22, 0.10, 0.07, gold, decor)

    # String lights: emissive meshes in the export, a few real lights in Godot.
    light_points: list[tuple[float, float, float]] = []
    for index in range(13):
        x = -6.4 + index * (12.8 / 12.0)
        normalized = abs(index - 6) / 6.0
        z = 6.72 + normalized * 0.42
        light_points.append((x, 0.95, z))
        add_sphere(f"HangingBulb_{index:02d}", (x, 0.95, z - 0.13), (0.085, 0.085, 0.13), bulb, decor)
    add_cable("StringLightCable", light_points, cable, decor)

    # Independently exported podium kit. Front is negative Blender Y / positive Godot Z.
    podium_specs = [
        ("Second", -3.2, 0.18, 0.94, 2.55, 2.15, 1.20, silver, blue, "2"),
        ("First", 0.0, 0.00, 1.22, 2.85, 2.28, 1.76, gold, gold_dark, "1"),
        ("Third", 3.2, 0.34, 0.80, 2.55, 2.15, 0.94, bronze, green, "3"),
    ]
    for label, x, y, height, width, depth, body_height, body_mat, accent_mat, rank in podium_specs:
        floor_top = 0.43
        add_box(
            f"Podium{label}",
            (x, y, floor_top + body_height * 0.5),
            (width, depth, body_height),
            body_mat, podiums, 0.11,
        )
        add_box(
            f"Podium{label}Top",
            (x, y, floor_top + body_height + 0.07),
            (width + 0.12, depth + 0.12, 0.14),
            accent_mat, podiums, 0.04,
        )
        medallion_z = floor_top + body_height * 0.52
        front_y = y - depth * 0.51
        add_cylinder(
            f"Podium{label}Medallion", (x, front_y, medallion_z), 0.53, 0.10,
            accent_mat, podiums, vertices=48,
            rotation=(math.radians(90.0), 0.0, 0.0), bevel_width=0.025,
        )
        add_text(
            f"Podium{label}Rank", rank, (x, front_y - 0.08, medallion_z),
            0.66, 0.035, gold if label != "Second" else silver, podiums,
        )
        add_box(
            f"Podium{label}Nameplate", (x, front_y - 0.04, 0.28),
            (width + 0.36, 0.42, 0.34), near_black, podiums, 0.07,
        )
        add_star(
            f"Podium{label}NameStarLeft", (x - width * 0.42, front_y - 0.27, 0.28),
            0.11, 0.05, 0.04, body_mat, podiums,
        )
        add_star(
            f"Podium{label}NameStarRight", (x + width * 0.42, front_y - 0.27, 0.28),
            0.11, 0.05, 0.04, body_mat, podiums,
        )

    # Small trophy landing plinth in front of the champion.
    add_cylinder("TrophyLandingPlinth", (0.0, -1.62, 0.54), 0.58, 0.24, gold_dark, podiums, vertices=48, bevel_width=0.04)
    add_torus("TrophyLandingGlow", (0.0, -1.62, 0.68), 0.44, 0.035, gold_glow, podiums)

    # Reference-only camera/lights make the .blend immediately inspectable.
    camera_data = bpy.data.cameras.new("WinnersCircleReferenceCameraData")
    camera_data.lens = 52.0
    camera = bpy.data.objects.new("WinnersCircleReferenceCamera", camera_data)
    camera.location = (0.0, -15.2, 4.65)
    point_at(camera, (0.0, 0.25, 2.75))
    reference.objects.link(camera)
    bpy.context.scene.camera = camera
    key = add_reference_light("ReferenceKey", "AREA", (-4.5, -5.0, 7.8), 1050.0, (1.0, 0.35, 0.10), reference, 6.0)
    point_at(key, (0.0, 0.0, 2.4))
    fill = add_reference_light("ReferenceFill", "AREA", (4.8, -2.0, 5.5), 700.0, (0.12, 0.22, 1.0), reference, 5.0)
    point_at(fill, (0.0, 0.0, 2.1))
    champion = add_reference_light("ReferenceChampion", "AREA", (0.0, -1.5, 7.4), 1200.0, (1.0, 0.46, 0.08), reference, 3.5)
    point_at(champion, (0.0, 0.0, 1.6))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.002, 0.004, 0.012)
    return {"shell": shell, "podiums": podiums, "decor": decor, "reference": reference}


def export_collection(target: bpy.types.Collection, filename: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in target.all_objects:
        if obj.type in {"MESH", "CURVE"}:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_DIR / filename),
        export_format="GLB",
        use_selection=True,
        export_cameras=False,
        export_lights=False,
    )


def main() -> None:
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    collections = build_scene()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    export_collection(collections["shell"], "wc_stage_shell_blockout.glb")
    export_collection(collections["podiums"], "wc_podiums_blockout.glb")
    export_collection(collections["decor"], "wc_decor_blockout.glb")
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"WINNERS_CIRCLE_BLEND={BLEND_PATH}")
    print(f"WINNERS_CIRCLE_EXPORT_DIR={EXPORT_DIR}")


if __name__ == "__main__":
    main()
