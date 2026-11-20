# TAT-2 Core Engine Audit — audit-core.md

Date: 2026-11-20. HEAD: post-round-1 + round-2 playtest fixes.
Scope: `game/src/core/` + `game/src/stealth/` (+ `noise_bus` interface).
Method: read-only. Every P0/P1 below is backed by a span re-opened this session; quotes are verbatim.
Ground truth: `.omo/waves/tat2-ground-truth/backlog.md` (F1/F5/F7/F8/F9 rows).

Grades: **KEEP** (sound, no action) / **FIX** (defects to fix) / **WATCH** (risks to monitor).
Counts: **P0 = 5, P1 = 41, P2 = 10** (ranked list at the end).

---

## 1. `game/src/core/level_loader.gd` (2912 lines) — Grade: **FIX**

**Owns:** UE5 → Godot level builder. Parses `.tatlevel.json` sublevels, chunks
repeated `.glb` meshes into per-32 m-cell `MultiMeshInstance3D`s with tight
`custom_aabb`, binds PBR materials (Albedo/Normal/ORM + glass/HDR-emissive/CPD
special cases), emits per-cell `StaticBody3D` colliders + `OccluderInstance3D`s,
Den window-wall split + Den prop grounding, landscapes/weightmaps, procedural curb
ribbons (F7 replica), decals/rect-lights/volumes/GI fills, capped light budgets
(`load_sublevels` / `load_sublevels_async`). Owns the loader rows of F1/F5/F7/F8/F9.

**Top defect risks:**

- **P0-5 — collision budget silently drops colliders past 32k shapes** (`:1685-1688`):
  ```gdscript
  func _add_collider(ctx: Dictionary, cell: Vector2i, shape: Shape3D, tr: Transform3D, shape_offset: Vector3) -> void:
      if int(ctx.get("collision_shapes", 0)) >= MAX_TOTAL_SHAPES:
          return
  ```
  with `const MAX_TOTAL_SHAPES: int = 32000` (`:95`). No warning, no counter.
  Guildhall maps + curb ribbons share the budget, so overflow produces
  walk-through walls/floors late in load order depending on parse order.
- **P1-L1 — F8 missing-mesh hole: no geometry, no collider, no occluder** (`:764-775`, `:1720-1727`):
  ```gdscript
  func _ue_mesh_to_res(ue_path: String) -> String:
      var clean := ue_path.split(".")[0]
  ```
  only `.glb`/`.gltf` are probed, else `""` → cached `{mesh: null, shape: null}`:
  ```gdscript
  var info: Dictionary = _get_mesh_and_shape(mp)
  var mesh: Mesh = info["mesh"]
  if mesh == null:
  ...
      push_warning("[level_loader] missing mesh for UE path ", mp, "; skipping draw item (no collider/occluder emitted)")
  ```
  ```gdscript
      if miss_arr.size() < 128 and not miss_arr.has(mp):
  ```
  Evidence list is capped at 128 while the count stays exact; anything without a
  converted GLB (F5 window border, F7 curb SMs) vanishes silently. Corrupt-import
  `load()` (`:781 `var packed: Variant = load(res_path)``) caches null forever.
- **P1-L2 — F8 null-texture fallback guesses plausible-but-wrong masonry** (`:327-329` + fallback chain):
  ```gdscript
  func _load_tex(res_path: String) -> Texture2D:
      if res_path == "":
          return null
  ```
  tail `return null` when neither `ResourceLoader` nor `FileAccess` hits; callers
  then bind brick/stone/dirt/wood by name substring, e.g.
  ```gdscript
  if "brick" in low:
  ```
  masking F8/F11 coverage holes as wrong-but-rendered walls.
- **P1-L3 — Den grounding / window split are string-gated and position-fragile** (`:1533`, `:1559`, `:1627`):
  ```gdscript
  func _is_den_window_wall(low_mp: String) -> bool:
      var is_den: bool = low_mp.find("thievesden") >= 0 or low_mp.find("windowborder") >= 0 or low_mp.find("thievesden_window") >= 0
  ```
  ```gdscript
  func _ground_den_prop_shape(low_mp: String, shape: BoxShape3D, tr: Transform3D, soff: Vector3) -> Array:
  ```
  ```gdscript
      if float_m <= 0.02 or float_m > 1.0:
          return [shape, soff]
  ```
  ```gdscript
  func _clip_den_window_visual(ctx: Dictionary, tr: Transform3D, soff: Vector3, mesh_gap: float, ...) -> void:
  ```
  ```gdscript
              if mi.transform.origin.distance_to(tr.origin) < 0.01:
  ```
  Props floating >1.0 m, sunk props, and all trimesh-path props never ground
  (F1 partly open); a mesh rename silently disables the 4-box split
  (`DEN_WINDOW_GAP_M 0.95`, sill `0.9`, lintel `2.0`); the visual clip no-ops when
  the sibling visual is not within 1 cm, leaving the baked-opaque gray slab.
