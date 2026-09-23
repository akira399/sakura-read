#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成测试素材：中文 TXT（UTF-8 / GBK）与 EPUB（2.0 NCX 版 + 3.0 Nav 版）。

用法: python3 tool/make_fixtures.py
输出: test/fixtures/ 下的 novel_utf8.txt、novel_gbk.txt、novel_epub3.epub、novel_epub2.epub
"""
import os
import struct
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'test', 'fixtures'))
os.makedirs(OUT, exist_ok=True)

SENTENCES = [
    '窗外的樱花又开了，风一吹，花瓣便像融化的雪一样飘落下来。',
    '她轻轻合上那本泛黄的旧书，指尖仍停留在扉页的署名上。',
    '“今天的课就上到这里吧。”老师推了推眼镜，合上了教案。',
    '夕阳把教学楼的影子拉得很长很长，像是要把整个下午都拌进去。',
    '便利店的屋檐下，两人并肩站着，看雨点在地面溅起细小的花。',
    '“其实啊，星星的光要走很久才能到达地球呢。”她忽然说。',
    '少年愣了一下，随即笑起来，那笑容干净得像刚洗过的天空。',
    '书架最上层的位置，放着一本谁都没有借过的蓝色诗集。',
    '电车穿过隧道，灯光明明灭灭，仿佛穿行在时间的褶皱里。',
    '夏夜的蝉鸣渐渐低了下去，只剩下两颗心跳的声音。',
    '“如果时间能停在这一刻就好了。”她小声地、几乎听不见地说。',
    '海风带着咸味吹过堤岸，纸飞机在暮色里划出一道弧线。',
]


def para(seed, n=4):
    """生成一个自然段（确定性）。"""
    return ''.join(SENTENCES[(seed * 5 + k) % len(SENTENCES)] for k in range(n))


def chapter_text(title, n_paras, seed):
    lines = [title]
    for i in range(n_paras):
        lines.append(para(seed + i))
    return '\n'.join(lines)


CHAPTERS = [
    ('序章 樱花树下的约定', 10, 1),
    ('第一章 借书证与旧时光', 14, 50),
    ('第二章 星夜列车', 13, 100),
    ('第三章 雨中的便利店', 12, 150),
    ('第四章 尾声 · 春日来信', 8, 200),
]

TITLE = '星夜下的约定'
AUTHOR = '樱井小夜'
DESC = '一部用于测试的轻小说样例，讲述少女与旧书店之间的奇妙缘分，以及樱花树下的那个约定。'

full_text_parts = []
for title, n, seed in CHAPTERS:
    full_text_parts.append(chapter_text(title, n, seed))
full_text = '\n\n'.join(full_text_parts) + '\n\n（全文完）\n'

# ---------- TXT ----------
utf8_path = os.path.join(OUT, 'novel_utf8.txt')
with open(utf8_path, 'w', encoding='utf-8') as f:
    f.write(full_text)

gbk_path = os.path.join(OUT, 'novel_gbk.txt')
with open(gbk_path, 'wb') as f:
    f.write(full_text.encode('gbk'))
print('TXT 已生成:', utf8_path, gbk_path)


# ---------- PNG 封面 ----------
def make_cover_png(width=480, height=640):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        c += struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    raw = bytearray()
    cx, cy = width * 0.5, height * 0.42
    for y in range(height):
        raw.append(0)  # filter: none
        for x in range(width):
            t = y / height
            r = int(255 - 70 * t)
            g = int(170 + 50 * (1 - t))
            b = int(205 - 30 * t)
            # 画几个花瓣般的浅色圆
            for (px, py, pr) in (
                (cx, cy, width * 0.30),
                (cx - width * 0.22, cy - height * 0.06, width * 0.16),
                (cx + width * 0.22, cy - height * 0.06, width * 0.16),
                (cx, cy + height * 0.12, width * 0.14),
            ):
                if (x - px) ** 2 + (y - py) ** 2 < pr * pr:
                    r = min(255, r + 30)
                    g = min(255, g + 20)
                    b = min(255, b + 20)
            raw += bytes((r, g, b))
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', ihdr)
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    return png


COVER = make_cover_png()


def xhtml(title, body_paras):
    ps = '\n'.join('<p>%s</p>' % p for p in body_paras)
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        '<head><title>%s</title></head>\n'
        '<body>\n<h1>%s</h1>\n%s\n</body>\n</html>\n' % (title, title, ps)
    )


CONTAINER = (
    '<?xml version="1.0"?>\n'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
    '  <rootfiles>\n'
    '    <rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/>\n'
    '  </rootfiles>\n'
    '</container>\n'
)


def write_epub(path, epub3):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        # mimetype 必须是第一个、不压缩
        zi = zipfile.ZipInfo('mimetype')
        zi.compress_type = zipfile.ZIP_STORED
        z.writestr(zi, 'application/epub+zip')
        z.writestr('META-INF/container.xml', CONTAINER)
        z.writestr('OEBPS/cover.png', COVER)
        for idx, (title, n, seed) in enumerate(CHAPTERS, start=1):
            paras = [para(seed + i) for i in range(n)]
            z.writestr('OEBPS/ch%d.xhtml' % idx, xhtml(title, paras))
        if epub3:
            nav_items = '\n'.join(
                '      <li><a href="ch%d.xhtml">%s</a></li>' % (i, c[0])
                for i, c in enumerate(CHAPTERS, start=1)
            )
            nav = (
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<html xmlns="http://www.w3.org/1999/xhtml" '
                'xmlns:epub="http://www.idpf.org/2007/ops">\n'
                '<head><title>目录</title></head>\n'
                '<body><nav epub:type="toc"><h1>目录</h1>\n'
                '  <ol>\n%s\n  </ol>\n</nav></body></html>\n' % nav_items
            )
            z.writestr('OEBPS/nav.xhtml', nav)
            opf = (
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
                'unique-identifier="bookid">\n'
                ' <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
                '  <dc:identifier id="bookid">urn:uuid:demo-0001</dc:identifier>\n'
                '  <dc:title>%s</dc:title>\n'
                '  <dc:creator>%s</dc:creator>\n'
                '  <dc:language>zh-CN</dc:language>\n'
                '  <dc:description>%s</dc:description>\n'
                ' </metadata>\n'
                ' <manifest>\n'
                '  <item id="nav" href="nav.xhtml" '
                'media-type="application/xhtml+xml" properties="nav"/>\n'
                '  <item id="cover" href="cover.png" media-type="image/png" '
                'properties="cover-image"/>\n'
                '%s'
                ' </manifest>\n'
                ' <spine>\n%s\n </spine>\n</package>\n'
            ) % (
                TITLE,
                AUTHOR,
                DESC,
                '\n'.join(
                    '  <item id="ch%d" href="ch%d.xhtml" '
                    'media-type="application/xhtml+xml"/>' % (i, i)
                    for i in range(1, len(CHAPTERS) + 1)
                ),
                '\n'.join(
                    '  <itemref idref="ch%d"/>' % i
                    for i in range(1, len(CHAPTERS) + 1)
                ),
            )
            z.writestr('OEBPS/content.opf', opf)
        else:
            ncx_points = '\n'.join(
                '    <navPoint id="np%d" playOrder="%d">\n'
                '      <navLabel><text>%s</text></navLabel>\n'
                '      <content src="ch%d.xhtml"/>\n'
                '    </navPoint>' % (i, i, c[0], i)
                for i, c in enumerate(CHAPTERS, start=1)
            )
            ncx = (
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
                '  <head><meta name="dtb:uid" content="urn:uuid:demo-0002"/></head>\n'
                '  <docTitle><text>%s</text></docTitle>\n'
                '  <navMap>\n%s\n  </navMap>\n</ncx>\n' % (TITLE, ncx_points)
            )
            z.writestr('OEBPS/toc.ncx', ncx)
            opf = (
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
                'unique-identifier="bookid">\n'
                ' <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
                '  <dc:identifier id="bookid">urn:uuid:demo-0002</dc:identifier>\n'
                '  <dc:title>%s</dc:title>\n'
                '  <dc:creator>%s</dc:creator>\n'
                '  <dc:language>zh-CN</dc:language>\n'
                '  <meta name="cover" content="cover"/>\n'
                ' </metadata>\n'
                ' <manifest>\n'
                '  <item id="ncx" href="toc.ncx" '
                'media-type="application/x-dtbncx+xml"/>\n'
                '  <item id="cover" href="cover.png" media-type="image/png"/>\n'
                '%s'
                ' </manifest>\n'
                ' <spine toc="ncx">\n%s\n </spine>\n</package>\n'
            ) % (
                TITLE,
                AUTHOR,
                '\n'.join(
                    '  <item id="ch%d" href="ch%d.xhtml" '
                    'media-type="application/xhtml+xml"/>' % (i, i)
                    for i in range(1, len(CHAPTERS) + 1)
                ),
                '\n'.join(
                    '  <itemref idref="ch%d"/>' % i
                    for i in range(1, len(CHAPTERS) + 1)
                ),
            )
            z.writestr('OEBPS/content.opf', opf)
    print('EPUB 已生成:', path)


write_epub(os.path.join(OUT, 'novel_epub3.epub'), epub3=True)
write_epub(os.path.join(OUT, 'novel_epub2.epub'), epub3=False)

print('全部素材生成完成 ->', OUT)
