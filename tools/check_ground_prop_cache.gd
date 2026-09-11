extends "./check_prop_source_cache.gd"

const TERRAIN = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.road_orientation_mode = 1
	road.sample_step = 6
	scene.add_child(road)
	var first := PROFILE.new()
	first.name = "Long"
	first.show_width_preview = false
	first.curve = Curve3D.new()
	for i in range(9):
		var height := 20.0 if i % 4 >= 2 else 0.0
		first.curve.add_point(Vector3(0, height, i * 60), Vector3(0, 0, -20), Vector3(0, 0, 20))
	road.add_child(first)
	var second := _path("Other", Vector3(150, 5, 0))
	road.add_child(second)
	var terrain := TERRAIN.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.incremental_generation_enabled = true
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/Long"), NodePath("../Road/Other")])
	terrain.adaptive_path_sampling = false
	terrain.path_sample_step = 8
	terrain.near_road_width = 6
	terrain.near_road_step = 16
	terrain.far_grid_step = 32
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(60, 240)
	terrain.manual_size_xz = Vector2(260, 560)
	terrain.left_profile_distances = PackedFloat32Array([0, 40])
	terrain.right_profile_distances = PackedFloat32Array([0, 40])
	terrain.left_profile_heights = PackedFloat32Array([0, 0])
	terrain.right_profile_heights = PackedFloat32Array([0, 0])
	terrain.noise_enabled = false
	scene.add_child(terrain)
	_build_terrain(terrain)
	var props := PROPS.new()
	props.name = "Props"
	props.auto_regenerate_in_editor = false
	props.road_network_source = NodePath("../Road")
	props.terrain_height_source = NodePath("../Terrain")
	props.source_paths.assign([NodePath("../Road/Long"), NodePath("../Road/Other")])
	props.item_mesh = BoxMesh.new()
	props.ranges_mode = 0
	props.avoid_intersections = false
	props.placement_mode = 3
	props.spacing = 2
	props.outward_offset = 3
	props.snap_to_ground_enabled = true
	props.snap_to_ground_max_angle_deg = 12
	props.snap_to_ground_slope_mode = 1
	props.longitudinal_jitter = 0.4
	props.lateral_jitter = 0.2
	props.yaw_jitter_degrees = 15
	props.random_uniform_scale_min = 0.8
	props.random_uniform_scale_max = 1.2
	scene.add_child(props)
	if "--profile-ground" in OS.get_cmdline_user_args():
		_profile_ground_queries(terrain, props, first)
		scene.free()
		quit(1 if _failed else 0)
		return
	_check(not _snapshot(props).is_empty(), "real ground-snapped mesh props exist")
	var entry: Dictionary = props._placement_cache.previous(first)
	_check(not entry.is_empty() and entry.blocks.size() > 4, "ground placements use actual source blocks")
	var accepted := 0
	var steep := 0
	for query: Array in entry.get("ground_queries", []):
		accepted += int(query[1].get("within_max_angle", false))
		steep += int(query[1].get("hit", false) and not query[1].get("within_max_angle", false))
	_check(accepted > 0 and steep > 0, "fixture exercises valid and clamped steep terrain")
	var original := _snapshot(props)
	props.regenerate()
	var warm: Dictionary = props.get_placement_rebuild_stats()
	_check(warm.paths_reused == 2 and warm.sampling_steps == 0 and warm.ground_queries_checked > 0,
		"whole-path replay validates terrain hits without running placement loops")
	_check(_snapshot(props) == original, "warm ground props are identical")
	_assert_full_equal(road, props, "warm clamp-last-valid ground")
	first.curve.set_point_position(4, first.curve.get_point_position(4) + Vector3(2, 3, 0))
	_build_terrain(terrain)
	props.regenerate()
	var local: Dictionary = props.get_placement_rebuild_stats()
	_check(local.blocks_reused > 0 and local.blocks_rebuilt > 0, "ground edit reuses and rebuilds placement blocks")
	_assert_full_equal(road, props, "local edit with per-side clamp state and downstream RNG")
	print("GROUND_PROP_LOCAL ", local)
	for mode in [0, 1]:
		props.snap_to_ground_slope_mode = mode
		props.regenerate()
		_assert_full_equal(road, props, "slope mode %s" % mode)
	terrain.noise_enabled = true
	terrain.noise_start_distance_from_road = 0
	terrain.noise_fade_distance = 1
	terrain.noise_amplitude = 4
	_build_terrain(terrain)
	props.regenerate()
	_assert_full_equal(road, props, "terrain-only noise edit")
	props.snap_to_ground_y_offset = 1.5
	props.regenerate()
	_assert_full_equal(road, props, "snap offset edit")
	var before_terrain_only := _snapshot(props)
	terrain.y_offset += 2
	_build_terrain(terrain)
	_check(props.get_placement_rebuild_stats().pending_terrain, "terrain-only completion schedules dependent props")
	props._process(0)
	_check(_snapshot(props) != before_terrain_only, "terrain-only change moves actual props without a manual prop rebuild")
	_assert_full_equal(road, props, "automatic terrain-only update")
	var saved_sources: Array[NodePath] = terrain.source_paths.duplicate()
	terrain.source_paths.clear()
	_build_terrain(terrain)
	props._process(0)
	_check(_snapshot(props).is_empty(), "empty terrain source produces genuine no-hit placements")
	props.regenerate()
	_check(props.get_placement_rebuild_stats().paths_reused == 2 and props.get_placement_rebuild_stats().sampling_steps == 0,
		"empty rejected ground blocks can replay their consumed RNG state")
	terrain.source_paths = saved_sources
	_build_terrain(terrain)
	props._process(0)
	_check(not _snapshot(props).is_empty() and props.get_placement_rebuild_stats().blocks_rebuilt > 0,
		"new valid terrain invalidates previously missing hits")
	_assert_full_equal(road, props, "terrain reappears after no-hit block replay")
	await _test_pending(road, terrain, first, props)
	var scene_prop := Node3D.new()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	scene_prop.add_child(body)
	body.add_child(shape)
	body.owner = scene_prop
	shape.owner = scene_prop
	var packed := PackedScene.new()
	_check(packed.pack(scene_prop) == OK, "scene-prop collision fixture packs")
	scene_prop.free()
	props.item_scene = packed
	props.regenerate()
	_check(_count_collisions(props) > 0 and props.get_placement_rebuild_stats().bypass_reasons.has("item_scene"),
		"scene props retain their collision/lifecycle workflow")
	await _test_pending(road, terrain, first, props)
	props.item_scene = null
	props.regenerate()
	await _test_pending(road, terrain, first, props, true)
	_benchmark_ground(road, terrain, first, props)
	scene.free()
	print("GROUND_PROP_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _build_terrain(terrain: Node) -> void:
	terrain.regenerate()
	while not terrain._mesh_build_state.is_empty():
		terrain._process_mesh_build()


func _test_pending(road: Node, terrain: Node, path: Path3D, props: Node, move_to_parent: bool = false) -> void:
	var previous := _snapshot(props)
	var old_ids := _owned_ids(props)
	terrain.threaded_triangulation_enabled = true
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	_check(terrain.is_terrain_generation_pending(), "fixture has a pending real terrain job")
	path.curve.set_point_tilt(3, 0.15)
	props.regenerate()
	_check(props.get_placement_rebuild_stats().pending_terrain and _owned_ids(props) == old_ids,
		"pending provider preserves exact existing node identities")
	_check(_snapshot(props) == previous, "pending provider does not erase or move valid props")
	if move_to_parent:
		props.use_parent_as_generated_root = true
		_check(_owned_ids(props) == old_ids, "changing output parent while pending preserves existing scene nodes")
	terrain.regenerate()
	var deadline := Time.get_ticks_msec() + 30000
	while (terrain.is_terrain_generation_pending() or props.get_placement_rebuild_stats().pending_terrain) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not terrain.is_terrain_generation_pending() and not props.get_placement_rebuild_stats().pending_terrain,
		"deferred props regenerate automatically after the latest terrain job")
	_assert_full_equal(road, props, "automatic retry uses final terrain state")
	terrain.threaded_triangulation_enabled = false
	terrain.regenerate()
	props.regenerate()
	_check(props.get_placement_rebuild_stats().pending_terrain, "multi-frame terrain also defers props")
	props._clear_generated_from_button()
	while terrain.is_terrain_generation_pending():
		terrain._process_mesh_build()
	props._process(0)
	_check(_snapshot(props).is_empty() and not props.get_placement_rebuild_stats().pending_terrain,
		"manual Clear Generated cancels deferred regeneration")
	_check(props._last_signature == props._build_signature(), "manual clear does not immediately trigger editor auto-regeneration")
	props.regenerate()
	_assert_full_equal(road, props, "explicit regeneration after clear")


