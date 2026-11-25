# B1 facts — Guildhall foyer fills and the interior exposure overshoot

Worktree: `/home/john/Projects/TAT-2-rem-w9-p2`, branch `rem/w9-p2`, HEAD
`b13260b3da78273edc98e54a1ae5d167c5ad431b` (base `b13260b`). Read-only
investigation; no Godot/capture was run. The baseline is HEAD `b13260b`; the
working tree became dirty during the investigation (see §0.1). All gameplay
line references are to `git show b13260b:...` unless explicitly labelled
“current dirty”. P1's captures/logs are not in this worktree; they are in
`/home/john/Projects/TAT-2-rem-w9-p1` and `/tmp/opencode/grade*.log`.

Items are numbered to match the B1 brief. No fixes are proposed.

## 0. One-screen factual summary

- At HEAD `b13260b`, the P2-owned foyer fill is one function,
  `_add_guildhall_foyer_fills()`
  (`git show b13260b:game/src/missions/mission_controller.gd:564-580`). It
  creates exactly **two** shadowless warm omnis (the concurrent dirty worktree
  removes the `-53` one — §0.1):
  - `GuildhallFoyerFill_-53` at `(27, 31, -53)`, energy **1.6**, range **16 m**,
    attenuation **1.2**, colour `(1.0, 0.78, 0.55)`, `shadow_enabled=false`,
    registered with `light_probe` (`:567-580`).
  - `GuildhallFoyerFill_-64` at `(27, 31, -64)`, energy **1.3**, same range,
    attenuation, colour and registration (`:567-580`).
- The function runs from `_setup_environment()` (`:287`), which is called from
  `_ready()` (`:167`) **before** `start_contract()` (`:174`) loads the sublevels
  (`:672` async / `:682` sync). The fills are therefore present before the
  level-loader light plan and are **not** part of its 160-light budget.
- `_setup_environment()` adds 10 Guildhall port fills plus the registered
  `MissionMoon`; `PERF_CENSUS` on the P1 Guildhall load reports
  `lights=171 ... light_budget=160` while `TAT-2 Loaded guildhall` reports
  `lights=160` (`/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/logs/cap_p1_before_upper_foyer.log:65-66`).
- Distances to the `upper_foyer` / `yaw180` camera eye `(27, 29.67, -50)`:
  **3.282 m** (`-53`) and **14.063 m** (`-64`), both inside the 16 m range.
  Distances to the `gate` eye `(10, 24, 66)`: **120.412 m** and **131.294 m**,
  far outside 16 m. To the `foyer` eye `(22, 22.17, 125.3)`: **178.589 m** and
  **189.572 m**. To the `saferoom` eye `(22, 22.17, 128.4)`: **181.684 m** and
  **192.667 m**. Table in §6.
- P1 measured the fills' effect at exposure **0.44**, not 1.15: freeing both
  fills moves `upper_foyer` from `28.8 / 15 / 130 / 8.0` to
  `22.7 / 9 / 131 / 32.2` (mean/p50/p95/%<8) and `yaw180` from
  `21.5 / 13 / 73 / 22.4` to `20.3 / 12 / 70 / 24.5`
  (`build/qa/w9/p1-report.md:66-70`; `build/qa/w9/audit-a4.md:265-270`).
  No fills-off measurement at 1.15 exists.
- Suite 98 pins Guildhall **preset** constants (`AGX`, `NIGHT_EXPOSURE >= 1.15`,
  ambient `0.16`, one `gloomy` map), not any light node
  (`git show b13260b:game/tests/run_tests.gd:7414-7496`). Reducing the foyer
  fills cannot trip it.
- `game/src/core/weather_profile.gd` is byte-identical to `c2a1cd8`:
  `git diff c2a1cd8 -- game/src/core/weather_profile.gd | wc -l` = **0**;
  blob hash `5fc0213534c3e853ad95ddd67cb37c6f9ae0693d` on both sides.

### 0.1 Worktree drift during this investigation

- At the start (12:20) the only tracked dirty file was
  `build/qa/w9_grade_probe.gd` (the 314-line fill-scale edit).
- At 12:43 a concurrent process had also modified
  `game/src/missions/mission_controller.gd` (current dirty: the near
  `GuildhallFoyerFill_-53` removed at `:572-589`, a camera-scoped
  `FOYER_GRADE_*` block added at `:590-657`, called from `_process` at
  `:4492`) and `game/tests/run_tests.gd` (new suite 100 at `:7523-7560`); the
  probe had grown to 323 lines with `W9_GRADE_FILLS=near|far` (`:149`,
  `:231-234`). `git diff --stat` at that moment: probe 94 lines,
  `mission_controller.gd` 85 lines, `run_tests.gd` 42 lines.
- None of those edits is in HEAD `b13260b`. They are not part of the P1
  measurements, and this fact sheet does not evaluate the concurrent P2
  implementation. The P1 captures predate them (08:19-11:11). Line numbers in
  this drift bullet are the dirty tree at 12:43 and may move again.

---

## 1. `_add_guildhall_foyer_fills()` — exact contract and call site

### 1.1 Code (HEAD `b13260b`)

`git show b13260b:game/src/missions/mission_controller.gd:560-580`:

```gdscript
## The authored Guildhall foyer is a large checkered hall with a refill
## station; its practicals are sparse, so the 0.20 skylight leaves the stone
## walls and busts near-black. Two warm, shadowless fills lift the hall
## without touching the gate or the upper floors (range 16 m, y=31).
func _add_guildhall_foyer_fills() -> void:
	if GameState.active_map_id != "guildhall":
		return
	for spec: Array in [
		[Vector3(27.0, 31.0, -53.0), 1.6],
		[Vector3(27.0, 31.0, -64.0), 1.3],
	]:
		var fill := OmniLight3D.new()
		fill.name = "GuildhallFoyerFill_%d" % int((spec[0] as Vector3).z)
		fill.position = spec[0] as Vector3
		fill.light_color = Color(1.0, 0.78, 0.55)
		fill.light_energy = float(spec[1])
		fill.omni_range = 16.0
		fill.omni_attenuation = 1.2
		fill.shadow_enabled = false
		add_child(fill)
		light_probe.register_light(fill)
```

The doc comment says “without touching the gate or the upper floors” (`:563`).
Geometry shows the gate claim is true for the fill-to-eye distance (§6), but the
`upper_foyer` pose is 3.3 m / 14.1 m from the two lights and is the pose P1
measured as over-bright; the same comment's “upper floors” wording is therefore
contradicted by the P1 A/B result (`build/qa/w9/p1-report.md:66-70`).

### 1.2 Parameter table

| property | `GuildhallFoyerFill_-53` | `GuildhallFoyerFill_-64` | source |
|---|---|---|---|
| class | `OmniLight3D` | `OmniLight3D` | `mission_controller.gd:571` |
| position | `(27, 31, -53)` | `(27, 31, -64)` | `:567-570` |
| energy | `1.6` | `1.3` | `:568-569`, `:575` |
| colour | `Color(1.0, 0.78, 0.55)` | same | `:574` |
| range | `16.0` m | `16.0` m | `:576` |
| attenuation | `1.2` | `1.2` | `:577` |
| shadows | `false` | `false` | `:578` |
| volumetric fog energy | not set (class default) | not set | no assignment in `:571-578` |
| specular | not set | not set | no assignment |
| distance fade | not set | not set | no assignment |
| parent | mission node (`add_child(fill)`) | mission node | `:579` |
| group | none | none | no `add_to_group` |
| metadata | none | none | no `set_meta` |
| `light_probe` | registered | registered | `:580` |
| node name | `GuildhallFoyerFill_-53` | `GuildhallFoyerFill_-64` | `:572`; spelled out in `game/addons/tat2_review/review_environment.gd:115-116` |

