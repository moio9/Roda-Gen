@tool
extends RefCounted
## Socket clustering, junction welding and intersection edge trimming.
## Configuration is captured before a generation job; the coordinator owns scene nodes.

var _road: Node
var _lateral_join: RefCounted
const STRIP_SIDE_BOTH := 0
const STRIP_SIDE_LEFT := -1
const STRIP_SIDE_RIGHT := 1
var sample_step := 0.5
var endpoint_snap_distance := 2.0
var allow_endpoint_to_midpath := true
var strip_shoulder_sidewalk_at_intersections := true
var intersection_strip_length := 0.0
var geometry_cache := preload("./road_junction_geometry_cache.gd").new()
var contour := preload("./road_contour_junction.gd").new()
var junction_geometry_mode := 0

# Discovery consumes immutable position snapshots before welding mutates the
# assembled geometry. Cache support contains positions in array order, never
# path_id/row_idx values, so a cached ordinal always refers to the current rows.
const QUERY_CACHE_MAX_ENTRIES := 2048
const QUERY_CACHE_MAX_IDLE_BUILDS := 2
var incremental_generation_enabled := false
var last_stats: Dictionary = {
	"enabled": false, "queries_reused": 0, "queries_rebuilt": 0,
	"point_queries_reused": 0, "point_queries_rebuilt": 0,
	"pair_queries_reused": 0, "pair_queries_rebuilt": 0,
	"distance_tests": 0, "row_snapshots": 0, "cache_entries": 0, "cache_evicted": 0,
}
var _query_build := 0
var _query_cache: Dictionary = {}
var _discovery_row_snapshots: Array[Dictionary] = []
var _discovery_snapshots_ready := false

func configure(source: Node) -> void:
	_road = source
	_lateral_join = source.get("_lateral_join")
	sample_step = source.get("sample_step")
	endpoint_snap_distance = source.get("endpoint_snap_distance")
	allow_endpoint_to_midpath = source.get("allow_endpoint_to_midpath")
	strip_shoulder_sidewalk_at_intersections = source.get("strip_shoulder_sidewalk_at_intersections")
	intersection_strip_length = source.get("intersection_strip_length")
	var mode: Variant = source.get("junction_geometry_mode")
	junction_geometry_mode = int(mode) if mode != null else 0
	contour.clear()
	incremental_generation_enabled = bool(source.get("incremental_generation_enabled"))
	_begin_query_build()
	geometry_cache.begin_build(incremental_generation_enabled)


func _owns_lateral_pair(a: Dictionary, b: Dictionary) -> bool:
	return _lateral_join != null and _lateral_join.owns_junction_pair(a,b)


func clear_cache() -> void:
	geometry_cache.clear()
	_query_cache.clear()
	_discovery_row_snapshots.clear()
	_discovery_snapshots_ready = false
	last_stats["cache_entries"] = 0


func _begin_query_build() -> void:
	_query_build += 1
	_discovery_row_snapshots.clear()
	_discovery_snapshots_ready = false
	last_stats = {
		"enabled": incremental_generation_enabled,
		"queries_reused": 0,
		"queries_rebuilt": 0,
		"point_queries_reused": 0,
		"point_queries_rebuilt": 0,
		"pair_queries_reused": 0,
		"pair_queries_rebuilt": 0,
		"distance_tests": 0,
		"row_snapshots": 0,
		"cache_entries": 0,
		"cache_evicted": 0,
	}
	if not incremental_generation_enabled:
		_query_cache.clear()
	else:
		for key in _query_cache.keys():
			if _query_build - int(_query_cache[key]["build"]) > QUERY_CACHE_MAX_IDLE_BUILDS:
				_query_cache.erase(key)
				last_stats["cache_evicted"] += 1
	last_stats["cache_entries"] = _query_cache.size()


func _prepare_discovery_row_snapshots(path_rows: Array) -> void:
	if not incremental_generation_enabled or _discovery_snapshots_ready:
		return
	# Both augmentation passes run before any weld. Holding the source arrays here
	# only supplies identity for this build; every query uses the copied positions.
	for rows_raw in path_rows:
		var rows: Array[Dictionary] = rows_raw
		_discovery_row_snapshots.append({"rows": rows, "snapshot": _capture_query_rows(rows)})
	_discovery_snapshots_ready = true


func _capture_query_rows(rows: Array[Dictionary]) -> Dictionary:
	var positions := PackedVector3Array()
	for i in range(1, rows.size() - 1):
		positions.append(Vector3(rows[i].get("position", Vector3.ZERO)))
	last_stats["row_snapshots"] += 1
	return {
		"count": rows.size(),
		"positions": positions,
		"signature": _query_digest(var_to_bytes([rows.size(), positions])),
	}


func _query_rows(rows: Array[Dictionary]) -> Dictionary:
	for entry in _discovery_row_snapshots:
		if is_same(entry["rows"], rows):
			return entry["snapshot"]
	# Direct helper calls outside augmentation are still exact if their caller
	# changes rows between queries: only the explicit discovery pass freezes them.
	return _capture_query_rows(rows)


