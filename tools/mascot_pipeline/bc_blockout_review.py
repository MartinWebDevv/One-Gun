"""Compose Section 3 Blue Cat reference overlays and a review contact sheet.

Run after ``bc_blockout.py`` with the workspace Python runtime.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
QA = ROOT / "art_src/mascots/blue_cat/qa"

OVERLAY_OUT = RENDERS / "S3_BlueCat_Blockout_ReferenceOverlay_v001.png"
REVIEW_OUT = RENDERS / "S3_BlueCat_Blockout_ReviewSheet_v001.png"
TURNTABLE_OUT = RENDERS / "S3_BlueCat_Turntable_v001.webp"
TURNTABLE_CONTACT_OUT = RENDERS / "S3_BlueCat_TurntableContact_v001.png"

SIZE = 1024
CAMERA_TARGET_Z = 0.70
CAMERA_ORTHO_SCALE = 1.70
CAMERA_TOP_Z = CAMERA_TARGET_Z + CAMERA_ORTHO_SCALE / 2
TARGET_PX_PER_M = SIZE / CAMERA_ORTHO_SCALE

BG = (14, 17, 24)
PANEL = (22, 27, 38)
LINE = (62, 71, 90)
TEXT = (232, 235, 241)
MUTED = (162, 171, 187)
GREEN = (88, 220, 139)
GOLD = (246, 190, 66)
CYAN = (74, 193, 239)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "arialbd.ttf" if bold else "arial.ttf"
    try:
        return ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), size)
    except OSError:
        return ImageFont.load_default()


def contain(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = min(width / image.width, height / image.height)
    return image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )


def reference_canvas(
    sheet: Image.Image,
    crop_box: tuple[int, int, int, int],
    source_ear_y: int,
    source_floor_y: int,
) -> Image.Image:
    """Place a source crop into the exact Blender camera meter mapping."""
    crop = sheet.crop(crop_box).convert("RGBA")
    source_ppm = (source_floor_y - source_ear_y) / 1.40
    resize_scale = TARGET_PX_PER_M / source_ppm
    crop = crop.resize(
        (round(crop.width * resize_scale), round(crop.height * resize_scale)),
        Image.Resampling.LANCZOS,
    )
    ear_target_y = round((CAMERA_TOP_Z - 1.40) * TARGET_PX_PER_M)
    top = round(ear_target_y - (source_ear_y - crop_box[1]) * resize_scale)
    left = (SIZE - crop.width) // 2
    canvas = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
    canvas.alpha_composite(crop, (left, top))
    return canvas


def add_metric_guides(image: Image.Image, label: str) -> Image.Image:
    out = image.copy()
    draw = ImageDraw.Draw(out)
    floor_y = round((CAMERA_TOP_Z - 0.0) * TARGET_PX_PER_M)
    ear_y = round((CAMERA_TOP_Z - 1.40) * TARGET_PX_PER_M)
    center_x = SIZE // 2
    draw.line((0, floor_y, SIZE, floor_y), fill=GOLD + (220,), width=2)
    draw.line((0, ear_y, SIZE, ear_y), fill=GOLD + (160,), width=1)
    draw.line((center_x, 0, center_x, SIZE), fill=CYAN + (90,), width=1)
    draw.rounded_rectangle((16, 15, 425, 54), radius=10, fill=(10, 13, 19, 220), outline=LINE + (255,), width=1)
    draw.text((29, 23), label, fill=TEXT + (255,), font=font(18, True))
    draw.text((15, floor_y - 29), "0.00 m", fill=GOLD + (255,), font=font(15, True))
    draw.text((15, ear_y + 8), "1.40 m", fill=GOLD + (255,), font=font(15, True))
    return out


def overlay(reference: Image.Image, render: Image.Image, label: str) -> Image.Image:
    render = render.convert("RGBA")
    alpha = render.getchannel("A").point(lambda value: round(value * 0.58))
    render.putalpha(alpha)
    combined = Image.alpha_composite(reference.convert("RGBA"), render)
    return add_metric_guides(combined, label)


def build_overlays() -> None:
    sheet = Image.open(SHEET).convert("RGB")
    front_ref = reference_canvas(sheet, (262, 90, 384, 275), 97, 268)
    side_ref = reference_canvas(sheet, (243, 590, 335, 730), 596, 724)
    front_render = Image.open(QA / "S3_BlueCat_Blockout_FrontAlpha_v001.png")
    side_render = Image.open(QA / "S3_BlueCat_Blockout_SideAlpha_v001.png")

    front_ref = add_metric_guides(front_ref, "LOCKED LINEUP FRONT")
    side_ref = add_metric_guides(side_ref, "LOCKED BACK-3/4 / NEAR-PROFILE")
    front_mix = overlay(reference_canvas(sheet, (262, 90, 384, 275), 97, 268), front_render, "FRONT OVERLAY — 58% BLOCKOUT")
    side_mix = overlay(reference_canvas(sheet, (243, 590, 335, 730), 596, 724), side_render, "SIDE OVERLAY — SOURCE IS NOT TRUE ORTHO")

    canvas = Image.new("RGB", (SIZE * 2, SIZE * 2 + 112), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 20), "BLUE CAT — SECTION 3 REFERENCE OVERLAYS v001", fill=TEXT, font=font(32, True))
    draw.text((24, 65), "Same 1.40 m camera mapping • source left • blockout overlay right", fill=MUTED, font=font(19))
    canvas.paste(front_ref.convert("RGB"), (0, 112))
    canvas.paste(front_mix.convert("RGB"), (SIZE, 112))
    canvas.paste(side_ref.convert("RGB"), (0, 112 + SIZE))
    canvas.paste(side_mix.convert("RGB"), (SIZE, 112 + SIZE))
    draw.line((SIZE, 112, SIZE, canvas.height), fill=LINE, width=3)
    draw.line((0, 112 + SIZE, canvas.width, 112 + SIZE), fill=LINE, width=3)
    canvas.save(OVERLAY_OUT)
    print(f"WROTE: {OVERLAY_OUT} {canvas.size}")


def build_black_silhouette() -> None:
    """Create a true shape-only pass from the transparent front render."""
    front = Image.open(QA / "S3_BlueCat_Blockout_FrontAlpha_v001.png").convert("RGBA")
    alpha = front.getchannel("A").point(lambda value: 255 if value >= 8 else 0)
    silhouette = Image.new("RGB", front.size, (242, 242, 242))
    silhouette.paste((0, 0, 0), (0, 0, front.width, front.height), alpha)
    path = RENDERS / "S3_BlueCat_Blockout_BlackSilhouette_v001.png"
    silhouette.save(path)
    print(f"WROTE: {path} {silhouette.size}")


def draw_tile(canvas: Image.Image, index: int, title: str, image_path: Path, note: str) -> None:
    draw = ImageDraw.Draw(canvas)
    width, height = canvas.size
    margin, gap, header = 34, 22, 120
    tile_w = (width - margin * 2 - gap * 2) // 3
    tile_h = 690
    col, row = index % 3, index // 3
    x = margin + col * (tile_w + gap)
    y = header + row * (tile_h + gap)
    draw.rounded_rectangle((x, y, x + tile_w, y + tile_h), radius=18, fill=PANEL, outline=LINE, width=2)
    draw.text((x + 18, y + 16), title, fill=TEXT, font=font(21, True))
    image = Image.open(image_path).convert("RGB")
    shown = contain(image, tile_w - 32, tile_h - 104)
    px = x + (tile_w - shown.width) // 2
    py = y + 55 + (tile_h - 112 - shown.height) // 2
    canvas.paste(shown, (px, py))
    draw.text((x + 18, y + tile_h - 37), note, fill=MUTED, font=font(15))


def build_review_sheet() -> None:
    canvas = Image.new("RGB", (2400, 1560), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((38, 28), "BLUE CAT — SECTION 3 BLOCKOUT REVIEW v001", fill=TEXT, font=font(36, True))
    draw.text((38, 76), "1.40 m A-pose • temporary editable masses • fixed orthographic cameras", fill=MUTED, font=font(20))
    tiles = [
        ("FRONT", RENDERS / "S3_BlueCat_Blockout_Front_v001.png", "fixed orthographic camera"),
        ("SIDE", RENDERS / "S3_BlueCat_Blockout_Side_v001.png", "fixed orthographic camera"),
        ("BACK", RENDERS / "S3_BlueCat_Blockout_Back_v001.png", "fixed orthographic camera"),
        ("THREE-QUARTER", RENDERS / "S3_BlueCat_Blockout_ThreeQuarter_v001.png", "neutral studio lighting"),
        ("BLACK SILHOUETTE", RENDERS / "S3_BlueCat_Blockout_BlackSilhouette_v001.png", "shape-only readability check"),
        ("REFERENCE OVERLAY", OVERLAY_OUT, "front + near-profile comparison"),
    ]
    for i, tile in enumerate(tiles):
        draw_tile(canvas, i, *tile)
    canvas.save(REVIEW_OUT)
    print(f"WROTE: {REVIEW_OUT} {canvas.size}")


def build_turntable() -> None:
    frame_dir = QA / "turntable_frames_v001"
    paths = sorted(frame_dir.glob("S3_BlueCat_Turntable_*.png"))
    if len(paths) != 48:
        raise ValueError(f"Expected 48 turntable frames, found {len(paths)}")
    frames = [Image.open(path).convert("RGB") for path in paths]
    frames[0].save(
        TURNTABLE_OUT,
        save_all=True,
        append_images=frames[1:],
        duration=42,
        loop=0,
        format="WEBP",
        quality=88,
        method=4,
    )
    print(f"WROTE: {TURNTABLE_OUT} ({len(frames)} frames)")

    # Eight-angle static contact sheet for reviewers who cannot play animation.
    selected = [frames[index] for index in range(0, 48, 6)]
    contact = Image.new("RGB", (4 * 420, 2 * 455 + 78), BG)
    draw = ImageDraw.Draw(contact)
    draw.text((22, 18), "BLUE CAT — 360° TURNTABLE CONTACT v001", fill=TEXT, font=font(28, True))
    for i, frame in enumerate(selected):
        shown = contain(frame, 400, 400)
        x = (i % 4) * 420 + 10
        y = 68 + (i // 4) * 455
        contact.paste(shown, (x + (400 - shown.width) // 2, y))
        draw.text((x + 12, y + 405), f"{i * 45:03d}°", fill=GOLD, font=font(17, True))
    contact.save(TURNTABLE_CONTACT_OUT)
    print(f"WROTE: {TURNTABLE_CONTACT_OUT} {contact.size}")


def main() -> None:
    build_turntable()
    build_black_silhouette()
    build_overlays()
    build_review_sheet()


if __name__ == "__main__":
    main()
