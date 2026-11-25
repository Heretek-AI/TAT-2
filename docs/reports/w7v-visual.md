# W7V — KF11 skyline, Cotter wardrobe and acceptance captures

Worktree: `/tmp/opencode/tat2-w7v-visual` (base `74a43b8`)
Data: `XDG_DATA_HOME=/tmp/opencode/w7v-data`, captures under
`/tmp/opencode/w7v-captures` (PNG + `.txt` sidecar per shot).
Owned files: `game/src/ui/mission_prep_ui.gd`,
`game/src/ui/wardrobe_ui.gd`, `game/src/ui/ledger_ui.gd`, new
`game/src/ui/tool_preview.gd`, new `game/tests/test_w7v_ui_acceptance.gd`,
new capture scripts under `build/qa/`, and new tracked expansion content
`game/data/expansion/prep_skyline.json`.

## 1. KF11 prep — tracked TAT-2 expansion skyline

The two loaded lobby sublevels (`MissionLobby_Geo3` + `MissionLobby_Periphery`)
carry no usable skyline in the framed sector: the nine authored
`SM_DistantBuildingC` instances sit west, behind the Periphery storefront wall,
and the only clear sky was the narrow slot the W6U1 moon used at x 0.88. KF11
needs a full distant silhouette behind the thief.

`game/data/expansion/prep_skyline.json` is **new TAT-2 expansion content, not
shipped Kilcairn art**. It is a camera-relative layout (azimuth / distance /
base Y / yaw / scale) over shipped Skybox assets only:

| reused shipped asset | role |
|---|---|
| `/Game/Art/Environment/Skybox/Buildings/SM_DistantBuildingC` | roofline + horizon blocks (dormers, chimneys, lit windows) |
| `/Game/Art/Environment/Skybox/Buildings/SM_DistantTowerA` | KF11 clocktower spire |
| `/Game/Art/Environment/Skybox/Buildings/SM_DistantTowerB` | secondary tower |
| `/Game/Art/Environment/Skybox/SkyboxSmokestacks/SM_SkyboxSmokestacksA` | industrial stack |
| `/Game/Art/Environment/Skybox/SkyboxUrban/SM_Skybox_UrbanTowerB` | right-side tower |
| `/Game/Art/Environment/Skybox/Buildings/M_DistantBuildingC`, `ML/MI_DistantBuidingA`, `M_DistantTowerB`, `SkyboxSmokestacks/ML/MI_SkyboxSmokestacks`, `/Game/MaterialLibrary/Utility/M_DarkGrey` | authored albedo/emissive/ORM materials |

Runtime (`mission_prep_ui.gd`):

- `_load_prep_skyline()` validates `schema == tat2.prep_skyline/1` and
  `expansion: true`; a missing/drifted file leaves the authored sky untouched.
- `_add_prep_skyline()` spawns one `MeshInstance3D` per piece named
  `PrepSkyline_<id>`, in group `prep_skyline`, meta `expansion=true`, no
  collision/shape children, shadow casting OFF, and a stage-only night grade
  (`SKYLINE_ALBEDO_TINT`, `SKYLINE_EMISSION_SCALE`) so the skybox materials read
  as silhouettes under the prep stage's 2.6 exposure instead of white slabs.
- Subject placement is a **0.84 m dummy offset**, not a camera yaw: yawing into
  the near authored city block hid the moon. The camera keeps the authored
  mirrored slot, FOV 20 `KEEP_WIDTH`, roll −14.78°, and the
  `midnight_clear_mission_lobby` preset.
- Moon disc target `(0.76, 0.09)` (KF11 measured). Thief centre lands in
  0.70–0.84 with the ridge in the lower third.

## 2. Wardrobe — KF03/KF04 defaults + Chameleon Cotter

- Defaults no longer fall back to the alphabetic first row (`AltA` =
  Tarantula). `_default_outfit_key()` resolves
  `Outfit.<Thief>.Head.BowlerA`, `Body.Default`, `CallingCard.Default` for
  both thieves (KF03’s Spider wears the Bowler Hat).
- Chameleon now renders the authored **ThiefCotter** body and head, not Nisha:
  `COTTER_BODY_DEFAULT_PATH`, `_ALTA_`, `_ALTA_PatternB_` and all **18**
  `DT_CharacterOutfitsMetadata` Chameleon Head rows mapped to
  `SK_ThiefCotter__Head_*` meshes. `TopHatA.MonocleA` has no standalone mesh in
  the shipped set, so it uses the authored combined
  `SK_ThiefCotter__Head_TopHatA_MonocleA_BeardA.glb` (documented fallback).
- Chameleon preview plays `AN_ThiefCotter_WardrobeIdle` (Spider keeps
  `AN_ThiefNisha_WardrobeIdle`). Three-column KF03 layout and no APPLY button
  are unchanged.

## 3. Ledger/Black Market — live 3D tool preview

- New shared `game/src/ui/tool_preview.gd` (`ToolPreviewStage`): one authored
  tool-mesh map (all 7 catalog tools + blackjack) and one warm tool-card world,
  used by the Wardrobe tool card and the new KF08 preview.
- The Black Market preview card gains `LedgerToolPreview` (SubViewport,
  360×220) and shows the live 3D gear for tool rows; perks/cosmetics keep the
  authored reward icon (a real fallback, not an invented model). Closing frees
  the stage.
- The ledger root now sizes itself to `get_viewport_rect()` so the KF08 panel
  is centred at 1280×720 and 1920×1080 under the `canvas_items` stretch.
- Authored catalog rows, prices and gates are untouched.

## 4. Captures

