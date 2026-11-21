#!/usr/bin/env python3
"""
Parse the four map-spawner buckets plus their referenced pickup/civilian
Blueprint JSON into game/data/generated/gameplay/spawners.json.

Buckets (extracted/json/Missions/Spawners/Buckets/):
  DA_SpawnBucket_Bottles      -> throwable distraction bottles
  DA_SpawnBucket_AmmoRefill   -> ammo/tool refill pickup
  DA_SpawnBucket_Health       -> health refill pickup
  DA_SpawnBucket_Civilians    -> civilian generator variants

Resolved meshes are existence-checked against game/assets/ue/Content/*.glb.
Values that only exist in cooked Blueprint graphs (health heal amount, ammo
refill amount, bottle throw speed/impact noise, civilian walk speed) are NOT
invented here; they are documented approximations in docs/reports/spawners.md
and implemented as clearly-labelled constants in the GDScript side.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "spawners.json"
ASSETS = ROOT / "game" / "assets" / "ue" / "Content"

BUCKET_DIR = EX / "Missions" / "Spawners" / "Buckets"

# Bucket asset -> gameplay kind.
BUCKET_KIND = {
    "DA_SpawnBucket_Bottles": "throwable",
    "DA_SpawnBucket_AmmoRefill": "ammo",
    "DA_SpawnBucket_Health": "health",
    "DA_SpawnBucket_Civilians": "civilian",
}


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_bp_file(asset_path_name: str) -> Path | None:
    """'/Game/Gameplay/.../BP_Foo.BP_Foo_C' -> extracted/json/.../BP_Foo.json."""
    pkg = asset_path_name.split(".")[0]
    if pkg.startswith("/Game/"):
        pkg = pkg[len("/Game/") :]
    stem = pkg.split("/")[-1]
    matches = sorted((EX).rglob(stem + ".json"))
    return matches[0] if matches else None


def static_meshes_in(bp_data) -> list[str]:
    """All StaticMesh asset paths referenced by a Blueprint JSON (deduped)."""
    out: list[str] = []

    def walk(v):
        if isinstance(v, dict):
            sm = v.get("StaticMesh")
            if isinstance(sm, dict) and isinstance(sm.get("ObjectPath"), str):
                out.append(sm["ObjectPath"])
            for vv in v.values():
                walk(vv)
        elif isinstance(v, list):
            for vv in v:
                walk(vv)

    walk(bp_data)
    seen: set[str] = set()
    uniq: list[str] = []
    for p in out:
        name = p.split("'")[-2] if "'" in p else p
        if name not in seen:
            seen.add(name)
            uniq.append(p)
    return uniq


def skeletal_meshes_in(bp_data) -> list[str]:
    out: list[str] = []

    def walk(v):
        if isinstance(v, dict):
            for k, vv in v.items():
                if (
                    k == "ObjectName"
                    and isinstance(vv, str)
                    and vv.startswith("SkeletalMesh'")
                ):
                    out.append(vv)
                else:
                    walk(vv)
        elif isinstance(v, list):
            for vv in v:
                walk(vv)

    walk(bp_data)
    seen: set[str] = set()
    uniq: list[str] = []
    for p in out:
        if p not in seen:
            seen.add(p)
            uniq.append(p)
    return uniq


def ue_pkg_to_res(asset_object_path: str) -> tuple[str, bool]:
    """'/Game/Art/.../SM_Foo.N' -> ('res://assets/ue/Content/Art/.../SM_Foo.glb', exists)."""
    inner = (
        asset_object_path.split("'")[1]
        if "'" in asset_object_path
        else asset_object_path
    )
    pkg = inner.split(".")[0]
    if pkg.startswith("/Game/"):
        pkg = pkg[len("/Game/") :]
    res = f"res://assets/ue/Content/{pkg}.glb"
    rel = res[len("res://") :]
    # res:// maps to game/ for assets under game/.
    disk = ROOT / "game" / rel
    return res, disk.is_file()


def hidden_static_meshes(bp_data) -> set[str]:
    """StaticMesh paths on components explicitly authored bVisible=false.

    The ammo pickup carries two hidden briefcase dressing meshes plus the
    visible SM_Toolbox interact mesh; the briefcases must not win the
    "first mesh" heuristic below.
    """
    hidden: set[str] = set()

    def walk(v):
        if isinstance(v, dict):
            if v.get("Type") == "StaticMeshComponent":
                props = v.get("Properties", {})
                if isinstance(props, dict) and props.get("bVisible") is False:
                    sm = props.get("StaticMesh")
                    if isinstance(sm, dict) and isinstance(sm.get("ObjectPath"), str):
                        hidden.add(sm["ObjectPath"])
            for vv in v.values():
                walk(vv)
        elif isinstance(v, list):
            for vv in v:
                walk(vv)

    walk(bp_data)
    return hidden


# Representative civilian body/head per generator class. The generator
# Blueprints reference several outfit/head variants each; these are the
# documented canonical pairs (present in each file's referenced set).
CIVILIAN_PREFERRED = {
    "BP_CivilianGeneratorMale_LowerClass1_C": (
        "SK_CivMale_Common_01",
        "SK_CivMale_Head_Adam_Fade01",
    ),
    "BP_CivilianGeneratorMale_LowerClass2_C": (
        "SK_CivMale_Common_01D",
        "SK_CivMale_Head_Adam_Fade02",
    ),
    "BP_CivilianGeneratorFemale_LowerClass1_C": (
        "SK_CivFemale_Common_01C",
        "SK_CivFemale_Head_Abby_Short01",
    ),
    "BP_CivilianGeneratorFemale_LowerClass2_C": (
        "SK_CivFemale_Common_01C",
        "SK_CivFemale_Head_Abby_Short01",
    ),
}


def cdo_props(bp_data, class_name: str) -> dict:
    """Top-level Properties of the ClassDefaultObject entry for a BP class."""
    short = class_name.split(".")[-1]
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if entry.get("Name") == f"Default__{short}" or entry.get("Type") == short:
            props = entry.get("Properties")
            if isinstance(props, dict) and "UberGraphFrame" in props:
                return props
    return {}


def main() -> None:
    entries: list[dict] = []
    civilian_meshes: dict[str, dict] = {}
    for bucket_name in sorted(BUCKET_KIND.keys()):
        bucket_file = BUCKET_DIR / (bucket_name + ".json")
        if not bucket_file.is_file():
            raise SystemExit(f"missing bucket file: {bucket_file}")
        kind = BUCKET_KIND[bucket_name]
        bucket = bucket_name
        data = load_json(bucket_file)
        for asset in data:
            for e in asset.get("Properties", {}).get("Entries", []) or []:
                cts = e.get("ClassToSpawn") or {}
                apn = str(cts.get("AssetPathName", ""))
                if not apn:
                    continue
                bp_file = find_bp_file(apn)
                rec: dict = {
                    "kind": kind,
                    "bucket": bucket,
                    "class": apn,
                    "bucket_source": str(bucket_file.relative_to(ROOT)),
                    "bp_source": str(bp_file.relative_to(ROOT)) if bp_file else "",
                }
                if bp_file is not None:
                    bp = load_json(bp_file)
                    short = apn.split(".")[-1]
                    cdo = cdo_props(bp, short)
                    if "InteractDuration" in cdo:
                        rec["interact_duration_s"] = float(cdo["InteractDuration"])
                    if "SphereRadius" in cdo:
                        # UE centimetres on the component; 35.0 cm = 0.35 m.
                        rec["trigger_radius_cm"] = float(cdo["SphereRadius"])
                    meshes = static_meshes_in(bp)
                    if meshes:
                        # Prefer the first mesh NOT authored bVisible=false
                        # (ammo pickup: hidden briefcase dressing loses to
                        # the visible SM_Toolbox interact mesh).
                        hidden = hidden_static_meshes(bp)
                        visible = [m for m in meshes if m not in hidden]
                        ue_path = visible[0] if visible else meshes[0]
                        res, exists = ue_pkg_to_res(ue_path)
                        rec["mesh_ue_path"] = ue_path
                        rec["mesh_res_path"] = res
                        rec["mesh_exists"] = exists
                        if kind == "ammo":
                            rec["mesh_role"] = "interact_mesh"
                            rec["hidden_decor"] = [m for m in meshes if m != ue_path]
                    if kind == "civilian":
                        sk = skeletal_meshes_in(bp)
                        # Full referenced outfit/head set for the report.
                        rec["skeletal_meshes"] = sk
                        # Representative pair: preferred canonical names when
                        # present in the file, else first body/head found.
                        sk_names = [(s.split("'")[-2] if "'" in s else s) for s in sk]
                        pref_body, pref_head = CIVILIAN_PREFERRED.get(short, ("", ""))
                        body_name = (
                            pref_body
                            if pref_body in sk_names
                            else next((n for n in sk_names if "_Head_" not in n), "")
                        )
                        head_name = (
                            pref_head
                            if pref_head in sk_names
                            else next((n for n in sk_names if "_Head_" in n), "")
                        )

                        def sk_to_res(name: str) -> tuple[str, bool]:
                            # Mesh stem -> res path via Content-tree stem match.
                            ms = sorted(
                                (ROOT / "game" / "assets" / "ue" / "Content").rglob(
                                    name + ".glb"
                                )
                            )
                            if ms:
                                return "res://assets/ue/Content/" + str(
                                    ms[0].relative_to(
                                        ROOT / "game" / "assets" / "ue" / "Content"
                                    )
                                ).replace("\\", "/"), True
                            return "", False

                        body_res, body_ok = (
                            sk_to_res(body_name) if body_name else ("", False)
                        )
                        head_res, head_ok = (
                            sk_to_res(head_name) if head_name else ("", False)
                        )
                        rec["body_res_path"] = body_res
                        rec["body_exists"] = body_ok
                        rec["head_res_path"] = head_res
                        rec["head_exists"] = head_ok
                        civilian_meshes[short] = {
                            "body_res_path": body_res,
                            "body_exists": body_ok,
                            "head_res_path": head_res,
                            "head_exists": head_ok,
                        }
                entries.append(rec)

    missing = [e for e in entries if "mesh_res_path" in e and not e.get("mesh_exists")]
    # P1-7: fail-closed AND optimization-proof. `assert` vanishes under
    # `python -O`; a validator that disappears in optimized builds is no
    # validator. UE path is logged per missing mesh (sentinel discipline).
    if missing:
        for e in missing:
            print(f"[spawner-mesh-missing] kind={e.get('kind')} class={e.get('class')} ue={e.get('mesh_ue_path')}")
        raise SystemExit(f"resolved spawner meshes missing on disk: {len(missing)}")
    missing_civ = [
        k
        for k, v in civilian_meshes.items()
        if not (v["body_exists"] and v["head_exists"])
    ]
    if missing_civ:
        for k in missing_civ:
            print(f"[spawner-mesh-missing] civilian generator {k}: {civilian_meshes[k]}")
        raise SystemExit(f"civilian meshes missing on disk: {missing_civ}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(
            {
                "sources": [
                    str(p.relative_to(ROOT))
                    for p in sorted(BUCKET_DIR.glob("DA_SpawnBucket_*.json"))
                ],
                "buckets": entries,
                "civilian_meshes": civilian_meshes,
                "approximations": {
                    "health_heal_amount": "NOT SERIALIZED in cooked graphs; implemented as full heal (documented).",
                    "ammo_refill_amount": "NOT SERIALIZED in cooked graphs; implemented as refill-all-charges (documented).",
                    "bottle_throw_speed_m_s": "NOT SERIALIZED; documented approximation 12.0 m/s.",
                    "bottle_impact_noise_m": "NOT SERIALIZED; documented approximation 10.0 m radius.",
                    "civilian_walk_speed_m_s": "NOT SERIALIZED; documented approximation 1.4 m/s.",
                    "civfemale_clips": "NO CivFemale clips in the animation manifest; generic MM_Unarmed_* clips retargeted by bone name, else rest pose.",
                },
            },
            f,
            indent=2,
        )
        f.write("\n")
    print(
        f"wrote {OUT} ({len(entries)} bucket entries, {len(civilian_meshes)} civilian variants)"
    )


if __name__ == "__main__":
    main()
