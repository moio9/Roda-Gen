@tool
extends RefCounted
## Builds a junction from retained cross sections, without squeezing their widths.
## Candidate geometry is validated before any original triangles are removed.
var removed_vertices: Dictionary = {}
var regions: Array[Dictionary] = []
var reports: Array[Dictionary] = []

func clear() -> void:
	removed_vertices.clear()
	regions.clear()
	reports.clear()

func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func build(road: Node, verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, surfaces: Array, sockets: Array[Dictionary],
		cluster: Array, paths: Array, attempt := 0) -> bool:
	var selected: Dictionary = {}
	var center := Vector3.ZERO
	for id in cluster:
		var socket: Dictionary = sockets[id]
		var path_id := int(socket.path_id)
		if not selected.has(path_id):
			selected[path_id] = []
		selected[path_id].append(int(socket.row_idx))
		center += Vector3(socket.position)
	center /= cluster.size()
	var radius := float(road.junction_corner_radius)
	var clearance := radius
	for id in cluster:
		clearance = maxf(clearance, radius + float(sockets[id].width) * 0.5)
	clearance *= pow(1.6, attempt)
	var arms: Array[Dictionary] = []
	var arm_retreats: Array[Dictionary] = []
	var discarded: Dictionary = {}
	var pending_regions: Array[Dictionary] = []
	for path_id in selected:
		var rows: Array = paths[path_id]
		var ids: Array = selected[path_id]
		ids.sort()
		var first := int(ids.front())
		var last := int(ids.back())
		var low := first
		var high := last
		for direction in [-1, 1]:
			var anchor := first if direction < 0 else last
			if anchor + direction < 0 or anchor + direction >= rows.size():
				continue
			var index := anchor
			# Each arm has its own width, requested space, and available length.
			# Keep one original segment at the far end instead of rejecting the
			# entire junction when another arm's larger retreat cannot fit here.
			var requested := (radius + float(rows[anchor].width) * 0.5) * pow(1.6, attempt)
			var limit := 1 if direction < 0 else rows.size() - 2
			if (limit - anchor) * direction <= 0:
				return _reject("No room to retain a road segment on path %d, side %d" % [path_id, direction])
			while index != limit:
				index += direction
				if _xz(Vector3(rows[index].position) - center).length() >= requested:
					break
			var actual := _xz(Vector3(rows[index].position) - center).length()
			arm_retreats.append({"path": path_id, "side": direction, "requested": requested,
				"actual": actual, "limited": actual + 0.0001 < requested})
			var row: Dictionary = rows[index]
			var edges: Array = row.row_edges
			if edges.size() != 6:
				return _reject("Unsupported cross section")
			for vertex in edges:
				if removed_vertices.has(int(vertex)):
					return _reject("Overlapping neighboring junctions")
			var outgoing := (Vector3(rows[index + direction].position) - Vector3(row.position)).normalized()
			var positive_side := Vector2(-outgoing.z, outgoing.x)
			var left_ids := [0, 1, 2]
			var right_ids := [5, 4, 3]
			if _xz(verts[int(edges[0])] - Vector3(row.position)).dot(positive_side) < 0:
				var swap := left_ids
				left_ids = right_ids
				right_ids = swap
			var arm := {"path": path_id, "index": index, "position": Vector3(row.position),
				"direction": outgoing, "angle": atan2(outgoing.z, outgoing.x),
				"positive": [], "negative": []}
			for slot in left_ids:
				arm.positive.append(verts[int(edges[slot])])
			for slot in right_ids:
				arm.negative.append(verts[int(edges[slot])])
			arms.append(arm)
			if direction < 0:
				low = index
			else:
				high = index
		for index in range(low, high + 1):
			if (index == low and low < first) or (index == high and high > last):
				continue
			for vertex in rows[index].row_edges:
				discarded[int(vertex)] = true
		pending_regions.append({"path": path_id, "from": float(rows[low].distance), "to": float(rows[high].distance)})
	if arms.size() < 2:
		return _reject("Fewer than two usable arms")
	arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.angle < b.angle)
	var outline := PackedVector3Array()
	var corners: Array[Dictionary] = []
	var subdivisions := int(road.junction_corner_subdivisions)
	for i in range(arms.size()):
		var a: Dictionary = arms[i]
		var b: Dictionary = arms[(i + 1) % arms.size()]
		var delta := fposmod(float(b.angle) - float(a.angle), TAU)
		if delta < deg_to_rad(12.0):
			return _reject("Near-parallel arms require a merge connector")
		var p: Vector3 = a.positive[2]
		var q: Vector3 = b.negative[2]
		var da := _xz(Vector3(a.direction)).normalized()
		var db := _xz(Vector3(b.direction)).normalized()
		var hit: Variant = Geometry2D.line_intersects_line(_xz(p), da, _xz(q), db)
		var control := (p + q) * 0.5
		var rounded := false
		if hit != null and delta < PI - 0.02:
			var h: Vector2 = hit
			# Only an intersection behind both retained cross sections is usable.
			if (h - _xz(p)).dot(da) <= 0.01 and (h - _xz(q)).dot(db) <= 0.01:
				if h.distance_to(_xz(center)) < clearance * 4.0:
					control = Vector3(h.x, (p.y + q.y) * 0.5, h.y)
					rounded = true
		var lanes := PackedVector3Array()
		var shoulders := PackedVector3Array()
		var sidewalks := PackedVector3Array()
		var shoulder_a := _xz(Vector3(a.positive[1]) - p).length()
		var shoulder_b := _xz(Vector3(b.negative[1]) - q).length()
		var sidewalk_a := _xz(Vector3(a.positive[0]) - Vector3(a.positive[1])).length()
		var sidewalk_b := _xz(Vector3(b.negative[0]) - Vector3(b.negative[1])).length()
		var two_arm := arms.size() == 2
		for step in range(subdivisions + 1):
			var t := float(step) / subdivisions
			var blend := 1.0
			if road.junction_corner_profile != null:
				var profile_t := 1.0 - t if two_arm and i == 1 else t
				blend = clampf(road.junction_corner_profile.sample(profile_t), 0.0, 1.0)
			var straight := p.lerp(q, t)
			var bezier := p.lerp(control, t).lerp(control.lerp(q, t), t)
			var point := straight.lerp(bezier, blend) if rounded else straight
			if two_arm:
				var curve_center := _connection_center(a, b, t, blend)
				var previous := _connection_center(a, b, maxf(0.0, t - 0.001), blend)
				var following := _connection_center(a, b, minf(1.0, t + 0.001), blend)
				var tangent := _xz(following - previous).normalized()
				var right := Vector3(tangent.y, 0, -tangent.x)
				var width_a := _xz(p - Vector3(a.position)).length()
				var width_b := _xz(q - Vector3(b.position)).length()
				point = curve_center + right * lerpf(width_a, width_b, t)
				if step == 0:
					point = p
				elif step == subdivisions:
					point = q
			point.y = lerpf(p.y, q.y, t)
			lanes.append(point)
		for step in range(subdivisions + 1):
			var t := float(step) / subdivisions
			var tangent := _xz(lanes[mini(step + 1, subdivisions)] - lanes[maxi(step - 1, 0)]).normalized()
			var outward := Vector3(tangent.y, 0, -tangent.x)
			var inner := lanes[step] + outward * lerpf(shoulder_a, shoulder_b, t)
			inner.y = lerpf(Vector3(a.positive[1]).y, Vector3(b.negative[1]).y, t)
			var outer := inner + outward * lerpf(sidewalk_a, sidewalk_b, t)
			if step == 0:
				inner = a.positive[1]
				outer = a.positive[0]
			elif step == subdivisions:
				inner = b.negative[1]
				outer = b.negative[0]
			shoulders.append(inner)
			sidewalks.append(outer)
		outline.append_array(lanes)
		corners.append({"lane": lanes, "shoulder": shoulders, "sidewalk": sidewalks})
	var polygon := PackedVector2Array()
	for point in outline:
		polygon.append(_xz(point))
	if not _simple(polygon):
		if attempt < 3:
			return build(road, verts, normals, uvs, surfaces, sockets, cluster, paths, attempt + 1)
		return _reject("Could not construct non-overlapping asphalt within available arm lengths", arm_retreats)
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		return _reject("Corner outline cannot be triangulated")
	var outer_polygon := PackedVector2Array()
	for corner in corners:
		for point in corner.sidewalk:
			outer_polygon.append(_xz(point))
	if not _simple(outer_polygon):
		if attempt < 3:
			return build(road, verts, normals, uvs, surfaces, sockets, cluster, paths, attempt + 1)
		return _reject("Could not construct non-overlapping sidewalks at authored widths within available arm lengths", arm_retreats)
	# Nonplanar junctions need interior support. Ear clipping in XZ alone can
	# connect almost-collinear boundary vertices with different heights and
	# turn a gentle approach into a near-vertical asphalt sliver.
	var surface_points := outline.duplicate()
	var interior := _interior_support(outline, center) if arms.size() >= 3 else {}
	if not interior.is_empty():
		var interior_index := surface_points.size()
		surface_points.append(interior.point)
		triangles.clear()
		for edge in range(outline.size()):
			triangles.append_array(PackedInt32Array([edge, (edge + 1) % outline.size(), interior_index]))
	# Commit only after validating the full candidate.
	for surface in surfaces:
		remove_retired_triangles(surface, discarded)
	removed_vertices.merge(discarded)
	regions.append_array(pending_regions)
	var base := verts.size()
	for point in surface_points:
		_vertex(point, verts, normals, uvs)
	for i in range(0, triangles.size(), 3):
		_triangle(surfaces[0], base + triangles[i], base + triangles[i + 1], base + triangles[i + 2], verts, bool(road.invert_faces))
	for corner in corners:
		_band(corner.lane, corner.shoulder, surfaces[1], verts, normals, uvs, bool(road.invert_faces))
		_band(corner.shoulder, corner.sidewalk, surfaces[2], verts, normals, uvs, bool(road.invert_faces))
	reports.append({"ok": true, "arms": arms.size(), "corners": corners.size(), "center": center,
		"retreat": clearance, "arm_retreats": arm_retreats, "retries": attempt,
		"interior_support": not interior.is_empty()})
	return true

