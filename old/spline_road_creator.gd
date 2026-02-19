@tool
extends Node3D

@export_group("Source")
@export var path_node: NodePath

@export_group("Road")
@export_range(0.2, 50.0, 0.1) var road_width := 6.0
@export_range(0.1, 10.0, 0.1) var sample_step := 1.0
@export_range(-5.0, 5.0, 0.01) var y_offset := 0.02
@export_subgroup("Edges")
@export_range(0.0, 15.0, 0.1) var shoulder_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var shoulder_right_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_right_width := 0.0
@export_range(0.0, 2.0, 0.01) var sidewalk_height := 0.12
@export_subgroup("Edge Materials")
@export var road_material_override: Material
@export var shoulder_material_override: Material
@export var sidewalk_material_override: Material
@export_subgroup("Outer Walls")
@export_range(0.0, 30.0, 0.1) var outer_wall_height := 0.0
@export var outer_wall_material_override: Material
@export_range(0.01, 20.0, 0.01) var uv_length_scale := 0.25
@export var invert_faces := true
@export var material_override: Material

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_regenerate_in_editor := true
@export var regenerate_now := false: set = _set_regenerate_now

const MESH_NODE_NAME := "GeneratedSplineRoad"

var _last_signature := ""


func _ready() -> void:
	set_process(true)
	if _can_generate():
		regenerate()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not auto_regenerate_in_editor:
		return
	if not _can_generate():
		return

	var sig := _build_signature()
	if sig == _last_signature:
		return

	_last_signature = sig
	regenerate()


func _set_regenerate_now(value: bool) -> void:
	regenerate_now = false
	if value and _can_generate():
		regenerate()


func _can_generate() -> bool:
	return not Engine.is_editor_hint() or generate_in_editor


