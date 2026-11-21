# task-p0-t2 — T2 SEARCH sight promotion (rank-based)

Date (UTC): 2026-11-20. Ground truth: AUDIT.md §1 T2 + §2 item 8, lane
`audit-gameplay.md` §3.3 P0-6 (sight) and §3.3 P1 (KO-wake meter).

## Reproduced spans (pre-change)

- `game/src/ai/guard_ai.gd:1011-1021` (sight ramp in `_physics_process`):
  `elif detection >= DETECTION_ALERTED_AT and state < Alertness.ALERTED:`
  is false for `SEARCH(4)` (`4 < 2` false); `state == Alertness.NEUTRAL`
  likewise excludes SEARCH. A SEARCHing guard staring at the player at
  detection 15–99 stayed SEARCH; only `>= 100 → _enter_combat()` (no
  state guard) escaped — dead zone 15–99 jumping straight to instant
  combat at 100.
- Noise path `guard_ai.gd:1158-1160`
  (`if state != ALERTED and state != COMBAT: _enter_alerted()`) correctly
  pulled SEARCH→ALERTED — vision and hearing used different transition
  tables. Untouched (out of scope); now agrees with the fixed sight ramp.
- `enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH,
  KNOCKED_OUT }` (`guard_ai.gd:5`): `SEARCH(4) > COMBAT(3)`, so every
  raw `<`/`>` comparison on the enum is suspect.
- `_recover_from_ko` (`guard_ai.gd:1223-1230`): `_set_state(SEARCH)`
  with no meter reset; `clamped_detection_for_transition` has no SEARCH
  ceiling and `ALERTNESS_RANK` has no KNOCKED_OUT entry, so the pre-KO
  meter (including 100) carried into SEARCH.

## Change (`game/src/ai/guard_ai.gd`, sight ramp only)

Replaced the two raw enum-order checks with `ALERTNESS_RANK`
comparisons via a `sight_rank` local (`ALERTNESS_RANK.get(state, 99)` —
KNOCKED_OUT sorts above every conscious level; unreachable here anyway
since the KO branch returns first):

- `detection >= DETECTION_ALERTED_AT and sight_rank < RANK[ALERTED]` →
  `_enter_alerted()` (was `state < Alertness.ALERTED`)
- `detection >= DETECTION_SUSPICIOUS_AT and sight_rank < RANK[SUSPICIOUS]`
  → SUSPICIOUS (was `state == Alertness.NEUTRAL`; identical outcome for
  all current states, rank-based form)

KO-wake: no behavior change — `_recover_from_ko` keeps the pre-KO meter
(100 included) by construction; added a comment pinning that intent.

## Rank table (`ALERTNESS_RANK`, unchanged)

| State      | Enum | Rank |
|------------|------|------|
| NEUTRAL    | 0    | 0    |
| SUSPICIOUS | 1    | 1    |
| SEARCH     | 4    | 2    |
| ALERTED    | 2    | 3    |
| COMBAT     | 3    | 4    |
| KNOCKED_OUT| 5    | — (unranked; `get` default 99 at the sight ramp) |

## Post-fix sight transition matrix (conscious states)

| Meter  | NEUTRAL (0) | SUSPICIOUS (1) | SEARCH (2)      | ALERTED (3) | COMBAT (4) |
|--------|-------------|----------------|-----------------|-------------|------------|
| ≥ 100  | COMBAT      | COMBAT         | COMBAT          | COMBAT      | COMBAT     |
| 45–99  | ALERTED     | ALERTED        | ALERTED (FIXED; was: stays SEARCH) | stays | stays |
| 15–44  | SUSPICIOUS  | stays          | stays, meter climbs while visible → 45 → ALERTED | stays | stays |

All non-SEARCH rows are behavior-identical to before (verified case by
case against the old conditions). SEARCH now matches the noise path's
table (SEARCH→ALERTED), closing the vision/hearing disagreement.

## Verify

- Re-read edited spans: rank comparisons present; no `state <` / `state >`
  ordering remains in the sight ramp or `_can_see_player` (only `==`/`!=`
  there). Remaining raw-order uses elsewhere are out of scope: noise
  SUSPICIOUS branch `:1164-1166` (`state < SUSPICIOUS`, lane-judged
  harmless) and decay/down-ramp code that already uses `ALERTNESS_RANK`.
- Full suite NOT run per brief (orchestrator runs it at settle).
