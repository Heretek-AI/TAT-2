#!/usr/bin/env bash
# Mechanically capture the post-stamp gate-ratchet run.
#
# The runner's in-run `docs/reports/logs/final/gate_ratchet.log` must not be
# overwritten. This wrapper produces the post-stamp artefact in ONE pass:
# `STARTED:` is stamped before the checker runs, the checker's real stdout and
# exit code are captured, and `FINISHED:` is stamped after it. Nothing is
# hand-assembled and no line is edited.
#
# The checker validates the poststamp artefact itself (it is a static evidence
# log). During generation it is therefore run with `--generating-poststamp`,
# which skips only that self-referential entry; a plain run afterwards validates
# the finished artefact (stamps + content). See tools/check_gate_ratchet.py.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/docs/reports/logs/final/gate_ratchet_poststamp.log}"
case "$OUT" in
/*) ;;
*) OUT="$ROOT/$OUT" ;;
esac

TMP="$(mktemp "${TMPDIR:-/tmp}/tat2-poststamp.XXXXXX")" || exit 2
trap 'rm -f "$TMP"' EXIT

{
  printf '== POST_STAMP gate_ratchet\n'
  printf 'COMMAND: python3 -B tools/check_gate_ratchet.py --generating-poststamp\n'
  printf 'CWD: .\n'
  printf 'STARTED: %s\n\n' "$(date -Is)"
} >"$TMP"

python3 -B "$ROOT/tools/check_gate_ratchet.py" --generating-poststamp >>"$TMP" 2>&1
rc=$?

printf '\nEXIT: %d\nFINISHED: %s\n' "$rc" "$(date -Is)" >>"$TMP"

mv -f -- "$TMP" "$OUT"
trap - EXIT
exit "$rc"