- **P1-L4 — curb replica capped and shares the 32k shape budget** (`:2021-2024`):
  ```gdscript
      if done >= CURB_MAX_SPLINES:
          push_warning("[level_loader] curb build hit CURB_MAX_SPLINES=", CURB_MAX_SPLINES, "; remaining splines skipped")
  ```
  3 collision boxes per ribbon segment feed `MAX_TOTAL_SHAPES` and can starve
  building colliders (feeds P0-5).
- **P1-L5 — Guildhall hole-discard keyed on map-name substring** (`:2711`):
  ```gdscript
  mat.set_shader_parameter("discard_holes", 0.0 if source_low.contains("guildhall") else 1.0)
  ```
  A renamed source reopens the safe-room void (F8 "floating ground").
- **P1-L6 — emissive quads carry the look while omnis are shadowless** (`:2350`):
  ```gdscript
  qmat.emission_energy_multiplier = 2.0
  ```
  vs `_build_rect_lights` with `omni.shadow_enabled = false`; glow-vs-light
  desync reads as F9 flicker; tuning lives in disconnected constants.

**Dead code:** `den_window_gap_spec()` (`:1543`) and `result["moonshape_hidden"]`
(`:1009`, `:1123`) look write-only in-file but are **test contract** —
`game/tests/run_tests.gd:3360` calls the former, `:2457-2463` assert the latter.
Keep. `far_item` horizon path (`:1749`, `:1794`) sets `visibility_range_end = 0.0`
(always drawn) — intended for skyline, not dead.

**Performance notes:** one `MultiMeshInstance3D` per (mesh × override-key × 32 m
cell) with tight `mm.custom_aabb`; 982 authored lights budget-cut to
`max_lights` (default 96) via `_prioritize_lights` (spawn-25 m priority, then
`_light_score`); `distance_fade` on non-hero lights, decals 45→60 m; per-frame
cost is visibility-range fades on clutter/tiny/small props only (structural
tokens always resident). Load-time risks: GDScript heightmap decode +
`ConcavePolygonShape3D` per landscape component, unbounded `_override_mesh_cache`
(one mesh duplicate per override key), full-GLB `load()` per unique mesh.

---

## 2. `game/src/core/animation_library.gd` (749 lines) — Grade: **FIX**

**Owns:** Guard/FP/TP animation resolution. Loads `anims_manifest.json`, parses
source GLBs via `GLTFDocument`, retargets tracks by bone name, strips `root`
translation for in-place locomotion, exposes `clip_for_role` / `clip_for_state`
and `build_player` / `build_fp_player` / `ensure_*` lazy loaders. Takedown/crank
roles for thief 3P vs 1P viewmodel.

**Top defect risks:**

- **P0-2 — `_load_source` takes the first animation, ignoring the clip name:**
  ```gdscript
  for an in lib.get_animation_list():
      if anim == null:
          anim = lib.get_animation(an) as Animation
  ```
  (both the `ResourceLoader` path and the `GLTFDocument` fallback path). A
  takedown/montage GLB packing Atk+Vic or multi-take silently plays the wrong
  side — guard gets attacker motion or vice versa. No name check against the
  manifest `animation` field.
- **P1-A1 — `build_player` and `build_fp_player` share and wipe instance state:**
  ```gdscript
  applied.clear()
  anim_lengths.clear()
  missing_roles.clear()
  ```
  present in both builders. Reusing one `GuardAnimationLibrary` for guard + FP +
  TP silently wipes prior roles; the header warns a dedicated instance is required
  but nothing enforces it.
- **P1-A2 — pelvis-only unit scale with silent 0.01 fallback:**
  ```gdscript
  var k: float = 0.01
  var mrest_p = _mesh_local.get("pelvis", null)
  ```
  ```gdscript
  if al > 0.0001 and ml > 0.0001:
      k = ml / al
  ```
  Non-pelvis-root rigs get 100× wrong translation with only a visual glitch.
- **P1-A3 — static caches grow forever:**
  ```gdscript
  static var _source_cache: Dictionary = {}
  static var _retarget_cache: Dictionary = {}
  ```
  keyed `clip_name + "|" + skeleton_name`; every new skeleton name pins a full
  `Animation` + rest dicts. Level reloads / editor iterations leak.

**Dead code:** `const FP_BLEND: float = 0.2` (`:117`) — sole occurrence in
`game/` (verified by grep), never read. **P2-D1.** `bone_report()` (`:303`) and
`has_fp_role()` (`:470`) have no callers in `game/` (test file included).
**P2-D2.** `applied_clip_count()` and `fp_clip_for_role()` have live callers
(`thief_character.gd:2208`, `guard_ai.gd:344`, `run_tests.gd:3160`) — keep.

**Performance notes:** cold clip = `FileAccess.get_buffer(full GLB)` +
`GLTFDocument.append_from_buffer` + `generate_scene(state, 30.0, …)` on the main
thread per cold `ensure_*` (30 FP tool clips → first-equip hitch); retarget-hit
avoids recompute; long montages duplicate every key.

---

## 3. `game/src/core/weather_visuals.gd` (328 lines) — Grade: **WATCH**

