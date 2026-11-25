# T05-UI — remediation report

Team: **T05-UI** · branch `rem/T05-ui` · worktree `/home/john/Projects/TAT-2-rem-T05-ui`
Base: `38e7b03` · Date: 2026-11-25
Scope: `game/src/ui/**` (hud, main_menu, contract_table_ui, mission_prep_ui,
art_nouveau_theme, new `ui_strings.gd`), new tests under `game/tests/`.
No Vulkan capture was run. Every number below is a headless measurement or a
source/extract quote; the pixel confirmation of the prep frame remains the
integrator's step.

---

## Team summary

| verdict | count | findings |
|---|---|---|
| **FIXED** | 11 | prep camera regression (P0), prep skyline scale/contract, prep subject slot, LOCATION thumbnail crop, READY/UNREADY nameplate, HP-bar composition, HP splatter state, HUD duplication instrumentation + same-frame double draw, LAUNCH prompt contrast, pause backdrop dim + HUD hiding + footer collision, pause Den target + abandonment payout, authored 9-slice frames, five authored fonts + type scale, ST_HUD/ST_Screens/ST_PostMatch wiring, post-match panel |
| **PARTIAL** | 1 | l10n wiring (25 call sites / 19 distinct authored rows now table-driven; the remaining HUD literals have no authored rows) |
| **NOT REPRODUCED** | 1 | HP-frame right-cap duplication in the recorded client (one HudScript / one frame in-tree) |
| **BLOCKED-ON T07** | 1 | prep light/grade (ACES 2.6 / ambient 1.8; skyline `disable_ambient_light`) |
| **BLOCKED-ON T10** | 1 | `Cat Statue` bare `Label3D` nameplate (`loot_item.gd:180-186`) |
| **DEFERRED** | 3 | light-gem semantics (needs capture), compass ticks/hotbar glyphs, contract-selector raw map ids; XP/progression/tutorial screens |

Gate evidence (this worktree, serially):

| gate | result |
|---|---|
| compile (`check_scripts_compile.gd`) | **122 checked, 0 broken** (baseline 120; +`ui_strings.gd`, +`test_t05_ui_contract.gd`) |
| `make test` | **`SUMMARY: fails=0`** |
| `test_t05_ui_contract.gd` (new) | **`T05_SUMMARY: fails=0 checks=56`** |
| `test_hud_gem_compass.gd` | **`HUD_GEM_COMPASS_SUMMARY: fails=0`** (11 checks) |
| `test_w7v_ui_acceptance.gd` | **`W7V_SUMMARY: fails=0 checks=49`** (after repairing a polluted user save; see doc corrections) |
| E2E `run_e2e_tests.gd` (full) | **`SUMMARY: fails=0 passed=278 total=278`** (re-run on the final tree; the only E2E edit is the T1-13-C cast, count unchanged) |
| `make audit` | **AUDIT PASS** (baseline matches; `vgmstream` binary provisioned from the main checkout, `tools/bin/` is gitignored) |
| `build/qa/test_perf_guard.sh` | **`PERF_GUARD_TEST PASS checks=78 fails=0`** |

---

## S1–S6 register

