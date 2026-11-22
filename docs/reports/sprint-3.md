# Sprint 3 — close M1, take M2 (world + rendering)

Started 2026-11-21. Decisions taken with the user:

| Decision | Choice |
|---|---|
| E2E baseline policy | **Baseline and forward** — fix harness + genuine-now defects; defer system-dependent failures to their owning milestone with a GitHub issue. |
| Regeneration gate (`11.11`) | **At sprint start** — wipe regenerable data, re-extract, re-normalize, prove every gate from clean. |
| Level Niagara target | **Absolute 3,695** — reconcile extraction accounting until the audited total is spawned. |
| Visual acceptance | **Screenshot pairs + report** under `build/qa/` (gitignored) plus a short written report. |

## Order

1. `A1` E2E baseline triage (uses current generated data).
2. `A2` per-milestone issues.
3. `A3` wipe + `make extract` + `make normalize` + gates.
4. `B1`–`B5` world loading/geometry.
5. `C1`–`C5` rendering/weather/VFX/materials.

## Baseline evidence

- E2E run (unmasked): `/tmp/opencode/e2e_unmasked.log`.
- Unit suite: `run_tests` fails=0, 0 leaks, 0 `SCRIPT ERROR`.
- M2 player suite: 9/9.
- Compile: 46/46.
- UID: 0/0.
- Pipeline: 107/107 maps, 210 patrol paths / 673 waypoints, 222 SV variants, 21 device families.

## Notes

- `11.11` wipes `extracted/` and `game/data/generated/`; both are gitignored, so no commit risk.
- The Niagara reconciliation starts from `game/data/generated/levels/**` record totals vs the audit's 3,695; the 107-map emission may have changed the accounting versus the audit's 70-map snapshot.
