# Handoff Report — Explorer 2 (`KF11–KF20` Callout Coordinate Specification)

**Handoff Type:** Hard (Task Complete)  
**Scope:** `KF11_01m00s_mission_prep_countdown.jpg` through `KF20_02m29s_smoke_bomb_plume.jpg` (`1920x1080`)  
**Machine-Usable Spec:** `/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_2/callout_spec_kf11_20.json`

---

## 1. Observation

1. **Source Baseline & Constraints Read:**
   - Read `ORIGINAL_REQUEST.md`, `PROJECT.md`, `sub_orch_m2/SCOPE.md`, and `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` (lines `1–247`).
   - Color & code contract (`SCOPE.md:22–25`): `Amber #FFB300` (`Visual`: `V1–V7`), `Cyan #00E5FF` (`HUD/UI`: `UI1–UI5`), `Magenta #FF4081` (`Gameplay/Audio`: `G1–G5` / `AU1–AU6`).
   - Badge & label geometry (`SCOPE.md:27–30`): `28px` circular badge, `2.5px` leader line with `1px` casing to `(tx, ty)`, compact pill label (`<= 4` words), safe margins `x in [16, 1904]`, `y in [16, 1064]`, zero HUD occlusion, zero overlap.
2. **Direct Visual & Pixel Inspection (`KF11–KF20`):**
   - Visually read all 10 `1920x1080` clean JPEGs under `/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/clean/` via `read_file` and measured exact pixel bounding boxes via `/usr/bin/python3` (`PIL` + `numpy`):
     - `KF11` (`01:00.30`, `S09`): Countdown `(788, 29, 1132, 127)`, Map card `(41, 45, 699, 479)`, Mission card `(40, 480, 679, 729)`, Contract card `(55, 730, 688, 883)`, Moon `(1357, 0, 1558, 146)`, Spider head `(1479, 250, 1620, 379)`, `READY` `(1379, 712, 1547, 785)`, `[F] UNREADY` / `[ESC] BACK` `(1701, 985, 1865, 1039)`.
     - `KF12` (`01:06.50`, `S10`): Left dirigible `(580, 229, 749, 339)`, full moon `(1374, 148, 1535, 319)`, Spinner `(926, 497, 991, 559)` + `LOADING...` `(874, 578, 1045, 600)`, Gold logo `(895, 923, 1043, 1024)`.
     - `KF13` (`01:10.00`, `S11`): Parchment sheet `(552, 206, 1368, 863)`, inner right scrollbar `(1334, 236, 1336, 732)`, `[SPACE] CONTINUE` `(842, 825, 1072, 888)`.
     - `KF14` (`01:15.75`, `S12`): Escape Portal outline `(775, 0, 1256, 470)`, lantern top-left `(158, 0, 262, 43)`, loot/mission `(50, 130, 524, 190)` (Health Bar absent at 100% HP), `Johnny Cipher` card `(1615, 26, 1891, 156)`, `SE` compass `(880, 35, 1040, 85)`, hotbar + ping prompt `(28, 935, 317, 1042)`, Light Gem + faint red arcs `(878, 951, 1035, 1057)`.
     - `KF15` (`01:21.38`, `S13`): `BARRON'S DEMOLITION` banner `(10, 100, 845, 610)`, cyan bulkhead doorway `(1004, 137, 1024, 184)`, metal ladder `(1164, 8, 1299, 639)`, 1P right hand `(1487, 744, 1900, 1078)`, dark Light Gem `(896, 951, 1022, 1058)`.
     - `KF16` (`01:40.20`, `S14`): `CONSTABLE'S GUILDHALL` arch `(520, 110, 989, 214)`, guard + flashlight + yellow alert bar `(860, 360, 959, 592)`, car headlights `(1499, 554, 1691, 632)`, ZipWire `[1]` 1P launcher, half-lit Light Gem `(896, 930, 1033, 1058)`, bottom-right prompts `(1700, 960, 1900, 1055)`.
     - `KF17` (`01:51.20`, `S15`): ZipWire cable `(580, 0, 899, 459)`, clocktower silhouette `(1080, 60, 1219, 349)`, circular `CRANK [LMB]` reticle `(915, 440, 1059, 626)`, red directional threat pip `(1174, 810, 1219, 853)`.
     - `KF18` (`02:14.80`, `S17`): ZipWire cable `(910, 250, 1029, 1059)`, crowned left pillar `(420, 170, 619, 349)`, green distant guard `(1182, 268, 1189, 276)`, right griffin `(1282, 378, 1411, 501)`, `CONSTABL...` right arch, intense red threat arcs `(857, 966, 1059, 1041)`.
     - `KF19` (`02:25.40`, `S18`): Revealed Health Bar frame `(40, 28, 418, 104)` (`~75%` red fill `(96, 39, 379, 73)`), griffin + light `(930, 320)`, `MACL...` sign `(1661, 299, 1683, 389)`, 1P Smoke Bomb `[2]` canister `(1500, 450, 1899, 859)`, `THROW [LMB]` `(1769, 1012, 1873, 1041)`.
     - `KF20` (`02:29.20`, `S18`): Volumetric smoke plume `(471, 446, 1497, 628)`, persistent Health Bar `(96, 41, 371, 72)`, intense red threat arcs `(790, 967, 1111, 1042)`, `THROW [LMB]` `(1769, 1012, 1873, 1041)`.
