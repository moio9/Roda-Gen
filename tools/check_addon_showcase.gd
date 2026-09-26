extends "./check_road_examples.gd"

func _run() -> void:
	root.size = Vector2i(1440, 1000)
	var scene := load("res://addons/scenes/examples/addon_showcase.tscn").instantiate() as Node3D
	root.add_child(scene)
	var camera := scene.get_node("Camera") as Camera3D
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	for i in range(5):
		await process_frame
	var road := scene.get_node("Road")
	var terrain := scene.get_node("Terrain")
	var deadline := Time.get_ticks_msec() + 90000
	while road.is_road_generation_pending() or terrain.is_terrain_generation_pending():
		if Time.get_ticks_msec() > deadline:
			push_error("Showcase generation timed out")
			quit(1)
			return
		await process_frame
	for i in range(5):
		await process_frame
	_check_generic_scripts(scene)
	if terrain._active_height_modifiers.size() != 1:
		push_error("Showcase terrain must consume TownGrade")
		failures += 1
	if scene.get_node("Trees").get_placement_rebuild_stats().get("pending_terrain", true):
		push_error("Trees must finish snapping after terrain generation")
		failures += 1
	for path in ["Road/GeneratedSplineRoadWelded", "Road/GeneratedRoadMarkings", "Terrain/GeneratedTopologyTerrain",
		"Crosswalks", "FencePosts", "FenceLowerRail", "FenceUpperRail", "GuardrailPosts", "Guardrail", "LampPoles", "LampHeads", "Trees"]:
		var output := scene.get_node_or_null(path)
		if output == null or not _has_renderable(output):
			push_error("Missing showcase output: " + path)
			failures += 1
	var stats: Dictionary = road.get_source_rebuild_stats()
	var reports: Array = stats.get("contour_junctions", [])
	if reports.size() != 1 or not reports[0].ok or reports[0].arms != 4:
		push_error("Showcase must have one working four-arm contour intersection: " + str(reports))
		failures += 1
	if stats.get("lateral_joins", {}).get("contacts", 0) <= 0:
		push_error("Showcase extra lane must join laterally")
		failures += 1
	var mesh := road.get_node("GeneratedSplineRoadWelded") as MeshInstance3D
	_check_asphalt(mesh, road.road_material_override,
		[Vector2(-45, -45), Vector2(-40, 50), Vector2(-45, -130)], [Vector2(-30, 55)])
	if "--screenshots" in OS.get_cmdline_user_args():
		var views := {
			"overview": [Vector3(185, 230, 240), Vector3(-20, 8, -25)],
			"junction": [Vector3(3, 68, 12), Vector3(-45, 0, -45)],
			"lanes": [Vector3(12, 55, 86), Vector3(-43, 0, 48)],
			"cliff": [Vector3(133, 73, 103), Vector3(77, 17, 32)]}
		for key in views:
			camera.position = views[key][0]
			camera.look_at(views[key][1])
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/roda-showcase-%s.png" % key)
	print("SHOWCASE ", "OK" if failures == 0 else "FAILED", " failures=", failures,
		" junctions=", reports.size(), " lateral_contacts=", stats.get("lateral_joins", {}).get("contacts", 0))
	scene.free()
	quit(0 if failures == 0 else 1)

func _has_renderable(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.instance_count > 0:
		return true
	for child in node.get_children():
		if _has_renderable(child):
			return true
	return false
