"""Create the corrected Blue Cat measured-proportion sheet for Section 2.

Measurements are normalized from the approved written height of 1.40 m and
explicit landmarks on the lineup front image.  The decorative scale-panel
grid is retained as source evidence but is not used as a ruler because it is
internally inconsistent with its own human silhouette and height caption.

Run:
    python tools/mascot_pipeline/bc_ref_measure.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png"
REF = ROOT / "art_src/mascots/blue_cat/ref"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
OUT = RENDERS / "S2_BlueCat_MeasuredProportions_v002.png"
PALETTE_OUT = REF / "BlueCat_Palette_sampled_v002.png"

BG = (14, 17, 24)
PANEL = (22, 27, 38)
LINE = (67, 76, 96)
TEXT = (231, 234, 240)
MUTED = (163, 172, 188)
GREEN = (88, 220, 139)
GOLD = (246, 190, 66)
CYAN = (81, 190, 235)
ORANGE = (245, 145, 70)

# Native lineup crop and explicit source landmarks.  Top/floor were confirmed
# against the visible ear tips and foot contact, not broad color segmentation.
LINEUP_BOX = (262, 90, 384, 275)
EAR_TIP_Y = 97
FLOOR_Y = 268
SOURCE_PX_PER_M = (FLOOR_Y - EAR_TIP_Y) / 1.40

# These satisfy every dimension requested by Section 2.  "Measured" values
# come from visible pixels.  "Estimated" values depend on fuzzy/overlapping
# edges.  "Proposal" values describe unseen depth or joint-center placement
# and are not approved design facts.
MEASUREMENTS = [
    ("Overall height", "1.40 m", "LOCKED", "written height; ear tip to floor"),
    ("Overall width", "0.89 m", "MEASURED", "widest visible arm/body span"),
    ("Head height", "0.68 m", "MEASURED", "ear tip to chin; dome-only 0.58 m"),
    ("Head width", "0.75 m", "MEASURED", "widest cheek span; dome span 0.65 m"),
    ("Iris size", "0.13 × 0.16 m", "MEASURED", "visible green iris ellipse"),
    ("Inner-eye gap", "0.16 m", "MEASURED", "nearest iris edges"),
    ("Muzzle", "0.34 × 0.18 m", "ESTIMATED", "center ≈0.86 m above floor"),
    ("Torso length", "0.37 m", "MEASURED", "shoulder line to crotch"),
    ("Shoulder width", "0.47 m", "ESTIMATED", "joint centers obscured by arms"),
    ("Arm length", "0.41 m", "ESTIMATED", "shoulder-to-wrist curved path"),
    ("Hand size", "0.17 × 0.21 m", "ESTIMATED", "one hanging mitten"),
    ("Leg length", "0.28 m", "MEASURED", "crotch to floor vertically"),
    ("Foot size", "0.25 × 0.16 m", "ESTIMATED", "one front foot silhouette"),
    ("Ear size", "0.17 × 0.27 m", "ESTIMATED", "one outer ear"),
    ("Tail thickness", "0.10–0.12 m", "MEASURED", "scale-panel/action views"),
    ("Stance width", "0.59 m", "MEASURED", "outer foot contact span"),
]

PROPOSAL_DEPTHS = [
    ("Head depth", "≈0.62 m", "from near-profile evidence"),
    ("Body depth", "≈0.42 m", "belly/rear envelope"),
    ("Muzzle projection", "0.06–0.08 m", "true side not supplied"),
    ("Toe reach", "≈0.30 m", "true side not supplied"),
]

HEIGHT_LANDMARKS = [
    ("ear tip", 1.40),
    ("head dome", 1.30),
    ("eye center", 1.00),
    ("nose", 0.90),
    ("chin", 0.72),
    ("shoulder", 0.65),
    ("hand bottom", 0.32),
    ("crotch", 0.28),
    ("tail root", 0.26),
    ("foot top", 0.15),
    ("floor", 0.00),
]

PALETTE = [
    ("Primary blue", "#386CA8"),
    ("Lit blue", "#4976A8"),
    ("Shadow blue", "#274B7A"),
    ("Deep shadow", "#1A3961"),
    ("Cream", "#C4C5BD"),
    ("Inner-ear pink", "#C65C7A"),
    ("Iris green", "#57852D"),
    ("Pupil / nose", "#040802"),
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "arialbd.ttf" if bold else "arial.ttf"
    try:
        return ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), size)
    except OSError:
        return ImageFont.load_default()


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def arrow(draw: ImageDraw.ImageDraw, start: tuple[float, float], end: tuple[float, float], color, width: int = 3) -> None:
    draw.line((start, end), fill=color, width=width)
    x1, y1 = start
    x2, y2 = end
    if abs(x2 - x1) >= abs(y2 - y1):
        draw.polygon(((x1, y1), (x1 + 12, y1 - 7), (x1 + 12, y1 + 7)), fill=color)
        draw.polygon(((x2, y2), (x2 - 12, y2 - 7), (x2 - 12, y2 + 7)), fill=color)
    else:
        draw.polygon(((x1, y1), (x1 - 7, y1 + 12), (x1 + 7, y1 + 12)), fill=color)
        draw.polygon(((x2, y2), (x2 - 7, y2 - 12), (x2 + 7, y2 - 12)), fill=color)


def make_palette() -> Image.Image:
    width, height = 2328, 190
    image = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(image)
    sw = width // len(PALETTE)
    for i, (name, value) in enumerate(PALETTE):
        x = i * sw
        draw.rectangle((x + 8, 8, x + sw - 8, 104), fill=hex_rgb(value), outline=(238, 238, 238), width=1)
        draw.text((x + 10, 116), name, fill=TEXT, font=font(16, True))
        draw.text((x + 10, 146), value, fill=MUTED, font=font(16))
    image.save(PALETTE_OUT)
    return image


def status_color(status: str) -> tuple[int, int, int]:
    return {"LOCKED": GREEN, "MEASURED": CYAN, "ESTIMATED": GOLD, "PROPOSAL": ORANGE}[status]


def draw_front_panel(canvas: Image.Image, sheet: Image.Image) -> None:
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = 36, 142, 1034, 1504
    draw.rounded_rectangle((x0, y0, x1, y1), radius=20, fill=PANEL, outline=LINE, width=2)
    draw.text((x0 + 24, y0 + 20), "FRONT MEASUREMENT MASTER", fill=GREEN, font=font(25, True))
    draw.text((x0 + 24, y0 + 55), "locked lineup view • normalized to written 1.40 m", fill=MUTED, font=font(18))

    scale = 700.0
    floor_y = 1272.0
    crop = sheet.crop(LINEUP_BOX)
    resize = (round(crop.width * scale / SOURCE_PX_PER_M), round(crop.height * scale / SOURCE_PX_PER_M))
    crop = crop.resize(resize, Image.Resampling.LANCZOS)
    crop_top = floor_y - (FLOOR_Y - LINEUP_BOX[1]) * scale / SOURCE_PX_PER_M
    crop_left = x0 + 190
    canvas.paste(crop, (round(crop_left), round(crop_top)))
    draw = ImageDraw.Draw(canvas)

    def sy(meters: float) -> float:
        return floor_y - meters * scale

    # 0.10 m ruler with 0.20 m labels.
    ruler_x = x0 + 76
    draw.line((ruler_x, sy(1.4), ruler_x, floor_y), fill=GOLD, width=3)
    step = 0.10
    h = 0.0
    while h <= 1.4001:
        y = sy(h)
        major = round(h * 10) % 2 == 0
        tick = 28 if major else 14
        draw.line((ruler_x - tick, y, ruler_x + tick, y), fill=GOLD if major else (137, 113, 54), width=2)
        if major:
            draw.text((ruler_x - 65, y - 12), f"{h:.1f}", fill=GOLD, font=font(15, True))
        h += step
    draw.text((ruler_x - 45, sy(1.4) - 36), "m", fill=GOLD, font=font(16, True))

    # Major height landmarks.  Alternate label columns to avoid collisions.
    for i, (label, meters) in enumerate(HEIGHT_LANDMARKS):
        y = sy(meters)
        draw.line((ruler_x + 31, y, x1 - 24, y), fill=(66, 73, 77), width=1)
        tx = x1 - (208 if i % 2 == 0 else 392)
        draw.rounded_rectangle((tx - 8, y - 14, tx + 172, y + 14), radius=7, fill=(17, 21, 29))
        draw.text((tx, y - 10), f"{label} {meters:.2f}", fill=MUTED, font=font(14))

    # Visible horizontal dimensions.  These are placed outside the face/body
    # so they remain reviewable without obscuring the source image.
    arrow(draw, (crop_left + 50, sy(0.83)), (crop_left + 50 + 0.75 * scale, sy(0.83)), CYAN)
    draw.text((crop_left + 214, sy(0.83) - 32), "head 0.75 m", fill=CYAN, font=font(17, True))
    arrow(draw, (crop_left + 11, sy(0.37)), (crop_left + 11 + 0.89 * scale, sy(0.37)), CYAN)
    draw.text((crop_left + 205, sy(0.37) + 14), "max span 0.89 m", fill=CYAN, font=font(17, True))
    arrow(draw, (crop_left + 120, floor_y + 24), (crop_left + 120 + 0.59 * scale, floor_y + 24), CYAN)
    draw.text((crop_left + 220, floor_y + 38), "stance 0.59 m", fill=CYAN, font=font(17, True))

    draw.rounded_rectangle((x0 + 22, y1 - 130, x1 - 22, y1 - 20), radius=14, fill=(40, 31, 22), outline=GOLD, width=2)
    draw.text((x0 + 42, y1 - 112), "CALIBRATION DECISION", fill=GOLD, font=font(18, True))
    draw.text((x0 + 42, y1 - 78), "Accept the printed PLAYER HEIGHT: ~1.4m statement.", fill=TEXT, font=font(18))
    draw.text((x0 + 42, y1 - 48), "Reject the decorative 0–2.5m grid as metric evidence; its silhouettes span incompatible heights.", fill=MUTED, font=font(16))


def draw_measurement_table(canvas: Image.Image) -> None:
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = 1060, 142, 2364, 1195
    draw.rounded_rectangle((x0, y0, x1, y1), radius=20, fill=PANEL, outline=LINE, width=2)
    draw.text((x0 + 24, y0 + 20), "VISIBLE PROPORTIONS", fill=TEXT, font=font(25, True))
    draw.text((x0 + 24, y0 + 56), "±0.02–0.05 m drawing uncertainty unless noted", fill=MUTED, font=font(17))

    headers = ("FEATURE", "RESULT", "CLASS", "BASIS")
    col_x = (x0 + 24, x0 + 310, x0 + 520, x0 + 720)
    row_y = y0 + 101
    for cx, header in zip(col_x, headers):
        draw.text((cx, row_y), header, fill=MUTED, font=font(15, True))
    draw.line((x0 + 20, row_y + 26, x1 - 20, row_y + 26), fill=LINE, width=2)

    row_h = 55
    for i, (feature, result, status, basis) in enumerate(MEASUREMENTS):
        y = row_y + 36 + i * row_h
        if i % 2:
            draw.rectangle((x0 + 16, y - 7, x1 - 16, y + row_h - 8), fill=(26, 32, 44))
        draw.text((col_x[0], y), feature, fill=TEXT, font=font(17, True))
        draw.text((col_x[1], y), result, fill=TEXT, font=font(17))
        color = status_color(status)
        draw.rounded_rectangle((col_x[2] - 4, y - 2, col_x[2] + 142, y + 26), radius=8, fill=tuple(max(0, c // 5) for c in color), outline=color, width=1)
        draw.text((col_x[2] + 7, y + 3), status, fill=color, font=font(13, True))
        draw.text((col_x[3], y), basis, fill=MUTED, font=font(15))

    # Proposal-only depth values are isolated from measured front proportions.
    py0 = 1223
    draw.rounded_rectangle((x0, py0, x1, 1504), radius=20, fill=(35, 25, 22), outline=ORANGE, width=2)
    draw.text((x0 + 24, py0 + 18), "UNSEEN DEPTH — PROPOSAL, NOT LOCKED", fill=ORANGE, font=font(22, True))
    draw.text((x0 + 24, py0 + 52), "These values may guide the Section 3 blockout only after approval.", fill=MUTED, font=font(17))
    for i, (feature, result, basis) in enumerate(PROPOSAL_DEPTHS):
        y = py0 + 94 + i * 41
        draw.text((x0 + 32, y), feature, fill=TEXT, font=font(17, True))
        draw.text((x0 + 310, y), result, fill=ORANGE, font=font(17, True))
        draw.text((x0 + 500, y), basis, fill=MUTED, font=font(16))


def main() -> None:
    RENDERS.mkdir(parents=True, exist_ok=True)
    REF.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGB")
    if sheet.size != (1536, 1024):
        raise ValueError(f"Approved sheet dimensions changed: expected 1536x1024, got {sheet.size}")

    canvas = Image.new("RGB", (2400, 1760), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((38, 30), "BLUE CAT — MEASURED PROPORTIONS v002", fill=TEXT, font=font(38, True))
    draw.text(
        (38, 82),
        "Locked height • explicit source landmarks • estimates and proposals separated",
        fill=MUTED,
        font=font(21),
    )
    draw_front_panel(canvas, sheet)
    draw_measurement_table(canvas)

    palette = make_palette()
    canvas.paste(palette, (36, 1548))
    canvas.save(OUT)
    print(f"WROTE: {PALETTE_OUT}")
    print(f"WROTE: {OUT} {canvas.size}")


if __name__ == "__main__":
    main()