func _query_digest(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func _same_query_rows(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("count", -1)) == int(b.get("count", -1)) and a.get("positions") == b.get("positions")


func _read_query_cache(key: String, query: PackedByteArray, a: Dictionary, b: Dictionary = {}) -> Dictionary:
	if not _query_cache.has(key):
		return {}
	var entry: Dictionary = _query_cache[key]
	# Compare the exact inputs as well as their digests: hashes are lookup aids,
	# not permission to reuse a result for different geometric support.
	if entry["query"] != query or not _same_query_rows(entry["a"], a) or not _same_query_rows(entry["b"], b):
		return {}
	entry["build"] = _query_build
	_query_cache.erase(key)
	_query_cache[key] = entry
	return entry


func _write_query_cache(key: String, query: PackedByteArray, a: Dictionary, b: Dictionary, result: Variant) -> void:
	_query_cache.erase(key)
	_query_cache[key] = {"query": query, "a": a, "b": b, "result": result, "build": _query_build}
	while _query_cache.size() > QUERY_CACHE_MAX_ENTRIES:
		_query_cache.erase(_query_cache.keys()[0])
		last_stats["cache_evicted"] += 1
	last_stats["cache_entries"] = _query_cache.size()


func _count_query(kind: String, reused: bool) -> void:
	var outcome := "reused" if reused else "rebuilt"
	last_stats["queries_" + outcome] += 1
	last_stats[kind + "_queries_" + outcome] += 1


func weld_cluster(
	verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
	lane_indices: PackedInt32Array, shoulder_indices: PackedInt32Array, sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary], cluster: Array, path_rows: Array, stripped_side_indices: Dictionary,
	path_weld_snap: Array, path_weld_strip_enabled: Array, path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary, invert_faces: bool
) -> void:
	if cluster.size() < 2:
		return
	var started := Time.get_ticks_usec()
	var surfaces := [lane_indices, shoulder_indices, sidewalk_indices]
	if junction_geometry_mode == 1:
		if contour.build(_road, verts, normals, uvs, surfaces, sockets, cluster, path_rows):
			geometry_cache.last_stats.clusters_rebuilt += 1
			geometry_cache.last_stats.geometry_ms += float(Time.get_ticks_usec() - started) / 1000.0
			return
		push_warning("Contour junction kept legacy geometry: " + str(contour.reports.back().get("reason", "Unsupported cluster")))
	var starts := PackedInt32Array([lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size()])
	var query: Dictionary = geometry_cache.make_query(self, verts, normals, uvs,
		sockets, cluster, path_rows, path_weld_snap, path_weld_strip_enabled,
		path_weld_strip_length, invert_faces, not shoulder_indices.is_empty(), not sidewalk_indices.is_empty())
	if geometry_cache.replay(query, verts, normals, uvs, surfaces, stripped_side_indices):
		geometry_cache.last_stats.clusters_reused += 1
		geometry_cache.last_stats.geometry_ms += float(Time.get_ticks_usec() - started) / 1000.0
		return
	geometry_cache.start_recording(query)
	if _cluster_has_midpath_socket(sockets, cluster):
		_weld_cluster_with_midpath_pairs(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices,
			sockets, cluster, path_rows, stripped_side_indices, path_weld_snap,
			path_weld_strip_enabled, path_weld_strip_length, paths_with_mid_intersections)
	elif cluster.size() == 2:
		_weld_two_socket_cluster(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices,
			sockets, cluster, path_rows, stripped_side_indices, path_weld_snap,
			path_weld_strip_enabled, path_weld_strip_length, paths_with_mid_intersections)
	else:
		_weld_endpoint_fan(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices,
			sockets, cluster, path_rows, stripped_side_indices, path_weld_snap,
			path_weld_strip_enabled, path_weld_strip_length, paths_with_mid_intersections, invert_faces)
	geometry_cache.store_patch(query, verts, normals, uvs, surfaces, starts)
	geometry_cache.last_stats.clusters_rebuilt += 1
	geometry_cache.last_stats.geometry_ms += float(Time.get_ticks_usec() - started) / 1000.0


func _weld_endpoint_fan(
	verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
	lane_indices: PackedInt32Array, shoulder_indices: PackedInt32Array, sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary], cluster: Array, path_rows: Array, stripped_side_indices: Dictionary,
	path_weld_snap: Array, path_weld_strip_enabled: Array, path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary, invert_faces: bool
) -> void:
	var center := Vector3.ZERO
	for s_idx in cluster:
		center += sockets[s_idx]["position"]
	center /= float(cluster.size())

	var shoulders: Array[Dictionary] = []
	for s_idx in cluster:
		var s := sockets[s_idx]
		var s_path_id := int(s.get("path_id", -1))
		if strip_shoulder_sidewalk_at_intersections:
			if _is_path_strip_enabled(s_path_id, path_weld_strip_enabled):
				var strip_len := _resolve_path_strip_length(s_path_id, path_weld_snap, path_weld_strip_length)
				var strip_snap := _resolve_path_snap_for_id(s_path_id, path_weld_snap)
				var strip_focus := _find_strip_focus_for_socket(sockets, cluster, int(s_idx))
				if bool(strip_focus.get("ok", false)):
					var focus_pos: Vector3 = strip_focus.get("position", s.get("position", Vector3.ZERO))
					var focus_path_id := int(strip_focus.get("path_id", -1))
					_strip_endpoint_rows_near_socket(
						verts,
						normals,
						uvs,
						path_rows,
						s,
						strip_len,
						strip_snap,
						stripped_side_indices,
						focus_pos,
						focus_path_id,
						true
					)

		var row_a: int = s["row_a"]
		var row_b: int = s["row_b"]
		var socket_width := float(s["width"])
		if strip_shoulder_sidewalk_at_intersections:
			socket_width = max(0.1, verts[row_a].distance_to(verts[row_b]))
		var dir: Vector3 = s["position"] - center
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = s["out_dir"]
			dir.y = 0.0
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()

		var local_snap: float = float(s.get("weld_snap_distance", endpoint_snap_distance))
		var arm_distance: float = max(socket_width * 0.75, local_snap)
		var arm_center := center + dir * arm_distance
		var right := Vector3.UP.cross(dir).normalized()
		if right.length() < 0.001:
			right = Vector3.RIGHT

		var half_w := socket_width * 0.5
		var s0 := arm_center - right * half_w
		var s1 := arm_center + right * half_w
		s0.y = center.y
		s1.y = center.y

		var current_a: Vector3 = verts[row_a]
		var current_b: Vector3 = verts[row_b]
		var keep_cost := current_a.distance_to(s0) + current_b.distance_to(s1)
		var swap_cost := current_a.distance_to(s1) + current_b.distance_to(s0)
		if swap_cost < keep_cost:
			var tmp := s0
			s0 = s1
			s1 = tmp

		_apply_row_edge_strip_transform(
			verts,
			normals,
			uvs,
			s.get("row_edges", []),
			row_a,
			row_b,
			s0,
			s1
		)

		shoulders.push_back({"index": row_a, "position": s0, "angle": atan2(s0.z - center.z, s0.x - center.x)})
		shoulders.push_back({"index": row_b, "position": s1, "angle": atan2(s1.z - center.z, s1.x - center.x)})

	if shoulders.size() < 3:
		return

	shoulders.sort_custom(func(a, b): return a["angle"] < b["angle"])

	var ring_indices: Array[int] = []
	var ring_positions: Array[Vector3] = []
	for sh in shoulders:
		var idx: int = sh["index"]
		var p: Vector3 = sh["position"]
		if ring_indices.is_empty():
			ring_indices.push_back(idx)
			ring_positions.push_back(p)
			continue
		if ring_indices[ring_indices.size() - 1] == idx:
			continue
		if ring_positions[ring_positions.size() - 1].distance_to(p) <= 0.02:
			continue
		ring_indices.push_back(idx)
		ring_positions.push_back(p)

	if ring_indices.size() >= 2 and ring_positions[0].distance_to(ring_positions[ring_positions.size() - 1]) <= 0.02:
		ring_indices.remove_at(ring_indices.size() - 1)
		ring_positions.remove_at(ring_positions.size() - 1)

	if ring_indices.size() < 3:
		return

	var center_idx := verts.size()
	verts.push_back(center)
	normals.push_back(Vector3.UP)
	uvs.push_back(Vector2(0.5, 0.5))

	for i in range(ring_indices.size()):
		var i1: int = ring_indices[i]
		var i2: int = ring_indices[(i + 1) % ring_indices.size()]
		if invert_faces:
			_road._append_triangle_to_outer_surface(lane_indices, shoulder_indices, sidewalk_indices, center_idx, i2, i1)
		else:
			_road._append_triangle_to_outer_surface(lane_indices, shoulder_indices, sidewalk_indices, center_idx, i1, i2)




