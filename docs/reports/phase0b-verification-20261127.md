# Phase 0b — independent verification (2026-11-27)

| | |
|---|---|
| scope | `7681b1c` (clean route2 evidence) and `074341f` (45-gate set + ratchet) on `main` |
| verified HEAD | `79d8b8a2271681b54355f094c4a194a2d1ef9b69` (working tree clean before this update) |
| first-pass HEAD | `074341f474b92602ba5e58863d661683dff30173` |
| fix commit | `79d8b8a` (parent `074341f`; local, **not pushed**) |
| measured head | `912a481d42611cb0de77f31d4e01e63029b68190` |
| plan | `docs/reports/next-phases-plan-20261127.md` §3 |
| method | read-only: committed evidence, `git show`/`grep`/`identify`/`ffprobe`/`ffmpeg`, `make check-greps`, `make gate-ratchet`, `make audit`; no GPU/Steam/Vulkan; no edit outside this file; no push |
| prior phase | `docs/reports/phase0a-verification-20261127.md` (8/8 PASS) |

## Verdict

**Overall: FINAL PASS.** The 45/45 gate set at `912a481`, the clean
route2-clean capture, the ratchet re-stamp and the audit are all substantiated
by committed, independently reproducible evidence. The three conditional
corrections from the first pass (trailing space, wrong historic commit
citation, stale `measured_on` row) are resolved in `79d8b8a`; the artifact
bytes, every gate value and every ratchet floor are unchanged. No
re-measurement was needed.

## 0. Conditional fixes resolved (`79d8b8a`) — final PASS

Re-checked `79d8b8a2271681b54355f094c4a194a2d1ef9b69` (parent `074341f`) on
2026-11-27 after the fix commit:

| Fix | Evidence in `79d8b8a` | Verdict |
|---|---|---|
| Trailing space | `.gitattributes:1–5` adds `docs/reports/logs/**/capture.log whitespace=-trailing-space` with a verbatim-log rationale; `route2-clean/capture.log` blob is still `bbbcb1aea5a3a67f63f68b2afd5a0743a334b3f` (= `7681b1c` blob), sha256 `fe9c529b5cfdd0bedb1d9d5f134ffc39d356eb0643e774142ba84c3c778af12c`; `git diff --check 912a481..7681b1c`, `git diff --check` (worktree) and `git diff --check 912a481..HEAD` all exit 0 | **RESOLVED** |
| Citations | all six places now read “measured at `5135f53`, committed on `main` at `3d62f6b`, replaced in place at `912a481`” and name `docs/reports/logs/final/`; four also spell out recovery “at `912a481` and `3d62f6b`”, while `AGENTS.md` and `HANDOFF_NEXT_AGENT.md` name `912a481` as the recovery point and `3d62f6b` as the commit. No “remain in git history at commit `5135f53`” remains outside this report’s own quotation | **RESOLVED** |
| `AGENTS.md` ratchet row | `AGENTS.md:111` is now `PASS (measured_on=912a481; …)`, matching line 85 and `tools/gate_ratchet.json:3` | **RESOLVED** |

Unchanged evidence after the fix: `git diff --name-only 074341f..79d8b8a --
docs/reports/logs/ build/qa/ game/ extracted/ game/data/` is empty (0 files);
`tools/gate_ratchet.json`’s `gates`, `evidence`, `measured_on` and `report`
objects are byte-identical to `074341f` (only the `source` prose changed);
`P0B_ROUTE_SELFTEST PASS checks=62 fails=0` is still the committed line
(`docs/reports/logs/final/p0b_route_self_test.log:49–50`); and
`make check-greps`, `make gate-ratchet` and `make audit` all pass at `79d8b8a`
(see §7).

## 1. Checks

