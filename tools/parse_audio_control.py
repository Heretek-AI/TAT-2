#!/usr/bin/env python3
"""Parse the extracted Wwise control plane into ``audio_control.json``.

The T03 producer (``tools/parse_wwise.py``) owns the *routing* graph: buses,
attenuation curves, transmission loss, music segments, placed emitters and VO
lines.  It deliberately says nothing about the three Wwise **control** planes
that a mix actually runs on, and the runtime therefore had no way to set a
switch, a state or a game parameter.  This producer owns exactly that slice.

Reads (read-only, all under the repository root):

    extracted/json/Audio/WwiseSharedAssetLibrary.json
        The cooked bank.  This is the only source for:
          * ``SwitchContainer`` objects: ``GroupId``, ``DefaultSwitch``,
            ``SwitchPackages`` (switch id -> child node ids) and the *media*
            behind each package (walk the child graph to ``SoundSfxVoice`` and
            take ``Source.SourceId`` = MediaId);
          * ``StateGroups`` on any node (``BaseParams`` and the AudioBus
            ``Data``): the authored per-state property overrides;
          * ``RtpcList`` on any node: the authored RTPC -> property curves
            (``ConversionTable`` graph points + accumulation mode);
          * the parent edges (``BaseParams.DirectParentId``) used to reach a
            node from the ``EventAction.ReferencedId`` an event plays.
        The bank stores **no names** for groups, values or RTPCs.
    extracted/audio-meta/Audio/** + extracted/json/Audio/** for
    ``AkSwitchValue`` / ``AkStateValue`` / ``AkRtpc`` assets
        The only source of authored group and value *names*, plus the group
        id each value belongs to.  Both trees are scanned because the shipped
        dumps split them: 13 switch groups live under ``Audio/Switches`` and
        the 14th (``IsInteractablePropLocal``) only exists under
        ``Audio/Events/Environment/Props_Interactive``.  A value asset's
        ``Name`` is ``<GroupName>-<ValueName>`` (the Wwise UE integration
        convention); the group name is taken from that prefix only when every
        value in the group agrees on it.
    extracted/audio-meta/Audio/Events/**/*.json
        ``AkAudioEvent`` dumps: EventId -> Name, the only event names anywhere
        in the extraction (the bank stores ids only).

Produces exactly one file: ``<--out>/audio_control.json`` (schema
``tat2.audio_control/1``).

Media-selection contract (why ``packages[].media`` is a superset)
-----------------------------------------------------------------
A SwitchContainer package owns every ``SoundSfxVoice`` under its node ids,
**including the branches of any nested switch container**, because a nested
group's runtime value is unknown at parse time.  The runtime therefore resolves
selection as a *ban*, not a pick::

    banned  = union over every reached container of
              (all media its packages cover) - (all media the selected
               package covers)
    allowed = the event's media - banned

A media id no container covers (a plain layer on its own Play action) is never
banned.  This is exact for a nested tree and for parallel containers on
different Play actions, and it never invents a selection: an unset group uses
the container's authored ``DefaultSwitch``.  Measured on
``Play_FS_Player_Walk`` (319 media): ``FS_Material=Stone`` leaves 44, of which
every surface clip is Stone (16) and no Carpet/Tile/Dirt clip survives.  Some
branches share a node in the bank (Tile reuses the Stone container; Carpet
reuses a ShallowWater container), so those selections legitimately include the
shared family — that is authored data, not a parser defect.

Deliberately does NOT:
    * invent a group, value, RTPC or curve name.  A bank group/value/RTPC with
      no asset dump is emitted with ``name: null`` and counted as unnamed.
    * invent a *binding* (which bus or player a curve drives).  Curves are
      emitted per authored node (``nodes`` list); choosing a consumer binding
      is the runtime's documented job, never this producer's.
    * read clips or media paths.  Selection data is MediaIds; the runtime joins
      them to clips through ``audio_events.json`` (convert_wwise.py) so this
      producer does not depend on the decode step or its ordering.
    * apply, smooth or clamp a curve.  Points are emitted verbatim.

Two traps this file exists to handle:

1. **Signed vs unsigned ids.**  The asset dumps serialise ``GroupId`` and
   value ``ID`` as signed int32, the bank serialises the same ids as u32.  Every
   id is normalised with ``& 0xFFFFFFFF`` before it is used as a key
   (``Music_Switch_Escape`` is ``-1935005111`` in the dump and ``2359962185``
   in the bank; comparing the raw values reports 13 groups instead of 14).
   The RTPC ``ShortId`` is signed the same way.

2. **Per-bank duplication.**  A node is embedded in every soundbank that uses
   it (28,202 entries for 18,355 objects).  De-duplicating on ``(Type, Id)`` is
   only safe if the copies agree on every field this producer reads, so a
   disagreement on ``DirectParentId`` / ``GroupId`` / ``DefaultSwitch`` /
   ``SwitchPackages`` / ``RtpcList`` / ``StateGroups`` / ``Source`` is a hard
   error (measured: 0 conflicts on this extraction).

Fail-closed rules (exit code 1, no file written):
    * a duplicate ``(Type, Id)`` whose copies disagree on a control field;
    * one group name claimed by two different group ids, or one group id with
      two different names;
    * one value (group id, value id) with two different names;
    * one RTPC id with two different names;
    * an event that reaches a node id with two different types.

Determinism: sorted keys, sorted arrays, rounded floats, no timestamps, no host
paths.  Two runs on the same extraction are byte-identical.  ``--check``
re-reads an emitted file, asserts the verified invariant table and exits
non-zero on any drift.

Exit codes: 0 success, 1 ``--check`` mismatch or a fail-closed control conflict,
2 missing/unreadable source.
"""

import argparse
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK_PATH = ROOT / "extracted" / "json" / "Audio" / "WwiseSharedAssetLibrary.json"
EVENTS_DIR = ROOT / "extracted" / "audio-meta" / "Audio" / "Events"
# Both extraction trees carry the same asset dumps; the union is scanned and
# de-duplicated because the *set* of dumps is not identical (see module docstring).
CONTROL_ROOTS = (
    ROOT / "extracted" / "audio-meta" / "Audio",
    ROOT / "extracted" / "json" / "Audio",
)

