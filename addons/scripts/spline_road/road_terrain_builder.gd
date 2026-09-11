@tool
extends RefCounted
## Terrain fill topology, road clipping, height sampling and skirts.
## Configuration is captured before a generation job; the coordinator owns scene nodes.

var _road: Node
const TERRAIN_FILL_RECTANGLE := 1
const TERRAIN_FILL_BOOLEAN := 2
const TERRAIN_FILL_TOPOLOGY_GLOBAL_RECT := 1
const TERRAIN_FILL_TOPOLOGY_CONVEX_HULL := 2
const TERRAIN_FILL_TOPOLOGY_GRID := 3
const TERRAIN_FILL_TOPOLOGY_RADIAL := 4
const TERRAIN_FILL_TOPOLOGY_HEX := 5
const TERRAIN_FILL_TOPOLOGY_DIAMOND := 6
const TERRAIN_FILL_TOPOLOGY_ADAPTIVE := 7
const TERRAIN_FILL_TOPOLOGY_QUADTREE_ERROR := 8
const TERRAIN_FILL_TOPOLOGY_LANE_FOLLOW := 9
const TERRAIN_FILL_TOPOLOGY_LOD_RINGS := 10
const TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY := 11
const TERRAIN_CUT_FILL_CUT_ONLY := 1
const TERRAIN_CUT_FILL_FILL_ONLY := 2
const TERRAIN_RECT_FILL_MAX_TRIANGLES := 2500000
const TERRAIN_FILL_GRID_MAX_TILES := 12000
const TERRAIN_FILL_RADIAL_MAX_CELLS := 16000
const TERRAIN_FILL_HEX_MAX_CELLS := 14000
const TERRAIN_FILL_DIAMOND_MAX_CELLS := 14000
const TERRAIN_FILL_QUADTREE_MAX_CELLS := 18000
const TERRAIN_FILL_DELAUNAY_MAX_POINTS := 6000
const TERRAIN_RECT_FILL_INTERIOR_MAX_POINTS_PER_POLYGON := 5000
var road_width := 6.0
var sample_step := 0.5
var y_offset := 0.0
var invert_faces := false
var terrain_fill_algorithm := 0
var terrain_fill_topology := 0
var terrain_fill_base_height := 0.0
var terrain_fill_height_match_epsilon := 0.05
var terrain_fill_height_match_max_distance := 0.2
var terrain_fill_height_assign_only := false
var terrain_fill_height_blend_falloff := 2.0
var terrain_fill_grid_tile_size := 8.0
var terrain_fill_radial_ring_count := 10
var terrain_fill_radial_sector_count := 36
var terrain_fill_hex_radius := 6.0
var terrain_fill_diamond_tile_size := 8.0
var terrain_fill_adaptive_max_depth := 3
var terrain_fill_adaptive_edge_factor := 0.8
var terrain_fill_adaptive_area_factor := 1.0
var terrain_fill_quadtree_max_depth := 5
var terrain_fill_quadtree_min_cell_size := 6.0
var terrain_fill_quadtree_error_threshold := 0.35
var terrain_fill_lane_follow_width := 24.0
var terrain_fill_lane_follow_bands := 3
var terrain_fill_lod_ring_count := 8
var terrain_fill_lod_band_growth := 1.4
var terrain_fill_lod_edge_step_near := 1.0
var terrain_fill_lod_edge_step_far := 8.0
var terrain_fill_delaunay_step_near := 1.0
var terrain_fill_delaunay_step_far := 7.0
var terrain_fill_delaunay_jitter := 0.2
var terrain_fill_outer_padding := 0.0
var terrain_rect_fill_cell_size := 1.0
var terrain_rect_fill_interior_point_step := 0.0
var terrain_rect_fill_road_margin := 0.0
var terrain_left_width := 0.0
var terrain_right_width := 0.0
var terrain_road_clearance := 0.02
var terrain_detection_width_scale := 1.0
var terrain_growth_scan_step := 0.25
var terrain_growth_max_delta_per_row := 1.25
var terrain_skirt_depth := 0.0
var terrain_skirt_segments := 3
var terrain_skirt_outward := 1.0
var terrain_skirt_profile := 1.4
var terrain_skirt_soften_slope_deg := 12.0
var terrain_skirt_soften_max_drop := 1.0
var terrain_skirt_soften_power := 1.2
var terrain_skirt_soften_area_rings := 3
var terrain_skirt_soften_area_falloff := 1.6
var terrain_skirt_soften_row_smooth_passes := 1
var terrain_subdivisions := 1
var terrain_adaptive_subdivisions_enabled := true
var terrain_adaptive_subdivisions_per_meter := 0.15
var terrain_adaptive_noise_quality := 1.5
var terrain_adaptive_subdivisions_max := 80
var terrain_noise_enabled := false
var terrain_noise_amplitude := 0.0
var terrain_noise_frequency := 0.06
var terrain_noise_seed := 1337
var terrain_noise_falloff := 1.5
var terrain_cut_fill_mode := 0
var terrain_artifact_safe_stitch := true
var terrain_chain_smooth_passes := 1
var uv_length_scale := 0.2
var _terrain_influence_strips: Array = []
var _terrain_influence_loops: Array = []

# Whole ordered strips are the fast path. Edited strips additionally reuse
# value-only stages with explicit width, neighbor, obstacle and center support.
const STRIP_CACHE_MAX_ENTRIES := 64
const STRIP_CACHE_MAX_PAYLOAD_BYTES := 64 * 1024 * 1024
const STRIP_CACHE_MAX_IDLE_BUILDS := 2
var incremental_generation_enabled := false
var last_stats: Dictionary = {
	"enabled": false, "strips_reused": 0, "strips_rebuilt": 0,
	"rows_reused": 0, "rows_rebuilt": 0, "growth_width_queries": 0,
	"vertices_reused": 0, "vertices_built": 0, "cache_entries": 0,
	"cache_payload_bytes": 0, "cache_evicted": 0,
	"growth_queries_reused": 0, "ring_rows_reused": 0, "ring_rows_rebuilt": 0,
	"chain_blend_rows_reused": 0, "chain_blend_rows_rebuilt": 0,
	"skirt_blend_rows_reused": 0, "skirt_blend_rows_rebuilt": 0,
	"skirt_columns_reused": 0, "skirt_columns_rebuilt": 0,
	"skirt_drops_reused": 0, "skirt_drops_rebuilt": 0, "stages": {},
	"fill_polygons_reused": 0, "fill_polygons_rebuilt": 0,
	"fill_triangles": 0,
	"fill_clips_reused": 0, "fill_clips_rebuilt": 0,
	"fill_heights_reused": 0, "fill_heights_rebuilt": 0,
	"nearest_queries_reused": 0, "nearest_queries_rebuilt": 0, "nearest_dependency_points": 0,
	"height_cell_points_checked": 0, "height_dependency_cells": 0, "height_regions_reused": 0,
}
var _strip_cache: Dictionary = {}
var _strip_cache_build := 0
var _strip_cache_payload_bytes := 0
var _strip_cache_clear_requested := false
var _stage_cache = preload("./terrain_stage_cache.gd").new()
var _height_snapshot := PackedByteArray()
var _height_revision := 0
var _height_cell_revision := 0
var _nearest_probes: Dictionary = {}

func configure(source: Node) -> void:
	_road = source
	road_width = source.get("road_width")
	sample_step = source.get("sample_step")
	y_offset = source.get("y_offset")
	invert_faces = bool(source.get("invert_faces"))
	terrain_fill_algorithm = source.get("terrain_fill_algorithm")
	terrain_fill_topology = source.get("terrain_fill_topology")
	terrain_fill_base_height = source.get("terrain_fill_base_height")
	terrain_fill_height_match_epsilon = source.get("terrain_fill_height_match_epsilon")
	terrain_fill_height_match_max_distance = source.get("terrain_fill_height_match_max_distance")
	terrain_fill_height_assign_only = source.get("terrain_fill_height_assign_only")
	terrain_fill_height_blend_falloff = source.get("terrain_fill_height_blend_falloff")
	terrain_fill_grid_tile_size = source.get("terrain_fill_grid_tile_size")
	terrain_fill_radial_ring_count = source.get("terrain_fill_radial_ring_count")
	terrain_fill_radial_sector_count = source.get("terrain_fill_radial_sector_count")
	terrain_fill_hex_radius = source.get("terrain_fill_hex_radius")
	terrain_fill_diamond_tile_size = source.get("terrain_fill_diamond_tile_size")
	terrain_fill_adaptive_max_depth = source.get("terrain_fill_adaptive_max_depth")
	terrain_fill_adaptive_edge_factor = source.get("terrain_fill_adaptive_edge_factor")
	terrain_fill_adaptive_area_factor = source.get("terrain_fill_adaptive_area_factor")
	terrain_fill_quadtree_max_depth = source.get("terrain_fill_quadtree_max_depth")
	terrain_fill_quadtree_min_cell_size = source.get("terrain_fill_quadtree_min_cell_size")
	terrain_fill_quadtree_error_threshold = source.get("terrain_fill_quadtree_error_threshold")
	terrain_fill_lane_follow_width = source.get("terrain_fill_lane_follow_width")
	terrain_fill_lane_follow_bands = source.get("terrain_fill_lane_follow_bands")
	terrain_fill_lod_ring_count = source.get("terrain_fill_lod_ring_count")
	terrain_fill_lod_band_growth = source.get("terrain_fill_lod_band_growth")
	terrain_fill_lod_edge_step_near = source.get("terrain_fill_lod_edge_step_near")
	terrain_fill_lod_edge_step_far = source.get("terrain_fill_lod_edge_step_far")
	terrain_fill_delaunay_step_near = source.get("terrain_fill_delaunay_step_near")
	terrain_fill_delaunay_step_far = source.get("terrain_fill_delaunay_step_far")
	terrain_fill_delaunay_jitter = source.get("terrain_fill_delaunay_jitter")
	terrain_fill_outer_padding = source.get("terrain_fill_outer_padding")
	terrain_rect_fill_cell_size = source.get("terrain_rect_fill_cell_size")
	terrain_rect_fill_interior_point_step = source.get("terrain_rect_fill_interior_point_step")
	terrain_rect_fill_road_margin = source.get("terrain_rect_fill_road_margin")
	terrain_left_width = source.get("terrain_left_width")
	terrain_right_width = source.get("terrain_right_width")
	terrain_road_clearance = source.get("terrain_road_clearance")
	terrain_detection_width_scale = source.get("terrain_detection_width_scale")
	terrain_growth_scan_step = source.get("terrain_growth_scan_step")
	terrain_growth_max_delta_per_row = source.get("terrain_growth_max_delta_per_row")
	terrain_skirt_depth = source.get("terrain_skirt_depth")
	terrain_skirt_segments = source.get("terrain_skirt_segments")
	terrain_skirt_outward = source.get("terrain_skirt_outward")
	terrain_skirt_profile = source.get("terrain_skirt_profile")
	terrain_skirt_soften_slope_deg = source.get("terrain_skirt_soften_slope_deg")
	terrain_skirt_soften_max_drop = source.get("terrain_skirt_soften_max_drop")
	terrain_skirt_soften_power = source.get("terrain_skirt_soften_power")
	terrain_skirt_soften_area_rings = source.get("terrain_skirt_soften_area_rings")
	terrain_skirt_soften_area_falloff = source.get("terrain_skirt_soften_area_falloff")
	terrain_skirt_soften_row_smooth_passes = source.get("terrain_skirt_soften_row_smooth_passes")
	terrain_subdivisions = source.get("terrain_subdivisions")
	terrain_adaptive_subdivisions_enabled = source.get("terrain_adaptive_subdivisions_enabled")
	terrain_adaptive_subdivisions_per_meter = source.get("terrain_adaptive_subdivisions_per_meter")
	terrain_adaptive_noise_quality = source.get("terrain_adaptive_noise_quality")
	terrain_adaptive_subdivisions_max = source.get("terrain_adaptive_subdivisions_max")
	terrain_noise_enabled = source.get("terrain_noise_enabled")
	terrain_noise_amplitude = source.get("terrain_noise_amplitude")
	terrain_noise_frequency = source.get("terrain_noise_frequency")
	terrain_noise_seed = source.get("terrain_noise_seed")
	terrain_noise_falloff = source.get("terrain_noise_falloff")
	terrain_cut_fill_mode = source.get("terrain_cut_fill_mode")
	terrain_artifact_safe_stitch = source.get("terrain_artifact_safe_stitch")
	terrain_chain_smooth_passes = source.get("terrain_chain_smooth_passes")
	uv_length_scale = source.get("uv_length_scale")
	_terrain_influence_strips = source.get("_terrain_influence_strips")
	_terrain_influence_loops = source.get("_terrain_influence_loops")
	incremental_generation_enabled = bool(source.get("incremental_generation_enabled"))
	_begin_strip_cache_build()


func _begin_strip_cache_build() -> void:
	_strip_cache_build += 1
	last_stats = {
		"enabled": incremental_generation_enabled and terrain_fill_algorithm == 0,
		"strips_reused": 0, "strips_rebuilt": 0, "rows_reused": 0,
		"rows_rebuilt": 0, "growth_width_queries": 0, "vertices_reused": 0,
		"vertices_built": 0, "cache_entries": 0, "cache_payload_bytes": 0,
		"cache_evicted": 0,
		"growth_queries_reused": 0, "ring_rows_reused": 0, "ring_rows_rebuilt": 0,
		"chain_blend_rows_reused": 0, "chain_blend_rows_rebuilt": 0,
		"skirt_blend_rows_reused": 0, "skirt_blend_rows_rebuilt": 0,
		"skirt_columns_reused": 0, "skirt_columns_rebuilt": 0,
		"skirt_drops_reused": 0, "skirt_drops_rebuilt": 0,
		"fill_polygons_reused": 0, "fill_polygons_rebuilt": 0,
		"fill_triangles": 0,
		"fill_clips_reused": 0, "fill_clips_rebuilt": 0,
		"fill_heights_reused": 0, "fill_heights_rebuilt": 0,
		"nearest_queries_reused": 0, "nearest_queries_rebuilt": 0, "nearest_dependency_points": 0,
		"height_cell_points_checked": 0, "height_dependency_cells": 0, "height_regions_reused": 0,
	}
	if not incremental_generation_enabled or _strip_cache_clear_requested:
		_nearest_probes.clear()
		_height_snapshot = PackedByteArray()
	_stage_cache.configure(incremental_generation_enabled, _strip_cache_clear_requested)
	if _strip_cache_clear_requested or not bool(last_stats["enabled"]):
		_strip_cache.clear()
		_strip_cache_payload_bytes = 0
		_strip_cache_clear_requested = false
	else:
		for key in _strip_cache.keys():
			if _strip_cache_build - int(_strip_cache[key]["build"]) > STRIP_CACHE_MAX_IDLE_BUILDS:
				_evict_strip_cache_entry(key)
	_update_strip_cache_stats()


## Safe during a worker-owned generation: configure consumes the flag only
## after the coordinator has joined that worker. Do not clear its dictionary
## concurrently with strip construction/replay.
func request_incremental_cache_clear() -> void:
	_strip_cache_clear_requested = true


## Main-thread only, after joining any worker that owns this builder.
func clear_incremental_cache() -> void:
	_strip_cache.clear()
	_stage_cache.clear()
	_nearest_probes.clear()
	_height_snapshot = PackedByteArray()
	_strip_cache_payload_bytes = 0
	_strip_cache_clear_requested = false
	_update_strip_cache_stats()


func _update_strip_cache_stats() -> void:
	last_stats["cache_entries"] = _strip_cache.size()
	last_stats["cache_payload_bytes"] = _strip_cache_payload_bytes
	last_stats["stages"] = _stage_cache.stats


func _evict_strip_cache_entry(key: String) -> void:
	_strip_cache_payload_bytes -= int(_strip_cache[key]["payload_bytes"])
	_strip_cache.erase(key)
	last_stats["cache_evicted"] += 1


func _strip_cache_settings() -> Array:
	return [
		terrain_road_clearance, terrain_detection_width_scale, terrain_growth_scan_step,
		terrain_growth_max_delta_per_row, terrain_skirt_depth, terrain_skirt_segments,
		terrain_skirt_outward, terrain_skirt_profile, terrain_skirt_soften_slope_deg,
		terrain_skirt_soften_max_drop, terrain_skirt_soften_power,
		terrain_skirt_soften_area_rings, terrain_skirt_soften_area_falloff,
		terrain_skirt_soften_row_smooth_passes, terrain_subdivisions,
		terrain_adaptive_subdivisions_enabled, terrain_adaptive_subdivisions_per_meter,
		terrain_adaptive_noise_quality, terrain_adaptive_subdivisions_max,
		terrain_noise_enabled, terrain_noise_amplitude, terrain_noise_frequency,
		terrain_noise_seed, terrain_noise_falloff, terrain_cut_fill_mode,
		terrain_artifact_safe_stitch, terrain_chain_smooth_passes, uv_length_scale,
		invert_faces,
	]


func _make_strip_cache_query(
	verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
	rows: Array, blocked_side_vertices: Dictionary, road_tris: Array
) -> Dictionary:
	if not incremental_generation_enabled or terrain_fill_algorithm != 0:
		return {}
	var base_ids := PackedInt32Array()
	var base_to_local: Dictionary = {}
	var base_vertices := PackedVector3Array()
	var base_normals := PackedVector3Array()
	var base_uvs := PackedVector2Array()
	var base_blocked := PackedByteArray()
	var row_support: Array = []
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var max_width := 0.001
	for row_raw in rows:
		var row: Dictionary = row_raw
		var edges: Array = row.get("row_edges", [])
		if edges.size() < 6:
			# Invalid rows keep the original recovery behavior without caching.
			return {}
		var local_edges := PackedInt32Array()
		for id_raw in edges:
			var id := int(id_raw)
			if id < 0 or id >= verts.size() or id >= normals.size() or id >= uvs.size():
				return {}
			if not base_to_local.has(id):
				var p := verts[id]
				if not p.is_finite():
					return {}
				base_to_local[id] = base_ids.size()
				base_ids.append(id)
				base_vertices.append(p)
				base_normals.append(normals[id])
				base_uvs.append(uvs[id])
				base_blocked.append(int(blocked_side_vertices.has(id)))
				min_v = min_v.min(Vector2(p.x, p.z))
				max_v = max_v.max(Vector2(p.x, p.z))
			local_edges.append(int(base_to_local[id]))
		var left_width := maxf(0.0, float(row.get("terrain_left_width", terrain_left_width)))
		var right_width := maxf(0.0, float(row.get("terrain_right_width", terrain_right_width)))
		if not is_finite(left_width) or not is_finite(right_width):
			return {}
		max_width = maxf(max_width, maxf(left_width, right_width))
		row_support.append([local_edges, row.get("out_dir", Vector3.FORWARD), left_width, right_width])
	# Only growth validation queries road_tris: it tests candidate points, their
	# connecting segment and the base-to-outer quad. All are within source bounds
	# expanded by requested width (growth never exceeds it), plus clearance/inset.
	# Earlier-edge tests use this entire path's base arrays, already in the key.
	# There is no nearest-height/global-nearest query in the path-strip pipeline.
	# Extra padding makes this deliberately conservative under float rounding.
	var padding := max_width * 1.01 + maxf(0.0, terrain_road_clearance) + 1.0
	min_v -= Vector2.ONE * padding
	max_v += Vector2.ONE * padding
	if not min_v.is_finite() or not max_v.is_finite():
		return {}
	var nearby_road_support := PackedVector2Array()
	for tri in road_tris:
		var tri_min: Vector2 = tri["min"]
		var tri_max: Vector2 = tri["max"]
		if tri_max.x < min_v.x or tri_min.x > max_v.x or tri_max.y < min_v.y or tri_min.y > max_v.y:
			continue
		nearby_road_support.append(tri["a"])
		nearby_road_support.append(tri["b"])
		nearby_road_support.append(tri["c"])
	var input_bytes := var_to_bytes([
		_strip_cache_settings(), base_vertices, base_normals, base_uvs,
		base_blocked, row_support, nearby_road_support,
	])
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(input_bytes)
	return {"key": digest.finish().hex_encode(), "input": input_bytes, "base_ids": base_ids, "base_to_local": base_to_local}


func _replay_strip_cache(
	query: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, terrain_indices: PackedInt32Array
) -> bool:
	if query.is_empty() or not _strip_cache.has(query["key"]):
		return false
	var entry: Dictionary = _strip_cache[query["key"]]
	if entry["input"] != query["input"]:
		return false
	_stage_cache.touch_group(entry.get("stage_keys", PackedStringArray()))
	var base_ids: PackedInt32Array = query["base_ids"]
	var base_vertices: PackedVector3Array = entry["base_vertices"]
	var base_normals: PackedVector3Array = entry["base_normals"]
	var base_uvs: PackedVector2Array = entry["base_uvs"]
	# Skirt softening can reach ring 0. Apply its base-road changes in the same
	# path order as a full build, before the next path captures its own inputs.
	for i in range(base_ids.size()):
		verts[base_ids[i]] = base_vertices[i]
		normals[base_ids[i]] = base_normals[i]
		uvs[base_ids[i]] = base_uvs[i]
	var append_start := verts.size()
	verts.append_array(entry["vertices"])
	normals.append_array(entry["normals"])
	uvs.append_array(entry["uvs"])
	for local_id in entry["indices"]:
		terrain_indices.append(base_ids[-local_id - 1] if local_id < 0 else append_start + local_id)
	entry["build"] = _strip_cache_build
	_strip_cache.erase(query["key"])
	_strip_cache[query["key"]] = entry
	last_stats["vertices_reused"] += entry["vertices"].size()
	return true


func _store_strip_cache(
	query: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, terrain_indices: PackedInt32Array,
	vertex_start: int, index_start: int
) -> void:
	if query.is_empty():
		return
	var base_ids: PackedInt32Array = query["base_ids"]
	var base_to_local: Dictionary = query["base_to_local"]
	var indices := PackedInt32Array()
	for index in terrain_indices.slice(index_start):
		if index < vertex_start:
			if not base_to_local.has(index):
				return
			indices.append(-int(base_to_local[index]) - 1)
		else:
			indices.append(index - vertex_start)
	var base_vertices := PackedVector3Array()
	var base_normals := PackedVector3Array()
	var base_uvs := PackedVector2Array()
	for id in base_ids:
		base_vertices.append(verts[id])
		base_normals.append(normals[id])
		base_uvs.append(uvs[id])
	var new_vertices := verts.slice(vertex_start)
	var new_normals := normals.slice(vertex_start)
	var new_uvs := uvs.slice(vertex_start)
	var payload_bytes: int = query["input"].size() + indices.size() * 4 + (new_vertices.size() + base_ids.size()) * 32
	var stage_keys: PackedStringArray = _stage_cache.group_keys()
	payload_bytes += stage_keys.size() * 64
	if payload_bytes > STRIP_CACHE_MAX_PAYLOAD_BYTES:
		return
	var key: String = query["key"]
	if _strip_cache.has(key):
		_evict_strip_cache_entry(key)
	_strip_cache[key] = {
		"input": query["input"], "base_vertices": base_vertices,
		"base_normals": base_normals, "base_uvs": base_uvs,
		"vertices": new_vertices, "normals": new_normals, "uvs": new_uvs,
		"indices": indices, "build": _strip_cache_build, "payload_bytes": payload_bytes,
		"stage_keys": stage_keys,
	}
	_strip_cache_payload_bytes += payload_bytes
	while _strip_cache.size() > STRIP_CACHE_MAX_ENTRIES or _strip_cache_payload_bytes > STRIP_CACHE_MAX_PAYLOAD_BYTES:
		_evict_strip_cache_entry(_strip_cache.keys()[0])
	_update_strip_cache_stats()


