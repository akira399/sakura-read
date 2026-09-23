#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成樱读 App 图标（樱花 logo + 粉紫渐变底）。

产物：
  legacy 圆角图标   -> mipmap-*/ic_launcher.png            (48/72/96/144/192)
  自适应前景层      -> mipmap-*/ic_launcher_foreground.png  (108/162/216/324/432, 透明底)
  自适应背景层      -> mipmap-*/ic_launcher_background.png  (108..432, 全幅渐变)
  单色主题层        -> mipmap-*/ic_launcher_monochrome.png  (108..432, 白色剪影)
  自适应图标 XML    -> mipmap-anydpi-v26/ic_launcher.xml
  启动页 logo       -> drawable-nodpi/splash_logo.png       (480, 不随密度缩放)

用法:
  python3 tool/make_icon.py            # 生成全部 PNG + XML
  python3 tool/make_icon.py --preview  # 终端 ASCII 预览（不写文件）
"""
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(
    os.path.join(HERE, '..', 'android', 'app', 'src', 'main', 'res')
)

LEGACY_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}
ADAPTIVE_SIZES = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
}

PINK = (255, 158, 199)
LAVENDER = (157, 140, 255)
PETAL = (255, 255, 255)
CENTER = (255, 224, 130)
CORNER = 0.70          # 圆角起始（归一化 -1..1 空间）
PETAL_CY = -0.52       # 花瓣椭圆中心距
PETAL_RX = 0.36
PETAL_RY = 0.52
CENTER_R = 0.16
FLOWER_LEGACY = 0.85   # legacy 图标里花的缩放（花尖 ≈0.88，不裁切）
FLOWER_FG = 0.575      # 自适应前景里花的缩放（花尖 ≈0.60，处于安全区内）
MASK_R = 0.667         # 自适应可见半径（仅预览用）
SS = 3                 # 超采样倍数


def in_rounded(nx, ny):
    ax, ay = abs(nx), abs(ny)
    if ax <= CORNER and ay <= CORNER:
        return True
    dx = max(0.0, ax - CORNER)
    dy = max(0.0, ay - CORNER)
    return dx * dx + dy * dy <= (1 - CORNER) ** 2


def petal_hit(x, y):
    """未缩放坐标上判断是否命中花瓣。"""
    for i in range(5):
        ang = i * math.pi * 2 / 5
        cos_a, sin_a = math.cos(ang), math.sin(ang)
        px = x * cos_a + y * sin_a
        py = -x * sin_a + y * cos_a
        vx = px / PETAL_RX
        vy = (py - PETAL_CY) / PETAL_RY
        if vx * vx + vy * vy <= 1.0:
            return True
    return False


def flower_parts(nx, ny, scale):
    """0=无, 1=花瓣, 2=花心。"""
    x, y = nx / scale, ny / scale
    if x * x + y * y <= CENTER_R * CENTER_R:
        return 2
    if petal_hit(x, y):
        return 1
    return 0


def bg_color(nx, ny):
    t = (nx + ny + 2) / 4
    return (
        int(PINK[0] * (1 - t) + LAVENDER[0] * t),
        int(PINK[1] * (1 - t) + LAVENDER[1] * t),
        int(PINK[2] * (1 - t) + LAVENDER[2] * t),
    )


def sample_legacy(nx, ny):
    if not in_rounded(nx, ny):
        return (0, 0, 0, 0)
    p = flower_parts(nx, ny, FLOWER_LEGACY)
    if p == 2:
        return (CENTER[0], CENTER[1], CENTER[2], 255)
    if p == 1:
        return (PETAL[0], PETAL[1], PETAL[2], 255)
    r, g, b = bg_color(nx, ny)
    return (r, g, b, 255)


def sample_fg(nx, ny):
    p = flower_parts(nx, ny, FLOWER_FG)
    if p == 2:
        return (CENTER[0], CENTER[1], CENTER[2], 255)
    if p == 1:
        return (PETAL[0], PETAL[1], PETAL[2], 255)
    return (0, 0, 0, 0)


def sample_bg(nx, ny):
    r, g, b = bg_color(nx, ny)
    return (r, g, b, 255)


def sample_mono(nx, ny):
    if flower_parts(nx, ny, FLOWER_FG) > 0:
        return (255, 255, 255, 255)
    return (0, 0, 0, 0)


def render(size, sampler):
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # PNG filter: none
        for x in range(size):
            acc = [0, 0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    nx = (x + (sx + 0.5) / SS) / size * 2 - 1
                    ny = (y + (sy + 0.5) / SS) / size * 2 - 1
                    p = sampler(nx, ny)
                    for k in range(4):
                        acc[k] += p[k]
            n = SS * SS
            raw += bytes((acc[0] // n, acc[1] // n, acc[2] // n, acc[3] // n))
    return bytes(raw)


def png(size, rgba):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        c += struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    return (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', ihdr)
        + chunk(b'IDAT', zlib.compress(rgba, 9))
        + chunk(b'IEND', b'')
    )


def write_png(path, size, sampler):
    data = png(size, render(size, sampler))
    with open(path, 'wb') as f:
        f.write(data)
    print('icon ->', path, f'({size}x{size}, {len(data)}B)')


ADAPTIVE_XML = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
    '</adaptive-icon>\n'
)


def preview():
    n = 46

    def legacy_char(fx, fy):
        if not in_rounded(fx, fy):
            return ' '
        return ('.', '#', '@')[flower_parts(fx, fy, FLOWER_LEGACY)]

    def adaptive_char(fx, fy):
        if fx * fx + fy * fy > MASK_R * MASK_R:
            return ' '
        return ('.', '#', '@')[flower_parts(fx, fy, FLOWER_FG)]

    for title, fn in (
        ('legacy（圆角方形，桌面图标实际形态）', legacy_char),
        ('adaptive（圆形遮罩裁剪后的可见形态）', adaptive_char),
    ):
        print('== %s ==' % title)
        for y in range(0, n, 2):
            row = []
            for x in range(n):
                nx = (x + 0.5) / n * 2 - 1
                ny = (y + 0.5) / n * 2 - 1
                row.append(fn(nx, ny))
            print(''.join(row))
        print()


def main():
    if '--preview' in sys.argv:
        preview()
        return
    for folder, size in LEGACY_SIZES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        write_png(os.path.join(d, 'ic_launcher.png'), size, sample_legacy)
    for folder, size in ADAPTIVE_SIZES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        write_png(os.path.join(d, 'ic_launcher_foreground.png'), size, sample_fg)
        write_png(os.path.join(d, 'ic_launcher_background.png'), size, sample_bg)
        write_png(os.path.join(d, 'ic_launcher_monochrome.png'), size, sample_mono)
    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    xml_path = os.path.join(anydpi, 'ic_launcher.xml')
    with open(xml_path, 'w', encoding='utf-8') as f:
        f.write(ADAPTIVE_XML)
    print('xml  ->', xml_path)
    splash_dir = os.path.join(RES, 'drawable-nodpi')
    os.makedirs(splash_dir, exist_ok=True)
    write_png(os.path.join(splash_dir, 'splash_logo.png'), 480, sample_legacy)
    print('done.')


if __name__ == '__main__':
    main()