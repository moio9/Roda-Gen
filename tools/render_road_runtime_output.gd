extends "./check_road_runtime_output.gd"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run with a real renderer, without --headless.")
		quit(2)
		return
	# Keep render resolution independent of tiling/window-manager startup resizing.
	root.content_scale_size = Vector2i(640, 480)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.04, 0.05, 0.07)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -20, 0)
	root.add_child(sun)
	var road := _make_road()
	road.incremental_generation_enabled = "--incremental" in OS.get_cmdline_user_args()
	var colors := [Color(0.2, 0.25, 0.3), Color(0.7, 0.55, 0.35), Color(0.85, 0.85, 0.85), Color(0.23, 0.38, 0.18), Color(0.6, 0.3, 0.12)]
	var property_names := ["road_material_override", "shoulder_material_override", "sidewalk_material_override", "terrain_material_override", "outer_wall_material_override"]
	for i in range(colors.size()):
		var mat: StandardMaterial3D = road.get(property_names[i])
		mat.albedo_color = colors[i]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lane: StandardMaterial3D = road.get("left_lane_material_overrides")[0]
	lane.albedo_color = Color(0.28, 0.32, 0.38)
	lane.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.add_child(road)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = road.global_transform * Vector3(0, 85, 70)
	camera.look_at(road.global_transform * Vector3.ZERO)
	camera.far = 1000.0
	camera.current = true
	var single := await _capture("single")
	road.output_mode = 1
	road.output_chunk_size = 25.0
	road.regenerate()
	_check(road.get_output_rebuild_stats().source_surface_uploads == (0 if road.incremental_generation_enabled else 5),
		"render exercises the requested native/direct source path")
	var chunks := await _capture("chunks")
	_compare_images(single, chunks, "single_vs_chunks")
	var bake_path := "/tmp/roda-render-bake-%s.tscn" % Time.get_ticks_usec()
	_check(road.bake_runtime_scene(bake_path) == OK, "visual fixture bakes")
	var packed := ResourceLoader.load(bake_path) as PackedScene
	if packed != null:
		road.free()
		var baked := packed.instantiate()
		root.add_child(baked)
		var baked_image := await _capture("baked")
		_compare_images(chunks, baked_image, "chunks_vs_baked")
	print("ROAD_RUNTIME_RENDER_", "FAILED" if _failed else "OK")
	quit(1 if _failed else 0)


func _capture(label: String) -> Image:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty(), "renderer produced image")
	if rendered != null and not rendered.is_empty():
		_check(rendered.save_png("/tmp/roda-runtime-%s.png" % label) == OK, "screenshot saved")
	print("ROAD_RUNTIME_DRAWS mode=%s calls=%s" % [label, root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	return rendered


func _compare_images(expected: Image, actual: Image, label: String) -> void:
	if expected == null or actual == null or expected.get_size() != actual.get_size():
		_check(false, "rendered image dimensions match")
		return
	var changed := 0
	var foreground := 0
	var background := expected.get_pixel(0, 0)
	for y in range(expected.get_height()):
		for x in range(expected.get_width()):
			var a := expected.get_pixel(x, y)
			var b := actual.get_pixel(x, y)
			if _color_delta(a, background) > 0.05:
				foreground += 1
			if _color_delta(a, b) > 0.02:
				changed += 1
	_check(foreground > 2000, "camera sees substantial road geometry")
	_check(changed <= maxi(5, int(foreground * 0.001)), "rendered output matches: " + label)
	print("ROAD_RUNTIME_IMAGE %s foreground=%s changed=%s" % [label, foreground, changed])


func _color_delta(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
