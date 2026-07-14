# Blender 5.x headless generator for the "Maple & 3rd" city map assets.
# Run:  & "D:\Blender\blender.exe" --background --factory-startup --python "tools/gen_city_assets.py"
# Exports low-poly stylized .glb files into models/cityAssets/.
# Conventions: add_box takes HALF-extents; building fronts face -Y in Blender
# (imports facing +Z in Godot); Blender +Y maps to Godot -Z.

import bpy
import bmesh
import math
import random
import os
from mathutils import Vector, Matrix, noise

OUT_DIR = r"D:\Godot Projects\one-gun\models\cityAssets"

COL = {
    "brick_red":   (0.48, 0.22, 0.16, 1.0),
    "brick_brown": (0.40, 0.26, 0.18, 1.0),
    "brick_tan":   (0.62, 0.50, 0.36, 1.0),
    "concrete":    (0.62, 0.60, 0.56, 1.0),
    "concrete_d":  (0.45, 0.44, 0.42, 1.0),
    "trim_white":  (0.85, 0.83, 0.78, 1.0),
    "window":      (0.10, 0.13, 0.18, 1.0),
    "glass":       (0.25, 0.35, 0.42, 1.0),
    "door_red":    (0.55, 0.12, 0.10, 1.0),
    "awning_grn":  (0.10, 0.35, 0.20, 1.0),
    "awning_red":  (0.55, 0.14, 0.12, 1.0),
    "roof_gray":   (0.30, 0.30, 0.32, 1.0),
    "asphalt":     (0.22, 0.22, 0.24, 1.0),
    "asphalt_d":   (0.17, 0.17, 0.19, 1.0),
    "sidewalk":    (0.58, 0.57, 0.54, 1.0),
    "grass":       (0.22, 0.45, 0.20, 1.0),
    "hydrant_red": (0.72, 0.12, 0.10, 1.0),
    "metal_dark":  (0.15, 0.16, 0.17, 1.0),
    "metal_green": (0.12, 0.25, 0.16, 1.0),
    "usps_blue":   (0.12, 0.22, 0.48, 1.0),
    "taxi_yellow": (0.92, 0.72, 0.10, 1.0),
    "car_blue":    (0.25, 0.32, 0.45, 1.0),
    "van_white":   (0.80, 0.80, 0.78, 1.0),
    "tire":        (0.08, 0.08, 0.08, 1.0),
    "cloud":       (0.96, 0.96, 0.98, 1.0),
    "wood":        (0.45, 0.32, 0.20, 1.0),
    "skyline":     (0.35, 0.37, 0.42, 1.0),
    "skyline_win": (0.55, 0.60, 0.68, 1.0),
    "lamp_red":    (0.85, 0.10, 0.08, 1.0),
    "lamp_yel":    (0.90, 0.75, 0.10, 1.0),
    "lamp_grn":    (0.10, 0.75, 0.25, 1.0),
    "line_yellow": (0.85, 0.75, 0.25, 1.0),
    "line_white":  (0.85, 0.85, 0.82, 1.0),
}

_materials = {}

def mat(name, color, roughness=0.9, emission=None, estrength=2.0):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = estrength
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

def add_box(bm, center, half, mat_idx, rot_z=0.0, rot_x=0.0):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    rot = Matrix.Rotation(rot_z, 4, 'Z') @ Matrix.Rotation(rot_x, 4, 'X')
    for v in tmp.verts:
        v.co = Vector((v.co.x * half[0] * 2, v.co.y * half[1] * 2, v.co.z * half[2] * 2))
        v.co = rot @ v.co
        v.co += Vector(center)
    for f in tmp.faces:
        f.material_index = mat_idx
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)

def add_cyl(bm, base, r1, r2, depth, segs, mat_idx, rot_x=0.0, rot_y=0.0):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    rot = Matrix.Rotation(rot_y, 4, 'Y') @ Matrix.Rotation(rot_x, 4, 'X')
    for v in tmp.verts:
        v.co.z += depth / 2
        v.co = rot @ v.co
        v.co += Vector(base)
    for f in tmp.faces:
        f.material_index = mat_idx
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)