**Owns:** Night-sky + rain visuals from `game/data/generated/weather/*.json`:
horizon/zenith fallback chains, `make_sky` (tat_sky shader, moon disc, stars,
cloud haze), `apply_sky`, `make_rain` GPU box volume, `snap_rain_to` follow.

**Top defect risks:**

- **P1-W1 — synchronous 4K panorama decode per sky build:**
  ```gdscript
  var pano: Texture2D = load(MOON_PANORAMA_PATH) as Texture2D if ResourceLoader.exists(MOON_PANORAMA_PATH) else null
  ```
  `T_Moon_D.png 4096×2048` on the calling thread every `make_sky`; no static cache.
- **P1-W2 — new `ShaderMaterial` + `Sky` per call, old sky never freed:**
  ```gdscript
  var mat := ShaderMaterial.new()
  ```
  ```gdscript
  var sky := Sky.new()
  sky.sky_material = mat
  ```
  `apply_sky` overwrites `env.sky`; rapid weather blends accumulate.
- **P1-W3 — rain ignores the mobile tier:**
  ```gdscript
  drops.amount = clampi(int(RAIN_AMOUNT_AT_FULL * intensity), RAIN_AMOUNT_MIN, RAIN_AMOUNT_MAX)
  ```
  `1800 × intensity → [100, 2700]` billboarded alpha quads with no
  `MobileProfile` scale-down; storm on Performance tier = 2700 overdrawn transparents.

**Dead code:** none — `_tone_safe`, `_authored_sky_color`, `horizon_color_of`,
`zenith_color_of`, `moon_diameter_deg`, all `RAIN_*/MOON_*/FALLBACK_*` referenced.

**Performance notes:** sky = 1 sphere draw + hemisphere-mapped moon + hash stars +
FBM haze; `sky_radiance_scale` up to 35× on sub-0.05 `overall_color` can blow HDR
into glow. Rain ≈ 2970 live streaks at max, `local_coords = false` so the follow
snap does not smear (correct) but keeps everything world-simulated.

---

## 4. `game/src/core/weather_profile.gd` (477 lines) — Grade: **FIX**

**Owns:** weather data layer — `WEATHER_DIR` + `map_weather.json` loading, typed
getters, UE→Godot unit conversions (cm→m `0.01`, lux→energy `×10`, bloom→glow
`×0.08`), `apply_environment` / `apply_for_map`, shadow-toe LUT cache.

**Top defect risks:**

- **P1-P1 — disk + JSON re-parse per lookup, no cache** (`:68-94`):
  ```gdscript
  static func load_map_table() -> Dictionary:
      var parsed: Variant = _load_json(MAP_TABLE_PATH)
  ```
  ```gdscript
  static func preset_name_for_map(map_id: String) -> Dictionary:
      var table: Dictionary = load_map_table()
  ```
  every `preset_for_map` / `apply_for_map` re-opens both JSONs; map switches churn I/O.
- **P1-P2 — desktop enables volumetric + SSIL + SSR unconditionally:**
  ```gdscript
  env.volumetric_fog_enabled = true
  ```
  ```gdscript
  env.ssil_enabled = true
  ```
  ```gdscript
  env.ssr_enabled = true
  env.ssr_max_steps = 48
  ```
  gated only on `is_desktop = not MobileProfile.is_mobile()` — any desktop GPU pays
  full volumetric + SSIL + 48-step SSR. No quality toggle.
- **P1-P3 — fog-energy compensation divides up to 24×:**
  ```gdscript
  env.fog_light_energy = clampf(0.06 / fog_lum, 1.0, 24.0) if is_low_density else clampf(0.025 / fog_lum, 1.0, 8.0)
  ```
  pre-exposed `fog_lum 0.001–0.004` can white out fog on dark presets.
- **P1-P4 — glow loop cost on desktop:**
  ```gdscript
  for gl_i: int in range(2 if is_den_glow else 5):
      env.set_glow_level(gl_i, true)
  ```
  5 glow mips + `glow_hdr_scale 2.0` + `BLEND SCREEN` outside the Den.

**Dead code:** none claimed (all getters referenced by `apply_environment`).

**Performance notes:** per-call field writes are cheap; volumetric/SSIL/SSR/glow
dominate frame on Forward+. Moon energy preserves authored ratios (Gloomy
0.01→0.1 … Stormy 0.05→0.5); `fog_sky_affect 0.0` keeps sky/stars/moon from blacking.

---

## 5. `game/src/core/mobile_profile.gd` (159 lines) — Grade: **WATCH**

**Owns:** Android quality tiers — `is_mobile`, tier caps (`max_lights`,
`hero_shadows`, `render_scale`, `lod_bias`, `glow_enabled`, `target_fps`),
`apply_runtime` (FPS cap + viewport scaling), `apply_environment` (glow soften),
`_settings` (SaveSystem lookup).

**Top defect risks:**

- **P1-M1 — tree + dict lookup on every cap query:**
  ```gdscript
  var save_system: Node = tree.root.get_node_or_null("SaveSystem")
  var data_variant: Variant = save_system.get("data")
  ```
  `current_tier()` → `_settings()` per call, and every cap calls
  `current_tier()`; per-frame callers pay node lookup + string hash. Cache the tier.
