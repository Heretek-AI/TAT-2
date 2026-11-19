# Handoff Report — Explorer 1 (`KF01–KF10` Callout Spec & Tooling/Font Check)

**Core Findings:** Verified `/usr/bin/python3` (`3.15.2`), `Pillow 13.0.0`, `numpy 2.5.4`, and readable `NotoSans` / `FreeSans` / `DejaVuSans` `.ttf` fonts; visually inspected all 10 clean keyframes `KF01–KF10` (`1920x1080` RGB) and produced a programmatically validated 58-callout coordinate spec in `callout_spec_kf01_10.json` with zero overlaps, zero HUD occlusion, and zero out-of-bounds pills.

---

## 1. Observation

### 1.1 Python, Pillow, Numpy & System Fonts
Executed `/usr/bin/python3` against `PIL`, `numpy`, and `PIL.ImageFont.truetype(...)`:
- **Runtime**: `Python 3.15.2`, `Pillow 13.0.0`, `Numpy 2.5.4`.
- **Verified Loadable `.ttf` Fonts (`ImageFont.truetype(path, 16)` succeeded)**:
  - `/usr/share/fonts/google-noto/NotoSans-Bold.ttf` (recommended for badge numerals)
  - `/usr/share/fonts/google-noto/NotoSans-SemiBold.ttf` (recommended for compact label pills)
  - `/usr/share/fonts/google-noto/NotoSans-Medium.ttf`
  - `/usr/share/fonts/google-noto/NotoSans-Regular.ttf`
  - `/usr/share/fonts/gnu-free/FreeSansBold.ttf`, `/usr/share/fonts/gnu-free/FreeSans.ttf`
  - `/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf`, `/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf`
- **Missing paths** (do NOT reference): `/usr/share/fonts/TTF/DejaVuSans*.ttf`, `/usr/share/fonts/liberation/LiberationSans*.ttf`.

### 1.2 Clean Keyframes `KF01–KF10` Inspected (`1920x1080` RGB)
All 10 clean keyframes in `/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/clean/` were visually inspected via `read_file` and pixel-measured:
- `KF01_00m01s_startscreen.jpg` (`S01`, `00:01.00`): `Mac Neish` / `Jeweller` neon `(752,360,1018,519)`, purple orb `(848,290,909,364)`, streetlamp `(1355,193,1395,228)`, `THICK AS THIEVES` `(1311,290,1785,588)`, menu `(1312,670,1442,870)`, idle guard `(720..820,620..880)`, puddle `(700..1280,910..975)`, car fender `(100..320,650..900)`.
- `KF02_00m04s_den_entry.jpg` (`S03`, `00:04.50`): Top-center compass `(506,47,987,77)`, `Johnny Cipher` (`4`) card `(1615,26,1891,157)`, frosted window shaft `(280..600,100..480)`, armoire `(0..220,170..540)`, candlelit desk `(1060,347,1179,439)`, map table right `(1520..1920,400..650)`.
- `KF03_00m07s_wardrobe_loadout.jpg` (`S04`, `00:07.00`): `WARDROBE` `(804,48,1109,88)`, Spider/Chameleon cards `(165,72,745,360)`, `Edit Loadout` banner `(342,370,542,424)`, slots 1–4 `(213,427,654,581)`, prompt text `(184,580,717,659)`, Zipwire tooltip `(178,721,743,1015)`, 3D Spider `(806..1099,215..1014)`, right slots `Head`/`Body`/`Calling Card` `(1528,247,1677,756)`, `BACK [ESC]` `(1765,1019,1866,1041)`.
- `KF04_00m16s_wardrobe_vistara_diamond.jpg` (`S04`, `00:16.50`): Slot 3 expanded 4-tool drawer `(241,590,649,704)`, cursor hovering Slot 4 `(618,505)`, `Vistara Diamond` tooltip `(178,721,743,1015)`, Spider wearing `Cap` `(940,240)` synced in `Head` slot `(1573,247,1649,382)`. Pitch-black empty gutters verified on left/right of `Edit Loadout` (`(20,368,250,412)` max RGB 5; `(560,368,800,412)` max RGB 8).
- `KF05_00m20s_telescope_cheese_moon.jpg` (`S05`, `00:20.80`): Moon `(1253,56,1465,268)`, golden cheese wedge `(800,342,1154,689)`, `[F] EXIT` `(880,520,975,551)`, orbiting cheese chunks (`x~575`, `745`, `1315`), dark rooftops below `y=650`.
- `KF06_00m24s_den_wanted_window.jpg` (`S05`, `00:24.60`): Arched frosted window `(480..1020,80..950)`, fuse box `(220..420,330..500)`, open armoire mirror `(0..200,620..850)`, telescope `(810..910,880..1080)`, 5 Wanted posters `(1275,515,1665,1075)`, `Johnny Cipher` card `(1615,26,1891,157)`.
- `KF07_00m27s_ledger_journal.jpg` (`S06`, `00:27.00`): `[Q] JOURNAL` / `BLACK MARKET [E]` `(697,73,1222,105)`, `Level 4` XP bar `94/500` `(401,142,1563,319)`, Contract #1 clipped left `(0..240,414..951)`, Contract #2 `(270,414,1075,951)`, Contract #3 `(1115,413,1914,951)`, `BACK [ESC]` `(1765,1019,1866,1041)`.
- `KF08_00m28s_ledger_black_market.jpg` (`S06`, `00:28.50`): `YOUR TOTAL ASSETS: (£) 26,275` `(732,154,1191,207)`, `Zipwire` preview `(162,241,887,623)`, `TOOLS`/`GUILD PERKS` `(105,635,925,985)`, `SPIDER COSMETICS` `(955,248,1385,1018)`, `CHAMELEON COSMETICS` `(1400,248,1835,1018)`.
- `KF09_00m46s_den_gramophone.jpg` (`S07`, `00:46.25`): Brass-horn Gramophone `(500..990,10..620)`, `[F] TURN OFF` `(880,523,1029,558)`, 3-candle candelabra `(330,136,509,374)`, pink trunk gem `(34,172,161,239)`, white table diamond `(1209,598,1290,686)`, green floor diamond `(0,619,120,672)`.
- `KF10_00m52s_den_map_table.jpg` (`S08`, `00:52.35`): Floating top-center card `(586,17,909,250)`, `CONSTABLES' GUILDHALL` 3D token `(610,380,944,639)`, `[F] ENTER MATCH` `(865,520,1069,579)`, brass banker's lamp `(920..1080,10..310)`, marble bust `(1324,20,1510,405)`, bottom-right legend `(1644,932,1879,1041)`.

