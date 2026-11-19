# M2 audit log (worker: m2-audit)

## 1. Validator

Checked-in validator: `docs/reference/clip_1795033698901/_build/m2_audit_validate.py`.
It checks every handoff section 4.1 rule: `schema_version == "1.1"`, dict keys
exactly `KF01..KF30`, filename exists in `clean/`, ids exactly `1..N`, target
and anchor inside `safe_bounds [16,16,1904,1064]`, label at most 4 words,
category in palette, code in the section-4.2 taxonomy, category matches code
prefix, timestamp/segment/filename identical to `KEYFRAME_INDEX.md` section 3,
4-8 callouts (9 fails unless a justification is recorded in the script),
at least one `HUD/UI` callout per KF, at least one AU-code callout whose
detail names the audio state (explicit BGM presence/absence), plus legend
parity (30 sections, row counts equal spec callout counts).

- Run 1 (pre-fix): 15 FAILURES — no AU-code callout on KF02, KF06, KF10, KF15,
  KF16, KF18, KF19, KF21, KF22, KF24, KF25, KF27, KF28, KF29; KF27 had 9
  callouts with no justification. All schema/coordinate/label/category/code/
  timestamp checks passed, legend parity passed.
- Run 2 (post-fix, post `--emit-legends`): `ALL CHECKS PASSED` (30 KFs,
  195 callouts total).

Fixes were applied by `_build/m2_apply_fixes.py`, which first proved a
no-change `json.dump(indent=2, ensure_ascii)` round-trip is byte-identical to
the committed file, then applied surgical fixes and rewrote it.

## 2. Fixes made (KF, id, old -> new, reason)

ADDs (one AU-code callout each, explicit audio state incl. BGM absence):
- KF02 #7 AU1 `Quiet Den Room Tone` (new; Den room tone, no BGM).
- KF06 #7 AU3 `Quiet Den Footsteps` (new; footfalls + Ledger click, no BGM).
- KF10 #7 AU4 `Map Toggle Clicks` (new; toggle clicks + confirm chime, no BGM).
- KF15 #6 AU3 `Wet Cobble Footsteps` (new; rain + footfalls/splashes, no BGM).
- KF16 #7 AU6 `Guard Alert VO` (new; "I know someone's here!", no BGM).
- KF18 #8 AU5 `Cable Ratchet Clicks` (new; ratchet clicks, no BGM).
- KF19 #7 AU6 `Guard Shout VO` (new; "Hey! Show yourself!", no BGM).
- KF21 #8 AU5 `Diamond Scan Shimmer` (new; scan chime, no BGM).
- KF22 #7 AU5 `Re-Equip Click (No BGM)` (new; re-equip click, no BGM).
- KF24 #7 AU5 `Door Latch & Creak` (new; latch + creak, no BGM).
- KF25 #7 AU1 `Hearth Crackle (No BGM)` (new; crackle bed, no BGM).
- KF29 #7 AU5 `Shatter Sting & Climb` (new; shatter sting + climb SFX, no BGM).
- KF27 #8 AU3 `Marble Footstep Sequence` (new; marble footfalls, no BGM).
- KF28 #8 AU5 `Ward Tripwire Chime` (new; tripwire chime + ward hum, no BGM).

MERGEs (over-limit KFs; no element left undescribed):
- KF27 9 -> 8: old #1 + old #2 merged into new #1 G5 `Wall Emitter & Beam`
  (emitter projects the beam; one causal element); old #3 + old #6 merged
  into new #2 V4 `Case & Floor Plate` (both static foyer dressing; plate
  coordinates kept in detail as `x~910, y~608`); old #4..#5/#7..#9
  renumbered to #3..#7 unchanged.
- KF28 8 -> 8 with AU: old #6 + old #7 merged into new #6 UI5
  `Status Icons Above Gem` (target `[965,806]` on the two-icon cluster;
  both icons and both timestamps kept in detail); old #8 renumbered to #7.
- KF15 #1 bbox `[8,100,845,610]` -> `[8,210,845,610]` (old box enclosed the
  top-left HUD loot-tracker text; new box starts below it).

## 3. Determinism proof

- Copied `docs/reference/clip_1795033698901/` to literal
  `/tmp/opencode/m2-render/clip_1795033698901/`, ran
  `tools/render_annotations.py` there: all 30 outputs byte-identical
  (`cmp`) to the committed `annotated/` files (0 DIFFER lines);
  spot SHA-256 equal (KF01 `e7e7aeee...54455c2c` both sides).
- Regenerated legends in the temp copy with `--emit-legends`: `diff`
  against committed `CALLOUT_LEGENDS.md` is clean.
- The real `annotated/` dir was never written during the check (render ran
  only inside the temp copy).

## 4. Renderer `--check`

Exit 0, all 30 frames `OK` (collision/bounds/hud_exclusions). Legend
corners: BR x13, TR x4, BL x2, TL x2, None x9 (KF19-KF29 omit the strip
rather than cover HUD, allowed per spec).