| # | Check | Verdict |
|---|---|---|
| 1 | Route2-clean manifest/log, counts, PNGs, S24 beam, audio, error scan, preserved route1/route2, gitignored media | **PASS** |
| 2 | 45-gate set, `FINAL_GATES PASS`, values vs `AGENTS.md`, `uncommitted_entries_at_start: 1` | **PASS** |
| 3 | Report exists with the measured table; cross-refs; handoff/AGENTS/README/FIDELITY_GAPS/plan updated; old `5135f53` evidence noted | **PASS** after `79d8b8a` — the six citations and `AGENTS.md:111` were fixed (§0); the `074341f` finding was FAIL (minor) and is kept in §2.3 as the record |
| 4 | Ratchet `measured_on=912a481`, route self-test floor 62, no floor lowered, checker reads the log, `make gate-ratchet`/`make audit` PASS, post-stamp logs | **PASS** (one stale-name note, §4.5) |
| 5 | Commit hygiene, clean tree, no `game/`/`extracted/`/generated data, `origin/main` / push state | **PASS** — `79d8b8a` is local, `origin/main` is `074341f`; the earlier push moved `912a481 → 074341f` during the first pass (§4.6) |
| 6 | `git diff --check`, `make check-greps`, route self-test 62/0, run wall/time, audio/peak | **PASS** after `79d8b8a` — `.gitattributes` exempts the verbatim log; all three `git diff --check` forms exit 0; 6b–6e unchanged |

## 2. Evidence

### 2.1 Route2-clean (check 1) — PASS

`docs/reports/logs/p0b-route/route2-clean/manifest.json` (`tat2.p0b_route/1`):

| Field | Value | Line |
|---|---|---|
| `git.sha` | `912a481d42611cb0de77f31d4e01e63029b68190` | 1615 |
| `git.branch` / `git.dirty` | `main` / `false` | 1613–1614 |
| `status` / `mode` / `route_claim` | `captured` / `staged` / `none` | 1721 / 1669 / 1685 |
| `counts` | `beats=27 captured=13 deferred=14 partial=0 frame_errors=0 frames=17 extras=1` | 1551–1561 |
| audio | `enabled=true`, `186.259 s`, `19` marks, `rms=-30.32 dBFS`, `peak=-0.76 dBFS` | 7, 13, 314–317 |
| S24 `foyer_beam` | `beam_visible=true`, `camera_source=player`, card `(23.27, 29.76, -57.4)` | 1393; `capture.log` S24 block |

`capture.log`:

- `AUDIO_CAPTURE start enabled=true driver=PulseAudio rate=44100 …` (line 31)
- `AUDIO_CAPTURE stop enabled=true frames=8214016 seconds=186.259 … dropped=647168 files=3` (line 371)
- `P0B_ROUTE_CAPTURE_DONE status=captured beats=27 captured=13 deferred=14 partial=0 staged_failed=0 frame_errors=0 frames=17 errors=0 exit_ok=true` (line 372)
- `P0B_ROUTE_WALL mode=capture run=route2-clean exit=0 wall=207s` (line 375)
- `SCRIPT ERROR` 0, `SHADER ERROR` 0, `Parse Error` 0, `ERROR:` 0 (case-sensitive `grep -c`); the only teardown item is the known `7 RIDs of type "Texture" were leaked` warning.

Media: `identify` over `build/qa/p0b_route/route2-clean/*.png` returns **18**
files, all **1920×1080 sRGB** (17 beat frames + `extra_lounge_beam_close_pose.png`).
I opened `S24_foyer_beam.png` and `S12_safe_room.png`: real Vulkan renders with
the HUD, the authored bright beam line and the safe-room portal; not blanks or
placeholders. `ffprobe` on `audio.wav`: `pcm_s16le, 44100 Hz, stereo,
186.258866 s`; `ffmpeg volumedetect`: `mean_volume: -30.3 dB`,
`max_volume: -0.8 dB`, corroborating the manifest (`-30.32` / `-0.758`).

Preservation / ignore:

- `docs/reports/logs/p0b-route/route1/` (`status=partial`, 12/1/14, 16 frames,
  `sha=4341439`) and `route2/` (`status=captured`, `git.dirty=true`, 13/0/14,
  17 frames, `sha=4341439`) are unchanged: `git diff --name-only
  912a481..HEAD -- docs/reports/logs/p0b-route/route1
  docs/reports/logs/p0b-route/route2` is empty.