func _cluster_has_midpath_socket(sockets: Array[Dictionary], cluster: Array) -> bool:
	for idx in cluster:
		if not bool(sockets[idx].get("is_endpoint", true)):
			return true
	return false


func _weld_cluster_with_midpath_pairs(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary],
	cluster: Array,
	path_rows: Array,
	stripped_side_indices: Dictionary,
	path_weld_snap: Array,
	path_weld_strip_enabled: Array,
	path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary
) -> void:
	var endpoint_indices: Array = []
	var mid_indices: Array = []
	for idx in cluster:
		if bool(sockets[idx].get("is_endpoint", true)):
			endpoint_indices.push_back(idx)
		else:
			mid_indices.push_back(idx)

	if endpoint_indices.is_empty() or mid_indices.is_empty():
		return

	for e_idx in endpoint_indices:
		var best_mid := -1
		var best_dist := INF
		var e_path: int = sockets[e_idx]["path_id"]
		var e_pos: Vector3 = sockets[e_idx]["position"]
		for m_idx in mid_indices:
			var m_path: int = sockets[m_idx]["path_id"]
			if m_path == e_path:
				continue
			var d := e_pos.distance_to(sockets[m_idx]["position"])
			var pair_snap := _resolve_socket_pair_snap_distance(sockets[e_idx], sockets[m_idx], path_weld_snap)
			if d <= pair_snap and d < best_dist:
				best_dist = d
				best_mid = m_idx
		if best_mid >= 0:
			_weld_two_socket_cluster(
				verts,
				normals,
				uvs,
				lane_indices,
				shoulder_indices,
				sidewalk_indices,
				sockets,
				[e_idx, best_mid],
				path_rows,
				stripped_side_indices,
				path_weld_snap,
				path_weld_strip_enabled,
				path_weld_strip_length,
				paths_with_mid_intersections
			)


