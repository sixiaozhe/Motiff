#!/usr/bin/env bash
# motion_diff.sh - 视频运动时间差分可视化
# 将视频反色、半透明、相对原画面时间偏移 N 帧后叠加回原视频。
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  motion_diff.sh -i <输入视频> [-o <输出视频>] [-n <帧偏移>] [-a <不透明度>]

参数:
  -i  输入视频路径 (必填)
  -o  输出视频路径 (默认: <输入名>_motiondiff.<原扩展名>)
  -n  时间偏移帧数  正数=拖尾(叠加 N 帧前), 负数=前导(叠加 N 帧后) (默认: 3)
  -a  反色偏移层的不透明度, 0~1 (默认: 0.5)
  -h  显示本帮助并退出

示例:
  motion_diff.sh -i in.mp4                    # 拖尾 3 帧, 不透明度 0.5
  motion_diff.sh -i in.mp4 -n -5 -a 0.4       # 前导 5 帧, 不透明度 0.4
  motion_diff.sh -i in.mp4 -o out.mp4 -n 8    # 拖尾 8 帧
EOF
}

INPUT=""
OUTPUT=""
N=3
ALPHA=0.5

while getopts "i:o:n:a:h" opt; do
  case "$opt" in
    i) INPUT="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    n) N="$OPTARG" ;;
    a) ALPHA="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

command -v ffmpeg >/dev/null 2>&1 || { echo "错误: 未找到 ffmpeg, 请先安装。" >&2; exit 1; }

if [[ -z "$INPUT" ]]; then
  echo "错误: 必须用 -i 指定输入视频。" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "错误: 输入文件不存在: $INPUT" >&2
  exit 1
fi

if ! [[ "$N" =~ ^-?[0-9]+$ ]]; then
  echo "错误: -n 必须为整数, 当前为 '$N'。" >&2
  exit 1
fi

if [[ "$N" -eq 0 ]]; then
  echo "错误: -n 不能为 0 (无运动信息, 画面会变成纯灰)。" >&2
  exit 1
fi

if ! awk -v a="$ALPHA" 'BEGIN { exit !(a ~ /^[0-9]*\.?[0-9]+$/ && a + 0 >= 0 && a + 0 <= 1) }'; then
  echo "错误: -a 必须在 0~1 之间, 当前为 '$ALPHA'。" >&2
  exit 1
fi

if [[ -z "$OUTPUT" ]]; then
  base="${INPUT%.*}"
  ext="${INPUT##*.}"
  if [[ "$base" == "$INPUT" ]]; then
    base="$INPUT"
    ext="mp4"
  fi
  OUTPUT="${base}_motiondiff.${ext}"
fi

ABS_N="${N#-}"

if [[ "$N" -gt 0 ]]; then
  SHIFT="tpad=start=${ABS_N}:start_mode=clone"
else
  SHIFT="trim=start_frame=${ABS_N},setpts=PTS-STARTPTS,tpad=stop=${ABS_N}:stop_mode=clone"
fi

FILTER="[0:v]scale=trunc(iw/2)*2:trunc(ih/2)*2,format=gbrp,split=2[base][fx];"
FILTER+="[fx]negate,${SHIFT}[fx2];"
FILTER+="[base][fx2]blend=all_expr='A*(1-${ALPHA})+B*${ALPHA}':eof_action=endall,format=yuv420p[v]"

echo "输入:   $INPUT"
echo "输出:   $OUTPUT"
echo "偏移:   ${N} 帧 ($([[ "$N" -gt 0 ]] && echo 拖尾 || echo 前导))"
echo "不透明度: ${ALPHA}"

ffmpeg -v warning -stats -y -i "$INPUT" \
  -filter_complex "$FILTER" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart \
  "$OUTPUT"

echo "完成: $OUTPUT"
