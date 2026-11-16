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

var peer: ENetMultiplayerPeer
var is_coop: bool = false
var remote_visuals: Dictionary = {} # peer_id -> Node3D


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int): peer_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): peer_disconnected.emit(id))
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
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
		is_coop = true
	return err


func disconnect_net() -> void:
	for key: Variant in remote_visuals.keys():
		var n: Variant = remote_visuals.get(key)
		if n is Node and is_instance_valid(n as Node):
			(n as Node).queue_free()
	remote_visuals.clear()
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_coop = false


func broadcast_player_state(pos: Vector3, yaw: float, crouching: bool, thief_id: String) -> void:
	if not is_coop or multiplayer.multiplayer_peer == null:
		return
	sync_player_state.rpc(pos, yaw, crouching, thief_id)


func send_world_event(kind: String, target_name: String) -> void:
	if not is_coop or multiplayer.multiplayer_peer == null:
		return
	sync_world_event.rpc(kind, target_name)


@rpc("any_peer", "unreliable_ordered")
func sync_player_state(pos: Vector3, yaw: float, crouching: bool, thief_id: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	var visual: Node3D = _ensure_remote_visual(sender, thief_id)
	visual.position = pos
	visual.rotation = Vector3(0.0, yaw, 0.0)
	var target_scale: float = 0.72 if crouching else 1.0
	visual.scale = Vector3(1.0, target_scale, 1.0)
	remote_state_updated.emit(sender)


@rpc("any_peer", "reliable")
func sync_world_event(kind: String, target_name: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	world_event_received.emit(kind, target_name, sender)
	_apply_world_event(kind, target_name)


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
	if not is_coop:
		return
	_ensure_remote_visual(id, "")


func _on_peer_disconnected_despawn(id: int) -> void:
	var n: Variant = remote_visuals.get(id)
	if n is Node and is_instance_valid(n as Node):
		(n as Node).queue_free()
	remote_visuals.erase(id)


func _ensure_remote_visual(peer_id: int, thief_id: String) -> Node3D:
	var existing: Variant = remote_visuals.get(peer_id)
	if existing is Node3D and is_instance_valid(existing as Node):
		return existing as Node3D
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


func _apply_world_event(kind: String, target_name: String) -> void:
	if kind == "" or target_name == "":
		return
	var root: Node = _get_mission_root()
	var target: Node = root.find_child(target_name, true, false)
	if target == null:
		return
	if kind == "interact" and target.has_method("interact"):
		target.call("interact", self)
	elif kind == "collect" and target.has_method("interact"):
		target.call("interact", self)
	elif kind == "open" and target.has_method("open"):
		target.call("open")
	elif target.has_signal("triggered"):
		target.emit_signal("triggered")
