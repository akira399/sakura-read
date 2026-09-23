#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""探测候选「正版 / 无版权风险」书源站点，输出结构摘要（供书源规则设计）。

用法：python3 tool/probe_legal_sources.py
输出：tool/probe_out/*.html + 控制台摘要
"""
import os
import ssl
import urllib.parse
import urllib.request

UA = (
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36'
)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'probe_out')
os.makedirs(OUT, exist_ok=True)

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def fetch(name, url, headers=None, timeout=25):
    h = {'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9'}
    if headers:
        h.update(headers)
    try:
        req = urllib.request.Request(url, headers=h)
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            data = r.read()
        path = os.path.join(OUT, '%s.html' % name)
        with open(path, 'wb') as f:
            f.write(data)
        print('[OK] %-22s %s bytes  %s' % (name, len(data), r.status))
        return data.decode('utf-8', 'replace')
    except Exception as e:  # noqa: BLE001
        print('[ERR] %-22s %s: %s' % (name, type(e).__name__, e))
        return ''


def main():
    # 1) 中文维基文库（公有领域文献，CC BY-SA）
    fetch('ws_search', 'https://zh.wikisource.org/w/index.php?search=%s&title=Special:%%E6%%90%%9C%%E7%%B4%%A2' % urllib.parse.quote('論語'))
    fetch('ws_book', 'https://zh.wikisource.org/wiki/%s' % urllib.parse.quote('論語'))
    fetch('ws_chapter', 'https://zh.wikisource.org/wiki/%s' % urllib.parse.quote('論語/學而第一'))
    # 2) 古腾堡（公版书 API）
    fetch('gd_zh', 'https://gutendex.com/books?languages=zh')
    # 3) 中文维基文库 API（章节列表）
    fetch('ws_api_search', 'https://zh.wikisource.org/w/api.php?action=query&list=search&srsearch=%s&format=json&srlimit=3' % urllib.parse.quote('論語'))
    fetch('ws_api_parse', 'https://zh.wikisource.org/w/api.php?action=parse&page=%s&prop=text&format=json' % urllib.parse.quote('論語'))
    # 4) 官方正版平台（仅探测可达性，不抓付费内容）
    fetch('official_qidian', 'https://www.qidian.com/so/%s.html' % urllib.parse.quote('斗破苍穹'))
    fetch('official_fanqie', 'https://fanqienovel.com/api/author/search/search_book/v1?query=%s' % urllib.parse.quote('斗破苍穹'))
    fetch('official_qimao', 'https://www.qimao.com/search?keyword=%s' % urllib.parse.quote('斗破苍穹'))
    print('\nDONE -> %s' % OUT)


if __name__ == '__main__':
    main()
