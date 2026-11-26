#!/usr/bin/env python3
"""W10-A defect 8 gate: the authored `CanBeLockpicked` RESOLVED VALUE.

No Godot, no dependencies: plain `python3 build/qa/w10/check_lock_cdo.py`.
Reads the shipped UE5.5 dump (`extracted/json/**`, read-only) and re-derives the
fact machine, exactly as `build/qa/w10/re-1-locks.md` §2-§3 does.

WHAT THIS PROVES
  The dump serialises a **delta against the archetype**: every object names its
  archetype in `Template` (`Super` when the parent is a Blueprint, `SuperStruct`
  when it is native), and a property absent on an object means "inherit", not
  "false" (re-1-locks.md §2.1-§2.3). So walking `Super`/`SuperStruct` from every
  `BlueprintGeneratedClass` that owns a `_lockConfig` and taking the NEAREST
  explicit `CanBeLockpicked` yields the value every class and every placement
  actually resolves to. The unresolved tail (native class, no authored flag)
  resolves to the authored default `true` — that is why the prison door
  `StaticMeshActor_528` is pickable (`TATSwingingDoor` inherits `true`).

WHAT THIS DOES NOT PROVE
  The native C++ initialiser. No `/Script` package is exported
  (`grep -rl '"Package": "/Script' extracted/json | wc -l` -> 0), so
  `TATSwingingDoor` / `TATLockableToggle` have no CDO in the dump and the
  UPROPERTY default cannot be read (re-1-locks.md §3.4). The resolved value is
  *forced* by the delta rule, and the decisive same-chain case is
  `BP_Res_Int_Doorway_C` — a door on the same native class — whose FTUE instance
  writes `CanBeLockpicked: false` (re-1-locks.md §3.2): a delta serializer would
  have dropped that write if the inherited value were already `false`.
  Confidence: high for the resolved value, not for the unreadable initialiser.

ASSERTIONS (the expectations live HERE, never in a dump-provided summary)
  (i)   exactly ONE class resolves `false` — `BP_SlidingWindow_Base_C` — and it
        has ZERO directly placed actors in `extracted/json/Maps/**`;
  (ii)  every placed lock actor that resolves `false` authored that `false`
        EXPLICITLY on its instance (never inferred) — 33/33 today;
  (iii) the prison actor `StaticMeshActor_528` (Guildhall POI) authors
        `_locked: true`, a `KeyTag`, and NO `CanBeLockpicked`.

Prints, on success:

  LOCK_CDO PASS classes=<n> explicit_false=<n> one_false_class=<name> placed_false=33/33

and exits non-zero on any violation (fail closed).

Run:
  python3 build/qa/w10/check_lock_cdo.py
  python3 build/qa/w10/check_lock_cdo.py --root /home/john/Projects/TAT-2
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# --- expectations, pinned in the script (not read from the dump) --------------
EXPECTED_CLASSES_WITH_LOCK_CONFIG = 31
EXPECTED_EXPLICIT_FALSE = 34  # 33 placed instances + 1 CDO (BP_SlidingWindow_Base_C)
EXPECTED_EXPLICIT_TRUE = (
    3  # BP_Dumbwaiter_C, BP_Urban_Window_4x6_C, BP_Urban_Ext_BayWindow_C
)
EXPECTED_FALSE_CLASS = "BP_SlidingWindow_Base_C"
EXPECTED_FALSE_CLASS_PLACEMENTS = 0
EXPECTED_PLACED_FALSE = (
    33  # explicit false placements; the resolved-false total must equal it
)
PRISON_MAP = "Maps/Buildings/Guildhall/Building_Guildhall_POI.json"
PRISON_ACTOR = "StaticMeshActor_528"
PRISON_KEY = "Item.Key.Buildings.Guildhall"

TRAILING_INDEX_RE = re.compile(r"\.\d+$")


def _object_path(value):
    """`ObjectPath` of a dump reference, or None."""
    if isinstance(value, dict):
        path = value.get("ObjectPath")
        if isinstance(path, str) and path:
            return path
    elif isinstance(value, str) and value:
        return value
    return None


def _package_of(object_path):
    """Package path of an object path (`/Game/X/BP_Y.6` -> `/Game/X/BP_Y`)."""
    if not object_path:
        return None
    return TRAILING_INDEX_RE.sub("", object_path)


def _scan(root):
    """One pass over the dump: class records + placed lock actors."""
    classes = {}
    placements = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in filenames:
            if not filename.endswith(".json"):
                continue
            path = os.path.join(dirpath, filename)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    doc = json.load(handle)
            except (OSError, ValueError):
                continue
            if not isinstance(doc, list):
                continue
            # Index the CDOs once per document (a file can hold thousands of
            # objects; the class loop must not rescan it).
            cdo_props = {}
            first_cdo_props = None
            for inner in doc:
                if not isinstance(inner, dict):
                    continue
                inner_name = str(inner.get("Name") or "")
                if not inner_name.startswith("Default__"):
                    continue
                props = inner.get("Properties")
                if not isinstance(props, dict) or "_lockConfig" not in props:
                    continue
                cdo_props[inner_name] = props
                if first_cdo_props is None:
                    first_cdo_props = props
            for obj in doc:
                if not isinstance(obj, dict):
                    continue
                if obj.get("Type") == "BlueprintGeneratedClass":
                    package = obj.get("Package")
                    if not isinstance(package, str) or not package:
                        continue
                    name = str(obj.get("Name") or "")
                    props = cdo_props.get("Default__" + name, first_cdo_props)
                    classes[package] = {
                        "name": name,
                        "package": package,
                        "file": rel,
                        "super": _package_of(_object_path(obj.get("Super"))),
                        "native": (obj.get("SuperStruct") or {}).get("ObjectName")
                        if isinstance(obj.get("SuperStruct"), dict)
                        else None,
                        "lock_config": (props or {}).get("_lockConfig"),
                        "locked": (props or {}).get("_locked"),
                    }
                    continue
                if not rel.startswith("Maps/"):
                    continue
                props = obj.get("Properties")
                if not isinstance(props, dict) or "_lockConfig" not in props:
                    continue
                lock_config = props["_lockConfig"]
                if not isinstance(lock_config, dict):
                    continue
                placements.append(
                    {
                        "name": str(obj.get("Name") or ""),
                        "file": rel,
                        "lock_config": lock_config,
                        "template": _package_of(_object_path(obj.get("Template"))),
                        "locked": props.get("_locked"),
                    }
                )
    return classes, placements


def _resolve_can_be_lockpicked(package, classes):
    """Nearest explicit `CanBeLockpicked` up the Super/SuperStruct chain.

    Returns (value, chain, native_tail). `value` is None when no class in the
    chain authors the flag, i.e. the chain ends at a native class whose
    initialiser is not in the dump — the authored default (`true`) applies.
    """
    chain = []
    seen = 0
    while package and seen < 32:
        rec = classes.get(package)
        if rec is None:
            return None, chain, package
        chain.append(rec["name"])
        lock_config = rec["lock_config"]
        if isinstance(lock_config, dict) and "CanBeLockpicked" in lock_config:
            return lock_config["CanBeLockpicked"], chain, rec["native"]
        package = rec["super"]
        seen += 1
    native = classes[package]["native"] if package in classes else None
    return None, chain, native


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        default=None,
        help="repository root holding extracted/json (default: three levels above this script)",
    )
    args = parser.parse_args(argv)
    repo_root = (
        Path(args.root).resolve() if args.root else Path(__file__).resolve().parents[3]
    )
    dump = repo_root / "extracted" / "json"
    if not dump.is_dir():
        print(f"LOCK_CDO FAIL: dump directory not found: {dump}", file=sys.stderr)
        print(
            "  this gate needs the extracted UE dump (git-ignored); run it in the "
            "worktree or pass --root /home/john/Projects/TAT-2",
            file=sys.stderr,
        )
        return 2

    classes, placements = _scan(str(dump))
    failures = []

    def fail(message):
        failures.append(message)

    # --- census: classes that own a CDO `_lockConfig` ------------------------
    lock_classes = [
        rec for rec in classes.values() if isinstance(rec.get("lock_config"), dict)
    ]
    if len(lock_classes) != EXPECTED_CLASSES_WITH_LOCK_CONFIG:
        fail(
            "classes owning a CDO _lockConfig: %d (expected %d)"
            % (len(lock_classes), EXPECTED_CLASSES_WITH_LOCK_CONFIG)
        )

    # --- (i) resolved-value census: exactly one class resolves false ---------
    false_classes = []
    true_classes = []
    unresolved_classes = 0
    for rec in lock_classes:
        value, _chain, _native = _resolve_can_be_lockpicked(rec["package"], classes)
        if value is False:
            false_classes.append(rec)
        elif value is True:
            true_classes.append(rec["name"])
        else:
            unresolved_classes += 1
    false_names = sorted(rec["name"] for rec in false_classes)
    if false_names != [EXPECTED_FALSE_CLASS]:
        fail(
            "classes resolving CanBeLockpicked=false: %s (expected exactly [%r])"
            % (false_names, EXPECTED_FALSE_CLASS)
        )

    # (i) cont'd: the one false class must have zero DIRECT placements.
    false_packages = {rec["package"] for rec in false_classes}
    false_placements = [p for p in placements if p["template"] in false_packages]
    if len(false_placements) != EXPECTED_FALSE_CLASS_PLACEMENTS:
        fail(
            "direct placements of the class(es) resolving false (%s): %d (expected %d) — a "
            "class-level `false` with placed actors would need inheritance the producer "
            "cannot see"
            % (
                ", ".join(false_names) or "<none>",
                len(false_placements),
                EXPECTED_FALSE_CLASS_PLACEMENTS,
            )
        )

    # --- (ii) placed false is always authored explicitly --------------------
    placed_false = 0
    placed_resolved_false = 0
    placed_explicit_true = 0
    inherited_false = []
    for placement in placements:
        lock_config = placement["lock_config"]
        label = "%s (%s)" % (placement["name"], placement["file"])
        if "CanBeLockpicked" in lock_config:
            explicit = lock_config["CanBeLockpicked"]
            if explicit is False:
                placed_false += 1
                placed_resolved_false += 1
            elif explicit is True:
                placed_explicit_true += 1
            resolved = explicit
        else:
            value, _chain, _native = _resolve_can_be_lockpicked(
                placement["template"], classes
            )
            resolved = True if value is None else value
            if resolved is False:
                placed_resolved_false += 1
                inherited_false.append(label)
        if resolved is False and "CanBeLockpicked" not in lock_config:
            if label not in inherited_false:
                inherited_false.append(label)
    if placed_false != EXPECTED_PLACED_FALSE:
        fail(
            "placed actors authoring CanBeLockpicked=false explicitly: %d (expected %d)"
            % (placed_false, EXPECTED_PLACED_FALSE)
        )
    if inherited_false:
        fail(
            "%d placed actor(s) resolve false by INHERITANCE, not authored on the "
            "instance: %s"
            % (len(inherited_false), ", ".join(sorted(inherited_false)[:8]))
        )
    if placed_resolved_false != placed_false:
        fail(
            "placed resolved-false total %d != explicit-false total %d"
            % (placed_resolved_false, placed_false)
        )

    # --- explicit author census (the 37 expressions in re-1-locks §3.1) -----
    explicit_false_classes = 0
    explicit_true_classes = 0
    for rec in lock_classes:
        lock_config = rec["lock_config"]
        if "CanBeLockpicked" not in lock_config:
            continue
        value = lock_config["CanBeLockpicked"]
        if value is False:
            explicit_false_classes += 1
        elif value is True:
            explicit_true_classes += 1
    explicit_false = explicit_false_classes + placed_false
    explicit_true = explicit_true_classes + placed_explicit_true
    if explicit_false != EXPECTED_EXPLICIT_FALSE:
        fail(
            "explicit CanBeLockpicked=false authors in the dump: %d (expected %d)"
            % (explicit_false, EXPECTED_EXPLICIT_FALSE)
        )
    if explicit_true != EXPECTED_EXPLICIT_TRUE:
        fail(
            "explicit CanBeLockpicked=true authors in the dump: %d (expected %d)"
            % (explicit_true, EXPECTED_EXPLICIT_TRUE)
        )

    # --- (iii) the prison actor --------------------------------------------
    prison_path = dump / PRISON_MAP
    prison_hits = []
    try:
        with open(prison_path, "r", encoding="utf-8") as handle:
            prison_doc = json.load(handle)
    except (OSError, ValueError) as exc:
        fail("cannot read %s: %s" % (PRISON_MAP, exc))
        prison_doc = None
    if isinstance(prison_doc, list):
        prison_hits = [
            obj
            for obj in prison_doc
            if isinstance(obj, dict) and obj.get("Name") == PRISON_ACTOR
        ]
    if len(prison_hits) != 1:
        fail(
            "%s in %s: %d object(s) (expected exactly 1)"
            % (PRISON_ACTOR, PRISON_MAP, len(prison_hits))
        )
    prison_locked = None
    prison_key = ""
    prison_flag_present = None
    if len(prison_hits) == 1:
        props = prison_hits[0].get("Properties") or {}
        prison_locked = props.get("_locked") if isinstance(props, dict) else None
        lock_config = props.get("_lockConfig") if isinstance(props, dict) else None
        if not isinstance(lock_config, dict):
            fail("%s authors no _lockConfig dict" % PRISON_ACTOR)
            lock_config = {}
        key_tag = lock_config.get("KeyTag")
        if isinstance(key_tag, dict):
            prison_key = str(key_tag.get("TagName") or "")
        prison_flag_present = "CanBeLockpicked" in lock_config
        if prison_locked is not True:
            fail(
                "%s _locked=%r (expected True — re-1-locks.md §4.1)"
                % (PRISON_ACTOR, prison_locked)
            )
        if prison_key != PRISON_KEY:
            fail(
                "%s KeyTag.TagName=%r (expected %r)"
                % (PRISON_ACTOR, prison_key, PRISON_KEY)
            )
        if prison_flag_present:
            fail(
                "%s authors CanBeLockpicked (expected ABSENT: the un-authored "
                "value is the authored default true — re-1-locks.md §3.2)"
                % PRISON_ACTOR
            )

    # --- evidence block ------------------------------------------------------
    print("LOCK_CDO: classes with a CDO _lockConfig = %d" % len(lock_classes))
    print(
        "LOCK_CDO: explicit CanBeLockpicked authors = %d false / %d true "
        "(%d placed false + %d CDO false; %d placed true + %d CDO true)"
        % (
            explicit_false,
            explicit_true,
            placed_false,
            explicit_false_classes,
            placed_explicit_true,
            explicit_true_classes,
        )
    )
    print(
        "LOCK_CDO: resolved false classes = %s (direct placements %d); "
        "resolved true = %d; unresolved tail (native default) = %d"
        % (false_names, len(false_placements), len(true_classes), unresolved_classes)
    )
    print(
        "LOCK_CDO: placed lock actors = %d; explicit false = %d; resolved false = %d"
        % (len(placements), placed_false, placed_resolved_false)
    )
    print(
        "LOCK_CDO: %s _locked=%s key_tag=%s CanBeLockpicked_present=%s"
        % (PRISON_ACTOR, prison_locked, prison_key, prison_flag_present)
    )

    if failures:
        for message in failures:
            print("LOCK_CDO FAIL: " + message, file=sys.stderr)
        return 1

    print(
        "LOCK_CDO PASS classes=%d explicit_false=%d one_false_class=%s placed_false=%d/%d"
        % (
            len(lock_classes),
            explicit_false,
            false_names[0],
            placed_false,
            placed_resolved_false,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