func _append_terrain_with_mode(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	if terrain_fill_algorithm == TERRAIN_FILL_RECTANGLE:
		var profile_rect_start := _profile_start()
		var rect_vert_start := verts.size()
		var rect_normal_start := normals.size()
		var rect_uv_start := uvs.size()
		var rect_terrain_start := terrain_indices.size()
		_append_terrain_from_rect_fill(
			verts,
			normals,
			uvs,
			terrain_indices,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			path_rows,
			cancel_token
		)
		_profile_log("terrain mode rectangle fill", profile_rect_start, "tris=%s" % [maxi(0, (terrain_indices.size() - rect_terrain_start) / 3)])
		_debug_log(
			"rect fill terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - rect_terrain_start) / 3)]
		)
		if terrain_indices.size() > rect_terrain_start:
			return
		if _is_generation_cancelled(cancel_token):
			return
		verts.resize(rect_vert_start)
		normals.resize(rect_normal_start)
		uvs.resize(rect_uv_start)
		_debug_log("rect fill produced 0 terrain tris, fallback to path-row terrain")

	if terrain_fill_algorithm == TERRAIN_FILL_BOOLEAN:
		var profile_boolean_start := _profile_start()
		var vert_start := verts.size()
		var normal_start := normals.size()
		var uv_start := uvs.size()
		var terrain_start := terrain_indices.size()
		_append_terrain_from_boolean_fill(
			verts,
			normals,
			uvs,
			terrain_indices,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			path_rows,
			cancel_token
		)
		_profile_log("terrain mode boolean fill", profile_boolean_start, "tris=%s" % [maxi(0, (terrain_indices.size() - terrain_start) / 3)])
		_debug_log(
			"boolean fill terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - terrain_start) / 3)]
		)
		if terrain_indices.size() > terrain_start:
			return
		if _is_generation_cancelled(cancel_token):
			return
		# Boolean fallback: if subtraction produced no terrain, restore buffers and
		# build terrain with the stable row-based method.
		verts.resize(vert_start)
		normals.resize(normal_start)
		uvs.resize(uv_start)
		_debug_log("boolean fill produced 0 terrain tris, fallback to path-row terrain")
		var fb_vert_start := verts.size()
		var fb_normal_start := normals.size()
		var fb_uv_start := uvs.size()
		var profile_path_fallback_start := _profile_start()
		_append_terrain_from_path_rows(
			verts,
			normals,
			uvs,
			terrain_indices,
			path_rows,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			blocked_side_vertices,
			cancel_token
		)
		_profile_log("terrain mode path-row fallback", profile_path_fallback_start, "tris=%s" % [maxi(0, (terrain_indices.size() - terrain_start) / 3)])
		_debug_log(
			"path-row fallback terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - terrain_start) / 3)]
		)
		if terrain_indices.size() > terrain_start:
			return
		if _is_generation_cancelled(cancel_token):
			return
		verts.resize(fb_vert_start)
		normals.resize(fb_normal_start)
		uvs.resize(fb_uv_start)
		var emergency_width := clampf(maxf(2.5, road_width * 0.9), 2.0, 14.0)
		var emergency_rows := _path_rows_with_emergency_terrain_widths(path_rows, emergency_width)
		_debug_log("path-row fallback still 0, retry with emergency width=%s and unblocked sides" % [emergency_width])
		var saved_terrain_subdivisions := terrain_subdivisions
		var emergency_subdivisions := clampi(saved_terrain_subdivisions, 1, 8)
		if emergency_subdivisions != saved_terrain_subdivisions:
			terrain_subdivisions = emergency_subdivisions
			_debug_log(
				"emergency fallback uses reduced terrain_subdivisions=%s (from %s)"
				% [emergency_subdivisions, saved_terrain_subdivisions]
			)
		var profile_emergency_start := _profile_start()
		_append_terrain_from_path_rows(
			verts,
			normals,
			uvs,
			terrain_indices,
			emergency_rows,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			{},
			cancel_token
		)
		_profile_log("terrain mode emergency path-row fallback", profile_emergency_start, "tris=%s" % [maxi(0, (terrain_indices.size() - terrain_start) / 3)])
		terrain_subdivisions = saved_terrain_subdivisions
		_debug_log(
			"emergency fallback terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - terrain_start) / 3)]
		)
		return
	var profile_path_rows_start := _profile_start()
	_append_terrain_from_path_rows(
		verts,
		normals,
		uvs,
		terrain_indices,
		path_rows,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		blocked_side_vertices,
		cancel_token
	)
	_profile_log("terrain mode path rows", profile_path_rows_start, "terrain_tris=%s" % [terrain_indices.size() / 3])


func _path_rows_with_emergency_terrain_widths(path_rows: Array, width: float) -> Array:
	var out: Array = []
	var safe_width := maxf(0.0, width)
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		var rows_copy: Array = []
		for row_raw in rows:
			var row: Dictionary = row_raw
			var row_copy := row.duplicate(true)
			var left_w := maxf(0.0, float(row_copy.get("terrain_left_width", 0.0)))
			var right_w := maxf(0.0, float(row_copy.get("terrain_right_width", 0.0)))
			if left_w <= 0.0001:
				row_copy["terrain_left_width"] = safe_width
			if right_w <= 0.0001:
				row_copy["terrain_right_width"] = safe_width
			rows_copy.push_back(row_copy)
		out.push_back(rows_copy)
	return out


func _append_terrain_from_rect_fill(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array,
	cancel_token: Dictionary = {}
) -> void:
	var profile_total_start := _profile_start()
	var profile_boundary_start := _profile_start()
	var boundary_data := _extract_road_boundary_loops_xz(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	var mesh_road_loops_all: Array = boundary_data.get("loops", [])
	var boundary_points: Array = boundary_data.get("points", [])
	_append_terrain_influence_boundary_points(boundary_points)
	_profile_log("rect fill extract boundaries", profile_boundary_start, "loops=%s points=%s" % [mesh_road_loops_all.size(), boundary_points.size()])
	if boundary_points.is_empty():
		return

	var profile_parts_start := _profile_start()
	var road_loops := _build_path_row_boundary_polygons_xz_mode(verts, path_rows, false)
	var influence_loops: Array = []
	for loop_raw in _terrain_influence_loops:
		var loop: PackedVector2Array = _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() >= 3:
			influence_loops.push_back(loop)
	var boundary_source := "path-rows"
	if road_loops.is_empty():
		road_loops = mesh_road_loops_all
		boundary_source = "all-surfaces"
	if not influence_loops.is_empty():
		boundary_source += "+influence"
	if road_loops.is_empty() and influence_loops.is_empty() and _terrain_influence_strips.is_empty():
		return
	if road_loops.is_empty() and not influence_loops.is_empty():
		boundary_source = "influence-only"

	var road_margin := maxf(0.0, terrain_rect_fill_road_margin)
	var road_parts: Array = []
	for loop_raw in road_loops:
		var loop: PackedVector2Array = _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() < 3:
			continue
		if road_margin > 0.0001:
			var offset_parts: Array = _stage_cache.polygon_offset(loop, road_margin)
			if not offset_parts.is_empty():
				loop = _pick_largest_polygon_part_xz(offset_parts)
			loop = _compact_polygon2d_xz(loop, 0.001)
		if loop.size() < 3:
			continue
		road_parts.push_back(loop)
	var influence_parts := influence_loops
	var road_clip_parts := _build_effective_road_clip_parts(road_parts)

	var fill_parts := _build_outer_rect_fill_parts_from_road_parts(road_parts, boundary_points, cancel_token)
	_profile_log("rect fill build fill parts", profile_parts_start, "fill_parts=%s road_parts=%s influence_parts=%s" % [fill_parts.size(), road_parts.size(), influence_parts.size()])
	if fill_parts.is_empty():
		return
	var profile_clip_start := _profile_start()
	for part_raw in road_clip_parts:
		var part: PackedVector2Array = part_raw
		if part.size() < 3:
			continue
		fill_parts = _clip_fill_parts_by_polygon(fill_parts, part, cancel_token)
		if fill_parts.is_empty():
			break
		if _is_generation_cancelled(cancel_token):
			return
	for part_raw in influence_parts:
		var part: PackedVector2Array = part_raw
		if part.size() < 3:
			continue
		fill_parts = _clip_fill_parts_by_polygon(fill_parts, part, cancel_token)
		if fill_parts.is_empty():
			break
		if _is_generation_cancelled(cancel_token):
			return
	if fill_parts.is_empty():
		return
	_profile_log("rect fill clipping", profile_clip_start, "fill_parts=%s road_clip_parts=%s influence_parts=%s" % [fill_parts.size(), road_clip_parts.size(), influence_parts.size()])

	var profile_height_lookup_start := _profile_start()
	var snap_eps := maxf(0.0001, terrain_fill_height_match_epsilon)
	var base_y := terrain_fill_base_height + y_offset
	var boundary_height_map: Dictionary = {}
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var key := Vector2i(int(round(p.x / snap_eps)), int(round(p.z / snap_eps)))
		var sum_and_count: Array = boundary_height_map.get(key, [0.0, 0])
		sum_and_count[0] = float(sum_and_count[0]) + p.y
		sum_and_count[1] = int(sum_and_count[1]) + 1
		boundary_height_map[key] = sum_and_count
	var boundary_height_lookup := _build_boundary_height_lookup(boundary_points)
	_profile_log("rect fill height lookup", profile_height_lookup_start, "height_cells=%s" % [boundary_height_map.size()])

	var heightmap_image := _build_fill_heightmap_image()
	var base_edge_len := maxf(0.2, terrain_rect_fill_cell_size)
	var tri_limit := TERRAIN_RECT_FILL_MAX_TRIANGLES
	var tri_stats := {
		"tri_candidates": 0,
		"tri_kept": 0,
	}
	var fill_vertex_height_cache: Dictionary = {}
	var fill_vertex_index_cache: Dictionary = {}
	var edge_midpoint_height_cache: Dictionary = {}
	var limit_reached := false
	var profile_triangulate_start := _profile_start()
	for poly_raw in fill_parts:
		if _is_generation_cancelled(cancel_token):
			return
		if limit_reached:
			break
		var poly: PackedVector2Array = _compact_polygon2d_xz(poly_raw, 0.001)
		if poly.size() < 3:
			continue
		var root_tris := _triangulate_fill_polygon_for_rect_mode(poly, base_edge_len, cancel_token)
		if root_tris.is_empty():
			continue
		var max_conform_iters := 1
		for _iter in range(max_conform_iters):
			var changed := false
			for tri_raw in root_tris:
				if _is_generation_cancelled(cancel_token):
					return
				var tri: PackedVector2Array = tri_raw
				if tri.size() < 3:
					continue
				if _precompute_fill_split_edges(
					tri[0],
					tri[1],
					tri[2],
					boundary_height_map,
					boundary_points,
					base_y,
					road_parts,
					heightmap_image,
					base_edge_len,
					edge_midpoint_height_cache,
					0,
					boundary_height_lookup
				):
					changed = true
			if not changed:
				break

		for tri_raw in root_tris:
			if _is_generation_cancelled(cancel_token):
				return
			if int(tri_stats.get("tri_kept", 0)) >= tri_limit:
				limit_reached = true
				break
			var tri: PackedVector2Array = tri_raw
			if tri.size() < 3:
				continue
			var pa2: Vector2 = tri[0]
			var pb2: Vector2 = tri[1]
			var pc2: Vector2 = tri[2]
			var y_a := _sample_fill_vertex_height_cached(pa2, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)
			var y_b := _sample_fill_vertex_height_cached(pb2, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)
			var y_c := _sample_fill_vertex_height_cached(pc2, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)
			_append_fill_triangle_adaptive(
				pa2,
				pb2,
				pc2,
				verts,
				normals,
				uvs,
				terrain_indices,
				boundary_height_map,
				boundary_points,
				base_y,
				road_parts,
				heightmap_image,
				y_a,
				y_b,
				y_c,
				base_edge_len,
				tri_limit,
				tri_stats,
				edge_midpoint_height_cache,
				fill_vertex_index_cache,
				0,
				boundary_height_lookup
			)
			if int(tri_stats.get("tri_kept", 0)) >= tri_limit:
				limit_reached = true
				break

	last_stats.fill_triangles += int(tri_stats.get("tri_kept", 0))
	_profile_log("rect fill triangulate+append", profile_triangulate_start, "candidates=%s kept=%s cached_heights=%s cached_verts=%s limit=%s" % [int(tri_stats.get("tri_candidates", 0)), int(tri_stats.get("tri_kept", 0)), fill_vertex_height_cache.size(), fill_vertex_index_cache.size(), limit_reached])
	_debug_log(
		"rect fill source=%s parts=%s area=%.2f candidates=%s kept=%s clip_mode=%s"
		% [
			boundary_source,
			fill_parts.size(),
			_polygon_parts_total_area_abs_xz(fill_parts),
			int(tri_stats.get("tri_candidates", 0)),
			int(tri_stats.get("tri_kept", 0)),
			"outer"
		]
	)
	_profile_log("rect fill total", profile_total_start, "terrain_tris=%s" % [terrain_indices.size() / 3])


func _append_terrain_from_boolean_fill(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array,
	cancel_token: Dictionary = {}
) -> void:
	var profile_total_start := _profile_start()
	var boundary_source := "path-rows"
	var profile_boundary_start := _profile_start()
	var boundary_data := _extract_road_boundary_loops_xz(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	var mesh_road_loops: Array = boundary_data.get("loops", [])
	var boundary_points: Array = boundary_data.get("points", [])
	_append_terrain_influence_boundary_points(boundary_points)
	_profile_log("boolean fill extract boundaries", profile_boundary_start, "loops=%s points=%s" % [mesh_road_loops.size(), boundary_points.size()])
	var profile_parts_start := _profile_start()
	var road_loops := _build_path_row_boundary_polygons_xz(verts, path_rows)
	var influence_loops: Array = []
	for loop_raw in _terrain_influence_loops:
		var loop: PackedVector2Array = _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() >= 3:
			influence_loops.push_back(loop)
	if road_loops.is_empty():
		road_loops = mesh_road_loops
		boundary_source = "all-surfaces"
	if not influence_loops.is_empty():
		boundary_source += "+influence"
	if boundary_points.is_empty():
		return
	if road_loops.is_empty() and influence_loops.is_empty() and _terrain_influence_strips.is_empty():
		return
	if road_loops.is_empty() and not influence_loops.is_empty():
		boundary_source = "influence-only"
	_debug_log(
		"boolean fill boundary source=%s loops=%s clip_mode=%s"
		% [
			boundary_source,
			road_loops.size() + influence_loops.size(),
			"outer"
		]
	)

	var road_parts: Array = []
	for loop_raw in road_loops:
		var loop: PackedVector2Array = _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() < 3:
			continue
		road_parts.push_back(loop)
	var influence_parts := influence_loops
	var road_clip_parts := _build_effective_road_clip_parts(road_parts)

	var fill_parts := _build_outer_rect_fill_parts_from_road_parts(road_parts, boundary_points, cancel_token)
	_profile_log("boolean fill build fill parts", profile_parts_start, "fill_parts=%s road_parts=%s influence_parts=%s" % [fill_parts.size(), road_parts.size(), influence_parts.size()])
	if fill_parts.is_empty():
		return
	var profile_clip_start := _profile_start()
	for part_raw in road_clip_parts:
		var part: PackedVector2Array = part_raw
		if part.size() < 3:
			continue
		fill_parts = _clip_fill_parts_by_polygon(fill_parts, part, cancel_token)
		if fill_parts.is_empty():
			break
		if _is_generation_cancelled(cancel_token):
			return
	for part_raw in influence_parts:
		var part: PackedVector2Array = part_raw
		if part.size() < 3:
			continue
		fill_parts = _clip_fill_parts_by_polygon(fill_parts, part, cancel_token)
		if fill_parts.is_empty():
			break
		if _is_generation_cancelled(cancel_token):
			return
	_profile_log("boolean fill clipping", profile_clip_start, "fill_parts=%s road_clip_parts=%s influence_parts=%s" % [fill_parts.size(), road_clip_parts.size(), influence_parts.size()])
	_debug_log(
		"boolean fill clipped parts=%s area=%.2f road_parts=%s"
		% [fill_parts.size(), _polygon_parts_total_area_abs_xz(fill_parts), road_parts.size()]
	)

	var profile_height_lookup_start := _profile_start()
	var snap_eps := maxf(0.0001, terrain_fill_height_match_epsilon)
	var boundary_height_map: Dictionary = {}
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var key := Vector2i(int(round(p.x / snap_eps)), int(round(p.z / snap_eps)))
		var sum_and_count: Array = boundary_height_map.get(key, [0.0, 0])
		sum_and_count[0] = float(sum_and_count[0]) + p.y
		sum_and_count[1] = int(sum_and_count[1]) + 1
		boundary_height_map[key] = sum_and_count
	var boundary_height_lookup := _build_boundary_height_lookup(boundary_points)
	_profile_log("boolean fill height lookup", profile_height_lookup_start, "height_cells=%s" % [boundary_height_map.size()])

	var heightmap_image := _build_fill_heightmap_image()
	var base_y := terrain_fill_base_height + y_offset
	var base_edge_len := maxf(1.0, road_width * 0.35)
	var tri_limit := TERRAIN_RECT_FILL_MAX_TRIANGLES
	var tri_stats := {
		"tri_candidates": 0,
		"tri_kept": 0,
	}
	var fill_vertex_height_cache: Dictionary = {}
	var fill_vertex_index_cache: Dictionary = {}
	var edge_midpoint_height_cache: Dictionary = {}
	var limit_reached := false
	var profile_triangulate_start := _profile_start()
	for poly_raw in fill_parts:
		if _is_generation_cancelled(cancel_token):
			return
		if limit_reached:
			break
		var poly: PackedVector2Array = _compact_polygon2d_xz(poly_raw, 0.001)
		if poly.size() < 3:
			continue
		var root_tris := _triangulate_fill_polygon_for_rect_mode(poly, base_edge_len, cancel_token)
		if root_tris.is_empty():
			continue
		var max_conform_iters := 1
		for _iter in range(max_conform_iters):
			var changed := false
			for tri_raw in root_tris:
				if _is_generation_cancelled(cancel_token):
					return
				var tri: PackedVector2Array = tri_raw
				if tri.size() < 3:
					continue
				if _precompute_fill_split_edges(
					tri[0],
					tri[1],
					tri[2],
					boundary_height_map,
					boundary_points,
					base_y,
					road_parts,
					heightmap_image,
					base_edge_len,
					edge_midpoint_height_cache,
					0,
					boundary_height_lookup
				):
					changed = true
			if not changed:
				break

		for tri_raw in root_tris:
			if _is_generation_cancelled(cancel_token):
				return
			if int(tri_stats.get("tri_kept", 0)) >= tri_limit:
				limit_reached = true
				break
			var tri: PackedVector2Array = tri_raw
			if tri.size() < 3:
				continue
			var pa2: Vector2 = tri[0]
			var pb2: Vector2 = tri[1]
			var pc2: Vector2 = tri[2]
			var y_a := _sample_fill_vertex_height_cached(pa2, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)
			var y_b := _sample_fill_vertex_height_cached(pb2, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)
			var y_c := _sample_fill_vertex_height_cached(pc2, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)
			_append_fill_triangle_adaptive(
				pa2,
				pb2,
				pc2,
				verts,
				normals,
				uvs,
				terrain_indices,
				boundary_height_map,
				boundary_points,
				base_y,
				road_parts,
				heightmap_image,
				y_a,
				y_b,
				y_c,
				base_edge_len,
				tri_limit,
				tri_stats,
				edge_midpoint_height_cache,
				fill_vertex_index_cache,
				0,
				boundary_height_lookup
			)
			if int(tri_stats.get("tri_kept", 0)) >= tri_limit:
				limit_reached = true
				break
	last_stats.fill_triangles += int(tri_stats.get("tri_kept", 0))
	_profile_log("boolean fill triangulate+append", profile_triangulate_start, "candidates=%s kept=%s cached_heights=%s cached_verts=%s limit=%s" % [int(tri_stats.get("tri_candidates", 0)), int(tri_stats.get("tri_kept", 0)), fill_vertex_height_cache.size(), fill_vertex_index_cache.size(), limit_reached])
	_debug_log(
		"boolean fill tris candidates=%s kept=%s"
		% [
			int(tri_stats.get("tri_candidates", 0)),
			int(tri_stats.get("tri_kept", 0))
		]
	)
	_profile_log("boolean fill total", profile_total_start, "terrain_tris=%s" % [terrain_indices.size() / 3])


func _extract_road_boundary_loops_xz(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array
) -> Dictionary:
	var edge_counts: Dictionary = {}
	_count_boundary_edges_from_surface(lane_indices, edge_counts)
	_count_boundary_edges_from_surface(shoulder_indices, edge_counts)
	_count_boundary_edges_from_surface(sidewalk_indices, edge_counts)

	var adjacency: Dictionary = {}
	var boundary_keys: Array = []
	for key_raw in edge_counts.keys():
		var key := str(key_raw)
		if int(edge_counts.get(key, 0)) != 1:
			continue
		var edge := _edge_key_to_indices(key)
		if edge.x < 0 or edge.y < 0:
			continue
		boundary_keys.push_back(key)
		_append_boundary_neighbor(adjacency, edge.x, edge.y)
		_append_boundary_neighbor(adjacency, edge.y, edge.x)

	var visited: Dictionary = {}
	for key in boundary_keys:
		visited[key] = false

	var loops: Array = []
	var boundary_points: Array = []
	var boundary_segments: Array = []
	var boundary_resample_step := maxf(0.05, minf(sample_step * 0.5, maxf(0.05, terrain_rect_fill_cell_size * 0.5)))
	var boundary_point_cap := 180000
	for start_key in boundary_keys:
		if bool(visited.get(start_key, false)):
			continue
		var start_edge := _edge_key_to_indices(start_key)
		if start_edge.x < 0 or start_edge.y < 0:
			continue

		var chain: Array = [start_edge.x, start_edge.y]
		visited[start_key] = true
		var current := start_edge.y
		var closed := false
		var safety := 0
		while safety < 100000:
			safety += 1
			var neighbors: Array = adjacency.get(current, [])
			var next_idx := -1
			for n_raw in neighbors:
				var n := int(n_raw)
				var edge_key := _edge_key_from_indices(current, n)
				if bool(visited.get(edge_key, false)):
					continue
				next_idx = n
				break
			if next_idx < 0:
				break
			visited[_edge_key_from_indices(current, next_idx)] = true
			if next_idx == chain[0]:
				closed = true
				break
			chain.push_back(next_idx)
			current = next_idx
			if chain.size() > 65535:
				break
		if not closed or chain.size() < 3:
			continue

		var poly := PackedVector2Array()
		var chain_points_3d := PackedVector3Array()
		for vid_raw in chain:
			var vid := int(vid_raw)
			if vid < 0 or vid >= verts.size():
				continue
			var p3: Vector3 = verts[vid]
			poly.push_back(Vector2(p3.x, p3.z))
			boundary_points.push_back(p3)
			chain_points_3d.push_back(p3)
		poly = _compact_polygon2d_xz(poly, 0.001)
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		loops.push_back(poly)
		if chain_points_3d.size() >= 2:
			for i in range(chain_points_3d.size()):
				var a3: Vector3 = chain_points_3d[i]
				var b3: Vector3 = chain_points_3d[(i + 1) % chain_points_3d.size()]
				if Vector2(a3.x, a3.z).distance_to(Vector2(b3.x, b3.z)) <= 0.0001:
					continue
				boundary_segments.push_back({"a": a3, "b": b3})
		if chain_points_3d.size() >= 2 and boundary_points.size() < boundary_point_cap:
			for i in range(chain_points_3d.size()):
				if boundary_points.size() >= boundary_point_cap:
					break
				var a3: Vector3 = chain_points_3d[i]
				var b3: Vector3 = chain_points_3d[(i + 1) % chain_points_3d.size()]
				var edge_len := Vector2(a3.x, a3.z).distance_to(Vector2(b3.x, b3.z))
				if edge_len <= boundary_resample_step:
					continue
				var segments := maxi(1, int(ceil(edge_len / boundary_resample_step)))
				for s in range(1, segments):
					if boundary_points.size() >= boundary_point_cap:
						break
					var t := float(s) / float(segments)
					boundary_points.push_back(a3.lerp(b3, t))

	return {
		"loops": loops,
		"points": boundary_points,
		"segments": boundary_segments,
	}


func _build_path_row_boundary_polygons_xz(verts: PackedVector3Array, path_rows: Array) -> Array:
	return _build_path_row_boundary_polygons_xz_mode(
		verts,
		path_rows,
		false
	)


func _build_path_row_boundary_polygons_xz_mode(
	verts: PackedVector3Array,
	path_rows: Array,
	lane_only: bool
) -> Array:
	var loops: Array = []
	var left_edge_id := 0
	var right_edge_id := 5
	if lane_only:
		left_edge_id = 2
		right_edge_id = 3
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		if rows.size() < 2:
			continue
		var left_chain := PackedVector2Array()
		var right_chain := PackedVector2Array()
		for row_raw in rows:
			var row: Dictionary = row_raw
			var row_edges: Array = row.get("row_edges", [])
			if row_edges.size() < 6:
				continue
			var left_idx := int(row_edges[left_edge_id])
			var right_idx := int(row_edges[right_edge_id])
			if left_idx >= 0 and left_idx < verts.size():
				var lp := Vector2(verts[left_idx].x, verts[left_idx].z)
				if left_chain.is_empty() or left_chain[left_chain.size() - 1].distance_to(lp) > 0.001:
					left_chain.push_back(lp)
			if right_idx >= 0 and right_idx < verts.size():
				var rp := Vector2(verts[right_idx].x, verts[right_idx].z)
				if right_chain.is_empty() or right_chain[right_chain.size() - 1].distance_to(rp) > 0.001:
					right_chain.push_back(rp)
		if left_chain.size() < 2 or right_chain.size() < 2:
			continue
		var poly := PackedVector2Array()
		for p in left_chain:
			poly.push_back(p)
		for i in range(right_chain.size() - 1, -1, -1):
			poly.push_back(right_chain[i])
		poly = _compact_polygon2d_xz(poly, 0.001)
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		loops.push_back(poly)
	return loops


func _count_boundary_edges_from_surface(indices: PackedInt32Array, edge_counts: Dictionary) -> void:
	if indices.is_empty():
		return
	var tri_count := indices.size() - (indices.size() % 3)
	for i in range(0, tri_count, 3):
		_register_boundary_edge(int(indices[i]), int(indices[i + 1]), edge_counts)
		_register_boundary_edge(int(indices[i + 1]), int(indices[i + 2]), edge_counts)
		_register_boundary_edge(int(indices[i + 2]), int(indices[i]), edge_counts)


func _register_boundary_edge(a: int, b: int, edge_counts: Dictionary) -> void:
	if a == b:
		return
	var key := _edge_key_from_indices(a, b)
	edge_counts[key] = int(edge_counts.get(key, 0)) + 1


func _append_boundary_neighbor(adjacency: Dictionary, from_idx: int, to_idx: int) -> void:
	var neighbors: Array = adjacency.get(from_idx, [])
	neighbors.push_back(to_idx)
	adjacency[from_idx] = neighbors


func _edge_key_from_indices(a: int, b: int) -> String:
	return str(mini(a, b)) + ":" + str(maxi(a, b))


func _edge_key_to_indices(key: String) -> Vector2i:
	var parts := key.split(":")
	if parts.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _compact_polygon2d_xz(poly: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.size() < 3:
		return out
	var eps := maxf(0.000001, epsilon)
	for i in range(poly.size()):
		var p := poly[i]
		if out.is_empty() or out[out.size() - 1].distance_to(p) > eps:
			out.push_back(p)
	if out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) <= eps:
		out.remove_at(out.size() - 1)
	if out.size() < 3:
		return PackedVector2Array()
	return out


func _resample_polygon_edges_for_boolean_fill(poly: PackedVector2Array, max_edge_len: float) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var step := maxf(0.5, max_edge_len)
	var out := PackedVector2Array()
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		out.push_back(a)
		var edge_len := a.distance_to(b)
		if edge_len <= step:
			continue
		var segments := maxi(1, int(ceil(edge_len / step)))
		for s in range(1, segments):
			var t := float(s) / float(segments)
			out.push_back(a.lerp(b, t))
	return _compact_polygon2d_xz(out, 0.0005)


func _clip_fill_parts_by_polygon(
	fill_parts: Array,
	clip_poly: PackedVector2Array,
	cancel_token: Dictionary = {}
) -> Array:
	var out: Array = []
	var clip := _compact_polygon2d_xz(clip_poly, 0.001)
	if clip.size() < 3:
		return fill_parts
	var clip_box := _polygon_bbox_xz(clip)
	if clip_box.is_empty():
		return fill_parts

	# Ensure clip is clockwise for clip_polygons (subtraction)
	if not Geometry2D.is_polygon_clockwise(clip):
		clip.reverse()
	var clip_rev := clip
	clip_rev.reverse()
	var clip_edge_lookup := _build_polygon_edge_lookup(clip)

	for part_i in range(fill_parts.size()):
		if (part_i % 128) == 0 and _is_generation_cancelled(cancel_token):
			return []
		var part_raw = fill_parts[part_i]
		var part: PackedVector2Array = _compact_polygon2d_xz(part_raw, 0.001)
		if part.size() < 3:
			continue
		var part_box := _polygon_bbox_xz(part)
		if part_box.is_empty():
			continue
		if not _bbox_overlaps_or_touches(part_box, clip_box, 0.0):
			out.push_back(part)
			continue
		out.append_array(_clip_overlapping_fill_part(part, clip, clip_rev, clip_box, clip_edge_lookup))
	return out


func _clip_overlapping_fill_part(part: PackedVector2Array, clip: PackedVector2Array,
	clip_rev: PackedVector2Array, clip_box: Dictionary, clip_edge_lookup: Dictionary) -> Array:
	if not _stage_cache.enabled:
		last_stats.fill_clips_rebuilt += 1
		return _clip_overlapping_fill_part_uncached(part, clip, clip_rev, clip_box, clip_edge_lookup)
	# Bounding boxes and edge lookup are pure derivatives of these exact inputs.
	var query: Dictionary = _stage_cache.query("clip_fill_part", [part, clip])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.fill_clips_reused += 1
		return cached.result.duplicate(true)
	last_stats.fill_clips_rebuilt += 1
	_stage_cache.begin_scope()
	var result := _clip_overlapping_fill_part_uncached(part, clip, clip_rev, clip_box, clip_edge_lookup)
	var children: PackedStringArray = _stage_cache.end_scope()
	_stage_cache.store(query, result.duplicate(true), children)
	return result


func _clip_overlapping_fill_part_uncached(part: PackedVector2Array, clip: PackedVector2Array,
	clip_rev: PackedVector2Array, clip_box: Dictionary, clip_edge_lookup: Dictionary) -> Array:
	var quick_relation := _classify_fill_part_against_clip_polygon(part, clip, clip_box, clip_edge_lookup)
	if quick_relation < 0:
		return [part]
	if quick_relation > 0:
		return []
	# clip_polygons(A, B) computes A - B.
	var clipped: Array = _stage_cache.polygon_clip(part, clip)
	if not clipped.is_empty():
		clipped = _filter_parts_outside_clip(clipped, clip, clip_rev)
	if clipped.is_empty():
		# Winding mismatch can make clip_polygons return empty on valid inputs.
		var part_rev := part
		part_rev.reverse()
		clipped = _stage_cache.polygon_clip(part_rev, clip)
		if not clipped.is_empty():
			clipped = _filter_parts_outside_clip(clipped, clip, clip_rev)
	if clipped.is_empty():
		clipped = _stage_cache.polygon_clip(part, clip_rev)
		if not clipped.is_empty():
			clipped = _filter_parts_outside_clip(clipped, clip, clip_rev)
	if clipped.is_empty():
		var part_rev2 := part
		part_rev2.reverse()
		clipped = _stage_cache.polygon_clip(part_rev2, clip_rev)
		if not clipped.is_empty():
			clipped = _filter_parts_outside_clip(clipped, clip, clip_rev)
	if clipped.is_empty():
		return [] if Geometry2D.is_point_in_polygon(_polygon_probe_point(part), clip) else [part]
	var out: Array = []
	for piece_raw in clipped:
		var piece: PackedVector2Array = _compact_polygon2d_xz(piece_raw, 0.001)
		if piece.size() >= 3:
			out.push_back(piece)
	return out


func _classify_fill_part_against_clip_polygon(
	part: PackedVector2Array,
	clip: PackedVector2Array,
	clip_box: Dictionary,
	clip_edge_lookup: Dictionary = {}
) -> int:
	if part.size() < 3 or clip.size() < 3:
		return 0
	var inside_count := 0
	for p in part:
		if Geometry2D.is_point_in_polygon(p, clip):
			inside_count += 1
	if inside_count == part.size():
		return 1
	if inside_count > 0:
		return 0

	var part_box := _polygon_bbox_xz(part)
	if part_box.is_empty() or not _bbox_overlaps_or_touches(part_box, clip_box, 0.0):
		return -1

	var candidate_edges := _collect_segment_lookup_ids_for_box(clip_edge_lookup, part_box)
	if candidate_edges.is_empty() and not clip_edge_lookup.is_empty():
		return -1
	var segments: Array = clip_edge_lookup.get("segments", [])
	for i in range(part.size()):
		var a: Vector2 = part[i]
		var b: Vector2 = part[(i + 1) % part.size()]
		var edge_count := candidate_edges.size() if not candidate_edges.is_empty() else clip.size()
		for edge_idx in range(edge_count):
			var seg_idx := int(candidate_edges[edge_idx]) if not candidate_edges.is_empty() else edge_idx
			if seg_idx < 0 or seg_idx >= segments.size():
				continue
			var seg: Dictionary = segments[seg_idx]
			var c: Vector2 = seg.get("a", Vector2.ZERO)
			var d: Vector2 = seg.get("b", Vector2.ZERO)
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return 0
	return -1


func _build_outer_rect_fill_parts_from_boundary_points(boundary_points: Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return []
	var outer_padding := maxf(0.0, terrain_fill_outer_padding)
	min_x -= outer_padding
	max_x += outer_padding
	min_z -= outer_padding
	max_z += outer_padding

	var outer := PackedVector2Array([
		Vector2(min_x, min_z),
		Vector2(max_x, min_z),
		Vector2(max_x, max_z),
		Vector2(min_x, max_z),
	])
	if Geometry2D.is_polygon_clockwise(outer):
		outer.reverse()
	return [outer]


func _append_terrain_influence_boundary_points(boundary_points: Array) -> void:
	if _terrain_influence_strips.is_empty():
		return
	var boundary_resample_step := maxf(0.1, minf(1.0, maxf(0.25, sample_step * 0.35)))
	for strip_raw in _terrain_influence_strips:
		var strip: Dictionary = strip_raw
		var boundary: PackedVector3Array = strip.get("boundary_points", PackedVector3Array())
		for p in boundary:
			var p2 := Vector2(p.x, p.z)
			var base_y := _sample_terrain_influence_centerline_base_height(strip, p2)
			boundary_points.push_back(Vector3(p.x, base_y, p.z))
		var loop: PackedVector2Array = strip.get("loop", PackedVector2Array())
		if loop.size() < 2:
			continue
		for i in range(loop.size()):
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % loop.size()]
			var edge_len := a.distance_to(b)
			if edge_len <= boundary_resample_step:
				continue
			var segments := maxi(1, int(ceil(edge_len / boundary_resample_step)))
			for s in range(1, segments):
				var t := float(s) / float(segments)
				var p2 := a.lerp(b, t)
				var base_y := _sample_terrain_influence_centerline_base_height(strip, p2)
				boundary_points.push_back(Vector3(p2.x, base_y, p2.y))


func _build_over_road_snap_context(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array
) -> Dictionary:
	var zones := _collect_terrain_influence_over_road_snap_zones()
	if zones.is_empty():
		return {}
	var data := _extract_road_boundary_loops_xz(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	var road_boundary_segments: Array = data.get("segments", [])
	if road_boundary_segments.is_empty():
		return {}
	var max_snap_dist := maxf(0.1, minf(2.0, _resolve_effective_fill_height_match_distance() * 0.4))
	var cell_size := maxf(0.05, max_snap_dist)
	for zi in range(zones.size()):
		var zone: Dictionary = zones[zi]
		var loop: PackedVector2Array = zone.get("loop", PackedVector2Array())
		var edge_band := maxf(0.01, float(zone.get("edge_band", 0.35)))
		var edge_segments := _build_loop_boundary_segments_xz([loop])
		var edge_cell_size := maxf(0.01, minf(cell_size, edge_band))
		var edge_grid: Dictionary = {}
		if not edge_segments.is_empty():
			edge_grid = _build_segment_spatial_hash_2d(edge_segments, edge_cell_size, edge_band)
		zone["edge_segments"] = edge_segments
		zone["edge_grid"] = edge_grid
		zone["edge_cell_size"] = edge_cell_size
		zone["edge_band"] = edge_band
		zones[zi] = zone
	return {
		"zones": zones,
		"segments": road_boundary_segments,
		"grid": _build_segment_spatial_hash_2d(road_boundary_segments, cell_size, max_snap_dist),
		"cell_size": cell_size,
		"max_snap_dist": max_snap_dist,
	}


func _build_loop_boundary_segments_xz(loops: Array) -> Array:
	var out: Array = []
	for loop_raw in loops:
		var loop: PackedVector2Array = loop_raw
		if loop.size() < 2:
			continue
		for i in range(loop.size()):
			var a2: Vector2 = loop[i]
			var b2: Vector2 = loop[(i + 1) % loop.size()]
			if a2.distance_to(b2) <= 0.0001:
				continue
			out.push_back({
				"a": Vector3(a2.x, 0.0, a2.y),
				"b": Vector3(b2.x, 0.0, b2.y),
			})
	return out


func _build_segment_spatial_hash_2d(segments: Array, cell_size: float, max_dist: float) -> Dictionary:
	var grid: Dictionary = {}
	var inv := 1.0 / maxf(0.0001, cell_size)
	for i in range(segments.size()):
		var seg: Dictionary = segments[i]
		var a3: Vector3 = seg.get("a", Vector3.ZERO)
		var b3: Vector3 = seg.get("b", Vector3.ZERO)
		var min_x := minf(a3.x, b3.x) - max_dist
		var max_x := maxf(a3.x, b3.x) + max_dist
		var min_z := minf(a3.z, b3.z) - max_dist
		var max_z := maxf(a3.z, b3.z) + max_dist
		var min_cx := int(floor(min_x * inv))
		var max_cx := int(floor(max_x * inv))
		var min_cz := int(floor(min_z * inv))
		var max_cz := int(floor(max_z * inv))
		for cx in range(min_cx, max_cx + 1):
			for cz in range(min_cz, max_cz + 1):
				var key := Vector2i(cx, cz)
				var ids: Array = grid.get(key, [])
				ids.push_back(i)
				grid[key] = ids
	return grid


func _sample_nearest_segment_height_2d(
	point: Vector2,
	segments: Array,
	grid: Dictionary,
	cell_size: float,
	max_dist: float
) -> Dictionary:
	if segments.is_empty() or grid.is_empty():
		return {"found": false}
	var inv := 1.0 / maxf(0.0001, cell_size)
	var base_key := Vector2i(int(floor(point.x * inv)), int(floor(point.y * inv)))
	var radius_cells := maxi(1, int(ceil(max_dist / maxf(0.0001, cell_size))))
	var best_d2 := max_dist * max_dist
	var best_y := 0.0
	var found := false
	var seen: Dictionary = {}
	for cx in range(base_key.x - radius_cells, base_key.x + radius_cells + 1):
		for cy in range(base_key.y - radius_cells, base_key.y + radius_cells + 1):
			var key := Vector2i(cx, cy)
			if not grid.has(key):
				continue
			var ids: Array = grid[key]
			for id_raw in ids:
				var idx := int(id_raw)
				if seen.has(idx):
					continue
				seen[idx] = true
				if idx < 0 or idx >= segments.size():
					continue
				var seg: Dictionary = segments[idx]
				var a3: Vector3 = seg.get("a", Vector3.ZERO)
				var b3: Vector3 = seg.get("b", Vector3.ZERO)
				var a2 := Vector2(a3.x, a3.z)
				var b2 := Vector2(b3.x, b3.z)
				var t := _closest_point_param_on_segment_2d(point, a2, b2)
				var closest := a2.lerp(b2, t)
				var d2 := closest.distance_squared_to(point)
				if d2 > best_d2:
					continue
				best_d2 = d2
				best_y = lerpf(a3.y, b3.y, t)
				found = true
	if not found:
		return {"found": false}
	return {
		"found": true,
		"y": best_y,
		"dist": sqrt(best_d2),
	}


func _collect_terrain_influence_over_road_loops() -> Array:
	var out: Array = []
	for strip_raw in _terrain_influence_strips:
		var strip: Dictionary = strip_raw
		if not bool(strip.get("allow_over_road", false)):
			continue
		var loop := _compact_polygon2d_xz(strip.get("loop", PackedVector2Array()), 0.001)
		if loop.size() >= 3:
			out.push_back(loop)
	return out


func _collect_terrain_influence_over_road_snap_zones() -> Array:
	var out: Array = []
	for strip_raw in _terrain_influence_strips:
		var strip: Dictionary = strip_raw
		if not bool(strip.get("allow_over_road", false)):
			continue
		var loop := _compact_polygon2d_xz(strip.get("loop", PackedVector2Array()), 0.001)
		if loop.size() < 3:
			continue
		var edge_band := maxf(0.0, float(strip.get("over_road_edge_snap_band", 0.0)))
		if edge_band <= 0.0001:
			continue
		out.push_back({
			"loop": loop,
			"edge_band": edge_band,
		})
	return out


func _build_effective_road_clip_parts(road_parts: Array) -> Array:
	var over_road_loops := _collect_terrain_influence_over_road_loops()
	if over_road_loops.is_empty():
		return road_parts
	var out: Array = []
	for road_raw in road_parts:
		var road_part := _compact_polygon2d_xz(road_raw, 0.001)
		if road_part.size() < 3:
			continue
		var remaining: Array = [road_part]
		for loop_raw in over_road_loops:
			var loop: PackedVector2Array = loop_raw
			if loop.size() < 3:
				continue
			remaining = _clip_fill_parts_by_polygon(remaining, loop)
			if remaining.is_empty():
				break
		for part_raw in remaining:
			var part := _compact_polygon2d_xz(part_raw, 0.001)
			if part.size() >= 3:
				out.push_back(part)
	return out


func _collect_terrain_influence_seed_boxes() -> Array:
	var boxes: Array = []
	for strip_raw in _terrain_influence_strips:
		var strip: Dictionary = strip_raw
		var points: PackedVector3Array = strip.get("points", PackedVector3Array())
		if points.size() < 2:
			continue
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for p in points:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
		var edge := maxf(0.0, float(strip.get("max_half_width", strip.get("half_width", 0.0))) + float(strip.get("blend", 0.0)))
		min_x -= edge
		max_x += edge
		min_z -= edge
		max_z += edge
		if min_x >= max_x or min_z >= max_z:
			continue
		boxes.push_back({
			"min_x": min_x,
			"max_x": max_x,
			"min_z": min_z,
			"max_z": max_z,
		})
	return boxes


func _build_outer_rect_fill_parts_from_road_parts(
	road_parts: Array,
	boundary_points: Array,
	cancel_token: Dictionary = {}
) -> Array:
	match terrain_fill_topology:
		TERRAIN_FILL_TOPOLOGY_GLOBAL_RECT:
			return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
		TERRAIN_FILL_TOPOLOGY_CONVEX_HULL:
			var hull_parts := _build_fill_parts_convex_hull(road_parts, boundary_points)
			if not hull_parts.is_empty():
				return hull_parts
			return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
		TERRAIN_FILL_TOPOLOGY_GRID:
			var grid_parts := _build_fill_parts_grid(boundary_points)
			if not grid_parts.is_empty():
				return grid_parts
			return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
		TERRAIN_FILL_TOPOLOGY_RADIAL:
			var radial_parts := _build_fill_parts_radial(boundary_points)
			if not radial_parts.is_empty():
				return radial_parts
			return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
		TERRAIN_FILL_TOPOLOGY_HEX:
			var hex_parts := _build_fill_parts_hex_grid(boundary_points)
			if not hex_parts.is_empty():
				return hex_parts
			return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
		TERRAIN_FILL_TOPOLOGY_DIAMOND:
			var diamond_parts := _build_fill_parts_diamond_grid(boundary_points)
			if not diamond_parts.is_empty():
				return diamond_parts
			return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
		TERRAIN_FILL_TOPOLOGY_ADAPTIVE:
			return _build_fill_parts_cluster_rectangles(road_parts, boundary_points)
		TERRAIN_FILL_TOPOLOGY_QUADTREE_ERROR:
			var quadtree_error_parts := _build_fill_parts_error_quadtree(road_parts, boundary_points, cancel_token)
			if _is_generation_cancelled(cancel_token):
				return []
			if not quadtree_error_parts.is_empty():
				return quadtree_error_parts
			return _build_fill_parts_cluster_rectangles(road_parts, boundary_points)
		TERRAIN_FILL_TOPOLOGY_LANE_FOLLOW:
			var lane_follow_parts := _build_fill_parts_lane_follow(road_parts, boundary_points)
			if not lane_follow_parts.is_empty():
				return lane_follow_parts
			return _build_fill_parts_cluster_rectangles(road_parts, boundary_points)
		TERRAIN_FILL_TOPOLOGY_LOD_RINGS:
			var lod_parts := _build_fill_parts_lod_rings(road_parts, boundary_points)
			if not lod_parts.is_empty():
				return lod_parts
			return _build_fill_parts_cluster_rectangles(road_parts, boundary_points)
		TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY:
			var delaunay_parts := _build_fill_parts_adaptive_delaunay(road_parts, boundary_points, cancel_token)
			if _is_generation_cancelled(cancel_token):
				return []
			if not delaunay_parts.is_empty():
				return delaunay_parts
			return _build_fill_parts_cluster_rectangles(road_parts, boundary_points)
		_:
			return _build_fill_parts_cluster_rectangles(road_parts, boundary_points)


func _build_fill_parts_cluster_rectangles(road_parts: Array, boundary_points: Array) -> Array:
	var boxes: Array = []
	for part_raw in road_parts:
		var part: PackedVector2Array = _compact_polygon2d_xz(part_raw, 0.001)
		if part.size() < 3:
			continue
		var box := _polygon_bbox_xz(part)
		if box.is_empty():
			continue
		boxes.push_back(box)
	for box in _collect_terrain_influence_seed_boxes():
		boxes.push_back(box)

	if boxes.is_empty():
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)

	var parent: Array = []
	parent.resize(boxes.size())
	for i in range(parent.size()):
		parent[i] = i

	var merge_gap := maxf(0.001, road_width * 0.5)
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			if _bbox_overlaps_or_touches(boxes[i], boxes[j], merge_gap):
				_union_find_union(parent, i, j)

	var cluster_bbox: Dictionary = {}
	for i in range(boxes.size()):
		var root := _union_find_find(parent, i)
		var box: Dictionary = boxes[i]
		if not cluster_bbox.has(root):
			cluster_bbox[root] = box.duplicate(true)
			continue
		var acc: Dictionary = cluster_bbox[root]
		acc["min_x"] = minf(float(acc.get("min_x", INF)), float(box.get("min_x", INF)))
		acc["max_x"] = maxf(float(acc.get("max_x", -INF)), float(box.get("max_x", -INF)))
		acc["min_z"] = minf(float(acc.get("min_z", INF)), float(box.get("min_z", INF)))
		acc["max_z"] = maxf(float(acc.get("max_z", -INF)), float(box.get("max_z", -INF)))
		cluster_bbox[root] = acc

	var out: Array = []
	for root in cluster_bbox.keys():
		var box: Dictionary = cluster_bbox[root]
		var min_x := float(box.get("min_x", INF))
		var max_x := float(box.get("max_x", -INF))
		var min_z := float(box.get("min_z", INF))
		var max_z := float(box.get("max_z", -INF))
		var outer_padding := maxf(0.0, terrain_fill_outer_padding)
		min_x -= outer_padding
		max_x += outer_padding
		min_z -= outer_padding
		max_z += outer_padding
		if min_x >= max_x or min_z >= max_z:
			continue
		var outer := PackedVector2Array([
			Vector2(min_x, min_z),
			Vector2(max_x, min_z),
			Vector2(max_x, max_z),
			Vector2(min_x, max_z),
		])
		if Geometry2D.is_polygon_clockwise(outer):
			outer.reverse()
		out.push_back(outer)

	if out.is_empty():
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
	return out


func _build_fill_parts_convex_hull(road_parts: Array, boundary_points: Array) -> Array:
	var points := PackedVector2Array()
	for part_raw in road_parts:
		var part: PackedVector2Array = _compact_polygon2d_xz(part_raw, 0.001)
		for p in part:
			points.push_back(p)
	for box_raw in _collect_terrain_influence_seed_boxes():
		var box: Dictionary = box_raw
		var min_x := float(box.get("min_x", INF))
		var max_x := float(box.get("max_x", -INF))
		var min_z := float(box.get("min_z", INF))
		var max_z := float(box.get("max_z", -INF))
		if min_x >= max_x or min_z >= max_z:
			continue
		points.push_back(Vector2(min_x, min_z))
		points.push_back(Vector2(max_x, min_z))
		points.push_back(Vector2(max_x, max_z))
		points.push_back(Vector2(min_x, max_z))
	if points.size() < 3:
		for p_raw in boundary_points:
			var p: Vector3 = p_raw
			points.push_back(Vector2(p.x, p.z))
	if points.size() < 3:
		return []

	var hull := Geometry2D.convex_hull(points)
	hull = _compact_polygon2d_xz(hull, 0.001)
	if hull.size() < 3:
		return []

	var outer_padding := maxf(0.0, terrain_fill_outer_padding)
	if outer_padding > 0.0001:
		var hull_parts: Array = _stage_cache.polygon_offset(hull, outer_padding)
		if not hull_parts.is_empty():
			hull = _pick_largest_polygon_part_xz(hull_parts)
			hull = _compact_polygon2d_xz(hull, 0.001)
	if hull.size() < 3:
		return []
	if Geometry2D.is_polygon_clockwise(hull):
		hull.reverse()
	return [hull]


func _build_fill_parts_grid(boundary_points: Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return []

	var step := maxf(0.5, terrain_fill_grid_tile_size)
	var width := max_x - min_x
	var depth := max_z - min_z
	var count_x := maxi(1, int(ceil(width / step)))
	var count_z := maxi(1, int(ceil(depth / step)))
	var tile_count := count_x * count_z
	if tile_count > TERRAIN_FILL_GRID_MAX_TILES:
		var scale := sqrt(float(tile_count) / float(TERRAIN_FILL_GRID_MAX_TILES))
		step *= maxf(1.0, scale)
		count_x = maxi(1, int(ceil(width / step)))
		count_z = maxi(1, int(ceil(depth / step)))

	var out: Array = []
	for iz in range(count_z):
		var z0 := min_z + float(iz) * step
		var z1 := minf(max_z, z0 + step)
		if z1 - z0 <= 0.0001:
			continue
		for ix in range(count_x):
			var x0 := min_x + float(ix) * step
			var x1 := minf(max_x, x0 + step)
			if x1 - x0 <= 0.0001:
				continue
			var cell := PackedVector2Array([
				Vector2(x0, z0),
				Vector2(x1, z0),
				Vector2(x1, z1),
				Vector2(x0, z1),
			])
			out.push_back(cell)
	return out


func _build_fill_parts_radial(boundary_points: Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var center := Vector2.ZERO
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		var p := Vector2(p3.x, p3.z)
		center += p
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	if boundary_points.is_empty():
		return []
	center /= float(boundary_points.size())

	var radius := 0.0
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		radius = maxf(radius, Vector2(p3.x, p3.z).distance_to(center))
	if radius <= 0.0001 and min_x < max_x and min_z < max_z:
		radius = Vector2(max_x - min_x, max_z - min_z).length() * 0.5
	if radius <= 0.0001:
		return []

	var ring_count := clampi(terrain_fill_radial_ring_count, 2, 128)
	var sector_count := clampi(terrain_fill_radial_sector_count, 6, 256)
	var cells := ring_count * sector_count
	if cells > TERRAIN_FILL_RADIAL_MAX_CELLS:
		var scale := sqrt(float(cells) / float(TERRAIN_FILL_RADIAL_MAX_CELLS))
		sector_count = maxi(6, int(floor(float(sector_count) / maxf(1.0, scale))))
		cells = ring_count * sector_count
		if cells > TERRAIN_FILL_RADIAL_MAX_CELLS:
			ring_count = maxi(2, int(floor(float(TERRAIN_FILL_RADIAL_MAX_CELLS) / float(sector_count))))

	var out: Array = []
	for ring_idx in range(ring_count):
		var r0 := radius * float(ring_idx) / float(ring_count)
		var r1 := radius * float(ring_idx + 1) / float(ring_count)
		for sector_idx in range(sector_count):
			var a0 := TAU * float(sector_idx) / float(sector_count)
			var a1 := TAU * float(sector_idx + 1) / float(sector_count)
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			if ring_idx == 0:
				var tri := PackedVector2Array([
					center,
					center + d0 * r1,
					center + d1 * r1,
				])
				out.push_back(tri)
				continue
			var cell := PackedVector2Array([
				center + d0 * r0,
				center + d0 * r1,
				center + d1 * r1,
				center + d1 * r0,
			])
			out.push_back(cell)
	return out


func _build_fill_parts_hex_grid(boundary_points: Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return []

	var r := maxf(0.25, terrain_fill_hex_radius)
	var dx := sqrt(3.0) * r
	var dz := 1.5 * r
	var cols := maxi(1, int(ceil((max_x - min_x) / maxf(0.001, dx))) + 4)
	var rows := maxi(1, int(ceil((max_z - min_z) / maxf(0.001, dz))) + 4)
	var cell_count := cols * rows
	if cell_count > TERRAIN_FILL_HEX_MAX_CELLS:
		var scale := sqrt(float(cell_count) / float(TERRAIN_FILL_HEX_MAX_CELLS))
		r *= maxf(1.0, scale)
		dx = sqrt(3.0) * r
		dz = 1.5 * r
		cols = maxi(1, int(ceil((max_x - min_x) / maxf(0.001, dx))) + 4)
		rows = maxi(1, int(ceil((max_z - min_z) / maxf(0.001, dz))) + 4)

	var out: Array = []
	var start_z := min_z - r
	for row in range(rows):
		var z := start_z + float(row) * dz
		var x_offset := 0.0 if (row % 2) == 0 else dx * 0.5
		var start_x := min_x - dx + x_offset
		for col in range(cols):
			var x := start_x + float(col) * dx
			var poly := PackedVector2Array()
			for k in range(6):
				var angle := TAU * float(k) / 6.0 + PI / 6.0
				poly.push_back(Vector2(x + cos(angle) * r, z + sin(angle) * r))
			out.push_back(poly)
	return out


func _build_fill_parts_diamond_grid(boundary_points: Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return []

	var tile := maxf(0.25, terrain_fill_diamond_tile_size)
	var half := tile * 0.5
	var step := half
	var ix_count := maxi(1, int(ceil((max_x - min_x) / maxf(0.001, step))) + 8)
	var iz_count := maxi(1, int(ceil((max_z - min_z) / maxf(0.001, step))) + 8)
	var approx_cells := int(ceil(float(ix_count * iz_count) * 0.5))
	if approx_cells > TERRAIN_FILL_DIAMOND_MAX_CELLS:
		var scale := sqrt(float(approx_cells) / float(TERRAIN_FILL_DIAMOND_MAX_CELLS))
		tile *= maxf(1.0, scale)
		half = tile * 0.5
		step = half
		ix_count = maxi(1, int(ceil((max_x - min_x) / maxf(0.001, step))) + 8)
		iz_count = maxi(1, int(ceil((max_z - min_z) / maxf(0.001, step))) + 8)

	var start_x := min_x - tile
	var start_z := min_z - tile
	var out: Array = []
	for iz in range(iz_count):
		var cz := start_z + float(iz) * step
		for ix in range(ix_count):
			if ((ix + iz) % 2) != 0:
				continue
			var cx := start_x + float(ix) * step
			var diamond := PackedVector2Array([
				Vector2(cx, cz - half),
				Vector2(cx + half, cz),
				Vector2(cx, cz + half),
				Vector2(cx - half, cz),
			])
			out.push_back(diamond)
	return out


func _build_fill_parts_error_quadtree(
	road_parts: Array,
	boundary_points: Array,
	cancel_token: Dictionary = {}
) -> Array:
	var profile_total_start := _profile_start()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_idx in range(boundary_points.size()):
		if (p_idx % 256) == 0 and _is_generation_cancelled(cancel_token):
			return []
		var p_raw = boundary_points[p_idx]
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return []

	var road_loops: Array = []
	var road_boxes: Array = []
	for raw in road_parts:
		if _is_generation_cancelled(cancel_token):
			return []
		var poly: PackedVector2Array = _compact_polygon2d_xz(raw, 0.001)
		if poly.size() < 3:
			continue
		var box := _polygon_bbox_xz(poly)
		if box.is_empty():
			continue
		road_loops.push_back(poly)
		road_boxes.push_back(box)

	var snap_eps := maxf(0.0001, terrain_fill_height_match_epsilon)
	var base_y := terrain_fill_base_height + y_offset
	var boundary_height_map: Dictionary = {}
	for p_idx in range(boundary_points.size()):
		if (p_idx % 256) == 0 and _is_generation_cancelled(cancel_token):
			return []
		var p_raw = boundary_points[p_idx]
		var p: Vector3 = p_raw
		var key := Vector2i(int(round(p.x / snap_eps)), int(round(p.z / snap_eps)))
		var sum_and_count: Array = boundary_height_map.get(key, [0.0, 0])
		sum_and_count[0] = float(sum_and_count[0]) + p.y
		sum_and_count[1] = int(sum_and_count[1]) + 1
		boundary_height_map[key] = sum_and_count
	var boundary_height_lookup := _build_boundary_height_lookup(boundary_points)
	var height_sample_cache: Dictionary = {}

	var width := max_x - min_x
	var depth := max_z - min_z
	var side := maxf(width, depth)
	var center_x := (min_x + max_x) * 0.5
	var center_z := (min_z + max_z) * 0.5
	var root_min_x := center_x - side * 0.5
	var root_max_x := center_x + side * 0.5
	var root_min_z := center_z - side * 0.5
	var root_max_z := center_z + side * 0.5

	var max_depth := clampi(terrain_fill_quadtree_max_depth, 1, 10)
	var min_cell_size := maxf(0.25, terrain_fill_quadtree_min_cell_size)
	var error_threshold := maxf(0.01, terrain_fill_quadtree_error_threshold)
	var stack: Array = [{
		"min_x": root_min_x,
		"max_x": root_max_x,
		"min_z": root_min_z,
		"max_z": root_max_z,
		"depth": 0,
	}]
	var out: Array = []
	var emitted := 0
	var profile_subdivide_start := _profile_start()
	while not stack.is_empty():
		if _is_generation_cancelled(cancel_token):
			return []
		var node: Dictionary = stack.pop_back()
		var n_min_x := float(node.get("min_x", 0.0))
		var n_max_x := float(node.get("max_x", 0.0))
		var n_min_z := float(node.get("min_z", 0.0))
		var n_max_z := float(node.get("max_z", 0.0))
		var depth_i := int(node.get("depth", 0))
		var cell_w := n_max_x - n_min_x
		var cell_h := n_max_z - n_min_z
		var can_split := (
			depth_i < max_depth
			and minf(cell_w, cell_h) > min_cell_size * 1.0001
			and emitted + stack.size() < TERRAIN_FILL_QUADTREE_MAX_CELLS
		)
		if can_split:
			var split_by_road := (
				not road_loops.is_empty()
				and _quadtree_cell_should_split(n_min_x, n_max_x, n_min_z, n_max_z, road_loops, road_boxes)
			)
			var split_by_error := _quadtree_cell_has_height_error(
				n_min_x,
				n_max_x,
				n_min_z,
				n_max_z,
				boundary_height_map,
				boundary_points,
				base_y,
				error_threshold,
				height_sample_cache,
				boundary_height_lookup
			)
			if split_by_road or split_by_error:
				var mid_x := (n_min_x + n_max_x) * 0.5
				var mid_z := (n_min_z + n_max_z) * 0.5
				var next_depth := depth_i + 1
				stack.push_back({"min_x": n_min_x, "max_x": mid_x, "min_z": n_min_z, "max_z": mid_z, "depth": next_depth})
				stack.push_back({"min_x": mid_x, "max_x": n_max_x, "min_z": n_min_z, "max_z": mid_z, "depth": next_depth})
				stack.push_back({"min_x": n_min_x, "max_x": mid_x, "min_z": mid_z, "max_z": n_max_z, "depth": next_depth})
				stack.push_back({"min_x": mid_x, "max_x": n_max_x, "min_z": mid_z, "max_z": n_max_z, "depth": next_depth})
				continue
		var cell := PackedVector2Array([
			Vector2(n_min_x, n_min_z),
			Vector2(n_max_x, n_min_z),
			Vector2(n_max_x, n_max_z),
			Vector2(n_min_x, n_max_z),
		])
		out.push_back(cell)
		emitted += 1
	_profile_log("quadtree fill subdivide", profile_subdivide_start, "cells=%s" % [out.size()])
	if out.is_empty():
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
	_profile_log("quadtree fill total", profile_total_start, "cells=%s road_loops=%s" % [out.size(), road_loops.size()])
	return out


func _quadtree_cell_has_height_error(
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	error_threshold: float,
	height_sample_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> bool:
	var c0 := Vector2(min_x, min_z)
	var c1 := Vector2(max_x, min_z)
	var c2 := Vector2(max_x, max_z)
	var c3 := Vector2(min_x, max_z)
	var center := (c0 + c2) * 0.5
	var m01 := (c0 + c1) * 0.5
	var m12 := (c1 + c2) * 0.5
	var m23 := (c2 + c3) * 0.5
	var m30 := (c3 + c0) * 0.5
	var samples: Array = [c0, c1, c2, c3, center, m01, m12, m23, m30]
	var min_h := INF
	var max_h := -INF
	for sample_raw in samples:
		var sample: Vector2 = sample_raw
		var h := _sample_quadtree_error_height(
			sample,
			boundary_height_map,
			boundary_points,
			base_y,
			height_sample_cache,
			boundary_height_lookup
		)
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
	return (max_h - min_h) > error_threshold


func _sample_quadtree_error_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	height_sample_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> float:
	var scale := 1000.0
	var key := Vector2i(int(round(point.x * scale)), int(round(point.y * scale)))
	if height_sample_cache.has(key):
		return float(height_sample_cache[key])
	var sampled := _sample_boolean_fill_vertex_height(
		point,
		boundary_height_map,
		boundary_points,
		base_y,
		boundary_height_lookup
	)
	height_sample_cache[key] = sampled
	return sampled


func _quadtree_cell_should_split(
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float,
	road_loops: Array,
	road_boxes: Array
) -> bool:
	var cell_box := {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	}
	var c0 := Vector2(min_x, min_z)
	var c1 := Vector2(max_x, min_z)
	var c2 := Vector2(max_x, max_z)
	var c3 := Vector2(min_x, max_z)
	var center := (c0 + c2) * 0.5
	for i in range(road_loops.size()):
		var road_box: Dictionary = road_boxes[i]
		if not _bbox_overlaps_or_touches(cell_box, road_box, 0.0):
			continue
		var road: PackedVector2Array = road_loops[i]
		var inside_count := 0
		inside_count += 1 if Geometry2D.is_point_in_polygon(c0, road) else 0
		inside_count += 1 if Geometry2D.is_point_in_polygon(c1, road) else 0
		inside_count += 1 if Geometry2D.is_point_in_polygon(c2, road) else 0
		inside_count += 1 if Geometry2D.is_point_in_polygon(c3, road) else 0
		var center_inside := Geometry2D.is_point_in_polygon(center, road)
		if inside_count > 0 and inside_count < 4:
			return true
		if center_inside and inside_count < 4:
			return true
		if _polygon_has_point_inside_rect_xz(road, min_x, max_x, min_z, max_z):
			return true
		if _polygon_edges_intersect_rect_xz(road, c0, c1, c2, c3):
			return true
	return false


func _polygon_has_point_inside_rect_xz(
	poly: PackedVector2Array,
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float
) -> bool:
	for p in poly:
		if p.x >= min_x and p.x <= max_x and p.y >= min_z and p.y <= max_z:
			return true
	return false


func _polygon_edges_intersect_rect_xz(
	poly: PackedVector2Array,
	c0: Vector2,
	c1: Vector2,
	c2: Vector2,
	c3: Vector2
) -> bool:
	if poly.size() < 2:
		return false
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a, b, c0, c1) != null:
			return true
		if Geometry2D.segment_intersects_segment(a, b, c1, c2) != null:
			return true
		if Geometry2D.segment_intersects_segment(a, b, c2, c3) != null:
			return true
		if Geometry2D.segment_intersects_segment(a, b, c3, c0) != null:
			return true
	return false


func _build_fill_parts_lane_follow(_road_parts: Array, boundary_points: Array) -> Array:
	if boundary_points.is_empty():
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)

	var width := maxf(0.5, terrain_fill_lane_follow_width)
	var bands := clampi(terrain_fill_lane_follow_bands, 1, 12)
	var ring_step := maxf(0.25, width / float(bands))
	var center := Vector2.ZERO
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		center += Vector2(p3.x, p3.z)
	center /= float(boundary_points.size())

	var outer_radius := 0.0
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		outer_radius = maxf(outer_radius, Vector2(p3.x, p3.z).distance_to(center))
	if outer_radius <= 0.0001:
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)

	var ring_count := maxi(1, int(ceil(outer_radius / ring_step)))
	var sector_count := clampi(int(ceil((TAU * outer_radius) / maxf(0.5, ring_step))), 8, 256)
	var cell_count := ring_count * sector_count
	if cell_count > TERRAIN_FILL_RADIAL_MAX_CELLS:
		var scale := sqrt(float(cell_count) / float(TERRAIN_FILL_RADIAL_MAX_CELLS))
		sector_count = maxi(8, int(floor(float(sector_count) / maxf(1.0, scale))))
		cell_count = ring_count * sector_count
		if cell_count > TERRAIN_FILL_RADIAL_MAX_CELLS:
			ring_count = maxi(1, int(floor(float(TERRAIN_FILL_RADIAL_MAX_CELLS) / float(sector_count))))

	var out: Array = []
	for ring_idx in range(ring_count):
		var r0 := outer_radius * float(ring_idx) / float(ring_count)
		var r1 := outer_radius * float(ring_idx + 1) / float(ring_count)
		for sector_idx in range(sector_count):
			var a0 := TAU * float(sector_idx) / float(sector_count)
			var a1 := TAU * float(sector_idx + 1) / float(sector_count)
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			if ring_idx == 0:
				out.push_back(PackedVector2Array([
					center,
					center + d0 * r1,
					center + d1 * r1,
				]))
			else:
				out.push_back(PackedVector2Array([
					center + d0 * r0,
					center + d0 * r1,
					center + d1 * r1,
					center + d1 * r0,
				]))

	if out.is_empty():
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)
	return out


func _build_fill_parts_lod_rings(road_parts: Array, boundary_points: Array) -> Array:
	if boundary_points.is_empty():
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)

	var base_parts: Array = []
	for part_raw in road_parts:
		var part: PackedVector2Array = _compact_polygon2d_xz(part_raw, 0.001)
		if part.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(part):
			part.reverse()
		base_parts.push_back(part)
	if base_parts.is_empty():
		return _build_fill_parts_lane_follow(road_parts, boundary_points)

	var max_dist := 0.0
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		var d := _min_distance_to_road_loops_xz(Vector2(p3.x, p3.z), base_parts)
		if d < INF * 0.5:
			max_dist = maxf(max_dist, d)
	if max_dist <= 0.001:
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for p_raw in boundary_points:
			var p3: Vector3 = p_raw
			min_x = minf(min_x, p3.x)
			max_x = maxf(max_x, p3.x)
			min_z = minf(min_z, p3.z)
			max_z = maxf(max_z, p3.z)
		if min_x < max_x and min_z < max_z:
			max_dist = Vector2(max_x - min_x, max_z - min_z).length() * 0.25
	if max_dist <= 0.001:
		return _build_outer_rect_fill_parts_from_boundary_points(boundary_points)

	var ring_count := clampi(terrain_fill_lod_ring_count, 2, 20)
	var growth := clampf(terrain_fill_lod_band_growth, 1.0, 3.0)
	var edge_step_near := maxf(0.1, terrain_fill_lod_edge_step_near)
	var edge_step_far := maxf(edge_step_near, terrain_fill_lod_edge_step_far)

	var weights := PackedFloat32Array()
	weights.resize(ring_count)
	var total_weight := 0.0
	for i in range(ring_count):
		var w := pow(growth, float(i))
		weights[i] = w
		total_weight += w
	if total_weight <= 0.0001:
		total_weight = float(ring_count)
		for i in range(ring_count):
			weights[i] = 1.0
	var dist_scale := max_dist / total_weight

	var out: Array = []
	var inner_dist := 0.0
	for ring_idx in range(ring_count):
		var band_width := float(weights[ring_idx]) * dist_scale
		var outer_dist := inner_dist + band_width
		if outer_dist <= inner_dist + 0.0001:
			inner_dist = outer_dist
			continue

		var outer_parts: Array = []
		for base_raw in base_parts:
			var base: PackedVector2Array = base_raw
			var expanded_raw: Array = _stage_cache.polygon_offset(base, outer_dist)
			for ex_raw in expanded_raw:
				var ex: PackedVector2Array = _compact_polygon2d_xz(ex_raw, 0.001)
				if ex.size() < 3:
					continue
				if Geometry2D.is_polygon_clockwise(ex):
					ex.reverse()
				outer_parts.push_back(ex)
		if outer_parts.is_empty():
			inner_dist = outer_dist
			continue

		var ring_parts: Array = outer_parts
		if inner_dist <= 0.0001:
			for base_raw in base_parts:
				ring_parts = _clip_fill_parts_by_polygon(ring_parts, base_raw)
				if ring_parts.is_empty():
					break
		else:
			for base_raw in base_parts:
				var base: PackedVector2Array = base_raw
				var inner_raw: Array = _stage_cache.polygon_offset(base, inner_dist)
				for in_raw in inner_raw:
					var inner: PackedVector2Array = _compact_polygon2d_xz(in_raw, 0.001)
					if inner.size() < 3:
						continue
					if Geometry2D.is_polygon_clockwise(inner):
						inner.reverse()
					ring_parts = _clip_fill_parts_by_polygon(ring_parts, inner)
					if ring_parts.is_empty():
						break
				if ring_parts.is_empty():
					break

		var t := float(ring_idx) / float(maxi(1, ring_count - 1))
		var edge_step := lerpf(edge_step_near, edge_step_far, t)
		for rp_raw in ring_parts:
			var ring_poly: PackedVector2Array = _compact_polygon2d_xz(rp_raw, 0.001)
			if ring_poly.size() < 3:
				continue
			var resampled := _resample_polygon_edges_for_boolean_fill(ring_poly, edge_step)
			if resampled.size() >= 3:
				ring_poly = resampled
			if Geometry2D.is_polygon_clockwise(ring_poly):
				ring_poly.reverse()
			out.push_back(ring_poly)
		inner_dist = outer_dist

	if out.is_empty():
		return _build_fill_parts_lane_follow(road_parts, boundary_points)
	return out


func _build_fill_parts_adaptive_delaunay(
	road_parts: Array,
	boundary_points: Array,
	cancel_token: Dictionary = {}
) -> Array:
	var profile_total_start := _profile_start()
	if boundary_points.is_empty():
		return []

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		min_x = minf(min_x, p3.x)
		max_x = maxf(max_x, p3.x)
		min_z = minf(min_z, p3.z)
		max_z = maxf(max_z, p3.z)
	if min_x >= max_x or min_z >= max_z:
		return []

	var road_loops: Array = []
	for raw in road_parts:
		var poly: PackedVector2Array = _compact_polygon2d_xz(raw, 0.001)
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		road_loops.push_back(poly)

	var near_step := maxf(0.1, terrain_fill_delaunay_step_near)
	var far_step := maxf(near_step, terrain_fill_delaunay_step_far)
	var jitter := clampf(terrain_fill_delaunay_jitter, 0.0, 0.45)
	var road_distance_lookup := _build_road_loop_distance_lookup(road_loops, maxf(near_step, far_step))

	var profile_distance_start := _profile_start()
	var max_dist := 0.0
	if road_loops.is_empty():
		max_dist = Vector2(max_x - min_x, max_z - min_z).length() * 0.5
	else:
		for p_raw in boundary_points:
			var p3: Vector3 = p_raw
			var d := _min_distance_to_road_loops_xz(Vector2(p3.x, p3.z), road_loops, road_distance_lookup)
			if d < INF * 0.5:
				max_dist = maxf(max_dist, d)
	if max_dist <= 0.001:
		max_dist = maxf(near_step, Vector2(max_x - min_x, max_z - min_z).length() * 0.25)
	_profile_log("delaunay fill distance lookup", profile_distance_start, "road_loops=%s max_dist=%.2f" % [road_loops.size(), max_dist])

	var profile_points_start := _profile_start()
	var quant := maxf(0.0005, near_step * 0.35)
	var points := PackedVector2Array()
	var point_keys: Dictionary = {}
	_add_unique_fill_point(Vector2(min_x, min_z), points, point_keys, quant)
	_add_unique_fill_point(Vector2(max_x, min_z), points, point_keys, quant)
	_add_unique_fill_point(Vector2(max_x, max_z), points, point_keys, quant)
	_add_unique_fill_point(Vector2(min_x, max_z), points, point_keys, quant)
	_add_unique_fill_point(Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5), points, point_keys, quant)
	for p_raw in boundary_points:
		var p3: Vector3 = p_raw
		_add_unique_fill_point(Vector2(p3.x, p3.z), points, point_keys, quant)

	for loop_raw in road_loops:
		var loop: PackedVector2Array = loop_raw
		var dense_loop := _resample_polygon_edges_for_boolean_fill(loop, near_step)
		for p in dense_loop:
			_add_unique_fill_point(p, points, point_keys, quant)

	var rng := RandomNumberGenerator.new()
	rng.seed = 13371337
	var z := min_z
	while z <= max_z + 0.0001:
		if _is_generation_cancelled(cancel_token):
			return []
		var row_probe := Vector2((min_x + max_x) * 0.5, z)
		var row_t := 1.0
		if not road_loops.is_empty():
			var row_d := _min_distance_to_road_loops_xz(row_probe, road_loops, road_distance_lookup, max_dist)
			row_t = clampf(row_d / maxf(0.0001, max_dist), 0.0, 1.0)
		var row_step := lerpf(near_step, far_step, row_t)
		var x := min_x
		while x <= max_x + 0.0001:
			var probe := Vector2(x, z)
			var t := 1.0
			if not road_loops.is_empty():
				var d := _min_distance_to_road_loops_xz(probe, road_loops, road_distance_lookup, max_dist)
				t = clampf(d / maxf(0.0001, max_dist), 0.0, 1.0)
			var local_step := lerpf(near_step, far_step, t)
			var jitter_mag := local_step * jitter
			var px := clampf(x + rng.randf_range(-jitter_mag, jitter_mag), min_x, max_x)
			var pz := clampf(z + rng.randf_range(-jitter_mag, jitter_mag), min_z, max_z)
			_add_unique_fill_point(Vector2(px, pz), points, point_keys, quant)
			x += local_step
		z += maxf(0.25, row_step)

	if points.size() > TERRAIN_FILL_DELAUNAY_MAX_POINTS:
		var reduced := PackedVector2Array()
		var anchor_count := mini(64, points.size())
		for i in range(anchor_count):
			reduced.push_back(points[i])
		var remaining := points.size() - anchor_count
		var slots := TERRAIN_FILL_DELAUNAY_MAX_POINTS - anchor_count
		if remaining > 0 and slots > 0:
			var stride := float(remaining) / float(slots)
			var cursor := 0.0
			for _i in range(slots):
				var idx := anchor_count + mini(remaining - 1, int(floor(cursor)))
				reduced.push_back(points[idx])
				cursor += stride
		points = reduced
	_profile_log("delaunay fill collect points", profile_points_start, "points=%s bbox=%.2fx%.2f" % [points.size(), max_x - min_x, max_z - min_z])

	if points.size() < 3:
		return []
	var profile_delaunay_start := _profile_start()
	var tri_indices: PackedInt32Array = _stage_cache.polygon_triangulate(points, true)
	_profile_log("delaunay fill triangulate", profile_delaunay_start, "tri_indices=%s" % [tri_indices.size()])
	if tri_indices.size() < 3:
		return []

	var out: Array = []
	var profile_filter_start := _profile_start()
	var tri_count := tri_indices.size() - (tri_indices.size() % 3)
	for i in range(0, tri_count, 3):
		if (i % 384) == 0 and _is_generation_cancelled(cancel_token):
			return []
		var ia := int(tri_indices[i])
		var ib := int(tri_indices[i + 1])
		var ic := int(tri_indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= points.size() or ib >= points.size() or ic >= points.size():
			continue
		var a := points[ia]
		var b := points[ib]
		var c := points[ic]
		if absf((b - a).cross(c - a)) <= 0.000001:
			continue
		var tri := PackedVector2Array([a, b, c])
		if Geometry2D.is_polygon_clockwise(tri):
			tri.reverse()
		out.push_back(tri)
	_profile_log("delaunay fill filter triangles", profile_filter_start, "parts=%s" % [out.size()])
	_profile_log("delaunay fill total", profile_total_start, "parts=%s points=%s" % [out.size(), points.size()])
	return out


func _add_unique_fill_point(
	point: Vector2,
	points: PackedVector2Array,
	point_keys: Dictionary,
	quant_step: float
) -> void:
	var q := maxf(0.0001, quant_step)
	var key := Vector2i(int(round(point.x / q)), int(round(point.y / q)))
	if point_keys.has(key):
		return
	point_keys[key] = true
	points.push_back(point)


func _polygon_bbox_xz(poly: PackedVector2Array) -> Dictionary:
	if poly.size() < 3:
		return {}
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	if min_x >= max_x or min_z >= max_z:
		return {}
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	}


func _bbox_overlaps_or_touches(a: Dictionary, b: Dictionary, gap: float) -> bool:
	var min_ax := float(a.get("min_x", INF)) - gap
	var max_ax := float(a.get("max_x", -INF)) + gap
	var min_az := float(a.get("min_z", INF)) - gap
	var max_az := float(a.get("max_z", -INF)) + gap
	var min_bx := float(b.get("min_x", INF))
	var max_bx := float(b.get("max_x", -INF))
	var min_bz := float(b.get("min_z", INF))
	var max_bz := float(b.get("max_z", -INF))
	if min_ax > max_bx or max_ax < min_bx:
		return false
	if min_az > max_bz or max_az < min_bz:
		return false
	return true


func _union_find_find(parent: Array, i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	var current := i
	while parent[current] != current:
		var next = parent[current]
		parent[current] = root
		current = next
	return root


func _union_find_union(parent: Array, a: int, b: int) -> void:
	var ra := _union_find_find(parent, a)
	var rb := _union_find_find(parent, b)
	if ra == rb:
		return
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb


func _filter_parts_outside_clip(
	parts: Array,
	clip_a: PackedVector2Array,
	clip_b: PackedVector2Array
) -> Array:
	var out: Array = []
	for piece_raw in parts:
		var piece: PackedVector2Array = _compact_polygon2d_xz(piece_raw, 0.001)
		if piece.size() < 3:
			continue
		var probe := _polygon_probe_point(piece)
		var inside_a := Geometry2D.is_point_in_polygon(probe, clip_a)
		var inside_b := Geometry2D.is_point_in_polygon(probe, clip_b)
		if not inside_a and not inside_b:
			out.push_back(piece)
	return out


func _polygon_probe_point(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var tri_local: PackedInt32Array = _stage_cache.polygon_triangulate(poly)
	if tri_local.size() >= 3:
		var ia := int(tri_local[0])
		var ib := int(tri_local[1])
		var ic := int(tri_local[2])
		if ia >= 0 and ib >= 0 and ic >= 0 and ia < poly.size() and ib < poly.size() and ic < poly.size():
			return (poly[ia] + poly[ib] + poly[ic]) / 3.0
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())


func _polygon_parts_total_area_abs_xz(parts: Array) -> float:
	var total := 0.0
	for raw in parts:
		var poly: PackedVector2Array = raw
		total += _polygon_area_abs_xz(poly)
	return total


func _polygon_area_abs_xz(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var sum := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum * 0.5)


func _resolve_rect_fill_interior_point_step(base_edge_len: float) -> float:
	if terrain_rect_fill_interior_point_step > 0.0001:
		return maxf(0.25, terrain_rect_fill_interior_point_step)
	return maxf(base_edge_len * 2.5, maxf(road_width * 0.75, sample_step * 8.0))


func _triangulate_fill_polygon_for_rect_mode(
	poly_raw: PackedVector2Array, base_edge_len: float, cancel_token: Dictionary = {}
) -> Array:
	if _is_generation_cancelled(cancel_token):
		return []
	if not _stage_cache.enabled:
		last_stats.fill_polygons_rebuilt += 1
		return _triangulate_fill_polygon_uncached(poly_raw, base_edge_len, cancel_token)
	var query: Dictionary = _stage_cache.query("fill_polygon", [poly_raw, base_edge_len,
		_resolve_rect_fill_interior_point_step(base_edge_len), terrain_fill_topology == TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.fill_polygons_reused += 1
		return cached.result.duplicate(true)
	last_stats.fill_polygons_rebuilt += 1
	_stage_cache.begin_scope()
	var triangles := _triangulate_fill_polygon_uncached(poly_raw, base_edge_len, cancel_token)
	var children: PackedStringArray = _stage_cache.end_scope()
	if not _is_generation_cancelled(cancel_token):
		_stage_cache.store(query, triangles.duplicate(true), children)
	return triangles


func _triangulate_fill_polygon_uncached(
	poly_raw: PackedVector2Array,
	base_edge_len: float,
	cancel_token: Dictionary = {}
) -> Array:
	var poly := _compact_polygon2d_xz(poly_raw, 0.001)
	if poly.size() < 3:
		return []
	var boundary_poly := _resample_polygon_edges_for_boolean_fill(poly, base_edge_len)
	if boundary_poly.size() >= 3:
		poly = boundary_poly

	var simple_tris := _triangulate_fill_polygon_points(poly)
	var area := _polygon_area_abs_xz(poly)
	var interior_step := _resolve_rect_fill_interior_point_step(base_edge_len)
	var target_tris := int(ceil(area / maxf(0.0001, interior_step * interior_step) * 2.0))
	if (
		terrain_fill_topology == TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY
		or area <= interior_step * interior_step * 8.0
		or simple_tris.size() >= target_tris
	):
		return simple_tris

	var points := PackedVector2Array()
	var point_keys: Dictionary = {}
	var quant := maxf(0.0005, interior_step * 0.25)
	for p in poly:
		_add_unique_fill_point(p, points, point_keys, quant)

	var box := _polygon_bbox_xz(poly)
	if box.is_empty():
		return simple_tris
	var min_x := float(box.get("min_x", 0.0))
	var max_x := float(box.get("max_x", 0.0))
	var min_z := float(box.get("min_z", 0.0))
	var max_z := float(box.get("max_z", 0.0))
	var z := min_z + interior_step * 0.5
	while z <= max_z:
		if _is_generation_cancelled(cancel_token):
			return []
		var x := min_x + interior_step * 0.5
		while x <= max_x:
			var p := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(p, poly):
				_add_unique_fill_point(p, points, point_keys, quant)
			x += interior_step
		z += interior_step

	if points.size() > TERRAIN_RECT_FILL_INTERIOR_MAX_POINTS_PER_POLYGON:
		var reduced := PackedVector2Array()
		var stride := float(points.size()) / float(TERRAIN_RECT_FILL_INTERIOR_MAX_POINTS_PER_POLYGON)
		var cursor := 0.0
		for _i in range(TERRAIN_RECT_FILL_INTERIOR_MAX_POINTS_PER_POLYGON):
			reduced.push_back(points[mini(points.size() - 1, int(floor(cursor)))])
			cursor += stride
		points = reduced

	if points.size() <= poly.size():
		return simple_tris
	var tri_indices: PackedInt32Array = _stage_cache.polygon_triangulate(points, true)
	if tri_indices.size() < 3:
		return simple_tris
	var out: Array = []
	var tri_count := tri_indices.size() - (tri_indices.size() % 3)
	for i in range(0, tri_count, 3):
		var ia := int(tri_indices[i])
		var ib := int(tri_indices[i + 1])
		var ic := int(tri_indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= points.size() or ib >= points.size() or ic >= points.size():
			continue
		var a := points[ia]
		var b := points[ib]
		var c := points[ic]
		if absf((b - a).cross(c - a)) <= 0.000001:
			continue
		var centroid := (a + b + c) / 3.0
		if not Geometry2D.is_point_in_polygon(centroid, poly):
			continue
		var tri := PackedVector2Array([a, b, c])
		if Geometry2D.is_polygon_clockwise(tri):
			tri.reverse()
		out.push_back(tri)
	if out.is_empty():
		return simple_tris
	return out


func _triangulate_fill_polygon_points(poly: PackedVector2Array) -> Array:
	var out: Array = []
	var tri_local: PackedInt32Array = _stage_cache.polygon_triangulate(poly)
	if tri_local.size() < 3:
		return out
	var tri_count := tri_local.size() - (tri_local.size() % 3)
	for i in range(0, tri_count, 3):
		var local_a := int(tri_local[i])
		var local_b := int(tri_local[i + 1])
		var local_c := int(tri_local[i + 2])
		if local_a < 0 or local_b < 0 or local_c < 0:
			continue
		if local_a >= poly.size() or local_b >= poly.size() or local_c >= poly.size():
			continue
		out.push_back(PackedVector2Array([poly[local_a], poly[local_b], poly[local_c]]))
	return out


func _pick_largest_polygon_part_xz(parts: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for raw in parts:
		var poly: PackedVector2Array = _compact_polygon2d_xz(raw, 0.001)
		if poly.size() < 3:
			continue
		var area := _polygon_area_abs_xz(poly)
		if area > best_area:
			best_area = area
			best = poly
	return best


func _sample_boolean_fill_vertex_height(
	point: Vector2, boundary_height_map: Dictionary, boundary_points: Array,
	default_y: float, boundary_height_lookup: Dictionary = {}
) -> float:
	if not _stage_cache.enabled or terrain_fill_height_assign_only:
		last_stats.fill_heights_rebuilt += 1
		return _sample_boolean_fill_vertex_height_uncached(point, boundary_height_map, boundary_points, default_y, boundary_height_lookup)
	var eps := maxf(0.0001, terrain_fill_height_match_epsilon)
	var cell := Vector2i(int(round(point.x / eps)), int(round(point.y / eps)))
	# Exact-cell averaging is already constant-time. Assign-only uses the
	# separately cached nearest-neighbor query, retaining its original tie order.
	var query: Dictionary = {}
	if _stage_cache.enabled and not terrain_fill_height_assign_only and not boundary_height_map.has(cell):
		var radius := _resolve_effective_fill_height_match_distance()
		var support: Variant
		if boundary_height_lookup.has("_cell_revisions"):
			var radius_cells := maxi(1, int(ceil(maxf(0.0, radius) / float(boundary_height_lookup.cell_size))) + 1)
			var region := _boundary_cell_support(point, boundary_height_lookup, radius_cells, false)
			# The entire selected cell neighborhood matters, including points
			# outside the radius consulted by the zero-weight fallback.
			support = ["cells", region] if not region.is_empty() else ["global", boundary_height_lookup._revision]
		else:
			# Arbitrary caller-owned grids need their actual ordered candidates;
			# only builder-owned, immutable-per-build grids have cell revisions.
			var ids := _collect_boundary_point_ids_in_radius(point, boundary_height_lookup, radius)
			if not ids.is_empty():
				var points := PackedVector3Array()
				for id in ids:
					if id >= 0 and id < boundary_points.size():
						points.append(boundary_points[id])
				if not points.is_empty():
					support = points
			else:
				support = ["global", _boundary_revision(boundary_points)]
		if support != null:
			query = _stage_cache.query("fill_height", [point, default_y, radius, terrain_fill_height_blend_falloff, support])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.fill_heights_reused += 1
		return cached.result
	last_stats.fill_heights_rebuilt += 1
	var height := _sample_boolean_fill_vertex_height_uncached(point, boundary_height_map, boundary_points, default_y, boundary_height_lookup)
	_stage_cache.store(query, height)
	return height


func _sample_boolean_fill_vertex_height_uncached(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	default_y: float,
	boundary_height_lookup: Dictionary = {}
) -> float:
	var eps := maxf(0.0001, terrain_fill_height_match_epsilon)
	var key := Vector2i(int(round(point.x / eps)), int(round(point.y / eps)))
	if boundary_height_map.has(key):
		var sum_and_count: Array = boundary_height_map.get(key, [default_y, 1])
		var count := maxi(1, int(sum_and_count[1]))
		return float(sum_and_count[0]) / float(count)

	if terrain_fill_height_assign_only:
		var nearest_lookup := _find_nearest_boundary_points(point, boundary_points, boundary_height_lookup, 2)
		if bool(nearest_lookup.get("found", false)):
			var lookup_nearest0_dist := float(nearest_lookup.get("d0", INF))
			var lookup_nearest1_dist := float(nearest_lookup.get("d1", INF))
			var lookup_nearest0_y := float(nearest_lookup.get("y0", default_y))
			var lookup_nearest1_y := float(nearest_lookup.get("y1", default_y))
			if lookup_nearest0_dist >= INF * 0.5:
				return default_y
			if lookup_nearest1_dist >= INF * 0.5:
				return lookup_nearest0_y
			var lookup_w0 := 1.0 / maxf(0.0001, lookup_nearest0_dist)
			var lookup_w1 := 1.0 / maxf(0.0001, lookup_nearest1_dist)
			return (lookup_nearest0_y * lookup_w0 + lookup_nearest1_y * lookup_w1) / (lookup_w0 + lookup_w1)
		var nearest0_y := default_y
		var nearest0_dist := INF
		var nearest1_y := default_y
		var nearest1_dist := INF
		for p_raw in boundary_points:
			var p: Vector3 = p_raw
			var d := Vector2(p.x, p.z).distance_to(point)
			if d < nearest0_dist:
				nearest1_dist = nearest0_dist
				nearest1_y = nearest0_y
				nearest0_dist = d
				nearest0_y = p.y
			elif d < nearest1_dist:
				nearest1_dist = d
				nearest1_y = p.y
		if nearest0_dist >= INF * 0.5:
			return default_y
		if nearest1_dist >= INF * 0.5:
			return nearest0_y
		var w0 := 1.0 / maxf(0.0001, nearest0_dist)
		var w1 := 1.0 / maxf(0.0001, nearest1_dist)
		return (nearest0_y * w0 + nearest1_y * w1) / (w0 + w1)

	var max_dist := _resolve_effective_fill_height_match_distance()

	var best_dist := max_dist
	var nearest_any_y := default_y
	var nearest_any_dist := INF
	var weighted_sum := 0.0
	var total_weight := 0.0
	var falloff := maxf(0.2, terrain_fill_height_blend_falloff)
	var candidate_ids := _collect_boundary_point_ids_in_radius(point, boundary_height_lookup, max_dist)
	var use_candidates := not candidate_ids.is_empty()
	var source_count := candidate_ids.size() if use_candidates else boundary_points.size()
	for source_idx in range(source_count):
		var p := Vector3.ZERO
		if use_candidates:
			var point_idx := int(candidate_ids[source_idx])
			if point_idx < 0 or point_idx >= boundary_points.size():
				continue
			p = boundary_points[point_idx]
		else:
			p = boundary_points[source_idx]
		var d := Vector2(p.x, p.z).distance_to(point)
		if d < nearest_any_dist:
			nearest_any_dist = d
			nearest_any_y = p.y
		if d > max_dist:
			continue
		if d <= best_dist:
			best_dist = d
		var edge_t := 1.0 - clampf(d / max_dist, 0.0, 1.0)
		var w := pow(edge_t, falloff)
		if w <= 0.000001:
			continue
		weighted_sum += p.y * w
		total_weight += w

	if total_weight <= 0.000001:
		if nearest_any_dist >= INF * 0.5 and use_candidates:
			var nearest := _find_nearest_boundary_points(point, boundary_points, boundary_height_lookup, 1)
			if bool(nearest.get("found", false)):
				return float(nearest.get("y0", default_y))
		return nearest_any_y

	var blended_y := weighted_sum / total_weight
	var nearest_t := 1.0 - clampf(best_dist / max_dist, 0.0, 1.0)
	var influence := nearest_t * nearest_t * (3.0 - 2.0 * nearest_t)
	return lerpf(default_y, blended_y, influence)


func _resolve_effective_fill_height_match_distance() -> float:
	var configured := maxf(0.0, terrain_fill_height_match_max_distance)
	if configured > 0.0001:
		return configured
	# 0 = auto mode, so fill smoothing still has visible influence by default.
	var auto_dist := maxf(road_width * 1.25, sample_step * 2.0)
	return maxf(0.5, auto_dist)


func _build_fill_heightmap_image() -> Image:
	return null


func _build_boundary_height_lookup(boundary_points: Array) -> Dictionary:
	if boundary_points.is_empty():
		return {}
	var configured_dist := _resolve_effective_fill_height_match_distance()
	var cell_size := maxf(0.5, configured_dist)
	if terrain_fill_height_assign_only:
		cell_size = maxf(
			cell_size,
			maxf(terrain_rect_fill_cell_size, maxf(sample_step * 4.0, road_width * 2.0))
		)
	var inv := 1.0 / maxf(0.0001, cell_size)
	var grid: Dictionary = {}
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483647, -2147483647)
	for i in range(boundary_points.size()):
		var p: Vector3 = boundary_points[i]
		var key := Vector2i(int(floor(p.x * inv)), int(floor(p.z * inv)))
		var ids: Array = grid.get(key, [])
		ids.push_back(i)
		grid[key] = ids
		min_cell.x = mini(min_cell.x, key.x)
		min_cell.y = mini(min_cell.y, key.y)
		max_cell.x = maxi(max_cell.x, key.x)
		max_cell.y = maxi(max_cell.y, key.y)
	if grid.is_empty():
		return {}
	var max_radius := maxi(abs(max_cell.x - min_cell.x), abs(max_cell.y - min_cell.y)) + 2
	var lookup := {
		"grid": grid,
		"cell_size": cell_size,
		"max_radius_cells": max_radius,
	}
	if _stage_cache.enabled:
		lookup["_revision"] = _boundary_revision(boundary_points)
		var revisions: Dictionary = {}
		for key: Vector2i in grid:
			var ordered := PackedVector3Array()
			for id: int in grid[key]:
				ordered.append(boundary_points[id])
			last_stats.height_cell_points_checked += ordered.size()
			var query: Dictionary = _stage_cache.query("height_cell", [ordered])
			var cached: Dictionary = _stage_cache.lookup(query)
			if cached.is_empty():
				# Never recycle IDs, including after eviction/public cache clear.
				_height_cell_revision += 1
				revisions[key] = _height_cell_revision
				_stage_cache.store(query, _height_cell_revision)
			else:
				revisions[key] = cached.result
		lookup["_cell_revisions"] = revisions
		lookup["_support_regions"] = {}
	return lookup


func _boundary_revision(points: Array) -> int:
	var snapshot := var_to_bytes(points)
	if snapshot != _height_snapshot:
		_height_revision += 1
		_height_snapshot = snapshot
	return _height_revision


func _collect_boundary_point_ids_in_radius(
	point: Vector2,
	boundary_height_lookup: Dictionary,
	radius: float
) -> Array:
	var out: Array = []
	var grid: Dictionary = boundary_height_lookup.get("grid", {})
	if grid.is_empty():
		return out
	var cell_size := maxf(0.0001, float(boundary_height_lookup.get("cell_size", 1.0)))
	var inv := 1.0 / cell_size
	var base_key := Vector2i(int(floor(point.x * inv)), int(floor(point.y * inv)))
	var radius_cells := maxi(1, int(ceil(maxf(0.0, radius) / cell_size)) + 1)
	var seen: Dictionary = {}
	for cx in range(base_key.x - radius_cells, base_key.x + radius_cells + 1):
		for cy in range(base_key.y - radius_cells, base_key.y + radius_cells + 1):
			var key := Vector2i(cx, cy)
			if not grid.has(key):
				continue
			var ids: Array = grid[key]
			for id_raw in ids:
				var idx := int(id_raw)
				if seen.has(idx):
					continue
				seen[idx] = true
				out.push_back(idx)
	return out


func _find_nearest_boundary_points(
	point: Vector2, boundary_points: Array, boundary_height_lookup: Dictionary, needed: int
) -> Dictionary:
	if not _stage_cache.enabled or not boundary_height_lookup.has("_cell_revisions"):
		return _find_nearest_boundary_points_uncached(point, boundary_points, boundary_height_lookup, needed)
	var cell_size: float = maxf(0.0001, boundary_height_lookup.cell_size)
	var max_radius: int = maxi(0, boundary_height_lookup.max_radius_cells)
	var probe_key := var_to_bytes([point, needed, cell_size]).hex_encode()
	var old: Dictionary = _nearest_probes.get(probe_key, {})
	var query: Dictionary = {}
	if not old.is_empty():
		if bool(old.fallback):
			query = _stage_cache.query("nearest_full", [point, needed, cell_size, max_radius, boundary_height_lookup._revision])
		elif int(old.radius) <= max_radius and (bool(old.get("complete", false)) or int(old.radius) == max_radius):
			var support := _boundary_cell_support(point, boundary_height_lookup, old.radius, true)
			query = _stage_cache.query("nearest_grid", [point, needed, cell_size, old.radius, support])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.nearest_queries_reused += 1
		return cached.result.duplicate()
	last_stats.nearest_queries_rebuilt += 1
	var trace := {"record": true}
	var result := _find_nearest_boundary_points_uncached(point, boundary_points, boundary_height_lookup, needed, trace)
	if bool(trace.get("fallback", true)):
		query = _stage_cache.query("nearest_full", [point, needed, cell_size, max_radius, boundary_height_lookup._revision])
	else:
		var support := _boundary_cell_support(point, boundary_height_lookup, trace.radius, true)
		query = _stage_cache.query("nearest_grid", [point, needed, cell_size, trace.radius, support])
	_nearest_probes.erase(probe_key)
	_nearest_probes[probe_key] = {"fallback": trace.get("fallback", true), "radius": trace.get("radius", 0),
		"complete": trace.get("complete", false)}
	while _nearest_probes.size() > _stage_cache.MAX_ENTRIES:
		_nearest_probes.erase(_nearest_probes.keys()[0])
	_stage_cache.store(query, result.duplicate())
	return result


func _boundary_cell_support(point: Vector2, lookup: Dictionary, limit: int, rings: bool) -> PackedInt64Array:
	var cell_size: float = maxf(0.0001, lookup.cell_size)
	var inv := 1.0 / cell_size
	var base_key := Vector2i(int(floor(point.x * inv)), int(floor(point.y * inv)))
	var region_key := Vector4i(base_key.x, base_key.y, limit, int(rings))
	var regions: Dictionary = lookup._support_regions
	if regions.has(region_key):
		last_stats.height_regions_reused += 1
		return regions[region_key]
	var revisions: Dictionary = lookup._cell_revisions
	var support := PackedInt64Array()
	# Match the original query's ring/cell/source order, including equal-distance
	# ties. An unchanged stopping prefix cannot be affected by cells beyond its
	# conservative safe distance. Exhausting the old grid is NOT a stopping proof:
	# it can be reused only with the same domain limit, not a newly expanded one.
	for radius in range(0 if rings else limit, limit + 1):
		for cx in range(base_key.x - radius, base_key.x + radius + 1):
			for cy in range(base_key.y - radius, base_key.y + radius + 1):
				if rings and radius > 0 and cx > base_key.x - radius and cx < base_key.x + radius \
						and cy > base_key.y - radius and cy < base_key.y + radius:
					continue
				var key := Vector2i(cx, cy)
				last_stats.height_dependency_cells += 1
				if revisions.has(key):
					support.append(revisions[key])
	regions[region_key] = support
	return support


func _find_nearest_boundary_points_uncached(
	point: Vector2,
	boundary_points: Array,
	boundary_height_lookup: Dictionary,
	needed: int,
	trace: Dictionary = {}
) -> Dictionary:
	if boundary_points.is_empty():
		return {"found": false}
	var grid: Dictionary = boundary_height_lookup.get("grid", {})
	if grid.is_empty():
		return _find_nearest_boundary_points_full_scan(point, boundary_points)
	var cell_size := maxf(0.0001, float(boundary_height_lookup.get("cell_size", 1.0)))
	var inv := 1.0 / cell_size
	var base_key := Vector2i(int(floor(point.x * inv)), int(floor(point.y * inv)))
	var max_radius := maxi(0, int(boundary_height_lookup.get("max_radius_cells", 0)))
	var nearest0_y := 0.0
	var nearest0_dist := INF
	var nearest1_y := 0.0
	var nearest1_dist := INF
	var seen_points: Dictionary = {}
	var record := bool(trace.get("record", false))
	for radius in range(max_radius + 1):
		if record:
			trace["radius"] = radius
		for cx in range(base_key.x - radius, base_key.x + radius + 1):
			for cy in range(base_key.y - radius, base_key.y + radius + 1):
				if radius > 0 and cx > base_key.x - radius and cx < base_key.x + radius and cy > base_key.y - radius and cy < base_key.y + radius:
					continue
				var key := Vector2i(cx, cy)
				if not grid.has(key):
					continue
				var ids: Array = grid[key]
				for id_raw in ids:
					var idx := int(id_raw)
					if seen_points.has(idx):
						continue
					seen_points[idx] = true
					if idx < 0 or idx >= boundary_points.size():
						continue
					var p: Vector3 = boundary_points[idx]
					var d := Vector2(p.x, p.z).distance_to(point)
					if d < nearest0_dist:
						nearest1_dist = nearest0_dist
						nearest1_y = nearest0_y
						nearest0_dist = d
						nearest0_y = p.y
					elif d < nearest1_dist:
						nearest1_dist = d
						nearest1_y = p.y
		var safe_dist := maxf(0.0, (float(radius) - 1.0) * cell_size)
		if needed <= 1 and nearest0_dist < INF * 0.5 and nearest0_dist <= safe_dist:
			if record:
				trace["complete"] = true
			break
		if needed > 1 and nearest1_dist < INF * 0.5 and nearest1_dist <= safe_dist:
			if record:
				trace["complete"] = true
			break
	if record:
		trace["fallback"] = nearest0_dist >= INF * 0.5
	if nearest0_dist >= INF * 0.5:
		return _find_nearest_boundary_points_full_scan(point, boundary_points)
	return {
		"found": true,
		"y0": nearest0_y,
		"d0": nearest0_dist,
		"y1": nearest1_y,
		"d1": nearest1_dist,
	}


func _find_nearest_boundary_points_full_scan(point: Vector2, boundary_points: Array) -> Dictionary:
	var nearest0_y := 0.0
	var nearest0_dist := INF
	var nearest1_y := 0.0
	var nearest1_dist := INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var d := Vector2(p.x, p.z).distance_to(point)
		if d < nearest0_dist:
			nearest1_dist = nearest0_dist
			nearest1_y = nearest0_y
			nearest0_dist = d
			nearest0_y = p.y
		elif d < nearest1_dist:
			nearest1_dist = d
			nearest1_y = p.y
	if nearest0_dist >= INF * 0.5:
		return {"found": false}
	return {
		"found": true,
		"y0": nearest0_y,
		"d0": nearest0_dist,
		"y1": nearest1_y,
		"d1": nearest1_dist,
	}


func _sample_fill_vertex_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	heightmap_image: Image,
	boundary_height_lookup: Dictionary = {}
) -> float:
	return _sample_boolean_fill_vertex_height(point, boundary_height_map, boundary_points, base_y, boundary_height_lookup)


func _min_distance_to_road_loops_xz(
	point: Vector2,
	road_loops: Array,
	road_distance_lookup: Dictionary = {},
	max_search_dist: float = INF
) -> float:
	if not road_distance_lookup.is_empty():
		return _min_distance_to_segment_lookup(point, road_distance_lookup, max_search_dist)
	var best := INF
	for raw in road_loops:
		var loop: PackedVector2Array = raw
		if loop.size() < 2:
			continue
		for i in range(loop.size()):
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % loop.size()]
			var d := _distance_point_to_segment_2d(point, a, b)
			if d < best:
				best = d
	return best


func _build_road_loop_distance_lookup(road_loops: Array, cell_size_hint: float) -> Dictionary:
	var segments: Array = []
	for raw in road_loops:
		var loop: PackedVector2Array = raw
		if loop.size() < 2:
			continue
		for i in range(loop.size()):
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % loop.size()]
			if a.distance_to(b) <= 0.0001:
				continue
			segments.push_back({
				"a": a,
				"b": b,
				"min": Vector2(minf(a.x, b.x), minf(a.y, b.y)),
				"max": Vector2(maxf(a.x, b.x), maxf(a.y, b.y)),
			})
	return _build_2d_segment_distance_lookup(segments, cell_size_hint)


func _build_polygon_edge_lookup(poly: PackedVector2Array) -> Dictionary:
	if poly.size() < 2:
		return {}
	var segments: Array = []
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if a.distance_to(b) <= 0.0001:
			continue
		segments.push_back({
			"a": a,
			"b": b,
			"min": Vector2(minf(a.x, b.x), minf(a.y, b.y)),
			"max": Vector2(maxf(a.x, b.x), maxf(a.y, b.y)),
			"source_idx": i,
		})
	return _build_2d_segment_distance_lookup(segments, maxf(0.25, terrain_rect_fill_cell_size))


func _build_2d_segment_distance_lookup(segments: Array, cell_size_hint: float) -> Dictionary:
	if segments.is_empty():
		return {}
	var cell_size := maxf(0.25, cell_size_hint)
	var inv := 1.0 / cell_size
	var grid: Dictionary = {}
	for i in range(segments.size()):
		var seg: Dictionary = segments[i]
		var min_v: Vector2 = seg.get("min", Vector2.ZERO)
		var max_v: Vector2 = seg.get("max", Vector2.ZERO)
		var min_cx := int(floor(min_v.x * inv))
		var max_cx := int(floor(max_v.x * inv))
		var min_cy := int(floor(min_v.y * inv))
		var max_cy := int(floor(max_v.y * inv))
		for cx in range(min_cx, max_cx + 1):
			for cy in range(min_cy, max_cy + 1):
				var key := Vector2i(cx, cy)
				var ids: Array = grid.get(key, [])
				ids.push_back(i)
				grid[key] = ids
	if grid.is_empty():
		return {}
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483647, -2147483647)
	return {
		"segments": segments,
		"grid": grid,
		"cell_size": cell_size,
		"max_radius_cells": _segment_lookup_max_radius_cells(grid),
	}


func _min_distance_to_segment_lookup(point: Vector2, lookup: Dictionary, max_search_dist: float) -> float:
	var segments: Array = lookup.get("segments", [])
	var grid: Dictionary = lookup.get("grid", {})
	if segments.is_empty() or grid.is_empty():
		return max_search_dist
	var cell_size := maxf(0.0001, float(lookup.get("cell_size", 1.0)))
	var inv := 1.0 / cell_size
	var base_key := Vector2i(int(floor(point.x * inv)), int(floor(point.y * inv)))
	var max_lookup_radius := maxi(1, int(lookup.get("max_radius_cells", 1)))
	var radius_cells := max_lookup_radius
	if max_search_dist < INF * 0.5:
		radius_cells = mini(radius_cells, maxi(1, int(ceil(maxf(0.0, max_search_dist) / cell_size)) + 1))
	var best := max_search_dist
	var found := false
	var seen: Dictionary = {}
	for radius in range(radius_cells + 1):
		for cx in range(base_key.x - radius, base_key.x + radius + 1):
			for cy in range(base_key.y - radius, base_key.y + radius + 1):
				if radius > 0 and cx > base_key.x - radius and cx < base_key.x + radius and cy > base_key.y - radius and cy < base_key.y + radius:
					continue
				var key := Vector2i(cx, cy)
				if not grid.has(key):
					continue
				var ids: Array = grid[key]
				for id_raw in ids:
					var idx := int(id_raw)
					if seen.has(idx):
						continue
					seen[idx] = true
					if idx < 0 or idx >= segments.size():
						continue
					var seg: Dictionary = segments[idx]
					var min_v: Vector2 = seg.get("min", Vector2.ZERO)
					var max_v: Vector2 = seg.get("max", Vector2.ZERO)
					if point.x < min_v.x - best or point.x > max_v.x + best:
						continue
					if point.y < min_v.y - best or point.y > max_v.y + best:
						continue
					var a: Vector2 = seg.get("a", Vector2.ZERO)
					var b: Vector2 = seg.get("b", Vector2.ZERO)
					var d := _distance_point_to_segment_2d(point, a, b)
					if d < best:
						best = d
						found = true
		var safe_dist := maxf(0.0, (float(radius) - 1.0) * cell_size)
		if found and best <= safe_dist:
			break
	return best


func _collect_segment_lookup_ids_for_box(lookup: Dictionary, box: Dictionary) -> Array:
	var out: Array = []
	var segments: Array = lookup.get("segments", [])
	var grid: Dictionary = lookup.get("grid", {})
	if segments.is_empty() or grid.is_empty() or box.is_empty():
		return out
	var cell_size := maxf(0.0001, float(lookup.get("cell_size", 1.0)))
	var inv := 1.0 / cell_size
	var min_x := float(box.get("min_x", INF))
	var max_x := float(box.get("max_x", -INF))
	var min_y := float(box.get("min_z", INF))
	var max_y := float(box.get("max_z", -INF))
	if min_x > max_x or min_y > max_y:
		return out
	var min_cx := int(floor(min_x * inv)) - 1
	var max_cx := int(floor(max_x * inv)) + 1
	var min_cy := int(floor(min_y * inv)) - 1
	var max_cy := int(floor(max_y * inv)) + 1
	var seen: Dictionary = {}
	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			var key := Vector2i(cx, cy)
			if not grid.has(key):
				continue
			var ids: Array = grid[key]
			for id_raw in ids:
				var idx := int(id_raw)
				if seen.has(idx):
					continue
				seen[idx] = true
				if idx < 0 or idx >= segments.size():
					continue
				var seg: Dictionary = segments[idx]
				var seg_min: Vector2 = seg.get("min", Vector2.ZERO)
				var seg_max: Vector2 = seg.get("max", Vector2.ZERO)
				if seg_max.x < min_x or seg_min.x > max_x:
					continue
				if seg_max.y < min_y or seg_min.y > max_y:
					continue
				out.push_back(idx)
	return out


func _segment_lookup_max_radius_cells(grid: Dictionary) -> int:
	if grid.is_empty():
		return 1
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483647, -2147483647)
	for key_raw in grid.keys():
		var key: Vector2i = key_raw
		min_cell.x = mini(min_cell.x, key.x)
		min_cell.y = mini(min_cell.y, key.y)
		max_cell.x = maxi(max_cell.x, key.x)
		max_cell.y = maxi(max_cell.y, key.y)
	return maxi(abs(max_cell.x - min_cell.x), abs(max_cell.y - min_cell.y)) + 2


func _collect_segment_lookup_source_ids(point: Vector2, lookup: Dictionary, radius: float) -> Array:
	var out: Array = []
	var segments: Array = lookup.get("segments", [])
	var grid: Dictionary = lookup.get("grid", {})
	if segments.is_empty() or grid.is_empty():
		return out
	var cell_size := maxf(0.0001, float(lookup.get("cell_size", 1.0)))
	var inv := 1.0 / cell_size
	var base_key := Vector2i(int(floor(point.x * inv)), int(floor(point.y * inv)))
	var radius_cells := maxi(1, int(ceil(maxf(0.0, radius) / cell_size)) + 1)
	var seen_segments: Dictionary = {}
	var seen_sources: Dictionary = {}
	for cx in range(base_key.x - radius_cells, base_key.x + radius_cells + 1):
		for cy in range(base_key.y - radius_cells, base_key.y + radius_cells + 1):
			var key := Vector2i(cx, cy)
			if not grid.has(key):
				continue
			var ids: Array = grid[key]
			for id_raw in ids:
				var idx := int(id_raw)
				if seen_segments.has(idx):
					continue
				seen_segments[idx] = true
				if idx < 0 or idx >= segments.size():
					continue
				var seg: Dictionary = segments[idx]
				var min_v: Vector2 = seg.get("min", Vector2.ZERO)
				var max_v: Vector2 = seg.get("max", Vector2.ZERO)
				if point.x < min_v.x - radius or point.x > max_v.x + radius:
					continue
				if point.y < min_v.y - radius or point.y > max_v.y + radius:
					continue
				var source_idx := int(seg.get("source_idx", idx))
				if seen_sources.has(source_idx):
					continue
				seen_sources[source_idx] = true
				out.push_back(source_idx)
	return out


func _fill_edge_height_cache_key(a: Vector2, b: Vector2) -> String:
	var scale := 100000.0
	var ax := int(round(a.x * scale))
	var ay := int(round(a.y * scale))
	var bx := int(round(b.x * scale))
	var by := int(round(b.y * scale))
	if ax > bx or (ax == bx and ay > by):
		var tx := ax
		var ty := ay
		ax = bx
		ay = by
		bx = tx
		by = ty
	return "%s,%s|%s,%s" % [ax, ay, bx, by]


func _fill_vertex_cache_key(point: Vector2) -> Vector2i:
	var scale := 100000.0
	return Vector2i(int(round(point.x * scale)), int(round(point.y * scale)))


func _sample_fill_vertex_height_cached(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	heightmap_image: Image,
	fill_vertex_height_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> float:
	var key := _fill_vertex_cache_key(point)
	if fill_vertex_height_cache.has(key):
		return float(fill_vertex_height_cache[key])
	var y := _sample_fill_vertex_height(
		point,
		boundary_height_map,
		boundary_points,
		base_y,
		heightmap_image,
		boundary_height_lookup
	)
	fill_vertex_height_cache[key] = y
	return y


func _get_or_create_fill_vertex(
	point: Vector2,
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	fill_vertex_index_cache: Dictionary
) -> int:
	var key := _fill_vertex_cache_key(point)
	if fill_vertex_index_cache.has(key):
		return int(fill_vertex_index_cache[key])
	var p := Vector3(point.x, y, point.y)
	var idx := verts.size()
	verts.push_back(p)
	normals.push_back(Vector3.UP)
	uvs.push_back(Vector2(p.x, p.z) * uv_length_scale)
	fill_vertex_index_cache[key] = idx
	return idx


func _get_fill_edge_midpoint_height(
	a: Vector2,
	b: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	heightmap_image: Image,
	edge_midpoint_height_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> float:
	var key := _fill_edge_height_cache_key(a, b)
	if edge_midpoint_height_cache.has(key):
		return float(edge_midpoint_height_cache[key])
	var midpoint := (a + b) * 0.5
	var y_mid := _sample_fill_vertex_height(
		midpoint,
		boundary_height_map,
		boundary_points,
		base_y,
		heightmap_image,
		boundary_height_lookup
	)
	edge_midpoint_height_cache[key] = y_mid
	return y_mid


func _fill_triangle_has_split_edge(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	edge_midpoint_height_cache: Dictionary
) -> bool:
	return (
		edge_midpoint_height_cache.has(_fill_edge_height_cache_key(a, b))
		or edge_midpoint_height_cache.has(_fill_edge_height_cache_key(b, c))
		or edge_midpoint_height_cache.has(_fill_edge_height_cache_key(c, a))
	)


func _fill_topology_uses_adaptive_triangulation() -> bool:
	return terrain_fill_topology == TERRAIN_FILL_TOPOLOGY_ADAPTIVE


func _get_fill_adaptive_max_depth() -> int:
	if not _fill_topology_uses_adaptive_triangulation():
		return 0
	return clampi(terrain_fill_adaptive_max_depth, 1, 8)


func _precompute_fill_split_edges(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	road_loops: Array,
	heightmap_image: Image,
	base_edge_len: float,
	edge_midpoint_height_cache: Dictionary,
	depth: int,
	boundary_height_lookup: Dictionary = {}
) -> bool:
	var max_depth := _get_fill_adaptive_max_depth()
	if depth >= max_depth:
		return false
	var forced_by_neighbor := _fill_triangle_has_split_edge(a, b, c, edge_midpoint_height_cache)
	var split_by_metric := _should_subdivide_fill_triangle(
		a,
		b,
		c,
		road_loops,
		heightmap_image,
		base_edge_len,
		depth
	)
	if not forced_by_neighbor and not split_by_metric:
		return false

	var changed := false
	var before := edge_midpoint_height_cache.size()
	var m_ab := (a + b) * 0.5
	var m_bc := (b + c) * 0.5
	var m_ca := (c + a) * 0.5
	_get_fill_edge_midpoint_height(
		a,
		b,
		boundary_height_map,
		boundary_points,
		base_y,
		heightmap_image,
		edge_midpoint_height_cache,
		boundary_height_lookup
	)
	_get_fill_edge_midpoint_height(
		b,
		c,
		boundary_height_map,
		boundary_points,
		base_y,
		heightmap_image,
		edge_midpoint_height_cache,
		boundary_height_lookup
	)
	_get_fill_edge_midpoint_height(
		c,
		a,
		boundary_height_map,
		boundary_points,
		base_y,
		heightmap_image,
		edge_midpoint_height_cache,
		boundary_height_lookup
	)
	if edge_midpoint_height_cache.size() != before:
		changed = true

	if _precompute_fill_split_edges(
		a,
		m_ab,
		m_ca,
		boundary_height_map,
		boundary_points,
		base_y,
		road_loops,
		heightmap_image,
		base_edge_len,
		edge_midpoint_height_cache,
		depth + 1,
		boundary_height_lookup
	):
		changed = true
	if _precompute_fill_split_edges(
		m_ab,
		b,
		m_bc,
		boundary_height_map,
		boundary_points,
		base_y,
		road_loops,
		heightmap_image,
		base_edge_len,
		edge_midpoint_height_cache,
		depth + 1,
		boundary_height_lookup
	):
		changed = true
	if _precompute_fill_split_edges(
		m_ca,
		m_bc,
		c,
		boundary_height_map,
		boundary_points,
		base_y,
		road_loops,
		heightmap_image,
		base_edge_len,
		edge_midpoint_height_cache,
		depth + 1,
		boundary_height_lookup
	):
		changed = true
	if _precompute_fill_split_edges(
		m_ab,
		m_bc,
		m_ca,
		boundary_height_map,
		boundary_points,
		base_y,
		road_loops,
		heightmap_image,
		base_edge_len,
		edge_midpoint_height_cache,
		depth + 1,
		boundary_height_lookup
	):
		changed = true
	return changed


func _should_subdivide_fill_triangle(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	_road_loops: Array,
	_heightmap_image: Image,
	base_edge_len: float,
	depth: int
) -> bool:
	if not _fill_topology_uses_adaptive_triangulation():
		return false
	var max_depth := _get_fill_adaptive_max_depth()
	if depth >= max_depth:
		return false
	var edge_factor := clampf(terrain_fill_adaptive_edge_factor, 0.25, 2.0)
	var edge_limit := maxf(0.2, base_edge_len * edge_factor)
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var max_edge := maxf(ab, maxf(bc, ca))
	if max_edge > edge_limit:
		return true
	var area2 := absf((b - a).cross(c - a))
	var area_factor := clampf(terrain_fill_adaptive_area_factor, 0.25, 4.0)
	var area_limit := edge_limit * edge_limit * area_factor
	return area2 > area_limit


func _append_fill_triangle_adaptive(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	road_loops: Array,
	heightmap_image: Image,
	y_a: float,
	y_b: float,
	y_c: float,
	base_edge_len: float,
	tri_limit: int,
	tri_stats: Dictionary,
	edge_midpoint_height_cache: Dictionary,
	fill_vertex_index_cache: Dictionary,
	depth: int,
	boundary_height_lookup: Dictionary = {}
) -> void:
	if tri_limit > 0 and int(tri_stats.get("tri_kept", 0)) >= tri_limit:
		return
	tri_stats["tri_candidates"] = int(tri_stats.get("tri_candidates", 0)) + 1
	var max_depth := _get_fill_adaptive_max_depth()
	if depth < max_depth and _fill_triangle_has_split_edge(a, b, c, edge_midpoint_height_cache):
		# Regular 1->4 split keeps triangulation shape stable and avoids fan-like blades.
		var m_ab := (a + b) * 0.5
		var m_bc := (b + c) * 0.5
		var m_ca := (c + a) * 0.5
		var y_m_ab := _get_fill_edge_midpoint_height(
			a,
			b,
			boundary_height_map,
			boundary_points,
			base_y,
			heightmap_image,
			edge_midpoint_height_cache,
			boundary_height_lookup
		)
		var y_m_bc := _get_fill_edge_midpoint_height(
			b,
			c,
			boundary_height_map,
			boundary_points,
			base_y,
			heightmap_image,
			edge_midpoint_height_cache,
			boundary_height_lookup
		)
		var y_m_ca := _get_fill_edge_midpoint_height(
			c,
			a,
			boundary_height_map,
			boundary_points,
			base_y,
			heightmap_image,
			edge_midpoint_height_cache,
			boundary_height_lookup
		)
		_append_fill_triangle_adaptive(
			a,
			m_ab,
			m_ca,
			verts,
			normals,
			uvs,
			terrain_indices,
			boundary_height_map,
			boundary_points,
			base_y,
			road_loops,
			heightmap_image,
			y_a,
			y_m_ab,
			y_m_ca,
			base_edge_len,
			tri_limit,
			tri_stats,
			edge_midpoint_height_cache,
			fill_vertex_index_cache,
			depth + 1,
			boundary_height_lookup
		)
		_append_fill_triangle_adaptive(
			m_ab,
			b,
			m_bc,
			verts,
			normals,
			uvs,
			terrain_indices,
			boundary_height_map,
			boundary_points,
			base_y,
			road_loops,
			heightmap_image,
			y_m_ab,
			y_b,
			y_m_bc,
			base_edge_len,
			tri_limit,
			tri_stats,
			edge_midpoint_height_cache,
			fill_vertex_index_cache,
			depth + 1,
			boundary_height_lookup
		)
		_append_fill_triangle_adaptive(
			m_ca,
			m_bc,
			c,
			verts,
			normals,
			uvs,
			terrain_indices,
			boundary_height_map,
			boundary_points,
			base_y,
			road_loops,
			heightmap_image,
			y_m_ca,
			y_m_bc,
			y_c,
			base_edge_len,
			tri_limit,
			tri_stats,
			edge_midpoint_height_cache,
			fill_vertex_index_cache,
			depth + 1,
			boundary_height_lookup
		)
		_append_fill_triangle_adaptive(
			m_ab,
			m_bc,
			m_ca,
			verts,
			normals,
			uvs,
			terrain_indices,
			boundary_height_map,
			boundary_points,
			base_y,
			road_loops,
			heightmap_image,
			y_m_ab,
			y_m_bc,
			y_m_ca,
			base_edge_len,
			tri_limit,
			tri_stats,
			edge_midpoint_height_cache,
			fill_vertex_index_cache,
			depth + 1,
			boundary_height_lookup
		)
		return

	var i_a := _get_or_create_fill_vertex(a, y_a, verts, normals, uvs, fill_vertex_index_cache)
	var i_b := _get_or_create_fill_vertex(b, y_b, verts, normals, uvs, fill_vertex_index_cache)
	var i_c := _get_or_create_fill_vertex(c, y_c, verts, normals, uvs, fill_vertex_index_cache)
	if i_a == i_b or i_b == i_c or i_c == i_a:
		return
	tri_stats["tri_kept"] = int(tri_stats.get("tri_kept", 0)) + 1
	_append_terrain_triangle_indices(terrain_indices, verts, i_a, i_b, i_c)


func _append_terrain_from_path_rows(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	if _is_generation_cancelled(cancel_token):
		return
	var profile_total_start := _profile_start()
	var profile_road_tris_start := _profile_start()
	var road_tris := _build_road_tri_xz_cache(verts, lane_indices, shoulder_indices, sidewalk_indices, path_rows)
	_profile_log("path-row terrain build road tri cache", profile_road_tris_start, "tris=%s" % [road_tris.size()])
	var terrain_noise := _build_terrain_noise()
	var use_blocked_sides := not blocked_side_vertices.is_empty()
	var continuity_width := 0.001
	var growth_recovery_floor := continuity_width * 8.0
	var group_idx := -1
	for rows_raw in path_rows:
		group_idx += 1
		if _is_generation_cancelled(cancel_token):
			return
		var rows: Array = rows_raw
		if rows.size() < 2:
			continue
		var profile_group_start := _profile_start()
		var strip_query := _make_strip_cache_query(verts, normals, uvs, rows, blocked_side_vertices, road_tris)
		if _replay_strip_cache(strip_query, verts, normals, uvs, terrain_indices):
			last_stats["strips_reused"] += 1
			last_stats["rows_reused"] += rows.size()
			_profile_log("path-row terrain reused strip", profile_group_start, "group=%s rows=%s" % [group_idx, rows.size()])
			continue
		last_stats["strips_rebuilt"] += 1
		_stage_cache.begin_group()
		last_stats["rows_rebuilt"] += rows.size()
		var strip_vertex_start := verts.size()
		var strip_index_start := terrain_indices.size()
		var terrain_subdiv_count := _resolve_terrain_subdivisions_for_rows(rows)
		_debug_log(
			"terrain adaptive rows=%s subdiv=%s"
			% [rows.size(), terrain_subdiv_count]
		)

		var left_outer_ids := PackedInt32Array()
		left_outer_ids.resize(rows.size())
		var right_outer_ids := PackedInt32Array()
		right_outer_ids.resize(rows.size())
		var left_outer_points: Array[Vector3] = []
		left_outer_points.resize(rows.size())
		var right_outer_points: Array[Vector3] = []
		right_outer_points.resize(rows.size())
		var left_base_ids := PackedInt32Array()
		left_base_ids.resize(rows.size())
		var right_base_ids := PackedInt32Array()
		right_base_ids.resize(rows.size())
		var left_applied_widths := PackedFloat32Array()
		left_applied_widths.resize(rows.size())
		var right_applied_widths := PackedFloat32Array()
		right_applied_widths.resize(rows.size())
		for init_idx in range(rows.size()):
			left_outer_ids[init_idx] = -1
			right_outer_ids[init_idx] = -1
			left_base_ids[init_idx] = -1
			right_base_ids[init_idx] = -1
			left_applied_widths[init_idx] = 0.0
			right_applied_widths[init_idx] = 0.0

		var profile_width_start := _profile_start()
		for row_idx in range(rows.size()):
			if (row_idx % 64) == 0 and _is_generation_cancelled(cancel_token):
				return
			var row: Dictionary = rows[row_idx]
			var row_edges: Array = row.get("row_edges", [])
			if row_edges.size() < 6:
				continue

			var left_w_requested := maxf(0.0, float(row.get("terrain_left_width", terrain_left_width)))
			var right_w_requested := maxf(0.0, float(row.get("terrain_right_width", terrain_right_width)))
			if use_blocked_sides:
				if (
					blocked_side_vertices.has(int(row_edges[0]))
					or blocked_side_vertices.has(int(row_edges[1]))
				):
					left_w_requested = 0.0
				if (
					blocked_side_vertices.has(int(row_edges[4]))
					or blocked_side_vertices.has(int(row_edges[5]))
				):
					right_w_requested = 0.0
			# Collapse detection is geometric-only; do not couple it to road clearance.
			var collapsed_eps := 0.02
			var left_outer_idx := int(row_edges[0])
			var left_inner_collapse_idx := int(row_edges[2])
			if (
				left_outer_idx >= 0
				and left_outer_idx < verts.size()
				and left_inner_collapse_idx >= 0
				and left_inner_collapse_idx < verts.size()
				and verts[left_outer_idx].distance_to(verts[left_inner_collapse_idx]) <= collapsed_eps
			):
				left_w_requested = 0.0
			var right_outer_idx := int(row_edges[5])
			var right_inner_collapse_idx := int(row_edges[3])
			if (
				right_outer_idx >= 0
				and right_outer_idx < verts.size()
				and right_inner_collapse_idx >= 0
				and right_inner_collapse_idx < verts.size()
				and verts[right_outer_idx].distance_to(verts[right_inner_collapse_idx]) <= collapsed_eps
			):
				right_w_requested = 0.0
			var left_w := left_w_requested
			var right_w := right_w_requested
			if left_w <= 0.0001 and right_w <= 0.0001:
				continue

			var row_dir := Vector3(row.get("out_dir", Vector3.FORWARD))
			row_dir.y = 0.0
			if row_dir.length() < 0.001:
				row_dir = Vector3.FORWARD
			else:
				row_dir = row_dir.normalized()

			left_base_ids[row_idx] = int(row_edges[0])
			right_base_ids[row_idx] = int(row_edges[5])

			if left_w > 0.0001:
				var left_top_idx := int(row_edges[0])
				var left_inner_idx := int(row_edges[2])
				if left_top_idx >= 0 and left_top_idx < verts.size() and left_inner_idx >= 0 and left_inner_idx < verts.size():
					var left_top := verts[left_top_idx]
					var left_out := left_top - verts[left_inner_idx]
					left_out.y = 0.0
					if left_out.length() < 0.001:
						left_out = Vector3(row_dir.z, 0.0, -row_dir.x)
					if left_out.length() < 0.001:
						left_out = Vector3.LEFT
					else:
						left_out = left_out.normalized()
					var left_prev_idx := row_idx - 1
					if left_prev_idx < 0 or int(left_outer_ids[left_prev_idx]) < 0:
						left_prev_idx = -1
					if left_prev_idx >= 0:
						if terrain_growth_max_delta_per_row > 0.0001:
							var prev_left_w := float(left_applied_widths[left_prev_idx])
							if prev_left_w > growth_recovery_floor:
								left_w = minf(left_w, prev_left_w + terrain_growth_max_delta_per_row)
						left_w = _limit_terrain_growth_width_for_segment(
							verts,
							left_top,
							left_out,
							left_w,
							left_prev_idx,
							row_idx,
							left_outer_points,
							left_outer_ids,
							left_base_ids,
							right_base_ids,
							road_tris
						)
					if left_w <= 0.0001:
						left_w = continuity_width
					left_applied_widths[row_idx] = left_w
					var left_terrain := left_top + left_out * left_w
					var left_idx := verts.size()
					verts.push_back(left_terrain)
					normals.push_back(Vector3.UP)
					uvs.push_back(Vector2(left_terrain.x, left_terrain.z) * uv_length_scale)
					left_outer_points[row_idx] = left_terrain
					left_outer_ids[row_idx] = left_idx

			if right_w > 0.0001:
				var right_top_idx := int(row_edges[5])
				var right_inner_idx := int(row_edges[3])
				if right_top_idx >= 0 and right_top_idx < verts.size() and right_inner_idx >= 0 and right_inner_idx < verts.size():
					var right_top := verts[right_top_idx]
					var right_out := right_top - verts[right_inner_idx]
					right_out.y = 0.0
					if right_out.length() < 0.001:
						right_out = Vector3(-row_dir.z, 0.0, row_dir.x)
					if right_out.length() < 0.001:
						right_out = Vector3.RIGHT
					else:
						right_out = right_out.normalized()
					var right_prev_idx := row_idx - 1
					if right_prev_idx < 0 or int(right_outer_ids[right_prev_idx]) < 0:
						right_prev_idx = -1
					if right_prev_idx >= 0:
						if terrain_growth_max_delta_per_row > 0.0001:
							var prev_right_w := float(right_applied_widths[right_prev_idx])
							if prev_right_w > growth_recovery_floor:
								right_w = minf(right_w, prev_right_w + terrain_growth_max_delta_per_row)
						right_w = _limit_terrain_growth_width_for_segment(
							verts,
							right_top,
							right_out,
							right_w,
							right_prev_idx,
							row_idx,
							right_outer_points,
							right_outer_ids,
							right_base_ids,
							left_base_ids,
							road_tris
						)
					if right_w <= 0.0001:
						right_w = continuity_width
					right_applied_widths[row_idx] = right_w
					var right_terrain := right_top + right_out * right_w
					var right_idx := verts.size()
					verts.push_back(right_terrain)
					normals.push_back(Vector3.UP)
					uvs.push_back(Vector2(right_terrain.x, right_terrain.z) * uv_length_scale)
					right_outer_points[row_idx] = right_terrain
					right_outer_ids[row_idx] = right_idx
		_profile_log("path-row terrain build side chains", profile_width_start, "group=%s rows=%s" % [group_idx, rows.size()])

		var profile_stabilize_start := _profile_start()
		if terrain_artifact_safe_stitch:
			_stabilize_terrain_side_chain(
				verts,
				normals,
				uvs,
				left_base_ids,
				left_outer_ids,
				left_outer_points,
				left_applied_widths
			)
			_stabilize_terrain_side_chain(
				verts,
				normals,
				uvs,
				right_base_ids,
				right_outer_ids,
				right_outer_points,
				right_applied_widths
			)
		_profile_log("path-row terrain stabilize side chains", profile_stabilize_start, "group=%s" % [group_idx])

		if _is_generation_cancelled(cancel_token):
			return
		var profile_rings_start := _profile_start()
		var left_ring_ids := _build_terrain_side_rings(
			verts,
			normals,
			uvs,
			left_base_ids,
			left_outer_ids,
			rows.size(),
			terrain_subdiv_count,
			terrain_noise,
			cancel_token
		)
		if _is_generation_cancelled(cancel_token):
			return
		var right_ring_ids := _build_terrain_side_rings(
			verts,
			normals,
			uvs,
			right_base_ids,
			right_outer_ids,
			rows.size(),
			terrain_subdiv_count,
			terrain_noise,
			cancel_token
		)
		if _is_generation_cancelled(cancel_token):
			return
		_profile_log("path-row terrain build rings", profile_rings_start, "group=%s subdiv=%s" % [group_idx, terrain_subdiv_count])

		var terrain_start := terrain_indices.size()
		var profile_indices_start := _profile_start()
		for span_idx in range(rows.size() - 1):
			if (span_idx % 64) == 0 and _is_generation_cancelled(cancel_token):
				return
			for ring_i in range(terrain_subdiv_count):
				var left_inner_ring: Array = left_ring_ids[ring_i]
				var left_outer_ring: Array = left_ring_ids[ring_i + 1]
				var left_inner0 := int(left_inner_ring[span_idx])
				var left_inner1 := int(left_inner_ring[span_idx + 1])
				var left_outer0 := int(left_outer_ring[span_idx])
				var left_outer1 := int(left_outer_ring[span_idx + 1])
				if left_inner0 >= 0 and left_inner1 >= 0 and left_outer0 >= 0 and left_outer1 >= 0:
					# Keep road-edge vertices fixed and only deform outward rings.
					_append_terrain_quad_indices(
						terrain_indices,
						verts,
						left_outer0,
						left_inner0,
						left_outer1,
						left_inner1
					)

				var right_inner_ring: Array = right_ring_ids[ring_i]
				var right_outer_ring: Array = right_ring_ids[ring_i + 1]
				var right_inner0 := int(right_inner_ring[span_idx])
				var right_inner1 := int(right_inner_ring[span_idx + 1])
				var right_outer0 := int(right_outer_ring[span_idx])
				var right_outer1 := int(right_outer_ring[span_idx + 1])
				if right_inner0 >= 0 and right_inner1 >= 0 and right_outer0 >= 0 and right_outer1 >= 0:
					_append_terrain_quad_indices(
						terrain_indices,
						verts,
						right_inner0,
						right_outer0,
						right_inner1,
						right_outer1
					)

		if terrain_skirt_depth > 0.0001:
			if _is_generation_cancelled(cancel_token):
				return
			_append_terrain_side_skirts(
				verts,
				normals,
				uvs,
				terrain_indices,
				left_ring_ids,
				terrain_subdiv_count,
				terrain_skirt_depth
			)
			_append_terrain_side_skirts(
				verts,
				normals,
				uvs,
				terrain_indices,
				right_ring_ids,
				terrain_subdiv_count,
				terrain_skirt_depth
			)
		_profile_log("path-row terrain append indices", profile_indices_start, "group=%s tris=%s" % [group_idx, maxi(0, (terrain_indices.size() - terrain_start) / 3)])
		_profile_log("path-row terrain group total", profile_group_start, "group=%s rows=%s" % [group_idx, rows.size()])
		if not _is_generation_cancelled(cancel_token):
			last_stats["vertices_built"] += verts.size() - strip_vertex_start
			_store_strip_cache(strip_query, verts, normals, uvs, terrain_indices, strip_vertex_start, strip_index_start)
	_profile_log("path-row terrain total", profile_total_start, "terrain_tris=%s road_tris_cache=%s" % [terrain_indices.size() / 3, road_tris.size()])


func _stabilize_terrain_side_chain(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	base_ids: PackedInt32Array,
	outer_ids: PackedInt32Array,
	outer_points: Array[Vector3],
	applied_widths: PackedFloat32Array
) -> void:
	var count := mini(base_ids.size(), outer_ids.size())
	if count <= 0:
		return

	# Keep topology continuous: missing rows get a collapsed outer vertex on the base edge.
	for i in range(count):
		var outer_idx := int(outer_ids[i])
		if outer_idx >= 0 and outer_idx < verts.size():
			outer_points[i] = verts[outer_idx]
			continue
		var base_idx := int(base_ids[i])
		if base_idx < 0 or base_idx >= verts.size():
			continue
		var p := verts[base_idx]
		var new_idx := verts.size()
		verts.push_back(p)
		normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(p.x, p.z) * uv_length_scale)
		outer_ids[i] = new_idx
		outer_points[i] = p
		if i < applied_widths.size():
			applied_widths[i] = 0.0

	var smooth_passes := maxi(0, terrain_chain_smooth_passes)
	if smooth_passes <= 0 or count < 3:
		return

	var blend_allowed := PackedByteArray()
	blend_allowed.resize(count)
	for i in range(1, count - 1):
		if i >= applied_widths.size() or applied_widths[i] <= 0.0001:
			continue
		var prev_idx := int(outer_ids[i - 1])
		var curr_idx := int(outer_ids[i])
		var next_idx := int(outer_ids[i + 1])
		if prev_idx >= 0 and curr_idx >= 0 and next_idx >= 0 \
				and prev_idx < verts.size() and curr_idx < verts.size() and next_idx < verts.size():
			blend_allowed[i] = 1
	for _pass in range(smooth_passes):
		var next_points := _terrain_chain_blend(outer_points, blend_allowed)

		for i in range(count):
			outer_points[i] = next_points[i]
			var idx := int(outer_ids[i])
			if idx < 0 or idx >= verts.size():
				continue
			var p: Vector3 = outer_points[i]
			verts[idx] = p
			normals[idx] = Vector3.UP
			uvs[idx] = Vector2(p.x, p.z) * uv_length_scale


func _terrain_chain_blend(points: Array[Vector3], allowed: PackedByteArray) -> Array[Vector3]:
	var next: Array[Vector3] = points.duplicate()
	var count := allowed.size()
	for start in range(0, count, _stage_cache.BLEND_ROWS):
		var stop := mini(count, start + _stage_cache.BLEND_ROWS)
		var support_start := maxi(0, start - 1)
		var query: Dictionary = _stage_cache.query("chain_blend", [
			PackedVector3Array(points.slice(support_start, mini(count, stop + 1))),
			allowed.slice(start, stop), start - support_start])
		var cached: Dictionary = _stage_cache.lookup(query)
		var result := PackedVector3Array()
		if not cached.is_empty():
			result = cached.result
			last_stats.chain_blend_rows_reused += stop - start
		else:
			last_stats.chain_blend_rows_rebuilt += stop - start
			for i in range(start, stop):
				var p: Vector3 = points[i]
				if allowed[i] != 0:
					p = (points[i - 1] + points[i] * 2.0 + points[i + 1]) * 0.25
					p.y = points[i].y
				result.append(p)
			_stage_cache.store(query, result)
		for i in range(start, stop):
			next[i] = result[i - start]
	return next


func _terrain_skirt_drop_blend(values: PackedFloat32Array) -> PackedFloat32Array:
	var next := values.duplicate()
	var count := values.size()
	for start in range(0, count, _stage_cache.BLEND_ROWS):
		var stop := mini(count, start + _stage_cache.BLEND_ROWS)
		var support_start := maxi(0, start - 1)
		var query: Dictionary = _stage_cache.query("skirt_blend", [
			values.slice(support_start, mini(count, stop + 1)), start - support_start,
			stop - start, start == 0, stop == count])
		var cached: Dictionary = _stage_cache.lookup(query)
		var result := PackedFloat32Array()
		if not cached.is_empty():
			result = cached.result
			last_stats.skirt_blend_rows_reused += stop - start
		else:
			last_stats.skirt_blend_rows_rebuilt += stop - start
			for i in range(start, stop):
				result.append((values[i - 1] + values[i] * 2.0 + values[i + 1]) * 0.25 if i > 0 and i < count - 1 else values[i])
			_stage_cache.store(query, result)
		for i in range(start, stop):
			next[i] = result[i - start]
	return next


func _resolve_terrain_subdivisions_for_rows(rows: Array) -> int:
	var base_subdiv := maxi(1, terrain_subdivisions)
	if not terrain_adaptive_subdivisions_enabled:
		return base_subdiv

	var max_width := 0.0
	for row_raw in rows:
		var row: Dictionary = row_raw
		var left_w := maxf(0.0, float(row.get("terrain_left_width", terrain_left_width)))
		var right_w := maxf(0.0, float(row.get("terrain_right_width", terrain_right_width)))
		max_width = maxf(max_width, left_w)
		max_width = maxf(max_width, right_w)

	if max_width <= 0.0001:
		return base_subdiv

	var density_target := int(ceil(max_width * maxf(0.0, terrain_adaptive_subdivisions_per_meter)))
	var noise_target := 0
	if terrain_noise_enabled and terrain_noise_amplitude > 0.0001:
		var safe_frequency := maxf(0.0, terrain_noise_frequency)
		var nyquist_target := max_width * safe_frequency * 2.0
		noise_target = int(ceil(nyquist_target * maxf(0.1, terrain_adaptive_noise_quality)))
	var adaptive_target := maxi(base_subdiv, maxi(density_target, noise_target))
	var hard_cap := maxi(base_subdiv, terrain_adaptive_subdivisions_max)
	return clampi(adaptive_target, 1, hard_cap)


func _append_terrain_side_skirts(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	ring_ids: Array,
	subdivisions: int,
	depth: float
) -> void:
	if depth <= 0.0001:
		return
	if ring_ids.size() < subdivisions + 1:
		return
	if subdivisions < 1:
		return
	var inner_ring: Array = ring_ids[0]
	var outer_ring: Array = ring_ids[subdivisions]
	if inner_ring.is_empty() or outer_ring.is_empty():
		return
	var row_count := inner_ring.size()
	if row_count < 2:
		return
	_soften_outer_area_for_skirt(verts, normals, ring_ids, subdivisions)

	var start_chain: Array = []
	var end_chain: Array = []
	for ring_i in range(subdivisions + 1):
		var ring: Array = ring_ids[ring_i]
		if ring.size() != row_count:
			return
		start_chain.push_back(int(ring[0]))
		end_chain.push_back(int(ring[row_count - 1]))

	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, inner_ring, depth)
	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, outer_ring, depth)
	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, start_chain, depth)
	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, end_chain, depth)


