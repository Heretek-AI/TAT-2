#!/usr/bin/env python3
"""
Emit game/data/generated/gameplay/containers.json: every allowlisted placed
loot-container Blueprint (the CLASSES map below), mapped to kind/bucket/slot
entries. `BP_UtilityBoxA_MinorLoot_C` also carries a spawner but is
deliberately outside CLASSES (one POI 3rd-floor marker); it is recorded as the
one known unemitted container in docs/reports/lane-gc-bookcases-20261127.md.

Classes:
  BP_ChestTrunk_MajorLoot_C               89  kind major (major bucket + minor bonus spawner)
  BP_DisplayCaseA_MajorLoot_C             68  kind major
  BP_LootStashInteractable_Secret_ThinWall_C 57  kind stash (no spawn bucket;
      real meshes SM_Stash_ThinWallA_Base/DoorLeft/DoorRight/Glow live in the
      level geometry; one-use deposit-all, its loot arrives as separately placed actors)
  BP_Storefront_DisplayCaseB_MinorLoot_C   6  kind minor
  BP_Storefront_DisplayCaseD_MinorLoot_C  14  kind minor

Phase 2 G-1 adds the three K-06 classes dropped by the old 5-class filter:
  BP_Manor_Bookcase_Cabinet_MinorLoot_C   8 Guildhall_Loot + 1 OldManor_Geo
                                          4 authored slots (minor bucket)
  BP_Manor_Bookcase_Cabinet_MajorLoot_C   2 Building_Guildhall_POI
                                          1 major slot (clue mode) + 3 minor
  BP_SmallSafe_MajorLoot_C                8 Guildhall_Loot, `locked: true`,
                                          cap 2; 1 major slot + 1 minor slot

Container meshes are NOT recorded here: they are already spawned by the
level loader from the level geometry, so the runtime never spawns them.

Slot entries come from the TATContainerSpawnerComponent SpawnSlotEntries
(raw UE centimetres + FRotator degrees). No Interact tags/durations are
authored on these Blueprints (or their parents), so open_interact is null:
opening is instant.

`breakable_source` (Phase 2 G-3; no damage path is invented):
  * `authored_breakable` - the Blueprint or an authored Super chain sets
    `_isBreakable: true` on its breakable component. The port still smashes
    with the labelled hold-F PORT_DECISION; no health/damage is applied.
  * `disabled_component` - no authored `_isBreakable: true` exists in the
    chain (the effective value is the shared
    BP_BreakableComponent_DisabledToggle CDO default `false`), or the class
    authors no breakable component at all. The port must never invent a
    break path for these; the GC overlay (when authored) is the only visual.

Per-instance locks are NOT in this file: the generated `.tatlevel.json`
markers carry the authored `locked` / `max_lock_level` / `min_lock_level` /
`can_lockpick` delta, and `loot_container.configure()` applies those. The
class-level `lock_config` here is only the CDO cap provenance.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "containers.json"

# Blueprint JSON (relative to extracted/json) -> container kind.
CLASSES = {
    "Art/Environment/Props/Furniture/Containers/Chest/BP_ChestTrunk_MajorLoot.json": "major",
    "Art/Gameplay/MajorLootSafe/BP_DisplayCaseA_MajorLoot.json": "major",
    "Gameplay/Loot/Actors/Stash/BP_LootStashInteractable_Secret_ThinWall.json": "stash",
    "Art/Environment/Storefront/Interior/BP_Storefront_DisplayCaseB_MinorLoot.json": "minor",
    "Art/Environment/Storefront/Interior/BP_Storefront_DisplayCaseD_MinorLoot.json": "minor",
    "Art/Environment/Manor/BP_Manor_Bookcase_Cabinet_MinorLoot.json": "minor",
    "Art/Environment/Manor/BP_Manor_Bookcase_Cabinet_MajorLoot.json": "major",
    "Gameplay/Interactables/Containers/BP_SmallSafe_MajorLoot.json": "major",
}


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def short_bucket(obj_name: str) -> str:
    """TATActorSpawnBucketAsset'DA_SpawnBucket_MajorLoot' -> DA_SpawnBucket_MajorLoot."""
    s = obj_name.strip()
    if "'" in s:
        s = s.split("'")[1]
    return s


def spawner_entries(bp_data) -> list:
    """All TATContainerSpawnerComponent entries: bucket + slot entries."""
    out = []
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if entry.get("Type") != "TATContainerSpawnerComponent":
            continue
        props = entry.get("Properties")
        if not isinstance(props, dict):
            continue
        bucket = props.get("SpawnBucket") or {}
        slots = []
        for s in props.get("SpawnSlotEntries") or []:
            off = (s or {}).get("SpawnOffset") or {}
            rot = (s or {}).get("SpawnRotation") or {}
            slots.append(
                {
                    "offset_cm": [
                        float(off.get("X", 0.0)),
                        float(off.get("Y", 0.0)),
                        float(off.get("Z", 0.0)),
                    ],
                    "rotation_deg": [
                        float(rot.get("Pitch", 0.0)),
                        float(rot.get("Yaw", 0.0)),
                        float(rot.get("Roll", 0.0)),
                    ],
                }
            )
        out.append(
            {
                "component": str(entry.get("Name", "")),
                "bucket": short_bucket(str(bucket.get("ObjectName", ""))),
                "bucket_path": str(bucket.get("ObjectPath", "")),
                "spawn_group": str((props.get("SpawnGroup") or {}).get("TagName", "")),
                # Phase 2 G-1 provenance: the two authored flags that decide
                # which spawner is the container's loot spawner.
                "primary_for_actor": props.get("_primarySpawnerForActor") is True,
                "clue_mode": str(props.get("_clueMode") or ""),
                "slot_entries": slots,
            }
        )
    return out


def interact_props(bp_data) -> dict | None:
    """Interact tags/duration when a component authors them, else None."""
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        props = entry.get("Properties")
        if not isinstance(props, dict):
            continue
        keys = [k for k in props.keys() if "nteract" in k]
        if keys and entry.get("Type") not in ("BlueprintGeneratedClass",):
            return {k: props[k] for k in keys}
    return None


def super_rel(bp_data) -> str | None:
    """BlueprintGeneratedClass.Super path -> extracted/json-relative .json path.

    The cooked export carries the parent class on the generated class
    (`Super.ObjectPath`, e.g. `/Game/Art/.../BP_SmallSafe.0`). Following it is
    the authored inheritance chain, not a name heuristic: the loot subclasses
    author no breakable properties of their own.
    """
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if entry.get("Type") != "BlueprintGeneratedClass":
            continue
        op = str(((entry.get("Super") or {}).get("ObjectPath")) or "")
        if not op.startswith("/Game/"):
            return None
        rel = op[len("/Game/") :].rsplit(".", 1)[0]
        return rel + ".json"
    return None


def breakable_props(bp_data) -> tuple[str, dict] | tuple[None, None]:
    """The class's own breakable component type + authored properties."""
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if "Breakable" not in str(entry.get("Type", "")):
            continue
        props = entry.get("Properties")
        return str(entry.get("Type", "")), (props if isinstance(props, dict) else {})
    return None, None


