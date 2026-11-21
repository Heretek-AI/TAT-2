# TAT-2 audit remediation — task P0-T4: netcode transport hardening

Date (UTC): 2026-11-20
Audit item: T4 — Unauthenticated `any_peer` RPCs drive `interact()`/`triggered` by node name.
File changed: `game/src/core/net_manager.gd` (only file touched; no gameplay call sites edited).

## Spans reproduced (before edit)

From `AUDIT.md` §1/T4, verified verbatim in `net_manager.gd` pre-edit
(line numbers drifted ±2 vs the audit anchors; spans identical):

- `@rpc("any_peer", "unreliable_ordered") func sync_player_state(...)` + body
  (audit `:75-77`; found at lines 74-75 + body).
- `@rpc("any_peer", "reliable") func sync_world_event(...)` + body
  (audit `:86-88`; found at lines 85-86 + body).
- `root.find_child(target_name, true, false)` then
  `target.call("interact", self)` / `target.emit_signal("triggered")`
  (audit `:159-173`; found at lines 163-173).
- Confirmed the defects: no kind allowlist, no ownership check on the
  resolved target, `interact` received the NetManager (`self`) instead of
  the interactor, and any unmatched `kind` fell through to
  `elif target.has_signal("triggered"): emit` — arbitrary named nodes
  callable/triggerable by any peer. `sync_player_state` had no rate limit.
- Producer check: `grep` over `game/` for `send_world_event`,
  `sync_world_event`, `world_event_received`, `broadcast_player_state`,
  `sync_player_state` hits only `net_manager.gd` itself — no live gameplay
  producers exist yet, so the allowlist below is strict with nothing to migrate.

## Allowlist rule (world events)

- `ALLOWED_WORLD_EVENT_KINDS = ["interact", "collect", "open", "trigger"]`.
  Enforced at three layers: `send_world_event()` (local send gate),
  `sync_world_event()` RPC (receive gate), `_apply_world_event()`
  (defence in depth — unknown kinds never reach `find_child`).
- Dispatch is per-kind, method-gated, with no catch-all:
  `interact`/`collect` → `target.call("interact", interactor)` only if
  `has_method("interact")`; `open` → `target.call("open")` only if
  `has_method("open")`; `trigger` → `emit_signal("triggered")` only if
  `has_signal("triggered")`. The old fallthrough
  (`elif has_signal("triggered")` for any other kind) is removed.
- Ownership checks on every receive before any call/emit:
  sender id must be `> 0`; `target_name` non-empty, length ≤
  `MAX_TARGET_NAME_LEN (64)`, and must not contain `/`, `.`, or `:`;
  `target` must be non-null, not the mission root itself, and
  `root.is_ancestor_of(target)` (inside the mission scene subtree);
  transport-owned remote visuals (`remote_visuals` values) are never valid
  targets.
- Interactor fix: gameplay `interact()` now receives the sender's remote
  player node (`_ensure_remote_visual(from_peer)`), never the NetManager.

## Throttle numbers (`sync_player_state`)

- `PLAYER_STATE_MIN_INTERVAL_MSEC = 50` → max 20 Hz.
- Send side: `broadcast_player_state()` drops calls inside the window.
- Receive side: per-sender gate in `sync_player_state()` via
  `_last_remote_state_msec[peer_id]`; state cleared on peer despawn and on
  `disconnect_net()`.
- Payload validation on receive: sender `> 0`, `pos.is_finite()` and
  `is_finite(yaw)`, each `pos` axis clamped to `±MAX_SYNC_POS_ABS (5000.0)`,
  `thief_id` truncated to `MAX_THIEF_ID_LEN (32)`.

## Verify

- Re-read `net_manager.gd` post-edit: single `find_child` site, inside
  `_apply_world_event`, reachable only after the allowlist + ownership gates.
- Structural check 17/17 PASS: gates ×3, `sender <= 0` ×2, ancestor +
  remote-visual exclusion, no `call("interact", self)`, no catch-all emit,
  send + per-sender receive throttle, finite/clamp/name checks.
- `task-p0-t4.md` (this file) exists.
- Full suite NOT run (orchestrator runs `make test` at settle per instruction).
