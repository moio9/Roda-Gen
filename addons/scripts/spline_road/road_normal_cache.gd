@tool
extends RefCounted
## Indexed-surface normals. Retain native triangle accumulation order per vertex;
## a topology change rebuilds the adjacency instead of guessing index identity.
const MAX_VERTICES := 131072
const MAX_TRIANGLES := 262144
const MAX_BYTES := 12 * 1024 * 1024
var stats: Dictionary = {}
var _indices := PackedInt32Array()
var _vertex_words := PackedInt32Array()
var _fallback_words := PackedInt32Array()
var _offsets := PackedInt32Array()
var _incident := PackedInt32Array()
var _faces := PackedVector3Array()
var _normals := PackedVector3Array()
var _topology_waiting := false
var _topology_count := 0


func clear() -> void:
	_indices = PackedInt32Array()
	_vertex_words = PackedInt32Array()
	_fallback_words = PackedInt32Array()
	_offsets = PackedInt32Array()
	_incident = PackedInt32Array()
	_faces = PackedVector3Array()
	_normals = PackedVector3Array()
	_topology_waiting = false
	_topology_count = 0


func compute(vertices: PackedVector3Array, indices: PackedInt32Array,
		fallback: PackedVector3Array, native: Callable) -> PackedVector3Array:
	var count := vertices.size()
	var triangles := indices.size() / 3
	stats = {"full_calls": 0, "patch_calls": 0, "vertices_rebuilt": 0,
		"vertices_reused": 0, "triangles_rebuilt": 0, "payload_bytes": 0, "fallback": ""}
	if count > MAX_VERTICES or triangles > MAX_TRIANGLES or count * 40 + triangles * 24 + indices.size() * 4 + 4 > MAX_BYTES:
		return _full(vertices, indices, fallback, native, false, "capacity")
	var words := vertices.to_byte_array().to_int32_array()
	if words.size() != count * 3:
		return _full(vertices, indices, fallback, native, false, "precision")
	if _normals.size() != count or _offsets.size() != count + 1 or _indices != indices:
		# Consecutively changing topology cannot amortize rebuilding adjacency.
		# After an existing layout changes, require it to repeat before seeding.
		if (not _offsets.is_empty() or _topology_waiting) \
				and not (_topology_waiting and _topology_count == count and _indices == indices):
			var result := _full(vertices, indices, fallback, native, false, "topology_warmup")
			_indices = indices.duplicate()
			_topology_waiting = true
			_topology_count = count
			stats.payload_bytes = _payload_bytes()
			return result
		return _full(vertices, indices, fallback, native, true, "topology")
	var fallback_words := fallback.to_byte_array().to_int32_array() if fallback.size() == count else PackedInt32Array()
	var dirty_faces: Dictionary = {}
	var dirty_vertices: Dictionary = {}
	for block_start in range(0, count, 256):
		var block_end := mini(count, block_start + 256)
		if words.slice(block_start * 3, block_end * 3) == _vertex_words.slice(block_start * 3, block_end * 3) \
				and fallback_words.size() == _fallback_words.size() \
				and fallback_words.slice(block_start * 3, block_end * 3) == _fallback_words.slice(block_start * 3, block_end * 3):
			continue
		for vertex in range(block_start, block_end):
			var position_changed := _different(words, _vertex_words, vertex)
			var fallback_changed := _different(fallback_words, _fallback_words, vertex)
			if not position_changed and not fallback_changed:
				continue
			if not vertices[vertex].is_finite() or (fallback.size() == count and not fallback[vertex].is_finite()):
				return _full(vertices, indices, fallback, native, false, "nonfinite")
			if fallback_changed:
				dirty_vertices[vertex] = true
			if position_changed:
				for slot in range(_offsets[vertex], _offsets[vertex + 1]):
					dirty_faces[_incident[slot]] = true
	for triangle: int in dirty_faces:
		var base := triangle * 3
		var a := indices[base]
		var b := indices[base + 1]
		var c := indices[base + 2]
		var face := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if not face.is_finite():
			return _full(vertices, indices, fallback, native, false, "nonfinite")
		_faces[triangle] = face
		dirty_vertices[a] = true
		dirty_vertices[b] = true
		dirty_vertices[c] = true
	for vertex: int in dirty_vertices:
		var normal := Vector3.ZERO
		for slot in range(_offsets[vertex], _offsets[vertex + 1]):
			var face := _faces[_incident[slot]]
			if face.length_squared() > 0.000000000001:
				normal += face
		if normal.length_squared() > 0.000000000001:
			_normals[vertex] = normal.normalized()
		elif fallback.size() == count and fallback[vertex].length_squared() > 0.000000000001:
			_normals[vertex] = fallback[vertex].normalized()
		else:
			_normals[vertex] = Vector3.UP
	_vertex_words = words
	_fallback_words = fallback_words
	stats.patch_calls = 1
	stats.vertices_rebuilt = dirty_vertices.size()
	stats.vertices_reused = count - dirty_vertices.size()
	stats.triangles_rebuilt = dirty_faces.size()
	stats.payload_bytes = _payload_bytes()
	# The caller flips upward normals in place; never expose the retained array.
	return _normals.duplicate()