func _soften_outer_area_for_skirt(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	ring_ids: Array,
	subdivisions: int
) -> void:
	var slope_limit := clampf(terrain_skirt_soften_slope_deg, 0.0, 89.0)
	var max_drop := maxf(0.0, terrain_skirt_soften_max_drop)
	var soften_power := maxf(0.1, terrain_skirt_soften_power)
	var area_rings := maxi(1, terrain_skirt_soften_area_rings)
	var area_falloff := maxf(0.1, terrain_skirt_soften_area_falloff)
	var smooth_passes := maxi(0, terrain_skirt_soften_row_smooth_passes)
	if slope_limit <= 0.0001 or max_drop <= 0.0001:
		return
	if subdivisions < 1:
		return
	if ring_ids.size() < subdivisions + 1:
		return
	var outer_ring: Array = ring_ids[subdivisions]
	var inner_ring: Array = ring_ids[maxi(0, subdivisions - 1)]
	var count := mini(outer_ring.size(), inner_ring.size())
	if count <= 0:
		return
	var row_drop := PackedFloat32Array()
	row_drop.resize(count)
	for i in range(count):
		row_drop[i] = 0.0
		var outer_idx := int(outer_ring[i])
		var inner_idx := int(inner_ring[i])
		if outer_idx < 0 or inner_idx < 0:
			continue
		if outer_idx >= verts.size() or inner_idx >= verts.size():
			continue
		var outer_p := verts[outer_idx]
		var inner_p := verts[inner_idx]
		row_drop[i] = _terrain_skirt_row_drop(outer_p, inner_p, slope_limit, max_drop, soften_power)

	if smooth_passes > 0 and count > 2:
		for _pass in range(smooth_passes):
			row_drop = _terrain_skirt_drop_blend(row_drop)

	for ring_offset in range(area_rings):
		var ring_idx := subdivisions - ring_offset
		if ring_idx < 0 or ring_idx >= ring_ids.size():
			break
		var ring: Array = ring_ids[ring_idx]
		var distance_factor := float(ring_offset + 1) / float(area_rings)
		var falloff := pow(distance_factor, area_falloff)
		for i in range(mini(count, ring.size())):
			var drop := row_drop[i] * falloff
			if drop <= 0.0001:
				continue
			var vi := int(ring[i])
			if vi < 0 or vi >= verts.size():
				continue
			var p := verts[vi]
			p.y -= drop
			verts[vi] = p
			if vi < normals.size():
				normals[vi] = Vector3.UP


