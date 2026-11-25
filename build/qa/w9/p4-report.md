# W9-P4 — StateTree runtime (report)

Phase lead: W9-P4. Worktree `/home/john/Projects/TAT-2-rem-w9-p4`, branch
`rem/w9-p4`, base `f1bf058` (W9-P3 merged; compile 176/0). **Nothing pushed,
merged or rebased.**

Every Godot invocation ran under `flock /tmp/opencode/tat2-godot.lock`, serially,
one process at a time. No producer was run; `game/data/generated/` and
`extracted/` were never written. One `tools/**` line was removed and is disclosed
in §8. No capture was needed: every number here is a headless measurement or a
source/data quote.

Commits: one coherent commit on `rem/w9-p4` (the runtime, the guard hook, the two
suites, the allowlist bookkeeping) plus one evidence commit (this report, the
three lane notes and the two audits).

## 0. Headline — the two numbers that decide S2

**Coverage** (measured from `guard_behavior.json` × the guard binding, §W9-P4-4):

| | classes | instances | covered | `parameter_blind` |
|---|---:|---:|---:|---:|
| tasks | 77 | 326 | **113 (34.7 %)** | 94 |
| conditions | 36 | 233 | **35 (15.0 %)** | 32 |
| **trees fully evaluable** | 21 | — | **0** | — |

`implemented 0 / mapped-to-port 18 / unsupported 59` task classes and
`implemented 0 / mapped-to-port 6 / unsupported 30` condition classes. **Zero
classes are `implemented`** in the strict sense (driven from fields the payload
carries): every mapped class is a port observation, and 94 of its 113 covered
task instances and 32 of its 35 covered condition instances are
`parameter_blind`.

**Side-effect proof:** the same arena, same frame count, run once with
`TAT2_STATETREE=off` and once with `=shadow`: **signature identical**
(`sig=-5750684789768048477` both; position `1.382652,-0.049066,3.357109`, yaw,
alertness 0, detection `0.000000`, `wp_index` 2, dwell timer, `ever_spotted`
false). The shadow run ticked **241** frames, wrote **70** trace rows and reached
`ST_Patrol`. Detail in §W9-P4-3.

**S2 decision: BLOCKED-ON T01, not attempted.** 0 of 21 trees can be fully
evaluated: the payload carries no node parameters at all, while the raw dump
carries 260/326 task and 209/233 condition parameter structs
([`p4-t01-contract.md`](p4-t01-contract.md)). A cutover driven by state-name
inferences would be invented behaviour, which the brief forbids. The shadow trace
already reproduces the authored patrol **order** against the FSM's real waypoints
(§W9-P4-6), so the remaining work is a producer pass, not an interpreter change.

---

### W9-P4-1 — parse and validate all 21 authored StateTrees
- **investigate:** `game/data/generated/gameplay/guard_behavior.json` (784 KB,
  schema `tat2.guard_behavior/1`) is written by `tools/parse_state_tree.py` from
  `extracted/json/AI/StateTrees/**` and had **no reader**:
  `git grep -c "guard_behavior" f1bf058 -- game/src game/tests` → no output
  (0 hits). `game/src/ai/guard_ai.gd` is a 6-state FSM
  (`enum Alertness` at :5) and `game/src/ai/civilian_npc.gd` a wander loop.
- **research:** [`p4-facts-data.md`](p4-facts-data.md) (exact payload shape,
  16-key state / 9-key transition records, raw-vs-payload omission table) and
  [`p4-re-statetree.md`](p4-re-statetree.md) §0/§6 (census, the four-hop
  parameter chain). Cited in the model header.
- **the dump is a property dump, not a compiled tree.** It is a flattened state
  list: per state `index/name/depth/type/parent/children/children_range/tasks/
  enter_conditions/utility/transitions/linked_asset/linked_state_index/enabled/
  selection_behavior`; per transition `index/trigger/priority/required_event/
  to_kind/to_state/to_state_index/conditions/enabled`. `children_range` is the
  raw pre-order span, not the direct child list — they differ on **52 states**.
