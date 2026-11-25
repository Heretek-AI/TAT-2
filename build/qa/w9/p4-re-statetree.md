# W9-P4 — StateTree runtime semantics (research lane)

Scope: the 21 cooked UE 5.5 StateTrees in `extracted/json/AI/StateTrees/**`, the
generated payload `game/data/generated/gameplay/guard_behavior.json`
(`tat2.guard_behavior/1`, producer `tools/parse_state_tree.py`), and Epic's
StateTree documentation for the parts the dump cannot prove.

Nothing here was produced by running an engine. Every number below was measured
by reading the JSON. Where a claim is not measurable it carries a label.

## Headline for the lead

1. **Selection is deterministic and simple.** Only 2 selection behaviours occur
   (`TrySelectChildrenInOrder` 439, `TryEnterState` 20), **all 20 `TryEnterState`
   states are leaves**, and no state has a utility consideration
   (`UtilityConsiderationsNum == 0` on all 459). `TryEnterState` and
   `TrySelectChildrenInOrder` are therefore equivalent in this dataset.
2. **`OnStateCompleted` and `OnStateSucceeded` are not the same.** The first fires
   on success *or* failure (D10). `ST_Patrol` relies on both, and five states with
   children own `OnStateSucceeded`/`OnStateFailed` transitions, which means a
   parent inherits its selected child's status (§3.5).
3. **Priority order is `None < Low < Normal < Medium < High < Critical`.** `Medium`
   outranks `Normal` — the in-flight `tree_model.gd` table has these two swapped,
   which silently re-ranks 21 transitions (Appendix A.1).
4. **All authored parameters are recoverable from the raw dump, none from the
   payload.** `Nodes.Structs[k].InstanceTemplateIndex` → the array named by
   `InstanceDataHandle.Source` → the authored values (e.g.
   `AlertnessLevel = Neutral`, `duration = 1.0`/`100.0`). `guard_behavior.json`
   carries none of it (§6).
5. **14 of the 17 event tags have no producer anywhere in the dump**; the send
   sites that do exist are 4 tasks inside the trees (§4.3). The reactive half of
   `ST_Guard` / `ST_Civilian` depends on native systems (targeting, stims,
   knowledge, smart objects) that the port must substitute (§7).
6. **A candidate transition that cannot select its target is skipped, not fatal.**
   `ST_Subtree_Combat_ActivateAttack[3] "Wait"` proves it with two condition-less
   `OnTick` transitions (§3.2 fact 7, §4.5).

## Label key

| Label | Meaning |
|---|---|
| **PROVEN** | Directly measurable in the dump. The cited field exists and the value/count is what is stated. |
| **INFERENCE-FROM-DOCS** | Epic/UE header documentation says it; the dump cannot show it. URL cited. |
| **INFERENCE (authoring)** | The authored graph only functions if the rule holds (a structural necessity argument). Not a proof of engine behaviour. |
| **UNKNOWN** | Neither the dump nor the docs settle it. Stated as unknown; never filled with a guess. |
| **RECOMMENDATION** | A port decision proposed by this lane, explicitly not UE behaviour. |

Citation notation:

