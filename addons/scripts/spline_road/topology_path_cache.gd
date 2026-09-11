@tool
extends "./terrain_stage_cache.gd"
## Native path rows, contour and segments. No persistent global path IDs.
const PROFILE: Script = preload("./spline_path_profile.gd")
const NETWORK_SETTINGS := ["road_width", "shoulder_left_width", "shoulder_right_width",
	"sidewalk_left_width", "sidewalk_right_width", "sidewalk_height", "y_offset",
	"road_orientation_mode", "road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance"]
const PROFILE_SETTINGS := ["default_width", "point_widths", "lane_profile_enabled",
	"default_lanes_left", "default_lanes_right", "default_lane_width", "point_lanes_left",
	"point_lanes_right", "point_lane_widths", "point_lane_transition_lengths",
	"shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width", "sidewalk_height"]
const BUILDER_SETTINGS := ["fallback_road_width", "path_sample_step", "adaptive_path_sampling",
	"adaptive_min_path_step", "adaptive_max_path_step", "adaptive_full_curve_angle_degrees",
	"road_orientation_mode", "road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance"]
var _current_keys := PackedStringArray()


func _entry_limit() -> int:
	return 512


func _max_idle_builds() -> int:
	# A shared Curve3D can alternate pre-bake lengths between road and terrain
	# builds. Keep both exact variants through intervening unchanged generations.
	return 4


func clear() -> void:
	super.clear()
	_current_keys.clear()


func begin_collection() -> void:
	_current_keys.clear()


func retain_collection() -> void:
	# An aggregate hit still uses these samples. Keep them alive across warm
	# generations so the next local edit can reuse the current unchanged paths.
	if enabled:
		touch_group(_current_keys)
		stats["collection_reused"] = int(stats.get("collection_reused", 0)) + 1


func configure(use_cache: bool, clear_requested: bool) -> void:
	super.configure(use_cache, clear_requested)
	stats.merge({"paths_reused": 0, "paths_rebuilt": 0, "rows_reused": 0,
		"rows_rebuilt": 0, "uncacheable_paths": 0, "collection_reused": 0,
		"segments_reused": 0, "segments_rebuilt": 0, "polygons_reused": 0, "polygons_rebuilt": 0}, true)


func _assembly_reuse_enabled() -> bool:
	return true


func collect_path(builder: Node3D, path: Path3D, curve: Curve3D, length: float,
		path_id: int, path_transform: Transform3D, builder_inverse: Transform3D) -> Dictionary:
	var inputs := _inputs(builder, path, length, path_transform, builder_inverse) if enabled else []
	var query_value := query("path_source", inputs) if not inputs.is_empty() else {}
	if not query_value.is_empty():
		_current_keys.append(query_value.key)
	var cached := lookup(query_value)
	var rows: Array
	if not cached.is_empty():
		var result: Dictionary = cached.result.duplicate(true)
		rows = result.rows
		stats.paths_reused += 1
		stats.rows_reused += rows.size()
		for row: Dictionary in rows:
			row.path_id = path_id
		if _assembly_reuse_enabled() and result.has("segments") and result.has("polygon"):
			for segment: Dictionary in result.segments:
				segment.path_id = path_id
			stats.segments_reused += result.segments.size()
			stats.polygons_reused += 1
			return result
		return _assemble(builder, rows, path_id)
	else:
		rows = []
		var d := 0.0
		while d < length:
			rows.append(builder._sample_road_row(path, curve, d, length, path_id, path_transform, builder_inverse))
			d += builder._get_adaptive_path_step(curve, d, length, path_transform, builder_inverse)
		rows.append(builder._sample_road_row(path, curve, length, length, path_id, path_transform, builder_inverse))
		if builder.get_script().get_base_script() == null:
			# Native profiles contain packed arrays borrowed from Inspector fields.
			# Detach them before assembly: both rows and segments then belong to
			# this collection even if an Inspector array is edited during a worker.
			# Cache hits already deep-copy their complete retained value graph.
			for row: Dictionary in rows:
				row.terrain_profile = row.terrain_profile.duplicate(true)
		stats["paths_rebuilt"] = int(stats.get("paths_rebuilt", 0)) + 1
		stats["rows_rebuilt"] = int(stats.get("rows_rebuilt", 0)) + rows.size()
		var result := _assemble(builder, rows, path_id)
		if not query_value.is_empty():
			var retained: Dictionary = result.duplicate(true) if _assembly_reuse_enabled() else {"rows": rows.duplicate(true)}
			for row: Dictionary in retained.rows:
				row.path_id = -1
			for segment: Dictionary in retained.get("segments", []):
				segment.path_id = -1
			store(query_value, retained)
		elif enabled:
			stats.uncacheable_paths += 1
		return result


