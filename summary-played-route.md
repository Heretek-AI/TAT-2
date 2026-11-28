# played-route — continuous first-class Cleanout attempt (BLOCKED, 11/27)

Extended `build/qa/route_driver.gd` from the Phase 3C `den_telescope` segment to a
continuous `cleanout_route` segment that boots the real `main_menu.tscn`, presses
PLAY with a real `ui_accept`, plays the Den (S02/S03, wardrobe S04, telescope S05,
ledger attempt S06, decoration+gramophone S07), opens the map table with `[F]` and
the table's own `[C]` Cleanout key (S08), presses `[F] READY` through the authored
6 s countdown (S09), lets the game's deploy closure reload `mission.tscn` on the
first-class `Mission.Guildhall.LootTheRoom` row (S10), closes the briefing letter
(S11), attempts the safe-room lantern (S12) and the street (S13), and opens the
pause menu (S27). No mission is `instantiate()`d, no body is teleported
(`transform_writes=0`), keys go through `Input.parse_input_event`. The clean run
at `1f3a50d` (`git.dirty=false`) gives `status=blocked_partial beats=27 driven=6
partial=5 blocked=3 unreachable=4 not_attempted=9 captured=11 mark_calls=11
checks=17 fails=0 route_claim=none`; `route_claim` stays `none` because only 11 of
27 beats are captured. **The task outcome is blocked**: S06 is 0.18 m outside the
ledger reach (1.9348 m vs 1.75 m), S12's authored safe-room spawn falls to a lower
collider (y 23.1585) than the dressing floor (y 25.0) and leaves the lantern
3.64 m away (raycast-measured), S13 reaches only the local safe-room area (best
probe 5.81 m; KF16 car 128.7 m away), and S19/S20/S22/S23 are NPC-unreachable
(85.4–150.7 m). The scorer now computes per-row capture coverage (`45/120`, 35
non-audio) from the 27 beats and still emits 0 tokens; self-test 22/22. A
`safe-room spawn floor gap` entry was added to `docs/FIDELITY_GAPS.md`. The
verifier should re-run both driver segments, the scorer self-test and its
manifest run, and independently confirm the S12 floor mismatch
(`SAFE_FLOOR_DIAG`-style raycasts) before accepting the blocker.
