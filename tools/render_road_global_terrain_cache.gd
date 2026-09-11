extends "./render_road_terrain_cache.gd"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Global terrain image comparison needs a real renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene := DEMO.instantiate()
	scene.get_node("Camera").fov = 45
	var road: Node3D = scene.get_node("Road")
	road.sample_step = 2.0
	road.terrain_fill_algorithm = 1
	road.terrain_fill_topology = 3
	road.terrain_fill_grid_tile_size = 12
	road.terrain_fill_outer_padding = 10
	road.terrain_rect_fill_cell_size = 6
	road.terrain_rect_fill_interior_point_step = 8
	road.terrain_fill_height_match_max_distance = 12
	road.terrain_fill_base_height = -2
	road.terrain_fill_adaptive_max_depth = 1
	road.terrain_material_override = StandardMaterial3D.new()
	road.terrain_material_override.albedo_color = Color(0.12, 0.38, 0.08)
	# Independent outer roads hold the seed-grid bounds fixed for an interior edit.
	for position in [Vector3(-30, 0, -25), Vector3(125, 0, 185)]:
		var anchor := Path3D.new()
		anchor.curve = Curve3D.new()
		anchor.curve.add_point(position)
		anchor.curve.add_point(position + Vector3(0, 0, 10))
		road.add_child(anchor)
	var path: Path3D = road.get_node("Route")
	var original_point := path.curve.get_point_position(2)
	root.add_child(scene)
	path.rebuild_lane_dependents()
	for algorithm in [1, 2]:
		road.terrain_fill_algorithm = algorithm
		road.terrain_fill_height_assign_only = algorithm == 2
		path.curve.set_point_position(2, original_point)
		road.incremental_generation_enabled = false
		road.regenerate()
		var original := await _capture("global-terrain-%s-full" % algorithm)
		_check(_color_pixels(original, true) > 500, "global fill is visibly green")
		road.incremental_generation_enabled = true
		road.regenerate()
		road.regenerate()
		var warm := await _capture("global-terrain-%s-warm" % algorithm)
		var warm_stats: Dictionary = road.get_source_rebuild_stats().terrain_strips
		_check(warm_stats.fill_triangles > 0 and warm_stats.strips_rebuilt == 0, "rendered global terrain is not fallback strips")
		_check(warm_stats.fill_polygons_reused > 0, "rendered global terrain skips unchanged polygon construction")
		_check(_changed_pixels(original, warm) == 0, "warm global fill matches full reconstruction")
		path.curve.set_point_position(2, original_point + Vector3(8, 2, 0))
		road.regenerate()
		var edited_stats: Dictionary = road.get_source_rebuild_stats().terrain_strips
		_check(edited_stats.fill_polygons_reused > 0 and edited_stats.fill_polygons_rebuilt > 0, "rendered edit reuses and rebuilds global polygons")
		var edited := await _capture("global-terrain-%s-edited" % algorithm)
		var edit_pixels := _changed_pixels(original, edited)
		_check(edit_pixels > 100, "global terrain edit visibly changes the scene")
		road.incremental_generation_enabled = false
		road.regenerate()
		var reference := await _capture("global-terrain-%s-edited-full" % algorithm)
		var changed := _changed_pixels(edited, reference)
		_check(changed == 0, "edited global terrain matches full reconstruction")
		print("GLOBAL_TERRAIN_RENDER algorithm=%s changed_pixels=%s edit_pixels=%s edited=%s" % [algorithm, changed, edit_pixels, edited_stats])
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in range(3):
		await process_frame
	scene.free()
	print("ROAD_GLOBAL_TERRAIN_RENDER_%s" % ["FAILED" if _failed else "OK"])
	quit(1 if _failed else 0)