func _weld_two_socket_cluster(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary],
	cluster: Array,
	path_rows: Array,
	stripped_side_indices: Dictionary,
	path_weld_snap: Array,
	path_weld_strip_enabled: Array,
	path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary
) -> void:
	var s0: Dictionary = sockets[cluster[0]]
	var s1: Dictionary = sockets[cluster[1]]

	# Prefer welding endpoint into mid-path row when available.
	var source := s0
	var target := s1
	if bool(s1.get("is_endpoint", false)) and not bool(s0.get("is_endpoint", false)):
		source = s1
		target = s0
	var source_is_endpoint: bool = bool(source.get("is_endpoint", true))
	var target_is_midpath: bool = not bool(target.get("is_endpoint", true))
	var source_path_id := int(source.get("path_id", -1))
	var target_path_id := int(target.get("path_id", -1))
	var source_edges: Array = source.get("row_edges", [])
	var target_all_edges: Array = target.get("row_edges", [])
	if strip_shoulder_sidewalk_at_intersections:
		if _is_path_strip_enabled(source_path_id, path_weld_strip_enabled):
			var source_strip_length := _resolve_path_strip_length(source_path_id, path_weld_snap, path_weld_strip_length)
			var source_snap := _resolve_path_snap_for_id(source_path_id, path_weld_snap)
			var target_focus_pos: Vector3 = target.get("position", source.get("position", Vector3.ZERO))
			_strip_endpoint_rows_near_socket(
				verts,
				normals,
				uvs,
				path_rows,
				source,
				source_strip_length,
				source_snap,
				stripped_side_indices,
				target_focus_pos,
				target_path_id,
				true
			)
		if _is_path_strip_enabled(target_path_id, path_weld_strip_enabled):
			var target_strip_length := _resolve_path_strip_length(target_path_id, path_weld_snap, path_weld_strip_length)
			var target_snap := _resolve_path_snap_for_id(target_path_id, path_weld_snap)
			var source_focus_pos: Vector3 = source.get("position", target.get("position", Vector3.ZERO))
			_strip_endpoint_rows_near_socket(
				verts,
				normals,
				uvs,
				path_rows,
				target,
				target_strip_length,
				target_snap,
				stripped_side_indices,
				source_focus_pos,
				source_path_id,
				true
			)

	var sa: int = source["row_a"]
	var sb: int = source["row_b"]
	var ta: int = target["row_a"]
	var tb: int = target["row_b"]

	var va := verts[sa]
	var vb := verts[sb]
	var wa := verts[ta]
	var wb := verts[tb]

	var keep_cost := va.distance_to(wa) + vb.distance_to(wb)
	var swap_cost := va.distance_to(wb) + vb.distance_to(wa)
	if swap_cost < keep_cost:
		var tmp := ta
		ta = tb
		tb = tmp
		var tmp_v := wa
		wa = wb
		wb = tmp_v

	if source_is_endpoint and target_is_midpath:
		# Edge weld to the side indicated by branch outward direction.
		var target_a := verts[ta]
		var target_b := verts[tb]
		var target_center := (target_a + target_b) * 0.5

		var side_a := (target_a - target_center).normalized()
		var side_b := (target_b - target_center).normalized()
		var source_dir: Vector3 = source["out_dir"]
		source_dir.y = 0.0
		if source_dir.length() < 0.001:
			source_dir = (source["position"] - target_center).normalized()
		if source_dir.length() < 0.001:
			source_dir = side_a

		var score_a := side_a.dot(source_dir)
		var score_b := side_b.dot(source_dir)

		var contact_idx := ta
		var contact_pos := target_a
		var outward := side_a
		if score_b > score_a:
			contact_idx = tb
			contact_pos = target_b
			outward = side_b

		if outward.length() < 0.001:
			outward = (contact_pos - target_center).normalized()
		if outward.length() < 0.001:
			outward = Vector3.RIGHT

		# True 2-vertex weld: scan the whole selected side and pick the best adjacent pair.
		if target_path_id >= 0 and target_path_id < path_rows.size():
			var rows: Array[Dictionary] = path_rows[target_path_id]
			if rows.size() >= 2:
				var side_key := "row_a"
				if int(target["row_b"]) == contact_idx:
					side_key = "row_b"

				var best_a := -1
				var best_b := -1
				var best_cost := INF

				for row_i in range(rows.size() - 1):
					geometry_cache.last_stats.side_pairs_tested += 1
					var row0: Dictionary = rows[row_i]
					var row1: Dictionary = rows[row_i + 1]
					var c0: int = int(row0[side_key])
					var c1: int = int(row1[side_key])
					if c0 == c1:
						continue

					var keep_map_cost := verts[sa].distance_to(verts[c0]) + verts[sb].distance_to(verts[c1])
					if keep_map_cost < best_cost:
						best_cost = keep_map_cost
						best_a = c0
						best_b = c1

					var swap_map_cost := verts[sa].distance_to(verts[c1]) + verts[sb].distance_to(verts[c0])
					if swap_map_cost < best_cost:
						best_cost = swap_map_cost
						best_a = c1
						best_b = c0

				if best_a >= 0 and best_b >= 0:
					_apply_row_edge_strip_transform(
						verts,
						normals,
						uvs,
						source_edges,
						sa,
						sb,
						verts[best_a],
						verts[best_b],
						best_a,
						best_b
					)

					_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sa, best_a)
					_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sb, best_b)
					return

		var source_width = max(0.1, va.distance_to(vb))
		var outer_pos = contact_pos + outward * source_width

		var sa_contact := sa
		var sb_outer := sb
		if verts[sb].distance_to(contact_pos) < verts[sa].distance_to(contact_pos):
			sa_contact = sb
			sb_outer = sa

		_apply_row_edge_strip_transform(
			verts,
			normals,
			uvs,
			source_edges,
			sa_contact,
			sb_outer,
			contact_pos,
			outer_pos,
			contact_idx,
			-1
		)

		# Collapse only contact edge index to target side index.
		_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sa_contact, contact_idx)
	else:
		# Endpoint-endpoint case: symmetric merge.
		var target_edges: Array = target_all_edges
		if source_edges.size() == target_edges.size() and source_edges.size() >= 2:
			var reverse_target_order := false
			var keep_cost_full := 0.0
			var reverse_cost_full := 0.0
			var edge_count := source_edges.size()
			for edge_i in range(edge_count):
				var s_idx := int(source_edges[edge_i])
				var t_keep_idx := int(target_edges[edge_i])
				var t_reverse_idx := int(target_edges[edge_count - 1 - edge_i])
				keep_cost_full += verts[s_idx].distance_to(verts[t_keep_idx])
				reverse_cost_full += verts[s_idx].distance_to(verts[t_reverse_idx])
			if reverse_cost_full < keep_cost_full:
				reverse_target_order = true
			elif is_equal_approx(reverse_cost_full, keep_cost_full):
				var source_span := verts[int(source_edges[source_edges.size() - 1])] - verts[int(source_edges[0])]
				var target_span := verts[int(target_edges[target_edges.size() - 1])] - verts[int(target_edges[0])]
				if source_span.dot(target_span) < 0.0:
					reverse_target_order = true

			for edge_i in range(source_edges.size()):
				var s_idx := int(source_edges[edge_i])
				var target_idx := edge_i
				if reverse_target_order:
					target_idx = source_edges.size() - 1 - edge_i
				var t_idx := int(target_edges[target_idx])
				var merged := (verts[s_idx] + verts[t_idx]) * 0.5
				verts[t_idx] = merged
				verts[s_idx] = merged
				normals[t_idx] = Vector3.UP
				normals[s_idx] = Vector3.UP
				uvs[s_idx] = uvs[t_idx]
				_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, s_idx, t_idx)
		else:
			var merged_a := (va + wa) * 0.5
			var merged_b := (vb + wb) * 0.5
			verts[ta] = merged_a
			verts[tb] = merged_b
			normals[ta] = Vector3.UP
			normals[tb] = Vector3.UP
			_apply_row_edge_strip_transform(
				verts,
				normals,
				uvs,
				source_edges,
				sa,
				sb,
				merged_a,
				merged_b,
				ta,
				tb
			)
			# Real weld: remap source row indices to target row indices in the mesh.
			_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sa, ta)
			_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sb, tb)


