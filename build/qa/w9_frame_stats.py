#!/usr/bin/env python3
"""W9-P0 frame statistics: mean / p50 / p95 / % pixels below 8 of 255.

Method — the exact pipeline lane L1 used for the 2026-11-24 review, and the one
the W9-P0 research lane reproduced against L1's published numbers:

    magick IMAGE -colorspace gray -resize 480x -depth 8 gray:-   -> histogram

i.e. ITU-R 601 grayscale on the sRGB-encoded values, downsampled to 480 px
wide with ImageMagick's default filter, then a 256-bin histogram. ``%<8`` is
the share of pixels with luma <= 7 (``hist[:8]``), the metric quoted in
COMPARISON_PORT_20261124.md and build/qa/review_20261124/findings/L1-render.md.
This is deliberately NOT ffmpeg YAVG (limited range) and NOT linear light.

A Pillow fallback (convert("L") + LANCZOS resize) is used only when ``magick``
is absent; it is close but not identical, so the method line says which ran.

Usage:
  /usr/bin/python3 build/qa/w9_frame_stats.py IMAGE [IMAGE ...] [--json] [--full]

  --full   skip the 480 px downsample (full-resolution histogram)
  --json   one JSON object per image

No file is written; the table goes to stdout.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

MAGICK = shutil.which("magick") or shutil.which("convert")


def _histogram_magick(path: Path, resize: bool) -> list[int]:
    cmd = [MAGICK, str(path), "-colorspace", "gray"]
    if resize:
        cmd += ["-resize", "480x"]
    cmd += ["-depth", "8", "gray:-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    hist = [0] * 256
    for byte in raw:
        hist[byte] += 1
    return hist


def _histogram_pillow(path: Path, resize: bool) -> list[int]:
    from PIL import Image  # noqa: PLC0415 - optional fallback only

    im = Image.open(path).convert("L")
    if resize:
        width = 480
        height = max(1, round(im.height * width / im.width))
        im = im.resize((width, height), Image.LANCZOS)
    return im.histogram()


def stats(path: Path, resize: bool = True) -> dict:
    if MAGICK:
        hist = _histogram_magick(path, resize)
        method = "magick-gray" + ("-resize480" if resize else "")
    else:
        hist = _histogram_pillow(path, resize)
        method = "pillow-gray" + ("-lanczos480" if resize else "")
    total = sum(hist)
    if total <= 0:
        raise ValueError(f"{path}: empty image")

    def pct_at(fraction: float) -> float:
        target = total * fraction
        acc = 0
        for level, count in enumerate(hist):
            acc += count
            if acc >= target:
                return float(level)
        return 255.0

    return {
        "file": str(path),
        "method": method,
        "samples": total,
        "mean": sum(level * count for level, count in enumerate(hist)) / total,
        "p50": pct_at(0.50),
        "p95": pct_at(0.95),
        "pct_lt8": sum(hist[:8]) / total * 100.0,
        "pct_lt16": sum(hist[:16]) / total * 100.0,
        "pct_gt200": sum(hist[201:]) / total * 100.0,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("images", nargs="+", type=Path)
    ap.add_argument(
        "--json", action="store_true", help="print one JSON object per image"
    )
    ap.add_argument(
        "--full",
        action="store_true",
        help="full-resolution histogram (no 480 px resize)",
    )
    args = ap.parse_args()
    rows = []
    for path in args.images:
        if not path.is_file():
            print(f"MISSING {path}", file=sys.stderr)
            return 2
        row = stats(path, resize=not args.full)
        rows.append(row)
        if not args.json:
            print(
                f"{path.name}\t{row['samples']}px\tmean={row['mean']:.1f}\t"
                f"p50={row['p50']:.0f}\tp95={row['p95']:.0f}\t"
                f"lt8={row['pct_lt8']:.1f}%\tlt16={row['pct_lt16']:.1f}%\t"
                f"gt200={row['pct_gt200']:.2f}%"
            )
    if args.json:
        for row in rows:
            print(json.dumps(row, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
