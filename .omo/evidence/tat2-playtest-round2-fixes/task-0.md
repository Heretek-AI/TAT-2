# Wave 0 evidence ledger — task-0: build pin, symptom re-verification, extraction verdicts

Date (UTC): 2026-11-20. Tree: `/home/john/Projects/TAT-2` (round-1 fixes UNCOMMITTED in worktree).
Method: read-only (no product/tool/test edits, no `make test` — orchestrator runs suites at settle).
Only file written: this ledger.

## 1. Build pin (HEAD + worktree)

`git rev-parse HEAD` (run 2026-11-20, verified §5):

```
ca7e8ed307d7dc2b1d8459c2c2e2144bc50377d3
```

`git status --porcelain`:

```
 M game/src/ai/guard_ai.gd
 M game/src/core/animation_library.gd
 M game/src/core/level_loader.gd
 M game/src/missions/mission_controller.gd
 M game/src/player/thief_character.gd
 M game/src/ui/art_nouveau_theme.gd
 M game/src/ui/contract_table_ui.gd
 M game/src/ui/hud.gd
 M game/src/ui/ledger_ui.gd
 M game/src/ui/mission_prep_ui.gd
 M game/src/ui/wardrobe_ui.gd
 M game/tests/run_tests.gd
?? .omo/drafts/tat2-playtest-ground-truth-fixes.md
?? .omo/drafts/tat2-playtest-round2-fixes.md
?? .omo/evidence/
?? .omo/plans/tat2-playtest-ground-truth-fixes.md
?? .omo/plans/tat2-playtest-round2-fixes.md
?? .omo/waves/tat2-ground-truth/
```

`git diff --stat` (worktree = round-1 fixes, uncommitted):

```
 game/src/ai/guard_ai.gd            | 267 ++++++++++++++++++++++++++---
 game/src/core/animation_library.gd |  33 ++++
 game/src/core/level_loader.gd      | 291 +++++++++++++++++++++++++++++++-
 game/src/missions/mission_controller.gd | 189 ++++++++++++++++++---
 game/src/player/thief_character.gd |  19 ++-
 game/src/ui/art_nouveau_theme.gd   |   4 +
 game/src/ui/contract_table_ui.gd   |  11 ++
 game/src/ui/hud.gd                 |   7 +-
 game/src/ui/ledger_ui.gd           |  59 +++++--
 game/src/ui/mission_prep_ui.gd     |  74 +++++++-
 game/src/ui/wardrobe_ui.gd         |  20 ++-
 game/tests/run_tests.gd            |   7 +-
 12 files changed, 911 insertions(+), 70 deletions(-)
```

Pin covers HEAD (`ca7e8ed`) + the above worktree delta. All §3 code-span line numbers are worktree (post-round-1) lines.

## 2. Fresh live log capture (live Vulkan Forward+, Xvfb display, real NVIDIA GPU)

Command (bounded, no files written — output captured in memory):

```
Xvfb :99 -screen 0 1280x720x24
DISPLAY=:99 timeout 100 flatpak run org.godotengine.Godot --path game --resolution 1280x720 --quit-after 120 2>&1
```

