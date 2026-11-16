# Tool Mechanics — Real Extracted Behaviour (MagicSlime / Smoke / Pickpocket)

Replaces the two wrong placeholder mechanics (20 m / 25 s Slithersap light
short-circuit; instant no-travel pickpocket) with the real extracted values.
No value below is invented: every number traces to a cooked-asset source path.
Fields the cooked assets do not contain are listed under Gaps.

## Value table (UE cm → Godot m)

| # | Real field | Cooked value | Godot value | Implemented in |
|---|------------|--------------|-------------|----------------|
| 1 | `BP_MagicSlime_Tool` MaxAmmo | 4 | 4 charges | `thief_character.gd` `SLITHERSAP_CHARGES` / `charges["slithersap"]` |
| 2 | `BP_MagicSlime_ExplodingProjectile` Puddle Radius | 200 cm | 2.0 m | `slip_puddle.gd` `PUDDLE_RADIUS` (collision + decal) |
| 3 | `BP_MagicSlime_ExplodingProjectile` explosion delay | 0 | puddle spawns at aim point immediately | `_use_slithersap` (no timer) |
| 4 | InhibitableActorSearchRadius | 150 cm | 1.5 m | `slip_puddle.gd` `INHIBITOR_RADIUS` → `light_probe.short_circuit_lights(origin, 1.5, 30.0, now)` |
| 5 | Inhibitor Class | `BP_MagicSlime_Inhibitor_C` | inhibitor behaviour folded into the puddle node (no separate actor) | `slip_puddle.gd::setup` |
| 6 | `BP_MagicSlime_Inhibitor` InitialLifeSpan | 30.0 s | 30 s puddle TTL + 30 s light disable | `PUDDLE_LIFETIME` / `INHIBITOR_LIFESPAN` |
| 7 | `BP_MagicSlime_PuddleCluster` Puddle Damage Per Overlap | 5.0 | 5.0, once per body | `_on_body_entered` (+ `_hit_ids`) |
| 8 | PuddleColor | R 0.6035, G 0.0943, B 0.8177 | exact `Color` | `PUDDLE_COLOR` (decal albedo + emission) |
| 9 | PuddleDecalMaterial | `M_MagicSlime_Decal` | flat solid-colour disc — texture NOT recoverable, none faked | decal `CylinderMesh` in `_build()` |
| 10 | PuddleParticleSystem | `NS_GooSplash_Explosion` | one-shot green burst at spawn (`spawn_sap_burst`, retained) | `_use_slithersap` |
| 11 | `GA_MagicSlime_GuardKnockdown` SlipDuration / `GE_MagicSlime_Knockdown` | 10.0 s | `knock_out(10.0)` then `play_slip()` (order matters: `play_slip` keeps an existing KO timer and only adds the slip montage) | `_on_body_entered` |
| 12 | `BP_SmokeBomb_Bomb_Tool` charges | 1 | 1, consumed | `charges["smoke_bomb"]`, `_use_smoke_bomb` |
| 13 | `BP_SmokeBomb_WorldActor` BoxExtent | {250, 250, 200} cm | 5 × 5 × 4 m AABB (`half = (2.5, 2.0, 2.5)`) | `mission_controller.gd` `SMOKE_HALF_EXTENTS` |
| 14 | `BP_SmokeBomb_WorldActor` InitialLifeSpan | 25.0 s | 25 s TTL | `SMOKE_TTL`; `spawn_smoke(pos, ttl := 25.0)` |
| 15 | Smoke blocking | box volume | segment-vs-AABB slab test (replaces sphere proximity) | `is_blocked_by_smoke` / `_segment_hits_aabb` |
| 16 | `BP_Pickpocket_Tool` TargetMaxRange | 2500 cm | 25 m cone selection (nearest-in-cone wins) | `PICKPOCKET_RANGE`, `pickpocket_select_target` |
| 17 | `BP_Pickpocket_Tool` TargetMaxViewAngleDeg | 9.0 | accept iff flat angle from view fwd ≤ 9° | `PICKPOCKET_CONE_DEG` |
| 18 | `GE_Pickpocket_Cooldown` | 0.5 s | 0.5 s gate, ticked in `_physics_process` | `PICKPOCKET_COOLDOWN`, `pickpocket_cooldown` |
| 19 | Pickpocket ammo | no ammo field | infinite: never consumed; display pinned to 999 (HUD has no ∞ glyph — see Gaps) | `PICKPOCKET_INFINITE_DISPLAY` |
| 20 | `BP_PickpocketFairy_FollowActor` FairySpeed | 450 cm/s | 4.5 m/s; flight time = dist / 4.5 | `FAIRY_SPEED`, `fairy_travel_time` |
| 21 | FairyLifeDuration | 20.0 s | travel capped at 20 s | `FAIRY_LIFE` |
| 22 | MaximumFacingAngleToBlock | 30.0° | attempt fails if guard faces player within 30° (re-checked on arrival) | `FAIRY_BLOCK_ANGLE_DEG`, `pickpocket_is_blocked` |
| 23 | Steal | on arrival | fairy flies the orb visual for the computed travel time, then steals the nearest uncollected loot within 10 m of the mark | `_use_pickpocket_fairy` / `_on_fairy_arrived` |

