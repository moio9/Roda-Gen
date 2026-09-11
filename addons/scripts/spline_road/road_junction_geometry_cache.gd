@tool
extends RefCounted
## Exact read-support and sparse write patches for one ordered weld cluster.
## Entries contain local vertex ordinals, never stale global mesh indices.

const MAX_ENTRIES := 256
const MAX_PAYLOAD_BYTES := 64 * 1024 * 1024
const MAX_IDLE_BUILDS := 2
var enabled := false
var recording := false
var last_stats: Dictionary = {}
var path_ids := PackedInt64Array()
var _entries: Dictionary = {}
var _generation := 0
var _bytes := 0
var _remaps := PackedInt32Array()
var _marks: Dictionary = {}


func begin_build(use_cache: bool) -> void:
	enabled = use_cache
	recording = false
	_generation += 1
	path_ids.clear()
	last_stats = {"enabled": enabled, "clusters_rebuilt": 0, "clusters_reused": 0,
		"support_vertices_checked": 0, "vertices_replayed": 0, "side_pairs_tested": 0,
		"remap_index_visits": 0, "geometry_ms": 0.0, "cache_entries": 0,
		"cache_payload_bytes": 0, "cache_evicted": 0}
	if not enabled:
		clear()
	else:
		for key in _entries.keys():
			if _generation - int(_entries[key].generation) > MAX_IDLE_BUILDS:
				_evict(key)
	_update_stats()


func set_paths(paths: Array[Path3D]) -> void:
	path_ids.clear()
	for path in paths:
		path_ids.append(path.get_instance_id())


func clear() -> void:
	_entries.clear()
	_bytes = 0
	recording = false
	_remaps.clear()
	_marks.clear()
	_update_stats()


func make_query(
	builder: RefCounted, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
	sockets: Array[Dictionary], cluster: Array, path_rows: Array,
	path_snap: Array, path_strip: Array, path_strip_length: Array,
	invert_faces: bool, has_shoulders: bool, has_sidewalks: bool
) -> Dictionary:
	if not enabled or path_ids.size() != path_rows.size():
		return {}
	var selected: Dictionary = {}
	var full_paths: Dictionary = {}
	for socket_index in cluster:
		var socket: Dictionary = sockets[socket_index]
		var path_id := int(socket.get("path_id", -1))
		var row_id := int(socket.get("row_idx", -1))
		if path_id < 0 or path_id >= path_rows.size() or row_id < 0 or row_id >= path_rows[path_id].size():
			return {}
		if not selected.has(path_id):
			selected[path_id] = {}
		# All current weld calls use focused stripping: anchor plus one neighbor.
		# Capture BOTH neighbors because choosing the neighbor reads their centers.
		for row in range(maxi(0, row_id - 1), mini(path_rows[path_id].size(), row_id + 2)):
			selected[path_id][row] = true
		if not bool(socket.get("is_endpoint", true)):
			# A midpoint weld can choose any adjacent edge pair along this path,
			# after preceding cluster mutations. The old winning pair is not enough.
			full_paths[path_id] = true
	for path_id in full_paths:
		for row in range(path_rows[path_id].size()):
			if not selected[path_id].has(row):
				# The long target-side scan reads only the two outer edge vertices
				# (and their UVs if chosen). Interior cross-section slots are used
				# only by the anchor/neighbor strip operations captured above.
				selected[path_id][row] = false
	var ids := PackedInt32Array()
	var local_ids: Dictionary = {}
	var positions := PackedVector3Array()
	var ups := PackedVector3Array()
	var texcoords := PackedVector2Array()
	var rows_support: Array = []
	for path_id in selected:
		var row_ids: Array = selected[path_id].keys()
		row_ids.sort()
		rows_support.append([path_ids[path_id],
			builder._resolve_path_snap_for_id(path_id, path_snap),
			builder._is_path_strip_enabled(path_id, path_strip),
			builder._resolve_path_strip_length(path_id, path_snap, path_strip_length)])
		for row_id in row_ids:
			var row: Dictionary = path_rows[path_id][row_id]
			var raw_edges: Array = row.get("row_edges", []).duplicate() if selected[path_id][row_id] else []
			raw_edges.append(row.get("row_a", -1))
			raw_edges.append(row.get("row_b", -1))
			var edges := PackedInt32Array()
			for raw_id in raw_edges:
				var id := int(raw_id)
				if id < 0 or id >= verts.size() or id >= normals.size() or id >= uvs.size():
					return {}
				if not local_ids.has(id):
					local_ids[id] = ids.size()
					ids.append(id)
					positions.append(verts[id])
					ups.append(normals[id])
					texcoords.append(uvs[id])
				edges.append(local_ids[id])
			rows_support.append([row_id, row.get("position", Vector3.ZERO), edges])
	var socket_support: Array = []
	for index in cluster:
		var socket: Dictionary = sockets[index]
		var edges := PackedInt32Array()
		for id in socket.get("row_edges", []):
			if not local_ids.has(int(id)):
				return {}
			edges.append(local_ids[int(id)])
		var a := int(socket.get("row_a", -1))
		var b := int(socket.get("row_b", -1))
		if not local_ids.has(a) or not local_ids.has(b):
			return {}
		socket_support.append([path_ids[socket.path_id], socket.row_idx,
			socket.get("position", Vector3.ZERO), socket.get("out_dir", Vector3.FORWARD),
			socket.get("width", 0.0), socket.get("weld_snap_distance", builder.endpoint_snap_distance),
			socket.get("is_endpoint", true), edges, local_ids[a], local_ids[b]])
	var input := var_to_bytes([[builder.sample_step, builder.endpoint_snap_distance,
		builder.strip_shoulder_sidewalk_at_intersections, builder.intersection_strip_length,
		invert_faces, has_shoulders, has_sidewalks], socket_support, rows_support, positions, ups, texcoords])
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(input)
	last_stats.support_vertices_checked += ids.size()
	return {"key": digest.finish().hex_encode(), "input": input, "ids": ids,
		"local_ids": local_ids, "positions": positions, "normals": ups, "uvs": texcoords,
		"vertex_start": verts.size()}