Environment (from the log's own first line — no GPU limitation to record):

```
Godot Engine v4.7.2.stable.flathub.ed1daf0bf - https://godotengine.org
Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Laptop GPU
```

Counts over the full 71-line log:

```
RenderingDevice.*ERROR : 0
SCRIPT ERROR           : 0
Parse Error            : 0
minis_tween            : 0
KeyError/KEYERROR      : 0
telescope/vista lines  : 0
missing mesh WARNINGs  : 9
```

Missing-mesh warning UE paths (one line each, full set):

```
WARNING: [level_loader] missing mesh for UE path /Game/Art/Environment/Lights/Searchlight/VFX_SkySearchLight_Mesh; skipping draw item (no collider/occluder emitted)
    [level_loader.gd:1645 via _build_one_draw_item <- load_sublevels <- main_menu.gd:83 _build_3d_backdrop <- main_menu.gd:38 _ready]
WARNING: [level_loader] missing mesh for UE path /Engine/BasicShapes/Cylinder; skipping draw item (no collider/occluder emitted)
WARNING: [level_loader] missing mesh for UE path /Engine/BasicShapes/Plane; skipping draw item (no collider/occluder emitted)
```

(backtrace identical on all 9 lines; 2x Searchlight + 4x Cylinder + 3x Plane = 9.)

WHERE IT STOPPED: the run reached only the main-menu 3D backdrop
(`main_menu.gd:38 _ready` → `_build_3d_backdrop` → `level_loader.gd:2417 load_sublevels`)
and quit after 120 frames. It NEVER reached the Thieves' Den hub, the
Den→Guildhall transition, or any mission stage. There are 0 telescope lines,
0 vista lines, 0 minis lines in the log. This is therefore an Xvfb
correctness-only partial on a real GPU (rendering path is genuine live Vulkan
Forward+, not software rasterization), NOT a completed Den→Guildhall route.
Per the task rule, symptoms whose only possible evidence is Den/Guildhall
gameplay are marked UNPROVEN below, never CONFIRMED on log grounds; CONFIRMED
verdicts rest on fresh-log lines that DID fire (missing meshes) or on
current-tree code spans / the 12 dated screenshots.

Screenshots on disk (all 2026-11-20, `/home/john/Pictures/Screenshots/`):

```
Screenshot_20261120_092827.png  Screenshot_20261120_092837.png
Screenshot_20261120_092850.png  Screenshot_20261120_092900.png
Screenshot_20261120_092916.png  Screenshot_20261120_092927.png
Screenshot_20261120_092945.png  Screenshot_20261120_092957.png
Screenshot_20261120_093044.png  Screenshot_20261120_093047.png
Screenshot_20261120_093055.png  Screenshot_20261120_093058.png
```

Prior round-1 review of this set (draft findings): headless guards, blown lamp
blooms, floating gate slab, black unlit box, white unshaded pickup,
unclimbable stairs. Round-1 proof captures also on disk:
`.omo/evidence/tat2-playtest-ground-truth-fixes/proof-{den,guildhall,prep,wardrobe}.png`.

## 3. Per-symptom verdicts (10/10, each exactly one of CONFIRMED/STALE/UNPROVEN)

| # | Symptom | Verdict | Evidence (fresh log line, screenshot, or current code span) |
|---|---------|---------|--------------------------------------------------------------|
| 1 | telescope dead | CONFIRMED | Code pattern still in tree: `mission_controller.gd:816` `if not _is_thieves_den: return` silent guard in `toggle_telescope_ponder` (:815-848); entry split — Area3D `tele_script.interact` → `toggle_telescope_ponder()` (:521-523) vs input-only exit in `_unhandled_input` (:939-948). Fresh log: 0 telescope lines (route stopped at menu, §2). Round-1 worktree added vista focus + floor snap but left the guard/split intact. |
| 2 | window vista wrong | CONFIRMED | `level_loader.gd:1528-1538` `den_window_gap_spec` still carries the dead hand keys (`vista_moon_ue`, `vista_moon_bodies: 8`, `vista_glass_ue`, `vista_frame_ue` — no UE source); `:1736-1742` split stays collider-only (`_add_den_window_split` emits colliders, visual wall uncut). Round-1 `_spawn_den_window_vista` (:719-811 replica) exists but is unverified live. Fresh log: 0 vista lines (§2). |
| 3 | wardrobe mismatch | UNPROVEN | `wardrobe_ui.gd` (998 lines) was structurally reworked in the worktree (diff stat: 20 changed lines) against KF03/KF04; the draft's gap rows (portraits, lock badges, thumbnail cards, BACK placement, staging) can be neither reproduced nor cleared without the live capture harness, and the fresh run stopped at the main menu (§2). Needs per-fix live proof; not claimed either way. |
| 4 | GH mini frozen + minis_tween KeyError | STALE | Current disk code cannot throw it: `:673` `mi.get_meta("minis_tween", null) as Tween` (defaulted get + `is_valid` kill at :673-678), and `grep -rn minis_tween game/src/` = exactly those 2 lines — no dict-style access anywhere. Fresh log `minis_tween` = 0, `KeyError` = 0 (menu-only, non-probative alone). The user log's `:673` KeyError line numbers drift +40-90 vs disk → it came from a stale build. |
| 5 | crank 3P static | CONFIRMED | `thief_character.gd:998-1010` `_play_wire_crank_clip` is 1P-only by construction (`push_warning("...crank clip no-op without real arms...")`, `ensure_fp_clip(..., "zipwire_crank")`); no 3P crank rig/handle/anim-player node exists in the file. Fresh log cannot reach tools (menu only). |
| 6 | stairs unclimbable + floating ground | CONFIRMED | `thief_character.gd:37` `FLOOR_SNAP_LENGTH = 0.3` (step-down only, no step-up) + `:440` `floor_block_on_wall = true`; stairs risers still collide as full-AABB box faces (no stair-step relational shape in `level_loader.gd`). Round-1 `_ground_den_prop_shape` (:1518-1540) grounds only small (<2.5 m) floating props. Screenshots 092827-093058 set shows the floating gate slab + unclimbable stairs (draft findings). |
| 7 | blinding diamond/lamps | CONFIRMED | `DIAMOND_ENERGY_CAP := 0.65` covers the 1P gem surface only (`thief_character.gd:2406-2417` + assert); uncapped emitters remain in-tree: orb 2.2 (:2445), cable 2.8 (:1065), flashes 2-3, loader tongs path (draft). Screenshots show blown lamp-bloom orbs. Fresh log: 0 RD errors at menu (§2) — menu backdrop only, Den lamp rig never loaded. |
| 8 | takedowns absent | CONFIRMED | `grep -c takedown game/src/core/animation_library.gd` = 0 (no takedown role/clip/state); `thief_character.gd:1715-1750` `_try_blackjack` instant-KOs (`GameState.takedowns += 1`, noise emit) with no victim handoff. (Upstream clips exist — see §4 asset 5 — so this is wiring, not extraction.) |
| 9 | headless guards | CONFIRMED | `guard_ai.gd:590-646` `_bind_guard_glb_materials`: empty slots (notably `SK_GuardEnforcer__Preview` slots 0-2, upstream data gap) resolve to the logged navy fallback, and screenshots 092827-093058 show headless guards. Code only repaints missing heads; it cannot conjure geometry. (Upstream SK heads exist — see §4 asset 4.) |
| 10 | missing meshes | CONFIRMED | Fresh log (§2): 9 `missing mesh ... skipping draw item` WARNINGs naming `VFX_SkySearchLight_Mesh`, `/Engine/BasicShapes/Cylinder`, `/Engine/BasicShapes/Plane` via `level_loader.gd:1645`. Live-on-GPU proof the converted meshes are absent at runtime. |

Symptom counts: 10/10 verdicts — CONFIRMED 8 (1, 2, 5, 6, 7, 8, 9, 10), STALE 1 (4), UNPROVEN 1 (3).

## 4. Per-asset verdicts (8/8, each exactly one verdict; patterns quoted, hit or empty result quoted)

Conventions: PRESENT-UPSTREAM = in `extracted/filelist.txt` (22005 entries) but no
converted mesh under `game/assets/ue/` (extractor filter gap, cf.
`tools/tat-extract/Exporter.cs:200` allowlist `SM_/SK_/SKM_/GB_/Meshes//Mesh/…`
— no `VFX_`, `Coin_`, or Engine-package rule). PRESENT-BUT-UNWIRED = converted
data present in `game/data/generated/` but game code never binds/plays it.
MISSING-UPSTREAM = absent from filelist (nothing to extract; replica stands).

| # | Asset | Verdict | Evidence |
|---|-------|---------|----------|
| A1 | VFX_SkySearchLight_Mesh | PRESENT-UPSTREAM | Pattern `grep -c 'VFX_SkySearchLight_Mesh\|SkySearchLight' extracted/filelist.txt` → `3`: `TAT/Content/Art/Environment/Lights/Searchlight/VFX_SkySearchLight_Mesh.uasset`, `.ubulk`, `M_SkySearchLight.uasset`. Generated: no GLB (`find game/assets/ue -iname '*SkySearch*'` → empty); only tatlevel refs. Fresh log proves runtime absence (§2 warnings). |
| A2 | Coin_Bronze / Coin_Silver / Coin_Platinum | PRESENT-UPSTREAM | Pattern `grep -c 'Coin_Bronze\|Coin_Silver\|Coin_Platinum' extracted/filelist.txt` → `6` (all three `.uasset` + `.ubulk` under `.../Loot/LootMinor/Coins/`). Generated: no Coin Bronze/Silver/Platinum GLB (`find -iname '*Coin_Bronze*'` → empty; `ls .../Coins/` = `SM_CoinPileA.glb` only); `grep -ril 'Coin_Bronze' game/data/generated/` → only `ThievesDenTest_P.tatlevel.json` (a ref, not a mesh). |
| A3 | Engine BasicShapes (Cube/Cylinder/Plane/Sphere/Cone) | PRESENT-UPSTREAM | Pattern `grep -i 'BasicShapes' extracted/filelist.txt` → `11` hits (`Engine/Content/BasicShapes/{Cone,Cube,Cylinder,Plane,Sphere}.uasset` + `.ubulk` + material). Generated: `find game/assets/ue/Content/Engine -name '*.glb'` → `No such file or directory`; only tatlevel path refs (`grep -ril 'BasicShape\|BasicShapes' game/data/generated/` → Guildhall/OldManor tatlevels). Fresh log proves runtime absence (§2 Cylinder/Plane warnings). |
| A4 | guard heads | PRESENT-BUT-UNWIRED | Pattern `grep -i 'Guard.*Head\|Head.*Guard' extracted/filelist.txt` → `62` hits incl. `SK_Guard_Head01__Helm_Elite`, `SK_Guard_Head02__NoHelm`, `SK_Guard_Head03__NoHelm_Slick`, `SK_GuardSecurity_01__Head`, `SK_Hauntstable__Head` + `MI_`/`T_` head materials. Generated: `mesh_materials.json` carries the binds (`grep -c` Head → 130). Game binds them (`guard_ai.gd:590-646`) but empty Preview slots 0-2 fall to navy and screenshots show headless guards → data present, not rendering. |
| A5 | takedown clips | PRESENT-BUT-UNWIRED | Pattern `grep -c 'takedown\|Takedown' game/data/generated/anims_manifest.json` → `120`, e.g. `"name": "AN_Takedown_FallBackwards_Vic"`, `"AN_Takedown_Guard_Heavy_Front_Atk"` + `_Montage` variants (Atk + Vic). Game: `grep -c takedown game/src/core/animation_library.gd` → `0` — no role registered, instant-KO bypasses them (symptom 8). |
| A6 | telescope (SM_TeleScope + BP_HidingSpot_Telescope) | PRESENT-UPSTREAM | Pattern `grep -c 'Telescope\|TeleScope' extracted/filelist.txt` → `10`: `SM_TeleScope.uasset` + `.ubulk`, `BP_HidingSpot_Telescope.uasset`, `MI_TeleScope_Inst`, `T_TeleScope_{A,N,RMA}`. Generated: no GLB (`find -iname '*Telescope*'` → empty); refs only in `ThievesDenTest_P.tatlevel.json` + `mesh_materials.json`. (Game logic gap is separate — symptom 1.) |
| A7 | window border (SM_ThievesDen_WindowBorder) | PRESENT-UPSTREAM | Pattern `grep -c 'WindowBorder\|ThievesDen_Window' extracted/filelist.txt` → `3`: `SM_ThievesDen_WindowBorder.uasset` + `.ubulk` (+ unrelated Slate `WindowBorder.png`). Generated: no GLB (`find -iname '*WindowBorder*'` → empty); refs only in `ThievesDen_Geo.tatlevel.json` + `mesh_materials.json`. Loader routes the substring (`level_loader.gd:1184`) but has no mesh to draw. |
| A8 | den vista actors (moon + rooftop exterior kit) | MISSING-UPSTREAM | Pattern `grep -c 'MoonShape' extracted/filelist.txt` → `1`: only `BP_MoonShape.uasset` (+ `MI_MoonshapeEmissive`, `ThievesDen_Geo.umap` as the level shell). No dedicated vista/exterior kit exists upstream — the UE moons are in-level actors (`BP_MoonShape_C_0..C_7` per task-5, cooked inside `ThievesDen_Geo.json`). Nothing to extract; the procedural replica (`mission_controller.gd:719-811`, KF05-framed) stands as the F5-precedent fallback. |

Asset counts: 8/8 verdicts — PRESENT-UPSTREAM 5 (A1, A2, A3, A6, A7), PRESENT-BUT-UNWIRED 2 (A4, A5), MISSING-UPSTREAM 1 (A8).

Extractor note (spans re-read, not edited): `tools/tat-extract/Exporter.cs:194-200`
`Meshes()` allowlist explains A1/A2/A3/A6/A7 mechanically (name must start
`SM_/SK_/SKM_/GB_` or contain `/Meshes/`, `/Mesh/`, `/Test/LevelKits/`,
`/GasLamps/`, `/Furniture/Tables/`, `/Levers/`, `/GeneratedMeshes/`,
`/Developers/`).

## 5. Verification

- Re-read this file from disk before reporting (done).
- `git rev-parse HEAD` re-run at write time → `ca7e8ed307d7dc2b1d8459c2c2e2144bc50377d3` (matches §1).
- Every symptom has exactly one verdict: 10 rows, CONFIRMED/STALE/UNPROVEN = 8/1/1.
- Every asset has exactly one verdict: 8 rows, PRESENT-UPSTREAM / PRESENT-BUT-UNWIRED / MISSING-UPSTREAM = 5/2/1.
- Live-run stop point recorded (§2: main-menu backdrop, Den/Guildhall never reached); UNPROVEN used once (symptom 3), never as cover for a CONFIRMED claim.
- No product, tool, or test file touched; `make test` not run (orchestrator owns suites at settle).
