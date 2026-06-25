extends SceneTree

var _road_node: Node = null
var _frame := 0
var _max_wait_ms := 300000
var _start_ms := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless --path . --script tools/profile_road_scene.gd -- res://path/to/scene.tscn [RoadNodeName] [max_wait_ms] [property=value...]")
		quit(2)
		return
	var scene_path := str(args[0])
	var road_node_name := ""
	if args.size() >= 2:
		road_node_name = str(args[1])
	if args.size() >= 3:
		_max_wait_ms = maxi(1, int(args[2]))
	_start_ms = Time.get_ticks_msec()

	var packed := load(scene_path)
	if packed == null:
		push_error("Failed to load scene: " + scene_path)
		quit(2)
		return
	var scene: Node = packed.instantiate()
	_road_node = _find_profile_node(scene, road_node_name)
	if _road_node == null:
		push_error("Could not find a node with profile_generation_timings in scene: " + scene_path)
		quit(2)
		return
	_road_node.set("profile_generation_timings", true)
	if _has_property(_road_node, "debug_generation_logs"):
		_road_node.set("debug_generation_logs", true)
	for i in range(3, args.size()):
		_apply_override(str(args[i]))
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _road_node != null and _road_node.has_method("_is_generation_thread_active"):
		var active := bool(_road_node.call("_is_generation_thread_active"))
		if not active and _frame > 2:
			quit(0)
			return true
	if Time.get_ticks_msec() - _start_ms >= _max_wait_ms:
		push_error("Timed out waiting for generation.")
		quit(3)
		return true
	return false


func _find_profile_node(node: Node, preferred_name: String) -> Node:
	if (preferred_name.is_empty() or node.name == preferred_name) and _has_property(node, "profile_generation_timings"):
		return node
	for child in node.get_children():
		var found := _find_profile_node(child, preferred_name)
		if found != null:
			return found
	return null


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _apply_override(text: String) -> void:
	var eq := text.find("=")
	if eq <= 0:
		return
	var key := text.substr(0, eq)
	var value_text := text.substr(eq + 1)
	if not _has_property(_road_node, key):
		push_warning("Unknown road generator property: " + key)
		return
	var current = _road_node.get(key)
	var value: Variant = value_text
	if current is bool:
		value = value_text.to_lower() in ["1", "true", "yes", "on"]
	elif current is int:
		value = int(value_text)
	elif current is float:
		value = float(value_text)
	_road_node.set(key, value)
