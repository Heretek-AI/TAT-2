# W0p — shipped-lens measurement rig and provenance

**Status:** rig, flags, wrapper provenance and headless tests landed. **No GPU
numbers were produced in this wave** — this machine is shared and the integrator
measures on a quiet one (see “What the integrator must measure”).

## Why every earlier perf number is a relative A/B

`game/tests/perf/perf_matrix_runner.gd` used to force

```gdscript
_cam.fov = 60.0
_cam.far = 500.0
```

The shipped frame is neither:

| | old rig | shipped |
|---|---|---|
| vertical FOV | 60.0 | **54.54** (`thief_character.CAMERA_FOV`, UE 85 horizontal at 16:9) |
| horizontal FOV at 16:9 | 91.49° | **85.00°** |
| camera far | 500 m | **4000 m** (Godot `Camera3D` default; the game never overrides it) |

Two biases, in opposite directions:

- **FOV 60 is ~25.4 % wider than shipped** in the frustum-area proxy
  `tan(v/2)·tan(h/2)` (0.5926 vs 0.4724). Every pose therefore drew more of the
  level per frame — more draws, more primitives, more shadow casters in
  view — and sampled the scene at a different angular density. Bias: **cost
  high**.
- **far 500 m clips everything past 500 m.** Skybox shell, periphery/skyline
  geometry and any distant occluder were culled by the near far plane even
  though the shipped game renders them. Bias: **cost low**.

The two do not cancel and their sizes are pose-dependent, so the published
1080p ladder is a valid *relative* comparison of quality levels under one fixed
(wrong) frustum — it is **not** a claim about shipped frame time, shipped draws
or shipped VRAM. That framing is now explicit in the code, the log and this
report instead of implied.

## What changed

- `perf_matrix_runner.gd`: defaults to `54.54` / `4000`, accepts
  `--perf-fov=` / `--perf-far=`, re-asserts the lens at every pose, logs both in
  `PERF_RUN` and in each per-pose record (read back from the live camera). The
  six poses are unchanged.
- `perf_profile.gd`: fail-closed parsing and application of
  `--perf-fov`, `--perf-far`, `--perf-occlusion=on|off`,
  `--perf-mesh-lod=<float>`, `--perf-dir-shadow=on|off`,
  `--perf-shadow-splits=1|2|4`, `--perf-shadow-max-distance=<int>`.
  `apply()` writes `Viewport.use_occlusion_culling` and
  `Viewport.mesh_lod_threshold`; `config_mismatches()` verifies them plus the
  camera FOV/far and the moon (fail closed before any frame is recorded).
  `apply_directional_shadow()` is called by `mission_controller` after the
  weather preset and logs the values read back from the real moon as
  `PERF_SHADOW`.
- `build/qa/run_perf_matrix.sh`: passes `--perf-fov`/`--perf-far` explicitly,
  records a real 120-frame pre-warm, and logs GPU clocks/temperature/memory
  clock/power/utilization + clock-throttle reasons and `/proc/loadavg` before
  and after the measured run (`PERF_GPU_BEFORE/AFTER`, `PERF_LOAD_BEFORE/AFTER`,
  `PERF_PREWARM`).
- `game/tests/test_perf_profile.gd`: standalone headless suite for parser
  accept/reject, defaults, viewport application and `config_mismatches`.

Shipped values reported when no override is given: occlusion **on**
(`project.godot`), directional shadow **on**, PSSM **4 splits**, **80 m**
(`lights_and_shadows/directional_shadow/max_distance=80`).

## Provenance recorded per run

`PERF_HOST` (git, binary mode/stat, xdg data home), `PERF_ARGS` (all requested
levers incl. fov/far), `PERF_CONFIG` (effective availability/viewport/shadow),
`PERF_SHADOW` (moon read-back), `PERF_RUN` (fov, far, poses, mode),
per-pose `fov`/`far`, `PERF_GPU_*`, `PERF_LOAD_*`, `PERF_DISPLAY`
(host vs Xvfb).

## Remaining bias (do not silently ignore)

1. **Binary.** The wrapper prefers a release export
   (`build/tat2-linux-x86_64`); the editor binary is debug and not comparable.
   Check `binary_mode=` in `PERF_HOST`.
