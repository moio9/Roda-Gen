extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://addons/scenes/examples/junction_playground.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	root.size = Vector2i(1400, 800)
	root.add_child(scene)
	await process_frame
	var failures := 0
	var profiles: Array = []
	for name in ["Cross", "T_Junction", "Oblique"]:
		var road := scene.get_node(name)
		var reports: Array = road.get_source_rebuild_stats().contour_junctions
		var arms := 3 if name == "T_Junction" else 4
		if reports.size() != 1 or not reports[0].ok or reports[0].arms != arms:
			failures += 1
		for output in ["GeneratedSplineRoadWelded", "GeneratedRoadMarkings"]:
			var mesh := road.get_node_or_null(output) as MeshInstance3D
			if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
				failures += 1
		if road.junction_corner_profile in profiles:
			failures += 1
		profiles.append(road.junction_corner_profile)
		print("PLAYGROUND ", name, " ", reports)
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/roda-junction-playground.png")
		var camera := scene.get_node("Camera") as Camera3D
		var road := scene.get_node("T_Junction") as Node3D
		var report: Array = road.get_source_rebuild_stats().contour_junctions
		if report.size() == 1 and report[0].ok:
			var focus: Vector3 = road.to_global(report[0].center)
			camera.position = focus + Vector3(18, 52, 38)
			camera.look_at(focus)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/roda-junction-playground-detail.png")
	scene.queue_free()
	await process_frame
	print("JUNCTION PLAYGROUND ", "OK" if failures == 0 else "FAILED")
	quit(failures)
