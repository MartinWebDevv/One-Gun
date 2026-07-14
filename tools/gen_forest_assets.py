# Blender 5.x headless generator for One Gun's fantasy forest assets.
# Run:  & "D:\Blender\blender.exe" --background --factory-startup --python "tools/gen_forest_assets.py"
# Exports low-poly stylized .glb files into models/forestAssets/.
# Every model is seeded => reruns produce identical results; tweak constants and rerun.

import bpy
import bmesh
import math
import random
import os
from mathutils import Vector, Matrix, noise

OUT_DIR = r"D:\Godot Projects\one-gun\models\forestAssets"

# ---------- palette (twilight-lush fantasy) ----------
COL = {
    "trunk":        (0.28, 0.19, 0.13, 1.0),
    "trunk_dark":   (0.20, 0.13, 0.10, 1.0),
    "canopy_deep":  (0.09, 0.40, 0.22, 1.0),
    "canopy_mid":   (0.16, 0.55, 0.27, 1.0),
    "canopy_light": (0.30, 0.68, 0.32, 1.0),
    "canopy_teal":  (0.12, 0.50, 0.40, 1.0),
    "grass":        (0.12, 0.45, 0.18, 1.0),
    "grass_dark":   (0.07, 0.32, 0.14, 1.0),
    "fern":         (0.10, 0.40, 0.22, 1.0),
    "flower_pink":  (0.90, 0.35, 0.60, 1.0),
    "flower_blue":  (0.35, 0.45, 0.95, 1.0),
    "flower_yellow":(0.95, 0.80, 0.25, 1.0),
    "flower_center":(0.95, 0.90, 0.55, 1.0),
    "stem":         (0.15, 0.42, 0.18, 1.0),
    "shroom_stem":  (0.88, 0.84, 0.74, 1.0),
    "shroom_red":   (0.75, 0.15, 0.12, 1.0),
    "shroom_spot":  (0.95, 0.93, 0.88, 1.0),
    "glow_teal":    (0.15, 0.95, 0.85, 1.0),
    "glow_violet":  (0.70, 0.40, 1.00, 1.0),
    "rock":         (0.42, 0.44, 0.48, 1.0),
    "rock_moss":    (0.16, 0.36, 0.20, 1.0),
    "stone_old":    (0.38, 0.42, 0.50, 1.0),
    "wood_plank":   (0.42, 0.30, 0.18, 1.0),
    "wood_dark":    (0.30, 0.20, 0.12, 1.0),
    "ground_grass": (0.10, 0.34, 0.15, 1.0),
    "ground_dirt":  (0.30, 0.22, 0.14, 1.0),
    "leaf":         (0.55, 0.70, 0.25, 1.0),
}

_materials = {}

def mat(name, color, emission=None, emission_strength=3.0, roughness=0.9):
    key = (name, emission)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    _materials[key] = m
    return m

# ---------- scene helpers ----------

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

def export_glb(obj, filename):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True)
    print("EXPORTED", filename)

def displace(bm, amount, seed, scale=1.0, only_up=False):
    for v in bm.verts:
        n = noise.noise(v.co * scale + Vector((seed * 13.7, seed * 7.3, seed * 3.1)))
        off = v.normal * n * amount
        if only_up:
            off.z = max(off.z, 0)
        v.co += off

def add_blob(bm, center, radius, squash, mat_idx, seed, subdiv=2, lumpy=0.22):
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=radius)
    for v in tmp.verts:
        n = noise.noise(v.co * 1.4 + Vector((seed * 11.1, seed * 5.7, seed * 2.9)))
        v.co += v.normal * n * radius * lumpy
        v.co.z *= squash
        v.co += Vector(center)
    for f in tmp.faces:
        f.material_index = mat_idx
    tmp_mesh = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)
    bpy.data.meshes.remove(tmp_mesh)

def add_cone(bm, base, radius1, radius2, depth, segments, mat_idx, tilt=(0, 0), taper_seed=None):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=segments,
                          radius1=radius1, radius2=radius2, depth=depth)
    for v in tmp.verts:
        t = (v.co.z + depth / 2) / depth  # 0 bottom .. 1 top
        v.co.x += tilt[0] * t * depth
        v.co.y += tilt[1] * t * depth
        if taper_seed is not None:
            n = noise.noise(v.co * 2.0 + Vector((taper_seed, taper_seed, 0)))
            v.co.x += n * radius1 * 0.15
            v.co.y += n * radius1 * 0.15
        v.co.z += depth / 2
        v.co += Vector(base)
    for f in tmp.faces:
        f.material_index = mat_idx
    tmp_mesh = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)
    bpy.data.meshes.remove(tmp_mesh)

