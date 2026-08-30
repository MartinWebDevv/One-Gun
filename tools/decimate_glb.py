#!/usr/bin/env python3
"""Decimate isolated solid-material GLB meshes while preserving scene transforms.

This is the fallback for disconnected curve/conversion geometry that
meshoptimizer cannot reduce without dropping the entire decorative primitive.
Source assets remain untouched; output is always a separate runtime candidate.

Build-time dependencies only (not shipped with or imported by Godot):
    python -m pip install trimesh fast-simplification
"""

from __future__ import annotations

import argparse
from pathlib import Path

import trimesh


def decimate(
    input_path: Path,
    output_path: Path,
    target_faces: int,
    aggression: int,
) -> None:
    scene = trimesh.load(input_path, force="scene", process=False)
    if not isinstance(scene, trimesh.Scene) or not scene.geometry:
        raise ValueError(f"{input_path} contains no scene geometry")
    total_faces = sum(len(mesh.faces) for mesh in scene.geometry.values())
    if total_faces <= target_faces:
        output_path.write_bytes(scene.export(file_type="glb"))
        return

    for name, source in list(scene.geometry.items()):
        share = max(round(target_faces * len(source.faces) / total_faces), 12)
        simplified = source.simplify_quadric_decimation(
            face_count=share,
            aggression=aggression,
        )
        material = getattr(source.visual, "material", None)
        if material is not None:
            simplified.visual = trimesh.visual.TextureVisuals(material=material)
        scene.geometry[name] = simplified

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(scene.export(file_type="glb"))
    final_faces = sum(len(mesh.faces) for mesh in scene.geometry.values())
    print(
        f"Decimated {input_path} -> {output_path}: "
        f"{total_faces} to {final_faces} faces"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--target-faces", type=int, required=True)
    parser.add_argument("--aggression", type=int, default=10)
    args = parser.parse_args()
    if args.target_faces < 12:
        raise ValueError("--target-faces must be at least 12")
    decimate(args.input, args.output, args.target_faces, args.aggression)


if __name__ == "__main__":
    main()
