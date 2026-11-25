#!/usr/bin/env python3
"""Emit the authored Black Market unlock table for TAT-2.

Reads the shipped cooked DataAsset dump

    extracted/json/UI/Progression/DA_UnlockableContentEntries.json

(``TATUnlockableContentDataAsset.EntryTable``, 68 entries) and the string
tables it points at (``ST_BlackMarket`` for 66 entries, ``ST_Tools`` for the
Glamour and Vistara Diamond descriptions), then writes

    game/data/generated/gameplay/unlocks.json

What this producer does and does not claim:

* Every field is copied from the cooked asset. Prices are emitted exactly as
  authored, including the 54 rows whose authored ``Price`` is 0. No price is
  invented, rounded or derived from the port's UI copy.
* The four KF08 frame-visible prices (Bob hair GBP 7,500 / Mustache 5,000 /
  Full Beard 7,500 / Eyepatch 2,500) are the only prices the port can verify
  against the shipped build, so they are asserted here as an anchor: if the
  asset ever changes, this producer fails instead of silently drifting.
* ``shop_category`` is the one derived field. The asset carries
  ``ContentType`` and the entry ``Tag``; the Black Market's four authored
  column labels (``Category.Tools`` / ``Category.GuildPerks`` /
  ``Category.Customizations`` / ``Category.Difficulty``) and the KF08 frame
  columns (TOOLS, GUILD PERKS, SPIDER COSMETICS, CHAMELEON COSMETICS) show how
  rows are grouped. The mapping below is a display grouping, flagged
  ``derived`` in the payload so nothing downstream mistakes it for authored
  data.
* Unlock conditions keep the raw ``ETATUnlockType`` (``RequiredLevel`` 48 /
  ``RequiredContract`` 10 conditions) plus the level and contract tag; a
  ``None`` contract tag means "no contract gate".

* ``save_id`` is the stable id SaveSystem stores. Tools and guild perks reuse
  the ids the port already persists (``zipwire`` ... ``vistara_diamond``);
  cosmetics use the authored outfit tag verbatim (``Outfit.Spider.Head.BowlerA``),
  which is also what the wardrobe already saves for an equipped head/body/card.
  Every id is asserted unique, and the tool/perk sets are pinned to the
  SaveSystem ids so a renamed tag fails the producer instead of silently
  orphaning a player's purchase.

* ``condition.text`` is derived from the structured unlock requirement (the
  field the shipped game gates on) in the shipped tooltip voice:
  "Unlocked at Level N." / "Unlocked in Contract N." The authored description
  copy carries its own "Unlocked ..." sentence; where the two disagree the
  producer records both (``condition.copy`` + ``condition.copy_agrees``) rather
  than picking a winner, because the data asset itself is inconsistent
  (Master Thief gates on Contract.Main.5 while its copy says Contract 8).

``game/src/ui/unlock_catalog.gd`` reads this file for the Ledger Black Market
and the Wardrobe; no UI row is hard-coded any more. ``blackjack`` is a built-in
tool, not one of the 68 rows, and is emitted separately under
``catalog.built_ins``.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_ROOT = ROOT / "extracted" / "json"
ENTRY_JSON = JSON_ROOT / "UI" / "Progression" / "DA_UnlockableContentEntries.json"
STRING_TABLE_DIR = JSON_ROOT / "StringTables"
OUT_PATH = ROOT / "game" / "data" / "generated" / "gameplay" / "unlocks.json"
## Imported texture root (game/assets/ue/Raw mirrors /Game/). Only consulted
## when it exists: a fresh clone runs `make normalize` before the Godot import,
## so a missing tree is "not measured", never "missing icon".
RAW_UE_ROOT = ROOT / "game" / "assets" / "ue" / "Raw"
SCHEMA = "tat2.unlocks/1"
CATALOG_SCHEMA = "tat2.unlock_catalog/1"
GAME_VERSION = "Steam 1.5.193.148559"

EXPECTED_ENTRIES = 68
EXPECTED_PRICED = 55
## KF08 shows exactly four authored Black Market columns. The counts are
## asserted because a new/renamed content type must land in a deliberate column.
EXPECTED_COLUMNS = {
    "tools": 7,
    "guild_perks": 7,
    "spider_cosmetics": 28,
    "chameleon_cosmetics": 26,
}

## SaveSystem ids these rows must resolve to. Tools/perks keep the ids the port
## already persists; a rename here without a SaveSystem migration silently
## orphans a purchase, so the sets are pinned.
TOOL_SAVE_IDS = {
    "Tool.Type.Zipwire": "zipwire",
    "Tool.Type.SmokeBomb": "smoke_bomb",
    "Tool.Type.Pickpocket": "pickpocket_fairy",
    "Tool.Type.CuckooClock": "insult_fairy",
    "Tool.Type.MagicSlime": "slither_sap",
    "Tool.Type.Glamour": "glamour",
    "Tool.Type.VistaraDiamond": "vistara_diamond",
}
PERK_SAVE_IDS = {
    "Difficulty.Novice": "novice_difficulty",
    "Difficulty.Thief": "thief_difficulty",
    "Difficulty.MasterThief": "master_thief_difficulty",
    "Map.Guildhall": "guildhall",
    "Map.OldManor": "old_manor",
    "Thief.Spider": "spider",
    "Thief.Chameleon": "chameleon",
}
## blackjack is the starting reticle tool: shipped from the start, never a
## Black Market row, so it is emitted as a built-in for the Wardrobe candidates.
BUILT_IN_TOOLS = [
    {
        "save_id": "blackjack",
        "title": "Blackjack",
        "reason": "Built-in starting tool; not one of the 68 Black Market rows.",
    }
]

## Contract gates are only real when the tag names a main contract. The
## level-gated cosmetic rows carry the parent tag "Contract", which the shipped
## copy treats as "no contract gate" ("Unlocked at Level 2."), so it is not a
## requirement.
CONTRACT_TAG_RE = re.compile(r"^Contract\.Main\.(\d+)$")
CONDITION_COPY_RE = re.compile(r"Unlocked (?:in Contract|at level|at Level) (\d+)\.")
LEVEL_ANY_RE = re.compile(r"level (\d+)", re.IGNORECASE)

# The only prices verified from a shipped frame (KF08, 00:28.50 of the capture
# clip). Tag -> authored price in the data asset. Both thieves' cosmetics were
# also visible; only the Spider rows are uniquely identifiable at that frame
# resolution, so those are the anchor.
KF08_PRICES = {
    "Outfit.Spider.Head.Hair.Bob": 7500,
    "Outfit.Spider.Head.MustacheA": 5000,
    "Outfit.Spider.Head.BeardA": 7500,
    "Outfit.Spider.Head.EyepatchA": 2500,
}
KF08_LABELS = {
    "Outfit.Spider.Head.Hair.Bob": "Bob Hair Style",
    "Outfit.Spider.Head.MustacheA": "Mustache",
    "Outfit.Spider.Head.BeardA": "Full Beard",
    "Outfit.Spider.Head.EyepatchA": "Eyepatch",
}

CONTENT_TYPES = {"Difficulty", "Gear", "Map", "Thief", "Cosmetic"}
UNLOCK_TYPES = {"RequiredLevel", "RequiredContract"}

SHOP_CATEGORIES = {
    "Difficulty": "guild_perks",
    "Map": "guild_perks",
    "Thief": "guild_perks",
    "Gear": "tools",
}
SHOP_CATEGORY_DERIVATION = (
    "ContentType Difficulty|Map|Thief -> guild_perks, Gear -> tools; Cosmetic "
    "splits on the authored Tag prefix (Outfit.Spider -> spider_cosmetics, "
    "Outfit.Chameleon -> chameleon_cosmetics). Derived from the authored "
    "ContentType/Tag plus the authored Category.* shop labels; not a field in "
    "the data asset."
)


class Fail(RuntimeError):
    pass


def load_json(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def one_asset(path: Path, name: str) -> dict:
    data = load_json(path)
    if not isinstance(data, list):
        raise Fail(f"{path.name}: expected a list of exports")
    for item in data:
        if item.get("Name") == name:
            return item
    raise Fail(f"{path.name}: no export named {name!r}")


def tag_name(value) -> str:
    if isinstance(value, dict):
        return str(value.get("TagName", ""))
    return str(value or "")


def enum_tail(value, label: str) -> str:
    text = str(value or "")
    if "::" not in text:
        raise Fail(f"{label}: expected an E* enum value, got {text!r}")
    return text.split("::")[-1]


def shop_category(content_type: str, tag: str) -> str:
    if content_type == "Cosmetic":
        if tag.startswith("Outfit.Spider"):
            return "spider_cosmetics"
        if tag.startswith("Outfit.Chameleon"):
            return "chameleon_cosmetics"
        raise Fail(f"cosmetic entry {tag!r} is neither Spider nor Chameleon")
    try:
        return SHOP_CATEGORIES[content_type]
    except KeyError:
        raise Fail(f"unknown content type {content_type!r}") from None


def save_category(content_type: str) -> str:
    if content_type == "Cosmetic":
        return "cosmetics"
    if content_type == "Gear":
        return "tools"
    return "perks"


def save_id_for(tag: str, content_type: str) -> str:
    if content_type == "Gear":
        try:
            return TOOL_SAVE_IDS[tag]
        except KeyError:
            raise Fail(f"unmapped tool {tag!r}; pin its SaveSystem id") from None
    if content_type == "Cosmetic":
        return tag
    try:
        return PERK_SAVE_IDS[tag]
    except KeyError:
        raise Fail(f"unmapped guild perk {tag!r}; pin its SaveSystem id") from None


def icon_res(asset_path: str) -> str:
    """Map a cooked texture object path to its imported res:// PNG.

    The asset name repeats the package name
    (``/Game/Art/UI/Icons/.../T_X.T_X``); the port drops everything after the
    last dot and appends ``.png`` (``game/assets/ue/Raw`` mirrors ``/Game/``).
    """
    text = str(asset_path or "")
    if not text.startswith("/Game/"):
        return ""
    base = text.rsplit(".", 1)[0]
    return "res://assets/ue/Raw/" + base[len("/Game/") :] + ".png"


def condition_of(row_desc: str, conditions: list[dict], tag: str) -> dict:
    levels = sorted({int(c["level"]) for c in conditions if int(c["level"]) > 0})
    contracts: list[int] = []
    for cond in conditions:
        raw = str(cond.get("contract_tag_raw") or "")
        match = CONTRACT_TAG_RE.match(raw)
        if match:
            order = int(match.group(1))
            if order not in contracts:
                contracts.append(order)
        elif raw not in ("", "None", "Contract"):
            raise Fail(f"{tag}: unrecognised contract tag {raw!r}")
    contracts.sort()
    if len(levels) > 1 or len(contracts) > 1:
        raise Fail(
            f"{tag}: multiple level/contract conditions are not modelled "
            f"({levels}, {contracts})"
        )
    requires_level = levels[0] if levels else None
    requires_contract = contracts[0] if contracts else None
    parts: list[str] = []
    if requires_level is not None:
        parts.append(f"at Level {requires_level}")
    if requires_contract is not None:
        parts.append(f"in Contract {requires_contract}")
    text = ""
    if len(parts) == 1:
        text = "Unlocked " + parts[0] + "."
    elif len(parts) == 2:
        text = "Unlocked " + " and ".join(parts) + "."

    # Authored copy: the description usually closes with its own claim.
    copy_match = CONDITION_COPY_RE.search(row_desc)
    copy_text = copy_match.group(0) if copy_match else None
    copy_number = int(copy_match.group(1)) if copy_match else None
    copy_is_contract = bool(copy_text) and "in Contract" in str(copy_text)
    if copy_text is None:
        any_level = LEVEL_ANY_RE.search(row_desc)
        copy_number = int(any_level.group(1)) if any_level else None
        copy_is_contract = False
    agrees = True
    if copy_match is not None:
        if copy_is_contract:
            agrees = requires_contract is not None and copy_number == requires_contract
        else:
            agrees = requires_level is not None and copy_number == requires_level
    return {
        "text": text,
        "requires_level": requires_level,
        "requires_contract": requires_contract,
        "copy": copy_text,
        "copy_number": copy_number,
        "copy_agrees": agrees,
    }


def load_string_tables(entries: list[dict]) -> dict[str, dict[str, str]]:
    """Load every string table an entry points at, keyed by table id."""
    tables: dict[str, dict[str, str]] = {}
    for entry in entries:
        for field in ("DisplayName", "Description"):
            ref = entry[field]
            table_id = str(ref.get("TableId", ""))
            if not table_id:
                raise Fail(f"{tag_name(entry['Tag'])}: {field} has no TableId")
            if table_id in tables:
                continue
            stem = table_id.split(".")[-1]
            path = STRING_TABLE_DIR / f"{stem}.json"
            if not path.is_file():
                raise Fail(f"missing string table {stem!r} for {field}")
            export = one_asset(path, stem)
            keys = export.get("StringTable", {}).get("KeysToEntries")
            if not isinstance(keys, dict):
                raise Fail(f"{path.name}: no StringTable.KeysToEntries")
            tables[table_id] = {str(k): str(v) for k, v in keys.items()}
    return tables


def resolve_string(ref: dict, tables: dict[str, dict[str, str]], label: str) -> dict:
    table_id = str(ref.get("TableId", ""))
    key = str(ref.get("Key", ""))
    table = tables.get(table_id, {})
    if key not in table:
        raise Fail(f"{label}: key {key!r} missing from {table_id}")
    value = table[key]
    source = str(ref.get("SourceString", ""))
    if source and source != value:
        raise Fail(f"{label}: {key!r} source string disagrees with {table_id}")
    return {
        "text": value,
        "key": key,
        "table": table_id,
        "table_name": table_id.split(".")[-1],
    }


def build_entry(entry: dict, tables, known_tags: set[str]) -> dict:
    tag = tag_name(entry.get("Tag"))
    if not tag:
        raise Fail("entry without a Tag")
    if tag in known_tags:
        raise Fail(f"duplicate unlock tag {tag!r}")

    content_type = enum_tail(entry.get("ContentType"), f"{tag} ContentType")
    if content_type not in CONTENT_TYPES:
        raise Fail(f"{tag}: unknown content type {content_type!r}")

    price = entry.get("Price")
    if not isinstance(price, int) or isinstance(price, bool) or price < 0:
        raise Fail(f"{tag}: authored Price is not a non-negative int ({price!r})")

    requirement = entry.get("unlockRequirement") or {}
    conditions = []
    for raw in requirement.get("UnlockConditions") or []:
        unlock_type = enum_tail(raw.get("UnlockType"), f"{tag} UnlockType")
        if unlock_type not in UNLOCK_TYPES:
            raise Fail(f"{tag}: unknown unlock type {unlock_type!r}")
        level = raw.get("RequiredLevel")
        if not isinstance(level, int) or isinstance(level, bool) or level < 0:
            raise Fail(f"{tag}: RequiredLevel is not a non-negative int")
        contract = tag_name(raw.get("RequiredContractTag"))
        conditions.append(
            {
                "type": unlock_type,
                "level": level,
                "contract": None if contract in ("", "None") else contract,
                "contract_tag_raw": contract,
            }
        )

    texture = entry.get("Texture") or {}
    title = resolve_string(entry["DisplayName"], tables, f"{tag} title")
    description = resolve_string(entry["Description"], tables, f"{tag} description")
    icon_asset = str(texture.get("AssetPathName", ""))
    return {
        "tag": tag,
        "save_id": save_id_for(tag, content_type),
        "save_category": save_category(content_type),
        "content_type": content_type,
        "price": price,
        "display": {
            "title": title,
            "description": description,
        },
        "icon": {
            "asset": icon_asset,
            "sub_path": str(texture.get("SubPathString", "")),
            "res": icon_res(icon_asset),
        },
        "condition": condition_of(str(description["text"]), conditions, tag),
        "unlock": {
            "must_meet_all_conditions": bool(
                requirement.get("MustMeetAllConditions", False)
            ),
            "hidden_if_locked": bool(requirement.get("HiddenIfLocked", False)),
            "conditions": conditions,
        },
        "shop_category": shop_category(content_type, tag),
    }


def main() -> int:
    try:
        asset = one_asset(ENTRY_JSON, "DA_UnlockableContentEntries")
        entries = asset.get("Properties", {}).get("EntryTable")
        if not isinstance(entries, list):
            raise Fail("DA_UnlockableContentEntries has no EntryTable")
        if len(entries) != EXPECTED_ENTRIES:
            raise Fail(
                f"EntryTable has {len(entries)} rows, expected {EXPECTED_ENTRIES}"
            )

        tables = load_string_tables(entries)
        known: set[str] = set()
        rows = []
        for entry in entries:
            row = build_entry(entry, tables, known)
            known.add(row["tag"])
            rows.append(row)

        by_tag = {row["tag"]: row for row in rows}
        for tag, price in KF08_PRICES.items():
            if tag not in by_tag:
                raise Fail(f"KF08 anchor {tag!r} is missing from the EntryTable")
            authored = by_tag[tag]["price"]
            if authored != price:
                raise Fail(
                    f"KF08 anchor {tag!r} price drifted: have {authored}, want {price}"
                )
            label = by_tag[tag]["display"]["title"]["text"]
            if label != KF08_LABELS[tag]:
                raise Fail(
                    f"KF08 anchor {tag!r} title drifted: have {label!r}, "
                    f"want {KF08_LABELS[tag]!r}"
                )

        content_types = Counter(row["content_type"] for row in rows)
        categories = Counter(row["shop_category"] for row in rows)
        save_categories = Counter(row["save_category"] for row in rows)
        unlock_types = Counter(
            cond["type"] for row in rows for cond in row["unlock"]["conditions"]
        )
        priced = [row for row in rows if row["price"] > 0]
        free = [row for row in rows if row["price"] == 0]
        free_with_conditions = [
            row["tag"] for row in free if row["unlock"]["conditions"]
        ]

        # --- catalog contract -------------------------------------------------
        if categories != Counter(EXPECTED_COLUMNS):
            raise Fail(
                f"Black Market columns drifted: have {dict(categories)}, "
                f"want {EXPECTED_COLUMNS}"
            )
        if len(priced) != EXPECTED_PRICED:
            raise Fail(f"{len(priced)} priced rows, expected {EXPECTED_PRICED}")
        save_ids = [row["save_id"] for row in rows]
        if len(set(save_ids)) != len(save_ids):
            dupes = sorted({s for s in save_ids if save_ids.count(s) > 1})
            raise Fail(f"duplicate save_id(s): {dupes}")
        if any(not str(s).strip() for s in save_ids):
            raise Fail("empty save_id")
        tool_rows = [r for r in rows if r["save_category"] == "tools"]
        perk_rows = [r for r in rows if r["save_category"] == "perks"]
        if {r["save_id"] for r in tool_rows} != set(TOOL_SAVE_IDS.values()):
            raise Fail("tool save_id set does not match the pinned SaveSystem ids")
        if {r["save_id"] for r in perk_rows} != set(PERK_SAVE_IDS.values()):
            raise Fail("perk save_id set does not match the pinned SaveSystem ids")
        for row in rows:
            if not str(row["icon"]["asset"]).strip() or not row["icon"]["res"]:
                raise Fail(f"{row['tag']}: no icon asset/res path")

        icons_on_disk = 0
        if RAW_UE_ROOT.is_dir():
            for row in rows:
                rel = row["icon"]["res"].replace("res://assets/ue/Raw/", "")
                if not (RAW_UE_ROOT / rel).is_file():
                    raise Fail(f"{row['tag']}: icon not imported on disk: {rel}")
                icons_on_disk += 1

        mismatched_copy = [
            {
                "tag": row["tag"],
                "gates": row["condition"]["text"],
                "copy": row["condition"]["copy"],
            }
            for row in rows
            if not row["condition"]["copy_agrees"]
        ]
        conditions_without_text = [
            row["tag"]
            for row in rows
            if row["unlock"]["conditions"] and not row["condition"]["text"]
        ]
        if conditions_without_text:
            raise Fail(
                f"gated rows without derived condition text: {conditions_without_text}"
            )

        columns_meta = [
            {
                "key": "tools",
                "title": "TOOLS",
                "save_category": "tools",
                "thief": None,
                "count": categories.get("tools", 0),
            },
            {
                "key": "guild_perks",
                "title": "GUILD PERKS",
                "save_category": "perks",
                "thief": None,
                "count": categories.get("guild_perks", 0),
            },
            {
                "key": "spider_cosmetics",
                "title": "SPIDER COSMETICS",
                "save_category": "cosmetics",
                "thief": "spider",
                "count": categories.get("spider_cosmetics", 0),
            },
            {
                "key": "chameleon_cosmetics",
                "title": "CHAMELEON COSMETICS",
                "save_category": "cosmetics",
                "thief": "chameleon",
                "count": categories.get("chameleon_cosmetics", 0),
            },
        ]

        used_pairs = {
            (row["display"][field]["table_name"], row["display"][field]["key"])
            for row in rows
            for field in ("title", "description")
        }
        if not used_pairs:
            raise Fail("no string keys resolved")
        table_keys = {
            (table_id.split(".")[-1], key)
            for table_id, values in tables.items()
            for key in values
        }
        unreferenced = sorted(table_keys - used_pairs)
        bm_unreferenced = [
            key for name, key in unreferenced if name == "ST_BlackMarket"
        ]
        table_roles = {
            "ST_BlackMarket": "black_market_shop",
            "ST_Tools": "shared tool strings (descriptions for the two tool rows)",
        }

        payload = {
            "schema": SCHEMA,
            "game_version": GAME_VERSION,
            "source": {
                "entries": "extracted/json/UI/Progression/DA_UnlockableContentEntries.json",
                "entries_class": "TATUnlockableContentDataAsset",
                "string_tables": {
                    table_id.split(".")[-1]: (
                        f"extracted/json/StringTables/{table_id.split('.')[-1]}.json"
                    )
                    for table_id in sorted(tables)
                },
            },
            "units": {
                "price": "authored in-game currency units (no scaling applied)",
                "level": "authored player level (1-based as shown in the Ledger)",
            },
            "derivation": {
                "shop_category": SHOP_CATEGORY_DERIVATION,
                "save_id": (
                    "Tools/guild perks reuse the SaveSystem ids the port already "
                    "persists; cosmetics use the authored outfit tag (the same "
                    "form the Wardrobe stores for an equipped slot)."
                ),
                "condition_text": (
                    "Derived from the structured UnlockConditions (the gate the "
                    "shipped game applies), not from the description copy."
                ),
            },
            "catalog": {
                "schema": CATALOG_SCHEMA,
                "consumer": "game/src/ui/unlock_catalog.gd",
                "columns": columns_meta,
                "built_ins": BUILT_IN_TOOLS,
                "save_ids": {
                    "tools": sorted(r["save_id"] for r in tool_rows),
                    "perks": sorted(r["save_id"] for r in perk_rows),
                    "cosmetics": sorted(
                        r["save_id"] for r in rows if r["save_category"] == "cosmetics"
                    ),
                },
                "icons": {
                    "with_asset": len(rows),
                    "on_disk": icons_on_disk,
                    "root": "res://assets/ue/Raw/ (mirrors /Game/)",
                    "note": (
                        "on_disk is 0 when the extracted texture tree is absent "
                        "(normalize can run before the Godot asset import)."
                    ),
                },
            },
            "price_provenance": {
                "kf08": {
                    "frame": "KF08 00:28.50 — Black Market, YOUR TOTAL ASSETS GBP 26,275",
                    "reason": (
                        "Only these four spawned-frame prices are legible in the "
                        "shipped build; every other row is unverifiable on screen."
                    ),
                    "verified": [
                        {
                            "tag": tag,
                            "title": by_tag[tag]["display"]["title"]["text"],
                            "price": by_tag[tag]["price"],
                        }
                        for tag in KF08_PRICES
                    ],
                    "state_explains_lock": (
                        "The four visible prices are exactly the Spider cosmetic "
                        "rows whose structured level gate is <= 4 (Bob 4, Mustache "
                        "3, Full Beard 4, Eyepatch 2); every other row in the frame "
                        "shows a padlock, so the padlock is the unmet level/contract "
                        "gate and the price is the purchasable state."
                    ),
                },
                "authored_prices": (
                    "Every row's price is copied from the DataAsset; rows with "
                    "price 0 are free unlocks in the shipped table."
                ),
                "port_note": (
                    "ledger_ui.gd reads this file through unlock_catalog.gd; the "
                    "port no longer carries hard-coded show rows or an unknown "
                    "price state."
                ),
            },
            "stats": {
                "entries": len(rows),
                "by_content_type": dict(sorted(content_types.items())),
                "by_shop_category": dict(sorted(categories.items())),
                "by_save_category": dict(sorted(save_categories.items())),
                "by_unlock_type": dict(sorted(unlock_types.items())),
                "priced_entries": len(priced),
                "free_entries": len(free),
                "free_entries_with_conditions": len(free_with_conditions),
                "min_price": min(row["price"] for row in rows),
                "max_price": max(row["price"] for row in rows),
                "unique_save_ids": len(set(save_ids)),
                "icons_with_asset": len(rows),
                "icons_on_disk": icons_on_disk,
                "condition_copy_mismatches": len(mismatched_copy),
                "string_keys_used": len(used_pairs),
                "string_keys_unreferenced": len(bm_unreferenced),
                "conditions": sum(len(row["unlock"]["conditions"]) for row in rows),
            },
            "condition_copy_audit": {
                "reason": (
                    "The data asset's structured gate and its description copy "
                    "disagree on these rows; both are kept and the UI gates on the "
                    "structured requirement."
                ),
                "mismatches": mismatched_copy,
            },
            "string_tables": {
                table_id.split(".")[-1]: {
                    "table_id": table_id,
                    "role": table_roles.get(
                        table_id.split(".")[-1], "referenced by unlock rows"
                    ),
                    "keys": len(values),
                    "unreferenced_keys": sorted(
                        key
                        for name, key in unreferenced
                        if name == table_id.split(".")[-1]
                    ),
                }
                for table_id, values in sorted(tables.items())
            },
            "entries": rows,
        }

        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUT_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    except Fail as exc:
        print(f"parse_unlocks: FAIL: {exc}", file=sys.stderr)
        return 1

    stats = payload["stats"]
    print(
        "Parsed {} unlockable entries -> {}".format(
            stats["entries"], OUT_PATH.relative_to(ROOT)
        )
    )
    print(
        "  content types: "
        + ", ".join(f"{k}={v}" for k, v in stats["by_content_type"].items())
    )
    print(
        "  shop columns: "
        + ", ".join(f"{k}={v}" for k, v in stats["by_shop_category"].items())
    )
    print(
        "  prices: {} priced / {} free, {}..{}".format(
            stats["priced_entries"],
            stats["free_entries"],
            stats["min_price"],
            stats["max_price"],
        )
    )
    print(
        "  catalog: {} unique save ids, {} icons ({} on disk), {} condition-copy "
        "mismatches".format(
            stats["unique_save_ids"],
            stats["icons_with_asset"],
            stats["icons_on_disk"],
            stats["condition_copy_mismatches"],
        )
    )
    for tag in KF08_PRICES:
        row = by_tag[tag]
        print(
            "  KF08 anchor {} {} = {}".format(
                tag, row["display"]["title"]["text"], row["price"]
            )
        )
    for row in mismatched_copy:
        print(f"  copy/gate disagreement {row['tag']}: {row['gates']} vs {row['copy']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
