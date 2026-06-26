extends SceneTree


func _initialize() -> void:
	var scene_path := "res://addons/scenes/test.tscn"
	var node_name := "TerrainTopologyBuilder3D"
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		scene_path = str(args[0])
	if args.size() >= 2:
		node_name = str(args[1])

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Could not load scene: " + scene_path)
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var builder := _find_node_by_name(scene, node_name)
	if builder == null:
		push_error("Could not find node: " + node_name)
		quit(1)
		return

	builder.set("debug_logs", true)
	builder.call("_get_cached_road_data")
	builder.call("_get_cached_road_data")
	print("cache_check_done")
	quit()


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null
