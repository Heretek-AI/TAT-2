#!/usr/bin/env python3
"""
Export authored UE AnimSequence / AnimMontage metadata for the Godot port.

The animation GLBs produced by `make anims` carry the sampled bone tracks but
no UE notify or montage-section data: CUE4Parse writes those into the raw
`extracted/json/**/AN_*.json` and `AM_*.json` package dumps. This producer
reads every `AnimSequence` / `AnimMontage` export under `extracted/json/` and
writes `game/data/generated/anims_meta.json`, keyed by the manifest clip
basename (`animation` in `anims_manifest.json`).

Everything emitted here is authored data from the dump:
  - `SequenceLength` (the montage/sequence play length);
  - every `FAnimNotifyEvent` in `Notifies`, with its notify class, display
    name, absolute trigger time, authored duration and the notify object's
    serialized `Properties` as `payload`;
  - montage `CompositeSections` (name, start, end derived from the next
    authored section start, or the play length);
  - montage `SlotAnimTracks` slot names.
No notify, section, time or payload is synthesized. A notify whose class is
only a name (UE's named montage notifies) is kept with an empty class string,
and a referenced object that the dump did not export leaves `payload` empty
plus a warning. Bytecode-only payloads cannot be recovered and are not claimed.

Link times follow UE's `FAnimLinkableElement::GetTime` contract: Absolute uses
`LinkValue`, Relative adds `SegmentBeginTime`, Proportional adds
`SegmentBeginTime + LinkValue * SegmentLength`. The shipped dumps are all
Absolute; the other branches exist so a future re-extract cannot silently
mis-time a notify.

Output is deterministic (sorted clip keys, stable notify order, sorted
warnings) so the audit baseline digest is meaningful.
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_JSON = ROOT / "extracted" / "json"
MANIFEST = ROOT / "game" / "data" / "generated" / "anims_manifest.json"
OUT = ROOT / "game" / "data" / "generated" / "anims_meta.json"

SCHEMA = "tat2.anims_meta/1"
ANIM_TYPES = ("AnimSequence", "AnimMontage")
TIME_EPS = 1e-4

OBJECT_NAME_RE = re.compile(r"^([^']+)'(.+)'$")


def _ref_class(ref) -> str:
    """UObject reference -> class name before the quote, or ""."""
    if not isinstance(ref, dict):
        return ""
    obj_name = ref.get("ObjectName")
    if not isinstance(obj_name, str) or "'" not in obj_name:
        return ""
    return obj_name.split("'", 1)[0]


def _ref_object_name(ref) -> str:
    """UObject reference -> the exported object name (outer export name)."""
    if not isinstance(ref, dict):
        return ""
    obj_name = ref.get("ObjectName")
    if not isinstance(obj_name, str):
        return ""
    match = OBJECT_NAME_RE.match(obj_name)
    if not match:
        return ""
    inner = match.group(2)
    # Subobject refs look like "Notify_0.RootMotionModifier_SkewWarp"; the
    # direct notify object is the outer export before the subobject dot.
    return inner.split(":", 1)[-1].split(".", 1)[0]


def _object_short_name(obj_name: str) -> str:
    """`AnimMontage'AN_X'` style ObjectName -> the quoted asset/subobject path."""
    match = OBJECT_NAME_RE.match(obj_name)
    return match.group(2) if match else obj_name


def _norm_payload_value(value, clip: str, key: str, warnings: list):
    """Serialized UE property value -> compact JSON, without inventing fields."""
    if isinstance(value, dict):
        tag = value.get("TagName")
        if isinstance(tag, str):
            return tag
        obj_name = value.get("ObjectName")
        if isinstance(obj_name, str):
            return _object_short_name(obj_name)
        out = {}
        for k in sorted(value):
            out[k] = _norm_payload_value(value[k], clip, key + "." + k, warnings)
        return out
    if isinstance(value, list):
        return [
            _norm_payload_value(v, clip, "%s[%d]" % (key, i), warnings)
            for i, v in enumerate(value)
        ]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    warnings.append(
        "%s: payload %s has unsupported serialized type %s; value dropped"
        % (clip, key, type(value).__name__)
    )
    return None


def _notify_time(event: dict):
    """UE FAnimLinkableElement::GetTime for an FAnimNotifyEvent, or None."""
    method = event.get("CachedLinkMethod") or event.get("LinkMethod")
    if not isinstance(method, str):
        method = "EAnimLinkMethod::Absolute"
    try:
        link = float(event.get("LinkValue", 0.0))
        begin = float(event.get("SegmentBeginTime", 0.0) or 0.0)
        segment = float(event.get("SegmentLength", 0.0) or 0.0)
    except (TypeError, ValueError):
        return None
    if method.endswith("::Absolute"):
        return link
    if method.endswith("::Relative"):
        return begin + link
    if method.endswith("::Proportional"):
        return begin + link * segment
    return None


def _notifies(props: dict, length: float, objects: dict, clip: str, warnings: list):
    out = []
    raw = props.get("Notifies") or []
    if not isinstance(raw, list):
        warnings.append("%s: Notifies is not a list; skipped" % clip)
        return out
    for index, event in enumerate(raw):
        if not isinstance(event, dict):
            warnings.append("%s: notify[%d] is not an object; skipped" % (clip, index))
            continue
        ref = event.get("Notify") or event.get("NotifyStateClass") or {}
        notify_class = _ref_class(ref)
        notify_name = event.get("NotifyName")
        if not isinstance(notify_name, str) or notify_name == "":
            notify_name = _ref_object_name(ref)
        if notify_class == "" and notify_name == "":
            warnings.append(
                "%s: notify[%d] has neither class nor name; skipped" % (clip, index)
            )
            continue
        time = _notify_time(event)
        if time is None:
            warnings.append(
                "%s: notify %r has no resolvable time; skipped"
                % (clip, notify_name or notify_class)
            )
            continue
        if time < -TIME_EPS or time > length + TIME_EPS:
            warnings.append(
                "%s: notify %r time %.6f outside [0, %.6f]"
                % (clip, notify_name or notify_class, time, length)
            )
        payload = {}
        obj = objects.get(_ref_object_name(ref))
        if notify_class != "" and obj is None:
            warnings.append(
                "%s: notify %r (%s) references an object the dump did not export; payload omitted"
                % (clip, notify_name or notify_class, notify_class)
            )
        elif obj is not None:
            obj_props = obj.get("Properties")
            if isinstance(obj_props, dict):
                for key in sorted(obj_props):
                    value = _norm_payload_value(
                        obj_props[key],
                        clip,
                        "notify %s %s" % (notify_name, key),
                        warnings,
                    )
                    if value is not None or obj_props[key] is None:
                        payload[key] = value
        try:
            duration = float(event.get("duration", 0.0) or 0.0)
        except (TypeError, ValueError):
            duration = 0.0
        out.append(
            {
                "name": notify_name,
                "class": notify_class,
                "time": round(time, 6),
                "duration": round(duration, 6),
                "payload": payload,
            }
        )
    return out


def _sections(props: dict, length: float, clip: str, warnings: list):
    """Montage sections, ordered by authored start; end is the next start."""
    raw = props.get("CompositeSections") or []
    if not isinstance(raw, list):
        warnings.append("%s: CompositeSections is not a list; skipped" % clip)
        return []
    entries = []
    for index, section in enumerate(raw):
        if not isinstance(section, dict):
            warnings.append("%s: section[%d] is not an object; skipped" % (clip, index))
            continue
        name = section.get("SectionName")
        if not isinstance(name, str) or name == "":
            warnings.append("%s: section[%d] has no name; skipped" % (clip, index))
            continue
        value = section.get("LinkValue", section.get("SegmentBeginTime", 0.0))
        try:
            start = float(value)
        except (TypeError, ValueError):
            warnings.append(
                "%s: section %r has no resolvable start; skipped" % (clip, name)
            )
            continue
        if start < -TIME_EPS or start > length + TIME_EPS:
            warnings.append(
                "%s: section %r start %.6f outside [0, %.6f]"
                % (clip, name, start, length)
            )
            continue
        entries.append((start, index, name))
    entries.sort(key=lambda e: (e[0], e[1]))
    out = []
    for i, (start, _index, name) in enumerate(entries):
        end = entries[i + 1][0] if i + 1 < len(entries) else length
        start = min(max(start, 0.0), length)
        end = min(max(end, start), length)
        out.append({"name": name, "start": round(start, 6), "end": round(end, 6)})
    return out


def _slots(props: dict):
    out = []
    seen = set()
    raw = props.get("SlotAnimTracks") or []
    if not isinstance(raw, list):
        return out
    for track in raw:
        if not isinstance(track, dict):
            continue
        name = track.get("SlotName")
        if isinstance(name, str) and name != "" and name not in seen:
            seen.add(name)
            out.append(name)
    return out


def _scan_dumps():
    """Every animation export plus the notify objects exported beside it."""
    clips = {}
    notify_objects = 0
    warnings = []
    for path in sorted(EX_JSON.rglob("*.json")):
        try:
            exports = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            warnings.append(
                "%s: cannot parse dump (%s)" % (path.relative_to(ROOT), exc)
            )
            continue
        if not isinstance(exports, list):
            continue
        objects = {}
        for export in exports:
            if not isinstance(export, dict):
                continue
            name = export.get("Name")
            if isinstance(name, str):
                objects[name] = export
            if str(export.get("Type", "")).startswith("AnimNotify"):
                notify_objects += 1
        for export in exports:
            if not isinstance(export, dict):
                continue
            kind = export.get("Type")
            if kind not in ANIM_TYPES:
                continue
            name = export.get("Name")
            if not isinstance(name, str) or name == "":
                warnings.append(
                    "%s: animation export has no name; skipped" % path.relative_to(ROOT)
                )
                continue
            if name in clips:
                warnings.append(
                    "%s: duplicate animation name %r; first dump kept"
                    % (path.relative_to(ROOT), name)
                )
                continue
            props = export.get("Properties")
            if not isinstance(props, dict):
                warnings.append(
                    "%s: animation %r has no Properties; skipped"
                    % (path.relative_to(ROOT), name)
                )
                continue
            try:
                length = float(props.get("SequenceLength"))
            except (TypeError, ValueError):
                warnings.append(
                    "%s: animation %r has no SequenceLength; skipped"
                    % (path.relative_to(ROOT), name)
                )
                continue
            if length <= 0.0:
                warnings.append(
                    "%s: animation %r has non-positive length %.6f"
                    % (path.relative_to(ROOT), name, length)
                )
            asset = export.get("Package")
            if not isinstance(asset, str) or asset == "":
                asset = "/Game/" + str(path.relative_to(EX_JSON).with_suffix(""))
                warnings.append(
                    "%s: animation %r has no Package; asset path derived"
                    % (path.relative_to(ROOT), name)
                )
            clips[name] = {
                "asset": asset,
                "kind": "sequence" if kind == "AnimSequence" else "montage",
                "length": round(length, 6),
                "notifies": _notifies(props, length, objects, name, warnings),
                "sections": _sections(props, length, name, warnings)
                if kind == "AnimMontage"
                else [],
                "slots": _slots(props) if kind == "AnimMontage" else [],
                "source_file": str(path.relative_to(ROOT)),
            }
    return clips, notify_objects, warnings


def _manifest_names():
    if not MANIFEST.is_file():
        return None
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    entries = data.get("entries") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        return None
    names = []
    for entry in entries:
        if isinstance(entry, dict) and isinstance(entry.get("animation"), str):
            names.append(entry["animation"])
    return names


def _stats(clips: dict, notify_objects: int, manifest_names, warnings: list) -> dict:
    class_counts = Counter()
    montage_class_counts = Counter()
    name_only = 0
    notifies = 0
    montage_notifies = 0
    clips_with_notifies = 0
    sections = 0
    slots = Counter()
    for clip in clips.values():
        if clip["notifies"]:
            clips_with_notifies += 1
        for notify in clip["notifies"]:
            notifies += 1
            if clip["kind"] == "montage":
                montage_notifies += 1
            if notify["class"] == "":
                name_only += 1
            else:
                class_counts[notify["class"]] += 1
                if clip["kind"] == "montage":
                    montage_class_counts[notify["class"]] += 1
        sections += len(clip["sections"])
        for slot in clip["slots"]:
            slots[slot] += 1
    sequences = sum(1 for c in clips.values() if c["kind"] == "sequence")
    montages = sum(1 for c in clips.values() if c["kind"] == "montage")
    stats = {
        "clips": len(clips),
        "sequences": sequences,
        "montages": montages,
        "clips_with_notifies": clips_with_notifies,
        "notifies": notifies,
        "name_only_notifies": name_only,
        "notify_classes": dict(sorted(class_counts.items())),
        "montage_notifies": montage_notifies,
        "montage_notify_classes": dict(sorted(montage_class_counts.items())),
        "notify_objects": notify_objects,
        "montage_sections": sections,
        "montage_slots": dict(sorted(slots.items())),
    }
    if manifest_names is not None:
        manifest_set = set(manifest_names)
        missing = sorted(manifest_set - set(clips))
        extra = sorted(set(clips) - manifest_set)
        for name in missing:
            warnings.append("%s: manifest clip has no animation dump metadata" % name)
        for name in extra:
            warnings.append("%s: animation dump metadata has no manifest clip" % name)
        stats["manifest_clips"] = len(manifest_names)
        stats["manifest_missing_meta"] = len(missing)
        stats["manifest_extra_meta"] = len(extra)
    return stats


def main() -> None:
    if not EX_JSON.is_dir():
        raise SystemExit("missing extracted JSON dumps at %s" % EX_JSON)
    clips, notify_objects, warnings = _scan_dumps()
    if not clips:
        raise SystemExit("no AnimSequence/AnimMontage exports found under %s" % EX_JSON)
    manifest_names = _manifest_names()
    if manifest_names is None:
        warnings.append(
            "anims_manifest.json missing or malformed; manifest coverage not checked"
        )
    stats = _stats(clips, notify_objects, manifest_names, warnings)

    data = {
        "schema": SCHEMA,
        "stats": stats,
        "warnings": sorted(set(warnings)),
        "clips": {name: clips[name] for name in sorted(clips)},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    print("Wrote %s" % OUT.relative_to(ROOT))
    print(
        "clips: %d (%d sequences, %d montages)"
        % (stats["clips"], stats["sequences"], stats["montages"])
    )
    print(
        "notifies: %d (%d name-only) across %d clips"
        % (stats["notifies"], stats["name_only_notifies"], stats["clips_with_notifies"])
    )
    print(
        "montage sections: %d; slots: %s"
        % (
            stats["montage_sections"],
            ", ".join("%s=%d" % kv for kv in stats["montage_slots"].items()) or "-",
        )
    )
    print("notify classes:")
    for name, count in stats["notify_classes"].items():
        print("  %5d %s" % (count, name))
    print("warnings: %d" % len(data["warnings"]))
    for line in data["warnings"][:20]:
        print("  warning: %s" % line)
    if len(data["warnings"]) > 20:
        print("  ... %d more" % (len(data["warnings"]) - 20))


if __name__ == "__main__":
    main()
