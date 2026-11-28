#!/usr/bin/env python3
"""Fail-closed test manifest for the TAT-2 headless gate set.

Every ``game/tests/**/*.gd`` must be reachable from one of the three entry
points the final runner owns:

  * ``game/tests/run_tests.gd`` (the ``make test`` suite),
  * ``game/tests/e2e/run_e2e_tests.gd`` (the E2E tiers), or
  * ``build/qa/run_final_gates.sh`` -- including its ``build/qa/*.sh``
    wrappers, which may launch a test themselves.

Reachability is transitive and syntactic: a reference counts only when it is a
real execution path -- a ``load()``/``preload()`` argument, a ``--script``
argument, or a suite-table row (a list literal whose third string is the test
path, the convention ``run_tests.gd`` consumes with ``OS.execute``). A bare
string occurrence, an unused ``const``/``var`` holding a test path, or a
comment does NOT keep a dead test "reachable". A reference containing ``..`` or
an absolute path is rejected as unsafe.

Anything else must be named explicitly in ``build/qa/retired_tests.txt`` with a
reason. The manifest fails on:

  * an unlisted orphan,
  * a stale retired entry (missing path),
  * a retired entry that is also reachable (the list has drifted),
  * a malformed / duplicate retired entry.

Run: ``python3 build/qa/gate_manifest.py`` (or ``--root <dir>`` for a test
fixture). Exit 0 only when every test file is accounted for.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path, PurePosixPath

GD_LOAD = re.compile(r"\b(?:load|preload)\s*\(\s*[\"'](res://tests/[^\"']+\.gd)[\"']")
GD_SCRIPT = re.compile(r'--script["\']?\s*,?\s*["\']?(res://tests/[^"\'\s]+\.gd)["\']?')
# `["101", "description", "res://tests/x.gd", "MARKER"]` — the suite table that
# run_tests.gd feeds to OS.execute via str(entry[2]). A scalar const holding the
# same path does not match this list-literal form.
GD_SUITE = re.compile(r'\[\s*"[^"]*"\s*,\s*"[^"]*"\s*,\s*"(res://tests/[^"]+\.gd)"\s*,')
SH_SCRIPT = re.compile(r'--script[\s=]+["\']?(res://tests/[^"\'\s]+\.gd)["\']?')
# `$ROOT/build/qa/x.sh`, `build/qa/x.sh`; the leading group is just the path.
SH_REF = re.compile(r"((?:\$ROOT/)?build/qa/[A-Za-z0-9_./-]+\.sh)")
TEST_PREFIX = "game/tests/"
REASON_CODES = {"perf", "historical"}


def strip_gdscript_comments(text: str) -> str:
    """Drop `# ...` comments while keeping `#` inside string literals."""
    out: list[str] = []
    for line in text.splitlines():
        quote: str | None = None
        escaped = False
        buf: list[str] = []
        for ch in line:
            if quote is not None:
                buf.append(ch)
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == quote:
                    quote = None
            elif ch in ("'", '"'):
                quote = ch
                buf.append(ch)
            elif ch == "#":
                break
            else:
                buf.append(ch)
        out.append("".join(buf))
    return "\n".join(out)


def strip_shell_comments(text: str) -> str:
    """Drop shell comments (a `#` at the start of a word, outside quotes)."""
    out: list[str] = []
    for line in text.splitlines():
        quote: str | None = None
        escaped = False
        buf: list[str] = []
        for i, ch in enumerate(line):
            if quote is not None:
                buf.append(ch)
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == quote:
                    quote = None
            elif ch in ("'", '"'):
                quote = ch
                buf.append(ch)
            elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
                break
            else:
                buf.append(ch)
        out.append("".join(buf))
    return "\n".join(out)


def _normalize(raw: str) -> str:
    """Map an `res://tests/...` capture to a repo-relative path."""
    return "game/" + raw.removeprefix("res://")


def _safe_ref(raw: str) -> str | None:
    """Reject absolute paths and `..` components (repo-root escapes)."""
    rel = raw.removeprefix("$ROOT/")
    if rel.startswith("/") or rel.startswith("\\"):
        return None
    if ".." in PurePosixPath(rel).parts:
        return None
    return rel


def refs_in(path: Path) -> tuple[set[str], list[str]]:
    """Return (safe execution refs, unsafe refs) for a reachable file."""
    text = path.read_text(errors="replace")
    raw_refs: set[str] = set()
    if path.suffix == ".sh":
        text = strip_shell_comments(text)
        raw_refs |= {_normalize(m) for m in SH_SCRIPT.findall(text)}
        raw_refs |= set(SH_REF.findall(text))
    else:
        text = strip_gdscript_comments(text)
        for pattern in (GD_LOAD, GD_SCRIPT, GD_SUITE):
            raw_refs |= {_normalize(m) for m in pattern.findall(text)}

    refs: set[str] = set()
    unsafe: list[str] = []
    for raw in raw_refs:
        rel = _safe_ref(raw)
        if rel is None:
            unsafe.append(raw)
        else:
            refs.add(rel)
    return refs, unsafe


def resolve(root: Path, rel: str) -> Path:
    candidate = (root / rel).resolve()
    # Defense in depth: even a sanitized ref must stay under the fixture root.
    candidate.relative_to(root.resolve())
    return candidate


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        default=None,
        help="repository root (default: the parent of build/qa this file lives in)",
    )
    args = ap.parse_args(argv)
    root = (
        Path(args.root).resolve()
        if args.root
        else Path(__file__).resolve().parent.parent.parent
    )

    tests_dir = root / "game/tests"
    runner = root / "build/qa/run_final_gates.sh"
    retired_path = root / "build/qa/retired_tests.txt"

    problems: list[str] = []

    def fail(msg: str) -> None:
        problems.append(msg)
        print(f"FAIL: {msg}")

    if not tests_dir.is_dir():
        print(f"FAIL: missing test directory {tests_dir}")
        return 1
    if not runner.is_file():
        print(f"FAIL: missing final runner {runner}")
        return 1
    if not retired_path.is_file():
        print(f"FAIL: missing retired list {retired_path}")
        return 1

    all_tests = sorted(p.relative_to(root).as_posix() for p in tests_dir.rglob("*.gd"))

    # Transitive reachability from the three entry points.
    reachable: set[str] = set()
    pending: list[str] = [
        "game/tests/run_tests.gd",
        "game/tests/e2e/run_e2e_tests.gd",
        "build/qa/run_final_gates.sh",
    ]
    while pending:
        rel = pending.pop()
        if rel in reachable:
            continue
        try:
            path = resolve(root, rel)
        except ValueError:
            fail(f"reference escapes the repo root: {rel}")
            continue
        if not path.is_file():
            fail(f"entry point or reference does not exist: {rel}")
            continue
        reachable.add(rel)
        refs, unsafe = refs_in(path)
        for raw in unsafe:
            fail(f"unsafe reference from {rel}: {raw!r} (absolute or contains '..')")
        for ref in refs:
            if ref.endswith(".gd") or ref.endswith(".sh"):
                pending.append(ref)

    # The manifest itself is not a test file; the entry points are.
    reachable_tests = {
        rel for rel in reachable if rel.startswith(TEST_PREFIX) and rel.endswith(".gd")
    }

    retired: dict[str, str] = {}
    for lineno, raw in enumerate(retired_path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            fail(
                f"{retired_path.name}:{lineno}: expected "
                f"'<path>TAB<reason-code>TAB<reason>', got {raw!r}"
            )
            continue
        rel = parts[0].strip()
        code = parts[1].strip()
        reason = "\t".join(parts[2:]).strip()
        if not rel.startswith(TEST_PREFIX) or not rel.endswith(".gd"):
            fail(f"{retired_path.name}:{lineno}: not a game/tests/*.gd path: {rel!r}")
            continue
        if code not in REASON_CODES:
            fail(
                f"{retired_path.name}:{lineno}: unknown reason code {code!r} "
                f"(expected one of {sorted(REASON_CODES)})"
            )
        if not reason:
            fail(f"{retired_path.name}:{lineno}: empty reason for {rel}")
        if rel in retired:
            fail(f"{retired_path.name}:{lineno}: duplicate retired entry {rel}")
            continue
        retired[rel] = reason
        if rel not in all_tests:
            fail(
                f"{retired_path.name}:{lineno}: stale entry {rel} does not exist — "
                "remove it from the retired list"
            )
        if rel in reachable_tests:
            fail(
                f"{retired_path.name}:{lineno}: {rel} is reachable from an entry "
                "point but is also listed as retired — remove the entry"
            )

    orphans = sorted(set(all_tests) - reachable_tests - set(retired))
    for rel in orphans:
        fail(
            f"orphan test {rel}: not reachable from run_tests.gd, an E2E tier or "
            "build/qa/run_final_gates.sh, and not listed in retired_tests.txt"
        )

    tracked = len(all_tests)
    print(
        "GATE_MANIFEST: "
        f"tracked={tracked} reachable={len(reachable_tests)} "
        f"retired={len(retired)} orphans={len(orphans)}"
    )
    if problems:
        print(f"\nGATE_MANIFEST: FAIL ({len(problems)} problem(s))")
        return 1
    print("GATE_MANIFEST: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