def add_box(bm, center, size, mat_idx, rot_z=0.0):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    rot = Matrix.Rotation(rot_z, 4, 'Z')
    for v in tmp.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        v.co = rot @ v.co
        v.co += Vector(center)
    for f in tmp.faces:
        f.material_index = mat_idx
    tmp_mesh = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)
    bpy.data.meshes.remove(tmp_mesh)

# ---------- assets ----------

def make_tree(name, seed, height, canopy_r, blob_count, colors, trunk_r=None, elder=False):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Trunk", COL["trunk"]), mat("TrunkDark", COL["trunk_dark"])]
    col_idx = {}
    for c in colors:
        col_idx[c] = len(mats)
        mats.append(mat("Canopy_" + c, COL[c], roughness=1.0))
    tr = trunk_r if trunk_r else height * 0.045
    tilt = (random.uniform(-0.06, 0.06), random.uniform(-0.06, 0.06))
    add_cone(bm, (0, 0, 0), tr, tr * 0.55, height * 0.62, 7, 0, tilt=tilt, taper_seed=seed)
    if elder:
        for i in range(3):
            a = seed + i * 2.1
            ang = i * 2.1 + random.uniform(-0.4, 0.4)
            bx, by = math.cos(ang) * tr * 0.7, math.sin(ang) * tr * 0.7
            add_cone(bm, (bx, by, height * random.uniform(0.30, 0.45)),
                     tr * 0.45, tr * 0.18, height * 0.45, 6, 1,
                     tilt=(math.cos(ang) * 0.55, math.sin(ang) * 0.55), taper_seed=a)
    top = height * 0.62
    for i in range(blob_count):
        ang = random.uniform(0, math.tau)
        dist = random.uniform(0, canopy_r * 0.55)
        cx, cy = math.cos(ang) * dist, math.sin(ang) * dist
        cz = top + random.uniform(-canopy_r * 0.15, canopy_r * 0.45)
        r = canopy_r * random.uniform(0.45, 0.75)
        c = colors[i % len(colors)]
        add_blob(bm, (cx, cy, cz), r, random.uniform(0.7, 0.9), col_idx[c], seed + i)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_bush(name, seed, radius, blob_count):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Canopy_deep", COL["canopy_deep"], roughness=1.0),
            mat("Canopy_mid", COL["canopy_mid"], roughness=1.0)]
    for i in range(blob_count):
        ang = random.uniform(0, math.tau)
        dist = random.uniform(0, radius * 0.5)
        r = radius * random.uniform(0.4, 0.65)
        add_blob(bm, (math.cos(ang) * dist, math.sin(ang) * dist, r * 0.55),
                 r, random.uniform(0.65, 0.85), i % 2, seed + i)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_grass(name, seed, blades, height):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Grass", COL["grass"], roughness=1.0),
            mat("GrassDark", COL["grass_dark"], roughness=1.0)]
    for i in range(blades):
        ang = random.uniform(0, math.tau)
        lean_x = math.cos(ang) * random.uniform(0.15, 0.45)
        lean_y = math.sin(ang) * random.uniform(0.15, 0.45)
        h = height * random.uniform(0.6, 1.15)
        w = h * 0.10
        bx = math.cos(ang) * random.uniform(0, 0.12)
        by = math.sin(ang) * random.uniform(0, 0.12)
        tmp = bmesh.new()
        v0 = tmp.verts.new((bx - w, by, 0))
        v1 = tmp.verts.new((bx + w, by, 0))
        v2 = tmp.verts.new((bx + w * 0.35 + lean_x * h * 0.5, by + lean_y * h * 0.5, h * 0.6))
        v3 = tmp.verts.new((bx - w * 0.35 + lean_x * h * 0.5, by + lean_y * h * 0.5, h * 0.6))
        v4 = tmp.verts.new((bx + lean_x * h, by + lean_y * h, h))
        f1 = tmp.faces.new((v0, v1, v2, v3))
        f2 = tmp.faces.new((v3, v2, v4))
        mi = i % 2
        f1.material_index = mi
        f2.material_index = mi
        tmp_mesh = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(tmp_mesh)
        tmp.free()
        bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_fern(name, seed, fronds):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Fern", COL["fern"], roughness=1.0)]
    for i in range(fronds):
        ang = i * math.tau / fronds + random.uniform(-0.2, 0.2)
        length = random.uniform(0.5, 0.8)
        droop = random.uniform(0.25, 0.45)
        segs = 4
        tmp = bmesh.new()
        prev = None
        for s in range(segs + 1):
            t = s / segs
            r = length * t
            z = math.sin(t * math.pi * 0.8) * droop + 0.05
            w = 0.10 * (1.0 - t * 0.8)
            px, py = math.cos(ang) * r, math.sin(ang) * r
            wx, wy = -math.sin(ang) * w, math.cos(ang) * w
            a = tmp.verts.new((px - wx, py - wy, z))
            b = tmp.verts.new((px + wx, py + wy, z))
            if prev:
                tmp.faces.new((prev[0], prev[1], b, a))
            prev = (a, b)
        tmp_mesh = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(tmp_mesh)
        tmp.free()
        bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_flowers(name, seed, petal_color, count):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Stem", COL["stem"], roughness=1.0),
            mat("Petal_" + petal_color, COL[petal_color], roughness=0.8),
            mat("FlowerCenter", COL["flower_center"], roughness=0.8)]
    for i in range(count):
        ang = random.uniform(0, math.tau)
        dist = random.uniform(0, 0.25)
        bx, by = math.cos(ang) * dist, math.sin(ang) * dist
        h = random.uniform(0.16, 0.28)
        add_cone(bm, (bx, by, 0), 0.022, 0.014, h, 5, 0)
        add_blob(bm, (bx, by, h + 0.05), 0.11, 0.55, 1, seed + i, subdiv=1, lumpy=0.4)
        add_blob(bm, (bx, by, h + 0.10), 0.035, 0.8, 2, seed + i + 50, subdiv=1, lumpy=0.1)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_mushroom(name, seed, count, cap_color, glow):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    cap_mat = mat("Cap_" + name, COL[cap_color],
                  emission=COL[cap_color] if glow else None,
                  emission_strength=2.5, roughness=0.7)
    mats = [mat("ShroomStem", COL["shroom_stem"], roughness=0.9), cap_mat]
    for i in range(count):
        ang = random.uniform(0, math.tau)
        dist = random.uniform(0, 0.30) if count > 1 else 0
        bx, by = math.cos(ang) * dist, math.sin(ang) * dist
        h = random.uniform(0.12, 0.35)
        r = h * random.uniform(0.55, 0.8)
        add_cone(bm, (bx, by, 0), r * 0.30, r * 0.22, h, 6, 0)
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=2, radius=r)
        for v in tmp.verts:
            if v.co.z < 0:
                v.co.z *= 0.25
            v.co.z *= 0.75
            n = noise.noise(v.co * 3.0 + Vector((seed + i, 0, 0)))
            v.co += v.normal * n * r * 0.08
            v.co += Vector((bx, by, h))
        for f in tmp.faces:
            f.material_index = 1
        tmp_mesh = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(tmp_mesh)
        tmp.free()
        bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_log(name, seed):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("TrunkDark", COL["trunk_dark"]), mat("RockMoss", COL["rock_moss"], roughness=1.0)]
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=9, radius1=0.42, radius2=0.36, depth=3.4)
    for v in tmp.verts:
        v.co.rotate(Matrix.Rotation(math.radians(90), 3, 'Y'))
        n = noise.noise(v.co * 1.2 + Vector((seed, seed, 0)))
        v.co += v.normal * n * 0.08
        v.co.z += 0.40
    for f in tmp.faces:
        center = f.calc_center_median()
        f.material_index = 1 if (center.z > 0.60 and noise.noise(center * 4.5 + Vector((seed, 0, 0))) > 0.42) else 0
    tmp_mesh = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)
    bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_stump(name, seed):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Trunk", COL["trunk"]), mat("ShroomStem", COL["shroom_stem"], roughness=1.0)]
    add_cone(bm, (0, 0, 0), 0.55, 0.45, 0.55, 9, 0, taper_seed=seed)
    add_cone(bm, (0, 0, 0.55), 0.44, 0.44, 0.03, 9, 1)
    displace(bm, 0.05, seed, scale=2.0)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_boulder(name, seed, radius):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Rock", COL["rock"], roughness=1.0), mat("RockMoss", COL["rock_moss"], roughness=1.0)]
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=2, radius=radius)
    for v in tmp.verts:
        n = noise.noise(v.co * 1.1 + Vector((seed * 9.1, seed * 4.3, seed)))
        v.co += v.normal * n * radius * 0.30
        v.co.z *= 0.75
        v.co.z += radius * 0.55
    for f in tmp.faces:
        center = f.calc_center_median()
        up = f.normal.z
        f.material_index = 1 if (up > 0.45 and noise.noise(center * 1.5 + Vector((seed, 0, 0))) > -0.05) else 0
    tmp_mesh = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)
    bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_standing_stone(name, seed, height):
    random.seed(seed)
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("StoneOld", COL["stone_old"], roughness=1.0),
            mat("RockMoss", COL["rock_moss"], roughness=1.0),
            mat("RuneGlow", (0.20, 0.95, 0.80, 1.0),
                emission=(0.20, 0.95, 0.80, 1.0), emission_strength=2.4, roughness=0.6)]
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    res = bmesh.ops.subdivide_edges(tmp, edges=tmp.edges[:], cuts=3, use_grid_fill=True)
    for v in tmp.verts:
        t = (v.co.z + 0.5)
        s = 1.0 - t * 0.40
        v.co.x *= 1.35 * s
        v.co.y *= 0.90 * s
        v.co.z = v.co.z * height + height / 2
        n = noise.noise(v.co * 1.6 + Vector((seed * 3.3, seed * 8.8, 0)))
        v.co.x += n * 0.22
        v.co.y += n * 0.16
    for f in tmp.faces:
        center = f.calc_center_median()
        nrm = f.normal
        if center.z < height * 0.25 and noise.noise(center * 2.2) > 0.0:
            f.material_index = 1
        elif (abs(nrm.y) > 0.55 and height * 0.30 < center.z < height * 0.85
              and noise.noise(center * 5.0 + Vector((seed, 0, seed))) > 0.42):
            f.material_index = 2  # glowing rune patch on the broad faces
        else:
            f.material_index = 0
    tmp_mesh = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(tmp_mesh)
    tmp.free()
    bm.from_mesh(tmp_mesh)
    bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_bridge(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("WoodPlank", COL["wood_plank"], roughness=0.95),
            mat("WoodDark", COL["wood_dark"], roughness=0.95)]
    span, width, arch = 13.0, 4.2, 0.7
    boards = 18
    for i in range(boards):
        t = i / (boards - 1)
        x = (t - 0.5) * span
        z = math.sin(t * math.pi) * arch + 0.10
        ang = math.cos(t * math.pi) * (math.pi * arch / span) * 1.35
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        rot = Matrix.Rotation(-ang, 4, 'Y')
        for v in tmp.verts:
            v.co = Vector((v.co.x * (span / boards) * 1.08, v.co.y * width / 2, v.co.z * 0.06))
            v.co = rot @ v.co
            v.co += Vector((x, 0, z))
        for f in tmp.faces:
            f.material_index = 0
        tmp_mesh = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(tmp_mesh)
        tmp.free()
        bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)
    # side stringers
    for side in (-1, 1):
        for i in range(boards - 1):
            t0, t1 = i / (boards - 1), (i + 1) / (boards - 1)
            x0, x1 = (t0 - 0.5) * span, (t1 - 0.5) * span
            z0 = math.sin(t0 * math.pi) * arch + 0.04
            z1 = math.sin(t1 * math.pi) * arch + 0.04
            mid = Vector(((x0 + x1) / 2, side * (width / 2 - 0.06), (z0 + z1) / 2))
            length = math.hypot(x1 - x0, z1 - z0)
            ang = math.atan2(z1 - z0, x1 - x0)
            tmp = bmesh.new()
            bmesh.ops.create_cube(tmp, size=1.0)
            rot = Matrix.Rotation(ang, 4, 'Y')
            for v in tmp.verts:
                v.co = Vector((v.co.x * length * 1.1, v.co.y * 0.09, v.co.z * 0.14))
                v.co = Matrix.Rotation(-ang, 4, 'Y') @ v.co
                v.co += mid
            for f in tmp.faces:
                f.material_index = 1
            tmp_mesh = bpy.data.meshes.new("_tmp")
            tmp.to_mesh(tmp_mesh)
            tmp.free()
            bm.from_mesh(tmp_mesh)
            bpy.data.meshes.remove(tmp_mesh)
    # rail posts + handrail
    posts = 6
    for side in (-1, 1):
        rail_pts = []
        for i in range(posts):
            t = i / (posts - 1)
            x = (t - 0.5) * span * 0.94
            z = math.sin(t * math.pi) * arch + 0.10
            add_box(bm, (x, side * (width / 2 - 0.05), z + 0.5), (0.05, 0.05, 0.5), 1)
            rail_pts.append((x, z + 1.0))
        for i in range(posts - 1):
            x0, z0 = rail_pts[i]
            x1, z1 = rail_pts[i + 1]
            mid = Vector(((x0 + x1) / 2, side * (width / 2 - 0.05), (z0 + z1) / 2))
            length = math.hypot(x1 - x0, z1 - z0)
            ang = math.atan2(z1 - z0, x1 - x0)
            tmp = bmesh.new()
            bmesh.ops.create_cube(tmp, size=1.0)
            for v in tmp.verts:
                v.co = Vector((v.co.x * length * 1.1, v.co.y * 0.05, v.co.z * 0.05))
                v.co = Matrix.Rotation(-ang, 4, 'Y') @ v.co
                v.co += mid
            for f in tmp.faces:
                f.material_index = 0
            tmp_mesh = bpy.data.meshes.new("_tmp")
            tmp.to_mesh(tmp_mesh)
            tmp.free()
            bm.from_mesh(tmp_mesh)
            bpy.data.meshes.remove(tmp_mesh)
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_bird(name):
    # Low-poly bird: body + separately named wings so a script can flap them.
    clear_scene()
    body_mat = mat("BirdBody", (0.16, 0.14, 0.20, 1.0), roughness=0.9)
    breast_mat = mat("BirdBreast", (0.55, 0.45, 0.50, 1.0), roughness=0.9)
    wing_mat = mat("BirdWing", (0.12, 0.10, 0.16, 1.0), roughness=0.9)

    def solo_object(oname, mats):
        mesh = bpy.data.meshes.new(oname)
        obj = bpy.data.objects.new(oname, mesh)
        bpy.context.collection.objects.link(obj)
        bm = bmesh.new()
        return obj, bm, mats

    # body (stretched icosphere + cone tail + small head sphere)
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    body, bm, mats = solo_object("Body", [body_mat, breast_mat])
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=0.16)
    for v in tmp.verts:
        v.co.y *= 2.1
        v.co.z *= 0.9
    for f in tmp.faces:
        f.material_index = 1 if f.calc_center_median().z < -0.03 else 0
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    # head
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=0.09)
    for v in tmp.verts:
        v.co += Vector((0, 0.33, 0.07))
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    # tail
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=4, radius1=0.09, radius2=0.02, depth=0.22)
    for v in tmp.verts:
        v.co.rotate(Matrix.Rotation(math.radians(100), 3, 'X'))
        v.co += Vector((0, -0.38, 0.03))
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)
    finish(body, bm, mats)
    body.parent = root
    # wings: flat tapered quads hinged at the body side
    for side, wname in ((1, "Wing_L"), (-1, "Wing_R")):
        wobj, wbm, wmats = solo_object(wname, [wing_mat])
        v0 = wbm.verts.new((0, 0.10, 0))
        v1 = wbm.verts.new((0, -0.12, 0))
        v2 = wbm.verts.new((side * 0.42, -0.16, 0.02))
        v3 = wbm.verts.new((side * 0.34, 0.16, 0.02))
        wbm.faces.new((v0, v1, v2, v3) if side > 0 else (v3, v2, v1, v0))
        finish(wobj, wbm, wmats)
        wobj.parent = root
        wobj.location = Vector((side * 0.13, 0.05, 0.05))
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    body.select_set(True)
    for c in root.children:
        c.select_set(True)
    bpy.context.view_layer.objects.active = root
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True)
    print("EXPORTED", name + ".glb")