- **P1-M2 — desktop still forces the scaler pass:**
  ```gdscript
  Engine.max_fps = target_fps()
  win.scaling_3d_scale = scale
  win.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
  ```
  desktop `target_fps() = 0` stomps any prior `Engine.max_fps`; setting
  `scaling_3d_scale = 1.0 + BILINEAR` still enables the scaler. Early-out when
  not mobile.
- **P1-M3 — order-dependent glow cap:**
  ```gdscript
  env.glow_intensity = minf(env.glow_intensity, 0.45)
  env.glow_bloom = minf(env.glow_bloom, 0.12)
  ```
  correct only if mobile runs *after* `weather_profile.apply_environment`.

**Dead code:** `DESKTOP_MAX_LIGHTS = 48` is returned but never enforced in
`vfx_manager.gd` (cross-file gap, wire the budget — not deletion).
`lod_bias()` / `hero_shadows()` have live loader callers — keep.

**Performance notes:** tiers Performance `12/1/0.7/2.5/glow-off/30 FPS`,
Balanced `24/2/0.85/2.0/60`, Quality `32/4/1.0/1.5/60`, Desktop `48/2/1.0/1.0`.
Render scale 0.7 ≈ 49% pixels — the biggest mobile win. `apply_*` are O(1).

---

## 6. `game/src/core/vfx_manager.gd` (1093 lines) — Grade: **FIX**

**Owns:** all procedural HL-1 stand-in VFX — smoke plume (3 GPU layers), fairy
orb, grapple beam, sap burst, candle flame, lockpick sparks, blackjack swing,
window godray, footprint decals, blue wisp, foyer beams, arcane ward, vine lock,
crimson alarm, prop highlight.

**Top defect risks:**

- **P1-V1 — alarm spot at 4.5 with strobe peaks at 5.4 (F10 blinding):**
  ```gdscript
  spot.light_energy = 4.5
  ```
  ```gdscript
  strobe.tween_property(spot, "light_energy", 2.2, 0.11)
  strobe.tween_property(spot, "light_energy", 5.4, 0.11)
  ```
  plus `bulb emission ×4.0`. A separate `fade` tween drives the same
  `light_energy` over the last 0.6 s — last-writer-wins flicker/pop.
- **P1-V2 — ward wash + energies above every other cap:**
  ```gdscript
  wash.light_energy = 1.6
  ```
  ```gdscript
  veil_mat.set_shader_parameter("energy", 2.4)
  ```
  ```gdscript
  shard_mat.set_shader_parameter("energy", 2.8)
  ```
  vs fairy/sap/smoke caps at 0.65 — no single light budget; stacking
  wisps + wards + alarms busts Forward+.
- **P1-V3 — blue wisp takes caller-controlled energy, default 0.30:**
  ```gdscript
  static func spawn_blue_wisp(parent: Node3D, local_pos: Vector3, light_energy: float = 0.30) -> Node3D:
  ```
  ```gdscript
  glow.light_energy = light_energy
  ```
  ```gdscript
  orb_mat.emission_energy_multiplier = 3.0
  ```
  no clamp; plus an unbounded `bob_tween.set_loops()` unless the caller keeps the handle.
- **P1-V4 — per-footstep allocation storm, 6 s lifetime:**
  ```gdscript
  var quad: PlaneMesh = PlaneMesh.new()
  var mat: StandardMaterial3D = StandardMaterial3D.new()
  ```
  ```gdscript
  fade_tween.tween_property(mat, "albedo_color:a", 0.0, 6.0)
  ```
  new mesh + material + tween + 6.1 s timer per step; sprinting = dozens of live
  transparent quads. No pool, no cap.
- **P1-V5 — `ttl = 0.0` spawners never auto-free** (godray, foyer beams):
  ```gdscript
  static func spawn_window_godray(parent: Node, pos: Vector3, target_pos: Vector3) -> void:
  ```
  (no ttl param at all) and `spawn_foyer_security_beam(…, ttl: float = 0.0)`
  only frees `if ttl > 0.0`. Missed manual free = permanent cone + lights.
- **P1-V6 — footstep mask pixel loop on first wet step:**
  ```gdscript
  for y: int in range(h):
      for x: int in range(w):
          var c: Color = img.get_pixel(x, y)
  ```
  `get_pixel`/`set_pixel` per texel + decompress + convert on the main thread.

**Dead code:** no dead spawners (all public API). `_aim_node` logic is
copy-pasted in grapple-beam/godray/`_aim_node` — consolidate, do not delete.
`spawn_smoke_cloud` is a one-line alias of `spawn_smoke_plume` — keep.

**Performance notes:** smoke = 130 GPU particles + flash omni 9 m + 23 s haze
tween per cast (overlapping smokes = 260+ overdrawn spheres); wisp = 2 spheres +
CPU particles + omni 6 m; ward = veil + 6 shards + 28 particles + omni 7 m;
vine = 8 cylinders + omni 5 m; foyer = 2 beams + housing (emission 3.0) + omni
5 m + plate. All beam shaders `blend_add + cull_disabled + depth_draw_never` —
cheap per-pixel, overdraw-heavy stacked. No mobile gating in this file.

