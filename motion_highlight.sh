#!/usr/bin/env bash
# motion_highlight.sh - 无残影运动高亮 (相邻帧差分)
# 用 |当前帧 - 上一帧| 作为高亮蒙版叠加回原帧: 静态区域保持原样,
# 仅在运动处按当前位置着色, 不产生位移重影。
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  motion_highlight.sh -i <输入视频> [-o <输出视频>] [-b] [-s] [-x] [-d]
                      [-k <帧距>] [-n <背景窗口>] [-t <阈值>] [-g <增益>] [-c <颜色>]

参数:
  -i  输入视频路径 (必填)
  -o  输出视频路径 (默认: <输入名>_highlight.mp4, -x 时为 <输入名>_remove.mp4)
  -b  不要背景: 原画面置黑, 只保留运动高亮
  -s  透层模式: 凡有运动高亮的像素都完全透出原画面, 静止处黑屏 (二值, 不膨胀)
  -x  去物/隐形模式: 运动物体替换为背景估计(时间中值), 物体消失露出背景
  -n  背景估计窗口帧数(-x), >=3 的奇数; 越大去物越彻底但背景变化时易残影 (默认: 15)
  -e  高亮/物体边缘羽化强度(高斯 sigma); 0=硬边, 越大边缘越柔和 (默认: 2)
  -d  差分前做时域降噪(atadenoise), 抑制暗光/噪点引起的闪点 (默认: 关)
  -k  参考帧距(帧): 与 N 帧前比较而非相邻帧; >1 可填充运动体、减少前后双边缘 (默认: 1)
  -t  差分阈值, 0~255; 低于此值视为噪声不高亮 (默认: 15)
  -g  高亮增益, >0; 越大高亮越强 (默认: 3)
  -c  高亮颜色, 6 位十六进制 RRGGBB (默认: ffffff 白)
  -h  显示本帮助并退出

示例:
  motion_highlight.sh -i in.mp4
  motion_highlight.sh -i in.mp4 -b                 # 黑底白线
  motion_highlight.sh -i in.mp4 -s                 # 有运动处完全透出原画面, 静止黑屏
  motion_highlight.sh -i in.mp4 -s -e 4            # 边缘更柔和
  motion_highlight.sh -i in.mp4 -s -e 0            # 严格二值硬边
  motion_highlight.sh -i in.mp4 -s -d              # 暗光素材, 先降噪去闪点
  motion_highlight.sh -i in.mp4 -s -k 3            # 与3帧前比较, 运动体更完整
  motion_highlight.sh -i in.mp4 -x                 # 去掉运动的人/车, 露出背景
  motion_highlight.sh -i in.mp4 -x -n 31 -t 25     # 更长背景窗口, 更彻底去物
  motion_highlight.sh -i in.mp4 -b -t 25 -c ff7319 # 黑底橙色
EOF
}

INPUT=""
OUTPUT=""
THRESH=15
GAIN=3
COLOR="ffffff"
BG_SUPPRESS=0
SILHOUETTE=0
SIGMA=2
DENOISE=0
GAP=1
REMOVE=0
BGWIN=15

while getopts "i:o:t:g:c:bse:dk:xn:h" opt; do
  case "$opt" in
    i) INPUT="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    b) BG_SUPPRESS=1 ;;
    s) SILHOUETTE=1 ;;
    e) SIGMA="$OPTARG" ;;
    d) DENOISE=1 ;;
    k) GAP="$OPTARG" ;;
    x) REMOVE=1 ;;
    n) BGWIN="$OPTARG" ;;
    t) THRESH="$OPTARG" ;;
    g) GAIN="$OPTARG" ;;
    c) COLOR="$OPTARG" ;;
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

if ! [[ "$THRESH" =~ ^[0-9]+$ ]] || [[ "$THRESH" -gt 255 ]]; then
  echo "错误: -t 必须为 0~255 的整数, 当前为 '$THRESH'。" >&2
  exit 1
fi

if ! awk -v g="$GAIN" 'BEGIN { exit !(g ~ /^[0-9]*\.?[0-9]+$/ && g + 0 > 0) }'; then
  echo "错误: -g 必须为正数, 当前为 '$GAIN'。" >&2
  exit 1
fi

if ! [[ "$COLOR" =~ ^[0-9a-fA-F]{6}$ ]]; then
  echo "错误: -c 必须为 6 位十六进制 RRGGBB, 当前为 '$COLOR'。" >&2
  exit 1
fi

if ! awk -v s="$SIGMA" 'BEGIN { exit !(s ~ /^[0-9]*\.?[0-9]+$/ && s + 0 >= 0) }'; then
  echo "错误: -e 必须为非负数, 当前为 '$SIGMA'。" >&2
  exit 1
fi

if ! [[ "$GAP" =~ ^[0-9]+$ ]] || [[ "$GAP" -lt 1 ]]; then
  echo "错误: -k 必须为 >=1 的整数(帧), 当前为 '$GAP'。" >&2
  exit 1
