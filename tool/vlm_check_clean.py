#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查生气立绘是否「干净无符号」（重点：不能有星号/十字/emoji 等装饰）。

用法：python3 tool/vlm_check_clean.py tool/artwork/candidates/pet_rage_v5_a.jpg ...
"""
import base64
import json
import os
import sys
import urllib.request

KEY = open('/tmp/sf_key').read().strip()

QUESTION = (
    '请仔细观察这张 Q 版动漫少女立绘，严格回答：\n'
    '1) 人物头部周围、身体周围、背景里，有没有任何【符号或装饰图案】？'
    '例如：星号 * 六角星 十字 💢 青筋符号 emoji 爱心 闪光 图标 文字。'
    '请明确回答"有"或"没有"，若有请具体描述位置和形状。\n'
    '2) 背景是否为干净的纯白色且没有图案？\n'
    '3) 人物姿态是否自然（双手叉腰站立、双脚并拢）？有无抬腿/扭曲？\n'
    '4) 表情是否明显生气（皱眉/瞪眼/鼓脸）？\n'
    '5) 画面是否有畸形（多余手指、结构错误）？\n'
    '最后给一行结论：可用 / 不可用（若含符号则不可用），并打分 1-10。'
)


def check(img):
    ext = img.rsplit('.', 1)[-1].lower()
    mime = 'image/png' if ext == 'png' else 'image/jpeg'
    b64 = base64.b64encode(open(img, 'rb').read()).decode()
    body = {
        'model': 'Qwen/Qwen3-VL-32B-Instruct',
        'messages': [{
            'role': 'user',
            'content': [
                {'type': 'image_url', 'image_url': {'url': f'data:{mime};base64,{b64}'}},
                {'type': 'text', 'text': QUESTION},
            ],
        }],
        'max_tokens': 900,
    }
    req = urllib.request.Request(
        'https://api.siliconflow.cn/v1/chat/completions',
        data=json.dumps(body).encode(),
        headers={'Authorization': f'Bearer {KEY}',
                 'Content-Type': 'application/json'},
    )
    resp = json.loads(urllib.request.urlopen(req, timeout=200).read())
    return resp['choices'][0]['message']['content']


def main():
    paths = sys.argv[1:]
    if not paths:
        outdir = 'tool/artwork/candidates'
        paths = [os.path.join(outdir, f) for f in sorted(os.listdir(outdir))
                 if f.startswith('pet_rage_v5')]
    for p in paths:
        print('=' * 70)
        print('FILE:', p)
        print('=' * 70)
        try:
            print(check(p))
        except Exception as e:  # noqa: BLE001
            print('ERR', type(e).__name__, e)
        print()


if __name__ == '__main__':
    main()