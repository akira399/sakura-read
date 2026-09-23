#!/bin/bash
# 硅基流动文生图小工具
# 用法: bash sf_image.sh <model> <image_size> <prompt_file> <out_file>
# 例:   bash sf_image.sh "Qwen/Qwen-Image" "1024x1024" prompt.txt out.jpg
set -u
WS="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$1"
SIZE="$2"
PROMPT_FILE="$3"
OUT="$4"
KEY=$(cat /tmp/sf_key)

python3 - "$MODEL" "$SIZE" "$PROMPT_FILE" <<'PYEOF' > /tmp/sf_req.json
import json, sys
model, size, prompt_file = sys.argv[1], sys.argv[2], sys.argv[3]
prompt = open(prompt_file, encoding='utf-8').read().strip()
print(json.dumps({"model": model, "prompt": prompt, "image_size": size, "batch_size": 1}, ensure_ascii=False))
PYEOF

RESP=$(curl -sS -m 240 https://api.siliconflow.cn/v1/images/generations \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d @/tmp/sf_req.json)
echo "$RESP" > /tmp/sf_resp.json
URL=$(python3 -c "import json;d=json.load(open('/tmp/sf_resp.json'));print(d['images'][0]['url'] if isinstance(d,dict) and 'images' in d else '')" 2>/dev/null)
if [ -z "$URL" ]; then
  echo "FAIL($MODEL): $(head -c 400 /tmp/sf_resp.json)"
  exit 1
fi
curl -sS -m 120 -o "$OUT" "$URL" && echo "OK -> $OUT ($(stat -c%s "$OUT") bytes)"
