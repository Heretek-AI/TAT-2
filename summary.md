BLOCKED: `e2e_errscan` (gate 34/58) fails non-deterministically on Godot's
teardown resource warning; two full serial runs stopped there.

What I did
- Set up the fresh worktree: symlinked `extracted`, `game/data/generated`,
  `game/assets/ue`; ran the one-time import (8m32s).
- Found and fixed a setup gap: `make audit` fails on `vgmstream -> missing`
  without a `tools/bin` symlink (git-ignored tool binary). After
  `ln -s /home/john/Projects/TAT-2/tools/bin tools/bin`, `make audit` exits 0.
- Ran `build/qa/run_final_gates.sh` twice (1116 s and 1126 s to gate 34/58).
  All 33 preceding gates exit 0; `e2e_errscan` fails both times, differently:
  attempt 1 `e2e_a2` had 0 ERROR (zero=`truncated` rule), attempt 2 `e2e` had
  32 > ceiling 31 because the same teardown warning appeared there.
- Proved the warning is random: three identical A2 standalones gave 0/1/1
  ERROR lines, all 22/22 green.
- Left the gate, allowlist, ceilings, logs and ratchet untouched; restored
  `docs/reports/logs/final/` to HEAD so no mixed-sample baseline is committed.
- Wrote `docs/reports/phase3-baseline-20261127.md` with the full evidence,
  measured gate table, deltas (compile 228→229, run_tests 327→328, doors
  47→49), the `/tmp` prefix/save loss, and the host context.

What I did not do
- Did not complete gates 35–58, did not advance `tools/gate_ratchet.json`
  `measured_on`, and did not re-stamp README / AGENTS / HANDOFF to 58 gates,
  because that would claim a baseline the runner cannot produce.
- Did not edit `build/qa/e2e_errscan.sh` or its allowlist (out of scope and a
  re-baseline); the correct fix belongs to the gate-integrity lane.

For the verifier: the failure is not a game regression — `e2e` 300/300,
`e2e_a2` 22/22, `run_tests` 328/0, `run_tests` ERROR count stable at 482.
The blocker is the errscan's sampled teardown-warning distribution.
