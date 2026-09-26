extends SceneTree
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene: Node3D = load("res://addons/scenes/lane_appearance_demo.tscn").instantiate()
	root.add_child(scene)
	var road: Node3D = scene.get_node("Road")
	var path: Path3D = scene.get_node("Road/Route")
	var camera: Camera3D = scene.get_node("Camera")
	camera.look_at(Vector3(0, 0, -40))
	var original := await _capture("overview")
	var filename := "/tmp/roda-lane-appearance-render-%d.tscn" % Time.get_ticks_usec()
	_check(road.bake_runtime_scene(filename) == OK, "Bake succeeds")
	var rules: Array = path.lane_appearance_overrides.duplicate()
	path.lane_appearance_overrides.clear()
	road.regenerate()
	var defaults := await _capture("defaults")
	_check(_changed(original, defaults) > 500, "Per-lane markings and material are visible")
	path.lane_appearance_overrides.assign(rules)
	road.regenerate()
	var restored := await _capture("restored")
	_check(_changed(original, restored) == 0, "Removing/restoring rules restores rendered output exactly")
	var baked: Node3D = load(filename).instantiate()
	road.free()
	scene.add_child(baked)
	var baked_image := await _capture("baked")
	var changed := _changed(original, baked_image)
	_check(changed == 0, "Baked lane appearance matches procedural rendering")
	camera.position = Vector3(-15, 20, -12)
	camera.look_at(Vector3(-3, 0, -23))
	await _capture("entry")
	print("LANE APPEARANCE RENDER %s baked_changed_pixels=%d" % ["FAIL" if failed else "PASS", changed])
	root.msaa_3d = Viewport.MSAA_DISABLED
	for i in range(3):
		await process_frame
	scene.free()
	quit(1 if failed else 0)

func _capture(label: String) -> Image:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	_check(result.save_png("/tmp/roda-lane-appearance-%s.png" % label) == OK, "Capture saves")
	return result

func _changed(a: Image, b: Image) -> int:
	var count := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			count += int(maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b))) > 0.02)
	return count

func _check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)
