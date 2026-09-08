"""Rebuild deterministic prototype textures. No game asset is modified."""
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "project" / "art"
OUT.mkdir(parents=True, exist_ok=True)
REPO = ROOT.parents[1]
FONT = REPO / "fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf"
rng = random.Random(1977)


def font(size):
    return ImageFont.truetype(str(FONT), size)

def surface(name, rgb, tile=False):
    im = Image.new("RGB", (512,512), rgb)
    im.putdata([tuple(max(0,min(255,c+rng.randrange(-5,6))) for c in rgb) for _ in range(512*512)])
    d = ImageDraw.Draw(im)
    if tile:
        for y in range(0, 512, 64):
            for x in range(-64 if (y // 64) % 2 else 0, 512, 128):
                c = tuple(max(0, min(255, v + rng.randint(-10, 7))) for v in rgb)
                d.rectangle((x + 2, y + 2, x + 126, y + 62), fill=c)
                d.line((x + 3, y + 3, x + 124, y + 3), fill=tuple(min(v+18, 255) for v in c))
    for _ in range(180):
        x, y = rng.randrange(512), rng.randrange(512)
        d.line((x, y, x+rng.randrange(-8, 9), y+rng.randrange(1, 24)), fill=tuple(max(25, c-25) for c in rgb))
    im.save(OUT / f"{name}.png")

surface("concrete", (111, 107, 92))
surface("tile", (151, 153, 137), True)
surface("floor", (81, 84, 76), True)

im = Image.new("RGB", (1024, 512), "#18242a")
d = ImageDraw.Draw(im)
for x in range(0, 1024, 32):
    d.line((x, 0, x, 512), fill="#202f35")
for y in range(0, 512, 32):
    d.line((0, y, 1024, y), fill="#202f35")
d.text((38, 22), "UNLISTED / TRANSIT AUTHORITY", font=font(34), fill="#e9dfba")
for color, pts in [("#d7ce45", [(40,390),(210,390),(320,220),(780,220),(930,95)]),
                   ("#51c5d3", [(90,140),(390,140),(580,370),(950,370)]),
                   ("#d07ab4", [(180,470),(460,260),(720,260),(880,460)])]:
    d.line(pts, fill=color, width=10)
    for x,y in pts[1:-1]:
        d.ellipse((x-10,y-10,x+10,y+10), fill="#e9dfba", outline="#18242a", width=4)
d.text((595,404), "YOU ARE NOT HERE.", font=font(35), fill="#e9dfba")
im.save(OUT / "route_map.png")

im = Image.new("RGB", (1024, 1024), "#d5cfad")
d = ImageDraw.Draw(im)
palette = ["#d9d63e", "#d977ad", "#62b8c4", "#e58849"]
posters = [("NO NAMES.", "NO FACES.", "ONE GUN."), ("THE WORLD", "IS YOUR", "ARENA."),
           ("AFTER", "HOURS", "ONLY."), ("TEN ENTER.", "ONE RULE.", "NO ALIBIS.")]
for i, lines in enumerate(posters):
    x,y = (i%2)*512, (i//2)*512
    d.rectangle((x+8,y+8,x+504,y+504), fill=palette[i])
    d.text((x+32,y+30), "OG / UNLISTED EVENTS", font=font(31), fill="#1d282b")
    for j, line in enumerate(lines):
        d.text((x+26,y+110+j*96), line, font=font(90 if len(line)<10 else 69), fill="#1d282b")
    d.text((x+30,y+450), "LOCATION WITHHELD // EST. 01", font=font(29), fill="#1d282b")
for _ in range(1400):
    x,y=rng.randrange(1024),rng.randrange(1024)
    d.line((x,y,x+rng.randrange(1,12),y+1),fill="#9d977e")
im.save(OUT / "posters.png")

im = Image.new("RGB", (1024, 1024), "#353c3b")
d = ImageDraw.Draw(im)
d.ellipse((32,32,992,992), outline="#b9b03f", width=18)
d.ellipse((64,64,960,960), outline="#707062", width=3)
d.text((512, 240), "NO NAMES. NO FACES.", anchor="mm",font=font(65),fill="#c6bc83")
d.text((512, 431), "ONE",anchor="mm",font=font(225),fill="#dfd742")
d.text((512, 626), "GUN",anchor="mm",font=font(225),fill="#dfd742")
d.text((512, 820), "THE LOCATION CHANGES.",anchor="mm",font=font(51),fill="#c6bc83")
d.text((512, 884), "THE RULE NEVER DOES.",anchor="mm",font=font(51),fill="#c6bc83")
for _ in range(6500):
    x,y=rng.randrange(1024),rng.randrange(1024)
    d.line((x,y,x+rng.randrange(1,10),y),fill="#353c3b")
im.save(OUT / "floor_seal.png")
(OUT / "heading.ttf").write_bytes(FONT.read_bytes())
print(f"Generated {len(list(OUT.iterdir()))} offline art assets in {OUT}")
