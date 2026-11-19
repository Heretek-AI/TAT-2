# TAT-2 Reference Baseline — execution plan

Goal: complete `docs/HANDOFF_OMO_ULW_REFERENCE_BASELINE.md` end to end; all §8 gates green.

## Wave 0 — preflight (DONE)
- `render_annotations.py --check` → 30/30 OK (exit 0)
- `m2_audit_validate.py` → ALL CHECKS PASSED (exit 0)
- Read `BREAKDOWN.md` S01–S04 template; recorded exact segment boundaries S05–S27 from `KEYFRAME_INDEX.md` §2.

## Wave 1 — data gathering (RUNNING, run `dag_f77ebc9b`)
- `audio-s05-s27` (retry attempt 2, running) → `_build/audio_s05_s27.md`
- `citations` (retry attempt 2, running) → `_build/citations_verified.md`
- `seg-s05-s13` DONE + verified (9 segs, 63 subsections, filenames real, BGM explicit, no threat-arc)
- `seg-s14-s20` DONE + verified (7 segs, 49 subsections)
- `seg-s21-s27` DONE + verified (7 segs, 49 subsections)
- Known Wave2 fix: `docs/...md:` placeholder citation in `seg_s05_s13.md` must be replaced with a real path.

## Wave 2 — merge + baseline (NEXT, new run `tat2-baseline-wave2`)
- `merge-breakdown`: append S05–S27 to `BREAKDOWN.md` after S04; fix placeholder citation; enforce HUD glossary + `Seg[n].End == Seg[n+1].Start`; VERIFY by running checks 1+2 of the (Wave3) verifier spec manually via grep.
- `author-baseline`: write `docs/REFERENCE_BASELINE.md` (all 10 §6.2 sections; ≥60-row 4-pillar checklist; every S01–S27 ≥1x; Port columns blank) using `_build/citations_verified.md` + `BREAKDOWN.md`.
- Depends on: Wave1 `audio_s05_s27.md` + `citations_verified.md` existing (merge node treats missing file as FAIL).

## Wave 3 — scorecard + verifier (RUNNING as `tat2-baseline-wave3b`, run `dag_92d96509`; note: key `tat2-baseline-wave3` burned by a refused `writing`-category definition, fresh key used)
- `scorecard`: `COMPARISON_TEMPLATE.md` (mirror §8 checklist 1:1, 27 image slots + alignment rows + summary) + `tools/make_side_by_side.sh` (usage with 0 args, refuses missing files, `bash -n` clean).
- `verifier`: `tools/verify_baseline.py` (`/usr/bin/python3`, stdlib+Pillow only, 8 checks per §6.3).

## Wave 4 — adversarial QA + cleanup (RUNNING as `tat2-baseline-wave4`, run `dag_ac74eabe`)
- Pre-checks by lead: verify_baseline.py 8/8, m2_audit_validate.py, render --check 30/30.
- 2 parallel verifier nodes (read-only + Verification-log append by ONE writer node to avoid collisions):
  - `adv-visual-hud` (unspecified-low): spot-check >= 6 visual claims vs 4K frames/contact sheets + >= 3 HUD-verbatim claims vs clean/annotated KFs; writes _build/adv_visual_hud.md (Claim -> Evidence Command -> Verdict rows).
  - `adv-audio-time` (unspecified-low): spot-check >= 3 audio dBFS claims (re-run ffmpeg astats/ebur128 slices in fresh mktemp, compare) + >= 2 gameplay-timing claims; writes _build/adv_audio_time.md.
  - `adv-cite-image` (quick): re-open >= 6 annotated images (badge/label accuracy) + >= 8 repo citations (file:line); writes _build/adv_cite_image.md.
  - `verify-log` (quick, dependsOn the three): appends all rows into docs/REFERENCE_BASELINE.md ## Verification log with counts (must reach >= 12 claims / >= 6 images / >= 8 citations) WITHOUT touching any other section.
- `cleanup` (quick, dependsOn verify-log): deletes docs/reference/clip_1795033698901/_carryover/, _build/seg_*.md, _build/audio_*.md, _build/citations_*.md, _build/adv_*.md (keeps m2_audit_validate.py); rm -rf temp dirs; re-runs verify_baseline.py AFTER cleanup and reports 8/8 PASS; records teardown receipts (kill -0 / tmux ls / lsof checks).
- Run `verify_baseline.py` + `m2_audit_validate.py` + `render --check` myself.
- 2–3 read-only verifier children: ≥12 claim spot checks (4 visual / 3 HUD-verbatim / 3 audio-dBFS / 2 gameplay), ≥6 image re-opens, ≥8 citation re-opens → `## Verification log`.
- Delete `_carryover/` + `_build` staging (`seg_*.md`, `audio_*.md`, `citations_*.md`); `rm -rf $T`; re-run `verify_baseline.py` after cleanup.

## Final gate (§8, all exit 0 / thresholds)
`verify_baseline.py` 8/8 PASS; `render --check` 30/30; `bash -n` side-by-side;
`grep -c '^## S'` = 27; `du -sh` ≤ 25M; no `_carryover/`; `git diff --stat -- game tools build extracted` empty;
`## Verification log` counts ≥12/≥6/≥8.