OUT_NAME = "audio_control.json"
SCHEMA = "tat2.audio_control/1"

# Wwise AkPropID values that a RtpcList / StateGroups entry can target.  Only
# ids that are unambiguous in the Wwise SDK are named; anything else is emitted
# as "param_<id>" so a consumer can never mistake it for a supported target.
AK_PROP_NAMES = {
    0: "volume_db",
    1: "lfe",
    2: "pitch_cents",
    3: "low_pass",
    4: "high_pass",
    5: "makeup_gain",
}
MAX_WALK_DEPTH = 40

# Verified counts (this producer, 2026-11-26).  --check enforces exactly these;
# a drift means the extraction or the parse changed and the runtime contract
# must be re-verified before the number is moved.
EXPECTED_COUNTS = {
    "switch_groups": 14,
    "switch_values": 84,
    "switch_value_duplicates": 6,
    "switch_groups_without_containers": 2,
    "dangling_switch_values": 70,
    "state_groups": 4,
    "state_values": 10,
    "state_value_duplicates": 2,
    "rtpcs": 16,
    "rtpc_curves": 142,
    "switch_containers": 185,
    "switch_package_media": 13146,
    "events_with_control": 180,
}

_ABS_PATH_RE = re.compile(r"^(?:/home/|/tmp/|/Users/|/var/|/root/|[A-Za-z]:[\\/])")


class SourceError(RuntimeError):
    """A required extracted input is missing or unreadable (exit code 2)."""


class ControlConflict(RuntimeError):
    """Two authored sources disagree about an id this producer emits."""


def rel(path):
    """Repository-relative POSIX path for messages and the sources block."""
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


def u32(value):
    """Normalise a signed-int32 authored id to the unsigned form the bank uses."""
    return int(value) & 0xFFFFFFFF


def _round(value, digits=6):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    return round(float(value), digits)


def base_params(hierarchy):
    """Parent/props block: ``BaseParams`` on nodes, ``ContainerHierarchy`` on music."""
    data = hierarchy.get("Data") or {}
    return data.get("BaseParams") or data.get("ContainerHierarchy") or {}


# ---------------------------------------------------------------------------
# Bank
# ---------------------------------------------------------------------------
def _control_signature(hierarchy):
    data = hierarchy.get("Data") or {}
    params = base_params(hierarchy)
    return json.dumps(
        {
            "parent": params.get("DirectParentId"),
            "group_id": data.get("GroupId"),
            "group_type": data.get("GroupType"),
            "default_switch": data.get("DefaultSwitch"),
            "switch_packages": data.get("SwitchPackages"),
            "rtpc_list": params.get("RtpcList"),
            "state_groups": params.get("StateGroups") or data.get("StateGroups"),
            "source": data.get("Source"),
        },
        sort_keys=True,
    )


def load_bank():
    """Load the bank, de-duplicate on ``(Type, Id)`` and index the parent edges."""
    library = read_json(BANK_PATH)
    try:
        packaged = library[0]["CookedData"]["PackagedFiles"]
    except (IndexError, KeyError, TypeError) as exc:
        raise SourceError(f"{rel(BANK_PATH)}: not a Wwise asset library") from exc

    objects = {}
    signatures = {}
    conflicts = []
    entries = Counter()
    for packaged_file in packaged:
        hierarchies = (packaged_file.get("BulkData") or {}).get("Hierarchies") or []
        for hierarchy in hierarchies:
            obj_type = hierarchy.get("Type")
            key = (obj_type, str(hierarchy.get("Id")))
            entries[obj_type] += 1
            signature = _control_signature(hierarchy)
            if key in objects:
                if signatures[key] != signature:
                    conflicts.append(key)
                continue
            objects[key] = hierarchy
            signatures[key] = signature
    if conflicts:
        listed = ", ".join(f"{kind}:{obj_id}" for kind, obj_id in conflicts[:6])
        raise ControlConflict(
            f"{len(conflicts)} (Type, Id) duplicates disagree on a control field "
            f"({listed}); the first copy cannot be trusted"
        )

    # id -> type.  A numeric id under two types is a dangling reference risk.
    types = defaultdict(set)
    for obj_type, obj_id in objects:
        types[int(obj_id)].add(obj_type)
    ambiguous = {
        obj_id: sorted(kinds) for obj_id, kinds in types.items() if len(kinds) > 1
    }

    # parent -> children, from each node's own DirectParentId.
    children = defaultdict(list)
    for (obj_type, obj_id), hierarchy in objects.items():
        if obj_type == "EventAction":
            continue
        parent = base_params(hierarchy).get("DirectParentId")
        if parent:
            children[int(parent)].append(int(obj_id))
    for kids in children.values():
        kids.sort()

    return {
        "packaged_files": len(packaged),
        "entries": entries,
        "objects": objects,
        "types": types,
        "ambiguous": ambiguous,
        "children": children,
    }


def node_type(bank, node_id):
    kinds = bank["types"].get(int(node_id))
    if not kinds:
        return None
    return sorted(kinds)[0]


# ---------------------------------------------------------------------------
# Control asset dumps (switch / state / RTPC names)
# ---------------------------------------------------------------------------
def _scan_assets(type_name):
    """Every dump of [param type_name] under the two extraction trees."""
    rows = []
    seen_files = set()
    for root in CONTROL_ROOTS:
        for path in sorted(glob.glob(str(root) + "/**/*.json", recursive=True)):
            if path in seen_files:
                continue
            try:
                text = Path(path).read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            if type_name not in text:
                continue
            seen_files.add(path)
            try:
                payload = json.loads(text)
            except ValueError:
                continue
            entries = payload if isinstance(payload, list) else [payload]
            for entry in entries:
                if entry.get("Type") == type_name:
                    rows.append((path, entry))
    return rows


