#!/usr/bin/env bash
# W9-P0 capture wrapper: one Godot at a time, Xvfb, the shared flock, and
# nvidia-smi + wall time recorded around the run.
#
#   build/qa/w9_capture.sh <prep|upper_foyer|foyer|saferoom> [tag] [WxH]
#
# TAT2_AO=on|off is passed through to the game (see weather_profile.gd:341).
# PNG output goes to build/qa/w9/captures (gitignored); the log and the two
# GPU samples go to build/qa/w9/logs. This script never writes outside the
# worktree it lives in.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:?usage: w9_capture.sh <prep|upper_foyer|foyer|saferoom> [tag] [WxH]}"
TAG="${2:-$MODE}"
SIZE="${3:-1920x1080}"
AO="${TAT2_AO:-on}"

OUT="$ROOT/build/qa/w9/captures"
LOGS="$ROOT/build/qa/w9/logs"
mkdir -p "$OUT" "$LOGS"
LOG="$LOGS/cap_${TAG}.log"
GPU_Q="name,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"

# Fail closed on a concurrent game: the lock serialises the Godot calls, but a
# process already running outside the lock means the GPU is busy.
if pgrep -f "[t]at2-linux-x86_64" >/dev/null || pgrep -f "[G]odot_v4" >/dev/null || pgrep -f "[f]latpak run org.godotengine" >/dev/null; then
  echo "ABORT: concurrent Godot/game process detected" >&2
  exit 2
fi

nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_before" 2>&1
START="$(date +%s)"
export TAT2_AO="$AO"
export W9_QA_OUT="$OUT"

flock /tmp/opencode/tat2-godot.lock -c \
  "cd '$ROOT' && timeout 1800 xvfb-run -a -s '-screen 0 1920x1080x24' \
   tools/godot --path game --rendering-driver vulkan \
   --script '$ROOT/build/qa/w9_capture.gd' -- --mode=$MODE --tag=$TAG --size=$SIZE" \
  > "$LOG" 2>&1
ST=$?
END="$(date +%s)"
nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_after" 2>&1

echo "W9_CAPTURE_WALL mode=$MODE tag=$TAG ao=$AO exit=$ST wall=$((END - START))s"
echo "GPU before: $(cat "$LOG.gpu_before")"
echo "GPU after:  $(cat "$LOG.gpu_after")"
grep -E "W9_CAPTURE|W9_STAGE|W9_ENV|SCRIPT ERROR|SHADER ERROR|Vulkan|Godot Engine" "$LOG" | tail -20
exit "$ST"