func _collapse_row_side_edges_to_lane(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	row_edges_raw: Array,
	strip_side: int = STRIP_SIDE_BOTH
) -> void:
	if row_edges_raw.size() < 6:
		return
	var left_lane_idx := int(row_edges_raw[2])
	var right_lane_idx := int(row_edges_raw[3])
	var left_lane := verts[left_lane_idx]
	var right_lane := verts[right_lane_idx]
	var left_uv := uvs[left_lane_idx]
	var right_uv := uvs[right_lane_idx]

	if strip_side != STRIP_SIDE_RIGHT:
		for idx_raw in [row_edges_raw[0], row_edges_raw[1]]:
			var idx := int(idx_raw)
			verts[idx] = left_lane
			normals[idx] = Vector3.UP
			uvs[idx] = left_uv

	if strip_side != STRIP_SIDE_LEFT:
		for idx_raw in [row_edges_raw[4], row_edges_raw[5]]:
			var idx := int(idx_raw)
			verts[idx] = right_lane
			normals[idx] = Vector3.UP
			uvs[idx] = right_uv


func _strip_endpoint_rows_near_socket(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	path_rows: Array,
	socket: Dictionary,
	strip_length: float,
	strip_snap_distance: float,
	marked: Dictionary,
	focus_position: Vector3 = Vector3.ZERO,
	focus_path_id: int = -1,
	use_focus_side: bool = false
) -> void:
	if strip_length <= 0.0001:
		return
	var path_id := int(socket.get("path_id", -1))
	if path_id < 0 or path_id >= path_rows.size():
		return
	var rows_raw: Array = path_rows[path_id]
	if rows_raw.is_empty():
		return
	var row_idx := int(socket.get("row_idx", -1))
	if row_idx < 0 or row_idx >= rows_raw.size():
		return

	var anchor_row: Dictionary = rows_raw[row_idx]
	var anchor_pos: Vector3 = anchor_row.get("position", Vector3.ZERO)
	var anchor_edges: Array = anchor_row.get("row_edges", [])
	var is_endpoint := bool(socket.get("is_endpoint", true))
	var strip_side := STRIP_SIDE_BOTH
	if use_focus_side:
		if focus_path_id >= 0 and focus_path_id == path_id:
			return
		strip_side = _resolve_strip_side_for_row(verts, anchor_edges, focus_position)
		# Focused strip mode: remove the full local segment (anchor + one adjacent row).
		_collapse_row_side_edges_to_lane(verts, normals, uvs, anchor_edges, strip_side)
		_mark_row_side_vertices_for_strip(marked, anchor_edges, strip_side)
		var neighbor_row_idx := _pick_adjacent_strip_row(rows_raw, row_idx, focus_position)
		if neighbor_row_idx >= 0 and neighbor_row_idx < rows_raw.size() and neighbor_row_idx != row_idx:
			var neighbor_row: Dictionary = rows_raw[neighbor_row_idx]
			var neighbor_edges: Array = neighbor_row.get("row_edges", [])
			_collapse_row_side_edges_to_lane(verts, normals, uvs, neighbor_edges, strip_side)
			_mark_row_side_vertices_for_strip(marked, neighbor_edges, strip_side)
		return

	if is_endpoint:
		var step := 1
		if row_idx >= rows_raw.size() - 1:
			step = -1
		elif row_idx > 0 and row_idx >= rows_raw.size() / 2:
			step = -1
		var i := row_idx
		while i >= 0 and i < rows_raw.size():
			var row: Dictionary = rows_raw[i]
			var row_pos: Vector3 = row.get("position", anchor_pos)
			if row_pos.distance_to(anchor_pos) > strip_length:
				break
			var row_edges: Array = row.get("row_edges", [])
			_collapse_row_side_edges_to_lane(verts, normals, uvs, row_edges, strip_side)
			_mark_row_side_vertices_for_strip(marked, row_edges, strip_side)
			i += step
		return

	# Mid-path sockets: strip both directions around the intersection.
	var first_row: Dictionary = rows_raw[0]
	var last_row: Dictionary = rows_raw[rows_raw.size() - 1]
	var first_pos: Vector3 = first_row.get("position", anchor_pos)
	var last_pos: Vector3 = last_row.get("position", anchor_pos)
	var path_span := first_pos.distance_to(last_pos)
	var end_guard_length: float = max(sample_step * 2.0, maxf(0.1, strip_snap_distance) * 0.75)
	if path_span > 0.0001:
		end_guard_length = min(end_guard_length, path_span * 0.45)

	var forward_i := row_idx
	while forward_i < rows_raw.size():
		if forward_i == rows_raw.size() - 1:
			break
		var forward_row: Dictionary = rows_raw[forward_i]
		var forward_pos: Vector3 = forward_row.get("position", anchor_pos)
		if forward_pos.distance_to(last_pos) <= end_guard_length:
			break
		if forward_pos.distance_to(anchor_pos) > strip_length:
			break
		var forward_edges: Array = forward_row.get("row_edges", [])
		_collapse_row_side_edges_to_lane(verts, normals, uvs, forward_edges, strip_side)
		_mark_row_side_vertices_for_strip(marked, forward_edges, strip_side)
		forward_i += 1

	var backward_i := row_idx - 1
	while backward_i >= 0:
		if backward_i == 0:
			break
		var backward_row: Dictionary = rows_raw[backward_i]
		var backward_pos: Vector3 = backward_row.get("position", anchor_pos)
		if backward_pos.distance_to(first_pos) <= end_guard_length:
			break
		if backward_pos.distance_to(anchor_pos) > strip_length:
			break
		var backward_edges: Array = backward_row.get("row_edges", [])
		_collapse_row_side_edges_to_lane(verts, normals, uvs, backward_edges, strip_side)
		_mark_row_side_vertices_for_strip(marked, backward_edges, strip_side)
		backward_i -= 1


