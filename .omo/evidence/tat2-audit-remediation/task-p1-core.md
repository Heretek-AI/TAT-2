# Task P1-Core — evidence ledger

Date (UTC): 2026-11-20. Scope: AUDIT.md §3 Core P1s + audit-core.md items for exactly:
`game/src/core/{level_loader,weather_visuals,weather_profile,mobile_profile,vfx_manager,audio_manager,game_data,game_state,net_manager}.gd`
+ `game/src/stealth/light_probe.gd`. No other game files touched (955+/147- across the 10 files).
Phase-1 P0s untouched; all fixes preserve test-pinned values (see §4).

Result: **33 FIXED, 2 HARD_LIMIT (H2, H3).** Nothing skipped.

## 1. Per-item verdicts

### level_loader.gd
- L1 missing-mesh hole — FIXED. Corrupt imports (resolved path, failed `load()` / non-PackedScene) are now distinguished from genuinely-missing meshes: `_note_corrupt_mesh()` push_errors with UE path + resolved path, counts separately (`corrupt_mesh_count`, 128-cap list). `_finalize` exports `corrupt_mesh_count/corrupt_meshes` + `meshes_ok` and push_errors `MESH HOLES` at settle when missing+corrupt > 0 (mirrors the T6 collider pattern). The missing path keeps its warning + 128-cap list.
- L2 null-texture guessing — FIXED. The substring-guess chain now records tier metadata on the material (`tat_fallback_tier`: 2 = guessed texture bound, 3 = flat color) and `_note_fallback_material()` push-warns with the UE path + running count (128-cap list). Coverage holes still render (no behaviour change) but never silently.
- L3 Den string-gating — FIXED (accounting + loud miss). `_add_den_window_split` counts splits + narrow-wall fallbacks (`den_window_splits/den_window_unsplit`); `_clip_den_window_visual`'s 1 cm sibling-miss now counts + push-warns with the collider origin (16-cap list) instead of silently leaving the gray slab. Rename detector via L5 disagreement error.
- L5 guildhall `discard_holes` map-name match — FIXED. `_landscape_weighted_material(lc, map_hint="")` takes an explicit hint derived from the level JSON path (`_map_hint_from_paths`, set as `ctx["map_hint"]` in both load paths). Explicit hint wins, source scan is the fallback, and any hint-vs-source disagreement is a push_error naming both. Test path (1-arg call, guildhall source) still yields 0.0.
- L6 emissive-vs-shadowless desync — FIXED. Quad keeps authored 2.0 energy but now fades over `LIGHT_DISTANCE_FADE_BEGIN+LENGTH` (`VISIBILITY_RANGE_FADE_SELF`), the same range its omni uses, so glow cannot outlive light. Shared constants, no new tuning.
- Heightmap per-texel decode (load-path storm) — FIXED. `(stride+1)^2` `get_pixel` calls replaced with a bulk `get_data()` byte read for RG8/RGB8/RGBA8 uncompressed images (byte-identical `(r8<<8)|g8`), with size guard + `get_pixel` fallback for odd formats.
- Footprint-mask prewarm (V6 companion) — FIXED. `load_sublevels`/`load_sublevels_async` call `_VfxManager.prewarm_footstep_mask()` so the one-time bake hides behind the loading screen.

### weather_visuals.gd
- W1 4K pano per build — FIXED. `_moon_panorama()` static cache: one disk decode per session, UE path logged once on hit/miss.
- W2 sky leak — FIXED (no-leak verified + churn reduced). `Sky`/`ShaderMaterial` are RefCounted: the old pair is freed on `env.sky` reassignment, so nothing accumulates; the allocation that mattered was the 4K texture, now cached (W1). Documented at the cache site.
- W3 mobile-ungated rain — FIXED. `make_rain` scales by `MobileProfile.rain_scale()` (desktop 1.0 / quality 0.8 / balanced 0.6 / performance 0.35), logged when < 1.0.

