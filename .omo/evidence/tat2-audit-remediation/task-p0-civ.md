# P0-8 Evidence — Civilian continuous wandering (task-p0-civ)

## Loop rule
Reproduce every cited span before changing it. No product-code change without a quoted ground-truth span.

## Ground truth reproduced (before edit)
- `AUDIT.md` T9-adjacent P0 backlog: "Gameplay P0-8 (civilians wander once, `civilian_npc.gd:186-196`; `_pick_new_target` only in `_ready`)".
- `audit-gameplay.md` §3.7 P0-8: `_pick_new_target` called only in `_ready` (`civilian_npc.gd:59-60`); physics loop (`:186-196`) arrival re-arms `_idle_ttl` onto the same reached `_target`; no second destination ever picked; target is `wander_center ± 6 m` with no navmesh/raycast validation and no stuck timeout (`:228-233`); `move_and_slide` with `collision_mask = 1` slides along walls but never repicks.
- File as found: `_ready()` called `_pick_new_target()` once; `_physics_process` arrival branch set `_idle_ttl = randf_range(IDLE_MIN_S, IDLE_MAX_S)` with no repick; `_pick_new_target()` assigned a raw random offset with no validation.

## Edit (only `game/src/ai/civilian_npc.gd`)
- Constants: `STUCK_TIMEOUT_S = 8.0`, `MAX_TARGET_ATTEMPTS = 8`.
- State: `_stuck_ttl` reset to `STUCK_TIMEOUT_S` on every `_pick_new_target()`.
- Repick triggers (3):
  1. Arrival: arrival branch sets idle AND calls `_pick_new_target()` for the next leg.
  2. Idle expiry: when `_idle_ttl` crosses `<= 0.0`, calls `_pick_new_target()`.
  3. Stuck timeout: walking branch decrements `_stuck_ttl`; on expiry sets a short idle (`0.5-1.5 s`) and repicks.
- Validation `_is_target_valid()`: horizontal world-ray (mask 1) from `wander_center + UP` to candidate rejects through-wall targets; vertical drop-ray rejects no-floor targets; navmesh snap via `NavigationServer3D.map_get_closest_point` rejects candidates > 1.0 m off-mesh when a navigation map exists. Fail-open before inside-tree / null world / null space so spawn never blocks. Up to `MAX_TARGET_ATTEMPTS` tries, fallback `_target = wander_center`.

## Verify
- Re-read edited spans: constants block, `_physics_process` idle/arrival/stuck branches, `_pick_new_target` + `_is_target_valid`.
- Repick triggers confirmed: arrival repick, idle-expiry repick, stuck-timeout repick each call `_pick_new_target()`; `_stuck_ttl` reset on every pick.
- Targeted check: string scan confirms `_pick_new_target()` appears in `_ready`, idle-expiry, arrival, and stuck branches; `_is_target_valid` contains `intersect_ray` × 2 and `map_get_closest_point`.
- `task-p0-civ.md` exists at `.omo/evidence/tat2-audit-remediation/task-p0-civ.md`.
- Full suite NOT run per instruction (orchestrator runs `make test` at settle).