func _resolve_strip_side_for_row(
	verts: PackedVector3Array,
	row_edges_raw: Array,
	focus_position: Vector3
) -> int:
	if row_edges_raw.size() < 6:
		return STRIP_SIDE_BOTH
	var left_a := int(row_edges_raw[0])
	var left_b := int(row_edges_raw[1])
	var right_a := int(row_edges_raw[4])
	var right_b := int(row_edges_raw[5])
	if (
		left_a < 0
		or left_a >= verts.size()
		or left_b < 0
		or left_b >= verts.size()
		or right_a < 0
		or right_a >= verts.size()
		or right_b < 0
		or right_b >= verts.size()
	):
		return STRIP_SIDE_BOTH

	var left_mid := (verts[left_a] + verts[left_b]) * 0.5
	var right_mid := (verts[right_a] + verts[right_b]) * 0.5
	var focus_xz := Vector3(focus_position.x, 0.0, focus_position.z)
	var left_xz := Vector3(left_mid.x, 0.0, left_mid.z)
	var right_xz := Vector3(right_mid.x, 0.0, right_mid.z)
	var left_dist := left_xz.distance_to(focus_xz)
	var right_dist := right_xz.distance_to(focus_xz)
	if absf(left_dist - right_dist) <= 0.001:
		return STRIP_SIDE_BOTH
	if left_dist < right_dist:
		return STRIP_SIDE_LEFT
	return STRIP_SIDE_RIGHT


func _pick_adjacent_strip_row(rows_raw: Array, row_idx: int, focus_position: Vector3) -> int:
	if rows_raw.size() < 2:
		return -1
	if row_idx <= 0:
		return 1
	if row_idx >= rows_raw.size() - 1:
		return rows_raw.size() - 2

	var focus_xz := Vector3(focus_position.x, 0.0, focus_position.z)
	var prev_row: Dictionary = rows_raw[row_idx - 1]
	var next_row: Dictionary = rows_raw[row_idx + 1]
	var prev_pos: Vector3 = prev_row.get("position", Vector3.ZERO)
	var next_pos: Vector3 = next_row.get("position", Vector3.ZERO)
	var prev_xz := Vector3(prev_pos.x, 0.0, prev_pos.z)
	var next_xz := Vector3(next_pos.x, 0.0, next_pos.z)
	if prev_xz.distance_to(focus_xz) <= next_xz.distance_to(focus_xz):
		return row_idx - 1
	return row_idx + 1


func _mark_row_side_vertices_for_strip(
	marked: Dictionary,
	row_edges_raw: Array,
	strip_side: int = STRIP_SIDE_BOTH
) -> void:
	if row_edges_raw.size() < 6:
		return
	if strip_side != STRIP_SIDE_RIGHT:
		marked[int(row_edges_raw[0])] = true
		marked[int(row_edges_raw[1])] = true
		geometry_cache.record_mark(int(row_edges_raw[0]))
		geometry_cache.record_mark(int(row_edges_raw[1]))
	if strip_side != STRIP_SIDE_LEFT:
		marked[int(row_edges_raw[4])] = true
		marked[int(row_edges_raw[5])] = true
		geometry_cache.record_mark(int(row_edges_raw[4]))
		geometry_cache.record_mark(int(row_edges_raw[5]))


func _find_strip_focus_for_socket(sockets: Array[Dictionary], cluster: Array, socket_idx: int) -> Dictionary:
	var out := {"ok": false}
	if socket_idx < 0 or socket_idx >= sockets.size():
		return out
	var socket: Dictionary = sockets[socket_idx]
	var socket_path := int(socket.get("path_id", -1))
	var socket_pos: Vector3 = socket.get("position", Vector3.ZERO)
	var best_dist := INF
	var best_path := -1
	var best_pos := socket_pos
	for other_idx_raw in cluster:
		var other_idx := int(other_idx_raw)
		if other_idx == socket_idx:
			continue
		if other_idx < 0 or other_idx >= sockets.size():
			continue
		var other: Dictionary = sockets[other_idx]
		var other_path := int(other.get("path_id", -1))
		if other_path == socket_path:
			continue
		var other_pos: Vector3 = other.get("position", socket_pos)
		var d := socket_pos.distance_to(other_pos)
		if d < best_dist:
			best_dist = d
			best_path = other_path
			best_pos = other_pos
	if best_path < 0:
		return out
	out["ok"] = true
	out["path_id"] = best_path
	out["position"] = best_pos
	return out


func _move_blocked_triangles_to_lane(
	indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	blocked: Dictionary
) -> PackedInt32Array:
	if indices.is_empty() or blocked.is_empty():
		return indices
	var out := PackedInt32Array()
	var i := 0
	while i + 2 < indices.size():
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var blocked_count := 0
		if blocked.has(a):
			blocked_count += 1
		if blocked.has(b):
			blocked_count += 1
		if blocked.has(c):
			blocked_count += 1
		if blocked_count >= 2:
			if a != b and b != c and c != a:
				lane_indices.push_back(a)
				lane_indices.push_back(b)
				lane_indices.push_back(c)
		else:
			out.push_back(a)
			out.push_back(b)
			out.push_back(c)
		i += 3
	return out