### weather_profile.gd
- P1 JSON re-parse per lookup — FIXED. Static `_map_table_cache` + `_preset_cache` (one decode each per session), `reload_weather_cache()` invalidator. Missing data still fails closed (warn + `{}`), `apply_for_map("no_such_map")` still false.
- P2 unconditional volumetric+SSIL+SSR-48 — FIXED. Desktop quality toggle: `set_quality_level(0-2)` + SaveSystem `graphics_quality` (low/medium/high), default high = shipped behaviour. High keeps all; medium halves SSR steps + drops SSIL; low drops all three. Logged per apply.
- P3 fog-energy 24x — FIXED. Both branches share `FOG_ENERGY_COMP_MAX := 8.0` via `_clamped_fog_compensation()`; over-cap presets push-warn with preset id + fog_lum. Old `24.0` literal removed.
- P4 glow loop — FIXED. Off-Den uses `GLOW_LEVELS_NON_DEN := 3` + `GLOW_HDR_SCALE_NON_DEN := 1.5`, levels 3-4 explicitly disabled. Den path byte-identical. `glow_intensity` formula untouched.
- M3 glow-cap order — FIXED. `apply_environment` ends with `MobileProfile.apply_environment(env)` when mobile, so the order is enforced at the seam instead of trusting call order.

### mobile_profile.gd
- M1 per-query tree lookup — FIXED. `_cached_tier` + `_tier_dirty`, invalidated in `set_tier()` and `set_force_mobile()` (the only writers). Out-of-range cache falls back to BALANCED with a warning.
- M2 desktop scaler stomp — FIXED. `apply_runtime` early-outs on desktop (no more `Engine.max_fps = 0` stomp, no forced 1.0x bilinear scaler).
- (M3 fixed on the weather side, above.) `rain_scale()` added here (0.35/0.6/0.8/1.0 perf policy).

### vfx_manager.gd
- V1 alarm 4.5→5.4 strobe + fade fight — FIXED. Strobe dips 4.5→2.2→4.5 (no overshoot; `ALARM_BASE_ENERGY/DIP_ENERGY` consts + assert), fade kills the strobe first (`fade.tween_callback(strobe.kill)`), bulb 4.0→3.0 cap + assert.
- V2 ward wash over caps — FIXED. `WARD_WASH_ENERGY := 1.2`, `WARD_SHADER_ENERGY := 2.0` + asserts + log (was 1.6/2.4/2.8).
- V3 unclamped wisp + infinite tween — FIXED. Caller energy clamped to `WISP_LIGHT_ENERGY_CAP := 0.65` (over-cap warned, assert). Infinite `bob_tween` kept deliberately: it is node-bound (`orb.create_tween` dies with the orb), so no orphan tween survives a freed wisp — documented.
- V4 per-footstep allocation storm — FIXED. Shared static `PlaneMesh`, `MAX_FOOTPRINTS := 24` oldest-first eviction (counted, warned 1st + every 50th). Per-decal materials kept (fade drives per-decal alpha; 6.0 s fade preserved).
- V5 `ttl=0` never-free — FIXED. `spawn_window_godray` gains `ttl` + returns the node; all ttl<=0 spawns (godray, foyer, ward, vine) register in the pruned/capped persistent set (`_register_persistent_vfx`, `persistent_vfx_count()`); timed spawns still self-free. Caller-owned decor is now counted, not invisible.
- V6 per-texel mask loop — FIXED. One-time bake downscaled to 128px (corner<0.05 / max>0.5 alpha contract preserved), still cached statically, plus `prewarm_footstep_mask()` called from the loader.

