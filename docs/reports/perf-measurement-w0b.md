# W0b — measurement truth: quality ladder, `mission_ready`, fixed-pose matrix

**Date:** 2026-11-24
**Wave:** W0b (parallel worktree `/tmp/opencode/tat2-w0b`)
**Base:** `efa0934` — `docs: record the gameplay truth wave, measured performance and residuals`
**Scope:** make performance measurement honest and repeatable. This wave does
**not** claim an FPS improvement; it fixes the inputs, the load-complete
boundary and the capture path so the next wave can measure a real ladder.

## Why the previous ladder was invalid

- `WeatherProfile.quality_level()` already read `settings.graphics_quality`,
  but `SaveSystem._defaults()` never wrote the key, Settings never exposed it,
  and no CLI flag set `WeatherProfile.set_quality_level()`. Every "low /
  medium / high" run therefore applied level 2; four runs log the same
  `WeatherQuality: desktop level=2`.
- `measure_fps.sh` passed no override and left the saved `vsync: true` in
  effect.
- The medium run was truncated (no completion marker), yet its samples were
  reported.
- A frame-time run under Xvfb was mixed with host-compositor numbers. Xvfb
  adds a large presentation cost at the same resolution (measured below), so
  those numbers are not comparable.

## What changed

### 1. Quality wiring

- `game/src/core/save_system.gd`: `settings.graphics_quality` defaults to
  `"high"`; `_ensure_defaults()` normalises missing, wrong-typed and unknown
  values to `high` and lower-cases the three valid keys (`low`, `medium`,
  `high`). `mobile_quality` is untouched.
- `game/src/ui/settings_ui.gd`: desktop-only **Graphics Quality**
  OptionButton (Low/Medium/High) in the existing Graphics Quality card. It
  persists `graphics_quality`, applies `WeatherProfile.set_quality_level()`
  immediately and never rewrites `mobile_quality`.
- `game/src/core/perf_profile.gd`: fail-closed parser/applier for
  `--perf-quality`, `--perf-scale`, `--perf-scaling`, `--perf-lights`,
  `--perf-shadows`, `--perf-vsync`. It applies before the mission scene is
  instantiated, logs one `PERF_CONFIG` JSON line with the effective values,
  and rejects unknown `--perf-*` flags rather than silently reusing the last
  configuration.
- `game/src/core/mobile_profile.gd`: static QA light/shadow cap overrides
  (`set_override_limits` / `clear_override_limits`); `reset_test_state()`
  clears them. The desktop policy (160 / 6) is unchanged when no override is
  set.
- `game/src/ui/main_menu.gd`: applies the CLI envelope before the startscreen
  backdrop and mission start; `--perf-matrix` starts the exported-runner path
  (release exports do not honour `--script`).

### 2. Load-complete signal

`mission_controller.gd` now has:

```gdscript
signal mission_ready(map_id: String, stats: Dictionary)
```

It is emitted once per `start_contract()`, after the level build, player/AI/
loot/clue/door/device spawns and `finish_loading()`. It does not change
gameplay. Harnesses wait on this instead of polling player + doors, so a
truncated load cannot look complete.

### 3. Fixed-pose harness

- `game/tests/perf/perf_matrix_runner.gd` (Node, shared implementation) and
  `game/tests/perf/perf_matrix.gd` (SceneTree entry for `--script`).
- One mission load, wait for `mission_ready`, discard 180 warm-up frames, then
  the six Guildhall poses taken from the capture scripts: `spawn_overlook`,
  `gate_approach`, `gate_sign`, `foyer`, `upper_foyer`, `door_approach`.
- Per pose: 3 s hold + 30° pan over 4 s; records wall-clock frame time,
  `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS`,
  `viewport_get_measured_render_time_cpu/gpu`, draw calls, visible objects,
  primitives, node count, VRAM, light nodes, device nodes and level chunks.
  Emits one JSON object per pose plus `PERF_SUMMARY` and `PERF_DONE`.
- The player is frozen (physics and look input off). The player camera is used
  so the 1P viewmodel stays in frame; the path reads no input.
- Exit codes: 0 complete, 2 bad config/pose, 3 timeout/map mismatch,
  4 deadline, 5 runtime/config mismatch, 6 truncated pose list. The wrapper
  also fails a log without `PERF_CONFIG` / `PERF_SUMMARY` / `PERF_DONE`.
