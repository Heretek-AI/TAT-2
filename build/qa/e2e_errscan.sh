#!/usr/bin/env bash
# Engine-error ceiling scan for the three large Godot logs.
#
# The TAT-2 suites are green but Godot emits known engine noise (freed lambdas,
# teardown resource warnings, the audited save-system "unusable" cases). A new
# `ERROR:` message is a regression that a `fails=0` summary cannot see, so this
# gate pins an explicit allowlist and a hard ceiling per log:
#
#       e2e        33
#       e2e_a2      2
#       run_tests  482
#
# The 2026-11-27 raise from 31/1 is a reviewed change for a nondeterministic
# Godot teardown warning (`N resources still in use at exit`). It is at most one
# summary line per process and was observed 0-1 across the standalone and
# full-run samples, so the ceiling of 2 is one-slot headroom, not a measured
# maximum. It is not a lowered quality floor: a new/unmatched ERROR class still
# fails, each class keeps its own pinned maximum, and the per-log minimum totals
# below still reject a log whose known errors were deleted wholesale.
#
# Rules:
#   * Every ERROR: line must match an allowlist regex for its log; an
#     unmatched line fails as a NEW error.
#   * A log is complete only when it is non-empty AND carries its tier's own
#     completion marker (`SUMMARY: fails=0 passed=… total=…`) AND the runner
#     footer (`FINISHED:` and `EXIT: 0` in the last lines). A missing marker,
#     missing footer, or an empty file fails as truncated. Zero ERROR: lines in
#     a complete log pass only where the per-log minimum total is 0.
#   * A log may not fall below its tamper minimum (e2e 31, e2e_a2 0,
#     run_tests 482) or exceed its ceiling. A legitimate class disappearance is
#     a reviewed change to the minimum, never a silent pass.
#   * A pattern may not exceed its pinned maximum and a log may not exceed its
#     pinned ceiling. A lower count is fine (noise may disappear).
#   * The per-log sum of the allowlist maxima must equal the ceiling and every
#     individual maximum must be <= the ceiling. Adding or widening an entry
#     therefore forces a visible ceiling change instead of silently hiding a
#     new message.
#   * A maximum is parsed as base-10 and bounded (<= ceiling), so a huge value
#     cannot overflow bash arithmetic; an empty or non-alphanumeric (wildcard)
#     pattern is rejected.
#   * A symlinked --logdir or a symlinked/non-regular log is refused. A grep
#     that fails for a reason other than "no match" fails the gate; it is not
#     treated as zero errors.
#   * Lowering a ceiling (or raising a maximum) needs a comment here plus a
#     note in the wave report; never edit them silently.
#
# Usage:
#   build/qa/e2e_errscan.sh [--logdir DIR] [--allowlist FILE]
#
# Exit 0 only when every ERROR line is allowlisted, every count is within its
# pinned maximum/ceiling and tamper minimum, every log carries its completion
# marker and runner footer, and every log was actually read.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOGDIR="$ROOT/docs/reports/logs/final"
ALLOWLIST="$ROOT/build/qa/e2e_errscan_allowlist.txt"
LOGS=(e2e e2e_a2 run_tests)

# Pinned ceilings and tamper minima. e2e 33 / e2e_a2 2 / run_tests 482: the
# 2026-11-27 raise from 31/1 covers the nondeterministic `N resources still in
# use at exit` teardown class (observed 0-1; 2 is one-slot headroom). The minima
# keep a log from passing after its stable known errors were deleted.
# Lowering a ceiling or a minimum is a deliberate, reviewed change: add a
# comment here and a note in the wave report.
declare -A CEILING=([e2e]=33 [e2e_a2]=2 [run_tests]=482)
declare -A MIN_TOTAL=([e2e]=31 [e2e_a2]=0 [run_tests]=482)

# A complete log must carry its tier's own summary. This is the truncation
# check: absence of `ERROR:` lines is not truncation, a missing completion
# marker is.
declare -A COMPLETION=(
  [e2e]='SUMMARY: fails=0 passed=300 total=300'
  [e2e_a2]='SUMMARY: fails=0 passed=22 total=22'
  [run_tests]='SUMMARY: fails=0'
)

usage() {
  printf 'usage: %s [--logdir DIR] [--allowlist FILE]\n' "$0" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
  --logdir)
    LOGDIR="${2:?--logdir needs a value}"
    shift 2
    ;;
  --allowlist)
    ALLOWLIST="${2:?--allowlist needs a value}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
  esac