- **measured inventory** (suite 110 asserts every per-tree count against the
  payload's own `stats`, 9 keys × 21 trees):

| tree | states | transitions | groups | linked | disabled | depth | tasks | conds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `ST_Guard` | 126 | 148 | 9 | 17 | 1 | 7 | 27 | 15 |
| `ST_Civilian` | 73 | 82 | 8 | 10 | 2 | 4 | 20 | 9 |
| `ST_Subtree_Combat` | 52 | 57 | 4 | 4 | 1 | 6 | 20 | 16 |
| `ST_Subtree_Flee` | 32 | 26 | 6 | 0 | 0 | 6 | 21 | 7 |
| `ST_Patrol` | 23 | 22 | 2 | 0 | 0 | 4 | 14 | 4 |
| `ST_Subtree_GeneralInvestigateStim` | 23 | 26 | 1 | 0 | 0 | 3 | 10 | 1 |
| `ST_Subtree_Combat_Hauntstable` | 22 | 21 | 0 | 2 | 0 | 5 | 14 | 9 |
| `ST_InvestigateStims_Guard` | 17 | 22 | 0 | 6 | 0 | 3 | 7 | 4 |
| `ST_TriggerFlee_Civilian` | 17 | 5 | 3 | 0 | 3 | 3 | 9 | 2 |
| `ST_Subtree_ReviveNPC` | 16 | 15 | 0 | 2 | 0 | 2 | 10 | 2 |
| `ST_Subtree_Lockdown` | 13 | 12 | 0 | 1 | 0 | 4 | 8 | 0 |
| `ST_ClueGiving` | 9 | 4 | 2 | 0 | 0 | 3 | 7 | 3 |
| `ST_InvestigateStims_Civilian` | 6 | 3 | 0 | 3 | 0 | 1 | 2 | 4 |
| `ST_Standby_Guards` | 4 | 4 | 0 | 0 | 0 | 1 | 4 | 0 |
| `ST_Subtree_Combat_ActivateAttack` | 4 | 4 | 0 | 0 | 0 | 1 | 4 | 2 |
| `ST_Subtree_IntruderNoLongerSuspicious` | 4 | 3 | 0 | 0 | 0 | 1 | 3 | 0 |
| `ST_Subtree_SpottedIntruderReaction` | 4 | 3 | 0 | 0 | 0 | 1 | 3 | 0 |
| `ST_Subtree_SpottedIntruderReaction_Hauntstable` | 4 | 3 | 0 | 0 | 0 | 1 | 3 | 0 |
| `ST_Subtree_TryActivateAlarm` | 4 | 3 | 0 | 0 | 0 | 2 | 2 | 0 |
| `ST_OffNavLink` | 3 | 2 | 0 | 0 | 0 | 1 | 2 | 0 |
| `ST_SmartObject_DefensiveSpot` | 3 | 2 | 0 | 0 | 0 | 1 | 2 | 0 |
| **total** | **459** | **467** | 35 | 45 | 7 | 8 | 77 | 36 |

  Value domains: state types `State 376 / Group 35 / LinkedAsset 45 / Linked 2 /
  Subtree 1`; selection `TrySelectChildrenInOrder 439 / TryEnterState 20` (all 20
  are leaves, so the two behaviours are equivalent here); triggers
  `OnStateCompleted 284 / OnEvent 89 / OnStateSucceeded 38 / OnStateFailed 36 /
  OnTick 20`; priorities `None 358 / Normal 67 / Medium 21 / Critical 12 /
  High 9`; targets `state 417 / Succeeded 35 / Next 15`; **7 disabled states, 1
  disabled transition, 0 utility considerations**; the payload has no transition
  `delay`/`fallback`/`consume_event` key at all (the raw dump authors 0 of 467
  non-zero delays).
- **composition, kept apart:** 45 `LinkedAsset` states name another asset and
  always run its `Root` (`linked_state_index` null on all 45); 2 `Linked` states
  (both in `ST_InvestigateStims_Guard`) point at a **second root inside the same
  asset** (index 8, type `Subtree`) — that tree is the only one with two roots.
- **what the payload omits (the honest ceiling):**

| omitted field | authored / recoverable from the raw dump | effect on a runtime |
|---|---|---|
| task parameters | **260 of 326** instances | which alertness, which delay, which target |
| enter / transition condition parameters | **209 of 233** instances | which bool, which tag, which distance, which patrol type |
| `Transitions[].Fallback` | 39 `NextSelectableSibling`, 428 `None` | the "if/else" idiom of this AI |
| `Transitions[].Delay` | 0 of 467 non-zero (inert today) | no observable loss today, but the field is absent |
| `bConsumeEventOnSelect` | false on 2 states | event re-use in one tick |
| `States[].RequiredEventToEnter` | 3 states (`ST_Patrol[21]`, `ST_Subtree_Combat[6]`, `ST_InvestigateStims_Guard[6]`) | those states can be entered without their gate event |
| state / asset parameter values | 93 states carry a schema only | per-state configuration |
| node UClass | 139 Blueprint nodes carry `TaskClass`/`ConditionClass` | `class` identity; **display names are not unique** (12 classes share two names; `Run Env Query` is two classes) |

  The chain is proven in [`p4-re-statetree.md`](p4-re-statetree.md) §6 and
  [`p4-facts-data.md`](p4-facts-data.md) §3:
  `Nodes.Structs[k].InstanceTemplateIndex` selects the instance struct named by
  `InstanceDataHandle.Source`; it is **not** `InstanceDataHandle.Index` (they
  differ on 300 of 566 nodes). The producer contract that closes this is
  [`p4-t01-contract.md`](p4-t01-contract.md) — **BLOCKED-ON T01**.
- **fix:** new `game/src/ai/statetree/tree_model.gd` — load/parse/validate, all
  indices bounds-checked, every `LinkedAsset` target resolved, every
  trigger/priority/to_kind validated, `errors`/`warnings` per tree.
- **test:** `W9P4_STATETREE_SUMMARY: fails=0 checks=58`;
  `P4LIB trees=21 states=459 transitions=467 task_classes=77
  condition_classes=36 linked_asset=45 local_links=2`.
- **verdict: FIXED.** The payload parses and validates 21/21. What it cannot
  supply is listed above and is not invented anywhere.

---

### W9-P4-2 — the generic interpreter (selector / task / transition / observer)
- **investigate:** the FSM's decisions are `_physics_process` heuristics
  (`guard_ai.gd:1444-1546`) with invented timers (6 s ALERTED, 5 s SUSPICIOUS,
  6 s SEARCH); the authored graph is never consulted.
- **research:** [`p4-re-statetree.md`](p4-re-statetree.md) §1-§5: selection
  semantics, `EStateTreeRunStatus`, transition arbitration (`EStateTreeTransitionPriority`
  order `None<Low<Normal<Medium<High<Critical`), `OnStateCompleted` = success OR
  failure, `Succeeded`/`Next` handles, `Fallback`, observers (`OnTick` 20) and
  events. Every rule is labelled PROVEN / INFERENCE-FROM-DOCS in that file.
- **fix:** `engine-neutral` runtime under `game/src/ai/statetree/`:

| file | role |
|---|---|
| `tree_model.gd` | payload → one dictionary per tree (above) |
| `interpreter.gd` | active **frame stack** (a `LinkedAsset` runs another asset without flattening the two), enter conditions, `TrySelectChildrenInOrder` selection with rollback, task lifecycle, status propagation, transition arbitration with priority + delay, `Succeeded`/`Next`, event queue, `OnTick` observers |
| `bindings.gd` | the gameplay-agnostic surface (`condition_state`, `task_enter/tick/exit`, `event_matches`, `declaration`, `covers`, `mutates`); default UNKNOWN/UNSUPPORTED |
| `guard_bindings.gd` | the port's read-only observation map for guards (`mutates() == false`) |
| `coverage.gd` | the measured table |
| `trace.gd` | event-only structured trace (ring buffer + optional NDJSON) |
| `shadow_runner.gd` | one interpreter per guard, the mode flag, the 21-tree harness |

  Rules encoded (each with its evidence in the RE file):
  * priority order — **Normal is weaker than Medium**; a swapped table silently
    re-ranks 21 authored `Medium` transitions (suite 110 pins `Medium > Normal`);
  * all active states are candidate sources, leaf first; highest priority wins,
    ties to the deepest state, then authored array order;
  * `OnStateCompleted` fires on success **or** failure; `OnStateSucceeded` /
    `OnStateFailed` are the discriminated forms;
  * a candidate whose target cannot be selected is **skipped** and the next
    candidate is considered (proven by `ST_Subtree_Combat_ActivateAttack[3]`);
  * a state with children that cannot select any child is **not selected**
    (Epic's selection docs): the entry is rolled back and the parent tries its
    next sibling;
  * a no-task state has finished its own work on entry (how a Group waits and
    how a no-task leaf completes at once);
  * a parent does not inherit a child's completion before the child's own
    completion transitions are consumed.

  Port decisions (no UE reference; stated, not hidden): UNKNOWN is treated like
  FALSE for selection and transition conditions and every UNKNOWN is counted;
  an unsupported task marks its frame `UNSET` (that frame can never complete)
  but its already-selected child keeps running so the reachable sub-graph stays
  observable.
- **test:** five synthetic trees in suite 110 drive selector → task lifecycle →
  `OnStateCompleted` switch, `OnTick` observer, `OnEvent`, transition delay,
  `Succeeded` handle, UNKNOWN-enter fall-through, and `Medium` vs `Normal`
  priority. Five corrupt payloads are rejected (child out of range, missing
  transition target, `OnEvent` without an event, unknown trigger, unresolvable
  link) and the clean payload is accepted.
- **verdict: FIXED** for the generic runtime. Gameplay-node coverage is
  §W9-P4-4 and is not claimed beyond the table.

---

### W9-P4-3 — shadow mode and the side-effect proof
- **investigate:** no existing hook could run a second behaviour model; the guard
  has one `_physics_process` and no read-only accessor for its dwell timer
  (`_patrol_wait_left` is private).
- **fix:** `TAT2_STATETREE=off|shadow|patrol` (default `off`, read once per
  process; unknown degrades to `off` with one warning). `guard_ai._ready()`
  attaches a runner after the patrol data exists; `_physics_process` (and the KO
  branch) calls `tick(delta)` behind a single null check. One new read-only
  accessor, `patrol_wait_remaining()`, so the binding never touches a private
  field. `cleanup_static_caches()` releases the library and the trace.
  `patrol` is recognised and reserved for S2; today it behaves like `shadow` and
  says so once.
- **trace:** event-only rows (`start`, `enter`, `exit`, `transition`,
  `transition_armed`, `transition_unmet` with each candidate's unmet conditions
  and `unavailable` targets, `fallback`, `task_enter`, `task_succeeded`,
  `task_block`, `condition_unknown`, `block`, `linked_refused`, `stall`), each
  carrying tree, tick, time, state, path and guard id.
  `TAT2_STATETREE_TRACE=/abs/path.ndjson` streams them (flush every 64 rows).
- **confirm (red):** before the hook, `git grep -c "TAT2_STATETREE" f1bf058 --
  game/src` → 0 hits.
- **test:** `test_w9p4_shadow.gd` (suite 111) runs one process with two phases on
  the same arena — a live guard on a live physics floor, a 4-point patrol path
  with authored waits and facing, 240 physics frames each — and hashes position
  (6 dp), yaw, alertness, detection, `wp_index` and the dwell timer per frame.
- **confirm (green):**
  ```
  SHADOW_PHASE mode=off    sig=-5750684789768048477 pos=1.382652,-0.049066,3.357109 state=0 detection=0.000000 wp=2 ever=false rows=0 ticks=0 transitions=0 trees=
  SHADOW_PHASE mode=shadow sig=-5750684789768048477 pos=1.382652,-0.049066,3.357109 state=0 detection=0.000000 wp=2 ever=false rows=70 ticks=241 transitions=6 visited=16 trees=ST_Guard,ST_Patrol reached_patrol=true
  W9P4_SHADOW_SUMMARY: fails=0 checks=20
  ```
  Read honestly: the no-player arena means `detection` is `0.000000` in both
  runs, so the *detection* half is an equality of zeros, not a ramp that ran.
  What it establishes is that 241 shadow ticks, 70 trace rows, 6 transitions and
  16 distinct states — including the `ST_Patrol` link — change nothing the FSM
  owns. A detection-ramp variant is S3 work (§9) because it needs a player stub
  with the full damage/pose surface, which this lane did not add.
- **coverage of the 21 trees:** `shadow_runner.trace_all_trees()` starts every
  tree once with the base binding and records at least a start, an enter and the
  block that stopped it — `P4TREES started=21 blocked=0 rows=140 trees=21`.
- **a real mission, shadow on:** `TAT2_STATETREE=shadow
  TAT2_STATETREE_TRACE=/tmp/opencode/p4_mission.ndjson build/qa/runtime_smoke.sh
  90` → `RUNTIME_SMOKE PASS`, 0 script/shader errors, `mission_ready=1`.
  The trace has **220 rows from 4 guards** (`Guard_1`, `Guard_3`,
  `Guard_ClubLantern_0`, `Guard_ClubLantern_2`; free-play spawns 4 at this
  difficulty), ticks 0..3622, trees `ST_Guard` + `ST_Patrol`, 17 transitions,
  12 `transition_unmet`, 11 fallbacks, 4 `task_block` (the unsupported
  `STT Distraction Smart Objects`) and 4 conditions the payload cannot evaluate
  (`Bool Compare`). All four guards reached `ST_Patrol`.
  Two of the four (`Guard_1`, `Guard_ClubLantern_0`) sat in `Move To Point` for
  the rest of the 60 s window; the port has no navmesh (RE-I-06/RE-I-10), so this
  is consistent with a guard blocked by geometry — exactly the divergence the
  trace exists to surface. It is **not diagnosed further**: the trace has no
  per-guard position series. The other two reached `Delay` with a >20 s authored
  dwell. The final NDJSON line is truncated because `timeout` SIGTERMs the
  engine, which is expected.
- **verdict: FIXED** for side-effect freedom and trace coverage; the runtime cost
  is **not verified** (the flag is off by default and no capture/perf run was
  permitted for this lane).

---

### W9-P4-4 — the coverage table, measured not asserted
- **investigate:** no existing artefact counted node coverage; the producer's
  `PORT_COVERAGE` is a curated prose table that omits `React to Damage` and
  `React to Player Tool` (RE-I-15.4).
- **fix:** `coverage.gd` walks every authored instance and asks the binding two
  questions — the class declaration (`implemented` / `mapped-to-port` /
  `unsupported`) and the per-instance predicate `covers(kind, name, tree,
  state)` — so the table is recomputed on every run and a new binding or a
  producer change moves it. `guard_bindings.gd` narrows each class to the
  instances the port can actually drive (e.g. `Move To` covers only the
  `ST_Patrol` move states; `Delay Task` only the two patrol dwell states).
- **result:**

| | implemented | mapped-to-port | unsupported | instances | covered | blind |
|---|---:|---:|---:|---:|---:|---:|
| tasks | 0 | 18 | 59 | 326 | 113 | 94 |
| conditions | 0 | 6 | 30 | 233 | 35 | 32 |

  **0 of 21 trees** have every task and condition instance covered
  (`P4COVERAGE fully_covered_trees=0`). The full 113-row table is Appendix A;
  every row has a note saying which port fact answered it and, when
  `parameter_blind`, that the authored value is absent.
- **why `implemented` is zero:** every node's behaviour depends on an authored
  parameter the payload does not carry. The nearest thing to an `implemented`
  class is a transition's trigger/priority mechanics, which are graph fields and
  not counted here.
- **verdict: FIXED (the table).** The number it reports is the honest ceiling and
  is the input to the S2 decision below.

---

### W9-P4-5 — tests
- **suite 110** `test_w9p4_statetree.gd` — **58 checks, 0 fails**:
  21/21 parse + per-tree count equality vs `stats`; 459/467/45/2 measured; five
  corruptions rejected; five synthetic trees for the interpreter paths; the
  coverage table covers every class and instance with valid statuses/notes and
  `covered <= instances`; 21/21 structural traces.
- **suite 111** `test_w9p4_shadow.gd` — **20 checks, 0 fails**: the off/shadow
  signature equality, the shadow-liveness assertions, the shipping env-switch
  parse (`off`/`shadow`/`patrol`/unknown→off) through `OS.set_environment`.
- `probe_statetree_shadow.gd` is the evidence probe for §W9-P4-6 (not a gate).
- **verdict: FIXED.**

---

### W9-P4-6 — S2 patrol cutover: decision and readiness
- **investigate:** the FSM's patrol is
  `guard_ai._patrol_service_waypoint` (:1775) / `_patrol_wait_for` (:1801) /
  `_apply_patrol_yaw` (:1810) / `_advance_patrol_index` (:1821), driven by the
  authored level record the level producer emits (210 paths / 673 points).
- **research:** the authored patrol branch is
  `ST_Guard Root → Standard States → Reset Focus → Return To Normal →
  Patrolling (LinkedAsset) → ST_Patrol Root → Patrol`, then
  `Set Next Patrol Path Point → [Has Broken Location? unavailable] → Reset
  Alertness → [smart object unavailable] → Patrol to Location → Move To Point →
  Say a Voice Line → Rotate → Delay → Complete Segment` (RE §"ST_Patrol", and the
  trace below).
- **decision: BLOCKED-ON T01, not attempted.** The four values the branch needs
  are all absent from the payload: `Set Alertness.AlertnessLevel` (20 instances),
  `Delay Task.duration` (32 instances; `ST_Patrol` alone authors 1.0 s and
  100.0 s), `Move To`'s target binding (9), `Bool Compare`'s operands (15). An
  interpreter driven from those absences would be *my* behaviour, not the
  authored one, and the parity test would compare the FSM with a re-spelling of
  itself. Contract: [`p4-t01-contract.md`](p4-t01-contract.md).
- **readiness evidence (what S2 would inherit):** `probe_statetree_shadow.gd`,
  560 frames, a 4-point path (waits 0 / 0.5 / 0 / 0.5 s, facing on 1 and 2):

  ```
  FSM_WP frame=0   wp=1 wait_left=0.00 pos=0.00,0.04
  FSM_WP frame=172 wp=2 wait_left=0.00 pos=0.00,3.02
  FSM_WP frame=320 wp=3 wait_left=0.00 pos=3.04,3.74
  FSM_WP frame=487 wp=0 wait_left=0.00 pos=3.75,0.96
  TREE_ENTER      tick=1   Patrol/Set Next Patrol Path Point
  TREE_ENTER      tick=2   Reset Alertness
  TREE_ENTER      tick=3   Is Patrol Point A Patrol to Location -> Move To Point
  TREE_TRANSITION tick=142 from=14 OnStateSucceeded -> Say a Voice Line
  TREE_TRANSITION tick=143 from=15 OnStateCompleted -> Rotate
  TREE_TRANSITION tick=144 from=16 OnStateCompleted -> Delay
  TREE_TRANSITION tick=174 from=17 OnStateCompleted -> Complete Segment
  TREE_TRANSITION tick=175 from=18 OnStateCompleted -> Set Next Patrol Path Point
  … cycle repeats at ticks 176 / 321 / 489 / 492
  ```

  | authored step | tree | FSM | parity |
  |---|---|---|---|
  | next point | `Set Next Patrol Path Point` | `wp_index` advance | same order (1→2→3→0) |
  | branch | `Has Broken Location?` unavailable → `Reset Alertness` → `Patrol to Location` | no broken-segment concept; patrols | same branch |
  | move | `Move To Point` completes at ≤1.0 m | arrival gate `< 1.0 m` | same gate, tree within 1 tick |
  | VO | `Say a Voice Line` | no VO from the tree | mapped no-op (PORT GAP) |
  | face | `Rotate` then `Delay` | `_apply_patrol_yaw` during the dwell | same yaw source; the tree's `Rotate` hits its 3 s observation cap on cycle 2 because the FSM's lerp (`delta*4`) does not converge inside a 0.5 s dwell |
  | dwell | `Delay` completes when the FSM's dwell ends | `_patrol_wait_left` | same duration (0.5 s: tree 144→174, FSM 142→172) |
  | segment | `Complete Segment` → `Set Next` | advance | same |

- **two FSM defects the trace surfaced** (reported, not fixed — FSM behaviour,
  out of S1 scope, and both would break parity if S2 were attempted):
  1. `state_timer` is zeroed after `_enter_alerted()` in three call sites (the
     caller sets 6.0, `_enter_alerted → _set_state` zeroes it), so a guard raised
     by a shout/damage drops to SEARCH on its first blind frame;
  2. `_move_ai` overwrites the authored arrival yaw with `look_at` on any
     no-wait arrival frame, so a point with `HasFacing` and `WaitSeconds == 0`
     never holds its authored yaw.
- **verdict: BLOCKED-ON T01** (S2 not attempted; readiness measured above).

---

## 6. Independent audit

<!-- to fill -->

## 7. Gates

All runs on this tree, serially, under `flock /tmp/opencode/tat2-godot.lock`; one
Godot at a time.

| gate | result |
|---|---|
| `tools/check_scripts_compile.gd` | **186 checked, 0 broken** (base 176; +10 = 7 statetree + 2 suites + 1 probe) |
| `tests/run_tests.gd` | **`SUMMARY: fails=0`**, **314** `^PASS` (base 312 + suites 110/111; no suite removed) |
| `tests/test_m2_player.gd` | **`M2_SUMMARY: fails=0`** |
| `tests/e2e/run_e2e_tests.gd -- --tier=1` | **`fails=0 passed=117 total=117`** |
| `tests/e2e/run_e2e_tests.gd` | **`fails=0 passed=278 total=278`** |
| `tests/probe_door_walk.gd` | **DOORWALK PASS** |
| `tests/probe_viewmodel_truth.gd` | **VIEWMODEL_TRUTH PASS** |
| `tests/probe_niagara.gd` | **NIAGARA_PROBE PASS** (3695 authored / 1048 active / 16 systems) |
| `tests/probe_blackjack_race.gd` | **BLACKJACK_PROBE PASS fails=0** |
| `tests/probe_geometry_placement.gd` | **GEOM_PROBE PASS checks=7 fails=0** |
| suite 110 | **`W9P4_STATETREE_SUMMARY: fails=0 checks=58`** |
| suite 111 | **`W9P4_SHADOW_SUMMARY: fails=0 checks=20`** |
| `build/qa/runtime_smoke.sh 90` (off) | **`RUNTIME_SMOKE PASS`** (`exit=124 script_errors=0 shader_errors=0 mission_ready=1`) |
| `TAT2_STATETREE=shadow build/qa/runtime_smoke.sh 90` | **`RUNTIME_SMOKE PASS`** (`script_errors=0 shader_errors=0 mission_ready=1`), 4 guards traced |
| `make audit` | **AUDIT PASS** (`CONSUMER AUDIT PASS`, baseline matches) |
| `make texture-cap-check` | **OK** |
| `make gate-ratchet` | **GATE_RATCHET: PASS** |
| `build/qa/test_perf_guard.sh` | **PERF_GUARD_TEST PASS checks=78 fails=0** |

No floor was lowered: compile 176 → 186, `run_tests` 312 → 314, E2E 278 → 278,
M2 12 → 12.

## 8. Ownership exception and blocked items

- **One `tools/**` line removed**: `tools/consumer_allowlist.json` carried a
  `blocked_on_team` rule (owner T11) for `gameplay/guard_behavior.json`. The
  payload now has a real `game/src` reader, and `check_consumers.py` fails closed
  with `STALE RULE` when a rule matches no unreachable file. The rule is deleted
  (5 lines; 20 rules remain); `python3 tools/check_consumers.py` →
  `CONSUMER AUDIT PASS`. This is the only `tools/**` edit and it is bookkeeping,
  not a gate change. Flagged because the brief says `tools/**` is not mine.
- **BLOCKED-ON T01**: node parameters, `Fallback`, `Delay`,
  `bConsumeEventOnSelect`, `RequiredEventToEnter` — contract in
  [`p4-t01-contract.md`](p4-t01-contract.md). S2 depends on it.
- **No other phase-owned file was touched**: `level_loader.gd`,
  `mission_controller.gd`, `hud.gd`, `game/src/ui/**` and every producer are
  byte-identical.

## 9. Open risks / what remains (S3)

1. **No parameter recovery** (§W9-P4-1) — the single largest gap; S2 waits on T01.
2. **Unsupported subsystems** behind the unsupported classes: smart objects
   (19 `Run Env Query`, 6+6 smart-object tasks), targeting groups (31+16 condition
   instances), individual knowledge/attitude (21 tasks/conditions), gameplay
   abilities (9), EQS, lockdown, revive, combat positioning. They are why 59 task
   classes stay unsupported even after a parameter pass.
3. **No `StateTreeEvent.*` emitter in the port** (0 hits in `game/src`): all 89
   `OnEvent` transitions are unreachable. `guard_bindings.event_matches` returns
   FALSE rather than UNKNOWN so the distinction stays precise ("the port never
   sends it" vs "the payload cannot evaluate it"). The FSM reacts to `NoiseBus`
   and sight directly; a future adapter must synthesise `StimChange`/`TargetChange`
   there.
4. **`detection` is a zero-equality in the side-effect proof** (§W9-P4-3); a ramp
   variant needs a player stub with `take_damage`/`apply_shock`/pose.
5. **`Rotate to Face` 3 s observation cap** and the two FSM defects in
   §W9-P4-6 must be settled before S2 can claim parity.
6. **`Fallback` is absent**, so "skip the unavailable candidate, then advance past
   the completed state" reproduces `NextSelectableSibling` only when the target is
   the next sibling. For the 39 authored uses that is the common shape
   (`ST_Patrol t[3]`), but it is not proven for all of them.
7. **Display names are not unique keys** (12 classes / 2 names; `Run Env Query`
   is two classes), so the name-keyed coverage table may declare one of the two
   `Run Env Query` classes with the other's status. The contract adds `class`.
8. **Cost not verified**: shadow adds one dictionary snapshot and one interpreter
   tick per guard per frame; no FPS measurement was taken (flag off by default,
   no capture permitted). `not verified`.
9. **S3 civilians untouched**: `ST_Civilian` (73 states) parses and traces, but
   the port has no civilian sense/health/behaviour binding.

## 10. Integrator steps

1. **Cherry-pick the commits in order; do not squash.** Nothing was pushed,
   merged or rebased.
2. **The one `tools/consumer_allowlist.json` deletion** is part of the wave
   (§8); `python3 tools/check_consumers.py` must print `CONSUMER AUDIT PASS`.
3. **No producer/regeneration is needed for S1** — the runtime reads the payload
   as emitted. The T01 contract is the next wave's prerequisite, not a blocker.
4. **`--import` generated `.gd.uid` files for other lanes' scripts** (P1/P2/P3
   files that lacked them). Only the ten files this phase added are committed;
   the rest stay untracked and are regenerated on the integrator's import.
5. **Re-run the gate set at the merged HEAD** (§7 numbers are the floors). The
   two new suites are 110/111; compile grows by 10 scripts, `run_tests` by 2
   suites.
6. **Docs owed at integration (not P4-owned):** `docs/FIDELITY_GAPS.md` — the
   StateTree consumer now exists (21 trees parsed, 0 fully evaluable, the
   parameter gap and the T01 contract); `docs/HANDOFF_NEXT_AGENT.md` — new HEAD,
   gate numbers, the S2/S3 list. `docs/FIDELITY_GAPS.md:421-425` and `:535` say
   the tree "does not drive `guard_ai.gd`" — still true for behaviour, and now
   false for "no consumer".
7. **Keep `TAT2_STATETREE=off` as the shipped default.** Shadow is opt-in until
   S2 lands.

## Appendix A — full coverage table

Generated from the `P4ROW` lines of suite 110 (`build/qa/w9/p4_rows.txt`):


### Tasks (77 classes, 326 instances)
| task | status | instances | covered | blind | note |
|---|---|---:|---:|---:|---|
| `Delay Task` | mapped-to-port | 32 | 2 | 2 | observes the FSM's authored WaitSeconds dwell; the task's Duration binding is not in the payload |
| `Request Voice Line` | mapped-to-port | 31 | 31 | 31 | PORT GAP: the port's VO is tag-driven from the FSM, not from the tree; the task completes without playing the authored line |
| `TATState Tree Task Set Alertness` | mapped-to-port | 20 | 20 | 20 | observes the FSM's alertness; the authored EAlertnessLevel parameter is not in the payload, the target is inferred from the state name |
| `Clear Focus` | mapped-to-port | 19 | 19 | 0 | PORT GAP (vacuous): the port has no focus subsystem, so clearing focus completes immediately |
| `Run Env Query` | unsupported | 19 | 0 | 0 | no port counterpart |
| `Extract Target From Targeting Group` | unsupported | 14 | 0 | 0 | no port counterpart |
| `Set Focus (Actor)` | mapped-to-port | 12 | 12 | 12 | PORT GAP (vacuous): no focus subsystem; completes without turning the guard |
| `Request Conditional Voice Line` | mapped-to-port | 10 | 10 | 10 | PORT GAP: as Request Voice Line; the tag parameter is not in the payload |
| `Move To` | mapped-to-port | 9 | 2 | 2 | completes when the FSM reaches the authored patrol point (1.0 m gate) or advances wp_index; the target binding is not in the payload |
| `TATState Tree Task Rotate to Face` | mapped-to-port | 9 | 1 | 1 | observes the authored patrol yaw the FSM already applies; the task's target binding is not in the payload |
| `TATState Tree Task Update Knowledge Of Actor` | unsupported | 9 | 0 | 0 | no port counterpart |
| `Set Value (bool)` | unsupported | 8 | 0 | 0 | no port counterpart |
| `Set Individual Attitude To Target` | unsupported | 7 | 0 | 0 | no port counterpart |
| `STT Use Smart Object with Target Actor` | unsupported | 6 | 0 | 0 | no port counterpart |
| `[TAT] Move To` | unsupported | 6 | 0 | 0 | no port counterpart |
| `STT Use Smart Object with Target Slot Handle` | unsupported | 5 | 0 | 0 | no port counterpart |
| `TATState Tree Task Set Blackboard Value` | unsupported | 5 | 0 | 0 | no port counterpart |
| `TATState Tree Task Set Individual Knowledge` | unsupported | 5 | 0 | 0 | no port counterpart |
| `Report Noise Event` | unsupported | 4 | 0 | 0 | no port counterpart |
| `TATState Tree Task Extract Stim Data from Event` | unsupported | 4 | 0 | 0 | no port counterpart |
| `TATState Tree Task Wait for Applied Tags` | unsupported | 4 | 0 | 0 | no port counterpart |
| `Trigger Gameplay Ability By Class` | unsupported | 4 | 0 | 0 | no port counterpart |
| `Trigger ability via Gameplay Tag and Wait` | unsupported | 4 | 0 | 0 | no port counterpart |
| `Apply Gameplay Effect` | unsupported | 3 | 0 | 0 | no port counterpart |
| `Get Location From Actor` | unsupported | 3 | 0 | 0 | no port counterpart |
| `Repeatedly Trigger VO` | mapped-to-port | 3 | 3 | 3 | PORT GAP: the delay/tag parameters are not in the payload; completes as a one-shot |
| `STT Set Focus` | mapped-to-port | 3 | 3 | 3 | PORT GAP (vacuous): no focus subsystem |
| `TATState Tree Send Event to NPC` | unsupported | 3 | 0 | 0 | no port counterpart |
| `TATState Tree Task Extract Main Target Data from Event` | unsupported | 3 | 0 | 0 | no port counterpart |
| `TATState Tree Task Set Blackboard Actor Value` | unsupported | 3 | 0 | 0 | no port counterpart |
| `Add Targeting Groups` | mapped-to-port | 2 | 2 | 2 | PORT GAP (vacuous): the port keeps no targeting-group registry at the tree level; ReactionRoles covers only the combat role cap |
| `Debug Text Task` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Extract Reaction Role` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Extract Scalable Float` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Register for Reaction Role` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Request Conditional Voice Line Copy` | mapped-to-port | 2 | 2 | 2 | PORT GAP: as Request Voice Line |
| `STT Equip Unequip` | unsupported | 2 | 0 | 0 | no port counterpart |
| `STT Set Share Partner` | unsupported | 2 | 0 | 0 | no port counterpart |
| `STT Trigger Search Animation` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Scoped Individual Knowledge` | unsupported | 2 | 0 | 0 | no port counterpart |
| `TATState Tree Task Loop` | unsupported | 2 | 0 | 0 | no port counterpart |
| `TATState Tree Task Set Combat Target` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Complete Broken Segment` | mapped-to-port | 1 | 1 | 1 | the port has no broken-patrol-segment concept, so this branch is unreachable |
| `Complete Patrol Segment` | mapped-to-port | 1 | 1 | 1 | the FSM advances the authored path index itself; completion is observed, not commanded |
| `Extract Conversation Share Target Data` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Extract Conversation Voice Line Data` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Extract Distraction Data` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Distraction Smart Objects` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Get Distance Between Actors` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Remember Target to Share` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Remember Target to Share Location` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Set Clue Giving Enabled` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Set Contextual Location in Use` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Share Target` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Try Claim Contextual Location` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Try Forget Share Partner` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STT Use Smart Object with Claimed Handle` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Scoped Stim Investigation` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Send Gameplay Event` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Set Focus (Location)` | mapped-to-port | 1 | 1 | 1 | PORT GAP (vacuous): no focus subsystem; completes without turning the guard |
| `TATState Tree Lockdown` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Lockdown Extract Search Target` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Lockdown Finish Searching` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Lockdown Get Alarm Station` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Send Event to NPC Share Target` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Task Combat Positioning` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Task Persist Patrol Data` | mapped-to-port | 1 | 1 | 1 | the port persists patrol state in guard fields (wp_index/_patrol_wait_left); no authored parameter is carried |
| `TATState Tree Task Retrieve Share Target` | unsupported | 1 | 0 | 0 | no port counterpart |
| `TATState Tree Task Setup Patrol` | mapped-to-port | 1 | 1 | 1 | reads the same authored patrol record the FSM uses (level `patrol_paths`); Setup Patrol's own task params are not in the payload |
| `TATState Tree Task Wait for AIResource Unlocked` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Track Targeting Groups` | mapped-to-port | 1 | 1 | 1 | PORT GAP (vacuous): no targeting-group registry |
| `Trigger Gameplay Ability By Gameplay Event` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Trigger Gameplay Ability By Input` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Trigger and Wait For Animation` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Update Stim Info` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Use Interactable Actor` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Use Smart Object` | unsupported | 1 | 0 | 0 | no port counterpart |

### Conditions (36 classes, 233 instances)
| condition | status | instances | covered | blind | note |
|---|---|---:|---:|---:|---|
| `TATState Tree Condition Main Targeting Group Matches` | unsupported | 31 | 0 | 0 | no port counterpart |
| `Check Target Has Gameplay Tag` | mapped-to-port | 27 | 27 | 27 | answered as 'the FSM is not NEUTRAL' (it has a target); the authored tag is not in the payload |
| `TATState Tree Condition Main Target Matches Detection` | unsupported | 21 | 0 | 0 | no port counterpart |
| `Object Is Valid` | mapped-to-port | 18 | 1 | 1 | answered false only where the port has no such object (smart-object states); otherwise UNKNOWN |
| `Check Targeting Data Exists for Targeting Group` | unsupported | 17 | 0 | 0 | no port counterpart |
| `Check Targeting Group Matches` | unsupported | 16 | 0 | 0 | no port counterpart |
| `Bool Compare` | mapped-to-port | 15 | 2 | 2 | answered only where the owning state disambiguates it; every other instance is UNKNOWN |
| `Check Distance From Owner` | unsupported | 10 | 0 | 0 | no port counterpart |
| `Check Gameplay Tag Event Matches` | unsupported | 10 | 0 | 0 | no port counterpart |
| `TATState Tree Condition Stim` | unsupported | 7 | 0 | 0 | no port counterpart |
| `Check Stim Event Matches` | unsupported | 6 | 0 | 0 | no port counterpart |
| `Has Tag` | unsupported | 6 | 0 | 0 | no port counterpart |
| `Check Targeting Data Matches Visibility` | unsupported | 5 | 0 | 0 | no port counterpart |
| `TATState Tree Condition Main Target Matches Actor` | unsupported | 5 | 0 | 0 | no port counterpart |
| `Check Stim Data instigator matches attitude` | unsupported | 4 | 0 | 0 | no port counterpart |
| `Check Target Knowledge with Detection` | unsupported | 4 | 0 | 0 | no port counterpart |
| `STC Has Knowlewdge to Share` | unsupported | 3 | 0 | 0 | no port counterpart |
| `TATState Tree Condition Target Detection` | unsupported | 3 | 0 | 0 | no port counterpart |
| `Check Gameplay Tag Is Valid` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Check Target Knowledge with Attitude` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Is Carrying Major Loot` | mapped-to-port | 2 | 2 | 0 | guards never carry major loot in the port; false by construction |
| `Object Equals` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Patrol Point Is Of Type` | mapped-to-port | 2 | 2 | 2 | answered from the owning state name; all 673 authored patrol points are PatrolToLocation, so the Smart Object branch is false |
| `STC Has Clue` | unsupported | 2 | 0 | 0 | no port counterpart |
| `STC Has Equipment` | unsupported | 2 | 0 | 0 | no port counterpart |
| `Check Distance From Owner Copy` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Check Linked State Is Active` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Check Stim Data Instigator matches private zone tags on actor` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Check Stim Data instigator matches attitude Copy` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Check Targeting Data Matches Specific Target` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Check Targeting Data Matches Visibility Copy` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Distance Compare` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Has Individual Knowledge` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Integer Compare` | unsupported | 1 | 0 | 0 | no port counterpart |
| `Object Is Valid Copy` | unsupported | 1 | 0 | 0 | no port counterpart |
| `STC Blackboard Actor Is Set` | mapped-to-port | 1 | 1 | 0 | PORT GAP: the port has no StateTree blackboard, so no blackboard actor is set |
