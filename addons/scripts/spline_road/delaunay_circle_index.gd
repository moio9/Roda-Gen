@tool
extends RefCounted
## Bounded, value-only circle support. No scene references or renderer state.
const MAX_CELL_LINKS := 262144
var _triangles: Dictionary = {}
var _cells: Dictionary = {}
var _large: Dictionary = {}
var _cell_size := 1.0
var _links := 0

func clear() -> void:
	_triangles.clear()
	_cells.clear()
	_large.clear()
	_links = 0

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / _cell_size), floori(point.y / _cell_size))

func _insert(triangle: Dictionary) -> void:
	_triangles[triangle.id] = triangle
	var radius := sqrt(float(triangle.radius))
	# Almost-collinear circumcircles must not overflow int32 cell coordinates.
	if not is_finite(radius) or not triangle.center.is_finite() or radius > _cell_size * 4.0 or maxf(absf(triangle.center.x), absf(triangle.center.y)) / _cell_size > 1e9:
		_large[triangle.id] = true
		return
	radius += maxf(_cell_size * 0.00001, radius * 0.00001)
	var lower := _cell(triangle.center - Vector2(radius, radius))
	var upper := _cell(triangle.center + Vector2(radius, radius))
	var count := (upper.x - lower.x + 1) * (upper.y - lower.y + 1)
	if count > 64 or _links + count > MAX_CELL_LINKS:
		_large[triangle.id] = true
		return
	for x in range(lower.x, upper.x + 1):
		for y in range(lower.y, upper.y + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				_cells[cell] = {}
			_cells[cell][triangle.id] = true
	_links += count
	triangle["bounds"] = Vector4i(lower.x, lower.y, upper.x, upper.y)

func _remove(id: int) -> void:
	var triangle: Dictionary = _triangles[id]
	if _large.has(id):
		_large.erase(id)
	else:
		var bounds: Vector4i = triangle.bounds
		for x in range(bounds.x, bounds.z + 1):
			for y in range(bounds.y, bounds.w + 1):
				var cell := Vector2i(x, y)
				_cells[cell].erase(id)
				_links -= 1
				if _cells[cell].is_empty():
					_cells.erase(cell)
	_triangles.erase(id)