func _terrain_skirt_row_drop(outer: Vector3, inner: Vector3, slope_limit: float, max_drop: float, power: float) -> float:
	var query: Dictionary = _stage_cache.query("skirt_drop", [outer, inner, slope_limit, max_drop, power])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.skirt_drops_reused += 1
		return cached.result
	last_stats.skirt_drops_rebuilt += 1
	var drop := 0.0
	var edge := outer - inner
	var edge_xz := Vector2(edge.x, edge.z).length()
	if edge_xz > 0.0001:
		var slope_deg := absf(rad_to_deg(atan2(edge.y, edge_xz)))
		if slope_deg < slope_limit:
			var t := 1.0 - (slope_deg / slope_limit)
			t = pow(clampf(t, 0.0, 1.0), power)
			drop = max_drop * t
	_stage_cache.store(query, drop)
	return drop


func _append_terrain_skirt_from_index_chain(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	chain: Array,
	depth: float
) -> void:
	if chain.size() < 2:
		return
	var steps := maxi(1, terrain_skirt_segments)
	var outward := maxf(0.0, terrain_skirt_outward)
	var profile := maxf(0.1, terrain_skirt_profile)
	var levels: Array = []
	levels.resize(steps + 1)
	var top_level: Array = []
	top_level.resize(chain.size())
	var center := Vector3.ZERO
	var center_count := 0
	for i in range(chain.size()):
		var top_idx := int(chain[i])
		top_level[i] = top_idx
		if top_idx >= 0 and top_idx < verts.size():
			center += verts[top_idx]
			center_count += 1
	levels[0] = top_level
	if center_count <= 0:
		return
	center /= float(center_count)

	var depth_offsets := PackedFloat64Array()
	var outward_offsets := PackedFloat64Array()
	for step_i in range(1, steps + 1):
		var t := float(step_i) / float(steps)
		depth_offsets.append(depth * pow(t, profile))
		outward_offsets.append(outward * sin(t * PI * 0.5))
	var columns: Array = []
	columns.resize(chain.size())
	for i in range(chain.size()):
		var top_idx := int(top_level[i])
		if top_idx >= 0 and top_idx < verts.size():
			var out_dir := _compute_skirt_outward_dir(verts, chain, i, center)
			columns[i] = _terrain_skirt_stage_column(verts[top_idx], out_dir, depth_offsets, outward_offsets)
	for step_i in range(1, steps + 1):
		var level: Array = []
		level.resize(chain.size())
		for i in range(chain.size()):
			level[i] = -1
			var top_idx := int(top_level[i])
			if top_idx < 0 or top_idx >= verts.size():
				continue
			var column: Dictionary = columns[i]
			var p: Vector3 = column.vertices[step_i - 1]
			var vi := verts.size()
			verts.push_back(p)
			normals.push_back(column.normal)
			uvs.push_back(column.uvs[step_i - 1])
			level[i] = vi
		levels[step_i] = level

	for step_i in range(steps):
		var upper: Array = levels[step_i]
		var lower: Array = levels[step_i + 1]
		for i in range(chain.size() - 1):
			var up0 := int(upper[i])
			var up1 := int(upper[i + 1])
			var lo0 := int(lower[i])
			var lo1 := int(lower[i + 1])
			if up0 < 0 or up1 < 0 or lo0 < 0 or lo1 < 0:
				continue
			_append_quad_indices(terrain_indices, up0, lo0, up1, lo1)


