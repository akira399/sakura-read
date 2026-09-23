#!/usr/bin/env python3
"""批量文生图：读 manifest JSON（任务列表），依次生成到 tool/artwork/candidates/。

用法: python3 tool/sf_batch.py tool/artwork/manifest_wave2.json
"""
import json
import os
import sys
import time
import urllib.request

WS = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
KEY = open('/tmp/sf_key').read().strip()
API = 'https://api.siliconflow.cn/v1/images/generations'


def gen_one(model, prompt, size, seed=None, negative=None):
    body = {"model": model, "prompt": prompt, "image_size": size, "batch_size": 1}
    if seed is not None:
        body["seed"] = seed
    if negative:
        body["negative_prompt"] = negative
    req = urllib.request.Request(
        API,
        data=json.dumps(body, ensure_ascii=False).encode(),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    resp = json.loads(urllib.request.urlopen(req, timeout=300).read())
    if 'images' not in resp:
        raise RuntimeError(str(resp)[:300])
    url = resp['images'][0]['url']
    data = urllib.request.urlopen(url, timeout=180).read()
    return data, resp.get('seed')


def main():
    manifest = json.load(open(sys.argv[1], encoding='utf-8'))
    outdir = os.path.join(WS, 'tool/artwork/candidates')
    os.makedirs(outdir, exist_ok=True)
    for t in manifest:
        out = os.path.join(outdir, t['name'] + '.jpg')
        if os.path.exists(out) and not t.get('force'):
            print(f"SKIP {t['name']} (exists)", flush=True)
            continue
        print(f"GEN {t['name']} ({t['model']}) ...", flush=True)
        try:
            data, seed = gen_one(
                t['model'], t['prompt'], t.get('size', '1024x1024'), t.get('seed'),
                t.get('negative'))
            open(out, 'wb').write(data)
            print(f"OK {t['name']} {len(data)}B seed={seed}", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {t['name']}: {e}", flush=True)
        time.sleep(1)


if __name__ == '__main__':
    main()