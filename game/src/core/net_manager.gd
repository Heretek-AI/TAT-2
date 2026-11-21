extends Node
## 2-player online/LAN co-op transport using Godot ENetMultiplayerPeer.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed()
signal remote_state_updated(peer_id: int)
signal world_event_received(kind: String, target_name: String, from_peer: int)

const DEFAULT_PORT: int = 7742
const REMOTE_GLB_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb",
	"res://assets/ue/Content/Art/Animation/ThiefCotter/Skin/Base/Dyn/SK_ThiefCotter_Dyn__Body_NoPostProcABP.glb",
	"res://assets/models/SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb",
	"res://assets/models/SK_ThiefCotter_Dyn__Body_NoPostProcABP.glb",
]

## T4 hardening: world events are a closed allowlist; anything else is dropped.
## "trigger" is the only kind allowed to emit the "triggered" signal.
const ALLOWED_WORLD_EVENT_KINDS: Array[String] = ["interact", "collect", "open", "trigger"]
const MAX_TARGET_NAME_LEN: int = 64
## Player-state rate limit (20 Hz): send-side gate + per-sender receive gate.
const PLAYER_STATE_MIN_INTERVAL_MSEC: int = 50
const MAX_SYNC_POS_ABS: float = 5000.0
const MAX_THIEF_ID_LEN: int = 32

var peer: ENetMultiplayerPeer
var is_coop: bool = false
var remote_visuals: Dictionary = {} # peer_id -> Node3D
var _last_broadcast_msec: int = -100000
var _last_remote_state_msec: Dictionary = {} # peer_id -> int msec


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
	_last_broadcast_msec = -100000
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_coop = false


func broadcast_player_state(pos: Vector3, yaw: float, crouching: bool, thief_id: String) -> void:
	if not is_coop or multiplayer.multiplayer_peer == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_broadcast_msec < PLAYER_STATE_MIN_INTERVAL_MSEC:
		return
	_last_broadcast_msec = now
	sync_player_state.rpc(pos, yaw, crouching, thief_id)


func send_world_event(kind: String, target_name: String) -> void:
	if not is_coop or multiplayer.multiplayer_peer == null:
		return
	if not ALLOWED_WORLD_EVENT_KINDS.has(kind):
		return
	if target_name == "" or target_name.length() > MAX_TARGET_NAME_LEN:
		return
	sync_world_event.rpc(kind, target_name)


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
	if not pos.is_finite() or not is_finite(yaw):
		return
	if absf(pos.x) > MAX_SYNC_POS_ABS or absf(pos.y) > MAX_SYNC_POS_ABS or absf(pos.z) > MAX_SYNC_POS_ABS:
		return
	var visual: Node3D = _ensure_remote_visual(sender, thief_id.left(MAX_THIEF_ID_LEN))
	visual.position = pos
	visual.rotation = Vector3(0.0, yaw, 0.0)
	var target_scale: float = 0.72 if crouching else 1.0
	visual.scale = Vector3(1.0, target_scale, 1.0)
	remote_state_updated.emit(sender)


@rpc("any_peer", "reliable")
func sync_world_event(kind: String, target_name: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if not ALLOWED_WORLD_EVENT_KINDS.has(kind):
		return
	if target_name == "" or target_name.length() > MAX_TARGET_NAME_LEN:
		return
	if target_name.contains("/") or target_name.contains(".") or target_name.contains(":"):
		return
	world_event_received.emit(kind, target_name, sender)
	_apply_world_event(kind, target_name, sender)


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


func _on_peer_connected_spawn(id: int) -> void:
	# N2: no spawn-before-handshake. The visual is created lazily on the
	# first authenticated sync_player_state / sync_world_event for that
	# peer (see _ensure_remote_visual), so stray connects never accumulate
	# RemotePeer_* nodes and disconnects leave nothing behind.
	if not is_coop:
		return


func _on_peer_disconnected_despawn(id: int) -> void:
	var n: Variant = remote_visuals.get(id)
	if n is Node and is_instance_valid(n as Node):
		(n as Node).queue_free()
	remote_visuals.erase(id)
	_last_remote_state_msec.erase(id)


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
	var packed: PackedScene = _find_remote_packed()
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


func _find_remote_packed() -> PackedScene:
	for path: String in REMOTE_GLB_CANDIDATES:
		if ResourceLoader.exists(path):
			var loaded: Resource = ResourceLoader.load(path)
			if loaded is PackedScene:
				return loaded as PackedScene
	return null


func _apply_world_event(kind: String, target_name: String, from_peer: int = 0) -> void:
	# Closed allowlist: unknown kinds never reach find_child + call.
	if not ALLOWED_WORLD_EVENT_KINDS.has(kind):
		return
	if target_name == "" or target_name.length() > MAX_TARGET_NAME_LEN:
		return
	var root: Node = _get_mission_root()
	if root == null:
		return
	var target: Node = root.find_child(target_name, true, false)
	if target == null or target == root:
		return
	# Ownership: the target must be a node of the mission scene subtree.
	# The transport's own remote visuals are never valid event targets.
	if not root.is_ancestor_of(target):
		return
	if remote_visuals.values().has(target):
		return
	# The interactor passed to gameplay is the sender's remote player node,
	# never the NetManager itself.
	var interactor: Node3D = _ensure_remote_visual(from_peer, "")
	if interactor == null or not is_instance_valid(interactor):
		return
	match kind:
		"interact", "collect":
			if target.has_method("interact"):
				target.call("interact", interactor)
		"open":
			if target.has_method("open"):
				target.call("open")
		"trigger":
			if target.has_signal("triggered"):
				target.emit_signal("triggered")
