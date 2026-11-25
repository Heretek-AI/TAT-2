#!/usr/bin/env python3
"""Fail-closed consumer audit: every normalised output needs a reader.

``make audit`` has always proved that a producer *ran* (output hash + file
count) and that a table file *exists*. It has never proved that anything reads
it, so on the W7 tree 103 of 144 normalised tables and nine analysis/manifest
JSON files were unreachable from ``game/src`` while the gate was green
(RE-A-03, RE-A-09, RE-A-12). This checker closes that hole: an output is either
reachable from the runtime, or it is named in ``tools/consumer_allowlist.json``
with a reason and (where applicable) the team that owes the consumer.

What counts as "reachable"
--------------------------
Tables (``game/data/generated/tables/**``):
  1. the file sits in a directory ``game/src/core/game_data.gd`` loads through
     ``_load_tables_from_dir("res://data/generated/tables/<dir>", <recursive>)``
     -- the roots are **parsed from the GDScript**, never hardcoded here, so
     adding a root in the runtime widens the audit automatically; or
  2. the file's stem appears as a literal (``<stem>.json``) somewhere in
     ``game/src/**/*.gd``.

Every other generated JSON (``generated/*.json``, ``generated/gameplay/*.json``,
``generated/weather/*.json``, ``generated/vfx/*.json``):
  the relative path (``gameplay/quests.json``) or the basename appears in
  ``game/src/**/*.gd``. A basename that appears only under ``game/tests/**`` is
  reported as ``tests_only`` -- a weaker class that still needs a rule saying so.

The allowlist (``tools/consumer_allowlist.json``)
-------------------------------------------------
Each rule is ``{glob, kind, reason[, consumer][, owner]}``. The checker fails
when:

* an unreachable file matches no rule (``UNCONSUMED``);
* a rule matches no file (``STALE RULE``) -- so the allowlist cannot rot;
* a rule has an empty ``reason``;
* ``kind`` is not one of the known classes;
* ``kind == "blocked_on_team"`` and no ``owner`` is named;
* a rule names a ``consumer`` file that does not exist, or that exists but
  never mentions the rule's directory stem or basename (an unverifiable claim).

Globs are ``pathlib``-style and are matched against the path relative to
``game/data/generated`` (``tables/StringTables/**``), using ``PurePosixPath.match``
so ``**`` spans directories.

Usage::

    python3 tools/check_consumers.py                    # gate
    python3 tools/check_consumers.py --list-unconsumed   # same, print every row
    python3 tools/check_consumers.py --json              # machine summary
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GENERATED = ROOT / "game" / "data" / "generated"
DEFAULT_SRC = ROOT / "game" / "src"
DEFAULT_TESTS = ROOT / "game" / "tests"
DEFAULT_ALLOWLIST = ROOT / "tools" / "consumer_allowlist.json"

KINDS = {
    "text_via_locres": "the same strings reach the runtime through localization/*.csv",
    "folded_into_aggregate": "the authored rows are folded into an aggregate JSON that game/src reads",
    "producer_intermediate": "read by another producer under tools/, never by the runtime",
    "build_manifest": "build-time bookkeeping for a producer, not runtime data",
    "provenance": "audit/provenance artefact for the pipeline",
    "tests_only": "read only by game/tests, never by the runtime",
    "placeholder": "authored placeholder/example rows (Mission.Example.* style fallbacks)",
    "blocked_on_team": "no consumer yet; a named remediation team owns the reader",
}

TABLE_ROOT_RE = re.compile(
    r'_load_tables_from_dir\(\s*"res://data/generated/(tables/[^"]+)"\s*,\s*(true|false)\s*\)'
)
# game_data.gd also loads a list of roots through a for-loop variable:
#     for dir_path: String in [ "res://data/generated/tables/A",
#                               "res://data/generated/tables/B" ]:
#         _load_tables_from_dir(dir_path, true)
ROOT_LOOP_RE = re.compile(
    r"for\s+(?P<var>\w+)\s*(?::\s*\w+)?\s+in\s+\[(?P<body>.*?)\]",
    re.DOTALL,
)
CALL_RE = re.compile(
    r"_load_tables_from_dir\(\s*(?P<arg>[^,]+?)\s*,\s*(?P<rec>true|false)\s*\)"
)
LITERAL_RE = re.compile(r'"(res://data/generated/(?:tables)/[^"]+)"')


def _glob_to_regex(glob: str) -> re.Pattern[str]:
    """Pathlib-style glob with ``**`` spanning directories.

    ``PurePath.match`` deliberately does not support recursive ``**``; the
    allowlist needs ``tables/StringTables/**`` to match nested tables, so build
    the regex here instead.
    """
    out = []
    index = 0
    while index < len(glob):
        char = glob[index]
        if char == "*":
            if glob.startswith("**", index):
                out.append(".*")
                index += 2
                continue
            out.append("[^/]*")
        elif char == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(char))
        index += 1
    return re.compile("^" + "".join(out) + "$")


def _strip_func_body(text: str, header: str) -> str:
    """Remove a top-level GDScript function body so its recursion is not parsed
    as a new table root."""
    start = text.find(header)
    if start == -1:
        return text
    end = text.find("\nfunc ", start + len(header))
    if end == -1:
        return text[:start]
    return text[:start] + text[end:]


def parse_table_roots(src_text: str) -> list[tuple[str, bool]]:
    """Return [(tables-relative dir, recursive)] declared by game_data.gd.

    Fail-closed: the parser raises ``ValueError`` when a
    ``_load_tables_from_dir`` call uses an argument it cannot resolve to a
    literal or to a parsed loop variable, so a new root can never be silently
    skipped by this audit.
    """
    roots: list[tuple[str, bool]] = []
    scan_text = _strip_func_body(src_text, "func _load_tables_from_dir(")
    for match in TABLE_ROOT_RE.finditer(scan_text):
        roots.append((match.group(1).rstrip("/"), match.group(2) == "true"))

    loop_vars: set[str] = set()
    for match in ROOT_LOOP_RE.finditer(scan_text):
        var = match.group("var")
        # The call site may sit outside the bracket literal, so resolve the
        # recursion flag for this variable name from the whole file.
        calls = [
            call
            for call in CALL_RE.finditer(scan_text)
            if call.group("arg").strip() == var
        ]
        if not calls:
            continue
        recursive = calls[0].group("rec") == "true"
        for literal in LITERAL_RE.finditer(match.group("body")):
            roots.append(
                (
                    literal.group(1).replace("res://data/generated/", "").rstrip("/"),
                    recursive,
                )
            )
        loop_vars.add(var)

    for call in CALL_RE.finditer(scan_text):
        arg = call.group("arg").strip()
        if arg.startswith('"') or arg in loop_vars:
            continue
        raise ValueError(
            f"unparseable _load_tables_from_dir argument {arg!r} in game_data.gd; "
            "extend tools/check_consumers.py rather than skipping the root"
        )

    unique = sorted(set(roots))
    return [(rel, rec) for rel, rec in unique]


def _gd_text(path: Path) -> str:
    parts = []
    for gd in sorted(path.rglob("*.gd")):
        try:
            parts.append(gd.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            continue
    return "\n".join(parts)


def is_reachable(
    rel: str,
    src_text: str,
    roots: list[tuple[str, bool]],
    dir_tokens: set[str],
) -> tuple[bool, str]:
    """Return (reachable, how) for one generated-relative posix path.

    ``how`` is one of ``literal`` (``<stem>.json`` appears in GDScript),
    ``table_root`` (the file sits under a ``_load_tables_from_dir`` root),
    ``dir_scan`` (GDScript opens the parent directory and resolves names
    itself, e.g. the weather preset cache), or ``""``.
    """
    posix = PurePosixPath(rel)
    stem = posix.stem
    if f"{stem}.json" in src_text:
        return True, "literal"
    if posix.parent.as_posix().startswith("tables"):
        for root, recursive in roots:
            if not rel.startswith(root + "/"):
                continue
            tail = rel[len(root) + 1 :]
            if recursive or "/" not in tail:
                return True, "table_root"
    if posix.parent.as_posix() in dir_tokens:
        return True, "dir_scan"
    return False, ""


def collect_targets(generated: Path) -> list[tuple[str, str]]:
    """Return [(generated-relative posix path, domain)] for every audited file."""
    targets: list[tuple[str, str]] = []
    tables = generated / "tables"
    if tables.is_dir():
        for path in sorted(tables.rglob("*.json")):
            targets.append((path.relative_to(generated).as_posix(), "table"))
    for pattern, domain in (
        ("*.json", "manifest"),
        ("gameplay/*.json", "gameplay"),
        ("weather/*.json", "weather"),
        ("vfx/*.json", "vfx"),
    ):
        for path in sorted(generated.glob(pattern)):
            if path.is_file():
                targets.append((path.relative_to(generated).as_posix(), domain))
    # curves.json / materials.json etc. at the root are covered by "*.json".
    return targets


def load_allowlist(path: Path) -> tuple[list[dict], list[str]]:
    problems: list[str] = []
    if not path.is_file():
        return [], [f"missing consumer allowlist {path}"]
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [], [f"{path}: not valid JSON: {exc}"]
    rules = payload.get("rules")
    if not isinstance(rules, list):
        return [], [f"{path}: 'rules' must be a list"]
    seen = set()
    for index, rule in enumerate(rules):
        label = f"{path}: rule #{index}"
        if not isinstance(rule, dict):
            problems.append(f"{label} is not an object")
            continue
        glob = rule.get("glob")
        if not isinstance(glob, str) or not glob:
            problems.append(f"{label} has no glob")
            continue
        label = f"{path}: rule {glob!r}"
        if glob in seen:
            problems.append(f"{label} is duplicated")
        seen.add(glob)
        kind = rule.get("kind")
        if kind not in KINDS:
            problems.append(f"{label} has unknown kind {kind!r}")
        if not str(rule.get("reason") or "").strip():
            problems.append(f"{label} has no reason")
        if kind == "blocked_on_team" and not str(rule.get("owner") or "").strip():
            problems.append(f"{label} is blocked_on_team but names no owner")
        consumer = rule.get("consumer")
        if consumer:
            consumer_path = ROOT / consumer
            if not consumer_path.is_file():
                problems.append(
                    f"{label} names consumer {consumer} which does not exist"
                )
        if "optional" in rule and not isinstance(rule["optional"], bool):
            problems.append(f"{label} has a non-boolean optional flag")
        if rule.get("consumer") and not str(rule.get("claim_token") or "").strip():
            problems.append(f"{label} names a consumer but no claim_token")
    return rules, problems


def rule_matches(glob: str, rel: str) -> bool:
    return bool(_glob_to_regex(glob).match(rel))


def verify_consumer_claim(rule: dict) -> str | None:
    """Return a problem string when a rule's ``consumer`` claim is unverifiable.

    A rule that names a ``consumer`` must also name the ``claim_token`` that
    proves it: a literal string the consumer file must contain. Explicit tokens
    are used instead of guessing path segments, because a directory glob
    (``tables/Maps/**``) has no distinctive basename to grep for.
    """
    consumer = rule.get("consumer")
    if not consumer:
        return None
    path = ROOT / consumer
    if not path.is_file():
        return f"consumer {consumer} does not exist"
    token = rule.get("claim_token")
    if not isinstance(token, str) or not token.strip():
        return f"consumer {consumer} is claimed but no claim_token proves it"
    text = path.read_text(encoding="utf-8", errors="replace")
    if token not in text:
        return f"claim_token {token!r} does not appear in {consumer}"
    return None


def audit(
    generated: Path,
    src: Path,
    tests: Path,
    allowlist_path: Path,
    list_unconsumed: bool,
    strict_optional: bool = False,
) -> int:
    src_text = _gd_text(src)
    tests_text = _gd_text(tests)
    roots = parse_table_roots(src_text)
    if not roots:
        print(
            "FAIL: no _load_tables_from_dir(...) roots parsed from game_data.gd",
            file=sys.stderr,
        )
        return 1
    rules, problems = load_allowlist(allowlist_path)
    failures = list(problems)
    rule_hits = {
        rule["glob"]: 0 for rule in rules if isinstance(rule, dict) and "glob" in rule
    }

    targets = collect_targets(generated)
    dir_tokens = set(re.findall(r'"res://data/generated/([^"%]+?)"', src_text))
    dir_tokens = {token.rstrip("/") for token in dir_tokens}
    consumed = tests_only = allowlisted = 0
    by_how: dict[str, int] = {}
    unconsumed: list[str] = []
    by_kind: dict[str, int] = {}
    blocked: dict[str, list[str]] = {}

    for rel, domain in targets:
        reachable, how = is_reachable(rel, src_text, roots, dir_tokens)
        if reachable:
            consumed += 1
            by_how[how] = by_how.get(how, 0) + 1
            continue
        matched = [rule for rule in rules if rule_matches(rule["glob"], rel)]
        if matched:
            rule = matched[0]
            allowlisted += 1
            kind = str(rule.get("kind"))
            by_kind[kind] = by_kind.get(kind, 0) + 1
            rule_hits[rule["glob"]] += 1
            if kind == "blocked_on_team":
                owner = str(rule.get("owner"))
                blocked.setdefault(owner, []).append(rel)
            if list_unconsumed:
                print(f"  allowlisted [{kind}] {rel}")
            continue
        if f"{PurePosixPath(rel).stem}.json" in tests_text:
            tests_only += 1
            unconsumed.append(f"tests_only {rel}")
        else:
            unconsumed.append(f"UNCONSUMED {rel}")

    for rel in unconsumed:
        if rel.startswith("UNCONSUMED"):
            failures.append(rel)

    for glob, hits in sorted(rule_hits.items()):
        rule = next((r for r in rules if r.get("glob") == glob), {})
        if hits == 0 and (strict_optional or not rule.get("optional")):
            failures.append(
                f"STALE RULE {glob}: matches no generated file; delete or retarget it"
                + (" (--strict-optional)" if rule.get("optional") else "")
            )
        elif hits == 0:
            print(
                f"  note: optional rule {glob} matched nothing (producer output not regenerated here)"
            )

    for rule in rules:
        claim = verify_consumer_claim(rule)
        if claim:
            failures.append(f"RULE {rule['glob']!r}: {claim}")

    # Table-root coverage diagnostic. An empty root is a dead directory literal
    # in the runtime (RE-A-01): game_data.gd asks for a directory that has no
    # files. Once the curve producer has run (curves.json exists) the roots it
    # fills are expected non-empty, so an empty root becomes a hard failure
    # instead of a note. This tightens itself on the first regeneration.
    curves_emitted = (generated / "curves.json").is_file()
    empty_roots = []
    for root, _recursive in roots:
        root_dir = generated / root
        if not root_dir.is_dir() or not any(root_dir.rglob("*.json")):
            empty_roots.append(root)
    if empty_roots:
        if curves_emitted:
            failures.extend(
                f"EMPTY ROOT {root}: game_data.gd loads it but no generated table "
                "exists; run tools/parse_curves.py (make normalize)"
                for root in empty_roots
            )
    print(f"consumer audit: {len(targets)} generated files")
    print(
        f"  runtime-read: {consumed} "
        + "("
        + ", ".join(f"{k} {v}" for k, v in sorted(by_how.items()))
        + ")"
    )
    print(
        f"  allowlisted:  {allowlisted} "
        + (
            "(" + ", ".join(f"{k} {v}" for k, v in sorted(by_kind.items())) + ")"
            if by_kind
            else ""
        )
    )
    print(f"  table roots parsed from game_data.gd: {len(roots)}")
    if empty_roots:
        print(f"  EMPTY table roots: {len(empty_roots)} ({', '.join(empty_roots)})")
    if blocked:
        print(
            "  blocked on a named owner: "
            + ", ".join(
                f"{owner} {len(items)}" for owner, items in sorted(blocked.items())
            )
        )
    if list_unconsumed:
        print("  every allowlisted row printed above")
    if tests_only:
        print(f"  tests-only readers (need a tests_only rule): {tests_only}")
    pending = [row for row in unconsumed if row.startswith("UNCONSUMED")]
    for row in pending[:20]:
        print(f"  {row}")
    if len(pending) > 20:
        print(f"  ... {len(pending) - 20} more (rerun with --list-unconsumed)")

    if failures:
        print(f"CONSUMER AUDIT FAILED: {len(failures)} failure(s)")
        for item in failures[:40]:
            print(f"FAIL: {item}")
        return 1
    print("CONSUMER AUDIT PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", default=str(DEFAULT_GENERATED))
    parser.add_argument("--src", default=str(DEFAULT_SRC))
    parser.add_argument("--tests", default=str(DEFAULT_TESTS))
    parser.add_argument("--allowlist", default=str(DEFAULT_ALLOWLIST))
    parser.add_argument("--list-unconsumed", action="store_true")
    parser.add_argument(
        "--strict-optional",
        action="store_true",
        help="Treat an optional rule that matches nothing as a failure. Use this "
        "after `make normalize` has created the staged producer's output.",
    )
    parser.add_argument("--json", action="store_true", help="also print a JSON summary")
    args = parser.parse_args()
    status = audit(
        Path(args.generated),
        Path(args.src),
        Path(args.tests),
        Path(args.allowlist),
        args.list_unconsumed,
        args.strict_optional,
    )
    if args.json:
        print(json.dumps({"status": "pass" if status == 0 else "fail"}))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
