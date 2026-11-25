# W9-P4 — StateTree data-payload fact sheet (measured)

Worktree `/home/john/Projects/TAT-2-rem-w9-p4`, branch `rem/w9-p4`, HEAD `f1bf058`.
Investigation lane only: no Godot run, no producer run, no file written except this
report.

Scope: `game/data/generated/gameplay/guard_behavior.json` (schema
`tat2.guard_behavior/1`), the raw cooked dumps under
`extracted/json/AI/StateTrees/**`, and the producer `tools/parse_state_tree.py`.

Every number below is copied from a command output or from a JSON path; the
commands are in Appendix A.

Snapshot caveat: this worktree is shared with other W9 lanes. During the
measurement the untracked paths were `game/src/ai/statetree/` (one 545-line
`tree_model.gd` at 17:15, seven files / 2,483 lines by 17:26) and a transient
`game/tests/_tmp_selfload_test.gd`; `game/src/ai/guard_ai.gd` also gained 20
uncommitted lines (2573 → 2593). None of it is in `git ls-files`. The payload
measurements are of the data on disk, not of that uncommitted code; §6.1 states
what the directory contained at the time of the run.

Where a quantity is not present in the data it is labelled **not provable**
with the reason.

Payload identity on disk:

```
784227 bytes   game/data/generated/gameplay/guard_behavior.json
26673 lines
sha256 3f397005e37ebef7d7f5a8a924cdb9ee7ae9853fc1ffe6e6a9d93534fb26b006
```
That sha256 is the one recorded in `tools/audit_baseline.json:453-459`, so the
payload on disk is exactly the producer output the audit baseline was stamped
from (no regeneration drift in this worktree).

Headline measured facts (details in the sections):

| quantity | value |
|---|---|
| cooked StateTree assets | 21 (3 roots + 18 under `SubTrees/`) |
| states / transitions | 459 / 467 |
| states by type | `State` 376, `Group` 35, `LinkedAsset` 45, `Linked` 2, `Subtree` 1 |
| subtree links (`LinkedAsset` states) | 45, **all** with `LinkedState.Index = 65535` (default entry) |
| authored-disabled states / transitions | 7 / 1 |
| distinct task names / task instances | 77 / 326 |
| distinct condition names (enter+transition) | 36 |
| enter-condition instances / transition-condition instances | 81 / 152 |
| utility considerations | 0 names, 0 instances |
| raw `Nodes.Structs` entries | 566 (326 tasks, 233 referenced conditions, 6 property functions, 1 evaluator) |
| task nodes with a recoverable per-instance parameter | 190 native structs with a non-null authored value + 70 BP nodes with per-instance overrides in the tree export → **260 / 326 carry an authored per-instance value** (57 BP inherit class CDO defaults, 9 native are null-only) |
| condition nodes with per-instance parameters | 205 native authored + 4 BP overrides → **209 / 233 referenced conditions** (the other 24 of 233 have no authored value; 6 `Get Actor Location` property functions are not conditions) |
| authored transition `Delay` | 0 / 467 non-zero (raw and payload both zero) |
| blueprint leaves | 28 `STT_*` + 6 `STC_*` + 9 targeting considerations, 0 other |

---

## 1. Tree inventory (measured)

21 assets, 459 states, 467 transitions, 45 linked-asset states, 7 disabled
states. `roots` is the payload list of depth-0 states; 20 trees have exactly one
(`Root`), `ST_InvestigateStims_Guard` has two.

| tree | package (`asset`) | states | transitions | groups | linked-asset states | disabled states | max depth | evaluators | roots |
|---|---|---|---|---|---|---|---|---|---|
| `ST_Civilian` | `/Game/AI/StateTrees/ST_Civilian` | 73 | 82 | 8 | 10 | 2 | 4 | 0 | Root |
| `ST_ClueGiving` | `/Game/AI/StateTrees/SubTrees/ST_ClueGiving` | 9 | 4 | 2 | 0 | 0 | 3 | 0 | Root |
| `ST_Guard` | `/Game/AI/StateTrees/ST_Guard` | 126 | 148 | 9 | 17 | 1 | 7 | 1 | Root |
| `ST_InvestigateStims_Civilian` | `/Game/AI/StateTrees/SubTrees/ST_InvestigateStims_Civilian` | 6 | 3 | 0 | 3 | 0 | 1 | 0 | Root |
| `ST_InvestigateStims_Guard` | `/Game/AI/StateTrees/SubTrees/ST_InvestigateStims_Guard` | 17 | 22 | 0 | 6 | 0 | 3 | 0 | Root, Substate Tree For Reaction |
| `ST_OffNavLink` | `/Game/AI/StateTrees/ST_OffNavLink` | 3 | 2 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Patrol` | `/Game/AI/StateTrees/SubTrees/ST_Patrol` | 23 | 22 | 2 | 0 | 0 | 4 | 0 | Root |
| `ST_SmartObject_DefensiveSpot` | `/Game/AI/StateTrees/SubTrees/ST_SmartObject_DefensiveSpot` | 3 | 2 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Standby_Guards` | `/Game/AI/StateTrees/SubTrees/ST_Standby_Guards` | 4 | 4 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Subtree_Combat` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_Combat` | 52 | 57 | 4 | 4 | 1 | 6 | 0 | Root |
| `ST_Subtree_Combat_ActivateAttack` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_Combat_ActivateAttack` | 4 | 4 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Subtree_Combat_Hauntstable` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_Combat_Hauntstable` | 22 | 21 | 0 | 2 | 0 | 5 | 0 | Root |
| `ST_Subtree_Flee` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_Flee` | 32 | 26 | 6 | 0 | 0 | 6 | 0 | Root |
| `ST_Subtree_GeneralInvestigateStim` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_GeneralInvestigateStim` | 23 | 26 | 1 | 0 | 0 | 3 | 0 | Root |
| `ST_Subtree_IntruderNoLongerSuspicious` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_IntruderNoLongerSuspicious` | 4 | 3 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Subtree_Lockdown` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_Lockdown` | 13 | 12 | 0 | 1 | 0 | 4 | 0 | Root |
| `ST_Subtree_ReviveNPC` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_ReviveNPC` | 16 | 15 | 0 | 2 | 0 | 2 | 0 | Root |
| `ST_Subtree_SpottedIntruderReaction` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_SpottedIntruderReaction` | 4 | 3 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Subtree_SpottedIntruderReaction_Hauntstable` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_SpottedIntruderReaction_Hauntstable` | 4 | 3 | 0 | 0 | 0 | 1 | 0 | Root |
| `ST_Subtree_TryActivateAlarm` | `/Game/AI/StateTrees/SubTrees/ST_Subtree_TryActivateAlarm` | 4 | 3 | 0 | 0 | 0 | 2 | 0 | Root |
| `ST_TriggerFlee_Civilian` | `/Game/AI/StateTrees/SubTrees/ST_TriggerFlee_Civilian` | 17 | 5 | 3 | 0 | 3 | 3 | 0 | Root |
| **total** | 21 assets | **459** | **467** | 35 | 45 | 7 | max 7 | 1 | |

Source: `guard_behavior.json` → `trees.<name>.stats` and `trees.<name>.roots`
(producer `tools/parse_state_tree.py:498-512`). `groups` counts
`type == "Group"`, `linked_asset_states` counts `type == "LinkedAsset"`; the 2
`Linked` and 1 `Subtree` states are not in either count (see §1.3). For all 21
trees `stats.subtree_links == stats.linked_asset_states` (45 = 45; the
`linked-asset states` column is therefore also the per-tree subtree-link count).

Totals check: 459 states, 467 transitions, 45 links, 7 disabled — identical to
`guard_behavior.json` → `stats` (`trees`, `states`, `transitions`,
`subtree_links`, `disabled_states`).

### 1.1 Roots vs subtrees

* Top-level root assets (directory `extracted/json/AI/StateTrees/`):
  `ST_Guard`, `ST_Civilian`, `ST_OffNavLink`. The payload also records them in
  `payload.roots` (`["ST_Guard","ST_Civilian","ST_OffNavLink"]`, producer
  `ROOT_TREES`, `tools/parse_state_tree.py:65`).
* Subtree assets (directory `SubTrees/`): the other 18.

Referenced-subtree graph: 45 links reach 15 distinct assets. Never referenced by
any of the 21 assets: `ST_Civilian`, `ST_Guard`, `ST_OffNavLink`,
`ST_SmartObject_DefensiveSpot`, `ST_Subtree_Combat_Hauntstable`,
`ST_Subtree_SpottedIntruderReaction_Hauntstable`.

### 1.2 Subtree links (all 45), with target asset and entry state

Every link's `entry_state_index` is `null` in the payload, i.e. the raw
`LinkedState.Index` is 65535 (`FStateTreeStateHandle::Invalid`) — the linked
tree runs from its own `Root` (state 0). The entry column below is therefore the
resolved target `Root` for all 45 rows.

| # | referrer | state | target asset | entry |
|---|---|---|---|---|
| 1 | `ST_Civilian` | [3] `Clue Giving` | `ST_ClueGiving` | Root (index 0; `LinkedState.Index=65535`) |
| 2 | `ST_Civilian` | [4] `Patrolling` | `ST_Patrol` | Root (index 0; `LinkedState.Index=65535`) |
| 3 | `ST_Civilian` | [26] `React to Stims (Civilian)` | `ST_InvestigateStims_Civilian` | Root (index 0; `LinkedState.Index=65535`) |
| 4 | `ST_Civilian` | [35] `Move to intruder` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 5 | `ST_Civilian` | [56] `Trigger Flee` | `ST_TriggerFlee_Civilian` | Root (index 0; `LinkedState.Index=65535`) |
| 6 | `ST_Civilian` | [58] `Trigger Flee` | `ST_TriggerFlee_Civilian` | Root (index 0; `LinkedState.Index=65535`) |
| 7 | `ST_Civilian` | [62] `Trigger Flee` | `ST_TriggerFlee_Civilian` | Root (index 0; `LinkedState.Index=65535`) |
| 8 | `ST_Civilian` | [63] `Flee Behavior` | `ST_Subtree_Flee` | Root (index 0; `LinkedState.Index=65535`) |
| 9 | `ST_Civilian` | [67] `Flee Behavior` | `ST_Subtree_Flee` | Root (index 0; `LinkedState.Index=65535`) |
| 10 | `ST_Civilian` | [72] `Flee Behavior` | `ST_TriggerFlee_Civilian` | Root (index 0; `LinkedState.Index=65535`) |
| 11 | `ST_Guard` | [5] `Locked Down` | `ST_Subtree_Lockdown` | Root (index 0; `LinkedState.Index=65535`) |
| 12 | `ST_Guard` | [17] `Patrolling` | `ST_Patrol` | Root (index 0; `LinkedState.Index=65535`) |
| 13 | `ST_Guard` | [39] `Move to intruder` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 14 | `ST_Guard` | [51] `React to Stims (Guard)` | `ST_InvestigateStims_Guard` | Root (index 0; `LinkedState.Index=65535`) |
| 15 | `ST_Guard` | [52] `React to Downed NPC` | `ST_Subtree_ReviveNPC` | Root (index 0; `LinkedState.Index=65535`) |
| 16 | `ST_Guard` | [55] `Search Area around incapacitate` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 17 | `ST_Guard` | [58] `Search Area` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 18 | `ST_Guard` | [80] `Move To Last Known Position` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 19 | `ST_Guard` | [82] `Move To Last Known Position` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 20 | `ST_Guard` | [87] `Move to intruder` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 21 | `ST_Guard` | [88] `React to spotting Intruder` | `ST_Subtree_SpottedIntruderReaction` | Root (index 0; `LinkedState.Index=65535`) |
| 22 | `ST_Guard` | [89] `Intruder no longer suspicious` | `ST_Subtree_IntruderNoLongerSuspicious` | Root (index 0; `LinkedState.Index=65535`) |
| 23 | `ST_Guard` | [91] `Intruder Reaction` | `ST_Subtree_SpottedIntruderReaction` | Root (index 0; `LinkedState.Index=65535`) |
| 24 | `ST_Guard` | [92] `Intruder no longer suspicious (Spotted)` | `ST_Subtree_IntruderNoLongerSuspicious` | Root (index 0; `LinkedState.Index=65535`) |
| 25 | `ST_Guard` | [105] `Search Near Damage Location` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 26 | `ST_Guard` | [113] `Combat` | `ST_Subtree_Combat` | Root (index 0; `LinkedState.Index=65535`) |
| 27 | `ST_Guard` | [125] `Combat` | `ST_Subtree_Combat` | Root (index 0; `LinkedState.Index=65535`) |
| 28 | `ST_InvestigateStims_Civilian` | [3] `React To Generic Light Stim` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 29 | `ST_InvestigateStims_Civilian` | [4] `React To Generic Heavy Stim` | `ST_TriggerFlee_Civilian` | Root (index 0; `LinkedState.Index=65535`) |
| 30 | `ST_InvestigateStims_Civilian` | [5] `React to Share Knowledge` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 31 | `ST_InvestigateStims_Guard` | [11] `Long Investigation` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 32 | `ST_InvestigateStims_Guard` | [12] `Short Investigation` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 33 | `ST_InvestigateStims_Guard` | [13] `React To Guard Calling For Help` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 34 | `ST_InvestigateStims_Guard` | [14] `React To Touch Stim` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 35 | `ST_InvestigateStims_Guard` | [15] `React to Share Knowledge` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 36 | `ST_InvestigateStims_Guard` | [16] `Standby Behavior` | `ST_Standby_Guards` | Root (index 0; `LinkedState.Index=65535`) |
| 37 | `ST_Subtree_Combat` | [22] `Light Attack` | `ST_Subtree_Combat_ActivateAttack` | Root (index 0; `LinkedState.Index=65535`) |
| 38 | `ST_Subtree_Combat` | [47] `Activate an alarm` | `ST_Subtree_TryActivateAlarm` | Root (index 0; `LinkedState.Index=65535`) |
| 39 | `ST_Subtree_Combat` | [48] `Find Target after Evasion` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 40 | `ST_Subtree_Combat` | [50] `Search Around Current Location` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 41 | `ST_Subtree_Combat_Hauntstable` | [19] `Find Target after Evasion` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 42 | `ST_Subtree_Combat_Hauntstable` | [20] `Search Around Current Location` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 43 | `ST_Subtree_Lockdown` | [5] `Move to and use spot` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 44 | `ST_Subtree_ReviveNPC` | [10] `Search Area around incapacitate` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |
| 45 | `ST_Subtree_ReviveNPC` | [14] `Search Area around incapacitate` | `ST_Subtree_GeneralInvestigateStim` | Root (index 0; `LinkedState.Index=65535`) |

Total 45 links; 45 of 45 have `entry_state_index = null` (raw 65535).

Payload path: `trees.<referrer>.subtree_links[]` =
`{state, state_index, asset, entry_state_index}`; built at
`tools/parse_state_tree.py:481-490` from `States[i].LinkedAsset` and
`States[i].LinkedState` (`linked_asset_name` at 261-269 keeps only the basename
after the `'` and before the `.`).

### 1.3 States whose type is not `State`/`Group`/`LinkedAsset`

`ST_InvestigateStims_Guard` is the only asset with the other two type values:

| state | type | parent | `linked_asset` | `linked_state_index` |
|---|---|---|---|---|
| `[5] Run Substate Tree` | `Linked` | `Register for Reaction Role` (3) | null | 8 |
| `[7] Run Substate Tree without Event` | `Linked` | `Handle Reactions or Non-Reactions` (2) | null | 8 |
| `[8] Substate Tree For Reaction` | `Subtree` | *(none — depth 0)* | null | null |

`Linked` + `LinkedState.Index = 8` is an **intra-asset** entry into state 8
(`Substate Tree For Reaction`), which is itself a second depth-0 state of type
`Subtree`. Neither `Linked` state appears in `subtree_links` (the producer only
lists states with a non-null `LinkedAsset`), and the 9 states under state 8 are
unreachable from `Root` by child/transition edges alone (see §4.2).