| # | finding | sev | S1 site | S2 authored truth | S3 red | S4 fix | S5 test | S6 green | verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Prep stage reframe (“empty blue-violet void”) | P0 | `mission_prep_ui.gd:75-78,94` (`LOBBY_CAM_POS (4,1,10)`, 1.26 m dummy offset) | `MissionLobby_Geo3 CameraActor_0` (12.6065,−0.16698,−1.05384), pitch 6.685/yaw 173.186/roll −14.780/FOV 20; 2,107 meshes, 387 in the 10° cone | 6 FAILs incl. `P12 inside=13` | live camera = authored transform; subject = authored dummy slot; reframe lever removed | `test_t05_ui_contract.gd` P2–P12 | 56/0 | **FIXED** |
| 2 | `prep_skyline` pieces 2–5× oversized / not a distant layer | P0/P1 | `prep_skyline.json` scales 1.0–1.7 | KF11 distant city; authored lens 20°×11.33° | pre-fix `mid_roofline_a` = **1.58 frame widths**, top sy 0.161 | per-piece scales 0.56–0.75, absolute `base_y` contract, band constants | P13/P14/P14b–d | band green | **FIXED** |
| 3 | LOCATION thumbnail 3.54:1 crop of a 1.78:1 splash | P2 | `mission_prep_ui.gd:456` (`382×108`, `KEEP_ASPECT_COVERED`) | `MapSplash_Guildhall.png` 3138×1765 | measured art box **500×108 = 4.63:1** | `AspectRatioContainer` 1.778, 152 px tall | P19/P20 | 1.778:1, stack bottom 696 | **FIXED** |
| 4 | READY/UNREADY flips the nameplate too | P2 | `_refresh_ready_controls` shared `word` | KF11 01:00: label READY / button `[F] UNREADY` / hint `[F] UNREADY` | `run_tests.gd` pinned nameplate `UNREADY` | nameplate = state (READY), button+hint = action | P21 + updated suite assertion | green | **FIXED** |
| 5 | HP bar: flat fill, permanent splatter, wrong rect | P1 | `hud.gd:997-1023` (old) | `T_healthBar_straight_RGB.png` (shaped fill), frame/splatter 1024×256 | RED `authored_fill_referenced=false`, `hp_fill_class=ColorRect`, `splatter_visible_at_80pct=true` | shaped-fill TextureRect, splatter `<50 %`, shared 4:1 rect 256×64 | H7–H11 | green | **FIXED** |
| 6 | HUD “duplicate cap / doubled labels” | P1 | C-4: one HudScript, one frame | ADJUDICATIONS C-4: cause undetermined | one-instance counts were unproven | `debug_hud_counts()` + `_ready` build line; action-hint deferred-free double draw removed | H2–H6 | 1/1/1/1 | **NOT REPRODUCED** (render path) + same-frame double draw **FIXED** |
| 7 | `LAUNCH` prompt ~2 % contrast | P1 | `_refresh_action_hints` disabled colour `(0.55,0.62,0.76,0.48)` | KF16 both rows legible | disabled alpha 0.48 over lit walls | near-white body both states, 2 px shadow; separation 10 | H24 (see §5) | green | **FIXED** |
| 8 | Pause “RETURN TO THIEF’S DEN” → start screen, no payout | P1 | `hud.gd:1839-1846` | `BPUI_StartMenuOptions` Den action; AGENTS “every failure path owes a payout” | RED `pause_handler_targets_main_menu=true`, `banks_payout=false` | `_pause_return_to_den()`: settle via `build_payout("capture")`+`SaveSystem.bank_payout`, then mission scene contract 1 | H16–H19 | green | **FIXED** |
| 9 | Pause blurs but does not dim; HUD stays drawn; footer/legend collision | P1 | `hud.gd:1791-1870` | KF30 mean 38.1→5.2, no HUD | RED `pause_dim_alpha=0.72`, `hint_visible_while_paused=true` | dim 0.86, live HUD hidden/restored on resume | H12–H15 | green | **FIXED** |
| 10 | Authored 9-slice frames unused (“corrupted ribbon” substitute) | P1 | `art_nouveau_theme.gd` flat StyleBoxFlat | `T_PanelFrame_Primary` 0.2/0.4/0.2/0.3; `T_boxFrame_ornate_2` 0.22/0.32/0.22/0.22 | `theme_9slice_at_HEAD=0` | `add_authored_frame()` NinePatchRect, clamped non-zero margins | P14b–d, H6d | green | **FIXED** |
| 11 | Five authored fonts never loaded; type at ~47 % | P1 | `art_nouveau_theme.gd:66-74` | Balthazar 48/54, FacultyGlyphic 32/55, PermanentMarker, Caveat 28, Abel 24 | `theme_font_roles_at_HEAD=0` | five font accessors + `font_size_px()` 2/3 rule + menu/header/numbers roles | H6b/H6c | green | **FIXED** (roles applied; body/HUD sizes still need per-screen passes) |
| 12 | 54 StringTables / 1,687 rows, 1 read; 17 labels localised | P1 | `Loc.t(` only in its docstring; hardcoded literals | `ST_HUD`, `ST_Screens`, `ST_PostMatch` rows | `hud_stringtables_at_HEAD=0`, `prep_stringtables_at_HEAD=0` | new `ui_strings.gd` reader; prep 8 rows, HUD 2, main menu 4, post-match all | P22–P24, H5b, H20–H23 | green | **PARTIAL** |
| 13 | Post-match/XP screens absent; invented result panel | P1/P2 | `hud.gd:2004-2030` | `ST_PostMatch` 71 rows + `ST_Screens.PostMatch.*` | `invented_rating_strings=true` | authored status/mission/contract/haul panel, Continue → Den | H20–H23 | green | **FIXED** (XP breakdown still absent) |
| 14 | Prep light/grade (black-on-black skyline, ACES 2.6 / ambient 1.8) | P1 | `_grade_skyline_material`, `_build_stage` | gameplay AGX 1.0 / ambient 0.16 | measured in L3-02/C3-03 | not edited — T07 owns the grade | — | — | **BLOCKED-ON T07** |
| 15 | `Cat Statue` bare `Label3D` font 28, no panel | P2 | `loot_item.gd:180-186` (T10 file) | HUD toast language (`BPUI_ToastWidget`, `Toasts.MajorLootTaken`) | capture L3-17 | not edited | — | — | **BLOCKED-ON T10** |
| 16 | Light gem / compass / contract-selector ids | P2 | `hud.gd` gem, compass, `contract_table_ui.gd:141` | KF14/KF17/KF02; map names | capture L3-18/19/22 | not edited | — | — | **DEFERRED** |

