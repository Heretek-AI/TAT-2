---
slug: tat2-playtest-ground-truth-fixes
status: approved
intent: clear
review_required: true
plan_path: .omo/plans/tat2-playtest-ground-truth-fixes.md
plan_sha256: 68ec4e0fa218d59bbc6fd86aa025bcad606b89d0b07408c21a5f14fa5a6e9547
review_round_id: rr-mwohx8nl
review_round_limit: 5
pending-action: none — plan approved, handoff delivered
review:
  plan_reviewer:
    status: approved
    workspace_root: /home/john/Projects/TAT-2
    runtime_home: null
    target: .omo/plans/tat2-playtest-ground-truth-fixes.md
    round_id: rr-mwohx8nl
    plan_sha256: 68ec4e0fa218d59bbc6fd86aa025bcad606b89d0b07408c21a5f14fa5a6e9547
    launch_id: null
    session: null
    result: approved round rr-mwohx8nl (unconditional OKAY); round 1 rejection (empty success table) fixed and re-reviewed
approach: verify-against-ground-truth per finding
---

# Draft: tat2-playtest-ground-truth-fixes

## Affected user and ideal state
Player running the Steam build route (Den → Guildhall) against official footage; the developer verifying parity gates.
- IS-1 | A full live playtest run prints zero RenderingDevice ERROR lines | RD errors mean broken textures/passes on screen
- IS-2 | Den props rest on surfaces, the window shows the exterior, the telescope operates | core Den interactions from the reference route
- IS-3 | Ledger/Black Market and Wardrobe screens match the reference layout and content | diegetic UI parity gate family
- IS-4 | Guildhall geometry is complete and stable: curved curbs, no missing meshes/textures, ground at the right height, no flicker | exterior parity + 60 FPS gate
- IS-5 | Guards render with authored materials and move/animate per reference | AI/animation parity
- IS-6 | Zipwire crank reload animation plays on crank | tool parity (T1-43 family)
- IS-7a | Map buildings behave per reference | HUD/map parity
- IS-7b | Diamond tool light is sane, never blinding | tool light sanity
- IS-8 | Every Ghidra-derived value reproducible from committed scripts/offsets | executor and maintainer trust
- GAP-1 | Live run emits a null-texture RD cascade (slice views, bad mipmap chain, null uniform sets) | user playtest log 2026-11-20
- GAP-2 | Den has floating objects, dead window view, dead telescope | user findings 1, 5
- GAP-3 | Ledger/Market and Wardrobe UI do not match reference | user findings 2, 3
- GAP-4 | Guildhall has block corners, missing meshes, floating ground, flicker | user finding 6
- GAP-5 | Guards render white with broken AI/animation | user finding 8
- GAP-6 | Crank reload animation missing | user finding 9
- GAP-7 | Map buildings static; diamond light blinding | user findings 4, 7 | closed by C8
- GAP-8 | Ghidra-derived values not reproducible from committed artifacts | forgotten executor user (Plan Consultant) | closed by C7
<!-- Who this output touches (a customer, another programmer, a program or agent consuming it - often more than one) and how each uses it today and will use it after. -->
<!-- IS-n | property of the ideal state: nothing snags, feels odd, regresses, or degrades for them | reason -->
<!-- GAP-n | difference between IS-n and today | reason | closed by todo(s) -->

## Components (topology ledger)
- C1 | RD/texture pipeline emits zero ERRORs on a live Den→Guildhall run | active | user playtest log 2026-11-20
- C2 | Den interior: props grounded, window vista, telescope functional | active | /home/john/Videos/2026-11-19 23-08-20.mp4 + KF02-KF11
- C3 | Ledger/Market + Wardrobe UI match reference | active | KEYFRAME_INDEX.md + user findings 2, 3
- C4 | Guildhall exterior geometry complete and stable | active | user finding 6
- C5 | Guard materials + AI/animation per reference | active | user finding 8
- C6 | Zipwire crank reload animation plays | active | user finding 9 + T1-43
- C7 | UE ground-truth extraction (Paks/Content) feeds every fix | active | Thick As Thieves install + ~/.local/bin/ghidra
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->

