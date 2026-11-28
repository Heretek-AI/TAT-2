#!/usr/bin/env python3
"""Executed regression for Exporter.FaceMeanLinear (stdlib only).

Run with: ``python3 tools/test_face_mean.py``

Round 3 added a self-test because a source-text assertion cannot see a dead
branch. Round 4 tightened it to the layouts the pinned CUE4Parse
1.2.2.202611 actually supports:
  * ``PF_FloatRGB`` was removed — it is R11G11B10_FLOAT in 4 bytes, not 3 x
    half, and the old 6-byte fixture fabricated a layout;
  * ``PF_R32G32B32F`` was removed — it is ``Supported=false`` in the pinned
    library, so ``Decode`` throws before the mean is ever computed;
  * ``PF_A32B32G32R32F`` is read in the library's ``ToHdrBitmap`` flip order
    (components 3/2/1), so the mean describes the exported face.

The test builds the extractor when the binary is missing/stale and runs the
real function via ``tat-extract selftest-face-mean`` (no pak mount or game
data). Every set member must be ``Supported`` and encodable by the writer.
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
    # format: (r, g, b, block_bytes, components)
    "PF_FloatRGBA": (0.25, 0.5, 0.75, 8, 4),
    "PF_A32B32G32R32F": (0.25, 0.5, 0.75, 16, 4),
    "PF_R32_FLOAT": (0.5, 0.5, 0.5, 4, 1),
    "PF_R16F": (0.5, 0.5, 0.5, 2, 1),
}
EXCLUDED = {
    # format: (library_supported, block_bytes)
    "PF_FloatRGB": (True, 4),  # R11G11B10_FLOAT, not 3 x half
    "PF_R32G32B32F": (False, 12),  # Supported=false: Decode throws
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
    out = proc.stdout

    layout = {}
    for m in re.finditer(
        r"^FACE_MEAN_LAYOUT format=(\w+) block_bytes=(-?\d+) components=(-?\d+) "
        r"supported=(\w+)$",
        out,
        re.MULTILINE,
    ):
        layout[m.group(1)] = (
            int(m.group(2)),
            int(m.group(3)),
            m.group(4) == "true",
        )
    means = {}
    for m in re.finditer(
        r"^FACE_MEAN format=(\w+) r=([-\d.]+) g=([-\d.]+) b=([-\d.]+) "
        r"null=(\w+) ok=(\w+)$",
        out,
        re.MULTILINE,
    ):
        means[m.group(1)] = (
            float(m.group(2)),
            float(m.group(3)),
            float(m.group(4)),
            m.group(5) == "true",
            m.group(6) == "true",
        )
    encodes = {}
    for m in re.finditer(
        r"^FACE_MEAN_ENCODE format=(\w+) ext=(\w+) bytes=(\d+) ok=(\w+)$",
        out,
        re.MULTILINE,
    ):
        encodes[m.group(1)] = (m.group(2), int(m.group(3)), m.group(4) == "true")

    for fmt, (want_r, want_g, want_b, want_bytes, want_comps) in EXPECTED.items():
        check(fmt in layout, f"{fmt} has a library layout", str(sorted(layout)))
        block_bytes, components, supported = layout[fmt]
        check(
            block_bytes == want_bytes and components == want_comps,
            f"{fmt} uses the library block bytes/components ({want_bytes}/{want_comps})",
            f"{block_bytes}/{components}",
        )
        check(supported, f"{fmt} is Supported in the pinned library")
        check(fmt in means, f"{fmt} produced a face mean", str(sorted(means)))
        r, g, b, is_null, ok = means[fmt]
        check(not is_null, f"{fmt} is non-null")
        check(ok, f"{fmt} matches the fixture", f"({r},{g},{b})")
        check(
            abs(r - want_r) < 1e-3
            and abs(g - want_g) < 1e-3
            and abs(b - want_b) < 1e-3,
            f"{fmt} mean is ({want_r},{want_g},{want_b})",
            f"({r},{g},{b})",
        )
        check(fmt in encodes, f"{fmt} was encoded by the writer", str(sorted(encodes)))
        ext, size, enc_ok = encodes[fmt]
        check(
            ext == "hdr" and size > 0 and enc_ok,
            f"{fmt} encodes as .hdr",
            f"{ext}/{size}",
        )

    check(
        "FACE_MEAN_SELFTEST PASS formats=4" in out,
        "the self-test reports PASS formats=4",
    )
    check(
        "FACE_MEAN_UNSUPPORTED format=PF_B8G8R8A8 null=true" in out,
        "an unsupported layout is reported as null",
    )
    for fmt, (want_supported, want_bytes) in EXCLUDED.items():
        m = re.search(
            rf"^FACE_MEAN_EXCLUDED format={fmt} in_set=(\w+) "
            rf"library_supported=(\w+) block_bytes=(-?\d+)$",
            out,
            re.MULTILINE,
        )
        check(m is not None, f"{fmt} is reported as excluded", out[-500:])
        assert m is not None
        check(m.group(1) == "false", f"{fmt} is not in the readable set")
        check(
            (m.group(2) == "true") == want_supported,
            f"{fmt} matches the pinned library Supported flag",
            m.group(2),
        )
        check(
            int(m.group(3)) == want_bytes,
            f"{fmt} block bytes are the library value ({want_bytes})",
            m.group(3),
        )
    check(
        not any(
            "null=true" in line and "UNSUPPORTED" not in line
            for line in out.splitlines()
        ),
        "no supported format is reported as null (dead-branch guard)",
    )
    print(f"FACE_MEAN_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
