# UE Ground-Truth Value Backlog — 14 playtest findings (F1–F14)

Source plan: `.omo/plans/tat2-playtest-ground-truth-fixes.md` Todo 1 (closes GAP-8, enables GAP-1–GAP-7).
Finding definitions: `.omo/drafts/tat2-playtest-ground-truth-fixes.md` Findings (cited path:lines), explore lane 2026-11-20.
Footage: `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` (clip `clip_1,795,033,698,901.mp4`, 30 KFs).

## Provenance (actual paths on this host)

- Steam install: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`
- Paks (actual): `TAT/Content/Paks/pakchunk0-Windows.{pak,ucas,utoc}` + `global.{ucas,utoc}` (2.8 GB). NOTE: the plan text wrote `TAT/Paks/`; the true mount root is `TAT/Content/Paks/` (verified 2026-11-20).
- Loose content root: `TAT/Content/` (only `Licenses/ Movies/ Paks/ Splash/` — game assets are cooked inside the Paks, not loose).
- Extractor: `tools/tat-extract/` (CUE4Parse 1.2.2.202611, GAME_UE5_5, commands `probe|list|json|tables|textures|meshes|anims|audio|raw`). Prior output: `/home/john/Projects/TAT-2/extracted/` (`filelist.txt` 22005 entries, `json/` 12560 files, plus `anims/ assets/ audio/ raw/`).
- Cooked-JSON root in this doc = `extracted/json/<path-without-TAT/Content-prefix>`; UE source path = full `TAT/Content/...` Pak path.
- Ghidra: `~/.local/bin/ghidra`; target binary `TAT/Binaries/Win64/TAT-Win64-Shipping.exe`. No Ghidra run was executed for this backlog; Ghidra rows are named targets with UE export anchors and `offset: TBD`. No decompiled bodies are pasted anywhere in this file (per the short-excerpts-only boundary).
- Port ownership cites per finding come from the draft Findings F1–F14 ledger and are repeated per row so each row is self-contained.

## Fallback ladder (per value row)

1. `cooked` — `tat-extract json|tables|meshes|textures` output already on disk under `extracted/json/` (verified by `python3 -c json.load` 2026-11-20, counts quoted per row).
2. `ghidra` — named `TAT-Win64-Shipping.exe` target + UE export anchor; offset TBD by the fix todo that consumes the row.
3. `footage` — KF timestamp from KEYFRAME_INDEX.md as the visual ground truth when cooked data cannot yield a number.

Status per row: `found` = cooked asset verified on disk (row is consumable by its fix todo for at least the asset identity/transform/material-list level; exact numeric extraction continues in the fix todo). `stalled` = no cooked asset yields the value; Ghidra target named, KF fallback cited, stall reason recorded. No row is `blocked` (nothing needs access we lack).

## Value rows

### F1 — Floating Den props (ground placement)
- Port ownership: `game/src/core/level_loader.gd:1574/1661`, `game/src/missions/mission_controller.gd:371` (hub offsets, no ground snap).
- UE source: `TAT/Content/Maps/ThievesDen/ThievesDen_Geo.umap` object `ThievesDen_Geo:PersistentLevel` (Pak `TAT/Content/Paks/pakchunk0-Windows.ucas/utoc`).
- Cooked value (found): `extracted/json/Maps/ThievesDen/ThievesDen_Geo.json` — 348 exports, first `ArrowComponent/Arrow` on `BP_CandelabraTableA_C_0`; per-prop `StaticMeshComponent` entries carry `AttachParent` + relative transform (ground-snap source = each prop actor's location vs its `BodySetup` bounds).
- Ghidra target: none needed for identity; numeric per-prop Z snap is fix-todo arithmetic, not RE.
- Fallback: KF02 (`00:04.50` Den entry, desk/ledger sightline) + KF09 (`00:46.25` gramophone/table props).
- Source + status: `cooked found`.

### F2 — Ledger / Black Market UI (layout + content)
- Port ownership: `game/src/ui/ledger_ui.gd:124/93/376/418`, `game/src/ui/art_nouveau_theme.gd`.
- UE source: `TAT/Content/Art/Environment/ThievesDen/Stations/SM_OpenedLedger.uasset` + `MI_OpenedLedger.uasset` + textures `T_OpenedLedger_D/N/ORM.uasset`; content rows `TAT/Content/Gameplay/Clues/ClueSets/Contracts/CLS_Contract_09..16.uasset` + `DT_ClueFacts_Contracts_*.uasset` (Pak as above).
- Cooked value (found): `extracted/json/Art/Environment/ThievesDen/Stations/SM_OpenedLedger.json` (3 exports, `BodySetup_0`); `MI_OpenedLedger.json` (`MaterialInstanceConstant/MI_OpenedLedger`); ledger map art `T_Map_ThievesDen_D.json` (`Texture2D`); contract tables present under `extracted/json/Gameplay/Clues/ClueSets/Contracts/` (CLS + DT rows; XP `94/500`, assets `(£) 26,275`, 4 tables confirmed on footage).
- Ghidra target: layout geometry (UMG `UWidget` rects) only if UMG JSON proves insufficient — target `TAT-Win64-Shipping.exe` + `BPUI` ledger widget export anchor, offset TBD.
- Fallback: KF07 (`00:27.00` JOURNAL: `Johnny Cipher`, Level 4, `94/500`, Contracts #1–3) + KF08 (`00:28.50` BLACK MARKET: `YOUR TOTAL ASSETS: (£) 26,275`, `TOOLS/GUILD PERKS/SPIDER COSMETICS/CHAMELEON COSMETICS`).
- Source + status: `cooked found`.

### F3 — Wardrobe UI (layout + content)
- Port ownership: `game/src/ui/wardrobe_ui.gd:152/179/233/323/393/440/627/674`.
- UE source: `TAT/Content/Art/Environment/ThievesDen/Stations/BP_ThievesDen_Wardrobe_Contents.uasset` + `SM_ThievesDen_Wardrobe.uasset` + `SM_ThievesDen_Wardrobe_Mirror.uasset` + `MI_ThievesDen_Wardrobe{,_NoAO}.uasset` + `MLI_ThievesDen_Wardrobe.uasset`; shell art `TAT/Content/Art/UI/Shell/wardrobe/T_wardrobeBackgroundImage.uasset` (Pak as above).
- Cooked value (found): `extracted/json/Art/Environment/ThievesDen/Stations/BP_ThievesDen_Wardrobe_Contents.json` (83 exports, `BlueprintGeneratedClass/BP_ThievesDen_Wardrobe_Contents_C`); `SM_ThievesDen_Wardrobe.json` + `T_ThievesDen_Wardrobe_D/N/ORM.json` present.
- Ghidra target: UMG rect values for the Head/Body/Calling-Card grid only if needed — target `TAT-Win64-Shipping.exe` + wardrobe `BPUI` export anchor, offset TBD.
- Fallback: KF03 (`00:07.00` WARDROBE loadout slots 1–4, Zipwire tooltip) + KF04 (`00:16.50` slot-3 4-tool row, Vistara Diamond tooltip).
- Source + status: `cooked found`.

### F4 — Map buildings static (grow/shrink behavior)
- Port ownership: `game/src/missions/mission_controller.gd:583/624-625/632`, `game/src/ui/hud.gd:374/1402/2711+`.
- UE source: `TAT/Content/Art/UI/Map/SM_MapBuilding_GuildHall.uasset` + `M_MapBuilding_GuildHall.uasset` + `T_MapBuilding_GuildHall_{D,N,ORM}.uasset` (Pak as above).
- Cooked value (found): `extracted/json/Art/UI/Map/SM_MapBuilding_GuildHall.json` (3 exports, `BodySetup_0`); `M_MapBuilding_GuildHall.json` (`Material/M_MapBuilding_GuildHall`); textures D/N/ORM present (OldManor siblings confirm the set shape).
- Ghidra target: scale-animation curve (if the grow/shrink is a timeline, not a material param) — target `TAT-Win64-Shipping.exe` + `SM_MapBuilding_GuildHall` actor tick anchor, offset TBD; fix todo decides material-param vs timeline.
- Fallback: KF10 (`00:52.35` KILCAIRN map, wooden `ELWAY MANOR` / `CONSTABLES' GUILDHALL` tokens, `[H]/[R]/[F]` card).
- Source + status: `cooked found`.

