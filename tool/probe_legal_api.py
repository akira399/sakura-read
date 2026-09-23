#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第二轮探测：验证「公版/开放内容」源的 API 形态（供书源规则设计）。"""
import json
import os
import ssl
import urllib.parse
import urllib.request

UA = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/122.0 Mobile Safari/537.36'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'probe_out')
os.makedirs(OUT, exist_ok=True)
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def get(name, url, timeout=25):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            data = r.read()
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
        print('[OK] %-20s %6d bytes' % (name, len(data)))
        return data.decode('utf-8', 'replace')
    except Exception as e:
        print('[ERR] %-20s %s: %s' % (name, type(e).__name__, e))
        return ''


def main():
    q = urllib.parse.quote
    api = 'https://zh.wikisource.org/w/api.php'

    # 1) 搜索 API（简体关键词）
    t = get('api_search.json', '%s?action=query&list=search&srsearch=%s&format=json&srlimit=5' % (api, q('论语')))
    if t:
        d = json.loads(t)
        print('   search hits:', [(x['title'], round(x.get('size', 0))) for x in d['query']['search']])

    # 2) 章节列表（sections / links）
    t = get('api_sections.json', '%s?action=parse&page=%s&prop=sections&format=json' % (api, q('論語')))
    if t:
        d = json.loads(t)
        secs = d.get('parse', {}).get('sections', [])
        print('   sections:', [(s['line'], s['anchor']) for s in secs[:6]])

    # 3) 纯文本提取（extracts）
    t = get('api_extract.json', '%s?action=query&prop=extracts&explaintext=1&format=json&titles=%s' % (api, q('論語/學而第一')))
    if t:
        d = json.loads(t)
        pages = d.get('query', {}).get('pages', {})
        for k, v in pages.items():
            ex = v.get('extract', '')
            print('   extract len=%d  head=%r' % (len(ex), ex[:120]))

    # 4) 章节链接（parse links）
    t = get('api_links.json', '%s?action=parse&page=%s&prop=links&format=json' % (api, q('論語')))
    if t:
        d = json.loads(t)
        links = d.get('parse', {}).get('links', [])
        print('   links:', [x['*'] for x in links[:8]])

    # 5) 古腾堡：中文搜索 + 图书详情
    t = get('gd_search.json', 'https://gutendex.com/books?languages=zh&search=%s' % q('唐诗'))
    if t:
        d = json.loads(t)
        print('   gd count=%d  first=%s' % (d.get('count', 0), [b['title'] for b in d['results'][:3]]))
    t = get('gd_topic.json', 'https://gutendex.com/books?languages=zh&topic=%s' % q('literature'))
    if t:
        d = json.loads(t)
        print('   gd topic count=%d' % d.get('count', 0))
    print('\nDONE')


if __name__ == '__main__':
    main()