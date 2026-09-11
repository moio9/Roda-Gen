extends SceneTree

const JUNCTION := preload("../addons/scripts/spline_road/road_junction_builder.gd")
var _failed := false
var _checks := 0


class Configuration extends Node:
	var sample_step := 0.5
	var endpoint_snap_distance := 2.0
	var allow_endpoint_to_midpath := true
	var strip_shoulder_sidewalk_at_intersections := true
	var intersection_strip_length := 0.0
	var incremental_generation_enabled := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := Configuration.new()
	var full := JUNCTION.new()
	var cached := JUNCTION.new()
	_configure(full, source, false)
	_configure(cached, source, true)
	var a := _rows([Vector3(-20, 0, 0), Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(20, 0, 0)], 1)
	var b := _rows([Vector3(0, 0, -20), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(0, 0, 20)], 2)
	for point in [Vector3.ZERO, Vector3(100, 1, 0), Vector3(1, 0, 0), Vector3(1.00000011920929, 0, 0)]:
		for radius in [-1.0, 0.0, 1.0, 1.4142135623730951, 200.0]:
			var expected: int = full._find_nearest_inner_row(a, point, radius)
			_check(cached._find_nearest_inner_row(a, point, radius) == expected, "point cold parity")
			_check(cached._find_nearest_inner_row(a, point, radius) == expected, "point warm parity")
	for radius in [-1.0, 0.0, 1.0, 1.4142135623730951, 200.0]:
		var expected: PackedInt32Array = full._find_nearest_inner_row_pair(a, b, radius)
		_check(cached._find_nearest_inner_row_pair(a, b, radius) == expected, "pair cold parity")
		var returned: PackedInt32Array = cached._find_nearest_inner_row_pair(a, b, radius)
		_check(returned == expected, "pair warm parity")
		if not returned.is_empty():
			returned[0] = 999
		_check(cached._find_nearest_inner_row_pair(a, b, radius) == expected, "caller cannot mutate cached result")
	_check(cached._find_nearest_inner_row(a, Vector3.ZERO, 1.0) == 2, "point ties still select last row")
	_check(cached._find_nearest_inner_row_pair(a, b, 200.0) == PackedInt32Array([2, 2]), "pair ties still select last ordered pair")
	for count in range(3):
		var short_rows: Array[Dictionary] = a.slice(0, count)
		_check(cached._find_nearest_inner_row(short_rows, Vector3.ZERO, 200.0) == -1, "short paths have no inner row")
		_check(cached._find_nearest_inner_row_pair(short_rows, b, 200.0).is_empty(), "short paths have no inner pair")
	# A tiny real position change must miss even when rounded text would collide.
	_configure(cached, source, true)
	cached._find_nearest_inner_row(a, Vector3.ZERO, 200.0)
	a[1]["position"] = Vector3(-1.00000011920929, 0, 0)
	_check(cached._find_nearest_inner_row(a, Vector3.ZERO, 200.0) == full._find_nearest_inner_row(a, Vector3.ZERO, 200.0), "direct queries observe changed support")
	_check(int(cached.last_stats["point_queries_rebuilt"]) == 1, "exact binary position change invalidates prior support")
	# Array ordinals, not stored global row/path IDs, identify the returned rows.
	_configure(cached, source, true)
	cached._find_nearest_inner_row_pair(a, b, 200.0)
	var copied_a: Array[Dictionary] = a.duplicate(true)
	var copied_b: Array[Dictionary] = b.duplicate(true)
	for row in copied_a:
		row["path_id"] = 45
		row["row_idx"] = 991
	_configure(cached, source, true)
	_check(cached._find_nearest_inner_row_pair(copied_a, copied_b, 200.0) == full._find_nearest_inner_row_pair(a, b, 200.0), "fresh arrays and remapped metadata reuse current ordinals")
	_check(int(cached.last_stats["pair_queries_reused"]) == 1 and int(cached.last_stats["distance_tests"]) == 0, "unchanged pair skips every distance test")
	_check(cached._find_nearest_inner_row_pair(copied_b, copied_a, 200.0) == full._find_nearest_inner_row_pair(b, a, 200.0), "ordered pair reversal retains tie semantics")
	_test_discovery(cached, full, source)
	_test_eviction(cached, source)
	_test_timing(cached, full, source)
	_configure(cached, source, false)
	_check(cached._query_cache.is_empty(), "disabling incremental generation releases old entries")
	cached._find_nearest_inner_row_pair(a, b, 200.0)
	cached._find_nearest_inner_row_pair(a, b, 200.0)
	_check(int(cached.last_stats["queries_reused"]) == 0 and int(cached.last_stats["queries_rebuilt"]) == 2, "disabled mode performs every query")
	source.free()
	_test_baseline_enabled()
	if not _failed:
		print("ROAD_JUNCTION_CACHE_OK checks=%d" % _checks)
	quit(1 if _failed else 0)