### F5 — Den window shows no vista (collision-only split, fake god-ray)
- Port ownership: `game/src/core/level_loader.gd:1489/1498/1511` + horizon `:923/:151/:1333` + occluders `:85/1463/1472/1447`; `mission_controller.gd:371+` (`DenMoonBeam`, `spawn_window_godray`).
- UE source: `TAT/Content/Art/Environment/Urban/WallWindow/SM_ThievesDen_WindowBorder.uasset` + `TAT/Content/Maps/ThievesDen/ThievesDen_Geo.umap` (window actor + vista actors in the same PersistentLevel) (Pak as above).
- Cooked value (found): `extracted/json/Art/Environment/Urban/WallWindow/SM_ThievesDen_WindowBorder.json` (3 exports, `BodySetup_0`); window placement + exterior-side actors enumerable in `Maps/ThievesDen/ThievesDen_Geo.json` (348 exports).
- Ghidra target: exterior skyline mesh identity only if the Geo level holds a placeholder — target `TAT-Win64-Shipping.exe` + `SM_ThievesDen_WindowBorder` spawn anchor, offset TBD.
- Fallback: KF02 (`00:04.50` moon shaft through arched frosted window) + KF06 (`00:24.60` leaded-glass window + Wanted wall).
- Source + status: `cooked found`.

