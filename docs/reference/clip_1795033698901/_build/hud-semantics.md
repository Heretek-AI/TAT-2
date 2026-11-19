# HUD Semantics Correction — Evidence (`hud-semantics`, run `20261118-185627-d692`)

Normative rule (user-confirmed): the bottom-centre **Light Gem** shows light on the player + direction
(lit-sector size = amount, sector position = direction; bright = exposed, dark = concealed; NOT a
detection meter). The **red arcs** flanking it show player noise level (large/bright = loud, absent =
quiet; NOT enemy threat/detection, do not track guard proximity). `KF17#4` is a different element (a
guard-perception alert pip away from the gem).

## Every callout change (old → new)

### KF14 (`01:15.75`) — 7 → 8 callouts
- #6 UI5 `Light Gem & Arcs` → #6 UI3 `Lit Light Gem` (gem target kept `[958,998]`/anchor `[1140,975]`).
  Old detail: "…flanked by faint red directional threat arcs." / New: "…glowing warm cream-white
  (lit sector upper-left, lantern side; exposed, not concealed). Faint red player-noise arcs flank it
  (right arc brighter)…; NOT a detection meter."
- NEW #7 UI5 `Faint Noise Arcs`, target `[828,1002]` (left arc), anchor `[800,948]` pill_left. Detail
  states player-noise meaning with the safe-room footstep context.
- Old #7 (AU6 Nisha VO) → #8, content unchanged.

### KF15 (`01:21.38`)
- #4 UI3 `Shadowed Dark Light Gem`: "…with zero threat arcs." → "…with no red player-noise arcs
  (quiet alley-drop approach; silent at this instant)."

### KF16 (`01:40.20`)
- #5 UI3 `Half-Lit Light Gem`: detail now states lit sector left / indigo right, partial
  headlight/streetlamp exposure, no red player-noise arcs (quiet aim/equip moment).

### KF17 (`01:51.20`) — 5 → 6 callouts
- #4 UI5 `Red Directional Threat Pip` → `Guard Alert Direction Pip`. Detail now identifies it as a
  guard-perception alert pip (NOT gem noise arcs; no gem arcs present), coinciding with the guard shout
  "Oh, I will find you, thief!".
- NEW #6 UI3 `Dark Concealed Light Gem`, target `[960,1000]`, anchor `[1130,975]` pill_right. Gem fully
  dark indigo, no noise arcs (quiet crank-aim moment).

### KF18 (`02:14.80`) — 6 → 7 callouts
- #6 UI5 `Intense Red Threat Arcs` → #6 UI3 `Shadowed Light Gem` (target gem `[960,1002]`, anchor
  `[720,985]` pill_left). Mostly dark indigo, small cream lit sector upper-left.
- NEW #7 UI5 `Bright Noise Arcs`, target right arc `[1130,985]`, anchor `[1300,985]` pill_right. Detail
  ties arcs to ZipWire traversal ratchet clicks (`02:13.4–02:15.1`), not guard proximity.

### KF19 (`02:25.40`)
- #6 UI3 `Warm-Lit Light Gem`: lit sector upper-left, no red player-noise arcs (quiet walk holding the
  Smoke Bomb; Guard VO "Hey! Show yourself!" noted).

### KF20 (`02:29.20`) — 5 → 6 callouts
- #4 UI5 `Intense Red Threat Arcs` → #4 UI3 `Lit Light Gem` (target `[958,1000]`, anchor `[660,975]`
  pill_left). Lit cream-white, lit sector upper-left.
- NEW #5 UI5 `Loud Noise Arcs`, target left arc `[720,980]`, anchor `[500,980]` pill_left → moved to
  target `[1195,980]` / anchor `[1330,980]` pill_right after `--check` collision. Detail ties arcs to the
  detonation pop + hiss (`02:28.3–02:29.8`, `pk=-20.5 dBFS`).
- Old #5 (UI2 THROW prompt) → #6, content unchanged.

### KF21 (`02:32.20`) — 6 → 7 callouts
- NEW #7 UI3 `Dark Concealed Gem`, target `[960,990]`, anchor `[750,975]` pill_left. Dark indigo, small
  white highlight upper-left, no arcs (quiet Vistara scan moment).

### KF22 (`02:33.00`) — 5 → 6 callouts
- NEW #6 UI3 `Dark Concealed Gem`, target `[960,990]`, anchor `[1120,1015]` pill_right (anchor moved down
  after `--check` badge/pill collision with #5). Dark, quiet ZipWire re-equip moment.

### KF23 (`02:41.00`) — 6 → 7 callouts
- NEW #7 UI3 `Dark Concealed Gem`, target `[960,990]`, anchor `[1120,975]` pill_right (right-side badge to
  avoid #6 pill collision). Dark, quiet balcony traversal.

