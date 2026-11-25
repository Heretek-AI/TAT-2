#!/usr/bin/env python3
"""Emit ``project_settings.json`` from the shipped UE ``DefaultGame.ini``.

Inputs
------
``<extracted>/raw/TAT/Config/DefaultGame.ini`` — the cooked project config
(898 CRLF lines in the shipped build). Only five sections are covered:

  /Script/TAT.TATProgressionSettings       progression / XP curve settings
  /Script/TAT.TATProjectSettings           maps, missions, FTUE, endgame clock
  /Script/TAT.TATScoringSettings           end-of-match scoring weights
  /Script/Engine.GameSession               MaxPlayers (1 key)
  /Script/EngineSettings.GeneralProjectSettings   project provenance (read-only)

Output
------
``<out-dir>/project_settings.json``, schema ``tat2.project_settings/1``. The
default out-dir is ``<repo>/game/data/generated``; pass ``--out-dir`` to write
elsewhere. Output is deterministic (sorted keys, authored list order preserved,
no timestamps), so two runs are byte-identical.

JSON contract
-------------
::

    {
      "schema": "tat2.project_settings/1",
      "generated_by": "tools/parse_project_ini.py",
      "source": "extracted/raw/TAT/Config/DefaultGame.ini",
      "source_sha256": "<sha256 of the ini>",
      "progression": {
        "maximum_level": 25,
        "level_up_xp": 500,
        "xp_per_minute": 0.6,
        "maximum_time_in_game_xp": 25.0,
        "win_xp": 80.0,
        "mission_xp": 20.0,
        "contracts_xp": 20.0,
        "open_queue_xp": 5.0,
        "major_loot_xp": 6.0,
        "minor_loot_xp": 2.0,
        "looting_player_xp_multiplier": 1.1,
        "coop_xp_multiplier": 1.5,
        "difficulty_xp_multipliers": {"Easy": 1.0, "Normal": 2.0, "Hard": 3.0},
        "ftue_level_up_xp_categories": ["XP.ReachExitInTime", ...],
        "ftue_level_up_xp_is_on_top_of_regular_xp": true,
        "player_stat_data_table": "/Game/.../DT_PlayerStats.DT_PlayerStats",
        "xp_data_table": "...",
        "xp_to_level_table": "...",
        "xp_to_level": {"table": "/Game/.../CT_XPToLevel.CT_XPToLevel",
                        "row": "XPToLevel"},
        "upgrade_editor_progression_node_styles": [
          {"index": 0, "style": "BorderDark",
           "color": {"R": 0.5, "G": 0.5, "B": 0.5, "A": 1.0}}, ...],
        "raw": {"<exact ini key>": "<exact raw value string>", ...}
      },
      "project": {
        "hub_map_name": "MissionLobby_P",
        "thieves_den_map_name": "ThievesDenTest_P",
        "enable_thieves_den": true,
        "show_tutorial_map_after_complete": false,
        "show_normal_play_if_tutorial_unstarted": false,
        "ftue_min_thieves_den_money": 5000,
        "post_ftue_contracts": [{"tag": "Contract.Main.1",
                                 "requirement": "Complete"}, ...],
        "maps": [
          {"tag": "Map.Guildhall",
           "map": "/Game/Maps/Guildhall/Guildhall_P.Guildhall_P",
           "game_mode": "/Game/Core/BP_TATPvEGameMode.BP_TATPvEGameMode_C",
           "map_name": "Guildhall",
           "map_display_name": "LOCTABLE(\\"/Game/...ST_MapTool.ST_MapTool\\", "
                               "\\"Guildhall.MapName\\")",
           "missions": ["Mission.Guildhall.VaultHeist", ...],
           "mesh_scaling": {"X": 0.5, "Y": 0.5, "Z": 0.5},
           "coordinates_on_city_map": {"X": 65.0, "Y": 10.0},
           "raw": {"<parsed authored map struct>": "..."}},
          ...],
        "map_type_settings": [{"index": 0,
                               "allow_default_player_tools": false}, ...],
        "endgame_durations_by_difficulty": [1200.0, 600.0, 300.0],
        "endgame_duration_seconds_by_difficulty_index":
            {"0": 1200.0, "1": 600.0, "2": 300.0},
        "stashed_loot_value_to_trigger_endgame": 99999,
        "match_essentially_complete_threshold": 30.0,
        "initial_unlocked_content": ["Difficulty.Novice", ...],
        "post_ftue_unlocked_content": ["Map.Guildhall", ...],
        "mission_data_table": "...", "contract_data_table": "...",
        "difficulty_property_name": "Difficulty",
        "difficulty_index_source": "unproven: index order only",
        "raw": {"<exact ini key>": "<exact raw value string>", ...}
      },
      "scoring": {
        "escape_order_bonus_curve": "/Game/.../C_Ranking_EscapeOrderBonus...",
        "mission_complete_bonus": 300.0,
        "contract_complete_bonus": 100.0,
        "stashed_loot_value_multiplier_bonus": 0.1,
        "carried_loot_value_multiplier_bonus": 0.1,
        "raw": {...}
      },
      "general": {"max_players": 2, "project_name": "Thick As Thieves",
                  "project_version": "0.0.0.1",
                  "company_name": "OtherSide Entertainment", "raw": {...}},
      "unmapped_keys": []
    }

Additional keys are emitted where they are a plain snake_case translation of an
authored ini key (``settings_string_table``, ``post_match_unlock_tutorials``,
``end_match_rpc_delay_seconds``, ``project_id``, ``copyright_notice``, ...).
Maps carry only authored fields; the ini has no per-map placeholder key, so
none is emitted. ``maps[].raw`` is the *parsed* authored map struct; the exact
source text is in ``project.raw["Maps"]`` (a list, in authored order).

Grammar
-------
A real UE config parser, not ``key=value.split()``:

* ``+Key=...`` appends, ``-Key=...`` removes a matching value, ``!Key=`` clears,
  ``.Key=`` appends uniquely, plain ``Key=...`` sets. The effective value is
  evaluated in source order.
* ``Key[0]=...`` is an indexed property; the integer index is kept and lists
  built from it are sorted by index.
* Struct values ``(A=1,B=(C=2),D=((E=1),(E=2)))`` become dicts; a
  parenthesised comma list of values ``((..),(..))`` becomes a list; a bare
  tuple ``((TagName="X"), Complete)`` becomes a two-element list.
* Scalars: int, float, ``True``/``False``, ``"quoted"`` strings, bare tokens
  and enum tokens (``RCIM_Linear``, ``Complete``,
  ``ECollisionEnabled::QueryAndPhysics``) are kept verbatim as strings. ``None``
  is kept as the string ``"None"``, not JSON null.
* ``LOCTABLE(...)``, ``INVTEXT(...)`` and ``NSLOCTEXT(...)`` (and any other
  ``Ident(...)`` call) are kept as the exact raw expression string. No table
  lookup is performed and no fallback text is invented.
* Values that are not valid structured syntax are preserved verbatim as
  strings (the shipped file has exactly one: the unquoted
  ``CopyrightNotice=(c) 2018-...``). An unset value (``Key=``) becomes ``""``.
  The three typed sections are asserted to contain no fallback.

``raw`` is the fidelity guarantee: every key in a covered section appears
there, whether or not it has a typed field, with the exact text after ``=``
(CR stripped, nothing else). A key that appears once maps to a string; a key
that appears several times (``+Maps``, or a repeated set) maps to a list of
values in source order. Indexed keys keep their bracket suffix
(``MapTypeSettings[0]``). ``unmapped_keys`` is always ``[]``: the producer
computes it as *keys present in the section but absent from raw* and exits
non-zero if that set is ever non-empty, rather than shipping a partial map.

Difficulties
------------
``EndgameDurationsByDifficulty[0..2]`` is an authored **indexed** array. The
ini never names the indices. Names ``Easy``/``Normal``/``Hard`` appear in
``extracted/json`` only as ``ETATDifficulty::Easy`` etc. (10/8/6 occurrences,
no enum dump and no index), so ``difficulty_index_source`` is
``"unproven: index order only"`` and no consumer may claim ``[0] == Easy``
without separate evidence. ``progression.difficulty_xp_multipliers`` is a
different, explicitly named set (``EasyDifficultyXPMultiplier`` etc.).

CLI
---
``python3 tools/parse_project_ini.py [--extracted DIR] [--out-dir DIR] [--quiet]``.
``source`` in the payload is always the repo-relative ini path, independent of
``--extracted`` (which only locates the file to read). Exits non-zero with a
message on stderr when the source file, a covered section, or a required
authored field is missing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = "tat2.project_settings/1"
GENERATED_BY = "tools/parse_project_ini.py"
SOURCE_REL = "extracted/raw/TAT/Config/DefaultGame.ini"
SOURCE_PARTS = ("raw", "TAT", "Config", "DefaultGame.ini")
OUT_NAME = "project_settings.json"

PROGRESSION = "/Script/TAT.TATProgressionSettings"
PROJECT = "/Script/TAT.TATProjectSettings"
SCORING = "/Script/TAT.TATScoringSettings"
GAME_SESSION = "/Script/Engine.GameSession"
GENERAL = "/Script/EngineSettings.GeneralProjectSettings"


class IniError(ValueError):
    """A malformed ini line or a missing/ill-typed authored field."""


class _ParseError(ValueError):
    """Internal: a value did not match the UE structured-value grammar."""


_KEY_RE = re.compile(r"^([+\-.!]?)([A-Za-z_][A-Za-z0-9_]*)(?:\[(\d+)\])?$")
_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_CALL_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\s*\(")
_INT_RE = re.compile(r"^[+-]?\d+$")
_FLOAT_RE = re.compile(r"^[+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?$")
_CLASS_REF_RE = re.compile(r"^[^']+'([^']+)'$")
_OP_NAMES = {"": "set", "+": "add", "-": "remove", "!": "clear", ".": "add_unique"}


@dataclass(frozen=True)
class Entry:
    """One authored assignment."""

    key: str
    op: str
    index: int | None
    raw_key: str
    raw_value: str
    value: Any
    fallback: bool

    @property
    def raw_name(self) -> str:
        """Key as written, minus the operator prefix (index kept)."""
        return f"{self.key}[{self.index}]" if self.index is not None else self.key


@dataclass
class Section:
    name: str
    line: int
    entries: list[Entry] = field(default_factory=list)


class _ValueParser:
    """Recursive-descent parser for one UE config value."""

    def __init__(self, text: str) -> None:
        self.s = text
        self.i = 0

    # -- entry point ----------------------------------------------------
    def parse(self) -> Any:
        value = self._value()
        self._skip_ws()
        if self.i != len(self.s):
            raise _ParseError(
                f"trailing text at {self.i}: {self.s[self.i : self.i + 40]!r}"
            )
        return value

    # -- primitives -----------------------------------------------------
    def _skip_ws(self) -> None:
        while self.i < len(self.s) and self.s[self.i].isspace():
            self.i += 1

    def _peek(self) -> str:
        if self.i >= len(self.s):
            raise _ParseError("unexpected end of value")
        return self.s[self.i]

    def _value(self) -> Any:
        self._skip_ws()
        # UE writes an unset struct member as ``Key=`` (followed by ',' or ')'),
        # or an empty whole value as ``Key=``. There is no type information to
        # pick "" vs [] here; the verbatim text is preserved in ``raw``.
        if self.i >= len(self.s) or self.s[self.i] in ",)":
            return ""
        ch = self._peek()
        if ch == '"':
            return self._quoted()
        if ch == "(":
            return self._group()
        match = _CALL_RE.match(self.s, self.i)
        if match:
            return self._call()
        return self._bare()

    def _quoted(self) -> str:
        assert self._peek() == '"'
        self.i += 1
        out: list[str] = []
        while self.i < len(self.s):
            ch = self.s[self.i]
            if ch == "\\":
                self.i += 1
                if self.i >= len(self.s):
                    raise _ParseError("dangling escape in quoted string")
                out.append(self.s[self.i])
                self.i += 1
                continue
            if ch == '"':
                self.i += 1
                return "".join(out)
            out.append(ch)
            self.i += 1
        raise _ParseError("unterminated quoted string")

    def _call(self) -> str:
        """Keep ``Ident(args...)`` verbatim (LOCTABLE/INVTEXT/NSLOCTEXT/...)."""
        start = self.i
        match = _IDENT_RE.match(self.s, self.i)
        if not match:
            raise _ParseError("expected call name")
        self.i = match.end()
        self._skip_ws()
        if self._peek() != "(":
            raise _ParseError("expected '(' after call name")
        depth = 0
        in_quote = False
        escaped = False
        while self.i < len(self.s):
            ch = self.s[self.i]
            if in_quote:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    in_quote = False
            else:
                if ch == '"':
                    in_quote = True
                elif ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        self.i += 1
                        return self.s[start : self.i]
            self.i += 1
        raise _ParseError("unterminated call expression")

    def _bare(self) -> Any:
        start = self.i
        while self.i < len(self.s) and self.s[self.i] not in ",)":
            self.i += 1
        token = self.s[start : self.i].strip()
        if not token:
            raise _ParseError("empty value")
        if token in ("True", "true"):
            return True
        if token in ("False", "false"):
            return False
        if _INT_RE.match(token):
            return int(token)
        if _FLOAT_RE.match(token):
            return float(token)
        return token

    # -- groups ---------------------------------------------------------
    def _group(self) -> Any:
        assert self._peek() == "("
        self.i += 1
        if self._looks_like_struct(self.i):
            return self._struct_body()
        return self._list_body()

    def _looks_like_struct(self, pos: int) -> bool:
        """True when the first top-level token is ``Name=``, else a list."""
        depth = 0
        in_quote = False
        escaped = False
        while pos < len(self.s):
            ch = self.s[pos]
            if in_quote:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    in_quote = False
            elif ch == '"':
                in_quote = True
            elif ch == "(":
                depth += 1
            elif ch == ")":
                if depth == 0:
                    return False
                depth -= 1
            elif ch == "=" and depth == 0:
                return True
            elif ch == "," and depth == 0:
                return False
            pos += 1
        raise _ParseError("unterminated group")

    def _struct_body(self) -> dict[str, Any]:
        out: dict[str, Any] = {}
        while True:
            self._skip_ws()
            if self._peek() == ")":
                self.i += 1
                return out
            match = _IDENT_RE.match(self.s, self.i)
            if not match:
                raise _ParseError(f"expected struct key at {self.i}")
            key = match.group(0)
            self.i = match.end()
            self._skip_ws()
            if self._peek() != "=":
                raise _ParseError(f"expected '=' after struct key {key!r}")
            self.i += 1
            out[key] = self._value()
            self._skip_ws()
            ch = self._peek()
            if ch == ",":
                self.i += 1
                continue
            if ch == ")":
                self.i += 1
                return out
            raise _ParseError(f"expected ',' or ')' at {self.i}")

    def _list_body(self) -> list[Any]:
        out: list[Any] = []
        while True:
            self._skip_ws()
            if self._peek() == ")":
                self.i += 1
                return out
            out.append(self._value())
            self._skip_ws()
            ch = self._peek()
            if ch == ",":
                self.i += 1
                continue
            if ch == ")":
                self.i += 1
                return out
            raise _ParseError(f"expected ',' or ')' at {self.i}")


def parse_value(raw: str) -> tuple[Any, bool]:
    """Parse one value; fall back to the verbatim string on bad syntax.

    Returns ``(value, fallback)``. ``fallback`` is True only when the text
    could not be parsed as UE structured syntax.
    """
    try:
        return _ValueParser(raw.strip()).parse(), False
    except _ParseError:
        return raw.strip(), True


def parse_ini_text(text: str) -> dict[str, Section]:
    """Parse a UE config file into ``{section name: Section}``."""
    sections: dict[str, Section] = {}
    current: Section | None = None
    # splitlines() handles the shipped CRLF without leaving a stray \r.
    for lineno, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("["):
            if not line.endswith("]"):
                raise IniError(f"line {lineno}: malformed section header {line!r}")
            name = line[1:-1].strip()
            if not name:
                raise IniError(f"line {lineno}: empty section name")
            if name not in sections:
                sections[name] = Section(name=name, line=lineno)
            current = sections[name]
            continue
        if current is None:
            raise IniError(f"line {lineno}: assignment before any section")
        raw_key, sep, raw_value = raw_line.partition("=")
        if not sep:
            raise IniError(f"line {lineno}: missing '=' in {raw_line!r}")
        key_token = raw_key.strip()
        match = _KEY_RE.match(key_token)
        if not match:
            raise IniError(f"line {lineno}: unparsable key {key_token!r}")
        op, key, index_text = match.groups()
        value, fallback = parse_value(raw_value)
        current.entries.append(
            Entry(
                key=key,
                op=_OP_NAMES[op],
                index=int(index_text) if index_text is not None else None,
                raw_key=key_token,
                raw_value=raw_value,
                value=value,
                fallback=fallback,
            )
        )
    return sections


# ---------------------------------------------------------------------------
# Section accessors
# ---------------------------------------------------------------------------


def _entry(section: Section, key: str, index: int | None = None) -> Entry:
    matches = [
        e
        for e in section.entries
        if e.key == key and (index is None or e.index == index)
    ]
    if not matches:
        where = f"{key}[{index}]" if index is not None else key
        raise IniError(f"{section.name}: missing authored key {where!r}")
    entry = matches[-1]
    if entry.index is not None and index is None:
        raise IniError(f"{section.name}: {key!r} is indexed, use _indexed()")
    return entry


def _as_int(value: Any, where: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise IniError(f"{where}: expected integer, got {value!r}")
    return value


def _as_float(value: Any, where: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise IniError(f"{where}: expected number, got {value!r}")
    return float(value)


def _as_bool(value: Any, where: str) -> bool:
    if not isinstance(value, bool):
        raise IniError(f"{where}: expected bool, got {value!r}")
    return value


def _as_str(value: Any, where: str) -> str:
    if not isinstance(value, str):
        raise IniError(f"{where}: expected string, got {value!r}")
    return value


def _as_list(value: Any, where: str) -> list[Any]:
    if not isinstance(value, list):
        raise IniError(f"{where}: expected list, got {value!r}")
    return value


def _as_dict(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise IniError(f"{where}: expected struct, got {value!r}")
    return value


def _tag(value: Any, where: str) -> str:
    struct = _as_dict(value, where)
    if set(struct) != {"TagName"}:
        raise IniError(f"{where}: expected (TagName=...), got {struct!r}")
    return _as_str(struct["TagName"], f"{where}.TagName")


def _int(section: Section, key: str) -> int:
    return _as_int(_entry(section, key).value, f"{section.name} {key}")


def _float(section: Section, key: str) -> float:
    return _as_float(_entry(section, key).value, f"{section.name} {key}")


def _bool(section: Section, key: str) -> bool:
    return _as_bool(_entry(section, key).value, f"{section.name} {key}")


def _str(section: Section, key: str) -> str:
    return _as_str(_entry(section, key).value, f"{section.name} {key}")


def _struct(section: Section, key: str, index: int | None = None) -> dict:
    return _as_dict(_entry(section, key, index).value, f"{section.name} {key}")


def effective_array(section: Section, key: str) -> list[Any]:
    """Apply ``+``/``-``/``!``/``.``/set semantics in source order."""
    out: list[Any] = []
    for entry in section.entries:
        if entry.key != key or entry.index is not None:
            continue
        if entry.op == "set":
            # A plain Key=(A,B) replaces the whole array; a plain Key=(X=1)
            # on an array-of-structs is a one-element array literal.
            out = list(entry.value) if isinstance(entry.value, list) else [entry.value]
        elif entry.op == "add":
            out.append(entry.value)
        elif entry.op == "remove":
            if entry.value in out:
                out.remove(entry.value)
        elif entry.op == "clear":
            out = []
        elif entry.op == "add_unique":
            if entry.value not in out:
                out.append(entry.value)
    return out


def indexed_values(section: Section, key: str) -> list[tuple[int, Any]]:
    """All ``Key[n]`` entries, ordered by index; indices must be contiguous."""
    found: dict[int, Any] = {}
    for entry in section.entries:
        if entry.key != key or entry.index is None:
            continue
        found[entry.index] = entry.value
    if not found:
        raise IniError(f"{section.name}: missing indexed key {key!r}")
    expected = set(range(max(found) + 1))
    if set(found) != expected:
        raise IniError(
            f"{section.name}: {key} indices are not contiguous: {sorted(found)}"
        )
    return [(i, found[i]) for i in sorted(found)]


def raw_map(section: Section) -> dict[str, str | list[str]]:
    """Exact authored text per key; repeated keys become ordered lists."""
    grouped: dict[str, list[str]] = {}
    for entry in section.entries:
        grouped.setdefault(entry.raw_name, []).append(entry.raw_value)
    return {
        key: values[0] if len(values) == 1 else values
        for key, values in sorted(grouped.items())
    }


def _assert_structured(section: Section) -> None:
    """Typed sections must parse every value; a fallback would hide a bug."""
    for entry in section.entries:
        if entry.fallback and entry.raw_value.lstrip().startswith("("):
            raise IniError(
                f"{section.name} line entry {entry.raw_name!r}: "
                f"structured value did not parse: {entry.raw_value!r}"
            )


def _class_ref_path(value: str) -> str:
    """``/Script/Engine.CurveTable'/Game/x.CT_X'`` -> ``/Game/x.CT_X``."""
    match = _CLASS_REF_RE.match(value)
    return match.group(1) if match else value


def _section(sections: dict[str, Section], name: str) -> Section:
    if name not in sections:
        raise IniError(f"missing section [{name}]")
    return sections[name]


# ---------------------------------------------------------------------------
# Payload
# ---------------------------------------------------------------------------


def _progression(section: Section) -> dict[str, Any]:
    _assert_structured(section)
    xp_to_level = _struct(section, "XPToLevel")
    curve = _as_dict(xp_to_level.get("Curve"), f"{section.name} XPToLevel.Curve")
    styles = []
    for index, value in indexed_values(section, "UpgradeEditorProgressionNodeStyles"):
        struct = _as_dict(value, f"{section.name} style {index}")
        color = _as_dict(struct.get("Color"), "style color")
        styles.append(
            {
                "index": index,
                "style": _as_str(struct.get("Style"), "style"),
                "color": {
                    name: _as_float(color.get(name), f"style color {name}")
                    for name in ("R", "G", "B", "A")
                },
            }
        )
    return {
        "maximum_level": _int(section, "MaximumLevel"),
        "level_up_xp": _int(section, "LevelUpXP"),
        "xp_per_minute": _float(section, "XPPerMinute"),
        "maximum_time_in_game_xp": _float(section, "MaximumTimeInGameXP"),
        "win_xp": _float(section, "WinXP"),
        "mission_xp": _float(section, "MissionXP"),
        "contracts_xp": _float(section, "ContractsXP"),
        "open_queue_xp": _float(section, "OpenQueueXP"),
        "major_loot_xp": _float(section, "MajorLootXP"),
        "minor_loot_xp": _float(section, "MinorLootXP"),
        "looting_player_xp_multiplier": _float(section, "LootingPlayerXPMultiplier"),
        "coop_xp_multiplier": _float(section, "CoopXPMultiplier"),
        "difficulty_xp_multipliers": {
            "Easy": _float(section, "EasyDifficultyXPMultiplier"),
            "Normal": _float(section, "NormalDifficultyXPMultiplier"),
            "Hard": _float(section, "HardDifficultyXPMultiplier"),
        },
        "ftue_level_up_xp_categories": [
            _tag(value, f"{section.name} FtueLevelUpXPCategories")
            for value in effective_array(section, "FtueLevelUpXPCategories")
        ],
        "ftue_level_up_xp_is_on_top_of_regular_xp": _bool(
            section, "FtueLevelUpXpIsOnTopOfRegularXp"
        ),
        "player_stat_data_table": _str(section, "PlayerStatDataTable"),
        "xp_data_table": _str(section, "XPDataTable"),
        "xp_to_level_table": _str(section, "XPToLevelTable"),
        "xp_to_level": {
            "table": _class_ref_path(
                _as_str(curve.get("CurveTable"), "XPToLevel.Curve.CurveTable")
            ),
            "row": _as_str(curve.get("RowName"), "XPToLevel.Curve.RowName"),
            "value": _as_float(xp_to_level.get("Value"), "XPToLevel.Value"),
            "registry_type": _as_str(
                xp_to_level.get("RegistryType"), "XPToLevel.RegistryType"
            ),
        },
        "upgrade_editor_progression_node_styles": styles,
        "raw": raw_map(section),
    }


def _pair(value: Any, where: str) -> tuple[Any, Any]:
    pair = _as_list(value, where)
    if len(pair) != 2:
        raise IniError(f"{where}: expected a 2-tuple, got {pair!r}")
    return pair[0], pair[1]


def _map_entry(value: Any, where: str) -> dict[str, Any]:
    struct = _as_dict(value, where)
    missions = [
        _tag(item, f"{where}.Missions")
        for item in _as_list(struct.get("Missions"), f"{where}.Missions")
    ]
    scaling = _as_dict(struct.get("MeshScaling"), f"{where}.MeshScaling")
    coords = _as_dict(
        struct.get("CoordinatesOnCityMap"), f"{where}.CoordinatesOnCityMap"
    )
    out = {
        "tag": _tag(struct.get("MapTag"), f"{where}.MapTag"),
        "map": _as_str(struct.get("Map"), f"{where}.Map"),
        "game_mode": _as_str(struct.get("GameMode"), f"{where}.GameMode"),
        "map_name": _as_str(struct.get("MapName"), f"{where}.MapName"),
        "map_display_name": _as_str(
            struct.get("MapDisplayName"), f"{where}.MapDisplayName"
        ),
        "missions": missions,
        "mesh_scaling": {
            name: _as_float(scaling.get(name), f"{where}.MeshScaling.{name}")
            for name in ("X", "Y", "Z")
        },
        "coordinates_on_city_map": {
            name: _as_float(coords.get(name), f"{where}.CoordinatesOnCityMap.{name}")
            for name in ("X", "Y")
        },
        "raw": struct,
    }
    for authored, field_name in (
        ("MapFlavorText", "map_flavor_text"),
        ("SplashImage", "splash_image"),
        ("MapPreviewMesh", "map_preview_mesh"),
    ):
        if authored in struct:
            out[field_name] = _as_str(struct[authored], f"{where}.{authored}")
    if not missions:
        raise IniError(f"{where}: authored Missions list is empty")
    return out


def _project(section: Section) -> dict[str, Any]:
    _assert_structured(section)
    contracts = []
    for value in effective_array(section, "PostFtueContracts"):
        tag, requirement = _pair(value, f"{section.name} PostFtueContracts")
        contracts.append(
            {
                "tag": _tag(tag, f"{section.name} PostFtueContracts tag"),
                "requirement": _as_str(
                    requirement, f"{section.name} PostFtueContracts requirement"
                ),
            }
        )
    tutorials = []
    for value in effective_array(section, "PostMatchUnlockTutorials"):
        tag, runner = _pair(value, f"{section.name} PostMatchUnlockTutorials")
        tutorials.append(
            {
                "tag": _tag(tag, f"{section.name} PostMatchUnlockTutorials tag"),
                "tutorial_runner": _as_str(
                    runner, f"{section.name} PostMatchUnlockTutorials runner"
                ),
            }
        )
    maps = [
        _map_entry(value, f"{section.name} Maps[{i}]")
        for i, value in enumerate(effective_array(section, "Maps"))
    ]
    map_types = []
    for index, value in indexed_values(section, "MapTypeSettings"):
        struct = _as_dict(value, f"{section.name} MapTypeSettings[{index}]")
        row: dict[str, Any] = {"index": index}
        for authored, field_name in (
            ("AllowDefaultPlayerTools", "allow_default_player_tools"),
            (
                "AddDefaultPlayerGearLoadoutOnSpawn",
                "add_default_player_gear_loadout_on_spawn",
            ),
            ("UseMapIntroStates", "use_map_intro_states"),
            ("AllowActiveQuests", "allow_active_quests"),
            ("RunMapVariation", "run_map_variation"),
        ):
            if authored not in struct:
                raise IniError(
                    f"{section.name} MapTypeSettings[{index}]: missing {authored!r}"
                )
            row[field_name] = _as_bool(
                struct[authored], f"{section.name} MapTypeSettings[{index}].{authored}"
            )
        row["raw"] = struct
        map_types.append(row)

    durations = [
        _as_float(value, f"{section.name} EndgameDurationsByDifficulty[{index}]")
        for index, value in indexed_values(section, "EndgameDurationsByDifficulty")
    ]

    return {
        "settings_string_table": _str(section, "SettingsStringTable"),
        "hub_map_name": _str(section, "HubMapName"),
        "enable_thieves_den": _bool(section, "EnableThievesDen"),
        "create_joinable_session_in_thieves_den": _bool(
            section, "CreateJoinableSessionInThievesDen"
        ),
        "thieves_den_map_name": _str(section, "ThievesDenMapName"),
        "show_tutorial_map_after_complete": _bool(
            section, "ShowTutorialMapAfterComplete"
        ),
        "show_normal_play_if_tutorial_unstarted": _bool(
            section, "ShowNormalPlayIfTutorialUnstarted"
        ),
        "post_ftue_contracts": contracts,
        "ftue_min_thieves_den_money": _int(section, "FtueMinThievesDenMoney"),
        "post_match_unlock_tutorials": tutorials,
        "maps": maps,
        "map_type_settings": map_types,
        "endgame_durations_by_difficulty": durations,
        "endgame_duration_seconds_by_difficulty_index": {
            str(index): value for index, value in enumerate(durations)
        },
        "stashed_loot_value_to_trigger_endgame": _int(
            section, "StashedLootValueToTriggerEndgame"
        ),
        "match_essentially_complete_threshold": _float(
            section, "MatchEssentiallyCompleteThreshold"
        ),
        "initial_unlocked_content": [
            _tag(value, f"{section.name} InitialUnlockedContent")
            for value in effective_array(section, "InitialUnlockedContent")
        ],
        "post_ftue_unlocked_content": [
            _tag(value, f"{section.name} PostFtueUnlockedContent")
            for value in effective_array(section, "PostFtueUnlockedContent")
        ],
        "mission_data_table": _str(section, "MissionDataTable"),
        "editor_mission_data_table": _str(section, "EditorMissionDataTable"),
        "contract_data_table": _str(section, "ContractDataTable"),
        "difficulty_property_name": _str(section, "DifficultyPropertyName"),
        # The ini never names the difficulty indices; see module docstring.
        "difficulty_index_source": "unproven: index order only",
        "unlockable_content_data": _str(section, "UnlockableContentData"),
        "default_match_settings_class": _str(section, "DefaultMatchSettingsClass"),
        "default_character_metadata": _str(section, "DefaultCharacterMetadata"),
        "map_sprite_data": _str(section, "MapSpriteData"),
        "transient_map_actor_data": _str(section, "TransientMapActorData"),
        "end_match_rpc_delay_seconds": _float(section, "EndMatchRPCDelaySeconds"),
        "cleanup_delay_after_match_end_seconds": _float(
            section, "CleanupDelayAfterMatchEndSeconds"
        ),
        "maximum_dedicated_server_match_duration_minutes": _float(
            section, "MaximumDedicatedServerMatchDurationMinutes"
        ),
        "auto_exit_dedicated_server_process": _bool(
            section, "AutoExitDedicatedServerProcess"
        ),
        "pvp_game_mode": _str(section, "PvpGameMode"),
        "raw": raw_map(section),
    }


def _scoring(section: Section) -> dict[str, Any]:
    _assert_structured(section)
    return {
        "escape_order_bonus_curve": _str(section, "EscapeOrderBonus"),
        "mission_complete_bonus": _float(section, "MissionCompleteBonus"),
        "contract_complete_bonus": _float(section, "ContractCompleteBonus"),
        "stashed_loot_value_multiplier_bonus": _float(
            section, "StashedLootValueMultiplierBonus"
        ),
        "carried_loot_value_multiplier_bonus": _float(
            section, "CarriedLootValueMultiplierBonus"
        ),
        "raw": raw_map(section),
    }


def _general(session: Section, general: Section) -> dict[str, Any]:
    out = {
        "max_players": _int(session, "MaxPlayers"),
        "project_name": _str(general, "ProjectName"),
        "project_version": _str(general, "ProjectVersion"),
        "company_name": _str(general, "CompanyName"),
    }
    for authored, field_name in (
        ("ProjectID", "project_id"),
        ("CompanyDistinguishedName", "company_distinguished_name"),
        ("Homepage", "homepage"),
        ("Description", "description"),
        ("CopyrightNotice", "copyright_notice"),
        ("SupportContact", "support_contact"),
    ):
        if any(e.key == authored for e in general.entries):
            out[field_name] = _str(general, authored)
    out["max_players_raw"] = raw_map(session)
    out["raw"] = raw_map(general)
    return out


def build_payload(text: str, source_sha256: str) -> dict[str, Any]:
    """Build the full payload from ini text (usable with fixture text)."""
    sections = parse_ini_text(text)
    progression = _section(sections, PROGRESSION)
    project = _section(sections, PROJECT)
    scoring = _section(sections, SCORING)
    session = _section(sections, GAME_SESSION)
    general = _section(sections, GENERAL)

    unmapped: list[str] = []
    payload = {
        "schema": SCHEMA,
        "generated_by": GENERATED_BY,
        "source": SOURCE_REL,
        "source_sha256": source_sha256,
        "progression": _progression(progression),
        "project": _project(project),
        "scoring": _scoring(scoring),
        "general": _general(session, general),
        "unmapped_keys": unmapped,
    }
    # Fail closed if a covered section ever stops being fully represented.
    for section, raw in (
        (progression, payload["progression"]["raw"]),
        (project, payload["project"]["raw"]),
        (scoring, payload["scoring"]["raw"]),
        (session, payload["general"]["max_players_raw"]),
        (general, payload["general"]["raw"]),
    ):
        missing = sorted({e.raw_name for e in section.entries} - set(raw))
        if missing:
            raise IniError(f"{section.name}: keys missing from raw: {missing}")
        unmapped.extend(missing)
    return payload


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit project_settings.json from DefaultGame.ini."
    )
    parser.add_argument(
        "--extracted",
        type=Path,
        default=ROOT / "extracted",
        help="extracted tree root (default: <repo>/extracted)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=ROOT / "game" / "data" / "generated",
        help="output directory (default: <repo>/game/data/generated)",
    )
    parser.add_argument("--quiet", action="store_true", help="no stdout summary")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    source = args.extracted.joinpath(*SOURCE_PARTS)
    if not source.is_file():
        print(f"error: missing source file {source}", file=sys.stderr)
        return 1
    try:
        data = source.read_bytes()
        payload = build_payload(data.decode("utf-8"), hashlib.sha256(data).hexdigest())
    except (OSError, UnicodeDecodeError, IniError) as exc:
        print(f"error: {source}: {exc}", file=sys.stderr)
        return 1

    out = args.out_dir / OUT_NAME
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except OSError as exc:
        print(f"error: cannot write {out}: {exc}", file=sys.stderr)
        return 1
    if not args.quiet:
        print(
            f"wrote {out} "
            f"({len(payload['project']['maps'])} maps, "
            f"{len(payload['project']['map_type_settings'])} map types, "
            f"{len(payload['project']['raw'])} project raw keys)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