### 1.4 Disabled states and transitions (complete list)

Payload `enabled=false`: 7 states, 1 transition.

| tree | state index | name | type | parent |
|---|---|---|---|---|
| `ST_Civilian` | 20 | `Return Loot` | `State` | `Root` |
| `ST_Civilian` | 23 | `React to Spotting Loot` | `State` | `Root` |
| `ST_Guard` | 75 | `Play VO` | `State` | `React To Shared Target` |
| `ST_Subtree_Combat` | 47 | `Activate an alarm` | `LinkedAsset` | `Lost Target` |
| `ST_TriggerFlee_Civilian` | 8 | `Trigger Noise Event` | `State` | `Face Actor` |
| `ST_TriggerFlee_Civilian` | 11 | `Trigger Noise Event` | `State` | `Face Location` |
| `ST_TriggerFlee_Civilian` | 14 | `Trigger Noise Event` | `State` | `VO Fallback (when TurnToFace ends too quickly)` |

The one disabled transition is `ST_Guard` transition 14:
`React To Stims, Intruder, Broken Object and Conversation Event` →
`React to Player Tool`, `OnEvent`, event `StateTreeEvent.TargetChange`,
conditions `["Check Targeting Group Matches"]`.

A separate, node-level flag also exists in the raw dump: `Nodes.Structs[k].
bTaskEnabled = false` on exactly one node (`ST_ClueGiving` node 1,
`STT Set Clue Giving Enabled`, `ActiveInstanceDataObject` index 2, state 0).
The payload does not carry it.

---

## 2. Record shapes and measured value domains

### 2.1 Payload state record — exact keys (16)

Path: `trees.<tree>.states[i]`.

```
index, name, depth, type, parent, parent_index, children, children_range,
tasks, enter_conditions, utility_considerations, transitions, linked_asset,
linked_state_index, enabled, selection_behavior
```

Notes measured from the payload:

* `children` is the list of **direct** children (resolved by the producer by
  scanning `ChildrenBegin..ChildrenEnd` for states whose `Parent.Index` is this
  state, `tools/parse_state_tree.py:347-354`).
* `children_range` is the raw pre-order `[ChildrenBegin, ChildrenEnd)` span and
  includes **every descendant**, not only direct children.
* `parent` is the parent's name (or `null` at depth 0); `parent_index` is the raw
  index (`65535` → `null`).
* `linked_state_index` is `null` for 457 of the 459 states (including all 45
  `LinkedAsset` states, raw `65535`) and `8` for the two `Linked` states.
* `tasks`, `enter_conditions`, `utility_considerations` are arrays of **plain
  strings** (display names), never objects.
* `transitions` is an array of a reduced 9-key form:
  `{index, to_state, to_state_index, to_kind, trigger, priority, required_event,
  conditions, enabled}`.

Example (`ST_Patrol` state 5, abridged; note `children` is 4 direct children
while `children_range` is the wider pre-order span):

```json
{"index":5,"name":"Has Broken Location?","depth":3,"type":"State",
 "parent":"Patrol","parent_index":3,"children":[6,7,8,9],
 "children_range":[6,10],"tasks":[],"enter_conditions":["Bool Compare"],
 "utility_considerations":[],
 "transitions":[{"index":5,"to_state":"Reset Alertness","to_state_index":10,
                 "to_kind":"state","trigger":"OnStateCompleted","priority":"None",
                 "required_event":"","conditions":[],"enabled":true}],
 "linked_asset":null,"linked_state_index":null,"enabled":true,
 "selection_behavior":"TrySelectChildrenInOrder"}
```

### 2.2 Payload transition record — exact keys (14 full / 9 nested)

Full record: `trees.<tree>.transitions[k]`.

```
index, from_state, from_state_index, to_state, to_state_index, to_kind,
trigger, priority, required_event, conditions, enabled, delay_seconds,
delay_random_variance, fallback
```

Nested per-state copy (`states[i].transitions[j]`) omits the five source/delay
keys:

```
index, to_state, to_state_index, to_kind, trigger, priority, required_event,
conditions, enabled
```

`to_state` is `null` for the 50 terminal targets; `to_state_index` keeps the raw
special handle (65534 `Succeeded`, 65533 `Next`).

### 2.3 Task / enter-condition / utility-consideration entry

There is **no node record in the payload**. Each entry is a JSON string:

* task entry = `trees.<tree>.states[i].tasks[j]` → `"TATState Tree Task Set Alertness"`;
* enter-condition entry = `...enter_conditions[j]` → `"Bool Compare"`;
* utility consideration = `...utility_considerations[j]` → 0 entries in all 21 trees;
* transition-condition entry = `trees.<tree>.transitions[k].conditions[j]` → `"Check Distance From Owner"`.

The only per-tree metadata about them is the name sets
`trees.<tree>.tasks` / `trees.<tree>.conditions` and the counts in `stats`.

### 2.4 Raw node record — the observed shapes

Path: `Properties.Nodes.Structs[k]`. `Properties.Nodes` has exactly one key,
`Structs`; there is **no** `Nodes.DefaultInstanceData` (the instance data is a
sibling `Properties.DefaultInstanceData`).

| shape | count | extra keys beyond `Name/BindingsBatch/InstanceTemplateIndex/InstanceDataHandle` | what it is |
|---|---|---|---|
| native task | 199 | `bTaskEnabled`, `TransitionHandlingPriority` (9 of them also `ShouldTrackLocation`; 2 `Text/TextColor/FontScale/Offset/bEnabled` Debug Text; `Operand/Operator/bInvert/bExactMatch/KnowledgeTagToCheck` appear only on conditions) | C++ task instance data |
| blueprint task | 127 | `TaskClass` (a `BlueprintGeneratedClass'…'` object ref) + the same two task flags | BP task instance |
| native condition | 221 | `Operand`, `DeltaIndent`, `EvaluationMode`, plus per-type extras: `bInvert` (44), `bExactMatch` (6), `Operator` (2), `Invert` (1), `KnowledgeTagToCheck` (1) | C++ condition instance data |
| blueprint condition | 12 | `ConditionClass` + `Operand/DeltaIndent/EvaluationMode` | BP condition instance |
| property function | 6 | *(none)* — only the five common keys | `Get Actor Location`, used as a binding source, not a state entry |
| global evaluator | 1 | *(none)* | `ST_Guard` `Difficulty Evaluator` |

`InstanceTemplateIndex` and `InstanceDataHandle` are present on all 566 nodes
(100 %), and `BindingsBatch` too. 455 nodes point at a real `CopyBatches` entry;
111 carry `BindingsBatch.Value = 65535` (no bindings).

### 2.5 Payload value domains (all 21 trees)

| field | value | count |
|---|---|---|
| state `type` | `State` | 376 |
| | `Group` | 35 |
| | `LinkedAsset` | 45 |
| | `Linked` | 2 |
| | `Subtree` | 1 |
| state `selection_behavior` | `TrySelectChildrenInOrder` | 439 |
| | `TryEnterState` | 20 |
| state `enabled` | `true` / `false` | 452 / 7 |
| transition `trigger` | `OnStateCompleted` | 284 |
| | `OnEvent` | 89 |
| | `OnStateSucceeded` | 38 |
| | `OnStateFailed` | 36 |
| | `OnTick` | 20 |
| transition `priority` | `None` | 358 |
| | `Normal` | 67 |
| | `Medium` | 21 |
| | `Critical` | 12 |
| | `High` | 9 |
| transition `to_kind` | `state` | 417 |
| | `Succeeded` | 35 |
| | `Next` | 15 |
| transition `enabled` | `true` / `false` | 466 / 1 |
| transition `fallback` | `None` | 428 |
| | `NextSelectableSibling` | 39 |
| transition `delay_seconds` | `0.0` | 467 (none non-zero) |
| transition `delay_random_variance` | `0.0` | 467 (none non-zero) |
| transition `required_event` | non-empty | 89 (17 distinct tags) |
| state `depth` | 0 / 1 / 2 / 3 / 4 / 5 / 6 / 7 | 22 / 81 / 114 / 118 / 69 / 24 / 25 / 6 |
| states with ≥1 task | — | 308 |
| states with ≥1 enter condition | — | 64 |
| states with ≥1 transition | — | 349 |
| states with children | — | 131 |
| max tasks / enter conditions / transitions on one state | — | 3 / 3 / 11 |

The raw dump agrees exactly on `Type`, `SelectionBehavior`, `bEnabled` and on
`Delay` (`{(0,0): 467}`; `0` transitions with a non-zero `duration` or
`RandomVariance`).

The 17 distinct `required_event` tags and their transition counts:

| event | count |
|---|---|
| `StateTreeEvent.TargetChange` | 48 |
| `StateTreeEvent.StimChange` | 14 |
| `StateTreeEvent.GameplayTagChange` | 10 |
| `StateTreeEvent.ConversationEvent` | 2 |
| `StateTreeEvent.ReactionRoleChange` | 2 |
| `StateTreeEvent.LockdownNewAlarmGuard` | 2 |
| `StateTreeEvent.AbandonLockdown` | 1 |
| `StateTreeEvent.Civilian.Flee` | 1 |
| `StateTreeEvent.ClueChange` | 1 |
| `StateTreeEvent.ConversationEvent.Response` | 1 |
| `StateTreeEvent.DistractionEvent` | 1 |
| `StateTreeEvent.LockdownEvent` | 1 |
| `StateTreeEvent.LockdownGuardLeaving` | 1 |
| `StateTreeEvent.LockdownHoldPosition` | 1 |
| `StateTreeEvent.ReactionEventEnd` | 1 |
| `StateTreeEvent.SharePartnerLost` | 1 |
| `StateTreeEvent.ShareTarget` | 1 |

`OnEvent` transitions = 89 = the number with a non-empty `required_event`, i.e.
the payload never has an `OnEvent` transition without an event tag and never a
non-`OnEvent` transition with one (the untracked
S1 `tree_model.gd` asserts this; the producer does not).

### 2.6 Utility considerations

`utility_considerations` is empty for all 459 states and the payload records no
utility node in `Nodes.Structs` either: `UtilityConsiderationsBegin/Num` ranges
are all empty (`0` instances). The 9 `Targeting/DA_TargetingConsideration_*`
assets are separate data assets listed in `payload.targeting_considerations`
and are **not** referenced from any tree by name.

---

## 3. What the payload omits vs the raw dump

Producer reads (verified against `tools/parse_state_tree.py`): `build_tree()`
reads only `Properties.States`, `Properties.Transitions`,
`Properties.Nodes.Structs` and `Properties.EvaluatorsNum` (the last at
line 505); from each state it reads `Name, Depth, Parent.Index,
ChildrenBegin/ChildrenEnd, TasksBegin/TasksNum,
EnterConditionsBegin/Num, UtilityConsiderationsBegin/Num,
TransitionsBegin/Num, Type, SelectionBehavior, bEnabled, LinkedAsset,
LinkedState.Index`; from each transition `State.Index,
RequiredEvent.Tag.TagName, ConditionsBegin/Num, Trigger, Priority, Fallback,
Delay.duration, Delay.RandomVariance, bTransitionEnabled`; from each node only
`Name`; and from the asset record `Name`/`Package`. It never reads `Tag`,
`RequiredEventToEnter`, `ParameterTemplateIndex`, `ParameterDataHandle`,
`ParameterBindingsBatch`, `EventDataIndex`, `InstanceDataNum`, `Weight`,
`bConsumeEventOnSelect`, `bHasTransitionTasks`, `bHasStateChangeConditions`,
`bCheckPrerequisitesWhenActivatingChildDirectly`, any `DefaultInstanceData`,
`SharedInstanceData`, `PropertyBindings`, `Parameters`, `ContextDataDescs`,
`Schema`, `IDTo*Mappings`, `NumContextData`, `NumGlobalInstanceData` or
`GlobalTasksBegin`. `build_leaf()` records the leaf's `Name`, `Class`,
`Package`, its `Function` export names and (for targeting considerations) the
`TargetingConsiderationInput` exports' names/classes/Properties; it drops the
Blueprint CDO export and every `ChildProperties` declaration.

Three representative assets, measured:

| | `SubTrees/ST_Patrol` | `ST_Guard` | `SubTrees/ST_Subtree_Combat` |
|---|---|---|---|
| states / transitions | 23 / 22 | 126 / 148 | 52 / 57 |
| `Nodes.Structs` | 28 | 160 | 73 |
| `DefaultInstanceData…Structs` | 42 | 206 | 88 |
| `SharedInstanceData…Structs` | 9 | 80 | 37 |
| `ContextDataDescs` | 2 (`Actor`, `AIController`) | 2 (`Actor`, `AIController`) | 2 (`Actor`, `AIController`) |
| asset `Parameters.PropertyDescs` | `ResetAlertness` | `ShouldReactToIncorrectObjects`, `ShouldReviveNPCs` | `TargetingTag`, `ShouldCheckIfTargetIdentified` |
| asset `Parameters.SerialSize` | 3 | 4 | 13 |
| `PropertyBindings.SourceStructs` | 56 | 330 | 133 |
| `…CopyBatches` | 26 | 125 | 73 |
| `…PropertyPathBindings` | 37 | 173 | 105 |
| `…PropertyReferencePaths` | 5 | 30 | 6 |
| `…PropertyAccesses` | 5 | 30 | 6 |
| `IDToStateMappings/NodeMappings/TransitionMappings` | 23/28/22 | 126/160/148 | 52/73/57 |
| `Schema` | `StateTreeAIComponentSchema'…'` | same | same |
| `EvaluatorsNum` | absent (0) | 1 | absent (0) |

`Schema`, `LastCompiledEditorDataHash`, `IDTo*Mappings`, `NumContextData`,
`NumGlobalInstanceData`, `GlobalTasksBegin`, `ContextDataDescs`, `Parameters`,
`PropertyBindings`, `DefaultInstanceData`, `SharedInstanceData` are **absent
from the payload entirely**. The payload top-level keys are only
`schema, game_version, source, units, roots, stats, trees, condition_classes,
task_blueprints, targeting_considerations, other_blueprints`
(`tools/parse_state_tree.py:881-933`).

Field-by-field, for the three assets:

