#!/usr/bin/env python3
"""Tests for the tat-extract source configuration (stdlib only).

Run with: ``python3 tools/test_extractor_config.py``

The extractor has no unit harness (it needs the private pak mount), so the
filter/scope contract is pinned at the source level:
  * ``Destructibles/`` is a ``tables`` root (GC_ChestTrunkALid is dumped);
  * the ``levels`` predicate queues ``LS_`` LevelSequence packages;
  * HDR texture export is scoped to ``CubemapOpts`` / the ``cubemaps`` command
    only — the default and anim passes stay 8-bit;
  * the Makefile runs the filtered Destructibles json stage and re-encodes
    cubemaps so a stale 8-bit face cannot survive.

These are source assertions, not a claim that the private extraction ran.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPORTER = ROOT / "tools" / "tat-extract" / "Exporter.cs"
PROGRAM = ROOT / "tools" / "tat-extract" / "Program.cs"
MAKEFILE = ROOT / "Makefile"

PASSED = 0


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


def slice_between(source: str, start: str, end: str) -> str:
    """Source from `start` up to the next `end` (both markers excluded)."""
    a = source.index(start)
    b = source.index(end, a + len(start))
    return source[a:b]


def main() -> None:
    src = EXPORTER.read_text()
    lines = src.splitlines()

    # 1. Destructibles is a tables root.
    roots_line = next(line for line in lines if "var roots = new[]" in line).strip()
    check(
        '"TAT/Content/Destructibles/"' in roots_line,
        "tables roots include TAT/Content/Destructibles/",
        roots_line[:200],
    )
    # Negative: no accidental sibling prefix without the trailing slash.
    check(
        '"TAT/Content/Destructibles"'
        not in roots_line.replace('"TAT/Content/Destructibles/"', ""),
        "the Destructibles root keeps its trailing slash",
    )

    # 2. The levels predicate queues LS_ packages.
    levels = slice_between(
        src,
        "public void Levels()",
        "// Material packages referenced by mesh sidecars",
    )
    check('StartsWith("LS_")' in levels, "levels() queues LS_ level-sequence packages")
    check('EndsWith(".umap")' in levels, "levels() still queues .umap packages")
    # Negative: LS_ is a file-name prefix, never a path substring.
    check(
        'Path.GetFileName(f.Path).StartsWith("LS_")' in levels,
        "LS_ is a file-name prefix, not a path substring",
    )

    # 3. HDR scope: only CubemapOpts promotes HDR.
    default_body = slice_between(
        src,
        "ExportOptions DefaultOpts()",
        "ExportOptions AnimOpts()",
    )
    check(
        "exportHdrTexturesAsHdr: false" in default_body,
        "DefaultOpts stays non-HDR (other texture passes unchanged)",
    )
    anim = slice_between(src, "ExportOptions AnimOpts()", "ExportOptions CubemapOpts()")
    check("exportHdrTexturesAsHdr: false" in anim, "AnimOpts stays non-HDR")
    cube_opts = slice_between(
        src, "ExportOptions CubemapOpts()", "// Textures referenced by material dumps"
    )
    check(
        "exportHdrTexturesAsHdr: true" in cube_opts,
        "CubemapOpts sets exportHdrTexturesAsHdr true",
    )
    cubemaps = slice_between(
        src,
        "public void Cubemaps()",
        "// ------------------------------------------------------------------- navmesh",
    )
    check(
        "var opts = CubemapOpts();" in cubemaps,
        "the cubemaps command uses CubemapOpts",
    )
    # Negative: exactly one HDR-true construction exists, and the cubemaps
    # command no longer uses the 8-bit default opts.
    check(
        src.count("exportHdrTexturesAsHdr: true") == 1,
        "exactly one method hard-codes HDR true (CubemapOpts)",
        str(src.count("exportHdrTexturesAsHdr: true")),
    )
    check(
        "var opts = DefaultOpts();" not in cubemaps,
        "the cubemaps command no longer uses the 8-bit default opts",
    )

    # 4. The cubemap manifest records the linear/HDR truth and the real mean.
    check('["hdr"] = hdrEncoded' in cubemaps, "the cubemap manifest records hdr")
    check(
        '["transfer"] = hdrEncoded ? "linear"' in cubemaps,
        "an HDR cube is always labelled linear",
    )
    check(
        'doc["face_mean_linear"] = meansLinear' in cubemaps,
        "the cubemap manifest records the unclamped linear face mean",
    )
    check(
        "FaceMeanLinear(" in src and "PixelFormatUtils.IsHDR" in src,
        "the linear mean is read from HDR raw formats, not a guessed gamma",
    )
    # Negative: the old clamped 8-bit mean is never used as the HDR energy.
    check(
        "face_mean_8bit" in cubemaps and "meansLinear" in cubemaps,
        "8-bit means and linear means are recorded separately",
    )

    # 5. Program.cs documents the command surface.
    program = PROGRAM.read_text()
    check(
        'case "json": ex.Json();' in program
        and 'case "cubemaps": ex.Cubemaps();' in program,
        "Program.cs still routes the json/cubemaps commands",
    )

    # 6. Makefile: filtered Destructibles stage + cubemap re-encode.
    make = MAKEFILE.read_text()
    check(
        re.search(r"^json: build-extractor$", make, re.MULTILINE) is not None,
        "Makefile has a standalone json stage",
    )
    check(
        "$(EX) json --overwrite --filter 'Destructibles/'" in make,
        "make extract runs the filtered Destructibles json stage",
    )
    check(
        re.search(r"^extract-json: json$", make, re.MULTILINE) is not None,
        "Makefile documents extract-json as an alias",
    )
    check(
        "$(EX) cubemaps --overwrite" in make,
        "make extract re-encodes cubemaps so HDR replaces stale PNG faces",
    )
    extract = slice_between(make, "extract: build-extractor", "\nanims:")
    check(
        "$(EX) tables" in extract and "$(EX) levels" in extract,
        "make extract keeps the tables and levels stages",
    )
    check(
        "$(EX) json"
        not in slice_between(make, "extract-json: json", "\nextract: build-extractor"),
        "extract-json is an alias, not a second json dump",
    )

    print(f"EXTRACTOR_CONFIG_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
