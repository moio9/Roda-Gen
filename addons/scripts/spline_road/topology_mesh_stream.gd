@tool
extends RefCounted
## Transient native vertex/UV stream for one main-thread mesh job. Complete
## cached blocks append in bulk; the SurfaceTool receives the exact same order.
## The caller supplies an empty, begun triangle SurfaceTool and routes every
## vertex through this stream until flush/fallback. Only UVs and default smooth
## groups are supported; custom emitters keep the original immediate-mode path.

const MAX_VERTICES := 393216
var target: SurfaceTool
var stats: Dictionary = {}
var _vertices := PackedVector3Array()
var _uvs := PackedVector2Array()


func begin(surface: SurfaceTool, enabled: bool) -> void:
	clear()
	target = surface if enabled else null
	stats = {"enabled": enabled, "vertices_buffered": 0, "vertices_bulk": 0,
		"bulk_blocks": 0, "flushes": 0, "capacity_fallback": false, "direct_arrays": false}


func clear() -> void:
	target = null
	_vertices = PackedVector3Array()
	_uvs = PackedVector2Array()
	stats = {}


func _vertex_limit() -> int:
	return MAX_VERTICES


func _reserve(surface: SurfaceTool, count: int) -> bool:
	if target == null or target != surface:
		return false
	if _vertices.size() + count > _vertex_limit():
		stats.capacity_fallback = true
		flush(true)
		return false
	return true


func append_vertex(surface: SurfaceTool, vertex: Vector3, uv: Vector2) -> bool:
	if not _reserve(surface, 1):
		return false
	_vertices.append(vertex)
	_uvs.append(uv)
	stats.vertices_buffered += 1
	return true


func append_block(surface: SurfaceTool, vertices: PackedVector3Array, uvs: PackedVector2Array) -> bool:
	if vertices.size() != uvs.size() or not _reserve(surface, vertices.size()):
		return false
	_vertices.append_array(vertices)
	_uvs.append_array(uvs)
	stats.vertices_buffered += vertices.size()
	stats.vertices_bulk += vertices.size()
	stats.bulk_blocks += 1
	return true


func append_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		a2: Vector2, b2: Vector2, c2: Vector2, flip: bool) -> bool:
	if not _reserve(surface, 3):
		return false
	if flip:
		_vertices.append(c)
		_vertices.append(b)
		_vertices.append(a)
		_uvs.append(c2)
		_uvs.append(b2)
		_uvs.append(a2)
	else:
		_vertices.append(a)
		_vertices.append(b)
		_vertices.append(c)
		_uvs.append(a2)
		_uvs.append(b2)
		_uvs.append(c2)
	stats.vertices_buffered += 3
	return true


func take_arrays(surface: SurfaceTool) -> Array:
	# Transfer only this job's complete raw stream. No SurfaceTool is populated;
	# the consumer can build one lazily if a full native normal pass is required.
	if target == null or target != surface or _vertices.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	target = null
	_vertices = PackedVector3Array()
	_uvs = PackedVector2Array()
	stats.flushes += 1
	stats.direct_arrays = true
	return arrays


func flush(for_continuation := false) -> void:
	if target != null and not _vertices.is_empty():
		if for_continuation:
			# create_from_arrays closes SurfaceTool's immediate-mode emission.
			# A capacity fallback must leave it begun for the remaining vertices.
			for i in range(_vertices.size()):
				target.set_uv(_uvs[i])
				target.add_vertex(_vertices[i])
		else:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = _vertices
			arrays[Mesh.ARRAY_TEX_UV] = _uvs
			target.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
		stats.flushes += 1
	target = null
	_vertices = PackedVector3Array()
	_uvs = PackedVector2Array()
