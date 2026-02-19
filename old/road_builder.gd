@tool
extends Node3D

@export_group("Source Paths")
@export var source_paths: Array[NodePath] = []
@export var source_path: NodePath
@export_subgroup("Per-Path Settings")
@export var enable_per_path_overrides := true

@export_group("Global Defaults")
@export_range(0.5, 30.0, 0.1) var road_width := 6.0
@export_range(0.5, 50.0, 0.1) var sample_step := 6.0
@export var adaptive_sampling := true
@export_range(0.0, 2.0, 0.01) var y_offset := 0.02
@export_subgroup("Road Edges")
@export_range(0.0, 15.0, 0.1) var shoulder_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var shoulder_right_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_right_width := 0.0
@export var material_override: Material

@export_group("Intersections")
@export_subgroup("Merge Base")
@export var enable_junction_merge := true
@export_range(0.1, 30.0, 0.1) var junction_snap_distance := 3.0
@export_range(0, 36, 1) var junction_endpoint_blend_points := 3

@export_subgroup("Flatten")
@export var enable_junction_height_flatten := true
@export_range(0.2, 40.0, 0.1) var junction_height_flatten_radius := 6.0
@export_range(0.0, 1.0, 0.01) var junction_height_flatten_strength := 1.0

@export_subgroup("Recap Mode")
@export var enable_intersection_recap := false
@export_enum("Legacy Ring", "Boolean Union", "Vertex Weld") var intersection_recap_mode := 0
@export_range(0.1, 20.0, 0.01) var intersection_fill_radius := 3.0
@export_range(0.5, 3.0) var intersection_recap_radius_scale := 1.2
@export_range(4, 56, 1) var intersection_recap_bins := 40

@export_subgroup("Fill")
@export_range(0.0, 3.0, 0.01) var intersection_seam_cleanup_margin := 0.18
@export var enable_dead_end_seam_bridge := true
@export var enable_global_mesh_repair := true
@export var enable_global_parallel_seam_stitch := true

@export_subgroup("Boolean Mode")
@export var boolean_recap_fallback_to_legacy := true
@export_range(12, 96, 1) var boolean_recap_circle_steps := 40
@export_range(0.6, 2.0, 0.05) var boolean_recap_clip_scale := 1.15
@export var boolean_recap_linear_caps := true
@export_range(0.8, 3.0, 0.05) var boolean_recap_arm_half_width_scale := 1.35
@export var boolean_recap_distance_stitch := true
@export_range(0.0, 5.0, 0.01) var boolean_recap_stitch_gap_max := 0.0
@export_range(0.0, 2.0, 0.01) var boolean_recap_spike_cleanup := 0.0

@export_subgroup("Vertex Weld Mode")
@export_range(0.02, 5.0, 0.01) var vertex_weld_distance := 0.45
@export_range(0.0, 1.0, 0.01) var vertex_weld_blend := 0.5
@export_range(0.02, 5.0, 0.01) var vertex_weld_projection_width := 0.65
@export var vertex_weld_allow_near_intersections := false

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_generate_on_ready := true
@export var auto_regenerate_on_change := true
@export_subgroup("Manual Trigger")
@export var regenerate_button := false: set = _set_regenerate_button

@export_group("Debug")
@export var debug_show_mesh_copy := false: set = _set_debug_show_mesh_copy
@export_range(0.0, 50.0, 0.1) var debug_mesh_copy_height := 4.0: set = _set_debug_mesh_copy_height
@export var debug_show_repair_overlay := false: set = _set_debug_show_repair_overlay
@export var debug_show_recap_contours := false: set = _set_debug_show_recap_contours
@export_range(0.0, 10.0, 0.01) var debug_repair_overlay_height := 0.03: set = _set_debug_repair_overlay_height

const MESH_NODE_NAME := "GeneratedRoadMesh"
const DEBUG_MESH_NODE_NAME := "GeneratedRoadMeshDebug"
const DEBUG_REPAIR_NODE_NAME := "GeneratedRoadMeshRepairDebug"
const RECAP_MODE_LEGACY := 0
const RECAP_MODE_BOOLEAN := 1
const RECAP_MODE_VERTEX_WELD := 2
var _is_ready := false
var _regenerate_queued := false
var _last_weld_hints: Array = []
var _debug_boundary_segments: Array = []
var _debug_dead_end_points: Array = []
var _debug_recap_contours: Array = []
var _debug_removed_tri_centers: Array = []
var _debug_added_tri_centers: Array = []


func _ready() -> void:
	_is_ready = true
	if auto_generate_on_ready and _can_generate():
		regenerate()


func _set_regenerate_button(value: bool) -> void:
	regenerate_button = false
	if value and _can_generate():
		regenerate()


func _set_debug_show_mesh_copy(value: bool) -> void:
	debug_show_mesh_copy = value
	if not value:
		_clear_debug_mesh_copy()
		return
	var mi: MeshInstance3D = get_node_or_null(MESH_NODE_NAME)
	if mi != null and mi.mesh is ArrayMesh:
		_sync_debug_mesh_copy(mi.mesh, _last_weld_hints)


func _set_debug_mesh_copy_height(value: float) -> void:
	debug_mesh_copy_height = value
	var copy: MeshInstance3D = get_node_or_null(DEBUG_MESH_NODE_NAME)
	if copy != null:
		copy.position = Vector3(0.0, debug_mesh_copy_height, 0.0)


func _set_debug_show_repair_overlay(value: bool) -> void:
	debug_show_repair_overlay = value
	if not value:
		_clear_debug_repair_overlay()
		return
	var mi: MeshInstance3D = get_node_or_null(MESH_NODE_NAME)
	if mi != null and mi.mesh is ArrayMesh:
		_sync_debug_repair_overlay(mi.mesh)


func _set_debug_show_recap_contours(value: bool) -> void:
	debug_show_recap_contours = value
	if not debug_show_repair_overlay:
		return
	var mi: MeshInstance3D = get_node_or_null(MESH_NODE_NAME)
	if mi != null and mi.mesh is ArrayMesh:
		_sync_debug_repair_overlay(mi.mesh)


func _set_debug_repair_overlay_height(value: float) -> void:
	debug_repair_overlay_height = value
	var root: Node3D = get_node_or_null(DEBUG_REPAIR_NODE_NAME)
	if root != null:
		root.position = Vector3(0.0, debug_repair_overlay_height, 0.0)


func _can_generate() -> bool:
	return not Engine.is_editor_hint() or generate_in_editor


func _queue_regenerate() -> void:
	if not _is_ready:
		return
	if not Engine.is_editor_hint():
		return
	if not auto_regenerate_on_change:
		return
	if not _can_generate():
		return
	if _regenerate_queued:
		return
	_regenerate_queued = true
	call_deferred("_run_queued_regenerate")


func _run_queued_regenerate() -> void:
	_regenerate_queued = false
	if not is_inside_tree():
		return
	if not _can_generate():
		return
	regenerate()


func regenerate() -> void:
	_debug_boundary_segments.clear()
	_debug_dead_end_points.clear()
	_debug_recap_contours.clear()
	_debug_removed_tri_centers.clear()
	_debug_added_tri_centers.clear()

	var paths := _resolve_source_paths()
	if paths.is_empty():
		push_warning("No Path3D source found.")
		_clear_mesh_node()
		return

	var sampled := _sample_paths(paths)
	if sampled.is_empty():
		push_warning("Sampled path data is empty.")
		_clear_mesh_node()
		return

	var weld_hints: Array = []
	if enable_junction_merge:
		var prep := _apply_junction_merges(sampled)
		sampled = prep["paths"]
		weld_hints = prep["weld_hints"]
		if enable_junction_height_flatten:
			sampled = _flatten_junction_heights(sampled, weld_hints)

	var mesh := _build_mesh_from_paths(sampled)
	if intersection_recap_mode == RECAP_MODE_VERTEX_WELD:
		mesh = _apply_intersection_vertex_weld(mesh, sampled)
	elif enable_intersection_recap:
		if intersection_recap_mode == RECAP_MODE_BOOLEAN and enable_junction_merge:
			mesh = _apply_intersection_recap_boolean(mesh, sampled, weld_hints)
		elif enable_junction_merge:
			mesh = _apply_intersection_recap(mesh, weld_hints)
	if enable_global_mesh_repair:
		mesh = _apply_global_mesh_repair(mesh)
	_last_weld_hints = weld_hints.duplicate(true)
	_assign_mesh(mesh)
	_sync_debug_mesh_copy(mesh, _last_weld_hints)
	_sync_debug_repair_overlay(mesh)
	if debug_show_repair_overlay:
		print(
			"[RoadBuilder][DebugOverlay] boundary=", _debug_boundary_segments.size(),
			" dead_ends=", _debug_dead_end_points.size(),
			" removed=", _debug_removed_tri_centers.size(),
			" added=", _debug_added_tri_centers.size(),
			" recap_contours=", _debug_recap_contours.size(),
			" junction_merge=", enable_junction_merge,
			" recap=", enable_intersection_recap,
			" recap_mode=", intersection_recap_mode
		)


func _resolve_source_paths() -> Array:
	var result: Array = []
	for p in source_paths:
		var n := get_node_or_null(p)
		if n is Path3D:
			result.append(n)
	if result.is_empty() and source_path != NodePath():
		var single := get_node_or_null(source_path)
		if single is Path3D:
			result.append(single)
	return result


func _sample_paths(paths: Array) -> Array:
	var out: Array = []
	for p in paths:
		var settings := _get_path_settings(p)
		var curve: Curve3D = p.curve
		if curve == null or curve.point_count < 2:
			continue
		var len := curve.get_baked_length()
		if len <= 0.001:
			continue
		var local_step: float = float(settings.get("sample_step", sample_step))
		var local_y_offset: float = float(settings.get("y_offset", y_offset))
		var local_width: float = float(settings.get("road_width", road_width))
		var local_shoulder_left: float = maxf(0.0, float(settings.get("shoulder_left_width", shoulder_left_width)))
		var local_shoulder_right: float = maxf(0.0, float(settings.get("shoulder_right_width", shoulder_right_width)))
		var local_sidewalk_left: float = maxf(0.0, float(settings.get("sidewalk_left_width", sidewalk_left_width)))
		var local_sidewalk_right: float = maxf(0.0, float(settings.get("sidewalk_right_width", sidewalk_right_width)))
		var local_use_profiles: bool = settings.get("use_per_point_profiles", false) == true
		var local_profile_widths: PackedFloat32Array = settings.get("per_point_widths", PackedFloat32Array())
		var local_profile_banks_deg: PackedFloat32Array = settings.get("per_point_bank_degrees", PackedFloat32Array())
		var distances := _build_sample_distances(curve, len, local_step)
		var count := distances.size()
		var pts: Array = []
		var widths: Array = []
		var lane_widths: Array = []
		var banks_rad: Array = []
		var side_extra := local_shoulder_left + local_shoulder_right + local_sidewalk_left + local_sidewalk_right
		for i in range(count):
			var d := float(distances[i])
			var world = p.global_transform * curve.sample_baked(d, true)
			world.y += local_y_offset
			pts.append(world)
			var t_norm := float(i) / maxf(1.0, float(count - 1))
			var lane_width := local_width
			if local_use_profiles:
				var sampled_w := _sample_control_profile(local_profile_widths, t_norm, local_width)
				var sampled_bank_deg := _sample_control_profile(local_profile_banks_deg, t_norm, 0.0)
				lane_width = maxf(0.2, sampled_w)
				widths.append(maxf(0.2, lane_width + side_extra))
				banks_rad.append(deg_to_rad(sampled_bank_deg))
			else:
				lane_width = maxf(0.2, local_width)
				widths.append(maxf(0.2, lane_width + side_extra))
				banks_rad.append(0.0)
			lane_widths.append(lane_width)
		if curve.closed and pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) < 0.001:
			pts.remove_at(pts.size() - 1)
			widths.remove_at(widths.size() - 1)
			lane_widths.remove_at(lane_widths.size() - 1)
			banks_rad.remove_at(banks_rad.size() - 1)
		out.append({
			"points": pts,
			"widths": widths,
			"lane_widths": lane_widths,
			"shoulder_left_width": local_shoulder_left,
			"shoulder_right_width": local_shoulder_right,
			"sidewalk_left_width": local_sidewalk_left,
			"sidewalk_right_width": local_sidewalk_right,
			"banks_rad": banks_rad,
			"closed": curve.closed,
		})
	return out


func _build_mesh_from_paths(path_data: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if material_override:
		st.set_material(material_override)

	for data in path_data:
		var points: Array = data["points"]
		var widths: Array = data["widths"]
		var lane_widths: Array = data.get("lane_widths", widths)
		var shoulder_left: float = maxf(0.0, float(data.get("shoulder_left_width", shoulder_left_width)))
		var shoulder_right: float = maxf(0.0, float(data.get("shoulder_right_width", shoulder_right_width)))
		var sidewalk_left: float = maxf(0.0, float(data.get("sidewalk_left_width", sidewalk_left_width)))
		var sidewalk_right: float = maxf(0.0, float(data.get("sidewalk_right_width", sidewalk_right_width)))
		var banks: Array = data["banks_rad"]
		var closed: bool = data["closed"]
		if points.size() < 2:
			continue

		var count := points.size()
		var tangents: Array = []
		tangents.resize(count)
		for i in range(count):
			var prev_i := i - 1
			var next_i := i + 1
			if closed:
				prev_i = (i - 1 + count) % count
				next_i = (i + 1) % count
			else:
				prev_i = maxi(0, i - 1)
				next_i = mini(count - 1, i + 1)
			var t = (points[next_i] - points[prev_i]).normalized()
			if t.length_squared() < 0.000001:
				t = Vector3.FORWARD
			tangents[i] = t

		var rights: Array = []
		rights.resize(count)
		var right_prev := _safe_right_from_dir_and_up(tangents[0], Vector3.UP)
		rights[0] = right_prev
		for i in range(1, count):
			var f_prev: Vector3 = tangents[i - 1]
			var f_cur: Vector3 = tangents[i]
			var axis := f_prev.cross(f_cur)
			var right_cur := right_prev
			if axis.length_squared() > 0.0000001:
				var axis_n := axis.normalized()
				var angle := atan2(axis.length(), clampf(f_prev.dot(f_cur), -1.0, 1.0))
				right_cur = right_prev.rotated(axis_n, angle)
			right_cur = (right_cur - f_cur * right_cur.dot(f_cur)).normalized()
			if right_cur.length_squared() < 0.000001:
				right_cur = _safe_right_from_dir_and_up(f_cur, Vector3.UP)
			rights[i] = right_cur
			right_prev = right_cur

		var banked_rights: Array = []
		banked_rights.resize(count)
		var half_lane_widths: Array = []
		half_lane_widths.resize(count)
		var side_extra := shoulder_left + shoulder_right + sidewalk_left + sidewalk_right
		for i in range(count):
			var f: Vector3 = tangents[i]
			var r: Vector3 = rights[i]
			var bank := float(banks[i]) if i < banks.size() else 0.0
			if absf(bank) > 0.000001:
				r = r.rotated(f, bank).normalized()
			banked_rights[i] = r
			var lane_w := road_width
			if i < widths.size():
				lane_w = maxf(0.2, float(widths[i]) - side_extra)
			elif i < lane_widths.size():
				lane_w = maxf(0.2, float(lane_widths[i]))
			half_lane_widths[i] = lane_w * 0.5

		var seg_count := count if closed else count - 1
		for i in range(seg_count):
			var ni := (i + 1) % count
			var p0: Vector3 = points[i]
			var p1: Vector3 = points[ni]
			if p0.distance_to(p1) < 0.001:
				continue
			var r0: Vector3 = banked_rights[i]
			var r1: Vector3 = banked_rights[ni]
			var lane_hw0: float = float(half_lane_widths[i])
			var lane_hw1: float = float(half_lane_widths[ni])
			var left_lane0 := p0 - r0 * lane_hw0
			var right_lane0 := p0 + r0 * lane_hw0
			var left_lane1 := p1 - r1 * lane_hw1
			var right_lane1 := p1 + r1 * lane_hw1

			var left_shoulder0 := p0 - r0 * (lane_hw0 + shoulder_left)
			var left_shoulder1 := p1 - r1 * (lane_hw1 + shoulder_left)
			var right_shoulder0 := p0 + r0 * (lane_hw0 + shoulder_right)
			var right_shoulder1 := p1 + r1 * (lane_hw1 + shoulder_right)

			var left_outer0 := p0 - r0 * (lane_hw0 + shoulder_left + sidewalk_left)
			var left_outer1 := p1 - r1 * (lane_hw1 + shoulder_left + sidewalk_left)
			var right_outer0 := p0 + r0 * (lane_hw0 + shoulder_right + sidewalk_right)
			var right_outer1 := p1 + r1 * (lane_hw1 + shoulder_right + sidewalk_right)

			_add_quad(st, left_lane0, right_lane0, right_lane1, left_lane1)

			if shoulder_left > 0.0:
				_add_quad(st, left_shoulder0, left_lane0, left_lane1, left_shoulder1)
			if shoulder_right > 0.0:
				_add_quad(st, right_lane0, right_shoulder0, right_shoulder1, right_lane1)
			if sidewalk_left > 0.0:
				_add_quad(st, left_outer0, left_shoulder0, left_shoulder1, left_outer1)
			if sidewalk_right > 0.0:
				_add_quad(st, right_shoulder0, right_outer0, right_outer1, right_shoulder1)

	st.generate_normals()
	var mesh := st.commit()
	return mesh if mesh != null else ArrayMesh.new()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(st, a, b, c)
	_add_triangle(st, a, c, d)


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.length_squared() < 0.000001:
		n = Vector3.UP
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _apply_junction_merges(path_data: Array) -> Dictionary:
	var out: Array = []
	for d in path_data:
		out.append((d as Dictionary).duplicate(true))

	var endpoints: Array = []
	for p_idx in range(out.size()):
		var data: Dictionary = out[p_idx]
		var pts: Array = data["points"]
		if data["closed"] or pts.size() < 2:
			continue
		endpoints.append({"path_idx": p_idx, "is_start": true})
		endpoints.append({"path_idx": p_idx, "is_start": false})

	var used := {}
	var weld_hints: Array = []

	# Phase 1: endpoint clusters (2+ endpoints meeting in one junction).
	var pairs: Array = []
	for i in range(endpoints.size()):
		for j in range(i + 1, endpoints.size()):
			var a: Dictionary = endpoints[i]
			var b: Dictionary = endpoints[j]
			if int(a["path_idx"]) == int(b["path_idx"]):
				continue
			var pa := _endpoint_pos(out, a)
			var pb := _endpoint_pos(out, b)
			var d := _dist_xz(pa, pb)
			if d <= junction_snap_distance:
				pairs.append({"a": i, "b": j})
	var clusters := _build_endpoint_clusters(endpoints.size(), pairs)

	for cluster_raw in clusters:
		var cluster: Array = cluster_raw
		var merged := Vector3.ZERO
		for idx_raw in cluster:
			var idx := int(idx_raw)
			var e: Dictionary = endpoints[idx]
			merged += _endpoint_pos(out, e)
		if cluster.is_empty():
			continue
		merged /= float(cluster.size())
		for idx_raw in cluster:
			var idx := int(idx_raw)
			var e: Dictionary = endpoints[idx]
			_move_endpoint_with_blend(out, e, merged)
			weld_hints.append({"pos": merged, "dir": _endpoint_dir(out, e)})
			used[idx] = true

	# Phase 2: endpoint to segment for unmatched endpoints.
	for i in range(endpoints.size()):
		if used.has(i):
			continue
		var e: Dictionary = endpoints[i]
		var e_path_idx := int(e["path_idx"])
		var e_pos := _endpoint_pos(out, e)
		var best_dist := INF
		var best_pos := e_pos
		var best_dir := Vector3.FORWARD
		var best_side := 0.0
		var best_half_width := road_width * 0.5
		for p_idx in range(out.size()):
			if p_idx == e_path_idx:
				continue
			var d: Dictionary = out[p_idx]
			var pts: Array = d["points"]
			if pts.size() < 2:
				continue
			var hit_edge: Dictionary = _closest_path_pair_snap_xz(d, e_pos)
			var dist := float(hit_edge.get("dist", INF))
			if dist < best_dist and dist <= junction_snap_distance:
				best_dist = dist
				best_pos = Vector3(hit_edge.get("center_pos", hit_edge.get("pos", e_pos)))
				best_dir = Vector3(hit_edge.get("dir", Vector3.FORWARD))
				best_side = float(hit_edge.get("side_sign", 0.0))
				best_half_width = float(hit_edge.get("half_width", road_width * 0.5))
		if best_dist < INF:
			_move_endpoint_with_blend(out, e, best_pos)
			if best_half_width > 0.0:
				_move_endpoint_width_with_blend(out, e, best_half_width)
			weld_hints.append({"pos": best_pos, "dir": best_dir, "passive_side": best_side})

	return {"paths": out, "weld_hints": weld_hints}


func _build_endpoint_clusters(endpoint_count: int, pairs: Array) -> Array:
	if endpoint_count <= 1 or pairs.is_empty():
		return []

	var adjacency: Array = []
	adjacency.resize(endpoint_count)
	for i in range(endpoint_count):
		adjacency[i] = []

	for pair in pairs:
		var a := int(pair["a"])
		var b := int(pair["b"])
		if a < 0 or b < 0 or a >= endpoint_count or b >= endpoint_count:
			continue
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)

	var seen := {}
	var clusters: Array = []
	for i in range(endpoint_count):
		if seen.has(i):
			continue
		var neigh: Array = adjacency[i]
		if neigh.is_empty():
			continue
		var queue: Array = [i]
		var component: Array = []
		seen[i] = true
		while not queue.is_empty():
			var cur := int(queue.pop_back())
			component.append(cur)
			for n_raw in adjacency[cur]:
				var n := int(n_raw)
				if seen.has(n):
					continue
				seen[n] = true
				queue.append(n)
		if component.size() > 1:
			clusters.append(component)
	return clusters