2. **Display path.** Host compositor and Xvfb are not comparable (Xvfb adds a
   ~25 ms/frame presentation copy at 720p on the reference RTX 4070). Xvfb runs
   are labelled `PERF_DISPLAY xvfb=…` and cannot be mixed into one table.
3. **Thermals are only partly controlled.** The 120-frame pre-warm raises
   clocks, but there is no soak and no fixed power limit. Clock-throttle
   reasons are recorded; a run whose `throttle=` is not `0x0000000000000000`
   (and not an idle reason) is flagged, not silently averaged.
4. **The quality ladder is the game's own** (`WeatherProfile` level 0/1/2 +
   lights/shadows), not a UE-settings parity claim.
5. **`mesh_lod_threshold`** only throttles the engine's own LOD transitions; it
   is not a substitute for authored LODs and does nothing in a headless/dummy
   renderer.
6. **Occlusion culling** is on in `project.godot` and can only be *measured*
   under Vulkan; headless runs prove the flag plumbing, not the culling.
7. **User save FOV.** The runner writes the camera directly, so a saved
   `fov` cannot drift the measured lens; the player's `base_fov` is untouched
   and its physics-driven FOV feedback is disabled while frozen.

## Exact 3-run protocol

Requirements: quiet machine (no other Godot, no GPU browsers/transcodes), host
compositor on the same refresh rate, AC power, performance power profile
recorded in the report, and the binary mode noted.

For each configuration, three back-to-back invocations (each one acquires the
`flock`, pre-warms 120 frames, then measures):

```bash
for i in 1 2 3; do
  build/qa/run_perf_matrix.sh --quality=high --scale=1.0 --scaling=bilinear \
    --tag="w0p_high_run$i"
done
```

Rules for turning logs into numbers:

1. Take `PERF_SUMMARY.per_pose[*].p50_ms` / `p95_ms` / `p99_ms` (and
   `one_percent_low_fps`) from each of the three logs.
2. Report the **median of the three** per pose; keep all three values.
3. If max−min of the three p50 exceeds 5 % for a pose, either re-run the
   outlier pair or publish the spread and mark that pose unstable. Never
   publish one run as "the" number.
4. Quote `fov`, `far`, `binary_mode`, `PERF_DISPLAY`, and the
   `PERF_GPU_*`/`PERF_LOAD_*` lines with the table. A number without them is an
   anecdote.
5. A/B pairs must be interleaved (A,B,A,B,A,B), not three A then three B, so a
   drifting ambient temperature affects both arms equally.

## What the integrator must measure

1. **Re-baseline the ladder at the shipped lens** (`54.54` / `4000`), all six
   poses: quality high / medium / low, scale 1.0 / 0.85 / 0.75 and
   bilinear / fsr1 / fsr2. The old 60/500 table cannot be compared with these
   numbers and must not be appended to.
2. **The four levers as 3-run A/B pairs** (same quality/scale otherwise):
   - `--occlusion=on` vs `--occlusion=off` (expect draw/GPU change only in
     Vulkan, and only where the occluders actually pay off);
   - `--mesh-lod=1.0` vs `--mesh-lod=0.5`;
   - `--dir-shadow=on` vs `--dir-shadow=off` (the moon is the main shadow cost,
     not the 6 hero omnis);
   - `--shadow-splits=4` vs `2` vs `1` at `--shadow-max-distance=80`, plus
     `--shadow-max-distance=40` as a separate arm.
3. **Confirm the known hero-shadow result** (6→2 barely moves draws) with
   `--shadows=2` at the shipped lens, so the "hero shadows are not the cost"
   claim rests on current numbers.
4. Publish per-pose draws/primitives/VRAM alongside frame times; the FOV fix
   changes the draw count materially, which is the most direct evidence the old
   table was frustum-biased.

## Gates run in this wave (headless, no GPU)

- `check_scripts_compile.gd` — `scripts checked: 83, broken: 0`
- `tests/test_perf_profile.gd` — `PERF_PROFILE_SUMMARY: fails=0` (56 checks)
- `tests/test_m2_player.gd` — `M2_SUMMARY: fails=0`
- `tests/run_tests.gd` — `SUMMARY: fails=0`

No frame-time, draw-call or VRAM number appears in this wave. The wrapper's
`--fov/--far/--occlusion/--mesh-lod/--dir-shadow/--shadow-splits/
--shadow-max-distance/--prewarm` validators were exercised for their abort
paths only; the measurement path was not run.
