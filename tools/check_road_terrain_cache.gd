extends SceneTree

const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
var _failed := false
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var road := ROAD.new()
	if "--winding-only" in OS.get_cmdline_user_args():
		_test_winding_snapshot(road)
		road.free()
		quit(1 if _failed else 0)
		return
	road.name = "TerrainCacheRoad"
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.output_generate_collision = true
	road.sample_step = 4.0
	road.terrain_fill_algorithm = 0
	road.terrain_growth_scan_step = 2.0
	road.terrain_adaptive_subdivisions_enabled = false
	road.terrain_subdivisions = 3
	road.terrain_noise_enabled = true
	road.terrain_noise_amplitude = 1.2
	road.terrain_skirt_depth = 3.0
	road.terrain_skirt_soften_area_rings = 8
	road.terrain_skirt_soften_max_drop = 2.0
	var first := _path("First", Vector3.ZERO)
	var far := _path("Far", Vector3(300, 0, 0))
	road.add_child(first)
	road.add_child(far)
	root.add_child(road)
	var cold := _stats(road)
	_check(cold.strips_rebuilt == 2 and cold.vertices_built > 100, "cold cache constructs both strips")
	var initial := _geometry(road)
	road.regenerate()
	var warm := _stats(road)
	_check(warm.strips_reused == 2 and warm.growth_width_queries == 0, "warm strips skip growth and ring construction")
	_check(_geometry(road) == initial, "warm cache preserves exact mesh and collision including skirt softening")
	first.curve.set_point_position(1, Vector3(9, 3, 40))
	road.regenerate()
	var local := _stats(road)
	_check(local.strips_reused == 1 and local.strips_rebuilt == 1, "local road edit retains distant terrain strip")
	_assert_full_equal(road, "local CP edit")
	first.terrain_left_width = 12.0
	road.regenerate()
	_check(_stats(road).strips_reused == 1, "per-path width change retains other strip")
	_assert_full_equal(road, "per-path width override")
	var obstacle := _path("Obstacle", Vector3(1000, 0, 0))
	obstacle.terrain_left_width = 0
	obstacle.terrain_right_width = 0
	road.add_child(obstacle)
	road.regenerate()
	_check(_stats(road).strips_reused == 2, "adding distant path preserves prior strips despite global geometry change")
	_assert_full_equal(road, "distant path addition")
	obstacle.position.x = -986.0
	road.regenerate()
	_check(_stats(road).strips_rebuilt >= 2 and _stats(road).strips_reused == 1, "new nearby road invalidates terrain support")
	_assert_full_equal(road, "nearby road enters growth region")
	obstacle.free()
	road.regenerate()
	_assert_full_equal(road, "nearby road removal")
	road.source_paths = [NodePath("Far"), NodePath("First")]
	road.regenerate()
	_check(_stats(road).strips_reused == 2, "path reorder resolves cached local indices against current vertex offsets")
	_assert_full_equal(road, "path reorder")
	first.curve.add_point(Vector3(15, 0, 110), Vector3(0, 0, -8))
	road.regenerate()
	_assert_full_equal(road, "changed row count")
	first.curve.remove_point(3)
	first.curve.set_point_in(1, Vector3(-8, -2, -10))
	road.regenerate()
	_assert_full_equal(road, "tangent and row removal")
	var changes := {"terrain_chain_smooth_passes": 3, "terrain_skirt_segments": 5,
		"terrain_skirt_soften_area_rings": 1, "terrain_noise_seed": 81,
		"terrain_cut_fill_mode": 1, "terrain_detection_width_scale": 0.4,
		"terrain_road_clearance": 0.6, "terrain_growth_max_delta_per_row": 0.15,
		"terrain_subdivisions": 5, "uv_length_scale": 0.7, "invert_faces": true}
	for property in changes:
		road.set(property, changes[property])
		road.regenerate()
		_check(_stats(road).strips_reused == 0, "global strip setting invalidation: " + property)
		_assert_full_equal(road, property)
	road.terrain_adaptive_subdivisions_enabled = true
	road.terrain_adaptive_subdivisions_per_meter = 0.4
	road.terrain_noise_amplitude = 2.1
	road.regenerate()
	_assert_full_equal(road, "adaptive subdivisions depend on path maximum")
	first.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.05)).scaled(Vector3(-1.3, 0.8, 1.2)), Vector3(4, 2, 5))
	road.transform = Transform3D(Basis.from_euler(Vector3(0, 0.1, 0)).scaled(Vector3(-0.9, 1.1, 1.3)), Vector3(20, 3, 40))
	road.regenerate()
	_assert_full_equal(road, "mirrored and nonuniform transforms")
	# A joining endpoint exercises blocked strip edges and post-weld source data.
	var joining := _path("Joining", Vector3.ZERO)
	joining.curve.set_point_position(0, far.curve.get_point_position(0))
	joining.curve.set_point_position(1, Vector3(320, 0, -30))
	joining.curve.set_point_position(2, Vector3(340, 0, -60))
	road.add_child(joining)
	road.source_paths.append(NodePath("Joining"))
	road.regenerate()
	_assert_full_equal(road, "welded and blocked strip edges")
	joining.free()
	road.source_paths.pop_back()
	road.regenerate()
	_assert_full_equal(road, "junction disappearance")
	road.clear_source_generation_cache()
	_check(road._terrain_builder._strip_cache.is_empty(), "public clear releases terrain cache when idle")
	road.regenerate()
	_check(_stats(road).strips_reused == 0, "cleared terrain cache is cold")
	# Read-only stats and deferred clear must be safe while a worker owns terrain.
	road.threaded_generation_enabled = true
	road.regenerate()
	_check(road._is_generation_thread_active(), "terrain job pending")
	_check(_stats(road).get("pending", false), "stats do not read worker-owned terrain Dictionary")
	road.clear_source_generation_cache()
	first.curve.set_point_tilt(1, 0.3)
	road.regenerate()
	var deadline := Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "cancelled terrain worker joins and regenerates")
	road.threaded_generation_enabled = false
	road.regenerate()
	_assert_full_equal(road, "cache clear during threaded cancellation")
	var full_times: Array[float] = []
	var warm_times: Array[float] = []
	for i in range(5):
		road.incremental_generation_enabled = false
		var started := Time.get_ticks_usec()
		road.regenerate()
		full_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
		road.incremental_generation_enabled = true
		road.regenerate()
		started = Time.get_ticks_usec()
		road.regenerate()
		warm_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	full_times.sort()
	warm_times.sort()
	print("ROAD_TERRAIN_CACHE_TIMING full_total_ms=%s warm_total_ms=%s local=%s" % [full_times[2], warm_times[2], local])
	_test_winding_snapshot(road)
	first.free()
	far.free()
	road.source_paths.clear()
	road.regenerate()
	_check(road._terrain_builder._strip_cache.is_empty(), "empty road releases terrain cache")
	road.free()
	print("ROAD_TERRAIN_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _path(label: String, offset: Vector3) -> Path3D:
	var path := PROFILE.new()
	path.name = label
	path.show_width_preview = false
	path.curve = Curve3D.new()
	path.curve.add_point(offset, Vector3.ZERO, Vector3(0, 0, 10))
	path.curve.add_point(offset + Vector3(6, 2, 40), Vector3(0, 0, -10), Vector3(0, 0, 10))
	path.curve.add_point(offset + Vector3(0, 0, 80), Vector3(0, 0, -10))
	path.shoulder_left_width = 0.7
	path.shoulder_right_width = 0.9
	path.terrain_override_enabled = true
	path.terrain_left_width = 7.0
	path.terrain_right_width = 6.0
	return path


func _stats(road: Node) -> Dictionary:
	return road.get_source_rebuild_stats().get("terrain_strips", {})


func _test_winding_snapshot(road: Node) -> void:
	var previous: bool = road.invert_faces
	road.invert_faces = false
	road._terrain_builder.configure(road)
	var points := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 0, -1)])
	for method in ["_append_quad_indices", "_append_terrain_triangle_indices", "_append_terrain_quad_indices"]:
		var before := PackedInt32Array()
		var after := PackedInt32Array()
		road.invert_faces = false
		if method == "_append_quad_indices":
			road._terrain_builder.call(method, before, 0, 1, 2, 3)
		elif method == "_append_terrain_triangle_indices":
			road._terrain_builder.call(method, before, points, 0, 1, 2)
		else:
			road._terrain_builder.call(method, before, points, 0, 1, 2, 3)
		# Simulate an Inspector edit after worker configuration, without racing
		# scheduling in the test: the in-flight builder must keep its snapshot.
		road.invert_faces = true
		if method == "_append_quad_indices":
			road._terrain_builder.call(method, after, 0, 1, 2, 3)
		elif method == "_append_terrain_triangle_indices":
			road._terrain_builder.call(method, after, points, 0, 1, 2)
		else:
			road._terrain_builder.call(method, after, points, 0, 1, 2, 3)
		_check(not before.is_empty() and before == after, "configured winding snapshot: " + method)
	road.invert_faces = previous


func _assert_full_equal(road: Node, label: String) -> void:
	var actual := _geometry(road)
	road.incremental_generation_enabled = false
	road.regenerate()
	_check(actual == _geometry(road), "full/incremental mesh and collision parity: " + label)
	road.incremental_generation_enabled = true
	road.regenerate()
	var cold := _geometry(road)
	road.regenerate()
	_check(cold == _geometry(road), "immutable warm terrain replay: " + label)


func _geometry(road: Node) -> Array:
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var arrays: Array = []
	for surface in range(mesh.get_surface_count()):
		arrays.append(var_to_bytes(mesh.surface_get_arrays(surface)))
	var shape: ConcavePolygonShape3D = road.get_node("GeneratedSplineRoadWelded/StaticBody3D/CollisionShape3D").shape
	arrays.append(shape.get_faces())
	return arrays


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error(message)
