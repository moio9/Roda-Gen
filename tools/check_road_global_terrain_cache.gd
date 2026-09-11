extends "./check_road_terrain_cache.gd"

var _height_tests_complete := false
var _polygon_tests_complete := false


func _run() -> void:
	var road := ROAD.new()
	if "--height-only" in OS.get_cmdline_user_args():
		_test_height_support(road)
		_check(_height_tests_complete, "height helper fixture completes")
		road.free()
		print("GLOBAL_HEIGHT_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
		quit(1 if _failed else 0)
		return
	road.name = "GlobalTerrainCache"
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.output_generate_collision = true
	road.sample_step = 6
	road.terrain_fill_outer_padding = 12
	road.terrain_rect_fill_cell_size = 8
	road.terrain_rect_fill_interior_point_step = 12
	road.terrain_fill_grid_tile_size = 20
	road.terrain_fill_radial_ring_count = 2
	road.terrain_fill_radial_sector_count = 8
	road.terrain_fill_hex_radius = 20
	road.terrain_fill_diamond_tile_size = 20
	road.terrain_fill_adaptive_max_depth = 1
	road.terrain_fill_quadtree_max_depth = 2
	road.terrain_fill_quadtree_min_cell_size = 15
	road.terrain_fill_lod_ring_count = 2
	road.terrain_fill_lod_edge_step_near = 8
	road.terrain_fill_lod_edge_step_far = 16
	road.terrain_fill_delaunay_step_near = 12
	road.terrain_fill_delaunay_step_far = 20
	road.terrain_fill_height_match_max_distance = 12
	road.terrain_fill_base_height = -2
	var first := _path("First", Vector3.ZERO)
	var second := _path("Second", Vector3(70, 1, 0))
	road.add_child(first)
	road.add_child(second)
	# Fixed outer extrema keep grid/radial seed domains stable while an interior
	# road changes. Without these, even a tiny bound shift relocates every tile.
	var bounds := _path("Bounds", Vector3(-50, 0, -30))
	bounds.curve.set_point_position(1, Vector3(-50, 0, 30))
	bounds.curve.set_point_position(2, Vector3(150, 0, 110))
	road.add_child(bounds)
	root.add_child(road)
	if "--benchmark-only" in OS.get_cmdline_user_args():
		road.profile_generation_timings = "--profile" in OS.get_cmdline_user_args()
		if "--dense" in OS.get_cmdline_user_args():
			road.sample_step = 1.0
		_benchmark_global(road, first)
		road.free()
		quit(1 if _failed else 0)
		return
	var local_reuse: Array = []
	for algorithm in [1, 2]:
		for topology in range(12):
			road.terrain_fill_algorithm = algorithm
			road.terrain_fill_topology = topology
			road.clear_source_generation_cache()
			road.regenerate()
			var initial := _geometry(road)
			_check(initial.size() > 1, "global fixture has actual mesh/collision")
			road.regenerate()
			var warm := _stats(road)
			_check(warm.fill_triangles > 0 and warm.strips_rebuilt == 0, "actual global fill, not fallback strips algorithm=%s topology=%s" % [algorithm, topology])
			_check(warm.fill_polygons_reused > 0, "warm polygon source reuse algorithm=%s topology=%s" % [algorithm, topology])
			_check(initial == _geometry(road), "warm exact mesh/collision algorithm=%s topology=%s" % [algorithm, topology])
			first.curve.set_point_position(1, first.curve.get_point_position(1) + Vector3(0.3, 0.1, 0))
			road.regenerate()
			var local := _stats(road)
			if local.fill_polygons_reused > 0 and local.fill_polygons_rebuilt > 0:
				local_reuse.append([algorithm, topology])
			_assert_full_equal(road, "global local edit %s/%s" % [algorithm, topology])
	_check(local_reuse.size() >= 8, "multiple Rectangle and Boolean topologies reuse unaffected polygons after edits")
	road.terrain_fill_algorithm = 1
	road.terrain_fill_topology = 3
	road.terrain_fill_height_assign_only = true
	road.regenerate()
	road.regenerate()
	_check(_stats(road).nearest_queries_reused > 0, "assign-only warm nearest queries are reused")
	first.curve.set_point_position(1, first.curve.get_point_position(1) + Vector3(0.5, 0.2, 0))
	road.regenerate()
	_check(_stats(road).nearest_queries_reused > 0 and _stats(road).nearest_queries_rebuilt > 0, "assign-only local edit keeps unaffected nearest search prefixes")
	_assert_full_equal(road, "assign-only height and local nearest support")
	road.source_paths.assign([NodePath("Second"), NodePath("First"), NodePath("Bounds")])
	road.regenerate()
	_assert_full_equal(road, "global source order and exact-height averaging")
	road.terrain_rect_fill_road_margin = 1.2
	road.regenerate()
	_assert_full_equal(road, "polygon offset and shared-vertex reconstruction")
	road.terrain_fill_height_assign_only = false
	road.terrain_fill_height_match_max_distance = 0
	road.terrain_fill_height_blend_falloff = 0.7
	road.regenerate()
	_assert_full_equal(road, "automatic height radius and weighted falloff")
	road.invert_faces = true
	road.regenerate()
	_assert_full_equal(road, "winding changes do not alter cached polygon inputs")
	_benchmark_global(road, first)
	road.sample_step = 1.0
	_benchmark_global(road, first)
	road.sample_step = 6.0
	await _test_global_worker(road, first)
	_test_height_support(road)
	_test_polygon_immutability(road)
	_check(_height_tests_complete and _polygon_tests_complete, "all helper fixtures completed without an early script return")
	print("GLOBAL_TERRAIN_LOCAL_TOPOLOGIES ", local_reuse)
	road.free()
	print("ROAD_GLOBAL_TERRAIN_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _benchmark_global(road: Node, path: Path3D) -> void:
	road.terrain_fill_algorithm = 1
	road.terrain_fill_topology = 3
	road.terrain_fill_height_match_max_distance = 12
	road.terrain_fill_height_assign_only = false
	var original := path.curve.get_point_position(1)
	var results: Dictionary = {}
	for incremental in [false, true]:
		road.incremental_generation_enabled = incremental
		path.curve.set_point_position(1, original)
		road.clear_source_generation_cache()
		road.regenerate()
		var samples: Array = []
		for i in range(5):
			# Distinct edits cannot hit a retained whole historical road/strip.
			path.curve.set_point_position(1, original + Vector3(0.17 * (i + 1), 0.11 * (i + 1), 0))
			var start := Time.get_ticks_usec()
			road.regenerate()
			samples.append((Time.get_ticks_usec() - start) / 1000.0)
			if incremental:
				var stats := _stats(road)
				_check(stats.fill_polygons_reused > 0 and stats.fill_polygons_rebuilt > 0,
					"timed edit actually rebuilds changed global polygons and reuses unaffected ones")
		samples.sort()
		results["local_ms" if incremental else "full_ms"] = samples[2]
	print("GLOBAL_TERRAIN_DISTINCT_EDIT_MEDIAN sample_step=%s %s" % [road.sample_step, results])
	_assert_full_equal(road, "last distinct benchmark edit")
	path.curve.set_point_position(1, original)


func _test_height_support(road: Node) -> void:
	var builder = road._terrain_builder
	road.incremental_generation_enabled = true
	road.terrain_fill_height_assign_only = true
	road.terrain_fill_height_match_max_distance = 6
	builder.configure(road)
	var points: Array = [Vector3(9, 2, 10), Vector3(11, 5, 10), Vector3(1000, 100, 1000)]
	var point := Vector2(10, 10)
	var lookup: Dictionary = builder._build_boundary_height_lookup(points)
	var old_revisions: Dictionary = lookup._cell_revisions.duplicate()
	var first: Dictionary = builder._find_nearest_boundary_points(point, points, lookup, 2)
	_check(first.y0 == 2 and first.y1 == 5, "nearest fixture has equal-distance source-order tie")
	points[2] = Vector3(1100, 999, 1100)
	lookup = builder._build_boundary_height_lookup(points)
	_check(lookup._cell_revisions.get(Vector2i.ZERO) == old_revisions.get(Vector2i.ZERO),
		"distant edit retains exact local cell revision")
	var reused: int = builder.last_stats.nearest_queries_reused
	_check(builder._find_nearest_boundary_points(point, points, lookup, 2) == first \
		and builder.last_stats.nearest_queries_reused == reused + 1, "distant boundary edit preserves nearest stopping prefix")
	points.push_front(Vector3(10, 20, 10))
	lookup = builder._build_boundary_height_lookup(points)
	var closer: Dictionary = builder._find_nearest_boundary_points(point, points, lookup, 2)
	_check(closer.y0 == 20 and closer == builder._find_nearest_boundary_points_uncached(point, points, lookup, 2), "new closer point invalidates search prefix")
	points.pop_front()
	var swap: Variant = points[0]
	points[0] = points[1]
	points[1] = swap
	lookup = builder._build_boundary_height_lookup(points)
	var tied: Dictionary = builder._find_nearest_boundary_points(point, points, lookup, 2)
	_check(tied.y0 == 5 and tied == builder._find_nearest_boundary_points_uncached(point, points, lookup, 2), "equal-distance reordering invalidates selected height")
	points.pop_back()
	lookup = builder._build_boundary_height_lookup(points)
	var far := Vector2(1000, 1000)
	var fallback: Dictionary = builder._find_nearest_boundary_points(far, points, lookup, 2)
	_check(fallback == builder._find_nearest_boundary_points_uncached(far, points, lookup, 2), "empty grid search uses exact global fallback")
	reused = builder.last_stats.nearest_queries_reused
	_check(builder._find_nearest_boundary_points(far, points, lookup, 2) == fallback \
		and builder.last_stats.nearest_queries_reused == reused + 1, "global fallback skips unchanged full scan")
	points[0] = Vector3(11, 31, 10)
	lookup = builder._build_boundary_height_lookup(points)
	_check(builder._find_nearest_boundary_points(far, points, lookup, 2) == builder._find_nearest_boundary_points_uncached(far, points, lookup, 2),
		"global fallback revision changes with source heights")
	points = [Vector3(9, 2, 10)]
	lookup = builder._build_boundary_height_lookup(points)
	var single: Dictionary = builder._find_nearest_boundary_points(point, points, lookup, 2)
	_check(is_inf(single.d1), "one-point search exhausts its grid domain without a second neighbor")
	points.append(Vector3(100, 9, 10))
	lookup = builder._build_boundary_height_lookup(points)
	var extended: Dictionary = builder._find_nearest_boundary_points(point, points, lookup, 2)
	_check(extended.y1 == 9 and extended == builder._find_nearest_boundary_points_uncached(point, points, lookup, 2),
		"expanded search domain invalidates an exhausted prefix even when its old cells are unchanged")
	points.pop_back()
	lookup = builder._build_boundary_height_lookup(points)
	_check(builder._find_nearest_boundary_points(point, points, lookup, 2) == builder._find_nearest_boundary_points_uncached(point, points, lookup, 2),
		"shrinking a search domain cannot reuse a longer prefix")
	var old_cell_ids: Array = lookup._cell_revisions.values()
	builder._stage_cache.clear()
	lookup = builder._build_boundary_height_lookup(points)
	_check(not old_cell_ids.has(lookup._cell_revisions.values()[0]), "cell revision IDs are not recycled after eviction/clear")
	_check(builder._find_nearest_boundary_points(point, points, lookup, 2) == builder._find_nearest_boundary_points_uncached(point, points, lookup, 2),
		"old nearest hints remain safe after inner stage storage is cleared")
	var external := lookup.duplicate(true)
	external.erase("_cell_revisions")
	_check(builder._find_nearest_boundary_points(point, points, external, 2) == builder._find_nearest_boundary_points_uncached(point, points, external, 2),
		"caller-owned grids bypass revision-dependent nearest cache")
	road.terrain_fill_height_assign_only = false
	builder.configure(road)
	points = [Vector3(1, 10, 0), Vector3(4, 20, 0), Vector3(1000, 100, 1000)]
	lookup = builder._build_boundary_height_lookup(points)
	var height: float = builder._sample_boolean_fill_vertex_height(Vector2.ZERO, {}, points, -2.0, lookup)
	points[2] = Vector3(1200, 999, 1000)
	lookup = builder._build_boundary_height_lookup(points)
	reused = builder.last_stats.fill_heights_reused
	_check(builder._sample_boolean_fill_vertex_height(Vector2.ZERO, {}, points, -2.0, lookup) == height \
		and builder.last_stats.fill_heights_reused == reused + 1, "weighted blend only depends on selected local cells")
	var exact_map := {Vector2i.ZERO: [18.0, 2]}
	_check(builder._sample_boolean_fill_vertex_height(Vector2.ZERO, exact_map, points, -2.0, lookup) == 9.0,
		"exact quantized cell averaging takes priority over an old cached blend")
	points[0] = Vector3(1, 30, 0)
	lookup = builder._build_boundary_height_lookup(points)
	_check(builder._sample_boolean_fill_vertex_height(Vector2.ZERO, {}, points, -2.0, lookup) \
		== builder._sample_boolean_fill_vertex_height_uncached(Vector2.ZERO, {}, points, -2.0, lookup), "weighted local height change invalidates blend")
	points = [Vector3(9, 44, 0), Vector3(10, 55, 0)]
	lookup = builder._build_boundary_height_lookup(points)
	_check(builder._sample_boolean_fill_vertex_height(Vector2.ZERO, {}, points, -2.0, lookup) == 44.0,
		"zero-weight local candidates retain original nearest-any fallback")
	points.push_front(Vector3(8, 66, 0))
	lookup = builder._build_boundary_height_lookup(points)
	_check(builder._sample_boolean_fill_vertex_height(Vector2.ZERO, {}, points, -2.0, lookup) == 66.0,
		"out-of-radius point inside selected cells still invalidates height fallback")
	road.clear_source_generation_cache()
	_check(builder._nearest_probes.is_empty() and builder._height_snapshot.is_empty(), "public cache clear releases nearest probes and revision snapshot")
	_height_tests_complete = true


func _test_global_worker(road: Node, path: Path3D) -> void:
	road.terrain_fill_algorithm = 2
	road.terrain_fill_height_assign_only = true
	road.regenerate()
	road.threaded_generation_enabled = true
	road.regenerate()
	_check(road._is_generation_thread_active(), "global terrain worker is pending")
	_check(_stats(road).get("pending", false), "global stats avoid worker-owned cell and scope Dictionaries")
	road.clear_source_generation_cache()
	path.curve.set_point_tilt(1, 0.31)
	road.regenerate()
	var deadline := Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "global terrain cancellation/clear joins and restarts")
	road.threaded_generation_enabled = false
	road.regenerate()
	_check(road._terrain_builder._stage_cache._dependency_scopes.is_empty(), "global worker leaves no open polygon dependency scopes")
	_assert_full_equal(road, "global worker cancellation and deferred clear")


func _test_polygon_immutability(road: Node) -> void:
	var builder = road._terrain_builder
	builder.configure(road)
	var cache = builder._stage_cache
	var poly := PackedVector2Array([Vector2.ZERO, Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	var clip := PackedVector2Array([Vector2(10, -5), Vector2(25, -5), Vector2(25, 25), Vector2(10, 25)])
	var first: Array = cache.polygon_clip(poly, clip)
	var expected := first.duplicate(true)
	first[0].reverse()
	_check(cache.polygon_clip(poly, clip) == expected, "returned clip polygons cannot mutate cached winding")
	var tri: PackedInt32Array = cache.polygon_triangulate(poly, true)
	var expected_tri := tri.duplicate()
	tri[0] = -999
	_check(cache.polygon_triangulate(poly, true) == expected_tri, "returned Delaunay indices cannot mutate cache")
	var triangles: Array = builder._triangulate_fill_polygon_for_rect_mode(poly, 4.0)
	var expected_triangles := triangles.duplicate(true)
	triangles[0].reverse()
	for i in range(5):
		builder.configure(road)
		_check(builder._triangulate_fill_polygon_for_rect_mode(poly, 4.0) == expected_triangles, "coarse polygon hit remains immutable")
	var native_key: Dictionary = cache.query("geometry_2d/triangulate", [builder._resample_polygon_edges_for_boolean_fill(poly, 4.0), null])
	_check(not cache.lookup(native_key).is_empty(), "polygon replay retains nested native triangulation entries past idle expiry")
	var clipped: Array = builder._clip_fill_parts_by_polygon([poly], clip)
	var expected_clipped := clipped.duplicate(true)
	_check(not clipped.is_empty(), "coarse clipping fixture produces a real polygon")
	clipped[0].reverse()
	for i in range(5):
		builder.configure(road)
		_check(builder._clip_fill_parts_by_polygon([poly], clip) == expected_clipped and builder.last_stats.fill_clips_reused > 0,
			"coarse clipping replay remains immutable and retains its children")
	var cancelled := {"cancelled": true}
	_check(builder._is_generation_cancelled(cancelled), "fixture uses the coordinator's actual cancellation token")
	_check(builder._triangulate_fill_polygon_for_rect_mode(poly, 4.0, cancelled).is_empty(), "cancelled polygon query does not replay geometry")
	_check(builder._clip_fill_parts_by_polygon([poly], clip, cancelled).is_empty(), "cancelled clipping does not replay cached parts")
	_check(cache._dependency_scopes.is_empty(), "cancelled call leaves no open dependency capture")
	_polygon_tests_complete = true
