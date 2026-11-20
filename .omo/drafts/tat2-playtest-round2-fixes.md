---
slug: tat2-playtest-round2-fixes
status: drafting
intent: clear
review_required: true
plan_path: .omo/plans/tat2-playtest-round2-fixes.md
plan_sha256: dcc0077eb868920c6c29d35c3f3bc103f07011299dc158daa3ddf9c798a710aa
review_round_id: rr-20261120-01
review_round_limit: 5
round_status: active
pending-action: review .omo/plans/tat2-playtest-round2-fixes.md
review:
  plan_reviewer:
    status: approved
    workspace_root: /home/john/Projects/TAT-2
    runtime_home: null
    target: .omo/plans/tat2-playtest-round2-fixes.md
    round_id: rr-20261120-01
    plan_sha256: dcc0077eb868920c6c29d35c3f3bc103f07011299dc158daa3ddf9c798a710aa
    result: approved-first-round-no-blockers
convergence: [round-1 approval, no new blocker-eligible findings, ledger frozen, digest re-validated live]
    launch_id: null
    session: null
    result: null
approach: Reproduce-then-fix per defect on a verified HEAD build (12 user screenshots + live log as ground truth): Wave 0 pins the build (rebuild from HEAD, re-capture log, re-verify each of the 10 symptoms against current code, extraction audit verdict per missing asset); fix waves follow the dependency order (shared files serialized), every fix value re-derived from UE install/extraction or KF frames with cited sources, per-fix proof on live Vulkan plus headless suite; no new gameplay content, no invented values.
---

# Draft: tat2-playtest-round2-fixes

## Affected user and ideal state
- Player (you) running the Steam-route playtest Den -> Guildhall against official footage; developer verifying parity gates.
<!-- IS-n | property of the ideal state | reason -->
- IS-1 | Telescope enters/exits a zoomed rooftop view on [F] | core Den interaction from the reference route
- IS-2 | Den window shows the exterior (moon, rooftops) through leaded glass | reference sightline KF02/KF06
- IS-3 | Wardrobe UI matches KF03/KF04 layout and content | diegetic UI parity
- IS-4 | Old Manor AND Guildhall minis grow/shrink on selection | HUD/map parity per KF10
- IS-5 | Zipwire crank handle moves on the 3P model after firing | tool parity
- IS-6 | Player climbs stairs; ground meshes sit at authored height, never floating | traversal + exterior parity
- IS-7 | Diamond/tool light is sane, never blinding; no white-bloom lamp orbs | tool light sanity
- IS-8 | Takedown animations play on blackjack/takedown | AI/animation parity
- IS-9 | Guards render with heads and authored materials | character parity
- IS-10 | Every fixed value cites its UE/extraction/KF source; no silent fallbacks | executor trust
<!-- GAP-n | difference between IS-n and today | reason | closed by todo(s) -->
- GAP-1 | Telescope does nothing (entry split + silent map_id guard + local/global camera mix) | breaks IS-1
- GAP-2 | Window shows wall texture + fake godray; vista hidden behind uncut visual wall, wrong side/depth | breaks IS-2
- GAP-3 | Wardrobe structural gaps (portraits, lock badges, thumbnail cards, BACK placement, staging) | breaks IS-3
- GAP-4 | GH mini frozen (likely token missing via silent mesh-null continue) + minis_tween KeyError on stale-or-current build | breaks IS-4
- GAP-5 | Crank is 1P-viewmodel only; 3P has no crank rig, handle, or anim player | breaks IS-5
- GAP-6 | Stairs collide as full-AABB boxes (wall faces); curb lip passes but risers do not | breaks IS-6
- GAP-7 | Blinding blooms from uncapped lamps + diamond cap covers one 1P surface only | breaks IS-7
- GAP-8 | No takedown role/clip/state exists; instant-KO bypasses animation | breaks IS-8
- GAP-9 | Guard heads absent (asset-side or slot-misroute; code only makes navy patches) | breaks IS-9
- GAP-10 | Missing UE Engine BasicShapes + coins + VFX/searchlight meshes; parser-vs-upstream undecided | breaks IS-10

