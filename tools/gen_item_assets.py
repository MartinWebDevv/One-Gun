# Blender 5.x headless generator for the new pickup item models.
# Run:  & "D:\Blender\blender.exe" --background --factory-startup --python "tools/gen_item_assets.py"
# Exports: SmokeBomb.glb, Boomerang.glb, DecoyBag.glb -> models/items/

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

OUT_DIR = r"D:\Godot Projects\one-gun\models\items"

_materials = {}

def mat(name, color, roughness=0.8, metallic=0.0):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    _materials[name] = m
    return m

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

def new_object(name):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj

def finish_export(obj, bm, mats, filename):
    bm.to_mesh(obj.data)
    bm.free()
    for m in mats:
        obj.data.materials.append(m)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, filename),
                              export_format='GLB', use_selection=True)
    print("EXPORTED", filename)

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

def add_box(bm, center, half, mat_idx, rot=None):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * half[0] * 2, v.co.y * half[1] * 2, v.co.z * half[2] * 2))
        if rot:
            v.co = rot @ v.co
        v.co += Vector(center)
    for f in tmp.faces:
        f.material_index = mat_idx
    tm = bpy.data.meshes.new("_t"); tmp.to_mesh(tm); tmp.free()
    bm.from_mesh(tm); bpy.data.meshes.remove(tm)

def make_smoke_bomb():
    clear_scene()
    obj = new_object("SmokeBomb")
    bm = bmesh.new()
    mats = [mat("SB_body", (0.25, 0.35, 0.30, 1.0), 0.5, 0.6),
            mat("SB_band", (0.85, 0.75, 0.25, 1.0), 0.6),
            mat("SB_top", (0.20, 0.20, 0.22, 1.0), 0.4, 0.8)]
    # canister
    add_cyl(bm, (0, 0, 0), 0.11, 0.11, 0.3, 10, 0)
    # warning band
    add_cyl(bm, (0, 0, 0.12), 0.115, 0.115, 0.06, 10, 1)
    # cap + valve
    add_cyl(bm, (0, 0, 0.3), 0.09, 0.08, 0.05, 10, 2)
    add_cyl(bm, (0, 0, 0.35), 0.03, 0.03, 0.04, 8, 2)
    # pull ring (small torus-ish ring of boxes)
    for i in range(8):
        a = i * math.tau / 8
        add_box(bm, (math.cos(a) * 0.05 + 0.06, math.sin(a) * 0.05, 0.4), (0.012, 0.012, 0.008), 2)
    finish_export(obj, bm, mats, "SmokeBomb.glb")

def make_boomerang():
    clear_scene()
    obj = new_object("Boomerang")
    bm = bmesh.new()
    mats = [mat("BR_wood", (0.55, 0.35, 0.15, 1.0), 0.85),
            mat("BR_stripe", (0.85, 0.25, 0.15, 1.0), 0.7)]
    # two flat blades meeting at ~100 degrees, slight airfoil taper
    for ang in (0.0, math.radians(100)):
        rot = Matrix.Rotation(ang, 4, 'Z')
        for i in range(5):
            t = i / 5.0
            L = 0.42
            seg_c = rot @ Vector((0.06 + t * L + L / 10, 0, 0))
            w = 0.075 * (1.0 - t * 0.45)
            mi = 1 if i == 2 else 0
            add_box(bm, seg_c, (L / 10 + 0.005, w, 0.014 * (1.0 - t * 0.4)), mi, rot)
    # center hub
    add_cyl(bm, (0.03, 0.02, -0.015), 0.075, 0.075, 0.035, 8, 0)
    finish_export(obj, bm, mats, "Boomerang.glb")

def make_decoy_bag():
    clear_scene()
    obj = new_object("DecoyBag")
    bm = bmesh.new()
    mats = [mat("DB_canvas", (0.45, 0.38, 0.25, 1.0), 0.95),
            mat("DB_strap", (0.25, 0.20, 0.14, 1.0), 0.85),
            mat("DB_tag", (0.85, 0.20, 0.15, 1.0), 0.7)]
    # duffel body (squashed capsule from boxes+cyl)
    add_cyl(bm, (0, 0, 0.13), 0.14, 0.14, 0.26, 10, 0, rot_x=math.radians(90))
    add_box(bm, (0, 0, 0.13), (0.13, 0.19, 0.115), 0)
    # end caps
    for sy in (-0.2, 0.2):
        add_cyl(bm, (0, sy, 0.13), 0.13, 0.10, 0.04, 10, 0, rot_x=math.radians(90 if sy < 0 else -90))
    # straps
    for sy in (-0.09, 0.09):
        add_box(bm, (0, sy, 0.245), (0.135, 0.02, 0.012), 1)
    # zipper line + tag
    add_box(bm, (0, 0, 0.26), (0.012, 0.18, 0.008), 1)
    add_box(bm, (0.05, 0.16, 0.27), (0.03, 0.02, 0.005), 2)
    finish_export(obj, bm, mats, "DecoyBag.glb")

os.makedirs(OUT_DIR, exist_ok=True)
make_smoke_bomb()
make_boomerang()
make_decoy_bag()
print("ALL ITEM ASSETS EXPORTED")
