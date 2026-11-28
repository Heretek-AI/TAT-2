PASS (round 4 final). The 58/58 measured baseline remains at `5857589`; these
are tooling/evidence/doc commits only.

What changed
- **B1 stamp pair enforced.** `tools/check_gate_ratchet.py` now requires BOTH
  `STARTED:` and `FINISHED:` on every one of the 59 evidence bindings
  (58 unique files; 14 numeric+marker logs are evaluated twice, 73 binding→log
  evaluations). A missing pair fails with `missing stamp pair`; it no longer
  returns silently. `FINISHED < STARTED`, `mtime < STARTED`, and a one-of-two
  pair still fail.
- **B1 poststamp body check.** The poststamp binding must carry real checker
  output, not just the marker: a >=100-line body containing
  `PASS: measured_on=`, `PASS: audit coverage`,
  `PASS: runner/binding self-check` and `GATE_RATCHET: PASS`. A bare marker
  fails.
- **Controls (scratch ROOTs):** old `25d9c94` headerless poststamp → FAIL
  `missing stamp pair`; both stamps deleted from `e2e.log` → FAIL
  `missing stamp pair`; poststamp reduced to the marker with valid stamps →
  FAIL `below the 100-line minimum … a bare PASS marker is not evidence`;
  current real artifact → PASS.
- **Regenerated poststamp artifact** with the mechanical wrapper:
  `STARTED: 2026-11-27T23:03:14-05:00`, `EXIT: 0`,
  `FINISHED: 2026-11-27T23:03:15-05:00`, mtime `23:03:15.049`, 375 lines;
  plain checker PASS.
- **Riders:** `tools/gate_ratchet.json` source `measured 0-2` → `observed 0-1`;
  report `run in the gun` → `run as gates`.
- Report §6 and OPEN_ISSUES item 25 updated.

Verification
- `python3 -B tools/check_gate_ratchet.py` → PASS (73 coherent-stamp
  evaluations, poststamp carries real 375-line output).
- `bash build/qa/poststamp_gate_ratchet.sh` → exit 0; plain re-validation PASS.
- `make gate-ratchet` → PASS; `make audit` → exit 0;
  `build/qa/e2e_errscan.sh` → PASS.
- No GPU, no generated data, no lowered floor; 58/58 measurement unchanged.
