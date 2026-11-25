# W9-P4 — guard FSM fact sheet (`game/src/ai/guard_ai.gd`)

Read-only investigation of `rem/w9-p4` at `f1bf058`. No Godot run, no producer
run, no file touched except this one. All line numbers are the branch HEAD
(2573 lines in `guard_ai.gd`).

---

## 1. FSM definition

### 1.1 The enum and the state fields

`enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }`
— `guard_ai.gd:5`. Numeric values are 0..5 in that order; tests and the KO probe
compare against the literals (`probe_blackjack_race.gd:168,172` uses `5`;
`run_tests.gd:8474` uses `0`).

State-carrying fields (all plain `var`, no setters — a `set("state", n)` bypasses
`_set_state` entirely, which is what several tests do):

| field | line | type | notes |
|---|---|---|---|
| `state` | 225 | `int` | alertness |
| `health` | 226 | `float` | set to `_guard_max_hp()` at 386 |
| `detection` | 227 | `float` | 0..100 meter |
| `ko_timer` | 228 | `float` | only decremented in the KO branch |
| `wp_index` | 229 | `int` | patrol index |
| `state_timer` | 269 | `float` | per-state dwell; reset to 0 by `_set_state:1258` |
| `_seconds_in_state` | 270 | `float` | +delta at 1449; 0 on `_set_state` |
| `_seconds_since_visible` | 271 | `float` | 0 on any visible frame (1464); +delta otherwise (1494) |
| `attack_cooldown` | 272 | `float` | decayed at 1447 |
| `investigate_pos` | 268 | `Vector3` | target of SUSPICIOUS/ALERTED/SEARCH |
| `_search_goal` / `_search_goal_timer` | 278-279 | | SEARCH fan-out |
| `search_scan_phase` | 276 | `float` | SEARCH yaw/scan phase |
| `_patrol_wait_left` / `_patrol_dir` | 266-267 | `float` / `int` | dwell + PingPong direction |
| `_regen_blackout` | 282 | `float` | gates `_tick_regen` |
| `_ally_scan_timer` | 283 | `float` | gates `_update_ally_wakeup` |
| `_body_scan_timer` | 296 | `float` | gates `_scan_downed_guards` |
| `bodies_seen` | 297 | `int` | last scan result |
| `_revive_target` / `_revive_progress` | 280-281 | | ally revive hold |

### 1.2 `_physics_process` — exact evaluation order (`1435-1522`)

1. **`1436-1437` hard gate.** `if GameState.state != "playing": return`. The
   whole FSM is inert in `menu`/`hub`/`paused`/`victory`/`failed`
   (`game_state.gd:78`; default `"menu"`). Every live-guard test sets
   `GameState.state = "playing"` first (`probe_blackjack_race.gd:41`,
   `run_tests.gd:8251`).
2. **`1438-1444` KO branch, returns.** `ko_timer -= delta`; at `<= 0` →
   `_recover_from_ko()` (1441), else `_update_guard_anim(delta)` (1443). Nothing
   else in the tick runs while KO: no regen, no detection, no patrol, no ally
   scan, no body scan.
3. `1446` `_tick_regen(delta)` — see 1.5.
4. `1447` `attack_cooldown = maxf(0, attack_cooldown - delta)`.
5. `1448` `_regen_blackout = maxf(0, _regen_blackout - delta)`.
6. `1449` `_seconds_in_state += delta` (before any transition this frame).
7. `1450-1451` `get_tree().get_nodes_in_group("player")` → `_nearest_player`
   (`1528-1539`, nearest by 3-D distance; `null` when none).
8. `1452` `_update_disguise_viewcone(delta, player)` — see 1.6.
9. `1453` `sees_player = _can_see_player(player)` (`1817-1885`).
10. **`1455-1492` visible branch** (sees_player true):
    - `1464` `_seconds_since_visible = 0.0`
    - `1465` `dist_m` = 3-D distance to the player
    - `1466-1470` `rate = detection_gain_per_second(dist_m, is_crouching,
      is_sprinting, |Δy|)` (see 1.3)
    - `1471-1474` `is_inf(rate)` → `detection = 100.0`, else
      `detection = minf(100.0, detection + rate * delta)`
    - `1475` `investigate_pos = player.global_position`
    - `1481` `sight_rank = ALERTNESS_RANK.get(state, 99)` — SEARCH ranks **2**,
      between SUSPICIOUS and ALERTED (`165-171`)
    - `1482-1485` `detection >= 100` → `_enter_combat()`; sets
      `GameState.ever_spotted = ever_chased = true`
    - `1486-1489` `detection >= 45 && sight_rank < 3` → `_enter_alerted()`,
      then `state_timer = 6.0`; `GameState.ever_spotted = true`
    - `1490-1492` `detection >= 15 && sight_rank < 1` → `_set_state(SUSPICIOUS)`
      (only reachable from NEUTRAL), `state_timer = 5.0`
    - no de-escalation exists on the visible path; COMBAT cannot be demoted
      while the player is seen.
11. **`1493-1515` not-visible branch:**
    - `1494` `_seconds_since_visible += delta`
    - `1498` `detection = decay_step_detection(state, detection,
      _seconds_in_state, _seconds_since_visible, delta)` (see 1.4)
    - `1499-1501` `state == COMBAT && detection <= 35.0` → ALERTED,
      `state_timer = 6.0`
    - `1502-1506` `state == ALERTED` → `state_timer -= delta`; at `<= 0` →
      SEARCH, `state_timer = 6.0`. Note: **no detection term** — 6 s without
      sight always demotes ALERTED.
    - `1507-1511` `state == SUSPICIOUS && detection <= 0.0` → SEARCH,
      `state_timer = investigation_search_seconds` (4.0 default at 242; 8.0
      after a long stim, 1969; 8.0 for GuardDowned, 1748)
    - `1512-1515` `state == SEARCH` → `state_timer -= delta`; at `<= 0` →
      NEUTRAL
12. `1517` `_update_indicator()` (`2254-2270`, Label3D text/modulate)
13. `1518` `_emit_alert_state_if_needed(false)` (`2309-2314`; emits the
    `alert_state_changed` signal when |Δ suspicion| >= 0.05)
14. `1519` `_update_ally_wakeup(delta)` — **can change state after the branch**
    (see 1.7)
15. `1520` `_scan_downed_guards(delta)` — **can raise detection/state after the
    branch** (see 1.8); the promotion test for this frame has already run, so a
    body noticed here takes effect on the movement code below and on the next
    frame's ramp
16. `1521` `_move_ai(delta, player)` (`1542-1605`)
17. `1522` `_update_guard_anim(delta)` (`883-907`)

Hearing is **not** in this list: `_ready:425` connects
`NoiseBus.noise_record_emitted` to `_on_noise_record` (`1905-1906`), and
`NoiseBus.emit_noise` emits synchronously (`noise_bus.gd:127-131`). A guard's
state can therefore change inside *another* guard's tick, inside
`take_knockout`, or inside `interact` — in particular `_enter_alerted:1283`
emits a 14 m `guard_alert`, whose listeners run inline before `_set_state`
returns.