- `build/qa/run_perf_matrix.sh`: one config per invocation, `flock` + live
  process check, isolated `XDG_DATA_HOME`, `--audio-driver Dummy`, vsync off,
  wall-clock timeout, `stdbuf` line-buffered log capture, optional
  `nvidia-smi` before/after. It prefers `build/tat2-linux-x86_64` (release
  export) and falls back to `tools/godot`. Host compositor by default; Xvfb is
  a labelled fallback because its presentation path is not comparable.

### 4. Tests

Suite 85 (`run_tests.gd`) asserts:

- `graphics_quality` defaults to `high`, accepts low/medium/high, and
  normalises unknown/non-string values to `high`;
- the `--perf-*` parser accepts a full valid set and rejects unknown quality,
  scale, scaling, negative lights, non-numeric shadows, bad vsync and unknown
  flags; `--perf-matrix` is a selector, not a value;
- `mission_ready` exists on `mission_controller.gd` and is emitted for the
  Contract 3 mission loaded earlier in the suite (map `old_manor`).

## Validation (one pose, 300 frames)

Environment: native Godot 4.7.2 release export from this worktree,
NVIDIA GeForce RTX 4070 Laptop GPU, driver 620.73.04, Vulkan 1.4.357,
Forward+, host Wayland compositor (119.88 Hz reported), vsync off, Dummy audio.
Contract 4 (Guildhall), pose `spawn_overlook`, 180 warm-up frames discarded,
300 measured frames, frame mode (hold/pan fraction scaled to the 300 frames).

`PERF_CONFIG` (1080p):

```json
{"args":{"lights":160,"quality":"high","scale":1.0,"scaling":"bilinear","shadows":6,"vsync":0},"binary":"/tmp/opencode/tat2-w0b/build/tat2-linux-x86_64","driver":"vulkan","effective":{"lights":160,"quality":"high","quality_level":2,"requested":true,"scale":1.0,"scaling":"bilinear","shadows":6,"vsync":"off"},"engine":"4.7.2-stable (official)","git_sha":"efa0934a30aa","gpu":"NVIDIA GeForce RTX 4070 Laptop GPU","gpu_api":"1.4.357","gpu_vendor":"NVIDIA","refresh_hz":119.879997253418,"renderer":"forward_plus","resolution":"1920x1080","window":"1920x1080"}
```

The `git_sha` is the worktree base `efa0934` because these runs happened
before the W0b commit existed. The measured tree is the W0b `feat(perf)`
commit; only the `TAT_GIT_SHA` provenance differs.

| Metric (p50 unless noted) | 1920×1080 | 1280×720 |
|---|---:|---:|
| Wall frame time | **20.40 ms** | **21.18 ms** |
| Wall FPS (p50 / mean) | 49.0 / 48.3 | 47.2 / 45.9 |
| 1% low FPS | 29.6 | 27.9 |
| p95 / p99 frame | 25.12 / 29.80 ms | 28.66 / 34.63 ms |
| `TIME_PROCESS` | 21.73 ms | 22.50 ms |
| `TIME_PHYSICS_PROCESS` | 4.92 ms | 4.84 ms |
| measured render CPU | 7.26 ms | 7.40 ms |
| measured render GPU | 19.67 ms | 17.61 ms |
| draw calls | 9,738 | 10,015 |
| visible objects | 11,015 | 11,459 |
| primitives | 10,211,597 | 9,550,670 |
| node count | 37,397 | 37,397 |
| VRAM | 3,683.2 MB | 3,565.6 MB |
| light nodes / devices / chunks | 175 / 903 / 5,735 | 175 / 903 / 5,735 |

`PERF_DONE poses=1 expected=1 samples=300` (both runs). The exported Wayland
process hung in window teardown after the marker; the wrapper printed
`PERF_TEARDOWN forced_kill=1 after PERF_DONE` and still exited 0, with all
markers present. The X11/Xvfb path exits cleanly.

### Run-to-run variance is larger than the 720p/1080p delta here

A repeat of the 1080p pose measured 21.00 ms p50 (GPU 19.57 ms); the final
1080p run measured 20.40 ms. A 120-frame host 720p run on a cool GPU measured
16.95 ms, while the final 300-frame 720p run started at 65.6 °C and measured
21.18 ms (GPU 17.61 ms). The pose is geometry/CPU-bound: draw calls, visible
objects and the running AI/world state differ between runs, and a hot GPU
starts a run in a different power state. Do **not** derive a resolution fit
from one pass of this pose; the full matrix needs repeats and a recorded
thermal state. The wrapper records `nvidia-smi` temperature/clock/power before
and after for exactly this reason.

### Ladder proof

Short 30-frame host runs (same pose, 1280×720) with the only change being
`--perf-quality`:

