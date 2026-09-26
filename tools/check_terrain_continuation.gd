extends "./check_topology_source_cache.gd"


func _run() -> void:
	if "--screenshot" in OS.get_cmdline_user_args():
		await _capture_demo()
		quit()
		return
	var scene: Node3D = load("res://addons/scenes/examples/wide_chasm.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var terrain: Node3D = scene.get_node("Terrain")
	var path: Path3D = scene.get_node("Road/Ridge")
	terrain.generate_on_ready = false
	_build(terrain)
	_height(terrain, Vector3(220, 0, 0), -45, "right floor extends well beyond profile")
	_height(terrain, Vector3(-90, 0, 0), 0, "left side keeps legacy base")
	_check(_terrain_geometry(terrain).size() > 1, "demo generates mesh and collision")
	var mesh: Mesh = terrain.get_node("GeneratedTopologyTerrain").mesh
	var far_floor_vertices := 0
	for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.x > 180 and absf(vertex.y + 45) < 0.01:
			far_floor_vertices += 1
	_check(far_floor_vertices > 10, "actual generated triangles cover the distant floor")
	var continued := _terrain_geometry(terrain)
	terrain.incremental_generation_enabled = true
	_build(terrain)
	_build(terrain)
	_check(continued == _terrain_geometry(terrain), "warm cache preserves continuation mesh and collision")
	path.terrain_right_profile_continuation = -1
	_build(terrain)
	_height(terrain, Vector3(220, 0, 0), 0, "inherit defaults restores return to base")
	_check(continued != _terrain_geometry(terrain), "changing path mode rebuilds actual mesh")
	_assert_terrain_full_equal(terrain, "path mode edit")
	terrain.right_profile_continuation = 1
	_build(terrain)
	_height(terrain, Vector3(220, 0, 0), -45, "builder continuation inherited by path")
	_assert_terrain_full_equal(terrain, "global mode edit")
	path.terrain_right_profile_continuation = 0
	_build(terrain)
	_height(terrain, Vector3(220, 0, 0), 0, "explicit return overrides global continuation")
	terrain.left_profile_heights = PackedFloat32Array([0, 5, 12])
	path.terrain_left_profile_continuation = 1
	_build(terrain)
	_height(terrain, Vector3(-90, 0, 0), 12, "left continuation supports raised plateau")
	_height(terrain, Vector3(220, 0, 0), 0, "right side remains independent")
	_assert_terrain_full_equal(terrain, "left raised plateau")
	path.terrain_height_profile_override_enabled = true
	path.terrain_left_profile_distances = PackedFloat32Array([0, 20])
	path.terrain_left_profile_heights = PackedFloat32Array([0, 12])
	path.terrain_right_profile_distances = PackedFloat32Array([0, 20])
	path.terrain_right_profile_heights = PackedFloat32Array([0, -60])
	path.terrain_right_profile_continuation = 1
	_build(terrain)
	_height(terrain, Vector3(220, 0, 0), -60, "per-path height profile works with continuation")
	_assert_terrain_full_equal(terrain, "local height profile")
	scene.free()
	print("TERRAIN CONTINUATION %s (%d checks)" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _capture_demo() -> void:
	var demo: Node3D = load("res://addons/scenes/examples/wide_chasm.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	var terrain: Node = demo.get_node("Terrain")
	while terrain.is_terrain_generation_pending():
		await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/roda-wide-chasm.png")
	demo.free()


func _height(terrain: Node, point: Vector3, expected: float, label: String) -> void:
	var result: Dictionary = terrain.get_terrain_height_at_world(point)
	_check(result.get("hit", false) and absf(float(result.get("y", INF)) - expected) < 0.01,
		"%s: expected %.2f, got %s" % [label, expected, result])
