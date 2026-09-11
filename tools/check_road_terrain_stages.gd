extends "./check_road_terrain_cache.gd"


func _run() -> void:
	var road := ROAD.new()
	road.name = "TerrainStages"
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.output_generate_collision = true
	road.sample_step = 4
	road.terrain_growth_scan_step = 3
	road.terrain_subdivisions = 4
	road.terrain_adaptive_subdivisions_enabled = false
	road.terrain_noise_enabled = true
	road.terrain_noise_amplitude = 1.3
	road.terrain_skirt_depth = 2
	road.terrain_skirt_soften_area_rings = 8
	road.terrain_chain_smooth_passes = 3
	road.terrain_skirt_soften_row_smooth_passes = 3
	var path := PROFILE.new()
	path.name = "Long"
	path.show_width_preview = false
	path.terrain_override_enabled = true
	path.terrain_left_width = 8
	path.terrain_right_width = 7
	path.shoulder_left_width = 0.7
	path.shoulder_right_width = 0.7
	path.curve = Curve3D.new()
	for i in range(9):
		path.curve.add_point(Vector3(0, 0, i * 60), Vector3(0, 0, -20), Vector3(0, 0, 20))
	road.add_child(path)
	root.add_child(road)
	var initial := _geometry(road)
	_check(initial.size() > 1, "fixture contains road/terrain mesh and collision")
	for i in range(5):
		road.regenerate()
	_check(_stats(road).stages.entries > 0, "whole-path replay retains nested stages past idle expiry")
	path.curve.set_point_position(4, Vector3(8, 2, 240))
	road.regenerate()
	var local := _stats(road)
	_check(local.strips_reused == 0 and local.strips_rebuilt == 1, "local fixture rebuilds the edited path itself")
	_check_local_stages(local, "interior position")
	_check(_geometry(road) != initial, "edit changes actual geometry")
	_assert_full_equal(road, "all stages after interior edit")
	path.curve.set_point_tilt(4, 0.25)
	road.regenerate()
	_check_local_stages(_stats(road), "banking and post-weld road frame")
	_assert_full_equal(road, "local tilt with chain smoothing halo and skirts")
	path.curve.set_point_position(8, Vector3(0, 0, 500))
	road.regenerate()
	_check_local_stages(_stats(road), "path extension")
	_assert_full_equal(road, "row count and skirt center change")
	var obstacle := _path("Obstacle", Vector3(1000, 0, 120))
	obstacle.terrain_left_width = 0
	obstacle.terrain_right_width = 0
	road.add_child(obstacle)
	road.regenerate()
	obstacle.position.x = -989
	road.regenerate()
	_check(_stats(road).growth_queries_reused > 0 and _stats(road).growth_width_queries > 0,
		"new nearby road preserves unrelated growth queries within edited support")
	_assert_full_equal(road, "nearby blocker and sequential width recovery")
	obstacle.free()
	road.regenerate()
	_assert_full_equal(road, "blocker disappears")
	road.terrain_adaptive_subdivisions_enabled = true
	road.terrain_adaptive_subdivisions_per_meter = 0.8
	road.regenerate()
	_check(_stats(road).ring_rows_reused == 0, "path-wide subdivision maximum invalidates every ring")
	_check(_stats(road).growth_queries_reused > 0, "subdivision change retains independent growth calculation")
	_assert_full_equal(road, "path-wide subdivision maximum")
	road.terrain_noise_seed = 991
	road.regenerate()
	_check(_stats(road).ring_rows_reused == 0, "noise revision invalidates ring samples")
	_check(_stats(road).growth_queries_reused > 0, "noise revision retains width search")
	_assert_full_equal(road, "noise and skirt softening")
	road.clear_source_generation_cache()
	_check(road._terrain_builder._stage_cache._entries.is_empty(), "idle public clear releases stage storage")
	road.regenerate()
	_assert_full_equal(road, "cold stage cache after clear")
	# Compare total synchronous road regeneration, including source, dependency
	# checks, triangle assembly, material surfaces and collision construction.
	road.terrain_adaptive_subdivisions_enabled = false
	var full_times: Array[float] = []
	var local_times: Array[float] = []
	for enabled in [false, true]:
		road.incremental_generation_enabled = enabled
		path.curve.set_point_tilt(4, 0.3)
		road.regenerate()
		for i in range(5):
			# Unique edits: toggling two old states can hit the whole-strip cache
			# and would not measure within-path recalculation at all.
			path.curve.set_point_tilt(4, 0.1 + i * 0.03)
			var start := Time.get_ticks_usec()
			road.regenerate()
			var elapsed := (Time.get_ticks_usec() - start) / 1000.0
			if enabled:
				local_times.append(elapsed)
				_check(_stats(road).strips_reused == 0, "timed edit is not an old whole-strip cache hit")
			else:
				full_times.append(elapsed)
	full_times.sort()
	local_times.sort()
	_check_local_stages(_stats(road), "timed local edits")
	_assert_full_equal(road, "timed terrain edit")
	print("TERRAIN_STAGE_TIMING full_total_ms=%s local_total_ms=%s local=%s" % [full_times[2], local_times[2], local])
	_test_growth_dependencies(road)
	_test_stage_storage()
	road.free()
	print("ROAD_TERRAIN_STAGES_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _check_local_stages(stats: Dictionary, label: String) -> void:
	_check(stats.growth_queries_reused > 0 and stats.growth_width_queries > 0, "local width reuse/rebuild: " + label)
	_check(stats.ring_rows_reused > 0 and stats.ring_rows_rebuilt > 0, "local ring reuse/rebuild: " + label)
	_check(stats.chain_blend_rows_reused > 0 and stats.chain_blend_rows_rebuilt > 0, "local smoothing halos: " + label)
	_check(stats.skirt_blend_rows_reused > 0, "skirt drop smoothing reuse: " + label)
	_check(stats.skirt_columns_reused > 0 and stats.skirt_columns_rebuilt > 0, "skirt columns respect current chain center: " + label)


func _test_growth_dependencies(road: Node) -> void:
	road.incremental_generation_enabled = true
	var builder = road._terrain_builder
	builder.configure(road)
	var verts := PackedVector3Array([Vector3(100, 0, 4), Vector3(110, 0, 4), Vector3.ZERO, Vector3(0, 0, 10),
		Vector3(106, 0, 4), Vector3(116, 0, 4), Vector3(6, 0, 0), Vector3(6, 0, 10)])
	var bases := PackedInt32Array([0, 1, 2, 3])
	var opposite := PackedInt32Array([4, 5, 6, 7])
	var outer_ids := PackedInt32Array([-1, -1, 2, -1])
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3(-8, 0, 0), Vector3.ZERO]
	var args: Array = [verts, verts[3], Vector3.LEFT, 8.0, 2, 3, points, outer_ids, bases, opposite, []]
	var first: float = builder.callv("_limit_terrain_growth_width_for_segment", args)
	_check(first == 8, "unblocked growth fixture reaches full requested width")
	var reused: int = builder.last_stats.growth_queries_reused
	verts[0] = Vector3(101, 0, 4)
	args[0] = verts
	_check(builder.callv("_limit_terrain_growth_width_for_segment", args) == first \
		and builder.last_stats.growth_queries_reused == reused + 1, "distant earlier-edge edit does not invalidate local query")
	verts[0] = Vector3(-12, 0, 5)
	verts[1] = Vector3(-1, 0, 5)
	args[0] = verts
	var crossed: float = builder.callv("_limit_terrain_growth_width_for_segment", args)
	var crossed_full: float = builder.callv("_limit_terrain_growth_width_uncached", args)
	_check(crossed < first and crossed == crossed_full, "earlier own-side edge enters support and invalidates cached width")
	verts[0] = Vector3(100, 0, 4)
	verts[1] = Vector3(110, 0, 4)
	verts[4] = Vector3(-12, 0, 5)
	verts[5] = Vector3(-1, 0, 5)
	args[0] = verts
	_check(builder.callv("_limit_terrain_growth_width_for_segment", args) == builder.callv("_limit_terrain_growth_width_uncached", args),
		"earlier opposite-side edge is also a dependency")
	verts[4] = Vector3(106, 0, 4)
	verts[5] = Vector3(116, 0, 4)
	args[0] = verts
	var tris: Array = []
	builder._append_tri_to_xz_cache(tris, Vector3(-20, 0, 3), Vector3(10, 0, 3), Vector3(-20, 0, 8))
	builder._append_tri_to_xz_cache(tris, Vector3(10, 0, 3), Vector3(10, 0, 8), Vector3(-20, 0, 8))
	args[10] = tris
	var blocked: float = builder.callv("_limit_terrain_growth_width_for_segment", args)
	_check(blocked < first and blocked == builder.callv("_limit_terrain_growth_width_uncached", args), "nearby road-triangle insertion invalidates cached growth")
	args[10] = []
	points[2] = Vector3(-0.01, 0, 0)
	args[6] = points
	args[3] = 0.3
	_check(builder.callv("_limit_terrain_growth_width_for_segment", args) == builder.callv("_limit_terrain_growth_width_uncached", args),
		"incoming accepted outer point and recovered requested width are dependencies")


