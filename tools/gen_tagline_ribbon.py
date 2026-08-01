# Blender 5.x headless generator for the main-menu TAGLINE RIBBON banner
# (concept art: blue folded ribbon under the logo; text is rendered live in
# Godot on top, so this is the blank banner shape only).
#
# Run:  & "D:\Blender\blender.exe" --background --factory-startup --python "tools/gen_tagline_ribbon.py"
# Outputs:
#   UI/MainMenu/TaglineRibbon.png    (transparent 1800x480 front render)
#   models/menu/TaglineRibbon.blend  (editable source)

import bpy
import math
import os

PNG_OUT = r"D:\Godot Projects\one-gun\UI\MainMenu\TaglineRibbon.png"
BLEND_OUT = r"D:\Godot Projects\one-gun\models\menu\TaglineRibbon.blend"

_materials = {}

def mat(name, color, roughness=0.45, metallic=0.0):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Emission Color"].default_value = color
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    _materials[name] = m
    return m

BLUE      = mat("RibbonBlue", (0.020, 0.090, 0.50, 1.0), 0.38)
BLUE_TAIL = mat("RibbonTail", (0.010, 0.050, 0.33, 1.0), 0.45)
BLUE_DARK = mat("RibbonFold", (0.005, 0.022, 0.15, 1.0), 0.5)
TRIM      = mat("RibbonTrim", (0.93, 0.68, 0.14, 1.0), 0.3, 1.0)

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True

def rbox(name, material, loc, scale, rot=(0, 0, 0), bevel=0.05):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.rotation_euler = rot
    m = o.modifiers.new("Bevel", 'BEVEL')
    m.width = bevel
    m.segments = 4
    o.data.materials.append(material)
    smooth(o)
    return o

def notch_cutter(loc, rot):
    # Triangular prism (3-vert cylinder) used to cut the ribbon-tail V notch.
    bpy.ops.mesh.primitive_cylinder_add(vertices=3, radius=0.34, depth=0.6, location=loc)
    o = bpy.context.active_object
    o.rotation_euler = rot
    o.hide_render = True
    return o

def build():
    parts = []

    # Central band — long, slightly plump, glossy toy plastic.
    band = rbox("Band", BLUE, (0, 0, 0), (2.55, 0.13, 0.44), (0, 0, 0), 0.07)
    parts.append(band)
    # Thin gold trim lines along top and bottom of the band.
    parts.append(rbox("TrimTop", TRIM, (0, -0.09, 0.40), (2.42, 0.05, 0.034), (0, 0, 0), 0.012))
    parts.append(rbox("TrimBot", TRIM, (0, -0.09, -0.40), (2.42, 0.05, 0.034), (0, 0, 0), 0.012))

    # Tails — angled down/outward, sitting slightly behind the band.
    for sx in (-1, 1):
        tail = rbox("Tail", BLUE_TAIL, (2.78 * sx, 0.16, -0.26), (0.58, 0.10, 0.38),
            (0, 0, math.radians(-14 * sx)), 0.05)
        cutter = notch_cutter((3.34 * sx, 0.16, -0.40), (math.radians(90), 0, math.radians(90 if sx > 0 else -90)))
        boolean = tail.modifiers.new("Notch", 'BOOLEAN')
        boolean.operation = 'DIFFERENCE'
        boolean.object = cutter
        parts.append(tail)
        # Fold connector — darker blue wedge behind the band's end.
        parts.append(rbox("Fold", BLUE_DARK, (2.46 * sx, 0.13, -0.34), (0.20, 0.08, 0.18),
            (0, 0, math.radians(28 * sx)), 0.03))

    return parts

def setup_render():
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'   # exact flat colors, no AgX wash
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 380
    scene.render.filepath = PNG_OUT

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 7.5
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, -8.0, -0.16)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam

    sun_data = bpy.data.lights.new("Sun", type='SUN')
    sun_data.energy = 2.4
    sun = bpy.data.objects.new("Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(78), 0, 0)   # near-frontal: even tone

    fill_data = bpy.data.lights.new("Fill", type='AREA')
    fill_data.energy = 90.0
    fill_data.size = 12.0
    fill = bpy.data.objects.new("Fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (0.0, -11.0, 1.2)
    fill.rotation_euler = (math.radians(88), 0, 0)

def main():
    clear_scene()
    build()
    setup_render()
    os.makedirs(os.path.dirname(PNG_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    bpy.ops.render.render(write_still=True)
    print("WROTE:", BLEND_OUT)
    print("WROTE:", PNG_OUT)

main()
