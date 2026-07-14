# Blender 5.x headless generator for the Western V2 map assets.
# Run:  & "D:\Blender\blender.exe" --background --factory-startup --python "tools/gen_western_assets.py"
# Exports low-poly stylized .glb files into models/westernV2/.

import bpy
import bmesh
import math
import random
import os
from mathutils import Vector, Matrix, noise

OUT_DIR = r"D:\Godot Projects\one-gun\models\westernV2"

COL = {
    "wood_light":  (0.55, 0.42, 0.28, 1.0),
    "wood_mid":    (0.42, 0.30, 0.19, 1.0),
    "wood_red":    (0.48, 0.20, 0.13, 1.0),
    "wood_gray":   (0.38, 0.34, 0.30, 1.0),
    "trim":        (0.78, 0.72, 0.60, 1.0),
    "inset":       (0.07, 0.055, 0.045, 1.0),
    "roof_dark":   (0.25, 0.18, 0.12, 1.0),
    "sandstone":   (0.78, 0.47, 0.26, 1.0),
    "sandstone_d": (0.62, 0.35, 0.20, 1.0),
    "sand":        (0.82, 0.66, 0.42, 1.0),
    "scrub":       (0.66, 0.55, 0.34, 1.0),
    "hay":         (0.80, 0.66, 0.28, 1.0),
    "metal":       (0.48, 0.47, 0.45, 1.0),
    "white":       (0.85, 0.83, 0.78, 1.0),
    "water_dark":  (0.25, 0.33, 0.35, 1.0),
}

_materials = {}

def mat(name, color, roughness=0.92):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    _materials[name] = m
    return m

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

def new_object(name):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj

def finish(obj, bm, mats):
    bm.to_mesh(obj.data)
    bm.free()
    for m in mats:
        obj.data.materials.append(m)
    for poly in obj.data.polygons:
        poly.use_smooth = False

def export_glb(obj, filename, extra=None):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    if extra:
        for e in extra:
            e.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, filename),
                              export_format='GLB', use_selection=True)
    print("EXPORTED", filename)

def add_box(bm, center, size, mat_idx, rot_z=0.0, rot_x=0.0):
    # size = HALF-extents (create_cube verts sit at +/-0.5, so double)
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    rot = Matrix.Rotation(rot_z, 4, 'Z') @ Matrix.Rotation(rot_x, 4, 'X')
    for v in tmp.verts:
        v.co = Vector((v.co.x * size[0] * 2, v.co.y * size[1] * 2, v.co.z * size[2] * 2))
        v.co = rot @ v.co
        v.co += Vector(center)
    for f in tmp.faces:
        f.material_index = mat_idx
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)

def add_cyl(bm, base, r1, r2, depth, segs, mat_idx, rot_x=0.0):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    rot = Matrix.Rotation(rot_x, 4, 'X')
    for v in tmp.verts:
        v.co.z += depth / 2
        v.co = rot @ v.co
        v.co += Vector(base)
    for f in tmp.faces:
        f.material_index = mat_idx
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)

# ---------- buildings ----------

