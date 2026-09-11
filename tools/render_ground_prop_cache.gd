extends "./render_topology_source_cache.gd"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ground prop comparison needs a real renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene := DEMO.instantiate()
	scene.get_node("Camera").fov = 45
	root.add_child(scene)
	var road: Node3D = scene.get_node("Road")
	var path: Path3D = road.get_node("Route")
	path.rebuild_lane_dependents()
	var terrain := TOPOLOGY.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
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
	var props := PROPS.new()
	props.name = "Props"
	props.road_network_source = NodePath("../Road")
	props.terrain_height_source = NodePath("../Terrain")
	props.source_paths.assign([NodePath("../Road/Route")])
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.5, 3, 0.5)
	props.item_material_override = StandardMaterial3D.new()
	props.item_material_override.albedo_color = Color(0.8, 0.03, 0.02)
	props.placement_mode = 3
	props.ranges_mode = 0
	props.spacing = 1.5
	props.outward_offset = 2
	props.snap_to_ground_enabled = true
	props.snap_to_ground_max_angle_deg = 89
	props.snap_to_ground_y_offset = 1.5
	props.render_mode = 1
	scene.add_child(props)
	var original := await _capture("ground-props-full")
	_check(_color_pixels(original, true) > 500 and _color_pixels(original, false) > 50, "terrain and snapped props are visibly distinct")
	road.incremental_generation_enabled = true
	terrain.incremental_generation_enabled = true
	_build_terrain(terrain)
	props.regenerate()
	var warm_root: Node = props.get_node("GeneratedSplineProps")
	var warm_resources: Array = []
	for batch: MultiMeshInstance3D in warm_root.get_children():
		warm_resources.append([batch.get_instance_id(), batch.multimesh.get_instance_id()])
	_build_terrain(terrain)
	props.regenerate()
	var retained_resources: Array = []
	for batch: MultiMeshInstance3D in props.get_node("GeneratedSplineProps").get_children():
		retained_resources.append([batch.get_instance_id(), batch.multimesh.get_instance_id()])
	_check(warm_resources == retained_resources and props.get_node("GeneratedSplineProps") == warm_root,
		"visible warm output preserves exact native batch and resource identities")
	_check(props.get_placement_rebuild_stats().output_buffers_rebuilt == 0,
		"warm visible output does not rewrite MultiMesh buffers")
	var warm := await _capture("ground-props-warm")
	_check(_changed_pixels(original, warm) == 0, "warm ground MultiMesh matches full generation")
	_check(props.get_placement_rebuild_stats().paths_reused == 1, "visible warm ground props reuse placements")
	var old_root: Node = props.get_node("GeneratedSplineProps")
	path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(8, 2, 0))
	road.regenerate()
	terrain.regenerate()
	props.regenerate()
	_check(props.get_placement_rebuild_stats().pending_terrain and props.get_node("GeneratedSplineProps") == old_root,
		"pending visible terrain preserves existing MultiMesh batches")
	while terrain.is_terrain_generation_pending():
		terrain._process_mesh_build()
	props._process(0)
	var stats: Dictionary = props.get_placement_rebuild_stats()
	_check(not stats.pending_terrain and stats.blocks_reused > 0 and stats.blocks_rebuilt > 0,
		"automatic completion update reuses and rebuilds actual ground prop blocks")
	var edited := await _capture("ground-props-edited")
	var edit_pixels := _changed_pixels(original, edited)
	_check(edit_pixels > 100, "ground scene edit visibly changes the result")
	road.incremental_generation_enabled = false
	terrain.incremental_generation_enabled = false
	_build_terrain(terrain)
	props.regenerate()
	var reference := await _capture("ground-props-edited-full")
	var changed := _changed_pixels(edited, reference)
	_check(changed == 0, "edited ground props and terrain match full reconstruction")
	print("GROUND_PROP_RENDER_%s changed_pixels=%s edit_pixels=%s local=%s" % ["FAILED" if _failed else "OK", changed, edit_pixels, stats])
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in range(3):
		await process_frame
	scene.free()
	quit(1 if _failed else 0)
