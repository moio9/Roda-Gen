@tool
extends RefCounted
## Samples road paths into geometry rows consumed by junction and terrain builders.

var _road: Node
var _source_cache := preload("./road_source_cache.gd").new()
var last_stats: Dictionary = {}
const MAX_ASSEMBLY_ROWS := 16384
const MAX_ASSEMBLY_BYTES := 32 * 1024 * 1024
var assembly_cache_enabled := true # Test override; also gated by source-cache eligibility.
var _assembly_bytes := 0
var _assembly_stats: Dictionary = {}
var sample_step := 0.5
var y_offset := 0.0
var uv_length_scale := 0.2
var markings_enabled := false
var _terrain_influence_strips: Array = []
var _terrain_influence_loops: Array = []


func configure(source: Node) -> void:
	_road = source
	sample_step = source.get("sample_step")
	y_offset = source.get("y_offset")
	uv_length_scale = source.get("uv_length_scale")
	markings_enabled = source.get("markings_enabled")
	_terrain_influence_strips = source.get("_terrain_influence_strips")
	_terrain_influence_loops = source.get("_terrain_influence_loops")


func sample_paths(paths: Array[Path3D], inv_global: Transform3D) -> Dictionary:
	var source_start := Time.get_ticks_usec()
	var sampling_usec := 0
	var assembly_usec := 0
	_source_cache.begin_build(_road)
	_assembly_bytes = 0
	_assembly_stats = {"paths_reused": 0, "paths_rebuilt": 0, "rows_reused": 0,
		"rows_rebuilt": 0, "payload_bytes": 0, "bypassed": 0}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var lane_indices := PackedInt32Array()
	var shoulder_indices := PackedInt32Array()
	var sidewalk_indices := PackedInt32Array()
	var terrain_indices := PackedInt32Array()
	var wall_indices := PackedInt32Array()
	var sockets: Array[Dictionary] = []
	var socket_keys: Dictionary = {}
	var path_rows: Array = []
	path_rows.resize(paths.size())
	var endpoint_positions_by_path: Array = _collect_path_endpoints(paths, inv_global)
	var path_weld_snap: Array = []
	path_weld_snap.resize(paths.size())
	var path_weld_allow_midpath: Array = []
	path_weld_allow_midpath.resize(paths.size())
	var path_weld_strip_enabled: Array = []
	path_weld_strip_enabled.resize(paths.size())
	var path_weld_strip_length: Array = []
	path_weld_strip_length.resize(paths.size())

	var profile_path_rows_start := _profile_start()
	for path_idx in range(paths.size()):
		var path := paths[path_idx]
		var rows_info: Array[Dictionary] = []
		var weld_snap := _resolve_path_weld_endpoint_snap_distance(path)
		var weld_allow_midpath := _resolve_path_weld_allow_endpoint_to_midpath(path)
		var weld_strip_enabled := _resolve_path_weld_strip_shoulder_sidewalk(path)
		var weld_strip_length := _resolve_path_weld_intersection_strip_length(path)
		var path_has_adaptive_override: bool = _path_has_adaptive_sampling_overrides(path)
		var path_adaptive_enabled: bool = _resolve_path_adaptive_sampling_enabled(path)
		var path_adaptive_advanced: bool = _resolve_path_adaptive_sampling_advanced(path)
		var path_adaptive_step_scale: float = _resolve_path_adaptive_sampling_step_scale(path)
		var path_adaptive_radius_scale: float = _resolve_path_adaptive_sampling_radius_scale(path)
		var path_adaptive_offset: float = _resolve_path_adaptive_sampling_offset(path)
		var terrain_influence_only := _path_is_terrain_influence_only(path)
		path_weld_snap[path_idx] = weld_snap
		path_weld_allow_midpath[path_idx] = weld_allow_midpath
		path_weld_strip_enabled[path_idx] = weld_strip_enabled
		path_weld_strip_length[path_idx] = weld_strip_length

		if path == null or path.curve == null:
			path_rows[path_idx] = rows_info
			continue

		var curve := path.curve
		if curve.point_count < 2:
			path_rows[path_idx] = rows_info
			continue

		var generation_step := sample_step
		if path.has_method("get_road_generation_sample_step"):
			generation_step = maxf(0.01, float(path.call("get_road_generation_sample_step", sample_step)))
		curve.bake_interval = max(generation_step, 0.01)
		var length := curve.get_baked_length()
		if length <= 0.0:
			path_rows[path_idx] = rows_info
			continue

		var path_to_mesh := inv_global * path.global_transform
		var distances := _build_open_distances_with_step(length, generation_step)
		if not path_adaptive_enabled:
			_debug_log(
				"adaptive path=%s enabled=false override=%s"
				% [path_idx, path_has_adaptive_override]
			)
		if path_adaptive_enabled:
			var local_step: float = _compute_adaptive_local_step(path_adaptive_step_scale, generation_step)
			var local_radius: float = _compute_adaptive_local_radius(
				local_step,
				path_adaptive_radius_scale
			)
			var anchors: PackedFloat32Array = _collect_adaptive_anchor_offsets(
				path_idx,
				curve,
				path_to_mesh,
				endpoint_positions_by_path,
				weld_snap * 1.5
			)
			if anchors.is_empty():
				# Keep adaptive responsive even when no intersection anchors are detected.
				distances = _build_open_distances_with_step(length, local_step)
			else:
				anchors = _apply_adaptive_anchor_offset(
					anchors,
					length,
					path_adaptive_advanced,
					path_adaptive_offset
				)
				distances = _build_open_distances_with_anchors(length, anchors, local_step, local_radius, generation_step)
			_debug_log(
				"adaptive path=%s enabled=%s override=%s advanced=%s anchors=%s step=%.3f radius=%.3f rows=%s"
				% [path_idx, path_adaptive_enabled, path_has_adaptive_override, path_adaptive_advanced, anchors.size(), local_step, local_radius, distances.size()]
			)
		if distances.size() < 2:
			path_rows[path_idx] = rows_info
			continue
		if terrain_influence_only:
			var strip := _build_terrain_influence_strip(path, curve, path_to_mesh, distances)
			if not strip.is_empty():
				_terrain_influence_strips.push_back(strip)
				var loop: PackedVector2Array = strip.get("loop", PackedVector2Array())
				var clip_base_terrain_by_loop := bool(strip.get("clip_base_terrain_by_loop", strip.get("generate_surface", true)))
				if clip_base_terrain_by_loop and loop.size() >= 3:
					_terrain_influence_loops.push_back(loop)
			path_rows[path_idx] = rows_info
			continue

		var stage_start := Time.get_ticks_usec()
		var source := _sample_source_blocks(path, curve, path_to_mesh, length, distances)
		sampling_usec += Time.get_ticks_usec() - stage_start
		stage_start = Time.get_ticks_usec()
		var vertex_base := verts.size()
		verts.append_array(source.verts)
		normals.append_array(source.normals)
		uvs.append_array(source.uvs)
		var assembled := _assemble_path(path, source, distances, path_idx, vertex_base,
			weld_snap, weld_allow_midpath, weld_strip_enabled, weld_strip_length)
		lane_indices.append_array(assembled.lane)
		shoulder_indices.append_array(assembled.shoulder)
		sidewalk_indices.append_array(assembled.sidewalk)
		rows_info = assembled.rows
		path_rows[path_idx] = rows_info

		if rows_info.size() >= 2:
			_add_socket_unique(sockets, socket_keys, rows_info[0], true)
			_add_socket_unique(sockets, socket_keys, rows_info[rows_info.size() - 1], true)
		assembly_usec += Time.get_ticks_usec() - stage_start

	var profile_row_count := 0
	for rows_raw in path_rows:
		var rows_for_profile: Array = rows_raw
		profile_row_count += rows_for_profile.size()
	_profile_log("main build path rows", profile_path_rows_start, "rows=%s verts=%s lane=%s shoulder=%s sidewalk=%s influence_strips=%s" % [profile_row_count, verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), _terrain_influence_strips.size()])
	_source_cache.end_build()
	last_stats = _source_cache.last_stats.duplicate()
	last_stats["source_ms"] = float(Time.get_ticks_usec() - source_start) / 1000.0
	last_stats["sampling_ms"] = float(sampling_usec) / 1000.0
	last_stats["assembly_ms"] = float(assembly_usec) / 1000.0
	_assembly_stats.payload_bytes = _assembly_bytes
	last_stats["assembly"] = _assembly_stats.duplicate()
	return {
		"verts": verts,
		"normals": normals,
		"uvs": uvs,
		"lane_indices": lane_indices,
		"shoulder_indices": shoulder_indices,
		"sidewalk_indices": sidewalk_indices,
		"terrain_indices": terrain_indices,
		"wall_indices": wall_indices,
		"sockets": sockets,
		"socket_keys": socket_keys,
		"path_rows": path_rows,
		"path_weld_snap": path_weld_snap,
		"path_weld_allow_midpath": path_weld_allow_midpath,
		"path_weld_strip_enabled": path_weld_strip_enabled,
		"path_weld_strip_length": path_weld_strip_length,
	}


