extends RefCounted
## Pre-path-cache collection oracle. Keep assembly independent of production.
static func collect(builder: Node3D) -> Dictionary:
	var all_rows: Array = []
	var all_segments: Array = []
	var all_polygons: Array = []
	var path_id := 0
	for np in builder.source_paths:
		var node := builder.get_node_or_null(np)
		if node == null or not node is Path3D:
			continue
		var path := node as Path3D
		var curve := path.curve
		if curve == null or curve.point_count <= 0:
			continue
		var length := curve.get_baked_length()
		if length <= 0.001:
			continue
		var bake_step: float = builder.path_sample_step
		if builder.adaptive_path_sampling:
			bake_step = minf(builder.path_sample_step, builder.adaptive_min_path_step)
		curve.bake_interval = maxf(0.05, bake_step)
		var path_transform := path.global_transform
		var builder_inverse := builder.global_transform.affine_inverse()
		var rows: Array = []
		var d := 0.0
		while d < length:
			rows.append(builder._sample_road_row(path, curve, d, length, path_id, path_transform, builder_inverse))
			d += builder._get_adaptive_path_step(curve, d, length, path_transform, builder_inverse)
		rows.append(builder._sample_road_row(path, curve, length, length, path_id, path_transform, builder_inverse))
		if rows.size() < 2:
			continue
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for row in rows:
			left.push_back(row.get("left2", Vector2.ZERO))
			right.push_back(row.get("right_edge2", Vector2.ZERO))
		var poly := PackedVector2Array()
		for p in left:
			poly.push_back(p)
		for i in range(right.size() - 1, -1, -1):
			poly.push_back(right[i])
		all_polygons.append(poly)
		all_rows.append_array(rows)
		for i in range(rows.size() - 1):
			var a: Dictionary = rows[i]
			var b: Dictionary = rows[i + 1]
			var a2: Vector2 = a.get("center2", Vector2.ZERO)
			var b2: Vector2 = b.get("center2", Vector2.ZERO)
			if a2.distance_to(b2) < 0.001:
				continue
			var ab := b2 - a2
			var len2 := ab.length_squared()
			all_segments.append({
				"a": a2,
				"b": b2,
				"ab": ab,
				"len2": len2,
				"direction": ab / sqrt(len2),
				"ay": float(a.get("center_y", 0.0)),
				"by": float(b.get("center_y", 0.0)),
				"right_a": a.get("right", Vector3.RIGHT),
				"right_b": b.get("right", Vector3.RIGHT),
				"wa": float(a.get("width", builder.fallback_road_width)),
				"wb": float(b.get("width", builder.fallback_road_width)),
				"left_half_xz_a": float(a.get("left_half_xz", builder.fallback_road_width * 0.5)),
				"left_half_xz_b": float(b.get("left_half_xz", builder.fallback_road_width * 0.5)),
				"right_half_xz_a": float(a.get("right_half_xz", builder.fallback_road_width * 0.5)),
				"right_half_xz_b": float(b.get("right_half_xz", builder.fallback_road_width * 0.5)),
				"left_surface_raise_a": float(a.get("left_surface_raise", 0.0)),
				"left_surface_raise_b": float(b.get("left_surface_raise", 0.0)),
				"right_surface_raise_a": float(a.get("right_surface_raise", 0.0)),
				"right_surface_raise_b": float(b.get("right_surface_raise", 0.0)),
				"terrain_profile": a.get("terrain_profile", builder._default_terrain_height_profile()),
				"path_id": path_id,
			})
		path_id += 1
	return {"rows": all_rows, "segments": all_segments, "polygons": all_polygons}
