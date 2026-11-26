#!/usr/bin/env python3
"""W10-A literal-grep gate (stdlib only; exit 0/1).

Two independent scans, because the two classes need opposite treatment:

1. **Code-only** (`game/src/**/*.gd`): strip `#` comments and every string
   literal, then require 0 hits of the port-invented formulas
   `maxi(100`, `count % 12`, `3 + count % 2`. The explanatory comments in
   `game/src/core/save_system.gd` and `game/src/missions/mission_controller.gd`
   that document the removals therefore stay legal; a live formula does not.

2. **String literals only** (`game/src/ui/**`): require 0 hits of the invented
   post-match rating vocabulary `GHOST`, `BRAWLER`, `CONSTABULARY`. The removal
   comment in `game/src/ui/hud.gd` is a comment, not a literal, so it does not
   trip the gate; a genuine rating label would.

The scan is deliberately literal (no word boundaries, no case folding): the
tokens are the defect signatures, and the lower-case/Title-case words in the
game ("were ghosts", "The Constable's Due") are authored prose, not labels.
Multi-line GDScript strings are sliced per line, which is sufficient here: the
signatures are single-line labels.

Prints `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=<n>` on
success and one `LITERAL_GREPS FAIL file:line: pattern: text` line per hit plus
a summary on failure.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "game" / "src"
UI = SRC / "ui"

CODE_PATTERNS = ("maxi(100", "count % 12", "3 + count % 2")
UI_RATING_WORDS = ("GHOST", "BRAWLER", "CONSTABULARY")


def split_code_and_literals(line: str) -> tuple[str, list[str]]:
    """Return (code, literals) for one GDScript line.

    `code` has every string literal replaced by a space and the `#` comment
    removed. `literals` holds the decoded-enough literal contents (escapes are
    kept verbatim: the gate searches for words, not values).
    """
    code: list[str] = []
    literals: list[str] = []
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if ch == "#":
            break
        if ch in ('"', "'"):
            quote = ch
            i += 1
            buf: list[str] = []
            while i < n:
                c = line[i]
                if c == "\\" and i + 1 < n:
                    buf.append(line[i : i + 2])
                    i += 2
                    continue
                if c == quote:
                    i += 1
                    break
                buf.append(c)
                i += 1
            literals.append("".join(buf))
            code.append(" ")
            continue
        code.append(ch)
        i += 1
    return "".join(code), literals


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def main() -> int:
    if not SRC.is_dir():
        print(f"LITERAL_GREPS FAIL missing {rel(SRC)}")
        return 1
    files = sorted(SRC.rglob("*.gd"))
    code_hits: list[tuple[str, int, str, str]] = []
    ui_hits: list[tuple[str, int, str, str]] = []
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as exc:  # fail closed on an unreadable source
            print(f"LITERAL_GREPS FAIL {rel(path)}: unreadable ({exc})")
            return 1
        in_ui = UI in path.parents
        for lineno, line in enumerate(lines, 1):
            code, literals = split_code_and_literals(line)
            for pattern in CODE_PATTERNS:
                if pattern in code:
                    code_hits.append((rel(path), lineno, pattern, line.strip()))
            if in_ui:
                for literal in literals:
                    for word in UI_RATING_WORDS:
                        if word in literal:
                            ui_hits.append((rel(path), lineno, word, line.strip()))

    for file_name, lineno, pattern, text in code_hits + ui_hits:
        print(f"LITERAL_GREPS FAIL {file_name}:{lineno}: {pattern}: {text}")
    if code_hits or ui_hits:
        print(
            f"LITERAL_GREPS FAIL code_hits={len(code_hits)} "
            f"ui_rating_literals={len(ui_hits)} files={len(files)}"
        )
        return 1
    print(f"LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files={len(files)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