3. **Repository Hygiene:**
   - Zero files modified inside `/home/john/Projects/TAT-2/` and zero leftover `/tmp` files.

---

## 2. Logic Chain

1. **Pixel-anchored placement:** Measuring exact `1920x1080` bounding boxes of every HUD panel, reticle, character, and VFX region ensures every `Target (tx, ty)` lands directly on the observable feature and every `protected_hud` box accurately reserves on-screen HUD space.
2. **Collision-free margin routing:** Placing `Label Anchor (lx, ly)` with explicit `pill_left` / `pill_right` orientation in uncluttered sky, floor, or wall margins prevents pills from covering targets or HUD elements.
3. **Automated geometric verification:** Testing conservative pill bounding boxes (`max(150, len*11 + 24)` x `34px` around the `28px` badge) against image borders `[16, 16, 1904, 1064]`, `protected_hud` boxes, peer pills (`>=10px` padding), and leader-line segments caught 3 initial collisions (`KF13 #5` hitting parchment right corner, `KF15 #2` hitting top-right `Johnny Cipher` card, and `KF18 #5` leader line crossing `#4`), all of which were relocated and re-verified to **0 issues across 56 callouts**.

---

## 3. Caveats

- Pill widths in the geometric validator used a conservative formula (`max(150, len(label)*11 + 24)` px). Actual rendered pill width depends on the Worker's chosen Pillow font (`font_size=16..18`); if a larger font size (`>= 22px`) is used, `KF15 #2` (`x=1380`, `pill_right`) or `KF16 #1` (`x=1060`, `pill_right`) should still be visually spot-checked after rendering.
- `BBox` is provided selectively for grouped HUD/UI panels, the Escape Portal, the `BARRON'S DEMOLITION` banner, the `CRANK [LMB]` ring, Light Gem + threat arc clusters, Health Bar, and the volumetric smoke plume; single-point targets set `bbox: null`.

---

## 4. Conclusion

The complete, verified callout coordinate specification for **`KF11–KF20`** (`56` callouts across `10` keyframes; `5–7` callouts per keyframe; all 3 color categories represented in every keyframe) is ready for the Worker in `callout_spec_kf11_20.json` and summarized below:

