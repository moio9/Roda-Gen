@tool
extends RefCounted
## Value-only filtered/height-fitted triangles. Groups are spatial, but callers
## consume and record their slots in the original global triangle order. No
## native work is performed early and no node, resource or callback is retained.

const CELL_SIZE := 32.0
const GROUP_TRIANGLES := 64
const MAX_GROUPS := 4096
const MAX_TRIANGLES := 262144
const MAX_PAYLOAD_BYTES := 64 * 1024 * 1024
var _records: Dictionary = {}
var _payload_bytes := 0
var stats: Dictionary = {}


func configure(enabled: bool, clear_requested: bool) -> void:
	if not enabled or clear_requested:
		clear()
	stats = {"enabled": enabled, "groups_reused": 0, "groups_rebuilt": 0,
		"triangles_reused": 0, "triangles_rebuilt": 0, "uncertified": 0,
		"runs_reused": 0, "candidates_bulk": 0, "emission_triangles_reused": 0,
		"entries": _records.size(), "payload_bytes": _payload_bytes, "fallback": ""}
	stats.misses = {"absent": 0, "input": 0, "scope": 0}


func clear() -> void:
	_records.clear()
	_payload_bytes = 0
	stats = {}


func prepare(points: PackedVector2Array, indices: PackedInt32Array) -> Dictionary:
	if not stats.get("enabled", false):
		return {}
	if indices.size() % 3 != 0 or indices.size() / 3 > MAX_TRIANGLES:
		stats.fallback = "triangle_limit_or_invalid_stream"
		return {}
	var groups: Array[Dictionary] = []
	var current: Dictionary = {}
	var group_ids := PackedInt32Array()
	var slots := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var triangle := PackedVector2Array()
		for j in range(3):
			var id := indices[i + j]
			if id < 0 or id >= points.size() or not points[id].is_finite():
				stats.fallback = "invalid_point"
				return {}
			triangle.append(points[id])
		var center := (triangle[0] + triangle[1] + triangle[2]) / 3.0
		var cell := Vector2i(floori(center.x / CELL_SIZE), floori(center.y / CELL_SIZE))
		var group_id: int = current.get(cell, -1)
		var ordinal := 0
		if group_id >= 0:
			ordinal = groups[group_id].key.z
			if groups[group_id].points.size() == GROUP_TRIANGLES * 3:
				group_id = -1
				ordinal += 1
		if group_id < 0:
			if groups.size() >= MAX_GROUPS:
				stats.fallback = "group_limit"
				return {}
			group_id = groups.size()
			groups.append({"key": Vector3i(cell.x, cell.y, ordinal), "points": PackedVector2Array()})
			current[cell] = group_id
		var raw: PackedVector2Array = groups[group_id].points
		group_ids.append(group_id)
		slots.append(raw.size() / 3)
		raw.append_array(triangle)
		groups[group_id].points = raw
	# Consecutive runs preserve global order even when spatial groups interleave.
	# Exclusive ends let the caller stop at its existing per-frame candidate cap.
	var ends := PackedInt32Array()
	ends.resize(group_ids.size())
	for i in range(group_ids.size() - 1, -1, -1):
		ends[i] = ends[i + 1] if i + 1 < group_ids.size() and group_ids[i] == group_ids[i + 1] else i + 1
	return {"groups": groups, "ids": group_ids, "slots": slots, "ends": ends}


func resolve(group: Dictionary, settings: PackedByteArray, edge_heights: Array, source: RefCounted) -> void:
	if group.has("hit"):
		return
	var input := var_to_bytes([group.points, settings, edge_heights])
	var old: Dictionary = _records.get(group.key, {})
	if not old.is_empty() and old.input == input and source.validate_mesh_scope(old.scope):
		group.merge(old.duplicate(true))
		group.hit = true
		_records.erase(group.key)
		_records[group.key] = old
		stats.groups_reused += 1
		return
	stats.misses["absent" if old.is_empty() else ("input" if old.input != input else "scope")] += 1
	group.hit = false
	group.input = input
	group.scope = {}
	var accepted := PackedByteArray()
	accepted.resize(group.points.size() / 3)
	group.accepted = accepted
	var reasons := PackedStringArray()
	reasons.resize(accepted.size())
	group.reasons = reasons
	var vertices := PackedVector3Array()
	vertices.resize(group.points.size())
	group.vertices = vertices
	stats.groups_rebuilt += 1