func _assemble_path(path: Path3D, source: Dictionary, distances: PackedFloat32Array, path_idx: int,
		vertex_base: int, weld_snap: float, weld_allow_midpath: bool, weld_strip_enabled: bool,
		weld_strip_length: float) -> Dictionary:
	# Only the current immutable source entry may certify assembly reuse. A
	# changed source replaces this entry, discarding its previous assembly.
	var entry: Dictionary = _source_cache.current_path(path)
	var key := var_to_bytes([path_idx, vertex_base, weld_snap, weld_allow_midpath,
		weld_strip_enabled, weld_strip_length, _road.invert_faces, markings_enabled])
	var eligible := assembly_cache_enabled and not entry.is_empty() and distances.size() <= MAX_ASSEMBLY_ROWS
	if eligible and entry.get("assembly_key", PackedByteArray()) == key \
			and _assembly_bytes + int(entry.get("assembly_bytes", 0)) <= MAX_ASSEMBLY_BYTES:
		_assembly_bytes += entry.assembly_bytes
		_assembly_stats.paths_reused += 1
		_assembly_stats.rows_reused += distances.size()
		return entry.assembly.duplicate(true)
	entry.erase("assembly")
	entry.erase("assembly_key")
	entry.erase("assembly_bytes")
	var result := _assemble_path_native(source, distances, path_idx, vertex_base,
		weld_snap, weld_allow_midpath, weld_strip_enabled, weld_strip_length)
	_assembly_stats.paths_rebuilt += 1
	_assembly_stats.rows_rebuilt += distances.size()
	if eligible:
		var bytes := var_to_bytes(result).size() + key.size()
		if _assembly_bytes + bytes <= MAX_ASSEMBLY_BYTES:
			entry.assembly = result.duplicate(true)
			entry.assembly_key = key
			entry.assembly_bytes = bytes
			_assembly_bytes += bytes
			return result
	_assembly_stats.bypassed += 1
	return result


