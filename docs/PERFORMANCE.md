# TAT-2 Performance Notes

Measured on Godot `4.7.2.stable.flathub` (Forward+ / Jolt), headless load benchmark,
NVIDIA RTX 4070 Laptop target for the runtime.

## What changed

All work is in `game/src/core/level_loader.gd` unless stated otherwise.

| Area | Before | After |
|---|---|---|
| Mesh batching | one map-wide `MultiMeshInstance3D` per `.glb` (AABB spanned the whole city, never cullable) | partitioned into 32 m × 32 m XZ cells; explicit tight `custom_aabb` per chunk |
| Single-instance cells | 1-instance `MultiMesh` | plain `MeshInstance3D` |
| Distance culling | end 85 m only when mesh AABB < 1.5 m, using the merged map AABB | foliage/debris 22 m, props < 1.2 m → 45 m, props < 4 m → 95 m (effective ranges; each adds a 16 m chunk-radius pad because `visibility_range_*` measures the chunk AABB centre), structural unbounded |
| Shadows | off only when mesh AABB < 0.8 m | off for all foliage/debris and props < 1.2 m |
| Collision bodies | one `LevelCollision` `StaticBody3D` with 13,830 shapes (Guildhall) | per-cell bodies (`LevelCollision_<cx>_<cz>`) capped at 384 shapes per body; landscapes own `LandscapeCollision_<n>` |
| Skybox/periphery | full physics colliders | `*_SkyboxGeo` / `*_Periphery*` sublevels generate **no** colliders |
| Occlusion culling | disabled | `rendering/occlusion_culling/use_occlusion_culling=true` + `BoxOccluder3D` for 6–48 m structural meshes (max 768) |
| Positional shadow atlas | 4096 | **left at 4096** — only the 4 hero lights cast shadows, so 2048 would only blur them without a meaningful win |
| Lights | up to 96 live, no camera-distance fade | non-hero omni/spot lights fade 28 m → 40 m (`distance_fade_*`) |
| `light_probe.gd` | sampled every physics frame, raycast every light in range | ~12.5 Hz throttle, 25 m squared-distance early-out, per-position cache |
| Prop highlight | group scan every physics tick + `find_children` on every toggle | 10 Hz scan throttle; mesh list cached on the target by `VfxManager.set_prop_highlight()` |
| Loading | terrain/collider loops blocked the main thread | async path yields per sublevel, per landscape, and every 64 draw items |

## Measured (Guildhall, 13 sublevels)

Cold-process headless load, same 96-light budget and collision enabled:

| Metric | Old loader | New loader |
|---|---|---|
| Load time | **53.3 s** | **16.2 s** |
| Scene nodes | 1,190 | 5,651 (4,517 chunk nodes) |
| `MultiMeshInstance3D` | 891 map-wide | 2,030 chunked + 2,505 plain meshes |
| Max batch AABB diagonal | map-wide (hundreds of m) | **95.2 m** (p95 56 m) |
| Distance-culled nodes | ~0 | 1,110 |
| Static bodies (collision) | 1 | 68 |
| Collision shapes | 13,830 | 8,268 |

Old Manor: `chunks=2470`, `collision_bodies=40`, `collision_shapes=4539`, `occluders=571`.
Thieves' Den: `chunks=156`, `collision_bodies=2`, `collision_shapes=95`, `occluders=74`.

## How to verify at runtime

- `make test` — 15 headless suites; the perf suite asserts `chunks ≥ 500`, split collision
  bodies, occluder count, a chunk span < 140 m, and ≥ 300 distance-culled nodes for Guildhall.
  Current output: `chunks=4517, multimeshes=2030, collision_bodies=68, shapes=8268,
  occluders=768, max_chunk_span=95.2m, distance-culled=1110`.
- `make audit` — manifest coverage unchanged (`--min-coverage 0.90`).
- `make run` — press **F3** for the live overlay (FPS, frame ms, draw calls, visible
  objects/primitives, node count, VRAM, player position, contract title). It is implemented
  in `game/src/ui/hud.gd` (`toggle_fps_overlay()`), updates at 4 Hz.

## Measurement rig (2026-11-24)

- `build/qa/run_perf_matrix.sh` is the only supported frame-time path: release
  export, host compositor, vsync off, six fixed poses, one config per run.
- The rig defaults to the shipped lens (**54.54 vertical / 4000 m**), logs
  FOV/far/occlusion/LOD/shadow flags and GPU clocks, and enforces a thermal
  guard (**W4P**, full detail in
  [`reports/w4p-thermal-guard.md`](reports/w4p-thermal-guard.md)); `--max-temp`
  defaults to **95 °C**; `PERF_THERMAL` records the start, pre-warm, peak and
  peak RSS. A package temperature at the limit kills the run and exits 8. Do not
  rerun until the machine is cool.
- Thermal/memory gate (fail closed):
  - `--start-temp=<C>` (default **78**) — refuse a sustained run when the
    package is above this. A 91 °C machine may no longer start with
    `--max-temp=92`; the old guard had no headroom.
  - `--max-temp=<C>` (default **95**) — kill the launch at or above this.
  - `--max-rss-mb=<MB>` (default **8192**) — fail the run when `VmHWM`
    (`/proc/<pid>/status`) exceeds it. `VmRSS` samples are still logged as the
    curve. Each launch also gets a user scope with `MemoryMax=12G` /
    `MemorySwapMax=0` when `systemd-run --user --scope` works, with a logged
    fallback to a direct launch.
  - `--sample-sec=<s>` (default **1**) — an **independent** sampler process
    (not the wait loop) logs `PERF_THERMAL_SAMPLE` every tick for the pre-warm
    and the measured run, records `PERF_THERMAL_PREWARM_PEAK`, and kills the
    sampled PID at `>= --max-temp`. Both validation bounds are 60..105 with
    `start < max`. An unknown (`?`) package temperature, a sampler that does
    not start, or a missing sampler summary aborts instead of running.
- Proof without a GPU (safe on a hot host):
  `bash -n build/qa/run_perf_matrix.sh`,
  `build/qa/test_perf_guard.sh` (42 checks: decisions, argument bounds,
  machinery), and `build/qa/run_perf_matrix.sh --guard-check=79` → exit 8.
  A real measurement must still run on a cool host:
  `build/qa/run_perf_matrix.sh --quality=high --scale=1.0 --scaling=bilinear --tag=w4p_gate`.
- On the reference i9-14900HX host, package temperature idles around 82 °C and
  reaches the critical 100 °C under repeated Guildhall loads. With the 78 °C
  start gate that host refuses a sustained run until it idles down; raising
  `--start-temp` without cooling is not a substitute for headroom. Run **one**
  Godot process at a time; never run the matrix beside a test suite or bake.

- Xvfb is not a frame-time environment (same pose measured 66.55 ms vs 20.4 ms
  on the host); Xvfb numbers are labelled and not comparable.

## Known caveats

- Headless runs cannot read back `MultiMesh` instance transforms or `get_aabb()` (the dummy
  rendering server does not store them). Verification therefore reads the explicit
  `custom_aabb` we set, which is the same value the renderer uses for culling.
- Occlusion culling is conservative but not pixel-perfect: `BoxOccluder3D` boxes are sized to
  mesh AABBs, so openings inside a wall mesh (doors, archways) are covered by the box. This
  is why doors/windows/arches/railings are excluded from occluder creation. A visual pass in
  `make run` is still required on Guildhall and Old Manor before shipping.
- Occlusion culling can be toggled at runtime with
  `get_tree().root.use_occlusion_culling`; Godot 4.7 does not require a full
  game restart for the viewport property.
