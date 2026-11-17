#!/usr/bin/env python3
"""Generate the 1024x1024 app icon.

Composition (matching the original SWF Player icon):
  - saturated red background with a bright core
  - one large white ring whose stroke tapers to a fine point at both ends
    (the "brush stroke" look of the reference, not a uniform stroke)
  - a thin tapered swoosh trailing outside the ring on the upper right
  - rounded white play triangle inside the ring
  - italic "SWF" wordmark rotated in the lower-right gap

The arcs are drawn as variable-width polygons sampled in polar coordinates,
which is what gives the tapered, converging ends. Everything else is
supersampled 4x and downscaled for clean edges.

Requires Pillow (``python -m pip install Pillow``). The generated PNG is
committed, so CI does not need Pillow.

Output is 8-bit RGB with NO alpha channel - Xcode / actool rejects RGBA
app icons.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

SIZE = 1024
SS = 4                      # supersampling factor
S = SIZE * SS
ROOT = Path(__file__).resolve().parent.parent
OUT = (ROOT / "SWFPlayer" / "Resources" / "Assets.xcassets"
       / "AppIcon.appiconset" / "AppIcon-1024.png")

FONT_CANDIDATES = [
    r"C:/Windows/Fonts/ariblk.ttf",
    r"C:/Windows/Fonts/arialbd.ttf",
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/Library/Fonts/Arial Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

EDGE_RED = (198, 15, 6)
CORE_RED = (247, 56, 42)
WHITE = (255, 255, 255)

# --- geometry (fractions of the canvas) -----------------------------------
RING_CX = 0.500
RING_CY = 0.478
RING_RADIUS = 0.372          # centre line of the stroke
RING_STROKE = 0.082          # widest point of the stroke
RING_START = 66.0            # degrees, screen space (0 = 3 o'clock, cw)
RING_END = 384.0             # 384 == 24 deg -> gap sits at the lower right

SWOOSH_RADIUS = 0.452
SWOOSH_STROKE = 0.017
SWOOSH_START = 300.0
SWOOSH_END = 390.0

TRI_CX = 0.512
TRI_CY = 0.474
TRI_HALF_W = 0.118
TRI_HALF_H = 0.138

MARK_CX = 0.812
MARK_CY = 0.818
MARK_WIDTH = 0.320
MARK_HEIGHT = 0.312
MARK_ANGLE = 42.0


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    raise SystemExit("No suitable bold font found; install Arial Black or edit FONT_CANDIDATES.")


def background() -> Image.Image:
    """Bright core slightly up-left, deepening toward the edges."""
    radial = Image.radial_gradient("L").resize((int(S * 1.45), int(S * 1.45)), Image.BICUBIC)
    mask = Image.new("L", (S, S), 0)
    mask.paste(radial, (-int(S * 0.26), (-int(S * 0.28))))
    return ImageOps.colorize(mask, black=EDGE_RED, white=CORE_RED).convert("RGB")


def taper(progress: float) -> float:
    """Rounded brush-stroke profile: both ends converge to a fine, smooth tip.

    ``sin(pi * t)`` alone falls off too abruptly near the ends; raising it to a
    power > 1 makes both tips ease out gently (a rounded, converging taper like
    the original icon) instead of snapping to a hard point. A tiny floor keeps
    the very tip from turning into aliased specks after downsampling.
    """
    s = max(0.0, math.sin(math.pi * progress))
    return 0.018 + 0.982 * (s ** 1.35)


def draw_tapered_arc(draw: ImageDraw.ImageDraw,
                     cx: float, cy: float,
                     radius: float,
                     start_deg: float, end_deg: float,
                     max_width: float,
                     start_weight: float = 1.0,
                     end_weight: float = 1.0) -> None:
    """Fill a wedge of an arc whose half-width follows ``taper``."""
    steps = 900
    outer: list[tuple[float, float]] = []
    inner: list[tuple[float, float]] = []
    for i in range(steps + 1):
        t = i / steps
        angle = math.radians(start_deg + (end_deg - start_deg) * t)
        # asymmetric bias lets one end stay heavier than the other
        weight = start_weight + (end_weight - start_weight) * t
        half = max_width * taper(t) * weight / 2.0
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        outer.append((cx + cos_a * (radius + half), cy + sin_a * (radius + half)))
        inner.append((cx + cos_a * (radius - half), cy + sin_a * (radius - half)))
    draw.polygon(outer + inner[::-1], fill=WHITE)


def draw_ring(image: Image.Image) -> None:
    draw = ImageDraw.Draw(image)
    cx, cy = S * RING_CX, S * RING_CY
    # 缺口下侧（start）收得更细，上侧（end）略饱满，形成自然的笔锋节奏。
    draw_tapered_arc(draw, cx, cy, S * RING_RADIUS,
                     RING_START, RING_END, S * RING_STROKE,
                     start_weight=0.58, end_weight=1.0)
    # Thin trailing swoosh just outside the ring, tangent to its upper-right end.
    draw_tapered_arc(draw, cx, cy, S * SWOOSH_RADIUS,
                     SWOOSH_START, SWOOSH_END, S * SWOOSH_STROKE,
                     start_weight=0.45, end_weight=1.0)


def draw_triangle(image: Image.Image) -> None:
    cx, cy = S * TRI_CX, S * TRI_CY
    half_w, half_h = S * TRI_HALF_W, S * TRI_HALF_H
    points = [
        (int(cx - half_w), int(cy - half_h)),
        (int(cx - half_w), int(cy + half_h)),
        (int(cx + half_w * 1.12), int(cy)),
    ]
    # Blur-then-threshold is an SDF approximation: it rounds every corner
    # evenly and never bulges outside the silhouette.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(int(S * 0.014)))
    mask = mask.point(lambda value: 255 if value > 128 else 0)
    image.paste(Image.new("RGB", (S, S), WHITE), (0, 0), mask)


def draw_wordmark(image: Image.Image) -> None:
    font = load_font(int(S * 0.21))
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
