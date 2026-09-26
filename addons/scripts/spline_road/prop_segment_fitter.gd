@tool
extends RefCounted
## Rigid modules fitted to shared points on a road edge, including width and bank changes.
## Deliberately separate from independent scatter/randomization and its placement cache.

var _model_basis := Basis.IDENTITY
var _model_offset := Vector3.ZERO
var _min_z := INF
var _max_z := -INF
var _minimum := Vector3(INF, INF, INF)
var _maximum := Vector3(-INF, -INF, -INF)
var _road_edge := preload("./prop_road_edge_query.gd").new()


func prepare(props: Node3D) -> bool:
	_road_edge.configure(_road_source(props) if props.follow_generated_road_edge else null)
	var yaw := Basis(Vector3.UP, deg_to_rad(float(props.yaw_offset_degrees)))
	_model_basis = yaw * props.custom_transform.basis
	_model_offset = yaw * props.custom_transform.origin
	_min_z = INF
	_max_z = -INF
	_minimum = Vector3(INF, INF, INF)
	_maximum = Vector3(-INF, -INF, -INF)
	if props.item_scene != null:
		var model: Node = props.item_scene.instantiate()
		if model is Node3D:
			# Spawn placement replaces the scene root transform; child transforms remain.
			_measure_node(model, Transform3D.IDENTITY)
		model.free()
	elif props.item_mesh != null:
		_measure_mesh(props.item_mesh, Transform3D.IDENTITY)
	return is_finite(_min_z) and is_finite(_max_z) and _max_z - _min_z > 0.0001


func _measure_node(node: Node, local: Transform3D) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_measure_mesh(node.mesh, local)
	for child in node.get_children():
		var child_transform := local
		if child is Node3D:
			child_transform *= child.transform
		_measure_node(child, child_transform)


func _measure_mesh(mesh: Mesh, local: Transform3D) -> void:
	# Actual vertices avoid false extra length from rotated child AABBs.
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			continue
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var point := _model_basis * (local * vertex)
			_min_z = minf(_min_z, point.z)
			_max_z = maxf(_max_z, point.z)
			_minimum = _minimum.min(point)
			_maximum = _maximum.max(point)


func placements(props: Node3D, path: Path3D, parent: Node3D, zones: Array, span_ranges: Dictionary) -> Array:
	var output: Array = []
	if path == null or path.curve == null or path.curve.point_count < 2:
		return output
	var length := path.curve.get_baked_length()
	var begin := clampf(props.start_offset, 0.0, length)
	var end := maxf(begin, length - maxf(0.0, props.end_trim))
	var intervals := _intervals(props, path, length, begin, end, span_ranges)
	var parent_inverse := parent.global_transform.affine_inverse()
	var step := maxf(0.1, props.spacing)
	var candidates := 0
	for side: int in props._build_sides_for_mode():
		for interval: Vector2 in intervals:
			var distance := interval.x
			var ground_state: Dictionary = {}
			var previous := _sample(props, path, distance, length, side, ground_state)
			while distance < interval.y - 0.0001 and candidates < 200000:
				var next_distance := minf(distance + step, interval.y)
				var next := _sample(props, path, next_distance, length, side, ground_state)
				candidates += 1
				if not previous.is_empty() and not next.is_empty():
					var a: Vector3 = previous.position
					var b: Vector3 = next.position
					if a.distance_to(b) > 0.0001 and not _blocked(props, path, a, b, side, zones):
						var tangent := (b - a).normalized()
						var up: Vector3 = previous.up + next.up
						var basis := _basis(tangent, up)
						basis = basis.scaled_local(Vector3(1.0, 1.0, a.distance_to(b) / (_max_z - _min_z)))
						var origin := (a + b) * 0.5 - basis.z * ((_min_z + _max_z) * 0.5)
						var world := Transform3D(basis * _model_basis, origin)
						# A rigid chord can cross the road at an abrupt junction or a
						# tight bend even with both endpoints outside. Leave that opening clear.
						if not _crosses_road(props, side, Transform3D(basis, origin)):
							output.append([parent_inverse * world, origin])
				previous = next
				distance = next_distance
	return output