* `ST_Patrol` = `extracted/json/AI/StateTrees/SubTrees/ST_Patrol.json`, export `[0]`
  (`Properties` is that export's `Properties`). So
  `ST_Patrol.Properties.States[3].SelectionBehavior` is an exact JSON path.
* `payload:` = `game/data/generated/gameplay/guard_behavior.json`.
* `ST_Patrol[3]` = state index 3 in that tree.

### Doc sources used

| # | URL | Used for |
|---|---|---|
| D1 | https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-state-tree-in-unreal-engine | selection flow, task execution, transition evaluation order, evaluators/global tasks, data-flow table |
| D2 | https://dev.epicgames.com/documentation/en-us/unreal-engine/statetree-selectors-overview | selection-behaviour definitions, utility scoring |
| D3 | https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/StateTreeModule/EStateTreeRunStatus?application_version=5.5 | run-status enum |
| D4 | https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/StateTreeModule/FStateTreeTaskBase?application_version=5.5 | task contract (`EnterState`/`Tick`/`ExitState`/`StateCompleted`/`TriggerTransitions`), `bTaskEnabled`, `TransitionHandlingPriority` |
| D5 | https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/StateTreeModule/FStateTreeTransitionResult?application_version=5.5 | Source/Target/Next, `ChangeType` Sustained/Changed |
| D6 | https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/StateTreeModule/FStateTreeEvent?application_version=5.5 | event Tag/Payload/Origin |
| D7 | https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/StateTreeModule/FStateTreeExecutionContext?application_version=5.5 | `Tick`, `TickUpdateTasks`, `TickTriggerTransitions`, `SelectState`, `RequestTransition`, `ConsumeEvent` |
| D8 | https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/StateTreeTransitionPriority | priority enum values and the "first transition of highest priority" sentence |
| D9 | https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/StateTreeRunStatus | run-status member docs |
| D10 | https://uehow.web.fc2.com/Contents/Eng/UE4/Cpp/EngineHeader/StateTree.html | mirror of the UE 5.5 header doc-comments for `EStateTreeStateType`, `EStateTreeStateSelectionBehavior`, `EStateTreeTransitionTrigger`, `EStateTreeTransitionPriority`, `EStateTreeSelectionFallback`, `EStateTreeDataSourceType`, `FCompactStateTreeState`, `FCompactStateTransition`. Secondary source: these are the engine's own `/** */` strings, but they are quoted from a header mirror, not from Epic's site. |

---

## 0. What the dump actually contains (census)

| Measure | Value | Evidence |
|---|---|---|
| trees | 21 | 3 roots (`ST_Guard`, `ST_Civilian`, `ST_OffNavLink`) + 18 subtrees |
| states | 459 | sum of `Properties.States` |
| transitions | 467 | sum of `Properties.Transitions` |
| node records | 566 | sum of `Properties.Nodes.Structs` |
| … task nodes (`bTaskEnabled` present) | 326 | 127 carry `TaskClass` (Blueprint), 199 do not (native C++) |
| … condition nodes (`Operand` present) | 233 | 12 carry `ConditionClass` (Blueprint), 221 do not (native C++) |
| … other nodes | 7 | 1 global evaluator + 6 `Get Actor Location` property functions |
| root count | 20 trees with 1 root, `ST_InvestigateStims_Guard` with 2 | `States[].Parent.Index == 65535` |
| disabled states | 7 | `States[].bEnabled == false` |
| disabled transitions | 1 | `ST_Guard` t[14] (`OnEvent` `TargetChange` → `React to Player Tool`) |

**PROVEN** and important for scope: 199 of 326 task instances and 221 of 233
condition instances are *native C++ nodes whose class is not serialised*. The dump
gives their authored display name (`Nodes.Structs[].Name`) and their instance-data
template, but not their UClass. A runtime must map display names to behaviour by
hand.

Node-record layout (**PROVEN** by range checks, all 566 records):

```
state.TasksBegin/TasksNum                  -> Nodes.Structs[k]      (task)
state.EnterConditionsBegin/Num             -> Nodes.Structs[k]      (condition)
state.UtilityConsiderationsBegin/Num       -> Nodes.Structs[k]      (0 in this data)
transition.ConditionsBegin/Num             -> Nodes.Structs[k]      (condition)
Nodes.Structs[0].Name == "Difficulty Evaluator" with Source=GlobalInstanceData  (only ST_Guard)
```

Everything else in `Nodes.Structs` is either a task, a condition, or (6 cases) a
`Get Actor Location` property function reachable only through
`PropertyBindings.CopyBatches`. **PROVEN**: `ST_Guard` nodes 6 and 28, `ST_Patrol`
22, `ST_SmartObject_DefensiveSpot` 2, `ST_Subtree_Combat_Hauntstable` 14,
`ST_Subtree_ReviveNPC` 9 are the only `Nodes.Structs` entries not covered by any
state/transition range, and each has `DataSource: "EStateTreeBindableStructSource::PropertyFunction"`
in its `CopyBatches` record.

`ChildrenBegin..ChildrenEnd` is the **full pre-order descendant span**, not the
direct-child list. **PROVEN** for all 459 states in all 21 trees: for every state
`S`, the set `{i : ChildrenBegin ≤ i < ChildrenEnd}` is exactly the transitive
descendant set of `S`, and every direct child has `Depth == S.Depth + 1`. A
runtime must build its own parent→children index (the payload already does this in
`states[].children`).

---

## 1. State selection semantics

### 1.1 What is measured

| Field | Value | Count |
|---|---|---|
| `SelectionBehavior` | `TrySelectChildrenInOrder` | 439 |
| `SelectionBehavior` | `TryEnterState` | 20 |
| `Type` | `State` | 376 |
| `Type` | `LinkedAsset` | 45 |
| `Type` | `Group` | 35 |
| `Type` | `Linked` | 2 |
| `Type` | `Subtree` | 1 |
| `UtilityConsiderationsNum` | `0` | **459 (all)** |
| `Weight` | `1.0` | 457 |
| `Weight` | `2.0` / `0.5` | 1 / 1 |
| `bHasStateChangeConditions` | `false` | **459 (all)** |
| `bHasTransitionTasks` | `false` | **459 (all)** |

**PROVEN consequences**

1. No tree uses `None`, `TrySelectChildrenAtRandom`,
   `TrySelectChildrenWithHighestUtility`,
   `TrySelectChildrenAtRandomWeightedByUtility` or `TryFollowTransitions`.
   Selection in all 21 trees is **deterministic**.
2. No state has a utility consideration, so `Weight` never participates. The two
   non-unit weights (`ST_Subtree_Combat_Hauntstable[12]` = 2.0,
   `ST_Subtree_GeneralInvestigateStim[22]` = 0.5) are authored but inert.
3. **All 20 `TryEnterState` states are leaves** (`ChildrenBegin == ChildrenEnd`):
   `ST_Civilian[1][18]`, `ST_Guard[2][11][12][13][23][37][38][41][111]`,
   `ST_Patrol[4][17]`, `ST_Subtree_GeneralInvestigateStim[7][9][10][11][15][16]`,
   `ST_Subtree_ReviveNPC[12]`. Since `TrySelectChildrenInOrder` on a childless
   state "behaves like SelectState" (D2/D10), **the two measured behaviours are
   functionally identical in this dataset.** An interpreter only has to implement
   `TrySelectChildrenInOrder` correctly; `TryEnterState` differs only in the
   hypothetical case of a state with children, which does not occur here.
4. **No state has `bHasRequiredEventToEnter`.** That field name does not exist in
   the dump. The equivalent gate is
   `States[].RequiredEventToEnter.Tag != "None"` — **3 occurrences only**, listed
   in §4.4.

### 1.2 The selection algorithm

**INFERENCE-FROM-DOCS** (D1, "Selecting a new State", quoted verbatim):

> StateTree selects active States similarly to a behavior tree. State selection
> starts from root on the first Tick, and it continues down the tree evaluating
> each State's Enter Conditions.
> – If the Enter Conditions do not pass, the selection proceeds to the next
> sibling State.
> – If the Enter Conditions pass, and the State is a leaf State, it is selected as
> a new State.
> – If the State has child States, the same process continues on to the first
> child State until a leaf State is found.
>
> If a State has child States, yet none can be selected (their Enter Conditions
> fail), the State will not be selected even if all its Enter Conditions passed
> the test.

**INFERENCE-FROM-DOCS** (D2): `Try Select Children in Order` = "Try to select the
first child state in the order they appear in the child list. If no child states
are present, it behaves like Try Enter."

**INFERENCE-FROM-DOCS** (D1): "When a State is selected, the selected State and
all its parent States become active. All Tasks are executed for all active States,
starting from the root, down to the selected State."

So the selected set is always a **root→leaf path**, and every state on that path is
active. This is the "selected-state stack" the interpreter needs; it is not a
single state.

**PROVEN** support for the path model: the authored graph is a strict tree by
`Parent.Index` — every state has exactly one parent except the 22 roots (one per
asset, plus `ST_InvestigateStims_Guard`'s extra `Subtree` root) — so the active set
is a chain. Use `parent_index` for identity: **state names are not unique** — `ST_Guard` alone has 7 states
called `VO Line`, 6 called `Clear Focus`, 4 called `Delay`, 4 called
`Grab Target From Event`, 3 called `Move to and Use Smart Object`, 3 called
`Raise Alertness`, and `ST_Civilian` has 6 `VO Line`, 4 `Delay`, 4 `Raise
Alertness`, 4 `Grab Target From Event` (**PROVEN**).

### 1.3 `EStateTreeStateType` semantics

All doc strings below are **INFERENCE-FROM-DOCS** (D10, mirroring UE 5.5
`StateTreeTypes.h`); the shape claims next to them are **PROVEN**.

| Type | Doc string | Measured shape in this data |
|---|---|---|
| `State` | "A State containing tasks and child states." | 376. 280 leaf+has tasks; 1 leaf+no tasks (`ST_Subtree_Combat[23]`); 67 with children+no tasks; 28 with children+tasks. |
| `Group` | "A State containing just child states." | 35. **All 35 have `TasksNum == 0`**, all 35 have ≥1 child; 20 of the 35 carry enter conditions (e.g. `ST_Patrol[13]` has 1, `ST_Subtree_Flee[22]` has 3). |
| `LinkedAsset` | "A state that is linked to another StateTree asset (the execution continues on the Root state of the linked asset)." | 45, all leaves, all `TasksNum == 0`, **all 45 have `LinkedState.Index == 65535`** (no entry-state override), 11 of them also carry enter conditions. |
| `Linked` | "A state that is linked to another state in the tree (the execution continues on the linked state)." | 2, both in `ST_InvestigateStims_Guard`, both `LinkedState.Index = 8`, leaves, no tasks. |
| `Subtree` | "A subtree that can be linked to." | 1: `ST_InvestigateStims_Guard[8] "Substate Tree For Reaction"`, `Depth = 0`, `Parent = 65535`, and it is the **only** state whose `ParameterDataHandle.Source` is `SubtreeParameterData` (**PROVEN**, 1 of 459). |

**PROVEN**: `Linked` targets resolve inside the same asset —
`ST_InvestigateStims_Guard.Properties.States[5].LinkedState.Index == 8` and
`States[7].LinkedState.Index == 8`, and state 8 is the `Subtree` root. So
`Linked` + `Subtree` are one mechanism: a named second entry point into the same
asset. The payload records this as `linked_state_index` and `roots` (which is why
`ST_InvestigateStims_Guard` has two roots).

**INFERENCE-FROM-DOCS** (D1): `LinkedAsset` execution "continues on the Root state
of the linked asset" — i.e. the linked tree is *entered at its root and selected
normally*; the link is not a jump to a specific state. This matches the dump: no
`LinkedAsset` state in any of the 45 carries an entry index.

### 1.4 A Group with no tasks — does it enter, and does it complete?

* **It is evaluated and activated, not "selected".** *INFERENCE-FROM-DOCS* (D1):
  "Selector State: Refers to a State that has child States. This State will never
  be selected directly, and selection will continue to one of its child States."
  The Group still contributes its **enter conditions**, because selection
  evaluates them while walking down (D1). **PROVEN** that 20 of 35 Groups carry
  enter conditions, so the dump shows they are used as gates, not as labels.
* **It contributes no tasks.** **PROVEN** (35/35 `TasksNum == 0`).
* **It completes when its selected child completes.** *INFERENCE (authoring)*:
  only 11 of the 35 Groups own any transition — 6 `OnStateCompleted`, 3 `OnTick`,
  1 `OnEvent`, 1 `OnEvent + OnStateCompleted` (**PROVEN**); the other 24 own none
  and are pure branch collectors. The 6 with `OnStateCompleted` are the proof
  point: `ST_Subtree_Combat[24] "Has No Path to Target"`,
  `ST_Subtree_Flee[3] "Find Guard (Magical Knowledge)"`, `[8] "Spotted Guard, Get
  Help"`, `ST_TriggerFlee_Civilian[2] "Remember Target To Share"`, `[5] "Turn To
  Face Target"`, `[12] "VO Fallback (when TurnToFace ends too quickly)"`. A Group
  with **no tasks** can only reach a completion transition through its child's
  completion. `ST_Guard[3]`, the top-level reaction dispatcher, is the mixed case
  (10 `OnEvent` + `t[17] OnStateCompleted → Root`): it stays alive for events and
  resets to `Root` if the selected reaction ends without its own transition.
  The observer form is `ST_Subtree_Combat[18] "Combat Actions"`
  (`t[23] OnTick Normal → Clear Focus`, 2 conditions, no completion transition),
  and the branch-gate form is `ST_Patrol[10] "Reset Alertness"`
  `t[10] OnStateCompleted Fallback=NextSelectableSibling → "Is Patrol Point A
  Smart Object?"` (a Group with 1 enter condition) — if the Group cannot be
  entered, the fallback selects its next sibling.
* **UNKNOWN**: whether the Group's own completion status is `Succeeded`
  unconditionally or mirrors the child. The data distinguishes them
  (`OnStateCompleted` vs `OnStateSucceeded` are both used on parents — see §3.6),
  but not what a Group specifically reports.

### 1.5 `bCheckPrerequisitesWhenActivatingChildDirectly`

`true` on 78 states, `false` on 381 (**PROVEN**).

**INFERENCE-FROM-DOCS** (D10, `FCompactStateTreeState`): "Should state's required
event and enter conditions be evaluated when transition leads directly to it's
child."

This only matters for the **24 transitions that target a descendant** of their
owning state (**PROVEN**: target `Depth` > owner `Depth`). For those, the
intermediate states' enter conditions are skipped unless the flag is `true` on
them. Of the 78 flagged states, only **15** also have a real prerequisite
(`EnterConditionsNum > 0`), and they are the ones that actually change behaviour:
`ST_Guard[6]` (1), `ST_InvestigateStims_Guard[10]` (3), `[11]` (1), `[12]` (1),
`ST_Patrol[6]` (1), `[16]` (1), `ST_Subtree_Combat[7]` (2), `[12]` (1), `[21]`
(1), `[34]` (1), `[39]` (1), `ST_Subtree_Combat_ActivateAttack[1]` (1), `[2]`
(1), `ST_Subtree_ReviveNPC[7]` (1), `[11]` (1). The other 63 are flagged but have
no conditions, so the flag is inert for them.

---

## 2. Task lifecycle

### 2.1 `EStateTreeRunStatus`

| Member | Doc string | Numeric (C++ order) |
|---|---|---|
| `Running` | "Tree is still running." | 0 |
| `Failed` | "Tree execution has stopped on failure." | 1 |
| `Succeeded` | "Tree execution has stopped on success." | 2 |
| `Stopped` | "The State Tree was requested to stop without a particular success or failure state." | 3 |
| `Unset` | "Status not set." | 4 |

**INFERENCE-FROM-DOCS** (D3/D9). Note the brief's four-value list omits `Stopped`,
which exists in 5.5. `Unset` is the "not evaluated yet" value, not a failure.

### 2.2 The task contract

**INFERENCE-FROM-DOCS** (D4), quoting `FStateTreeTaskBase`:

| Member | Doc string | Consequence |
|---|---|---|
| `EnterState(Context, Transition)` → `EStateTreeRunStatus` | "Called when a new state is entered and task is part of active states." | Enter can already complete: returning `Succeeded`/`Failed` finishes the task in the enter frame. |
| `Tick(Context, DeltaTime)` → `EStateTreeRunStatus` | "Called during state tree tick when the task is on active state." | Only a task that returned `Running` from `EnterState` needs ticking. |
| `ExitState` | "Called when a current state is exited and task is part of active states." | |
| `StateCompleted` | "Called right after a state has been completed, but before new state has been selected." | A task can observe its own state completing. |
| `TriggerTransitions` | "Called when state tree triggers transitions." | Only reachable if `bShouldAffectTransitions` is set. |
| `bShouldCallTick`, `bShouldCallTickOnlyOnEvents` | "If set to true, Tick() is called." / "…only when there are events." | |
| `bShouldStateChangeOnReselect` | "the task will receive EnterState/ExitState even if the state was previously active." | Ties to `ChangeType` `Sustained` vs `Changed` (D5). |
| `bTaskEnabled` | "True if the node is Enabled (i.e. not explicitly disabled in the asset)." | |
| `TransitionHandlingPriority` | (no description) | Only used with `bShouldAffectTransitions`. |

**PROVEN** in the dump: `bTaskEnabled` is `true` on 325 task nodes and `false` on
exactly **1**: `ST_ClueGiving.Properties.Nodes.Structs[1]` ("STT Set Clue Giving
Enabled", owned by state 0 `Root`). A disabled task must never enter or tick, and
must not be counted as a completion source.

### 2.3 What "completed" means per state shape

The four shapes in this data (**PROVEN** counts):

| Shape | Count | Completion rule | Support |
|---|---|---|---|
| leaf, has tasks | 280 `State` (+ 47 `LinkedAsset`/`Linked` handled below) | the **first task to leave `Running`** decides the status (D1: "The first Task that completes its execution triggers a Transition") | INFERENCE-FROM-DOCS |
| leaf, **no** tasks, `State` | **1** (`ST_Subtree_Combat[23] "Fallback Behavior"`) | completes immediately on entry | INFERENCE (authoring): it has 0 tasks, 0 children, 0 enter conditions and exactly one `t[29] OnStateCompleted → "Decision"`. If a task-less leaf never completed, this state would be a permanent dead end and `Decision` would be unreachable from it. |
| with children, **no** tasks | 67 `State` + 35 `Group` + 1 `Subtree` = **103** | completes when the **selected child** completes, carrying the child's status | INFERENCE (authoring): **49 of the 103 own at least one transition** — 17 only `OnStateCompleted`, 14 `OnEvent + OnStateCompleted`, 9 only `OnEvent`, 5 only `OnTick`, 2 `OnStateCompleted + OnTick`, 1 all three, 1 `OnStateSucceeded + OnStateFailed` — and 54 own none (**PROVEN**). A state with no tasks cannot reach a completion transition any other way, e.g. `ST_Subtree_Combat[43] "Lost Target"` (0 tasks, 8 descendants) `t[46] OnStateCompleted → Succeeded`. |
| with children **and** tasks | **28** (`ST_Guard[0][26][85][97]`, `ST_Civilian[0][50]`, `ST_ClueGiving[0][4]`, `ST_InvestigateStims_Guard[2][3][9]`, `ST_Patrol[2][3]`, `ST_Subtree_Combat[5][8][9]`, `ST_Subtree_Combat_ActivateAttack[0]`, `ST_Subtree_Combat_Hauntstable[5][6][7]`, `ST_Subtree_Flee[0][25][28]`, `ST_Subtree_Lockdown[1][4][8]`, `ST_TriggerFlee_Civilian[6][9]`) | **UNKNOWN** | The authored tasks are *capability* tasks (`Add Targeting Groups`, `Persist Patrol Data`, `Rotate to Face`, `Repeatedly Trigger VO`, `Scoped Individual Knowledge`, `Register for Reaction Role`, `Set Combat Target`, `Lockdown`). If any of them completed eagerly the child branch would be dead code. INFERENCE (authoring): they must stay `Running` until exit. The dump cannot prove it because their classes are native. |

`LinkedAsset` / `Linked` states (47, **PROVEN** all leaf and task-less) complete
when the entered asset/state chain completes; **INFERENCE-FROM-DOCS** (D10)
`EStateTreeTransitionType::Succeeded` = "Stop State Tree or sub-tree and mark
execution succeeded", i.e. success inside a linked asset surfaces as the linked
state's success in the parent.

### 2.4 Latent vs instantaneous tasks — what the dump can and cannot prove

`guard_behavior.json.task_blueprints[*].functions` lists the functions **declared
on that Blueprint's generated class** (export type `Function` in the leaf dump).
**PROVEN** caveats that limit its use as a latency oracle:

* The leaf dumps contain only `[BlueprintGeneratedClass, Function…, CDO]` — **no
  `SuperStruct`**. A child BP that only overrides `GrabSmartObjectResults`
  (`STT_UseSmartObjectWithTargetActor_C`, `…Component_C`, `…SlotHandle_C`,
  `STT_UseSmartObjectWithClaimedHandle_C`) genuinely *inherits* the parent's
  `ReceiveLatentEnterState`; its short function list does not prove it is
  instantaneous. **UNKNOWN** for those four.
* **PROVEN**: 199 of 326 task instances are native classes with no function list
  at all, so their latency is **UNKNOWN** from the dump (that includes every
  `TATState Tree Task *`, `Move To`, `Delay Task`, `Run Env Query`, `Set Value
  (bool)`, `Get Location From Actor`, `Apply Gameplay Effect`, …). The native
  tasks whose names are self-describing (`Delay Task`, `Move To`,
  `Run Env Query`, `Trigger Gameplay Ability By Class`) are obviously latent, but
  that is reading the name, not the data.

What the function lists **do** prove (**PROVEN** per-leaf, then INFERENCE for
latency meaning):

| Blueprint task | Declared `Receive*` | Instances |
|---|---|---|
| `STT_ClearFocus_C` | `ReceiveLatentEnterState` only | 19 |
| `STT_DistractionSmartObjects_C` | `ReceiveExitState`, `ReceiveLatentEnterState` | 1 |
| `STT_EquipUnequip_C` | `…EnterState`, `ReceiveLatentTick` | 2 |
| `STT_GetDistanceBetweenActors_C` | `ReceiveLatentTick` **only** (no enter) | 1 |
| `STT_InteractWithInteractable_C` | `…EnterState`, `ReceiveLatentTick`, `ReceiveExitState` | 1 |
| `STT_RememberTargetToShare_C` / `_Location_C` | `ReceiveLatentEnterState` only | 1 / 1 |
| `STT_ReportNoise_C` | `ReceiveLatentEnterState` only | 4 |
| `STT_RequestVOLine_C` | `…EnterState`, `ReceiveLatentTick` | 31 |
| `STT_RequestVOLine_Conditional_C` | `…EnterState`, `ReceiveLatentTick` | 12 |
| `STT_RequestVOLine_Repeating_C` | `…EnterState`, `ReceiveLatentTick`, `OnTimer`, `ReceiveStateCompleted` | 3 |
| `STT_SendGameplayEvent_C` | `ReceiveLatentEnterState` only | 1 |
| `STT_SetAttitudeToTarget_C` | `ReceiveLatentEnterState` only | 7 |
| `STT_SetClueGivingEnabled_C` | `…EnterState`, `ReceiveExitState` | 1 |
| `STT_SetContextualLocationInUse_C` | `…EnterState`, `ReceiveExitState` | 1 |
| `STT_SetFocus_C` / `_Location_C` | `ReceiveLatentEnterState` only | 15 / 1 |
| `STT_SetSharePartner_C` | `ReceiveLatentEnterState` only | 2 |
| `STT_ShareTarget_C` | `ReceiveLatentEnterState` only | 1 |
| `STT_TriggerAndWaitForAnimation_C` | `…EnterState`, `ReceiveLatentTick`, `ReceiveExitState` | 2 |
| `STT_TriggerGameplayAbilityWithEvent_C` | `…EnterState`, tag/timeout callbacks, `ReceiveExitState` | 4 |
| `STT_TryClaimContextualLocation_C` | `…EnterState`, `ReceiveExitState` | 1 |
| `STT_TryForgetSharePartner_C` | `…EnterState`, `ReceiveExitState` | 1 |
| `STT_UseSmartObjectBase_C` | `…EnterState`, `ReceiveExitState`, move callbacks | **0 direct instances** — parent of the 4 subclasses below |
| ↳ `STT_UseSmartObjectWithTargetActor_C` | (`GrabSmartObjectResults` only; inherits the base) | 6 |
| ↳ `STT_UseSmartObjectWithTargetComponent_C` | (`GrabSmartObjectResults` only) | 1 |
| ↳ `STT_UseSmartObjectWithTargetSlotHandle_C` | (`GrabSmartObjectResults` only) | 5 |
| ↳ `STT_UseSmartObjectWithClaimedHandle_C` | `…EnterState`, `ReceiveExitState`, move callbacks | 1 |

**INFERENCE-FROM-DOCS** (Epic's Blueprint task mapping): a Blueprint implementation
of a *latent* StateTree task overrides `ReceiveLatentEnterState` (the task stays
running), and a latent task that needs periodic work overrides
`ReceiveLatentTick`. Therefore any BP task whose only `Receive*` is
`ReceiveLatentEnterState` is **latent** (it must be exited, never completes on its
own): `ClearFocus`, `RememberTargetToShare*`, `ReportNoise`, `SendGameplayEvent`,
`SetAttitudeToTarget`, `SetFocus*`, `SetSharePartner`, `ShareTarget`,
`SetClueGivingEnabled`, `TryClaimContextualLocation`, `TryForgetSharePartner`.
That is a strong, usable classification for the port.

### 2.5 `TransitionHandlingPriority`

**PROVEN**: every one of the 326 task nodes carries
`TransitionHandlingPriority: "EStateTreeTransitionPriority::Normal"` — no other
value occurs. Combined with `bHasTransitionTasks == false` on all 459 states, no
task in these 21 trees participates in transition handling, so the field is inert
and transition arbitration only sees authored `Transitions[]`.

---

## 3. Transition arbitration

### 3.1 What is measured

| Field | Values | Count |
|---|---|---|
| `Trigger` | `OnStateCompleted` | 284 |
| | `OnEvent` | 89 |
| | `OnStateSucceeded` | 38 |
| | `OnStateFailed` | 36 |
| | `OnTick` | 20 |
| `Priority` | `None` | 358 |
| | `Normal` | 67 |
| | `Medium` | 21 |
| | `Critical` | 12 |
| | `High` | 9 |
| | `Low` | **0** |
| `State` (target) | a state index | 417 |
| | `65534` (`Succeeded`) | 35 |
| | `65533` (`Next`) | 15 |
| | `65535` (`Invalid`) | 0 |
| `Fallback` | `None` | 428 |
| | `NextSelectableSibling` | 39 |
| `Delay.duration` | `0` | **467 (all)** |
| `Delay.RandomVariance` | `0` | **467 (all)** |
| `bTransitionEnabled` | `true` / `false` | 466 / 1 |
| `ConditionsNum` | 0 / 1 / 2 / 3 | 375 / 34 / 56 / 2 |

**PROVEN** correlations worth stating:

* Every `OnStateCompleted` / `OnStateSucceeded` / `OnStateFailed` transition has
  `Priority = None` (284 + 38 + 36 = 358). Priorities only appear on `OnEvent`
  (89) and `OnTick` (20).
* Every `OnTick` transition is `Priority = Normal`.
* No transition authored a delay, so **time-based arbitration is unused**; the
  runtime does not need transition timers for this data (it still needs `Delay`
  for completeness, but every value is 0).

### 3.2 The ordering rule

Two doc sentences, verbatim:

* **D8** (`EStateTreeTransitionPriority`): *"Transition priority. When multiple
  transitions trigger at the same time, the first transition of highest priority
  is selected."*
* **D1**: *"Transitions are evaluated starting from the leaf State and
  progressing upwards toward the root. During this process, the first Transition
  that succeeds and leads to State selection is selected."*

**INFERENCE-FROM-DOCS (reconciliation)**: the only reading that satisfies both is
*collect every transition that triggers this tick across all active states, then
pick the highest `Priority`; ties go to the earliest in evaluation order
(leaf→root, and within a state the authored array order)*. Reading it as "the leaf
wins outright" contradicts D8; reading it as "priority is global and order is
irrelevant" contradicts D1.

**UNKNOWN**: whether UE compares priority *within* a state only and then walks
leaf→root (which would let a leaf's `None` beat a Root's `Critical`). The docs do
not say, and the dump cannot be executed. The discriminating case in this data is
`ST_Guard.Root`'s three `Critical` `GameplayTagChange` transitions (`t[0..2]`): if
a leaf task completes on the same tick that `In Smoke` becomes true, the
reconciliation fires `In Smoke`; the "leaf wins" reading ignores the forced state.
That is exactly the "Forced States" branch, so it is testable: a port should add a
unit test that completes a leaf and raises the tag in one tick and assert which
state is entered.

**PROVEN** facts the interpreter must encode:

1. **Enum order is `None(0) < Low(1) < Normal(2) < Medium(3) < High(4) < Critical(5)`.**
   D8 gives the numeric values: `NORMAL = 2`, `MEDIUM = 3`. *`Medium` outranks
   `Normal`.* (This is the one place the in-flight `tree_model.gd` table is wrong;
   see Appendix A.)
2. `None` is the **lowest** priority, not "no priority / highest". 358 of 467
   transitions are `None`, i.e. the default and weakest.
3. Critical exists and is used **only** on `OnEvent` transitions that force a
   state: `ST_Guard.Root` `t[0..2]` (`GameplayTagChange` → `In Smoke` /
   `Unconcious` / `Cower`), `ST_Guard[1] "Standard States"` `t[4]` (`TargetChange`
   → `Combat`, 2 conditions), `ST_Guard[105]` `t[130]` (→ `Combat`), and
   `ST_Civilian` `t[0]`, `t[7]`, `t[13]`, `t[26]`, `t[31]`, `t[37]`, `t[44]`
   (`GameplayTagChange` → `In Smoke`, `TargetChange` → `Spotted a hostile
   player`). These are the "Forced States" mechanism; the whole design depends on
   a Critical transition on an *ancestor* beating what the active leaf is doing.
4. Three same-priority Critical transitions on one state
   (`ST_Guard.Root` t[0], t[1], t[2], all `GameplayTagChange`) can only be ordered
   by **authored array order**: first match wins. That is the same tiebreak D8's
   "first transition" implies.
5. Authored order is preserved in the dump: `Transitions[]` is a flat array and a
   state's slice is `TransitionsBegin..+TransitionsNum` in authoring order.
   `ST_Guard[3]` demonstrates intent: two `High` `StimChange` transitions, the
   condition-gated damage one (`t[7]`, 1 condition) before the generic one
   (`t[13]`, 0 conditions).
6. **`OnTick` always outranks a completion transition on the same state**, because
   `OnTick` is `Normal` and every completion transition is `None`. Example:
   `ST_Guard[89] "Intruder no longer suspicious"` has `t[113] OnTick Normal
   (2 conditions) → React to spotting Intruder` *before* `t[114] OnStateCompleted
   None → Root`, and `ST_Guard[92]` mirrors it.
7. **A candidate that cannot select its target is skipped, not fatal.** D1 says
   "the first Transition that succeeds *and leads to State selection*". The proof
   is `ST_Subtree_Combat_ActivateAttack[3] "Wait"` (§4.5, §3.6): two condition-less
   `OnTick → <enter-conditioned state>` transitions on one state; the second is
   only reachable under the skip reading.

### 3.3 Which states are evaluated ("descendant" vs "directly selected")

**INFERENCE-FROM-DOCS** (D1): all active states on the root→leaf path, leaf first.
**PROVEN** that the graph needs this: 69 transitions target an **ancestor** of
their owner (e.g. `ST_Guard[89] t[114] → Root`, `ST_Subtree_Combat[19] t[24] →
Decision`, `ST_Patrol[19] t[18] → Patrol`), and 24 target a **descendant**. A model
that only let the selected leaf fire transitions could not express either.

`FStateTreeTransitionResult` (D5) makes the same point from the other side:
"Source is the state where the transition started, Target describes the state
where the transition pointed at, and Next describes the selected state. … the
Transition state can be a selector state, in which case the children will be
visited until a leaf state is found."

### 3.4 `Succeeded` (65534) and `Next` (65533)

**INFERENCE-FROM-DOCS** (D10, `EStateTreeTransitionType`):

* `Succeeded` — "Stop State Tree or sub-tree and mark execution succeeded."
* `Next` — "Transition to the next sibling state."

**PROVEN** usage:

* 35 `Succeeded` — **PROVEN** split: 10 on states that *have* descendants (e.g.
  `ST_Patrol[3] "Patrol"` `t[1] OnStateSucceeded → Succeeded`,
  `ST_Subtree_Combat[7] "Chaser"` `t[9] OnStateCompleted → Succeeded`,
  `ST_Subtree_Flee[1] "Flee"` `t[1]`, `ST_Standby_Guards[0] Root` `t[0]`), 10 on
  `Linked`/`LinkedAsset` states that end a sub-tree, 15 on ordinary leaves.
  Meaning in a port: success of the **current frame** — the linked asset if inside
  one, otherwise the whole tree.
* 15 `Next` — 12 of the 15 owners have a following sibling (**PROVEN**); the 3
  exceptions are `ST_InvestigateStims_Guard[7] "Run Substate Tree without Event"`,
  `[12] "Short Investigation"` and `[16] "Standby Behavior"`, each the last child
  of its parent (**PROVEN**). **UNKNOWN**: what UE does when `Next` has no sibling
  — the dump does not say and the doc does not cover it. A runtime must at minimum
  not crash; treating it as "no transition selected, stay" is the RECOMMENDATION.

### 3.5 `OnStateCompleted` vs `OnStateSucceeded` — the ST_Patrol case

**INFERENCE-FROM-DOCS** (D10, `EStateTreeTransitionTrigger`):

| Trigger | Doc string |
|---|---|
| `OnStateCompleted` | "Try trigger transition when a state succeeded or failed." |
| `OnStateSucceeded` | "Try trigger transition when a state succeeded." |
| `OnStateFailed` | "Try trigger transition when a state failed." |
| `OnTick` | "Try trigger transition each State Tree tick." |
| `OnEvent` | "Try trigger transition on specific State Tree event." |

So `OnStateCompleted` = **either** outcome; `OnStateSucceeded`/`OnStateFailed` are
the discriminated forms. This is the whole distinction and it is documented, not
inferred.

`ST_Patrol` (**PROVEN** paths, the concrete sequence):

```
Root[0]                       State, 0 tasks
 ├─ Set Alertness[1]          State, 1 task, 1 enter cond
 │    t[0] OnStateCompleted                                  → Distractable Window[2]
 └─ Distractable Window[2]    State, 1 task (STT Distraction Smart Objects), descendants 3..20
     └─ Patrol[3]             State, 2 tasks, 7 children
          t[1] OnStateSucceeded                                → Succeeded      (stop ST_Patrol, success)
          t[2] OnEvent Normal DistractionEvent                 → Extract distraction Event[21]
          ├─ Set Next Patrol Path Point[4]  TryEnterState, 1 task
          │    t[3] OnStateSucceeded  Fallback=NextSelectableSibling → Has Broken Location?[5]
          │    t[4] OnStateFailed                              → Failed[19]
          ├─ Has Broken Location?[5]       State, 0 tasks, 1 enter cond, 4 descendants
          │    t[5] OnStateCompleted  Fallback=NextSelectableSibling → Reset Alertness[10]
          │    └─ Raise alertness[6] → Move To Broken Point[7] → Set Alertness[8] → Complete[9]
          │         (each OnStateCompleted → the next; [9] t[9] → Set Next Patrol Path Point[4])
          ├─ Reset Alertness[10]
          │    t[10] OnStateCompleted Fallback=NextSelectableSibling → Is Patrol Point A Smart Object?[11]
          ├─ Is Patrol Point A Smart Object?[11]   Group, 1 enter cond
          ├─ Is Patrol Point A Patrol to Location?[13] Group, 1 enter cond
          │    └─ Move To Point[14] → Say a Voice Line[15] → Rotate[16] → Delay[17] → Complete Segment[18]
          │         ([14] t[13] OnStateFailed → Patrol[3])
          └─ Failed[19]  (Delay 100 s, then t[18] OnStateCompleted → Patrol[3])
```

Why both triggers appear in one tree, and what a runtime must get right:

* `Patrol[3]` uses **`OnStateSucceeded`** because it only wants to stop the patrol
  when its child branch *succeeded*. Its children loop
  (`Complete[9] → Set Next Patrol Path Point[4]`), so `Succeeded` is the exit.
* `Set Alertness[1]`, `Has Broken Location?[5]`, `Reset Alertness[10]`,
  `Raise alertness[6]`, `Move To Broken Point[7]`, `Set Alertness[8]`,
  `Complete[9]`, `Move To Point[14]`→`Complete Segment[18]` all use
  **`OnStateCompleted`**, i.e. "move on whatever happened". `Move To Point[14]` is
  the exception that discriminates: `t[12] OnStateSucceeded → Say a Voice Line`
  and `t[13] OnStateFailed → Patrol`. A port that collapses `OnStateCompleted`
  into `OnStateSucceeded` breaks `Move To Broken Point`/`Complete` whenever a child
  fails, and a port that treats a parent as always succeeding breaks
  `Patrol[3]`'s exit.
* **PROVEN** that parents really do inherit the child's discriminated status:
  **five** states own `OnStateSucceeded`/`OnStateFailed` *and* have children
  (six such transitions) — `ST_Patrol[3]` (Succeeded),
  `ST_InvestigateStims_Guard[3]` (Failed), `[10]` (Succeeded + Failed),
  `ST_Subtree_Flee[25]` (Failed), `ST_Subtree_Lockdown[4]` (Failed). Without
  status propagation those six transitions are unreachable.

**RECOMMENDATION**: represent per-state status as
`Unset | Running | Succeeded | Failed | Stopped`; on child completion set the
parent's status to the child's, and fire `OnStateCompleted` for `Succeeded` *or*
`Failed`, `OnStateSucceeded` only for `Succeeded`, `OnStateFailed` only for
`Failed`.

### 3.6 `Fallback` and `bConsumeEventOnSelect`

**INFERENCE-FROM-DOCS** (D10):

* `EStateTreeSelectionFallback` — "Fallback behavior indicating what to do after
  failing to select a state." `None` = "No fallback"; `NextSelectableSibling` =
  "Find next selectable sibling, if any, and select it."
* `FCompactStateTransition.Fallback` — "Fallback of the transition if it fails to
  select the target state."
* `FCompactStateTransition.bConsumeEventOnSelect` — "If set to true, the required
  event is consumed (later state selection cannot react to it) if state selection
  can be made."

**PROVEN**: 39 transitions use `NextSelectableSibling`, 428 use `None`. Of the 39,
19 target a state that can fail selection (`EnterConditionsNum > 0` or has
children) and 20 target a state that cannot, which is consistent with `Fallback`
being *inert* on the 20. The canonical use is `ST_Patrol t[3]`: `Set Next Patrol
Path Point` succeeds, the transition targets `Has Broken Location?` (which has an
enter condition), and `Fallback = NextSelectableSibling` sends execution to the
next sibling (`Reset Alertness`) when the condition is false. That is the
"if/else" idiom of this AI.

**PROVEN** that the default is *not* "fall through": 173 transitions with
`Fallback = None` target a state that can fail to select. If failure fell through
silently, those would be indistinguishable from `NextSelectableSibling`.

**INFERENCE-FROM-DOCS + PROVEN-by-authoring**: when a target cannot be selected
and `Fallback == None`, that *candidate* is skipped and the next candidate in
arbitration order is considered (D1: "the first Transition that succeeds **and
leads to State selection** is selected"). If no candidate can commit, nothing
changes this tick. The proof case is
`ST_Subtree_Combat_ActivateAttack[3] "Wait"` (§4.5): two condition-less `OnTick`
transitions, both `Fallback = None`, both targets enter-conditioned — the only
reading that keeps `Activate` reachable is "skip the failed candidate".

`bConsumeEventOnSelect` is `false` on exactly 2 states (**PROVEN**):
`ST_Patrol[21] "Extract distraction Event"` and `ST_Subtree_Combat[6] "Extract
Reaction Role from Event"` — both are the `RequiredEventToEnter` consumers, so the
event must survive selection long enough for the state (and its sibling listener)
to read it. **INFERENCE-FROM-DOCS**: with `true` (the default, 457 states) the
event is removed once selection succeeds, so a second handler on the same event in
the same tick cannot see it.

---

## 4. Events and observers

### 4.1 The event object

**INFERENCE-FROM-DOCS** (D6) `FStateTreeEvent`: `Tag` (FGameplayTag),
`Payload` (FInstancedStruct, optional), `Origin` (FName, optional who-sent info).
The context owns an **event queue** (D7: `GetEventQueue`, `ConsumeEvent`
"Consumes and removes the specified event from the event queue",
`ForEachEvent`), plus `GetEventsToProcess` for the current tick. So events are
queued and drained per tick, not delivered by callback.

### 4.2 The 17 authored event tags and their listeners

**PROVEN** (transition `RequiredEvent.Tag`, 89 `OnEvent` transitions):

| Tag | listeners | notable owner |
|---|---|---|
| `StateTreeEvent.TargetChange` | 48 | main driver of `ST_Guard`/`ST_Civilian` reactions |
| `StateTreeEvent.StimChange` | 14 | damage vs generic stim reactions |
| `StateTreeEvent.GameplayTagChange` | 10 | forced states (`In Smoke`, `Unconcious`, `Cower`) |
| `StateTreeEvent.ConversationEvent` | 2 | `ST_Guard[3]`, `ST_Guard[83]` |
| `StateTreeEvent.ReactionRoleChange` | 2 | `ST_InvestigateStims_Guard[4]`, `ST_Subtree_Combat[5]` |
| `StateTreeEvent.LockdownNewAlarmGuard` | 2 | `ST_Subtree_Lockdown[4][7]` |
| `StateTreeEvent.Civilian.Flee` | 1 | `ST_Civilian[0] Root`, High |
| `StateTreeEvent.ClueChange` | 1 | `ST_Civilian[2]`, 2 conditions |
| `StateTreeEvent.ShareTarget` | 1 | `ST_Guard[3]` |
| `StateTreeEvent.LockdownEvent` | 1 | `ST_Guard[17] Patrolling` |
| `StateTreeEvent.DistractionEvent` | 1 | `ST_Patrol[3]` |
| `StateTreeEvent.ReactionEventEnd` | 1 | `ST_Standby_Guards[0] Root → Succeeded` |
| `StateTreeEvent.SharePartnerLost` | 1 | `ST_Subtree_Flee[1]` |
| `StateTreeEvent.ConversationEvent.Response` | 1 | `ST_Subtree_Flee[16]` |
| `StateTreeEvent.AbandonLockdown` | 1 | `ST_Subtree_Lockdown[1]` |
| `StateTreeEvent.LockdownHoldPosition` | 1 | `ST_Subtree_Lockdown[4]`, Medium |
| `StateTreeEvent.LockdownGuardLeaving` | 1 | `ST_Subtree_Lockdown[7]` |

**PROVEN** event-data plumbing: exactly **89** `PropertyBindings.SourceStructs`
entries have `DataSource: "EStateTreeBindableStructSource::TransitionEvent"` — one
per `OnEvent` transition. So an `OnEvent` transition exposes its event (tag +
payload) as a bindable data source to its own conditions.

### 4.3 Producers — what the dump proves and what it does not

Only **four** send sites exist inside the recovered assets (**PROVEN**, resolved
through `Nodes.Structs[].InstanceTemplateIndex` → `DefaultInstanceData`):

| Site | Task | Authored parameters |
|---|---|---|
| `ST_Guard[70]` | `TATState Tree Send Event to NPC` (native) | `EventTagToUse = StateTreeEvent.ConversationEvent.Response` |
| `ST_Guard[77]` | same | same |
| `ST_Subtree_Flee[14]` | `TATState Tree Send Event to NPC Share Target` (native) | `EventTagToUse = StateTreeEvent.ShareTarget`, `DelayBeforeVoiceLine = 2.0`, `SharedTargetLocation`, `VoiceLineToPlay = None` |
| `ST_TriggerFlee_Civilian[16]` | `TATState Tree Send Event to NPC` (native) | `EventTagToUse = StateTreeEvent.Civilian.Flee` |

Plus one Blueprint sender: `ST_Guard[16]` uses `STT_SendGameplayEvent_C` with
`Event Tag = AI.Event.Escalation.Reset` — note that is a **GAS** tag namespace, not
`StateTreeEvent.*`.

**PROVEN negative result**: grepping the entire `extracted/json/` tree for the 14
remaining `StateTreeEvent.*` tags finds **no asset outside `AI/StateTrees/`** that
mentions them. Their producers are native C++:
`StateTreeEvent.TargetChange` and `StimChange` almost certainly come from
`TATStateTreeTargetingComponent` / `TATAIStimDatabase` (which are visible as
components on `AIC_StateTreeBase` but whose source is not in the dump), and
`GameplayTagChange` from the controller's tag listener
(`AIC_StateTreeBase.Properties` has `DisableBrainTags: ["Condition.Negative"]` and
functions `ListenForConditionTags` / `OnGameplayTagChanged_*`). **UNKNOWN** which
exact component emits which tag: the dump does not contain the send calls.

The `TATStateTreeSendEvent*` name in the brief is a **display name only**; the
native task's UClass is not serialised, so the dump proves the *behaviour* (send
tag `X` to `TargetNPC`) and not the C++ symbol.

### 4.4 `RequiredEventToEnter` — every occurrence

**PROVEN**, all three, with the full raw record:

| Tree / state | Tag | Payload struct | `bConsumeEventOnSelect` | `EventDataIndex` |
|---|---|---|---|---|
| `ST_InvestigateStims_Guard[6] "Extract Reaction Role from Event"` | `StateTreeEvent.ReactionRoleChange` | `Class'TATAITargetingEvent_ReactionRoleChanged'` | `true` | `6` |
| `ST_Patrol[21] "Extract distraction Event"` | `StateTreeEvent.DistractionEvent` | `Class'TATAITargetingEvent_DistractionEvent'` | `false` | `3` |
| `ST_Subtree_Combat[6] "Extract Reaction Role from Event"` | `StateTreeEvent.ReactionRoleChange` | `Class'TATAITargetingEvent_ReactionRoleChanged'` | `false` | `4` |

**PROVEN** correlations (3/3):

1. `EventDataIndex != 65535` on exactly these 3 states — the event payload's
   storage slot.
2. The transitions that **lead into** these states carry the same typed
   `RequiredEvent.PayloadStruct`: `ST_InvestigateStims_Guard t[2]`,
   `ST_Patrol t[2]`, `ST_Subtree_Combat t[6]`. All other 464 transitions have
   `PayloadStruct: null`.
3. Their tasks are the `Extract … from Event` tasks, which read the payload.
4. `PropertyBindings.SourceStructs` has exactly **3** entries with
   `DataSource: "EStateTreeBindableStructSource::StateEvent"` — one per such
   state (**PROVEN**), the bindable view of the state's required event.

So the idiom is fully recoverable: *an `OnEvent` transition with a typed payload
selects a state that also requires that event; the payload is stored at
`EventDataIndex`; the state's task reads it.*

### 4.5 Observers (`OnTick`)

**PROVEN**: 20 `OnTick` transitions, all `Normal`. **18 carry conditions** (7 with
1, 11 with 2) and **2 carry none**: `ST_Subtree_Combat_ActivateAttack[3] "Wait"`
`t[2] → Ranged Attack[2]` and `t[3] → Activate[1]`, both `Normal`, both
`Fallback = None`, both targets carrying an enter condition. That pair is the
ordered "try Ranged Attack, else Activate" branch, and it only works if a
transition whose target fails to select is **skipped in favour of the next
candidate** (D1: "the first Transition that succeeds *and leads to State
selection* is selected"). If failure aborted arbitration, `Activate` would be
unreachable whenever `Ranged Attack` was not selectable and `Wait` would stall
forever.

The condition-less pair also proves that a `RequiredEvent`-less `OnTick` fires on
the next evaluated tick, not "when the state feels finished" — the state's own task
does not gate it.

The conditioned observers are the "watch while running" mechanism, e.g.

* `ST_Guard[85] "Try Find Intruder"` `t[109] OnTick (1 cond) → React to spotting Intruder`
* `ST_Subtree_Combat[18] "Combat Actions"` `t[23] OnTick (2 conds) → Clear Focus`
* `ST_Subtree_Combat[43] "Lost Target"` `t[45] OnTick → Found Target` **and**
  `t[46] OnStateCompleted → Succeeded` **and** `t[47] OnTick → Succeeded`
* `ST_Civilian[27]` / `ST_Guard[89]` / `[92]` mix `OnTick` with `OnEvent` and/or
  `OnStateCompleted` on the same state (9 states do this, **PROVEN**).

**INFERENCE-FROM-DOCS** (D1): "Other Transitions can be marked as Tick and are
tested on each tick." So observers are evaluated every tick on every active state,
and the arbitration rule of §3.2 decides whether they win.

### 4.6 State tags

**PROVEN**: 456 states have `Tag = None`; 3 carry a gameplay tag:
`ST_Guard[91] "Intruder Reaction"` = `AI.StateTree.IntruderInitialReaction`,
`ST_Guard[113] "Combat"` = `AI.StateTree.Combat`,
`ST_Guard[125] "Combat"` = `AI.StateTree.ForcedAgro`. The dump does not show who
queries them (**UNKNOWN**; most likely the debug HUD or telemetry).

---

## 5. Global evaluators, context data, parameters, bindings

### 5.1 Field-name corrections

The dump has **no `GlobalEvaluators` array**. The raw `Properties` keys are
(**PROVEN**, present on 1 tree only):

```
ST_Guard.Properties.EvaluatorsNum          = 1
ST_Guard.Properties.GlobalTasksBegin       = 1     # index into Nodes.Structs; globals occupy [0,1)
ST_Guard.Properties.NumGlobalInstanceData  = 1
```

`payload:stats.st_guard.global_evaluators == 1` is the producer's copy of
`EvaluatorsNum`, not a count of an array. The one evaluator node is
`ST_Guard.Properties.Nodes.Structs[0]`:

```json
{"Name": "Difficulty Evaluator",
 "BindingsBatch": {"Value": 65535},
 "InstanceTemplateIndex": {"Value": 0},
 "InstanceDataHandle": {"Source": "EStateTreeDataSourceType::GlobalInstanceData",
                        "Index": 0, "StateHandle": {"Index": 65535}}}
```

and its template is
`ST_Guard.Properties.DefaultInstanceData.Data.InstanceStructs.Structs[0] =
{"Difficulty": "ETATDifficulty::Normal", "VigilantLoopCount": 1}` (**PROVEN**).

### 5.2 Evaluators and global tasks

**INFERENCE-FROM-DOCS** (D1, "Data Flow"):

> **Evaluators** … "can execute custom code when the tree starts, stops, and on
> each Tick. The properties of an Evaluator can be bound to Parameters or Context
> Data, or other Evaluators that come before in the Evaluator list."
> **Global Tasks** "are started before the Root State in the tree" … "active
> between the Tree Start and Stop events."

**PROVEN**: no tree in this data uses a global *task* (`GlobalTasksBegin` is absent
everywhere except `ST_Guard`, where it equals `EvaluatorsNum`, i.e. zero global
tasks). `ST_Guard`'s single evaluator is a difficulty evaluator.

**Runtime requirement**: one evaluator slot with `EnterState` → `Tick` → `ExitState`,
ticked before the state tasks, whose outputs are bindable. For this data it only
needs to expose `Difficulty` (from `ETATDifficulty`) and `VigilantLoopCount`.

### 5.3 Context data

**PROVEN**, `Properties.ContextDataDescs` (always the same shape: struct class,
name, handle, `Requirement`):

| Count | Trees | Descriptors |
|---|---|---|
| 2 | 20 of 21 | `Actor` (`Class'Pawn'` in 15 trees, `Class'TATCharacterAIBase'` in 5) and `AIController` (`Class'AIController'` in 17, `Class'TATAIController'` in 4) |
| 5 | `ST_SmartObject_DefensiveSpot` | `AIController`, `Pawn`, `SmartObjectActor` (`Class'Actor'`), `SmartObjectClaimedHandle` (`Class'SmartObjectClaimHandle'`), `SlotEntranceHandle` (`Class'SmartObjectSlotEntranceHandle'`) |

`NumContextData` is 2 or 5 accordingly. All descriptors are
`EStateTreeExternalDataRequirement::Required` (**PROVEN**, 0 `Optional`).

The schema is serialised too: `Properties.Schema.ObjectName` is
`StateTreeAIComponentSchema'…'` for 20 trees and
`TATSmartObjectStateTreeSchema'…'` for `ST_SmartObject_DefensiveSpot`
(**PROVEN**). **INFERENCE-FROM-DOCS** (D1): "Context Data refers to the predefined
data available to the State Tree based on the selected State Tree Schema" — i.e.
the schema, not the tree, decides which descriptors exist.

### 5.4 Parameters (the property bag)

**PROVEN**, `Properties.Parameters` exists on 17 of 21 trees; it is an
`FInstancedPropertyBag` description (`PropertyDescs[]` + `SerialSize`) with **no
values**. Examples:

| Tree | Parameters (name: type) |
|---|---|
| `ST_Guard` | `ShouldReactToIncorrectObjects: Bool`, `ShouldReviveNPCs: Bool` |
| `ST_Patrol` | `ResetAlertness: Bool` |
| `ST_Subtree_GeneralInvestigateStim` | `AlertnessToRaiseTo: Enum`, `InitialDelayDuration: Double`, `DelayDuration: Double`, `LoopCount: Int32`, `InitialInvestigationVOLine: Struct`, `InvestigationSearchingVOLine: Struct`, `InvestigationGiveUpVOLine: Struct`, `InitialSearchLocation: Struct`, `InnerSearchRadius: Float`, `OuterSearchRadius: Float` |
| `ST_Subtree_ReviveNPC` | `Target: Object`, `ShouldActuallyRevive: Bool` |
| `ST_Subtree_Lockdown`, `ST_Subtree_Flee`, `ST_ClueGiving` | (empty bag) |

**PROVEN**: the same descriptors are duplicated on the owning component, e.g.
`AIC_StateTreeBase.Properties` → `MainStateTree.StateTreeRef.Parameters` carries
`ShouldReactToIncorrectObjects` + `ShouldReviveNPCs`. So a tree's global parameter
*names and types* are recoverable but its **values are not** (both places show
only the schema; `SerialSize: 4` is a byte count, the bytes are not in the JSON).

**PROVEN** wiring — `Properties.PropertyBindings.SourceStructs` has **1183**
entries in total, one per bindable thing, and the counts match the graph exactly:

| `DataSource` | Count | Equals |
|---|---|---|
| `StateParameter` | **459** | one per state |
| `Task` | **326** | one per task node |
| `Condition` | **233** | one per condition node |
| `TransitionEvent` | **89** | one per `OnEvent` transition |
| `StateEvent` | **3** | one per `RequiredEventToEnter` state (§4.4) |
| `Context` | **45** | Actor+AIController (2 × 21) + the 3 extra smart-object descriptors |
| `Parameter` | **21** | one global bag per tree |
| `Evaluator` | **1** | the `ST_Guard` difficulty evaluator |
| `PropertyFunction` | **6** | `Get Actor Location` nodes |

And `States[].ParameterBindingsBatch != 65535` on **30 states, all `LinkedAsset` (28)
or `Linked` (2)** — the batch that maps the parent state's parameters into the
linked asset's parameter bag.

### 5.5 `PropertyBindings` — the binding graph

**PROVEN** structure (`ST_Patrol.Properties.PropertyBindings`):

| Array | Length (ST_Patrol) | Meaning |
|---|---|---|
| `SourceStructs` | 56 | bindable structs: `{Name, DataHandle, DataSource}` |
| `CopyBatches` | 26 | one per node: `{TargetStruct{Struct,Name,DataHandle,DataSource}, BindingsBegin, BindingsEnd, PropertyFunctionsBegin/End}` |
| `PropertyPathBindings` | 37 | `{SourceDataHandle, SourcePropertyPath{Segments[{Name,ArrayIndex,InstanceStruct}]}, TargetPropertyPath{…}}` |
| `PropertyReferencePaths` | 5 | references into a struct parameter (e.g. `PatrolPointData`, `CurrentPatrolWorldLocation`) |
| `PropertyAccesses` | 5 | offset-based access `{SourceIndirection{Offset, Type, …}, SourceDataHandle}` |

**PROVEN** joins, all 566 nodes checked:

* `Nodes.Structs[k].BindingsBatch.Value` indexes `CopyBatches`; 455 nodes have a
  valid batch, 111 have `65535` (no bindings), 0 out of range.
* `CopyBatches[b].TargetStruct.DataHandle == Nodes.Structs[k].InstanceDataHandle`
  for **455/455** nodes with a batch (0 mismatches). So the batch's `TargetStruct`
  is the node, and the batch's `DataSource` names the node kind
  (`Task`, `Condition`, `PropertyFunction`).
* Each `CopyBatches[b]` owns
  `PropertyPathBindings[BindingsBegin ..< BindingsEnd]`, which are the authored
  input bindings by **property name** on both sides.

**INFERENCE-FROM-DOCS** (D7): `CopyBatchOnActiveInstances` "Copies a batch of
properties to the data in TargetView" and `EvaluatePropertyFunctions…` "Evaluate
all function at given range" — i.e. bindings are re-evaluated from source to
target on enter/tick, which is why the authored values in the instance templates
look like defaults (`null`, `0`) for anything bound.

**Runtime requirement**: to execute the real behaviour a port must (a) hold a
parameter bag per state, (b) evaluate `PropertyPathBindings` by name before each
task enter/tick and each condition test, and (c) support the 6 property functions
used (`Get Actor Location`). Without (b) every bound input keeps its serialised
default and most conditions read garbage.

---

## 6. Instance data / parameter recoverability

### 6.1 The chain, verified from the raw dump

`States[].TasksBegin/TasksNum` → `Nodes.Structs[k]` →
`Nodes.Structs[k].InstanceTemplateIndex.Value` → the instance-data array selected
by `Nodes.Structs[k].InstanceDataHandle.Source` → authored parameter values.

**PROVEN** array-selection rule (all 566 nodes in range; 0 mismatches):

| `InstanceDataHandle.Source` | Array | Count | Doc string (D10) |
|---|---|---|---|
| `GlobalInstanceData` / `…Object` | `Properties.DefaultInstanceData.Data.InstanceStructs.Structs` | 1 | "Global Tasks, Evaluators" |
| `ActiveInstanceData` / `ActiveInstanceDataObject` | same `DefaultInstanceData` array | 199 + 127 | "Active State Tasks" |
| `SharedInstanceData` / `SharedInstanceDataObject` | `Properties.SharedInstanceData.Data.InstanceStructs.Structs` | 227 + 12 | "Conditions and Considerations" |
| `ContextData` / `StateParameterData` / `GlobalParameterData` / `SubtreeParameterData` / `TransitionEvent` | not node data — data handles into context/parameter bags | — | D10 |

**PROVEN** correlation: the `…Object` variants (127 + 12 = 139) are *exactly* the
nodes that carry `TaskClass`/`ConditionClass`, and their template is
`{"InstanceObject": <UObject ref>}`; the non-Object variants are inline structs.

**PROVEN** that `InstanceTemplateIndex` is **not** the same number as
`InstanceDataHandle.Index`: they differ on **300 of 566 nodes**. E.g. `ST_Patrol`
node 0 has `InstanceTemplateIndex = 2` and `InstanceDataHandle.Index = 2`, but
node 5 has `InstanceTemplateIndex = 12`, `Index = 8`. `Index` is the runtime slot
(pooled: several mutually-exclusive tasks share slot 8); `InstanceTemplateIndex`
is the template. Reading parameters from the template always works; reading them
by `Index` reads the wrong struct on 300 of 566 nodes (**PROVEN**).

### 6.2 Three worked examples

**(1) `TATState Tree Task Set Alertness` → `AlertnessLevel`** — `ST_Patrol[1] "Set Alertness"`

```
ST_Patrol.Properties.States[1].TasksBegin = 0, TasksNum = 1
ST_Patrol.Properties.Nodes.Structs[0] =
  {"Name":"TATState Tree Task Set Alertness","BindingsBatch":{"Value":0},
   "InstanceTemplateIndex":{"Value":2},
   "InstanceDataHandle":{"Source":"...ActiveInstanceData","Index":2,"StateHandle":{"Index":1}},
   "bTaskEnabled":true,"TransitionHandlingPriority":"...Normal"}
ST_Patrol.Properties.DefaultInstanceData.Data.InstanceStructs.Structs[2] =
  {"AIController": null,
   "AlertnessLevel": "EAlertnessLevel::Neutral",
   "RunUntilAnimationFinished": true}
```

Recovered: `AlertnessLevel = Neutral`, `RunUntilAnimationFinished = true`;
`AIController` is bound (`CopyBatches[0]` → `PropertyPathBindings[0]` binds
`AIController` from `ContextData[1]`, **PROVEN**). 20 instances of this task exist;
each has its own template index and its own `AlertnessLevel`.

**(2) `Delay Task` → `duration`** — `ST_Patrol[17] "Delay"` and `ST_Patrol[19] "Failed"`

```
States[17].TasksBegin = 14 → Nodes.Structs[14] = {"Name":"Delay Task",
   "InstanceTemplateIndex":{"Value":32}, "InstanceDataHandle":{...Index:8...}}
DefaultInstanceData...Structs[32] =
   {"duration": 1.0, "RandomDeviation": 0.0, "bRunForever": false}

States[19].TasksBegin = 16 → Nodes.Structs[16] = {"Name":"Delay Task",
   "InstanceTemplateIndex":{"Value":36}, ...}
DefaultInstanceData...Structs[36] =
   {"duration": 100.0, "RandomDeviation": 0.0, "bRunForever": false}
```

Two instances of the same task with different authored durations (1.0 s and
100.0 s) — exactly the kind of value the current payload loses. 32 `Delay Task`
instances exist with 32 distinct templates.

**(3) `STC_PatrolPathPointIsOfType_C` → `PatrolPathType`** — `ST_Patrol[11]` and `[13]`

```
States[11].EnterConditionsBegin = 24 → Nodes.Structs[24] =
  {"ConditionClass":{"ObjectName":"...STC_PatrolPathPointIsOfType_C"},
   "InstanceTemplateIndex":{"Value":5},
   "InstanceDataHandle":{"Source":"...SharedInstanceDataObject","Index":5,...},
   "Operand":"Copy","DeltaIndent":0,"EvaluationMode":"...Evaluated","bInvert":false}
SharedInstanceData.Data.InstanceStructs.Structs[5] =
  {"InstanceObject":{"ObjectName":"STC_PatrolPathPointIsOfType_C'ST_Patrol:STC_PatrolPathPointIsOfType_C_2'",
                     "ObjectPath":"/Game/AI/StateTrees/SubTrees/ST_Patrol.2"}}
ST_Patrol[export 2] = {"Type":"STC_PatrolPathPointIsOfType_C",
                       "Name":"STC_PatrolPathPointIsOfType_C_2",
                       "Properties":{"PatrolPathType":"EPatrolPointType::SmartObjectInteraction"}}
```

The other instance (`ST_Patrol[13]`, template 7 → export 3) has
`Properties: {}` (**PROVEN**), i.e. no per-instance override; its value is the
Blueprint class default, and
`extracted/json/AI/StateTrees/Conditionals/STC_PatrolPathPointIsOfType.json`
`[2] Default__STC_PatrolPathPointIsOfType_C` also has `Properties: {}`
(**PROVEN**), so the default is the *C++ property default*, which is **UNKNOWN**
from the dump.

**PROVEN** general rule: for a `…Object` node the chain is
`node → template.InstanceObject.ObjectPath → that export in the same file`; a
missing property means "inherit the class default" and the class default is in the
leaf dump's CDO *only if the Blueprint overrode it*. Two such hops are invisible
otherwise.

### 6.3 Can `guard_behavior.json` alone recover these? **No.**

**PROVEN by counter-example.** The payload's per-state record is exactly
(`payload:trees.ST_Patrol.states[1]`):

```json
{"index":1,"name":"Set Alertness","depth":1,"type":"State","parent":"Root",
 "parent_index":0,"children":[],"children_range":[2,2],
 "tasks":["TATState Tree Task Set Alertness"],
 "enter_conditions":["Bool Compare"],"utility_considerations":[],
 "transitions":[...],"linked_asset":null,"linked_state_index":null,
 "enabled":true,"selection_behavior":"TrySelectChildrenInOrder"}
```

There is no field anywhere in the payload that carries
`InstanceTemplateIndex`, `InstanceDataHandle`, `BindingsBatch`, `TaskClass`,
`ConditionClass`, the instance-data arrays, `PropertyBindings`,
`RequiredEventToEnter`, `bCheckPrerequisitesWhenActivatingChildDirectly`,
`bConsumeEventOnSelect`, `Weight`, or `UtilityConsiderationsNum`. A grep of the
file for `EAlertnessLevel`, `PatrolPathType`, `InstanceTemplateIndex`,
`duration` and `PropertyBindings` returns **0 hits** (**PROVEN**).

Therefore: `AlertnessLevel = Neutral`, `duration = 1.0 / 100.0`, and
`PatrolPathType = SmartObjectInteraction` are **all unrecoverable** from
`guard_behavior.json`. The same is true for every other authored value: 199/199
native task templates and 221/221 native condition templates in the raw dump carry
authored values (e.g. `ST_Subtree_Flee[22]`'s `Check Distance From Owner` has
`ComparisonValue: 1200.0`), and 0 of them reach the payload.

### 6.4 Exact producer fields a fix must emit

Recommended additive schema (all names already exist in the raw dump, so the
producer stays a pure projection — no guessing):

```jsonc
"trees": { "<Tree>": {
  "entry": <int>,                                    // roots[0]; already synthesised in tree_model.gd
  "states": [ {
    ...existing...,
    "required_event_to_enter": {"tag": "...", "payload_struct": "...|null"},
    "event_data_index": <int|null>,
    "check_prerequisites_when_activating_child_directly": <bool>,
    "consume_event_on_select": <bool>,
    "weight": <float>,
    "parameter_template_index": <int>,
    "parameter_bindings_batch": <int|null>,
    "tasks": [ {                                       // replaces string[]
        "name": "...",
        "class": "STT_…_C | null",                      // TaskClass when present
        "native": <bool>,                               // no TaskClass → native C++
        "enabled": <bool>,                              // bTaskEnabled
        "transition_handling_priority": "Normal|…",
        "template_index": <int>,                         // InstanceTemplateIndex
        "data_source": "ActiveInstanceData|…Object",
        "bindings_batch": <int|null>,
        "params": { "<AuthoredProperty>": <json value>, … },
        "bound": ["AIController", …]                     // target paths with a binding
    } ],
    "enter_conditions": [ {
        "name": "...", "class": "STC_…_C|null", "operand": "Copy|And|Or",
        "delta_indent": <int>, "invert": <bool|null>,
        "evaluation_mode": "Evaluated", "template_index": <int>,
        "params": {…}, "bound": […]
    } ],
    "transitions": [ { ...existing...,
        "fallback": "...", "consume_event_on_select": <bool>,
        "delay_random_variance": <float>,
        "required_event_payload_struct": "...|null",
        "conditions": [ /* same shape as enter_conditions */ ]
    } ],
    "children": [<int>]
  } ],
  "global": {
     "evaluators": [ {"name":"Difficulty Evaluator","template_index":0,
                      "params":{"Difficulty":"ETATDifficulty::Normal","VigilantLoopCount":1}} ],
     "global_tasks": [],
     "context_data": [ {"name":"Actor","struct":"Pawn","requirement":"Required"} ],
     "parameters": [ {"name":"ShouldReviveNPCs","type":"Bool"} ]
  },
  "bindings": { "copy_batches": [...], "path_bindings": [...] },     // optional, large
  "property_functions": [ {"name":"Get Actor Location","node":22} ]
} }
```

Minimum viable subset if size matters: `tasks/enter_conditions[].params`,
`tasks[].class` + `native`, `required_event_to_enter`, `check_prerequisites…`,
`consume_event_on_select`, and `children` as **integers** (so consumers do not
have to match on non-unique names). Everything else (`bindings`, `property_functions`)
is only needed for full behavioural fidelity; without it the interpreter runs on
serialised defaults.

**Size estimate**: 566 node records, of which **445 carry authored per-node
values** — 199 native task templates, 221 native condition templates, 7 property
function/evaluator structs, 13 Blueprint task instances with property overrides
and 5 Blueprint condition instances with overrides (**PROVEN**). The remaining
121 are Blueprint nodes with an empty override set (`Properties: {}`), which
inherit their class defaults. The raw `DefaultInstanceData` + `SharedInstanceData`
structs total a few thousand JSON objects across 21 trees — well under the current
784 KB payload.

---

## 7. UE semantics the port cannot reproduce

Each row names the dump artifact that **proves** the dependency and the minimum
runtime surface a port would have to fake or implement.

| # | Semantics | Evidence in the dump | What a port needs |
|---|---|---|---|
| 1 | **Smart objects / GameplayInteractionSystem** | **13** task instances across the 4 `STT_UseSmartObject*` subclasses plus `STT_DistractionSmartObjects_C`; `ST_SmartObject_DefensiveSpot` is a whole tree with `TATSmartObjectStateTreeSchema` and context `SmartObjectClaimHandle` / `SlotEntranceHandle`; `SmartObjectSlotHandle` output on 19 `Run Env Query` instances; `TATStateTreeDistractionComponent._QueryTemplate = EQS_FindDistractionLocation` (`AIC_StateTreeBase`) | An SO registry with claim/handle/slot objects, `Claim`, `Use`, `Release`, slot entrance transforms, and "is slot available" queries. Godot has no equivalent; the port would need a project-owned smart-object graph. |
| 2 | **EQS** | 19 `Run Env Query` task instances over **11 distinct** query assets (`EQS_FindInvestigationLocation` ×3, `EQS_FindNavigableLocationNearQuerier` ×3, `EQS_FindRangedAttackLocation` ×2, `EQS_FindInitialInvestigationLocation` ×2, `EQS_FindMajorLootReturnLocation` ×2, `EQS_FindDamagingActor` ×2, + `EQS_FindGuardDefensivePoint`, `EQS_FindCivilianCowerPoint`, `EQS_FindSharedTargetPartner`, `EQS_FindAlarmLocation`, `EQS_OffNavLinkSearchPosition`). The queries *are* dumped (`extracted/json/AI/EQS/EnvironmentQuery/**`) with generators (`EnvQueryGenerator_ActorKnowledge`, …) and scored tests (`EnvQueryTest_Distance` InverseLinear max 5000, `EnvQueryTest_GameplayTags` …) | A scoring spatial query: candidate set (actors by knowledge/tag), N tests with filter/scoring equations, weighted pick, plus navmesh projection. The *data* is recoverable; the *evaluator* is not present. |
| 3 | **Gameplay abilities (GAS)** | `Trigger Gameplay Ability By Class` ×4, `Trigger ability via Gameplay Tag and Wait` ×4 (`STT_TriggerGameplayAbilityWithEvent_C`), `Trigger Gameplay Ability By Gameplay Event` ×1, `Trigger Gameplay Ability By Input` ×1, `Apply Gameplay Effect` ×3, `TATState Tree Task Wait for Applied Tags` ×4, `TATState Tree Task Wait for AIResource Unlocked` ×1 | A tag-keyed ability system with activation, wait-for-tag and applied-effect bookkeeping, and an "AI resource" lock. |
| 4 | **Individual knowledge & attitude** | `TATState Tree Task Update Knowledge Of Actor` ×9, `TATState Tree Task Set Individual Knowledge` ×5, `Scoped Individual Knowledge` ×2, `STT_SetAttitudeToTarget_C` ×7, `STT_ShareTarget_C`, `Check Target Knowledge with Detection/Attitude`, `Has Individual Knowledge`; component `TATIndividualKnowledgeComponent` on `AIC_StateTreeBase` | A per-agent knowledge store (actor → facts with timestamps/decay, query API) and an attitude/enum per target. |
| 5 | **Targeting groups** | `TATStateTreeTargetingComponent` component; `Add Targeting Groups` ×2, `Track Targeting Groups` ×1, `Extract Target From Targeting Group` ×14, `Extract Main Target Data from Event` ×3; 9 `DA_TargetingConsideration_*` assets whose inputs enumerate the dependencies: `Distance`, `LineTraceToTarget`, `MatchesVisibility`, `IsAttitude`, `DetectionMatches`, `HasIndividualKnowledgeOfTarget`, `HasPathToTarget`, `SmartObjectHasSlotAvailable`, `IsClueInteractableByTarget`, `IsInAccessibleZone`, `HasTrait`, `MatchesTagQuery`, `CheckUtilityTargetingGroup` | A target-set manager with per-group scored selection over those inputs. 48 `TargetChange` transitions depend on it: without it, most of `ST_Guard`/`ST_Civilian` is dead. |
| 6 | **Blackboard** | `TATState Tree Task Set Blackboard Value` ×5, `… Set Blackboard Actor Value` ×3, `BlackboardComponent` with `DefaultBlackboardAsset: BB_NPC_Base` on `AIC_StateTreeBase`, `STC_BlackboardActorIsSet_C` | A named key/value store with actor keys; trivial to add, but the key names come from the task params, not the payload. |
| 7 | **Escalation / difficulty** | `TATEscalationComponent` + `AI.Event.Escalation.Reset` send + `Difficulty Evaluator` (`ETATDifficulty::Normal`) + `TATState Tree Task Loop` ×2 + the `Vigilant Escalation` branch (11 states incl. the branch root) | A difficulty value per agent and an escalation counter; the evaluator output must be bindable. |
| 8 | **Stim database / hearing** | `TATAIStimDatabase` CDO on `AIC_StateTreeBase`; `TATState Tree Task Extract Stim Data from Event` ×4, `Check Stim Event Matches` ×6, `TATState Tree Condition Stim` ×7, `Check Stim Data instigator matches attitude` ×4, `…private zone tags` ×1, `Update Stim Info` ×1, `Scoped Stim Investigation` ×1 | A stim record (location, strength, instigator, tags) with dedupe/expiry. The port already has `NoiseBus`/`HearingData` (W6G) — partial. |
| 9 | **VO / voice-line knowledge** | `OSEVoiceLineKnowledgeComponent` on `AIC_StateTreeBase`; 31 + 12 + 3 `STT_RequestVOLine*` instances; `STT_RequestVOLine_Repeating_C` has `OnTimer`; params `VOLineTag`, `Delay`, `DelayVariation`, `StartVariation`, `VoiceLineToPlay`, `DelayBeforeVoiceLine` | A VO request queue keyed by gameplay tag with per-line cooldown/knowledge and a duration callback (the repeating variant needs `ReceiveStateCompleted`). |
| 10 | **Reaction roles** | `Register for Reaction Role` ×2, `Extract Reaction Role` ×2, `TATAITargetingEvent_ReactionRoleChanged` payload; `StateTreeEvent.ReactionRoleChange` listeners | An NPC-to-NPC role reservation (who reacts, who watches) with change notification. |
| 11 | **Animation / montage wait** | `STT_TriggerAndWaitForAnimation_C` ×2, `TATState Tree Task Rotate to Face` ×9 (params `Type`, `TargetActor`, `TargetLocation`, `Precision`, `EndTaskWhenFacing`), and the `Cower` / `In Smoke` states whose only action is a gameplay-ability trigger | A montage/task that returns `Running` until animation end, plus facing control. |
| 12 | **Navigation / path following** | `Move To` ×9 + `[TAT] Move To` ×6 (`Destination`, `AcceptableRadius`, `bProjectGoalLocation`, `bRequireNavigableEndLocation`, …), `TATPathFollowingComponent`, `ST_OffNavLink` | Navmesh path following with reach tests and partial paths; the port has CharacterBody3D + a navmesh, so this is the most tractable row. |
| 13 | **Contextual locations** | `STT_TryClaimContextualLocation_C` ×1, `STT_SetContextualLocationInUse_C` ×1 | A claimable "spot" registry (distinct from smart objects). |
| 14 | **Interaction** | `STT_InteractWithInteractable_C` ×1, `Use Interactable Actor` | An interactable interface with an interaction duration. |

**What *is* reproducible without any of the above**: the graph itself (selection,
groups, links, transitions, priorities, events), all 12 BP conditions
(`STC_HasClue`, `STC_HasEquipment`, `STC_IsCarryingMajorLoot`,
`STC_HasKnowlewdgeToShare`, `STC_BlackboardActorIsSet`,
`STC_PatrolPathPointIsOfType`), `Bool Compare` / `Distance Compare` /
`Object Is Valid` / `Has Tag` / `Check Gameplay Tag Is Valid` / `Integer Compare`
on values the port supplies, `Delay Task`, `Clear Focus`, `Set Focus`, `Report
Noise` and the two event extractors. That is roughly the "shell" of ST_Patrol,
ST_ClueGiving and the reaction trees; ST_Subtree_Combat and ST_Guard's target
reactions are dominated by rows 1–5.

---

## 8. Minimum viable interpreter contract — RECOMMENDATION

Everything in this section is a **RECOMMENDATION** (a port decision), built on the
PROVEN/INFERENCE facts above. It is written engine-neutral.

### 8.1 State kept per instance

```
frames        : stack of {tree_id, state_index, status, entered_tick}
                status ∈ {UNSET, RUNNING, SUCCEEDED, FAILED, STOPPED}
                frames[0] is the tree root, frames[-1] the selected leaf
task_slots    : per (frame, task_index) -> {status, instance}   (only for tasks with bTaskEnabled)
event_queue   : FIFO of {tag, payload, origin}
tick_events   : events drained for the current tick
tree_status   : RUNNING | SUCCEEDED | FAILED | STOPPED
```

### 8.2 `Tick(dt)` — ordered pseudocode

```
Tick(dt):
 1. if tree_status != RUNNING: return tree_status
 2. tick_events = drain(event_queue)                 # only this tick's events are visible
 3. TICK GLOBALS
      for each evaluator:   evaluator.Tick(dt)        # before state tasks (D1)
      for each global task: global_task.Tick(dt)      # none in this data
 4. PROPAGATE COMPLETION (leaf → root)             # a child's terminal status becomes its parent's
      for d from leaf down to 1:
          if frames[d].status in {SUCCEEDED, FAILED, STOPPED}:
              frames[d-1].status = frames[d].status
 5. TICK TASKS (root → leaf, D1)
      for each frame f in root..leaf:
          for each enabled task t of f.state:
              if not t.entered:      t.entered = true; t.status = t.EnterState(f)
              elif t.status == RUNNING and t.should_tick(dt, tick_events):
                                     t.status = t.Tick(dt)
          # FIRST task to leave RUNNING decides the state (D1)
          first = first t with t.status in {SUCCEEDED, FAILED}
          if first: f.status = first.status; StateCompleted(f.state)
 6. COLLECT TRANSITION CANDIDATES (leaf → root, D1)
      candidates = []
      for depth d from leaf down to root:
          f = frames[d]
          for each transition tr of f.state, in authored order:
              if not tr.enabled: continue
              if not trigger_matches(tr.trigger, f.status, tick_events): continue
              if tr.trigger == OnEvent and not event_present(tr.required_event): continue
              if not all conditions TRUE(tr.conditions): continue
              candidates.append({depth: d, index: tr.index, priority: rank(tr.priority), tr: tr})
 7. ARBITRATE + APPLY (highest priority first, then deepest, then authored order)
      if candidates is empty: return RUNNING                       # nothing fires, stay
      for c in sort(candidates, by=(priority desc, depth desc, index asc)):
          if apply(c) == OK: return COMMIT                          # D1: first that *leads to selection*
      return RUNNING                                                # every candidate failed to select
 8. APPLY(c)
      if c.tr.trigger == OnEvent and c.tr.consume_event_on_select:
          consume(c.tr.required_event)                              # §3.6
      target = resolve(c.tr.state)                                  # 65533 -> next sibling,
                                                                    # 65534 -> SUCCEEDED,
                                                                    # else state index
      if target == SUCCEEDED: return stop_frame(c.frame, SUCCEEDED) # tree or sub-tree
      if target == NEXT and no next sibling: return FAIL_SELECT     # UNKNOWN in UE
      return select(target, c.tr.fallback, c.event)                 # steps 9-10
 9. SELECT(target) — TrySelectChildrenInOrder
      s = target
      loop:
          if not s.enabled: return FAIL_SELECT
          if s.required_event_to_enter.tag != None:
              if not event_present(tag): return FAIL_SELECT
          if not all conditions TRUE(s.enter_conditions): return FAIL_SELECT
          if s.type == Linked:      s = linked_state(s)            # same asset, jump
          elif s.type == LinkedAsset: push a new frame for the linked tree's root; return OK
          children = direct_children(s)                            # payload states[].children
          if s.selection_behavior == TryEnterState or children is empty: return OK(s)
          nxt = first c in children order with select(c) == OK     # recursive, same rules
          if nxt: return OK(nxt)
          return FAIL_SELECT                                       # D1: parent is NOT selected
 10. SELECT fallback (only if step 9 returned FAIL_SELECT)
      if fallback == NextSelectableSibling:
          for each sibling after the failed target, in order: if select(sibling) == OK: return OK
      return FAIL_SELECT
 11. COMMIT
      common = longest common prefix of (old frames, new frames)
      for f in old frames after common:  f.tasks.ExitState(); pop            # leaf → root
      for f in new frames after common:  f.tasks.EnterState(); push          # root → leaf
      # a frame that stayed keep its task instances (ChangeType = Sustained, D5)
 12. return RUNNING
```

### 8.3 The six rules this contract fixes (and where each comes from)

| Rule | Source |
|---|---|
| only a root→leaf chain is active, all of it ticks | D1 |
| a state's status comes from its first completing task, else from its selected child | D1 + §2.3 |
| transitions are collected from every active state, leaf→root | D1 + 69 ancestor/24 descendant targets (§3.3) |
| highest `Priority` wins; ties by depth then authored order; `None` is weakest | D8 + §3.2 |
| a candidate that cannot select its target is skipped for the next candidate | D1 ("succeeds and leads to State selection") + `ST_Subtree_Combat_ActivateAttack[3]` (§3.6) |
| a failed target selection only falls through to a sibling with `Fallback = NextSelectableSibling` | D10 + 173 `None`-fallback targets that can fail (§3.6) |

### 8.4 Deliberate simplifications that are safe for *this* data

* **No utility scoring.** `UtilityConsiderationsNum == 0` on all 459 states; only
  `TrySelectChildrenInOrder` semantics are needed (§1.1).
* **No transition timers.** `Delay == 0` on all 467 transitions (§3.1).
* **No task transition handling.** `bHasTransitionTasks == false` on all 459
  states and all 326 tasks are `Normal` (§2.5).
* **Random seeding is irrelevant to selection.** No random behaviour is authored.
* **UNKNOWN conditions are treated as not-TRUE** (nothing enters, nothing fires)
  and should be recorded per evaluation. The payload cannot resolve them; a
  runtime must never read UNKNOWN as "true by default".

---

## Appendix A — corrections for the in-flight implementation

Read-only observations against `game/src/ai/statetree/tree_model.gd` and
`interpreter.gd` in this worktree (not modified by this lane):

1. **`PRIORITY_RANK` has `Medium` and `Normal` swapped.**
   `tree_model.gd` has `"Medium": 2, "Normal": 3`. UE 5.5 is
   `NORMAL = 2`, `MEDIUM = 3` (D8). The enum declaration order is
   `None, Low, Normal, Medium, High, Critical` (D10).
   Consequence with the current table: 21 `Medium` transitions rank *below* 67
   `Normal` ones. The clearest authored case is `ST_Guard[85]`, which puts
   `t[109] OnTick Normal` (1 condition) before
   `t[110] OnEvent Medium StimChange`; UE's intent is that the stim event beats
   the tick observer, the current table makes the observer win whenever both are
   eligible. Same inversion hits `ST_Guard[3]`: `t[8]`, `t[9]`, `t[15]` are
   `Medium`, and the `Normal` ones they must outrank are `t[10]`, `t[11]`, `t[12]`,
   `t[14]`, `t[16]` (its `t[17]` is `OnStateCompleted`/`None`).
2. **"A state whose children all fail to enter selects itself" contradicts D1.**
   D1, verbatim: *"If a State has child States, yet none can be selected (their
   Enter Conditions fail), the State will not be selected even if all its Enter
   Conditions passed the test."* The 39 `NextSelectableSibling` fallbacks (19 on
   targets that can fail) only make sense under that rule — the transition
   re-targets the next sibling instead of selecting the parent. The doc-comment
   calls this a port decision, which is honest, but it changes 19 authored
   branches; a `Fallback`-aware selection is closer to the shipped behaviour.
3. **`Next` is "next sibling of the *source* state"** (D10: "Transition to the
   next sibling state"), not "the parent advances". Functionally equivalent when
   the sibling exists, and 3 of the 15 `Next` transitions sit on last children
   where UE's behaviour is **UNKNOWN** (see §3.4).
4. **`RequiredEventToEnter` is not in the payload**, so the 3 states in §4.4
   cannot be gated today: `ST_Patrol[21]`, `ST_Subtree_Combat[6]`,
   `ST_InvestigateStims_Guard[6]`. They are the entry points for the only typed
   event payloads in the data (§6.4 needs `required_event_to_enter` +
   `event_data_index`).
5. **Names are not unique.** `parent`, `to_state` and `from_state` in the payload
   are names; `ST_Guard` alone has 7 `VO Line`, 6 `Clear Focus`, 4 `Delay`, 4
   `Grab Target From Event`, 3 `Raise Alertness` and 3 `Move to and Use Smart
   Object`. Use `parent_index` / `to_state_index` for identity.
6. **`PayloadStruct` is not the same as "no payload".** 3 transitions carry a
   typed payload (§4.4); 464 have `null`. If the runtime models events as
   tag-only it loses the two `Extract … from Event` tasks.

## Appendix B — how to reproduce the measurements

Everything above comes from these reads (no engine, no producer):

```bash
# state/transition/priority census
python3 - <<'PY'
import json, glob, collections
T={}
for f in sorted(glob.glob('extracted/json/AI/StateTrees/**/*.json', recursive=True)):
    d=json.load(open(f))
    if not isinstance(d,list) or not d: continue
    p=d[0].get('Properties')
    if not isinstance(p,dict) or 'States' not in p: continue
    T[d[0]['Name']]=(f,d[0],p)
print(collections.Counter(str(s['Type']).split('::')[-1] for _,_,p in T.values() for s in p['States']))
print(collections.Counter(str(t['Priority']).split('::')[-1] for _,_,p in T.values() for t in p['Transitions']))
print(collections.Counter(str(t['Trigger']).split('::')[-1] for _,_,p in T.values() for t in p['Transitions']))
PY

# the parameter chain for one node
python3 - <<'PY'
import json
p=json.load(open('extracted/json/AI/StateTrees/SubTrees/ST_Patrol.json'))[0]['Properties']
n=p['Nodes']['Structs'][0]
print(n['InstanceTemplateIndex'], p['DefaultInstanceData']['Data']['InstanceStructs']['Structs'][n['InstanceTemplateIndex']['Value']])
PY
```

Checked and found absent in `guard_behavior.json` (all 0 hits): `EAlertnessLevel`,
`PatrolPathPointIsOfType`, `InstanceTemplateIndex`, `PropertyBindings`, `duration`.