### `KF11` (`01:00.30`, `S09`) — `KF11_01m00s_mission_prep_countdown.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `HUD/UI` (`#00E5FF`) | `UI1` | `6s Prep Countdown` | `(955, 48)` | `(1190, 72)` | `pill_right` | `(785, 22, 1138, 134)` | `"MISSION STARTING IN 5... / Mode: Solo / Difficulty: Novice"` centered top HUD during active 6 s countdown (`00:58.9–01:04.8`). |
| 2 | `HUD/UI` (`#00E5FF`) | `UI2` | `Map & Mission Cards` | `(685, 240)` | `(750, 240)` | `pill_right` | `(48, 50, 695, 725)` | Stacked Art-Nouveau bordered cards: `"CONSTABLES' GUILDHALL"` (gate preview), `"Cleanout Heist"`, `"Time Limit: 55 minutes"` (matches Briefing). |
| 3 | `HUD/UI` (`#00E5FF`) | `UI2` | `Contract Inactive Card` | `(680, 805)` | `(750, 805)` | `pill_right` | `(52, 730, 688, 885)` | Bottom-left card reading `"Contract Inactive: Your active contract is not available for the currently selected map."` |
| 4 | `Visual` (`#FFB300`) | `V1` | `Moon & Searchlights` | `(1455, 72)` | `(1620, 120)` | `pill_right` | `(1355, 0, 1560, 150)` | Full moon upper-right casting cool blue-slate rim lighting and angled volumetric searchlight beams across gothic Kilcairn rooftops. |
| 5 | `Visual` (`#FFB300`) | `V3` | `3D Spider Rooftop Pose` | `(1545, 430)` | `(1280, 430)` | `pill_left` | `—` | 3D Spider character (`"Johnny Cipher"`) standing on slate roof ridge wearing cap, goggles, and belt pouches. |
| 6 | `Gameplay/Audio` (`#FF4081`) | `AU3` | `Ready & Countdown Ticks` | `(1460, 745)` | `(1280, 745)` | `pill_left` | `—` | Green `"READY"` toggle (`[F] UNREADY` / `[ESC] BACK`) paired with 6 percussive UI ticks at `1.00 s` intervals (`00:59.0–01:04.0`). |

### `KF12` (`01:06.50`, `S10`) — `KF12_01m06s_loading_screen.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Visual` (`#FFB300`) | `V2` | `Kilcairn Skyline & Dirigibles` | `(665, 275)` | `(560, 145)` | `pill_left` | `—` | Dark-indigo illustrated Kilcairn rooftop silhouette with twin airship dirigibles sweeping warm yellow searchlight cones. |
| 2 | `Visual` (`#FFB300`) | `V1` | `Illustrated Full Moon` | `(1455, 235)` | `(1595, 235)` | `pill_right` | `—` | Textured pale full moon in upper-right violet-indigo sky illuminating rooftop ridges and circular fan facade (left). |
| 3 | `HUD/UI` (`#00E5FF`) | `UI2` | `Loading Spinner Ring` | `(958, 528)` | `(1135, 528)` | `pill_right` | `(870, 492, 1050, 606)` | Centered rotating cyan/white circular ring above crisp `"LOADING..."` text (Loading Screen 2, `01:04.80–01:09.44`). |
| 4 | `HUD/UI` (`#00E5FF`) | `UI2` | `Gold Title Emblem` | `(968, 975)` | `(1135, 975)` | `pill_right` | `(888, 920, 1050, 1030)` | Bottom-center gold stylized `"THICK AS THIEVES"` stacked emblem with diamond flourish. |
| 5 | `Gameplay/Audio` (`#FF4081`) | `AU6` | `Digital Silence Window` | `(960, 385)` | `(790, 415)` | `pill_left` | `—` | True digital silence (`-240.0 dBFS`, `01:04.94–01:07.78`) with zero loading music before rain fades in at `01:07.78`. |

