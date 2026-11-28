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

    # 5. Program.cs documents the command surface and can fail non-zero.
    program = PROGRAM.read_text()
    check(
        'case "json": ex.Json();' in program
        and 'case "cubemaps": ex.Cubemaps();' in program,
        "Program.cs still routes the json/cubemaps commands",
    )
    check(
        'case "--fail-on-error": o.FailOnError = true;' in program,
        "Program.cs accepts --fail-on-error",
    )
    check(
        "return opt.FailOnError && ex.FailCount > 0 ? 1 : 0;" in program,
        "a failed dump exits non-zero under --fail-on-error",
    )
    check(
        "public int FailCount => _fail.Values.Sum();" in src,
        "Exporter exposes the counted failure total",
    )

    # 4b. Cubemap path/swap hardening.
    check("SafeCubeId(CubeId(cube.Name))" in cubemaps, "cube ids are sanitised")
    check(
        "escapes {cubesRoot}" in cubemaps,
        "the cube directory is asserted under Cubemaps/",
    )
    check(
        cubemaps.index("if (!ok)")
        < cubemaps.index('Directory.GetFiles(dir, "face_*")'),
        "stale faces are deleted only after a successful encode",
    )
    check(
        cubemaps.index("File.WriteAllBytes(Path.Combine(dir, file), bytes)")
        < cubemaps.index("File.Move(tmpManifest, manifest, true)"),
        "the manifest is swapped in last",
    )

    # 6. Makefile: the nav filter survives make, json is standalone, cubemaps
    # is reached.
    make = MAKEFILE.read_text()
    json_target = slice_between(make, "json: build-extractor", "\nextract-json:")
    check(
        re.search(r"^json: build-extractor$", make, re.MULTILINE) is not None,
        "Makefile has a standalone json stage",
    )
    check(
        "--usmap '$(USMAP)'" in json_target,
        "make json passes the resolved mapping file",
    )
    check(
        "--fail-on-error" in json_target,
        "make json fails non-zero when a package dump fails",
    )
    check(
        "--filter 'Destructibles/'" in json_target,
        "make json is the filtered Destructibles dump",
    )
    check(
        re.search(r"^extract-json: json$", make, re.MULTILINE) is not None,
        "Makefile documents extract-json as an alias",
    )
    extract = slice_between(make, "extract: build-extractor", "\nanims:")
    check(
        "$(EX) json" not in extract,
        "make extract does not repeat the standalone Destructibles json stage",
    )
    check(
        "$(EX) cubemaps --overwrite" in extract,
        "make extract re-encodes cubemaps so HDR replaces stale PNG faces",
    )
    check(
        "$(EX) tables" in extract and "$(EX) levels" in extract,
        "make extract keeps the tables and levels stages",
    )
    # The round-1 bug: a bare `$'` is make's one-character variable reference.
    check(
        "\\.umap$$'" in extract,
        "the nav filter closes with $$' so make does not eat the quote",
    )
    check(
        re.search(r"(?<!\$)\$'", extract) is None,
        "no bare $' remains in the extract recipe",
    )
    nav_pos = extract.index("$(EX) nav")
    cube_pos = extract.index("$(EX) cubemaps")
    check(
        nav_pos < cube_pos,
        "cubemaps --overwrite is reached after the nav stage",
    )

    print(f"EXTRACTOR_CONFIG_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
