#!/usr/bin/env python3
"""Fail-closed validator for the logic data produced by the W5E producers.

Validates the three generated payloads (all gitignored) and the committed
report that summarises one of them:

    game/data/generated/gameplay/unlocks.json        tools/parse_unlocks.py
    game/data/generated/gameplay/hearing.json        tools/parse_hearing.py
    game/data/generated/gameplay/perception.json     tools/parse_hearing.py
    game/data/generated/gameplay/guard_behavior.json tools/parse_state_tree.py
    docs/reports/w5e-guard-state-tree.md             tools/parse_state_tree.py

The expected values below are the measured shipped-build counts, kept here
independently of the producers so a producer bug cannot validate itself:

* 68 unlockable entries, 4 KF08-anchored prices.
* 54 hearing stimuli, 22 loudness surfaces, 11 weather types, 285 acoustic
  portals across 7 sublevels, 5 hearing + 4 vision range modifiers.
* 21 StateTrees (ST_Guard 126/148, ST_Civilian 73/82), 467 transitions total,
  6 condition Blueprints, 28 task Blueprints, 9 targeting considerations.

It also re-derives every internal statistic (counts, extents, metre mirrors,
basis orthonormality, transition targets, child/parent consistency) instead of
trusting the ``stats`` blocks, and cross-checks the two hearing/perception views
of weather sound-carry against each other.

Exit 0 only when every check passes.
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "game" / "data" / "generated" / "gameplay"
UNLOCKS = GEN / "unlocks.json"
HEARING = GEN / "hearing.json"
PERCEPTION = GEN / "perception.json"
GUARD = GEN / "guard_behavior.json"
DEVICES = GEN / "devices_runtime.json"
REPORT = ROOT / "docs" / "reports" / "w5e-guard-state-tree.md"

SCHEMA_UNLOCKS = "tat2.unlocks/1"
SCHEMA_HEARING = "tat2.hearing/1"
SCHEMA_PERCEPTION = "tat2.perception/1"
SCHEMA_GUARD = "tat2.guard_behavior/1"

EXPECTED_UNLOCK_ENTRIES = 68
KF08_PRICES = {
    "Outfit.Spider.Head.Hair.Bob": 7500,
    "Outfit.Spider.Head.MustacheA": 5000,
    "Outfit.Spider.Head.BeardA": 7500,
    "Outfit.Spider.Head.EyepatchA": 2500,
}
CONTENT_TYPES = {"Difficulty", "Gear", "Map", "Thief", "Cosmetic"}
SHOP_CATEGORIES = {
    "guild_perks",
    "tools",
    "spider_cosmetics",
    "chameleon_cosmetics",
}
UNLOCK_TYPES = {"RequiredLevel", "RequiredContract"}

EXPECTED_HEARING_ROWS = 54
EXPECTED_LOUDNESS_SURFACES = 22
EXPECTED_WEATHER_ROWS = 11
EXPECTED_VISION_ROWS = 8
EXPECTED_PORTALS = 285
EXPECTED_PORTAL_SUBLEVELS = 7
EXPECTED_RUNTIME_PORTALS = 14
EXPECTED_MATCHED_PORTALS = 12
EXPECTED_BITMASK_HISTOGRAM = {30: 2, 62: 1, 86: 1, 127: 50}
LOUDNESS_ANCHORS = {"Carpet": 0.0, "Stone": 1.5, "Lattice": 1.0, "Glass": 1.5}
HEARING_MODIFIER_ANCHORS = {
    "Status.Nervous": 1.2,
    "Weather.SoundCarry.High": 1.0,
    "Weather.SoundCarry.Mid": 0.9,
    "Weather.SoundCarry.Low": 0.8,
    "Weather.SoundCarry.High_Extra": 1.25,
}
VISION_MODIFIER_ANCHORS = {"AI.Status.Escalation.Drowsy.Asleep": 0.1}
SEVERITIES = {"Light", "Heavy"}
CARRY_LEVELS = {"High", "Mid", "Low"}
VISIBILITY_LEVELS = {"High", "Mid", "Low"}

EXPECTED_TREES = 21
EXPECTED_GUARD = (126, 148)
EXPECTED_CIVILIAN = (73, 82)
EXPECTED_STATES_TOTAL = 459
EXPECTED_TRANSITIONS_TOTAL = 467
EXPECTED_CONDITIONALS = 6
EXPECTED_TASKS = 28
EXPECTED_CONSIDERATIONS = 9
EXPECTED_DISABLED = 7
EXPECTED_SUBTREE_LINKS = 45
EXPECTED_EVENTS = 17
CORE_EVENTS = {
    "StateTreeEvent.TargetChange",
    "StateTreeEvent.StimChange",
    "StateTreeEvent.GameplayTagChange",
    "StateTreeEvent.LockdownEvent",
}
SPECIAL_HANDLES = {65534: "Succeeded", 65533: "Next", 65535: "Invalid"}
BASIS_TOL = 1e-3


class Check:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.checks = 0
        self.section = ""

    def start(self, name: str) -> None:
        self.section = name

    def expect(self, condition: bool, message: str) -> None:
        self.checks += 1
        if not condition:
            self.failures.append(f"[{self.section}] {message}")

    def equal(self, have, want, label: str) -> None:
        self.expect(have == want, f"{label}: have {have!r}, want {want!r}")

    def close(self, have, want, label: str, tol: float = 1e-4) -> None:
        ok = (
            isinstance(have, (int, float))
            and not isinstance(have, bool)
            and abs(float(have) - float(want)) <= tol
        )
        self.expect(ok, f"{label}: have {have!r}, want {want!r} (+-{tol})")


def load(check: Check, path: Path, producer: str) -> dict | None:
    if not path.is_file():
        check.expect(False, f"missing {path.relative_to(ROOT)} (run {producer})")
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        check.expect(False, f"{path.name}: invalid JSON ({exc})")
        return None
    if not isinstance(data, dict):
        check.expect(False, f"{path.name}: top level is not an object")
        return None
    return data


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def basis_ok(basis) -> bool:
    if not isinstance(basis, list) or len(basis) != 9:
        return False
    try:
        values = [float(v) for v in basis]
    except (TypeError, ValueError):
        return False
    cols = [values[0:3], values[3:6], values[6:9]]
    for col in cols:
        if abs(math.sqrt(sum(v * v for v in col)) - 1.0) > BASIS_TOL:
            return False
    for i in range(3):
        for j in range(i + 1, 3):
            if abs(sum(cols[i][k] * cols[j][k] for k in range(3))) > BASIS_TOL:
                return False
    det = (
        cols[0][0] * (cols[1][1] * cols[2][2] - cols[1][2] * cols[2][1])
        - cols[0][1] * (cols[1][0] * cols[2][2] - cols[1][2] * cols[2][0])
        + cols[0][2] * (cols[1][0] * cols[2][1] - cols[1][1] * cols[2][0])
    )
    return det > 0.0


# ---------------------------------------------------------------------------
# unlocks.json
# ---------------------------------------------------------------------------
def check_unlocks(check: Check) -> None:
    check.start("unlocks")
    data = load(check, UNLOCKS, "python3 tools/parse_unlocks.py")
    if data is None:
        return
    check.equal(data.get("schema"), SCHEMA_UNLOCKS, "schema")
    entries = data.get("entries")
    if not isinstance(entries, list):
        check.expect(False, "entries is not a list")
        return
    check.equal(len(entries), EXPECTED_UNLOCK_ENTRIES, "entry count")

    tags = [entry.get("tag") for entry in entries]
    check.equal(len(set(tags)), len(tags), "unique tags")
    prices = {entry.get("tag"): entry.get("price") for entry in entries}
    for tag, want in KF08_PRICES.items():
        check.equal(prices.get(tag), want, f"KF08 price {tag}")

    bad_price = [
        tag
        for tag, price in prices.items()
        if not isinstance(price, int) or isinstance(price, bool) or price < 0
    ]
    check.expect(not bad_price, f"prices must be non-negative ints: {bad_price[:5]}")

    for entry in entries:
        tag = entry.get("tag")
        check.expect(bool(tag) and isinstance(tag, str), f"{tag}: tag is a string")
        check.expect(
            entry.get("content_type") in CONTENT_TYPES,
            f"{tag}: content_type {entry.get('content_type')!r}",
        )
        check.expect(
            entry.get("shop_category") in SHOP_CATEGORIES,
            f"{tag}: shop_category {entry.get('shop_category')!r}",
        )
        display = entry.get("display") or {}
        for field in ("title", "description"):
            block = display.get(field) or {}
            check.expect(
                bool(str(block.get("text", "")).strip()),
                f"{tag}: {field} text is empty",
            )
            check.expect(
                bool(block.get("key")) and bool(block.get("table")),
                f"{tag}: {field} key/table missing",
            )
        unlock = entry.get("unlock") or {}
        for cond in unlock.get("conditions") or []:
            check.expect(
                cond.get("type") in UNLOCK_TYPES,
                f"{tag}: unlock type {cond.get('type')!r}",
            )
            level = cond.get("level")
            check.expect(
                isinstance(level, int) and not isinstance(level, bool) and level >= 0,
                f"{tag}: unlock level {level!r}",
            )
            contract = cond.get("contract")
            check.expect(
                contract is None or str(contract).startswith("Contract"),
                f"{tag}: contract {contract!r}",
            )

    stats = data.get("stats") or {}
    check.equal(
        stats.get("by_content_type"),
        dict(sorted(Counter(e["content_type"] for e in entries).items())),
        "by_content_type",
    )
    check.equal(
        stats.get("by_shop_category"),
        dict(sorted(Counter(e["shop_category"] for e in entries).items())),
        "by_shop_category",
    )
    check.equal(
        stats.get("by_unlock_type"),
        dict(
            sorted(
                Counter(
                    c["type"] for e in entries for c in e["unlock"]["conditions"]
                ).items()
            )
        ),
        "by_unlock_type",
    )
    check.equal(
        stats.get("priced_entries"),
        sum(1 for e in entries if e["price"] > 0),
        "priced_entries",
    )
    check.equal(
        stats.get("free_entries"),
        sum(1 for e in entries if e["price"] == 0),
        "free_entries",
    )
    check.equal(stats.get("min_price"), min(prices.values()), "min_price")
    check.equal(stats.get("max_price"), max(prices.values()), "max_price")
    check.equal(
        stats.get("conditions"),
        sum(len(e["unlock"]["conditions"]) for e in entries),
        "condition count",
    )
    provenance = (data.get("price_provenance") or {}).get("kf08") or {}
    check.equal(
        [row.get("price") for row in provenance.get("verified") or []],
        [KF08_PRICES[tag] for tag in KF08_PRICES],
        "KF08 verified order/prices",
    )


# ---------------------------------------------------------------------------
# hearing.json
# ---------------------------------------------------------------------------
def check_hearing(check: Check, perception: dict | None) -> None:
    check.start("hearing")
    data = load(check, HEARING, "python3 tools/parse_hearing.py")
    if data is None:
        return
    check.equal(data.get("schema"), SCHEMA_HEARING, "schema")

    stimuli = data.get("stimuli")
    if not isinstance(stimuli, list):
        check.expect(False, "stimuli is not a list")
        return
    check.equal(len(stimuli), EXPECTED_HEARING_ROWS, "stimulus rows")
    check.equal(len({s.get("tag") for s in stimuli}), len(stimuli), "unique tags")
    check.equal(len({s.get("row") for s in stimuli}), len(stimuli), "unique rows")
    histogram = Counter(s.get("query_bitmask") for s in stimuli)
    check.equal(dict(histogram), EXPECTED_BITMASK_HISTOGRAM, "query bitmask histogram")

    for stim in stimuli:
        row = stim.get("row")
        check.expect(
            stim.get("severity") in SEVERITIES,
            f"{row}: severity {stim.get('severity')!r}",
        )
        check.expect(bool(stim.get("propagation")), f"{row}: propagation empty")
        heard_by = stim.get("heard_by") or {}
        check.equal(
            set(heard_by),
            {"hostiles", "neutrals", "friendlies"},
            f"{row}: heard_by keys",
        )
        for key, value in heard_by.items():
            check.expect(isinstance(value, bool), f"{row}: heard_by.{key} not bool")
        for field in (
            "max_range_cm",
            "inner_investigation_range_cm",
            "outer_investigation_range_cm",
        ):
            check.expect(is_number(stim.get(field)), f"{row}: {field} not numeric")
        metric = stim.get("metric") or {}
        check.close(
            metric.get("max_range_m"),
            stim["max_range_cm"] / 100.0,
            f"{row}: max_range_m mirror",
        )
        check.close(
            metric.get("inner_investigation_range_m"),
            stim["inner_investigation_range_cm"] / 100.0,
            f"{row}: inner mirror",
        )
        check.close(
            metric.get("outer_investigation_range_m"),
            stim["outer_investigation_range_cm"] / 100.0,
            f"{row}: outer mirror",
        )
        behaviours = stim.get("behaviors")
        check.expect(
            isinstance(behaviours, list)
            and behaviours
            and all(isinstance(b, str) and b for b in behaviours),
            f"{row}: behaviors must be a non-empty string list",
        )
        bitmask = stim.get("query_bitmask")
        check.expect(
            isinstance(bitmask, int)
            and not isinstance(bitmask, bool)
            and 0 <= bitmask <= 255,
            f"{row}: query_bitmask {bitmask!r} outside 0..255",
        )

    loudness = data.get("loudness_modifiers") or {}
    surfaces = loudness.get("by_surface") or {}
    check.equal(len(surfaces), EXPECTED_LOUDNESS_SURFACES, "loudness surfaces")
    for name, want in LOUDNESS_ANCHORS.items():
        check.equal(
            (surfaces.get(name) or {}).get("multiplier"), want, f"loudness/{name}"
        )
    for name, row in surfaces.items():
        check.expect(
            is_number(row.get("multiplier")), f"loudness/{name}: multiplier not numeric"
        )
        check.expect(bool(row.get("package")), f"loudness/{name}: package empty")

    carry = data.get("weather_sound_carry") or {}
    check.equal(len(carry), EXPECTED_WEATHER_ROWS, "weather sound-carry rows")
    hearing_mods = {
        row.get("tag"): row.get("range_multiplier")
        for row in ((data.get("perception_modifiers") or {}).get("hearing") or [])
    }
    for tag, want in HEARING_MODIFIER_ANCHORS.items():
        check.close(hearing_mods.get(tag), want, f"hearing modifier {tag}")
    for weather_tag, row in carry.items():
        for context in ("indoors", "outdoors"):
            side = (row or {}).get(context) or {}
            check.expect(
                side.get("level") in CARRY_LEVELS,
                f"{weather_tag}/{context}: carry level {side.get('level')!r}",
            )
            check.equal(
                side.get("range_multiplier"),
                hearing_mods.get(side.get("tag")),
                f"{weather_tag}/{context}: multiplier must match hearing config",
            )

    portals = data.get("acoustic_portals") or {}
    check.equal(portals.get("class"), "BP_TATAcousticPortal_C", "portal class")
    check.equal(portals.get("count"), EXPECTED_PORTALS, "portal count")
    check.equal(
        portals.get("box_extent_cm"), [100.0, 100.0, 100.0], "portal box extent"
    )
    rows = portals.get("portals")
    if not isinstance(rows, list):
        check.expect(False, "portals is not a list")
        return
    check.equal(len(rows), EXPECTED_PORTALS, "portal rows")
    check.equal(len({row.get("id") for row in rows}), len(rows), "unique portal ids")
    by_sublevel = Counter(row.get("sublevel") for row in rows)
    check.equal(
        dict(sorted(by_sublevel.items())),
        portals.get("by_sublevel"),
        "portal by_sublevel",
    )
    check.equal(len(by_sublevel), EXPECTED_PORTAL_SUBLEVELS, "portal sublevels")
    for row in rows:
        pid = row.get("id")
        pos = row.get("pos")
        scale = row.get("scale")
        check.expect(
            isinstance(pos, list) and len(pos) == 3 and all(is_number(v) for v in pos),
            f"{pid}: pos must be 3 numbers",
        )
        check.expect(basis_ok(row.get("basis")), f"{pid}: basis not orthonormal det+1")
        check.expect(
            isinstance(scale, list)
            and len(scale) == 3
            and all(is_number(v) and v > 0 for v in scale),
            f"{pid}: scale must be 3 positive numbers",
        )
        check.expect(bool(row.get("actor")), f"{pid}: actor empty")

    cross = portals.get("cross_check") or {}
    if DEVICES.is_file():
        check.equal(cross.get("available"), True, "runtime cross-check available")
        check.equal(
            cross.get("runtime_portals"), EXPECTED_RUNTIME_PORTALS, "runtime portals"
        )
        check.equal(cross.get("mismatched"), [], "portal transform mismatches")
        check.equal(cross.get("matched"), EXPECTED_MATCHED_PORTALS, "matched portals")
        check.equal(
            len(cross.get("runtime_unmatched") or []),
            EXPECTED_RUNTIME_PORTALS - EXPECTED_MATCHED_PORTALS,
            "runtime-only portal placements",
        )
    else:
        print("  note: devices_runtime.json absent; runtime portal cross-check skipped")

    stats = data.get("stats") or {}
    check.equal(stats.get("stimuli"), len(stimuli), "stats.stimuli")
    check.equal(
        stats.get("by_severity"),
        dict(sorted(Counter(s["severity"] for s in stimuli).items())),
        "stats.by_severity",
    )
    check.equal(
        stats.get("by_behaviour"),
        dict(sorted(Counter(b for s in stimuli for b in s["behaviors"]).items())),
        "stats.by_behaviour",
    )
    check.equal(
        stats.get("by_query_bitmask"),
        {str(k): v for k, v in sorted(histogram.items())},
        "stats.by_query_bitmask",
    )
    check.equal(stats.get("portals"), len(rows), "stats.portals")
    check.equal(
        stats.get("loudness_surfaces"), len(surfaces), "stats.loudness_surfaces"
    )
    check.equal(stats.get("weather_types"), len(carry), "stats.weather_types")

    if perception is not None:
        weather = ((perception.get("weather") or {}).get("by_type")) or {}
        check.equal(
            set(weather), set(carry), "hearing/perception weather type sets agree"
        )
        for tag, row in weather.items():
            for context in ("indoors", "outdoors"):
                check.equal(
                    row["sound_carry"][context]["tag"],
                    carry[tag][context]["tag"],
                    f"{tag}/{context}: carry tag agrees across files",
                )


# ---------------------------------------------------------------------------
# perception.json
# ---------------------------------------------------------------------------
def check_perception(check: Check) -> dict | None:
    check.start("perception")
    data = load(check, PERCEPTION, "python3 tools/parse_hearing.py")
    if data is None:
        return None
    check.equal(data.get("schema"), SCHEMA_PERCEPTION, "schema")
    senses = data.get("senses") or {}
    check.equal(set(senses), {"hearing", "vision_guard"}, "sense set")

    for name, anchors in (
        ("hearing", HEARING_MODIFIER_ANCHORS),
        ("vision_guard", VISION_MODIFIER_ANCHORS),
    ):
        sense = senses.get(name) or {}
        modifiers = {
            row.get("tag"): row.get("range_multiplier")
            for row in sense.get("range_modifiers") or []
        }
        check.expect(bool(sense.get("asset")), f"{name}: asset empty")
        check.expect(bool(sense.get("range_modifiers")), f"{name}: no modifiers")
        for tag, want in anchors.items():
            check.close(modifiers.get(tag), want, f"{name} modifier {tag}")

    weather = (data.get("weather") or {}).get("by_type") or {}
    check.equal(len(weather), EXPECTED_WEATHER_ROWS, "weather rows")
    for tag, row in weather.items():
        check.equal(row.get("tag"), tag, f"{tag}: WeatherType matches row key")
        for context in ("indoors", "outdoors"):
            check.expect(
                (row.get("visibility") or {}).get(context, {}).get("level")
                in VISIBILITY_LEVELS,
                f"{tag}/{context}: visibility level",
            )
            check.expect(
                (row.get("sound_carry") or {}).get(context, {}).get("level")
                in CARRY_LEVELS,
                f"{tag}/{context}: sound-carry level",
            )
        check.expect(
            str(row.get("level_filter_mode", "")).startswith(("Allow", "Use")),
            f"{tag}: level filter mode {row.get('level_filter_mode')!r}",
        )

    vision = (data.get("vision_stimuli") or {}).get("by_row") or {}
    check.equal(len(vision), EXPECTED_VISION_ROWS, "vision stimulus rows")
    for row, payload in vision.items():
        check.expect(payload.get("severity") in SEVERITIES, f"vision {row}: severity")
    return data


# ---------------------------------------------------------------------------
# guard_behavior.json + report
# ---------------------------------------------------------------------------
def check_guard(check: Check) -> None:
    check.start("guard_behavior")
    data = load(check, GUARD, "python3 tools/parse_state_tree.py")
    if data is None:
        return
    check.equal(data.get("schema"), SCHEMA_GUARD, "schema")
    trees = data.get("trees")
    if not isinstance(trees, dict):
        check.expect(False, "trees is not an object")
        return
    check.equal(len(trees), EXPECTED_TREES, "tree count")
    for root in ("ST_Guard", "ST_Civilian", "ST_OffNavLink"):
        check.expect(root in trees, f"missing root tree {root}")
        check.expect(root in (data.get("roots") or []), f"{root} not listed in roots")
    if "ST_Guard" in trees:
        stats = trees["ST_Guard"]["stats"]
        check.equal(
            (stats["states"], stats["transitions"]), EXPECTED_GUARD, "ST_Guard counts"
        )
    if "ST_Civilian" in trees:
        stats = trees["ST_Civilian"]["stats"]
        check.equal(
            (stats["states"], stats["transitions"]),
            EXPECTED_CIVILIAN,
            "ST_Civilian counts",
        )

    states_total = 0
    transitions_total = 0
    links_total = 0
    disabled_total = 0
    for name, tree in trees.items():
        states = tree.get("states")
        transitions = tree.get("transitions")
        if not isinstance(states, list) or not isinstance(transitions, list):
            check.expect(False, f"{name}: states/transitions not lists")
            continue
        states_total += len(states)
        transitions_total += len(transitions)
        links_total += tree["stats"]["subtree_links"]
        disabled_total += sum(1 for state in states if not state.get("enabled", True))
        check.expect(len(tree.get("roots") or []) >= 1, f"{name}: no root state")
        expected_children = {
            parent: [
                child
                for child in range(parent + 1, len(states))
                if states[child].get("parent_index") == parent
                and child
                < (states[parent].get("children_range") or [0, len(states)])[1]
            ]
            for parent in range(len(states))
        }
        check.equal(tree["stats"]["states"], len(states), f"{name}: stats.states")
        check.equal(
            tree["stats"]["transitions"],
            len(transitions),
            f"{name}: stats.transitions",
        )
        seen_transitions: list[int] = []
        for index, state in enumerate(states):
            check.equal(state.get("index"), index, f"{name}[{index}]: index")
            check.expect(bool(state.get("name")), f"{name}[{index}]: empty name")
            parent = state.get("parent_index")
            depth = state.get("depth")
            if parent is None:
                check.equal(depth, 0, f"{name}[{index}]: root depth")
            else:
                check.expect(
                    0 <= parent < index,
                    f"{name}[{index}]: parent {parent} must precede the state",
                )
                if 0 <= parent < len(states):
                    check.equal(
                        depth, states[parent]["depth"] + 1, f"{name}[{index}]: depth"
                    )
                    check.expect(
                        index in states[parent]["children"],
                        f"{name}[{index}]: not a child of its parent",
                    )
            for child in state.get("children") or []:
                check.expect(
                    0 <= child < len(states),
                    f"{name}[{index}]: child {child} out of range",
                )
                if 0 <= child < len(states):
                    check.equal(
                        states[child]["parent_index"],
                        index,
                        f"{name}[{index}]: child {child} parent",
                    )
            check.equal(
                state.get("children"),
                expected_children[index],
                f"{name}[{index}]: direct children do not match parent links",
            )
            for task in state.get("tasks") or []:
                check.expect(
                    bool(str(task).strip()), f"{name}[{index}]: empty task name"
                )
            for cond in state.get("enter_conditions") or []:
                check.expect(
                    bool(str(cond).strip()), f"{name}[{index}]: empty condition name"
                )
            for transition in state.get("transitions") or []:
                seen_transitions.append(transition["index"])
                target = transition.get("to_state_index")
                kind = transition.get("to_kind")
                if kind == "state":
                    check.expect(
                        isinstance(target, int) and 0 <= target < len(states),
                        f"{name}[{index}]: transition target {target} out of range",
                    )
                    check.equal(
                        transition.get("to_state"),
                        states[target]["name"]
                        if isinstance(target, int) and 0 <= target < len(states)
                        else None,
                        f"{name}[{index}]: transition target name",
                    )
                else:
                    check.equal(
                        kind,
                        SPECIAL_HANDLES.get(target),
                        f"{name}[{index}]: transition special handle {target}",
                    )
                check.expect(
                    bool(transition.get("trigger")),
                    f"{name}[{index}]: transition trigger empty",
                )
        check.equal(
            sorted(seen_transitions),
            list(range(len(transitions))),
            f"{name}: each transition is claimed exactly once",
        )
        for link in tree.get("subtree_links") or []:
            check.expect(
                link.get("asset") in trees,
                f"{name}: subtree {link.get('asset')!r} is not a recovered tree",
            )

    check.equal(states_total, EXPECTED_STATES_TOTAL, "states total")
    check.equal(transitions_total, EXPECTED_TRANSITIONS_TOTAL, "transitions total")
    check.equal(links_total, EXPECTED_SUBTREE_LINKS, "subtree links total")
    check.equal(disabled_total, EXPECTED_DISABLED, "disabled states total")

    leaves = data.get("stats", {}).get("leaf_blueprints") or {}
    check.equal(
        leaves.get("conditionals"), EXPECTED_CONDITIONALS, "condition Blueprints"
    )
    check.equal(leaves.get("tasks"), EXPECTED_TASKS, "task Blueprints")
    check.equal(
        leaves.get("targeting_considerations"),
        EXPECTED_CONSIDERATIONS,
        "targeting considerations",
    )
    check.equal(
        len(data.get("condition_classes") or []),
        EXPECTED_CONDITIONALS,
        "condition_classes",
    )
    check.equal(
        len(data.get("task_blueprints") or []), EXPECTED_TASKS, "task_blueprints"
    )
    check.equal(
        len(data.get("targeting_considerations") or []),
        EXPECTED_CONSIDERATIONS,
        "targeting_considerations list",
    )
    for leaf in data.get("condition_classes") or []:
        check.expect(
            leaf.get("name", "").startswith("STC_"),
            f"condition {leaf.get('name')} naming",
        )
        check.expect(
            bool(leaf.get("package")), f"condition {leaf.get('name')}: package"
        )
    for leaf in data.get("task_blueprints") or []:
        check.expect(
            leaf.get("name", "").startswith("STT_"), f"task {leaf.get('name')} naming"
        )

    events = set((data.get("stats") or {}).get("events") or [])
    check.equal(len(events), EXPECTED_EVENTS, "event count")
    check.expect(CORE_EVENTS <= events, f"missing core events: {CORE_EVENTS - events}")

    check.start("report")
    if not REPORT.is_file():
        check.expect(False, f"missing {REPORT.relative_to(ROOT)}")
        return
    text = REPORT.read_text(encoding="utf-8")
    check.expect(
        f"{EXPECTED_STATES_TOTAL} states" in text
        and f"{EXPECTED_TRANSITIONS_TOTAL} transitions" in text,
        "report totals do not match the payload (regenerate the report)",
    )
    for root in ("ST_Guard", "ST_Civilian"):
        check.expect(f"`{root}`" in text, f"report does not mention {root}")
    check.expect(
        "## Missing branches" in text, "report has no missing-branches section"
    )
    missing_heading = re.search(r"(\d+) of the (\d+) authored branches", text)
    check.expect(missing_heading is not None, "report missing-branch sentence absent")


def main() -> int:
    check = Check()
    check_unlocks(check)
    perception = check_perception(check)
    check_hearing(check, perception)
    check_guard(check)

    if check.failures:
        print(f"LOGIC_DATA FAIL: {len(check.failures)} of {check.checks} checks failed")
        for failure in check.failures:
            print(f"  - {failure}")
        return 1
    print(f"LOGIC_DATA PASS: {check.checks} checks, 0 failures")
    print(
        "  unlocks 68 (4 KF08 prices) | hearing 54 stim / 22 surfaces / "
        "11 weather / 285 portals | perception 2 senses / 8 vision stim | "
        "guard 21 trees / 459 states / 467 transitions"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
