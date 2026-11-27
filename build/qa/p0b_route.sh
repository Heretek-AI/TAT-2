#!/usr/bin/env bash
# P0b route runner v1 wrapper: one Godot at a time, Xvfb for the real Vulkan
# staging, the shared flock for every invocation, GPU samples around the run.
#
#   build/qa/p0b_route.sh --dry-run     # headless, no GPU render, tracked manifest
#   build/qa/p0b_route.sh --self-test   # headless table/schema checks
#   build/qa/p0b_route.sh               # real staged capture (owner GPU run)
#   build/qa/p0b_route.sh --tag=run2 --seed=1025051536
#
# Outputs
#   build/qa/p0b_route/<run>/<beat>_<frame>.png    (gitignored media)
#   docs/reports/logs/p0b-route/<run>/manifest.json (tracked provenance)
#   docs/reports/logs/p0b-route/<run>/capture.log   (tracked evidence)
#   docs/reports/logs/p0b-route/dry-run/manifest.json + dry-run.log   (tracked)
#   docs/reports/logs/p0b-route/self-test/self-test.log               (tracked)
#
# P0B_ROUTE_EVIDENCE_DIR overrides the evidence root for a later wave's own
# logs; the default stays docs/reports/logs/p0b-route and a real capture always
# writes there.
#
# Every mode exports TAT2_PARITY_ONLY=1 (expansion content excluded).
# The wrapper refuses to start a GPU run while another Godot/game process is
# live or the lock is held. It never holds the lock across the run itself: the
# `flock ... -c` invocation owns it for exactly the Godot process. This is a
# STAGED capture (route_claim=none), not a played route.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/build/qa/p0b_route.gd"
LOCK="/tmp/opencode/tat2-godot.lock"
EVIDENCE_DIR="${P0B_ROUTE_EVIDENCE_DIR:-$ROOT/docs/reports/logs/p0b-route}"
SEED="derived"
TAG=""
MODE="capture"

usage() {
	awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run) MODE="dry-run" ;;
	--self-test) MODE="self-test" ;;
	--seed=*) SEED="${1#*=}" ;;
	--seed)
		shift
		SEED="${1:-derived}"
		;;
	--tag=*) TAG="${1#*=}" ;;
	--tag)
		shift
		TAG="${1:-}"
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

if [ -n "$TAG" ] && ! printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9._-]+$'; then
	echo "ABORT: --tag must be [A-Za-z0-9._-]+" >&2
	exit 2
fi

mkdir -p "$(dirname "$LOCK")" || exit 2

if [ "$MODE" = "dry-run" ]; then
	OUT="$ROOT/build/qa/p0b_route/dry-run"
	MANIFEST="$EVIDENCE_DIR/dry-run/manifest.json"
	LOG="$EVIDENCE_DIR/dry-run/dry-run.log"
elif [ "$MODE" = "self-test" ]; then
	OUT="$ROOT/build/qa/p0b_route/selftest"
	MANIFEST="$ROOT/build/qa/p0b_route/selftest/manifest.json"
	LOG="$EVIDENCE_DIR/self-test/self-test.log"
else
	SHORT="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo nogit)"
	RUN="${TAG:-$(date -u +%Y%m%dT%H%M%SZ)_${SHORT}_staged}"
	OUT="$ROOT/build/qa/p0b_route/$RUN"
	MANIFEST="$EVIDENCE_DIR/$RUN/manifest.json"
	LOG="$EVIDENCE_DIR/$RUN/capture.log"
fi
mkdir -p "$(dirname "$LOG")" "$(dirname "$MANIFEST")" || exit 2
# Write the run log to a temp file and only replace the previous evidence once
# the run returns. A blocked `flock` waiter (another lane owns the Godot lock)
# therefore never truncates the previous log; a run killed mid-flight leaves
# its partial log behind via the EXIT trap.
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

ARGS="--mode=$MODE --seed=$SEED"
[ "$MODE" = "capture" ] && ARGS="$ARGS --run-id=$(basename "$OUT")"
export P0B_ROUTE_OUT="$OUT"
export P0B_ROUTE_MANIFEST="$MANIFEST"
# P0b governance: every mode runs parity-only so expansion content (prep
# skyline, TAT-2 overrides) cannot leak into a parity capture. The manifest
# env block records TAT2_PARITY_ONLY=1.
export TAT2_PARITY_ONLY=1

GPU_Q="name,driver_version,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"
if [ "$MODE" = "capture" ]; then
	nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader >"$LOG.gpu_before" 2>&1
	START="$(date +%s)"
	flock "$LOCK" -c \
		"cd '$ROOT' && timeout 1800 xvfb-run -a -s '-screen 0 1920x1080x24' \
     tools/godot --path game --rendering-driver vulkan \
     --script '$SCRIPT' -- $ARGS" \
		>"$TMPLOG" 2>&1
	ST=$?
	mv -f "$TMPLOG" "$LOG"
	END="$(date +%s)"
	nvidia-smi --query-gpu="$GPU_Q" --format=csv,noheader >"$LOG.gpu_after" 2>&1
	echo "P0B_ROUTE_WALL mode=$MODE run=$(basename "$OUT") exit=$ST wall=$((END - START))s"
	echo "GPU before: $(cat "$LOG.gpu_before" 2>/dev/null)"
	echo "GPU after:  $(cat "$LOG.gpu_after" 2>/dev/null)"
else
	START="$(date +%s)"
	flock "$LOCK" -c \
		"cd '$ROOT' && timeout 600 tools/godot --headless --path game \
     --script '$SCRIPT' -- $ARGS" \
		>"$TMPLOG" 2>&1
	ST=$?
	mv -f "$TMPLOG" "$LOG"
	END="$(date +%s)"
	echo "P0B_ROUTE_WALL mode=$MODE exit=$ST wall=$((END - START))s (headless, no GPU render)"
fi

echo "manifest: $MANIFEST"
echo "log:      $LOG"
grep -E "P0B_ROUTE_(DRY_RUN|SELFTEST|CAPTURE_DONE)|SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:" "$LOG" 2>/dev/null | tail -40
exit "$ST"
