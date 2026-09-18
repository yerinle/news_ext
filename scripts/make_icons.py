#!/usr/bin/env python3
"""Generate the extension/app icon set: a newspaper mark on a News-red tile."""
from PIL import Image, ImageDraw
import os

BG_TOP = (214, 56, 48)
BG_BOTTOM = (176, 32, 42)
OUT = os.path.join(os.path.dirname(__file__), '..', 'extension', 'icons')
os.makedirs(OUT, exist_ok=True)


def make(size):
    s = size * 4  # supersample, then downscale for clean edges
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # vertical gradient tile
    grad = Image.new('RGBA', (1, s))
    gd = ImageDraw.Draw(grad)
    for y in range(s):
        t = y / max(s - 1, 1)
        gd.point((0, y), fill=(
            int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t),
            int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t),
            int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t), 255))
    grad = grad.resize((s, s))

    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.225), fill=255)
    img.paste(grad, (0, 0), mask)

    # newspaper: a page with text lines and a headline block
    m = s * 0.24
    page = [m, m * 1.05, s - m, s - m * 1.05]
    d.rounded_rectangle(page, radius=int(s * 0.035), fill=(255, 255, 255, 255))

    px0, py0, px1, py1 = page
    pw = px1 - px0
    pad = pw * 0.13
    x0, x1 = px0 + pad, px1 - pad
    y = py0 + pad * 1.15

    # headline block
    d.rounded_rectangle([x0, y, x0 + (x1 - x0) * 0.62, y + pw * 0.14],
                        radius=int(s * 0.012), fill=BG_BOTTOM + (255,))
    y += pw * 0.14 + pad * 0.72

    # body lines
    for i, frac in enumerate((1.0, 1.0, 0.84, 1.0, 0.55)):
        h = pw * 0.052
        if y + h > py1 - pad * 0.8:
            break
        d.rounded_rectangle([x0, y, x0 + (x1 - x0) * frac, y + h],
                            radius=int(s * 0.008), fill=(120, 124, 132, 255))
        y += h + pad * 0.44

    return img.resize((size, size), Image.LANCZOS)


for size in (16, 32, 48, 96, 128, 256, 512, 1024):
    make(size).save(os.path.join(OUT, f'icon-{size}.png'))
print('wrote icons:', ', '.join(f'icon-{s}.png' for s in (16, 32, 48, 96, 128, 256, 512, 1024)))
