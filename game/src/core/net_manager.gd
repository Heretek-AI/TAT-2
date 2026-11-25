extends Node
## 2-player online/LAN co-op transport using Godot ENetMultiplayerPeer.
##
## Authority split (W6b):
## - Player transforms are client-owned: each peer broadcasts its own state at
##   <= 20 Hz and the receiver only updates a cosmetic remote visual.
## - World events are host-authoritative: a peer asks the server, the server
##   validates sender / kind / target / distance / cooldown and then applies the
##   event locally and broadcasts the validated result to every peer. Gameplay
##   code listens to `world_event_applied`; the transport never dispatches to
##   arbitrary methods chosen by the network.
## - Loot, AI and mission progression are NOT replicated here (see docs).
## - RE-N-11: the run outcome (escape/capture/timeout) is host-authoritative.
##   A client asks the host, the host validates sender/outcome/cooldown, banks
##   the run once and broadcasts the banked payout record; clients only receive
##   a signal and apply that record. The transport never dispatches to a method
##   chosen by the network.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed()
signal remote_state_updated(peer_id: int)
## Legacy raw notification, emitted only after host validation (or after the
## authoritative broadcast reaches a client). Local listeners that need the
## resolved node should use world_event_applied instead.
signal world_event_received(kind: String, target_name: String, from_peer: int)
## Validated world event for local gameplay listeners. `target` is resolved in
## this peer's own scene tree; `from_peer` is the originating player.
signal world_event_applied(kind: String, target: Node, from_peer: int)
## RE-N-11: a validated client run-outcome request, emitted on the host only.
signal run_requested(outcome: String, from_peer: int)
## RE-N-11: the host's banked payout record, emitted on every client. Clients
## apply it verbatim; they never recompute the numbers.
signal run_resolved(outcome: String, payout: Dictionary)

const DEFAULT_PORT: int = 7742
## RE-N-11: the Cotter (Chameleon) export has no Dyn/ folder — the authored body
## lives directly under Skin/Base/. The old "..._Dyn_..." candidate never
## existed on disk, so a Chameleon remote visual always fell back to the capsule.
## The canonical per-thief table is GameState.THIEF_BASE_MESHES; this list is the
## historical fallback and is consulted after it (see _find_remote_packed).
const REMOTE_GLB_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb",
	"res://assets/ue/Content/Art/Animation/ThiefCotter/Skin/Base/SK_ThiefCotter__Body.glb",
	"res://assets/models/SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb",
	"res://assets/models/SK_ThiefCotter__Body.glb",
]

## Closed allowlist: the transport never resolves a gameplay method from an
## arbitrary string. Listeners decide what each validated kind means.
const ALLOWED_WORLD_EVENT_KINDS: Array[String] = ["interact", "collect", "open", "close", "trigger"]
const MAX_TARGET_NAME_LEN: int = 64
## Player-state rate limit (20 Hz): send-side gate + per-sender receive gate.
const PLAYER_STATE_MIN_INTERVAL_MSEC: int = 50
const MAX_SYNC_POS_ABS: float = 5000.0
const MAX_THIEF_ID_LEN: int = 32
## Host world-event authority gates.
const WORLD_EVENT_COOLDOWN_MSEC: int = 250
const MAX_WORLD_EVENT_DISTANCE_M: float = 3.0
## RE-N-11 run-outcome authority gates. The outcome vocabulary is closed (the
## winning option is never a network-chosen method name) and both directions are
## bounded so a peer cannot push an oversized record through the RPC.
const RUN_OUTCOMES: Array[String] = ["escape", "capture", "timeout"]
const RUN_OUTCOME_COOLDOWN_MSEC: int = 1000
const MAX_PAYOUT_JSON_LEN: int = 8192

