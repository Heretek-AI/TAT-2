# T7 deploy handoff — mission id + co-op mode survive to start (P0)

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
T7 + `audit-gameplay.md` §1.2 (P0-1, P0-2). Scope: authorized spans only; no
signal-arity changes, no minis/telescope/vista/clue spans touched. `make test`
not run (orchestrator settles); verify here is file-level + targeted checks.

## Root cause (reproduced before editing)

- `mission_prep_ui.gd:151` emitted `(map_id, difficulty, mode, contract_order)`
  with no mission id; `mission_controller.gd:1150-1153` re-derived positionally
  (`matching[absi(order) % matching.size()]`), discarding the OptionButton
  override (`mission_prep_ui.gd:688-693`).
- Table kept local `coop_mode` (`contract_table_ui.gd:23,504-507`), emitted it in
  `mission_selected` (`:517,544`, zero listeners); deploy closure took only
  `(order_id, map_id)` (`mission_controller.gd:1132-1134`).
- `GameState.reset_run` (`game_state.gd:40-44`) clears `active_mission_id` on map
  change (Den → mission map always changes), so even a stored choice died before
  `_setup_mission_objectives` ran. Mode survived `reset_run` (untouched) but was
  never written — sole writer was the Den floor R-toggle (`mission_controller.gd:726`).

## Threaded contract (end to end)

1. Prep READY — `mission_prep_ui.gd:148-160` (`_emit_ready`): the
   OptionButton override in `_selected_mission_idx` (set by `_on_mission_selected`,
   `:688-693`, defaulted per-map at `:712`) is written to
   `GameState.active_mission_id` when it belongs to the deploy map; cross-map
   picks are left unset so setup falls back. Emit arity unchanged.
2. Table confirm — `contract_table_ui.gd:542-550` (`_on_prep_ready`): persists
   `GameState.active_mission_mode = p_mode` (and local `coop_mode`) before
   `mission_selected` / `deploy_requested`. Signal arities unchanged.
3. Deploy closure — `mission_controller.gd:1131-1143` (`open_contract_table_ui`):
   stashes `active_mission_id` + `active_mission_mode` across `reset_run`, then
   restores both before scene reload. The id restore is safe: setup validates it
   against `missions_by_id` + map before honoring.
4. Setup — `mission_controller.gd:1148-1165` (`_setup_mission_objectives`): honors
   the threaded id when it matches the map (`:1154-1157`, pre-existing); the
   positional fallback is replaced by deterministic first-for-map (legacy paths
   that never set an id only), and `order` is renamed `_order` (unused).
   No `absi(order) % size` re-derivation remains in `mission_controller.gd`
   (grep-verified, 0 matches).

## Verify (this turn)

- Re-read all edited spans post-edit; arities of `deploy_requested`,
  `mission_selected`, `ready_pressed` unchanged (decls untouched).
- `GameState` is a registered autoload (`game/project.godot:16`); the new
  `GameState.active_mission_id` write in `mission_prep_ui.gd` resolves the same
  way as the existing `GameState.*` uses in `contract_table_ui.gd`.
- No godot binary on this host; full suite runs at orchestrate settle.
- Untouched as ordered: minis/telescope/vista/clue spans in mission_controller,
  prep `:712`/`:750` positional defaults, `reset_run` body in game_state.gd.

## Changed ranges (HEAD-relative)

- `game/src/missions/mission_controller.gd:1131-1143`, `:1148`, `:1158-1165`
- `game/src/ui/contract_table_ui.gd:542-550`
- `game/src/ui/mission_prep_ui.gd:148-160`