### 1.3 Detection gain

- `_ramp_for_state()` `1297-1306`: NEUTRAL→`DETECTION_RAMPS[0]`, SUSPICIOUS and
  SEARCH→`[1]`, ALERTED→`[2]`, everything else (COMBAT, KNOCKED_OUT)→`[3]`.
  Rows `119-124`: all four have `critical_time 0.0, critical_range 2.0,
  crouch_mult 0.75`; ramp 0/1 `agnostic 0.4, crouch_min 2.75`; ramp 2
  `agnostic 0.2, crouch_min 2.75`; ramp 3 `agnostic 0.2, crouch_min 2.0`.
- `get_detection_rate(dist_m, crouching)` `1313-1321`: `time_s = agnostic*dist +
  critical_time`; returns `INF` when `dist <= critical_range` or `time_s <= 0`;
  else `100/time_s`, times `crouch_mult` when crouching and
  `dist >= crouch_min`.
- `detection_gain_per_second(dist_m, crouching, sprinting, height_diff_m)`
  `1330-1336`: rate × `sprint_ramp_multiplier` (x8 when sprinting, 1395-1396) ×
  `height_difference_strength_multiplier` — **only while `state == NEUTRAL`**
  (1333-1335); 1.0 below 3.0 m, 0.0 at/above (`1401-1404`).
- Light is not in this function: light gates acquisition *range* in
  `_can_see_player` (`1844-1845`) only.

### 1.4 Detection decay

- `detection_decay_seconds(alertness)` `1340-1341`:
  `DECAY_SECONDS_BY_STATE` (`149-154`) NEUTRAL 1.0, SUSPICIOUS 5.0, ALERTED 10.0,
  COMBAT 10.0; anything else (SEARCH, KO) → `DECAY_BASE_SECONDS 7.0` (143).
- `detection_decay_per_second` `1346-1350` = `100/seconds`.
- `decayed_detection` `1355-1356`.
- `decay_step_detection(state, current, seconds_in_state, seconds_since_visible,
  delta)` `1365-1370`: **SEARCH bypasses both gates** and decays
  unconditionally at 100/7 ≈ 14.29 pts/s; every other state returns `current`
  until `_seconds_in_state >= 6.0` **and** `_seconds_since_visible >= 4.0`
  (141-142).
- `clamped_detection_for_transition(old, new, current)` `1378-1384`: no clamp
  unless `new_rank < old_rank`; ceiling from `DETECTION_ENTRY_CEILING`
  (`178-183`: NEUTRAL 15, SUSPICIOUS 15, ALERTED 45, COMBAT 100). **SEARCH and
  KNOCKED_OUT are absent** → `minf(current, current)` = unchanged.

### 1.5 `_tick_regen` (`1235-1242`)

Returns immediately while `state == COMBAT` or `KNOCKED_OUT` (1236-1237), and
while `_regen_blackout > 0` (1238-1239). Otherwise
`health = minf(cap, health + _guard_regen_rate()*delta)` (1240-1242). Rates come
from `GameData.eval_curve("CT_AIStats", ...)` at 1210-1215 (fallbacks 30 HP /
15 HP/s). `_regen_blackout = 4.0` on any non-lethal hit (`take_knockout:2030`).

### 1.6 `_update_disguise_viewcone` (`2535-2567`)

Runs before sight. Returns when player null / state KO / delta<=0 (2536), player
astral (2538), not disguised (2540), or the player lacks
`apply_guard_viewcone_disguise_decay` (2542). Then: eye = guard +1.5 m (2544),
player eye +1.3 m (2545), distance gate 10.0 m
(`VIEWCONE_DISGUISE_RANGE_M`, 30), half-cone 65.0 deg
(`VIEWCONE_DISGUISE_HALF_DEG`, 31), smoke gate via `level_ctrl` (2556-2558), ray
mask `1|2|4|8` excluding both RIDs (2564), and on a clear ray calls
`player.apply_guard_viewcone_disguise_decay(delta, true)` (2567). It never
writes the guard.

### 1.7 `_update_ally_wakeup` (`2131-2192`)

- `2138-2141` if state is COMBAT or KNOCKED_OUT: clear `_revive_target` /
  `_revive_progress`, return. NEUTRAL/SUSPICIOUS/SEARCH/ALERTED may revive.
- `2142-2145` 0.4 s scan throttle (`_ally_scan_timer`).
- `2146-2158` nearest KO'd guard in group `guards` within 6.0 m (`best_d = 6.0`).
- `2160-2162` found: `investigate_pos = other_position`.
- `2163-2182` if `best_d <= 1.8`: `_revive_target` bookkeeping, then
  `_revive_progress += 0.4` per scan; at `>= revive_hold_s()` (5.0 s,
  `1220-1227`) → clear target, `best_ko.set("ko_timer", 0.0)`,
  `wake_up_from_ko()`, `_set_state(SEARCH)` (2176), `state_timer = 6.0`,
  `detection = maxf(detection, 40.0)`, 10 m `guard_alert` noise + VO.
  13 scans at 0.4 s ≈ 5.2 s of real time.
- `2183-2185` found but farther than 1.8 m and state NEUTRAL →
  `_set_state(SUSPICIOUS)`, `state_timer = 5.0`.
- `2186-2192` stale-target cleanup at > 2.0 m.
- Note `_recover_from_ko:2110` also clamps detection to 40.

### 1.8 `_scan_downed_guards` (`1701-1731`) and the reaction

- `1702-1703` not in tree → return.
- `1704-1707` `_body_scan_timer -= delta`; on expiry reset to
  `BODY_SCAN_INTERVAL_S 0.5` (102).
- `1709-1712` `sight_row()`, `SightModel.eye_position`, forward,
  `effective_vision_range(true)` = `lose_sight_range` (×0.1 while KO, but KO
  never reaches here — 1438 returns first).
- `1715-1730` for each node in group `guard_bodies` (103): skip self/invalid,
  skip beyond range, `SightModel.frustum_admits(..., sight_frustum_enabled)`,
  then a layer-1 ray excluding both RIDs; every admitted body calls
  `_on_downed_guard_noticed` (1730). `bodies_seen = seen` (1731).
- `_on_downed_guard_noticed` `1737-1754`: shared event id
  `0x40000000 + body_instance_id % 0x3FFFFFFF` (1740); `ReactionRoles.claim_hearing(
  event_id, "vision.guard_downed", "Heavy", ...)` (1741) → Heavy row = 2
  investigators, 0.5 s grace. Investigator (1742-1748): `investigate_pos = body`,
  `detection = maxf(detection, 45)`, `state_timer = 6.0`, `_enter_alerted()`,
  `last_investigation_kind = long`, `investigation_search_seconds = 8.0`.
  Standby (1749-1754): `detection = maxf(detection, 15)`, and NEUTRAL →
  SUSPICIOUS + `state_timer = 5.0`.