var peer: ENetMultiplayerPeer
var is_coop: bool = false
var remote_visuals: Dictionary = {} # peer_id -> Node3D
## Peer position from its last validated player-state packet, and the source of
## truth for the host's world-event range check. Never used for gameplay.
var _last_known_pos: Dictionary = {} # peer_id -> Vector3
var _last_broadcast_msec: int = -100000
var _last_remote_state_msec: Dictionary = {} # peer_id -> int msec
var _last_world_event_msec: Dictionary = {} # peer_id -> int msec
## RE-N-11: per-sender run-request gate (one request per second per peer).
var _last_run_request_msec: Dictionary = {} # peer_id -> int msec
## Test/embedding seam: 0 uses the live MultiplayerAPI. A positive id lets a
## headless suite exercise host/client routing without opening a socket.
var _peer_id_override: int = 0
## Observable send counters (also used by the gate suite).
var broadcast_send_count: int = 0
var world_event_accept_count: int = 0
var world_event_reject_count: int = 0
## RE-N-11 run-outcome counters, read by the lifecycle suite so the routing can
## be asserted without a live socket.
var run_request_count: int = 0
var run_resolved_send_count: int = 0
var run_resolved_accept_count: int = 0
var run_resolved_reject_count: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int): peer_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): peer_disconnected.emit(id))
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	# N1: a failed join must never leave is_coop true (broadcasts would RPC
	# into the void). The local reset runs alongside the public signal.
	multiplayer.connection_failed.connect(_on_connection_failed_reset)
	multiplayer.peer_connected.connect(_on_peer_connected_spawn)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected_despawn)


func host(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, 2)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		is_coop = true
	return err


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		# N1: no optimistic is_coop — the flag flips only on the real
		# connected_to_server handshake (one-shot; failed joins reset it).
		multiplayer.connected_to_server.connect(_on_connected_handshake, CONNECT_ONE_SHOT)
	return err


## N1: server handshake completed — co-op is real now, not hoped for.
func _on_connected_handshake() -> void:
	is_coop = true
	print("NetCoop: connected_to_server handshake; is_coop=true")


## N1: connection_failed resets the flag so post-failure broadcasts stop.
func _on_connection_failed_reset() -> void:
	if is_coop:
		push_warning("[net_manager] connection_failed; is_coop reset to false (N1: no optimistic coop)")
	is_coop = false


func disconnect_net() -> void:
	for key: Variant in remote_visuals.keys():
		var n: Variant = remote_visuals.get(key)
		if n is Node and is_instance_valid(n as Node):
			(n as Node).queue_free()
	remote_visuals.clear()
	_last_remote_state_msec.clear()
	_last_known_pos.clear()
	_last_world_event_msec.clear()
	_last_run_request_msec.clear()
	_last_broadcast_msec = -100000
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_coop = false


## Local peer id: 1 is the ENet server. 0 means "no readable peer".
func local_peer_id() -> int:
	if _peer_id_override > 0:
		return _peer_id_override
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


## True only in a real co-op session where this peer is the ENet server (id 1).
## Solo/offline is neither host nor client, so gameplay never treats it as one.
func is_host() -> bool:
	return is_coop and local_peer_id() == 1


func is_client() -> bool:
	return is_coop and local_peer_id() > 1


## Headless-test seam: force the local peer id without a live MultiplayerPeer.
## Passing 0 restores live MultiplayerAPI behaviour.
func set_test_peer_id(id: int) -> void:
	_peer_id_override = maxi(id, 0)


## Send this peer's transform/pose. Returns true only when a packet was
## attempted (call rate-limited at 20 Hz, state validated first). The receiver
## side is cosmetic: it updates the RemotePeer_* visual only.
func broadcast_player_state(pos: Vector3, yaw: float, crouching: bool, thief_id: String) -> bool:
	if not is_coop or multiplayer.multiplayer_peer == null:
		return false
	if not _valid_player_state(pos, yaw):
		return false
	var now: int = Time.get_ticks_msec()
	if now - _last_broadcast_msec < PLAYER_STATE_MIN_INTERVAL_MSEC:
		return false
	_last_broadcast_msec = now
	var safe_id: String = _sanitize_thief_id(thief_id)
	# The host's own player is never an RPC sender, so cache its position here
	# for the host-side world-event range check.
	if is_host():
		_last_known_pos[local_peer_id()] = pos
	broadcast_send_count += 1
	sync_player_state.rpc(pos, yaw, crouching, safe_id)
	return true


## Compatibility API. Host applies directly; client asks the server; solo and
## malformed requests are silent no-ops.
func send_world_event(kind: String, target_name: String) -> void:
	request_world_event(kind, target_name)