func _different(a: PackedInt32Array, b: PackedInt32Array, vertex: int) -> bool:
	if a.size() != b.size():
		return true
	if a.is_empty():
		return false
	var base := vertex * 3
	return a[base] != b[base] or a[base + 1] != b[base + 1] or a[base + 2] != b[base + 2]


func _full(vertices: PackedVector3Array, indices: PackedInt32Array,
		fallback: PackedVector3Array, native: Callable, retain: bool, reason: String) -> PackedVector3Array:
	clear()
	var result: PackedVector3Array = native.call(vertices, indices, fallback)
	stats.full_calls = 1
	stats.vertices_rebuilt = vertices.size()
	stats.triangles_rebuilt = indices.size() / 3
	stats.fallback = reason
	if not retain:
		return result
	for vertex: Vector3 in vertices:
		if not vertex.is_finite():
			stats.fallback = "nonfinite"
			return result
	if fallback.size() == vertices.size():
		for normal: Vector3 in fallback:
			if not normal.is_finite():
				stats.fallback = "nonfinite"
				return result
	var count := vertices.size()
	_offsets.resize(count + 1)
	_offsets.fill(0)
	_faces.resize(indices.size() / 3)
	_faces.fill(Vector3.ZERO)
	for triangle in range(_faces.size()):
		var base := triangle * 3
		var a := indices[base]
		var b := indices[base + 1]
		var c := indices[base + 2]
		if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= count:
			continue
		var face := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if not face.is_finite():
			clear()
			stats.fallback = "nonfinite"
			return result
		_faces[triangle] = face
		for vertex in [a, b, c]:
			_offsets[vertex + 1] += 1
	for vertex in range(count):
		_offsets[vertex + 1] += _offsets[vertex]
	_incident.resize(_offsets[count])
	var cursor := _offsets.duplicate()
	for triangle in range(_faces.size()):
		var base := triangle * 3
		var a := indices[base]
		var b := indices[base + 1]
		var c := indices[base + 2]
		if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= count:
			continue
		for vertex in [a, b, c]:
			_incident[cursor[vertex]] = triangle
			cursor[vertex] += 1
	_indices = indices.duplicate()
	_vertex_words = vertices.to_byte_array().to_int32_array()
	_fallback_words = fallback.to_byte_array().to_int32_array() if fallback.size() == count else PackedInt32Array()
	_normals = result.duplicate()
	stats.payload_bytes = _payload_bytes()
	return result


func _payload_bytes() -> int:
	return (_indices.size() + _vertex_words.size() + _fallback_words.size() + _offsets.size() + _incident.size()) * 4 \
		+ (_faces.size() + _normals.size()) * 12