func _terrain_skirt_stage_column(top: Vector3, direction: Vector3,
		depth_offsets: PackedFloat64Array, outward_offsets: PackedFloat64Array) -> Dictionary:
	# Direction is freshly resolved from the current whole-chain center, with
	# the original neighbor fallback. A distant edit may legitimately change it.
	var query: Dictionary = _stage_cache.query("skirt_column", [top, direction, depth_offsets, outward_offsets, uv_length_scale])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.skirt_columns_reused += 1
		return cached.result
	last_stats.skirt_columns_rebuilt += 1
	var points := PackedVector3Array()
	var texture_points := PackedVector2Array()
	var normal := Vector3(direction.x, 0.35, direction.z)
	normal = Vector3.UP if normal.length() < 0.001 else normal.normalized()
	for i in range(depth_offsets.size()):
		var p := top + direction * outward_offsets[i] - Vector3.UP * depth_offsets[i]
		points.append(p)
		texture_points.append(Vector2(p.x, p.z) * uv_length_scale)
	var result := {"vertices": points, "normal": normal, "uvs": texture_points}
	_stage_cache.store(query, result)
	return result


func _compute_skirt_outward_dir(
	verts: PackedVector3Array,
	chain: Array,
	idx: int,
	center: Vector3
) -> Vector3:
	var curr_idx := int(chain[idx])
	if curr_idx < 0 or curr_idx >= verts.size():
		return Vector3.ZERO
	var curr := verts[curr_idx]
	var radial2 := Vector2(curr.x - center.x, curr.z - center.z)
	var radial := Vector3(radial2.x, 0.0, radial2.y)
	if radial.length() > 0.001:
		return radial.normalized()

	var prev_i := maxi(0, idx - 1)
	var next_i := mini(chain.size() - 1, idx + 1)
	var prev_idx := int(chain[prev_i])
	var next_idx := int(chain[next_i])
	if prev_idx >= 0 and prev_idx < verts.size() and next_idx >= 0 and next_idx < verts.size():
		var prev := verts[prev_idx]
		var next := verts[next_idx]
		var tan2 := Vector2(next.x - prev.x, next.z - prev.z)
		if tan2.length() > 0.001:
			var tn := tan2.normalized()
			var perp := Vector2(-tn.y, tn.x)
			return Vector3(perp.x, 0.0, perp.y).normalized()
	return Vector3.RIGHT


