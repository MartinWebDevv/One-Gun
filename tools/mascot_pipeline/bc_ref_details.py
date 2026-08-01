"""Create the corrected Blue Cat Section 2 detail-reference sheet.

All image tiles are aspect-preserving crops from the approved concept.  Notes
call out contradictions and proposals instead of resolving them silently.

Run:
    python tools/mascot_pipeline/bc_ref_details.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png"
PALETTE = ROOT / "art_src/mascots/blue_cat/ref/BlueCat_Palette_sampled_v002.png"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
OUT = RENDERS / "S2_BlueCat_DetailGuides_v002.png"

W, H = 2400, 1660
MARGIN, GAP = 38, 24
HEADER_H = 130
TILE_W = (W - MARGIN * 2 - GAP * 2) // 3
TILE_H = 500

BG = (14, 17, 24)
PANEL = (22, 27, 38)
LINE = (63, 72, 91)
TEXT = (231, 234, 240)
MUTED = (161, 170, 187)
GREEN = (88, 220, 139)
GOLD = (246, 190, 66)
ORANGE = (247, 145, 70)


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


def pair_image(sheet: Image.Image, boxes: list[tuple[int, int, int, int]]) -> Image.Image:
    images = [sheet.crop(box) for box in boxes]
    height = max(image.height for image in images)
    width = sum(image.width for image in images) + 12 * (len(images) - 1)
    out = Image.new("RGB", (width, height), BG)
    x = 0
    for image in images:
        out.paste(image, (x, (height - image.height) // 2))
        x += image.width + 12
    return out


def draw_tile(
    canvas: Image.Image,
    index: int,
    title: str,
    image: Image.Image,
    note: str,
    status: str = "LOCKED EVIDENCE",
) -> None:
    draw = ImageDraw.Draw(canvas)
    col, row = index % 3, index // 3
    x = MARGIN + col * (TILE_W + GAP)
    y = HEADER_H + row * (TILE_H + GAP)
    draw.rounded_rectangle((x, y, x + TILE_W, y + TILE_H), radius=18, fill=PANEL, outline=LINE, width=2)

    status_color = GREEN if status == "LOCKED EVIDENCE" else ORANGE
    draw.text((x + 18, y + 16), title, fill=TEXT, font=font(22, True))
    badge_w = 175 if status == "LOCKED EVIDENCE" else 128
    draw.rounded_rectangle((x + TILE_W - badge_w - 18, y + 14, x + TILE_W - 18, y + 45), radius=8,
                           fill=tuple(c // 6 for c in status_color), outline=status_color, width=1)
    draw.text((x + TILE_W - badge_w + 1, y + 20), status, fill=status_color, font=font(12, True))

    image_box = (x + 18, y + 58, x + TILE_W - 18, y + 380)
    shown = contain(image, image_box[2] - image_box[0], image_box[3] - image_box[1])
    px = image_box[0] + (image_box[2] - image_box[0] - shown.width) // 2
    py = image_box[1] + (image_box[3] - image_box[1] - shown.height) // 2
    canvas.paste(shown, (px, py))
    draw.rectangle(image_box, outline=(48, 55, 70), width=1)
    draw.multiline_text((x + 18, y + 397), note, fill=MUTED, font=font(16), spacing=5)


def draw_register(canvas: Image.Image) -> None:
    draw = ImageDraw.Draw(canvas)
    y0 = HEADER_H + 2 * (TILE_H + GAP)
    draw.rounded_rectangle((MARGIN, y0, W - MARGIN, H - 36), radius=20, fill=(35, 25, 22), outline=ORANGE, width=2)
    draw.text((MARGIN + 24, y0 + 20), "INFERENCE + CONTRADICTION REGISTER", fill=ORANGE, font=font(24, True))

    left = [
        ("TRUE SIDE / BACK", "Not supplied. v002 turnaround panels are proposal envelopes only."),
        ("HAND CONSTRUCTION", "Source reads as a mitten. 3 fingers + thumb remains a rigging proposal."),
        ("BACK MARKINGS", "None are shown. Proposal is plain blue; no new patch or seam is introduced."),
    ]
    right = [
        ("HANDS / FEET", "Lineup shows blue limbs with cream palm/toe caps; toy guide reads mostly cream. Proposal: lineup master wins."),
        ("TAIL", "Thickness and cream tip are visible; exact rear carry and curl are not."),
        ("WHISKERS / BROWS", "Three cream whiskers per cheek and two cream brow dashes per eye are directly visible."),
    ]
    for col, items in enumerate((left, right)):
        x = MARGIN + 26 + col * 1155
        for i, (title, body) in enumerate(items):
            y = y0 + 76 + i * 112
            draw.text((x, y), title, fill=TEXT, font=font(18, True))
            draw.multiline_text((x, y + 30), body, fill=MUTED, font=font(16), spacing=4)
    draw.text(
        (MARGIN + 26, H - 77),
        "No realistic fur, sharp anatomy, extra clothing, muscle definition, or unapproved markings were added.",
        fill=GOLD,
        font=font(17, True),
    )


def main() -> None:
    RENDERS.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGB")
    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((MARGIN, 27), "BLUE CAT — DETAIL GUIDES v002", fill=TEXT, font=font(38, True))
    draw.text((MARGIN, 79), "Approved close-ups • proportion-preserving presentation • unresolved choices flagged", fill=MUTED, font=font(21))

    tiles = [
        (
            "NEUTRAL FACE",
            sheet.crop((258, 425, 355, 530)),
            "Large rounded head; neutral W-mouth; cream muzzle/chin;\nthree cream whiskers per cheek; small crown tufts.",
        ),
        (
            "EYE CONSTRUCTION",
            sheet.crop((262, 448, 310, 496)),
            "Dark outer rim → cream sclera → deep-green edge → green iris\n→ black pupil → large upper-left and small lower-right highlights.",
        ),
        (
            "MOUTH + MUZZLE",
            sheet.crop((278, 476, 338, 516)),
            "Cream double-lobe muzzle, compact dark triangular nose,\nshallow W-mouth line, separate cream chin pad.",
        ),
        (
            "HAND MARKING EVIDENCE",
            pair_image(sheet, [(352, 195, 384, 230), (1262, 228, 1308, 272)]),
            "Left: lineup master, blue mitt + cream palm. Right: toy guide,\nmostly cream paw. CONTRADICTION — lineup treatment is proposed.",
        ),
        (
            "FOOT MARKING EVIDENCE",
            pair_image(sheet, [(290, 245, 345, 275), (1285, 275, 1350, 315)]),
            "Left: lineup blue foot + cream toe cap. Right: toy guide reads\nmostly cream. Sturdy rounded foot silhouette remains locked.",
        ),
        (
            "TAIL SHAPE + TIP",
            pair_image(sheet, [(210, 650, 320, 730), (430, 565, 530, 710)]),
            "Thick flexible blue tail with rounded cream tip is visible.\nExact neutral back-view curl remains a proposal.",
        ),
    ]
    for i, (title, image, note) in enumerate(tiles):
        draw_tile(canvas, i, title, image, note)

    draw_register(canvas)
    canvas.save(OUT)
    print(f"WROTE: {OUT} {canvas.size}")


if __name__ == "__main__":
    main()
