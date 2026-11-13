#!/usr/bin/env python3
"""Generate the 1024x1024 app icon with the standard library only (no Pillow needed).

The icon is a red gradient with a white ring and pixel-rendered "SWF" lettering.
Output is 8-bit RGB with NO alpha channel (Xcode/actool rejects RGBA app icons).
It is intentionally original artwork - nothing is copied from the discontinued app.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIZE = 1024
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SWFPlayer" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"

GLYPHS = {
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
}


def chunk(tag: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


def build() -> bytes:
    pixels = bytearray(SIZE * SIZE * 3)

    # 1. diagonal red gradient
    for y in range(SIZE):
        for x in range(SIZE):
            t = max(0.0, min(1.0, (x + y) / (2.0 * (SIZE - 1))))
            i = (y * SIZE + x) * 3
            pixels[i] = int(0xF5 + (0xFF - 0xF5) * t)
            pixels[i + 1] = int(0x33 + (0x6B - 0x33) * t)
            pixels[i + 2] = int(0x3F + (0x5C - 0x3F) * t)

    def paint(x: int, y: int, alpha: float = 1.0) -> None:
        if 0 <= x < SIZE and 0 <= y < SIZE and alpha > 0:
            i = (y * SIZE + x) * 3
            pixels[i] = int(255 * alpha + pixels[i] * (1 - alpha))
            pixels[i + 1] = int(255 * alpha + pixels[i + 1] * (1 - alpha))
            pixels[i + 2] = int(255 * alpha + pixels[i + 2] * (1 - alpha))

    # 2. thin white ring
    cx = cy = SIZE / 2.0
    outer, inner = 428.0, 410.0
    for y in range(int(cy - outer - 2), int(cy + outer + 3)):
        for x in range(int(cx - outer - 2), int(cx + outer + 3)):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if inner * inner <= d2 <= outer * outer:
                paint(x, y, 0.9)

    # 3. "SWF" lettering
    word = "SWF"
    cell = 46
    gap = 12
    glyph_w = 5 * cell
    total_w = 3 * glyph_w + 2 * gap
    total_h = 7 * cell
    start_x = int((SIZE - total_w) / 2)
    start_y = int((SIZE - total_h) / 2)
    for index, letter in enumerate(word):
        glyph = GLYPHS[letter]
        base_x = start_x + index * (glyph_w + gap)
        for gy, line in enumerate(glyph):
            for gx, bit in enumerate(line):
                if bit != "1":
                    continue
                for dy in range(cell):
                    for dx in range(cell):
                        paint(base_x + gx * cell + dx, start_y + gy * cell + dy)

    # 4. encode as 8-bit RGB PNG (color type 2, no alpha)
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        raw.extend(pixels[y * SIZE * 3:(y + 1) * SIZE * 3])

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(build())
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
