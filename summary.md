PASS. Phase 2.5 baseline complete: **58/58 gates exit 0** in **23m19s** at
run head `5857589853e43a30339ccc3e2d8cba26c1dde281` (`5857589`).

What I did
- Fixed `build/qa/e2e_errscan.sh`: a log is truncated only when it is empty or
  missing its tier's completion marker (`SUMMARY: fails=0 …`); a complete log
  with zero `ERROR:` lines passes. Kept the per-pattern max + `sum == ceiling`
  rule. Raised e2e 31→33 and e2e_a2 1→2 and allowlisted the nondeterministic
  `N resources still in use at exit` teardown class at max 2 per tier
  (measured 0–2; run_tests stays 482).
- Proved the semantics with six scratch-copy controls: zero+marker PASS,
  empty FAIL, marker-removed FAIL, new class FAIL, teardown 3 FAIL (max),
  total 34 FAIL (ceiling).
- Added the `tools/bin` symlink (git-ignored `vgmstream` the audit needs);
  recorded the fresh-worktree setup gap in the report, AGENTS.md and
  OPEN_ISSUES.md.
- Ran the full runner serially: 58/58 exit 0. Key measured values: compile
  229/0, run_tests 328/0 (suite 125), M2 12/0, doors 49, manifest 109/70/39/0,
  e2e_errscan 31/33 + 0/2 + 482/482 new=0, E2E 300/300, p2 17/17, VO 53, AEM
  77, cubemap 37, P5 54, locks 162, collision 0.869/868852.
- `make audit` exit 0 twice (no stamp refresh); `make gate-ratchet` PASS
  in-run at the old stamp and PASS post-stamp at `measured_on=5857589`
  (`gate_ratchet_poststamp.log`; the in-run log is intact).
- Updated README, AGENTS.md and HANDOFF_NEXT_AGENT.md with the measured
  values; wrote `docs/reports/phase3-baseline-20261127.md`.

Doc cells changed
- README: compile 228→229; run_tests 327→328 (suites →125); route self-test
  "49-gate set"→"58-gate set"; ratchet `37bb69e`/49 gates→`5857589`/58 gates;
  `make test` 327→328.
- AGENTS: `make test` 327→328 (suites 125); runner 49→58; gate-table header
  49/`37bb69e`→58/`5857589`; compile 228→229; run_tests 327→328 (suite 125);
  doors 47→49; ratchet cell; current-set narrative (58 gates, 229/0, 328/0,
  manifest/errscan, VO/AEM/cubemap in-run); Phase 0b stamp clause →
  `5857589`; definition-of-done 327/228/47/49 → 328/229/49/58; parallel-wave
  setup now includes `tools/bin`; new `e2e_errscan` known trap.
- HANDOFF: header tip/head/counts; §2 header + table (58, 229/0, 328/0, doors
  49, manifest, errscan; removed the VO/AEM/cubemap † note and paragraph);
  §5 prefix/save deletion; §7/§9/§10 counts; ratchet note.
- `tools/gate_ratchet.json`: `measured_on=5857589`, new `source`, report
  pointer, floors compile 228→229, run_tests 327→328, doors 47→49,
  gate_manifest.tracked 108→109. No floor lowered.

Caveats
- The errscan still pins the teardown class at 2/tier; a 3+ copy run fails by
  design. No GPU/Vulkan/Xvfb was run; P5/KF27 remain headless/reference-only.
  The `/tmp` prefix + save (md5 `976f8730…`) are confirmed deleted; the md5 is
  historical, not re-verified; `/home/john/tat2-ref-build` survives; #13 needs
  a fresh prefix/save. The 23m19s run is on the fixed 2026-11-27 host and is
  not a comparison with the old 80 W / 23–30 W host run.