### 1.3 Repository Status
`git -C /home/john/Projects/TAT-2 status --short` shows zero files added or modified by Explorer 1.

---

## 2. Logic Chain

1. **Tooling & Font Selection**: `Pillow 13.0.0` and `numpy 2.5.4` are confirmed under `/usr/bin/python3` (`3.15.2`). Because `LiberationSans` and `TTF/DejaVuSans` paths do not exist on this host, `NotoSans-Bold.ttf` (numerals) and `NotoSans-SemiBold.ttf` (labels) provide verified crisp sans-serif metrics with zero missing-font risk.
2. **Coordinate Model**: Defining each callout with `target (tx, ty)` and badge center `anchor (lx, ly)` plus `placement` (`pill_right` or `pill_left`, `28px` badge, `32px` pill height, `17px` `NotoSans-SemiBold.ttf`) allows exact bounding-box calculation prior to rendering.
3. **Iterative Conflict Elimination**: Programmatic validation against measured HUD boxes, pixel brightness masks, and target coordinates caught and resolved five initial issues:
   - Shifted `KF03` Character Switch bbox top to `y=72` (actual portrait top `y=80`) and moved `Loadout Slots 1–4` into the empty dark gutter right of `Edit Loadout` (`(580, 392)`).
   - Placed `KF04` `#1` (`Slot 3 Tool Drawer`) and `#2` (`Slot Hover Click SFX`) in the two verified pitch-black gutters flanking `Edit Loadout` (`(42, 392)` and `(575, 392)`).
   - Tightened `KF04 #2` and `KF05 #1` labels to `<= 4` words.
   - Repositioned `KF08` `#2`, `#4`, `#5` anchors to eliminate leader-line crossings over `#1` and `#4`.
   - Moved `KF10 #2` onto the dark upper-left wall (`(42, 310)`, mean RGB `18.8`) so no pill sits over bright parchment or the marble bust (`x=1324..1510`).

---

## 3. Caveats

