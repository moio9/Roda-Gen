@tool
extends RefCounted
## Whole-path and within-path placement reuse. Random streams are dependencies.
## Built-in idle terrain queries are revalidated before replay. Unknown ground
## providers and scene scripts retain their original lifecycle.

const PROFILE = preload("./spline_path_profile.gd")
const SOURCE_SUPPORT = preload("./road_source_cache.gd")
const BLOCK_CANDIDATES := 32
const MAX_BUILD_GROUND_QUERIES := 16384
const PLACEMENT_SETTINGS := ["placement_mode", "spacing", "start_offset", "end_trim",
	"default_lane_width", "edge_uses_total_road_width", "lateral_offset", "outward_offset", "vertical_offset",
	"avoid_intersections", "avoid_own_path_endpoints", "avoid_other_path_endpoints",
	"avoid_intersections_in_center_mode", "intersection_clear_radius", "ranges_mode", "range_source_mode",
	"distance_ranges", "align_with_path", "align_with_curve_up", "tangent_sample_distance", "yaw_offset_degrees", "custom_transform",
	"longitudinal_jitter", "lateral_jitter", "vertical_jitter", "yaw_jitter_degrees",
	"random_uniform_scale_min", "random_uniform_scale_max", "render_mode", "multimesh_chunk_size",
	"snap_to_ground_enabled", "snap_to_ground_max_angle_deg", "snap_to_ground_slope_mode", "snap_to_ground_y_offset"]
const PROFILE_SETTINGS := ["default_width", "point_widths", "lane_profile_enabled",
	"default_lanes_left", "default_lanes_right", "default_lane_width", "point_lanes_left", "point_lanes_right",
	"point_lane_widths", "point_lane_transition_lengths", "shoulder_left_width", "shoulder_right_width",
	"sidewalk_left_width", "sidewalk_right_width"]
const ROAD_SETTINGS := ["y_offset", "road_orientation_mode", "road_bank_max_degrees", "road_bank_strength",
	"road_bank_sample_distance"]

var stats: Dictionary = {}
var _entries: Dictionary = {}
var _next_entries: Dictionary = {}
var _common_key: Array = []
var _block_common_key: Array = []
var _source_support = SOURCE_SUPPORT.new()
var _road: Node3D
var _props: Node3D
var _bypass_reason := ""
var _uses_endpoint_zones := true
var _ground_provider: Node
var _ground_samples: Dictionary = {}


func begin_build(props: Node3D) -> void:
	stats = {"paths_reused": 0, "paths_rebuilt": 0, "paths_bypassed": 0,
		"placements_reused": 0, "placements_rebuilt": 0, "sampling_steps": 0, "bypass_reasons": {},
		"blocks_reused": 0, "blocks_rebuilt": 0, "candidates_reused": 0, "candidates_rebuilt": 0,
		"dependency_rows_checked": 0, "endpoint_queries_checked": 0,
		"ground_queries_checked": 0, "ground_queries_sampled": 0,
		"ground_provider_queries": 0, "ground_results_reused": 0}
	_props = props
	_next_entries = {}
	_common_key = []
	_block_common_key = []
	_road = null
	_ground_provider = null
	_ground_samples.clear()
	_bypass_reason = ""
	_uses_endpoint_zones = props.avoid_intersections
	var road: Node = null
	if not props.road_network_source.is_empty():
		road = props.get_node_or_null(props.road_network_source)
	var road_script_path: String = get_script().resource_path.get_base_dir().path_join("road_network_creator.gd")
	var props_script_path: String = get_script().resource_path.get_base_dir().path_join("spline_prop_array.gd")
	var terrain_script_path: String = get_script().resource_path.get_base_dir().path_join("terrain_topology_builder.gd")
	if props.snap_to_ground_enabled:
		var provider: Node = props._get_terrain_height_source()
		if is_instance_valid(provider) and provider.get_script() == load(terrain_script_path) \
				and provider.supports_terrain_placement_cache():
			_ground_provider = provider
	if props.get_script() != load(props_script_path):
		_bypass_reason = "custom_props"
	elif props.fit_segments_to_path:
		_bypass_reason = "connected_segments"
	elif road == null or road.get_script() != load(road_script_path):
		_bypass_reason = "no_compatible_road"
	elif not road.incremental_generation_enabled:
		_bypass_reason = "road_incremental_disabled"
	elif props.item_scene != null:
		_bypass_reason = "item_scene"
	elif props.snap_to_ground_enabled and _ground_provider == null:
		_bypass_reason = "ground_snap"
	elif props.randomize_seed_each_regenerate:
		_bypass_reason = "randomized_seed"
	if not _bypass_reason.is_empty():
		_ground_provider = null
		return
	_road = road
	_source_support.begin_build(_road)
	_common_key = [props.global_transform, road.global_transform,
		_ground_provider.get_instance_id() if _ground_provider != null else 0]
	_block_common_key = _common_key.duplicate()
	for property in PLACEMENT_SETTINGS:
		_common_key.append(props.get(property))
		# The effective ranges are clipped to each block's jitter/clamp domain.
		if property != "distance_ranges":
			_block_common_key.append(props.get(property))
	for property in ROAD_SETTINGS:
		_common_key.append(road.get(property))
		_block_common_key.append(road.get(property))