`fill.name = "GuildhallFoyerFill_%d" % int(z)` (`:572`) produces the hyphenated
names because `z` is `-53.0` / `-64.0`; the review-mode copy spells the resulting
names explicitly (`game/addons/tat2_review/review_environment.gd:115-116`).

### 1.3 Call site, map/contract conditions, order relative to the level load

- `_setup_environment()` is called once from `_ready()` at
  `git show b13260b:game/src/missions/mission_controller.gd:167`.
- Before that call, `_ready()` resolves the map from the active contract and
  writes it to `GameState.active_map_id` (`:163-166`).
- `_ready()` then calls `start_contract(GameState.active_contract_order)` at
  `:174`. `start_contract()` re-resolves the contract map and writes
  `GameState.active_map_id` again at `:608-613`.
- `_setup_environment()` creates the environment, moon and all port fills
  (`:246-288`): moon at `:250-255`, weather apply at `:260-263`, Guildhall fog
  at `:273-277`, moon registration at `:283`, then gate fills (`:284`), car
  lights (`:285`), road fills (`:286`), **foyer fills (`:287`)**, saferoom fill
  (`:288`).
- The authored level is loaded later, inside `start_contract()`:
  sublevel paths at `:663`, light budget at `:666`, async load at `:667-672`
  (`load_sublevels_async(..., light_budget)`) or sync load at `:679-682`
  (`load_sublevels(..., light_budget)`). The fill nodes already exist at that
  point.
- The only map gate in `_add_guildhall_foyer_fills()` is
  `if GameState.active_map_id != "guildhall": return` (`:565-566`). There is no
  contract-order check and no `MobileProfile.is_mobile()` check, so every
  Guildhall deploy (normal contract or free play) gets both lights, on desktop
  and mobile.
- `light_budget` is computed only at `:666`, after the fills were created, and
  passed only to the loader. It is not a global node cap; see §3.

### 1.4 What `light_probe.register_light` does

`git show b13260b:game/src/stealth/light_probe.gd:80-82`:

```gdscript
func register_light(light: Light3D) -> void:
	if not registered_lights.has(light):
		registered_lights.append(light)
```

- Registration is an append to `registered_lights` (`:60`), deduped by instance.
  It does not add the light to any budget, group or scene count, and it does not
  affect rendering.
- `sample_visibility()` (`:180-225`) is the consumer:
  - starts at ambient `0.08` (`:188`);
  - iterates `registered_lights` (`:190`);
  - skips invalid/invisible lights (`:191`);
  - directionals contribute `energy * 0.25`, capped `0.35`, after an occlusion
    ray (`:193-202`);
  - local lights with `light_energy > 0.01` (`:203`) are rejected if farther
    than the global `LIGHT_SAMPLE_RANGE = 25.0` (`:9`, `:205-207`) or outside
    their own `omni_range`/`spot_range` (`:208-214`);
  - a ray from the light position to `world_pos + Vector3.UP * 0.9` is cast on
    `OCCLUSION_MASK = 1` with the caller's `exclude` (`:52-53`, `:215-218`);
  - if unoccluded, contribution is
    `falloff * falloff * light_visibility_weight(energy)` where
    `falloff = 1 - dist/range` (`:219-221`);
  - `light_visibility_weight(energy) = clamp(energy * 0.9, 0.15, 0.9)`
    (`:44-46`, `:176-177`); the total is clamped to `0..1` (`:222`).
- The player calls this on each `_tick_sustained_systems()` tick and stores the
  result: `git show b13260b:game/src/player/thief_character.gd:1595-1597` writes
  `GameState.player_light_visibility`. The same registered set also feeds the
  HUD light-gem sector (`thief_character.gd:1093-1120`) and the Slithersap /
  puddle short-circuit (`light_probe.gd:91-103`).
- The guard consumes the stored value:
  `git show b13260b:game/src/ai/guard_ai.gd:1410-1415` (`_player_light_value`)
  and `:1845`; the disguise gate also reads it at `:1835`.
  `GameState.gd:136` initialises it to `0.2`.
- Net effect: a registered fill contributes to **player light visibility,
  guard sight-range scaling, HUD light direction and light short-circuiting**.
  An unregistered fill is render-only for stealth.
- Measurement caveat: `w9_grade_probe.gd` moves a standalone camera, not the
  player (`build/qa/w9_grade_probe.gd:239-251`); the player remains at the
  mission spawn. The P1 grade frames therefore measure rendering, not the
  player's sampled stealth value at those camera positions.

For the two foyer fills, the camera-eye distances are 3.282 m and 14.063 m. The
actual `sample_visibility` sample point is the player feet plus 0.9 m
(`light_probe.gd:215`), not the camera eye; at the `upper_foyer` player feet
`(27, 28, -50)` the sample point `(27, 28.9, -50)` is **3.662 m** and
**14.156 m** from the fills, still inside 16 m.

---

## 2. Every other port-authored `OmniLight3D` / `SpotLight3D` in the same file

`mission_controller.gd` at HEAD `b13260b` creates all of the following outside
`level_loader`. The Guildhall table is the complete set of Guildhall hand lights
at HEAD; the Den table is the other map's hand fills in the same file.
“Registered” means `light_probe.register_light()` was called. The concurrent
dirty worktree removes the `-53` row; see §0.1.

### 2.1 Guildhall hand lights at HEAD `b13260b` (10) plus `MissionMoon`

| node | class | position | energy | range | attenuation | colour | shadows | fog energy | registered | source |
|---|---|---|---:|---:|---:|---|---|---|---|---|
| `GuildhallGateLampFill` | Omni | `(11.5, 23, 92)` | 2.2 | 12 | 1.2 | `(1.0,0.74,0.48)` | off | default | **yes** `:311` | `:302-311` |
| `GuildhallFenceLampFill` | Omni | `(10, 27, 46)` | 3.5 | 16 | 1.2 | `(1.0,0.76,0.52)` | off | default | **yes** `:324` | `:312-324` |
| `GuildhallOrnateGateFill` | Omni | `(80, 20, 18)` | 1.5 | 11 | 1.3 | `(1.0,0.76,0.52)` | off | **0.0** `:336` | **no** (comment `:328`) | `:329-338` |
| `GuildhallRoadFillL` | Omni | `(8.6, 21.2, 52)` | 0.7 | 8 | 1.4 | `(1.0,0.76,0.52)` | off | **0.0** `:364` | **no** (comment `:344-345`) | `:351-365` |
| `GuildhallRoadFillR` | Omni | `(11.4, 21.2, 52)` | 0.7 | 8 | 1.4 | `(1.0,0.76,0.52)` | off | **0.0** `:364` | **no** | `:351-365` |
| `GuildhallCarHeadlightL` | Spot | `(17.83, 19.96, 65.81)`, aims `(11,18.6,54)` | 4.5 | 16 | 1.0 | `(1.0,0.843,0.651)` | off | **0.0** `:396` | **no** (comment `:372-373`) | `:382-403` |
| `GuildhallCarHeadlightR` | Spot | `(17.91, 19.96, 67.02)`, aims `(9,18.6,57)` | 4.5 | 16 | 1.0 | same | off | **0.0** `:396` | **no** | `:382-403` |
| `GuildhallFoyerFill_-53` | Omni | `(27, 31, -53)` | 1.6 | 16 | 1.2 | `(1.0,0.78,0.55)` | off | default | **yes** `:580` | `:564-580` |
| `GuildhallFoyerFill_-64` | Omni | `(27, 31, -64)` | 1.3 | 16 | 1.2 | same | off | default | **yes** `:580` | `:564-580` |
| `GuildhallSafeRoomFill` | Omni | `(127, 29, -5)` | 1.1 | 12 | 1.2 | `(0.72,0.78,0.95)` | off | default | **yes** `:557` | `:545-557` |
| `MissionMoon` | Directional | mission origin, rotated `(-48,32,0)` fallback | fallback `0.55`, weather may override | n/a | n/a | fallback `(0.68,0.78,0.98)` | on (fallback `:605`) | n/a | **yes** `:283` | `:250-255`, `:282-283`, `:601-605` |

