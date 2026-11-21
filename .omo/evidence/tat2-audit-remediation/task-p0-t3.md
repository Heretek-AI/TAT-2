# TAT-2 audit remediation — P0 T3: unify win condition on loot_goal + quest flags

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md` §1 T3
plus lane reports `audit-core.md` (P0-3, P1-S1/S2), `audit-gameplay.md` (P0-7), `audit-ui.md`.
`mission_controller.gd` read-only context only (not modified).

## Reproduced spans (pre-change, verbatim)

- `game/src/core/game_state.gd:26` — `var loot_needed: int = 5`
- `game/src/core/game_state.gd:47-62` — `reset_run` resets `loot_goal` but never touches `loot_needed`
- `game/src/core/game_state.gd:110-112` —
  `if are_all_objectives_complete() and not quest_item_acquired: / quest_item_acquired = true / objective_completed.emit()`
- `game/src/core/game_state.gd:126-130` —
  `if loot_goal > 0 and loot_value >= loot_goal: return true` (riches short-circuit quest entries)
- `game/src/core/game_state.gd:167-168` — loot path sets `quest_item_acquired = true` (dual source, left as-is: out of authorized scope)
- `game/src/interact/escape_gate.gd:75` — `if GameState.quest_item_acquired or GameState.loot_collected >= GameState.loot_needed:`
- `game/src/ui/hud.gd:2152` — `"Reach Escape Gate" if ... quest_item_acquired else "❧ %s (%d/%d Loot)" % [..., loot_collected, loot_needed]`
- `game/src/missions/mission_controller.gd:1186` (context, untouched) — `goal_val = 1000 * clampi(GameState.difficulty, 1, 3)`

## Single-source rule

`loot_goal` (`1000 × difficulty` on Cleanout, `0` elsewhere) is the only loot threshold.
Victory = `GameState.are_all_objectives_complete()`:

- loot leg: `loot_goal > 0 and loot_value < loot_goal` → not complete;
- quest leg: every `mission_objectives` entry `done` (quest flags stay mandatory — loot alone can no longer complete);
- empty-objectives fallback unchanged: `return quest_item_acquired` (Den has no escape by construction).

`loot_needed` is legacy compat only (decl + `reset_run` reset + `loot_changed` payload/snapshot shape).
Nothing reads it as a threshold anymore.

## Changes (ranges post-edit)

1. `game/src/core/game_state.gd:26` — `loot_needed` init `5` → `0` + LEGACY comment.
2. `game/src/core/game_state.gd:47-50` — `reset_run` now resets `loot_needed = 0` alongside `loot_goal = 0`.
3. `game/src/core/game_state.gd:110-113` — `update_objective_progress` emits `objective_completed` on the unified
   condition without writing `quest_item_acquired` (removes the generic-progress flag write; quest pickups in
   `add_loot` still own the flag).
4. `game/src/core/game_state.gd:126-134` — `are_all_objectives_complete` requires BOTH loot-goal satisfaction
   AND all objective entries done (was: loot-goal short-circuit `return true`).
5. `game/src/interact/escape_gate.gd:75` — gate opens only on `GameState.are_all_objectives_complete()`;
   bare `loot_collected >= loot_needed` count-5 shortcut removed.
6. `game/src/ui/hud.gd:2152-2155` — fallback status reads the unified condition; incomplete state shows
   goal-vs-value `£ loot_value / £ loot_goal` (bare quest label when no goal); count-vs-5 removed.
   Main loot label (`_update_objectives_and_loot`, `:2117-2118`) already showed goal-vs-value; untouched.

## Three read sites (post-change)

- Gate: `escape_gate.gd:75` → `GameState.are_all_objectives_complete()`
- HUD loot/fallback: `hud.gd:2117-2118` (goal-vs-value label, pre-existing) + `hud.gd:2152-2155` (unified status)
- Logic: `game_state.gd:126-134` (single definition of victory)

## Verify

- Re-read edited spans; `grep` confirms no `loot_needed` threshold read in gate/HUD, no `loot_collected >=`,
  no bare-5 gate, no count-vs-5 HUD. `loot_needed` remains only in decl/reset/signal payloads.
- Truth-table check of the new predicate: cleanout under/at goal, rich-but-quest-open, set 2/3 vs 3/3,
  empty-objs with/without flag — 7/7 PASS.
- Full suite NOT run (orchestrator runs it at settle per task instructions).
