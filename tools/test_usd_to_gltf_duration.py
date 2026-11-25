#!/usr/bin/env python3
"""Duration regression test for tools/usd_to_gltf.py (RE-F-04). Stdlib only.

Run with::

    python3 tools/test_usd_to_gltf_duration.py

The USD writer emits N samples at timecodes 0..N-1 with
``timeCodesPerSecond = N / authored_length``. Blender's glTF exporter writes
``seconds = frame / (render.fps * render.fps_base)`` (Blender 5.3,
``io_scene_gltf2/blender/exp/animation/keyframes.py:13``), so setting
``fps = timeCodesPerSecond`` exports ``(N-1)/N`` of the authored length.

``compute_render_fps`` must return a scene fps pair whose exported duration
``frame_span / (fps * fps_base)`` equals the authored length. Zero-span
(single-pose additive) clips keep the legacy behaviour and return ``None``.
"""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import usd_to_gltf  # noqa: E402  (no bpy at import time)

_compute_render_fps = getattr(usd_to_gltf, "compute_render_fps", None)


def exported_seconds(frame_span: float, retime: dict) -> float:
    """Seconds Blender writes for the last key: frame/(fps*fps_base)."""
    return frame_span / (retime["fps"] * retime["fps_base"])


class ComputeRenderFpsTest(unittest.TestCase):
    def helper(self, *args):
        if _compute_render_fps is None:
            self.fail(
                "usd_to_gltf.compute_render_fps is missing: the producer still "
                "sets fps=timeCodesPerSecond and exports (N-1)/N of the clip"
            )
        return _compute_render_fps(*args)

    def assert_duration(self, n, tps, first_frame, last_frame, authored=None):
        start, end = 0, n - 1
        span = last_frame - first_frame
        authored = n / tps if authored is None else authored
        retime = self.helper(tps, start, end, span)
        self.assertIsNotNone(retime)
        self.assertIsInstance(retime["fps"], int)
        self.assertGreater(retime["fps"], 0)
        self.assertGreater(retime["fps_base"], 0.0)
        self.assertAlmostEqual(retime["authored_length"], authored, delta=1e-12)
        self.assertAlmostEqual(exported_seconds(span, retime), authored, delta=1e-9)
        return retime

    def test_integer_sample_rate_is_exact(self):
        # 61 samples at 61 tps -> 1.0 s; frames 0..60 span 60 intervals.
        retime = self.assert_duration(61, 61.0, 0, 60)
        self.assertAlmostEqual(exported_seconds(60, retime), 1.0, delta=1e-9)

    def test_fractional_sample_rate_is_exact(self):
        # 41 samples at 61.5 tps -> 0.6666... s (not (40/41) of it).
        retime = self.assert_duration(41, 61.5, 0, 40)
        self.assertAlmostEqual(exported_seconds(40, retime), 41 / 61.5, delta=1e-9)

    def test_two_key_clip_spanning_the_full_clip(self):
        # Sparse 2-key face clip: keys at timecode 0 and N-1.
        retime = self.assert_duration(201, 30.15, 0, 200)
        self.assertAlmostEqual(exported_seconds(200, retime), 201 / 30.15, delta=1e-9)

    def test_two_key_two_sample_clip(self):
        retime = self.assert_duration(2, 120.0, 0, 1)
        self.assertAlmostEqual(exported_seconds(1, retime), 2 / 120.0, delta=1e-9)

    def test_zero_span_single_pose_is_left_alone(self):
        # 23 additive single-pose clips legitimately export duration 0.
        self.assertIsNone(self.helper(61.5, 0, 40, 0.0))
        self.assertIsNone(self.helper(61.5, 0, 0, 0))

    def test_missing_inputs_keep_legacy_behaviour(self):
        self.assertIsNone(self.helper(None, 0, 40, 40.0))
        self.assertIsNone(self.helper(0.0, 0, 40, 40.0))
        self.assertIsNone(self.helper(61.5, None, None, 40.0))
        self.assertIsNone(self.helper(61.5, 0, 40, None))
        self.assertIsNone(self.helper(61.5, 0, 40, float("nan")))

    def test_fps_fps_base_reproduce_the_requested_rate(self):
        retime = self.helper(61.5, 0, 40, 40.0)
        self.assertAlmostEqual(
            retime["fps"] * retime["fps_base"], retime["effective_fps"], delta=1e-9
        )
        self.assertAlmostEqual(retime["effective_fps"], 40 / (41 / 61.5), delta=1e-9)

    def test_legacy_fps_equals_tps_is_short(self):
        # Red proof of RE-F-04: the pre-fix mapping exports (N-1)/N.
        n, tps = 61, 61.0
        authored = n / tps
        span = n - 1
        legacy_seconds = span / tps
        legacy_ratio = legacy_seconds / authored
        self.assertNotAlmostEqual(legacy_ratio, 1.0, delta=1e-9)
        self.assertAlmostEqual(legacy_ratio, (n - 1) / n, delta=1e-12)
        self.assertLess(legacy_seconds, authored)
        self.assertAlmostEqual((legacy_ratio - 1.0) * 100.0, -1.639344, delta=1e-5)

    def test_errors_are_one_sample_interval(self):
        # The defect is exactly one sample interval at every sample rate.
        for n, tps in ((2, 120.0), (41, 61.5), (61, 61.0), (6910, 1632.0064697265625)):
            authored = n / tps
            legacy = (n - 1) / tps
            self.assertAlmostEqual(authored - legacy, 1.0 / tps, delta=1e-12)
            retime = self.helper(tps, 0, n - 1, float(n - 1))
            self.assertAlmostEqual(
                exported_seconds(n - 1, retime), authored, delta=1e-9
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
