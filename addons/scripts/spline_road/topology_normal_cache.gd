@tool
extends RefCounted
## Native smooth-group-zero normals with complete ordered dirty-vertex stars.
## SurfaceTool still computes normals; this helper only selects its input domain.
## Upstream contract: scene/resources/surface_tool.cpp, generate_normals() and
## SmoothGroupVertex (position + smoothing group). UVs do not affect smoothing.
const MAX_VERTICES := 393216
const MAX_SNAPSHOT_BYTES := 64 * 1024 * 1024

var stats: Dictionary = {}
var _input := PackedByteArray()
var _cells: Dictionary = {}
var _order: Array[Vector3i] = []
var _cell_size := 0.0
var _snapshot_bytes := 0


func clear() -> void:
	_input = PackedByteArray()
	_cells.clear()
	_order.clear()
	_snapshot_bytes = 0
	stats = {}


## A null surface denotes the native raw vertex/UV path. Full fallback builds
## it lazily; unchanged/local-normal jobs never materialize all source vertices.
func prepare(surface: SurfaceTool, arrays: Array, cell_size: float, partitioner: Callable) -> Dictionary:
	var started := Time.get_ticks_usec()
	stats = {"full_calls": 0, "patch_calls": 0, "vertices_reused": 0,
		"vertices_rebuilt": 0, "patch_triangles": 0, "snapshot_bytes": 0, "fallback": "", "source_surface_builds": 0}
	if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array \
		or arrays[Mesh.ARRAY_INDEX] != null:
		clear()
		stats = {"fallback": "unsupported_stream"}
		return {}
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if positions.is_empty() or positions.size() > MAX_VERTICES:
		clear()
		stats = {"fallback": "vertex_limit"}
		return {}
	var input := var_to_bytes([arrays, cell_size])
	if not _cells.is_empty() and input == _input:
		stats.vertices_reused = positions.size()
		stats.snapshot_bytes = _snapshot_bytes
		stats.normal_ms = float(Time.get_ticks_usec() - started) / 1000.0
		return _cells.duplicate(true)
	var partition: Dictionary = partitioner.call(arrays, cell_size, true)
	if partition.is_empty():
		clear()
		stats = {"fallback": "unsupported_partition"}
		return {}
	var cells: Dictionary = partition.cells
	var groups: Dictionary = partition.groups
	var order: Array[Vector3i] = []
	order.resize(positions.size() / 3)
	var changed: Dictionary = {}
	for cell: Vector2i in cells:
		var ids: Array = groups[cell]
		for i in range(0, ids.size(), 3):
			order[ids[i] / 3] = Vector3i(cell.x, cell.y, i / 3)
		if not _cells.has(cell) or var_to_bytes(cells[cell][Mesh.ARRAY_VERTEX]) != var_to_bytes(_cells[cell][Mesh.ARRAY_VERTEX]):
			changed[cell] = true
	for cell: Vector2i in _cells:
		if not cells.has(cell):
			changed[cell] = true
	var fallback := ""
	if _cells.is_empty() or _cell_size != cell_size:
		fallback = "cold_or_repartition"
	elif changed.size() * 2 > maxi(cells.size(), _cells.size()):
		fallback = "large_changed_domain"
	elif not _unchanged_order_matches(order, changed):
		# Native floating-point accumulation depends on relative triangle order.
		# Removing changed cells must leave the same common triangle subsequence.
		fallback = "unchanged_triangle_reordering"
	if fallback.is_empty():
		_patch(positions, cells, order, changed)
	else:
		if surface == null:
			surface = SurfaceTool.new()
			surface.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
			stats.source_surface_builds = 1
		_full(surface, cells, groups)
		stats.fallback = fallback
	_input = input
	_cells = cells.duplicate(true)
	_order = order
	_cell_size = cell_size
	var size := _snapshot_size()
	_snapshot_bytes = size
	stats.snapshot_bytes = size
	if size > MAX_SNAPSHOT_BYTES:
		_input = PackedByteArray()
		_cells.clear()
		_order.clear()
		_snapshot_bytes = 0
		stats.snapshot_bytes = 0
		stats.fallback = "snapshot_limit"
	stats.normal_ms = float(Time.get_ticks_usec() - started) / 1000.0
	return cells


