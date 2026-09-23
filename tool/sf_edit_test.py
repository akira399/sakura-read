#!/usr/bin/env python3
"""试探 Qwen-Image-Edit 调用参数：输入一张图 + 编辑指令，输出编辑后的图。
用法: cd <工作区> && python3 tool/sf_edit_test.py <输入图相对路径> <输出名> [编辑指令]
"""
import base64
import json
import sys
import urllib.error
import urllib.request

KEY = open('/tmp/sf_key').read().strip()
SRC = sys.argv[1] if len(sys.argv) > 1 else 'tool/artwork/candidates/zimage_turbo_ver1.jpg'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'pink_edit_v1'
INSTR = sys.argv[3] if len(sys.argv) > 3 else '把少女的黑色头发改成柔顺的淡樱花粉色长发，其他一切保持不变。'

b64 = base64.b64encode(open(SRC, 'rb').read()).decode()
body = {
    "model": "Qwen/Qwen-Image-Edit",
    "prompt": INSTR,
    "image": f"data:image/jpeg;base64,{b64}",
    "image_size": "1024x1024",
}
req = urllib.request.Request(
    "https://api.siliconflow.cn/v1/images/generations",
    data=json.dumps(body, ensure_ascii=False).encode(),
    headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
)
try:
    resp = json.loads(urllib.request.urlopen(req, timeout=300).read())
    print('RESP:', json.dumps(resp, ensure_ascii=False)[:400])
    if isinstance(resp, dict) and 'images' in resp:
        url = resp['images'][0]['url']
        data = urllib.request.urlopen(url, timeout=180).read()
        out_path = f'tool/artwork/candidates/{OUT}.jpg'
        open(out_path, 'wb').write(data)
        print('SAVED', out_path, len(data), 'bytes')
except urllib.error.HTTPError as e:
    print('HTTPError', e.code)
    print(e.read().decode()[:800])