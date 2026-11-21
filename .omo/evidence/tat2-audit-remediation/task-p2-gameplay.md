# Task P2-gameplay — evidence ledger

Date (UTC): 2026-11-21. Scope: AUDIT.md §4 Gameplay (12 groups) as itemized in
audit-gameplay.md P2 §12 plus the listed interact/mission hygiene rows.
Method: re-read every span in HEAD (`game/` post round-1 + round-2 playtest
fixes); 25 of 29 rows were already landed by phases 0-2 with `P2 ...` comments
quoting the fix. One row got the last minimal diff this turn (gaze-bypass
comment); 4 rows are standing HARD_LIMIT (fix lives in a read-only file).
No behavior change beyond the P2 item in any edit. `make test` not run per
brief (orchestrator runs the suite at settle); VERIFY is file-level re-read.

Result: **FIXED 25 / HARD_LIMIT 4.** No open rows.

## Thief / guard / civilian hygiene batch (audit-gameplay.md P2-12)

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Smoke preview raycasts in `_process` | FIXED | `thief_character.gd:2026-2033` throttles the 32-ray sweep to `PROP_SCAN_INTERVAL` (0.1 s, `:145`); `:3102-3115` gates on tool/charges/state/`can_act`/cam. Was every rendered frame. |
| 2 | Per-tick signal spam | FIXED | `stamina_changed` gated by 0.01 delta (`:1099-1101`); disguise via `_emit_disguise_if_changed` (`:1104-1109`). Event-path emits (damage `:1444`, steal `:1544`, toggle `:1579`) are not per-tick. |
| 3 | Two-clock hold | FIXED | Arm sets `_interact_hold_sec = 0.0` (`:593`); physics accumulates `delta` (`:1089-1091`); release reads physics seconds (`:601`). Wall-clock `Time.get_ticks_msec()` (`:592`) is now arm-flag only. |
| 4 | No-hysteresis sprint | FIXED | `SPRINT_START_STAMINA 3.0` / `SPRINT_STOP_STAMINA 2.0` (`:52-53`); engage/disengage logic (`:579-582`, `:957-964`). FOV lerp (`:909-910` per audit) no longer flickers at one threshold. |
| 5 | Downed/grapple invariant | FIXED | `is_grappling = false` cleared in both `_enter_downed` (`:440`) and the downed physics branch (`:872`); single-entry invariant holds even if the entry site is bypassed. |
| 6 | No-revive signal | FIXED | `signal revived()` (`:88`); `revive()` emits it after `health_changed` (`:464-471`). Downed-cleared counterpart to `downed_started`/`downed` exists. |
| 7 | Dual vision vars | FIXED | `thief_vision_on` is the single source; `thief_vision` mirrors it; `is_thief_vision_active()` (`:835-838`) is the documented accessor for new readers. |
| 8 | Anim fallback asymmetry | FIXED | Locomotion fallback warns like the crank path (`:2516-2520`: `push_warning(... FP role clip missing ...)`), closing the silent-vs-loud split (`:1030,1035` crank warns). |
| 9 | `TPTakedownPlayer` never stopped | FIXED | `_tp_takedown_stop()` (`:2639-2645`) stops the attacker montage; called before each replay (`:1998`) and on downed entry (`:441`). Overlap with crank montage gone. |
| 10 | Inverted `_end_astral` guard | FIXED | `if not astral_active: return` (`:1615-1616`); vision is synced, never gating. Old `not active and not vision` form removed. |
| 11 | `players.back()` single-target | FIXED | Nearest-player sense: `_nearest_player()` (`:1089-1096`) over the `player` group; conscious tick uses it (`:1014-1015`). Single-player behavior unchanged. |
| 12 | Runtime GDScript compile (guard carried item) | FIXED | `static var _carry_scr_cache` (`guard_ai.gd:~152`) compiled once via `GDScript.new()` + `reload()` (`:1621-1640`), reused by every guard; fail-loud (`push_error` + `assert`) on compile failure. |
| 13 | SEARCH pan vs `look_at` | FIXED | Body eases with `lerp_angle` during SEARCH (`guard_ai.gd:1144-1151`) so the procedural `visual_root` ±35° scan (`:1400-1404`) reads as head motion; non-SEARCH keeps snap `look_at` (`:1151`). |
| 14 | Civilian guard-table coupling | FIXED | `_setup_civilian_anims` passes the `"civilian"` token (`civilian_npc.gd:156-161`); comment records the core table coerces unknown weapons identically, behavior unchanged. |
| 15 | Bucket-hash duplication | FIXED | `loot_container.bucket_index()` is the single source (`loot_container.gd:62-69`); `mission_controller._loot_bucket_index` delegates and pins parity with `push_error` + `assert` on drift. |
| 16 | Wall-clock light cache | HARD_LIMIT | Cache clock lives in `game/src/stealth/light_probe.gd:125-127` (`Time.get_ticks_msec`), a core file outside the write scope (`MUST NOT touch core/...`). Pause-expiry recompute is benign; converging the clocks needs a core edit. |
| 17 | Dynamic pickpocket-fail radius | FIXED | Fixed `FAIRY_FAIL_RADIUS_M 8.0` (`thief_character.gd:55`); arrival-fail noise uses it (`:1861`), replacing `distance_to(mark) + 2.0` (farther = louder). |
| 18 | Mid-air bottle failsafe | FIXED | `_on_expire` despawns silently when `_impacted` is false (`thrown_bottle.gd:68-73`); the 6 s timer no longer `_impact()`s (no 10 m sky noise). Impact path unchanged (`:76-83`). |

