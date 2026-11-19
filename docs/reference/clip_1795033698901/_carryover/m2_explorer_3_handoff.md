# Handoff Report — Explorer 3 (`KF21–KF30` Callout Coordinate Spec)

**Core Summary:** Inspected all 10 clean `1920x1080` keyframes `KF21–KF30`, verified exact pixel coordinates for HUD exclusion zones and scene features via `/usr/bin/python3`, and produced `callout_spec_kf21_30.json` containing **57 callouts** across `KF21–KF30` (`5–8` per frame) with **0** boundary, overlap, HUD-occlusion, or leader-crossing errors.

---

## 1. Observation

1. **Source Inputs Verified (`1920x1080` RGB):**
   - Visual inspection via `read_file` and `/usr/bin/python3` `PIL.Image` check confirmed all 10 files in `/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/clean/` are `1920x1080` RGB JPEGs:
     - `KF21_02m32s_vistara_diamond_red_guard.jpg` (`02:32.20`, `S19`)
     - `KF22_02m33s_vistara_diamond_green_guard.jpg` (`02:33.00`, `S19`)
     - `KF23_02m41s_side_wing_macleod_sign.jpg` (`02:41.00`, `S20`)
     - `KF24_03m00s_locked_blue_double_doors.jpg` (`03:00.60`, `S21`)
     - `KF25_03m16s_parlor_pickpocket_takedown.jpg` (`03:16.80`, `S22`)
     - `KF26_03m20s_parlor_guard_takedown.jpg` (`03:20.20`, `S23`)
     - `KF27_03m27s_foyer_security_beam.jpg` (`03:27.60`, `S24`)
     - `KF28_03m35s_foyer_arcane_barriers.jpg` (`03:35.00`, `S25`)
     - `KF29_03m39s_stairs_crimson_alarm.jpg` (`03:39.40`, `S26`)
     - `KF30_03m43s_pause_menu.jpg` (`03:43.20`, `S27`)
2. **Measured Gameplay HUD Exclusion Boxes (`1920x1080`):**
   - `top_left_hud` (Health Bar + `(£) 0` + `Mission: Steal 4,000 in loot value[0/4,000]`): `(34, 24, 524, 191)` -> padded box `[30, 20, 535, 200]`.
   - `top_center_compass`: ticks/cardinals at `y=40..74`, `x=645..1318` -> padded box `[620, 20, 1300, 85]`.
   - `top_right_card` (`Johnny Cipher` portrait + level `4`): `(1615, 26, 1891, 157)` -> padded box `[1605, 20, 1900, 165]`.
   - `bottom_left_hotbar` (`[1] [2] [4]` + `[TAB] MAP [MMB] [HOLD] PING MENU` + `Guildhall Key` when acquired): `(10, 870, 317, 1069)` -> padded box `[10, 865, 330, 1070]`.
   - `bottom_center_gem` (Light Gem + red threat arcs): `(830, 930, 1089, 1057)` -> padded box `[825, 930, 1095, 1065]`; status icons above gem (`KF28` jaw-trap `[920, 783, 957, 830]`, `xx/zz` `[975, 784, 1009, 834]`; `KF29` jaw-trap `[938, 783, 983, 830]`).
   - `bottom_right_prompt` (`THROW [LMB]` or `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`): `(1677, 953, 1873, 1064)` -> padded box `[1670, 950, 1900, 1068]`.
3. **Measured Feature Target Coordinates (Representative Highlights):**
   - `KF21`: Red health fill centroid `(233, 56)`; portico red guard silhouette `(960, 678)` (red-biased span `x=948..974, y=645..721`); Vistara Diamond `(1458, 666)` (`bbox [1333, 551, 1614, 803]`).
   - `KF22`: Green guard silhouette `(891, 598)` (`bbox [880, 572, 902, 634]`); warm courtyard golden glint `(1046, 789)` (`bbox [1008, 750, 1119, 859]`).
   - `KF23`: `NE` compass text `(666, 66)`; red-lit barred window `(549, 520)` (`bbox [499, 376, 584, 697]`); vertical `MACLEOD` sign `(1809, 290)` (`bbox [1780, 175, 1845, 430]`).
   - `KF24`: `[F] OPEN` `(950, 551)` (`[894, 520, 991, 564]`), `[F] [HOLD] LOCK` `(950, 598)` (`[873, 586, 1051, 610]`).
   - `KF25`: Hearth flames `(368, 869)`; glowing blue hip baton `(650, 625)`; `[F] PICK POCKET` `(960, 552)` & `[F] [HOLD] TAKEDOWN` `(960, 597)`.
   - `KF26`: Active `[F] [HOLD] TAKEDOWN` progress arc `(960, 552)` (`[834, 530, 1084, 576]`); `Guildhall Key` HUD label `[20, 860, 185, 928]`.
   - `KF27`: Left-wall beam emitter `(341, 432)` (brightest RGB `[247, 240, 212]` at `~40%` image height); horizontal white volumetric beam at `y=435`; glass statue case `(735, 358)`; cyan ceiling node `(1026, 252)`; overhead security camera `(1151, 84)`.
   - `KF28`: Purple crystalline ward `(870, 360)` (`bbox [793, 76, 1080, 1065]`); `Basement Stairs` plaque `(1214, 603)` (`[1185, 555, 1245, 645]`); overhead camera `(1400, 435)` (lens `[1423, 441]`); green arcane vines `(1331, 599)` (`[1285, 535, 1395, 655]`); jaw-trap icon `(939, 808)` & unconscious-head `xx/zz` icon `(992, 805)`.
   - `KF29`: Unlit dark grey/slate upper steps `(1080, 120)` vs. crimson spotlight cast `(1220, 540)`; `CRANK [LMB]` center reticle `(960, 550)` (`[910, 495, 1010, 630]`); re-triggered jaw-trap icon `(960, 808)`.
   - `KF30`: Art-Nouveau modal `[673, 341, 1246, 739]`; `RETURN TO THIEF'S DEN` `(776, 565)` (straight apostrophe); single hover cursor on `QUIT TO DESKTOP` `(1070, 682)`; footer `(158, 1052)` (`1.5.148559   Novice   1025051536`).
