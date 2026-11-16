#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WIN64="${TAT_GAME:-$HOME/.local/share/Steam/steamapps/common/Thick As Thieves}/TAT/Binaries/Win64"
mkdir -p "$HERE/output"
find "$WIN64" -maxdepth 3 -name "*.usmap" -exec cp {} "$HERE/output/" \; || true
[ -d "$WIN64/ue4ss/CXXHeaderDump" ] && cp -r "$WIN64/ue4ss/CXXHeaderDump" "$HERE/output/" || true
[ -f "$WIN64/ue4ss/UE4SS.log" ] && cp "$WIN64/ue4ss/UE4SS.log" "$HERE/output/" || true
rm -rf "$WIN64/ue4ss" "$WIN64/dwmapi.dll" "$WIN64/TATAutoDump.done" "$WIN64"/*.usmap
echo "removed UE4SS; outputs in $HERE/output"