### KF24 (`03:00.60`) — 5 → 6 callouts
- #5 UI5 `Light Gem Threat Arcs` → #5 UI3 `Fully Lit Light Gem` (target `[960,1000]`, anchor `[780,970]`
  pill_left). Fully lit, exposed.
- NEW #6 UI5 `Small Noise Arcs`, target right arc `[1060,1010]`, anchor `[1200,1010]` pill_right. Faint at
  this quiet door-approach instant (before latch click `03:01.0–03:02.2`).

### KF25 (`03:16.80`)
- #6 UI3 `Exposed Bright Light Gem`: "without red alert arcs" → "with no red player-noise arcs (quiet
  crouch before the `03:17.10` pickpocket)".

### KF26 (`03:20.20`)
- #5 UI3 `Bright Parlor Light Gem`: added "no red player-noise arcs visible at this instant" (takedown).
- #3 UI5 `Active Takedown Hold Arc` KEPT (hold-progress ring = countdown-like feedback; see UNCERTAIN).

### KF27 (`03:27.60`) — 8 → 9 callouts
- NEW #8 UI3 `Half-Lit Light Gem`, target `[960,1005]`, anchor `[740,975]` pill_left. Half-lit cream
  upper-left, dark indigo lower-right.
- Old #8 → #9 UI5 `Threat Arcs Active` → `Bright Noise Arcs`, target outer right arc `[1185,1000]`,
  anchor `[1330,1000]` pill_right. Detail: twin inner + outer pairs flare with marble footsteps
  (`pk=-28.9 dBFS`), track player noise not guard proximity.
- NOTE: 9 callouts exceeds the "4–8 target" in handoff §4.1; kept because the spec requires both a UI3
  gem callout and a UI5 arcs callout whenever each element is visible, and both are visible here.

### KF28 (`03:35.00`) — 7 → 8 callouts
- NEW #8 UI3 `Half-Lit Light Gem`, target `[960,1000]`, anchor `[740,985]` pill_left. Half-lit cream
  upper-left, dark lower-right, no arcs at this instant.

### KF29 (`03:39.40`) — 5 → 6 callouts
- NEW #6 UI3 `Fully Lit Light Gem`, target `[890,1012]`, anchor `[620,975]` pill_left. Fully lit under the
  crimson alarm spotlight, no arcs at this ascent instant.

### KF30 (`03:43.20`) + KF08 (`00:28.50`) — audit code fixes
- KF30#3 UI5 → UI1 `QUIT TO DESKTOP Hover` (pause-menu hover is a front-end menu element, not an alert).
- KF08#5 UI5 → UI4 `Chameleon Cosmetics` (full-screen panel column, not an alert).

### Supporting file changes
- `tools/render_annotations.py`: UI5 taxonomy "pips, threat arcs, alarms, countdowns" → "guard-alert
  pips, player-noise arcs, status icons, alarms, countdowns"; UI3 taxonomy gains "light gem"; `emit_legends`
  header gains the `## HUD semantics glossary (user-confirmed)` block so regeneration cannot drop it.
- `CALLOUT_LEGENDS.md`: regenerated with `--emit-legends` only (rows not hand-edited); 30/30 parity OK.
- `tools/merge_callout_specs.py`: docstring guard note + `--write` now REFUSES to overwrite an existing
  schema-1.1 spec (exit 2; verified: "VALID: 30 keyframes, 173 callouts / REFUSED …"). Stale
  CODE_OVERRIDES numbering/wording can no longer clobber the corrected spec.
- `KEYFRAME_INDEX.md`: §2 S13/S18/S20/S26 + §3 KF17/KF18/KF20 reworded; §5.2 gained a bottom-center
  Light Gem + noise-arcs bullet; `## Errata` appended (8 entries, `2026-11-19T00:09:10Z`).

## Per-KF HUD audit disposition (all 30 frames)

