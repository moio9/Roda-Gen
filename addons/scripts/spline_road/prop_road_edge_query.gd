@tool
extends RefCounted
## Cross sections of the final road, including welded/laterally joined surfaces.
const CUT = preload("./terrain_road_mesh_cut.gd")
const HEIGHT_TOLERANCE := 0.75
const JOIN_EPS := 0.002
var _cut := CUT.new()
var _bounds := AABB()
var _source_id := 0
var _revision := -1
var _transform := Transform3D.IDENTITY


func configure(road: Node3D) -> void:
	_cut.prepare(null, Transform3D.IDENTITY)
	_source_id = road.get_instance_id() if road != null else 0
	_revision = -1
	_bounds = AABB()
	_transform = road.global_transform if road != null else Transform3D.IDENTITY
	if road == null or not road.has_method("get_terrain_surface_data"):
		return
	if road.has_method("get_terrain_surface_revision"):
		_revision = road.get_terrain_surface_revision()
	var data: Dictionary = road.get_terrain_surface_data()
	var vertices: PackedVector3Array = data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = data.get("indices", PackedInt32Array())
	if vertices.is_empty() or indices.is_empty():
		return
	_cut.append_surface(vertices, indices, _transform)
	for i in range(vertices.size()):
		var point := _transform * vertices[i]
		_bounds = AABB(point, Vector3.ZERO) if i == 0 else _bounds.expand(point)


func changed(road: Node3D) -> bool:
	if road == null:
		return _source_id != 0
	var revision: int = road.get_terrain_surface_revision() if road.has_method("get_terrain_surface_revision") else -1
	return road.get_instance_id() != _source_id or revision != _revision or road.global_transform != _transform


func active() -> bool:
	return not _cut._triangles.is_empty()


func edge_at(center: Vector3, direction: Vector3) -> Dictionary:
	if not active():
		return {}
	var origin := Vector2(center.x, center.z)
	var ray := Vector2(direction.x, direction.z)
	if ray.length_squared() < 0.000001:
		return {}
	var limit := (Vector2(_bounds.size.x, _bounds.size.z).length() + 1.0) / ray.length()
	var candidates: Dictionary = {}
	# Sample cells along the ray; half a cell per step cannot skip an intersected
	# cell when its immediate neighbors are included.
	var step := _cut.CELL_SIZE * 0.5 / ray.length()
	var t := 0.0
	while t <= limit + step:
		var point := origin + ray * minf(t, limit)
		var cell := Vector2i(floori(point.x / _cut.CELL_SIZE), floori(point.y / _cut.CELL_SIZE))
		for x in range(cell.x - 1, cell.x + 2):
			for z in range(cell.y - 1, cell.y + 2):
				for id in _cut._cells.get(Vector2i(x, z), []):
					candidates[id] = true
		t += step
	var intervals: Array[Dictionary] = []
	for id in candidates:
		var triangle: PackedVector3Array = _cut._triangles[id].points
		var interval := _clip_ray(origin, ray, triangle, limit)
		if not interval.is_empty():
			interval["triangle"] = triangle
			interval["origin"] = origin
			interval["ray"] = ray
			intervals.append(interval)
	intervals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.start < b.start)
	var owner: Dictionary = {}
	var error := HEIGHT_TOLERANCE
	for interval in intervals:
		if interval.start > JOIN_EPS:
			break
		var height_error := absf(_height(interval, 0.0) - center.y)
		if height_error <= error:
			error = height_error
			owner = interval
	if owner.is_empty():
		return {}
	var end: float = owner.end
	for interval in intervals:
		if interval.start > end + JOIN_EPS:
			break
		if interval.end <= end:
			continue
		# Follow touching surfaces at this height, never a disconnected parallel
		# road or a bridge occupying the same XZ coordinates on another level.
		var contact := maxf(owner.start, interval.start)
		if absf(_height(interval, contact) - _height(owner, contact)) > HEIGHT_TOLERANCE:
			continue
		end = interval.end
		owner = interval
	var point := origin + ray * end
	var triangle: PackedVector3Array = owner.triangle
	var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
	if normal.y < 0.0:
		normal = -normal
	return {"position": Vector3(point.x, _height(owner, end), point.y), "up": normal}


func _clip_ray(origin: Vector2, ray: Vector2, triangle: PackedVector3Array, limit: float) -> Dictionary:
	var lower := 0.0
	var upper := limit
	for edge in range(3):
		var a := Vector2(triangle[edge].x, triangle[edge].z)
		var b := Vector2(triangle[(edge + 1) % 3].x, triangle[(edge + 1) % 3].z)
		var direction := b - a
		var value := direction.cross(origin - a)
		var slope := direction.cross(ray)
		if absf(slope) < 0.0000001:
			if value < -0.000001:
				return {}
		elif slope > 0.0:
			lower = maxf(lower, -value / slope)
		else:
			upper = minf(upper, -value / slope)
		if lower > upper + 0.000001:
			return {}
	return {"start": lower, "end": upper}


func _height(interval: Dictionary, distance: float) -> float:
	var triangle: PackedVector3Array = interval.triangle
	var point: Vector2 = interval.origin + interval.ray * distance
	var a := Vector2(triangle[0].x, triangle[0].z)
	var ab := Vector2(triangle[1].x, triangle[1].z) - a
	var ac := Vector2(triangle[2].x, triangle[2].z) - a
	var delta := point - a
	var u := delta.cross(ac) / ab.cross(ac)
	var v := ab.cross(delta) / ab.cross(ac)
	return triangle[0].y * (1.0 - u - v) + triangle[1].y * u + triangle[2].y * v


func overlaps_footprint(corners: PackedVector3Array) -> bool:
	for i in [1, 2]:
		for triangle: PackedVector3Array in _cut.intersect_surface(corners[0], corners[i], corners[i + 1], HEIGHT_TOLERANCE):
			var ab := Vector2(triangle[1].x - triangle[0].x, triangle[1].z - triangle[0].z)
			var ac := Vector2(triangle[2].x - triangle[0].x, triangle[2].z - triangle[0].z)
			if absf(ab.cross(ac)) > 0.00001:
				return true
	return false
