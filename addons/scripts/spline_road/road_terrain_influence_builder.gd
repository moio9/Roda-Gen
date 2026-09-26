@tool
extends RefCounted
## Terrain influence strip geometry, projection and height blending.
## Configuration is captured before a generation job; the coordinator owns scene nodes.

var _road: Node
var _standalone_lookup = preload("./road_terrain_builder.gd").new()
const TERRAIN_INFLUENCE_DEFAULT_WIDTH := 6.0
const TERRAIN_INFLUENCE_DEFAULT_BLEND := 3.0
const TERRAIN_INFLUENCE_DEFAULT_STRENGTH := 1.0
var sample_step := 0.5
var y_offset := 0.0
var terrain_fill_base_height := 0.0
var uv_length_scale := 0.2
var _terrain_influence_strips: Array = []

func configure(source: Node) -> void:
	_road = source
	sample_step = source.get("sample_step")
	y_offset = source.get("y_offset")
	terrain_fill_base_height = source.get("terrain_fill_base_height")
	uv_length_scale = source.get("uv_length_scale")
	_terrain_influence_strips = source.get("_terrain_influence_strips")


func _build_terrain_influence_strip(
	path: Path3D,
	curve: Curve3D,
	path_to_mesh: Transform3D,
	distances: PackedFloat32Array
) -> Dictionary:
	if path == null or curve == null or distances.size() < 2:
		return {}
	var width := TERRAIN_INFLUENCE_DEFAULT_WIDTH
	var blend := TERRAIN_INFLUENCE_DEFAULT_BLEND
	var strength := TERRAIN_INFLUENCE_DEFAULT_STRENGTH
	var band_count := 4
	var profile_curve := 1.0
	var profile_height := 0.0
	var profile_graph_samples := PackedFloat32Array()
	var generate_surface := true
	var allow_over_road := false
	var clip_base_terrain_by_loop := true
	var over_road_edge_snap_band := 0.0
	if path.has_method("get_terrain_influence_width"):
		width = maxf(0.2, float(path.call("get_terrain_influence_width")))
	if path.has_method("get_terrain_influence_flatten_blend"):
		blend = maxf(0.0, float(path.call("get_terrain_influence_flatten_blend")))
	if path.has_method("get_terrain_influence_flatten_strength"):
		strength = clampf(float(path.call("get_terrain_influence_flatten_strength")), 0.0, 1.0)
	if path.has_method("get_terrain_influence_band_count"):
		band_count = clampi(int(path.call("get_terrain_influence_band_count")), 1, 16)
	if path.has_method("get_terrain_influence_profile_curve"):
		profile_curve = maxf(0.2, float(path.call("get_terrain_influence_profile_curve")))
	if path.has_method("get_terrain_influence_profile_height"):
		profile_height = float(path.call("get_terrain_influence_profile_height"))
	if path.has_method("get_terrain_influence_profile_graph_samples"):
		profile_graph_samples = _to_packed_float32_array(path.call("get_terrain_influence_profile_graph_samples"))
	if path.has_method("should_generate_terrain_influence_surface"):
		generate_surface = bool(path.call("should_generate_terrain_influence_surface"))
	if path.has_method("get_over_road_edge_snap_band"):
		over_road_edge_snap_band = maxf(0.0, float(path.call("get_over_road_edge_snap_band")))
	if over_road_edge_snap_band > 0.0001:
		allow_over_road = true
	if path.has_method("should_clip_base_terrain_by_influence_loop"):
		clip_base_terrain_by_loop = bool(path.call("should_clip_base_terrain_by_influence_loop"))
	else:
		clip_base_terrain_by_loop = generate_surface
	var curve_length := maxf(0.001, curve.get_baked_length())
	var points := PackedVector3Array()
	points.resize(distances.size())
	var rights := PackedVector3Array()
	rights.resize(distances.size())
	var half_widths := PackedFloat32Array()
	half_widths.resize(distances.size())
	var profile_heights := PackedFloat32Array()
	profile_heights.resize(distances.size())
	var outer_half := PackedFloat32Array()
	outer_half.resize(distances.size())
	var max_half_width := width * 0.5
	for i in range(distances.size()):
		var dist := distances[i]
		var p_local := curve.sample_baked(dist, true)
		var p_mesh := path_to_mesh * p_local
		p_mesh.y += y_offset
		points[i] = p_mesh

		var prev_dist := maxf(0.0, dist - maxf(0.05, sample_step * 0.5))
		var next_dist := minf(curve.get_baked_length(), dist + maxf(0.05, sample_step * 0.5))
		var p_prev := path_to_mesh * curve.sample_baked(prev_dist, true)
		var p_next := path_to_mesh * curve.sample_baked(next_dist, true)
		var tangent := (p_next - p_prev).normalized()
		if tangent.length_squared() <= 0.000000000001:
			tangent = Vector3.FORWARD
		var up_local := _sample_curve_up_vector(curve, dist)
		var up_mesh := (path_to_mesh.basis * up_local).normalized()
		if up_mesh.length_squared() <= 0.000000000001:
			up_mesh = Vector3.UP
		var right := up_mesh.cross(tangent).normalized()
		if right.length_squared() <= 0.000000000001:
			right = Vector3.UP.cross(tangent).normalized()
		if right.length_squared() <= 0.000000000001:
			right = Vector3.RIGHT

		var prev_dir := (p_mesh - p_prev).normalized()
		var next_dir := (p_next - p_mesh).normalized()
		var corner_factor := 0.0
		if prev_dir.length_squared() > 0.000000000001 and next_dir.length_squared() > 0.000000000001:
			corner_factor = clampf((1.0 - prev_dir.dot(next_dir)) * 0.5, 0.0, 1.0)
		var width_at_dist := _resolve_path_component_width(
			path,
			dist,
			curve_length,
			"get_terrain_influence_width_at_offset",
			"get_terrain_influence_width_at_ratio",
			width
		)
		var profile_height_at_dist := _resolve_path_component_scalar(
			path,
			dist,
			curve_length,
			"get_terrain_influence_profile_height_at_offset",
			"get_terrain_influence_profile_height_at_ratio",
			profile_height
		)
		var local_half_width := maxf(0.1, width_at_dist * 0.5)
		rights[i] = right
		half_widths[i] = local_half_width
		profile_heights[i] = profile_height_at_dist
		max_half_width = maxf(max_half_width, local_half_width)
		outer_half[i] = local_half_width + blend * corner_factor

	var band_left_edges: Array = []
	var band_right_edges: Array = []
	var band_loops_raw: Array = []
	var band_loops: Array = []
	for band_idx in range(band_count):
		var band_t := float(band_idx + 1) / float(band_count)
		var profile_t := _semicircle_profile_t(band_t, profile_curve)
		var left_edge := PackedVector3Array()
		var right_edge := PackedVector3Array()
		left_edge.resize(points.size())
		right_edge.resize(points.size())
		for i in range(points.size()):
			# Semicircle cross-profile from centerline to outside (half-tube feel).
			var base_half := maxf(0.1, half_widths[i])
			var local_half := base_half + blend * profile_t + (outer_half[i] - base_half) * profile_t
			left_edge[i] = points[i] - rights[i] * local_half
			right_edge[i] = points[i] + rights[i] * local_half
		var smooth_band := blend * band_t
		left_edge = _smooth_open_edge_chain(left_edge, smooth_band)
		right_edge = _smooth_open_edge_chain(right_edge, smooth_band)
		var loop_raw := _build_capsule_loop_xz(points, left_edge, right_edge, band_count)
		var loop := _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() >= 3 and Geometry2D.is_polygon_clockwise(loop):
			loop.reverse()
			loop_raw.reverse()
		if loop.size() < 3 or loop_raw.size() < 3:
			continue
		band_left_edges.push_back(left_edge)
		band_right_edges.push_back(right_edge)
		band_loops_raw.push_back(loop_raw)
		band_loops.push_back(loop)

	var loop := PackedVector2Array()
	if not band_loops.is_empty():
		loop = band_loops[band_loops.size() - 1]
	var boundary_points := PackedVector3Array()
	for edge_raw in band_left_edges:
		var edge: PackedVector3Array = edge_raw
		for p in edge:
			boundary_points.push_back(p)
	for edge_raw in band_right_edges:
		var edge: PackedVector3Array = edge_raw
		for p in edge:
			boundary_points.push_back(p)
	return {
		"points": points,
		"rights": rights,
		"band_count": band_count,
		"band_left_edges": band_left_edges,
		"band_right_edges": band_right_edges,
		"band_loops_raw": band_loops_raw,
		"band_loops": band_loops,
		"loop": loop,
		"outer_vertex_ids": {},
		"boundary_points": boundary_points,
		"half_width": max_half_width,
		"half_widths": half_widths,
		"max_half_width": max_half_width,
		"blend": blend,
		"strength": strength,
		"profile_curve": profile_curve,
		"profile_height": profile_height,
		"profile_heights": profile_heights,
		"profile_graph_samples": profile_graph_samples,
		"generate_surface": generate_surface,
		"allow_over_road": allow_over_road,
		"over_road_edge_snap_band": over_road_edge_snap_band,
		"clip_base_terrain_by_loop": clip_base_terrain_by_loop,
	}


