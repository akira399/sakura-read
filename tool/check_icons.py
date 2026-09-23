#!/usr/bin/env python3
"""图标链路验证：APK 内图标 vs res 现状 vs 512 源图（纯标准库，无第三方依赖）。

手动解 PNG（zlib + 反滤波），逐像素比较，用于排查图标管线是否已同步。
用法：python3 tool/check_icons.py
"""
import os
import struct
import zlib
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.dirname(HERE)
DL = '/sdcard/Download'


def decode_png(data):
    """返回 (w, h, pixels: list[tuple(r,g,b,a)])，仅支持 8-bit RGBA/RGB。"""
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8
    width = height = None
    bitdepth = colortype = None
    idat = b''
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b'IHDR':
            width, height, bitdepth, colortype = struct.unpack('>IIBB', chunk[:10])
        elif tag == b'IDAT':
            idat += chunk
        elif tag == b'IEND':
            break
    assert bitdepth == 8, f'bitdepth {bitdepth}'
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colortype]
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
        if ftype == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
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
    # -> RGBA tuples
    px = []
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


def load_file(path):
    with open(path, 'rb') as f:
        return decode_png(f.read())


def load_apk(apk, entry):
    with zipfile.ZipFile(apk) as z:
        return decode_png(z.read(entry))


def stats(a, b):
    """返回 (完全不同?, 平均差异, 最大差异)。尺寸不同时取左上重叠区。"""
    wa, ha, pa = a
    wb, hb, pb = b
    w, h = min(wa, wb), min(ha, hb)
    total = 0
    maxd = 0
    for y in range(h):
        for x in range(w):
            ia = (y * wa + x)
            ib = (y * wb + x)
            d = 0
            ca, cb = pa[ia], pb[ib]
            for k in range(3):
                dd = abs(ca[k] - cb[k])
                if dd > d:
                    d = dd
            total += d
            if d > maxd:
                maxd = d
    avg = total / (w * h)
    return avg < 0.5, avg, maxd


print('=== 载入 ===')
v125 = load_apk(f'{DL}/樱读-v1.2.5.apk', 'res/mipmap-xxxhdpi/ic_launcher.png')
v124 = load_apk(f'{DL}/樱读-v1.2.4.apk', 'res/mipmap-xxxhdpi/ic_launcher.png')
res = load_file(f'{WS}/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')
sq = load_file(f'{WS}/tool/artwork/icon_square_512.png')
rnd = load_file(f'{WS}/tool/artwork/icon_round_512.png')
rndd = load_file(f'{WS}/tool/artwork/icon_rounded_512.png')
print(f'v125 {v125[0]}x{v125[1]} | v124 {v124[0]}x{v124[1]} | res {res[0]}x{res[1]}')
print(f'square {sq[0]}x{sq[1]} | round {rnd[0]}x{rnd[1]} | rounded {rndd[0]}x{rndd[1]}')

print()
print('=== APK vs res 现状 ===')
s, a, m = stats(v125, res)
print(f'v1.2.5 APK vs res: 相同={s} avg={a:.3f} max={m}')
s, a, m = stats(v124, res)
print(f'v1.2.4 APK vs res: 相同={s} avg={a:.3f} max={m}')
s, a, m = stats(v125, v124)
print(f'v1.2.5 vs v1.2.4:  相同={s} avg={a:.3f} max={m}')

print()
print('=== 源图（512→192 下采样近似）vs res ===')


def center_crop_scale(img, size):
    """从 512 缩到 192：直接按比例取整（近似最近邻）。"""
    w, h, px = img
    scale = w / size
    ox = (w - size * scale) / 2
    oy = (h - size * scale) / 2
    out = []
    for y in range(size):
        sy = int(oy + y * scale)
        for x in range(size):
            sx = int(ox + x * scale)
            out.append(px[sy * w + sx])
    return (size, size, out)


for name, img in [
    ('square', sq),
    ('round', rnd),
    ('rounded', rndd),
]:
    small = center_crop_scale(img, 192)
    s, a, m = stats(small, res)
    print(f'{name}: 相同={s} avg={a:.3f} max={m}')