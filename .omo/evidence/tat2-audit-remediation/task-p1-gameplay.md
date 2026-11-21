# TAT-2 Audit Remediation — Task P1 Gameplay (thief / AI / mission-contract)

Date (UTC): 2026-11-21. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
§3 (P1 backlog) plus lane reports `audit-gameplay.md` (P1 1–14, P2 1–12).
Scope: gameplay P1s + the assigned P2s that live in writable files.
Phase 1 (13 P0s) taken as landed. `make test` NOT run here (orchestrator runs
the full suite at settle); VERIFY below is file-level + targeted checks.

Sentinel discipline (per fix): UE path logged in a comment, loud failure
(`push_error`/`push_warning` + `assert(false, …)`) on contract breaks, never
silent continue. `assert` is debug-only by Godot convention; `push_*` is the
release-visible signal.

Check outputs (2026-11-21, targeted, no godot binary on this host):
- C1 marker sweep: every fix anchor present (see per-item lines); stale
  patterns gone: `_note_air_release` 0 refs, per-guard `GDScript.new()` 0,
  smoke `"node": null` 0, swinging-door `set_locked(true, 1)` 0 live code
  (1 comment mention), `players.back()` 0 live code (1 comment mention).
- C2 balance: `{}`/`()`/`[]` deltas are 0 in all 10 touched files.
- C3 indent: 0 space-indented lines across all touched files.
- C4 re-read: every edited span re-opened after editing (see lines).

## Thief batch (`game/src/player/thief_character.gd`)

| # | Audit item | Verdict | Evidence |
|---|------------|---------|----------|
| T1 | Crank starts/continues on wall-climb (`_tick_wire_crank` gate skips `is_wall_climbing`) | FIXED | `_begin_wire_crank` + `_tick_wire_crank` now exclude `is_wall_climbing` (~l.1046,1117). C1 `is_wall_climbing` 15 refs incl. both gates. |
| T2 | Astral activation does no state cleanup (grapple/mantle/climb/crank persist) | FIXED | Moth branch clears grapple (with `_note_air_link_start`), mantle, climb, crank before `astral_active=true` (~l.1560). |
| T3 | Tap-fire hop (release on next physics frame, winch starts 0.3) | FIXED | `GRAPPLE_MIN_HOLD_SEC=0.12` (l.51); releases shorter than it keep the winch engaged (l.929-930). Retained tuning, no UE source. |
| T4 | Mantle early-return skips stamina regen, disguise drain/probe, light probe, hold progress | FIXED | Mantle branch ticks stamina + `_tick_sustained_systems(delta)` (l.905-912); helper also owns the normal path (l.1055). Disguise-TTL pause exploit + hold freeze closed. |
| T5a | Fairy arrival rechecks block with the moved player pos | FIXED | Throw-time `global_position` snapshotted to `throw_pos`; `_on_fairy_arrived(mark, throw_pos, seq)` tests the snapshot (l.1878). |
| T5b | Fairy SceneTree timer has no cancel (freed mark guarded, level/down- mid-flight not) | FIXED | `_fairy_seq` guard: stale seq / not-inside-tree / state≠playing / downed → silent return (l.1881). |
| T6 | Smoke charge-before-spawn (no camera + no spawner eats the charge) | FIXED | `smoke_spawned` flag; decrement only on commit, else `push_error` + `assert(false)` + keep charge (l.1740). |
| T7 | Sap instant-30 m teleport (throw anim cosmetic) | FIXED | `SAP_ARM_DELAY_SEC=0.3` arm delay with throw-time aim snapshot + stale-timer refund in `_on_sap_armed` (l.1694-1720). No speed invented (Godot-side pacing only). |
| T8 | Crank 0.5 s trickle refund offsets cooldown without completing | FIXED | Partial refund deleted in `_end_wire_crank`; only full crank clears cooldown + grants charge (l.1145). |
| T9 | Fall immunity chains (release-at-apex + re-grapple never pays) | FIXED | `_note_air_link_start` counts consecutive airborne immune-engagement starts; link 3+ sets `_fall_immunity_revoked` (l.357-372); `_apply_fall_damage` honors it with a loud warning (l.375). Grounded non-immune frames reset. Retained tuning `AIR_GRAPPLE_CHAIN_LIMIT=2`, no UE source. |
| T10 | `tool_used` gaps (blackjack/disguise/astral) | FIXED | Emits added: blackjack (l.1929), chameleon toggle + steal-disguise, moth astral. Safe: no HUD `tool_used` listener (grep), world_pickup uses `("ammo_refill", -1)` precedent. Mantle intentionally not emitted (movement, not a tool). |
| T11 | Viewcone double-count depends on external-before-tick call order | FIXED | External calls only queue (`_pending_viewcone_*`); `_tick_sustained_systems` consumes once per tick, local scan OR-ed in (l.1272,1060). Two-guards-per-tick double drain also closed. |
| T12 | Inverted `_end_astral` guard (`not active and not vision`) | FIXED | Now `if not astral_active: return` (l.1614). |
| T13 | Sprint: no hysteresis (FOV flicker at 2.0), `absf` hides sign errors | FIXED | Start floor 3.0 / stop floor 2.0 + toggle re-arm gate at input (l.918-930); positive-curve `push_error` + assert (l.936). |
| T14 | Downed branch doesn't clear grapple (single-entry invariant only in `_enter_downed`) | FIXED | Downed branch clears `is_grappling` too (l.869). |
| T15 | No revive signal | FIXED | `signal revived` (l.88) + `revived.emit()` in `revive()`. |
| T16 | Dual vision vars (`thief_vision` vs `thief_vision_on`) | FIXED | `is_thief_vision_active()` documented as the single reader; `_sync_thief_vision` single writer (l.835). |
| T17 | Anim fallback asymmetry (locomotion silent, crank loud) | FIXED | Fallback now `push_warning`s with the UE clip path (l.2520). |
| T18 | `TPTakedownPlayer` never stopped (montages fight on the rig) | FIXED | `_tp_takedown_stop()` added; called at swing start and on downed (l.2639,1909,441). |
| T19 | Smoke preview does 32 raycasts/frame in `_process` | FIXED | Throttled to `PROP_SCAN_INTERVAL` (l.1993). |
| T20 | Hold-interact uses two clocks (wall ms vs physics) | FIXED | `_interact_hold_sec` accumulates physics delta in the helper (l.1091); release reads it (l.640). Pause/slow-mo safe. |
| T21 | Per-tick `stamina_changed`/`disguise_changed` spam | FIXED | `_emit_*_if_changed` with epsilon/state gates (l.1100-1116). |

