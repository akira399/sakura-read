#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三轮探测：公版古籍站点候选（国内可达性 + 结构）+ 维基文库目录结构。"""
import os
import re
import ssl
import urllib.parse
import urllib.request

UA = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/122.0 Mobile Safari/537.36'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'probe_out')
os.makedirs(OUT, exist_ok=True)
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def get(name, url, timeout=20):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            data = r.read()
            code = r.status
            final = r.geturl()
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
        print('[OK] %-18s %6d B  %s' % (name, len(data), final[:80]))
        return data.decode('utf-8', 'replace')
    except Exception as e:
        print('[ERR] %-18s %s: %s' % (name, type(e).__name__, str(e)[:80]))
        return ''


def probe_links(html, pats, limit=8):
    for p in pats:
        m = re.findall(p, html)
        print('     %-52s hits=%d %s' % (p[:52], len(m), (str(m[0])[:100] if m else '')))


def main():
    q = urllib.parse.quote
    print('### 候选站点可达性 + 首页结构')
    for name, url in [
        ('zhdc_home', 'http://www.zhonghuadiancang.com/'),
        ('openlit_home', 'http://www.open-lit.com/'),
        ('gushiwen', 'https://www.gushiwen.cn/'),
        ('ws_book2', 'https://zh.wikisource.org/wiki/%E4%B8%89%E5%9C%8B%E6%BC%94%E7%BE%A9'),
        ('ws_book3', 'https://zh.wikisource.org/wiki/%E7%B4%85%E6%A8%93%E5%A4%A2'),
    ]:
        h = get(name, url)
        if h and name == 'zhdc_home':
            probe_links(h, [r'<a[^>]*href="(/[a-z]+/[0-9]+/?)"[^>]*>([^<]{1,20})</a>',
                            r'class="([^"]{0,30})"'])
        if h and name in ('ws_book2', 'ws_book3'):
            probe_links(h, [r'<h2[^>]*id="([^"]*)"', r'mw-parser-output'])

    print('\n### 维基文库《論語》目录区结构')
    s = open(os.path.join(OUT, 'ws_book.html'), encoding='utf-8', errors='replace').read()
    i = s.find('id="各篇"')
    print(re.sub(r'\s+', ' ', s[i:i + 1800])[:1800])

    print('\n### 维基文库搜索 API 结果结构（论語）')
    s = open(os.path.join(OUT, 'api_search.json'), encoding='utf-8', errors='replace').read()
    print(s[:900])
    print('\nDONE')


if __name__ == '__main__':
    main()