def breakable_provenance(rel: str) -> dict:
    """Resolve `_isBreakable` / health row along the authored Super chain.

    `authored_breakable` requires an explicit `_isBreakable: true` somewhere in
    the chain (the loot subclasses inherit it from the non-loot base class).
    Everything else is `disabled_component`: the shared
    BP_BreakableComponent_DisabledToggle CDO default is `_isBreakable: false`,
    or no breakable component exists at all. The probe/consumer must not invent
    a damage path for those.
    """
    cur = rel
    seen = set()
    for _ in range(8):
        if cur is None or cur in seen:
            break
        seen.add(cur)
        path = EX / cur
        if not path.is_file():
            break
        data = load_json(path)
        comp_type, props = breakable_props(data)
        if comp_type is not None and props.get("_isBreakable") is True:
            health = props.get("_maxHealth") or {}
            curve = (health.get("Curve") or {}) if isinstance(health, dict) else {}
            return {
                "breakable_source": "authored_breakable",
                "breakable_owner": Path(cur).stem + "_C",
                "breakable_health_row": str(curve.get("RowName") or ""),
            }
        cur = super_rel(data)
    return {
        "breakable_source": "disabled_component",
        "breakable_owner": "",
        "breakable_health_row": "",
    }


def cdo_props(bp_data) -> dict:
    """The Default__<class> CDO properties (lock config, spawned defaults)."""
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if not str(entry.get("Name", "")).startswith("Default__"):
            continue
        props = entry.get("Properties")
        return props if isinstance(props, dict) else {}
    return {}


def lock_config(bp_data) -> dict:
    """Authored `_lockConfig` (CDO cap) + `_locked` when the class serialises it.

    This is class-level provenance only: the placed marker delta in the level
    payload is what `loot_container.configure()` applies.
    """
    props = cdo_props(bp_data)
    cfg = props.get("_lockConfig")
    out: dict = {}
    if isinstance(cfg, dict):
        if "MaxLockLevel" in cfg:
            out["max_lock_level"] = int(cfg["MaxLockLevel"])
        if "MinLockLevel" in cfg:
            out["min_lock_level"] = int(cfg["MinLockLevel"])
        if "CanBeLockpicked" in cfg:
            out["can_lockpick"] = bool(cfg["CanBeLockpicked"])
    if "_locked" in props:
        out["locked_default"] = bool(props.get("_locked"))
    return out


