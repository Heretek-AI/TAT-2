# Task 3 — Time-boxed probes: car/vehicle handler + guard SK material coverage

Date: 2026-11-20. Scope: read-only probes of
`game/src/ai/guard_ai.gd`, `game/src/core/level_loader.gd`,
`game/data/generated/materials.json`, `game/data/generated/mesh_materials.json`.
No source files edited.

## (a) Car/vehicle mesh handler verdict

| Verdict | Detail |
|---|---|
| HARD_LIMIT — no dedicated car/vehicle mesh handler exists in scope | Grepped `game/src/core/level_loader.gd` + `game/src/ai/guard_ai.gd` for `car\|vehicle` (case-insensitive): all hits are false positives (`carried_item`/`_carried_node`/`carries_lantern` in guard_ai.gd; `carpet` in CLUTTER_TOKENS level_loader.gd:164/795, `carr`/`carr.append` locals, `carry` in comments). Second sweep for `SM_Vehicle\|vehicle\|sedan\|truck\|auto[^m]\|wheel\|chassis\|SM_Car\|BP_Vehicle` in both files: zero matches (grep exit 1). Probe ends here per time-box: no handler function, branch, or token list to cite as file:line; vehicles (if any) fall through the generic `_get_mesh_and_shape` / `_bind_glb_materials` mesh path in level_loader.gd. No open-ended repo-wide hunt undertaken. |

## (b) Guard material coverage per SK GLB (from guard_ai.gd:395 `_resolve_guard_glb_path`)

SK set (guard_ai.gd:395-410): `SK_Hauntstable__Body`, `SK_GuardSecurity_01__Body`, `SK_GuardEnforcer__Preview`.

Key mapping: mesh_materials.json keys are UE paths without extension
(e.g. `/Game/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body`);
materials.json keys are UE material paths (exact + case-insensitive match).

### mesh_materials.json (2045 keys) — per SK file

| SK GLB | Verdict |
|---|---|
| SK_Hauntstable__Body (`.../Hauntstable/SK_Hauntstable__Body`) | COVERED — 2 slots: `MI_Hauntstable_Top`, `MI_Hauntstable_Bottom` |
| SK_GuardSecurity_01__Body (`.../Security/SK_GuardSecurity_01__Body`) | COVERED — 2 slots: `MI_GuardSecurity_Bottom`, `MI_GuardSecurity_Top` |
| SK_GuardEnforcer__Preview (`.../Base/SK_GuardEnforcer__Preview`) | COVERED (partial) — 8 slots: 3 empty-string slots (no authored material) + 5 populated |

### materials.json (1571 keys) — per slot material

| SK GLB | Slot material | materials.json |
|---|---|---|
| SK_Hauntstable__Body | `/Game/Art/Character/Hauntstable/MI_Hauntstable_Top` | COVERED |
| SK_Hauntstable__Body | `/Game/Art/Character/Hauntstable/MI_Hauntstable_Bottom` | COVERED |
| SK_GuardSecurity_01__Body | `/Game/Art/Character/GuardEnforcer/PrivateSecurity/MI_GuardSecurity_Bottom` | COVERED |
| SK_GuardSecurity_01__Body | `/Game/Art/Character/GuardEnforcer/PrivateSecurity/MI_GuardSecurity_Top` | COVERED |
| SK_GuardEnforcer__Preview | (slots 0-2: empty string) | MISSING — no authored material in mesh_materials.json slot; nothing to resolve in materials.json |
| SK_GuardEnforcer__Preview | `/Game/Art/Character/GuardEnforcer/Head/MI_GuardEnforcer_Head_01A` | COVERED |
| SK_GuardEnforcer__Preview | `/Game/Art/Character/GuardEnforcer/Base/MI_GuardEnforcer_Top` | COVERED |
| SK_GuardEnforcer__Preview | `/Game/Art/Character/GuardEnforcer/Base/MI_GuardEnforcer_HelmetEyes` | COVERED |
| SK_GuardEnforcer__Preview | `/Game/Art/Character/GuardEnforcer/Base/MI_GuardEnforcer_Bottom` | COVERED |
| SK_GuardEnforcer__Preview | `/Game/Art/Character/GuardEnforcer/Base/MI_GuardEnforcer_BodyA` | COVERED |

Summary: no HARD_LIMIT — all 3 SK keys present in mesh_materials.json; all 9
non-empty slot materials present in materials.json. Only gap is the 3 empty
slots on SK_GuardEnforcer__Preview (upstream data gap, not a materials.json miss).
