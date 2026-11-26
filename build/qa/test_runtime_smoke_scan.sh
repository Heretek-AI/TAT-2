#!/usr/bin/env bash
# W10-A D9 red/green proof for the runtime-smoke decision logic.
#
# Runs WITHOUT Godot: every case is a fixture log plus a simulated exit code.
# Two deciders are compared:
#   * `pre_fix`  — a verbatim copy of build/qa/runtime_smoke.sh:26-45 at
#                  29046c8 (counted only SCRIPT/SHADER ERROR, never read the
#                  exit code, never looked at ERROR:);
#   * `scanned`  — build/qa/runtime_smoke_scan.sh, the factor-out now called by
#                  runtime_smoke.sh.
#
# The script fails when either decider disagrees with the expected verdict, and
# it prints the red explicitly: the pre-fix logic MUST pass the four blind spots.
# Run: build/qa/test_runtime_smoke_scan.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/runtime_smoke_scan.sh"
TMP="$(mktemp -d -t tat2-smoke-scan-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
CHECKS=0

ok()   { CHECKS=$((CHECKS+1)); }
pass() { ok; }
fail() { ok; FAILS=$((FAILS+1)); echo "FAIL: $*" >&2; }

# ---------------------------------------------------------------- fixtures
c_clean="$TMP/clean.log"
{
  echo "Godot Engine v4.7.2.stable"
  echo "TAT-2 mission_ready map=guildhall meshes=63100 lights=160 chunks=6015"
  echo "AUTHORED_COLLISION meshes=947 hull=937 prims=599 convex=899 absent=10 no_collision=7 query_only=7 reduced=16 shapes_per_instance_avg=1.14 elements=2184 load_ms=310"
} >"$c_clean"

c_engine="$TMP/engine_error.log"
{ cat "$c_clean"; echo 'ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()'; } >"$c_engine"

c_push="$TMP/push_error.log"
{ cat "$c_clean"; echo 'USER ERROR: "[mission_controller] loot economy shortfall: spawned value 900 < loot_goal 1000"'; } >"$c_push"

c_script="$TMP/script_error.log"
{ cat "$c_clean"; echo 'SCRIPT ERROR: Invalid call. Nonexistent function "foo" in base "Bar".'; } >"$c_script"

c_shader="$TMP/shader_error.log"
{ cat "$c_clean"; echo 'SHADER ERROR: Invalid expression in shader.'; } >"$c_shader"

c_noready="$TMP/no_ready.log"
{ echo "Godot Engine v4.7.2.stable"; echo "TAT-2 booting"; } >"$c_noready"

c_crash="$TMP/crash.log"
{ cat "$c_clean"; echo "handle_crash: Program crashed with signal 11"; } >"$c_crash"

c_exit0="$TMP/exit_zero.log"
{ cat "$c_clean"; echo "TAT-2 shutdown"; } >"$c_exit0"

c_allow="$TMP/allowlisted.log"
{ cat "$c_clean"; echo "ERROR: 2 resources still in use at exit (run with --verbose for details)."; } >"$c_allow"

c_warn="$TMP/warnings.log"
{ cat "$c_clean"
  echo "WARNING: [game_data] map fallback (unrecognized mission row routes to example) for row 'Mission.Example.Multi' (fallbacks=1, cap=64)"
  echo "WARNING: [hearing_data] 5 authored investigation-range anomalies clamped: AI.Stim.Hearing.LockPicking.Picked: outer 5.0 m > max 3.0 m (clamped)"
  echo "WARNING: [nav_steering] no synchronised navigation map (no NavigationRegion3D baked for this map)"
} >"$c_warn"

# --------------------------------------------- pre-fix decider (29046c8 code)
pre_fix_decision() {
  local LOG="$1" CODE="$2"
  local SCRIPT SHADER READY
  SCRIPT=$(grep -c "SCRIPT ERROR" "$LOG" 2>/dev/null || true)
  SHADER=$(grep -c "SHADER ERROR" "$LOG" 2>/dev/null || true)
  READY=$(grep -c "TAT-2 mission_ready" "$LOG" 2>/dev/null || true)
  SCRIPT=${SCRIPT:-0}; SHADER=${SHADER:-0}; READY=${READY:-0}
  if [ "$READY" -lt 1 ]; then return 1; fi
  if [ "$SCRIPT" -gt 0 ] || [ "$SHADER" -gt 0 ]; then return 1; fi
  return 0
}

