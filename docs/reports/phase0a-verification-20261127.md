# Phase 0a independent verification — `276a5bd` (2026-11-27)

**Verifier:** independent read-only pass (OpenCode subagent). **Scope:** Phase 0a
of [`next-phases-plan-20261127.md`](next-phases-plan-20261127.md) §2 at commit
**`276a5bdf3a84793f63df70aea1cdf5a46a72c390`**. **No GPU, Vulkan, Xvfb, Steam or
game launch was used.** No existing file was edited; this report is the only new
file.

## Verdict

**PASS — 8 / 8 checks.** The Phase 0a commit is a docs/QA/provenance commit, the
save baseline is restored to `976f8730…`, the route self-test gate is present
and green, the V6-03 erratum is confined to the official cell, the issue
triage is substantiated by the committed `5135f53` E2E log, and the commit is
local (not pushed). No corrective edit is required.

| # | Check | Result |
|---|---|---|
| 1 | Save baseline restored (774 files, `976f8730…`, archive intact, docs/#13 record it) | **PASS** |
| 2 | README / handoff / FIDELITY_GAPS / live-capture / live-ref-verification / rescore / AGENTS / plan truth | **PASS** |
| 3 | Scorecard provenance moved under `docs/reference/`; references and media-outside-git note | **PASS** |
| 4 | `p0b_route_self_test` gate (45 total), wrapper exit in log, 62/0 self-test, no compile-script change, no 45-gate claim | **PASS** |
| 5 | V6-03 official-cell erratum; port cell, `DELTA`, and 120 tally unchanged | **PASS** |
| 6 | Issue triage #2–#11: closures substantiated; deferrals labelled; #13 open with caveat | **PASS** |
| 7 | Hygiene: docs/QA/plan/provenance only, clean tree, no `game/`/generated changes, no push | **PASS** |
| 8 | `make check-greps`, `git diff --check`, route self-test 62/0, `bash -n` | **PASS** |

---

## 1. Save baseline — PASS

Measured directly on the copied prefix:

```text
$ find /tmp/opencode/tat2-ref-prefix -type f | wc -l
774
$ md5sum .../Saved/SaveGames/TAT_ETS.sav .../Saved/SaveGames.pre-p0b-20261126-230522/TAT_ETS.sav
976f8730eac989bab1c6c792343b7c00  SaveGames/TAT_ETS.sav
976f8730eac989bab1c6c792343b7c00  SaveGames.pre-p0b-20261126-230522/TAT_ETS.sav
```

- `SaveGames/` and the archive each hold the same three files
  (`TAT_ETS.sav`, `EnhancedInputUserSettings.sav`, `steam_autocloud.vdf`); the
  restored `TAT_ETS.sav` carries the archive's `2026-11-18 15:24:37` mtime, so
  this is a `cp -a` restore, not the 2026-11-27 02:00 `369e20d0…` save.
- The archive file mtimes remain `2026-11-18`; its bytes are unchanged.
- The report records the explicit restore and the no-`stage`+`tail -1` rule:
  [`docs/reports/phase0a-20261127.md:17`](phase0a-20261127.md),
  [`docs/HANDOFF_NEXT_AGENT.md:30`](../HANDOFF_NEXT_AGENT.md),
  [`docs/reports/p0b-live-capture.md:25`](p0b-live-capture.md) and
  [`docs/reports/p0b-live-capture.md:319`](p0b-live-capture.md).
- Issue **#13** has the checked baseline item and the explicit rule in both the
  body and the Phase 0a comment (`gh issue view 13`).

## 2. Docs truth — PASS

| Claim | Measured evidence |
|---|---|
| README 217 scripts, 324 checks, 300/300 E2E, audit 12660/12703, suites 121 | `README.md:19-25`; route row at `README.md:24`; `make test` 324 at `README.md:59` |
| Handoff header `a9ac606` | `docs/HANDOFF_NEXT_AGENT.md:3-7` (code/data tip `5135f53`; docs/evidence tip `a9ac606`; Phase 0a local, not pushed) |
| Save state in handoff | `docs/HANDOFF_NEXT_AGENT.md:30-36` (774 files, md5, archive, no `stage`+`tail -1`) |
| §7 adds `p0b-route-rescore.md` + live-ref plan/lanes | `docs/HANDOFF_NEXT_AGENT.md:375-379`; plan file `docs/reports/live-ref-review-plan.md` and lanes R1/R2/R3 exist |
| Beam qualification / route2 dirty / #13 / 120-tally note | `docs/HANDOFF_NEXT_AGENT.md:193-197` (`git.dirty=true` at `4341439`, clean re-run = Phase 0b), `:205-215` (120 tally, #13, save `976f`, 900 s, audio 80) |
| FIDELITY_GAPS: live reference pending; beam qualified; gem record present/payload absent; mirrors/landscape UNVERIFIED | `docs/FIDELITY_GAPS.md:21` (pending, not "none"), `:28` ("Beam claim qualified"), `:35` (gem), `:39` (mirrors/landscape), `:48` (V6-03), `:53` (tally note) |
| `p0b-live-capture.md`: 774 files, save, 126 G / 52 G / 9.1 G, 900 s, audio 80 | `docs/reports/p0b-live-capture.md:19-20` (900 s; Master/Music/SFX/Dialogue 80), `:25-27` (774 files, save), `:121` (disk), `:134-142` (restore + disk), `:319-323` (md5), `:602-606` (one band / above-door node), `:720` (#13 audio 80) |
| `live-ref-review-verification.md` stale UI4-05/S27 removed | `git show 276a5bd -- docs/reports/live-ref-review-verification.md` removes both "Residual" paragraphs; current `:90-95` says the UI4-05 copy was aligned, `:156-163` records the provenance move and unchanged tally |
| `p0b-route-rescore.md` provenance | `docs/reports/p0b-route-rescore.md:12-16` (Phase 0a move; V6-03 pointer), `:41` (tracked matrix path) |
| AGENTS 45 gates + route self-test row | `AGENTS.md:69` (45 gates), `:106` (route self-test row), `:204` (W10 44 measured; Phase 0a adds the 45th) |
| Plan file present | `docs/reports/next-phases-plan-20261127.md` §2 at `:63-107` |

No contradiction was found between these numbers and the committed final
evidence: `docs/reports/final-20261127.md:8` and
`docs/reports/logs/final/final-run.log:4` bind the measured set to `5135f53`.

## 3. Provenance — PASS

- Tracked files exist:
  `docs/reference/clip_1795033698901/row_route_matrix.md` (22,909 bytes;
  md5 `70ca2a7b58a8a176d006e0d89457f660`; tally `43 YES / 21 PARTIAL / 56 NO`
  at `:167`) and
  `docs/reference/clip_1795033698901/ADJUDICATIONS.md` (6,797 bytes; md5
  `554f591a8248c5c89497136828041801`).
- The `build/qa` originals are gone:
  `ls build/qa/review_20261124/row_route_matrix.md` and
  `ls build/qa/review_20261124/ADJUDICATIONS.md` both report "No such file";
  `git ls-files` lists only the two `docs/reference/` paths. This is a move,
  not a copy.
- References point at the tracked paths: scorecard sources at
  `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md:19`; rescore
  at `docs/reports/p0b-route-rescore.md:12-14` and `:41`; live-ref
  verification at `docs/reports/live-ref-review-verification.md:158-163`;
  lanes R1/R2/R3 at their source tables; plan at
  `docs/reports/next-phases-plan-20261127.md:25`, `:84`, `:261`.
- The media-outside-git note is in the scorecard provenance section:
  `COMPARISON_PORT_20261124.md:36-41` says the 2026-11-24 recording and its
  281 frames remain outside git; only the scorecard and the two provenance
  documents are tracked.
- Historical mentions of `build/qa/review_20261124/` remain in
  `live-ref-review-verification.md:161` and `build/qa/review_20261124/MORNING_BRIEF.md:108`
  as history, not as live references. Consistent with the move.

## 4. QA gate — PASS

- `build/qa/run_final_gates.sh` has the new `p0b_route_self_test` gate at
  `:370-372`; it runs `bash -n` on `p0b_route.sh` and `p0b_live_capture.sh`
  and then `P0B_ROUTE_EVIDENCE_DIR="$OUT" build/qa/p0b_route.sh --self-test`
  (`:364-368`). The script contains **45** gate invocations
  (`grep -cE '^(gate|gate_marker|gate_marker_re) [a-z]'` = 45); no other gate
  body was changed in the commit.
- The wrapper writes its own exit into the captured log
  (`build/qa/p0b_route.sh`, `git show 276a5bd`):
  `P0B_ROUTE_WALL mode=self-test exit=0 wall=1s (headless, no GPU render)`.
  The committed self-test log carries it at
  `docs/reports/logs/p0b-route/self-test/self-test.log:95-96`.
- Rerun with a temp evidence dir:
  `P0B_ROUTE_EVIDENCE_DIR=/tmp/opencode/phase0a-verify build/qa/p0b_route.sh --self-test`
  → exit 0, `P0B_ROUTE_SELFTEST PASS checks=62 fails=0`
  (`/tmp/opencode/phase0a-verify/self-test/self-test.log:95-96`).
- `bash -n` on `build/qa/p0b_route.sh`, `build/qa/p0b_live_capture.sh` and
  `build/qa/run_final_gates.sh`: all exit 0.
- `git diff 276a5bd^ 276a5bd -- tools/check_scripts_compile.gd` is empty;
  the commit's file list contains no `tools/` path. The build/qa scripts were
  not added to the compile scan.
- The full 45-gate serial run is explicitly **not** claimed:
  `docs/reports/phase0a-20261127.md:5` ("Not done … the full 45-gate serial
  run"), `:80` ("first full 45-gate serial run are Phase 0b"), and
  `docs/HANDOFF_NEXT_AGENT.md:133` ("first full 45-gate serial run is Phase
  0b"). The measured baseline remains the 44-gate `5135f53` set.

## 5. V6-03 erratum — PASS

- Official cell, `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md:99`:
  "**Corrected 2026-11-27 (Phase 0a):** one crisp horizontal white volumetric
  beam … emitter at **x 17.8 %, y 40.0 %**; one band at rows **40.0–40.5 %**
  (about 6 px thick, x≈341→1300); cyan node at **x≈53 %, y≈23–25 %**, above the
  far doors (not a ceiling diamond). The earlier `x~17%, y~56%` / two-beam /
  cyan-ceiling-diamond text was a transcription error."
- `git show 276a5bd -- COMPARISON_PORT_20261124.md` shows only the official
  cell changed in that row; the port-side text ("Not reached. No beam, wall
  emitter, ceiling node …") is byte-identical, and the row token remains
  `DELTA`.
- The tally is unchanged: `COMPARISON_PORT_20261124.md:280-284` still reports
  `48 scored / 56 N/A-route / 16 UNVERIFIED`; the matrix still reports
  `43 / 21 / 56` at `row_route_matrix.md:167`.

## 6. Issue triage — PASS

`gh issue list --state all` shows:

| Issue | State | Evidence |
|---|---|---|
| #5 | CLOSED / COMPLETED | Comment cites `docs/reports/logs/final/e2e.log` `SUMMARY: fails=0 passed=300 total=300` at `:1893`; `docs/reports/e2e-baseline.md` exists; `git grep -nE "load_patched\|or true\|tautolog" -- game/tests/e2e/` = 0 hits |
| #7 | CLOSED / COMPLETED | T1-17-C `e2e.log:506`, T2-03-B `:698`, T2-17-A `:1017` — all `PASS:` |
| #8 | CLOSED / COMPLETED | All 27 listed IDs have `PASS: [ID]` lines; cited examples: T1-10-C `:339`, T1-11-D `:348`, T1-11-E `:360`, T2-08-C/D/E `:763-765`, T2-09-A/B/D `:768-776`, T4-04…T4-09 |
| #9 | CLOSED / COMPLETED | T2-05-A/B/E `:746-750`, T2-14-C `:805`, T2-16-A `:889`, T2-16-D `:936`, T2-18-A/B/C `:1022-1024`, T3-18 `:1265`, T3-19 `:1266`, T4-02 `:1353`, T4-03 `:1453` |
| #10 | CLOSED / COMPLETED | T2-20-A `:1032`, T3-07 `:1072`, T3-17 `:1263` — all `PASS:` |
| #2, #3, #4, #6, #11 | OPEN, `deferred` label | Each has a Phase 0a comment mapping it to a phase/reason: #2 mobile out of scope (R4); #3 Phase 2 G-4 destructibles; #4 Phase 3 D-3 perf; #6 Phase 1 P4.1 IBL/weather; #11 tag-vocabulary blocker |
| #13 | OPEN, `deferred,live-reference` | Save baseline checked; Cleanout capture still deferred; body and comment carry the `976f`/no-`stage`+`tail -1` caveat |

The closures cite the committed `5135f53` run, not a new Phase 0a E2E:
`docs/reports/logs/final/final-run.log:4` records
`head: 5135f53dfff8a9b268576f7731588ab7a0be3494`, and `:98` records
`FINAL_GATES PASS ... gates=44`. That is consistent with a docs-only commit.
No issue was closed without a recorded reason.

## 7. Hygiene — PASS

`git show --stat 276a5bd` reports **19 files**, all docs/QA/plan/provenance:

```text
AGENTS.md
README.md
build/qa/p0b_route.sh
build/qa/run_final_gates.sh
docs/FIDELITY_GAPS.md
docs/HANDOFF_NEXT_AGENT.md
docs/reference/clip_1795033698901/{ADJUDICATIONS.md,COMPARISON_PORT_20261124.md,row_route_matrix.md}
docs/reports/live-ref-lane-r{1,2,3}.md
docs/reports/live-ref-review-20261127.md
docs/reports/live-ref-review-verification.md
docs/reports/logs/p0b-route/self-test/self-test.log
docs/reports/next-phases-plan-20261127.md
docs/reports/p0b-live-capture.md
docs/reports/p0b-route-rescore.md
docs/reports/phase0a-20261127.md
```

No `game/`, `extracted/` or `game/data/generated/` path is in the commit
(`git diff-tree --no-commit-id --name-only -r 276a5bd`). `git status --short`
was clean at verification start. `git rev-parse origin/main` = `a9ac606`
(unchanged); `HEAD` = `276a5bd` — local, not pushed.

## 8. Commands actually run

```text
git status --short                                   clean (before this report)
git show --stat 276a5bd                              19 files; docs/QA/plan/provenance
git diff-tree --no-commit-id --name-only -r 276a5bd  no game/extracted/generated
git rev-parse origin/main                            a9ac606f141cca54c4c69949af701ceee15a2243
bash -n build/qa/p0b_route.sh                        exit 0
bash -n build/qa/p0b_live_capture.sh                 exit 0
bash -n build/qa/run_final_gates.sh                  exit 0
P0B_ROUTE_EVIDENCE_DIR=/tmp/opencode/phase0a-verify \
  build/qa/p0b_route.sh --self-test                  exit 0; PASS checks=62 fails=0
make check-greps                                     LITERAL_GREPS PASS code_hits=0
                                                     ui_rating_literals=0 files=106; exit 0
git diff --check                                     clean; exit 0
```

No Godot renderer, Vulkan, Xvfb, Steam or game process was launched. The
self-test is the headless wrapper; `make check-greps` scans `game/src` only.
The E2E log was inspected, not re-run.

---

## Residual risk (not a Phase 0a failure)

1. **The 45-gate set is statically complete but not measured as a set.** The
   new gate was executed headless and the 44-gate `5135f53` logs remain the
   measured baseline. Phase 0b owns the first serial 45/45 run.
2. **The save/prefix is outside git and lives under `/tmp`.** The hash and
   file count are correct now, and the archive is intact, but `/tmp` is
   volatile; the archive path and the restore rule in the docs are the durable
   record. A reboot would require re-staging from the archive.
3. **Issue closures rest on the 2026-11-26 `5135f53` E2E log**, not a new E2E
   at `276a5bd`. The commit is docs/QA-only, so there is no code delta, but the
   closure evidence is one day older than the triage.
4. **V6-03 is a transcription correction, not a new measurement.** The erratum
   transcribes the existing KF27 foyer measurement; no GPU or new capture was
   made in Phase 0a. The port-side cell and the tally remain Phase 3.
5. **The provenance move cannot be hash-compared to a tracked pre-move
   baseline** because the originals were git-ignored. Identity is supported by
   the preserved size/mtime, the `43/21/56` tally, and the absence of the old
   paths; a future change to the tracked copies would need a new baseline.
6. **Route2 remains dirty.** `git.dirty=true` at `4341439` is documented; the
   clean GPU re-run is Phase 0b, so no clean route2 claim exists yet.
7. **The verifier report is untracked.** This file was created for review; the
   parent session must decide whether to commit it. It was not added to
   `276a5bd`.

**Minimal correction for any failed check:** none — all eight checks pass.
