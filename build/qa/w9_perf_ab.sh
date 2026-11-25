#!/usr/bin/env bash
# W9-P2 B0 collision A/B wrapper: one Godot at a time, one process per mode.
#
#   TAT2_COLLISION=authored build/qa/w9_perf_ab.sh authored 1920x1080 240 60
#   TAT2_COLLISION=aabb     build/qa/w9_perf_ab.sh aabb     1920x1080 240 60
#
# Prints load_ms, the loader's LoadTiming phases, per-pose FPS p50/p95/p99 and
# the collision census. Host compositor by default (Xvfb adds ~25 ms/frame at
# 720p and would swamp a small delta); W9_PERF_XVFB=1 forces a virtual display.
# Never writes outside the worktree it lives in.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:?usage: w9_perf_ab.sh <authored|aabb> [WxH] [frames] [warmup]}"
SIZE="${2:-1920x1080}"
FRAMES="${3:-240}"
WARMUP="${4:-60}"
AO="${TAT2_AO:-on}"
COLL="${TAT2_COLLISION:-$MODE}"

LOGS="$ROOT/build/qa/w9/logs"
mkdir -p "$LOGS"
LOG="$LOGS/perf_ab_${MODE}.log"
GPU_Q="name,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"
CPU_TEMP="$(sensors -u 2>/dev/null | awk '/Package id 0:/{f=1;next} f&&/temp1_input/{printf "%d",$2;exit}')"

if pgrep -f "[t]at2-linux-x86_64" >/dev/null || pgrep -f "[G]odot_v4" >/dev/null || pgrep -f "[f]latpak run org.godotengine" >/dev/null; then
  echo "ABORT: concurrent Godot/game process detected" >&2
  exit 2
fi

nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_before" 2>&1
START="$(date +%s)"
export TAT2_AO="$AO"
export TAT2_COLLISION="$COLL"
export TAT_LOAD_TIMING=1
if [ "${W9_PERF_XVFB:-0}" = "1" ]; then
  LAUNCH="xvfb-run -a -s '-screen 0 1920x1080x24'"
else
  LAUNCH=""
fi

flock /tmp/opencode/tat2-godot.lock -c \
  "cd '$ROOT' && $LAUNCH timeout 1800 tools/godot --path game --rendering-driver vulkan \
   --script '$ROOT/build/qa/w9_perf_ab.gd' -- --tag=ab_$MODE --mode=$MODE --size=$SIZE --frames=$FRAMES --warmup=$WARMUP" \
  > "$LOG" 2>&1
ST=$?
END=$(date +%s)
CPU_AFTER="$(sensors -u 2>/dev/null | awk '/Package id 0:/{f=1;next} f&&/temp1_input/{printf "%d",$2;exit}')"
nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_after" 2>&1

echo "W9_PERF_AB_WALL mode=$MODE collision=$COLL ao=$AO exit=$ST wall=$((END - START))s cpu_before=${CPU_TEMP}C cpu_after=${CPU_AFTER}C"
echo "GPU before: $(cat "$LOG.gpu_before")"
echo "GPU after:  $(cat "$LOG.gpu_after")"
grep -E "W9_PERF_AB|W9_LOAD|W9_PERF |LoadTiming|AUTHORED_COLLISION|SCRIPT ERROR|SHADER ERROR" "$LOG" | tail -40
exit "$ST"
