#!/usr/bin/env python3
"""Create left/right one-shoe GLBs without modifying the original pickup model."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from glb_geometry_edit import _load_glb, _write_glb


_INDEX_FORMATS = {5121: "B", 5123: "H", 5125: "I"}


def _accessor_layout(document: dict, accessor_index: int) -> tuple[dict, dict, int, int]:
    accessor = document["accessors"][accessor_index]
    view = document["bufferViews"][accessor["bufferView"]]
    base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return accessor, view, base, view.get("byteStride", 0)


def _position(binary: bytearray, document: dict, accessor_index: int, vertex: int) -> tuple[float, float, float]:
    accessor, _view, base, stride = _accessor_layout(document, accessor_index)
    if accessor.get("componentType") != 5126 or accessor.get("type") != "VEC3":
        raise ValueError("Spring shoe positions must be float32 VEC3")
    stride = stride or 12
    return struct.unpack_from("<3f", binary, base + vertex * stride)


def split(input_path: Path, output_path: Path, keep_side: str) -> None:
    document, binary, extra_chunks = _load_glb(input_path)
    kept_vertices: set[int] = set()
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            position_accessor = primitive.get("attributes", {}).get("POSITION")
            index_accessor = primitive.get("indices")
            if position_accessor is None or index_accessor is None:
                raise ValueError("Expected an indexed spring-shoe primitive")
            accessor, _view, base, stride = _accessor_layout(document, index_accessor)
            fmt = _INDEX_FORMATS.get(accessor.get("componentType"))
            if fmt is None:
                raise ValueError("Unsupported shoe index component type")
            width = struct.calcsize(fmt)
            stride = stride or width
            count = int(accessor["count"])
            if count % 3 != 0:
                raise ValueError("Expected triangle-list shoe geometry")
            indices = [struct.unpack_from("<" + fmt, binary, base + i * stride)[0] for i in range(count)]
            keep_triangles: list[bool] = []
            for tri in range(0, count, 3):
                tri_indices = indices[tri:tri + 3]
                # The authored pair sits on opposite sides of Z=0 and runs
                # lengthwise along X. Splitting on X cuts both shoes down the
                # middle; Z keeps one complete shoe on each side of an X-axis
                # dividing line.
                centroid_z = sum(_position(binary, document, position_accessor, vertex)[2] for vertex in tri_indices) / 3.0
                keep = centroid_z <= 0.0 if keep_side == "left" else centroid_z > 0.0
                keep_triangles.append(keep)
                if keep:
                    kept_vertices.update(tri_indices)
            if not kept_vertices:
                raise ValueError(f"No {keep_side} shoe triangles found")
            fallback = min(kept_vertices)
            for triangle_index, keep in enumerate(keep_triangles):
                if keep:
                    continue
                first = triangle_index * 3
                for offset in range(3):
                    struct.pack_into("<" + fmt, binary, base + (first + offset) * stride, fallback)
            positions = [_position(binary, document, position_accessor, vertex) for vertex in kept_vertices]
            center_x = (min(value[0] for value in positions) + max(value[0] for value in positions)) * 0.5
            floor_y = min(value[1] for value in positions)
            center_z = (min(value[2] for value in positions) + max(value[2] for value in positions)) * 0.5
            _position_accessor, _position_view, position_base, position_stride = _accessor_layout(
                document, position_accessor
            )
            position_stride = position_stride or 12
            for vertex in kept_vertices:
                x, y, z = _position(binary, document, position_accessor, vertex)
                struct.pack_into(
                    "<3f",
                    binary,
                    position_base + vertex * position_stride,
                    x - center_x,
                    y - floor_y,
                    z - center_z,
                )
            positions = [_position(binary, document, position_accessor, vertex) for vertex in kept_vertices]
            document["accessors"][position_accessor]["min"] = [min(value[axis] for value in positions) for axis in range(3)]
            document["accessors"][position_accessor]["max"] = [max(value[axis] for value in positions) for axis in range(3)]
    document.setdefault("asset", {})["generator"] = "One Gun single spring-shoe extractor"
    _write_glb(output_path, document, binary, extra_chunks)
    print(f"Created {keep_side} shoe: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--side", choices=["left", "right"], required=True)
    args = parser.parse_args()
    split(args.input, args.output, args.side)


if __name__ == "__main__":
    main()
