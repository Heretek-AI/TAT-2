#!/usr/bin/env python3
"""Parse the extracted Wwise control plane into ``audio_wwise.json``.

Reads (read-only, all under the repository root):
    extracted/json/Audio/WwiseSharedAssetLibrary.json
        Cooked Wwise soundbanks: 8,593 packaged files, 3,543 of them carrying
        ``BulkData.Hierarchies``.  This is the only source for bus topology,
        attenuation curves, effects (FxShareSet/FxCustom) and the event ->
        action -> object graph.
    extracted/audio-meta/Audio/Events/**/*.json
        1,298 UE asset dumps, 1,296 of them ``AkAudioEvent`` (the other two are
        ``AkSwitchValue``).  They are the only source of event *names* plus
        ``MaxAttenuationRadius`` (centimetres), ``MinimumDuration``,
        ``MaximumDuration`` and ``IsInfinite``.
    extracted/audio-meta/Audio/Reverb/**/*.json
        16 ``AkAuxBus`` dumps.  The only authored bus names in the whole
        extraction, and the only per-bus impulse-response names.
    extracted/json/Audio/InitBank.json
        ``InitBankCookedData.Media``: MediaId -> impulse DebugName.
    extracted/json/WwiseAudio/DefaultGeometrySurfacePropertiesTable.json
    extracted/json/WwiseAudio/DefaultReverbAssignmentTable.json
        Transmission-loss rows and decay -> aux-bus rows.
    extracted/json/Maps/**/*Audio*.json (+ the startscreen dump, which does not
    match the glob: Maps/Menus/MainMenu/BeautifulCorner_Startscreen_P.json)
        Placed actors: ``AkAmbientSound`` (event = ``ActorLabel``),
        ``TATAudioRoomComponent`` (room bed, keyed by its ``Outer`` volume) and
        ``AkComponent``/``TATCCAudioComponent`` component events.
    game/data/generated/levels/**/*.tatlevel.json
        Read-only, for actor positions by name.  Never written.

Produces exactly one file: ``<--out>/audio_wwise.json`` (schema
``tat2.audio_wwise/1``).  ``--out`` is required; nothing is written outside it.

Deliberately does NOT:
    * decode or copy media.  ``fx[].ir_name`` names the authored convolution
      impulse, but the samples live in PLUG chunks this producer never reads.
    * regenerate, extend or touch ``game/data/generated/``.  Positions are read
      from the generated level tables, never produced into them.
    * re-derive game content (contracts, loot, dialogue).  VO "subtitles" are a
      functional parse of the authored event name, never authored text: no VO
      text exists anywhere in the extraction.
    * take metadata from an audio playback library.  Every number comes from
      the files above.

Two traps this file exists to handle:

1. Per-bank duplication.  A Wwise object is embedded in every soundbank that
   uses it, so 28,202 hierarchy entries are only 18,355 distinct objects and the
   entry count is *not* a count of anything authored.  Everything here
   de-duplicates on ``(Type, Id)`` first; the per-bank copies differ only in
   their local ``ChildIds`` (verified while loading: parent, bus override and
   prop bundle agree across every copy), so the surviving copy is safe for the
   parent walk.

2. Float-as-u32 ids.  The exporter serialised integer ids that sit in ``Props``
   as IEEE-754 floats, so a reference must be recovered from the bit pattern::

       as_u32(7.017046e-20) == 530952049   # a real Attenuation id

   ``int(7.017046e-20)`` is ``0`` and silently loses the reference.  This
   applies to prop id 75 (attenuation) on every object in the parent walk.

Determinism: sorted keys, sorted arrays, rounded floats, no timestamps, no host
paths.  Two runs on the same extraction are byte-identical.  ``--check`` re-reads
an emitted file, asserts the verified invariant table (counts, bus parents,
attenuation references, room-bed/emitter split, canonical bytes) and exits
non-zero on any drift.

Event routing: an event's bus and attenuation come from its first ``Play``
action (or its first action when it has no ``Play``), so the Play and Stop
actions of one event can never disagree.  A prop-75 reference that does not name
one of the 23 extracted attenuations becomes ``null`` rather than a dangling id
the runtime cannot resolve.

Event join: the bank stores no event name at all, so a dump is joined to its
bank Event by ``EventId`` and every join is verified against the packaged-file
``Hash`` (1,296/1,296).  The dump's ``Package`` basename, ``Name`` and SoundBank
``DebugName`` agree except for 10 events whose soundbank is forwarded to another
event; those are listed in ``warnings``.

Exit codes: 0 success, 1 ``--check`` mismatch, 2 missing/unreadable source.
"""

import argparse
import json
import os
import re
import struct
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK_PATH = ROOT / "extracted" / "json" / "Audio" / "WwiseSharedAssetLibrary.json"
EVENTS_DIR = ROOT / "extracted" / "audio-meta" / "Audio" / "Events"
REVERB_DIR = ROOT / "extracted" / "audio-meta" / "Audio" / "Reverb"
INIT_BANK_PATH = ROOT / "extracted" / "json" / "Audio" / "InitBank.json"
SURFACE_TABLE_PATH = (
    ROOT
    / "extracted"
    / "json"
    / "WwiseAudio"
    / "DefaultGeometrySurfacePropertiesTable.json"
)
REVERB_TABLE_PATH = (
    ROOT / "extracted" / "json" / "WwiseAudio" / "DefaultReverbAssignmentTable.json"
)
MAPS_DIR = ROOT / "extracted" / "json" / "Maps"
STARTSCREEN_DUMP = (
    MAPS_DIR / "Menus" / "MainMenu" / "BeautifulCorner_Startscreen_P.json"
)
LEVELS_DIR = ROOT / "game" / "data" / "generated" / "levels"

OUT_NAME = "audio_wwise.json"
SCHEMA = "tat2.audio_wwise/1"

# The four *_Audio dumps that carry AkAmbientSound actors, plus the startscreen.
# Building_Guildhall_POI_Audio and ThievesDen_Audio match the glob but place no
# ambience emitter (ThievesDen has a single room bed).
EMITTER_DUMPS = {
    "Guildhall_Audio": 34,
    "FTUE_Audio": 27,
    "OldManor_Audio_Ext": 15,
    "OldManor_Audio": 2,
}
STARTSCREEN_EMITTERS = 12
ROOM_BEDS_IN_AUDIO_DUMPS = 128
ROOM_BEDS_ON_STARTSCREEN = 8
MUSIC_SWITCH_CONTAINERS = 2
TRANSMISSION_LOSS_ROWS = 31
REVERB_ASSIGNMENT_ROWS = 4

# Wwise object types.  Only the ones the walk needs are looked up by bare id.
NODE_TYPES = frozenset(
    {
        "RandomSequenceContainer",
        "SwitchContainer",
        "ActorMixer",
        "LayerContainer",
        "SoundSfxVoice",
        "MusicTrack",
        "MusicSegment",
        "MusicRandomSequenceContainer",
        "MusicSwitchContainer",
    }
)

# AkPropID values observed on AudioBus/AuxiliaryBus.  Anything else is opaque:
# the extraction does not say what it means, so it is emitted verbatim by id.
BUS_PROP_VOLUME = 0
BUS_PROP_HPF = 4
BUS_PROP_LPF = 5
PROP_ATTENUATION = 75

MAX_PARENT_HOPS = 40

VO_PREFIX = "Play_VO_"
MUSIC_PLAY_PREFIX = "Play_Mus_"
MUSIC_STOP_PREFIX = "Stop_Mus_"
MUSIC_MUTE_PREFIX = "Mute_Music"
MUSIC_UNMUTE_PREFIX = "UnMute_Music"

