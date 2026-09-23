#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图标链路体检：确认 APK 内的图标 == res 现状，并检查自适应图标各层是否齐全。

用法：python3 tool/check_icon_sync.py
"""
import hashlib
import os
import struct
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.dirname(HERE)
RES = os.path.join(WS, 'android/app/src/main/res')
APK = os.path.join(WS, 'build/app/outputs/flutter-apk/app-release.apk')
DL_APK = '/sdcard/Download/樱读-v1.3.2.apk'

DENSITIES = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']
LAYERS = ['ic_launcher', 'ic_launcher_foreground', 'ic_launcher_background',
          'ic_launcher_monochrome']


def md5(data):
    return hashlib.md5(data).hexdigest()[:12]


def png_size(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    w, h = struct.unpack('>II', data[16:24])
    return w, h


def apk_entry(apk, name):
    with zipfile.ZipFile(apk) as z:
        for n in z.namelist():
            if n.endswith(name):
                return n, z.read(n)
    return None, None


def main():
    print('=== APK 是否存在 ===')
    for p in (APK, DL_APK):
        print('  %-58s %s' % (p, os.path.exists(p)))

    for apk in (APK, DL_APK):
        if not os.path.exists(apk):
            continue
        print('\n=== %s 内图标（与 res 对比）===' % os.path.basename(apk))
        with zipfile.ZipFile(apk) as z:
            names = [n for n in z.namelist() if 'ic_launcher' in n and n.endswith('.png')]
        print('  APK 内图标条目数：%d' % len(names))
        for n in sorted(names):
            entry, data = apk_entry(apk, n)
            size = png_size(data)
            # 找对应 res 文件
            for d in DENSITIES:
                base = os.path.join(RES, 'mipmap-%s' % d, os.path.basename(n))
                if os.path.exists(base):
                    with open(base, 'rb') as f:
                        resdata = f.read()
                    same = 'SAME ' if md5(resdata) == md5(data) else 'DIFF!'
                    print('  %-46s %sx%-4s %s apk=%s res=%s' % (
                        n, size[0] if size else '?', size[1] if size else '?',
                        same, md5(data), md5(resdata)))
                    break

    print('\n=== res 各层齐全性（含 monochrome）===')
    for d in DENSITIES:
        row = []
        for layer in LAYERS:
            p = os.path.join(RES, 'mipmap-%s' % d, '%s.png' % layer)
            if not os.path.exists(p):
                row.append('%s=MISSING' % layer)
                continue
            with open(p, 'rb') as f:
                data = f.read()
            size = png_size(data)
            row.append('%s=%sx%s' % (layer.replace('ic_launcher_', ''),
                                     size[0] if size else '?',
                                     size[1] if size else '?'))
        print('  mipmap-%-8s %s' % (d, '  '.join(row)))

    print('\n=== monochrome 是否仍是 Flutter 默认占位图 ===')
    for d in DENSITIES:
        p = os.path.join(RES, 'mipmap-%s' % d, 'ic_launcher_monochrome.png')
        if not os.path.exists(p):
            print('  %-10s MISSING' % d)
            continue
        with open(p, 'rb') as f:
            data = f.read()
        print('  %-10s %6d bytes  %s' % (d, len(data), md5(data)))

    print('\n=== 与主图标内容比对（monochrome 应同款剪影）===')
    for d in DENSITIES:
        a = os.path.join(RES, 'mipmap-%s' % d, 'ic_launcher.png')
        b = os.path.join(RES, 'mipmap-%s' % d, 'ic_launcher_monochrome.png')
        if os.path.exists(a) and os.path.exists(b):
            with open(a, 'rb') as f:
                da = f.read()
            with open(b, 'rb') as f:
                db = f.read()
            print('  %-10s main=%7d mono=%7d  %s' % (
                d, len(da), len(db),
                '相同' if da == db else '不同（需检查是否为占位图）'))

    print('\nDONE')


if __name__ == '__main__':
    main()