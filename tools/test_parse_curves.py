#!/usr/bin/env python3
"""Unit + end-to-end tests for tools/parse_curves.py (stdlib only).

Run with: ``python3 tools/test_parse_curves.py``

The end-to-end half reads the real ``extracted/json`` tree read-only and writes
into a temporary directory, so it never touches ``game/data/generated``. Every
expected count below is a *measured* count of the shipped build, kept here
independently of the producer so a producer bug cannot validate itself:

    python3 - <<'EOF'
    import json, glob
    top = nested = ct = 0
    for p in sorted(glob.glob('extracted/json/**/*.json', recursive=True)):
        for o in json.load(open(p)) if isinstance(json.load(open(p)), list) else []:
            t = o.get('Type')
            if t == 'CurveTable':
                ct += 1
            elif t in ('CurveFloat', 'CurveVector', 'CurveLinearColor'):
                pkg = o.get('Package') or ''
                if pkg.rsplit('/', 1)[-1] == o.get('Name'):
                    top += 1
                else:
                    nested += 1
    print(top, nested, ct)
    EOF

gives ``16 108 23`` on the W7 extract (2026-11-25).
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_curves.py"
EXTRACTED = ROOT / "extracted"

# Measured on the shipped build (see module docstring for the command).
EXPECTED_STANDALONE = 16
EXPECTED_NESTED = 108
EXPECTED_CURVE_TABLES = 23
EXPECTED_BY_TYPE = {"CurveFloat": 14, "CurveLinearColor": 2}
# The five directories game/src/core/game_data.gd loads that were empty before
# this producer existed (RE-A-01).
FORMER_EMPTY_ROOTS = (
    "tables/AI/Alertness",
    "tables/Art/Environment/Weather",
    "tables/Gameplay/Carry",
    "tables/Gameplay/Input/Character",
    "tables/Gameplay/Traversal/Dodge",
)

failures: list[str] = []
checks = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if condition:
        print(f"ok {name}")
    else:
        failures.append(f"{name}: {detail}" if detail else name)
        print(f"FAIL {name} {detail}")


def run(extracted: Path, out: Path, quiet: bool = True) -> subprocess.CompletedProcess:
    cmd = [
        sys.executable,
        str(PRODUCER),
        "--extracted",
        str(extracted),
        "--out-dir",
        str(out),
    ]
    if quiet:
        cmd.append("--quiet")
    return subprocess.run(cmd, capture_output=True, text=True)


def write_dump(path: Path, exports: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(exports, indent=1) + "\n", encoding="utf-8")


def key(time: float, value: float, mode: str = "RCIM_Linear") -> dict:
    return {
        "InterpMode": mode,
        "TangentMode": "RCTM_Auto",
        "TangentWeightMode": "RCTWM_WeightedNone",
        "Time": time,
        "Value": value,
        "ArriveTangent": 0.0,
        "ArriveTangentWeight": 0.0,
        "LeaveTangent": 0.0,
        "LeaveTangentWeight": 0.0,
    }


def fixture_curve_float(pkg: str, name: str, keys: list[dict]) -> dict:
    return {
        "Type": "CurveFloat",
        "Name": name,
        "Class": "UScriptClass'CurveFloat'",
        "Package": pkg,
        "Properties": {"FloatCurve": {"Keys": keys}},
    }


def fixture_linear_color(pkg: str, name: str, channels: dict) -> dict:
    properties: dict = {}
    for index, keys in sorted(channels.items()):
        properties["FloatCurves" if index == 0 else f"FloatCurves[{index}]"] = {
            "Keys": keys
        }
    return {
        "Type": "CurveLinearColor",
        "Name": name,
        "Class": "UScriptClass'CurveLinearColor'",
        "Package": pkg,
        "Properties": properties,
    }


def fixture_nested(bp: str, name: str) -> dict:
    return {
        "Type": "CurveFloat",
        "Name": name,
        "Class": "UScriptClass'CurveFloat'",
        "Outer": {
            "ObjectName": "BlueprintGeneratedClass'%s_C'" % bp,
            "ObjectPath": bp + ".0",
        },
        "Properties": {"FloatCurve": {"Keys": [key(0.0, 1.0)]}},
    }


def test_fixture(tmp: Path) -> None:
    extracted = tmp / "extracted"
    out = tmp / "out"
    # -- a standalone float curve, a 2-channel colour with a sparse alpha, a
    #    nested blueprint curve, and a materialised CurveTable that must not be
    #    touched by this producer.
    write_dump(
        extracted / "json/Gameplay/Carry/Curve_Throw.json",
        [
            fixture_curve_float(
                "/Game/Gameplay/Carry/Curve_Throw",
                "Curve_Throw",
                [key(0.0, 0.0), key(1.0, 2.0)],
            )
        ],
    )
    write_dump(
        extracted / "json/Art/Env/C_Sky.json",
        [
            fixture_linear_color(
                "/Game/Art/Env/C_Sky",
                "C_Sky",
                {0: [key(0.0, 1.0), key(1.0, 0.0, "RCIM_Constant")], 3: []},
            )
        ],
    )
    write_dump(
        extracted / "json/Gameplay/Traversal/Dodge/Curve_Dodge.json",
        [
            fixture_curve_float(
                "/Game/Gameplay/Traversal/Dodge/Curve_Dodge",
                "Curve_Dodge",
                [key(0.0, 3.0)],
            )
        ],
    )
    write_dump(
        extracted / "json/Art/BP_Thing.json",
        [
            {
                "Type": "BlueprintGeneratedClass",
                "Name": "BP_Thing_C",
                "Package": "/Game/Art/BP_Thing",
            },
            fixture_nested("/Game/Art/BP_Thing", "CurveFloat_1"),
        ],
    )
    write_dump(
        extracted / "json/Gameplay/Tuning/CT_Existing.json",
        [
            {
                "Type": "CurveTable",
                "Name": "CT_Existing",
                "Package": "/Game/Gameplay/Tuning/CT_Existing",
                "Rows": {
                    "Row": {
                        "InterpMode": "RCIM_Linear",
                        "Keys": [{"Time": 0.0, "Value": 1.0}],
                    }
                },
            }
        ],
    )

    proc = run(extracted, out)
    check("fixture: producer exits 0", proc.returncode == 0, proc.stderr.strip())

    table = out / "tables/Gameplay/Carry/Curve_Throw.json"
    check("fixture: curve table file written", table.is_file())
    if table.is_file():
        payload = json.loads(table.read_text())
        check("fixture: type is the UE class", payload.get("type") == "CurveFloat")
        check(
            "fixture: asset path preserved",
            payload.get("asset") == "/Game/Gameplay/Carry/Curve_Throw",
        )
        check(
            "fixture: single Value row with both keys",
            list(payload.get("rows", {})) == ["Value"]
            and [k["Time"] for k in payload["rows"]["Value"]["Keys"]] == [0.0, 1.0],
        )
        check(
            "fixture: authored key values preserved",
            [k["Value"] for k in payload["rows"]["Value"]["Keys"]] == [0.0, 2.0],
        )
        check("fixture: time_range computed", payload.get("time_range") == [0.0, 1.0])
        check("fixture: no invented channel", payload.get("sparse_channels") == [])

    colour = out / "tables/Art/Env/C_Sky.json"
    check("fixture: colour curve written", colour.is_file())
    if colour.is_file():
        payload = json.loads(colour.read_text())
        check(
            "fixture: sparse channels indexed, authored R kept",
            payload.get("channels") == ["R"]
            and payload.get("sparse_channels") == ["G", "B", "A"],
            f"channels={payload.get('channels')} sparse={payload.get('sparse_channels')}",
        )
        check(
            "fixture: RCIM_Constant survives normalisation",
            payload["rows"]["R"]["Keys"][1]["InterpMode"] == "RCIM_Constant",
        )

    check(
        "fixture: nested blueprint curve is indexed, not emitted as a table",
        not (out / "tables/Art/BP_Thing.json").exists(),
    )
    index = json.loads((out / "curves.json").read_text())
    nested = index.get("nested") or []
    check(
        "fixture: nested curve records its owner",
        any(
            n["owner"] == "/Game/Art/BP_Thing" and n["name"] == "CurveFloat_1"
            for n in nested
        ),
        str(nested),
    )
    check(
        "fixture: existing CurveTable untouched",
        not (out / "tables/Gameplay/Tuning/CT_Existing.json").exists(),
    )
    check(
        "fixture: curve table counted",
        index["counts"]["curve_tables"] == 1,
        str(index["counts"]),
    )
    check(
        "fixture: counts reconcile",
        index["counts"]["standalone"] == 3
        and index["counts"]["nested"] == 1
        and index["counts"]["emitted"] == 3,
        str(index["counts"]),
    )

    # Determinism: the audit baseline pins the produced bytes.
    out2 = tmp / "out2"
    run(extracted, out2)
    a = {p.relative_to(out): p.read_bytes() for p in out.rglob("*") if p.is_file()}
    b = {p.relative_to(out2): p.read_bytes() for p in out2.rglob("*") if p.is_file()}
    check("fixture: two runs are byte-identical", a == b)

    # Unknown shape fails closed rather than dropping data.
    bad = tmp / "bad"
    write_dump(
        bad / "extracted/json/Bad/Curve_Bad.json",
        [
            {
                "Type": "CurveFloat",
                "Name": "Curve_Bad",
                "Package": "/Game/Bad/Curve_Bad",
                "Properties": {"FloatCurve": {"Keys": []}},
            }
        ],
    )
    proc = run(bad / "extracted", tmp / "bad-out")
    check(
        "fixture: an empty curve fails closed",
        proc.returncode != 0,
        "producer accepted a keyless curve",
    )
    check(
        "fixture: failure names the curve",
        "Curve_Bad" in (proc.stderr or ""),
        proc.stderr.strip()[:160],
    )


def test_real_tree(tmp: Path) -> None:
    if not (EXTRACTED / "json").is_dir():
        print("skip real tree: extracted/json not present (run make extract first)")
        return
    out = tmp / "real"
    proc = run(EXTRACTED, out)
    check("real: producer exits 0", proc.returncode == 0, proc.stderr.strip()[-400:])
    index = json.loads((out / "curves.json").read_text())
    counts = index["counts"]
    check(
        "real: standalone curve assets",
        counts["standalone"] == EXPECTED_STANDALONE,
        str(counts),
    )
    check(
        "real: nested curve objects", counts["nested"] == EXPECTED_NESTED, str(counts)
    )
    check(
        "real: CurveTables untouched",
        counts["curve_tables"] == EXPECTED_CURVE_TABLES,
        str(counts),
    )
    check(
        "real: every standalone curve emitted",
        counts["emitted"] == EXPECTED_STANDALONE,
        str(counts),
    )
    check(
        "real: by type", counts["standalone_by_type"] == EXPECTED_BY_TYPE, str(counts)
    )

    for rel in FORMER_EMPTY_ROOTS:
        files = sorted((out / rel).glob("*.json"))
        check(
            f"real: root {rel} is no longer empty",
            bool(files),
            f"{rel} has no curve file",
        )

    # RE-A-13's curve: the authored keys and the outgoing-segment interp modes.
    alertness = (
        out / "tables/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json"
    )
    check("real: alertness curve emitted", alertness.is_file())
    if alertness.is_file():
        rows = json.loads(alertness.read_text())["rows"]["Value"]["Keys"]
        check(
            "real: alertness keys are (2.0,1.0 Constant),(3.0,0.0 Linear)",
            [(k["Time"], k["Value"], k["InterpMode"]) for k in rows]
            == [(2.0, 1.0, "RCIM_Constant"), (3.0, 0.0, "RCIM_Linear")],
            str(rows),
        )

    # The two gamepad response curves RE-A-01 called out.
    for name in ("Curve_GamepadMoveThumbstickResponse", "Curve_GamepadLookEdgeBoost"):
        path = out / "tables/Gameplay/Input/Character" / f"{name}.json"
        payload = json.loads(path.read_text()) if path.is_file() else {}
        check(
            f"real: {name} emitted with keys",
            bool(payload.get("rows", {}).get("Value", {}).get("Keys")),
            str(payload)[:120],
        )

    # Loader compatibility: game_data.gd only reads {rows: {row: {Keys: [...]}}}
    # and treats a row dictionary containing Keys as a curve.
    sample = json.loads(
        (out / "tables/Gameplay/Traversal/Dodge/Curve_Dodge.json").read_text()
    )
    check(
        "real: payload matches the game_data.gd curve contract",
        isinstance(sample.get("rows"), dict)
        and all("Keys" in row for row in sample["rows"].values())
        and "Time" in sample["rows"]["Value"]["Keys"][0]
        and "Value" in sample["rows"]["Value"]["Keys"][0],
        str(sample)[:160],
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="tat2-curves-test-") as td:
        tmp = Path(td)
        test_fixture(tmp)
        test_real_tree(tmp)
    if failures:
        print(f"FAIL: {len(failures)} failure(s)")
        for item in failures:
            print(f"  {item}")
        return 1
    print(f"PASS: {checks} checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
