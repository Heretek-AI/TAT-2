# tat2-playtest-round2-fixes - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**Who this is for and what changes for them:** You, playtesting the Den to Guildhall route. After this, the telescope zooms, the window shows the night city, the wardrobe matches the footage, both map tokens grow, the crank handle turns on the model, stairs climb, lights stop blinding you, takedowns animate, and guards have heads — with every value traced to the game files it came from.

**What you'll get:** 10 fix todos in dependency order (build-pin + extraction audit first, then Den exterior, wardrobe, crank, minis, stairs, heads, light budget, takedowns), each proven on live Vulkan plus the headless suite.

**Why this approach:** Two load-bearing calls. Reproduce on a verified HEAD first (your log disagrees with current code, so nothing is fixed on stale evidence). Repair the extractor where it provably drops meshes, wire what it provably extracted, and replicate only what upstream never had.

**What it will NOT do:** No new gameplay or redesigns. No invented values. No FPS numbers (that gate lives in the perf plan). No finding left silent: unfixable paths become documented HARD_LIMIT rows.

**Effort:** XL
<!-- Effort is exactly ONE band, never hours/days. Quick = single edit, minutes of agent work; Short = one focused change, a few files; Medium = multi-file feature in one session; Large = several waves, one long session; XL = multi-session or architectural work. A written duration is rewritten to a band. -->
**Risk:** High - Ghidra-free UE re-derivation breadth plus live-GPU proof per fix; the Wave 0 pin plus per-todo sentinels contain it.
**Decisions to sanity-check:** Reproduce-first on rebuilt HEAD; exporter filter repair vs procedural fallback split; takedowns play synced animations (no instant-KO).

Your next move: <fill - e.g. approve, or run a high-accuracy review>. Full execution detail follows below.

---

> TL;DR (machine): XL effort, high risk (UE re-derivation breadth + per-fix live proof); 10 fix todos closing 10 gap rows with cited values.

## Scope
### Affected user and ideal state
<!-- From the draft ledger: who this touches and how they use the result, then one IS row per property with its reason, then one GAP row per difference with its reason. Every todo below closes a GAP row; ## Success criteria proves every IS row. -->
**Affected user:** You, the player, running the Steam Den → Guildhall route against official footage; after this plan every listed defect matches the reference. The headless suite + capture rig is a second consumer: it must stay green and gain one sentinel per fix.

| Row | Statement | Reason |
| --- | --- | --- |
| IS-1 | Telescope enters/exits a zoomed rooftop view on [F] | Core Den interaction from the reference route |
| IS-2 | Den window shows the exterior (moon, rooftops) through leaded glass | Reference sightlines KF02/KF06 |
| IS-3 | Wardrobe UI matches KF03/KF04 layout and content | Diegetic UI parity |
| IS-4 | Old Manor AND Guildhall minis grow/shrink on selection; no meta KeyError | HUD/map parity per KF10 |
| IS-5 | Zipwire crank handle moves on the 3P model after firing | Tool parity |
| IS-6 | Player climbs stairs; ground meshes sit at authored height, never floating | Traversal + exterior parity |
| IS-7 | Diamond/tool light is sane, never blinding; no white-bloom lamp orbs | Tool light sanity |
| IS-8 | Takedown animations play on blackjack/takedown | AI/animation parity |
| IS-9 | Guards render with heads and authored materials | Character parity |
| IS-10 | Headless suite stays green; every fix has a capture artifact at a known path | Executor + automation trust |
| GAP-1 | Telescope does nothing (entry split + silent map_id guard + local/global camera mix) | Breaks IS-1 |
| GAP-2 | Window shows wall texture + fake godray; vista hidden, wrong side/depth | Breaks IS-2 |
| GAP-3 | Wardrobe structural gaps (portraits, lock badges, thumbnail cards, BACK placement, staging) | Breaks IS-3 |
| GAP-4 | GH mini frozen (token likely dropped by silent mesh-null continue); minis_tween KeyError on stale-or-current build | Breaks IS-4 |
| GAP-5 | Crank is 1P-viewmodel-only; 3P has no crank rig, handle, or anim player | Breaks IS-5 |
| GAP-6 | Stairs collide as full-AABB boxes (wall faces); curb lip passes but risers do not; some ground meshes float | Breaks IS-6 |
| GAP-7 | Blinding blooms from uncapped lamps; diamond 0.65 cap covers one 1P surface only | Breaks IS-7 |
| GAP-8 | No takedown role/clip/state exists; manifest clips quarantined under Attack/unused/; instant-KO bypasses animation | Breaks IS-8 |
| GAP-9 | Guards headless (asset-side or slot-misroute; code only makes navy patches) | Breaks IS-9 |
| GAP-10 | VFX searchlight mesh, coin meshes, Engine BasicShapes missing from generated data (parser filters); den vista has no upstream asset | Breaks IS-10 |