def _group_and_value(entry):
    cooked = entry.get("GroupValueCookedData") or {}
    group_id = cooked.get("GroupId")
    value_id = cooked.get("ID")
    if group_id is None or value_id is None:
        return None
    return (
        u32(group_id),
        u32(value_id),
        cooked.get("DebugName"),
        entry.get("Name") or "",
    )


def _tree_of(path):
    """Which extraction tree a dump came from (the two are near-mirrors)."""
    text = str(path)
    return "audio-meta" if f"{os.sep}audio-meta{os.sep}" in text else "json"


def load_group_values(type_name):
    """Build ``{group id: {value id: {...}}}`` with fail-closed name conflicts."""
    groups = defaultdict(dict)
    names_by_group = defaultdict(set)
    files = Counter()
    mirrors = 0
    duplicates = 0
    for path, entry in _scan_assets(type_name):
        row = _group_and_value(entry)
        if row is None:
            continue
        group_id, value_id, debug_name, asset_name = row
        prefix, sep, _ = asset_name.partition("-")
        if sep and prefix:
            names_by_group[group_id].add(prefix)
        tree = _tree_of(path)
        existing = groups[group_id].get(value_id)
        if existing is not None:
            if existing["name"] != debug_name or existing["asset"] != asset_name:
                raise ControlConflict(
                    f"{type_name} group {group_id} value {value_id} is named "
                    f"{existing['name']!r} and {debug_name!r}"
                )
            existing["files"].add(rel(path))
            if tree in existing["trees"]:
                # A true repeat inside one tree: the same asset dumped twice.
                duplicates += 1
            else:
                # The other extraction tree carries the same asset; not a defect.
                existing["trees"].add(tree)
                mirrors += 1
            continue
        groups[group_id][value_id] = {
            "name": debug_name,
            "asset": asset_name,
            "files": {rel(path)},
            "trees": {tree},
        }
        files[rel(path)] += 1
    by_name = {}
    for group_id, values in groups.items():
        names = sorted(names_by_group.get(group_id) or [])
        if len(names) > 1:
            raise ControlConflict(
                f"{type_name} group {group_id} carries {len(names)} asset name "
                f"prefixes ({', '.join(names[:4])}); the group name is ambiguous"
            )
        name = names[0] if names else None
        if name is not None:
            if name in by_name:
                raise ControlConflict(
                    f"{type_name} name {name!r} is claimed by group {by_name[name]} "
                    f"and {group_id}"
                )
            by_name[name] = group_id
    return {
        "groups": groups,
        "files": len(files),
        "mirrors": mirrors,
        "duplicates": duplicates,
    }


def load_rtpc_assets():
    """Build ``{u32 short id: {...}}`` for every AkRtpc dump."""
    rtpcs = {}
    files = 0
    duplicates = 0
    for path, entry in _scan_assets("AkRtpc"):
        cooked = entry.get("GameParameterCookedData") or {}
        short_id = cooked.get("ShortId")
        if short_id is None:
            continue
        files += 1
        group_id = u32(short_id)
        existing = rtpcs.get(group_id)
        if existing is not None:
            duplicates += 1
            if existing["name"] != cooked.get("DebugName"):
                raise ControlConflict(
                    f"AkRtpc {group_id} is named {existing['name']!r} and "
                    f"{cooked.get('DebugName')!r}"
                )
            continue
        rtpcs[group_id] = {
            "name": cooked.get("DebugName"),
            "short_id": int(short_id),
            "asset": entry.get("Name"),
            "file": rel(path),
        }
    return {"rtpcs": rtpcs, "files": files, "duplicates": duplicates}


# ---------------------------------------------------------------------------
# Curves and property overrides
# ---------------------------------------------------------------------------
def conversion_table(table):
    """Normalise a RtpcList ``ConversionTable`` into points + per-point interpolation."""
    if not isinstance(table, dict):
        return None
    points = []
    interpolation = []
    for point in table.get("GraphPoints") or []:
        points.append([_round(point.get("From")), _round(point.get("To"))])
        interpolation.append(point.get("Interpolation"))
    if not points:
        return None
    return {
        "scaling": table.get("Scaling"),
        "points": points,
        "interpolation": interpolation,
    }


def state_overrides(groups):
    """Per-state property rows, keyed by (param id), with the nodes that carry them."""
    # key: (group id, param id) -> {state id: {value: [nodes]}}
    out = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for (obj_type, obj_id), hierarchy in _iter_nodes(groups):
        data = hierarchy.get("Data") or {}
        params = base_params(hierarchy)
        for state_group in params.get("StateGroups") or data.get("StateGroups") or []:
            group_id = u32(state_group.get("Id"))
            for state in state_group.get("States") or []:
                state_id = u32(state.get("Id"))
                for prop in state.get("Properties") or []:
                    param_id = prop.get("Id")
                    value = prop.get("Value")
                    if param_id is None or value is None:
                        continue
                    out[(group_id, int(param_id))][state_id][_round(value)].append(
                        f"{obj_type}:{obj_id}"
                    )
    return out


def _iter_nodes(bank):
    for (obj_type, obj_id), hierarchy in bank["objects"].items():
        yield (obj_type, obj_id), hierarchy


