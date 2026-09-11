extends "./check_road_terrain_cache.gd"

const CACHE = preload("../addons/scripts/spline_road/road_junction_geometry_cache.gd")


func _run() -> void:
	_test_remap_order()
	_test_cache_lifecycle()
	var road := _make_fans()
	root.add_child(road)
	var cold := _junction_stats(road)
	_check(cold.clusters_rebuilt == 2, "two separated junction fans are built")
	_check(cold.side_pairs_tested == 0, "fan fixture does not silently select midpoint welds")
	for entry in road._junction_builder.geometry_cache._entries.values():
		_check(entry.extra_vertices.size() == 1, "fan payload contains its generated center vertex")
	var initial := _geometry(road)
	road.regenerate()
	_check(_junction_stats(road).clusters_reused == 2 and _junction_stats(road).clusters_rebuilt == 0, "unchanged fan geometry is actually skipped")
	_check(initial == _geometry(road), "warm fan mesh and collision match original")
	var path: Path3D = road.get_node("Fan0Arm0")
	path.curve.set_point_position(0, Vector3(0.4, 0.2, 0))
	road.regenerate()
	var local := _junction_stats(road)
	_check(local.clusters_rebuilt == 1 and local.clusters_reused == 1, "local edit preserves the other junction geometry")
	_assert_full_equal(road, "one edited fan and one retained fan")
	# An unrelated sidewalk changes the original global fan surface-routing rule.
	var extra := _line("Extra", [Vector3(500, 0, 0), Vector3(530, 0, 0)])
	extra.sidewalk_left_width = 1.0
	road.add_child(extra)
	road.regenerate()
	_check(_junction_stats(road).clusters_rebuilt == 2, "global fan material/surface routing is included")
	_assert_full_equal(road, "unrelated sidewalk added")
	extra.free()
	road.regenerate()
	_assert_full_equal(road, "unrelated sidewalk removed")
	road.source_paths.clear()
	for i in [3, 4, 5, 0, 1, 2]:
		road.source_paths.append(NodePath("Fan%dArm%d" % [i / 3, i % 3]))
	road.regenerate()
	_check(_junction_stats(road).clusters_reused == 2, "cluster order/path rebase maps local vertices to current global offsets")
	_assert_full_equal(road, "reordered fan paths")
	var values := {"invert_faces": true, "intersection_strip_length": 0.0,
		"strip_shoulder_sidewalk_at_intersections": false, "endpoint_snap_distance": 3.0}
	for property in values:
		road.set(property, values[property])
		road.regenerate()
		_assert_full_equal(road, property)
	road.strip_shoulder_sidewalk_at_intersections = true
	road.intersection_strip_length = 6.0
	path.curve.add_point(Vector3(90, 8, 0), Vector3(-10, 0, 0))
	road.regenerate()
	_assert_full_equal(road, "changed source row count")
	path.transform = Transform3D(Basis.from_euler(Vector3(0.03, 0, 0.02)).scaled(Vector3(1.05, 0.9, 1.1)), Vector3.ZERO)
	road.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.04)).scaled(Vector3(-1.1, 0.8, 1.3)), Vector3(20, 5, 10))
	road.regenerate()
	_assert_full_equal(road, "banked nonuniform mirrored creator")
	# One fan becomes a two-endpoint weld, then disappears completely.
	var removed: Node = road.get_node("Fan0Arm2")
	road.source_paths.erase(NodePath(removed.name))
	removed.free()
	road.regenerate()
	_assert_full_equal(road, "fan becomes a pair")
	path.position = Vector3(80, 0, 40)
	road.regenerate()
	_assert_full_equal(road, "junction removed without stale patches")
	road.clear_source_generation_cache()
	_check(road._junction_builder.geometry_cache._entries.is_empty(), "public clear drops geometry entries")
	road.regenerate()
	_check(_junction_stats(road).clusters_reused == 0, "geometry cache is cold after clear")
	road.free()
	_test_midpaths()
	_test_global_fallback()
	print("ROAD_JUNCTION_GEOMETRY_%s checks=%s local=%s" % ["FAILED" if _failed else "OK", _checks, local])
	quit(1 if _failed else 0)


