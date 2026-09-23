#!/usr/bin/env python3
"""多图对比质检：核对多张看板娘素材是否为“同一个角色”。

用法: python3 tool/vlm_compare.py <img1> <img2> [img3 ...]
"""
import base64
import json
import sys
import urllib.request

KEY = open('/tmp/sf_key').read().strip()

QUESTION = (
    '这是同一款阅读App的看板娘系列插画候选。请重点回答：'
    '1) 这些图中的少女是否为“同一个角色”？从发型发色、发饰、服装搭配、脸型五官、整体气质逐项对比，'
    '指出哪些一致、哪些明显不一致；'
    '2) 如果要做成同一套App素材，一致性能打几分（1-10）？有待改进的关键点是什么（用简短清单）；'
    '3) 每张图分别适合什么用途（空状态陪伴 / 关于页立绘 / 欢迎招呼 / 阅读中/加载）？'
)

content = []
for p in sys.argv[1:]:
    ext = p.rsplit('.', 1)[-1].lower()
    mime = 'image/png' if ext == 'png' else 'image/jpeg'
    b64 = base64.b64encode(open(p, 'rb').read()).decode()
    content.append({'type': 'image_url', 'image_url': {'url': f'data:{mime};base64,{b64}'}})
content.append({'type': 'text', 'text': QUESTION})

body = {
    'model': 'Qwen/Qwen3-VL-32B-Instruct',
    'messages': [{'role': 'user', 'content': content}],
    'max_tokens': 2000,
}
req = urllib.request.Request(
    'https://api.siliconflow.cn/v1/chat/completions',
    data=json.dumps(body).encode(),
    headers={'Authorization': f'Bearer {KEY}', 'Content-Type': 'application/json'},
)
resp = json.loads(urllib.request.urlopen(req, timeout=300).read())
print(resp['choices'][0]['message']['content'])