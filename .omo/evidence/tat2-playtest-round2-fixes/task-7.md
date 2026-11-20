# Task 7 — Guard heads resolve cite ledger

Date (UTC): 2026-11-20. Scope: resolve headless guards from Wave-1 T1
re-extracted SK data in `game/src/ai/guard_ai.gd` bind spans only + this file.
Ground truth read first: Wave 0 ledger
`.omo/evidence/tat2-playtest-round2-fixes/task-0.md` (HEAD `ca7e8ed` +
round-1 worktree; symptom 9 CONFIRMED — `_bind_guard_glb_materials` paints
empty Preview slots 0-2 navy, screenshots show headless guards), F11 backlog
row (`.omo/waves/tat2-ground-truth/backlog.md`, cooked-found), task-3.md
(coverage cite: `SK_Hauntstable__Body` 2/2, `SK_GuardSecurity_01__Body` 2/2,
`SK_GuardEnforcer__Preview` 8 slots / 3 empty upstream / 5 covered).
Reads in scope: guard_ai spans, `game/data/generated/mesh_materials.json`
(slot rows), all guard head/body GLB JSON chunks (surface dump §1), task-3.md.
Writes: ONLY `game/src/ai/guard_ai.gd` bind spans + this file. Takedown and
crank systems untouched. No suite/GPU run (orchestrator owns settle).

## 1. Surface dump (GLB JSON chunk: materials = surface order, mesh prims)

`SK_GuardEnforcer__Preview.glb` (2 839 096 B, 1 mesh, 8 prims, 97-joint skin):
materials in surface order =
`Cornea, Eyes, Overlay, MI_GuardEnforcer_Head_01A, MI_GuardEnforcer_Top,
MI_GuardEnforcer_HelmetEyes, MI_GuardEnforcer_Bottom, MI_GuardEnforcer_BodyA`.
mesh_materials slots for the same UE key =
`"", "", "", MI_GuardEnforcer_Head_01A, MI_GuardEnforcer_Top,
MI_GuardEnforcer_HelmetEyes, MI_GuardEnforcer_Bottom, MI_GuardEnforcer_BodyA`.
Verdict: slots 0-2 are empty upstream and sit exactly on the two eye
surfaces + overlay — NOT on missing head geometry. Prim 3 carries the head
(skin `Head_01A`, authored). The Preview/enforcer guard was never headless;
it had navy/misbound eyes: with named surfaces the old substring match sent
surface 1 (`Eyes`) onto slot 5 (`HelmetEyes`, since `"helmeteyes".find("eyes")`
hits), and surfaces 0/2 (`Cornea`/`Overlay`) fell through to the empty slots
0/2 → navy fallback.

`SK_GuardSecurity_01__Body.glb` (1 281 984 B, 1 mesh, 2 prims, 97 joints):
materials = `MI_GuardSecurity_Bottom, MI_GuardSecurity_Top`. No head prims —
this torso-only SK is one genuine headless source (it is what
`_resolve_guard_glb_path` returned for every security guard).

`SK_GuardSecurity_01_Body.glb` (1 245 968 B, 1 mesh, 5 prims, 97 joints):
materials = `MI_GuardEnforcer_Head_01A, MI_GuardSecurity_TopB,
MI_GuardSecurity_BottomB, MI_GuardEnforcer_BodyA, MI_GuardSecurity_Badge`.
Headed security variant. Joint name+order array IDENTICAL to the headless
`__Body` (97/97, diff 0; `neck_01/head/neck_twist` present) → path swap is
animation-safe. mesh_materials slots cover all 5 (Head_01A, TopB, BottomB,
BodyA, Badge); every slot's `materials.json` entry carries an albedo texture
that exists on disk (§3).

`SK_Hauntstable__Body.glb` (2 prims: `MI_Hauntstable_Top/Bottom`) — torso-only,
second genuine headless source. `SK_Hauntstable__Head.glb` (1 421 212 B,
1 mesh, 3 prims, 97 joints): materials =
`MI_Hauntstable_Top, MI_Hauntstable_Eyes, MI_Hauntstable_Head`, matching its
3 mesh_materials slots. Joint name+order array IDENTICAL to the body (97/97)
→ MeshInstance3D reparent under the body Skeleton3D is skin-safe. All three
slot materials carry albedo textures on disk (§3).

Six `Base/Heads` variant SKs (`Head01__Helm`, `Head01__Helm_Elite`,
`Head02__HeadGear`, `Head02__Helm`, `Head02__NoHelm`, `Head03__NoHelm_Slick`):
6–8 prims each, full 95-joint skeletons, materials = variant helm/hair + eye
set + `MI_GuardEnforcer_Top/HelmetEyes`. Left unbound BY CHOICE (§2): the
Preview already carries head geometry, and no archetype→variant-head mapping
exists in the port (UE modular-part selection is not recovered). Documented
as available variant stock, not a gap.

## 2. Chosen fix (remap + one sub-skeleton attach; no HARD_LIMIT)

- Enforcer/Preview: eye-rescue remap. Exact-name rescue
  (`GUARD_EYE_RESCUE`: Cornea→`MI_Eye_Cornea`, Eyes→`MI_Eye_Base_Brown`,
  Overlay→`MI_Eye_Overlay`) fires BEFORE the substring match, fixing the
  `Eyes`→`HelmetEyes` misroute; unnamed-surface imports fall back to
  `GUARD_PREVIEW_EYE_BY_SLOT` index rescue for slots 0-2. Slots 3-7 keep the
  existing authored chain.