Details:
- Gate, foyer and saferoom fills are Guildhall-only with no mobile guard
  (`:300`, `:565`, `:546`); road fills add the map gate at `:347` and the desktop
  gate at `:349-350`; car lights add the map gate at `:378` and the desktop gate
  at `:380-381`.
- The car spots set `spot_angle = 55.0` (`:393`), `distance_fade_enabled = true`,
  `distance_fade_begin = 25.0`, `distance_fade_length = 20.0` (`:397-399`), and
  aim after `add_child` via `look_at` (`:401-403`).
- `MissionMoon` is the only directional hand light. Its energy is set by
  `_apply_fallback_moon()` at `:604` and then overwritten by the weather preset
  in `_setup_environment()` (`:260-261`).
- `GuildhallSkylineClocktower` is **not a light**: `_add_guildhall_skyline_clocktower()`
  creates a `MeshInstance3D`, position `(10, 20, -120)`, scale `2.6`
  (`:511-538`), and its own comment says “no collision, no light_probe
  registration” (`:509`). It runs after the level build at `:696`, not in
  `_setup_environment()`.
- `review_environment.gd:108-118` mirrors **eight** of the ten Guildhall hand
  lights (gate, fence, ornate, road L/R, the two foyer fills and saferoom; it
  omits the two car headlights) for review mode; it is a copy, not a call into
  `mission_controller`.

### 2.2 Den hand fills in the same file (Guildhall-irrelevant, for completeness)

These are created only in `_setup_thieves_den_hub()`, which the Guildhall path
never calls: the call is inside `if map_id == "thieves_den"` at
`git show b13260b:game/src/missions/mission_controller.gd:715-716`.

| node | class | position | energy | range | attenuation | registered | source |
|---|---|---|---:|---:|---:|---|---|
| `DenAtticFill` | Omni | `anchor + (1.5, 2.6, -1.5)` | 0.15 | 8 | 1.2 | yes `:1057` | `:1048-1057` |
| `DenRoomFill` | Omni | `(1.3, anchor.y+1.05, 271.4)` | 0.40 | 8 | 2.0 | yes `:1074` | `:1064-1074` |
| `DenMoonBeam` | Spot | `win_pos`; aims at `win_pos - outward*DEN_WINDOW_SHAFT_LENGTH` | 0.25 | 14 | 2.0 | yes `:1100` | `:1086-1100` |
| `DenWindowBacklight` | Spot | `win_pos + outward*1.1`; aims inward | 0.6 | 7 | 1.6 | yes `:1124` | `:1109-1124` |
| `DenShadeFill` | Omni | `(4.011, 41.7004, 267.5435)` | 0.60 | 3 | 1.5 | yes `:1179` | `:1167-1179` |
| `DenPosterFill` | Omni | `DEN_POSTER_WALL_CENTRE + DEN_POSTER_FILL_OFFSET` | `DEN_POSTER_FILL_ENERGY = 0.10` (`:122`) | 2.6 | 2.0 | yes `:1198` | `:1186-1198` |
| `DenWardLight` | Omni | `wardrobe_pos + (0, 1.1, 0.4)` | 0.20 | 5 | not set | yes `:1319` | `:1311-1319` |

- The “wisp” light is created by `VfxManager.spawn_blue_wisp()` and only added
  to the `den_hand_fills` group (`mission_controller.gd:1237-1241`); it is not
  registered with `light_probe`. T07's count is “7 `den_hand_fills`, sum 2.00,
  6 of 7 registered — the wisp light is not”
  (`docs/reports/remediation-20261125/T07-render.md:360`).
- `DenWindowBacklight` is deliberately not in `den_hand_fills` (comment
  `:1104-1108`), so it is not part of the 2.00 group sum.
- Guard lanterns are a third runtime source outside this file:
  `git show b13260b:game/src/ai/guard_ai.gd:2346-2355` creates `LanternLight`
  (Omni, energy 1.4, range 8.5, attenuation 1.35, shadows off) and registers it
  at `:2358-2373`.

### 2.3 Node count observed

P1's Guildhall capture log has both numbers in one load:

```
PERF_CENSUS ... lights=171 shadow_lights=7 ... light_budget=160 hero_shadows=6 ...
TAT-2 Loaded guildhall: meshes=63103 lights=160
```

`/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/logs/cap_p1_before_upper_foyer.log:65-66`.
`lights=160` is the loader's own count; `lights=171` is the mission-tree count
after the 10 Guildhall fills and `MissionMoon` were added. This is the same
“160 budgeted + 11 non-budgeted” count stated in
`docs/reports/remediation-20261125/T07-render.md:105`.

---

## 3. How lights are budgeted/selected; do the mission fills count?

### 3.1 The budget pipeline

- The desktop cap is `MobileProfile.DESKTOP_MAX_LIGHTS = 160`
  (`game/src/core/mobile_profile.gd:14`) and
  `DESKTOP_HERO_SHADOWS = 6` (`:15`). There is **no** `MAX_*_LIGHTS` constant in
  `level_loader.gd`; the cap is owned by `MobileProfile`.
- Mobile tier caps are 12 / 24 / 32 (`mobile_profile.gd:156-163`); mobile hero
  shadows 1 / 2 / 4 (`:166-180`).
- `MobileProfile.light_budget(fallback)` accepts a positive `TAT2_LIGHT_BUDGET`
  env override (`:20`, `:139-141`). `MobileProfile.max_lights()` is the
  mission-facing getter (`:148-153`); QA can also set `--perf-lights` through
  `set_override_limits()` (`:58-69`).
- `mission_controller.start_contract()` computes
  `var light_budget: int = MobileProfile.max_lights()` at `:666` and passes it to
  `load_sublevels_async(..., light_budget)` at `:672` or
  `load_sublevels(..., light_budget)` at `:682`.
- `level_loader._effective_light_budget(requested)` is the single applied-budget
  helper (`game/src/core/level_loader.gd:559-563`); it prints the
  `TAT-2 perf light env` line only when the applied budget/shadow count differs.
- The loader collects only parsed authored lights into `acc["lights"]`
  (`:6699` parse), then `pending_lights = _prioritize_lights(acc["lights"], ...)`
  at `:6714`. `plan_light_selection(pending_lights, ...)` is called at `:6719`.
  The sync path is the same: `_add_lights(acc["lights"], ...)` at `:6651`.
- `plan_light_selection(ordered, max_lights, map_hint)`
  (`level_loader.gd:5449-5525`) has no tree scan; it sees only `ordered`, which
  is the authored list. Therefore the mission-controller hand fills cannot be in
  it.

### 3.2 Per-room fair plan in one paragraph

`plan_light_selection` (`level_loader.gd:5449-5525`):

1. `budget = mini(ordered.size(), max_lights)` (`:5450`).
2. Guildhall-protected lights (six KF16 gate lights, contract-2 safe-room spot)
   are pulled into `forced` and skipped from the cells (`:5459-5461`, protected
   points `:373-380`).
3. Every other candidate gets a 16 m cell key
   `light_room_cell()` (`:5423-5432`, `LIGHT_ROOM_CELL_M = 16.0` `:356`);
   preference order inside a cell is preserved (`:5454-5466`).
4. Cells are sorted densest-first, then by the best light's score, then by a
   stable cell-key order (`:5470-5486`).
5. Slots are handed out one round at a time: each cell gets its next light
   before any cell gets a second (`:5487-5505`).
6. The first `MobileProfile.hero_shadows()` selected lights in global preference
   order get shadows; forced lights are appended shadowless (`:5506-5514`).
