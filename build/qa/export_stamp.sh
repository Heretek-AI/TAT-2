#!/usr/bin/env bash
# Export provenance for the Linux QA build (W7G).
#
# `make linux-build` calls `write` after a successful export. The perf wrapper
# calls `verify` before it measures an exported binary, so a measurement can
# never be attributed to a tree other than the one the binary was built from:
#
#   build/qa/export_stamp.sh write  --root <repo> --binary build/tat2-linux-x86_64
#   build/qa/export_stamp.sh verify --root <repo> --binary build/tat2-linux-x86_64
#
# The stamp records HEAD (short + full), the UTC build time, the Godot version,
# a tracked-tree dirty flag, and the SHA-256 + byte size of both the executable
# and its PCK. Output is <binary>.stamp.json (gitignored with build/).
#
# verify exits:
#   0  stamp matches this tree and both artifacts
#   3  stale: stamp HEAD != current HEAD (rebuild before measuring)
#   4  artifact mismatch: PCK/binary size or SHA-256 differs from the stamp
#   5  missing stamp or artifact
#   6  --require-clean was passed and the tracked tree was dirty at build time
#
# Never uploads or rewrites anything: write replaces only its own stamp.
set -u

ROOT=""
BINARY=""
STAMP=""
PRESET="Linux"
REQUIRE_CLEAN=0
MODE="${1:-}"
[ $# -gt 0 ] && shift

die() { echo "EXPORT_STAMP_FAIL $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root=*) ROOT="${1#*=}" ;;
    --root) shift; ROOT="${1:-}" ;;
    --binary=*) BINARY="${1#*=}" ;;
    --binary) shift; BINARY="${1:-}" ;;
    --stamp=*) STAMP="${1#*=}" ;;
    --stamp) shift; STAMP="${1:-}" ;;
    --preset=*) PRESET="${1#*=}" ;;
    --preset) shift; PRESET="${1:-}" ;;
    --require-clean) REQUIRE_CLEAN=1 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[ -n "$ROOT" ] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ -n "$BINARY" ] || die "--binary is required"
[ -n "$STAMP" ] || STAMP="${BINARY}.stamp.json"

abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$ROOT" "$1" ;; esac; }
BINARY="$(abs_path "$BINARY")"
STAMP="$(abs_path "$STAMP")"

