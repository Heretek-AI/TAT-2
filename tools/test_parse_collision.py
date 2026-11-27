#!/usr/bin/env python3
"""Tests for tools/parse_collision.py (stdlib only).

Run with: ``python3 tools/test_parse_collision.py``

Fixture packages are hand-built in a ``tempfile.TemporaryDirectory``; the
end-to-end cases run the real producer against the read-only ``extracted/``
tree into a temporary directory. Every hardcoded count below was measured with
the AggGeom scanner recorded in the T01-PIPELINE worker-A evidence file, not
copied from the producer's output.
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_collision.py"
EXTRACTED = ROOT / "extracted"

# Measured 2026-11-25 over all 12,541 extracted/json/*.json dumps.
MEASURED_COUNTS = {
    "meshes": 1992,
    "body_setups": 2935,
    "skeletal_body_setups": 219,
    "elements": 8601,
    "box": 2334,
    "sphere": 50,
    "sphyl": 295,
    "convex": 5922,
    "tapered_capsule": 0,
    "body_setup_elements": 8382,
    "skeletal_body_setup_elements": 219,
    "empty_body_setup": 0,
    "multi_body_setup_packages": 40,
    "packages_with_uniform_collision_profile": 1921,
    "packages_complex_as_simple": 14,
    "nav_collision_packages": 1977,
    "nav_collision_packages_with_area_data": 0,
    "nav_collision_packages_without_simple_collision": 330,
    "files_scanned": 12541,
    "non_package_documents": 0,
}

PASSED = 0


def check(condition: bool, name: str, detail: str = "") -> None:
    global PASSED
    if not condition:
        message = f"FAIL: {name}"
        if detail:
            message += f" ({detail})"
        print(message)
        raise SystemExit(1)
    print(f"ok {name}")
    PASSED += 1


def run_producer(
    extracted: Path, out_dir: Path, extra_args: list[str] | None = None
) -> subprocess.CompletedProcess:
    command = [
        sys.executable,
        str(PRODUCER),
        "--extracted",
        str(extracted),
        "--out-dir",
        str(out_dir),
        "--quiet",
    ]
    command.extend(extra_args or [])
    return subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def write_dump(extracted: Path, relative: str, exports: list[dict]) -> Path:
    path = extracted / "json" / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(exports, indent=1) + "\n", encoding="utf-8")
    return path


def box_element() -> dict:
    return {
        "Center": {"X": 1.0, "Y": 2.0, "Z": 3.0},
        "Rotation": {"Pitch": 0.0, "Yaw": 90.0, "Roll": 0.0},
        "X": 4.0,
        "Y": 5.0,
        "Z": 6.0,
        "RestOffset": 0.5,
        "Name": "BoxA",
        "bContributeToMass": True,
        "CollisionEnabled": "ECollisionEnabled::QueryOnly",
    }


def sphere_element() -> dict:
    return {
        "Center": {"X": 0.0, "Y": 0.0, "Z": 0.0},
        "Radius": 7.0,
        "RestOffset": 0.0,
        "Name": "None",
        "bContributeToMass": False,
        "CollisionEnabled": "ECollisionEnabled::NoCollision",
    }


def sphyl_element() -> dict:
    return {
        "Center": {"X": 0.0, "Y": 0.0, "Z": 0.0},
        "Rotation": {"Pitch": 0.0, "Yaw": 0.0, "Roll": 90.0},
        "Radius": 8.0,
        "Length": 9.0,
        "RestOffset": 0.0,
        "Name": "None",
        "bContributeToMass": True,
        "CollisionEnabled": "ECollisionEnabled::QueryAndPhysics",
    }


def convex_element() -> dict:
    return {
        "VertexData": [
            {"X": 0.0, "Y": 0.0, "Z": 0.0},
            {"X": 1.0, "Y": 0.0, "Z": 0.0},
            {"X": 0.0, "Y": 1.0, "Z": 0.0},
        ],
        "IndexData": [0, 1, 2],
        "ElemBox": {
            "Min": {"X": 0.0, "Y": 0.0, "Z": 0.0},
            "Max": {"X": 1.0, "Y": 1.0, "Z": 0.0},
            "IsValid": 1,
        },
        "Transform": {
            "Rotation": {
                "X": 0.0,
                "Y": 0.0,
                "Z": 0.0,
                "W": 1.0,
                "IsNormalized": True,
                "Size": 1.0,
                "SizeSquared": 1.0,
            },
            "Translation": {"X": 0.0, "Y": 0.0, "Z": 0.0},
            "Scale3D": {"X": 1.0, "Y": 1.0, "Z": 1.0},
        },
        "RestOffset": 0.0,
        "Name": "None",
        "bContributeToMass": True,
        "CollisionEnabled": "ECollisionEnabled::QueryAndPhysics",
    }


def default_instance() -> dict:
    return {
        "ObjectType": "ECollisionChannel::ECC_WorldStatic",
        "CollisionProfileName": "BlockAll",
        "CollisionResponses": {
            "ResponseArray": [
                {"Channel": "Interact", "Response": "ECollisionResponse::ECR_Block"}
            ]
        },
    }


def body_export(
    name: str,
    package: str,
    index: int,
    agg_geom: dict,
    trace_flag: str | None = "ECollisionTraceFlag::CTF_UseComplexAsSimple",
) -> dict:
    properties: dict = {"AggGeom": agg_geom, "DefaultInstance": default_instance()}
    if trace_flag is not None:
        properties["CollisionTraceFlag"] = trace_flag
    return {
        "Type": "BodySetup",
        "Name": name,
        "Outer": {
            "ObjectName": f"StaticMesh'{package.rsplit('/', 1)[-1]}'",
            "ObjectPath": f"{package}.{index}",
        },
        "Properties": properties,
    }


def write_fixture_package(extracted: Path) -> None:
    write_dump(
        extracted,
        "Props/SM_Fixture.json",
        [
            {
                "Type": "StaticMesh",
                "Name": "SM_Fixture",
                "Package": "/Game/Test/SM_Fixture",
                "Properties": {},
            },
            body_export(
                "BodySetup_0",
                "/Game/Test/SM_Fixture",
                2,
                {
                    "BoxElems": [box_element()],
                    "SphereElems": [sphere_element()],
                    "SphylElems": [sphyl_element()],
                    "ConvexElems": [convex_element()],
                },
            ),
            {
                "Type": "NavCollision",
                "Name": "NavCollision_1",
                "Outer": {
                    "ObjectName": "StaticMesh'SM_Fixture'",
                    "ObjectPath": "/Game/Test/SM_Fixture.3",
                },
                "CookedFormatData": {
                    "NavCollision_Chaos": {"ElementCount": 42, "SizeOnDisk": 42}
                },
            },
        ],
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="test_collision_") as tmp:
        tmpdir = Path(tmp)

        # -- fixture: one package, all four element types ------------------
        fixture = tmpdir / "fixture"
        write_fixture_package(fixture)
        fixture_out = tmpdir / "fixture-out"
        run = run_producer(fixture, fixture_out)
        check(
            run.returncode == 0 and (fixture_out / "mesh_collision.json").is_file(),
            "fixture producer exits 0",
            run.stderr.strip(),
        )
        payload = json.loads((fixture_out / "mesh_collision.json").read_text())
        counts = payload["counts"]
        check(
            payload["schema"] == "tat2.mesh_collision/1"
            and payload["generated_by"] == "tools/parse_collision.py"
            and payload["source"] == "extracted/json/**"
            and "centimetres" in payload["units"]
            and "HALF-extents" in payload["notes"]
            and payload["index_data_included"] is False,
            "fixture schema, units and default index-data mode",
        )
        check(
            counts["meshes"] == 1
            and counts["body_setups"] == 1
            and counts["skeletal_body_setups"] == 0
            and counts["elements"] == 4
            and [counts[name] for name in ("box", "sphere", "sphyl", "convex")]
            == [1, 1, 1, 1]
            and counts["empty_body_setup"] == 0
            and counts["nav_collision_packages"] == 1
            and counts["nav_collision_packages_with_area_data"] == 0
            and counts["packages_complex_as_simple"] == 1,
            "fixture counts",
            repr(counts),
        )
        mesh = payload["meshes"]["/Game/Test/SM_Fixture"]
        by_type = {element["type"]: element for element in mesh["elements"]}
        check(
            list(by_type) == ["box", "sphere", "sphyl", "convex"]
            and by_type["box"]["center"] == [1.0, 2.0, 3.0]
            and by_type["box"]["half_extent"] == [4.0, 5.0, 6.0]
            and by_type["box"]["rotation"] == {"pitch": 0.0, "yaw": 90.0, "roll": 0.0}
            and by_type["box"]["rest_offset"] == 0.5
            and by_type["box"]["name"] == "BoxA"
            and by_type["sphere"]["radius"] == 7.0
            and by_type["sphere"]["b_contribute_to_mass"] is False
            and by_type["sphyl"]["radius"] == 8.0
            and by_type["sphyl"]["length"] == 9.0
            and by_type["convex"]["vertex_count"] == 3
            and by_type["convex"]["vertices_flat"]
            == [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
            and len(by_type["convex"]["vertices_flat"])
            == 3 * by_type["convex"]["vertex_count"]
            and "index_data" not in by_type["convex"]
            and "index_count" not in by_type["convex"]
            and by_type["convex"]["aabb_min"] == [0.0, 0.0, 0.0]
            and by_type["convex"]["aabb_max"] == [1.0, 1.0, 0.0],
            "fixture elements round-trip (flat vertices, no index data)",
            repr(by_type),
        )

        # -- fixture: opt-in index data -------------------------------------
        index_out = tmpdir / "fixture-index-out"
        run = run_producer(fixture, index_out, ["--with-index-data"])
        index_payload = json.loads((index_out / "mesh_collision.json").read_text())
        index_convex = index_payload["meshes"]["/Game/Test/SM_Fixture"]["elements"][3]
        check(
            run.returncode == 0
            and index_payload["index_data_included"] is True
            and index_convex["type"] == "convex"
            and index_convex["index_data"] == [0, 1, 2]
            and index_convex["index_count"] == len(index_convex["index_data"])
            and index_convex["vertices_flat"]
            == [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
            "fixture --with-index-data emits triangles",
            repr({k: v for k, v in index_convex.items() if k != "transform"}),
        )
        check(
            mesh["body_setup"] == "BodySetup_0"
            and mesh["collision_profile"] == "BlockAll"
            and mesh["object_type"] == "ECollisionChannel::ECC_WorldStatic"
            and mesh["collision_responses"]
            == [{"channel": "Interact", "response": "ECollisionResponse::ECR_Block"}]
            and mesh["complex_as_simple"] is True
            and mesh["collision_trace_flag"]
            == "ECollisionTraceFlag::CTF_UseComplexAsSimple"
            and mesh["body_setups"][0]["element_count"] == 4
            and mesh["body_setups"][0]["default_instance_fields"]["collision_profile"]
            == "BlockAll",
            "fixture body setup and profile fields",
            repr({k: v for k, v in mesh.items() if k != "elements"}),
        )
        check(
            mesh["nav_collision"]
            == {
                "present": True,
                "has_area_data": False,
                "cooked": [
                    {
                        "format": "NavCollision_Chaos",
                        "element_count": 42,
                        "size_on_disk": 42,
                    }
                ],
            },
            "fixture nav collision metadata",
            repr(mesh.get("nav_collision")),
        )

        # -- fixture: an empty AggGeom is counted, not silently dropped ---
        empty_fixture = tmpdir / "empty"
        write_dump(
            empty_fixture,
            "Props/SM_Empty.json",
            [body_export("BodySetup_0", "/Game/Test/SM_Empty", 1, {})],
        )
        empty_out = tmpdir / "empty-out"
        run = run_producer(empty_fixture, empty_out)
        empty_payload = json.loads((empty_out / "mesh_collision.json").read_text())
        check(
            run.returncode == 0
            and empty_payload["counts"]["empty_body_setup"] == 1
            and empty_payload["counts"]["elements"] == 0
            and empty_payload["meshes"]["/Game/Test/SM_Empty"]["elements"] == [],
            "empty AggGeom is counted",
            repr(empty_payload["counts"]),
        )

        # -- fixture: a BodySetup with no AggGeom is recorded separately, and
        # the authored trace flag / CollisionEnabled decide complex vs none ----
        no_geom_fixture = tmpdir / "no-geom"
        write_dump(
            no_geom_fixture,
            "Props/SM_NoGeom.json",
            [
                body_export("BodySetup_0", "/Game/Test/SM_NoGeom", 1, {}, None),
                body_export("BodySetup_1", "/Game/Test/SM_NoGeom", 2, {}, None),
            ],
        )
        # The helper always writes AggGeom; drop the key to model the real dumps.
        no_geom_path = no_geom_fixture / "json" / "Props" / "SM_NoGeom.json"
        exports = json.loads(no_geom_path.read_text())
        for export in exports:
            export["Properties"].pop("AggGeom", None)
        exports[1]["Properties"]["CollisionTraceFlag"] = (
            "ECollisionTraceFlag::CTF_UseSimpleAsComplex"
        )
        no_geom_path.write_text(json.dumps(exports, indent=1) + "\n", encoding="utf-8")
        write_dump(
            no_geom_fixture,
            "Props/SM_NoGeomOff.json",
            [body_export("BodySetup_0", "/Game/Test/SM_NoGeomOff", 1, {}, None)],
        )
        off_path = no_geom_fixture / "json" / "Props" / "SM_NoGeomOff.json"
        off_exports = json.loads(off_path.read_text())
        off_exports[0]["Properties"].pop("AggGeom", None)
        off_exports[0]["Properties"]["DefaultInstance"]["CollisionEnabled"] = (
            "ECollisionEnabled::NoCollision"
        )
        off_path.write_text(json.dumps(off_exports, indent=1) + "\n", encoding="utf-8")
        no_geom_out = tmpdir / "no-geom-out"
        run = run_producer(no_geom_fixture, no_geom_out)
        no_geom_payload = json.loads((no_geom_out / "mesh_collision.json").read_text())
        no_simple = no_geom_payload["no_simple_collision"]
        check(
            run.returncode == 0
            and no_geom_payload["counts"]["meshes"] == 0
            and no_geom_payload["counts"]["body_setups"] == 0
            and no_geom_payload["no_simple_collision_counts"]
            == {"packages": 2, "complex_as_simple": 1, "no_collision": 1}
            and no_simple["/Game/Test/SM_NoGeom"]["kind"] == "complex_as_simple"
            and no_simple["/Game/Test/SM_NoGeom"]["reason"]
            == "default_complex_fallback"
            and no_simple["/Game/Test/SM_NoGeomOff"]["kind"] == "no_collision"
            and no_simple["/Game/Test/SM_NoGeomOff"]["reason"]
            == "explicit_no_collision",
            "BodySetup without AggGeom is recorded as complex-as-simple or no-collision",
            repr(no_geom_payload["no_simple_collision_counts"]),
        )

        # -- fixture: an unknown AggGeom key fails closed ------------------
        bad_fixture = tmpdir / "bad"
        write_dump(
            bad_fixture,
            "Props/SM_Bad.json",
            [
                body_export(
                    "BodySetup_0",
                    "/Game/Test/SM_Bad",
                    1,
                    {"CapsuleElems": []},
                )
            ],
        )
        bad = run_producer(bad_fixture, tmpdir / "bad-out")
        check(
            bad.returncode != 0 and "unknown AggGeom keys" in bad.stderr,
            "unknown AggGeom key fails closed",
            bad.stderr.strip(),
        )

        missing = run_producer(tmpdir / "does-not-exist", tmpdir / "missing-out")
        check(
            missing.returncode != 0
            and (
                "missing extracted json directory" in missing.stderr
                or "no *.json dumps" in missing.stderr
            ),
            "producer fails on a missing dump tree",
            missing.stderr.strip(),
        )

        # -- end-to-end against the shipped tree --------------------------
        out1 = tmpdir / "real-out1"
        run = run_producer(EXTRACTED, out1)
        check(
            run.returncode == 0 and (out1 / "mesh_collision.json").is_file(),
            "producer real run exits 0",
            run.stderr.strip(),
        )
        real = json.loads((out1 / "mesh_collision.json").read_text())
        check(
            real["counts"] == MEASURED_COUNTS and real["index_data_included"] is False,
            "measured counts match (1992 packages / 8601 elements)",
            repr(real["counts"]),
        )
        check(
            real["no_simple_collision_counts"]
            == {"packages": 334, "complex_as_simple": 293, "no_collision": 41},
            "measured no-simple-collision census (334 packages / 293 complex / 41 none)",
            repr(real["no_simple_collision_counts"]),
        )
        no_simple = real["no_simple_collision"]
        check(
            set(no_simple) == set(sorted(no_simple))
            and all(
                entry["kind"] in ("complex_as_simple", "no_collision")
                and entry["reason"]
                in (
                    "default_complex_fallback",
                    "complex_as_simple_flag",
                    "explicit_no_collision",
                    "simple_as_complex_without_shapes",
                )
                for entry in no_simple.values()
            )
            and no_simple["/Game/Developers/Christopher/1m_Plane_Reverse"]["kind"]
            == "complex_as_simple",
            "no-simple-collision entries are sorted, closed-vocabulary and typed",
            repr(no_simple.get("/Game/Developers/Christopher/1m_Plane_Reverse")),
        )

        meshes = real["meshes"]
        check(
            list(meshes) == sorted(meshes) and len(meshes) == MEASURED_COUNTS["meshes"],
            "meshes are sorted by package path",
        )
        structural_ok = True
        for mesh in meshes.values():
            expected = 0
            for body in mesh["body_setups"]:
                if body["element_start"] != expected:
                    structural_ok = False
                expected += body["element_count"]
            if expected != len(mesh["elements"]):
                structural_ok = False
            for element in mesh["elements"]:
                if element["type"] not in (
                    "box",
                    "sphere",
                    "sphyl",
                    "convex",
                    "tapered_capsule",
                ):
                    structural_ok = False
                if element["type"] == "convex":
                    if "index_data" in element or "index_count" in element:
                        structural_ok = False
                    if len(element["vertices_flat"]) != 3 * element["vertex_count"]:
                        structural_ok = False
        check(
            structural_ok,
            "every body slice indexes its merged element list; flat vertices only",
        )

        cana = meshes["/Game/Art/Environment/Props/Containers/Cans/SM_CanA"]
        box = cana["elements"][0]
        check(
            len(cana["elements"]) == 1
            and box["type"] == "box"
            and cana["body_setup"] == "BodySetup_0"
            and cana["collision_profile"] == "BlockAll"
            and cana["object_type"] == "ECollisionChannel::ECC_WorldStatic"
            and cana["collision_responses"]
            == [
                {"channel": "Interact", "response": "ECollisionResponse::ECR_Block"},
                {"channel": "AOE", "response": "ECollisionResponse::ECR_Block"},
                {"channel": "Ping", "response": "ECollisionResponse::ECR_Block"},
            ]
            and "complex_as_simple" not in cana,
            "SM_CanA collision profile and no guessed complex flag",
            repr({k: v for k, v in cana.items() if k != "elements"}),
        )
        check(
            all(
                math.isclose(actual, expected, abs_tol=1e-6)
                for actual, expected in zip(
                    box["center"], [0.13850065, -0.00038051605, 13.832164]
                )
            )
            and all(
                math.isclose(actual, expected, abs_tol=1e-6)
                for actual, expected in zip(
                    box["half_extent"], [15.940169, 15.669875, 25.463127]
                )
            )
            and box["rotation"] == {"pitch": 0.0, "yaw": 0.0, "roll": 0.0}
            and box["b_contribute_to_mass"] is True
            and box["collision_enabled"] == "ECollisionEnabled::QueryAndPhysics"
            and box["name"] == "None",
            "SM_CanA box half-extents (tolerance 1e-6)",
            repr(box),
        )
        check(
            cana["nav_collision"]["present"] is True
            and cana["nav_collision"]["has_area_data"] is False
            and cana["nav_collision"]["cooked"][0]["element_count"] == 410,
            "SM_CanA nav collision is cooked-only",
            repr(cana.get("nav_collision")),
        )

        hat = meshes["/Game/Art/Character/CivMale/Props/Hat/SM_CivMale_Hat_01"]
        convex = next(e for e in hat["elements"] if e["type"] == "convex")
        extents = [
            high - low for high, low in zip(convex["aabb_max"], convex["aabb_min"])
        ]
        check(
            convex["vertex_count"] == 32
            and len(convex["vertices_flat"]) == 3 * convex["vertex_count"]
            and "index_data" not in convex
            and max(extents) > 0.5
            and all(
                low <= high for low, high in zip(convex["aabb_min"], convex["aabb_max"])
            )
            and convex["transform"]["rotation"]["W"] == 1.0,
            "convex hull flat vertices and non-degenerate AABB",
            repr({k: v for k, v in convex.items() if k != "vertices_flat"}),
        )

        pillar = meshes["/Game/Art/Environment/Basement/Pillars/SM_PillarBasementA_12m"]
        sphyl = next(e for e in pillar["elements"] if e["type"] == "sphyl")
        check(
            sphyl["radius"] == 66.29773
            and sphyl["length"] == 1186.7773
            and sphyl["radius"] > 0.0
            and sphyl["length"] > 0.0,
            "sphyl radius and length are positive and exact",
            repr(sphyl),
        )

        street = meshes["/Game/Art/Environment/City/Streets/SM_StreetLrgA"]
        check(
            street["complex_as_simple"] is True
            and street["collision_trace_flag"]
            == "ECollisionTraceFlag::CTF_UseComplexAsSimple",
            "complex-as-simple comes from the authored trace flag",
            repr(
                {
                    k: v
                    for k, v in street.items()
                    if k not in ("elements", "body_setups")
                }
            ),
        )

        # -- opt-in index data end-to-end ----------------------------------
        index_out1 = tmpdir / "real-index-out1"
        index_run = run_producer(EXTRACTED, index_out1, ["--with-index-data"])
        check(
            index_run.returncode == 0
            and (index_out1 / "mesh_collision.json").is_file(),
            "producer --with-index-data exits 0",
            index_run.stderr.strip(),
        )
        with_index = json.loads((index_out1 / "mesh_collision.json").read_text())
        check(
            with_index["index_data_included"] is True
            and with_index["counts"] == MEASURED_COUNTS,
            "--with-index-data payload flag and counts",
            repr(with_index["counts"]),
        )
        indices_ok = True
        for mesh in with_index["meshes"].values():
            for element in mesh["elements"]:
                if element["type"] != "convex":
                    continue
                if element["index_count"] != len(element["index_data"]):
                    indices_ok = False
                if len(element["vertices_flat"]) != 3 * element["vertex_count"]:
                    indices_ok = False
                if any(
                    not 0 <= value < element["vertex_count"]
                    for value in element["index_data"]
                ):
                    indices_ok = False
        check(
            indices_ok,
            "every index is in range and index_count matches (all hulls)",
        )
        index_hat = with_index["meshes"][
            "/Game/Art/Character/CivMale/Props/Hat/SM_CivMale_Hat_01"
        ]
        index_convex = next(e for e in index_hat["elements"] if e["type"] == "convex")
        check(
            index_convex["index_count"] == 180
            and len(index_convex["index_data"]) == 180
            and index_convex["vertex_count"] == 32,
            "hat hull keeps its 180 authored indices in opt-in mode",
        )

        # -- idempotency ---------------------------------------------------
        out2 = tmpdir / "real-out2"
        run2 = run_producer(EXTRACTED, out2)
        index_out2 = tmpdir / "real-index-out2"
        index_run2 = run_producer(EXTRACTED, index_out2, ["--with-index-data"])
        check(
            run2.returncode == 0
            and index_run2.returncode == 0
            and (out1 / "mesh_collision.json").read_bytes()
            == (out2 / "mesh_collision.json").read_bytes()
            and (index_out1 / "mesh_collision.json").read_bytes()
            == (index_out2 / "mesh_collision.json").read_bytes(),
            "two runs are byte-identical in both modes",
        )

    print(f"PASS: {PASSED} checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
