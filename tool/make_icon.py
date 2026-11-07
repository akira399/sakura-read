#!/usr/bin/env python3
"""Generate Android Sakura Read icons from the illustrated book artwork.

Requires Pillow. The adaptive foreground keeps the artwork inside the Android
safe area; the system-themed layer is a simple white mascot and book.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android/app/src/main/res'
ART = ROOT / 'tool/artwork/sakura_pet_reading_icon.png'
SIZES = {'mdpi': (48, 108), 'hdpi': (72, 162), 'xhdpi': (96, 216),
         'xxhdpi': (144, 324), 'xxxhdpi': (192, 432)}


def make_layers():
    artwork = Image.open(ART).convert('RGBA').resize((512, 512), Image.Resampling.LANCZOS)
    # A softly blurred continuation supplies colour outside the icon safe area.
    bg = artwork.filter(ImageFilter.GaussianBlur(100))
    fg = Image.new('RGBA', (512, 512))
    inner = artwork.resize((350, 350), Image.Resampling.LANCZOS)
    mask = Image.new('L', (350, 350))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 349, 349), radius=65, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(14))
    inner.putalpha(mask)
    fg.alpha_composite(inner, (81, 81))
    mono = Image.new('RGBA', (512, 512))
    draw = ImageDraw.Draw(mono)
    # Themed icon: mascot head/hair and a clearly separated open book.
    draw.ellipse((125, 108, 387, 352), fill='white')
    draw.rounded_rectangle((112, 195, 400, 366), radius=70, fill='white')
    draw.polygon([(135, 285), (193, 282), (256, 311), (319, 282), (377, 285),
                  (377, 366), (318, 360), (256, 389), (194, 360), (135, 366)], fill='white')
    draw.line([(256, 311), (256, 389)], fill=(0, 0, 0, 0), width=8)
    return artwork, bg, fg, mono


def main():
    artwork, bg, fg, mono = make_layers()
    for density, (legacy_size, adaptive_size) in SIZES.items():
        folder = RES / ('mipmap-' + density)
        for name, image, size in [('ic_launcher', artwork, legacy_size),
                                  ('ic_launcher_background', bg, adaptive_size),
                                  ('ic_launcher_foreground', fg, adaptive_size),
                                  ('ic_launcher_monochrome', mono, adaptive_size)]:
            image.resize((size, size), Image.Resampling.LANCZOS).save(folder / (name + '.png'))
    artwork.resize((480, 480), Image.Resampling.LANCZOS).save(RES / 'drawable-nodpi/splash_logo.png')


if __name__ == '__main__':
    main()