# Verified counts (T03 integrator, 2026-11-24), plus the emitters/room-beds
# correction.  These are what --check enforces; a drift means the extraction or
# the producer changed and the runtime contract must be re-verified.
EXPECTED_COUNTS = {
    "bank_packaged_files": 8593,
    "bank_files_with_hierarchies": 3543,
    "objects_unique": 18355,
    "objects_entries": 28202,
    "buses": 130,
    "audio_buses": 91,
    "aux_buses": 39,
    "named_buses": 16,
    "fx_sharesets": 46,
    "fx_custom": 199,
    "attenuations": 23,
    "events_total": 3544,
    "events_ue_dumps": 1296,
    "events_play": 3228,
    "events_with_bus": 1757,
    "events_with_attenuation": 1580,
    "events_2d": 227,
    "music_play_events": 23,
    "music_segments": 188,
    "music_tracks": 235,
    "vo_events": 645,
    "emitters": 90,
    "room_beds": 136,
}

_ABS_PATH_RE = re.compile(r"^(?:/home/|/tmp/|/Users/|/var/|/root/|[A-Za-z]:[\\/])")


class SourceError(RuntimeError):
    """A required extracted input is missing or unreadable (exit code 2)."""


def rel(path):
    """Repository-relative POSIX path for messages and the sources block.

    ``Path.resolve()`` is deliberately avoided: in a remediation worktree
    ``extracted/`` (and ``game/data/generated/``) are symlinks into the main
    checkout, so resolving would leak an absolute host path into the output.
    """
    absolute = Path(os.path.abspath(path))
    try:
        return absolute.relative_to(ROOT).as_posix()
    except ValueError:
        return absolute.as_posix()


def read_json(path):
    try:
        with path.open("rb") as handle:
            return json.load(handle)
    except FileNotFoundError as exc:
        raise SourceError(f"{rel(path)}: missing") from exc
    except (OSError, ValueError) as exc:
        raise SourceError(f"{rel(path)}: unreadable ({exc})") from exc


def as_u32(value):
    """Recover a u32 id from the exporter's float-encoded IEEE-754 bit pattern."""
    return struct.unpack("<I", struct.pack("<f", float(value)))[0]


def as_id(value):
    """Normalise a JSON integer id that may be signed int32 (reverb dumps)."""
    return int(value) & 0xFFFFFFFF


def base_params(data):
    """Return the parent/props block of a sound object.

    Containers keep it under ``BaseParams``; music objects (tracks, segments,
    switch containers) keep it under ``ContainerHierarchy``.
    """
    return data.get("BaseParams") or data.get("ContainerHierarchy") or {}


def ref_name(ref):
    """Return the bare name inside ``{"ObjectName": "Klass'/path/Name'"}``."""
    if not isinstance(ref, dict):
        return None
    name = ref.get("ObjectName") or ""
    match = re.match(r"[A-Za-z0-9_]+'(.*)'$", name)
    return match.group(1) if match else (name or None)


def short_name(ref):
    """Return the last path segment of a ``ref_name`` result."""
    name = ref_name(ref)
    return name.rsplit(".", 1)[-1] if name else None


def load_bank():
    """Load the shared asset library and de-duplicate it on ``(Type, Id)``."""
    library = read_json(BANK_PATH)
    try:
        packaged = library[0]["CookedData"]["PackagedFiles"]
    except (IndexError, KeyError, TypeError) as exc:
        raise SourceError(f"{rel(BANK_PATH)}: not a Wwise asset library") from exc

    entries = Counter()
    objects = {}
    signatures = {}
    conflicts = []
    event_hashes = {}
    files_with_hierarchies = 0
    for packaged_file in packaged:
        hierarchies = (packaged_file.get("BulkData") or {}).get("Hierarchies") or []
        if hierarchies:
            files_with_hierarchies += 1
        for hierarchy in hierarchies:
            obj_type = hierarchy.get("Type")
            key = (obj_type, str(hierarchy.get("Id")))
            entries[obj_type] += 1
            if obj_type == "Event" and int(key[1]) not in event_hashes:
                # The packaged file that owns an Event hierarchy is that event's
                # own soundbank; the UE dump repeats this Hash, which is what
                # proves the name join.
                event_hashes[int(key[1])] = packaged_file.get("Hash")
            params = base_params(hierarchy.get("Data") or {})
            signature = json.dumps(
                {
                    "parent": params.get("DirectParentId"),
                    "bus": params.get("OverrideBusId"),
                    "props": (params.get("PropBundle") or {}).get("Props") or [],
                },
                sort_keys=True,
            )
            if key in objects:
                # A later soundbank embedding the same object.  Only a change in
                # the fields the parent walk uses would make the first copy
                # unsafe; ChildIds legitimately differ per bank.
                if signatures[key] != signature:
                    conflicts.append(key)
                continue
            objects[key] = hierarchy
            signatures[key] = signature

    nodes = {}
    id_collisions = []
    for (obj_type, obj_id), hierarchy in objects.items():
        if obj_type not in NODE_TYPES:
            continue
        numeric = int(obj_id)
        if numeric in nodes:
            id_collisions.append(numeric)
            continue
        nodes[numeric] = hierarchy

    return {
        "packaged_files": len(packaged),
        "files_with_hierarchies": files_with_hierarchies,
        "entries": entries,
        "objects": objects,
        "nodes": nodes,
        "conflicts": conflicts,
        "id_collisions": id_collisions,
        "event_hashes": event_hashes,
    }


def load_events():
    """Load UE AkAudioEvent dumps keyed by EventId."""
    if not EVENTS_DIR.is_dir():
        raise SourceError(f"{rel(EVENTS_DIR)}: missing")
    dumps = {}
    files = sorted(EVENTS_DIR.rglob("*.json"))
    switch_values = 0
    name_mismatches = 0
    debug_name_mismatches = 0
    duplicate_ids = []
    for path in files:
        payload = read_json(path)
        entries = payload if isinstance(payload, list) else [payload]
        for entry in entries:
            if entry.get("Type") != "AkAudioEvent":
                switch_values += 1
                continue
            name = entry.get("Name")
            package = entry.get("Package") or ""
            if package.rsplit("/", 1)[-1] != name:
                name_mismatches += 1
            cooked = entry.get("EventCookedData") or {}
            languages = cooked.get("EventLanguageMap") or []
            event_id = None
            media_count = 0
            bank_debug_names = []
            bank_hashes = []
            for language in languages:
                value = language.get("Value") or {}
                if event_id is None:
                    event_id = value.get("EventId")
                media_count += len(value.get("Media") or [])
                for bank in value.get("SoundBanks") or []:
                    bank_debug_names.append(bank.get("DebugName"))
                    bank_hashes.append((bank.get("PackagedFile") or {}).get("Hash"))
            if event_id is None:
                continue
            if any(debug and debug != name for debug in bank_debug_names):
                debug_name_mismatches += 1
            if event_id in dumps:
                duplicate_ids.append(event_id)
                continue
            dumps[event_id] = {
                "name": name,
                "media_count": media_count,
                "max_radius_cm": entry.get("MaxAttenuationRadius"),
                "min_duration_s": entry.get("MinimumDuration"),
                "max_duration_s": entry.get("MaximumDuration"),
                "is_infinite": entry.get("IsInfinite"),
                "bank_debug_names": bank_debug_names,
                "bank_hashes": bank_hashes,
            }
    return {
        "files": len(files),
        "switch_values": switch_values,
        "name_mismatches": name_mismatches,
        "debug_name_mismatches": debug_name_mismatches,
        "duplicate_ids": duplicate_ids,
        "dumps": dumps,
    }


