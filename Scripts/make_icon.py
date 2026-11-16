#!/usr/bin/env python3
"""Generate the 1024x1024 app icon.

Reproduces the classic red Flash-player look of the original store listing:
saturated red gradient, a white broken ring, a rounded play triangle and
diagonal "SWF" lettering in the lower-right corner.

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
    center = S / 2.0
    radius = S * 0.385
    width = int(S * 0.056)
    box = [center - radius, center - radius, center + radius, center + radius]
    # Narrow opening on the right, matching the original's broken ring.
    draw.arc(box, start=20, end=340, fill=WHITE, width=width)


def draw_triangle(image: Image.Image) -> None:
    points = [
        (int(S * 0.398), int(S * 0.381)),
        (int(S * 0.398), int(S * 0.619)),
        (int(S * 0.617), int(S * 0.500)),
    ]
    # Blur-then-threshold is an SDF approximation: it rounds every corner
    # evenly and never bulges outside the silhouette.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(int(S * 0.013)))
    mask = mask.point(lambda value: 255 if value > 128 else 0)
    image.paste(Image.new("RGB", (S, S), WHITE), (0, 0), mask)


def draw_wordmark(image: Image.Image) -> None:
    font = load_font(int(S * 0.250))
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))

    # Tight manual kerning: the original wordmark is nearly touching letters,
    # which keeps the three glyphs inside the small lower-right area.
    tracking = int(S * -0.008)
    letters = []
    for char in "SWF":
        left, top, right, bottom = probe.textbbox((0, 0), char, font=font)
        letters.append((char, left, top, right - left, bottom - top))

    pad = int(S * 0.02)
    total_w = sum(item[3] for item in letters) + tracking * (len(letters) - 1)
    max_h = max(item[4] for item in letters)
    layer = Image.new("RGBA", (total_w + pad * 2, max_h + pad * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    cursor = pad
    for char, left, top, width, _ in letters:
        # A thin red stroke acts as a knockout shadow: where the wordmark crosses
        # the white ring, the letters stay readable instead of fusing into it.
        draw.text((cursor - left, pad - top), char, font=font,
                  fill=(255, 255, 255, 255),
                  stroke_width=int(S * 0.011),
                  stroke_fill=(196, 20, 8, 255))
        cursor += width + tracking

    # Italic slant: top edge shifts right, baseline stays put.
    width, height = layer.size
    shear = 0.26
    layer = layer.transform(
        (width + int(height * shear), height),
        Image.AFFINE,
        (1, -shear, shear * height, 0, 1, 0),
        resample=Image.BICUBIC,
    )
    # Tilt the wordmark so it climbs to the upper right, as in the original.
    layer = layer.rotate(31, expand=True, resample=Image.BICUBIC)

    # Condense horizontally: Arial Black is wide, and a tall narrow wordmark
    # stays legible where it crosses the ring.
    width, height = layer.size
    layer = layer.resize((int(width * 0.80), height), Image.LANCZOS)

    # Anchor to the bottom-right corner but keep every letter inside the canvas.
    width, height = layer.size
    x = S - width - int(S * 0.012)
    y = S - height - int(S * 0.008)
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
