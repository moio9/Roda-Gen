@tool
extends RefCounted
## Value-only terrain stage results; no scene objects or persistent vertex IDs.
## Owned by the terrain builder (and its worker while generating).

const MAX_ENTRIES := 16384
const MAX_PAYLOAD_BYTES := 64 * 1024 * 1024
const MAX_IDLE_BUILDS := 2
const BLEND_ROWS := 32

var enabled := false
var stats: Dictionary = {}
var _entries: Dictionary = {}
var _build := 0
var _payload_bytes := 0
var _group_keys: Dictionary = {}
var _dependency_scopes: Array = []


func configure(use_cache: bool, clear_requested: bool) -> void:
	enabled = use_cache
	_build += 1
	stats = {"enabled": enabled, "queries_reused": 0, "queries_rebuilt": 0, "entries": 0,
		"payload_bytes": 0, "evicted": 0, "geometry_2d": {}}
	_dependency_scopes.clear()
	_group_keys.clear()
	if not enabled or clear_requested:
		clear()
	else:
		var max_idle := _max_idle_builds()
		for key in _entries.keys():
			if _build - int(_entries[key].build) > max_idle:
				_evict(key)
	_update_stats()


func clear() -> void:
	_entries.clear()
	_group_keys.clear()
	_dependency_scopes.clear()
	_payload_bytes = 0
	_update_stats()


func begin_group() -> void:
	_group_keys.clear()


func group_keys() -> PackedStringArray:
	return PackedStringArray(_group_keys.keys())


func begin_scope() -> void:
	_dependency_scopes.append({})


func end_scope() -> PackedStringArray:
	return PackedStringArray(_dependency_scopes.pop_back().keys())


func _record_key(key: String) -> void:
	_group_keys[key] = true
	for scope: Dictionary in _dependency_scopes:
		scope[key] = true


func touch_group(keys: PackedStringArray) -> void:
	# A whole-strip hit must keep its inner stage entries alive for a future edit.
	for key in keys:
		if _entries.has(key):
			_entries[key].build = _build
			_record_key(key)


func query(stage: String, inputs: Array) -> Dictionary:
	if not enabled:
		return {}
	var input := var_to_bytes([stage, inputs])
	return {"key": _query_key(input), "input": input}


func _query_key(input: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(input)
	return hash.finish().hex_encode()


func lookup(query_value: Dictionary) -> Dictionary:
	if query_value.is_empty():
		return {}
	var key: String = query_value.key
	_record_key(key)
	if _entries.has(key) and _entries[key].input == query_value.input:
		var entry: Dictionary = _entries[key]
		entry.build = _build
		_entries.erase(key)
		_entries[key] = entry
		touch_group(entry.get("children", PackedStringArray()))
		stats.queries_reused += 1
		return entry
	stats.queries_rebuilt += 1
	return {}


func store(query_value: Dictionary, result: Variant, children: PackedStringArray = PackedStringArray()) -> void:
	if query_value.is_empty():
		return
	var size: int = query_value.input.size() + var_to_bytes(result).size() + children.size() * 64
	if size > MAX_PAYLOAD_BYTES:
		return
	var key: String = query_value.key
	if _entries.has(key):
		_evict(key)
	_entries[key] = {"input": query_value.input, "result": result, "build": _build, "payload_bytes": size, "children": children}
	_payload_bytes += size
	_record_key(key)
	while _entries.size() > _entry_limit() or _payload_bytes > MAX_PAYLOAD_BYTES:
		_evict(_first_key(_entries))
	_update_stats()


func _entry_limit() -> int:
	return MAX_ENTRIES


func _max_idle_builds() -> int:
	return MAX_IDLE_BUILDS


func _first_key(values: Dictionary) -> String:
	# Dictionary iteration is insertion-ordered. Do not allocate/copy every key
	# just to evict one entry from a full cache; mutation happens after iteration.
	for key: String in values:
		return key
	return ""


func polygon_clip(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	return _geometry_2d("clip", a, b)


func polygon_offset(poly: PackedVector2Array, offset: float) -> Array:
	return _geometry_2d("offset", poly, offset)


func polygon_triangulate(poly: PackedVector2Array, delaunay: bool = false) -> PackedInt32Array:
	return _geometry_2d("delaunay" if delaunay else "triangulate", poly, null)


func _geometry_2d(operation: String, poly: PackedVector2Array, parameter: Variant) -> Variant:
	var query_value := query("geometry_2d/" + operation, [poly, parameter])
	var cached := lookup(query_value)
	var operations: Dictionary = stats.get("geometry_2d", {})
	var counters: Dictionary = operations.get(operation, {"reused": 0, "rebuilt": 0})
	operations[operation] = counters
	stats["geometry_2d"] = operations
	if not cached.is_empty():
		counters.reused += 1
		return _copy_geometry_result(cached.result)
	counters.rebuilt += 1
	var result: Variant
	match operation:
		"clip":
			result = Geometry2D.clip_polygons(poly, parameter)
		"offset":
			result = Geometry2D.offset_polygon(poly, parameter)
		"delaunay":
			result = Geometry2D.triangulate_delaunay(poly)
		_:
			result = Geometry2D.triangulate_polygon(poly)
	if enabled:
		store(query_value, _copy_geometry_result(result))
	return result


func _copy_geometry_result(result: Variant) -> Variant:
	# Downstream winding correction may reverse returned packed polygons.
	return result.duplicate(true) if result is Array else result.duplicate()


func _evict(key: String) -> void:
	_payload_bytes -= int(_entries[key].payload_bytes)
	_entries.erase(key)
	stats.evicted += 1


func _update_stats() -> void:
	stats["entries"] = _entries.size()
	stats["payload_bytes"] = _payload_bytes