### Must have
- Wave 0 pins the build first: record commit hash, rebuild from HEAD, re-capture a live log, re-verify all 10 symptoms against current code, and record per-asset verdicts PRESENT-UPSTREAM / MISSING-UPSTREAM / PRESENT-BUT-UNWIRED before any fix.
- Every fix value re-derived from the UE install (`/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`), `extracted/` tree, or KF frames in `docs/reference/clip_1795033698901/`, with cited source per value; unsourced values labeled `procedural-replica` explicitly.
- Per-fix proof: headless suite green plus live Vulkan Forward+ capture; RD-zero holds on the final tree.
- No silent fallbacks: every mesh/material/camera miss logs its UE path and trips a headless assertion.
### Must NOT have (guardrails, anti-slop, scope boundaries)
- No new gameplay content or redesigns: wardrobe work stays within KF03/KF04 layout and content; vista replica follows F5 precedent.
- No numeric FPS acceptance here (perf plan owns it); per-fix gate is no-measured-regression on the named scene plus suite green.
- No invented values where UE/extraction/KF can supply them; no files touched outside each todo's ownership paths.
- No user-manual QA steps; no prose-grep acceptance.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: tests-after (ground-truth values first, then failing checks, then fixes) + `make test` headless suite + live Vulkan Forward+ proof per fix
- Evidence: .omo/evidence/tat2-playtest-round2-fixes/task-<N>.<ext> (headless logs, live-Vulkan capture logs, committed value tables with UE path + line or KF frame cites)