func _test_discovery(cached: RefCounted, full: RefCounted, source: Node) -> void:
	var paths: Array = [
		_rows([Vector3(-8, 0, 0), Vector3(-4, 0, 0), Vector3.ZERO, Vector3(4, 0, 0), Vector3(8, 0, 0)], 0),
		_rows([Vector3(0, 0, -8), Vector3(0, 0, -4), Vector3.ZERO, Vector3(0, 0, 4), Vector3(0, 0, 8)], 1),
		_rows([Vector3(3, 0, -8), Vector3(3, 0, -4), Vector3(3, 0, 0), Vector3(3, 0, 4), Vector3(3, 0, 8)], 2),
	]
	for step in range(7):
		if step == 2:
			# Only a third path changes. The first path pair must stay cached.
			paths[2][2]["position"] = Vector3(100, 0, 100)
		elif step == 3:
			paths[2][0]["position"] = Vector3.ZERO
		elif step == 4:
			paths[2][0]["position"] = Vector3(200, 0, 200)
		elif step == 5:
			paths[2].remove_at(2)
		elif step == 6:
			paths.remove_at(2)
		_configure(full, source, false)
		_configure(cached, source, true)
		var expected := _discover(full, paths)
		var actual := _discover(cached, paths)
		_check(var_to_bytes(actual) == var_to_bytes(expected), "endpoint/pair augmentation parity step %d" % step)
		_check(int(cached.last_stats["row_snapshots"]) == paths.size(), "each path is captured once before both discovery passes")
		if step == 1:
			_check(int(cached.last_stats["queries_rebuilt"]) == 0 and int(cached.last_stats["distance_tests"]) == 0, "unchanged discovery skips all comparisons")
		if step >= 2:
			_check(int(cached.last_stats["pair_queries_reused"]) >= 1, "unaffected path pair reused after other source changes")
		# Weld mutations concern vertex arrays and irrelevant row metadata, never
		# the frozen discovery positions. Repeated lookup still uses current order.
		paths[0][1]["row_a"] = 123456


func _discover(builder: RefCounted, paths: Array) -> Array[Dictionary]:
	var sockets: Array[Dictionary] = []
	var keys: Dictionary = {}
	var snaps: Array = []
	var allow: Array = []
	for rows_raw in paths:
		var rows: Array[Dictionary] = rows_raw
		snaps.append(2.0)
		allow.append(true)
		if rows.size() >= 2:
			builder._add_socket_unique(sockets, keys, rows[0], true)
			builder._add_socket_unique(sockets, keys, rows[rows.size() - 1], true)
	builder._augment_with_midpath_sockets(sockets, keys, paths, sockets.size(), allow, snaps)
	builder._augment_with_midpath_pair_sockets(sockets, keys, paths, allow, snaps)
	return sockets


