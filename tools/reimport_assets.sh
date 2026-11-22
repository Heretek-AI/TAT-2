#!/usr/bin/env bash
# P2-7: reimport step for extracted GLBs. Re-exporting a GLB with different
# CUE4Parse conversion settings without reimport leaves Godot rendering the
# stale imported mesh (995 .glb.import files under game/assets/ue/ carry
# source mtimes + import params). Run this after `make extract` (or any
# subset re-parse) and before `make test` so .godot/imported/ matches disk.
#
# Usage: tools/reimport_assets.sh [--check]
#   --check: fail without importing if any .glb under game/assets/ue/ is
#            newer than its .glb.import sidecar (staleness probe for CI).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-tools/godot}"
# game/assets/ue/Raw -> extracted/assets and game/assets/ue/Content -> extracted/assets/TAT/Content,
# so Godot sees the TAT tree through two res:// routes and reports duplicate UIDs. The
# ignore must sit at the physical TAT root; placing it under Content/ would hide every mesh.
GDIGNORE="$ROOT/extracted/assets/TAT/.gdignore"

if [[ "${1:-}" == "--check" ]]; then
    if [[ ! -f "$GDIGNORE" ]]; then
        echo "MISSING: $GDIGNORE (duplicate UID scans will return)" >&2
        exit 1
    fi
    stale=0
    # -L: the extracted GLBs live behind the game/assets/ue symlinks; a plain find
    # never descends into them and silently skips 2,058 files.
    while IFS= read -r glb; do
        if [[ "$glb" -nt "$glb.import" ]]; then
            echo "STALE: $glb newer than $glb.import"
            stale=1
        fi
    done < <(find -L "$ROOT/game/assets/ue" -name '*.glb')
    if [[ "$stale" == 1 ]]; then
        echo "reimport needed: run tools/reimport_assets.sh" >&2
        exit 1
    fi
    echo "reimport check: all .glb.import sidecars fresh"
    exit 0
fi

# Full headless import: re-runs the Godot import pipeline over game/.
# Recreate the duplicate-UID ignore first: it must exist before any scan.
mkdir -p "$(dirname "$GDIGNORE")"
: > "$GDIGNORE"
$GODOT --headless --path "$ROOT/game" --import
echo "reimport done"
