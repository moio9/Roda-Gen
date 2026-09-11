extends "./check_road_presets.gd"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This check needs a real renderer, without --headless.")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene := DEMO.instantiate()
	root.add_child(scene)
	var camera := scene.get_node("Camera") as Camera3D
	camera.position = Vector3(22, 18, 40)
	camera.look_at(Vector3(7, 3, 65))
	for index in range(3):
		var road: Node3D
		# A fresh demo per style keeps material and transform state independent.
		if index > 0:
			var fresh := DEMO.instantiate()
			road = fresh.get_node("Road")
			fresh.remove_child(road)
			fresh.free()
			scene.add_child(road)
		else:
			road = scene.get_node("Road")
		_check(road.apply_road_preset(CONTROLLER.BUILTINS[index]) == OK, "render preset applies")
		var label: String = ["mountain", "urban", "highway"][index]
		var original := await _capture(label)
		road.get_node(CONTROLLER.NODE_NAME).visible = false
		var without := await _capture(label + "-without-barriers")
		var barrier_pixels := _changed_pixels(original, without)
		_check(barrier_pixels > 200, "barriers are visible for " + label)
		road.get_node(CONTROLLER.NODE_NAME).visible = true
		var file := "/tmp/roda-preset-render-%s-%s.tscn" % [label, Time.get_ticks_usec()]
		_check(road.bake_runtime_scene(file) == OK, "rendered road bakes")
		var baked: Node3D = load(file).instantiate()
		road.free()
		scene.add_child(baked)
		var baked_image := await _capture(label + "-baked")
		var changed := _changed_pixels(original, baked_image)
		_check(changed < 10, "baked preset renders identically for " + label)
		print("ROAD_PRESET_IMAGE %s visible_barrier_pixels=%s baked_changed_pixels=%s" % [label, barrier_pixels, changed])
		baked.free()
	scene.free()
	print("ROAD_PRESETS_RENDER_%s" % ("FAILED" if _failed else "OK"))
	quit(1 if _failed else 0)


func _capture(label: String) -> Image:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty(), "renderer returns an image")
	_check(rendered.save_png("/tmp/roda-preset-%s.png" % label) == OK, "image saves")
	return rendered


func _changed_pixels(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return 9999999
	var changed := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			changed += int(maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b))) > 0.02)
	return changed