---

## Prep regression: before/after numbers

All measurements are headless (`--headless --path game`, 1280×720 design canvas),
from the live `MissionPrepUI` stage or the generated `MissionLobby_*` JSON. No
pixel was sampled; the S3 pixel reference is `build/qa/vf_mission_prep.png`
(pre-regression) and the integrator’s capture is still the visual arbiter.

| measurement | before (`38e7b03`) | after (this branch) | source |
|---|---|---|---|
| `LOBBY_CAM_POS` | `(4.0, 1.0, 10.0)` | **`(12.6065, −0.16698, −1.05384)`** | `mission_prep_ui.gd:68` |
| distance from authored `CameraActor_0` | **14.06 m** | **0.00 m** | constant |
| `LOBBY_CAM_FWD` vs authored | dot 0.357 = **69.1° off** | dot **1.000 = 0.0°** | `:69` |
| live camera basis vs authored pitch/yaw/roll | `x=(0.868, 0.254, −0.426)` | `x=(−0.085, 0.253, −0.964)` = authored | test P10 |
| authored 10° cone (mesh pivots) | **13 / 2,107** | **387 / 2,107** | test P12 |
| subject slot | `(−0.4281, 0.82, −1.3868)` (W7V offset) | **`(−1.5871, 0.82, −0.7868)`** (authored dummy X/Z) | `:79` |
| thief chest screen x | 0.912 (off KF11 band) | **0.785** (KF11 0.70–0.84) | test P16 |
| thief soles screen y | — | **0.858** | test P17 |
| `mid_roofline_a` projected width | **1.58 frame widths** | **0.48** | probe / test P14 |
| all 8 pieces: max width | 1.58 | **0.54** (limit 0.60) | test P14 |
| all 8 pieces: top screen y | 0.161 … 0.860 (pre-fix port camera) | **0.746 … 0.954** (band 0.65–0.98) | test P14 |
| LOCATION art box | 500×108 = **4.63:1** (middle 50 % rows) | **270×152 = 1.778:1** (full splash) | test P19 |
| prep card stack bottom | 628 | **696** (≤ 710) | test P20 |

The cone numbers were independently reproduced from the generated level JSON
before the fix (`t05_probe_skyline.gd`: port camera 13, authored 387, total
2,107) and are now asserted by the test against the **live** camera.

