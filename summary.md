**Cleanout (Phase 3B.5) — round 2: display gating, hub reset, overlay-free QA,
save-layer guard.** Round 1 made `Mission.Guildhall.LootTheRoom` a first-class
Cleanout (`begin_cleanout`/`end_cleanout`, `run_credits_contract()` gate,
3300 s side-mission row, safe-room spawn, Den entry, no Contract 2 bank credit).
Round 2 closes the falsifier findings:

1. **Display-only credit removed.** `hud._post_match_contract_line`, the HUD's
   post-match contract row, and `post_match_ui._contract_outcome_line` now return
   empty when `run_credits_contract()` is false; `_xp_rows` shows only the three
   authored “Unsuccessful” rows at `+0` and `_expected_xp` returns 0, so a
   Cleanout win no longer claims +20/+20/+80 (the measured award is 0). The
   FTUE remainder row is gated too.
2. **Hub return clears the mode.** `hud.reset_run_modes_for_hub()` is shared by
   pause RETURN TO DEN and post-match Continue and calls `end_free_play()` +
   `end_cleanout()` (contract order 1), so a Cleanout cannot persist at the Den.
3. **QA works without the contracts.json overlay.** `GameData.is_side_mission`
   now falls back to the authored `*.LootTheRoom` id and authored
   `mission_loot_goals`, so `--qa-mission=Mission.Guildhall.LootTheRoom` stages
   `begin_cleanout` (no Contract 2 credit / £1,000) even with the overlay absent.
4. **Save layer refuses credit.** `SaveSystem.record_contract_complete` gates on
   `GameState.run_credits_contract()` (defensive free-play fallback) and its
   comment is corrected, so a direct call cannot credit a Cleanout.
5. **Prep selector no-op removed.** The mission `OptionButton` is disabled for
   free-play/Cleanout prep (`_refresh_all`), and `_on_mission_selected` ignores
   programmatic picks in those modes, so the card/time limit cannot be rewritten
   only to have READY force the row back.
6. **E2E extended.** Tier `s2` is now 22 checks: S2-18 covers capture, timeout
   and door-collapse banking; S2-19 asserts the displayed copy/award (no
   Contract 2 row, +0 breakdown, mission row still shown); S2-20 covers a co-op
   Cleanout resolve banking without credit; S2-21 proves overlay-free side-mission
   detection; S2-22 proves the shared hub-return clears both run modes.

Evidence: compile 233/0; `run_tests.gd` fails=0 (329 PASS); full E2E **310/310**;
`--tier=s2` **22/22**; `make audit` PASS; string audit 311/199/112 unchanged. No
save schema bump, no lock/texture/audit re-baseline.
