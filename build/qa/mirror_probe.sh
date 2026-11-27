#!/usr/bin/env bash
# P4.2 synthetic mirror probe wrapper.
#
#   build/qa/mirror_probe.sh                 # headless self-test (no GPU)
#   build/qa/mirror_probe.sh --selftest      # same
#   build/qa/mirror_probe.sh --run --tag=t1  # Vulkan/Xvfb readback (integrator)
#
# The self-test needs no renderer and is the lane gate. `--run` is the
# integrator's GPU measurement (one Godot at a time, shared flock); it writes
# build/qa/mirror_probe/<tag>.png + <tag>.log, both gitignored.
#
# Exit contract (`--run`): 0 only when `MIRROR_PROBE RESULT ... pass=1`.
# `pass=1` requires control_ok, the baked identity+mirror terms, single_baked,
# the CULL_FRONT terms unless TAT2_MIRROR_FAST=off, and native_single unless
# TAT2_MIRROR_SINGLE=baked. The wrapper also greps the RESULT flag, so a stray
# exit 0 cannot be read as a pass.
#
# The readback answers two questions:
#   * does a negative-scale MultiMesh instance render its front face?
#   * does the port's baked variant / CULL_FRONT fast path render it instead?
# The negative control (`control_front`, CULL_FRONT on a positive instance) must
# be black; otherwise the readback is not measuring culling.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/build/qa/mirror_probe.gd"
OUT="$ROOT/build/qa/mirror_probe"
LOCK="/tmp/opencode/tat2-godot.lock"
TAG="$(date -u +%Y%m%dT%H%M%SZ)"
MODE="selftest"

while [ $# -gt 0 ]; do
	case "$1" in
	--run) MODE="run" ;;
	--selftest | --dry-run) MODE="selftest" ;;
	--tag=*) TAG="${1#*=}" ;;
	--tag)
		shift
		TAG="${1:-probe}"
		;;
	-h | --help)
		awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
		exit 0
		;;
	*)
		echo "unknown argument: $1" >&2
		exit 2
		;;
	esac
	shift
done

if ! printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9._-]+$'; then
	echo "ABORT: --tag must be [A-Za-z0-9._-]+" >&2
	exit 2
fi

mkdir -p "$OUT" "$(dirname "$LOCK")" || exit 2

if [ "$MODE" = "selftest" ]; then
	# Scene construction + bake/fast-path assertions only; no renderer needed.
	timeout 300 "$ROOT/tools/godot" --headless --audio-driver Dummy \
		--path "$ROOT/game" --script "$SCRIPT" -- --selftest --tag="$TAG" 2>&1 |
		tee "$OUT/${TAG}_selftest.log"
	status=${PIPESTATUS[0]}
	if grep -q "MIRROR_PROBE_SELFTEST PASS" "$OUT/${TAG}_selftest.log"; then
		exit 0
	fi
	echo "ABORT: self-test did not print PASS (exit=$status)" >&2
	exit 1
fi

# ----- GPU run (integrator) --------------------------------------------------
if ! command -v xvfb-run >/dev/null 2>&1; then
	echo "ABORT: xvfb-run is required for the Vulkan readback" >&2
	exit 2
fi
if command -v pgrep >/dev/null 2>&1; then
	live="$(pgrep -af 'Godot_v4\.7\.2|godot.*--path' | grep -v "mirror_probe" || true)"
	if [ -n "$live" ]; then
		echo "ABORT: another Godot process is live; one GPU run at a time:" >&2
		echo "$live" >&2
		exit 2
	fi
fi

LOG="$OUT/${TAG}.log"
echo "GPU command: xvfb-run -a ... tools/godot --path game --rendering-driver vulkan --script build/qa/mirror_probe.gd -- --run --tag=$TAG"
echo "log: $LOG"
echo "png: $OUT/$TAG.png"
# The flock is held only for the Godot process, never for the shell.
(
	set -o pipefail
	flock -w 120 -x "$LOCK" xvfb-run -a -s "-screen 0 1280x720x24" \
		env -u WAYLAND_DISPLAY -u XAUTHORITY \
		"$ROOT/tools/godot" --path "$ROOT/game" --rendering-driver vulkan \
		--script "$SCRIPT" -- --run --tag="$TAG" 2>&1 | tee "$LOG"
)
status=$?
echo "exit=$status"
grep -E "MIRROR_PROBE " "$LOG" || true
# Gate on both: the probe exits non-zero on a bad term, and the wrapper also
# requires the machine-readable RESULT pass flag so an unexpected exit 0 can
# never be read as a pass.
if [ "$status" -eq 0 ] && ! grep -q "MIRROR_PROBE RESULT .*pass=1" "$LOG"; then
	echo "ABORT: probe exited 0 without MIRROR_PROBE RESULT ... pass=1" >&2
	status=1
fi
if [ "$status" -ne 0 ]; then
	echo "ABORT: mirror probe failed (negative control, a port term, or renderer); see $LOG" >&2
fi
exit "$status"