### Why the camera, and what is not proven

`7128d43` (W6U1) replaced the authored camera with `(4,1,10)` aimed
`(−0.458,0.084,−0.885)`. That transform sees only 13 mesh pivots; the “void” was
the reframe. Restoring the authored transform puts the authored city (towers
75 m, `SM_DistantBuildingC` 140–387 m, mountain 2.4 km) back inside the lens.

Not proven here (needs the capture): that the authored frame *composes* as KF11
(the near Periphery storefront may dominate the lower/left frame) and that the
expansion skyline is still visually necessary. The expansion pieces are now a
low far-city layer by construction (horizon sy 1.09 under the authored pitch),
so they may be largely occluded by the near roof. **Recommendation:** after the
capture, decide whether to keep or retire `prep_skyline.json`; it is labelled
expansion content and this branch does not remove it.

---

## Finding details

### 1 — L3-01/L3-02, C3-01/C3-02, C5-02: prep reframe (P0, FIXED)

- **S1.** `mission_prep_ui.gd` constants `LOBBY_CAM_POS/_FWD` were the W6U1/W7V
  reframe; `LOBBY_THIEF_POS` carried the W7V dummy offset. The skyline consumer
  set `pos.y = base_y` while the JSON note claimed a camera-relative Y.
- **S2.** `extracted/json/Maps/MissionLobby/MissionLobby_Geo3.json`
  `CameraActor_0`: `RelativeLocation (1260.6521, −105.38367, −16.698135) cm`,
  `Pitch 6.68548 / Yaw 173.18552 / Roll −14.780165`, `FieldOfView 20.0`,
  `AspectRatio 1.778646`. Two always-loaded sublevels, 2,107 meshes; the
  position-only 10° cone holds 387 (C5-02).
- **S3.** New test on the reverted tree:
  `FAIL T05.P2 ... got (4.0, 1.0, 10.0)`, `P8`, `P10`,
  `P12 ... inside=13`. The pre-fix skyline probe measured `mid_roofline_a`
  at 1.58 frame widths, top sy 0.161 under the port camera.
- **S4.** `game/src/ui/mission_prep_ui.gd`: live constants = authored; removed
  the `LOBBY_CAM_YAW_DEG` reframe lever; dummy X/Z = authored; skyline `base_y`
  documented and enforced as absolute; band constants added.
  `game/data/expansion/prep_skyline.json`: per-piece scales re-authored against
  the authored lens (0.56–0.75) and the two right-edge pieces lifted onto the
  city’s rising ground (`base_y 18 / 6`) so their tops remain inside the band.
- **S5.** `game/tests/test_t05_ui_contract.gd` P1–P20: constants, live basis,
  cone count, skyline band (real spawned AABBs), subject framing, thumbnail
  aspect, card budget.
- **S6.** `T05_SUMMARY: fails=0 checks=56`.
- **Verdict: FIXED** (visual composition: capture pending, integrator).

### 2 — C3-05 / L3-09: LOCATION thumbnail (P2, FIXED)

- **S1.** `mission_prep_ui.gd:456` `custom_minimum_size = Vector2(382,108)`
  with `STRETCH_KEEP_ASPECT_COVERED`.
- **S2.** `MapSplash_Guildhall.png` is 3138×1765 (1.78:1); the 382×108 box is
  3.54:1 and (measured) actually laid out at 500×108 = 4.63:1.
- **S3.** `T05.P19` measured `aspect=4.630` before the fix.
- **S4.** An `AspectRatioContainer` (ratio 1.7779773, height 152, width follows)
  holds the full-width TextureRect; COVERED becomes an exact fit.
- **S5/S6.** `T05.P19` 1.778:1, `T05.P20` card stack bottom 696.
- **Verdict: FIXED.**

### 3 — C3-07 / L3-10: READY/UNREADY nameplate (P2, FIXED)

- **S1.** `_refresh_ready_controls` fed one `word` to label, button and hint.
- **S2.** KF11 at 01:00 (counting): nameplate `READY`, button `[F] UNREADY`,
  hint `[F] UNREADY · [ESC] BACK`.
