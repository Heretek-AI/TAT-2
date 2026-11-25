#!/usr/bin/env python3
"""Tests for tools/parse_input.py (stdlib only).

Run with: ``python3 tools/test_parse_input.py``

Two halves:

* a synthetic ``extracted/json/Gameplay/Input`` tree in a
  ``tempfile.TemporaryDirectory`` that pins every contract rule the shipped
  dumps do not exercise on their own (cross-package ObjectPath resolution, an
  export without ``Properties``, unknown classes, unresolved references,
  missing contexts) plus byte-for-byte determinism;
* one read-only end-to-end run against the real ``extracted/`` tree, asserting
  the measured shipped numbers (5 contexts / 3 shipping / 91 shipping rows /
  52 shipping actions / 237 rows / 54 actions / 65 action assets / 2 curves).

The producer is always invoked with an explicit ``--out-dir``; the test never
writes into ``game/data`` or ``extracted/``.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_input.py"
REAL = ROOT / "extracted"
REL_INPUT = Path("json") / "Gameplay" / "Input"

CHAR = "/Game/Gameplay/Input/Character"
MAP = "/Game/Gameplay/Input/Map"
RADIAL = "/Game/Gameplay/Input/Radial"


def _json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")


def _ref(kind: str, name: str, path: str) -> dict:
    return {"ObjectName": f"{kind}'{name}'", "ObjectPath": path}


def _loc(text: str, key: str) -> dict:
    return {
        "TableId": "/Game/StringTables/ST_Settings_Input.ST_Settings_Input",
        "Key": key,
        "SourceString": text,
        "LocalizedString": text,
    }


def _settings(name: str, display_name: str, display_category: str) -> dict:
    """A PlayerMappableKeySettings export (display fields explicit)."""
    return {
        "Type": "PlayerMappableKeySettings",
        "Name": name,
        "Class": "UScriptClass'PlayerMappableKeySettings'",
        "Properties": {
            "Name": name,
            "DisplayName": _loc(display_name[0], display_name[1]),
            "DisplayCategory": _loc(display_category[0], display_category[1]),
        },
    }


def _row(
    action: str,
    key: str,
    *,
    triggers: list[dict] | None = None,
    modifiers: list[dict] | None = None,
    settings: dict | None = None,
    behavior: str = "EPlayerMappableKeySettingBehaviors::InheritSettingsFromAction",
) -> dict:
    return {
        "Triggers": triggers or [],
        "Modifiers": modifiers or [],
        "Action": _ref(
            "InputAction", action.rsplit("/", 1)[-1].rsplit(".", 1)[0], action
        ),
        "Key": {"KeyName": key},
        "SettingBehavior": behavior,
        "PlayerMappableKeySettings": settings,
    }


def _imc(
    name: str, package_dir: str, rows: list[dict], extra: list[dict]
) -> list[dict]:
    package = f"{package_dir}/{name}"
    head = {
        "Type": "InputMappingContext",
        "Name": name,
        "Class": "UScriptClass'InputMappingContext'",
        "Package": package,
        "Properties": {"Mappings": rows},
    }
    return [head, *extra]


def _action(name: str, package_dir: str, properties: dict | None = None) -> list[dict]:
    package = f"{package_dir}/{name}"
    export = {
        "Type": "InputAction",
        "Name": name,
        "Class": "UScriptClass'InputAction'",
        "Package": package,
    }
    if properties is not None:
        export["Properties"] = properties
    return [export]


def _build_fixture(base: Path) -> Path:
    """Build a complete synthetic input tree; returns the --extracted root."""
    extracted = base / "extracted"
    inp = extracted / REL_INPUT
    character = inp / "Character"
    map_dir = inp / "Map"
    radial = inp / "Radial"

    primary = f"{CHAR}/IA_Ability_Action_Primary.0"
    primary_hold = f"{CHAR}/IA_Ability_Action_Primary_Hold.0"
    prevent_look = f"{CHAR}/IA_PreventLookGamepad.0"
    shoulder = f"{CHAR}/IA_ControllerLeftShoulder.0"
    move = f"{CHAR}/IA_Move.0"
    radial_dir = f"{RADIAL}/IA_Radial_Directional.0"
    map_prev = f"{MAP}/IA_MapSwitch_Prev.0"
    testing = f"{CHAR}/IA_TestingThing.0"

    # IMC_Character: 5 rows; refs are later exports of its own package.
    _json(
        character / "IMC_Character.json",
        _imc(
            "IMC_Character",
            CHAR,
            [
                # 0: mappable, no trigger/modifier (the contract's example row).
                _row(
                    primary,
                    "LeftMouseButton",
                    settings=_ref(
                        "PlayerMappableKeySettings",
                        "IMC_Character:PlayerMappableKeySettings_10",
                        f"{CHAR}/IMC_Character.1",
                    ),
                ),
                # 1: same action on a gamepad key, no row settings.
                _row(primary, "Gamepad_RightTrigger"),
                # 2: Hold trigger.
                _row(
                    primary_hold,
                    "LeftMouseButton",
                    triggers=[
                        _ref(
                            "InputTriggerHold",
                            "IMC_Character:InputTriggerHold_0",
                            f"{CHAR}/IMC_Character.2",
                        )
                    ],
                ),
                # 3: DeadZone modifier.
                _row(
                    primary,
                    "Mouse2D",
                    modifiers=[
                        _ref(
                            "InputModifierDeadZone",
                            "IMC_Character:InputModifierDeadZone_0",
                            f"{CHAR}/IMC_Character.3",
                        )
                    ],
                ),
                # 4: chord trigger.
                _row(
                    prevent_look,
                    "Gamepad_Right2D",
                    triggers=[
                        _ref(
                            "InputTriggerChordAction",
                            "IMC_Character:InputTriggerChordAction_0",
                            f"{CHAR}/IMC_Character.4",
                        )
                    ],
                ),
            ],
            [
                # Deliberately transposed, mirroring the shipped ActionPrimary.
                _settings(
                    "ActionPrimary",
                    ("Interaction", "InputSetting.Category.Interaction"),
                    ("Primary Fire", "InputSetting.PrimaryFire"),
                ),
                {
                    "Type": "InputTriggerHold",
                    "Name": "InputTriggerHold_0",
                    "Properties": {"HoldTimeThreshold": 0.2},
                },
                {
                    "Type": "InputModifierDeadZone",
                    "Name": "InputModifierDeadZone_0",
                    "Properties": {"LowerThreshold": 0.18, "UpperThreshold": 0.98},
                },
                {
                    "Type": "InputTriggerChordAction",
                    "Name": "InputTriggerChordAction_0",
                    "Properties": {
                        "ChordAction": _ref(
                            "InputAction", "IA_ControllerLeftShoulder", shoulder
                        )
                    },
                },
            ],
        ),
    )

    # ClimbTest: row 0 resolves a trigger in IMC_Character's package; row 1
    # resolves an export of its own file that has no "Properties" key at all.
    _json(
        character / "IMC_Character_ClimbTest.json",
        _imc(
            "IMC_Character_ClimbTest",
            CHAR,
            [
                _row(
                    move,
                    "W",
                    triggers=[
                        _ref(
                            "InputTriggerHold",
                            "IMC_Character:InputTriggerHold_0",
                            f"{CHAR}/IMC_Character.2",
                        )
                    ],
                ),
                _row(
                    primary,
                    "Gamepad_RightTrigger",
                    triggers=[
                        _ref(
                            "InputTriggerPressed",
                            "IMC_Character_ClimbTest:InputTriggerPressed_0",
                            f"{CHAR}/IMC_Character_ClimbTest.1",
                        )
                    ],
                ),
            ],
            [{"Type": "InputTriggerPressed", "Name": "InputTriggerPressed_0"}],
        ),
    )

    _json(
        character / "IMC_Character_Testing.json",
        _imc("IMC_Character_Testing", CHAR, [_row(testing, "LeftMouseButton")], []),
    )

    _json(
        map_dir / "IMC_MapTool.json",
        _imc("IMC_MapTool", MAP, [_row(map_prev, "Gamepad_DPad_Up")], []),
    )

    _json(
        radial / "IMC_Radial.json",
        _imc(
            "IMC_Radial",
            RADIAL,
            [
                _row(
                    radial_dir,
                    "Gamepad_Right2D",
                    modifiers=[
                        _ref(
                            "InputModifierDeadZone",
                            "IMC_Radial:InputModifierDeadZone_0",
                            f"{RADIAL}/IMC_Radial.1",
                        )
                    ],
                )
            ],
            [
                {
                    "Type": "InputModifierDeadZone",
                    "Name": "InputModifierDeadZone_0",
                    "Properties": {
                        "LowerThreshold": 0.25,
                        "UpperThreshold": 0.95,
                        "Type": "EDeadZoneType::Axial",
                    },
                }
            ],
        ),
    )

    # Actions: one export each, one with its own settings object.
    _json(
        character / "IA_Ability_Action_Primary.json",
        [
            {
                "Type": "InputAction",
                "Name": "IA_Ability_Action_Primary",
                "Class": "UScriptClass'InputAction'",
                "Package": f"{CHAR}/IA_Ability_Action_Primary",
                "Properties": {
                    "PlayerMappableKeySettings": _ref(
                        "PlayerMappableKeySettings",
                        "IA_Ability_Action_Primary:PlayerMappableKeySettings_10",
                        f"{CHAR}/IA_Ability_Action_Primary.1",
                    )
                },
            },
            _settings(
                "ActionPrimary",
                ("Interaction", "InputSetting.Category.Interaction"),
                ("Primary Fire", "InputSetting.PrimaryFire"),
            ),
        ],
    )
    _json(
        character / "IA_Ability_Action_Primary_Hold.json",
        _action(
            "IA_Ability_Action_Primary_Hold",
            CHAR,
            {"ValueType": "EInputActionValueType::Axis1D"},
        ),
    )
    _json(
        character / "IA_ControllerLeftShoulder.json",
        _action(
            "IA_ControllerLeftShoulder",
            CHAR,
            {"ValueType": "EInputActionValueType::Boolean"},
        ),
    )
    _json(
        character / "IA_PreventLookGamepad.json",
        _action(
            "IA_PreventLookGamepad",
            CHAR,
            {"ValueType": "EInputActionValueType::Axis2D"},
        ),
    )
    _json(
        character / "IA_Move.json",
        _action("IA_Move", CHAR, {"ValueType": "EInputActionValueType::Axis2D"}),
    )
    _json(character / "IA_TestingThing.json", _action("IA_TestingThing", CHAR))
    _json(
        radial / "IA_Radial_Directional.json",
        _action(
            "IA_Radial_Directional",
            RADIAL,
            {"ValueType": "EInputActionValueType::Axis2D"},
        ),
    )
    _json(map_dir / "IA_MapSwitch_Prev.json", _action("IA_MapSwitch_Prev", MAP))

    _json(
        character / "Curve_GamepadMoveThumbstickResponse.json",
        [
            {
                "Type": "CurveFloat",
                "Name": "Curve_GamepadMoveThumbstickResponse",
                "Class": "UScriptClass'CurveFloat'",
                "Package": f"{CHAR}/Curve_GamepadMoveThumbstickResponse",
                "Properties": {
                    "FloatCurve": {
                        "Keys": [
                            {
                                "InterpMode": "RCIM_Linear",
                                "TangentMode": "RCTM_Auto",
                                "TangentWeightMode": "RCTWM_WeightedNone",
                                "Time": 0.0,
                                "Value": 0.0,
                                "ArriveTangent": -0.1314473,
                                "ArriveTangentWeight": 0.0,
                                "LeaveTangent": 0.0,
                                "LeaveTangentWeight": 0.16666667,
                            }
                        ]
                    }
                },
            }
        ],
    )
    return extracted


def _run(
    extracted: Path,
    out_dir: Path,
    *,
    expect: int = 0,
    contains: str | None = None,
) -> subprocess.CompletedProcess:
    cmd = [
        sys.executable,
        str(PRODUCER),
        "--extracted",
        str(extracted),
        "--out-dir",
        str(out_dir),
        "--quiet",
    ]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=False)
    output = proc.stdout + proc.stderr
    if proc.returncode != expect:
        raise AssertionError(
            f"expected exit {expect}, got {proc.returncode}\n"
            f"command: {' '.join(cmd)}\n{output}"
        )
    if contains is not None and contains not in output:
        raise AssertionError(f"missing {contains!r} in producer output:\n{output}")
    return proc


def _load(out_dir: Path) -> dict:
    path = out_dir / "gameplay" / "input_actions.json"
    if not path.is_file():
        raise AssertionError(f"producer wrote no {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _check(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def _eq(actual, expected, msg: str) -> None:
    if actual != expected:
        raise AssertionError(f"{msg}: expected {expected!r}, got {actual!r}")


def _row_named(payload: dict, context: str, action: str, key: str) -> dict:
    for row in payload["contexts"][context]["mappings"]:
        if row["action"] == action and row["key"] == key:
            return row
    raise AssertionError(f"{context}: no row {action} / {key}")


def main() -> int:
    checks = 0
    try:
        with tempfile.TemporaryDirectory(prefix="tat2-input-fixture-") as td:
            base = Path(td)
            extracted = _build_fixture(base)
            out = base / "out"
            _run(extracted, out)
            payload = _load(out)

            # --- contract shape -------------------------------------------------
            _eq(payload["schema"], "tat2.input_actions/1", "schema")
            _eq(payload["generated_by"], "tools/parse_input.py", "generated_by")
            _eq(payload["source"], "extracted/json/Gameplay/Input/**", "source")
            _eq(payload["unresolved"], [], "unresolved")
            _eq(
                sorted(
                    p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()
                ),
                ["gameplay/input_actions.json"],
                "producer wrote only the documented output",
            )

            counts = payload["counts"]
            _eq(counts["contexts"], 5, "fixture contexts")
            _eq(counts["shipping_contexts"], 3, "fixture shipping contexts")
            _eq(counts["shipping_mappings"], 7, "fixture shipping mappings")
            _eq(counts["shipping_actions"], 5, "fixture shipping actions")
            _eq(counts["all_mappings"], 10, "fixture all mappings")
            _eq(counts["all_actions"], 7, "fixture all actions")
            _eq(counts["actions_assets"], 8, "fixture action assets")
            _eq(counts["curve_assets"], 1, "fixture curve assets")

            flags = {name: ctx["shipping"] for name, ctx in payload["contexts"].items()}
            _eq(
                flags,
                {
                    "IMC_Character": True,
                    "IMC_Character_ClimbTest": False,
                    "IMC_Character_Testing": False,
                    "IMC_MapTool": True,
                    "IMC_Radial": True,
                },
                "fixture shipping flags",
            )
            _eq(
                {
                    name: len(ctx["mappings"])
                    for name, ctx in payload["contexts"].items()
                },
                {
                    "IMC_Character": 5,
                    "IMC_Character_ClimbTest": 2,
                    "IMC_Character_Testing": 1,
                    "IMC_MapTool": 1,
                    "IMC_Radial": 1,
                },
                "fixture row counts",
            )

            first = _row_named(
                payload, "IMC_Character", "IA_Ability_Action_Primary", "LeftMouseButton"
            )
            _eq(first["key_is_gamepad"], False, "LeftMouseButton key_is_gamepad")
            _eq(first["value_type"], "Boolean", "default ValueType is Boolean")
            _eq(first["player_mappable"], True, "row 0 player_mappable")
            _eq(first["mappable_name"], "ActionPrimary", "row 0 mappable_name")
            _eq(
                first["setting_behavior"],
                "EPlayerMappableKeySettingBehaviors::InheritSettingsFromAction",
                "row 0 setting_behavior",
            )
            _eq(
                (first["display_name"], first["display_name_key"]),
                ("Interaction", "InputSetting.Category.Interaction"),
                "transposed DisplayName emitted verbatim",
            )
            _eq(
                (first["display_category"], first["display_category_key"]),
                ("Primary Fire", "InputSetting.PrimaryFire"),
                "transposed DisplayCategory emitted verbatim",
            )
            _eq(
                first["display_table"],
                "/Game/StringTables/ST_Settings_Input.ST_Settings_Input",
                "LOCTABLE table id kept",
            )
            _eq(
                first["mappable_settings_path"],
                f"{CHAR}/IMC_Character.1",
                "row settings path",
            )

            gamepad = _row_named(
                payload,
                "IMC_Character",
                "IA_Ability_Action_Primary",
                "Gamepad_RightTrigger",
            )
            _eq(gamepad["key_is_gamepad"], True, "Gamepad_ key_is_gamepad")
            _eq(gamepad["player_mappable"], False, "row 1 player_mappable")

            hold = _row_named(
                payload,
                "IMC_Character",
                "IA_Ability_Action_Primary_Hold",
                "LeftMouseButton",
            )["trigger"]
            _eq(hold["type"], "Hold", "trigger type")
            _eq(hold["hold_time"], 0.2, "hold_time")
            _eq(
                hold["properties"],
                {"HoldTimeThreshold": 0.2},
                "hold properties verbatim",
            )

            deadzone = _row_named(
                payload, "IMC_Character", "IA_Ability_Action_Primary", "Mouse2D"
            )["modifiers"][0]
            _eq(deadzone["type"], "DeadZone", "modifier type")
            _eq((deadzone["lower"], deadzone["upper"]), (0.18, 0.98), "deadzone bounds")
            _eq(
                deadzone["properties"],
                {"LowerThreshold": 0.18, "UpperThreshold": 0.98},
                "deadzone properties verbatim",
            )

            radial_mod = payload["contexts"]["IMC_Radial"]["mappings"][0]["modifiers"][
                0
            ]
            _eq(
                radial_mod["type"],
                "DeadZone",
                "reserved field: authored Type must not overwrite the class label",
            )
            _eq(
                radial_mod["property_type"],
                "EDeadZoneType::Axial",
                "colliding authored property keeps a property_ field",
            )

            chord_row = _row_named(
                payload, "IMC_Character", "IA_PreventLookGamepad", "Gamepad_Right2D"
            )
            _eq(
                chord_row["chord_action"],
                "IA_ControllerLeftShoulder",
                "row chord_action",
            )
            _eq(
                chord_row["trigger"]["chord_action_path"],
                f"{CHAR}/IA_ControllerLeftShoulder.0",
                "chord_action_path",
            )
            _check(
                chord_row["chord_action"] in payload["actions"],
                "chord target is an indexed action",
            )

            hold_action = payload["actions"]["IA_Ability_Action_Primary_Hold"]
            _eq(hold_action["value_type"], "Axis1D", "authored ValueType")
            _eq(hold_action["value_type_authored"], True, "authored flag")
            _eq(
                payload["actions"]["IA_Ability_Action_Primary"]["value_type_authored"],
                False,
                "default flag",
            )
            _eq(
                payload["actions"]["IA_Ability_Action_Primary"]["keys"],
                ["LeftMouseButton", "Gamepad_RightTrigger", "Mouse2D"],
                "action keys in first-seen order",
            )
            _eq(
                payload["actions"]["IA_Ability_Action_Primary"]["contexts"],
                ["IMC_Character", "IMC_Character_ClimbTest"],
                "action contexts sorted",
            )

            curve = payload["curves"]["Curve_GamepadMoveThumbstickResponse"]
            _eq(len(curve["keys"]), 1, "fixture curve keys")
            key = curve["keys"][0]
            _eq((key["time"], key["value"]), (0.0, 0.0), "curve key time/value")
            _eq(key["interp_mode"], "Linear", "curve interp short name")
            _eq(key["ue_interp_mode"], "RCIM_Linear", "curve interp UE name")
            _eq(key["tangent_mode"], "Auto", "curve tangent short name")
            _eq(key["arrive_tangent"], -0.1314473, "curve arrive tangent")
            _eq(
                key["ue_tangent_weight_mode"],
                "RCTWM_WeightedNone",
                "tangent weight mode",
            )
            print("ok fixture payload + contract")
            checks += 1

            # --- determinism ----------------------------------------------------
            out_again = base / "out-again"
            _run(extracted, out_again)
            first_bytes = (out / "gameplay" / "input_actions.json").read_bytes()
            second_bytes = (out_again / "gameplay" / "input_actions.json").read_bytes()
            _eq(first_bytes, second_bytes, "two runs are byte-identical")
            _check(first_bytes.endswith(b"\n"), "payload ends with a newline")
            _check(b"generated_at" not in first_bytes, "payload carries no timestamp")
            print("ok fixture determinism")
            checks += 1

            # --- cross-package and same-file resolution -------------------------
            climb = payload["contexts"]["IMC_Character_ClimbTest"]["mappings"]
            _eq(
                climb[0]["trigger_path"],
                f"{CHAR}/IMC_Character.2",
                "cross-package path kept",
            )
            _eq(climb[0]["trigger"]["hold_time"], 0.2, "cross-package trigger resolved")
            _eq(
                climb[1]["trigger"]["type"],
                "Pressed",
                "same-file export without Properties",
            )
            _eq(climb[1]["trigger"]["properties"], {}, "absent Properties becomes {}")
            print("ok cross-package + same-file ObjectPath resolution")
            checks += 1

            # --- fail closed: unknown trigger class -----------------------------
            hold_file = extracted / REL_INPUT / "Character" / "IMC_Character.json"
            hold_bytes = hold_file.read_bytes()
            mutated = json.loads(hold_bytes)
            mutated[2]["Type"] = "InputTriggerWobble"
            _json(hold_file, mutated)
            _run(
                extracted,
                base / "bad-trigger",
                expect=1,
                contains="InputTriggerWobble",
            )
            hold_file.write_bytes(hold_bytes)
            _run(extracted, base / "restored-trigger")
            print("ok unknown trigger class fails closed")
            checks += 1

            # --- fail closed: unknown modifier class ----------------------------
            radial_file = extracted / REL_INPUT / "Radial" / "IMC_Radial.json"
            radial_bytes = radial_file.read_bytes()
            mutated = json.loads(radial_bytes)
            mutated[1]["Type"] = "InputModifierWobble"
            _json(radial_file, mutated)
            _run(
                extracted,
                base / "bad-modifier",
                expect=1,
                contains="InputModifierWobble",
            )
            radial_file.write_bytes(radial_bytes)
            _run(extracted, base / "restored-modifier")
            print("ok unknown modifier class fails closed")
            checks += 1

            # --- fail closed: missing shipping context --------------------------
            maptool = extracted / REL_INPUT / "Map" / "IMC_MapTool.json"
            maptool_bytes = maptool.read_bytes()
            maptool.unlink()
            _run(extracted, base / "missing-context", expect=1, contains="IMC_MapTool")
            maptool.write_bytes(maptool_bytes)
            _run(extracted, base / "restored-context")
            print("ok missing context fails closed")
            checks += 1

            # --- fail closed: unresolved ObjectPath -----------------------------
            mutated = json.loads(radial_bytes)
            mutated[0]["Properties"]["Mappings"][0]["Modifiers"][0]["ObjectPath"] = (
                f"{RADIAL}/IMC_Radial.99"
            )
            _json(radial_file, mutated)
            _run(extracted, base / "unresolved", expect=1, contains="IMC_Radial.99")
            radial_file.write_bytes(radial_bytes)
            _run(extracted, base / "restored-unresolved")
            print("ok unresolved reference fails closed")
            checks += 1

        # --- read-only end-to-end run against the shipped tree ------------------
        real_input = REAL / REL_INPUT
        if not real_input.is_dir():
            raise AssertionError(f"real extracted input tree is missing: {real_input}")
        with tempfile.TemporaryDirectory(prefix="tat2-input-e2e-") as td:
            out = Path(td) / "out"
            _run(REAL, out)
            payload = _load(out)

            _eq(payload["schema"], "tat2.input_actions/1", "e2e schema")
            _eq(payload["unresolved"], [], "e2e unresolved")
            counts = payload["counts"]
            # Measured on the shipped dumps (see evidence.md).
            _eq(counts["contexts"], 5, "e2e contexts")
            _eq(counts["shipping_contexts"], 3, "e2e shipping contexts")
            _eq(counts["shipping_mappings"], 91, "e2e shipping mappings")
            _eq(counts["shipping_actions"], 52, "e2e shipping actions")
            _eq(counts["all_mappings"], 237, "e2e all mappings")
            _eq(counts["all_actions"], 54, "e2e all actions")
            _eq(counts["actions_assets"], 65, "e2e action assets")
            _eq(counts["curve_assets"], 2, "e2e curve assets")

            _eq(
                {name: ctx["shipping"] for name, ctx in payload["contexts"].items()},
                {
                    "IMC_Character": True,
                    "IMC_Character_ClimbTest": False,
                    "IMC_Character_Testing": False,
                    "IMC_MapTool": True,
                    "IMC_Radial": True,
                },
                "e2e shipping flags",
            )
            _eq(
                {
                    name: len(ctx["mappings"])
                    for name, ctx in payload["contexts"].items()
                },
                {
                    "IMC_Character": 76,
                    "IMC_Character_ClimbTest": 69,
                    "IMC_Character_Testing": 77,
                    "IMC_MapTool": 4,
                    "IMC_Radial": 11,
                },
                "e2e row counts",
            )
            print("ok real tree counts")
            checks += 1

            primary_rows = [
                row
                for row in payload["contexts"]["IMC_Character"]["mappings"]
                if row["action"] == "IA_Ability_Action_Primary"
            ]
            _eq(
                [row["key"] for row in primary_rows],
                ["LeftMouseButton", "Gamepad_RightTrigger"],
                "e2e primary action keys",
            )
            _eq(
                [row["key_is_gamepad"] for row in primary_rows],
                [False, True],
                "e2e primary key_is_gamepad",
            )
            _eq(
                primary_rows[0]["mappable_name"],
                "ActionPrimary",
                "e2e primary mappable name",
            )
            _eq(
                primary_rows[0]["setting_behavior"],
                "EPlayerMappableKeySettingBehaviors::InheritSettingsFromAction",
                "e2e primary setting behavior",
            )

            holds = [
                row["trigger"]
                for ctx in payload["contexts"].values()
                for row in ctx["mappings"]
                if row["trigger"] and row["trigger"]["type"] == "Hold"
            ]
            _check(
                holds and all(t.get("hold_time") == 0.2 for t in holds),
                f"e2e Hold triggers should all be 0.2s, got {[t.get('hold_time') for t in holds]}",
            )
            deadzones = [
                mod
                for ctx in payload["contexts"].values()
                for row in ctx["mappings"]
                for mod in row["modifiers"]
                if mod["type"] == "DeadZone"
            ]
            _check(
                deadzones and all(mod["type"] == "DeadZone" for mod in deadzones),
                "e2e every DeadZone modifier keeps type=DeadZone",
            )
            _eq(len(deadzones), 9, "e2e DeadZone modifier rows")
            _check(
                any(
                    mod.get("property_type") == "EDeadZoneType::Axial"
                    for mod in deadzones
                ),
                "e2e authored EDeadZoneType::Axial kept as property_type",
            )
            _check(
                any(
                    mod.get("lower") == 0.18 and mod.get("upper") == 0.98
                    for mod in deadzones
                ),
                "e2e DeadZone 0.18/0.98 missing",
            )
            chords = [
                row["chord_action"]
                for ctx in payload["contexts"].values()
                for row in ctx["mappings"]
                if row["chord_action"]
            ]
            _eq(
                set(chords),
                {"IA_ControllerLeftShoulder", "IA_Ability_Action_Secondary"},
                "e2e chord targets",
            )
            _check(
                all(action in payload["actions"] for action in chords),
                "e2e chord targets are real actions",
            )

            move = payload["actions"]["IA_Move"]
            _eq(move["value_type"], "Axis2D", "e2e IA_Move ValueType")
            _eq(move["value_type_authored"], True, "e2e IA_Move authored ValueType")

            curves = payload["curves"]
            _eq(
                set(curves),
                {"Curve_GamepadMoveThumbstickResponse", "Curve_GamepadLookEdgeBoost"},
                "e2e curves",
            )
            move_key = curves["Curve_GamepadMoveThumbstickResponse"]["keys"][0]
            _eq(
                (move_key["time"], move_key["value"], move_key["interp_mode"]),
                (0.0, 0.0, "Linear"),
                "e2e move curve first key",
            )
            _eq(move_key["arrive_tangent"], -0.1314473, "e2e move curve arrive tangent")
            _eq(
                len(curves["Curve_GamepadMoveThumbstickResponse"]["keys"]),
                4,
                "e2e move curve key count",
            )
            _eq(
                len(curves["Curve_GamepadLookEdgeBoost"]["keys"]),
                2,
                "e2e look curve key count",
            )
            print("ok real tree authored rows + curves")
            checks += 1

            out_again = Path(td) / "out-again"
            _run(REAL, out_again)
            _eq(
                (out / "gameplay" / "input_actions.json").read_bytes(),
                (out_again / "gameplay" / "input_actions.json").read_bytes(),
                "e2e runs are byte-identical",
            )
            print("ok real tree determinism")
            checks += 1
    except AssertionError as exc:
        print(f"FAIL: {exc}")
        return 1

    print(f"PASS: {checks} checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