func record(group: Dictionary, slot: int, accepted: bool, reason: String,
		a: Vector3, b: Vector3, c: Vector3, source: RefCounted, inverted := false) -> void:
	group.accepted[slot] = int(accepted)
	group.reasons[slot] = reason
	group.vertices[slot * 3] = a
	group.vertices[slot * 3 + 1] = b
	group.vertices[slot * 3 + 2] = c
	stats.triangles_rebuilt += 1
	if slot + 1 < group.accepted.size():
		group.scope = source.pause_mesh_scope()
		return
	group.scope = source.end_mesh_scope()
	if group.scope.is_empty():
		stats.uncertified += 1
		return
	var record := {"input": group.input, "scope": group.scope, "accepted": group.accepted,
		"reasons": group.reasons, "vertices": group.vertices, "emission": _pack_emission(group, inverted), "bytes": 0}
	var size := var_to_bytes(record).size()
	if size > MAX_PAYLOAD_BYTES:
		stats.uncertified += 1
		return
	if _records.has(group.key):
		_payload_bytes -= int(_records[group.key].bytes)
		_records.erase(group.key)
	while not _records.is_empty() and (_records.size() >= MAX_GROUPS or _payload_bytes + size > MAX_PAYLOAD_BYTES):
		var first: Variant
		for key: Vector3i in _records:
			first = key
			break
		_payload_bytes -= int(_records[first].bytes)
		_records.erase(first)
	record.bytes = size
	_records[group.key] = record.duplicate(true)
	_payload_bytes += size
	stats.entries = _records.size()
	stats.payload_bytes = _payload_bytes


func _pack_emission(group: Dictionary, inverted: bool) -> Dictionary:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var offsets := PackedInt32Array([0])
	var winding := PackedInt32Array([0])
	var last_rejected := PackedInt32Array([-1])
	var reasons: Dictionary = {}
	var count: int = group.accepted.size()
	for reason: String in group.reasons:
		if not reason.is_empty() and not reasons.has(reason):
			var prefix := PackedInt32Array()
			prefix.resize(count + 1)
			reasons[reason] = prefix
	for slot in range(count):
		var fixes := 0
		var reason := ""
		if group.accepted[slot] != 0:
			var a: Vector3 = group.vertices[slot * 3]
			var b: Vector3 = group.vertices[slot * 3 + 1]
			var c: Vector3 = group.vertices[slot * 3 + 2]
			var flip := (b - a).cross(c - a).y < 0.0
			fixes = int(flip)
			if inverted:
				flip = not flip
			for corner in range(3):
				var index := slot * 3 + (2 - corner if flip else corner)
				vertices.append(group.vertices[index])
				var point: Vector2 = group.points[index]
				uvs.append(Vector2(point.x * 0.05, point.y * 0.05))
		else:
			reason = group.reasons[slot]
		offsets.append(vertices.size())
		winding.append(winding[-1] + fixes)
		last_rejected.append(slot if not reason.is_empty() else last_rejected[-1])
		for key: String in reasons:
			reasons[key][slot + 1] = reasons[key][slot] + int(key == reason)
	return {"vertices": vertices, "uvs": uvs, "offsets": offsets, "winding": winding,
		"reasons": reasons, "last_rejected": last_rejected, "inverted": inverted}


func emit_run(group: Dictionary, first: int, count: int, inverted: bool,
		stream: RefCounted, surface: SurfaceTool) -> Dictionary:
	# No new dependencies are queried here: resolve already certified the entire
	# group. Old pre-emission records and unavailable/overflowed streams fall back.
	if not group.get("hit", false) or not group.has("emission") or count <= 0 or first < 0:
		return {}
	var emission: Dictionary = group.emission
	var end := first + count
	if emission.inverted != inverted or end >= emission.offsets.size():
		return {}
	var start_vertex: int = emission.offsets[first]
	var end_vertex: int = emission.offsets[end]
	if not stream.append_block(surface, emission.vertices.slice(start_vertex, end_vertex), emission.uvs.slice(start_vertex, end_vertex)):
		return {}
	var rejections: Dictionary = {}
	for reason: String in emission.reasons:
		var rejected: int = emission.reasons[reason][end] - emission.reasons[reason][first]
		if rejected > 0:
			rejections[reason] = rejected
	var last: int = emission.last_rejected[end]
	var triangles := (end_vertex - start_vertex) / 3
	stats.triangles_reused += count
	stats.runs_reused += 1
	stats.candidates_bulk += count
	stats.emission_triangles_reused += triangles
	return {"triangles": triangles, "winding": emission.winding[end] - emission.winding[first],
		"rejections": rejections, "last_reason": group.reasons[last] if last >= first else ""}
