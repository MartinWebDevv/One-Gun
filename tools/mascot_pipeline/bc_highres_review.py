"""Package Blue Cat Section 4 renders into approval sheets and turntable."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
QA = ROOT / "art_src/mascots/blue_cat/qa"

OVERLAY_OUT = RENDERS / "S4_BlueCat_HighRes_ReferenceOverlay_v001.png"
SILHOUETTE_OUT = RENDERS / "S4_BlueCat_HighRes_BlackSilhouette_v001.png"
REVIEW_OUT = RENDERS / "S4_BlueCat_HighRes_ReviewSheet_v001.png"
CLOSEUPS_OUT = RENDERS / "S4_BlueCat_HighRes_DetailCloseups_v001.png"
WIRE_OUT = RENDERS / "S4_BlueCat_HighRes_WireReview_v001.png"
TURNTABLE_OUT = RENDERS / "S4_BlueCat_HighRes_Turntable_v001.webp"
TURNTABLE_CONTACT_OUT = RENDERS / "S4_BlueCat_HighRes_TurntableContact_v001.png"

SIZE = 1024
CAMERA_TOP_Z = 0.70 + 1.70 / 2
TARGET_PX_PER_M = SIZE / 1.70

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
    return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)


def reference_canvas(sheet, box, ear_y, floor_y) -> Image.Image:
    crop = sheet.crop(box).convert("RGBA")
    source_ppm = (floor_y - ear_y) / 1.40
    scale = TARGET_PX_PER_M / source_ppm
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
    target_ear = round((CAMERA_TOP_Z - 1.40) * TARGET_PX_PER_M)
    top = round(target_ear - (ear_y - box[1]) * scale)
    left = (SIZE - crop.width) // 2
    canvas = Image.new("RGBA", (SIZE, SIZE), BG + (255,))
    canvas.alpha_composite(crop, (left, top))
    return canvas


def guides(image: Image.Image, label: str) -> Image.Image:
    out = image.copy()
    draw = ImageDraw.Draw(out)
    floor_y = round((CAMERA_TOP_Z - 0.0) * TARGET_PX_PER_M)
    ear_y = round((CAMERA_TOP_Z - 1.40) * TARGET_PX_PER_M)
    draw.line((0, floor_y, SIZE, floor_y), fill=GOLD + (220,), width=2)
    draw.line((0, ear_y, SIZE, ear_y), fill=GOLD + (170,), width=1)
    draw.line((SIZE // 2, 0, SIZE // 2, SIZE), fill=CYAN + (90,), width=1)
    draw.rounded_rectangle((16, 15, 455, 54), radius=10, fill=(10, 13, 19, 220), outline=LINE + (255,), width=1)
    draw.text((28, 23), label, fill=TEXT + (255,), font=font(18, True))
    draw.text((14, ear_y + 8), "1.40 m", fill=GOLD + (255,), font=font(15, True))
    draw.text((14, floor_y - 28), "0.00 m", fill=GOLD + (255,), font=font(15, True))
    return out


def overlay(reference: Image.Image, render: Image.Image, label: str) -> Image.Image:
    render = render.convert("RGBA")
    render.putalpha(render.getchannel("A").point(lambda value: round(value * 0.58)))
    return guides(Image.alpha_composite(reference.convert("RGBA"), render), label)


def build_turntable() -> None:
    paths = sorted((QA / "s4_turntable_frames_v001").glob("S4_BlueCat_Turntable_*.png"))
    if len(paths) != 48:
        raise ValueError(f"Expected 48 Section 4 turntable frames, found {len(paths)}")
    frames = [Image.open(path).convert("RGB") for path in paths]
    frames[0].save(TURNTABLE_OUT, save_all=True, append_images=frames[1:], duration=42, loop=0, format="WEBP", quality=90, method=4)
    print(f"WROTE: {TURNTABLE_OUT} ({len(frames)} frames)")

    selected = [frames[index] for index in range(0, 48, 6)]
    contact = Image.new("RGB", (1680, 988), BG)
    draw = ImageDraw.Draw(contact)
    draw.text((22, 18), "BLUE CAT — SECTION 4 360° CONTACT v001", fill=TEXT, font=font(28, True))
    for i, frame in enumerate(selected):
        shown = contain(frame, 400, 400)
        x = (i % 4) * 420 + 10
        y = 68 + (i // 4) * 455
        contact.paste(shown, (x + (400 - shown.width) // 2, y))
        draw.text((x + 12, y + 405), f"{i * 45:03d}°", fill=GOLD, font=font(17, True))
    contact.save(TURNTABLE_CONTACT_OUT)
    print(f"WROTE: {TURNTABLE_CONTACT_OUT} {contact.size}")


def build_silhouette() -> None:
    front = Image.open(QA / "S4_BlueCat_HighRes_FrontAlpha_v001.png").convert("RGBA")
    alpha = front.getchannel("A").point(lambda value: 255 if value >= 8 else 0)
    image = Image.new("RGB", front.size, (242, 242, 242))
    image.paste((0, 0, 0), (0, 0, front.width, front.height), alpha)
    image.save(SILHOUETTE_OUT)
    print(f"WROTE: {SILHOUETTE_OUT} {image.size}")


def build_overlays() -> None:
    sheet = Image.open(SHEET).convert("RGB")
    front_ref_raw = reference_canvas(sheet, (262, 90, 384, 275), 97, 268)
    side_ref_raw = reference_canvas(sheet, (243, 590, 335, 730), 596, 724)
    front = Image.open(QA / "S4_BlueCat_HighRes_FrontAlpha_v001.png")
    side = Image.open(QA / "S4_BlueCat_HighRes_SideAlpha_v001.png")
    panes = [
        guides(front_ref_raw, "LOCKED LINEUP FRONT"),
        overlay(front_ref_raw, front, "HIGH-RES FRONT OVERLAY — 58% MODEL"),
        guides(side_ref_raw, "LOCKED BACK-3/4 / NEAR-PROFILE"),
        overlay(side_ref_raw, side, "HIGH-RES SIDE — SOURCE NOT TRUE ORTHO"),
    ]
    canvas = Image.new("RGB", (2048, 2160), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 20), "BLUE CAT — SECTION 4 REFERENCE OVERLAYS v001", fill=TEXT, font=font(32, True))
    draw.text((24, 65), "Same approved 1.40 m mapping • source left • model overlay right", fill=MUTED, font=font(19))
    for i, pane in enumerate(panes):
        x = (i % 2) * SIZE
        y = 112 + (i // 2) * SIZE
        canvas.paste(pane.convert("RGB"), (x, y))
    draw.line((SIZE, 112, SIZE, canvas.height), fill=LINE, width=3)
    draw.line((0, 112 + SIZE, canvas.width, 112 + SIZE), fill=LINE, width=3)
    canvas.save(OVERLAY_OUT)
    print(f"WROTE: {OVERLAY_OUT} {canvas.size}")


def tile(canvas, index, columns, header, tile_h, title, image_path, note):
    draw = ImageDraw.Draw(canvas)
    margin, gap = 34, 22
    tile_w = (canvas.width - margin * 2 - gap * (columns - 1)) // columns
    col, row = index % columns, index // columns
    x = margin + col * (tile_w + gap)
    y = header + row * (tile_h + gap)
    draw.rounded_rectangle((x, y, x + tile_w, y + tile_h), radius=18, fill=PANEL, outline=LINE, width=2)
    draw.text((x + 17, y + 15), title, fill=TEXT, font=font(20, True))
    image = Image.open(image_path).convert("RGB")
    shown = contain(image, tile_w - 30, tile_h - 100)
    px = x + (tile_w - shown.width) // 2
    py = y + 52 + (tile_h - 108 - shown.height) // 2
    canvas.paste(shown, (px, py))
    draw.text((x + 17, y + tile_h - 36), note, fill=MUTED, font=font(14))


def build_review_sheet() -> None:
    canvas = Image.new("RGB", (2400, 1560), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((38, 28), "BLUE CAT — SECTION 4 HIGH-RES REVIEW v001", fill=TEXT, font=font(36, True))
    draw.text((38, 76), "Continuous rounded body shell • premium-toy form pass • no UVs or rig", fill=MUTED, font=font(20))
    entries = [
        ("FRONT", RENDERS / "S4_BlueCat_HighRes_Front_v001.png", "fixed orthographic"),
        ("SIDE", RENDERS / "S4_BlueCat_HighRes_Side_v001.png", "fixed orthographic"),
        ("BACK", RENDERS / "S4_BlueCat_HighRes_Back_v001.png", "fixed orthographic"),
        ("THREE-QUARTER", RENDERS / "S4_BlueCat_HighRes_ThreeQuarter_v001.png", "neutral studio"),
        ("BLACK SILHOUETTE", SILHOUETTE_OUT, "shape-only readability"),
        ("REFERENCE OVERLAY", OVERLAY_OUT, "front + near-profile"),
    ]
    for i, entry in enumerate(entries):
        tile(canvas, i, 3, 120, 690, *entry)
    canvas.save(REVIEW_OUT)
    print(f"WROTE: {REVIEW_OUT} {canvas.size}")


def build_closeups() -> None:
    canvas = Image.new("RGB", (2400, 700), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((38, 24), "BLUE CAT — SECTION 4 FORM CLOSEUPS v001", fill=TEXT, font=font(34, True))
    draw.text((38, 68), "Face • continuous shoulder/arm • grip hand • stable feet • tail", fill=MUTED, font=font(19))
    entries = [
        ("FACE", RENDERS / "S4_BlueCat_Closeup_Face_v001.png", "eyes, lids, muzzle"),
        ("SHOULDERS", RENDERS / "S4_BlueCat_Closeup_Shoulders_v001.png", "continuous limb trunks"),
        ("HAND", RENDERS / "S4_BlueCat_Closeup_Hand_v001.png", "3 fingers + thumb"),
        ("FEET", RENDERS / "S4_BlueCat_Closeup_Feet_v001.png", "broad contact"),
        ("TAIL", RENDERS / "S4_BlueCat_Closeup_Tail_v001.png", "smooth root + tip"),
    ]
    for i, entry in enumerate(entries):
        tile(canvas, i, 5, 108, 550, *entry)
    canvas.save(CLOSEUPS_OUT)
    print(f"WROTE: {CLOSEUPS_OUT} {canvas.size}")


def build_wire_sheet() -> None:
    canvas = Image.new("RGB", (2048, 1120), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 20), "BLUE CAT — SECTION 4 WIREFRAME PREVIEW v001", fill=TEXT, font=font(31, True))
    draw.text((24, 64), "High-resolution source density • not Section 5 retopology", fill=MUTED, font=font(18))
    for i, (label, path) in enumerate((
        ("FRONT", RENDERS / "S4_BlueCat_HighRes_WireFront_v001.png"),
        ("THREE-QUARTER", RENDERS / "S4_BlueCat_HighRes_WireThreeQuarter_v001.png"),
    )):
        image = Image.open(path).convert("RGB")
        shown = contain(image, 1000, 1000)
        x = i * 1024 + (1024 - shown.width) // 2
        y = 105 + (1000 - shown.height) // 2
        canvas.paste(shown, (x, y))
        draw.text((i * 1024 + 24, 108), label, fill=CYAN, font=font(20, True))
    draw.line((1024, 100, 1024, 1120), fill=LINE, width=3)
    canvas.save(WIRE_OUT)
    print(f"WROTE: {WIRE_OUT} {canvas.size}")


def main() -> None:
    build_turntable()
    build_silhouette()
    build_overlays()
    build_review_sheet()
    build_closeups()
    build_wire_sheet()


if __name__ == "__main__":
    main()