func _build_capsule_loop_xz(
	centers: PackedVector3Array,
	left_edge: PackedVector3Array,
	right_edge: PackedVector3Array,
	band_count: int
) -> PackedVector2Array:
	var loop := PackedVector2Array()
	if centers.size() < 2 or left_edge.size() != centers.size() or right_edge.size() != centers.size():
		return loop

	for p in left_edge:
		loop.push_back(Vector2(p.x, p.z))

	var end_idx := centers.size() - 1
	var end_center := Vector2(centers[end_idx].x, centers[end_idx].z)
	var end_prev := Vector2(centers[end_idx - 1].x, centers[end_idx - 1].z)
	var end_tangent := (end_center - end_prev).normalized()
	if end_tangent.length_squared() <= 0.000000000001:
		end_tangent = Vector2(0.0, 1.0)
	var end_right := Vector2(right_edge[end_idx].x, right_edge[end_idx].z) - end_center
	var end_radius := end_right.length()
	if end_radius > 0.0001:
		var end_cap_steps := clampi(6 + band_count * 2, 8, 48)
		for step in range(1, end_cap_steps):
			var t := float(step) / float(end_cap_steps)
			var angle := lerpf(-PI * 0.5, PI * 0.5, t)
			var dir := end_tangent * cos(angle) + end_right.normalized() * sin(angle)
			loop.push_back(end_center + dir * end_radius)

	for i in range(right_edge.size() - 1, -1, -1):
		var p := right_edge[i]
		loop.push_back(Vector2(p.x, p.z))

	var start_center := Vector2(centers[0].x, centers[0].z)
	var start_next := Vector2(centers[1].x, centers[1].z)
	var start_tangent := (start_next - start_center).normalized()
	if start_tangent.length_squared() <= 0.000000000001:
		start_tangent = Vector2(0.0, 1.0)
	var start_right := Vector2(right_edge[0].x, right_edge[0].z) - start_center
	var start_radius := start_right.length()
	if start_radius > 0.0001:
		var start_cap_steps := clampi(6 + band_count * 2, 8, 48)
		for step in range(1, start_cap_steps):
			var t := float(step) / float(start_cap_steps)
			var angle := lerpf(PI * 0.5, -PI * 0.5, t)
			var dir := -start_tangent * cos(angle) + start_right.normalized() * sin(angle)
			loop.push_back(start_center + dir * start_radius)

	return loop