func _build_terrain_side_rings(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	base_ids: PackedInt32Array,
	outer_ids: PackedInt32Array,
	row_count: int,
	subdivisions: int,
	terrain_noise: FastNoiseLite,
	cancel_token: Dictionary = {}
) -> Array:
	var rings: Array = []
	rings.resize(subdivisions + 1)
	for ring_i in range(subdivisions + 1):
		var ring: Array = []
		ring.resize(row_count)
		for row_i in range(row_count):
			ring[row_i] = -1
		rings[ring_i] = ring

	for row_i in range(row_count):
		if (row_i % 64) == 0 and _is_generation_cancelled(cancel_token):
			return []
		var base_idx := int(base_ids[row_i])
		if base_idx >= 0 and base_idx < verts.size():
			var base_ring: Array = rings[0]
			base_ring[row_i] = base_idx
			rings[0] = base_ring

		var outer_idx := int(outer_ids[row_i])
		if base_idx < 0 or outer_idx < 0:
			continue
		if base_idx >= verts.size() or outer_idx >= verts.size():
			continue

		var base_point: Vector3 = verts[base_idx]
		var outer_point: Vector3 = verts[outer_idx]
		var points := _terrain_ring_stage_points(base_point, outer_point, subdivisions, terrain_noise)
		for ring_i in range(1, subdivisions + 1):
			var p := points[ring_i - 1]
			var ring_idx := outer_idx
			if ring_i < subdivisions:
				ring_idx = verts.size()
				verts.push_back(p)
				normals.push_back(Vector3.UP)
				uvs.push_back(Vector2(p.x, p.z) * uv_length_scale)
			else:
				verts[outer_idx] = p
				normals[outer_idx] = Vector3.UP
				uvs[outer_idx] = Vector2(p.x, p.z) * uv_length_scale
			var ring_ids: Array = rings[ring_i]
			ring_ids[row_i] = ring_idx
			rings[ring_i] = ring_ids
	return rings