func regenerate() -> void:
	var path := _resolve_path()
	if path == null or path.curve == null:
		_clear_mesh_node()
		return

	var curve := path.curve
	if curve.point_count < 2:
		_clear_mesh_node()
		return

	curve.bake_interval = max(sample_step, 0.01)
	var length := curve.get_baked_length()
	if length <= 0.0:
		_clear_mesh_node()
		return

	var closed := curve.closed
	var distances: PackedFloat32Array = PackedFloat32Array()

	if closed:
		var d := 0.0
		while d < length:
			distances.push_back(d)
			d += sample_step
		if distances.size() < 3:
			distances = PackedFloat32Array([0.0, length / 3.0, (2.0 * length) / 3.0])
	else:
		var d_open := 0.0
		while d_open < length:
			distances.push_back(d_open)
			d_open += sample_step
		distances.push_back(length)
		if distances.size() < 2:
			distances = PackedFloat32Array([0.0, length])

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var lane_indices := PackedInt32Array()
	var shoulder_indices := PackedInt32Array()
	var sidewalk_indices := PackedInt32Array()
	var wall_indices := PackedInt32Array()
	var row_edges: Array = []
	var row_lane_widths := PackedFloat32Array()
	var row_shoulder_left_widths := PackedFloat32Array()
	var row_shoulder_right_widths := PackedFloat32Array()
	var row_sidewalk_left_widths := PackedFloat32Array()
	var row_sidewalk_right_widths := PackedFloat32Array()
	var row_outer_wall_heights := PackedFloat32Array()

	var inv_global := global_transform.affine_inverse()

	for i in range(distances.size()):
		var dist := distances[i]
		var p_local := curve.sample_baked(dist, true)
		var lane_width := _resolve_path_width(path, dist, length)
		var shoulder_left := _resolve_path_shoulder_left(path, dist, length)
		var shoulder_right := _resolve_path_shoulder_right(path, dist, length)
		var sidewalk_left := _resolve_path_sidewalk_left(path, dist, length)
		var sidewalk_right := _resolve_path_sidewalk_right(path, dist, length)
		var local_sidewalk_height := _resolve_path_sidewalk_height(path, dist, length)
		var local_outer_wall_height := _resolve_path_outer_wall_height(path, dist, length)

		var next_dist := dist + 0.1
		if closed:
			next_dist = fmod(next_dist, length)
		else:
			next_dist = min(length, next_dist)
		if is_equal_approx(next_dist, dist):
			next_dist = max(0.0, dist - 0.1)

		var p_next_local := curve.sample_baked(next_dist, true)
		var tangent_local := (p_next_local - p_local).normalized()
		if tangent_local.length() < 0.001:
			tangent_local = Vector3.FORWARD

		var up_local := Vector3.UP
		var right_local := up_local.cross(tangent_local).normalized()
		if right_local.length() < 0.001:
			right_local = tangent_local.cross(Vector3.FORWARD).normalized()
		if right_local.length() < 0.001:
			right_local = Vector3.RIGHT

		var lane_half := lane_width * 0.5
		var left_lane := p_local - right_local * lane_half
		var right_lane := p_local + right_local * lane_half
		var left_shoulder := p_local - right_local * (lane_half + shoulder_left)
		var right_shoulder := p_local + right_local * (lane_half + shoulder_right)
		var left_outer := p_local - right_local * (lane_half + shoulder_left + sidewalk_left)
		var right_outer := p_local + right_local * (lane_half + shoulder_right + sidewalk_right)
		var left_raise := local_sidewalk_height if sidewalk_left > 0.0001 else 0.0
		var right_raise := local_sidewalk_height if sidewalk_right > 0.0001 else 0.0
		left_shoulder.y += left_raise
		left_outer.y += left_raise
		right_shoulder.y += right_raise
		right_outer.y += right_raise

		var side_total := shoulder_left + shoulder_right + sidewalk_left + sidewalk_right
		var total_for_uv := maxf(0.001, lane_width + side_total)
		var u0 := 0.0
		var u1 := sidewalk_left / total_for_uv
		var u2 := (sidewalk_left + shoulder_left) / total_for_uv
		var u3 := (sidewalk_left + shoulder_left + lane_width) / total_for_uv
		var u4 := (sidewalk_left + shoulder_left + lane_width + shoulder_right) / total_for_uv
		var u5 := 1.0
		var v := dist * uv_length_scale

		var edge_points := [
			left_outer,
			left_shoulder,
			left_lane,
			right_lane,
			right_shoulder,
			right_outer,
		]
		var edge_us := [u0, u1, u2, u3, u4, u5]
		var row: Array[int] = []
		row.resize(6)
		for edge_idx in range(6):
			var world_p: Vector3 = path.global_transform * edge_points[edge_idx]
			world_p.y += y_offset
			var vi := verts.size()
			verts.push_back(inv_global * world_p)
			normals.push_back(Vector3.UP)
			uvs.push_back(Vector2(float(edge_us[edge_idx]), v))
			row[edge_idx] = vi
		row_edges.push_back(row)

		row_lane_widths.push_back(maxf(0.1, lane_width))
		row_shoulder_left_widths.push_back(maxf(0.0, shoulder_left))
		row_shoulder_right_widths.push_back(maxf(0.0, shoulder_right))
		row_sidewalk_left_widths.push_back(maxf(0.0, sidewalk_left))
		row_sidewalk_right_widths.push_back(maxf(0.0, sidewalk_right))
		row_outer_wall_heights.push_back(maxf(0.0, local_outer_wall_height))

	var seg_count := row_edges.size() if closed else row_edges.size() - 1
	for i in range(seg_count):
		var ni := (i + 1) % row_edges.size()
		var row0: Array = row_edges[i]
		var row1: Array = row_edges[ni]
		var lane_w_avg := (float(row_lane_widths[i]) + float(row_lane_widths[ni])) * 0.5
		var shoulder_l_avg := (float(row_shoulder_left_widths[i]) + float(row_shoulder_left_widths[ni])) * 0.5
		var shoulder_r_avg := (float(row_shoulder_right_widths[i]) + float(row_shoulder_right_widths[ni])) * 0.5
		var sidewalk_l_avg := (float(row_sidewalk_left_widths[i]) + float(row_sidewalk_left_widths[ni])) * 0.5
		var sidewalk_r_avg := (float(row_sidewalk_right_widths[i]) + float(row_sidewalk_right_widths[ni])) * 0.5

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

	if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
		_clear_mesh_node()
		return

	_append_outer_walls_from_rows(verts, normals, uvs, wall_indices, row_edges, row_outer_wall_heights, closed)
	var mesh := _build_mesh(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, wall_indices)
	_assign_mesh(mesh)
	_last_signature = _build_signature()


func _resolve_path() -> Path3D:
	if path_node != NodePath():
		var linked := get_node_or_null(path_node)
		if linked is Path3D:
			return linked

	for child in get_children():
		if child is Path3D:
			return child

	return null


