#!/usr/bin/env python3
"""Convert CUE4Parse USD animation exports (.usda) to GLB via headless Blender.

Usage (single file):
    blender --background --python tools/usd_to_gltf.py -- <in.usda> <out.glb>

Usage (batch, preserving relative paths):
    blender --background --python tools/usd_to_gltf.py -- <src_dir> <dst_dir> [--filter REGEX]

Batch mode walks <src_dir> for *.usda files and writes *.glb under <dst_dir>,
mirroring the relative path. Prints a JSON summary line per file to stdout.
"""

import json
import math
import re
import sys
from pathlib import Path


def read_usd_header(usda_path: str) -> dict:
    """Parse the USDA header for its authored sample rate and timecode range."""
    header = {"tps": None, "start": None, "end": None}
    with open(usda_path, "r", errors="ignore") as fh:
        for i, line in enumerate(fh):
            if i > 25:
                break
            m = re.search(r"timeCodesPerSecond\s*=\s*([0-9.]+)", line)
            if m:
                header["tps"] = float(m.group(1))
                continue
            m = re.search(r"startTimeCode\s*=\s*(-?\d+)", line)
            if m:
                header["start"] = int(m.group(1))
                continue
            m = re.search(r"endTimeCode\s*=\s*(-?\d+)", line)
            if m:
                header["end"] = int(m.group(1))
    return header


def compute_render_fps(
    tps: float | None,
    start_timecode: int | None,
    end_timecode: int | None,
    frame_span: float | None,
) -> dict | None:
    """Scene fps/fps_base that makes the exported clip the authored length.

    The USD writer emits N = end - start + 1 samples at timeCodesPerSecond, so
    the authored length is L = N / tps. Blender maps every timecode to one
    frame and its glTF exporter writes seconds as frame / (fps * fps_base)
    (io_scene_gltf2/blender/exp/animation/keyframes.py), so a keyframe span of
    `frame_span` frames lasts frame_span / (fps * fps_base). Solving that for L
    gives the rate below; with startTimeCode == 0 the span is also the last
    exported frame, so the GLB's max input time is exactly L.

    Returns {"fps", "fps_base", "effective_fps", "authored_length"} or None
    when there is nothing to match: a zero or unknown keyframe span (the 23
    single-pose additive clips legitimately export duration 0) or a missing,
    non-positive or non-finite tps/timecode range.
    """
    if frame_span is None or not math.isfinite(frame_span) or frame_span <= 0:
        return None
    if (
        tps is None
        or not math.isfinite(tps)
        or tps <= 0
        or start_timecode is None
        or end_timecode is None
        or end_timecode < start_timecode
    ):
        return None
    authored_length = (end_timecode - start_timecode + 1) / tps
    effective_fps = frame_span / authored_length
    if not math.isfinite(effective_fps) or effective_fps <= 0:
        return None
    # Blender's render.fps is an integer; fps_base carries the fraction, and
    # the exporter multiplies the two.
    fps = max(1, round(effective_fps))
    return {
        "fps": fps,
        "fps_base": effective_fps / fps,
        "effective_fps": effective_fps,
        "authored_length": authored_length,
    }


def convert_one(in_usda: str, out_glb: str) -> dict:
    import bpy

    # Start clean.
    bpy.ops.wm.read_factory_settings(use_empty=True)

    bpy.ops.wm.usd_import(filepath=in_usda)
    imported = [o for o in bpy.context.scene.objects]
    armatures = [o for o in imported if o.type == "ARMATURE"]
    actions = [a for a in bpy.data.actions]

    # Make sure every action is reachable for the exporter: assign the first
    # action to each imported armature that has none, and stash all actions
    # so export keeps them.
    result = {
        "in": in_usda,
        "out": out_glb,
        "objects": len(imported),
        "armatures": len(armatures),
        "actions": [],
    }
    for arm in armatures:
        if arm.animation_data is None:
            arm.animation_data_create()
        if not arm.animation_data.action and actions:
            arm.animation_data.action = actions[0]

    for act in actions:
        # Blender 4.4+ uses layered actions (layers -> strips -> channelbags).
        channels = 0
        keypoints = 0
        f0 = f1 = None
        try:
            bags = []
            if hasattr(act, "layers"):
                for lay in act.layers:
                    for st in lay.strips:
                        bags.extend(list(st.channelbags))
            else:
                bags = [act]
            for bag in bags:
                for fc in bag.fcurves:
                    channels += 1
                    kps = fc.keyframe_points
                    keypoints += len(kps)
                    if len(kps):
                        xs = [kp.co.x for kp in kps]
                        f0 = min(xs) if f0 is None else min(f0, min(xs))
                        f1 = max(xs) if f1 is None else max(f1, max(xs))
        except Exception:
            pass
        result["actions"].append(
            {
                "name": act.name,
                "channels": channels,
                "keys": keypoints,
                "frame_range": [
                    float(f0) if f0 is not None else 0.0,
                    float(f1) if f1 is not None else 0.0,
                ],
            }
        )
    Path(out_glb).parent.mkdir(parents=True, exist_ok=True)
    # Preserve the authored clip length. Blender maps USD timecodes 1:1 to
    # frames and its glTF exporter writes seconds as frame/(fps*fps_base), so
    # fps = timeCodesPerSecond alone exports only (N-1)/N of the authored
    # length: the N samples span N-1 frame intervals. compute_render_fps()
    # solves for the rate that makes that span last the authored seconds;
    # zero-span single-pose clips keep the legacy sample-rate mapping (they
    # export duration 0 by design). Default 24fps would silently slow every
    # clip ~2.5x, so the USDA header is always the source of truth.
    header = read_usd_header(in_usda)
    tps = header["tps"]
    span = max(
        (a["frame_range"][1] - a["frame_range"][0] for a in result["actions"]),
        default=0.0,
    )
    retime = compute_render_fps(tps, header["start"], header["end"], span)
    if retime is not None:
        bpy.context.scene.render.fps = retime["fps"]
        bpy.context.scene.render.fps_base = retime["fps_base"]
        result["duration_retime"] = retime
    elif tps and tps > 0:
        fps_int = max(1, round(tps))
        bpy.context.scene.render.fps = fps_int
        bpy.context.scene.render.fps_base = tps / fps_int
    result["fps_applied"] = tps
    bpy.ops.export_scene.gltf(
        filepath=out_glb,
        export_format="GLB",
        export_animations=True,
        export_nla_strips=False,
        export_anim_single_armature=True,
        export_skins=True,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
    )
    result["glb_bytes"] = Path(out_glb).stat().st_size
    return result


