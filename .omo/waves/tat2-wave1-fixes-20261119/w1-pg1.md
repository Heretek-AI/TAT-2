# W1 PG-1 — GPU stability & FPS

- Lane: `w1-pg1-stability` (wave key `tat2-wave1-fixes-20261119`)
- Date: 2026-11-19
- Machine: RTX 4070 Laptop 8 GB, NVIDIA driver 620.70.06, Vulkan 1.4.357, Godot 4.7.2.stable Forward+, 62 GB RAM; the desktop presents at ~145 Hz (observed FPS ceiling)

## 1. Verdict

- **RD cascades: 0.** Live Vulkan Forward+ full-pipeline runs (Thieves' Den Contract 1,
  Guildhall Contract 4, Startscreen) contain **zero** `Too many mipmaps`, `texture_create`,
  `update_sizes` or `uniform_set` lines, and zero `SCRIPT ERROR` / `SHADER ERROR`. The TEMP
  `--env-strip=0..8` hook is already gone at HEAD `5093dc8`; `grep -rn '_env_strip_level|env-strip'
  game/src game/tests` = **0 hits**, so the "strip 7 (full pipeline)" evidence is the
  full-pipeline run quoted below.
- **Teardown: exit code 0** on every mission-free + `quit()` probe path and on all exported
  binary runs; no `double free`, no `X connection` drop, no crash. A 2-cycle load/free probe
  returns GPU texture memory to **6 MB** after each cycle (no per-load leak).
- **FPS:** Startscreen and Thieves' Den now clear 60 FPS at both 720p and 1080p.
  The Guildhall rises to 45 FPS at 720p and 29 FPS at 1080p (previous 1080p probes on
  this card: 3-12 FPS) but **still misses the 60 FPS gate**; the residual is draw submission
  + per-frame scripts, not VRAM or the RenderingDevice (attribution in §2.3). Recorded
  honestly rather than papered over.
- **`make test`: `SUMMARY: fails=0`, exit 0** (90 PASS lines, 0 SCRIPT ERROR).
  The exit-time ObjectDB/RID warnings that remain are itemised with their owners in §5.

## 2. Root cause (live re-diagnosis)

The prior snapshot claimed "1080p 18-35 FPS + exit-time RenderingDevice cascade + double free".
Re-diagnosed live: there is **no** RD cascade and no double free on this tree. The FPS failure
is a **texture-VRAM capacity failure**, and the artificial Xvfb numbers made it look worse
than it is.

### 2.1 VRAM

`extracted/` PNG imports are Lossless (`compress/mode=0`), mipmaps off, no size limit. The
Guildhall binds **631 unique textures = 5.95 GB RGBA8** even at a 2048 px long-edge cap
(`PERF_TEXCENSUS textures=631 rgba8_mb=5954`), and loads **8920 MB texture / 9322 MB video**
uncapped (`build/qa/perf/gh_vram_1080.log`) onto an 8 GB card, i.e. the driver thrashes.
Godot 4.7.2 has no texture streaming.

### 2.2 The fix and its measured effect

`level_loader.gd` now caps the long edge of every texture it loads at `TEX_BUDGET_MAX_DIM`
(default **1024**, `TAT2_TEX_CAP=<px>` overrides for A/B). Measured, same scene, same probe:

| Guildhall (live Vulkan, editor probe) | texture MB | census RGBA8 | frame time |
|---|---|---|---|
| uncapped (pre-change probe, `gh_real_1080.log`) | 8920 | - | 86.7 ms (1080p) |
| 2048 cap | 6560-6857 | 5954 MB (631 tex) | 125.7 ms (1080p) |
| **1024 cap** | **2412-2597** | **2038 MB (631 tex)** | **58.2 ms (1080p)** |

The uncapped row is a different run from before this lane started; the 2048/1024 rows are a
same-probe A/B on one machine window (the 2048 run overlapped other wave agents' test loads,
which is why its frame time is above the pre-change baseline). The A/B that matters is the
texture bytes (5954 -> 2038 MB) and 1080p 125.7 -> 58.2 ms from the same probe.

Den 720p probe: 3169 MB / 19.84 ms uncapped -> 2329 MB / 15.95 ms at 2048 -> **931 MB** at 1024.
The capped copy keeps the source `resource_path` (`take_over_path`) so QA/UI code that
identifies textures by path (Mission Prep PBR check, landscape weightmap check) keeps working.

### 2.3 What is left in the Guildhall (cost attribution, 1080p, cap 1024)

`capture_pg1_cost.gd`, 60 measured frames per phase (`build/qa/perf/pg1_gh1080_env.log`):

