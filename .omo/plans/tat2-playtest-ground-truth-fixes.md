# tat2-playtest-ground-truth-fixes - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**Who this is for and what changes for them:** You, playtesting the Den to Guildhall route against official footage. After this, the live run is RD-silent, the Den and Guildhall match the reference, and every fix cites the UE value it came from.

**What you'll get:** 10 fix todos (probe-first RD repair, Den interior, both UI screens, guards, Guildhall geometry, crank animation, map and diamond) plus a committed UE ground-truth backlog, each proven on live Vulkan plus headless suites.

**Why this approach:** Two load-bearing calls. Probe before fixing (code shows no sub-32px viewport, so the #86631 hypothesis must be confirmed live, not assumed). Full native RE with per-function checkpoints (your explicit depth choice, made visible instead of silent).

**What it will NOT do:** No new gameplay content. No re-derivation outside each finding's ownership files. No numeric 60 FPS acceptance here (that stays in the perf plan). No finding deferred: unprovable paths become documented HARD_LIMIT rows.

**Effort:** XL
<!-- Effort is exactly ONE band, never hours/days. Quick = single edit, minutes of agent work; Short = one focused change, a few files; Medium = multi-file feature in one session; Large = several waves, one long session; XL = multi-session or architectural work. A written duration is rewritten to a band. -->
**Risk:** High - Ghidra throughput on cooked Blueprint and graph gaps is unvalidated; the checkpoint plus fallback ladder contains it.
**Decisions to sanity-check:** Tiny-viewport fix with SSAO and SSIL kept; full native RE; per-fix live Vulkan proof (Xvfb defer allowed with the todo left open).

Your next move: plan-reviewer high-accuracy review runs automatically (default-on), then the handoff. Full execution detail follows below.

---

> TL;DR (machine): <1 line - effort, risk, deliverables>

## Scope
### Affected user and ideal state
Player running the Steam build route (Den → Guildhall) against official footage; the developer verifying parity gates. Today the player hits a null-texture RD cascade, floating Den props, a dead window and telescope, wrong ledger/wardrobe UI, broken Guildhall geometry, white malfunctioning guards, a missing crank animation, static map buildings, and a blinding tool light — each measured against the UE install and reference clip as ground truth.

| Row | Statement | Reason |
| --- | --- | --- |
| IS-1 | A full live playtest run prints zero RenderingDevice ERROR lines | RD errors mean broken textures/passes on screen |
| IS-2 | Den props rest on surfaces, the window shows the exterior, the telescope operates | Core Den interactions from the reference route |
| IS-3 | Ledger/Black Market and Wardrobe screens match the reference layout and content | Diegetic UI parity gate family |
| IS-4 | Guildhall geometry is complete and stable: curved curbs, no missing meshes/textures, ground at the right height, no flicker | Exterior parity; numeric 60 FPS acceptance lives in tat2-godot-perf-60fps.md, this plan asserts no-regression + RD-zero |
| IS-5 | Guards render with authored materials and move/animate per reference | AI/animation parity |
| IS-6 | Zipwire crank reload animation plays on crank | Tool parity (T1-43 family) |
| IS-7a | Map buildings behave per reference | HUD/map parity |
| IS-7b | Diamond tool light is sane, never blinding | Tool light sanity |
| IS-8 | Every Ghidra-derived value is reproducible from committed scripts/offsets | Executor and maintainer trust |
| GAP-1 | Live run emits a null-texture RD cascade (slice views, bad mipmap chain, null uniform sets) | User playtest log 2026-11-20 |
| GAP-2 | Den has floating objects, dead window view, dead telescope | User findings 1, 5 |
| GAP-3 | Ledger/Market and Wardrobe UI do not match reference | User findings 2, 3 |
| GAP-4 | Guildhall has block corners, missing meshes, floating ground, flicker | User finding 6 |
| GAP-5 | Guards render white with broken AI/animation | User finding 8 |
| GAP-6 | Crank reload animation missing | User finding 9 |
| GAP-7 | Map buildings static; diamond light blinding | User findings 4, 7 |
| GAP-8 | Ghidra-derived values not reproducible from committed artifacts | Forgotten executor user (Plan Consultant) |
<!-- From the draft ledger: who this touches and how they use the result, then one IS row per property with its reason, then one GAP row per difference with its reason. Every todo below closes a GAP row; ## Success criteria proves every IS row. -->
**Affected user:** <who, and how they use it today and after>

| Row | Statement | Reason |
| --- | --- | --- |
| IS-1 | <what the user does, sees, or never has break> | <why this is the ideal for them> |
| GAP-1 | <how today differs from IS-1> | <why it matters to them> |

### Must have
- Every fix value re-derived from the UE install (`/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`, Paks/Content via tat-extract/CUE4Parse first, `~/.local/bin/ghidra` where cooked data fails) or reference footage, with a cited source per value.
- RD-zero on the live Den→Guildhall run (`grep -c RenderingDevice.*ERROR` == 0) and no FPS regression vs the pre-fix baseline.
- Per-fix proof: live Vulkan Forward+ plus headless suites; GPU-less scenarios pass with no GPU present.
- Ghidra-derived values committed as versioned artifacts with UE path + offset cites; excerpts allowed in wave reports per the user boundary.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No re-derivation of green code: re-derivation limited to each finding's ownership paths (F1–F14 cites); never touch files outside ownership.
- No new gameplay/design content: procedural geometry replicating UE-cooked geometry (curbs, vista) is in scope; invented content is not.
- No deferred or phased-out findings: all 14 findings close; time-boxed probes exit as documented HARD_LIMIT rows, never silent drops.
- No user-manual QA steps; no prose-grep acceptance; no numeric FPS acceptance here (that gate lives in tat2-godot-perf-60fps.md).

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: tests-after (ground-truth values first, then failing checks, then fixes) + Godot headless suites (`make test`, tiered E2E) + live Vulkan Forward+ proof per fix.
- Evidence: .omo/evidence/tat2-playtest-ground-truth-fixes/task-<N>.<ext> (headless logs, live-Vulkan capture logs, committed ground-truth artifacts with UE path + offset cites).
- QA labels: every scenario marked GPU-required (live Vulkan, RTX 4070 host, 720p/1080p, allow_hidpi=false) or GPU-less (must pass with no GPU present; Xvfb correctness only, never FPS claims).

## Execution strategy
### Parallel execution waves
Wave 0 (ground truth + probes, all parallel, read-only except committed artifacts): T1 UE value backlog, T2 live SubViewport/RD-size probe, T3 UNMAPPED time-boxed probes. Wave 1 (fixes against T1 artifacts + T2 probe sites): T4 RD/viewport fix, T5 Den interior, T6 ledger/wardrobe UI, T7 guards, T9 crank — disjoint ownership, all parallel. Wave 2: T8 Guildhall geometry (level_loader landscape, after T5's prop edits to the same file), T10 map/diamond (mission_controller minis after T5's Den hub edits, hud, thief/vfx) — parallel with each other, after Wave 1. C7 artifacts publish before dependent fixes proceed.

### Dependency matrix
| Todo | Writes (files, shared state) | Depends on (reason) | Blocks |
| --- | --- | --- | --- |
| 1 | C7 backlog artifact (.omo/waves/*ground-truth*/backlog.md) | none | 4,5,6,7,8,9,10 (fixes need cited values) |
| 2 | C1 probe script + sizes report | none | 4 (fix only probe-confirmed sites) |
| 3 | UNMAPPED probe reports (car path, guard JSON coverage) | none | 7,8 (fix or HARD_LIMIT) |
| 4 | UI viewport sizes, weather_visuals, mobile_profile env toggles | 1,2 (values + confirmed sites) | none |
| 5 | mission_controller Den hub, level_loader prop/vista spans | 1 (values) | 8,10 (same files) |
| 6 | ledger_ui, wardrobe_ui, art_nouveau_theme | 1 (values) | none |
| 7 | guard_ai, animation_library, civilian compare | 1,3 (values + coverage) | none |
| 8 | level_loader landscape/material spans | 1,3,5 (values, coverage, same file after T5) | none |
| 9 | thief_character crank wiring, hud crank ring | 1 (clip value) | none |
| 10 | mission_controller minis, hud map, thief/vfx diamond | 1,5 (values, same file after T5) | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [x] 1. UE ground-truth backlog for all 14 findings
  What to do / Must NOT do: Build the value-ordered function/asset backlog: for each of F1–F14 record the UE source path (Pak/Content path + object), the cooked-data value where tat-extract/CUE4Parse yields it, and the Ghidra target (binary + function) where it does not, with the fallback ladder cooked → Ghidra → footage-derived per item. MUST NOT paste decompiled bodies beyond short excerpts needed for the fix; record UE path + offset per value. Commit the backlog as .omo/waves/tat2-ground-truth/backlog.md with a machine-checkable index (every value row has source + status found|stalled|blocked).
  Closes: GAP-8 (and enables GAP-1–GAP-7)
  Parallelization: Wave 0 | Blocked by: nothing | Blocks: 4,5,6,7,8,9,10
  References: /home/john/.local/share/Steam/steamapps/common/Thick As Thieves/TAT/Content/, /home/john/.local/share/Steam/steamapps/common/Thick As Thieves/TAT/Paks/, tools/tat-extract/, docs/reference/clip_1795033698901/KEYFRAME_INDEX.md, draft findings F1–F14
  Acceptance criteria: backlog.md exists; every one of the 14 findings has ≥1 value row with a UE path or footage timestamp; `python3 -c` JSON index parse exit 0 with 14 finding keys present.
  QA scenarios: happy — all 14 findings valued from cooked data alone; failure — cooked gap on ≥1 finding with Ghidra target named and stall reported per the checkpoint rule, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-1.md
  Commit: Y | docs(scope): ground-truth backlog for 14 playtest findings
  Recommended task executor category: unspecified-low (multi-source research with a fixed ledger shape; no implementation)
- [x] 2. Probe live SubViewport and RD target sizes on the Den→Guildhall run
  What to do / Must NOT do: Add a temporary probe (deleted after the run, never committed) that logs every live SubViewport.size at runtime plus RD blur-target sizes on the Den→Guildhall route under live Vulkan Forward+; record which viewports fall <32px on an axis or get container-crushed, and whether SSAO/SSIL blur targets go tiny. Covers both the <32px-crush hypothesis and the librarian's tiny-blur-target alternative. MUST NOT change any size, toggle, or material — probe only.
  Closes: GAP-1 (diagnosis half)
  Parallelization: Wave 0 | Blocked by: nothing | Blocks: 4
  References: game/src/ui/main_menu.gd:63-71, game/src/ui/mission_prep_ui.gd:161-164, game/src/ui/wardrobe_ui.gd:247-298, game/src/core/weather_visuals.gd:173/273, game/src/core/mobile_profile.gd (glow gate), https://github.com/godotengine/godot/issues/86631
  Acceptance criteria: sizes report exists listing every live SubViewport size + RD target sizes; the <32px set is named explicitly (possibly empty, which itself kills the crush hypothesis).
  QA scenarios: happy — probe completes the route and the report names each viewport size; failure — route cannot run live, then Xvfb correctness run with the GPU limitation recorded and the todo left open per the GPU-gating decision, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-2.log
  Commit: N (probe deleted after the run; only the sizes report commits)
  Recommended task executor category: deep-low (live-GPU diagnostics across renderer + UI; settled from what the worker reads)
- [x] 3. Time-boxed probes for UNMAPPED paths (car meshes, guard material coverage)
  What to do / Must NOT do: Probe (a) any car/vehicle mesh handler in game/src (grep + load-path trace) and (b) mesh_materials.json/materials.json coverage for the three guard SK GLBs from guard_ai.gd:395. Time-box each at the executor's discretion; on expiry write a HARD_LIMIT row (what was searched, why it ends) consistent with the COMPARISON_SCORECARD precedent. MUST NOT expand into open-ended hunts.
  Closes: GAP-4 (car flicker attribution), GAP-5 (white-guard attribution)
  Parallelization: Wave 0 | Blocked by: nothing | Blocks: 7,8
  References: game/src/ai/guard_ai.gd:200/224/395, game/src/core/level_loader.gd:551/746/759/309, game/data/generated/materials.json, game/data/generated/mesh_materials.json
  Acceptance criteria: probe report exists; car path either located with file:line or closed as HARD_LIMIT; guard GLB coverage stated per SK file (covered/missing).
  QA scenarios: happy — both paths located; failure — time-box expires and HARD_LIMIT rows are written with search evidence, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-3.md
  Commit: Y | docs(scope): UNMAPPED-path probe results
  Recommended task executor category: quick (bounded search with a fixed report shape)
- [x] 4. Fix RD cascade at probe-confirmed sites, keep SSAO/SSIL
  What to do / Must NOT do: Using only T2 probe-confirmed sites, clamp/enlarge sub-32px viewports or fix container crush (never shrink content), keeping ssao/ssil enabled; drop the level_loader resize/mipmap paths from the suspect list per the librarian verdict (keep the null-on-exists-fail guards). MUST NOT disable SSAO/SSIL globally; MUST NOT touch level_loader texture paths beyond the exists-fail guards.
  Closes: GAP-1
  Parallelization: Wave 1 | Blocked by: 1,2 | Blocks: none
  References: T2 sizes report, game/src/ui/ (viewport owners), game/src/core/weather_visuals.gd:173/273, game/src/core/mobile_profile.gd, game/src/core/level_loader.gd:309/746/759, draft F14
  Acceptance criteria: live Den→Guildhall run prints `grep -c 'RenderingDevice.*ERROR'` == 0; no FPS regression vs pre-fix baseline on the same host.
  QA scenarios (GPU-required): happy — RD-zero + no regression; failure — cascade persists, then the executor records remaining ERROR lines and re-opens the blur-target half of T2 instead of guessing, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-4.log
  Commit: Y | fix(render): RD-zero via probe-confirmed viewport sizes
  Recommended task executor category: deep-low (renderer + UI interaction, settled from probe evidence)
- [x] 5. Den interior: grounded props, window vista, working telescope
  What to do / Must NOT do: Snap Den hub props (mission_controller.gd:371 desk/ledger offsets) to level geometry with a ground-placement rule; build the window vista from UE-derived exterior geometry (procedural replica in scope); implement telescope zoom/focus against UE values replacing the ponder-cam placeholder (:678) and placeholder cheese. Re-derive each value from T1 artifacts. MUST NOT touch the Den hub flow outside these three defects.
  Closes: GAP-2
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 8,10
  References: game/src/missions/mission_controller.gd:371/492-511/678/716, game/src/core/level_loader.gd:1489/1498/1511/1574/1661/1447, T1 backlog vista + telescope values
  Acceptance criteria: live Den run shows zero floating props on the reference sightlines, exterior visible through the window, telescope enters/exits a zoomed view; headless `make test` exit 0.
  QA scenarios (GPU-required + GPU-less): happy — live screenshots + suite green; failure — vista mesh missing at runtime, then assert the loader logs the missing UE path instead of a null crash, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-5.log
  Commit: Y | fix(den): grounded props, window vista, telescope
  Recommended task executor category: deep-low (multi-file gameplay + loader reasoning from UE values)
- [x] 6. Ledger/Black Market and Wardrobe UI parity
  What to do / Must NOT do: Rebuild ledger_ui (_build_ui :124, tabs, _refresh_market :376, _refresh_preview :418) and wardrobe_ui (_build_* :152-323, preview worlds :393/440, figure :627, materials :674) layouts against UE-derived layout values + KEYFRAME reference frames; keep the teal theme path (art_nouveau_theme.gd). MUST NOT invent layout; every row/spacing value cites T1 or a KF frame.
  Closes: GAP-3
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: none
  References: game/src/ui/ledger_ui.gd, game/src/ui/wardrobe_ui.gd, game/src/ui/art_nouveau_theme.gd, T1 backlog UI values, docs/reference/clip_1795033698901/clean/KF07..KF10
  Acceptance criteria: side-by-side capture harness asserts layout match per screen (same harness style as w3-e2e-strict --strict); `make test` exit 0.
  QA scenarios: happy — harness passes on both screens; failure — a UE value unrecoverable, then the APPROX gap is documented as a HARD_LIMIT row, not silently approximated, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-6.log
  Commit: Y | fix(ui): ledger and wardrobe reference parity
  Recommended task executor category: visual-engineering (UI layout parity work)
- [x] 7. Guards: authored materials, working AI/animation
  What to do / Must NOT do: Using T3 coverage results, bind the authored guard materials (fix the white-GLB path: missing-texture binds, not the navy fallback), and repair the anim state machine (guard_ai.gd:260/274/280/292/303/317/331/346) against UE-derived clip roles from animation_library.gd:179/243/247. MUST NOT touch thief_character.gd or HUD files.
  Closes: GAP-5
  Parallelization: Wave 1 | Blocked by: 1,3 | Blocks: none
  References: game/src/ai/guard_ai.gd, game/src/core/animation_library.gd, game/src/ai/civilian_npc.gd:152/208 (fallback compare), T1 backlog guard values, T3 coverage report
  Acceptance criteria: live Guildhall run shows textured (non-white) guards patrolling/alerting per reference; headless guard suites + `make test` exit 0.
  QA scenarios: happy — textured guards with state transitions; failure — missing-texture fallback triggers, then assert the navy fallback renders (never white) and the missing bind is logged with its UE path, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-7.log
  Commit: Y | fix(guards): authored materials and animation state machine
  Recommended task executor category: deep-low (AI/animation cross-module reasoning from evidence)
- [x] 8. Guildhall geometry: curbs, missing meshes, ground height, flicker
  What to do / Must NOT do: Generate curved-curb geometry replicating UE-cooked curbs (procedural replica in scope, level_loader landscape/spline spans :1685/2440/2315/2402/1284/2346); fix missing-mesh binds and ground height per T1 values (:551 chain, :746/:759, :2343-2346); eliminate wall flicker via the cull/occluder/glow owners (:404/407/1463/1472/1447, mission_controller glow :113/122-124/280). Runs after T5 (same file). MUST NOT alter gameplay collision semantics beyond restoring authored surfaces.
  Closes: GAP-4
  Parallelization: Wave 2 | Blocked by: 1,3,5 | Blocks: none
  References: game/src/core/level_loader.gd spans above, game/src/missions/mission_controller.gd:113/280, T1 backlog geometry values, T3 car-path verdict
  Acceptance criteria: live Guildhall run shows curbs, complete meshes, correct ground, zero flicker on the reference sightlines; RD-zero holds; `make test` exit 0.
  QA scenarios (GPU-required): happy — geometry complete and stable; failure — a car-mesh path still UNMAPPED, then the HARD_LIMIT row from T3 stands and the rest still ships, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-8.log
  Commit: Y | fix(guildhall): curbs, missing meshes, ground, flicker
  Recommended task executor category: deep-low (loader + renderer interaction at scale)
- [x] 9. Zipwire crank reload animation wiring
  What to do / Must NOT do: Wire animation_library.gd:84 zipwire_crank manifest entry through thief_character.gd:989/1001/1010/1031 and hud.gd:268/282-291 against the UE-derived clip value; handle manifest-missing/zero-bone/arm-flag-off as a logged no-op, never a crash (:998-1000). MUST NOT touch other tool wiring.
  Closes: GAP-6
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: none
  References: game/src/core/animation_library.gd:84/179, game/src/player/thief_character.gd:989-1031, game/src/ui/hud.gd:268/282-291, T1 backlog crank value
  Acceptance criteria: crank interact plays the reload loop on live run; headless T1-43-family suite passes; `make test` exit 0.
  QA scenarios: happy — clip plays on crank; failure — manifest clip absent, then assert logged no-op with the UE clip path recorded, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-9.log
  Commit: Y | fix(zipwire): crank reload animation wiring
  Recommended task executor category: unspecified-low (small cross-file wiring with a fixed contract)
- [x] 10. Map building behavior and diamond tool light
  What to do / Must NOT do: Implement reference map-building grow/shrink (mission_controller.gd:583/624-625 minis scale animation + :632 highlight; hud.gd:374/1402/2711+ tactical points) and sane diamond light levels (thief_character.gd:2393/2402-2404/2430-2432, vfx spawn knobs 0.3-4.5, light_probe.gd:115, mission glow 0.65) from UE-derived values. Runs after T5 (same mission_controller file). MUST NOT touch other HUD or tool systems.
  Closes: GAP-7
  Parallelization: Wave 2 | Blocked by: 1,5 | Blocks: none
  References: files above, T1 backlog map + vistara values
  Acceptance criteria: map buildings animate per reference on the live run; diamond light never exceeds the UE-derived energy cap (asserted in the run log); `make test` exit 0.
  QA scenarios: happy — animated map + sane light; failure — light cap exceeded, then assert the run log line and clamp, Evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-10.log
  Commit: Y | fix(map): building behavior and diamond light levels
  Recommended task executor category: unspecified-high (multi-file feature with real integration surface)

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [x] F1. Plan compliance audit
- [x] F2. Code quality review
- [x] F3. Real manual QA
- [x] F4. Ideal-state fidelity

## Commit strategy

## Success criteria
> One row per IS row. The plan is complete only when every IS row has a delivering todo and a proving QA scenario; F4 checks the delivered behavior against these rows 1:1, and a shortfall becomes new `- [ ] N.` rows, never a note.
| IS | Delivering todo(s) | Proving QA scenario | Evidence |
| --- | --- | --- | --- |
| IS-1 | 2, 4 | RD-zero live run + no-regression FPS | .omo/evidence/tat2-playtest-ground-truth-fixes/task-4.log |
| IS-2 | 5 | Live Den screenshots + suite green | .omo/evidence/tat2-playtest-ground-truth-fixes/task-5.log |
| IS-3 | 6 | Side-by-side harness on both screens | .omo/evidence/tat2-playtest-ground-truth-fixes/task-6.log |
| IS-4 | 8 | Live Guildhall stability + suite green | .omo/evidence/tat2-playtest-ground-truth-fixes/task-8.log |
| IS-5 | 7 | Textured guards + state transitions live | .omo/evidence/tat2-playtest-ground-truth-fixes/task-7.log |
| IS-6 | 9 | Crank plays reload loop live + suite | .omo/evidence/tat2-playtest-ground-truth-fixes/task-9.log |
| IS-7a | 10 | Animated map buildings live | .omo/evidence/tat2-playtest-ground-truth-fixes/task-10.log |
| IS-7b | 10 | Diamond energy cap in run log | .omo/evidence/tat2-playtest-ground-truth-fixes/task-10.log |
| IS-8 | 1 | Backlog JSON index parses, offsets cited | .omo/evidence/tat2-playtest-ground-truth-fixes/task-1.md |
