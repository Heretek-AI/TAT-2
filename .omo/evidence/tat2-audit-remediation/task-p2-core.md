# Task P2-Core — Evidence Ledger

Date (UTC): 2026-11-21. Scope: core/stealth polish only.
Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md` §4 Core
(D1–D10) + lane reports' core-owned P2 leftovers.
Write scope honored: `game/src/core/*`, `game/src/stealth/*` only.
No `ai/player/missions/interact/ui/tests/tools` file touched.
`make test` NOT run (orchestrator runs the full suite at settle).

## Verdicts — D1–D10 (AUDIT §4 Core)

| Item | Location | Verdict | What was done |
|------|----------|---------|---------------|
| D1 `FP_BLEND` unread | `core/animation_library.gd:117` (was) | FIXED this turn | Deleted the dead const (sole `game/` occurrence incl. tests, verified by grep). Wiring it (e.g. `set_blend_time`) would add crossfades = behavior change, out of polish scope. Value recoverable from git if FP crossfades are ever added. |
| D2 `bone_report` / `has_fp_role` no callers | `core/animation_library.gd:303,470` (were) | FIXED this turn | `bone_report()` deleted (zero callers in `game/` incl. `tests/`, verified by grep; per-role coverage is asserted via `missing_roles`/`applied`). `has_fp_role()` wired as the single table-membership check in `ensure_fp_clip()` (early `if not has_fp_role(role): return ""`, `else` branch simplified; behavior identical). |
| D3 triplicated AU4 headers | `core/audio_manager.gd:552-558` (were) | FIXED this turn | Three stacked `AU4:` comment blocks above `wire_hover_sfx()` collapsed into one merged block (names + `ui_`-prefix form + full cue list). Comment-only. |
| D4 volume-trim bypass (`BED_TARGET_DBFS`/`UI_DB`/`VO_DB`) | `core/audio_manager.gd:888-944` | FIXED (prior phase, verified this turn) | No edit needed: `fire_event` now routes UI→`UI_DB`, Dialogue→`VO_DB`, Ambience→`_ambience_trim_db()` (bed-name substring, documented `AMB_FALLBACK_DB`/`MUSIC_FALLBACK_DB` fallbacks). Re-read this turn, spans match. |
| D5 `contracts_source_table` write-only | `core/game_data.gd:11,282` | FIXED this turn | Kept as provenance (which DT_/CDT_ table `contracts.json` overlay came from) + documented + added `contracts_source()` accessor. Read-capable, zero behavior change. |
| D6 `_sample_calls` write-only telemetry | `stealth/light_probe.gd:48` | FIXED this turn | Added `sample_call_count()` getter (total invocations incl. cache hits); compare with `sample_compute_count()` for throttle/cache hit rate. Same pattern as the existing test-used getter. |
| D7 `noise_bus` comment-only contract | `stealth/noise_bus.gd:1-26` | FIXED this turn | Stale comment corrected (surface does NOT travel on the bus — no surface arg exists; `play_footstep` resolves listener-side). Added `is_known_surface()` static for typo-loud surface checks + empty-tag `push_warning` (warn-only, emission unchanged). |
| D8 bus-0 assumption + unchecked `dir.rename` | `core/save_system.gd:69,208` (were) | FIXED this turn | Master bus now addressed by name (`get_bus_index("Master")`, warns if missing instead of touching index 0). `write_save` warns on tmp-open failure; `dir == null` warns; `rename()` result checked with `error_string` warning. Log-only, no save-format change. |
| D9 triplicated `_aim_node` | `core/vfx_manager.gd:107,306,380` (were) | FIXED this turn | Grapple-beam + godray-shaft inline basis blocks (identical +Y convention) now call `_aim_node()`; unused `offset` locals removed. `_aim_node` documented as the +Y-beam shared helper; Z-facing swing streak keeps its convention with an explicit NOT-`_aim_node` comment; `-Z` stays in `_aim_spot`. Same math, fewer copies. |
| D10 `set_tier` silent no-op + static leak | `core/mobile_profile.gd:54` | FIXED this turn | Non-Dictionary save data now warns (was silent return); out-of-range tier warns then clamps (was silent clamp). Added `reset_test_state()` clearing `_force_mobile` + dirtying the tier cache for test isolation (test-support API, same precedent as `sample_compute_count()`). |

## Verdicts — task-named P2-adjacent items (core-owned)

| Item | Location | Verdict | Notes |
|------|----------|---------|-------|
| Scene-unsafe `await` timers (U3) | `core/audio_manager.gd:629-650,842+` | FIXED (prior phase, verified this turn) | `_countdown_async` carries token + scene check (stale timer bails, `_countdown_running` resets); horn path guards `current_scene`. Re-read this turn. |
| Bed OGG duplicate-to-loop (U4) | `core/audio_manager.gd:643-665` | FIXED (prior phase, verified this turn) | One looped duplicate per unique clip via `_bed_loop_cache` (shared one-shots untouched). Re-read this turn. |
| `"lock"` tag audio-less (gameplay P2-8) | `core/audio_manager.gd:952-972` | FIXED this turn | `"lock"` now maps to the `lockpick` cue in `_resolve_tag` (relock was audible to guards via NoiseBus but silent to the player). One match-arm, no other change. |
| S1/S2-adjacent polish (dual completion, set-counter, `loot_needed`) | `core/game_state.gd:22-26,47-62,152-220` | FIXED (prior phase, verified this turn) | Loot path only completes when the full objective list is done; set-counter advances only for generic/`set_main` pickups; `loot_needed` synced to `loot_goal` in `set_mission_objectives` (kept as LEGACY compat with comment). Re-read this turn. |
| N-hygiene (optimistic `is_coop`, spawn-before-handshake) | `core/net_manager.gd:38-90,169-258` | FIXED (prior phase, verified this turn) | Handshake-gated `is_coop` + `connection_failed` reset; no spawn-before-handshake (lazy `_ensure_remote_visual`); closed allowlist + ownership + rate limits on world events. Re-read this turn. |
| H-polish (directional occlusion, cache, named consts) | `stealth/light_probe.gd:44-50,118-127` | FIXED (prior phase, verified this turn) | H1 directional occlusion raycast, H4 two-slot ring cache, `OCCUPATION_MASK`/`EYE_OFFSET_M` named consts all present. Re-read this turn. |
| C1 deduct-before-validate | `core/save_system.gd:307-324` | FIXED this turn | Category validated via `_unlock_list_for` BEFORE any deduction (old order kept the deduction in memory for unknown categories). Reorder only. |
| C2 silent write failure (partial) | `core/save_system.gd:200-221` | FIXED (warn path) + HARD_LIMIT (merge) | Tmp-open failure, `user://` open failure, and rename failure now all `push_warning`. See HARD_LIMIT row for the merge half. |

## Standing HARD_LIMIT rows (unsafe to touch as polish; line-cited)

| Item | Location | Reason it stays |
|------|----------|-----------------|
| C2 blind `data.merge(pd, true)` | `core/save_system.gd:~195` | No type checks (`"currency": "lots"` → `int()` 0). Type-gating the merge changes load semantics for existing player saves — needs a save-migration design, not a polish diff. |
| G1 tutorial→`jaspering_hall` + `"example"` catch-all | `core/game_data.gd:445-495` | Fallbacks are now counted + warned (`_note_map_fallback`). Converting to hard errors would break Jaspering Hall tutorial routing and Contract 1's hub default — needs design sign-off. |
| G2 unknown map inherits FTUE unlimited | `core/game_data.gd:352-379` | Same: counted + warned. Erroring changes match-timer behavior for misspelled maps — needs routing policy. |
| G3 `parts[1]` filename parse | `core/game_data.gd:238-240` | `int("")` collides malformed tables at index 0 silently. Guarding changes contract-string mapping — needs a malformed-table policy coordinated with the parser. |
| G4 `MatchDurationsByDifficulty[1/2]` invented keys | `core/game_data.gd:481-483` | Falls back to `d0` (all-Novice durations) if the converter emits an Array. Changing the read changes difficulty durations — needs parser+data coordination. |
| G5 raw-`.png` icon check | `core/game_data.gd:429-472` | Now counted + warned (`icon_unimported_count`). Hard-gating would fail loads on present-but-unimported art. |
| U1 `MAX_VOICES` silent drop | `core/audio_manager.gd:959-978` | Priority/stealing policy + return-value API change — a design decision, not polish. |
| H2 darkness floor + H3 mask/offset | `stealth/light_probe.gd:36-50,146` | `LIGHT_VISIBILITY_MIN`/0.08 floor and layer-1 + 0.9 m offset are stealth balance tuned against the loader; changing them alters detection — needs design sign-off. |
| Wall-clock sample cache (gameplay P2-12) | `stealth/light_probe.gd:119-127` | Throttle uses `Time.get_ticks_msec`; pause expiry just recomputes on resume (lane-verified harmless). Switching clocks changes cadence + couples the probe to run-state. |
| N leftover: `_find_remote_packed` sync GLB `load` on join | `core/net_manager.gd:~240` | Preload policy for the join path; changing load timing touches net handshake — needs a loading-policy decision. |

## Verification (this turn, no `make test` per task)

- Re-read every edited span after editing: `animation_library.gd` (FP_BLEND deletion, `ensure_fp_clip` wiring, `bone_report` deletion), `audio_manager.gd` (AU4 header, `"lock"` arm), `game_data.gd` (`contracts_source` doc + accessor), `light_probe.gd` (`sample_call_count`), `noise_bus.gd` (header + `is_known_surface` + warn-only emit), `save_system.gd` (Master-by-name, write warnings, rename check, `purchase_item` reorder + duplicate-`lst` removal), `vfx_manager.gd` (3 `_aim_node` routings + `offset` cleanup + helper doc), `mobile_profile.gd` (tier warnings + `reset_test_state`).
- Targeted checks: grep confirms zero remaining `FP_BLEND` / `bone_report` references in `game/` (incl. tests); single `var lst` in `purchase_item`; `_aim_node(beam, from_pos, to_pos)` / `_aim_node(shaft, pos, target_pos)` call sites use in-scope params; no `ai/player/missions/interact/ui/tests/tools` file modified (all edits under `game/src/core/` + `game/src/stealth/`).

## Counts

- FIXED this turn: 11 (D1, D2, D3, D5, D6, D7, D8, D9, D10, `"lock"` tag, C1) + C2-warn-half.
- FIXED prior phase (verified this turn, no edit): 8 (D4, U3, U4, S1/S2, N1/N2, H1/H4, plus G1/G2/G5 sentinels).
- HARD_LIMIT standing: 10 rows above, each with line-cited reason.