## Execution strategy
### Parallel execution waves
Wave 0 (pin + audit, evidence only): T0 build-pin, symptom re-verification, per-asset verdicts. Wave 1 (disjoint writes): T1 extraction repair (tools + generated data), T2 Den exterior telescope+vista (mission_controller + level_loader), T3 wardrobe (wardrobe_ui), T4 crank 3P (thief_character crank spans + animation_library 3P entry). Wave 2: T5 minis (mission_controller minis spans, after T2), T6 stairs+ground (level_loader colliders + thief physics, after T2), T7 guard heads (guard_ai + mesh binds). Wave 3: T8 diamond/tool-light budget (thief_character diamond spans, after T4/T6). Wave 4: T9 takedowns (animation_library + guard_ai + thief blackjack spans, after T4/T6/T7/T8). T10 vista fallback is folded into T2 (MISSING-UPSTREAM verdict gates replica, not a separate todo).
### Dependency matrix
| Todo | Writes (files, shared state) | Depends on (reason) | Blocks |
| --- | --- | --- | --- |
| 0 | evidence only (no product edits) | none | 1-9 (all fixes need pinned verdicts) |
| 1 | tools/tat-extract/Exporter.cs, extracted/ + game/data/generated + game/assets deltas | 0 (verdicts say what to repair) | 5,7 (heads + minis need re-extracted binds) |
| 2 | mission_controller telescope+vista spans, level_loader vista split spans | 0 (verdicts + values) | 5,6 (same files serialize) |
| 3 | wardrobe_ui.gd | 0 (values) | none |
| 4 | thief_character crank spans, animation_library 3P crank entry | 0 (values) | 8,9 (same files serialize) |
| 5 | mission_controller minis spans | 0,2 (values + same file after T2) | 8,9 (same file serializes) |
| 6 | level_loader collider spans, thief_character physics spans | 0,2 (values + same level_loader after T2) | 8,9 (same files serialize) |
| 7 | guard_ai bind spans, head mesh binds | 0,1 (values + re-extracted heads) | 9 (same guard_ai serializes) |
| 8 | thief_character diamond/light spans | 0,4,6 (values + same file after T4/T6) | 9 (same file serializes) |
| 9 | animation_library takedown roles, guard_ai victim handoff, thief blackjack spans | 0,4,5,7,8 (values + same files after T4-T8) | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [x] 0. Pin build, re-verify symptoms, record extraction verdicts
  What to do / Must NOT do: Record `git rev-parse HEAD`, rebuild from HEAD, re-capture a live Den→Guildhall log, re-verify all 10 symptoms against current code (telescope, vista, wardrobe, GH mini + minis_tween, crank 3P, stairs, diamond/lamps, takedowns, heads, missing meshes), and record per-asset verdicts PRESENT-UPSTREAM / MISSING-UPSTREAM / PRESENT-BUT-UNWIRED for VFX_SkySearchLight_Mesh, Coin_Bronze/Silver/Platinum, Engine BasicShapes, guard heads, takedown clips, telescope, window border, vista actors. MUST NOT edit product code; diagnosis only.
  Closes: GAP-10 (verdict half; enables GAP-1–GAP-9)
  Parallelization: Wave 0 | Blocked by: nothing | Blocks: 1,2,3,4,5,6,7,8,9
  References: /home/john/Projects/TAT-2/extracted/filelist.txt, extracted/json, game/data/generated/mesh_materials.json + anims_manifest.json, tools/tat-extract/Exporter.cs:30-35 (Packages TAT/ gate) + Meshes() SM_/SK_ allowlist, docs/reference/clip_1795033698901/KEYFRAME_INDEX.md, prior evidence .omo/evidence/tat2-playtest-ground-truth-fixes/task-*.log
  Acceptance criteria: task-0 report lists all 10 symptoms CONFIRMED/STALE with build hash; `grep -c minis_tween` on fresh log decides stale-vs-current; `python3 -c` parses the verdict JSON with one row per asset.
  QA scenarios: happy — all 10 symptoms reproduce on HEAD; failure — a symptom does not reproduce, then it is marked STALE with the fixing commit cited and its fix todo narrowed, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-0.md
  Commit: N (evidence only) | docs(scope): build-pin and verdict ledger
  Recommended task executor category: unspecified-low (multi-source verification ledger; no implementation)
- [x] 1. Repair extraction filters + re-extract dropped meshes
  What to do / Must NOT do: Widen the `Meshes()` name allowlist to queue VFX_*, Coin_*, and Engine/BasicShapes packages (or an explicit allowlist), keep the TAT/ gate for everything else; re-run meshes + parse_materials; audit with before/after filelist diff proving Coin_Bronze/Silver/Platinum GLBs, VFX_SkySearchLight_Mesh GLB, and Engine BasicShapes GLBs now exist with mesh_materials binds. MUST NOT change conversion settings or touch unrelated exporters; revert is `git checkout` on tools/ + generated deltas.
  Closes: GAP-10 (repair half)
  Parallelization: Wave 1 | Blocked by: 0 | Blocks: 5,7
  References: tools/tat-extract/Exporter.cs:30-35 + Meshes() allowlist, tools/parse_tables.py, tools/parse_loot.py:11,106-220, game/data/generated/mesh_materials.json
  Acceptance criteria: `ls game/assets/ue/Content/Art/Gameplay/Loot/LootMinor/Coins/ | grep -c Coin_` returns 3 and `find game/assets/ue/Content/Engine -name '*.glb' | wc -l` is nonzero; `make test` exit 0.
  QA scenarios: happy — all dropped meshes export with binds; failure — a mesh still missing, then the audit names the exact filter line that still excludes it, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-1.md
  Commit: Y | fix(extract): queue VFX_, Coin_ and Engine BasicShapes meshes
  Recommended task executor category: unspecified-low (small tool change + rerun + audit)