## Source paths (cooked extraction)

- MagicSlime tool / projectile / inhibitor / puddle cluster / knockdown grant
  + effect: `BP_MagicSlime_Tool`, `BP_MagicSlime_ExplodingProjectile`,
  `BP_MagicSlime_Inhibitor` (+ `_C`), `BP_MagicSlime_PuddleCluster`,
  `GA_MagicSlime_GuardKnockdown`, `GE_MagicSlime_Knockdown`,
  `M_MagicSlime_Decal`, `NS_GooSplash_Explosion`.
- Smoke: `BP_SmokeBomb_Bomb_Tool`, `BP_SmokeBomb_WorldActor`.
- Pickpocket: `BP_Pickpocket_Tool`, `GE_Pickpocket_Cooldown`,
  `BP_PickpocketFairy_FollowActor`.

## Simplifications / gaps (nothing invented)

1. **Projectile speed**: the cooked MagicSlime projectile's
   `ProjectileMovementComponent` has no stored `InitialSpeed`, so no lobbed
   flight is simulated — the puddle spawns at the camera aim raycast
   (`_slithersap_aim_point`, 30 m ray, 2.5 m-ahead fallback). The 30 m ray is
   an aim affordance, not an extracted value.
2. **Decal texture**: `M_MagicSlime_Decal`'s texture exists only in the cooked
   graph and is NOT recoverable. The puddle visual is a flat solid-colour disc
   using the exact real `PuddleColor` — no poster/fabricated texture.
3. **Player slippery effect**: skipped. No cooked source for a friction/slide
   value exists; none was invented. Guards get slip + 10 s KO; other bodies
   with `take_damage` take the 5.0 overlap damage once.
4. **Fairy steal radius**: the 10 m loot search around the mark on arrival
   (`FAIRY_STEAL_RADIUS`) is retained scaffolding — no UE source defines what
   the fairy steals. Facing-block is re-checked on arrival with the real 30°.
5. **Infinite charge display**: `BP_Pickpocket_Tool` has no ammo field, so the
   tool is never consumed. `charges["pickpocket_fairy"]` is pinned to 999
   because the HUD (`hud.gd`, untouched by this wave) renders integer counts
   and has no infinity glyph. A proper ∞ display needs a HUD pass.
6. **Smoke visual**: `spawn_smoke_cloud` now emits from the real 5×5×4 m box
   (`EMISSION_SHAPE_BOX`) with a matching `BoxMesh (5, 4, 5)` core that fades
   over the 25 s TTL, and bails out when the parent is outside the tree.

## What needs a visual pass

- Puddle: replace the flat colour disc with a real goo decal/shader once an
  authored (not cooked-ripped) slime texture exists; add the
  `NS_GooSplash_Explosion` fluid burst when a particle look is authored.
- Smoke: the box core is a plain fading volume; needs a proper lingering
  smoke shader to read as a 25 s screen.
- Fairy: the orb visual now flies at the real 4.5 m/s (`spawn_fairy_orb`
  takes a `duration`; default 0.45 s keeps old callers compiling), but the
  fairy itself is still a glowing sphere — needs a real fairy mesh/anim.
- HUD: pickpocket slot should render ∞ instead of 999.

## Verification

- Temporary `game/tests/_tmp_tools_check.gd` (27 asserts, since deleted):
  puddle radius/lifetime from the node; guard KO + 10 s timer after simulated
  overlap; inhibitor disables exactly lights ≤ 1.5 m and restores after 30 s
  (`light_probe` + `tick`); smoke AABB blocks an inside segment, passes
  outside/above segments, 25 s TTL; pickpocket accepts dead-ahead + just
  inside 9°, rejects 45° + just outside 9°, facing-block at 30°, travel time
  9 m → 2 s, no ammo consumed. Result: `SUMMARY: fails=0`, no SCRIPT ERROR.
- `run_tests.gd` untouched; `make test` → `SUMMARY: fails=0`, 0 SCRIPT ERROR
  (exit 0; only headless renderer shutdown warnings).
- Touched files only: `game/src/interact/slip_puddle.gd` (new),
  `game/src/player/thief_character.gd`,
  `game/src/missions/mission_controller.gd`, `game/src/core/vfx_manager.gd`,
  the temp check (deleted), this report.
