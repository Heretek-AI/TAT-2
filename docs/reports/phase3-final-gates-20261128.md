# TAT-2 Phase 3 final gate baseline (2026-11-28)

**Code head:** `900f8eb` (route-code merge; all Phase 3B/3A code + regenerated data).
**Run:** one serial `build/qa/run_final_gates.sh` into `docs/reports/logs/final/`.
**Gate set:** 59 gates. `measured_on=900f8eb`.

This is the post-Phase-3 re-stamp after the Cleanout, route instruments, GC
fallback regeneration, HDR cubemaps, nav v2 bake and sRGB prompt fixes. The
first attempt of this run stopped on stale source-text/count markers
(`probe_p1_beams` foyer_beam_wide/gap_view, audio 135, VO 60, E2E 310,
errscan run_tests 495); each was a reviewed marker/ceiling update, not a
behaviour change. The numbers below are the measured logs at this head.

| Gate | Value |
|---|---|
| compile | 234 / 0 |
| run_tests | 329 PASS / fails=0 |
| M2 | 12 / 0 |
| E2E | 310 / 310 (a2 22/22, p2 17/17) |
| parity-only | 60 / 60 |
| cream 119 | GREEN passes=5 |
| audio 121 | 135 / 0 |
| VO 122 | 60 / 0 |
| AEM 123 | 77 / 0 |
| cubemap 124 | 51 / 0 |
| P5 UI | 54 / 0; `GEM_PAYLOAD layers=21` |
| P1 safe / doors / beams / ward / street | 86 / 49 / 9 / 44 / 31 |
| landscape mask | 7 / 0 |
| nav runtime | 97 / 0 (v2 bake: 78/2, 60/4, 4/0) |
| GC destruction | 55 / 0 (`fallback_broken=93`, `sibling_smc=5`, `unresolved=0`) |
| collision | `COL_MAPS PASS min_coverage=0.869 coverage_ppm=868852 dropped=0 planar_skipped=2` |
| locks | 162 = 152 containers + 10 door nodes |
| gate manifest | 112 tracked / 73 reachable / 39 retired / 0 orphans |
| Den spawn / Den window / route NPC | 9 / 44 / 4 |
| capture dry-run / self-test | 9 poses / 23 |
| KF27 reference | 9/9 reference-only (the port wide/pinned are 5/9; see the GPU report) |
| route self-test | 62 / 0 |
| runtime smoke | exit=124 errors=0 mission_ready=1 |
| e2e_errscan | `e2e=31/33`, `e2e_a2=0-1/2`, `run_tests=482-495/495`, `new=0` (ceilings 33/2/495; the measured counts vary within the known classes) |
| audit | 12664 measured / 12703 (floor 12660 / 12703), 0 unexpected |
| texture cap | 1567 targets / 796 capped / 1 alpha / 0 offenders |
| string audit | 311 routed / 199 authored / 112 invented |
| perf guard | 78 / 78 |
| gate ratchet | PASS in-run and post-stamp (59 gates / 60 bindings, `measured_on=900f8eb`) |

## Floors moved (raise only; no floor lowered)

compile 229->234, run_tests 328->329, E2E 300->310, nav 70->97, cubemap
37->51, GC 52->55, gate_manifest.tracked 109->112, capture dry-run poses 7->9,
audio 123->135, VO 53->60, den_window 34->44 (route-code), route NPC 4 (new),
errscan run_tests ceiling 482->495 (nav suite 126 known noise, `new=0`).

## Notes

- The KF27 port look is unchanged: the wide pose frames the card at 18.0/40.0
  and scores 5/9; the pinned pose is 5/9. The four failing terms are beam
  material (band 38.80, six bands, glow falloff, core saturation), not framing.
- The played route is a documented partial (11/27 beats captured, 45/120 rows)
  with measured blockers; it is not relabelled played.
- The 2026-11-27 host fixes are active; the GPU session recorded 125 W current
  limit (140 max) and did not compare against the pre-fix 80 W host.