func _owned_ids(props: Node) -> Array:
	var result: Array = []
	var pending: Array[Node] = [props.get_parent()]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if props._is_generated_node_for_this_array(node):
			result.append(node.get_instance_id())
		for child in node.get_children():
			pending.append(child)
	return result


func _benchmark_ground(road: Node, terrain: Node, path: Path3D, props: Node) -> void:
	var original := path.curve.get_point_position(4)
	var results: Dictionary = {}
	for incremental in [false, true]:
		road.incremental_generation_enabled = incremental
		path.curve.set_point_position(4, original)
		props._placement_cache.clear()
		terrain.clear_source_generation_cache()
		road.regenerate()
		_build_terrain(terrain)
		props.regenerate()
		var prop_samples: Array = []
		var total_samples: Array = []
		for i in range(5):
			path.curve.set_point_position(4, original + Vector3(0.17 * (i + 1), 0.11 * (i + 1), 0))
			var total_start := Time.get_ticks_usec()
			road.regenerate()
			_build_terrain(terrain)
			var prop_start := Time.get_ticks_usec()
			props.regenerate()
			prop_samples.append((Time.get_ticks_usec() - prop_start) / 1000.0)
			total_samples.append((Time.get_ticks_usec() - total_start) / 1000.0)
			if incremental:
				var stats: Dictionary = props.get_placement_rebuild_stats()
				_check(stats.blocks_reused > 0 and stats.blocks_rebuilt > 0,
					"timed distinct ground edit reuses and rebuilds real blocks")
		prop_samples.sort()
		total_samples.sort()
		results["local" if incremental else "full"] = {"props_ms": prop_samples[2], "road_terrain_props_ms": total_samples[2]}
	print("GROUND_PROP_DISTINCT_EDIT_MEDIAN terrain_source_cache_enabled=%s %s" % [terrain.incremental_generation_enabled, results])
	_assert_full_equal(road, props, "last timed ground edit")


