#!/usr/bin/env python3
"""Read-only proof: GLB primitive -> material mapping vs index-based binding.

Parses the GLB container and BIN index accessors with the standard library
only, prints per-primitive material/geometry facts, and compares them with:
  * the source UE sidecar ``<Mesh>.materials.json`` (slot order), and
  * ``game/data/generated/mesh_materials.json`` (index-based runtime binding).

Usage:
    python3 build/qa/glb_slots.py [GLB ...] [--out build/qa/glb_slots.json]
"""

from __future__ import annotations

import argparse
import difflib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXTRACTED = ROOT / "extracted" / "assets"
MESH_MATERIALS = ROOT / "game" / "data" / "generated" / "mesh_materials.json"
MATERIALS_DB = ROOT / "game" / "data" / "generated" / "materials.json"

CHUNK_JSON = 0x4E4F534A  # 'JSON'
CHUNK_BIN = 0x004E4942  # 'BIN\0'
COMPONENT = {5121: ("<B", 1), 5123: ("<H", 2), 5125: ("<I", 4)}
TRI_MODES = {4: "TRIANGLES", 5: "TRIANGLE_STRIP", 6: "TRIANGLE_FAN"}
MODE_NAMES = {
    0: "POINTS",
    1: "LINES",
    2: "LINE_LOOP",
    3: "LINE_STRIP",
    4: "TRIANGLES",
    5: "TRIANGLE_STRIP",
    6: "TRIANGLE_FAN",
}


def short_name(value: str) -> str:
    """UE object path -> material object name (drops the '.Object' suffix)."""
    return str(value).replace("\\", "/").rsplit("/", 1)[-1].split(".")[0]


def norm_name(value: str) -> str:
    """Comparison key; strips glTF duplicate suffixes such as '.001'."""
    name = short_name(value).lower()
    while "." in name and name.rsplit(".", 1)[-1].isdigit():
        name = name.rsplit(".", 1)[0]
    return name


def load_glb(path: Path):
    raw = path.read_bytes()
    if len(raw) < 12:
        raise ValueError("file shorter than GLB header")
    magic, version, declared = struct.unpack_from("<4sII", raw, 0)
    if magic != b"glTF":
        raise ValueError(f"bad magic {magic!r}")
    chunks = []
    off = 12
    while off + 8 <= len(raw):
        clen, ctype = struct.unpack_from("<II", raw, off)
        off += 8
        data = raw[off : off + clen]
        if len(data) != clen:
            raise ValueError(f"truncated chunk at byte {off - 8}")
        chunks.append((ctype, data))
        off += clen
    if off != len(raw):
        raise ValueError(f"{len(raw) - off} trailing bytes after chunks")
    json_chunk = next((d for t, d in chunks if t == CHUNK_JSON), None)
    if json_chunk is None:
        raise ValueError("missing JSON chunk")
    gltf = json.loads(json_chunk.rstrip(b" \t\r\n\0").decode("utf-8"))
    bin_chunk = next((d for t, d in chunks if t == CHUNK_BIN), b"")
    return gltf, bin_chunk, version, declared, chunks


def read_indices(gltf: dict, bin_data: bytes, accessor_index: int) -> list[int]:
    acc = gltf["accessors"][accessor_index]
    if acc.get("sparse"):
        raise ValueError("sparse index accessor unsupported")
    count = int(acc["count"])
    bv_index = acc.get("bufferView")
    if bv_index is None:
        return [0] * count
    if int(acc["componentType"]) not in COMPONENT:
        raise ValueError(f"bad index componentType {acc['componentType']}")
    fmt, elem_size = COMPONENT[int(acc["componentType"])]
    view = gltf["bufferViews"][int(bv_index)]
    base = int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
    stride = int(view.get("byteStride", elem_size))
    end = base + (count - 1) * stride + elem_size if count else base
    if end > len(bin_data):
        raise ValueError(
            f"accessor {accessor_index} overruns BIN ({end} > {len(bin_data)})"
        )
    return [
        struct.unpack_from(fmt, bin_data, base + i * stride)[0] for i in range(count)
    ]


def material_name(gltf: dict, material_index) -> str:
    if material_index is None:
        return "(none)"
    mats = gltf.get("materials") or []
    idx = int(material_index)
    if 0 <= idx < len(mats):
        return mats[idx].get("name") or f"material_{idx}"
    return f"(invalid material {idx})"


