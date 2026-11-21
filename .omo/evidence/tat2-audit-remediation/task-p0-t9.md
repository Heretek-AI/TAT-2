# T9 Contract Journal — dead drawer removed; Den table is the single live deploy path (P0)

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
T9 + `audit-ui.md` §2 (P0-1) and §11 (P0-1). Scope: `game/src/ui/main_menu.gd`
journal spans only; PLAY flow untouched except the `_launch` body dependency
on the deleted drawer widgets. `make test` not run (orchestrator settles at
the wave level); verify here is file-level + targeted checks.

## Spans reproduced (before editing)

- `main_menu.gd:412` `# Contract Journal drawer (hidden until "CONTRACTS & CO-OP" is clicked)`
- `main_menu.gd:414` `journal_panel.visible = false`
- `main_menu.gd:391,400,404,408` menu is exactly PLAY / SETTINGS / CREDITS / QUIT —
  no "CONTRACTS & CO-OP" button exists.
- `main_menu.gd:393` PLAY hardcodes `selected_order = 1` then calls `_launch`.
- `main_menu.gd:570-578` `_launch` read `thief_opt.selected` / `diff_opt.selected`
  (widgets built inside the hidden drawer) plus `selected_order`, then
  `change_scene_to_file("res://scenes/mission.tscn")` directly — no
  `active_mission_id`, no `active_mission_mode`, no deploy-closure threading.
- Fixed deploy path (from `task-p0-t7.md`, re-read this turn, not re-edited):
  prep `_emit_ready` (`mission_prep_ui.gd:148-160`) threads the OptionButton
  mission pick into `GameState.active_mission_id`; table `_on_prep_ready`
  (`contract_table_ui.gd:542-550`) persists `GameState.active_mission_mode`;
  deploy closure (`mission_controller.gd:1131-1143`) stashes id + mode across
  `reset_run` and restores them; `_setup_mission_objectives` (`:1148-1165`)
  honors the threaded id when it matches the map, else deterministic
  first-for-map. T4 net-auth hardening (`task-p0-t4.md`) already landed, so the
  Den co-op route is the authenticated one.

## Decision: delete the drawer (keeps one live deploy path)

Restoring a "CONTRACTS & CO-OP" entry would create a *second* full deploy path
from the main menu whose LAUNCH bypasses the T7 handoff: the journal has no
mission picker (so `active_mission_id` would always be unset → silent
first-for-map fallback, re-shipping the T7a drop), and its Host/Join buttons
drive `NetManager` directly without ever writing `GameState.active_mission_mode`
(T7b split-brain: networked peer while the run boots Solo). Wiring it correctly
means duplicating the table→prep→deploy threading in the menu — two paths to
maintain, against AUDIT §2 ordering (T9 terminal, after T7/T4). The Den map
table already is the theme reference (28 `ThemeScript` refs), has the mission
picker, difficulty, mode, and DEPLOY through the fixed closure. So per the audit
("add the entry, or delete drawer + comment if the Den table is the intended
single route"): the drawer goes, the Den table stays the single live route,
PLAY remains a quick boot into the default contract.

## Changed ranges (`game/src/ui/main_menu.gd` only)

- Header comment: `+ Contract Journal` dropped; notes the Den table owns selection.
- Member vars: deleted `thief_opt`, `diff_opt`, `contract_list`, `detail_lbl`,
  `portrait_rect`, `net_status`, `ip_edit`, `journal_panel` (drawer-only state).
  `selected_order` kept (PLAY writes 1, `_launch` reads it).
- `_build_ui`: deleted the entire drawer build — panel + comment, header/close,
  top bar (thief/difficulty/host/join/ip/status), contract list + splash/detail
  column, LAUNCH button, default-select block. Left a 3-line T9 note naming the
  Den table as the single route. Menu buttons PLAY / SETTINGS / CREDITS / QUIT
  untouched.
- Deleted dead callbacks `_on_thief_selected` and `_on_contract_selected`
  (only served the drawer; zero other callers).
- `_launch` simplified to the widget-free quick boot: set
  `GameState.active_contract_order` + resolve `active_map_id` from the contract
  display, then change scene. Thief/difficulty writes removed — widget defaults
  were index 0 (Spider/Novice), identical to the `GameState` defaults, so
  default-boot behavior is unchanged and no widget dependency remains.

## Verify (this turn)

- Re-read edited spans post-edit: menu builds 4 buttons only; drawer block,
  comment, and both callbacks gone; `_launch` reads no deleted widget.
- Targeted grep over `main_menu.gd`: `journal_panel`, `thief_opt`,
  `diff_opt`, `contract_list`, `detail_lbl`, `portrait_rect`, `net_status`,
  `ip_edit`, `_on_thief_selected`, `_on_contract_selected`,
  `CONTRACTS & CO-OP`, `LAUNCH CONTRACT`, `KILCAIRN CONTRACT JOURNAL` —
  all 0 matches. `sans`/`serif` still consumed by menu buttons/logo fallback;
  `selected_order` written once (PLAY) and read once (`_launch`).
- Exactly one live route: Den table → prep → T7 deploy closure (mission id +
  mode threaded); PLAY is the widget-free default-contract boot through
  `start_contract` → `reset_run` → `_setup_mission_objectives` fallback.
  No menu surface can launch around the fixed handoff anymore.
- Design-system note (visual task): deletion only, no new chrome — zero new
  colors/spacing/type introduced. Removed inline gold-on-dark panel chrome
  (`Color(0.03, 0.035, 0.06, 0.94)` / `Color(0.55, 0.45, 0.25, 0.8)`) and inline
  journal title color, reducing the menu's theme bypass the UI audit flagged.
- Untouched as ordered: PLAY button wiring + `selected_order = 1`, settings /
  credits / quit, 3D backdrop, mission/prep/table/game-state files.
- Full suite NOT run (orchestrator runs `make test` at settle per instruction).
