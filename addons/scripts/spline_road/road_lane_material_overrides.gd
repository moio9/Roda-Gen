@tool
extends RefCounted
const APPEARANCE = preload("./road_lane_appearance.gd")
const PROJECTOR = preload("./road_lane_overlay_projector.gd")


static func has_overrides(paths: Array[Path3D]) -> bool:
	for path in paths:
		if path.has_method("get_lane_appearance_overrides"):
			for rule: Dictionary in path.get_lane_appearance_overrides():
				if rule.surface_material != null:
					return true
	return false


func append_surfaces(road: Node3D, mesh: ArrayMesh, paths: Array[Path3D], inv_global: Transform3D) -> void:
	var projector := PROJECTOR.new()
	projector.configure(road._terrain_surface_data, road.global_transform)
	var buckets: Dictionary = {}
	for path in paths:
		if path.curve == null or path.curve.point_count < 2 or road._path_is_terrain_influence_only(path):
			continue
		var rules: Array = path.get_lane_appearance_overrides() if path.has_method("get_lane_appearance_overrides") else []
		for side in [-1, 1]:
			var materials: Array[Material] = road.left_lane_material_overrides if side < 0 else road.right_lane_material_overrides
			var lanes := materials.size()
			for rule: Dictionary in rules:
				if rule.side == side and rule.surface_material != null:
					lanes = maxi(lanes, rule.lane)
			for lane in range(1, lanes + 1):
				var fallback: Material = materials[lane - 1] if lane <= materials.size() else null
				_append_lane(road, path, side, lane, rules, fallback, inv_global, projector, buckets)
	for bucket: Dictionary in buckets.values():
		road._lane_overlay_cache.mesh_builder._add_surface(mesh, bucket.vertices, bucket.normals,
			bucket.uvs, bucket.indices, bucket.material, true)


func _append_lane(road: Node3D, path: Path3D, side: int, lane: int, rules: Array,
		fallback: Material, inv_global: Transform3D, projector: RefCounted, buckets: Dictionary) -> void:
	var lane_rules: Array = []
	for rule: Dictionary in rules:
		if rule.side == side and rule.lane == lane and rule.surface_material != null:
			lane_rules.append(rule)
	if fallback == null and lane_rules.is_empty():
		return
	var distances: PackedFloat32Array = road._lane_material_sample_distances(path)
	var length := path.curve.get_baked_length()
	var ranges: Array[Vector2i] = []
	if fallback != null:
		ranges.append(Vector2i(0, distances.size() - 1))
	else:
		for rule: Dictionary in lane_rules:
			var start := maxf(0.0, rule.start)
			var end := minf(length, rule.end)
			if end <= start:
				continue
			# Keep the original bracketing samples: trimming the sample grid would
			# change its triangles, interpolation and projection at the range ends.
			var first := maxi(0, distances.bsearch(start) - 1)
			var last := mini(distances.size() - 1, distances.bsearch(end))
			ranges.append(Vector2i(first, last))
	ranges.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var merged: Array[Vector2i] = []
	for span in ranges:
		if not merged.is_empty() and span.x <= merged[-1].y:
			merged[-1].y = maxi(merged[-1].y, span.y)
		else:
			merged.append(span)
	for span in merged:
		var samples := distances.slice(span.x, span.y + 1)
		var data: Dictionary = road._lane_overlay_cache.range_rows(path, inv_global, side < 0,
			lane - 1, samples, length, span.x)
		_append_range(road, data, samples, side, lane, lane_rules, fallback, inv_global, projector, buckets)


func _append_range(road: Node3D, data: Dictionary, distances: PackedFloat32Array,
		side: int, lane: int, rules: Array, fallback: Material, inv_global: Transform3D,
		projector: RefCounted, buckets: Dictionary) -> void:
	var vertices: PackedVector3Array = data.vertices
	var normals: PackedVector3Array = data.normals
	var uvs: PackedVector2Array = data.uvs
	var indices := PackedInt32Array()
	for row in range(data.widths.size() - 1):
		if maxf(data.widths[row], data.widths[row + 1]) > 0.0001:
			road._append_quad_indices(indices, row * 2, row * 2 + 1, row * 2 + 2, row * 2 + 3)
	for i in range(0, indices.size(), 3):
		var source: Array[Dictionary] = []
		var low := INF
		var high := -INF
		for corner in range(3):
			var index := indices[i + corner]
			var up := (road.global_basis * normals[index]).normalized()
			var distance := float(distances[index / 2])
			source.append({"point": road.global_transform * vertices[index] - up * road.lane_material_overlay_lift,
				"uv": uvs[index], "distance": distance})
			low = minf(low, distance)
			high = maxf(high, distance)
		var splits := APPEARANCE.intervals(rules, low, high)
		for part in range(splits.size() - 1):
			var start := splits[part]
			var end := splits[part + 1]
			var material: Material = APPEARANCE.value_at(rules, side, lane, (start + end) * 0.5, "surface_material", fallback)
			if material == null or end - start < 0.000001:
				continue
			var polygon := _clip(_clip(source, start, true), end, false)
			var key := material.get_instance_id()
			if not buckets.has(key):
				buckets[key] = {"material": material, "vertices": PackedVector3Array(),
					"normals": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}
			for fan in range(1, polygon.size() - 1):
				var points := PackedVector3Array([polygon[0].point, polygon[fan].point, polygon[fan + 1].point])
				var texcoords := PackedVector2Array([polygon[0].uv, polygon[fan].uv, polygon[fan + 1].uv])
				for triangle: Dictionary in projector.project(points, texcoords, road.lane_material_overlay_lift):
					road._append_projected_lane_triangle(buckets[key], triangle, inv_global)


func _clip(polygon: Array[Dictionary], limit: float, keep_after: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if polygon.is_empty():
		return result
	var previous := polygon[-1]
	var sign_ := 1.0 if keep_after else -1.0
	var previous_distance := (float(previous.distance) - limit) * sign_
	for current in polygon:
		var distance := (float(current.distance) - limit) * sign_
		if (distance >= 0.0) != (previous_distance >= 0.0):
			var t := previous_distance / (previous_distance - distance)
			result.append({"point": (previous.point as Vector3).lerp(current.point, t),
				"uv": (previous.uv as Vector2).lerp(current.uv, t), "distance": limit})
		if distance >= 0.0:
			result.append(current)
		previous = current
		previous_distance = distance
	return result