func start_recording(query: Dictionary) -> void:
	recording = not query.is_empty()
	_remaps.clear()
	_marks.clear()


func record_remap(from: int, to: int) -> void:
	if recording:
		_remaps.append(from)
		_remaps.append(to)


func record_mark(id: int) -> void:
	if recording:
		# Record requested marks even if a preceding cluster already marked them.
		_marks[id] = true


func store_patch(
	query: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, surfaces: Array, starts: PackedInt32Array
) -> void:
	recording = false
	if query.is_empty():
		return
	var ids: PackedInt32Array = query.ids
	var local_ids: Dictionary = query.local_ids
	var patches := PackedInt32Array()
	var positions := PackedVector3Array()
	var ups := PackedVector3Array()
	var texcoords := PackedVector2Array()
	for i in range(ids.size()):
		var id := ids[i]
		if verts[id] != query.positions[i] or normals[id] != query.normals[i] or uvs[id] != query.uvs[i]:
			patches.append(i)
			positions.append(verts[id])
			ups.append(normals[id])
			texcoords.append(uvs[id])
	var remaps := PackedInt32Array()
	for id in _remaps:
		if not local_ids.has(id):
			return
		remaps.append(local_ids[id])
	var marks := PackedInt32Array()
	for id in _marks:
		if not local_ids.has(id):
			return
		marks.append(local_ids[id])
	var appended: Array = []
	var index_count := 0
	for surface in range(surfaces.size()):
		var indices := PackedInt32Array()
		for id in surfaces[surface].slice(starts[surface]):
			if id >= query.vertex_start:
				indices.append(-1 - (id - int(query.vertex_start)))
			elif local_ids.has(id):
				indices.append(local_ids[id])
			else:
				return
		appended.append(indices)
		index_count += indices.size()
	var extra_vertices := verts.slice(query.vertex_start)
	var payload_bytes: int = query.input.size() + (patches.size() + extra_vertices.size()) * 32 + (patches.size() + remaps.size() + marks.size() + index_count) * 4
	if payload_bytes > MAX_PAYLOAD_BYTES:
		return
	if _entries.has(query.key):
		_evict(query.key)
	_entries[query.key] = {"input": query.input, "patches": patches,
		"positions": positions, "normals": ups, "uvs": texcoords,
		"remaps": remaps, "marks": marks, "indices": appended,
		"extra_vertices": extra_vertices, "extra_normals": normals.slice(query.vertex_start),
		"extra_uvs": uvs.slice(query.vertex_start), "generation": _generation, "bytes": payload_bytes}
	_bytes += payload_bytes
	while _entries.size() > MAX_ENTRIES or _bytes > MAX_PAYLOAD_BYTES:
		_evict(_entries.keys()[0])
	_update_stats()


func replay(
	query: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, surfaces: Array, marked: Dictionary
) -> bool:
	if query.is_empty() or not _entries.has(query.key):
		return false
	var entry: Dictionary = _entries[query.key]
	if entry.input != query.input:
		return false
	var ids: PackedInt32Array = query.ids
	for i in range(entry.patches.size()):
		var id := ids[entry.patches[i]]
		verts[id] = entry.positions[i]
		normals[id] = entry.normals[i]
		uvs[id] = entry.uvs[i]
	for id in entry.marks:
		marked[ids[id]] = true
	var substitutions := compose_remaps(entry.remaps, ids)
	if not substitutions.is_empty():
		# One dense lookup per index is cheaper than a Variant Dictionary lookup
		# per triangle corner. Include earlier fan centers as identity entries.
		var mapping := PackedInt32Array()
		mapping.resize(verts.size())
		for i in range(mapping.size()):
			mapping[i] = i
		for from in substitutions:
			mapping[from] = substitutions[from]
		for indices: PackedInt32Array in surfaces:
			last_stats.remap_index_visits += indices.size()
			for i in range(indices.size()):
				indices[i] = mapping[indices[i]]
	var vertex_start := verts.size()
	verts.append_array(entry.extra_vertices)
	normals.append_array(entry.extra_normals)
	uvs.append_array(entry.extra_uvs)
	for surface in range(surfaces.size()):
		for id in entry.indices[surface]:
			surfaces[surface].append(vertex_start - id - 1 if id < 0 else ids[id])
	last_stats.vertices_replayed += entry.patches.size() + entry.extra_vertices.size()
	entry.generation = _generation
	_entries.erase(query.key)
	_entries[query.key] = entry
	return true


func compose_remaps(remaps: PackedInt32Array, ids: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for i in range(0, remaps.size(), 2):
		var from := ids[remaps[i]]
		var to := ids[remaps[i + 1]]
		# Compose in original execution order. Never chase the result transitively:
		# B->C then A->B must leave raw A mapped to B, not to C.
		for key in result.keys():
			if result[key] == from:
				result[key] = to
		if not result.has(from):
			result[from] = to
	return result


func _evict(key: String) -> void:
	_bytes -= int(_entries[key].bytes)
	_entries.erase(key)
	last_stats.cache_evicted += 1


func _update_stats() -> void:
	last_stats["cache_entries"] = _entries.size()
	last_stats["cache_payload_bytes"] = _bytes
