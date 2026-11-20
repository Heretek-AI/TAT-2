---
slug: tat2-godot-perf-60fps
status: awaiting-approval
intent: clear
review_required: true
plan_path: .omo/plans/tat2-godot-perf-60fps.md
plan_sha256: null
review_round_id: null
review_round_limit: 5
pending-action: write and review .omo/plans/tat2-godot-perf-60fps.md
review:
  plan_reviewer:
    status: pending
    workspace_root: null
    runtime_home: null
    target: .omo/plans/tat2-godot-perf-60fps.md
    round_id: null
    plan_sha256: null
    launch_id: null
    session: null
    result: null
approach: Layered performance rescue: (1) cut embedded-GLB texture VRAM 4-8x with Basis Universal/VRAM compression plus a reproducible import tool, (2) cut Guildhall draw calls/geometry with larger/global batching, LOD/HLOD and culling, (3) cut shadow/light/effect cost and add FSR2/dynamic-resolution tiers, (4) prove true-resolution 60 FPS with a VRAM/draw-call/frame-time harness and the full export gate; no experimental engine fork in the production path.
---

# Draft: tat2-godot-perf-60fps

## Affected user and ideal state

Affected users:
- **Player** on the shipped Linux build (RTX 4070 Laptop, 8 GB VRAM, 4K/120 Hz desktop at 250% scale): wants a stable 60 FPS at 1280x720 and 1920x1080 through Startscreen, Thieves' Den and Guildhall, with the reference look intact and a clean quit.
- **Executor agent** (the next worker): needs deterministic import/export commands and measurable acceptance so it can iterate without re-discovering the scene.
- **Reviewer/QA**: needs one harness that reports true-resolution frame time, VRAM, draw calls and exit status, and rejects Xvfb/DPI artifacts.
- **Maintainer** on a fresh checkout: needs the optimized import path to reproduce from committed tools, not local `.import` edits.

Ideal state rows:
- IS-1 | Player: median >=60 FPS and p95 frame time <=16.67 ms at 1920x1080 and 1280x720 in Startscreen, Den and Guildhall, on the real display. | The gate is 60 FPS at both resolutions; current Guildhall collapses to 3-5 FPS.
- IS-2 | Player: game VRAM stays under a defined budget (~4.0 GB) and never pins the 8 GB GPU while the desktop uses ~3.2 GB. | VRAM exhaustion is the observed root cause of the 200-1000 ms frames.
- IS-3 | Player: no visible parity regression beyond documented HARD_LIMITs; skyline, hero materials and HUD stay legible. | The reference scorecard is the product acceptance surface.
- IS-4 | QA: 0 SHADER ERROR, 0 SCRIPT ERROR, 0 RD cascade warnings, clean quit exit 0. | Existing Tier-1 gate.
- IS-5 | Executor: a single command re-applies the texture/mesh import policy after a fresh clone and re-export. | `.import` files are gitignored and generated.
- IS-6 | Reviewer: one harness measures true 720p/1080p frame time, VRAM and draw calls and writes a pass/fail artifact. | Earlier 1080p numbers were Xvfb-present-bound or HiDPI-scaled and misleading.
- IS-7 | Maintainer: production path stays on Godot 4.7.2 stable; any experimental renderer is a time-boxed spike, not a dependency. | 4.7.2 is the export/parity baseline.