func _terrain_ring_stage_points(base: Vector3, outer: Vector3, subdivisions: int, noise: FastNoiseLite) -> PackedVector3Array:
	var query: Dictionary = _stage_cache.query("rings", [base, outer, subdivisions, noise != null,
		terrain_noise_amplitude, terrain_noise_frequency, terrain_noise_seed, terrain_noise_falloff, terrain_cut_fill_mode])
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.ring_rows_reused += 1
		return cached.result
	last_stats.ring_rows_rebuilt += 1
	var points := PackedVector3Array()
	for ring_i in range(1, subdivisions + 1):
		var t := float(ring_i) / float(subdivisions)
		var p := base.lerp(outer, t)
		p.y = base.y + _terrain_noise_offset_y(p, t, noise)
		points.append(p)
	_stage_cache.store(query, points)
	return points


func _terrain_noise_offset_y(
	point: Vector3,
	ring_t: float,
	terrain_noise: FastNoiseLite
) -> float:
	var t := clampf(ring_t, 0.0, 1.0)
	if t <= 0.0001:
		return 0.0
	var total_offset := 0.0

	if terrain_noise != null and terrain_noise_amplitude > 0.0001:
		var falloff := maxf(0.0, terrain_noise_falloff)
		var weight := 1.0 if falloff <= 0.0001 else pow(t, falloff)
		total_offset += terrain_noise.get_noise_2d(point.x, point.z) * terrain_noise_amplitude * weight

	match terrain_cut_fill_mode:
		TERRAIN_CUT_FILL_CUT_ONLY:
			return minf(total_offset, 0.0)
		TERRAIN_CUT_FILL_FILL_ONLY:
			return maxf(total_offset, 0.0)
	return total_offset