### F6 — Telescope dead (ponder-cam + placeholder cheese)
- Port ownership: `game/src/missions/mission_controller.gd:678` + Area `:492-511` + card `:716`.
- UE source: `TAT/Content/ThirdParty/Stylized_Furniture/Meshes/SM_TeleScope.uasset` + `TAT/Content/Art/Gameplay/HidingSpots/BP_HidingSpot_Telescope.uasset` (both in `filelist.txt`) (Pak as above).
- Cooked value (found): `extracted/json/ThirdParty/Stylized_Furniture/Meshes/SM_TeleScope.json` (3 exports, `BodySetup_1`); textures `T_TeleScope_A/N/RMA.json` present per filelist.
- Ghidra target: `PONDER` camera FOV/zoom + rooftop-view target transform — target `TAT-Win64-Shipping.exe` + `BP_HidingSpot_Telescope` interact anchor, offset TBD.
- Fallback: KF05 (`00:20.80` telescope view: rooftops, full moon, rotating golden cheese + 3 chunks, `[F] EXIT`).
- Source + status: `cooked found`.

### F7 — Guildhall curbs are block corners (no curb meshes)
- Port ownership: `game/src/core/level_loader.gd:1685/2440/2315/2402/1284/2346`.
- UE source: `TAT/Content/Maps/Guildhall/Guildhall_Landscape.umap` + `TAT/Content/Maps/Guildhall/Guildhall_Geometry.umap` (landscape spline / curb static-mesh actors, if authored) (Pak as above).
- Cooked value: STALLED — `grep -ri curb|kerb filelist.txt` returns no curb asset; no `SM_*Curb*` in `extracted/json`. Cooked `Guildhall_Landscape.json` (156 exports) + `Guildhall_Geometry.json` (981 exports) are the search space, not the value.
- Ghidra target: `TAT-Win64-Shipping.exe` + UE export anchor `/Game/Maps/Guildhall/Guildhall_Landscape` (landscape spline segment actor) and `/Game/Maps/Guildhall/Guildhall_Geometry` (curb-adjacent static-mesh actors); function area = landscape-spline / static-mesh spawn path; offset TBD by Todo 8.
- Fallback: KF15 (`01:21.38` `BARRON'S DEMOLITION` alley, wet cobbles/crates/drums) + KF16 (`01:40.20` gate steps/cobbles) for curb profiles.
- Source + status: `ghidra stalled`.