func _make_fans() -> Node3D:
	var road := _road()
	road.allow_endpoint_to_midpath = false
	for fan in range(2):
		var center := Vector3(fan * 220.0, 0, 0)
		for arm in range(3):
			var direction := Vector3(cos(arm * TAU / 3.0), 0, sin(arm * TAU / 3.0))
			road.add_child(_line("Fan%dArm%d" % [fan, arm], [center, center + direction * 55 + Vector3.UP * arm]))
	return road


func _road() -> Node3D:
	var road := ROAD.new()
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.auto_regenerate_in_editor = false
	road.incremental_generation_enabled = true
	road.output_generate_collision = true
	road.road_orientation_mode = 2
	road.sample_step = 2.0
	road.intersection_strip_length = 6.0
	road.adaptive_sampling_enabled = false
	return road


func _line(label: String, points: Array) -> Path3D:
	var path := PROFILE.new()
	path.name = label
	path.show_width_preview = false
	path.shoulder_left_width = 0.5
	path.shoulder_right_width = 0.7
	path.curve = Curve3D.new()
	for i in range(points.size()):
		var before: Vector3 = points[i] - points[maxi(0, i - 1)]
		var after: Vector3 = points[mini(points.size() - 1, i + 1)] - points[i]
		path.curve.add_point(points[i], -before / 3.0, after / 3.0)
	return path


func _junction_stats(road: Node) -> Dictionary:
	return road.get_source_rebuild_stats().junction_geometry


func _test_midpaths() -> void:
	var road := _road()
	road.sample_step = 1.0
	road.endpoint_snap_distance = 0.4
	var main := _line("Main", [Vector3(-50, 0, 0), Vector3.ZERO, Vector3(50, 0, 0)])
	var branch0 := _line("Branch0", [Vector3.ZERO, Vector3(0, 0, 25)])
	var branch1 := _line("Branch1", [Vector3(1, 0, 0), Vector3(1, 0, 25)])
	road.add_child(main)
	road.add_child(branch0)
	road.add_child(branch1)
	road.add_child(_line("FarA", [Vector3(200, 0, 0), Vector3(220, 0, 0)]))
	road.add_child(_line("FarB", [Vector3(200, 0, 0), Vector3(180, 0, 0)]))
	root.add_child(road)
	_check(_junction_stats(road).side_pairs_tested > 0, "midpoint fixture exercises whole target-side search")
	var initial := _geometry(road)
	road.regenerate()
	_check(_junction_stats(road).clusters_rebuilt == 0 and _junction_stats(road).clusters_reused >= 3, "overlapping midpoint and endpoint pairs are cached")
	_check(_junction_stats(road).side_pairs_tested == 0, "cached midpoint weld skips side-pair search")
	_check(_geometry(road) == initial, "ordered overlapping strip patches and remaps reproduce full output")
	_assert_full_equal(road, "two adjacent T junctions with overlapping strips")
	branch0.curve.set_point_position(0, Vector3(-0.2, 0.1, 0))
	road.regenerate()
	_check(_junction_stats(road).clusters_reused >= 1 and _junction_stats(road).clusters_rebuilt >= 1, "midpoint edit retains distant pair")
	_assert_full_equal(road, "changed predecessor strip and target geometry")
	# Moving a far control point can create a better candidate far along the side.
	main.curve.set_point_position(2, Vector3(0.2, 0, 1.0))
	road.regenerate()
	_assert_full_equal(road, "new remote target-side competitor")
	main.curve.set_point_position(2, Vector3(50, 0, 0))
	branch0.free()
	road.regenerate()
	_assert_full_equal(road, "removing preceding overlapping junction")
	road.terrain_left_width = 3
	road.terrain_right_width = 3
	road.terrain_growth_scan_step = 2
	main.terrain_override_enabled = true
	main.terrain_left_width = 4
	main.terrain_right_width = 4
	main.sidewalk_left_width = 0.8
	road.regenerate()
	_assert_full_equal(road, "cached weld feeds terrain and blocked-side routing")
	road.markings_enabled = true
	road.regenerate()
	var exclusions: Dictionary = road._marking_exclusions.duplicate(true)
	road.regenerate()
	_check(exclusions == road._marking_exclusions, "marking exclusions are refreshed on a geometry hit")
	_assert_full_equal(road, "paint-compatible midpoint geometry")
	var full_times: Array[float] = []
	var cached_times: Array[float] = []
	for i in range(5):
		road.incremental_generation_enabled = false
		road.regenerate()
		full_times.append(_junction_stats(road).geometry_ms)
		road.incremental_generation_enabled = true
		road.regenerate()
		road.regenerate()
		cached_times.append(_junction_stats(road).geometry_ms)
	full_times.sort()
	cached_times.sort()
	print("ROAD_JUNCTION_GEOMETRY_TIMING full_weld_ms=%s warm_weld_ms=%s warm=%s" % [full_times[2], cached_times[2], _junction_stats(road)])
	road.free()