### 1.9 `_set_state` (`1250-1267`) and every call site

Body: early return if unchanged (1251-1252); `state = new_state` (1254);
`_seconds_in_state = 0.0` (1255); `state_timer = 0.0` (1258); clears
`_revive_target/_revive_progress` when the new state is COMBAT or KNOCKED_OUT
(1262-1264); `detection = clamped_detection_for_transition(...)` (1265);
`_apply_authored_escalation(new_state)` (1266, writes `sight_range`,
`lose_sight_range`, `fov_deg` — 501-518); `_emit_alert_state_if_needed(true)`
(1267).

13 call sites:

| # | line | caller | trigger | timer written after |
|---|---|---|---|---|
| 1 | 1282 (`_enter_alerted`) | 1487 sight, 1746 GuardDowned, 1981 `guard_alert`, 2042 damage, 2508 pickpocket-spotted | detection ≥ 45 (rank < 3) / investigator role / shout / surviving hit / alert-victim theft | 6.0 **stays** at 1488 and 2509 (written after the call); 6.0 is **zeroed** at 1745, 1980, 2041 (written *before* the call, and `_set_state:1258` resets it) |
| 2 | 1291 (`_enter_combat`) | 1483 sight | detection ≥ 100 | none (0) |
| 3 | 1491 | tick, visible | detection ≥ 15 and rank < 1 (NEUTRAL only) | 5.0 at 1492 |
| 4 | 1500 | tick, blind | COMBAT and detection ≤ 35 | 6.0 at 1501 |
| 5 | 1505 | tick, blind | ALERTED and `state_timer <= 0` | 6.0 at 1506 |
| 6 | 1508 | tick, blind | SUSPICIOUS and detection ≤ 0 | `investigation_search_seconds` (1511) |
| 7 | 1515 | tick, blind | SEARCH and `state_timer <= 0` | none (0) |
| 8 | 1753 | `_on_downed_guard_noticed` | standby witness in NEUTRAL | 5.0 at 1754 |
| 9 | 2011 | `_hear` | investigator role, state NEUTRAL | 5.0 at 2012 |
| 10 | 2055 | `knock_out` | not already KO | `ko_timer` 2059-2062, state_timer 0 |
| 11 | 2113 | `_recover_from_ko` | `ko_timer <= 0` | 6.0 at 2114 |
| 12 | 2176 | `_update_ally_wakeup` | revive completed | 6.0 at 2177, detection ≥ 40 at 2178 |
| 13 | 2184 | `_update_ally_wakeup` | KO ally 1.8..6.0 m, NEUTRAL | 5.0 at 2185 |

KO entry/exit: `knock_out` (2052-2089) sets `ko_timer` from
`GameData.eval_curve("CT_AIStats","GuardKnockoutDuration", x, 180.0)` (2062),
`alert_indicator.text = "ZZZ"` (2063), hides the lantern light, adds group
`guard_bodies` (2058), starts the tip-over tween/anim. `_recover_from_ko`
(2099-2128): full health, removes `guard_bodies`, `detection = minf(detection,
40)`, `investigate_pos` fallback, `_set_state(SEARCH)`, `state_timer = 6.0`.
`_seconds_since_visible` is **not** reset by either.

`state_timer` is a real timer only in ALERTED and SEARCH. In SUSPICIOUS it is
written (5.0) and never read; in COMBAT it is 0 and unused.

**Timer-write order matters, and three call sites get it wrong.** `_set_state`
always zeroes `state_timer` before the caller's next statement. So:

- `_enter_alerted(); state_timer = 6.0` → 6.0 (sight 1487-1488, pickpocket
  2507-2509).
- `state_timer = 6.0; _enter_alerted()` → **0.0**, unless the guard was already
  ALERTED (then `_enter_alerted:1280-1281` early-returns and 6.0 survives).
  Affected: GuardDowned investigator 1745-1746 (only survives from ALERTED),
  `guard_alert` shout 1980-1981 and `take_knockout` 2041-2042 (both guarded on
  `state != ALERTED and != COMBAT`, so the transition always happens and the
  value is always 0).
- Consequence: a guard raised to ALERTED by a shout or by surviving damage
  enters with `state_timer == 0.0` and drops to SEARCH on its **first blind
  frame** (1502-1505), whereas a guard raised by sight or by a pickpocket
  attempt gets the full 6.0 s.

---

## 2. Patrol

### 2.1 Data path (producer → loader → mission → guard)

1. **Producer** `tools/parse_tables.py:2518-2547`: per `APatrolPath` actor,
   `{"actor", "class", "loop_type": props.LoopType, "points": [...]}`; each point
   `{"pos": [m, m, m] Godot axes, "wait": WaitSeconds, "wait_deviation",
   "facing": HasFacing, "yaw": Facing.Yaw (UE degrees), "type"}`. Requires at
   least one point (2539).
2. **Loader** `level_loader.gd:2647-2650` (accumulator key) and `3532-3537`
   (merged verbatim; no re-transform).
3. **Mission** `mission_controller.gd:729` passes
   `ue_level_data["patrol_paths"]` into `_spawn_guards` (`3738`).
   `_authored_patrol_index_for` (`3803-3822`) picks the nearest path whose
   nearest point is within `PATROL_MATCH_RADIUS_M = 30.0` (`:85`), preferring an
   unused index; `_assign_authored_patrol` (`3861-3883`) is the writer.
4. **Guard fields**: `patrol_points: Array[Vector3]` `196`,
   `patrol_waits: Array[float]` `200`, `patrol_yaws: Array[float]` `201`,
   `patrol_facing: Array[bool]` `202`, `patrol_loop_mode: String` `205`,
   `patrol_speed: float` `217`, `wp_index: int` `229`,
   `_patrol_wait_left: float` `266`, `_patrol_dir: int` `267`.
   Writers: `_assign_authored_patrol:3879-3883` (`set()`), the synthetic square
   `mission_controller.gd:3786-3791` (direct assignment of 4 points, no
   waits/yaws/facings, loop_mode stays `""`), `_ready:426-427` (3-point fallback
   when `patrol_points` is empty: own position, +6X, +6X+6Z), `_advance_patrol_index`
   (`wp_index`, `_patrol_dir`), `_patrol_service_waypoint` (`_patrol_wait_left`).
5. **Speed scaling**: `_ready:387` `_speed_scale = lerpf(0.85, 1.2, (diff_x-1)*0.5)`
   and `388` `patrol_speed *= _speed_scale`; `suspicious_speed` 389;
   `chase_speed` 394. `GameState.difficulty_curve_x()` is `float(difficulty)`
   (`game_state.gd:809-810`) with `NOVICE=1, THIEF=2, MASTER_THIEF=3` (`:19`).
   At NOVICE `_speed_scale = 0.85` → `patrol_speed = 1.275 m/s`; THIEF 1.025 →
   1.5375; MASTER_THIEF 1.20 → 1.80. A roster-bound spawn overwrites
   `patrol_speed = GuardRoster.patrol_speed_m_s(roster()) * _speed_scale` (408).

