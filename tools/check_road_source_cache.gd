extends SceneTree

const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
const CUSTOM = preload("./fixtures/cache_custom_path.gd")
var _failed := false
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var road := ROAD.new()
	road.name = "SourceCacheRoad"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.adaptive_sampling_enabled = false
	road.incremental_generation_enabled = true
	road.output_generate_collision = true
	road.sample_step = 1.0
	road.markings_enabled = true
	var path := _path("Route", 9, Vector3.ZERO)
	var other := _path("UnchangedRoute", 4, Vector3(500, 0, 0))
	road.add_child(path)
	road.add_child(other)
	root.add_child(road)
	var cold: Dictionary = road.get_source_rebuild_stats()
	_check(cold.rows_rebuilt > 300 and cold.rows_reused == 0, "cold cache constructs source rows")
	var initial := _geometry(road)
	road.regenerate()
	var warm: Dictionary = road.get_source_rebuild_stats()
	_check(warm.rows_rebuilt == 0 and warm.paths_reused == 2, "unchanged paths skip all source row construction")
	_check(warm.junction_search.distance_tests == 0, "unchanged junction queries skip distance tests")
	_check(_geometry(road) == initial, "warm pre-weld cache does not retain mutations")
	var local_stats: Dictionary
	for mode in range(3):
		road.road_orientation_mode = mode
		road.regenerate()
		path.curve.set_point_position(5, path.curve.get_point_position(5) + Vector3(2, 1, 0))
		var local_start := Time.get_ticks_usec()
		road.regenerate()
		local_stats = road.get_source_rebuild_stats()
		local_stats["total_ms"] = float(Time.get_ticks_usec() - local_start) / 1000.0
		_check(local_stats.paths_reused == 1, "other path skips source construction after CP edit")
		_check(local_stats.blocks_rebuilt > 0 and local_stats.blocks_reused > 0, "CP edit reuses unaffected blocks in orientation %s" % mode)
		_assert_full_equal(road, "middle CP / orientation %s" % mode)
		for index in [0, 8]:
			path.curve.set_point_position(index, path.curve.get_point_position(index) + Vector3(1, 0.5, 2))
			road.regenerate()
			_assert_full_equal(road, "end CP %s / orientation %s" % [index, mode])
		path.curve.set_point_out(4, path.curve.get_point_out(4) + Vector3(3, -1, 0))
		road.regenerate()
		_assert_full_equal(road, "outgoing tangent / orientation %s" % mode)
		path.curve.set_point_in(4, path.curve.get_point_in(4) + Vector3(-2, 1, 0))
		road.regenerate()
		_assert_full_equal(road, "incoming tangent / orientation %s" % mode)
		path.curve.set_point_tilt(5, path.curve.get_point_tilt(5) + 0.15)
		road.regenerate()
		_assert_full_equal(road, "tilt / orientation %s" % mode)
	# Directional transition data is local, but includes actual Curve resource data.
	path.lane_profile_enabled = true
	path.point_lanes_left = PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1, 1])
	path.point_lanes_right = PackedInt32Array([1, 1, 2, 2, 2, 1, 1, 1, 1])
	path.point_lane_widths = PackedFloat32Array([3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5])
	path.point_lane_transition_lengths = PackedFloat32Array([0, 20, 30, 0, 0, 25, 0, 0, 0])
	path.point_lane_transition_curves.resize(9)
	var ease := Curve.new()
	ease.add_point(Vector2.ZERO)
	ease.add_point(Vector2.ONE)
	path.point_lane_transition_curves[2] = ease
	path.rebuild_lane_dependents()
	road.regenerate()
	path.point_lanes_right[5] = 2
	path.point_lane_widths[4] = 3.8
	road.regenerate()
	_assert_full_equal(road, "asymmetric lane counts/widths")
	ease.set_point_right_tangent(0, 2.0)
	road.regenerate()
	_assert_full_equal(road, "transition Curve edited in place")
	path.point_lane_transition_lengths[5] = 35
	road.regenerate()
	_assert_full_equal(road, "transition distance")
	ease.bake_resolution = 32
	road.regenerate()
	_assert_full_equal(road, "transition bake resolution")
	path.curve.set_point_position(6, path.curve.get_point_position(6) + Vector3(-4, 2, 1))
	road.regenerate()
	_assert_full_equal(road, "control offsets after lane-profile CP edit")
	path.lane_profile_enabled = false
	road.regenerate()
	path.point_lanes_right[4] = 4
	ease.set_point_right_tangent(0, 1.5)
	road.regenerate()
	_assert_full_equal(road, "disabled-lane marking metadata changes")
	path.point_widths = PackedFloat32Array([5, 6, 7, 8, 6, 5, 7, 8, 9])
	road.regenerate()
	path.curve.set_point_position(8, path.curve.get_point_position(8) + Vector3(0, 0, 20))
	road.regenerate()
	_assert_full_equal(road, "legacy widths depend on total length")
	path.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.15, 0.05)).scaled(Vector3(-1.2, 0.9, 1.1)), Vector3(12, 3, 5))
	road.regenerate()
	_assert_full_equal(road, "mirrored nonuniform source transform")
	road.rotation = Vector3(0.12, 0.2, 0.03)
	road.regenerate()
	_assert_full_equal(road, "creator world-up transform")
	path.transform = Transform3D.IDENTITY
	road.rotation = Vector3.ZERO
	road.adaptive_sampling_enabled = true
	road.regenerate()
	other.curve.set_point_position(0, path.curve.get_point_position(4))
	road.regenerate()
	_assert_full_equal(road, "nearby endpoint changes adaptive anchors/junctions")
	other.curve.set_point_position(0, Vector3(500, 0, 0))
	road.regenerate()
	_assert_full_equal(road, "junction disappears")
	road.move_child(other, 0)
	road.regenerate()
	_assert_full_equal(road, "path order changes global vertex/socket offsets")
	path.curve.add_point(Vector3(30, 4, 170), Vector3(0, 0, -10), Vector3(0, 0, 10), 4)
	road.regenerate()
	_assert_full_equal(road, "control point insertion")
	path.curve.remove_point(4)
	road.regenerate()
	_assert_full_equal(road, "control point removal")
	path.curve.closed = true
	road.regenerate()
	_assert_full_equal(road, "closed curve")
	path.curve.closed = false
	var removed_id := other.get_instance_id()
	other.free()
	road.regenerate()
	_check(not road._path_sampler._source_cache._paths.has(removed_id), "removed paths are evicted")
	_assert_full_equal(road, "path removal")
	road.road_orientation_mode = 1
	path.curve.up_vector_enabled = false
	road.regenerate()
	_assert_full_equal(road, "up vector flag with World Up")
	path.curve.up_vector_enabled = true
	path.shoulder_left_width = 0.8
	path.sidewalk_height = 0.18
	path.terrain_override_enabled = true
	path.terrain_left_width = 0.3
	path.terrain_right_width = 0.4
	road.regenerate()
	_assert_full_equal(road, "edge and terrain overrides")
	var custom := CUSTOM.new()
	custom.name = "DynamicWidth"
	custom.curve = Curve3D.new()
	custom.curve.add_point(Vector3(600, 0, 0))
	custom.curve.add_point(Vector3(600, 0, 30))
	road.add_child(custom)
	road.regenerate()
	custom.width_queries = 0
	custom.dynamic_width = 11.0
	road.regenerate()
	_check(custom.width_queries > 0 and road.get_source_rebuild_stats().uncacheable_paths == 1, "custom width providers bypass caching")
	_assert_full_equal(road, "dynamic custom width provider")
	custom.free()
	path.terrain_override_enabled = false
	path.outer_wall_height = 0.3
	road.threaded_generation_enabled = true
	road.regenerate()
	_check(road._is_generation_thread_active(), "source cache feeds a pending worker")
	path.curve.set_point_position(5, path.curve.get_point_position(5) + Vector3(2, 1, 0))
	road.regenerate()
	var deadline := Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "cancelled cached-source worker is replaced and joined")
	road.threaded_generation_enabled = false
	road.regenerate()
	_assert_full_equal(road, "cached source survives worker cancellation")
	path.outer_wall_height = 0.0
	road.adaptive_sampling_enabled = false
	path.point_widths.fill(6.0)
	road.regenerate()
	var full_times: Array[float] = []
	var cached_times: Array[float] = []
	var full_total_times: Array[float] = []
	var cached_total_times: Array[float] = []
	for i in range(5):
		road.incremental_generation_enabled = false
		var full_start := Time.get_ticks_usec()
		road.regenerate()
		full_total_times.append(float(Time.get_ticks_usec() - full_start) / 1000.0)
		full_times.append(road.get_source_rebuild_stats().source_ms)
		road.incremental_generation_enabled = true
		road.regenerate()
		var warm_start := Time.get_ticks_usec()
		road.regenerate()
		cached_total_times.append(float(Time.get_ticks_usec() - warm_start) / 1000.0)
		cached_times.append(road.get_source_rebuild_stats().source_ms)
	full_times.sort()
	cached_times.sort()
	full_total_times.sort()
	cached_total_times.sort()
	print("ROAD_SOURCE_CACHE_TIMING full_source_ms=%s warm_source_ms=%s full_total_ms=%s warm_total_ms=%s" % [full_times[2], cached_times[2], full_total_times[2], cached_total_times[2]])
	print("ROAD_SOURCE_CACHE_LOCAL ", local_stats)
	path.free()
	road.regenerate()
	_check(road._path_sampler._source_cache._paths.is_empty(), "empty generator releases source cache")
	road.free()
	print("ROAD_SOURCE_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _path(label: String, count: int, offset: Vector3) -> Path3D:
	var path := PROFILE.new()
	path.name = label
	path.show_width_preview = false
	path.curve = Curve3D.new()
	for i in range(count):
		var point := offset + Vector3(sin(float(i) * 0.5) * 20, sin(float(i) * 0.8) * 3, i * 45.0)
		path.curve.add_point(point, Vector3(0, 0, -12) if i > 0 else Vector3.ZERO, Vector3(0, 0, 12) if i < count - 1 else Vector3.ZERO)
		path.curve.set_point_tilt(i, sin(float(i)) * 0.12)
	path.shoulder_left_width = 0.5
	path.shoulder_right_width = 0.7
	path.sidewalk_left_width = 0.8
	path.sidewalk_height = 0.15
	return path


func _assert_full_equal(road: Node, label: String) -> void:
	var actual := _geometry(road)
	road.incremental_generation_enabled = false
	road.regenerate()
	_check(actual == _geometry(road), "full versus incremental mesh/paint/collision equality: " + label)
	road.incremental_generation_enabled = true
	road.regenerate()
	var cold := _geometry(road)
	road.regenerate()
	_check(cold == _geometry(road), "warm source cache remains immutable: " + label)


func _geometry(road: Node) -> Array:
	# Include exact sampled metadata, not only the subset current paint consumes.
	var result: Array = [var_to_bytes(road._marking_rows)]
	for name in ["GeneratedSplineRoadWelded", "GeneratedRoadMarkings"]:
		var node := road.get_node_or_null(NodePath(name)) as MeshInstance3D
		if node == null or node.mesh == null:
			result.append(null)
			continue
		for surface in range(node.mesh.get_surface_count()):
			result.append(var_to_bytes(node.mesh.surface_get_arrays(surface)))
			var material := node.mesh.surface_get_material(surface) as BaseMaterial3D
			result.append(material.albedo_color if material != null else Color())
	var collision := road.get_node_or_null("GeneratedSplineRoadWelded/StaticBody3D/CollisionShape3D") as CollisionShape3D
	result.append(collision.shape.get_faces() if collision != null else PackedVector3Array())
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error(message)