7. The returned `stats` report authored/budget/kept/forced/cells/covered/
   `cell_m`/`hero_shadows` (`:5515-5525`).

The measured P1 Guildhall load:
`TAT-2 light allocation: map=guildhall authored=914 kept=159 budget=159 forced=7 rooms=152/187 cell_m=16.0`
and `TAT-2 gate lights: total=160 (generic=159 rect=1) budget=159 forced=7 hero_shadows=6`
(`/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/logs/cap_p1_before_upper_foyer.log:38-39`;
same lines in `docs/reports/remediation-20261125/T07-render.md:111-112`).

### 3.3 Do the ephemeral mission_controller fills count against the budget?

**No.** The evidence chain:

- The fills are added to the mission node in `_setup_environment()`
  (`mission_controller.gd:284-288`, foyer specifically `:287`), before
  `start_contract()` calls the loader (`:174`, `:672` / `:682`).
- The loader's plan receives only `acc["lights"]` from the parsed authored
  sublevels (`level_loader.gd:6699`, `:6714`, `:6719`; sync `:6651`).
- `plan_light_selection` budget is `min(ordered.size(), max_lights)` (`:5450`),
  i.e. only the authored list.
- Observed count: `PERF_CENSUS ... lights=171 ... light_budget=160` while
  `TAT-2 Loaded guildhall ... lights=160`
  (`cap_p1_before_upper_foyer.log:65-66`). The extra 11 are the 10 Guildhall
  hand fills plus `MissionMoon`; `PERF_CENSUS` runs inside the loader before
  guards spawn, so no guard lanterns are included.
- T07 states the same: “10 Guildhall fills + 7 Den fills are created in
  `mission_controller.gd` **after** the budget, so they occupy nodes 161-177”
  (`docs/reports/remediation-20261125/T07-render.md:332-347`) and the node-count
  row is `160 budgeted + 11 non-budgeted`
  (`docs/reports/remediation-20261125/T07-render.md:105`).

One code-comment inconsistency: `_add_guildhall_road_fills()` says the road fills
are “added after the authored 160-light budget pass”
(`mission_controller.gd:344-345`), but all five `_add_guildhall_*` fill calls run
in `_setup_environment()` at `:284-288`, i.e. **before** the sublevel load at
`:672`/`:682`. The fills do bypass the budget; the “after the pass” wording is
not the call order.

---

## 4. P1 measurement contract (quotes from `build/qa/w9/p1-report.md` §0.2)

### 4.1 Conditions

`build/qa/w9/p1-report.md:11-12`:

> All frames are 1920×1080 Vulkan, `TAT2_AO=on`, measured with the L1 pipeline
> (`python3 build/qa/w9_frame_stats.py`), not with the in-engine non-black guard.

`build/qa/w9/p1-report.md:46-47`:

> Measured with `build/qa/w9_grade_probe.gd` (one launch, timed A/B `grade8`,
> wall 97 s, GPU 60.67 → 65.83 °C, 5454 → 5779 MiB):

### 4.2 The four-pose table, copied verbatim

`build/qa/w9/p1-report.md:49-54`:

| pose | exposure 1.15 (today) mean/p50/p95/%<8 | exposure 0.44 mean/p50/p95/%<8 |
|---|---|---|
| KF16/KF18 gate approach | 23.2 / 10 / 66 / **23.9** | 12.5 / 3 / 40 / **72.0** |
| `upper_foyer` | 50.4 / 34 / 182 / **0.8** | 28.8 / 15 / 130 / **8.0** |
| `foyer_sweep_yaw180` (KF27) | 40.5 / 31 / 105 / **2.3** | 21.5 / 13 / 73 / **22.4** |
| `foyer` (lower approach) | 31.5 / 32 / 58 / **1.3** | 15.0 / 13 / 34 / **36.1** |

`foyer_sweep_yaw180` in the report is the probe's `yaw180` pose
(`build/qa/w9_grade_probe.gd:45`) and the PNG `grade8_yaw180_e115_a100_l100.png`;
the capture-harness name is the `yaw180` shot of `foyer_sweep`
(`build/qa/w9_capture.gd:353-369`).

I re-ran `python3 build/qa/w9_frame_stats.py` over the 13 P1 PNGs (8 `grade8_*`,
3 `grade7_*`, 2 `grade4_*_nofill` in
`/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/captures/`) and every table row
reproduced exactly, including `%<8` and `p95`. No capture was run for this check.

### 4.3 Fill-free A/B, copied verbatim

`build/qa/w9/p1-report.md:66-70`:

> The room-local cause is measured: the two shadowless foyer fills
> (`mission_controller.gd:564-580`, energy 1.6 at 3.3 m and 1.3 at 14.1 m from the
> upper-foyer eye) own that pose's overshoot. Freeing them at one exposure moves
> `upper_foyer` 28.8 → 22.7 mean, p50 15 → 9, `%<8` 8.0 → 32.2, while `yaw180`
> barely moves (21.5 → 20.3). **Verdict: BLOCKED-ON P2** (per-room grade), with a
> guard suite (98) that fails if anyone lands a global cut without the room scope.

The “one exposure” is **0.44**, from `grade4`'s `W9_GRADE_START`
(`/tmp/opencode/grade4.log:29`) and the `_e044_` filenames. `audit-a4.md:265-270`
gives the full four-number A/B:

- `grade4_upper_foyer_e044_a100_nofill.png` = **22.7 / 9 / 131 / 32.2**;
- `grade4_yaw180_e044_a100_nofill.png` = **20.3 / 12 / 70 / 24.5**;
- with fills on at 0.44: `upper_foyer` = 28.8 / 15 / 130 / 8.0, `yaw180` =
  21.5 / 13 / 73 / 22.4 (the table above).

I re-measured those two nofill PNGs with `w9_frame_stats.py` and got the same
numbers. **There is no fills-off measurement at exposure 1.15** in the P1
evidence; the only nofill run is `grade4` at 0.44 / 0.50
(`/tmp/opencode/grade4.log:29`).

### 4.4 Gate ladder, copied verbatim

`build/qa/w9/p1-report.md:56-57`:

> Gate ladder at one launch (`grade7`, wall 283 s): 1.00 → 21.3 / 9 / **38.0 %**;
> 0.85 → 19.3 / 7 / **51.8 %**; 0.75 → 17.9 / 6 / **59.6 %**.

The `grade7` log's base exposure was 0.440 with a transient `interior=true`
branch (`/tmp/opencode/grade7.log:33`, `:509594`); the ladder itself sets each
exposure explicitly, so the three values are valid for those explicit
exposures. The shipped `grade8` load is at 1.150
(`/tmp/opencode/grade8.log:33`, `:560319`).

Re-measured from the P1 PNGs:

```
grade7_gate_e100_a100_l100.png  mean=21.3 p50=9 p95=61 lt8=38.0%
grade7_gate_e085_a100_l100.png  mean=19.3 p50=7 p95=57 lt8=51.8%
grade7_gate_e075_a100_l100.png  mean=17.9 p50=6 p95=54 lt8=59.6%
```

Suite 98's comment records `51.9` and `62.2` for the last two rungs
(`git show b13260b:game/tests/run_tests.gd:7420-7421`), which do not match the
measured P1 PNGs (`51.8`, `59.6`) or the P1 report (`51.8`, `59.6`). No captured
frame in `/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/captures/` corresponds
to 62.2; the `e075` gate frame measures 59.6.

### 4.5 Target band and its citation

`build/qa/w9/p1-report.md:59-64`:

> **The interior target (p50 13-15, `%<8` 9-24) is reachable — at ≈0.44 — but only
> by crushing the same preset's gate view**, which is *already* below its own
> KF16/KF18 reference at 1.15 (p50 10 against a p50 26-28 target) and loses black
> floor for every step removed. One `gloomy` Environment cannot move in both
> directions, so **no global exposure/ambient change shipped** and
> `weather_profile.gd` is byte-identical to `c2a1cd8`.

