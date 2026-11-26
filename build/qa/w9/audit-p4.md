# W9-P4 — independent audit (StateTree runtime, S1)

**AUDIT: FAIL**

Independent auditor: a separate session from the phase lead. **I did not write any
of this code.** I modified exactly one file — this one,
`build/qa/w9/audit-p4.md`. I did not fix code, weaken, skip or delete a test, run a
producer, `make normalize`, `make audit-refresh-stamps`, push, merge or rebase.
My throwaway scripts and logs live in `/tmp/opencode/`
(`p4_audit_data.py`, `p4_audit_probe.gd`, `p4_audit_runs.sh`, `p4_audit_runs.log`,
`p4_audit_probe.log`).

Audited tree: worktree `/home/john/Projects/TAT-2-rem-w9-p4`, branch `rem/w9-p4`,
base `f1bf058`, HEAD `eed70ab` (runtime `2241d28`, evidence `eed70ab`). Nothing
pushed or merged.

**Tree-state note.** While I was auditing, `build/qa/w9/p4-report.md` gained an
**uncommitted** +9/−2 edit (§W9-P4-4, mtime 18:00:57, i.e. 32 s after the commit).
I did not make it. I audited the working-tree content
(`sha256 5cdaa9d01434e5327af3f99cf6a5aceee70bbe62be973c9d55da4e51e518324d`); the
committed blob (`sha256 bc77df75…`) contains the same findings F1/F2 and only
differs by that paragraph. The evidence commit and the working tree therefore do
not match — commit or revert it before hand-off. `build/qa/*` is gitignored
(`.gitignore:25`), so this audit file must be added with `git add -f`, like the
other `build/qa/w9/audit-*.md` files.

Every Godot invocation below ran one at a time under
`flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script …'`.
`godot` was never taken from `$PATH`.

---

## 1. No FSM path deleted — **PASS**

```
$ git diff --numstat f1bf058 -- game/src/ai/guard_ai.gd
20	0	game/src/ai/guard_ai.gd
$ git diff f1bf058 -- game/src/ai/guard_ai.gd | grep -c '^@@'      -> 7
$ … | grep -c '^+[^+]'                                             -> 18 (+2 blank)
$ … | grep -c '^-[^-]'                                             -> 0
```

All seven hunks are additions, so nothing could have been removed **or
reordered**:

| hunk | content | kind |
|---|---|---|
| `@@ -24,6 +24,9` | `const StateTreeShadow = preload(...)` + comment | add |
| `@@ -298,6 +301,8` | `var _st_shadow: RefCounted = null` + comment | add |
| `@@ -425,6 +430,10` | `_st_shadow = StateTreeShadow.attach(self)` in `_ready`, after the patrol fallback seed | add |
| `@@ -1441,6 +1450,8` | `if _st_shadow != null: _st_shadow.tick(delta)` in the KO branch | add |
| `@@ -1520,6 +1531,8` | same null-guarded tick at the end of `_physics_process` | add |
| `@@ -1778,6 +1791,12` | `patrol_wait_remaining()` accessor (returns `maxf(0.0, _patrol_wait_left)`) | add |
| `@@ -2571,3 +2590,4` | `StateTreeShadow.cleanup_static_caches()` in `cleanup_static_caches` | add |

No function, state, branch, constant or call site is removed or moved. The two
`tick` sites are the only calls into the runner; `attach` at `:436` is the only
attach site (full-tree grep for `_st_shadow`, `StateTreeShadow`,
`shadow_runner.attach` — see item 5).

## 2. Compile + suites — **PASS**

Own runs, serialised (`/tmp/opencode/p4_audit_runs.log`):

```
=== BEGIN compile 2026-11-25T18:01:47-05:00
scripts checked: 186, broken: 0
=== END compile exit=0
W9P4_STATETREE_SUMMARY: fails=0 checks=58          (suite 110, exit 0)
W9P4_SHADOW_SUMMARY: fails=0 checks=20             (suite 111, exit 0)
```

Both markers and the exit code are coupled:

* `game/tests/test_w9p4_statetree.gd:41-42` —
  `print("W9P4_STATETREE_SUMMARY: fails=%d checks=%d" % [fails, checks])` then
  `quit(0 if fails == 0 else 1)`.
* `game/tests/test_w9p4_shadow.gd:56-57` — the same pair.
* `fails` is only ever incremented inside `_ok()` (`test_w9p4_statetree.gd:45-49`,
  `test_w9p4_shadow.gd:81-85`); `grep -n "fails *+="` returns only those two
  lines. Every check is an `_ok(...)` call, so `fails=0` cannot print when a
  check failed.
* Suite 110 executes 58 checks and suite 111 executes 20, matching the markers.

A failing child also fails the parent: the 110/111 registration block in
`game/tests/run_tests.gd:7576-7604` does
`if code != 0 or text.find(marker) < 0: printerr("FAIL: ..."); fails += 1`, and the
parent ends with `print("SUMMARY: fails=", fails); quit(0 if fails == 0 else 1)`
(`run_tests.gd:7624-7625`).

The long gates are **quoted** from the lead's committed-run logs, as the brief
permits: `run_tests` `SUMMARY: fails=0` with **314** `^PASS` lines
(`/tmp/opencode/p4_gates.log:3634`, counted 314), `M2_SUMMARY: fails=0`
(`p4_gates.log:3700`), E2E `fails=0 passed=117 total=117` and
`fails=0 passed=278 total=278` (`:4337`, `:6033`), the five probes PASS, and
`p4_post.log` shows `RUNTIME_SMOKE PASS` off and with shadow, `AUDIT PASS`,
`GATE_RATCHET: PASS`, perf guard 78/78. I re-ran compile, both new suites and the
shadow probe myself, as required.

## 3. Coverage table vs the JSON — **PASS**

I wrote `/tmp/opencode/p4_audit_data.py` (outside the repo). It recomputes the
table from `game/data/generated/gameplay/guard_behavior.json`, re-implements the
`covers()` predicate from `guard_bindings.gd` and parses `TASK_DECL`/`COND_DECL`
from the same source.

```
task classes 77  instances 326  covered 113  blind 94
cond classes 36  instances 233  covered  35  blind 32
enter conditions 81   transition conditions 152
status split tasks {'mapped-to-port': 18, 'unsupported': 59}
status split conds {'mapped-to-port': 6, 'unsupported': 30}
fully covered trees []
rows: expected 113, mine 113, mismatches 0
report appendix: 113 rows, missing 0
per-tree table: 21 rows compared, mismatches 0
```