### `KF13` (`01:10.00`, `S11`) — `KF13_01m10s_briefing_letter.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Visual` (`#FFB300`) | `V6` | `Blurred Safe-Room Backdrop` | `(280, 340)` | `(120, 220)` | `pill_right` | `—` | Darkened depth-of-field / Gaussian blur over Guildhall safe-room brick wall and iron grate window behind modal. |
| 2 | `HUD/UI` (`#00E5FF`) | `UI2` | `Folded Parchment Sheet` | `(565, 500)` | `(480, 500)` | `pill_left` | `(548, 202, 1372, 868)` | Centered folded cream parchment sheet with horizontal crease shadow and 11-line typewriter briefing text. |
| 3 | `HUD/UI` (`#00E5FF`) | `UI2` | `55m/20m Mission Rules` | `(760, 595)` | `(480, 625)` | `pill_left` | `—` | Verbatim briefing specifies `"55 minute window"` (matching Mission Prep) and `"magic door ... summoned for 20 minutes"`. |
| 4 | `HUD/UI` (`#00E5FF`) | `UI2` | `Letter Right Scrollbar` | `(1335, 420)` | `(1425, 420)` | `pill_right` | `—` | Thin bright vertical scrollbar along right inner margin of parchment letter. |
| 5 | `Gameplay/Audio` (`#FF4081`) | `AU3` | `Continue & Paper Rustle` | `(955, 855)` | `(1150, 925)` | `pill_right` | `(842, 825, 1072, 888)` | `"[SPACE] CONTINUE"` button below letter; opening/dismissing plays crisp paper rustle (`01:09.5–01:10.3`) over exterior rain. |

### `KF14` (`01:15.75`, `S12`) — `KF14_01m15s_saferoom_portal_hud.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Visual` (`#FFB300`) | `V4` | `Escape Portal Wall VFX` | `(1015, 240)` | `(1320, 240)` | `pill_right` | `(775, 4, 1256, 470)` | Jagged glowing emerald-green and violet chromatic-edge Escape Portal outline shimmering on safe-room wall (`01:15.2–01:16.2`). |
| 2 | `Visual` (`#FFB300`) | `V1` | `Warm Oil Lantern Glow` | `(210, 25)` | `(360, 75)` | `pill_right` | `—` | Ignited caged wall lantern casting warm orange bounce light on dark brick beside dark iron grate catwalk. |
| 3 | `HUD/UI` (`#00E5FF`) | `UI1` | `Loot Tracker (No HP)` | `(260, 165)` | `(120, 260)` | `pill_right` | `(42, 118, 535, 198)` | Top-left `"(£) 0"` and `"Mission: Steal 4,000 in loot value[0/4,000]"`; Health Bar stays hidden at 100% HP until `02:23.30`. |
| 4 | `HUD/UI` (`#00E5FF`) | `UI1` | `Player Card & Compass` | `(1760, 85)` | `(1540, 120)` | `pill_left` | `—` | Top-right `"Johnny Cipher"` (Level 4, Spider portrait) and subtle top-center `"SE"` compass bar. |
| 5 | `HUD/UI` (`#00E5FF`) | `UI3` | `Hotbar & Ping Menu` | `(165, 975)` | `(165, 845)` | `pill_right` | `(20, 930, 325, 1055)` | Bottom-left tool slots `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond plus `"[TAB] MAP [MMB] [HOLD] PING MENU"`. |
| 6 | `HUD/UI` (`#00E5FF`) | `UI1` | `Light Gem & Arcs` | `(958, 998)` | `(1140, 975)` | `pill_right` | `(872, 945, 1045, 1060)` | Bottom-center stealth Light Gem glowing warm cream-gold (lit by lantern) flanked by faint red directional threat arcs. |
| 7 | `Gameplay/Audio` (`#FF4081`) | `AU4` | `Nisha VO & Lantern` | `(960, 540)` | `(680, 540)` | `pill_left` | `—` | ThiefNisha VO `"Let the thieving begin."` (`01:11.6–01:13.1`) and lantern ignite click-whoosh (`01:15.1`); zero BGM. |

