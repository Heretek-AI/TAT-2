#!/usr/bin/env python3
"""Convert Unreal Engine .locres localization resources to Godot translation CSVs.

The shipped game localizes through FText keys (GUID-style namespace/key pairs) resolved
against Game.locres, not through per-culture StringTable assets. This tool decodes the
Optimized_CRC32 layout used by UE 5.5 (the same layout CUE4Parse implements) and emits one
CSV per culture that Godot imports as a Translation:

    keys,<locale>
    <namespace>.<key>,<localized text>

Usage:
    python3 tools/parse_locres.py [--locres-dir DIR] [--out-dir DIR] [--quiet]

Exit codes: 0 success, 1 no locales found or a parse error.
"""

from __future__ import annotations

import argparse
import csv
import json
import struct
import sys
from pathlib import Path

MAGIC = bytes.fromhex("0e147475674a03fc4a15909dc3377f1b")

# ELocResVersion: Legacy=0, Compact=1, Optimized_CRC32=2, Optimized_CityHash64_UTF16=3
VERSION_COMPACT = 1
VERSION_OPTIMIZED_CRC32 = 2

LOCALES = ["de-DE", "en", "es-ES", "fr-FR", "ja-JP", "pt-BR", "zh-Hans", "zh-Hant"]


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0

    def u8(self) -> int:
        value = self.data[self.pos]
        self.pos += 1
        return value

    def u32(self) -> int:
        value = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return value

    def i32(self) -> int:
        value = struct.unpack_from("<i", self.data, self.pos)[0]
        self.pos += 4
        return value

    def i64(self) -> int:
        value = struct.unpack_from("<q", self.data, self.pos)[0]
        self.pos += 8
        return value

    def skip(self, count: int) -> None:
        self.pos += count

    def fstring(self) -> str:
        length = self.i32()
        if length == 0:
            return ""
        if length < 0:
            raw = self.data[self.pos : self.pos + (-length) * 2]
            self.pos += (-length) * 2
            text = raw.decode("utf-16-le", errors="replace")
        else:
            raw = self.data[self.pos : self.pos + length]
            self.pos += length
            text = raw.decode("utf-8", errors="replace")
        return text.rstrip("\x00")

    def seek(self, pos: int) -> None:
        self.pos = pos


def parse_locres(data: bytes) -> dict[str, str]:
    """Return {"namespace.key": localized_text} for one .locres file."""
    r = Reader(data)
    magic = data[:16]
    if magic != MAGIC:
        raise ValueError(f"unexpected locres magic {magic.hex()}")
    r.skip(16)
    version = r.u8()
    if version > 3:
        raise ValueError(f"unsupported locres version {version}")

    strings: list[str] = []
    if version >= VERSION_COMPACT:
        lut_offset = r.i64()
        if lut_offset != -1:
            restore = r.pos
            r.seek(lut_offset)
            count = r.i32()
            strings = []
            for _ in range(count):
                strings.append(r.fstring())
                if version >= VERSION_OPTIMIZED_CRC32:
                    r.i32()  # RefCount, interleaved per entry
            r.seek(restore)

    if version >= VERSION_OPTIMIZED_CRC32:
        r.skip(4)  # total entry count

    entries: dict[str, str] = {}
    namespace_count = r.u32()
    for _ in range(namespace_count):
        if version >= VERSION_OPTIMIZED_CRC32:
            r.u32()  # namespace CRC32
        namespace = r.fstring()
        key_count = r.u32()
        for _ in range(key_count):
            if version >= VERSION_OPTIMIZED_CRC32:
                r.u32()  # key CRC32
            key = r.fstring()
            r.u32()  # source string CRC32
            if version >= VERSION_COMPACT:
                index = r.i32()
                text = strings[index] if 0 <= index < len(strings) else ""
            else:
                text = r.fstring()
            entries[f"{namespace}.{key}" if namespace else key] = text
    return entries


def write_csv(out_path: Path, locale: str, entries: dict[str, str]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["keys", locale])
        for key in sorted(entries):
            writer.writerow([key, entries[key]])


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--locres-dir",
        default=str(root / "extracted/raw/TAT/Content/Localization/Game"),
    )
    parser.add_argument(
        "--out-dir", default=str(root / "game/data/generated/localization")
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    locres_dir = Path(args.locres_dir)
    out_dir = Path(args.out_dir)
    written = 0
    missing: list[str] = []
    for locale in LOCALES:
        source = locres_dir / locale / "Game.locres"
        if not source.is_file():
            missing.append(locale)
            continue
        entries = parse_locres(source.read_bytes())
        write_csv(out_dir / f"{locale}.csv", locale, entries)
        if locale == "en":
            # Runtime reverse-map source: CSV imports are remapped in exported
            # builds, so Loc reads this JSON (key -> English source) instead of
            # the raw CSV. It is a normal runtime data file.
            (out_dir / "sources.json").write_text(
                json.dumps(entries, ensure_ascii=False, sort_keys=True),
                encoding="utf-8",
            )
        written += 1
        if not args.quiet:
            print(f"  {locale}: {len(entries)} keys -> {out_dir / (locale + '.csv')}")

    if missing:
        print(f"ERROR: missing .locres for {', '.join(missing)}", file=sys.stderr)
        return 1
    if written == 0:
        print("ERROR: no locales converted", file=sys.stderr)
        return 1
    print(f"locres: {written} locales written to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
