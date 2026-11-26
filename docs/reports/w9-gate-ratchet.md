# Gate ratchet — W9 tip (8a4b0dd)

Re-measured on the merged W9 tree at `8a4b0dd` on 2026-11-25, after the four phases
and the footstep-occlusion hotfix. Logs: `docs/reports/logs/w9/`.

| Gate | Floor |
|---|---|
| compile | 186/0 |
| run_tests | 314 PASS, fails=0 (suites to 111) |
| M2 | 12 PASS, fails=0 |
| E2E | 278/278 |
| audit | coverage 12660/12703, 0 unexpected |
| texture cap | 797 capped, 1 alpha-critical, 0 offenders |
| perf guard | 78/78 |
| probes | doorwalk, viewmodel truth, Niagara, blackjack, geometry — all PASS |

Floors are **minimums**: a wave may add tests and files, never lower a floor or
introduce a failure. This supersedes the R8 floors measured on `e3678be` (152/301).
Update only from a committed log, as `tools/check_gate_ratchet.py` requires.

`make runtime-smoke` is not counted in this ratchet (it is a boot gate, not a counted
log); it is documented in `AGENTS.md` and must pass before a push.
