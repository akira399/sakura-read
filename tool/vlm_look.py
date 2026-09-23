#!/usr/bin/env python3
"""用硅基流动的 Qwen3-VL 视觉模型“看图说话”——给生成的插画做质检报告。
用法: python3 vlm_look.py <image_path> [自定义问题]
"""
import base64
import json
import sys
import urllib.request

KEY = open('/tmp/sf_key').read().strip()
IMG = sys.argv[1]
QUESTION = sys.argv[2] if len(sys.argv) > 2 else (
    '请详细评价这张插画：'
    '1) 画风是否为日系动画/二次元风格（像不像日本动画的赛璐璐/插画风），还是更像3D/写实/欧美风？'
    '2) 人物外观：发型发色、服装、表情、姿态、气质。'
    '3) 构图、光影、色彩、背景元素。'
    '4) 有没有明显缺陷（手部、眼睛、解剖、文字乱码、肢体错误）？'
    '5) 整体是否适合做一款手机阅读App的“看板娘”形象？打分1-10。'
)
EXT = IMG.rsplit('.', 1)[-1].lower()
MIME = 'image/png' if EXT == 'png' else 'image/jpeg'
B64 = base64.b64encode(open(IMG, 'rb').read()).decode()

BODY = {
    'model': 'Qwen/Qwen3-VL-32B-Instruct',
    'messages': [{
        'role': 'user',
        'content': [
            {'type': 'image_url', 'image_url': {'url': f'data:{MIME};base64,{B64}'}},
            {'type': 'text', 'text': QUESTION},
        ],
    }],
    'max_tokens': 1200,
}
REQ = urllib.request.Request(
    'https://api.siliconflow.cn/v1/chat/completions',
    data=json.dumps(BODY).encode(),
    headers={'Authorization': f'Bearer {KEY}', 'Content-Type': 'application/json'},
)
RESP = json.loads(urllib.request.urlopen(REQ, timeout=180).read())
print(RESP['choices'][0]['message']['content'])