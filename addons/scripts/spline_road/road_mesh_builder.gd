@tool
extends RefCounted
## Road surfaces, normals and wall geometry.
## Configuration is captured before a generation job; the coordinator owns scene nodes.

var _road: Node

var road_material_override: Material
var shoulder_material_override: Material
var sidewalk_material_override: Material
var terrain_material_override: Material
var outer_wall_height := 0.0
var outer_wall_material_override: Material
var material_override: Material
var uv_length_scale := 0.2
var retain_output_arrays := false
var normal_cache_enabled := false
var normal_cache_stats: Array = []
var _normal_caches: Array = []
var _normal_surface_slot := 0
var direct_output_enabled := true

func configure(source: Node) -> void:
	_road = source
	road_material_override = source.get("road_material_override")
	shoulder_material_override = source.get("shoulder_material_override")
	sidewalk_material_override = source.get("sidewalk_material_override")
	terrain_material_override = source.get("terrain_material_override")
	outer_wall_height = source.get("outer_wall_height")
	outer_wall_material_override = source.get("outer_wall_material_override")
	material_override = source.get("material_override")
	uv_length_scale = source.get("uv_length_scale")
	retain_output_arrays = int(source.get("output_mode")) == 1
	normal_cache_enabled = bool(source.get("incremental_generation_enabled"))
	if not normal_cache_enabled:
		clear_incremental_cache()


func clear_incremental_cache() -> void:
	_normal_caches.clear()
	normal_cache_stats.clear()


func _append_outer_walls_from_path_rows(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	wall_indices: PackedInt32Array,
	path_rows: Array
) -> void:
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		if rows.size() < 2:
			continue
		for i in range(rows.size() - 1):
			var row0: Dictionary = rows[i]
			var row1: Dictionary = rows[i + 1]
			var e0: Array = row0.get("row_edges", [])
			var e1: Array = row1.get("row_edges", [])
			if e0.size() < 6 or e1.size() < 6:
				continue
			var wall_h0 := float(row0.get("outer_wall_height", outer_wall_height))
			var wall_h1 := float(row1.get("outer_wall_height", outer_wall_height))
			var wall_height := (wall_h0 + wall_h1) * 0.5
			if wall_height <= 0.0001:
				continue
			_append_outer_wall_segment(verts, normals, uvs, wall_indices, int(e0[0]), int(e1[0]), int(e0[2]), int(e1[2]), wall_height)
			_append_outer_wall_segment(verts, normals, uvs, wall_indices, int(e0[5]), int(e1[5]), int(e0[3]), int(e1[3]), wall_height)


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
	terrain_indices: PackedInt32Array,
	wall_indices: PackedInt32Array
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	normal_cache_stats.clear()
	if retain_output_arrays:
		# Give spatial output the CPU arrays before normal packing. Reading arrays
		# back from ArrayMesh and encoding them again introduces normal quantization.
		mesh.set_meta("_roda_output_arrays", [])
		if normal_cache_enabled and direct_output_enabled:
			# Spatial output consumes CPU arrays and materials. Do not upload a
			# complete temporary mesh whose node deliberately has no visible mesh.
			mesh.set_meta("_roda_direct_output", true)
			mesh.set_meta("_roda_output_materials", [])
	var profile_surface_start := _profile_start()
	_add_surface(mesh, verts, normals, uvs, lane_indices, road_material_override if road_material_override != null else material_override, true)
	_profile_log("build mesh surface lane", profile_surface_start, "indices=%s" % [lane_indices.size()])
	profile_surface_start = _profile_start()
	_add_surface(mesh, verts, normals, uvs, shoulder_indices, shoulder_material_override if shoulder_material_override != null else material_override, true)
	_profile_log("build mesh surface shoulder", profile_surface_start, "indices=%s" % [shoulder_indices.size()])
	profile_surface_start = _profile_start()
	_add_surface(mesh, verts, normals, uvs, sidewalk_indices, sidewalk_material_override if sidewalk_material_override != null else material_override, true)
	_profile_log("build mesh surface sidewalk", profile_surface_start, "indices=%s" % [sidewalk_indices.size()])
	profile_surface_start = _profile_start()
	_add_surface(
		mesh,
		verts,
		normals,
		uvs,
		terrain_indices,
		terrain_material_override if terrain_material_override != null else (sidewalk_material_override if sidewalk_material_override != null else material_override),
		true
	)
	_profile_log("build mesh surface terrain", profile_surface_start, "indices=%s" % [terrain_indices.size()])
	profile_surface_start = _profile_start()
	_add_surface(
		mesh,
		verts,
		normals,
		uvs,
		wall_indices,
		outer_wall_material_override if outer_wall_material_override != null else (sidewalk_material_override if sidewalk_material_override != null else material_override),
		false
	)
	_profile_log("build mesh surface outer walls", profile_surface_start, "indices=%s" % [wall_indices.size()])
	return mesh