Serialized native Vulkan under Xvfb 1920×1080; one Godot at a time; sidecars
carry engine/renderer/size/save/profile, camera pose+FOV+aspect, weather preset
and measured ROI luminance stats.

| PNG | content |
|---|---|
| `prep_before.png` | HEAD baseline (pre-wave) prep stage |
| `prep_after.png` | W7V KF11 stage: expansion skyline, moon at (0.76, 0.09), thief at 0.77 |
| `briefing_after.png` | KF13 free-play letter over the live safe room |
| `den_poster_after.png` | KF06/C2 Den Wanted-poster wall |
| `ledger_kf07_after.png` | KF07 Journal |
| `ledger_kf08_after.png` | KF08 Black Market with the Zipwire 3D tool preview |
| `wardrobe_kf03_after.png` | KF03 BowlerA/Default defaults |
| `wardrobe_kf04_after.png` | KF04 slot 3 expanded candidate row |
| `wardrobe_chameleon_after.png` | Chameleon Cotter body/head, BowlerA/Default/Default |
| `prep_720.png` | 1280×720 fit (no clipping) |
| `den_west_window_after.png` | C1: framed west opening, moonbeam lands mid-room |
| `den_poster_after.png` | C2: Wanted-poster wall |

C1/C2 are captured. C8 (Guildhall haze/wet ground) and C9 (horizon vs zenith)
are **not captured**: their camera/fog staging lives in the Guildhall mission
path (`mission_controller.gd`), outside this wave’s ownership (`hud.gd` and
`mission_controller.gd` were not touched). They remain open for the HUD/mission
pass.

Measured prep ROIs from `prep_after.txt` (luma, 2-px stride):

| ROI | mean | max |
|---|---|---|
| moon (x .62–.92, y .00–.26) | 0.209 | 0.870 |
| thief (x .68–.86, y .24–.96) | 0.203 | 0.991 |
| ridge / lower band (x .24–.88, y .68–.98) | 0.103 | 0.979 |
| skyline mid (x .44–.84, y .26–.60) | 0.121 | 0.823 |
| full frame | 0.121 | 0.979 |

Capture runtime note: the first post-grade prep attempt ran 12 min at 100 % CPU
because a failed GDScript parse spun the run (the function boundary was broken
while inserting the grade helper); after the fix the full nine-shot 1920 set
completed in **52 s** and the 720p fit in ~10 s. No real capture exceeded
~1 minute.

## 5. Tests

`game/tests/test_w7v_ui_acceptance.gd` (standalone, headless):

- W7V.1–.21 wardrobe defaults / Cotter paths / 18 head rows / idle / layout.
- W7V.22–.42 prep skyline JSON, spawn, groups, expansion meta, no collision,
  no shadow, moon-ray non-occlusion, moon screen anchor, thief band, ridge.
- W7V.43–.49 one ledger tool stage, tool-vs-icon fallback, stage freed on
  close.

## 6. Deferred (explicit)

- Monochrome slot-icon shader — visual-only polish, not shipped this wave.
- Blurred Ledger/Wardrobe panel background — visual-only, not shipped.
- Briefing paper tone/creases and the `SPACE` keycap — deferred to the HUD
  pass (`hud.gd` not touched).
- C8 Guildhall haze/wet ground and C9 horizon-vs-zenith captures — need the
  Guildhall mission staging owned by the HUD/mission lanes; not captured here.

## 7. Gates (serial, one Godot at a time)

| gate | result |
|---|---|
| compile (`check_scripts_compile.gd`) | **112 checked, 0 broken** |
| focused W7V (`test_w7v_ui_acceptance.gd`) | **W7V_SUMMARY: fails=0** (49 checks) |
| W6U1 briefing suite (reframed anchor) | **W6U1_SUMMARY: fails=0** |
| W6U2 catalog suite | **W6U2_SUMMARY: fails=0** |
| `make test` (`run_tests.gd`) | **SUMMARY: fails=0** |
| E2E tier 1 | fails=0 passed=115 total=115 |
| E2E tier 2 | fails=0 passed=110 total=110 |
| E2E tier 3 | fails=0 passed=25 total=25 |
| E2E tier 4 | fails=0 passed=14 total=14 |
| E2E total | **264/264** |
| `make audit` | **exit 2** — W7S generated-data drift + missing `vgmstream`, not this wave (verbatim below) |

`make audit` output (not fixed, not re-stamped):

```text
AUDIT FAILED: 6 failure(s)
FAIL: baseline: producer tools/parse_tables.py output gen:gameplay content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_gameplay.py output gen:gameplay content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_contracts.py output gen:gameplay/contracts.json content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_loot.py output gen:gameplay/loot_actors.json content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_containers.py output gen:gameplay/containers.json content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: tool version drift: vgmstream: 'vgmstream CLI decoder r2168 (Oct 25 2026)' -> 'missing'; regenerate affected outputs and run --refresh-stamps
```

Content checks still pass (`CONTENT_OVERRIDES: PASS`, disk-backed coverage
12657/12703 = 99.6 %, 0 unexpected).

## 8. Data-safety proof (`game/data`)

`git status --short game/data`:

```text
?? game/data/expansion/prep_skyline.json
?? game/data/generated
```

`git diff --stat -- game/data` is empty: none of the three tracked expansion
files (`briefing_overrides.json`, `content_overrides.json`,
`personal_spider.json`) is modified or deleted. The commit stages only
`game/data/expansion/prep_skyline.json`; `game/data/generated` is a read-only
symlink to the main checkout and is never staged. No producer, `make normalize`,
`make audit-refresh-stamps` or `tools/audit_baseline.json` change was made.
