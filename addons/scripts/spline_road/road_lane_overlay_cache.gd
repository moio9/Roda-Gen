@tool
extends RefCounted
## Retained pre-index lane rows. Final surface order and seam normals stay native.
const SOURCE = preload("./road_source_cache.gd")
const BLOCK_ROWS := 64
const MAX_ENTRIES := 4096
const MAX_BYTES := 32 * 1024 * 1024
var cache_enabled := true
var last_stats: Dictionary = {}
var _source := SOURCE.new()
var mesh_builder := preload("./road_mesh_builder.gd").new()
var _road: Node3D
var _entries: Dictionary = {}
var _next: Dictionary = {}
var _bytes := 0
var _enabled := false
var _started := 0


func begin(road: Node3D) -> void:
	_started = Time.get_ticks_usec()
	_road = road
	_enabled = road.incremental_generation_enabled and cache_enabled
	_source.begin_build(road)
	mesh_builder.configure(road)
	mesh_builder.normal_cache_stats.clear()
	_next = {}
	_bytes = 0
	if not _enabled:
		_entries.clear()
	last_stats = {"enabled": _enabled, "blocks_reused": 0, "blocks_rebuilt": 0,
		"rows_reused": 0, "rows_rebuilt": 0, "paths_bypassed": 0,
		"entries": 0, "payload_bytes": 0, "capacity_bypasses": 0, "dependency_rows_checked": 0}


func finish() -> void:
	_entries = _next
	_next = {}
	last_stats.entries = _entries.size()
	last_stats.payload_bytes = _bytes
	last_stats.build_ms = float(Time.get_ticks_usec() - _started) / 1000.0
	last_stats.normals = mesh_builder.normal_cache_stats.duplicate(true)
	if mesh_builder.normal_cache_stats.is_empty():
		mesh_builder.clear_incremental_cache()
	_source.end_build()


func clear() -> void:
	_entries.clear()
	_next.clear()
	_source.clear()
	mesh_builder.clear_incremental_cache()
	last_stats = {}


func rows(path: Path3D, inv_global: Transform3D, left_side: bool, lane: int,
		distances: PackedFloat32Array, length: float) -> Dictionary:
	if not _enabled or not _source.can_cache(path):
		last_stats.paths_bypassed += 1
		last_stats.rows_rebuilt += distances.size()
		return _road._build_lane_material_rows_native(path, inv_global, left_side, lane, distances, length)
	var result := _empty()
	var path_input := var_to_bytes([inv_global, left_side, lane, _road.lane_material_overlay_lift,
		_source.path_key(path, distances, inv_global * path.global_transform)])
	for start in range(0, distances.size(), BLOCK_ROWS):
		var block := distances.slice(start, mini(start + BLOCK_ROWS, distances.size()))
		var key := "%d:%d:%d:%d" % [path.get_instance_id(), int(left_side), lane, start]
		var old: Dictionary = _entries.get(key, {})
		# The frame API clamps distance before sampling. Width/layout APIs receive
		# the original float32 sample; preserve both semantics in the exact key.
		var input: PackedByteArray
		if old.get("path_input", PackedByteArray()) == path_input:
			input = old.input
		else:
			var frame_distances: Array = []
			var widths: Array = []
			for distance in block:
				frame_distances.append(clampf(float(distance), 0.0, length))
				var extents: Vector2 = _road._resolve_path_lane_extents(path, distance, length)
				var extent := extents.x if left_side else extents.y
				widths.append([extent, _road._resolve_lane_material_width(path, distance, extent)])
			input = var_to_bytes([inv_global, left_side, lane, block, widths,
				_road.lane_material_overlay_lift,
				_source.block_key(path, frame_distances, inv_global * path.global_transform)])
			last_stats.dependency_rows_checked += block.size()
		var data: Dictionary
		if old.get("input", PackedByteArray()) == input:
			data = old.data
			last_stats.blocks_reused += 1
			last_stats.rows_reused += block.size()
		else:
			data = _road._build_lane_material_rows_native(path, inv_global, left_side, lane, block, length)
			last_stats.blocks_rebuilt += 1
			last_stats.rows_rebuilt += block.size()
		for field in result:
			result[field].append_array(data[field])
		var bytes: int = path_input.size() + input.size() + data.vertices.size() * 32 + data.widths.size() * 8 + 512
		if _next.size() < _entry_limit() and _bytes + bytes <= _byte_limit():
			_next[key] = {"path_input": path_input, "input": input, "data": data}
			_bytes += bytes
		else:
			last_stats.capacity_bypasses += 1
	return result


func _empty() -> Dictionary:
	return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
		"uvs": PackedVector2Array(), "widths": PackedFloat64Array()}


func _entry_limit() -> int:
	return MAX_ENTRIES


func _byte_limit() -> int:
	return MAX_BYTES
