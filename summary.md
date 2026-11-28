PASS (round 5 final). The 58/58 measured baseline remains at `5857589`; these
are tooling/evidence/doc commits only.

What changed
- **B1 poststamp body bound to the ratchet.** `tools/check_gate_ratchet.py`
  now requires exactly `PASS: measured_on=5857589` and
  `PASS: report names measured_on=5857589` (no other/duplicate value), the exact
  line `PASS: runner/binding self-check 58 gates, 59 ratchet bindings`,
  `PASS: audit coverage 12660/12703`, and structural floors of >=300 total lines
  and >=300 `^PASS:` lines.
- **Per-large-log minima** added: e2e >= 4000, run_tests >= 3000, e2e_a2 >= 200
  lines (current 4343 / 3647 / 253). The check keys by `<name>.log` so a gutted
  10-line e2e stub fails.
- **All 59 evidence bindings** (58 unique files; 73 binding→log evaluations)
  still require both STARTED/FINISHED; a missing pair fails.
- **Controls (scratch ROOTs):** current real artifact PASS; 122-line stub FAIL
  (line/PASS floor); stale 25d9c94 body + typed `measured_on=5857589` FAIL
  (stale value + floor); identity rewrite to `measured_on=37bb69e` FAIL
  (measured_on binding); gutted 10-line e2e.log FAIL (4000-line minimum).
- **Report §6 reworded** to state what is actually proven (mechanical capture,
  stamp coherence, measured_on binding, real-output shape, binding
  completeness) and that a post-hoc byte edit with intact stamps/mtime can only
  be caught by re-running the gates. It no longer claims end-to-end validation.
- **Re-captured poststamp mechanically:** `STARTED 2026-11-27T23:17:48-05:00`,
  `EXIT: 0`, `FINISHED 2026-11-27T23:17:49-05:00`, mtime `23:17:49.004`,
  **378 lines / 367 PASS**; plain checker PASS.
- OPEN_ISSUES item 26 appended. `tools/gate_ratchet.json` measured_on unchanged
  at `5857589`.

Verification
- `python3 -B tools/check_gate_ratchet.py` → PASS
  (`carries real checker output bound to measured_on=5857589 (378 lines, 367
  PASS, exact bindings)`; large-log minima PASS).
- `bash build/qa/poststamp_gate_ratchet.sh` → exit 0; plain re-validation PASS.
- `make gate-ratchet` → PASS; `make audit` → exit 0;
  `build/qa/e2e_errscan.sh` → PASS.
- No GPU, no generated data, no lowered floor; 58/58 measurement unchanged.

## Phase 3B.1 — statetree (worker summary)

Made the StateTree path stop certifying a no-op and named what the coverage
number actually proves: `TAT2_STATETREE` now has an asserted `off` default
(`DEFAULT_MODE`, unset-env and unknown-value tests) and `TAT2_STATETREE=patrol`
**fails closed** (`attach()` returns null + one `push_error` + `patrol_refusal()`
naming `guard_bindings.mutates() == false`) unless the new experimental
`TAT2_STATETREE_WRITER=on` flag is set; the writer is a new
`writer_spike.gd::apply_step(dt)` that drives a guard from the interpreter's
selected leaf on a synthetic arena (default off, not a cutover). Coverage now
names `ST_Subtree_IntruderNoLongerSuspicious` as structurally covered but
behaviourally vacuous (4 states: Set Focus → Request Voice Line → Delay →
Succeeded) and pins `fully_parity_covered_trees=0 of 21`; the event census is
17 authored / 1 live-emitted (`StateTreeEvent.StimChange`, pushed from the real
`NoiseBus` hearing path in `guard_ai._hear`) / 16 unemitted, and the report
records `ST_Patrol`'s 4 missing smart-object/distraction tasks and 3 conditions
as the cutover floor without faking any subsystem. Measured: suite 110
205/0, suite 111 56/0 (A/B max per-frame planar deviation: off↔shadow
0.000000000 m, patrol+writer 0.255 m vs a 0.05 m difference floor and 6.0 m
bound; writer max step 0.0213 m ≤ 0.0419 m), probe PASS, `run_tests` fails=0
(328 PASS), compile 231/0, `make audit` PASS. The falsification evidence (flip
the default → 4 fails; remove the patrol refusal → 3 fails) is in
`docs/reports/statetree-3b1-20261127.md`. Not done: the 16 unemitted tags, the
smart-object/EQS floor, and any cutover — all recorded, none invented.