- Callout bounding boxes assume the Worker renders labels with `NotoSans-SemiBold.ttf` at `17px` (`pill_height=32`, `pill_pad_x=12`, `badge_diameter=28`, `badge_pill_gap=6`). If the Worker uses a larger font size or wider padding, re-run the Verification Method check with the Worker's exact constants.
- Explorer 1 covers `KF01–KF10` only (`58` callouts total); `KF11–KF30` are covered by peer explorers.

---

## 4. Conclusion & Complete Callout Spec (`KF01–KF10`)

The complete machine-consumable spec is saved at:
`/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_1/callout_spec_kf01_10.json`

### Color & Font Spec for Worker
- **Colors**: `Visual = #FFB300`, `HUD/UI = #00E5FF`, `Gameplay/Audio = #FF4081`
- **Fonts**: Badge numerals `/usr/share/fonts/google-noto/NotoSans-Bold.ttf` (`16px`); Labels `/usr/share/fonts/google-noto/NotoSans-SemiBold.ttf` (`17px`)

### Summary Tables (`KF01–KF10`)

#### `KF01` — `KF01_00m01s_startscreen.jpg` (`S01`, `00:01.00`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | Visual | `V1` | `Neon Sign & Flicker` | `(885, 440)` | `(575, 160)` | `pill_left` | — | Magenta cursive neon `Mac Neish` / `Jeweller` (lit full at `00:01.00` amidst `00:00.1–00:02.1` flicker) with warm amber window/awning neon bars and Art Nouveau gold scrollwork. |
| 2 | Visual | `V2` | `Shopfront Orb & Lamp` | `(878, 326)` | `(940, 110)` | `pill_right` | — | Glowing purple egg/orb inside upper Art Nouveau shopframe (`x=848..909, y=290..364`) beneath upper-right warm streetlamp (`x=1375, y=210`). |
| 3 | HUD/UI | `UI1` | `Title & Menu Stack` | `(1436, 675)` | `(1550, 680)` | `pill_right` | `(1295, 655, 1475, 885)` | Right-aligned `THICK AS THIEVES` logo above `PLAY`, `SETTINGS`, `CREDITS`, `QUIT` with cursor approaching `PLAY` (`00:02.0` click, `pk=-33.4 dBFS`). |
| 4 | Gameplay/Audio | `G2` | `Idle Guard Patrol` | `(775, 740)` | `(560, 740)` | `pill_left` | — | Stationary idle guard in dark uniform, helmet, and brown belt standing before the `Mac Neish` shopfront. |
| 5 | Visual | `V5` | `Puddle & Rain Streaks` | `(960, 945)` | `(620, 995)` | `pill_left` | — | Rain-slick cobblestones reflecting magenta/amber shopfront neon in foreground puddle with diagonal falling rain streaks. |
| 6 | Gameplay/Audio | `AU1` | `Rain Ambience (No BGM)` | `(220, 780)` | `(60, 520)` | `pill_right` | — | Steady night rain hiss + distant street air (`-53 to -49 dBFS` RMS, explicit zero BGM) framing vintage car rear fender on left. |

#### `KF02` — `KF02_00m04s_den_entry.jpg` (`S03`, `00:04.50`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | Visual | `V1` | `Volumetric Moon Shaft` | `(460, 290)` | `(440, 110)` | `pill_left` | — | Volumetric teal-cyan moonlight shaft pouring through arched frosted leaded-glass window, casting mullion shadows across dark floorboards. |
| 2 | HUD/UI | `UI1` | `Player Card (Lvl 4)` | `(1750, 95)` | `(1565, 195)` | `pill_left` | `(1605, 18, 1900, 165)` | Top-right `Johnny Cipher` player card with Spider portrait and level `4` badge fading in by `00:02.70`. |
| 3 | HUD/UI | `UI2` | `Top-Center Compass` | `(960, 58)` | `(960, 118)` | `pill_right` | — | Subtle horizontal top-center compass bar with center tick and `NW` heading indicator. |
| 4 | Gameplay/Audio | `G1` | `Interactive Den Stations` | `(140, 340)` | `(110, 620)` | `pill_right` | — | Open illuminated Wardrobe armoire (left) and brass tripod telescope in quiet Thieves' Den (`-76.3 to -73.1 dBFS` room tone, wooden footsteps, no BGM). |
| 5 | Visual | `V4` | `Candlelit Rolltop Desk` | `(1115, 385)` | `(1060, 230)` | `pill_right` | — | Warm point-lit 3-candle candelabra illuminating open Ledger book on rolltop desk, contrasting with cool moonlight shaft. |
| 6 | Gameplay/Audio | `G2` | `Kilcairn Map Table` | `(1660, 490)` | `(1540, 710)` | `pill_right` | — | Mission-selection `KILCAIRN` parchment map table with 3D wooden building tokens; scattered newspapers on foreground floorboards. |

