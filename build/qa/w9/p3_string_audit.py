#!/usr/bin/env python3
"""W9-P3 visible-UI string audit (W10-A: optional fail-closed floors).

Reads the port UI sources and classifies every *visible* string expression:

  routed     produced by the Loc pipeline through one of the sanctioned helpers
             UIStringsScript.st_text/st_upper/st_template/raw/loc,
             _loc/_loc_upper, Loc.t, InputGlyphs.prompt, TutorialText.render
  authored   the represented source string exists in an authored table
             (game/data/generated/tables/StringTables/**.json entries, or the
             locres reverse map game/data/generated/localization/sources.json),
             including the port's ALL-CAPS form of a Title-case authored row
  invented   routeable copy with no authored counterpart

Two string sources are counted:
  1. helper calls: the authored table/key (or locres source) argument and its
     literal fallback are the represented string;
  2. plain visible assignments (`.text = "..."`, `add_item("...")`,
     `_make_menu_btn("...")`, `white_keycap("...")`) with no helper.

Output: totals, coverage ratios, per-file routed counts, and an optional TSV.
`--tsv PATH` writes file<TAB>line<TAB>kind<TAB>routed<TAB>authored<TAB>literal.

Gate floors are optional: with no floor flag the script is the W9 measurement
and always exits 0. `--min-routed N --min-authored N --max-invented N` turns it
into a gate: a missed floor prints `UI_STRINGS GATE FAIL …` and exits 1. The
Makefile target `string-audit` pins the W10-A measured floors
(306 routed / 195 authored / 111 invented).
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "game" / "src"
STRINGS = ROOT / "game" / "data" / "generated" / "tables" / "StringTables"
SOURCES = ROOT / "game" / "data" / "generated" / "localization" / "sources.json"

UI_FILES = [p for p in sorted((SRC / "ui").glob("*.gd")) if p.name != "review_mode.gd"]
EXTRA_FILES = [
    SRC / "missions" / "mission_controller.gd",
    SRC / "interact" / "loot_container.gd",
    SRC / "interact" / "loot_item.gd",
    SRC / "interact" / "clue_item.gd",
    SRC / "interact" / "escape_gate.gd",
]

ARG = r'"((?:[^"\\]|\\.)*)"'
HELPERS = [
    # table, key, fallback
    (
        "st_text",
        re.compile(r"\.st_text\(\s*" + ARG + r"\s*,\s*" + ARG + r"\s*,\s*" + ARG),
    ),
    (
        "st_upper",
        re.compile(r"\.st_upper\(\s*" + ARG + r"\s*,\s*" + ARG + r"\s*,\s*" + ARG),
    ),
    (
        "st_template",
        re.compile(r"\.st_template\(\s*" + ARG + r"\s*,\s*" + ARG + r"\s*,\s*" + ARG),
    ),
    ("raw", re.compile(r"\.raw\(\s*" + ARG + r"\s*,\s*" + ARG + r"\s*,\s*" + ARG)),
    ("loc", re.compile(r"\.loc\(\s*" + ARG + r"\s*\)")),
    ("loc_template", re.compile(r"\.loc_template\(\s*" + ARG + r"\s*,")),
    ("_loc", re.compile(r"(?<![\w.])_loc\(\s*" + ARG + r"\s*\)")),
    ("_loc_upper", re.compile(r"(?<![\w.])_loc_upper\(\s*" + ARG + r"\s*\)")),
    ("Loc.t", re.compile(r"Loc\.t\(\s*" + ARG + r"\s*\)")),
    ("glyph_prompt", re.compile(r"\.prompt\(\s*" + ARG + r"\s*,\s*" + ARG)),
    ("tutorial", re.compile(r"TutorialText\.render\(\s*" + ARG)),
    ("slider_label", re.compile(r"_make_slider_row\(\s*" + ARG + r"\s*,\s*" + ARG)),
    ("status", re.compile(r"\._status\(\s*" + ARG + r"\s*\)")),
    ("hint", re.compile(r"\.?_set_hint\(\s*" + ARG + r"\s*\)")),
]
ROUTED_MARKERS = (
    "UIStringsScript.",
    "UIStrings.",
    "_loc(",
    "_loc_upper(",
    "Loc.t(",
    "InputGlyphs.",
    "TutorialText.render(",
    "st_text(",
    "st_upper(",
    "st_template(",
    ".loc(",
)
ASSIGN_RE = re.compile(
    r"""(?:\.text|\.placeholder_text|\.tooltip_text)\s*=\s*(?P<rhs>.*)$"""
)
CALL_RES = [
    re.compile(r"""add_item\(\s*""" + ARG),
    re.compile(r"""_make_menu_btn\(\s*""" + ARG),
    re.compile(r"""white_keycap\(\s*""" + ARG),
    re.compile(r"""keycap\(\s*""" + ARG),
]
# Gameplay-emitted UI feedback (mission_controller / interact files): the value
# reaches a Control through the HUD, so it is a visible string even though the
# assignment happens in another script.
EXTRA_FILE_NAMES = {
    "mission_controller.gd",
    "loot_container.gd",
    "clue_item.gd",
    "loot_item.gd",
}
DICT_UI_RE = re.compile(r'"(?:title|prompt|label)":\s*' + ARG)
HUD_CALL_LITERAL_RE = re.compile(
    r'\.(?:call\(\s*"(?:show_toast|show_clue_toast|show_inventory_full_toast|set_steal_prompt|_set_prompt)"\s*,\s*|'
    r"(?:show_toast|show_clue_toast|show_inventory_full_toast|set_steal_prompt|_set_prompt)\()"
    + ARG
)
LITERAL_RE = re.compile(r'^"(?P<s>(?:[^"\\]|\\.)*)"$')
# Keycap tokens are device glyphs, not copy: they are replaced by InputGlyphs
# calls in W9-P3-C3 and are counted separately as KEYCAPS.
KEYCAP_TOKENS = {
    "TAB",
    "MMB",
    "RMB",
    "LMB",
    "F",
    "Q",
    "E",
    "ESC",
    "SPACE",
    "SHIFT",
    "CTRL",
    "ENTER",
    "BACKSPACE",
    "WASD",
    "H",
    "G",
    "R",
    "LB",
    "RB",
    "LT",
    "RT",
    "A",
    "B",
    "X",
    "Y",
    "UP",
    "DOWN",
    "LEFT",
    "RIGHT",
    "PREV",
    "NEXT",
    "∞",
    "↺",
    "[",
    "]",
}
DEBUG_MARKERS = ("FPS %d", "ms | draws", "sublevels=%d", "on:  %s")
HEAD_RE = re.compile(r'^"(?P<s>(?:[^"\\]|\\.)*)"\s*(?:%|\+)')


def load_authored() -> tuple[set[str], dict[tuple[str, str], str], set[str]]:
    tables: set[str] = set()
    keyed: dict[tuple[str, str], str] = {}
    if STRINGS.exists():
        for p in STRINGS.rglob("*.json"):
            try:
                doc = json.loads(p.read_text(encoding="utf-8"))
            except Exception:
                continue
            entries = doc.get("entries")
            if isinstance(entries, dict):
                for k, v in entries.items():
                    if isinstance(v, str):
                        tables.add(v)
                        keyed[(p.stem, str(k))] = v
    sources: set[str] = set()
    if SOURCES.exists():
        try:
            doc = json.loads(SOURCES.read_text(encoding="utf-8"))
            if isinstance(doc, dict):
                sources.update(str(v) for v in doc.values())
        except Exception:
            pass
    return tables, keyed, sources


def is_keycap(lit: str) -> bool:
    return lit.strip() in KEYCAP_TOKENS


def is_copy(lit: str) -> bool:
    """True when the literal is game copy: it carries a word, not only
    numbers/format specs/symbols."""
    if any(m in lit for m in DEBUG_MARKERS):
        return False
    cleaned = re.sub(r"%[-+ #0-9.*]*[sdfxXv]", "", lit)
    cleaned = re.sub(r"\{[^}]*\}", "", cleaned)
    cleaned = re.sub(r"[£$€()\[\]{}%:;,./|_+=<>#*·—–\-\s\d]", "", cleaned)
    return bool(re.search(r"[A-Za-z\u00c0-\u024f\u3040-\u9fff]", cleaned))


def static_prefix(lit: str) -> str:
    for mark in ("%s", "%d", "%0", "{", "\\n"):
        i = lit.find(mark)
        if i > 0:
            return lit[:i]
    return lit


def authored_match(lit: str, tables: set[str], sources: set[str]) -> bool:
    if not lit:
        return False
    cand = {lit, lit.strip()}
    for c in cand:
        if c in tables or c in sources:
            return True
    if lit == lit.upper() and lit != lit.lower():
        cap = lit.capitalize()
        if cap in tables or cap in sources:
            return True
        for c in cand:
            if c.title() in tables or c.title() in sources:
                return True
    # No prefix inference: a port string that merely starts with an authored
    # row ("Objective" vs "Objective: ", "Steal the %s" vs the authored
    # "Steal the {ItemName}") is NOT an authored row. The independent C2 audit
    # (audit-c2 §1.4) flagged 11 such rows; strictness matters more than a
    # higher number.
    return False


def read_lines(path: pathlib.Path, rev: str) -> list[str]:
    if rev:
        rel = str(path.relative_to(ROOT))
        try:
            out = subprocess.check_output(
                ["git", "-C", str(ROOT), "show", f"{rev}:{rel}"], text=True
            )
            return out.splitlines()
        except subprocess.CalledProcessError:
            return []
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def scan(path: pathlib.Path, tables, keyed, sources, rev: str = ""):
    rows = []
    text = read_lines(path, rev)
    for i, line in enumerate(text, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if any(
            m in stripped
            for m in ("push_warning(", "push_error(", "print(", "printerr(", "assert ")
        ):
            continue
        found = False
        for name, rx in HELPERS:
            for m in rx.finditer(line):
                found = True
                gd = m.groupdict()
                if name in ("st_text", "st_upper", "st_template", "raw"):
                    table, key = gd["s"] if False else (m.group(1), m.group(2))
                    # NOTE: group 1/2 are table/key; the last group is the fallback.
                    literal = m.group(3)
                    ok = (table, key) in keyed
                    rows.append(
                        {
                            "file": str(path.relative_to(ROOT)),
                            "line": i,
                            "kind": name,
                            "routed": True,
                            "literal": literal,
                            "keyed": ok,
                        }
                    )
                elif name == "glyph_prompt":
                    rows.append(
                        {
                            "file": str(path.relative_to(ROOT)),
                            "line": i,
                            "kind": name,
                            "routed": True,
                            "literal": m.group(2),
                            "keyed": False,
                        }
                    )
                else:
                    # The label is the second arg for _make_slider_row; other
                    # helpers carry the copy in group 1. A raw helper arg (e.g.
                    # "Touch Look") is not routed unless the same line also
                    # carries a pipeline call.
                    lit_arg = m.group(2) if name == "slider_label" else m.group(1)
                    if lit_arg.strip() == "" or not is_copy(lit_arg):
                        continue
                    rows.append(
                        {
                            "file": str(path.relative_to(ROOT)),
                            "line": i,
                            "kind": name,
                            "routed": any(mk in line for mk in ROUTED_MARKERS),
                            "literal": lit_arg,
                            "keyed": False,
                        }
                    )
        if not found and path.name in EXTRA_FILE_NAMES:
            for rx in (DICT_UI_RE, HUD_CALL_LITERAL_RE):
                for m in rx.finditer(line):
                    if m.group(1).strip() == "" or not is_copy(m.group(1)):
                        continue
                    found = True
                    rows.append(
                        {
                            "file": str(path.relative_to(ROOT)),
                            "line": i,
                            "kind": "hud_feedback",
                            "routed": any(mk in line for mk in ROUTED_MARKERS),
                            "literal": m.group(1),
                            "keyed": False,
                        }
                    )
        if found:
            continue
        rhs = None
        m = ASSIGN_RE.search(line)
        if m:
            rhs = m.group("rhs").strip()
        else:
            for rx in CALL_RES:
                cm = rx.search(line)
                if cm:
                    rhs = '"' + cm.group(1) + '"'
                    break
        if rhs is None:
            continue
        lit = None
        lm = LITERAL_RE.match(rhs)
        if lm:
            lit = lm.group("s")
        else:
            hm = HEAD_RE.match(rhs)
            if hm:
                lit = hm.group("s")
        if lit is None or lit.strip() == "":
            continue
        if is_keycap(lit) or not is_copy(lit):
            continue
        if "res://" in lit or lit.startswith("uid://") or lit.startswith("/root/"):
            continue
        rows.append(
            {
                "file": str(path.relative_to(ROOT)),
                "line": i,
                "kind": "literal",
                "routed": False,
                "literal": lit,
                "keyed": False,
            }
        )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", default="")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument(
        "--rev", default="", help="measure another git revision (e.g. 8ce9a86)"
    )
    ap.add_argument(
        "--same-files-as",
        default="",
        help="keep only files present at this git revision",
    )
    ap.add_argument(
        "--expressions",
        action="store_true",
        help="count every expression instead of one row per assignment site",
    )
    ap.add_argument(
        "--min-routed",
        type=int,
        default=None,
        help="fail (exit 1) when routed is below this floor",
    )
    ap.add_argument(
        "--min-authored",
        type=int,
        default=None,
        help="fail (exit 1) when authored is below this floor",
    )
    ap.add_argument(
        "--max-invented",
        type=int,
        default=None,
        help="fail (exit 1) when invented is above this ceiling",
    )
    args = ap.parse_args()
    tables, keyed, sources = load_authored()
    files = UI_FILES + [p for p in EXTRA_FILES if p.exists()]
    if args.same_files_as:
        keep = []
        for p in files:
            rel = str(p.relative_to(ROOT))
            try:
                subprocess.check_output(
                    [
                        "git",
                        "-C",
                        str(ROOT),
                        "cat-file",
                        "-e",
                        f"{args.same_files_as}:{rel}",
                    ],
                    stderr=subprocess.DEVNULL,
                )
                keep.append(p)
            except subprocess.CalledProcessError:
                continue
        files = keep
    rows = []
    for p in files:
        rows.extend(scan(p, tables, keyed, sources, args.rev))
    for r in rows:
        r["authored"] = bool(r.pop("keyed", False)) or authored_match(
            r["literal"], tables, sources
        )
    total = len(rows)
    routed = sum(1 for r in rows if r["routed"])
    authored = sum(1 for r in rows if r["authored"])
    routed_auth = sum(1 for r in rows if r["routed"] and r["authored"])
    invented = [r for r in rows if not r["authored"]]
    print(
        f"UI_STRINGS total={total} routed={routed} authored={authored} "
        f"routed_authored={routed_auth} invented={len(invented)}"
    )
    # W10-A: optional fail-closed floors. No flag = the W9 measurement contract
    # (always exit 0); the `string-audit` Makefile target pins the measured
    # floors and `make audit` fails on a regression.
    gate_failures: list[str] = []
    if args.min_routed is not None and routed < args.min_routed:
        gate_failures.append(f"routed={routed} < min-routed={args.min_routed}")
    if args.min_authored is not None and authored < args.min_authored:
        gate_failures.append(f"authored={authored} < min-authored={args.min_authored}")
    if args.max_invented is not None and len(invented) > args.max_invented:
        gate_failures.append(
            f"invented={len(invented)} > max-invented={args.max_invented}"
        )
    floors_set = any(
        v is not None for v in (args.min_routed, args.min_authored, args.max_invented)
    )
    if gate_failures:
        print(
            "UI_STRINGS GATE FAIL "
            + " ".join(gate_failures)
            + f" (total={total} routed={routed} authored={authored} "
            f"routed_authored={routed_auth} invented={len(invented)})"
        )
        return 1
    if floors_set:
        print(
            "UI_STRINGS GATE PASS "
            f"routed={routed} authored={authored} invented={len(invented)}"
        )
    print(f"COVERAGE routed/total={routed / total:.4f}" if total else "COVERAGE n/a")
    if authored:
        print(f"COVERAGE authored_routed/authored={routed_auth / authored:.4f}")
    kinds: dict[str, int] = {}
    for r in rows:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print("KINDS " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())))
    files = {}
    for r in rows:
        f = files.setdefault(r["file"], [0, 0])
        f[0] += 1
        if r["routed"]:
            f[1] += 1
    for f in sorted(files, key=lambda k: -files[k][0]):
        t, rt = files[f]
        print(f"  {f}: {rt}/{t} routed")
    if args.verbose:
        for r in rows:
            state = "R" if r["routed"] else "."
            auth = "A" if r["authored"] else "X"
            print(f"{state}{auth} {r['file']}:{r['line']} {r['literal'][:90]!r}")
    if args.tsv:
        out = pathlib.Path(args.tsv)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            "file\tline\tkind\trouted\tauthored\tliteral\n"
            + "\n".join(
                f"{r['file']}\t{r['line']}\t{r['kind']}\t{int(r['routed'])}\t"
                f"{int(r['authored'])}\t{r['literal']}"
                for r in rows
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"TSV {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
