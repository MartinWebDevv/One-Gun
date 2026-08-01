# Blender 5.x headless generator for the MAIN MENU trophy pedestal
# (FABLE5 packet Section 4). Menu-only prop.
#
# Deliberately HIGH-DETAIL and smooth (user request: nothing low poly):
# 192-segment tiers, multi-segment bevels everywhere, smooth shading.
#
# Run:  & "D:\Blender\blender.exe" --background --factory-startup --python "tools/gen_trophy_pedestal.py"
# Exports:
#   models/menu/TrophyPedestal.glb    (game asset)
#   models/menu/TrophyPedestal.blend  (editable source)

import bpy
import bmesh
import math
import os

OUT_DIR = r"D:\Godot Projects\one-gun\models\menu"
SEG = 192   # cylinder segments — generously smooth

_materials = {}

def mat(name, color, roughness=0.5, metallic=0.0, emission=None, emission_strength=0.0):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    _materials[name] = m
    return m

BRONZE   = mat("BronzeBody", (0.055, 0.042, 0.038, 1.0), 0.42, 0.85)
BRONZE_L = mat("BronzeLip",  (0.115, 0.085, 0.062, 1.0), 0.35, 0.9)
DECK     = mat("DeckDark",   (0.045, 0.048, 0.065, 1.0), 0.48, 0.6)
GOLD     = mat("GoldTrim",   (0.85, 0.60, 0.16, 1.0), 0.24, 1.0)
GOLD_GLOW= mat("GoldGlow",   (1.0, 0.72, 0.22, 1.0), 0.3, 0.4, (1.0, 0.72, 0.22, 1.0), 2.6)
PLAQUE_BG= mat("PlaqueNavy", (0.055, 0.06, 0.10, 1.0), 0.45, 0.3)
GOLD_LIT = mat("GoldLit",    (0.90, 0.66, 0.20, 1.0), 0.25, 1.0, (1.0, 0.75, 0.28, 1.0), 1.1)

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True

def add_bevel(obj, width=0.02, segments=5):
    m = obj.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(40)

def tier(name, material, z_bottom, height, r_bottom, r_top, bevel=0.025):
    bpy.ops.mesh.primitive_cylinder_add(vertices=SEG, radius=r_bottom, depth=height,
        location=(0, 0, z_bottom + height / 2.0))
    o = bpy.context.active_object
    o.name = name
    # taper the top ring for a molded profile
    bm = bmesh.new()
    bm.from_mesh(o.data)
    top_z = height / 2.0 - 0.0001
    for v in bm.verts:
        if v.co.z > top_z:
            f = r_top / r_bottom
            v.co.x *= f
            v.co.y *= f
    bm.to_mesh(o.data)
    bm.free()
    add_bevel(o, bevel, 6)
    o.data.materials.append(material)
    smooth(o)
    return o

def torus(name, material, z, major_r, minor_r):
    bpy.ops.mesh.primitive_torus_add(major_segments=SEG, minor_segments=48,
        major_radius=major_r, minor_radius=minor_r, location=(0, 0, z))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    smooth(o)
    return o

def rbox(name, material, loc, scale, rot=(0, 0, 0), bevel=0.012, segs=4):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.rotation_euler = rot
    m = o.modifiers.new("Bevel", 'BEVEL')
    m.width = bevel
    m.segments = segs
    o.data.materials.append(material)
    smooth(o)
    return o

def sphere(name, material, loc, r):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    smooth(o)
    return o

def star(name, material, loc, outer_r, inner_r, thickness, rot=(0, 0, 0)):
    bm = bmesh.new()
    verts = []
    for i in range(10):
        r = outer_r if i % 2 == 0 else inner_r
        a = math.pi / 2.0 + i * math.pi / 5.0
        verts.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    face = bm.faces.new(verts)
    ret = bmesh.ops.extrude_face_region(bm, geom=[face])
    for elem in ret["geom"]:
        if isinstance(elem, bmesh.types.BMVert):
            elem.co.z += thickness
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    o.data.materials.append(material)
    return o

