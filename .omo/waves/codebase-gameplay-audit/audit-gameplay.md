# TAT-2 Gameplay Systems Audit — End to End

**Scope:** `game/src/missions/mission_controller.gd` (2042 lines), `game/src/player/thief_character.gd` (3030 lines), `game/src/player/smoke_projectile.gd` (162), `game/src/ai/guard_ai.gd` (1603), `game/src/ai/civilian_npc.gd` (233), all 9 `game/src/interact/*.gd`, `game/src/stealth/noise_bus.gd` (26) + `light_probe.gd` (159), plus call-site reads in `game/src/core/game_state.gd`, `game_data.gd`, `save_system.gd`, `game/src/ui/hud.gd` (3055), `contract_table_ui.gd`, `mission_prep_ui.gd`, `lockable_door.gd`, `loot_container.gd`, `swinging_door.gd`, `escape_gate.gd`, `clue_item.gd`, `loot_item.gd`, `thrown_bottle.gd`. Read-only; no product code changed.
**Method:** full-file reads of every file above plus four parallel deep reads (missions / thief / AI / interact-stealth-save); every P0/P1 below was re-opened in place this session and quotes the exact lines.
**Counts: P0 = 8 (broken loop), P1 = 14 (weak loop), P2 = 12 (polish).**

---

## 1. mission_controller.gd — Den hub, contracts, minis, telescope, glow, objectives, spawners

### 1.1 Loop integrity (every frame vs event)

- `_process` runs the run-timer, smoke TTL, and rain snap every frame, gated on `GameState.state == "playing"` for the timer only (`mission_controller.gd:1987-1991`):
```
func _process(delta: float) -> void:
	if GameState.state == "playing":
		GameState.elapsed_sec += delta
		if GameState.run_time_limit > 0.0 and GameState.elapsed_sec >= GameState.run_time_limit:
```
Nobody ever writes `"paused"`/`"hub"` (`game_state.gd:22` comment lists them; only writers are `reset_run` → `"playing"` at `game_state.gd:59`, `_on_extracted` → `"victory"` at `mission_controller.gd:2008`, `_on_player_downed` → `"failed"` at `:2025`, `_on_time_expired` → `"failed"` at `:2036`). Pause works only because the tree freezes — any future `PROCESS_MODE_ALWAYS` node touching `elapsed_sec` breaks the timer silently. P2 architecture risk, recorded here.
- Mission-start letter and lockpick minigame do **not** stop the timer. `_trigger_mission_start_letter` (`mission_controller.gd:1205-1216`) emits `GameState.request_mission_letter`, HUD shows it (`hud.gd:1821-1832`), but `elapsed_sec` keeps accumulating and `_on_time_expired` can fire mid-letter. Same for the HUD-ticked minigame (`hud.gd:2065-2066`). Design-or-bug decision; listed as P1 (timer fairness).
- Smoke TTL bookkeeping tracks a node that is always null (`mission_controller.gd:1978-1981`):
```
func spawn_smoke(pos: Vector3, ttl: float = SMOKE_TTL) -> void:
	VfxManager.spawn_smoke_cloud(self, pos, SMOKE_HALF_EXTENTS, ttl)
```
appended dict is `{"min":…,"max":…,"ttl":…,"node": null}`; expiry (`:1994-2000`) frees `smokes[i]["node"]` = null, so gameplay occlusion expires correctly (`is_blocked_by_smoke`, `:1983-1986`) while the visual's lifetime is whatever VfxManager chose. P1 (gameplay/visual smoke desync).
- Rain snap runs outside the state gate (`mission_controller.gd:2003-2004`): `WeatherVisuals.snap_rain_to(rain_node, player)` every frame including victory/failed screens. Cosmetic only → P2.

### 1.2 Contract accept flow (Den → table → prep → deploy)

- **P0-1 — Prep mission picker is decorative; the choice is dropped.** `mission_prep_ui.gd:151`: `ready_pressed.emit(map_id, difficulty, mode, contract_order)` carries no mission id; the deploy closure (`mission_controller.gd:1132-1134`):
```
ui.connect("deploy_requested", func(order_id: int, map_id: String) -> void:
	GameState.reset_run(order_id, map_id)
	get_tree().reload_current_scene()
```
then `_setup_mission_objectives` (`mission_controller.gd:1150-1153`) re-derives positionally:
```
var matching: Array[Dictionary] = GameData.get_missions_for_map(map_id)
if not matching.is_empty():
	chosen = matching[absi(order) % matching.size()].duplicate(true)
```
An explicit user override in the OptionButton (`mission_prep_ui.gd:688-693`) is silently discarded; only the default (`mission_prep_ui.gd:712`, same formula) agrees.
- **P0-2 — Co-op mode selected in table/prep never reaches GameState.** Only writer in the codebase is the Den floor toggle (`mission_controller.gd:726`): `GameState.active_mission_mode = "Co-op" if GameState.active_mission_mode == "Solo" else "Solo"`. The table keeps a local `coop_mode` (`contract_table_ui.gd:23`), toggles locally (`:504-507`), emits it in `mission_selected` (`:517,544`) which has **zero listeners** (verified by grep), and the deploy closure takes only `(order_id, map_id)`. Host/Join + DEPLOY launches whatever the Den R-key last set. `GameState.difficulty` survives only because every selector mutates the autoload as a side effect.
- P1 — Contract→mission link is positional (`absi(order) % matching.size()`); `reset_run` clears `active_mission_id` on map change (`game_state.gd:42-44`). No persistent contract↔mission binding exists.
- P1 — `mission_selected` and `GameState.objective_completed` are emitted to nobody (zero `connect` sites). Objective completion produces no toast/prompt; only the HUD checklist ✓ next frame (`hud.gd:2134-2148`). The fallback `"Reach Escape Gate"` status line (`hud.gd:2152`) is unreachable whenever objectives exist.
- P2 — Table opens with the right map but the wrong row: `open_contract_table_ui` (`mission_controller.gd:1126-1129`) sets `selected_map_id` but never `selected_order`; `selected_order = 1` default (`contract_table_ui.gd:20`) highlights contract #1 regardless of the active contract.

### 1.3 Complete / fail paths

Topology is complete: victory only via `escape_gate._on_body_entered → extracted → _on_extracted` (`escape_gate.gd:73-78`, `mission_controller.gd:2007-2014`); failure via downed (`:2024-2028`) or timer (`:2033-2041`).
- P1 — Failures persist nothing; victory persists everything. `_on_extracted` does `SaveSystem.add_currency` + `record_contract_complete` (`mission_controller.gd:2011-2012`); `_on_player_downed` / `_on_time_expired` write no XP, no attempt record. If no-partial-credit is intended it is uncommented.
- **P0-7 — Escape gate and objectives use different loot thresholds** (see §7 interact cross-check). `escape_gate.gd:75`: `if GameState.quest_item_acquired or GameState.loot_collected >= GameState.loot_needed:` vs `game_state.gd:26`: `var loot_needed: int = 5` — never assigned anywhere else (grep-verified); `reset_run` (`game_state.gd:47-62`) resets `loot_goal` but not `loot_needed`. On a Cleanout (`loot_goal = 1000 × difficulty`, `mission_controller.gd:1186`) the gate opens at 5 items *or* at goal — a silent shortcut around a £3000 goal. Conversely `hud.gd:2152` shows count-vs-5 while objectives track value.
- P1 — Terminal states leave the world running behind a single-button panel (`hud.gd:1702-1729`, `RETURN TO MAIN MENU`; pause menu also goes to `main_menu.tscn`, `hud.gd:1612-1615`). No retry/redeploy; the controller issues no input-freeze or guard stand-down, relying on each system's own `GameState.state` checks.
- P2 — Timeout reason travels but the panel recomputes it anyway: `_on_time_expired` sets `contract_info["timed_out"]`/`["timeout_reason"]` (`mission_controller.gd:2038-2039`) while `show_result` re-derives from the clock (`hud.gd:1718-1719`).

