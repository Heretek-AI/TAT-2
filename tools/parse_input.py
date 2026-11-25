#!/usr/bin/env python3
"""Parse the shipped Enhanced Input assets into gameplay/input_actions.json.

The game's Enhanced Input is authored in 5 ``InputMappingContext`` assets and
65 ``InputAction`` assets under ``extracted/json/Gameplay/Input/**``. Nothing
else in the pipeline reads them, so the runtime's bindings were hand-written.
This producer turns the dumps into one deterministic table the runtime can read
instead: every context, every authored mapping row in source order, every
resolved trigger/modifier (with the authored properties kept verbatim), every
action's mappable-key metadata, and the two gamepad response curves.

Authored inputs
  extracted/json/Gameplay/Input/Character/IMC_Character.json            (76 rows)
  extracted/json/Gameplay/Input/Character/IMC_Character_ClimbTest.json  (69 rows, dev)
  extracted/json/Gameplay/Input/Character/IMC_Character_Testing.json    (77 rows, dev)
  extracted/json/Gameplay/Input/Map/IMC_MapTool.json                    (4 rows)
  extracted/json/Gameplay/Input/Radial/IMC_Radial.json                  (11 rows)
  extracted/json/Gameplay/Input/**/IA_*.json                            (65 actions)
  extracted/json/Gameplay/Input/Character/Curve_*.json                  (2 curves)

Each dump is a JSON list of exports of one package. Export 0 is the asset; a
reference such as ``/Game/Gameplay/Input/Character/IMC_Character.16`` names
export 16 of that package's own list. ``IMC_Character_ClimbTest`` references
objects in ``IMC_Character``'s package, so resolution is indexed per *package*
(the ObjectPath before the final dot), not per file.

Output
  <out-dir>/gameplay/input_actions.json

Shipping policy is the one hand-authored fact here: IMC_Character, IMC_Radial
and IMC_MapTool ship; IMC_Character_ClimbTest and IMC_Character_Testing are dev
contexts. No shipped asset references the two dev contexts, so the dumps carry
no machine-readable shipping flag. All counts are computed from the dumps.

``value_type``: the dump omits properties that equal the UE class default, so
57 of 65 actions carry no ``ValueType``. UInputAction's engine default is
Boolean, so an absent ValueType is reported as ``"Boolean"`` with
``"value_type_authored": false``; an authored value (Axis1D/Axis2D/Axis3D) is
reported verbatim with ``true``. No other property is synthesised.

``display_name``/``display_category`` are emitted verbatim from the settings
object by authored field name. All five shipped ``ActionPrimary`` settings
objects store the two fields transposed (DisplayName.Key is
``InputSetting.Category.Interaction`` while DisplayCategory.Key is
``InputSetting.PrimaryFire``); the other 17 settings objects are not. The
producer does not rewrite authored data, so consumers should resolve by
``display_name_key``/``display_category_key`` rather than trust the field name
for those actions. ``LocalizedString`` is identical to ``SourceString`` in all
44 authored LOCTABLE fields, so only the source string is emitted plus the KEY
and the ST_ table id.

JSON contract (schema ``tat2.input_actions/1``)::

  {
    "schema": "tat2.input_actions/1",
    "generated_by": "tools/parse_input.py",
    "source": "extracted/json/Gameplay/Input/**",
    "counts": {"contexts": 5, "shipping_contexts": 3, "shipping_mappings": 91,
               "shipping_actions": 52, "all_mappings": 237, "all_actions": 54,
               "actions_assets": 65, "curve_assets": 2},
    "contexts": {
      "IMC_Character": {
        "asset": "/Game/Gameplay/Input/Character/IMC_Character",
        "shipping": true,
        "source": "json/Gameplay/Input/Character/IMC_Character.json",
        "mappings": [
          {"action": "IA_Ability_Action_Primary",
           "action_path": "/Game/Gameplay/Input/Character/IA_Ability_Action_Primary.0",
           "key": "LeftMouseButton",
           "key_is_gamepad": false,
           "value_type": "Boolean",
           "trigger": {"type": "Hold", "hold_time": 0.2,
                       "path": "/Game/Gameplay/Input/Character/IMC_Character.16",
                       "properties": {"HoldTimeThreshold": 0.2}},
           "trigger_path": "/Game/Gameplay/Input/Character/IMC_Character.16",
           "modifiers": [{"type": "DeadZone", "lower": 0.18, "upper": 0.98,
                          "path": "/Game/Gameplay/Input/Character/IMC_Character.1",
                          "properties": {"LowerThreshold": 0.18,
                                         "UpperThreshold": 0.98}}],
           "chord_action": null,
           "player_mappable": true,
           "mappable_name": "ActionPrimary",
           "setting_behavior": "EPlayerMappableKeySettingBehaviors::InheritSettingsFromAction",
           "display_category": "Primary Fire",
           "display_name": "Interaction",
           "display_name_key": "InputSetting.Category.Interaction",
           "display_category_key": "InputSetting.PrimaryFire",
           "display_table": "/Game/StringTables/ST_Settings_Input.ST_Settings_Input",
           "mappable_settings_path": "/Game/Gameplay/Input/Character/IMC_Character.37"}
        ]
      }
    },
    "actions": {
      "IA_Ability_Action_Primary": {
        "asset": "/Game/Gameplay/Input/Character/IA_Ability_Action_Primary",
        "mappable_name": "ActionPrimary",
        "display_name": "Interaction",
        "display_category": "Primary Fire",
        "value_type": "Boolean",
        "value_type_authored": false,
        "contexts": ["IMC_Character"],
        "keys": ["LeftMouseButton", "Gamepad_RightTrigger"],
        "display_name_key": "InputSetting.Category.Interaction",
        "display_category_key": "InputSetting.PrimaryFire",
        "display_table": "/Game/StringTables/ST_Settings_Input.ST_Settings_Input",
        "mappable_settings_path": "/Game/Gameplay/Input/Character/IA_Ability_Action_Primary.1",
        "triggers": [],
        "properties": {"PlayerMappableKeySettings": {"ObjectName": "...",
                                                    "ObjectPath": "..."}}
      }
    },
    "curves": {
      "Curve_GamepadMoveThumbstickResponse": {
        "asset": "/Game/Gameplay/Input/Character/Curve_GamepadMoveThumbstickResponse",
        "keys": [{"time": 0.0, "value": 0.0, "interp_mode": "Linear",
                  "tangent_mode": "Auto", "ue_interp_mode": "RCIM_Linear",
                  "ue_tangent_mode": "RCTM_Auto", "arrive_tangent": -0.1314473,
                  "leave_tangent": 0.0, "arrive_tangent_weight": 0.0,
                  "leave_tangent_weight": 0.16666667,
                  "ue_tangent_weight_mode": "RCTWM_WeightedNone"}]
      }
    },
    "unresolved": []
  }

Rules the payload follows:

* one mapping row per authored ``Mappings`` entry, in source order, in every
  context; ``contexts`` itself is sorted by context name;
* ``trigger``/``modifiers`` are always resolved from the export table of the
  package named by the ObjectPath, and ``trigger_path``/``path`` are always
  kept so a consumer can re-derive them;
* ``type`` is the UE class short name without the ``InputTrigger`` /
  ``InputModifier`` prefix (``Hold``, ``Tap``, ``Pressed``, ``Released``,
  ``Down``, ``ChordAction`` / ``DeadZone``, ``Negate``, OSE and TAT classes
  keep their full name);
* authored properties are grouped on the object under their snake_case name
  (``HoldTimeThreshold`` -> ``hold_time``, ``LowerThreshold`` -> ``lower``) and
  the full authored dict is repeated under ``properties`` so nothing is
  dropped; object references become the referenced asset name plus a
  ``*_path`` companion; nested struct values are copied verbatim with their
  authored field names (``Scalar`` -> ``{"X": .., "Y": .., "Z": ..}``); an
  authored property whose snake_case name would collide with ``type``,
  ``path`` or ``properties`` is prefixed ``property_`` (``InputModifierDeadZone``
  authors ``Type = EDeadZoneType::Axial`` -> ``property_type``), so the class
  label is never overwritten;
* ``chord_action`` repeats the chord trigger's target action on the row;
* ``key_is_gamepad`` is derived from the ``Gamepad_`` key-name prefix;
* ``keys`` is first-seen order over contexts sorted by name, rows in source
  order; ``contexts`` on an action is sorted;
* a row carries at most one trigger (all 237 authored rows do); a row with
  more is rejected instead of being silently truncated;
* one authored ``InputModifierDeadZone`` object (``IMC_Character.3``) carries
  no ``Properties`` at all and is referenced by two rows in different
  contexts, so those modifiers expose ``type``/``path``/``properties: {}``
  and no ``lower``/``upper``; the engine default applies and the producer
  does not invent it;
* ``unresolved`` is always ``[]`` because any reference that cannot be
  resolved aborts the run with a non-zero exit;
* an unknown trigger/modifier class aborts the run (fail closed) rather than
  dropping the mapping;
* deterministic bytes: sorted collections, no timestamps, indent 2, trailing
  newline.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = "tat2.input_actions/1"
INPUT_REL = Path("json") / "Gameplay" / "Input"
REL_SOURCE = "extracted/json/Gameplay/Input/**"

# Hand-authored shipping policy (see module docstring).
SHIPPING_CONTEXTS = frozenset({"IMC_Character", "IMC_Radial", "IMC_MapTool"})
EXPECTED_CONTEXTS = frozenset(
    {
        "IMC_Character",
        "IMC_Character_ClimbTest",
        "IMC_Character_Testing",
        "IMC_MapTool",
        "IMC_Radial",
    }
)

# Every trigger class actually present (plus InputTriggerDown, which the
# contract names). An unlisted class is a hard failure.
TRIGGER_TYPES = {
    "InputTriggerChordAction": "ChordAction",
    "InputTriggerDown": "Down",
    "InputTriggerHold": "Hold",
    "InputTriggerPressed": "Pressed",
    "InputTriggerReleased": "Released",
    "InputTriggerTap": "Tap",
}

# Every modifier class actually authored on a mapping row.
MODIFIER_TYPES = {
    "InputModifierDeadZone": "DeadZone",
    "InputModifierFOVScaling": "FOVScaling",
    "InputModifierNegate": "Negate",
    "InputModifierResponseCurveExponential": "ResponseCurveExponential",
    "InputModifierScalar": "Scalar",
    "InputModifierSwizzleAxis": "SwizzleAxis",
    "OSEEnhancedInputFloatingThreshold1D": "OSEEnhancedInputFloatingThreshold1D",
    "OSEEnhancedInputGamepadEdgeAcceleration": "OSEEnhancedInputGamepadEdgeAcceleration",
    "OSEEnhancedInputModifierGamepadLookSensitivity": "OSEEnhancedInputModifierGamepadLookSensitivity",
    "OSEEnhancedInputModifierGamepadMoveSensitivity": "OSEEnhancedInputModifierGamepadMoveSensitivity",
    "OSEEnhancedInputModifierInvertGamepadLook": "OSEEnhancedInputModifierInvertGamepadLook",
    "OSEEnhancedInputModifierInvertMouseLook": "OSEEnhancedInputModifierInvertMouseLook",
    "OSEEnhancedInputModifierMouseLookSensitivity": "OSEEnhancedInputModifierMouseLookSensitivity",
    "OSEEnhancedInputModifierRequireSign": "OSEEnhancedInputModifierRequireSign",
    "OSEEnhancedInputMouseSmooth": "OSEEnhancedInputMouseSmooth",
    "OSEInputModifierGamepadLookSpeed": "OSEInputModifierGamepadLookSpeed",
    "OSEInputModifierResponseCurveAbsolute": "OSEInputModifierResponseCurveAbsolute",
    "TATEnhancedInputModifierGamepadLookSensitivity": "TATEnhancedInputModifierGamepadLookSensitivity",
    "TATEnhancedInputModifierGamepadLookSensitivityMultiplier": "TATEnhancedInputModifierGamepadLookSensitivityMultiplier",
    "TATEnhancedInputModifierMouseLookSensitivity": "TATEnhancedInputModifierMouseLookSensitivity",
    "TATEnhancedInputModifierMouseLookSensitivityMultiplier": "TATEnhancedInputModifierMouseLookSensitivityMultiplier",
}

TRIGGER_FIELD_RENAMES = {
    "AffectedChordAction": "chord_action",
    "ChordAction": "chord_action",
    "HoldTimeThreshold": "hold_time",
}
MODIFIER_FIELD_RENAMES = {
    "LowerThreshold": "lower",
    "UpperThreshold": "upper",
}

# Field names the described object already owns. An authored property that
# snake-cases onto one of these gets a "property_" prefix instead of silently
# overwriting the class label (InputModifierDeadZone authors Type =
# EDeadZoneType::Axial, which would otherwise replace type="DeadZone").
RESERVED_FIELDS = frozenset({"type", "path", "properties"})

_SNAKE_ACRONYM = re.compile(r"(.)([A-Z][a-z]+)")
_SNAKE_WORD = re.compile(r"([a-z0-9])([A-Z])")


class Fail(Exception):
    """A fail-closed condition; main() prints it to stderr and exits non-zero."""


def snake(name: str) -> str:
    """CamelCase/PascalCase -> snake_case (acronyms kept together)."""
    text = _SNAKE_ACRONYM.sub(r"\1_\2", name)
    text = _SNAKE_WORD.sub(r"\1_\2", text)
    return text.lower()


def ref_name(value: dict[str, Any]) -> str:
    """``InputAction'IA_Move'`` -> ``IA_Move`` (tolerates a plain name)."""
    object_name = value.get("ObjectName")
    if isinstance(object_name, str) and "'" in object_name:
        return object_name.rsplit("'", 2)[-2]
    if isinstance(object_name, str):
        return object_name
    path = value.get("ObjectPath") or ""
    return Path(path.rsplit(".", 1)[0]).name


def is_ref(value: Any) -> bool:
    return isinstance(value, dict) and isinstance(value.get("ObjectPath"), str)


def loc_string(block: Any) -> tuple[str | None, str | None, str | None]:
    """(text, loc key, table id) from a UE LOCTABLE text property dict."""
    if not isinstance(block, dict):
        return None, None, None
    text = block.get("LocalizedString")
    if not isinstance(text, str) or not text:
        text = block.get("SourceString")
    if not isinstance(text, str):
        text = None
    key = block.get("Key")
    table = block.get("TableId")
    return (
        text,
        key if isinstance(key, str) else None,
        table if isinstance(table, str) else None,
    )


def split_path(path: str) -> tuple[str, int]:
    package, _, index = path.rpartition(".")
    if not package or not index.isdigit():
        raise Fail(f"malformed ObjectPath {path!r} (expected <package>.<index>)")
    return package, int(index)


class AssetIndex:
    """Positional export tables keyed by package path, across the whole tree."""

    def __init__(self, extracted: Path) -> None:
        self.extracted = extracted
        self.root = extracted / INPUT_REL
        if not self.root.is_dir():
            raise Fail(f"input dump directory is missing: {self.root}")
        self.tables: dict[str, dict[int, dict[str, Any]]] = {}
        self.files: dict[str, Path] = {}
        for path in sorted(self.root.rglob("*.json")):
            self._load(path)
        if not self.tables:
            raise Fail(f"no JSON dumps under {self.root}")

    def _load(self, path: Path) -> None:
        rel = path.relative_to(self.extracted).as_posix()
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise Fail(f"{rel}: unreadable JSON: {exc}") from exc
        if not isinstance(data, list) or not data:
            raise Fail(f"{rel}: expected a non-empty JSON list of exports")
        package = next(
            (
                item["Package"]
                for item in data
                if isinstance(item, dict)
                and isinstance(item.get("Package"), str)
                and item["Package"]
            ),
            None,
        )
        if package is None:
            raise Fail(f"{rel}: no export carries a Package path")
        if package in self.tables:
            raise Fail(
                f"package {package} is dumped twice: "
                f"{self.files[package].name} and {path.name}"
            )
        self.tables[package] = {
            index: item for index, item in enumerate(data) if isinstance(item, dict)
        }
        self.files[package] = path
        # Inline subobjects omit Package; an export that claims a different
        # package would break positional resolution, so reject it.
        for index, item in enumerate(data):
            own = item.get("Package") if isinstance(item, dict) else None
            if isinstance(own, str) and own and own != package:
                raise Fail(
                    f"{rel}: export {index} claims package {own}, expected {package}"
                )

    def resolve(self, path: str, *, role: str, allowed: set[str]) -> dict[str, Any]:
        package, index = split_path(path)
        table = self.tables.get(package)
        if table is None:
            raise Fail(
                f"{role} {path}: package {package} has no dump under {self.root}"
            )
        item = table.get(index)
        if item is None:
            raise Fail(
                f"{role} {path}: export index {index} is not present in "
                f"{self.files[package].name} ({len(table)} exports)"
            )
        kind = item.get("Type")
        if not isinstance(kind, str) or kind not in allowed:
            raise Fail(
                f"{role} {path}: unexpected class {kind!r} in "
                f"{self.files[package].name}"
            )
        return item

    def exports(self, kind: str) -> dict[str, tuple[str, dict[str, Any]]]:
        """name -> (package, export) for every export of ``kind``."""
        found: dict[str, tuple[str, dict[str, Any]]] = {}
        for package, table in self.tables.items():
            for index in sorted(table):
                item = table[index]
                if item.get("Type") != kind:
                    continue
                name = item.get("Name")
                if not isinstance(name, str) or not name:
                    raise Fail(f"{package}.{index}: {kind} export has no Name")
                if name in found:
                    raise Fail(f"{kind} {name} appears in two packages")
                found[name] = (package, item)
        return found


def describe(
    item: dict[str, Any],
    path: str,
    kind: str,
    labels: dict[str, str],
    renames: dict[str, str],
) -> dict[str, Any]:
    """Group authored properties on a trigger/modifier object (nothing dropped)."""
    properties = item.get("Properties")
    if properties is None:
        properties = {}
    if not isinstance(properties, dict):
        raise Fail(f"{kind} {path}: Properties is not an object")
    described: dict[str, Any] = {"type": labels[item["Type"]]}
    for key, value in properties.items():
        field = renames.get(key, snake(key))
        if field in RESERVED_FIELDS:
            field = f"property_{field}"
        if field in described:
            raise Fail(f"{kind} {path}: two authored properties map to {field!r}")
        if is_ref(value):
            described[field] = ref_name(value)
            described[f"{field}_path"] = value["ObjectPath"]
        else:
            described[field] = value
    described["path"] = path
    described["properties"] = properties
    return described


def build(extracted: Path) -> dict[str, Any]:
    if not SHIPPING_CONTEXTS <= EXPECTED_CONTEXTS:
        raise Fail("SHIPPING_CONTEXTS must be a subset of EXPECTED_CONTEXTS")
    index = AssetIndex(extracted)

    # --- contexts -----------------------------------------------------------
    found_contexts: dict[str, tuple[str, dict[str, Any], Path]] = {}
    for package, table in index.tables.items():
        head = table.get(0)
        if not isinstance(head, dict) or head.get("Type") != "InputMappingContext":
            continue
        name = head.get("Name")
        if not isinstance(name, str) or not name:
            raise Fail(f"{package}: InputMappingContext export has no Name")
        if name in found_contexts:
            raise Fail(f"input mapping context {name} is dumped twice")
        found_contexts[name] = (package, head, index.files[package])

    missing = sorted(EXPECTED_CONTEXTS - set(found_contexts))
    if missing:
        raise Fail(f"missing input mapping context asset(s): {', '.join(missing)}")
    unexpected = sorted(set(found_contexts) - EXPECTED_CONTEXTS)
    if unexpected:
        raise Fail(
            "unexpected input mapping context(s): "
            f"{', '.join(unexpected)}; add them to EXPECTED_CONTEXTS and "
            "SHIPPING_CONTEXTS deliberately"
        )

    # --- actions and curves -------------------------------------------------
    action_exports = index.exports("InputAction")
    if not action_exports:
        raise Fail("no InputAction assets found")
    curve_exports = index.exports("CurveFloat")
    if not curve_exports:
        raise Fail("no CurveFloat assets found")

    actions: dict[str, dict[str, Any]] = {}
    action_settings: dict[
        str, tuple[str | None, str | None, str | None, str | None]
    ] = {}
    for name in sorted(action_exports):
        package, item = action_exports[name]
        properties = item.get("Properties")
        if properties is None:
            properties = {}
        if not isinstance(properties, dict):
            raise Fail(f"InputAction {name}: Properties is not an object")

        authored_type = properties.get("ValueType")
        if isinstance(authored_type, str) and authored_type:
            value_type = authored_type.rsplit("::", 1)[-1]
            value_type_authored = True
        else:
            value_type = "Boolean"  # UInputAction's engine default (see docstring)
            value_type_authored = False

        settings_path = None
        mappable_name = None
        display_name = display_category = None
        display_name_key = display_category_key = display_table = None
        settings_ref = properties.get("PlayerMappableKeySettings")
        if is_ref(settings_ref):
            settings_path = settings_ref["ObjectPath"]
            settings = index.resolve(
                settings_path,
                role=f"InputAction {name} settings",
                allowed={"PlayerMappableKeySettings"},
            )
            sp = settings.get("Properties")
            if sp is None:
                sp = {}
            if not isinstance(sp, dict):
                raise Fail(f"InputAction {name}: settings Properties is not an object")
            mappable_name = sp.get("Name")
            display_name, display_name_key, display_table = loc_string(
                sp.get("DisplayName")
            )
            display_category, display_category_key, _ = loc_string(
                sp.get("DisplayCategory")
            )
        action_settings[name] = (
            settings_path,
            mappable_name if isinstance(mappable_name, str) else None,
            display_name,
            display_category,
        )

        described_triggers = []
        for trigger_ref in properties.get("Triggers") or []:
            if not is_ref(trigger_ref):
                raise Fail(f"InputAction {name}: malformed Triggers entry")
            path = trigger_ref["ObjectPath"]
            trigger = index.resolve(
                path, role=f"InputAction {name} trigger", allowed=set(TRIGGER_TYPES)
            )
            described_triggers.append(
                describe(
                    trigger,
                    path,
                    "InputAction trigger",
                    TRIGGER_TYPES,
                    TRIGGER_FIELD_RENAMES,
                )
            )

        actions[name] = {
            "asset": package,
            "mappable_name": action_settings[name][1],
            "display_name": display_name,
            "display_category": display_category,
            "value_type": value_type,
            "value_type_authored": value_type_authored,
            "contexts": [],
            "keys": [],
            "display_name_key": display_name_key,
            "display_category_key": display_category_key,
            "display_table": display_table,
            "mappable_settings_path": settings_path,
            "triggers": described_triggers,
            "properties": properties,
        }

    # --- curves -------------------------------------------------------------
    curves: dict[str, dict[str, Any]] = {}
    for name in sorted(curve_exports):
        package, item = curve_exports[name]
        properties = item.get("Properties")
        if not isinstance(properties, dict):
            raise Fail(f"CurveFloat {name}: Properties is not an object")
        float_curve = properties.get("FloatCurve")
        if not isinstance(float_curve, dict):
            raise Fail(f"CurveFloat {name}: FloatCurve is missing")
        raw_keys = float_curve.get("Keys")
        if not isinstance(raw_keys, list) or not raw_keys:
            raise Fail(f"CurveFloat {name}: no authored keys")
        keys = []
        for position, key in enumerate(raw_keys):
            if not isinstance(key, dict):
                raise Fail(f"CurveFloat {name}: key {position} is not an object")
            for required in ("Time", "Value"):
                if not isinstance(key.get(required), (int, float)):
                    raise Fail(f"CurveFloat {name}: key {position} has no {required}")
            interp = key.get("InterpMode")
            tangent = key.get("TangentMode")
            keys.append(
                {
                    "time": key["Time"],
                    "value": key["Value"],
                    "interp_mode": interp.rsplit("_", 1)[-1]
                    if isinstance(interp, str)
                    else None,
                    "tangent_mode": tangent.rsplit("_", 1)[-1]
                    if isinstance(tangent, str)
                    else None,
                    "ue_interp_mode": interp,
                    "ue_tangent_mode": tangent,
                    "arrive_tangent": key.get("ArriveTangent"),
                    "leave_tangent": key.get("LeaveTangent"),
                    "arrive_tangent_weight": key.get("ArriveTangentWeight"),
                    "leave_tangent_weight": key.get("LeaveTangentWeight"),
                    "ue_tangent_weight_mode": key.get("TangentWeightMode"),
                }
            )
        curves[name] = {"asset": package, "keys": keys}

    # --- mappings -----------------------------------------------------------
    contexts: dict[str, dict[str, Any]] = {}
    for name in sorted(found_contexts):
        package, head, path = found_contexts[name]
        properties = head.get("Properties")
        if not isinstance(properties, dict):
            raise Fail(f"InputMappingContext {name}: Properties is missing")
        raw_mappings = properties.get("Mappings")
        if not isinstance(raw_mappings, list) or not raw_mappings:
            raise Fail(f"InputMappingContext {name}: no authored mapping rows")

        rows = []
        for row_index, row in enumerate(raw_mappings):
            where = f"{name} row {row_index}"
            if not isinstance(row, dict):
                raise Fail(f"{where}: mapping is not an object")
            action_ref = row.get("Action")
            if not is_ref(action_ref):
                raise Fail(f"{where}: Action reference is missing")
            action_path = action_ref["ObjectPath"]
            action = index.resolve(
                action_path, role=f"{where} action", allowed={"InputAction"}
            )
            action_name = action.get("Name")
            if not isinstance(action_name, str) or action_name not in actions:
                raise Fail(
                    f"{where}: action {action_path} is not an indexed InputAction"
                )

            key_block = row.get("Key")
            key_name = key_block.get("KeyName") if isinstance(key_block, dict) else None
            if not isinstance(key_name, str) or not key_name:
                raise Fail(f"{where}: Key.KeyName is missing")

            trigger_refs = row.get("Triggers") or []
            if not isinstance(trigger_refs, list):
                raise Fail(f"{where}: Triggers is not a list")
            if len(trigger_refs) > 1:
                raise Fail(
                    f"{where}: {len(trigger_refs)} triggers authored; the "
                    "tat2.input_actions/1 row contract holds at most one"
                )
            trigger = None
            trigger_path = None
            if trigger_refs:
                trigger_ref = trigger_refs[0]
                if not is_ref(trigger_ref):
                    raise Fail(f"{where}: malformed trigger reference")
                trigger_path = trigger_ref["ObjectPath"]
                resolved = index.resolve(
                    trigger_path, role=f"{where} trigger", allowed=set(TRIGGER_TYPES)
                )
                trigger = describe(
                    resolved,
                    trigger_path,
                    f"{where} trigger",
                    TRIGGER_TYPES,
                    TRIGGER_FIELD_RENAMES,
                )

            modifiers = []
            modifier_refs = row.get("Modifiers") or []
            if not isinstance(modifier_refs, list):
                raise Fail(f"{where}: Modifiers is not a list")
            for modifier_ref in modifier_refs:
                if not is_ref(modifier_ref):
                    raise Fail(f"{where}: malformed modifier reference")
                modifier_path = modifier_ref["ObjectPath"]
                resolved = index.resolve(
                    modifier_path,
                    role=f"{where} modifier",
                    allowed=set(MODIFIER_TYPES),
                )
                modifiers.append(
                    describe(
                        resolved,
                        modifier_path,
                        f"{where} modifier",
                        MODIFIER_TYPES,
                        MODIFIER_FIELD_RENAMES,
                    )
                )

            settings_ref = row.get("PlayerMappableKeySettings")
            mappable_settings_path = None
            mappable_name = action_settings[action_name][1]
            display_name = actions[action_name]["display_name"]
            display_category = actions[action_name]["display_category"]
            display_name_key = actions[action_name]["display_name_key"]
            display_category_key = actions[action_name]["display_category_key"]
            display_table = actions[action_name]["display_table"]
            if is_ref(settings_ref):
                mappable_settings_path = settings_ref["ObjectPath"]
                settings = index.resolve(
                    mappable_settings_path,
                    role=f"{where} settings",
                    allowed={"PlayerMappableKeySettings"},
                )
                sp = settings.get("Properties")
                if sp is None:
                    sp = {}
                if not isinstance(sp, dict):
                    raise Fail(f"{where}: settings Properties is not an object")
                if isinstance(sp.get("Name"), str):
                    mappable_name = sp["Name"]
                text, key, table = loc_string(sp.get("DisplayName"))
                if text is not None:
                    display_name, display_name_key = text, key
                if table is not None:
                    display_table = table
                text, key, table = loc_string(sp.get("DisplayCategory"))
                if text is not None:
                    display_category, display_category_key = text, key
                if table is not None:
                    display_table = table

            setting_behavior = row.get("SettingBehavior")
            rows.append(
                {
                    "action": action_name,
                    "action_path": action_path,
                    "key": key_name,
                    "key_is_gamepad": key_name.startswith("Gamepad_"),
                    "value_type": actions[action_name]["value_type"],
                    "trigger": trigger,
                    "trigger_path": trigger_path,
                    "modifiers": modifiers,
                    "chord_action": trigger.get("chord_action") if trigger else None,
                    "player_mappable": bool(mappable_settings_path),
                    "mappable_name": mappable_name,
                    "setting_behavior": setting_behavior,
                    "display_category": display_category,
                    "display_name": display_name,
                    "display_name_key": display_name_key,
                    "display_category_key": display_category_key,
                    "display_table": display_table,
                    "mappable_settings_path": mappable_settings_path,
                }
            )

            entry = actions[action_name]
            if name not in entry["contexts"]:
                entry["contexts"].append(name)
            if key_name not in entry["keys"]:
                entry["keys"].append(key_name)

        contexts[name] = {
            "asset": package,
            "shipping": name in SHIPPING_CONTEXTS,
            "source": path.relative_to(extracted).as_posix(),
            "mappings": rows,
        }

    # --- counts (computed) --------------------------------------------------
    shipping_names = [name for name in contexts if contexts[name]["shipping"]]
    all_mappings = sum(len(c["mappings"]) for c in contexts.values())
    shipping_mappings = sum(len(contexts[name]["mappings"]) for name in shipping_names)
    all_row_actions = {
        row["action_path"]
        for context in contexts.values()
        for row in context["mappings"]
    }
    shipping_row_actions = {
        row["action_path"]
        for name in shipping_names
        for row in contexts[name]["mappings"]
    }

    return {
        "schema": SCHEMA,
        "generated_by": "tools/parse_input.py",
        "source": REL_SOURCE,
        "counts": {
            "contexts": len(contexts),
            "shipping_contexts": len(shipping_names),
            "shipping_mappings": shipping_mappings,
            "shipping_actions": len(shipping_row_actions),
            "all_mappings": all_mappings,
            "all_actions": len(all_row_actions),
            "actions_assets": len(actions),
            "curve_assets": len(curves),
        },
        "contexts": contexts,
        "actions": actions,
        "curves": curves,
        "unresolved": [],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Parse Enhanced Input dumps into gameplay/input_actions.json"
    )
    parser.add_argument(
        "--extracted",
        type=Path,
        default=ROOT / "extracted",
        help="extracted asset root (default: <repo>/extracted)",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=ROOT / "game" / "data" / "generated",
        help="generated output root (default: <repo>/game/data/generated)",
    )
    parser.add_argument(
        "--quiet", action="store_true", help="suppress the success summary"
    )
    args = parser.parse_args(argv)

    try:
        payload = build(args.extracted)
    except Fail as exc:
        print(f"parse_input: FAIL-CLOSED: {exc}", file=sys.stderr)
        return 1

    out_path = args.out_dir / "gameplay" / "input_actions.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(payload, indent=2, allow_nan=False) + "\n", encoding="utf-8"
    )
    if not args.quiet:
        counts = payload["counts"]
        print(
            "wrote gameplay/input_actions.json "
            f"(contexts={counts['contexts']}, "
            f"shipping={counts['shipping_mappings']} mappings / "
            f"{counts['shipping_actions']} actions, "
            f"all={counts['all_mappings']} mappings / "
            f"{counts['all_actions']} actions, "
            f"{counts['actions_assets']} action assets, "
            f"{counts['curve_assets']} curves)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