- `build/qa/*` is git-ignored (`.gitignore:25`), so the 18 PNGs/WAV/PCM stay out
  of git; the manifest, capture log and GPU samples are tracked.

### 2.2 45-gate set (check 2) — PASS

`docs/reports/logs/final/final-run.log`:

- line 4 `head: 912a481d42611cb0de77f31d4e01e63029b68190`, line 5 `branch: main`
- line 9 `uncommitted_entries_at_start: 1`
- line 100 `FINAL_GATES PASS head=912a481… gates=45`

`final-summary.txt` has **45** unique gate names, all `exit=0`; the master log has
**45** `FINAL_GATE name=…` lines, all `exit=0`.

The measured values (current logs) match the `AGENTS.md` table:

| Gate | Measured line | Log |
|---|---|---|
| compile | `scripts checked: 217, broken: 0` | `compile.log:8` |
| `run_tests` | `SUMMARY: fails=0` + **324** `PASS:` lines; suites 119 and 121 present | `run_tests.log:2934`, `2931`, `2933` |
| M2 | `M2_SUMMARY: fails=0` + 12 `PASS:` | `m2.log:69` |
| P1 safe/doors/beams/ward/street | `86/0/0` (checks/fails/skips), `47/0`, `7/0`, `44`, `31/0 hard_limits=2` | `probe_p1_safe.log:124`, `doors:111`, `beams:40`, `ward:108`, `street:161` |
| guard Guildhall | `GUARD_CHECK PASS … lounge=1 lounge_marker=C_20 … buckets=4/4` | `probe_guard_positions_guildhall.log` |
| guard Old Manor | `GUARD_CHECK PASS map=old_manor order=3 … buckets=4/4` | `probe_guard_positions_old_manor.log` |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` (`no_record=0`) | `probe_collision_authored.log` |
| locks | `applied=154 containers=144 door_nodes=10 … state=APPLIED` | `probe_lock_inventory.log` |
| Niagara | `authored=3695 active=1048 … systems=16` / `NIAGARA_PROBE PASS` | `probe_niagara.log` |
| door walk / viewmodel / geometry / blackjack | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `GEOM_PROBE PASS` / `BLACKJACK_PROBE PASS` | respective logs |
| turret | `TURRET_PROBE PASS checks=11 actors=229 visible_parts=1145 hidden_parts=0` | `probe_device_meshes.log` |
| GC / trigger / civilian | `44/0` / `21/0` / `passed=23 total=23` | `probe_gc_destruction.log`, `test_gc_break_trigger.log`, `test_w10a2_civilian.log` |
| beam geometry | `cards=330 max_axis_err_deg=0.000006 clamped=0` / `BEAM_GEOMETRY_SUMMARY: fails=0` | `test_beam_geometry.log` |
| leak | clean `PROBE start`; no exit leak/`SCRIPT ERROR` | `probe_leak.log` |
| E2E `all` / `a2` / `p2` | `300/300` (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) / `22/22` / `14/14 expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` | `e2e*.log` |
| parity / cream / audio / P5 / Den | `60/60 rules=11` / `GREEN passes=5` / `checks=71` / `44` / `9` (`source=authored`, 2434 meshes) | respective logs |
| capture harness | dry-run `poses=6` / `P0B_SELFTEST PASS checks=21` / manifest `poses=6 dry_run=true` / `KF27 … met=7/7` | `p0b_*.log` |
| route self-test | `P0B_ROUTE_SELFTEST PASS checks=62 fails=0` | `p0b_route_self_test.log:49–50` |
| runtime / scan | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 … mission_ready=1` / `29/0` | `runtime_smoke.log:7`, `runtime_smoke_scan.log` |
| string / greps | `311/311/199/199/112` / `code_hits=0 ui_rating_literals=0 files=106` | `string_audit.log`, `literal_greps.log` |
| audit / texture / perf | `12660/12703 … unexpected 0` + **13** `content …: OK` groups / `796/1/0` / `78/0` | `audit.log:90–91,139`, `texture_cap.log:10–13`, `perf_guard.log` |
| ratchet | `GATE_RATCHET: PASS` | `gate_ratchet.log` (serial) + `gate_ratchet_poststamp.log` |