func _sample(props: Node3D, path: Path3D, distance: float, length: float, side: int, ground_state: Dictionary) -> Dictionary:
	props._placement_cache.stats.sampling_steps += 1
	var curve := path.curve
	var path_transform := path.global_transform
	var center := path_transform * curve.sample_baked(distance, true)
	var tangent: Vector3 = props._sample_curve_tangent_world(curve, path_transform, distance, length)
	var up: Vector3 = props._sample_curve_up_world(curve, path_transform, distance)
	var right := up.cross(tangent).normalized()
	var frame: Dictionary = props._get_road_surface_frame(path, distance)
	if not frame.is_empty():
		center = frame.get("center", center)
		right = frame.get("right", right)
		up = frame.get("up", up)
		tangent = right.cross(up).normalized()
	var offset: float = props._compute_side_offset(path, distance, length, side)
	offset += float(side) * props.outward_offset + props.lateral_offset
	var position: Vector3 = center + right * offset + up * props.vertical_offset
	if side != 0 and props.follow_generated_road_edge and props.edge_uses_total_road_width:
		var outward := right * float(side)
		var edge: Dictionary = _road_edge.edge_at(center, outward)
		if not edge.is_empty():
			up = edge.up
			# Extend the final surface slope beyond its boundary for the offset.
			if up.y > 0.001:
				outward.y = -(up.x * outward.x + up.z * outward.z) / up.y
			outward = outward.normalized()
			var half_width := maxf(0.0, -_minimum.x if side < 0 else _maximum.x)
			position = edge.position + outward * (half_width + props.outward_offset) \
				+ right * props.lateral_offset + up * props.vertical_offset
	if props.snap_to_ground_enabled:
		props._placement_cache.stats.ground_queries_sampled += 1
		var hit: Dictionary = props._placement_cache.sample_ground(position,
			clampf(props.snap_to_ground_max_angle_deg, 0.0, 89.0), props.snap_to_ground_y_offset)
		if not hit.get("hit", false):
			return {}
		if hit.get("within_max_angle", false):
			position.y = hit.y
			ground_state["y"] = position.y
		elif props.snap_to_ground_slope_mode == 1 and ground_state.has("y"):
			position.y = ground_state.y
		else:
			return {}
	if not props.align_with_curve_up:
		up = Vector3.UP
	# Apply offsets to the shared samples so neighboring modules agree on endpoints.
	position += _basis(tangent, up) * _model_offset
	return {"position": position, "up": up}


func _crosses_road(props: Node3D, side: int, fitted: Transform3D) -> bool:
	if side == 0 or not props.follow_generated_road_edge or not props.edge_uses_total_road_width or not _road_edge.active():
		return false
	var corners := PackedVector3Array([
		Vector3(_minimum.x, _minimum.y, _min_z), Vector3(_maximum.x, _minimum.y, _min_z),
		Vector3(_maximum.x, _minimum.y, _max_z), Vector3(_minimum.x, _minimum.y, _max_z)])
	return _road_edge.overlaps_footprint(fitted * corners)


func road_changed(props: Node3D) -> bool:
	return props.follow_generated_road_edge and _road_edge.changed(_road_source(props))


func _road_source(props: Node3D) -> Node3D:
	return props.get_node_or_null(props.road_network_source) as Node3D if not props.road_network_source.is_empty() else null


func _basis(tangent: Vector3, up: Vector3) -> Basis:
	var t := tangent.normalized()
	var x := t.cross(up).normalized()
	if x.length_squared() < 0.0001:
		x = t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis(x, x.cross(t).normalized(), -t)


func _blocked(props: Node3D, path: Path3D, a: Vector3, b: Vector3, side: int, zones: Array) -> bool:
	# Test the closest point of the full module, not only its pivot, against clearance zones.
	for zone: Dictionary in zones:
		var closest := Geometry3D.get_closest_point_to_segment(zone.position, a, b)
		if props._point_blocked_by_intersection_zones(path, closest, side, [zone]):
			return true
	return false


func _intervals(props: Node3D, path: Path3D, length: float, begin: float, end: float, spans: Dictionary) -> Array[Vector2]:
	var output: Array[Vector2] = []
	if end <= begin + 0.0001:
		return output
	var ranges: PackedVector2Array = props._build_effective_ranges(path, length, spans)
	if props.ranges_mode == 0 or ranges.is_empty():
		return [Vector2(begin, end)]
	var sorted: Array[Vector2] = []
	for pair in ranges:
		var a := maxf(begin, pair.x)
		var b := minf(end, pair.y)
		if b > a + 0.0001:
			sorted.append(Vector2(a, b))
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for pair in sorted:
		if not merged.is_empty() and pair.x <= merged[-1].y:
			merged[-1].y = maxf(merged[-1].y, pair.y)
		else:
			merged.append(pair)
	if props.ranges_mode == 1:
		return merged
	var cursor := begin
	for pair in merged:
		if pair.x > cursor + 0.0001:
			output.append(Vector2(cursor, pair.x))
		cursor = pair.y
	if end > cursor + 0.0001:
		output.append(Vector2(cursor, end))
	return output
