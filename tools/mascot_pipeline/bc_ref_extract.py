"""Build the locked-evidence portion of the Blue Cat Section 2 package.

The native crops are exact pixel crops from the approved concept sheet.  The
presentation crops and atlas are aspect-preserving resizes only; no warping,
paint-over, or generated detail is applied.

Run:
    python tools/mascot_pipeline/bc_ref_extract.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png"
REF = ROOT / "art_src/mascots/blue_cat/ref"
CROPS = REF / "crops"
NATIVE = CROPS / "native"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
ATLAS = RENDERS / "S2_BlueCat_LockedEvidenceAtlas_v002.png"

# (left, top, right, bottom) in the native 1536 x 1024 concept sheet.
# The scale factor is used only for the convenient presentation copy.
REGIONS = {
    "lineup_bluecat_front": ((255, 85, 385, 340), 4),
    "scale_proportions": ((15, 545, 375, 795), 3),
    "toy_style_guide": ((1265, 50, 1525, 390), 3),
    "expressions_row": ((245, 390, 1170, 540), 2),
    "animation_preview": ((375, 545, 1165, 730), 2),
    "weapon_holds": ((375, 730, 1040, 880), 2),
    "rig_tpose": ((1180, 395, 1525, 725), 2),
    "environment_example": ((1040, 870, 1525, 1020), 2),
    "color_material_palette": ((15, 795, 375, 1015), 3),
    "face_closeup_idle": ((258, 425, 355, 530), 6),
}

ATLAS_ORDER = [
    ("lineup_bluecat_front", "LINEUP FRONT", "primary silhouette and proportion evidence"),
    ("scale_proportions", "SCALE FRONT + NEAR-PROFILE", "written 1.4 m height; grid rejected as metric evidence"),
    ("toy_style_guide", "TOY STYLE GUIDE", "surface language, rounded forms, hands and feet"),
    ("expressions_row", "EXPRESSIONS", "neutral face plus expression range"),
    ("animation_preview", "ANIMATION EXAMPLES", "motion silhouette, tail and contact evidence"),
    ("weapon_holds", "WEAPON HOLDS", "two-hand and one-hand grip evidence"),
    ("rig_tpose", "RIG DIAGRAM", "topology/rig intent only; not the modeling pose"),
    ("environment_example", "ENVIRONMENT FIT", "game-camera readability and weapon scale"),
]

BG = (15, 18, 25)
PANEL = (23, 27, 38)
LINE = (62, 70, 89)
TEXT = (228, 232, 239)
MUTED = (161, 169, 184)
GREEN = (92, 220, 139)
GOLD = (246, 189, 65)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "arialbd.ttf" if bold else "arial.ttf"
    path = Path("C:/Windows/Fonts") / name
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def contain(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = min(width / image.width, height / image.height)
    return image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )


def build_atlas(native_images: dict[str, Image.Image]) -> None:
    width, height = 2400, 1760
    margin, gap = 42, 24
    header_h = 132
    tile_w = (width - margin * 2 - gap) // 2
    tile_h = (height - header_h - margin - gap * 3) // 4
    canvas = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(canvas)

    draw.text((margin, 28), "BLUE CAT — LOCKED EVIDENCE ATLAS v002", fill=TEXT, font=font(38, True))
    draw.text(
        (margin, 80),
        "Exact source crops from the approved concept • aspect ratio preserved • no design completion",
        fill=MUTED,
        font=font(22),
    )
    draw.rounded_rectangle((width - 474, 30, width - margin, 94), radius=16, fill=(19, 54, 39), outline=GREEN, width=2)
    draw.text((width - 447, 48), "LOCKED SOURCE EVIDENCE", fill=GREEN, font=font(22, True))

    for i, (name, label, note) in enumerate(ATLAS_ORDER):
        col, row = i % 2, i // 2
        x = margin + col * (tile_w + gap)
        y = header_h + row * (tile_h + gap)
        draw.rounded_rectangle((x, y, x + tile_w, y + tile_h), radius=18, fill=PANEL, outline=LINE, width=2)

        label_y = y + 16
        draw.text((x + 20, label_y), label, fill=GREEN, font=font(22, True))
        box = REGIONS[name][0]
        coords = f"source px {box[0]},{box[1]}–{box[2]},{box[3]}"
        bbox = draw.textbbox((0, 0), coords, font=font(16))
        draw.text((x + tile_w - (bbox[2] - bbox[0]) - 20, label_y + 4), coords, fill=MUTED, font=font(16))

        image_box = (x + 18, y + 54, x + tile_w - 18, y + tile_h - 58)
        available_w = image_box[2] - image_box[0]
        available_h = image_box[3] - image_box[1]
        shown = contain(native_images[name], available_w, available_h)
        px = image_box[0] + (available_w - shown.width) // 2
        py = image_box[1] + (available_h - shown.height) // 2
        canvas.paste(shown, (px, py))

        draw.line((x + 18, y + tile_h - 48, x + tile_w - 18, y + tile_h - 48), fill=LINE, width=1)
        draw.text((x + 20, y + tile_h - 38), note, fill=MUTED, font=font(17))

    RENDERS.mkdir(parents=True, exist_ok=True)
    canvas.save(ATLAS)
    print(f"WROTE: {ATLAS} {canvas.size}")


def main() -> None:
    CROPS.mkdir(parents=True, exist_ok=True)
    NATIVE.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGB")
    if sheet.size != (1536, 1024):
        raise ValueError(f"Approved sheet dimensions changed: expected 1536x1024, got {sheet.size}")

    native_images: dict[str, Image.Image] = {}
    for name, (box, scale) in REGIONS.items():
        native = sheet.crop(box)
        native_images[name] = native
        native_path = NATIVE / f"{name}.png"
        native.save(native_path)

        presented = native.resize(
            (native.width * scale, native.height * scale),
            Image.Resampling.LANCZOS,
        )
        presentation_path = CROPS / f"{name}.png"
        presented.save(presentation_path)
        print(f"WROTE: {native_path} {native.size}; presentation {presented.size}")

    build_atlas(native_images)


if __name__ == "__main__":
    main()
