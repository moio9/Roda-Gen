@tool
extends RefCounted
## Opt-in native cavity triangulation. Main-thread value-only retained support.
## Output triangle order can differ from the native full call.

const CIRCLES = preload("./delaunay_circle_index.gd")
const GEOMETRY = preload("./delaunay_geometry.gd")
const MAX_POINTS := 16384
const MAX_TRIANGLES := 32768
var stats: Dictionary = {}
var _index := CIRCLES.new()
var _points: Dictionary = {}
var _ids: Dictionary = {}
var _positions: Dictionary = {}
var _by_point: Dictionary = {}
var _hull := PackedVector2Array()
var _next_point := 0
var _next_triangle := 0
var _point_cells: Dictionary = {}
var _current: Dictionary = {}
var condition_native := false
var _origin := Vector2.ZERO
var _input := PackedVector2Array()
var _snapshot_centered := false
var _defer_full := false
var expand_external_ties := true # Test override for the previous strict fallback.


func clear() -> void:
	_index.clear()
	_points.clear()
	_ids.clear()
	_positions.clear()
	_by_point.clear()
	_hull.clear()
	_point_cells.clear()
	_current.clear()
	_next_point = 0
	_next_triangle = 0
	_input.clear()
	_origin = Vector2.ZERO


func matches(points: PackedVector2Array, centered: bool) -> bool:
	return not _input.is_empty() and _input == points and _snapshot_centered == centered


func try_patch(points: PackedVector2Array, centered: bool) -> Dictionary:
	condition_native = centered
	_defer_full = true
	var indices := triangulate(points)
	_defer_full = false
	return {"indices": indices} if stats.fallback.is_empty() else {}


func triangulate(points: PackedVector2Array) -> PackedInt32Array:
	stats = {"full_calls": 0, "local_calls": 0, "triangles_reused": 0,
		"triangles_rebuilt": 0, "patch_points": 0, "expansions": 0, "ambiguous_circles": 0,
		"external_ties": 0, "fallback": ""}
	if points.size() > MAX_POINTS:
		return _full(points, "capacity")
	_current = {}
	for i in range(points.size()):
		if _current.has(points[i]) or not points[i].is_finite():
			return _full(points, "duplicate_or_nonfinite")
		_current[points[i]] = i
	if _points.is_empty() or points.size() < 3:
		return _full(points, "cold")
	if condition_native != _snapshot_centered or _calculation_origin(points) != _origin:
		return _full(points, "conditioning_changed")
	var previous_order := -1
	for p: Vector2 in _current:
		if _points.has(p):
			if int(_points[p]) <= previous_order:
				return _full(points, "reordered_points")
			previous_order = _points[p]
	var added: Array[Vector2] = []
	var removed: Array[Vector2] = []
	for p: Vector2 in _current:
		if not _points.has(p):
			added.append(p)
	for p: Vector2 in _points:
		if not _current.has(p):
			removed.append(p)
	if added.is_empty() and removed.is_empty():
		stats.triangles_reused = _index._triangles.size()
		return _output()
	for p: Vector2 in removed:
		if _hull.has(p):
			return _full(points, "removed_hull")
	for p: Vector2 in added:
		if not Geometry2D.is_point_in_polygon(p, _hull):
			return _full(points, "expanded_hull")
	var cavity: Dictionary = {}
	for p: Vector2 in removed:
		for id: int in _by_point.get(p, {}):
			cavity[id] = true
	for p: Vector2 in added:
		var candidates: Array = _index._large.keys()
		candidates.append_array(_index._cells.get(_index._cell(p), {}).keys())
		for id: int in candidates:
			var tri: Dictionary = _index._triangles[id]
			if p.distance_squared_to(tri.center) <= tri.radius + _epsilon(tri.radius):
				cavity[id] = true
		_ids[p] = _next_point
		_positions[_next_point] = p
		_next_point += 1
	_point_cells.clear()
	for p: Vector2 in _current:
		var cell: Vector2i = _index._cell(p)
		if not _point_cells.has(cell):
			_point_cells[cell] = []
		_point_cells[cell].append(p)
	for attempt in range(8):
		var patch := _patch(cavity, added)
		if patch.has("failure"):
			return _full(points, patch.failure)
		var violations: Dictionary = patch.violations
		if violations.is_empty():
			if _index._triangles.size() - cavity.size() + patch.triangles.size() > MAX_TRIANGLES:
				return _full(points, "capacity")
			stats.triangles_reused = _index._triangles.size() - cavity.size()
			stats.triangles_rebuilt = patch.triangles.size()
			for id: int in cavity:
				_remove(id)
			for tri: Dictionary in patch.triangles:
				_add(tri)
			for p: Vector2 in removed:
				_positions.erase(_ids[p])
				_ids.erase(p)
			_points = _current.duplicate()
			_input = points.duplicate()
			return _output()
		var before := cavity.size()
		for p: Vector2 in violations:
			for id: int in _by_point.get(p, {}):
				cavity[id] = true
		if cavity.size() == before:
			return _full(points, "uncertified_circle")
		stats.expansions += 1
	return _full(points, "expansion_limit")


