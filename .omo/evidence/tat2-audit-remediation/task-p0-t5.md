# TAT-2 Audit Remediation — Task P0-T5: footstep `get_rid()` crash

Date (UTC): 2026-11-20. Task: T5 — `player.get_rid()` on a `Node3D` throws on
every Guildhall/OldManor footstep.

## Ground truth reproduced (before change)

- `AUDIT.md §T5`: `game/src/core/audio_manager.gd:469-484` — `_is_indoor()`
  builds `Array[RID] = [player.get_rid()]`, but `Node3D` has no `get_rid()`
  (only `CollisionObject3D`). Path runs per footstep via `_footstep_clip` →
  `_scene_surface` → `_is_indoor` outside the Den (which early-returns
  `"wood"` before the raycast). First non-Den step throws.
- `audit-core.md P0-1 (:469-484)`: same span quoted verbatim:
  `var player: Node3D = tree.get_first_node_in_group("player") as Node3D` +
  `var excluded: Array[RID] = [player.get_rid()]`.
- File pre-edit span confirmed: `_is_indoor()` at `audio_manager.gd:469-484`
  with `var excluded: Array[RID] = [player.get_rid()]`.

## Chosen mechanism

Capability guard + `CollisionObject3D` exclusion (both authorized options
combined, minimal form):

```gdscript
var excluded: Array[RID] = []
if player is CollisionObject3D:
    var body: CollisionObject3D = player as CollisionObject3D
    excluded.append_array(body.get_collision_exceptions())
    excluded.append(body.get_rid())
q.exclude = excluded
```

- `player is CollisionObject3D` is the capability check: a plain-`Node3D`
  player skips the RID lookup entirely, so the footstep path can never throw.
- When the player IS a physics body, exclusion is strictly better than
  before: own RID plus `get_collision_exceptions()` (e.g. held/carried
  bodies) are excluded from the ceiling probe, so the indoor/outdoor ray
  cannot self-hit.
- No collision-layer check was needed; the `is` guard covers every `Node3D`
  shape and keeps the ray mask unchanged.

## Scope discipline

- Touched only `_is_indoor()` in `game/src/core/audio_manager.gd`.
- Voice/bed logic untouched; footstep callers (`_footstep_clip`,
  `_scene_surface`) unchanged.

## Verify

- Re-read edited `_is_indoor()` span post-edit: guard present, no bare
  `player.get_rid()` remains on the footstep path.
- Headless-load check: no `godot` binary on PATH (`godot`/`godot4`/`godot-headless` all absent), so a headless script load was not possible; file-level verification stands (godot binary check run 2026-11-20).
- `grep get_rid audio_manager.gd` post-edit: single hit at line 486, `excluded.append(body.get_rid())`, inside the `if player is CollisionObject3D` guard — no bare `player.get_rid()` remains.
- This file exists at `.omo/evidence/tat2-audit-remediation/task-p0-t5.md`.
