# Two-row contact sheet of the city assets.
import bpy
import math
import os

ASSET_DIR = r"D:\Godot Projects\one-gun\models\cityAssets"
OUT = r"C:\Users\mc55j\AppData\Local\Temp\claude\D--Godot-Projects-one-gun\b705fca5-322e-49c7-8376-3d0aab3274b3\scratchpad\city_preview.png"

ROW1 = [
    ("CornerStore.glb", 1.0, 13), ("Diner.glb", 1.0, 14), ("Brownstone_Enterable.glb", 1.0, 11),
    ("Brownstone_A.glb", 1.0, 10), ("Facade_Tall.glb", 1.0, 8), ("Facade_Mid_A.glb", 1.0, 10),
]
ROW2 = [
    ("Car_Sedan.glb", 1.5, 8), ("Car_Taxi.glb", 1.5, 8), ("Car_Van.glb", 1.5, 9),
    ("FireHydrant.glb", 4.0, 4), ("LampPost.glb", 1.2, 4), ("TrafficLight.glb", 1.2, 6),
    ("TrashCan.glb", 3.0, 4), ("Dumpster.glb", 2.0, 6), ("Mailbox.glb", 3.0, 5),
    ("BusShelter.glb", 1.5, 7), ("BasketballHoop.glb", 1.4, 5), ("Cloud_B.glb", 0.6, 10),
]

for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)

def place_row(items, y):
    x = 0.0
    for fname, s, w in items:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ASSET_DIR, fname))
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.parent is None:
                o.scale = (s, s, s)
                o.location.x += x + w / 2
                o.location.y += y
        x += w
    return x

w1 = place_row(ROW1, 15)
w2 = place_row(ROW2, 0)
total_w = max(w1, w2)
bpy.ops.mesh.primitive_plane_add(size=total_w * 3, location=(total_w / 2, 7, -0.02))
sd = bpy.data.lights.new("Sun", type='SUN'); sd.energy = 3.0
sun = bpy.data.objects.new("Sun", sd); sun.rotation_euler = (math.radians(50), 0, math.radians(30))
bpy.context.collection.objects.link(sun)
cd = bpy.data.cameras.new("Cam"); cd.lens = 40
cam = bpy.data.objects.new("Cam", cd); bpy.context.collection.objects.link(cam)
cam.location = (total_w / 2, -total_w * 0.5, total_w * 0.25)
cam.rotation_euler = (math.radians(70), 0, 0)
bpy.context.scene.camera = cam
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.light = 'STUDIO'
sc.render.resolution_x = 2400
sc.render.resolution_y = 1000
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("PREVIEW SAVED")