func _patch(cavity: Dictionary, added: Array[Vector2]) -> Dictionary:
	var edges: Dictionary = {}
	var vertices: Dictionary = {}
	for id: int in cavity:
		var tri: Dictionary = _index._triangles[id]
		var ids: Vector3i = tri.vertices
		for p_id: int in [ids.x, ids.y, ids.z]:
			if _current.has(_positions[p_id]):
				vertices[p_id] = true
		for edge: Vector2i in _edges(ids):
			edges[edge] = int(edges.get(edge, 0)) + 1
	var boundary: Dictionary = {}
	var adjacent: Dictionary = {}
	for edge: Vector2i in edges:
		if edges[edge] == 1:
			boundary[edge] = true
			for pair: Vector2i in [edge, Vector2i(edge.y, edge.x)]:
				if not adjacent.has(pair.x):
					adjacent[pair.x] = []
				adjacent[pair.x].append(pair.y)
	var boundary_expansion: Dictionary = {}
	for p: int in adjacent:
		if adjacent[p].size() != 2 or not vertices.has(p):
			boundary_expansion[_positions[p]] = true
	if not boundary_expansion.is_empty():
		# Patches can meet at a single vertex. Include its remaining incident
		# triangles to obtain closed disjoint loops before retriangulation.
		return {"violations": boundary_expansion, "triangles": []}
	var loops: Array[PackedVector2Array] = []
	var visited: Dictionary = {}
	for start: int in adjacent:
		if visited.has(start):
			continue
		var loop := PackedVector2Array()
		var previous := -1
		var current := start
		while not visited.has(current):
			visited[current] = true
			loop.append(_positions[current])
			var next: int = adjacent[current][0] if adjacent[current][0] != previous else adjacent[current][1]
			previous = current
			current = next
		if current != start or loop.size() < 3:
			return {"failure": "open_boundary"}
		loops.append(loop)
	for p: Vector2 in added:
		vertices[_ids[p]] = true
	var ordered: Array = vertices.keys()
	ordered.sort_custom(func(a: int, b: int) -> bool: return _current[_positions[a]] < _current[_positions[b]])
	var local_points := PackedVector2Array()
	for id: int in ordered:
		local_points.append(_positions[id])
	stats.patch_points = local_points.size()
	stats.local_calls += 1
	var indices := _native_call(local_points, _origin)
	var triangles: Array = []
	var patch_edges: Dictionary = {}
	var used: Dictionary = {}
	for i in range(0, indices.size(), 3):
		var a: Vector2 = local_points[indices[i]]
		var b: Vector2 = local_points[indices[i + 1]]
		var c: Vector2 = local_points[indices[i + 2]]
		var center := (a + b + c) / 3.0
		var inside := false
		for loop: PackedVector2Array in loops:
			if Geometry2D.is_point_in_polygon(center, loop):
				inside = not inside
		if not inside:
			continue
		var ids := Vector3i(ordered[indices[i]], ordered[indices[i + 1]], ordered[indices[i + 2]])
		var tri := _triangle(ids)
		if not is_finite(tri.radius) or not tri.center.is_finite():
			return {"failure": "degenerate_triangle"}
		triangles.append(tri)
		for edge: Vector2i in _edges(ids):
			patch_edges[edge] = int(patch_edges.get(edge, 0)) + 1
		for id: int in [ids.x, ids.y, ids.z]:
			used[id] = true
	for edge: Vector2i in boundary:
		if patch_edges.get(edge, 0) != 1:
			boundary_expansion[_positions[edge.x]] = true
			boundary_expansion[_positions[edge.y]] = true
	if not boundary_expansion.is_empty():
		return {"violations": boundary_expansion, "triangles": []}
	for edge: Vector2i in patch_edges:
		if patch_edges[edge] != (1 if boundary.has(edge) else 2):
			return {"failure": "unmatched_patch_edge"}
	if used.size() != vertices.size():
		var unused: Array = []
		for id: int in vertices:
			if not used.has(id) and unused.size() < 4:
				var local_id: int = ordered.find(id)
				var incident: Array = []
				for old_id: int in _by_point.get(_positions[id], {}):
					if cavity.has(old_id) and incident.size() < 4:
						var old: Dictionary = _index._triangles[old_id]
						incident.append({"positions": old.positions, "radius": old.radius,
							"area": (old.positions[1] - old.positions[0]).cross(old.positions[2] - old.positions[0])})
				unused.append({"point": _positions[id], "native_local_used": indices.has(local_id),
					"previously_used": _by_point.has(_positions[id]), "incident": incident})
		stats["unused_points"] = unused
		return {"failure": "unused_patch_point"}
	var violations: Dictionary = {}
	for tri: Dictionary in triangles:
		for p: Vector2 in _circle_points(tri):
			if tri.positions.has(p):
				continue
			var distance: float = p.distance_squared_to(tri.center) - tri.radius
			if absf(distance) <= _epsilon(tri.radius):
				stats.ambiguous_circles += 1
				# Internal ties were triangulated natively with original relative
				# point order. External ties have not participated in that call.
				if not vertices.has(_ids[p]):
					stats.external_ties += 1
					if not expand_external_ties:
						return {"failure": "cocircular_ambiguity"}
					# Include the tied point and its incident triangles, then run
					# the native patch again with original relative point order.
					violations[p] = true
				continue
			if distance < 0:
				violations[p] = true
	return {"triangles": triangles, "violations": violations}