## AI batch (`game/src/ai/guard_ai.gd`, `civilian_npc.gd`)

| # | Audit item | Verdict | Evidence |
|---|------------|---------|----------|
| G1 | Pickpocket free/silent on SUSPICIOUS/ALERTED/SEARCH victims | FIXED | `interact()` allows only NEUTRAL lift / KO loot; alert attempts escalate to ALERTED + 6 m `pickpocket_spotted` noise (l.1655). NEUTRAL success bumps SUSPICIOUS + 4 m tell (l.1577). Carried-item proxy now routes through `interact(actor)` (l.1611) so the gate can't be bypassed. |
| G2 | ALERTED outruns COMBAT (`chase_speed` unscaled) | FIXED | `chase_speed *= _speed_scale` + `lose_sight_range` scaled in `_ready` (l.231); `_move_ai` ALERTED/COMBAT arms use `get_state_speed()` (l.1133,1145). |
| G3 | In-combat 15/s regen heals 0→full in ~2 s | FIXED | `_tick_regen` skips COMBAT + 4 s `_regen_blackout` after any damage (l.866); blackout set in `take_knockout`, ticked in physics (l.883,1053). Table values untouched (authored). |
| G4 | Dead `hearing_range` (radius = emitter loudness) | FIXED | `radius = minf(loudness, hearing_range)` with over-loud `push_warning` (l.1230); `state < SUSPICIOUS` corrected to `== NEUTRAL` (l.1249). |
| G5 | Sight rays ignore bodies (mask 1) | FIXED | Both rays (acquisition + disguise viewcone) use mask `1\|2\|4\|8` with self/player RID exclusion (l.1201,1695). |
| G6 | Retention snaps 20→30 m and drops the light gate on any blip | FIXED | `sensed` needs `detection >= 15` or non-neutral state; light multiplier gates both branches (l.1185). |
| G7 | Disguise hard-gate (invisible at 4 m in full light) vs still-running drain | FIXED | Gate needs distance > 9 m or sampled light < 0.35 (l.1171); near+lit inspects while DT_DisguiseV3 rows keep draining. Double-drain closed by T11 queue. |
| G8 | Sprint ×8 dwarfs light/crouch | FIXED (code) + HARD_LIMIT (value) | Authored `SPRINT_RAMP_MULTIPLIER=8.0` kept (detection.json rows 55-58) — changing it invents data. Code bug fixed: `vis_mult` now rates raw sampled light instead of the movement-floored value (l.1064), so sprint no longer pays twice (ramp × light-floor). |
| G9 | KO wake searches own feet, keeps pre-KO 100 | FIXED | `investigate_pos` keeps last stimulus (own-pos only when ZERO vector); meter clamped to revive ceiling 40 (l.1303). |
| G10 | Ally-revive: first-in-group, ALERTED/COMBAT never revive, strand on escalation | FIXED | Nearest-KO scan; ALERTED admitted, COMBAT excluded; strand cleared in `_set_state` on leaving calm set + on disallowed states; retarget on nearer KO (l.1329-1385). |
| G11 | Sticky de-escalation (`state_timer` manual everywhere) | FIXED | `_set_state` central `state_timer = 0.0` reset (callers overwrite) (l.886). |
| G12 | `players.back()` single-target sensing | FIXED | `_nearest_player(players)` helper (l.1095); physics uses it (l.1055). |
| G13 | Per-guard runtime GDScript compile in `_rebuild_carried_visual` | FIXED | `static var _carry_scr_cache` compiled once, reused, `reload()` error checked with assert (l.1595-1614). |
| G14 | SEARCH procedural pan fights `look_at` | FIXED | SEARCH eases yaw (`lerp_angle`, 5/s) instead of snapping (l.1157); other states keep snap. |
| C1 | Civilian guard-table coupling (`lib.setup("club", …)`) | FIXED | Passes `"civilian"` token (core library read-only coerces to club table — behavior identical, intent decoupled) with comment (civilian_npc.gd l.152). Full table split needs a core pass (out of scope, noted). |
| C2 | P0-8 re-verify (wander once) | ALREADY FIXED (Phase 1) | `_physics_process` repicks on idle expiry, arrival, and stuck timeout with nav/ray validation (`_pick_new_target`, `_is_target_valid`). No change made. |

