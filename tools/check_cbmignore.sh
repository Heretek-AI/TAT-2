#!/usr/bin/env bash
# Regression check for the codebase-memory index whitelist (.cbmignore).
#
# The repo's .gitignore also excludes most of these trees, so running
# check-ignore inside TAT-2 would pass even if .cbmignore regressed. This runs
# check-ignore in a throwaway repo whose only exclude source is .cbmignore, so
# the assertions isolate its semantics.
#
# Note: `git check-ignore -v` also reports whitelist negations (`!pattern`) as
# matches (exit 0). A path is only "ignored" when the last matching pattern is
# NOT prefixed with `!`, so we inspect the pattern itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE="$ROOT/.cbmignore"
[ -f "$IGNORE" ] || { echo "FAIL: missing $IGNORE" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cbmignore-check.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q

fail=0

pattern_for() {
  local out
  out="$(git -C "$TMP" -c core.excludesFile="$IGNORE" check-ignore -v --no-index -- "$1" || true)"
  [ -n "$out" ] || return 0
  local pat="${out#*:*:}"
  printf '%s' "${pat%%$'\t'*}"
}

check_ignored() {
  local p="$1" pat
  pat="$(pattern_for "$p")"
  if [ -z "$pat" ]; then
    printf 'FAIL  not ignored: %s\n' "$p" >&2
    fail=1
    return
  fi
  if [ "${pat:0:1}" = "!" ]; then
    printf 'FAIL  whitelisted, must be ignored: %s  (pattern %s)\n' "$p" "$pat" >&2
    fail=1
    return
  fi
  printf 'ok    ignored:   %-50s <- %s\n' "$p" "$pat"
}

check_indexable() {
  local p="$1" pat
  pat="$(pattern_for "$p")"
  if [ -n "$pat" ] && [ "${pat:0:1}" != "!" ]; then
    printf 'FAIL  ignored, must stay indexable: %s  (pattern %s)\n' "$p" "$pat" >&2
    fail=1
    return
  fi
  printf 'ok    indexable: %s\n' "$p"
}

# Heavy/derived trees: hard "never index" assertions.
while IFS= read -r p; do
  [ -n "$p" ] && check_ignored "$p"
done <<'EOF'
extracted/foo/bar.uasset
build/qa/capture.png
game/.godot/imported/x.ctex
game/data/generated/world.json
game/scenes/review/bake.tscn
game/assets/ue/Mesh.uasset
game/i18n/generated/strings.json
tools/tat-extract/bin/app.dll
tools/tat-extract/obj/project.assets.json
tools/ue4ss/cache/cache.bin
tools/__pycache__/parse.cpython-311.pyc
EOF

# Hand-written source: must remain indexable.
while IFS= read -r p; do
  [ -n "$p" ] && check_indexable "$p"
done <<'EOF'
game/src/player/thief_character.gd
game/tests/test_m2_player.gd
game/addons/foo/plugin.cfg
game/scenes/Mission01.tscn
game/data/expansion/contracts.json
tools/parse_materials.py
tools/tat-extract/Program.cs
tools/ue4ss/README.md
docs/FIDELITY_GAPS.md
AGENTS.md
README.md
Makefile
.gitignore
.cbmignore
.gitattributes
EOF

if [ "$fail" -ne 0 ]; then
  echo "CBMIGNORE CHECK FAILED" >&2
  exit 1
fi

echo "CBMIGNORE CHECK PASS: heavy trees ignored, source whitelist intact"
