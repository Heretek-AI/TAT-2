PASS (round 3 evidence-chain repair). The 58/58 measured baseline remains at
`5857589` (23m19s); these commits are tooling/evidence only.

What changed
- **A1 mechanical poststamp + timestamp self-check.** New
  `build/qa/poststamp_gate_ratchet.sh` captures the poststamp run in one pass:
  STARTED before `python3 -B tools/check_gate_ratchet.py --generating-poststamp`,
  the real exit code as `EXIT:`, FINISHED after, then moves the temp into place.
  `docs/reports/logs/final/gate_ratchet_poststamp.log` is now a real run:
  `STARTED: 2026-11-27T22:53:58-05:00`, `EXIT: 0`,
  `FINISHED: 2026-11-27T22:53:58-05:00`, mtime `22:53:58.693` (the old file had
  STARTED 22:16:00 > FINISHED 22:15:28). `tools/check_gate_ratchet.py` now
  rejects an evidence log with FINISHED < STARTED, mtime < STARTED, or an
  incomplete stamp pair. Controls: STARTED=2099 FAIL; mtime=2000 FAIL; restored
  PASS. A plain checker run after the capture validates the new log end to end.
- **A3 footer.** `e2e_errscan.sh` now also requires `FINISHED:` and `EXIT: 0`
  near the end; a log truncated right after `SUMMARY:` fails.
- **A2 minima.** Per-log minimum totals e2e 31 / run_tests 482 / e2e_a2 0;
  deleting every e2e or run_tests ERROR line fails. A2 min 0 is intentional
  (teardown may be absent); residual documented.
- **Ceilings pinned.** `tools/gate_ratchet.json` now pins e2e 33, e2e_a2 2,
  run_tests 482 plus the minima (31/0/482); `check_gate_ratchet.py` enforces
  them from the PASS line and the stale 31/1/482 comment is fixed.
- **Wording corrected.** The teardown line is observed **0-1** per process, not
  0-2; ceiling 2 is one-slot headroom. Committed standalone A2 evidence under
  `docs/reports/logs/errscan-a2/` (0/0/1 runs, all 22/22).
- **Docs.** `docs/reports/phase3-baseline-20261127.md` §5/§6 and
  `docs/reports/phase3-plan-20261127.md` §2.5.4 record the reviewed 33/2/482
  raise and the controls; AGENTS/HANDOFF wording corrected. OPEN_ISSUES items
  21-24 appended (A1/A2/A3 closed, A5/A6 evidence).

Affected-gate re-runs (not the full 58)
- `bash build/qa/e2e_errscan.sh --logdir docs/reports/logs/final` →
  `E2E_ERRSCAN PASS e2e=31/33 e2e_a2=0/2 run_tests=482/482 new=0`.
- `bash build/qa/poststamp_gate_ratchet.sh` → exit 0; plain checker → PASS.
- `make gate-ratchet` → PASS; `make audit` → exit 0.
- Controls: truncation-after-SUMMARY FAIL (footer); deleted-all-ERROR e2e FAIL
  (min 31); deleted-all-ERROR run_tests FAIL (min 482); zero A2 PASS; bad
  STARTED/mtime FAIL. No GPU, no generated data, no lowered floor.