#### `KF03` — `KF03_00m07s_wardrobe_loadout.jpg` (`S04`, `00:07.00`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | HUD/UI | `UI1` | `Character Switch [Q/E]` | `(450, 200)` | `(420, 40)` | `pill_left` | `(165, 72, 745, 360)` | `[Q]` `The Spider` (selected, cyan border) vs `[E]` `The Chameleon` (`LOCKED` with pink padlock) under `WARDROBE` header. |
| 2 | HUD/UI | `UI2` | `Loadout Slots 1–4` | `(550, 505)` | `(580, 392)` | `pill_right` | `(200, 425, 680, 590)` | `Edit Loadout` slots `[1]` Zipwire (grey signature lock), `[2]` Smoke Bomb, `[3]` empty, `[4]` Vistara Diamond (grey signature lock). |
| 3 | HUD/UI | `UI3` | `Zipwire Tooltip Card` | `(460, 865)` | `(460, 1044)` | `pill_left` | `(172, 710, 750, 1025)` | Bottom-left ornate tooltip card showing 3D `Zipwire` grapple gun preview and verbatim grapple-recoil description. |
| 4 | Visual | `V3` | `3D Spider Turntable` | `(940, 420)` | `(1120, 210)` | `pill_right` | — | 3D `The Spider` character turntable wearing Bowler Hat, yellow goggles, and purple ribbed sweater before open armoire. |
| 5 | Visual | `V2` | `Open Wardrobe Armoire` | `(1290, 460)` | `(1160, 850)` | `pill_right` | — | Open wooden armoire interior lit by overhead curved lamp with hanging bottles/tools; Wardrobe open chime at `00:06.7` (`pk=-23.5 dBFS`, no BGM). |
| 6 | HUD/UI | `UI4` | `Cosmetic & Back Slots` | `(1615, 515)` | `(1460, 140)` | `pill_right` | `(1515, 220, 1705, 795)` | Right customization column (`Head`, `Body`, `Calling Card` spider emblem) above bottom-right `BACK [ESC]` button. |

#### `KF04` — `KF04_00m16s_wardrobe_vistara_diamond.jpg` (`S04`, `00:16.50`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | HUD/UI | `UI2` | `Slot 3 Tool Drawer` | `(265, 645)` | `(42, 392)` | `pill_right` | `(205, 588, 660, 708)` | Slot `3` selected (cyan highlight) expanding 4-tool row: `Smoke Bomb` unlocked; `Pickpocket Fairy`, `Insult Fairy`, `Slither Sap` with pink padlocks. |
| 2 | Gameplay/Audio | `UI5` | `Slot Hover Click SFX` | `(618, 505)` | `(575, 392)` | `pill_right` | — | Cursor hovering Slot `4` (`Vistara Diamond`, grey signature padlock); crisp metallic slot ticks (`pk=-34.6 to -39.4 dBFS`, no BGM). |
| 3 | HUD/UI | `UI3` | `Vistara Diamond Card` | `(460, 865)` | `(460, 1044)` | `pill_left` | `(172, 710, 750, 1025)` | `Vistara Diamond` tooltip card (`A mysterious gem that allows the holder to see traps and treasures.`) with diamond-caliper preview. |
| 4 | Visual | `V3` | `Cap Equipped on Spider` | `(940, 240)` | `(1120, 210)` | `pill_right` | — | 3D Spider turntable wearing reddish-brown `Cap` headgear (updated from Bowler Hat, mirrored in right `Head` slot). |
| 5 | HUD/UI | `UI4` | `Updated Head Preview` | `(1612, 315)` | `(1460, 140)` | `pill_right` | `(1525, 225, 1695, 405)` | `Head` thumbnail synced to equipped `Cap` alongside `Body` (`Classic`), `Calling Card`, and `BACK [ESC]`. |