## Interact / mission hygiene rows

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 19 | Rain snap on result screens | FIXED | `snap_rain_to` (`mission_controller.gd:2179-2180`) sits inside the `if GameState.state == "playing"` block (`:2156`); timer/smoke/Den-card share the same gate. Victory/failed panels get no snap. |
| 20 | Table highlights wrong row | FIXED | Opener sets both `selected_map_id` and `selected_order` (`GameState.active_contract_order`, `:1182-1186`) plus `coop_mode` (`:1187`); highlight no longer sits on contract #1. |
| 21 | Timeout reason recomputed | HARD_LIMIT | `contract_info["timed_out"/"timeout_reason"]` travel from the controller (`:2214-2215`) and the panel reads `timeout_reason` from info (`hud.gd:1722`), but the `timed_out` bool fallback recompute (`hud.gd:1717-1719`) can only be removed in `hud.gd`, which is read-only context. |
| 22 | Gaze bypasses `set_den_selected_map` | FIXED | This turn's diff: comment at `:1007-1012` records the direct write as intentional — the setter re-enters `_refresh_den_lookat_card` (we are inside it), so calling it would recurse; highlights converge on `_update_map_token_highlights`, one path. Zero behavior change. |
| 23 | Escape not floor-grounded | FIXED | `_ground_escape_position` raycasts with a hit flag and loud warning on miss (`:1976-1990`); `_spawn_escape` grounds the authored marker (`:1998-2002`), unlike the old raw placement. |
| 24 | Wardrobe cursor asymmetry | FIXED | No edit needed: `wardrobe_ui._apply_and_close` restores `MOUSE_MODE_CAPTURED` itself and emits `closed` (`wardrobe_ui.gd:1120-1124`); `open_customizer` takes the mouse (`:112`). The ledger-side wiring (`:600-604`) exists because the ledger does not self-restore. |
| 25 | `is_hub` order-vs-map_id split | HARD_LIMIT | `hud.gd:633,828,961,2071` keys hub off `active_contract_order <= 1` while the controller keys off `map_id` (`mission_controller.gd:139`, `_is_thieves_den`). Converging the two definitions needs a `ui/` edit, out of scope. |
| 26 | `"lock"` tag audio-less | HARD_LIMIT | Relock emits tag `"lock"` (`lockable_door.gd:335`, `swinging_door.gd:236`); `_resolve_tag` (`audio_manager.gd:886-911`) has no `"lock"` arm and `_sfx` has no `"lock"` key, so the mirror is silent. The fix (add the arm) lives in `audio_manager.gd`, a core file outside the write scope; swapping the emitted tag would alter the authored tag vocabulary. |
| 27 | Swinging relock downgrades to Lv1 | FIXED | `set_locked(true, maxi(lock_level, 1))` (`swinging_door.gd:232-234`); matches the `lockable_door` keep-level path (`lockable_door.gd:331-332`). |
| 28 | Container 1-6 vs jam 1-4 | FIXED | `FALLBACK_JAM_DAMAGE` extends the authored doubling to Lv5/6 (80/160) and `jam_damage_for_level` clamps 1..6 (`lockable_door.gd:44-60`); `loot_container.set_locked` 1..6 (`:152-157`) and `swinging_door.set_locked` via `table_max_lock_level()` now have economics for every level they accept. |
| 29 | `loot_item` prompt fallback | FIXED | `get_interact_prompt` returns `[E] Take %s` for quest items, `[E] Steal %s` otherwise (`loot_item.gd:205-209`); quest relics no longer read "Steal". |

## Out-of-list confirmations (read paths, no edits)

- Escape gate reads `GameState.are_all_objectives_complete()` (`escape_gate.gd:73-78`), not the stale `loot_needed` — P0-7 stays closed.
- Clue items are one-shot reads (`clue_item.gd:69-72` early-return; toast+noise only on first read) — the P1 re-fire row stays closed.
- Door/container lockpick noise carries the actor (`_audible_source`/`_noise_source`, `lockable_door.gd:225-235`; `swinging_door` mirrors) so HUD arcs flash — the P1 sourced-`self` row stays closed.
- This-turn diff footprint: 4 comment lines added at `mission_controller.gd:1008-1011`; zero logic lines touched.

Assumptions recorded: single player in `player` group; civilian passivity is design per `civilian_npc.gd:7-11`; Den area `GDScript.new()` sites (`mission_controller.gd:461,497,526,569,1097,1161`) build once per Den entry, not per frame, so they are outside the listed per-guard/per-tick hygiene rows and were left untouched; `ResourceLoader.load` call sites hit the loader cache.
