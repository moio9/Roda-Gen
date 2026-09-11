extends "./check_road_terrain_cache.gd"
const TOPOLOGY = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
const LEGACY = preload("./fixtures/topology_source_legacy.gd")
class RebuiltAssembly extends "../addons/scripts/spline_road/topology_path_cache.gd":
	func _assembly_reuse_enabled() -> bool:
		return false
class BorrowedCollection extends TOPOLOGY:
	var borrowed := {"rows": [], "segments": [], "polygons": []}
	func _collect_road_data() -> Dictionary:
		return borrowed
class DynamicPath extends Path3D:
	var calls := 0
	func get_width_at_offset(_offset: float) -> float:
		calls += 1
		return 8.0
class DynamicRoad extends ROAD:
	var calls := 0
	func get_path_surface_frame(path: Path3D, distance: float) -> Dictionary:
		calls += 1
		return super.get_path_surface_frame(path, distance)
class CollisionCache extends "../addons/scripts/spline_road/topology_path_cache.gd":
	func _query_key(_input: PackedByteArray) -> String:
		return "collision"


func _run() -> void:
	var scene := Node3D.new()
	var road := ROAD.new()
	road.name = "Road"
	road.generate_in_editor = false
	road.debug_generation_logs = false
	var terrain := TOPOLOGY.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.incremental_generation_enabled = true
	terrain.adaptive_path_sampling = false
	terrain.path_sample_step = 4.0
	terrain.road_network_source = NodePath("../Road")
	var first := _path("First", Vector3.ZERO)
	var second := _path("Second", Vector3(200, 0, 0))
	road.add_child(first)
	road.add_child(second)
	scene.add_child(road)
	scene.add_child(terrain)
	terrain.source_paths.assign([NodePath("../Road/First"), NodePath("../Road/Second")])
	root.add_child(scene)
	# Stabilize the initial interval only for warm-reuse assertions. Separate
	# checks below explicitly restore differing pre-bake lengths for both runs.
	first.curve.bake_interval = 4.0
	second.curve.bake_interval = 4.0
	_pair(terrain, "cold")
	_pair(terrain, "warm")
	_check(terrain._path_cache.stats.paths_reused == 2, "unchanged native paths skip sampling")
	_check(terrain._path_cache.stats.polygons_reused == 2 and terrain._path_cache.stats.segments_reused > 0
		and terrain._path_cache.stats.segments_rebuilt == 0, "warm paths skip contour and segment assembly")
	terrain.invalidate_road_data_cache()
	var owned: Dictionary = terrain._get_cached_road_data()
	var owned_bytes := var_to_bytes(owned)
	owned.segments[0].direction = Vector2(999, 999)
	owned.polygons[0][0] = Vector2(999, 999)
	terrain.invalidate_road_data_cache()
	_check(var_to_bytes(terrain._get_cached_road_data()) == owned_bytes,
		"native aggregate ownership never exposes retained path records to mutation")
	var borrowed := BorrowedCollection.new()
	borrowed.generate_in_editor = false
	scene.add_child(borrowed)
	var borrowed_result: Dictionary = borrowed._get_cached_road_data()
	borrowed_result.rows.append({"caller": true})
	_check(borrowed.borrowed.rows.is_empty(), "custom collection results remain detached from their provider")
	borrowed.free()
	# Force a miss rather than a replay of already-detached cached values.
	terrain._path_cache.clear()
	terrain.invalidate_road_data_cache()
	var inspector_snapshot: Dictionary = terrain._get_cached_road_data()
	var inspector_bytes := var_to_bytes(inspector_snapshot)
	var inspector_heights: PackedFloat32Array = terrain.left_profile_heights.duplicate()
	terrain.left_profile_heights[3] += 100
	_check(var_to_bytes(inspector_snapshot) == inspector_bytes,
		"fresh native collections detach Inspector profile arrays before publication")
	terrain.left_profile_heights = inspector_heights
	_check(var_to_bytes(terrain._get_cached_road_data()) == inspector_bytes,
		"restoring Inspector values cannot resurrect mutated persistent source data")
	terrain.invalidate_road_data_cache()
	terrain._get_cached_road_data()
	for warm in range(6):
		terrain._path_cache.configure(true, false)
		terrain._get_cached_road_data()
	_check(terrain._path_cache.stats.collection_reused == 1 and terrain._path_cache.stats.entries == 2,
		"aggregate road-data hits retain current path entries beyond idle expiry")
	first.curve.set_point_position(1, Vector3(8, 3, 40))
	_pair(terrain, "local point edit")
	_check(terrain._path_cache.stats.paths_reused == 1 and terrain._path_cache.stats.paths_rebuilt == 1,
		"local point edit resamples only one path")
	_check(terrain._path_cache.stats.polygons_reused == 1 and terrain._path_cache.stats.polygons_rebuilt == 1
		and terrain._path_cache.stats.segments_reused > 0 and terrain._path_cache.stats.segments_rebuilt > 0,
		"local edit assembles only the changed path")
	for edit in range(6):
		for path: Path3D in [first, second]:
			path.curve.bake_interval = 0.3 if edit % 2 == 0 else 4.0
		_pair(terrain, "alternating exact pre-bake length " + str(edit))
		if edit >= 2:
			_check(terrain._path_cache.stats.paths_reused == 2, "both exact pre-bake variants survive intervening generations")
		terrain._path_cache.configure(true, false)
		terrain._path_cache.retain_collection()
	terrain.source_paths.reverse()
	var reordered := _pair(terrain, "reordered paths")
	_check(terrain._path_cache.stats.paths_reused == 2 and reordered.rows[0].center.x > 100
		and reordered.rows[0].path_id == 0, "retained rows receive current path IDs")
	for mode in range(3):
		road.road_orientation_mode = mode
		road.road_bank_strength = 0.7
		first.curve.set_point_tilt(1, 0.3)
		_pair(terrain, "bank/frame mode " + str(mode))
		_pair(terrain, "warm bank/frame mode " + str(mode))
		_check(terrain._path_cache.stats.paths_reused == 2, "all native frame modes reuse exact inputs")
	first.lane_profile_enabled = true
	first.point_lanes_left = PackedInt32Array([1, 3, 2])
	first.point_lanes_right = PackedInt32Array([2, 1, 1])
	first.point_lane_transition_lengths = PackedFloat32Array([0, 12, 16])
	var transition := Curve.new()
	transition.add_point(Vector2.ZERO)
	transition.add_point(Vector2.ONE)
	first.point_lane_transition_curves.assign([null, transition])
	_pair(terrain, "asymmetric lane profile")
	_pair(terrain, "warm lanes")
	_check(terrain._path_cache.stats.paths_reused == 2, "native lane offsets and transition values reuse")
	transition.set_point_left_tangent(1, 0.25)
	_pair(terrain, "transition resource edit")
	_check(terrain._path_cache.stats.paths_reused == 1, "in-place transition resource changes invalidate only its path")
	first.point_lanes_left[1] += 1
	terrain.invalidate_road_data_cache()
	_pair(terrain, "explicit deferred lane edit")
	_check(terrain._path_cache.stats.paths_reused == 1, "live lane extents invalidate independently of dependent revision")
	first.shoulder_left_width += 1.25
	_pair(terrain, "shoulder edit")
	first.terrain_height_profile_override_enabled = true
	first.terrain_left_profile_distances = PackedFloat32Array([0, 20])
	first.terrain_right_profile_distances = PackedFloat32Array([0, 20])
	first.terrain_left_profile_heights = PackedFloat32Array([0, 7])
	first.terrain_right_profile_heights = PackedFloat32Array([0, 5])
	_pair(terrain, "per-path terrain height profile")
	first.terrain_left_profile_heights[1] = 9
	_pair(terrain, "in-place terrain profile edit")
	_check(terrain._path_cache.stats.paths_reused == 1, "terrain profile change is local")
	terrain.left_profile_heights[1] += 1
	_pair(terrain, "default profile edit")
	first.position.y += 2
	_pair(terrain, "path transform")
	road.rotation.z = 0.07
	_pair(terrain, "road transform")
	terrain.position = Vector3(2, 3, -4)
	_pair(terrain, "builder transform")
	road.y_offset += 0.15
	_pair(terrain, "network vertical offset")
	first.curve.bake_interval = 0.3
	_pair(terrain, "pre-bake length change")
	first.curve.closed = true
	_pair(terrain, "closed curve")
	first.curve.closed = false
	first.curve.up_vector_enabled = false
	road.road_orientation_mode = 1
	_pair(terrain, "up-vector mode")
	terrain.adaptive_path_sampling = true
	_pair(terrain, "adaptive sampling")
	terrain.adaptive_max_path_step = 5.75
	_pair(terrain, "adaptive step edit")
	# Mutable callers cannot poison the retained snapshots.
	var exposed := _pair(terrain, "snapshot before mutation")
	var expected := var_to_bytes(exposed)
	exposed.rows[0].center = Vector3(999, 999, 999)
	exposed.rows[0].terrain_profile.left_heights[0] = 999
	exposed.segments[0].path_id = 999
	exposed.segments[0].direction = Vector2(999, 999)
	exposed.segments[0].terrain_profile.left_heights[0] = 999
	exposed.polygons[0][0] = Vector2(999, 999)
	_check(var_to_bytes(_pair(terrain, "snapshot after mutation")) == expected, "returned rows/profiles are detached from stored values")
	terrain.source_paths.append(NodePath("../Road/Missing"))
	_pair(terrain, "missing source")
	terrain.source_paths.remove_at(0)
	_pair(terrain, "removed source")
	var plain := Path3D.new()
	plain.name = "Plain"
	plain.curve = second.curve.duplicate()
	scene.add_child(plain)
	terrain.source_paths.append(NodePath("../Plain"))
	terrain.road_network_source = NodePath()
	_pair(terrain, "plain path without provider")
	_pair(terrain, "warm plain path")
	_check(terrain._path_cache.stats.paths_reused == 2, "native parent-provider and no-provider paths both reuse")
	var vertical := Path3D.new()
	vertical.name = "Vertical"
	vertical.curve = Curve3D.new()
	vertical.curve.add_point(Vector3.ZERO)
	vertical.curve.add_point(Vector3(0, 3, 0))
	vertical.curve.add_point(Vector3(0, 6, 0))
	scene.add_child(vertical)
	terrain.source_paths.append(NodePath("../Vertical"))
	_pair(terrain, "vertical path with no XZ segments")
	var vertical_result := _pair(terrain, "warm vertical contour")
	_check(terrain._path_cache.stats.polygons_reused == 3 and vertical_result.rows.back().path_id == 2
		and vertical_result.segments.back().path_id == 1, "empty segment lists retain their polygon and current path ID")
	terrain.source_paths.append(NodePath("../Plain"))
	var duplicate := _pair(terrain, "duplicate source path")
	_check(duplicate.rows.back().path_id == 3 and duplicate.segments.back().path_id == 3,
		"duplicate cached path values are detached and remapped independently")
	terrain.source_paths.resize(terrain.source_paths.size() - 2)
	terrain._path_cache = RebuiltAssembly.new()
	_pair(terrain, "row-only fallback cold")
	_pair(terrain, "row-only fallback warm")
	_check(terrain._path_cache.stats.paths_reused == 2 and terrain._path_cache.stats.polygons_reused == 0
		and terrain._path_cache.stats.polygons_rebuilt == 2, "row-only records retain sampling but still assemble contours and segments")
	# Switch to native assembly replay while retaining the row-only schema.
	var row_only_entries: Dictionary = terrain._path_cache._entries.duplicate(true)
	terrain._path_cache = preload("../addons/scripts/spline_road/topology_path_cache.gd").new()
	terrain._path_cache.configure(true, false)
	for key: String in row_only_entries:
		var entry: Dictionary = row_only_entries[key]
		terrain._path_cache.store({"key": key, "input": entry.input}, entry.result)
	_pair(terrain, "row-only schema falls back to native assembly")
	_check(terrain._path_cache.stats.paths_reused == 2 and terrain._path_cache.stats.polygons_rebuilt == 2,
		"incomplete assembly records cannot be treated as complete source paths")
	var dynamic := DynamicPath.new()
	dynamic.name = "Dynamic"
	dynamic.curve = second.curve.duplicate()
	scene.add_child(dynamic)
	terrain.source_paths.append(NodePath("../Dynamic"))
	_pair(terrain, "custom path")
	var calls := dynamic.calls
	_pair(terrain, "warm custom path")
	_check(dynamic.calls > calls and terrain._path_cache.stats.uncacheable_paths == 1, "custom path callbacks remain live on every collection")
	var custom_road := DynamicRoad.new()
	custom_road.name = "DynamicRoad"
	custom_road.generate_in_editor = false
	custom_road.debug_generation_logs = false
	custom_road.threaded_generation_enabled = false
	custom_road.road_orientation_mode = 1
	scene.add_child(custom_road)
	terrain.road_network_source = NodePath("../DynamicRoad")
	_pair(terrain, "custom frame provider")
	calls = custom_road.calls
	_pair(terrain, "warm custom frame provider")
	_check(custom_road.calls > calls and terrain._path_cache.stats.paths_reused == 0, "custom network callbacks cannot be cached")
	terrain.road_network_source = NodePath("../Road")
	terrain._path_cache = CollisionCache.new()
	_pair(terrain, "forced key collisions")
	_pair(terrain, "warm forced key collisions")
	_check(terrain._path_cache.stats.paths_reused == 0, "hash collisions compare exact inputs")
	terrain.clear_source_generation_cache()
	_check(terrain._path_cache.stats.entries == 0, "explicit source clear releases path samples")
	var bounded := preload("../addons/scripts/spline_road/topology_path_cache.gd").new()
	bounded.configure(true, false)
	for i in range(520):
		bounded.store(bounded.query("bounded_path", [i]), [i])
	_check(bounded.stats.entries == 512 and bounded.stats.evicted == 8, "path retention has its own 512-entry limit")
	for idle in range(4):
		bounded.configure(true, false)
	_check(bounded.stats.entries == 512, "path variants survive four idle generations")
	bounded.configure(true, false)
	_check(bounded.stats.entries == 0, "unused paths expire after four idle generations")
	bounded.store(bounded.query("clear_path", [1]), [1])
	bounded.configure(false, false)
	_check(bounded.stats.entries == 0 and bounded.stats.payload_bytes == 0, "disabling reuse releases retained paths")
	scene.free()
	print("TOPOLOGY_PATH_CACHE_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _pair(terrain: Node, label: String) -> Dictionary:
	var intervals: Dictionary = {}
	for np: NodePath in terrain.source_paths:
		var path := terrain.get_node_or_null(np) as Path3D
		if path != null and path.curve != null:
			intervals[path.curve] = path.curve.bake_interval
	terrain._path_cache.configure(true, false)
	var cached: Dictionary = terrain._collect_road_data()
	for curve: Curve3D in intervals:
		curve.bake_interval = intervals[curve]
	# Separate pre-cache collection/assembly implementation, with the same native
	# row sampler and pre-bake interval sequence but no production cache helpers.
	var full: Dictionary = LEGACY.collect(terrain)
	_check(var_to_bytes(cached) == var_to_bytes(full), label + " exact rows, polygons, segments and current IDs")
	return cached