func _semicircle_profile_t(t: float, curve: float = 1.0) -> float:
	var x := clampf(t, 0.0, 1.0)
	x = pow(x, maxf(0.2, curve))
	var inv := 1.0 - x
	return sqrt(maxf(0.0, 1.0 - inv * inv))


func _terrain_influence_cross_profile(
	dist_t: float,
	curve: float,
	graph_samples: PackedFloat32Array = PackedFloat32Array()
) -> float:
	var x := clampf(dist_t, 0.0, 1.0)
	if graph_samples.size() >= 2:
		var max_idx := graph_samples.size() - 1
		var f := x * float(max_idx)
		var i0 := int(floor(f))
		var i1 = min(i0 + 1, max_idx)
		var a := f - float(i0)
		return clampf(lerpf(float(graph_samples[i0]), float(graph_samples[i1]), a), 0.0, 1.0)
	if x >= 0.999999:
		return 0.0
	var shaped := pow(x, maxf(0.2, curve))
	return sqrt(maxf(0.0, 1.0 - shaped * shaped))


func _smooth_open_edge_chain(points: PackedVector3Array, blend: float) -> PackedVector3Array:
	if points.size() < 3 or blend <= 0.0001:
		return points
	var out := points
	var passes := clampi(int(floor(blend / maxf(0.2, sample_step))), 1, 4)
	var factor := clampf(blend / maxf(0.001, blend + 1.0), 0.1, 0.75)
	for _pass in range(passes):
		var src := out
		var dst := src
		for i in range(1, src.size() - 1):
			var avg := (src[i - 1] + src[i] + src[i + 1]) / 3.0
			dst[i] = src[i].lerp(avg, factor)
		out = dst
	return out