| raw path | in payload? |
|---|---|
| `States[i].Name` | yes (`name`) |
| `States[i].Depth` | yes (`depth`) |
| `States[i].Parent.Index` | yes (`parent`, `parent_index`) |
| `States[i].ChildrenBegin/ChildrenEnd` | yes (`children_range`, plus resolved direct `children`) |
| `States[i].Type` | yes (`type`, enum tail) |
| `States[i].SelectionBehavior` | yes (`selection_behavior`) |
| `States[i].bEnabled` | yes (`enabled`) |
| `States[i].LinkedAsset` | partial: basename only (`linked_asset`); the `/Game/...` object path is dropped |
| `States[i].LinkedState.Index` | yes (`linked_state_index`, 65535 → null) |
| `States[i].Tag` | **no** — non-`None` on 3 `ST_Guard` states (§3.4) |
| `States[i].RequiredEventToEnter` | **no** — non-`None` on 3 states (§3.4) |
| `States[i].ParameterTemplateIndex` | **no** |
| `States[i].ParameterDataHandle`, `ParameterBindingsBatch` | **no** |
| `States[i].EventDataIndex`, `InstanceDataNum` | **no** |
| `States[i].Weight` | **no** |
| `States[i].bConsumeEventOnSelect`, `bHasTransitionTasks`, `bHasStateChangeConditions`, `bCheckPrerequisitesWhenActivatingChildDirectly` | **no** |
| `Transitions[j].State.Index` | yes (`to_state_index`/`to_state`/`to_kind`) |
| `Transitions[j].Trigger`, `Priority`, `Fallback` | yes (enum tails) |
| `Transitions[j].RequiredEvent.Tag.TagName` | yes (`required_event`) |
| `Transitions[j].RequiredEvent.PayloadStruct` | **no** |
| `Transitions[j].ConditionsBegin/Num` | yes, resolved to names |
| `Transitions[j].Delay.duration/RandomVariance` | yes (`delay_seconds`, `delay_random_variance`) — all zero |
| `Transitions[j].bTransitionEnabled` | yes (`enabled`) |
| `Transitions[j].bConsumeEventOnSelect` | **no** |
| `Nodes.Structs[k].Name` | yes |
| `Nodes.Structs[k].InstanceTemplateIndex` | **no** |
| `Nodes.Structs[k].InstanceDataHandle` (`Source/Index/StateHandle.Index`) | **no** |
| `Nodes.Structs[k].BindingsBatch` | **no** |
| `Nodes.Structs[k].bTaskEnabled`, `TransitionHandlingPriority` | **no** |
| `Nodes.Structs[k].TaskClass`, `ConditionClass` | **no** |
| `Nodes.Structs[k].Operand`, `EvaluationMode`, `DeltaIndent` | **no** |
| `Nodes.Structs[k].bInvert` / `bExactMatch` / `Operator` / `KnowledgeTagToCheck` / `ShouldTrackLocation` / Debug Text fields | **no** |
| `DefaultInstanceData.Data.InstanceStructs.Structs[0..N]` | **no** |
| `SharedInstanceData.Data.InstanceStructs.Structs[0..N]` | **no** |
| `PropertyBindings.SourceStructs[]` | **no** |
| `PropertyBindings.CopyBatches[]` | **no** |
| `PropertyBindings.PropertyPathBindings[]` | **no** |
| `PropertyBindings.PropertyReferencePaths[]`, `PropertyAccesses[]` | **no** |
| `Parameters.PropertyDescs/SerialSize` | **no** |
| `ContextDataDescs[]` | **no** |
| `EvaluatorsNum` | yes, as `trees.<name>.stats.global_evaluators` (count only) |

The producer's own docstring records the intent: node names are copied from
`Nodes.Structs[k].Name` and the "cooked dump does not serialise the node's
UClass on the struct itself" (`tools/parse_state_tree.py:23-27`). That statement
is **only true for the 427 native nodes**: the 139 blueprint nodes do carry
`TaskClass`/`ConditionClass` inline (see §3.4).

### 3.1 Question (a): are TASK parameters recoverable from the raw dump?

**Yes for 260 of 326 task instances.** The full chain is:

1. `Properties.Nodes.Structs[n].InstanceTemplateIndex.Value` = `t`;
2. for `InstanceDataHandle.Source` ∈ {`ActiveInstanceData`,
   `ActiveInstanceDataObject`}: the parameter struct is
   `Properties.DefaultInstanceData.Data.InstanceStructs.Structs[t]`
   (note: `DefaultInstanceData` is a **sibling of `Nodes`**, not
   `Nodes.DefaultInstanceData` — `Properties.Nodes` has only `Structs`);
3. for `ActiveInstanceData` the struct holds the native fields directly;
   for `ActiveInstanceDataObject` the struct is `{InstanceObject:{ObjectName,
   ObjectPath}}` and `ObjectPath` = `"<package>.N"`, i.e. **export `N` of the
   same tree file**, whose `Properties` object holds the per-instance overrides
   and whose `Template.ObjectPath` names the Blueprint CDO in the leaf asset.

Measured counts over all 21 trees (`326` task nodes = `199` native + `127` BP):

| task instance shape | count |
|---|---|
| native struct with ≥1 non-null authored value | 190 |
| native struct with only null/default fields (`{AIController:null}`, `{ReferenceActor:null}`, `{AIController:null,Target:null}`, …) | 9 |
| BP instance object with per-instance overrides in the tree export | 70 |
| BP instance object with no overrides (class CDO defaults apply) | 57 |
| property-bag instance struct (schema only, no values) | 0 |
| **total with an authored per-instance value** | **260 / 326 (79.8 %)** |

Worked examples with exact paths:

* `extracted/json/AI/StateTrees/SubTrees/ST_Patrol.json`
  `Properties.Nodes.Structs[0]` = `TATState Tree Task Set Alertness`,
  `InstanceTemplateIndex.Value = 2` →
  `Properties.DefaultInstanceData.Data.InstanceStructs.Structs[2]` =
  `{"AIController": null, "AlertnessLevel": "EAlertnessLevel::Neutral",
  "RunUntilAnimationFinished": true}`.
  All 20 `TATState Tree Task Set Alertness` instances resolve; the authored
  values are `Alerted`×7, `Neutral`×5, `Combat`×3, `Alerted`+
  `RunUntilAnimationFinished=false`×2, `Suspicious`×2, `Combat`+`false`×1.
* `SubTrees/ST_Patrol.json` `Nodes.Structs[16]` = `Delay Task`,
  `InstanceTemplateIndex.Value = 36` →
  `DefaultInstanceData…Structs[36]` =
  `{"duration": 100.0, "RandomDeviation": 0.0, "bRunForever": false}`.
  The 32 `Delay Task` instances have 9 distinct value sets; durations measured:
  0.2, 1.0 (×25), 2.0, 4.0, 20.0 (with `RandomDeviation` 5.0), 50.0 (×2),
  100.0; `bRunForever=true` on 13 of them.
* `ST_Guard.json` `Nodes.Structs[34]` = `Delay Task`,
  `InstanceTemplateIndex.Value = 77` → `{duration: 2.0, …}`.
* BP task with overrides: `SubTrees/ST_Patrol.json` `Nodes.Structs[3]` =
  `Repeatedly Trigger VO`, `InstanceTemplateIndex.Value = 7` →
  `DefaultInstanceData…Structs[7]` =
  `{InstanceObject:{ObjectName:"STT_RequestVOLine_Repeating_C'ST_Patrol:…_1'",
  ObjectPath:"/Game/AI/StateTrees/SubTrees/ST_Patrol.6"}}` → export `[6]` of
  `ST_Patrol.json` has
  `Properties = {VOLineTag:{TagName:"VoiceLine.Conditional.IdleAloneOnPatrol"},
  Delay:7.0, DelayVariation:2.0, StartVariation:2.0}`.
* BP task without overrides: `SubTrees/ST_Patrol.json`
  `Nodes.Structs[1]` = `STT Distraction Smart Objects` → struct
  `{InstanceObject: …}` → export `[4]` has no `Properties`, so the class
  defaults apply; those defaults are in
  `extracted/json/AI/StateTrees/Tasks/Patrol/Distraction/STT_DistractionSmartObjects.json`
  export `Default__STT_DistractionSmartObjects_C.Properties` =
  `{bShouldCopyBoundPropertiesOnTick:…, bShouldStateChangeOnReselect:…}`.
  The producer's `build_leaf()` records only `functions` from such a leaf dump
  (`tools/parse_state_tree.py:530-543`) and drops the CDO `Properties`.

Blueprint CDO defaults are present in all 34 leaf dumps (each has a
`Default__<Class>_C` export). 18 of the 34 carry ≥1 authored CDO property; e.g.
`STT_RequestVOLine_C` → `{Delay, VOLineTag}`,
`STT_TriggerAndWaitForAnimation_C` → `{Abort Tag, End Tag,
InitialLocationToWatchValue, LocationToWatch, SearchLocation, Start Tag}`,
`STT_UseSmartObjectWithClaimedHandle_C` → `{Behavior Class, Claim Handle}`.
`STC_PatrolPathPointIsOfType_C`, `STC_BlackboardActorIsSet_C`,
`STC_HasClue_C`, `STC_IsCarryingMajorLoot_C`, `STT_ClearFocus_C`,
`STT_SetFocus_C`, `STT_ShareTarget_C`, `STT_SetAttitudeToTarget_C`,
`STT_RememberTargetToShare_C`, `STT_InteractWithInteractable_C`,
`STT_UseSmartObjectWithTargetActor/Component_C`,
`STT_TryClaimContextualLocation_C`, `STT_SetContextualLocationInUse_C` have an
empty CDO `Properties` (only inherited/transient keys).

### 3.2 Question (b): are ENTER-CONDITION and TRANSITION-CONDITION parameters recoverable?

**Yes for 209 of the 233 referenced condition instances** (and 0 of the 6
`Get Actor Location` property functions, which have no authored value). Same `InstanceTemplateIndex`
chain, but the array is
`Properties.SharedInstanceData.Data.InstanceStructs.Structs[t]` because the
handle `Source` is `SharedInstanceData` / `SharedInstanceDataObject` (shared
because conditions are evaluated as transition/enter tests and are not
per-state activations). Condition nodes carry `Operand`, `DeltaIndent`,
`EvaluationMode` inline on the node, and the class via
`PropertyBindings.SourceStructs[].Struct.ObjectName` (native) or
`Nodes.Structs[k].ConditionClass` (BP).

Measured counts (239 = 233 referenced conditions + 6 `Get Actor Location`
property functions):

| condition instance shape | count |
|---|---|
| native struct with ≥1 non-null authored value | 205 |
| native struct with only null/default fields (`{Object:null}` etc.) | 22 |
| BP instance object with per-instance overrides | 4 |
| BP instance object with no overrides | 8 |
| **total with an authored per-instance value** | **209 / 239 (87.4 %)** |

Worked examples:

* `SubTrees/ST_Patrol.json` `Nodes.Structs[19]` = `Bool Compare`,
  `InstanceTemplateIndex.Value = 0` →
  `SharedInstanceData…Structs[0]` = `{"bLeft": false, "bRight": true}`.
  *Which* bool is supplied by
  `PropertyBindings.CopyBatches[17]` →
  `PropertyPathBindings[27]`: `TargetPropertyPath = ["bLeft"]`,
  `SourceDataHandle = {Source:"GlobalParameterData", Index:65535}`,
  `SourcePropertyPath = ["ResetAlertness"]`.
  So this condition is `ResetAlertness == true`.
  The other ST_Patrol instances bind `bLeft` the same way (batches 18, 21,
  25): state-3 `PatrolWasInterrupted`, `GlobalParameterData.ResetAlertness`,
  state-3 `PatrolPointData.HasFacing`. The struct's own `bRight` is the
  expected value (8 instances `true`, 7 `false` across all trees).
* `SubTrees/ST_Patrol.json` `Nodes.Structs[24]` = `Patrol Point Is Of Type`,
  `InstanceTemplateIndex.Value = 5` → `{InstanceObject: …C_2}` → export `[2]`
  of `ST_Patrol.json`, `Properties = {"PatrolPathType":
  "EPatrolPointType::SmartObjectInteraction"}`; the comparison target comes
  from `PropertyPathBindings[33]`:
  `TargetPropertyPath = ["TargetPatrolPathType"]` ←
  `StateParameterData[3] (state 3) . PatrolPointData.PatrolPointType`.
  The second `Patrol Point Is Of Type` instance (node 26, export `[3]`) has no
  `Properties`, so its own `PatrolPathType` keeps the CDO value (the CDO dump
  has no authored value for either enum field → the class default).
* `SubTrees/ST_Patrol.json` `Nodes.Structs[21]` = `Distance Compare`,
  `InstanceTemplateIndex.Value = 2` →
  `SharedInstanceData…Structs[2]` = `{"Source":{0,0,0},"Target":{0,0,0},
  "Distance":3000.0}`; `Source` ← `Get Actor Location.Output`,
  `Target` ← state-3 param `PatrolBrokenLocation`.
* Transition condition: `SubTrees/ST_Subtree_Combat.json`
  `Nodes.Structs[50]` = `Check Distance From Owner`,
  `InstanceTemplateIndex.Value = 14` →
  `SharedInstanceData…Structs[14]` = `{"Controller":null,"Target":null,
  "ComparisonValue":1200.0,"ComparisonMethod":"EOSEComparisonMethod::LessThanOrEqualTo"}`.
  This is the exact `value/operator` pair the report question asked for, and it
  is present verbatim in the dump.
* `Bool Compare` in an enter condition and in a transition condition are the
  same class (`StateTreeCompareBoolConditionInstanceData`, 15 instances) — the
  payload's split between `enter_conditions` and transition `conditions` does
  not change the node record.

`Patrol Point Is Of Type` totals 2 instances (1 with `PatrolPathType =
SmartObjectInteraction`, 1 without), and `Distance Compare` totals 1 instance
(`3000.0`). `Bool Compare` totals 15 (`{false,true}`×8, `{false,false}`×7).

### 3.3 Node-class mapping: provable, and how

The mapping from a display name to a class is recoverable for **566 / 566**
nodes, by two different routes:

* **139 BP nodes** carry the class inline:
  `Nodes.Structs[k].TaskClass` (127) or `.ConditionClass` (12), each a
  `{"ObjectName": "BlueprintGeneratedClass'STT_…_C'", "ObjectPath":
  "/Game/AI/StateTrees/…"}` object.
* **427 native nodes** (199 tasks + 221 conditions + 6 property functions + the
evaluator) have no class field, but
  `PropertyBindings.SourceStructs[m]` gives
  `Struct.ObjectName` (e.g. `Class'StateTreeCompareBoolConditionInstanceData'`)
  for the matching `DataHandle` `(Source, Index, StateHandle.Index)`. 565 nodes
  match an `ActiveInstanceData`/`SharedInstanceData` entry; the evaluator
  matches the `GlobalInstanceData` entry
  (`Struct = Class'TATDifficultyEvaluatorData'`,
  `DataSource = EStateTreeBindableStructSource::Evaluator`).

For native nodes this names the **instance-data struct**, not the StateTree node
class: the node UClass itself is not serialised. Whether that proxy is 1:1 is
measurable from the dump: 104 distinct data-struct classes cover the 115 node
names (114 task/condition/property-function names + the one evaluator), with 12
structs shared by two display names (§5.6) and one display name
(`Run Env Query`) shared by two structs. So the mapping is not injective in
either direction; a runtime needs the `(display name, class)` pair, not the name
alone.

### 3.4 What is **not** provable from the dump

