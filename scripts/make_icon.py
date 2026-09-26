#!/usr/bin/env python3
"""Renders the Form app icon: a barbell seen end-on on navy, with faint knurling."""
from pathlib import Path
from PIL import Image, ImageDraw

S = 2048  # draw at 2x, downsample for smooth edges
OUT = Path(__file__).resolve().parent.parent / "ios/Form/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

NAVY = (28, 43, 69)
ORANGE = (226, 99, 42)
ORANGE_DARK = (168, 68, 26)
CHALK = (244, 239, 230)
CHROME = (163, 170, 179)
CHROME_LIGHT = (210, 215, 221)
INK = (22, 23, 26)

img = Image.new("RGB", (S, S), NAVY)

# Knurl texture
knurl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
k = ImageDraw.Draw(knurl)
step = 56
for x in range(-S, 2 * S, step):
    k.line([(x, 0), (x + S, S)], fill=(244, 239, 230, 14), width=4)
    k.line([(x + S, 0), (x, S)], fill=(244, 239, 230, 14), width=4)
img.paste(knurl, (0, 0), knurl)

d = ImageDraw.Draw(img)
cx, cy = S // 2, S // 2

def circle(r, fill=None, outline=None, width=0, dy=0):
    d.ellipse([cx - r, cy - r + dy, cx + r, cy + r + dy], fill=fill, outline=outline, width=width)

circle(760, fill=ORANGE_DARK, dy=36)                 # plate edge / shadow
circle(760, fill=ORANGE)                             # plate face
circle(600, outline=ORANGE_DARK, width=26)           # cast groove
circle(318, fill=(0, 0, 0), dy=18)                   # collar shadow
circle(318, fill=CHALK)                              # collar
circle(232, fill=CHROME)                             # sleeve
d.chord([cx - 232, cy - 232, cx + 232, cy + 232], 200, 290, fill=CHROME_LIGHT)  # sleeve highlight
circle(196, fill=CHROME)
circle(128, fill=INK)                                # bore

OUT.parent.mkdir(parents=True, exist_ok=True)
img.resize((1024, 1024), Image.LANCZOS).save(OUT)
print("wrote", OUT)
