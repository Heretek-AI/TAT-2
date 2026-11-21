# T8 remediation — mission clue + Den-card F hint key mismatches

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md` §T8
plus `audit-gameplay.md` §1.5 (P0-4) / §1.7 (P0-3). Every cited span re-opened before editing.
Scope: `game/src/missions/mission_controller.gd` clue/card spans only. No minis/telescope/vista/deploy changes.
`hud.gd` / `game_data.gd` / `contract_table_ui.gd` read-only (shape references only).

## 1. Reproduced spans (pre-fix, HEAD b5b5358 + round-1/round-2 work)

- `mission_controller.gd:147` — `loading.call("start_loading", ..., str(contract_info.get("clue", "")), map_id)`
- `mission_controller.gd:1234` (`_spawn_clues`, AUDIT cites :1222) —
  `str(contract_info.get("clue", "Locate the target vault and watch the Constabulary patrol timing."))`
- `mission_controller.gd:930` — ponder card `"hints": [{"key": "F", "label": "EXIT"}]`
- `mission_controller.gd:966-970` — map-table card `"hints": [H/Difficulty, R/Mode, F/Prepare for Mission]`
- `mission_controller.gd:981` — telescope card `"hints": [{"key": "F", "label": "PONDER"}]`
- `game_data.gd:389` — producer: `base["clue_facts"] = clues` (array). Zero `"clue"` writers (grep-verified).
- `hud.gd:1840-1871` — consumer `set_den_lookat_card` renders only
  `lines / difficulty / mode / prompt / bottom_hints`; never `"hints"`.
- Correct readers (unchanged, proof the producer key is `clue_facts`):
  `contract_table_ui.gd:310` (`disp.get("clue_facts", [])`, `• `-bulleted `"\n"` join),
  `main_menu.gd:563` (`d.get("clue_facts", [])`).

## 2. Reconciled key table

| # | Producer | Key written | Consumer (pre-fix) | Key read | Verdict |
|---|----------|-------------|--------------------|----------|---------|
| C1 | `game_data.gd:389` `get_contract_display` | `clue_facts` (Array[String], may be empty) | `mission_controller.gd:147` loading screen | `clue` | MISMATCH — loading clue always `""` |
| C2 | same | `clue_facts` | `mission_controller.gd:1234` `_spawn_clues` | `clue` | MISMATCH — clue body always hardcoded fallback |
| C3 | `mission_controller.gd:930,966-970,981` Den cards | `hints` (Array of {key,label}) | `hud.gd:1840-1871` `set_den_lookat_card` | `lines/difficulty/mode/prompt/bottom_hints` | MISMATCH — F row (Prepare/PONDER/EXIT) dropped; H/R rows rendered only via `difficulty`/`mode` keys |
| — | same producer | `clue_facts` | `contract_table_ui.gd:310` intel panel | `clue_facts` | OK (reference join convention) |

## 3. Fix (consumer-side, producer untouched)

- New `_contract_clue_text(info, fallback)` (`mission_controller.gd`, above `_spawn_clues`):
  legacy non-empty `"clue"` first → `"clue_facts"` joined `"• "+fact` with `"\n"`
  (same convention as the table intel panel) → caller fallback.
  Debug contract: a dict carrying neither `"clue"` nor `"clue_facts"` logs `push_error`
  and trips `assert(false, ...)` (stripped in release), then returns the fallback.
- `:147` loading call now passes `_contract_clue_text(contract_info, "")`.
- `:1234` `_spawn_clues` now passes `_contract_clue_text(contract_info, "<generic fallback>")`
  (existing empty-guard retained).
- All three visible cards rewritten onto the hud-supported contract; dead `"hints"` key removed
  (sole consumer is `set_den_lookat_card`, verified by grep — no other readers):
  - ponder-active (was :930): `"prompt": "EXIT"` (renders the in-card F row) +
    `"bottom_hints": [{F, EXIT}]` (drives the hub action-hint bar, `hud.gd:2304-2305`).
  - map-table (was :966-970): keeps `difficulty`/`mode` (H/R rows) + new
    `"prompt": "Prepare for Mission"` (F row) + `"bottom_hints": [H, R, F]`.
  - telescope (was :981): `"prompt": "PONDER"` + `"bottom_hints": [{F, PONDER}]`.
  - hidden default card (:924): same supported shape (`prompt`/`bottom_hints`), never rendered.

## 4. Verify

- Re-read edited spans: asserts present on missing keys; no `get("clue", ...)` consumers remain
  in `mission_controller.gd` outside the legacy-first branch of the helper.
- `gdparse mission_controller.gd` → rc 0. Delimiter balance {}/[]/() even.
- `make test` NOT run per task instructions (orchestrator runs the full suite at settle).
- Untouched as scoped: minis/telescope/vista spans, `hud.gd`, `game_data.gd`, deploy handoff.
