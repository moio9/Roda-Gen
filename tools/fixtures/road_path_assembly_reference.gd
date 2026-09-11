extends "../../addons/scripts/spline_road/road_path_sampler.gd"
## Frozen pre-cache assembly, independent of the production cache/assembler.
func _sample_source_blocks(path: Path3D, curve: Curve3D, transform: Transform3D,
		length: float, distances: PackedFloat32Array) -> Dictionary:
	# Preserve the original whole-source copy boundary for the frozen assembler.
	return super._sample_source_blocks(path, curve, transform, length, distances).duplicate(true)


func _assemble_path_native(source: Dictionary, distances: PackedFloat32Array, path_idx: int,
		vertex_base: int, weld_snap: float, weld_allow_midpath: bool, weld_strip_enabled: bool,
		weld_strip_length: float) -> Dictionary:
	var rows_info: Array[Dictionary] = []
	var lane_indices := PackedInt32Array()
	var shoulder_indices := PackedInt32Array()
	var sidewalk_indices := PackedInt32Array()
	var row_edges: Array = source.row_edges
	var row_centers: Array[Vector3] = source.row_centers
	var row_widths: PackedFloat32Array = source.row_widths
	var row_lane_widths: PackedFloat32Array = source.row_lane_widths
	var row_lane_extents: PackedVector2Array = source.row_lane_extents
	var row_marking_layouts: Array[Dictionary] = source.row_marking_layouts
	var row_shoulder_left_widths: PackedFloat32Array = source.row_shoulder_left_widths
	var row_shoulder_right_widths: PackedFloat32Array = source.row_shoulder_right_widths
	var row_sidewalk_left_widths: PackedFloat32Array = source.row_sidewalk_left_widths
	var row_sidewalk_right_widths: PackedFloat32Array = source.row_sidewalk_right_widths
	var row_terrain_left_widths: PackedFloat32Array = source.row_terrain_left_widths
	var row_terrain_right_widths: PackedFloat32Array = source.row_terrain_right_widths
	var row_outer_wall_heights: PackedFloat32Array = source.row_outer_wall_heights
	for row: Array in row_edges:
		for edge in range(row.size()):
			row[edge] += vertex_base

	for i in range(row_edges.size() - 1):
		var row0: Array = row_edges[i]
		var row1: Array = row_edges[i + 1]
		var lane_w_avg := (float(row_lane_widths[i]) + float(row_lane_widths[i + 1])) * 0.5
		var shoulder_l_avg := (float(row_shoulder_left_widths[i]) + float(row_shoulder_left_widths[i + 1])) * 0.5
		var shoulder_r_avg := (float(row_shoulder_right_widths[i]) + float(row_shoulder_right_widths[i + 1])) * 0.5
		var sidewalk_l_avg := (float(row_sidewalk_left_widths[i]) + float(row_sidewalk_left_widths[i + 1])) * 0.5
		var sidewalk_r_avg := (float(row_sidewalk_right_widths[i]) + float(row_sidewalk_right_widths[i + 1])) * 0.5

		if sidewalk_l_avg > 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[0]), int(row0[1]), int(row1[0]), int(row1[1]))
		if shoulder_l_avg > 0.0001:
			_append_quad_indices(shoulder_indices, int(row0[1]), int(row0[2]), int(row1[1]), int(row1[2]))
		if lane_w_avg > 0.0001:
			_append_quad_indices(lane_indices, int(row0[2]), int(row0[3]), int(row1[2]), int(row1[3]))
		if shoulder_r_avg > 0.0001:
			_append_quad_indices(shoulder_indices, int(row0[3]), int(row0[4]), int(row1[3]), int(row1[4]))
		if sidewalk_r_avg > 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[4]), int(row0[5]), int(row1[4]), int(row1[5]))

		# If sidewalk exists but shoulder is zero, close the curb gap to avoid see-through.
		if sidewalk_l_avg > 0.0001 and shoulder_l_avg <= 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[1]), int(row0[2]), int(row1[1]), int(row1[2]))
		if sidewalk_r_avg > 0.0001 and shoulder_r_avg <= 0.0001:
			_append_quad_indices(sidewalk_indices, int(row0[3]), int(row0[4]), int(row1[3]), int(row1[4]))

	for i in range(row_edges.size()):
		var out_dir := _compute_row_out_dir(row_centers, i)
		var row: Array = row_edges[i]
		rows_info.push_back({
			"path_id": path_idx,
			"row_idx": i,
			"distance": distances[i],
			"lane_extents": row_lane_extents[i],
			"position": row_centers[i],
			"out_dir": out_dir,
			"row_a": int(row[0]),
			"row_b": int(row[5]),
				"width": row_widths[i],
				"weld_snap_distance": weld_snap,
				"weld_allow_endpoint_to_midpath": weld_allow_midpath,
				"weld_strip_enabled": weld_strip_enabled,
				"weld_strip_length": weld_strip_length,
				"terrain_left_width": row_terrain_left_widths[i],
				"terrain_right_width": row_terrain_right_widths[i],
				"outer_wall_height": row_outer_wall_heights[i],
				"row_edges": row,
			})
		if markings_enabled:
			rows_info[rows_info.size() - 1]["marking_layout"] = row_marking_layouts[i]

	return {"rows": rows_info, "lane": lane_indices, "shoulder": shoulder_indices, "sidewalk": sidewalk_indices}


func _append_quad_indices(indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	_road._append_quad_indices(indices, a, b, c, d)


func _compute_row_out_dir(centers: Array[Vector3], index: int) -> Vector3:
	return _road._compute_row_out_dir(centers, index)
