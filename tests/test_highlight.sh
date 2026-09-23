#!/usr/bin/env bash
# motion_highlight.sh 冒烟测试: 静态区不变、运动处高亮、错误处理。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
SCRIPT="$ROOT/motion_highlight.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }

command -v ffmpeg >/dev/null 2>&1 || { echo "SKIP: 未找到 ffmpeg"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: 未找到 python3"; exit 0; }

echo "== 生成运动测试视频 (白色方块右移, 黑色背景, 50 帧) =="
ffmpeg -v error -y -f lavfi -i "color=c=black:s=320x240:r=25:d=2" \
  -f lavfi -i "color=c=white:s=60x60:r=25:d=2" \
  -filter_complex "[0:v][1:v]overlay=x='mod(t*80,220)':y=80,format=yuv420p" \
  -c:v libx264 -pix_fmt yuv420p "$TMP/testbox.mp4" || { echo "无法生成测试视频"; exit 1; }

echo "== 运行高亮 =="
if bash "$SCRIPT" -i "$TMP/testbox.mp4" -o "$TMP/hl.mp4" -t 15 -g 3 -c ff7319 >/dev/null 2>&1; then
  ok "脚本执行成功"
  n=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$TMP/hl.mp4")
  [[ "$n" == "50" ]] && ok "输出 50 帧" || no "输出帧数错误: $n"
  ffmpeg -v error -y -i "$TMP/hl.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/hl.raw"
  if python3 - "$TMP/hl.raw" <<'PY'
import sys
W, H = 320, 240
d = open(sys.argv[1], 'rb').read()
fr = d[25 * W * H * 3:26 * W * H * 3]
def px(x, y):
    o = (y * W + x) * 3
    return fr[o], fr[o + 1], fr[o + 2]
# 静态角落必须仍是黑 (未高亮)
c = px(5, 5)
if max(c) > 12:
    sys.exit(f"静态角落被高亮: {c}")
# 运动处应出现橙色高亮 (R>G>B 且 R 足够亮)
orange = sum(1 for x in range(W) for y in range(80, 140)
             if (lambda p: p[0] > 150 and p[0] > p[1] > p[2] and p[2] < 90)(px(x, y)))
if orange < 10:
    sys.exit(f"运动处橙色高亮像素过少: {orange}")
print(f"orange={orange}")
PY
  then ok "静态区保持不变且运动处有橙色高亮"; else no "高亮效果断言失败"; fi
else
  no "高亮脚本执行失败"
fi

echo "== -b 黑底模式 (背景应被去掉) =="
ffmpeg -v error -y -f lavfi -i "color=c=green:s=320x240:r=25:d=2" \
  -f lavfi -i "color=c=white:s=60x60:r=25:d=2" \
  -filter_complex "[0:v][1:v]overlay=x='mod(t*80,220)':y=80,format=yuv420p" \
  -c:v libx264 -pix_fmt yuv420p "$TMP/testboxg.mp4"
bash "$SCRIPT" -i "$TMP/testboxg.mp4" -o "$TMP/g_def.mp4" >/dev/null 2>&1 \
  && bash "$SCRIPT" -i "$TMP/testboxg.mp4" -o "$TMP/g_b.mp4" -b >/dev/null 2>&1 \
  && ok "-b 模式执行成功" || no "-b 模式执行失败"
ffmpeg -v error -y -i "$TMP/g_def.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/g_def.raw"
ffmpeg -v error -y -i "$TMP/g_b.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/g_b.raw"
if python3 - "$TMP/g_def.raw" "$TMP/g_b.raw" <<'PY'
import sys
W, H = 320, 240
def corner(path):
    d = open(path, 'rb').read()
    fr = d[25 * W * H * 3:26 * W * H * 3]
    o = (5 * W + 5) * 3
    return fr[o], fr[o + 1], fr[o + 2]
def has_white(path):
    d = open(path, 'rb').read()
    fr = d[25 * W * H * 3:26 * W * H * 3]
    n = 0
    for x in range(W):
        for y in range(80, 140):
            o = (y * W + x) * 3
            r, g, b = fr[o], fr[o + 1], fr[o + 2]
            if r > 150 and abs(r - g) < 30 and abs(g - b) < 30:
                n += 1
    return n
cd = corner(sys.argv[1])
cb = corner(sys.argv[2])
if max(cd) < 80:
    sys.exit(f"默认模式背景应可见, 实际 {cd}")
if max(cb) > 12:
    sys.exit(f"-b 模式背景应置黑, 实际 {cb}")
if has_white(sys.argv[2]) < 10:
    sys.exit("-b 模式 (默认白色) 丢失运动高亮")
PY
then ok "默认保留背景; -b 置黑且保留高亮"; else no "-b 模式断言失败"; fi

echo "== -s 透层模式 (按运动强度透出原画面, 静止黑屏) =="
bash "$SCRIPT" -i "$TMP/testboxg.mp4" -o "$TMP/g_sil.mp4" -s >/dev/null 2>&1 \
  && ok "-s 模式执行成功" || no "-s 模式执行失败"
ffmpeg -v error -y -i "$TMP/g_sil.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/g_sil.raw"
if python3 - "$TMP/g_sil.raw" <<'PY'
import sys
W, H = 320, 240
d = open(sys.argv[1], 'rb').read()
n = len(d) // (W * H * 3)
if n != 50:
    sys.exit(f"帧数 {n} != 50")
fr = d[25 * W * H * 3:26 * W * H * 3]
def px(x, y):
    o = (y * W + x) * 3
    return fr[o], fr[o + 1], fr[o + 2]
c = px(5, 5)
if max(c) > 12:
    sys.exit(f"静止角落应黑屏, 实际 {c}")
# 运动方块区域应显示原样像素 (白色方块/绿色背景, 至少有些亮像素)
bright = sum(1 for x in range(W) for y in range(80, 140) if max(px(x, y)) > 120)
if bright < 10:
    sys.exit(f"运动区域未显示原样像素: {bright}")
PY
then ok "剪影模式: 静止黑屏且运动处原样显示"; else no "-s 模式断言失败"; fi

echo "== -k 参考帧距 / -d 时域降噪 =="
bash "$SCRIPT" -i "$TMP/testboxg.mp4" -o "$TMP/g_kd.mp4" -s -k 3 -d >/dev/null 2>&1 \
  && ok "-s -k 3 -d 执行成功" || no "-s -k 3 -d 执行失败"
if [[ -f "$TMP/g_kd.mp4" ]]; then
  n=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$TMP/g_kd.mp4")
  [[ "$n" == "50" ]] && ok "-k/-d 输出 50 帧" || no "-k/-d 输出帧数错误: $n"
fi
bash "$SCRIPT" -i "$TMP/testbox.mp4" -o "$TMP/hl_k.mp4" -k 4 >/dev/null 2>&1 \
  && ok "高亮模式 -k 4 执行成功" || no "高亮模式 -k 4 执行失败"

echo "== -x 去物/隐形模式 (运动物体被背景替换) =="
bash "$SCRIPT" -i "$TMP/testbox.mp4" -o "$TMP/x_rm.mp4" -x -n 51 >/dev/null 2>&1 \
  && ok "-x 执行成功" || no "-x 执行失败"
if [[ -f "$TMP/x_rm.mp4" ]]; then
  ffmpeg -v error -y -i "$TMP/x_rm.mp4" -pix_fmt rgb24 -f rawvideo "$TMP/x_rm.raw"
  if python3 - "$TMP/x_rm.raw" <<'PY'
import sys
W, H = 320, 240
d = open(sys.argv[1], 'rb').read()
n = len(d) // (W * H * 3)
if n != 50:
    sys.exit(f"帧数 {n} != 50")
fr = d[25 * W * H * 3:26 * W * H * 3]
def px(x, y):
    o = (y * W + x) * 3
    return fr[o], fr[o + 1], fr[o + 2]
if max(px(5, 5)) > 12:
    sys.exit(f"静态背景应保留黑, 实际 {px(5, 5)}")
if max(px(100, 110)) > 40:
    sys.exit(f"运动方块应被抹除, 实际 {px(100, 110)}")
PY
  then ok "去物: 静止背景保留且运动方块被背景替换"; else no "-x 去物断言失败"; fi
fi

echo "== 参数与错误处理 =="
bash "$SCRIPT" -h >/dev/null 2>&1 && ok "-h 退出码 0" || no "-h 退出码非 0"
bash "$SCRIPT" >/dev/null 2>&1 && no "缺 -i 应失败" || ok "缺 -i 正确失败"
bash "$SCRIPT" -i "$TMP/nope.mp4" >/dev/null 2>&1 && no "输入不存在应失败" || ok "输入不存在正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -t 999 >/dev/null 2>&1 && no "-t 999 应失败" || ok "-t 999 正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -g 0 >/dev/null 2>&1 && no "-g 0 应失败" || ok "-g 0 正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -c xyz >/dev/null 2>&1 && no "-c xyz 应失败" || ok "-c xyz 正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -k 0 >/dev/null 2>&1 && no "-k 0 应失败" || ok "-k 0 正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -x -n 4 >/dev/null 2>&1 && no "-n 4 (偶数) 应失败" || ok "-n 偶数正确失败"
bash "$SCRIPT" -i "$TMP/testbox.mp4" -x -n 1 >/dev/null 2>&1 && no "-n 1 应失败" || ok "-n 1 正确失败"

echo
echo "== 结果: $pass 通过, $fail 失败 =="
[[ "$fail" -eq 0 ]]
