extends "./check_road_markings.gd"


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
	var road: Node3D = scene.get_node("Road")
	var camera := scene.get_node("Camera") as Camera3D
	await _capture("overview")
	camera.position = Vector3(25, 45, 35)
	camera.look_at(Vector3(0, 2, 40))
	var entry := await _capture("entry")
	road.markings_enabled = false
	road.regenerate()
	var off := await _capture("off")
	_check(_changed_pixels(entry, off) > 500, "paint makes a substantial visible difference")
	road.markings_enabled = true
	road.regenerate()
	camera.position = Vector3(110, 45, 140)
	camera.look_at(Vector3(70, 4, 140))
	await _capture("exit")
	camera.position = Vector3(25, 45, 35)
	camera.look_at(Vector3(0, 2, 40))
	var bake_path := "/tmp/roda-markings-render-%s.tscn" % Time.get_ticks_usec()
	_check(road.bake_runtime_scene(bake_path) == OK, "rendered road and paint bake")
	var baked: Node3D = load(bake_path).instantiate()
	road.free()
	scene.add_child(baked)
	var baked_image := await _capture("baked")
	var changed := _changed_pixels(entry, baked_image)
	_check(changed < 10, "baked road markings render identically")
	print("ROAD_MARKINGS_RENDER_%s baked_changed_pixels=%s" % ["FAILED" if _failed else "OK", changed])
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in range(3):
		await process_frame
	scene.free()
	quit(1 if _failed else 0)


func _capture(label: String) -> Image:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty(), "renderer returns an image")
	if rendered != null:
		_check(rendered.save_png("/tmp/roda-markings-%s.png" % label) == OK, "image saves")
	var yellow := 0
	var white := 0
	for y in range(rendered.get_height()):
		for x in range(rendered.get_width()):
			var pixel := rendered.get_pixel(x, y)
			yellow += int(pixel.r > 0.5 and pixel.g > 0.4 and pixel.b < pixel.r * 0.6)
			white += int(minf(pixel.r, minf(pixel.g, pixel.b)) > 0.65)
	if label != "off":
		_check(yellow > 50 and white > 100, "both center and lane/edge paint are visible in " + label)
	print("ROAD_MARKINGS_IMAGE %s yellow=%s white=%s" % [label, yellow, white])
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