func _interior_support(outline: PackedVector3Array, center: Vector3) -> Dictionary:
	var min_y := INF
	var max_y := -INF
	var rays := PackedVector2Array()
	for point in outline:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
		rays.append(_xz(point - center))
	if max_y - min_y < 0.0001:
		return {}
	# A fan is valid only from the polygon kernel: every boundary edge must
	# see the center on the same side. Concave non-star-shaped outlines retain
	# the validated polygon triangulation instead of gaining crossing triangles.
	var sign_ := 0.0
	var half_angles := PackedFloat64Array()
	for i in range(rays.size()):
		var a := rays[i]
		var b := rays[(i + 1) % rays.size()]
		var cross_ := a.cross(b)
		if absf(cross_) < 0.00001:
			return {}
		if sign_ == 0.0:
			sign_ = signf(cross_)
		if cross_ * sign_ <= 0.0:
			return {}
		var denominator := a.length() * b.length() + a.dot(b)
		if denominator <= 0.00001:
			return {}
		half_angles.append(absf(cross_) / denominator)
	# Mean-value coordinates reproduce a tilted plane exactly and interpolate
	# a banked boundary without moving the retained road cross sections.
	var weight_sum := 0.0
	var height_sum := 0.0
	for i in range(rays.size()):
		var weight := (half_angles[(i + rays.size() - 1) % rays.size()] + half_angles[i]) / rays[i].length()
		weight_sum += weight
		height_sum += weight * outline[i].y
	center.y = height_sum / weight_sum
	return {"point": center}

