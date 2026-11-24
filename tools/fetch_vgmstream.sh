#!/usr/bin/env bash
# Download the pinned prebuilt vgmstream CLI (Linux x86_64) used to decode
# the extracted Wwise Vorbis-in-RIFF chunks (codec tag 0xFFFF), which
# neither Godot nor FFmpeg can decode.
#
# Pinned release: r2168
# URL: https://github.com/vgmstream/vgmstream/releases/download/r2168/vgmstream-linux.zip
# Usage: ./tools/fetch_vgmstream.sh   (or: make audio-tools)
set -euo pipefail

VERSION="r2168"
URL="https://github.com/vgmstream/vgmstream/releases/download/${VERSION}/vgmstream-linux.zip"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${ROOT}/tools/bin/vgmstream"
BIN="${DEST_DIR}/vgmstream-cli"

mkdir -p "${DEST_DIR}"

if [ -x "${BIN}" ]; then
    echo "vgmstream already present: ${BIN} ($("${BIN}" -h 2>&1 | head -1))"
    exit 0
fi

TMP_ZIP="$(mktemp)"
trap 'rm -f "${TMP_ZIP}"' EXIT

echo "Downloading vgmstream ${VERSION} ..."
curl -fSL --proto '=https' --retry 3 -o "${TMP_ZIP}" "${URL}"
unzip -o -j "${TMP_ZIP}" "vgmstream-cli" -d "${DEST_DIR}"
chmod +x "${BIN}"
echo "Installed: ${BIN}"
"${BIN}" -h 2>&1 | head -2