- Security: path swap in `_resolve_guard_glb_path` (all 3 returns) from the
  headless `SK_GuardSecurity_01__Body.glb` torso to the headed
  `SK_GuardSecurity_01_Body.glb` (skeleton-identical). No extra instance.
- Hauntstable: head sub-skeleton attach. `_attach_guard_head` (called from
  `_build_visuals`) instances `SK_Hauntstable__Head.glb` via `GUARD_HEAD_GLB`,
  rebinds its 3 surfaces through the shared `_bind_guard_mi_surfaces`, then
  reparents the MeshInstance3Ds under the body Skeleton3D (global transform
  preserved, `mi.skeleton` pointed at the new parent) and frees the spare
  instance. The full-skeleton sub-instance alternative (two Skeleton3Ds, one
  unanimated) was rejected: the reparent keeps one animated skeleton.
- Refactor: slot lookup extracted to `_guard_slots_for_ue_key`; surface loop
  extracted to `_bind_guard_mi_surfaces` shared by body and head binds.
  Single-GLB assumption removed only where it was wrong (security path,
  hauntstable attach); enforcer still single-GLB by design.
- Navy fallback retained ONLY for genuinely missing binds (unknown surface,
  empty non-Preview slot, unresolvable material) with the UE path logged —
  never white, per the standing rule.

## 3. Per-slot binds (all authored, all verified)

| Archetype | Surface | Slot / rescue | materials.json texs.albedo | On disk |
|---|---|---|---|---|
| Preview 0 | Cornea | `MI_Eye_Cornea` | `.../EyeLibrary/T_Eye_Cornea_DA.png` | OK |
| Preview 1 | Eyes | `MI_Eye_Base_Brown` | `.../EyeLibrary/T_Eye_Base_Dark_D.png` | OK |
| Preview 2 | Overlay | `MI_Eye_Overlay` | `.../EyeLibrary/T_Eye_Overlay_DA.png` | OK |
| Preview 3 | Head skin | `MI_GuardEnforcer_Head_01A` | `.../GuardEnforcer/Base/Textures/T_GuardEnforcer_Head_D.png` | OK |
| Preview 4-7 | Top/HelmetEyes/Bottom/BodyA | slots 4-7 (unchanged) | pre-existing task-3 covers | OK |
| Security 0 | Head skin | `MI_GuardEnforcer_Head_01A` | as Preview 3 | OK |
| Security 1/2 | TopB/BottomB | `MI_GuardSecurity_TopB/BottomB` | `.../Base/Textures/T_GuardEnforcer_Top_D.png` / `T_GuardEnforcer_Bottom_D.png` | OK |
| Security 3/4 | BodyA/Badge | `MI_GuardEnforcer_BodyA` / `MI_GuardSecurity_Badge` | `.../T_GuardEnforcer_Body_D.png` / `T_GuardEnforcer_Top_D.png` | OK |
| Haunt body 0/1 | Top/Bottom | slots 0-1 (unchanged) | `T_Hair_D.png` / `T_ThiefNisha_Bottom_D.png` | OK |
| Haunt head 0/1/2 | Top/Eyes/Head | `MI_Hauntstable_Top/Eyes/Head` | `T_Hair_D.png` / `T_ThiefNisha_Eyes_D.png` / head `T_ThiefNisha_Head_D.png` + `T_Hauntstable_Head_N.png` | OK |

No HARD_LIMIT: every archetype resolves to authored materials in code. (The
six variant heads are intentionally unused stock — §1, not missing data.)

## 4. Verification (file-level + targeted check, no suite/GPU run)

- Re-read edited spans from disk: coverage/`GUARD_NAVY` const block +
  `GUARD_EYE_RESCUE` + `GUARD_PREVIEW_EYE_BY_SLOT` + `GUARD_HEAD_GLB`,
  `_build_visuals` attach call, `_resolve_guard_glb_path` security returns,
  `_guard_slots_for_ue_key` + `_bind_guard_mi_surfaces` +
  `_bind_guard_glb_materials` + `_attach_guard_head` — all spans carry
  inline task-7 cites. Changed ranges: const block ~182-214, `_build_visuals`
  +2 lines, `_resolve_guard_glb_path` 3 returns, bind chain refactor + attach.
- Targeted parse check on the new code (probe file with the 3 consts + 4 funcs
  verbatim + stubs, since removed): `flatpak run org.godotengine.Godot
  --headless --check-only --script` → RC 0, no errors.
- Full-file `--check-only` reports exactly 1 error, `Identifier not found:
  GameState` at `_ready` line 228 — pre-existing (untouched by this diff;
  `git diff` shows no `_ready`/autoload hunk; same error class task-3 recorded
  as the pre-existing autoload-reference pattern on `wardrobe_ui.gd`). New
  code introduces zero new diagnostics.
- Non-navy confirm: every head/eye surface in §3 maps to a `materials.json`
  entry with an albedo texture verified present on disk; code paths to
  `_guard_navy_fallback` remain only for the genuinely-missing cases.
- Scope: `git status` delta from this turn = `game/src/ai/guard_ai.gd` + this
  ledger (other modified/untracked entries pre-date this turn: round-1
  worktree + Wave-1 extraction outputs). Takedown/crank untouched.
- Live proof (head visibility in Den/Guildhall) belongs to the orchestrator's
  settle run — explicitly not run here per task.
