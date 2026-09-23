# 视频运动时间差分可视化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供 `motion_diff.sh`，将视频反色、半透明、按 N 帧时间偏移后叠加回原视频，生成时间差分运动可视化。

**Architecture:** 单个 bash 脚本封装 ffmpeg 滤镜链：`split` 成两路，一路 `negate` + 帧级时移（`tpad`/`trim`），再与原图用 `blend=all_expr` 按 alpha 合成。全部在 RGB（`gbrp`）空间做，保证“反色”是真正的 RGB 反相。时移完全基于帧数，无需帧率计算。

**Tech Stack:** bash、ffmpeg（需 `negate`/`blend`/`tpad`/`trim` 滤镜）、python3（仅测试脚本读取原始像素做断言）。

**关键事实（已实测验证）:**
- `blend` 中 `A`=第一路输入(base)，`B`=第二路(fx)；`all_expr='A*(1-a)+B*a'`。
- `eof_action=endall` 让输出长度取两路较短者，避免拖尾方向多出 N 帧。
- `tpad=start=N:start_mode=clone` 将输入延迟 N 帧（拖尾）。
- `trim=start_frame=N,setpts=PTS-STARTPTS,tpad=stop=N:stop_mode=clone` 将输入提前 N 帧（前导）。
- ffmpeg 4.4.2 已具备以上全部能力；`getopts` 可接收 `-n -3`。

---

### Task 1: 脚本骨架与参数校验

**Files:**
- Create: `motion_diff.sh`

- [ ] **Step 1: 写参数解析、校验、用法**

接受 `-i/-o/-n/-a/-h`，校验：输入必填且存在、`-n` 为整数且非 0、`-a` 在 `[0,1]`、`ffmpeg` 存在。默认输出 `<输入名>_motiondiff.<原扩展名>`（无扩展名则 `.mp4`）。

### Task 2: 滤镜链与时移

**Files:**
- Modify: `motion_diff.sh`

- [ ] **Step 1: 拖尾 (N>0)**

`SHIFT="tpad=start=${N}:start_mode=clone"`

- [ ] **Step 2: 前导 (N<0)**

`SHIFT="trim=start_frame=${ABS_N},setpts=PTS-STARTPTS,tpad=stop=${ABS_N}:stop_mode=clone"`

- [ ] **Step 3: 完整 ffmpeg 调用**

```
[0:v]scale=trunc(iw/2)*2:trunc(ih/2)*2,format=gbrp,split=2[base][fx];
[fx]negate,${SHIFT}[fx2];
[base][fx2]blend=all_expr='A*(1-${ALPHA})+B*${ALPHA}':eof_action=endall,format=yuv420p[v]
```
映射 `[v]` 与 `0:a?`（`-c:a copy`），输出 `libx264 -pix_fmt yuv420p`。

### Task 3: 测试脚本

**Files:**
- Create: `tests/run_tests.sh`

- [ ] **Step 1: 生成运动测试视频**

`overlay` 移动白色方块（320x240,25fps,2s,50 帧）。

- [ ] **Step 2: 断言**

- 拖尾 `-n 5`：黑色带在运动后方（左侧），白色带在右侧。
- 前导 `-n -5`：白色带在左侧，黑色带在运动前方（右侧）。
- 任一方向输出恰好 50 帧。
- `-h` 退出码 0；缺失输入 / `-n 0` / `-a 2` 退出码非 0。

- [ ] **Step 3: 运行全部测试**

Run: `bash tests/run_tests.sh`
Expected: 所有断言 PASS。

---

## Self-Review

- 覆盖 spec：接口、双向时移、alpha、音频保留、错误处理、测试方案均有对应任务。
- 无占位符；命令与代码为实际可运行内容。
- 命名一致：`motion_diff.sh`、`-n/-a/-i/-o/-h` 全程一致。
- 与 spec 的偏差：时移由“ffprobe 帧率换算”改为“帧级 `tpad`/`trim`”，更简单稳健，已同步更新 spec；依赖因此仅剩 ffmpeg（ffprobe 不再需要）。
