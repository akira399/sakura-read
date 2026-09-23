#!/bin/bash
# wait_for.sh —— 有界等待助手（专治“界面长时间卡在等待”）
#
# 用法: bash tool/wait_for.sh <文件路径> <关键词> [最多等待秒数，默认60]
#
# 行为:
#   - 每 2 秒检查一次文件是否包含关键词；
#   - 发现关键词 → 打印 FOUND 并立即返回（退出码 0）；
#   - 到时限仍无 → 打印 TIMEOUT 返回（退出码 1）。
#     任务可能仍在后台跑，稍后再次调用本脚本检查即可。
#
# 目的: 所有“等后台任务”的场景都改成 后台启动 + 本脚本轮询，
#       单次调用有界（默认≤60s），不再使用无界长 sleep，
#       界面不会长时间卡在“执行中”。
FILE="$1"
PATTERN="$2"
MAX="${3:-60}"

if [ -z "$FILE" ] || [ -z "$PATTERN" ]; then
  echo "用法: bash tool/wait_for.sh <文件路径> <关键词> [最多等待秒数]"
  exit 2
fi

i=0
while [ "$i" -lt "$MAX" ]; do
  if [ -f "$FILE" ] && grep -q "$PATTERN" "$FILE" 2>/dev/null; then
    echo "FOUND(等待${i}s): \"$PATTERN\" in $FILE"
    exit 0
  fi
  # 注意: proot 环境里 shell 自带 sleep 会偶发 "write error: Function not implemented"，
  # 这里优先用 Python 的 sleep（系统调用），失败才退回 shell sleep。
  python3 -c 'import time; time.sleep(2)' 2>/dev/null || sleep 2
  i=$((i+2))
done
echo "TIMEOUT(等待${MAX}s): 未发现 \"$PATTERN\"，任务可能仍在运行，稍后再查。"
exit 1