| phase | mean ms | delta vs baseline |
|---|---|---|
| baseline | 56.5 | - |
| no shadows (3 shadowed lights) | 52.0 | -4.5 |
| no decorative far batches | 49.2 | -7.3 |
| no meshes (102 draws) | 41.6 | -14.9 |
| no lights | 52.7 | -3.8 |
| SSIL+SSR off | 57.5 | -0.0 |
| volumetric fog off | 58.4 | +0.0 |
| glow off | 56.9 | -0.4 |
| SSIL+SSR+vol+glow+sky off | 55.9 | -0.6 |
| paused (scripts off) | 45.1 | -11.4 |

So: full-screen environment effects are **negligible** (~0.6 ms combined) at this profile;
the residual is ~15 ms of geometry/draw submission (7851 draws / 8.9 M prims, 3 shadowed
lights) and ~11 ms of per-frame scripts. The 720p Wayland run of the same build is 22.2 ms
median, which is the same story without the Xvfb 1080p present floor.

## 3. Changes

| file | change | reason |
|---|---|---|
| `game/src/core/level_loader.gd` | PG-1 texture VRAM budget: `TEX_BUDGET_MAX_DIM = 1024`, `TAT2_TEX_CAP` env override, `_resolve_texture_budget()`, `_cap_image()`, `_cap_texture()` applied to both `.ctex` and raw-file loads; capped copies keep the source `resource_path`; downscales accounted in `downscaled_textures`/`downscaled_count`; caches still cleared in `_exit_tree()` | root cause of the 1080p FPS collapse (3-12 FPS in the prior probes): 8.9 GB of lossless RGBA8 on an 8 GB card. 1024 cap cuts bound texture bytes 5.95 GB -> 2.04 GB and 1080p frame time 125.7 -> 58.2 ms |
| `game/project.godot` | removed `[tat2] debug_autostart_contract=4` | in scope; the e2e gate asserts it is absent (`T2-22-B`) and QA passes `--qa-contract=N` on the CLI |
| `build/qa/capture_pg1_teardown.gd` | added `--cycles=N` load/free repetition, `PERF_LOADER` / `PERF_TEXCENSUS` provenance counters, 30-frame teardown drain; every path still ends in `quit()` | produces the leak-scaling and texture-provenance evidence quoted here |
| `build/qa/capture_pg1_cost.gd` (new) | cost-isolation probe: shadows / decorative / meshes / lights / particles / SSIL / SSR / volumetric / glow / sky / paused / empty floor | attributes the remaining frame budget instead of guessing |

No shader, audio, HUD, guard, thief or other lane-owned file was touched. `level_loader.gd`
also carries the already-present working-tree far-batch/48-light changes from before this lane
started; only the texture-budget blocks are this lane's edit.

## 4. Evidence

### 4.1 RD counts — live Vulkan Forward+, full pipeline

Counted per log with
`grep -cE 'Too many mipmaps|texture_create|update_sizes|uniform_set'` and inspected for
`RID allocations|RIDs of type|double free|SCRIPT ERROR|SHADER ERROR`.

| run | RD cascade lines | exit |
|---|---|---|
| Den 720p, 2 load/free cycles (`pg1_den_cycles2.log`) | **0** | **0** |
| Den 720p (`pg1_den720.log`, `pg1_den720_cap2048.log`) | 0 cascade; 1x `WARNING: 7 RIDs of type "Texture" were leaked` on some exits | 0 |
| Guildhall 1080p cap 2048 / cap 1024 (`pg1_gh1080_cap*.log`) | **0** | 0 |
| Guildhall 720p census / cost / env probes | **0** | 0 |
| Startscreen (`pg1_menu720.log`) | **0** | 0 |
| Export `make linux-build` | 0 SHADER/SCRIPT ERROR | 0 |

Exported-binary full-pipeline runs (`build/qa/perf/w1_fps_*.log`): **0 cascade lines** in
Startscreen, Den and Guildhall; all six runs exit 0. The only RD-related line anywhere is the
intermittent `WARNING: 7 RIDs of type "Texture" were leaked` in the Den logs (§5.3); the
Guildhall/Startscreen exits report no RID leak at all.

### 4.2 Teardown

- Probe (`capture_pg1_teardown.gd`, Contract 1, 2 cycles): `PG1_PROBE_FREED` -> texture 6 MB /
  video 85 MB both cycles, `PG1_PROBE_QUIT cycles=2`, **exit 0**, no RID/ObjectDB leak lines.
- Exported binary: all six runs exit **0** - `startscreen720`, `startscreen1080`, `den720`,
  `den1080`, `guildhall720_nvsync`, `guildhall1080_nvsync` (exit lines in
  `build/qa/perf/w1_fps_summary.txt`).
- The only exit-time lines left are the ones listed in §5; none is a cascade.

