"""Create the corrected Blue Cat Section 2 turnaround review sheet.

Only the front and rear three-quarter/near-profile images are directly shown
by the approved concept.  True side, true back, and relaxed A-pose panels are
therefore rendered as explicit construction proposals, never as locked art.

Run:
    python tools/mascot_pipeline/bc_ref_turnaround.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png"
RENDERS = ROOT / "art_src/mascots/blue_cat/renders"
OUT = RENDERS / "S2_BlueCat_TurnaroundReview_v002.png"

W, H = 2600, 1820
MARGIN = 34
HEADER_H = 138
PANEL_W = 500
PANEL_TOP = 148
PANEL_BOTTOM = 1234
SCALE = 480.0  # composed pixels per meter in every view panel
FLOOR = 1014.0

BG = (14, 17, 24)
PANEL = (22, 27, 38)
LINE = (62, 71, 90)
GRID = (43, 49, 62)
TEXT = (231, 234, 240)
MUTED = (160, 170, 187)
GREEN = (87, 221, 139)
ORANGE = (247, 145, 70)
GOLD = (247, 191, 66)
BLUE = (56, 108, 168)
BLUE_LIT = (73, 118, 168)
BLUE_DARK = (39, 75, 122)
CREAM = (196, 197, 189)
PINK = (198, 92, 122)
EYE = (87, 133, 45)
DARK = (8, 13, 17)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "arialbd.ttf" if bold else "arial.ttf"
    try:
        return ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), size)
    except OSError:
        return ImageFont.load_default()


def m2y(meters: float) -> float:
    return FLOOR - meters * SCALE


def panel_center(index: int) -> float:
    return MARGIN + PANEL_W * index + PANEL_W / 2


def paste_metric(
    canvas: Image.Image,
    sheet: Image.Image,
    crop_box: tuple[int, int, int, int],
    source_top: int,
    source_floor: int,
    index: int,
) -> None:
    """Paste source evidence so top-to-floor spans the official 1.40 m."""
    crop = sheet.crop(crop_box)
    source_ppm = (source_floor - source_top) / 1.40
    resize_scale = SCALE / source_ppm
    crop = crop.resize(
        (round(crop.width * resize_scale), round(crop.height * resize_scale)),
        Image.Resampling.LANCZOS,
    )
    top = m2y(1.40) - (source_top - crop_box[1]) * resize_scale
    left = panel_center(index) - crop.width / 2
    canvas.paste(crop, (round(left), round(top)))


def capsule(draw: ImageDraw.ImageDraw, start, end, width: int, fill, outline=None, outline_w: int = 0) -> None:
    draw.line((start, end), fill=outline or fill, width=width + outline_w * 2)
    r = width / 2 + outline_w
    for x, y in (start, end):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=outline or fill)
    if outline and outline_w:
        draw.line((start, end), fill=fill, width=width)
        r = width / 2
        for x, y in (start, end):
            draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def thick_curve(draw: ImageDraw.ImageDraw, points, width: int, fill) -> None:
    """Draw a rounded thick polyline without segment gaps at tight bends."""
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width / 2
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def draw_shared_grid(draw: ImageDraw.ImageDraw, index: int) -> None:
    x0 = MARGIN + PANEL_W * index
    x1 = x0 + PANEL_W - 8
    draw.rounded_rectangle((x0, PANEL_TOP, x1, PANEL_BOTTOM), radius=18, fill=PANEL, outline=LINE, width=2)
    h = 0.0
    while h <= 1.4001:
        y = m2y(h)
        major = round(h * 10) % 2 == 0
        draw.line((x0 + 12, y, x1 - 12, y), fill=GRID if not major else (57, 63, 75), width=1)
        if major:
            draw.text((x0 + 17, y - 18), f"{h:.1f}m", fill=(103, 111, 128), font=font(13, True))
        h += 0.10
    draw.line((x0 + 12, FLOOR, x1 - 12, FLOOR), fill=GOLD, width=2)


def draw_side_proposal(draw: ImageDraw.ImageDraw, index: int) -> None:
    cx = panel_center(index) - 8
    outline_w = 5
    # Ear behind, head, visible ear.
    draw.polygon(
        ((cx - 98, m2y(1.19)), (cx - 68, m2y(1.40)), (cx - 12, m2y(1.22))),
        fill=BLUE_DARK,
        outline=ORANGE,
    )
    draw.polygon(
        ((cx + 45, m2y(1.20)), (cx + 87, m2y(1.38)), (cx + 118, m2y(1.14))),
        fill=BLUE,
        outline=ORANGE,
    )
    draw.polygon(
        ((cx + 66, m2y(1.22)), (cx + 84, m2y(1.33)), (cx + 98, m2y(1.19))),
        fill=PINK,
    )
    head = (cx - 128, m2y(1.30), cx + 170, m2y(0.72))
    draw.ellipse(head, fill=BLUE, outline=ORANGE, width=outline_w)
    # Body, limbs, foot.
    draw.ellipse((cx - 102, m2y(0.72), cx + 100, m2y(0.25)), fill=BLUE_LIT, outline=ORANGE, width=outline_w)
    draw.ellipse((cx + 21, m2y(0.66), cx + 102, m2y(0.28)), fill=CREAM, outline=ORANGE, width=3)
    capsule(draw, (cx - 25, m2y(0.35)), (cx - 20, m2y(0.13)), 85, BLUE, ORANGE, 4)
    draw.ellipse((cx - 44, m2y(0.16), cx + 108, FLOOR), fill=BLUE, outline=ORANGE, width=5)
    draw.ellipse((cx + 27, m2y(0.15), cx + 108, FLOOR - 2), fill=CREAM)
    capsule(draw, (cx - 55, m2y(0.61)), (cx - 25, m2y(0.34)), 65, BLUE, ORANGE, 4)
    draw.ellipse((cx - 60, m2y(0.38), cx + 12, m2y(0.25)), fill=BLUE, outline=ORANGE, width=3)
    draw.ellipse((cx - 43, m2y(0.35), cx - 2, m2y(0.28)), fill=CREAM)
    # Face and muzzle profile.
    draw.ellipse((cx + 46, m2y(1.17), cx + 114, m2y(0.96)), fill=CREAM, outline=DARK, width=3)
    draw.ellipse((cx + 66, m2y(1.14), cx + 103, m2y(1.00)), fill=EYE, outline=CREAM, width=7)
    draw.ellipse((cx + 82, m2y(1.11), cx + 99, m2y(1.01)), fill=DARK)
    draw.ellipse((cx + 104, m2y(0.99), cx + 185, m2y(0.80)), fill=CREAM, outline=ORANGE, width=3)
    draw.polygon(((cx + 164, m2y(0.94)), (cx + 182, m2y(0.91)), (cx + 165, m2y(0.88))), fill=DARK)
    # Tail evidence envelope.
    points = []
    for i in range(31):
        t = i / 30
        x = cx - 68 - 150 * t + 28 * t * t
        y = m2y(0.27 + 0.16 * t + 0.02 * t * t)
        points.append((x, y))
    thick_curve(draw, points, 65, ORANGE)
    thick_curve(draw, points, 55, BLUE)
    thick_curve(draw, points[-7:], 55, CREAM)


def draw_back_proposal(draw: ImageDraw.ImageDraw, index: int) -> None:
    cx = panel_center(index)
    # Head and rear-facing ears; no invented back marking.
    draw.polygon(((cx - 150, m2y(1.16)), (cx - 112, m2y(1.40)), (cx - 44, m2y(1.22))), fill=BLUE, outline=ORANGE)
    draw.polygon(((cx + 44, m2y(1.22)), (cx + 112, m2y(1.40)), (cx + 150, m2y(1.16))), fill=BLUE, outline=ORANGE)
    draw.ellipse((cx - 181, m2y(1.30), cx + 181, m2y(0.72)), fill=BLUE, outline=ORANGE, width=5)
    # Tufts are directly supported; rear shape is still proposal.
    draw.polygon(
        ((cx - 42, m2y(1.30)), (cx - 20, m2y(1.37)), (cx, m2y(1.31)), (cx + 22, m2y(1.38)), (cx + 43, m2y(1.29))),
        fill=BLUE_LIT,
        outline=ORANGE,
    )
    draw.ellipse((cx - 125, m2y(0.72), cx + 125, m2y(0.25)), fill=BLUE_LIT, outline=ORANGE, width=5)
    capsule(draw, (cx - 122, m2y(0.62)), (cx - 172, m2y(0.35)), 70, BLUE, ORANGE, 4)
    capsule(draw, (cx + 122, m2y(0.62)), (cx + 172, m2y(0.35)), 70, BLUE, ORANGE, 4)
    draw.ellipse((cx - 205, m2y(0.39), cx - 140, m2y(0.26)), fill=BLUE, outline=ORANGE, width=4)
    draw.ellipse((cx + 140, m2y(0.39), cx + 205, m2y(0.26)), fill=BLUE, outline=ORANGE, width=4)
    capsule(draw, (cx - 68, m2y(0.30)), (cx - 73, m2y(0.10)), 93, BLUE, ORANGE, 4)
    capsule(draw, (cx + 68, m2y(0.30)), (cx + 73, m2y(0.10)), 93, BLUE, ORANGE, 4)
    draw.ellipse((cx - 142, m2y(0.15), cx - 8, FLOOR), fill=BLUE, outline=ORANGE, width=5)
    draw.ellipse((cx + 8, m2y(0.15), cx + 142, FLOOR), fill=BLUE, outline=ORANGE, width=5)
    # Tail crosses rear silhouette; cream cap is visible in locked side evidence.
    points = []
    for i in range(41):
        t = i / 40
        x = cx + 35 + 210 * t - 40 * t * t
        y = m2y(0.26 + 0.13 * t + 0.11 * t * t)
        points.append((x, y))
    thick_curve(draw, points, 66, ORANGE)
    thick_curve(draw, points, 56, BLUE_DARK)
    thick_curve(draw, points[-8:], 56, CREAM)


def draw_apose_proposal(draw: ImageDraw.ImageDraw, index: int) -> None:
    cx = panel_center(index)
    # Centerline and shoulder/hip construction guides.
    draw.line((cx, m2y(1.4), cx, FLOOR), fill=(87, 95, 112), width=2)
    draw.line((cx - 180, m2y(0.65), cx + 180, m2y(0.65)), fill=(65, 73, 90), width=2)
    draw.line((cx - 130, m2y(0.29), cx + 130, m2y(0.29)), fill=(65, 73, 90), width=2)

    draw.polygon(((cx - 154, m2y(1.16)), (cx - 113, m2y(1.40)), (cx - 45, m2y(1.22))), fill=BLUE, outline=ORANGE)
    draw.polygon(((cx + 45, m2y(1.22)), (cx + 113, m2y(1.40)), (cx + 154, m2y(1.16))), fill=BLUE, outline=ORANGE)
    draw.ellipse((cx - 180, m2y(1.30), cx + 180, m2y(0.72)), fill=BLUE, outline=ORANGE, width=5)
    draw.ellipse((cx - 115, m2y(0.72), cx + 115, m2y(0.27)), fill=BLUE_LIT, outline=ORANGE, width=5)
    draw.ellipse((cx - 74, m2y(0.68), cx + 74, m2y(0.31)), fill=CREAM, outline=ORANGE, width=3)

    # Relaxed symmetric A-pose: arms ~32 degrees from torso, soft elbow.
    for side in (-1, 1):
        shoulder = (cx + side * 112, m2y(0.64))
        elbow = (cx + side * 174, m2y(0.49))
        wrist = (cx + side * 210, m2y(0.34))
        capsule(draw, shoulder, elbow, 70, BLUE, ORANGE, 4)
        capsule(draw, elbow, wrist, 62, BLUE, ORANGE, 4)
        draw.ellipse((wrist[0] - 34, wrist[1] - 32, wrist[0] + 34, wrist[1] + 40), fill=BLUE, outline=ORANGE, width=4)
        draw.ellipse((wrist[0] - 21, wrist[1] - 13, wrist[0] + 21, wrist[1] + 29), fill=CREAM)
        # Three short finger separation lines: construction intent only.
        direction = 1 if side > 0 else -1
        for off in (-11, 0, 11):
            draw.line((wrist[0] + direction * 5, wrist[1] + off, wrist[0] + direction * 25, wrist[1] + off + 3), fill=BLUE_DARK, width=2)
        capsule(draw, (cx + side * 58, m2y(0.30)), (cx + side * 65, m2y(0.11)), 88, BLUE, ORANGE, 4)
        draw.ellipse((cx + side * 65 - 66, m2y(0.15), cx + side * 65 + 66, FLOOR), fill=BLUE, outline=ORANGE, width=5)
        draw.ellipse((cx + side * 65 - 45, m2y(0.14), cx + side * 65 + 45, FLOOR - 2), fill=CREAM)

    # Neutral face keeps the pose recognizable while remaining schematic.
    for side in (-1, 1):
        ex = cx + side * 72
        draw.ellipse((ex - 44, m2y(1.16), ex + 44, m2y(0.94)), fill=CREAM, outline=DARK, width=3)
        draw.ellipse((ex - 22, m2y(1.13), ex + 22, m2y(0.98)), fill=EYE)
        draw.ellipse((ex - 9, m2y(1.10), ex + 9, m2y(1.00)), fill=DARK)
    draw.ellipse((cx - 72, m2y(0.98), cx + 72, m2y(0.78)), fill=CREAM, outline=ORANGE, width=3)
    draw.polygon(((cx - 13, m2y(0.93)), (cx + 13, m2y(0.93)), (cx, m2y(0.88))), fill=DARK)


def panel_label(draw: ImageDraw.ImageDraw, index: int, title: str, status: str, note: str) -> None:
    x = MARGIN + PANEL_W * index
    color = GREEN if status == "LOCKED" else ORANGE
    draw.text((x + 16, PANEL_BOTTOM - 172), title, fill=TEXT, font=font(19, True))
    draw.rounded_rectangle((x + 16, PANEL_BOTTOM - 133, x + 138, PANEL_BOTTOM - 101), radius=8, fill=tuple(c // 6 for c in color), outline=color, width=1)
    draw.text((x + 28, PANEL_BOTTOM - 127), status, fill=color, font=font(14, True))
    draw.multiline_text((x + 16, PANEL_BOTTOM - 89), note, fill=MUTED, font=font(14), spacing=4)


def draw_footer(draw: ImageDraw.ImageDraw) -> None:
    y0 = 1262
    draw.rounded_rectangle((34, y0, 1655, 1784), radius=20, fill=PANEL, outline=LINE, width=2)
    draw.text((58, y0 + 22), "APPROVAL DECISIONS BEFORE SECTION 3", fill=GOLD, font=font(24, True))
    decisions = [
        ("01", "HAND / FOOT MARKINGS", "Proposal: lineup master wins — blue mitts with cream palms; blue feet with cream toe caps."),
        ("02", "TRUE SIDE DEPTH", "Proposal: head ≈0.62 m, body ≈0.42 m, muzzle projection 0.06–0.08 m, toe reach ≈0.30 m."),
        ("03", "BACK + TAIL", "Proposal: plain blue back with no new markings; tail root 0.26 m, 0.10–0.12 m thick, cream tip."),
        ("04", "MODELING POSE + HAND", "Proposal: symmetric relaxed A-pose, ~32° arms, soft elbows, 3 sculpted fingers plus thumb."),
    ]
    for i, (number, title, body) in enumerate(decisions):
        y = y0 + 78 + i * 101
        draw.rounded_rectangle((58, y, 112, y + 54), radius=14, fill=(52, 39, 22), outline=GOLD, width=2)
        draw.text((72, y + 14), number, fill=GOLD, font=font(18, True))
        draw.text((132, y + 1), title, fill=TEXT, font=font(18, True))
        draw.text((132, y + 31), body, fill=MUTED, font=font(16))

    x0 = 1680
    draw.rounded_rectangle((x0, y0, 2566, 1784), radius=20, fill=(35, 25, 22), outline=ORANGE, width=2)
    draw.text((x0 + 28, y0 + 22), "READING THIS SHEET", fill=ORANGE, font=font(24, True))
    draw.rounded_rectangle((x0 + 28, y0 + 78, x0 + 168, y0 + 116), radius=9, fill=(16, 55, 39), outline=GREEN, width=2)
    draw.text((x0 + 49, y0 + 86), "LOCKED", fill=GREEN, font=font(16, True))
    draw.text((x0 + 190, y0 + 84), "direct crop from approved art", fill=TEXT, font=font(17))
    draw.rounded_rectangle((x0 + 28, y0 + 133, x0 + 168, y0 + 171), radius=9, fill=(58, 34, 21), outline=ORANGE, width=2)
    draw.text((x0 + 40, y0 + 141), "PROPOSAL", fill=ORANGE, font=font(16, True))
    draw.text((x0 + 190, y0 + 139), "construction guide awaiting approval", fill=TEXT, font=font(17))
    draw.multiline_text(
        (x0 + 28, y0 + 212),
        "The approved sheet contains no true orthographic side,\n"
        "true back, or neutral three-quarter render. The v001\n"
        "sheet mirrored the same near-profile evidence and filled\n"
        "a front silhouette; v002 does not present either as fact.\n\n"
        "Every panel uses the same 480 px/m vertical ruler.\n"
        "Proposal art is a dimensional envelope for review, not\n"
        "final character art and not authorization to model.",
        fill=MUTED,
        font=font(18),
        spacing=9,
    )


def main() -> None:
    RENDERS.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGB")
    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((38, 28), "BLUE CAT — TURNAROUND REVIEW v002", fill=TEXT, font=font(38, True))
    draw.text((38, 80), "Common 1.40 m scale • locked evidence and inferred construction never mixed", fill=MUTED, font=font(21))

    for i in range(5):
        draw_shared_grid(draw, i)

    # Locked source evidence.
    paste_metric(canvas, sheet, (262, 90, 384, 275), 97, 268, 0)
    paste_metric(canvas, sheet, (243, 590, 335, 730), 596, 724, 1)
    draw = ImageDraw.Draw(canvas)

    # Explicit proposals for views/pose the source does not supply.
    draw_side_proposal(draw, 2)
    draw_back_proposal(draw, 3)
    draw_apose_proposal(draw, 4)

    panel_label(draw, 0, "FRONT", "LOCKED", "lineup master\nneutral, arms down")
    panel_label(draw, 1, "BACK 3/4 / NEAR-PROFILE", "LOCKED", "scale panel evidence\nnot a true orthographic side")
    panel_label(draw, 2, "TRUE SIDE ENVELOPE", "PROPOSAL", "depth and muzzle interpretation\nawaiting approval")
    panel_label(draw, 3, "TRUE BACK ENVELOPE", "PROPOSAL", "plain back + tail carry\nawaiting approval")
    panel_label(draw, 4, "MODELING A-POSE", "PROPOSAL", "symmetrical construction target\nawaiting approval")
    draw_footer(draw)

    canvas.save(OUT)
    print(f"WROTE: {OUT} {canvas.size}")


if __name__ == "__main__":
    main()