func _assemble_path_native(source: Dictionary, distances: PackedFloat32Array, path_idx: int,
		vertex_base: int, weld_snap: float, weld_allow_midpath: bool, weld_strip_enabled: bool,
		weld_strip_length: float) -> Dictionary:
	var rows_info: Array[Dictionary] = []
	var lane_indices := PackedInt32Array()
	var shoulder_indices := PackedInt32Array()
	var sidewalk_indices := PackedInt32Array()
	# Source snapshots remain immutable. Only these nested arrays/dictionaries
	# escape into mutable junction/marking metadata; packed streams append by value.
	var row_edges: Array = source.row_edges.duplicate(true)
	var row_centers: Array[Vector3] = source.row_centers
	var row_widths: PackedFloat32Array = source.row_widths
	var row_lane_widths: PackedFloat32Array = source.row_lane_widths
	var row_lane_extents: PackedVector2Array = source.row_lane_extents
	var row_marking_layouts: Array[Dictionary] = source.row_marking_layouts
	var row_shoulder_left_widths: PackedFloat32Array = source.row_shoulder_left_widths
	var row_shoulder_right_widths: PackedFloat32Array = source.row_shoulder_right_widths
	var row_sidewalk_left_widths: PackedFloat32Array = source.row_sidewalk_left_widths
	var row_sidewalk_right_widths: PackedFloat32Array = source.row_sidewalk_right_widths
	var row_terrain_left_widths: PackedFloat32Array = source.row_terrain_left_widths
	var row_terrain_right_widths: PackedFloat32Array = source.row_terrain_right_widths
	var row_outer_wall_heights: PackedFloat32Array = source.row_outer_wall_heights
	for row: Array in row_edges:
		for edge in range(row.size()):
			row[edge] += vertex_base

	for i in range(row_edges.size() - 1):
		var row0: Array = row_edges[i]
		var row1: Array = row_edges[i + 1]
		var lane_w_avg := (float(row_lane_widths[i]) + float(row_lane_widths[i + 1])) * 0.5
		var shoulder_l_avg := (float(row_shoulder_left_widths[i]) + float(row_shoulder_left_widths[i + 1])) * 0.5
		var shoulder_r_avg := (float(row_shoulder_right_widths[i]) + float(row_shoulder_right_widths[i + 1])) * 0.5
		var sidewalk_l_avg := (float(row_sidewalk_left_widths[i]) + float(row_sidewalk_left_widths[i + 1])) * 0.5
		var sidewalk_r_avg := (float(row_sidewalk_right_widths[i]) + float(row_sidewalk_right_widths[i + 1])) * 0.5

		if sidewalk_l_avg > 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[0]), int(row0[1]), int(row1[0]), int(row1[1]))
		if shoulder_l_avg > 0.0001:
			_append_quad_indices(shoulder_indices, int(row0[1]), int(row0[2]), int(row1[1]), int(row1[2]))
		if lane_w_avg > 0.0001:
			_append_quad_indices(lane_indices, int(row0[2]), int(row0[3]), int(row1[2]), int(row1[3]))
		if shoulder_r_avg > 0.0001:
			_append_quad_indices(shoulder_indices, int(row0[3]), int(row0[4]), int(row1[3]), int(row1[4]))
		if sidewalk_r_avg > 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[4]), int(row0[5]), int(row1[4]), int(row1[5]))

		# If sidewalk exists but shoulder is zero, close the curb gap to avoid see-through.
		if sidewalk_l_avg > 0.0001 and shoulder_l_avg <= 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[1]), int(row0[2]), int(row1[1]), int(row1[2]))
		if sidewalk_r_avg > 0.0001 and shoulder_r_avg <= 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[3]), int(row0[4]), int(row1[3]), int(row1[4]))

	for i in range(row_edges.size()):
		var out_dir := _compute_row_out_dir(row_centers, i)
		var row: Array = row_edges[i]
		rows_info.push_back({
			"path_id": path_idx,
			"row_idx": i,
			"distance": distances[i],
			"lane_extents": row_lane_extents[i],
			"position": row_centers[i],
			"out_dir": out_dir,
			"row_a": int(row[0]),
			"row_b": int(row[5]),
				"width": row_widths[i],
				"weld_snap_distance": weld_snap,
				"weld_allow_endpoint_to_midpath": weld_allow_midpath,
				"weld_strip_enabled": weld_strip_enabled,
				"weld_strip_length": weld_strip_length,
				"terrain_left_width": row_terrain_left_widths[i],
				"terrain_right_width": row_terrain_right_widths[i],
				"outer_wall_height": row_outer_wall_heights[i],
				"row_edges": row,
			})
		if markings_enabled:
			rows_info[rows_info.size() - 1]["marking_layout"] = row_marking_layouts[i].duplicate(true)

	return {"rows": rows_info, "lane": lane_indices, "shoulder": shoulder_indices, "sidewalk": sidewalk_indices}



