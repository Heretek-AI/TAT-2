#!/usr/bin/env bash
# Static/decision test for the perf-matrix thermal guard (W4P).
#
# Starts no game and touches no GPU: `--guard-check=<C>` runs the exact
# `thermal_decision()` the wrapper uses before a sustained run, on a synthetic
# reading, and exits 0 (would run) / 8 (would refuse). Argument validation is
# exercised the same way (exit 2). Static greps then assert the guard machinery
# (1 s sampler, VmHWM, memory scope, pre-warm coverage) is present in the
# wrapper, so deleting it fails this test even on a host with no sensors.
#
# Usage: build/qa/test_perf_guard.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/run_perf_matrix.sh"
CHECKS=0
FAILS=0

pass() { CHECKS=$((CHECKS + 1)); printf 'ok   %s\n' "$1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$1"; }

expect_code() { # want desc args...
  local want="$1" desc="$2" out got
  shift 2
  out="$("$WRAPPER" "$@" 2>&1)"
  got=$?
  if [ "$got" = "$want" ]; then
    pass "$desc (exit $got)"
  else
    fail "$desc (want $want, got $got): $(printf '%s' "$out" | tail -3)"
  fi
}

expect_contains() { # file/text desc pattern
  local text="$1" desc="$2" pat="$3"
  if printf '%s' "$text" | grep -q -- "$pat"; then
    pass "$desc"
  else
    fail "$desc (missing: $pat)"
  fi
}

expect_grep() { # desc pattern
  if grep -qF -- "$2" "$WRAPPER"; then pass "$1"; else fail "$1 (missing: $2)"; fi
}

echo "== bash -n =="
if bash -n "$WRAPPER"; then pass "run_perf_matrix.sh parses"; else fail "run_perf_matrix.sh does not parse"; fi
if bash -n "$HERE/test_perf_guard.sh"; then pass "test_perf_guard.sh parses"; else fail "test_perf_guard.sh does not parse"; fi

echo "== temperature decision (defaults start=78 max=95) =="
OUT="$("$WRAPPER" --guard-check=77 2>&1)"; CODE=$?
[ "$CODE" = 0 ] && pass "77 C starts" || fail "77 C should start (got $CODE)"
expect_contains "$OUT" "guard-check reports the defaults" "start_max=78 max=95"
expect_contains "$OUT" "guard-check reports ok" "decision=ok"
expect_code 0 "78 C == --start-temp starts" --guard-check=78
expect_code 8 "79 C > --start-temp is refused"
expect_code 8 "94 C (hot idle, below max) is refused"
expect_code 8 "95 C == --max-temp is refused"
expect_code 8 "unknown temperature is refused (fail closed)" '--guard-check=?'
expect_code 8 "non-numeric temperature is refused" --guard-check=abc

echo "== explicit start/max headroom =="
expect_code 0 "start 90 / max 95, 90 C starts" --start-temp=90 --max-temp=95 --guard-check=90
expect_code 8 "start 90 / max 95, 91 C is refused" --start-temp=90 --max-temp=95 --guard-check=91
expect_code 8 "start 90 / max 95, 95 C is refused" --start-temp=90 --max-temp=95 --guard-check=95

echo "== argument validation =="
expect_code 2 "--start-temp below 60" --start-temp=59
expect_code 2 "--start-temp above 105" --start-temp=106
expect_code 2 "--max-temp above 105" --max-temp=106
expect_code 2 "--max-temp below 60" --max-temp=59
expect_code 2 "zero headroom (start == max)" --start-temp=95 --max-temp=95
expect_code 2 "inverted headroom (start > max)" --start-temp=96 --max-temp=95
expect_code 2 "non-numeric --max-rss-mb" --max-rss-mb=abc
expect_code 2 "--max-rss-mb below 256" --max-rss-mb=64
expect_code 2 "--sample-sec 0" --sample-sec=0
expect_code 2 "--sample-sec above 60" --sample-sec=61

echo "== guard machinery in the wrapper =="
expect_grep "start-temp default is 78" 'START_TEMP="${PERF_START_TEMP:-78}"'
expect_grep "max-temp default is 95" 'MAX_TEMP="${PERF_MAX_TEMP:-95}"'
expect_grep "RSS cap default is 8192 MB" 'MAX_RSS_MB="${PERF_MAX_RSS_MB:-8192}"'
expect_grep "sampler cadence default is 1 s" 'SAMPLE_SEC="${PERF_THERMAL_SAMPLE_SEC:-1}"'
expect_grep "sampler logs PERF_THERMAL_SAMPLE" 'PERF_THERMAL_SAMPLE phase='
expect_grep "pre-warm peak is recorded" 'PERF_THERMAL_PREWARM_PEAK'
expect_grep "pre-warm is sampled" 'start_thermal_sampler "$GAME_PID" prewarm'
expect_grep "measured run is sampled" 'start_thermal_sampler "$GAME_PID" run'
expect_grep "VmHWM is read from /proc" 'VmHWM:'
expect_grep "VmRSS samples are kept" 'VmRSS:'
expect_grep "memory scope uses MemoryMax" 'MemoryMax=$MEM_MAX'
expect_grep "memory scope disables swap" 'MemorySwapMax=0'
expect_grep "scope fallback is logged" 'systemd-run --user --scope failed'
expect_grep "unknown temperature aborts the pre-check" 'reason=unknown_temp phase=precheck'
expect_grep "missing sampler aborts the launch" 'reason=sampler_missing'
expect_grep "RSS overrun fails the run" 'PERF_RSS_FAIL'
expect_grep "thermal abort fails the run" 'FAIL: thermal guard'
expect_grep "pre-check logs start/start_max/max" 'PERF_THERMAL start=${TEMP_START} start_max=${START_TEMP} max=${MAX_TEMP}'

echo
if [ "$FAILS" -ne 0 ]; then
  echo "PERF_GUARD_TEST FAIL checks=$CHECKS fails=$FAILS"
  exit 1
fi
echo "PERF_GUARD_TEST PASS checks=$CHECKS fails=0"
exit 0
