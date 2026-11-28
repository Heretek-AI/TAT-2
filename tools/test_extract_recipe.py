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
  * ``extract`` runs list, raw, tables, levels, nav (with the exact regex as
    one argv and a closed quote), meshes, materials, audio, textures,
    cubemaps --overwrite, anims — in that order;
  * the standalone Destructibles ``json`` stage is NOT in ``extract``;
  * ``make json`` passes the resolved ``--usmap`` path, ``--fail-on-error``
    and the Destructibles filter;
  * ``make json`` fails with exit 2 when no mapping file resolves, and
    propagates a failing extractor as non-zero.
"""

from __future__ import annotations

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

        # 1. `make extract` reaches every stage, including cubemaps after nav.
        proc = run_make(
            ["extract", f"EX={stub}"],
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
            ["cubemaps", "--overwrite"],
            ["anims"],
        ]
        check(rows == expected, "make extract runs the exact command order", f"{rows}")
        check(
            not any(r and r[0] == "json" for r in rows),
            "make extract no longer repeats the Destructibles json stage",
        )
        check(
            rows[-2] == ["cubemaps", "--overwrite"],
            "cubemaps --overwrite is reached after the nav filter",
        )
        log.unlink()

        # 2. The nav regex is one argv with its closing quote intact.
        nav = next(r for r in rows if r and r[0] == "nav")
        check(
            nav[-1] == "Maps/(Guildhall|OldManor|FTUE)/.*\\.umap$",
            "the nav filter arrives closed and unmodified",
            nav[-1],
        )

        # 3. `make json`: resolved usmap + fail-on-error + filter.
        usmap = base / "TAT-test.usmap"
        usmap.write_bytes(b"fixture")
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

        # 4. `make json` with no mapping file fails closed (exit 2).
        # Run from an empty temp cwd with empty GIT_COMMON/MAIN_CHECKOUT so no
        # wildcard can find a real usmap; the recipe still comes from ROOT.
        no_repo = base / "no-repo"
        no_repo.mkdir()
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

        # 5. A failing extractor makes `make json` non-zero.
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