# ---------------------------------------------------------------------------
# Switch containers and media
# ---------------------------------------------------------------------------
def _walk_media(
    bank, start_ids, switch_selection, depth=0, seen=None, out=None, all_branches=False
):
    """Collect MediaIds reachable from [param start_ids] under a switch selection.

    ``switch_selection`` is ``{group id: switch value id}``; a container uses
    the selected value, then its authored default, then (fail-closed) nothing.

    ``all_branches`` unions *every* nested package instead of resolving the
    nested selection.  That is what a package's emitted media uses: a nested
    group's runtime selection is unknown at parse time, so the package must
    carry the superset and the runtime intersects it with the nested container's
    own resolved branch (see the media-selection contract in the module docs).
    """
    if seen is None:
        seen = set()
    if out is None:
        out = Counter()
    if depth > MAX_WALK_DEPTH:
        return out
    for node_id in start_ids:
        node_id = int(node_id)
        if node_id in seen:
            continue
        seen.add(node_id)
        kind = node_type(bank, node_id)
        if kind is None:
            continue
        hierarchy = bank["objects"][(kind, str(node_id))]
        data = hierarchy.get("Data") or {}
        if kind == "SoundSfxVoice":
            source = data.get("Source") or {}
            media = source.get("SourceId")
            if media:
                out[int(media)] += 1
            continue
        if kind in ("SwitchContainer", "MusicSwitchContainer"):
            group_id = data.get("GroupId")
            packages = data.get("SwitchPackages") or []
            if all_branches or (kind == "MusicSwitchContainer" and not packages):
                # Union every child: music containers select through a
                # DecisionTree key rather than SwitchPackages, and a
                # superset is what the runtime intersects.
                _walk_media(
                    bank,
                    bank["children"].get(node_id, []),
                    switch_selection,
                    depth + 1,
                    seen,
                    out,
                )
                continue
            selected = switch_selection.get(group_id, data.get("DefaultSwitch"))
            chosen = []
            for package in packages:
                if package.get("SwitchId") == selected:
                    chosen = package.get("NodeIds") or []
                    break
            if not chosen:
                for package in packages:
                    if package.get("SwitchId") == data.get("DefaultSwitch"):
                        chosen = package.get("NodeIds") or []
                        break
            _walk_media(bank, chosen, switch_selection, depth + 1, seen, out)
            continue
        _walk_media(
            bank,
            bank["children"].get(node_id, []),
            switch_selection,
            depth + 1,
            seen,
            out,
        )
    return out


def parse_switch_containers(bank, switch_groups):
    """Every SwitchContainer: group, default, and the media behind each package.

    ``switch_groups`` is ``{group id: {"values": {value id: {...}}}}`` so a
    package can carry the authored value name; an unnamed group/value stays
    ``None``.
    """
    containers = []
    media_per_package = 0
    unnamed_packages = 0
    unset = 0
    for (obj_type, obj_id), hierarchy in sorted(bank["objects"].items()):
        if obj_type != "SwitchContainer":
            continue
        data = hierarchy.get("Data") or {}
        group_id = data.get("GroupId")
        group_id = u32(group_id) if group_id is not None else None
        packages_raw = data.get("SwitchPackages") or []
        if (group_id in (None, 0)) and not packages_raw:
            # A SwitchContainer with no group and no package selects nothing: it
            # carries no control surface, so it is counted and not emitted.
            unset += 1
            continue
        default = data.get("DefaultSwitch")
        default = u32(default) if default is not None else None
        packages = []
        seen_switch = set()
        for package in data.get("SwitchPackages") or []:
            switch_id = package.get("SwitchId")
            switch_id = u32(switch_id) if switch_id is not None else None
            if switch_id is None or switch_id in seen_switch:
                continue
            seen_switch.add(switch_id)
            media = _walk_media(
                bank,
                package.get("NodeIds") or [],
                {group_id: switch_id} if group_id is not None else {},
                all_branches=True,
            )
            media_ids = sorted(media)
            media_per_package += len(media_ids)
            values = (switch_groups.get(group_id) or {}).get("values") or {}
            value = values.get(switch_id) or {}
            if value.get("name") is None:
                unnamed_packages += 1
            packages.append(
                {
                    "switch": switch_id,
                    "name": value.get("name"),
                    "media": media_ids,
                    "voices": sum(media.values()),
                }
            )
        packages.sort(key=lambda item: (item["switch"] is None, item["switch"] or 0))
        group = switch_groups.get(group_id) or {}
        default_value = (group.get("values") or {}).get(default) or {}
        containers.append(
            {
                "id": int(obj_id),
                "group": group_id,
                "group_name": group.get("name"),
                "default": default,
                "default_name": default_value.get("name"),
                "packages": packages,
            }
        )
    containers.sort(key=lambda item: item["id"])
    return {
        "containers": containers,
        "media_per_package": media_per_package,
        "unnamed_packages": unnamed_packages,
        "unset": unset,
    }


# ---------------------------------------------------------------------------
# Event -> control edges
# ---------------------------------------------------------------------------
def load_event_names():
    """EventId -> authored AkAudioEvent Name (the bank has ids only)."""
    if not EVENTS_DIR.is_dir():
        raise SourceError(f"{rel(EVENTS_DIR)}: missing")
    names = {}
    files = 0
    for path in sorted(EVENTS_DIR.rglob("*.json")):
        payload = read_json(path)
        entries = payload if isinstance(payload, list) else [payload]
        for entry in entries:
            if entry.get("Type") != "AkAudioEvent":
                continue
            files += 1
            name = entry.get("Name")
            cooked = entry.get("EventCookedData") or {}
            for language in cooked.get("EventLanguageMap") or []:
                event_id = (language.get("Value") or {}).get("EventId")
                if event_id is None:
                    continue
                existing = names.get(int(event_id))
                if existing is not None and existing != name:
                    raise ControlConflict(
                        f"event {event_id} is named {existing!r} and {name!r}"
                    )
                names[int(event_id)] = name
    return {"names": names, "files": files}


def collect_control(bank, start_id):
    """Union every switch/state/RTPC an event's play action can reach.

    Switch branches are *all* expanded (not only the selected one): the event
    can be told to play any of them, so its control surface is the union.
    """
    containers = {}
    switch_groups = set()
    state_groups = set()
    rtpc_ids = set()
    stack = [(int(start_id), 0)]
    seen = set()
    while stack:
        node_id, depth = stack.pop()
        if depth > MAX_WALK_DEPTH or node_id in seen:
            continue
        seen.add(node_id)
        kind = node_type(bank, node_id)
        if kind is None:
            continue
        hierarchy = bank["objects"][(kind, str(node_id))]
        data = hierarchy.get("Data") or {}
        if kind == "SwitchContainer":
            group_id = data.get("GroupId")
            group_id = u32(group_id) if group_id is not None else None
            containers[node_id] = group_id
            if group_id is not None:
                switch_groups.add(group_id)
        for entry in base_params(hierarchy).get("RtpcList") or []:
            if (
                entry.get("RtpcType") == "GameParameter"
                and entry.get("RtpcId") is not None
            ):
                rtpc_ids.add(int(entry["RtpcId"]))
        for state_group in (
            base_params(hierarchy).get("StateGroups") or data.get("StateGroups") or []
        ):
            if state_group.get("Id") is not None:
                state_groups.add(u32(state_group.get("Id")))
        for child in bank["children"].get(node_id, []):
            stack.append((child, depth + 1))
    return {
        "containers": containers,
        "switch_groups": switch_groups,
        "state_groups": state_groups,
        "rtpcs": rtpc_ids,
    }