# --------------------------------------------------------------- assertions
expect() {
  local label="$1" want="$2" log="$3" code="$4"
  local got
  "$SCAN" "$log" "$code" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    ok
    printf 'PASS scan   %-24s exit=%s\n' "$label" "$got"
  else
    fail "scanned: $label expected exit $want, got $got ($log exit=$code)"
  fi
}

expect_pre_fix() {
  local label="$1" want="$2" log="$3" code="$4"
  local got
  if pre_fix_decision "$log" "$code"; then got=0; else got=1; fi
  if [ "$got" -eq "$want" ]; then
    ok
    printf 'PASS prefix %-24s exit=%s\n' "$label" "$got"
  else
    fail "pre_fix: $label expected exit $want, got $got"
  fi
}

# Green: the good boot passes both deciders.
expect         "clean boot"            0 "$c_clean"  124
expect_pre_fix "clean boot"            0 "$c_clean"  124
# Green: warnings are reported, not fatal.
expect         "warning-only boot"     0 "$c_warn"   124
# Green: an allowlisted teardown ERROR passes (embedded defaults).
expect         "allowlisted ERROR"     0 "$c_allow"  124

# Red: the pre-fix logic's blind spots — it MUST pass all four of these,
# while the scanner rejects each of them.
for case in "ERROR: line|$c_engine|124" "push_error line|$c_push|124" \
            "signal-11 crash|$c_crash|139" "premature exit 0|$c_exit0|0" \
            "clean log, exit 1|$c_clean|1"; do
  IFS='|' read -r label log code <<<"$case"
  if pre_fix_decision "$log" "$code"; then cur=PASS; else cur=FAIL; fi
  "$SCAN" "$log" "$code" >/dev/null 2>&1
  if [ $? -eq 0 ]; then prop=PASS; else prop=FAIL; fi
  echo "PRE_FIX_BLIND_SPOT: ${label} -> runtime_smoke.sh at 29046c8=${cur}, scanned=${prop}"
  if [ "$cur" = "PASS" ] && [ "$prop" = "FAIL" ]; then pass; else
    fail "blind spot not reproduced for '${label}' (pre_fix=${cur}, scanned=${prop})"
  fi
done
expect_pre_fix "ERROR: line"           0 "$c_engine" 124
expect_pre_fix "push_error line"       0 "$c_push"   124
expect_pre_fix "signal-11 crash"       0 "$c_crash"  139
expect_pre_fix "premature exit 0"      0 "$c_exit0"  0
expect_pre_fix "clean log, exit 1"     0 "$c_clean"  1
expect         "ERROR: line"           1 "$c_engine" 124
expect         "push_error line"       1 "$c_push"   124
expect         "signal-11 crash"       1 "$c_crash"  139
expect         "premature exit 0"      1 "$c_exit0"  0
expect         "clean log, exit 1"     1 "$c_clean"  1

# Both reject the cases the old gate already caught.
expect_pre_fix "SCRIPT ERROR"          1 "$c_script" 124
expect         "SCRIPT ERROR"          1 "$c_script" 124
expect_pre_fix "SHADER ERROR"          1 "$c_shader" 124
expect         "SHADER ERROR"          1 "$c_shader" 124
expect_pre_fix "never mission_ready"   1 "$c_noready" 124
expect         "never mission_ready"   1 "$c_noready" 124

# The machine line is the contract the gate log/ratchet reads.
line=$("$SCAN" "$c_clean" 124 2>/dev/null | tail -1)
case "$line" in
  "RUNTIME_SMOKE_SCAN PASS"*"exit=124"*"mission_ready=1"*"reason=ok"*"path=$c_clean")
    pass ;;
  *) fail "unexpected machine line: $line" ;;
esac
line_bad=$("$SCAN" "$c_engine" 124 2>/dev/null | tail -1)
case "$line_bad" in
  "RUNTIME_SMOKE_SCAN FAIL"*"reason=runtime_errors"*) pass ;;
  *) fail "unexpected failure line: $line_bad" ;;
esac

# Usage/unreadable-log errors are distinct from a verdict.
"$SCAN" >/dev/null 2>&1
if [ $? -eq 2 ]; then pass; else fail "missing args should exit 2"; fi
"$SCAN" "$TMP/does-not-exist.log" 124 >/dev/null 2>&1
if [ $? -eq 1 ]; then pass; else fail "missing log should exit 1"; fi

echo "RUNTIME_SMOKE_SCAN_TEST $([ "$FAILS" -eq 0 ] && echo PASS || echo FAIL) checks=${CHECKS} fails=${FAILS}"
[ "$FAILS" -eq 0 ]
