"""Render the Meal Notes app icon.

A bowl in profile with two written lines beneath it: a meal, and a note about
it. The second line is shorter, the way a real note tails off. Drawn at 4x and
downsampled so the curve stays smooth.

The palette is the app's own accent teal with a warm off-white, so the icon on
the home screen matches the tint inside the app. No alpha channel: iOS rejects
icons that have one.

Needs Pillow (`pip install pillow`), which is a tool for regenerating the
artwork, not a dependency of the app — the PNG it writes is checked in, so
nothing in the build or the test run needs Python at all.

    python3 scripts/make_icon.py
"""

import pathlib

from PIL import Image, ImageDraw

S, SS = 1024, 4
N = S * SS
TEAL = (22, 83, 109)        # AccentColor, light appearance
CREAM = (243, 238, 229)

# Geometry, laid out from the top of the bowl's rim and then centred vertically.
RADIUS, THICK = 286, 52
LINE_H, LINE_GAP = 59, 125
LINE_1_W, LINE_2_W = 623, 387

rim_to_bottom = THICK / 2 + RADIUS + 82 + LINE_GAP + LINE_H / 2
top = (S - rim_to_bottom) / 2
bowl_cy = top + THICK / 2
line_1_cy = bowl_cy + RADIUS + 82
line_2_cy = line_1_cy + LINE_GAP

img = Image.new("RGB", (N, N), TEAL)
d = ImageDraw.Draw(img)


def line(cx, cy, w, h):
    d.rounded_rectangle(
        [(cx - w / 2) * SS, (cy - h / 2) * SS, (cx + w / 2) * SS, (cy + h / 2) * SS],
        radius=(h / 2) * SS,
        fill=CREAM,
    )


# The bowl: a half-ring for the body, a flat bar for the rim.
d.arc(
    [(512 - RADIUS) * SS, (bowl_cy - RADIUS) * SS,
     (512 + RADIUS) * SS, (bowl_cy + RADIUS) * SS],
    start=0, end=180, fill=CREAM, width=int(THICK * SS),
)
line(512, bowl_cy, 2 * RADIUS + THICK, THICK)

line(512, line_1_cy, LINE_1_W, LINE_H)
line(512, line_2_cy, LINE_2_W, LINE_H)

out = pathlib.Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.resize((S, S), Image.LANCZOS).save(out)
print("wrote", out)
