#!/usr/bin/env python3
"""Generate the 1024x1024 app icon.

Reproduces the red Flash-player look of the original listing, but with a
deliberately non-overlapping composition:

  top    - white broken ring + rounded play triangle
  bottom - italic "SWF" wordmark inside its own clear band

Nothing is drawn on top of anything else, so no glyph is ever clipped or
merged with the ring.

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

EDGE_RED = (176, 8, 0)
CORE_RED = (252, 96, 78)
WHITE = (255, 255, 255)

# Vertical bands: ring occupies the top two thirds, wordmark its own band.
RING_CENTER_Y = 0.368
RING_RADIUS = 0.285
RING_WIDTH = 0.056
MARK_WIDTH = 0.60
MARK_HEIGHT = 0.170
MARK_BOTTOM = 0.900


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    raise SystemExit("No suitable bold font found; install Arial Black or edit FONT_CANDIDATES.")


def background() -> Image.Image:
    """Radial red gradient with the bright core slightly up-left, like the original."""
    radial = Image.radial_gradient("L").resize((int(S * 1.3), int(S * 1.3)), Image.BICUBIC)
    mask = Image.new("L", (S, S), 0)
    mask.paste(radial, (-int(S * 0.20), -int(S * 0.23)))
    return ImageOps.colorize(mask, black=EDGE_RED, white=CORE_RED).convert("RGB")


def draw_ring(image: Image.Image) -> None:
    draw = ImageDraw.Draw(image)
    center_x = S / 2.0
    center_y = S * RING_CENTER_Y
    radius = S * RING_RADIUS
    box = [center_x - radius, center_y - radius, center_x + radius, center_y + radius]
    # Opening on the right, matching the original's broken ring.
    draw.arc(box, start=14, end=346, fill=WHITE, width=int(S * RING_WIDTH))


def draw_triangle(image: Image.Image) -> None:
    center_x = S * 0.518
    center_y = S * RING_CENTER_Y
    half_h = S * 0.122
    half_w = S * 0.101
    points = [
        (int(center_x - half_w), int(center_y - half_h)),
        (int(center_x - half_w), int(center_y + half_h)),
        (int(center_x + half_w * 1.06), int(center_y)),
    ]
    # Blur-then-threshold is an SDF approximation: it rounds every corner
    # evenly and never bulges outside the silhouette.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(int(S * 0.013)))
    mask = mask.point(lambda value: 255 if value > 128 else 0)
    image.paste(Image.new("RGB", (S, S), WHITE), (0, 0), mask)


def draw_wordmark(image: Image.Image) -> None:
    """Italic SWF lettering, centred in its own band below the ring."""
    font = load_font(int(S * 0.24))
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    left, top, right, bottom = probe.textbbox((0, 0), "SWF", font=font)
    text_w, text_h = right - left, bottom - top

    layer = Image.new("RGBA", (text_w, text_h), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((-left, -top), "SWF", font=font, fill=(255, 255, 255, 255))

    # Italic slant: the top edge shifts right, the baseline stays put.
    shear = 0.16
    width, height = layer.size
    layer = layer.transform(
        (width + int(height * shear), height),
        Image.AFFINE,
        (1, -shear, shear * height, 0, 1, 0),
        resample=Image.BICUBIC,
    )

    # Fit the wordmark to an exact box so its footprint is predictable and it
    # can never creep back into the ring's band.
    target_w = int(S * MARK_WIDTH)
    target_h = int(S * MARK_HEIGHT)
    layer = layer.resize((target_w, target_h), Image.LANCZOS)

    x = (S - target_w) // 2
    y = int(S * MARK_BOTTOM) - target_h
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