Gap rows:
- GAP-1 | 8,920 MB texture / 9,322 MB video memory in the Guildhall on an 8 GB GPU; 3-5 FPS and 7.8 GB GPU use. | Embedded GLB textures import as Lossless RGBA8; Godot 4.7.2 has no texture streaming. | closed by VRAM-pipeline todos.
- GAP-2 | 63,222 mesh instances, 5,738 chunks, ~2,008 main-pass draws / 3.9M prims after the far-batch optimization. | No Nanite/VSM; current chunking still emits thousands of draws. | closed by geometry/batching/LOD todos.
- GAP-3 | 48 lights, 2 hero shadows, SSIL/SSR/volumetric/glow all active; shadow pass added ~5.8k draws before the cut. | UE5 uses VSM/Lumen with downsampled budgets; Godot equivalents are per-object heavy. | closed by lighting/shadow/effect todos.
- GAP-4 | No resolution scaling/FSR2 in the shipped profile; UE5 runs 90% screen percentage + TSR. | A free 10-50% GPU budget is being left unused. | closed by scaling/quality-profile todos.
- GAP-5 | 1080p measurements were taken under Xvfb (present-bound) or with `allow_hidpi` on a 250% display, so the true render resolution was not what the gate names. | No trustworthy perf harness. | closed by harness todos.
- GAP-6 | Import settings live in gitignored `.import` files; `gltf/embedded_image_handling` cannot be set in project import defaults (Godot issue #89379). | A fresh checkout would regress to Lossless RGBA8. | closed by reproducible import-tool todos.
- GAP-7 | Only the Den was ever verified at 720p/60; Startscreen and Guildhall have no clean true-resolution 60 proof. | Scope drifted to the Den during the port. | closed by the final gate todos.

## Components (topology ledger)

| id | outcome (one line) | status | evidence path |
|---|---|---|---|
| C1 VRAM/texture pipeline | Guildhall texture memory falls from ~8.9 GB to <=3.0 GB with acceptable quality | active | `build/qa/perf/gh_vram_1080.log`; `.godot/imported/*.ctex` histogram |
| C2 Geometry/draw-call pipeline | Guildhall visible draws and chunks fall enough for <=16.7 ms | active | `build/qa/perf/gh_real_1080.log`; `level_loader.gd:1239-1358` |
| C3 Lighting/shadow/effects budget | Shadow/light/SSIL/SSR/volumetric cost fits the frame budget | active | `weather_profile.gd:348-460`; `mobile_profile.gd:14-20` |
| C4 Resolution/quality profile | FSR2/dynamic scale provides a controlled GPU-bound fallback | active | `project.godot`; `save_system.gd:80-90`; Godot 4.7 resolution-scaling docs |
| C5 Measurement harness | True-resolution FPS/VRAM/draw-call proof is one command | active | `/tmp/ulw-finish-port-notepad.md`; `build/qa/perf_*.gd` |
| C6 Reproducible asset pipeline | Fresh clone/export re-applies the import/mesh policy | active | `.glb.import` sample; Godot issue #89379 |

## Open assumptions (announced defaults)

- A1 | Target game VRAM <=4.0 GB, leaving ~3.2 GB for the desktop and ~1 GB headroom. | Observed desktop use 3.1-3.2 GB; 8.9 GB scene pinned the GPU. | reversible.
- A2 | Target hardware is this RTX 4070 Laptop 8 GB at 1920x1080 and 1280x720, real display, windowed; exact framebuffer resolution is enforced with `display/window/dpi/allow_hidpi=false`. | The gate names these resolutions; HiDPI 250% invalidated earlier numbers. | reversible.
- A3 | Basis Universal (GLTF `HANDLE_BINARY_EMBED_AS_BASISU`) is acceptable for embedded GLB textures if a hero-asset visual check passes; otherwise fall back to a 2048 cap + BC7. | Embedded textures currently bypass Detect 3D/VRAM compression (Godot issues #62295, #89379); Basis is the built-in lossy fix. | reversible per asset.
- A4 | Import rework may take up to ~30 minutes per full reimport/export and is acceptable. | 6,086 `.import` files; 2,416 textures. | process cost only.
- A5 | 60 FPS proof = median >=60 and p95 frame time <=16.67 ms over a 30 s post-warmup sample, with no 1-5 FPS collapse. | Matches the gate's frame-time wording and catches thrash. | none.
- A6 | No gameplay/design changes; visual parity is preserved within documented HARD_LIMITs. | The master gate scores parity separately. | scope guard.

## Findings (cited - path:lines)

- Godot project: `game/project.godot` (Forward+, Jolt, 1280x720 base, `canvas_items` stretch); export preset `game/export_presets.cfg`; Linux build `Makefile:50-54`.
- UE5 reference config: `extracted/raw/TAT/Config/DefaultEngine.ini:528-541` sets `r.VirtualTextures=True`, `r.DynamicGlobalIlluminationMethod=1`, `r.Lumen.HardwareRayTracing=True`, `r.Shadow.Virtual.Enable=1`, `r.RayTracing=False`; `extracted/raw/TAT/Config/DefaultDeviceProfiles.ini:2` sets `r.SecondaryScreenPercentage.GameViewport=90`; `extracted/raw/TAT/Config/DefaultScalability.ini` budgets Lumen probes, VSM pages and volumetric-fog grid sizes by quality.
- Measured Godot Guildhall: `build/qa/perf/gh_vram_1080.log` -> `PERF_VRAM loaded texture_mb=8920 video_mb=9322`; `build/qa/perf/fps_gh_1080_focus_1920x1080_focus.log` -> 3 FPS median, 333 ms median, 7.8 GB GPU; `build/qa/perf/gh_real_1080.log` -> baseline 86.7 ms / 7,851 draws / 8.9M prims, no-shadows 77.6 ms / 2,008 draws / 3.9M prims, no-meshes 37.9 ms.
- Current Den/Startscreen: `build/qa/perf/real_1080_startscreen.log` -> 86.7 FPS mean at 1080p on the real display before the HiDPI fix; `/tmp/ulw-finish-port/waves/tat2-wave3-liveqa/sess720.log` -> Den ~60 FPS median at 720p.
- Texture budget: 2,416 `.ctex`, RGBA8 total 22.96 GiB; 776x 2048^2 = 12.12 GiB; 105x 4096^2 = 6.56 GiB; 534x 1024^2 = 2.09 GiB; BC7 4:1 -> 5.74 GiB all; cap-2048 + BC7 -> 4.37 GiB all; cap-1024 + BC7 -> 1.58 GiB all. The Guildhall loaded 8.9 GB of that set.
- Guildhall import surface: `game/assets/ue/Raw` is a symlink to `extracted/assets`; the 2,416 PNG `.import` files there are Lossless (`compress/mode=0`), mipmap-free (`mipmaps/generate=false`), uncapped (`process/size_limit=0`), `vram_texture=false`. The mobile build already proves the fix: `build/mobile_game/**/*.png.import` has `vram_texture=true`, `compress/mode=2`, `mipmaps/generate=true`, `process/size_limit=1024`; its generator is `tools/prepare_mobile_project.py:183-196`.
- Guildhall content scope (architect): 1,008 unique meshes, 1.50 M unique triangles, 71.1 M instance-weighted triangles, 607 bound textures = 7.0 GiB RGBA8; 29 pure 4096^2, 39 >=4K, 315 >=2K.
- UE5 actual runtime on this machine: `GameUserSettings.ini` reports `Resolution=1920x1440`, `ResolutionSizeX=3840`, `ResolutionSizeY=2134`, `ResolutionQuality=42` (~1613x896 internal), `OverallQuality=-1`, `sg.ResolutionQuality=42`, all groups `0` except `TextureQuality=1`, VSync off, uncapped. The reference is therefore an upscaled ~1613x896 render, not native 4K.
- Godot 4.7 docs: `StreamedTexture2D`/`TextureStreaming` pages are absent at `/en/4.7/`; texture mip streaming merged to master in PR #113429 (2026-08-27), so it is not in 4.7.2. `docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html` documents FSR2.2 on Forward+; `tutorials/3d/mesh_lod.html` documents meshoptimizer LOD on import; `tutorials/3d/visibility_ranges.html` documents HLOD; `tutorials/3d/occlusion_culling.html` documents occluders.
- GLTF import: sample `.glb.import` sets `gltf/embedded_image_handling=1` and `meshes/generate_lods=true`; Godot's `GLTFState` docs say mode 1 extracts (acts uncompressed at runtime) while mode 2 embeds Basis Universal VRAM-compressed textures; issue #89379 says the option cannot be set in project import defaults (4.3+); issue #62295 says Detect 3D does not affect embedded `.glb` textures.
- GitHub prior art: `Arkaein/godotite` (MIT, Godot 4.5+, Nanite-style cluster LOD, C# build, GDScript runtime, no .NET at runtime); `Bieuulls/arboria-engine` (experimental GPU-driven virtual geometry for Godot 4.7+ Forward+); `HammerVala/NaniteGodot` (GDExtension, Godot 4.2+); `zhangjt93/godot-imposter` (MIT, octahedral impostors, verified on 4.5 beta); `tdaven/godot-streamed-texture-reimport-tool` (requires the #113429 engine feature, not 4.7.2).
- Existing loader controls: `game/src/core/level_loader.gd:51-70` (32 m chunks, visibility ranges, 768 occluders), `:1468-1590` (MultiMesh/far batch), `game/src/core/mobile_profile.gd:14-20` (48 lights, 2 shadows), `game/src/core/weather_profile.gd:348-460` (SSIL/SSR/volumetric/glow).

## Decisions (with rationale)

- D1 | First wave attacks texture VRAM, not shaders: 8.9 GB is a hard capacity failure; no amount of draw-call tuning fixes a thrashing GPU. | The measured 3 FPS run had 7.8/8.2 GB GPU and 200-1000 ms frames.
- D2 | Prefer built-in Godot 4.7.2 mechanisms first (Basis/VRAM compression, meshoptimizer LOD, visibility ranges, occlusion, FSR2); treat Godotite/impostors as optional skyline spikes and Arboria/NaniteGodot as non-production until proven. | Engine-fork risk is larger than the remaining frame budget; 4.7.2 is the export baseline.
- D3 | Use FSR2/dynamic 3D scale as a quality tier, not the primary fix; UE5 itself renders at 90% screen percentage and upsamples. | Matches the reference and preserves native 1080p as an option.
- D4 | Make the import policy reproducible with a committed tool/script; never rely on local `.import` edits. | `.import` is gitignored; a fresh checkout would otherwise regress.
- D5 | Measure on the real display at true framebuffer resolution; Xvfb is only for correctness captures, not FPS. | Earlier 1080p numbers were invalid for two independent reasons (Xvfb presentation, 250% HiDPI).

## Scope IN

- Texture import/compression and VRAM budget for embedded GLB textures (all maps, with hero-asset checks).
- Guildhall geometry/draw-call and skyline strategy (batching, LOD/HLOD, culling), plus lighting/shadow/effect budgets.
- Resolution scaling/FSR2 quality profile and a reproducible import/export tool.
- A true-resolution FPS/VRAM/draw-call harness and the full acceptance gate re-run (make test, E2E, audit, --strict, verify_baseline).
- Documentation updates: FIDELITY_GAPS, HANDOFF_NEXT_SESSION, a perf report with measured evidence.

## Scope OUT (Must NOT have)

- Gameplay/design changes, new content, or re-authored art beyond compression/size policy.
- A production dependency on an experimental engine fork or unfinished Nanite plugin.
- Mobile/Android retuning (best-effort only after the desktop gate is green).
- Committing `build/`, `game/.godot/`, generated assets, or local `.import` caches.
- Silent quality reductions without a visible scorecard/report entry.

## Open questions

- Q1 | RESOLVED BY TIMEOUT DEFAULT: desktop import policy = **VRAM Compressed (BC1/BC3/RGTC) + mipmaps + 2048 cap; BC7/high-quality only for hero assets; UI/2D lossless**. This replaces the earlier Basis-only framing; the mobile pipeline already proves the recipe (`build/mobile_game/**/*.png.import`: `vram_texture=true`, `compress/mode=2`, `mipmaps/generate=true`, `process/size_limit=1024`). Reversible per asset.
- Q2 | RESOLVED BY TIMEOUT DEFAULT: production path stays on **Godot 4.7.2 stable + built-ins**; Godotite/impostor HLOD is a time-boxed spike for the skyline only; Arboria/NaniteGodot are not production dependencies.
- Q3 | RESOLVED BY TIMEOUT DEFAULT: **native 1080p first**, with FSR2 Quality (0.67-0.9 internal) as an automatic fallback/quality tier. UE5 itself runs 90% screen percentage + TSR, so an upscaled 1080p is parity-fair.
- Q4 | RESOLVED BY TIMEOUT DEFAULT: **all three primary scenes** (Startscreen, Den, Guildhall) at both resolutions, matching the master gate.

## Research synthesis (four routes)

| Route | First move | Expected effect | Verdict |
|---|---|---|---|
| A asset/import pipeline | Desktop `.import` rewrite to VRAM Compressed + mips + 2048 cap; reimport/export | Guildhall texture 8.9 GB -> ~1.5-2.5 GB; removes VRAM thrash | **Recommended first**; only measured hard capacity failure |
| B scene/draw/shadow budget | 1 shadow caster, <1,200 main draws, tune far-batch ranges; LightmapGI for static world if needed | 86.7 ms -> ~17-30 ms after A; not enough alone | Second, measured after A |
| C renderer/scaling | FSR2 Quality + dynamic scale + effect tiers (SSIL/SSR/volumetric off) | 10-30% GPU savings when fill-bound; no help if CPU/VRAM-bound | Third, native-first fallback |
| D plugin/engine fork | Godotite/impostor skyline; Arboria/NaniteGodot/4.8 streaming | High integration/parity risk; scene has modest triangles, not multi-million | Optional skyline spike only |

Key measured facts driving the order:
- UE5 official runtime on this machine: 3840x2134 window, `ResolutionQuality=42` (~1613x896 internal), lowest scalability tier, VSync off, uncapped; Nanite/VSM/Virtual Textures/Lumen enabled.
- Godot Guildhall: 8,920 MB texture / 9,322 MB video; 607 bound Guildhall textures = 7.0 GiB RGBA8; all 2,416 PNGs import Lossless/no-mips/no-size-limit.
- 720p is not faster than 1080p (3 vs 5 FPS on the same build) -> capacity/CPU-bound, not fill-bound; FSR2 alone cannot fix it.
- Post-opt1: 6,857 geometry nodes, 5,738 chunks, 86.69 ms p50, 7,851 draws (2,008 with shadows off), 3.9M prims (shadow off); no_meshes still 37.9 ms. Shadows alone ~9 ms; geometry alone cannot reach 16.7 ms.


## Approval gate
status: awaiting-approval

Approach to plan: **Wave 1 texture-import rescue** (desktop import defaults + reimport, target `texture_mb < 3.5 GB` / `video_mb < 5 GB`, hero-asset visual check) -> **Wave 2 true-resolution re-measure** (real display, `allow_hidpi=false`, 720p/1080p, Startscreen/Den/Guildhall) -> **Wave 3 shadow/draw/effect budget** only if p50 >16.7 ms -> **Wave 4 FSR2/quality tiers** only if GPU-bound -> **Wave 5 full gate, docs, commits, cleanup**. Reproducible import tool is mandatory; experimental engine forks are out.

Approval requested: write `.omo/plans/tat2-godot-perf-60fps.md` and run the default plan-reviewer high-accuracy review. Execution remains separate (`/ulw-execute`).