### 1.4 Den map minis

Mechanism is the most carefully built in the file and essentially sound: per-token UE-derived base scale (`mission_controller.gd:660,683`), 1.15×/0.25 s tween with old-tween kill (`:674-675,687-693`), warm-gold emissive toggle (`:699-707`).
- P2 — `_refresh_den_lookat_card` (`:955-957`) writes `_den_selected_map_id` + highlights directly instead of via `set_den_selected_map` (`:710-717`); converges on `_update_map_token_highlights`, one maintenance path.
- P1 — Token roster hardcoded to two maps (`_spawn_map_table_miniatures`, `:606-663`, `old_manor`/`guildhall`; `set_den_selected_map` rejects anything else at `:710-711`) while contracts 17-18 (`jaspering_hall`, `game_data.gd` orders 17/18) are deployable from the same table. Jaspering Hall deploys (base sublevels exist, `:346-350`) but the Den selector can never preview it.

### 1.5 Telescope / ponder

State machine is clean: `_ponder_active`, same-frame double-dispatch guard (`mission_controller.gd:857-860`, `set_meta("ponder_toggle_frame", frame_now)`), camera created once and re-aimed per entry (`:870-892`), exit restores player cam (`:898-903`) + stops wind bed (`:904-905`), card forced (`:906`).
- **P0-4 — The F-key hint the card carries is never rendered.** Card sends `"hints": [{"key": "F", "label": "EXIT"}]` (`:930`), `"hints": [{"key": "H"...}, {"key": "R"...}, {"key": "F"...}]` (`:966-970`), `"hints": [{"key": "F", "label": "PONDER"}]` (`:981`), but `set_den_lookat_card` (`hud.gd:1840-1871`) reads only `lines`, `difficulty`, `mode`, `prompt`, `bottom_hints` — never `hints`:
```
var lines_v: Variant = card.get("lines", null)
...
		if card.has("difficulty"):
			_add_den_card_row("H", "Difficulty:", str(card.get("difficulty", "Novice")))
		if card.has("mode"):
			_add_den_card_row("R", "Mode:", str(card.get("mode", "Solo")))
		if card.has("prompt"):
			_add_den_card_row("F", str(card.get("prompt", "Prepare for Mission")), "")
```
The player sees H/Difficulty + R/Mode rows; the F row ("Prepare for Mission" / "PONDER" / "EXIT") is dropped. The 3D Area prompts (`"[F] ENTER MATCH"`, `"[F] PONDER"`) still show via the interact system — which is presumably why nobody noticed — but the Den card itself never advertises the F action it depends on (`_unhandled_input` F-handling at `:1013-1014,1017-1022`).

### 1.6 Glow / atmosphere

Ordering is correct and best-documented: fallback → weather preset → mobile override in `_setup_environment` (`mission_controller.gd:92-110`); Den dim (`:218-228`) runs *after* `_apply_level_atmosphere` (`:170` before `:177`); post-process re-enables glow only through the mobile-aware cap (`:291-302`, Den cap 0.32, `glow_hdr_scale 1.0`, 2 levels).
- P1 tuning — Guard count ignores Novice→Thief (`mission_controller.gd:1441`): `6 + (2 if MASTER_THIEF else 0)`. Identical patrol density for two of three difficulties.

### 1.7 Objectives construction

`_setup_mission_objectives` (`mission_controller.gd:1140-1202`) covers Set/Multi per map (`:1163-1184`), LootTheRoom `1000 × difficulty` (`:1185-1189`), vault fallback with map-specific relic names (`:1191-1201`); `GameState.set_mission_objectives` normalizes defensively (`game_state.gd:65-87`); quest loot is popped out of the minor/major pools before regulars (`mission_controller.gd:1596-1639`) with `_ensure_unique_loot_position` de-conflict (`:1729-1742`).
- **P0-3 — Clue text and loading-screen clue are always the generic fallback.** `_spawn_clues` (`mission_controller.gd:1220-1223`):
```
var clue_title: String = str(contract_info.get("title", "Contract Clue"))
var clue_body: String = str(contract_info.get("clue", "Locate the target vault and watch the Constabulary patrol timing."))
```
and the loading call (`:147`): `loading.call("start_loading", ..., str(contract_info.get("clue", "")), map_id)`. But `GameData.get_contract_display` never sets a `"clue"` key — it sets `"clue_facts"` (array, `game_data.gd:389`: `base["clue_facts"] = clues`); grep confirms zero `"clue"` writers in `game_data.gd`. So `clue_body` is always the hardcoded fallback and the loading screen always receives `""`. The table intel panel reads `clue_facts` correctly — only the mission-side consumers use the wrong key.
- P1 — Quest loot advances objectives without an objective id, by positional convention. `loot_item.interact` (`loot_item.gd:201-206`) calls `GameState.add_loot(1, value, is_quest_item)` with no `objective_id`, so `add_loot` (`game_state.gd:152-220`) scans for `set_main` and marks "the next incomplete `set_item_*`" (`game_state.gd:190-199`). Works for the single-quest-per-marker layout the spawner builds, but the binding is by array order, not by which relic was grabbed.

### 1.8 Spawner hooks

`_spawn_spawner_content` + `_spawn_swinging_doors` run for **every** map including the Den (`mission_controller.gd:194-195`, outside the `if/else` at `:186-193`); containers (`:191`, inside the `else`) are Den-skipped per their comment. Escape (`:193`, inside `else`) never spawns in the hub — so the Den has no victory path and no timer (`get_match_duration("thieves_den")` → FTUE 0 = unlimited). By construction; the container comment (`:1687-1690`) is easy to misread as covering all spawns.
- P2 — Escape gate is the one spawn not floor-grounded: guards/loot use `_ground_position` raycasts; `_spawn_escape` (`mission_controller.gd:1842-1849`) places `ue_escapes[0]` raw. A floating authored marker = a floating gate.

### 1.9 Save / progression handoffs