- [x] 2. Den exterior: working telescope + cut window vista
  What to do / Must NOT do: Fix toggle entry (F dispatches to Area OR lookat path, never both-neither; map_id guard logs instead of silent return), fix ponder-cam to global-space eye + DenWindowVista focus, derive win_pos/beam_target/outward from WindowBorder UE coords (not hand values), cut the visual wall with the collider split (or place vista inside the room), bind frame + frosted glass, scale moon/rooftops to KF02/KF05/KF06 framing, hook wind swell audio. MUST NOT touch minis, Den hub flow, or other mission_controller systems outside telescope/vista spans.
  Closes: GAP-1, GAP-2
  Parallelization: Wave 1 | Blocked by: 0 | Blocks: 5,6
  References: game/src/missions/mission_controller.gd:57-63,185-187,371-420,499-529,702-848,938-957, game/src/core/level_loader.gd:1514-1590,1609-1616, game/src/core/vfx_manager.gd:328-365, game/data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json, backlog F5/F6, task-5.log, KF02/KF05/KF06
  Acceptance criteria: live Den run shows exterior through the window and [F] enters/exits a zoomed view; headless Den spawn asserts DenWindowVista exists with focus meta; `make test` exit 0.
  QA scenarios: happy — vista visible + telescope zooms; failure — vista mesh missing at runtime, then the loader logs the UE path and the test fails loudly (never silent), Evidence .omo/evidence/tat2-playtest-round2-fixes/task-2.log
  Commit: Y | fix(den): telescope ponder + cut window vista
  Recommended task executor category: deep-low (camera math + wall-cut reasoning from UE values)
- [x] 3. Wardrobe UI parity rebuild (KF03/KF04)
  What to do / Must NOT do: Rebuild wardrobe layout against KF03/KF04: portraits + LOCKED states in the switcher, lock badges + slot-3 expanded row in loadout, thumbnail portrait cards in the right rail, BACK placement, UE-derived staging numbers; keep hard-coded fallbacks only where task-6 HARD_LIMIT rows name them, and close each row with a cited value or an explicit standing HARD_LIMIT. MUST NOT invent art or paths; MUST NOT touch ledger/market code.
  Closes: GAP-3
  Parallelization: Wave 1 | Blocked by: 0 | Blocks: none
  References: game/src/ui/wardrobe_ui.gd:152-439,619-668, game/data/generated/tables/Character/Player/DT_CharacterOutfitsMetadata.json (54 rows), docs/reference/clip_1795033698901/clean/KF03_00m07s_wardrobe_loadout.jpg + KF04, .omo/evidence/tat2-playtest-ground-truth-fixes/task-6.log (23 cites + 10 HARD_LIMITs)
  Acceptance criteria: side-by-side capture harness asserts per-row cites (same harness style as prior UI work); `make test` exit 0.
  QA scenarios: happy — harness passes; failure — a value unrecoverable, then a standing HARD_LIMIT row with search evidence (never silent), Evidence .omo/evidence/tat2-playtest-round2-fixes/task-3.log
  Commit: Y | fix(ui): wardrobe KF03/KF04 parity
  Recommended task executor category: visual-engineering (UI layout parity work)
- [x] 4. Crank handle moves on the 3P model
  What to do / Must NOT do: Wire a 3P crank path: resolve the firing thief rig (not the hidden 1P viewmodel), bind AN_Zipwire_Crank_Montage (4.65 s 3P form, distinct from the 1P reload loop at animation_library.gd:84) to the crank-handle bone/track, drive it while _is_cranking holds; add the handle sub-node if the fallback mesh lacks one. Keep the 1P reload loop untouched. MUST NOT touch other tool wiring or guard spans.
  Closes: GAP-5
  Parallelization: Wave 1 | Blocked by: 0 | Blocks: 8,9
  References: game/src/player/thief_character.gd:443-475,989-1035,2180-2265,2567-2598, game/src/core/animation_library.gd:84, extracted/json/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage.json, task-9.log, KF S15 (01:49.50-01:58.50 crank ascent)
  Acceptance criteria: live crank hold visibly moves the model handle (capture frames before/after); headless assert: crank state implies 3P crank track playing; `make test` exit 0.
  QA scenarios: happy — handle cranks on model; failure — rig lacks a crank bone, then the plan records the procedural-handle fallback explicitly, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-4.log
  Commit: Y | fix(zipwire): 3P crank handle wiring
  Recommended task executor category: deep-low (rig + anim wiring across viewmodel/3P split)