func _apply_row_edge_strip_transform(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	row_edges_raw: Array,
	end_a_idx: int,
	end_b_idx: int,
	end_a_pos: Vector3,
	end_b_pos: Vector3,
	uv_a_idx: int = -1,
	uv_b_idx: int = -1
) -> void:
	var row_edges: Array = []
	for idx in row_edges_raw:
		row_edges.push_back(int(idx))
	if row_edges.size() < 2:
		row_edges = [end_a_idx, end_b_idx]

	var pos_a := row_edges.find(end_a_idx)
	var pos_b := row_edges.find(end_b_idx)
	if pos_a < 0 or pos_b < 0:
		row_edges = [end_a_idx, end_b_idx]
	else:
		if pos_a > pos_b:
			row_edges.reverse()

	var uv_a := uvs[end_a_idx]
	var uv_b := uvs[end_b_idx]
	if uv_a_idx >= 0 and uv_a_idx < uvs.size():
		uv_a = uvs[uv_a_idx]
	if uv_b_idx >= 0 and uv_b_idx < uvs.size():
		uv_b = uvs[uv_b_idx]

	var old_positions: Array[Vector3] = []
	old_positions.resize(row_edges.size())
	for i in range(row_edges.size()):
		old_positions[i] = verts[int(row_edges[i])]

	var cumulative := PackedFloat32Array()
	cumulative.resize(row_edges.size())
	cumulative[0] = 0.0
	var total_len := 0.0
	for i in range(1, row_edges.size()):
		total_len += old_positions[i - 1].distance_to(old_positions[i])
		cumulative[i] = total_len

	var denom:int = max(1, row_edges.size() - 1)
	for i in range(row_edges.size()):
		var row_idx := int(row_edges[i])
		var t := float(i) / float(denom)
		if total_len > 0.0001:
			t = cumulative[i] / total_len
		verts[row_idx] = end_a_pos.lerp(end_b_pos, t)
		normals[row_idx] = Vector3.UP
		uvs[row_idx] = uv_a.lerp(uv_b, t)


func _add_socket_unique(sockets: Array[Dictionary], keys: Dictionary, row: Dictionary, is_endpoint: bool) -> void:
	var key := str(row["path_id"]) + ":" + str(row["row_idx"])
	if keys.has(key):
		return
	keys[key] = true

	var s := row.duplicate(true)
	s["is_endpoint"] = is_endpoint
	sockets.push_back(s)


func _augment_with_midpath_sockets(
	sockets: Array[Dictionary],
	keys: Dictionary,
	path_rows: Array,
	endpoint_count: int,
	path_weld_allow_midpath: Array,
	path_weld_snap: Array
) -> void:
	_prepare_discovery_row_snapshots(path_rows)
	for i in range(endpoint_count):
		var ep: Dictionary = sockets[i]
		var ep_path_id: int = int(ep.get("path_id", -1))
		if not _is_path_allow_midpath(ep_path_id, path_weld_allow_midpath):
			continue
		var ep_pos: Vector3 = Vector3(ep.get("position", Vector3.ZERO))

		for path_id in range(path_rows.size()):
			if path_id == ep_path_id:
				continue
			if not _is_path_allow_midpath(path_id, path_weld_allow_midpath):
				continue
			var rows: Array[Dictionary] = path_rows[path_id]
			if rows.size() < 3:
				continue

			var pair_snap: float = maxf(
				_resolve_path_snap_for_id(ep_path_id, path_weld_snap),
				_resolve_path_snap_for_id(path_id, path_weld_snap)
			)
			var nearest_idx := _find_nearest_inner_row(rows, ep_pos, pair_snap)
			if nearest_idx < 0:
				continue

			if _owns_lateral_pair(ep, rows[nearest_idx]):
				continue
			_add_socket_unique(sockets, keys, rows[nearest_idx], false)


func _augment_with_midpath_pair_sockets(
	sockets: Array[Dictionary],
	keys: Dictionary,
	path_rows: Array,
	path_weld_allow_midpath: Array,
	path_weld_snap: Array
) -> void:
	_prepare_discovery_row_snapshots(path_rows)
	for path_a in range(path_rows.size()):
		if not _is_path_allow_midpath(path_a, path_weld_allow_midpath):
			continue
		var rows_a: Array[Dictionary] = path_rows[path_a]
		if rows_a.size() < 3:
			continue

		for path_b in range(path_a + 1, path_rows.size()):
			if not _is_path_allow_midpath(path_b, path_weld_allow_midpath):
				continue
			var rows_b: Array[Dictionary] = path_rows[path_b]
			if rows_b.size() < 3:
				continue

			var pair_snap: float = maxf(
				_resolve_path_snap_for_id(path_a, path_weld_snap),
				_resolve_path_snap_for_id(path_b, path_weld_snap)
			)
			var pair_rows := _find_nearest_inner_row_pair(rows_a, rows_b, pair_snap * 2.5)
			if pair_rows.size() < 2:
				continue

			var a_idx := int(pair_rows[0])
			var b_idx := int(pair_rows[1])
			if a_idx <= 0 or a_idx >= rows_a.size() - 1:
				continue
			if b_idx <= 0 or b_idx >= rows_b.size() - 1:
				continue

			if _owns_lateral_pair(rows_a[a_idx], rows_b[b_idx]):
				continue
			_add_socket_unique(sockets, keys, rows_a[a_idx], false)
			_add_socket_unique(sockets, keys, rows_b[b_idx], false)


func _find_nearest_inner_row(rows: Array[Dictionary], point: Vector3, max_distance: float) -> int:
	if incremental_generation_enabled:
		var snapshot := _query_rows(rows)
		var query := var_to_bytes([0, snapshot["signature"], point, max_distance])
		var key := _query_digest(query)
		var cached := _read_query_cache(key, query, snapshot)
		if not cached.is_empty():
			_count_query("point", true)
			return int(cached["result"])
		_count_query("point", false)
		var positions: PackedVector3Array = snapshot["positions"]
		var nearest := -1
		var nearest_distance := max_distance
		last_stats["distance_tests"] += positions.size()
		for i in range(positions.size()):
			var distance := positions[i].distance_to(point)
			if distance <= nearest_distance:
				nearest_distance = distance
				nearest = i + 1
		_write_query_cache(key, query, snapshot, {}, nearest)
		return nearest
	_count_query("point", false)
	if rows.size() < 3:
		return -1

	var best := -1
	var best_dist := max_distance
	last_stats["distance_tests"] += rows.size() - 2
	for i in range(1, rows.size() - 1):
		var p: Vector3 = Vector3(rows[i].get("position", Vector3.ZERO))
		var d := p.distance_to(point)
		if d <= best_dist:
			best_dist = d
			best = i
	return best