def make_ground(name):
    # Oval arena ground: disc grid, gentle noise, pond basin in center, raised rim.
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("GroundGrass", COL["ground_grass"], roughness=1.0),
            mat("GroundDirt", COL["ground_dirt"], roughness=1.0)]
    grid = 48
    half_x, half_y = 32.0, 24.0   # oval half-extents (playable ~58x43 inside rim)
    pond_rx, pond_ry, pond_depth = 7.5, 5.0, 1.1
    verts = {}
    for iy in range(grid + 1):
        for ix in range(grid + 1):
            sx = ix / grid * 2 - 1
            sy = iy / grid * 2 - 1
            # square -> disc mapping keeps quads nice
            dx = sx * math.sqrt(max(0.0, 1 - sy * sy / 2))
            dy = sy * math.sqrt(max(0.0, 1 - sx * sx / 2))
            x, y = dx * half_x, dy * half_y
            r_norm = math.sqrt((x / half_x) ** 2 + (y / half_y) ** 2)
            z = noise.noise(Vector((x * 0.08, y * 0.08, 0))) * 0.55
            z += noise.noise(Vector((x * 0.02, y * 0.02, 5))) * 0.9
            # pond basin (elliptical, smooth falloff)
            pd = math.sqrt((x / pond_rx) ** 2 + (y / pond_ry) ** 2)
            if pd < 1.0:
                z -= (math.cos(pd * math.pi) + 1) * 0.5 * pond_depth
            # raised rim bowl at the arena edge
            if r_norm > 0.82:
                t = (r_norm - 0.82) / 0.18
                z += t * t * 3.2
            verts[(ix, iy)] = bm.verts.new((x, y, z))
    bm.verts.ensure_lookup_table()
    for iy in range(grid):
        for ix in range(grid):
            a = verts[(ix, iy)]
            b = verts[(ix + 1, iy)]
            c = verts[(ix + 1, iy + 1)]
            d = verts[(ix, iy + 1)]
            if a.co == b.co or b.co == c.co or c.co == d.co or a.co == d.co:
                continue
            try:
                f = bm.faces.new((a, b, c, d))
            except ValueError:
                continue
            center = f.calc_center_median()
            pd = math.sqrt((center.x / pond_rx) ** 2 + (center.y / pond_ry) ** 2)
            f.material_index = 1 if pd < 1.05 else 0
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