func key_for(path: Path3D, parent: Node3D, rng: RandomNumberGenerator, endpoints: Array, ranges: Dictionary) -> PackedByteArray:
	var reason := _bypass_reason
	if reason.is_empty() and (path == null or path.curve == null or path.curve.point_count < 2):
		reason = "invalid_path"
	if reason.is_empty() and (path.get_script() != null and path.get_script() != PROFILE):
		reason = "custom_path"
	if reason.is_empty() and path.curve.get_script() != null:
		reason = "custom_curve"
	if not reason.is_empty():
		stats.paths_bypassed += 1
		stats.bypass_reasons[reason] = stats.bypass_reasons.get(reason, 0) + 1
		return PackedByteArray()
	var profile: Array = []
	if path.get_script() == PROFILE:
		for property in PROFILE_SETTINGS:
			profile.append(path.get(property))
		for transition: Curve in path.point_lane_transition_curves:
			profile.append(_transition_key(transition))
	var curve := path.curve
	return var_to_bytes([_common_key, path.global_transform, parent.global_transform,
		curve.get("_data"), curve.closed, curve.up_vector_enabled, curve.bake_interval,
		profile, endpoints if _uses_endpoint_zones else [], ranges.get(path.get_instance_id(), PackedVector2Array()), rng.seed, rng.state])


func can_reuse_output(paths: Array[Path3D]) -> bool:
	if not _bypass_reason.is_empty():
		return false
	var names: Dictionary = {}
	for path: Path3D in paths:
		# Legacy native names derive from path.name, not identity. With duplicate
		# names, preserve the original ordered create/auto-rename lifecycle.
		if names.has(path.name):
			return false
		names[path.name] = true
		if path.get_script() != null and path.get_script() != PROFILE:
			return false
		if path.curve != null and path.curve.get_script() != null:
			return false
	return true


func previous(path: Path3D) -> Dictionary:
	return _entries.get(path.get_instance_id(), {})


func path_context(path: Path3D, parent: Node3D, endpoints: Array, effective_ranges: PackedVector2Array, ranges_mode: int) -> Dictionary:
	return {"key": [_block_common_key, path.global_transform, parent.global_transform],
		"endpoints": endpoints, "ranges": effective_ranges if ranges_mode != 0 else PackedVector2Array(),
		"transform": _road.global_transform.affine_inverse() * path.global_transform}


func open_block(path: Path3D, context: Dictionary, previous_blocks: Array, index: int,
		dist: float, begin: float, end: float, step: float, jitter: float, remaining: int, rng: RandomNumberGenerator,
		ground_state: Dictionary = {}) -> Dictionary:
	var bases := PackedFloat64Array()
	# Match repeated addition in the original loop, including fractional spacing.
	while dist <= end + 0.0001 and bases.size() < mini(BLOCK_CANDIDATES, remaining):
		bases.append(dist)
		dist += step
	var lower := clampf(bases[0] - absf(jitter), begin, end)
	var upper := clampf(bases[bases.size() - 1] + absf(jitter), begin, end)
	var prefix := var_to_bytes([context.key, bases, begin, lower, upper,
		_range_support(context.ranges, lower, upper), rng.seed, rng.state, ground_state])
	if index < previous_blocks.size():
		var old: Dictionary = previous_blocks[index]
		if old.prefix == prefix and old.geometry_key == _geometry_key(path, context, old.distances) \
				and ground_matches(old) \
				and old.endpoint_key == _endpoint_key(path, context, old.endpoint_queries):
			stats.blocks_reused += 1
			stats.candidates_reused += bases.size()
			return old
	stats.blocks_rebuilt += 1
	stats.candidates_rebuilt += bases.size()
	return {"prefix": prefix, "next_dist": dist, "candidate_count": bases.size()}


