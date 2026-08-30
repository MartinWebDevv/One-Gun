#!/usr/bin/env python3
"""Small reproducible geometry fixes for binary glTF assets.

This intentionally only supports float32 POSITION accessors in GLB 2.0 files,
which is the format used by the City asset pack. It keeps the source asset
untouched when an output path is supplied.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


def _load_glb(path: Path) -> tuple[dict, bytearray, list[tuple[bytes, bytes]]]:
    data = path.read_bytes()
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(data):
        raise ValueError(f"{path} is not a valid GLB 2.0 file")

    cursor = 12
    document: dict | None = None
    binary = bytearray()
    extra_chunks: list[tuple[bytes, bytes]] = []
    while cursor < len(data):
        chunk_length, chunk_type = struct.unpack_from("<I4s", data, cursor)
        cursor += 8
        payload = data[cursor:cursor + chunk_length]
        cursor += chunk_length
        if chunk_type == b"JSON":
            document = json.loads(payload.decode("utf-8").rstrip(" \t\r\n\x00"))
        elif chunk_type == b"BIN\x00":
            binary = bytearray(payload)
        else:
            extra_chunks.append((chunk_type, payload))
    if document is None:
        raise ValueError(f"{path} has no JSON chunk")
    return document, binary, extra_chunks


def _write_glb(
    path: Path,
    document: dict,
    binary: bytearray,
    extra_chunks: list[tuple[bytes, bytes]],
) -> None:
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    chunks = [(b"JSON", json_bytes), (b"BIN\x00", bytes(binary)), *extra_chunks]
    total_length = 12 + sum(8 + len(payload) for _, payload in chunks)
    output = bytearray(struct.pack("<4sII", b"glTF", 2, total_length))
    for chunk_type, payload in chunks:
        output += struct.pack("<I4s", len(payload), chunk_type)
        output += payload
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(output)


def _position_accessors(document: dict, material_name: str | None = None) -> list[int]:
    material_index = None
    if material_name is not None:
        names = [material.get("name", "") for material in document.get("materials", [])]
        if material_name not in names:
            raise ValueError(f"Material {material_name!r} was not found")
        material_index = names.index(material_name)

    indices: list[int] = []
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if material_index is not None and primitive.get("material") != material_index:
                continue
            accessor_index = primitive.get("attributes", {}).get("POSITION")
            if accessor_index is not None and accessor_index not in indices:
                indices.append(accessor_index)
    if not indices:
        raise ValueError("No matching POSITION accessors were found")
    return indices


def _transform_positions(
    document: dict,
    binary: bytearray,
    accessor_indices: list[int],
    scale: float,
    offset: tuple[float, float, float],
) -> None:
    accessors = document["accessors"]
    buffer_views = document["bufferViews"]
    for accessor_index in accessor_indices:
        accessor = accessors[accessor_index]
        if accessor.get("componentType") != 5126 or accessor.get("type") != "VEC3":
            raise ValueError(f"Accessor {accessor_index} is not a float32 VEC3")
        view = buffer_views[accessor["bufferView"]]
        if view.get("buffer", 0) != 0:
            raise ValueError("Only GLBs using buffer 0 are supported")
        stride = view.get("byteStride", 12)
        base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        new_min = [float("inf")] * 3
        new_max = [float("-inf")] * 3
        for vertex_index in range(accessor["count"]):
            position_offset = base + vertex_index * stride
            source = struct.unpack_from("<3f", binary, position_offset)
            result = tuple(source[axis] * scale + offset[axis] for axis in range(3))
            struct.pack_into("<3f", binary, position_offset, *result)
            for axis in range(3):
                new_min[axis] = min(new_min[axis], result[axis])
                new_max[axis] = max(new_max[axis], result[axis])
        accessor["min"] = new_min
        accessor["max"] = new_max


def normalize(input_path: Path, output_path: Path, target_width: float) -> None:
    document, binary, extra_chunks = _load_glb(input_path)
    position_indices = _position_accessors(document)
    accessors = document["accessors"]
    minimum = [min(accessors[index]["min"][axis] for index in position_indices) for axis in range(3)]
    maximum = [max(accessors[index]["max"][axis] for index in position_indices) for axis in range(3)]
    horizontal_size = max(maximum[0] - minimum[0], maximum[2] - minimum[2])
    if horizontal_size <= 0.0:
        raise ValueError("Asset has no horizontal extent")
    scale = target_width / horizontal_size
    center_x = (minimum[0] + maximum[0]) * 0.5
    center_z = (minimum[2] + maximum[2]) * 0.5
    offset = (-center_x * scale, -minimum[1] * scale, -center_z * scale)
    _transform_positions(document, binary, position_indices, scale, offset)
    document.setdefault("asset", {})["generator"] = "One Gun City GLB geometry normalizer"
    _write_glb(output_path, document, binary, extra_chunks)
    print(f"Normalized {input_path} -> {output_path} (scale={scale:.10g})")


def translate_material(
    input_path: Path,
    output_path: Path,
    material_name: str,
    translation: tuple[float, float, float],
) -> None:
    document, binary, extra_chunks = _load_glb(input_path)
    position_indices = _position_accessors(document, material_name)
    _transform_positions(document, binary, position_indices, 1.0, translation)
    document.setdefault("asset", {})["generator"] = "One Gun City GLB geometry editor"
    _write_glb(output_path, document, binary, extra_chunks)
    print(f"Translated {material_name} in {input_path} -> {output_path}: {translation}")


def isolate_material(input_path: Path, output_path: Path, material_name: str) -> None:
    """Keep only primitives using one named material for a later prune/merge pass."""
    document, binary, extra_chunks = _load_glb(input_path)
    material_names = [material.get("name", "") for material in document.get("materials", [])]
    if material_name not in material_names:
        raise ValueError(f"Material {material_name!r} was not found")
    material_index = material_names.index(material_name)
    kept_meshes: set[int] = set()
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        primitives = [
            primitive for primitive in mesh.get("primitives", [])
            if primitive.get("material") == material_index
        ]
        mesh["primitives"] = primitives
        if primitives:
            kept_meshes.add(mesh_index)
    for node in document.get("nodes", []):
        if "mesh" in node and node["mesh"] not in kept_meshes:
            del node["mesh"]
    document.setdefault("asset", {})["generator"] = "One Gun GLB material isolator"
    _write_glb(output_path, document, binary, extra_chunks)
    print(f"Isolated material {material_name!r} from {input_path} -> {output_path}")


def isolate_node(input_path: Path, output_path: Path, node_name: str) -> None:
    """Keep the mesh referenced by one named node for a later prune/merge pass."""
    document, binary, extra_chunks = _load_glb(input_path)
    nodes = document.get("nodes", [])
    matching = [index for index, node in enumerate(nodes) if node.get("name", "") == node_name]
    if not matching:
        raise ValueError(f"Node {node_name!r} was not found")
    kept_meshes = {
        nodes[index]["mesh"] for index in matching if "mesh" in nodes[index]
    }
    if not kept_meshes:
        raise ValueError(f"Node {node_name!r} has no mesh")
    for index, node in enumerate(nodes):
        if index not in matching and "mesh" in node:
            del node["mesh"]
    document.setdefault("asset", {})["generator"] = "One Gun GLB node isolator"
    _write_glb(output_path, document, binary, extra_chunks)
    print(f"Isolated node {node_name!r} from {input_path} -> {output_path}")


def strip_attribute(input_path: Path, output_path: Path, attribute_name: str) -> None:
    """Drop an unused vertex attribute before prune/weld/simplify optimization."""
    document, binary, extra_chunks = _load_glb(input_path)
    removed = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes", {})
            if attribute_name in attributes:
                del attributes[attribute_name]
                removed += 1
    if removed == 0:
        raise ValueError(f"Attribute {attribute_name!r} was not found")
    document.setdefault("asset", {})["generator"] = "One Gun GLB attribute stripper"
    _write_glb(output_path, document, binary, extra_chunks)
    print(f"Stripped {attribute_name!r} from {removed} primitives: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    normalize_parser = subparsers.add_parser("normalize")
    normalize_parser.add_argument("input", type=Path)
    normalize_parser.add_argument("output", type=Path)
    normalize_parser.add_argument("--target-width", type=float, required=True)

    translate_parser = subparsers.add_parser("translate-material")
    translate_parser.add_argument("input", type=Path)
    translate_parser.add_argument("output", type=Path)
    translate_parser.add_argument("--material", required=True)
    translate_parser.add_argument("--x", type=float, default=0.0)
    translate_parser.add_argument("--y", type=float, default=0.0)
    translate_parser.add_argument("--z", type=float, default=0.0)

    material_parser = subparsers.add_parser("isolate-material")
    material_parser.add_argument("input", type=Path)
    material_parser.add_argument("output", type=Path)
    material_parser.add_argument("--material", required=True)

    node_parser = subparsers.add_parser("isolate-node")
    node_parser.add_argument("input", type=Path)
    node_parser.add_argument("output", type=Path)
    node_parser.add_argument("--node", required=True)

    attribute_parser = subparsers.add_parser("strip-attribute")
    attribute_parser.add_argument("input", type=Path)
    attribute_parser.add_argument("output", type=Path)
    attribute_parser.add_argument("--attribute", required=True)

    args = parser.parse_args()
    if args.command == "normalize":
        normalize(args.input, args.output, args.target_width)
    elif args.command == "translate-material":
        translate_material(
            args.input,
            args.output,
            args.material,
            (args.x, args.y, args.z),
        )
    elif args.command == "isolate-material":
        isolate_material(args.input, args.output, args.material)
    elif args.command == "isolate-node":
        isolate_node(args.input, args.output, args.node)
    else:
        strip_attribute(args.input, args.output, args.attribute)


if __name__ == "__main__":
    main()