func _test_global_fallback() -> void:
	var road := _road()
	road.endpoint_snap_distance = 1.0
	road.allow_endpoint_to_midpath = false
	road.add_child(_line("A", [Vector3.ZERO, Vector3(-25, 0, 0)]))
	road.add_child(_line("B", [Vector3(2, 0, 0), Vector3(27, 0, 0)]))
	root.add_child(road)
	road.regenerate()
	_check(_junction_stats(road).clusters_reused == 1, "2.5x fallback junction is cached")
	var c := _line("C", [Vector3(100, 0, 0), Vector3(125, 0, 0)])
	var d := _line("D", [Vector3(100, 0, 0), Vector3(75, 0, 0)])
	road.add_child(c)
	road.add_child(d)
	road.regenerate()
	_assert_full_equal(road, "a normal cluster suppresses global fallback junction")
	c.free()
	d.free()
	road.regenerate()
	_assert_full_equal(road, "global fallback returns after removing normal cluster")
	road.free()


func _test_remap_order() -> void:
	var cache := CACHE.new()
	var ids := PackedInt32Array([10, 30, 50, 70, 90])
	var special := cache.compose_remaps(PackedInt32Array([1, 2, 0, 1]), ids)
	_check(special[10] == 30 and special[30] == 50, "substitutions are ordered rather than transitive")
	var rng := RandomNumberGenerator.new()
	rng.seed = 419
	for attempt in range(100):
		var operations := PackedInt32Array()
		var expected := ids.duplicate()
		for operation in range(20):
			var from := rng.randi_range(0, ids.size() - 1)
			var to := rng.randi_range(0, ids.size() - 1)
			operations.append(from)
			operations.append(to)
			for i in range(expected.size()):
				if expected[i] == ids[from]:
					expected[i] = ids[to]
		var composed := cache.compose_remaps(operations, ids)
		var actual := ids.duplicate()
		for i in range(actual.size()):
			actual[i] = composed.get(actual[i], actual[i])
		_check(actual == expected, "composed remap matches sequential reference %s" % attempt)


func _test_cache_lifecycle() -> void:
	var cache := CACHE.new()
	cache.begin_build(true)
	var positions := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO])
	var surfaces := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var query: Dictionary
	for i in range(CACHE.MAX_ENTRIES + 3):
		query = {"key": str(i), "input": var_to_bytes(i), "ids": PackedInt32Array([0]),
			"local_ids": {0: 0}, "positions": positions.duplicate(), "normals": normals.duplicate(),
			"uvs": uvs.duplicate(), "vertex_start": 1}
		cache.start_recording(query)
		cache.store_patch(query, positions, normals, uvs, surfaces, PackedInt32Array([0, 0, 0]))
	_check(cache._entries.size() == CACHE.MAX_ENTRIES and cache.last_stats.cache_evicted == 3, "geometry cache has a bounded entry count")
	_check(cache.last_stats.cache_payload_bytes > 0, "geometry cache accounts for stored payload")
	query.input = var_to_bytes(-1)
	_check(not cache.replay(query, positions, normals, uvs, surfaces, {}), "matching lookup key does not bypass exact input comparison")
	for i in range(CACHE.MAX_IDLE_BUILDS + 1):
		cache.begin_build(true)
	_check(cache._entries.is_empty() and cache.last_stats.cache_payload_bytes == 0, "unused junctions expire without retaining geometry")
	cache.begin_build(false)
	_check(not cache.enabled and cache._entries.is_empty(), "disabled geometry cache retains no entries")