func _add_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	mat: Material,
	force_upward_normals: bool = false
) -> void:
	if indices.is_empty():
		return
	_normal_surface_slot = mesh.get_meta("_roda_output_arrays").size() if mesh.has_meta("_roda_output_arrays") else mesh.get_surface_count()
	var surface_normals := _compute_surface_normals_from_indices(verts, indices, normals)
	if force_upward_normals:
		_force_normals_upward(surface_normals)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = surface_normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	if mesh.has_meta("_roda_output_arrays"):
		var output_arrays: Array = mesh.get_meta("_roda_output_arrays")
		output_arrays.append(arr)
	if mesh.get_meta("_roda_direct_output", false):
		var output_materials: Array = mesh.get_meta("_roda_output_materials")
		output_materials.append(mat)
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mat != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _compute_surface_normals_from_indices(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	fallback_normals: PackedVector3Array
) -> PackedVector3Array:
	if not normal_cache_enabled or _normal_surface_slot >= 5:
		return _compute_surface_normals_full(verts, indices, fallback_normals)
	while _normal_caches.size() <= _normal_surface_slot:
		_normal_caches.append(preload("./road_normal_cache.gd").new())
	var cache: RefCounted = _normal_caches[_normal_surface_slot]
	var result: PackedVector3Array = cache.compute(verts, indices, fallback_normals, _compute_surface_normals_full)
	while normal_cache_stats.size() <= _normal_surface_slot:
		normal_cache_stats.append({})
	normal_cache_stats[_normal_surface_slot] = cache.stats.duplicate()
	return result


func _compute_surface_normals_full(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	fallback_normals: PackedVector3Array
) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in range(out.size()):
		out[i] = Vector3.ZERO

	var tri_count := indices.size() - (indices.size() % 3)
	for i in range(0, tri_count, 3):
		var ia := int(indices[i])
		var ib := int(indices[i + 1])
		var ic := int(indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
			continue
		var n := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		if n.length_squared() <= 0.000000000001:
			continue
		out[ia] += n
		out[ib] += n
		out[ic] += n

	var have_fallback := fallback_normals.size() == verts.size()
	for i in range(out.size()):
		var n: Vector3 = out[i]
		if n.length_squared() > 0.000000000001:
			out[i] = n.normalized()
			continue
		if have_fallback:
			var f: Vector3 = fallback_normals[i]
			if f.length_squared() > 0.000000000001:
				out[i] = f.normalized()
				continue
		out[i] = Vector3.UP

	return out


func _force_normals_upward(surface_normals: PackedVector3Array) -> void:
	for i in range(surface_normals.size()):
		var n := surface_normals[i]
		if n.length_squared() <= 0.000000000001:
			continue
		if n.y < 0.0:
			surface_normals[i] = -n


# Typed entry points into the generation coordinator.
func _profile_start() -> int:
	return _road._profile_start()


func _profile_log(label: String, start_usec: int, extra: String = "") -> void:
	_road._profile_log(label, start_usec, extra)