def make_leaf(name):
    clear_scene()
    obj = new_object(name)
    bm = bmesh.new()
    mats = [mat("Leaf", COL["leaf"], roughness=1.0)]
    v0 = bm.verts.new((0, 0, 0))
    v1 = bm.verts.new((0.06, 0.10, 0.01))
    v2 = bm.verts.new((0, 0.22, 0))
    v3 = bm.verts.new((-0.06, 0.10, 0.01))
    bm.faces.new((v0, v1, v2, v3))
    finish(obj, bm, mats)
    export_glb(obj, name + ".glb")

# ---------- run ----------

os.makedirs(OUT_DIR, exist_ok=True)

make_tree("Tree_Large_A", 101, 10.5, 3.6, 6, ["canopy_deep", "canopy_mid", "canopy_light"])
make_tree("Tree_Large_B", 102, 11.5, 4.0, 7, ["canopy_deep", "canopy_teal", "canopy_mid"])
make_tree("Tree_Large_C", 103, 9.5, 3.3, 6, ["canopy_mid", "canopy_light", "canopy_deep"])
make_tree("Tree_Med_A", 201, 6.5, 2.4, 5, ["canopy_mid", "canopy_deep"])
make_tree("Tree_Med_B", 202, 7.0, 2.7, 5, ["canopy_teal", "canopy_mid"])
make_tree("Sapling_A", 301, 2.8, 1.1, 3, ["canopy_light", "canopy_mid"])
make_tree("Sapling_B", 302, 3.3, 1.3, 3, ["canopy_mid", "canopy_teal"])
make_tree("Tree_Elder", 401, 13.0, 4.5, 8, ["canopy_deep", "canopy_teal", "canopy_mid"], trunk_r=1.1, elder=True)
make_bush("Bush_A", 501, 0.9, 4)
make_bush("Bush_B", 502, 1.3, 5)
make_grass("Grass_A", 601, 9, 0.45)
make_grass("Grass_B", 602, 7, 0.35)
make_grass("Grass_C", 603, 12, 0.55)
make_fern("Fern_A", 701, 7)
make_fern("Fern_B", 702, 9)
make_flowers("Flowers_Pink", 801, "flower_pink", 5)
make_flowers("Flowers_Blue", 802, "flower_blue", 4)
make_flowers("Flowers_Yellow", 803, "flower_yellow", 6)
make_mushroom("Mushroom_Red_A", 901, 2, "shroom_red", False)
make_mushroom("Mushroom_Red_B", 902, 3, "shroom_red", False)
make_mushroom("GlowShroom_Teal", 951, 4, "glow_teal", True)
make_mushroom("GlowShroom_Violet", 952, 3, "glow_violet", True)
make_log("Fallen_Log", 1001)
make_stump("Stump", 1101)
make_boulder("Boulder_A", 1201, 1.0)
make_boulder("Boulder_B", 1202, 1.7)
make_standing_stone("Standing_Stone_A", 1301, 2.6)
make_standing_stone("Standing_Stone_B", 1302, 3.4)
make_bridge("Bridge")
make_ground("ForestGround")
make_leaf("Leaf")
make_bird("Bird")

print("ALL FOREST ASSETS EXPORTED")
