# W7S-S2 — carried loot, stash, payout and save v8

**Worktree:** `/tmp/opencode/tat2-w7s-s2` (base `74a43b8`)
**Scope:** carried loot inventory, one-use stash, binary-keep payout, save
schema v8, major-loot mesh verification, producer provenance.
**Not in scope / untouched:** `hud.gd`, S5 phase/start/process/spawn/escape
logic, loader, UI, hearing, visual code, guard pickpocket carry.

## Decisions (implemented, with provenance)

| Rule | Value | Source |
|---|---|---|
| Inventory slots | **12** | `BP_TATPlayerState` `TATLootInventoryComponent.InventorySlotMaxCapacity` |
| Slot cost | minor **1**, major **3**, quest **1** | authored rows are all `SlotSizeOverride 1`, `UseSlotSizeOverride false`; the 3-slot major cost is a recorded port capacity decision (`loot_settings.json → port_decisions.major_slot_cost`) |
| Capacity | enforced at pickup with the authored line | `ST_Interactables.ErrorInventoryFull` = `INVENTORY FULL` |
| Pickup beat | **1.0 s** actor linger | `BP_LootBagActor._minInteractDuration = 1.0` (port beat; actor leaves every gameplay group and stops monitoring immediately, then frees) |
| Keep on escape | **1.0** | port decision (binary keep) |
| Keep on capture | **0.0** | port decision (stashed value is always kept) |
| Contract reward | **£1,000** on a completed getaway | mission `Rewards[]` `TATQuestRewardType_Money` = 1000 (Guildhall/Old Manor/FTUE; Thieves' Den tutorial authors none → 0) |
| Difficulty multiplier | **none** | explicit: payout is independent of Novice/Thief/Master Thief |

Payout record (authored post-match DisplayData names):

```
Original = gross loot_value (monotonic; stashing never subtracts)
Kept     = carried haul × keep ratio (escape 1.0 / capture 0.0)
Stashed  = stashed_loot_value (always kept)
Score    = round(Kept × stealth multiplier)   # ghost 1.25, shadow 1.10, loud 1.0
MoneyTaken = Score + Stashed + Reward
```

Free play computes the same record but `SaveSystem.bank_payout()` banks **0**
and never writes a contract completion (hosting order 2 stays untouched).

## Runtime files

- `game/src/interact/loot_inventory.gd` (new): `SLOTS`, `SLOT_COST`,
  `CAP_ENFORCED`, `ACTOR_LINGER_S`, `KEPT_ON_ESCAPE`, `KEPT_ON_CAPTURE`,
  `can_carry`/`carry`, authored prompt/refusal, linger, `build_payout`.
- `game/src/interact/loot_stash.gd` (new): one-use deposit-all, quest items
  never depositable, authored stash prompts, single SFX/VFX hook
  (`deposit_feedback`; the capture's `GC_LootStashDeposit` cues have no resolved
  extracted media, so the default is silent rather than invented).
- `game/src/interact/loot_item.gd`: carry path, authored prompt/refusal,
  `is_large_carry` + `carry_mesh_path` fields, linger instead of same-frame
  `queue_free`.
- `game/src/interact/loot_container.gd`: `kind: "stash"` deposit trigger,
  `stash_uses`, carry metadata on spawned items.
- `game/src/core/game_state.gd` (loot fields only): carried list, tracking
  flag, stashed value, run payout id, `carried_loot_changed` /
  `stash_changed` signals.
- `game/src/core/save_system.gd`: `save_schema 8`, `loot_schema 1`,
  `last_match`, `pending_payout`, strict payout normaliser, idempotent
  `bank_payout`, `stage_pending_payout`/`settle_pending_payout`, one-shot
  `_migrate_save_schema` and crash recovery on load.
- `game/src/missions/mission_controller.gd`: `_on_extracted` builds/banks the
  escape payout; the two adjacent failure handlers bank capture/timeout
  payouts (kept 0, stashed kept). No S5 phase/start/process/spawn/escape code
  was changed.

## Producers (committed) → outputs

| Producer | Output(s) |
|---|---|
| `tools/parse_settings.py` (new) | `game/data/generated/gameplay/loot_settings.json` |
| `tools/parse_loot.py` | `game/data/generated/gameplay/loot_actors.json` (adds `is_large_carry`, slot override, `carry_mesh_res`; adds DT_LootInfo sources) |
| `tools/parse_contracts.py` | `game/data/generated/gameplay/contracts.json` (adds per-contract `reward_money`/`reward_source`, `mission_rewards`, `mission_durations[*].reward_money`) |
| `tools/parse_containers.py` | `game/data/generated/gameplay/containers.json` (secret stash `kind: "stash"`, `stash_uses: 1`, `one_use: true`) |

Wiring:

- `Makefile` `NORMALIZERS` now includes `parse_settings` → `make normalize`
  runs it on a clean extract.
- `tools/manifest_audit.py` `PRODUCERS` now includes `parse_settings.py` with
  `gen:gameplay/loot_settings.json`, so `make audit` stamps/gates it
  (new-producer and output-hash checks). It is not a separate *content group*
  (those count extracted payload classes); generated gameplay JSON is covered
  by the producer baseline and the `gen:gameplay` output directory.
- `tools/audit_baseline.json` was refreshed locally during implementation and
  then **reverted to HEAD** on the coordinator's instruction. Integration must
  regenerate the four outputs and re-stamp at the merged HEAD; a clean local
  `make audit` will therefore report producer-hash drift until then. This is
  expected, not a defect.

## Save v8 migration

- Old saves (no `save_schema`) merge into the v8 defaults, then
  `_migrate_save_schema()` stamps `save_schema 8` / `loot_schema 1` once.
- `last_match` / `pending_payout` are strict records: only the authored field
  set survives; unknown keys are dropped (never minted), values are type
  coerced/bounded, carried entries are capped at 64.
- `bank_payout` is idempotent by `match_id` (a repeated escape/downed signal or
  a retried mission banks once).
- A `pending_payout` left by a crash between staging and banking is settled
  once on the next load; a second load is a no-op.
- Payout records retain `Original/Kept/Stashed/Reward/Score/MoneyTaken`,
  `stealth_mult`, `capture`, `free_play`, `applied`, `banked` and a carried
  snapshot.

## Verification (real runs, 2026-11-24, `XDG_DATA_HOME=/tmp/opencode/w7s-data`)

| Gate | Result |
|---|---|
| compile | `scripts checked: 115, broken: 0` |
| `run_tests.gd` (full) | `SUMMARY: fails=0` (suites 89 + 90 green) |
| suite 89 (focused) | provenance, 12 slots / major 3, refusal, linger, quest items, stash, payout — all PASS |
| suite 90 (focused) | save schema, normaliser, idempotency, free play, crash recovery, migration, major mesh — all PASS |
| S2 E2E (`--tier=s2`) | `SUMMARY: fails=0 passed=12 total=12` (real Guildhall mission, 257 loot nodes) |
| E2E tier 2 | `SUMMARY: fails=0 passed=110 total=110` |
| E2E tier 4 | `SUMMARY: fails=0 passed=14 total=14` (T4-13/T4-14 banking preserved) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` |
| `make audit` (before baseline revert) | `AUDIT PASS`; after revert integration must re-stamp |

S2 E2E detail (real mission): major loot `1 visual root / 1 mesh node / 0
authored-off lights`; 3-slot pickup; real secret stash deposits 225 and spends
its one use; 12-slot cap refuses a real pickup with
`CLUE — NOTICE: INVENTORY FULL`; escape payout
`Original=1065 Kept=840 Stashed=225 Reward=1000 MoneyTaken=2275` banked once;
repeat signal idempotent; capture keeps 225 only.

## Deferred (explicit)

- **HUD tickers** for carried/stashed value (HUD not edited; `GameState`
  signals are ready).
- **Post-match UI** (the shipped `BPUI_PostMatchRackup` / `BPUI_EndMatchXP`
  panels are not wired; the save record carries their fields).
- **XP amounts**: `DT_PlayerExperience` authors category tags only; the
  capture has no per-category amounts, so `loot_settings.json` records the
  `CT_XPToLevel` curve and category tags and invents no XP numbers.
- **Pickpocket carry**: `guard_ai.gd` still calls `GameState.add_loot()`
  directly, so pickpocketed value counts in `loot_value` but is not added to
  the carried list (outside this lane's file ownership; the gross counter is
  still paid for legacy/staged runs).
- **Difficulty scaling**: deliberately not applied to payout.