func _append_terrain_influence_fill_faces(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	strips: Array = [],
	cancel_token: Dictionary = {}
) -> void:
	var strips_ref: Array = strips
	if strips_ref.is_empty():
		strips_ref = _terrain_influence_strips
	if strips_ref.is_empty():
		return
	for strip_idx in range(strips_ref.size()):
		if _is_generation_cancelled(cancel_token):
			return
		var strip: Dictionary = strips_ref[strip_idx]
		if not strip.has("segment_lookup"):
			strip["segment_lookup"] = _build_terrain_influence_segment_lookup(strip)
		var outer_vertex_ids: Dictionary = {}
		if not bool(strip.get("generate_surface", true)):
			strip["outer_vertex_ids"] = outer_vertex_ids
			strips_ref[strip_idx] = strip
			continue
		var band_loops_data: Array = strip.get("band_loops_raw", [])
		if band_loops_data.is_empty():
			band_loops_data = strip.get("band_loops", [])
		if band_loops_data.is_empty():
			var fallback_loop: PackedVector2Array = strip.get("loop", PackedVector2Array())
			_append_terrain_influence_loop_fill(strip, fallback_loop, PackedVector2Array(), verts, normals, uvs, terrain_indices, cancel_token)
			strip["outer_vertex_ids"] = outer_vertex_ids
			strips_ref[strip_idx] = strip
			continue
		# Use the exact clipping loop for the outer ring to avoid T-junction seams.
		var clip_loop: PackedVector2Array = strip.get("loop", PackedVector2Array())
		var use_clip_loop := clip_loop.size() >= 3
		var loops: Array = []
		var maps: Array = []
		for li in range(band_loops_data.size()):
			if _is_generation_cancelled(cancel_token):
				return
			var loop: PackedVector2Array = band_loops_data[li]
			if use_clip_loop and li == band_loops_data.size() - 1:
				loop = clip_loop
			if loop.size() < 3:
				continue
			loops.push_back(loop)
			var force_flat_edge := use_clip_loop and li == band_loops_data.size() - 1
			var local_to_global := _append_terrain_influence_loop_vertices(strip, loop, verts, normals, uvs, force_flat_edge, cancel_token)
			if _is_generation_cancelled(cancel_token):
				return
			if local_to_global.size() != loop.size():
				return
			maps.push_back(local_to_global)
			if force_flat_edge:
				for vid_raw in local_to_global:
					outer_vertex_ids[int(vid_raw)] = true
		if loops.is_empty():
			strip["outer_vertex_ids"] = outer_vertex_ids
			strips_ref[strip_idx] = strip
			continue
		_append_terrain_influence_loop_triangulation(loops[0], maps[0], verts, terrain_indices, cancel_token)
		if _is_generation_cancelled(cancel_token):
			return
		for li in range(1, loops.size()):
			if _is_generation_cancelled(cancel_token):
				return
			var inner_loop: PackedVector2Array = loops[li - 1]
			var outer_loop: PackedVector2Array = loops[li]
			var inner_map: PackedInt32Array = maps[li - 1]
			var outer_map: PackedInt32Array = maps[li]
			if inner_loop.size() != outer_loop.size():
				_append_terrain_influence_loop_fill(strip, outer_loop, inner_loop, verts, normals, uvs, terrain_indices, cancel_token)
				continue
			_append_terrain_influence_loop_bridge(inner_map, outer_map, verts, terrain_indices, cancel_token)
		strip["outer_vertex_ids"] = outer_vertex_ids
		strips_ref[strip_idx] = strip


func _append_terrain_influence_loop_vertices(
	strip: Dictionary,
	loop: PackedVector2Array,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	force_flat_edge: bool = false,
	cancel_token: Dictionary = {}
) -> PackedInt32Array:
	var local_to_global := PackedInt32Array()
	local_to_global.resize(loop.size())
	for i in range(loop.size()):
		if (i % 128) == 0 and _is_generation_cancelled(cancel_token):
			return PackedInt32Array()
		var p2 := loop[i]
		var y := _sample_terrain_influence_centerline_height(strip, p2)
		if force_flat_edge:
			y = _sample_terrain_influence_centerline_base_height(strip, p2)
		var p3 := Vector3(p2.x, y, p2.y)
		local_to_global[i] = verts.size()
		verts.push_back(p3)
		normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(p3.x, p3.z) * uv_length_scale)
	return local_to_global


