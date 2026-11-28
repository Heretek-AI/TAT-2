#!/usr/bin/env python3
"""Executed regression for Exporter.FaceMeanLinear (stdlib only).

Run with: ``python3 tools/test_face_mean.py``

Round 3 exists because the round-2 "format support" was source-text only and
the function was gated on ``PixelFormatUtils.IsHDR``, which is false for
``PF_FloatRGB`` and ``PF_R32G32B32F`` — those switch arms were dead. Source
assertions cannot see a dead branch, so this test builds the extractor (when
the binary is missing or older than its sources) and runs the real function via
``tat-extract selftest-face-mean``, which needs no pak mount or game data.

Pinned: PF_FloatRGBA, PF_FloatRGB, PF_A32B32G32R32F, PF_R32G32B32F and PF_R16F
each return a non-null mean with the fixture values, and a non-float layout
returns null.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "tools" / "tat-extract" / "bin" / "Release" / "net10.0" / "tat-extract"
SOURCES = [
    ROOT / "tools" / "tat-extract" / "Exporter.cs",
    ROOT / "tools" / "tat-extract" / "Program.cs",
]

PASSED = 0
EXPECTED = {
    "PF_FloatRGBA": (0.25, 0.5, 0.75),
    "PF_FloatRGB": (0.25, 0.5, 0.75),
    "PF_A32B32G32R32F": (0.25, 0.5, 0.75),
    "PF_R32G32B32F": (0.25, 0.5, 0.75),
    "PF_R16F": (0.5, 0.5, 0.5),
}


def check(condition: bool, name: str, detail: str = "") -> None:
    global PASSED
    if not condition:
        message = f"FAIL: {name}"
        if detail:
            message += f" ({detail})"
        print(message)
        raise SystemExit(1)
    PASSED += 1
    print(f"PASS: {name}")


def ensure_binary() -> None:
    newest_source = max(p.stat().st_mtime for p in SOURCES)
    if BIN.is_file() and BIN.stat().st_mtime >= newest_source:
        return
    print("note: extractor binary missing/stale; running make build-extractor")
    proc = subprocess.run(
        ["make", "build-extractor"],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=600,
    )
    if proc.returncode != 0:
        print(proc.stdout[-2000:])
        print(proc.stderr[-2000:], file=sys.stderr)
        raise SystemExit("FAIL: make build-extractor failed")
    if not BIN.is_file():
        raise SystemExit(f"FAIL: build-extractor did not produce {BIN}")


def main() -> None:
    ensure_binary()
    proc = subprocess.run(
        [str(BIN), "selftest-face-mean"],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    check(
        proc.returncode == 0,
        "selftest-face-mean exits 0",
        f"rc={proc.returncode} stderr={proc.stderr[-400:]}",
    )
    lines = [line for line in proc.stdout.splitlines() if line.startswith("FACE_MEAN")]
    rows = {}
    pattern = re.compile(
        r"^FACE_MEAN format=(\w+) r=([-\d.]+) g=([-\d.]+) b=([-\d.]+) "
        r"null=(\w+) ok=(\w+)$"
    )
    for line in lines:
        m = pattern.match(line)
        if not m:
            continue
        rows[m.group(1)] = (
            float(m.group(2)),
            float(m.group(3)),
            float(m.group(4)),
            m.group(5) == "true",
            m.group(6) == "true",
        )
    for fmt, want in EXPECTED.items():
        check(fmt in rows, f"{fmt} produced a face mean", str(sorted(rows)))
        r, g, b, is_null, ok = rows[fmt]
        check(not is_null, f"{fmt} is non-null")
        check(ok, f"{fmt} matches the fixture", f"({r},{g},{b})")
        check(
            abs(r - want[0]) < 1e-3
            and abs(g - want[1]) < 1e-3
            and abs(b - want[2]) < 1e-3,
            f"{fmt} mean is {want}",
            f"({r},{g},{b})",
        )
    check(
        "FACE_MEAN_SELFTEST PASS formats=5" in proc.stdout,
        "the self-test reports PASS formats=5",
    )
    check(
        "FACE_MEAN_UNSUPPORTED format=PF_B8G8R8A8 null=true" in proc.stdout,
        "an unsupported layout is reported as null",
    )
    check(
        not any("null=true" in line and "UNSUPPORTED" not in line for line in lines),
        "no supported format is reported as null (dead-branch guard)",
    )
    print(f"FACE_MEAN_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
