extends "./check_topology_source_cache.gd"
## Compares actual mesh attributes and concave collision, not just input indices.
var _initial_image: Image
var _last_full_ms := 0.0


func _run() -> void:
	var scene := Node3D.new()
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.generate_in_editor = false
	var path := PROFILE.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	for p in [Vector3(-35, 0, -30), Vector3(-20, 2, 0), Vector3(0, 4, 30), Vector3(20, 0, 60)]:
		path.curve.add_point(p, Vector3(0, 0, -10), Vector3(0, 0, 10))
	road.add_child(path)
	scene.add_child(road)
	var terrain := TOPOLOGY.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/Path")])
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(0, 20)
	terrain.manual_size_xz = Vector2(160, 160)
	terrain.near_road_width = 12
	terrain.near_road_step = 6
	terrain.far_grid_step = 12
	terrain.generate_collision = true
	var large := OS.get_cmdline_user_args().has("--large")
	terrain.centered_triangulation_enabled = large
	if large:
		for i in range(1, 10):
			var other := PROFILE.new()
			other.name = "Path" + str(i)
			other.curve = path.curve.duplicate(true)
			other.position.x = i * 85
			road.add_child(other)
			terrain.source_paths.append(NodePath("../Road/" + str(other.name)))
		terrain.manual_center_xz = Vector2(350, 20)
		terrain.manual_size_xz = Vector2(950, 220)
	terrain.incremental_generation_enabled = true
	terrain.local_triangulation_enabled = true
	scene.add_child(terrain)
	root.add_child(scene)
	if DisplayServer.get_name() != "headless":
		_setup_visual(scene, terrain)
	_build(terrain)
	_initial_image = await _capture_output("initial")
	_check(not terrain._local_delaunay._input.is_empty(), "native cold result seeds local support")
	for edit in range(3):
		path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(0.25, 0.1, 0))
		road.regenerate()
		var started := Time.get_ticks_usec()
		_build(terrain)
		var local_ms := float(Time.get_ticks_usec() - started) / 1000.0
		print("LOCAL_TOPOLOGY_LOCAL_STAGES ", terrain.get_source_rebuild_stats().stage_ms)
		print("LOCAL_TOPOLOGY_SOURCE_STATS ", terrain.get_source_rebuild_stats())
		if large:
			var source: Dictionary = terrain.get_source_rebuild_stats()
			_check(source.triangle_groups.triangles_reused > source.triangle_groups.triangles_rebuilt and source.evicted == 0,
				"ten-road local edits retain most filtered triangles without cyclic source eviction")
			_check(source.entries <= terrain._source_cache.MAX_TOPOLOGY_ENTRIES and source.payload_bytes <= terrain._source_cache.MAX_PAYLOAD_BYTES,
				"ten-road source retention respects entry and payload ceilings")
		var stats: Dictionary = terrain.get_source_rebuild_stats().local_triangulation
		print("LOCAL_TOPOLOGY_BEFORE_COMPARE ", stats)
		_check(stats.get("local_calls", 0) > 0 and stats.get("fallback", "") == "",
			"actual terrain uses local triangulation instead of full fallback")
		_check(stats.get("triangles_reused", 0) > 0 and stats.get("triangles_rebuilt", 0) > 0, "actual local output mixes retained and rebuilt triangles")
		await _compare_output(terrain, "edit " + str(edit))
		print("LOCAL_TOPOLOGY_TERRAIN_TIME edit=", edit, " local_ms=", local_ms, " full_ms=", _last_full_ms)
		print("LOCAL_TOPOLOGY_OUTPUT_EDIT ", stats)
	# The comparisons above intentionally clear/reseed the native reference. This
	# independent node lets several local edits keep their complete cache history.
	var continuous_reference := TOPOLOGY.new()
	for property: Dictionary in terrain.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			continuous_reference.set(property.name, terrain.get(property.name))
	continuous_reference.incremental_generation_enabled = false
	continuous_reference.generate_in_editor = false
	continuous_reference.threaded_triangulation_enabled = false
	scene.add_child(continuous_reference)
	for edit in range(4):
		path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(0.25, 0.1, 0))
		road.regenerate()
		_build(terrain)
		_build(continuous_reference)
		var source: Dictionary = terrain.get_source_rebuild_stats()
		_check(source.nearest_reused > 0, "consecutive edits keep source reuse beyond idle expiry")
		_check(source.entries <= terrain._source_cache.MAX_TOPOLOGY_ENTRIES and source.payload_bytes <= terrain._source_cache.MAX_PAYLOAD_BYTES,
			"consecutive edit history remains bounded")
		_check(_terrain_geometry(terrain) == _terrain_geometry(continuous_reference),
			"consecutive local edits have byte-exact mesh attributes and collision against independent full output")
	continuous_reference.free()
	var warm := _terrain_geometry(terrain)
	_build(terrain)
	_check(_terrain_geometry(terrain) == warm, "warm mesh/collision output retains exact buffer order")
	terrain.threaded_triangulation_enabled = true
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	_check(terrain._triangulation_thread != null, "cold local mode retains real worker fallback")
	terrain.centered_triangulation_enabled = not large
	terrain.regenerate()
	await _wait_terrain(terrain)
	_check(terrain._triangulation_context.centered == (not large), "restart captures latest conditioning mode")
	terrain.threaded_triangulation_enabled = false
	await _compare_output(terrain, "worker restart")
	terrain.threaded_triangulation_enabled = true
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	terrain.regenerate()
	terrain._clear_generated_from_button()
	await _wait_terrain(terrain)
	_check(terrain.get_node_or_null("GeneratedTopologyTerrain") == null, "clear cancels local-mode worker output and queued restart")
	terrain.clear_source_generation_cache()
	_check(terrain._local_delaunay._input.is_empty() and terrain._local_delaunay._index._triangles.is_empty(), "public cache clear releases local support")
	terrain.threaded_triangulation_enabled = false
	var modifier := DynamicModifier.new()
	terrain.add_child(modifier)
	_build(terrain)
	_check(not terrain._triangulation_context.local and not terrain._triangulation_context.canonical
		and terrain._local_delaunay._input.is_empty(), "arbitrary modifiers bypass retention and ordering changes")
	var calls: int = modifier.calls
	_build(terrain)
	_check(modifier.calls > calls, "modifier callbacks still run on unchanged inputs")
	await _compare_output(terrain, "modifier fallback")
	modifier.free()
	scene.free()
	print("LOCAL_TOPOLOGY_OUTPUT_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _wait_terrain(terrain: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while terrain._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not terrain._is_generation_thread_active(), "terrain job finishes")


func _compare_output(terrain: Node, label: String) -> void:
	var actual := _snapshot(terrain)
	var edited_image: Image = await _capture_output("edited") if label == "edit 0" else null
	terrain.incremental_generation_enabled = false
	var started := Time.get_ticks_usec()
	_build(terrain)
	_last_full_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("LOCAL_TOPOLOGY_FULL_STAGES ", terrain.get_source_rebuild_stats().stage_ms)
	var reference := _snapshot(terrain)
	if edited_image != null:
		var full_image: Image = await _capture_output("full")
		var changed := _pixel_difference(edited_image, full_image)
		var edited := _pixel_difference(_initial_image, edited_image)
		_check(changed == 0, "actual local/full terrain renders match pixel-for-pixel")
		_check(edited > 100, "local curve edit visibly changes the rendered terrain/road")
		var pixels := edited_image.get_data()
		var green := 0
		for i in range(0, pixels.size(), 4):
			if pixels[i + 1] > 30 and pixels[i + 1] > pixels[i] * 1.4 and pixels[i + 1] > pixels[i + 2] * 1.4:
				green += 1
		_check(green > 1000, "actual generated terrain is visible in the render comparison")
		print("LOCAL_TOPOLOGY_RENDER changed_pixels=", changed, " edit_pixels=", edited)
	_check(actual.collision == reference.collision, "exact oriented collision triangles: " + label)
	_check(actual.mesh.keys().size() == reference.mesh.keys().size() and actual.mesh.size() > 100,
		"actual terrain has matching nonempty triangle sets: " + label)
	var equal := true
	var max_normal_delta := 0.0
	for key: String in actual.mesh:
		if not reference.mesh.has(key) or actual.mesh[key].size() != reference.mesh[key].size():
			equal = false
			continue
		for i in range(actual.mesh[key].size()):
			var a: Array = actual.mesh[key][i]
			var b: Array = reference.mesh[key][i]
			for vertex in range(3):
				max_normal_delta = maxf(max_normal_delta, a[vertex * 2].distance_to(b[vertex * 2]))
				equal = equal and a[vertex * 2 + 1] == b[vertex * 2 + 1]
	_check(equal and max_normal_delta == 0.0, "exact oriented positions/UVs/normals: " + label)
	print("LOCAL_TOPOLOGY_NORMAL_DELTA ", label, " ", max_normal_delta)
	terrain.local_triangulation_enabled = true
	terrain.incremental_generation_enabled = true
	_build(terrain)


func _snapshot(terrain: Node) -> Dictionary:
	var triangles: Dictionary = {}
	for arrays: Array in _surface_arrays(terrain.get_node("GeneratedTopologyTerrain")):
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in range(positions.size()):
				indices.append(i)
		for i in range(0, indices.size(), 3):
			var ids := [indices[i], indices[i + 1], indices[i + 2]]
			var corners := PackedVector3Array([positions[ids[0]], positions[ids[1]], positions[ids[2]]])
			var order := _rotation(corners)
			var key := var_to_bytes(PackedVector3Array([corners[order], corners[(order + 1) % 3], corners[(order + 2) % 3]])).hex_encode()
			var attributes: Array = []
			for corner in range(3):
				var id: int = ids[(order + corner) % 3]
				attributes.append_array([normals[id], uvs[id]])
			if not triangles.has(key):
				triangles[key] = []
			triangles[key].append(attributes)
	var collision: Dictionary = {}
	var body := terrain.get_node_or_null("GeneratedTopologyTerrainCollision")
	for node: Node in body.get_children() if body != null else []:
		if node is CollisionShape3D:
			var faces: PackedVector3Array = node.shape.get_faces()
			for i in range(0, faces.size(), 3):
				var corners := faces.slice(i, i + 3)
				var order := _rotation(corners)
				var key := var_to_bytes(PackedVector3Array([corners[order], corners[(order + 1) % 3], corners[(order + 2) % 3]])).hex_encode()
				collision[key] = int(collision.get(key, 0)) + 1
	return {"mesh": triangles, "collision": collision}


func _surface_arrays(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			result.append(node.mesh.surface_get_arrays(surface))
	for child: Node in node.get_children():
		result.append_array(_surface_arrays(child))
	return result


func _rotation(corners: PackedVector3Array) -> int:
	var best := 0
	for i in range(1, 3):
		if var_to_bytes(corners[i]).hex_encode() < var_to_bytes(corners[best]).hex_encode():
			best = i
	return best


func _setup_visual(scene: Node3D, terrain: Node) -> void:
	root.size = Vector2i(960, 720)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(120, 150, 170)
	camera.look_at(Vector3(0, 0, 15))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.03, 0.04, 0.05)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, -0.5, 0)
	scene.add_child(light)
	terrain.invert_faces = true
	terrain.terrain_material_override = StandardMaterial3D.new()
	terrain.terrain_material_override.albedo_color = Color(0.12, 0.4, 0.08)


func _capture_output(label: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	rendered.convert(Image.FORMAT_RGBA8)
	_check(rendered.save_png("/tmp/roda-local-topology-%s.png" % label) == OK, "terrain image saves")
	return rendered


func _pixel_difference(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var left := a.get_data()
	var right := b.get_data()
	var changed := 0
	for i in range(0, left.size(), 4):
		if left[i] != right[i] or left[i + 1] != right[i + 1] or left[i + 2] != right[i + 2] or left[i + 3] != right[i + 3]:
			changed += 1
	return changed