`uncommitted_entries_at_start: 1` is the untracked route2-clean evidence, not
code/data: at `912a481` the route2-clean path does not exist
(`git cat-file -e 912a481:docs/reports/logs/p0b-route/route2-clean/manifest.json`
→ fatal) while route1/route2/self-test/dry-run do; `912a481` is the recorded
HEAD and the tracked tree matched it (the capture ran 10:31–10:34, the gate run
started 10:35:15). `7681b1c` is the only commit that adds that directory.

The “every count unchanged” claim is independently true: I compared the marker
lines of 32 log files covering the numeric gates against the old logs committed
at `3d62f6b` (measured head `5135f53`) — all identical.

### 2.3 Evidence/report (check 3) — PASS after `79d8b8a` (was FAIL in `074341f`)

Present and correct:

- `docs/reports/final-20261127-phase0b.md` exists, `measured_on=912a481`
  (line 8), `45 / 45 exit 0` (line 14), the 45-row measured table (lines
  107–153), the ratchet diff and the re-stamp section.
- `docs/reports/final-20261127.md:18–23` marks itself superseded and links to
  the new report.
- `AGENTS.md:85` header and `234–240` paragraph; `README.md:12,24–27`;
  `docs/FIDELITY_GAPS.md:60–65`; `docs/HANDOFF_NEXT_AGENT.md:143–147`;
  `docs/reports/next-phases-plan-20261127.md` §11 execution log — all updated
  for 45 gates / route2-clean.
- Logs were replaced in place: at `912a481`,
  `docs/reports/logs/final/final-run.log` still ends
  `FINAL_GATES PASS head=5135f53… gates=44`; the new run overwrote it.

**Defect found in `074341f` (now resolved in `79d8b8a`):** the sentence “they
remain in git history at commit `5135f53`” was false. At `5135f53`,
`docs/reports/logs/final/final-run.log` does not exist (`git cat-file -e` →
“exists on disk, but not in '5135f53'”). The 44-gate logs were **measured at**
`5135f53` and **committed on `main` at `3d62f6b`** (“chore(final): W10 evidence
run, ratchet re-stamp and docs”; its `final-run.log` records
`head: 5135f53…`, `gates=44`). They are also recoverable from the pre-Phase-0b
revision `912a481`. The wrong citation appeared in:

| File | Line |
|---|---|
| `docs/reports/final-20261127-phase0b.md` | 38–39 |
| `docs/reports/final-20261127.md` | 21–22 |
| `AGENTS.md` | 240 |
| `docs/FIDELITY_GAPS.md` | 65 |
| `docs/HANDOFF_NEXT_AGENT.md` | 145–146 |
| `tools/gate_ratchet.json` (`source` prose) | 4 |

Everything substantive on the page was right; only the recovery pointer was
wrong. `79d8b8a` now states the correct chain in all six places (§0), including
the exact path `docs/reports/logs/final/`.

**Second defect found in `074341f` (now resolved):** `AGENTS.md:111` read
`make gate-ratchet | PASS (measured_on=5135f53; …)` while the table header on
line 85 and `tools/gate_ratchet.json` both said `912a481`. One row was missed;
`79d8b8a` now sets it to `912a481` (§0). `README.md:26` was already correct.

### 2.4 Ratchet/audit (check 4) — PASS

- `tools/gate_ratchet.json:3` `measured_on=912a481`; line 51 evidence entry
  `p0b_route_self_test.log`; line 157 floor `checks=62, fails=0`; report points
  at `docs/reports/final-20261127-phase0b.md`.
- `tools/check_gate_ratchet.py:134–148` adds the `p0b_route_self_test` entry:
  both wrapper `bash -n` checks plus the real self-test, with the
  `P0B_ROUTE_SELFTEST PASS checks=(\d+) fails=0` pattern (a probe that loses
  checks cannot pass).
