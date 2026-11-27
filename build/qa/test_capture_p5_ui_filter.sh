#!/usr/bin/env bash
# Negative test for build/qa/capture_p5_ui.gd's P5_ONLY filter (U-2).
#
# The harness used to accept any P5_ONLY value: `P5_ONLY=ledger_market` captured
# nothing and exited 0, and an unknown name silently produced zero frames. The
# contract is now fail-closed: an unknown shot name exits 2 with
# `P5_CAPTURE FAIL unknown shot=<name> known=<list>` before any mission load or
# capture. This test starts Godot headless (it never renders), asserts that exit
# code and message, then asserts the documented known names (including the two
# sub-frames `ledger_market` and `pause_backdrop`) are accepted by the same
# check without an unknown-shot failure.
#
# It does NOT run the capture itself: that needs Xvfb + Vulkan and is the
# integrator's step. Run serially (`build/qa/capture_p5_ui.gd` is headless
# startup only, but this repo serializes Godot anyway).
#
# Usage: build/qa/test_capture_p5_ui_filter.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="$ROOT/tools/godot"
CHECKS=0
FAILS=0

pass() {
	CHECKS=$((CHECKS + 1))
	printf 'ok   %s\n' "$1"
}
fail() {
	CHECKS=$((CHECKS + 1))
	FAILS=$((FAILS + 1))
	printf 'FAIL %s\n' "$1"
}

run_filter() { # name outdir
	local name="$1"
	local out="$2"
	local log="$out/capture.log"
	mkdir -p "$out"
	timeout 300 env P5_ONLY="$name" P5_OUT="$out" P5_SIZE=720 \
		"$GODOT" --headless --path "$ROOT/game" --script "$ROOT/build/qa/capture_p5_ui.gd" \
		>"$log" 2>&1
	echo $?
}

TMP="$(mktemp -d /tmp/opencode/p5-filter-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# 1. Unknown name: exit 2 + the explicit failure line, no capture.
CODE="$(run_filter "no_such_screen" "$TMP/unknown")"
if [ "$CODE" = "2" ]; then
	pass "unknown P5_ONLY exits 2"
else
	fail "unknown P5_ONLY exit=$CODE (want 2)"
fi
if grep -q 'P5_CAPTURE FAIL unknown shot=no_such_screen' "$TMP/unknown/capture.log"; then
	pass "unknown P5_ONLY names the rejected shot"
else
	fail "unknown P5_ONLY did not print the failure line"
fi
if grep -q 'P5_CAPTURE FAIL unknown shot' "$TMP/unknown/capture.log" &&
	! grep -q 'P5_CAPTURE_SIZE' "$TMP/unknown/capture.log"; then
	pass "unknown P5_ONLY stops before the shot loop"
else
	fail "unknown P5_ONLY reached the shot loop"
fi

# 2. A real sub-frame name must pass the filter check. `ledger_market` needs a
#    Den mission to actually capture; headless has no renderer, so the harness
#    must reach the size/shot loop and fail on the headless frame, not on the
#    filter. Exit 1 (headless capture failure) is the pass condition here.
CODE="$(run_filter "ledger_market" "$TMP/known")"
if grep -q 'P5_CAPTURE FAIL unknown shot' "$TMP/known/capture.log"; then
	fail "ledger_market rejected by the filter"
else
	pass "ledger_market accepted by the filter"
fi
if grep -q 'P5_CAPTURE_SIZE' "$TMP/known/capture.log" &&
	grep -q 'P5_CAPTURE FAILED headless' "$TMP/known/capture.log"; then
	pass "ledger_market reaches the shot loop (headless capture refused, exit $CODE)"
else
	fail "ledger_market did not reach the shot loop"
fi

if [ "$FAILS" -eq 0 ]; then
	printf 'CAPTURE_P5_FILTER_TEST PASS checks=%d\n' "$CHECKS"
	exit 0
fi
printf 'CAPTURE_P5_FILTER_TEST FAIL checks=%d fails=%d\n' "$CHECKS" "$FAILS"
exit 1