The same band is stated in `build/qa/w9/p0-report.md:26-28`:

> Pre-R8 was p50 2–4 with 52–78 % of pixels < 8; the target was p50 13–15 with
> 9–24 % < 8.

`p0-report.md:81` cites `T07-render.md:555-560` for that band. What T07 actually
says at `docs/reports/remediation-20261125/T07-render.md:555-556` is:

> expect p50 to move from 2 toward the reference 13-15 and `%<8` from 78 % down
> to ~10-25 %.

So the **p50 13-15** part is verbatim in T07; the **`%<8` 9-24** part is not
verbatim in T07 (T07 says ~10-25). The 9-24 figure appears first in the P0
report (`:27`) and is repeated by P1 (`:59`).

The gate reference p50 26-28 is in `p1-report.md:61`; T07's normalized
0.10-0.11 gate reference is at
`docs/reports/remediation-20261125/T07-render.md:176-177`.

---

## 5. Harness contracts

### 5.1 `build/qa/w9_grade_probe.gd` — env contract

At HEAD `b13260b` the probe has 271 lines and no fill-energy axis; the only fill
lever is `W9_GRADE_FILLS=off`
(`git show b13260b:build/qa/w9_grade_probe.gd:22-34`, `:181-184`). The table
below documents the **314-line B1 fill-scale snapshot** read at 12:28 (not HEAD
and not the later concurrent 323-line near/far edit). The “HEAD?” column says
whether the variable exists at `b13260b`.

| env var / arg | default | effect | line (B1 snapshot) | HEAD? |
|---|---|---|---|---|
| `W9_QA_OUT` | `<repo>/build/qa/w9/captures` | output directory; PNGs saved here | `:22-23`, `:68-73`, `:118-119` | yes |
| `W9_GRADE_POSES` | `upper_foyer,yaw180` | comma list; known names `upper_foyer`, `yaw180`, `yaw090`, `yaw270`, `foyer`, `saferoom`, `gate`; unknown names print `W9_GRADE unknown pose=` and are skipped | `:24-25`, `:43-53`, `:219-227` | yes (`gate` is in the table at HEAD) |
| `W9_GRADE_EXPOSURES` | `0.30,0.40,0.50,0.60` | comma list of `Environment.tonemap_exposure` values | `:26`, `:212` | yes |
| `W9_GRADE_AMBIENT_SCALES` | `1.0,0.5` | multipliers on the live `Environment.ambient_light_energy` | `:27-28`, `:213` | yes |
| `W9_GRADE_LIGHT_SCALES` | `1.0` | multipliers on lights that carry the `tat_ue_intensity` meta (loader-authored only); **not documented in the header** | `:215`, `:186-195`, `:198-202` | yes (HEAD `:184`, undocumented) |
| `W9_GRADE_FILL_SCALES` | `1.0` | multipliers on **only** the two `GuildhallFoyerFill_*` omnis | `:29-30`, `:217`, `:159-169`, `:172-179` | **no**; uncommitted B1 edit |
| `W9_GRADE_FILL_RANGE_SCALES` | `1.0` | multipliers on the same two fills' `omni_range` | `:31-32`, `:218`, `:172-179` | **no**; uncommitted B1 edit |
| `W9_GRADE_FILLS` | `on` | exactly the lower-case string `off` frees every node named `GuildhallFoyerFill_*` before the bracket and appends `_nofill` to names; other values are “on” | `:33-34`, `:228`, `:140-149`, `:267-270` | yes |
| `TAT2_AO` | inherited (`on` in P1) | passed through, echoed in `W9_GRADE_START` | `:35-36`, `:229-234` | yes |
| `--tag=` | `grade` | filename prefix | `:206` | yes |
| `--size=` | `1920x1080` | render size | `:207-210` | yes |

The concurrent dirty probe (323 lines) adds `W9_GRADE_FILLS=near|far`
(`:231-234`) and names freed frames `_nofill_<mode>`; the fill-scale axes remain
(`:216-218`, `:290-307` in that dirty file).

Implementation of the fill axis in the 314-line B1 snapshot:

- `_foyer_fill_base()` walks the mission tree and collects only `OmniLight3D`
  nodes whose name begins with `GuildhallFoyerFill_`, storing
  `[node, base_energy, base_range]` (`:159-169`).
- `_apply_fill_scale(base, energy_scale, range_scale)` sets
  `light_energy = base_energy * energy_scale` and
  `omni_range = max(0.1, base_range * range_scale)` (`:172-179`).
- The bracket loop order is pose → ambient scale → light scale → fill energy
  scale → fill range scale → exposure (`:284-292`), with `await _wait(10)` per
  shot (`:297`).
- The filename suffix `_fNNN_rNNN` is added only when either fill scale is not
  `1.0` (`:301-303`); the base name is
  `tag_pose_e(exp*100)_a(ambient*100)_l(light*100)` (`:304-306`), then `.png`
  in `_save` (`:116-124`).
- The live grade is restored after the loop (`:309-313`).

The energy axis is therefore already implemented in the B1 snapshot at those
five points. At HEAD only `W9_GRADE_FILLS=off` exists; the authored-light
`W9_GRADE_LIGHT_SCALES` axis does **not** touch the hand fills because they have
no `tat_ue_intensity` metadata (`:186-195`; the comment at `:181-185` says the
light-scale axis was wired but unmeasured).

### 5.2 Grade-probe pose table (all entries)

`build/qa/w9_grade_probe.gd:43-53`:

| pose | eye | target |
|---|---|---|
| `upper_foyer` | `(27, 28+1.67, -50)` = `(27, 29.67, -50)` | `(27, 29.67, -60)` |
| `yaw180` | `(27, 29.67, -50)` | `(27, 29.67, -40)` |
| `yaw090` | `(27, 29.67, -50)` | `(37, 29.67, -50)` |
| `yaw270` | `(27, 29.67, -50)` | `(17, 29.67, -50)` |
| `foyer` | `(22, 22.17, 125.3)` | `(22, 22.17, 115.3)` |
| `saferoom` | `(22, 20.5+1.67, 128.4)` = `(22, 22.17, 128.4)` | `(22, 22.17, 118.4)` |
| `gate` | `(10, 24, 66)` | `(10, 25, 48)` |

`gate` exists in the table and is accepted by `W9_GRADE_POSES`, but the header's
pose list (`:24-25`) omits it. The commentary at `:46-49` gives the gate
provenance: authored tunnel `(10,20,100)->(10,22,88)`, sign plane z 48.35-49.02,
hero light `(10,26,49.8)`.

### 5.3 `build/qa/w9_capture.gd` — modes and poses

Dispatch (`build/qa/w9_capture.gd:389-395`):

- prep modes: `prep`, `prep_nosky`, `prep_noui`, `prep_noperiph`, `prep_ledge`,
  `prep_report` → `_prep()`; each saves `<tag>.png` at `:293`.
- mission modes: `upper_foyer`, `foyer`, `saferoom` → `_mission_interior()`;
  each saves `<tag>.png` at `:375`.
- `foyer_sweep` → four shots, `<tag>_yaw000.png`, `_yaw090`, `_yaw180`,
  `_yaw270` (`:353-369`).

Mission poses (`:328-341`):

| mode | eye | target |
|---|---|---|
| `upper_foyer` | `(27, 28+1.67, -50)` | `(27, 29.67, -60)` |
| `foyer` | `(22, 22.17, 125.3)` | `(22, 22.17, 115.3)` |
| `saferoom` | `(22, 20.5+1.67, 128.4)` | `(22, 22.17, 118.4)` |
| `foyer_sweep` | origin `(27, 28+1.67, -50)` | four yaws 0/90/180/270, aim `origin + (sin(yaw),0,-cos(yaw))*10` (`:353-364`) |