#### `KF05` — `KF05_00m20s_telescope_cheese_moon.jpg` (`S05`, `00:20.80`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | Visual | `V1` | `Night Sky & Moon` | `(1360, 160)` | `(1530, 250)` | `pill_right` | — | Bright crater-textured full moon in upper-right against cloudy teal-blue night sky and faint stars. |
| 2 | Visual | `V4` | `Golden Cheese Wedge` | `(975, 480)` | `(1190, 355)` | `pill_right` | — | Giant rotating golden Pac-Man-shaped cheese wedge (`x=800..1154, y=342..689`) suspended over Kilcairn rooftops. |
| 3 | Visual | `V5` | `Orbiting Cheese Chunks` | `(575, 415)` | `(430, 240)` | `pill_left` | — | Three porous golden cheese chunks orbiting the central giant wedge (`x~575`, `745`, and `1315`). |
| 4 | HUD/UI | `UI1` | `Telescope [F] EXIT` | `(930, 535)` | `(960, 840)` | `pill_right` | — | `[F] EXIT` prompt centered in telescope reticle, accompanied by subtle `NW` compass and `Johnny Cipher` (`4`) card. |
| 5 | Gameplay/Audio | `AU2` | `Rooftop Wind Swell` | `(310, 620)` | `(160, 840)` | `pill_right` | — | Dark Kilcairn chimney silhouettes; exterior wind whoosh swell (`00:19.6–00:21.9`, peaking `-39.5 dBFS` RMS / `-29.8 dBFS` pk, no BGM). |

#### `KF06` — `KF06_00m24s_den_wanted_window.jpg` (`S05`, `00:24.60`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | Visual | `V1` | `Arched Frosted Window` | `(780, 350)` | `(1140, 210)` | `pill_right` | — | Arched leaded-glass frosted window radiating a volumetric teal-cyan moonlight shaft into the attic Den. |
| 2 | Visual | `V4` | `Wall Electrical Fuse Box` | `(315, 405)` | `(160, 220)` | `pill_right` | — | Mounted industrial electrical fuse box with twin circular gauges on left timber wall beside window. |
| 3 | Visual | `V3` | `Open Armoire & Mirror` | `(105, 730)` | `(180, 950)` | `pill_right` | — | Open illuminated Wardrobe mirror and curved brass wall lamp on far left (`[F] CUSTOMIZE LOADOUT` station). |
| 4 | Gameplay/Audio | `G1` | `Brass Tripod Telescope` | `(845, 945)` | `(680, 990)` | `pill_left` | — | Brass tripod telescope below window (`[F] PONDER`); wooden footsteps (`00:23.1–00:23.9`, `pk=-27.1 dBFS`) in quiet Den (no BGM). |
| 5 | Visual | `V5` | `5 Framed Wanted Posters` | `(1475, 720)` | `(1230, 470)` | `pill_left` | `(1275, 515, 1665, 1075)` | Five Wanted posters (`HIS HANDS ARE FAST`, `CHARMING MAN?`, `TELL A CONSTABLE!`, `£10000`, `REWARD £5000`) on right wall. |
| 6 | HUD/UI | `UI1` | `Top-Right Player Card` | `(1750, 95)` | `(1565, 110)` | `pill_left` | `(1605, 18, 1900, 165)` | Top-right `Johnny Cipher` card (level `4`) and subtle top-center compass ticks. |

#### `KF07` — `KF07_00m27s_ledger_journal.jpg` (`S06`, `00:27.00`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | HUD/UI | `UI1` | `Journal / Market Tabs` | `(960, 88)` | `(1290, 88)` | `pill_right` | `(685, 60, 1235, 118)` | `[Q] JOURNAL` (active) and `BLACK MARKET [E]` Ledger navigation tabs. |
| 2 | HUD/UI | `UI2` | `Level 4 XP Progress` | `(780, 220)` | `(1605, 220)` | `pill_right` | `(360, 130, 1575, 345)` | `Johnny Cipher` portrait, `Level 4` header, and teal XP progress bar reading `94/500`. |
| 3 | HUD/UI | `UI3` | `Contract #1 Clipped` | `(110, 620)` | `(55, 345)` | `pill_right` | — | Left-clipped `Completed` `Contract #1` card (`...nd managed... The "Vistara... origins.`). |
| 4 | HUD/UI | `UI4` | `Contract #2 Lore Card` | `(670, 680)` | `(670, 1020)` | `pill_left` | `(262, 398, 1082, 958)` | `Completed` `Contract #2` — *Into the Lion's Den* detailing Vistara Diamond looted from Calcutta 50 years ago and smuggled by Hugh Montgomery. |
| 5 | HUD/UI | `UI5` | `Contract #3 Active Card` | `(1515, 680)` | `(1210, 1020)` | `pill_right` | `(1108, 398, 1915, 958)` | `Active` `Contract #3` — *In the Eye of the Beholder* (Mary Elway & Hugh Montgomery marriage condition) with cursor. |
| 6 | Gameplay/Audio | `AU1` | `Parchment & Tab Clicks` | `(1815, 1030)` | `(1690, 1025)` | `pill_left` | — | `BACK [ESC]` prompt; Ledger opens with crisp parchment rustle & tab clicks (`00:26.6–00:27.1`, `pk=-30.4 dBFS`, zero BGM). |