func _test_stage_storage() -> void:
	var cache = preload("../addons/scripts/spline_road/terrain_stage_cache.gd").new()
	cache.configure(true, false)
	var first: Dictionary = cache.query("fixture", [1])
	cache.lookup(first)
	cache.store(first, 2.0)
	var collision: Dictionary = cache.query("fixture", [3])
	collision.key = first.key
	_check(cache.lookup(collision).is_empty(), "hash collision still requires exact input bytes")
	var retained := cache.group_keys()
	for i in range(5):
		cache.configure(true, false)
		cache.touch_group(retained)
	_check(not cache.lookup(first).is_empty(), "whole-strip use retains stage entries")
	for i in range(3):
		cache.configure(true, false)
	_check(cache._entries.is_empty(), "unused stage entries expire after two idle builds")
	for i in range(cache.MAX_ENTRIES + 3):
		var query: Dictionary = cache.query("bounded", [i])
		cache.store(query, float(i))
	_check(cache.stats.entries == cache.MAX_ENTRIES and cache.stats.evicted >= 3 \
		and cache.stats.payload_bytes <= cache.MAX_PAYLOAD_BYTES, "stage cache enforces entry/payload limits")
	cache.configure(true, true)
	_check(cache._entries.is_empty() and cache.stats.payload_bytes == 0, "deferred clear consumed during safe configuration")
