#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""彩蛋立绘质检：逐张评估「生气表情是否到位 + 姿势是否自然」。

用法：python3 tool/vlm_check_rage.py tool/artwork/candidates/pet_rage_v4_a.jpg ...
"""
import base64
import json
import os
import sys
import urllib.request

KEY = open('/tmp/sf_key').read().strip()

# 针对性问题：直接对齐用户反馈的两个问题
QUESTION = (
    '请严格评估这张 Q 版（chibi）角色立绘，用于手机 App 的「生气」表情：\n'
    '1) 画风：是否为日本动画赛璐璐上色风格？是否避免写实/3D/厚涂/油光？\n'
    '2) 【姿势】姿态是否自然？具体描述她的站姿/手部动作/腿部动作。'
    '有没有抬腿、单脚站立、扭腰、手臂姿势别扭等「奇怪姿势」问题？\n'
    '3) 【表情】是否明显表达"生气"？描述眉毛、眼睛、嘴巴、脸颊。\n'
    '4) 是否有明显的画面缺陷（多余肢体、畸形手、眼神呆滞、结构错误）？\n'
    '5) 背景是否为干净的纯色/白色（便于抠图）？\n'
    '最后给出一行结论：适合/不适合作为「生气」立绘，并打分 1-10。'
)


def check(img, question=QUESTION):
    ext = img.rsplit('.', 1)[-1].lower()
    mime = 'image/png' if ext == 'png' else 'image/jpeg'
    b64 = base64.b64encode(open(img, 'rb').read()).decode()
    body = {
        'model': 'Qwen/Qwen3-VL-32B-Instruct',
        'messages': [{
            'role': 'user',
            'content': [
                {'type': 'image_url', 'image_url': {'url': f'data:{mime};base64,{b64}'}},
                {'type': 'text', 'text': question},
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
                 if f.startswith('pet_rage_v4')]
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