### `KF15` (`01:21.38`, `S13`) — `KF15_01m21s_alley_barrons_demolition.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Visual` (`#FFB300`) | `V5` | `BARRON'S DEMOLITION Banner` | `(440, 385)` | `(580, 660)` | `pill_right` | `(8, 100, 845, 610)` | Weathered brick wall banner reading `"BARRON'S DEMOLITION"` (faint `"EST. 1865"`) and `"Out with the old, in with the new!"`. |
| 2 | `Visual` (`#FFB300`) | `V1` | `Cyan Doorway & Reflections` | `(1015, 160)` | `(1380, 215)` | `pill_right` | `—` | Teal-cyan caged bulkhead light illuminating rain-slicked alley cobblestones, puddle speculars, and metal wall ladder. |
| 3 | `Visual` (`#FFB300`) | `V2` | `Alley Ladder & Drums` | `(1230, 420)` | `(1380, 420)` | `pill_right` | `—` | Vertical steel access ladder beside brick corner, crates, fallen steel oil drums, and sparse alley weeds. |
| 4 | `HUD/UI` (`#00E5FF`) | `UI1` | `Shadowed Dark Light Gem` | `(958, 998)` | `(1110, 965)` | `pill_right` | `(888, 945, 1028, 1060)` | Bottom-center Light Gem rests in deep indigo-blue (full shadow concealment) with zero threat arcs. |
| 5 | `Gameplay/Audio` (`#FF4081`) | `G3` | `1P Drop & Foley` | `(1620, 860)` | `(1410, 740)` | `pill_left` | `—` | 1P gloved hands & forearm brace alley drop; rain ambience (`-49 dBFS`) transitions to wet cobble footsteps & puddle splashes. |

### `KF16` (`01:40.20`, `S14`) — `KF16_01m40s_zipwire_gate_headlights.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Visual` (`#FFB300`) | `V5` | `CONSTABLE'S GUILDHALL Arch` | `(750, 175)` | `(1060, 115)` | `pill_right` | `—` | Wrought-iron perimeter gate arch bearing gilded `"CONSTABLE'S GUILDHALL"` lettering and crowned stone pillars. |
| 2 | `Gameplay/Audio` (`#FF4081`) | `G2` | `Guard Alert & Eyes` | `(912, 425)` | `(690, 425)` | `pill_left` | `—` | Alerted constable inside gate with glowing red eyes, hip flashlight, vertical yellow alert bar, and VO `"I know someone's here!"` (`01:39.3–01:40.6`). |
| 3 | `Visual` (`#FFB300`) | `V1` | `Vintage Car Headlights` | `(1605, 585)` | `(1400, 445)` | `pill_left` | `—` | Flashing dual headlights on parked vintage car (triggered by `[F] INTERACT` + double-honk at `01:35.68`) casting glare across wet cobbles. |
| 4 | `Gameplay/Audio` (`#FF4081`) | `G1` | `ZipWire [1] Crank Launcher` | `(1160, 720)` | `(1280, 620)` | `pill_right` | `—` | 1P mechanical spring-loaded ZipWire crank launcher equipped in slot `[1]` (no fall damage occurs on `01:44` foliage drop). |
| 5 | `HUD/UI` (`#00E5FF`) | `UI4` | `Half-Lit Light Gem` | `(958, 995)` | `(740, 995)` | `pill_left` | `—` | Half-lit white/indigo Light Gem reflecting partial headlight/streetlamp exposure while bottom-right shows `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`. |
| 6 | `HUD/UI` (`#00E5FF`) | `UI3` | `ZipWire Action Prompts` | `(1795, 1005)` | `(1640, 895)` | `pill_left` | `—` | Bottom-right tool prompts: `"LAUNCH [LMB]"` and `"[HOLD] CRANK [RMB]"` paired with white-highlighted slot `[1]` bottom-left. |