### F8 — Missing meshes / floating ground (fallback chain + landscape)
- Port ownership: `game/src/core/level_loader.gd:551` fallback chain + `:746/:759/:309` (`_load_tex` null on `ResourceLoader.exists` fail) + landscape `:2440/2343-2346`.
- UE source: `TAT/Content/Maps/Guildhall/Guildhall_Landscape.umap` + `TAT/Content/Maps/Guildhall/Guildhall_Geometry.umap` + `TAT/Content/Maps/Guildhall/Guildhall_P.umap` (persistent) (Pak as above).
- Cooked value (found): `extracted/json/Maps/Guildhall/Guildhall_Landscape.json` (156 exports, `BodySetup_0` first); `Guildhall_Geometry.json` (981 exports, `ChaosDebugDrawActor_0` first); `Guildhall_P.json` present. Actor list is the missing-mesh cross-reference (fix todo diffs port fallback binds against these actors).
- Ghidra target: none for identity; exact missing-bind texture paths resolve in Todo 8 from the `:551/:746/:759` chain against these actor lists.
- Fallback: KF18 (`02:14.80` gate arch, griffins, stairs from the cable) + KF15 (`01:21.38` alley ground plane).
- Source + status: `cooked found`.

### F9 — Guildhall flicker (cull/occluder/glow + UNMAPPED car path)
- Port ownership: `game/src/core/level_loader.gd:404/407/441/462-467/472/562/1808/1678-1681` + `game/src/missions/mission_controller.gd:113/122-124/280` glow; car-mesh path UNMAPPED (Todo 3 probe).
- UE source: `TAT/Content/Maps/Guildhall/Guildhall_Geometry.umap` (cull/occluder volumes) + glow/emissive `MI_*` under `TAT/Content/Art/Environment/` (Pak as above).
- Cooked value: STALLED — per-actor cull/occluder flags + glow scalar values need per-export property pulls from `Guildhall_Geometry.json` that this backlog did not enumerate; car-mesh handler has no UE path yet (UNMAPPED, Todo 3 time-box).
- Ghidra target: `TAT-Win64-Shipping.exe` + UE export anchor `/Game/Maps/Guildhall/Guildhall_Geometry` (occluder/cull volume actors); function area = occlusion-culling + emissive bind path; offset TBD by Todo 8. Car path: no target yet — Todo 3 probe first.
- Fallback: KF27 (`03:27.60` foyer beams/emitters) + KF29 (`03:39.40` slate stairs under crimson alarm) for flicker sightlines; car sightline KF16 (`01:40.20` headlights on wet cobbles).
- Source + status: `ghidra stalled`.

### F10 — Diamond tool light blinding (emissive + bloom, no FP light node)
- Port ownership: `game/src/player/thief_character.gd:2393/2402-2404/2430-2432/2514/1058-1060/2636` + `vfx_manager` spawn knobs `0.3-4.5` + `light_probe.gd:115` + mission glow `0.65`.
- UE source: `TAT/Content/Gameplay/Tools/PrimaryTools/VistaraDiamond/BP_VistaraDiamond_Tool.uasset` + `TAT/Content/Art/Gameplay/Gear/VistaraDiamond/MI_VistaraDiamond.uasset` + `SK_VistaraDiamond.uasset` (Pak as above).
- Cooked value (found): `extracted/json/Gameplay/Tools/PrimaryTools/VistaraDiamond/BP_VistaraDiamond_Tool.json` (`BlueprintGeneratedClass/BP_VistaraDiamond_Tool_C`, 2 exports); `extracted/json/Art/Gameplay/Gear/VistaraDiamond/MI_VistaraDiamond.json` (`MaterialInstanceConstant/MI_VistaraDiamond` — emissive/energy scalars live here for Todo 10); `SK_VistaraDiamond.json` present.
- Ghidra target: none for identity; energy-cap number finalizes in Todo 10 from the MI scalars.
- Fallback: KF21 (`02:32.20` RED guard silhouette in diamond scan) + KF22 (`02:33.00` GREEN transition, courtyard glint) + KF09 (`00:46.25` Den table diamond reference).
- Source + status: `cooked found`.

