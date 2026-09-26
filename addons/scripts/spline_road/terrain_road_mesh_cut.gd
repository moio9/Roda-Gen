@tool
extends RefCounted
## Exact XZ subtraction for terrain triangles, including the road-edge collars.
## Accepts final road surface arrays independently of rendering/output mode.
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
	# Compatibility entry point for callers supplying an already isolated mesh.
	# General terrain uses append_surface with explicit road-only indices.
	for surface in range(output.mesh.get_surface_count()):
		var arrays := output.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		append_surface(vertices, indices, transform_)

func append_surface(vertices: PackedVector3Array, indices: PackedInt32Array, transform_: Transform3D) -> void:
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

## Nearest height on this surface in XZ. The result includes distance from the
## surface so a joining road can ease into it across several metres.
func nearest_height_at(point: Vector3, radius: float) -> Dictionary:
	var xz := _xz(point)
	var candidates: Dictionary = {}
	for x in range(floori((xz.x-radius)/CELL_SIZE),floori((xz.x+radius)/CELL_SIZE)+1):
		for z in range(floori((xz.y-radius)/CELL_SIZE),floori((xz.y+radius)/CELL_SIZE)+1):
			for id in _cells.get(Vector2i(x,z),[]):
				candidates[id] = true
	var best_distance := radius+EPS
	var best_height_gap := INF
	var best_height := 0.0
	for id in candidates:
		var vertices: PackedVector3Array = _triangles[id].points
		var a := _xz(vertices[0])
		var b := _xz(vertices[1])
		var c := _xz(vertices[2])
		var ab := b-a
		var ac := c-a
		var det := ab.cross(ac)
		if absf(det) < EPS:
			continue
		var q := xz
		var ap := q-a
		var u := ap.cross(ac)/det
		var v := ab.cross(ap)/det
		if minf(1.0-u-v,minf(u,v)) < 0.0:
			var qa := Geometry2D.get_closest_point_to_segment(xz,a,b)
			var qb := Geometry2D.get_closest_point_to_segment(xz,b,c)
			var qc := Geometry2D.get_closest_point_to_segment(xz,c,a)
			q = qa
			if xz.distance_squared_to(qb) < xz.distance_squared_to(q):
				q = qb
			if xz.distance_squared_to(qc) < xz.distance_squared_to(q):
				q = qc
			ap = q-a
			u = ap.cross(ac)/det
			v = ab.cross(ap)/det
		var distance := xz.distance_to(q)
		if distance > radius+EPS:
			continue
		var y: float = vertices[0].y*(1.0-u-v)+vertices[1].y*u+vertices[2].y*v
		var height_gap := absf(y-point.y)
		if distance < best_distance-EPS or (absf(distance-best_distance) <= EPS and height_gap < best_height_gap):
			best_distance = distance
			best_height_gap = height_gap
			best_height = y
	return {"found": best_height_gap < INF, "distance": best_distance, "height": best_height}

## keep_vertical also clips curb faces using the same XZ half planes, retaining
## triangles with nonzero 3D area. Terrain callers keep the default XZ-only path.
func subtract(a: Vector3, b: Vector3, c: Vector3, keep_vertical := false, max_height_gap := INF) -> Array:
	var bounds := Rect2(_xz(a),Vector2.ZERO).expand(_xz(b)).expand(_xz(c))
	if keep_vertical:
		bounds = bounds.grow(EPS)
	var candidates: Dictionary = {}
	for x in range(floori(bounds.position.x/CELL_SIZE), floori(bounds.end.x/CELL_SIZE)+1):
		for z in range(floori(bounds.position.y/CELL_SIZE), floori(bounds.end.y/CELL_SIZE)+1):
			for id in _cells.get(Vector2i(x,z),[]):
				if bounds.intersects(_triangles[id].bounds):
					candidates[id] = true
	var vertical := absf((_xz(b)-_xz(a)).cross(_xz(c)-_xz(a))) < EPS
	var polygons: Array = [PackedVector3Array([a,b,c])]
	for id in candidates:
		var road: PackedVector3Array = _triangles[id].points
		if minf(a.y,minf(b.y,c.y)) > maxf(road[0].y,maxf(road[1].y,road[2].y))+max_height_gap or maxf(a.y,maxf(b.y,c.y)) < minf(road[0].y,minf(road[1].y,road[2].y))-max_height_gap:
			continue
		var next: Array = []
		for polygon: PackedVector3Array in polygons:
			if (not keep_vertical or not vertical) and not _overlaps(polygon,road):
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
			var area := (polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0]).length() if keep_vertical else absf((_xz(polygon[i])-_xz(polygon[0])).cross(_xz(polygon[i+1])-_xz(polygon[0])))
			if area > EPS:
				result.append(PackedVector3Array([polygon[0],polygon[i],polygon[i+1]]))
	return result

