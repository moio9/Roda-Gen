extends "./check_road_junction_geometry_cache.gd"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Junction image comparison requires a real renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.035, 0.045, 0.055)
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -20, 0)
	root.add_child(sun)
	var road := _make_fans()
	road.incremental_generation_enabled = false
	for property in ["road_material_override", "shoulder_material_override"]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(0.32, 0.35, 0.38) if property == "road_material_override" else Color(0.8, 0.55, 0.22)
		road.set(property, material)
	root.add_child(road)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(110, 220, 160)
	camera.look_at(Vector3(110, 0, 0))
	camera.current = true
	camera.far = 1000
	var full := await _capture("full")
	road.incremental_generation_enabled = true
	road.regenerate()
	road.regenerate()
	var warm := await _capture("warm")
	_check(_junction_stats(road).clusters_reused == 2, "rendered fans reuse geometry")
	_check(_changed(full, warm) == 0, "warm junction image equals full reconstruction")
	var path: Path3D = road.get_node("Fan0Arm0")
	path.curve.set_point_position(0, Vector3(1.5, 0.5, 0))
	road.regenerate()
	var stats := _junction_stats(road)
	_check(stats.clusters_reused == 1 and stats.clusters_rebuilt == 1, "visible edit rebuilds only one fan")
	var edited := await _capture("edited")
	var edit_difference := _changed(full, edited)
	_check(edit_difference > 20, "control point edit visibly changes the junction")
	road.incremental_generation_enabled = false
	road.regenerate()
	var reference := await _capture("edited-full")
	var difference := _changed(edited, reference)
	_check(difference == 0, "local junction replay equals edited full reference")
	print("ROAD_JUNCTION_RENDER_%s changed_pixels=%s edit_pixels=%s stats=%s" % ["FAILED" if _failed else "OK", difference, edit_difference, stats])
	road.free()
	camera.free()
	world.free()
	sun.free()
	quit(1 if _failed else 0)


func _capture(label: String) -> Image:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty(), "renderer returns a junction image")
	_check(rendered.save_png("/tmp/roda-junction-%s.png" % label) == OK, "junction image saves")
	var foreground := 0
	for y in range(rendered.get_height()):
		for x in range(rendered.get_width()):
			foreground += int(rendered.get_pixel(x, y).r > 0.2)
	_check(foreground > 2000, "junctions are visible in " + label)
	return rendered


func _changed(a: Image, b: Image) -> int:
	var count := 0
	if a.get_size() != b.get_size():
		return 9999999
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			count += int(maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b))) > 0.02)
	return count