func _test_eviction(cached: RefCounted, source: Node) -> void:
	_configure(cached, source, false)
	_configure(cached, source, true)
	var rows := _rows([Vector3.ZERO, Vector3.ONE, Vector3(2, 2, 2)], 0)
	for i in range(JUNCTION.QUERY_CACHE_MAX_ENTRIES + 4):
		cached._find_nearest_inner_row(rows, Vector3(float(i), 0, 0), 1.0)
	_check(cached._query_cache.size() == JUNCTION.QUERY_CACHE_MAX_ENTRIES, "entry count remains bounded within one build")
	_check(int(cached.last_stats["cache_evicted"]) == 4, "deterministic least recently used eviction")
	for _i in range(JUNCTION.QUERY_CACHE_MAX_IDLE_BUILDS + 1):
		_configure(cached, source, true)
	_check(cached._query_cache.is_empty(), "disappeared queries expire after bounded idle builds")


func _test_timing(cached: RefCounted, full: RefCounted, source: Node) -> void:
	var positions_a: Array = []
	var positions_b: Array = []
	for i in range(902):
		positions_a.append(Vector3(float(i), sin(float(i) * 0.07), 0))
	for i in range(1002):
		positions_b.append(Vector3(450, cos(float(i) * 0.11), float(i) - 500))
	var a := _rows(positions_a, 0)
	var b := _rows(positions_b, 1)
	var paths: Array = [a, b]
	_configure(cached, source, false)
	var cold_start := Time.get_ticks_usec()
	_configure(cached, source, true)
	cached._prepare_discovery_row_snapshots(paths)
	var expected: PackedInt32Array = cached._find_nearest_inner_row_pair(a, b, 10.0)
	var cold_usec := Time.get_ticks_usec() - cold_start
	_check(int(cached.last_stats["distance_tests"]) == 900000, "cold pair performs the original search")
	var full_samples: Array[int] = []
	var warm_samples: Array[int] = []
	for _i in range(5):
		var start := Time.get_ticks_usec()
		_configure(full, source, false)
		var full_result: PackedInt32Array = full._find_nearest_inner_row_pair(a, b, 10.0)
		full_samples.append(Time.get_ticks_usec() - start)
		start = Time.get_ticks_usec()
		_configure(cached, source, true)
		cached._prepare_discovery_row_snapshots(paths)
		var warm_result: PackedInt32Array = cached._find_nearest_inner_row_pair(a, b, 10.0)
		warm_samples.append(Time.get_ticks_usec() - start)
		_check(expected == full_result and expected == warm_result, "large pair full/warm exact result")
		_check(int(cached.last_stats["distance_tests"]) == 0, "large warm pair skips 900000 distance calculations")
	full_samples.sort()
	warm_samples.sort()
	print("ROAD_JUNCTION_CACHE_TIMING cold_usec=%d full_median_usec=%d warm_median_usec=%d skipped_distance_tests=900000" % [cold_usec, full_samples[2], warm_samples[2]])