func _circle_points(tri: Dictionary) -> Array:
	var radius := sqrt(float(tri.radius)) * 1.0001 + 0.0001
	if radius > _index._cell_size * 8.0 or maxf(absf(tri.center.x), absf(tri.center.y)) / _index._cell_size > 1e9:
		return _current.keys()
	var lower: Vector2i = _index._cell(tri.center - Vector2(radius, radius))
	var upper: Vector2i = _index._cell(tri.center + Vector2(radius, radius))
	if (upper.x - lower.x + 1) * (upper.y - lower.y + 1) > 256:
		return _current.keys()
	var result: Array = []
	for x in range(lower.x, upper.x + 1):
		for y in range(lower.y, upper.y + 1):
			result.append_array(_point_cells.get(Vector2i(x, y), []))
	return result


func _epsilon(radius_squared: float) -> float:
	return maxf(0.0000001, radius_squared * 0.00001)


func _edges(ids: Vector3i) -> Array[Vector2i]:
	return [Vector2i(mini(ids.x, ids.y), maxi(ids.x, ids.y)),
		Vector2i(mini(ids.y, ids.z), maxi(ids.y, ids.z)),
		Vector2i(mini(ids.z, ids.x), maxi(ids.z, ids.x))]


func _triangle(ids: Vector3i) -> Dictionary:
	var origin: Vector2 = _positions[ids.x]
	var a: Vector2 = _positions[ids.y] - origin
	var b: Vector2 = _positions[ids.z] - origin
	var offset := (b * a.length_squared() - a * b.length_squared()).orthogonal() / (a.cross(b) * 2.0)
	return {"vertices": ids, "positions": PackedVector2Array([origin, _positions[ids.y], _positions[ids.z]]),
		"center": origin + offset, "radius": offset.length_squared()}


func _add(triangle: Dictionary) -> void:
	triangle.id = _next_triangle
	_next_triangle += 1
	_index._insert(triangle)
	for p: Vector2 in triangle.positions:
		if not _by_point.has(p):
			_by_point[p] = {}
		_by_point[p][triangle.id] = true


func _remove(id: int) -> void:
	for p: Vector2 in _index._triangles[id].positions:
		_by_point[p].erase(id)
		if _by_point[p].is_empty():
			_by_point.erase(p)
	_index._remove(id)


func _full(points: PackedVector2Array, reason: String) -> PackedInt32Array:
	stats.fallback = reason
	if _defer_full:
		clear()
		return PackedInt32Array()
	stats.full_calls += 1
	var indices := GEOMETRY.triangulate(points, condition_native)
	accept_full(points, indices, condition_native)
	return indices


func accept_full(points: PackedVector2Array, indices: PackedInt32Array, centered: bool) -> void:
	clear()
	condition_native = centered
	if points.size() < 3 or points.size() > MAX_POINTS or indices.size() > MAX_TRIANGLES * 3:
		return
	_origin = _calculation_origin(points)
	var rect := Rect2(points[0], Vector2.ZERO)
	for i in range(points.size()):
		if not points[i].is_finite() or _points.has(points[i]):
			clear()
			return
		_points[points[i]] = i
		_ids[points[i]] = i
		_positions[i] = points[i]
		rect = rect.expand(points[i])
	_current = _points.duplicate()
	_next_point = points.size()
	_index._cell_size = maxf(0.001, maxf(rect.size.x, rect.size.y) / 32.0)
	_hull = Geometry2D.convex_hull(points)
	for i in range(0, indices.size(), 3):
		_add(_triangle(Vector3i(indices[i], indices[i + 1], indices[i + 2])))
	stats.triangles_rebuilt = indices.size() / 3
	_input = points.duplicate()
	_snapshot_centered = centered


func _calculation_origin(points: PackedVector2Array) -> Vector2:
	if not condition_native or GEOMETRY.prepare_points(points, true) == points:
		return Vector2.ZERO
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds.get_center()


func _native_call(points: PackedVector2Array, origin: Vector2) -> PackedInt32Array:
	if origin == Vector2.ZERO:
		return Geometry2D.triangulate_delaunay(points)
	var shifted := PackedVector2Array()
	for p: Vector2 in points:
		shifted.append(p - origin)
	return Geometry2D.triangulate_delaunay(shifted)


func _output() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for tri: Dictionary in _index._triangles.values():
		for p: Vector2 in tri.positions:
			indices.append(_current[p])
	return indices