### `KF17` (`01:51.20`, `S15`) — `KF17_01m51s_zipwire_aim_roof.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Gameplay/Audio` (`#FF4081`) | `G1` | `Anchored ZipWire Cable` | `(755, 250)` | `(540, 250)` | `pill_left` | `—` | 2nd ZipWire shot anchored to upper brick roof parapet; accompanied by spring launch (`01:51.7`) and cable zip whine (`01:52.2`). |
| 2 | `Visual` (`#FFB300`) | `V2` | `Clocktower Fog Silhouette` | `(1145, 190)` | `(1300, 190)` | `pill_right` | `—` | Distant Guildhall spire/clocktower silhouette with tiny red window accents emerging through volumetric night mist. |
| 3 | `HUD/UI` (`#00E5FF`) | `UI1` | `CRANK [LMB] Progress Ring` | `(955, 535)` | `(700, 535)` | `pill_left` | `(905, 440, 1015, 628)` | Center-screen radial segmented progress ring displaying `"CRANK [LMB]"` while cable attaches for facade ascent. |
| 4 | `HUD/UI` (`#00E5FF`) | `UI1` | `Red Directional Threat Pip` | `(1195, 832)` | `(1330, 832)` | `pill_right` | `—` | Three-dash crimson directional alert indicator pulsing over lower-right view as patrolling guard shouts `"Oh, I will find you, thief!"`. |
| 5 | `Gameplay/Audio` (`#FF4081`) | `AU1` | `Ratchet Crank Audio Cue` | `(1240, 620)` | `(1390, 560)` | `pill_right` | `—` | 1P ZipWire crank handle initiates rhythmic ratchet hand-cranking SFX (`01:56.1–02:01.2`, `pk=-22.2 dBFS`) during roof climb. |

### `KF18` (`02:14.80`, `S17`) — `KF18_02m14s_guildhall_arch_overlook.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Gameplay/Audio` (`#FF4081`) | `G1` | `Elevated ZipWire Traversal` | `(965, 560)` | `(760, 560)` | `pill_left` | `—` | Mid-cable traversal overlooking courtyard (`02:11.00–02:17.00`) with center reticle dot and ratchet clicks (`02:13.4–02:15.1`). |
| 2 | `Visual` (`#FFB300`) | `V2` | `Crowned Gate Pillars` | `(520, 260)` | `(330, 260)` | `pill_left` | `—` | Ornate star-topped crown finials atop wrought-iron perimeter gate pillars framing Guildhall courtyard. |
| 3 | `Gameplay/Audio` (`#FF4081`) | `G2` | `Green Guard Silhouette` | `(1185, 272)` | `(1280, 175)` | `pill_right` | `—` | Patrolling constable beneath portico highlighted in bright green silhouette across courtyard fog. |
| 4 | `Visual` (`#FFB300`) | `V2` | `Twin Griffin Statues` | `(1350, 420)` | `(1470, 420)` | `pill_right` | `—` | Pair of winged stone griffin statues perched on brick pedestals flanking Guildhall grand exterior staircase. |
| 5 | `Visual` (`#FFB300`) | `V5` | `CONSTABLE'S Arch (Right)` | `(1760, 375)` | `(1880, 280)` | `pill_left` | `—` | Partial wrought-iron `"CONSTABL..."` arch lettering visible at right edge from elevated gate-pillar cable angle. |
| 6 | `HUD/UI` (`#00E5FF`) | `UI1` | `Intense Red Threat Arcs` | `(875, 1005)` | `(720, 985)` | `pill_left` | `(852, 950, 1064, 1060)` | Twin bright-red directional threat/alert arcs bracketing dark indigo Light Gem during high-elevation crossing. |