def parse_events(bank, event_names, container_groups):
    """Event name -> the control objects its Play actions reach.

    ``container_groups`` is the emitted ``{container id: group id}`` map; a
    SwitchContainer the producer does not emit (unset group, no package) is
    dropped from the event surface too, so the two tables cannot disagree.
    """
    actions = {
        int(obj_id): hierarchy
        for (obj_type, obj_id), hierarchy in bank["objects"].items()
        if obj_type == "EventAction"
    }
    events = {}
    edges = Counter()
    unnamed = 0
    for (obj_type, obj_id), hierarchy in sorted(bank["objects"].items()):
        if obj_type != "Event":
            continue
        event_id = int(obj_id)
        containers = set()
        switch_ids = set()
        state_ids = set()
        rtpc_ids = set()
        for action_id in (hierarchy.get("Data") or {}).get("EventActionIds") or []:
            action = actions.get(action_id)
            if action is None:
                continue
            reference = (action.get("Data") or {}).get("ReferencedId")
            if not reference:
                continue
            found = collect_control(bank, int(reference))
            for node_id, group_id in found["containers"].items():
                if node_id not in container_groups:
                    continue
                containers.add(node_id)
                if group_id is not None:
                    switch_ids.add(group_id)
            state_ids |= found["state_groups"]
            rtpc_ids |= found["rtpcs"]
        if not (containers or switch_ids or state_ids or rtpc_ids):
            continue
        name = event_names.get(event_id)
        if not name:
            # The bank stores ids only; an event with no AkAudioEvent dump has
            # no name the runtime could ever ask for.
            unnamed += 1
            continue
        edges["containers"] += len(containers)
        edges["switch_groups"] += len(switch_ids)
        edges["state_groups"] += len(state_ids)
        edges["rtpcs"] += len(rtpc_ids)
        events[name] = {
            "event_id": event_id,
            "containers": sorted(containers),
            "switch_groups": sorted(switch_ids),
            "state_groups": sorted(state_ids),
            "rtpcs": sorted(rtpc_ids),
        }
    return {"events": events, "edges": edges, "unnamed_events": unnamed}


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------
def _group_block(
    group_id, info, container_counts, node_counts, overrides, unnamed_values=None
):
    values = []
    for value_id in sorted(info["values"]):
        value = info["values"][value_id]
        values.append(
            {
                "id": value_id,
                "name": value["name"],
                "asset": value["asset"],
            }
        )
    block = {
        "id": group_id,
        "name": info.get("name"),
        "values": values,
        "containers": container_counts.get(group_id, 0),
        "nodes": node_counts.get(group_id, 0),
    }
    if unnamed_values:
        # Value ids a SwitchPackage references in this group with no AkSwitchValue
        # dump *for this group*. The same id can be named under a different group
        # (MetalPipe/WoodObject), so the name is group-scoped and stays null.
        block["unnamed_values"] = sorted(unnamed_values)
    if overrides is not None:
        rows = []
        for param_id in sorted(overrides):
            states = overrides[param_id]
            rows.append(
                {
                    "param_id": param_id,
                    "param": AK_PROP_NAMES.get(param_id, f"param_{param_id}"),
                    "values": [
                        {
                            "state": state_id,
                            "value": value,
                            "nodes": sorted(set(states[state_id][value])),
                        }
                        for state_id in sorted(states)
                        for value in sorted(
                            states[state_id], key=lambda item: (item is None, item)
                        )
                    ],
                }
            )
        block["overrides"] = rows
    return block


def parse_rtpcs(bank, rtpc_assets, event_control):
    """Every RTPC the bank references: authored curves, per-param, per-node.

    Curves are de-duplicated on the *curve itself* (param, accumulation,
    scaling, points, interpolation), never on (param, accumulation) alone: the
    same RTPC carries different curves on different nodes (13 volume rows on the
    detection RTPC are 4 distinct shapes), and collapsing them would attribute
    one node's curve to another.
    """
    # rtpc id -> (param id, accum, signature) -> {table, accum, nodes}
    curves = defaultdict(dict)
    rtpc_nodes = Counter()
    for (obj_type, obj_id), hierarchy in bank["objects"].items():
        for entry in base_params(hierarchy).get("RtpcList") or []:
            if entry.get("RtpcType") != "GameParameter":
                continue
            rtpc_id = entry.get("RtpcId")
            if rtpc_id is None:
                continue
            param_id = entry.get("ParamId")
            if param_id is None:
                continue
            table = conversion_table(entry.get("ConversionTable"))
            if table is None:
                continue
            accum = entry.get("RtpcAccum")
            signature = json.dumps(
                {
                    "scaling": table["scaling"],
                    "points": table["points"],
                    "interpolation": table["interpolation"],
                    "accum": accum,
                    "param": int(param_id),
                },
                sort_keys=True,
            )
            key = (int(param_id), str(accum), signature)
            bucket = curves[int(rtpc_id)].get(key)
            if bucket is None:
                bucket = {"table": table, "accum": accum, "nodes": []}
                curves[int(rtpc_id)][key] = bucket
            bucket["nodes"].append(f"{obj_type}:{obj_id}")
            rtpc_nodes[int(rtpc_id)] += 1

    events_by_rtpc = defaultdict(list)
    for name, block in event_control["events"].items():
        for rtpc_id in block["rtpcs"]:
            events_by_rtpc[rtpc_id].append(name)

    named = []
    unnamed = []
    curve_count = 0
    # Every RTPC id the bank references *and* every authored asset is emitted:
    # an RTPC with no conversion table still exists, so `set_rtpc` must be able
    # to record it; dropping it would understate the control plane.
    for rtpc_id in sorted(set(curves) | set(rtpc_assets)):
        rows = []
        ordered = sorted(
            curves[rtpc_id].items(),
            key=lambda item: (
                item[0][0],
                item[0][1],
                -len(item[1]["nodes"]),
                item[0][2],
            ),
        )
        for (param_id, _accum, _signature), bucket in ordered:
            table = bucket["table"]
            rows.append(
                {
                    "param_id": param_id,
                    "param": AK_PROP_NAMES.get(param_id, f"param_{param_id}"),
                    "accum": bucket["accum"],
                    "scaling": table["scaling"],
                    "points": table["points"],
                    "interpolation": table["interpolation"],
                    "nodes": sorted(bucket["nodes"]),
                }
            )
            curve_count += 1
        asset = rtpc_assets.get(rtpc_id)
        block = {
            "id": rtpc_id,
            "curves": rows,
            "nodes": rtpc_nodes[rtpc_id],
            "events": sorted(events_by_rtpc.get(rtpc_id, [])),
        }
        if asset is None:
            block["name"] = None
            block["short_id"] = None
            unnamed.append(block)
        else:
            block["name"] = asset["name"]
            block["short_id"] = asset["short_id"]
            named.append(block)
    named.sort(key=lambda item: (item["name"] or "", item["id"]))
    unnamed.sort(key=lambda item: item["id"])
    return {
        "named": named,
        "unnamed": unnamed,
        "curves": curve_count,
        "assets": len(rtpc_assets),
    }


