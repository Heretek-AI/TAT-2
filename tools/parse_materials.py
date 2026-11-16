#!/usr/bin/env python3
"""Build game/data/generated/materials.json from extracted MI_*/M_* JSONs and PNGs."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_JSON = ROOT / "extracted" / "json"
EX_ASSETS = ROOT / "extracted" / "assets"
OUT = ROOT / "game" / "data" / "generated" / "materials.json"
OUT_MESH_MATS = ROOT / "game" / "data" / "generated" / "mesh_materials.json"


def ue_to_res_png(obj_path: str) -> str:
    if not obj_path or not isinstance(obj_path, str):
        return ""
    clean = obj_path.split(".")[0]
    if clean.startswith("/Game/"):
        clean = clean[6:]
    if (EX_ASSETS / (clean + ".png")).exists():
        return "res://assets/ue/Raw/" + clean + ".png"
    if (EX_ASSETS / "TAT" / "Content" / (clean + ".png")).exists():
        return "res://assets/ue/Content/" + clean + ".png"
    return ""


DIFFUSE_SUFFIXES = ("_d", "_da", "_bc", "_bco", "_c", "_alb", "_basecolor", "_diffuse")

# Category -> candidate texture stems (lowercase, verified against extracted Raw set).
CATEGORY_FALLBACK_STEMS = {
    "brick": [
        "t_civicbricka_d",
        "t_oldbricksa_d",
        "t_oldbricksb_d",
        "t_brickgrounda_d",
        "t_roadbricksa_d",
    ],
    "stone": [
        "t_wallstonea_d",
        "t_civicstonea_d",
        "t_modularstonea_d",
        "t_stonewalld_da",
        "t_granitefloora_d",
    ],
    "wood": [
        "t_woodfloora_d",
        "t_manorwood_d",
        "t_woodboardsa_d",
        "t_woodvarnisha_d",
        "t_manorpanels_d",
    ],
    "plaster": [
        "t_plaster_d",
        "t_plastera_bco",
        "t_plasterb_d",
        "t_plasterc_d",
        "t_ceilingplaster_da",
    ],
    "roof": [
        "t_roofslatea_d",
        "t_roofslatee_d",
        "t_roofbitumena_da",
        "t_roofslatec_da",
    ],
    "metal": [
        "t_trimmetala_d",
        "t_metalstripsa_bco",
        "t_basicmetalsurfacetrimA_d".lower(),
        "t_metaltilepipes_d",
        "t_grate_d",
    ],
    "dirt": [
        "t_grounddirta_d",
        "t_grounddirta_bco",
        "t_grounddirtb_d",
        "t_dirtmossa_bc",
    ],
}


def _strip_material_base(mat_name: str) -> str:
    base: str = mat_name.lower()
    base = re.sub(r"^(mi_|m_)", "", base)
    base = re.sub(r"(_inst.*|_instance.*)$", "", base)
    base = base.strip("_")
    return base


def _stem_fallback_albedo(
    mat_name: str, pkg: str, parent: str, tex_by_stem: dict
) -> str:
    base: str = _strip_material_base(mat_name)
    if base == "":
        return ""
    # 1) Direct stem match: look for diffuse textures whose stem mentions the base.
    best: str = ""
    best_len: int = 10_000
    for tstem, res in tex_by_stem.items():
        low: str = tstem.lower()
        if not low.endswith(DIFFUSE_SUFFIXES):
            continue
        if base in low or low in ("t_" + base + "_d", "t_" + base + "_bc"):
            if len(low) < best_len:
                best = res
                best_len = len(low)
    if best != "":
        return best
    # Token match: any underscore-separated token of base inside a diffuse stem.
    tokens: list = [t for t in re.split(r"[^a-z0-9]+", base) if len(t) >= 4]
    for tstem, res in tex_by_stem.items():
        low2: str = tstem.lower()
        if not low2.endswith(DIFFUSE_SUFFIXES):
            continue
        for tok in tokens:
            if tok in low2:
                return res
    # 2) Category fallback: material/pkg/parent name mentions Brick/Stone/Wood/etc.
    hay: str = (mat_name + " " + pkg + " " + parent).lower()
    for cat, stems in CATEGORY_FALLBACK_STEMS.items():
        if cat in hay:
            for cand in stems:
                if cand in tex_by_stem:
                    found: str = tex_by_stem[cand]
                    return found
    return ""


def main():
    tex_by_stem = {}
    for png in EX_ASSETS.rglob("*.png"):
        rel = png.relative_to(EX_ASSETS)
        s = str(rel)
        res = (
            ("res://assets/ue/Content/" + s[len("TAT/Content/") :])
            if s.startswith("TAT/Content/")
            else ("res://assets/ue/Raw/" + s)
        )
        tex_by_stem.setdefault(png.stem.lower(), res)

    raw_mats = {}
    for jf in EX_JSON.rglob("*.json"):
        name = jf.stem
        if not (name.startswith("MI_") or name.startswith("M_")):
            continue
        try:
            exps = json.loads(jf.read_text())
        except Exception:
            continue
        if not isinstance(exps, list) or not exps:
            continue
        exp = exps[0]
        props = exp.get("Properties") or {}
        pkg = exp.get("Package") or (
            "/Game/" + str(jf.relative_to(EX_JSON).with_suffix(""))
        )
        parent = ((props.get("Parent") or {}).get("ObjectPath") or "").split(".")[0]
        texs = {}
        for tv in props.get("TextureParameterValues") or []:
            pinfo = tv.get("ParameterInfo") or {}
            pname = (pinfo.get("Name") or "").lower()
            assoc = pinfo.get("Association") or ""
            tpath = ue_to_res_png(
                (tv.get("ParameterValue") or {}).get("ObjectPath") or ""
            )
            if not tpath:
                continue
            stem = Path(tpath).stem.lower()
            is_mask = (
                "blendparameter" in assoc.lower()
                or stem.endswith(("_ma", "_mask", "_m", "_r", "_g", "_b", "_a", "_ao"))
                or any(
                    k in pname
                    for k in (
                        "mask",
                        "blend",
                        "grunge",
                        "noise",
                        "stroke",
                        "pattern",
                        "detail",
                        "cavity",
                        "height",
                    )
                )
            )
            if any(k in pname for k in ("normal", "norm")) or stem.endswith(
                ("_n", "_nm")
            ):
                texs.setdefault("normal", tpath)
            elif (
                "orm" in pname
                or "roughness" in pname
                or "arm" in pname
                or stem.endswith(("_orm", "_ormm", "_arm"))
            ):
                texs.setdefault("orm", tpath)
            elif "emissive" in pname or stem.endswith("_e"):
                if "black" not in stem and not name.startswith("M_Env"):
                    texs.setdefault("emissive", tpath)
            elif not is_mask and (
                any(
                    k in pname
                    for k in (
                        "albedo",
                        "basecolor",
                        "base_color",
                        "diffuse",
                        "color",
                        "bc",
                        "base texture",
                    )
                )
                or stem.endswith(("_d", "_da", "_bc", "_bco", "_c", "_alb"))
            ):
                texs.setdefault("albedo", tpath)

        # Fallback: UE5 MaterialLayers store used textures in TextureStreamingData and CachedExpressionData.ReferencedTextures
        extra_paths = []
        for tsd in props.get("TextureStreamingData") or []:
            tn = (tsd.get("TextureName") or "").lower()
            if tn and tn in tex_by_stem:
                extra_paths.append(tex_by_stem[tn])
        for rt in (exp.get("CachedExpressionData") or {}).get(
            "ReferencedTextures"
        ) or []:
            if isinstance(rt, dict):
                tp = ue_to_res_png(rt.get("ObjectPath") or "")
                if tp:
                    extra_paths.append(tp)
        for tpath in extra_paths:
            stem = Path(tpath).stem.lower()
            if stem.endswith(("_ma", "_mask", "_ao", "_e")) or any(
                k in stem
                for k in ("paintstroke", "grunge", "noise", "default", "black", "white")
            ):
                continue
            if stem.endswith(("_n", "_nm")):
                texs.setdefault("normal", tpath)
            elif stem.endswith(("_orm", "_ormm", "_arm")):
                texs.setdefault("orm", tpath)
            elif stem.endswith(("_d", "_da", "_bc", "_bco", "_c", "_alb")):
                texs.setdefault("albedo", tpath)
        # Stem-based fallback: strip MI_/M_/Inst and search indexed Raw diffuse
        # textures; then fall back to category textures (Brick/Stone/Wood/...).
        if "albedo" not in texs:
            fb: str = _stem_fallback_albedo(name, pkg, parent, tex_by_stem)
            if fb != "":
                texs["albedo"] = fb
        tint = None
        for vv in props.get("VectorParameterValues") or []:
            pinfo = vv.get("ParameterInfo") or {}
            pname = (pinfo.get("Name") or "").lower()
            if (
                "mask" in pname
                or "channel" in pname
                or "blendparameter" in (pinfo.get("Association") or "").lower()
            ):
                continue
            if (
                "tint" in pname
                or "basecolor" in pname
                or "albedo" in pname
                or pname == "color"
            ):
                val = vv.get("ParameterValue") or {}
                if "R" in val:
                    r, g, b, a = (
                        float(val["R"]),
                        float(val["G"]),
                        float(val["B"]),
                        float(val.get("A", 1.0)),
                    )
                    # Skip RGBA channel selector vectors like [0, 1, 0, 0] or [1, 0, 0, 0]
                    if a <= 0.01 or (
                        max(r, g, b) >= 0.99
                        and min(r, g, b) == 0.0
                        and (r + g + b) <= 1.01
                    ):
                        continue
                    tint = [round(r, 3), round(g, 3), round(b, 3), round(a, 3)]
                    break
        raw_mats[pkg] = {"parent": parent, "texs": texs, "tint": tint}

    # Resolve parent inheritance
    resolved = {}

    def resolve(pkg, depth=0):
        if pkg in resolved:
            return resolved[pkg]
        if depth > 8 or pkg not in raw_mats:
            return {"texs": {}, "tint": None}
        cur = raw_mats[pkg]
        base = (
            resolve(cur["parent"], depth + 1)
            if cur["parent"]
            else {"texs": {}, "tint": None}
        )
        texs = dict(base["texs"])
        texs.update(cur["texs"])
        tint = cur["tint"] if cur["tint"] is not None else base["tint"]
        resolved[pkg] = {"texs": texs, "tint": tint}
        return resolved[pkg]

    for k in raw_mats:
        resolve(k)

    # Keep only entries that have at least one texture or tint
    out = {k: v for k, v in resolved.items() if v["texs"] or v["tint"]}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2))
    print(f"Resolved {len(out)} materials with textures/tints -> {OUT}")

    mesh_mats = {}
    for mf in EX_ASSETS.rglob("*.materials.json"):
        rel = str(mf.relative_to(EX_ASSETS)).replace(".materials.json", "")
        if rel.startswith("TAT/Content/"):
            rel = rel[len("TAT/Content/") :]
        ue_mesh = "/Game/" + rel
        try:
            slots = json.loads(mf.read_text())
        except Exception:
            continue
        mesh_mats[ue_mesh] = [
            (s.get("material") or "").split(".")[0]
            for s in slots
            if isinstance(s, dict)
        ]
    OUT_MESH_MATS.write_text(json.dumps(mesh_mats, indent=2))
    print(f"Mapped {len(mesh_mats)} mesh material slot lists -> {OUT_MESH_MATS}")


if __name__ == "__main__":
    main()