- [x] 5. Guildhall mini grows + minis_tween robustness
  What to do / Must NOT do: Log + assert (never silent-continue) when a mini mesh is missing so the GH token can never vanish quietly; make highlight updates safe on first call from any order (defaults on every meta read); verify GH token present with UE-relative base in _den_tokens. Runs after T2 (same file). MUST NOT touch telescope/vista spans.
  Closes: GAP-4
  Parallelization: Wave 2 | Blocked by: 0,2 | Blocks: 8,9
  References: game/src/missions/mission_controller.gd:595-702,883-900, game/data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json, extracted/json/Art/UI/Map/SM_MapBuilding_*.json (45.56192/27.39531), task-0 verdict on GH mesh presence
  Acceptance criteria: live Den map shows OM and GH both tweening on selection; headless assert: both tokens present with UE-ratio bases; `make test` exit 0 (34d asserts UE-relative bases).
  QA scenarios: happy — both minis grow/shrink + emission toggles; failure — GH mesh still missing upstream, then sentinel logged + test fails loudly with the UE path, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-5.log
  Commit: Y | fix(map): GH mini token + tween robustness
  Recommended task executor category: unspecified-low (state machine + robustness with fixed contract)
- [x] 6. Stairs climb + ground meshes seated
  What to do / Must NOT do: Give stairs per-tread or trimesh collision (no full-AABB wall faces) and/or step-up assist within the 0.3 m snap philosophy; seat floating ground meshes at authored height (verify against UE heightmap decode). Runs after T2 (same level_loader). MUST NOT change collision semantics beyond restoring authored walkability.
  Closes: GAP-6
  Parallelization: Wave 2 | Blocked by: 0,2 | Blocks: 8,9
  References: game/src/core/level_loader.gd:814-825 (Box bucket), :1508, :1783+ (curb 0.15 precedent), game/src/player/thief_character.gd:36-41,432-441,898-921, user screenshots 092837 (stairs) + 092850 (floating slab)
  Acceptance criteria: live player climbs the 092837 stair run; headless step-up probe: 0.18 m riser climbs, 0.6 m wall blocks; `make test` exit 0.
  QA scenarios: happy — stairs + gait; failure — a stair run still blocks, then the probe names the run with file:line, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-6.log
  Commit: Y | fix(traversal): stair collision + step-up
  Recommended task executor category: deep-low (physics + collider interaction)
- [x] 7. Guard heads resolve
  What to do / Must NOT do: Dump the Preview GLB surfaces to place slots 0-2 (empty upstream) vs head geometry; either bind the six extracted SK_Guard_Head* SKs as head sub-skeletons or remap the misrouted Head_01A slot onto the true head surface; keep navy fallback only for genuinely missing binds. Verify against T1 re-extracted heads.
  Closes: GAP-9
  Parallelization: Wave 2 | Blocked by: 0,1 | Blocks: 9
  References: game/src/ai/guard_ai.gd:237-250,455-642, game/data/generated/mesh_materials.json:7972-7981 + :8043-8101, game/assets/ue/Content/.../Heads/ (6 GLBs), task-3.md + task-7.log
  Acceptance criteria: live guards render heads with authored materials; headless assert: guard head surface bound non-navy; `make test` exit 0.
  QA scenarios: happy — headed textured guards; failure — head geometry truly absent from GLB, then the surface dump + UE path are logged and the gap becomes a standing HARD_LIMIT, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-7.log
  Commit: Y | fix(guards): head geometry binds
  Recommended task executor category: deep-low (bind chain + asset-side reasoning)
- [x] 8. Tool-light energy budget (diamond + lamps + flashes)
  What to do / Must NOT do: Cap the whole emitter rig that blinds the screenshots (lamp lights, OrbLight 1.2, fairy 2.2, cable 2.8, flashes 2-3, loader tongs/3P emissive path) at UE-derived levels with the diamond cap pattern (const + assert + run-log line); keep the 0.65 gem cap. Runs after T4/T6 (same thief_character). MUST NOT touch crank or takedown spans.
  Closes: GAP-7
  Parallelization: Wave 3 | Blocked by: 0,4,6 | Blocks: 9
  References: game/src/player/thief_character.gd:1065,2398-2432,2434+, game/src/core/vfx_manager.gd:53-60,154-158,621-625, game/src/core/level_loader.gd (PBR emissive 2.2/8.0 path), task-10.log, screenshots 092900/093055/093058 (bloom orbs)
  Acceptance criteria: live night scenes show no clipped-white bloom orbs; headless assert: every capped emitter <= cap; `make test` exit 0.
  QA scenarios: happy — sane lights; failure — an emitter uncappable from UE data, then cap + HARD_LIMIT row with the UE path, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-8.log
  Commit: Y | fix(light): tool and lamp energy budget
  Recommended task executor category: unspecified-low (multi-file budget with fixed pattern)