- No floor lowered: `git diff 912a481..074341f -- tools/gate_ratchet.json`
  changes only `measured_on`, `source`, `report`, the evidence map and adds
  `p0b_route_self_test`; every existing gate object is byte-identical.
- I re-ran `make gate-ratchet` on `074341f`: exit 0,
  `GATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run locally)`,
  ending `PASS: report names measured_on=912a481`; re-ran it again on `79d8b8a`
  with the same result (§7).
- I re-ran `make audit` on `074341f`: exit 0, `AUDIT PASS`;
  `Case-sensitive parity: raw 12630/12703 … unexpected 0` (line 90);
  `Disk-backed content coverage: 12660/12703 (99.7%) … unexpected 0` (line 91);
  13 `content …: OK` groups; re-ran on `79d8b8a` with the same result (§7).
- Post-stamp logs exist: `gate_ratchet_poststamp.log` (finished 11:00:35, exit 0,
  `PASS: p0b_route_self_test.checks=62 >= 62` lines 47–48 and 100–101) and
  `audit_poststamp.log` (`AUDIT PASS`, exit 0).

Note (§4.5): the serial run's `gate_ratchet.log` predates the re-stamp — it
says `PASS: report names measured_on=5135f53` and has no route-self-test lines
because the checker entry was added afterwards. The report §5 explains this;
the post-stamp log is the proof of the new floor.

### 2.5 Hygiene (check 5) — PASS, with a push during verification

- `git show --stat 7681b1c`: 5 files — the four
  `docs/reports/logs/p0b-route/route2-clean/` evidence files and
  `docs/reports/p0b-route.md`.
- `git show --stat 074341f`: 62 files — docs, `docs/reports/logs/final/**`,
  `AGENTS.md`, `README.md`, the plan, `tools/gate_ratchet.json` and
  `tools/check_gate_ratchet.py`.
- `git diff --name-only 912a481..074341f | grep -E '^(game/|extracted/)'` →
  none; no `game/data/generated`; no media under `build/`.
- Working tree clean at the first-pass HEAD (`074341f`, `git status --short`
  empty).
- Push state changed **during** this verification: at the start
  `git rev-parse origin/main` returned `912a481`; at 11:04:49 EST the reflog
  records `074341f … update by push`, and `git ls-remote origin
  refs/heads/main` confirms `074341f…`. The worker's “commits local, not
  pushed” was true at handoff (commits 11:01:39 / 11:02:02, push 11:04:49);
  the pushed tree is the same HEAD verified here. I ran no push. See §4.6.
- Fix commit `79d8b8a` (8 files): `.gitattributes`, the five citation/AGENTS
  docs, this verification report and `tools/gate_ratchet.json`; no `game/`,
  `extracted/`, `game/data/generated/`, `build/qa/**` or media path. HEAD is
  `79d8b8a`, `origin/main` is `074341f`, `79d8b8a` is not on `origin/main`
  (`git branch -r --contains 79d8b8a` is empty; `git ls-remote origin
  refs/heads/main` returns `074341f…`), and the working tree was clean before
  this report update.

### 2.6 Checks (check 6) — PASS after `79d8b8a`

| Sub-check | Result |
|---|---|
| `git diff --check 912a481..7681b1c` | **PASS** (exit 0) after `79d8b8a`; it was the one trailing-space failure before `.gitattributes` |
| `git diff --check` (worktree) | PASS (exit 0) |
| `git diff --check 912a481..HEAD` | PASS (exit 0) |
| `make check-greps` | PASS — `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=106` |
| route self-test | PASS — `P0B_ROUTE_SELFTEST PASS checks=62 fails=0` (`p0b_route_self_test.log:49–50`) |
| run wall/time | 19 m 49 s (`final-run.log:2` 10:35:15 → `perf_guard.log` / `gate_ratchet.log` 10:55:04); capture 207 s (`capture.log:375`) |
| route2-clean audio/peak | PASS — enabled, 186.259 s, peak −0.758 dBFS / rms −30.32 dBFS, corroborated by ffmpeg (−0.8 / −30.3 dB); see §4.4 for the drop caveat |