def primitive_stats(gltf: dict, bin_data: bytes, prim: dict) -> dict:
    mode = int(prim.get("mode", 4))
    attrs = prim.get("attributes") or {}
    vertex_count = None
    pos_acc = attrs.get("POSITION")
    if pos_acc is not None:
        vertex_count = int(gltf["accessors"][int(pos_acc)]["count"])
    if "indices" in prim:
        indices = read_indices(gltf, bin_data, int(prim["indices"]))
        source = "accessor"
    else:
        if vertex_count is None:
            indices = []
        else:
            indices = list(range(vertex_count))
        source = "non-indexed"
    distinct = len(set(indices))
    triangles = 0
    degenerate_tris = 0
    if mode in (4, 5, 6):
        if mode == 4:
            triangles = len(indices) // 3
            for i in range(0, triangles * 3, 3):
                if len(set(indices[i : i + 3])) < 3:
                    degenerate_tris += 1
        else:
            triangles = max(0, len(indices) - 2)
    out_of_range = 0
    if vertex_count is not None:
        out_of_range = sum(1 for i in indices if i < 0 or i >= vertex_count)
    degenerate = distinct < 3 or triangles == 0
    return {
        "mode": mode,
        "mode_name": MODE_NAMES.get(mode, f"MODE_{mode}"),
        "index_source": source,
        "index_count": len(indices),
        "distinct_indices": distinct,
        "vertex_count": vertex_count,
        "triangles": triangles,
        "degenerate_triangles": degenerate_tris,
        "out_of_range_indices": out_of_range,
        "degenerate": degenerate,
    }


def find_sidecar(glb: Path):
    """Return (chosen_sidecar_or_None, [all candidates]) using path mirroring."""
    rel = glb.resolve().relative_to(ROOT.resolve()).as_posix()
    mirrored = []
    if rel.startswith("game/assets/ue/Content/"):
        mirrored.append(
            EXTRACTED / (rel[len("game/assets/ue/Content/") :] + ".materials.json")
        )
    if rel.startswith("extracted/assets/TAT/Content/"):
        mirrored.append(
            EXTRACTED
            / (rel[len("extracted/assets/TAT/Content/") :] + ".materials.json")
        )
    if rel.startswith("extracted/assets/"):
        mirrored.append(
            EXTRACTED / (rel[len("extracted/assets/") :] + ".materials.json")
        )
    candidates = [p for p in mirrored if p.is_file()]
    stem = glb.stem
    for p in sorted(EXTRACTED.rglob(f"{stem}.materials.json")):
        if p not in candidates:
            candidates.append(p)
    return (candidates[0] if candidates else None), candidates


def key_from_sidecar(sidecar: Path) -> str | None:
    try:
        rel = sidecar.resolve().relative_to(EXTRACTED.resolve()).as_posix()
    except ValueError:
        return None
    rel = rel[: -len(".materials.json")]
    if rel.startswith("TAT/Content/"):
        rel = rel[len("TAT/Content/") :]
    return "/Game/" + rel


def build_name_index(materials_db: dict) -> dict:
    index = {}
    for key in materials_db:
        index.setdefault(norm_name(key), []).append(key)
    return index


def material_resolution(
    gltf: dict, sidecar_slots: list[dict], name_index: dict
) -> list[dict]:
    """Resolve each GLB material name to a full UE path via the mesh sidecar."""
    out = []
    for i, mat in enumerate(gltf.get("materials") or []):
        name = mat.get("name") or f"material_{i}"
        key = norm_name(name)
        sidecar_paths = sorted(
            {
                str(s["material_path"]).split(".")[0]
                for s in sidecar_slots
                if norm_name(s["material_name"]) == key
            }
        )
        expected = sidecar_paths[0] if len(sidecar_paths) == 1 else None
        db_matches = name_index.get(key, [])
        out.append(
            {
                "index": i,
                "name": name,
                "sidecar_paths": sidecar_paths,
                "db_matches": db_matches,
                "resolved_path": expected,
                "sidecar_unambiguous": len(sidecar_paths) == 1,
                "exact_name_match": any(
                    s["material_name"] == name for s in sidecar_slots
                ),
                "in_materials_db": expected in db_matches if expected else None,
            }
        )
    return out


def diff_sequences(source: list[str], glb: list[str]) -> dict:
    matcher = difflib.SequenceMatcher(None, source, glb, autojunk=False)
    common = {norm_name(x) for x in source} & {norm_name(x) for x in glb}
    source_common = [x for x in source if norm_name(x) in common]
    glb_common = [x for x in glb if norm_name(x) in common]
    replaced = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "replace":
            replaced.append(
                {
                    "source": source[i1:i2],
                    "glb": glb[j1:j2],
                    "same_width": (i2 - i1) == (j2 - j1),
                }
            )
    return {
        "dropped": [x for x in source if norm_name(x) not in common],
        "added": [x for x in glb if norm_name(x) not in common],
        "reordered": [norm_name(x) for x in source_common]
        != [norm_name(x) for x in glb_common],
        "replaced": replaced,
        "common_order_source": source_common,
        "common_order_glb": glb_common,
    }


