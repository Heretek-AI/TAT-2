extends RefCounted
## Gameplay-agnostic binding surface for the StateTree interpreter (W9-P4 S1).
##
## The interpreter knows states, transitions, tasks and conditions by NAME and
## nothing else. Everything that needs a game (the player, perception, an
## animation, a blackboard) is supplied here by a subclass. This file is the
## default: every condition is UNKNOWN and every task is UNSET, which is the
## correct answer for a tree whose data source does not carry node parameters.
##
## EVIDENCE CLASSES (the coverage table is built from `declaration()`):
##   * IMPLEMENTED     the authored semantics are driven from fields the payload
##                     actually carries (e.g. a transition's trigger/priority);
##   * MAPPED          the port performs the authored effect through a different
##                     authored data source; the interpreter observes it instead
##                     of executing it, and `parameter_blind` says whether the
##                     payload's missing parameter was needed;
##   * UNSUPPORTED     no port counterpart exists.
##
## A binding MUST NOT mutate game state during shadow mode. Cutover bindings may
## act; they are a different subclass and are declared `mutates() == true`.

const STATUS_IMPLEMENTED: String = "implemented"
const STATUS_MAPPED: String = "mapped-to-port"
const STATUS_UNSUPPORTED: String = "unsupported"

## EStateTreeRunStatus mirror. UNSET means "this task cannot be driven".
const RUNNING: int = 0
const RUNNING_LATENT: int = 1
const SUCCEEDED: int = 2
const FAILED: int = 3
const UNSET: int = 4

## Tri-state condition result.
const COND_UNKNOWN: int = -1
const COND_FALSE: int = 0
const COND_TRUE: int = 1

const STATUS_NAMES: Dictionary = {
	RUNNING: "running",
	RUNNING_LATENT: "running_latent",
	SUCCEEDED: "succeeded",
	FAILED: "failed",
	UNSET: "unset",
}

const COND_NAMES: Dictionary = {
	COND_UNKNOWN: "unknown",
	COND_FALSE: "false",
	COND_TRUE: "true",
}


func status_name(value: int) -> String:
	return str(STATUS_NAMES.get(value, "?"))


func cond_name(value: int) -> String:
	return str(COND_NAMES.get(value, "?"))


## True when this binding can change the world. Shadow mode asserts false.
func mutates() -> bool:
	return false


## Declaration used by the coverage table:
## { "status": STATUS_*, "parameter_blind": bool, "note": String }
func declaration(kind: String, name: String) -> Dictionary:
	return {"status": STATUS_UNSUPPORTED, "parameter_blind": false, "note": "no binding declared", "kind": kind, "name": name}


## Evaluate one condition instance.
##   tree_name:   the tree that owns `frame_state` (a LinkedAsset runs another
##                tree, and state indices are only unique inside one tree);
##   frame_state: the state whose enter conditions are being tested, or the
##                state that owns the transition (for `transition != {}`);
##   transition:  the transition dictionary for a transition condition, else {}.
## Return COND_TRUE / COND_FALSE / COND_UNKNOWN.
func condition_state(_name: String, _tree_name: String, _frame_state: int, _transition: Dictionary) -> int:
	return COND_UNKNOWN


## Per-instance coverage predicate for the coverage table. The default says a
## non-unsupported declaration covers every instance; a binding that drives only
## some instances (e.g. `Move To` on the patrol branch) narrows it.
func covers(_kind: String, name: String, _tree_name: String, _state_index: int) -> bool:
	return str(declaration(_kind, name).get("status", STATUS_UNSUPPORTED)) != STATUS_UNSUPPORTED


## Instantiate a per-entry task instance. Return a Dictionary the interpreter
## will carry until the task exits; `_tick`/`_exit` receive the same dictionary.
## Return {} to mean "cannot drive" (the interpreter records an UNSET task and
## the state can never complete).
func task_enter(_name: String, _tree_name: String, _frame_state: int) -> Dictionary:
	return {}


## Advance one task instance. Return RUNNING / RUNNING_LATENT / SUCCEEDED /
## FAILED / UNSET.
func task_tick(_instance: Dictionary, _delta: float) -> int:
	return UNSET


## Release a task instance (called on state exit). Must not fail.
func task_exit(_instance: Dictionary) -> void:
	pass


## Does an event satisfy a transition's `RequiredEvent`? Return COND_TRUE,
## COND_FALSE or COND_UNKNOWN (e.g. the event tag matches but its payload is not
## carried by the payload, so the transition's conditions cannot be evaluated).
func event_matches(_transition: Dictionary, _event: Dictionary) -> int:
	return COND_FALSE


## Called once after the interpreter finishes a tick. Shadow bindings flush
## per-tick observations here.
func after_tick(_interpreter: RefCounted) -> void:
	pass