## Mission/contract batch (`mission_controller.gd`, `interact/*`, `escape_gate.gd`)

| # | Audit item | Verdict | Evidence |
|---|------------|---------|----------|
| M1 | Clue re-fires toast + 1.5 m noise per press | FIXED | `clue_item.interact` returns silently when `collected` (l.69). First read still toasts + noises once. |
| M2 | Door/container lockpick noise sourced `self` → HUD arcs never flash | FIXED | `_noise_source()` (stored player driver) in lockable_door (8 uses), loot_container (4), swinging_door (7); `_audible_source(actor)` for hold/relock paths. Audibility unchanged (guards heard it); the player-facing feedback is restored. |
| M3 | Timeout reason travels but panel recomputes | HARD_LIMIT | Controller provides `timed_out`/`timeout_reason` (l.2081); the recompute lives in `hud.gd` (read-only). No writable-side fix exists. |
| M4 | Gaze bypasses `set_den_selected_map` | FIXED | Shared roster `is_selectable_den_map()` used by both setter and gaze site (l.724,993); gaze validates + highlights through the same path (no recursion: no card refresh inside the lookat builder). |
| M5 | Escape spawn not floor-grounded | FIXED | `_ground_escape_position()` explicit raycast with hit flag; keeps authored pos + `push_warning` when floorless (l.1935). |
| M6 | Wardrobe mouse-restore asymmetry | HARD_LIMIT | Close wiring lives in the wardrobe UI (read-only); controller cannot wire its `closed` signal. Noted for the UI pass. |
| M7 | `is_hub` (order) vs `_is_thieves_den` (map_id) split | HARD_LIMIT | Panel side is `hud.gd` (read-only). Controller consistently uses map_id. |
| M8 | `"lock"` noise tag has no audio mirror | HARD_LIMIT | `audio_manager.gd` is core (read-only). Guards hear it (tag-agnostic distance); audio mirror needs the audio pass. |
| M9 | Swinging-door relock downgrades to Lv1 | FIXED | `set_locked(true, maxi(lock_level, 1))` (swinging_door.gd l.232), parity with lockable_door. |
| M10 | Container locks 1-6 vs jam table 1-4 | FIXED | `FALLBACK_JAM_DAMAGE` extended 5:80/6:160 (authored doubling, retained inference) + clamp 1..6; table rows still win (lockable_door.gd l.16,57). |
| M11 | `loot_item` has no `get_interact_prompt` (falls back to "Steal") | FIXED | Quest items read `[E] Take …`, regular loot `[E] Steal …` (loot_item.gd l.201). |
| M12 | Bucket-hash duplication (two files, comment-kept) | FIXED | `loot_container.bucket_index` is the single source; `mission_controller._loot_bucket_index` delegates + asserts parity (l.1705). |
| M13 | Jaspering Hall unpreviewable (roster hardcoded to two maps) | FIXED | `is_selectable_den_map` roster + procedural fallback token (loud `push_warning`, no invented UE mesh) + `JASPERING HALL` card title (l.724,640,700,1003). |
| M14 | Guard count flat Novice→Thief | FIXED | Novice 4 / Thief 6 / Master 8 (l.1607). Retained tuning, no UE per-difficulty source. |
| M15 | Spawner/eco checks vs unified `loot_goal` | FIXED | `_audit_loot_economy()` sums spawned `loot` values after wave+containers; shortfall `push_error`s with both numbers (l.204); prints parity line when covered. Data-driven: error log, no assert. |
| M16 | Smoke gameplay/visual desync (`node: null` bookkeeping) | FIXED | Gameplay box authoritative over `SMOKE_TTL`; dead node field removed; non-standard TTL `push_error` + assert (l.2014). Callers already pass 25.0. |
| M17 | Table highlights wrong row (never sets `selected_order`) | FIXED | `open_contract_table_ui` sets `selected_order` from `GameState.active_contract_order` (l.1170). |
| M18 | Rain snap runs on result screens | FIXED | Snap moved inside the `playing` gate (l.2046). |
| M19 | Timer runs during mission-start letter | FIXED | `LETTER_GRACE_SEC=6.0` hold after the letter request (l.2040); lockpick minigame still runs the clock by design (player action time, not forced UI). |
| M20 | Contract→mission positional link; `mission_selected`/`objective_completed` dead | FIXED (link) + HARD_LIMIT (signals) | Link: Phase-1 deploy stash + `missions_by_id` validation + deterministic first-match legacy fallback, no silent discard (l.1180). Signals: zero `connect` sites; any listener would be HUD-side (read-only). |
| M21 | Fail/timeout persist nothing | HARD_LIMIT | No-partial-credit policy is a design decision (uncommented); inventing XP/attempt records is out of scope. Noted for design sign-off. |
| M22 | Quest loot advances objectives by positional convention (no objective id) | HARD_LIMIT | Binding lives in `game_state.add_loot` (core, read-only). Writable side already passes `is_quest_item`; id threading needs the game-state pass. |
| M23 | Wall-clock light cache (`light_probe` TTL on `Time.get_ticks_msec`) | HARD_LIMIT | `light_probe.gd` is core/stealth (read-only). Pause only expires the cache early (recompute on resume) — harmless, noted. |
| M24 | Mid-air bottle failsafe impacts (10 m noise from the sky) | FIXED | `_on_expire` now despawns silently instead of `_impact()` (thrown_bottle.gd l.67). |
| M25 | Fairy blocked-fail radius dynamic (`dist + 2.0`) | FIXED | `FAIRY_FAIL_RADIUS_M=8.0` fixed radius (thief T5 const). Arrival `pickpocket_spotted` 6.0 m kept (already fixed). |
| M26 | `save/quest` read paths the P1s name | VERIFIED READ-ONLY | Write path clean per audit §6; fail/timeout persistence is M21 (design). No writable-side change; no silent behavior added. |

## Counts

- FIXED: 21 thief + 14 AI + 2 civilian (1 already-fixed verified) + 20 mission/interact = 57 item-rows.
- HARD_LIMIT: 8 (M3, M6, M7, M8, M20-signals, M21, M22, M23) + 1 value-half (G8 authored 8.0 kept).
- Full `make test`: not run (orchestrator at settle). Targeted checks C1–C4 above all pass.
