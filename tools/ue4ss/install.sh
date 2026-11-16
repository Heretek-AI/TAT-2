#!/usr/bin/env bash
# Temporarily installs UE4SS into the game to dump Mappings.usmap. Reverted by uninstall.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WIN64="${TAT_GAME:-$HOME/.local/share/Steam/steamapps/common/Thick As Thieves}/TAT/Binaries/Win64"
[ -e "$WIN64/dwmapi.dll" ] && { echo "dwmapi.dll already present, refusing"; exit 1; }
cp "$HERE/cache/pkg/dwmapi.dll" "$WIN64/"
cp -r "$HERE/cache/pkg/ue4ss" "$WIN64/"
cp -r "$HERE/mod/TATAutoDump" "$WIN64/ue4ss/Mods/"
printf 'TATAutoDump : 1\nKeybinds : 1\n' > "$WIN64/ue4ss/Mods/mods.txt"
echo "installed into $WIN64"