- [x] 9. Takedown animations wired end to end
  What to do / Must NOT do: Add takedown roles/clips to the animation tables referencing the extracted StealthTakedown/TakedownOverhead/BlackJack sets (out of Attack/unused/ quarantine), bind Atk to the thief blackjack path replacing instant-KO with an animation handoff, bind Vic to the guard victim with state entry, keep camera punch + counter. Runs after T4/T5/T7/T8 (same files). MUST NOT invent clips; every clip cites anims_manifest + GLB path.
  Closes: GAP-8
  Parallelization: Wave 4 | Blocked by: 0,4,5,7,8 | Blocks: none
  References: game/src/core/animation_library.gd (role tables :179-293), game/src/player/thief_character.gd:1716-1750, game/src/ai/guard_ai.gd:323-401, game/data/generated/anims_manifest.json:881-965 + StealthTakedown lines ~4700, task-7.log
  Acceptance criteria: live takedown plays Atk + Vic synced with prompt; headless assert: takedown role resolves to a manifest clip with GLB on disk; `make test` exit 0.
  QA scenarios: happy — synced takedown; failure — a clip missing GLB, then sentinel + UE path logged and the role falls back loudly, Evidence .omo/evidence/tat2-playtest-round2-fixes/task-9.log
  Commit: Y | fix(takedown): role + clip + victim handoff
  Recommended task executor category: unspecified-high (anim system feature with real integration surface)

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [x] F1. Plan compliance audit
- [x] F2. Code quality review
- [x] F3. Real manual QA
- [x] F4. Ideal-state fidelity

## Commit strategy
One commit per todo (type(scope): summary on each row); Wave 0 produces no product commit (evidence only). Exporter repair commits tools/ and regenerated data together so re-extraction is reviewable via filelist diff. Revert path per todo is `git checkout` of its listed files.

## Success criteria
> One row per IS row. The plan is complete only when every IS row has a delivering todo and a proving QA scenario; F4 checks the delivered behavior against these rows 1:1, and a shortfall becomes new `- [ ] N.` rows, never a note.
| IS | Delivering todo(s) | Proving QA scenario | Evidence |
| --- | --- | --- | --- |
| IS-1 | 2 | Telescope enters/exits zoomed view live | .omo/evidence/tat2-playtest-round2-fixes/task-2.log |
| IS-2 | 2 | Exterior visible through window live + headless DenWindowVista assert | .omo/evidence/tat2-playtest-round2-fixes/task-2.log |
| IS-3 | 3 | Side-by-side capture harness on wardrobe screens | .omo/evidence/tat2-playtest-round2-fixes/task-3.log |
| IS-4 | 5 | Both minis tween live + headless UE-ratio assert (34d) | .omo/evidence/tat2-playtest-round2-fixes/task-5.log |
| IS-5 | 4 | Crank handle moves on model (before/after capture) | .omo/evidence/tat2-playtest-round2-fixes/task-4.log |
| IS-6 | 6 | Stair run climbs live + step-up probe (0.18 climbs / 0.6 blocks) | .omo/evidence/tat2-playtest-round2-fixes/task-6.log |
| IS-7 | 8 | No clipped-white blooms live + emitter cap asserts | .omo/evidence/tat2-playtest-round2-fixes/task-8.log |
| IS-8 | 9 | Synced Atk+Vic takedown live + role-resolves assert | .omo/evidence/tat2-playtest-round2-fixes/task-9.log |
| IS-9 | 7 | Headed textured guards live + head-bind assert | .omo/evidence/tat2-playtest-round2-fixes/task-7.log |
| IS-10 | 0,1 | Suite green + per-fix capture artifacts at known paths | .omo/evidence/tat2-playtest-round2-fixes/task-0.md |
