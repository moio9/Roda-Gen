@tool
extends RefCounted
## Complete native collar row blocks, including oriented vertex/UV input order.
## Persistent records contain only values; source tracing is synchronous.

const ROW_PAIRS := 8
const MAX_GROUPS := 4096
const MAX_VERTICES := 262144
const MAX_PAYLOAD_BYTES := 64 * 1024 * 1024
var enabled := false
var recording := false
var stats: Dictionary = {}
var _records: Dictionary = {}
var _payload_bytes := 0
var _pending: Dictionary = {}
var _vertices := PackedVector3Array()
var _points := PackedVector2Array()
var _uvs := PackedVector2Array()
var _edge_heights: Dictionary = {}
var _overflow := false


func configure(use_cache: bool, clear_requested: bool) -> void:
	if not use_cache or clear_requested:
		clear()
	enabled = use_cache
	stats = {"enabled": enabled, "groups_reused": 0, "groups_rebuilt": 0,
		"triangles_reused": 0, "triangles_rebuilt": 0, "uncertified": 0,
		"entries": _records.size(), "payload_bytes": _payload_bytes}
	stats.misses = {"absent": 0, "input": 0, "scope": 0, "edge_heights": 0}


func clear() -> void:
	enabled = false
	_records.clear()
	_payload_bytes = 0
	_reset_capture()
	stats = {}


func lookup(key: Vector2i, input: PackedByteArray, source: RefCounted, edge_lookup: Dictionary) -> Dictionary:
	if not enabled:
		return {}
	var old: Dictionary = _records.get(key, {})
	if old.is_empty() or not old.has("uvs"):
		stats.misses.absent += 1
		return {}
	if old.input != input:
		stats.misses.input += 1
		return {}
	if not source.validate_mesh_scope(old.scope):
		stats.misses.scope += 1
		return {}
	var current_heights: Array = []
	for point: Vector2i in old.edge_heights:
		current_heights.append(edge_lookup.get(point, null))
	# Numerical equality merges signed zero. Keep exact values just as the
	# source-query and triangle-group input snapshots do.
	if var_to_bytes(current_heights) != old.edge_bytes:
		stats.misses.edge_heights += 1
		return {}
	_records.erase(key)
	_records[key] = old
	stats.groups_reused += 1
	stats.triangles_reused += old.triangles
	return old.duplicate(true)


func begin(key: Vector2i, input: PackedByteArray, source: RefCounted) -> void:
	_reset_capture()
	if not enabled:
		return
	_pending = {"key": key, "input": input}
	recording = true
	stats.groups_rebuilt += 1
	source.begin_mesh_scope()


func capture_height(key: Vector2i, value: Variant) -> void:
	if not recording:
		return
	if _edge_heights.size() >= MAX_VERTICES and not _edge_heights.has(key):
		_overflow = true
		recording = false
		return
	_edge_heights[key] = value


func capture_vertex(vertex: Vector3, point: Vector2, uv: Variant = null) -> void:
	if not recording:
		return
	if _vertices.size() >= MAX_VERTICES:
		_overflow = true
		recording = false
		return
	_vertices.append(vertex)
	_points.append(point)
	_uvs.append(Vector2(point.x * 0.05, point.y * 0.05) if uv == null else uv)


func finish(triangles: int, source: RefCounted) -> void:
	if _pending.is_empty():
		return
	var scope: Dictionary = source.end_mesh_scope()
	stats.triangles_rebuilt += triangles
	if _overflow or scope.is_empty() or _vertices.size() != triangles * 3:
		stats.uncertified += 1
		_reset_capture()
		return
	var result := {"input": _pending.input, "vertices": _vertices, "points": _points, "uvs": _uvs,
		"scope": scope, "edge_heights": _edge_heights, "edge_bytes": var_to_bytes(_edge_heights.values()),
		"triangles": triangles, "bytes": 0}
	var size := var_to_bytes(result).size()
	if size > MAX_PAYLOAD_BYTES:
		stats.uncertified += 1
		_reset_capture()
		return
	var key: Vector2i = _pending.key
	if _records.has(key):
		_payload_bytes -= int(_records[key].bytes)
		_records.erase(key)
	while not _records.is_empty() and (_records.size() >= MAX_GROUPS or _payload_bytes + size > MAX_PAYLOAD_BYTES):
		var first: Variant
		for candidate: Vector2i in _records:
			first = candidate
			break
		_payload_bytes -= int(_records[first].bytes)
		_records.erase(first)
	result.bytes = size
	_records[key] = result.duplicate(true)
	_payload_bytes += size
	stats.entries = _records.size()
	stats.payload_bytes = _payload_bytes
	_reset_capture()


func _reset_capture() -> void:
	recording = false
	_pending = {}
	_vertices = PackedVector3Array()
	_points = PackedVector2Array()
	_uvs = PackedVector2Array()
	_edge_heights = {}
	_overflow = false