### 2.2 `_patrol_service_waypoint(delta) -> bool` (`1762-1778`), line by line

1. `1763-1764` empty `patrol_points` → `false` (no dwell).
2. `1765-1770` **dwelling**: `_patrol_wait_left = maxf(0, left - delta)`;
   `_apply_patrol_yaw(delta, wp_index)`; when it reaches 0,
   `_advance_patrol_index()`; **always returns `true`** on this frame (the frame
   the timer expires is still a stand-still frame).
3. `1771` arrival test: `global_position.distance_to(patrol_points[wp_index]) < 1.0`
   — a full 3-D distance, not planar.
4. `1772` `wait_s = _patrol_wait_for(wp_index)` (`1782-1785`: 0.0 when the index
   is outside `patrol_waits`, else `maxf(0, patrol_waits[index])`).
5. `1773` `_apply_patrol_yaw(delta, wp_index)`.
6. `1774-1776` `wait_s > 0` → `_patrol_wait_left = wait_s` (set to the **full**
   authored value, not decremented this frame) and return `true`.
7. `1777` `_advance_patrol_index()`; `1778` return `false` (walk to the new
   index on the same frame).

`_apply_patrol_yaw(delta, index)` (`1791-1797`): returns unless
`index < patrol_yaws.size()` **and** `index < patrol_facing.size()` **and**
`patrol_facing[index]`; target = `deg_to_rad(-(patrol_yaws[index] + 90.0))`;
`rotation.y = lerp_angle(rotation.y, target, clampf(delta*4.0, 0, 1))` — an
eased turn at 4·delta per frame (≈0.067 at 60 Hz, 0.25 s time constant), never a
snap.

`_advance_patrol_index()` (`1802-1814`): `count <= 1` → `wp_index = 0`, return
(no direction change). PingPong iff `patrol_loop_mode.to_lower().find("pingpong") >= 0`
(1807): if `wp_index + _patrol_dir >= count` → `_patrol_dir = -1`; elif
`< 0` → `_patrol_dir = 1`; then `wp_index = clampi(wp_index + _patrol_dir, 0, count-1)`
— the endpoints are visited once, never twice. Any other loop string → 
`wp_index = (wp_index + 1) % count` (1814).

### 2.3 Per-tick observable effects in NEUTRAL (`_move_ai` `1542-1605`)

`1544` `spd = patrol_speed`; `1551-1555`:
- `_patrol_service_waypoint` true → `target = global_position`, `spd = 0.0`.
- false → `target = patrol_points[wp_index]`.

Then `1582` `flat = (target - pos)` with `y = 0`; `1583` the movement gate is
`flat.length() > 0.25 and spd > 0.0`:
- gate true: `1587` `_nav.step_towards(target)`; `1588` fallback `flat.normalized()`
  (no baked navmesh → straight line + one process-wide warning,
  `nav_steering.gd:174-181`); `1589-1590` `velocity.x/z = dir * spd`;
  `1598` `look_at(global_position + dir, UP)` → **rotation.y snaps** to
  `atan2(-dir.x, -dir.z)`.
- gate false: `1600-1601` `velocity.x = velocity.z = 0`, no rotation write.
- `1603-1604` gravity if airborne; `1605` `move_and_slide()` → position
  advances ≈ `spd*delta` along `dir`, `rotation.y` unchanged except the two
  writes above.

Ordering consequence: `_apply_patrol_yaw` runs *inside* the service call, i.e.
before `_move_ai`'s `look_at`. On an arrival frame with no wait the index has
already advanced, so the `look_at` toward the **next** waypoint overwrites the
authored yaw set for the point just reached. The authored yaw survives only on
dwell frames (service returns true → no `look_at`).

### 2.4 Edge cases (exact behaviour)

| case | behaviour |
|---|---|
| **0 points** | `_patrol_service_waypoint` returns false (1763-1764) and `_move_ai:1555` evaluates `patrol_points[wp_index]` → Godot index-out-of-bounds error each tick. Only `_ready:426-427` prevents this at spawn; clearing `patrol_points` at runtime on a live NEUTRAL guard re-arms it. |
| **1 point** | `_advance_patrol_index` pins `wp_index = 0` (1804-1806). Inside 1.0 m: wait>0 → dwell + re-arm forever (the timer expiring advances to the same index, so the next frame arms the same wait again); wait=0 → advance (no-op), return false, target = own position → `flat` < 0.25 → velocity 0. Outside 1.0 m: walks to it, then the above. |
| **`loop_type == ""`** | wrap `(wp_index+1) % count` (1814). |
| **PingPong** | `_patrol_dir` flips at each end (1807-1812); 3 points from index 0: 1, 2, 1, 0, 1, … (verified by `run_tests.gd:5456-5471`). |
| **point with no facing** | `patrol_facing[i] == false` → `_apply_patrol_yaw` returns (1794-1795); `patrol_yaws[i]` is still written (0.0 by the mission writer, 3875) but unread. |
| **wait 0** | no dwell; index advances on the arrival frame and the guard keeps walking (1777-1778). |
| **1.0 m arrival radius** | `global_position.distance_to(point) < 1.0` (1771), 3-D. A point whose authored `y` is more than 1.0 m below/above the walking plane can never be "reached" — `_move_ai` is planar (1582) but the radius is not. |
| **authored y kept** | `_assign_authored_patrol` copies `pos` verbatim (`3861-3876`); floor contact owns y (guard comment 1760-1761). |

Observables a parity test can compare per tick: `global_position` (x/z advance,
y from gravity/floor), `rotation.y`, `wp_index`, `_patrol_dir`,
`_patrol_wait_left`, `velocity.x/velocity.z`, and (indirectly)
`nav_steering` counters.

---

## 3. Spawn / configure API

### 3.1 Public surface a mission or test uses

| purpose | API | line |
|---|---|---|
| patrol path points | `patrol_points` (`@export Array[Vector3]`) | 196 |
| per-point dwell | `patrol_waits` (`@export Array[float]`) | 200 |
| per-point UE yaw (degrees) | `patrol_yaws` (`@export Array[float]`) | 201 |
| per-point facing flag | `patrol_facing` (`@export Array[bool]`) | 202 |
| loop mode | `patrol_loop_mode` (`@export String`) | 205 |
| patrol speed | `patrol_speed` (`@export float`) | 217 |
| escalation row inputs | `sight_range` 220, `lose_sight_range` 221, `hearing_range` 222, `fov_deg` 223, `sight_frustum_enabled` 216 | |
| escalation pin escape hatch | `_authored_senses_enabled` 258 (set false automatically at 504-509 when a caller pins an export) | |
| roster row | `roster_bucket` (`@export String`) 212; readers `roster()` 450, `roster_source()` 458, `escalation_profile()` 435, `escalation_row(state)` 470 | |
| level controller | `level_ctrl: Node` 322 — used for `is_blocked_by_smoke` (1870-1872, 2556-2558) and `light_probe` (2363) | |
| nav binding | none public: `_nav: NavSteering` created per instance at 300 and bound with `_nav.setup(self)` at 401 (`nav_steering.gd:53-55`) | |
| carried item | `set_carried_item(dict)` 2376, `has_carried_item()` 2382, `steal_carried_item()` 2386, `carries_lantern` 324, `enable_lantern()` 2319 | |
| telemetry | `get_alert_state()` 2291, signal `alert_state_changed` 7 | |
| KO/health | `take_knockout(dmg)` 2028, `apply_damage(dmg)` 2048, `knock_out(duration_override)` 2052, `wake_up_from_ko()` 2092 | |
| hearing config | `hearing_query_mask` 233 (default 127), `perception_tags` 246 | |

