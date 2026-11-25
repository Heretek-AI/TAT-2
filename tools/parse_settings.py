#!/usr/bin/env python3
"""
Parse the authored loot-inventory / payout settings into
game/data/generated/gameplay/loot_settings.json (W7S-S2).

Every value traces to a source JSON path recorded in "sources"; nothing is
invented. The runtime (src/interact/loot_inventory.gd) keeps the same numbers
as code constants and only overrides them when this file is readable, so a
missing generated table degrades to the documented authored defaults.

Authored inputs
  Core/BP_TATPlayerState.json
      TATLootInventoryComponent.InventorySlotMaxCapacity = 12
  Gameplay/Loot/Data/DT_LootInfo_{Minor,Major,Quest}.json
      UseSlotSizeOverride / SlotSizeOverride / IsLargeCarry / Value per row
  Gameplay/Tuning/DT_PlayerExperience.json
      XP category tags (amounts are not authored in the dump; none invented)
  Gameplay/Tuning/CT_XPToLevel.json
      XPToLevel curve keys (per-level thresholds)
  Gameplay/Quests/DT_Missions_*.json (generated tables copy)
      Rewards[] money quantities (1000 on the shipped maps)
  StringTables/ST_Interactables.json
      authored prompt/error text ("INVENTORY FULL", stash prompts)
  Gameplay/Loot/Actors/BP_LootBagActor.json
      _minInteractDuration = 1.0 (the loot bag's one-second pickup beat)
  Gameplay/Loot/Actors/Stash/BP_LootStashInteractable.json
      Ability.Stash.Use / instant take animation tag

Port decisions (recorded in "port_decisions", not presented as authored):
  major loot occupies 3 of the 12 inventory slots (minor/quest 1),
  the cap is enforced at pickup with the authored INVENTORY FULL line,
  each secret stash is a one-use deposit-all,
  kept-on-escape 1.0 / kept-on-capture 0.0 (stashed loot is always kept),
  a completed contract pays the mission reward once on a successful getaway.

Fails closed: any missing or unreadable source aborts with a non-zero exit.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "loot_settings.json"
MISSION_TABLES = ROOT / "game" / "data" / "generated" / "tables" / "Gameplay" / "Quests"

PLAYER_STATE = "Core/BP_TATPlayerState.json"
LOOT_TABLES = {
    "minor": "Gameplay/Loot/Data/DT_LootInfo_Minor.json",
    "major": "Gameplay/Loot/Data/DT_LootInfo_Major.json",
    "quest": "Gameplay/Loot/Data/DT_LootInfo_Quest.json",
}
XP_CATEGORIES = "Gameplay/Tuning/DT_PlayerExperience.json"
XP_CURVE = "Gameplay/Tuning/CT_XPToLevel.json"
STRINGS = "StringTables/ST_Interactables.json"
LOOT_BAG = "Gameplay/Loot/Actors/BP_LootBagActor.json"
STASH_ACTOR = "Gameplay/Loot/Actors/Stash/BP_LootStashInteractable.json"
MISSION_REWARD_TABLES = {
    "guildhall": "DT_Missions_Guildhall.json",
    "old_manor": "DT_Missions_OldManor.json",
    "thieves_den": "DT_Missions_ThievesDen_Tutorial.json",
    "ftue": "DT_Missions_Tutorial.json",
}
PROMPT_KEYS = [
    "ErrorInventoryFull",
    "PromptStashDepositLoot",
    "PromptStashNoLoot",
    "PromptStashUsesRemaining",
    "PromptStashUse",
    "PromptTakeLootBagContents",
    "PromptStashStealLoot",
]


class Fail(Exception):
    pass


def load(rel: str):
    p = EX / rel
    if not p.is_file():
        raise Fail(f"missing source file: {rel}")
    try:
        return json.loads(p.read_text())
    except Exception as e:  # noqa: BLE001 - fail closed with the path
        raise Fail(f"unparseable source file {rel}: {e}")


def need(props: dict, key: str, where: str):
    if key not in props:
        raise Fail(f"missing property {key!r} in {where}")
    return props[key]


def find_export(data, type_name: str, name: str = "") -> dict:
    for entry in data:
        if not isinstance(entry, dict):
            continue
        if entry.get("Type") != type_name:
            continue
        if name and entry.get("Name") != name:
            continue
        return entry.get("Properties") or {}
    raise Fail(f"export not found: {type_name} {name}")


def _table_export(data, name: str) -> dict:
    """DataTable/CurveTable JSON keeps its rows at the export root.

    Unlike Blueprint exports these files have no Properties wrapper:
    {"Type": "DataTable", "Name": ..., "Rows": {...}}.
    """
    for entry in data if isinstance(data, list) else []:
        if isinstance(entry, dict) and entry.get("Name") == name:
            return entry
    raise Fail(f"table not found: {name}")


def tier_settings(rel: str) -> dict:
    data = load(rel)
    if not data or not isinstance(data, list):
        raise Fail(f"{rel}: no exports")
    props = data[0]
    rows = props.get("Rows")
    if not isinstance(rows, dict) or not rows:
        raise Fail(f"{rel}: no Rows")
    slot_sizes = sorted(
        {
            int(row.get("SlotSizeOverride", 1))
            for row in rows.values()
            if isinstance(row, dict)
        }
    )
    overrides = sorted(
        {
            bool(row.get("UseSlotSizeOverride", False))
            for row in rows.values()
            if isinstance(row, dict)
        }
    )
    large = sorted(
        key
        for key, row in rows.items()
        if isinstance(row, dict) and bool(row.get("IsLargeCarry", False))
    )
    values = [
        int(row.get("Value", 0))
        for row in rows.values()
        if isinstance(row, dict) and "Value" in row
    ]
    return {
        "rows": len(rows),
        "slot_size_values": slot_sizes,
        "use_slot_size_override": overrides,
        "is_large_carry_rows": large,
        "value_min": min(values) if values else 0,
        "value_max": max(values) if values else 0,
    }


def mission_rewards() -> tuple[dict, dict]:
    rewards = {}
    sources = {}
    for map_id, name in MISSION_REWARD_TABLES.items():
        path = MISSION_TABLES / name
        if not path.is_file():
            raise Fail(f"missing mission table: {path.relative_to(ROOT)}")
        data = json.loads(path.read_text())
        rows = data.get("rows")
        if not isinstance(rows, dict) or not rows:
            raise Fail(f"{path.relative_to(ROOT)}: no rows")
        quantity = 0
        row_name = ""
        rows_with_rewards = []
        for row_key, row in rows.items():
            if not isinstance(row, dict):
                continue
            entries = row.get("Rewards") or []
            money = 0
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                rtype = str((entry.get("RewardType") or {}).get("ObjectName", ""))
                if "RewardType_Money" in rtype:
                    money += int(entry.get("Quantity", 0))
            if money > 0:
                rows_with_rewards.append(row_key)
                if quantity == 0:
                    quantity = money
                    row_name = row_key
        rewards[map_id] = quantity
        sources[map_id] = {
            "table": str(path.relative_to(ROOT)),
            "rows_with_rewards": sorted(rows_with_rewards),
            "money_rows": row_name,
        }
    return rewards, sources


def main() -> int:
    try:
        player = load(PLAYER_STATE)
        inv = find_export(
            player, "TATLootInventoryComponent", "TATLootInventoryComponent"
        )
        slots = int(need(inv, "InventorySlotMaxCapacity", "TATLootInventoryComponent"))
        if slots <= 0:
            raise Fail(f"invalid InventorySlotMaxCapacity {slots}")

        loot_tables = {tier: tier_settings(rel) for tier, rel in LOOT_TABLES.items()}

        xp_rows = load(XP_CATEGORIES)
        xp_table = _table_export(xp_rows, "DT_PlayerExperience")
        categories = sorted((xp_table.get("Rows") or {}).keys())
        if not categories:
            raise Fail("DT_PlayerExperience: no XP category rows")

        curve = load(XP_CURVE)
        curve_table = _table_export(curve, "CT_XPToLevel")
        curve_row = (curve_table.get("Rows") or {}).get("XPToLevel")
        if not isinstance(curve_row, dict):
            raise Fail("CT_XPToLevel: XPToLevel row missing")
        curve_keys = [
            {"level": float(k.get("Time", 0.0)), "xp": float(k.get("Value", 0.0))}
            for k in (curve_row.get("Keys") or [])
            if isinstance(k, dict)
        ]
        if not curve_keys:
            raise Fail("CT_XPToLevel: XPToLevel has no keys")

        strings = load(STRINGS)
        if not strings or not isinstance(strings[0].get("StringTable"), dict):
            raise Fail("ST_Interactables: StringTable missing")
        entries = (strings[0]["StringTable"]).get("KeysToEntries")
        if not isinstance(entries, dict):
            raise Fail("ST_Interactables: KeysToEntries missing")
        prompts = {}
        for key in PROMPT_KEYS:
            if key not in entries:
                raise Fail(f"ST_Interactables: missing {key}")
            prompts[key] = str(entries[key])

        bag = load(LOOT_BAG)
        bag_props = find_export(bag, "BP_LootBagActor_C", "Default__BP_LootBagActor_C")
        linger = float(need(bag_props, "_minInteractDuration", "BP_LootBagActor_C"))
        if linger <= 0.0:
            raise Fail(f"invalid loot-bag pickup beat {linger}")

        stash = load(STASH_ACTOR)
        stash_props = find_export(
            stash, "BP_LootStashInteractable_C", "Default__BP_LootStashInteractable_C"
        )
        stash_interact = str(
            (
                need(
                    stash_props, "_interactGameplayEvent", "BP_LootStashInteractable_C"
                )
                or {}
            ).get("TagName", "")
        )
        stash_anim = str(
            (
                need(
                    stash_props,
                    "_interactInstantAnimation",
                    "BP_LootStashInteractable_C",
                )
                or {}
            ).get("TagName", "")
        )
        if not stash_interact or not stash_anim:
            raise Fail("BP_LootStashInteractable_C: stash interact tags missing")

        rewards, reward_sources = mission_rewards()
        reward_fallback = 0
        for map_id in ("guildhall", "old_manor", "ftue"):
            if rewards.get(map_id, 0) > 0:
                reward_fallback = int(rewards[map_id])
                break
        if reward_fallback <= 0:
            raise Fail("no authored money reward found in the mission tables")

        payload = {
            "version": 1,
            "slots": slots,
            "cap_enforced": True,
            "slot_cost_authored": {
                tier: (values[0] if len(values) == 1 else 1)
                for tier, values in (
                    (t, info["slot_size_values"]) for t, info in loot_tables.items()
                )
            },
            "slot_cost_port": {"minor": 1, "major": 3, "quest": 1},
            "is_large_carry": {
                tier: info["is_large_carry_rows"] for tier, info in loot_tables.items()
            },
            "authored_slot_tables": loot_tables,
            "actor_linger_s": linger,
            "kept_on_escape": 1.0,
            "kept_on_capture": 0.0,
            "contract_rewards": rewards,
            "contract_reward_fallback": reward_fallback,
            "stash": {
                "kind": "stash",
                "uses_per_stash": 1,
                "one_use": True,
                "interact_gameplay_event": stash_interact,
                "interact_animation": stash_anim,
                "depositable_tiers": ["minor", "major"],
                "quest_items_depositable": False,
            },
            "prompts": prompts,
            "xp": {
                "curve_table": "CT_XPToLevel",
                "curve_row": "XPToLevel",
                "curve_keys": curve_keys,
                "categories": categories,
                "amounts_note": (
                    "DT_PlayerExperience authors category tags only; the capture "
                    "carries no per-category XP amounts, so none are invented."
                ),
            },
            "port_decisions": {
                "major_slot_cost": 3,
                "capacity_refusal_line": prompts["ErrorInventoryFull"],
                "actor_linger_s": (
                    "The 1.0 s pickup beat reuses the authored loot-bag "
                    "_minInteractDuration; the port keeps the picked-up actor "
                    "visible for that beat instead of freeing it in the same frame."
                ),
                "secret_stash_one_use": (
                    "Each secret stash deposit is a one-use deposit-all; "
                    "the count is a port policy (no count is authored)."
                ),
                "kept_on_escape_capture": (
                    "Binary keep: a successful getaway keeps the carried haul, "
                    "a capture keeps only the already-stashed value."
                ),
            },
            "sources": {
                "slots": (
                    "extracted/json/Core/BP_TATPlayerState.json "
                    "(TATLootInventoryComponent.InventorySlotMaxCapacity)"
                ),
                "loot_tables": {
                    tier: f"extracted/json/{rel}" for tier, rel in LOOT_TABLES.items()
                },
                "xp_categories": f"extracted/json/{XP_CATEGORIES}",
                "xp_curve": f"extracted/json/{XP_CURVE}",
                "prompts": f"extracted/json/{STRINGS}",
                "actor_linger_s": (
                    f"extracted/json/{LOOT_BAG} (_minInteractDuration; port beat)"
                ),
                "stash_tags": f"extracted/json/{STASH_ACTOR}",
                "contract_rewards": reward_sources,
            },
        }
    except Fail as e:
        print(f"parse_settings: FAIL-CLOSED: {e}", file=sys.stderr)
        return 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(
        f"wrote game/data/generated/gameplay/loot_settings.json "
        f"(slots={slots}, linger={linger}s, reward={reward_fallback}, "
        f"{len(categories)} XP categories)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