def window_grid(bm, wall_key_idx, w, h_lo, h_hi, front_y, cols, rows, win_mat_idx, inset=0.05):
    for c in range(cols):
        for r in range(rows):
            wx = -w / 2 + (c + 0.5) * (w / cols)
            wz = h_lo + (r + 0.5) * ((h_hi - h_lo) / rows)
            add_box(bm, (wx, front_y - inset, wz), (w / cols * 0.28, 0.04, (h_hi - h_lo) / rows * 0.30), win_mat_idx)

# ============================================================
# Enterable buildings: walls built as segments around door openings.
# All walls 0.3 thick. Doors 1.8 wide x 2.6 high.
# ============================================================

def make_corner_store(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_brick_red", COL["brick_red"]), mat("C_trim", COL["trim_white"]),
            mat("C_window", COL["window"]), mat("C_awning", COL["awning_grn"]),
            mat("C_roof", COL["roof_gray"]), mat("C_wood", COL["wood"]),
            mat("C_concrete", COL["concrete"])]
    W, D, H, T = 5.0, 4.0, 4.5, 0.15  # half-extents footprint, full height, wall half-thickness
    # front wall (-Y): door opening centered at x=-2.2, width 1.8
    dx, dw = -2.2, 0.9
    add_box(bm, ((-W + (dx - dw)) / 2, -D + T, H / 2), ((dx - dw + W) / 2, T, H / 2), 0)
    add_box(bm, ((dx + dw + W) / 2, -D + T, H / 2), ((W - dx - dw) / 2, T, H / 2), 0)
    add_box(bm, (dx, -D + T, (2.6 + H) / 2), (dw, T, (H - 2.6) / 2), 0)  # lintel above door
    # side wall (+X): second door opening centered at y=1.0
    dy = 1.0
    add_box(bm, (W - T, (-D + (dy - dw)) / 2, H / 2), (T, (dy - dw + D) / 2, H / 2), 0)
    add_box(bm, (W - T, (dy + dw + D) / 2, H / 2), (T, (D - dy - dw) / 2, H / 2), 0)
    add_box(bm, (W - T, dy, (2.6 + H) / 2), (T, dw, (H - 2.6) / 2), 0)
    # solid walls: back (+Y) and -X side
    add_box(bm, (0, D - T, H / 2), (W, T, H / 2), 0)
    add_box(bm, (-W + T, 0, H / 2), (T, D, H / 2), 0)
    # roof slab + parapet lip
    add_box(bm, (0, 0, H + 0.12), (W, D, 0.12), 4)
    add_box(bm, (0, -D + 0.06, H + 0.38), (W, 0.06, 0.16), 1)
    # storefront windows either side of the door (outside, dark glass)
    add_box(bm, (1.6, -D - 0.02, 1.8), (2.0, 0.04, 1.0), 2)
    add_box(bm, (-4.2, -D - 0.02, 1.8), (0.55, 0.04, 1.0), 2)
    # awning over the front
    add_box(bm, (0, -D - 0.8, 3.4), (W * 0.9, 0.85, 0.06), 3, rot_x=math.radians(8))
    # interior: counter along -X wall + two shelf rows
    add_box(bm, (-W + 1.1, 0.4, 0.55), (0.45, 1.6, 0.55), 5)
    for sy in (-1.6, 1.9):
        add_box(bm, (1.0, sy, 0.75), (1.6, 0.28, 0.75), 5)
    # sign board above awning
    add_box(bm, (0, -D - 0.1, 4.0), (W * 0.8, 0.07, 0.35), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_diner(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_concrete", COL["concrete"]), mat("C_trim", COL["trim_white"]),
            mat("C_window", COL["window"]), mat("C_awning_red", COL["awning_red"]),
            mat("C_roof", COL["roof_gray"]), mat("C_wood", COL["wood"]),
            mat("C_metal", COL["metal_dark"])]
    W, D, H, T = 5.5, 3.5, 4.0, 0.15
    dw = 0.9
    # front wall (-Y): centered door
    add_box(bm, ((-W - dw) / 2 + 0, -D + T, H / 2), ((W - dw) / 2, T, H / 2), 0)
    add_box(bm, ((W + dw) / 2, -D + T, H / 2), ((W - dw) / 2, T, H / 2), 0)
    add_box(bm, (0, -D + T, (2.6 + H) / 2), (dw, T, (H - 2.6) / 2), 0)
    add_box(bm, (0, D - T, H / 2), (W, T, H / 2), 0)
    add_box(bm, (-W + T, 0, H / 2), (T, D, H / 2), 0)
    add_box(bm, (W - T, 0, H / 2), (T, D, H / 2), 0)
    add_box(bm, (0, 0, H + 0.12), (W, D, 0.12), 4)
    # big diner windows along the front
    for wx in (-3.4, 3.4):
        add_box(bm, (wx, -D - 0.02, 1.9), (1.6, 0.04, 0.85), 2)
    # metal trim band
    add_box(bm, (0, -D - 0.04, 3.1), (W, 0.05, 0.18), 6)
    # rooftop sign
    add_box(bm, (0, 0, H + 1.0), (2.6, 0.10, 0.55), 1)
    for px in (-2.2, 2.2):
        add_box(bm, (px, 0, H + 0.35), (0.07, 0.07, 0.30), 6)
    # interior: counter along back + booths on the -X side
    add_box(bm, (0.5, D - 1.1, 0.55), (2.6, 0.45, 0.55), 5)
    for by in (-1.6, 0.0, 1.6):
        add_box(bm, (-W + 0.9, by, 0.45), (0.55, 0.22, 0.45), 3)   # bench
        add_box(bm, (-W + 1.9, by, 0.42), (0.38, 0.5, 0.06), 5)    # table top
        add_box(bm, (-W + 1.9, by, 0.20), (0.06, 0.06, 0.20), 6)   # table leg
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_brownstone(name, enterable, height, wall_key, seed):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_" + wall_key, COL[wall_key]), mat("C_trim", COL["trim_white"]),
            mat("C_window", COL["window"]), mat("C_door", COL["door_red"]),
            mat("C_roof", COL["roof_gray"]), mat("C_concrete", COL["concrete"])]
    W, D, T = 4.0, 4.5, 0.15
    H = height
    dw = 0.9
    if enterable:
        # front wall with raised door (stoop) at x=+1.4; door bottom at stoop 0.75
        dx = 1.4
        add_box(bm, ((-W + (dx - dw)) / 2, -D + T, H / 2), ((dx - dw + W) / 2, T, H / 2), 0)
        add_box(bm, ((dx + dw + W) / 2, -D + T, H / 2), ((W - dx - dw) / 2, T, H / 2), 0)
        add_box(bm, (dx, -D + T, (0.75 + 0) / 2), (dw, T, 0.375), 0)           # below door
        add_box(bm, (dx, -D + T, (3.35 + H) / 2), (dw, T, (H - 3.35) / 2), 0)  # above door
        # side/back walls solid
        add_box(bm, (0, D - T, H / 2), (W, T, H / 2), 0)
        add_box(bm, (-W + T, 0, H / 2), (T, D, H / 2), 0)
        add_box(bm, (W - T, 0, H / 2), (T, D, H / 2), 0)
        # roof slab with hatch opening (2.2 x 1.6 at -X end) + parapet ring
        add_box(bm, ((-W + (-1.4)) / 2 + 0.0, 0, H + 0.10), ((W - 1.4) / 2, D, 0.10), 4)  # roof -X part up to hatch...
        # simpler: three roof strips around a hatch at x -1.9..-0.3, y -1.0..1.0
        # (rebuild strips cleanly)
    else:
        add_box(bm, (0, -D + T, H / 2), (W, T, H / 2), 0)
        add_box(bm, (0, D - T, H / 2), (W, T, H / 2), 0)
        add_box(bm, (-W + T, 0, H / 2), (T, D, H / 2), 0)
        add_box(bm, (W - T, 0, H / 2), (T, D, H / 2), 0)
        add_box(bm, (0, 0, H + 0.10), (W, D, 0.10), 4)
    if enterable:
        # roof strips leaving a stair hatch opening x[-2.0,-0.2] y[-1.2,1.2]
        add_box(bm, ((-W - 2.0) / 2, 0, H + 0.10), ((W - 2.0) / 2, D, 0.10), 4)
        add_box(bm, ((-0.2 + W) / 2, 0, H + 0.10), ((W + 0.2) / 2, D, 0.10), 4)
        # hatch enlarged both ways (godot z -2.0..+2.2): climbers need overhead
        # clearance through the whole final flight, not just at the top
        add_box(bm, (-1.1, (2.0 + D) / 2, H + 0.10), (0.9, (D - 2.0) / 2, 0.10), 4)
        add_box(bm, (-1.1, (-D - 2.2) / 2, H + 0.10), (0.9, (D - 2.2) / 2, 0.10), 4)
        # interior stairs: two flights along -X wall with mid landing (visual)
        steps = 8
        for i in range(steps):  # flight A: ground up +Y direction
            t = i / steps
            add_box(bm, (-2.6, -2.4 + t * 3.6, (i + 1) * (H / 2 / steps) - 0.1), (0.7, 3.6 / steps / 2 + 0.02, 0.1), 5)
        add_box(bm, (-2.6, 1.9, H / 2 - 0.1), (0.7, 0.8, 0.1), 5)  # mid landing
        for i in range(steps):  # flight B: back -Y direction up to roof
            t = i / steps
            add_box(bm, (-1.1, 1.4 - t * 3.4, H / 2 + (i + 1) * (H / 2 / steps) - 0.1), (0.75, 3.4 / steps / 2 + 0.02, 0.1), 5)
        # ground floor slab
        add_box(bm, (0.6, 0, 0.06), (W - 0.75, D, 0.06), 5)
    # parapet ring
    add_box(bm, (0, -D + 0.07, H + 0.55), (W, 0.07, 0.35), 1)
    add_box(bm, (0, D - 0.07, H + 0.55), (W, 0.07, 0.35), 1)
    add_box(bm, (-W + 0.07, 0, H + 0.55), (0.07, D, 0.35), 1)
    add_box(bm, (W - 0.07, 0, H + 0.55), (0.07, D, 0.35), 1)
    # stoop steps out front
    sx = 1.4 if enterable else 0.0
    for i in range(3):
        add_box(bm, (sx, -D - 0.55 + i * 0.35, 0.125 + i * 0.25), (1.2, 0.55 - i * 0.17, 0.125), 5)
    # door slab (visual)
    add_box(bm, (sx, -D - 0.02, 2.0 if enterable else 1.75), (0.85, 0.04, 1.25), 3)
    # window grid on the front
    window_grid(bm, 0, W * 2 * 0.8, 3.6 if enterable else 2.8, H - 0.7, -D, 3, 2, 2)
    # cornice
    add_box(bm, (0, -D - 0.12, H + 0.18), (W + 0.15, 0.12, 0.14), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_facade(name, seed, w, d, h, wall_key):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_" + wall_key, COL[wall_key]), mat("C_trim", COL["trim_white"]),
            mat("C_window", COL["window"]), mat("C_roof", COL["roof_gray"])]
    add_box(bm, (0, 0, h / 2), (w / 2, d / 2, h / 2), 0)
    add_box(bm, (0, 0, h + 0.1), (w / 2 + 0.05, d / 2 + 0.05, 0.1), 3)
    add_box(bm, (0, -d / 2 - 0.1, h - 0.15), (w / 2 + 0.12, 0.1, 0.15), 1)
    rows = max(2, int(h / 2.6))
    cols = max(2, int(w / 2.2))
    window_grid(bm, 0, w * 0.85, 1.2, h - 0.9, -d / 2, cols, rows, 2)
    # ground-level storefront band on some variants
    if seed % 2 == 0:
        add_box(bm, (0, -d / 2 - 0.03, 0.9), (w / 2 * 0.85, 0.05, 0.7), 2)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_skyline_block(name, seed, w, h):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_skyline", COL["skyline"]), mat("C_skyline_win", COL["skyline_win"])]
    add_box(bm, (0, 0, h / 2), (w / 2, w / 2 * 0.7, h / 2), 0)
    for r in range(int(h / 4)):
        for c in range(max(2, int(w / 4))):
            if random.random() < 0.55:
                wx = -w / 2 + (c + 0.5) * (w / max(2, int(w / 4)))
                add_box(bm, (wx, -w / 2 * 0.7 - 0.05, 2.0 + r * 4.0), (0.5, 0.04, 0.8), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

# ============================================================
# Street furniture
# ============================================================

def make_hydrant(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_hydrant", COL["hydrant_red"], roughness=0.6)]
    add_cyl(bm, (0, 0, 0), 0.16, 0.14, 0.55, 8, 0)
    add_cyl(bm, (0, 0, 0.55), 0.15, 0.02, 0.25, 8, 0)
    add_cyl(bm, (0.0, 0, 0.38), 0.06, 0.06, 0.36, 6, 0, rot_x=math.radians(90))
    add_box(bm, (0, 0, 0.38), (0.19, 0.06, 0.06), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_lamp_post(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_green", COL["metal_green"], roughness=0.7), mat("C_trim", COL["trim_white"])]
    add_cyl(bm, (0, 0, 0), 0.09, 0.06, 4.5, 8, 0)
    add_cyl(bm, (0, 0.0, 4.5), 0.05, 0.05, 1.1, 6, 0, rot_x=math.radians(-80))
    add_box(bm, (0, 1.05, 4.62), (0.16, 0.30, 0.09), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_traffic_light(name):
    clear_scene()
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    pole = new_object("Pole")
    bm = bmesh.new()
    mats = [mat("C_metal_dark", COL["metal_dark"], roughness=0.7)]
    add_cyl(bm, (0, 0, 0), 0.10, 0.08, 4.8, 8, 0)
    add_cyl(bm, (0, 0, 4.8), 0.06, 0.06, 2.4, 6, 0, rot_x=math.radians(-90))
    add_box(bm, (0, 2.1, 4.35), (0.16, 0.14, 0.48), 0)
    finish(pole, bm, mats)
    pole.parent = root
    lamps = []
    for lname, key, z in (("Lamp_R", "lamp_red", 4.68), ("Lamp_Y", "lamp_yel", 4.36), ("Lamp_G", "lamp_grn", 4.04)):
        lo = new_object(lname)
        lb = bmesh.new()
        lm = [mat("C_" + key, COL[key], roughness=0.4, emission=COL[key], estrength=2.2)]
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=True, segments=8, radius1=0.10, radius2=0.10, depth=0.06)
        rot = Matrix.Rotation(math.radians(90), 4, 'X')
        for v in tmp.verts:
            v.co = rot @ v.co
            v.co += Vector((0, 2.1 - 0.16, z))
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        lb.from_mesh(tm); bpy.data.meshes.remove(tm)
        finish(lo, lb, lm)
        lo.parent = root
        lamps.append(lo)
    export_glb(root, name + ".glb", extra=[pole] + lamps)

def make_trash_can(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_dark", COL["metal_dark"], roughness=0.8)]
    add_cyl(bm, (0, 0, 0), 0.30, 0.34, 0.85, 10, 0)
    add_cyl(bm, (0, 0, 0.85), 0.36, 0.30, 0.12, 10, 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_dumpster(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_grn2", (0.16, 0.30, 0.20, 1.0), roughness=0.85), mat("C_metal_dark", COL["metal_dark"])]
    add_box(bm, (0, 0, 0.65), (1.1, 0.65, 0.55), 0)
    add_box(bm, (0, 0, 1.28), (1.12, 0.66, 0.07), 1, rot_x=math.radians(4))
    for wx in (-0.9, 0.9):
        add_box(bm, (wx, 0, 0.06), (0.08, 0.5, 0.06), 1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_mailbox(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_usps", COL["usps_blue"], roughness=0.6)]
    add_box(bm, (0, 0, 0.85), (0.35, 0.25, 0.30), 0)
    add_cyl(bm, (0, 0, 1.15), 0.25, 0.25, 0.35, 8, 0, rot_x=math.radians(0), rot_y=math.radians(90))
    for lx, ly in ((-0.25, -0.15), (0.25, -0.15), (-0.25, 0.15), (0.25, 0.15)):
        add_box(bm, (lx, ly, 0.28), (0.04, 0.04, 0.28), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_bus_shelter(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_dark", COL["metal_dark"]), mat("C_glass", COL["glass"], roughness=0.2), mat("C_wood", COL["wood"])]
    add_box(bm, (0, 0.55, 2.25), (1.7, 0.75, 0.05), 0)
    add_box(bm, (0, 1.15, 1.1), (1.65, 0.04, 1.1), 1)
    for px in (-1.6, 1.6):
        add_box(bm, (px, 0.5, 1.1), (0.06, 0.7, 1.1), 0)
    add_box(bm, (0, 0.85, 0.45), (1.4, 0.25, 0.05), 2)
    for px in (-1.1, 1.1):
        add_box(bm, (px, 0.85, 0.2), (0.06, 0.2, 0.2), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_manhole(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_dark", COL["metal_dark"], roughness=0.95)]
    add_cyl(bm, (0, 0, 0), 0.45, 0.45, 0.03, 12, 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_hoop(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_dark", COL["metal_dark"]), mat("C_trim", COL["trim_white"]), mat("C_hyd", COL["hydrant_red"])]
    add_cyl(bm, (0, 0, 0), 0.09, 0.09, 3.4, 8, 0)
    add_box(bm, (0, 0.35, 3.35), (0.06, 0.35, 0.06), 0)
    add_box(bm, (0, 0.75, 3.5), (0.9, 0.04, 0.6), 1)
    add_cyl(bm, (0, 0.55, 3.05), 0.24, 0.24, 0.04, 10, 2)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_park_fence(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_metal_dark", COL["metal_dark"], roughness=0.7)]
    for rz in (0.25, 0.95):
        add_box(bm, (0, 0, rz), (1.2, 0.03, 0.03), 0)
    for i in range(7):
        px = -1.05 + i * 0.35
        add_box(bm, (px, 0, 0.5), (0.02, 0.02, 0.5), 0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

# ============================================================
# Vehicles (front = +Y blender -> -Z Godot; wheels = named children)
# ============================================================

def make_vehicle(name, body_key, kind):
    clear_scene()
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    body = new_object("Body")
    bm = bmesh.new()
    mats = [mat("C_" + body_key, COL[body_key], roughness=0.35), mat("C_window", COL["window"], roughness=0.2),
            mat("C_metal_dark", COL["metal_dark"]), mat("C_trim", COL["trim_white"])]
    if kind == "van":
        add_box(bm, (0, 0, 0.9), (0.95, 2.4, 0.55), 0)
        add_box(bm, (0, 1.6, 1.85), (0.9, 0.75, 0.45), 0)
        add_box(bm, (0, 0.2, 1.85), (0.92, 2.1, 0.42), 0)
        add_box(bm, (0, 2.15, 1.85), (0.8, 0.28, 0.3), 1)  # windshield
    else:
        add_box(bm, (0, 0, 0.75), (0.9, 2.2, 0.35), 0)
        add_box(bm, (0, -0.25, 1.3), (0.82, 1.1, 0.28), 0)
        add_box(bm, (0, 0.75, 1.28), (0.78, 0.35, 0.24), 1)   # windshield
        add_box(bm, (0, -1.25, 1.28), (0.78, 0.28, 0.22), 1)  # rear glass
        if kind == "taxi":
            add_box(bm, (0, -0.2, 1.68), (0.28, 0.5, 0.10), 3)  # roof sign
    # bumpers
    add_box(bm, (0, 2.25 if kind != "van" else 2.45, 0.5), (0.88, 0.08, 0.12), 2)
    add_box(bm, (0, -2.25 if kind != "van" else -2.45, 0.5), (0.88, 0.08, 0.12), 2)
    finish(body, bm, mats)
    body.parent = root
    wheels = []
    wy = 1.45 if kind != "van" else 1.6
    for wname, wx, wyy in (("Wheel_FL", -0.92, wy), ("Wheel_FR", 0.92, wy), ("Wheel_RL", -0.92, -wy), ("Wheel_RR", 0.92, -wy)):
        wo = new_object(wname)
        wb = bmesh.new()
        wm = [mat("C_tire", COL["tire"], roughness=0.95)]
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=True, segments=10, radius1=0.34, radius2=0.34, depth=0.24)
        rot = Matrix.Rotation(math.radians(90), 4, 'Y')
        for v in tmp.verts:
            v.co = rot @ v.co
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        wb.from_mesh(tm); bpy.data.meshes.remove(tm)
        finish(wo, wb, wm)
        wo.parent = root
        wo.location = Vector((wx, wyy, 0.34))
        wheels.append(wo)
    export_glb(root, name + ".glb", extra=[body] + wheels)

# ============================================================
# Clouds + ground
# ============================================================

def make_cloud(name, seed, blobs, spread, base_r):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_cloud", COL["cloud"], roughness=1.0)]
    for i in range(blobs):
        cx = random.uniform(-spread, spread)
        cy = random.uniform(-spread * 0.4, spread * 0.4)
        r = base_r * random.uniform(0.5, 1.0)
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=r)
        for v in tmp.verts:
            v.co.z *= 0.45
            v.co += Vector((cx, cy, random.uniform(0, base_r * 0.25)))
        tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
        bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_ground(name):
    # Flat 76x54 with material zones. Blender +Y == Godot -Z.
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("C_asphalt", COL["asphalt"], roughness=1.0), mat("C_sidewalk", COL["sidewalk"], roughness=1.0),
            mat("C_grass", COL["grass"], roughness=1.0), mat("C_asphalt_d", COL["asphalt_d"], roughness=1.0)]
    HX, HY = 38.0, 27.0
    cell = 1.0
    nx, ny = int(HX * 2 / cell), int(HY * 2 / cell)
    verts = {}
    for iy in range(ny + 1):
        for ix in range(nx + 1):
            x = -HX + ix * cell
            y = -HY + iy * cell
            verts[(ix, iy)] = bm.verts.new((x, y, 0.0))
    def zone(x, y):
        cross_road = abs(x) < 4.5 or abs(y) < 4.5
        ring_road = (24.0 < abs(x) < 32.0 and abs(y) < 25.0) or (16.0 < abs(y) < 24.0 and abs(x) < 32.0)
        # blender y<0 == Godot z>0 (south)
        park = (-24.0 < x < -4.5) and (-16.0 < y < -4.5)
        lot = (14.0 < x < 24.0) and (-16.0 < y < -10.0)
        if park:
            return 2
        if lot:
            return 3
        if cross_road or ring_road:
            return 0
        return 1
    for iy in range(ny):
        for ix in range(nx):
            f = bm.faces.new((verts[(ix, iy)], verts[(ix + 1, iy)], verts[(ix + 1, iy + 1)], verts[(ix, iy + 1)]))
            c = f.calc_center_median()
            f.material_index = zone(c.x, c.y)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

# ---------- run ----------

os.makedirs(OUT_DIR, exist_ok=True)

make_corner_store("CornerStore")
make_diner("Diner")
make_brownstone("Brownstone_Enterable", True, 8.0, "brick_brown", 71)
make_brownstone("Brownstone_A", False, 7.0, "brick_red", 72)
make_brownstone("Brownstone_B", False, 9.0, "brick_tan", 73)
make_facade("Facade_Tall", 80, 6.0, 5.0, 14.0, "brick_red")
make_facade("Facade_Mid_A", 81, 8.0, 5.0, 9.0, "brick_tan")
make_facade("Facade_Mid_B", 82, 7.0, 5.0, 11.0, "concrete")
make_facade("Facade_Short", 83, 9.0, 5.0, 6.5, "brick_brown")
make_skyline_block("Skyline_A", 91, 12.0, 24.0)
make_skyline_block("Skyline_B", 92, 16.0, 32.0)
make_skyline_block("Skyline_C", 93, 10.0, 18.0)
make_hydrant("FireHydrant")
make_lamp_post("LampPost")
make_traffic_light("TrafficLight")
make_trash_can("TrashCan")
make_dumpster("Dumpster")
make_mailbox("Mailbox")
make_bus_shelter("BusShelter")
make_manhole("Manhole")
make_hoop("BasketballHoop")
make_park_fence("ParkFence")
make_vehicle("Car_Sedan", "car_blue", "sedan")
make_vehicle("Car_Taxi", "taxi_yellow", "taxi")
make_vehicle("Car_Van", "van_white", "van")
make_cloud("Cloud_A", 101, 5, 4.0, 2.2)
make_cloud("Cloud_B", 102, 8, 7.0, 2.8)
make_cloud("Cloud_C", 103, 3, 2.5, 1.8)
make_cloud("Cloud_D", 104, 11, 10.0, 3.2)
make_ground("CityGround")

print("ALL CITY ASSETS EXPORTED")
