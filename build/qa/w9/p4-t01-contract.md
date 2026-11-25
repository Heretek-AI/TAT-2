# W9-P4 → T01 producer contract: StateTree node parameters

Status: **BLOCKED-ON T01** (the integrator owns `tools/parse_state_tree.py` and
the regeneration; W9-P4 owns only `game/src/ai/**`). Nothing in this document was
applied. The runtime side is written and validated against the *current* payload;
this is the exact change that lifts the ceiling measured in
[`p4-report.md`](p4-report.md) §2.

Evidence for every claim: [`p4-facts-data.md`](p4-facts-data.md) §3 and
[`p4-re-statetree.md`](p4-re-statetree.md) §6 (four-hop chain, three worked
examples, counts).

## 1. Why

`guard_behavior.json` carries task and condition **display names only**. The raw
cooked dump carries the authored parameter struct for

* **260 of 326** task instances,
* **209 of 233** condition instances,

and the payload carries none of them. Measured consequence today
(`p4-report.md` §2):

| class | authored | covered by the port binding | `parameter_blind` |
|---|---:|---:|---:|
| task classes | 77 (326 instances) | 18 classes / 113 instances | 94 |
| condition classes | 36 (233 instances) | 6 classes / 35 instances | 32 |
| trees fully evaluable | 21 | **0** | — |

No node parameter may be invented: `Set Alertness` has 20 instances with 20
different authored `EAlertnessLevel` values, `Delay Task` has 32 instances with
authored durations of 1.0 s and 100.0 s, and `Bool Compare` is 15 instances over
different property pairs. A runtime that guesses is wrong 90 % of the time.

## 2. Resolution path (proven, 566/566 nodes in range)

```
States[i].TasksBegin / EnterConditionsBegin / Transitions[j].ConditionsBegin
  -> Nodes.Structs[k]
  -> Nodes.Structs[k].InstanceTemplateIndex.Value           (the template slot)
  -> array chosen by Nodes.Structs[k].InstanceDataHandle.Source:
       GlobalInstanceData*  -> DefaultInstanceData.Data.InstanceStructs.Structs
       ActiveInstanceData*  -> DefaultInstanceData.Data.InstanceStructs.Structs
       SharedInstanceData*  -> SharedInstanceData.Data.InstanceStructs.Structs
  -> Structs[template_index]  = the authored values
```

Two traps the producer must encode, both **PROVEN**:

1. **`InstanceTemplateIndex` is not `InstanceDataHandle.Index`** — they differ on
   **300 of 566** nodes (`Index` is a pooled runtime slot shared by
   mutually-exclusive tasks). Reading by `Index` gives the wrong struct.
2. For the `…Object` variants (139 nodes = exactly the Blueprint nodes carrying
   `TaskClass`/`ConditionClass`), the template is
   `{"InstanceObject": {"ObjectPath": "/Game/…/ST_Patrol.2"}}`: resolve that export
   in the same file and read its `Properties`. A missing property means "inherit
   the class default"; the class default is only in the leaf dump's CDO when the
   Blueprint overrode it, so `{Name, properties: {}}` plus
   `inherited: true` is the honest encoding.

## 3. Payload change (`tat2.guard_behavior/2`)

Every node entry becomes an object instead of a bare string. The old string form
stays readable by the consumer (`tree_model.gd` accepts both), so the switch is
additive.

