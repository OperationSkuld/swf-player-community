#!/usr/bin/env python3
"""Fetch the official App Store artwork and use it as the app icon.

The community build deliberately reuses the *original* SWF Player icon that
Apple serves on the App Store product page (the artwork referenced by the
original app's Info.plist bundle icon). We download the 1024px master directly
from Apple's CDN and write it as an 8-bit RGB PNG.

Why RGB (no alpha): Xcode's actool rejects RGBA app icons. The App Store
artwork already has an opaque red background, so colour conversion is lossless
for the visible image.

The generated PNG is committed, so CI does NOT need network access or Pillow to
build the icon - this script exists only to refresh the artwork when needed.

Requires Pillow (``python -m pip install Pillow``) and network access.
"""
from __future__ import annotations

import urllib.request
from pathlib import Path

from PIL import Image

SIZE = 1024
ROOT = Path(__file__).resolve().parent.parent
OUT = (ROOT / "SWFPlayer" / "Resources" / "Assets.xcassets"
       / "AppIcon.appiconset" / "AppIcon-1024.png")

# Apple iTunes Lookup API artworkUrl512 host path for app id 6761699690.
# Requesting 1024x1024bb returns the 1024px master (JPEG). See README comments.
ARTWORK_URL = (
    "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/"
    "ab/cf/1a/abcf1a93-5f51-c255-a48b-02bee604df54/"
    "AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/1024x1024bb.jpg"
)


def fetch() -> Image.Image:
    """Download the official artwork and return it as an RGB image."""
    request = urllib.request.Request(ARTWORK_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    import io
    image = Image.open(io.BytesIO(raw))
    if image.size != (SIZE, SIZE):
        image = image.resize((SIZE, SIZE), Image.LANCZOS)
    return image.convert("RGB")


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon = fetch()
    icon.save(OUT, format="PNG", optimize=True)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, mode={icon.mode})")


if __name__ == "__main__":
    main()