#### `KF08` — `KF08_00m28s_ledger_black_market.jpg` (`S06`, `00:28.50`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | HUD/UI | `UI1` | `Assets Banner (£26,275)` | `(960, 180)` | `(670, 180)` | `pill_left` | `(720, 145, 1200, 215)` | `BLACK MARKET [E]` active tab (hovered by cursor) above `YOUR TOTAL ASSETS: (£) 26,275`. |
| 2 | HUD/UI | `UI2` | `Zipwire Purchase Card` | `(300, 400)` | `(55, 180)` | `pill_right` | `(155, 235, 895, 628)` | Selected `Zipwire` preview box showing `✓ PURCHASED` badge, 3D model, and grapple description. |
| 3 | HUD/UI | `UI3` | `Tools & Guild Perks` | `(510, 800)` | `(520, 1035)` | `pill_left` | `(105, 635, 925, 985)` | `TOOLS` (`Zipwire`, `Smoke Bomb` `✓`; 3 fairies/sap `🔒`) and `GUILD PERKS` (`Novice`, `Guildhall`, `Elway Manor`, `The Spider` `✓`; `Thief`/`Master`/`Chameleon` `🔒`). |
| 4 | HUD/UI | `UI4` | `Spider Cosmetics Table` | `(1170, 320)` | `(1245, 212)` | `pill_right` | `(955, 248, 1385, 1018)` | Scrollable `SPIDER COSMETICS` column showing `✓` (`Bowler Hat`), prices (`7,500`, `5,000`, `2,500`), and pink padlocks (`🔒`). |
| 5 | HUD/UI | `UI5` | `Chameleon Cosmetics` | `(1615, 320)` | `(1550, 155)` | `pill_right` | `(1400, 248, 1835, 1018)` | Scrollable `CHAMELEON COSMETICS` column showing all 17 visible entries locked with pink padlocks (`🔒`). |
| 6 | Gameplay/Audio | `AU1` | `Quiet Market Browse` | `(1815, 1030)` | `(1690, 1042)` | `pill_left` | — | `BACK [ESC]` prompt; tab click (`00:28.0`, `pk=-34.5 dBFS`) followed by `~5.8 s` quiet reading (`-68 dBFS` room tone, zero BGM). |

#### `KF09` — `KF09_00m46s_den_gramophone.jpg` (`S07`, `00:46.25`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | Gameplay/Audio | `AU3` | `Diegetic Brass Gramophone` | `(745, 300)` | `(1160, 210)` | `pill_right` | — | **ONLY music in clip:** brass-horn Gramophone playing warped wind-up + scratchy 1920s jazz/ragtime with vinyl crackle (`00:45.4–00:47.8`, `pk=-24.9 dBFS`). |
| 2 | HUD/UI | `UI1` | `Interact [F] TURN OFF` | `(955, 540)` | `(1210, 430)` | `pill_right` | — | Center reticle `[F] TURN OFF` prompt (flipped from `[F] TURN ON` after switch click at `00:44.4`) with subtle `SE` compass above. |
| 3 | Visual | `V1` | `3-Candle Candelabra` | `(415, 220)` | `(230, 75)` | `pill_right` | — | Warm 3-candle candelabra casting amber highlights onto the fluted brass horn and wooden trunk. |
| 4 | Gameplay/Audio | `G1` | `Interactive Trunk Gems` | `(100, 205)` | `(55, 430)` | `pill_right` | — | Faceted pink gem resting atop stacked trunks (swappable via `[F] CHANGE DECORATION` alongside Fabergé egg / golden chalice). |
| 5 | Visual | `V2` | `Iridescent Table Diamond` | `(1250, 642)` | `(1390, 720)` | `pill_right` | — | Faceted iridescent white-blue diamond shader on chest top beside Gramophone. |
| 6 | Visual | `V3` | `Glowing Green Diamond` | `(60, 645)` | `(160, 860)` | `pill_right` | — | Emissive faceted green diamond resting on left floorboards beside trunk shadow. |