def build():
    """Assemble the document.  Raises SourceError / ControlConflict."""
    bank = load_bank()

    switch_assets = load_group_values("AkSwitchValue")
    state_assets = load_group_values("AkStateValue")
    rtpc_assets = load_rtpc_assets()
    event_names = load_event_names()["names"]

    # Resolve each group's authored name from the common asset prefix.
    def named_groups(assets):
        out = {}
        for group_id, values in assets["groups"].items():
            prefixes = set()
            for value in values.values():
                prefix, sep, _ = value["asset"].partition("-")
                if sep and prefix:
                    prefixes.add(prefix)
            if len(prefixes) > 1:
                raise ControlConflict(
                    f"group {group_id} carries {len(prefixes)} asset name prefixes; "
                    "the group name is ambiguous"
                )
            out[group_id] = {
                "name": next(iter(prefixes)) if prefixes else None,
                "values": values,
            }
        names = {}
        for group_id, info in out.items():
            name = info["name"]
            if name is None:
                continue
            if name in names:
                raise ControlConflict(
                    f"group name {name!r} is claimed by {names[name]} and {group_id}"
                )
            names[name] = group_id
        return out

    switch_groups = named_groups(switch_assets)
    state_groups = named_groups(state_assets)

    overrides = state_overrides(bank)
    container_counts = Counter()
    state_node_counts = Counter()
    for (obj_type, obj_id), hierarchy in bank["objects"].items():
        data = hierarchy.get("Data") or {}
        if obj_type == "SwitchContainer" and data.get("GroupId") is not None:
            container_counts[u32(data.get("GroupId"))] += 1
        for state_group in (
            base_params(hierarchy).get("StateGroups") or data.get("StateGroups") or []
        ):
            if state_group.get("Id") is not None:
                state_node_counts[u32(state_group.get("Id"))] += 1

    switch_container_block = parse_switch_containers(bank, switch_groups)
    container_groups = {
        container["id"]: container["group"]
        for container in switch_container_block["containers"]
    }
    event_control = parse_events(bank, event_names, container_groups)
    rtpc_block = parse_rtpcs(bank, rtpc_assets["rtpcs"], event_control)

    # Switch groups present in the bank but with no asset dump.
    named_switch_ids = set(switch_groups)
    for group_id in sorted(container_counts):
        if group_id == 0:
            continue
        if group_id in named_switch_ids:
            continue
        if group_id not in switch_groups:
            switch_groups[group_id] = {"name": None, "values": {}}
    # State groups referenced by the bank but with no asset dump.
    for group_id in sorted(state_node_counts):
        if group_id in state_groups:
            continue
        state_groups[group_id] = {"name": None, "values": {}}

    switch_blocks = []
    unnamed_value_ids = defaultdict(set)
    for container in switch_container_block["containers"]:
        group_id = container["group"]
        known = set((switch_groups.get(group_id) or {}).get("values") or {})
        for package in container["packages"]:
            switch_id = package["switch"]
            if switch_id is not None and switch_id not in known:
                unnamed_value_ids[group_id].add(switch_id)
    for group_id, info in switch_groups.items():
        switch_blocks.append(
            _group_block(
                group_id,
                info,
                container_counts,
                Counter(),
                None,
                unnamed_value_ids.get(group_id),
            )
        )
    switch_blocks.sort(
        key=lambda item: (item["name"] is None, item["name"] or "", item["id"])
    )

    state_blocks = []
    for group_id, info in state_groups.items():
        block = _group_block(
            group_id,
            info,
            Counter(),
            state_node_counts,
            {
                param: states
                for (gid, param), states in overrides.items()
                if gid == group_id
            },
        )
        state_blocks.append(block)
    state_blocks.sort(
        key=lambda item: (item["name"] is None, item["name"] or "", item["id"])
    )

    counts = {
        "switch_groups": sum(1 for item in switch_blocks if item["name"] is not None),
        "switch_groups_total": len(switch_blocks),
        "switch_values": sum(
            1
            for item in switch_blocks
            for value in item["values"]
            if value["name"] is not None
        ),
        "switch_value_duplicates": switch_assets["duplicates"],
        "switch_value_mirrors": switch_assets["mirrors"],
        "dangling_switch_values": sum(len(ids) for ids in unnamed_value_ids.values()),
        "state_groups": sum(1 for item in state_blocks if item["name"] is not None),
        "state_groups_total": len(state_blocks),
        "state_values": sum(
            1
            for item in state_blocks
            for value in item["values"]
            if value["name"] is not None
        ),
        "state_value_duplicates": state_assets["duplicates"],
        "state_value_mirrors": state_assets["mirrors"],
        "rtpcs": len(rtpc_block["named"]),
        "rtpcs_total": len(rtpc_block["named"]) + len(rtpc_block["unnamed"]),
        "rtpc_curves": rtpc_block["curves"],
        "switch_containers": len(switch_container_block["containers"]),
        "unset_switch_containers": switch_container_block["unset"],
        "switch_package_media": switch_container_block["media_per_package"],
        "events_with_control": len(event_control["events"]),
        "events_without_name": event_control["unnamed_events"],
        "event_containers": event_control["edges"]["containers"],
        "event_rtpcs": event_control["edges"]["rtpcs"],
        "event_switch_groups": event_control["edges"]["switch_groups"],
        "event_state_groups": event_control["edges"]["state_groups"],
        "switch_groups_without_containers": sum(
            1
            for item in switch_blocks
            if item["name"] is not None and item["containers"] == 0
        ),
    }

    warnings = _warnings(
        counts=counts,
        switch_assets=switch_assets,
        state_assets=state_assets,
        rtpc_block=rtpc_block,
        switch_container_block=switch_container_block,
        event_control=event_control,
        bank=bank,
    )

    return {
        "schema": SCHEMA,
        "generated_by": "tools/parse_audio_control.py",
        "sources": {
            "bank": rel(BANK_PATH),
            "events_dir": rel(EVENTS_DIR),
            "control_roots": [rel(path) for path in CONTROL_ROOTS],
        },
        "counts": counts,
        "switch_groups": switch_blocks,
        "state_groups": state_blocks,
        "rtpcs": rtpc_block["named"],
        "unnamed_rtpcs": rtpc_block["unnamed"],
        "switch_containers": switch_container_block["containers"],
        "events": event_control["events"],
        "warnings": warnings,
    }