- **S3.** `run_tests.gd` asserted `_readiness_lbl.text == "UNREADY"` while
  counting — the defect was pinned as expected behaviour.
- **S4.** Nameplate always `Ready`; button/hint use the action word.
- **S5.** `T05.P21`; `run_tests.gd` §60a assertion updated with the KF11
  evidence (not weakened: same count, corrected expectation).
- **S6.** `make test` fails=0; P21 green.
- **Verdict: FIXED.**

### 4 — ADJUDICATIONS C-4 / C3-08 / L3-13: health bar composition (P1, FIXED)

- **S1.** `hud.gd:997-1023` (old): flat `ColorRect` 204×20 under a 256×62 frame
  at a different rect; `hp_splatter` added unconditionally at 204×28.
- **S2.** Authored assets are all 1024×256 (4:1); `T_healthBar_straight_RGB.png`
  is the shaped fill and was never loaded (`grep` 0 hits at HEAD). The splatter
  is a damage state.
- **S3.** Red probe on `38e7b03`: `authored_fill_referenced=false`,
  `hp_fill_class=ColorRect`, `splatter_visible_at_80pct=true`.
- **S4.** `HP_BAR_MAX_W 256` + `HP_BAR_H 64`; shaped-fill TextureRect; frame and
  fill share the rect; splatter hidden at ≥50 %; ticks rescaled. `hp_fill`
  remains a `Control` (public contract) and its `size.x` still scales with HP.
- **S5/S6.** H7–H11 green. The E2E T1-13-C cast changed from `ColorRect` to
  `Control` because the assertion is about position/width, not node type.
- **Verdict: FIXED** for composition. The recorded **37 % rendered height** was
  not reproducible from this tree (code composes 256×64 at the authored 4:1
  aspect); see doc corrections.

### 5 — ADJUDICATIONS C-4 / RE-L-07: HUD duplication (P1, NOT REPRODUCED + one cause fixed)

- **S1.** One `HudScript`; one `hp_frame` (C-4). Candidate mechanisms:
  second instance, second frame, deferred same-frame rebuild.
- **S2.** C-4 requires the named experiment.
- **S3.** No in-tree reproduction: the new counts are 1 HudScript, 1 hp frame,
  1 fill, 1 objective label, 1 hint row.
- **S4.** Instrumentation (`debug_hud_counts()`, `TAT-2 HUD build: id=…`),
  plus `remove_child()` before `queue_free()` in `_refresh_action_hints`, which
  *did* produce a provable one-frame double draw of the hint rows.
- **S5/S6.** H2–H6 green.
- **Verdict:** hp-frame/cap doubling **NOT REPRODUCED** (render/upscale path or
  a different recorded build); action-hint same-frame doubling **FIXED**. A
  lossless 1:1 capture of the hp right cap is the remaining falsifier.

### 6 — L3-14 / C3-12: LAUNCH prompt contrast (P1, FIXED)

- **S1.** `_refresh_action_hints` disabled label `(0.55,0.62,0.76,0.48)`; rows
  rebuilt with `queue_free()` only.
- **S2.** KF16: both rows legible, same type system.
- **S3.** Capture L3-14: ~2 % luminance separation.
- **S4.** Near-white body in both states, 2 px black shadow, 10 px separation,
  20 px per-row minimum, immediate removal of old rows. No type/colour restyle.
- **S5.** H24 asserts the disabled hint colour alpha ≥0.75 and luma ≥0.55.
- **Verdict: FIXED** (pixel confirmation pending).

### 7 — C3-10 / L3-21 / RE-L-03: pause Den target + payout (P1, FIXED)

- **S1.** `hud.gd:1839-1846`: `change_scene_to_file("res://scenes/main_menu.tscn")`.
- **S2.** `BPUI_StartMenuOptions` has two separate actions (`QuitToThievesDen`,
  `QuitToMainMenu`); the Den hub is contract 1 (`thieves_den`) in the mission
  scene; AGENTS: every failure path owes a payout; `loot_inventory.gd`
  `build_payout("capture")` = carried lost, stashed kept.
