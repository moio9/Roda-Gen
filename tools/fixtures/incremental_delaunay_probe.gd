@tool
extends RefCounted
## Ordered Bowyer-Watson replay experiment, deliberately outside the addon.
## Exact parity passes, but measured GDScript replay is slower than native full
## triangulation. This is a test/reference implementation, not a runtime option.
## Algorithm/order follow Godot core/math/delaunay_2d.h:
## https://github.com/godotengine/godot/blob/master/core/math/delaunay_2d.h
##
## Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
## Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
## The above copyright notice and this permission notice shall be included in
## all copies or substantial portions of the Software.
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
## THE SOFTWARE.

var stats: Dictionary = {}
var _points := PackedVector2Array()
var _super := PackedVector2Array()
var _operations: Array = []
var _triangles: Dictionary = {}
var _cells: Dictionary = {}
var _large: Dictionary = {}
var _next_id := 0
var _cell_size := 1.0


func clear() -> void:
	_points.clear()
	_super.clear()
	_operations.clear()
	_triangles.clear()
	_cells.clear()
	_large.clear()
	_next_id = 0


func triangulate(points: PackedVector2Array) -> PackedInt32Array:
	stats = {"prefix_reused": 0, "insertions_reused": 0,
		"insertions_rebuilt": 0, "circle_tests": 0, "triangles_retained": 0}
	if points.size() < 3:
		clear()
		return PackedInt32Array()
	var rect := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		rect = rect.expand(p)
	var delta := maxf(rect.size.x, rect.size.y)
	var center := rect.get_center()
	var bounding := PackedVector2Array([
		Vector2(center.x - delta * 16, center.y - delta),
		Vector2(center.x, center.y + delta * 16),
		Vector2(center.x + delta * 16, center.y - delta)])
	if not is_finite(delta) or delta <= 0:
		clear()
		return Geometry2D.triangulate_delaunay(points)
	var prefix := 0
	var previous: Array = _operations.duplicate()
	var current_ids: Dictionary = {}
	var unique_points := true
	for i in range(points.size()):
		if current_ids.has(points[i]):
			unique_points = false
		current_ids[points[i]] = i
	var previous_by_point: Dictionary = {}
	if unique_points:
		for operation: Dictionary in previous:
			if previous_by_point.has(operation.point):
				unique_points = false
				break
			previous_by_point[operation.point] = operation
	if bounding == _super:
		while prefix < mini(points.size(), _points.size()) and points[prefix] == _points[prefix]:
			prefix += 1
		for i in range(_operations.size() - 1, prefix - 1, -1):
			var operation: Dictionary = _operations[i]
			for triangle: Dictionary in operation.created:
				_remove(triangle.id)
			for triangle: Dictionary in operation.removed:
				_insert(triangle)
			_next_id = operation.start_id
		_operations.resize(prefix)
	else:
		clear()
		previous.clear()
		previous_by_point.clear()
		_super = bounding
		_cell_size = maxf(0.001, delta / 32.0)
		_points = points.duplicate()
		_insert(_triangle(-1, -2, -3))
	_points = points.duplicate()
	stats.prefix_reused = prefix
	stats.triangles_retained = _triangles.size()
	for i in range(prefix, points.size()):
		var candidates: Array = _large.keys()
		var cell := _cell(points[i])
		if _cells.has(cell):
			candidates.append_array(_cells[cell].keys())
		candidates.sort()
		candidates.reverse()
		var removed: Array = []
		for id: int in candidates:
			var triangle: Dictionary = _triangles[id]
			stats.circle_tests += 1
			if points[i].distance_squared_to(triangle.center) < triangle.radius:
				removed.append(triangle)
				_remove(id)
		var operation := {"point": points[i], "removed": removed,
			"created": [], "start_id": _next_id}
		var old: Dictionary = previous_by_point.get(points[i], {}) if unique_points else (previous[i] if i < previous.size() else {})
		var remapped := _remap_created(old, current_ids, i) if unique_points else []
		if _same_cavity(old, points[i], removed, unique_points) and (not unique_points or remapped.size() == old.created.size()):
			stats.insertions_reused += 1
			for saved: Dictionary in (remapped if unique_points else old.created):
				var triangle := saved.duplicate()
				triangle.id = _next_id
				_next_id += 1
				operation.created.append(triangle)
				_insert(triangle)
		else:
			stats.insertions_rebuilt += 1
			var polygon: Array[Vector2i] = []
			var counts: Dictionary = {}
			for triangle: Dictionary in removed:
				var ids: Vector3i = triangle.vertices
				# Super vertices sort after real vertices, as in the native input.
				for edge: Vector2i in [Vector2i(ids.x, ids.y), Vector2i(ids.y, ids.z), Vector2i(ids.z, ids.x)]:
					edge = _ordered_edge(edge, points.size())
					polygon.append(edge)
					counts[edge] = int(counts.get(edge, 0)) + 1
			for edge: Vector2i in polygon:
				if counts[edge] == 1:
					var triangle := _triangle(edge.x, edge.y, i)
					operation.created.append(triangle)
					_insert(triangle)
		_operations.append(operation)
	var ordered: Array = _triangles.keys()
	ordered.sort()
	var result := PackedInt32Array()
	for id: int in ordered:
		var vertices: Vector3i = _triangles[id].vertices
		if vertices.x >= 0 and vertices.y >= 0 and vertices.z >= 0:
			result.append_array(PackedInt32Array([vertices.x, vertices.y, vertices.z]))
	return result