func _append_terrain_influence_loop_triangulation(
	loop: PackedVector2Array,
	local_to_global: PackedInt32Array,
	verts: PackedVector3Array,
	terrain_indices: PackedInt32Array,
	cancel_token: Dictionary = {}
) -> void:
	if loop.size() < 3 or local_to_global.size() != loop.size():
		return
	var tri_local: PackedInt32Array = Geometry2D.triangulate_polygon(loop)
	if tri_local.size() < 3:
		return
	var tri_count := tri_local.size() - (tri_local.size() % 3)
	for i in range(0, tri_count, 3):
		if (i % 384) == 0 and _is_generation_cancelled(cancel_token):
			return
		var ia := int(tri_local[i])
		var ib := int(tri_local[i + 1])
		var ic := int(tri_local[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= local_to_global.size() or ib >= local_to_global.size() or ic >= local_to_global.size():
			continue
		var ga := int(local_to_global[ia])
		var gb := int(local_to_global[ib])
		var gc := int(local_to_global[ic])
		_append_terrain_triangle_indices(terrain_indices, verts, ga, gb, gc)


func _append_terrain_influence_loop_bridge(
	inner_map: PackedInt32Array,
	outer_map: PackedInt32Array,
	verts: PackedVector3Array,
	terrain_indices: PackedInt32Array,
	cancel_token: Dictionary = {}
) -> void:
	var count := inner_map.size()
	if count < 3 or outer_map.size() != count:
		return
	for i in range(count):
		if (i % 128) == 0 and _is_generation_cancelled(cancel_token):
			return
		var ni := (i + 1) % count
		var ii := int(inner_map[i])
		var inx := int(inner_map[ni])
		var oi := int(outer_map[i])
		var onx := int(outer_map[ni])
		_append_terrain_triangle_indices(terrain_indices, verts, ii, oi, onx)
		_append_terrain_triangle_indices(terrain_indices, verts, ii, onx, inx)


func _append_terrain_influence_loop_fill(
	strip: Dictionary,
	loop_raw: PackedVector2Array,
	inner_loop_raw: PackedVector2Array,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	cancel_token: Dictionary = {}
) -> void:
	var loop := _compact_polygon2d_xz(loop_raw, 0.001)
	if loop.size() < 3:
		return
	var inner_loop := _compact_polygon2d_xz(inner_loop_raw, 0.001)
	var has_inner := inner_loop.size() >= 3
	var tri_local: PackedInt32Array = Geometry2D.triangulate_polygon(loop)
	if tri_local.size() < 3:
		return
	var local_to_global := PackedInt32Array()
	local_to_global.resize(loop.size())
	for i in range(loop.size()):
		if (i % 128) == 0 and _is_generation_cancelled(cancel_token):
			return
		var p2 := loop[i]
		var y := _sample_terrain_influence_centerline_height(strip, p2)
		var p3 := Vector3(p2.x, y, p2.y)
		local_to_global[i] = verts.size()
		verts.push_back(p3)
		normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(p3.x, p3.z) * uv_length_scale)
	var tri_count := tri_local.size() - (tri_local.size() % 3)
	for i in range(0, tri_count, 3):
		if (i % 384) == 0 and _is_generation_cancelled(cancel_token):
			return
		var ia := int(tri_local[i])
		var ib := int(tri_local[i + 1])
		var ic := int(tri_local[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= local_to_global.size() or ib >= local_to_global.size() or ic >= local_to_global.size():
			continue
		if has_inner:
			var centroid := (loop[ia] + loop[ib] + loop[ic]) / 3.0
			if Geometry2D.is_point_in_polygon(centroid, inner_loop):
				continue
		var ga := int(local_to_global[ia])
		var gb := int(local_to_global[ib])
		var gc := int(local_to_global[ic])
		_append_terrain_triangle_indices(terrain_indices, verts, ga, gb, gc)


func _sample_terrain_influence_centerline_height(strip: Dictionary, point: Vector2) -> float:
	var projection := _sample_terrain_influence_projection(strip, point)
	if not bool(projection.get("valid", false)):
		return terrain_fill_base_height + y_offset
	var base_y := float(projection.get("y", terrain_fill_base_height + y_offset))
	var half_width := maxf(0.0, float(projection.get("half_width", strip.get("half_width", 0.0))))
	var blend := maxf(0.0, float(strip.get("blend", 0.0)))
	var max_dist := maxf(0.0001, half_width + blend)
	var profile_curve := maxf(0.2, float(strip.get("profile_curve", 1.0)))
	var profile_height := float(projection.get("profile_height", strip.get("profile_height", 0.0)))
	var profile_graph_samples: PackedFloat32Array = strip.get("profile_graph_samples", PackedFloat32Array())
	var best_dist := float(projection.get("dist", INF))
	var dist_t := clampf(best_dist / max_dist, 0.0, 1.0)
	var profile_peak := _terrain_influence_cross_profile(dist_t, profile_curve, profile_graph_samples)
	return base_y + profile_height * profile_peak


func _sample_terrain_influence_centerline_base_height(strip: Dictionary, point: Vector2) -> float:
	var projection := _sample_terrain_influence_projection(strip, point)
	return float(projection.get("y", terrain_fill_base_height + y_offset))


func _sample_terrain_influence_projection(strip: Dictionary, point: Vector2) -> Dictionary:
	var points: PackedVector3Array = strip.get("points", PackedVector3Array())
	var fallback_half := maxf(0.0, float(strip.get("half_width", 0.0)))
	var fallback_profile_height := float(strip.get("profile_height", 0.0))
	if points.size() < 2:
		return {
			"valid": false,
			"dist": INF,
			"y": terrain_fill_base_height + y_offset,
			"half_width": fallback_half,
		"profile_height": fallback_profile_height,
	}
	var half_widths: PackedFloat32Array = strip.get("half_widths", PackedFloat32Array())
	var profile_heights: PackedFloat32Array = strip.get("profile_heights", PackedFloat32Array())
	var max_half_width := maxf(fallback_half, float(strip.get("max_half_width", fallback_half)))
	var blend := maxf(0.0, float(strip.get("blend", 0.0)))
	var segment_lookup: Dictionary = strip.get("segment_lookup", {})
	var segment_ids := _collect_segment_lookup_source_ids(point, segment_lookup, maxf(0.25, max_half_width + blend))
	if segment_ids.is_empty() and not segment_lookup.is_empty():
		return {
			"valid": false,
			"dist": INF,
			"y": terrain_fill_base_height + y_offset,
			"half_width": fallback_half,
			"profile_height": fallback_profile_height,
		}
	var segment_count := segment_ids.size() if not segment_ids.is_empty() else points.size() - 1
	var best_dist := INF
	var best_y := points[0].y
	var best_half := fallback_half
	var best_profile_height := fallback_profile_height
	for segment_idx in range(segment_count):
		var i := int(segment_ids[segment_idx]) if not segment_ids.is_empty() else segment_idx
		if i < 0 or i + 1 >= points.size():
			continue
		var a := points[i]
		var b := points[i + 1]
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var t := _closest_point_param_on_segment_2d(point, a2, b2)
		var c := a2.lerp(b2, t)
		var d := point.distance_to(c)
		if d >= best_dist:
			continue
		best_dist = d
		best_y = lerpf(a.y, b.y, t)
		var half_a := fallback_half
		var half_b := fallback_half
		if i < half_widths.size():
			half_a = maxf(0.0, float(half_widths[i]))
		if i + 1 < half_widths.size():
			half_b = maxf(0.0, float(half_widths[i + 1]))
		best_half = lerpf(half_a, half_b, t)
		var profile_a := fallback_profile_height
		var profile_b := fallback_profile_height
		if i < profile_heights.size():
			profile_a = float(profile_heights[i])
		if i + 1 < profile_heights.size():
			profile_b = float(profile_heights[i + 1])
		best_profile_height = lerpf(profile_a, profile_b, t)
	return {
		"valid": true,
		"dist": best_dist,
		"y": best_y,
		"half_width": best_half,
		"profile_height": best_profile_height,
	}


func _build_terrain_influence_segment_lookup(strip: Dictionary) -> Dictionary:
	var points: PackedVector3Array = strip.get("points", PackedVector3Array())
	if points.size() < 2:
		return {}
	var max_half_width := maxf(0.0, float(strip.get("max_half_width", strip.get("half_width", 0.0))))
	var blend := maxf(0.0, float(strip.get("blend", 0.0)))
	var max_dist := maxf(0.25, max_half_width + blend)
	var segments: Array = []
	for i in range(points.size() - 1):
		var a3: Vector3 = points[i]
		var b3: Vector3 = points[i + 1]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		if a.distance_to(b) <= 0.0001:
			continue
		segments.push_back({
			"a": a,
			"b": b,
			"min": Vector2(minf(a.x, b.x), minf(a.y, b.y)),
			"max": Vector2(maxf(a.x, b.x), maxf(a.y, b.y)),
			"source_idx": i,
		})
	return _build_2d_segment_distance_lookup(segments, max_dist)


func _apply_terrain_influence_strips_to_mesh(
	verts: PackedVector3Array,
	terrain_indices: PackedInt32Array,
	strips: Array = [],
	over_road_snap_context: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	var strips_ref: Array = strips
	if strips_ref.is_empty():
		strips_ref = _terrain_influence_strips
	if strips_ref.is_empty() or terrain_indices.is_empty():
		return
	var over_road_zones: Array = over_road_snap_context.get("zones", [])
	var road_snap_segments: Array = over_road_snap_context.get("segments", [])
	var road_snap_grid: Dictionary = over_road_snap_context.get("grid", {})
	var road_snap_cell_size := maxf(0.05, float(over_road_snap_context.get("cell_size", 0.25)))
	var road_snap_max_dist := maxf(0.05, float(over_road_snap_context.get("max_snap_dist", 0.25)))
	var can_snap_over_road := not over_road_zones.is_empty() and not road_snap_segments.is_empty() and not road_snap_grid.is_empty()
	var prepared_strips: Array = []
	for strip_raw in strips_ref:
		if _is_generation_cancelled(cancel_token):
			return
		var prepared_strip: Dictionary = strip_raw
		prepared_strip = prepared_strip.duplicate(true)
		prepared_strip["segment_lookup"] = _build_terrain_influence_segment_lookup(prepared_strip)
		prepared_strips.push_back(prepared_strip)
	var terrain_vertex_ids: Dictionary = {}
	for idx_i in range(terrain_indices.size()):
		if (idx_i % 1024) == 0 and _is_generation_cancelled(cancel_token):
			return
		var idx_raw := terrain_indices[idx_i]
		var idx := int(idx_raw)
		if idx >= 0 and idx < verts.size():
			terrain_vertex_ids[idx] = true
	var terrain_vertex_keys := terrain_vertex_ids.keys()
	for key_i in range(terrain_vertex_keys.size()):
		if (key_i % 256) == 0 and _is_generation_cancelled(cancel_token):
			return
		var idx_key = terrain_vertex_keys[key_i]
		var vi := int(idx_key)
		var p := verts[vi]
		var p2 := Vector2(p.x, p.z)
		p.y = sample_prepared_height(p, prepared_strips, vi, cancel_token)
		if can_snap_over_road:
			var zone_match := false
			for zone_raw in over_road_zones:
				var zone: Dictionary = zone_raw
				var loop: PackedVector2Array = zone.get("loop", PackedVector2Array())
				if loop.size() < 3 or not Geometry2D.is_point_in_polygon(p2, loop):
					continue
				var zone_segments: Array = zone.get("edge_segments", [])
				var zone_grid: Dictionary = zone.get("edge_grid", {})
				if zone_segments.is_empty() or zone_grid.is_empty():
					continue
				var zone_edge_cell_size := maxf(0.01, float(zone.get("edge_cell_size", 0.25)))
				var zone_edge_band := maxf(0.01, float(zone.get("edge_band", 0.35)))
				var near_edge := _sample_nearest_segment_height_2d(
					p2,
					zone_segments,
					zone_grid,
					zone_edge_cell_size,
					zone_edge_band
				)
				if not bool(near_edge.get("found", false)):
					continue
				zone_match = true
				break
			if not zone_match:
				verts[vi] = p
				continue
			var nearest := _sample_nearest_segment_height_2d(
				p2,
				road_snap_segments,
				road_snap_grid,
				road_snap_cell_size,
				road_snap_max_dist
			)
			if bool(nearest.get("found", false)):
				var road_y := float(nearest.get("y", p.y))
				p.y = road_y
		verts[vi] = p


func _closest_point_param_on_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.000000000001:
		return 0.0
	return clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)


# Typed entry points into the generation coordinator.
func _is_generation_cancelled(cancel_token: Dictionary) -> bool:
	if cancel_token.is_empty():
		return false
	return _road._is_generation_cancelled(cancel_token)


func _append_terrain_triangle_indices(
	terrain_indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int
) -> void:
	_road._append_terrain_triangle_indices(terrain_indices, verts, a, b, c)


func _compact_polygon2d_xz(poly: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	return _road._compact_polygon2d_xz(poly, epsilon)


func _sample_nearest_segment_height_2d(
	point: Vector2,
	segments: Array,
	grid: Dictionary,
	cell_size: float,
	max_dist: float
) -> Dictionary:
	return _road._sample_nearest_segment_height_2d(point, segments, grid, cell_size, max_dist)


func _build_2d_segment_distance_lookup(segments: Array, cell_size_hint: float) -> Dictionary:
	return _standalone_lookup._build_2d_segment_distance_lookup(segments, cell_size_hint) if _road == null else _road._build_2d_segment_distance_lookup(segments, cell_size_hint)


func _collect_segment_lookup_source_ids(point: Vector2, lookup: Dictionary, radius: float) -> Array:
	return _standalone_lookup._collect_segment_lookup_source_ids(point, lookup, radius) if _road == null else _road._collect_segment_lookup_source_ids(point, lookup, radius)


func _to_packed_float32_array(value: Variant) -> PackedFloat32Array:
	return _road._to_packed_float32_array(value)


func _resolve_path_component_width(
	path: Path3D,
	dist: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	fallback: float
) -> float:
	return _road._resolve_path_component_width(path, dist, length, offset_method, ratio_method, fallback)


func _resolve_path_component_scalar(
	path: Path3D,
	dist: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	fallback: float
) -> float:
	return _road._resolve_path_component_scalar(path, dist, length, offset_method, ratio_method, fallback)


func _sample_curve_up_vector(curve: Curve3D, dist: float) -> Vector3:
	return _road._sample_curve_up_vector(curve, dist)


## Shared height evaluation for built-in and standalone terrain.
func sample_prepared_height(p: Vector3, prepared_strips: Array, vi := -1, cancel_token: Dictionary = {}) -> float:
	var p2 := Vector2(p.x, p.z)
	var best_weight := 0.0
	var best_target_y := p.y
	for strip_raw in prepared_strips:
		var strip: Dictionary = strip_raw
		var outer_vertex_ids: Dictionary = strip.get("outer_vertex_ids", {})
		var lock_outer_vertex := bool(outer_vertex_ids.get(vi, false))
		var points: PackedVector3Array = strip.get("points", PackedVector3Array())
		if points.size() < 2:
			continue
		var half_widths: PackedFloat32Array = strip.get("half_widths", PackedFloat32Array())
		var max_half_width := maxf(0.0, float(strip.get("max_half_width", strip.get("half_width", 0.0))))
		var blend := maxf(0.0, float(strip.get("blend", 0.0)))
		var strength := clampf(float(strip.get("strength", 1.0)), 0.0, 1.0)
		var profile_curve := maxf(0.2, float(strip.get("profile_curve", 1.0)))
		var profile_height := float(strip.get("profile_height", 0.0))
		var profile_heights: PackedFloat32Array = strip.get("profile_heights", PackedFloat32Array())
		var profile_graph_samples: PackedFloat32Array = strip.get("profile_graph_samples", PackedFloat32Array())
		var max_dist := max_half_width + blend
		if max_dist <= 0.0001 or strength <= 0.0001:
			continue
		var segment_lookup: Dictionary = strip.get("segment_lookup", {})
		var segment_ids := _collect_segment_lookup_source_ids(p2, segment_lookup, max_dist)
		if segment_ids.is_empty() and not segment_lookup.is_empty():
			continue
		var segment_count := segment_ids.size() if not segment_ids.is_empty() else points.size() - 1
		for segment_idx in range(segment_count):
			if (segment_idx % 64) == 0 and _is_generation_cancelled(cancel_token):
				return p.y
			var i := int(segment_ids[segment_idx]) if not segment_ids.is_empty() else segment_idx
			if i < 0 or i + 1 >= points.size():
				continue
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var a2 := Vector2(a.x, a.z)
			var b2 := Vector2(b.x, b.z)
			var t := _closest_point_param_on_segment_2d(p2, a2, b2)
			var closest := a2.lerp(b2, t)
			var dist := p2.distance_to(closest)
			var local_half_width := max_half_width
			if i < half_widths.size():
				local_half_width = maxf(0.0, float(half_widths[i]))
			if i + 1 < half_widths.size():
				local_half_width = lerpf(local_half_width, maxf(0.0, float(half_widths[i + 1])), t)
			var local_profile_height := profile_height
			if i < profile_heights.size():
				local_profile_height = float(profile_heights[i])
			if i + 1 < profile_heights.size():
				local_profile_height = lerpf(local_profile_height, float(profile_heights[i + 1]), t)
			var local_max_dist := local_half_width + blend
			if local_max_dist <= 0.0001 or dist > local_max_dist:
				continue
			var edge_weight := 1.0
			if blend > 0.0001 and dist > local_half_width:
				edge_weight = 1.0 - clampf((dist - local_half_width) / blend, 0.0, 1.0)
			elif dist > local_half_width:
				edge_weight = 0.0
			if edge_weight <= 0.0001:
				continue
			edge_weight = edge_weight * edge_weight * (3.0 - 2.0 * edge_weight)
			edge_weight *= strength
			if edge_weight <= best_weight:
				continue
			best_weight = edge_weight
			var dist_t := clampf(dist / local_max_dist, 0.0, 1.0)
			var profile_peak := _terrain_influence_cross_profile(dist_t, profile_curve, profile_graph_samples)
			if lock_outer_vertex:
				profile_peak = 0.0
			best_target_y = lerpf(a.y, b.y, t) + local_profile_height * profile_peak
	if best_weight > 0.0001:
		p.y = lerpf(p.y, best_target_y, best_weight)
	return p.y