- **S3.** Red probe: `pause_handler_targets_main_menu=true`,
  `pause_handler_banks_payout=false`.
- **S4.** `_pause_return_to_den()` → `_settle_run_for_exit()` (build+bank once,
  `GameState.resolve_phase()`) → contract 1 → `mission.tscn`.
  `save_system.gd` and `mission_controller.gd` untouched.
- **S5/S6.** H16–H19: target path, applied once, idempotent, phase resolved.
- **Verdict: FIXED.** T02-STATE should confirm the payout record shape (it uses
  the shared `build_payout`/`bank_payout` APIs, no new fields).

### 8 — L3-20 / V7-05: pause dim, HUD hiding, footer collision (P1, FIXED)

- **S1.** `_pause_root` dim was `Color(0.004,0.006,0.014,0.72)` and every live
  HUD element stayed visible; footer at design y 690 inside the hint row
  684–706.
- **S2.** KF30: world band 38.1 → 5.2 (~86 % darkening), no HUD, footer alone.
- **S3.** Red probe: `pause_dim_alpha=0.72`, `hint_visible_while_paused=true`.
- **S4.** Dim alpha 0.86; `_hide_live_hud_for_pause()` snapshots and hides every
  `_root` child except the pause root, restored on resume (this also removes the
  footer/hint-row collision, matching KF30’s hidden HUD).
- **S5/S6.** H12–H15 green.
- **Verdict: FIXED.**

### 9 — RE-L-20 / C5-03: authored 9-slice frames (P1, FIXED)

- **S1.** `art_nouveau_theme.gd` drew every panel as `StyleBoxFlat`;
  `add_teal_filigree` is the procedural substitute.
- **S2.** `BP_BorderStyle_Frame_Primary` → `T_PanelFrame_Primary` margins
  0.2/0.4/0.2/0.3; `BP_BorderStyle_Frame_Ornate` → `T_boxFrame_ornate_2`
  0.22/0.32/0.22/0.22 (1024², Box).
- **S3.** `theme_9slice_at_HEAD=0`.
- **S4.** `add_authored_frame()` (NinePatchRect behind content) with the authored
  fractional margins, clamped so a small widget never gets border > 42 % of its
  rect and never zero. Applied to prep cards, pause panel, result/post-match
  panel and `make_modal`.
- **S5/S6.** P14b–d (ornate, margins 225/119/225/119 on a 241 px card), H6d
  (primary on the pause panel).
- **Verdict: FIXED.**

### 10 — RE-L-18/19: five fonts + type scale (P1, FIXED)

- **S1.** Only Raleway/SourceSerifPro/SpecialElite were loaded; buttons 15 px.
- **S2.** Shipped text styles: Balthazar Header 54 / MenuButton 48;
  FacultyGlyphic numbers 32 / numbers_White 55; PermanentMarker
  Heading_Handwritten; Caveat MapTool 28; Abel Base_sessionlist 24. The port
  canvas is 1280×720 vs the authored 1920×1080 → 2/3.
- **S3.** `theme_font_roles_at_HEAD=0`; two `font_size 15` button styles.
- **S4.** `font_display/numbers/handwritten/map_hand/session()`; `font_size_px()`
  = authored × 2/3; `PX_MENU_BUTTON 32`, `PX_HEADER 36`, `PX_NUMBERS 21`,
  `PX_BODY 25`, `PX_TYPEWRITER 28`, `PX_MAP_HAND 19`, `PX_SESSION 16`.
  Applied to menu buttons, tabs, modal titles, prep card titles, level badge,
  Den look-at title, tactical map title, pause footer; dense button rows pass
  explicit 20/24/28.
- **S5/S6.** H6b/H6c green.
- **Verdict: FIXED for the authored roles that were measured; body/HUD text
  remains at port sizes** (raising every body label needs per-screen layout
  passes; recorded as an open risk).

