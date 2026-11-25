# W9-P2 B3 — behaviour fact sheet

Read-only investigation (no edits, no Godot). Key facts and `file:line`; the
lane's three decisions and tests are in `b3-impl.md` / p2-report §B3.

## A. Telescope `[F] EXIT` / Den roof (L4-13)

- The ponder toggle is camera-only: `mission_controller.gd:2266-2343` writes
  `_ponder_cam.global_position` (`:2309`), camera current/cull mask
  (`:2319`, `:2334-2335`), the vista, LUT and wind bed. It never writes the
  player. `grep "global_position\\s*=" mission_controller.gd` has exactly one
  write, the ponder camera.
- Telescope area: `_den_telescope_pos` (`:99`, overwritten to the floor anchor
  at `:1271`), area created `:1272-1296` at (-4.9202, 40.25511, 270.7337),
  1.14 m inboard of the measured west opening (wall plane x=-6.06, z
  270.4–272.4, sill y=41.0, top y=45.1; `:108-113`).
- The 0.745 m sill is inside `try_auto_mantle`'s 0.45–4.0 m band
  (`thief_character.gd:1529-1530, 2136, 2152`); the Den `volumes` array is
  empty and `SM_ThievesDen_Glass` had no collision before P1's `7939a61`, so
  the recorded run's post-exit walk mantled out.
- On the current HEAD the authored glass/shell collision stops the walk
  (x≈-5.26); the RED does not reproduce. The blocker is defense-in-depth.
- Existing coverage: E2E T1-17-E only asserts the PONDER prompt exists
  (`e2e_tier1_features.gd:1652-1660`); W5C tests are pure functions
  (`run_tests.gd:858-902`); `build/qa/probe_telescope.gd` enters but never
  exits; no committed run exercises `[F] EXIT`.

## B. Jam damage (L4-01)

- Authored `CT_LockpickDamage.DamageByLockLevel` = 5/10/20/40
  (`extracted/json/Gameplay/Tuning/CT_LockpickDamage.json:10-28`), produced
  1:1 into `interactables.json` (`jam_damage_by_lock_level`, delay 0.5 s).
- The only production applier is `hud.gd:3252-3267` (`p.call("take_damage",
  dmg)`); the door/container false callbacks (`swinging_door.gd:420-445`,
  `lockable_door.gd:253-272`, `loot_container.gd:334-351`) never damage, and
  the no-HUD timed fallbacks do not either. No double-hit exists.
- Player `max_health` 300 (`thief_character.gd:244-245`), no armour/regen;
  bar reveals at hp_frac < 0.999 (`hud.gd:2760`); splatter < 0.5.
- Four LV3 jams = 80 → 220/300 = 73.3 %, matching the record's ~75 % first
  reveal; the 38 % end state needs ~8–9 jams (not fully closed).
- Tests: T1-19-E (table values), T2-15-B (JSON/source strings), T3-13
  (`take_damage` directly), T05.H9-H11 (splatter), but **no test of the HUD
  strike path or the no-pause/reveal semantics**.

## C. Magic-door continuity

- `escape_gate.gd` states: dormant (`:41-53`), `activate` (`:113-130`),
  `expire` (`:135-143`), `collapse` terminal (`:148-158`), `is_available`
  (`:161-162`), extraction gate (`:173-188`: group player, state playing,
  available, phase endgame `:183`, objectives complete `:185`).
- `mission_controller._start_endgame` (`:4497-4519`) summons every marker;
  `_process` endgame tick calls `_rearm_escape_gates` (`:4430-4440,
  :4468-4494`); `_on_escape_gate_extracted` rejects non-endgame/expired
  (`:4531-4539`); `_on_door_collapsed` collapses all and resolves
  (`:4605-4620`).
- Tests S5.3–S5.11 cover phases, dormant/main, the 240 s cycle, the re-arm at
  t=1001, collapse; they call `_on_body_entered` directly, so real Area3D
  overlap, post-resolution blocking and incomplete-objectives-with-endgame
  are unasserted.
- Decision: keep continuous (T10/R10 port decision: the 240 s authored cycle
  is re-armable inside the 1200 s endgame); no production change.
