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
# live or the lock is held. It holds the lock on an fd only around the Godot
# process (no shell string is built from user input) and samples the GPU
# outside it. Every user string is validated with a whole-string bash ERE so an
# embedded newline cannot reach a command line. The capture timeout scales with
# the selected pose count and --settle-seconds so a legal long settle is never
# killed by the 1800 s default.
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
# Validate with [[ =~ ]], not `grep -E '^...$'`: POSIX grep `$` matches before
# a newline, so `$'25\n<cmd>'` passes a line-anchored check and then reaches the
# executed command line. Bash [[ =~ ]] anchors ^$ to the whole string and the
# case guards reject CR/LF explicitly.
case "$TAG" in
  *$'\n'* | *$'\r'*) echo "ABORT: --tag must be a single line" >&2; exit 2 ;;
esac
if [ -n "$TAG" ] && ! [[ "$TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ABORT: --tag must be [A-Za-z0-9._-]+" >&2
  exit 2
fi
case "$SEED" in
  *$'\n'* | *$'\r'*) echo "ABORT: --seed must be a single line" >&2; exit 2 ;;
esac
if [ "$SEED" != "derived" ] && ! [[ "$SEED" =~ ^-?[0-9]+$ ]]; then
  echo "ABORT: --seed must be 'derived' or an integer" >&2
  exit 2
fi
# --poses must be a comma list of the same ids POSE_IDS declares in
# p0b_capture.gd; unknown or empty tokens abort before Godot is launched.
POSE_ALLOW=(gate upper_foyer yaw180 foyer_beam foyer_beam_wide lounge lounge_beam beam_close gap_view)
if [ -n "$POSES" ]; then
  case "$POSES" in
    *$'\n'* | *$'\r'*) echo "ABORT: --poses must be a single line" >&2; exit 2 ;;
  esac
  IFS=',' read -r -a _pose_tokens <<< "$POSES"
  for _p in "${_pose_tokens[@]}"; do
    _ok=0
    for _allowed in "${POSE_ALLOW[@]}"; do
      if [ "$_p" = "$_allowed" ]; then _ok=1; break; fi
    done
    if [ "$_ok" -ne 1 ]; then
      echo "ABORT: --poses unknown pose '$_p' (allowed: ${POSE_ALLOW[*]})" >&2
      exit 2
    fi
  done
fi
# --settle-seconds is 0 (off) or >=25 s; the AEM/A-B sessions use 25. Reject a
# small positive value rather than silently shortening the hold.
if [ -n "$SETTLE" ]; then
  case "$SETTLE" in
    *$'\n'* | *$'\r'*) echo "ABORT: --settle-seconds must be a single line" >&2; exit 2 ;;
    *[!0-9.]* | .* | *.*.*) echo "ABORT: --settle-seconds must be a plain non-negative number" >&2; exit 2 ;;
  esac
  if ! [[ "$SETTLE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
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

# Build an argv array; never interpolate a user string into a shell command.
ARGS=(--mode="$MODE" --beam-card="$BEAM" --seed="$SEED")
[ -n "$POSES" ] && ARGS+=(--poses="$POSES")
[ -n "$SETTLE" ] && ARGS+=(--settle-seconds="$SETTLE")
[ "$MODE" = "capture" ] && ARGS+=(--run-id="$(basename "$OUT")")
# Scale the outer timeout: a fixed 1800 s default would kill a legal long
# --settle-seconds hold (up to 3600 s per pose), so add pose_count * settle.
CAPTURE_TIMEOUT=1800
if [ -n "$SETTLE" ]; then
  _pose_n="${#POSE_ALLOW[@]}"
  if [ -n "$POSES" ]; then
    IFS=',' read -r -a _sel <<< "$POSES"
    _pose_n="${#_sel[@]}"
  fi
  _settle_i="$(awk -v s="$SETTLE" 'BEGIN { printf "%d", s }')"
  CAPTURE_TIMEOUT=$(( 1800 + _pose_n * _settle_i ))
fi
export P0B_OUT="$OUT"
export P0B_MANIFEST="$MANIFEST"
export TAT2_AO="$AO"
export TAT2_BEAM_CARD="$BEAM"

GPU_Q="name,driver_version,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"
if [ "$MODE" = "capture" ]; then
  nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_before" 2>&1
  START="$(date +%s)"
  exec 9>"$LOCK" || { echo "ABORT: cannot open $LOCK" >&2; exit 2; }
  flock 9
  (
    cd "$ROOT" || exit 3
    exec timeout "$CAPTURE_TIMEOUT" xvfb-run -a -s '-screen 0 1920x1080x24' \
      tools/godot --path game --rendering-driver vulkan \
      --script "$SCRIPT" -- "${ARGS[@]}"
  ) > "$TMPLOG" 2>&1
  ST=$?
  flock -u 9
  exec 9>&-
  mv -f "$TMPLOG" "$LOG"
  END="$(date +%s)"
  nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader > "$LOG.gpu_after" 2>&1
  echo "P0B_CAPTURE_WALL mode=$MODE run=$(basename "$OUT") beam=$BEAM ao=$AO exit=$ST wall=$((END - START))s timeout=${CAPTURE_TIMEOUT}s"
  echo "GPU before: $(cat "$LOG.gpu_before" 2>/dev/null)"
  echo "GPU after:  $(cat "$LOG.gpu_after" 2>/dev/null)"
else
  START="$(date +%s)"
  exec 9>"$LOCK" || { echo "ABORT: cannot open $LOCK" >&2; exit 2; }
  flock 9
  (
    cd "$ROOT" || exit 3
    exec timeout 600 tools/godot --headless --path game \
      --script "$SCRIPT" -- "${ARGS[@]}"
  ) > "$TMPLOG" 2>&1
  ST=$?
  flock -u 9
  exec 9>&-
  mv -f "$TMPLOG" "$LOG"
  END="$(date +%s)"
  echo "P0B_CAPTURE_WALL mode=$MODE exit=$ST wall=$((END - START))s (headless, no GPU)"
fi

echo "manifest: $MANIFEST"
echo "log:      $LOG"
grep -E "P0B_|AUDIO_CAPTURE|SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:" "$LOG" 2>/dev/null | tail -40
exit "$ST"