Method: opened every clean JPEG showing gameplay HUD (KF14–KF29) and reviewed every HUD/UI callout label,
code and detail in `callout_spec.json` against the frame and the normative semantics.
- KF01: UI1 menu stack OK. No gem (startscreen). PASS.
- KF02: UI3 player card + compass OK. No gem (den vista). PASS.
- KF03: UI4 panels ×4 OK. No gem (wardrobe). PASS.
- KF04: UI4/UI2 panels OK. No gem (wardrobe). PASS.
- KF05: UI2 `[F] EXIT` OK. No gem (telescope view). PASS.
- KF06: UI3 player card OK. No gem visible. PASS.
- KF07: UI4 journal panels OK. No gem. PASS.
- KF08: UI4 panels OK; #5 recoded UI5→UI4 (fix applied). #6 AU4 OK. PASS after fix.
- KF09: UI2 `[F] TURN OFF` OK. No HUD gem (floating diamond is a look-target, not the HUD gem). PASS.
- KF10: UI4 map card, UI2 enter prompt, UI3 legend OK. No gem. PASS.
- KF11: UI5 6s countdown OK (countdowns are UI5 per taxonomy), UI4 cards OK. No gem. PASS.
- KF12: UI4 spinner + emblem OK. No gem (loading). PASS.
- KF13: UI4 letter panels OK. No gem (briefing). PASS.
- KF14: fixed + split (see above). PASS.
- KF15: fixed wording (see above). PASS.
- KF16: fixed wording (see above). PASS.
- KF17: pip renamed + gem added (see above). PASS.
- KF18: fixed + split (see above). PASS.
- KF19: fixed wording (see above). PASS.
- KF20: fixed + split (see above). PASS.
- KF21: gem added (see above); other HUD (health, slot, THROW) OK. PASS.
- KF22: gem added (see above); other HUD OK. PASS.
- KF23: gem added (see above); compass OK. PASS.
- KF24: fixed + split (see above); `[F]` prompts OK. PASS.
- KF25: fixed wording; `[F]` prompts OK. PASS.
- KF26: gem fixed; #3 hold-arc kept (see UNCERTAIN). PASS with note.
- KF27: gem added + arcs rewritten (9 callouts, justified above). PASS with note.
- KF28: gem added; jaw-trap + unconscious icons correctly UI5. PASS.
- KF29: gem added; jaw-trap icon correctly UI5; CRANK reticle UI2 OK. PASS.
- KF30: #3 recoded UI5→UI1 (fix applied); other UI1/AU4 OK. No gem (pause). PASS.

## UNCERTAIN items
- KF26#3 `Active Takedown Hold Arc` (UI5): the clean frame shows the `[F] [HOLD] TAKEDOWN` prompt but the
  circular hold-progress arc itself is not clearly resolvable at 1080p. Kept as-is (hold-progress reads as
  countdown-like UI5 feedback); verifier should confirm against the 4K source frame at `03:20.20`.
- Light-direction wording stays at sector-position level (e.g. "lit sector upper-left"); no compass direction
  of the light source is claimed beyond what the gem face shows.

## Local checks (real output)
- `/usr/bin/python3 …/render_annotations.py --check`: exit 0, all 30 KF lines OK (0 failures; 3 collisions
  found and fixed during iteration: KF20#5, KF22#6, KF23#7 anchors).
- `--emit-legends`: WROTE CALLOUT_LEGENDS.md; legends row counts == spec counts for all 30 KFs (184 total).
- Forbidden-phrase grep (case-insensitive) over `callout_spec.json`, `CALLOUT_LEGENDS.md`,
  `KEYFRAME_INDEX.md`: matches only inside the `## Errata` old-text quotes (explicitly allowed) and in
  `_carryover/` scratch drafts (owned by m4-final; untouched).
- `du -sh docs/reference/clip_1795033698901`: 16 MiB (≤ 25 MiB).
- `find annotated -name '*.jpg' -size +750k`: no output (largest re-render 535 KB).
- `merge_callout_specs.py --write`: REFUSED with exit 2 (guard works; spec untouched).
- Re-rendered all 18 frames whose specs changed
  (KF08, KF14, KF15, KF16, KF17, KF18, KF19, KF20, KF21, KF22, KF23, KF24, KF25, KF26, KF27, KF28, KF29, KF30).
  11 produced new bytes (label/geometry changes); 7 are byte-identical (detail-text-only or code-only
  changes: badge colour follows category, and both recodes stayed inside HUD/UI cyan).
  Spot-checked annotated KF14, KF20, KF22, KF27 visually: badges/pills readable, leaders land on the gem /
  the correct arc, nothing covers HUD elements, legend strips present where placed.

## For the verifier (attack these)
- Confirm KF17's three dashes are a guard-alert pip and not gem noise arcs (gem dark, no gem arcs in frame).
- Confirm KF26#3's hold-progress arc against the 4K frame at `03:20.20`.
- Confirm KF27 really needs 9 callouts (gem + arcs both visible; nothing else safe to merge).
- Re-run `--check`, the forbidden-phrase grep, id-contiguity/label-length/bounds validation, and legend
  parity independently; re-open any 2–3 annotated frames of your choice.
- Confirm `clean/*.jpg` untouched and no edits outside
  `docs/reference/clip_1795033698901/{callout_spec.json,CALLOUT_LEGENDS.md,KEYFRAME_INDEX.md,tools/,annotated/}`.