func _snapshot_size() -> int:
	return _input.size() + var_to_bytes(_cells).size() + _order.size() * 12


func _unchanged_order_matches(order: Array[Vector3i], changed: Dictionary) -> bool:
	var cursor := 0
	for triangle: Vector3i in order:
		if changed.has(Vector2i(triangle.x, triangle.y)):
			continue
		while cursor < _order.size() and changed.has(Vector2i(_order[cursor].x, _order[cursor].y)):
			cursor += 1
		if cursor >= _order.size() or _order[cursor] != triangle:
			return false
		cursor += 1
	while cursor < _order.size() and changed.has(Vector2i(_order[cursor].x, _order[cursor].y)):
		cursor += 1
	return cursor == _order.size()


func _full(surface: SurfaceTool, cells: Dictionary, groups: Dictionary) -> void:
	surface.generate_normals()
	var all_normals: PackedVector3Array = surface.commit_to_arrays()[Mesh.ARRAY_NORMAL]
	stats.full_calls = 1
	stats.vertices_rebuilt = all_normals.size()
	for cell: Vector2i in cells:
		var ids: Array = groups[cell]
		var normals := PackedVector3Array()
		normals.resize(ids.size())
		for i in range(ids.size()):
			normals[i] = all_normals[ids[i]]
		cells[cell][Mesh.ARRAY_NORMAL] = normals


func _patch(positions: PackedVector3Array, cells: Dictionary, order: Array[Vector3i], changed: Dictionary) -> void:
	if changed.is_empty():
		for cell: Vector2i in cells:
			cells[cell][Mesh.ARRAY_NORMAL] = _cells[cell][Mesh.ARRAY_NORMAL]
		stats.vertices_reused = positions.size()
		return
	var dirty: Dictionary = {}
	for cell: Vector2i in changed:
		for source: Dictionary in [_cells, cells]:
			if source.has(cell):
				for point: Vector3 in source[cell][Mesh.ARRAY_VERTEX]:
					dirty[point] = true
	var patch_positions := PackedVector3Array()
	var affected_cells: Dictionary = {}
	for i in range(0, positions.size(), 3):
		if dirty.has(positions[i]) or dirty.has(positions[i + 1]) or dirty.has(positions[i + 2]):
			var triangle := order[i / 3]
			affected_cells[Vector2i(triangle.x, triangle.y)] = true
			patch_positions.append(positions[i])
			patch_positions.append(positions[i + 1])
			patch_positions.append(positions[i + 2])
	var rebuilt: Dictionary = {}
	if not patch_positions.is_empty():
		var patch := SurfaceTool.new()
		var patch_arrays: Array = []
		patch_arrays.resize(Mesh.ARRAY_MAX)
		patch_arrays[Mesh.ARRAY_VERTEX] = patch_positions
		patch.create_from_arrays(patch_arrays, Mesh.PRIMITIVE_TRIANGLES)
		patch.generate_normals()
		var normals: PackedVector3Array = patch.commit_to_arrays()[Mesh.ARRAY_NORMAL]
		for i in range(patch_positions.size()):
			if dirty.has(patch_positions[i]) and not rebuilt.has(patch_positions[i]):
				rebuilt[patch_positions[i]] = normals[i]
		stats.patch_calls = 1
		stats.patch_triangles = patch_positions.size() / 3
	for cell: Vector2i in cells:
		var points: PackedVector3Array = cells[cell][Mesh.ARRAY_VERTEX]
		if not affected_cells.has(cell):
			cells[cell][Mesh.ARRAY_NORMAL] = _cells[cell][Mesh.ARRAY_NORMAL]
			stats.vertices_reused += points.size()
			continue
		var normals: PackedVector3Array = _cells[cell][Mesh.ARRAY_NORMAL] if not changed.has(cell) else PackedVector3Array()
		if normals.size() != points.size():
			normals.resize(points.size())
		for i in range(points.size()):
			if dirty.has(points[i]):
				normals[i] = rebuilt[points[i]]
				stats.vertices_rebuilt += 1
			else:
				stats.vertices_reused += 1
		cells[cell][Mesh.ARRAY_NORMAL] = normals
