@tool
extends RefCounted
## Exact XZ subtraction for terrain triangles, including the road-edge collars.
## This helper is opt-in: the Poiana terrain adapter supplies its final road mesh.
const CELL_SIZE := 16.0
const EPS := 0.000001
var _triangles: Array = []
var _cells: Dictionary = {}

func prepare(output: MeshInstance3D, to_terrain: Transform3D) -> void:
	_triangles.clear()
	_cells.clear()
	if output == null or output.mesh == null:
		return
	var transform_ := to_terrain * output.global_transform
	# The adapter's road contains asphalt and shoulders only, with no built-in
	# terrain. Include all its surfaces so shoulder bands stay clear as well.
	for surface in range(output.mesh.get_surface_count()):
		var arrays := output.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count, 3):
			var a := transform_ * vertices[indices[i] if not indices.is_empty() else i]
			var b := transform_ * vertices[indices[i+1] if not indices.is_empty() else i+1]
			var c := transform_ * vertices[indices[i+2] if not indices.is_empty() else i+2]
			var area := (_xz(b)-_xz(a)).cross(_xz(c)-_xz(a))
			if absf(area) < EPS:
				continue
			if area < 0:
				var swap := b
				b = c
				c = swap
			var bounds := Rect2(_xz(a), Vector2.ZERO).expand(_xz(b)).expand(_xz(c))
			var id := _triangles.size()
			_triangles.append({"points": PackedVector3Array([a,b,c]), "bounds": bounds})
			for x in range(floori(bounds.position.x/CELL_SIZE), floori(bounds.end.x/CELL_SIZE)+1):
				for z in range(floori(bounds.position.y/CELL_SIZE), floori(bounds.end.y/CELL_SIZE)+1):
					var key := Vector2i(x,z)
					if not _cells.has(key):
						_cells[key] = []
					_cells[key].append(id)

func subtract(a: Vector3, b: Vector3, c: Vector3) -> Array:
	var bounds := Rect2(_xz(a),Vector2.ZERO).expand(_xz(b)).expand(_xz(c))
	var candidates: Dictionary = {}
	for x in range(floori(bounds.position.x/CELL_SIZE), floori(bounds.end.x/CELL_SIZE)+1):
		for z in range(floori(bounds.position.y/CELL_SIZE), floori(bounds.end.y/CELL_SIZE)+1):
			for id in _cells.get(Vector2i(x,z),[]):
				if bounds.intersects(_triangles[id].bounds):
					candidates[id] = true
	var polygons: Array = [PackedVector3Array([a,b,c])]
	for id in candidates:
		var road: PackedVector3Array = _triangles[id].points
		var next: Array = []
		for polygon: PackedVector3Array in polygons:
			if not _overlaps(polygon,road):
				next.append(polygon)
				continue
			# Convex subtraction: retain the outside of each successive edge;
			# only the still-inside fragment proceeds to the next edge.
			var remainder := polygon
			for edge in range(3):
				var start := _xz(road[edge])
				var end := _xz(road[(edge+1)%3])
				var outside := _half_plane(remainder,start,end,false)
				if outside.size() >= 3:
					next.append(outside)
				remainder = _half_plane(remainder,start,end,true)
				if remainder.size() < 3:
					break
		polygons = next
		if polygons.is_empty():
			break
	var result: Array = []
	for polygon: PackedVector3Array in polygons:
		for i in range(1,polygon.size()-1):
			if absf((_xz(polygon[i])-_xz(polygon[0])).cross(_xz(polygon[i+1])-_xz(polygon[0]))) > EPS:
				result.append(PackedVector3Array([polygon[0],polygon[i],polygon[i+1]]))
	return result

func _half_plane(polygon: PackedVector3Array, a: Vector2, b: Vector2, inside: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[polygon.size()-1]
	var previous_d := (b-a).cross(_xz(previous)-a)
	for current in polygon:
		var current_d := (b-a).cross(_xz(current)-a)
		var previous_in := previous_d >= 0 if inside else previous_d <= 0
		var current_in := current_d >= 0 if inside else current_d <= 0
		if current_in != previous_in:
			var denominator := previous_d-current_d
			if absf(denominator) > EPS:
				result.append(previous.lerp(current,clampf(previous_d/denominator,0,1)))
		if current_in:
			result.append(current)
		previous = current
		previous_d = current_d
	return result

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x,point.z)

func _overlaps(polygon: PackedVector3Array, road: PackedVector3Array) -> bool:
	var p := PackedVector2Array()
	var r := PackedVector2Array()
	for vertex in polygon:
		p.append(_xz(vertex))
	for vertex in road:
		r.append(_xz(vertex))
	return not Geometry2D.intersect_polygons(p,r).is_empty()
