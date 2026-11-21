# task-p0-t1 — Blackjack damage branches + takedown counting (T1)

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md` §1 T1,
spans reproduced verbatim before editing (`thief_character.gd:1760-1783`,
`guard_ai.gd:1181-1182` `knock_out` early-return on already-KO).

## Changed range

`game/src/player/thief_character.gd` `_try_blackjack` loop body only
(guard-target block, ~:1764-1786). No other spans touched
(crank/diamond/takedown-anim out of scope).

## Branch table (after fix)

| Guard state at swing | Position | Damage dealt | Counter | Noise |
|---|---|---|---|---|
| 5 (KNOCKED_OUT) | any | none — skipped via `continue` | not counted | none |
| 0 / 1, behind (`behind_dot > 0.25`) | behind | `heavy_dmg` (`BlackjackDamageHeavy`, fallback `base_dmg` if `<= 0`) | +1 only if this swing transitions guard into state 5 | 4.5 m only on transition into KO |
| 0 / 1, not behind | frontal/side | `base_dmg` (`BlackjackDamageLight`) | +1 only if this swing transitions guard into state 5 | 4.5 m only on transition into KO |
| other (2-4 ALERTED/COMBAT/SEARCH) | any | `base_dmg` (no behind bonus) | +1 only if this swing transitions guard into state 5 | 4.5 m only on transition into KO |

Before: both branches assigned `heavy_dmg` (`base_dmg` fetched at :1760, never used);
`GameState.takedowns += 1` + 4.5 m noise fired on every swing, including on
already-KO guards (`knock_out` early-returns, so repeats farmed score via
`hud.gd:1728` and re-alerted the area).

## Counter rule

`GameState.takedowns` increments if and only if the struck guard's state reads
`== 5` **after** `take_knockout(final_dmg)` when it read `!= 5` before
(pre-swing state-5 targets are skipped with `continue`, so the post-swing check
observes exactly transitions into KO). Same gate applies to the 4.5 m
`takedown` noise. Light (non-KO) hits deal damage and end the swing (`return`)
with no count and no noise. State literal `5` matches the file's existing
convention (`_find_nearest_guard` uses `int(st) == 5`; no `Alertness` import in
this file).

## Verify

- Re-read edited spans: default `final_dmg = base_dmg`, behind branch assigns
  `heavy_dmg`, `guard_state == 5 → continue`, count/noise inside
  `if int(g.get("state")) == 5`.
- Full suite NOT run (orchestrator runs `make test` at settle per brief).