## Findings (cited - path:lines)
Explore lane (2026-11-20): every finding mapped except car-specific mesh path (UNMAPPED) and engine-internal RD files (UNMAPPED as direct owners).
- F1 floating Den props: level_loader.gd:1574/1661 (collider skipped by clutter/hidden rules while visual emits); mission_controller.gd:371 (hub offsets, no ground snap; player-only snap :1320/1338, safety floor :1033).
- F2 ledger/market UI: ledger_ui.gd:124/93/376/418, teal theme art_nouveau_theme.gd (src/ui/).
- F3 wardrobe UI: wardrobe_ui.gd:152/179/233/323/393/440/627/674 (SubViewport turntable + OptionButtons, not reference layout).
- F4 map buildings static: mission_controller.gd:583/624-625 (fixed scale 0.24, highlight-only :632); 2D map hud.gd:374/1402/2711+ has no grow logic.
- F5 Den window no vista: level_loader.gd:1489/1498/1511 (collision-only split, no vista mesh); horizon rule :923/:151/:1333; occluders :85/1463/1472/1447. Shaft is fake (mission_controller :371+ DenMoonBeam + spawn_window_godray).
- F6 telescope dead: mission_controller.gd:678 (ponder-cam toggle + placeholder cheese only); Area ~:492-511; card :716.
- F7 block curbs: level_loader.gd:1685/2440/2315/2402/1284/2346 — no curb mesh generation exists.
- F8 missing meshes/floating ground: level_loader.gd:551 fallback chain, :746/:759/:309 (_load_tex null when ResourceLoader.exists fails); landscape :2440/2343-2346.
- F9 flicker: level_loader.gd:404/407/441/462-467/472/562/1808/1678-1681 + mission_controller.gd:113/122-124/280 glow; car mesh path UNMAPPED.
- F10 diamond blinding: thief_character.gd:2393/2402-2404/2430-2432/2514/1058-1060/2636 (emissive+bloom, no FP light node); knobs vfx_manager spawn_* 0.3-4.5, light_probe.gd:115, mission glow 0.65.
- F11 white guards: guard_ai.gd:200/224/237/395 — all-white is GLB-loaded-with-missing-textures (via get_material_for_ue :551 / _load_tex :309), not the navy fallback; confirm via mesh/material JSON coverage.
- F12 guard AI/anim: guard_ai.gd:260/274/280/292/303/317/331/346 + animation_library.gd:179/243/247 + state machine :125/140/195+; cf. civilian_npc.gd:152/208.
- F13 crank reload missing: animation_library.gd:84 manifest → thief_character.gd:989/1001/1010/1031 + hud.gd:268/282-291; no-op if manifest lacks clip, zero shared bones, or _fp_use_real_arms false (:998-1000).
- F14 RD cascade feeders (ordered): (a) level_loader.gd:269/276/283/194/218/309 tiny-texture/cap paths; (b) weather_visuals.gd:66/54-56/173/273 + mission_controller.gd:89/113/236/280; (c) vfx_manager.gd:174/328/651/732; mobile glow gate mobile_profile.gd.
- LIBRARIAN VERDICT (sourced, 2026-11-20): the cascade matches godotengine/godot#86631 — SSAO/SSIL enabled + a SubViewport <32px on an axis → engine requests 6 mipmaps on a target allowing 2 → texture_create returns null → every slice view / uniform set / compute dispatch downstream fails. Docs: SubViewport.size must be >=2px both axes (SubViewport.xml); ssao/ssil are Forward+-only toggles (Environment.xml). Fix direction: keep viewports >=32px both axes (fix container crush to 1x1), or disable ssao/ssil, or enable them only after the viewport is sized. The compute/uniform errors (#3) are downstream of the null texture — fix the texture first. Item #4 UNSOURCED as an engine bug: Image.resize builds a mipmap-less dest, so resize+clear_mipmaps+create_from_image is correct usage, NOT the mipmap culprit; suspect tiny RD blur targets instead.

## Decisions (with rationale)
- RD cascade fix direction (user-chosen 2026-11-20): fix tiny SubViewports (<32px axes / container crush), keep SSAO/SSIL for visual parity. Reversible.
- UE extraction depth (user-chosen 2026-11-20): full native RE of the functions behind the defects, regardless of time cost.
- QA per fix (user-chosen 2026-11-20): live Vulkan Forward+ proof plus headless suites on every fix todo; if GPU unavailable, Xvfb correctness now with deferred live proof recorded and the todo left open.
- All existing port code/parses/tools treated as defective until proven (user directive 2026-11-20); every fix todo re-derives its value from the UE install or reference footage with a cited source.
- Extraction order: existing tat-extract/CUE4Parse pipeline first, ghidra only where cooked data is insufficient.
- Stance: no planning-style episodes on record, CLEAR intent → one-by-one questions; say the word for batch.
- EULA boundary (user-chosen 2026-11-20): Ghidra excerpts may land in wave reports where needed for the fix.
- RE checkpoints (user-chosen 2026-11-20): value-ordered function backlog with per-function stall/fallback reporting.
- Plan Consultant folded 2026-11-20: add C8 (map/diamond, owns F4/F10, closes GAP-7); resolve F14(a)-librarian contradiction (drop resize/mipmap paths as suspects, keep null-on-exists-fail); C1 probe-before-fix (log live SubViewport + RD target sizes); narrow defective-until-proven reading per ownership paths; procedural geometry replicating cooked geometry is in scope; stack pinned (Godot 4.7.2 Forward+/Jolt, Linux x86_64, RTX 4070, 720p/1080p, allow_hidpi=false); this plan owns no-regression + RD-zero, numeric 60 FPS stays with tat2-godot-perf-60fps.md; C7 enabler with fan-out artifacts; UNMAPPED probes get time-boxed HARD_LIMIT exits; per-todo GPU-required/GPU-less labels; IS-8 extraction reproducibility.

## Scope IN
- C1–C7 fixes for the 14 playtest findings, each value re-derived from the UE install (extractors first, ghidra where cooked data fails) or reference footage, with live Vulkan + headless proof.
- Repro of the user playtest log as the C1 acceptance baseline.

## Scope OUT (Must NOT have)
- New features beyond the 14 findings; no refactors of files outside a finding's ownership.
- Tier-2 items from the master prompt (OldManor_P walk, Steam-56 full diff, Android) unless a finding's root cause lives there.
- Reduced subsets or phased deferrals of the 14 findings.

## Open questions
None — RD direction, RE depth, and QA level all user-decided 2026-11-20.

## Approval gate
status: awaiting-approval
Approach: verify-against-ground-truth per finding (C1–C7), full native RE where cooked data fails, live Vulkan + headless proof per fix, Plan Consultant gap analysis after approval, plan-reviewer review (default-on).
Next workflow action: write and review .omo/plans/tat2-playtest-ground-truth-fixes.md.
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
