extends "./render_road_markings.gd"

const PROPS = preload("../addons/scripts/spline_road/spline_prop_array.gd")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Terrain/props image comparison needs a real renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene := DEMO.instantiate()
	# Keep the denser prop blocks and white edge paint legible in one capture.
	scene.get_node("Camera").fov = 45
	var road: Node3D = scene.get_node("Road")
	road.sample_step = 2.0
	road.terrain_growth_scan_step = 2.0
	road.terrain_noise_enabled = true
	road.terrain_noise_amplitude = 1.1
	road.terrain_skirt_depth = 2.0
	road.terrain_material_override = StandardMaterial3D.new()
	road.terrain_material_override.albedo_color = Color(0.12, 0.38, 0.08)
	var path: Path3D = road.get_node("Route")
	path.terrain_override_enabled = true
	path.terrain_left_width = 8
	path.terrain_right_width = 8
	root.add_child(scene)
	path.rebuild_lane_dependents()
	road.regenerate()
	var props := PROPS.new()
	props.name = "Props"
	props.road_network_source = NodePath("../Road")
	props.source_paths = [NodePath("../Road/Route")]
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.5, 3, 0.5)
	props.item_material_override = StandardMaterial3D.new()
	props.item_material_override.albedo_color = Color(0.8, 0.03, 0.02)
	props.placement_mode = 3
	props.ranges_mode = 0
	# Enough candidates per path to exercise mixed rebuilt/reused source blocks.
	props.spacing = 1.5
	props.outward_offset = 2
	props.vertical_offset = 1.5
	props.render_mode = 1
	scene.add_child(props)
	var original := await _capture("terrain-full")
	_check(_color_pixels(original, true) > 500, "terrain is visibly green in the reference")
	_check(_color_pixels(original, false) > 50, "mesh props are visibly red in the reference")
	road.incremental_generation_enabled = true
	road.regenerate()
	props.regenerate()
	road.regenerate()
	props.regenerate()
	var warm := await _capture("terrain-warm")
	_check(_changed_pixels(original, warm) == 0, "full and warm terrain/props image parity")
	var terrain_stats: Dictionary = road.get_source_rebuild_stats().terrain_strips
	var prop_stats: Dictionary = props.get_placement_rebuild_stats()
	_check(terrain_stats.strips_reused == 1 and terrain_stats.growth_width_queries == 0, "rendered terrain skips strip construction")
	_check(prop_stats.paths_reused == 1 and prop_stats.sampling_steps == 0, "rendered MultiMesh props skip placement construction")
	path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(8, 2, 0))
	road.regenerate()
	props.regenerate()
	var edited_prop_stats: Dictionary = props.get_placement_rebuild_stats()
	var edited_terrain_stats: Dictionary = road.get_source_rebuild_stats().terrain_strips
	_check(edited_terrain_stats.growth_queries_reused > 0 and edited_terrain_stats.growth_width_queries > 0,
		"rendered terrain edit retains and rebuilds growth queries inside one path")
	_check(edited_terrain_stats.ring_rows_reused > 0 and edited_terrain_stats.ring_rows_rebuilt > 0,
		"rendered terrain edit retains and rebuilds ring geometry inside one path")
	_check(edited_prop_stats.blocks_reused > 0 and edited_prop_stats.blocks_rebuilt > 0,
		"rendered local edit reuses and rebuilds blocks within the same prop path")
	var edited := await _capture("terrain-edited")
	_check(_changed_pixels(original, edited) > 100, "local edit visibly changes terrain and road")
	road.incremental_generation_enabled = false
	road.regenerate()
	props.regenerate()
	var reference := await _capture("terrain-edited-full")
	var changed := _changed_pixels(edited, reference)
	_check(changed == 0, "edited cached terrain/props match full reconstruction")
	print("ROAD_TERRAIN_RENDER_%s changed_pixels=%s terrain=%s props=%s edited_props=%s edited_terrain=%s" % ["FAILED" if _failed else "OK", changed, terrain_stats, prop_stats, edited_prop_stats, edited_terrain_stats])
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in range(3):
		await process_frame
	scene.free()
	quit(1 if _failed else 0)


func _color_pixels(rendered: Image, green: bool) -> int:
	var count := 0
	for y in range(rendered.get_height()):
		for x in range(rendered.get_width()):
			var pixel := rendered.get_pixel(x, y)
			if green:
				count += int(pixel.g > 0.15 and pixel.g > pixel.r * 1.5 and pixel.g > pixel.b * 1.5)
			else:
				count += int(pixel.r > 0.3 and pixel.r > pixel.g * 2.0 and pixel.r > pixel.b * 2.0)
	return count