func _build_row_block(path: Path3D, curve: Curve3D, path_to_mesh: Transform3D, length: float, distances: PackedFloat32Array) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var row_edges: Array = []
	var row_centers: Array[Vector3] = []
	var row_widths := PackedFloat32Array()
	var row_lane_widths := PackedFloat32Array()
	var row_lane_extents := PackedVector2Array()
	var row_marking_layouts: Array[Dictionary] = []
	var row_shoulder_left_widths := PackedFloat32Array()
	var row_shoulder_right_widths := PackedFloat32Array()
	var row_sidewalk_left_widths := PackedFloat32Array()
	var row_sidewalk_right_widths := PackedFloat32Array()
	var row_terrain_left_widths := PackedFloat32Array()
	var row_terrain_right_widths := PackedFloat32Array()
	var row_outer_wall_heights := PackedFloat32Array()

	for i in range(distances.size()):
		var dist := distances[i]
		var p_local := curve.sample_baked(dist, true)
		var p_mesh := path_to_mesh * p_local
		var lane_extents := _resolve_path_lane_extents(path, dist, length)
		var lane_left_width := lane_extents.x
		var lane_right_width := lane_extents.y
		var lane_width := maxf(0.1, lane_left_width + lane_right_width)
		var shoulder_left := _resolve_path_shoulder_left(path, dist, length)
		var shoulder_right := _resolve_path_shoulder_right(path, dist, length)
		var sidewalk_left := _resolve_path_sidewalk_left(path, dist, length)
		var sidewalk_right := _resolve_path_sidewalk_right(path, dist, length)
		var local_terrain_widths := _resolve_path_terrain_widths(path, dist, length)
		var local_terrain_left := local_terrain_widths.x
		var local_terrain_right := local_terrain_widths.y
		var local_sidewalk_height := _resolve_path_sidewalk_height(path, dist, length)
		var local_outer_wall_height := _resolve_path_outer_wall_height(path, dist, length)
		var total_width := lane_width + shoulder_left + shoulder_right + sidewalk_left + sidewalk_right
		var prev_dist: float = max(0.0, dist - 0.1)
		var next_dist: float = min(length, dist + 0.1)
		if is_equal_approx(next_dist, prev_dist):
			if next_dist < length:
				next_dist = min(length, next_dist + 0.1)
			elif prev_dist > 0.0:
				prev_dist = max(0.0, prev_dist - 0.1)
		var p_prev_mesh := path_to_mesh * curve.sample_baked(prev_dist, true)
		var p_next_mesh := path_to_mesh * curve.sample_baked(next_dist, true)
		var frame: Dictionary = _road._resolve_road_frame(curve, path_to_mesh, dist, length,
			p_mesh, p_prev_mesh, p_next_mesh, path)
		var right: Vector3 = frame.get("right", Vector3.RIGHT)
		var up_mesh: Vector3 = frame.get("up", Vector3.UP)

		var left_lane := p_mesh - right * lane_left_width
		var right_lane := p_mesh + right * lane_right_width
		var left_shoulder := p_mesh - right * (lane_left_width + shoulder_left)
		var right_shoulder := p_mesh + right * (lane_right_width + shoulder_right)
		var left_outer := p_mesh - right * (lane_left_width + shoulder_left + sidewalk_left)
		var right_outer := p_mesh + right * (lane_right_width + shoulder_right + sidewalk_right)
		var left_raise := local_sidewalk_height if sidewalk_left > 0.0001 else 0.0
		var right_raise := local_sidewalk_height if sidewalk_right > 0.0001 else 0.0
		left_shoulder.y += left_raise
		left_outer.y += left_raise
		right_shoulder.y += right_raise
		right_outer.y += right_raise

		var side_total := shoulder_left + shoulder_right + sidewalk_left + sidewalk_right
		var total_for_uv := maxf(0.001, lane_width + side_total)
		var u0 := 0.0
		var u1 := sidewalk_left / total_for_uv
		var u2 := (sidewalk_left + shoulder_left) / total_for_uv
		var u3 := (sidewalk_left + shoulder_left + lane_width) / total_for_uv
		var u4 := (sidewalk_left + shoulder_left + lane_width + shoulder_right) / total_for_uv
		var u5 := 1.0
		var v := dist * uv_length_scale

		var edge_points := [
			left_outer,
			left_shoulder,
			left_lane,
			right_lane,
			right_shoulder,
			right_outer,
		]
		var edge_us := [u0, u1, u2, u3, u4, u5]
		var row: Array[int] = []
		row.resize(6)
		for edge_idx in range(6):
			var p_edge: Vector3 = edge_points[edge_idx]
			p_edge.y += y_offset
			var vi := verts.size()
			verts.push_back(p_edge)
			normals.push_back(up_mesh)
			uvs.push_back(Vector2(float(edge_us[edge_idx]), v))
			row[edge_idx] = vi

		row_edges.push_back(row)
		row_centers.push_back(Vector3(p_mesh.x, p_mesh.y + y_offset, p_mesh.z))
		row_widths.push_back(maxf(0.1, total_width))
		row_lane_widths.push_back(maxf(0.1, lane_width))
		row_lane_extents.push_back(lane_extents)
		if markings_enabled:
			var marking_layout: Dictionary = {"enabled": false}
			if path.has_method("get_lane_layout_at_offset"):
				marking_layout = path.get_lane_layout_at_offset(dist)
			row_marking_layouts.append(marking_layout)
		row_shoulder_left_widths.push_back(maxf(0.0, shoulder_left))
		row_shoulder_right_widths.push_back(maxf(0.0, shoulder_right))
		row_sidewalk_left_widths.push_back(maxf(0.0, sidewalk_left))
		row_sidewalk_right_widths.push_back(maxf(0.0, sidewalk_right))
		row_terrain_left_widths.push_back(maxf(0.0, local_terrain_left))
		row_terrain_right_widths.push_back(maxf(0.0, local_terrain_right))
		row_outer_wall_heights.push_back(maxf(0.0, local_outer_wall_height))

	return {
		"verts": verts,
		"normals": normals,
		"uvs": uvs,
		"row_edges": row_edges,
		"row_centers": row_centers,
		"row_widths": row_widths,
		"row_lane_widths": row_lane_widths,
		"row_lane_extents": row_lane_extents,
		"row_marking_layouts": row_marking_layouts,
		"row_shoulder_left_widths": row_shoulder_left_widths,
		"row_shoulder_right_widths": row_shoulder_right_widths,
		"row_sidewalk_left_widths": row_sidewalk_left_widths,
		"row_sidewalk_right_widths": row_sidewalk_right_widths,
		"row_terrain_left_widths": row_terrain_left_widths,
		"row_terrain_right_widths": row_terrain_right_widths,
		"row_outer_wall_heights": row_outer_wall_heights,
	}