done

fails=0
note_fail() {
  printf 'ERRSCAN FAIL: %s\n' "$*"
  fails=$((fails + 1))
}

# A symlinked logdir would let --logdir redirect the scan to an attacker-chosen
# tree; require a real directory.
if [ -L "$LOGDIR" ] || [ ! -d "$LOGDIR" ]; then
  printf 'E2E_ERRSCAN FAIL reason=unsafe_logdir path=%s\n' "$LOGDIR"
  exit 1
fi
if [ -L "$ALLOWLIST" ] || [ ! -f "$ALLOWLIST" ]; then
  printf 'E2E_ERRSCAN FAIL reason=missing_or_symlinked_allowlist path=%s\n' "$ALLOWLIST"
  exit 1
fi

# Count ERROR: lines. Return 2 when grep could not read the file, so an
# unreadable log is a failure rather than a silent zero.
count_errors() {
  local p="$1" out rc
  out="$(grep -c -- 'ERROR:' "$p" 2>/dev/null)"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    return 2
  fi
  if [ "$rc" -eq 1 ]; then
    out=0
  fi
  printf '%s\n' "$out"
  return 0
}

# Parse the TSV allowlist: <log><TAB><max><TAB><extended-regex>. The maximum
# must be a bounded base-10 integer (no leading zeros), <= that log's ceiling;
# the pattern must contain at least one literal alphanumeric character so a
# bare `.*` cannot whitelist arbitrary lines.
pat_log=()
pat_max=()
pat_re=()
declare -A SUM=([e2e]=0 [e2e_a2]=0 [run_tests]=0)
MAX_RE='^(0|[1-9][0-9]{0,7})$'
lineno=0
while IFS=$'\t' read -r log max re; do
  lineno=$((lineno + 1))
  case "$log" in
  '' | \#*) continue ;;
  esac
  if [ -z "${CEILING[$log]+x}" ]; then
    note_fail "allowlist line $lineno: unknown log '$log'"
    continue
  fi
  if ! [[ "$max" =~ $MAX_RE ]]; then
    note_fail "allowlist line $lineno: max '$max' is not a bounded non-negative integer"
    continue
  fi
  max_i=$((10#$max))
  if [ "$max_i" -gt "${CEILING[$log]}" ]; then
    note_fail \
      "allowlist line $lineno: max $max_i exceeds the $log ceiling ${CEILING[$log]}"
    continue
  fi
  if [ -z "$re" ]; then
    note_fail "allowlist line $lineno: empty regex"
    continue
  fi
  if [ "${#re}" -gt 400 ]; then
    note_fail "allowlist line $lineno: regex is longer than 400 chars"
    continue
  fi
  if ! [[ "$re" =~ [A-Za-z0-9] ]]; then
    note_fail \
      "allowlist line $lineno: regex has no literal alphanumeric character (wildcard pattern)"
    continue
  fi
  pat_log+=("$log")
  pat_max+=("$max_i")
  pat_re+=("$re")
  SUM[$log]=$((${SUM[$log]} + max_i))
done <"$ALLOWLIST"

for log in "${LOGS[@]}"; do
  if [ "${SUM[$log]}" -ne "${CEILING[$log]}" ]; then
    note_fail \
      "allowlist maxima for $log sum to ${SUM[$log]}, but the pinned ceiling is ${CEILING[$log]}"
  fi
done

new_errors=0
declare -A new_error_lines=()
for log in "${LOGS[@]}"; do
  path="$LOGDIR/$log.log"
  if [ ! -e "$path" ]; then
    note_fail "missing log $path"
    continue
  fi
  if [ -L "$path" ] || [ ! -f "$path" ]; then
    note_fail "log $path is a symlink or non-regular file; refusing to scan it"
    continue
  fi
  if [ ! -s "$path" ]; then
    note_fail "log $path is empty; a truncated log cannot prove the gate"
    continue
  fi
  # Truncation is a missing completion marker, not a zero ERROR count: a
  # complete log with no teardown noise is a clean run.
  if grep -Fq -- "${COMPLETION[$log]}" "$path" 2>/dev/null; then
    :
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      note_fail "cannot read log $path (grep failed)"
    else
      note_fail \
        "log $path is missing its completion marker '${COMPLETION[$log]}'; truncated log cannot prove the gate"
    fi
    continue
  fi
  # The runner footer proves the gate wrapper closed the log. A file truncated
  # right after `SUMMARY:` still has the marker but loses the footer.
  if ! tail -n 6 -- "$path" | grep -Fq -- 'FINISHED:'; then
    note_fail \
      "log $path is missing the FINISHED footer; truncated log cannot prove the gate"
    continue
  fi
  if ! tail -n 6 -- "$path" | grep -Fq -- 'EXIT: 0'; then
    note_fail \
      "log $path is missing the 'EXIT: 0' footer; truncated log cannot prove the gate"
    continue
  fi
  actual="$(count_errors "$path")"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    note_fail "cannot read log $path (grep failed)"
    continue
  fi
  if [ "$actual" -gt "${CEILING[$log]}" ]; then
    note_fail "log $log has $actual ERROR: line(s), above the pinned ceiling ${CEILING[$log]}"
  fi
  if [ "$actual" -lt "${MIN_TOTAL[$log]}" ]; then
    note_fail \
      "log $log has $actual ERROR: line(s), below the minimum total ${MIN_TOTAL[$log]} (a legitimate class disappearance is a reviewed change)"
  fi

  # Per-pattern counts start at zero for this log.
  counts=()
  for i in "${!pat_log[@]}"; do
    if [ "${pat_log[$i]}" = "$log" ]; then
      counts[$i]=0
    fi
  done

  # Materialise the grep output so a read failure is distinguishable from an
  # empty match set (process substitution would hide grep's exit code).
  tmp="$(mktemp "${TMPDIR:-/tmp}/tat2-errscan.XXXXXX")" || {
    note_fail "cannot create a temp file for $log"
    continue
  }
  # grep exits 1 when there is no match: a complete log with zero ERROR: lines
  # is valid (only exit > 1 is a read failure).
  grep -n -- 'ERROR:' "$path" >"$tmp" 2>/dev/null
  rc=$?
  if [ "$rc" -gt 1 ]; then
    note_fail "cannot read ERROR: lines from $path (grep exit $rc)"
    rm -f "$tmp"
    continue
  fi
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    msg="${raw#*ERROR:}"
    msg="${msg#"${msg%%[![:space:]]*}"}"
    matched=-1
    for i in "${!pat_log[@]}"; do
      if [ "${pat_log[$i]}" != "$log" ]; then
        continue
      fi
      if [[ "$msg" =~ ${pat_re[$i]} ]]; then
        matched=$i
        break
      fi
    done
    if [ "$matched" -lt 0 ]; then
      new_errors=$((new_errors + 1))
      new_error_lines[$log]+="  $msg"$'\n'
    else
      counts[$matched]=$((${counts[$matched]} + 1))
    fi
  done <"$tmp"
  rm -f "$tmp"

  for i in "${!pat_log[@]}"; do
    if [ "${pat_log[$i]}" != "$log" ]; then
      continue
    fi
    if [ "${counts[$i]}" -gt "${pat_max[$i]}" ]; then
      note_fail \
        "log $log pattern ${i} matched ${counts[$i]} times, above its pinned maximum ${pat_max[$i]}: ${pat_re[$i]}"
    fi
  done
done

if [ "$new_errors" -gt 0 ]; then
  for log in "${LOGS[@]}"; do
    if [ -n "${new_error_lines[$log]:-}" ]; then
      printf 'ERRSCAN NEW %s:\n%s' "$log" "${new_error_lines[$log]}"
    fi
  done
fi

if [ "$fails" -ne 0 ] || [ "$new_errors" -ne 0 ]; then
  printf 'E2E_ERRSCAN FAIL fails=%d new=%d\n' "$fails" "$new_errors"
  exit 1
fi

# Report actual counts (not ceilings) so a shrinking noise floor is visible.
parts=()
for log in "${LOGS[@]}"; do
  actual="$(count_errors "$LOGDIR/$log.log")"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    printf 'E2E_ERRSCAN FAIL fails=1 new=0 (cannot re-read %s)\n' "$log"
    exit 1
  fi
  parts+=("$log=$actual/${CEILING[$log]}")
done
printf 'E2E_ERRSCAN PASS %s new=0\n' "${parts[*]}"
exit 0
