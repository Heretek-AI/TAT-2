# Ecosystem reuse review — Godot 4.7.2, plugins, open-source games and UE pipelines

Date: 2026-11-24. Read-only research (four parallel lanes), verified against
repositories, READMEs, licences and releases. This is a **decision document**:
what to reuse, what to evaluate in a time-boxed experiment, and what not to
build or adopt. It does not replace the fidelity audit or the phase plan.

Compatibility note: Godot **4.7.2** is newer than most addon releases. Every
"4.7" claim below is either stated by the project or marked **unverified** and
must be proven in the named experiment before adoption.

## 1. Bottom line

1. **There is no open-source Lumen replacement for Godot 4.7.** The built-in
   GI set is `LightmapGI`, `VoxelGI`, `SDFGI`, `SSIL` and `ReflectionProbe`. The
   Lumen-inspired work is an unmerged draft engine PR, not an addon.
2. **UE-style volumetric fog/beams have a core replacement, not a plugin:** the
   Forward+ froxel volumetric fog + `FogVolume` + shadowed lights. Third-party
   god-ray plugins are Godot 3, stylised meshes, or worse than core.
3. **The 27 FPS Guildhall problem is not one bottleneck.** From 1080p 27 FPS
   (37.0 ms) and 720p 49 FPS (20.4 ms), the fit is CPU ≈20.4 ms and GPU ≈37 ms
   at 1080p. The first experiments are the quality ladder, render scale, merging
   the 2,505 plain meshes, and district HLOD — not a streaming plugin.
4. **The best open-source Godot UI is CC0 and 4.7:** *Worlds Upon The Wind*.
   The best interaction vocabulary is *COGITO* (MIT). The best stealth logic
   references are *Pixel Sabotage* (MIT) and *ragtail* (Apache-2.0 code).
5. **No cooked-UE→Godot importer exists.** CUE4Parse remains the right base.
   Montage notifies and DataTables are local gaps (high ROI); Blueprint graphs,
   material graphs and Niagara VM rates are unrecoverable.
6. **Do not adopt Wwise/FMOD or rollback netcode** for this port. The honest
   audio path is the decoded Ogg event map; the co-op path is host-authoritative
   ENet.

## 2. Rendering and GI

| Candidate | Licence | Status | Verdict |
|---|---|---|---|
| Godot `VoxelGI` (runtime bake) | engine | documented; `bake()` 5–20 s, exported builds | **ADOPT for the Den experiment** |
| Godot `LightmapGI` | engine | best static quality; editor bake only | **EVALUATE** (needs a bake pipeline) |
| Godot `SDFGI` | engine | no dynamic occluders/emissive, leaks, 30-frame convergence | **AVOID for Guildhall at 27 FPS** |
| Godot froxel volumetric fog + `FogVolume` | engine | single-scattering, finite range, temporal ghosting | **ADOPT for beams/shafts** |
| `jebbyk/SSRT_GI_CompositorEffect` | MIT | 4.7 Forward+, 25★, no releases, no FSR2 | **EVALUATE** (1-day bake-off) |
| `dequevedo/radiance-cascades-lab` | MIT | 4.7 compute, 3★ research, one camera volume | **EVALUATE** (benchmark only) |
| `GregPickering/O1S_FauxGI` | MIT | 4.4.1 tested, 18 months stale | **EVALUATE** (fallback) |
| `TokisanGames/Sky3D` | MIT | 962★, v2.1.0, 4.3+ (4.7 unverified) | **ADOPT if time-of-day ships** |
| `TokisanGames/Terrain3D` | MIT | 4,796★, v1.1.0, 4.5–4.8 | **ADOPT only if terrain replaces the UE heightmap** |
| `zhangjt93/godot-imposter` | MIT | 4.5 beta5 verified, 4.7 unverified | **EVALUATE** (distant skyline) |
| Godot-3 volumetrics / GPL raytracing / "Godot Lumen" | — | obsolete, GPL, or nonexistent | **AVOID** |

Experiments (pass/fail):
- **Den GI bake-off:** VoxelGI vs SSRT. Pass = every ROI within ±10 % of the UE
  reference, no visible leaks, ≤2 ms added, bake ≤30 s behind a loading screen.
- **Den beams:** core froxel fog vs current `tat_beam`. Pass = luminance-profile
  correlation r ≥ 0.90 at three distances, no banding/ghosting, ≤2 ms, ≤5 %
  leakage outside the shaft.
- **Guildhall budget:** quality low/medium/high × render scale 1.0/0.85/0.75,
  SSIL/fog/glow/cluster-cap toggles. Pass = a config with median ≤16.7 ms and
  1 % low ≤20 ms, or a measured ≥2× GPU saving with a path to 16.7 ms.

## 3. Performance and scale

