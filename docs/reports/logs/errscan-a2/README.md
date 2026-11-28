# Standalone A2 teardown measurement (2026-11-27)

Committed evidence for the nondeterministic Godot teardown warning that the
`e2e_errscan` ceilings and minimum totals are calibrated against.

Command (headless, one Godot at a time, shared lock):

```bash
flock /tmp/opencode/tat2-godot.lock tools/godot --headless --path game \
  --script res://tests/e2e/run_e2e_tests.gd -- --tier=a2
```

Raw logs in this directory (`a2-standalone-{1,2,3}.log`), measured at code head
`5857589`:

| Run | rc | `ERROR:` lines | teardown lines (`resources still in use at exit`) | summary |
|---|---|---|---|---|
| 1 | 0 | 0 | 0 | `fails=0 passed=22 total=22` |
| 2 | 0 | 0 | 0 | `fails=0 passed=22 total=22` |
| 3 | 0 | 1 | 1 | `fails=0 passed=22 total=22` |

Across these runs and the two Phase 2.5 full-run samples the teardown line was
observed **0 or 1** per process (at most one summary line per process). The
`e2e_a2` ceiling of 2 in `build/qa/e2e_errscan.sh` is therefore **one-slot
headroom**, not a measured maximum; `e2e_a2_min=0` keeps a clean (zero-noise) A2
log valid. `e2e` and `run_tests` keep their stable minima (31 / 482) so deleting
their known errors fails.