| item | why |
|---|---|
| **State parameter values** | 93 of 459 states have a non-empty state-parameter schema (`States[i].ParameterTemplateIndex` → `DefaultInstanceData…Structs[t].Parameters.PropertyDescs`, 77 distinct names: `InnerSearchRadius`×25, `OuterSearchRadius`×25, `InitialDelayDuration`×23, `LoopCount`×23, `AlertnessToRaiseTo`×22, `DelayDuration`×22, `InitialInvestigationVOLine`×22, `InvestigationSearchingVOLine`×22, `InvestigationGiveUpVOLine`×22, `InitialSearchLocation`×22, `Target`×14, `TargetActor`×13, …). Only the schema (`Name`, `ValueType`, `ID`) and `SerialSize` are serialised; no value bytes and no default values. The same is true for the 12 assets with a non-empty asset-level `Parameters` schema (`ShouldReactToIncorrectObjects`, `ShouldReviveNPCs`, `TargetingTag`, `ShouldCheckIfTargetIdentified`, …): `SerialSize` 3–55, zero values. |
| **Linked-subtree input wiring is partial** | A `LinkedAsset` state gets the subtree's parameter schema (e.g. `ST_Guard` state 39 `Move to intruder` → `ParameterTemplateIndex 67`, schema with `AlertnessToRaiseTo`, `InitialDelayDuration`, `DelayDuration`, `LoopCount`, `InitialInvestigationVOLine`, `InvestigationSearchingVOLine`, `InvestigationGiveUpVOLine`, `InitialSearchLocation`, `InnerSearchRadius`, `OuterSearchRadius`). Of those 10 inputs, the referrer wires **one** (`PropertyPathBindings[43]`: parent state 36 `SearchLocation` → linked state `InitialSearchLocation`). The other 9 are only named. |
| **Difficulty evaluator selection** | `ST_Guard` `Nodes.Structs[0]` `Difficulty Evaluator`, `GlobalInstanceData[0]`, `DefaultInstanceData…Structs[0]` = `{"Difficulty":"ETATDifficulty::Normal","VigilantLoopCount":1}`. That is one hard-coded value; the per-difficulty behaviour is not in the dump. The producer only counts `EvaluatorsNum` (`stats.global_evaluators = 1` for `ST_Guard`, 0 elsewhere). |
| **EQS query assets behind `Run Env Query`** | The task parameter *is* recoverable: 19 instances (17 `TATStateTreeRunEnvQueryInstanceData`, 2 `StateTreeRunEnvQueryInstanceData`) carry `QueryTemplate` in the native struct, e.g. `ST_Civilian` node 13 → `{"QueryTemplate":{"ObjectName":"EnvQuery'EQS_FindMajorLootReturnLocation'","ObjectPath":"/Game/AI/EQS/EnvironmentQuery/EQS_FindMajorLootReturnLocation.0"},"RunMode":"EEnvQueryRunMode::SingleResult",…}`. The 19 instances name 11 distinct queries. What the payload does **not** carry is the reference or the query definition; the EQS assets themselves are dumped separately (15 JSON files under `extracted/json/AI/EQS/`, e.g. `EnvironmentQuery/EQS_FindInvestigationLocation.json`) and are outside `guard_behavior.json`. |
| **Blueprint task/condition behaviour** | The leaf dumps carry the class, `ChildProperties` (declared fields with types), `FuncMap`/`Children` function names, and the CDO `Properties`. They do **not** carry the ubergraph bytecode or node graph; `functions` in the payload is only the name list. |
| **Node UClass for native tasks** | Already covered: only the instance-data struct is serialised. The producer's note (`parse_state_tree.py:25-27`) says "the cooked graph does not serialise the node UClass" — true for the 427 native nodes, false for the 139 BP nodes. |
| **`RequiredEventToEnter` and state `Tag`** | Both are authored **non-`None`** on three states each, and the payload keeps neither. `Tag`: `ST_Guard` [91] `Intruder Reaction` = `AI.StateTree.IntruderInitialReaction`; `ST_Guard` [113] `Combat` = `AI.StateTree.Combat`; `ST_Guard` [125] `Combat` = `AI.StateTree.ForcedAgro`. `RequiredEventToEnter`: `ST_InvestigateStims_Guard` [6] `Extract Reaction Role from Event` = `StateTreeEvent.ReactionRoleChange`; `ST_Patrol` [21] `Extract distraction Event` = `StateTreeEvent.DistractionEvent`; `ST_Subtree_Combat` [6] `Extract Reaction Role from Event` = `StateTreeEvent.ReactionRoleChange`. The two sets are disjoint (3 + 3 states); the remaining 453 states carry `None` in both fields. |
| **Transition `Delay`** | Raw `Delay.duration` and `RandomVariance` are `0` on all 467 transitions, so the payload's `delay_seconds = 0.0` everywhere is not a producer loss — there is nothing to carry. |

---

## 4. Reachability

### 4.1 Entry state per tree

All 20 single-root trees enter at state 0 `Root`. `ST_InvestigateStims_Guard`
has two depth-0 states: state 0 `Root` (type `State`) and state 8
`Substate Tree For Reaction` (type `Subtree`), reached from two `Linked` states
(§1.3).

| tree | `roots` (payload) | entry | states / note |
|---|---|---|---|
| `ST_Civilian` | `Root` | 0 `Root` | 73 |
| `ST_ClueGiving` | `Root` | 0 `Root` | 9 |
| `ST_Guard` | `Root` | 0 `Root` | 126 |
| `ST_InvestigateStims_Civilian` | `Root` | 0 `Root` | 6 |
| `ST_InvestigateStims_Guard` | `Root`, `Substate Tree For Reaction` | 0 `Root` | 17; second depth-0: [8] `Substate Tree For Reaction` (Subtree) |
| `ST_OffNavLink` | `Root` | 0 `Root` | 3 |
| `ST_Patrol` | `Root` | 0 `Root` | 23 |
| `ST_SmartObject_DefensiveSpot` | `Root` | 0 `Root` | 3 |
| `ST_Standby_Guards` | `Root` | 0 `Root` | 4 |
| `ST_Subtree_Combat` | `Root` | 0 `Root` | 52 |
| `ST_Subtree_Combat_ActivateAttack` | `Root` | 0 `Root` | 4 |
| `ST_Subtree_Combat_Hauntstable` | `Root` | 0 `Root` | 22 |
| `ST_Subtree_Flee` | `Root` | 0 `Root` | 32 |
| `ST_Subtree_GeneralInvestigateStim` | `Root` | 0 `Root` | 23 |
| `ST_Subtree_IntruderNoLongerSuspicious` | `Root` | 0 `Root` | 4 |
| `ST_Subtree_Lockdown` | `Root` | 0 `Root` | 13 |
| `ST_Subtree_ReviveNPC` | `Root` | 0 `Root` | 16 |
| `ST_Subtree_SpottedIntruderReaction` | `Root` | 0 `Root` | 4 |
| `ST_Subtree_SpottedIntruderReaction_Hauntstable` | `Root` | 0 `Root` | 4 |
| `ST_Subtree_TryActivateAlarm` | `Root` | 0 `Root` | 4 |
| `ST_TriggerFlee_Civilian` | `Root` | 0 `Root` | 17 |

### 4.2 Reachability counts (child-selection + transition edges, no subtree expansion)

BFS from the entry over direct children and `to_kind == "state"` transitions:

| tree | reachable | unreachable |
|---|---|---|
| all 20 single-root trees | all states | 0 |
| `ST_InvestigateStims_Guard` | 8 / 17 from state 0 | 9: `[8] Substate Tree For Reaction` and the 8 states under it (`[9]`–`[16]`) |

Adding the two `Linked` → state 8 edges makes `ST_InvestigateStims_Guard`
17 / 17 reachable. No tree has a dangling transition target: every
`to_state_index` with `to_kind == "state"` is in range, and the 50 terminal
targets are exactly the 35 `Succeeded` (65534) + 15 `Next` (65533) handles.

### 4.3 `ST_Patrol` — every state, depth-indented

Format: `[index] <indent><name> <type> sel=<selection_behavior>` then
`tasks:`, `enter:`, and one line per outgoing transition
`T#<index> <trigger>/<priority> [event=<tag>] → <target> [conditions]`.
`**DISABLED**` marks `enabled=false`.

`[0]` **Root**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[1]`   **Set Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: Bool Compare  
T#0 OnStateCompleted/None → Distractable Window [—]  

`[2]`   **Distractable Window**  <State> sel=TrySelectChildrenInOrder  
tasks: STT Distraction Smart Objects  
enter: —  

`[3]`     **Patrol**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Persist Patrol Data, Repeatedly Trigger VO  
enter: —  
T#1 OnStateSucceeded/None → <Succeeded> [—]  
T#2 OnEvent/Normal event=StateTreeEvent.DistractionEvent → Extract distraction Event [—]  

`[4]`       **Set Next Patrol Path Point**  <State> sel=TryEnterState  
tasks: TATState Tree Task Setup Patrol  
enter: —  
T#3 OnStateSucceeded/None → Has Broken Location? [—]  
T#4 OnStateFailed/None → Failed [—]  

`[5]`       **Has Broken Location?**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Bool Compare  
T#5 OnStateCompleted/None → Reset Alertness [—]  

`[6]`         **Raise alertness (so we run back)**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: Distance Compare  
T#6 OnStateCompleted/None → Move To Broken Point [—]  

`[7]`         **Move To Broken Point**  <State> sel=TrySelectChildrenInOrder  
tasks: Move To  
enter: —  
T#7 OnStateCompleted/None → Set Alertness [—]  

`[8]`         **Set Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: Bool Compare  
T#8 OnStateCompleted/None → Complete [—]  

`[9]`         **Complete**  <State> sel=TrySelectChildrenInOrder  
tasks: Complete Broken Segment  
enter: —  
T#9 OnStateCompleted/None → Set Next Patrol Path Point [—]  

`[10]`       **Reset Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: —  
T#10 OnStateCompleted/None → Is Patrol Point A Smart Object? [—]  

`[11]`       **Is Patrol Point A Smart Object?**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Patrol Point Is Of Type  

`[12]`         **Move to and Use Smart Object**  <State> sel=TrySelectChildrenInOrder  
tasks: Use Smart Object  
enter: Object Is Valid  
T#11 OnStateCompleted/None → Complete Segment [—]  

`[13]`       **Is Patrol Point A Patrol to Location**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Patrol Point Is Of Type  

`[14]`         **Move To Point**  <State> sel=TrySelectChildrenInOrder  
tasks: Move To  
enter: —  
T#12 OnStateSucceeded/None → Say a Voice Line [—]  
T#13 OnStateFailed/None → Patrol [—]  

`[15]`         **Say a Voice Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Conditional Voice Line  
enter: —  
T#14 OnStateCompleted/None → Rotate [—]  

`[16]`         **Rotate**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Rotate to Face  
enter: Bool Compare  
T#15 OnStateCompleted/None → Delay [—]  

`[17]`         **Delay**  <State> sel=TryEnterState  
tasks: Delay Task  
enter: —  
T#16 OnStateCompleted/None → Complete Segment [—]  

`[18]`       **Complete Segment**  <State> sel=TrySelectChildrenInOrder  
tasks: Complete Patrol Segment  
enter: —  
T#17 OnStateCompleted/None → Set Next Patrol Path Point [—]  

`[19]`       **Failed**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#18 OnStateCompleted/None → Patrol [—]  

`[20]`   **Distractions**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[21]`     **Extract distraction Event**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Distraction Data  
enter: —  
T#19 OnStateSucceeded/None → Move to and use SO [—]  
T#20 OnStateFailed/None → Patrol [—]  

`[22]`     **Move to and use SO**  <State> sel=TrySelectChildrenInOrder  
tasks: STT Use Smart Object with Target Slot Handle  
enter: —  
T#21 OnStateCompleted/None → Patrol [—]  


### 4.4 `ST_Guard` — every state, depth-indented

Same format. 126 states, 148 transitions.

`[0]` **Root**  <State> sel=TrySelectChildrenInOrder  
tasks: Add Targeting Groups  
enter: —  
T#0 OnEvent/Critical event=StateTreeEvent.GameplayTagChange → In Smoke [Check Gameplay Tag Event Matches, Check Target Has Gameplay Tag]  
T#1 OnEvent/Critical event=StateTreeEvent.GameplayTagChange → Unconcious [Check Gameplay Tag Event Matches]  
T#2 OnEvent/Critical event=StateTreeEvent.GameplayTagChange → Cower [Check Gameplay Tag Event Matches, Check Target Has Gameplay Tag]  
T#3 OnEvent/Medium event=StateTreeEvent.TargetChange → Forced Agro [TATState Tree Condition Main Targeting Group Matches, TATState Tree Condition Main Target Matches Actor, Check Target Has Gameplay Tag]  

`[1]`   **Standard States**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#4 OnEvent/Critical event=StateTreeEvent.TargetChange → Combat [TATState Tree Condition Main Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[2]`     **Reset Focus**  <State> sel=TryEnterState  
tasks: Clear Focus  
enter: —  
T#5 OnStateCompleted/None → Return Loot [Is Carrying Major Loot]  
T#6 OnStateCompleted/None → Return To Normal [—]  

`[3]`     **React To Stims, Intruder, Broken Object and Conversation Event**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#7 OnEvent/High event=StateTreeEvent.StimChange → React to Damage [Check Stim Event Matches]  
T#8 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Almost Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#9 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#10 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Spotting Loot [Check Targeting Group Matches]  
T#11 OnEvent/Normal event=StateTreeEvent.ConversationEvent → React To Conversation Event [—]  
T#12 OnEvent/Normal event=StateTreeEvent.ShareTarget → React To Shared Target [—]  
T#13 OnEvent/High event=StateTreeEvent.StimChange → React to Stims (Guard) [—]  
T#14 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Player Tool [Check Targeting Group Matches] **DISABLED**  
T#15 OnEvent/Medium event=StateTreeEvent.TargetChange → React to projectile visible [TATState Tree Condition Main Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  
T#16 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  
T#17 OnStateCompleted/None → Root [—]  

`[4]`       **Return To Normal**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[5]`         **Locked Down**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_Lockdown`  
tasks: —  
enter: STC Blackboard Actor Is Set  
T#18 OnStateCompleted/None → Root [—]  

`[6]`         **Vigilant Escalation**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Check Target Has Gameplay Tag  
T#19 OnStateCompleted/None → Root [—]  

`[7]`           **Set Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: —  
T#20 OnStateCompleted/None → Search Defensive Locations [—]  

`[8]`           **Search Defensive Locations**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[9]`             **EQS**  <State> sel=TrySelectChildrenInOrder  
tasks: Run Env Query  
enter: —  
T#21 OnStateSucceeded/None → Move To Smart Object [—]  
T#22 OnStateFailed/None → Fallback if EQS Failed [—]  

`[10]`             **Fallback if EQS Failed**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[11]`               **Set Target Location in Blackboard**  <State> sel=TryEnterState  
tasks: TATState Tree Task Set Blackboard Value  
enter: —  
T#23 OnStateCompleted/None → Run EQS to Find Investigation Location [—]  

`[12]`               **Run EQS to Find Investigation Location**  <State> sel=TryEnterState  
tasks: Run Env Query  
enter: —  
T#24 OnStateSucceeded/None → Move to nearby location [—]  
T#25 OnStateCompleted/None → Reset Escalation [—]  

`[13]`               **Move to nearby location**  <State> sel=TryEnterState  
tasks: [TAT] Move To  
enter: —  
T#26 OnStateSucceeded/None → Loop [—]  
T#27 OnStateFailed/None → Loop [—]  

`[14]`             **Move To Smart Object**  <State> sel=TrySelectChildrenInOrder  
tasks: STT Use Smart Object with Target Slot Handle  
enter: —  
T#28 OnStateCompleted/None → Loop [—]  

`[15]`             **Loop**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Loop  
enter: —  
T#29 OnStateFailed/None → Reset Escalation [—]  
T#30 OnStateSucceeded/None → Search Defensive Locations [—]  

`[16]`             **Reset Escalation**  <State> sel=TrySelectChildrenInOrder  
tasks: Send Gameplay Event  
enter: —  
T#31 OnStateCompleted/None → Root [—]  

`[17]`         **Patrolling**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Patrol`  
tasks: —  
enter: —  
T#32 OnEvent/Normal event=StateTreeEvent.TargetChange → Greet Player for the first time [Check Targeting Group Matches]  
T#33 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Incorrect or Broken Object [TATState Tree Condition Main Targeting Group Matches, Bool Compare, Check Targeting Data Exists for Targeting Group]  
T#34 OnEvent/Normal event=StateTreeEvent.LockdownEvent → Locked Down [—]  
T#35 OnStateCompleted/None → Root [—]  

`[18]`       **Greet Player for the first time**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#36 OnStateCompleted/None → Root [—]  

`[19]`         **Grab target from the event**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Extract Main Target Data from Event  
enter: —  
T#37 OnStateCompleted/None → Remember the player so we don't greet them again [—]  

`[20]`         **Remember the player so we don't greet them again**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Individual Knowledge  
enter: —  
T#38 OnStateCompleted/None → Look at target [—]  

`[21]`         **Look at target**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Focus (Actor)  
enter: —  
T#39 OnStateCompleted/None → VO Line [—]  

`[22]`         **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#40 OnStateCompleted/None → Reset Focus [—]  

`[23]`         **Reset Focus**  <State> sel=TryEnterState  
tasks: Clear Focus  
enter: —  
T#41 OnStateCompleted/None → Root [—]  

`[24]`       **React to Incorrect or Broken Object**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#42 OnStateCompleted/None → Root [—]  
T#43 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[25]`         **Grab Target From Event**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Target From Targeting Group  
enter: —  
T#44 OnStateCompleted/None → Reactions [—]  

`[26]`         **Reactions**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Update Knowledge Of Actor, Scoped Individual Knowledge  
enter: —  

`[27]`           **Broken Object**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Check Target Has Gameplay Tag  

