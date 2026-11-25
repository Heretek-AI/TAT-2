#!/usr/bin/env bash
# W9-P0 perf-matrix wrapper: one Godot at a time under the shared flock.
#
#   TAT2_AO=on build/qa/w9_perf.sh ao_on
#
# Display policy: the host compositor by default, because Xvfb adds ~25 ms per
# frame at 720p (build/qa/run_perf_matrix.sh header) and would swamp the AO
# delta. Set W9_PERF_XVFB=1 to force a virtual display instead. Vsync is
# disabled inside the runner.
#
# Records wall time, CPU package temperature and nvidia-smi before/after next
# to the log. Never writes outside the worktree it lives in.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAG="${1:?usage: [TAT2_AO=on|off] w9_perf.sh <tag> [WxH] [frames] [warmup]}"
SIZE="${2:-1920x1080}"
FRAMES="${3:-240}"
WARMUP="${4:-60}"
AO="${TAT2_AO:-on}"

LOGS="$ROOT/build/qa/w9/logs"
mkdir -p "$LOGS"
LOG="$LOGS/perf_${TAG}.log"
GPU_Q="name,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"
CPU_TEMP="$(sensors -u 2>/dev/null | awk '/Package id 0:/{f=1;next} f&&/temp1_input/{printf "%d",$2;exit}')"

if pgrep -f "[t]at2-linux-x86_64" >/dev/null || pgrep -f "[G]odot_v4" >/dev/null || pgrep -f "[f]latpak run org.godotengine" >/dev/null; then
  echo "ABORT: concurrent Godot/game process detected" >&2
  exit 2
fi

nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_before" 2>&1
START="$(date +%s)"
export TAT2_AO="$AO"
if [ "${W9_PERF_XVFB:-0}" = "1" ]; then
  LAUNCH="xvfb-run -a -s '-screen 0 1920x1080x24'"
else
  LAUNCH=""
fi

flock /tmp/opencode/tat2-godot.lock -c \
  "cd '$ROOT' && $LAUNCH timeout 1800 tools/godot --path game --rendering-driver vulkan \
   --script '$ROOT/build/qa/w9_perf.gd' -- --tag=$TAG --size=$SIZE --frames=$FRAMES --warmup=$WARMUP" \
  > "$LOG" 2>&1
ST=$?
END="$(date +%s)"
CPU_AFTER="$(sensors -u 2>/dev/null | awk '/Package id 0:/{f=1;next} f&&/temp1_input/{printf "%d",$2;exit}')"
nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_after" 2>&1

echo "W9_PERF_WALL tag=$TAG ao=$AO exit=$ST wall=$((END - START))s cpu_before=${CPU_TEMP}C cpu_after=${CPU_AFTER}C"
echo "GPU before: $(cat "$LOG.gpu_before")"
echo "GPU after:  $(cat "$LOG.gpu_after")"
grep -E "W9_PERF|SCRIPT ERROR|SHADER ERROR|Vulkan|Godot Engine" "$LOG" | tail -20
exit "$ST"