func clear_cache() -> void:
	_source_cache.clear()
	_assembly_bytes = 0
	_assembly_stats.clear()
	last_stats = {}


func _sample_source_blocks(path: Path3D, curve: Curve3D, transform: Transform3D, length: float, distances: PackedFloat32Array) -> Dictionary:
	var cacheable := _source_cache.can_cache(path)
	if not cacheable:
		_source_cache.last_stats.uncacheable_paths += 1
		_source_cache.last_stats.blocks_rebuilt += ceili(float(distances.size()) / _source_cache.BLOCK_ROWS)
		_source_cache.last_stats.rows_rebuilt += distances.size()
		return _build_row_block(path, curve, transform, length, distances)
	var key := _source_cache.path_key(path, distances, transform) if cacheable else PackedByteArray()
	var previous := _source_cache.previous_path(path) if cacheable else {}
	if cacheable and previous.get("key", PackedByteArray()) == key:
		_source_cache.retain_path(path, previous)
		_source_cache.last_stats.paths_reused += 1
		_source_cache.last_stats.blocks_reused += previous.blocks.size()
		_source_cache.last_stats.rows_reused += distances.size()
		return previous.rows
	var blocks: Array = []
	var old_blocks: Array = previous.get("blocks", [])
	var result: Dictionary = {}
	for begin in range(0, distances.size(), _source_cache.BLOCK_ROWS):
		var block_distances := distances.slice(begin, mini(begin + _source_cache.BLOCK_ROWS, distances.size()))
		var block_key := _source_cache.block_key(path, block_distances, transform) if cacheable else PackedByteArray()
		var block_index := blocks.size()
		var block: Dictionary
		if cacheable and block_index < old_blocks.size() and old_blocks[block_index].key == block_key:
			block = old_blocks[block_index]
			_source_cache.last_stats.blocks_reused += 1
			_source_cache.last_stats.rows_reused += block_distances.size()
		else:
			block = {"key": block_key, "rows": _build_row_block(path, curve, transform, length, block_distances)}
			_source_cache.last_stats.blocks_rebuilt += 1
			_source_cache.last_stats.rows_rebuilt += block_distances.size()
		blocks.append(block)
		_append_source_block(result, block.rows)
	if cacheable:
		_source_cache.retain_path(path, {"key": key, "blocks": blocks, "rows": result})
	# Assembly copies nested metadata at its mutation boundary.
	return result