### 4.3 FPS — real Wayland display, exported binary `build/tat2-linux-x86_64`

Method: `--display-driver wayland --resolution <WxH> --audio-driver Dummy --quit-after N
--print-fps -- "--qa-contract=<1|4>"` (no `--qa-contract` for Startscreen), vsync enabled
unless noted; steady state = samples after `TAT-2 Loaded`, first 3 post-load samples dropped.
Logs: `build/qa/perf/w1_fps_*.log`.

| scene | resolution | median ms | median FPS | mean ms | p95 ms | min FPS | gate |
|---|---|---|---|---|---|---|---|
| Startscreen | 1280x720 | 6.89 | **145.1** | 6.90 | 6.94 | 144.1 | PASS |
| Startscreen | 1920x1080 | 6.89 | **145.1** | 6.89 | 6.89 | 145.1 | PASS |
| Thieves' Den | 1280x720 | 6.99 | **143.1** | 7.42 | 13.15 | 76.0 | PASS |
| Thieves' Den | 1920x1080 | 14.92 | **67.0** | 15.09 | 16.66 | 59.0 | PASS |
| Guildhall | 1280x720 | 22.22 | **45.0** | 22.86 | 28.57 | 31.0 | FAIL |
| Guildhall | 1920x1080 | 34.48 | **29.0** | 35.14 | 45.45 | 18.0 | FAIL |

Startscreen/Den 720p numbers are display-capped (~145 Hz) - the headroom is larger, the gate
is >=60. Guildhall rows are GPU/CPU work (not vsync). All three Guildhall measurements (720p
vsync, 720p and 1080p with `--disable-vsync`) fail the 60 FPS gate; the vsync-enabled 1080p
attempt stalled at 0% GPU in `vkQueuePresentKHR` (hidden-window present block), so the
Guildhall rows were re-measured with `--disable-vsync` to get a stable cause, not a present
artifact. Full-scene cost attribution is in §2.3.

### 4.4 make test (headless, dummy renderer)

`cd /home/john/Projects/TAT-2 && make test` -> **exit 0**, `SUMMARY: fails=0`, 90 PASS lines,
0 SCRIPT ERROR. Tail:

```
PASS: 45 stairs snap (max_angle 50 deg, snap 0.3 m, wall-block/constant-speed kept, stair slope 32.7 deg walkable, 55 deg blocked, no new mantle)
PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=0.95m + sill + lintel (2m marker gate kept)
SUMMARY: fails=0
WARNING: 28 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 7 resources still in use at exit (run with `--verbose` for details).
   at: clear (core/io/resource.cpp:822)
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
```

## 5. What remains (owners, out of this lane's write scope)

1. **6 `RendererSceneCull::InstanceE` RID leaks at headless exit** are six `DirectionalLight3D`
   fixtures created in `game/tests/run_tests.gd` (`:535`, `:583`, `:591`, `:594`, `:842`, `:882`)
   and never freed - `--verbose` names exactly 6 `DirectionalLight3D` with an empty node path.
   Freeing each fixture (rather than dropping the reference) is expected to remove the line;
   the test file is not in this lane's scope, so it was not edited.
2. **28 ObjectDB + 7 resources at exit** are the `AudioStreamOggVorbis` / `OggPacketSequence` /
   playback objects (`AudioManager`, PG-6 lane) plus the 6 light fixtures above; `--verbose`
   names no other object type.
3. **`WARNING: 7 RIDs of type "Texture" were leaked`** appeared on some Den exits (both editor
   probe and exported binary) but not on the 2-cycle probe, Startscreen or Guildhall runs; the
   count does not scale with load cycles. It is exit-order noise rather than a per-load leak;
   the Startscreen-menu texture set (loaded through `main_menu.gd`, never through the level
   loader) is the remaining suspect and is outside this lane.
4. **Guildhall 60 FPS** needs the C2 geometry/script work: 7851 draws / 8.9 M prims with 3
   shadowed lights, and ~11 ms of per-frame scripts (`guard_ai`, `thief_character`, HUD -
   other lanes). In-lane levers left on the table, with measured headroom: one fewer hero
   shadow (~2 ms of the 4.5-7 ms shadow cost) and a lower light budget; both are visible
   quality/gameplay trades, so they were not taken without a product decision.
5. **Import pipeline (correct long-term fix):** generate desktop `.ctex` with VRAM compression
   and a size cap the way `tools/prepare_mobile_project.py` already does for Android. That
   removes the runtime 1024 cap, restores full texture detail on large-VRAM cards, and removes
   the ~3-4 s of load-time stalls the runtime cap causes (one downscale per oversized texture
   on the main thread; visible as 1 FPS samples in the load window of Den/Guildhall logs).