Clean on the write path: victory → `add_currency` + `record_contract_complete(order, score, ghost)` (`mission_controller.gd:2011-2012`) → XP (`maxi(100, score/2)`), level re-derived from the authored curve, atomic tmp-rename write (`save_system.gd`). Save hygiene is good: shallow-merge + `_ensure_defaults` backfills (`save_system.gd:140-175`), level re-derived from XP (`:186-196`), XP/level clamped (`:30-31`).
- P1 — Fail/timeout write nothing (see §1.3); mid-run quit loses everything since run state (`loot_collected/value`, `takedowns`, `objectives`, `elapsed_sec`) lives only in `GameState` and `write_save` persists only meta (xp/contracts/currency/unlocks/loadout).
- P2 — Wardrobe opened from the Den (`mission_controller.gd:1054-1058`) has no `closed` → mouse-restore wiring, unlike the ledger (`:1060-1074`, restores `MOUSE_MODE_CAPTURED`); if the wardrobe UI doesn't self-restore, the cursor stays visible in the hub.
- P2 — `hud.is_hub` keys off contract *order* (`hud.gd:633,828,961,2071`, `active_contract_order <= 1`) while `_is_thieves_den` keys off *map_id*. Any future non-hub contract on `thieves_den` (or hub-ordered contract elsewhere) splits the two definitions.

---

## 2. thief_character.gd + smoke_projectile.gd — movement, step-up, tools, takedowns

### 2.1 Loop integrity

- P2 — Smoke preview does physics raycasts in `_process`: `_update_smoke_trajectory` (`thief_character.gd:2891`) builds a 32-step ballistic `for i: int in range(1, 33):` with `space.intersect_ray(...)` per step, every rendered frame while smoke is equipped (`_process` at `:1835-1837`). Frame-rate-dependent preview on the wrong tick; throttle like `_prop_scan_accum` (`:972-975`).
- P2 — Unconditional per-tick signal spam: `stamina_changed.emit(stamina, max_stamina)` (`:906`) and disguise `disguise_changed.emit(...)` (`:980-993`) fire every physics tick even unchanged.
- P1 — Mantle early-return skips systems for 0.3 s (`thief_character.gd:846-857`): stamina regen (`:904-906`), disguise drain/TTL (`:980-993`), light probe (`:997-1000`), `interact_hold_progress` (`:1002-1006`) all freeze mid-mantle. Disguise TTL pause is a small exploit; hold-progress freeze is user-visible.
- P2 — Hold-interact uses two clocks: armed in `_unhandled_input` (`:522`) with `Time.get_ticks_msec()`, progress recomputed in physics (`:1002-1006`) with `float(Time.get_ticks_msec() - _interact_hold_ms)`. Wall-clock vs physics-delta mix; pause/slow-mo diverge.
- P1 — Fairy flight uses a SceneTree timer with no cancel (`thief_character.gd:1707`): `get_tree().create_timer(travel).timeout.connect(_on_fairy_arrived.bind(mark))`. Freed-mark is guarded (`is_instance_valid`, `:1712`) but level-change / downed-mid-flight are not.

### 2.2 State machine (no enum; flags `is_grappling/is_mantling/is_wall_climbing/_is_cranking/is_downed/astral_active`)

- P1 — Crank can start/continue on wall-climb: `_tick_wire_crank` gate (`:1011`) checks `not is_grappling`/`not is_mantling` but not `is_wall_climbing`; wall-climb (`:1179-1205`) doesn't check `_is_cranking`. Crank accrues while climbing.
- P2 — Mantle can trigger while wall-climbing (`:941` checks `not is_mantling` but no climb guard; `try_auto_mantle` at `:1123` likewise). Benign (success clears climb at `:1170-1171`) but overlapping.
- P1 — Astral activation does no state cleanup (moth branch `:1453-1457` sets `astral_active = true; astral_ttl = 8.0` without clearing grapple/mantle/climb/crank); grapple branch (`:861-881`) still overrides movement while astral. Combined with fall immunity (§2.4) astral+grapple is double-immune with ambiguous movement priority.
- P2 — `_end_astral` guard reads inverted (`:1477-1482`: `if not astral_active and not thief_vision_on: return` then resets both). Harmless; tighten to `if not astral_active: return`.
- P1 — Fire and release share `primary_action`: grapple fires on press (`:696`, `:1515`), release checks `Input.is_action_just_released("primary_action")` (`:866`); a tap-to-fire releases next physics frame with `winch = clampf(grapple_time / 0.35, 0.3, 1.0)` starting at 0.3 (`:869-872` vaults immediately). Quick-tap becomes hop, not pull.
- P2 — Sprint threshold has no hysteresis (`:890-894`: sprint needs `stamina > 2.0`, drops `_sprint_toggled` at `<= 2.0`); FOV lerp (`:909-910`) flickers at the boundary.
- P2 — Downed branch (`:814-825`) clears crank/mantle/climb but not `is_grappling`; safe only because `_enter_downed` (`:400`) sets `is_grappling = false` — a single-entry invariant that should be cleared in both places.

### 2.3 Missing handoffs

- P1 — `tool_used` missing for blackjack/disguise/astral: emitted for crank/grapple/sap/smoke/bottle/fairy (`:1058,1534,1568,1606,1627,1695-1707`) but never for `_try_blackjack` (`:1748-1783`), chameleon toggle, moth astral, mantle. HUD/cooldown listeners keyed on `tool_used` miss those actions.
- P2 — `interacted` missing on fairy arrival: `_on_fairy_arrived` (`:1711-1725`) calls `best.interact(self)` with no `interacted.emit` (other paths emit at `:1387,1428,1442`).
- P2 — No revive signal: `revive` (`:423-433`) emits `health_changed` but no downed-cleared/revived counterpart to `downed_started`/`downed` (`:402,409-414`).
- P2 — Dual vision vars: `_sync_thief_vision` + `_update_thief_vision` maintain both `thief_vision_on` and `thief_vision`; readers picking the wrong one see stale state (a public `is_thief_vision_active()` exists — use it everywhere).
- P1 — Viewcone double-count guard depends on call order: physics (`:983`) drains only `if not _viewcone_decay_handled`; external `apply_guard_viewcone_disguise_decay` (`:1275`) sets the flag + drains immediately, cleared end of physics (`:994`). Correct only if the external call lands before that tick's drain section; document or queue to next tick explicitly.
- P2 — Animation fallbacks hide missing clips inconsistently: `_update_fp_anim_state` (`:2321-2323`) silently falls back `crouch/sprint/walk` when `ensure_fp_clip` returns `""`, while crank warns (`:1030,1035`).
- P2 — Takedown 3P player never stopped: `_tp_crank_stop` (`:2428`) stops `TPCrankPlayer`; `TPTakedownPlayer` created in `_tp_takedown_atk_start` (`:1807`) has no stop — overlapping crank+takedown montages fight on the same rig.

### 2.4 Takedown / blackjack