func _endpoint_pos(path_data: Array, endpoint: Dictionary) -> Vector3:
	var data: Dictionary = path_data[int(endpoint["path_idx"])]
	var pts: Array = data["points"]
	if bool(endpoint["is_start"]):
		return pts[0]
	return pts[pts.size() - 1]


func _endpoint_dir(path_data: Array, endpoint: Dictionary) -> Vector3:
	var data: Dictionary = path_data[int(endpoint["path_idx"])]
	var pts: Array = data["points"]
	if pts.size() < 2:
		return Vector3.FORWARD
	if bool(endpoint["is_start"]):
		return (pts[1] - pts[0]).normalized()
	return (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()


func _closest_path_pair_snap_xz(path_data: Dictionary, query_pos: Vector3) -> Dictionary:
	var pts: Array = path_data["points"]
	var widths: Array = path_data["widths"]
	var closed := bool(path_data["closed"])
	var count := pts.size()
	if count < 2:
		return {"center_pos": query_pos, "dist": INF}

	var seg_count := count if closed else count - 1
	var best_dist := INF
	var best_center := query_pos
	var best_left := query_pos
	var best_right := query_pos
	var best_dir := Vector3.FORWARD
	var best_side := 0.0
	var best_hw := road_width * 0.5

	for s in range(seg_count):
		if not closed and count > 3 and (s == 0 or s == seg_count - 1):
			continue
		var i0 := s
		var i1 := (s + 1) % count
		var a: Vector3 = pts[i0]
		var b: Vector3 = pts[i1]
		if _dist_xz(a, b) < 0.0001:
			continue
		var hit := _closest_point_on_segment_xz(query_pos, a, b)
		var seg_t := float(hit["t"])
		var c: Vector3 = hit["pos"]
		var t0 := _path_tangent_at(pts, i0, closed)
		var t1 := _path_tangent_at(pts, i1, closed)
		var t := t0.lerp(t1, seg_t).normalized()
		if t.length_squared() < 0.000001:
			t = (b - a).normalized()
		if t.length_squared() < 0.000001:
			t = Vector3.FORWARD
		var r := _safe_right_from_dir_and_up(t, Vector3.UP)
		var hw0 := road_width * 0.5
		var hw1 := road_width * 0.5
		if i0 < widths.size():
			hw0 = maxf(0.1, float(widths[i0]) * 0.5)
		if i1 < widths.size():
			hw1 = maxf(0.1, float(widths[i1]) * 0.5)
		var hw := lerpf(hw0, hw1, seg_t)
		var left := c - r * hw
		var right := c + r * hw
		var dl := _dist_xz(query_pos, left)
		var dr := _dist_xz(query_pos, right)
		var d := minf(dl, dr)
		if d < best_dist:
			best_dist = d
			best_center = c
			best_left = left
			best_right = right
			best_dir = t
			best_side = -1.0 if dl < dr else 1.0
			best_hw = hw

	return {
		"center_pos": best_center,
		"left_pos": best_left,
		"right_pos": best_right,
		"dist": best_dist,
		"dir": best_dir,
		"side_sign": best_side,
		"half_width": best_hw,
	}


func _nearest_path_data_index(path_data: Array, query_pos: Vector3) -> int:
	if path_data.is_empty():
		return -1
	var best_idx := 0
	var best_dist := INF
	for i in range(path_data.size()):
		var pd: Dictionary = path_data[i]
		var snap := _closest_path_pair_snap_xz(pd, query_pos)
		var d := float(snap.get("dist", INF))
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func _path_tangent_at(points: Array, i: int, closed: bool) -> Vector3:
	var count := points.size()
	if count < 2:
		return Vector3.FORWARD
	var prev_i := i - 1
	var next_i := i + 1
	if closed:
		prev_i = (i - 1 + count) % count
		next_i = (i + 1) % count
	else:
		prev_i = maxi(0, i - 1)
		next_i = mini(count - 1, i + 1)
	var t = (points[next_i] - points[prev_i]).normalized()
	if t.length_squared() < 0.000001:
		return Vector3.FORWARD
	return t


func _flatten_junction_heights(path_data: Array, weld_hints: Array) -> Array:
	if path_data.is_empty() or weld_hints.is_empty():
		return path_data
	var radius := maxf(0.2, junction_height_flatten_radius)
	var strength := clampf(junction_height_flatten_strength, 0.0, 1.0)
	if strength <= 0.0:
		return path_data
	var centers := _collect_unique_hint_centers(weld_hints)
	if centers.is_empty():
		return path_data

	for c_raw in centers:
		var c: Vector3 = c_raw
		var y_sum := 0.0
		var y_count := 0
		for data_raw in path_data:
			var data: Dictionary = data_raw
			var pts: Array = data["points"]
			for p_raw in pts:
				var p: Vector3 = p_raw
				if _dist_xz(p, c) <= radius:
					y_sum += p.y
					y_count += 1
		if y_count == 0:
			continue
		var target_y := y_sum / float(y_count)

		for data_raw in path_data:
			var data: Dictionary = data_raw
			var pts: Array = data["points"]
			for i in range(pts.size()):
				var p: Vector3 = pts[i]
				var d := _dist_xz(p, c)
				if d > radius:
					continue
				var w := (1.0 - d / radius) * strength
				p.y = lerpf(p.y, target_y, w)
				pts[i] = p

	return path_data


func _apply_intersection_recap(mesh: ArrayMesh, weld_hints: Array) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0 or weld_hints.is_empty():
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return mesh
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return mesh

	var tris: Array = []
	for i in range(0, verts.size(), 3):
		if i + 2 >= verts.size():
			break
		tris.append([verts[i], verts[i + 1], verts[i + 2]])
	if tris.is_empty():
		return mesh

	var centers := _collect_unique_hint_centers(weld_hints)
	if centers.is_empty():
		return mesh

	var any_change := false
	for c_raw in centers:
		var c: Vector3 = c_raw
		var patch_radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
		var updated := _recap_single_intersection_patch(tris, c, patch_radius)
		if bool(updated.get("changed", false)):
			tris = updated["tris"]
			any_change = true

	if not any_change:
		return mesh
	tris = _cleanup_triangles(tris)
	tris = _fill_small_boundary_holes_near_intersections(tris, centers)
	if boolean_recap_distance_stitch:
		tris = _stitch_parallel_seam_gaps_near_intersections(tris, centers)
	if enable_dead_end_seam_bridge:
		tris = _bridge_dead_end_seams_near_intersections(tris, centers)
	return _mesh_from_triangles(tris)


func _apply_intersection_recap_boolean(mesh: ArrayMesh, path_data: Array, weld_hints: Array) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0 or weld_hints.is_empty():
		return mesh
	if path_data.is_empty():
		return _apply_intersection_recap(mesh, weld_hints) if boolean_recap_fallback_to_legacy else mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return mesh
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return mesh

	var tris: Array = []
	for i in range(0, verts.size(), 3):
		if i + 2 >= verts.size():
			break
		tris.append([verts[i], verts[i + 1], verts[i + 2]])
	if tris.is_empty():
		return mesh

	var centers := _collect_unique_hint_centers(weld_hints)
	if centers.is_empty():
		return mesh

	var any_change := false
	for c_raw in centers:
		var c: Vector3 = c_raw
		var patch_radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
		var updated := _boolean_recap_single_patch(tris, path_data, c, patch_radius)
		if bool(updated.get("changed", false)):
			tris = updated["tris"]
			any_change = true

	if not any_change:
		return _apply_intersection_recap(mesh, weld_hints) if boolean_recap_fallback_to_legacy else mesh

	tris = _cleanup_triangles(tris)
	tris = _fill_small_boundary_holes_near_intersections(tris, centers)
	if boolean_recap_distance_stitch:
		tris = _stitch_parallel_seam_gaps_near_intersections(tris, centers)
	if enable_dead_end_seam_bridge:
		tris = _bridge_dead_end_seams_near_intersections(tris, centers)
	return _mesh_from_triangles(tris)


func _apply_intersection_vertex_weld(mesh: ArrayMesh, path_data: Array) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	if path_data.is_empty():
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return mesh
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return mesh

	var tris: Array = []
	for i in range(0, verts.size(), 3):
		if i + 2 >= verts.size():
			break
		tris.append([verts[i], verts[i + 1], verts[i + 2]])
	if tris.is_empty():
		return mesh

	var centers := _collect_intersection_centers_from_paths(path_data)
	if centers.is_empty():
		return mesh

	var weld_dist := maxf(0.02, vertex_weld_distance)
	var blend := clampf(vertex_weld_blend, 0.0, 1.0)
	var proj_width := maxf(0.02, vertex_weld_projection_width)
	var any_change := false
	for c_raw in centers:
		var c: Vector3 = c_raw
		var updated := _vertex_weld_single_intersection_patch(tris, path_data, c, weld_dist, blend, proj_width)
		if bool(updated.get("changed", false)):
			tris = updated["tris"]
			any_change = true

	if not any_change:
		return mesh

	tris = _cleanup_triangles(tris)
	return _mesh_from_triangles(tris)


func _vertex_weld_single_intersection_patch(tris: Array, path_data: Array, center: Vector3, weld_dist: float, blend: float, proj_width: float) -> Dictionary:
	if tris.is_empty():
		return {"changed": false, "tris": tris}

	const VERTEX_QUANT := 320.0
	var segments := _extract_boundary_segments_xz(tris, VERTEX_QUANT)
	if segments.is_empty():
		return {"changed": false, "tris": tris}

	var center_radius := weld_dist * 3.5
	var max_pair_dist := weld_dist * 2.2
	var max_mid_dist := weld_dist * 2.2
	var max_y_delta := weld_dist * 2.2

	var key_pos := {}
	var local_segments: Array = []
	var local_adj := {}
	for s_raw in segments:
		var s: Dictionary = s_raw
		var mid: Vector3 = s["mid"]
		if _dist_xz(mid, center) > center_radius:
			continue
		var ka := str(s["ka"])
		var kb := str(s["kb"])
		var pa: Vector3 = s["a"]
		var pb: Vector3 = s["b"]
		key_pos[ka] = pa
		key_pos[kb] = pb
		if not local_adj.has(ka):
			local_adj[ka] = []
		if not local_adj.has(kb):
			local_adj[kb] = []
		var a_ns: Array = local_adj[ka]
		if not a_ns.has(kb):
			a_ns.append(kb)
			local_adj[ka] = a_ns
		var b_ns: Array = local_adj[kb]
		if not b_ns.has(ka):
			b_ns.append(ka)
			local_adj[kb] = b_ns
		local_segments.append(s)
	if local_segments.size() < 2:
		return {"changed": false, "tris": tris}

	var merge_map := {}
	var merge_anchor := {}
	var mapped_segments := 0
	for i in range(local_segments.size()):
		var s1: Dictionary = local_segments[i]
		var best_j := -1
		var best_map := 0
		var best_score := INF
		for j in range(i + 1, local_segments.size()):
			var s2: Dictionary = local_segments[j]
			var ka1 := str(s1["ka"])
			var kb1 := str(s1["kb"])
			var ka2 := str(s2["ka"])
			var kb2 := str(s2["kb"])
			if ka1 == ka2 or ka1 == kb2 or kb1 == ka2 or kb1 == kb2:
				continue

			var dir1: Vector2 = s1["dir"]
			var dir2: Vector2 = s2["dir"]
			var parallel := absf(dir1.dot(dir2))
			if parallel < 0.78:
				continue

			var mid_d := _dist_xz(Vector3(s1["mid"]), Vector3(s2["mid"]))
			if mid_d > max_mid_dist:
				continue

			var a1: Vector3 = s1["a"]
			var b1: Vector3 = s1["b"]
			var a2: Vector3 = s2["a"]
			var b2: Vector3 = s2["b"]
			var d_ac := _dist_xz(a1, a2)
			var d_bd := _dist_xz(b1, b2)
			var d_ad := _dist_xz(a1, b2)
			var d_bc := _dist_xz(b1, a2)
			var map0_max := maxf(d_ac, d_bd)
			var map1_max := maxf(d_ad, d_bc)
			var map := 0
			var score := d_ac + d_bd
			var pair_max := map0_max
			if d_ad + d_bc < score:
				map = 1
				score = d_ad + d_bc
				pair_max = map1_max
			if pair_max > max_pair_dist:
				continue
			if absf(a1.y - a2.y) > max_y_delta and absf(a1.y - b2.y) > max_y_delta:
				continue

			score = score / maxf(0.001, parallel) + mid_d * 0.22
			if score < best_score:
				best_score = score
				best_j = j
				best_map = map

		if best_j == -1:
			continue
		var sa: Dictionary = s1
		var sb: Dictionary = local_segments[best_j]
		var a_a: Vector3 = sa["a"]
		var a_b: Vector3 = sa["b"]
		var b_a: Vector3 = sb["a"]
		var b_b: Vector3 = sb["b"]
		var bka := str(sb["ka"])
		var bkb := str(sb["kb"])
		if best_map == 1:
			var t := b_a
			b_a = b_b
			b_b = t
			var tk := bka
			bka = bkb
			bkb = tk

		var sa_mid: Vector3 = sa["mid"]
		var sb_mid: Vector3 = sb["mid"]
		var snap_a := _closest_path_pair_snap_xz(path_data[_nearest_path_data_index(path_data, sa_mid)], sa_mid) if not path_data.is_empty() else {"half_width": float(sa["len"]) * 0.5}
		var snap_b := _closest_path_pair_snap_xz(path_data[_nearest_path_data_index(path_data, sb_mid)], sb_mid) if not path_data.is_empty() else {"half_width": float(sb["len"]) * 0.5}
		var width_a := float(snap_a.get("half_width", float(sa["len"]) * 0.5))
		var width_b := float(snap_b.get("half_width", float(sb["len"]) * 0.5))
		var active_is_a := width_a >= width_b
		if absf(width_a - width_b) < 0.05:
			active_is_a = float(sa["len"]) >= float(sb["len"])
		var act0 := a_a if active_is_a else b_a
		var act1 := a_b if active_is_a else b_b
		var pas0 := b_a if active_is_a else a_a
		var pas1 := b_b if active_is_a else a_b
		var act0_key := str(sa["ka"]) if active_is_a else bka
		var act1_key := str(sa["kb"]) if active_is_a else bkb
		var pas0_key := bka if active_is_a else str(sa["ka"])
		var pas1_key := bkb if active_is_a else str(sa["kb"])

		var target0 := pas0.lerp(act0, blend)
		var target1 := pas1.lerp(act1, blend)
		merge_map[pas0_key] = target0
		merge_map[pas1_key] = target1
		merge_anchor[pas0_key] = pas0
		merge_anchor[pas1_key] = pas1

		var passive_chain_keys := _collect_passive_chain_keys(local_adj, key_pos, pas0_key, pas1_key, pas0, pas1, proj_width)
		var chain_len_total := 0.0
		var chain_acc := {}
		if passive_chain_keys.size() >= 2:
			chain_acc[str(passive_chain_keys[0])] = 0.0
			for ci in range(1, passive_chain_keys.size()):
				var pk_prev := str(passive_chain_keys[ci - 1])
				var pk_cur := str(passive_chain_keys[ci])
				if not key_pos.has(pk_prev) or not key_pos.has(pk_cur):
					continue
				chain_len_total += _dist_xz(Vector3(key_pos[pk_prev]), Vector3(key_pos[pk_cur]))
				chain_acc[pk_cur] = chain_len_total
		for k_raw in passive_chain_keys:
			var k := str(k_raw)
			if k == pas0_key or k == pas1_key:
				continue
			if k == act0_key or k == act1_key:
				continue
			if not key_pos.has(k):
				continue
			var p: Vector3 = key_pos[k]
			var tseg := 0.0
			if chain_len_total > 0.000001 and chain_acc.has(k):
				tseg = clampf(float(chain_acc[k]) / chain_len_total, 0.0, 1.0)
			else:
				var hit := _closest_point_on_segment_xz(p, pas0, pas1)
				tseg = clampf(float(hit.get("t", 0.0)), 0.0, 1.0)
			var on_active := act0.lerp(act1, tseg)
			var projected := p.lerp(on_active, blend)
			merge_map[k] = projected
			merge_anchor[k] = p
		mapped_segments += 1

	if mapped_segments < 1 or merge_map.is_empty():
		return {"changed": false, "tris": tris}

	var out: Array = []
	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var new_tri: Array = []
		for p_raw in tri:
			var p: Vector3 = p_raw
			if _dist_xz(p, center) > center_radius * 1.6:
				new_tri.append(p)
				continue
			var k := _quantized_vertex_key_xz(p, VERTEX_QUANT)
			if merge_map.has(k):
				var anchor: Vector3 = Vector3(merge_anchor.get(k, p))
				var near_anchor_xz := _dist_xz(p, anchor) <= maxf(0.03, weld_dist * 0.9)
				var near_anchor_y := absf(p.y - anchor.y) <= maxf(0.08, max_y_delta * 0.9)
				if not near_anchor_xz or not near_anchor_y:
					new_tri.append(p)
					continue
				new_tri.append(Vector3(merge_map[k]))
			else:
				new_tri.append(p)
		if new_tri.size() == 3:
			out.append(new_tri)

	if debug_show_repair_overlay:
		for k_raw in merge_map.keys():
			var mk := str(k_raw)
			_debug_push_point(_debug_added_tri_centers, Vector3(merge_map[mk]))
	return {"changed": true, "tris": out}


func _apply_global_mesh_repair(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return mesh
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return mesh

	var tris: Array = []
	for i in range(0, verts.size(), 3):
		if i + 2 >= verts.size():
			break
		tris.append([verts[i], verts[i + 1], verts[i + 2]])
	if tris.is_empty():
		return mesh

	tris = _cleanup_triangles(tris)
	var centers := _collect_boundary_repair_centers_xz(tris)
	if not centers.is_empty():
		tris = _fill_small_boundary_holes_near_intersections(tris, centers)
	if enable_global_parallel_seam_stitch:
		tris = _stitch_parallel_seam_gaps_global(tris)
	if enable_dead_end_seam_bridge:
		tris = _bridge_dead_end_seams_near_intersections(tris, [])
	tris = _cleanup_triangles(tris)
	return _mesh_from_triangles(tris)


func _collect_boundary_repair_centers_xz(tris: Array) -> Array:
	if tris.is_empty():
		return []

	const VERTEX_QUANT := 260.0
	var vertex_accum := {}
	var edge_counts := {}
	var edge_verts := {}

	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var vkeys: Array = []
		for p_raw in tri:
			var p: Vector3 = p_raw
			var vk := _quantized_vertex_key_xz(p, VERTEX_QUANT)
			if not vertex_accum.has(vk):
				vertex_accum[vk] = {"sum": p, "count": 1}
			else:
				var acc: Dictionary = vertex_accum[vk]
				acc["sum"] = Vector3(acc["sum"]) + p
				acc["count"] = int(acc["count"]) + 1
				vertex_accum[vk] = acc
			vkeys.append(vk)

		var e01 := _edge_key_from_vertex_keys(str(vkeys[0]), str(vkeys[1]))
		var e12 := _edge_key_from_vertex_keys(str(vkeys[1]), str(vkeys[2]))
		var e20 := _edge_key_from_vertex_keys(str(vkeys[2]), str(vkeys[0]))
		for e in [e01, e12, e20]:
			if e == "":
				continue
			edge_counts[e] = int(edge_counts.get(e, 0)) + 1
		if e01 != "":
			edge_verts[e01] = [str(vkeys[0]), str(vkeys[1])]
		if e12 != "":
			edge_verts[e12] = [str(vkeys[1]), str(vkeys[2])]
		if e20 != "":
			edge_verts[e20] = [str(vkeys[2]), str(vkeys[0])]

	if edge_counts.is_empty():
		return []

	var vertex_pos := {}
	for k_raw in vertex_accum.keys():
		var k := str(k_raw)
		var acc: Dictionary = vertex_accum[k]
		var cnt := maxf(1.0, float(acc["count"]))
		vertex_pos[k] = Vector3(acc["sum"]) / cnt

	var base_radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
	var cell_size := maxf(sample_step * 2.2, maxf(road_width * 0.45, base_radius * 0.55))
	cell_size = maxf(0.2, cell_size)
	var cell_accum := {}

	for e_raw in edge_counts.keys():
		var e := str(e_raw)
		if int(edge_counts[e]) != 1:
			continue
		if not edge_verts.has(e):
			continue
		var pair: Array = edge_verts[e]
		if pair.size() < 2:
			continue
		var ka := str(pair[0])
		var kb := str(pair[1])
		if ka == kb:
			continue
		if not vertex_pos.has(ka) or not vertex_pos.has(kb):
			continue
		var pa: Vector3 = vertex_pos[ka]
		var pb: Vector3 = vertex_pos[kb]
		var mid := (pa + pb) * 0.5
		var cx := int(round(mid.x / cell_size))
		var cz := int(round(mid.z / cell_size))
		var ck := str(cx) + "_" + str(cz)
		if not cell_accum.has(ck):
			cell_accum[ck] = {"sum": mid, "count": 1}
		else:
			var cacc: Dictionary = cell_accum[ck]
			cacc["sum"] = Vector3(cacc["sum"]) + mid
			cacc["count"] = int(cacc["count"]) + 1
			cell_accum[ck] = cacc

	if cell_accum.is_empty():
		return []

	var keys: Array = cell_accum.keys()
	keys.sort()
	var centers: Array = []
	for k_raw in keys:
		var k := str(k_raw)
		var cacc: Dictionary = cell_accum[k]
		var cnt := maxf(1.0, float(cacc["count"]))
		centers.append(Vector3(cacc["sum"]) / cnt)

	const MAX_CENTERS := 240
	if centers.size() > MAX_CENTERS:
		var step := maxi(1, int(ceil(float(centers.size()) / float(MAX_CENTERS))))
		var reduced: Array = []
		for i in range(0, centers.size(), step):
			reduced.append(centers[i])
		centers = reduced

	return centers


func _boolean_recap_single_patch(tris: Array, path_data: Array, center: Vector3, patch_radius: float) -> Dictionary:
	if tris.is_empty() or path_data.is_empty():
		return {"changed": false, "tris": tris}

	var center2 := Vector2(center.x, center.z)
	var clip_radius := patch_radius * maxf(0.6, boolean_recap_clip_scale)
	var clip_poly := _build_circle_polygon_2d(center2, clip_radius, maxi(12, boolean_recap_circle_steps))
	if clip_poly.size() < 3:
		return {"changed": false, "tris": tris}

	var union_parts: Array = []
	for data_raw in path_data:
		var data: Dictionary = data_raw
		var road_poly := _path_to_road_polygon_xz(data)
		if road_poly.size() < 3:
			continue
		var clipped_parts: Array = []
		if boolean_recap_linear_caps:
			var pts: Array = data.get("points", [])
			var closed := bool(data.get("closed", false))
			var widths: Array = data.get("widths", [])
			var nearest := _nearest_path_sample_to_center_xz(pts, center)
			var nearest_idx := int(nearest.get("idx", -1))
			var nearest_dist := float(nearest.get("dist", INF))
			if nearest_idx >= 0 and nearest_dist <= clip_radius * 1.45:
				var t3 := _path_tangent_at(pts, nearest_idx, closed)
				t3.y = 0.0
				var dir2 := Vector2(t3.x, t3.z)
				if dir2.length_squared() > 0.000001:
					dir2 = dir2.normalized()
					var local_width := road_width
					if nearest_idx < widths.size():
						local_width = maxf(0.2, float(widths[nearest_idx]))
					var half_w := maxf(road_width * 0.45, local_width * 0.5 * boolean_recap_arm_half_width_scale)
					var arm_clip := _build_oriented_rect_polygon_2d(center2, dir2, clip_radius, half_w)
					clipped_parts = Geometry2D.intersect_polygons(road_poly, arm_clip)
		if clipped_parts.is_empty():
			clipped_parts = Geometry2D.intersect_polygons(road_poly, clip_poly)
		for part_raw in clipped_parts:
			var part: PackedVector2Array = part_raw
			part = _compact_polygon2d(part, maxf(0.005, sample_step * 0.01))
			if part.size() < 3:
				continue
			union_parts = _union_polygon_parts(union_parts, part)

	if union_parts.is_empty():
		return {"changed": false, "tris": tris}

	var patch_poly := _pick_best_patch_polygon(union_parts, center2)
	patch_poly = _compact_polygon2d(patch_poly, maxf(0.005, sample_step * 0.01))
	if boolean_recap_spike_cleanup > 0.0:
		patch_poly = _smooth_boolean_patch_polygon(patch_poly, center2, boolean_recap_spike_cleanup)
	if patch_poly.size() < 3:
		return {"changed": false, "tris": tris}
	if debug_show_repair_overlay:
		var contour3: Array = []
		for v_raw in patch_poly:
			var v: Vector2 = v_raw
			contour3.append(Vector3(v.x, center.y, v.y))
		_debug_recap_contours.append(contour3)

	var cap_indices: PackedInt32Array = Geometry2D.triangulate_polygon(patch_poly)
	if cap_indices.size() < 3:
		return {"changed": false, "tris": tris}

	var kept: Array = []
	var removed := 0
	for tri_raw in tris:
		var tri: Array = tri_raw
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		if _triangle_overlaps_polygon_xz(a, b, c, patch_poly, center2, clip_radius * 1.45):
			removed += 1
			if debug_show_repair_overlay:
				_debug_push_point(_debug_removed_tri_centers, (a + b + c) / 3.0)
			continue
		kept.append(tri)
	if removed < 1:
		return {"changed": false, "tris": tris}

	var y_samples := _collect_local_y_samples(path_data, center, clip_radius * 1.6)
	var fallback_y := center.y
	if not y_samples.is_empty():
		var y_sum := 0.0
		for p_raw in y_samples:
			var p: Vector3 = p_raw
			y_sum += p.y
		fallback_y = y_sum / float(y_samples.size())

	var patch_points: Array = []
	for v_raw in patch_poly:
		var v: Vector2 = v_raw
		var y := _sample_y_from_samples_xz(y_samples, v, fallback_y)
		patch_points.append(Vector3(v.x, y, v.y))

	var target_winding_sign := _preferred_fill_winding_sign(kept, center)
	var added := 0
	for t in range(0, cap_indices.size(), 3):
		if t + 2 >= cap_indices.size():
			break
		var ia := int(cap_indices[t])
		var ib := int(cap_indices[t + 1])
		var ic := int(cap_indices[t + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= patch_points.size() or ib >= patch_points.size() or ic >= patch_points.size():
			continue
		var size_before := kept.size()
		_append_oriented_triangle(kept, patch_points[ia], patch_points[ib], patch_points[ic], target_winding_sign)
		if kept.size() > size_before:
			added += 1
			if debug_show_repair_overlay:
				_debug_push_point(_debug_added_tri_centers, (patch_points[ia] + patch_points[ib] + patch_points[ic]) / 3.0)

	return {"changed": added > 0, "tris": kept}


func _build_circle_polygon_2d(center: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var segs := maxi(12, steps)
	var r := maxf(0.0001, radius)
	for i in range(segs):
		var a := TAU * float(i) / float(segs)
		out.append(center + Vector2(cos(a), sin(a)) * r)
	return out


func _build_oriented_rect_polygon_2d(center: Vector2, dir: Vector2, half_len: float, half_width: float) -> PackedVector2Array:
	var d := dir
	if d.length_squared() < 0.000001:
		d = Vector2.RIGHT
	d = d.normalized()
	var r := Vector2(-d.y, d.x)
	var hl := maxf(0.0001, half_len)
	var hw := maxf(0.0001, half_width)
	var out := PackedVector2Array()
	out.append(center - d * hl - r * hw)
	out.append(center + d * hl - r * hw)
	out.append(center + d * hl + r * hw)
	out.append(center - d * hl + r * hw)
	return out


func _nearest_path_sample_to_center_xz(points: Array, center: Vector3) -> Dictionary:
	if points.is_empty():
		return {"idx": -1, "dist": INF}
	var best_idx := -1
	var best_dist := INF
	for i in range(points.size()):
		var p: Vector3 = points[i]
		var d := _dist_xz(p, center)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return {"idx": best_idx, "dist": best_dist}


func _compact_polygon2d(poly: PackedVector2Array, eps: float) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var compact := PackedVector2Array()
	var e := maxf(0.00001, eps)
	for p in poly:
		if compact.is_empty():
			compact.append(p)
			continue
		if compact[compact.size() - 1].distance_to(p) > e:
			compact.append(p)
	if compact.size() >= 2 and compact[0].distance_to(compact[compact.size() - 1]) <= e:
		compact.remove_at(compact.size() - 1)
	return compact


func _path_to_road_polygon_xz(path_data: Dictionary) -> PackedVector2Array:
	var pts: Array = path_data.get("points", [])
	var widths: Array = path_data.get("widths", [])
	var closed := bool(path_data.get("closed", false))
	var count := pts.size()
	if count < 2:
		return PackedVector2Array()

	var left: Array = []
	var right: Array = []
	for i in range(count):
		var t := _path_tangent_at(pts, i, closed)
		t.y = 0.0
		if t.length_squared() < 0.000001:
			if i + 1 < count:
				t = (pts[i + 1] - pts[i]).normalized()
			elif i > 0:
				t = (pts[i] - pts[i - 1]).normalized()
		t.y = 0.0
		if t.length_squared() < 0.000001:
			t = Vector3.FORWARD
		t = t.normalized()

		var r := _safe_right_from_dir_and_up(t, Vector3.UP)
		r.y = 0.0
		if r.length_squared() < 0.000001:
			r = Vector3.RIGHT
		r = r.normalized()

		var p: Vector3 = pts[i]
		var hw := road_width * 0.5
		if i < widths.size():
			hw = maxf(0.1, float(widths[i]) * 0.5)
		left.append(Vector2(p.x - r.x * hw, p.z - r.z * hw))
		right.append(Vector2(p.x + r.x * hw, p.z + r.z * hw))

	var poly := PackedVector2Array()
	for p_raw in left:
		var p: Vector2 = p_raw
		poly.append(p)
	for i in range(right.size() - 1, -1, -1):
		var p: Vector2 = right[i]
		poly.append(p)
	return _compact_polygon2d(poly, maxf(0.005, sample_step * 0.01))


func _union_polygon_parts(parts: Array, poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p_raw in parts:
		var p: PackedVector2Array = p_raw
		out.append(p)
	out.append(poly)

	var merged := true
	while merged:
		merged = false
		for i in range(out.size()):
			var a: PackedVector2Array = out[i]
			for j in range(i + 1, out.size()):
				var b: PackedVector2Array = out[j]
				var candidate: Array = Geometry2D.merge_polygons(a, b)
				if candidate.size() == 1:
					var only: PackedVector2Array = candidate[0]
					out[i] = _compact_polygon2d(only, maxf(0.005, sample_step * 0.01))
					out.remove_at(j)
					merged = true
					break
			if merged:
				break
	return out


func _pick_best_patch_polygon(parts: Array, center2: Vector2) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_score := -INF
	for p_raw in parts:
		var poly: PackedVector2Array = p_raw
		if poly.size() < 3:
			continue
		var area_abs := absf(_polygon_signed_area_2d(poly))
		if area_abs < 0.0001:
			continue
		var score := area_abs
		if Geometry2D.is_point_in_polygon(center2, poly):
			score += 1000000.0
		if score > best_score:
			best_score = score
			best = poly
	return best


func _smooth_boolean_patch_polygon(poly: PackedVector2Array, center2: Vector2, radius: float) -> PackedVector2Array:
	if poly.size() < 3 or radius <= 0.0:
		return poly
	var inset_parts: Array = Geometry2D.offset_polygon(poly, -radius)
	if inset_parts.is_empty():
		return poly
	var inset := _pick_best_patch_polygon(inset_parts, center2)
	inset = _compact_polygon2d(inset, maxf(0.005, sample_step * 0.01))
	if inset.size() < 3:
		return poly
	var outset_parts: Array = Geometry2D.offset_polygon(inset, radius)
	if outset_parts.is_empty():
		return inset
	var out := _pick_best_patch_polygon(outset_parts, center2)
	out = _compact_polygon2d(out, maxf(0.005, sample_step * 0.01))
	return out if out.size() >= 3 else inset


func _polygon_signed_area_2d(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var area2 := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area2 += a.x * b.y - b.x * a.y
	return area2 * 0.5


func _triangle_overlaps_polygon_xz(a: Vector3, b: Vector3, c: Vector3, poly: PackedVector2Array, center2: Vector2, dist_limit: float) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var c2 := Vector2(c.x, c.z)
	var tc := (a2 + b2 + c2) / 3.0
	var far := (
		tc.distance_to(center2) > dist_limit
		and a2.distance_to(center2) > dist_limit
		and b2.distance_to(center2) > dist_limit
		and c2.distance_to(center2) > dist_limit
	)
	if far:
		return false

	var inside_count := 0
	inside_count += 1 if Geometry2D.is_point_in_polygon(a2, poly) else 0
	inside_count += 1 if Geometry2D.is_point_in_polygon(b2, poly) else 0
	inside_count += 1 if Geometry2D.is_point_in_polygon(c2, poly) else 0
	var center_inside := Geometry2D.is_point_in_polygon(tc, poly)
	if inside_count >= 2 or center_inside:
		return true

	var edge_hits := 0
	for i in range(poly.size()):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a2, b2, p0, p1) != null:
			edge_hits += 1
		if Geometry2D.segment_intersects_segment(b2, c2, p0, p1) != null:
			edge_hits += 1
		if Geometry2D.segment_intersects_segment(c2, a2, p0, p1) != null:
			edge_hits += 1

	# Be conservative near the cut boundary:
	# do not remove long triangles that only graze the patch and would create
	# holes outside the reconstructed area.
	if edge_hits <= 0:
		return false
	if inside_count >= 1:
		return true
	return tc.distance_to(center2) <= dist_limit * 0.75

	return false


func _is_point_in_triangle_2d(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var s1 := _sign2d(p, a, b)
	var s2 := _sign2d(p, b, c)
	var s3 := _sign2d(p, c, a)
	var has_neg := (s1 < 0.0) or (s2 < 0.0) or (s3 < 0.0)
	var has_pos := (s1 > 0.0) or (s2 > 0.0) or (s3 > 0.0)
	return not (has_neg and has_pos)


func _sign2d(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _collect_local_y_samples(path_data: Array, center: Vector3, radius: float) -> Array:
	var out: Array = []
	var r := maxf(0.0001, radius)
	for data_raw in path_data:
		var data: Dictionary = data_raw
		var pts: Array = data.get("points", [])
		for p_raw in pts:
			var p: Vector3 = p_raw
			if _dist_xz(p, center) <= r:
				out.append(p)
	return out


func _sample_y_from_samples_xz(samples: Array, pos2: Vector2, fallback_y: float) -> float:
	if samples.is_empty():
		return fallback_y
	var sum := 0.0
	var wsum := 0.0
	for p_raw in samples:
		var p: Vector3 = p_raw
		var d2 := Vector2(p.x, p.z).distance_squared_to(pos2)
		var w := 1.0 / (0.05 + d2)
		sum += p.y * w
		wsum += w
	return sum / wsum if wsum > 0.0000001 else fallback_y


func _fill_small_boundary_holes_near_intersections(tris: Array, centers: Array) -> Array:
	if tris.is_empty() or centers.is_empty():
		return tris

	const VERTEX_QUANT := 260.0
	var vertex_accum := {}
	var edge_counts := {}
	var edge_verts := {}

	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var vkeys: Array = []
		for p_raw in tri:
			var p: Vector3 = p_raw
			var vk := _quantized_vertex_key_xz(p, VERTEX_QUANT)
			if not vertex_accum.has(vk):
				vertex_accum[vk] = {"sum": p, "count": 1}
			else:
				var acc: Dictionary = vertex_accum[vk]
				acc["sum"] = Vector3(acc["sum"]) + p
				acc["count"] = int(acc["count"]) + 1
				vertex_accum[vk] = acc
			vkeys.append(vk)

		var e01 := _edge_key_from_vertex_keys(str(vkeys[0]), str(vkeys[1]))
		var e12 := _edge_key_from_vertex_keys(str(vkeys[1]), str(vkeys[2]))
		var e20 := _edge_key_from_vertex_keys(str(vkeys[2]), str(vkeys[0]))
		for e in [e01, e12, e20]:
			if e == "":
				continue
			edge_counts[e] = int(edge_counts.get(e, 0)) + 1
		if e01 != "":
			edge_verts[e01] = [str(vkeys[0]), str(vkeys[1])]
		if e12 != "":
			edge_verts[e12] = [str(vkeys[1]), str(vkeys[2])]
		if e20 != "":
			edge_verts[e20] = [str(vkeys[2]), str(vkeys[0])]

	if edge_counts.is_empty():
		return tris

	var vertex_pos := {}
	for k_raw in vertex_accum.keys():
		var k := str(k_raw)
		var acc: Dictionary = vertex_accum[k]
		var cnt := maxf(1.0, float(acc["count"]))
		vertex_pos[k] = Vector3(acc["sum"]) / cnt

	var boundary_edges: Array = []
	var adjacency := {}
	for e_raw in edge_counts.keys():
		var e := str(e_raw)
		if int(edge_counts[e]) != 1:
			continue
		if not edge_verts.has(e):
			continue
		var pair: Array = edge_verts[e]
		if pair.size() < 2:
			continue
		var ka := str(pair[0])
		var kb := str(pair[1])
		if ka == kb:
			continue
		if not vertex_pos.has(ka) or not vertex_pos.has(kb):
			continue
		boundary_edges.append([ka, kb])
		if not adjacency.has(ka):
			adjacency[ka] = []
		if not adjacency.has(kb):
			adjacency[kb] = []
		var adj_a: Array = adjacency[ka]
		if not adj_a.has(kb):
			adj_a.append(kb)
			adjacency[ka] = adj_a
		var adj_b: Array = adjacency[kb]
		if not adj_b.has(ka):
			adj_b.append(ka)
			adjacency[kb] = adj_b

	if boundary_edges.is_empty():
		return tris

	var loops := _collect_boundary_loops_xz(boundary_edges, adjacency, vertex_pos)
	if loops.is_empty():
		return tris

	var out: Array = tris.duplicate(true)
	var filled_keys := {}
	var added := 0
	var base_radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
	var seam_pad := maxf(0.0, intersection_seam_cleanup_margin)
	var max_hole_area := maxf(0.03, sample_step * sample_step * 12.0)
	max_hole_area = maxf(max_hole_area, road_width * road_width * 0.35)
	var max_intersection_hole_area := PI * pow(base_radius + seam_pad + sample_step * 2.3, 2.0) * 0.5

	for c_raw in centers:
		var center: Vector3 = c_raw
		var radius := base_radius + seam_pad + sample_step * 1.75
		var target_winding_sign := _preferred_fill_winding_sign(out, center)
		for loop_raw in loops:
			var loop: Array = loop_raw
			loop = _compact_contour_loop(loop, maxf(0.002, sample_step * 0.012))
			if loop.size() < 3 or loop.size() > 48:
				continue

			var poly2d := PackedVector2Array()
			var loop_min_dist := INF
			var cx := 0.0
			var cz := 0.0
			var y_sum := 0.0
			var min_x := INF
			var max_x := -INF
			var min_z := INF
			var max_z := -INF
			for p_raw in loop:
				var p: Vector3 = p_raw
				loop_min_dist = minf(loop_min_dist, _dist_xz(p, center))
				cx += p.x
				cz += p.z
				y_sum += p.y
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
				poly2d.append(Vector2(p.x, p.z))
			var inv_n := 1.0 / float(loop.size())
			var centroid_dist := _dist_xz(Vector3(cx * inv_n, center.y, cz * inv_n), center)
			if loop_min_dist > radius and centroid_dist > radius * 1.2:
				continue

			var area := absf(_polygon_signed_area_2d(poly2d))
			if area <= 0.00001:
				continue
			var allow_large := centroid_dist <= radius * 0.92 and loop.size() <= 26
			var area_limit := max_hole_area
			if allow_large:
				area_limit = maxf(area_limit, max_intersection_hole_area)
			if area > area_limit:
				continue
			var span_x := max_x - min_x
			var span_z := max_z - min_z
			if allow_large and (span_x > radius * 2.8 or span_z > radius * 2.8):
				continue

			var key := _loop_key_xz(loop, 320.0)
			if key == "" or filled_keys.has(key):
				continue

			var cap_indices: PackedInt32Array = Geometry2D.triangulate_polygon(poly2d)
			if cap_indices.size() < 3:
				continue

			var loop_y := y_sum / float(loop.size())
			var points3: Array = []
			for v_raw in poly2d:
				var v: Vector2 = v_raw
				points3.append(Vector3(v.x, loop_y, v.y))

			var local_added := 0
			for t in range(0, cap_indices.size(), 3):
				if t + 2 >= cap_indices.size():
					break
				var ia := int(cap_indices[t])
				var ib := int(cap_indices[t + 1])
				var ic := int(cap_indices[t + 2])
				if ia < 0 or ib < 0 or ic < 0:
					continue
				if ia >= points3.size() or ib >= points3.size() or ic >= points3.size():
					continue
				var before := out.size()
				_append_oriented_triangle(out, points3[ia], points3[ib], points3[ic], target_winding_sign)
				if out.size() > before:
					local_added += 1

			if local_added > 0:
				filled_keys[key] = true
				added += local_added

	if added == 0:
		return tris
	return _cleanup_triangles(out)


func _bridge_dead_end_seams_near_intersections(tris: Array, centers: Array) -> Array:
	if tris.is_empty():
		return tris

	const VERTEX_QUANT_XZ := 260.0
	const VERTEX_QUANT_Y := 340.0
	var vertex_accum := {}
	var edge_counts := {}
	var edge_verts := {}

	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var vkeys: Array = []
		for p_raw in tri:
			var p: Vector3 = p_raw
			var vk := _quantized_vertex_key_xyz(p, VERTEX_QUANT_XZ, VERTEX_QUANT_Y)
			if not vertex_accum.has(vk):
				vertex_accum[vk] = {"sum": p, "count": 1}
			else:
				var acc: Dictionary = vertex_accum[vk]
				acc["sum"] = Vector3(acc["sum"]) + p
				acc["count"] = int(acc["count"]) + 1
				vertex_accum[vk] = acc
			vkeys.append(vk)

		var e01 := _edge_key_from_vertex_keys(str(vkeys[0]), str(vkeys[1]))
		var e12 := _edge_key_from_vertex_keys(str(vkeys[1]), str(vkeys[2]))
		var e20 := _edge_key_from_vertex_keys(str(vkeys[2]), str(vkeys[0]))
		for e in [e01, e12, e20]:
			if e == "":
				continue
			edge_counts[e] = int(edge_counts.get(e, 0)) + 1
		if e01 != "":
			edge_verts[e01] = [str(vkeys[0]), str(vkeys[1])]
		if e12 != "":
			edge_verts[e12] = [str(vkeys[1]), str(vkeys[2])]
		if e20 != "":
			edge_verts[e20] = [str(vkeys[2]), str(vkeys[0])]

	if edge_counts.is_empty():
		return tris

	var vertex_pos := {}
	for k_raw in vertex_accum.keys():
		var k := str(k_raw)
		var acc: Dictionary = vertex_accum[k]
		var cnt := maxf(1.0, float(acc["count"]))
		vertex_pos[k] = Vector3(acc["sum"]) / cnt

	var adjacency := {}
	for e_raw in edge_counts.keys():
		var e := str(e_raw)
		if int(edge_counts[e]) != 1:
			continue
		if not edge_verts.has(e):
			continue
		var pair: Array = edge_verts[e]
		if pair.size() < 2:
			continue
		var ka := str(pair[0])
		var kb := str(pair[1])
		if ka == kb:
			continue
		if not vertex_pos.has(ka) or not vertex_pos.has(kb):
			continue
		if not adjacency.has(ka):
			adjacency[ka] = []
		if not adjacency.has(kb):
			adjacency[kb] = []
		var adj_a: Array = adjacency[ka]
		if not adj_a.has(kb):
			adj_a.append(kb)
			adjacency[ka] = adj_a
		var adj_b: Array = adjacency[kb]
		if not adj_b.has(ka):
			adj_b.append(ka)
			adjacency[kb] = adj_b

	var endpoints: Array = []
	for k_raw in adjacency.keys():
		var k := str(k_raw)
		var ns: Array = adjacency[k]
		if ns.size() == 1 and vertex_pos.has(k):
			endpoints.append(k)
	if endpoints.size() < 2:
		return tris

	var out: Array = tris.duplicate(true)
	var added := 0
	var used := {}
	var base_radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
	var seam_pad := maxf(0.0, intersection_seam_cleanup_margin)
	var search_radius := base_radius + seam_pad + sample_step * 2.6
	var max_gap := maxf(0.34, minf(sample_step * 2.05, road_width * 0.62))
	max_gap = maxf(max_gap, seam_pad * 2.5)
	var max_neighbor_gap := max_gap * 1.9
	var max_y_delta := maxf(0.22, sample_step * 0.8)
	var cluster_radius := maxf(base_radius * 1.25 + sample_step * 1.7, road_width * 1.9)
	cluster_radius += seam_pad * 1.2
	var endpoint_clusters := _cluster_vertex_keys_by_distance_xz(endpoints, vertex_pos, cluster_radius)

	for cluster_raw in endpoint_clusters:
		var cluster: Array = cluster_raw
		if cluster.size() < 2:
			continue

		var center_acc := Vector3.ZERO
		var center_count := 0
		for k_raw in cluster:
			var k := str(k_raw)
			if not vertex_pos.has(k):
				continue
			center_acc += Vector3(vertex_pos[k])
			center_count += 1
		if center_count < 2:
			continue
		var cluster_center := center_acc / float(center_count)

		if not centers.is_empty():
			var near_any := false
			for c_raw in centers:
				var c: Vector3 = c_raw
				if _dist_xz(cluster_center, c) <= search_radius * 1.35:
					near_any = true
					break
			if not near_any:
				continue

		var target_winding_sign := _preferred_fill_winding_sign(out, cluster_center)

		var changed_local := true
		while changed_local:
			changed_local = false
			var local_endpoints: Array = []
			for k_raw in cluster:
				var k := str(k_raw)
				if used.has(k):
					continue
				if not adjacency.has(k) or not vertex_pos.has(k):
					continue
				var ns: Array = adjacency[k]
				if ns.size() == 1:
					local_endpoints.append(k)
			if local_endpoints.size() < 2:
				break

			var best_for := {}
			for ka_raw in local_endpoints:
				var ka := str(ka_raw)
				if used.has(ka):
					continue
				var na := str(adjacency[ka][0])
				if not vertex_pos.has(na):
					continue

				var pa: Vector3 = vertex_pos[ka]
				var pna: Vector3 = vertex_pos[na]
				var ta := Vector2(pa.x - pna.x, pa.z - pna.z)
				if ta.length_squared() < 0.000001:
					continue
				ta = ta.normalized()

				var best_k := ""
				var best_score := INF
				for kb_raw in local_endpoints:
					var kb := str(kb_raw)
					if kb == ka or used.has(kb):
						continue
					var nb := str(adjacency[kb][0])
					if nb == ka or nb == na or not vertex_pos.has(nb):
						continue

					var pb: Vector3 = vertex_pos[kb]
					var pnb: Vector3 = vertex_pos[nb]
					var gap := _dist_xz(pa, pb)
					if gap > max_gap:
						continue
					var neighbor_gap := _dist_xz(pna, pnb)
					if neighbor_gap > max_neighbor_gap:
						continue
					if _dist_xz(pa, pna) < 0.06 or _dist_xz(pb, pnb) < 0.06:
						continue
					if absf(pa.y - pb.y) > max_y_delta:
						continue
					if absf(pna.y - pnb.y) > max_y_delta * 1.8:
						continue

					var tb := Vector2(pb.x - pnb.x, pb.z - pnb.z)
					if tb.length_squared() < 0.000001:
						continue
					tb = tb.normalized()
					var tangent_parallel := absf(ta.dot(tb))
					if tangent_parallel < 0.2:
						continue

					var bridge_dir := Vector2(pb.x - pa.x, pb.z - pa.z)
					var neighbor_dir := Vector2(pnb.x - pna.x, pnb.z - pna.z)
					var bridge_parallel := 1.0
					if bridge_dir.length_squared() > 0.000001 and neighbor_dir.length_squared() > 0.000001:
						bridge_parallel = absf(bridge_dir.normalized().dot(neighbor_dir.normalized()))
						if bridge_parallel < 0.2:
							continue

					var score := gap + neighbor_gap * 0.58
					score += (1.0 - tangent_parallel) * 0.24 + (1.0 - bridge_parallel) * 0.20
					if score < best_score:
						best_score = score
						best_k = kb

				if best_k != "":
					best_for[ka] = best_k

			for ka_raw in best_for.keys():
				var ka := str(ka_raw)
				if used.has(ka):
					continue
				var kb := str(best_for[ka])
				if kb == "" or used.has(kb):
					continue
				if not best_for.has(kb) or str(best_for[kb]) != ka:
					continue
				if ka > kb:
					continue
				if not adjacency.has(ka) or not adjacency.has(kb):
					continue
				var na_list: Array = adjacency[ka]
				var nb_list: Array = adjacency[kb]
				if na_list.size() != 1 or nb_list.size() != 1:
					continue
				var na := str(na_list[0])
				var nb := str(nb_list[0])
				if not vertex_pos.has(ka) or not vertex_pos.has(kb) or not vertex_pos.has(na) or not vertex_pos.has(nb):
					continue

				var pa: Vector3 = vertex_pos[ka]
				var pb: Vector3 = vertex_pos[kb]
				var pna: Vector3 = vertex_pos[na]
				var pnb: Vector3 = vertex_pos[nb]

				var before := out.size()
				var diag0 := _dist_xz(pa, pnb)
				var diag1 := _dist_xz(pna, pb)
				if diag0 <= diag1:
					_append_oriented_triangle(out, pa, pna, pnb, target_winding_sign)
					_append_oriented_triangle(out, pa, pnb, pb, target_winding_sign)
				else:
					_append_oriented_triangle(out, pa, pna, pb, target_winding_sign)
					_append_oriented_triangle(out, pna, pnb, pb, target_winding_sign)
				if out.size() > before:
					used[ka] = true
					used[kb] = true
					added += out.size() - before
					changed_local = true

	if added == 0:
		return tris
	return _cleanup_triangles(out)


func _loop_key_xz(loop: Array, quant: float) -> String:
	if loop.is_empty():
		return ""
	var keys: Array = []
	for p_raw in loop:
		var p: Vector3 = p_raw
		keys.append(_quantized_vertex_key_xz(p, quant))
	keys.sort()
	var out := ""
	for i in range(keys.size()):
		out += "|" if i > 0 else ""
		out += str(keys[i])
	return out


func _stitch_parallel_seam_gaps_near_intersections(tris: Array, centers: Array) -> Array:
	if tris.is_empty() or centers.is_empty():
		return tris

	var segments := _extract_boundary_segments_xz(tris, 280.0)
	if segments.is_empty():
		return tris

	var out: Array = tris.duplicate(true)
	var stitched_pairs := {}
	var added := 0
	var base_radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
	base_radius += maxf(0.0, intersection_seam_cleanup_margin) + sample_step * 1.9
	var gap_max := maxf(0.12, minf(sample_step * 1.2, road_width * 0.28))
	gap_max = maxf(gap_max, intersection_seam_cleanup_margin * 1.8)
	if boolean_recap_stitch_gap_max > 0.0:
		gap_max = maxf(0.02, boolean_recap_stitch_gap_max)

	for c_raw in centers:
		var center: Vector3 = c_raw
		var target_winding_sign := _preferred_fill_winding_sign(out, center)
		var local_idxs: Array = []
		for i in range(segments.size()):
			var s: Dictionary = segments[i]
			var mid: Vector3 = s["mid"]
			if _dist_xz(mid, center) <= base_radius:
				local_idxs.append(i)
		if local_idxs.size() < 2:
			continue

		for li in range(local_idxs.size()):
			var i := int(local_idxs[li])
			var s1: Dictionary = segments[i]
			var best_j := -1
			var best_map := 0
			var best_score := INF
			for lj in range(li + 1, local_idxs.size()):
				var j := int(local_idxs[lj])
				var s2: Dictionary = segments[j]
				var ka1 := str(s1["ka"])
				var kb1 := str(s1["kb"])
				var ka2 := str(s2["ka"])
				var kb2 := str(s2["kb"])
				if ka1 == ka2 or ka1 == kb2 or kb1 == ka2 or kb1 == kb2:
					continue

				var pair_key := _edge_pair_key(ka1, kb1, ka2, kb2)
				if stitched_pairs.has(pair_key):
					continue

				var dir1: Vector2 = s1["dir"]
				var dir2: Vector2 = s2["dir"]
				var parallel := absf(dir1.dot(dir2))
				if parallel < 0.88:
					continue

				var mid_d := _dist_xz(Vector3(s1["mid"]), Vector3(s2["mid"]))
				if mid_d > gap_max * 2.4:
					continue

				var a1: Vector3 = s1["a"]
				var b1: Vector3 = s1["b"]
				var a2: Vector3 = s2["a"]
				var b2: Vector3 = s2["b"]
				var d_ac := _dist_xz(a1, a2)
				var d_bd := _dist_xz(b1, b2)
				var d_ad := _dist_xz(a1, b2)
				var d_bc := _dist_xz(b1, a2)
				var map0_max := maxf(d_ac, d_bd)
				var map1_max := maxf(d_ad, d_bc)
				var map0_score := d_ac + d_bd
				var map1_score := d_ad + d_bc
				var map := 0
				var score := map0_score
				var pair_max := map0_max
				if map1_score < map0_score:
					map = 1
					score = map1_score
					pair_max = map1_max

				if pair_max > gap_max * 2.8:
					continue

				var len1 := float(s1["len"])
				var len2 := float(s2["len"])
				var len_ratio := minf(len1, len2) / maxf(0.0001, maxf(len1, len2))
				if len_ratio < 0.22:
					continue

				score = score / maxf(0.001, parallel) + mid_d * 0.22
				if score < best_score:
					best_score = score
					best_j = j
					best_map = map

			if best_j == -1:
				continue

			var s2_best: Dictionary = segments[best_j]
			var p1a: Vector3 = s1["a"]
			var p1b: Vector3 = s1["b"]
			var p2a: Vector3 = s2_best["a"]
			var p2b: Vector3 = s2_best["b"]
			if best_map == 1:
				var tmp := p2a
				p2a = p2b
				p2b = tmp

			var before := out.size()
			_append_oriented_triangle(out, p1a, p1b, p2b, target_winding_sign)
			_append_oriented_triangle(out, p1a, p2b, p2a, target_winding_sign)
			if out.size() > before:
				var pair_key := _edge_pair_key(str(s1["ka"]), str(s1["kb"]), str(s2_best["ka"]), str(s2_best["kb"]))
				stitched_pairs[pair_key] = true
				added += out.size() - before

	if added == 0:
		return tris
	return _cleanup_triangles(out)


func _stitch_parallel_seam_gaps_global(tris: Array) -> Array:
	if tris.is_empty():
		return tris

	var segments := _extract_boundary_segments_xz(tris, 280.0)
	if segments.size() < 2:
		return tris

	var out: Array = tris.duplicate(true)
	var used_segment := {}
	var stitched_pairs := {}
	var added := 0

	var gap_max := maxf(0.24, minf(sample_step * 2.0, road_width * 0.72))
	gap_max = maxf(gap_max, intersection_seam_cleanup_margin * 2.4)
	var max_mid_dist := gap_max * 2.2
	var max_pair_dist := gap_max * 2.65
	var max_y_delta := maxf(0.18, sample_step * 0.75)
	var cell_size := maxf(gap_max * 1.35, 0.24)

	var grid := {}
	for i in range(segments.size()):
		var s: Dictionary = segments[i]
		var mid: Vector3 = s["mid"]
		var cx := int(round(mid.x / cell_size))
		var cz := int(round(mid.z / cell_size))
		var ck := str(cx) + "_" + str(cz)
		if not grid.has(ck):
			grid[ck] = []
		var arr: Array = grid[ck]
		arr.append(i)
		grid[ck] = arr

	for i in range(segments.size()):
		if used_segment.has(i):
			continue
		var s1: Dictionary = segments[i]
		var len1 := float(s1["len"])
		if len1 < 0.06:
			continue
		var mid1: Vector3 = s1["mid"]
		var dir1: Vector2 = s1["dir"]
		var cx := int(round(mid1.x / cell_size))
		var cz := int(round(mid1.z / cell_size))

		var best_j := -1
		var best_map := 0
		var best_score := INF
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var nk := str(cx + dx) + "_" + str(cz + dz)
				if not grid.has(nk):
					continue
				var candidates: Array = grid[nk]
				for j_raw in candidates:
					var j := int(j_raw)
					if j == i or used_segment.has(j):
						continue
					var s2: Dictionary = segments[j]
					var ka1 := str(s1["ka"])
					var kb1 := str(s1["kb"])
					var ka2 := str(s2["ka"])
					var kb2 := str(s2["kb"])
					if ka1 == ka2 or ka1 == kb2 or kb1 == ka2 or kb1 == kb2:
						continue

					var pair_key := _edge_pair_key(ka1, kb1, ka2, kb2)
					if pair_key == "" or stitched_pairs.has(pair_key):
						continue

					var dir2: Vector2 = s2["dir"]
					var parallel := absf(dir1.dot(dir2))
					if parallel < 0.9:
						continue

					var mid2: Vector3 = s2["mid"]
					var mid_d := _dist_xz(mid1, mid2)
					if mid_d > max_mid_dist:
						continue

					var a1: Vector3 = s1["a"]
					var b1: Vector3 = s1["b"]
					var a2: Vector3 = s2["a"]
					var b2: Vector3 = s2["b"]
					var d_ac := _dist_xz(a1, a2)
					var d_bd := _dist_xz(b1, b2)
					var d_ad := _dist_xz(a1, b2)
					var d_bc := _dist_xz(b1, a2)
					var map0_max := maxf(d_ac, d_bd)
					var map1_max := maxf(d_ad, d_bc)
					var map0_score := d_ac + d_bd
					var map1_score := d_ad + d_bc
					var map := 0
					var score := map0_score
					var pair_max := map0_max
					if map1_score < map0_score:
						map = 1
						score = map1_score
						pair_max = map1_max
					if pair_max > max_pair_dist:
						continue

					var len2 := float(s2["len"])
					var len_ratio := minf(len1, len2) / maxf(0.0001, maxf(len1, len2))
					if len_ratio < 0.35:
						continue

					var y_ok := false
					if map == 0:
						var ya := absf(a1.y - a2.y)
						var yb := absf(b1.y - b2.y)
						y_ok = ya <= max_y_delta and yb <= max_y_delta
					else:
						var ya2 := absf(a1.y - b2.y)
						var yb2 := absf(b1.y - a2.y)
						y_ok = ya2 <= max_y_delta and yb2 <= max_y_delta
					if not y_ok:
						continue

					score = score / maxf(0.001, parallel) + mid_d * 0.2
					if score < best_score:
						best_score = score
						best_j = j
						best_map = map

		if best_j == -1:
			continue

		var s2_best: Dictionary = segments[best_j]
		var p1a: Vector3 = s1["a"]
		var p1b: Vector3 = s1["b"]
		var p2a: Vector3 = s2_best["a"]
		var p2b: Vector3 = s2_best["b"]
		if best_map == 1:
			var tmp := p2a
			p2a = p2b
			p2b = tmp

		var target_winding_sign := _preferred_fill_winding_sign(out, (Vector3(s1["mid"]) + Vector3(s2_best["mid"])) * 0.5)
		var before := out.size()
		_append_oriented_triangle(out, p1a, p1b, p2b, target_winding_sign)
		_append_oriented_triangle(out, p1a, p2b, p2a, target_winding_sign)
		if out.size() > before:
			used_segment[i] = true
			used_segment[best_j] = true
			var pair_key_final := _edge_pair_key(str(s1["ka"]), str(s1["kb"]), str(s2_best["ka"]), str(s2_best["kb"]))
			if pair_key_final != "":
				stitched_pairs[pair_key_final] = true
			added += out.size() - before

	if added == 0:
		return tris
	return _cleanup_triangles(out)


func _extract_boundary_segments_xz(tris: Array, vertex_quant: float) -> Array:
	if tris.is_empty():
		return []

	var vertex_accum := {}
	var edge_counts := {}
	var edge_verts := {}

	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var vkeys: Array = []
		for p_raw in tri:
			var p: Vector3 = p_raw
			var vk := _quantized_vertex_key_xz(p, vertex_quant)
			if not vertex_accum.has(vk):
				vertex_accum[vk] = {"sum": p, "count": 1}
			else:
				var acc: Dictionary = vertex_accum[vk]
				acc["sum"] = Vector3(acc["sum"]) + p
				acc["count"] = int(acc["count"]) + 1
				vertex_accum[vk] = acc
			vkeys.append(vk)

		var e01 := _edge_key_from_vertex_keys(str(vkeys[0]), str(vkeys[1]))
		var e12 := _edge_key_from_vertex_keys(str(vkeys[1]), str(vkeys[2]))
		var e20 := _edge_key_from_vertex_keys(str(vkeys[2]), str(vkeys[0]))
		for e in [e01, e12, e20]:
			if e == "":
				continue
			edge_counts[e] = int(edge_counts.get(e, 0)) + 1
		if e01 != "":
			edge_verts[e01] = [str(vkeys[0]), str(vkeys[1])]
		if e12 != "":
			edge_verts[e12] = [str(vkeys[1]), str(vkeys[2])]
		if e20 != "":
			edge_verts[e20] = [str(vkeys[2]), str(vkeys[0])]

	var vertex_pos := {}
	for k_raw in vertex_accum.keys():
		var k := str(k_raw)
		var acc: Dictionary = vertex_accum[k]
		var cnt := maxf(1.0, float(acc["count"]))
		vertex_pos[k] = Vector3(acc["sum"]) / cnt

	var out: Array = []
	for e_raw in edge_counts.keys():
		var e := str(e_raw)
		if int(edge_counts[e]) != 1:
			continue
		if not edge_verts.has(e):
			continue
		var pair: Array = edge_verts[e]
		if pair.size() < 2:
			continue
		var ka := str(pair[0])
		var kb := str(pair[1])
		if ka == kb:
			continue
		if not vertex_pos.has(ka) or not vertex_pos.has(kb):
			continue
		var a: Vector3 = vertex_pos[ka]
		var b: Vector3 = vertex_pos[kb]
		var d := Vector2(b.x - a.x, b.z - a.z)
		var l := d.length()
		if l < 0.0005:
			continue
		out.append({
			"ka": ka,
			"kb": kb,
			"a": a,
			"b": b,
			"mid": (a + b) * 0.5,
			"dir": d / l,
			"len": l,
		})
	return out


func _edge_pair_key(ka1: String, kb1: String, ka2: String, kb2: String) -> String:
	var e1 := _edge_key_from_vertex_keys(ka1, kb1)
	var e2 := _edge_key_from_vertex_keys(ka2, kb2)
	if e1 == "" or e2 == "":
		return ""
	return e1 + "||" + e2 if e1 < e2 else e2 + "||" + e1


func _snap_contour_to_boundary_segments(
	contour: Array,
	seam_segments: Array,
	center: Vector3,
	patch_radius: float,
	snap_dist: float
) -> Array:
	if contour.size() < 3 or seam_segments.is_empty():
		return contour

	var out: Array = []
	var max_mid_dist := patch_radius * 1.7
	var snap_limit := maxf(0.005, snap_dist)
	for p_raw in contour:
		var p: Vector3 = p_raw
		var best := p
		var best_d := snap_limit
		for s_raw in seam_segments:
			var s: Dictionary = s_raw
			var mid: Vector3 = s["mid"]
			if _dist_xz(mid, center) > max_mid_dist:
				continue
			var a: Vector3 = s["a"]
			var b: Vector3 = s["b"]
			var hit := _closest_point_on_segment_xz(p, a, b)
			var d := float(hit.get("dist", INF))
			if d < best_d:
				best_d = d
				best = Vector3(hit.get("pos", p))
		out.append(best)

	var compact := _compact_contour_loop(out, maxf(0.005, snap_limit * 0.35))
	return compact if compact.size() >= 3 else out


func _collect_unique_hint_centers(weld_hints: Array) -> Array:
	var merge_dist := maxf(0.2, junction_snap_distance * 0.35)
	var centers: Array = []
	for hint in weld_hints:
		var p := Vector3(hint.get("pos", Vector3.ZERO))
		var found := false
		for i in range(centers.size()):
			var c: Vector3 = centers[i]
			if _dist_xz(c, p) <= merge_dist:
				centers[i] = c.lerp(p, 0.5)
				found = true
				break
		if not found:
			centers.append(p)
	return centers


func _collect_intersection_centers_from_paths(path_data: Array) -> Array:
	var out: Array = []
	if path_data.size() < 2:
		return out
	var merge_dist := maxf(0.05, vertex_weld_distance * 1.2)
	var near_dist := maxf(0.05, vertex_weld_distance * 0.9)
	for i in range(path_data.size()):
		var a_data: Dictionary = path_data[i]
		var a_pts: Array = a_data.get("points", [])
		var a_closed := bool(a_data.get("closed", false))
		var a_seg_count := a_pts.size() if a_closed else a_pts.size() - 1
		if a_seg_count < 1:
			continue
		for j in range(i + 1, path_data.size()):
			var b_data: Dictionary = path_data[j]
			var b_pts: Array = b_data.get("points", [])
			var b_closed := bool(b_data.get("closed", false))
			var b_seg_count := b_pts.size() if b_closed else b_pts.size() - 1
			if b_seg_count < 1:
				continue
			for sa in range(a_seg_count):
				var a0: Vector3 = a_pts[sa]
				var a1: Vector3 = a_pts[(sa + 1) % a_pts.size()]
				var a0_2 := Vector2(a0.x, a0.z)
				var a1_2 := Vector2(a1.x, a1.z)
				for sb in range(b_seg_count):
					var b0: Vector3 = b_pts[sb]
					var b1: Vector3 = b_pts[(sb + 1) % b_pts.size()]
					var b0_2 := Vector2(b0.x, b0.z)
					var b1_2 := Vector2(b1.x, b1.z)
					var hit = Geometry2D.segment_intersects_segment(a0_2, a1_2, b0_2, b1_2)
					var center := Vector3.ZERO
					if hit != null:
						var h2: Vector2 = hit
						var hy := (a0.y + a1.y + b0.y + b1.y) * 0.25
						center = Vector3(h2.x, hy, h2.y)
					elif vertex_weld_allow_near_intersections:
						# Also treat very close segments as an intersection center so
						# vertex weld works without endpoint snapping/junction merge.
						var ca0: Dictionary = _closest_point_on_segment_xz(a0, b0, b1)
						var ca1: Dictionary = _closest_point_on_segment_xz(a1, b0, b1)
						var cb0: Dictionary = _closest_point_on_segment_xz(b0, a0, a1)
						var cb1: Dictionary = _closest_point_on_segment_xz(b1, a0, a1)
						var best_a := a0
						var best_b := Vector3(ca0["pos"])
						var best_d := float(ca0["dist"])
						if float(ca1["dist"]) < best_d:
							best_a = a1
							best_b = Vector3(ca1["pos"])
							best_d = float(ca1["dist"])
						if float(cb0["dist"]) < best_d:
							best_a = Vector3(cb0["pos"])
							best_b = b0
							best_d = float(cb0["dist"])
						if float(cb1["dist"]) < best_d:
							best_a = Vector3(cb1["pos"])
							best_b = b1
							best_d = float(cb1["dist"])
						var ta := 0.0
						var tb := 0.0
						if best_a == a0:
							tb = float(ca0.get("t", 0.0))
						elif best_a == a1:
							tb = float(ca1.get("t", 0.0))
						elif best_b == b0:
							ta = float(cb0.get("t", 0.0))
						else:
							ta = float(cb1.get("t", 0.0))
						if best_d > near_dist:
							continue
						# avoid welding at arbitrary close parallel lanes:
						# keep only near matches that hit interior segment spans.
						if (ta <= 0.05 or ta >= 0.95) and (tb <= 0.05 or tb >= 0.95):
							continue
						center = (best_a + best_b) * 0.5
					else:
						continue
					var merged := false
					for c_idx in range(out.size()):
						var c: Vector3 = out[c_idx]
						if _dist_xz(c, center) <= merge_dist:
							out[c_idx] = c.lerp(center, 0.5)
							merged = true
							break
					if not merged:
						out.append(center)
	return out


func _collect_passive_chain_keys(
	adjacency: Dictionary,
	key_pos: Dictionary,
	start_key: String,
	end_key: String,
	p0: Vector3,
	p1: Vector3,
	corridor_width: float
) -> Array:
	var fallback: Array = [start_key, end_key]
	if start_key == "" or end_key == "" or not adjacency.has(start_key) or not adjacency.has(end_key):
		return fallback
	if not key_pos.has(start_key) or not key_pos.has(end_key):
		return fallback

	var queue: Array = [start_key]
	var visited := {start_key: true}
	var parent := {}
	var width := maxf(0.02, corridor_width)
	var dir2 := Vector2(p1.x - p0.x, p1.z - p0.z)
	if dir2.length_squared() < 0.000001:
		return fallback
	dir2 = dir2.normalized()

	while not queue.is_empty():
		var cur := str(queue.pop_front())
		if cur == end_key:
			break
		var ns: Array = adjacency.get(cur, [])
		for n_raw in ns:
			var n := str(n_raw)
			if visited.has(n):
				continue
			if not key_pos.has(cur) or not key_pos.has(n):
				continue
			var pc: Vector3 = key_pos[cur]
			var pn: Vector3 = key_pos[n]
			var hc := _closest_point_on_segment_xz(pc, p0, p1)
			var hn := _closest_point_on_segment_xz(pn, p0, p1)
			if float(hc.get("dist", INF)) > width or float(hn.get("dist", INF)) > width:
				continue
			var e2 := Vector2(pn.x - pc.x, pn.z - pc.z)
			if e2.length_squared() < 0.0000001:
				continue
			e2 = e2.normalized()
			if absf(e2.dot(dir2)) < 0.6:
				continue
			visited[n] = true
			parent[n] = cur
			queue.append(n)

	if not visited.has(end_key):
		return fallback

	var path: Array = []
	var k := end_key
	while true:
		path.append(k)
		if k == start_key:
			break
		if not parent.has(k):
			return fallback
		k = str(parent[k])
	path.reverse()
	return path


func _recap_single_intersection_patch(tris: Array, center: Vector3, patch_radius: float) -> Dictionary:
	if tris.is_empty():
		return {"changed": false, "tris": tris}

	var kept: Array = []
	var ring_samples: Array = []
	var cut_count := 0
	var center_cut := patch_radius * 0.82
	var cut_max := patch_radius * 1.08
	var ring_min := patch_radius * 0.45
	var ring_max := patch_radius * 1.35

	for tri_raw in tris:
		var tri: Array = tri_raw
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var da := _dist_xz(a, center)
		var db := _dist_xz(b, center)
		var dc := _dist_xz(c, center)
		var tri_center := (a + b + c) / 3.0
		var dtri := _dist_xz(tri_center, center)
		var near_count := (1 if da <= cut_max else 0) + (1 if db <= cut_max else 0) + (1 if dc <= cut_max else 0)
		var cut := dtri <= center_cut or near_count >= 2

		for v in tri:
			var dv := _dist_xz(v, center)
			if dv >= ring_min and dv <= ring_max:
				ring_samples.append(v)

		if cut:
			cut_count += 1
			if debug_show_repair_overlay:
				_debug_push_point(_debug_removed_tri_centers, tri_center)
		else:
			kept.append(tri)

	if cut_count < 2:
		return {"changed": false, "tris": tris}

	var recap_bins := _compute_legacy_recap_bins(patch_radius, ring_samples.size())
	var contour := _extract_contour_from_ring_samples(center, ring_samples, recap_bins)
	if contour.size() < 3:
		return {"changed": false, "tris": tris}
	if debug_show_repair_overlay:
		_debug_recap_contours.append(contour.duplicate(true))
	contour = _order_contour_radial(center, contour)
	contour = _untangle_contour_order(contour)
	if contour.size() < 3:
		return {"changed": false, "tris": tris}
	var seam_segments := _extract_boundary_segments_xz(kept, 320.0)
	if not seam_segments.is_empty():
		contour = _snap_contour_to_boundary_segments(
			contour,
			seam_segments,
			center,
			patch_radius,
			maxf(0.03, sample_step * 0.8)
		)
		contour = _order_contour_radial(center, contour)
		contour = _untangle_contour_order(contour)
		if contour.size() < 3:
			return {"changed": false, "tris": tris}

	var poly2d := PackedVector2Array()
	var contour_y_sum := 0.0
	for p_raw in contour:
		var p: Vector3 = p_raw
		poly2d.append(Vector2(p.x - center.x, p.z - center.z))
		contour_y_sum += p.y
	var fill_center2 := Vector2.ZERO
	if not Geometry2D.is_point_in_polygon(fill_center2, poly2d):
		fill_center2 = _polygon_centroid_2d(poly2d)
		if not Geometry2D.is_point_in_polygon(fill_center2, poly2d):
			fill_center2 = _polygon_average_2d(poly2d)
	var fill_y := contour_y_sum / float(contour.size())
	var cleanup_margin := maxf(0.0, intersection_seam_cleanup_margin)
	var cleanup_poly := _expand_polygon_radial(poly2d, cleanup_margin)
	var seam_protect := maxf(0.002, minf(0.25, cleanup_margin * 0.55))
	var inner_poly := _expand_polygon_radial(poly2d, -seam_protect)

	var filtered_kept: Array = []
	for tri_raw in kept:
		var tri: Array = tri_raw
		var ta: Vector2 = Vector2((tri[0] as Vector3).x - center.x, (tri[0] as Vector3).z - center.z)
		var tb: Vector2 = Vector2((tri[1] as Vector3).x - center.x, (tri[1] as Vector3).z - center.z)
		var tc: Vector2 = Vector2((tri[2] as Vector3).x - center.x, (tri[2] as Vector3).z - center.z)
		var tcenter := (ta + tb + tc) / 3.0
		var inside_inner_count := 0
		inside_inner_count += 1 if Geometry2D.is_point_in_polygon(ta, inner_poly) else 0
		inside_inner_count += 1 if Geometry2D.is_point_in_polygon(tb, inner_poly) else 0
		inside_inner_count += 1 if Geometry2D.is_point_in_polygon(tc, inner_poly) else 0
		var remove_inner := Geometry2D.is_point_in_polygon(tcenter, inner_poly) or inside_inner_count >= 2
		if remove_inner:
			continue

		if cleanup_margin > 0.000001:
			var inside_cleanup_count := 0
			inside_cleanup_count += 1 if Geometry2D.is_point_in_polygon(ta, cleanup_poly) else 0
			inside_cleanup_count += 1 if Geometry2D.is_point_in_polygon(tb, cleanup_poly) else 0
			inside_cleanup_count += 1 if Geometry2D.is_point_in_polygon(tc, cleanup_poly) else 0
			var remove_margin := Geometry2D.is_point_in_polygon(tcenter, cleanup_poly) and inside_cleanup_count >= 2
			if remove_margin:
				continue

		if _triangle_area2_xz((tri[0] as Vector3), (tri[1] as Vector3), (tri[2] as Vector3)) < 0.0000001:
			continue
		filtered_kept.append(tri)

	var target_winding_sign := _preferred_fill_winding_sign(filtered_kept, center)

	# Build a two-ring cap instead of a pure center fan. This avoids steep
	# radial ramps and keeps the middle of the intersection flatter.
	var inner_ratio := clampf(0.42 + (sample_step / maxf(0.1, patch_radius)) * 0.1, 0.35, 0.55)
	var inner_points: Array = []
	var inner_poly2d := PackedVector2Array()
	for i in range(contour.size()):
		var outer: Vector3 = contour[i]
		var outer2 := Vector2(outer.x - center.x, outer.z - center.z)
		var inner2 := fill_center2 + (outer2 - fill_center2) * inner_ratio
		var inner_y := lerpf(outer.y, fill_y, 0.88)
		var inner3 := Vector3(center.x + inner2.x, inner_y, center.z + inner2.y)
		inner_points.append(inner3)
		inner_poly2d.append(inner2)

	for i in range(contour.size()):
		var ni := (i + 1) % contour.size()
		var outer_a: Vector3 = contour[i]
		var outer_b: Vector3 = contour[ni]
		var inner_a: Vector3 = inner_points[i]
		var inner_b: Vector3 = inner_points[ni]
		_append_oriented_triangle(filtered_kept, outer_a, outer_b, inner_b, target_winding_sign)
		if debug_show_repair_overlay:
			_debug_push_point(_debug_added_tri_centers, (outer_a + outer_b + inner_b) / 3.0)
		_append_oriented_triangle(filtered_kept, outer_a, inner_b, inner_a, target_winding_sign)
		if debug_show_repair_overlay:
			_debug_push_point(_debug_added_tri_centers, (outer_a + inner_b + inner_a) / 3.0)

	var cap_indices: PackedInt32Array = Geometry2D.triangulate_polygon(inner_poly2d)
	if cap_indices.size() >= 3:
		for t in range(0, cap_indices.size(), 3):
			if t + 2 >= cap_indices.size():
				break
			var ia := int(cap_indices[t])
			var ib := int(cap_indices[t + 1])
			var ic := int(cap_indices[t + 2])
			if ia < 0 or ib < 0 or ic < 0:
				continue
			if ia >= inner_points.size() or ib >= inner_points.size() or ic >= inner_points.size():
				continue
			_append_oriented_triangle(filtered_kept, inner_points[ia], inner_points[ib], inner_points[ic], target_winding_sign)
			if debug_show_repair_overlay:
				_debug_push_point(_debug_added_tri_centers, (inner_points[ia] + inner_points[ib] + inner_points[ic]) / 3.0)
	else:
		# Fallback if triangulation fails on a pathological contour.
		var flat_center := Vector3(center.x + fill_center2.x, fill_y, center.z + fill_center2.y)
		for i in range(inner_points.size()):
			var pa: Vector3 = inner_points[i]
			var pb: Vector3 = inner_points[(i + 1) % inner_points.size()]
			_append_oriented_triangle(filtered_kept, flat_center, pa, pb, target_winding_sign)
			if debug_show_repair_overlay:
				_debug_push_point(_debug_added_tri_centers, (flat_center + pa + pb) / 3.0)

	return {"changed": true, "tris": filtered_kept}


func _compute_legacy_recap_bins(patch_radius: float, sample_count: int) -> int:
	var cfg_bins := clampi(intersection_recap_bins, 8, 256)
	if sample_count <= 0:
		return cfg_bins

	var effective_radius := maxf(0.1, patch_radius)
	var arc_step := maxf(0.16, sample_step * 0.95)
	var bins_geom := int(round((TAU * effective_radius) / arc_step))
	bins_geom = clampi(bins_geom, 8, 256)

	# Prevent too many empty angular bins when ring sampling is sparse.
	var bins_sample_cap := int(floor(float(sample_count) * 0.6))
	bins_sample_cap = clampi(bins_sample_cap, 8, 256)

	return maxi(8, mini(cfg_bins, mini(bins_geom, bins_sample_cap)))


func _order_contour_radial(center: Vector3, contour: Array) -> Array:
	if contour.size() < 3:
		return contour
	var ranked: Array = []
	for p_raw in contour:
		var p: Vector3 = p_raw
		var ang := atan2(p.z - center.z, p.x - center.x)
		ranked.append({"a": ang, "p": p})
	ranked.sort_custom(func(x, y): return float(x["a"]) < float(y["a"]))

	var ordered: Array = []
	var eps := maxf(0.01, sample_step * 0.08)
	for r in ranked:
		var p: Vector3 = r["p"]
		if ordered.is_empty():
			ordered.append(p)
			continue
		var prev: Vector3 = ordered[ordered.size() - 1]
		if _dist_xz(prev, p) > eps:
			ordered.append(p)
	if ordered.size() >= 2 and _dist_xz(ordered[0], ordered[ordered.size() - 1]) <= eps:
		ordered.remove_at(ordered.size() - 1)
	return ordered


func _untangle_contour_order(contour: Array) -> Array:
	var n := contour.size()
	if n < 4:
		return contour
	var out := contour.duplicate(true)
	var max_loops := n * n
	for _loop in range(max_loops):
		var changed := false
		for i in range(n):
			var a1: Vector3 = out[i]
			var a2: Vector3 = out[(i + 1) % n]
			for j in range(i + 2, n):
				if i == 0 and j == n - 1:
					continue
				var b1: Vector3 = out[j]
				var b2: Vector3 = out[(j + 1) % n]
				if _segments_intersect_xz(a1, a2, b1, b2):
					_reverse_array_slice(out, i + 1, j)
					changed = true
		if not changed:
			break
	return out


func _segments_intersect_xz(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3) -> bool:
	var hit = Geometry2D.segment_intersects_segment(
		Vector2(a1.x, a1.z),
		Vector2(a2.x, a2.z),
		Vector2(b1.x, b1.z),
		Vector2(b2.x, b2.z)
	)
	return hit != null


func _reverse_array_slice(arr: Array, start_idx: int, end_idx: int) -> void:
	var i := start_idx
	var j := end_idx
	while i < j:
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		i += 1
		j -= 1


func _preferred_fill_winding_sign(tris: Array, center: Vector3) -> float:
	if tris.is_empty():
		return 1.0
	var radius_hint := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55) * 1.7
	var sum := 0.0
	var count := 0
	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var tc := (a + b + c) / 3.0
		if _dist_xz(tc, center) > radius_hint:
			continue
		var ny := (b - a).cross(c - a).y
		if absf(ny) < 0.0000001:
			continue
		sum += ny
		count += 1
	if count == 0:
		return 1.0
	return 1.0 if sum >= 0.0 else -1.0


func _polygon_average_2d(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())


func _polygon_centroid_2d(poly: PackedVector2Array) -> Vector2:
	if poly.size() < 3:
		return _polygon_average_2d(poly)
	var area2 := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in range(poly.size()):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % poly.size()]
		var cross := p0.x * p1.y - p1.x * p0.y
		area2 += cross
		cx += (p0.x + p1.x) * cross
		cy += (p0.y + p1.y) * cross
	if absf(area2) < 0.0000001:
		return _polygon_average_2d(poly)
	var f := 1.0 / (3.0 * area2)
	return Vector2(cx * f, cy * f)


func _expand_polygon_radial(poly: PackedVector2Array, margin: float) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	if absf(margin) <= 0.000001:
		return poly
	var out := PackedVector2Array()
	for i in range(poly.size()):
		var p: Vector2 = poly[i]
		var dir := p.normalized()
		if dir.length_squared() < 0.000001:
			var prev: Vector2 = poly[(i - 1 + poly.size()) % poly.size()]
			var next: Vector2 = poly[(i + 1) % poly.size()]
			dir = (next - prev).orthogonal().normalized()
			if dir.length_squared() < 0.000001:
				dir = Vector2.RIGHT
		out.append(p + dir * margin)
	return out


func _triangle_area2_xz(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b - a).cross(c - a).length_squared()


func _append_oriented_triangle(out: Array, a: Vector3, b: Vector3, c: Vector3, target_winding_sign: float) -> void:
	if _triangle_area2_xz(a, b, c) < 0.0000001:
		return
	var pa := a
	var pb := b
	var pc := c
	var n := (pb - pa).cross(pc - pa)
	if n.y * target_winding_sign < 0.0:
		var tmp := pb
		pb = pc
		pc = tmp
	out.append([pa, pb, pc])


func _extract_contour_from_cut_boundary(center: Vector3, cut_tris: Array, patch_radius: float, cut_max: float) -> Array:
	if cut_tris.is_empty():
		return []

	const VERTEX_QUANT := 220.0
	var vertex_accum := {}
	var edge_counts := {}
	var edge_verts := {}

	for tri_raw in cut_tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var vkeys: Array = []
		for p_raw in tri:
			var p: Vector3 = p_raw
			var vk := _quantized_vertex_key_xz(p, VERTEX_QUANT)
			if not vertex_accum.has(vk):
				vertex_accum[vk] = {"sum": p, "count": 1}
			else:
				var acc: Dictionary = vertex_accum[vk]
				acc["sum"] = Vector3(acc["sum"]) + p
				acc["count"] = int(acc["count"]) + 1
				vertex_accum[vk] = acc
			vkeys.append(vk)

		var e01 := _edge_key_from_vertex_keys(str(vkeys[0]), str(vkeys[1]))
		var e12 := _edge_key_from_vertex_keys(str(vkeys[1]), str(vkeys[2]))
		var e20 := _edge_key_from_vertex_keys(str(vkeys[2]), str(vkeys[0]))
		for e in [e01, e12, e20]:
			if e == "":
				continue
			edge_counts[e] = int(edge_counts.get(e, 0)) + 1
		if e01 != "":
			edge_verts[e01] = [str(vkeys[0]), str(vkeys[1])]
		if e12 != "":
			edge_verts[e12] = [str(vkeys[1]), str(vkeys[2])]
		if e20 != "":
			edge_verts[e20] = [str(vkeys[2]), str(vkeys[0])]

	if edge_counts.is_empty():
		return []

	var vertex_pos := {}
	for k_raw in vertex_accum.keys():
		var k := str(k_raw)
		var acc: Dictionary = vertex_accum[k]
		var cnt := maxf(1.0, float(acc["count"]))
		vertex_pos[k] = Vector3(acc["sum"]) / cnt

	var min_mid_dist := maxf(0.08, patch_radius * 0.08)
	var max_mid_dist := cut_max * 1.45
	var adjacency := {}
	var boundary_edges: Array = []
	for e_raw in edge_counts.keys():
		var e := str(e_raw)
		if int(edge_counts[e]) != 1:
			continue
		if not edge_verts.has(e):
			continue
		var pair: Array = edge_verts[e]
		if pair.size() < 2:
			continue
		var ka := str(pair[0])
		var kb := str(pair[1])
		if ka == kb:
			continue
		if not vertex_pos.has(ka) or not vertex_pos.has(kb):
			continue
		var pa: Vector3 = vertex_pos[ka]
		var pb: Vector3 = vertex_pos[kb]
		var dmid := _dist_xz((pa + pb) * 0.5, center)
		if dmid < min_mid_dist or dmid > max_mid_dist:
			continue

		boundary_edges.append([ka, kb])
		if not adjacency.has(ka):
			adjacency[ka] = []
		if not adjacency.has(kb):
			adjacency[kb] = []
		var adj_a: Array = adjacency[ka]
		if not adj_a.has(kb):
			adj_a.append(kb)
			adjacency[ka] = adj_a
		var adj_b: Array = adjacency[kb]
		if not adj_b.has(ka):
			adj_b.append(ka)
			adjacency[kb] = adj_b

	if boundary_edges.is_empty():
		return []

	var loops := _collect_boundary_loops_xz(boundary_edges, adjacency, vertex_pos)
	if loops.is_empty():
		return []

	var best_loop: Array = []
	var best_score := -INF
	for loop_raw in loops:
		var loop: Array = loop_raw
		loop = _compact_contour_loop(loop, maxf(0.01, sample_step * 0.06))
		if loop.size() < 3:
			continue
		var poly := PackedVector2Array()
		var area2 := 0.0
		for i in range(loop.size()):
			var p: Vector3 = loop[i]
			var q: Vector3 = loop[(i + 1) % loop.size()]
			var p2 := Vector2(p.x - center.x, p.z - center.z)
			var q2 := Vector2(q.x - center.x, q.z - center.z)
			poly.append(p2)
			area2 += p2.x * q2.y - q2.x * p2.y
		var area_abs := absf(area2) * 0.5
		if area_abs < 0.0001:
			continue

		var contains_center := Geometry2D.is_point_in_polygon(Vector2.ZERO, poly)
		var centroid2 := _polygon_centroid_2d(poly)
		var score := area_abs - centroid2.length() * 0.02
		if contains_center:
			score += 1000000.0
		if score > best_score:
			best_score = score
			best_loop = loop

	return best_loop


func _collect_boundary_loops_xz(boundary_edges: Array, adjacency: Dictionary, vertex_pos: Dictionary) -> Array:
	var loops: Array = []
	var used_edges := {}

	for edge_raw in boundary_edges:
		var edge: Array = edge_raw
		if edge.size() < 2:
			continue
		var start_a := str(edge[0])
		var start_b := str(edge[1])
		var first_edge_key := _edge_key_from_vertex_keys(start_a, start_b)
		if first_edge_key == "" or used_edges.has(first_edge_key):
			continue

		var loop_keys: Array = [start_a, start_b]
		used_edges[first_edge_key] = true
		var prev := start_a
		var cur := start_b
		var closed := false
		var guard := 0
		while guard < 4096:
			guard += 1
			if not adjacency.has(cur):
				break
			var neighbors: Array = adjacency[cur]
			if neighbors.is_empty():
				break

			var prev_dir := Vector2.ZERO
			if vertex_pos.has(prev) and vertex_pos.has(cur):
				var prev_pos: Vector3 = vertex_pos[prev]
				var cur_pos: Vector3 = vertex_pos[cur]
				prev_dir = Vector2(cur_pos.x - prev_pos.x, cur_pos.z - prev_pos.z).normalized()

			var next_key := ""
			var best_score := -INF
			for n_raw in neighbors:
				var cand := str(n_raw)
				if cand == prev:
					continue
				var edge_key := _edge_key_from_vertex_keys(cur, cand)
				if edge_key == "":
					continue
				var score := 0.0
				if not used_edges.has(edge_key):
					score += 1000.0
				if prev_dir.length_squared() > 0.000001 and vertex_pos.has(cand):
					var cand_pos: Vector3 = vertex_pos[cand]
					var cur_pos2: Vector3 = vertex_pos[cur]
					var cand_dir := Vector2(cand_pos.x - cur_pos2.x, cand_pos.z - cur_pos2.z).normalized()
					score += prev_dir.dot(cand_dir)
				if score > best_score:
					best_score = score
					next_key = cand

			if next_key == "":
				break

			var next_edge := _edge_key_from_vertex_keys(cur, next_key)
			used_edges[next_edge] = true
			if next_key == loop_keys[0]:
				closed = true
				break
			if loop_keys.has(next_key):
				break

			loop_keys.append(next_key)
			prev = cur
			cur = next_key

		if closed and loop_keys.size() >= 3:
			var loop_points: Array = []
			for k_raw in loop_keys:
				var k := str(k_raw)
				if vertex_pos.has(k):
					loop_points.append(vertex_pos[k])
			if loop_points.size() >= 3:
				loops.append(loop_points)

	return loops


func _compact_contour_loop(contour: Array, eps: float) -> Array:
	if contour.size() < 3:
		return contour
	var compact: Array = []
	for p_raw in contour:
		var p: Vector3 = p_raw
		if compact.is_empty():
			compact.append(p)
			continue
		var prev: Vector3 = compact[compact.size() - 1]
		if _dist_xz(prev, p) > eps:
			compact.append(p)
	if compact.size() >= 2 and _dist_xz(compact[0], compact[compact.size() - 1]) <= eps:
		compact.remove_at(compact.size() - 1)
	if compact.size() < 4:
		return compact

	var out: Array = []
	var n := compact.size()
	for i in range(n):
		var prev: Vector3 = compact[(i - 1 + n) % n]
		var cur: Vector3 = compact[i]
		var next: Vector3 = compact[(i + 1) % n]
		var v0 := Vector2(cur.x - prev.x, cur.z - prev.z)
		var v1 := Vector2(next.x - cur.x, next.z - cur.z)
		var l0 := v0.length()
		var l1 := v1.length()
		if l0 < eps * 0.2 or l1 < eps * 0.2:
			continue
		var bend := absf(v0.x * v1.y - v0.y * v1.x) / maxf(0.0000001, l0 * l1)
		if bend < 0.0025 and minf(l0, l1) < eps * 3.0:
			continue
		out.append(cur)
	return out if out.size() >= 3 else compact


func _edge_key_from_vertex_keys(a: String, b: String) -> String:
	if a == "" or b == "" or a == b:
		return ""
	return a + "|" + b if a < b else b + "|" + a


func _quantized_vertex_key_xz(v: Vector3, quant: float) -> String:
	var qx := int(round(v.x * quant))
	var qz := int(round(v.z * quant))
	return str(qx) + "_" + str(qz)


func _quantized_vertex_key_xyz(v: Vector3, quant_xz: float, quant_y: float) -> String:
	var qx := int(round(v.x * quant_xz))
	var qy := int(round(v.y * quant_y))
	var qz := int(round(v.z * quant_xz))
	return str(qx) + "_" + str(qy) + "_" + str(qz)


func _cluster_vertex_keys_by_distance_xz(keys: Array, vertex_pos: Dictionary, max_dist: float) -> Array:
	var out: Array = []
	if keys.is_empty():
		return out
	var remaining := {}
	for k_raw in keys:
		var k := str(k_raw)
		if vertex_pos.has(k):
			remaining[k] = true
	if remaining.is_empty():
		return out

	var r := maxf(0.0001, max_dist)
	while not remaining.is_empty():
		var start := str(remaining.keys()[0])
		remaining.erase(start)
		var cluster: Array = [start]
		var queue: Array = [start]

		while not queue.is_empty():
			var current := str(queue.pop_back())
			if not vertex_pos.has(current):
				continue
			var p_cur: Vector3 = vertex_pos[current]
			var snapshot: Array = remaining.keys()
			for cand_raw in snapshot:
				var cand := str(cand_raw)
				if not remaining.has(cand):
					continue
				if not vertex_pos.has(cand):
					remaining.erase(cand)
					continue
				var p_cand: Vector3 = vertex_pos[cand]
				if _dist_xz(p_cur, p_cand) <= r:
					remaining.erase(cand)
					cluster.append(cand)
					queue.append(cand)
		out.append(cluster)

	return out


func _extract_contour_from_ring_samples(center: Vector3, samples: Array, bins: int) -> Array:
	if samples.is_empty() or bins < 3:
		return []
	var best_by_bin: Array = []
	best_by_bin.resize(bins)
	var dist_by_bin: Array = []
	dist_by_bin.resize(bins)
	for i in range(bins):
		best_by_bin[i] = null
		dist_by_bin[i] = -1.0

	for s_raw in samples:
		var s: Vector3 = s_raw
		var angle := atan2(s.z - center.z, s.x - center.x)
		var norm := (angle + PI) / TAU
		var bin := int(floor(norm * float(bins)))
		bin = clampi(bin, 0, bins - 1)
		var d := _dist_xz(s, center)
		if d > float(dist_by_bin[bin]):
			best_by_bin[bin] = s
			dist_by_bin[bin] = d

	var ordered: Array = []
	var quantized := {}
	for i in range(bins):
		var v = best_by_bin[i]
		if v == null:
			continue
		var p: Vector3 = v
		var key := str(int(round(p.x * 100.0))) + "_" + str(int(round(p.z * 100.0)))
		if quantized.has(key):
			continue
		quantized[key] = true
		ordered.append(p)
	if ordered.size() < 3:
		return []

	var compact: Array = []
	var eps := maxf(0.01, sample_step * 0.1)
	for p_raw in ordered:
		var p: Vector3 = p_raw
		if compact.is_empty():
			compact.append(p)
		else:
			var prev: Vector3 = compact[compact.size() - 1]
			if _dist_xz(prev, p) > eps:
				compact.append(p)
	if compact.size() >= 2 and _dist_xz(compact[0], compact[compact.size() - 1]) <= eps:
		compact.remove_at(compact.size() - 1)
	return compact


func _mesh_from_triangles(tris: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if material_override:
		st.set_material(material_override)
	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		_add_triangle(st, tri[0], tri[1], tri[2])
	st.generate_normals()
	var mesh := st.commit()
	return mesh if mesh != null else ArrayMesh.new()


func _cleanup_triangles(tris: Array) -> Array:
	var out: Array = []
	var seen := {}
	const QUANT := 200.0
	for tri_raw in tris:
		var tri: Array = tri_raw
		if tri.size() < 3:
			continue
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var area2 := (b - a).cross(c - a).length_squared()
		if area2 < 0.0000001:
			continue
		var key := _triangle_key_quantized(a, b, c, QUANT)
		if seen.has(key):
			continue
		seen[key] = true
		out.append([a, b, c])
	return out


func _triangle_key_quantized(a: Vector3, b: Vector3, c: Vector3, quant: float) -> String:
	var keys: Array = [
		_quantized_vertex_key(a, quant),
		_quantized_vertex_key(b, quant),
		_quantized_vertex_key(c, quant),
	]
	keys.sort()
	return str(keys[0]) + "|" + str(keys[1]) + "|" + str(keys[2])


func _quantized_vertex_key(v: Vector3, quant: float) -> String:
	var qx := int(round(v.x * quant))
	var qy := int(round(v.y * quant))
	var qz := int(round(v.z * quant))
	return str(qx) + "_" + str(qy) + "_" + str(qz)


func _move_endpoint_width_with_blend(path_data: Array, endpoint: Dictionary, target_half_width: float) -> void:
	var data: Dictionary = path_data[int(endpoint["path_idx"])]
	var widths: Array = data["widths"]
	var pts: Array = data["points"]
	if widths.is_empty() or pts.is_empty():
		return
	var idx := 0 if bool(endpoint["is_start"]) else widths.size() - 1
	if idx < 0 or idx >= widths.size():
		return

	var target_width := maxf(0.2, target_half_width * 2.0)
	var old_width := float(widths[idx])
	var delta := target_width - old_width
	if absf(delta) < 0.000001:
		return
	widths[idx] = target_width

	var blend_n := maxi(0, junction_endpoint_blend_points)
	if blend_n <= 0:
		return
	var max_dist := maxf(sample_step * float(blend_n), sample_step)
	var cumulative := 0.0
	if bool(endpoint["is_start"]):
		for p_idx in range(1, mini(widths.size(), pts.size())):
			cumulative += pts[p_idx].distance_to(pts[p_idx - 1])
			if cumulative > max_dist:
				break
			var w := 1.0 - (cumulative / max_dist)
			widths[p_idx] = maxf(0.2, float(widths[p_idx]) + delta * w)
	else:
		for p_idx in range(mini(widths.size(), pts.size()) - 2, -1, -1):
			cumulative += pts[p_idx].distance_to(pts[p_idx + 1])
			if cumulative > max_dist:
				break
			var w := 1.0 - (cumulative / max_dist)
			widths[p_idx] = maxf(0.2, float(widths[p_idx]) + delta * w)


func _move_endpoint_with_blend(path_data: Array, endpoint: Dictionary, target_pos: Vector3) -> void:
	var data: Dictionary = path_data[int(endpoint["path_idx"])]
	var pts: Array = data["points"]
	var idx := 0 if bool(endpoint["is_start"]) else pts.size() - 1
	var old_pos: Vector3 = pts[idx]
	var delta := target_pos - old_pos
	if delta.length_squared() < 0.0000001:
		return
	pts[idx] = target_pos
	var blend_n := maxi(0, junction_endpoint_blend_points)
	if blend_n <= 0:
		return
	var max_dist := maxf(sample_step * float(blend_n), sample_step)
	var cumulative := 0.0
	if bool(endpoint["is_start"]):
		for p_idx in range(1, pts.size()):
			cumulative += pts[p_idx].distance_to(pts[p_idx - 1])
			if cumulative > max_dist:
				break
			var w := 1.0 - (cumulative / max_dist)
			pts[p_idx] = pts[p_idx] + delta * w
	else:
		for p_idx in range(pts.size() - 2, -1, -1):
			cumulative += pts[p_idx].distance_to(pts[p_idx + 1])
			if cumulative > max_dist:
				break
			var w := 1.0 - (cumulative / max_dist)
			pts[p_idx] = pts[p_idx] + delta * w


func _closest_point_on_segment_xz(p: Vector3, a: Vector3, b: Vector3) -> Dictionary:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var ab_len2 := ab.length_squared()
	var t := 0.0
	if ab_len2 > 0.0000001:
		t = clampf(ap.dot(ab) / ab_len2, 0.0, 1.0)
	var pos := a.lerp(b, t)
	var dist := _dist_xz(p, pos)
	return {"t": t, "pos": pos, "dist": dist}


func _dist_xz(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _get_path_settings(path: Path3D) -> Dictionary:
	var settings := {
		"road_width": road_width,
		"sample_step": sample_step,
		"y_offset": y_offset,
		"shoulder_left_width": shoulder_left_width,
		"shoulder_right_width": shoulder_right_width,
		"sidewalk_left_width": sidewalk_left_width,
		"sidewalk_right_width": sidewalk_right_width,
		"use_per_point_profiles": false,
		"per_point_widths": PackedFloat32Array(),
		"per_point_bank_degrees": PackedFloat32Array(),
	}
	if not enable_per_path_overrides:
		return settings
	if path != null and path.has_method("get_road_builder_settings"):
		var overrides = path.call("get_road_builder_settings")
		if overrides is Dictionary:
			if overrides.has("road_width"):
				settings["road_width"] = maxf(0.2, float(overrides["road_width"]))
			if overrides.has("sample_step"):
				settings["sample_step"] = maxf(0.1, float(overrides["sample_step"]))
			if overrides.has("y_offset"):
				settings["y_offset"] = float(overrides["y_offset"])
			if overrides.has("shoulder_left_width"):
				settings["shoulder_left_width"] = maxf(0.0, float(overrides["shoulder_left_width"]))
			if overrides.has("shoulder_right_width"):
				settings["shoulder_right_width"] = maxf(0.0, float(overrides["shoulder_right_width"]))
			if overrides.has("sidewalk_left_width"):
				settings["sidewalk_left_width"] = maxf(0.0, float(overrides["sidewalk_left_width"]))
			if overrides.has("sidewalk_right_width"):
				settings["sidewalk_right_width"] = maxf(0.0, float(overrides["sidewalk_right_width"]))
			if overrides.has("use_per_point_profiles"):
				settings["use_per_point_profiles"] = overrides["use_per_point_profiles"] == true
			if overrides.has("per_point_widths"):
				settings["per_point_widths"] = overrides["per_point_widths"]
			if overrides.has("per_point_bank_degrees"):
				settings["per_point_bank_degrees"] = overrides["per_point_bank_degrees"]
	return settings


func _sample_control_profile(values: PackedFloat32Array, t_norm: float, fallback: float) -> float:
	if values.is_empty():
		return fallback
	if values.size() == 1:
		return values[0]
	var s := clampf(t_norm, 0.0, 1.0) * float(values.size() - 1)
	var i0 := int(floor(s))
	var i1 := mini(i0 + 1, values.size() - 1)
	var a := s - float(i0)
	return lerpf(values[i0], values[i1], a)


func _build_sample_distances(curve: Curve3D, total_len: float, base_step: float) -> Array:
	var dists: Array = [0.0]
	if total_len <= 0.001:
		return dists
	var step_base := maxf(0.05, base_step)
	var step_min := maxf(0.05, step_base * 0.25)
	if not adaptive_sampling:
		var d := step_base
		while d < total_len:
			dists.append(d)
			d += step_base
		dists.append(total_len)
		return dists

	var d_adapt := 0.0
	while d_adapt < total_len:
		var step := _adaptive_step_for_distance(curve, total_len, d_adapt, step_base, step_min)
		d_adapt = minf(total_len, d_adapt + step)
		if dists[dists.size() - 1] != d_adapt:
			dists.append(d_adapt)
	if dists[dists.size() - 1] != total_len:
		dists.append(total_len)
	return dists


func _adaptive_step_for_distance(curve: Curve3D, total_len: float, d: float, step_base: float, step_min: float) -> float:
	const CURVATURE_FULL_EFFECT_DEG := 22.0
	const SLOPE_FULL_EFFECT_DEG := 16.0
	const CURVATURE_INFLUENCE := 0.7
	const SLOPE_INFLUENCE := 0.6

	var probe := minf(1.0, step_base * 0.5)
	var prev_d := maxf(0.0, d - probe)
	var next_d := minf(total_len, d + probe)
	var p_prev: Vector3 = curve.sample_baked(prev_d, true)
	var p_now: Vector3 = curve.sample_baked(d, true)
	var p_next: Vector3 = curve.sample_baked(next_d, true)
	var t0 := (p_now - p_prev).normalized()
	var t1 := (p_next - p_now).normalized()
	if t0.length_squared() < 0.000001 or t1.length_squared() < 0.000001:
		return step_base

	var curve_angle := rad_to_deg(acos(clampf(t0.dot(t1), -1.0, 1.0)))
	var slope_angle := rad_to_deg(asin(clampf(absf(t1.y), 0.0, 1.0)))
	var curve_factor := clampf(curve_angle / maxf(0.001, CURVATURE_FULL_EFFECT_DEG), 0.0, 1.0) * CURVATURE_INFLUENCE
	var slope_factor := clampf(slope_angle / maxf(0.001, SLOPE_FULL_EFFECT_DEG), 0.0, 1.0) * SLOPE_INFLUENCE
	var influence := clampf(maxf(curve_factor, slope_factor), 0.0, 1.0)
	return lerpf(step_base, step_min, influence)


func _safe_right_from_dir_and_up(dir: Vector3, up: Vector3) -> Vector3:
	var right := up.cross(dir).normalized()
	if right.length_squared() >= 0.000001:
		return right
	right = Vector3.FORWARD.cross(dir).normalized()
	if right.length_squared() >= 0.000001:
		return right
	return Vector3.RIGHT


func _assign_mesh(mesh: ArrayMesh) -> void:
	var mi: MeshInstance3D = get_node_or_null(MESH_NODE_NAME)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MESH_NODE_NAME
		add_child(mi)
		_assign_owner(mi)
	mi.mesh = mesh
	if material_override:
		mi.material_override = material_override


func _clear_mesh_node() -> void:
	var mi: MeshInstance3D = get_node_or_null(MESH_NODE_NAME)
	if mi:
		mi.queue_free()
	_last_weld_hints.clear()
	_clear_debug_mesh_copy()
	_clear_debug_repair_overlay()


func _sync_debug_mesh_copy(mesh: ArrayMesh, weld_hints: Array) -> void:
	if not debug_show_mesh_copy:
		_clear_debug_mesh_copy()
		return
	var debug_mesh := _build_intersection_debug_mesh(mesh, weld_hints)
	if debug_mesh == null or debug_mesh.get_surface_count() == 0:
		_clear_debug_mesh_copy()
		return
	var copy: MeshInstance3D = get_node_or_null(DEBUG_MESH_NODE_NAME)
	if copy == null:
		copy = MeshInstance3D.new()
		copy.name = DEBUG_MESH_NODE_NAME
		add_child(copy)
		_assign_owner(copy)
	copy.mesh = debug_mesh
	if material_override:
		copy.material_override = material_override
	else:
		copy.material_override = null
	copy.transform = Transform3D.IDENTITY
	copy.position = Vector3(0.0, debug_mesh_copy_height, 0.0)


func _sync_debug_repair_overlay(mesh: ArrayMesh) -> void:
	if not debug_show_repair_overlay:
		_clear_debug_repair_overlay()
		return
	if mesh == null or mesh.get_surface_count() == 0:
		_clear_debug_repair_overlay()
		return
	_collect_debug_boundary_info(mesh)

	var root: Node3D = get_node_or_null(DEBUG_REPAIR_NODE_NAME)
	if root == null:
		root = Node3D.new()
		root.name = DEBUG_REPAIR_NODE_NAME
		add_child(root)
		_assign_owner(root)
	root.position = Vector3(0.0, debug_repair_overlay_height, 0.0)

	_rebuild_debug_overlay_child_lines(
		root,
		"BoundaryEdges",
		_debug_boundary_segments,
		Color(1.0, 0.9, 0.1, 0.95)
	)
	_rebuild_debug_overlay_child_crosses(
		root,
		"DeadEnds",
		_debug_dead_end_points,
		maxf(0.035, sample_step * 0.15),
		Color(1.0, 0.15, 1.0, 0.95)
	)

	var contour_segments: Array = []
	if debug_show_recap_contours:
		for contour_raw in _debug_recap_contours:
			var contour: Array = contour_raw
			if contour.size() < 2:
				continue
			for i in range(contour.size()):
				var a: Vector3 = contour[i]
				var b: Vector3 = contour[(i + 1) % contour.size()]
				contour_segments.append([a, b])
	_rebuild_debug_overlay_child_lines(
		root,
		"RecapContours",
		contour_segments,
		Color(0.2, 0.95, 1.0, 0.95)
	)
	_rebuild_debug_overlay_child_crosses(
		root,
		"RemovedTriangles",
		_debug_removed_tri_centers,
		maxf(0.02, sample_step * 0.09),
		Color(1.0, 0.25, 0.2, 0.95)
	)
	_rebuild_debug_overlay_child_crosses(
		root,
		"AddedTriangles",
		_debug_added_tri_centers,
		maxf(0.02, sample_step * 0.09),
		Color(0.25, 1.0, 0.25, 0.95)
	)


func _collect_debug_boundary_info(mesh: ArrayMesh) -> void:
	_debug_boundary_segments.clear()
	_debug_dead_end_points.clear()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return
	var tris: Array = []
	for i in range(0, verts.size(), 3):
		if i + 2 >= verts.size():
			break
		tris.append([verts[i], verts[i + 1], verts[i + 2]])
	if tris.is_empty():
		return

	var segments := _extract_boundary_segments_xz(tris, 280.0)
	for s_raw in segments:
		var s: Dictionary = s_raw
		_debug_boundary_segments.append([Vector3(s["a"]), Vector3(s["b"])])

	var adjacency := {}
	for s_raw in segments:
		var s: Dictionary = s_raw
		var ka := str(s["ka"])
		var kb := str(s["kb"])
		if not adjacency.has(ka):
			adjacency[ka] = []
		if not adjacency.has(kb):
			adjacency[kb] = []
		var a_ns: Array = adjacency[ka]
		if not a_ns.has(kb):
			a_ns.append(kb)
			adjacency[ka] = a_ns
		var b_ns: Array = adjacency[kb]
		if not b_ns.has(ka):
			b_ns.append(ka)
			adjacency[kb] = b_ns

	var key_to_pos := {}
	for s_raw in segments:
		var s: Dictionary = s_raw
		key_to_pos[str(s["ka"])] = Vector3(s["a"])
		key_to_pos[str(s["kb"])] = Vector3(s["b"])

	for k_raw in adjacency.keys():
		var k := str(k_raw)
		var ns: Array = adjacency[k]
		if ns.size() == 1 and key_to_pos.has(k):
			_debug_dead_end_points.append(Vector3(key_to_pos[k]))


func _rebuild_debug_overlay_child_lines(root: Node3D, child_name: String, segments: Array, color: Color) -> void:
	var child: MeshInstance3D = root.get_node_or_null(child_name)
	if segments.is_empty():
		if child != null:
			child.queue_free()
		return

	var mesh := _build_line_mesh(segments)
	if mesh == null:
		if child != null:
			child.queue_free()
		return
	if child == null:
		child = MeshInstance3D.new()
		child.name = child_name
		root.add_child(child)
		_assign_owner(child)
	child.mesh = mesh
	child.material_override = _make_debug_unshaded_material(color)


func _rebuild_debug_overlay_child_crosses(root: Node3D, child_name: String, points: Array, size: float, color: Color) -> void:
	var child: MeshInstance3D = root.get_node_or_null(child_name)
	if points.is_empty():
		if child != null:
			child.queue_free()
		return
	var segments: Array = []
	var s := maxf(0.002, size)
	for p_raw in points:
		var p: Vector3 = p_raw
		segments.append([p + Vector3(-s, 0.0, 0.0), p + Vector3(s, 0.0, 0.0)])
		segments.append([p + Vector3(0.0, -s, 0.0), p + Vector3(0.0, s, 0.0)])
		segments.append([p + Vector3(0.0, 0.0, -s), p + Vector3(0.0, 0.0, s)])

	var mesh := _build_line_mesh(segments)
	if mesh == null:
		if child != null:
			child.queue_free()
		return
	if child == null:
		child = MeshInstance3D.new()
		child.name = child_name
		root.add_child(child)
		_assign_owner(child)
	child.mesh = mesh
	child.material_override = _make_debug_unshaded_material(color)


func _build_line_mesh(segments: Array) -> ArrayMesh:
	if segments.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for seg_raw in segments:
		var seg: Array = seg_raw
		if seg.size() < 2:
			continue
		st.add_vertex(Vector3(seg[0]))
		st.add_vertex(Vector3(seg[1]))
	var mesh := st.commit()
	return mesh if mesh != null else null


func _make_debug_unshaded_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _debug_push_point(out: Array, p: Vector3, max_points: int = 5000) -> void:
	if out.size() >= max_points:
		return
	out.append(p)


func _build_intersection_debug_mesh(mesh: ArrayMesh, weld_hints: Array) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0 or weld_hints.is_empty():
		return ArrayMesh.new()
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return ArrayMesh.new()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return ArrayMesh.new()

	var centers := _collect_unique_hint_centers(weld_hints)
	if centers.is_empty():
		return ArrayMesh.new()
	var radius := maxf(intersection_fill_radius * intersection_recap_radius_scale, road_width * 0.55)
	radius += maxf(0.0, intersection_seam_cleanup_margin) + sample_step * 0.15

	var picked: Array = []
	for i in range(0, verts.size(), 3):
		if i + 2 >= verts.size():
			break
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[i + 1]
		var c: Vector3 = verts[i + 2]
		for center_raw in centers:
			var center: Vector3 = center_raw
			if _triangle_near_center_xz(a, b, c, center, radius):
				picked.append([a, b, c])
				break
	if picked.is_empty():
		return ArrayMesh.new()
	picked = _cleanup_triangles(picked)
	return _mesh_from_triangles(picked)


func _triangle_near_center_xz(a: Vector3, b: Vector3, c: Vector3, center: Vector3, radius: float) -> bool:
	var r := maxf(0.0001, radius)
	if _dist_xz(a, center) <= r or _dist_xz(b, center) <= r or _dist_xz(c, center) <= r:
		return true
	var tc := (a + b + c) / 3.0
	if _dist_xz(tc, center) <= r:
		return true
	var dab := float((_closest_point_on_segment_xz(center, a, b)).get("dist", INF))
	var dbc := float((_closest_point_on_segment_xz(center, b, c)).get("dist", INF))
	var dca := float((_closest_point_on_segment_xz(center, c, a)).get("dist", INF))
	return minf(dab, minf(dbc, dca)) <= r


func _clear_debug_mesh_copy() -> void:
	var copy: MeshInstance3D = get_node_or_null(DEBUG_MESH_NODE_NAME)
	if copy:
		copy.queue_free()


func _clear_debug_repair_overlay() -> void:
	var node: Node3D = get_node_or_null(DEBUG_REPAIR_NODE_NAME)
	if node:
		node.queue_free()


func _assign_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_tree().edited_scene_root
	if root:
		node.owner = root


func _on_property_list_changed() -> void:
	_queue_regenerate()


func _on_editor_state_changed() -> void:
	_queue_regenerate()
