extends SceneTree

const EXAMPLES := ["urban_intersection", "highway_entry", "canyon_road"]
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1100, 800)
	for example in EXAMPLES:
		var packed := load("res://addons/scenes/examples/%s.tscn" % example) as PackedScene
		if packed == null:
			failures += 1
			continue
		var scene := packed.instantiate()
		root.add_child(scene)
		for frame in range(5):
			await process_frame
		var road := scene.get_node("Road")
		var terrain := scene.get_node("Terrain")
		var deadline := Time.get_ticks_msec() + 60000
		while road.is_road_generation_pending() or terrain.is_terrain_generation_pending():
			if Time.get_ticks_msec() > deadline:
				push_error("Generation timeout: " + example)
				failures += 1
				break
			await process_frame
		for node_path in ["Road/GeneratedSplineRoadWelded", "Road/GeneratedRoadMarkings", "Terrain/GeneratedTopologyTerrain"]:
			var output := scene.get_node_or_null(node_path) as MeshInstance3D
			if output == null or output.mesh == null or output.mesh.get_surface_count() == 0:
				push_error("Missing geometry: %s / %s" % [example, node_path])
				failures += 1
		var junctions: Dictionary = road.get_source_rebuild_stats().get("junction_geometry", {})
		var expected_junctions := 0
		if int(junctions.get("clusters_rebuilt", 0)) != expected_junctions:
			push_error("Unexpected junction count: " + example)
			failures += 1
		if example == "highway_entry":
			var merge := scene.get_node("AccelerationLane") as MeshInstance3D
			var ramp := scene.get_node("Road/EntryRamp") as Path3D
			if merge.mesh == null or not ramp.curve.get_point_position(2).is_equal_approx(Vector3(7.5, 0, 20)):
				push_error("Missing parallel acceleration lane connection")
				failures += 1
			_check_connector(merge, [Vector2(9, 21), Vector2(9, 99), Vector2(9, 140)],
				[Vector2(10, 160), Vector2(9, 181)])
		elif example == "urban_intersection":
			_check_connector(scene.get_node("Intersection"),
				[Vector2.ZERO, Vector2(0, 13.9), Vector2(13.9, 0), Vector2(0, -13.9), Vector2(-13.9, 0)],
				[Vector2(9.75, -9.75)])
		for source in ["Bollards", "GuardrailPosts", "Guardrail"]:
			var generator := scene.get_node_or_null(source)
			if generator != null and not _has_mesh(generator):
				push_error("Missing prop/deformer output: " + source)
				failures += 1
		var camera := scene.get_node("Camera") as Camera3D
		var initial := camera.transform
		var zoom := InputEventMouseButton.new()
		zoom.button_index = MOUSE_BUTTON_WHEEL_UP
		zoom.pressed = true
		camera._unhandled_input(zoom)
		if camera.transform == initial:
			failures += 1
		var reset := InputEventKey.new()
		reset.keycode = KEY_R
		reset.pressed = true
		camera._unhandled_input(reset)
		if not camera.transform.is_equal_approx(initial):
			failures += 1
		print("EXAMPLE ", example, " junctions=", junctions.get("clusters_rebuilt", 0))
		if "--screenshots" in OS.get_cmdline_user_args():
			if example == "urban_intersection":
				camera.position = Vector3(32, 42, 36)
				camera.look_at(Vector3.ZERO)
			elif example == "highway_entry":
				camera.position = Vector3(55, 115, 130)
				camera.look_at(Vector3(8, 0, 55))
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_png("/tmp/roda-example-%s.png" % example)
			if result != OK:
				failures += 1
		scene.queue_free()
		for frame in range(3):
			await process_frame
	print("ROAD EXAMPLES ", "OK" if failures == 0 else "FAILED", " failures=", failures)
	quit(0 if failures == 0 else 1)

func _has_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	for child in node.get_children():
		if _has_mesh(child):
			return true
	return false

func _check_connector(connector: MeshInstance3D, inside: Array, outside: Array) -> void:
	if connector.mesh == null or connector.mesh.get_surface_count() > 3:
		push_error("Connector must have geometry batched by material")
		failures += 1
		return
	for point in inside:
		if not _asphalt_covers(connector, point):
			push_error("Missing connector asphalt at " + str(point))
			failures += 1
	for point in outside:
		if _asphalt_covers(connector, point):
			push_error("Connector extends outside intended outline at " + str(point))
			failures += 1
	for surface_index in range(connector.mesh.get_surface_count()):
		if connector.mesh.surface_get_material(surface_index) != connector.asphalt:
			continue
		var vertices: PackedVector3Array = connector.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		for i in range(0, vertices.size(), 3):
			if (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).y >= 0:
				push_error("Back-facing asphalt triangle")
				failures += 1

func _asphalt_covers(connector: MeshInstance3D, point: Vector2) -> bool:
	for surface_index in range(connector.mesh.get_surface_count()):
		if connector.mesh.surface_get_material(surface_index) != connector.asphalt:
			continue
		var vertices: PackedVector3Array = connector.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		for i in range(0, vertices.size(), 3):
			var a := Vector2(vertices[i].x, vertices[i].z)
			var b := Vector2(vertices[i + 1].x, vertices[i + 1].z)
			var c := Vector2(vertices[i + 2].x, vertices[i + 2].z)
			if Geometry2D.is_point_in_polygon(point, PackedVector2Array([a, b, c])):
				return true
	return false
