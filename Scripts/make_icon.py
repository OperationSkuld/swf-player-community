#!/usr/bin/env python3
"""Generate the 1024x1024 app icon.

Composition (matching the reference design):
  - saturated red background
  - one large white broken ring filling most of the canvas
  - rounded white play triangle centred in the ring
  - italic "SWF" wordmark rotated ~40 deg in the lower-right corner,
    tucked into the ring's opening so no two white shapes overlap

Requires Pillow (``python -m pip install Pillow``). The generated PNG is
committed, so CI does not need Pillow.

Output is 8-bit RGB with NO alpha channel - Xcode / actool rejects RGBA
app icons.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

SIZE = 1024
SS = 4                      # supersampling factor
S = SIZE * SS
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SWFPlayer" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"

FONT_CANDIDATES = [
    r"C:/Windows/Fonts/ariblk.ttf",
    r"C:/Windows/Fonts/arialbd.ttf",
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/Library/Fonts/Arial Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

EDGE_RED = (206, 12, 4)
CORE_RED = (244, 40, 26)
WHITE = (255, 255, 255)

# --- geometry (fractions of the canvas) -----------------------------------
RING_CX = 0.500
RING_CY = 0.455
RING_OUTER = 0.424
RING_STROKE = 0.070
# Screen-space angles (0 deg = 3 o'clock, clockwise). The ring is left open at
# the lower right so the wordmark never has to cross the white band.
RING_ARC_START = 84.0
RING_ARC_END = 392.0            # 392 == 32 deg

SWOOSH_RADIUS = 0.432
SWOOSH_STROKE = 0.013

TRI_CX = 0.522
TRI_CY = 0.452
TRI_HALF_W = 0.117
TRI_HALF_H = 0.145

MARK_CX = 0.800
MARK_CY = 0.812
MARK_WIDTH = 0.330
MARK_HEIGHT = 0.305
MARK_ANGLE = 40.0


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    raise SystemExit("No suitable bold font found; install Arial Black or edit FONT_CANDIDATES.")


def background() -> Image.Image:
    """Nearly flat red, with the bright core slightly up-left, as in the reference."""
    radial = Image.radial_gradient("L").resize((int(S * 1.35), int(S * 1.35)), Image.BICUBIC)
    mask = Image.new("L", (S, S), 0)
    mask.paste(radial, (-int(S * 0.22), -int(S * 0.25)))
    return ImageOps.colorize(mask, black=EDGE_RED, white=CORE_RED).convert("RGB")


def draw_ring(image: Image.Image) -> None:
    draw = ImageDraw.Draw(image)
    cx, cy = S * RING_CX, S * RING_CY
    radius = S * RING_OUTER - S * RING_STROKE / 2
    box = [cx - radius, cy - radius, cx + radius, cy + radius]
    draw.arc(box, start=RING_ARC_START, end=RING_ARC_END,
             fill=WHITE, width=int(S * RING_STROKE))

    # Two thin satellite arcs: the small "orbit" detail from the reference.
    thin_radius = S * SWOOSH_RADIUS
    thin_box = [cx - thin_radius, cy - thin_radius, cx + thin_radius, cy + thin_radius]
    thin_width = int(S * SWOOSH_STROKE)
    draw.arc(thin_box, start=272, end=352, fill=WHITE, width=thin_width)
    draw.arc(thin_box, start=112, end=196, fill=WHITE, width=thin_width)


def draw_triangle(image: Image.Image) -> None:
    cx, cy = S * TRI_CX, S * TRI_CY
    half_w, half_h = S * TRI_HALF_W, S * TRI_HALF_H
    points = [
        (int(cx - half_w), int(cy - half_h)),
        (int(cx - half_w), int(cy + half_h)),
        (int(cx + half_w * 1.08), int(cy)),
    ]
    # Blur-then-threshold is an SDF approximation: it rounds every corner
    # evenly and never bulges outside the silhouette.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(int(S * 0.015)))
    mask = mask.point(lambda value: 255 if value > 128 else 0)
    image.paste(Image.new("RGB", (S, S), WHITE), (0, 0), mask)


def draw_wordmark(image: Image.Image) -> None:
    font = load_font(int(S * 0.20))
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    left, top, right, bottom = probe.textbbox((0, 0), "SWF", font=font)
    text_w, text_h = right - left, bottom - top

    layer = Image.new("RGBA", (text_w, text_h), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((-left, -top), "SWF", font=font, fill=(255, 255, 255, 255))

    # Italic slant, then rotate so the wordmark climbs to the upper right.
    shear = 0.14
    width, height = layer.size
    layer = layer.transform(
        (width + int(height * shear), height),
        Image.AFFINE,
        (1, -shear, shear * height, 0, 1, 0),
        resample=Image.BICUBIC,
    )
    layer = layer.rotate(MARK_ANGLE, expand=True, resample=Image.BICUBIC)

    # Fit to an exact footprint so its position stays predictable at any size.
    target_w = int(S * MARK_WIDTH)
    target_h = int(S * MARK_HEIGHT)
    scale = min(target_w / layer.width, target_h / layer.height)
    layer = layer.resize((max(1, int(layer.width * scale)), max(1, int(layer.height * scale))),
                         Image.LANCZOS)

    x = int(S * MARK_CX - layer.width / 2)
    y = int(S * MARK_CY - layer.height / 2)
    image.paste(layer, (x, y), layer)


def build() -> Image.Image:
    image = background()
    draw_ring(image)
    draw_triangle(image)
    draw_wordmark(image)
    return image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon = build()
    icon.save(OUT, format="PNG", optimize=True)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, mode={icon.mode})")