def make_false_front(name, seed, w, d, h, wall_key, trim_key):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_" + wall_key, COL[wall_key]), mat("W_" + trim_key, COL[trim_key]),
            mat("W_inset", COL["inset"]), mat("W_roof", COL["roof_dark"])]
    # body ("front" faces -Y)
    add_box(bm, (0, 0, h / 2), (w / 2, d / 2, h / 2), 0)
    # flat roof cap
    add_box(bm, (0, 0.1, h + 0.06), (w / 2 - 0.05, d / 2 - 0.02, 0.08), 3)
    # false front parapet (taller than body, at front)
    front_y = -d / 2 - 0.06
    add_box(bm, (0, front_y, (h + 1.1) / 2), (w / 2 + 0.12, 0.06, (h + 1.1) / 2), 1)
    # parapet top trim
    add_box(bm, (0, front_y, h + 1.16), (w / 2 + 0.22, 0.10, 0.09), 1)
    # sign board
    add_box(bm, (0, front_y - 0.08, h - 0.25), (w / 2 - 0.35, 0.05, 0.30), 2)
    # door + windows (dark insets on the front)
    add_box(bm, (0, front_y - 0.05, 1.05), (0.5, 0.05, 1.05), 2)
    for wx in (-w / 4 - 0.25, w / 4 + 0.25):
        add_box(bm, (wx, front_y - 0.05, 1.45), (0.38, 0.05, 0.55), 2)
    # porch awning + posts
    add_box(bm, (0, front_y - 1.0, h - 0.65), (w / 2 + 0.1, 1.05, 0.06), 3, rot_x=math.radians(6))
    for px in (-w / 2 + 0.25, w / 2 - 0.25):
        add_box(bm, (px, front_y - 1.85, (h - 0.85) / 2), (0.07, 0.07, (h - 0.85) / 2), 1)
    # boardwalk slab under porch
    add_box(bm, (0, front_y - 1.0, 0.10), (w / 2 + 0.1, 1.15, 0.10), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_church(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_white", COL["white"]), mat("W_roof", COL["roof_dark"]), mat("W_inset", COL["inset"])]
    # nave (half-extents 2.4 x 3.4 x 1.7 => 4.8 wide, 6.8 long, 3.4 tall)
    add_box(bm, (0, 0.6, 1.7), (2.4, 3.4, 1.7), 0)
    # pitched roof: two slabs meeting at a ridge over the nave
    slab_half = 1.55   # half-length of each slope
    pitch = math.radians(35)
    ridge_z = 3.4 + 2.4 * math.tan(pitch) * 0.92
    for side, ang in ((-1, pitch), (1, -pitch)):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        rot = Matrix.Rotation(ang, 4, 'Y')
        for v in tmp.verts:
            v.co = Vector((v.co.x * slab_half * 2, v.co.y * 3.7 * 2, v.co.z * 0.16))
            v.co = rot @ v.co
            v.co += Vector((side * 1.25, 0.6, (3.35 + ridge_z) / 2.0))
        for f in tmp.faces:
            f.material_index = 1
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    # tower at front
    add_box(bm, (0, -3.4, 2.6), (0.95, 0.95, 2.6), 0)
    # spire
    add_cyl(bm, (0, -3.4, 5.2), 1.05, 0.02, 1.9, 4, 1)
    # door
    add_box(bm, (0, -4.38, 1.0), (0.45, 0.05, 1.0), 2)
    # cross
    add_box(bm, (0, -3.4, 7.35), (0.05, 0.05, 0.35), 0)
    add_box(bm, (0, -3.4, 7.5), (0.22, 0.05, 0.05), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_water_tower(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_wood_mid", COL["wood_mid"]), mat("W_roof", COL["roof_dark"]), mat("W_trim", COL["trim"])]
    # 4 legs, slightly splayed
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            t = (v.co.z + 0.5)
            spread = 1.35 - t * 0.45
            v.co = Vector((v.co.x * 0.18 + sx * spread, v.co.y * 0.18 + sy * spread, v.co.z * 5.2 + 2.6))
        for f in tmp.faces:
            f.material_index = 0
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    # cross braces
    add_box(bm, (0, 0, 2.4), (1.25, 0.05, 0.06), 0)
    add_box(bm, (0, 0, 2.4), (0.05, 1.25, 0.06), 0)
    # platform (ring must be wider than the 1.0m player capsule: half 2.5 - tank 1.32 = 1.18m)
    add_box(bm, (0, 0, 5.25), (2.8, 2.8, 0.08), 2)
    # perimeter guard rail
    for sx, sy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        add_box(bm, (sx * 2.75, sy * 2.75, 6.35), (0.05 if sx else 2.8, 0.05 if sy else 2.8, 0.04), 0)
    for cx, cy in ((-2.75, -2.75), (2.75, -2.75), (-2.75, 2.75), (2.75, 2.75)):
        add_box(bm, (cx, cy, 5.85), (0.05, 0.05, 0.52), 0)
    # tank
    add_cyl(bm, (0, 0, 5.35), 1.25, 1.18, 1.9, 12, 0)
    # tank bands
    add_cyl(bm, (0, 0, 5.7), 1.28, 1.28, 0.07, 12, 2)
    add_cyl(bm, (0, 0, 6.6), 1.24, 1.24, 0.07, 12, 2)
    # conical roof
    add_cyl(bm, (0, 0, 7.25), 1.38, 0.03, 0.85, 12, 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_windmill(name):
    clear_scene()
    # tower + head as root mesh; blades as separate named child for spinning
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    tower = new_object("Tower")
    bm = bmesh.new()
    mats = [mat("W_wood_gray", COL["wood_gray"]), mat("W_metal", COL["metal"])]
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            t = (v.co.z + 0.5)
            spread = 1.05 - t * 0.75
            v.co = Vector((v.co.x * 0.16 + sx * spread, v.co.y * 0.16 + sy * spread, v.co.z * 6.8 + 3.4))
        for f in tmp.faces:
            f.material_index = 0
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    add_box(bm, (0, 0, 2.2), (0.95, 0.05, 0.06), 0)
    add_box(bm, (0, 0, 2.2), (0.05, 0.95, 0.06), 0)
    add_box(bm, (0, 0, 4.6), (0.62, 0.05, 0.06), 0)
    add_box(bm, (0, 0, 4.6), (0.05, 0.62, 0.06), 0)
    # head + tail vane
    add_box(bm, (0, 0.15, 7.0), (0.22, 0.5, 0.22), 1)
    add_box(bm, (0, 1.0, 7.05), (0.04, 0.5, 0.3), 1)
    finish(tower, bm, mats)
    tower.parent = root
    # blades: separate object named "Blades"
    blades = new_object("Blades")
    bb = bmesh.new()
    bmats = [mat("W_metal", COL["metal"]), mat("W_trim", COL["trim"])]
    for i in range(10):
        ang = i * math.tau / 10
        tmp = bmesh.new()
        v0 = tmp.verts.new((0.14, 0, 0))
        v1 = tmp.verts.new((1.5, 0, 0.26))
        v2 = tmp.verts.new((1.5, 0, -0.26))
        v3 = tmp.verts.new((0.14, 0, -0.10))
        tmp.faces.new((v0, v1, v2, v3))
        rot = Matrix.Rotation(ang, 4, 'Y')
        for v in tmp.verts:
            v.co = rot @ v.co
        for f in tmp.faces:
            f.material_index = 1 if i % 2 == 0 else 0
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bb.from_mesh(tm); bpy.data.meshes.remove(tm)
    # hub
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=8, radius1=0.16, radius2=0.16, depth=0.2)
    rot = Matrix.Rotation(math.radians(90), 4, 'X')
    for v in tmp.verts:
        v.co = rot @ v.co
    for f in tmp.faces:
        f.material_index = 0
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bb.from_mesh(tm); bpy.data.meshes.remove(tm)
    finish(blades, bb, bmats)
    blades.parent = root
    blades.location = Vector((0, -0.45, 7.0))
    export_glb(root, name + ".glb", extra=[tower, blades])

# ---------- props ----------

def make_hitching_post(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_wood_mid", COL["wood_mid"])]
    for px in (-0.8, 0.8):
        add_box(bm, (px, 0, 0.5), (0.06, 0.06, 0.5), 0)
    add_box(bm, (0, 0, 0.92), (0.95, 0.05, 0.05), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_trough(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_wood_mid", COL["wood_mid"]), mat("W_water", COL["water_dark"], roughness=0.15)]
    add_box(bm, (0, 0, 0.25), (0.9, 0.35, 0.25), 0)
    add_box(bm, (0, 0, 0.42), (0.78, 0.24, 0.03), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_hay_bale(name, seed, stack):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_hay", COL["hay"], roughness=1.0)]
    positions = [(0, 0, 0.35)]
    if stack:
        positions += [(0.95, 0.1, 0.35), (0.45, 0.05, 1.02)]
    for p in positions:
        add_box(bm, p, (0.55, 0.38, 0.35), 0, rot_z=random.uniform(-0.15, 0.15))
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_sand_rock(name, seed, radius):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_sandstone", COL["sandstone"], roughness=1.0), mat("W_sandstone_d", COL["sandstone_d"], roughness=1.0)]
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=2, radius=radius)
    for v in tmp.verts:
        n = noise.noise(v.co * 1.2 + Vector((seed * 7.7, seed * 3.9, seed)))
        v.co += v.normal * n * radius * 0.3
        v.co.z *= 0.7
        v.co.z += radius * 0.5
    for f in tmp.faces:
        f.material_index = 1 if f.calc_center_median().z < radius * 0.35 else 0
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_mesa(name, seed, radius, height):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_sandstone", COL["sandstone"], roughness=1.0), mat("W_sandstone_d", COL["sandstone_d"], roughness=1.0)]
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=12, radius1=radius, radius2=radius * 0.72, depth=height)
    for v in tmp.verts:
        n = noise.noise(Vector((v.co.x * 0.25, v.co.y * 0.25, v.co.z * 0.12)) + Vector((seed, seed, 0)))
        v.co.x += n * radius * 0.22
        v.co.y += n * radius * 0.22
        v.co.z += height / 2
    for f in tmp.faces:
        c = f.calc_center_median()
        band = math.sin(c.z * 0.9 + seed)
        f.material_index = 1 if band > 0.35 else 0
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_stair_flight(name):
    # straight external staircase: 3.4m rise over 5.1m run, ascending +Y
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_wood_mid", COL["wood_mid"]), mat("W_wood_light", COL["wood_light"])]
    steps = 12
    rise, run = 3.4, 5.1
    for i in range(steps):
        sy = i * (run / steps) + (run / steps) / 2
        sz = i * (rise / steps) + (rise / steps) / 2
        add_box(bm, (0, sy, sz), (0.75, run / steps / 2 + 0.02, rise / steps / 2), 1 if i % 2 == 0 else 0)
    # sloped side stringers + handrails
    ang = math.atan2(rise, run)
    length = math.hypot(rise, run) / 2 + 0.2
    for side in (-1, 1):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        rot = Matrix.Rotation(-ang, 4, 'X')
        for v in tmp.verts:
            v.co = Vector((v.co.x * 0.12, v.co.y * length * 2, v.co.z * 0.24))
            v.co = rot @ v.co
            v.co += Vector((side * 0.78, run / 2, rise / 2 - 0.1))
        for f in tmp.faces:
            f.material_index = 0
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bm.from_mesh(tm); bpy.data.meshes.remove(tm)
        # handrail
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            v.co = Vector((v.co.x * 0.05, v.co.y * length * 2, v.co.z * 0.05))
            v.co = rot @ v.co
            v.co += Vector((side * 0.78, run / 2, rise / 2 + 0.85))
        for f in tmp.faces:
            f.material_index = 0
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_catwalk(name):
    # 19m plank bridge along Y with rails and two mid cover panels
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_wood_mid", COL["wood_mid"]), mat("W_wood_light", COL["wood_light"])]
    half_len = 9.5
    planks = 24
    for i in range(planks):
        y = -half_len + (i + 0.5) * (half_len * 2 / planks)
        add_box(bm, (0, y, 0), (0.8, half_len / planks + 0.01, 0.045), 1 if i % 2 == 0 else 0)
    # side rails: posts + top rail
    for side in (-1, 1):
        add_box(bm, (side * 0.78, 0, 1.0), (0.045, half_len, 0.04), 0)
        for i in range(7):
            y = -half_len + 0.5 + i * (half_len * 2 - 1.0) / 6
            add_box(bm, (side * 0.78, y, 0.5), (0.05, 0.05, 0.5), 0)
    # two cover panels on alternating sides
    add_box(bm, (-0.55, -3.2, 0.55), (0.06, 1.0, 0.55), 1)
    add_box(bm, (0.55, 3.2, 0.55), (0.06, 1.0, 0.55), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_roof_walkway(name):
    # short plank connector between adjacent roofs (along X)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_wood_mid", COL["wood_mid"]), mat("W_wood_light", COL["wood_light"])]
    planks = 6
    for i in range(planks):
        x = -1.5 + (i + 0.5) * (3.0 / planks)
        add_box(bm, (x, 0, 0), (3.0 / planks / 2 + 0.01, 0.7, 0.04), 1 if i % 2 == 0 else 0)
    for side in (-1, 1):
        add_box(bm, (0, side * 0.68, 0.06), (1.5, 0.04, 0.03), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_ground(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("W_sand", COL["sand"], roughness=1.0), mat("W_scrub", COL["scrub"], roughness=1.0)]
    grid = 48
    half_x, half_y = 34.0, 26.0
    street_half = 9.0   # flat main-street band along X
    verts = {}
    for iy in range(grid + 1):
        for ix in range(grid + 1):
            sx = ix / grid * 2 - 1
            sy = iy / grid * 2 - 1
            dx = sx * math.sqrt(max(0.0, 1 - sy * sy / 2))
            dy = sy * math.sqrt(max(0.0, 1 - sx * sx / 2))
            x, y = dx * half_x, dy * half_y
            r_norm = math.sqrt((x / half_x) ** 2 + (y / half_y) ** 2)
            z = noise.noise(Vector((x * 0.05, y * 0.05, 3))) * 0.7
            z += noise.noise(Vector((x * 0.015, y * 0.015, 9))) * 1.0
            # flatten the main street + building band
            flat_w = abs(y) / (street_half + 6.0)
            if flat_w < 1.0:
                blend = flat_w * flat_w
                z *= blend
            # raised rock shelf, south-east quadrant in Godot terms
            # (Blender +Y exports to Godot -Z, so Godot z>12 is Blender y<-12)
            edge = min((x - 6.0) / 3.0, (-y - 12.0) / 3.0)
            if edge > 0.0:
                z += min(edge, 1.0) ** 2 * 2.2 if edge < 1.0 else 2.2
            if r_norm > 0.84:
                t = (r_norm - 0.84) / 0.16
                z += t * t * 3.4
            verts[(ix, iy)] = bm.verts.new((x, y, z))
    for iy in range(grid):
        for ix in range(grid):
            a, b = verts[(ix, iy)], verts[(ix + 1, iy)]
            c, d = verts[(ix + 1, iy + 1)], verts[(ix, iy + 1)]
            if a.co == b.co or b.co == c.co or c.co == d.co or a.co == d.co:
                continue
            try:
                f = bm.faces.new((a, b, c, d))
            except ValueError:
                continue
            center = f.calc_center_median()
            f.material_index = 0 if abs(center.y) < street_half else 1
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

# ---------- run ----------

os.makedirs(OUT_DIR, exist_ok=True)

make_false_front("Storefront_Tan", 11, 4.5, 4.0, 3.2, "wood_light", "trim")
make_false_front("Storefront_Red", 12, 5.5, 4.6, 3.8, "wood_red", "trim")
make_false_front("Storefront_Gray", 13, 3.8, 3.6, 3.0, "wood_gray", "wood_light")
make_false_front("Storefront_Brown", 14, 5.0, 4.2, 3.4, "wood_mid", "trim")
make_church("Church")
make_water_tower("WaterTower")
make_windmill("Windmill")
make_hitching_post("HitchingPost")
make_trough("Trough")
make_hay_bale("HayBale_Single", 21, False)
make_hay_bale("HayBale_Stack", 22, True)
make_sand_rock("SandRock_A", 31, 0.9)
make_sand_rock("SandRock_B", 32, 1.6)
make_mesa("Mesa_A", 41, 9.0, 12.0)
make_mesa("Mesa_B", 42, 13.0, 16.0)
make_stair_flight("StairFlight")
make_catwalk("Catwalk")
make_roof_walkway("RoofWalkway")
make_ground("WesternGround")

print("ALL WESTERN ASSETS EXPORTED")