func _find_nearest_inner_row_pair(
	rows_a: Array[Dictionary],
	rows_b: Array[Dictionary],
	max_distance: float
) -> PackedInt32Array:
	if incremental_generation_enabled:
		var snapshot_a := _query_rows(rows_a)
		var snapshot_b := _query_rows(rows_b)
		var query := var_to_bytes([1, snapshot_a["signature"], snapshot_b["signature"], max_distance])
		var key := _query_digest(query)
		var cached := _read_query_cache(key, query, snapshot_a, snapshot_b)
		if not cached.is_empty():
			_count_query("pair", true)
			var cached_result: PackedInt32Array = cached["result"]
			return cached_result.duplicate()
		_count_query("pair", false)
		var positions_a: PackedVector3Array = snapshot_a["positions"]
		var positions_b: PackedVector3Array = snapshot_b["positions"]
		var nearest_a := -1
		var nearest_b := -1
		var nearest_distance := max_distance
		last_stats["distance_tests"] += positions_a.size() * positions_b.size()
		for i in range(positions_a.size()):
			for j in range(positions_b.size()):
				var distance := positions_a[i].distance_to(positions_b[j])
				if distance > nearest_distance:
					continue
				nearest_distance = distance
				nearest_a = i + 1
				nearest_b = j + 1
		var result := PackedInt32Array()
		if nearest_a >= 0 and nearest_b >= 0:
			result.append(nearest_a)
			result.append(nearest_b)
		_write_query_cache(key, query, snapshot_a, snapshot_b, result.duplicate())
		return result
	_count_query("pair", false)
	var out := PackedInt32Array()
	if rows_a.size() < 3 or rows_b.size() < 3:
		return out

	var best_a := -1
	var best_b := -1
	var best_dist := max_distance
	last_stats["distance_tests"] += (rows_a.size() - 2) * (rows_b.size() - 2)

	for i in range(1, rows_a.size() - 1):
		var pa: Vector3 = rows_a[i].get("position", Vector3.ZERO)
		for j in range(1, rows_b.size() - 1):
			var pb: Vector3 = rows_b[j].get("position", Vector3.ZERO)
			var d := pa.distance_to(pb)
			if d > best_dist:
				continue
			best_dist = d
			best_a = i
			best_b = j

	if best_a >= 0 and best_b >= 0:
		out.push_back(best_a)
		out.push_back(best_b)
	return out


func _cluster_sockets(
	sockets: Array[Dictionary],
	min_paths: int,
	path_weld_snap: Array,
	snap_scale: float = 1.0
) -> Array:
	var clusters: Array = []
	var used: Dictionary = {}
	var scale := maxf(0.01, snap_scale)

	for i in range(sockets.size()):
		if used.has(i):
			continue

		var cluster: Array = [i]
		used[i] = true
		var changed := true
		while changed:
			changed = false
			for j in range(sockets.size()):
				if used.has(j):
					continue
				for idx in cluster:
					if _owns_lateral_pair(sockets[idx], sockets[j]):
						continue
					var a: Vector3 = sockets[idx]["position"]
					var b: Vector3 = sockets[j]["position"]
					var pair_snap := _resolve_socket_pair_snap_distance(sockets[idx], sockets[j], path_weld_snap)
					if a.distance_to(b) <= pair_snap * scale:
						cluster.push_back(j)
						used[j] = true
						changed = true
						break

		var path_set: Dictionary = {}
		for idx in cluster:
			path_set[sockets[idx]["path_id"]] = true
		if path_set.size() >= min_paths:
			clusters.push_back(cluster)

	return clusters


func _resolve_socket_pair_snap_distance(socket_a: Dictionary, socket_b: Dictionary, path_weld_snap: Array) -> float:
	var path_a := int(socket_a.get("path_id", -1))
	var path_b := int(socket_b.get("path_id", -1))
	var snap_a := float(socket_a.get("weld_snap_distance", _resolve_path_snap_for_id(path_a, path_weld_snap)))
	var snap_b := float(socket_b.get("weld_snap_distance", _resolve_path_snap_for_id(path_b, path_weld_snap)))
	return maxf(0.1, maxf(snap_a, snap_b))


func _resolve_path_snap_for_id(path_id: int, path_weld_snap: Array) -> float:
	if path_id >= 0 and path_id < path_weld_snap.size():
		return maxf(0.1, float(path_weld_snap[path_id]))
	return maxf(0.1, endpoint_snap_distance)


func _is_path_allow_midpath(path_id: int, path_weld_allow_midpath: Array) -> bool:
	if path_id >= 0 and path_id < path_weld_allow_midpath.size():
		return bool(path_weld_allow_midpath[path_id])
	return allow_endpoint_to_midpath


func _is_path_strip_enabled(path_id: int, path_weld_strip_enabled: Array) -> bool:
	if path_id >= 0 and path_id < path_weld_strip_enabled.size():
		return bool(path_weld_strip_enabled[path_id])
	return strip_shoulder_sidewalk_at_intersections


func _resolve_path_strip_length(path_id: int, _path_weld_snap: Array, path_weld_strip_length: Array) -> float:
	if path_id >= 0 and path_id < path_weld_strip_length.size():
		return maxf(0.0, float(path_weld_strip_length[path_id]))
	return maxf(0.0, intersection_strip_length)


# Typed entry points into the generation coordinator.
func _remap_index_in_all_surfaces(
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	from_idx: int,
	to_idx: int
) -> void:
	_road._remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, from_idx, to_idx)
	if from_idx != to_idx:
		geometry_cache.last_stats.remap_index_visits += lane_indices.size() + shoulder_indices.size() + sidewalk_indices.size()
	geometry_cache.record_remap(from_idx, to_idx)