### `KF19` (`02:25.40`, `S18`) — `KF19_02m25s_smoke_bomb_equip.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `HUD/UI` (`#00E5FF`) | `UI1` | `Health Bar Revealed (~75%)` | `(245, 58)` | `(490, 62)` | `pill_right` | `(40, 26, 422, 106)` | Ornate Art-Nouveau Health Bar appears post-`02:23.30` courtyard fall damage (`red_px: 0->27,560`), settled at `~75%` fill. |
| 2 | `Visual` (`#FFB300`) | `V2` | `Griffin Statue & Bridge` | `(930, 320)` | `(720, 320)` | `pill_left` | `—` | Wet sculpted stone griffin statue on brick plinth beside wooden crates and overhead iron bridge silhouette in fog. |
| 3 | `Visual` (`#FFB300`) | `V5` | `Distant MACLEOD Sign` | `(1672, 345)` | `(1510, 230)` | `pill_left` | `—` | Vertical illuminated gold serif `"MACL..."` (`"MACLEOD"`) sign glowing through night mist on distant right facade. |
| 4 | `Gameplay/Audio` (`#FF4081`) | `G1` | `Smoke Bomb [2] Canister` | `(1680, 630)` | `(1480, 630)` | `pill_left` | `—` | 1P gloved right hand grips dark cylindrical Smoke Bomb canister with lever; slot `[2]` active bottom-left. |
| 5 | `HUD/UI` (`#00E5FF`) | `UI3` | `THROW [LMB] Prompt` | `(1820, 1025)` | `(1660, 930)` | `pill_left` | `—` | Bottom-right action prompt switches to `"THROW [LMB]"` matching equipped Smoke Bomb `[2]`. |
| 6 | `HUD/UI` (`#00E5FF`) | `UI4` | `Warm-Lit Light Gem` | `(958, 995)` | `(1100, 995)` | `pill_right` | `—` | Light Gem glows warm cream-gold on wet courtyard flagstones (Guard VO: `"Hey! Show yourself!"` at `02:24.8–02:26.0`). |

### `KF20` (`02:29.20`, `S18`) — `KF20_02m29s_smoke_bomb_plume.jpg`
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1, y1, x2, y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | `Visual` (`#FFB300`) | `V4` | `Volumetric Smoke Plume VFX` | `(820, 560)` | `(820, 290)` | `pill_right` | `(200, 380, 1540, 700)` | Opaque grey-white volumetric smoke puffs expanding horizontally across grand stairs post-`02:28.20` ignition flash to block line-of-sight. |
| 2 | `Gameplay/Audio` (`#FF4081`) | `AU1` | `Detonation & Smoke Hiss` | `(1350, 505)` | `(1450, 320)` | `pill_right` | `—` | Detonation pop + sustained pressurized hiss/whoosh (`02:28.3–02:29.8`, `pk=-20.5 dBFS`) followed by guard cough & VO. |
| 3 | `HUD/UI` (`#00E5FF`) | `UI1` | `Health Bar (~75% Fill)` | `(245, 58)` | `(490, 62)` | `pill_right` | `—` | Ornate top-left Health Bar remains visible below 100% HP (`~75%` fill) above `"(£) 0"` and loot mission tracker. |
| 4 | `HUD/UI` (`#00E5FF`) | `UI1` | `Intense Red Threat Arcs` | `(825, 1005)` | `(660, 975)` | `pill_left` | `(788, 950, 1115, 1060)` | Wide twin red directional threat arcs flaring around lit Light Gem as guard reacts (`"You stop making noise, you dog!"`). |
| 5 | `HUD/UI` (`#00E5FF`) | `UI3` | `Slot [2] THROW Prompt` | `(1820, 1025)` | `(1660, 920)` | `pill_left` | `—` | Smoke Bomb slot `[2]` remains active bottom-left with `"THROW [LMB]"` bottom-right after canister throw. |

---

## 5. Verification Method

1. **Automated Geometry & Schema Validation (Verified PASS):**
   - Run `/usr/bin/python3` against `/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_2/callout_spec_kf11_20.json` checking:
     - `len(keyframes) == 10` (`KF11..KF20`), `56` total callouts (`5–7` per keyframe), all 3 colors per keyframe, all labels `<= 4` words.
     - All badge+pill boxes strictly inside `[16, 16, 1904, 1064]`.
     - `0` pill-pill overlaps, `0` pill-HUD overlaps, `0` leader-line crossings, `0` targets occluded.
2. **Invalidation Conditions:**
   - Any rendered `annotated/KF11..KF20` using a font wider than `~11px/char` that causes a pill to touch a border/HUD box, or any mismatch between badge IDs `[1]..[N]` and `CALLOUT_LEGENDS.md`.
3. **Repo Hygiene Check:**
   - Confirm `git status` in `/home/john/Projects/TAT-2` shows zero changes made by this Explorer.