func _build_terrain_noise() -> FastNoiseLite:
	if not terrain_noise_enabled:
		return null
	if terrain_noise_amplitude <= 0.0001:
		return null
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = terrain_noise_seed
	terrain_noise.frequency = terrain_noise_frequency
	return terrain_noise


func _build_road_tri_xz_cache(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array
) -> Array:
	var out: Array = []
	_append_surface_tri_xz_cache(out, verts, lane_indices)
	_append_surface_tri_xz_cache(out, verts, shoulder_indices)
	_append_surface_tri_xz_cache(out, verts, sidewalk_indices)
	# Extra row envelope is conservative; skip it when clearance is zero
	# to avoid over-rejecting terrain growth in free areas.
	if terrain_road_clearance > 0.0001:
		_append_path_row_road_envelope_tri_xz_cache(out, verts, path_rows)
	return out


func _append_surface_tri_xz_cache(out: Array, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	if indices.is_empty():
		return
	var tri_count := indices.size() - (indices.size() % 3)
	for i in range(0, tri_count, 3):
		var ia := int(indices[i])
		var ib := int(indices[i + 1])
		var ic := int(indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
			continue
		_append_tri_to_xz_cache(out, verts[ia], verts[ib], verts[ic])


func _append_path_row_road_envelope_tri_xz_cache(
	out: Array,
	verts: PackedVector3Array,
	path_rows: Array
) -> void:
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		if rows.size() < 2:
			continue
		for i in range(rows.size() - 1):
			var row0: Dictionary = rows[i]
			var row1: Dictionary = rows[i + 1]
			var e0: Array = row0.get("row_edges", [])
			var e1: Array = row1.get("row_edges", [])
			if e0.size() < 6 or e1.size() < 6:
				continue
			var l0 := int(e0[0])
			var r0 := int(e0[5])
			var l1 := int(e1[0])
			var r1 := int(e1[5])
			if l0 < 0 or r0 < 0 or l1 < 0 or r1 < 0:
				continue
			if l0 >= verts.size() or r0 >= verts.size() or l1 >= verts.size() or r1 >= verts.size():
				continue
			_append_tri_to_xz_cache(out, verts[l0], verts[r0], verts[l1])
			_append_tri_to_xz_cache(out, verts[l1], verts[r0], verts[r1])


func _append_tri_to_xz_cache(out: Array, a3: Vector3, b3: Vector3, c3: Vector3) -> void:
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var c := Vector2(c3.x, c3.z)
	var area2 := absf((b - a).cross(c - a))
	if area2 <= 0.0000001:
		return
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	var min_y := minf(a.y, minf(b.y, c.y))
	var max_y := maxf(a.y, maxf(b.y, c.y))
	out.push_back({
		"a": a,
		"b": b,
		"c": c,
		"min": Vector2(min_x, min_y),
		"max": Vector2(max_x, max_y),
	})


func _point_over_any_road_triangle_xz(point: Vector2, road_tris: Array, margin: float) -> bool:
	if road_tris.is_empty():
		return false
	for tri in road_tris:
		var min_v: Vector2 = tri["min"]
		var max_v: Vector2 = tri["max"]
		if point.x < min_v.x - margin or point.x > max_v.x + margin:
			continue
		if point.y < min_v.y - margin or point.y > max_v.y + margin:
			continue
		var a: Vector2 = tri["a"]
		var b: Vector2 = tri["b"]
		var c: Vector2 = tri["c"]
		var poly := PackedVector2Array([a, b, c])
		if Geometry2D.is_point_in_polygon(point, poly):
			return true
		if margin > 0.000001:
			var d0 := Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)
			if d0 <= margin:
				return true
			var d1 := Geometry2D.get_closest_point_to_segment(point, b, c).distance_to(point)
			if d1 <= margin:
				return true
			var d2 := Geometry2D.get_closest_point_to_segment(point, c, a).distance_to(point)
			if d2 <= margin:
				return true
	return false


func _segment_over_any_road_triangle_xz(a: Vector2, b: Vector2, road_tris: Array, margin: float = 0.0) -> bool:
	if road_tris.is_empty():
		return false
	var seg_min := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var seg_max := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var seg_mid := (a + b) * 0.5
	for tri in road_tris:
		var min_v: Vector2 = tri["min"]
		var max_v: Vector2 = tri["max"]
		if seg_max.x < min_v.x - margin or seg_min.x > max_v.x + margin:
			continue
		if seg_max.y < min_v.y - margin or seg_min.y > max_v.y + margin:
			continue
		var ta: Vector2 = tri["a"]
		var tb: Vector2 = tri["b"]
		var tc: Vector2 = tri["c"]
		var tri_poly := PackedVector2Array([ta, tb, tc])
		if Geometry2D.is_point_in_polygon(a, tri_poly):
			return true
		if Geometry2D.is_point_in_polygon(b, tri_poly):
			return true
		if Geometry2D.is_point_in_polygon(seg_mid, tri_poly):
			return true
		if _segments_intersect_2d_strict(a, b, ta, tb):
			return true
		if _segments_intersect_2d_strict(a, b, tb, tc):
			return true
		if _segments_intersect_2d_strict(a, b, tc, ta):
			return true
		if margin > 0.000001:
			if _segment_distance_2d(a, b, ta, tb) <= margin:
				return true
			if _segment_distance_2d(a, b, tb, tc) <= margin:
				return true
			if _segment_distance_2d(a, b, tc, ta) <= margin:
				return true
	return false


func _segment_distance_2d(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if hit != null:
		return 0.0
	var d0 := _distance_point_to_segment_2d(a0, b0, b1)
	var d1 := _distance_point_to_segment_2d(a1, b0, b1)
	var d2 := _distance_point_to_segment_2d(b0, a0, a1)
	var d3 := _distance_point_to_segment_2d(b1, a0, a1)
	return minf(minf(d0, d1), minf(d2, d3))


func _distance_point_to_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)


func _segments_intersect_2d_strict(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if hit == null:
		return false
	if typeof(hit) != TYPE_VECTOR2:
		return false
	var hp: Vector2 = hit
	if hp.distance_to(a0) <= 0.000001:
		return false
	if hp.distance_to(a1) <= 0.000001:
		return false
	if hp.distance_to(b0) <= 0.000001:
		return false
	if hp.distance_to(b1) <= 0.000001:
		return false
	return true


func _limit_terrain_growth_width_for_segment(
	verts: PackedVector3Array, base_point: Vector3, out_dir: Vector3, requested_width: float,
	prev_idx: int, curr_idx: int, outer_points: Array[Vector3], outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array, opposite_ids: PackedInt32Array, road_tris: Array
) -> float:
	var query := _growth_stage_query(verts, base_point, out_dir, requested_width,
		prev_idx, curr_idx, outer_points, base_ids, opposite_ids, road_tris)
	var cached: Dictionary = _stage_cache.lookup(query)
	if not cached.is_empty():
		last_stats.growth_queries_reused += 1
		return cached.result
	var width := _limit_terrain_growth_width_uncached(verts, base_point, out_dir, requested_width,
		prev_idx, curr_idx, outer_points, outer_ids, base_ids, opposite_ids, road_tris)
	_stage_cache.store(query, width)
	return width


func _growth_stage_query(
	verts: PackedVector3Array, base_point: Vector3, out_dir: Vector3, requested_width: float,
	prev_idx: int, curr_idx: int, outer_points: Array[Vector3],
	base_ids: PackedInt32Array, opposite_ids: PackedInt32Array, road_tris: Array
) -> Dictionary:
	if not _stage_cache.enabled or requested_width <= 0.0001 or prev_idx < 0 \
			or prev_idx >= outer_points.size() or curr_idx <= prev_idx:
		return {}
	var previous_outer: Vector3 = outer_points[prev_idx]
	var endpoint := base_point + out_dir * requested_width
	var low := Vector2(base_point.x, base_point.z).min(Vector2(endpoint.x, endpoint.z)).min(Vector2(previous_outer.x, previous_outer.z))
	var high := Vector2(base_point.x, base_point.z).max(Vector2(endpoint.x, endpoint.z)).max(Vector2(previous_outer.x, previous_outer.z))
	var bases: Array = []
	for address in [[base_ids, prev_idx], [base_ids, curr_idx], [opposite_ids, curr_idx]]:
		var ids: PackedInt32Array = address[0]
		var row: int = address[1]
		var id: int = ids[row] if row >= 0 and row < ids.size() else -1
		if id >= 0 and id < verts.size():
			var point := verts[id]
			bases.append(point)
			low = low.min(Vector2(point.x, point.z))
			high = high.max(Vector2(point.x, point.z))
		else:
			bases.append(null)
	# Every probe lies between the current base and requested endpoint; detection
	# scale is clamped to <= 1. Include the preceding accepted edge and clearance.
	var padding := maxf(0.0, terrain_road_clearance) + 1.0
	low -= Vector2.ONE * padding
	high += Vector2.ONE * padding
	var earlier_segments := PackedVector3Array()
	for ids: PackedInt32Array in [base_ids, opposite_ids]:
		for k in range(maxi(0, mini(curr_idx - 1, ids.size() - 1))):
			if k >= prev_idx - 1 and k <= curr_idx:
				continue
			var a := int(ids[k])
			var b := int(ids[k + 1])
			if a < 0 or b < 0 or a >= verts.size() or b >= verts.size():
				continue
			var p := verts[a]
			var q := verts[b]
			var segment_low := Vector2(p.x, p.z).min(Vector2(q.x, q.z))
			var segment_high := Vector2(p.x, p.z).max(Vector2(q.x, q.z))
			if segment_high.x < low.x or segment_low.x > high.x or segment_high.y < low.y or segment_low.y > high.y:
				continue
			earlier_segments.append(p)
			earlier_segments.append(q)
	var nearby_tris := PackedVector2Array()
	for tri in road_tris:
		var tri_low: Vector2 = tri.min
		var tri_high: Vector2 = tri.max
		if tri_high.x < low.x or tri_low.x > high.x or tri_high.y < low.y or tri_low.y > high.y:
			continue
		nearby_tris.append(tri.a)
		nearby_tris.append(tri.b)
		nearby_tris.append(tri.c)
	return _stage_cache.query("growth", [base_point, out_dir, requested_width, previous_outer,
		bases, earlier_segments, nearby_tris, terrain_growth_scan_step, terrain_detection_width_scale, terrain_road_clearance])


func _limit_terrain_growth_width_uncached(
	verts: PackedVector3Array,
	base_point: Vector3,
	out_dir: Vector3,
	requested_width: float,
	prev_idx: int,
	curr_idx: int,
	outer_points: Array[Vector3],
	outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	road_tris: Array
) -> float:
	last_stats["growth_width_queries"] += 1
	var width := maxf(0.0, requested_width)
	if width <= 0.0001:
		return 0.0
	if prev_idx < 0 or prev_idx >= outer_points.size():
		return width
	if curr_idx <= prev_idx:
		return width
	var prev_outer := outer_points[prev_idx]
	var scan_step := maxf(0.05, terrain_growth_scan_step)
	var probe_steps := maxi(2, mini(24, int(ceil(width / scan_step))))
	var step_len := width / float(probe_steps)
	var best := 0.0

	# Probe progressively and keep the furthest valid width.
	for probe_i in range(1, probe_steps + 1):
		var probe_w := step_len * float(probe_i)
		var probe_point := base_point + out_dir * probe_w
		if _is_terrain_growth_segment_valid(
			verts,
			prev_outer,
			probe_point,
			prev_idx,
			curr_idx,
			outer_points,
			outer_ids,
			base_ids,
			opposite_ids,
			road_tris
		):
			best = probe_w

	if best <= 0.0001:
		return 0.0
	if best >= width - 0.0001:
		return width

	var low := best
	var high := minf(width, best + step_len)
	while high < width:
		var high_point := base_point + out_dir * high
		if _is_terrain_growth_segment_valid(
			verts,
			prev_outer,
			high_point,
			prev_idx,
			curr_idx,
			outer_points,
			outer_ids,
			base_ids,
			opposite_ids,
			road_tris
		):
			low = high
			high = minf(width, high + step_len)
			continue
		break

	if low >= width - 0.0001:
		return width
	for _iter in range(8):
		var mid := (low + high) * 0.5
		var p_mid := base_point + out_dir * mid
		if _is_terrain_growth_segment_valid(
			verts,
			prev_outer,
			p_mid,
			prev_idx,
			curr_idx,
			outer_points,
			outer_ids,
			base_ids,
			opposite_ids,
			road_tris
		):
			low = mid
		else:
			high = mid
	return low if low > 0.0001 else 0.0


func _is_terrain_growth_segment_valid(
	verts: PackedVector3Array,
	seg_a: Vector3,
	seg_b: Vector3,
	prev_idx: int,
	curr_idx: int,
	outer_points: Array[Vector3],
	outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	road_tris: Array
) -> bool:
	# Keep detection on/inside the actual candidate extent.
	# Values > 1.0 can overreach and create false positives that stop terrain growth.
	var detection_width_scale := clampf(terrain_detection_width_scale, 0.1, 1.0)
	var base_prev_idx := int(base_ids[prev_idx]) if prev_idx >= 0 and prev_idx < base_ids.size() else -1
	var base_curr_idx := int(base_ids[curr_idx]) if curr_idx >= 0 and curr_idx < base_ids.size() else -1
	var detect_a := seg_a
	var detect_b := seg_b
	if base_prev_idx >= 0 and base_prev_idx < verts.size():
		var base_prev := verts[base_prev_idx]
		detect_a = base_prev + (seg_a - base_prev) * detection_width_scale
	if base_curr_idx >= 0 and base_curr_idx < verts.size():
		var base_curr := verts[base_curr_idx]
		detect_b = base_curr + (seg_b - base_curr) * detection_width_scale

	for k in range(curr_idx - 1):
		if k + 1 >= base_ids.size():
			break
		if k >= prev_idx - 1 and k <= curr_idx:
			continue
		var rb0 := int(base_ids[k])
		var rb1 := int(base_ids[k + 1])
		if rb0 < 0 or rb1 < 0:
			continue
		if rb0 >= verts.size() or rb1 >= verts.size():
			continue
		if _segments_intersect_xz(verts[rb0], verts[rb1], detect_a, detect_b):
			return false

	for k in range(curr_idx - 1):
		if k + 1 >= opposite_ids.size():
			break
		if k >= prev_idx - 1 and k <= curr_idx:
			continue
		var ro0 := int(opposite_ids[k])
		var ro1 := int(opposite_ids[k + 1])
		if ro0 < 0 or ro1 < 0:
			continue
		if ro0 >= verts.size() or ro1 >= verts.size():
			continue
		if _segments_intersect_xz(verts[ro0], verts[ro1], detect_a, detect_b):
			return false

	var seg_mid := (detect_a + detect_b) * 0.5
	var seg_q1 := detect_a.lerp(detect_b, 0.25)
	var seg_q3 := detect_a.lerp(detect_b, 0.75)
	var p_end := Vector2(detect_b.x, detect_b.z)
	var p_q1 := Vector2(seg_q1.x, seg_q1.z)
	var p_mid := Vector2(seg_mid.x, seg_mid.z)
	var p_q3 := Vector2(seg_q3.x, seg_q3.z)
	var p_a := Vector2(detect_a.x, detect_a.z)
	var road_clearance := maxf(0.0, terrain_road_clearance)
	if _point_over_any_road_triangle_xz(p_end, road_tris, road_clearance):
		return false
	if _point_over_any_road_triangle_xz(p_q1, road_tris, road_clearance):
		return false
	if _point_over_any_road_triangle_xz(p_mid, road_tris, road_clearance):
		return false
	if _point_over_any_road_triangle_xz(p_q3, road_tris, road_clearance):
		return false
	if _segment_over_any_road_triangle_xz(p_a, p_end, road_tris, road_clearance):
		return false
	if base_prev_idx >= 0 and base_curr_idx >= 0 and base_prev_idx < verts.size() and base_curr_idx < verts.size():
		if _terrain_quad_over_any_road_triangle_xz(
			verts[base_prev_idx],
			verts[base_curr_idx],
			detect_a,
			detect_b,
			road_tris,
			0.0
		):
			return false
	if _is_point_over_road_cross_xz(verts, detect_b, base_ids, opposite_ids, curr_idx):
		return false
	if _is_point_over_road_cross_xz(verts, seg_mid, base_ids, opposite_ids, curr_idx):
		return false

	return true


func _terrain_quad_over_any_road_triangle_xz(
	base_prev: Vector3,
	base_curr: Vector3,
	outer_prev: Vector3,
	outer_curr: Vector3,
	road_tris: Array,
	margin: float
) -> bool:
	if road_tris.is_empty():
		return false
	var prev_out := outer_prev - base_prev
	prev_out.y = 0.0
	var curr_out := outer_curr - base_curr
	curr_out.y = 0.0
	if prev_out.length() <= 0.0001 or curr_out.length() <= 0.0001:
		return false

	# Keep a tiny outward inset to avoid rejecting quads that only touch the road edge.
	# Clearance is handled by point/segment distance checks before this function.
	var edge_inset := 0.001
	var base_prev_p := Vector2(base_prev.x, base_prev.z) + Vector2(prev_out.x, prev_out.z).normalized() * edge_inset
	var base_curr_p := Vector2(base_curr.x, base_curr.z) + Vector2(curr_out.x, curr_out.z).normalized() * edge_inset
	var outer_curr_p := Vector2(outer_curr.x, outer_curr.z)
	var outer_prev_p := Vector2(outer_prev.x, outer_prev.z)
	var quad := PackedVector2Array([base_prev_p, base_curr_p, outer_curr_p, outer_prev_p])

	var q_min := Vector2(
		minf(base_prev_p.x, minf(base_curr_p.x, minf(outer_curr_p.x, outer_prev_p.x))),
		minf(base_prev_p.y, minf(base_curr_p.y, minf(outer_curr_p.y, outer_prev_p.y)))
	)
	var q_max := Vector2(
		maxf(base_prev_p.x, maxf(base_curr_p.x, maxf(outer_curr_p.x, outer_prev_p.x))),
		maxf(base_prev_p.y, maxf(base_curr_p.y, maxf(outer_curr_p.y, outer_prev_p.y)))
	)
	for tri in road_tris:
		var min_v: Vector2 = tri["min"]
		var max_v: Vector2 = tri["max"]
		if q_max.x < min_v.x - margin or q_min.x > max_v.x + margin:
			continue
		if q_max.y < min_v.y - margin or q_min.y > max_v.y + margin:
			continue
		var tri_poly := PackedVector2Array([tri["a"], tri["b"], tri["c"]])
		if _polygon_intersects_triangle_xz(quad, tri_poly):
			return true
	return false


func _polygon_intersects_triangle_xz(poly: PackedVector2Array, tri: PackedVector2Array) -> bool:
	for p in poly:
		if Geometry2D.is_point_in_polygon(p, tri):
			return true
	for t in tri:
		if Geometry2D.is_point_in_polygon(t, poly):
			return true
	for i in range(poly.size()):
		var a0 := poly[i]
		var a1 := poly[(i + 1) % poly.size()]
		for j in range(tri.size()):
			var b0 := tri[j]
			var b1 := tri[(j + 1) % tri.size()]
			var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
			if hit != null:
				return true
	return false


func _is_point_over_road_cross_xz(
	verts: PackedVector3Array,
	point: Vector3,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	row_idx: int
) -> bool:
	if row_idx < 0 or row_idx >= base_ids.size() or row_idx >= opposite_ids.size():
		return false
	var b := int(base_ids[row_idx])
	var o := int(opposite_ids[row_idx])
	if b < 0 or o < 0:
		return false
	if b >= verts.size() or o >= verts.size():
		return false

	var base := verts[b]
	var opp := verts[o]
	var across := Vector2(opp.x - base.x, opp.z - base.z)
	var across_len := across.length()
	if across_len <= 0.0001:
		return false
	var across_n := across / across_len
	var rel := Vector2(point.x - base.x, point.z - base.z)
	var proj := rel.dot(across_n)
	# proj > 0 means candidate moved towards/over road interior.
	return proj > 0.01


func _segments_intersect_xz(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> bool:
	var p0 := Vector2(a0.x, a0.z)
	var p1 := Vector2(a1.x, a1.z)
	var q0 := Vector2(b0.x, b0.z)
	var q1 := Vector2(b1.x, b1.z)
	var hit = Geometry2D.segment_intersects_segment(p0, p1, q0, q1)
	if hit == null:
		return false
	if typeof(hit) != TYPE_VECTOR2:
		return false
	var hp: Vector2 = hit
	if hp.distance_to(p0) <= 0.0001:
		return false
	if hp.distance_to(p1) <= 0.0001:
		return false
	if hp.distance_to(q0) <= 0.0001:
		return false
	if hp.distance_to(q1) <= 0.0001:
		return false
	return true


# Typed entry points into the generation coordinator.
func _debug_log(message: String) -> void:
	_road._debug_log(message)


func _profile_start() -> int:
	return _road._profile_start()


func _profile_log(label: String, start_usec: int, extra: String = "") -> void:
	_road._profile_log(label, start_usec, extra)


func _is_generation_cancelled(cancel_token: Dictionary) -> bool:
	return _road._is_generation_cancelled(cancel_token)


func _append_quad_indices(indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	# A worker must not read a newer Inspector value midway through a strip;
	# otherwise the cached key and the stored triangle winding could disagree.
	if invert_faces:
		indices.append_array(PackedInt32Array([a, b, c, c, b, d]))
	else:
		indices.append_array(PackedInt32Array([a, c, b, c, d, b]))


func _append_terrain_triangle_indices(
	terrain_indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int
) -> void:
	_road._append_oriented_triangle(terrain_indices, verts, a, b, c, Vector3.DOWN if invert_faces else Vector3.UP)


func _append_terrain_quad_indices(
	terrain_indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	d: int
) -> void:
	_road._append_oriented_quad(terrain_indices, verts, a, b, c, d, Vector3.DOWN if invert_faces else Vector3.UP)


func _sample_terrain_influence_centerline_base_height(strip: Dictionary, point: Vector2) -> float:
	return _road._sample_terrain_influence_centerline_base_height(strip, point)


func _closest_point_param_on_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	return _road._closest_point_param_on_segment_2d(point, a, b)