func _connection_center(a: Dictionary, b: Dictionary, t: float, blend: float) -> Vector3:
	var p: Vector3 = a.position
	var q: Vector3 = b.position
	var handle := p.distance_to(q) * 0.65
	var c1 := p - Vector3(a.direction) * handle
	var c2 := q - Vector3(b.direction) * handle
	var u := 1.0 - t
	var curve := p * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + q * t * t * t
	return p.lerp(q, t).lerp(curve, blend)

func _reject(reason: String, arm_retreats: Array[Dictionary] = []) -> bool:
	reports.append({"ok": false, "reason": reason, "arm_retreats": arm_retreats})
	return false

func _simple(polygon: PackedVector2Array) -> bool:
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		for j in range(i + 2, polygon.size()):
			if i == 0 and j == polygon.size() - 1:
				continue
			if Geometry2D.segment_intersects_segment(a, b, polygon[j], polygon[(j + 1) % polygon.size()]) != null:
				return false
	return true

func _vertex(point: Vector3, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> int:
	var id := verts.size()
	verts.append(point)
	normals.append(Vector3.UP)
	uvs.append(_xz(point))
	return id

func _triangle(indices: PackedInt32Array, a: int, b: int, c: int, verts: PackedVector3Array, invert: bool) -> void:
	var cross := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	var cross_y := cross.y
	if cross.length_squared() < 0.000000000001:
		return
	if (cross_y > 0) == invert:
		indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))

func _band(a: PackedVector3Array, b: PackedVector3Array, indices: PackedInt32Array,
		verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, invert: bool) -> void:
	for i in range(a.size() - 1):
		var base := verts.size()
		for point in [a[i], a[i + 1], b[i + 1], b[i]]:
			_vertex(point, verts, normals, uvs)
		_triangle(indices, base, base + 1, base + 2, verts, invert)
		_triangle(indices, base, base + 2, base + 3, verts, invert)

func remove_retired_triangles(indices: PackedInt32Array, discarded: Dictionary) -> void:
	var kept := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		if not discarded.has(indices[i]) and not discarded.has(indices[i + 1]) and not discarded.has(indices[i + 2]):
			kept.append_array(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))
	indices.clear()
	indices.append_array(kept)