def _warnings(
    *,
    counts,
    switch_assets,
    state_assets,
    rtpc_block,
    switch_container_block,
    event_control,
    bank,
):
    warnings = [
        (
            f"{counts['switch_groups']} of {counts['switch_groups_total']} switch groups carry an "
            "authored name (AkSwitchValue dumps). The bank references the unnamed remainder by id "
            "only, and no asset dump names them, so their name is null rather than invented."
        ),
        (
            f"{counts['state_groups']} of {counts['state_groups_total']} state groups carry an "
            "authored name (AkStateValue dumps); the rest are bank-only ids."
        ),
        (
            f"{counts['switch_value_duplicates']} switch value and "
            f"{counts['state_value_duplicates']} state value dumps repeat an already-seen "
            "(group, value) id with the same name *within one extraction tree*; the duplicate is "
            "counted, not emitted twice. A further "
            f"{counts['switch_value_mirrors']} switch and {counts['state_value_mirrors']} state "
            "dumps are the other extraction tree's copy of the same asset (audio-meta vs json) "
            "and are not defects."
        ),
        (
            f"{counts['dangling_switch_values']} switch value ids are referenced by a "
            "SwitchPackage but have no AkSwitchValue dump *for that group*; their name is null "
            "and their media is still emitted. Names are group-scoped: MetalPipe/WoodObject carry "
            "a name under PhysmatImpact_Material and are unnamed under FS_Material."
        ),
        (
            f"State groups do not select media: a state group carries property overrides only. "
            f"The {counts['switch_containers']} SwitchContainers are the entire authored media "
            "selection surface."
        ),
        (
            f"{len(rtpc_block['unnamed'])} of {counts['rtpcs_total']} RTPC ids the bank references "
            f"have no AkRtpc dump (name null). {counts['rtpcs']} are named."
        ),
        (
            f"Curves are emitted per authored node ({counts['rtpc_curves']} node/param rows). "
            "A single global value cannot reproduce every node's curve; picking a consumer "
            "binding is the runtime's documented job."
        ),
        (
            f"{switch_container_block['unnamed_packages']} switch packages reference a value id "
            "with no authored name; their name is null and the media list is still emitted."
        ),
        (
            "Media selection is emitted as MediaIds. The runtime joins them to decoded clips "
            "through audio_events.json, so this producer does not depend on convert_wwise.py."
        ),
        (
            f"{event_control['unnamed_events']} bank events have no AkAudioEvent dump name and are "
            "omitted from the event table (the bank carries ids only)."
        ),
    ]
    if bank["ambiguous"]:
        listed = ", ".join(str(key) for key in sorted(bank["ambiguous"])[:6])
        warnings.append(
            f"{len(bank['ambiguous'])} numeric ids occur under more than one Wwise type "
            f"({listed}); a node type is resolved by sorted type name, which is unambiguous for "
            "the ids this producer walks."
        )
    named_without_containers = counts["switch_groups_without_containers"]
    if named_without_containers:
        warnings.append(
            f"{named_without_containers} named switch groups have no SwitchContainer: the two "
            "MusicSwitchContainers select through a DecisionTree key rather than SwitchPackages, "
            "so those groups carry no package media."
        )
    return sorted(set(warnings))