#### `KF10` — `KF10_00m52s_den_map_table.jpg` (`S08`, `00:52.35`)
| # | Category | Code | Label | Target `(tx, ty)` | Anchor `(lx, ly)` | Placement | BBox `(x1,y1,x2,y2)` | Observed UE5 Detail |
|---|---|---|---|---|---|---|---|---|
| 1 | HUD/UI | `UI1` | `Mission Settings Card` | `(748, 130)` | `(495, 120)` | `pill_left` | `(555, 8, 900, 255)` | Top-center floating card: `CONSTABLES' GUILDHALL`, `[H] Difficulty: Novice`, `[R] Mode: Solo`, `[F] Prepare for Mission`. |
| 2 | Gameplay/Audio | `G1` | `3D Map Token Selected` | `(775, 505)` | `(42, 310)` | `pill_right` | — | Highlighted 3D wooden `CONSTABLES' GUILDHALL` token on `KILCAIRN` parchment map (second `ELWAY MANOR` token bottom-left). |
| 3 | HUD/UI | `UI2` | `Center [F] ENTER MATCH` | `(965, 548)` | `(1530, 640)` | `pill_right` | — | Center reticle `[F] ENTER MATCH` prompt over illuminated parchment map; Map Table toggle clicks (`00:52.2–00:55.1`, `pk=-38.3 dBFS`, no BGM). |
| 4 | Visual | `V1` | `Brass Banker's Lamp` | `(985, 195)` | `(1045, 100)` | `pill_right` | — | Brass banker's lamp casting warm directional pool across `KILCAIRN` map & Guildhall token (`NE` compass visible above). |
| 5 | Visual | `V4` | `Marble Bust & Card` | `(1415, 220)` | `(1565, 260)` | `pill_right` | — | Classical white marble bust on table corner beside top-right `Johnny Cipher` (`4`) player card. |
| 6 | HUD/UI | `UI3` | `Bottom-Right Legend` | `(1760, 985)` | `(1570, 985)` | `pill_left` | `(1635, 925, 1890, 1050)` | Bottom-right keybind legend (`JOIN GAME [F]`, `TOGGLE MODE [R]`, `TOGGLE DIFFICULTY [H]`). |

---

## 5. Verification Method

1. **Tooling & Font Check**:
   ```bash
   /usr/bin/python3 -c "import PIL, numpy; from PIL import ImageFont; ImageFont.truetype('/usr/share/fonts/google-noto/NotoSans-Bold.ttf', 16); ImageFont.truetype('/usr/share/fonts/google-noto/NotoSans-SemiBold.ttf', 17); print(PIL.__version__, numpy.__version__)"
   ```
   Expected: `13.0.0 2.5.4`, exit code `0`.
2. **Spec Geometry Validation**:
   Validate `/home/john/.gemini/antigravity-cli/scratch/teamwork/1e28850f-0df2-429b-91da-3531b27dbba7/.agents/teamwork/teamwork_explorer_m2_r1_1/callout_spec_kf01_10.json` against `docs/reference/clip_1795033698901/clean/KF01..KF10` ensuring `0` out-of-bounds pills (`[16, 16, 1904, 1064]`), `0` pill-to-pill overlaps (`pad=8`), `0` HUD overlaps, `0` leader-to-pill intersections, `<= 4` words per label, and `<= 5%` bright pixels under every pill. (Executed: `Verified 10 keyframes, 58 callouts. TOTAL ISSUES: 0`.)
3. **Repo Hygiene Check**:
   `git -C /home/john/Projects/TAT-2 status --short` — confirm zero changes inside `/home/john/Projects/TAT-2` from Explorer 1.
4. **Invalidation Conditions**: If the Worker alters pill height (`>32px`), label font size (`>17px`), or horizontal padding (`>12px`), re-run the geometry bounding-box collision check before saving `annotated/KF01..KF10`.
