@tool
extends RefCounted
## Value-only snapshot of final road surfaces, shared by all terrain builders.
const ROAD_CUT = preload("./terrain_road_mesh_cut.gd")
var _cut := ROAD_CUT.new()
var _surface_queries: Dictionary = {}
var lock_height_to_road_edge := true
var road_edge_height_snap_distance := 1.0
var road_edge_height_blend_distance := 3.0
var terrain_edge_y_offset := 0.0
var y_offset := 0.0

func configure(source: Node) -> void:
	for property in ["lock_height_to_road_edge", "road_edge_height_snap_distance", "road_edge_height_blend_distance", "terrain_edge_y_offset", "y_offset"]:
		set(property, source.get(property))
	_cut.prepare(null, Transform3D.IDENTITY)
	_surface_queries.clear()

func active() -> bool:
	return not _cut._triangles.is_empty()

func _fit(point: Vector3) -> Vector3:
	if not lock_height_to_road_edge:
		return point
	var hit := _surface_at(_xz(point))
	if hit.is_empty():
		return point
	var snap := maxf(0.001, road_edge_height_snap_distance)
	var blend := maxf(0.001, road_edge_height_blend_distance)
	var weight := 1.0 - smoothstep(snap, snap + blend, float(hit.distance))
	point.y = lerpf(point.y, float(hit.y) + terrain_edge_y_offset + y_offset, weight)
	return point

func _fit_seam(point: Vector3) -> Vector3:
	if lock_height_to_road_edge:
		var hit := _surface_at(_xz(point))
		if not hit.is_empty() and float(hit.distance) <= 0.002:
			point.y = float(hit.y) + terrain_edge_y_offset + y_offset
	return point

func _surface_at(point: Vector2) -> Dictionary:
	if _surface_queries.has(point):
		return _surface_queries[point]
	var radius := maxf(0.002, road_edge_height_snap_distance + road_edge_height_blend_distance)
	var best := radius * radius
	var result: Dictionary = {}
	var candidates: Dictionary = {}
	for x in range(floori((point.x-radius)/_cut.CELL_SIZE), floori((point.x+radius)/_cut.CELL_SIZE)+1):
		for z in range(floori((point.y-radius)/_cut.CELL_SIZE), floori((point.y+radius)/_cut.CELL_SIZE)+1):
			for id in _cut._cells.get(Vector2i(x,z), []):
				candidates[id] = true
	for id in candidates:
		var triangle: PackedVector3Array = _cut._triangles[id].points
		var a := _xz(triangle[0])
		var b := _xz(triangle[1])
		var c := _xz(triangle[2])
		var area := (b-a).cross(c-a)
		var wb := (point-a).cross(c-a)/area
		var wc := (b-a).cross(point-a)/area
		if wb >= 0.0 and wc >= 0.0 and wb+wc <= 1.0:
			result = {"distance": 0.0, "y": triangle[0].y*(1.0-wb-wc)+triangle[1].y*wb+triangle[2].y*wc}
			break
		for edge in range(3):
			var start := triangle[edge]
			var end := triangle[(edge+1)%3]
			var delta := _xz(end)-_xz(start)
			var t := clampf((point-_xz(start)).dot(delta)/maxf(delta.length_squared(),0.00000001),0.0,1.0)
			var nearest := start.lerp(end,t)
			var distance := point.distance_squared_to(_xz(nearest))
			if distance < best:
				best = distance
				result = {"distance": sqrt(distance), "y": nearest.y}
	_surface_queries[point] = result
	return result

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