### 3.2 `mission_controller.gd` call sites (read-only)

- `:14` `const GuardScript := preload("res://src/ai/guard_ai.gd")`
- `:729` `_spawn_guards(ue_level_data.get("guard_spawns", []), anchor, ue_level_data.get("patrol_paths", []))`
- `:3738` signature `_spawn_guards(ue_spawns: Array, anchor: Vector3, patrol_paths: Array = [])`
- `:3743-3748` guard limit: 6 default, `NOVICE 4`, `MASTER_THIEF 8`
- `:3750-3754` candidate filter: `10.0 < p.distance_to(anchor) < 120.0`, first `limit`
- `:3755-3756` no candidate → four hard-coded offsets from the anchor
- `:3758` `_key_pool_for_map(...)`
- `:3763` `GuardScript.new()`
- `:3764` `g.level_ctrl = self`
- `:3765-3769` names: `"Guard_ClubLantern_%d"` for even idx (with
  `g.carries_lantern = true`, 3767), `"Guard_%d"` for odd idx
- `:3770` `_ground_position(pos, 8.0, 30.0, 0.15)`
- `:3771-3775` authored path branch: `_authored_patrol_index_for` →
  `_assign_authored_patrol(g, path)` → `patrol_paths_assigned += 1`
- `:3776-3791` fallback branch: `patrol_fallback_count += 1`, one `print`, and
  the 4-point square assigned directly to `g.patrol_points`
- `:3792` `g.position = grounded_pos`
- `:3793-3794` `if idx % 2 == 0 or idx == 1: g.set_carried_item(key_pool[idx % key_pool.size()])`
- `:3795` `add_child(g)` (so `_ready`/`_physics_process` start here)
- `:3861-3883` `_assign_authored_patrol` — see 3.3
- `:4744` `(load("res://src/ai/guard_ai.gd") as GDScript).cleanup_static_caches()` in `_exit_tree` (`:4717`)

Nothing in `mission_controller.gd` sets `roster_bucket`, so every mission-spawned
guard is roster-`"unbound"` and the name heuristic decides the profile
(`escalation_profile:435-444`): no `haunt`/`bouncer` in `Guard_ClubLantern_N` →
`"guardbase"`. `_ready:383-384` also sets `carries_lantern` from the name.

Group membership: `_ready:378-380` adds `"guards"`, `"thief_vision_highlight"`,
`"xray_target"`; `knock_out:2058` adds `"guard_bodies"` (removed at 2102);
`_rebuild_carried_visual:2426` adds `"interactables"`.
Collision: `collision_layer = 4`, `collision_mask = 1 | 2` (`_ready:381-382`).

### 3.3 Authored record shape (`_assign_authored_patrol`, `3861-3883`)

Input: one `patrol_paths[i]` record = `{"actor": String, "class": String,
"loop_type": String, "points": Array[Dictionary]}`; each point dictionary
`{"pos": [x,y,z] Godot metres, "wait": float seconds, "wait_deviation": float,
"facing": bool, "yaw": float UE degrees, "type": String}` (producer
`parse_tables.py:2529-2546`).

Transform: for each point dictionary, `_patrol_point_position` (3849-3853)
requires a 3-element `pos` and yields a `Vector3`, else `(INF,INF,INF)` and the
point is skipped (3870-3872, and 3833 in the distance helper). Appends to four
parallel arrays: `points.append(point)`, `waits.append(maxf(0, wait))`,
`yaws.append(yaw)`, `facings.append(facing)` (3873-3876). Empty result → return
without touching the guard (3877-3878). Then five `guard.set(...)` calls
(3879-3883) including `patrol_loop_mode = str(path.get("loop_type",""))`.

No re-projection, no y-flattening, no yaw conversion (the guard converts at
apply time, 1796).

### 3.4 Counts and map (authored data at this HEAD)

`guard_spawns` is built by `level_loader.gd:3436-3439` from `markers[]` whose
class contains `MissionSpawner_Character` or `Guard`, after the earlier `elif`
arms have taken throwables/ammo/health/civilians/`SmartObject`s
(`3392-3435`); the 800/907 `BP_SmartObject_GuardDefensiveLocation_C` markers go
to `smart_objects`, not `guard_spawns`.

| level file | `guard_spawns` | `civilian_spawns` | `patrol_paths` | waypoints |
|---|---|---|---|---|
| `Guildhall/Guildhall_Gameplay` | 116 | 3 | 120 | 350 |
| `OldManor/OldManor_Gameplay` | 82 | 2 | 82 | 308 |
| `FTUE/FTUE_AI` | 4 | 0 | 4 | 6 |
| `Guildhall/Guildhall_SkyboxGeo` | 3 | 0 | 0 | 0 |
| `OldManor/OldManor_Clues` | 1 | 0 | 2 | 4 |
| `OldManor/OldManor_Geo` | 2 | 0 | 0 | 0 |
| `MissionLobby/MissionLobby_Periphery` | 1 | 0 | 0 | 0 |

The merged Guildhall set is corroborated by the committed log:
`docs/reports/logs/r8/run_tests.log:1182` — `PASS: 55a authored patrols merged
(120 paths / 350 waypoints)`; same line at
`docs/reports/logs/w7-merged/run_tests.log:2246`.

Live guard count per mission = `min(limit, |markers within 10..120 m of the
player spawn|)` with `limit` 4/6/8 by difficulty (`3743-3754`). Node names are
`Guard_ClubLantern_<idx>` / `Guard_<idx>`; they are children of the
`MissionController` node, in groups `guards`, `thief_vision_highlight`,
`xray_target` (plus `interactables`/`guard_bodies` as above).

Which map is live: `GameState.active_map_id` defaults to `"old_manor"`
(`game_state.gd:47`) and `active_contract_order` to `2` (`:46`); contract 2's
sublevel tag is `Guildhall_Contract_02` (`run_tests.gd:78`), so the default
Guildhall deploy merges the 116 marker spawns + 120 patrol paths above. The
`thieves_den` map does not call `_spawn_guards` at all (`mission_controller.gd:727-729`).

---

## 4. Read-only surface inventory

### 4.1 Safe to read (no write to the guard)

