#!/usr/bin/env python3
"""Regenerate every raster app icon from assets/branding/montala-logo.svg.

Usage:
    python3 tools/generate_icons.py

The SVG is the single source of truth. Edit/replace it, rerun this script, and
commit the regenerated PNG/ICO files.

Requires `rsvg-convert` (Debian/Ubuntu: librsvg2-bin) and Pillow.
"""

from __future__ import annotations

import struct
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets/branding/montala-logo.svg"
BRAND = (0x0F, 0x76, 0x6E)  # MontalaColors.brand

ANDROID_RES = ROOT / "android/app/src/main/res"
WEB = ROOT / "web"
WINDOWS_ICO = ROOT / "windows/runner/resources/app_icon.ico"

# Legacy launcher icons (one PNG per density).
ANDROID_MIPMAPS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Adaptive icons: a 108dp foreground layer, of which Android shows the middle
# 72dp and guarantees only the middle 66dp circle. The artboard is scaled down
# so the mark's outermost corners stay inside that safe circle.
ANDROID_FOREGROUNDS = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
FOREGROUND_RATIO = 0.555

# PWA maskable icons must keep their content inside the middle 80% circle.
MASKABLE_RATIO = 0.72

WINDOWS_ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)


def render(size: int, tmp: Path) -> Image.Image:
    """Rasterise the logo into a size x size PNG and load it."""
    png = tmp / f"logo-{size}.png"
    if not png.exists():
        subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(LOGO)],
            check=True,
        )
    return Image.open(png).convert("RGBA")


def icon(size: int, ratio: float, tmp: Path, opaque: bool) -> Image.Image:
    """Render the logo at `ratio` of the canvas, centred, with brand padding."""
    art_size = max(1, round(size * ratio))
    art = render(art_size, tmp)
    if opaque:
        canvas = Image.new("RGBA", (size, size), BRAND + (255,))
    else:
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - art_size) // 2
    canvas.alpha_composite(art, (offset, offset))
    return canvas


def write_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Fully opaque icons are stored as RGB (smaller); the adaptive foreground
    # keeps its alpha channel.
    if image.mode == "RGBA" and image.getextrema()[3] == (255, 255):
        image = image.convert("RGB")
    image.save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT)}  {image.width}x{image.height}")


def write_ico(images: list[Image.Image], path: Path) -> None:
    """Write a multi-resolution ICO with PNG-compressed frames."""
    blobs = []
    for image in images:
        buf = tempfile.SpooledTemporaryFile()
        image.convert("RGBA").save(buf, "PNG", optimize=True)
        buf.seek(0)
        blobs.append(buf.read())

    header = struct.pack("<HHH", 0, 1, len(images))
    offset = len(header) + 16 * len(images)
    entries, payload = b"", b""
    for image, blob in zip(images, blobs):
        dim = 0 if image.width >= 256 else image.width
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset)
        payload += blob
        offset += len(blob)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + entries + payload)
    sizes = ", ".join(str(image.width) for image in images)
    print(f"  {path.relative_to(ROOT)}  [{sizes}]")


def main() -> None:
    if not LOGO.exists():
        raise SystemExit(f"missing source logo: {LOGO}")

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)

        print("android legacy icons")
        for density, size in ANDROID_MIPMAPS.items():
            write_png(icon(size, 1.0, tmp, opaque=True),
                      ANDROID_RES / f"mipmap-{density}/ic_launcher.png")

        print("android adaptive foregrounds")
        for density, size in ANDROID_FOREGROUNDS.items():
            write_png(icon(size, FOREGROUND_RATIO, tmp, opaque=False),
                      ANDROID_RES / f"mipmap-{density}/ic_launcher_foreground.png")

        print("web icons")
        write_png(icon(32, 1.0, tmp, opaque=True), WEB / "favicon.png")
        for size in (192, 512):
            write_png(icon(size, 1.0, tmp, opaque=True), WEB / f"icons/Icon-{size}.png")
            write_png(icon(size, MASKABLE_RATIO, tmp, opaque=True),
                      WEB / f"icons/Icon-maskable-{size}.png")

        print("windows icon")
        write_ico([icon(size, 1.0, tmp, opaque=True) for size in WINDOWS_ICO_SIZES],
                  WINDOWS_ICO)


if __name__ == "__main__":
    main()