git_head() { git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown'; }
git_head_full() { git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown'; }
# Tracked modifications only: the private extract/assets trees are untracked
# (gitignored) by design and must not make every build look dirty.
git_dirty() {
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}
file_sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
file_bytes() { stat -c '%s' "$1" 2>/dev/null || printf '0'; }

# Godot writes <binary>.pck for a non-embedded export. If the preset ever
# embeds it, the stamp records pck=none/embedded=1 and verify checks the
# executable only; a missing PCK is never silently treated as "fine".
find_pck() {
  if [ -f "${BINARY}.pck" ]; then printf '%s' "${BINARY}.pck"; fi
}

case "$MODE" in
  write)
    [ -f "$BINARY" ] || die "exported binary missing: $BINARY"
    PCK="$(find_pck)"
    if [ -n "$PCK" ]; then
      PCK_JSON="\"$(basename "$PCK")\""
      PCK_SHA="\"$(file_sha "$PCK")\""
      PCK_BYTES="$(file_bytes "$PCK")"
      EMBEDDED=0
    else
      PCK_JSON="null"
      PCK_SHA="null"
      PCK_BYTES=0
      EMBEDDED=1
    fi
    BIN_SHA="$(file_sha "$BINARY")"
    BIN_BYTES="$(file_bytes "$BINARY")"
    HEAD_SHORT="$(git_head)"
    HEAD_FULL="$(git_head_full)"
    DIRTY="$(git_dirty)"
    BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    GODOT_VERSION="$("$ROOT/tools/godot" --version 2>/dev/null | head -1 || printf 'unknown')"
    cat > "$STAMP" <<JSON
{
  "schema": "tat2.export_stamp/1",
  "preset": "$PRESET",
  "git_sha": "$HEAD_SHORT",
  "git_sha_full": "$HEAD_FULL",
  "git_dirty": $DIRTY,
  "built_at": "$BUILT_AT",
  "godot": "$GODOT_VERSION",
  "binary": "$(basename "$BINARY")",
  "binary_sha256": "$BIN_SHA",
  "binary_bytes": $BIN_BYTES,
  "pck": $PCK_JSON,
  "pck_sha256": $PCK_SHA,
  "pck_bytes": $PCK_BYTES,
  "pck_embedded": $EMBEDDED,
  "exclude": "scenes/review/**"
}
JSON
    echo "EXPORT_STAMP path=$STAMP git=$HEAD_SHORT dirty=$DIRTY binary=$(basename "$BINARY") binary_sha=$BIN_SHA binary_bytes=$BIN_BYTES pck=${PCK:-embedded} pck_bytes=$PCK_BYTES preset=$PRESET built_at=$BUILT_AT"
    if [ "$DIRTY" = "true" ]; then
      echo "EXPORT_STAMP_WARNING tracked tree dirty at build time: this build is not publishable" >&2
    fi
    ;;

  verify)
    [ -f "$STAMP" ] || { echo "EXPORT_STAMP_FAIL missing_stamp path=$STAMP" >&2; exit 5; }
    [ -f "$BINARY" ] || { echo "EXPORT_STAMP_FAIL missing_binary path=$BINARY" >&2; exit 5; }
    STAMPED_HEAD="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("git_sha",""))' "$STAMP" 2>/dev/null)"
    STAMPED_PCK="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pck") or "")' "$STAMP" 2>/dev/null)"
    STAMPED_PCK_SHA="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pck_sha256") or "")' "$STAMP" 2>/dev/null)"
    STAMPED_PCK_BYTES="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pck_bytes") or 0)' "$STAMP" 2>/dev/null)"
    STAMPED_BIN_SHA="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("binary_sha256") or "")' "$STAMP" 2>/dev/null)"
    STAMPED_BIN_BYTES="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("binary_bytes") or 0)' "$STAMP" 2>/dev/null)"
    STAMPED_DIRTY="$(python3 -c 'import json,sys;print(str(json.load(open(sys.argv[1])).get("git_dirty")).lower())' "$STAMP" 2>/dev/null)"
    STAMPED_GODOT="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("godot","unknown"))' "$STAMP" 2>/dev/null)"
    HEAD_SHORT="$(git_head)"
    if [ -z "$STAMPED_HEAD" ] || [ "$STAMPED_HEAD" = "unknown" ]; then
      echo "EXPORT_STAMP_FAIL unreadable_stamp path=$STAMP" >&2
      exit 5
    fi
    if [ "$STAMPED_HEAD" != "$HEAD_SHORT" ]; then
      echo "EXPORT_STAMP_FAIL stale stamp_git=$STAMPED_HEAD head=$HEAD_SHORT stamp=$STAMP" >&2
      exit 3
    fi
    BIN_SHA="$(file_sha "$BINARY")"
    BIN_BYTES="$(file_bytes "$BINARY")"
    if [ "$BIN_SHA" != "$STAMPED_BIN_SHA" ] || [ "$BIN_BYTES" != "$STAMPED_BIN_BYTES" ]; then
      echo "EXPORT_STAMP_FAIL binary_mismatch got_sha=$BIN_SHA want_sha=$STAMPED_BIN_SHA got_bytes=$BIN_BYTES want_bytes=$STAMPED_BIN_BYTES" >&2
      exit 4
    fi
    PCK="${BINARY}.pck"
    if [ -n "$STAMPED_PCK" ]; then
      [ -f "$PCK" ] || { echo "EXPORT_STAMP_FAIL missing_pck path=$PCK" >&2; exit 5; }
      PCK_SHA="$(file_sha "$PCK")"
      PCK_BYTES="$(file_bytes "$PCK")"
      if [ "$PCK_SHA" != "$STAMPED_PCK_SHA" ] || [ "$PCK_BYTES" != "$STAMPED_PCK_BYTES" ]; then
        echo "EXPORT_STAMP_FAIL pck_mismatch path=$PCK got_sha=$PCK_SHA want_sha=$STAMPED_PCK_SHA got_bytes=$PCK_BYTES want_bytes=$STAMPED_PCK_BYTES" >&2
        exit 4
      fi
      PCK_OUT="$PCK"
    else
      PCK_SHA="embedded"
      PCK_BYTES=0
      PCK_OUT="embedded"
    fi
    if [ "$REQUIRE_CLEAN" = "1" ] && [ "$STAMPED_DIRTY" = "true" ]; then
      echo "EXPORT_STAMP_FAIL dirty_build stamp says the tracked tree was dirty at build time" >&2
      exit 6
    fi
    echo "EXPORT_STAMP_OK git=$STAMPED_HEAD dirty=$STAMPED_DIRTY godot=$STAMPED_GODOT binary=$(basename "$BINARY") binary_sha=$BIN_SHA binary_bytes=$BIN_BYTES pck=$PCK_OUT pck_sha=$PCK_SHA pck_bytes=$PCK_BYTES stamp=$STAMP"
    ;;

  *)
    echo "usage: $0 write|verify --root=<repo> --binary=<path> [--stamp=<path>] [--preset=<name>] [--require-clean]" >&2
    exit 2
    ;;
esac
