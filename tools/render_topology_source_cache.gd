extends "./render_road_terrain_cache.gd"

const TOPOLOGY = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Separate terrain comparison needs a real renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene := DEMO.instantiate()
	scene.get_node("Camera").fov = 45
	var road: Node3D = scene.get_node("Road")
	road.sample_step = 2
	root.add_child(scene)
	var path: Path3D = road.get_node("Route")
	path.rebuild_lane_dependents()
	var terrain := TOPOLOGY.new()
	terrain.name = "SeparateTerrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.centered_triangulation_enabled = OS.get_cmdline_user_args().has("--centered")
	terrain.local_triangulation_enabled = OS.get_cmdline_user_args().has("--local-topology")
	var prefix := "topology-centered-" if terrain.centered_triangulation_enabled else "topology-"
	if terrain.local_triangulation_enabled:
		prefix += "local-"
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/Route")])
	terrain.path_sample_step = 3
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(40, 85)
	terrain.manual_size_xz = Vector2(190, 240)
	terrain.near_road_width = 10
	terrain.near_road_step = 4
	terrain.far_grid_step = 16
	terrain.invert_faces = true
	terrain.terrain_material_override = StandardMaterial3D.new()
	terrain.terrain_material_override.albedo_color = Color(0.12, 0.38, 0.08)
	scene.add_child(terrain)
	_build_terrain(terrain)
	var original := await _capture(prefix + "full")
	_check(_color_pixels(original, true) > 500, "separate terrain is visibly green")
	terrain.incremental_generation_enabled = true
	_build_terrain(terrain)
	_build_terrain(terrain)
	var warm := await _capture(prefix + "warm")
	_check(_changed_pixels(original, warm) == 0, "warm separate terrain matches full generation")
	_check(terrain.get_source_rebuild_stats().delaunay_reused == 1, "visible warm terrain skipped native triangulation")
	var edit_delta := Vector3(0.25, 0.1, 0) if OS.get_cmdline_user_args().has("--small-edit") else Vector3(8, 2, 0)
	path.curve.set_point_position(2, path.curve.get_point_position(2) + edit_delta)
	road.regenerate()
	_build_terrain(terrain)
	var stats: Dictionary = terrain.get_source_rebuild_stats()
	if terrain.local_triangulation_enabled:
		_check(stats.local_triangulation.get("fallback", "missing") == ""
			and stats.local_triangulation.get("triangles_reused", 0) > 0
			and stats.local_triangulation.get("triangles_rebuilt", 0) > 0,
			"visible edit actually uses a mixed local triangulation patch")
	_check(stats.nearest_reused > 0 and stats.nearest_rebuilt > 0, "visible edit reuses and rebuilds nearest searches")
	_check(stats.heights_reused > 0 and stats.heights_rebuilt > 0, "visible edit reuses and rebuilds terrain heights")
	var edited := await _capture(prefix + "edited")
	var edit_pixels := _changed_pixels(original, edited)
	_check(edit_pixels > 100, "separate terrain edit visibly changes the scene")
	terrain.incremental_generation_enabled = false
	_build_terrain(terrain)
	var reference := await _capture(prefix + "edited-full")
	var changed := _changed_pixels(edited, reference)
	_check(changed == 0, "edited separate terrain matches full reference")
	print("TOPOLOGY_SOURCE_RENDER_%s changed_pixels=%s edit_pixels=%s local=%s" % ["FAILED" if _failed else "OK", changed, edit_pixels, stats])
	print("TOPOLOGY_CENTERED_MODE ", terrain.centered_triangulation_enabled)
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in range(3):
		await process_frame
	scene.free()
	quit(1 if _failed else 0)


func _build_terrain(terrain: Node) -> void:
	terrain.regenerate()
	while not terrain._mesh_build_state.is_empty():
		terrain._process_mesh_build()