| field | type | line |
|---|---|---|
| `state` | `int` | 225 |
| `health` | `float` | 226 |
| `detection` | `float` | 227 |
| `ko_timer` | `float` | 228 |
| `wp_index` | `int` | 229 |
| `state_timer` | `float` | 269 |
| `_seconds_in_state` | `float` | 270 |
| `_seconds_since_visible` | `float` | 271 |
| `attack_cooldown` | `float` | 272 |
| `investigate_pos` | `Vector3` | 268 |
| `_search_goal` / `_search_goal_timer` | `Vector3` / `float` | 278-279 |
| `search_scan_phase` | `float` | 276 |
| `investigation_search_seconds` | `float` | 242 |
| `last_investigation_kind` | `String` | 241 |
| `last_heard_tag`, `last_heard_stim_tag` | `String` | 234-235 |
| `last_heard_distance_m`, `last_heard_radius_m` | `float` | 236-237 |
| `hearing_query_mask` | `int` | 233 |
| `perception_tags` | `Array[String]` | 246 |
| `_weather_sound_carry`, `_weather_indoors` | `float` / `bool` | 247, 251 |
| `_authored_senses_enabled` | `bool` | 258 |
| `_sense_diff_scale` | `float` | 259 |
| `_written_sight`, `_written_lose`, `_written_fov` | `float` | 260-262 |
| `_patrol_wait_left` | `float` | 266 |
| `_patrol_dir` | `int` | 267 |
| `_speed_scale` | `float` | 273 |
| `_regen_blackout` | `float` | 282 |
| `_ally_scan_timer` | `float` | 283 |
| `_body_scan_timer` | `float` | 296 |
| `bodies_seen` | `int` | 297 |
| `_revive_target` / `_revive_progress` | `Node` / `float` | 280-281 |
| `ranged_accuracy_stacks` | `int` | 291 |
| `combat_role` | `String` | 293 |
| `last_ranged_damage` | `float` | 294 |
| `_ranged_hits` | `int` | 295 |
| `heard_blocked_by_wall`, `heard_as_standby` | `int` | 303-304 |
| `_last_emitted_suspicion` | `float` | 329 |
| `_sight_key` (read; `_sight_row` via `sight_row()`) | `String` | 287 |
| `_roster_cache_key` | `String` | 298 |
| `_use_real_anims` | `bool` | 310 |
| `_attack_anim_lock` | `float` | 311 |
| `_slip_anim`, `_takedown_vic_anim` | `bool` | 315-316 |
| `anim_player` | `AnimationPlayer` | 307 |
| `visual_root`, `body_mesh`, `alert_indicator` | nodes | 318-321 |
| `level_ctrl` | `Node` | 322 |
| `carries_lantern` | `bool` | 324 |
| `carried_item` | `Dictionary` | 325 |
| `lantern_root`, `lantern_light` | nodes | 326-327 |
| `patrol_points`, `patrol_waits`, `patrol_yaws`, `patrol_facing`, `patrol_loop_mode`, `patrol_speed` | see §3.1 | 196-217 |
| `sight_range`, `lose_sight_range`, `hearing_range`, `fov_deg`, `sight_frustum_enabled` | `float` / `bool` | 216-223 |
| `roster_bucket` | `String` | 212 |

Node3D: `global_position`, `rotation.y`, `velocity`.
`_nav` 300 via its read-only accessors (`nav_steering.gd:58-89`).

Pure functions: `effective_vision_range` 524, `weather_indoors` 563,
`hearing_weather_multiplier` 567, `get_state_speed` 1419, `get_detection_rate`
1313, `detection_gain_per_second` 1330, `_state_name` 2273, `_anim_state_name`
862, `_patrol_wait_for` 1782, and the statics `escalation_row_name` 464,
`detection_decay_seconds` 1340, `detection_decay_per_second` 1346,
`decayed_detection` 1355, `decay_step_detection` 1365,
`clamped_detection_for_transition` 1378, `detection_entry_ceiling` 1389,
`sprint_ramp_multiplier` 1395, `height_difference_strength_multiplier` 1401,
`hearing_marks_spotted` 2019.

Query-only (physics space, no state write): `_los_to_player` 1683,
`_pickpocket_reachable` 2517.

### 4.2 Mutating — must not be called by a shadow runner