def glb_animation_info(glb_path: Path) -> dict:
    """Read the GLB JSON chunk and summarize its animations (stdlib only)."""
    import struct

    with open(glb_path, "rb") as fh:
        magic = fh.read(4)
        if magic != b"glTF":
            raise ValueError(f"not a GLB file: {glb_path}")
        fh.read(8)
        chunk_len = struct.unpack("<I", fh.read(4))[0]
        fh.read(4)  # chunk type JSON
        doc = json.loads(fh.read(chunk_len).decode("utf-8"))
    anims = []
    for anim in doc.get("animations", []):
        duration = 0.0
        for samp in anim.get("samplers", []):
            inp = samp.get("input")
            if inp is None:
                continue
            try:
                acc = doc["accessors"][inp]
                duration = max(duration, float(acc.get("max", [0.0])[0]))
            except (IndexError, KeyError, TypeError, ValueError):
                continue
        anims.append(
            {
                "name": anim.get("name", ""),
                "channels": len(anim.get("channels", [])),
                "samplers": len(anim.get("samplers", [])),
                "duration": duration,
            }
        )
    return {"animations": anims, "nodes": len(doc.get("nodes", []))}


def write_manifest(converted: list, src: Path, dst: Path, manifest: Path) -> None:
    """Write source-package -> GLB manifest with animation stats."""
    entries = []
    for src_file, out_file, info in converted:
        src_rel = str(src_file.relative_to(src))
        glb_rel = str(out_file.relative_to(dst))
        try:
            glb = glb_animation_info(out_file)
        except Exception as e:  # noqa: BLE001 - record what we can
            glb = {"animations": [], "nodes": 0, "glb_error": str(e)}
        first = glb["animations"][0] if glb["animations"] else {}
        entries.append(
            {
                "source_package": src_rel,
                "glb": glb_rel,
                "animation": first.get("name", ""),
                "duration": first.get("duration", 0.0),
                "track_count": first.get("channels", 0),
                "samplers": first.get("samplers", 0),
                "actions": info.get("actions", []),
            }
        )
    ok = len(entries)
    fail = sum(1 for e in entries if not e["animation"])
    manifest.parent.mkdir(parents=True, exist_ok=True)
    with open(manifest, "w") as fh:
        json.dump(
            {
                "duration_mode": "authored",
                "ok": ok,
                "fail": fail,
                "total": len(converted),
                "entries": entries,
            },
            fh,
            indent=1,
        )
    print(json.dumps({"manifest": str(manifest), "ok": ok, "fail": fail}))


def main(argv: list) -> int:
    if len(argv) < 2:
        print(
            "usage: usd_to_gltf.py <in.usda|src_dir> <out.glb|dst_dir> [--filter REGEX]",
            file=sys.stderr,
        )
        return 2
    src = Path(argv[0])
    dst = Path(argv[1])
    filt = None
    if "--filter" in argv:
        filt = re.compile(argv[argv.index("--filter") + 1], re.IGNORECASE)
    manifest = None
    if "--manifest" in argv:
        manifest = Path(argv[argv.index("--manifest") + 1])

    if src.is_dir():
        files = sorted(src.rglob("*.usda"))
        if filt:
            files = [f for f in files if filt.search(str(f))]
        ok = fail = 0
        converted = []
        for f in files:
            rel = f.relative_to(src)
            out = dst / rel.with_suffix(".glb")
            try:
                info = convert_one(str(f), str(out))
                print(json.dumps(info))
                converted.append((f, out, info))
                ok += 1
            except Exception as e:  # noqa: BLE001 - batch must continue
                print(json.dumps({"in": str(f), "error": f"{type(e).__name__}: {e}"}))
                fail += 1
        print(
            json.dumps(
                {"batch_done": True, "ok": ok, "fail": fail, "total": len(files)}
            )
        )
        if manifest is not None:
            write_manifest(converted, src, dst, manifest)
        return 0 if fail == 0 else 1
    info = convert_one(str(src), str(dst))
    print(json.dumps(info, indent=2))
    return 0


if __name__ == "__main__":
    # Blender passes its own args before '--'; user args come after.
    args = sys.argv
    if "--" in args:
        args = args[args.index("--") + 1 :]
    else:
        args = args[1:]
    sys.exit(main(args))
