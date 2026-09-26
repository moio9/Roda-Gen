@tool
extends RefCounted
## Project authored lane strips onto final asphalt, in world space. Ownership is
## scoped to each final triangle, so a bridge cannot erase paint on another deck.
const CUT = preload("./terrain_road_mesh_cut.gd")
const EPS := 0.000001
const MAX_HEIGHT_GAP := 0.75
var _surface := CUT.new()
var _claimed: Dictionary = {}


func configure(data: Dictionary, world: Transform3D) -> void:
	_surface = CUT.new()
	_claimed.clear()
	var indices: PackedInt32Array = data.get("lane_indices", PackedInt32Array())
	if not indices.is_empty():
		_surface.append_surface(data.vertices, indices, world)


func project(points: PackedVector3Array, uvs: PackedVector2Array, lift: float) -> Array:
	var source := PackedVector2Array([_xz(points[0]), _xz(points[1]), _xz(points[2])])
	if absf((source[1] - source[0]).cross(source[2] - source[0])) < EPS:
		return []
	var bounds := Rect2(source[0], Vector2.ZERO).expand(source[1]).expand(source[2])
	var candidates: Dictionary = {}
	for x in range(floori(bounds.position.x / CUT.CELL_SIZE), floori(bounds.end.x / CUT.CELL_SIZE) + 1):
		for z in range(floori(bounds.position.y / CUT.CELL_SIZE), floori(bounds.end.y / CUT.CELL_SIZE) + 1):
			for id in _surface._cells.get(Vector2i(x, z), []):
				if bounds.intersects(_surface._triangles[id].bounds):
					candidates[id] = true
	var result: Array = []
	for id in candidates:
		var target: PackedVector3Array = _surface._triangles[id].points
		var polygon := points
		for edge in range(3):
			polygon = _surface._half_plane(polygon, _xz(target[edge]), _xz(target[(edge + 1) % 3]), true)
		# Compare the planes at the actual intersection, not their broad Y bounds.
		polygon = _clip_height(polygon, target, 1.0)
		polygon = _clip_height(polygon, target, -1.0)
		if polygon.size() < 3:
			continue
		if not _claimed.has(id):
			_claimed[id] = CUT.new()
		var claimed: RefCounted = _claimed[id]
		var normal := (target[1] - target[0]).cross(target[2] - target[0]).normalized()
		if normal.y < 0.0:
			normal = -normal
		for i in range(1, polygon.size() - 1):
			var projected := PackedVector3Array()
			for p in [polygon[0], polygon[i], polygon[i + 1]]:
				projected.append(Vector3(p.x, _height(_xz(p), target), p.z))
			# Convex subtraction produces triangles, never a polygon containing a
			# hole that could accidentally be filled by independent triangulation.
			for piece: PackedVector3Array in claimed.subtract(projected[0], projected[1], projected[2]):
				claimed.append_surface(piece, PackedInt32Array(), Transform3D.IDENTITY)
				var vertices := PackedVector3Array()
				var texcoords := PackedVector2Array()
				for p in piece:
					var weights := _weights(_xz(p), points)
					vertices.append(p + normal * lift)
					texcoords.append(uvs[0] * weights.x + uvs[1] * weights.y + uvs[2] * weights.z)
				result.append({"vertices": vertices, "uvs": texcoords, "normal": normal})
	return result


func _clip_height(polygon: PackedVector3Array, target: PackedVector3Array, sign_: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[-1]
	var previous_gap := sign_ * (previous.y - _height(_xz(previous), target)) - MAX_HEIGHT_GAP
	for current in polygon:
		var gap := sign_ * (current.y - _height(_xz(current), target)) - MAX_HEIGHT_GAP
		if (gap <= 0.0) != (previous_gap <= 0.0):
			result.append(previous.lerp(current, previous_gap / (previous_gap - gap)))
		if gap <= 0.0:
			result.append(current)
		previous = current
		previous_gap = gap
	return result


func _weights(p: Vector2, triangle: PackedVector3Array) -> Vector3:
	var ab := _xz(triangle[1] - triangle[0])
	var ac := _xz(triangle[2] - triangle[0])
	var ap := p - _xz(triangle[0])
	var det := ab.cross(ac)
	var b := ap.cross(ac) / det
	var c := ab.cross(ap) / det
	return Vector3(1.0 - b - c, b, c)


func _height(p: Vector2, triangle: PackedVector3Array) -> float:
	var w := _weights(p, triangle)
	return triangle[0].y * w.x + triangle[1].y * w.y + triangle[2].y * w.z


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
