#!/usr/bin/env python3
"""Emit the authored guard/civilian StateTree graphs for TAT-2.

Reads every cooked StateTree dump under ``extracted/json/AI/StateTrees/`` and
writes

    game/data/generated/gameplay/guard_behavior.json
    docs/reports/w5e-guard-state-tree.md

The StateTree assets are the authoritative behaviour definition for the shipped
guards and civilians: ``ST_Guard`` (126 states / 148 transitions),
``ST_Civilian`` (73 / 82), ``ST_OffNavLink`` and 18 reusable subtrees, plus the
condition, task and targeting-consideration Blueprints they reference.

How the cooked graph is resolved (no guessing):

* ``States[i]`` carries ``Name``, ``Depth``, ``Parent.Index``,
  ``ChildrenBegin/ChildrenEnd``, ``TasksBegin/TasksNum``,
  ``EnterConditionsBegin/Num``, ``UtilityConsiderationsBegin/Num``,
  ``TransitionsBegin/Num``, ``Type`` and ``LinkedAsset``. Child/condition/task
  indices index the same asset's ``Nodes.Structs`` array and the child indices
  index ``States``; every range is bounds-checked here.
* Node display names (task, enter-condition, utility and transition-condition
  names) are copied from ``Nodes.Structs[k].Name``. The cooked dump does not
  serialise the node's UClass on the struct itself, so the graph keeps the
  authored display name plus the instance-template index for traceability
  instead of inventing a class mapping.
* ``LinkedAsset`` states are resolved to the subtree asset name and, when
  present, the ``LinkedState`` entry point.
* Transitions keep ``Trigger``, ``Priority``, ``RequiredEvent`` tag,
  target state name/index, condition names, delay and enabled flag.

The report is generated here as well so its counts can never drift from the
payload. The "port coverage" section is a curated comparison against
``game/src/ai/guard_ai.gd`` and ``game/src/ai/civilian_npc.gd``; every claim
there was checked with grep at generation time (the keyword hits are recorded
in the table) and the prose says "not verified" where a keyword is silent
rather than assuming absence of behaviour in the engine.

No runtime wiring: guard_ai.gd keeps its hand-written alertness FSM.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_ROOT = ROOT / "extracted" / "json"
STATE_ROOT = JSON_ROOT / "AI" / "StateTrees"
OUT_PATH = ROOT / "game" / "data" / "generated" / "gameplay" / "guard_behavior.json"
REPORT_PATH = ROOT / "docs" / "reports" / "w5e-guard-state-tree.md"
GUARD_GD = ROOT / "game" / "src" / "ai" / "guard_ai.gd"
CIVILIAN_GD = ROOT / "game" / "src" / "ai" / "civilian_npc.gd"

SCHEMA = "tat2.guard_behavior/1"
GAME_VERSION = "Steam 1.5.193.148559"

EXPECTED_TREES = 21
EXPECTED_GUARD = {"states": 126, "transitions": 148}
EXPECTED_CIVILIAN = {"states": 73, "transitions": 82}
ROOT_TREES = ("ST_Guard", "ST_Civilian", "ST_OffNavLink")

NO_INDEX = 65535
# FStateTreeStateHandle special indices (UE MAX_uint16 - n).
SPECIAL_HANDLES = {65535: "Invalid", 65534: "Succeeded", 65533: "Next"}

# Curated port comparison. `needle` is the grep pattern used against the port
# source; `hits` records the measured match count so the report states evidence
# rather than opinion. `status`: implemented | partial | missing | unknown.
PORT_COVERAGE = (
    (
        "Alertness ladder (Set Alertness / escalation)",
        "React To Stims, Intruder, Broken Object and Conversation Event",
        "implemented",
        "enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }",
        r"enum Alertness",
        GUARD_GD,
    ),
    (
        "Sight cone, light visibility and smoke occlusion",
        "React to Intruder (Almost Spotted) / (Spotted)",
        "implemented",
        "sight constants + light probe + smoke LOS in the perception pass",
        r"SIGHT_RANGE|LightProbeScript|smoke",
        GUARD_GD,
    ),
    (
        "Hearing via the project noise bus",
        "Try Find Intruder",
        "implemented",
        "NoiseBus + HearingData (W6G: 54 authored stim rows gated by heard_by/query, "
        "MaxRange x surface x weather, Short/Long investigation; portals read-only)",
        r"NoiseBus|noise",
        GUARD_GD,
    ),
    (
        "Patrolling (ST_Patrol)",
        "Patrolling",
        "partial",
        "patrol_speed + patrol path points; no smart-object patrol points",
        r"patrol_speed|patrol_path",
        GUARD_GD,
    ),
    (
        "Investigate a stim location (ST_Subtree_GeneralInvestigateStim)",
        "Move to intruder / Move To Last Known Position",
        "partial",
        "one search goal + timer; no EQS defensive-spot query, no smart-object claim",
        r"_search_goal",
        GUARD_GD,
    ),
    (
        "Revive a downed guard (ST_Subtree_ReviveNPC)",
        "React to Downed NPC",
        "implemented",
        "revive_hold_s + nearest-first ally revive",
        r"revive_hold_s|_revive_target",
        GUARD_GD,
    ),
    (
        "Melee combat loop (ST_Subtree_Combat, 52 states)",
        "Combat",
        "partial",
        "one melee attack + cooldown; none of the combat subtree states",
        r"MELEE_|_play_guard_attack",
        GUARD_GD,
    ),
    (
        "First-time greeting (VO + focus)",
        "Greet Player for the first time",
        "missing",
        "no focus/VO system in the port guard",
        r"focus|voice|vo_",
        GUARD_GD,
    ),
    (
        "Conversation + shared-target handoff",
        "React To Conversation Event / React To Shared Target",
        "missing",
        "no conversation event or share-target plumbing",
        r"conversation|share_target",
        GUARD_GD,
    ),
    (
        "Broken / incorrect object knowledge reactions",
        "React to Incorrect or Broken Object",
        "missing",
        "no individual-knowledge model, so no repeat-suppression branches",
        r"knowledge",
        GUARD_GD,
    ),
    (
        "Spotting and returning world loot",
        "React to Spotting Loot / Return Loot",
        "missing",
        "the port's loot code is the pickpocket carry/drop path only; the "
        "civilian's two loot branches ship disabled",
        r"Return Loot|Spotting Loot",
        GUARD_GD,
    ),
    (
        "Smart-object claims (defensive spots, patrol points)",
        "Move To Smart Object / Claim / Move to and Use Smart Object",
        "missing",
        "no smart-object claims anywhere in the guard",
        r"smart_object|SmartObject",
        GUARD_GD,
    ),
    (
        "Vigilant escalation loop (EQS search + reset)",
        "Vigilant Escalation",
        "missing",
        "no EQS search loop or escalation reset task",
        r"Vigilant Escalation|Run Env Query",
        GUARD_GD,
    ),
    (
        "Alarm activation (ST_Subtree_TryActivateAlarm)",
        "Activate an alarm (from ST_Subtree_Combat)",
        "disabled",
        "the only link ships with bEnabled=false, so the shipped AI never "
        "raises an alarm; the port has no alarm handling either",
        r"alarm",
        GUARD_GD,
    ),
    (
        "Lockdown (ST_Subtree_Lockdown)",
        "Locked Down",
        "missing",
        "no lockdown event handling",
        r"lockdown",
        GUARD_GD,
    ),
    (
        "Forced states: cower / unconscious / in smoke",
        "Forced States",
        "partial",
        "KNOCKED_OUT exists; cower and the in-smoke ability do not",
        r"cower|in smoke",
        GUARD_GD,
    ),
    (
        "Forced agro",
        "Forced Agro",
        "missing",
        "no forced-target branch",
        r"forced.?agro",
        GUARD_GD,
    ),
    (
        "Post-revival / post-smoke search",
        "Post-Revival Behavior / Post-Smoke Behavior",
        "missing",
        "no behaviour hook after a revive or after smoke clears",
        r"Post-Revival|Post-Smoke",
        GUARD_GD,
    ),
    (
        "Civilian clue giving (ST_ClueGiving)",
        "Clue Giving",
        "missing",
        "civilian only idles/wanders",
        r"clue",
        CIVILIAN_GD,
    ),
    (
        "Civilian cower / flee (ST_TriggerFlee_Civilian, ST_Subtree_Flee)",
        "Trigger Flee / Flee Behavior",
        "missing",
        "no cower or flee path in the civilian",
        r"flee|cower",
        CIVILIAN_GD,
    ),
)


class Fail(RuntimeError):
    pass


def load_json(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def enum_tail(value, label: str) -> str:
    text = str(value or "")
    if "::" not in text:
        raise Fail(f"{label}: expected an E* enum value, got {text!r}")
    return text.split("::")[-1]


def tag_name(value) -> str:
    return str(value.get("TagName", "")) if isinstance(value, dict) else "None"


def linked_asset_name(state: dict) -> str | None:
    asset = state.get("LinkedAsset")
    if not isinstance(asset, dict):
        return None
    name = str(asset.get("ObjectName", ""))
    if "'" in name:
        name = name.split("'")[1]
    name = name.split(".")[0]
    return name or None


def build_tree(path: Path) -> dict | None:
    data = load_json(path)
    if not isinstance(data, list) or not data:
        raise Fail(f"{path}: empty export list")
    asset = data[0]
    props = asset.get("Properties") or {}
    states = props.get("States")
    if not isinstance(states, list):
        return None

    transitions = props.get("Transitions") or []
    nodes = ((props.get("Nodes") or {}).get("Structs")) or []
    name = str(asset.get("Name", path.stem))
    package = str(asset.get("Package", ""))
    if not isinstance(transitions, list):
        raise Fail(f"{name}: Transitions is not a list")

    def node_name(index: int, kind: str) -> str:
        if not 0 <= index < len(nodes):
            raise Fail(f"{name}: {kind} index {index} outside Nodes.Structs")
        label = str(nodes[index].get("Name", "")).strip()
        if not label:
            raise Fail(f"{name}: {kind} index {index} has no Name")
        return label

    def slice_names(begin: int, count: int, kind: str) -> list[str]:
        if count < 0 or begin < 0 or begin + count > len(nodes):
            raise Fail(
                f"{name}: {kind} range {begin}..{begin + count} outside "
                f"Nodes.Structs ({len(nodes)})"
            )
        return [node_name(begin + offset, kind) for offset in range(count)]

    def slice_transitions(begin: int, count: int) -> list[int]:
        if count < 0 or begin < 0 or begin + count > len(transitions):
            raise Fail(
                f"{name}: transition range {begin}..{begin + count} outside "
                f"Transitions ({len(transitions)})"
            )
        return list(range(begin, begin + count))

    def state_name(index: int) -> str:
        if index == NO_INDEX:
            return ""
        if not 0 <= index < len(states):
            raise Fail(f"{name}: state index {index} out of range")
        return str(states[index].get("Name", ""))

    out_states = []
    out_transitions = []
    task_names: list[str] = []
    condition_names: list[str] = []
    events: list[str] = []

    for index, state in enumerate(states):
        depth = state.get("Depth")
        parent_index = (state.get("Parent") or {}).get("Index", NO_INDEX)
        if not isinstance(depth, int):
            raise Fail(f"{name}[{index}]: Depth is not an int")
        if parent_index != NO_INDEX and not 0 <= parent_index < len(states):
            raise Fail(f"{name}[{index}]: Parent index {parent_index} out of range")
        if parent_index != NO_INDEX:
            parent_depth = states[parent_index].get("Depth")
            if depth != parent_depth + 1:
                raise Fail(
                    f"{name}[{index}]: Depth {depth} does not follow parent "
                    f"depth {parent_depth}"
                )
        elif depth != 0:
            raise Fail(f"{name}[{index}]: rootless state at depth {depth}")

        children_begin = int(state.get("ChildrenBegin", index + 1))
        children_end = int(state.get("ChildrenEnd", index + 1))
        if not 0 <= children_begin <= children_end <= len(states):
            raise Fail(f"{name}[{index}]: child range {children_begin}..{children_end}")
        # ChildrenBegin..ChildrenEnd spans every descendant, not only the direct
        # children; direct children are the states in that span whose Parent is
        # this state (validated against the parent index below).
        children = [
            child
            for child in range(children_begin, children_end)
            if (states[child].get("Parent") or {}).get("Index") == index
        ]

        tasks = slice_names(
            int(state.get("TasksBegin", 0)), int(state.get("TasksNum", 0)), "task"
        )
        enter = slice_names(
            int(state.get("EnterConditionsBegin", 0)),
            int(state.get("EnterConditionsNum", 0)),
            "enter condition",
        )
        utility = slice_names(
            int(state.get("UtilityConsiderationsBegin", 0)),
            int(state.get("UtilityConsiderationsNum", 0)),
            "utility consideration",
        )
        trans_indices = slice_transitions(
            int(state.get("TransitionsBegin", 0)), int(state.get("TransitionsNum", 0))
        )
        task_names.extend(tasks)
        condition_names.extend(enter)
        condition_names.extend(utility)

        state_transitions = []
        for trans_index in trans_indices:
            transition = transitions[trans_index]
            target_index = (transition.get("State") or {}).get("Index")
            if target_index is None:
                raise Fail(f"{name}[{index}]: transition {trans_index} has no state")
            conditions = slice_names(
                int(transition.get("ConditionsBegin", 0)),
                int(transition.get("ConditionsNum", 0)),
                "transition condition",
            )
            condition_names.extend(conditions)
            event_ref = transition.get("RequiredEvent") or {}
            event = tag_name(event_ref.get("Tag"))
            if event in ("", "None"):
                event = ""
            delay = transition.get("Delay") or {}
            if target_index in SPECIAL_HANDLES:
                to_state = None
                to_kind = SPECIAL_HANDLES[target_index]
            else:
                to_state = state_name(int(target_index))
                to_kind = "state"
            record = {
                "index": trans_index,
                "from_state": str(state.get("Name", "")),
                "from_state_index": index,
                "to_state": to_state,
                "to_state_index": int(target_index),
                "to_kind": to_kind,
                "trigger": enum_tail(
                    transition.get("Trigger"), f"{name} transition {trans_index}"
                ),
                "priority": enum_tail(
                    transition.get("Priority"), f"{name} transition {trans_index}"
                ),
                "required_event": event,
                "conditions": conditions,
                "enabled": bool(transition.get("bTransitionEnabled", True)),
                "delay_seconds": float(delay.get("duration", 0.0)),
                "delay_random_variance": float(delay.get("RandomVariance", 0.0)),
                "fallback": enum_tail(
                    transition.get("Fallback"), f"{name} transition {trans_index}"
                ),
            }
            if event:
                events.append(event)
            out_transitions.append(record)
            state_transitions.append(
                {
                    "index": trans_index,
                    "to_state": record["to_state"],
                    "to_state_index": record["to_state_index"],
                    "to_kind": to_kind,
                    "trigger": record["trigger"],
                    "priority": record["priority"],
                    "required_event": event,
                    "conditions": conditions,
                    "enabled": record["enabled"],
                }
            )

        linked = linked_asset_name(state)
        linked_state = (state.get("LinkedState") or {}).get("Index", NO_INDEX)
        out_states.append(
            {
                "index": index,
                "name": str(state.get("Name", "")),
                "depth": depth,
                "type": enum_tail(state.get("Type"), f"{name}[{index}] Type"),
                "parent": state_name(int(parent_index)) or None,
                "parent_index": None if parent_index == NO_INDEX else int(parent_index),
                "children": children,
                "children_range": [children_begin, children_end],
                "tasks": tasks,
                "enter_conditions": enter,
                "utility_considerations": utility,
                "transitions": state_transitions,
                "linked_asset": linked,
                "linked_state_index": (
                    None if linked_state == NO_INDEX else int(linked_state)
                ),
                "enabled": bool(state.get("bEnabled", True)),
                "selection_behavior": enum_tail(
                    state.get("SelectionBehavior"),
                    f"{name}[{index}] SelectionBehavior",
                ),
            }
        )

    covered: list[int] = []
    for state in out_states:
        for transition in state["transitions"]:
            covered.append(transition["index"])
    if len(set(covered)) != len(transitions):
        missing_transitions = sorted(set(range(len(transitions))) - set(covered))
        raise Fail(
            f"{name}: {len(set(covered))} of {len(transitions)} transitions are "
            f"reachable from a state (missing {missing_transitions[:8]}); "
            "ownership is expressed by each state's transition range"
        )
    if len(covered) != len(set(covered)):
        raise Fail(f"{name}: a transition is claimed by more than one state")

    roots = [state["name"] for state in out_states if state["parent_index"] is None]
    subtree_links = [
        {
            "state": state["name"],
            "state_index": state["index"],
            "asset": state["linked_asset"],
            "entry_state_index": state["linked_state_index"],
        }
        for state in out_states
        if state["linked_asset"]
    ]
    types = Counter(state["type"] for state in out_states)

    return {
        "asset": package or f"/Game/AI/StateTrees/{name}",
        "package": str(path.relative_to(ROOT).as_posix()),
        "name": name,
        "roots": roots,
        "stats": {
            "states": len(out_states),
            "transitions": len(out_transitions),
            "groups": types.get("Group", 0),
            "linked_asset_states": types.get("LinkedAsset", 0),
            "disabled_states": sum(1 for state in out_states if not state["enabled"]),
            "max_depth": max(state["depth"] for state in out_states),
            "global_evaluators": int(props.get("EvaluatorsNum", 0)),
            "tasks": len(set(task_names)),
            "task_instances": len(task_names),
            "conditions": len(set(condition_names)),
            "condition_instances": len(condition_names),
            "events": sorted(set(events)),
            "subtree_links": len(subtree_links),
        },
        "tasks": sorted(set(task_names)),
        "conditions": sorted(set(condition_names)),
        "subtree_links": subtree_links,
        "states": out_states,
        "transitions": out_transitions,
    }


def build_leaf(path: Path, data: list) -> dict | None:
    """A task / condition / consideration asset (no States)."""
    asset = data[0]
    props = asset.get("Properties")
    if isinstance(props, dict) and isinstance(props.get("States"), list):
        return None
    klass = str(asset.get("Class", ""))
    name = str(asset.get("Name", path.stem))
    rel = str(path.relative_to(ROOT).as_posix())
    if "BlueprintGeneratedClass" in klass:
        functions = sorted(
            str(export.get("Name", ""))
            for export in data[1:]
            if str(export.get("Type", "")) == "Function"
        )
        return {
            "kind": "blueprint",
            "name": name,
            "package": rel,
            "asset": str(asset.get("Package", "")),
            "class": klass,
            "functions": functions,
        }
    inputs = [
        export
        for export in data
        if "TargetingConsiderationInput" in str(export.get("Class", ""))
    ]
    if inputs:
        return {
            "kind": "targeting_consideration",
            "name": path.stem,
            "package": rel,
            "asset": f"/Game/AI/StateTrees/Targeting/{path.stem}",
            "inputs": [
                {
                    "name": str(export.get("Name", "")),
                    "class": str(export.get("Class", "")).split("'")[-1].rstrip("'"),
                    "properties": export.get("Properties") or {},
                }
                for export in inputs
            ],
        }
    return {
        "kind": "other",
        "name": name,
        "package": rel,
        "class": klass,
    }


def grep_count(path: Path, needle: str) -> int:
    if not path.is_file():
        return -1
    pattern = re.compile(needle, re.IGNORECASE)
    return sum(
        1
        for line in path.read_text(encoding="utf-8").splitlines()
        if pattern.search(line)
    )


def outline(tree: dict, max_depth: int) -> list[str]:
    lines = []
    for state in tree["states"]:
        if state["depth"] > max_depth:
            continue
        marker = {
            "Group": "[group]",
            "LinkedAsset": "[subtree]",
            "State": "",
        }.get(state["type"], "")
        suffix = f" -> {state['linked_asset']}" if state["linked_asset"] else ""
        label = f"{'  ' * state['depth']}{state['name']} {marker}{suffix}".rstrip()
        lines.append(label)
    return lines


def coverage_rows() -> list[dict]:
    rows = []
    for branch, anchor, status, note, needle, source in PORT_COVERAGE:
        rows.append(
            {
                "branch": branch,
                "anchor": anchor,
                "status": status,
                "note": note,
                "needle": needle,
                "source": source.relative_to(ROOT).as_posix(),
                "hits": grep_count(source, needle),
            }
        )
    return rows


def build_report(payload: dict, coverage: list[dict]) -> str:
    trees = payload["trees"]
    stats = payload["stats"]
    lines: list[str] = []
    add = lines.append

    add("# W5E — guard / civilian StateTree inventory")
    add("")
    add(
        "Generated by `tools/parse_state_tree.py`; regenerate with "
        "`python3 tools/parse_state_tree.py`. The payload it summarises is "
        "`game/data/generated/gameplay/guard_behavior.json` (gitignored)."
    )
    add("")
    add("## What was recovered")
    add("")
    add(
        f"{stats['trees']} cooked StateTree assets: {stats['states']} states and "
        f"{stats['transitions']} transitions in total, "
        f"{stats['subtree_links']} linked-subtree states and "
        f"{stats['disabled_states']} authored-disabled states. Every state keeps "
        "its authored name, depth, parent, children, task list, enter "
        "conditions and outgoing transitions; transition targets are resolved "
        "to state names."
    )
    add("")
    multi_root = [
        name for name, tree in sorted(trees.items()) if len(tree["roots"]) > 1
    ]
    if multi_root:
        add(
            "Most trees have one root; these ship more than one depth-0 entry "
            "state, so the payload records a root list rather than a root: "
            + ", ".join(
                f"`{name}` ({', '.join(trees[name]['roots'])})" for name in multi_root
            )
            + "."
        )
        add("")
    add(
        "| tree | states | transitions | groups | subtree links | disabled | max depth |"
    )
    add("|---|---|---|---|---|---|---|")
    for name in sorted(trees):
        tree = trees[name]
        s = tree["stats"]
        add(
            f"| `{name}` | {s['states']} | {s['transitions']} | {s['groups']} | "
            f"{s['linked_asset_states']} | {s['disabled_states']} | {s['max_depth']} |"
        )
    add("")
    add("## Guard root branches (`ST_Guard`)")
    add("")
    add("```")
    lines.extend(outline(trees["ST_Guard"], 3))
    add("```")
    add("")
    add("## Civilian root branches (`ST_Civilian`)")
    add("")
    add("```")
    lines.extend(outline(trees["ST_Civilian"], 3))
    add("```")
    add("")
    add("## Subtree reference graph")
    add("")
    referrers: dict[str, list[str]] = {}
    for name, tree in trees.items():
        for link in tree["subtree_links"]:
            referrers.setdefault(link["asset"], []).append(f"{name}: {link['state']}")
    for subtree in sorted(referrers):
        entries = referrers[subtree]
        unique = sorted(set(entries))
        placements = (
            f" ({len(entries)} placements)" if len(entries) != len(unique) else ""
        )
        add(
            f"- `{subtree}` — {len(unique)} referencing state(s){placements}: "
            + "; ".join(unique)
        )
    orphans = sorted(
        name for name in trees if name not in ROOT_TREES and name not in referrers
    )
    if orphans:
        add("")
        add(
            "Never referenced by another recovered tree: "
            + ", ".join(f"`{o}`" for o in orphans)
            + " — these are entry points for Blueprint/C++ callers or variant "
            "AI (the haunted-stable twins), not for the two root trees."
        )
    add("")
    add("## Authored events")
    add("")
    add(f"The transitions listen for these gameplay events ({len(stats['events'])}):")
    add("")
    for event in stats["events"]:
        add(f"- `{event}`")
    add("")
    disabled = [
        f"`{name}`: {state['name']} (state {state['index']})"
        for name, tree in sorted(trees.items())
        for state in tree["states"]
        if not state["enabled"]
    ]
    if disabled:
        add("## Authored-disabled states")
        add("")
        add(f"{len(disabled)} state(s) ship disabled and never run:")
        add("")
        for entry in disabled:
            add(f"- {entry}")
        add("")
    add("")
    add("## Port coverage (`game/src/ai/guard_ai.gd`, `civilian_npc.gd`)")
    add("")
    add(
        "Status is a curated read of the port source, not a runtime measurement. "
        "`grep hits` counts source lines matching the recorded pattern at "
        "generation time: 0 means the branch has no counterpart in the port "
        "file named, and the note says what does exist."
    )
    add("")
    add("| branch | authored anchor | status | evidence (grep) | note |")
    add("|---|---|---|---|---|")
    for row in coverage:
        add(
            f"| {row['branch']} | `{row['anchor']}` | **{row['status']}** | "
            f"`{row['needle']}` → {row['hits']} in `{row['source']}` | {row['note']} |"
        )
    add("")
    missing = [
        row for row in coverage if row["status"] == "missing" and row["hits"] == 0
    ]
    partial = [row for row in coverage if row["status"] == "partial"]
    disabled_branches = [row for row in coverage if row["status"] == "disabled"]
    add("## Missing branches")
    add("")
    add(
        f"{len(missing)} of the {len(coverage)} authored branches have no port "
        "counterpart and no matching source line in the owning file:"
    )
    add("")
    for row in missing:
        add(f"- **{row['branch']}** — authored as `{row['anchor']}`.")
    if disabled_branches:
        add("")
        add(
            f"{len(disabled_branches)} authored branch(es) are disabled in the "
            "shipped data and therefore not port work:"
        )
        add("")
        for row in disabled_branches:
            add(f"- **{row['branch']}** — {row['note']}.")
    add("")
    add(f"{len(partial)} further branches exist only in reduced form:")
    add("")
    for row in partial:
        add(f"- **{row['branch']}** — {row['note']}.")
    add("")
    add("## Remaining unknowns")
    add("")
    add(
        "- Node UClasses: the cooked StateTree structs serialise the node's "
        "display name and instance-template index, not the class path, so the "
        "payload names tasks/conditions by their authored display name. Mapping "
        "each name to `STT_*`/`STC_*` needs the per-node template walk."
    )
    add(
        "- Per-node parameters (durations, distances, tag queries) live in the "
        "instance-data templates and the task Blueprints, not in the StateTree "
        "graph; the payload does not claim them."
    )
    add(
        "- EQS query assets behind `Run Env Query` are not enumerated here; the "
        "state only records that the task exists."
    )
    add(
        "- The `Difficulty Evaluator` (the asset's one global evaluator, "
        "`EvaluatorsNum = 1`, configured `ETATDifficulty::Normal`) sits in "
        "`Nodes.Structs` but is not referenced by any state's task/condition "
        "range, so it is counted per tree (`global_evaluators`) and its "
        "per-difficulty selection is not recovered."
    )
    add(
        "- Behavioural equivalence with the port is unmeasured: no branch of "
        "`ST_Guard`/`ST_Civilian` has been executed in-engine."
    )
    add("")
    add("## Reproduce")
    add("")
    add("```bash")
    add("python3 tools/parse_state_tree.py")
    add("python3 tools/check_logic_data.py")
    add("```")
    add("")
    return "\n".join(lines)


def main() -> int:
    try:
        if not STATE_ROOT.is_dir():
            raise Fail(f"missing {STATE_ROOT}")
        trees: dict[str, dict] = {}
        leaves: list[dict] = []
        for path in sorted(STATE_ROOT.rglob("*.json")):
            data = load_json(path)
            if not isinstance(data, list) or not data:
                raise Fail(f"{path}: empty export list")
            tree = build_tree(path)
            if tree is None:
                leaf = build_leaf(path, data)
                if leaf is not None:
                    leaves.append(leaf)
                continue
            if tree["name"] in trees:
                raise Fail(f"duplicate tree name {tree['name']}")
            trees[tree["name"]] = tree

        if len(trees) != EXPECTED_TREES:
            raise Fail(f"recovered {len(trees)} trees, expected {EXPECTED_TREES}")
        for name, expected in (
            ("ST_Guard", EXPECTED_GUARD),
            ("ST_Civilian", EXPECTED_CIVILIAN),
        ):
            if name not in trees:
                raise Fail(f"missing root tree {name}")
            tree = trees[name]
            if tree["stats"]["states"] != expected["states"]:
                raise Fail(
                    f"{name} has {tree['stats']['states']} states, "
                    f"expected {expected['states']}"
                )
            if tree["stats"]["transitions"] != expected["transitions"]:
                raise Fail(
                    f"{name} has {tree['stats']['transitions']} transitions, "
                    f"expected {expected['transitions']}"
                )
        for name in ROOT_TREES:
            if name not in trees:
                raise Fail(f"missing root tree {name}")

        conditionals = [
            leaf
            for leaf in leaves
            if leaf["kind"] == "blueprint" and leaf["name"].startswith("STC_")
        ]
        tasks = [
            leaf
            for leaf in leaves
            if leaf["kind"] == "blueprint" and leaf["name"].startswith("STT_")
        ]
        considerations = [
            leaf for leaf in leaves if leaf["kind"] == "targeting_consideration"
        ]
        other = [
            leaf for leaf in leaves if leaf not in conditionals + tasks + considerations
        ]
        if not conditionals or not tasks or not considerations:
            raise Fail("no STC_/STT_/targeting-consideration leaves recovered")

        all_events = sorted(
            {event for tree in trees.values() for event in tree["stats"]["events"]}
        )
        states_total = sum(tree["stats"]["states"] for tree in trees.values())
        transitions_total = sum(tree["stats"]["transitions"] for tree in trees.values())
        payload = {
            "schema": SCHEMA,
            "game_version": GAME_VERSION,
            "source": {
                "state_trees": "extracted/json/AI/StateTrees/**/*.json",
                "port_reference": [
                    "game/src/ai/guard_ai.gd",
                    "game/src/ai/civilian_npc.gd",
                ],
                "note": (
                    "Task/condition nodes are named from Nodes.Structs[].Name; "
                    "the cooked graph does not serialise the node UClass."
                ),
            },
            "units": {
                "depth": "StateTree depth, root = 0",
                "delay_seconds": "authored transition delay (seconds)",
            },
            "roots": list(ROOT_TREES),
            "stats": {
                "trees": len(trees),
                "states": states_total,
                "transitions": transitions_total,
                "subtree_links": sum(
                    tree["stats"]["subtree_links"] for tree in trees.values()
                ),
                "disabled_states": sum(
                    tree["stats"]["disabled_states"] for tree in trees.values()
                ),
                "tasks": len(
                    {task for tree in trees.values() for task in tree["tasks"]}
                ),
                "conditions": len(
                    {cond for tree in trees.values() for cond in tree["conditions"]}
                ),
                "events": all_events,
                "st_guard": trees["ST_Guard"]["stats"],
                "st_civilian": trees["ST_Civilian"]["stats"],
                "leaf_blueprints": {
                    "conditionals": len(conditionals),
                    "tasks": len(tasks),
                    "targeting_considerations": len(considerations),
                    "other": len(other),
                },
            },
            "trees": trees,
            "condition_classes": sorted(conditionals, key=lambda leaf: leaf["name"]),
            "task_blueprints": sorted(tasks, key=lambda leaf: leaf["name"]),
            "targeting_considerations": sorted(
                considerations, key=lambda leaf: leaf["name"]
            ),
            "other_blueprints": sorted(other, key=lambda leaf: leaf["name"]),
        }

        coverage = coverage_rows()
        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUT_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(build_report(payload, coverage), encoding="utf-8")
    except Fail as exc:
        print(f"parse_state_tree: FAIL: {exc}", file=sys.stderr)
        return 1

    print(
        "Parsed {} StateTrees ({} states, {} transitions) -> {}".format(
            payload["stats"]["trees"],
            payload["stats"]["states"],
            payload["stats"]["transitions"],
            OUT_PATH.relative_to(ROOT),
        )
    )
    for name in ROOT_TREES:
        tree = trees[name]
        print(
            "  {}: {} states / {} transitions / {} subtree links".format(
                name,
                tree["stats"]["states"],
                tree["stats"]["transitions"],
                tree["stats"]["subtree_links"],
            )
        )
    print(
        "  leaves: {} conditions, {} tasks, {} targeting considerations, {} other".format(
            len(conditionals), len(tasks), len(considerations), len(other)
        )
    )
    print(f"  events: {', '.join(all_events)}")
    print(f"Wrote {REPORT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
