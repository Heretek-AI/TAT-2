#!/usr/bin/env bash
# Engine-error ceiling scan for the three large Godot logs.
#
# The TAT-2 suites are green but Godot emits known engine noise (freed lambdas,
# teardown resource warnings, the audited save-system "unusable" cases). A new
# `ERROR:` message is a regression that a `fails=0` summary cannot see, so this
# gate pins an explicit allowlist and a hard ceiling per log:
#
#       e2e        31
#       e2e_a2      1
#       run_tests  482
#
# Rules:
#   * Every ERROR: line must match an allowlist regex for its log; an
#     unmatched line fails as a NEW error.
#   * A pattern may not exceed its pinned maximum and a log may not exceed its
#     pinned ceiling. A lower count is fine (noise may disappear).
#   * The per-log sum of the allowlist maxima must equal the ceiling. Adding or
#     widening an entry therefore forces a visible ceiling change instead of
#     silently hiding a new message.
#   * Lowering a ceiling (or raising a maximum) needs a comment here plus a
#     note in the wave report; never edit them silently.
#
# Usage:
#   build/qa/e2e_errscan.sh [--logdir DIR] [--allowlist FILE]
#
# Exit 0 only when every ERROR line is allowlisted and every count is within
# its pinned maximum/ceiling.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOGDIR="$ROOT/docs/reports/logs/final"
ALLOWLIST="$ROOT/build/qa/e2e_errscan_allowlist.txt"
LOGS=(e2e e2e_a2 run_tests)

# Pinned ceilings, measured from docs/reports/logs/final/ at the Phase 3 base
# (e2e 31, e2e_a2 1, run_tests 482). Lowering one is a deliberate, reviewed
# change: add a comment here and a note in the wave report. Raising one because
# a new test legitimately emits a known message is also a reviewed change.
declare -A CEILING=([e2e]=31 [e2e_a2]=1 [run_tests]=482)

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

if [ ! -f "$ALLOWLIST" ]; then
  printf 'E2E_ERRSCAN FAIL reason=missing_allowlist path=%s\n' "$ALLOWLIST"
  exit 1
fi

# Parse the TSV allowlist: <log><TAB><max><TAB><extended-regex>.
pat_log=()
pat_max=()
pat_re=()
declare -A SUM=([e2e]=0 [e2e_a2]=0 [run_tests]=0)
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
  if ! [[ "$max" =~ ^[0-9]+$ ]]; then
    note_fail "allowlist line $lineno: max '$max' is not a non-negative integer"
    continue
  fi
  if [ -z "$re" ]; then
    note_fail "allowlist line $lineno: empty regex"
    continue
  fi
  pat_log+=("$log")
  pat_max+=("$max")
  pat_re+=("$re")
  SUM[$log]=$((${SUM[$log]} + max))
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
  if [ ! -f "$path" ]; then
    note_fail "missing log $path"
    continue
  fi
  if [ -L "$path" ]; then
    note_fail "log $path is a symlink; refusing to scan it"
    continue
  fi
  actual="$(grep -c -- 'ERROR:' "$path" 2>/dev/null || true)"
  [ -n "$actual" ] || actual=0
  if [ "$actual" -gt "${CEILING[$log]}" ]; then
    note_fail "log $log has $actual ERROR: line(s), above the pinned ceiling ${CEILING[$log]}"
  fi

  # Per-pattern counts start at zero for this log.
  counts=()
  for i in "${!pat_log[@]}"; do
    if [ "${pat_log[$i]}" = "$log" ]; then
      counts[$i]=0
    fi
  done

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
  done < <(grep -n -- 'ERROR:' "$path" 2>/dev/null || true)

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
  actual="$(grep -c -- 'ERROR:' "$LOGDIR/$log.log" 2>/dev/null || true)"
  [ -n "$actual" ] || actual=0
  parts+=("$log=$actual/${CEILING[$log]}")
done
printf 'E2E_ERRSCAN PASS %s new=0\n' "${parts[*]}"
exit 0
