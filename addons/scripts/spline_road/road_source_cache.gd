@tool
extends RefCounted
## Immutable pre-weld source blocks. Keys describe inputs, never generated meshes.
## Native Curve3D queries deliberately remain authoritative for arc length and up.

const PROFILE = preload("./spline_path_profile.gd")
const BLOCK_ROWS := 64
const SETTINGS := ["road_width", "y_offset", "uv_length_scale", "markings_enabled",
	"shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width",
	"sidewalk_height", "outer_wall_height", "terrain_left_width", "terrain_right_width",
	"road_orientation_mode", "road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance"]
const PROFILE_SETTINGS := ["default_width", "point_widths", "lane_profile_enabled",
	"default_lanes_left", "default_lanes_right", "default_lane_width", "point_lanes_left",
	"point_lanes_right", "point_lane_widths", "point_lane_transition_lengths",
	"shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width",
	"sidewalk_height", "outer_wall_height", "terrain_override_enabled", "terrain_left_width", "terrain_right_width"]
const EDGE_SETTINGS := ["shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width",
	"sidewalk_height", "outer_wall_height", "terrain_override_enabled", "terrain_left_width", "terrain_right_width"]

var enabled := false
var last_stats: Dictionary = {}
var _paths: Dictionary = {}
var _next_paths: Dictionary = {}
var _settings: Array = []
var _road: Node3D


func begin_build(road: Node3D) -> void:
	_road = road
	enabled = road.incremental_generation_enabled
	_next_paths = {}
	_settings = [road.global_transform]
	for property in SETTINGS:
		_settings.append(road.get(property))
	last_stats = {"paths_reused": 0, "blocks_rebuilt": 0, "blocks_reused": 0,
		"rows_rebuilt": 0, "rows_reused": 0, "dependency_rows_checked": 0, "uncacheable_paths": 0}
	if not enabled:
		_paths.clear()


func end_build() -> void:
	# Retain one completed source generation, not every edit in an editor session.
	_paths = _next_paths
	_next_paths = {}


func clear() -> void:
	_paths.clear()
	_next_paths.clear()


func can_cache(path: Path3D) -> bool:
	# Arbitrary user scripts may return time-varying widths without exposing data.
	return enabled and (path.get_script() == null or path.get_script() == PROFILE)


func path_key(path: Path3D, distances: PackedFloat32Array, transform: Transform3D) -> PackedByteArray:
	var curve := path.curve
	var profile: Array = []
	if path.get_script() == PROFILE:
		for property in PROFILE_SETTINGS:
			profile.append(path.get(property))
		for transition in path.point_lane_transition_curves:
			profile.append(_curve_key(transition))
	return var_to_bytes([_settings, transform, distances, curve.get("_data"), curve.closed,
		curve.up_vector_enabled, curve.bake_interval, profile])


func previous_path(path: Path3D) -> Dictionary:
	return _paths.get(path.get_instance_id(), {})


func retain_path(path: Path3D, entry: Dictionary) -> void:
	_next_paths[path.get_instance_id()] = entry


func current_path(path: Path3D) -> Dictionary:
	return _next_paths.get(path.get_instance_id(), {})


func block_key(path: Path3D, distances: Variant, transform: Transform3D) -> PackedByteArray:
	# Road rows use float32; prop jitter uses float64. Do not round prop queries
	# before checking the native curve/profile inputs that determine placement.
	var curve := path.curve
	var length := curve.get_baked_length()
	var supports := PackedVector3Array()
	var bank_probe_states: Array[bool] = []
	var mode: int = _road.road_orientation_mode
	var probe: float = maxf(0.05, _road.road_bank_sample_distance)
	for distance in distances:
		var previous := maxf(0.0, distance - 0.1)
		var next := minf(length, distance + 0.1)
		if is_equal_approx(next, previous):
			if next < length:
				next = minf(length, next + 0.1)
			elif previous > 0.0:
				previous = maxf(0.0, previous - 0.1)
		supports.append(curve.sample_baked(distance, true))
		supports.append(curve.sample_baked(previous, true))
		supports.append(curve.sample_baked(next, true))
		if mode == 0:
			# Includes transported posture, tilt and the native forward-vector cache.
			supports.append(_road._sample_curve_up_vector(curve, distance))
		elif mode == 2:
			var bank_previous := maxf(0.0, distance - probe)
			var bank_next := minf(length, distance + probe)
			supports.append(curve.sample_baked(bank_previous, true))
			supports.append(curve.sample_baked(bank_next, true))
			bank_probe_states.append(length <= 0.0001 or is_equal_approx(bank_previous, bank_next))
	last_stats.dependency_rows_checked += distances.size()
	return var_to_bytes([_settings, transform, distances, supports, bank_probe_states, _profile_support(path, distances, length)])


func _profile_support(path: Path3D, distances: Variant, length: float) -> Array:
	if path.get_script() == null:
		return []
	var support: Array = []
	for property in EDGE_SETTINGS:
		support.append(path.get(property))
	if not path.lane_profile_enabled:
		var widths: Array[float] = []
		for i in range(path.curve.point_count):
			widths.append(path._get_legacy_point_width(i))
		var uniform := true
		for width in widths:
			uniform = uniform and width == widths[0]
		# Legacy nonuniform widths genuinely depend on total path length.
		support.append([false, widths[0]] if uniform else [false, widths, length])
		if not _road.markings_enabled:
			return support
	var first: Dictionary = path._lane_segment_sample(distances[0])
	var last: Dictionary = path._lane_segment_sample(distances[distances.size() - 1])
	var offsets: PackedFloat32Array = path._control_point_offsets()
	# Disabled profiles still publish layout metadata to marking rows. Preserve
	# its exact values as well, even though current paint ignores disabled lanes.
	var lane_support: Array = [path.lane_profile_enabled, first.from, last.to]
	for index in range(int(first.from), int(last.to) + 1):
		lane_support.append([offsets[index], path._get_point_lane_count(index, true),
			path._get_point_lane_count(index, false), path._get_point_lane_width(index),
			path._get_point_lane_transition_length(index), _curve_key(path._get_point_lane_transition(index))])
	support.append(lane_support)
	return support


func _curve_key(curve: Curve) -> Array:
	if curve == null:
		return []
	var values: Array = [curve.min_domain, curve.max_domain, curve.bake_resolution]
	for i in range(curve.point_count):
		values.append([curve.get_point_position(i), curve.get_point_left_tangent(i), curve.get_point_right_tangent(i),
			curve.get_point_left_mode(i), curve.get_point_right_mode(i)])
	return values