def load_reverb():
    """Load the 16 AkAuxBus dumps: the only authored bus names."""
    if not REVERB_DIR.is_dir():
        raise SourceError(f"{rel(REVERB_DIR)}: missing")
    buses = []
    for path in sorted(REVERB_DIR.rglob("*.json")):
        payload = read_json(path)
        entries = payload if isinstance(payload, list) else [payload]
        for entry in entries:
            cooked = entry.get("AuxBusCookedData") or {}
            languages = cooked.get("AuxBusLanguageMap") or []
            if not languages:
                continue
            value = languages[0].get("Value") or {}
            media = value.get("Media") or []
            buses.append(
                {
                    "name": value.get("DebugName") or entry.get("Name"),
                    "id": as_id(value.get("AuxBusId")),
                    "ir_name": media[0].get("DebugName") if media else None,
                    "max_radius_cm": entry.get("MaxAttenuationRadius"),
                }
            )
    return buses


def load_init_bank():
    """Return MediaId -> impulse DebugName from the init bank."""
    payload = read_json(INIT_BANK_PATH)
    entries = payload if isinstance(payload, list) else [payload]
    if not entries:
        raise SourceError(f"{rel(INIT_BANK_PATH)}: empty")
    cooked = entries[0].get("InitBankCookedData") or {}
    names = {}
    for media in cooked.get("Media") or []:
        media_id = media.get("MediaId")
        if media_id is not None:
            names[media_id] = media.get("DebugName")
    return names


def load_table(path):
    """Return the ``Rows`` mapping of a UE DataTable dump."""
    payload = read_json(path)
    entries = payload if isinstance(payload, list) else [payload]
    if not entries:
        raise SourceError(f"{rel(path)}: empty")
    rows = entries[0].get("Rows")
    if not isinstance(rows, dict):
        raise SourceError(f"{rel(path)}: no Rows table")
    return rows


def resolve_reference(reference, nodes, bus_ids, attenuation_ids):
    """Walk ``DirectParentId`` and return (bus, attenuation, invalid_attenuation).

    The first ``OverrideBusId`` that names a bus wins; the first prop id 75 wins
    for attenuation (a dangling id yields ``None`` rather than an unknown id).
    """
    bus = None
    attenuation = None
    dangling = False
    att_seen = False
    current = reference
    seen = set()
    hops = 0
    while current and hops < MAX_PARENT_HOPS and current not in seen:
        seen.add(current)
        hops += 1
        obj = nodes.get(current)
        if obj is None:
            break
        params = base_params(obj.get("Data") or {})
        override = params.get("OverrideBusId")
        if bus is None and isinstance(override, int) and override in bus_ids:
            bus = override
        if not att_seen:
            for prop in (params.get("PropBundle") or {}).get("Props") or []:
                if prop.get("Id") != PROP_ATTENUATION:
                    continue
                att_seen = True
                candidate = as_u32(prop.get("Value"))
                if candidate in attenuation_ids:
                    attenuation = candidate
                else:
                    dangling = True
                break
        current = params.get("DirectParentId")
    return bus, attenuation, dangling


def parse_events(objects, nodes, dumps, bank_event_hashes, bus_ids, attenuation_ids):
    """Build the event table and the event-level routing counts."""
    actions = {
        int(obj_id): hierarchy
        for (obj_type, obj_id), hierarchy in objects.items()
        if obj_type == "EventAction"
    }
    event_objects = [
        (int(obj_id), hierarchy)
        for (obj_type, obj_id), hierarchy in objects.items()
        if obj_type == "Event"
    ]
    event_objects.sort()

    events = []
    counts = Counter()
    dangling_attenuations = 0
    missing_actions = 0
    hash_mismatches = 0
    for event_id, hierarchy in event_objects:
        action_ids = (hierarchy.get("Data") or {}).get("EventActionIds") or []
        present = []
        for action_id in action_ids:
            action = actions.get(action_id)
            if action is None:
                missing_actions += 1
                continue
            present.append(action)
        play = any(
            (action.get("Data") or {}).get("EventActionType") == "Play"
            for action in present
        )
        chosen = None
        for action in present:
            if (action.get("Data") or {}).get("EventActionType") == "Play":
                chosen = action
                break
        if chosen is None and present:
            chosen = present[0]

        bus = None
        attenuation = None
        if chosen is not None:
            reference = (chosen.get("Data") or {}).get("ReferencedId")
            bus, attenuation, dangling = resolve_reference(
                reference, nodes, bus_ids, attenuation_ids
            )
            if dangling:
                dangling_attenuations += 1

        dump = dumps.get(event_id)
        if dump is not None:
            expected_hash = bank_event_hashes.get(event_id)
            if expected_hash is not None and expected_hash not in dump["bank_hashes"]:
                hash_mismatches += 1

        if play:
            counts["events_play"] += 1
        if bus is not None:
            counts["events_with_bus"] += 1
        if attenuation is not None:
            counts["events_with_attenuation"] += 1
        max_radius = dump["max_radius_cm"] if dump else None
        if max_radius == 0.0:
            counts["events_2d"] += 1

        events.append(
            {
                "name": dump["name"] if dump else None,
                "id": event_id,
                "play": play,
                "bus": bus,
                "attenuation": attenuation,
                "max_radius_cm": _round(max_radius, 3),
                "is_infinite": dump["is_infinite"] if dump else None,
                "duration_s": {
                    "min": _round(dump["min_duration_s"], 6) if dump else None,
                    "max": _round(dump["max_duration_s"], 6) if dump else None,
                },
                "media_count": dump["media_count"] if dump else None,
            }
        )

    events.sort(
        key=lambda event: (event["name"] is None, event["name"] or "", event["id"])
    )
    stats = {
        "dangling_attenuations": dangling_attenuations,
        "missing_actions": missing_actions,
        "hash_mismatches": hash_mismatches,
    }
    return events, counts, stats


def _round(value, digits):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    return round(float(value), digits)


def parse_buses(objects, names_by_id):
    """Build the 130-bus table (91 audio + 39 auxiliary)."""
    bus_ids = {
        int(obj_id)
        for (obj_type, obj_id) in objects
        if obj_type in ("AudioBus", "AuxiliaryBus")
    }
    buses = []
    for (obj_type, obj_id), hierarchy in objects.items():
        if obj_type not in ("AudioBus", "AuxiliaryBus"):
            continue
        data = hierarchy.get("Data") or {}
        props = {}
        opaque = []
        for prop in data.get("Props") or []:
            prop_id = prop.get("Id")
            if prop_id in (BUS_PROP_VOLUME, BUS_PROP_HPF, BUS_PROP_LPF):
                props[prop_id] = _round(prop.get("Value"), 3)
            else:
                opaque.append({"id": prop_id, "value": _round(prop.get("Value"), 6)})
        opaque.sort(
            key=lambda item: (
                item["id"] if item["id"] is not None else -1,
                item["value"] if item["value"] is not None else float("-inf"),
            )
        )

        parent = data.get("OverrideBusId")
        if not (isinstance(parent, int) and parent in bus_ids):
            parent = None

        effects = []
        for effect in ((data.get("FxBusParams") or {}).get("FxParams") or {}).get(
            "Effects"
        ) or []:
            effects.append(
                {
                    "fx": effect.get("FXId"),
                    "shareset": bool(effect.get("IsShareSet")),
                }
            )
        effects.sort(key=lambda item: (item["fx"] is None, item["fx"] or 0))

        aux_params = data.get("AuxParams") or {}
        aux_sends = [as_id(value) for value in aux_params.get("AuxIds") or [] if value]
        reflections = aux_params.get("ReflectionsAuxBus")
        if not (isinstance(reflections, int) and reflections in bus_ids):
            reflections = None
        device = data.get("DeviceSharesetId")
        if not device:
            device = None

        bus_id = int(obj_id)
        buses.append(
            {
                "id": bus_id,
                "kind": "audio" if obj_type == "AudioBus" else "aux",
                "name": names_by_id.get(bus_id),
                "parent": parent,
                "volume_db": props.get(BUS_PROP_VOLUME),
                "hpf_db": props.get(BUS_PROP_HPF),
                "lpf_db": props.get(BUS_PROP_LPF),
                "effects": effects,
                "aux_sends": sorted(set(aux_sends)),
                "reflections_aux": reflections,
                "device": device,
                "state_groups": len(data.get("StateGroups") or []),
                "rtpcs": len(data.get("RTPCs") or []),
                "duck_rows": len(data.get("DuckInfo") or []),
                "opaque_props": opaque,
            }
        )
    buses.sort(key=lambda bus: bus["id"])
    return buses, bus_ids