### audio_manager.gd
- U1 `MAX_VOICES` silent drop — FIXED. Oldest-voice stealing at cap (`_steal_voice_if_full`), steal counted, push-warn (5 s throttle); `_voice_players` list kept exact via finished-signal erase + dead-prune. No more silent cue loss.
- U2 `fire_event` bypasses trims — FIXED. UI→`UI_DB`, Dialogue→`VO_DB`, Ambience→bed-trim-by-name (`_ambience_trim_db`, `AMB_FALLBACK_DB` documented fallback), Music→documented fallback, SFX 2D→0.0 (matches `_play_at`). Flat -10.0 for UI/Dialogue/Ambience gone.
- U3 scene-unsafe awaits — FIXED. Countdown captures tree + scene + generation token; scene change or newer countdown bails and resets `_countdown_running` (the stuck-true-forever path). Horn replay skips when the scene changed.
- U4 bed OGG duplicate-to-loop — FIXED within engine constraints. Godot 4.7 has no `AudioStreamLoop` (probe-verified: identifier undeclared), and bed clips are shared with one-shot events (audio_events.json: e.g. `116714935.ogg` × 4 events), so flipping loop on the shared resource would strand one-shot players. Fix: one looped duplicate per unique clip, cached in `_bed_loop_cache` — map changes stop re-duplicating; one-shots keep the pristine stream; non-Ogg streams return the duplicate (old behaviour, no null).

### game_data.gd
- G1 tutorial misroute + catch-all — FIXED. `_mission_map_id(row_key, row)` reads key AND `QuestGraph.AssetPathName`: FTUE-graph rows (e.g. `Mission.Tutorial.Single` → `/Game/Maps/FTUE/…`) now route to `thieves_den` instead of `jaspering_hall`. Unrecognized rows still return `example` but via `_note_map_fallback()` (warned + counted).
- G2 unknown-map inherits FTUE unlimited — FIXED (loud). Same safe default (unlimited is safer than an invented timer) but now push_errors with the key + counted. No silent sharing.
- G3 `parts[1]` filename parse — FIXED. `Contract<N>` regex-validated (`is_valid_int`); renamed/non-matching files push_error + skip instead of colliding at `contract_strings[0]`. All 15 shipped files match, behaviour unchanged.
- G4 invented duration keys — FIXED. `_match_durations_of()` reads the Array shape when the converter emits one, else the scalar `[1]/[2]` keys (chained fallback identical to before), else warned 0s. Shipped scalar rows produce identical values.
- G5 raw-PNG icon check — FIXED. `ResourceLoader.exists` wins; `FileAccess`-only paths are still returned (callers need a path) but warned + counted as unimported pipeline gaps.

### game_state.gd
- S1 dual completion sources — FIXED. The loot path no longer sets `quest_item_acquired` or emits on its own; it marks `cleanout_loot` and completes only if `are_all_objectives_complete()`. (Flag is only read for empty-objective runs, where the loot block never fires — behaviour-preserving for Den.)
- S2 set-counter over-increment + stale `loot_needed` — FIXED. `set_main` auto-bump now fires only for generic pickups (`objective_id == ""`, the live `loot_item` flow) or explicit `"set_main"`; a specific `objective_id` advances only itself (no double-count). `set_mission_objectives` syncs `loot_needed = loot_goal` so HUD/gate readers follow the live goal (signal shape unchanged).

### net_manager.gd
- N1 optimistic `is_coop` — FIXED. `join()` no longer sets the flag; `_on_connected_handshake` (one-shot `connected_to_server`) sets it, `connection_failed` resets it (`_on_connection_failed_reset` + warning). `host()` still sets it immediately — a created server is real, not optimistic.
- N2 spawn-before-handshake — FIXED. `_on_peer_connected_spawn` no longer creates visuals; first authenticated `sync_player_state`/`sync_world_event` lazily creates them. Unexpected >2 live visuals push-warn (2-player session) but still serve.

