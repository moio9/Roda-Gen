extends "../../scripts/spline_road/terrain_topology_builder.gd"

# Original ring traversal for exact result and tie-order parity checks.
func _nearest_road_info_spatial_uncached(p: Vector2, road_segments: Array, trace: Dictionary = {}) -> Dictionary:
	var best := INF
	var best_info := {}
	var tested: Dictionary = {}
	var cell_size := _road_spatial_cell_size
	var center_cell_x := floori(p.x / cell_size)
	var center_cell_z := floori(p.y / cell_size)
	var ring := 0

	while true:
		var min_cell_x := center_cell_x - ring
		var min_cell_z := center_cell_z - ring
		var max_cell_x := center_cell_x + ring
		var max_cell_z := center_cell_z + ring
		for x in range(min_cell_x, max_cell_x + 1):
			for z in range(min_cell_z, max_cell_z + 1):
				if ring > 0 and x != min_cell_x and x != max_cell_x and z != min_cell_z and z != max_cell_z:
					continue
				var segment_indices = _road_spatial_cells.get(Vector2i(x, z), null)
				if segment_indices == null:
					continue
				for segment_index in segment_indices:
					if tested.has(segment_index):
						continue
					tested[segment_index] = true
					if _source_cache.stats.has("distance_tests"):
						_source_cache.stats.distance_tests += 1
					var segment: Dictionary = road_segments[segment_index]
					var a: Vector2 = segment.get("a", Vector2.ZERO)
					var b: Vector2 = segment.get("b", Vector2.ZERO)
					var ab: Vector2 = segment.get("ab", b - a)
					var len2 := float(segment.get("len2", ab.length_squared()))
					if len2 < 0.000001:
						continue
					var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
					var q := a + ab * t
					var center_dist := p.distance_to(q)
					var width := lerpf(float(segment.get("wa", fallback_road_width)), float(segment.get("wb", fallback_road_width)), t)
					var side := _road_side_for_segment(segment, p, q)
					var edge_dist := center_dist - _segment_half_xz(segment, t, side)
					if edge_dist < best:
						best = edge_dist
						best_info = {
							"center": q,
							"center_distance": center_dist,
							"edge_distance": edge_dist,
							"side": side,
							"road_y": _sample_segment_surface_y(segment, p, q, t, side),
							"width": width,
							"t": t,
							"path_id": int(segment.get("path_id", -1)),
							"terrain_profile": segment.get("terrain_profile", _default_terrain_height_profile()),
						}

		if best == INF and tested.size() == road_segments.size():
			# All indexed sources may have degenerate XZ projections. Expanding
			# forever cannot find another candidate once every segment was tested.
			return {}
		if best < INF:
			var min_x := float(min_cell_x) * cell_size
			var min_z := float(min_cell_z) * cell_size
			var max_x := float(max_cell_x + 1) * cell_size
			var max_z := float(max_cell_z + 1) * cell_size
			var distance_to_unsearched := minf(minf(p.x - min_x, max_x - p.x), minf(p.y - min_z, max_z - p.y))
			if distance_to_unsearched - _road_max_half_width >= best:
				trace["ring"] = ring
				trace["distance"] = distance_to_unsearched
				trace["best"] = best
				return best_info
		ring += 1

	# The loop returns as soon as the current best is provably final. Keep an
	# explicit fallback for GDScript's control-flow analyser.
	return best_info
