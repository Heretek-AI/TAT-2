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
ROOT="$(cd "$HERE/../.." && pwd)"
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
if bash -n "$HERE/export_stamp.sh"; then pass "export_stamp.sh parses"; else fail "export_stamp.sh does not parse"; fi

echo "== temperature decision (defaults start=78 max=95) =="
OUT="$("$WRAPPER" --guard-check=77 2>&1)"; CODE=$?
[ "$CODE" = 0 ] && pass "77 C starts" || fail "77 C should start (got $CODE)"
expect_contains "$OUT" "guard-check reports the defaults" "start_max=78 max=95"
expect_contains "$OUT" "guard-check reports ok" "decision=ok"
expect_code 0 "78 C == --start-temp starts" --guard-check=78
# The guard-check argument is mandatory: without it the wrapper runs the full
# pre-check (and on a cool host would launch a game). This was a latent defect
# in the W4P test that only passed because the host was hot enough to exit 8.
expect_code 8 "79 C > --start-temp is refused" --guard-check=79
expect_code 8 "94 C (hot idle, below max) is refused" --guard-check=94
expect_code 8 "95 C == --max-temp is refused" --guard-check=95
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
expect_code 2 "--max-rss-mb below 1024" --max-rss-mb=64
expect_code 2 "--max-rss-mb above 262144" --max-rss-mb=262145
OUT="$(PERF_SCOPE_MEMORY_MAX=12X "$WRAPPER" --guard-check=70 2>&1)"; CODE=$?
[ "$CODE" = 2 ] && pass "invalid PERF_SCOPE_MEMORY_MAX is refused (exit 2)" || fail "invalid PERF_SCOPE_MEMORY_MAX should exit 2 (got $CODE)"
expect_code 2 "--sample-sec 0" --sample-sec=0
expect_code 2 "--sample-sec above 60" --sample-sec=61

echo "== RSS decision (synthetic) =="
expect_code 0 "1024 MB fits a 8192 MB ceiling" --rss-check=1024
expect_code 0 "8192 MB == ceiling is allowed" --rss-check=8192
expect_code 9 "8193 MB > ceiling is refused" --rss-check=8193
expect_code 9 "unknown RSS is refused (fail closed)" '--rss-check=?'
expect_code 9 "non-numeric RSS is refused" --rss-check=abc
expect_code 0 "explicit scope override accepts a fitting cap" --max-rss-mb=1024 --guard-check=70
OUT="$(PERF_SCOPE_MEMORY_MAX=1G "$WRAPPER" --max-rss-mb=2048 --guard-check=70 2>&1)"; CODE=$?
[ "$CODE" = 2 ] && pass "cap above an explicit 1G scope is refused (exit 2)" || fail "cap above the 1G scope should exit 2 (got $CODE)"

echo "== guard machinery in the wrapper =="
expect_grep "start-temp default is 78" 'START_TEMP="${PERF_START_TEMP:-78}"'
expect_grep "max-temp default is 95" 'MAX_TEMP="${PERF_MAX_TEMP:-95}"'
expect_grep "RSS cap default is 8192 MB" 'MAX_RSS_MB="${PERF_MAX_RSS_MB:-8192}"'
expect_grep "sampler cadence default is 1 s" 'SAMPLE_SEC="${PERF_THERMAL_SAMPLE_SEC:-1}"'
expect_grep "MemoryMax is derived from RAM" 'ram_total_mb()'
expect_grep "memory scope honours an explicit override" 'MEM_MAX_OVERRIDE="${PERF_SCOPE_MEMORY_MAX:-}"'
expect_grep "sampler logs PERF_THERMAL_SAMPLE" 'PERF_THERMAL_SAMPLE phase='
expect_grep "pre-warm peak is recorded" 'PERF_THERMAL_PREWARM_PEAK'
expect_grep "pre-warm is sampled" 'start_thermal_sampler "$GAME_PID" prewarm'
expect_grep "measured run is sampled" 'start_thermal_sampler "$GAME_PID" run'
expect_grep "VmHWM is read from /proc" 'VmHWM:'
expect_grep "VmRSS samples are kept" 'VmRSS:'
expect_grep "memory scope uses MemoryMax" 'MemoryMax=$MEM_MAX'
expect_grep "memory scope disables swap" 'MemoryMax=$MEM_MAX'
expect_grep "memory scope logs the RAM total" 'ram_total_mb=${RAM_TOTAL_MB:-unknown}'
expect_grep "memory scope disables swap" 'MemorySwapMax=0'
expect_grep "scope fallback is logged" 'systemd-run --user --scope failed'
expect_grep "unknown temperature aborts the pre-check" 'reason=unknown_temp phase=precheck'
expect_grep "missing sampler aborts the launch" 'reason=sampler_missing'
expect_grep "RSS overrun fails the run" 'PERF_RSS_FAIL'
expect_grep "thermal abort fails the run" 'FAIL: thermal guard'
expect_grep "pre-check logs start/start_max/max" 'PERF_THERMAL start=${TEMP_START} start_max=${START_TEMP} max=${MAX_TEMP}'
expect_grep "export stamp is verified" 'export_stamp.sh" verify'
expect_grep "provenance is logged" 'PERF_PROVENANCE mode=export'
expect_grep "PCK path/SHA/size is logged" 'PERF_PCK path='
expect_grep "stale stamp aborts the run" 'export stamp is stale'
expect_grep "artifact mismatch aborts the run" 'export artifact does not match its stamp'
expect_grep "publishable-only is enforced" 'publishable-only but this run is not publishable'