func _append_source_block(target: Dictionary, block: Dictionary) -> void:
	if target.is_empty():
		target.merge(block.duplicate(true))
		return
	var base: int = target.verts.size()
	for field in block:
		if field == "row_edges":
			for source_row: Array in block.row_edges:
				var row: Array[int] = []
				for index: int in source_row:
					row.append(index + base)
				target.row_edges.append(row)
		else:
			var values: Variant = target[field]
			values.append_array(block[field].duplicate(true) if block[field] is Array else block[field])
			target[field] = values


func _debug_log(message: String) -> void:
	_road._debug_log(message)


func _profile_start() -> int:
	return _road._profile_start()


func _profile_log(label: String, start_usec: int, extra: String = "") -> void:
	_road._profile_log(label, start_usec, extra)


func _append_quad_indices(indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	_road._append_quad_indices(indices, a, b, c, d)


func _compute_row_out_dir(row_centers: Array[Vector3], idx: int) -> Vector3:
	return _road._compute_row_out_dir(row_centers, idx)


func _add_socket_unique(sockets: Array[Dictionary], keys: Dictionary, row: Dictionary, is_endpoint: bool) -> void:
	_road._add_socket_unique(sockets, keys, row, is_endpoint)


func _build_open_distances_with_step(length: float, local_step: float) -> PackedFloat32Array:
	return _road._build_open_distances_with_step(length, local_step)


func _compute_adaptive_local_step(path_adaptive_step_scale: float, generation_step := -1.0) -> float:
	return _road._compute_adaptive_local_step(path_adaptive_step_scale, generation_step)


func _compute_adaptive_local_radius(
	local_step: float,
	path_adaptive_radius_scale: float
) -> float:
	return _road._compute_adaptive_local_radius(local_step, path_adaptive_radius_scale)


func _apply_adaptive_anchor_offset(
	anchors: PackedFloat32Array,
	length: float,
	path_adaptive_advanced: bool,
	path_adaptive_offset: float
) -> PackedFloat32Array:
	return _road._apply_adaptive_anchor_offset(anchors, length, path_adaptive_advanced, path_adaptive_offset)


func _build_open_distances_with_anchors(
	length: float,
	anchors: PackedFloat32Array,
	local_step: float,
	local_radius: float,
	base_step := -1.0
) -> PackedFloat32Array:
	return _road._build_open_distances_with_anchors(length, anchors, local_step, local_radius, base_step)


func _collect_path_endpoints(paths: Array[Path3D], inv_global: Transform3D) -> Array:
	return _road._collect_path_endpoints(paths, inv_global)


func _collect_adaptive_anchor_offsets(
	path_idx: int,
	curve: Curve3D,
	path_to_mesh: Transform3D,
	endpoint_positions_by_path: Array,
	max_snap_distance: float
) -> PackedFloat32Array:
	return _road._collect_adaptive_anchor_offsets(path_idx, curve, path_to_mesh, endpoint_positions_by_path, max_snap_distance)


func _resolve_path_weld_endpoint_snap_distance(path: Path3D) -> float:
	return _road._resolve_path_weld_endpoint_snap_distance(path)


func _resolve_path_weld_allow_endpoint_to_midpath(path: Path3D) -> bool:
	return _road._resolve_path_weld_allow_endpoint_to_midpath(path)


func _resolve_path_weld_strip_shoulder_sidewalk(path: Path3D) -> bool:
	return _road._resolve_path_weld_strip_shoulder_sidewalk(path)


func _resolve_path_weld_intersection_strip_length(path: Path3D) -> float:
	return _road._resolve_path_weld_intersection_strip_length(path)


func _path_has_adaptive_sampling_overrides(path: Path3D) -> bool:
	return _road._path_has_adaptive_sampling_overrides(path)


func _resolve_path_adaptive_sampling_enabled(path: Path3D) -> bool:
	return _road._resolve_path_adaptive_sampling_enabled(path)


func _resolve_path_adaptive_sampling_advanced(path: Path3D) -> bool:
	return _road._resolve_path_adaptive_sampling_advanced(path)


func _resolve_path_adaptive_sampling_step_scale(path: Path3D) -> float:
	return _road._resolve_path_adaptive_sampling_step_scale(path)


func _resolve_path_adaptive_sampling_radius_scale(path: Path3D) -> float:
	return _road._resolve_path_adaptive_sampling_radius_scale(path)


func _resolve_path_adaptive_sampling_offset(path: Path3D) -> float:
	return _road._resolve_path_adaptive_sampling_offset(path)


func _resolve_path_lane_extents(path: Path3D, dist: float, length: float) -> Vector2:
	return _road._resolve_path_lane_extents(path, dist, length)


func _resolve_path_shoulder_left(path: Path3D, dist: float, length: float) -> float:
	return _road._resolve_path_shoulder_left(path, dist, length)


func _resolve_path_shoulder_right(path: Path3D, dist: float, length: float) -> float:
	return _road._resolve_path_shoulder_right(path, dist, length)


func _resolve_path_sidewalk_left(path: Path3D, dist: float, length: float) -> float:
	return _road._resolve_path_sidewalk_left(path, dist, length)


func _resolve_path_sidewalk_right(path: Path3D, dist: float, length: float) -> float:
	return _road._resolve_path_sidewalk_right(path, dist, length)


func _resolve_path_terrain_widths(path: Path3D, dist: float, length: float) -> Vector2:
	return _road._resolve_path_terrain_widths(path, dist, length)


func _resolve_path_sidewalk_height(path: Path3D, dist: float, length: float) -> float:
	return _road._resolve_path_sidewalk_height(path, dist, length)


func _resolve_path_outer_wall_height(path: Path3D, dist: float, length: float) -> float:
	return _road._resolve_path_outer_wall_height(path, dist, length)


func _path_is_terrain_influence_only(path: Path3D) -> bool:
	return _road._path_is_terrain_influence_only(path)


func _build_terrain_influence_strip(
	path: Path3D,
	curve: Curve3D,
	path_to_mesh: Transform3D,
	distances: PackedFloat32Array
) -> Dictionary:
	return _road._build_terrain_influence_strip(path, curve, path_to_mesh, distances)


func _resolve_road_frame(
	curve: Curve3D,
	path_to_mesh: Transform3D,
	dist: float,
	length: float,
	p_mesh: Vector3,
	p_prev_mesh: Vector3,
	p_next_mesh: Vector3
) -> Dictionary:
	return _road._resolve_road_frame(curve, path_to_mesh, dist, length, p_mesh, p_prev_mesh, p_next_mesh)