def pick_primary_spawner(spawners: list, kind: str) -> tuple[dict, list]:
    """Primary loot spawner for the class + the remaining (extra) spawners.

    Preference order, all authored fields (Phase 2 G-1):
      1. `_primarySpawnerForActor == true` (the Blueprint's explicit primary);
      2. the bucket tier the kind names (MajorLoot / MinorLoot) — a chest ships
         a major spawner plus a minor bonus spawner;
      3. not `_clueMode` (`ETATSpawnerClueMode::FromSpawnedActor`) — clue mode
         is derived-clue output on the *same* loot spawner, never a reason to
         prefer a spawner over another, so this is only a tie-break;
      4. authored order.
    Every shipped major container (chest/display case/bookcase/safe) uses
    `_clueMode` on its major spawner; treating that as a disqualifier would
    drop the major bucket from all four.
    """
    if not spawners:
        return {}, []
    want = "MajorLoot" if kind == "major" else "MinorLoot"
    primary = next((s for s in spawners if s.get("primary_for_actor") is True), None)
    if primary is None:
        primary = next((s for s in spawners if want in s["bucket"]), None)
    if primary is None:
        primary = next((s for s in spawners if not s.get("clue_mode")), None)
    if primary is None:
        primary = spawners[0]
    return primary, [s for s in spawners if s is not primary]


def main() -> None:
    classes_out: dict[str, dict] = {}
    # P2-4: the CLASSES dict is closed — another container Blueprint in cooked
    # data would never emit. Scan for container-shaped Blueprints outside the
    # dict and warn so the gap is a visible line, not a silent hole. The token
    # list does not match `UtilityBox`, so `BP_UtilityBoxA_MinorLoot_C` (the one
    # known gap) stays silent here and is recorded in the lane report instead.
    known_stems = {Path(r).stem for r in CLASSES}
    for bp_file in sorted(EX.rglob("BP_*.json")):
        stem = bp_file.stem
        if stem in known_stems:
            continue
        if any(
            k in stem
            for k in ("Container", "Stash", "DisplayCase", "Chest", "LootStash")
        ):
            print(
                f"WARN: container-shaped Blueprint outside CLASSES (not emitted): {bp_file.relative_to(ROOT)}"
            )
    for rel, kind in CLASSES.items():
        bp_file = EX / rel
        if not bp_file.is_file():
            raise SystemExit(f"missing container Blueprint JSON: {bp_file}")
        bp = load_json(bp_file)
        spawners = spawner_entries(bp)
        if kind == "none" and spawners:
            raise SystemExit(f"{rel}: kind none but carries a spawn bucket")
        if kind in ("major", "minor") and not spawners:
            raise SystemExit(f"{rel}: kind {kind} but no TATContainerSpawnerComponent")
        bucket = ""
        slots: list = []
        extras: list = []
        primary: dict = {}
        if spawners:
            primary, extras = pick_primary_spawner(spawners, kind)
            bucket = primary["bucket"]
            slots = primary["slot_entries"]
        open_interact = interact_props(bp)
        breakable = breakable_provenance(rel)
        classes_out[bp_file.stem + "_C"] = {
            "kind": kind,
            "bucket": bucket,
            "slot_entries": slots,
            "slot_count": len(slots),
            "extra_spawners": extras,
            "primary_spawner": str(primary.get("component", "")),
            "open_interact": open_interact,
            "lock_config": lock_config(bp),
            **breakable,
            "source": str(bp_file.relative_to(ROOT)),
        }
        if kind == "stash":
            # Port policy (no count is authored on the Blueprint): each secret
            # stash is a one-use deposit-all. See tools/parse_settings.py
            # ("stash.uses_per_stash") for the matching runtime value.
            classes_out[bp_file.stem + "_C"]["stash_uses"] = 1
            classes_out[bp_file.stem + "_C"]["one_use"] = True

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(
            {
                "sources": {
                    "blueprints": sorted(
                        str((EX / r).relative_to(ROOT)) for r in CLASSES
                    ),
                    "note": (
                        "No Interact tags/durations are authored on these "
                        "Blueprints, so open_interact is null everywhere and "
                        "opening is instant. Container meshes are level "
                        "geometry (spawned by the level loader), never "
                        "spawned by the container script."
                    ),
                },
                "classes": classes_out,
            },
            f,
            indent=2,
        )
        f.write("\n")
    kinds = {c: v["kind"] for c, v in classes_out.items()}
    print(f"wrote {OUT} ({len(classes_out)} container classes: {kinds})")


if __name__ == "__main__":
    main()
