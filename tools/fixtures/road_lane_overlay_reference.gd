extends "../../addons/scripts/spline_road/road_network_creator.gd"
## Frozen pre-cache native path-strip construction.

func _append_lane_material_path_strip(
	vertices: PackedVector3Array,
	normals_out: PackedVector3Array,
	uvs_out: PackedVector2Array,
	indices: PackedInt32Array,
	path: Path3D,
	inv_global: Transform3D,
	left_side: bool,
	lane_index: int
) -> void:
	var curve := path.curve
	var length := curve.get_baked_length()
	if length <= 0.001:
		return
	var generation_step := sample_step
	if path.has_method("get_road_generation_sample_step"):
		generation_step = maxf(0.01, float(path.call("get_road_generation_sample_step", sample_step)))
	var distances := _build_open_distances_with_step(length, generation_step)
	if distances.size() < 2:
		return
	var rows: Array = []
	for distance in distances:
		var dist := float(distance)
		var frame := get_path_surface_frame(path, dist)
		if frame.is_empty():
			continue
		var center_world: Vector3 = frame.get("center", Vector3.ZERO)
		var right_world: Vector3 = frame.get("right", Vector3.RIGHT)
		var up_world: Vector3 = frame.get("up", Vector3.UP)
		var extents := _resolve_path_lane_extents(path, dist, length)
		var side_extent := extents.x if left_side else extents.y
		var local_lane_width := _resolve_lane_material_width(path, dist, side_extent)
		var inner_distance := minf(side_extent, float(lane_index) * local_lane_width)
		var outer_distance := minf(side_extent, float(lane_index + 1) * local_lane_width)
		var direction := -right_world if left_side else right_world
		var inner_world := center_world + direction * inner_distance + up_world * lane_material_overlay_lift
		var outer_world := center_world + direction * outer_distance + up_world * lane_material_overlay_lift
		var left_world := outer_world if left_side else inner_world
		var right_edge_world := inner_world if left_side else outer_world
		var normal_local := (inv_global.basis * up_world).normalized()
		var base_index := vertices.size()
		vertices.push_back(inv_global * left_world)
		vertices.push_back(inv_global * right_edge_world)
		normals_out.push_back(normal_local)
		normals_out.push_back(normal_local)
		uvs_out.push_back(Vector2(0.0, dist * uv_length_scale))
		uvs_out.push_back(Vector2(1.0, dist * uv_length_scale))
		rows.push_back([base_index, base_index + 1, outer_distance - inner_distance])
	for row_index in range(rows.size() - 1):
		var row0: Array = rows[row_index]
		var row1: Array = rows[row_index + 1]
		if maxf(float(row0[2]), float(row1[2])) <= 0.0001:
			continue
		_append_quad_indices(indices, int(row0[0]), int(row0[1]), int(row1[0]), int(row1[1]))