## Public request entry point AND the client→server RPC. A local client call is
## forwarded to peer 1; a local host call is validated exactly like a remote one.
@rpc("any_peer", "reliable")
func request_world_event(kind: String, target_name: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		if not is_coop or multiplayer.multiplayer_peer == null:
			return
		if is_client():
			request_world_event.rpc_id(1, kind, target_name)
			return
		_host_accept_world_event(kind, target_name, local_peer_id())
		return
	# Only the server accepts peer requests. A stray client-to-client copy of
	# this RPC is ignored (2-player sessions still allow Godot's broadcast form).
	if not is_host():
		return
	_host_accept_world_event(kind, target_name, sender)


## Server→all validated broadcast. Clients resolve the same target locally and
## emit world_event_applied exactly once; the RPC carries strings only.
@rpc("authority", "reliable")
func apply_world_event(kind: String, target_name: String, from_peer: int) -> void:
	# A local direct call has no remote sender; only peer 1's RPC is authority.
	if multiplayer.get_remote_sender_id() <= 0:
		return
	if not ALLOWED_WORLD_EVENT_KINDS.has(kind):
		return
	var target: Node = _resolve_world_event_target(target_name)
	if target == null:
		return
	_emit_world_event_applied(kind, target, from_peer)


## RE-N-11: client→server run-outcome request. Mirrors request_world_event: a
## local client call is forwarded to peer 1; the host validates the remote
## sender, the closed outcome allowlist and a per-sender cooldown, then emits
## run_requested. The transport never resolves a run by itself.
@rpc("any_peer", "reliable")
func request_run_resolved(outcome: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		if not is_coop:
			return
		if is_client():
			run_request_count += 1
			if multiplayer.multiplayer_peer != null:
				request_run_resolved.rpc_id(1, outcome)
			else:
				print("NetCoop: run request outcome=", outcome, " (test seam, no socket)")
			return
		# A local host call is validated exactly like a remote one.
		_host_accept_run_request(outcome, local_peer_id())
		return
	# Only the server accepts peer requests; a stray client-to-client copy is
	# ignored (same rule as the world-event RPC above).
	if not is_host():
		return
	_host_accept_run_request(outcome, sender)


## RE-N-11: host gate for a run-outcome request. Bounded outcome vocabulary, a
## positive sender and a one-second per-peer cooldown. Returns true only when
## run_requested was emitted; nothing is banked here.
func _host_accept_run_request(outcome: String, sender: int) -> bool:
	if sender <= 0 or not RUN_OUTCOMES.has(outcome):
		run_resolved_reject_count += 1
		return false
	var now: int = Time.get_ticks_msec()
	if now - int(_last_run_request_msec.get(sender, -100000)) < RUN_OUTCOME_COOLDOWN_MSEC:
		run_resolved_reject_count += 1
		return false
	_last_run_request_msec[sender] = now
	run_request_count += 1
	run_requested.emit(outcome, sender)
	return true


## RE-N-11: host→all validated run outcome. The RPC carries a bounded JSON
## string, never a network-chosen method; clients parse it and emit
## run_resolved. A client caller gets false (the host is the only authority).
func broadcast_run_resolved(outcome: String, payout: Dictionary) -> bool:
	if not is_host():
		return false
	if not RUN_OUTCOMES.has(outcome):
		return false
	var payout_json: String = JSON.stringify(payout)
	if payout_json.length() > MAX_PAYOUT_JSON_LEN:
		return false
	run_resolved_send_count += 1
	if multiplayer.multiplayer_peer != null:
		apply_run_resolved.rpc(outcome, payout_json)
	return true


## RE-N-11: server→all validated run outcome. A local direct call has no remote
## sender, so only peer 1's RPC is authority. The payload is re-validated here
## (closed allowlist, 8 KiB cap, a JSON object) before any listener sees it.
@rpc("authority", "reliable")
func apply_run_resolved(outcome: String, payout_json: String) -> void:
	if multiplayer.get_remote_sender_id() <= 0:
		return
	if not RUN_OUTCOMES.has(outcome) or payout_json.length() > MAX_PAYOUT_JSON_LEN:
		run_resolved_reject_count += 1
		return
	var parsed: Variant = JSON.parse_string(payout_json)
	if not (parsed is Dictionary):
		run_resolved_reject_count += 1
		return
	run_resolved_accept_count += 1
	run_resolved.emit(outcome, parsed as Dictionary)


## Client-owned movement, server-observed. Validation drops non-finite or
## far-away transforms; the handler never mutates health, loot or mission state.
@rpc("any_peer", "unreliable_ordered")
func sync_player_state(pos: Vector3, yaw: float, crouching: bool, thief_id: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var now: int = Time.get_ticks_msec()
	var last: int = int(_last_remote_state_msec.get(sender, -100000))
	if now - last < PLAYER_STATE_MIN_INTERVAL_MSEC:
		return
	_last_remote_state_msec[sender] = now
	if not _valid_player_state(pos, yaw):
		return
	_last_known_pos[sender] = pos
	var visual: Node3D = _ensure_remote_visual(sender, _sanitize_thief_id(thief_id))
	visual.position = pos
	visual.rotation = Vector3(0.0, yaw, 0.0)
	var target_scale: float = 0.72 if crouching else 1.0
	visual.scale = Vector3(1.0, target_scale, 1.0)
	remote_state_updated.emit(sender)


func get_remote_visual(peer_id: int) -> Node3D:
	var n: Variant = remote_visuals.get(peer_id)
	if n is Node3D:
		return n as Node3D
	return null


func _get_mission_root() -> Node:
	var scene: Node = get_tree().current_scene
	if scene is Node3D:
		return scene
	return self


func _valid_player_state(pos: Vector3, yaw: float) -> bool:
	if not pos.is_finite() or not is_finite(yaw):
		return false
	if absf(pos.x) > MAX_SYNC_POS_ABS or absf(pos.y) > MAX_SYNC_POS_ABS or absf(pos.z) > MAX_SYNC_POS_ABS:
		return false
	return true


func _is_safe_token(token: String, max_len: int, allow_at: bool) -> bool:
	if token.is_empty() or token.length() > max_len:
		return false
	for i: int in range(token.length()):
		var c: int = token.unicode_at(i)
		var ok: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45
		if not ok and allow_at and c == 64: # '@': Godot auto-generated node names
			ok = true
		if not ok:
			return false
	return true


func _sanitize_thief_id(thief_id: String) -> String:
	var t: String = thief_id.left(MAX_THIEF_ID_LEN)
	if not _is_safe_token(t, MAX_THIEF_ID_LEN, false):
		return ""
	return t


func _resolve_world_event_target(target_name: String) -> Node:
	if not _is_safe_token(target_name, MAX_TARGET_NAME_LEN, true):
		return null
	var root: Node = _get_mission_root()
	if root == null:
		return null
	var target: Node = root.find_child(target_name, true, false)
	if target == null or target == root:
		return null
	# The target must belong to this peer's mission subtree and must never be
	# one of the transport's own RemotePeer_* visuals.
	if not root.is_ancestor_of(target):
		return null
	if remote_visuals.values().has(target):
		return null
	return target


## Position the sender is allowed to act from. The host's own player is read
## live; remote peers use their last validated player-state position.
func _sender_position(sender: int) -> Variant:
	if sender == local_peer_id() and is_inside_tree():
		var p: Node = get_tree().get_first_node_in_group("player")
		if p is Node3D and is_instance_valid(p):
			var live: Vector3 = (p as Node3D).global_position
			if live.is_finite():
				return live
	var cached: Variant = _last_known_pos.get(sender)
	if cached is Vector3 and (cached as Vector3).is_finite():
		return cached as Vector3
	return null


## Full host-side gate. Returns the resolved target on acceptance, null when
## any check fails. This is intentionally callable from the gate suite.
func _validate_world_event(kind: String, target_name: String, sender: int) -> Node:
	if sender <= 0:
		return null
	if not ALLOWED_WORLD_EVENT_KINDS.has(kind):
		return null
	if not _is_safe_token(target_name, MAX_TARGET_NAME_LEN, true):
		return null
	var now: int = Time.get_ticks_msec()
	if now - int(_last_world_event_msec.get(sender, -100000)) < WORLD_EVENT_COOLDOWN_MSEC:
		return null
	var sender_pos_v: Variant = _sender_position(sender)
	if not (sender_pos_v is Vector3):
		return null
	var target: Node = _resolve_world_event_target(target_name)
	if not (target is Node3D):
		return null
	var target_pos: Vector3 = (target as Node3D).global_position
	var sender_pos: Vector3 = sender_pos_v as Vector3
	if sender_pos.distance_to(target_pos) > MAX_WORLD_EVENT_DISTANCE_M:
		return null
	return target


func _host_accept_world_event(kind: String, target_name: String, sender: int) -> bool:
	var target: Node = _validate_world_event(kind, target_name, sender)
	if target == null:
		world_event_reject_count += 1
		return false
	_last_world_event_msec[sender] = Time.get_ticks_msec()
	world_event_accept_count += 1
	_emit_world_event_applied(kind, target, sender)
	apply_world_event.rpc(kind, target_name, sender)
	return true


func _emit_world_event_applied(kind: String, target: Node, from_peer: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	world_event_received.emit(kind, String(target.name), from_peer)
	world_event_applied.emit(kind, target, from_peer)


func _on_peer_connected_spawn(id: int) -> void:
	# N2: no spawn-before-handshake. The visual is created lazily on the
	# first authenticated sync_player_state for that peer (see
	# _ensure_remote_visual), so stray connects never accumulate
	# RemotePeer_* nodes and disconnects leave nothing behind.
	if not is_coop:
		return


func _on_peer_disconnected_despawn(id: int) -> void:
	var n: Variant = remote_visuals.get(id)
	if n is Node and is_instance_valid(n as Node):
		(n as Node).queue_free()
	remote_visuals.erase(id)
	_last_remote_state_msec.erase(id)
	_last_known_pos.erase(id)
	_last_world_event_msec.erase(id)


func _ensure_remote_visual(peer_id: int, thief_id: String) -> Node3D:
	var existing: Variant = remote_visuals.get(peer_id)
	if existing is Node3D and is_instance_valid(existing as Node):
		return existing as Node3D
	# N2 companion: a 2-player session holds at most a handful of visuals.
	# More than two live entries means unexpected third peers — loud, not
	# silent, but still served so gameplay never nulls on a stray connect.
	if remote_visuals.size() >= 2:
		push_warning("[net_manager] unexpected remote visual count=", remote_visuals.size() + 1, " for peer ", peer_id, " (2-player session; check for stray connects)")
	var root: Node = _get_mission_root()
	var visual: Node3D = Node3D.new()
	visual.name = "RemotePeer_%d" % peer_id
	visual.set_meta("thief_id", thief_id)
	root.add_child(visual)
	var packed: PackedScene = _find_remote_packed(thief_id)
	if packed != null:
		var inst: Node = packed.instantiate()
		visual.add_child(inst)
	else:
		var mi: MeshInstance3D = MeshInstance3D.new()
		var cap: CapsuleMesh = CapsuleMesh.new()
		cap.radius = 0.32
		cap.height = 1.65
		mi.mesh = cap
		mi.position = Vector3(0.0, 0.85, 0.0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		if thief_id == "chameleon" or thief_id == "moth":
			mat.albedo_color = Color(0.16, 0.32, 0.24)
		else:
			mat.albedo_color = Color(0.18, 0.22, 0.34)
		mi.material_override = mat
		visual.add_child(mi)
	remote_visuals[peer_id] = visual
	return visual


## RE-N-11: resolve the peer's body mesh. GameState.THIEF_BASE_MESHES is the
## canonical per-thief path table (lead-owned), so a remote Chameleon resolves
## the real `Skin/Base/SK_ThiefCotter__Body.glb` instead of the candidate list's
## historical (non-existent) `Dyn/` path. `thief_base_mesh()` itself resolves the
## *local* thief, so it cannot answer for a remote peer id; the table it reads is
## the same source of truth. Falls back to the candidate list, skipping any path
## that does not exist or is not an imported PackedScene.
func _find_remote_packed(thief_id: String = "") -> PackedScene:
	var key: String = thief_id.strip_edges().to_lower()
	if key == "moth":
		# TAT-2's Moth has no authored outfit row; it renders on the Spider rig.
		key = "spider"
	if key != "":
		var entry_v: Variant = GameState.THIEF_BASE_MESHES.get(key, null)
		if entry_v is Dictionary:
			var canonical: String = str((entry_v as Dictionary).get("body", ""))
			if canonical != "":
				var canonical_scene: PackedScene = _load_packed_if_present(canonical)
				if canonical_scene != null:
					return canonical_scene
	for path: String in REMOTE_GLB_CANDIDATES:
		var scene: PackedScene = _load_packed_if_present(path)
		if scene != null:
			return scene
	return null


## One candidate: only an existing, imported scene is returned; a missing or
## unimported path is skipped (never a half-loaded visual).
func _load_packed_if_present(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path)
	if loaded is PackedScene:
		return loaded as PackedScene
	return null