func _same_cavity(old: Dictionary, point: Vector2, removed: Array, remap: bool) -> bool:
	if old.is_empty() or old.point != point or old.removed.size() != removed.size():
		return false
	for i in range(removed.size()):
		var a: Dictionary = old.removed[i]
		var b: Dictionary = removed[i]
		if a.positions != b.positions or (not remap and a.vertices != b.vertices) or a.center != b.center or a.radius != b.radius:
			return false
	return true


func _remap_created(old: Dictionary, current_ids: Dictionary, point_id: int) -> Array:
	var result: Array = []
	for saved: Dictionary in old.get("created", []):
		var ids := PackedInt32Array()
		for position: Vector2 in saved.positions:
			if current_ids.has(position):
				ids.append(current_ids[position])
			else:
				var super_index := _super.find(position)
				if super_index < 0:
					return []
				ids.append(-super_index - 1)
		# Replay cannot change the native edge sorting or introduce a vertex
		# which has not been inserted at this step in the new point ordering.
		if ids[2] != point_id or ids[0] >= point_id or ids[1] >= point_id:
			return []
		var edge := Vector2i(ids[0], ids[1])
		if _ordered_edge(edge, current_ids.size()) != edge:
			return []
		var triangle := saved.duplicate()
		triangle.vertices = Vector3i(ids[0], ids[1], ids[2])
		result.append(triangle)
	return result


func _ordered_edge(edge: Vector2i, count: int) -> Vector2i:
	var a := edge.x if edge.x >= 0 else count - edge.x - 1
	var b := edge.y if edge.y >= 0 else count - edge.y - 1
	return edge if a <= b else Vector2i(edge.y, edge.x)


func _point(id: int) -> Vector2:
	return _points[id] if id >= 0 else _super[-id - 1]


func _triangle(a_id: int, b_id: int, c_id: int) -> Dictionary:
	var origin := _point(a_id)
	var a := _point(b_id) - origin
	var b := _point(c_id) - origin
	var offset := (b * a.length_squared() - a * b.length_squared()).orthogonal() / (a.cross(b) * 2.0)
	var result := {"id": _next_id, "vertices": Vector3i(a_id, b_id, c_id),
		"positions": PackedVector2Array([origin, _point(b_id), _point(c_id)]),
		"center": offset + origin, "radius": offset.length_squared()}
	_next_id += 1
	return result


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / _cell_size), floori(point.y / _cell_size))


func _insert(triangle: Dictionary) -> void:
	_triangles[triangle.id] = triangle
	var radius := sqrt(float(triangle.radius))
	# Non-finite circles remain candidates so the native strict comparison also
	# decides their behavior. Avoid float-to-int conversion of infinities.
	if not is_finite(radius) or not triangle.center.is_finite():
		_large[triangle.id] = true
		return
	# Inflate the spatial-only bounds against float rounding. The final circle
	# test is exactly the native strict float comparison, never the inflated box.
	radius += maxf(_cell_size * 0.00001, radius * 0.00001)
	var lower := _cell(triangle.center - Vector2(radius, radius))
	var upper := _cell(triangle.center + Vector2(radius, radius))
	if (upper.x - lower.x + 1) * (upper.y - lower.y + 1) > 64:
		_large[triangle.id] = true
		return
	for x in range(lower.x, upper.x + 1):
		for y in range(lower.y, upper.y + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				_cells[cell] = {}
			_cells[cell][triangle.id] = true
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
				if _cells[cell].is_empty():
					_cells.erase(cell)
	_triangles.erase(id)