def parse_fx(objects, ir_names):
    """Build the FxShareSet/FxCustom table (46 + 199)."""
    fx = []
    unresolved = 0
    media_entries = 0
    for (obj_type, obj_id), hierarchy in objects.items():
        if obj_type not in ("FxShareSet", "FxCustom"):
            continue
        data = hierarchy.get("Data") or {}
        plugin = data.get("Plugin") or {}
        params = (data.get("PluginParams") or {}).get("Params")
        media = data.get("MediaList") or []
        source_id = media[0].get("SourceId") if media else None
        ir_name = ir_names.get(source_id) if source_id is not None else None
        for entry in media:
            media_entries += 1
            media_id = entry.get("SourceId")
            if media_id is None or media_id not in ir_names:
                unresolved += 1
        fx.append(
            {
                "id": int(obj_id),
                "kind": "shareset" if obj_type == "FxShareSet" else "custom",
                "plugin": plugin.get("PluginId"),
                "params": params,
                "ir_source_id": source_id,
                "ir_name": ir_name,
            }
        )
    fx.sort(key=lambda item: (item["id"], item["kind"]))
    stats = {"unresolved_media": unresolved, "media_entries": media_entries}
    return fx, stats


def parse_attenuations(objects):
    """Build the 23 attenuation curves."""
    attenuations = []
    for (obj_type, obj_id), hierarchy in objects.items():
        if obj_type != "Attenuation":
            continue
        data = hierarchy.get("Data") or {}
        curves = []
        for curve in data.get("Curves") or []:
            points = []
            for point in curve.get("GraphPoints") or []:
                points.append(
                    {
                        "from": _round(point.get("From"), 6),
                        "to": _round(point.get("To"), 6),
                        "interpolation": point.get("Interpolation"),
                    }
                )
            curves.append({"scaling": curve.get("Scaling"), "points": points})
        attenuations.append(
            {
                "id": int(obj_id),
                "height_spread": bool(data.get("IsHeightSpreadEnabled")),
                "cone": bool(data.get("IsConeEnabled")),
                "curves": curves,
            }
        )
    attenuations.sort(key=lambda item: item["id"])
    return attenuations


def parse_music(objects, events):
    """Build the music block: event name families, segments, counts."""
    names = [event["name"] for event in events if event["name"]]
    play = sorted(name for name in names if name.startswith(MUSIC_PLAY_PREFIX))
    stop = sorted(name for name in names if name.startswith(MUSIC_STOP_PREFIX))
    mute = sorted(name for name in names if name.startswith(MUSIC_MUTE_PREFIX))
    unmute = sorted(name for name in names if name.startswith(MUSIC_UNMUTE_PREFIX))

    segments = []
    track_count = 0
    switch_containers = 0
    for (obj_type, obj_id), hierarchy in objects.items():
        if obj_type == "MusicTrack":
            track_count += 1
        elif obj_type == "MusicSwitchContainer":
            switch_containers += 1
        elif obj_type == "MusicSegment":
            data = hierarchy.get("Data") or {}
            markers = data.get("Markers") or []
            positions = [
                _round(marker.get("Position"), 6)
                for marker in markers
                if marker.get("Position") is not None
            ]
            meter = data.get("MeterInfo") or {}
            segments.append(
                {
                    "id": int(obj_id),
                    "duration_ms": _round(data.get("Duration"), 6),
                    "tempo": _round(meter.get("Tempo"), 6),
                    "entry_marker": min(positions) if positions else None,
                    "exit_marker": max(positions) if positions else None,
                    "marker_count": len(markers),
                }
            )
    segments.sort(key=lambda item: item["id"])
    return {
        "play_events": play,
        "stop_events": stop,
        "mute_events": mute,
        "unmute_events": unmute,
        "segments": segments,
        "track_count": track_count,
        "switch_container_count": switch_containers,
    }


def _map_dumps():
    """Return [(path, map_name)] for every map dump that can place audio actors."""
    dumps = []
    for path in sorted(MAPS_DIR.rglob("*Audio*.json")):
        if "_generated_audio_boundaries" in path.parts:
            continue
        dumps.append(path)
    if STARTSCREEN_DUMP.is_file() and STARTSCREEN_DUMP not in dumps:
        dumps.append(STARTSCREEN_DUMP)
    dumps.sort(key=lambda item: rel(item))
    return [(path, path.stem) for path in dumps]


def _scene_object(actors, ref):
    """Resolve a UE object reference inside one map dump.

    ``ObjectPath`` ends in the export index (``.../Guildhall_Audio.34``), which
    is the exact position in the dump list, so it is tried first; the
    ``ObjectName`` identity is the fallback.
    """
    index = _scene_index(actors, ref)
    return actors[index] if index is not None else None


def _scene_index(actors, ref):
    """Return the dump-list index a UE object reference points at."""
    if not isinstance(ref, dict):
        return None
    path = ref.get("ObjectPath") or ""
    match = re.search(r"\.(\d+)$", path)
    if match:
        index = int(match.group(1))
        if 0 <= index < len(actors):
            return index
    name = ref_name(ref)
    if not name:
        return None
    outer, _, leaf = name.rpartition(".")
    for index, actor in enumerate(actors):
        if actor.get("Name") != leaf:
            continue
        if short_name(actor.get("Outer")) == outer.rsplit(".", 1)[-1]:
            return index
    return None


def _location(actor, actors):
    """Return the actor's root-component location in metres as [X, Z, Y]."""
    if not isinstance(actor, dict):
        return None
    properties = actor.get("Properties") or {}
    root = _scene_object(actors, properties.get("RootComponent"))
    if root is None:
        root = actor if "RelativeLocation" in properties else None
    if not isinstance(root, dict):
        return None
    location = (root.get("Properties") or {}).get("RelativeLocation")
    if not isinstance(location, dict):
        return None
    return [
        round(float(location.get("X") or 0.0) / 100.0, 4),
        round(float(location.get("Z") or 0.0) / 100.0, 4),
        round(float(location.get("Y") or 0.0) / 100.0, 4),
    ]


def _level_positions(dump_path):
    """Read ``pos`` per actor name from the generated .tatlevel.json, if any."""
    try:
        relative = dump_path.relative_to(MAPS_DIR)
    except ValueError:
        return {}
    target = LEVELS_DIR / (relative.with_suffix("").as_posix() + ".tatlevel.json")
    if not target.is_file():
        return {}
    try:
        payload = json.loads(target.read_text())
    except (OSError, ValueError):
        return {}
    positions = {}
    for actor in payload.get("actors") or []:
        name = actor.get("name")
        pos = actor.get("pos")
        if name and isinstance(pos, list) and len(pos) == 3:
            positions[name] = [round(float(value), 4) for value in pos]
    return positions


def _is_placeholder_label(label, actor_name):
    """True when an AkAmbientSound ActorLabel is still the default actor name."""
    if not label:
        return True
    if label == actor_name:
        return True
    return re.fullmatch(r"AkAmbientSound\d*", label) is not None