## Components (topology ledger)
- telescope | ponder zoom view works on [F] enter/exit | active | game/src/missions/mission_controller.gd:499-529,815-848,938-957
- den-vista | exterior visible through cut window | active | level_loader.gd:1514-1590 + mission_controller.gd:727-813
- wardrobe | KF03/KF04 parity rebuild | active | game/src/ui/wardrobe_ui.gd + task-6.log
- map-minis | OM+GH grow/shrink + tween meta fix | active | mission_controller.gd:595-702
- crank-3p | 3P crank handle wiring | active | thief_character.gd:989-1035 + animation_library.gd
- traversal | stairs climb + ground height | active | level_loader colliders + thief physics
- tool-light | energy budget across emitters | active | thief_character.gd:2398-2432 + vfx_manager + level_loader PBR
- takedown | roles + clips + victim handoff | active | animation_library.gd + thief_character.gd:1716-1750
- guard-heads | head geometry resolve | active | guard_ai.gd:479-642 + mesh_materials.json
- extraction | asset coverage verdict per missing mesh | active | extracted/filelist.txt + tools/tat-extract (lane st_01a1f963 pending)

## Open assumptions (announced defaults)
- Reproduce-first: every symptom re-verified on a rebuilt HEAD before fixing | build-hash check + fresh capture | evidence before code | yes
- Procedural-replica-in-scope for unrecoverable UE geometry (curbs precedent); extraction repair preferred where parser stage is identified | cheapest correct source per asset | yes
- Live Vulkan proof per fix + headless suite green; numeric FPS stays in perf plan | continuity with prior plan | yes

## Findings (cited - path:lines)
- Screenshots 092827-093058 reviewed: headless guards, blown lamp blooms, floating gate slab, black unlit box, white unshaded pickup, unclimbable stairs.
- User log: Engine BasicShapes + coins missing; minis_tween KeyError at :673 (disk lines 669/673 already defaulted -> build/pipeline suspect; log line numbers drift +40-90 vs disk -> verify build hash).
- Telescope: silent _is_thieves_den guard (:816), Area-only entry vs input-only exit (:521-523 vs :938-957), local/global camera mix (:831-839).
- Vista: collider-only split, visual wall uncut; hand win_pos vs UE WindowBorder; dead spec keys :1535-1538; moon r5@38m vs fov 13.
- Minis: silent mesh-null continue :630-633 can drop GH token; shared loop cannot freeze GH alone; 1.15x delta +0.036 GH vs +0.060 OM.
- Crank 3P: 1P-only by construction; mesh_root hidden :475; no handle node in fallback mesh.
- Diamond: cap covers 1P gem surface 0 only; OrbLight 1.2, fairy 2.2, cable 2.8, flashes 2-3, loader tongs path uncapped.
- Takedowns: zero refs in animation_library; manifest clips under Attack/unused/; instant-KO bypass.
- Heads: 3 empty Preview slots -> navy, not removal; asset-side dump needed.
- Stairs: full-AABB Box colliders + floor_block_on_wall + snap 0.3 step-down only, no step-up.

## Decisions (with rationale)
- Reproduce-first on rebuilt HEAD (build-hash check + fresh capture) before any fix: user's log line numbers drift vs disk and minis_tween KeyError is impossible on disk code, so evidence before code.
- Repair Exporter.cs:99 + :200 filters and re-run meshes + parse_materials for VFX_SkySearchLight_Mesh, Coin_Bronze/Silver/Platinum, Engine BasicShapes: narrow reversible tool fix, assets proven upstream-present.
- Procedural/footage fallback where upstream lacks the asset (den vista MISSING-UPSTREAM; BasicShapes primitives generatable): F5 precedent, nothing to extract.
- Downstream wiring for PRESENT-but-unwired assets (telescope ponder-cam BP, takedown Atk/Vic montages, guard head SKs, coin BP spawn entries): extraction exonerated by audit.
- Takedowns play synced animations (Atk + Vic handoff), not instant-KO: reference parity is the ideal state.
- Test strategy: tests-after + headless suite + live Vulkan proof per fix, agent-executed, zero human QA.

## Scope IN
All 10 reported defects: telescope, den window vista, wardrobe parity, GH minis grow + minis_tween robustness, crank 3P handle, stairs + floating ground, diamond/tool-light energy budget, takedown animation wiring, guard heads, extraction repairs (Exporter.cs) + fallbacks. Wave 0 build-pin + symptom re-verification; per-fix values cited from UE install/extraction/KF frames.

## Scope OUT (Must NOT have)
No new gameplay content or redesigns; no numeric FPS acceptance (perf plan owns it); no invented values where UE/extraction/KF can supply them; no touching files outside each fix's ownership paths; no manual QA steps.

## Open questions
None surviving: every fork resolved to evidence or an announced reversible default. Approval gate is the only outstanding decision.

## Approval gate
status: awaiting-approval
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
