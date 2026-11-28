#!/usr/bin/env python3
"""Executes the real Makefile recipes with a stub extractor.

Run with: ``python3 tools/test_extract_recipe.py``

Round 2 exists because round 1 proved the recipe with ``make -n`` only, which
cannot see shell quoting: ``$'`` on the nav filter was consumed by GNU make as
a one-character variable reference, so ``make extract`` reached the nav line
and died with an unmatched quote before ``cubemaps --overwrite``. These tests
run the recipe for real (``make -o build-extractor`` skips only the compile)
with ``EX`` pointing at a stub that logs its argv.

Pinned:
  * ``extract`` runs cubemaps (HDR pass, see below) then list, raw, tables,
    levels, nav (with the exact regex as one argv and a closed quote), meshes,
    materials, audio, textures, anims;
  * ``cubemaps`` (and therefore ``extract``) passes the resolved ``--usmap`` and
    ``--fail-on-error``: without the mapping an unversioned cube fails to load
    and the old 8-bit PNG faces survive while the command exits 0;
  * ``make extract`` fails closed (exit 2, nothing dumped) when no mapping file
    resolves, and propagates a failing extractor as non-zero;
  * the ``CUBEMAP_ROOT`` post-check refuses an 8-bit/PNG cube tree and a stale
    PNG beside an HDR manifest, so a silent 8-bit cubemap cannot pass;
  * the standalone Destructibles ``json`` stage is NOT in ``extract``;
  * ``make json`` passes the resolved ``--usmap`` path, ``--fail-on-error``
    and the Destructibles filter;
  * ``make json`` fails with exit 2 when no mapping file resolves, and
    propagates a failing extractor as non-zero.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
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


CUBE_FACES = ["px", "nx", "py", "ny", "pz", "nz"]


def write_cube(root: Path, cid: str, *, ext: str = ".hdr", hdr: bool = True) -> Path:
    """Minimal cube fixture: six face files + the manifest the extractor writes."""
    cube_dir = root / cid
    cube_dir.mkdir(parents=True)
    faces = {name: f"face_{name}{ext}" for name in CUBE_FACES}
    for rel in faces.values():
        (cube_dir / rel).write_bytes(b"fixture")
    (cube_dir / "cubemap.json").write_text(
        json.dumps(
            {
                "schema": "tat2.cubemap/1",
                "id": cid,
                "hdr": hdr,
                "encoding": "hdr" if hdr else "png",
                "transfer": "linear",
                "face_order": CUBE_FACES,
                "faces": faces,
            }
        )
    )
    return cube_dir


def write_stub(base: Path) -> Path:
    stub = base / "stub-extract"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        "{\n"
        '  printf "CMD"\n'
        '  for a in "$@"; do printf "\\t%s" "$a"; done\n'
        '  printf "\\n"\n'
        '} >> "${STUB_LOG:?}"\n'
        'exit "${STUB_EXIT:-0}"\n'
    )
    stub.chmod(0o755)
    return stub


def parse_log(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in path.read_text().splitlines():
        if not line:
            continue
        parts = line.split("\t")
        if parts[0] != "CMD":
            raise AssertionError(f"stub log line is not CMD: {line!r}")
        rows.append(parts[1:])
    return rows


def run_make(
    args: list[str],
    env_extra: dict,
    cwd: Path = ROOT,
) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.update(env_extra)
    return subprocess.run(
        ["make", "-o", "build-extractor", "-f", str(MAKEFILE), *args],
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def quote_errors(text: str) -> list[str]:
    lowered = text.lower()
    needles = (
        "unterminated quoted string",
        "unexpected eof while looking for matching",
        "syntax error",
        "missing separator",
    )
    return [n for n in needles if n in lowered]


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        stub = write_stub(base)
        log = base / "argv.log"
        usmap = base / "TAT-test.usmap"
        usmap.write_bytes(b"fixture")
        # A complete HDR cube tree: the `cubemaps` post-check runs against it.
        good_root = base / "cubemaps-hdr"
        write_cube(good_root, "cubemap_ground_floor_01")

        # 1. `make extract` reaches every stage; cubemaps runs first (it is a
        #    prerequisite) so a missing mapping fails before any dump.
        proc = run_make(
            ["extract", f"EX={stub}", f"USMAP={usmap}", f"CUBEMAP_ROOT={good_root}"],
            {"STUB_LOG": str(log)},
        )
        check(
            proc.returncode == 0,
            "make extract exits 0 with a stub extractor",
            f"rc={proc.returncode} stderr={proc.stderr[-400:]}",
        )
        errors = quote_errors(proc.stderr)
        check(not errors, "make extract has no shell quote/syntax error", str(errors))
        rows = parse_log(log)
        expected = [
            ["cubemaps", "--overwrite", "--usmap", str(usmap), "--fail-on-error"],
            ["list"],
            ["raw"],
            ["tables"],
            ["levels"],
            [
                "nav",
                "--overwrite",
                "--filter",
                "Maps/(Guildhall|OldManor|FTUE)/.*\\.umap$",
            ],
            ["meshes"],
            ["materials", "--overwrite"],
            ["audio"],
            ["textures"],
            ["anims"],
        ]
        check(rows == expected, "make extract runs the exact command order", f"{rows}")
        check(
            not any(r and r[0] == "json" for r in rows),
            "make extract no longer repeats the Destructibles json stage",
        )
        check(
            rows[0][:2] == ["cubemaps", "--overwrite"],
            "cubemaps runs first and is reached before the nav filter",
        )
        check(
            rows[0][2:] == ["--usmap", str(usmap), "--fail-on-error"],
            "cubemaps passes the resolved --usmap and --fail-on-error",
            str(rows[0]),
        )
        log.unlink()

        # 2. The nav regex is one argv with its closing quote intact.
        nav = next(r for r in rows if r and r[0] == "nav")
        check(
            nav[-1] == "Maps/(Guildhall|OldManor|FTUE)/.*\\.umap$",
            "the nav filter arrives closed and unmodified",
            nav[-1],
        )

        # 3. The cubemaps post-check refuses an 8-bit/PNG tree (the measured
        #    pre-fix defect: quantized faces left behind).
        png_root = base / "cubemaps-png"
        write_cube(png_root, "cubemap_ground_floor_01", ext=".png", hdr=False)
        proc = run_make(
            ["extract", f"EX={stub}", f"USMAP={usmap}", f"CUBEMAP_ROOT={png_root}"],
            {"STUB_LOG": str(log)},
        )
        check(
            proc.returncode != 0,
            "make extract fails when the cube tree is still 8-bit PNG",
            f"rc={proc.returncode}",
        )
        check(
            "CUBEMAP_EXPORT_CHECK FAIL" in proc.stdout,
            "the failure names the 8-bit faces",
            proc.stdout[-300:],
        )
        log.unlink()

        # 4. A stale PNG beside an HDR manifest is refused too.
        stale_root = base / "cubemaps-stale"
        stale_dir = write_cube(stale_root, "cubemap_ground_floor_01")
        (stale_dir / "face_px.png").write_bytes(b"stale")
        proc = run_make(
            ["extract", f"EX={stub}", f"USMAP={usmap}", f"CUBEMAP_ROOT={stale_root}"],
            {"STUB_LOG": str(log)},
        )
        check(
            proc.returncode != 0 and "stale 8-bit face" in proc.stdout,
            "make extract fails on a stale PNG beside an HDR manifest",
            f"rc={proc.returncode} stdout={proc.stdout[-300:]}",
        )
        log.unlink()

        # 5. No mapping file: `extract` fails closed before any dump.
        no_repo = base / "no-repo"
        no_repo.mkdir()
        proc = run_make(
            [
                "extract",
                f"EX={stub}",
                "USMAP=",
                "TAT_USMAP=",
                "GIT_COMMON=",
                "MAIN_CHECKOUT=",
                f"CUBEMAP_ROOT={good_root}",
            ],
            {"STUB_LOG": str(log)},
            cwd=no_repo,
        )
        check(
            proc.returncode == 2,
            "make extract without a .usmap exits 2",
            f"rc={proc.returncode}",
        )
        check(
            "no .usmap" in proc.stderr and "cubemaps" in proc.stderr,
            "the missing-mapping failure names the cubemaps pass",
            proc.stderr[-300:],
        )
        check(not log.exists(), "the no-usmap failure runs no dump")

        # 6. A failing extractor makes `make extract` non-zero.
        proc = run_make(
            ["extract", f"EX={stub}", f"USMAP={usmap}", f"CUBEMAP_ROOT={good_root}"],
            {"STUB_LOG": str(log), "STUB_EXIT": "1"},
        )
        check(
            proc.returncode != 0,
            "make extract propagates a failing cubemaps dump",
            f"rc={proc.returncode}",
        )
        log.unlink()

        # 7. `make json`: resolved usmap + fail-on-error + filter.
        proc = run_make(
            ["json", f"EX={stub}", f"USMAP={usmap}"],
            {"STUB_LOG": str(log)},
        )
        check(proc.returncode == 0, "make json exits 0 with a stub", proc.stderr[-300:])
        rows = parse_log(log)
        check(
            rows
            == [
                [
                    "json",
                    "--overwrite",
                    "--usmap",
                    str(usmap),
                    "--fail-on-error",
                    "--filter",
                    "Destructibles/",
                ]
            ],
            "make json passes --usmap/--fail-on-error/--filter",
            f"{rows}",
        )
        log.unlink()

        # 8. `make json` with no mapping file fails closed (exit 2).
        # Run from an empty temp cwd with empty GIT_COMMON/MAIN_CHECKOUT so no
        # wildcard can find a real usmap; the recipe still comes from ROOT.
        proc = run_make(
            [
                "json",
                f"EX={stub}",
                "USMAP=",
                "TAT_USMAP=",
                "GIT_COMMON=",
                "MAIN_CHECKOUT=",
            ],
            {"STUB_LOG": str(log)},
            cwd=no_repo,
        )
        check(
            proc.returncode == 2,
            "make json without a .usmap exits 2",
            f"rc={proc.returncode}",
        )
        check(
            "no .usmap" in proc.stderr,
            "the missing-mapping failure names the cause",
            proc.stderr[-300:],
        )
        check(not log.exists(), "the no-usmap failure runs no dump")

        # 9. A failing extractor makes `make json` non-zero.
        proc = run_make(
            ["json", f"EX={stub}", f"USMAP={usmap}"],
            {"STUB_LOG": str(log), "STUB_EXIT": "1"},
        )
        check(
            proc.returncode != 0,
            "make json propagates a failing dump",
            f"rc={proc.returncode}",
        )

    print(f"EXTRACT_RECIPE_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