## 5. Per-KF visual QA disposition (every annotated frame opened; clean frame opened where noted)

| KF | Disposition |
|----|-------------|
| KF01 | PASS, unchanged. #4 on guard torso, #6 on car fender, #5 on puddle; readable; legend BR clear. |
| KF02 | PASS after fix. Re-checked new #7: badge/pill on dark floorboards, leader ends by newspapers; readable. |
| KF03 | PASS, unchanged. #7 magenta on slot-1 tick area; legend TR clear. |
| KF04 | PASS, unchanged. #2 magenta ends on slot-4 diamond under cursor. |
| KF05 | PASS, unchanged. #4 exactly on `[F]` glyph. |
| KF06 | PASS after fix. Re-checked new #7 on dark floorboards; readable. Accepted minor: legend BR overlaps bottom edge of #5 poster bbox (`REWARD` row); every other corner collides, key poster text visible. |
| KF07 | PASS, unchanged (has AU4 #6). |
| KF08 | PASS, unchanged (has AU4 #6 on `BACK [ESC]`; leader crosses BACK text but text stays readable). |
| KF09 | PASS, unchanged (has AU2 #1 on gramophone horn). |
| KF10 | PASS after fix. Re-checked new #7 top-left, leader ends on open parchment; readable. |
| KF11 | PASS, unchanged (has AU4 #6 on READY). |
| KF12 | PASS, unchanged (has AU1 #5 on empty sky — correct for silence). |
| KF13 | PASS, unchanged (has AU3 #5 on CONTINUE). |
| KF14 | PASS, unchanged (has AU6 #8; gem + faint noise arcs correct). |
| KF15 | PASS after fix. Bbox no longer touches HUD loot text; new #6 leader ends on wet cobbles/puddle; readable. |
| KF16 | PASS after fix. Re-checked new #7: leader ends at guard alert bar; readable. |
| KF17 | PASS, unchanged (has AU5 #5; UI5 #4 is the guard-alert pip, correct semantics). |
| KF18 | PASS after fix. Re-checked new #8 on cable above reticle; legend moved None -> BR, sits over dark fence, covers nothing. |
| KF19 | PASS after fix. Re-checked new #7: leader ends mid-courtyard toward steps; readable. |
| KF20 | PASS, unchanged (has AU5 #2 on smoke puff). |
| KF21 | PASS after fix. Re-checked new #8: leader ends on lower diamond facet; readable. |
| KF22 | PASS after fix. Re-checked new #7: leader ends on ZipWire arm; readable. |
| KF23 | PASS, unchanged (has AU1 #6). |
| KF24 | PASS after fix. Re-checked new #7: leader ends on door handle plate; readable. |
| KF25 | PASS after fix. Re-checked new #7 on parquet floor; readable. |
| KF26 | PASS, unchanged (has AU5 #4). |
| KF27 | PASS after fix. Re-checked merged #1 (emitter), merged #2 (case statue), renumbered #3-#7, new #8 on checkered floor; all readable. |
| KF28 | PASS after fix. Re-checked merged #6 (icon cluster target between the two icons), new #8 (ward); readable. |
| KF29 | PASS after fix. Re-checked new #7 on crimson stairs; readable. |
| KF30 | PASS, unchanged (has AU4 #4). |

Re-done frames (spec changed + re-rendered + re-checked): KF02, KF06,
KF10, KF15, KF16, KF18, KF19, KF21, KF22, KF24, KF25, KF27, KF28, KF29.
Unchanged frames (byte-identical renders, QA from pass 1 stands): KF01,
KF03, KF04, KF05, KF07, KF08, KF09, KF11, KF12, KF13, KF14, KF17, KF20,
KF23, KF26, KF30.

## 6. HUD correction intact

`grep -rn -i 'threat arc\|alert arc\|threat pip'` over `callout_spec.json`,
`CALLOUT_LEGENDS.md`, `BREAKDOWN.md`, `render_annotations.py`: no matches.
Light Gem = light exposure + direction (UI3); red arcs = player noise
(UI5); KF17 guard-alert direction pip is a separate element. Not reverted.

## 7. Hygiene and sizes

- Deleted `tools/.probe2` and `tools/.write_probe` (via `git rm`); `find`
  for dotfiles under the clip dir returns nothing else.
- `du -sh docs/reference/clip_1795033698901` = 16 MiB (<= 25 MiB).
- No annotated JPEG over 750 KB (max KF08 548,787 B; all encoded q=90 ss=0).
- `clean/*.jpg` untouched; changes confined to
  `docs/reference/clip_1795033698901/` (spec, legends, 14 re-rendered
  annotated JPEGs, probe deletions, `_build/` evidence).

## 8. Validator output (final)

`checked 30 keyframes / ALL CHECKS PASSED` (exit 0).
Renderer `--check` exit 0, 30/30 OK.

## 9. Round 2 (retry after verified_fail: explicit-bgm-audio-state-4kf)

Verifier round 1: 13/14 PASS. Fatal: KF11 AU4, KF13 AU, KF20 AU5, KF26 AU5
named concrete sounds but never stated BGM absence, while KEYFRAME_INDEX
section 2 rows S09/S11/S18/S23 mandate Explicit Absence no BGM and handoff
4.1 requires explicit No BGM when there is none. The checked-in validator
falsely passed these 4 (its per-AU keyword list accepted any concrete
sound), so it was tightened (see below).

Fixes (in-place detail edits only; labels/ids/targets/anchors/counts
unchanged; 195 callouts total, still 4-8 per KF):
- KF11 #6 AU4 `Ready & Countdown Ticks`: old `... 6 percussive UI ticks at
  1.00 s intervals (00:59.0-01:04.0).` -> new `... (00:59.0-01:04.0).
  Explicit BGM Absence.` Reason: S09 mandates Explicit Absence no BGM.
- KF13 #5 AU3 `Continue & Paper Rustle`: old `... crisp paper rustle
  (01:09.5-01:10.3) over exterior rain.` -> new `... over exterior rain.
  Explicit BGM Absence; no VO narration.` Reason: S11 mandates Explicit
  Absence no BGM or VO narration.
- KF20 #2 AU5 `Detonation & Smoke Hiss`: old `... followed by guard cough
  & VO.` -> new `... followed by guard cough & VO. Explicit BGM Absence.`
  Reason: S18 mandates Explicit Absence no BGM.
- KF26 #4 AU5 `Takedown Lunge & Impact`: old `... blunt KO thud + groan
  (03:20.6-03:21.5, pk=-22.1 dBFS).` -> new `... (03:20.6-03:21.5,
  pk=-22.1 dBFS). Explicit BGM Absence.` Reason: S23 mandates Explicit
  Absence no BGM.
- KF17 #5 AU5 `Ratchet Crank Audio Cue` (additional, same defect class,
  caught by the tightened validator, not by the verifier's grep): old
  `... rhythmic ratchet hand-cranking SFX (01:56.1-02:01.2, pk=-22.2
  dBFS) during roof climb.` -> new `... during roof climb. Explicit BGM
  Absence.` Reason: S15 mandates Explicit Absence no BGM; pre-fix block
  grep for bgm/music/silence/room-tone/noise-bed returned 0 hits.

Validator tightening (`_build/m2_audit_validate.py`): added
`EXPLICIT_BGM_KEYWORDS = [bgm, music, silence, room tone, room-tone,
noise bed, noise-bed]` plus a per-KF block-level check that fails when
zero callout details in the block mention any of them. Pre-fix this check
fails on KF11/KF13/KF17/KF20/KF26; post-fix run: `checked 30 keyframes /
ALL CHECKS PASSED` (exit 0). The old per-AU AUDIO_STATE_KEYWORDS check is
kept (still passes; it names concrete audio states).

Legends + renderer: `--emit-legends` re-ran (5 detail rows updated in
`CALLOUT_LEGENDS.md`); `--check` exit 0, 30/30 OK (corners unchanged:
BR x13, TR x4, BL x2, TL x2, None x9).

Determinism re-proof: on-image legend strips carry only
KF/timestamp/segment/color-key and pills carry labels, so detail-only
edits cannot change pixels; proved by full-tree copy render + cmp:
copied `clip_1795033698901/` to an isolated temp copy, ran the renderer
there, `cmp`ed all 30 `annotated/*.jpg` against the committed files: 0
DIFFER lines; `--emit-legends` in the temp copy `diff`-clean against the
committed `CALLOUT_LEGENDS.md`. No in-place re-render was needed and the
real `annotated/` dir was never written. (Sandbox note: `mktemp -d` paths
and `rm -rf` outside the workspace are blocked, so the temp copy lived at
a workspace-local `_tmp_r2/clip/` and was fully removed afterwards with
plain `rm` + `rmdir`; final `git status` shows no trace of it.)

Per-KF QA: all 30 annotated JPEGs are byte-identical to the round-1
visually-QA'd files, and no label/target/anchor/bbox/id/count changed, so
every round-1 disposition in section 5 stands unchanged (the 5 edited KFs
keep PASS: KF11/KF13 QA'd AU pill positions unchanged; KF17 merged-pill
and gem/pip semantics unchanged; KF20/KF26 smoke/takedown pills
unchanged). Re-done frames this round: none (no pixels changed).

Hygiene + sizes re-confirmed: `du -sh` = 16 MiB (<= 25 MiB); 0 annotated
JPEGs over 750 KB; 195 `"label":` lines in spec (+0); probe files still
absent (`tools/` holds only `merge_callout_specs.py` +
`render_annotations.py`); scoped forbidden-phrase grep over spec +
legends + BREAKDOWN + renderer = 0 matches (remaining repo-wide hits are
pre-existing KEYFRAME_INDEX errata quotes, `_build` evidence, and
`_carryover` history); `clean/*.jpg` untouched; diff confined to the clip
dir (spec + legends + validator + this log).