def parse_ambience():
    """Build placed emitters and room beds from the map dumps.

    One emitter per placed actor.  An ``AkAmbientSound`` yields its
    ``ActorLabel``; when that label was never authored (the exporter left
    ``AkAmbientSound``/``AkAmbientSound7``) the paired ``AkComponent`` carries
    the real event.  The component is never a second emitter.
    """
    emitters = []
    room_beds = []
    stats = Counter()
    per_map = Counter()
    mapped_positions = 0
    skipped_components = 0
    looping_components = 0
    events_without_name = 0
    label_fallbacks = 0

    for dump_path, map_name in _map_dumps():
        payload = read_json(dump_path)
        actors = payload if isinstance(payload, list) else [payload]
        positions = _level_positions(dump_path)
        produced = {}

        # Pass 1: the placed ambience actors.
        for index, actor in enumerate(actors):
            if actor.get("Type") != "AkAmbientSound":
                continue
            name = actor.get("Name")
            properties = actor.get("Properties") or {}
            label = actor.get("ActorLabel")
            # The paired component's `AkAudioEvent` is the authoritative event
            # reference; `ActorLabel` is the *actor* name and is frequently a
            # per-instance description instead of an event (e.g.
            # "Play_Env_Life_Ground_Cricket_A2" whose component references
            # "Play_Env_Life_Ground_Cricket_A"). Prefer the component, fall back
            # to an authored label, and only then give up.
            component = _scene_object(
                actors,
                properties.get("AkComponent") or properties.get("RootComponent"),
            )
            event = short_name(
                ((component or {}).get("Properties") or {}).get("AkAudioEvent")
            )
            if event:
                label_fallbacks += 1
            elif not _is_placeholder_label(label, name):
                event = label
            if not event:
                events_without_name += 1
                continue
            pos = positions.get(name)
            if pos is not None:
                mapped_positions += 1
            else:
                pos = _location(actor, actors)
            emitters.append(
                {
                    "map": map_name,
                    "actor": name,
                    "class": "AkAmbientSound",
                    "event": event,
                    "pos": pos,
                }
            )
            per_map[map_name] += 1
            produced[index] = event

        # Pass 2: component-owned emitters, one entry per placed actor.
        for actor in actors:
            obj_type = actor.get("Type")
            properties = actor.get("Properties") or {}
            if obj_type == "TATCCAudioComponent":
                if not isinstance(properties.get("AkAudioEvent"), dict):
                    if isinstance(properties.get("AkLoopingAudio"), dict):
                        looping_components += 1
                    continue
                owner = _scene_object(
                    actors, {"ObjectPath": (actor.get("Outer") or {}).get("ObjectPath")}
                )
                event = short_name(properties.get("AkAudioEvent"))
                if owner is None or not event:
                    continue
                name = owner.get("Name")
                pos = positions.get(name) or _location(owner, actors)
                emitters.append(
                    {
                        "map": map_name,
                        "actor": name,
                        "class": "TATCCAudioComponent",
                        "event": event,
                        "pos": pos,
                    }
                )
                per_map[map_name] += 1
            elif obj_type == "AkComponent":
                if not isinstance(properties.get("AkAudioEvent"), dict):
                    continue
                event = short_name(properties.get("AkAudioEvent"))
                owner_ref = {"ObjectPath": (actor.get("Outer") or {}).get("ObjectPath")}
                owner_index = _scene_index(actors, owner_ref)
                owner = actors[owner_index] if owner_index is not None else None
                if (
                    isinstance(owner, dict)
                    and owner.get("Type") == "AkAmbientSound"
                    # The paired component of an ambience actor: same event,
                    # same placement, never a second emitter.
                    and (owner_index in produced or event == owner.get("ActorLabel"))
                ):
                    skipped_components += 1
                    continue
                pos = positions.get(actor.get("Name")) or _location(actor, actors)
                emitters.append(
                    {
                        "map": map_name,
                        "actor": actor.get("Name"),
                        "class": "AkComponent",
                        "event": event,
                        "pos": pos,
                    }
                )
                per_map[map_name] += 1

        # Pass 3: room beds, keyed by their TATSpatialAudioVolume.
        for actor in actors:
            if actor.get("Type") == "AkLateReverbComponent":
                stats["late_reverb_components"] += 1
                if not (actor.get("Properties") or {}).get("bEnable"):
                    stats["late_reverb_disabled"] += 1
            if actor.get("Type") != "TATAudioRoomComponent":
                continue
            properties = actor.get("Properties") or {}
            if not isinstance(properties.get("AkAudioEvent"), dict):
                continue
            volume = short_name(actor.get("Outer"))
            outer_path = (actor.get("Outer") or {}).get("ObjectPath")
            aux_bus = None
            for sibling in actors:
                if sibling.get("Type") != "AkLateReverbComponent":
                    continue
                if (sibling.get("Outer") or {}).get("ObjectPath") != outer_path:
                    continue
                aux_bus = short_name((sibling.get("Properties") or {}).get("AuxBus"))
                break
            if aux_bus is None:
                stats["room_beds_without_aux"] += 1
            room_beds.append(
                {
                    "map": map_name,
                    "volume": volume,
                    "event": short_name(properties.get("AkAudioEvent")),
                    "aux_bus": aux_bus,
                }
            )

    emitters.sort(key=lambda item: (item["map"], item["actor"] or "", item["event"]))
    room_beds.sort(
        key=lambda item: (item["map"], item["volume"] or "", item["event"] or "")
    )
    stats["mapped_positions"] = mapped_positions
    stats["skipped_components"] = skipped_components
    stats["looping_components"] = looping_components
    stats["events_without_name"] = events_without_name
    stats["label_fallbacks"] = label_fallbacks
    stats["per_map"] = per_map
    return emitters, room_beds, stats


def parse_vo(events):
    """Parse Play_VO_* event names into functional speaker/line/verb parts.

    No VO text exists in the extraction, so the parts are a tolerant parse of
    the authored event name (identity token, line number, verb, state, severity,
    variant).  Absent parts are null; the variant suffix (``03alt``) is dropped.
    """
    lines = []
    speakers = Counter()
    unparsed = 0
    for event in events:
        name = event.get("name")
        if not name or not name.startswith(VO_PREFIX):
            continue
        parts = name[len(VO_PREFIX) :].split("_")
        speaker = parts[0]
        index = 1
        # An identity token ("HauntstableDSP") only occurs before a line number;
        # in Play_VO_Player_POI_Entered_Generic the non-numeric token is the verb.
        if (
            len(parts) > index + 1
            and not parts[index].isdigit()
            and parts[index + 1].isdigit()
        ):
            speaker = f"{speaker}_{parts[index]}"
            index += 1
        line = None
        if index < len(parts) and parts[index].isdigit():
            line = int(parts[index])
            index += 1
        tail = parts[index:]
        variant = None
        if tail:
            match = re.fullmatch(r"(\d+)([A-Za-z]*)", tail[-1])
            if match:
                variant = int(match.group(1))
                tail.pop()
        if len(tail) > 3:
            unparsed += 1
        verb = tail[0] if tail and tail[0] else None
        state = tail[1] if len(tail) > 1 and tail[1] else None
        severity = None
        if len(tail) > 2:
            severity = "_".join(part for part in tail[2:] if part) or None
        speakers[speaker] += 1
        lines.append(
            {
                "event": name,
                "speaker": speaker,
                "line": line,
                "verb": verb,
                "state": state,
                "severity": severity,
                "variant": variant,
                "media_count": event.get("media_count"),
            }
        )
    lines.sort(key=lambda item: item["event"])
    stats = {"unparsed": unparsed}
    return {"speakers": dict(sorted(speakers.items())), "lines": lines}, stats


def parse_transmission_loss(rows):
    """Build the transmission-loss table from the surface properties DataTable."""
    table = []
    with_texture = 0
    for material, row in rows.items():
        texture_ref = (row.get("AcousticTexture") or {}).get("AssetPathName") or ""
        texture = texture_ref.rsplit("/", 1)[-1].split(".")[0] if texture_ref else None
        if texture:
            with_texture += 1
        table.append(
            {
                "material": material,
                "transmission_loss": _round(row.get("TransmissionLoss"), 6),
                "acoustic_texture": texture,
            }
        )
    table.sort(key=lambda item: item["material"])
    return table, with_texture