All 113 rows match `build/qa/w9/p4_rows.txt` exactly on
`(status, instances, covered, blind, note)`, and the class totals recomputed from
`p4_rows.txt`'s status column alone are `0 implemented / 18 or 6 mapped / 59 or 30
unsupported` — the same as §0 and Appendix A. Twelve named rows:

| row | expected (inst/cov/blind) | measured |
|---|---|---|
| `Delay Task` | 32/2/2 | 32/2/2 |
| `Move To` | 9/2/2 | 9/2/2 |
| `TATState Tree Task Set Alertness` | 20/20/20 | 20/20/20 |
| `Run Env Query` | 19/0/0 | 19/0/0 |
| `TATState Tree Condition Main Targeting Group Matches` | 31/0/0 | 31/0/0 |
| `Check Target Has Gameplay Tag` | 27/27/27 | 27/27/27 |
| `Request Voice Line` | 31/31/31 | 31/31/31 |
| `TATState Tree Task Rotate to Face` | 9/1/1 | 9/1/1 |
| `Bool Compare` | 15/2/2 | 15/2/2 |
| `Object Is Valid` | 18/1/1 | 18/1/1 |
| `Clear Focus` | 19/19/0 | 19/19/0 |
| `Patrol Point Is Of Type` | 2/2/2 | 2/2/2 |

Also independently reproduced: 459 states / 467 transitions / 45 LinkedAsset / 2
local `Linked` (both in `ST_InvestigateStims_Guard`, both to index 8, type
`Subtree`; only that tree has two roots); 376 State / 35 Group / 45 LinkedAsset /
2 Linked / 1 Subtree; selection 439/20 with all 20 `TryEnterState` childless;
triggers 284/89/38/36/20; priorities 358/67/21/12/9;
targets 417/35/15; 7 disabled states, 1 disabled transition, 0 utility
considerations; `children_range` differs from the direct child list on exactly
52 states (`b-a != len(children)`); 139 blueprint nodes (127 `TaskClass` +
12 `ConditionClass`); `bConsumeEventOnSelect == false` on 2 states; the 3
`RequiredEventToEnter` states are exactly the ones listed.

`P4COVERAGE fully_covered_trees=0` was reproduced. The coverage number is a
generous upper bound (class-level `blind`), and the report says so.

## 4. No parameter in the payload — **FAIL** (five of six greps are 0; `fallback` is not)

```
$ for pat in EAlertnessLevel PatrolPathType InstanceTemplateIndex \
             '"duration"' fallback required_event_to_enter; do
      printf '%-22s ' "$pat"; grep -c -- "$pat" game/data/generated/gameplay/guard_behavior.json; done