### F11 — Guards render white (GLB-loaded-with-missing-textures)
- Port ownership: `game/src/ai/guard_ai.gd:200/224/237/395` (`get_material_for_ue` / `_load_tex` path).
- UE source: `TAT/Content/Art/Animation/GuardEnforcer/Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body{,_Elite}.uasset` + heads `SK_Guard_Head*.uasset` + `TAT/Content/Art/Character/GuardEnforcer/Base/MI_GuardEnforcer_Body{A,C}.uasset` + `MI_GuardEnforcer_Bottom.uasset` + `TAT/Content/Character/Guards/BP_GuardEnforcer_Club{,B,Lantern}.uasset` (Pak as above).
- Cooked value (found): `SK_GuardEnforcer_Dyn__Body.json` + head variants present in `extracted/json/Art/Animation/GuardEnforcer/Skin/Base/`; `MI_GuardEnforcer_BodyA/C.json` present in `extracted/json/Art/Character/GuardEnforcer/Base/`; `BP_GuardEnforcer_Club.json` present in `extracted/json/Character/Guards/`. Material list is the coverage source for the Todo 3/7 bind check.
- Ghidra target: none for identity; missing-texture bind proves out in Todo 7 against `mesh_materials.json/materials.json` coverage.
- Fallback: KF16 (`01:40.20` gate guard with red eyes/flashlight/alert bar) + KF25 (`03:16.80` parlor constable, glowing blue hip baton).
- Source + status: `cooked found`.

### F12 — Guard AI / animation broken (state machine + clip roles)
- Port ownership: `game/src/ai/guard_ai.gd:260/274/280/292/303/317/331/346` + `game/src/core/animation_library.gd:179/243/247` + state machine `:125/140/195+`; compare `game/src/ai/civilian_npc.gd:152/208`.
- UE source: `TAT/Content/AI/StateTrees/ST_Guard.uasset` + subtrees (`ST_InvestigateStims_Guard`, `ST_Standby_Guards`, …) + `TAT/Content/Art/Animation/AnimationDataAssetMaps/CharacterAnimations/DAM_CharacterAnimationMapping_GuardBase.uasset` + `TAT/Content/Art/Animation/GuardEnforcer/ABP/AnimSet_Guard_Club{,Lantern,_Hauntsable}.uasset` (Pak as above).
- Cooked value (found): `extracted/json/AI/StateTrees/ST_Guard.json` (37 exports, `StateTree/ST_Guard`); `ST_InvestigateStims_Guard.json` + `ST_Standby_Guards.json` present; `DAM_CharacterAnimationMapping_GuardBase.json` (`TATCharacterAnimationMappingAsset`); `AnimSet_Guard_Club.json` (`AnimBlueprintGeneratedClass/AnimSet_Guard_Club_C`, 3 exports).
- Ghidra target: none for identity; transition/clip-role numbers resolve in Todo 7 from these JSONs.
- Fallback: KF16 (`01:40.20` patrol/alert) + KF25–KF26 (`03:16.80` pickpocket stance, `03:20.20` takedown grapple) + VO lines S13–S16 (`What?`, `too loud`, `I know someone's here!`, `Oh, I will find you, thief!`).
- Source + status: `cooked found`.

