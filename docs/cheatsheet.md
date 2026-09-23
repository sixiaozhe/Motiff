# Motiff Cheatsheet

Every option for both scripts. Run any script with `-h` for the same help text.

## `motion_highlight.sh`

Highlights motion in-place. Static pixels stay as the original frame; moving
pixels are tinted with the chosen color.

| Flag | Default | Description |
|---|---|---|
| `-i <file>` | — | Input video (**required**) |
| `-o <file>` | `<name>_highlight.<ext>` | Output path. `-x` changes default to `<name>_remove.<ext>` |
| `-b` | off | Drop the background: black out the original frame, keep only the highlight |
| `-s` | off | Silhouette / transparency: pixels with motion show the original frame, everything static goes black |
| `-x` | off | Erase / invisible mode: moving objects are replaced by a temporal-median background estimate |
| `-n <odd>` | `15` | Background-estimation window in frames for `-x` (≥3, odd). Larger = cleaner removal but more ghosting when the scene changes |
| `-e <sigma>` | `2` | Edge feathering (Gaussian sigma) for highlight/object edges. `0` = hard edges |
| `-d` | off | Temporal denoise (`atadenoise`) before differencing, suppresses noise flicker in low light |
| `-k <frames>` | `1` | Reference frame gap: compare against N frames back instead of the previous frame. `>1` fills in fast movers and reduces double edges |
| `-t <0-255>` | `15` | Difference threshold; below this is treated as noise |
| `-g <gain>` | `3` | Highlight gain (`>0`), higher = brighter |
| `-c <RRGGBB>` | `ffffff` | Highlight color, 6-digit hex |
| `-h` | — | Show help and exit |

### Examples

```bash
motion_highlight.sh -i in.mp4                       # white highlight over the scene
motion_highlight.sh -i in.mp4 -b                    # black background, white motion lines
motion_highlight.sh -i in.mp4 -b -c ff7319          # black background, orange
motion_highlight.sh -i in.mp4 -s                    # silhouette: only motion is visible
motion_highlight.sh -i in.mp4 -s -e 0               # strict binary, hard edges
motion_highlight.sh -i in.mp4 -s -e 4               # soft feathered edges
motion_highlight.sh -i in.mp4 -s -d                 # low light, denoise first
motion_highlight.sh -i in.mp4 -s -k 3               # compare with 3 frames back
motion_highlight.sh -i in.mp4 -x                    # erase moving objects
motion_highlight.sh -i in.mp4 -x -n 31 -t 25        # longer window, more thorough removal
```

## `motion_diff.sh`

Time-difference visualizer: negates a time-shifted copy of the frame, makes it
semi-transparent, and blends it back — motion becomes a colored ghost.

| Flag | Default | Description |
|---|---|---|
| `-i <file>` | — | Input video (**required**) |
| `-o <file>` | `<name>_motiondiff.<ext>` | Output path |
| `-n <frames>` | `3` | Frame offset. Positive = trail (blend N frames back); negative = leading (blend N frames ahead). Must not be `0` |
| `-a <0-1>` | `0.5` | Opacity of the inverted offset layer |
| `-h` | — | Show help and exit |

### Examples

```bash
motion_diff.sh -i in.mp4                            # 3-frame trail, opacity 0.5
motion_diff.sh -i in.mp4 -n -5 -a 0.4               # 5-frame leading ghost
motion_diff.sh -i in.mp4 -o out.mp4 -n 8            # 8-frame trail
```

## Recipes

**Traffic / crowd analysis** — reveal how many things are moving and where:

```bash
motion_highlight.sh -i street.mp4 -b -c 00e5ff -t 20 -g 4
```

**Remove a photobomber or passing car** — replace movers with the background:

```bash
motion_highlight.sh -i clip.mp4 -x -n 31 -e 3
```

**Motion study / sports** — glowing silhouettes on black:

```bash
motion_highlight.sh -i run.mp4 -s -e 1 -k 3
```

**Music-video style trails**:

```bash
motion_diff.sh -i dance.mp4 -n 6 -a 0.35
```

## Notes

- Output is H.264 (`libx264`, CRF 18) with `+faststart`; audio is stream-copied.
- All math runs on even-padded RGB frames, then converts back to `yuv420p` for
  maximum player compatibility.
- Larger `-n` (background window) and `-k` (frame gap) cost more memory and time.
