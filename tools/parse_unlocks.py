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

The game does not read this file yet; ``ledger_ui.gd`` still carries its own
hard-coded rows. This is the authoritative replacement source, not a wire-up.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_ROOT = ROOT / "extracted" / "json"
ENTRY_JSON = JSON_ROOT / "UI" / "Progression" / "DA_UnlockableContentEntries.json"
STRING_TABLE_DIR = JSON_ROOT / "StringTables"
OUT_PATH = ROOT / "game" / "data" / "generated" / "gameplay" / "unlocks.json"
SCHEMA = "tat2.unlocks/1"
GAME_VERSION = "Steam 1.5.193.148559"

EXPECTED_ENTRIES = 68

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
    return {
        "tag": tag,
        "content_type": content_type,
        "price": price,
        "display": {
            "title": resolve_string(entry["DisplayName"], tables, f"{tag} title"),
            "description": resolve_string(
                entry["Description"], tables, f"{tag} description"
            ),
        },
        "icon": {
            "asset": str(texture.get("AssetPathName", "")),
            "sub_path": str(texture.get("SubPathString", "")),
        },
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
        unlock_types = Counter(
            cond["type"] for row in rows for cond in row["unlock"]["conditions"]
        )
        priced = [row for row in rows if row["price"] > 0]
        free = [row for row in rows if row["price"] == 0]
        free_with_conditions = [
            row["tag"] for row in free if row["unlock"]["conditions"]
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
            "derivation": {"shop_category": SHOP_CATEGORY_DERIVATION},
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
                },
                "authored_prices": (
                    "Every row's price is copied from the DataAsset; rows with "
                    "price 0 are free unlocks in the shipped table."
                ),
                "port_note": (
                    "game/src/ui/ledger_ui.gd still carries hard-coded placeholder "
                    "prices for unverified rows and shows PRICE UNKNOWN for them."
                ),
            },
            "stats": {
                "entries": len(rows),
                "by_content_type": dict(sorted(content_types.items())),
                "by_shop_category": dict(sorted(categories.items())),
                "by_unlock_type": dict(sorted(unlock_types.items())),
                "priced_entries": len(priced),
                "free_entries": len(free),
                "free_entries_with_conditions": len(free_with_conditions),
                "min_price": min(row["price"] for row in rows),
                "max_price": max(row["price"] for row in rows),
                "string_keys_used": len(used_pairs),
                "string_keys_unreferenced": len(bm_unreferenced),
                "conditions": sum(len(row["unlock"]["conditions"]) for row in rows),
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
    for tag in KF08_PRICES:
        row = by_tag[tag]
        print(
            "  KF08 anchor {} {} = {}".format(
                tag, row["display"]["title"]["text"], row["price"]
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