4. **Generated Deliverable & Automated Geometry Output:**
   - Wrote `/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_3/callout_spec_kf21_30.json`.
   - Validation command reported: `Keyframes=10 | Total Callouts=57 | Errors=0`.

---

## 2. Logic Chain

1. From Observation #1 and `KEYFRAME_INDEX.md`, each frame `KF21–KF30` has distinct visual, HUD/UI, and gameplay/audio landmarks spanning Acts `S19–S27` (Vistara Diamond scan, `MACLEOD` exterior, blue double doors, parlor pickpocket & takedown, foyer beam/wards/status icons, crimson staircase alarm, and Pause Menu).
2. From Observation #2, all 6 gameplay HUD zones (`top_left_hud`, `top_center_compass`, `top_right_card`, `bottom_left_hotbar`, `bottom_center_gem`, `bottom_right_prompt`) plus frame-specific center reticle prompts and status icons were converted to strict exclusion rectangles.
3. From Observation #3, every callout target `(tx, ty)` was anchored directly on measured pixel centroids rather than estimates (notably catching the left-wall beam emitter at `(341, 432)`, i.e. `y=40%`, and avoiding `KF26`'s foreground ZipWire barrel by placing `Guildhall Key HUD` on `KF27` where the adjacent floor is completely unobstructed).
4. Each callout pill's conservative bounding box (`pw = max(145, len(label)*10 + 30)`, `ph = 34`, including the `28px` circular badge) was checked against `[16, 1904] x [16, 1064]`, all HUD exclusion rectangles (`4px` pad), all other pills (`8px` pad), all target coordinates (`6px` pad), and all leader line segments (zero crossings and zero pill intersections), yielding `0` errors across all 57 callouts (Observation #4).

---

## 3. Caveats

- **Pill Width Estimate vs. Actual Font Metrics:** `estimated_pill_bbox` uses a conservative `max(145, len(label)*10 + 30)` heuristic for ~`16–18px` bold sans-serif text. If the Worker uses a significantly wider font (`>20px`), `KF27` (`#1`/`#3`/`#5`) or `KF28` (`#2`/`#3`) clearances should be visually re-checked on the rendered JPEGs.
- **Audio Cues on Static Frames:** Audio-linked cues (e.g., `KF26` #4 `Takedown Lunge & Impact`, `KF30` #4 `-19 dB Ambience Ducking`) cite exact timestamps and dBFS peaks from `KEYFRAME_INDEX.md` §4 while anchoring their leader lines to the corresponding visual trigger/state on-screen.

---

## 4. Conclusion

The `KF21–KF30` callout specification is complete and ready for immediate consumption by the M2 rendering Worker:

- **Primary Artifact:** `/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_3/callout_spec_kf21_30.json`
- **Coverage:** `10` keyframes (`KF21–KF30`), `57` callouts (`5–8` per keyframe), all labels `<= 4` words, color-coded strictly to `#FFB300` (`Visual`), `#00E5FF` (`HUD/UI`), and `#FF4081` (`Gameplay/Audio`).
- **Callout Counts by Keyframe:** `KF21` (6), `KF22` (5), `KF23` (5), `KF24` (5), `KF25` (6), `KF26` (5), `KF27` (8), `KF28` (7), `KF29` (5), `KF30` (5).

---

## 5. Verification Method

Run the read-only `/usr/bin/python3` geometry & contract validator against `callout_spec_kf21_30.json` and check that `/home/john/Projects/TAT-2` was not modified:

```bash
/usr/bin/python3 - <<'EOF'
import json
from pathlib import Path
spec = json.loads(Path("/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_3/callout_spec_kf21_30.json").read_text())
assert len(spec["keyframes"]) == 10
assert sum(len(k["callouts"]) for k in spec["keyframes"]) == 57
for k in spec["keyframes"]:
    assert 4 <= len(k["callouts"]) <= 8
    for c in k["callouts"]:
        assert len(c["label"].split()) <= 4
        x1, y1, x2, y2 = c["estimated_pill_bbox"]
        assert 16 <= x1 < x2 <= 1904 and 16 <= y1 < y2 <= 1064
print("VERIFIED: 10 keyframes, 57 callouts, all bounds & word-count checks pass.")
EOF
```

**Invalidation Conditions:** Any change to the Pillow renderer's font size exceeding `~10 px/char` average glyph width or badge diameter `> 28px`, or any mismatch between rendered `annotated/KF21..KF30` badge numbers and `CALLOUT_LEGENDS.md` rows.