echo "== export preset excludes review scenes =="
if grep -qF 'exclude_filter="scenes/review/**"' "$ROOT/game/export_presets.cfg"; then
  pass "QA export excludes scenes/review/**"
else
  fail "QA export does not exclude scenes/review/**"
fi

echo "== export provenance (stamp writer/verifier) =="
STAMP_TOOL="$HERE/export_stamp.sh"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/tat2-stamp.XXXXXX")"
cleanup_tmp() { rm -rf "$TMPD"; }
trap cleanup_tmp EXIT
FAKE_BIN="$TMPD/tat2-linux-x86_64"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN"
chmod +x "$FAKE_BIN"
printf 'fake-pck' > "$FAKE_BIN.pck"
HEAD_SHORT="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
write_stamp() { "$STAMP_TOOL" write --root "$ROOT" --binary "$FAKE_BIN" --preset Linux >/dev/null 2>&1; }

OUT="$("$STAMP_TOOL" write --root "$ROOT" --binary "$FAKE_BIN" --preset Linux 2>&1)"; CODE=$?
[ "$CODE" = 0 ] && pass "stamp write exits 0" || fail "stamp write failed: $OUT"
expect_contains "$OUT" "stamp records HEAD" "git=$HEAD_SHORT"
expect_contains "$OUT" "stamp records the PCK size" "pck_bytes=$(stat -c '%s' "$FAKE_BIN.pck")"
[ -f "$FAKE_BIN.stamp.json" ] && pass "stamp file is written" || fail "stamp file is missing"
expect_contains "$(cat "$FAKE_BIN.stamp.json" 2>/dev/null)" "stamp excludes review scenes" '"exclude": "scenes/review'
expect_contains "$(cat "$FAKE_BIN.stamp.json" 2>/dev/null)" "stamp stores the PCK SHA-256" '"pck_sha256"'

OUT="$("$WRAPPER" --provenance-check="$FAKE_BIN" 2>&1)"; CODE=$?
[ "$CODE" = 0 ] && pass "wrapper accepts a current stamp (exit 0)" || fail "wrapper rejected a current stamp (exit $CODE): $OUT"
expect_contains "$OUT" "provenance check logs the PCK" "PERF_PCK path="

python3 - "$FAKE_BIN.stamp.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["git_sha"] = "deadbeef0000"
json.dump(d, open(p, "w"))
PY
OUT="$("$WRAPPER" --provenance-check="$FAKE_BIN" 2>&1)"; CODE=$?
[ "$CODE" = 3 ] && pass "stale stamp is refused (exit 3)" || fail "stale stamp should exit 3 (got $CODE)"
expect_contains "$OUT" "stale failure names the reason" "reason=stale_stamp"

write_stamp
printf 'tampered' >> "$FAKE_BIN.pck"
OUT="$("$WRAPPER" --provenance-check="$FAKE_BIN" 2>&1)"; CODE=$?
[ "$CODE" = 4 ] && pass "PCK hash mismatch is refused (exit 4)" || fail "PCK mismatch should exit 4 (got $CODE)"

write_stamp
rm -f "$FAKE_BIN.pck"
OUT="$("$WRAPPER" --provenance-check="$FAKE_BIN" 2>&1)"; CODE=$?
[ "$CODE" = 5 ] && pass "missing PCK is refused (exit 5)" || fail "missing PCK should exit 5 (got $CODE)"

write_stamp
rm -f "$FAKE_BIN.stamp.json"
OUT="$("$WRAPPER" --provenance-check="$FAKE_BIN" 2>&1)"; CODE=$?
[ "$CODE" = 5 ] && pass "missing stamp is refused (exit 5)" || fail "missing stamp should exit 5 (got $CODE)"

printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN"
printf 'fake-pck' > "$FAKE_BIN.pck"
write_stamp
OUT="$("$STAMP_TOOL" verify --root "$ROOT" --binary "$FAKE_BIN" 2>&1)"; CODE=$?
[ "$CODE" = 0 ] && pass "verify reports a clean stamp (exit 0)" || fail "verify failed on a clean stamp (exit $CODE): $OUT"
expect_contains "$OUT" "verify prints the artifact digests" "binary_sha="

echo
if [ "$FAILS" -ne 0 ]; then
  echo "PERF_GUARD_TEST FAIL checks=$CHECKS fails=$FAILS"
  exit 1
fi
echo "PERF_GUARD_TEST PASS checks=$CHECKS fails=0"
exit 0
