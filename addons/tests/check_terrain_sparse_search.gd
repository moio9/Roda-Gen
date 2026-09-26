extends SceneTree
const TERRAIN = preload("../scripts/spline_road/terrain_topology_builder.gd")
const REFERENCE = preload("fixtures/terrain_search_reference.gd")
var failures := 0
func _initialize():
	_run.call_deferred()
func _check(ok: bool, message: String):
	if not ok:
		push_error(message)
		failures += 1
func _run():
	var scene := Node3D.new()
	root.add_child(scene)
	var terrain = TERRAIN.new()
	var reference = REFERENCE.new()
	scene.add_child(terrain)
	scene.add_child(reference)
	terrain.bounds_mode = 1
	terrain.manual_size_xz = Vector2(100, 100)
	terrain.far_grid_step = 12
	terrain.generate_road_edge_collars = false
	terrain.auto_lane_profile_edge_collars = false
	terrain.auto_find_height_modifiers = false
	for axis in range(2):
		var path := Path3D.new()
		path.name = "Path%d" % axis
		path.curve = Curve3D.new()
		path.curve.add_point(Vector3(-30, -3, 0) if axis == 0 else Vector3(0, 4, -30))
		path.curve.add_point(Vector3(30, 3, 0) if axis == 0 else Vector3(0, 8, 30))
		terrain.add_child(path)
		terrain.source_paths.append(NodePath(path.name))
	terrain.regenerate()
	while terrain.is_terrain_generation_pending():
		await process_frame
	for name_ in ["_road_spatial_cells", "_road_spatial_segment_count", "_road_spatial_cell_size", "_road_max_half_width"]:
		reference.set(name_, terrain.get(name_))
	var segments: Array = terrain._get_cached_road_data().segments
	var points: Array[Vector2] = [Vector2.ZERO, Vector2(0, -30), Vector2(-30, 0), Vector2(30, 0), Vector2(0, 30), Vector2(700, -500), Vector2(-500, 700)]
	for i in range(30):
		points.append(Vector2(i * 3 - 45, i * -4 + 60))
	for cache_enabled in [false, true]:
		terrain._source_cache.enabled = cache_enabled
		for point in points:
			var old_trace: Dictionary = {}
			var new_trace: Dictionary = {}
			var expected: Dictionary = reference._nearest_road_info_spatial_uncached(point, segments, old_trace)
			var actual: Dictionary = terrain._nearest_road_info_spatial_uncached(point, segments, new_trace)
			_check(var_to_bytes(expected) == var_to_bytes(actual), "Nearest road parity at %s, cache=%s" % [point, cache_enabled])
			if cache_enabled:
				_check(old_trace == new_trace, "Preserve incremental dependency certificates")
	# Force the normal perimeter path even with source replay disabled.
	terrain._source_cache.enabled = false
	for i in range(65):
		terrain._road_spatial_cells[Vector2i(10000 + i, 10000)] = []
	for point in points:
		_check(var_to_bytes(reference._nearest_road_info_spatial_uncached(point, segments)) == var_to_bytes(terrain._nearest_road_info_spatial_uncached(point, segments)), "Large-index perimeter parity")
	print("TERRAIN_SEARCH failures=",failures)
	scene.free()
	quit(1 if failures else 0)
