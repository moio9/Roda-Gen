extends SceneTree

const EXAMPLES := ["urban_intersection", "highway_entry", "canyon_road"]
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1100, 800)
	await _check_runtime_terrain_startup()
	for example in EXAMPLES:
		var packed := load("res://addons/scenes/examples/%s.tscn" % example) as PackedScene
		if packed == null:
			failures += 1
			continue
		var scene := packed.instantiate()
		root.add_child(scene)
		# Physical keyboard/mouse input must not move the camera during checks.
		var camera := scene.get_node("Camera") as Camera3D
		camera.set_process(false)
		camera.set_process_unhandled_input(false)
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
		_check_generic_scripts(scene)
		var junctions: Dictionary = road.get_source_rebuild_stats().get("junction_geometry", {})
		var road_mesh := road.get_node("GeneratedSplineRoadWelded") as MeshInstance3D
		if example == "highway_entry":
			if not road.get_source_rebuild_stats().lateral_joins.transitions.is_empty():
				push_error("Authored zero-width ramp taper must not receive another extension")
				failures += 1
			if road.get_source_rebuild_stats().lateral_joins.contacts <= 0:
				push_error("Highway ramp must join laterally through the shared addon")
				failures += 1
			var ramp := scene.get_node("Road/EntryRamp") as Path3D
			if ramp.curve.point_count != 5 or scene.has_node("AccelerationLane"):
				push_error("Acceleration lane must belong to the editable ramp profile")
				failures += 1
			_check_asphalt(road_mesh, road.road_material_override,
				[Vector2(9, 21), Vector2(9, 99), Vector2(9, 140)],
				[Vector2(10, 160), Vector2(9, 181)])
		elif example == "urban_intersection":
			var reports: Array = road.get_source_rebuild_stats().get("contour_junctions", [])
			if reports.size() != 1 or not reports[0].ok or reports[0].arms != 4:
				push_error("Urban intersection must use the generic four-arm contour junction")
				failures += 1
			_check_asphalt(road_mesh, road.road_material_override,
				[Vector2.ZERO, Vector2(0, 13.9), Vector2(13.9, 0), Vector2(0, -13.9), Vector2(-13.9, 0)],
				[Vector2(9.75, -9.75)])
		for source in ["Bollards", "Crosswalks", "GuardrailPosts", "Guardrail"]:
			var generator := scene.get_node_or_null(source)
			if generator != null and not _has_mesh(generator):
				push_error("Missing prop/deformer output: " + source)
				failures += 1
		var initial := camera.transform
		var zoom := InputEventMouseButton.new()
		zoom.button_index = MOUSE_BUTTON_WHEEL_UP
		zoom.pressed = true
		camera._unhandled_input(zoom)
		if camera.transform == initial:
			push_error("Camera zoom did not move: " + example)
			failures += 1
		var reset := InputEventKey.new()
		reset.keycode = KEY_R
		reset.pressed = true
		camera._unhandled_input(reset)
		if not camera.transform.is_equal_approx(initial):
			push_error("Camera reset did not restore the view: " + example)
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

func _check_runtime_terrain_startup() -> void:
	var probe := preload("./fixtures/terrain_startup_probe.gd")
	var terrains: Array = []
	for enabled in [false, true]:
		var terrain := probe.new()
		terrain.generate_on_ready = enabled
		terrain.source_paths.assign([NodePath(".")])
		var saved_output := MeshInstance3D.new()
		saved_output.name = "GeneratedTopologyTerrain"
		saved_output.mesh = PlaneMesh.new()
		terrain.add_child(saved_output)
		terrains.append(terrain)
		root.add_child(terrain)
	for frame in range(3):
		await process_frame
	if terrains[0].rebuilds != 0 or not terrains[0].has_node("GeneratedTopologyTerrain"):
		push_error("Runtime terrain must preserve saved output unless opted in")
		failures += 1
	if terrains[1].rebuilds != 1:
		push_error("Opt-in runtime terrain must regenerate once")
		failures += 1
	for terrain in terrains:
		terrain.free()

func _has_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	for child in node.get_children():
		if _has_mesh(child):
			return true
	return false

func _check_generic_scripts(node: Node) -> void:
	var script := node.get_script() as Script
	if script != null and not script.resource_path.begins_with("res://addons/scripts/"):
		push_error("Example depends on a scene-specific script: " + script.resource_path)
		failures += 1
	for child in node.get_children():
		_check_generic_scripts(child)

func _check_asphalt(output: MeshInstance3D, asphalt: Material, inside: Array, outside: Array) -> void:
	for point in inside:
		if not _asphalt_covers(output, asphalt, point):
			push_error("Missing road asphalt at " + str(point))
			failures += 1
	for point in outside:
		if _asphalt_covers(output, asphalt, point):
			push_error("Road extends outside intended outline at " + str(point))
			failures += 1

func _asphalt_covers(output: MeshInstance3D, asphalt: Material, point: Vector2) -> bool:
	for surface_index in range(output.mesh.get_surface_count()):
		if output.mesh.surface_get_material(surface_index) != asphalt:
			continue
		var arrays := output.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count, 3):
			var polygon := PackedVector2Array()
			for j in range(3):
				var vertex := vertices[indices[i + j] if not indices.is_empty() else i + j]
				polygon.append(Vector2(vertex.x, vertex.z))
			if Geometry2D.is_point_in_polygon(point, polygon):
				return true
	return false