The camera is a new `Camera3D` with `fov = SHIPPED_FOV = 54.54`, `far = 4000`,
`keep_aspect = KEEP_HEIGHT` (`:23`, `:347-351`). `W9_CAPTURE_START` echoes
mode/tag/size/ao/prep-stage/out (`:383-387`); `W9_CAPTURE` prints
`file/size/err/mean601/pct_lt8/peak/nonblack/ao` (`:193-198`). The wrapper
`build/qa/w9_capture.sh` takes `<prep|upper_foyer|foyer|saferoom> [tag] [WxH]`
(`:5`, `:14-16`), writes captures to `build/qa/w9/captures` and logs to
`build/qa/w9/logs` (`:19-23`), defaults `TAT2_AO=on` (`:17`), aborts if another
Godot/game process is running (`:27-30`), and runs under
`flock /tmp/opencode/tat2-godot.lock` + `xvfb-run` (`:37-40`). The wrapper usage
string only advertises four modes; `foyer_sweep` and the prep diagnostics are
dispatched by the `.gd` (`w9_capture.gd:8-9`, `:389-395`) but not advertised by
the `.sh` (`w9_capture.sh:5`, `:14`).

### 5.4 `build/qa/w9_frame_stats.py` — usage and output

Usage (`build/qa/w9_frame_stats.py:18-24`):

```
/usr/bin/python3 build/qa/w9_frame_stats.py IMAGE [IMAGE ...] [--json] [--full]
```

- Method: ImageMagick `-colorspace gray -resize 480x -depth 8 gray:-`, 256-bin
  histogram (`:39-48`); Pillow `convert("L")` + LANCZOS is only the fallback
  when `magick`/`convert` is absent (`:51-59`). `--full` skips the 480 px
  downsample (`:101-105`).
- `%<8` is `sum(hist[:8])/total*100`, i.e. luma <= 7/255; this is the L1
  definition in the docstring (`:10-12`, `:89`).
- Default text output is one tab-separated line per image:
  `name.png  <samples>px  mean=..  p50=..  p95=..  lt8=..%  lt16=..%  gt200=..%`
  (`:114-120`).
- `--json` prints one JSON object per image with keys `file`, `method`,
  `samples`, `mean`, `p50`, `p95`, `pct_lt8`, `pct_lt16`, `pct_gt200`
  (`:82-92`, `:121-123`).
- No file is written; the table goes to stdout (`:24`).

### 5.5 Commands P1 actually used

The tracked P1 log directory does **not** contain grade logs; the grade logs are
in `/tmp/opencode/grade1.log` … `grade8.log`. The probe logs echo the parsed
axes (`W9_GRADE_START`) but not the shell command line. The wrapper logs do the
same (`W9_CAPTURE_START`).

Recorded wrapper evidence:

- `/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/logs/cap_p1_before_upper_foyer.log:27`:
  `W9_CAPTURE_START mode=upper_foyer tag=p1_before_upper_foyer size=(1920, 1080) ao=on out=.../captures`
- `/home/john/Projects/TAT-2-rem-w9-p1/build/qa/w9/logs/cap_p1_before_foyer_sweep.log:27`:
  `W9_CAPTURE_START mode=foyer_sweep tag=p1_before_foyer_sweep size=(1920, 1080) ao=on out=.../captures`

The corresponding wrapper invocation is fixed by `w9_capture.sh:37-40`:
`TAT2_AO=on build/qa/w9_capture.sh upper_foyer p1_before_upper_foyer 1920x1080`
and `TAT2_AO=on build/qa/w9_capture.sh foyer_sweep p1_before_foyer_sweep 1920x1080`
(reconstructed; the shell line itself is not logged).

Recorded grade axes:

- `grade8` (`/tmp/opencode/grade8.log:29`):
  `exposures=[1.15, 0.44] ambient_scales=[1.0] light_scales=[1.0] poses=["gate", "upper_foyer", "yaw180", "foyer"] fills=on ao=on`
- `grade7` (`/tmp/opencode/grade7.log:29`):
  `exposures=[0.75, 0.85, 1.0] ambient_scales=[1.0] light_scales=[1.0] poses=["gate", "upper_foyer", "yaw180", "foyer"] fills=on ao=on`
- `grade5` (`/tmp/opencode/grade5.log:29`):
  `exposures=[1.15, 0.44] ambient_scales=[1.0] poses=["gate"] fills=on ao=on`
- `grade4` (`/tmp/opencode/grade4.log:29`):
  `exposures=[0.44, 0.5] ambient_scales=[1.0] poses=["upper_foyer", "yaw180"] fills=off ao=on`; the log later prints `W9_GRADE fills freed=2` (`:509613`).
- `grade3` (`/tmp/opencode/grade3.log:29`):
  `exposures=[1.15, 0.44] ambient_scales=[1.0] poses=["upper_foyer", "yaw180", "foyer"] fills=on ao=on`.

A faithful reconstruction of the grade8 shell form (using the probe header
`:16-20` and the logged axes) is:

```bash
W9_GRADE_POSES="gate,upper_foyer,yaw180,foyer" \
W9_GRADE_EXPOSURES="1.15,0.44" \
W9_GRADE_AMBIENT_SCALES="1.0" \
W9_GRADE_LIGHT_SCALES="1.0" \
W9_GRADE_FILLS=on TAT2_AO=on \
flock /tmp/opencode/tat2-godot.lock -c \
 "xvfb-run -a -s '-screen 0 1920x1080x24' tools/godot --path game \
  --rendering-driver vulkan --script build/qa/w9_grade_probe.gd -- --tag=grade8"
```

This is reconstructed, not a transcription of a stored command.

---

## 6. Geometry from the pose table

Distances are 3D Euclidean metres. Fill positions are from HEAD `b13260b`
`mission_controller.gd:567-570`, `:550`, `:304`, `:317`, `:331`, `:352-353`,
`:383-384`; eye points are from `build/qa/w9_grade_probe.gd:43-53`.

### 6.1 Distance matrix (metres; `YES` = inside that light's own range)

| fill | range | `upper_foyer` / `yaw180` eye `(27,29.67,-50)` | `gate` eye `(10,24,66)` | `foyer` eye `(22,22.17,125.3)` | `saferoom` eye `(22,22.17,128.4)` |
|---|---:|---:|---:|---:|---:|
| `GuildhallFoyerFill_-53` | 16 | **3.282 YES** | 120.412 no | 178.589 no | 181.684 no |
| `GuildhallFoyerFill_-64` | 16 | **14.063 YES** | 131.294 no | 189.572 no | 192.667 no |
| `GuildhallSafeRoomFill` | 12 | 109.661 no | 136.949 no | 167.481 no | **169.904 no** |
| `GuildhallGateLampFill` | 12 | 142.999 no | 26.062 no | 34.926 no | 37.893 no |
| `GuildhallFenceLampFill` | 16 | 97.530 no | 20.224 no | 80.348 no | 83.409 no |
| `GuildhallOrnateGateFill` | 11 | 86.755 no | 84.971 no | 121.992 no | 124.727 no |
| `GuildhallRoadFillL` | 8 | 103.992 no | 14.346 no | 74.521 no | 77.572 no |
| `GuildhallRoadFillR` | 8 | 103.533 no | 14.346 no | 74.069 no | 77.138 no |
| `GuildhallCarHeadlightL` | 16 (spot) | 116.578 no | **8.813 YES** | 59.677 no | 62.768 no |
| `GuildhallCarHeadlightR` | 16 (spot) | 117.773 no | **8.940 YES** | 58.465 no | 61.556 no |

### 6.2 Conclusions