def analyse(glb_path: Path, mesh_materials: dict, name_index: dict) -> dict:
    gltf, bin_data, version, declared, chunks = load_glb(glb_path)
    materials = gltf.get("materials") or []
    meshes = []
    for mesh_index, mesh in enumerate(gltf.get("meshes") or []):
        prims = []
        for prim_index, prim in enumerate(mesh.get("primitives") or []):
            stats = primitive_stats(gltf, bin_data, prim)
            stats.update(
                {
                    "primitive": prim_index,
                    "material_index": prim.get("material"),
                    "material_name": material_name(gltf, prim.get("material")),
                }
            )
            prims.append(stats)
        meshes.append(
            {
                "mesh_index": mesh_index,
                "mesh_name": mesh.get("name") or f"mesh_{mesh_index}",
                "primitive_count": len(prims),
                "primitives": prims,
            }
        )

    sidecar, sidecar_candidates = find_sidecar(glb_path)
    sidecar_slots = []
    sidecar_error = None
    sidecar_key = None
    if sidecar is not None:
        try:
            raw = json.loads(sidecar.read_text())
            if isinstance(raw, list):
                sidecar_slots = [
                    {
                        "slot": s.get("slot"),
                        "material_path": s.get("material"),
                        "material_name": short_name(s.get("material") or ""),
                    }
                    for s in raw
                    if isinstance(s, dict)
                ]
            else:
                sidecar_error = f"unexpected sidecar JSON shape: {type(raw).__name__}"
        except Exception as exc:  # report, never hide
            sidecar_error = f"{type(exc).__name__}: {exc}"
        sidecar_key = key_from_sidecar(sidecar)
    else:
        sidecar_error = "no matching .materials.json found"

    current = mesh_materials.get(sidecar_key) if sidecar_key else None
    current_key_used = sidecar_key if current is not None else None
    if current is None:
        matches = [
            k
            for k in mesh_materials
            if k.rsplit("/", 1)[-1].lower() == glb_path.stem.lower()
        ]
        if len(matches) == 1:
            current_key_used = matches[0]
            current = mesh_materials[matches[0]]

    comparisons = []
    for mesh in meshes:
        glb_sequence = [p["material_name"] for p in mesh["primitives"]]
        source_sequence = [s["material_name"] for s in sidecar_slots]
        entry = {
            "mesh_name": mesh["mesh_name"],
            "glb_sequence": glb_sequence,
            "source_sequence": source_sequence,
            "source_vs_glb": diff_sequences(source_sequence, glb_sequence),
        }
        if current is not None:
            entry["current_sequence"] = list(current)
            entry["current_vs_glb"] = diff_sequences(list(current), glb_sequence)
            entry["bindings"] = [
                {
                    "surface": i,
                    "current": current[i] if i < len(current) else None,
                    "glb": glb_sequence[i] if i < len(glb_sequence) else None,
                    "status": (
                        "MATCH"
                        if i < len(current)
                        and i < len(glb_sequence)
                        and norm_name(current[i]) == norm_name(glb_sequence[i])
                        else "MISMATCH"
                    ),
                }
                for i in range(max(len(current), len(glb_sequence)))
            ]
        comparisons.append(entry)

    return {
        "glb": str(glb_path.relative_to(ROOT)),
        "glb_version": version,
        "declared_length": declared,
        "actual_length": glb_path.stat().st_size,
        "chunks": [{"type": f"0x{t:08X}", "length": len(d)} for t, d in chunks],
        "material_count": len(materials),
        "materials": [
            {"index": i, "name": m.get("name") or f"material_{i}"}
            for i, m in enumerate(materials)
        ],
        "meshes": meshes,
        "sidecar": str(sidecar.relative_to(ROOT)) if sidecar else None,
        "sidecar_candidates": [str(p.relative_to(ROOT)) for p in sidecar_candidates],
        "sidecar_error": sidecar_error,
        "sidecar_key": sidecar_key,
        "sidecar_slots": sidecar_slots,
        "material_resolution": material_resolution(gltf, sidecar_slots, name_index),
        "current_key": current_key_used,
        "current_slots": list(current) if current is not None else None,
        "comparisons": comparisons,
    }