`[28]`             **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Conditional Voice Line  
enter: —  
T#45 OnStateCompleted/None → Look At [—]  

`[29]`             **Look At**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Focus (Actor)  
enter: —  
T#46 OnStateCompleted/None → Delay [—]  

`[30]`             **Delay**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#47 OnStateCompleted/None → Clear Focus [—]  

`[31]`             **Clear Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Clear Focus  
enter: —  
T#48 OnStateCompleted/None → VO Line [—]  

`[32]`             **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Conditional Voice Line  
enter: —  
T#49 OnStateCompleted/None → Remember the broken object so we don't trigger again [—]  

`[33]`             **Remember the broken object so we don't trigger again**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Individual Knowledge  
enter: —  
T#50 OnStateCompleted/None → Root [—]  

`[34]`           **Incorrect Object State**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Check Target Has Gameplay Tag  

`[35]`             **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#51 OnStateCompleted/None → Has this recently been triggered? [—]  

`[36]`             **Has this recently been triggered?**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Has Individual Knowledge  
T#52 OnStateCompleted/None → Remember Actor [—]  

`[37]`               **Set Target Location in Blackboard**  <State> sel=TryEnterState  
tasks: TATState Tree Task Set Blackboard Value  
enter: —  
T#53 OnStateCompleted/None → Run EQS to Find Investigation Location [—]  

`[38]`               **Run EQS to Find Investigation Location**  <State> sel=TryEnterState  
tasks: Run Env Query  
enter: —  
T#54 OnStateCompleted/None → Move to intruder [—]  

`[39]`               **Move to intruder**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  

`[40]`             **Remember Actor**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Individual Knowledge  
enter: —  
T#55 OnStateCompleted/None → Move to and Use Smart Object [—]  

`[41]`             **Move to and Use Smart Object**  <State> sel=TryEnterState  
tasks: STT Use Smart Object with Target Actor  
enter: —  
T#56 OnStateSucceeded/None → VO Line [—]  
T#57 OnStateFailed/None → Can't reach actor, mark so we don't try again. [—]  

`[42]`             **Can't reach actor, mark so we don't try again.**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Individual Knowledge  
enter: —  
T#58 OnStateCompleted/None → DELAY [—]  

`[43]`             **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#59 OnStateCompleted/None → DELAY [—]  

`[44]`             **DELAY**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#60 OnStateCompleted/None → Root [—]  

`[45]`       **Return Loot**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#61 OnStateCompleted/None → Root [—]  
T#62 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[46]`         **Find a place to return the loot**  <State> sel=TrySelectChildrenInOrder  
tasks: Run Env Query  
enter: —  
T#63 OnStateCompleted/None → Move to and Use Smart Object [—]  

`[47]`         **Move to and Use Smart Object**  <State> sel=TrySelectChildrenInOrder  
tasks: STT Use Smart Object with Target Slot Handle  
enter: —  

`[48]`       **React to Spotting Loot**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#64 OnStateCompleted/None → Root [—]  
T#65 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[49]`         **Get Target**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Target From Targeting Group  
enter: —  
T#66 OnStateCompleted/None → Collect Loot [—]  

`[50]`         **Collect Loot**  <State> sel=TrySelectChildrenInOrder  
tasks: STT Use Smart Object with Target Actor  
enter: —  
T#67 OnStateSucceeded/None → Return Loot [—]  
T#68 OnStateFailed/None → Root [—]  

`[51]`       **React to Stims (Guard)**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_InvestigateStims_Guard`  
tasks: —  
enter: —  
T#69 OnStateCompleted/None → Root [—]  
T#70 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[52]`       **React to Downed NPC**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_ReviveNPC`  
tasks: —  
enter: —  
T#71 OnStateCompleted/None → Root [—]  

`[53]`       **Post-Revival Behavior**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#72 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[54]`         **Find Location**  <State> sel=TrySelectChildrenInOrder  
tasks: Run Env Query  
enter: —  
T#73 OnStateCompleted/None → Search Area around incapacitate [—]  

`[55]`         **Search Area around incapacitate**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  
T#74 OnStateCompleted/None → Root [—]  

`[56]`       **Post-Smoke Behavior**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#75 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[57]`         **Find Location**  <State> sel=TrySelectChildrenInOrder  
tasks: Run Env Query  
enter: —  
T#76 OnStateCompleted/None → Search Area [—]  

`[58]`         **Search Area**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  
T#77 OnStateCompleted/None → Root [—]  

`[59]`       **React to projectile visible**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#78 OnEvent/High event=StateTreeEvent.StimChange → React to Stims (Guard) [—]  
T#79 OnEvent/Medium event=StateTreeEvent.TargetChange → Root [TATState Tree Condition Main Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  
T#80 OnEvent/Normal event=StateTreeEvent.TargetChange → React to Downed NPC [Check Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  

`[60]`         **Grab Target From Event**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Target From Targeting Group  
enter: —  
T#81 OnStateSucceeded/None → Set Focus [Object Is Valid]  
T#82 OnStateCompleted/None → Root [—]  

`[61]`         **Set Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Focus (Actor)  
enter: —  
T#83 OnStateCompleted/None → Raise Alertness [—]  

`[62]`         **Raise Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: —  
T#84 OnStateCompleted/None → Initial Investigation VO [—]  

`[63]`         **Initial Investigation VO**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#85 OnStateCompleted/None → Delay until we lose target [—]  

`[64]`         **Delay until we lose target**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  

`[65]`     **React To Conversation Event**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#86 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Almost Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#87 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#88 OnStateCompleted/None → Root [—]  

`[66]`       **Extract**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Conversation Voice Line Data  
enter: —  
T#89 OnStateCompleted/None → Look At Target [—]  

`[67]`       **Look At Target**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Focus (Actor)  
enter: —  
T#90 OnStateCompleted/None → Delay [—]  

`[68]`       **Delay**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#91 OnStateCompleted/None → Play VO [—]  

`[69]`       **Play VO**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#92 OnStateCompleted/None → Send Event Back to original character [—]  

`[70]`       **Send Event Back to original character**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Send Event to NPC  
enter: —  

`[71]`     **React To Shared Target**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#93 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Almost Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#94 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#95 OnStateCompleted/None → Root [—]  

`[72]`       **Extract**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Conversation Share Target Data  
enter: —  
T#96 OnStateCompleted/None → Look At Target [—]  

`[73]`       **Look At Target**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Focus (Actor)  
enter: —  
T#97 OnStateCompleted/None → Delay [—]  

`[74]`       **Delay**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#98 OnStateCompleted/None → Clear Focus [—]  

`[75]`       **Play VO**  <State> sel=TrySelectChildrenInOrder  **DISABLED**  
tasks: Request Voice Line  
enter: —  
T#99 OnStateCompleted/None → Clear Focus [—]  

`[76]`       **Clear Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Clear Focus  
enter: —  
T#100 OnStateCompleted/None → Send Event Back to original character [—]  

`[77]`       **Send Event Back to original character**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Send Event to NPC  
enter: —  
T#101 OnStateCompleted/None → Handle Target Actor [—]  

`[78]`       **Handle Target Actor**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Object Is Valid  

`[79]`         **Set Attitude To Hostile**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Individual Attitude To Target  
enter: —  
T#102 OnStateCompleted/None → Move To Last Known Position [—]  

`[80]`         **Move To Last Known Position**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  
T#103 OnStateCompleted/None → Root [—]  

`[81]`       **Handle Target Location**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: Object Is Valid Copy  

`[82]`         **Move To Last Known Position**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  
T#104 OnStateCompleted/None → Root [—]  

`[83]`     **React to Intruder (Almost Spotted)**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#105 OnStateCompleted/None → Root [—]  
T#106 OnEvent/Normal event=StateTreeEvent.ConversationEvent → React To Conversation Event [—]  
T#107 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Almost Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  

`[84]`       **Grab Target From Event**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Target From Targeting Group  
enter: —  
T#108 OnStateCompleted/None → Try Find Intruder [—]  

`[85]`       **Try Find Intruder**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Update Knowledge Of Actor  
enter: —  
T#109 OnTick/Normal → React to spotting Intruder [TATState Tree Condition Target Detection]  
T#110 OnEvent/Medium event=StateTreeEvent.StimChange → React to Stims (Guard) [—]  

`[86]`         **Clear Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Clear Focus  
enter: —  
T#111 OnStateCompleted/None → Move to intruder [—]  

`[87]`         **Move to intruder**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  
T#112 OnStateCompleted/None → Root [—]  

`[88]`       **React to spotting Intruder**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_SpottedIntruderReaction`  
tasks: —  
enter: —  

`[89]`       **Intruder no longer suspicious**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_IntruderNoLongerSuspicious`  
tasks: —  
enter: —  
T#113 OnTick/Normal → React to spotting Intruder [Check Target Has Gameplay Tag, Check Target Has Gameplay Tag]  
T#114 OnStateCompleted/None → Root [—]  

`[90]`     **React to Intruder (Spotted)**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#115 OnStateCompleted/None → Root [—]  

`[91]`       **Intruder Reaction**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_SpottedIntruderReaction`  
tasks: —  
enter: —  
T#116 OnTick/Normal → Intruder no longer suspicious (Spotted) [Check Target Has Gameplay Tag, Check Target Has Gameplay Tag]  

`[92]`       **Intruder no longer suspicious (Spotted)**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_IntruderNoLongerSuspicious`  
tasks: —  
enter: —  
T#117 OnTick/Normal → Intruder Reaction [Check Target Has Gameplay Tag, Check Target Has Gameplay Tag]  
T#118 OnStateCompleted/None → Root [—]  

`[93]`     **React to Damage**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#119 OnStateCompleted/None → Root [—]  

`[94]`       **Set Stim Location From Event**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Extract Stim Data from Event  
enter: —  
T#120 OnStateCompleted/None → Extract Stim Location [—]  

`[95]`       **Extract Stim Location**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Update Knowledge Of Actor  
enter: —  
T#121 OnStateCompleted/None → Raise Alertness [—]  

`[96]`       **Raise Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: —  
T#122 OnStateCompleted/None → Look At Location [—]  

`[97]`       **Look At Location**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Rotate to Face  
enter: —  
T#123 OnStateCompleted/None → Try to Find Culprit [—]  

`[98]`         **Trigger VO**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#124 OnStateCompleted/None → Wait for Turn to Finish [—]  

`[99]`         **Wait for Turn to Finish**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  

`[100]`       **Try to Find Culprit**  <State> sel=TrySelectChildrenInOrder  
tasks: Run Env Query  
enter: —  
T#125 OnStateSucceeded/None → Culprit Found [—]  
T#126 OnStateFailed/None → Culprit Not Found [—]  

`[101]`       **Culprit Found**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[102]`         **Set Attitude**  <State> sel=TrySelectChildrenInOrder  
tasks: Set Individual Attitude To Target  
enter: —  
T#127 OnStateCompleted/None → Wait for Combat Target Changed [—]  

`[103]`         **Wait for Combat Target Changed**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  

`[104]`       **Culprit Not Found**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[105]`         **Search Near Damage Location**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_GeneralInvestigateStim`  
tasks: —  
enter: —  
T#128 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Almost Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#129 OnEvent/Medium event=StateTreeEvent.TargetChange → React to Intruder (Spotted) [TATState Tree Condition Main Target Matches Detection, TATState Tree Condition Main Targeting Group Matches]  
T#130 OnEvent/Critical event=StateTreeEvent.TargetChange → Combat [TATState Tree Condition Main Targeting Group Matches, Check Targeting Data Exists for Targeting Group]  
T#131 OnStateCompleted/None → Root [—]  

`[106]`     **React to Player Tool**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#132 OnStateCompleted/None → Root [—]  

`[107]`       **Grab Target From Event**  <State> sel=TrySelectChildrenInOrder  
tasks: Extract Target From Targeting Group  
enter: —  
T#133 OnStateCompleted/None → Claim [—]  

`[108]`       **Claim**  <State> sel=TrySelectChildrenInOrder  
tasks: STT Use Smart Object with Target Actor  
enter: —  
T#134 OnStateSucceeded/None → Raise Alertness [—]  
T#135 OnStateFailed/None → Root [—]  

`[109]`       **Raise Alertness**  <State> sel=TrySelectChildrenInOrder  
tasks: TATState Tree Task Set Alertness  
enter: —  
T#136 OnStateCompleted/None → VO Line [—]  

`[110]`       **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#137 OnStateCompleted/None → Move to and Use Smart Object [—]  

`[111]`       **Move to and Use Smart Object**  <State> sel=TryEnterState  
tasks: STT Use Smart Object with Claimed Handle  
enter: —  
T#138 OnStateCompleted/None → VO Line [—]  

`[112]`       **VO Line**  <State> sel=TrySelectChildrenInOrder  
tasks: Request Voice Line  
enter: —  
T#139 OnStateCompleted/None → Root [—]  

`[113]`     **Combat**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_Combat`  
tasks: —  
enter: —  

`[114]`   **Forced States**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[115]`     **Cower**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[116]`       **Clear Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Clear Focus  
enter: —  
T#140 OnStateCompleted/None → Trigger Cower Ability [—]  

`[117]`       **Trigger Cower Ability**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#141 OnEvent/Normal event=StateTreeEvent.GameplayTagChange → Root [Check Gameplay Tag Event Matches]  

`[118]`     **Unconcious**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[119]`       **Clear Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Clear Focus  
enter: —  
T#142 OnStateCompleted/None → Delay [—]  

`[120]`       **Delay**  <State> sel=TrySelectChildrenInOrder  
tasks: Delay Task  
enter: —  
T#143 OnEvent/Normal event=StateTreeEvent.GameplayTagChange → Post-Revival Behavior [Check Gameplay Tag Event Matches]  

`[121]`     **In Smoke**  <Group> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  

`[122]`       **Clear Focus**  <State> sel=TrySelectChildrenInOrder  
tasks: Clear Focus  
enter: —  
T#144 OnStateCompleted/None → Trigger In Smoke Ability [—]  

`[123]`       **Trigger In Smoke Ability**  <State> sel=TrySelectChildrenInOrder  
tasks: Trigger Gameplay Ability By Class  
enter: —  
T#145 OnEvent/Normal event=StateTreeEvent.GameplayTagChange → Post-Smoke Behavior [Check Gameplay Tag Event Matches]  

`[124]`     **Forced Agro**  <State> sel=TrySelectChildrenInOrder  
tasks: —  
enter: —  
T#146 OnEvent/Normal event=StateTreeEvent.TargetChange → Root [Check Targeting Group Matches, TATState Tree Condition Main Target Matches Actor]  

`[125]`       **Combat**  <LinkedAsset> sel=TrySelectChildrenInOrder  -> link `ST_Subtree_Combat`  
tasks: —  
enter: —  
T#147 OnStateCompleted/None → Root [—]  


---

## 5. Task / condition inventory (all 21 trees)

### 5.1 Counts

| quantity | value |
|---|---|
| distinct task names | **77** |
| task instances | **326** |
| distinct enter-condition names | **22** |
| enter-condition instances | **81** |
| distinct transition-condition names | **22** |
| transition-condition instances | **152** |
| distinct condition names, enter ∪ transition | **36** |
| condition instances, enter + transition | **233** |
| distinct utility-consideration names | 0 |
| raw shared-instance nodes | 239 = 233 referenced conditions + 6 `Get Actor Location` property functions |
| raw global-instance nodes | 1 (`ST_Guard` `Difficulty Evaluator`) |
| task names that are native (no BP class) | 47 |
| task names with a `STT_*` class | 30 |
| condition names that are native | 30 |
| condition names with a `STC_*` class | 6 |

The 14 names that appear only as enter conditions and the 14 that appear only as
transition conditions:

* enter-only: `Check Gameplay Tag Is Valid`, `Check Stim Data Instigator matches
  private zone tags on actor`, `Check Stim Data instigator matches attitude`,
  `Check Stim Data instigator matches attitude Copy`, `Check Targeting Data
  Matches Visibility Copy`, `Distance Compare`, `Has Individual Knowledge`,
  `Has Tag`, `Integer Compare`, `Object Is Valid Copy`, `Patrol Point Is Of
  Type`, `STC Blackboard Actor Is Set`, `STC Has Equipment`,
  `TATState Tree Condition Stim`.
* transition-only: `Check Distance From Owner Copy`, `Check Gameplay Tag Event
  Matches`, `Check Linked State Is Active`, `Check Stim Event Matches`, `Check
  Target Knowledge with Attitude`, `Check Target Knowledge with Detection`,
  `Check Targeting Data Matches Specific Target`, `Check Targeting Group
  Matches`, `Is Carrying Major Loot`, `Object Equals`, `TATState Tree Condition
  Main Target Matches Actor`, `TATState Tree Condition Main Target Matches
  Detection`, `TATState Tree Condition Main Targeting Group Matches`,
  `TATState Tree Condition Target Detection`.

### 5.2 The 77 distinct task names, instance counts, class and native/BP split

`class` is the raw `TaskClass` (BP) or the matched
`PropertyBindings.SourceStructs[].Struct.ObjectName` (native), stripped of
`Class'`/`BlueprintGeneratedClass'` and the trailing `'`.

