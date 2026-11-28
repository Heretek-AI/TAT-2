> **SUPERSEDED — see [docs/HANDOFF_NEXT_AGENT.md](HANDOFF_NEXT_AGENT.md).**

# TAT-2 — Handoff to OpenCode (2026-11-18 11:02 EST)

Continue the **visual fidelity + gameplay mechanics parity wave** started in Antigravity. Read `docs/HANDOFF_NEXT_SESSION.md` first for repo conventions, verification commands, hard limits and QA recipes; this file only covers what changed since then.

## Goal (approved task prompt)
Full-game 1:1 Godot rebuild of Thick As Thieves, **desktop Linux / Vulkan Forward+ only**. Close the highest-impact visual-fidelity and gameplay-mechanics gaps visible in the 56 Steam reference screenshots:
`$HOME/.local/share/Steam/userdata/397775346/760/remote/3341000/screenshots/*.jpg`

Acceptance:
- [ ] `make test` → `SUMMARY: fails=0`, zero `SCRIPT ERROR`
- [ ] `make audit` → no regression from `12,630 / 12,704 (99.4%)`
- [ ] Live Vulkan Forward+ captures: `SHADER ERROR = 0`, `SCRIPT ERROR = 0`, compared side by side with the Steam screenshots and the results written up
- [ ] No invented cooked-data parameters (Niagara VM, cooked material graphs, patrol splines, etc.); keep hard limits documented

