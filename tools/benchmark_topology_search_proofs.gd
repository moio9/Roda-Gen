extends "./check_topology_source_cache.gd"
## Run alone. Strict mode reproduces the old global-width invalidation rule.
class StrictWidth extends "../addons/scripts/spline_road/topology_stage_cache.gd":
	func begin_mesh_scope(previous: Dictionary = {}) -> void:
		super.begin_mesh_scope(previous)
		_mesh_scope.strict_width = _mesh_search_width
	func validate_mesh_scope(scope: Dictionary) -> bool:
		return scope.get("strict_width", -INF) == _mesh_search_width and super.validate_mesh_scope(scope)


func _run() -> void:
	var scene: Node3D = load("res://addons/scenes/road_markings_demo.tscn").instantiate()
	var road: Node3D = scene.get_node("Road")
	road.threaded_generation_enabled = false
	road.incremental_generation_enabled = true
	road.allow_endpoint_to_midpath = false
	var path: Path3D = road.get_node("Route")
	var far: Path3D = path.duplicate()
	far.name = "FarRoute"
	far.curve = path.curve.duplicate(true)
	far.position.x = 350
	road.add_child(far)
	for center: Vector3 in [Vector3.ZERO, Vector3(350, 0, 0)]:
		for arm in range(2):
			var branch := PROFILE.new()
			branch.name = "%sArm%d" % ["Near" if center.x == 0 else "Far", arm]
			branch.show_width_preview = false
			branch.curve = Curve3D.new()
			var offset := Vector3(-40, 0, -20) if arm == 0 else Vector3(35, 0, -30)
			branch.curve.add_point(center, Vector3.ZERO, offset / 3.0)
			branch.curve.add_point(center + offset, -offset / 3.0)
			road.add_child(branch)
	var terrain := TOPOLOGY.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.incremental_generation_enabled = true
	terrain.centered_triangulation_enabled = true
	terrain.local_triangulation_enabled = true
	terrain._local_delaunay.expand_external_ties = not "--strict-ties" in OS.get_cmdline_user_args()
	terrain.road_network_source = NodePath("../Road")
	for child in road.get_children():
		if child is Path3D:
			terrain.source_paths.append(NodePath("../Road/" + child.name))
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(220, 80)
	terrain.manual_size_xz = Vector2(700, 260)
	terrain.far_grid_step = 16
	terrain.near_road_step = 8
	terrain.near_road_width = 8
	terrain.generate_collision = true
	terrain.invert_faces = true
	var strict := "--strict-width" in OS.get_cmdline_user_args()
	if strict:
		terrain._source_cache = StrictWidth.new()
	var reference := TOPOLOGY.new()
	for property: Dictionary in terrain.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			reference.set(property.name, terrain.get(property.name))
	reference.name = "Reference"
	reference.incremental_generation_enabled = false
	scene.add_child(terrain)
	scene.add_child(reference)
	root.add_child(scene)
	_build(terrain)
	var original := path.curve.get_point_position(0)
	var totals: Array[float] = []
	var filtering: Array[float] = []
	var collars: Array[float] = []
	var triangulation: Array[float] = []
	for edit in range(5):
		path.curve.set_point_position(0, original + Vector3(1.5, 0.5, 0) * (edit + 1))
		road.regenerate()
		var intervals: Array = []
		for child in road.get_children():
			if child is Path3D:
				intervals.append([child.curve, child.curve.bake_interval])
		var started := Time.get_ticks_usec()
		_build(terrain)
		totals.append(float(Time.get_ticks_usec() - started) / 1000.0)
		var stats: Dictionary = terrain.get_source_rebuild_stats()
		filtering.append(stats.stage_ms.filter_emit_ms)
		collars.append(stats.stage_ms.collars_ms)
		triangulation.append(stats.stage_ms.get("triangulation_main_ms", 0.0))
		var cavity: RefCounted = terrain._local_delaunay
		var native := preload("../addons/scripts/spline_road/delaunay_geometry.gd").triangulate(cavity._input, true)
		_check(_triangle_set(cavity._output()) == _triangle_set(native),
			"complete unfiltered native triangle set matches retained cavity " + str(edit))
		if cavity.expand_external_ties:
			_check(stats.local_triangulation.fallback.is_empty() and stats.local_triangulation.triangles_reused > 0
				and stats.local_triangulation.triangles_rebuilt > 0,
				"six-road curve edit retains unfiltered triangles without a full fallback")
		var actual := _terrain_geometry(terrain)
		# Native topology reads the pre-bake length. Restore the same incoming
		# shared-curve intervals for the independent reference.
		for entry: Array in intervals:
			entry[0].bake_interval = entry[1]
		_build(reference)
		_check(actual.size() > 1 and actual == _terrain_geometry(reference), "actual terrain mesh and collision match uncached generation " + str(edit))
		if not strict:
			_check(stats.triangle_groups.triangles_reused > 0 and stats.collar_groups.triangles_reused > 0,
				"local certificates retain triangle and collar geometry")
		print("TOPOLOGY_SEARCH_SAMPLE strict=", strict, " edit=", edit, " width=", terrain._road_max_half_width,
			" triangles=", stats.triangle_groups, " collars=", stats.collar_groups)
		print("TOPOLOGY_CAVITY_SAMPLE ", stats.local_triangulation,
			" triangulation_ms=", stats.stage_ms.get("triangulation_main_ms", 0.0))
	for values: Array in [totals, filtering, collars, triangulation]:
		values.sort()
	print("TOPOLOGY_SEARCH_MEDIAN strict=", strict, " total_ms=", totals[2],
		" filter_ms=", filtering[2], " collars_ms=", collars[2], " triangulation_ms=", triangulation[2],
		" strict_ties=", not terrain._local_delaunay.expand_external_ties)
	scene.free()
	print("TOPOLOGY_SEARCH_PROOFS_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _triangle_set(indices: PackedInt32Array) -> Array:
	var result: Array = []
	for index in range(0, indices.size(), 3):
		var triangle := [indices[index], indices[index + 1], indices[index + 2]]
		triangle.sort()
		result.append(str(triangle))
	result.sort()
	return result