### 11 — RE-L-14/15: localisation (P1, PARTIAL)

- **S1.** `Loc.t(` only in its docstring; 17 `_loc` sites; `ST_Settings` the only
  StringTable read.
- **S2.** 54 generated tables / 1,687 rows under
  `res://data/generated/tables/StringTables/`; `Loc` already maps source → GUID
  → translation with English fallback.
- **S3.** `hud_stringtables_at_HEAD=0`, `prep_stringtables_at_HEAD=0`.
- **S4.** New `game/src/ui/ui_strings.gd` (cached table reader; `st_text` =
  authored row → `Loc.t` → literal). Wired: prep countdown / mode / difficulty /
  ready-unready / contract-inactive / three mission descriptions; HUD
  `Map`/`[Hold] Ping Menu`; startscreen Play/Settings/Credits/Quit; post-match
  status/mission/contract/haul/loot lines/Continue. 25 call sites / 19 distinct
  authored rows (`grep -c UIStringsScript.`: hud 11, prep 10, main menu 4).
- **S5/S6.** P22–P24, H5b, H20–H23 green.
- **Verdict: PARTIAL** — the remaining HUD/menus literals (objective formats,
  prompts, loading status lines, map-table title) either have no authored row or
  belong to other teams’ files; the reader is now the single path for new work.
  Table production stays T01-PIPELINE (`tools/` untouched).

### 12 — RE-L-09: post-match panel (P1/P2, FIXED for the rack-up)

- **S1.** `hud.gd:1932-1961` printed invented `CONTRACT COMPLETE /
  CAPTURED BY THE CONSTABULARY`, `Score … Stealth Rating: GHOST/SHADOW/BRAWLER`.
- **S2.** `ST_PostMatch` 71 rows (`PostMatch.Status.Escaped/Caught`,
  `PostMatch.Mission.<Map>.<Type>.<Result>`, `PostMatch.Contract.<n>.<Result>`,
  `PostMatch.Haul`) + `ST_Screens.PostMatch.LootEarned/LootLost/CashInHand` +
  `Screen.Continue`.
- **S3.** Red probe `invented_rating_strings=true`.
- **S4.** Authored panel: status, mission outcome (key derived from map +
  mission id, omitted when the row is absent), contract outcome, haul block from
  `SaveSystem.get_last_match()`, Continue → Den. `show_result()` signature kept
  (mission_controller’s contract).
- **S5/S6.** H20–H23.
- **Verdict: FIXED** for the rack-up. XP breakdown / level-up / progression
  screens remain **MISSING** (no XP award record at this layer; `ST_PostMatch`
  XP labels exist but there is no honest value to show yet).

### 13 — P2 items reported, not fixed

- **Cat Statue (L3-17 / C3-11) — BLOCKED-ON T10.** Required change in
  `game/src/interact/loot_item.gd:180-186`: give the `Label3D` a theme font,
  `outline_size ≈ 8`, `modulate`, `fixed_size = true` (so it stops being
  distance-scaled), or better, replace it with a HUD-side nameplate driven by a
  signal using `ThemeScript.teal_panel_style` + `white_keycap`. The authored
  popup is `BPUI_ToastWidget` (smoke-material border, icon, Show/EyeCatchingShow)
  with `Toasts.MajorLootTaken` — no `OPENED` string exists (C5-03).
- **Light gem (L3-18), compass ticks/hotbar glyphs (L3-19), contract-selector
  raw map ids (L3-22): DEFERRED.** All need per-frame capture evidence or a
  separate layout pass; none is in the P0/P1 brief list.

---

## Doc corrections

1. **`T_PanelFrame_Primary` margins.** The brief/RE-L quote
   “0.5/0.4/0.5/0.28” belongs to `BPUI_PanelFrame_Crown`, which slices the two
   painterly strips `T_PanelFrame_Primary_L/_R` (512×1024). The single
   `T_PanelFrame_Primary` (1024²) is `BP_BorderStyle_Frame_Primary` at
   **0.2/0.4/0.2/0.3**. This branch uses the single-texture margins for
   `add_authored_frame(ornate=false)`.