The one whitespace line is Godot's own warning text
(`WARNING: Nodes with non-equal opposite anchors …`) copied verbatim; the same
line already exists in the committed `route1/capture.log` and
`route2/capture.log` (added by `f44bc23`). `79d8b8a` exempts only the
trailing-space rule for `docs/reports/logs/**/capture.log` (`.gitattributes:5`)
and leaves the log bytes intact; the three `git diff --check` forms above now
all exit 0.

## 3. What is *not* claimed (checked, correct)

- No `game/` code, shader, generated data, producer or extractor change.
- The capture is still **staged**, `route_claim=none`, 13 captured / 14
  deferred; it is not a played route and has no 120-row or visual score.
- The Guildhall stage is the **free-play substitute**
  (`Mission.Guildhall.LootTheRoom`, contract 2;
  `official_free_play=false`), not the canonical
  `Mission.Guildhall.VaultHeist` selection.
- The perf matrix/VRAM numbers are not claimed; GPU samples are capture-only
  (47.13 °C / 1914 MiB before → 58.28 °C / 1914 MiB after).
- `beam_visible=true` is a presence flag at the authored card; the S24
  cream/exposure numbers in `FIDELITY_GAPS.md` are explicitly not re-scored.

## 4. Corrections (all three applied in `79d8b8a`)

### 4.1 `git diff --check` — RESOLVED

Godot's warning line in the new `capture.log` ends with a space. `79d8b8a`
added `.gitattributes:1–5`:

```
# Verbatim run logs are engine output, not hand-written text: Godot prints
# lines that end in a space, so `git diff --check` would flag every capture
# forever. Keep the bytes intact and exempt the logs from the trailing-space
# rule only (space-before-tab and other rules still apply).
docs/reports/logs/**/capture.log whitespace=-trailing-space
```

The route2-clean `capture.log` bytes are unchanged: `git hash-object` gives
`bbbcb1aea5a3a67f63f68b2afd5a0743a334b3f` (the `7681b1c` blob) and sha256
`fe9c529b5cfdd0bedb1d9d5f134ffc39d356eb0643e774142ba84c3c778af12c`.
`git diff --check 912a481..7681b1c`, `git diff --check` (worktree) and
`git diff --check 912a481..HEAD` all exit 0.

### 4.2 Old-evidence commit citation — RESOLVED

All six places (`final-20261127-phase0b.md`, `final-20261127.md`, `AGENTS.md`,
`FIDELITY_GAPS.md`, `HANDOFF_NEXT_AGENT.md`, `tools/gate_ratchet.json` source)
now state: measured at `5135f53`, committed on `main` at `3d62f6b`, replaced in
place at `912a481`; the exact path `docs/reports/logs/final/` is named, and the
pre-Phase-0b copies are pointed at `912a481` (four places add `3d62f6b`
explicitly; `AGENTS.md`/`HANDOFF` name `3d62f6b` as the commit). No “remain in
git history at commit `5135f53`” remains outside this report's own quotation
(§2.3).

### 4.3 Stale `measured_on` row in `AGENTS.md` — RESOLVED

`AGENTS.md:111` now reads ``PASS (`measured_on=912a481`; floors raised, never
lowered)``, matching the table header (line 85), `README.md:26` and
`tools/gate_ratchet.json:3`. No value or floor changed.

### 4.4 Audio drop caveat (documentation, not a defect)

`capture.log:371` reports `dropped=647168` frames in addition to the 8,214,016
written frames (186.259 s), i.e. ≈ 14.7 s of tap underruns. The WAV is real and
its level matches the manifest, but it is **not gap-free**; do not use it for
beat-accurate or audio-fidelity claims. One sentence in
`docs/reports/p0b-route.md` §route2-clean (and/or `final-20261127-phase0b.md`
§1) would close this.

### 4.5 Serial ratchet log name (optional clarity)

`docs/reports/logs/final/gate_ratchet.log` is the pre-stamp pass (old checker,
`measured_on=5135f53`, no route-self-test lines). The new floor is proven only
by `gate_ratchet_poststamp.log`. Consider keeping the post-stamp pass as
`gate_ratchet.log` and renaming the serial one `gate_ratchet_presstamp.log`, or
add a one-line pointer in `final-summary.txt`. `final-20261127-phase0b.md` §5
already explains it, so this is optional.