def print_report(results: list[dict]) -> None:
    for r in results:
        print("=" * 100)
        print(f"GLB: {r['glb']}")
        print(
            f"  version={r['glb_version']} declared={r['declared_length']} "
            f"actual={r['actual_length']} chunks={r['chunks']}"
        )
        print(f"  materials[{r['material_count']}]:")
        for m in r["materials"]:
            print(f"    [{m['index']}] {m['name']}")
        for mesh in r["meshes"]:
            print(
                f"  mesh[{mesh['mesh_index']}] {mesh['mesh_name']!r} "
                f"primitives={mesh['primitive_count']}"
            )
            print(
                "    prim  mat  material                    mode        idx  distinct  verts  tris  degT  range  degenerate"
            )
            for p in mesh["primitives"]:
                print(
                    f"    {p['primitive']:4d} {str(p['material_index']):>4}  "
                    f"{p['material_name'][:26]:<26} {p['mode_name']:<11} "
                    f"{p['index_count']:5d} {p['distinct_indices']:8d} "
                    f"{str(p['vertex_count']):>6} {p['triangles']:5d} "
                    f"{p['degenerate_triangles']:4d} {p['out_of_range_indices']:6d}  "
                    f"{'YES' if p['degenerate'] else 'no'}"
                )
        print(f"  sidecar: {r['sidecar']}  error={r['sidecar_error']}")
        if len(r["sidecar_candidates"]) > 1:
            print(f"  sidecar_candidates: {r['sidecar_candidates']}")
        print(f"  source key: {r['sidecar_key']}")
        if r["sidecar_slots"]:
            print("  source slots (sidecar order):")
            for i, s in enumerate(r["sidecar_slots"]):
                print(
                    f"    [{i}] slot={s['slot']!r} -> {s['material_name']}  ({s['material_path']})"
                )
        print("  GLB material name -> full path (via sidecar) -> materials.json:")
        for m in r["material_resolution"]:
            status = (
                "DB_OK"
                if m["in_materials_db"]
                else ("NOT_IN_DB" if m["in_materials_db"] is False else "UNRESOLVED")
            )
            print(
                f"    [{m['index']}] {m['name']} -> {m['resolved_path']} "
                f"exact={m['exact_name_match']} "
                f"sidecar_unambiguous={m['sidecar_unambiguous']} {status} "
                f"db_matches={m['db_matches']}"
            )
        print(f"  current mesh_materials key: {r['current_key']}")
        if r["current_slots"] is not None:
            print(f"  current slots: {r['current_slots']}")
        for c in r["comparisons"]:
            print(f"  --- comparison for mesh {c['mesh_name']!r}")
            print(f"  GLB material sequence:    {c['glb_sequence']}")
            print(f"  source material sequence: {c['source_sequence']}")
            d = c["source_vs_glb"]
            print(
                f"  source-vs-GLB: dropped={d['dropped']} added={d['added']} "
                f"reordered={d['reordered']}"
            )
            for rep in d["replaced"]:
                print(
                    f"    replaced source={rep['source']} glb={rep['glb']} same_width={rep['same_width']}"
                )
            if "current_sequence" in c:
                d2 = c["current_vs_glb"]
                print(
                    f"  current-vs-GLB: dropped={d2['dropped']} added={d2['added']} "
                    f"reordered={d2['reordered']}"
                )
                for rep in d2["replaced"]:
                    print(
                        f"    replaced current={rep['source']} glb={rep['glb']} same_width={rep['same_width']}"
                    )
                for b in c["bindings"]:
                    print(
                        f"    surface {b['surface']}: current={b['current']} "
                        f"glb={b['glb']} {b['status']}"
                    )
        print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glbs", nargs="*", help="GLB paths (default: six proof assets)")
    parser.add_argument("--out", help="write machine-readable JSON to this path")
    args = parser.parse_args()

    default_glbs = [
        ROOT / "game/assets/ue/Content/Developers/gjasp/SM_ThievesDen.glb",
        ROOT
        / "extracted/assets/TAT/Content/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA.glb",
        ROOT
        / "extracted/assets/TAT/Content/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA_Open.glb",
        ROOT
        / "extracted/assets/TAT/Content/Art/Environment/City/Facades/SM_FacadeLrgA_Base.glb",
        ROOT
        / "extracted/assets/TAT/Content/Art/Environment/City/Facades/SM_FacadeLrgA_TopA.glb",
        ROOT
        / "extracted/assets/TAT/Content/Art/Environment/City/Architecture/Roofs/RoofDetails/SM_RoofCity_WindowA.glb",
    ]
    paths = [Path(p) for p in args.glbs] if args.glbs else default_glbs
    missing = [str(p) for p in paths if not p.is_file()]
    if missing:
        for p in missing:
            print(f"MISSING GLB: {p}")
        return 2

    mesh_materials = json.loads(MESH_MATERIALS.read_text())
    name_index = build_name_index(json.loads(MATERIALS_DB.read_text()))
    results = [analyse(p, mesh_materials, name_index) for p in paths]
    print_report(results)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(results, indent=2) + "\n")
        print(f"WROTE {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
