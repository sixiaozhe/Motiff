#!/usr/bin/env bash
# 冒烟测试: 生成运动测试视频, 验证双向时移、帧数、错误处理。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
SCRIPT="$ROOT/motion_diff.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

command -v ffmpeg >/dev/null 2>&1 || { echo "SKIP: 未找到 ffmpeg"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: 未找到 python3"; exit 0; }

echo "== 生成运动测试视频 (白色方块右移, 50 帧) =="
ffmpeg -v error -y -f lavfi -i "color=c=black:s=320x240:r=25:d=2" \
  -f lavfi -i "color=c=white:s=60x60:r=25:d=2" \
  -filter_complex "[0:v][1:v]overlay=x='mod(t*80,220)':y=80,format=yuv420p" \
  -c:v libx264 -pix_fmt yuv420p "$TMP/testbox.mp4" || { echo "无法生成测试视频"; exit 1; }

frame_count() {
  ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of csv=p=0 "$1"
}

check_bands() {
  local raw="$1" expect="$2" label="$3"
  if python3 - "$raw" "$expect" <<'PY'
import sys
raw, expect = sys.argv[1], sys.argv[2]
W, H = 320, 240
d = open(raw, 'rb').read()
n = len(d) // (W * H * 3)
if n != 50:
    sys.exit(f"帧数 {n} != 50")
k, y = 25, 110
fr = d[k * W * H * 3:(k + 1) * W * H * 3]

def cls(x):
    v = sum(fr[(y * W + x) * 3:(y * W + x) * 3 + 3]) // 3
    return 'W' if v > 215 else ('K' if v < 40 else '.')

s = ''.join(cls(x) for x in range(W))
if 'W' not in s or 'K' not in s:
    sys.exit("缺少黑/白运动带")
Wmin, Wmax = s.find('W'), s.rfind('W')
Kmin, Kmax = s.find('K'), s.rfind('K')
if expect == 'trail' and not (Kmin < Wmin):
    sys.exit(f"拖尾应黑带在左: K{Kmin} W{Wmin}")
if expect == 'lead' and not (Wmin < Kmin):
    sys.exit(f"前导应白带在左: W{Wmin} K{Kmin}")
bg = sum(fr[(y * W + 5) * 3:(y * W + 5) * 3 + 3]) // 3
if not 90 <= bg <= 165:
    sys.exit(f"静态背景应为中灰, 实际 {bg}")
PY
  then ok "$label"; else no "$label"; fi
}

echo "== 拖尾 (N=5) =="
if bash "$SCRIPT" -i "$TMP/testbox.mp4" -o "$TMP/trail.mp4" -n 5 -a 0.5 >/dev/null 2>&1; then
  ok "脚本执行成功"
  ffmpeg -v error -y -i "$TMP/trail.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/trail.raw"
  check_bands "$TMP/trail.raw" trail "残影方向与静态变灰正确"
  [[ "$(frame_count "$TMP/trail.mp4")" == "50" ]] && ok "输出 50 帧" || no "输出帧数错误: $(frame_count "$TMP/trail.mp4")"
else
  no "拖尾模式脚本执行失败"
fi

echo "== 前导 (N=-5) =="
if bash "$SCRIPT" -i "$TMP/testbox.mp4" -o "$TMP/lead.mp4" -n -5 -a 0.5 >/dev/null 2>&1; then
  ok "脚本执行成功"
  ffmpeg -v error -y -i "$TMP/lead.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/lead.raw"
  check_bands "$TMP/lead.raw" lead "残影方向与静态变灰正确"
  [[ "$(frame_count "$TMP/lead.mp4")" == "50" ]] && ok "输出 50 帧" || no "输出帧数错误: $(frame_count "$TMP/lead.mp4")"
else
  no "前导模式脚本执行失败"
fi

echo "== 参数与错误处理 =="
bash "$SCRIPT" -h >/dev/null 2>&1 && ok "-h 退出码 0" || no "-h 退出码非 0"
bash "$SCRIPT" >/dev/null 2>&1 && no "缺 -i 应失败" || ok "缺 -i 正确失败"
bash "$SCRIPT" -i "$TMP/nope.mp4" >/dev/null 2>&1 && no "输入不存在应失败" || ok "输入不存在正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -n 0 >/dev/null 2>&1 && no "-n 0 应失败" || ok "-n 0 正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -a 2 >/dev/null 2>&1 && no "-a 2 应失败" || ok "-a 2 正确失败"

echo
echo "== 结果: $pass 通过, $fail 失败 =="
[[ "$fail" -eq 0 ]]