---

## 7. `game/src/core/audio_manager.gd` (994 lines) — Grade: **FIX**

**Owns:** full PG-6 audio runtime — `Master/Music/SFX/Ambience/UI/Dialogue`
buses, Wwise `audio_events.json` join → real OGG clips, beds (AU1), gramophone,
footstep pools (AU3), UI/countdown (AU4), one-shots + `NoiseBus` mirror (AU5), VO
(AU6), S27 pause-duck.

**Top defect risks:**

- **P0-1 — `get_rid()` called on a `Node3D` (crash on Guildhall/OldManor steps)** (`:469-484`):
  ```gdscript
  func _is_indoor() -> bool:
  ```
  ```gdscript
  var player: Node3D = tree.get_first_node_in_group("player") as Node3D
  ```
  ```gdscript
  var excluded: Array[RID] = [player.get_rid()]
  ```
  `Node3D` has no `get_rid()` (only `CollisionObject3D`). `_footstep_clip` →
  `_scene_surface` → `_is_indoor` runs on every non-Den footstep, so the first
  Guildhall/ smaller-map step throws. Thieves Den is unaffected (early-returns
  `"wood"` before the raycast).
- **P1-U1 — voices silently dropped under load** (`:959-960`, `:977-978`):
  ```gdscript
  if _active_voices >= MAX_VOICES or stream == null:
      return
  ```
  `MAX_VOICES = 16`, no priority/stealing, no return value — fights silently lose
  alert/VO cues and callers cannot tell.
- **P1-U2 — `fire_event` bypasses the calibrated trims** (`:872-884`):
  ```gdscript
  _play_stream_2d(stream, bus, -10.0)
  ```
  (twice: UI/Ambience/Music branch and the 2D fallback). `BED_TRIM_DB`,
  `UI_DB`, `VO_DB` exist but this path plays everything at −10.0.
- **P1-U3 — scene-unsafe `await` timers:**
  ```gdscript
  for i: int in range(6):
      play_countdown_tick(i)
      await get_tree().create_timer(1.0).timeout
  ```
  (`:619-624`; `_countdown_running` sticks `true` forever on scene change,
  permanently blocking `start_countdown`), and
  ```gdscript
  func _horn_second_blast(horn: AudioStream, pos: Vector3) -> void:
      await get_tree().create_timer(0.15).timeout
  ```
  (`:842-844`) replays at a possibly dead position with no validity guard.
- **P1-U4 — bed stream duplicated to set loop** (`:643-651`):
  ```gdscript
  var dup: Resource = stream.duplicate() as Resource
  ```
  doubles the whole OGG in memory per bed; prefer `AudioStreamLoop` or a
  loop-set imported resource.

**Dead code:** triplicated `## AU4: UI cue …` doc headers stacked above
`wire_hover_sfx()` (`:530-543`) — three near-identical comment blocks, one
function. **P2-D3.** `BED_TARGET_DBFS`, `UI_DB`, `VO_DB` defined but bypassed
(see P1-U2) — two volume authorities. **P2-D4.**

**Performance notes:** synchronous `ResourceLoader.load()` on hot paths
(`play_footstep`, `play_vo`, `fire_event` loop); `_scene_surface` →
`_is_indoor` does a physics `intersect_ray` **per footstep**; `wire_hover_sfx`
recurses the whole UI tree per panel open.

---

## 8. `game/src/core/game_data.gd` (510 lines) — Grade: **FIX**

**Owns:** normalized UE table loader — `DT_/CT_` JSONs → `curves`/`tables`,
contracts 1–16 + hardcoded 17–18, `contracts.json` overlay, UE sublevel → 
`.tatlevel.json` resolution, curve eval, match durations, contract strings, mission rows.

**Top defect risks:**

- **P1-G1 — tutorial missions misclassified + catch-all** (`:445-449`):
  ```gdscript
  if "tutorial" in low:
      return "jaspering_hall"
  return "example"
  ```
  every `DT_Missions_Tutorial` row becomes the expansion map; any key typo
  becomes `"example"`. Silent mis-routing, no warning.
- **P1-G2 — unknown map silently inherits unlimited timer** (`:352-359`):
  ```gdscript
  key = "ftue" if mission_durations.has("ftue") else key
  ```
  a misspelled `map_id` gets the FTUE zero limit (`0.0` = unlimited) instead of erroring.
- **P1-G3 — brittle filename parse** (`:238-240`):
  ```gdscript
  var prefix: String = parts[1] # e.g. Contract2
  var num: int = int(prefix.replace("Contract", ""))
  ```
  a renamed file yields `int("") == 0`, colliding all malformed tables at
  `contract_strings[0]` with silent overwrite.
- **P1-G4 — array field read via invented keys** (`:481-483`):
  ```gdscript
  var d0: float = float(rv.get("MatchDurationsByDifficulty", 0.0))
  var d1: float = float(rv.get("MatchDurationsByDifficulty[1]", d0))
  var d2: float = float(rv.get("MatchDurationsByDifficulty[2]", d1))
  ```
  if the converter emits an Array, `d1`/`d2` always fall back to `d0` — all three
  difficulties share Novice duration.