func _profile_ground_queries(terrain: Node, props: Node, path: Path3D) -> void:
	var entry: Dictionary = props._placement_cache.previous(path)
	var queries: Array = entry.ground_queries
	var points: Array[Vector3] = []
	for i in range(128):
		points.append(queries[i * queries.size() / 128][0])
	var results: Dictionary = {}
	for use_cache in [false, true]:
		terrain.incremental_generation_enabled = use_cache
		_build_terrain(terrain)
		if use_cache:
			var original := path.curve.get_point_position(4)
			for i in range(3):
				path.curve.set_point_position(4, original + Vector3(0.17 * (i + 1), 0.11 * (i + 1), 0))
				_build_terrain(terrain)
		var road_ms := 0.0
		var center_ms := 0.0
		var normal_ms := 0.0
		var expected: Array = []
		for point: Vector3 in points:
			var local_point: Vector3 = terrain.to_local(point)
			var start := Time.get_ticks_usec()
			var data: Dictionary = terrain._get_cached_road_data()
			road_ms += (Time.get_ticks_usec() - start) / 1000.0
			var segments: Array = data.segments
			var xz := Vector2(local_point.x, local_point.z)
			start = Time.get_ticks_usec()
			var height: float = terrain._sample_height_at_point(xz, segments)
			center_ms += (Time.get_ticks_usec() - start) / 1000.0
			start = Time.get_ticks_usec()
			var normal: Vector3 = terrain._sample_terrain_normal_local(xz, segments)
			normal_ms += (Time.get_ticks_usec() - start) / 1000.0
			expected.append([terrain.to_global(Vector3(local_point.x, height, local_point.z)).y,
				(terrain.global_transform.basis * normal).normalized()])
		var full_start := Time.get_ticks_usec()
		for i in range(points.size()):
			var hit: Dictionary = terrain.get_terrain_height_at_world(points[i])
			_check(hit.y == expected[i][0] and hit.normal == expected[i][1], "profile decomposition matches real query")
		results["cached" if use_cache else "uncached"] = {
			"queries": points.size(), "road_ms": road_ms, "center_ms": center_ms,
			"normal_ms": normal_ms, "full_repeat_ms": (Time.get_ticks_usec() - full_start) / 1000.0,
			"source_stats": terrain.get_source_rebuild_stats()}
	print("GROUND_QUERY_PROFILE ", results)
