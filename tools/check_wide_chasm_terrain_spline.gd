extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var demo: Node3D = load("res://addons/scenes/examples/wide_chasm.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	var terrain: Node = demo.get_node("Terrain")
	while terrain.is_terrain_generation_pending() or not terrain._mesh_build_state.is_empty():
		await process_frame
	var raised: Dictionary = terrain.get_terrain_height_at_world(Vector3(145, 0, 0))
	var floor_: Dictionary = terrain.get_terrain_height_at_world(Vector3(240, 0, 0))
	# Curved source heights use baked path samples, not exact control-point interpolation.
	var valid: bool = raised.get("hit", false) and absf(raised.y + 20) < 0.5 \
		and floor_.get("hit", false) and absf(floor_.y + 45) < 0.1
	var mesh: Mesh = terrain.get_node("GeneratedTopologyTerrain").mesh
	var raised_vertices := 0
	for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.x > 115 and vertex.x < 180 and vertex.y > -30:
			raised_vertices += 1
	valid = valid and raised_vertices > 10
	if "--screenshot" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/roda-wide-chasm-terrain-spline.png")
	print("WIDE CHASM TERRAIN SPLINE %s raised=%s floor=%s vertices=%d" % [
		"OK" if valid else "FAILED", raised, floor_, raised_vertices])
	demo.free()
	quit(0 if valid else 1)