| CLI | `PERF_CONFIG.effective.quality_level` | WeatherProfile log | p50 frame |
|---|---:|---|---:|
| `--perf-quality=low` | 0 | `WeatherQuality: desktop level=0` | 18.22 ms |
| `--perf-quality=medium` | 1 | `WeatherQuality: desktop level=1` | 17.87 ms |
| `--perf-quality=high` | 2 | `WeatherQuality: desktop level=2` | 20.40 ms (300-frame run) |

The old failure mode (all runs level 2) is gone. These short runs are not a
ladder conclusion: 30 frames and a geometry-bound exterior pose cannot rank
the post-effect levels. The full six-pose matrix is required.

### Xvfb is not a frame-time environment

The same 1080p pose under Xvfb at the same quality measured **66.55 ms p50**
(15.0 FPS; GPU 24.46 ms) versus **21.00 ms p50** on the host. The 720p pair is
43.21 ms (Xvfb) versus 19.85–21.18 ms (host 300-frame runs). The wrapper therefore defaults to the
host compositor and labels Xvfb runs; do not mix the two.

## Honest limits

- **This is one pose, not the matrix.** `spawn_overlook` is an exterior,
  draw-call-heavy view (9.7k draw calls, 11k visible objects). Its 720p and
  1080p results are within run-to-run/world-state variance (20.40 vs 21.18 ms
  in the final pair), so it cannot substitute for the interior/fill-bound poses
  or for the old single-view `--print-fps` baseline. Do not publish a new
  "13 ms + 14 ms pixel" fit from this table.
- The world (AI, devices, HUD) keeps running while the player is frozen. That
  is intentional gameplay cost, but pose-to-pose AI state can vary.
- The measured render CPU/GPU values are Godot's per-viewport counters; they
  can exclude passes or under-report on some drivers. Wall frame time is the
  primary number; the counters are diagnostics.
- `TIME_PROCESS` is Godot's full-frame monitor, not a pure `_process()` CPU
  split (it can track the frame period when uncapped).
- The release export hangs at exit on this Wayland compositor after
  `PERF_DONE`; the wrapper terminates it after a 10 s grace. The measurement
  is complete, but the teardown quirk is recorded here, not hidden.
- The full matrix was not run in this worktree: other workers were using
  headless Godot during the validation window and the wave instructions
  reserve the full six-pose run for the integrator on `main`.

## Commands

```bash
# Full matrix, one serialized config per invocation (release export on main):
build/qa/run_perf_matrix.sh --quality=high   --scale=1.0  --scaling=bilinear --lights=160 --shadows=6 --res=1920x1080 --tag=high_1080
build/qa/run_perf_matrix.sh --quality=medium --scale=0.85 --scaling=fsr1     --lights=80  --shadows=3 --res=1920x1080 --tag=medium_085_fsr1
build/qa/run_perf_matrix.sh --quality=low    --scale=0.75 --scaling=fsr2     --lights=40  --shadows=1 --res=1920x1080 --tag=low_075_fsr2
build/qa/run_perf_matrix.sh --quality=high   --scale=1.0  --scaling=bilinear --res=1280x720  --tag=high_720

# Short validation used here (one pose, 300 frames):
build/qa/run_perf_matrix.sh --quality=high --scale=1.0 --scaling=bilinear \
  --lights=160 --shadows=6 --res=1920x1080 --pose=spawn_overlook \
  --frames=300 --warmup=180 --tag=w0b_validate_host_1080

# Gates:
XDG_DATA_HOME=/tmp/opencode/w0b-data tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
XDG_DATA_HOME=/tmp/opencode/w0b-data tools/godot --headless --path game --script res://tests/run_tests.gd
XDG_DATA_HOME=/tmp/opencode/w0b-data tools/godot --headless --path game --script res://tests/test_m2_player.gd
XDG_DATA_HOME=/tmp/opencode/w0b-data tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
make audit
```

## Gate results (this worktree)

| Gate | Result |
|---|---|
| compile | 72 checked, 0 broken |
| `run_tests.gd` | `SUMMARY: fails=0` (59 suites; suite 85 added) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` |
| E2E | `fails=0 passed=264 total=264` |
| `probe_leak.gd` | exit 0, no `SCRIPT ERROR` |
| `make audit` | `AUDIT PASS` (tracked baseline unchanged) |

`make audit` initially failed only because this worktree lacked the ignored
`tools/bin/vgmstream/vgmstream-cli`; linking the tool from the main checkout
restored `vgmstream CLI decoder r2168 (Oct 25 2026)` and the tracked baseline
matched again. No baseline refresh was needed.