## Keep only the part of a small paint triangle that lies on the final asphalt.
## The source plane supplies the paint height; the road surface supplies its
## footprint, so trimmed transition paint cannot remain over bare terrain.
func intersect_surface(a: Vector3, b: Vector3, c: Vector3, max_height_gap := 0.75) -> Array:
	var source := PackedVector2Array([_xz(a), _xz(b), _xz(c)])
	var det := (source[1] - source[0]).cross(source[2] - source[0])
	if absf(det) < EPS:
		return []
	var bounds := Rect2(source[0], Vector2.ZERO).expand(source[1]).expand(source[2])
	var candidates: Dictionary = {}
	for x in range(floori(bounds.position.x / CELL_SIZE), floori(bounds.end.x / CELL_SIZE) + 1):
		for z in range(floori(bounds.position.y / CELL_SIZE), floori(bounds.end.y / CELL_SIZE) + 1):
			for id in _cells.get(Vector2i(x, z), []):
				if bounds.intersects(_triangles[id].bounds):
					candidates[id] = true
	var covered: Array[PackedVector2Array] = []
	var remaining: Array[PackedVector2Array] = [source]
	for id in candidates:
		if remaining.is_empty():
			break
		var road: PackedVector3Array = _triangles[id].points
		if minf(a.y, minf(b.y, c.y)) > maxf(road[0].y, maxf(road[1].y, road[2].y)) + max_height_gap:
			continue
		if maxf(a.y, maxf(b.y, c.y)) < minf(road[0].y, minf(road[1].y, road[2].y)) - max_height_gap:
			continue
		var footprint := PackedVector2Array([_xz(road[0]), _xz(road[1]), _xz(road[2])])
		var next_remaining: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in remaining:
			covered.append_array(Geometry2D.intersect_polygons(piece, footprint))
			next_remaining.append_array(Geometry2D.clip_polygons(piece, footprint))
		remaining = next_remaining
	var result: Array = []
	for polygon: PackedVector2Array in covered:
		for i in range(1, polygon.size() - 1):
			var triangle := PackedVector3Array()
			for point in [polygon[0], polygon[i], polygon[i + 1]]:
				var offset: Vector2 = point - source[0]
				var wb := offset.cross(source[2] - source[0]) / det
				var wc := (source[1] - source[0]).cross(offset) / det
				triangle.append(a * (1.0 - wb - wc) + b * wb + c * wc)
			if absf((_xz(triangle[1]) - _xz(triangle[0])).cross(_xz(triangle[2]) - _xz(triangle[0]))) > EPS:
				result.append(triangle)
	return result

func geometry_signature() -> int:
	var points: Array = []
	for triangle: Dictionary in _triangles:
		points.append(triangle.points)
	return hash(points)

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

## Clip an indexed surface while preserving UVs, normals, winding and vertical
## curb faces. Eligibility limits cleanup to the paths participating in a junction.
func clip_surface(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array, eligible: Dictionary,
		max_height_gap: float) -> void:
	var output := PackedInt32Array()
	for i in range(0,indices.size(),3):
		var ids := [indices[i],indices[i+1],indices[i+2]]
		if not eligible.has(ids[0]) or not eligible.has(ids[1]) or not eligible.has(ids[2]):
			output.append_array(ids)
			continue
		var a := vertices[ids[0]]
		var b := vertices[ids[1]]
		var c := vertices[ids[2]]
		var pieces := subtract(a,b,c,true,max_height_gap)
		if pieces.size() == 1 and pieces[0] == PackedVector3Array([a,b,c]):
			output.append_array(ids)
			continue
		var ab := b-a
		var ac := c-a
		var denominator := ab.length_squared()*ac.length_squared()-ab.dot(ac)*ab.dot(ac)
		if absf(denominator) < EPS*EPS:
			output.append_array(ids)
			continue
		for triangle: PackedVector3Array in pieces:
			for p in triangle:
				var wb := (ac.length_squared()*(p-a).dot(ab)-ab.dot(ac)*(p-a).dot(ac))/denominator
				var wc := (ab.length_squared()*(p-a).dot(ac)-ab.dot(ac)*(p-a).dot(ab))/denominator
				var wa := 1.0-wb-wc
				output.append(vertices.size())
				vertices.append(p)
				normals.append((normals[ids[0]]*wa+normals[ids[1]]*wb+normals[ids[2]]*wc).normalized())
				uvs.append(uvs[ids[0]]*wa+uvs[ids[1]]*wb+uvs[ids[2]]*wc)
	indices.clear()
	indices.append_array(output)
