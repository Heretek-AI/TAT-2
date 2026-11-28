#!/usr/bin/env bash
# P0b Lane I capture wrapper: one Godot at a time, Xvfb for the real Vulkan
# capture, the shared flock for every invocation, GPU samples around the run.
#
#   build/qa/p0b_capture.sh                        # all poses, Vulkan
#   build/qa/p0b_capture.sh --beam-card=off        # TAT2_BEAM_CARD A/B run
#   build/qa/p0b_capture.sh --poses=lounge_beam,beam_close
#   build/qa/p0b_capture.sh --settle-seconds=25    # extra >=25 s hold after the frames
#   build/qa/p0b_capture.sh --tag=run2 --seed=1025051536
#   build/qa/p0b_capture.sh --dry-run              # headless, no GPU, tracked manifest
#   build/qa/p0b_capture.sh --self-test            # headless checks only
#
# Outputs
#   build/qa/p0b/captures/<run>/<pose>.png         (gitignored; + audio WAV/PCM/JSON)
#   docs/reports/logs/p0b/<run>/manifest.json      (tracked provenance)
#   docs/reports/logs/p0b/<run>/capture.log        (tracked evidence; dry-run/self-test logs too)
#
# P0B_EVIDENCE_DIR overrides the evidence root for the headless dry-run/self-test
# only (a later wave records its own logs without rewriting the P0b evidence);
# the default stays docs/reports/logs/p0b and a real capture always writes there.
#
# The wrapper refuses to start a GPU run while another Godot/game process is
# live or the lock is held. It never holds the lock across the run itself: the
# `flock ... -c` invocation owns it for exactly the Godot process.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/build/qa/p0b_capture.gd"
LOCK="/tmp/opencode/tat2-godot.lock"
EVIDENCE_DIR="${P0B_EVIDENCE_DIR:-$ROOT/docs/reports/logs/p0b}"
BEAM="on"
AO="${TAT2_AO:-on}"
SEED="derived"
POSES=""
TAG=""
SETTLE=""
MODE="capture"

usage() {
  awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --self-test) MODE="self-test" ;;
    --beam-card=*) BEAM="${1#*=}" ;;
    --beam-card) shift; BEAM="${1:-on}" ;;
    --ao=*) AO="${1#*=}" ;;
    --ao) shift; AO="${1:-on}" ;;
    --seed=*) SEED="${1#*=}" ;;
    --seed) shift; SEED="${1:-derived}" ;;
    --poses=*) POSES="${1#*=}" ;;
    --poses) shift; POSES="${1:-}" ;;
    --tag=*) TAG="${1#*=}" ;;
    --tag) shift; TAG="${1:-}" ;;
    --settle-seconds=*) SETTLE="${1#*=}" ;;
    --settle-seconds) shift; SETTLE="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$BEAM" in on|off) ;; *) echo "ABORT: --beam-card=$BEAM (on|off)" >&2; exit 2 ;; esac
case "$AO" in on|off) ;; *) echo "ABORT: --ao=$AO (on|off)" >&2; exit 2 ;; esac
if [ -n "$TAG" ] && ! printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9._-]+$'; then
  echo "ABORT: --tag must be [A-Za-z0-9._-]+" >&2
  exit 2
fi
# --settle-seconds is 0 (off) or >=25 s; the AEM/A-B sessions use 25. Reject a
# small positive value rather than silently shortening the hold.
if [ -n "$SETTLE" ]; then
  if ! printf '%s' "$SETTLE" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
    echo "ABORT: --settle-seconds must be a non-negative number" >&2
    exit 2
  fi
  if awk -v s="$SETTLE" 'BEGIN { exit !((s + 0) > 0 && (s + 0) < 25) }'; then
    echo "ABORT: --settle-seconds=$SETTLE is below the 25 s minimum (omit for 0)" >&2
    exit 2
  fi
fi

mkdir -p "$(dirname "$LOCK")" || exit 2

if [ "$MODE" = "dry-run" ]; then
  OUT="$ROOT/build/qa/p0b/dry-run"
  MANIFEST="$EVIDENCE_DIR/dry-run/manifest.json"
  LOG="$EVIDENCE_DIR/dry-run/dry-run.log"