## Where the plan and research live (gitignored, `build/handoff/`)
- `build/handoff/teamwork_state/PROJECT.md` — **master plan**: architecture, R3 hard limits, the 22-feature inventory (#1–#22), milestones M1–M5, file ownership, and **the M2↔M3↔M4 interface contracts** (read lines 73–96).
- `build/handoff/teamwork_state/teamwork_explorer_survey_2/handoff.md` — 18 visual gaps mapped to specific screenshots and code lines (HUD/UI gaps are in the second half).
- `build/handoff/teamwork_state/teamwork_spec_miner_survey_1/handoff.md` — spec/doc mining, hard limits table, verification workflow.
- `build/handoff/teamwork_state/teamwork_spec_miner_e2e_r1_2/handoff.md` — mapping of all 56 Steam screenshots to scenes.
- `build/handoff/teamwork_state/teamwork_explorer_m1_*/`, `teamwork_explorer_m2_r1_*/`, `teamwork_spec_miner_m2_r1_3/` — per-milestone implementation blueprints.
- `build/handoff/teamwork_state/TEST_INFRA.md` + `teamwork_test_writer_e2e_vulkan_r1_1/handoff.md` — E2E/Vulkan parity test design (21 captures S01–S16+).
- `build/handoff/wave1_wave2_partial.patch` + `untracked.tgz` — snapshot of the whole working tree at handoff time (restore with `git apply` + `tar xzf` if anything gets clobbered).
- `build/handoff/check_m4_oldmanor.gd` — M4's in-progress OldManor terrain walk/collision probe (it was originally in `/tmp`).

## Status by milestone

Nothing is committed yet. Everything is uncommitted in the working tree on `main` (26 modified files, +6,451/−1,087, plus 3 untracked paths).

| Milestone | Features | Status |
|---|---|---|
| **M1** Atmosphere, lighting, shaders, 3D shell stages | #1–#6 | ✅ **Done.** Isolated headless check: `fails=0`. |
| **M2** 1P viewmodel, tool equip, ballistics, traversal, disguise | #7–#12 | ✅ **Done.** `test_m2_player.gd` `fails=0`; live Vulkan capture had 0 shader/script errors. |
| **Wave 1 gate** (M1+M2 combined) | — | ✅ `make test` `SUMMARY: fails=0`, exit 0 (10:32). M2 also reported `make audit` 99.4%. |
| **E2E track** | #22 (part) | ⚠️ **Partly done.** Scripts in `game/tests/e2e/` (`run_e2e_tests.gd`, helpers, tier1–4, 256 checks); the headless run result was never confirmed. The Vulkan parity capture (`build/qa/capture_e2e_parity.gd`) had 21 captures with 0 errors, but that was **before M1 and M2 landed**. `TEST_READY.md` was never written. |
| **M3** HUD, shell UI, map/ping, lockpicking UI | #13–#16 | ⚠️ **Partly done, unverified.** The worker hit quota partway through. `hud.gd` has +2,998 lines; `art_nouveau_theme.gd`, `wardrobe_ui.gd`, `contract_table_ui.gd`, `ledger_ui.gd`, `loading_screen.gd`, the 2D cards in `mission_prep_ui.gd` and `project.godot` (input actions) are edited. |
| **M4** Missions, doors/safes, guards, Den hub, OldManor terrain | #17–#21 | ⚠️ **Partly done, unverified.** The worker hit quota partway through. Edited: `mission_controller.gd` (+445), `game_state.gd`, `guard_ai.gd` (+254), `swinging_door.gd`, `loot_container.gd`, `lockable_door.gd`. The OldManor probe has not been run. |
| **M5** Final E2E, live Vulkan parity vs Steam, hardening | #22 | ❌ Not started. |

## M1 changes (done)
- `tat_sky.gdshader`: `sky_radiance_scale` (decoupled from UE's `0.001` pre-exposure; suite 22 helpers untouched), FBM cloud wisps, moon halo, cloud-attenuated stars.
- `tat_landscape.gdshader`: puddle normal depth, roughness `0.04`, wet specular `0.85`.
- `tat_glass.gdshader`: `depth_draw_never`, `translucent_color`, Fresnel transmission.
- `tat_hdr_emissive.gdshader`: `hdr_boost`, Fresnel, flicker (suite 37's `hdr_color`/`hdr_scale` kept).
- `weather_profile.gd` / `weather_visuals.gd`: fog radiance compensation; desktop-only volumetric fog, SSIL, shadow-toe LUT from `gain_shadows`, screen-blend bloom and SSR.
- `level_loader.gd`: `.scaled()`→`.scaled_local()` (fixes the Startscreen floor protrusion), filters `SM_FogSphere`, foliage alpha-scissor/backlight, exempts canopies from clutter culling, candle wick offsets, `LumenSkylightLeaking` → shadowless fill lights, `LocalExposure*` → colour correction.
- `vfx_manager.gd`: teardrop billboard candle flame, softer godray, yellow-gold outline in `set_prop_highlight`.
- `main_menu.gd`: wires `BeautifulCorner_Startscreen_Lighting`, removes the invented magenta glow, adds volumetric mist and headlights, a glowing streetlamp bulb, and an idle Constable (`SK_GuardEnforcer__Preview` + `AN_GuardEnforcer_NeutralFresh_Idle`).
- `mission_prep_ui.gd` (3D stage): real `MissionLobby_Geo3` + `_Periphery`, `midnight_clear_mission_lobby`, `CameraActor_0` (vFOV 11.33°, roll −14.78°), ThiefNisha idle.
- **Not visually verified yet:** MissionLobby roll sign, ThiefNisha foot contact (`y=0.82`), Constable facing, and the sky/neon/SSR/godray/glass tuning compared with the Steam shots.

## M2 changes (done)
- `tools/parse_gameplay.py` (regenerated `game/data/generated/gameplay/`): mantle 4.0 m / 25°; wall-climb 2.5 m/s; `CT_WireCrank` 6.0 s with 0.5 s minimum; SmokeBomb 30 m/s, bounciness 0.064, 0.5 s.
- `animation_library.gd`: similarity retarget for 1P, lazy `FP_TOOL_CLIPS` (`ensure_fp_clip`, `has_fp_role`, `fp_clip_for_role`).
- `smoke_projectile.gd` (new): `RigidBody3D` ballistic projectile with the real `SM_Bomb_Smoke.glb` and PBR.
- `thief_character.gd`: real 1P arms and 6 tool GLBs with PBR; viewmodel FOV 85 with depth remap; `[1]`–`[4]` equip plus LMB/RMB; Vistara Diamond ThiefVision; Zipwire target validation, persistent cable and RMB crank; auto-mantle; wall-climb; smoke trajectory arc; disguise drain rows `Lockpicking 5/s` and `GuardViewCone 10/s @10 m/65°`.
- **M2 contract API** (used by M3 and M4): `get_equipped_tool()`, `get_tool_slots()`, `get_active_reticle_state()`, `is_thief_vision_active()`, `set_lockpicking_active(bool)`, `apply_guard_viewcone_disguise_decay(delta, in_cone)`, signal `tool_equipped`.
- `game/tests/test_m2_player.gd`: 9 checks. Run: `flatpak run org.godotengine.Godot --headless --path game --script res://tests/test_m2_player.gd`

## M3 / M4 contracts the partial code should satisfy (check them)
- `hud.gd`: `start_lockpick_minigame(lock_level, label, on_complete: Callable)`, `is_lockpicking()`, `show_mission_letter(title, intro)`, `is_mission_letter_open()`, `set_den_lookat_card(card: Dictionary)`. Must **keep** `obj_lbl`, `compass_lbl`, `stealth_gem`, `hp_fill`, `stam_fill`, `hotbar_lbl`, `slot_count_lbls`.
- `loading_screen.gd`: keep `start_loading`, `set_progress`, `finish_loading`.
- `game_state.gd`: `mission_objectives` (`id, label, done, current, target`), `loot_value`, `loot_goal`, `contract_intro`, `contract_title`, signals `objectives_updated` and `mission_letter_requested(title, intro)`, `request_mission_letter()`, `set_mission_objectives()`, `update_objective_progress()`.
- `guard_ai.gd`: `get_alert_state()` → `{state, suspicion, world_pos, alerted, combat}`; ClubLantern `OmniLight3D` registered with `light_probe`; `carried_item`, `has_carried_item()`, `steal_carried_item()`; GuardViewCone → `player.apply_guard_viewcone_disguise_decay(delta, true)`.
- Doors and containers: `lock_level`; call `hud.start_lockpick_minigame` when available, otherwise a timed fallback (for headless runs); always toggle `player.set_lockpicking_active`.
- `mission_controller.gd`: remove the Den `Label3D` billboards (check suites 34/34b/34d first), look-at cards (`[H]` difficulty, `[R]` mode, `[F]` prepare, `[F] PONDER` telescope), `get_den_lookat_card()`, golden highlight on the active token (**keep scale `0.24` and the seated Y**), Set objectives (`[0/3]`) and the Cleanout loot threshold, mission letter on start.

## Next steps (in order)
1. **Triage the partial Wave 2 code.** Run `make test 2>&1 | tee /tmp/t.log; grep -E "SUMMARY|SCRIPT ERROR|Parse Error|FAIL" /tmp/t.log`. No `make test` has been run on the partial Wave 2 code yet; the 11:01 attempt never started. Fix parse errors first: the edits may be truncated mid-function in `hud.gd`, `mission_controller.gd` and the others. Check that every contract above exists and actually works.
2. **Finish M3** (#13–#16). Specs: `PROJECT.md` rows 13–16; survey_2 handoff, HUD section. Assets: `game/assets/ue/Raw/Art/UI/HUD/`.
3. **Finish M4** (#17–#21) and run `build/handoff/check_m4_oldmanor.gd` headless with `timeout`.
4. **Gate:** `make test` (`fails=0`, zero SCRIPT ERROR), `make audit` (≥99.4%), `test_m2_player.gd`, `game/tests/e2e/run_e2e_tests.gd`.
5. **M5 live Vulkan:** `bash build/qa/capture_vf.sh`, `bash build/qa/capture_mp_only.sh`, and the E2E parity capture (`build/qa/capture_e2e_parity.*`). Check `SHADER ERROR = 0` and `SCRIPT ERROR = 0`. Open each PNG next to the matching Steam JPG and tune. Record the results in a new `docs/reports/fidelity-mechanics-wave.md`.
6. Update `docs/HANDOFF_NEXT_SESSION.md` and `docs/FIDELITY_GAPS.md`. Commit in logical Conventional Commits (M1, M2, M3, M4, tests and docs as separate commits). Do not commit `build/`, `game/.godot/`, `game/data/generated/` or `extension_api.json`.

## Gotchas
- Godot 4.7: no `:=` on untyped Dictionary/Variant values; never write `bool(obj.get(...))` (use `== true`).
- Headless `make test` does **not** compile shaders; shader changes need a Vulkan run.
- Never run two mission-load Godot processes at the same time (they are CPU-heavy). Always use `timeout` and redirect output to a file.
- Do not edit `game/tests/run_tests.gd` assertions to make tests pass; fix the code.
- Do not leave `[tat2] debug_autostart_contract` in `project.godot`.

## Side task (separate, optional)
Create a standalone generic UE5 extractor repo at `~/Projects/ue5-linux-extract` from `tools/tat-extract`, `tools/ue4ss` and `tools/usd_to_gltf.py`. The plan is in `build/handoff/standalone_extractor_plan.md`. **Do not modify TAT-2 for this.**
