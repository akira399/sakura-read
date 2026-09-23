#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图标像素级比对：判断「APK 内图标」是否真的和仓库 res 一致，
以及 monochrome 层到底是自绘剪影还是模板占位图。

用法：python3 tool/icon_pixel_diff.py
"""
import os
import struct
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.dirname(HERE)
RES = os.path.join(WS, 'android/app/src/main/res')
APK = '/sdcard/Download/樱读-v1.3.3.apk'


def decode_png(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8
    width = height = bitdepth = colortype = None
    idat = b''
    palette = None
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b'IHDR':
            width, height, bitdepth, colortype = struct.unpack('>IIBB', chunk[:10])
        elif tag == b'IDAT':
            idat += chunk
        elif tag == b'PLTE':
            palette = chunk
        elif tag == b'IEND':
            break
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    ppos = 0
    for y in range(height):
        ftype = raw[ppos]
        ppos += 1
        line = bytearray(raw[ppos:ppos + stride])
        ppos += stride
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line

    px = []
    if colortype == 3:
        for i in range(len(out)):
            idx = out[i] * 3
            px.append((palette[idx], palette[idx + 1], palette[idx + 2], 255))
    else:
        for i in range(0, len(out), channels):
            if channels == 4:
                px.append(tuple(out[i:i + 4]))
            elif channels == 3:
                px.append((out[i], out[i + 1], out[i + 2], 255))
            elif channels == 2:
                g = out[i]
                px.append((g, g, g, out[i + 1]))
            else:
                g = out[i]
                px.append((g, g, g, 255))
    return width, height, px


def load(path):
    with open(path, 'rb') as f:
        return decode_png(f.read())


def load_apk(apk, suffix):
    with zipfile.ZipFile(apk) as z:
        for n in z.namelist():
            if n.endswith(suffix):
                return decode_png(z.read(n))
    return None


def diff(a, b):
    wa, ha, pa = a
    wb, hb, pb = b
    if (wa, ha) != (wb, hb):
        return None, None, '尺寸不同 %sx%s vs %sx%s' % (wa, ha, wb, hb)
    maxd = 0
    total = 0
    for i in range(len(pa)):
        d = 0
        for k in range(4):
            dd = abs(pa[i][k] - pb[i][k])
            if dd > d:
                d = dd
        total += d
        if d > maxd:
            maxd = d
    return total / len(pa), maxd, 'avg=%.3f max=%d' % (total / len(pa), maxd)


print('=== APK 内主图标 vs 仓库 res：像素级比对 ===')
for suf, density in [('mipmap-xxxhdpi/ic_launcher.png', 'xxxhdpi'),
                     ('mipmap-mdpi/ic_launcher.png', 'mdpi')]:
    a = load_apk(APK, suf)
    b = load(os.path.join(RES, suf))
    avg, mx, msg = diff(a, b)
    verdict = '✅ 完全一致（安装包图标=仓库图标）' if (mx == 0) else (
        '⚠️ 略有差异' if (avg is not None and avg < 2) else '❌ 明显不同')
    print('  %-9s %s' % (density, msg))
    print('             %s' % verdict)

print('\n=== monochrome 层内容分析（xxxhdpi）===')
mono = load(os.path.join(RES, 'mipmap-xxxhdpi/ic_launcher_monochrome.png'))
w, h, px = mono
print('  尺寸 %dx%d' % (w, h))
opaque = sum(1 for p in px if p[3] > 16)
print('  非透明像素占比：%.1f%%' % (opaque * 100.0 / len(px)))
colors = {}
for p in px:
    if p[3] > 16:
        colors[p[:3]] = colors.get(p[:3], 0) + 1
top = sorted(colors.items(), key=lambda kv: -kv[1])[:6]
print('  主色（前 6）：%s' % ', '.join('#%02X%02X%02X×%d' % (c[0], c[1], c[2], n)
                                       for c, n in top))
print('  是否为纯单色剪影：%s' % ('是' if len(colors) <= 3 else '否（%d 种颜色）' % len(colors)))

# 与主图标做形状相关性检查：主图 alpha>0 的区域，mono 是否也为不透明
main = load(os.path.join(RES, 'mipmap-xxxhdpi/ic_launcher.png'))
mw, mh, mpx = main
if (mw, mh) == (w, h):
    both = 0
    only_main = 0
    for i in range(len(px)):
        mo = mpx[i][3] > 16
        no = px[i][3] > 16
        if mo and no:
            both += 1
        elif mo and not no:
            only_main += 1
    tot_main = both + only_main
    print('  与主图标透明区域重合度：%s' % (
        '高（%.1f%% 主图不透明处 mono 也不透明）' % (both * 100.0 / tot_main)
        if tot_main else 'n/a'))

# Flutter 模板默认 monochrome 的特征：常见为一个小的居中方形/圆形块
print('\n=== 判断 ===')
print('  monochrome mtime = 2026-09-19 20:30（项目初始化时）')
print('  主图标 mtime     = 2026-09-20 23:55（自绘 Q 版看板娘生成时）')
print('  → 若上面显示 mono 与主图形状不一致，则 Android 13+ 主题图标仍是占位图')
print('\nDONE')