EAlertnessLevel        0
PatrolPathType         0
InstanceTemplateIndex  0
"duration"             0
fallback               467
required_event_to_enter 0
```

Node parameters really are absent, and the raw-dump values the report cites
really exist (sampled; `ST_Patrol[17]`/`[19]` are state indices, whose task
nodes are 14 and 16):

* `Properties.Nodes.Structs[0]`, `[7]`, `[9]` = `TATState Tree Task Set
  Alertness` → `{AIController:null, AlertnessLevel:"EAlertnessLevel::Neutral",
  RunUntilAnimationFinished:true}`; node `[5]` = `Alerted`.
* node `[14]` = `Delay Task` → `{duration:1.0, RandomDeviation:0.0,
  bRunForever:false}`, used by state 17 `Delay` (`TasksBegin=14`);
  node `[16]` → `{duration:100.0, …}`, used by state 19 `Failed`
  (`TasksBegin=16`).
* `PatrolPathType:"EPatrolPointType::SmartObjectInteraction"` at
  `extracted/json/AI/StateTrees/SubTrees/ST_Patrol.json:6022`.
* Exactly 3 states carry `EventDataIndex != 65535`: `ST_Patrol[21]`,
  `ST_Subtree_Combat[6]`, `ST_InvestigateStims_Guard[6]`.

**But `fallback` is not absent from the payload.** See F1.

## 5. Side-effect proof — **PASS**

Own run of suite 111 produced two lines that are identical on every field the
brief names:

```
SHADOW_PHASE mode=off    sig=-5750684789768048477 pos=1.382652,-0.049066,3.357109 state=0 detection=0.000000 wp=2 ever=false rows=0 ticks=0 transitions=0 trees=
SHADOW_PHASE mode=shadow sig=-5750684789768048477 pos=1.382652,-0.049066,3.357109 state=0 detection=0.000000 wp=2 ever=false rows=70 ticks=241 transitions=6 visited=16 trees=ST_Guard,ST_Patrol reached_patrol=true
```

`rows=70 > 0`, `ticks=241 >= 235`, `reached_patrol=true`, `trees=ST_Guard,ST_Patrol`
— all as claimed.

Code-path audit (the brief's exact grep):

```
$ grep -nE "\.set\(|_set_state|_enter_|take_knockout|detection =|state =" game/src/ai/statetree/*.gd
interpreter.gd: 116,144,149,269,270,276,309,310,318,326,332,335,372,377,397,426,461,680,776,778,833
   (all its own _enter_state/_enter_tasks/_evaluate_enter_conditions/_enter_name)
shadow_runner.gd:151  last_state = interpreter.current_state()
shadow_runner.gd:164  last_state = state
```

* Every `interpreter.gd` hit is the interpreter's **own** `_enter_state` /
  `_enter_tasks` / `_evaluate_enter_conditions` / `_enter_name`, not a guard
  call. `interpreter.gd` never holds a guard or a Node (its inputs are `trees`,
  `bindings`, `trace`; header :53-54 says so and the code matches).
* The only `state =` assignments are the runner's own `last_state`.
* No `.set(`, no `_set_state`, no `_enter_alerted` / `_enter_combat`, no
  `take_knockout`, no `detection =` on any guard.
* All guard access in `guard_bindings.gd` is a read: `guard.get("patrol_points")`,
  `"wp_index"`, `"patrol_facing"`, `"patrol_yaws"`, `"state"`, `"detection"`,
  `"health"`; `guard.has_method("patrol_wait_remaining")` + `guard.call(...)`;
  `node.global_position`, `node.rotation.y`, `get_instance_id()`, `guard.name`.
  The called accessor is read-only (`guard_ai.gd:1796-1797`,
  `return maxf(0.0, _patrol_wait_left)`).
* `guard_bindings.mutates()` returns `false` (`guard_bindings.gd:177-178`).
* `attach()` is called only from `guard_ai.gd:436`; `tick()` only from `:1454`
  and `:1535`; `cleanup_static_caches()` only from `:2593`. No other file in
  `game/src` references `_st_shadow`, `StateTreeShadow` or `shadow_runner`.

Writes that do exist — `observed`, `task_instances`, `unknown_conditions`,
`events_matched/refused`, `last_guard_position`, `stationary_s`, the runner's
`ticks`/`stall` fields and the trace sink — are all runner-local or global
diagnostics, none on a guard. The only process-level side effect is the optional
NDJSON trace when `TAT2_STATETREE_TRACE` is set. **The structural claim (read-only
binding) holds**, so the proof is not just a lucky arena.

Scope: the arena never leaves `state=0` (NEUTRAL) and has no player; the equality
therefore exercises the patrol/neutral tick path, and `detection` is an equality
of zeros (disclosed at report :224-228 and §9.4). See F8 for the missing NEUTRAL
sentence.

## 6. All 21 trees traced — **PASS**

Own suite-110 run:

```
P4TREES started=21 blocked=0 rows=140 trees=21
```

`shadow_runner.gd:226-256::trace_all_trees` starts each tree with the base
binding, ticks it 4× and returns `sink.rows_for(tree)` (rows whose `interpreter`
field is that tree). The suite's assertion only requires a non-empty trace, so I
also ran a throwaway probe (`/tmp/opencode/p4_audit_probe.gd`) that counts the
row kinds:

```
PROBE_TREES trees=21 with_start=21 with_enter=21 no_start=[] no_enter=[] rows=140 blocked=0
```

Per-tree examples: `ST_Patrol rows=14 kinds={start:1, enter:4, block:4, task_block:4, condition_unknown:1}`,
`ST_Guard rows=8 …`, every tree has exactly one `start`, ≥1 `enter` and ≥1
`block`. So the report's "at least a start, an enter and the block that stopped
it" is true — but it is measured by my probe, not asserted by suite 110 (F9).

## 7. The patrol readiness claim — **PASS** (with one narrative error, F3)

```
$ TAT2_STATETREE=shadow flock … tools/godot --headless --path game \
    --script res://tests/probe_statetree_shadow.gd -- --frames=560
FSM_WP frame=0   wp=1 wait_left=0.00 pos=0.00,0.04
FSM_WP frame=172 wp=2 wait_left=0.00 pos=0.00,3.02
FSM_WP frame=320 wp=3 wait_left=0.00 pos=3.04,3.74
FSM_WP frame=487 wp=0 wait_left=0.00 pos=3.75,0.96
TREE_TRANSITION tick=142 from=14 OnStateSucceeded -> Say a Voice Line
TREE_TRANSITION tick=143 from=15 OnStateCompleted -> Rotate
TREE_TRANSITION tick=144 from=16 OnStateCompleted -> Delay
TREE_TRANSITION tick=174 from=17 OnStateCompleted -> Complete Segment
TREE_TRANSITION tick=175 from=18 OnStateCompleted -> Set Next Patrol Path Point
… repeated at 176 / 321 / 489 / 492
P4TRACE mode=shadow frames=560 rows=107
P4SHADOW … ticks=561 visited=16 transitions=11 blocks=1 unknown=1 stalls=0
PROBE PASS fails=0
```

This matches §W9-P4-6's table **exactly**: wp 1→2 at 172, 2→3 at 320, 3→0 at 487,
same positions, `Move To` completes at 142, `Delay` 144→174 (30 ticks = 0.5 s),
same transition order, same repeat ticks. No drift at all, not even one frame.
The "Rotate hits its 3 s cap on cycle 2" sentence is not supported by this trace
(F3).

## 8. Flags and defaults — **PASS**

Throwaway probe, fresh process with `TAT2_STATETREE` unset
(`env -u TAT2_STATETREE`):

```
PROBE_ENV raw=''
PROBE_MODE_FRESH mode=off enabled=false
PROBE_DEFAULT_RUNNER is_null=true rows=0 mode=off     (after 30 live physics frames)
```

`shadow_runner.mode()` parses once (`_mode` cached), `parse_mode("")` → `off`,
`attach()` returns `null` before touching the library, and `guard_ai._ready()`
stores that null. `library()` has exactly the call sites the report claims:
`shadow_runner.gd:104` (`trees()`), `:134` (`_start`, only via `attach`), `:227`
(`trace_all_trees`) and `coverage()` at `:262`; `mode()` never calls it. So `off`
reads no payload file and does no trace I/O. `cleanup_static_caches()` clears the
library, the mode and the shared trace. Unknown values degrade to `off` with one
`push_warning`; suite 111's `OS.set_environment` checks exercise the real parser
(`off`/`shadow`/`patrol`/`nonsense`→`off`).

## 9. Tests not weakened — **PASS**

```
$ git diff --numstat f1bf058 -- game/tests/run_tests.gd
27	0	game/tests/run_tests.gd
```

The whole diff is one inserted block (`run_tests.gd:7576-7604`) immediately after
suite 109. No existing suite number, marker or assertion is changed — there are
no removed lines at all. Suites 110/111 are registered with their exact marker
strings (`"W9P4_STATETREE_SUMMARY: fails=0"`, `"W9P4_SHADOW_SUMMARY: fails=0"`)
and a failing child increments the parent's `fails` (see item 2). The two new
suites contain 58 and 20 `_ok` checks; the medium-vs-normal priority test really
pins the UE enum order (`_check_medium_beats_normal` builds `SYN_PRIORITY2` with
Normal vs Medium and fails if the wrong target fires). Nothing is skipped or
guarded off.

## 10. Gates and the one tools edit — **PASS**

```
$ git diff --numstat f1bf058 -- tools/
0	6	tools/consumer_allowlist.json
$ git diff --stat f1bf058 -- tools/
 tools/consumer_allowlist.json | 6 ------
$ python3 tools/check_consumers.py | tail -1
CONSUMER AUDIT PASS
```

Exactly one tools file changed, exactly the 6-line `blocked_on_team` object
(`{`, the four fields, `},` — the report's "5 lines" is one short); `rules` goes
21 → 20 (`git show f1bf058:tools/consumer_allowlist.json
| grep -c '"glob"'` = 21, current = 20). `tools/gate_ratchet.json` and every other
gate file are untouched. The deleted rule ("21 authored StateTrees (784 KB) have
no runtime consumer") is genuinely stale: `tree_model.gd:72` carries
`DEFAULT_PATH = "res://data/generated/gameplay/guard_behavior.json"`,
`load_library()` opens it, and `attach()` calls it whenever a guard exists, so the
payload is reachable from `game/src`. The audit fails closed on stale rules, so
leaving it would have failed.

## 11. Report honesty — **FAIL**

(a) **"0 implemented"** — reproduced as a count of declared statuses: no entry in
`TASK_DECL`/`COND_DECL` uses `implemented`, and the table's own definition
("driven from fields the payload carries") makes 0 correct because the payload
carries names only. §W9-P4-4 discloses that graph mechanics (trigger/priority)
are not counted. Not a false measurement.

(b) **`detection` is an equality of zeros** — disclosed verbatim at report
:224-228 and §9.4. Correct.

(c) **shadow cost `not verified`** — stated in the §W9-P4-3 verdict and §9.8.
Correct and honest.

(d) **S2 BLOCKED-ON T01 / no cutover** — confirmed: no cutover code exists
(`attach()` treats `patrol` exactly like `shadow` after one warning; `guard_ai`
has no mode test around the runner), and the test only proves the mode string
parses. The report says "behaves exactly like `shadow` and says so once", which is
true by inspection but is not asserted by suite 111 (nit, see F12).

(e) **§0 numbers** — all reproduced except the condition-parameter count (F2).
`113/94`, `35/32`, `326`, `233`, `0/18/59`, `0/6/30`, `sig=-5750684789768048477`,
`241` ticks, `70` rows, `220` mission rows/4 guards/17 transitions/12 unmet/11
fallbacks/4 task blocks/4 `Bool Compare` — every one checked (`p4_mission.ndjson`
parse included).

(f) **stale `file:line`** — one: the `docs/FIDELITY_GAPS.md:421-425` / `:535`
reference is wrong (F4). The `guard_ai.gd` references (`:5`, `:1444-1546`, `:1775`,
`:1801`, `:1810`, `:1821`) are current.

---

## Findings

| id | severity | finding | evidence | invalidates a report claim? |
|---|---|---|---|---|
| **F1** | **blocker** | The claim "the payload has no transition `delay`/`fallback`/`consume_event` key at all" is false for **fallback** and **delay**. The payload's flat `trees.<tree>.transitions[]` carries 14 keys, including `fallback` (428 `None` + 39 `NextSelectableSibling`, exactly matching the raw dump) and `delay_seconds`/`delay_random_variance` (all 0.0). The per-state 9-key copies omit them, and `tree_model.gd` builds only from the copies (`:257`, `:391`), so the interpreter cannot see authored fallback. Consequences: the omission table's Fallback/Delay rows, §9.6, `tree_model.gd:40-43`, and `p4-t01-contract.md` §3/§5.4 are wrong; the fix is consumer-side (read the flat record) or an explicit port decision, not a producer addition. | `grep -c fallback` → **467**; python walk of the flat arrays → 428/39 and 467×0.0; raw `ST_Patrol.json` `Properties.Transitions[3].Fallback = NextSelectableSibling`; total raw fallback 428/39; `tree_model.gd:257(:transitions.append)` and `:391(:delay_s)` read only `state["transitions"]`. | **Yes** — §W9-P4-1 :102-104 and :115-116, §9.6 :433 (committed :426), T01 §3/§5.4, `tree_model.gd` header. Not the coverage/side-effect numbers, and not the S2 conclusion (the four patrol-branch *parameters* are still absent). |
| **F2** | **blocker** | "209 of 233 condition instances carry an authored parameter struct" is 6 too high. The correct count over the 233 referenced condition instances is **203** (199 native + 4 BP). 205 = 199 referenced + the 6 `Get Actor Location` property-function nodes, which are **not** referenced as conditions (0 refs) and which the fact sheet itself excludes ("233 referenced conditions, 6 property functions"). The report and T01 copied the 239-node numerator onto the 233 denominator; the facts sheet's prose at :51/:577 does the same (its table at :591 is over 239). | Independent chain walk of all 21 raw assets: tasks 326 = 190 native-value + 9 native-null + 70 BP-override + 57 BP-inherit → **260** (matches); conditions 233 = 199 + 22 + 4 + 8 → **203**; all shared-source nodes 239 with 205 non-empty native structs (the 6 property functions are the delta); `grep` for `Get Actor Location` as a condition = 0 refs. | **Yes** — §0 :43, §W9-P4-1 :114, `p4-t01-contract.md` :19/:134, facts :51/:577. Does not change the conclusion (87 % of conditions still need a producer pass). |
| **F3** | should-fix | "The tree's `Rotate` hits its 3 s observation cap on cycle 2" is not what the trace shows: `Rotate` enters at tick 322 and leaves at 489 = **167 ticks ≈ 2.78 s**, 13 ticks *before* the 3.0 s cap; it converged on the yaw gate. Reword ("nearly hit the cap") or quote 2.78 s. | §W9-P4-6 :350; probe output ticks 322→489; `guard_bindings.gd:409` cap is `elapsed >= 3.0`. | Yes, one sentence in the parity table; not a gate/coverage claim. |
| **F4** | should-fix | `docs/FIDELITY_GAPS.md:421-425` and `:535` are stale. The StateTree sentences are at :475, **:499** ("guard StateTree data is not yet driving `guard_ai.gd`") and **:587**; 421-425 are quest placements and 535 is W6 integration. | `grep -n StateTree docs/FIDELITY_GAPS.md`; `sed -n '421,425p;535,540p'`. | Yes — §10.6:463-464. |
| **F5** | should-fix | "Five synthetic trees" — the suite builds **six** (`SYN_SELECTOR`, `SYN_PRIORITY`, `SYN_PRIORITY2`, `SYN_EVENT`, `SYN_DELAY`, `SYN_UNKNOWN`). | `test_w9p4_statetree.gd:448,465,478,491,503,515`; `grep -c 'trees\["SYN_'` = 6. | Yes — §W9-P4-2:182 and §W9-P4-5:295. |
| **F6** | should-fix | "Every row has a note … and, when `parameter_blind`, that the authored value is absent" overstates the notes: 15 of the 24 rows with `blind>0` do not say the authored value is absent (most are "PORT GAP (vacuous)"). The `blind` column does carry it. | `p4_rows.txt` parse: 24 blind>0 rows, 15 without an absence phrase. | Yes — §W9-P4-4:280-282. |
| **F7** | nit | "No `StateTreeEvent.*` emitter in the port (0 hits in `game/src`)" — there are 3 hits, all comments in the new files (`interpreter.gd:22`, `guard_bindings.gd:27,458`). There is indeed no emitter; the parenthetical count is wrong. | `grep -rn StateTreeEvent game/src` → 3, all `##`. | Cosmetic (§9.3:423). |
| **F8** | should-fix (scope) | The side-effect arena never leaves `state=0` (NEUTRAL) and has no player. The report discloses the detection-zero issue but not that the equality covers only the neutral/patrol tick path; the alerted/combat tick paths are covered by the structural read-only argument, not by the measured signature. | `SHADOW_PHASE … state=0` both phases; `_phase()` never sets the guard's state. | No false number; a scope sentence is owed (§W9-P4-3:217-228). |
| **F9** | nit | `trace_all_trees` hard-codes `"missing": []` (`shadow_runner.gd:253`), and the `P4TREES` assertion only requires a non-empty trace, not a `start` row. The report's "at least a start row per tree" is **true** (my probe: 21/21), but it is not asserted by suite 110. | `shadow_runner.gd:248-256`; `test_w9p4_statetree.gd:371-377`; probe output. | No — measurement stands; the test claim should say "measured by the audit probe". |
| **F10** | nit | The `SHADOW_PHASE` quote in the report drops the trailing `samples=…` field of the real line. The quoted fields are correct; label it abridged. | Actual lines in `/tmp/opencode/p4_audit_runs.log:232-233` vs report :219-220. | No. |
| **F11** | nit | "same gate" for `Move To`: the binding completes at `dist <= 1.0` (`guard_bindings.gd:399`), the FSM at `< 1.0` (`guard_ai.gd:1784`). A boundary simplification, not a behavioural finding. | source lines above. | No. |
| **F12** | nit | "`patrol` … behaves exactly like `shadow`" is proven by inspection (`attach()` only warns), not by suite 111, which asserts the mode string only. | `shadow_runner.gd:121-130`; `test_w9p4_shadow.gd:68-70`. | No — honest but untested; a one-line note would close it. |
| **F13** | observation | The working tree has an **uncommitted** +9/−2 edit to `build/qa/w9/p4-report.md` (§W9-P4-4) made at 18:00:57, after `eed70ab`; not mine. Evidence commit ≠ working tree. | `git status --short`; `git diff -- build/qa/w9/p4-report.md`; `stat` mtime; sha256 above. | No claim is invalidated; the committed evidence must be completed or reverted before hand-off. |

## Per-item verdicts

| item | verdict |
|---|---|
| 1 no FSM path deleted | **PASS** — 20 added, 0 removed, no reordering |
| 2 compile + suites | **PASS** — 186/0, 58/0, 20/0; marker and exit coupled; failing child fails parent |
| 3 coverage vs JSON | **PASS** — 113/113 rows exact, 21/21 per-tree, class totals exact |
| 4 no parameter in the payload | **FAIL** — node parameters absent (true), but `fallback` present 467× (F1) |
| 5 side-effect proof | **PASS** — identical signatures and a read-only code path; scope note F8 |
| 6 all 21 trees traced | **PASS** — 21/21 start + enter + block rows (probe) |
| 7 patrol readiness | **PASS** — exact match to the table; one narrative error F3 |
| 8 flags and defaults | **PASS** — off/runner-null/no library load reproduced |
| 9 tests not weakened | **PASS** — additive, registered, fails propagate |
| 10 gates and one tools edit | **PASS** — one 6-line deletion, audit green, no gate touched |
| 11 report honesty | **FAIL** — F1 and F2 are false data claims; F3-F7 overstate |

## Overall

The code is green on every gate I re-ran or quoted: compile 186/0, suites
110/111 at 58/0 and 20/0, the shadow proof's identical signatures, 21/21 tree
traces, the exact patrol order, the coverage table's 113 rows, the additive test
registration and the one disclosed tools deletion. The side-effect proof is
structurally sound, the FSM is untouched, and the S2 BLOCKED-ON T01 decision
survives even after F1/F2.

The verdict is **FAIL** because the "*BLOCKED-ON T01*" evidence contains two
false measurements/claims:

1. **F1** — the payload *does* carry `fallback` (39 `NextSelectableSibling`) and
   `delay` on its flat transition records; the runtime drops them by reading only
   the nested copies. The report, the model header and the T01 contract say the
   opposite, which misdirects the fix to the producer and hides a consumer-side
   gap.
2. **F2** — "209 of 233 condition instances" is really **203 of 233**; the 6
   extra are `Get Actor Location` property functions that are not conditions.

Neither changes the conclusion that a parameter pass is needed, and neither
touches the runtime/coverage/gate measurements. Fix the claims (and decide
whether to consume `fallback` from the flat record or record it as a port
decision), re-stamp the facts sheet and T01 contract, commit the pending report
edit, then re-audit.

**I did not write the code, and I modified nothing except this audit file.**

---

# Re-audit

**AUDIT: FAIL** — F1's code/join and F2 are closed, but the F1 fix introduced a
**new blocker** in the new target-selection path (N1): a transition whose target
is already an active ancestor (or the state itself) re-enters that state and
duplicates its frame. This is proven with a synthetic tree and affects 71
authored transitions (67 of them non-`OnEvent`). The committed F1 report prose
also still contradicts its own table (F1 below), and F4/F6/F10 are only partly
closed.

Re-audited tree: worktree `/home/john/Projects/TAT-2-rem-w9-p4`, branch
`rem/w9-p4`, HEAD `d351712` (`2241d28` runtime, `eed70ab` evidence, `d351712`
fixes), base `f1bf058`. At the start of the re-audit (18:33) the tracked tree was
clean apart from the data symlinks and other lanes' `.gd.uid` files. **During the
re-audit, uncommitted edits appeared**: `p4-report.md` at 18:35 (+22/−4: the
§W9-P4-1 sentence, §9.10/§9.11, the runtime-smoke row) and
`interpreter.gd`/`tree_model.gd`/`shadow_runner.gd` at 18:56–57 (a candidate
target-already-active guard, a full shared-key join cross-check, `_start()`
refusing `ok=false`). Those edits are **not in `d351712`** and were still changing
when this section was written; my gates ran at 18:33 and my ancestor probe at
18:54:40, both before the code edits, so the results below describe the commit. I
label every working-tree quote that is not in `d351712`. The pending edits look
like the right response to N1/N2 and the F1/F4/F6 wording, but they need a commit
and a full gate + ancestor-probe re-run. Still one Godot at a time under
`flock /tmp/opencode/tat2-godot.lock`; I modified only this file. Report line
numbers below are the **working-tree** file; the uncommitted edit shifts lines
after :100 by +1 and after :511 by +16 relative to the committed `d351712` file.

Commands run (own runs, serialised; logs in `/tmp/opencode/`):

```
tools/godot --headless --path game --script $PWD/tools/check_scripts_compile.gd
tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd
tools/godot --headless --path game --script res://tests/test_w9p4_shadow.gd
TAT2_STATETREE=shadow tools/godot --headless --path game \
  --script res://tests/probe_statetree_shadow.gd -- --frames=560
tools/godot --headless --path game --script /tmp/opencode/p4_reaudit_probe.gd
tools/godot --headless --path game --script /tmp/opencode/p4_ancestor_probe.gd
```

## What reproduced

| check | result |
|---|---|
| compile | **186 checked, 0 broken** (`p4_reaudit_runs.log:4`) |
| suite 110 | **`W9P4_STATETREE_SUMMARY: fails=0 checks=64`**, `P4LIB 21/459/467`, `P4TREES started=21 blocked=0 rows=140 trees=21` |
| suite 111 | **`W9P4_SHADOW_SUMMARY: fails=0 checks=20`**; **sig `-5750684789768048477` identical**; off `rows=0`, shadow `rows=66 ticks=241 transitions=10 visited=16 trees=ST_Guard,ST_Patrol reached_patrol=true` |
| probe 560 | `P4TRACE … rows=101`; FSM wp 1→2@172, 2→3@320, 3→0@487 with the same positions; `Move To` 142; `Delay` 144→174; `Rotate` **322→489 (167 ticks, 2.78 s)**; `PROBE PASS fails=0` |
| join (my probe) | `PROBE_JOIN transitions=467 next=39 none=428 bad=0 nonzero_delay=0`; `ST_Patrol` state 4 transition 3 → `fallback=NextSelectableSibling delay_s=0.0 to=Has Broken Location?`; 21 trees × 60 base-binding ticks → `PROBE_REFUSED []` |
| live mission trace | 209 rows from 4 guards, ticks 0..3622, **29 transitions (8 distinct)**, 0 `transition_unmet`, 0 `fallback` rows, 4 `task_block` (`STT Distraction Smart Objects`), 4 `Bool Compare`; the report's updated numbers match |
| gate logs (`p4_gates.log`, `p4_post.log`; mtimes 18:27/18:31, post-fix working tree) | compile 186/0; `run_tests` `SUMMARY: fails=0` with **314** `^PASS`; `M2_SUMMARY: fails=0`; E2E **117/117** and **278/278**; DOORWALK/VIEWMODEL/NIAGARA/BLACKJACK/GEOM PASS; `RUNTIME_SMOKE PASS` off and shadow (0 script/shader errors); `AUDIT PASS`; `GATE_RATCHET: PASS`; `PERF_GUARD_TEST PASS checks=78 fails=0` |

The suite-111 row/transition counts changed from 70/6 to **66/10** because the
fallback path now emits a `transition` row instead of a `TREE_FALLBACK` row.
The FSM signature is unchanged, which is what the side-effect proof claims.

## F1-F13 closure

| id | status | evidence |
|---|---|---|
| **F1** | **not fully closed in `d351712`** (code/join closed; the committed report prose still says the opposite) | The join runs: `PROBE_JOIN` 467 transitions, **39** `NextSelectableSibling`, **428** `None`, 0 bad, 0 non-zero delays; `ST_Patrol` t3 joined; `lib.ok=true`; suite 110 64/0. The committed table rows are corrected (:116-117) and T01's "Already emitted" section is committed. **But `d351712`:103-104 still says "the payload has no transition `delay`/`fallback`/`consume_event` key at all"** — the same section whose table now says they are in the payload. The uncommitted 18:35 report edit fixes that sentence (working tree :102-104); it is not in the audited commit. |
| **F2** | **closed** (one wording nit, N5) | Report :43-46 cites the fact sheet's 260/326 and 209/233 plus the audit's **203/233**; §W9-P4-1 :116 says "~203-209"; §W9-P4-5 :335-339 has the counting caveat; `tree_model.gd:30-38` and T01 :20-27 cite both. My chain walk still gives 203/233 (199 native + 4 BP). |
| **F3** | **closed** | Report §W9-P4-6 face row and §9.5 now say **2.78 s / 167 ticks, the 3 s cap did not fire**; probe Rotate 322→489. |
| **F4** | **not fully closed** (wording; the correct refs are present) | Report :549 still asserts `docs/FIDELITY_GAPS.md:421-425` and `:535` "say the tree does not drive…"; the parenthetical then says the real rows are `:475`, `:499`, `:587`. Replace, do not footnote. |
| **F5** | **closed** | Report §W9-P4-2 :197 and §W9-P4-5 :319 say **eight** synthetic trees; the suite defines 8 (`SYN_SELECTOR/ PRIORITY/ PRIORITY2/ EVENT/ DELAY/ UNKNOWN/ FALLBACK/ NOFALLBACK`). |
| **F6** | **not fully closed** (new wrong pairing, N4) | The substantive point is fixed ("the `blind` column, not the prose, is the count"), but :301-303 now says "On the **24 (of 35)** covered condition rows" — 24 is the number of rows with `blind>0` across tasks **and** conditions; there are **4** condition rows with `blind>0` and 35 covered condition **instances**. |
| **F7** | **closed** | Report §9.3 :487 says "0 emitters; 3 comment mentions"; `grep -rn StateTreeEvent game/src` → 3, all `##`. |
| **F8** | **closed** | Report §W9-P4-3 :244-246: "The arena also never leaves `NEUTRAL`… no detection ramp or alertness transition is exercised." |
| **F9** | **closed** | `shadow_runner.gd:246-257` computes `missing` from empty traces; report :250-254 says the suite asserts `started==21` + non-empty traces and the audit probe added the 21/21 `start` rows. My probe: 21/21 `start`, 21/21 `enter`, 21/21 `block`. |
| **F10** | **not closed** (N3) | Report :38 still says "wrote **70** trace rows"; the §W9-P4-3 confirm-green block at :237 (d351712 :236) still says `rows=70 … transitions=6`; the actual post-fix run is **66/10** (the prose :242 is correct). No "abridged" label exists (`grep abridged` only in the §6 summary claiming it closed). |
| **F11** | **closed** | `guard_bindings.gd` uses `< 1.0` in both `at_point` and `Move To`; report §W9-P4-6 says "<1.0 m … same gate". |
| **F12** | **closed** | Report §W9-P4-3 :220-221: "verified by inspecting `attach()` … and by suite 111 parsing the value, not by a behaviour test." |
| **F13** | **closed** | The first audit's pending report edit is committed in `d351712`; the tracked tree was clean at 18:33 when this re-audit started. (New uncommitted edits appeared later — see N6, not F13.) |

## Adversarial checks on the new path

* **Join key.** Transition `index` is unique per tree in the payload (0 duplicates
  across 467), so the `index`-only join cannot mis-join two transitions today. A
  missing/duplicate/foreign record appends an error and the model's `ok` becomes
  false — but in `d351712` `attach()` does not check `ok` (N2), and only
  `from_state_index` is cross-checked; the other 8 shared keys are not, so a
  flat/nested disagreement on `to_state_index`/`trigger`/`conditions` would be
  silent (N2). The uncommitted working tree adds the full shared-key cross-check
  and the `_start()` `ok` check; that is not in the audited commit.
* **Depth.** `_ancestor_depth` matches the old chain walk and returns ≥1 for a
  valid tree (its root is active), but `_select_target` re-enters a target that is
  already the frame at `depth-1` (N1).
* **Recursion.** None added; `_enter_state` is bounded by `MAX_FRAMES`; 21 trees ×
  60 base-binding ticks completed with 2–4 frames and `PROBE_REFUSED []`.
* **Sibling parent.** The fallback scans the target's authored parent and enters
  only its siblings, so it cannot enter a sibling of the wrong parent; no
  wrong-parent entry was observed. `_link_parent_child` assumes that parent is at
  `depth-1`, which holds when it is active.
* **Dry run vs full entry.** Statically over the 39: under the base binding, 0
  cases where `_can_select_target` says yes and `_select_target` cannot enter (the
  targets/fallback siblings either have condition-free children or no children),
  and the 60-tick run produced 0 `target refused` blocks. Under the guard binding
  the only fallback target with a TRUE condition and children is `ST_Patrol`
  `Rotate` (no children), so no measured divergence. The **uncommitted working-tree**
  report §9.11 discloses the shallow check (d351712's report does not); its "all
  39 … refusal is an enter condition" is imprecise
  (many targets have no enter conditions and simply cannot refuse), but the
  conclusion holds for the data. `_collect_and_apply` still ignores
  `_apply_transition`'s false return, so a future divergence would leave the
  stack truncated (hardening item, folded into N2).

## New findings

**N1 — blocker (new, introduced by `d351712`).** `_select_target()` dropped the
old "target is already the frame at `depth-1`" early return. When a transition
targets a state that is already active (an ancestor, or the state itself), the
code exits to the target's depth and then **re-enters the target**, appending a
duplicate frame. The old code (`eed70ab`, `interpreter.gd:773-775`) did
`_exit_to(depth); if target == frames[depth-1].state: return;` — that guard is
gone.

Evidence — `/tmp/opencode/p4_ancestor_probe.gd`, a valid synthetic
`Root → A → B` with `B --OnTick--> A` (ancestor), `PROBE_LIB ok=true errors=[]`:

```
PROBE_START path=…Root -> …Root/A -> …Root/A/B frames=3
PROBE_TICK 1 frames=4 duplicate_frames=1 path=…Root -> …Root/A -> …Root/A -> …Root/A/B
PROBE_TICK 2 frames=5 duplicate_frames=2 path=…Root -> …Root/A -> …Root/A -> …Root/A -> …Root/A/B
PROBE_TICK 3 frames=6 duplicate_frames=3 path=…Root -> …Root/A -> …Root/A -> …Root/A -> …Root/A -> …Root/A/B
```

Reach: **71** authored transitions target an ancestor or their own state
(69 ancestor + 2 self); **67 are non-`OnEvent`** (60 `OnStateCompleted`,
4 `OnStateFailed`, 2 `OnStateSucceeded`), so the missing event emitter does not
protect them. Examples: `ST_Guard "Patrolling"` (transition 35) `OnStateCompleted → Root`,
`ST_Patrol "Failed"` (transition 18) `OnStateCompleted → Patrol`,
`ST_Subtree_Combat` many `→ Decision`, `ST_Civilian` many `→ Root`.

Impact: the shadow interpreter's frame stack, `current_path`, `visited`,
completion propagation and `frames.size()` become wrong; a repeated trigger grows
the stack by one per fire until `MAX_FRAMES` 32. It is shadow-only today (the FSM
is untouched), but it is a regression in the generic runtime that the report's
§W9-P4-2 calls FIXED, and S2 would inherit it. None of the gates exercises it:
the 560-frame probe and the live mission do not fire an ancestor transition, and
suite 110's only ancestor transition (`SYN_SELECTOR` D→Root) is not reached by
the event test. The **uncommitted working-tree** report §9.10 (not in `d351712`; the committed
report's §9 ends at item 9) says "69 authored transitions target an ancestor and
24 a descendant, so the common case is exact" — for an **active** ancestor it is
not exact; `d351712` does not disclose the ancestor case at all.

**N2 — should-fix (test/validation gap in the new join).** The join is not
directly asserted: suite 110's +6 checks are all in `_check_fallback`; no test
reads a real joined `fallback`/`delay_s`, and the join's failure modes (missing,
duplicate, foreign `from_state_index`, flat-vs-nested disagreement) have no test.
"Fails closed" is only `lib.ok=false` in `d351712`: `shadow_runner._start()` does
not check `ok`, so a live guard would still run a partially joined tree (the
uncommitted worktree adds the refusal). In `d351712` the join cross-checks only
`from_state_index`; the other 8 shared keys are taken from the nested copy, so a
producer that changes `to_state_index` in one list would keep the nested target
and the flat fallback silently (the uncommitted worktree adds these checks). The current payload is clean
(my probe: 467/39/428/0, `lib.ok=true`), so this is a hardening item, not a
present error.

**N3 — should-fix (F10).** The confirm-green `SHADOW_PHASE` block and the §0
headline are stale (70/6 vs 66/10); the prose next to the block is correct. The
core claim (identical signatures) is independently reproduced, so this is an
evidence-hygiene fix: re-capture the block and label it if it is abridged.

**N4 — should-fix (F6).** Replace "the 24 (of 35) covered condition rows" with
the real split (4 condition rows have `blind>0`; 24 is the count of blind rows
across tasks and conditions), or just point at the `blind` column.

**N5 — nit.** F2/F4 are corrected only in parentheses: T01 :19-20 still leads
with "209 of 233", and report :549 still leads with `:421-425`/`:535` before
naming `:475`/`:499`/`:587`. Replace the primary text. Also the working-tree §9.10's "24 a
descendant" is 22 strict descendants + 2 self-targets in my count (the 69
ancestors are confirmed); not material.

**N6 — observation (the working tree is moving).** The uncommitted edits at
18:35/18:56-57 are a candidate response to N1/N2 and the F1/F4/F6 wording. I did
not gate-test them. The `_select_target` fix itself changed between 18:57:16
(return if the target is already active) and 18:57:41/18:57:56 (exit one frame and
re-enter the target, replacing it); the file was still changing when this section
was written. Commit the final form, run compile + suite 110 + suite 111 + probe
560 + the ancestor probe, then re-audit — do not treat this re-audit as a verdict
on the uncommitted code.

## Re-audit verdict

**AUDIT: FAIL** (on `d351712`; the uncommitted worktree is **not** audited — N6).
The F1 code/join is genuinely fixed on the consumer side — the flat join produces
the authored 39/428/0 in the running model, the interpreter honours
`NextSelectableSibling`, and every gate I re-ran or quoted is green with the same
FSM signature and the same patrol order/ticks — and F2 is fixed in the report,
the contract and the header. But **N1 is a new blocker** in the new path:
restoring the removed "target already active" guard is required before the
runtime can be called FIXED. The committed report still says the payload has no
`fallback` key (F1 :103-104, contradicting its own :116-117 table; the pending
18:35 edit fixes it), the confirm-green shadow block is the stale 70/6 output
(F10/N3), and F4/F6 are corrected only parenthetically (N4/N5). I did not patch
any of them; I re-ran the proofs and wrote this section only.

---

## Final re-audit

**AUDIT: PASS** — no blocker remains. N1, N2 and N4 are closed; N3 and N5 have
three stale text values and §9.10 still describes the old append semantics
(should-fix, listed below). No code, test or gate finding.

Re-audited tree: worktree `/home/john/Projects/TAT-2-rem-w9-p4`, branch
`rem/w9-p4`, HEAD **`8347ec6`** (`2241d28` runtime, `eed70ab` evidence, `d351712`
fallback, `8347ec6` ancestor/join fixes), base `f1bf058`. The code tree is clean;
`build/qa/w9/p4-report.md` has an uncommitted doc edit (+15/−3: the second-verdict
paragraph and the §W9-P4-2 test row) when this section was written — not mine,
and not part of `8347ec6`. All Godot runs were serialised under
`flock /tmp/opencode/tat2-godot.lock`, one at a time. I modified only this file.

Commands run (own runs; logs in `/tmp/opencode/`):

```
tools/godot --headless --path game --script $PWD/tools/check_scripts_compile.gd
tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd
tools/godot --headless --path game --script res://tests/test_w9p4_shadow.gd
tools/godot --headless --path game --script /tmp/opencode/p4_ancestor_probe.gd
TAT2_STATETREE=shadow tools/godot --headless --path game \
  --script res://tests/probe_statetree_shadow.gd -- --frames=560
tools/godot --headless --path game --script /tmp/opencode/p4_reaudit_probe.gd
```

## What reproduced

| check | result |
|---|---|
| compile | **186 checked, 0 broken** (19:01:29–19:01:34) |
| suite 110 | **`W9P4_STATETREE_SUMMARY: fails=0 checks=77`**; `P4LIB 21/459/467`; `P4TREES started=21 blocked=0 rows=140 trees=21` |
| suite 111 | **`W9P4_SHADOW_SUMMARY: fails=0 checks=20`**; **sig `-5750684789768048477` identical**; off `rows=0`, shadow `rows=66 ticks=241 transitions=10 visited=16 trees=ST_Guard,ST_Patrol reached_patrol=true` |
| ancestor scenario (my probe) | `PROBE_LIB ok=true errors=[]`; start frames **3**; ticks 1–3: **frames=3, duplicate_frames=0**, path `Root → A → B`, `fired=1,2,3` — **stable depth, no duplicate, exactly one fire per tick** |
| probe 560 | `P4TRACE … rows=101`; FSM wp 1→2@172, 2→3@320, 3→0@487 (same positions); `Move To` 142; `Delay` 144→174; `Rotate` **322→489 (167 ticks, 2.78 s)**; `P4SHADOW transitions=17`; `PROBE PASS fails=0` |
| join (my probe) | `PROBE_JOIN transitions=467 next=39 none=428 bad=0 nonzero_delay=0`; `ST_Patrol` state 4 transition 3 → `fallback=NextSelectableSibling delay_s=0.0 to=Has Broken Location?`; 21 trees × 60 base-binding ticks → `PROBE_REFUSED []` |
| live mission (`p4_mission.ndjson`, mtime 18:59, the `8347ec6` tree; quoted log, not re-run) | **209 rows, 4 guards**, ticks 0..3622, **29 transitions (8 distinct)**, 15 `NextSelectableSibling` + 14 `None`, 0 `transition_unmet`, 4 `task_block` (`STT Distraction Smart Objects`), 4 `Bool Compare`; matches the report |
| gate logs (`p4_gates.log`/`p4_post.log`, 18:27/18:31) | compile 186/0; `run_tests` `SUMMARY: fails=0` with **314** `^PASS`; `M2_SUMMARY: fails=0`; E2E **117/117** and **278/278**; five probes PASS; `RUNTIME_SMOKE PASS` off and shadow; `AUDIT PASS`; `GATE_RATCHET: PASS`; `PERF_GUARD_TEST PASS checks=78 fails=0`. These are the `d351712`-era runs; the changed files in `8347ec6` are the statetree runtime + suite + docs, and the statetree suites 110/111, probe 560 and the shadow mission trace above cover them. I did **not** re-run the full-game E2E on `8347ec6`. |

## F1-F13 + N1-N5 closure

| id | status | evidence |
|---|---|---|
| **F1** | **closed** | `8347ec6` §W9-P4-1 :103-104 now says the per-state records omit `fallback`/`delay` and the flat `transitions[]` carries them; the omission table :117-118 says "in the payload"; the code joins them. My probe: 467 / 39 / 428 / 0, `ST_Patrol` t3 joined, `lib.ok=true`. |
| **F2** | **closed** | §0 :43-44 and the table :116 say **203/233** condition instances; the caveat :335-339 explains the 209 fact-sheet count and the six property functions; T01 :19 says **203 of 233** and the parenthetical explains the 209. (The T01 acceptance example is stale — N5.) |
| **F3** | **closed** | Report §W9-P4-6 face row and §9.5 say **2.78 s / 167 ticks, the 3 s cap did not fire**; probe Rotate 322→489. |
| **F4** | **not fully closed** (same refs issue as N5) | Report :546-548 still leads with "`docs/FIDELITY_GAPS.md:421-425` and `:535` say the tree…" and only then names the correct `:475`, `:499`, `:587`. Replace the leading refs. |
| **F5** | **closed** | Report §W9-P4-2 :197 and §W9-P4-5 :319 say **nine** synthetic trees; the suite defines 9 (`SELECTOR/PRIORITY/PRIORITY2/EVENT/DELAY/UNKNOWN/FALLBACK/NOFALLBACK/ANCESTOR`). |
| **F6** | **closed** | Report :304-305 says the notes are a subset and the **`blind` column (94 task + 32 condition instances)** is the count — no "24 of 35" left. |
| **F7** | **closed** | Report §9.3 :487 says "0 emitters; 3 comment mentions"; `grep -rn StateTreeEvent game/src` → 3, all `##`. |
| **F8** | **closed** | Report §W9-P4-3 :244-246: "The arena also never leaves `NEUTRAL`… no detection ramp or alertness transition is exercised." |
| **F9** | **closed** | `shadow_runner.gd` computes `missing` from empty traces; report :250-254 says the suite asserts `started==21` + non-empty traces and the audit probe added 21/21 `start` rows. My probe (previous round) confirmed 21/21 `start`/`enter`/`block`; `P4TREES rows=140` unchanged. |
| **F10** | **not fully closed** | The §W9-P4-3 block is **66/10** now (:237), but §0 :38 still says "wrote **70** trace rows"; the actual run is 66. One-line fix. |
| **F11** | **closed** | `guard_bindings.gd` uses `< 1.0` in both `at_point` and `Move To`; report §W9-P4-6 says "<1.0 m … same gate". |
| **F12** | **closed** | Report §W9-P4-3 :220-221: "verified by inspecting `attach()` … and by suite 111 parsing the value, not by a behaviour test." |
| **F13** | **closed** | The first audit's pending report edit is in `d351712`; the code tree was clean at 18:33 and is clean at `8347ec6` (the only tracked modification is a later, uncommitted report doc edit — observation below). |
| **N1** | **closed** | `_select_target` now replaces an already-active target: `_exit_to(depth-1)` then `_enter_state(target)`, `_link_parent_child(depth-1)`. My probe: frames 3 / 0 duplicates / fires 1,2,3 (once per tick). Suite 110 `SYN_ANCESTOR` asserts `[0,1,2]`, 4 fires over 4 ticks, `max_frames==3`; suite 110 is 77/0. The 71 authored ancestor/self transitions no longer grow the stack. |
| **N2** | **closed** | Join requires `flat_count == per-state total` and `by_index.size() == total`, cross-checks `to_state_index` (numeric), `enabled`, `to_kind`, `trigger`, `priority`, `required_event`, `to_state` (null-normalised) and `conditions`; `shadow_runner._start()` refuses `ok=false`; suite 110's `_check_flat_join` asserts the real 467/39/428/0 and five corruption modes (missing, foreign from, unknown fallback, duplicate, target divergence). My probe independently: 467/39/428/0, t3 joined. |
| **N3** | **not fully closed** (same as F10) | The quote block is 66/10; §0 still 70. |
| **N4** | **closed** | The `blind`-row wording is replaced with the subset sentence (:304-305). |
| **N5** | **not fully closed** | 203/233 leads in the report (§0 :43-44, table :116, caveat :335-339) and in T01 :19. **But T01 :145's acceptance example still prints `condition_instances_with_params=209`**, and report :546-548 still leads the FIDELITY_GAPS refs with `:421-425`/`:535`. Both should quote 203 and the correct refs. |

## Code review of the new paths

* **`_select_target` replace-in-place** (`interpreter.gd:842-860`). For an active
  target (`frames[depth-1].state == target` and the same tree) it pops the target
  and its subtree and re-enters it; the parent keeps `has_child=true`. The probe
  shows `frames=3` on every tick, one fire per tick, no growth, no within-tick
  recursion (the tick's remaining passes are event-only). Re-entry re-runs the
  target's `task_exit`/`task_enter` and selection, which is the intended
  "restart the active state" semantics (stated in the commit). If `_enter_state`
  somehow failed after the pop, `_select_target` returns -1 and the frame is gone;
  that is unreachable for a target that was active under the same per-tick
  binding, and `_can_enter_deep` has already verified it.
* **`_can_enter_deep`** (`interpreter.gd:815-840`). Depth-bounded at 16, no
  memo, no mutation; it mirrors `_enter_state` for ordinary states: enter
  conditions, then any enterable child in authored order (the real selection
  tries them in order and rolls back, so "any" is the same answer). There are no
  linked-asset cycles in the payload (checked), and the authored max depth is 8
  < 16. Two asymmetries remain, both nits: (a) for a `LinkedAsset`/`Linked`
  target it requires the linked root/local target to be enterable, while
  `_enter_state` returns ENTER_OK for the link state and records `linked_refused`
  when the root refuses — 44 transitions target link states and 0 diverge under
  the base binding, and the measured guard path is unaffected; (b) tasks are not
  simulated, which §9.11 states.
* **Join** (`tree_model.gd:289-352`). All 467 indices are unique per tree, so the
  `index`-only join cannot mis-join today; the new count and field checks catch
  missing, duplicate, foreign and diverging records. My probe's synthetic
  flat/nested `to_state` mismatch is correctly rejected (`ok=false`).
* **Test strength.** The ancestor test fails on both the old duplicate (frames
  4, max 4) and the old no-op (frames 2) semantics; the join test exercises the
  real payload and five corruptions. 77/0 is real, not a weakened count.

## Residual should-fix / nits (no blocker)

1. **§0 :38 "wrote 70 trace rows"** — should be 66 (the block and prose already
   say 66). F10/N3.
2. **T01 :145 `condition_instances_with_params=209`** — the acceptance example
   must say **203**, matching the contract's own :19 and the report's :43.
3. **Report :546-548 FIDELITY_GAPS refs** — lead with `:475`/`:499`/`:587`
   instead of `:421-425`/`:535`. F4/N5.
4. **§9.10 :516-518** still says `_select_target` "appends the target" and calls
   the ancestor case exact; after the fix it **replaces** the active target for
   the 71 ancestor/self transitions. The counts (69/22/2) are right; the verb is
   stale.
5. **§W9-P4-2 :182** still lists "a candidate whose target cannot be selected is
   skipped" without the `Fallback = NextSelectableSibling` exception; the
   correction at :134 and the interpreter header have it.
6. **`_can_enter_deep` link-state strictness** (0/44 under the base binding, not
   exercised) and the 16-vs-32 depth bound (max authored depth 8) — add a
   sentence to the comment/§9.11, or leave as documented port decisions.
7. **Observation:** the working tree has an uncommitted `p4-report.md` doc edit
   (+15/−3, the second-verdict paragraph and the §W9-P4-2 test row) that is not
   in `8347ec6`; commit it with the final re-audit section. `build/qa/*` is
   gitignored, so this audit file needs `git add -f`.

## Final verdict

**AUDIT: PASS.** The code blocker N1 is fixed and independently reproduced
(stable depth, no duplicate, one fire per tick), the N2 join hardening is real
(467/39/428/0, five corruption tests, `ok=false` refused), N4 is closed, and
every gate I re-ran or quoted is green with the same FSM signature and the same
patrol order/ticks. N3 and N5 are not fully closed, and F4/§9.10 carry stale
wording — all four are text-only should-fix items that do not change any
measurement; fix them before integration if the evidence must be internally
consistent. I did not write the code, weaken a test or run a producer, and I
modified nothing except this audit file.