- **A 16 m omni cannot reach the gate pose.** The gate eye is at z = 66; the
  foyer fills are at z = -53 and -64, i.e. 119 m and 130 m away in z alone.
  Full distances are **120.412 m** and **131.294 m**, 7.5× and 8.2× the 16 m
  range. They also cannot reach the `gate` subject at the hero light point
  `(10, 26, 49.8)`: the same fills are 104.3 m and 115.3 m from that point.
- **The two fills can only reach the `upper_foyer` / `yaw180` pose** among the
  four measured eye points. That pose is the only one in the matrix where the
  foyer fills are inside range; `yaw180` shares the same eye.
- **They cannot reach the `foyer` pose** (`178.589` / `189.572` m) or the
  `saferoom` pose (`181.684` / `192.667` m). The P1 `foyer` and `saferoom`
  measurements are therefore not caused by these two fills.
- The `GuildhallSafeRoomFill` at `(127, 29, -5)` is **169.904 m** from the pose
  named `saferoom` at `(22, 22.17, 128.4)`, so it does not light that capture.
  The code comment gives the safe-room spawn as `(127.27, 26.47, -5.33)`
  (`mission_controller.gd:541-544`); `game/tests/run_tests.gd:982` uses
  `(127.2747, 25.4694, -5.3296)` for the same PeripheryA spawn check. The fill
  at `(127, 29, -5)` sits in that room. The pose named `saferoom` is instead at
  the `(22, ..., 128.4)` door coordinates used by
  `build/qa/capture_guildhall_door.gd:43-49`.
- At the `gate` eye, among the port fills in §2, only the two car headlight
  spots are within their own 16 m range (8.813 / 8.940 m). They are **not**
  registered with `light_probe` (`:372-373`), and their aim is down-street at
  `(11, 18.6, 54)` and `(9, 18.6, 57)`, not at the eye.
- The light_probe visibility model uses only `spot_range`, not the spot cone
  (`light_probe.gd:208-214`); therefore the car spots' cone/aim would not matter
  to stealth even if they were registered — but they are not registered, so
  they contribute zero to `GameState.player_light_visibility`.
- At the actual player sample point `(27, 28.9, -50)` (feet + 0.9 m), the two
  foyer fills are **3.662 m** and **14.156 m** away, still inside 16 m. The P1
  report's quoted 3.3 / 14.1 m are camera-eye distances.

---

## 7. Tests that pin the fills or the Guildhall grade

### 7.1 Suite 98 — `git show b13260b:game/tests/run_tests.gd:7414-7496`

The suite comment (`:7414-7427`) is:

```gdscript
# 98. W9-P1-A4 night-grade guard (investigation outcome, NO code change made).
# The Guildhall's single `gloomy` environment cannot grade both of its rooms.
# Measured at 1920x1080 Vulkan through build/qa/w9_frame_stats.py (PNGs under
# build/qa/w9/captures/): the interior foyer is ~2x too bright against KF27
# (upper_foyer p50 34 vs 15; foyer_sweep_yaw180 p50 31 vs 15) while the gate
# approach is already BELOW its KF16/KF18 reference (p50 10 vs 26) and loses
# black floor for every step of exposure removed (gate %<8: 23.9 at 1.15 ->
# 38.0 at 1.00 -> 51.9 at 0.85 -> 62.2 at 0.75). A global exposure/ambient
# cut is therefore a regression, and the interior band is BLOCKED-ON P2: the
# two shadowless foyer fills (mission_controller.gd:564-580, 1.6 at 3.3 m and
# 1.3 at 14.1 m from the upper-foyer eye) dominate that pose -- freeing them
# moves upper_foyer mean 28.8 -> 22.7 and %<8 8.0 -> 32.2 at one exposure.
# This suite pins today's contract and fails if the night grade is lowered
# globally without a room-scoped lever landing first.
```

The code then asserts only preset-level values:

- `var w9_floor: float = float(w9_wp.NIGHT_EXPOSURE)` (`:7433`).
- `const W9_NIGHT_FLOOR_REFERENCE: float = 1.15` (`:7439`);
  `if w9_floor < W9_NIGHT_FLOOR_REFERENCE - 0.0001` fails (`:7440-7441`).
- Guildhall must apply AGX: `e_gh.tonemap_mode != Environment.TONE_MAPPER_AGX`
  fails (`:7447-7448`).
- Guildhall applied exposure must equal `1.15`:
  `if not is_equal_approx(e_gh.tonemap_exposure, W9_NIGHT_FLOOR_REFERENCE)`
  (`:7449-7450`).
- Guildhall ambient must equal `0.16`:
  `if not is_equal_approx(e_gh.ambient_light_energy, 0.16)` (`:7451-7452`).
- Lobby night preset exposure must equal `1.15` (`:7454-7459`).
- Den exposure must equal `maxf(1.0 + bias, W9_NIGHT_FLOOR_REFERENCE)`
  (`:7462-7469`).
- `old_manor` must not be a night preset (`:7471-7472`).
- Exactly one shipped map may resolve to `gloomy`, and it must be `guildhall`
  (`:7473-7487`).
- Pass line (`:7496`):
  `PASS: 98 W9-P1-A4 night-grade guard (guildhall keeps AGX %.2f / ambient 0.16, lobby floor held, Den bias+floor held, old_manor ungraded, gloomy preset is one-map scoped)`.

### 7.2 Does reducing the fills trip suite 98?

**No.** Suite 98 never reads the mission tree, never looks up
`GuildhallFoyerFill`, and never asserts a fill energy or count. Its only
Guildhall constants are the preset exposure `1.15` and ambient `0.16`; the fill
energies are not in `weather_profile.gd` and do not change those values.

A `grep` restricted to `game/` and `build/qa/*.gd` for `GuildhallFoyerFill`
finds only:

- the creator `game/src/missions/mission_controller.gd:572` (HEAD);
- the review-mode mirror `game/addons/tat2_review/review_environment.gd:115-116`;
- the probe `build/qa/w9_grade_probe.gd:143`, `:162` (B1 snapshot).

No file under `game/tests/` contains `GuildhallFoyerFill`. The fill-energy
tests that do exist are Den-only: `run_tests.gd:3069-3106` sums the
`den_hand_fills` group and fails if the sum is `> 2.01`;
`test_w6u1_briefing.gd:277-292` checks the Den poster/wisp fills; and
`game/tests/e2e/e2e_tier1_features.gd:152-170` checks the same Den group. None
of these reads a Guildhall fill.

Other related tests, none of which pin foyer fill energy:

- `run_tests.gd:325-454` (suite 10) loads the Guildhall and asserts
  `gh_spawn_lights >= 1` within 20 m of the **safe-room spawn**
  (`:357-370`, `:450`) plus the authored contract-2 safe-room spot
  (aim -Z, 88°) at `(126.2758, 27.1426, -2.4736)` (`:371-376`). The foyer fills
  are ~110 m from that spawn and are not counted; the safe-room fill and the
  authored spot are both present, so reducing foyer fill energy cannot trip it.
- `game/tests/probe_render_t07.gd:289-319` pins authored light records (914),
  full budget spend, room coverage, the six gate lights, the safe-room spot and
  six hero shadows. It does not read hand fills; reducing filler energy does not
  change the authored selection.
- `game/tests/probe_render_t07.gd:332-396` pins the Guildhall grade
  (`AGX`, `exposure >= NIGHT_EXPOSURE`, `ambient 0.16`, fog, moon angle, SSIL,
  stage hand-off). It does not pin fills.

Concurrent, uncommitted test: suite 100
(`game/tests/run_tests.gd:7523-7560`, dirty tree) pins the dirty
`mission_controller.gd` room-grade helper (`0.452` at `upper_foyer`, `1.0` at
gate/lower/saferoom/Den) and the 1.15 preset. It is not in HEAD `b13260b` and is
not evaluated by this fact sheet.