- **P1-G5 — import-system bypass for icons** (`:429-432`):
  ```gdscript
  if ResourceLoader.exists(raw_path) or FileAccess.file_exists(raw_path):
      return raw_path
  ```
  a never-imported raw `.png` passes the check then fails at runtime `load()`.

**Dead code:** `contracts_source_table` (`:11`, written `:268`) is never read —
**P2-D5.** `missions_by_id` has a live external caller
(`mission_controller.gd:1146-1147`) — keep. Hardcoded expansion contracts
(`:200`, `:214`) share one duplicated `map_path` literal — consolidation, not deletion.

**Performance notes:** full `DirAccess` traversal + `JSON.parse_string` per table
on every `_ready()`; `get_contract_display()` linearly scans contracts per UI
refresh; `eval_curve()` interpolates per call (hot if per-frame); `get_data_row()`
shallow-duplicates — nested containers are shared and caller-mutable.

---

## 9. `game/src/core/game_state.gd` (241 lines) — Grade: **FIX**

**Owns:** global run-state autoload — thief/contract/difficulty/map selection,
`mission_objectives`, loot counters, stealth flags, mission-complete handshake
(`objective_completed` / `objectives_updated` / `loot_changed`).

**Top defect risks:**

- **P0-3 — loot value short-circuits quest objectives** (`:126-130`):
  ```gdscript
  func are_all_objectives_complete() -> bool:
      if loot_goal > 0 and loot_value >= loot_goal:
          return true
  ```
  reaching the loot value returns `true` with `set_main`/`vault_main` entries
  still incomplete; combined with `update_objective_progress()` (`:110-112`)
  firing `objective_completed` on the loot path, a rich player finishes the
  mission without the quest item.
- **P1-S1 — completion can fire from two sources** (`:167-168`, `:201-205`):
  ```gdscript
  if loot_value >= loot_goal and not quest_item_acquired:
      quest_item_acquired = true
  ```
  ```gdscript
  if not handled_set:
      quest_item_acquired = true
  ```
  loot path and `vault_main`/`contract_main` path both set the flag and emit.
- **P1-S2 — every quest pickup advances the set counter + stale display value:**
  ```gdscript
  if str(entry.get("id", "")) == "set_main":
      var next_cur: int = mini(int(entry.get("current", 0)) + 1, target_val)
  ```
  (`:184-195`) runs for *any* `is_quest_item` pickup and auto-completes the next
  `set_item_*`; meanwhile `loot_needed: int = 5` (`:26`) is emitted in both
  `loot_changed` emits (`:62`, `:220`) but never synced to `loot_goal`, so the
  HUD/escape-gate threshold (`escape_gate.gd:75`, `hud.gd:2152` read
  `loot_needed`) disagrees with the completion logic (reads `loot_goal`).

**Dead code:** none — all fields are read by HUD/gates/tests.

**Performance notes:** `add_loot()` is O(N²) worst-case over a tiny N (<20
objectives) with three separate signal emissions per pickup — correct but
wasteful; single-pass + one emit would do.

---

## 10. `game/src/stealth/light_probe.gd` (159 lines) — Grade: **KEEP**

**Owns:** stealth light-visibility sampler — `register_light` / `clear_lights` /
`short_circuit_lights` / `tick` over the loader-registered `Light3D` set;
`sample_visibility` returns 0.0–1.0 exposure with squared-distance early-outs
(`LIGHT_SAMPLE_RANGE 25.0`), per-light range reject, one shadow raycast per
survivor, throttled to ~12.5 Hz with a 0.75 m position cache. Static helpers
encode the authored UE curves. Throttling, early-outs, and energy-space weights
are sound; the risks below are correctness edges.

**Top defect risks:**

- **P1-H1 — directionals bypass occlusion and contribute up to 0.35 anywhere** (`:130-134`):
  ```gdscript
  if l is DirectionalLight3D:
      total += clampf(l.light_energy * 0.25, 0.0, 0.35)
      continue
  ```
  no raycast, no range check — interiors still accumulate skylight.
- **P1-H2 — true darkness unreachable** (`:113-115`, `:139`):
  ```gdscript
  static func light_visibility_weight(energy: float) -> float:
      return clampf(energy * LIGHT_ENERGY_TO_VISIBILITY, LIGHT_VISIBILITY_MIN, LIGHT_VISIBILITY_MAX)
  ```
  ```gdscript
  var total := 0.08 # ambient Kilcairn night floor
  ```
  with `MIN 0.15` (`:38`); shadows read ≥0.08 and overlapping lights saturate fast
  (F10 interplay: loader median energy 1.0 → 0.9 weight by construction).
- **P1-H3 — raycast mask hardcoded to layer 1 with +0.9 m eye offset** (`:146`):
  ```gdscript
  var q := PhysicsRayQueryParameters3D.create(l.global_position, world_pos + Vector3.UP * 0.9, 1, exclude)
  ```
  consistent with loader bodies today; any future occluder on another layer is
  silently see-through, and the offset can peek over low cover.