### 4.6 Push state (no action)

`origin/main` is `074341f` (the first-pass push at 11:04:49 EST moved
`912a481 → 074341f`); `79d8b8a` is local and **not pushed**. If the fix commit
should be remote, push it as a separate step; nothing in the verification
depends on it being on `origin`.

## 5. Residual risk

- **Staged, not played.** The route evidence remains 13 staged / 14 deferred,
  `route_claim=none`; the free-play substitute is not the official mission
  selection. Any later scorer must keep treating it as provenance only.
- **Audio quality.** 647,168 dropped frames; peak −0.758 dBFS is close to
  clipping. Levels are corroborated, continuity is not.
- **Renamed stale artifact.** `gate_ratchet.log` inside the 45-gate evidence
  directory reflects the old baseline; the new floor lives in
  `gate_ratchet_poststamp.log` (§4.5).
- **Fix commit is local only.** `79d8b8a` is on local `main`; `origin/main` is
  `074341f`. Until it is pushed, a fresh clone still sees the three pre-fix
  documents (wrong citation, stale `AGENTS.md` row, no `.gitattributes`). The
  measured evidence and every gate value are identical either way.
- **`uncommitted_entries_at_start` is not path-stamped.** The runner records the
  count only; identifying the one entry as route2-clean rests on `912a481`
  lacking that directory, the tracked tree matching HEAD and the capture
  timestamps, not on a logged path. The inference is strong but not direct.
- **Reproducibility boundary.** The 45 gates were measured once, serially, at
  `912a481`; the route capture is GPU/Xvfb-only and its PNGs are git-ignored,
  so a re-run needs the private extract and the same host class. The committed
  manifest/log is the durable evidence.

## 6. Commands used (for reproduction)

```bash
git show --stat 7681b1c 074341f 79d8b8a
git diff --name-only 912a481..074341f
git diff --name-only 074341f..79d8b8a
git diff 074341f..79d8b8a -- tools/gate_ratchet.json
git diff --check 912a481..7681b1c        # exit 0 after 79d8b8a
git diff --check 912a481..HEAD           # exit 0
identify -format '%f %wx%h %[colorspace]\n' build/qa/p0b_route/route2-clean/*.png
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels,duration \
  build/qa/p0b_route/route2-clean/audio.wav
ffmpeg -hide_banner -nostats -i build/qa/p0b_route/route2-clean/audio.wav \
  -af volumedetect -f null /dev/null
make check-greps
make gate-ratchet
make audit
```

## 7. Re-verification at `79d8b8a`

Re-run after the fix commit (2026-11-27, no GPU, no push):

| Check | Result |
|---|---|
| HEAD / tree | `79d8b8a2271681b54355f094c4a194a2d1ef9b69`; clean before this report update |
| `origin/main` | `074341f474b92602ba5e58863d661683dff30173`; `7681b1c` and `074341f` are ancestors, `79d8b8a` is not on the remote (`git ls-remote`; `git branch -r --contains 79d8b8a` empty) |
| evidence unchanged | `git diff --name-only 074341f..79d8b8a -- docs/reports/logs/ build/qa/ game/ extracted/ game/data/` → 0 files; `gate_ratchet.json` `gates`/`evidence`/`measured_on`/`report` identical (only `source` prose) |
| `git diff --check` | `912a481..7681b1c`, worktree and `912a481..HEAD` all exit 0 |
| `make check-greps` | PASS — `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=106` |
| `make gate-ratchet` | PASS — `GATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run locally)`; `PASS: report names measured_on=912a481` |
| `make audit` | PASS — `AUDIT PASS`; disk-backed coverage `12660/12703`, unexpected 0 |
| route self-test | unchanged `P0B_ROUTE_SELFTEST PASS checks=62 fails=0` |

`make audit` and `make gate-ratchet` write no tracked files; the only dirty
path after this update is this report.
