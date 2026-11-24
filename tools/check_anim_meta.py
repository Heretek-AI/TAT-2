#!/usr/bin/env python3
"""
Validate `game/data/generated/anims_meta.json` against the UE dumps.

This is a fail-closed gate, independent of the producer's bookkeeping:

  * every clip in `anims_manifest.json` has a metadata entry or a recorded
    warning that names it;
  * every metadata entry exists in the dumps with the same kind and play
    length, and the same authored notify/section counts;
  * notify times are within [0, length] and durations are non-negative;
  * montage sections are ordered, inside [0, length], and do not overlap;
  * the summary counts in `stats` match a fresh scan of `extracted/json`.

The scan here is deliberately a second implementation of the count logic, so
a producer bug cannot validate itself. Payload values are not re-derived (the
producer is the only place that flattens UE property shapes); the checker
verifies their presence only through the per-clip notify counts.

Exit code 0 means the metadata is present, complete and consistent. Any
failure prints `FAIL: ...` and exits 1.
"""

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_JSON = ROOT / "extracted" / "json"
MANIFEST = ROOT / "game" / "data" / "generated" / "anims_manifest.json"
META = ROOT / "game" / "data" / "generated" / "anims_meta.json"

SCHEMA = "tat2.anims_meta/1"
TIME_EPS = 1e-4


def _class_of(ref) -> str:
    if not isinstance(ref, dict):
        return ""
    obj_name = ref.get("ObjectName")
    if not isinstance(obj_name, str) or "'" not in obj_name:
        return ""
    return obj_name.split("'", 1)[0]


def _scan_dumps():
    """Fresh count/identity scan of every animation export in the dumps."""
    clips = {}
    notify_objects = 0
    for path in sorted(EX_JSON.rglob("*.json")):
        try:
            exports = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(exports, list):
            continue
        for export in exports:
            if isinstance(export, dict) and str(export.get("Type", "")).startswith(
                "AnimNotify"
            ):
                notify_objects += 1
        for export in exports:
            if not isinstance(export, dict):
                continue
            kind = export.get("Type")
            if kind not in ("AnimSequence", "AnimMontage"):
                continue
            name = export.get("Name")
            props = export.get("Properties")
            if not isinstance(name, str) or name == "" or not isinstance(props, dict):
                continue
            try:
                length = float(props.get("SequenceLength"))
            except (TypeError, ValueError):
                continue
            notifies = props.get("Notifies") or []
            if not isinstance(notifies, list):
                notifies = []
            sections = props.get("CompositeSections") or []
            if not isinstance(sections, list):
                sections = []
            clips[name] = {
                "kind": "sequence" if kind == "AnimSequence" else "montage",
                "length": length,
                "notifies": notifies,
                "sections": sections,
                "slots": [
                    str(track.get("SlotName"))
                    for track in (props.get("SlotAnimTracks") or [])
                    if isinstance(track, dict)
                    and isinstance(track.get("SlotName"), str)
                ],
                "source_file": str(path.relative_to(ROOT)),
            }
    return clips, notify_objects