def build():
    parts = []

    # --- Stepped tiers (low + wide, molded bronze) -------------------------
    parts.append(tier("TierBase", BRONZE_L, 0.00, 0.14, 1.60, 1.52))
    parts.append(tier("TierMid",  BRONZE,   0.14, 0.15, 1.46, 1.36))
    parts.append(tier("TierBody", BRONZE,   0.29, 0.20, 1.30, 1.24))

    # --- Warm-gold illuminated ring recessed under the top deck ------------
    parts.append(torus("GlowRing", GOLD_GLOW, 0.505, 1.235, 0.038))
    # thin gold trim rings framing the glow
    parts.append(torus("TrimLow",  GOLD, 0.455, 1.26, 0.016))
    parts.append(torus("TrimHigh", GOLD, 0.555, 1.21, 0.016))

    # --- Top deck (dark, subtle radial segmentation) -----------------------
    parts.append(tier("TopDeck", DECK, 0.55, 0.11, 1.20, 1.14))
    # 12 shallow radial seams as slim raised strips
    for i in range(12):
        a = i * math.tau / 12.0
        strip = rbox("Seam", BRONZE,
            (math.cos(a) * 0.60, math.sin(a) * 0.60, 0.662),
            (0.55, 0.008, 0.004), (0, 0, a), 0.003, 2)
        parts.append(strip)
    # small gold center disc
    parts.append(tier("CenterDisc", GOLD, 0.66, 0.012, 0.16, 0.15, 0.006))

    # --- Front plaque (gold frame, navy face, rivets, stars, lettering) ----
    # Front = -Y. The plaque stands proud of the base tier (radius 1.60) so it
    # reads as mounted ON the pedestal instead of sunk into it.
    plaque_y = -1.68
    tilt = math.radians(14)
    parts.append(rbox("PlaqueFrame", GOLD_LIT, (0, plaque_y, 0.21), (0.46, 0.03, 0.135), (tilt, 0, 0), 0.02, 5))
    parts.append(rbox("PlaqueFace", PLAQUE_BG, (0, plaque_y - 0.022, 0.21), (0.42, 0.016, 0.108), (tilt, 0, 0), 0.012, 4))
    # rivets
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(sphere("Rivet", GOLD_LIT, (0.40 * sx, plaque_y - 0.035, 0.21 + 0.095 * sz), 0.018))
    # star accents
    for sx in (-1, 1):
        parts.append(star("PlaqueStar", GOLD_LIT, (0.315 * sx, plaque_y - 0.042, 0.198),
            0.030, 0.013, 0.012, (math.radians(90) - tilt, 0, 0)))

    # lettering: real text, extruded, converted to mesh
    bpy.ops.object.text_add(location=(0, plaque_y - 0.045, 0.172))
    txt = bpy.context.active_object
    txt.data.body = "ONE GUN TROPHY"
    txt.data.size = 0.062
    txt.data.extrude = 0.010
    txt.data.align_x = 'CENTER'
    txt.data.offset = 0.002
    txt.rotation_euler = (math.radians(90) - tilt, 0, 0)
    bpy.ops.object.convert(target='MESH')
    txt = bpy.context.active_object
    txt.name = "PlaqueText"
    txt.data.materials.append(GOLD_LIT)
    parts.append(txt)

    # --- Join ---------------------------------------------------------------
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    pedestal = bpy.context.active_object
    pedestal.name = "TrophyPedestal"
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')   # origin at floor center

    os.makedirs(OUT_DIR, exist_ok=True)
    blend_path = os.path.join(OUT_DIR, "TrophyPedestal.blend")
    glb_path = os.path.join(OUT_DIR, "TrophyPedestal.glb")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format='GLB', export_apply=True)
    print("WROTE:", blend_path)
    print("WROTE:", glb_path)

clear_scene()
build()