- **P1-H4 — single-slot cache thrashes with >1 sampler** (`:118-127`):
  ```gdscript
  func sample_visibility(world_pos: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> void:
      _sample_calls += 1
  ```
  player + guard queries alternate positions → the 12.5 Hz throttle helps only
  single-sampler cases.

**Dead code:** `_sample_calls` (`:48`, `:120`) is write-only telemetry
(**P2-D6**, trivial); `sample_compute_count()`, both curve helpers are consumed.

**Performance notes:** per compute = O(registered) loop with two
squared-distance rejects before any raycast; `light_energy <= 0.01` skips
authored-off lights. A 96-light map raycasts only the handful in range, at most
every 80 ms per position. No per-sample allocation beyond the query object.
`_build_post_process_gi_fills` omnis are render-only (not probe-registered): no
stealth cost, but also no stealth effect.

---

## 11. `game/src/core/net_manager.gd` (173 lines) — Grade: **FIX**

**Owns:** 2-player ENet transport — `host()` / `join()` / `disconnect_net()`,
per-frame `broadcast_player_state()` (unreliable) + `send_world_event()`
(reliable), remote capsule/GLB visuals, `find_child`-based world-event application.

**Top defect risks:**

- **P0-4 — unauthenticated `any_peer` RPCs drive arbitrary `interact()` by node name** (`:75-77`, `:86-88`, `:159-173`):
  ```gdscript
  @rpc("any_peer", "unreliable_ordered")
  func sync_player_state(pos: Vector3, yaw: float, crouching: bool, thief_id: String) -> void:
  ```
  ```gdscript
  @rpc("any_peer", "reliable")
  func sync_world_event(kind: String, target_name: String) -> void:
  ```
  ```gdscript
  var target: Node = root.find_child(target_name, true, false)
  ```
  ```gdscript
  elif target.has_signal("triggered"):
      target.emit_signal("triggered")
  ```
  any peer spoofs positions and triggers vaults/doors/quest logic by name — no
  allowlist, no ownership check. Also `interact` receives `self` (the
  NetManager), not the interactor. Not shippable for public lobbies as-is.
- **P1-N1 — `is_coop` set before any connection exists** (`:40-50`):
  ```gdscript
  var err: Error = peer.create_server(port, 2)
  if err == OK:
      multiplayer.multiplayer_peer = peer
      is_coop = true
  ```
  `join()` sets `is_coop = true` on `create_client()` success; `broadcast_*`
  then RPCs into the void, and `connection_failed` never resets the flag.
- **P1-N2 — spawn-before-handshake** (`:106-109`):
  ```gdscript
  func _on_peer_connected_spawn(id: int) -> void:
      if not is_coop:
          return
      _ensure_remote_visual(id, "")
  ```
  creates `RemotePeer_*` under the mission root (or `self` in menus) on every
  connect; stale visuals accumulate without `disconnect_net()`.

**Dead code:** `REMOTE_GLB_CANDIDATES` fallbacks and the parallel
`peer_connected` re-emit vs `_on_peer_*` handlers can drift — consolidation, not deletion.

**Performance notes:** per-frame 60 Hz `unreliable_ordered` full-state RPCs
including the invariant `thief_id` string — no throttle/quantization/distance
cull; `_find_remote_packed()` does synchronous GLB `load()` on join (hitch);
`_apply_world_event` walks the scene tree per event (fine at low frequency).

---

## 12. Other files in scope

- `game/src/core/save_system.gd` (316 lines) — Grade: **WATCH.** Atomic
  `.tmp`-write + rename, clamp discipline, and XP-curve level derivation are
  right. **P1-C1** — `purchase_item()` deducts before validating:
  ```gdscript
  data["currency"] = int(data.get("currency", 0)) - cost
  var lst: Array = _unlock_list_for(category)
  if lst.is_empty():
      return false
  ```
  (`:292-305`) an invalid category keeps the deduction in memory (self-heals on
  reload since `write_save()` is skipped — still wrong). **P1-C2** — blind merge
  trusts the file (`:195 `data.merge(pd, true)``) with only missing-key backfill
  (no type checks; `"currency": "lots"` → `int(…)` silently 0), and `write_save()`
  (`:200-208`) returns silently on tmp-open failure while callers report success.
  No dead code; per-pickup full-file `JSON.stringify` + disk write on every
  `add_currency()` should be debounced.
- `game/src/stealth/noise_bus.gd` (26 lines) — Grade: **KEEP.** One signal +
  surface vocabulary; the correct seam between AI hearing and audio pools.
  **P2-D7:** the `SURFACES` contract is comment-only — a typo (`"wod"`) falls
  through to a default with no warning; no validation/culling at the bus (every
  footstep fans out to every listener). Consider a debug-only surface assert.

---

## Ranked issue list

### P0 — crash / wrong-behavior (5)

