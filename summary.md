**Cleanout (Phase 3B.5) — first-class deploy without Contract 2 credit.** Added
`GameState.begin_cleanout()`/`end_cleanout()` (staged across the map-change
`reset_run` like free play) and a single campaign-credit gate,
`run_credits_contract()`, which is false for free play, for a Cleanout run and
for any authored side-mission row. `mission_controller._finish_run` and the
co-op mirror now bank the haul for escape/capture/timeout/collapse exactly once
but call `record_contract_complete` only when that gate is true;
`LootInventory.build_payout` uses the same gate, so a Cleanout escape pays the
haul and 0 contract reward. The side-mission row is kept by
`_resolve_deploy_mission_row`/`_resolve_deploy_mission_id`, `_active_quest_objective`,
the briefing, clues and HUD when `cleanout_run` is set, so the run uses the
authored `Mission.Guildhall.LootTheRoom` row (3300 s Novice, 4,000 loot goal,
safe-room spawn) instead of the 7200 s hosting-map row; free play is unchanged
and still banks nothing. The Den contract table gained a separate
`CLEANOUT HEIST [C]` button wired to `_start_cleanout` → prep with
`free_play=false` + `side_mission_id`, and `--qa-mission=<side-mission id>` now
takes the Cleanout path instead of mis-crediting Contract 2. Verification:
compile 233/0; `run_tests.gd` fails=0 (329 PASS); full E2E 306/306; tier `s2`
18/18 (new S2-13..S2-18: row/clock, safe-room spawn, bank + no Contract 2
credit + exactly once, free-play zero bank, capture/timeout bank, table-entry
wiring); `make audit` PASS and string audit 311/199/112 unchanged. No save
schema bump, no lock/texture/audit re-baseline.