def parse_reverb_assignment(rows, reverb_buses):
    """Build the decay -> aux bus table, resolving names to ids."""
    by_name = {bus["name"]: bus["id"] for bus in reverb_buses if bus["name"]}
    table = []
    unresolved = 0
    for row in rows.values():
        reference = (row.get("AuxBus") or {}).get("AssetPathName") or ""
        name = reference.rsplit("/", 1)[-1].split(".")[0] if reference else None
        bus_id = by_name.get(name)
        if bus_id is None:
            unresolved += 1
        table.append(
            {
                "decay_s": _round(row.get("Decay"), 6),
                "aux_bus": name,
                "aux_bus_id": bus_id,
            }
        )
    table.sort(key=lambda item: (-(item["decay_s"] or 0.0), item["aux_bus"] or ""))
    return table, unresolved


def build():
    """Assemble the whole document.  Raises SourceError on a missing input."""
    bank = load_bank()
    event_dumps = load_events()
    reverb = load_reverb()
    ir_names = load_init_bank()
    surface_rows = load_table(SURFACE_TABLE_PATH)
    reverb_rows = load_table(REVERB_TABLE_PATH)

    objects = bank["objects"]
    names_by_id = {bus["id"]: bus["name"] for bus in reverb}
    buses, bus_ids = parse_buses(objects, names_by_id)
    fx, fx_stats = parse_fx(objects, ir_names)
    attenuations = parse_attenuations(objects)
    attenuation_ids = {item["id"] for item in attenuations}
    events, event_counts, event_stats = parse_events(
        objects,
        bank["nodes"],
        event_dumps["dumps"],
        bank["event_hashes"],
        bus_ids,
        attenuation_ids,
    )
    music = parse_music(objects, events)
    emitters, room_beds, ambience_stats = parse_ambience()
    vo, vo_stats = parse_vo(events)
    transmission_loss, textures = parse_transmission_loss(surface_rows)
    reverb_buses = sorted(
        (bus for bus in reverb if bus["id"] in bus_ids),
        key=lambda bus: (bus["name"] or "", bus["id"]),
    )
    reverb_assignment, unresolved_reverb = parse_reverb_assignment(
        reverb_rows, reverb_buses
    )

    counts = {
        "bank_packaged_files": bank["packaged_files"],
        "bank_files_with_hierarchies": bank["files_with_hierarchies"],
        "objects_unique": len(objects),
        "objects_entries": sum(bank["entries"].values()),
        "buses": len(buses),
        "audio_buses": sum(1 for bus in buses if bus["kind"] == "audio"),
        "aux_buses": sum(1 for bus in buses if bus["kind"] == "aux"),
        "named_buses": sum(1 for bus in buses if bus["name"]),
        "fx_sharesets": sum(1 for item in fx if item["kind"] == "shareset"),
        "fx_custom": sum(1 for item in fx if item["kind"] == "custom"),
        "attenuations": len(attenuations),
        "events_total": len(events),
        "events_ue_dumps": sum(1 for event in events if event["name"]),
        "events_play": event_counts["events_play"],
        "events_with_bus": event_counts["events_with_bus"],
        "events_with_attenuation": event_counts["events_with_attenuation"],
        "events_2d": event_counts["events_2d"],
        "music_play_events": len(music["play_events"]),
        "music_segments": len(music["segments"]),
        "music_tracks": music["track_count"],
        "vo_events": len(vo["lines"]),
        "emitters": len(emitters),
        "room_beds": len(room_beds),
    }

    warnings = _warnings(
        counts=counts,
        bank=bank,
        buses=buses,
        event_dumps=event_dumps,
        event_stats=event_stats,
        ambience_stats=ambience_stats,
        fx_stats=fx_stats,
        vo_stats=vo_stats,
        textures=textures,
        transmission_loss_rows=len(transmission_loss),
        unresolved_reverb=unresolved_reverb,
        attenuations=attenuations,
        ir_names=ir_names,
        room_beds=room_beds,
    )

    return {
        "schema": SCHEMA,
        "generated_by": "tools/parse_wwise.py",
        "sources": {
            "bank": rel(BANK_PATH),
            "events_dir": rel(EVENTS_DIR),
            "reverb_dir": rel(REVERB_DIR),
            "init_bank": rel(INIT_BANK_PATH),
            "surface_table": rel(SURFACE_TABLE_PATH),
            "reverb_table": rel(REVERB_TABLE_PATH),
        },
        "counts": counts,
        "buses": buses,
        "fx": fx,
        "attenuation": attenuations,
        "events": events,
        "transmission_loss": transmission_loss,
        "reverb_assignment": reverb_assignment,
        "reverb_buses": [
            {
                "name": bus["name"],
                "id": bus["id"],
                "ir_name": bus["ir_name"],
                "max_radius_cm": _round(bus["max_radius_cm"], 3),
            }
            for bus in reverb_buses
        ],
        "music": music,
        "ambience": {"emitters": emitters, "room_beds": room_beds},
        "vo": vo,
        "warnings": warnings,
    }