- **No mesh streaming exists in Godot 4.7** (proposal #6109 open). Scene/chunk
  streamers exist but do not reduce per-pixel cost.
- The scene is already batched into ~2,030 MultiMeshes + 2,505 plain meshes;
  streaming would improve load time/memory, not the 1080p frame.
- Levers, in order: quality ladder/render scale, light range/cluster cap,
  merge the 2,505 plain meshes per 32 m cell by material, district HLOD at
  100–120 m, impostors for the distant skyline, material simplification on LODs.
- `chunx` is alpha; `godotite` is a single-mesh Nanite-like system; neither is a
  city streaming solution. `Terrain3D` is terrain only.

Co-op:
- **Host-as-server on built-in ENet** (1–2 weeks): host owns NPCs, doors, loot,
  mission state; clients send requests; validate distance/state; replicate with
  `MultiplayerSynchronizer`. No rollback, no deterministic physics.
- `netfox` (MIT, 1.1k★) only if client prediction/reconciliation is required;
  its FPS branch is undocumented and 4.7 is unverified.
- `GodotSteam` 4.24 ships 4.7.2 templates (Codeberg) if Steam transport is
  needed. `GodotSteam/MultiplayerPeer` is archived; do not rely on it.

## 4. Open-source games and UI

| Project | Licence | Reuse | Verdict |
|---|---|---|---|
| `max99x/wutw-public` | CC0 code+art | ornate nine-slice button/panel shader, typed settings, `.tres`/`.tscn` i18n parser, save slots, shop/ledger screens | **ADOPT techniques** (Godot 4.7) |
| `r2d2m/Cogito` | MIT code | interaction component/verb model, readables, keypads, inventory/quests/persistence | **ADAPT** (4.2 → 4.7) |
| `openfw-game/OpenLiberty` | MIT | per-object `visibility_range`/LOD, instancing, collision | **EVALUATE** (not true streaming) |
| `rubberduck99/PixelSabotageAdventure` | MIT code | three-sample vision cone, LOS, call-for-help, security camera | **ADAPT** (2.5D → 3D) |
| `euuuuuuan/ragtail-public` | Apache-2.0 code, no media | detection FSM, noise, patrol planner, search coordinator, tests | **ADAPT logic/tests** |
| `DigitallyTailored/Godot-Open-World-Database` | MIT | frame-budgeted chunk load/unload | **EVALUATE** |
| `godotneers/G.U.I.D.E` | MIT | device-aware prompts/rebinding | **EVALUATE** |
| `nuxdie/blacksite` | **no licence** | closest stealth codebase, 4.7 | **DO NOT COPY** (design only) |
| Reia / Sunder | AGPL | study only | **AVOID code** |

No CC0 modular Victorian *street* kit of commercial quality was found. The
extracted UE kit, paid kits, or commissioned art remain the realistic paths.

## 5. UE → Godot pipeline

- **No cooked-UE→Godot importer.** Every exporter needs an Unreal editor project.
- **CUE4Parse** (Apache-2.0) is the base; **CUE4Parse-Conversion** already maps
  PBR/ORM parameters. **UAssetAPI** (MIT) exposes raw Kismet bytecode.
- **Montage notifies/sections and DataTables are recoverable and cheap.**
  CUE4Parse reads `UAnimSequenceBase.Notifies`, `UAnimMontage.CompositeSections`
  and `UDataTable.RowMap`. Export them; do not build a decompiler.
- **Material graphs are impossible** from cooked data (Epic confirms). Use
  parameters + an override layer; hand-author hero materials.
- **Blueprint graphs are impossible.** A selective pattern transpiler for
  20–30 gameplay BPs is feasible; a general one is not.
- **Niagara VM rates are impossible.** Build 6–8 particle templates and use the
  5,098 authored curve LUTs/bounds where bindings are known.
- **Wwise:** the community Godot integration (MIT code, Wwise SDK proprietary)
  is real but needs SoundBanks and a licence. We only have decoded Oggs; keep
  the event map, do not adopt FMOD.
- **LevelSequence:** defer unless cinematics become gameplay-critical.
- GPL tools (FModel, UEFormat, PSK/PSA) stay as separate CLI/Blender steps.

## 6. Localisation, input, themes

- **i18n is unwired, not merely unregistered.** `en.csv` keys are UE GUIDs and
  there are zero `tr()` calls. Fix by building a source→key reverse index from
  `en.csv` (`Loc.t("PLAY")`), registering the 8 `.translation` files at runtime,
  and adding a language setting. Do not claim translated UI before this exists.
- CJK fonts are already shipped (`Traditional_Chinese/Noto_Serif_HK` and
  siblings); add them as `Font.fallbacks`. No Noto Latin/CJK download needed for
  the current 8 locales.
- **G.U.I.D.E** (MIT, active) is the best input-glyph/rebinding framework if the
  138 InputMap actions are worth migrating; otherwise keep the built-in map and
  add a small glyph resolver.
- **No theme framework needed.** One `Theme` resource with type variations and
  focus StyleBoxes; the missing piece is gamepad focus, not a library.

## 7. Decisions

| Gap | Decision |
|---|---|
| Den GI | **Experiment** VoxelGI vs SSRT; do not promise Lumen parity. LightmapGI if a bake pipeline is acceptable. |
| Beams/fog | **Use core froxel fog + FogVolume + shadowed lights**; keep the mesh beam only for the hot core. |
| Guildhall FPS | **Measure, then cut GPU/CPU**; merge plain meshes and add a district HLOD before any plugin. |
| Co-op | **Host-authoritative ENet**; no rollback. |
| i18n | **Build the reverse-index autoload + language setting**, using shipped CSVs/translations and CJK fonts. |
| UI | **Adopt WUTW's i18n/theme techniques and COGITO's interaction vocabulary**; do not copy unlicensed art/code. |
| Pipeline | **Export montage notifies + DataTables now**; selective BP/ Niagara templates later; no graph/VM decompiler. |
| Streaming | **Do not adopt a streaming plugin** in this phase; revisit only after the FPS budget work. |

## 8. Unverified / risks

- Godot 4.7.2 compatibility is explicitly verified only for Terrain3D and
  GodotSteam; SSRT/Sky3D/O1S/impostor/G.U.I.D.E/netfox need a branch spike.
- The CPU/GPU split is inferred from two frame-rate points, not a profiler
  capture; confirm with `viewport_get_measured_render_time_gpu/cpu`.
- Published large-scene FPS numbers come from different GPUs/renderers; use them
  for direction, not guarantees.
- Licence review is not legal advice. Do not redistribute extracted game assets
  or GPL/AGPL code with the port.
