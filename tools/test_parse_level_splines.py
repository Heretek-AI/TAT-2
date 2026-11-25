#!/usr/bin/env python3
"""Unit tests for the level-payload producers added for T09-GEOMETRY.

Covers the pure conversion helpers in `tools/parse_tables.py`:

* `ue_spline_params_to_godot()` — RE-B-04, `SplineMeshComponent.SplineParams`
  (UE component-local cm / radians) -> the documented Godot-local `"spline"`
  payload (metres, Y/Z swapped, roll sign flipped).
* `_level_asset_rel_key()` — RE-B-02/RE-B-01, UE world-asset path -> the
  `level_payloads` key, shared by the LevelInstance merge and the streaming
  graph.

Run from the repository root:

    python3 tools/test_parse_level_splines.py -v
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_tables  # noqa: E402

SPLINE_KEYS = {
    "p0",
    "t0",
    "p1",
    "t1",
    "scale0",
    "scale1",
    "offset0",
    "offset1",
    "roll0",
    "roll1",
}

# Verbatim `Properties.SplineParams` from
# extracted/json/Maps/Guildhall/Guildhall_Landscape.json (`SplineMeshComponent_0`),
# the first of the 10 spline components in that level.
REAL_SPLINE_PARAMS = {
    "StartPos": {"X": -134.47995, "Y": -178.81181, "Z": 4.4001063e-06},
    "StartTangent": {"X": 240.46698, "Y": 395.16928, "Z": -1.149257e-05},
    "StartScale": {"X": 0.7330429, "Y": 0.7330429},
    "StartRoll": -7.939853e-09,
    "StartOffset": {"X": -3.3904352, "Y": -4.6983495e-10},
    "EndPos": {"X": 134.47995, "Y": 178.81181, "Z": -4.4001063e-06},
    "EndScale": {"X": 0.7330429, "Y": 0.7330429},
    "EndTangent": {"X": 294.98346, "Y": 314.24802, "Z": 0.0},
    "EndOffset": {"X": -3.3904352, "Y": 0.0},
}


class TestSplineParams(unittest.TestCase):
    def test_real_dump_literal(self):
        out = parse_tables.ue_spline_params_to_godot(REAL_SPLINE_PARAMS)
        self.assertEqual(set(out), SPLINE_KEYS)
        # Godot = (UE.x, UE.z, UE.y) * 0.01, rounded to 4 dp like every other
        # payload position.
        self.assertEqual(out["p0"], [-1.3448, 0.0, -1.7881])
        self.assertEqual(out["t0"], [2.4047, 0.0, 3.9517])
        self.assertEqual(out["p1"], [1.3448, 0.0, 1.7881])
        self.assertEqual(out["t1"], [2.9498, 0.0, 3.1425])
        # Scales are authored multipliers (width, height), never x0.01.
        self.assertEqual(out["scale0"], [0.73304, 0.73304])
        self.assertEqual(out["scale1"], [0.73304, 0.73304])
        # Offsets are authored in the component (Y, Z) plane: UE (0, X, Y) ->
        # Godot (0, Y, X) in metres, and Godot X is always 0.
        self.assertEqual(out["offset0"], [0.0, 0.0, -0.0339])
        self.assertEqual(out["offset1"], [0.0, 0.0, -0.0339])
        for key in ("offset0", "offset1"):
            self.assertEqual(out[key][0], 0.0)
        # Roll is already radians and flips sign under the det = -1 permutation.
        self.assertEqual(out["roll0"], 0.0)
        self.assertEqual(out["roll1"], 0.0)
        # The record must be plain JSON numbers/arrays for the payload writer.
        self.assertEqual(json.loads(json.dumps(out)), out)
        for key in ("p0", "t0", "p1", "t1", "offset0", "offset1"):
            self.assertEqual(len(out[key]), 3)
        for key in ("scale0", "scale1"):
            self.assertEqual(len(out[key]), 2)
        for key in ("roll0", "roll1"):
            self.assertIsInstance(out[key], float)

    def test_synthetic_roll_scale_offset(self):
        sp = {
            "StartPos": {"X": 100.0, "Y": 200.0, "Z": 300.0},
            "StartTangent": {"X": 1.0, "Y": 2.0, "Z": 3.0},
            "EndPos": {"X": -100.0, "Y": -200.0, "Z": -300.0},
            "EndTangent": {"X": -1.0, "Y": -2.0, "Z": -3.0},
            "StartScale": {"X": 2.5, "Y": 0.5},
            "EndScale": {"X": 0.25, "Y": 4.0},
            "StartRoll": 0.5,
            "EndRoll": -1.25,
            "StartOffset": {"X": 10.0, "Y": 20.0},
            "EndOffset": {"X": -30.0, "Y": 0.0},
        }
        out = parse_tables.ue_spline_params_to_godot(sp)
        self.assertEqual(out["p0"], [1.0, 3.0, 2.0])
        self.assertEqual(out["p1"], [-1.0, -3.0, -2.0])
        self.assertEqual(out["t0"], [0.01, 0.03, 0.02])
        self.assertEqual(out["scale0"], [2.5, 0.5])
        self.assertEqual(out["scale1"], [0.25, 4.0])
        self.assertEqual(out["offset0"], [0.0, 0.2, 0.1])
        self.assertEqual(out["offset1"], [0.0, 0.0, -0.3])
        self.assertEqual(out["roll0"], -0.5)
        self.assertEqual(out["roll1"], 1.25)

    def test_missing_optional_fields_use_ue_defaults(self):
        sp = {
            "StartPos": {"X": 0.0, "Y": 0.0, "Z": 0.0},
            "EndPos": {"X": 0.0, "Y": 0.0, "Z": 600.0},
            "StartTangent": {"X": 600.0, "Y": 0.0, "Z": 0.0},
            "EndTangent": {"X": 600.0, "Y": 0.0, "Z": 0.0},
        }
        out = parse_tables.ue_spline_params_to_godot(sp)
        self.assertEqual(out["scale0"], [1.0, 1.0])
        self.assertEqual(out["scale1"], [1.0, 1.0])
        self.assertEqual(out["offset0"], [0.0, 0.0, 0.0])
        self.assertEqual(out["offset1"], [0.0, 0.0, 0.0])
        self.assertEqual(out["roll0"], 0.0)
        self.assertEqual(out["roll1"], 0.0)
        self.assertEqual(out["p1"], [0.0, 6.0, 0.0])

    def test_rejects_incomplete_or_non_dict(self):
        self.assertIsNone(parse_tables.ue_spline_params_to_godot(None))
        self.assertIsNone(parse_tables.ue_spline_params_to_godot({}))
        self.assertIsNone(
            parse_tables.ue_spline_params_to_godot(
                {"EndPos": {"X": 1.0, "Y": 2.0, "Z": 3.0}}
            )
        )
        self.assertIsNone(
            parse_tables.ue_spline_params_to_godot(
                {"StartPos": {"X": 1.0, "Y": 2.0, "Z": 3.0}}
            )
        )

    def test_real_dump_first_spline_matches(self):
        dump = (
            Path(parse_tables.ROOT)
            / "extracted"
            / "json"
            / "Maps"
            / "Guildhall"
            / "Guildhall_Landscape.json"
        )
        if not dump.is_file():
            self.skipTest(f"extracted dump not present: {dump}")
        exps = json.loads(dump.read_text())
        comps = [e for e in exps if e.get("Type") == "SplineMeshComponent"]
        self.assertTrue(comps, "no SplineMeshComponent in Guildhall_Landscape")
        raw = comps[0]["Properties"]["SplineParams"]
        self.assertEqual(raw, REAL_SPLINE_PARAMS)
        self.assertEqual(
            parse_tables.ue_spline_params_to_godot(raw),
            parse_tables.ue_spline_params_to_godot(REAL_SPLINE_PARAMS),
        )


class TestLevelAssetRelKey(unittest.TestCase):
    def test_game_maps_prefix(self):
        self.assertEqual(
            parse_tables._level_asset_rel_key(
                "/Game/Maps/OldManor/OldManor_PathBlockers.OldManor_PathBlockers"
            ),
            "OldManor/OldManor_PathBlockers",
        )
        self.assertEqual(
            parse_tables._level_asset_rel_key("/Game/Maps/Buildings/Alley/Alley_1800"),
            "Buildings/Alley/Alley_1800",
        )

    def test_game_prefix_outside_maps(self):
        # RE-B-02: FacadeA/FacadeB live under Art/..., ApartmentE under Developers/.
        self.assertEqual(
            parse_tables._level_asset_rel_key(
                "/Game/Art/Environment/City/Facades/Level_Instances/FacadeA.FacadeA"
            ),
            "Art/Environment/City/Facades/Level_Instances/FacadeA",
        )
        self.assertEqual(
            parse_tables._level_asset_rel_key(
                "/Game/Developers/gjasp/Maps/Apartments/ApartmentE.ApartmentE"
            ),
            "Developers/gjasp/Maps/Apartments/ApartmentE",
        )

    def test_rejects_self_reference(self):
        self.assertIsNone(
            parse_tables._level_asset_rel_key(
                "/Game/Maps/OldManor/OldManor_P.OldManor_P",
                self_key="OldManor/OldManor_P",
            )
        )
        self.assertIsNone(
            parse_tables._level_asset_rel_key(
                "/Game/Art/Environment/City/Facades/Level_Instances/FacadeA",
                self_key="Art/Environment/City/Facades/Level_Instances/FacadeA",
            )
        )

    def test_rejects_non_game_and_empty(self):
        self.assertIsNone(parse_tables._level_asset_rel_key(""))
        self.assertIsNone(parse_tables._level_asset_rel_key(None))
        self.assertIsNone(parse_tables._level_asset_rel_key("/Script/Engine.World"))
        self.assertIsNone(parse_tables._level_asset_rel_key("/Game/"))
        self.assertIsNone(parse_tables._level_asset_rel_key("/Game/Maps/"))

    def test_streaming_uses_the_same_normaliser(self):
        # RE-B-01: streaming_levels[] entries are normalised exactly like a
        # LevelInstance target.
        self.assertEqual(
            parse_tables._level_asset_rel_key(
                "/Game/Maps/Guildhall/Guildhall_Audio.Guildhall_Audio"
            ),
            "Guildhall/Guildhall_Audio",
        )
        self.assertEqual(
            parse_tables._level_asset_rel_key(
                "/Game/Maps/Guildhall/Guildhall_Audio.Guildhall_Audio"
            ),
            parse_tables._level_asset_rel_key("/Game/Maps/Guildhall/Guildhall_Audio"),
        )
        self.assertIsNone(
            parse_tables._level_asset_rel_key(
                "/Game/Maps/Guildhall/Guildhall_P.Guildhall_P",
                self_key="Guildhall/Guildhall_P",
            )
        )


if __name__ == "__main__":
    unittest.main()
