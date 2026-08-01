"""Audit the saved Blue Cat Section 4 high-resolution source file."""

from __future__ import annotations

import bmesh
import bpy
from mathutils import Vector


shell = bpy.data.objects["BC_HighRes_BodyShell"]

bm = bmesh.new()
bm.from_mesh(shell.data)
bm.verts.ensure_lookup_table()
seen: set[int] = set()
components = 0
for vertex in bm.verts:
    if vertex.index in seen:
        continue
    components += 1
    stack = [vertex]
    seen.add(vertex.index)
    while stack:
        current = stack.pop()
        for edge in current.link_edges:
            neighbor = edge.other_vert(current)
            if neighbor.index not in seen:
                seen.add(neighbor.index)
                stack.append(neighbor)

nonmanifold = sum(1 for edge in bm.edges if not edge.is_manifold)
boundaries = sum(1 for edge in bm.edges if edge.is_boundary)
bm.free()

model_objects = [
    obj
    for obj in bpy.data.collections["BC_S4_HighResModel"].all_objects
    if obj.type in {"MESH", "CURVE"} and not obj.hide_render
]
points = [obj.matrix_world @ Vector(corner) for obj in model_objects for corner in obj.bound_box]

base_triangles = 0
for obj in model_objects:
    if obj.type == "MESH":
        obj.data.calc_loop_triangles()
        base_triangles += len(obj.data.loop_triangles)

print(f"AUDIT_HEIGHT_M={max(point.z for point in points) - min(point.z for point in points):.4f}")
print(
    "AUDIT_BOUNDS="
    f"x:{min(point.x for point in points):.4f}..{max(point.x for point in points):.4f} "
    f"y:{min(point.y for point in points):.4f}..{max(point.y for point in points):.4f} "
    f"z:{min(point.z for point in points):.4f}..{max(point.z for point in points):.4f}"
)
print(f"BODY_VERTS={len(shell.data.vertices)} BODY_FACES={len(shell.data.polygons)}")
print(f"BODY_COMPONENTS={components} NONMANIFOLD_EDGES={nonmanifold} BOUNDARY_EDGES={boundaries}")
print(f"BASE_TRIANGLES={base_triangles}")
print(f"UV_LAYERS={sum(len(mesh.uv_layers) for mesh in bpy.data.meshes)}")
print(f"ARMATURES={sum(1 for obj in bpy.data.objects if obj.type == 'ARMATURE')}")
construction = bpy.data.collections["BC_S4_EditableConstruction"]
print(f"CONSTRUCTION_OBJECTS={len(construction.all_objects)} HIDE_RENDER={construction.hide_render}")
print(f"BODY_MODIFIERS={[(modifier.name, modifier.type) for modifier in shell.modifiers]}")
print(f"FILE_TEXTURE_IMAGES={[(image.name, image.filepath) for image in bpy.data.images if image.source == 'FILE']}")