`_set_state` 1250, `_enter_alerted` 1279, `_enter_combat` 1288,
`take_knockout` 2028, `apply_damage` 2048, `knock_out` 2052,
`wake_up_from_ko` 2092, `_recover_from_ko` 2099, `play_slip` 795,
`play_takedown_vic` 818, `steal_carried_item` 2386, `set_carried_item` 2376,
`interact` 2485, `enable_lantern` 2319, `set_highlighted` 2236,
`set_xray_highlight` 2243, `refresh_weather_sound_carry` 539,
`_update_weather_scope` 543, `_tick_regen` 1235, `_move_ai` 1542,
`_service_combat` 1613, `_fire_ranged_at` 1661, `_combat_role` 1652 (writes the
global `ReactionRoles` registry), `_scan_downed_guards` 1701,
`_on_downed_guard_noticed` 1737, `_update_ally_wakeup` 2131 (can wake *another*
guard), `_update_guard_anim` 883, `_update_procedural_anim` 2195,
`_apply_guard_melee_hit` 763, `_tick_attack_hit_window` 778,
`_update_disguise_viewcone` 2535 (writes the player's disguise integrity),
`_update_indicator` 2254, `_emit_alert_state_if_needed` 2309,
`_build_visuals` 579, `_build_lantern` 2325, `_rebuild_carried_visual` 2416.

Direct writes that mutate: `state =`, `detection =`, `wp_index =`,
`_patrol_wait_left =`, `_patrol_dir =`, `state_timer =`, `_seconds_in_state =`,
`_seconds_since_visible =`, `ko_timer =`, `health =`, `investigate_pos =`,
`patrol_points/waits/yaws/facing/loop_mode =`, `sight_range/lose_sight_range/
fov_deg/hearing_range =`, `roster_bucket =`, `perception_tags =`,
`hearing_query_mask =`, `carries_lantern =`, `carried_item =`, `level_ctrl =`.
Note `set("state", n)` (used by `e2e_tier3_pairwise.gd:617-621`,
`test_hearing_ranges.gd:308`, `run_tests.gd:8269`) skips
`_apply_authored_escalation` and the detection clamp, so a guard forced that way
carries a different sense config than one that transitioned.

### 4.3 Lazily initialised — a reader can trigger these

| call | writes | triggered from |
|---|---|---|
| `sight_row()` 478-483 | `_sight_row`, `_sight_key` (cache), and through `escalation_row` → `HearingData.ensure_loaded()` (process-global JSON load, `hearing_data.gd:167-185`) | `_can_see_player:1860`, `_scan_downed_guards:1709` |
| `roster()` 450-454 | `_roster_row`, `_roster_cache_key`; `GuardRoster._json_buckets`/`_json_loaded` (`guard_roster.gd:143-168`) | `escalation_profile:436`, `_guard_weapon_set:649`, `_resolve_guard_glb_path:932`, `_ready:406-411` |
| `escalation_profile()` 435 | via `roster()` | `escalation_row:471` |
| `revive_hold_s()` 1220-1227 | static `_downed_data` (file read) | `_update_ally_wakeup:2170` |
| `hearing_sense_multiplier()` 574-576 | `HearingData` statics via `ensure_loaded` | `get_alert_state:2300`, `_hear:1926` |
| `_nav.step_towards` `nav_steering.gd:137` | `_ensure_agent()` adds a `NavigationAgent3D` child (`:116-131`), counters | `_move_ai:1587` |
| `_guard_ensure_material_dbs` 955 | `_guard_mats_db`/`_guard_mesh_mats` caches | `_bind_guard_glb_materials:1132`, `_attach_guard_head:1163` — i.e. `_ready` only |
| `_carry_scr_cache` 2435-2460 | static compiled `GDScript` | `_rebuild_carried_visual`, which is `_ready:424` and `set_carried_item:2379` |

`_apply_authored_escalation` (501-518) is **not** reached from the tick — only
`_ready:400` and `_set_state:1266`. There is no `_ensure_visual` in this file;
visuals are built once from `_ready:420` (`_build_visuals`), and the lantern from
`_ready:422` or `enable_lantern:2322`. `_ensure_agent` is the only node-tree
mutation a movement call can trigger.

---

## 5. Modules already ported (`game/src/ai/*.gd`)

| file | lines | authored data consumed | instantiation |
|---|---|---|---|
| `sight_model.gd` | 244 | `AIC_*` `_EscalationStateToSettings`: 8 fields × 4 rows, with the `AUTHORED_FALLBACK` table `75-102` and JSON overlay via `HearingData.escalation_row` `120` | **static only** — never `.new()`; `guard_ai:21` preloads it as a script constant |
| `guard_roster.gd` | 268 | 7 `DA_SpawnBucket_*` assets (`AUTHORED_BUCKETS` 52-118): profile, weapon, model, lantern, carries_key; optional `spawners.json.guard_buckets` overlay (147-168) | static only |
| `reaction_roles.gd` | 181 | `DT_ReactionEvents` 8 rows: investigator caps/grace (35-41), combat pair (122-138) | static only, **process-global registry** |
| `ranged_attack.gd` | 138 | `GA_MeleeRangedAttack` damage curve 10→2 over 0..20 m, 2 s cooldown, 10 s / 3-stack accuracy, 3 s shock, EQS band 2..10 m (39-59) | static only |
| `hearing_occlusion.gd` | 190 | 285 `BP_TATAcousticPortal` boxes + `DT_HearingStimProperties` `PropogateThroughOpenPortals`; binary block/portal test, fail-open (89-121) | static only, **static portal cache + counters** |
| `nav_steering.gd` | 189 | `TATPathFollowingComponent` navmesh consumption; no authored numbers beyond agent radius/height (34-36); degrades to straight line (174-181) | **per-guard instance**: `guard_ai:300`, `civilian_npc:112` |
| `hearing_data.gd` | 625 | `hearing.json` (54 stim rows), `perception.json` (range modifiers), `guard_ai.json` (escalation/surface/portals) — statics 135-143 | static only |
| `civilian_npc.gd` | 585 | `AIC_Civilian` 4 sight rows, `CT_AIStats` 40 HP / 60 s KO (56-59), `NPC.Yelp`/`NPC.CallForHelp` stims; own `Mode {WANDER, FLEE, COWER, DOWNED}` 75 | **separate CharacterBody3D class** (one node per civilian), not a guard submodule; also the base class of `npc_clue_actor.gd:1` |

`guard_ai.gd` also preloads `animation_library.gd` (13), `light_probe.gd` (14),
`weather_profile.gd` (18) and `anim_notify.gd` (61).

Scope note: a parallel W9-P4 lane has an untracked `game/src/ai/statetree/`
(`bindings.gd`, `tree_model.gd`) in this worktree at the time of writing. It is
not referenced by `guard_ai.gd` and is not part of the FSM described above.

---

## 6. Determinism / test hooks

### 6.1 Environment and command line

- **No `TAT2_*` environment variable is read anywhere in `game/src/ai/**`.**
  `grep -rn "TAT2_\|get_environment" game/src/ai/` matches only a comment
  (`sight_model.gd:53`).
- The one diagnostic read in `game/src/ai/**` is the user arg
  `--sight-frustum=off`: `sight_model.gd:215-222`, iterating
  `OS.get_cmdline_user_args()`, cached in static `_frustum_enabled` (111) with
  **no reset**. It disables only the vertical gate (236).
- Guard behaviour is still affected by env vars read outside `ai/**`:
  `TAT2_COLLISION` (`level_loader.gd:1934`) changes the world colliders every
  sight/hearing/LOS ray hits; `TAT2_ROUGH_BAKE` (905), `TAT2_TEX_CAP` (525),
  `TAT2_PERIPH_RANGE` (535), `TAT2_MERGE_CELLS` (551) change geometry/rendering
  only. `TAT2_NO_DEN_PROBE` (`mission_controller.gd:1039`) affects the Den only.

### 6.2 Static / global caches in `game/src/ai/**`

| file | name | line | reset |
|---|---|---|---|
| `guard_ai.gd` | `_downed_data` | 115 | `cleanup_static_caches()` 2571-2573 (clears both) |
| `guard_ai.gd` | `_carry_scr_cache` | 116 | same 2572 |
| `guard_roster.gd` | `_json_buckets` | 143 | **none** |
| `guard_roster.gd` | `_json_loaded` | 144 | **none** |
| `hearing_data.gd` | `_hearing`, `_perception`, `_guard_ai`, `_stimuli`, `_stimuli_lower`, `_surfaces`, `_anomalies`, `_loaded`, `_anomaly_logged` | 135-143 | `reload_cache()` 155-164 (all nine) |
| `hearing_occlusion.gd` | `_portals`, `_portals_loaded` | 34-35 | **none** |
| `hearing_occlusion.gd` | `_blocks`, `_passes`, `_fail_open`, `_portal_passes`, `_door_blocks` | 36-40 | `reset_stats()` 44-49 |
| `hearing_occlusion.gd` | `_enabled` | 41 | `set_enabled()` 66-67 |
| `nav_steering.gd` | `_degraded_warned` | 38 | `reset_stats()` 86-89 |
| `nav_steering.gd` | `_degraded_frames_total`, `_ready_frames_total` | 39-40 | same |
| `reaction_roles.gd` | `_events`, `_combat`, `_next_event_id`, `_granted_investigator`, `_granted_standby`, `_granted_chaser`, `_granted_ranged` | 49-56 | `reset()` 66-73 (all seven) |
| `sight_model.gd` | `_frustum_enabled` | 111 | **none** (cmdline is read once per process) |
| `civilian_npc.gd` | `_nav_pre_sync_warned` | 89 | **none** |
| `civilian_npc.gd` | `_nav_pre_sync_deferred` | 90 | **none** |

Per-instance (not static) but run-order dependent: `_sight_row`/`_sight_key`
286-287, `_roster_row`/`_roster_cache_key` 288/298, `_guard_mats_db`/
`_guard_mats_lower`/`_guard_mesh_mats`/`_guard_mesh_lower`/`_guard_tex_cache`/
`_guard_std_cache` 369-374, `_last_emitted_suspicion` 329.

Directly coupled process-global state outside `ai/**`: `NoiseBus._event_counter`
(`noise_bus.gd:58`, reset `reset_event_counter()` 62-63) → every record's
`event_id` (127); `LightProbe` static `_game_data` (`light_probe.gd:64`).

### 6.3 Non-deterministic inputs a parity test must pin

- `Time.get_ticks_msec()` — `_update_weather_scope:544`, `_combat_role:1654`,
  `_on_downed_guard_noticed:1741`, `_hear:1994,1996`.
- `get_instance_id()` — SEARCH fan angle
  `fmod(search_scan_phase*2.3 + instance_id % 29, TAU)` `1566`; combat claim key
  `"combat:<player_instance_id>"` `1653`; GuardDowned event id
  `0x40000000 + body_instance_id % 0x3FFFFFFF` `1740`. Instance ids are not
  stable across processes or across spawn order in one process.
- Iteration order: `get_nodes_in_group("player")` 1450,
  `get_nodes_in_group("guards")` 2148, `get_nodes_in_group(GUARD_BODY_GROUP)`
  1715 — tree order.
- Existing fixtures reset `ReactionRoles` around the reaction checks
  (`run_tests.gd:8421, 8541, 8549`), `HearingOcclusion.reset_stats()` (`8603`),
  `NavSteering.reset_stats()` (`8628`); `HearingData.reload_cache()` is reset at
  `test_hearing_ranges.gd:63` and `test_w7h_surface_hearing.gd:84`;
  `guard_ai.cleanup_static_caches()` at `run_tests.gd:7593` and
  `test_m2_player.gd:417` (end of run only).

---

## 7. Test instantiation recipe

### 7.1 Cheapest live guard with a patrol path that actually ticks

`game/tests/probe_blackjack_race.gd:84-121` (Phase A):

```
85  var guard := (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
86  guard.name = "ProbeGuardA"
87-88 guard.position = Vector3(0,0,0); guard.rotation = Vector3.ZERO
89  guard.set("patrol_points", [Vector3(0,0,0)])
90  root.add_child(guard)          # _ready builds visuals, seeds nothing (path non-empty)
91  await process_frame
92  var player := _stub_player(root, Vector3(0,0,2.2))   # plain CharacterBody3D, layer 2
93  await physics_frame            # exactly one tick of guard _physics_process
```

- Physics **not** disabled → the patrol/`_move_ai` path runs (the committed log
  proves it: `docs/reports/logs/r8/probe_blackjack_race.log:42-45` shows the
  `nav_steering` degradation backtrace `_note_degraded` ← `step_towards` ←
  `_move_ai (guard_ai.gd:1587)` ← `_physics_process (guard_ai.gd:1521)`).
- **No mission boot.** It builds two `StaticBody3D` floors itself
  (`:42-44, 52-62`) and sets `GameState.state = "playing"` (`:41`); with the
  default `"menu"` the tick returns at 1436.
- Physics runs: 1 (Phase A) + up to 240 + 90 (Phase B, `:153-170`).
- Runtime: **no committed log states a duration** for this probe. The r8 log has
  no ms line (`docs/reports/logs/r8/probe_blackjack_race.log:54`
  `BLACKJACK_PROBE PASS fails=0`).

Alternative with authored waits/yaws but **no tick**: `run_tests.gd:5292-5493`
(suite 55a) parses `Guildhall_Gameplay.tatlevel.json` through
`level_loader._parse_sublevel_file` (`5301-5302`), calls
`mission_controller._spawn_guards([...], anchor, paths)` on a bare
`.new()` controller (`5381`), detaches guard 0, re-parents to root
(`5423-5424`) and **disables physics** (`w2_g0.set_physics_process(false)`,
`5425`), then calls `_patrol_service_waypoint` / `_apply_patrol_yaw` /
`_advance_patrol_index` directly (`5438, 5441, 5452, 5461-5468`). The PingPong
guard at `5456-5470` is never added to the tree at all.

A live ticking guard with zeroed speeds: `run_tests.gd:8246-8305`
(`_ai_blackjack_hold`), guard `8253-8261` (`patrol_points=[at]`,
`patrol_speed/suspicious_speed/chase_speed = 0.0`), then 2 + ≤240 + ≤90 physics
frames with a real thief; also no mission boot; no duration in any log.
E2E tier 3 uses `e2e_helpers.spawn_test_guard` (`e2e_helpers.gd:373-381`,
`await step_physics(2)`) inside a `make_arena()` level load — heavier than the
probe.

### 7.2 Registering a new suite in `game/tests/run_tests.gd`

Two registration shapes exist at this HEAD (plus a shared teardown):

1. **In-process block** in `_initialize()`. Pattern for a helper-backed suite:
   `7403-7412` (comment, `var c97_problems: Array[String] = await _run_suite97(root)`,
   `printerr("FAIL: …")`/`fails += 1`, else `print("PASS: 97 …")`). The helper
   itself lives after `_initialize` (`_run_suite97` at `8309-…`, `_run_suite87`
   at `7610`, etc.). Inline (no helper) example: suite 99 at `7499-7522`.
2. **Child-process row** in the suite tables. W9-P2 table `7529-7535`, loop
   `7536-7550`; W9-P3 table `7557-7562`, loop `7563-7577`. Each row is
   `[number, label, "res://tests/<file>.gd", "<PASS marker>"]`; the loop runs
   `OS.execute(OS.get_executable_path(), ["--headless","--path",…,"--script",…])`
   and fails unless exit code 0 **and** the marker string appears.
3. Termination/teardown: static-cache cleanup at `7579-7595` (includes
   `guard_ai.cleanup_static_caches()` at `7593`), `print("SUMMARY: fails=", fails)`
   `7597`, `quit(0 if fails == 0 else 1)` `7598`. `make test` runs the file
   (`Makefile:117-118`).

Highest suite number in use: **109** (`7557-7561`, `["109", "W9-P3 C2 Loc
fallback …", "res://tests/test_w9p3_localization.gd", …]`). 110 is unused; 100 is
a gap (99 in-process at `7499`, then 101 at `7530`). Other high numbers in use:
108 `7560`, 107 `7559`, 106 `7558`, 105 `7534`, 101 `7530`, 99 `7499`, 98
`7414`, 97 `7403-7412`, 96 (comment `7377`, print `7398-7402`), 91 `7254-7263`,
90 `7243-7252`.

A new suite also moves the `run_tests` floor in `tools/gate_ratchet.json`
(`gates.run_tests.passes = 301`, compared with `>=` against the committed
`docs/reports/logs/r8/run_tests.log`; `measured_on: e3678be`).