func _assemble(builder: Node3D, rows: Array, path_id: int) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for row in rows:
		left.push_back(row.get("left2", Vector2.ZERO))
		right.push_back(row.get("right_edge2", Vector2.ZERO))
	var poly := PackedVector2Array()
	for p in left:
		poly.push_back(p)
	for i in range(right.size() - 1, -1, -1):
		poly.push_back(right[i])
	var segments: Array = []
	for i in range(rows.size() - 1):
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i + 1]
		var a2: Vector2 = a.get("center2", Vector2.ZERO)
		var b2: Vector2 = b.get("center2", Vector2.ZERO)
		if a2.distance_to(b2) < 0.001:
			continue
		var ab := b2 - a2
		var len2 := ab.length_squared()
		segments.append({
			"a": a2,
			"b": b2,
			"ab": ab,
			"len2": len2,
			"direction": ab / sqrt(len2),
			"ay": float(a.get("center_y", 0.0)),
			"by": float(b.get("center_y", 0.0)),
			"right_a": a.get("right", Vector3.RIGHT),
			"right_b": b.get("right", Vector3.RIGHT),
			"wa": float(a.get("width", builder.fallback_road_width)),
			"wb": float(b.get("width", builder.fallback_road_width)),
			"left_half_xz_a": float(a.get("left_half_xz", builder.fallback_road_width * 0.5)),
			"left_half_xz_b": float(b.get("left_half_xz", builder.fallback_road_width * 0.5)),
			"right_half_xz_a": float(a.get("right_half_xz", builder.fallback_road_width * 0.5)),
			"right_half_xz_b": float(b.get("right_half_xz", builder.fallback_road_width * 0.5)),
			"left_surface_raise_a": float(a.get("left_surface_raise", 0.0)),
			"left_surface_raise_b": float(b.get("left_surface_raise", 0.0)),
			"right_surface_raise_a": float(a.get("right_surface_raise", 0.0)),
			"right_surface_raise_b": float(b.get("right_surface_raise", 0.0)),
			"terrain_profile": a.get("terrain_profile", builder._default_terrain_height_profile()),
			"path_id": path_id,
		})
	stats["segments_rebuilt"] = int(stats.get("segments_rebuilt", 0)) + segments.size()
	stats["polygons_rebuilt"] = int(stats.get("polygons_rebuilt", 0)) + 1
	return {"rows": rows, "segments": segments, "polygon": poly}


func _inputs(builder: Node3D, path: Path3D, length: float,
		path_transform: Transform3D, builder_inverse: Transform3D) -> Array:
	# Do not suppress arbitrary callbacks, including inherited overrides or
	# scripted curves. Native frame providers have an explicit settings contract.
	if not builder.incremental_generation_enabled or builder.get_script().get_base_script() != null:
		return []
	if path.get_script() != null and path.get_script() != PROFILE:
		return []
	var curve := path.curve
	if curve.get_script() != null:
		return []
	var provider: Node = builder._resolve_road_network_for_path(path)
	var defaults: Node = builder.get_node_or_null(builder.road_network_source) if not builder.road_network_source.is_empty() else null
	var networks: Array = []
	for network: Node in [provider, defaults]:
		if network == null:
			networks.append(null)
			continue
		# Resolve relative to this addon, without a preload cycle through the road.
		var native_network: Script = load(PROFILE.resource_path.get_base_dir().path_join("road_network_creator.gd"))
		if network.get_script() != native_network:
			return []
		var values: Array = [network.global_transform]
		for property in NETWORK_SETTINGS:
			values.append(network.get(property))
		networks.append(values)
	var settings: Array = []
	for property in BUILDER_SETTINGS:
		settings.append(builder.get(property))
	var profile: Array = []
	if path.get_script() == PROFILE:
		for property in PROFILE_SETTINGS:
			profile.append(path.get(property))
		for transition: Curve in path.point_lane_transition_curves:
			if transition == null:
				profile.append(null)
				continue
			if transition.get_script() != null:
				return []
			var values: Array = [transition.min_domain, transition.max_domain, transition.bake_resolution]
			for i in range(transition.point_count):
				values.append([transition.get_point_position(i), transition.get_point_left_tangent(i),
					transition.get_point_right_tangent(i), transition.get_point_left_mode(i), transition.get_point_right_mode(i)])
			profile.append(values)
		# These are actual native interpolation inputs, not a deferred lane revision.
		if path.lane_profile_enabled:
			profile.append(path._control_point_offsets())
	return [path_transform, builder_inverse, builder.global_transform, settings, networks,
		curve.get("_data"), curve.closed, curve.up_vector_enabled, curve.bake_interval,
		length, profile, builder._resolve_path_terrain_height_profile(path)]