- **P0-5a — `base_dmg` is dead; every hit is heavy.** `thief_character.gd:1772-1779`:
```
		var final_dmg: float = heavy_dmg
		var guard_state: int = int(g.get("state"))
		if guard_state == 0 or guard_state == 1:
			var to_player: Vector3 = (global_position - guard_node.global_position).normalized()
			var guard_back: Vector3 = guard_node.global_transform.basis.z.normalized()
			var behind_dot: float = guard_back.dot(to_player)
			if behind_dot > 0.25:
				final_dmg = heavy_dmg
```
Both assignments are `heavy_dmg`; `base_dmg` (`:1760`, `BlackjackDamageLight`) is fetched but never used. The light/heavy distinction does not exist as coded.
- **P0-5b — KO guards not excluded; counter farmable.** Loop (`:1764-1783`) checks distance + `take_knockout` but never `state == 5` (KNOCKED_OUT per `guard_ai.gd:5`); `take_knockout` (`guard_ai.gd:1170-1173`) only KO's when `health <= 0`, and `knock_out` early-returns on already-KO (`guard_ai.gd:1181-1182`: `if state == Alertness.KNOCKED_OUT: return`), yet the thief still runs `GameState.takedowns += 1` (`:1781`) + `NoiseBus.emit_noise(global_position, 4.5, self, "takedown")` (`:1782`) every swing and `return`s. The *finder* used for the prompt does skip KO (`:1298`: `if st is int and int(st) == 5: continue`) — `_try_blackjack` doesn't reuse it. Repeated swings on one sleeping guard inflate score (`hud.gd:1728` consumes `GameState.takedowns`).
- P1 — Prompt/target mismatch; alert guards get the stealth prompt. `get_look_secondary_prompt` (`:1366-1372`): `if _find_nearest_guard(2.4) != null: return "[F] [HOLD] TAKEDOWN"` — any guard in 2.4 m (only KO excluded), and `_perform_hold_action` (`:1378`) re-finds rather than using the prompted guard. Alert/chasing guards get the same stealth takedown prompt and the struck guard may differ from the prompted one.

### 2.5 Tools: smoke / sap / fairy / diamond / crank

- P1 — Smoke: charge-before-spawn. `_use_smoke_bomb` (`:1587-1606`) decrements `charges["smoke_bomb"]` first; if `cam == null` and level lacks `spawn_smoke`, the charge is lost with no cloud. Decrement after successful spawn (or add an else-branch). Detonate split (`smoke_projectile.gd:150-153`) uses `level_ctrl.spawn_smoke(pos, 25.0)` when available else `VfxManager.spawn_smoke_cloud(parent, pos, Vector3(2.5,2.0,2.5), 25.0)` — two tunings for one bomb. Preview (`:2917+`, `v0 = fwd * INITIAL_SPEED_M_S` with `smoke_projectile.gd:12,47`, `INITIAL_SPEED_M_S = 30.0`, bounce 0.064/friction 1.0, RigidBody + continuous CD) is pure ballistic and diverges after the first bounce.
- P1 — Slithersap teleports (design gap, admitted in code): `:1545-1568` plays the throw then immediately `puddle.setup(aim, ...)` at `_slithersap_aim_point()` (raycast to 30 m). No travel delay/arc; the throw anim is cosmetic at 30 m instant placement.
- P1 — Fairy rechecks block with the moved player pos: on arrival (`:1711-1720`) `pickpocket_is_blocked(mark, global_position)` uses the player's *current* pos, not throw-time geometry; walking into view during `fairy_travel_time(dist)` (`:1674`, `dist / 4.5` capped 20 s) converts success into `pickpocket_spotted` noise. Snapshot throw-time position/facing at deploy.
- P2 — Diamond primary is equip-cosmetic: `_use_equipped_primary` vistara branch only `_fp_play_action("vistara_equip")`; vision is an equip side effect. Fine if intentional; confirm HUD doesn't promise an action.
- P1 — Crank economy: 0.5 s crank erases cooldown. `:1065-1070`: `if _crank_elapsed >= WIRE_CRANK_MIN_TIME and ability_cooldown > 0.0: ability_cooldown = maxf(0.0, ability_cooldown - _crank_elapsed)` with `WIRE_CRANK_MIN_TIME = 0.5` (`:43`) vs `WireCooldownSecondary` 5.0. Repeated taps fully offset cooldown without completing a crank; full completion (`:1055-1057`, `ability_cooldown = 0.0` + `+1` charge) is free even at max charges. Decide: partial refund vs full-crank-only reward.

### 2.6 Stamina / health tuning

- P1 — Grapple/astral grant total fall immunity (`thief_character.gd:336-339`): `if is_grappling or astral_active: return 0.0`, plus `_track_fall_state` (`:348+`) refreshes `_fall_peak_y` while grappling/astral so no drop accumulates. Documented intent ("winch controls descent / spirit") but release-at-apex + re-grapple chains never take fall damage.
- P2 — `absf` hides sign errors (`:902`): `absf(GameData.eval_curve("CT_StaminaSystem", "StaminaPerSecond.Sprint", 1.0, -5.0))` turns a future positive regen into drain; assert sign instead.
- P2 — `take_damage` ignores damage while downed (`:1315+`: `if is_downed: return`); post-down hits neither shorten nor extend the timer. Confirm the mission-fail path needs no hit feedback.
- P2 — Revive/full-restore + moth-blocks-fall-back-to-Spider are documented assumptions (unextracted `GE_SetPlayerAttributesAfterRecoverFromDowned`); flag for design sign-off, not a defect.

### 2.7 Movement / step-up

- P1 — Step-up teleports without a landing-pose check (`thief_character.gd:930-939`): the final `test_move(DOWN ...)` only proves a floor *would* be hit, not that the committed `stepped.origin` (lifted 0.3 m + forward 0.35 m) is free/grounded; direct `global_position` write bypasses `velocity`/`floor_snap`. One frame on stairs, but project down to the hit point. Also gated on `is_on_wall()` + `push_dir > 0.05`, so a flickering wall flag on stair noses judders — consider attempting when horizontal velocity was blocked instead. Tuning: `STEP_UP_MAX_M = 0.3` + `FORWARD = 0.35` (`:38-39`) vaults 0.3 m crates vs the `0.6m walls block` comment — generous; confirm stairs-only (0.18-0.2 m) vs crates intended.
- P2 — Stair stack is triple-layered: `floor_max_angle 50°` + `floor_snap 0.3` + manual assist + `floor_block_on_wall` + `floor_constant_speed`. Complementary (snap handles risers, assist fires on wall contact) but test the 0.18/0.2/0.3/0.6 matrix explicitly.
- P2 — Wall-climb ray is single-point (`_tick_wall_climb`, `:1179+`): one ray at +1.1 m forward 0.65 m, `absf(wn.y) > 0.35` reject, needs `wish.dot(-wn) > 0.3 or jump`. Misses overhangs/ledges; consider a head-height second ray.

---

## 3. guard_ai.gd + civilian_npc.gd — sensing, states, animation, binds

### 3.1 Loop integrity

Conscious path order (`guard_ai.gd:984-990` → `:1044-1048`) is intact: regen → cooldown → timers → disguise-viewcone → sight → ... → indicator → alert-emit → ally-wakeup → move → anim. KO branch (`:976-982`) correctly skips everything but freezes `_seconds_in_state`/`_seconds_since_visible`/`attack_cooldown` — the recover path must reset them explicitly (it does `_seconds_in_state` via `_set_state`; see §3.3).
- P2 — `players.back()` (`:988`) senses only the last node in the `player` group. Fine single-player; fragile if a decoy/astral clone ever joins the group.
- P1 — Two independent LOS raycasts per guard per physics tick when the player is disguised: `_update_disguise_viewcone` (own smoke+ray, `:1571-1592`) runs before `_can_see_player` (own smoke+ray, `:1140-1143`). 2× `intersect_ray` per guard per tick + the two systems can disagree (see §3.4).