### F13 — Zipwire crank reload animation missing (manifest wiring)
- Port ownership: `game/src/core/animation_library.gd:84` manifest → `game/src/player/thief_character.gd:989/1001/1010/1031` + `game/src/ui/hud.gd:268/282-291`; no-op if manifest lacks clip / zero shared bones / `_fp_use_real_arms` false (`:998-1000`).
- UE source: `TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage.uasset` + cast/idle/travel set (`AN_Zipwire_CastIdle_*.uasset`) + `TAT/Content/Art/Gameplay/Gear/Zipwire/SK_Zipwire.uasset` + `SKEL_Zipwire.uasset` (Pak as above).
- Cooked value (found): `extracted/json/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage.json` (`AnimMontage/AN_Zipwire_Crank_Montage`, 2 exports); `SK_Zipwire.json` (`AnimCurveMetaData_1` first of 2 exports); cast-idle set present (`AN_Zipwire_CastIdle_000` + `_Reach` variants).
- Ghidra target: none for identity; bone-share + montage length finalize in Todo 9 from this JSON.
- Fallback: KF17 (`01:51.20` 2nd-shot anchor, `CRANK [LMB]` progress reticle, cable to parapet).
- Source + status: `cooked found`.

### F14 — RD cascade feeders (tiny textures, blur targets, VFX, glow gate)
- Port ownership: (a) `level_loader.gd:269/276/283/194/218/309`; (b) `weather_visuals.gd:66/54-56/173/273` + `mission_controller.gd:89/113/236/280`; (c) `vfx_manager.gd:174/328/651/732`; mobile glow gate `mobile_profile.gd`. Librarian verdict: matches `godotengine/godot#86631` (SSAO/SSIL + SubViewport <32 px on an axis → 6-mipmap request on a 2-mipmap target → null texture → slice/uniform/compute downstream fails); Item #4 UNSOURCED; fix direction = keep viewports ≥32 px, keep SSAO/SSIL (user decision 2026-11-20). Probe before fix: Todo 2.
- UE source: texture set behind the `:309` `_load_tex` chain (`T_*_D/N/ORM` across Den + Guildhall, e.g. `T_ThievesDen_Wardrobe_*`, `T_MapBuilding_GuildHall_*`, `T_TeleScope_*` — all in filelist) (Pak as above).
- Cooked value: STALLED — texture dimensions are enumerable from cooked `T_*.json`, but the cascade root cause is engine-side (live SubViewport sizes + RD blur-target sizes are port-runtime values, not UE data). UE texture caps alone cannot close this finding; Todo 2 probe is the value source.
- Ghidra target: `TAT-Win64-Shipping.exe` + texture-streaming/mipmap-budget path anchor (UE `Texture2D` export set above); offset TBD — only pursued if Todo 2 probe clears the port viewports and the cascade persists.
- Fallback: no single KF (engine-wide); live Den→Guildhall probe route per Todo 2 replaces footage as ground truth (`grep -c RenderingDevice.*ERROR` == 0 gate).
- Source + status: `ghidra stalled`.

## Machine-checkable index (all 14 findings)

```json
{
  "F1": {"source": "cooked", "status": "found"},
  "F2": {"source": "cooked", "status": "found"},
  "F3": {"source": "cooked", "status": "found"},
  "F4": {"source": "cooked", "status": "found"},
  "F5": {"source": "cooked", "status": "found"},
  "F6": {"source": "cooked", "status": "found"},
  "F7": {"source": "ghidra", "status": "stalled"},
  "F8": {"source": "cooked", "status": "found"},
  "F9": {"source": "ghidra", "status": "stalled"},
  "F10": {"source": "cooked", "status": "found"},
  "F11": {"source": "cooked", "status": "found"},
  "F12": {"source": "cooked", "status": "found"},
  "F13": {"source": "cooked", "status": "found"},
  "F14": {"source": "ghidra", "status": "stalled"}
}
```

Counts: 14/14 keys; 11 found (cooked), 3 stalled (F7, F9, F14 — Ghidra targets named above, no offsets invented).
Validation: `python3 -c` JSON parse exit 0 with 14 finding keys (see evidence `task-1.md`).