func _assign_mesh(mesh: ArrayMesh) -> void:
	var mi := get_node_or_null(MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MESH_NODE_NAME
		add_child(mi)
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
	mi.mesh = mesh
	var has_per_band_materials := (
		road_material_override != null
		or shoulder_material_override != null
		or sidewalk_material_override != null
		or outer_wall_material_override != null
	)
	mi.material_override = null if has_per_band_materials else material_override


func _clear_mesh_node() -> void:
	var mi := get_node_or_null(MESH_NODE_NAME)
	if mi != null:
		mi.queue_free()


func _append_quad_indices(indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	if invert_faces:
		indices.push_back(a)
		indices.push_back(b)
		indices.push_back(c)
		indices.push_back(c)
		indices.push_back(b)
		indices.push_back(d)
	else:
		indices.push_back(a)
		indices.push_back(c)
		indices.push_back(b)
		indices.push_back(c)
		indices.push_back(d)
		indices.push_back(b)


func _append_outer_walls_from_rows(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	wall_indices: PackedInt32Array,
	row_edges: Array,
	row_outer_wall_heights: PackedFloat32Array,
	closed: bool
) -> void:
	if row_edges.size() < 2:
		return
	var seg_count := row_edges.size() if closed else row_edges.size() - 1
	for i in range(seg_count):
		var ni := (i + 1) % row_edges.size()
		var row0: Array = row_edges[i]
		var row1: Array = row_edges[ni]
		if row0.size() < 6 or row1.size() < 6:
			continue
		var wall_h0 := float(row_outer_wall_heights[i]) if i < row_outer_wall_heights.size() else outer_wall_height
		var wall_h1 := float(row_outer_wall_heights[ni]) if ni < row_outer_wall_heights.size() else outer_wall_height
		var wall_height := (wall_h0 + wall_h1) * 0.5
		if wall_height <= 0.0001:
			continue
		_append_outer_wall_segment(verts, normals, uvs, wall_indices, int(row0[0]), int(row1[0]), int(row0[2]), int(row1[2]), wall_height)
		_append_outer_wall_segment(verts, normals, uvs, wall_indices, int(row0[5]), int(row1[5]), int(row0[3]), int(row1[3]), wall_height)


func _append_outer_wall_segment(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	wall_indices: PackedInt32Array,
	top_idx_0: int,
	top_idx_1: int,
	inner_idx_0: int,
	inner_idx_1: int,
	wall_height: float
) -> void:
	if wall_height <= 0.0001:
		return
	var top0: Vector3 = verts[top_idx_0]
	var top1: Vector3 = verts[top_idx_1]
	if top0.distance_to(top1) <= 0.0001:
		return

	var inner0: Vector3 = verts[inner_idx_0]
	var inner1: Vector3 = verts[inner_idx_1]
	var outward := ((top0 - inner0) + (top1 - inner1)) * 0.5
	outward.y = 0.0
	if outward.length() < 0.001:
		var seg := top1 - top0
		outward = Vector3(seg.z, 0.0, -seg.x)
	if outward.length() < 0.001:
		outward = Vector3.RIGHT
	else:
		outward = outward.normalized()

	var bottom0 := top0 - Vector3.UP * wall_height
	var bottom1 := top1 - Vector3.UP * wall_height
	var seg_len := top0.distance_to(top1)
	var u_len := maxf(0.001, seg_len * uv_length_scale)
	var v_height := maxf(0.001, wall_height * uv_length_scale)

	var a := verts.size()
	verts.push_back(top0)
	normals.push_back(outward)
	uvs.push_back(Vector2(0.0, 0.0))

	var b := verts.size()
	verts.push_back(top1)
	normals.push_back(outward)
	uvs.push_back(Vector2(u_len, 0.0))

	var c := verts.size()
	verts.push_back(bottom0)
	normals.push_back(outward)
	uvs.push_back(Vector2(0.0, v_height))

	var d := verts.size()
	verts.push_back(bottom1)
	normals.push_back(outward)
	uvs.push_back(Vector2(u_len, v_height))

	_append_oriented_quad(wall_indices, verts, a, b, c, d, outward)


func _append_oriented_quad(
	indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	d: int,
	desired_normal: Vector3
) -> void:
	# Choose the more stable diagonal to avoid skipping entire side quads on near-degenerate setups.
	var area_abc := (verts[b] - verts[a]).cross(verts[c] - verts[a]).length_squared()
	var area_cbd := (verts[b] - verts[c]).cross(verts[d] - verts[c]).length_squared()
	var area_abd := (verts[b] - verts[a]).cross(verts[d] - verts[a]).length_squared()
	var area_adc := (verts[d] - verts[a]).cross(verts[c] - verts[a]).length_squared()
	if area_abc + area_cbd >= area_abd + area_adc:
		_append_oriented_triangle(indices, verts, a, b, c, desired_normal)
		_append_oriented_triangle(indices, verts, c, b, d, desired_normal)
	else:
		_append_oriented_triangle(indices, verts, a, b, d, desired_normal)
		_append_oriented_triangle(indices, verts, a, d, c, desired_normal)


func _append_oriented_triangle(
	indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	desired_normal: Vector3
) -> void:
	var tri_n := (verts[b] - verts[a]).cross(verts[c] - verts[a]).normalized()
	if tri_n.length_squared() < 0.000000000001:
		return
	if tri_n.dot(desired_normal) >= 0.0:
		indices.push_back(a)
		indices.push_back(b)
		indices.push_back(c)
	else:
		indices.push_back(a)
		indices.push_back(c)
		indices.push_back(b)


func _build_mesh(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	wall_indices: PackedInt32Array
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_surface(mesh, verts, normals, uvs, lane_indices, road_material_override if road_material_override != null else material_override)
	_add_surface(mesh, verts, normals, uvs, shoulder_indices, shoulder_material_override if shoulder_material_override != null else material_override)
	_add_surface(mesh, verts, normals, uvs, sidewalk_indices, sidewalk_material_override if sidewalk_material_override != null else material_override)
	_add_surface(
		mesh,
		verts,
		normals,
		uvs,
		wall_indices,
		outer_wall_material_override if outer_wall_material_override != null else (sidewalk_material_override if sidewalk_material_override != null else material_override)
	)
	return mesh


func _add_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	mat: Material
) -> void:
	if indices.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mat != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _resolve_path_width(path: Path3D, dist: float, length: float) -> float:
	var width := road_width
	if path != null and path.has_method("get_width_at_offset"):
		width = float(path.call("get_width_at_offset", dist))
	elif path != null and path.has_method("get_width_at_ratio"):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		width = float(path.call("get_width_at_ratio", ratio))
	return max(0.1, width)


func _resolve_path_shoulder_left(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_shoulder_left_at_offset",
		"get_shoulder_left_at_ratio",
		shoulder_left_width
	)


func _resolve_path_shoulder_right(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_shoulder_right_at_offset",
		"get_shoulder_right_at_ratio",
		shoulder_right_width
	)


func _resolve_path_sidewalk_left(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_left_at_offset",
		"get_sidewalk_left_at_ratio",
		sidewalk_left_width
	)


func _resolve_path_sidewalk_right(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_right_at_offset",
		"get_sidewalk_right_at_ratio",
		sidewalk_right_width
	)


func _resolve_path_sidewalk_height(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_height_at_offset",
		"get_sidewalk_height_at_ratio",
		sidewalk_height
	)


func _resolve_path_outer_wall_height(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_outer_wall_height_at_offset",
		"get_outer_wall_height_at_ratio",
		outer_wall_height
	)


func _resolve_path_component_width(
	path: Path3D,
	dist: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	fallback: float
) -> float:
	var value := maxf(0.0, fallback)
	if path != null and path.has_method(offset_method):
		value = float(path.call(offset_method, dist))
	elif path != null and path.has_method(ratio_method):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		value = float(path.call(ratio_method, ratio))
	return maxf(0.0, value)


func _build_signature() -> String:
	var path := _resolve_path()
	if path == null or path.curve == null:
		return "none"

	var curve := path.curve
	var parts: Array[String] = []
	parts.append(str(road_width))
	parts.append(str(sample_step))
	parts.append(str(y_offset))
	parts.append(str(shoulder_left_width))
	parts.append(str(shoulder_right_width))
	parts.append(str(sidewalk_left_width))
	parts.append(str(sidewalk_right_width))
	parts.append(str(sidewalk_height))
	parts.append(str(road_material_override))
	parts.append(str(shoulder_material_override))
	parts.append(str(sidewalk_material_override))
	parts.append(str(outer_wall_height))
	parts.append(str(outer_wall_material_override))
	parts.append(str(material_override))
	parts.append(str(uv_length_scale))
	parts.append(str(invert_faces))
	parts.append(str(path.global_transform))
	if path.has_method("get_width_profile_signature"):
		parts.append(str(path.call("get_width_profile_signature")))
	if path.has_method("get_edge_profile_signature"):
		parts.append(str(path.call("get_edge_profile_signature")))
	parts.append(str(curve.closed))
	parts.append(str(curve.point_count))

	for i in range(curve.point_count):
		parts.append(str(curve.get_point_position(i)))
		parts.append(str(curve.get_point_in(i)))
		parts.append(str(curve.get_point_out(i)))
		parts.append(str(curve.get_point_tilt(i)))

	return "|".join(parts)
