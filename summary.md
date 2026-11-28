# route-code — headless played-route instruments (Phase 3C)

Built the four missing instruments on branch `teamwork/20261127-1810-phase3-route-code`
(base `6773977`). `build/qa/route_driver.gd` + `route_driver.sh` is a deterministic
headless input driver (movement via `Input.action_press`, look via the player's
`add_look_pixel_delta` hook, interact via a real `KEY_F` event pushed through the
SceneTree, waits on physics frames; no `player.global_position` writes). Its only
implemented segment is `den_telescope`: S03 authored Den arrival (`driven_partial`,
mark_beat) and S05 walk to the telescope, `[F] PONDER`, 40-frame held-forward freeze,
`[F] EXIT`, camera restore, in-Den assertion, then a 4.89 m walk-away. Two runs of
seed `1025051536` produced identical evidence (151-frame / 8.8401 m approach, same
exit position); `ROUTE_DRIVER_DONE status=partial_driven beats=27 driven=1
partial=1 unreachable=4 not_attempted=21 mark_calls=2 checks=12 fails=0
route_claim=none`, manifest `git.dirty=false` at `da780d4`. `build/qa/p0b_route_stats.py`
binds all 120 matrix rows to the official beats, self-tests against
`row_route_matrix.md` (37/31/27/25 pillars, 43/21/56 tally) and emits zero tokens
unless `route_claim=played` (15/0). L4-13 is fixed in `mission_controller.gd`:
the scope pushes an `InputContext` `telescope_ponder` modal, zeroes body velocity
on entry, pops on exit/teardown; `probe_den_window.gd` now drives real-key
`[F] PONDER`/`[F] EXIT` and passes 44/0 with `0.0000 m` scope drift and the body
still inside the Den. `probe_route_npcs.gd` re-measures the 4 guards + 3 civilians
at **85.4–150.7 m** from the Contract 2 spawn (nearest 85.4 m, 0 in a 30 m radius),
so S19/S20/S22/S23 are recorded `unreachable`. Gates: compile 234/0, `run_tests`
329/0, driver 12/0, scorer 15/0, den-window 44/0, NPC 4/0; no GPU or capture.
Flag for the verifier: this is explicitly **not** a played route (`route_claim=none`);
the full 27-beat traversal and the UI/menu beats remain undriven, and the report's
`da780d4` code head sits one evidence commit below the branch tip `06d46b9`.

## Round 2 — gate integration

`probe_route_npcs` is now a first-class gate: `run_final_gates.sh` gains the
`probe_route_npcs` gate (`$OUT/probe_route_npcs.log`, marker `ROUTE_NPC PASS
checks=4 fails=0`), `EXPECTED_GATES` 58→59, with `checks=4`/`fails=0` and its
evidence log bound in `tools/gate_ratchet.json` and `check_gate_ratchet.py`
(LOG_GATES + binding + expected runner count 59). The same round also raises the
`probe_den_window` gate marker/floor 34→44, because the Phase 3C real-key
`[F] PONDER`/`[F] EXIT` block made the old literal marker fail the runner.
Measured: `gate_manifest.py` `orphans=0` (was 1); the new gate exits 0 and
greps `ROUTE_NPC PASS checks=4 fails=0`; `make gate-ratchet` PASS
(`runner/binding self-check 59 gates, 60 ratchet bindings`). No game-code or
claim change: `route_claim=none`, 1 driven / 1 partial / 4 unreachable /
21 not_attempted.

