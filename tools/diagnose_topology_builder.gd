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

	if builder.has_method("regenerate"):
		builder.call("regenerate")

	var frames := 0
	while builder.has_method("_is_generation_thread_active") and bool(builder.call("_is_generation_thread_active")):
		await process_frame
		frames += 1
		if frames > 2400:
			push_error("Timed out waiting for topology builder.")
			quit(1)
			return

	var mesh_node := _find_node_by_name(builder, "GeneratedTopologyTerrain") as MeshInstance3D
	var tri_count := 0
	if mesh_node != null and mesh_node.mesh != null:
		for si in range(mesh_node.mesh.get_surface_count()):
			var arrays := mesh_node.mesh.surface_get_arrays(si)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				tri_count += indices.size() / 3
			elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				tri_count += verts.size() / 3

	print("frames=", frames)
	print("mesh_found=", mesh_node != null)
	print("mesh_tris=", tri_count)
	print("reject_stats=", builder.get("_triangle_reject_stats"))
	print("generation_max_points=", builder.get("_generation_max_points"))
	quit()


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null