func finish_block(path: Path3D, context: Dictionary, block: Dictionary,
		distances: PackedFloat64Array, endpoint_queries: Array, placements: Array, rng: RandomNumberGenerator,
		ground_queries: Array = [], ground_state: Dictionary = {}) -> Dictionary:
	block["distances"] = distances
	block["geometry_key"] = _geometry_key(path, context, distances)
	block["endpoint_queries"] = endpoint_queries
	block["endpoint_key"] = _endpoint_key(path, context, endpoint_queries)
	block["placements"] = placements
	block["rng_after"] = rng.state
	block["ground_queries"] = ground_queries
	block["ground_key"] = _ground_key(ground_queries, false)
	block["ground_state_after"] = ground_state.duplicate()
	return block


func ground_matches(entry: Dictionary) -> bool:
	return entry.get("ground_key", PackedByteArray()) == _ground_key(entry.get("ground_queries", []), true)


func _ground_key(queries: Array, sample_current: bool) -> PackedByteArray:
	if _ground_provider == null:
		return PackedByteArray()
	var results: Array = []
	for query: Array in queries:
		if sample_current:
			stats.ground_queries_checked += 1
			results.append(sample_ground(query[0],
				clampf(_props.snap_to_ground_max_angle_deg, 0.0, 89.0), _props.snap_to_ground_y_offset))
		else:
			results.append(query[1])
	return var_to_bytes(results)


func sample_ground(point: Vector3, max_angle: float, offset: float) -> Dictionary:
	# A failed whole-path comparison and the subsequent block pass can inspect
	# the same point. Share only current-build pure results, never old terrain hits.
	var key := var_to_bytes([point, max_angle, offset]).hex_encode() if _ground_provider != null else ""
	if not key.is_empty() and _ground_samples.has(key):
		stats.ground_results_reused += 1
		return _ground_samples[key].duplicate(true)
	stats.ground_provider_queries += 1
	var result: Dictionary = _props._sample_terrain_height_hit(point, max_angle, offset)
	if not key.is_empty() and _ground_samples.size() < MAX_BUILD_GROUND_QUERIES:
		_ground_samples[key] = result.duplicate(true)
	return result


func _geometry_key(path: Path3D, context: Dictionary, distances: PackedFloat64Array) -> PackedByteArray:
	if distances.is_empty():
		return PackedByteArray()
	# Large longitudinal jitter can reverse adjacent sample distances. Profile
	# support needs the minimum/maximum, without changing emission or RNG order.
	var sorted := distances.duplicate()
	sorted.sort()
	return _source_support.block_key(path, sorted, context.transform)


func _endpoint_key(path: Path3D, context: Dictionary, queries: Array) -> PackedByteArray:
	# With matching geometry and incoming RNG, the first changed rejection is a
	# dependency change. It forces a rebuild before subsequent random draws can
	# diverge. Distant endpoint edits with identical decisions need no placement work.
	var decisions := PackedByteArray()
	for query: Array in queries:
		decisions.append(1 if _props._point_blocked_by_intersection_zones(path, query[0], query[1], context.endpoints) else 0)
	stats.endpoint_queries_checked += queries.size()
	return decisions


func _range_support(ranges: PackedVector2Array, lower: float, upper: float) -> Array:
	# No effective ranges means unrestricted, NOT reject all in include mode.
	if ranges.is_empty():
		return [true]
	var support: Array = [false]
	for pair in ranges:
		if pair.y >= lower and pair.x <= upper:
			support.append([maxf(lower, pair.x), minf(upper, pair.y)])
	return support


func retain(path: Path3D, entry: Dictionary) -> void:
	if not entry.has("ground_key"):
		var queries: Array = []
		for block: Dictionary in entry.get("blocks", []):
			queries.append_array(block.get("ground_queries", []))
		entry["ground_queries"] = queries
		entry["ground_key"] = _ground_key(queries, false)
	_next_entries[path.get_instance_id()] = entry


func end_build(rng: RandomNumberGenerator) -> void:
	_ground_samples.clear()
	_entries = _next_entries
	_next_entries = {}
	stats["rng_final_state"] = rng.state
	stats["cache_entries"] = _entries.size()
	if _road != null:
		stats.dependency_rows_checked = _source_support.last_stats.dependency_rows_checked
		_source_support.end_build()


func clear() -> void:
	_ground_samples.clear()
	_entries.clear()
	_next_entries.clear()


func _transition_key(curve: Curve) -> Array:
	if curve == null:
		return []
	var values: Array = [curve.min_domain, curve.max_domain, curve.min_value, curve.max_value, curve.bake_resolution]
	for i in range(curve.point_count):
		values.append([curve.get_point_position(i), curve.get_point_left_tangent(i), curve.get_point_right_tangent(i),
			curve.get_point_left_mode(i), curve.get_point_right_mode(i)])
	return values
