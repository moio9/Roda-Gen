extends "./render_road_markings.gd"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Source-cache rendering check needs a real renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.msaa_3d = Viewport.MSAA_4X
	var scene := DEMO.instantiate()
	var road: Node3D = scene.get_node("Road")
	road.sample_step = 0.4
	root.add_child(scene)
	var path: Path3D = road.get_node("Route")
	path.rebuild_lane_dependents()
	road.regenerate()
	var original := await _capture("source-full")
	road.incremental_generation_enabled = true
	road.regenerate()
	road.regenerate()
	var warm := await _capture("source-warm")
	_check(_changed_pixels(original, warm) == 0, "unchanged source-cache render matches full generation")
	path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(8, 2, 0))
	road.regenerate()
	var stats: Dictionary = road.get_source_rebuild_stats()
	var edited := await _capture("source-edited")
	_check(stats.blocks_rebuilt > 0 and stats.blocks_reused > 0, "visible edit uses both dirty and cached blocks")
	_check(_changed_pixels(original, edited) > 100, "control point edit visibly changes the road")
	road.incremental_generation_enabled = false
	road.regenerate()
	var reference := await _capture("source-edited-full")
	var changed := _changed_pixels(edited, reference)
	_check(changed == 0, "edited source-cache render matches a fresh full generation")
	scene.free()
	print("ROAD_SOURCE_RENDER_%s changed_pixels=%s stats=%s" % ["FAILED" if _failed else "OK", changed, stats])
	quit(1 if _failed else 0)