elif [ "$MODE" = "self-test" ]; then
  OUT="$ROOT/build/qa/p0b/selftest"
  MANIFEST="$ROOT/build/qa/p0b/selftest/manifest.json"
  LOG="$EVIDENCE_DIR/self-test/self-test.log"
else
  SHORT="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo nogit)"
  RUN="${TAG:-$(date -u +%Y%m%dT%H%M%SZ)_${SHORT}_b${BEAM}}"
  if [ "$BEAM" = "off" ] && [ "${RUN%_nobeam}" = "$RUN" ]; then
    RUN="${RUN}_nobeam"
  fi
  OUT="$ROOT/build/qa/p0b/captures/$RUN"
  MANIFEST="$ROOT/docs/reports/logs/p0b/$RUN/manifest.json"
  LOG="$ROOT/docs/reports/logs/p0b/$RUN/capture.log"
fi
mkdir -p "$(dirname "$LOG")" "$(dirname "$MANIFEST")" || exit 2
# Write the run log to a temp file and only replace the previous evidence once
# the run returns. A blocked `flock` waiter (another lane owns the Godot lock)
# therefore never truncates the previous capture log; a run killed mid-flight
# leaves its partial log behind via the EXIT trap.
TMPLOG="$LOG.tmp"
trap 'if [ -s "$TMPLOG" ]; then mv -f "$TMPLOG" "$LOG"; fi' EXIT

if [ "$MODE" = "capture" ]; then
  if ! command -v xvfb-run >/dev/null 2>&1; then
    echo "ABORT: xvfb-run is required for the Vulkan capture" >&2
    exit 2
  fi
  if pgrep -f "[t]at2-linux-x86_64" >/dev/null || pgrep -f "[G]odot_v4" >/dev/null || pgrep -f "[f]latpak run org.godotengine" >/dev/null; then
    echo "ABORT: concurrent Godot/game process detected" >&2
    exit 2
  fi
  if ! flock -n "$LOCK" true; then
    echo "ABORT: $LOCK is held (another lane is running Godot)" >&2
    exit 2
  fi
fi

ARGS="--mode=$MODE --beam-card=$BEAM --seed=$SEED"
[ -n "$POSES" ] && ARGS="$ARGS --poses=$POSES"
[ -n "$SETTLE" ] && ARGS="$ARGS --settle-seconds=$SETTLE"
[ "$MODE" = "capture" ] && ARGS="$ARGS --run-id=$(basename "$OUT")"
export P0B_OUT="$OUT"
export P0B_MANIFEST="$MANIFEST"
export TAT2_AO="$AO"
export TAT2_BEAM_CARD="$BEAM"

GPU_Q="name,driver_version,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"
if [ "$MODE" = "capture" ]; then
  nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_before" 2>&1
  START="$(date +%s)"
  flock "$LOCK" -c \
    "cd '$ROOT' && timeout 1800 xvfb-run -a -s '-screen 0 1920x1080x24' \
     tools/godot --path game --rendering-driver vulkan \
     --script '$SCRIPT' -- $ARGS" \
    > "$TMPLOG" 2>&1
  ST=$?
  mv -f "$TMPLOG" "$LOG"
  END="$(date +%s)"
  nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_after" 2>&1
  echo "P0B_CAPTURE_WALL mode=$MODE run=$(basename "$OUT") beam=$BEAM ao=$AO exit=$ST wall=$((END - START))s"
  echo "GPU before: $(cat "$LOG.gpu_before" 2>/dev/null)"
  echo "GPU after:  $(cat "$LOG.gpu_after" 2>/dev/null)"
else
  START="$(date +%s)"
  flock "$LOCK" -c \
    "cd '$ROOT' && timeout 600 tools/godot --headless --path game \
     --script '$SCRIPT' -- $ARGS" \
    > "$TMPLOG" 2>&1
  ST=$?
  mv -f "$TMPLOG" "$LOG"
  END="$(date +%s)"
  echo "P0B_CAPTURE_WALL mode=$MODE exit=$ST wall=$((END - START))s (headless, no GPU)"
fi

echo "manifest: $MANIFEST"
echo "log:      $LOG"
grep -E "P0B_|AUDIO_CAPTURE|SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:" "$LOG" 2>/dev/null | tail -40
exit "$ST"