| # | task name (payload string) | instances | class (raw) | kind |
|---|---|---|---|---|
| 1 | `Delay Task` | 32 | `StateTreeDelayTaskInstanceData` | native |
| 2 | `Request Voice Line` | 31 | `STT_RequestVOLine_C` | BP |
| 3 | `TATState Tree Task Set Alertness` | 20 | `TATStateTreeTaskSetAlertnessData` | native |
| 4 | `Clear Focus` | 19 | `STT_ClearFocus_C` | BP |
| 5 | `Run Env Query` | 17 | `TATStateTreeRunEnvQueryInstanceData` | native |
| 6 | `Extract Target From Targeting Group` | 14 | `TATStateTreeTaskExtractMainTargetDataFromTargetingGroupData` | native |
| 7 | `Set Focus (Actor)` | 12 | `STT_SetFocus_C` | BP |
| 8 | `Request Conditional Voice Line` | 10 | `STT_RequestVOLine_Conditional_C` | BP |
| 9 | `Move To` | 9 | `StateTreeMoveToTaskInstanceData` | native |
| 10 | `TATState Tree Task Rotate to Face` | 9 | `TATStateTreeTaskRotateToFaceData` | native |
| 11 | `TATState Tree Task Update Knowledge Of Actor` | 9 | `TATStateTreeTaskUpdateKnowledgeOfActorData` | native |
| 12 | `Set Value (bool)` | 8 | `TATStateTreeTaskSetValueBoolData` | native |
| 13 | `Set Individual Attitude To Target` | 7 | `STT_SetAttitudeToTarget_C` | BP |
| 14 | `STT Use Smart Object with Target Actor` | 6 | `STT_UseSmartObjectWithTargetActor_C` | BP |
| 15 | `[TAT] Move To` | 6 | `TATStateTreeMoveToTaskInstanceData` | native |
| 16 | `STT Use Smart Object with Target Slot Handle` | 5 | `STT_UseSmartObjectWithTargetSlotHandle_C` | BP |
| 17 | `TATState Tree Task Set Blackboard Value` | 5 | `TATStateTreeTaskSetBlackboardValueData` | native |
| 18 | `TATState Tree Task Set Individual Knowledge` | 5 | `TATStateTreeTaskSetIndividualKnowledgeData` | native |
| 19 | `Report Noise Event` | 4 | `STT_ReportNoise_C` | BP |
| 20 | `TATState Tree Task Extract Stim Data from Event` | 4 | `TATStateTreeTaskStimDataInstanceData` | native |
| 21 | `TATState Tree Task Wait for Applied Tags` | 4 | `TATStateTreeTaskWaitForAppliedTagsData` | native |
| 22 | `Trigger Gameplay Ability By Class` | 4 | `TATStateTreeTaskTriggerGameplayAbilityByClassData` | native |
| 23 | `Trigger ability via Gameplay Tag and Wait` | 4 | `STT_TriggerGameplayAbilityWithEvent_C` | BP |
| 24 | `Apply Gameplay Effect` | 3 | `TATStateTreeTaskApplyGameplayEffectData` | native |
| 25 | `Get Location From Actor` | 3 | `TATStateTreeTaskActorLocationData` | native |
| 26 | `Repeatedly Trigger VO` | 3 | `STT_RequestVOLine_Repeating_C` | BP |
| 27 | `STT Set Focus` | 3 | `STT_SetFocus_C` | BP |
| 28 | `TATState Tree Send Event to NPC` | 3 | `TATStateTreeSendEventToNPCData` | native |
| 29 | `TATState Tree Task Extract Main Target Data from Event` | 3 | `TATStateTreeTaskExtractMainTargetDataFromEventData` | native |
| 30 | `TATState Tree Task Set Blackboard Actor Value` | 3 | `TATStateTreeTaskSetBlackboardValueActorData` | native |
| 31 | `Add Targeting Groups` | 2 | `TATStateTreeTaskAddTargetingGroupsData` | native |
| 32 | `Debug Text Task` | 2 | `StateTreeDebugTextTaskInstanceData` | native |
| 33 | `Extract Reaction Role` | 2 | `TATStateTreeTaskRoleFromEventData` | native |
| 34 | `Extract Scalable Float` | 2 | `TATStateTreeTaskScalableFloatData` | native |
| 35 | `Register for Reaction Role` | 2 | `TATStateTreeTaskRegisterForRoleInstanceData` | native |
| 36 | `Request Conditional Voice Line Copy` | 2 | `STT_RequestVOLine_Conditional_C` | BP |
| 37 | `Run Env Query` | 2 | `StateTreeRunEnvQueryInstanceData` | native |
| 38 | `STT Equip Unequip` | 2 | `STT_EquipUnequip_C` | BP |
| 39 | `STT Set Share Partner` | 2 | `STT_SetSharePartner_C` | BP |
| 40 | `STT Trigger Search Animation` | 2 | `STT_TriggerAndWaitForAnimation_C` | BP |
| 41 | `Scoped Individual Knowledge` | 2 | `TATStateTreeTaskScopedIndividualKnowledgeData` | native |
| 42 | `TATState Tree Task Loop` | 2 | `TATStateTreeTaskLoopData` | native |
| 43 | `TATState Tree Task Set Combat Target` | 2 | `TATStateTreeTaskSetCombatTargetData` | native |
| 44 | `Complete Broken Segment` | 1 | `TATStateTreeTaskCompleteBrokenPathData` | native |
| 45 | `Complete Patrol Segment` | 1 | `TATStateTreeTaskCompletePatrolData` | native |
| 46 | `Extract Conversation Share Target Data` | 1 | `TATStateTreeExtractEventToNPC_ShareTargetData` | native |
| 47 | `Extract Conversation Voice Line Data` | 1 | `TATStateTreeExtractEventToNPC_VoiceLineData` | native |
| 48 | `Extract Distraction Data` | 1 | `TATStateTreeTaskExtractDistractionEventData` | native |
| 49 | `STT Distraction Smart Objects` | 1 | `STT_DistractionSmartObjects_C` | BP |
| 50 | `STT Get Distance Between Actors` | 1 | `STT_GetDistanceBetweenActors_C` | BP |
| 51 | `STT Remember Target to Share` | 1 | `STT_RememberTargetToShare_C` | BP |
| 52 | `STT Remember Target to Share Location` | 1 | `STT_RememberTargetToShare_Location_C` | BP |
| 53 | `STT Set Clue Giving Enabled` | 1 | `STT_SetClueGivingEnabled_C` | BP |
| 54 | `STT Set Contextual Location in Use` | 1 | `STT_SetContextualLocationInUse_C` | BP |
| 55 | `STT Share Target` | 1 | `STT_ShareTarget_C` | BP |
| 56 | `STT Try Claim Contextual Location` | 1 | `STT_TryClaimContextualLocation_C` | BP |
| 57 | `STT Try Forget Share Partner` | 1 | `STT_TryForgetSharePartner_C` | BP |
| 58 | `STT Use Smart Object with Claimed Handle` | 1 | `STT_UseSmartObjectWithClaimedHandle_C` | BP |
| 59 | `Scoped Stim Investigation` | 1 | `TATStateTreeTaskScopedStimInvestigationData` | native |
| 60 | `Send Gameplay Event` | 1 | `STT_SendGameplayEvent_C` | BP |
| 61 | `Set Focus (Location)` | 1 | `STT_SetFocusLocation_C` | BP |
| 62 | `TATState Tree Lockdown` | 1 | `TATStateTreeLockdownData` | native |
| 63 | `TATState Tree Lockdown Extract Search Target` | 1 | `TATStateTreeLockdownExtractSearchTargetData` | native |
| 64 | `TATState Tree Lockdown Finish Searching` | 1 | `TATStateTreeLockdownFinishSearchingData` | native |
| 65 | `TATState Tree Lockdown Get Alarm Station` | 1 | `TATStateTreeLockdownGetAlarmStationData` | native |
| 66 | `TATState Tree Send Event to NPC Share Target` | 1 | `TATStateTreeSendEventToNPC_ShareTargetData` | native |
| 67 | `TATState Tree Task Combat Positioning` | 1 | `TATStateTreeTaskCombatPositioningData` | native |
| 68 | `TATState Tree Task Persist Patrol Data` | 1 | `TATStateTreeTaskPersistPatrolDataType` | native |
| 69 | `TATState Tree Task Retrieve Share Target` | 1 | `TATStateTreeTaskRetrieveShareTargetData` | native |
| 70 | `TATState Tree Task Setup Patrol` | 1 | `TATStateTreeTaskSetupPatrolData` | native |
| 71 | `TATState Tree Task Wait for AIResource Unlocked` | 1 | `TATStateTreeTaskWaitForAIResourceUnlockedData` | native |
| 72 | `Track Targeting Groups` | 1 | `TATStateTreeTaskAddTargetingGroupsData` | native |
| 73 | `Trigger Gameplay Ability By Gameplay Event` | 1 | `TATStateTreeTaskTriggerGameplayAbilityByEventData` | native |
| 74 | `Trigger Gameplay Ability By Input` | 1 | `TATStateTreeTaskTriggerGameplayAbilityData` | native |
| 75 | `Trigger and Wait For Animation` | 1 | `STT_TriggerAndWaitForAnimation_C` | BP |
| 76 | `Update Stim Info` | 1 | `TATStateTreeTaskUpdateStimInfoData` | native |
| 77 | `Use Interactable Actor` | 1 | `STT_InteractWithInteractable_C` | BP |
| 78 | `Use Smart Object` | 1 | `STT_UseSmartObjectWithTargetComponent_C` | BP |
| | **77 distinct names** | **326** | 47 native + 30 BP names | |

The table has 78 rows for 77 names because `Run Env Query` is the one name with two
classes: 17 instances of `TATStateTreeRunEnvQueryInstanceData` (row 5) and 2 of
`StateTreeRunEnvQueryInstanceData` (row 37).

### 5.3 The 36 distinct condition names (enter and transition counts)

| # | condition name (payload string) | enter | transition | total | class (raw) | kind |
|---|---|---|---|---|---|---|
| 1 | `TATState Tree Condition Main Targeting Group Matches` | 0 | 31 | 31 | `TATStateTreeConditionMainTargetingGroupMatchesData` | native |
| 2 | `Check Target Has Gameplay Tag` | 14 | 13 | 27 | `TATStateTreeConditionActor_HasGameplayTagData` | native |
| 3 | `TATState Tree Condition Main Target Matches Detection` | 0 | 21 | 21 | `TATStateTreeConditionMainTargetMatchesDetectionData` | native |
| 4 | `Object Is Valid` | 14 | 4 | 18 | `StateTreeObjectIsValidConditionInstanceData` | native |
| 5 | `Check Targeting Data Exists for Targeting Group` | 2 | 15 | 17 | `TATStateTreeConditionHasTargetInGroupData` | native |
| 6 | `Check Targeting Group Matches` | 0 | 16 | 16 | `TATStateTreeConditionMainTargetingGroupMatchesData` | native |
| 7 | `Bool Compare` | 11 | 4 | 15 | `StateTreeCompareBoolConditionInstanceData` | native |
| 8 | `Check Distance From Owner` | 5 | 5 | 10 | `TATStateTreeConditionActorDistanceFromOwnerData` | native |
| 9 | `Check Gameplay Tag Event Matches` | 0 | 10 | 10 | `TATStateTreeConditionGameplayTagEventData` | native |
| 10 | `TATState Tree Condition Stim` | 7 | 0 | 7 | `TATStateTreeConditionStimInstanceData` | native |
| 11 | `Check Stim Event Matches` | 0 | 6 | 6 | `TATStateTreeConditionStimInstanceData` | native |
| 12 | `Has Tag` | 6 | 0 | 6 | `GameplayTagMatchConditionInstanceData` | native |
| 13 | `Check Targeting Data Matches Visibility` | 1 | 4 | 5 | `TATStateTreeConditionMainTargetMatchesVisibilityData` | native |
| 14 | `TATState Tree Condition Main Target Matches Actor` | 0 | 5 | 5 | `TATStateTreeConditionMainTargetMatchesActorData` | native |
| 15 | `Check Stim Data instigator matches attitude` | 4 | 0 | 4 | `TATStateTreeConditionStimInstigatorMatchesAttitudeData` | native |
| 16 | `Check Target Knowledge with Detection` | 0 | 4 | 4 | `TATStateTreeConditionTargetDetectionData` | native |
| 17 | `STC Has Knowlewdge to Share` | 2 | 1 | 3 | `STC_HasKnowlewdgeToShare_C` | BP |
| 18 | `TATState Tree Condition Target Detection` | 0 | 3 | 3 | `TATStateTreeConditionTargetDetectionData` | native |
| 19 | `Check Gameplay Tag Is Valid` | 2 | 0 | 2 | `TATStateTreeConditionGameplayTagIsValidData` | native |
| 20 | `Check Target Knowledge with Attitude` | 0 | 2 | 2 | `TATStateTreeConditionTargetWithAttitudeData` | native |
| 21 | `Is Carrying Major Loot` | 0 | 2 | 2 | `STC_IsCarryingMajorLoot_C` | BP |
| 22 | `Object Equals` | 0 | 2 | 2 | `StateTreeObjectEqualsConditionInstanceData` | native |
| 23 | `Patrol Point Is Of Type` | 2 | 0 | 2 | `STC_PatrolPathPointIsOfType_C` | BP |
| 24 | `STC Has Clue` | 1 | 1 | 2 | `STC_HasClue_C` | BP |
| 25 | `STC Has Equipment` | 2 | 0 | 2 | `STC_HasEquipment_C` | BP |
| 26 | `Check Distance From Owner Copy` | 0 | 1 | 1 | `TATStateTreeConditionActorDistanceFromOwnerData` | native |
| 27 | `Check Linked State Is Active` | 0 | 1 | 1 | `TATStateTreeConditionStateIsActiveInstanceData` | native |
| 28 | `Check Stim Data Instigator matches private zone tags on actor` | 1 | 0 | 1 | `TATStateTreeConditionStimFromSharedPrivateZoneActorData` | native |
| 29 | `Check Stim Data instigator matches attitude Copy` | 1 | 0 | 1 | `TATStateTreeConditionStimInstigatorMatchesAttitudeData` | native |
| 30 | `Check Targeting Data Matches Specific Target` | 0 | 1 | 1 | `TATStateTreeConditionMainTargetMatchesActorData` | native |
| 31 | `Check Targeting Data Matches Visibility Copy` | 1 | 0 | 1 | `TATStateTreeConditionMainTargetMatchesVisibilityData` | native |
| 32 | `Distance Compare` | 1 | 0 | 1 | `StateTreeCompareDistanceConditionInstanceData` | native |
| 33 | `Has Individual Knowledge` | 1 | 0 | 1 | `TATStateTreeConditionIndividualKnowledgeData` | native |
| 34 | `Integer Compare` | 1 | 0 | 1 | `StateTreeCompareIntConditionInstanceData` | native |
| 35 | `Object Is Valid Copy` | 1 | 0 | 1 | `StateTreeObjectIsValidConditionInstanceData` | native |
| 36 | `STC Blackboard Actor Is Set` | 1 | 0 | 1 | `STC_BlackboardActorIsSet_C` | BP |
| | **36 names** | **81** | **152** | **233** | 30 native + 6 BP names | |