2. **`Mission Starting in <Num>{number}...</>` IS in the locres.** RE-L-17 item 3
   says it is not; `en.csv` contains the row and `ST_Screens` has
   `Screen.MissionLobby.Countdown`. The prep countdown now reads that row.
3. **The pre-regression capture was taken from the *mirrored* camera.** C3-01
   correctly dates `build/qa/vf_mission_prep.png` before W6U1, but pre-W6U1 used
   `LOBBY_CAM_POS (12.6065, −0.16698, +1.05384)` / forward
   `(−0.986184, 0.116419, −0.117848)` — the Z-mirrored slot, not the authored
   `CameraActor_0` `(−1.05384 / +0.117848)`. This branch restores the
   **authored** camera per the P0 instruction; the resulting frame is not
   byte-identical to that old capture.
4. **`mid_roofline_a` “top at sy −0.42”.** Measured on this tree with the
   AABB-corner method at 1280×720: top sy **0.041** under the authored camera
   (0.161 under the pre-fix reframe), width **1.55–1.58** frame widths (the
   width figure matches the brief). The −0.42 figure could not be reproduced;
   the 1.57 width and the ~0.33 scale correction are confirmed.
5. **“HP bar renders at ~37 % of authored height” is not reproducible from this
   tree.** HEAD composes a 256×62 frame (4.13:1) over a 204×20 fill; the new
   composition is 256×64 (exactly 4:1). If the recorded client drew it at 10
   design px, that is a render/scale or different-build effect, not the current
   code. Pixel confirmation is still owed.
6. **`test_w7v_ui_acceptance.gd` is not hermetic.** A persisted
   `equipped_loadout.spider.head/body = AltA` (left by an earlier suite/user
   run) made W7V.2/.3/.5 fail on a clean tree. Resetting the save’s spider
   loadout to empty (authored defaults) restores `W7V_SUMMARY: fails=0
   checks=49`. The test should snapshot/restore the loadout, or the integrator
   should run it on a pristine profile.
7. **Sonar/ratchet note:** no `AGENTS.md`/`README`/`FIDELITY_GAPS`/
   `HANDOFF` edits were made by this team (integrator applies them).

---

## Open risks

1. **Prep composition is unverified visually.** The numeric contract is green
   (authored transform, 387-mesh cone, subject 0.785, skyline band), but only a
   capture can confirm the near Periphery facade does not dominate the frame and
   that the expansion skyline is still wanted. If it is redundant, retire
   `prep_skyline.json` in a follow-up (it is labelled expansion content).
2. **Prep grade remains T07’s.** `_grade_skyline_material` still sets
   `disable_ambient_light = true`, `emission_enabled = false`,
   `albedo_color ≈ 0.11`; the stage still uses ACES 2.6 + ambient 1.8 vs
   gameplay’s AGX 1.0 + 0.16. The skyline can still read black-on-black; the
   band test is geometric only. Coordinate before the capture.
3. **Type scale is partial.** Menu/header/numbers roles now use the 2/3 rule;
   body copy and HUD labels remain at port sizes. Raising them needs per-screen
   layout checks (objective strip, cards, ledger rows) and a capture.
4. **HP-bar duplication cause unknown.** One instance is proven in-tree; the
   recorded doubling may be an upscale/render artifact or a different build. A
   lossless 1:1 capture with the debug build line
   (`TAT-2 HUD build: id=1 root_children=… hp_frame=1`) is the falsifier.
5. **Post-match XP is absent.** The rack-up is authored; XP breakdown/level-up
   need an award record (T02/T10) before the XP screen can be built honestly.
6. **Pause payout semantics.** Abandonment is modelled as `capture` (carried
   lost, stashed kept) because no authored “abandon” outcome exists. T02-STATE
   should confirm this is the intended economy for a paused exit.
7. **E2E T1-13-C cast change.** One E2E line now types `hp_fill` as `Control`
   instead of `ColorRect`; the assertion (position/size) is unchanged. Counts
   are unchanged.