func _test_baseline_enabled() -> void:
	var road_script: Script = load("res://addons/scripts/spline_road/road_network_creator.gd")
	var profile_script: Script = load("res://addons/scripts/spline_road/spline_path_profile.gd")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/road_mesh_baseline.json"))
	for topology in [-1, 0, 2, 3, 8, 11]:
		var road: Node3D = road_script.new()
		road.name = "JunctionCacheBaseline"
		road.threaded_generation_enabled = false
		road.incremental_generation_enabled = true
		road.output_generate_collision = true
		road.debug_generation_logs = false
		road.sample_step = 2.0
		road.road_orientation_mode = 2
		road.shoulder_left_width = 0.5
		road.shoulder_right_width = 0.7
		road.sidewalk_left_width = 0.8
		road.sidewalk_right_width = 0.6
		road.outer_wall_height = 0.5
		road.terrain_left_width = 8.0
		road.terrain_right_width = 8.0
		road.terrain_fill_algorithm = 0 if topology == -1 else 1
		road.terrain_fill_topology = maxi(0, topology)
		road.terrain_rect_fill_cell_size = 8.0
		road.terrain_fill_quadtree_max_depth = 2
		road.terrain_fill_delaunay_step_near = 4.0
		road.terrain_fill_delaunay_step_far = 8.0
		for arm in range(3):
			var path: Path3D = profile_script.new()
			path.name = "Arm%d" % arm
			path.curve = Curve3D.new()
			var angle := TAU * float(arm) / 3.0
			var direction := Vector3(cos(angle), 0, sin(angle))
			path.curve.add_point(Vector3.ZERO, Vector3.ZERO, direction * 8.0)
			path.curve.add_point(direction * 35.0 + Vector3.UP * arm, -direction * 8.0)
			path.point_widths = PackedFloat32Array([6.0, 8.0])
			path.shoulder_left_width = 0.5
			path.shoulder_right_width = 0.7
			path.sidewalk_left_width = 0.8
			path.sidewalk_right_width = 0.6
			path.outer_wall_height = 0.5
			path.terrain_override_enabled = true
			path.terrain_left_width = 8.0
			path.terrain_right_width = 8.0
			road.add_child(path)
			road.source_paths.append(NodePath(path.name))
		root.add_child(road)
		_check(_road_mesh_digest(road) == expected[str(topology)]["sha256"], "enabled cold baseline topology %d" % topology)
		var cold_collision := _road_collision_bytes(road)
		_check(not cold_collision.is_empty(), "baseline has real concave collision faces")
		road.regenerate()
		_check(_road_mesh_digest(road) == expected[str(topology)]["sha256"], "enabled warm baseline topology %d" % topology)
		_check(_road_collision_bytes(road) == cold_collision, "warm collision face parity topology %d" % topology)
		_check(int(road._junction_builder.last_stats["distance_tests"]) == 0 and int(road._junction_builder.last_stats["queries_reused"]) > 0, "actual road reuses discovery topology %d" % topology)
		if topology == -1:
			var branch: Path3D = road.get_node("Arm2")
			for translation in [Vector3(100, 0, 100), Vector3.ZERO]:
				branch.position = translation
				road.regenerate()
				var incremental_digest := _road_mesh_digest(road)
				var incremental_collision := _road_collision_bytes(road)
				road.incremental_generation_enabled = false
				road.regenerate()
				_check(_road_mesh_digest(road) == incremental_digest, "full versus changed/disappearing junction geometry")
				_check(_road_collision_bytes(road) == incremental_collision, "full versus changed/disappearing junction collision faces")
				road.incremental_generation_enabled = true
				road.regenerate()
		road.free()


func _road_mesh_digest(road: Node3D) -> String:
	var generated := road.get_node_or_null("GeneratedSplineRoadWelded") as MeshInstance3D
	if generated == null or generated.mesh == null:
		return "missing"
	var surfaces: Array = []
	for surface in range(generated.mesh.get_surface_count()):
		surfaces.append(generated.mesh.surface_get_arrays(surface))
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(surfaces))
	return digest.finish().hex_encode()


func _road_collision_bytes(node: Node) -> PackedByteArray:
	var out := PackedByteArray()
	if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
		out.append_array(var_to_bytes(node.shape.get_faces()))
	for child in node.get_children():
		out.append_array(_road_collision_bytes(child))
	return out


func _configure(builder: RefCounted, source: Node, enabled: bool) -> void:
	source.incremental_generation_enabled = enabled
	builder.configure(source)


func _rows(positions: Array, path_id: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in range(positions.size()):
		rows.append({"position": positions[i], "path_id": path_id, "row_idx": i, "row_a": i * 6, "row_b": i * 6 + 5, "out_dir": Vector3.FORWARD, "width": 7.0})
	return rows


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("ROAD_JUNCTION_CACHE_FAIL " + message)