def _warnings(
    *,
    counts,
    bank,
    buses,
    event_dumps,
    event_stats,
    ambience_stats,
    fx_stats,
    vo_stats,
    textures,
    transmission_loss_rows,
    unresolved_reverb,
    attenuations,
    ir_names,
    room_beds,
):
    """Deterministic, human-readable notes about what the data cannot say."""
    per_map = ambience_stats["per_map"]
    audio_dump_emitters = sum(
        counts_map for name, counts_map in per_map.items() if name in EMITTER_DUMPS
    )
    start_emitters = per_map.get("BeautifulCorner_Startscreen_P", 0)
    audio_dump_beds = sum(1 for bed in room_beds if bed["map"] in EMITTER_DUMPS) + sum(
        1
        for bed in room_beds
        if bed["map"] in ("Building_Guildhall_POI_Audio", "ThievesDen_Audio")
    )
    start_beds = sum(
        1 for bed in room_beds if bed["map"] == "BeautifulCorner_Startscreen_P"
    )
    named = counts["named_buses"]
    unnamed = counts["buses"] - named
    buses_without_volume = sum(1 for bus in buses if bus["volume_db"] is None)
    warnings = [
        (
            f"{unnamed} of {counts['buses']} buses have no authored name in the extraction; "
            f"only the {named} reverb aux buses carry one, so every other bus is referred to by id."
        ),
        (
            f"{buses_without_volume} of {counts['buses']} buses carry no prop 0 (volume); volume_db is "
            "null for them (no authored volume override)."
        ),
        (
            f"{counts['events_total'] - counts['events_ue_dumps']} of {counts['events_total']} "
            "bank events have no UE asset dump; name, max_radius_cm, is_infinite, duration_s and "
            "media_count are null for them because the dumps are the only source of event names."
        ),
        (
            f"{ambience_stats['skipped_components']} AkComponent exports repeat the AkAudioEvent of "
            "their owning AkAmbientSound; one emitter is emitted per placed actor, so the paired "
            "component is never counted as a second emitter."
        ),
        (
            f"{ambience_stats['label_fallbacks']} AkAmbientSound emitters took their event from the "
            "paired AkComponent's AkAudioEvent, which is the authoritative reference; ActorLabel is "
            "the actor name and is often a per-instance description (e.g. "
            "Play_Env_Life_Ground_Cricket_A2 -> Play_Env_Life_Ground_Cricket_A), so it is only used "
            "when the component carries no event."
        ),
        (
            f"{ambience_stats['looping_components']} TATCCAudioComponent emitters carry AkLoopingAudio "
            "instead of AkAudioEvent and are therefore not emitted by this contract."
        ),
        (
            f"{ambience_stats['mapped_positions']} of {counts['emitters']} placed emitters joined an "
            "actor name in game/data/generated/levels (the generated tables omit AkAmbientSound), so "
            "every missing position was derived from the RootComponent RelativeLocation in centimetres."
        ),
        (
            f"Room beds without a sibling AkLateReverbComponent AuxBus: "
            f"{ambience_stats['room_beds_without_aux']} of {counts['room_beds']} (aux_bus null)."
        ),
        (
            f"{ambience_stats['late_reverb_disabled']} of "
            f"{ambience_stats['late_reverb_components']} AkLateReverbComponent objects carry "
            "bEnable=false; aux_bus is still emitted from the authored AuxBus reference because the "
            "schema has no enable flag."
        ),
        (
            f"The startscreen dump {rel(STARTSCREEN_DUMP)} does not match *Audio*.json; it is scanned "
            f"explicitly and contributes {start_emitters} emitters and {start_beds} room beds (4 of its "
            "12 TATAudioRoomComponent objects carry no event)."
        ),
        (
            f"{audio_dump_emitters} emitters come from the four *_Audio dumps "
            f"({', '.join(f'{name} {per_map[name]}' for name in sorted(EMITTER_DUMPS))}) and "
            f"{audio_dump_beds} room beds come from the six *_Audio dumps; with the startscreen the "
            f"totals are {counts['emitters']} and {counts['room_beds']}."
        ),
        (
            f"{event_stats['dangling_attenuations']} events resolve a prop-75 attenuation id that is "
            f"not one of the {len(attenuations)} extracted attenuations; they emit null rather than a "
            "dangling id."
        ),
        (
            f"{fx_stats['unresolved_media']} of {fx_stats['media_entries']} effect MediaList source ids "
            f"are absent from the {len(ir_names)} InitBank media entries; their ir_name is null."
        ),
        (
            "Effect impulses are named but not decoded: MediaList source ids point at PLUG chunks whose "
            "samples this producer does not read."
        ),
        (
            "Per-bank copies of the same (Type, Id) differ only in ChildIds; DirectParentId, "
            "OverrideBusId and PropBundle agree across every copy, so de-duplicating on (Type, Id) "
            "does not change the parent walk."
        ),
        (
            f"{textures} of {transmission_loss_rows} transmission-loss rows name an AcousticTexture; "
            "every row carries TransmissionLoss 1.0."
        ),
        (
            "VO subtitles are functional, parsed from the authored event name into speaker/line/verb/"
            "state/severity/variant; no VO text exists in the extraction, so they are not authored "
            "dialogue."
        ),
    ]
    if unresolved_reverb:
        warnings.append(
            f"{unresolved_reverb} reverb-assignment rows name an aux bus that has no AkAuxBus dump."
        )
    if vo_stats["unparsed"]:
        warnings.append(
            f"{vo_stats['unparsed']} Play_VO_ names carry more than the speaker/line/verb/state/"
            "severity/variant shape; the extra tokens are joined into severity."
        )
    if event_dumps["switch_values"]:
        warnings.append(
            f"{event_dumps['files']} files under {rel(EVENTS_DIR)} include "
            f"{event_dumps['switch_values']} AkSwitchValue dumps that are not events; "
            f"{counts['events_ue_dumps']} AkAudioEvent dumps joined."
        )
    if event_dumps["debug_name_mismatches"]:
        warnings.append(
            f"{event_dumps['debug_name_mismatches']} event dumps forward to another event "
            "soundbank (the SoundBank DebugName differs from the asset Name); the join is by "
            "EventId and verified by the packaged-file Hash."
        )
    if event_dumps["duplicate_ids"]:
        warnings.append(
            f"{len(event_dumps['duplicate_ids'])} EventIds occur in more than one event dump."
        )
    if ambience_stats["events_without_name"]:
        warnings.append(
            f"{ambience_stats['events_without_name']} AkAmbientSound actors carry neither an "
            "ActorLabel event nor a component AkAudioEvent and are not emitted."
        )
    if event_dumps["name_mismatches"]:
        warnings.append(
            f"{event_dumps['name_mismatches']} event dumps have a Package basename that differs "
            "from their Name."
        )
    if bank["conflicts"]:
        warnings.append(
            f"{len(bank['conflicts'])} (Type, Id) duplicates disagree on a field the parent walk "
            "uses; the first copy was kept."
        )
    if bank["id_collisions"]:
        warnings.append(
            f"{len(bank['id_collisions'])} numeric ids occur under more than one node type."
        )
    if event_stats["hash_mismatches"]:
        warnings.append(
            f"{event_stats['hash_mismatches']} event dumps do not repeat their bank soundbank hash."
        )
    return sorted(set(warnings))


