#!/usr/bin/env python3
"""
Emit game/data/generated/gameplay/containers.json: the five placed loot-
container Blueprints mapped to kind/bucket/slot entries.

Classes (234 markers across the normalized levels):
  BP_ChestTrunk_MajorLoot_C               89  kind major (major bucket + minor bonus spawner)
  BP_DisplayCaseA_MajorLoot_C             68  kind major
  BP_LootStashInteractable_Secret_ThinWall_C 57  kind stash (no spawn bucket;
      real meshes SM_Stash_ThinWallA_Base/DoorLeft/DoorRight/Glow live in the
      level geometry; one-use deposit-all, its loot arrives as separately placed actors)
  BP_Storefront_DisplayCaseB_MinorLoot_C   6  kind minor
  BP_Storefront_DisplayCaseD_MinorLoot_C  14  kind minor

Container meshes are NOT recorded here: they are already spawned by the
level loader from the level geometry, so the runtime never spawns them.

Slot entries come from the TATContainerSpawnerComponent SpawnSlotEntries
(raw UE centimetres + FRotator degrees). No Interact tags/durations are
authored on these Blueprints (or their parents), so open_interact is null:
opening is instant.
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


def main() -> None:
    classes_out: dict[str, dict] = {}
    # P2-4: the CLASSES dict is closed — a 6th container Blueprint in cooked
    # data would never emit. Scan for container-shaped Blueprints outside the
    # dict and warn so the gap is a visible line, not a silent hole.
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
        if spawners:
            # Primary spawner: the one whose bucket tier matches the kind
            # (ChestTrunk carries a major spawner plus a minor bonus spawner).
            want = "MajorLoot" if kind == "major" else "MinorLoot"
            primary = next((s for s in spawners if want in s["bucket"]), spawners[0])
            bucket = primary["bucket"]
            slots = primary["slot_entries"]
            extras = [s for s in spawners if s is not primary]
        open_interact = interact_props(bp)
        classes_out[bp_file.stem + "_C"] = {
            "kind": kind,
            "bucket": bucket,
            "slot_entries": slots,
            "extra_spawners": extras,
            "open_interact": open_interact,
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
