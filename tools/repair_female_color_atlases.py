"""Restore shared face details missing from the female cat color atlases.

The female UV atlas intentionally differs around the torso, so this script
copies only three tightly masked pigments from the matching male atlas:
iris/pupil, inner-ear pink, and nose brown. Outputs are versioned siblings;
the delivered source textures are never overwritten.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
MALE_ROOT = ROOT / "models" / "player_v2"
FEMALE_ROOT = MALE_ROOT / "femaleOGCat" / "femaleOGCatCOLORS"

TEXTURES = {
    "black": ("colorVariants/OGCatModelV2 color black.png", "OGcat color black BOOBA.png"),
    "blue": ("OGCatModelV2_Rigged_OGcat color blue.png", "OGcat color blue BOOBA.png"),
    "brown": ("colorVariants/OGCatModelV2 color brown.png", "OGcat color brown BOOBA.png"),
    "cyan": ("colorVariants/OGCatModelV2 color cyan.png", "OGcat color cyan BOOBA.png"),
    "green": ("colorVariants/OGCatModelV2 color green.png", "OGcat color green BOOBA.png"),
    "grey": ("colorVariants/OGCatModelV2 color grey.png", "OGcat color grey BOOBA.png"),
    "orange": ("colorVariants/OGCatModelV2 color orange.png", "OGcat color orange BOOBA.png"),
    "pink": ("colorVariants/OGCatModelV2 color pink.png", "OGcat color pink BOOBA.png"),
    "purple": ("colorVariants/OGCatModelV2 color purple.png", "OGcat color purple BOOBA.png"),
    "red": ("colorVariants/OGCatModelV2 color red.png", "OGcat color red BOOBA.png"),
    "salmon": ("colorVariants/OGCatModelV2 color salam.png", "OGcat color salam BOOBA.png"),
    "white": ("colorVariants/OGCatModelV2 color white.png", "OGcat color white BOOBA.png"),
    "yellow": ("colorVariants/OGCatModelV2 color yellow.png", "OGcat color yellow BOOBA.png"),
}


def _mask_region(image: Image.Image, box: tuple[int, int, int, int], predicate) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    pixels = image.load()
    mask_pixels = mask.load()
    left, top, right, bottom = box
    for y in range(top, bottom):
        for x in range(left, right):
            if predicate(*pixels[x, y]):
                mask_pixels[x, y] = 255
    return mask


def _fill_mask_holes(mask: Image.Image, box: tuple[int, int, int, int]) -> None:
    """Fill enclosed holes, preserving the white catchlight inside the pupil."""
    pixels = mask.load()
    left, top, right, bottom = box
    queue: deque[tuple[int, int]] = deque()
    visited: set[tuple[int, int]] = set()
    for x in range(left, right):
        queue.append((x, top))
        queue.append((x, bottom - 1))
    for y in range(top, bottom):
        queue.append((left, y))
        queue.append((right - 1, y))
    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or pixels[x, y] != 0:
            continue
        visited.add((x, y))
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if left <= nx < right and top <= ny < bottom:
                queue.append((nx, ny))
    for y in range(top, bottom):
        for x in range(left, right):
            if pixels[x, y] == 0 and (x, y) not in visited:
                pixels[x, y] = 255


def _detail_mask(male: Image.Image) -> Image.Image:
    eye_box = (700, 350, 1024, 760)
    eye = _mask_region(
        male,
        eye_box,
        lambda r, g, b, a: a > 0
        and (max(r, g, b) < 80 or (r > 130 and g > 55 and b < 135 and r > b * 1.35)),
    )
    _fill_mask_holes(eye, eye_box)

    ear = _mask_region(
        male,
        (70, 420, 165, 525),
        lambda r, g, b, a: a > 0 and r > 155 and r > g + 35 and r > b + 20,
    )
    nose = _mask_region(
        male,
        (650, 655, 765, 785),
        lambda r, g, b, a: a > 0
        and 35 < r < 170 and 25 < g < 150 and b < 135 and r > b + 8,
    )

    mask = Image.new("L", male.size, 0)
    for detail in (eye, ear, nose):
        mask = ImageChops.lighter(mask, detail)
    return mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.65))


def repair(skin_id: str) -> Path:
    male_relative, female_name = TEXTURES[skin_id]
    male_path = MALE_ROOT / male_relative
    female_path = FEMALE_ROOT / female_name
    output_path = female_path.with_name(f"{female_path.stem} corrected.png")
    with Image.open(male_path) as male_source, Image.open(female_path) as female_source:
        male = male_source.convert("RGBA")
        female = female_source.convert("RGBA")
        if male.size != (1024, 1024) or female.size != male.size:
            raise ValueError(f"Unexpected atlas size for {skin_id}: {male.size} / {female.size}")
        corrected = Image.composite(male, female, _detail_mask(male))
        corrected.save(output_path, format="PNG", optimize=True)
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skin", choices=[*TEXTURES, "all"], default="blue")
    args = parser.parse_args()
    skin_ids = TEXTURES if args.skin == "all" else [args.skin]
    for skin_id in skin_ids:
        print(repair(skin_id).relative_to(ROOT).as_posix())


if __name__ == "__main__":
    main()