```jsonc
"states": [{
  "index": 1, "name": "Set Alertness", "depth": 1, "type": "State",
  "parent": "Root", "parent_index": 0, "children": [], "children_range": [2, 2],
  "tasks": [{
    "name": "TATState Tree Task Set Alertness",
    "class": "TATStateTreeTask_SetAlertness_C",     // UClass / BP class, null when native
    "node_index": 0,                                 // Nodes.Structs index
    "template_index": 2,                             // InstanceTemplateIndex
    "data_source": "ActiveInstanceData",             // InstanceDataHandle.Source
    "inherited": false,                              // true when the template is a class default
    "parameters": {                                  // authored values, JSON-safe
      "AlertnessLevel": "Neutral",
      "RunUntilAnimationFinished": true
    }
  }],
  "enter_conditions": [/* same shape, data_source SharedInstanceData */],
  "required_event_to_enter": null,                   // 3 states carry it (see §4)
  "has_transition_tasks": false,
  "utility_considerations": []
}],
"transitions": [{
  "index": 3, "to_state": "Has Broken Location?", "to_state_index": 5,
  "to_kind": "state", "trigger": "OnStateSucceeded",
  "priority": "None", "required_event": "",
  "fallback": "NextSelectableSibling",               // NEW: 39 authored
  "consume_event_on_select": true,                   // NEW: false on 2 states
  "delay": {"duration": 0.0, "random_variance": 0.0},// NEW: 0/467 non-zero today
  "conditions": [/* node objects as above */],
  "enabled": true
}]
```

Naming rules:

* `class` is the `ObjectName`/`TaskClass`/`ConditionClass` leaf (strip the
  `BlueprintGeneratedClass'…'` wrapper); `null` for native nodes, whose class is
  not serialised. **Display names are not unique keys**: 12 classes share two
  display names and `Run Env Query` is two classes, so `class` is the only safe
  identity — keep `name` for trace readability but key the runtime by `class`
  when it is present.
* `parameters` is the template struct verbatim, minus engine object references
  (`AIController`, `InstanceObject`) which are binding slots, not values. Emit
  their binding target as `"bound": ["AIController"]` so the consumer knows the
  slot exists. Values that are UObject refs become
  `{"asset": "<ObjectPath>"}`.
* Enum values keep the dump's `"EAlertnessLevel::Neutral"` form; the producer
  must **not** reinterpret them into ints (the numeric order of
  `EAlertnessLevel` is not in the dump).

## 4. The three `RequiredEventToEnter` states

`ST_Patrol[21] "Extract distraction Event"`, `ST_Subtree_Combat[6] "Extract
Reaction Role from Event"`, `ST_InvestigateStims_Guard[6] "Extract Reaction Role
from Event"` carry `EventDataIndex != 65535`. Their event **type** is recoverable
from the source struct; the payload currently cannot gate them, so the
interpreter may enter them without an event. Emit
`required_event_to_enter: {"tag": "<StateTreeEvent.*>", "payload_struct": "<Struct>"}`
or `null`.

## 5. Acceptance test (integrator, at merged HEAD)

`python3 tools/parse_state_tree.py && make normalize`, then:
`tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd`
must print, with no code change on the runtime side:

```
P4PARAMS task_instances_with_params=260 condition_instances_with_params=209
P4COVERAGE ... task_blind_templated=94->0 ...
```

The runtime already accepts the object form; the only change needed once the
payload lands is to read `parameters` in `guard_bindings.gd` in place of the two
state-name fallbacks (`Set Alertness`, `Patrol Point Is Of Type`) — the coverage
table's `blind` column is the checklist.

A minimal producer self-check that fails closed (add to
`tools/check_logic_data.py`):

1. every node object has `name`, `node_index`, `template_index`, `data_source`;
2. `template_index` resolves inside the named instance array for 566/566 nodes;
3. the three worked examples equal
   `Neutral` / `1.0` and `100.0` / `SmartObjectInteraction` /
   `{inherited: true}` respectively;
4. `fallback` is present on every transition and is one of
   `None|NextSelectableSibling`;
5. `required_event_to_enter` is non-null on exactly those 3 states.

## 6. What this unblocks (and what it does not)

* **S2 patrol cutover**: the patrol branch (`ST_Patrol` 4/10/14/15/16/17/18) needs
  `Delay Task.duration`, `Set Alertness.AlertnessLevel`,
  `Move To`'s target binding and `Bool Compare`'s operands. With §3 all four are
  authored values instead of state-name inferences.
* **Not unblocked by parameters alone**: the smart-object, EQS, knowledge,
  attitude, targeting-group, gameplay-ability, lockdown and revive subsystems
  (§7 of `p4-re-statetree.md`). Those are behaviour work, not a producer fix, and
  they are why 59 of 77 task classes stay unsupported even after this contract.