def canonical(document):
    """Canonical serialisation used for both writing and --check."""
    return json.dumps(document, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def write_output(out_dir, document):
    """Write the canonical bytes atomically, so a failure leaves no partial file."""
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / OUT_NAME
    temp = out_dir / (OUT_NAME + ".tmp")
    try:
        temp.write_bytes(canonical(document).encode("utf-8"))
        temp.replace(target)
    except OSError:
        temp.unlink(missing_ok=True)
        raise
    return target


# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------
def _iter_strings(node):
    if isinstance(node, dict):
        for key, value in node.items():
            yield key
            yield from _iter_strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from _iter_strings(value)
    elif isinstance(node, str):
        yield node


def verify(document, raw_text):
    """Return a list of human-readable invariant failures (empty means OK)."""
    failures = []
    counts = document.get("counts") or {}
    if document.get("schema") != SCHEMA:
        failures.append(f"schema={document.get('schema')!r} expected {SCHEMA!r}")

    for key, expected in EXPECTED_COUNTS.items():
        actual = counts.get(key)
        if actual != expected:
            failures.append(f"counts.{key}={actual} expected {expected}")

    buses = document.get("buses") or []
    bus_ids = {bus["id"] for bus in buses}
    if len(bus_ids) != len(buses):
        failures.append("duplicate bus id")
    for bus in buses:
        if bus.get("parent") is not None and bus["parent"] not in bus_ids:
            failures.append(f"bus {bus['id']} parent {bus['parent']} is not a bus id")
            break
    if sum(1 for bus in buses if bus["kind"] == "audio") != counts.get("audio_buses"):
        failures.append("audio bus count disagrees with buses[]")
    if sum(1 for bus in buses if bus["kind"] == "aux") != counts.get("aux_buses"):
        failures.append("aux bus count disagrees with buses[]")
    named = sum(1 for bus in buses if bus.get("name"))
    if named != counts.get("named_buses"):
        failures.append("named bus count disagrees with buses[]")

    reverb_buses = document.get("reverb_buses") or []
    reverb_names = {bus["name"] for bus in reverb_buses}
    if len(reverb_buses) != counts.get("named_buses"):
        failures.append("reverb_buses length disagrees with named_buses")
    for bus in reverb_buses:
        if bus["id"] not in bus_ids:
            failures.append(f"reverb bus {bus['id']} is not a bus")
            break
    for bus in buses:
        if bus.get("name") and bus["name"] not in reverb_names:
            failures.append(f"named bus {bus['name']} missing from reverb_buses")
            break

    attenuations = document.get("attenuation") or []
    attenuation_ids = {item["id"] for item in attenuations}
    if len(attenuation_ids) != len(attenuations):
        failures.append("duplicate attenuation id")
    if len(attenuations) != counts.get("attenuations"):
        failures.append("attenuation count disagrees with attenuation[]")
    for event in document.get("events") or []:
        if (
            event.get("attenuation") is not None
            and event["attenuation"] not in attenuation_ids
        ):
            failures.append(f"event {event['id']} references unknown attenuation")
            break
        if event.get("bus") is not None and event["bus"] not in bus_ids:
            failures.append(f"event {event['id']} references unknown bus")
            break

    events = document.get("events") or []
    if len(events) != counts.get("events_total"):
        failures.append("events length disagrees with events_total")
    if len({event["id"] for event in events}) != len(events):
        failures.append("duplicate event id")
    dumped = sum(1 for event in events if event["name"])
    if dumped != counts.get("events_ue_dumps"):
        failures.append("events_ue_dumps disagrees with named events")
    for key, field in (
        ("events_play", "play"),
        ("events_with_bus", "bus"),
        ("events_with_attenuation", "attenuation"),
    ):
        actual = sum(1 for event in events if event[field])
        if actual != counts.get(key):
            failures.append(f"counts.{key}={counts.get(key)} but events[] has {actual}")

    loss_rows = document.get("transmission_loss") or []
    if len(loss_rows) != TRANSMISSION_LOSS_ROWS:
        failures.append(f"{len(loss_rows)} transmission-loss rows")
    assignment_rows = document.get("reverb_assignment") or []
    if len(assignment_rows) != REVERB_ASSIGNMENT_ROWS:
        failures.append(f"{len(assignment_rows)} reverb-assignment rows")

    fx = document.get("fx") or []
    if len({item["id"] for item in fx}) != len(fx):
        failures.append("duplicate fx id")
    if sum(1 for item in fx if item["kind"] == "shareset") != counts.get(
        "fx_sharesets"
    ):
        failures.append("fx_sharesets disagrees with fx[]")
    if sum(1 for item in fx if item["kind"] == "custom") != counts.get("fx_custom"):
        failures.append("fx_custom disagrees with fx[]")
    fx_ids = {item["id"] for item in fx}
    for bus in buses:
        if any(effect["fx"] not in fx_ids for effect in bus["effects"]):
            failures.append(f"bus {bus['id']} references an effect missing from fx[]")
            break

    music = document.get("music") or {}
    if len(music.get("segments") or []) != counts.get("music_segments"):
        failures.append("music segments disagree with counts")
    if music.get("track_count") != counts.get("music_tracks"):
        failures.append("music track count disagrees")
    if music.get("switch_container_count") != MUSIC_SWITCH_CONTAINERS:
        failures.append("music switch container count disagrees")
    if len(music.get("play_events") or []) != counts.get("music_play_events"):
        failures.append("music play event count disagrees")

    vo = document.get("vo") or {}
    if len(vo.get("lines") or []) != counts.get("vo_events"):
        failures.append("vo line count disagrees")
    if sum((vo.get("speakers") or {}).values()) != counts.get("vo_events"):
        failures.append("vo speaker counts disagree")

    ambience = document.get("ambience") or {}
    emitters = ambience.get("emitters") or []
    room_beds = ambience.get("room_beds") or []
    if len(emitters) != counts.get("emitters"):
        failures.append("emitter count disagrees")
    if len(room_beds) != counts.get("room_beds"):
        failures.append("room bed count disagrees")
    audio_emitters = sum(1 for item in emitters if item["map"] in EMITTER_DUMPS)
    if audio_emitters != sum(EMITTER_DUMPS.values()):
        failures.append(f"{audio_emitters} emitters in the four *_Audio dumps")
    if (
        sum(1 for item in emitters if item["map"] == "BeautifulCorner_Startscreen_P")
        != STARTSCREEN_EMITTERS
    ):
        failures.append("startscreen emitter count disagrees")
    audio_beds = sum(
        1
        for item in room_beds
        if item["map"] in EMITTER_DUMPS
        or item["map"] in ("Building_Guildhall_POI_Audio", "ThievesDen_Audio")
    )
    if audio_beds != ROOM_BEDS_IN_AUDIO_DUMPS:
        failures.append(f"{audio_beds} room beds in the *_Audio dumps")
    if (
        sum(1 for item in room_beds if item["map"] == "BeautifulCorner_Startscreen_P")
        != ROOM_BEDS_ON_STARTSCREEN
    ):
        failures.append("startscreen room bed count disagrees")
    flat_events = sum(1 for item in events if item.get("max_radius_cm") == 0.0)
    if flat_events != counts.get("events_2d"):
        failures.append(
            f"counts.events_2d={counts.get('events_2d')} but events[] has {flat_events}"
        )
    for item in emitters:
        if not (isinstance(item.get("pos"), list) and len(item["pos"]) == 3):
            failures.append(f"emitter {item.get('actor')} has no 3-element pos")
            break
    for item in room_beds:
        if not item.get("event"):
            failures.append(f"room bed {item.get('volume')} has no event")
            break

    for source in (document.get("sources") or {}).values():
        if (
            not isinstance(source, str)
            or _ABS_PATH_RE.match(source)
            or source.startswith("/")
        ):
            failures.append(f"source path is not repo-relative: {source!r}")
            break
    root = str(ROOT)
    for text in _iter_strings(document):
        if root in text or _ABS_PATH_RE.match(text):
            failures.append(f"absolute path leaked into output: {text!r}")
            break

    if raw_text != canonical(document):
        failures.append(
            "file is not byte-identical to the canonical serialisation (reformat or edit)"
        )
    if json.loads(json.dumps(document)) != document:
        failures.append("JSON does not round-trip")
    if failures:
        return failures
    return []


def summary_line(counts):
    return (
        f"WWISE_OK buses={counts['buses']} audio={counts['audio_buses']} "
        f"aux={counts['aux_buses']} named={counts['named_buses']} "
        f"fx={counts['fx_sharesets']}+{counts['fx_custom']} "
        f"attenuation={counts['attenuations']} events={counts['events_total']} "
        f"dumps={counts['events_ue_dumps']} play={counts['events_play']} "
        f"bus={counts['events_with_bus']} att={counts['events_with_attenuation']} "
        f"2d={counts['events_2d']} music={counts['music_segments']}/{counts['music_tracks']}/"
        f"{MUSIC_SWITCH_CONTAINERS} vo={counts['vo_events']} "
        f"emitters={counts['emitters']} room_beds={counts['room_beds']}"
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Parse the extracted Wwise control plane into audio_wwise.json."
    )
    parser.add_argument(
        "--out",
        required=True,
        metavar="DIR",
        help="output directory (created if missing); audio_wwise.json is written there",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="re-read <out>/audio_wwise.json and assert the invariant table",
    )
    parser.add_argument("--quiet", action="store_true", help="suppress progress lines")
    args = parser.parse_args(argv)

    out_dir = Path(args.out).expanduser()
    target = out_dir / OUT_NAME

    if args.check:
        if not target.is_file():
            print(f"WWISE_SOURCE {rel(target)}: missing", file=sys.stderr)
            return 2
        try:
            raw = target.read_bytes().decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            print(f"WWISE_SOURCE {rel(target)}: unreadable ({exc})", file=sys.stderr)
            return 2
        try:
            document = json.loads(raw)
        except ValueError as exc:
            print(f"WWISE_FAIL not JSON: {exc}", file=sys.stderr)
            return 1
        failures = verify(document, raw)
        if failures:
            reason = "; ".join(failures[:6])
            if len(failures) > 6:
                reason += f"; (+{len(failures) - 6} more)"
            print(f"WWISE_FAIL {reason}", file=sys.stderr)
            return 1
        print(summary_line(document["counts"]))
        return 0

    try:
        document = build()
    except SourceError as exc:
        print(f"WWISE_SOURCE {exc}", file=sys.stderr)
        return 2
    try:
        path = write_output(out_dir, document)
    except OSError as exc:
        print(f"WWISE_SOURCE cannot write {out_dir / OUT_NAME}: {exc}", file=sys.stderr)
        return 2
    if not args.quiet:
        counts = document["counts"]
        print(
            f"wrote {path} ({path.stat().st_size} bytes, "
            f"{len(document['warnings'])} warnings)"
        )
        print(summary_line(counts))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