One discrepancy inside suite 98: its comment says the gate `%<8` ladder continues
`51.9` at 0.85 and `62.2` at 0.75 (`run_tests.gd:7420-7421`), while the P1
report and the measured PNGs are `51.8` and `59.6` (`p1-report.md:56-57` and
the `grade7_gate_e085/e075` stats above). The `62.2` has no matching P1 frame.

---

## 8. `weather_profile.gd` vs `c2a1cd8`; shipped Guildhall grade constants

### 8.1 Byte identity

```
$ git diff c2a1cd8 -- game/src/core/weather_profile.gd | wc -l
0
$ git hash-object game/src/core/weather_profile.gd
5fc0213534c3e853ad95ddd67cb37c6f9ae0693d
$ git rev-parse c2a1cd8:game/src/core/weather_profile.gd
5fc0213534c3e853ad95ddd67cb37c6f9ae0693d
```

`git merge-base --is-ancestor c2a1cd8 HEAD` exits 0; `b13260b` is a descendant
of the W9-P0 base used by P1. P1 report `:64` also states the file is
byte-identical to `c2a1cd8`.

### 8.2 Shipped constants and application

- `const NIGHT_EXPOSURE := 1.15` — `game/src/core/weather_profile.gd:121`.
  The comment block at `:113-120` records why it applies to every authored night
  preset (`gloomy`, `midnight_clear*`) via `is_night_preset()`.
- `const AMBIENT_ENERGY_MIN := 0.05`, `AMBIENT_ENERGY_MAX := 0.35` — `:104-105`.
- `const AMBIENT_UE_TO_GODOT := 0.08` — `:112`.
- `ambient_energy(preset)` reads `preset.sky.intensity` and returns
  `clampf(raw * 0.08, 0.05, 0.35)` — `:682-686`.
- The Guildhall preset is `gloomy`; its generated JSON has
  `"sky": { "intensity": 2.0, ... }` at
  `game/data/generated/weather/gloomy.json:27-61`, intensity line `:54`, and
  `"auto_exposure_bias": 0.0` at `:107`. `2.0 * 0.08 = 0.16`, the ambient suite
  98 pins.
- `apply_environment()` applies the ambient at `:965-968` and, for a night
  preset, sets `tonemap_mode = AGX` and
  `env.tonemap_exposure = maxf(env.tonemap_exposure, NIGHT_EXPOSURE)` at
  `:998-1000`; the evidence line prints `TAT-2 exposure: preset=%s mode=AGX
  exposure=%.3f ...` at `:1003-1009`.
- `stage_grade_values(preset)` returns
  `tonemap_exposure = NIGHT_EXPOSURE if night else 1.0`, the computed ambient
  (0.16 for `gloomy`) and the preset glow at `:579-590`.

The P1 `grade7` log's `exposure=0.440 ... interior=true`
(`/tmp/opencode/grade7.log:33`) is a transient interior branch that P1 reports
as implemented, measured and reverted (`p1-report.md:330-332`); the shipped
`grade8` load prints `exposure=1.150` without `interior=true`
(`/tmp/opencode/grade8.log:33`), matching the current byte-identical file.

---

## 9. What is still unknown / unverified

1. **Exact grade shell command lines.** P1's `build/qa/w9/logs/` contains no
   grade logs; `/tmp/opencode/grade*.log` records `W9_GRADE_START` axes but not
   the shell command. The reconstructed grade8 line in §5.5 is derived from the
   probe header and the logged axes, not transcribed.
2. **Single-fill contribution.** P1 only freed **both** foyer fills together
   (`grade4`, `W9_GRADE_FILLS=off`) at 0.44 / 0.50. There is no measurement of
   `-53` alone, `-64` alone, or any fill-energy bracket at **1.15**.
3. **Fill-only calibration at 1.15.** The only fills-off data is at 0.44, where
   the room overshoots the other way (`upper_foyer` p50 9, `%<8` 32.2, outside
   the 13-15 / 9-24 band; `audit-a4.md:290-294`). Whether an energy scale below
   1.0 at 1.15 lands in band is unmeasured.
4. **The `saferoom` pose's location.** The pose named `saferoom` is at
   `(22, 22.17, 128.4)`, 169.904 m from `GuildhallSafeRoomFill` at
   `(127, 29, -5)`; it matches the door coordinates in
   `build/qa/capture_guildhall_door.gd:43-49`, not the authored safe-room spawn.
   No source states whether the name or the coordinate is wrong.
5. **The `foyer` pose's attribution.** The `foyer` pose is 178.6 / 189.6 m from
   the foyer fills, so those fills cannot cause its 1.15 brightness
   (31.5 / 32 / 58 / 1.3). P1 does not attribute that pose's excess to any
   specific light.
6. **Whether the gate pose is visually affected by the car spots.** The spots
   are within 8.8 / 8.9 m of the gate eye, but they are aimed down-street and
   are unregistered; P1's gate A/B did not isolate them.
7. **The `9-24` target's provenance.** T07 only says `~10-25`; `9-24` first
   appears in the P0 report and is repeated by P1. No measured reference frame
   producing exactly 9-24 is cited.
8. **Commit status of the fill-scale axis.** The uncommitted B1 probe snapshot
   adds `W9_GRADE_FILL_SCALES` and `W9_GRADE_FILL_RANGE_SCALES`; at HEAD
   `b13260b` those variables do not exist. The later concurrent edit also adds
   `W9_GRADE_FILLS=near|far` and changes the nofill suffix to `_nofill_<mode>`;
   see §0.1. None of this is committed here.
9. **The probe's `W9_GRADE_LIGHT_SCALES` axis is unmeasured.** Its own comment
   says only exposure/ambient were captured and the light-scale axis “is wired
   but unmeasured, so it must not be quoted” (`w9_grade_probe.gd:181-185`).

---

## 10. Calibrator command — bracket fill energy at exposure 1.15 on `upper_foyer,yaw180,gate`

The bracket uses the uncommitted B1 fill-scale probe snapshot (at HEAD
`b13260b` the only fill lever is `W9_GRADE_FILLS=off`; the later concurrent edit
keeps the same fill-scale axes and adds near/far modes). It keeps the preset
grade at its shipped 1.15 / 0.16, fixes authored-light and ambient scales at
1.0, and brackets the two foyer fills' energy. It produces 3 poses × 5 fill
energies × 1 exposure = **15** PNGs named
`build/qa/w9/captures/b1fill_<pose>_e115_a100_l100_f<NNN>_r100.png`; `_f000`
means energy 0, not a freed node. Read them with:

```bash
python3 build/qa/w9_frame_stats.py build/qa/w9/captures/b1fill_*.png
```

For a true node-free control at 1.15, run the same command with
`W9_GRADE_FILLS=off` and no `W9_GRADE_FILL_SCALES`; that produces the `_nofill`
frames (the later concurrent edit names them `_nofill_both`). Do not combine
`W9_GRADE_FILLS=off` with nonzero fill scales: the nodes are gone before
`_foyer_fill_base()` runs (`w9_grade_probe.gd:267-272`), so the fill count will
be 0.

```bash
cd /home/john/Projects/TAT-2-rem-w9-p2 && \
W9_GRADE_POSES="upper_foyer,yaw180,gate" \
W9_GRADE_EXPOSURES="1.15" \
W9_GRADE_AMBIENT_SCALES="1.0" \
W9_GRADE_LIGHT_SCALES="1.0" \
W9_GRADE_FILL_SCALES="0.0,0.25,0.5,0.75,1.0" \
W9_GRADE_FILL_RANGE_SCALES="1.0" \
W9_GRADE_FILLS=on TAT2_AO=on \
flock /tmp/opencode/tat2-godot.lock -c \
 "xvfb-run -a -s '-screen 0 1920x1080x24' tools/godot --path game \
  --rendering-driver vulkan --script build/qa/w9_grade_probe.gd -- --tag=b1fill"
```