def main() -> int:
    failures = []
    if not MANIFEST.is_file():
        print("FAIL: missing %s; run make anims first" % MANIFEST)
        return 1
    if not META.is_file():
        print("FAIL: missing %s; run python3 tools/parse_anim_meta.py" % META)
        return 1
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        meta = json.loads(META.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print("FAIL: cannot read manifest/meta JSON: %s" % exc)
        return 1

    entries = manifest.get("entries") if isinstance(manifest, dict) else None
    if not isinstance(entries, list):
        print("FAIL: %s has no entries list; regenerate with make anims" % MANIFEST)
        return 1
    manifest_names = [
        e["animation"]
        for e in entries
        if isinstance(e, dict) and isinstance(e.get("animation"), str)
    ]

    if not isinstance(meta, dict):
        print("FAIL: %s is not a JSON object" % META)
        return 1
    if meta.get("schema") != SCHEMA:
        failures.append(
            "schema: expected %r, found %r; regenerate with python3 tools/parse_anim_meta.py"
            % (SCHEMA, meta.get("schema"))
        )
    clips = meta.get("clips")
    stats = meta.get("stats")
    warnings = meta.get("warnings")
    if not isinstance(clips, dict):
        failures.append("clips: missing object")
        clips = {}
    if not isinstance(stats, dict):
        failures.append("stats: missing object")
        stats = {}
    if not isinstance(warnings, list) or not all(isinstance(w, str) for w in warnings):
        failures.append("warnings: expected a list of strings")
        warnings = []

    dump_clips, dump_notify_objects = _scan_dumps()

    # Coverage: every manifest clip has metadata or a named warning.
    covered = 0
    for name in manifest_names:
        if name in clips:
            covered += 1
            continue
        if any(name + ":" in warning for warning in warnings):
            continue
        failures.append(
            "coverage: manifest clip %r has no metadata entry and no recorded warning"
            % name
        )
    extra = sorted(set(clips) - set(manifest_names))
    for name in extra:
        failures.append(
            "coverage: metadata clip %r is not in anims_manifest.json" % name
        )

    # Per-clip identity and element counts.
    for name in sorted(clips):
        clip = clips[name]
        if not isinstance(clip, dict):
            failures.append("%s: clip entry is not an object" % name)
            continue
        dumped = dump_clips.get(name)
        if dumped is None:
            failures.append(
                "%s: clip has metadata but no AnimSequence/AnimMontage dump" % name
            )
            continue
        if clip.get("kind") != dumped["kind"]:
            failures.append(
                "%s: kind %r != dump %r" % (name, clip.get("kind"), dumped["kind"])
            )
        try:
            length = float(clip.get("length"))
        except (TypeError, ValueError):
            failures.append("%s: length is not numeric" % name)
            continue
        if abs(length - dumped["length"]) > 2e-6:
            failures.append(
                "%s: length %.6f != dump %.6f" % (name, length, dumped["length"])
            )
        notifies = clip.get("notifies")
        sections = clip.get("sections")
        slots = clip.get("slots")
        if not isinstance(notifies, list):
            failures.append("%s: notifies is not a list" % name)
            notifies = []
        if not isinstance(sections, list):
            failures.append("%s: sections is not a list" % name)
            sections = []
        if not isinstance(slots, list):
            failures.append("%s: slots is not a list" % name)
            slots = []
        if len(notifies) != len(dumped["notifies"]):
            failures.append(
                "%s: notify count %d != dump %d"
                % (name, len(notifies), len(dumped["notifies"]))
            )
        if len(sections) != len(dumped["sections"]):
            failures.append(
                "%s: section count %d != dump %d"
                % (name, len(sections), len(dumped["sections"]))
            )
        if sorted(slots) != sorted(dumped["slots"]):
            failures.append(
                "%s: slot names %r != dump %r" % (name, slots, dumped["slots"])
            )
        if not isinstance(clip.get("asset"), str) or not clip["asset"].startswith(
            "/Game/"
        ):
            failures.append("%s: asset is not a /Game/ package path" % name)
        source_file = clip.get("source_file")
        if not isinstance(source_file, str) or not (ROOT / source_file).is_file():
            failures.append(
                "%s: source_file is missing on disk: %r" % (name, source_file)
            )

        # Notify times within [0, length]; durations non-negative.
        for index, notify in enumerate(notifies):
            if not isinstance(notify, dict):
                failures.append("%s: notify[%d] is not an object" % (name, index))
                continue
            if not isinstance(notify.get("class"), str):
                failures.append("%s: notify[%d] class is not a string" % (name, index))
            if not isinstance(notify.get("name"), str) or notify["name"] == "":
                failures.append("%s: notify[%d] has no name" % (name, index))
            try:
                time = float(notify.get("time"))
                duration = float(notify.get("duration"))
            except (TypeError, ValueError):
                failures.append(
                    "%s: notify[%d] time/duration is not numeric" % (name, index)
                )
                continue
            if time < -TIME_EPS or time > length + TIME_EPS:
                failures.append(
                    "%s: notify[%d] time %.6f outside [0, %.6f]"
                    % (name, index, time, length)
                )
            if duration < 0.0:
                failures.append(
                    "%s: notify[%d] negative duration %.6f" % (name, index, duration)
                )
            if not isinstance(notify.get("payload"), dict):
                failures.append(
                    "%s: notify[%d] payload is not an object" % (name, index)
                )

        # Sections ordered, inside the clip, and non-overlapping.
        previous_end = 0.0
        for index, section in enumerate(sections):
            if not isinstance(section, dict):
                failures.append("%s: section[%d] is not an object" % (name, index))
                continue
            try:
                start = float(section.get("start"))
                end = float(section.get("end"))
            except (TypeError, ValueError):
                failures.append(
                    "%s: section[%d] start/end is not numeric" % (name, index)
                )
                continue
            if not isinstance(section.get("name"), str) or section["name"] == "":
                failures.append("%s: section[%d] has no name" % (name, index))
            if start < -TIME_EPS or end > length + TIME_EPS or end < start - TIME_EPS:
                failures.append(
                    "%s: section[%d] %r [%.6f, %.6f] outside [0, %.6f]"
                    % (name, index, section.get("name"), start, end, length)
                )
            if index > 0 and start < previous_end - TIME_EPS:
                failures.append(
                    "%s: section[%d] %r starts %.6f before previous end %.6f"
                    % (name, index, section.get("name"), start, previous_end)
                )
            previous_end = end

    # Summary counts must match the fresh dump scan.
    class_counts = Counter()
    montage_class_counts = Counter()
    name_only = 0
    notify_total = 0
    montage_notify_total = 0
    notify_clips = 0
    section_total = 0
    slot_counts = Counter()
    sequences = 0
    montages = 0
    for info in dump_clips.values():
        if info["kind"] == "sequence":
            sequences += 1
        else:
            montages += 1
        if info["notifies"]:
            notify_clips += 1
        notify_total += len(info["notifies"])
        if info["kind"] == "montage":
            montage_notify_total += len(info["notifies"])
        for event in info["notifies"]:
            if not isinstance(event, dict):
                continue
            notify_class = _class_of(
                event.get("Notify") or event.get("NotifyStateClass") or {}
            )
            if notify_class == "":
                name_only += 1
            else:
                class_counts[notify_class] += 1
                if info["kind"] == "montage":
                    montage_class_counts[notify_class] += 1
        section_total += len(info["sections"])
        for slot in info["slots"]:
            slot_counts[slot] += 1

    measured = {
        "clips": len(dump_clips),
        "sequences": sequences,
        "montages": montages,
        "clips_with_notifies": notify_clips,
        "notifies": notify_total,
        "name_only_notifies": name_only,
        "notify_classes": dict(sorted(class_counts.items())),
        "montage_notifies": montage_notify_total,
        "montage_notify_classes": dict(sorted(montage_class_counts.items())),
        "notify_objects": dump_notify_objects,
        "montage_sections": section_total,
        "montage_slots": dict(sorted(slot_counts.items())),
        "manifest_clips": len(manifest_names),
    }
    for key, value in measured.items():
        if stats.get(key) != value:
            failures.append(
                "stats.%s: %r != measured dump %r; regenerate with "
                "python3 tools/parse_anim_meta.py" % (key, stats.get(key), value)
            )
    if len(clips) != len(dump_clips):
        failures.append(
            "clips: %d entries != %d dumped animations" % (len(clips), len(dump_clips))
        )
    if stats.get("manifest_missing_meta") != 0:
        failures.append(
            "stats.manifest_missing_meta: %r != 0" % stats.get("manifest_missing_meta")
        )
    if covered != len(manifest_names):
        failures.append(
            "coverage: %d/%d manifest clips covered" % (covered, len(manifest_names))
        )

    print(
        "anim_meta: %d clips (%d sequences, %d montages), %d notifies "
        "(%d name-only) in %d clips, %d montage sections"
        % (
            measured["clips"],
            measured["sequences"],
            measured["montages"],
            measured["notifies"],
            measured["name_only_notifies"],
            measured["clips_with_notifies"],
            measured["montage_sections"],
        )
    )
    print(
        "classes: %s"
        % ", ".join("%s=%d" % kv for kv in measured["notify_classes"].items())
    )
    print(
        "slots: %s"
        % (", ".join("%s=%d" % kv for kv in measured["montage_slots"].items()) or "-")
    )
    print(
        "coverage: %d/%d manifest clips; warnings: %d"
        % (covered, len(manifest_names), len(warnings))
    )
    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        print("SUMMARY: fails=%d" % len(failures))
        return 1
    print("PASS: anims_meta matches the authored dumps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