def canonical(document):
    return json.dumps(document, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def write_output(out_dir, document):
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
    failures = []
    if document.get("schema") != SCHEMA:
        failures.append(f"schema={document.get('schema')!r} expected {SCHEMA!r}")
    counts = document.get("counts") or {}
    for key, expected in EXPECTED_COUNTS.items():
        actual = counts.get(key)
        if actual != expected:
            failures.append(f"counts.{key}={actual} expected {expected}")

    switch_groups = document.get("switch_groups") or []
    group_ids = [item["id"] for item in switch_groups]
    if len(set(group_ids)) != len(group_ids):
        failures.append("duplicate switch group id")
    for group in switch_groups:
        ids = [value["id"] for value in group["values"]]
        if len(set(ids)) != len(ids):
            failures.append(f"switch group {group['id']} has a duplicate value id")
            break
        if group["name"] is not None and any(
            value["name"] is None for value in group["values"]
        ):
            failures.append(f"named switch group {group['name']} has an unnamed value")
            break

    state_groups = document.get("state_groups") or []
    if len({item["id"] for item in state_groups}) != len(state_groups):
        failures.append("duplicate state group id")

    rtpcs = document.get("rtpcs") or []
    if len(rtpcs) != counts.get("rtpcs"):
        failures.append("rtpcs length disagrees with counts")
    if len({item["id"] for item in rtpcs}) != len(rtpcs):
        failures.append("duplicate rtpc id")
    all_rtpcs = rtpcs + (document.get("unnamed_rtpcs") or [])
    if len({item["id"] for item in all_rtpcs}) != len(all_rtpcs):
        failures.append("an rtpc id appears in both rtpcs and unnamed_rtpcs")
    if len(all_rtpcs) != counts.get("rtpcs_total"):
        failures.append("rtpcs_total disagrees with the two rtpc tables")
    curve_rows = 0
    for rtpc in all_rtpcs:
        if rtpc is None or not isinstance(rtpc.get("curves"), list):
            failures.append("rtpc row has no curves list")
            break
        for curve in rtpc["curves"]:
            curve_rows += 1
            if len(curve["points"]) != len(curve["interpolation"]):
                failures.append(
                    f"rtpc {rtpc['id']} curve points/interpolation disagree"
                )
                break
            xs = [point[0] for point in curve["points"]]
            if xs != sorted(xs):
                failures.append(f"rtpc {rtpc['id']} curve is not sorted by input")
                break
    if curve_rows != counts.get("rtpc_curves"):
        failures.append(f"rtpc curve rows {curve_rows} != counts.rtpc_curves")

    containers = document.get("switch_containers") or []
    if len(containers) != counts.get("switch_containers"):
        failures.append("switch container count disagrees")
    known_groups = {item["id"] for item in switch_groups}
    media_total = 0
    for container in containers:
        if container["group"] is not None and container["group"] not in known_groups:
            failures.append(
                f"container {container['id']} names unknown group {container['group']}"
            )
            break
        switches = [package["switch"] for package in container["packages"]]
        if len(set(switches)) != len(switches):
            failures.append(
                f"container {container['id']} has a duplicate switch package"
            )
            break
        for package in container["packages"]:
            media_total += len(package["media"])
    if media_total != counts.get("switch_package_media"):
        failures.append(
            f"package media total {media_total} != counts.switch_package_media"
        )

    events = document.get("events") or {}
    if len(events) != counts.get("events_with_control"):
        failures.append("event count disagrees with counts.events_with_control")
    container_ids = {item["id"] for item in containers}
    for name, block in events.items():
        for container_id in block["containers"]:
            if container_id not in container_ids:
                failures.append(f"event {name} names unknown container {container_id}")
                break
        else:
            continue
        break

    for source in (document.get("sources") or {}).values():
        if isinstance(source, list):
            continue
        if (
            not isinstance(source, str)
            or _ABS_PATH_RE.match(source)
            or source.startswith("/")
        ):
            failures.append(f"source path is not repo-relative: {source!r}")
            break
    for source in (document.get("sources") or {}).get("control_roots") or []:
        if (
            not isinstance(source, str)
            or _ABS_PATH_RE.match(source)
            or source.startswith("/")
        ):
            failures.append(f"control root is not repo-relative: {source!r}")
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
    return failures


def summary_line(counts):
    return (
        f"AUDIO_CONTROL_OK switch={counts['switch_groups']}/"
        f"{counts['switch_groups_total']} switch_values={counts['switch_values']} "
        f"state={counts['state_groups']}/{counts['state_groups_total']} "
        f"state_values={counts['state_values']} rtpcs={counts['rtpcs']}/"
        f"{counts['rtpcs_total']} curves={counts['rtpc_curves']} "
        f"containers={counts['switch_containers']} "
        f"package_media={counts['switch_package_media']} "
        f"events={counts['events_with_control']}"
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Parse the extracted Wwise control plane into audio_control.json."
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "game" / "data" / "generated",
        metavar="DIR",
        help="output directory (created if missing); audio_control.json is written there "
        "(default: game/data/generated, like the other producers)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="re-read <out>/audio_control.json and assert the invariant table",
    )
    parser.add_argument("--quiet", action="store_true", help="suppress progress lines")
    args = parser.parse_args(argv)

    out_dir = Path(args.out).expanduser()
    target = out_dir / OUT_NAME

    if args.check:
        if not target.is_file():
            print(f"AUDIO_CONTROL_SOURCE {rel(target)}: missing", file=sys.stderr)
            return 2
        try:
            raw = target.read_bytes().decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            print(
                f"AUDIO_CONTROL_SOURCE {rel(target)}: unreadable ({exc})",
                file=sys.stderr,
            )
            return 2
        try:
            document = json.loads(raw)
        except ValueError as exc:
            print(f"AUDIO_CONTROL_FAIL not JSON: {exc}", file=sys.stderr)
            return 1
        failures = verify(document, raw)
        if failures:
            reason = "; ".join(failures[:6])
            if len(failures) > 6:
                reason += f"; (+{len(failures) - 6} more)"
            print(f"AUDIO_CONTROL_FAIL {reason}", file=sys.stderr)
            return 1
        print(summary_line(document["counts"]))
        return 0

    try:
        document = build()
    except (SourceError, ControlConflict) as exc:
        print(f"AUDIO_CONTROL_SOURCE {exc}", file=sys.stderr)
        return 2 if isinstance(exc, SourceError) else 1
    try:
        path = write_output(out_dir, document)
    except OSError as exc:
        print(
            f"AUDIO_CONTROL_SOURCE cannot write {out_dir / OUT_NAME}: {exc}",
            file=sys.stderr,
        )
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
