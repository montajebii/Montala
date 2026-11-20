#!/usr/bin/env python3
"""Compose the مایکت store screenshots from the raw golden renders.

Input : store/screenshots/raw/*.png   (3240×5760 golden captures)
Output: store/screenshots/NN-*.png    (1080×1920, caption bar + logo)

The caption bar is identical on every image: brand teal #0F766E, white
Vazirmatn Bold RTL caption, gold #C08A2E accent strip, and a small, faint
montala logo in the bottom-left corner. App content is scaled uniformly
onto the app's own warm background above the bar — nothing is cropped.

Usage:
    STORE_SHOTS=1 flutter test test/store_screenshots --update-goldens
    python3 tools/make_store_screenshots.py
"""

import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "store", "screenshots", "raw")
OUT_DIR = os.path.join(ROOT, "store", "screenshots")
LOGO_SVG = os.path.join(ROOT, "assets", "branding", "montala-logo.svg")
FONT_PATH = os.path.join(ROOT, "assets", "fonts", "Vazirmatn-Bold.ttf")

TEAL = (15, 118, 110)        # MontalaColors.brand
GOLD = (192, 138, 46)        # MontalaColors.gold
WHITE = (255, 255, 255)
APP_BG = (252, 250, 247)     # MontalaColors.surfaceWarm — light cream

W, H = 1080, 1920
BAR_H = 192                  # caption bar height
CONTENT_H = H - BAR_H        # app-content area height (1728)

# Ordered captions — checked against the real UI of each screen.
CAPTIONS = [
    ("01-launcher", "همه ابزارها در یک نگاه"),
    ("02-profit-loss", "اگه قبلاً سرمایه\u200cگذاری کرده بودی، امروز چقدر می‌شد؟"),
    ("03-results", "مقایسه\u200cی همزمان دلار، طلا و سکه"),
    ("04-live-board", "قیمت لحظه\u200cای بازار، یک‌جا و به‌روز"),
    ("05-valuation", "ارزش دارایی\u200cهات رو توی هر تاریخ بدون"),
    ("06-transactions", "معاملاتت رو ثبت کن، سود و زیانت رو ببین"),
    ("07-history-analysis", "روند ارزش دارایی\u200cهات رو رصد کن"),
    ("08-jalali-calendar", "کاملاً فارسی، با تقویم خورشیدی"),
]

MAX_FILE_BYTES = 1_000_000
LOGO_PX = 128
MARGIN = 44


def render_logo_png() -> Image.Image:
    """Rasterize the SVG logo with rsvg-convert (cached per run)."""
    out = "/tmp/montala-logo-store.png"
    subprocess.run(
        ["rsvg-convert", "-w", "512", "-h", "512", LOGO_SVG, "-o", out],
        check=True,
    )
    img = Image.open(out).convert("RGBA")
    return img


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, img.size[0] - 1, img.size[1] - 1), radius=radius, fill=255
    )
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def fit_caption(draw: ImageDraw.ImageDraw, text: str, max_w: int):
    """Pick the largest font size that keeps the caption on one line."""
    for size in range(46, 29, -1):
        font = ImageFont.truetype(FONT_PATH, size)
        left, _, right, _ = draw.textbbox((0, 0), text, font=font,
                                          direction="rtl", language="fa")
        if right - left <= max_w:
            return font, right - left
    return ImageFont.truetype(FONT_PATH, 30), None


def compose(raw_path: str, caption: str, out_path: str, logo: Image.Image):
    raw = Image.open(raw_path).convert("RGB")

    # App content: uniform scale into the 1080×1728 area, centered on the
    # app's own warm background so the sides blend seamlessly.
    scale = CONTENT_H / raw.height
    content = raw.resize((round(raw.width * scale), CONTENT_H),
                         Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (W, CONTENT_H), APP_BG)
    canvas.paste(content, ((W - content.width) // 2, 0))

    # Caption bar.
    bar = Image.new("RGB", (W, BAR_H), TEAL)
    draw = ImageDraw.Draw(bar)
    # Gold accent strip along the top edge of the bar.
    draw.rectangle((0, 0, W, 6), fill=GOLD)

    # Logo, bottom-left corner of the image — full opacity, original
    # colours (#0F766E square + #C08A2E marks), transparent outside the
    # square. No shadow, no tint: the teal square matches the bar exactly
    # and only the gold marks read, so there is no halo.
    logo_img = logo.resize((LOGO_PX, LOGO_PX), Image.Resampling.LANCZOS)
    logo_img = rounded(logo_img, 24)
    logo_x, logo_y = MARGIN, (BAR_H - LOGO_PX) // 2 + 3
    bar.paste(logo_img, (logo_x, logo_y), logo_img)

    # Caption, white, RTL, right-aligned.
    text_right = W - MARGIN
    text_left_min = logo_x + LOGO_PX + 28
    max_w = text_right - text_left_min
    font, _ = fit_caption(draw, caption, max_w)
    bbox = draw.textbbox((0, 0), caption, font=font, direction="rtl",
                         language="fa")
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = text_right - tw
    y = (BAR_H - th) // 2 - bbox[1] + 3
    draw.text((x, y), caption, font=font, fill=WHITE, direction="rtl",
              language="fa")

    final = Image.new("RGB", (W, H))
    final.paste(canvas, (0, 0))
    final.paste(bar, (0, CONTENT_H))

    final.save(out_path, optimize=True)
    size = os.path.getsize(out_path)
    if size > MAX_FILE_BYTES:
        # Quantize to PNG-8 to stay under the store's per-file limit.
        quantized = final.quantize(colors=256, method=Image.MedianCut,
                                   dither=Image.FloydSteinberg)
        quantized.save(out_path, optimize=True)
        size = os.path.getsize(out_path)
    return size


def main() -> int:
    logo = render_logo_png()
    total = 0
    print(f"{'file':28} {'size':>9}  caption")
    for name, caption in CAPTIONS:
        raw_path = os.path.join(RAW_DIR, f"{name}.png")
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        if not os.path.exists(raw_path):
            print(f"missing raw: {raw_path}", file=sys.stderr)
            return 1
        size = compose(raw_path, caption, out_path, logo)
        total += size
        flag = "" if size <= MAX_FILE_BYTES else "  !! over 1MB"
        print(f"{name + '.png':28} {size / 1024:8.0f}KB  {caption}")
    print(f"\ntotal: {total / 1024:.0f}KB across {len(CAPTIONS)} images")
    return 0


if __name__ == "__main__":
    sys.exit(main())