### 5.4 Native vs blueprint split

| | names | instances |
|---|---|---|
| native tasks | 47 | 199 |
| BP tasks (`STT_*`) | 30 | 127 |
| native conditions | 30 | 221 |
| BP conditions (`STC_*`) | 6 | 12 |

The 30 BP task **names** map to 27 distinct `STT_*` classes (three classes carry
two display names: `STT_SetFocus_C` = `Set Focus (Actor)` + `STT Set Focus`;
`STT_RequestVOLine_Conditional_C` = `Request Conditional Voice Line` +
`Request Conditional Voice Line Copy`; `STT_TriggerAndWaitForAnimation_C` =
`STT Trigger Search Animation` + `Trigger and Wait For Animation`). 33 distinct
BP classes appear in the trees; the 34th declared class,
`STT_UseSmartObjectBase_C`, appears in no tree.

### 5.5 The 6 condition classes and 28 task blueprints (payload lists, exact)

**6 condition classes** (`condition_classes`)

| class | UE package | dump (`package`) | instances in 21 trees |
|---|---|---|---|
| `STC_BlackboardActorIsSet_C` | `/Game/AI/StateTrees/Conditionals/STC_BlackboardActorIsSet` | `extracted/json/AI/StateTrees/Conditionals/STC_BlackboardActorIsSet.json` | 1 |
| `STC_HasClue_C` | `/Game/AI/StateTrees/Conditionals/STC_HasClue` | `extracted/json/AI/StateTrees/Conditionals/STC_HasClue.json` | 2 |
| `STC_HasEquipment_C` | `/Game/AI/StateTrees/Tasks/Equipment/STC_HasEquipment` | `extracted/json/AI/StateTrees/Tasks/Equipment/STC_HasEquipment.json` | 2 |
| `STC_HasKnowlewdgeToShare_C` | `/Game/AI/StateTrees/Conditionals/STC_HasKnowlewdgeToShare` | `extracted/json/AI/StateTrees/Conditionals/STC_HasKnowlewdgeToShare.json` | 3 |
| `STC_IsCarryingMajorLoot_C` | `/Game/AI/StateTrees/Conditionals/STC_IsCarryingMajorLoot` | `extracted/json/AI/StateTrees/Conditionals/STC_IsCarryingMajorLoot.json` | 2 |
| `STC_PatrolPathPointIsOfType_C` | `/Game/AI/StateTrees/Conditionals/STC_PatrolPathPointIsOfType` | `extracted/json/AI/StateTrees/Conditionals/STC_PatrolPathPointIsOfType.json` | 2 |

**28 task blueprints** (`task_blueprints`)

| class | UE package | dump (`package`) | instances in 21 trees |
|---|---|---|---|
| `STT_ClearFocus_C` | `/Game/AI/StateTrees/Tasks/STT_ClearFocus` | `extracted/json/AI/StateTrees/Tasks/STT_ClearFocus.json` | 19 |
| `STT_DistractionSmartObjects_C` | `/Game/AI/StateTrees/Tasks/Patrol/Distraction/STT_DistractionSmartObjects` | `extracted/json/AI/StateTrees/Tasks/Patrol/Distraction/STT_DistractionSmartObjects.json` | 1 |
| `STT_EquipUnequip_C` | `/Game/AI/StateTrees/Tasks/Equipment/STT_EquipUnequip` | `extracted/json/AI/StateTrees/Tasks/Equipment/STT_EquipUnequip.json` | 2 |
| `STT_GetDistanceBetweenActors_C` | `/Game/AI/StateTrees/Tasks/STT_GetDistanceBetweenActors` | `extracted/json/AI/StateTrees/Tasks/STT_GetDistanceBetweenActors.json` | 1 |
| `STT_InteractWithInteractable_C` | `/Game/AI/StateTrees/Tasks/Interactables/STT_InteractWithInteractable` | `extracted/json/AI/StateTrees/Tasks/Interactables/STT_InteractWithInteractable.json` | 1 |
| `STT_RememberTargetToShare_C` | `/Game/AI/StateTrees/Tasks/Knowledge/STT_RememberTargetToShare` | `extracted/json/AI/StateTrees/Tasks/Knowledge/STT_RememberTargetToShare.json` | 1 |
| `STT_RememberTargetToShare_Location_C` | `/Game/AI/StateTrees/Tasks/Knowledge/STT_RememberTargetToShare_Location` | `extracted/json/AI/StateTrees/Tasks/Knowledge/STT_RememberTargetToShare_Location.json` | 1 |
| `STT_ReportNoise_C` | `/Game/AI/StateTrees/Tasks/STT_ReportNoise` | `extracted/json/AI/StateTrees/Tasks/STT_ReportNoise.json` | 4 |
| `STT_RequestVOLine_C` | `/Game/AI/StateTrees/Tasks/STT_RequestVOLine` | `extracted/json/AI/StateTrees/Tasks/STT_RequestVOLine.json` | 31 |
| `STT_RequestVOLine_Conditional_C` | `/Game/AI/StateTrees/Tasks/STT_RequestVOLine_Conditional` | `extracted/json/AI/StateTrees/Tasks/STT_RequestVOLine_Conditional.json` | 12 |
| `STT_RequestVOLine_Repeating_C` | `/Game/AI/StateTrees/Tasks/STT_RequestVOLine_Repeating` | `extracted/json/AI/StateTrees/Tasks/STT_RequestVOLine_Repeating.json` | 3 |
| `STT_SendGameplayEvent_C` | `/Game/AI/StateTrees/Tasks/STT_SendGameplayEvent` | `extracted/json/AI/StateTrees/Tasks/STT_SendGameplayEvent.json` | 1 |
| `STT_SetAttitudeToTarget_C` | `/Game/AI/StateTrees/Tasks/Knowledge/STT_SetAttitudeToTarget` | `extracted/json/AI/StateTrees/Tasks/Knowledge/STT_SetAttitudeToTarget.json` | 7 |
| `STT_SetClueGivingEnabled_C` | `/Game/AI/StateTrees/Tasks/STT_SetClueGivingEnabled` | `extracted/json/AI/StateTrees/Tasks/STT_SetClueGivingEnabled.json` | 1 |
| `STT_SetContextualLocationInUse_C` | `/Game/AI/StateTrees/Tasks/ContextualLocations/STT_SetContextualLocationInUse` | `extracted/json/AI/StateTrees/Tasks/ContextualLocations/STT_SetContextualLocationInUse.json` | 1 |
| `STT_SetFocusLocation_C` | `/Game/AI/StateTrees/Tasks/STT_SetFocusLocation` | `extracted/json/AI/StateTrees/Tasks/STT_SetFocusLocation.json` | 1 |
| `STT_SetFocus_C` | `/Game/AI/StateTrees/Tasks/STT_SetFocus` | `extracted/json/AI/StateTrees/Tasks/STT_SetFocus.json` | 15 |
| `STT_SetSharePartner_C` | `/Game/AI/StateTrees/Tasks/Knowledge/STT_SetSharePartner` | `extracted/json/AI/StateTrees/Tasks/Knowledge/STT_SetSharePartner.json` | 2 |
| `STT_ShareTarget_C` | `/Game/AI/StateTrees/Tasks/Knowledge/STT_ShareTarget` | `extracted/json/AI/StateTrees/Tasks/Knowledge/STT_ShareTarget.json` | 1 |
| `STT_TriggerAndWaitForAnimation_C` | `/Game/AI/StateTrees/Tasks/STT_TriggerAndWaitForAnimation` | `extracted/json/AI/StateTrees/Tasks/STT_TriggerAndWaitForAnimation.json` | 3 |
| `STT_TriggerGameplayAbilityWithEvent_C` | `/Game/AI/StateTrees/Tasks/GameplayAbilities/STT_TriggerGameplayAbilityWithEvent` | `extracted/json/AI/StateTrees/Tasks/GameplayAbilities/STT_TriggerGameplayAbilityWithEvent.json` | 4 |
| `STT_TryClaimContextualLocation_C` | `/Game/AI/StateTrees/Tasks/ContextualLocations/STT_TryClaimContextualLocation` | `extracted/json/AI/StateTrees/Tasks/ContextualLocations/STT_TryClaimContextualLocation.json` | 1 |
| `STT_TryForgetSharePartner_C` | `/Game/AI/StateTrees/Tasks/STT_TryForgetSharePartner` | `extracted/json/AI/StateTrees/Tasks/STT_TryForgetSharePartner.json` | 1 |
| `STT_UseSmartObjectBase_C` | `/Game/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectBase` | `extracted/json/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectBase.json` | 0 |
| `STT_UseSmartObjectWithClaimedHandle_C` | `/Game/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithClaimedHandle` | `extracted/json/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithClaimedHandle.json` | 1 |
| `STT_UseSmartObjectWithTargetActor_C` | `/Game/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithTargetActor` | `extracted/json/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithTargetActor.json` | 6 |
| `STT_UseSmartObjectWithTargetComponent_C` | `/Game/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithTargetComponent` | `extracted/json/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithTargetComponent.json` | 1 |
| `STT_UseSmartObjectWithTargetSlotHandle_C` | `/Game/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithTargetSlotHandle` | `extracted/json/AI/StateTrees/Tasks/SmartObjects/STT_UseSmartObjectWithTargetSlotHandle.json` | 5 |

Total 34 declared classes, 33 used in at least one tree; `STT_UseSmartObjectBase_C` is declared but used 0 times.

### 5.6 Display-name / class ambiguity (measured)

Twelve classes are shared by two display names each, so a runtime keyed on the
display name alone aliases different nodes onto the same behaviour and, for
`Run Env Query`, splits one name across two classes:

| class (raw) | display names sharing it |
|---|---|
| `TATStateTreeConditionMainTargetingGroupMatchesData` | `Check Targeting Group Matches` ×16 + `TATState Tree Condition Main Targeting Group Matches` ×31 |
| `StateTreeObjectIsValidConditionInstanceData` | `Object Is Valid` ×18 + `Object Is Valid Copy` ×1 |
| `STT_SetFocus_C` | `STT Set Focus` ×3 + `Set Focus (Actor)` ×12 |
| `TATStateTreeConditionStimInstanceData` | `Check Stim Event Matches` ×6 + `TATState Tree Condition Stim` ×7 |
| `STT_RequestVOLine_Conditional_C` | `Request Conditional Voice Line` ×10 + `Request Conditional Voice Line Copy` ×2 |
| `TATStateTreeConditionActorDistanceFromOwnerData` | `Check Distance From Owner` ×10 + `Check Distance From Owner Copy` ×1 |
| `TATStateTreeConditionTargetDetectionData` | `Check Target Knowledge with Detection` ×4 + `TATState Tree Condition Target Detection` ×3 |
| `TATStateTreeConditionMainTargetMatchesActorData` | `Check Targeting Data Matches Specific Target` ×1 + `TATState Tree Condition Main Target Matches Actor` ×5 |
| `TATStateTreeConditionMainTargetMatchesVisibilityData` | `Check Targeting Data Matches Visibility` ×5 + `Check Targeting Data Matches Visibility Copy` ×1 |
| `TATStateTreeConditionStimInstigatorMatchesAttitudeData` | `Check Stim Data instigator matches attitude` ×4 + `Check Stim Data instigator matches attitude Copy` ×1 |
| `STT_TriggerAndWaitForAnimation_C` | `STT Trigger Search Animation` ×2 + `Trigger and Wait For Animation` ×1 |
| `TATStateTreeTaskAddTargetingGroupsData` | `Add Targeting Groups` ×2 + `Track Targeting Groups` ×1 |

12 classes carry two names each; `Run Env Query` is the only name with two classes (`StateTreeRunEnvQueryInstanceData` ×2, `TATStateTreeRunEnvQueryInstanceData` ×17).

`Run Env Query` = `Class'StateTreeRunEnvQueryInstanceData'` ×2 +
`Class'TATStateTreeRunEnvQueryInstanceData'` ×17. The `.Copy`-suffixed names are
distinct nodes that use the same class as their un-suffixed twin (e.g.
`Object Is Valid` ×18 + `Object Is Valid Copy` ×1).

---

## 6. Port-side facts

### 6.1 Every reader of `guard_behavior.json`

Command: `rg -n 'guard_behavior' game/ tools/`

`game/` — **8 hits, all in untracked files** under `game/src/ai/statetree/`;
0 hits in `game/tests`, 0 hits in any tracked file. Measured at 17:27, after the
concurrent S1 lane had grown the directory from one file to seven:

```
game/src/ai/statetree/tree_model.gd:4,5,26,50,51   payload path + schema + the "cannot answer" note
game/src/ai/statetree/coverage.gd:13               "recomputed from guard_behavior.json"
game/src/ai/statetree/guard_bindings.gd:6          "payload does not carry a node's parameter"
game/src/ai/statetree/interpreter.gd:4             "Semantics come from ... guard_behavior.json"
```

`git status --short` shows `?? game/src/ai/statetree/`; `git ls-files
game/src/ai/statetree/` is empty, so this is **uncommitted work in this
worktree, not in the branch history**. The first measurement (17:15) saw only
`tree_model.gd` (545 lines); by 17:26 the directory held

```
game/src/ai/statetree/bindings.gd         119 lines
game/src/ai/statetree/coverage.gd         144
game/src/ai/statetree/guard_bindings.gd   470
game/src/ai/statetree/interpreter.gd      752
game/src/ai/statetree/shadow_runner.gd    265
game/src/ai/statetree/trace.gd            168
game/src/ai/statetree/tree_model.gd       565   (was 545 at 17:15)
```

and `game/src/ai/guard_ai.gd` had gained 20 lines (2573 → 2593) preloading
`shadow_runner.gd`. These counts move while the S1 lane writes; re-run the grep
before citing them.

`game/tests/` — `rg -c 'guard_behavior' game/tests` → **0 hits**.

`tools/` — 12 hits, four distinct roles:

| file:line | role |
|---|---|
| `tools/parse_state_tree.py:7,54,59,627` | producer (`OUT_PATH`, `SCHEMA`, report text) |
| `tools/check_logic_data.py:10,44,51,543-...` | gate: schema, 21 trees, 3 roots, `ST_Guard` 126/148, `ST_Civilian` 73/82, child ranges, transition ownership (`check_guard()`) |
| `tools/consumer_allowlist.json:116-121` | `{glob:"gameplay/guard_behavior.json", kind:"blocked_on_team", owner:"T11", reason:"21 authored StateTrees (784 KB) have no runtime consumer"}` |
| `tools/audit_baseline.json:453-465` | producer output hash/size (`sha256 3f397005…`, 784227 bytes) |
| `tools/manifest_audit.py:276` | producer→output map (`gen:gameplay/guard_behavior.json`) |

`tools/check_consumers.py` has no direct string for the file: it discovers
reachability by scanning `game/src/**/*.gd` for the relative path or basename,
and fails a rule that then matches nothing (`STALE RULE`, `check_consumers.py`
374-376). The moment any `game/src` file containing the path is tracked, the
`blocked_on_team` rule matches nothing and becomes a stale-rule failure in the
same change.

### 6.2 Modules under `game/src/ai/`

`wc -l game/src/ai/*.gd` + `wc -l game/src/ai/statetree/tree_model.gd`:

| file | lines | one-line purpose (from its own header) |
|---|---|---|
| `game/src/ai/guard_ai.gd` | 2573 (HEAD; 2593 with the concurrent S1 edit) | Constabulary guard AI: Neutral → Suspicious → Alerted → Combat, sight cone + light visibility + smoke LOS + NoiseBus hearing |
| `game/src/ai/civilian_npc.gd` | 585 | Ambient civilian from `BP_MissionSpawner_Civilian_C`: body/head meshes, `MM_Unarmed_*` locomotion, simple wander |
| `game/src/ai/guard_roster.gd` | 268 | Authored guard roster (seven spawn buckets) → sense profile, animation set, body model, lantern, carried key |
| `game/src/ai/hearing_data.gd` | 625 | Authored 54-row hearing/perception layer (`hearing.json`, `perception.json`, `guard_ai.json`) |
| `game/src/ai/hearing_occlusion.gd` | 190 | Binary acoustic occlusion: walls block, open portals pass (285 authored portals) |
| `game/src/ai/nav_steering.gd` | 189 | `NavigationAgent3D` consumer with documented degradation; never bakes a region |
| `game/src/ai/ranged_attack.gd` | 138 | Authored ranged attack `GA_MeleeRangedAttack` (damage curve, shock, delays) |
| `game/src/ai/reaction_roles.gd` | 181 | Authored reaction-role caps from `DT_ReactionEvents` (8 rows) |
| `game/src/ai/sight_model.gd` | 244 | Authored TAT sight geometry: the five fields the producer dropped + vertical frustum |
| `game/src/ai/statetree/` | 545 → 565 | **(untracked, concurrent S1 lane)** started as `tree_model.gd` (payload loader/model, link + transition validation); at 17:26 the directory held 7 files / 2,483 lines (`tree_model, bindings, coverage, guard_bindings, interpreter, shadow_runner, trace`) |

No other file or subdirectory exists under `game/src/ai/`.

### 6.3 Does any runtime code read `extracted/json/**`?

**Yes — exactly one tracked runtime module**: `game/src/core/vfx/niagara_params.gd`.

```
game/src/core/vfx/niagara_params.gd:46-50
    const ROOT_CANDIDATES: Array[String] = [
        "res://assets/ue/Raw/../json",
        "res://../extracted/json",
    ]
game/src/core/vfx/niagara_params.gd:104-121  extraction_json_root(): DirAccess.open() each candidate,
                                             then TAT2_EXTRACTED_JSON env escape hatch
game/src/core/vfx/niagara_params.gd:146     FileAccess.file_exists(root.path_join(rel))
game/src/core/vfx/niagara_params.gd:286     FileAccess.get_file_as_string(abs_path)
```

Every other `extracted` hit under `game/src` is a comment/citation, not a file
open. The full `rg -n 'extracted' game/src` output is 110 lines and all of them
are `##`/`#` comments except `niagara_params.gd` and the unrelated identifiers
`extracted_players`, `register_extracted_player`, `escape_gate.extracted` /
`_on_extracted` (mission-run bookkeeping, no file I/O).

Tests do read the private dump at runtime, via `_repo_json()`:
`game/tests/run_tests.gd:7915-7917` (helper; comment at 7914 says "Test-only:
runtime game code never reads extracted/"), callers at 1569
(`extracted/json/AI/Alertness/DA_AlertnessSettings.json`), 4192
(`extracted/json/Character/Guards/BP_Guard_Base.json`), 8323
(`extracted/json/AI/Controllers/AIC_GuardBase.json`); plus
`game/tests/test_w7s_loot_inventory.gd:19-21`,
`game/tests/test_w6u1_briefing.gd:93`,
`game/tests/e2e/e2e_tier2_boundaries.gd:674`,
`game/tests/e2e/e2e_helpers.gd:35`,
`game/tests/probe_lock_inventory.gd:89`. The top-level E2E boot check treats
`extracted/json` as a required data root (`e2e_helpers.gd:35`), while the
production game code path has the `niagara_params.gd` fallback above.

### 6.4 `game/src/ai/guard_ai.gd` public surface a shadow runner can read

Line numbers are from `git show HEAD:game/src/ai/guard_ai.gd` (2573 lines,
commit `f1bf058`). The working tree carries a concurrent W9-P4 S1 edit to the
same file (+20 lines: +3 after line 27, +2 after 301, +4 after 430, +2 after
1450; `wc -l` is 2593 at the time of writing), so a line number read from the
current file is shifted by up to +11 depending on where it sits. The names and
defaults below are unchanged by that edit; re-grep the file for the line.

`extends CharacterBody3D`; `enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED,
COMBAT, SEARCH, KNOCKED_OUT }` (`guard_ai.gd:5`); signals
`alert_state_changed(state_info)` :7, `carried_item_stolen(item)` :8,
`ranged_attack_fired(result)` :11.

Exported (`@export`) — writable but a reader need not touch:

| line | var | default |
|---|---|---|
| 196 | `patrol_points: Array[Vector3]` | `[]` |
| 200 | `patrol_waits: Array[float]` | `[]` |
| 201 | `patrol_yaws: Array[float]` | `[]` |
| 202 | `patrol_facing: Array[bool]` | `[]` |
| 205 | `patrol_loop_mode: String` | `""` (`"EPatrolLoopType::PingPong"` reverses) |
| 212 | `roster_bucket: String` | `""` |
| 216 | `sight_frustum_enabled: bool` | `true` |
| 217 | `patrol_speed: float` | `PATROL_SPEED` = 1.5 |
| 218 | `suspicious_speed: float` | 1.7 |
| 219 | `chase_speed: float` | 2.5 |
| 220 | `sight_range: float` | 20.0 |
| 221 | `lose_sight_range: float` | 30.0 |
| 222 | `hearing_range: float` | 25.0 |
| 223 | `fov_deg: float` | 80.0 |
| 324 | `carries_lantern: bool` | `false` |

Public plain vars (no leading `_`) — readable state:

| line | var | meaning |
|---|---|---|
| 225 | `state: int` | `Alertness` enum value |
| 226 | `health: float` | 30.0 |
| 227 | `detection: float` | 0..100 |
| 228 | `ko_timer: float` | knockout seconds left |
| 229 | `wp_index: int` | current patrol waypoint |
| 233 | `hearing_query_mask: int` | 127 |
| 234-237 | `last_heard_tag`, `last_heard_stim_tag`, `last_heard_distance_m`, `last_heard_radius_m` | last accepted stimulus |
| 241 | `last_investigation_kind: String` | `"short"` / `"long"` |
| 242 | `investigation_search_seconds: float` | 4.0 |
| 246 | `perception_tags: Array[String]` | range modifiers (empty today) |
| 268 | `investigate_pos: Vector3` | last investigation goal |
| 269 | `state_timer: float` | state timer |
| 272 | `attack_cooldown: float` | melee/ranged cooldown |
| 274 | `gravity: float` | 18.0 |
| 275 | `walk_phase: float` | procedural locomotion phase |
| 276 | `search_scan_phase: float` | scan sweep phase |
| 291 | `ranged_accuracy_stacks: int` | authored accuracy stacks |
| 293 | `combat_role: String` | `ReactionRoles.ROLE_CHASER` / `ROLE_RANGED` / `""` |
| 294 | `last_ranged_damage: float` | last shot damage |
| 297 | `bodies_seen: int` | downed guards noticed |
| 303-304 | `heard_blocked_by_wall`, `heard_as_standby` | hearing diagnostics |
| 307 | `anim_player: AnimationPlayer` | clip player (may be null) |
| 318-322 | `visual_root`, `body_mesh`, `alert_indicator`, `level_ctrl` | scene nodes |
| 325 | `carried_item: Dictionary` | carried key/loot record |
| 326-327 | `lantern_root`, `lantern_light` | lantern nodes |

Public functions a reader may call (mutators are flagged in the last column):

| line | signature | returns |
|---|---|---|
| 435 | `escalation_profile() -> String` | roster escalation profile name |
| 450 | `roster() -> Dictionary` | resolved roster row |
| 458 | `roster_source() -> String` | `"bound"` / `"unbound"` / heuristic source |
| 470 | `escalation_row(alertness: int) -> Dictionary` | authored escalation row |
| 478 | `sight_row() -> Dictionary` | authored sight row for current alertness |
| 524 | `effective_vision_range(use_lose_range := false) -> float` | metres |
| 563 | `weather_indoors() -> bool` | weather side |
| 567 | `hearing_weather_multiplier() -> float` | weather gain |
| 574 | `hearing_sense_multiplier() -> float` | perception gain |
| 1313 | `get_detection_rate(dist_m, crouching) -> float` | rate at distance |
| 1330 | `detection_gain_per_second(dist_m, crouching, sprinting, height_diff_m) -> float` | rate |
| 1419 | `get_state_speed() -> float` | current speed |
| 2291 | `get_alert_state() -> Dictionary` | HUD/alert snapshot |
| 2382 | `has_carried_item() -> bool` | — |
| 2439/2443 | `get_interact_prompt() -> String`, `get_interact_point() -> Vector3` | **inside a `"""…"""` template string at 2436-2457 (proxy script), not class methods** |
| 2476/2485 | `get_interact_prompt() -> String`, `interact(_actor: Node) -> void` | the real methods; `get_interact_prompt` reads, `interact` **mutates** (pickpocket/escalation) |

Mutating public functions (each call changes guard state): `take_knockout(dmg)`
:2028, `apply_damage(dmg)` :2048, `knock_out(duration_override := -1.0)` :2052,
`wake_up_from_ko()` :2092, `set_highlighted(on)` :2236,
`set_xray_highlight(on, category)` :2243, `enable_lantern()` :2319,
`set_carried_item(item)` :2376, `steal_carried_item() -> Dictionary` :2386,
`play_slip()` :795, `play_takedown_vic()` :818.

Private but read-only helpers a test may call: `_state_name()` :2273,
`_patrol_service_waypoint(delta)` :1762 (advances the waypoint — mutates),
`_apply_patrol_yaw(delta, index)` :1791 (writes rotation), `_advance_patrol_index()`
:1802 (mutates `wp_index`), `_can_see_player(player)` :1817,
`_los_to_player(player)` :1683.

---

## 7. Test conventions

### 7.1 `game/tests/run_tests.gd` suite registration

The file is one `extends SceneTree` script; `_initialize()` runs the inline
blocks in order and ends with `print("SUMMARY: fails=", fails)` +
`quit(0 if fails == 0 else 1)` (`run_tests.gd:7597-7598`). A suite is a numbered
comment block (`# 97.`) that either:

1. runs inline and calls `fails += _w3_check(cond, pass_text, fail_text)` (e.g.
   suite 93, `run_tests.gd:7346-7349`), or
2. calls a helper `_run_suiteNN(host) -> Array[String]` defined at the bottom
   (`_run_suite87` :7610, `_run_suite88` :7633, `_run_suite89` :7654,
   `_run_suite90` :7730, `_run_suite91` :7675, `_run_suite92` :7696,
   `_run_suite94` :7752, `_run_suite95` :8077, `_run_suite97` :8309), which
   loads a `res://tests/test_*.gd`, calls `run(host)` and returns a problem
   list; or
3. spawns a child engine with `OS.execute(OS.get_executable_path(), ["--headless",
   "--path", …, "--script", "res://tests/test_*.gd"], out, true)` and requires
   **both** exit 0 and a PASS marker (suites 99, 101-105, 106-109;
   suite 99 at `run_tests.gd:7499` with `OS.execute` at `:7515`; the two suite
   loops at `:7529` and `:7557`).

Numbers in use today: 1-55 (with lettered sub-suites such as 55a/55b), 60, 65,
70, 75, 80, 82, 83, 85-99, 101-109. **100 is unused; the next free number is
110.** The `--spider-only` shortcut runs only 87 + 88
(`run_tests.gd:18-38`).

### 7.2 Existing guard instantiation + patrol configuration

* `game/tests/run_tests.gd:5456-5459` (suite 55a, PingPong reversal):

```gdscript
var w2_pp: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
w2_pp.set("patrol_points", [Vector3.ZERO, Vector3(2.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)] as Array[Vector3])
w2_pp.set("patrol_loop_mode", "EPatrolLoopType::PingPong")
w2_pp.set("wp_index", 0)
```

It then calls `_advance_patrol_index()` (no scene tree, no physics) and
`free()`s the node.

* `game/tests/run_tests.gd:8427-8433` (suite 91e, four listeners):

```gdscript
var g: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
g.name = "AICapGuard%d" % i
g.position = arena + Vector3(20.0 + float(i) * 2.0, 0.0, 0.0)
g.set("patrol_points", [g.position])
host.add_child(g)
```

then `g2.set_physics_process(false)` and direct `_on_noise_record(record)` calls.

* `game/tests/e2e/e2e_helpers.gd:374` (`new_script_node`) and
  `game/tests/e2e/e2e_tier3_pairwise.gd:625-632` (`spawn_test_guard`, then
  `g.set("patrol_points", [(p as Node3D).global_position])`).
* `game/tests/test_w7h_surface_hearing.gd:77` loads the script into
  `GuardScript` for a standalone `--script` test.

### 7.3 `game/tests/e2e/run_e2e_tests.gd` tiers

Tier filter is parsed from user args as `--tier=<value>`, default `"all"`
(`run_e2e_tests.gd:37-40`). Declared tiers: `all`, `1`, `2`, `3`, `4`, `s2`
(each `if tier_filter == "all" or tier_filter == "<x>"` block, loading
`e2e_tier1_features.gd` :60, `e2e_tier2_boundaries.gd` :70,
`e2e_tier3_pairwise.gd` :80, `e2e_tier4_scenarios.gd` :90,
`e2e_s2_loot.gd` :103). Each tier class is constructed with the shared helper
`h` and `await t.call("run")`; the runner ends with
`SUMMARY: fails=%d passed=%d total=%d` (`:111-117`). A new tier would be a new
`if` block plus a `h.require(false, "<T>-BOOT", …)` guard.

### 7.4 `tools/check_scripts_compile.gd`

It scans **automatically**: `gd_files("res://")` recurses through every
directory, skipping any directory that contains `.gdignore` and any directory
whose name starts with `.` (`check_scripts_compile.gd:30-40`), and loads every
`.gd` (`:18-25`). A new directory such as `game/src/ai/statetree/` is therefore
picked up with no list edit. Current count of `.gd` files the walk sees:
`find game -name '*.gd' -not -path '*/.godot/*'` = **178** (includes
`game/addons/tat2_review` 7, `game/tests` 71 + 7 E2E, `game/src/ai` 9 + 1
untracked). The checker's own path is skipped only if the script is copied
inside `res://` (`:19-20`).

---

## Appendix A — commands used

```bash
# payload shape / stats / domains
python3 -c 'import json; p=json.load(open("game/data/generated/gameplay/guard_behavior.json")); ...'
rg -c '"(AlertnessLevel|PatrolPathType|RunUntilAnimationFinished|ComparisonValue|InstanceTemplateIndex|PropertyBindings|TaskClass|ConditionClass|ContextDataDescs|RequiredEventToEnter|Weight|bConsumeEventOnSelect)"' \
   game/data/generated/gameplay/guard_behavior.json          # all 0

# inventory / links / listings / inventories
python3 - <<'PY' ... PY     # scripts summarised in §1-§5

# port side
rg -n 'guard_behavior' game/
rg -n 'guard_behavior' tools/
rg -c 'guard_behavior' game/tests
rg -n 'extracted' game/src
rg -n '^@export|^var |^func ' game/src/ai/guard_ai.gd
wc -l game/src/ai/*.gd game/src/ai/statetree/tree_model.gd

# tests
rg -n '^\t# [0-9]+[\.-]' game/tests/run_tests.gd
sed -n '1,90p' game/tests/e2e/run_e2e_tests.gd
sed -n '1,40p' tools/check_scripts_compile.gd
find game -name '*.gd' -not -path '*/.godot/*' | wc -l   # 178

# provenance / gates
sed -n '450,470p' tools/audit_baseline.json
sed -n '108,130p' tools/consumer_allowlist.json
```

No Godot process was started and no producer was run for this report; the
payload on disk is byte-identical to the audit baseline (sha256 above).