| # | File:line | Issue |
|---|-----------|-------|
| P0-1 | `audio_manager.gd:482` | `player.get_rid()` on `Node3D` — invalid call on every Guildhall/OldManor footstep: `var excluded: Array[RID] = [player.get_rid()]` |
| P0-2 | `animation_library.gd:~660/~700` | `_load_source` takes the first animation in the GLB, ignoring the clip name — wrong takedown side can play: `for an in lib.get_animation_list():` + `if anim == null:` |
| P0-3 | `game_state.gd:126-130` | `loot_goal` reached short-circuits quest objectives — mission completes without the quest item: `if loot_goal > 0 and loot_value >= loot_goal: return true` |
| P0-4 | `net_manager.gd:75-77,159-173` | unauthenticated `any_peer` RPC executes `interact()`/`triggered` on any node by name: `var target: Node = root.find_child(target_name, true, false)` |
| P0-5 | `level_loader.gd:1685-1688` | collision shapes past 32000 are silently dropped — walk-through geometry: `if int(ctx.get("collision_shapes", 0)) >= MAX_TOTAL_SHAPES: return` |

### P1 — degradation (41)

Level loader (6): L1 missing-mesh skip + glb-only resolve (`:764-775`, `:1720-1727`);
L2 null-texture → substring guessing (`:327-329` + material fallbacks);
L3 Den string-gating + 1 cm visual lookup (`:1533`, `:1559-1577`, `:1627`);
L4 curb cap + shared shape budget (`:2021-2024`);
L5 `discard_holes` map-name match (`:~2711`);
L6 emissive quad vs shadowless omni desync (`:~2350`, `omni.shadow_enabled = false`).
Animation (3): A1 shared-instance `applied.clear()` collision;
A2 pelvis-only `k` fallback (`k = 0.01`);
A3 unbounded static caches.
Weather visuals (3): W1 4K pano `load()` per `make_sky`;
W2 `Sky` alloc per switch, old sky never freed;
W3 rain amount ignores mobile tier.
Weather profile (4): P1 JSON re-parse per lookup (`:68-94`);
P2 unconditional volumetric + SSIL + SSR-48 on desktop;
P3 fog energy ÷ lum clamped 24×;
P4 5-level glow loop + `hdr_scale 2.0` off-Den.
Mobile (3): M1 `_settings()` tree lookup per cap query;
M2 desktop `Engine.max_fps = 0` + forced bilinear scaler;
M3 order-dependent `minf` glow cap.
VFX (6): V1 alarm spot 4.5 / strobe 5.4 + tween fight;
V2 ward wash 1.6 + energies 2.4/2.8 over the 0.65 caps;
V3 wisp caller-controlled energy + infinite bob tween;
V4 per-footstep mesh/material/tween storm (6 s life);
V5 `ttl = 0.0` godray/beams never auto-free;
V6 footstep-mask per-texel loop on first wet step.
Audio (4): U1 `MAX_VOICES` silent drop (`:959-960`, `:977-978`);
U2 `fire_event` plays everything at −10.0 (`:872-884`);
U3 scene-unsafe countdown/horn `await` timers (`:619-624`, `:842-844`);
U4 bed OGG `duplicate()` to set loop (`:643-651`).
Game data (5): G1 tutorial → `jaspering_hall` + `"example"` catch-all (`:445-449`);
G2 unknown map inherits FTUE unlimited (`:352-359`);
G3 `parts[1]` filename parse (`:238-240`);
G4 `MatchDurationsByDifficulty[1/2]` invented keys (`:481-483`);
G5 raw-`.png` `FileAccess` icon check (`:429-432`).
Game state (2): S1 dual completion sources (`:167-168`, `:201-205`);
S2 set-counter over-increment + stale `loot_needed` (`:184-195`, `:26/:62/:220`).
Net (2): N1 optimistic `is_coop` (`:40-50`);
N2 spawn-before-handshake (`:106-109`).
Save (2): C1 deduct-before-validate (`:292-305`);
C2 blind `merge` + silent write failure (`:195`, `:200-208`).
Light probe (4): H1 unoccluded directionals (`:130-134`);
H2 0.08 floor + 0.15 minimum (`:113-115`, `:139`);
H3 layer-1-only mask + 0.9 m offset (`:146`);
H4 single-slot multi-sampler cache (`:118-127`).

### P2 — cleanup (10)

D1 `FP_BLEND` (`animation_library.gd:117`) never read (sole `game/` occurrence).
D2 `bone_report()` (`:303`), `has_fp_role()` (`:470`) — no callers in `game/`
(incl. tests); `applied_clip_count()` / `fp_clip_for_role()` have callers — keep.
D3 triplicated AU4 doc headers above `wire_hover_sfx()` (`audio_manager.gd:530-543`).
D4 `BED_TARGET_DBFS` / `UI_DB` / `VO_DB` defined but bypassed by `fire_event`.
D5 `contracts_source_table` (`game_data.gd:11`, written `:268`) never read.
D6 `_sample_calls` (`light_probe.gd:48`) write-only telemetry.
D7 `noise_bus` surface contract comment-only; no emit validation.
D8 `save_system.gd:61-63` assumes bus 0 is Master; unchecked `dir.rename` result.
D9 `_aim_node` basis logic triplicated across VFX spawners — consolidate.
D10 `mobile_profile.set_tier` silent no-ops + static `_force_mobile` leak across tests.