### light_probe.gd
- H1 unoccluded directionals — FIXED. `_directional_occluded()` raycasts from the sample point toward the light axis (+Z basis convention, shared with weather_visuals) over `DIRECTIONAL_OCCLUSION_RANGE := 50.0` on `OCCLUSION_MASK`; hits skip the 0.35 contribution. Off lights (≤0.01) skip like locals. Fail-open (false) on unusable space state.
- H4 single-slot thrash — FIXED. Two-slot ring (`_slot_pos/_val/_ms`, `_slot_next`) covers the player+guard sampler pair; `clear_lights`/`short_circuit_lights`/`tick` invalidate via `_clear_slots()`. Throttle math (`SAMPLE_MIN_INTERVAL_SEC`, 0.75 m) unchanged.
- H2 true-darkness floor — HARD_LIMIT. `total := 0.08` + `LIGHT_VISIBILITY_MIN 0.15` are pinned by tests 36/36b (retune: median 1.0→0.90, integration `0.08 + 0.8² × 0.9`) and encode stealth balance. Changing them alters guard AI, not just rendering. Evidence: `run_tests.gd:2826,2837-2843`.
- H3 layer-1-only mask + 0.9 m offset — HARD_LIMIT. Mask 1 matches the loader contract (`level_loader` creates bodies with `collision_layer = 1`); the 0.9 m eye offset is stealth-balance tuning with no authored ground truth. Extracted to named consts (`OCCLUSION_MASK`, `EYE_OFFSET_M`) so a future change is one edit. Evidence: `level_loader.gd` body creation; no test pins either value.

## 2. Verification

(a) Godot 4.7.2 headless `--check-only` per file (flatpak; suite NOT run per brief):
- OK (rc 0, no errors): level_loader, weather_visuals, weather_profile, mobile_profile, vfx_manager, game_data, game_state, net_manager, light_probe (9/10).
- audio_manager: SOLE error is `Identifier not found: NoiseBus` at line 234 — pre-existing autoload reference (HEAD line 219; my diff adds zero NoiseBus lines), unavailable in check-only mode where autoload singletons aren't registered. All my edited regions parse (no other diagnostics).
- light_probe initially failed twice during the fix (dangling `_clear_slots` declaration; then the real `AudioStreamLoop`-absence finding in audio) — both corrected and re-verified OK above.

(b) Targeted per-P1 checks: `/tmp/p1_core_checks.py` — 69 assertions (fix presence + sentinel text + test-pin preservation), exit 0:
- Fix presence: L1/L2/L3/L5/L6/height-bulk/prewarm, W1/W2-doc/W3, P1/P2/P3/P4/M3, M1/M2/M3, V1/V2/V3/V4/V5/V6, U1/U2/U3/U4, G1/G2/G3/G4/G5, S1/S2, N1/N2, H1/H4 — all PASS.
- Pin preservation: rect energy 2.0, footprint 6 s fade + alpha/emission attrs, light-probe 0.15/0.90/0.08, mobile tiers 12/24/2.0, den glow formula, `meshes_ok`/`meshes` accounting shape — all PASS.
- H2/H3 HARD_LIMIT: pinned values asserted unchanged.
Re-run: `python3 /tmp/p1_core_checks.py` (repo-independent; reads `game/src/**`).

(c) Re-read: every edited span re-opened after editing (game_state indent fix, weather P2/P3/P4/M3, vfx footprint/godray, loader finalize/L5/heightmap, audio bed/fire_event/steal). Two real defects caught by verification and fixed: `_countdown_running` declaration accidentally dropped; `func _clear_slots()` without body.

## 3. Assumptions / judgment calls (design values, not extracted data)
- Ward energies 1.2/2.0, alarm bulb 3.0, rain scales 0.35/0.6/0.8, glow 3 mips + 1.5x HDR, fog cap 8x, footprint cap 24, persistent-VFX cap 512, directional occlusion range 50 m, quality-level semantics — perf policy chosen to bound cost while keeping shipped look; all logged/asserted at the site.
- FTUE tutorial → `thieves_den` is data-derived (`QuestGraph` `/Game/Maps/FTUE/`), not guessed.
- Unknown-map timer stays unlimited (fail-loud, not fail-closed): inventing a timer on a real map is worse than unlimited.
- V3 keeps an infinite (node-bound) bob tween: persistence is the design, clamping was the defect.

## 4. Follow-ups for other nodes (not this scope)
- `settings_ui` does not expose `graphics_quality` yet — the P2 toggle reads it if present, else high. Wiring the UI control is a UI-node task.
- Animation (A1-A3) and save (C1-C2) P1s belong to their own nodes' write scopes; untouched here.