### 3.2 Sensing

- P1 — `hearing_range` is dead. Declared (`guard_ai.gd:34`: `const HEARING_RANGE: float = 25.0`; `:131`: `@export var hearing_range`) but never read; `_on_noise_emitted` (`:1146-1167`) uses `if global_position.distance_to(origin) <= loudness:` — radius = emitter-supplied loudness, not the 25 m authored value. Difficulty cannot tune hearing via the export; any large-loudness emitter bypasses it. Wire `minf(loudness, hearing_range)` or delete the export.
- P1 — Sight rays ignore bodies. `:1140-1143`: `PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.0, 1, [get_rid()])` — mask `1` = world only; guard bodies (layer 4, `:214-215`) and civilians (layer 8) never block. A line of guards doesn't screen the player. Self is already excluded, so mask `1|2|4|8` is strictly more correct. Same shape in the disguise ray (`:1586`, also excluding the player RID).
- P1 — Retention snaps range and drops the light gate. `:1113-1124`: `var sensed: bool = detection > 0.0 or state != Alertness.NEUTRAL` → `effective_range = lose_sight_range if sensed else sight_range`, and only the fresh branch scales with `LightProbeScript.light_intensity_range_multiplier(...)` (`:1124`). A 1-point blip extends range 20 m → flat 30 m unscaled (comment admits "Godot concept with no UE source") and removes the darkness protection that gated acquisition. With 6 s in-level + 4 s unseen decay gates (`:62-67`), a glimpse holds a 30 m unscaled lock for seconds.
- P1 — Close-range 360° vision + disguise hard-gate interact. `:1133-1135`: `if angle > fov_deg * 0.5 and dist > 3.5: return false` (360° inside 3.5 m, intended) vs `:1111-1112`: `if not guard_alerted and integrity >= 35.0 and dist_to_player > 3.5: return false` (calm + healthy disguise + >3.5 m = invisible even in full light at 4 m head-on). The viewcone-integrity drain still runs while "unseen" — two systems disagreeing about visibility.

### 3.3 State machine

`enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }` (`guard_ai.gd:5`) — `SEARCH(4) > COMBAT(3)`, so every `<`/`>` comparison is suspect (`ALERTNESS_RANK` exists for transitions but the sight/noise paths don't use it).
- **P0-6 — SEARCH can never promote to ALERTED/SUSPICIOUS by sight.** `guard_ai.gd:1011-1021`:
```
		if detection >= DETECTION_COMBAT_AT:
			_enter_combat()
			...
		elif detection >= DETECTION_ALERTED_AT and state < Alertness.ALERTED:
			_enter_alerted()
			state_timer = 6.0
			...
		elif detection >= DETECTION_SUSPICIOUS_AT and state == Alertness.NEUTRAL:
			_set_state(Alertness.SUSPICIOUS)
			state_timer = 5.0
```
`SEARCH(4) < ALERTED(2)` is false and `SEARCH != NEUTRAL`, so a SEARCHing guard staring at the player at detection 15-99 stays SEARCH; only `>= 100 → _enter_combat()` (no state guard) escapes. Dead zone 15-99 → instant combat at 100. Notably the *noise* path (`:1158-1160`, `if state != ALERTED and state != COMBAT: _enter_alerted()`) correctly pulls SEARCH→ALERTED — vision and hearing disagree. Same class at `:1164-1166` (`if state < Alertness.SUSPICIOUS` = only NEUTRAL(0); harmless today, use `== NEUTRAL`).
- P1 — Sticky de-escalation + asymmetric exits. COMBAT exits only via meter ≤ 35 (`:1027-1028`) but the meter only rises while seen — COMBAT→ALERTED→SEARCH→NEUTRAL is ~18 s minimum of no-vision (ALERTED 6 s timer at `:1032-1034`, SEARCH 6 s at `:1040-1042`). SUSPICIOUS exits only at `detection <= 0.0` (`:1036`) — a single footstep (`detection = maxf(detection, 25.0)` at `:1167`) holds SUSPICIOUS ~10 s — while ALERTED/SEARCH are timer-gated. Also `_set_state` resets `_seconds_in_state` (`:818`) but not `state_timer`; every current caller sets it manually, but one missed assignment = stale-timer leak. Move the reset into `_set_state`.
- P1 — KO wake searches its own feet and keeps its pre-KO meter. `_recover_from_ko` (`:1223-1230`) sets `_set_state(SEARCH); state_timer = 6.0; investigate_pos = global_position` — never the attacker position — and `clamped_detection_for_transition` (`:99-105`) deliberately has no SEARCH ceiling, so pre-KO 100 carries into SEARCH (HUD pip shows max suspicion on wake; contrast the revive path clamping to 40 at `:1287`).
- P1 — Ally revive scans one ally, revivers must stay calm, progress can strand. `_update_ally_wakeup` (`:1247-1296`): the `break` at `:1296` is unconditional — only the first KO ally in group order per 0.4 s scan, not the nearest, so a distant KO blocks an adjacent one. ALERTED/COMBAT guards never revive (early return at `:1248`); combined with `guard_alert` noise auto-ALERTing within 14 m, the first alert shuts down all area revives. If the reviver escalates mid-revive the function early-returns before the stale-target reset (`:1297-1303`), stranding `_revive_target/_revive_progress` — reset on state change or in `_set_state`. (The `g.set("ko_timer", 0.0)` + `wake_up_from_ko()` double-drive at `:1282-1284` is redundant but harmless.)

### 3.4 Animation binds

Single-source routing is good (`:490`: `_anim_lib.clip_for_state(_anim_state_name(), _anim_weapon, moving)`) with KO/slip/vic/attack locks (`:475-484`) and foot-slide clamp `[0.35, 1.8]` (`:506-512`).
- P1 — Attacker/victim takedown sync is coincidental, not wired. `play_takedown_vic` (`:411`) has no callers (verified by grep); `thief_character.gd:1759-1782` calls `g.take_knockout(final_dmg)` + `_tp_takedown_atk_start()` but never `play_takedown_vic`. The victim montage still plays because `knock_out()` duplicates it internally (`:1197-1201`), while the attacker montage fires unconditionally on swing (`thief_character.gd:1759`) before the hit test (`:1764-1768`) — attacker plays even on a whiff. Either call `play_takedown_vic` explicitly on hit or delete the dead API and fix the comment at `guard_ai.gd:405-408`.
- P2 — Procedural SEARCH pan fights `look_at`: `_move_ai` rotates the body (`:1089`) while SEARCH rotates `visual_root` ±35° (`:1312-1316`). Bypassed with real clips; visibly disagreeing on fallback art.
- P2 — Civilian anim bootstrap uses the guard table (`civilian_npc.gd:152-153`: `lib.setup("club", _skel)`); works via generic retarget but couples civilians to the guard table. Skipped clips correctly fall back to rest pose + bob (`:208-214`, early-return when `_has_anims` — no double-drive; correct).

### 3.5 Takedown / pickpocket interfaces

- P1 — Pickpocket is free, silent, and works on alert guards. `guard_ai.gd:1560-1565`:
```
func interact(_actor: Node) -> void:
	if carried_item.is_empty():
		return
	if state == Alertness.COMBAT:
		return
	steal_carried_item()
```
Only COMBAT blocks; SUSPICIOUS/ALERTED/SEARCH victims are pickpocketable with no check, cooldown, detection bump, noise, or state change (`steal_carried_item`, `:1484-1507`). The prompt advertises it (`:1551-1557`, `"[F] PICK POCKET"` vs `"[F] LOOT …"` when KO'd). Optimal play today: pickpocket an ALERTED guard's belt mid-hunt. (Per-guard runtime `GDScript` compile in `_rebuild_carried_visual` at `:1521-1535` also deserves a shared script resource — P2 perf hygiene. Double `interactables` membership is safe: both removed after steal at `:1495-1496,1515-1516`.)
- Covered in §2.4: every blackjack hit is heavy + KO hits still count (`thief_character.gd:1760-1783` vs `guard_ai.gd:1170-1173`).

### 3.6 Difficulty tuning

- P1 — ALERTED outruns COMBAT at high difficulty. `_ready` (`guard_ai.gd:231-234`): `_speed_scale = lerpf(0.85, 1.2, ...)` scales `patrol_speed` + `suspicious_speed` + `sight_range` — but never `chase_speed`. Yet ALERTED speed *is* scaled (`get_state_speed`, `:964`: `ALERTED_SPEED * _speed_scale`; duplicated in `_move_ai`, `:1064` vs `:1077` `spd = chase_speed`). At max scale ALERTED = 3.0 m/s > COMBAT = 2.5 m/s: the guard slows down when it catches the player. Scale `chase_speed` in `_ready` or make `_move_ai` call `get_state_speed` instead of duplicating the match. `lose_sight_range` (30 m) is likewise unscaled, compressing the fresh-vs-retention gap unevenly per difficulty.
- P1 — Detection ramps are near-identical; sprint ×8 dominates. `DETECTION_RAMPS` (`:45-50`): NEUTRAL and SUSPICIOUS rows identical, ALERTED/COMBAT only halve `agnostic` 0.4→0.2; crouch ×0.75 only beyond 2.75 m while critical range is 2.0 m instant-spot (`is_inf(rate)` → `detection = 100.0` at `:1006-1007`), so crouch matters in a 0.75 m band. Sprint ×8 (`:75` + `:1002`) dwarfs light (`vis_mult` clamped `[0.35, 1.5]` at `:999`) and height (NEUTRAL-only gate at `:1003-1005`). Movement state decides detection; light/stance barely register.
- P1 — In-combat regen heals chip damage in ~2 s. `_tick_regen` (`guard_ai.gd:800-805`):
```
func _tick_regen(delta: float) -> void:
	if state == Alertness.KNOCKED_OUT:
		return
	var cap: float = _guard_max_hp()
	if health < cap:
		health = minf(cap, health + _guard_regen_rate() * delta)
```
`GuardBaseHealthRegenRate 15/s` vs `GuardBaseHealth 30` (`:777-784`) → 0→full in 2 s, in every conscious state including COMBAT, called every physics tick (`:984`). Non-lethal hits mid-fight evaporate; combined with health-gated `take_knockout` this makes chip damage meaningless. Gate regen to non-COMBAT or add a damage-blackout timer. (`MELEE_DAMAGE 10 / COOLDOWN 2.0 / RADIUS 1.0` at `:36-38` are unscaled consts — correct per UE comments, but then `_speed_scale` is the *only* difficulty lever on this file.)

### 3.7 Civilians

- **P0-8 — Civilians wander once, then idle forever.** `_pick_new_target` is called only in `_ready` (`civilian_npc.gd:59-60`); the physics loop (`:186-196`):
```
	if _idle_ttl > 0.0:
		_idle_ttl -= delta
		...
	else:
		var to: Vector3 = _target - global_position
		to.y = 0.0
		if to.length() < ARRIVE_DIST_M:
			_idle_ttl = randf_range(IDLE_MIN_S, IDLE_MAX_S)
```
After reaching the first target, arrival re-arms `_idle_ttl`; on expiry the guard falls through to the *same already-reached* `_target` and re-arms idle. No second destination is ever picked (fix: call `_pick_new_target()` when idle expires). Secondary: target is `wander_center ± 6 m` with no navmesh/raycast validation and no stuck timeout (`_pick_new_target` at `:228-233`); `move_and_slide` with `collision_mask = 1` (world only, `:57-58`) slides along walls but never repicks — a target inside geometry = permanent walk-into-wall.
- P2 (by design, recorded) — `civilian_npc.gd:7-11` documents no detection/interaction/collision: no cower/flee on `guard_alert` or nearby COMBAT; `collision_layer = 8, mask = 1` (`:56-58`) means player and guards phase through civilians; two clips only (`:31-32`, female variants reuse male). Acceptable with the rest-pose+bob fallback; flagging so tuning owns the decision.

---

## 4. interact/ (all 9) — prompts, takedown/pickpocket/loot/doors

- **Covered as P0-5b:** `_try_blackjack` doesn't skip KO while the prompt finder does (`thief_character.gd:1298` vs `:1743-1783`).
- **Covered as P0-7:** gate-vs-objective loot threshold split (`escape_gate.gd:75` vs `game_state.gd:26` + `loot_goal`).
- P1 — Clue items re-fire noise + toast on every press. `clue_item.gd:69-72`:
```
func interact(actor: Node) -> void:
	collected = true
	clue_collected.emit(clue_title, clue_body)
	NoiseBus.emit_noise(global_position, 1.5, actor, 'clue')
```
No once-guard, never removed from `interactables`, never freed; prompt flips to `"[Read]"` (`:83-86`). Each re-press re-emits 1.5 m noise (guards re-investigate) and re-fires the HUD toast (`mission_controller.gd:1231-1232`).
- P1 — Door/container lockpicking emits player-caused noise with a non-player source, so HUD arcs never flash. All door/container noises pass `self` (`lockable_door.gd:252,265,274,289,315`; `loot_container.gd:255,277,287`; `swinging_door.gd:288,293,312,322,331`), e.g. `NoiseBus.emit_noise(global_position, 4.0, self, "lockpick")` (`lockable_door.gd:265`), but `hud.gd:2868-2869`: `if source != null and not source.is_in_group("player"): return` — only player-sourced noise drives the soundwave arcs. Correct emitters pass the player (`thrown_bottle.gd:77` `thrower`, `thief_character.gd:1782` `self`, `clue_item.gd:72` `actor`). Net: guards hear lockpicking, the player gets zero UI feedback they are audible.
- P2 — `"lock"` noise tag has no audio mirror. Relock emits `NoiseBus.emit_noise(global_position, 3.0, self, "lock")` (`lockable_door.gd:315`, `swinging_door.gd:234`); `_resolve_tag` (`audio_manager.gd:886-911`) has no `"lock"` arm and `_sfx` has no `"lock"` key (`:205-213`) → `""` → silent skip. Guards still hear it (distance check is tag-agnostic); audio-only.
- P2 — Relocking a swinging door downgrades its lock to Lv1 (`swinging_door.gd:229-233`: `set_locked(true, 1)`) vs `lockable_door.gd:308-315` which keeps `lock_level`.
- P2 — Containers accept lock levels 1-6 (`loot_container.gd:262`: `clampi(maxi(lock_level, 1), 1, 6)`; `set_locked` `:152-157` clamps 1..6) but the jam table tops out at 4 (`lockable_door.gd:44` `FALLBACK_MAX_LOCK_LEVEL`, jam `5/10/20/40`; `jam_damage_for_level` clamps 1..4 at `:60`). Lv5-6 containers get Lv4 jam economics with no table row.
- P2 — `loot_item.gd` has no `get_interact_prompt` (defines `interact` at `:201` + highlight only); the player falls back to the `item_name` branch (`thief_character.gd:1357-1359`: `return "[E] Steal %s"`). Quest loot reads "Steal …"; any future interactable without `item_name` degrades to `"[E] Interact"`.

---

## 5. Spawners

- P1 — Deterministic bucket hash duplicated in two files with only a comment keeping them in sync ("Same formula as mission_controller._loot_bucket_index so both waves agree"): `loot_container.gd:56-61` vs `mission_controller.gd:1637-1643`. One future tweak desyncs container loot from world loot — make it one shared static.
- Verified sound: `_spawn_pickups` (`mission_controller.gd:1911-1923`) and `_spawn_civilians` (`:1926-1938`) are type-guarded, mesh-empty guarded (`:1913-1914`; fallbacks hardcoded in `_load_spawner_tables`, `:1862-1873`), civilian modulo zero-division guarded (`:1931` ternary). Trigger-only Area3Ds, distance-culled (`world_pickup.gd:20,73-78`). `level_loader.gd:1249-1264` appends loot markers to both legacy `loot_spawns` and typed major/minor arrays; the consumer (`mission_controller.gd:1606-1621`) prefers typed and falls back only when both are empty — no double-spawn.

---

## 6. Save / progression

Covered in §1.9: write path clean (atomic tmp-rename, XP `maxi(100, score/2)`, level re-derived, `_ensure_defaults` backfill). Gaps are P1 (fail/timeout persist nothing; run state never persisted — mid-run quit loses loot, currency/XP land only at `_on_extracted`) and P2 (wardrobe cursor asymmetry; `is_hub` order-vs-map_id split). Per-node states (container `opened`, loot `collected`, door open/locked, clue `collected`) are node metas — new run respawns everything, consistent with a roguelite loop but sharing the single hardcoded gate count (§1.3/P0-7) across every contract.

---

## 7. Stealth — NoiseBus, light gem

- NoiseBus integrity is sound by design: pure relay (`noise_bus.gd:26`: `noise_emitted.emit(origin, loudness_meters, source, tag)`) — no validation/falloff/occlusion; all spatial logic lives in listeners, consistently `distance <= loudness` (`guard_ai.gd:1160,1165`). Self-hearing excluded (`guard_ai.gd:1147`), astral-moth muted (`:1152-1153`), `guard_alert` escalates straight to ALERTED (`:1154-1160`), audio mirror skips `footstep` to avoid doubling (`audio_manager.gd:924-927`). Two notes (P2): blocked-pickpocket noise uses a dynamic radius `distance_to(mark) + 2.0` (`thief_character.gd:1699`) — the farther the mark, the louder the failure; `thrown_bottle.gd:67` 6 s failsafe calls `_impact()` even mid-air (acceptable).
- Light-gem chain coherent: sample → `GameState.player_light_visibility = light_probe.sample_visibility(...)` (`thief_character.gd:999`, self excluded at `:998`); guard reads `max(sampled, movement floor)` (`guard_ai.gd:948-955`); sight scaled by `light_intensity_range_multiplier` 0.15–1.0 (`guard_ai.gd:1124`); gem lerps to clamped value (`hud.gd:2161-2162`). Invalidation correct (`light_probe.gd:74,77-81,131`). P2 wrinkle: sample *cache* runs on `Time.get_ticks_msec` wall-clock (`light_probe.gd:125-127`) while light state runs on run-time — pause expires the cache harmlessly (recompute on resume).
- The stealth-relevant *gaps* are the P1s in §3.2/§3.6: dead `hearing_range`, body-transparent sight rays, retention dropping the light gate, disguise unseen-but-draining, sprint-×8 dwarfing light/crouch.

---

## Ranked issue list

### P0 — broken loop (8)

| # | Issue | Evidence |
|---|-------|----------|
| P0-1 | Prep mission picker decorative; deploy drops the mission choice | `mission_prep_ui.gd:151` emits `(map_id, difficulty, mode, contract_order)` with no mission id → `mission_controller.gd:1132-1134` `reset_run(order_id, map_id)` → `:1150-1153` `matching[absi(order) % matching.size()]` |
| P0-2 | Co-op mode selected in table/prep never reaches GameState | Only writer `mission_controller.gd:726` (Den R-toggle); table local `coop_mode` (`contract_table_ui.gd:23,504-507`) emitted in `mission_selected` (`:517,544`, zero listeners); deploy closure takes `(order_id, map_id)` only |
| P0-3 | Mission clue + loading clue always generic fallback (wrong key) | `mission_controller.gd:1222` `contract_info.get("clue", "Locate the target vault…")` + `:147` `contract_info.get("clue", "")` vs `game_data.gd:389` `base["clue_facts"] = clues`; zero `"clue"` writers in game_data |
| P0-4 | Den F-action undiscoverable from the Den card (wrong key) | Card sends `"hints"` (`mission_controller.gd:930,966-970,981`) but `hud.gd:1840-1871` renders only `lines/difficulty/mode/prompt/bottom_hints` — F row dropped |
| P0-5 | Blackjack always-heavy + KO farmable counter | `thief_character.gd:1772-1779` both branches assign `heavy_dmg` (`base_dmg` at `:1760` never used); loop `:1764-1783` never skips state 5 while `GameState.takedowns += 1` (`:1781`) + noise (`:1782`) fire every swing; `knock_out` early-returns on KO (`guard_ai.gd:1181-1182`) |
| P0-6 | SEARCH guards can't promote by sight (enum-order dead zone 15-99) | `guard_ai.gd:1016` `state < Alertness.ALERTED` false for SEARCH(4); `:1020` `state == NEUTRAL` false for SEARCH — only `:1011` `>= 100 → combat` escapes; noise path `:1158-1160` correctly re-alerts, so vision/hearing disagree |
| P0-7 | Escape gate uses stale `loot_needed = 5`, not the mission `loot_goal` | `escape_gate.gd:75` `loot_collected >= GameState.loot_needed` vs `game_state.gd:26` `var loot_needed: int = 5` (never assigned; `reset_run` `:47-62` doesn't touch it) vs Cleanout `loot_goal = 1000 × difficulty` (`mission_controller.gd:1186`) |
| P0-8 | Civilians wander once then idle forever | `_pick_new_target` only in `_ready` (`civilian_npc.gd:59-60`); arrival re-arms `_idle_ttl` (`:186-196`) onto the same reached `_target`; no validation/stuck-timeout (`:228-233`, mask world-only `:57-58`) |

### P1 — weak loop (14)

1. Pickpocket free/silent on SUSPICIOUS/ALERTED/SEARCH victims — `guard_ai.gd:1560-1565` only COMBAT blocks; `steal_carried_item` (`:1484-1507`) bumps nothing.
2. ALERTED outruns COMBAT at high difficulty (`chase_speed` unscaled) — `guard_ai.gd:231-234` vs `:964`/`1064`/`1077`; `lose_sight_range` also unscaled.
3. In-combat regen 15/s heals 0→full in ~2 s — `guard_ai.gd:800-805` + `:777-784`, called every conscious tick (`:984`).
4. `hearing_range` (25 m) dead; hearing radius = emitter loudness — `guard_ai.gd:34,131` never read; `:1162,1165` use `loudness`.
5. Sight rays ignore bodies (mask 1, world-only) — `guard_ai.gd:1140-1143` (+ disguise ray `:1586`).
6. Retention snaps 20 m→30 m and drops the light gate on any blip — `guard_ai.gd:1113-1124`; decay gates `:62-67`.
7. Disguise hard-gate (>3.5 m + integrity ≥ 35 = invisible at 4 m in full light) while drain still runs — `guard_ai.gd:1111-1112` vs `:1571-1592`; 360° inside 3.5 m (`:1133-1135`).
8. Detection ramps near-identical; sprint ×8 dwarfs light/crouch — `guard_ai.gd:45-50,75,999,1002-1007`.
9. KO wake searches own feet, keeps pre-KO 100 — `guard_ai.gd:1223-1230` vs `:99-105` (no SEARCH ceiling) vs revive clamp `:1287`.
10. Ally revive: first-in-group only (`break` at `:1296`), ALERTED/COMBAT never revive (`:1248`), progress strands on escalation (reset at `:1297-1303` skipped by early return).
11. Door/container lockpick noise sourced `self` → HUD arcs never flash — `lockable_door.gd:252,265,274,289,315` etc. vs `hud.gd:2868-2869` player-only gate.
12. Clue re-fires toast + 1.5 m noise every press — `clue_item.gd:69-72`, prompt `:83-86`, HUD hook `mission_controller.gd:1231-1232`.
13. Contract→mission positional link; `mission_selected`/`objective_completed` emitted to nobody; fail/timeout persist nothing; timer runs during letter/minigame; smoke TTL visual desync; Jaspering Hall undeployable-from-Den-preview; guard count flat Novice→Thief — `mission_controller.gd:1150-1153`, `contract_table_ui.gd:517,544`, `game_state.gd:112,219`, `mission_controller.gd:2011-2012` vs `:2024-2041`, `:1205-1216`, `:1978-2000`, `:606-663`/`710-711`, `:1441`.
14. Thief-side: crank-on-wall-climb + no astral cleanup + fire/release sharing `primary_action` + mantle skipping regen/drain/probe/hold + fairy arrival recheck on moved pos + no SceneTree-cancel + smoke charge-before-spawn + sap instant-30 m + crank 0.5 s trickle refund + fall immunity + `tool_used` gaps (blackjack/disguise/astral) + viewcone call-order guard — `thief_character.gd:1011,1046,1179-1205,1453-1457,861-881,336-339,846-857,866-872,1378,1587-1606,1545-1568,1065-1070,1058,1275,983-994,1707-1725`.

### P2 — polish (12)

1. Rain snap runs on result screens (`mission_controller.gd:2003-2004`).
2. Table highlights wrong row (never sets `selected_order`) — `mission_controller.gd:1126-1129` vs `contract_table_ui.gd:20`.
3. Timeout reason travels but panel recomputes — `mission_controller.gd:2038-2039` vs `hud.gd:1718-1719`.
4. Gaze selection bypasses `set_den_selected_map` — `mission_controller.gd:955-957` vs `:710-717`.
5. Escape spawn not floor-grounded — `mission_controller.gd:1842-1849`.
6. Wardrobe mouse-restore asymmetry — `mission_controller.gd:1054-1058` vs `:1060-1074`.
7. `is_hub` (order) vs `_is_thieves_den` (map_id) split — `hud.gd:633,828,961,2071` vs controller.
8. `"lock"` tag has no audio mirror — `lockable_door.gd:315`, `swinging_door.gd:234` vs `audio_manager.gd:886-911,205-213`.
9. Swinging-door relock downgrades to Lv1 — `swinging_door.gd:229-233` vs `lockable_door.gd:308-315`.
10. Container locks 1-6 vs jam table 1-4 — `loot_container.gd:262,152-157` vs `lockable_door.gd:44,60`.
11. `loot_item.gd` has no `get_interact_prompt` (falls back to `"[E] Steal %s"` at `thief_character.gd:1357-1359`).
12. Thief/GC hygiene: smoke preview raycasts in `_process` (`:2891`, 32/frame); per-tick `stamina_changed`/`disguise_changed` (`:906,980-993`); two-clock hold (`:522` vs `:1002-1006`); no-hysteresis sprint (`:890-894` + FOV `:909-910`); downed doesn't clear grapple (`:814-825` vs `:400`); no revive signal (`:423-433` vs `:402,409-414`); dual vision vars; anim fallback asymmetry (`:2321-2323` vs `:1030,1035`); `TPTakedownPlayer` never stopped (`:1807` vs `:2428`); `_end_astral` guard reads inverted (`:1477-1482`); `players.back()` single-target (`guard_ai.gd:988`); per-guard runtime GDScript compile (`guard_ai.gd:1521-1535`); SEARCH pan vs `look_at` (`:1089` vs `:1312-1316`); civilian guard-table coupling (`civilian_npc.gd:152-153`); bucket-hash duplication (`loot_container.gd:56-61` vs `mission_controller.gd:1637-1643`); wall-clock light cache (`light_probe.gd:125-127`); dynamic pickpocket-fail radius (`thief_character.gd:1699`); bottle failsafe mid-air impact (`thrown_bottle.gd:67`).

---

## Suggested fix order (if a follow-up is authorized)

1. P0-5 (blackjack skip-KO + use `base_dmg` + count only actual KOs), P0-7 (gate on `loot_goal`/objectives).
2. P0-6 (rank-based sight promotion), P0-8 (repick on idle expiry + stuck timeout).
3. P0-1/P0-2 (pass mission id + mode through deploy), P0-3 (`clue_facts` key), P0-4 (render `hints` or send `prompt`/`bottom_hints`).
4. P1 pickpocket awareness handoff, chase-speed scaling, regen gating, hearing-range wiring, revive scan/strand fixes.
5. P1 thief-side: crank guards, astral cleanup, fairy snapshot + cancel, smoke decrement-after-spawn.

*Assumptions recorded: single player in `player` group; UE numbers taken at face value from file comments; civilian passivity is design (per `civilian_npc.gd:7-11` header); Moth-blocks-fall-back-to-Spider, revive-full-HP, sap-instant-placement are documented port assumptions; `guard_ai`/`thief`/`vfx`/`level_loader`/`weather` internals beyond cited call sites were traced through call sites only.*