fi

if ! [[ "$BGWIN" =~ ^[0-9]+$ ]] || [[ "$BGWIN" -lt 3 ]] || [[ $((BGWIN % 2)) -eq 0 ]]; then
  echo "错误: -n 必须为 >=3 的奇数(帧), 当前为 '$BGWIN'。" >&2
  exit 1
fi

if [[ -z "$OUTPUT" ]]; then
  base="${INPUT%.*}"
  ext="${INPUT##*.}"
  if [[ "$base" == "$INPUT" ]]; then
    base="$INPUT"
    ext="mp4"
  fi
  if [[ "$REMOVE" -eq 1 ]]; then
    OUTPUT="${base}_remove.${ext}"
  else
    OUTPUT="${base}_highlight.${ext}"
  fi
fi

BGR=$(( (BGWIN - 1) / 2 ))

RM=$(awk -v v=$((16#${COLOR:0:2})) 'BEGIN { printf "%.4f", v/255 }')
GM=$(awk -v v=$((16#${COLOR:2:2})) 'BEGIN { printf "%.4f", v/255 }')
BM=$(awk -v v=$((16#${COLOR:4:2})) 'BEGIN { printf "%.4f", v/255 }')

DENCHAIN=""
[[ "$DENOISE" -eq 1 ]] && DENCHAIN="atadenoise,"

if [[ "$GAP" -gt 1 ]]; then
  DIFFCHAIN="${DENCHAIN}split=2[da][db];[db]tpad=start=${GAP}:start_mode=clone[dbp];[da][dbp]blend=all_mode=difference:shortest=1,"
else
  DIFFCHAIN="${DENCHAIN}tblend=all_mode=difference,"
fi

SMOOTH=""
if awk -v s="$SIGMA" 'BEGIN { exit !(s + 0 > 0) }'; then
  SMOOTH="gblur=sigma=${SIGMA},"
fi

if [[ "$REMOVE" -eq 1 ]]; then
  FILTER="[0:v]format=gbrp,split=2[base][tb];"
  FILTER+="[tb]tpad=start=${BGR}:start_mode=clone:stop=${BGR}:stop_mode=clone,"
  FILTER+="tmedian=radius=${BGR},setpts=PTS-STARTPTS[bgs];"
  FILTER+="[bgs]split=2[bg1][bg2];"
  FILTER+="[base]split=2[cur][cmp];"
  FILTER+="[cmp][bg1]blend=all_mode=difference,format=gray,"
  FILTER+="lut=y='if(lt(val\,${THRESH}),0,255)',${SMOOTH}format=gbrp[m];"
  FILTER+="[cur][bg2][m]maskedmerge,format=yuv420p[v]"
elif [[ "$SILHOUETTE" -eq 1 ]]; then
  FILTER="[0:v]format=gbrp,split=2[base][d];"
  FILTER+="[d]${DIFFCHAIN}format=gray,"
  FILTER+="lut=y='if(lt(val\,${THRESH}),0,255)',${SMOOTH}format=gbrp[m];"
  FILTER+="[base][m]blend=all_mode=multiply,format=yuv420p[v]"
else
  DIFF="${DIFFCHAIN}format=gray,"
  DIFF+="lut=y='if(lt(val\,${THRESH}),0,min(255,(val-${THRESH})*${GAIN}))',"
  DIFF+="format=gbrp,lutrgb=r='val*${RM}':g='val*${GM}':b='val*${BM}'"

  if [[ "$BG_SUPPRESS" -eq 1 ]]; then
    FILTER="[0:v]format=gbrp,${DIFF},tpad=stop=1:stop_mode=clone,format=yuv420p[v]"
  else
    FILTER="[0:v]format=gbrp,split=2[base][d];"
    FILTER+="[d]${DIFF}[hi];"
    FILTER+="[base][hi]blend=all_mode=screen,format=yuv420p[v]"
  fi
fi

echo "输入:   $INPUT"
echo "输出:   $OUTPUT"
if [[ "$REMOVE" -eq 1 ]]; then
  echo "模式:   去物/隐形 (运动物体替换为背景估计, 背景窗口: ${BGWIN} 帧)   边缘羽化: ${SIGMA}"
elif [[ "$SILHOUETTE" -eq 1 ]]; then
  echo "模式:   透层 (有高亮的像素完全透出原画面, 静止黑屏)   边缘羽化: ${SIGMA}"
else
  echo "背景:   $([[ "$BG_SUPPRESS" -eq 1 ]] && echo '置黑' || echo '保留')"
  echo "颜色:   #${COLOR}   增益: ${GAIN}"
fi
echo "阈值:   ${THRESH}   参考帧距: ${GAP}   时域降噪: $([[ "$DENOISE" -eq 1 ]] && echo '开' || echo '关')"

ffmpeg -v warning -stats -y -i "$INPUT" \
  -filter_complex "$FILTER" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart \
  "$OUTPUT"

echo "完成: $OUTPUT"
