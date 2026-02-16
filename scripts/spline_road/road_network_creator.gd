@tool
extends Node3D

@export_group("Sources")
@export var source_paths: Array[NodePath] = []

@export_group("Road")
@export_range(0.2, 50.0, 0.1) var road_width := 6.0
@export_range(0.1, 10.0, 0.1) var sample_step := 0.5
@export_range(-5.0, 5.0, 0.01) var y_offset := 0.0
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
@export_subgroup("Terrain")
@export_range(0.0, 50.0, 0.1) var terrain_left_width := 0.0
@export_range(0.0, 50.0, 0.1) var terrain_right_width := 0.0
@export_range(-1.0, 2.0, 0.001) var terrain_road_clearance := 0.02
@export_range(0.1, 1.0, 0.05) var terrain_detection_width_scale := 1.0
@export_range(0.05, 5.0, 0.05) var terrain_growth_scan_step := 0.25
@export_range(0.0, 20.0, 0.05) var terrain_growth_max_delta_per_row := 1.25
@export_range(0.0, 200.0, 0.1) var terrain_skirt_depth := 0.0
@export_range(1, 12, 1) var terrain_skirt_segments := 3
@export_range(0.0, 50.0, 0.05) var terrain_skirt_outward := 1.0
@export_range(0.1, 4.0, 0.1) var terrain_skirt_profile := 1.4
@export_range(0.0, 89.0, 0.5) var terrain_skirt_soften_slope_deg := 12.0
@export_range(0.0, 30.0, 0.05) var terrain_skirt_soften_max_drop := 1.0
@export_range(0.1, 4.0, 0.1) var terrain_skirt_soften_power := 1.2
@export_range(1, 12, 1) var terrain_skirt_soften_area_rings := 3
@export_range(0.1, 4.0, 0.1) var terrain_skirt_soften_area_falloff := 1.6
@export_range(0, 4, 1) var terrain_skirt_soften_row_smooth_passes := 1
@export_range(1, 100, 1) var terrain_subdivisions := 1
@export_subgroup("Terrain Adaptive Subdivisions")
@export var terrain_adaptive_subdivisions_enabled := true
@export_range(0.0, 2.0, 0.01) var terrain_adaptive_subdivisions_per_meter := 0.15
@export_range(0.1, 4.0, 0.1) var terrain_adaptive_noise_quality := 1.5
@export_range(1, 256, 1) var terrain_adaptive_subdivisions_max := 80
@export var terrain_noise_enabled := false
@export_range(0.0, 30.0, 0.01) var terrain_noise_amplitude := 0.0
@export_range(0.001, 2.0, 0.001) var terrain_noise_frequency := 0.06
@export var terrain_noise_seed := 1337
@export_range(0.0, 4.0, 0.1) var terrain_noise_falloff := 1.5
@export_subgroup("Terrain Heightmap CPU")
@export var terrain_heightmap_enabled := false
@export var terrain_heightmap_texture: Texture2D
@export_range(-100.0, 100.0, 0.01) var terrain_heightmap_amplitude := 0.0
@export var terrain_heightmap_signed := true
@export var terrain_heightmap_invert := false
@export var terrain_heightmap_uv_scale := Vector2(0.03, 0.03)
@export var terrain_heightmap_uv_offset := Vector2.ZERO
@export_range(0.0, 4.0, 0.1) var terrain_heightmap_falloff := 1.5
@export_enum("Balanced (Cut+Fill)", "Cut Only", "Fill Only") var terrain_cut_fill_mode := 0
@export var terrain_artifact_safe_stitch := true
@export_range(0, 4, 1) var terrain_chain_smooth_passes := 1
@export var terrain_material_override: Material
@export_range(0.01, 20.0, 0.01) var uv_length_scale := 0.2
@export_group("Mesh Orientation")
@export var invert_faces := false
@export var material_override: Material

@export_group("Terrain Fill Boolean")
@export var terrain_boolean_fill_enabled := false
@export_range(0.0, 500.0, 0.1) var terrain_boolean_padding := 25.0
@export_range(-100.0, 100.0, 0.01) var terrain_boolean_base_height := 0.0
@export_range(0.001, 1.0, 0.001) var terrain_boolean_height_match_epsilon := 0.05
@export_range(0.0, 2.0, 0.01) var terrain_boolean_height_match_max_distance := 0.2
@export_enum("Boolean Cleanup", "Fill (Blender-like)") var terrain_boolean_solver_mode := 1
@export_enum("Outer (Lane+Shoulder+Sidewalk)", "Lane Only") var terrain_boolean_clip_width_mode := 1

@export_group("Terrain Fill Rectangle")
@export var terrain_rect_fill_enabled := false
@export_range(0.1, 20.0, 0.1) var terrain_rect_fill_cell_size := 1.0
@export_range(1000, 4000000, 1000) var terrain_rect_fill_max_cells := 250000
@export_range(0.0, 500.0, 0.1) var terrain_rect_fill_padding := 25.0
@export_range(-100.0, 100.0, 0.01) var terrain_rect_fill_base_height := 0.0
@export_range(0.001, 1.0, 0.001) var terrain_rect_fill_height_match_epsilon := 0.05
@export_range(0.0, 2.0, 0.01) var terrain_rect_fill_height_match_max_distance := 0.2
@export_range(0.0, 2.0, 0.001) var terrain_rect_fill_road_margin := 0.0
@export_enum("Outer (Lane+Shoulder+Sidewalk)", "Lane Only") var terrain_rect_fill_clip_width_mode := 1

@export_group("Weld")
@export_range(0.1, 30.0, 0.1) var endpoint_snap_distance := 2.0
@export var allow_endpoint_to_midpath := true
@export_range(2, 8, 1) var minimum_connections := 2
@export var strip_shoulder_sidewalk_at_intersections := true
@export_range(0.0, 30.0, 0.001) var intersection_strip_length := 0.0
@export var adaptive_sampling_enabled := true
@export_subgroup("Adaptive Sampling", "adaptive_sampling_")
@export var adaptive_sampling_advanced := false: set = _set_adaptive_sampling_advanced
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_step_scale := 1.0
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_radius_scale := 1.0
@export_range(-10.0, 10.0, 0.01) var adaptive_sampling_offset := 0.0

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_regenerate_in_editor := true
@export var regenerate_now := false: set = _set_regenerate_now
@export var debug_generation_logs := true

const MESH_NODE_NAME := "GeneratedSplineRoadWelded"
const LEGACY_MESH_NODE_NAME := "GeneratedSplineRoad"
const STRIP_SIDE_BOTH := 0
const STRIP_SIDE_LEFT := -1
const STRIP_SIDE_RIGHT := 1
const TERRAIN_CUT_FILL_BALANCED := 0
const TERRAIN_CUT_FILL_CUT_ONLY := 1
const TERRAIN_CUT_FILL_FILL_ONLY := 2
const TERRAIN_BOOLEAN_SOLVER_BOOLEAN := 0
const TERRAIN_BOOLEAN_SOLVER_FILL := 1
const TERRAIN_BOOLEAN_CLIP_OUTER := 0
const TERRAIN_BOOLEAN_CLIP_LANE_ONLY := 1
const TERRAIN_RECT_CLIP_OUTER := 0
const TERRAIN_RECT_CLIP_LANE_ONLY := 1

var _last_signature := ""


func _ready() -> void:
	set_process(true)
	if _can_generate():
		regenerate()
	else:
		_debug_log("_ready skipped regenerate: _can_generate() is false.")


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


func _set_adaptive_sampling_advanced(value: bool) -> void:
	adaptive_sampling_advanced = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	if (
		property.name == "adaptive_sampling_step_scale"
		or property.name == "adaptive_sampling_radius_scale"
		or property.name == "adaptive_sampling_offset"
	) and not adaptive_sampling_advanced:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _can_generate() -> bool:
	return not Engine.is_editor_hint() or generate_in_editor


func _debug_log(message: String) -> void:
	if not debug_generation_logs:
		return
	print("[SplineRoadWelded] " + message)


func regenerate() -> void:
	_debug_log("regenerate() start on " + str(get_path()))
	_cleanup_legacy_generated_children()

	var paths := _resolve_paths()
	_debug_log("resolved paths: " + str(paths.size()) + " (source_paths=" + str(source_paths.size()) + ")")
	if paths.is_empty():
		if not source_paths.is_empty():
			push_warning("SplineRoadWelded: no valid Path3D found in source_paths.")
		_debug_log("no valid paths, clearing generated mesh node.")
		_clear_mesh_node()
		return

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var lane_indices := PackedInt32Array()
	var shoulder_indices := PackedInt32Array()
	var sidewalk_indices := PackedInt32Array()
	var terrain_indices := PackedInt32Array()
	var wall_indices := PackedInt32Array()
	var sockets: Array[Dictionary] = []
	var socket_keys: Dictionary = {}
	var path_rows: Array = []
	path_rows.resize(paths.size())
	var inv_global := global_transform.affine_inverse()
	var endpoint_positions_by_path: Array = _collect_path_endpoints(paths, inv_global)
	var path_weld_snap: Array = []
	path_weld_snap.resize(paths.size())
	var path_weld_allow_midpath: Array = []
	path_weld_allow_midpath.resize(paths.size())
	var path_weld_strip_enabled: Array = []
	path_weld_strip_enabled.resize(paths.size())
	var path_weld_strip_length: Array = []
	path_weld_strip_length.resize(paths.size())

	for path_idx in range(paths.size()):
		var path := paths[path_idx]
		var rows_info: Array[Dictionary] = []
		var weld_snap := _resolve_path_weld_endpoint_snap_distance(path)
		var weld_allow_midpath := _resolve_path_weld_allow_endpoint_to_midpath(path)
		var weld_strip_enabled := _resolve_path_weld_strip_shoulder_sidewalk(path)
		var weld_strip_length := _resolve_path_weld_intersection_strip_length(path)
		var path_has_adaptive_override: bool = _path_has_adaptive_sampling_overrides(path)
		var path_adaptive_enabled: bool = _resolve_path_adaptive_sampling_enabled(path)
		var path_adaptive_advanced: bool = _resolve_path_adaptive_sampling_advanced(path)
		var path_adaptive_step_scale: float = _resolve_path_adaptive_sampling_step_scale(path)
		var path_adaptive_radius_scale: float = _resolve_path_adaptive_sampling_radius_scale(path)
		var path_adaptive_offset: float = _resolve_path_adaptive_sampling_offset(path)
		path_weld_snap[path_idx] = weld_snap
		path_weld_allow_midpath[path_idx] = weld_allow_midpath
		path_weld_strip_enabled[path_idx] = weld_strip_enabled
		path_weld_strip_length[path_idx] = weld_strip_length

		if path == null or path.curve == null:
			path_rows[path_idx] = rows_info
			continue

		var curve := path.curve
		if curve.point_count < 2:
			path_rows[path_idx] = rows_info
			continue

		curve.bake_interval = max(sample_step, 0.01)
		var length := curve.get_baked_length()
		if length <= 0.0:
			path_rows[path_idx] = rows_info
			continue

		var path_to_mesh := inv_global * path.global_transform
		var distances := _build_open_distances(length)
		if not path_adaptive_enabled:
			_debug_log(
				"adaptive path=%s enabled=false override=%s"
				% [path_idx, path_has_adaptive_override]
			)
		if path_adaptive_enabled:
			var local_step: float = _compute_adaptive_local_step(path_adaptive_step_scale)
			var local_radius: float = _compute_adaptive_local_radius(
				local_step,
				path_adaptive_radius_scale
			)
			var anchors: PackedFloat32Array = _collect_adaptive_anchor_offsets(
				path_idx,
				curve,
				path_to_mesh,
				endpoint_positions_by_path,
				weld_snap * 1.5
			)
			if anchors.is_empty():
				# Keep adaptive responsive even when no intersection anchors are detected.
				distances = _build_open_distances_with_step(length, local_step)
			else:
				anchors = _apply_adaptive_anchor_offset(
					anchors,
					length,
					path_adaptive_advanced,
					path_adaptive_offset
				)
				distances = _build_open_distances_with_anchors(length, anchors, local_step, local_radius)
			_debug_log(
				"adaptive path=%s enabled=%s override=%s advanced=%s anchors=%s step=%.3f radius=%.3f rows=%s"
				% [path_idx, path_adaptive_enabled, path_has_adaptive_override, path_adaptive_advanced, anchors.size(), local_step, local_radius, distances.size()]
			)
		if distances.size() < 2:
			path_rows[path_idx] = rows_info
			continue

		var row_edges: Array = []
		var row_centers: Array[Vector3] = []
		var row_widths := PackedFloat32Array()
		var row_lane_widths := PackedFloat32Array()
		var row_shoulder_left_widths := PackedFloat32Array()
		var row_shoulder_right_widths := PackedFloat32Array()
		var row_sidewalk_left_widths := PackedFloat32Array()
		var row_sidewalk_right_widths := PackedFloat32Array()
		var row_terrain_left_widths := PackedFloat32Array()
		var row_terrain_right_widths := PackedFloat32Array()
		var row_outer_wall_heights := PackedFloat32Array()

		for i in range(distances.size()):
			var dist := distances[i]
			var p_local := curve.sample_baked(dist, true)
			var p_mesh := path_to_mesh * p_local
			var lane_width := _resolve_path_width(path, dist, length)
			var shoulder_left := _resolve_path_shoulder_left(path, dist, length)
			var shoulder_right := _resolve_path_shoulder_right(path, dist, length)
			var sidewalk_left := _resolve_path_sidewalk_left(path, dist, length)
			var sidewalk_right := _resolve_path_sidewalk_right(path, dist, length)
			var local_terrain_widths := _resolve_path_terrain_widths(path, dist, length)
			var local_terrain_left := local_terrain_widths.x
			var local_terrain_right := local_terrain_widths.y
			var local_sidewalk_height := _resolve_path_sidewalk_height(path, dist, length)
			var local_outer_wall_height := _resolve_path_outer_wall_height(path, dist, length)
			var total_width := lane_width + shoulder_left + shoulder_right + sidewalk_left + sidewalk_right
			var up_local := _sample_curve_up_vector(curve, dist)
			var up_mesh := (path_to_mesh.basis * up_local).normalized()
			if up_mesh.length() < 0.001:
				up_mesh = Vector3.UP

			var prev_dist: float = max(0.0, dist - 0.1)
			var next_dist: float = min(length, dist + 0.1)
			if is_equal_approx(next_dist, prev_dist):
				if next_dist < length:
					next_dist = min(length, next_dist + 0.1)
				elif prev_dist > 0.0:
					prev_dist = max(0.0, prev_dist - 0.1)
			var p_prev_mesh := path_to_mesh * curve.sample_baked(prev_dist, true)
			var p_next_mesh := path_to_mesh * curve.sample_baked(next_dist, true)

			var tangent := (p_next_mesh - p_prev_mesh).normalized()
			if tangent.length() < 0.001:
				tangent = (p_next_mesh - p_mesh).normalized()
			if tangent.length() < 0.001:
				tangent = (p_mesh - p_prev_mesh).normalized()
			if tangent.length() < 0.001:
				tangent = Vector3.FORWARD

			var right := up_mesh.cross(tangent).normalized()
			if right.length() < 0.001:
				right = Vector3.UP.cross(tangent).normalized()
			if right.length() < 0.001:
				right = Vector3.RIGHT
			up_mesh = tangent.cross(right).normalized()
			if up_mesh.length() < 0.001:
				up_mesh = Vector3.UP

			var lane_half := lane_width * 0.5
			var left_lane := p_mesh - right * lane_half
			var right_lane := p_mesh + right * lane_half
			var left_shoulder := p_mesh - right * (lane_half + shoulder_left)
			var right_shoulder := p_mesh + right * (lane_half + shoulder_right)
			var left_outer := p_mesh - right * (lane_half + shoulder_left + sidewalk_left)
			var right_outer := p_mesh + right * (lane_half + shoulder_right + sidewalk_right)
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
				var p_edge: Vector3 = edge_points[edge_idx]
				p_edge.y += y_offset
				var vi := verts.size()
				verts.push_back(p_edge)
				normals.push_back(up_mesh)
				uvs.push_back(Vector2(float(edge_us[edge_idx]), v))
				row[edge_idx] = vi

			row_edges.push_back(row)
			row_centers.push_back(Vector3(p_mesh.x, p_mesh.y + y_offset, p_mesh.z))
			row_widths.push_back(maxf(0.1, total_width))
			row_lane_widths.push_back(maxf(0.1, lane_width))
			row_shoulder_left_widths.push_back(maxf(0.0, shoulder_left))
			row_shoulder_right_widths.push_back(maxf(0.0, shoulder_right))
			row_sidewalk_left_widths.push_back(maxf(0.0, sidewalk_left))
			row_sidewalk_right_widths.push_back(maxf(0.0, sidewalk_right))
			row_terrain_left_widths.push_back(maxf(0.0, local_terrain_left))
			row_terrain_right_widths.push_back(maxf(0.0, local_terrain_right))
			row_outer_wall_heights.push_back(maxf(0.0, local_outer_wall_height))

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

		path_rows[path_idx] = rows_info

		if rows_info.size() >= 2:
			_add_socket_unique(sockets, socket_keys, rows_info[0], true)
			_add_socket_unique(sockets, socket_keys, rows_info[rows_info.size() - 1], true)

	var endpoint_count := sockets.size()
	if endpoint_count > 0:
		_augment_with_midpath_sockets(
			sockets,
			socket_keys,
			path_rows,
			endpoint_count,
			path_weld_allow_midpath,
			path_weld_snap
		)
	_augment_with_midpath_pair_sockets(
		sockets,
		socket_keys,
		path_rows,
		path_weld_allow_midpath,
		path_weld_snap
	)
	var paths_with_mid_intersections: Dictionary = {}
	for s in sockets:
		if not bool(s.get("is_endpoint", true)):
			paths_with_mid_intersections[int(s.get("path_id", -1))] = true
	var stripped_side_indices: Dictionary = {}

	if sockets.size() < minimum_connections:
		if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
			_append_lane_fallback_from_path_rows(lane_indices, path_rows)
		if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
			_debug_log("no indices after fallback (low sockets branch), clearing mesh node.")
			_clear_mesh_node()
			return
		_debug_log(
			"assign mesh (low sockets): verts=%s lane=%s shoulder=%s sidewalk=%s terrain=%s wall=%s"
			% [verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), terrain_indices.size(), wall_indices.size()]
		)
		_append_terrain_with_mode(verts, normals, uvs, terrain_indices, path_rows, lane_indices, shoulder_indices, sidewalk_indices)
		_append_outer_walls_from_path_rows(verts, normals, uvs, wall_indices, path_rows)
		_assign_mesh(_build_mesh(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, terrain_indices, wall_indices))
		_last_signature = _build_signature()
		return

	var clusters := _cluster_sockets(sockets, minimum_connections, path_weld_snap, 1.0)
	if clusters.is_empty():
		clusters = _cluster_sockets(sockets, max(2, minimum_connections), path_weld_snap, 2.5)
	if clusters.is_empty():
		push_warning(
			"SplineRoadWelded: no weld clusters found; generating roads without intersections."
		)
		_debug_log(
			"assign mesh (no clusters): verts=%s lane=%s shoulder=%s sidewalk=%s terrain=%s wall=%s"
			% [verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), terrain_indices.size(), wall_indices.size()]
		)
		_append_terrain_with_mode(verts, normals, uvs, terrain_indices, path_rows, lane_indices, shoulder_indices, sidewalk_indices)
		_append_outer_walls_from_path_rows(verts, normals, uvs, wall_indices, path_rows)
		_assign_mesh(_build_mesh(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, terrain_indices, wall_indices))
		_last_signature = _build_signature()
		return

	for cluster in clusters:
		if cluster.size() < 2:
			continue

		if _cluster_has_midpath_socket(sockets, cluster):
			_weld_cluster_with_midpath_pairs(
				verts,
				normals,
				uvs,
				lane_indices,
				shoulder_indices,
				sidewalk_indices,
				sockets,
				cluster,
				path_rows,
				stripped_side_indices,
				path_weld_snap,
				path_weld_strip_enabled,
				path_weld_strip_length,
				paths_with_mid_intersections
			)
			continue

		if cluster.size() == 2:
			_weld_two_socket_cluster(
				verts,
				normals,
				uvs,
				lane_indices,
				shoulder_indices,
				sidewalk_indices,
				sockets,
				cluster,
				path_rows,
				stripped_side_indices,
				path_weld_snap,
				path_weld_strip_enabled,
				path_weld_strip_length,
				paths_with_mid_intersections
			)
			continue

		var center := Vector3.ZERO
		for s_idx in cluster:
			center += sockets[s_idx]["position"]
		center /= float(cluster.size())

		var shoulders: Array[Dictionary] = []
		for s_idx in cluster:
			var s := sockets[s_idx]
			var s_path_id := int(s.get("path_id", -1))
			if strip_shoulder_sidewalk_at_intersections:
				if _is_path_strip_enabled(s_path_id, path_weld_strip_enabled):
					var strip_len := _resolve_path_strip_length(s_path_id, path_weld_snap, path_weld_strip_length)
					var strip_snap := _resolve_path_snap_for_id(s_path_id, path_weld_snap)
					var strip_focus := _find_strip_focus_for_socket(sockets, cluster, int(s_idx))
					if bool(strip_focus.get("ok", false)):
						var focus_pos: Vector3 = strip_focus.get("position", s.get("position", Vector3.ZERO))
						var focus_path_id := int(strip_focus.get("path_id", -1))
						_strip_endpoint_rows_near_socket(
							verts,
							normals,
							uvs,
							path_rows,
							s,
							strip_len,
							strip_snap,
							stripped_side_indices,
							focus_pos,
							focus_path_id,
							true
						)

			var row_a: int = s["row_a"]
			var row_b: int = s["row_b"]
			var socket_width := float(s["width"])
			if strip_shoulder_sidewalk_at_intersections:
				socket_width = max(0.1, verts[row_a].distance_to(verts[row_b]))
			var dir: Vector3 = s["position"] - center
			dir.y = 0.0
			if dir.length() < 0.001:
				dir = s["out_dir"]
				dir.y = 0.0
			if dir.length() < 0.001:
				continue
			dir = dir.normalized()

			var local_snap: float = float(s.get("weld_snap_distance", endpoint_snap_distance))
			var arm_distance: float = max(socket_width * 0.75, local_snap)
			var arm_center := center + dir * arm_distance
			var right := Vector3.UP.cross(dir).normalized()
			if right.length() < 0.001:
				right = Vector3.RIGHT

			var half_w := socket_width * 0.5
			var s0 := arm_center - right * half_w
			var s1 := arm_center + right * half_w
			s0.y = center.y
			s1.y = center.y

			var current_a: Vector3 = verts[row_a]
			var current_b: Vector3 = verts[row_b]
			var keep_cost := current_a.distance_to(s0) + current_b.distance_to(s1)
			var swap_cost := current_a.distance_to(s1) + current_b.distance_to(s0)
			if swap_cost < keep_cost:
				var tmp := s0
				s0 = s1
				s1 = tmp

			_apply_row_edge_strip_transform(
				verts,
				normals,
				uvs,
				s.get("row_edges", []),
				row_a,
				row_b,
				s0,
				s1
			)

			shoulders.push_back({"index": row_a, "position": s0, "angle": atan2(s0.z - center.z, s0.x - center.x)})
			shoulders.push_back({"index": row_b, "position": s1, "angle": atan2(s1.z - center.z, s1.x - center.x)})

		if shoulders.size() < 3:
			continue

		shoulders.sort_custom(func(a, b): return a["angle"] < b["angle"])

		var ring_indices: Array[int] = []
		var ring_positions: Array[Vector3] = []
		for sh in shoulders:
			var idx: int = sh["index"]
			var p: Vector3 = sh["position"]
			if ring_indices.is_empty():
				ring_indices.push_back(idx)
				ring_positions.push_back(p)
				continue
			if ring_indices[ring_indices.size() - 1] == idx:
				continue
			if ring_positions[ring_positions.size() - 1].distance_to(p) <= 0.02:
				continue
			ring_indices.push_back(idx)
			ring_positions.push_back(p)

		if ring_indices.size() >= 2 and ring_positions[0].distance_to(ring_positions[ring_positions.size() - 1]) <= 0.02:
			ring_indices.remove_at(ring_indices.size() - 1)
			ring_positions.remove_at(ring_positions.size() - 1)

		if ring_indices.size() < 3:
			continue

		var center_idx := verts.size()
		verts.push_back(center)
		normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(0.5, 0.5))

		for i in range(ring_indices.size()):
			var i1: int = ring_indices[i]
			var i2: int = ring_indices[(i + 1) % ring_indices.size()]
			if invert_faces:
				_append_triangle_to_outer_surface(lane_indices, shoulder_indices, sidewalk_indices, center_idx, i2, i1)
			else:
				_append_triangle_to_outer_surface(lane_indices, shoulder_indices, sidewalk_indices, center_idx, i1, i2)

	if strip_shoulder_sidewalk_at_intersections and not stripped_side_indices.is_empty():
		shoulder_indices = _move_blocked_triangles_to_lane(shoulder_indices, lane_indices, stripped_side_indices)
		sidewalk_indices = _move_blocked_triangles_to_lane(sidewalk_indices, lane_indices, stripped_side_indices)

	if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
		_append_lane_fallback_from_path_rows(lane_indices, path_rows)
	if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
		_debug_log("no indices after weld branch fallback, clearing mesh node.")
		_clear_mesh_node()
		return

	_debug_log(
		"assign mesh (welded): verts=%s lane=%s shoulder=%s sidewalk=%s terrain=%s wall=%s"
		% [verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), terrain_indices.size(), wall_indices.size()]
	)
	_append_terrain_with_mode(
		verts,
		normals,
		uvs,
		terrain_indices,
		path_rows,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		stripped_side_indices
	)
	_append_outer_walls_from_path_rows(verts, normals, uvs, wall_indices, path_rows)
	_assign_mesh(_build_mesh(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, terrain_indices, wall_indices))
	_last_signature = _build_signature()


func _cluster_has_midpath_socket(sockets: Array[Dictionary], cluster: Array) -> bool:
	for idx in cluster:
		if not bool(sockets[idx].get("is_endpoint", true)):
			return true
	return false


func _weld_cluster_with_midpath_pairs(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary],
	cluster: Array,
	path_rows: Array,
	stripped_side_indices: Dictionary,
	path_weld_snap: Array,
	path_weld_strip_enabled: Array,
	path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary
) -> void:
	var endpoint_indices: Array = []
	var mid_indices: Array = []
	for idx in cluster:
		if bool(sockets[idx].get("is_endpoint", true)):
			endpoint_indices.push_back(idx)
		else:
			mid_indices.push_back(idx)

	if endpoint_indices.is_empty() or mid_indices.is_empty():
		return

	for e_idx in endpoint_indices:
		var best_mid := -1
		var best_dist := INF
		var e_path: int = sockets[e_idx]["path_id"]
		var e_pos: Vector3 = sockets[e_idx]["position"]
		for m_idx in mid_indices:
			var m_path: int = sockets[m_idx]["path_id"]
			if m_path == e_path:
				continue
			var d := e_pos.distance_to(sockets[m_idx]["position"])
			var pair_snap := _resolve_socket_pair_snap_distance(sockets[e_idx], sockets[m_idx], path_weld_snap)
			if d <= pair_snap and d < best_dist:
				best_dist = d
				best_mid = m_idx
		if best_mid >= 0:
			_weld_two_socket_cluster(
				verts,
				normals,
				uvs,
				lane_indices,
				shoulder_indices,
				sidewalk_indices,
				sockets,
				[e_idx, best_mid],
				path_rows,
				stripped_side_indices,
				path_weld_snap,
				path_weld_strip_enabled,
				path_weld_strip_length,
				paths_with_mid_intersections
			)


func _weld_two_socket_cluster(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary],
	cluster: Array,
	path_rows: Array,
	stripped_side_indices: Dictionary,
	path_weld_snap: Array,
	path_weld_strip_enabled: Array,
	path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary
) -> void:
	var s0: Dictionary = sockets[cluster[0]]
	var s1: Dictionary = sockets[cluster[1]]

	# Prefer welding endpoint into mid-path row when available.
	var source := s0
	var target := s1
	if bool(s1.get("is_endpoint", false)) and not bool(s0.get("is_endpoint", false)):
		source = s1
		target = s0
	var source_is_endpoint: bool = bool(source.get("is_endpoint", true))
	var target_is_midpath: bool = not bool(target.get("is_endpoint", true))
	var source_path_id := int(source.get("path_id", -1))
	var target_path_id := int(target.get("path_id", -1))
	var source_edges: Array = source.get("row_edges", [])
	var target_all_edges: Array = target.get("row_edges", [])
	if strip_shoulder_sidewalk_at_intersections:
		if _is_path_strip_enabled(source_path_id, path_weld_strip_enabled):
			var source_strip_length := _resolve_path_strip_length(source_path_id, path_weld_snap, path_weld_strip_length)
			var source_snap := _resolve_path_snap_for_id(source_path_id, path_weld_snap)
			var target_focus_pos: Vector3 = target.get("position", source.get("position", Vector3.ZERO))
			_strip_endpoint_rows_near_socket(
				verts,
				normals,
				uvs,
				path_rows,
				source,
				source_strip_length,
				source_snap,
				stripped_side_indices,
				target_focus_pos,
				target_path_id,
				true
			)
		if _is_path_strip_enabled(target_path_id, path_weld_strip_enabled):
			var target_strip_length := _resolve_path_strip_length(target_path_id, path_weld_snap, path_weld_strip_length)
			var target_snap := _resolve_path_snap_for_id(target_path_id, path_weld_snap)
			var source_focus_pos: Vector3 = source.get("position", target.get("position", Vector3.ZERO))
			_strip_endpoint_rows_near_socket(
				verts,
				normals,
				uvs,
				path_rows,
				target,
				target_strip_length,
				target_snap,
				stripped_side_indices,
				source_focus_pos,
				source_path_id,
				true
			)

	var sa: int = source["row_a"]
	var sb: int = source["row_b"]
	var ta: int = target["row_a"]
	var tb: int = target["row_b"]

	var va := verts[sa]
	var vb := verts[sb]
	var wa := verts[ta]
	var wb := verts[tb]

	var keep_cost := va.distance_to(wa) + vb.distance_to(wb)
	var swap_cost := va.distance_to(wb) + vb.distance_to(wa)
	if swap_cost < keep_cost:
		var tmp := ta
		ta = tb
		tb = tmp
		var tmp_v := wa
		wa = wb
		wb = tmp_v

	if source_is_endpoint and target_is_midpath:
		# Edge weld to the side indicated by branch outward direction.
		var target_a := verts[ta]
		var target_b := verts[tb]
		var target_center := (target_a + target_b) * 0.5

		var side_a := (target_a - target_center).normalized()
		var side_b := (target_b - target_center).normalized()
		var source_dir: Vector3 = source["out_dir"]
		source_dir.y = 0.0
		if source_dir.length() < 0.001:
			source_dir = (source["position"] - target_center).normalized()
		if source_dir.length() < 0.001:
			source_dir = side_a

		var score_a := side_a.dot(source_dir)
		var score_b := side_b.dot(source_dir)

		var contact_idx := ta
		var contact_pos := target_a
		var outward := side_a
		if score_b > score_a:
			contact_idx = tb
			contact_pos = target_b
			outward = side_b

		if outward.length() < 0.001:
			outward = (contact_pos - target_center).normalized()
		if outward.length() < 0.001:
			outward = Vector3.RIGHT

		# True 2-vertex weld: scan the whole selected side and pick the best adjacent pair.
		if target_path_id >= 0 and target_path_id < path_rows.size():
			var rows: Array[Dictionary] = path_rows[target_path_id]
			if rows.size() >= 2:
				var side_key := "row_a"
				if int(target["row_b"]) == contact_idx:
					side_key = "row_b"

				var best_a := -1
				var best_b := -1
				var best_cost := INF

				for row_i in range(rows.size() - 1):
					var row0: Dictionary = rows[row_i]
					var row1: Dictionary = rows[row_i + 1]
					var c0: int = int(row0[side_key])
					var c1: int = int(row1[side_key])
					if c0 == c1:
						continue

					var keep_map_cost := verts[sa].distance_to(verts[c0]) + verts[sb].distance_to(verts[c1])
					if keep_map_cost < best_cost:
						best_cost = keep_map_cost
						best_a = c0
						best_b = c1

					var swap_map_cost := verts[sa].distance_to(verts[c1]) + verts[sb].distance_to(verts[c0])
					if swap_map_cost < best_cost:
						best_cost = swap_map_cost
						best_a = c1
						best_b = c0

				if best_a >= 0 and best_b >= 0:
					_apply_row_edge_strip_transform(
						verts,
						normals,
						uvs,
						source_edges,
						sa,
						sb,
						verts[best_a],
						verts[best_b],
						best_a,
						best_b
					)

					_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sa, best_a)
					_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sb, best_b)
					return

		var source_width = max(0.1, va.distance_to(vb))
		var outer_pos = contact_pos + outward * source_width

		var sa_contact := sa
		var sb_outer := sb
		if verts[sb].distance_to(contact_pos) < verts[sa].distance_to(contact_pos):
			sa_contact = sb
			sb_outer = sa

		_apply_row_edge_strip_transform(
			verts,
			normals,
			uvs,
			source_edges,
			sa_contact,
			sb_outer,
			contact_pos,
			outer_pos,
			contact_idx,
			-1
		)

		# Collapse only contact edge index to target side index.
		_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sa_contact, contact_idx)
	else:
		# Endpoint-endpoint case: symmetric merge.
		var target_edges: Array = target_all_edges
		if source_edges.size() == target_edges.size() and source_edges.size() >= 2:
			var reverse_target_order := false
			var keep_cost_full := 0.0
			var reverse_cost_full := 0.0
			var edge_count := source_edges.size()
			for edge_i in range(edge_count):
				var s_idx := int(source_edges[edge_i])
				var t_keep_idx := int(target_edges[edge_i])
				var t_reverse_idx := int(target_edges[edge_count - 1 - edge_i])
				keep_cost_full += verts[s_idx].distance_to(verts[t_keep_idx])
				reverse_cost_full += verts[s_idx].distance_to(verts[t_reverse_idx])
			if reverse_cost_full < keep_cost_full:
				reverse_target_order = true
			elif is_equal_approx(reverse_cost_full, keep_cost_full):
				var source_span := verts[int(source_edges[source_edges.size() - 1])] - verts[int(source_edges[0])]
				var target_span := verts[int(target_edges[target_edges.size() - 1])] - verts[int(target_edges[0])]
				if source_span.dot(target_span) < 0.0:
					reverse_target_order = true

			for edge_i in range(source_edges.size()):
				var s_idx := int(source_edges[edge_i])
				var target_idx := edge_i
				if reverse_target_order:
					target_idx = source_edges.size() - 1 - edge_i
				var t_idx := int(target_edges[target_idx])
				var merged := (verts[s_idx] + verts[t_idx]) * 0.5
				verts[t_idx] = merged
				verts[s_idx] = merged
				normals[t_idx] = Vector3.UP
				normals[s_idx] = Vector3.UP
				uvs[s_idx] = uvs[t_idx]
				_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, s_idx, t_idx)
		else:
			var merged_a := (va + wa) * 0.5
			var merged_b := (vb + wb) * 0.5
			verts[ta] = merged_a
			verts[tb] = merged_b
			normals[ta] = Vector3.UP
			normals[tb] = Vector3.UP
			_apply_row_edge_strip_transform(
				verts,
				normals,
				uvs,
				source_edges,
				sa,
				sb,
				merged_a,
				merged_b,
				ta,
				tb
			)
			# Real weld: remap source row indices to target row indices in the mesh.
			_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sa, ta)
			_remap_index_in_all_surfaces(lane_indices, shoulder_indices, sidewalk_indices, sb, tb)


func _collapse_row_side_edges_to_lane(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	row_edges_raw: Array,
	strip_side: int = STRIP_SIDE_BOTH
) -> void:
	if row_edges_raw.size() < 6:
		return
	var left_lane_idx := int(row_edges_raw[2])
	var right_lane_idx := int(row_edges_raw[3])
	var left_lane := verts[left_lane_idx]
	var right_lane := verts[right_lane_idx]
	var left_uv := uvs[left_lane_idx]
	var right_uv := uvs[right_lane_idx]

	if strip_side != STRIP_SIDE_RIGHT:
		for idx_raw in [row_edges_raw[0], row_edges_raw[1]]:
			var idx := int(idx_raw)
			verts[idx] = left_lane
			normals[idx] = Vector3.UP
			uvs[idx] = left_uv

	if strip_side != STRIP_SIDE_LEFT:
		for idx_raw in [row_edges_raw[4], row_edges_raw[5]]:
			var idx := int(idx_raw)
			verts[idx] = right_lane
			normals[idx] = Vector3.UP
			uvs[idx] = right_uv


func _strip_endpoint_rows_near_socket(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	path_rows: Array,
	socket: Dictionary,
	strip_length: float,
	strip_snap_distance: float,
	marked: Dictionary,
	focus_position: Vector3 = Vector3.ZERO,
	focus_path_id: int = -1,
	use_focus_side: bool = false
) -> void:
	if strip_length <= 0.0001:
		return
	var path_id := int(socket.get("path_id", -1))
	if path_id < 0 or path_id >= path_rows.size():
		return
	var rows_raw: Array = path_rows[path_id]
	if rows_raw.is_empty():
		return
	var row_idx := int(socket.get("row_idx", -1))
	if row_idx < 0 or row_idx >= rows_raw.size():
		return

	var anchor_row: Dictionary = rows_raw[row_idx]
	var anchor_pos: Vector3 = anchor_row.get("position", Vector3.ZERO)
	var anchor_edges: Array = anchor_row.get("row_edges", [])
	var is_endpoint := bool(socket.get("is_endpoint", true))
	var strip_side := STRIP_SIDE_BOTH
	if use_focus_side:
		if focus_path_id >= 0 and focus_path_id == path_id:
			return
		strip_side = _resolve_strip_side_for_row(verts, anchor_edges, focus_position)
		# Focused strip mode: remove the full local segment (anchor + one adjacent row).
		_collapse_row_side_edges_to_lane(verts, normals, uvs, anchor_edges, strip_side)
		_mark_row_side_vertices_for_strip(marked, anchor_edges, strip_side)
		var neighbor_row_idx := _pick_adjacent_strip_row(rows_raw, row_idx, focus_position)
		if neighbor_row_idx >= 0 and neighbor_row_idx < rows_raw.size() and neighbor_row_idx != row_idx:
			var neighbor_row: Dictionary = rows_raw[neighbor_row_idx]
			var neighbor_edges: Array = neighbor_row.get("row_edges", [])
			_collapse_row_side_edges_to_lane(verts, normals, uvs, neighbor_edges, strip_side)
			_mark_row_side_vertices_for_strip(marked, neighbor_edges, strip_side)
		return

	if is_endpoint:
		var step := 1
		if row_idx >= rows_raw.size() - 1:
			step = -1
		elif row_idx > 0 and row_idx >= rows_raw.size() / 2:
			step = -1
		var i := row_idx
		while i >= 0 and i < rows_raw.size():
			var row: Dictionary = rows_raw[i]
			var row_pos: Vector3 = row.get("position", anchor_pos)
			if row_pos.distance_to(anchor_pos) > strip_length:
				break
			var row_edges: Array = row.get("row_edges", [])
			_collapse_row_side_edges_to_lane(verts, normals, uvs, row_edges, strip_side)
			_mark_row_side_vertices_for_strip(marked, row_edges, strip_side)
			i += step
		return

	# Mid-path sockets: strip both directions around the intersection.
	var first_row: Dictionary = rows_raw[0]
	var last_row: Dictionary = rows_raw[rows_raw.size() - 1]
	var first_pos: Vector3 = first_row.get("position", anchor_pos)
	var last_pos: Vector3 = last_row.get("position", anchor_pos)
	var path_span := first_pos.distance_to(last_pos)
	var end_guard_length: float = max(sample_step * 2.0, maxf(0.1, strip_snap_distance) * 0.75)
	if path_span > 0.0001:
		end_guard_length = min(end_guard_length, path_span * 0.45)

	var forward_i := row_idx
	while forward_i < rows_raw.size():
		if forward_i == rows_raw.size() - 1:
			break
		var forward_row: Dictionary = rows_raw[forward_i]
		var forward_pos: Vector3 = forward_row.get("position", anchor_pos)
		if forward_pos.distance_to(last_pos) <= end_guard_length:
			break
		if forward_pos.distance_to(anchor_pos) > strip_length:
			break
		var forward_edges: Array = forward_row.get("row_edges", [])
		_collapse_row_side_edges_to_lane(verts, normals, uvs, forward_edges, strip_side)
		_mark_row_side_vertices_for_strip(marked, forward_edges, strip_side)
		forward_i += 1

	var backward_i := row_idx - 1
	while backward_i >= 0:
		if backward_i == 0:
			break
		var backward_row: Dictionary = rows_raw[backward_i]
		var backward_pos: Vector3 = backward_row.get("position", anchor_pos)
		if backward_pos.distance_to(first_pos) <= end_guard_length:
			break
		if backward_pos.distance_to(anchor_pos) > strip_length:
			break
		var backward_edges: Array = backward_row.get("row_edges", [])
		_collapse_row_side_edges_to_lane(verts, normals, uvs, backward_edges, strip_side)
		_mark_row_side_vertices_for_strip(marked, backward_edges, strip_side)
		backward_i -= 1


func _resolve_strip_side_for_row(
	verts: PackedVector3Array,
	row_edges_raw: Array,
	focus_position: Vector3
) -> int:
	if row_edges_raw.size() < 6:
		return STRIP_SIDE_BOTH
	var left_a := int(row_edges_raw[0])
	var left_b := int(row_edges_raw[1])
	var right_a := int(row_edges_raw[4])
	var right_b := int(row_edges_raw[5])
	if (
		left_a < 0
		or left_a >= verts.size()
		or left_b < 0
		or left_b >= verts.size()
		or right_a < 0
		or right_a >= verts.size()
		or right_b < 0
		or right_b >= verts.size()
	):
		return STRIP_SIDE_BOTH

	var left_mid := (verts[left_a] + verts[left_b]) * 0.5
	var right_mid := (verts[right_a] + verts[right_b]) * 0.5
	var focus_xz := Vector3(focus_position.x, 0.0, focus_position.z)
	var left_xz := Vector3(left_mid.x, 0.0, left_mid.z)
	var right_xz := Vector3(right_mid.x, 0.0, right_mid.z)
	var left_dist := left_xz.distance_to(focus_xz)
	var right_dist := right_xz.distance_to(focus_xz)
	if absf(left_dist - right_dist) <= 0.001:
		return STRIP_SIDE_BOTH
	if left_dist < right_dist:
		return STRIP_SIDE_LEFT
	return STRIP_SIDE_RIGHT


func _pick_adjacent_strip_row(rows_raw: Array, row_idx: int, focus_position: Vector3) -> int:
	if rows_raw.size() < 2:
		return -1
	if row_idx <= 0:
		return 1
	if row_idx >= rows_raw.size() - 1:
		return rows_raw.size() - 2

	var focus_xz := Vector3(focus_position.x, 0.0, focus_position.z)
	var prev_row: Dictionary = rows_raw[row_idx - 1]
	var next_row: Dictionary = rows_raw[row_idx + 1]
	var prev_pos: Vector3 = prev_row.get("position", Vector3.ZERO)
	var next_pos: Vector3 = next_row.get("position", Vector3.ZERO)
	var prev_xz := Vector3(prev_pos.x, 0.0, prev_pos.z)
	var next_xz := Vector3(next_pos.x, 0.0, next_pos.z)
	if prev_xz.distance_to(focus_xz) <= next_xz.distance_to(focus_xz):
		return row_idx - 1
	return row_idx + 1


func _mark_row_side_vertices_for_strip(
	marked: Dictionary,
	row_edges_raw: Array,
	strip_side: int = STRIP_SIDE_BOTH
) -> void:
	if row_edges_raw.size() < 6:
		return
	if strip_side != STRIP_SIDE_RIGHT:
		marked[int(row_edges_raw[0])] = true
		marked[int(row_edges_raw[1])] = true
	if strip_side != STRIP_SIDE_LEFT:
		marked[int(row_edges_raw[4])] = true
		marked[int(row_edges_raw[5])] = true


func _find_strip_focus_for_socket(sockets: Array[Dictionary], cluster: Array, socket_idx: int) -> Dictionary:
	var out := {"ok": false}
	if socket_idx < 0 or socket_idx >= sockets.size():
		return out
	var socket: Dictionary = sockets[socket_idx]
	var socket_path := int(socket.get("path_id", -1))
	var socket_pos: Vector3 = socket.get("position", Vector3.ZERO)
	var best_dist := INF
	var best_path := -1
	var best_pos := socket_pos
	for other_idx_raw in cluster:
		var other_idx := int(other_idx_raw)
		if other_idx == socket_idx:
			continue
		if other_idx < 0 or other_idx >= sockets.size():
			continue
		var other: Dictionary = sockets[other_idx]
		var other_path := int(other.get("path_id", -1))
		if other_path == socket_path:
			continue
		var other_pos: Vector3 = other.get("position", socket_pos)
		var d := socket_pos.distance_to(other_pos)
		if d < best_dist:
			best_dist = d
			best_path = other_path
			best_pos = other_pos
	if best_path < 0:
		return out
	out["ok"] = true
	out["path_id"] = best_path
	out["position"] = best_pos
	return out


func _move_blocked_triangles_to_lane(
	indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	blocked: Dictionary
) -> PackedInt32Array:
	if indices.is_empty() or blocked.is_empty():
		return indices
	var out := PackedInt32Array()
	var i := 0
	while i + 2 < indices.size():
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var blocked_count := 0
		if blocked.has(a):
			blocked_count += 1
		if blocked.has(b):
			blocked_count += 1
		if blocked.has(c):
			blocked_count += 1
		if blocked_count >= 2:
			if a != b and b != c and c != a:
				lane_indices.push_back(a)
				lane_indices.push_back(b)
				lane_indices.push_back(c)
		else:
			out.push_back(a)
			out.push_back(b)
			out.push_back(c)
		i += 3
	return out


func _apply_row_edge_strip_transform(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	row_edges_raw: Array,
	end_a_idx: int,
	end_b_idx: int,
	end_a_pos: Vector3,
	end_b_pos: Vector3,
	uv_a_idx: int = -1,
	uv_b_idx: int = -1
) -> void:
	var row_edges: Array = []
	for idx in row_edges_raw:
		row_edges.push_back(int(idx))
	if row_edges.size() < 2:
		row_edges = [end_a_idx, end_b_idx]

	var pos_a := row_edges.find(end_a_idx)
	var pos_b := row_edges.find(end_b_idx)
	if pos_a < 0 or pos_b < 0:
		row_edges = [end_a_idx, end_b_idx]
	else:
		if pos_a > pos_b:
			row_edges.reverse()

	var uv_a := uvs[end_a_idx]
	var uv_b := uvs[end_b_idx]
	if uv_a_idx >= 0 and uv_a_idx < uvs.size():
		uv_a = uvs[uv_a_idx]
	if uv_b_idx >= 0 and uv_b_idx < uvs.size():
		uv_b = uvs[uv_b_idx]

	var old_positions: Array[Vector3] = []
	old_positions.resize(row_edges.size())
	for i in range(row_edges.size()):
		old_positions[i] = verts[int(row_edges[i])]

	var cumulative := PackedFloat32Array()
	cumulative.resize(row_edges.size())
	cumulative[0] = 0.0
	var total_len := 0.0
	for i in range(1, row_edges.size()):
		total_len += old_positions[i - 1].distance_to(old_positions[i])
		cumulative[i] = total_len

	var denom:int = max(1, row_edges.size() - 1)
	for i in range(row_edges.size()):
		var row_idx := int(row_edges[i])
		var t := float(i) / float(denom)
		if total_len > 0.0001:
			t = cumulative[i] / total_len
		verts[row_idx] = end_a_pos.lerp(end_b_pos, t)
		normals[row_idx] = Vector3.UP
		uvs[row_idx] = uv_a.lerp(uv_b, t)


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


func _append_lane_fallback_from_path_rows(lane_indices: PackedInt32Array, path_rows: Array) -> void:
	for rows_raw in path_rows:
		var rows: Array[Dictionary] = rows_raw
		if rows.size() < 2:
			continue
		for i in range(rows.size() - 1):
			var row0: Dictionary = rows[i]
			var row1: Dictionary = rows[i + 1]
			var e0: Array = row0.get("row_edges", [])
			var e1: Array = row1.get("row_edges", [])
			if e0.size() < 4 or e1.size() < 4:
				continue
			_append_quad_indices(
				lane_indices,
				int(e0[2]),
				int(e0[3]),
				int(e1[2]),
				int(e1[3])
			)


func _append_triangle_to_outer_surface(
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	a: int,
	b: int,
	c: int
) -> void:
	if not sidewalk_indices.is_empty():
		sidewalk_indices.push_back(a)
		sidewalk_indices.push_back(b)
		sidewalk_indices.push_back(c)
		return
	if not shoulder_indices.is_empty():
		shoulder_indices.push_back(a)
		shoulder_indices.push_back(b)
		shoulder_indices.push_back(c)
		return
	lane_indices.push_back(a)
	lane_indices.push_back(b)
	lane_indices.push_back(c)


func _remap_index_in_all_surfaces(
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	from_idx: int,
	to_idx: int
) -> void:
	_remap_index_in_surface(lane_indices, from_idx, to_idx)
	_remap_index_in_surface(shoulder_indices, from_idx, to_idx)
	_remap_index_in_surface(sidewalk_indices, from_idx, to_idx)


func _remap_index_in_surface(indices: PackedInt32Array, from_idx: int, to_idx: int) -> void:
	for i in range(indices.size()):
		if indices[i] == from_idx:
			indices[i] = to_idx


func _append_terrain_with_mode(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {}
) -> void:
	if terrain_rect_fill_enabled:
		var rect_vert_start := verts.size()
		var rect_normal_start := normals.size()
		var rect_uv_start := uvs.size()
		var rect_terrain_start := terrain_indices.size()
		_append_terrain_from_rect_fill(
			verts,
			normals,
			uvs,
			terrain_indices,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			path_rows
		)
		_debug_log(
			"rect fill terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - rect_terrain_start) / 3)]
		)
		if terrain_indices.size() > rect_terrain_start:
			return
		verts.resize(rect_vert_start)
		normals.resize(rect_normal_start)
		uvs.resize(rect_uv_start)
		_debug_log("rect fill produced 0 terrain tris, fallback next mode")

	if terrain_boolean_fill_enabled:
		var vert_start := verts.size()
		var normal_start := normals.size()
		var uv_start := uvs.size()
		var terrain_start := terrain_indices.size()
		_append_terrain_from_boolean_fill(
			verts,
			normals,
			uvs,
			terrain_indices,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			path_rows
		)
		_debug_log(
			"boolean fill terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - terrain_start) / 3)]
		)
		if terrain_indices.size() > terrain_start:
			return
		# Boolean fallback: if subtraction produced no terrain, restore buffers and
		# build terrain with the stable row-based method.
		verts.resize(vert_start)
		normals.resize(normal_start)
		uvs.resize(uv_start)
		_debug_log("boolean fill produced 0 terrain tris, fallback to path-row terrain")
		var fb_vert_start := verts.size()
		var fb_normal_start := normals.size()
		var fb_uv_start := uvs.size()
		_append_terrain_from_path_rows(
			verts,
			normals,
			uvs,
			terrain_indices,
			path_rows,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			blocked_side_vertices
		)
		_debug_log(
			"path-row fallback terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - terrain_start) / 3)]
		)
		if terrain_indices.size() > terrain_start:
			return
		verts.resize(fb_vert_start)
		normals.resize(fb_normal_start)
		uvs.resize(fb_uv_start)
		var emergency_width := clampf(maxf(2.5, road_width * 0.9), 2.0, 14.0)
		var emergency_rows := _path_rows_with_emergency_terrain_widths(path_rows, emergency_width)
		_debug_log("path-row fallback still 0, retry with emergency width=%s and unblocked sides" % [emergency_width])
		var saved_terrain_subdivisions := terrain_subdivisions
		var emergency_subdivisions := clampi(saved_terrain_subdivisions, 1, 8)
		if emergency_subdivisions != saved_terrain_subdivisions:
			terrain_subdivisions = emergency_subdivisions
			_debug_log(
				"emergency fallback uses reduced terrain_subdivisions=%s (from %s)"
				% [emergency_subdivisions, saved_terrain_subdivisions]
			)
		_append_terrain_from_path_rows(
			verts,
			normals,
			uvs,
			terrain_indices,
			emergency_rows,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			{}
		)
		terrain_subdivisions = saved_terrain_subdivisions
		_debug_log(
			"emergency fallback terrain tris=%s"
			% [maxi(0, (terrain_indices.size() - terrain_start) / 3)]
		)
		return
	_append_terrain_from_path_rows(
		verts,
		normals,
		uvs,
		terrain_indices,
		path_rows,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		blocked_side_vertices
	)


func _path_rows_with_emergency_terrain_widths(path_rows: Array, width: float) -> Array:
	var out: Array = []
	var safe_width := maxf(0.0, width)
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		var rows_copy: Array = []
		for row_raw in rows:
			var row: Dictionary = row_raw
			var row_copy := row.duplicate(true)
			var left_w := maxf(0.0, float(row_copy.get("terrain_left_width", 0.0)))
			var right_w := maxf(0.0, float(row_copy.get("terrain_right_width", 0.0)))
			if left_w <= 0.0001:
				row_copy["terrain_left_width"] = safe_width
			if right_w <= 0.0001:
				row_copy["terrain_right_width"] = safe_width
			rows_copy.push_back(row_copy)
		out.push_back(rows_copy)
	return out


func _append_terrain_from_rect_fill(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array
) -> void:
	var boundary_data := _extract_road_boundary_loops_xz(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	var mesh_road_loops_all: Array = boundary_data.get("loops", [])
	var boundary_points: Array = boundary_data.get("points", [])
	if boundary_points.is_empty():
		return

	var lane_only_clip := terrain_rect_fill_clip_width_mode == TERRAIN_RECT_CLIP_LANE_ONLY
	var road_loops := _build_path_row_boundary_polygons_xz_mode(verts, path_rows, lane_only_clip)
	var boundary_source := "path-rows"
	if road_loops.is_empty():
		if lane_only_clip:
			var lane_only_boundary := _extract_road_boundary_loops_xz(
				verts,
				lane_indices,
				PackedInt32Array(),
				PackedInt32Array()
			)
			road_loops = lane_only_boundary.get("loops", [])
			boundary_source = "lane-surfaces"
		else:
			road_loops = mesh_road_loops_all
			boundary_source = "all-surfaces"
	if road_loops.is_empty():
		return

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return

	var padding := maxf(0.0, terrain_rect_fill_padding)
	var outer := PackedVector2Array([
		Vector2(min_x - padding, min_z - padding),
		Vector2(max_x + padding, min_z - padding),
		Vector2(max_x + padding, max_z + padding),
		Vector2(min_x - padding, max_z + padding),
	])
	if Geometry2D.is_polygon_clockwise(outer):
		outer.reverse()

	var road_margin := maxf(0.0, terrain_rect_fill_road_margin)
	var road_parts: Array = []
	for loop_raw in road_loops:
		var loop: PackedVector2Array = _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() < 3:
			continue
		if road_margin > 0.0001:
			var offset_parts: Array = Geometry2D.offset_polygon(loop, road_margin)
			if not offset_parts.is_empty():
				loop = _pick_largest_polygon_part_xz(offset_parts)
				loop = _compact_polygon2d_xz(loop, 0.001)
		if loop.size() < 3:
			continue
		road_parts.push_back(loop)
	if road_parts.is_empty():
		return

	var fill_parts: Array = [outer]
	for part_raw in road_parts:
		var part: PackedVector2Array = part_raw
		if part.size() < 3:
			continue
		fill_parts = _clip_fill_parts_by_polygon(fill_parts, part)
		if fill_parts.is_empty():
			break
	if fill_parts.is_empty():
		return

	var snap_eps := maxf(0.0001, terrain_rect_fill_height_match_epsilon)
	var max_dist := maxf(0.0, terrain_rect_fill_height_match_max_distance)
	var base_y := terrain_rect_fill_base_height + y_offset
	var boundary_height_map: Dictionary = {}
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var key := Vector2i(int(round(p.x / snap_eps)), int(round(p.z / snap_eps)))
		var sum_and_count: Array = boundary_height_map.get(key, [0.0, 0])
		sum_and_count[0] = float(sum_and_count[0]) + p.y
		sum_and_count[1] = int(sum_and_count[1]) + 1
		boundary_height_map[key] = sum_and_count

	var max_edge_len := maxf(0.2, terrain_rect_fill_cell_size)
	var tri_limit := maxi(1000, terrain_rect_fill_max_cells)
	var tri_candidates := 0
	var tri_kept := 0
	var limit_reached := false
	for poly_raw in fill_parts:
		if limit_reached:
			break
		var poly: PackedVector2Array = _compact_polygon2d_xz(poly_raw, 0.001)
		if poly.size() < 3:
			continue
		var dense_poly := _resample_polygon_edges_for_boolean_fill(poly, max_edge_len)
		if dense_poly.size() >= 3:
			poly = dense_poly
		var tri_local: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
		if tri_local.size() < 3:
			continue

		var base_idx := verts.size()
		for p2 in poly:
			var y := _sample_rect_fill_vertex_height(
				p2,
				boundary_height_map,
				boundary_points,
				base_y,
				snap_eps,
				max_dist
			)
			var p3 := Vector3(p2.x, y, p2.y)
			verts.push_back(p3)
			normals.push_back(Vector3.UP)
			uvs.push_back(Vector2(p3.x, p3.z) * uv_length_scale)

		var tri_count := tri_local.size() - (tri_local.size() % 3)
		for i in range(0, tri_count, 3):
			tri_candidates += 1
			if tri_kept >= tri_limit:
				limit_reached = true
				break
			var local_a := int(tri_local[i])
			var local_b := int(tri_local[i + 1])
			var local_c := int(tri_local[i + 2])
			if local_a < 0 or local_b < 0 or local_c < 0:
				continue
			if local_a >= poly.size() or local_b >= poly.size() or local_c >= poly.size():
				continue
			var a := base_idx + local_a
			var b := base_idx + local_b
			var c := base_idx + local_c
			if invert_faces:
				terrain_indices.push_back(a)
				terrain_indices.push_back(b)
				terrain_indices.push_back(c)
			else:
				terrain_indices.push_back(a)
				terrain_indices.push_back(c)
				terrain_indices.push_back(b)
			tri_kept += 1

	_debug_log(
		"rect fill source=%s parts=%s area=%.2f candidates=%s kept=%s clip_mode=%s"
		% [
			boundary_source,
			fill_parts.size(),
			_polygon_parts_total_area_abs_xz(fill_parts),
			tri_candidates,
			tri_kept,
			"lane-only" if lane_only_clip else "outer"
		]
	)


func _sample_rect_fill_vertex_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	default_y: float,
	snap_eps: float,
	max_dist: float
) -> float:
	var key := Vector2i(int(round(point.x / snap_eps)), int(round(point.y / snap_eps)))
	if boundary_height_map.has(key):
		var sum_and_count: Array = boundary_height_map.get(key, [default_y, 1])
		var count := maxi(1, int(sum_and_count[1]))
		return float(sum_and_count[0]) / float(count)

	if max_dist <= 0.0001:
		return default_y

	var best_y := default_y
	var best_dist := max_dist
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var d := Vector2(p.x, p.z).distance_to(point)
		if d <= best_dist:
			best_dist = d
			best_y = p.y
	return best_y


func _append_terrain_from_boolean_fill(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array
) -> void:
	var boundary_source := "path-rows"
	var boundary_data := _extract_road_boundary_loops_xz(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	var mesh_road_loops: Array = boundary_data.get("loops", [])
	var boundary_points: Array = boundary_data.get("points", [])
	var road_loops := _build_path_row_boundary_polygons_xz(verts, path_rows)
	if road_loops.is_empty():
		road_loops = mesh_road_loops
		boundary_source = "all-surfaces"
	var overlap_shoulder_indices := shoulder_indices
	var overlap_sidewalk_indices := sidewalk_indices
	if terrain_boolean_clip_width_mode == TERRAIN_BOOLEAN_CLIP_LANE_ONLY:
		overlap_shoulder_indices = PackedInt32Array()
		overlap_sidewalk_indices = PackedInt32Array()
	var road_tris := _build_road_tri_xz_cache(
		verts,
		lane_indices,
		overlap_shoulder_indices,
		overlap_sidewalk_indices,
		[]
	)

	if road_loops.is_empty() or boundary_points.is_empty():
		return
	_debug_log(
		"boolean fill boundary source=%s loops=%s clip_mode=%s solver=%s"
		% [
			boundary_source,
			road_loops.size(),
			"lane-only" if terrain_boolean_clip_width_mode == TERRAIN_BOOLEAN_CLIP_LANE_ONLY else "outer",
			"fill" if terrain_boolean_solver_mode == TERRAIN_BOOLEAN_SOLVER_FILL else "boolean"
		]
	)

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	if min_x >= max_x or min_z >= max_z:
		return

	var padding := maxf(0.0, terrain_boolean_padding)
	var outer := PackedVector2Array([
		Vector2(min_x - padding, min_z - padding),
		Vector2(max_x + padding, min_z - padding),
		Vector2(max_x + padding, max_z + padding),
		Vector2(min_x - padding, max_z + padding),
	])
	if Geometry2D.is_polygon_clockwise(outer):
		outer.reverse()

	var road_parts: Array = []
	for loop_raw in road_loops:
		var loop: PackedVector2Array = _compact_polygon2d_xz(loop_raw, 0.001)
		if loop.size() < 3:
			continue
		road_parts.push_back(loop)

	var fill_parts: Array = [outer]
	for part_raw in road_parts:
		var part: PackedVector2Array = part_raw
		if part.size() < 3:
			continue
		fill_parts = _clip_fill_parts_by_polygon(fill_parts, part)
		if fill_parts.is_empty():
			break
	_debug_log(
		"boolean fill clipped parts=%s area=%.2f road_parts=%s"
		% [fill_parts.size(), _polygon_parts_total_area_abs_xz(fill_parts), road_parts.size()]
	)

	var snap_eps := maxf(0.0001, terrain_boolean_height_match_epsilon)
	var boundary_height_map: Dictionary = {}
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var key := Vector2i(int(round(p.x / snap_eps)), int(round(p.z / snap_eps)))
		var sum_and_count: Array = boundary_height_map.get(key, [0.0, 0])
		sum_and_count[0] = float(sum_and_count[0]) + p.y
		sum_and_count[1] = int(sum_and_count[1]) + 1
		boundary_height_map[key] = sum_and_count

	var base_y := terrain_boolean_base_height + y_offset
	var max_leaf_edge_len := maxf(1.0, road_width * 0.35)
	var split_depth_max := 7
	var tri_stats := {
		"tri_candidates": 0,
		"tri_rejected_overlap": 0,
		"tri_kept": 0,
	}
	for poly_raw in fill_parts:
		var poly: PackedVector2Array = _compact_polygon2d_xz(poly_raw, 0.001)
		if poly.size() < 3:
			continue
		var dense_poly := _resample_polygon_edges_for_boolean_fill(
			poly,
			maxf(1.0, road_width * 0.35)
		)
		if dense_poly.size() >= 3:
			poly = dense_poly
		var tri_local: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
		if tri_local.size() < 3:
			continue

		var tri_count := tri_local.size() - (tri_local.size() % 3)
		for i in range(0, tri_count, 3):
			var local_a := int(tri_local[i])
			var local_b := int(tri_local[i + 1])
			var local_c := int(tri_local[i + 2])
			if local_a < 0 or local_b < 0 or local_c < 0:
				continue
			if local_a >= poly.size() or local_b >= poly.size() or local_c >= poly.size():
				continue
			var pa2: Vector2 = poly[local_a]
			var pb2: Vector2 = poly[local_b]
			var pc2: Vector2 = poly[local_c]
			if terrain_boolean_solver_mode == TERRAIN_BOOLEAN_SOLVER_FILL:
				tri_stats["tri_candidates"] = int(tri_stats.get("tri_candidates", 0)) + 1
				var y_a := _sample_boolean_fill_vertex_height(pa2, boundary_height_map, boundary_points, base_y)
				var y_b := _sample_boolean_fill_vertex_height(pb2, boundary_height_map, boundary_points, base_y)
				var y_c := _sample_boolean_fill_vertex_height(pc2, boundary_height_map, boundary_points, base_y)
				var p_a := Vector3(pa2.x, y_a, pa2.y)
				var p_b := Vector3(pb2.x, y_b, pb2.y)
				var p_c := Vector3(pc2.x, y_c, pc2.y)
				var i_a := verts.size()
				verts.push_back(p_a)
				normals.push_back(Vector3.UP)
				uvs.push_back(Vector2(p_a.x, p_a.z) * uv_length_scale)
				var i_b := verts.size()
				verts.push_back(p_b)
				normals.push_back(Vector3.UP)
				uvs.push_back(Vector2(p_b.x, p_b.z) * uv_length_scale)
				var i_c := verts.size()
				verts.push_back(p_c)
				normals.push_back(Vector3.UP)
				uvs.push_back(Vector2(p_c.x, p_c.z) * uv_length_scale)
				tri_stats["tri_kept"] = int(tri_stats.get("tri_kept", 0)) + 1
				if invert_faces:
					terrain_indices.push_back(i_a)
					terrain_indices.push_back(i_b)
					terrain_indices.push_back(i_c)
				else:
					terrain_indices.push_back(i_a)
					terrain_indices.push_back(i_c)
					terrain_indices.push_back(i_b)
			else:
				_append_boolean_fill_triangle_bisect(
					pa2,
					pb2,
					pc2,
					verts,
					normals,
					uvs,
					terrain_indices,
					road_tris,
					boundary_height_map,
					boundary_points,
					base_y,
					max_leaf_edge_len,
					split_depth_max,
					0,
					tri_stats
				)
	_debug_log(
		"boolean fill tris candidates=%s kept=%s rejected_overlap=%s"
		% [
			int(tri_stats.get("tri_candidates", 0)),
			int(tri_stats.get("tri_kept", 0)),
			int(tri_stats.get("tri_rejected_overlap", 0))
		]
	)


func _append_boolean_fill_triangle_bisect(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	road_tris: Array,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	max_edge_len: float,
	max_depth: int,
	depth: int,
	tri_stats: Dictionary
) -> void:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var longest := maxf(ab, maxf(bc, ca))
	if depth < max_depth and longest > max_edge_len:
		if ab >= bc and ab >= ca:
			var m_ab := (a + b) * 0.5
			_append_boolean_fill_triangle_bisect(
				a,
				m_ab,
				c,
				verts,
				normals,
				uvs,
				terrain_indices,
				road_tris,
				boundary_height_map,
				boundary_points,
				base_y,
				max_edge_len,
				max_depth,
				depth + 1,
				tri_stats
			)
			_append_boolean_fill_triangle_bisect(
				m_ab,
				b,
				c,
				verts,
				normals,
				uvs,
				terrain_indices,
				road_tris,
				boundary_height_map,
				boundary_points,
				base_y,
				max_edge_len,
				max_depth,
				depth + 1,
				tri_stats
			)
			return
		if bc >= ca:
			var m_bc := (b + c) * 0.5
			_append_boolean_fill_triangle_bisect(
				b,
				m_bc,
				a,
				verts,
				normals,
				uvs,
				terrain_indices,
				road_tris,
				boundary_height_map,
				boundary_points,
				base_y,
				max_edge_len,
				max_depth,
				depth + 1,
				tri_stats
			)
			_append_boolean_fill_triangle_bisect(
				m_bc,
				c,
				a,
				verts,
				normals,
				uvs,
				terrain_indices,
				road_tris,
				boundary_height_map,
				boundary_points,
				base_y,
				max_edge_len,
				max_depth,
				depth + 1,
				tri_stats
			)
			return
		var m_ca := (c + a) * 0.5
		_append_boolean_fill_triangle_bisect(
			c,
			m_ca,
			b,
			verts,
			normals,
			uvs,
			terrain_indices,
			road_tris,
			boundary_height_map,
			boundary_points,
			base_y,
			max_edge_len,
			max_depth,
			depth + 1,
			tri_stats
		)
		_append_boolean_fill_triangle_bisect(
			m_ca,
			a,
			b,
			verts,
			normals,
			uvs,
			terrain_indices,
			road_tris,
			boundary_height_map,
			boundary_points,
			base_y,
			max_edge_len,
			max_depth,
			depth + 1,
			tri_stats
		)
		return

	tri_stats["tri_candidates"] = int(tri_stats.get("tri_candidates", 0)) + 1
	if _boolean_fill_triangle_overlaps_road_xz(a, b, c, road_tris):
		tri_stats["tri_rejected_overlap"] = int(tri_stats.get("tri_rejected_overlap", 0)) + 1
		return

	var y_a := _sample_boolean_fill_vertex_height(a, boundary_height_map, boundary_points, base_y)
	var y_b := _sample_boolean_fill_vertex_height(b, boundary_height_map, boundary_points, base_y)
	var y_c := _sample_boolean_fill_vertex_height(c, boundary_height_map, boundary_points, base_y)
	var p_a := Vector3(a.x, y_a, a.y)
	var p_b := Vector3(b.x, y_b, b.y)
	var p_c := Vector3(c.x, y_c, c.y)

	var i_a := verts.size()
	verts.push_back(p_a)
	normals.push_back(Vector3.UP)
	uvs.push_back(Vector2(p_a.x, p_a.z) * uv_length_scale)
	var i_b := verts.size()
	verts.push_back(p_b)
	normals.push_back(Vector3.UP)
	uvs.push_back(Vector2(p_b.x, p_b.z) * uv_length_scale)
	var i_c := verts.size()
	verts.push_back(p_c)
	normals.push_back(Vector3.UP)
	uvs.push_back(Vector2(p_c.x, p_c.z) * uv_length_scale)

	tri_stats["tri_kept"] = int(tri_stats.get("tri_kept", 0)) + 1
	if invert_faces:
		terrain_indices.push_back(i_a)
		terrain_indices.push_back(i_b)
		terrain_indices.push_back(i_c)
	else:
		terrain_indices.push_back(i_a)
		terrain_indices.push_back(i_c)
		terrain_indices.push_back(i_b)


func _boolean_fill_triangle_overlaps_road_xz(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	road_tris: Array
) -> bool:
	if road_tris.is_empty():
		return false
	var centroid := (a + b + c) / 3.0
	# Clipping already subtracts road polygons. Here we only guard against
	# residual triangles fully inside road area; border-touching triangles are kept.
	var eps := 0.0001
	if not _point_over_any_road_triangle_xz(centroid, road_tris, eps):
		return false
	var inside_vertices := 0
	if _point_over_any_road_triangle_xz(a, road_tris, eps):
		inside_vertices += 1
	if _point_over_any_road_triangle_xz(b, road_tris, eps):
		inside_vertices += 1
	if _point_over_any_road_triangle_xz(c, road_tris, eps):
		inside_vertices += 1
	if inside_vertices >= 2:
		return true
	var mid_ab := (a + b) * 0.5
	var mid_bc := (b + c) * 0.5
	var mid_ca := (c + a) * 0.5
	var inside_midpoints := 0
	if _point_over_any_road_triangle_xz(mid_ab, road_tris, eps):
		inside_midpoints += 1
	if _point_over_any_road_triangle_xz(mid_bc, road_tris, eps):
		inside_midpoints += 1
	if _point_over_any_road_triangle_xz(mid_ca, road_tris, eps):
		inside_midpoints += 1
	return inside_midpoints >= 2


func _extract_road_boundary_loops_xz(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array
) -> Dictionary:
	var edge_counts: Dictionary = {}
	_count_boundary_edges_from_surface(lane_indices, edge_counts)
	_count_boundary_edges_from_surface(shoulder_indices, edge_counts)
	_count_boundary_edges_from_surface(sidewalk_indices, edge_counts)

	var adjacency: Dictionary = {}
	var boundary_keys: Array = []
	for key_raw in edge_counts.keys():
		var key := str(key_raw)
		if int(edge_counts.get(key, 0)) != 1:
			continue
		var edge := _edge_key_to_indices(key)
		if edge.x < 0 or edge.y < 0:
			continue
		boundary_keys.push_back(key)
		_append_boundary_neighbor(adjacency, edge.x, edge.y)
		_append_boundary_neighbor(adjacency, edge.y, edge.x)

	var visited: Dictionary = {}
	for key in boundary_keys:
		visited[key] = false

	var loops: Array = []
	var boundary_points: Array = []
	for start_key in boundary_keys:
		if bool(visited.get(start_key, false)):
			continue
		var start_edge := _edge_key_to_indices(start_key)
		if start_edge.x < 0 or start_edge.y < 0:
			continue

		var chain: Array = [start_edge.x, start_edge.y]
		visited[start_key] = true
		var current := start_edge.y
		var closed := false
		var safety := 0
		while safety < 100000:
			safety += 1
			var neighbors: Array = adjacency.get(current, [])
			var next_idx := -1
			for n_raw in neighbors:
				var n := int(n_raw)
				var edge_key := _edge_key_from_indices(current, n)
				if bool(visited.get(edge_key, false)):
					continue
				next_idx = n
				break
			if next_idx < 0:
				break
			visited[_edge_key_from_indices(current, next_idx)] = true
			if next_idx == chain[0]:
				closed = true
				break
			chain.push_back(next_idx)
			current = next_idx
			if chain.size() > 65535:
				break
		if not closed or chain.size() < 3:
			continue

		var poly := PackedVector2Array()
		for vid_raw in chain:
			var vid := int(vid_raw)
			if vid < 0 or vid >= verts.size():
				continue
			var p3: Vector3 = verts[vid]
			poly.push_back(Vector2(p3.x, p3.z))
			boundary_points.push_back(p3)
		poly = _compact_polygon2d_xz(poly, 0.001)
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		loops.push_back(poly)

	return {
		"loops": loops,
		"points": boundary_points,
	}


func _build_path_row_boundary_polygons_xz(verts: PackedVector3Array, path_rows: Array) -> Array:
	return _build_path_row_boundary_polygons_xz_mode(
		verts,
		path_rows,
		terrain_boolean_clip_width_mode == TERRAIN_BOOLEAN_CLIP_LANE_ONLY
	)


func _build_path_row_boundary_polygons_xz_mode(
	verts: PackedVector3Array,
	path_rows: Array,
	lane_only: bool
) -> Array:
	var loops: Array = []
	var left_edge_id := 0
	var right_edge_id := 5
	if lane_only:
		left_edge_id = 2
		right_edge_id = 3
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		if rows.size() < 2:
			continue
		var left_chain := PackedVector2Array()
		var right_chain := PackedVector2Array()
		for row_raw in rows:
			var row: Dictionary = row_raw
			var row_edges: Array = row.get("row_edges", [])
			if row_edges.size() < 6:
				continue
			var left_idx := int(row_edges[left_edge_id])
			var right_idx := int(row_edges[right_edge_id])
			if left_idx >= 0 and left_idx < verts.size():
				var lp := Vector2(verts[left_idx].x, verts[left_idx].z)
				if left_chain.is_empty() or left_chain[left_chain.size() - 1].distance_to(lp) > 0.001:
					left_chain.push_back(lp)
			if right_idx >= 0 and right_idx < verts.size():
				var rp := Vector2(verts[right_idx].x, verts[right_idx].z)
				if right_chain.is_empty() or right_chain[right_chain.size() - 1].distance_to(rp) > 0.001:
					right_chain.push_back(rp)
		if left_chain.size() < 2 or right_chain.size() < 2:
			continue
		var poly := PackedVector2Array()
		for p in left_chain:
			poly.push_back(p)
		for i in range(right_chain.size() - 1, -1, -1):
			poly.push_back(right_chain[i])
		poly = _compact_polygon2d_xz(poly, 0.001)
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		loops.push_back(poly)
	return loops


func _count_boundary_edges_from_surface(indices: PackedInt32Array, edge_counts: Dictionary) -> void:
	if indices.is_empty():
		return
	var tri_count := indices.size() - (indices.size() % 3)
	for i in range(0, tri_count, 3):
		_register_boundary_edge(int(indices[i]), int(indices[i + 1]), edge_counts)
		_register_boundary_edge(int(indices[i + 1]), int(indices[i + 2]), edge_counts)
		_register_boundary_edge(int(indices[i + 2]), int(indices[i]), edge_counts)


func _register_boundary_edge(a: int, b: int, edge_counts: Dictionary) -> void:
	if a == b:
		return
	var key := _edge_key_from_indices(a, b)
	edge_counts[key] = int(edge_counts.get(key, 0)) + 1


func _append_boundary_neighbor(adjacency: Dictionary, from_idx: int, to_idx: int) -> void:
	var neighbors: Array = adjacency.get(from_idx, [])
	neighbors.push_back(to_idx)
	adjacency[from_idx] = neighbors


func _edge_key_from_indices(a: int, b: int) -> String:
	return str(mini(a, b)) + ":" + str(maxi(a, b))


func _edge_key_to_indices(key: String) -> Vector2i:
	var parts := key.split(":")
	if parts.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _compact_polygon2d_xz(poly: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.size() < 3:
		return out
	var eps := maxf(0.000001, epsilon)
	for i in range(poly.size()):
		var p := poly[i]
		if out.is_empty() or out[out.size() - 1].distance_to(p) > eps:
			out.push_back(p)
	if out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) <= eps:
		out.remove_at(out.size() - 1)
	if out.size() < 3:
		return PackedVector2Array()
	return out


func _resample_polygon_edges_for_boolean_fill(poly: PackedVector2Array, max_edge_len: float) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var step := maxf(0.5, max_edge_len)
	var out := PackedVector2Array()
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		out.push_back(a)
		var edge_len := a.distance_to(b)
		if edge_len <= step:
			continue
		var segments := maxi(1, int(ceil(edge_len / step)))
		for s in range(1, segments):
			var t := float(s) / float(segments)
			out.push_back(a.lerp(b, t))
	return _compact_polygon2d_xz(out, 0.0005)


func _union_polygon_parts_for_fill(parts: Array, poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p_raw in parts:
		var p: PackedVector2Array = p_raw
		if p.size() >= 3:
			out.push_back(p)
	out.push_back(poly)

	var merged := true
	while merged:
		merged = false
		for i in range(out.size()):
			var a: PackedVector2Array = out[i]
			for j in range(i + 1, out.size()):
				var b: PackedVector2Array = out[j]
				var candidate: Array = Geometry2D.merge_polygons(a, b)
				if candidate.size() == 1:
					var only: PackedVector2Array = _compact_polygon2d_xz(candidate[0], 0.001)
					if only.size() < 3:
						continue
					out[i] = only
					out.remove_at(j)
					merged = true
					break
			if merged:
				break
	return out


func _clip_fill_parts_by_polygon(fill_parts: Array, clip_poly: PackedVector2Array) -> Array:
	var out: Array = []
	var clip := _compact_polygon2d_xz(clip_poly, 0.001)
	if clip.size() < 3:
		return fill_parts

	# Ensure clip is clockwise for clip_polygons (subtraction)
	if not Geometry2D.is_polygon_clockwise(clip):
		clip.reverse()
	var clip_rev := clip
	clip_rev.reverse()

	for part_raw in fill_parts:
		var part: PackedVector2Array = _compact_polygon2d_xz(part_raw, 0.001)
		if part.size() < 3:
			continue

		# clip_polygons(A, B) computes A - B.
		var clipped := Geometry2D.clip_polygons(part, clip)
		if clipped.is_empty():
			# Winding mismatch can make clip_polygons return empty on valid inputs.
			var part_rev := part
			part_rev.reverse()
			clipped = Geometry2D.clip_polygons(part_rev, clip)
		if clipped.is_empty():
			clipped = Geometry2D.clip_polygons(part, clip_rev)
		if clipped.is_empty():
			var part_rev2 := part
			part_rev2.reverse()
			clipped = Geometry2D.clip_polygons(part_rev2, clip_rev)
		
		# If clipping failed or produced no results, check if the part is completely inside or outside.
		if clipped.is_empty():
			var probe := _polygon_probe_point(part)
			if Geometry2D.is_point_in_polygon(probe, clip):
				# Completely inside the road, drop it.
				continue
			else:
				# Completely outside, keep it.
				out.push_back(part)
				continue

		for piece_raw in clipped:
			var piece: PackedVector2Array = _compact_polygon2d_xz(piece_raw, 0.001)
			if piece.size() >= 3:
				out.push_back(piece)
	return out


func _filter_parts_outside_clip(
	parts: Array,
	clip_a: PackedVector2Array,
	clip_b: PackedVector2Array
) -> Array:
	var out: Array = []
	for piece_raw in parts:
		var piece: PackedVector2Array = _compact_polygon2d_xz(piece_raw, 0.001)
		if piece.size() < 3:
			continue
		var probe := _polygon_probe_point(piece)
		var inside_a := Geometry2D.is_point_in_polygon(probe, clip_a)
		var inside_b := Geometry2D.is_point_in_polygon(probe, clip_b)
		if not inside_a and not inside_b:
			out.push_back(piece)
	return out


func _polygon_probe_point(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var tri_local: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if tri_local.size() >= 3:
		var ia := int(tri_local[0])
		var ib := int(tri_local[1])
		var ic := int(tri_local[2])
		if ia >= 0 and ib >= 0 and ic >= 0 and ia < poly.size() and ib < poly.size() and ic < poly.size():
			return (poly[ia] + poly[ib] + poly[ic]) / 3.0
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())


func _compact_polygons_array_xz(parts: Array) -> Array:
	var out: Array = []
	for raw in parts:
		var poly: PackedVector2Array = _compact_polygon2d_xz(raw, 0.001)
		if poly.size() >= 3:
			out.push_back(poly)
	return out


func _polygon_parts_total_area_abs_xz(parts: Array) -> float:
	var total := 0.0
	for raw in parts:
		var poly: PackedVector2Array = raw
		total += _polygon_area_abs_xz(poly)
	return total


func _polygon_area_abs_xz(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var sum := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum * 0.5)


func _pick_largest_polygon_part_xz(parts: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for raw in parts:
		var poly: PackedVector2Array = _compact_polygon2d_xz(raw, 0.001)
		if poly.size() < 3:
			continue
		var area := _polygon_area_abs_xz(poly)
		if area > best_area:
			best_area = area
			best = poly
	return best


func _sample_boolean_fill_vertex_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	default_y: float
) -> float:
	var eps := maxf(0.0001, terrain_boolean_height_match_epsilon)
	var key := Vector2i(int(round(point.x / eps)), int(round(point.y / eps)))
	if boundary_height_map.has(key):
		var sum_and_count: Array = boundary_height_map.get(key, [default_y, 1])
		var count := maxi(1, int(sum_and_count[1]))
		return float(sum_and_count[0]) / float(count)

	var max_dist := maxf(0.0, terrain_boolean_height_match_max_distance)
	if max_dist <= 0.0001:
		return default_y

	var best_y := default_y
	var best_dist := max_dist
	for p_raw in boundary_points:
		var p: Vector3 = p_raw
		var d := Vector2(p.x, p.z).distance_to(point)
		if d <= best_dist:
			best_dist = d
			best_y = p.y
	return best_y


func _append_terrain_from_path_rows(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {}
) -> void:
	var road_tris := _build_road_tri_xz_cache(verts, lane_indices, shoulder_indices, sidewalk_indices, path_rows)
	var terrain_noise := _build_terrain_noise()
	var terrain_heightmap_image := _build_terrain_heightmap_image()
	var use_blocked_sides := not blocked_side_vertices.is_empty()
	var continuity_width := 0.001
	var growth_recovery_floor := continuity_width * 8.0
	for rows_raw in path_rows:
		var rows: Array = rows_raw
		if rows.size() < 2:
			continue
		var terrain_subdiv_count := _resolve_terrain_subdivisions_for_rows(rows)
		_debug_log(
			"terrain adaptive rows=%s subdiv=%s"
			% [rows.size(), terrain_subdiv_count]
		)

		var left_outer_ids := PackedInt32Array()
		left_outer_ids.resize(rows.size())
		var right_outer_ids := PackedInt32Array()
		right_outer_ids.resize(rows.size())
		var left_outer_points: Array[Vector3] = []
		left_outer_points.resize(rows.size())
		var right_outer_points: Array[Vector3] = []
		right_outer_points.resize(rows.size())
		var left_base_ids := PackedInt32Array()
		left_base_ids.resize(rows.size())
		var right_base_ids := PackedInt32Array()
		right_base_ids.resize(rows.size())
		var left_applied_widths := PackedFloat32Array()
		left_applied_widths.resize(rows.size())
		var right_applied_widths := PackedFloat32Array()
		right_applied_widths.resize(rows.size())
		for init_idx in range(rows.size()):
			left_outer_ids[init_idx] = -1
			right_outer_ids[init_idx] = -1
			left_base_ids[init_idx] = -1
			right_base_ids[init_idx] = -1
			left_applied_widths[init_idx] = 0.0
			right_applied_widths[init_idx] = 0.0

		for row_idx in range(rows.size()):
			var row: Dictionary = rows[row_idx]
			var row_edges: Array = row.get("row_edges", [])
			if row_edges.size() < 6:
				continue

			var left_w_requested := maxf(0.0, float(row.get("terrain_left_width", terrain_left_width)))
			var right_w_requested := maxf(0.0, float(row.get("terrain_right_width", terrain_right_width)))
			if use_blocked_sides:
				if (
					blocked_side_vertices.has(int(row_edges[0]))
					or blocked_side_vertices.has(int(row_edges[1]))
				):
					left_w_requested = 0.0
				if (
					blocked_side_vertices.has(int(row_edges[4]))
					or blocked_side_vertices.has(int(row_edges[5]))
				):
					right_w_requested = 0.0
			# Collapse detection is geometric-only; do not couple it to road clearance.
			var collapsed_eps := 0.02
			var left_outer_idx := int(row_edges[0])
			var left_inner_collapse_idx := int(row_edges[2])
			if (
				left_outer_idx >= 0
				and left_outer_idx < verts.size()
				and left_inner_collapse_idx >= 0
				and left_inner_collapse_idx < verts.size()
				and verts[left_outer_idx].distance_to(verts[left_inner_collapse_idx]) <= collapsed_eps
			):
				left_w_requested = 0.0
			var right_outer_idx := int(row_edges[5])
			var right_inner_collapse_idx := int(row_edges[3])
			if (
				right_outer_idx >= 0
				and right_outer_idx < verts.size()
				and right_inner_collapse_idx >= 0
				and right_inner_collapse_idx < verts.size()
				and verts[right_outer_idx].distance_to(verts[right_inner_collapse_idx]) <= collapsed_eps
			):
				right_w_requested = 0.0
			var left_w := left_w_requested
			var right_w := right_w_requested
			if left_w <= 0.0001 and right_w <= 0.0001:
				continue

			var row_dir := Vector3(row.get("out_dir", Vector3.FORWARD))
			row_dir.y = 0.0
			if row_dir.length() < 0.001:
				row_dir = Vector3.FORWARD
			else:
				row_dir = row_dir.normalized()

			left_base_ids[row_idx] = int(row_edges[0])
			right_base_ids[row_idx] = int(row_edges[5])

			if left_w > 0.0001:
				var left_top_idx := int(row_edges[0])
				var left_inner_idx := int(row_edges[2])
				if left_top_idx >= 0 and left_top_idx < verts.size() and left_inner_idx >= 0 and left_inner_idx < verts.size():
					var left_top := verts[left_top_idx]
					var left_out := left_top - verts[left_inner_idx]
					left_out.y = 0.0
					if left_out.length() < 0.001:
						left_out = Vector3(row_dir.z, 0.0, -row_dir.x)
					if left_out.length() < 0.001:
						left_out = Vector3.LEFT
					else:
						left_out = left_out.normalized()
					var left_prev_idx := row_idx - 1
					if left_prev_idx < 0 or int(left_outer_ids[left_prev_idx]) < 0:
						left_prev_idx = -1
					if left_prev_idx >= 0:
						if terrain_growth_max_delta_per_row > 0.0001:
							var prev_left_w := float(left_applied_widths[left_prev_idx])
							if prev_left_w > growth_recovery_floor:
								left_w = minf(left_w, prev_left_w + terrain_growth_max_delta_per_row)
						left_w = _limit_terrain_growth_width_for_segment(
							verts,
							left_top,
							left_out,
							left_w,
							left_prev_idx,
							row_idx,
							left_outer_points,
							left_outer_ids,
							left_base_ids,
							right_base_ids,
							road_tris
						)
					if left_w <= 0.0001:
						left_w = continuity_width
					left_applied_widths[row_idx] = left_w
					var left_terrain := left_top + left_out * left_w
					var left_idx := verts.size()
					verts.push_back(left_terrain)
					normals.push_back(Vector3.UP)
					uvs.push_back(Vector2(left_terrain.x, left_terrain.z) * uv_length_scale)
					left_outer_points[row_idx] = left_terrain
					left_outer_ids[row_idx] = left_idx

			if right_w > 0.0001:
				var right_top_idx := int(row_edges[5])
				var right_inner_idx := int(row_edges[3])
				if right_top_idx >= 0 and right_top_idx < verts.size() and right_inner_idx >= 0 and right_inner_idx < verts.size():
					var right_top := verts[right_top_idx]
					var right_out := right_top - verts[right_inner_idx]
					right_out.y = 0.0
					if right_out.length() < 0.001:
						right_out = Vector3(-row_dir.z, 0.0, row_dir.x)
					if right_out.length() < 0.001:
						right_out = Vector3.RIGHT
					else:
						right_out = right_out.normalized()
					var right_prev_idx := row_idx - 1
					if right_prev_idx < 0 or int(right_outer_ids[right_prev_idx]) < 0:
						right_prev_idx = -1
					if right_prev_idx >= 0:
						if terrain_growth_max_delta_per_row > 0.0001:
							var prev_right_w := float(right_applied_widths[right_prev_idx])
							if prev_right_w > growth_recovery_floor:
								right_w = minf(right_w, prev_right_w + terrain_growth_max_delta_per_row)
						right_w = _limit_terrain_growth_width_for_segment(
							verts,
							right_top,
							right_out,
							right_w,
							right_prev_idx,
							row_idx,
							right_outer_points,
							right_outer_ids,
							right_base_ids,
							left_base_ids,
							road_tris
						)
					if right_w <= 0.0001:
						right_w = continuity_width
					right_applied_widths[row_idx] = right_w
					var right_terrain := right_top + right_out * right_w
					var right_idx := verts.size()
					verts.push_back(right_terrain)
					normals.push_back(Vector3.UP)
					uvs.push_back(Vector2(right_terrain.x, right_terrain.z) * uv_length_scale)
					right_outer_points[row_idx] = right_terrain
					right_outer_ids[row_idx] = right_idx

		if terrain_artifact_safe_stitch:
			_stabilize_terrain_side_chain(
				verts,
				normals,
				uvs,
				left_base_ids,
				left_outer_ids,
				left_outer_points,
				left_applied_widths
			)
			_stabilize_terrain_side_chain(
				verts,
				normals,
				uvs,
				right_base_ids,
				right_outer_ids,
				right_outer_points,
				right_applied_widths
			)

		var left_ring_ids := _build_terrain_side_rings(
			verts,
			normals,
			uvs,
			left_base_ids,
			left_outer_ids,
			rows.size(),
			terrain_subdiv_count,
			terrain_noise,
			terrain_heightmap_image
		)
		var right_ring_ids := _build_terrain_side_rings(
			verts,
			normals,
			uvs,
			right_base_ids,
			right_outer_ids,
			rows.size(),
			terrain_subdiv_count,
			terrain_noise,
			terrain_heightmap_image
		)

		for span_idx in range(rows.size() - 1):
			for ring_i in range(terrain_subdiv_count):
				var left_inner_ring: Array = left_ring_ids[ring_i]
				var left_outer_ring: Array = left_ring_ids[ring_i + 1]
				var left_inner0 := int(left_inner_ring[span_idx])
				var left_inner1 := int(left_inner_ring[span_idx + 1])
				var left_outer0 := int(left_outer_ring[span_idx])
				var left_outer1 := int(left_outer_ring[span_idx + 1])
				if left_inner0 >= 0 and left_inner1 >= 0 and left_outer0 >= 0 and left_outer1 >= 0:
					# Keep road-edge vertices fixed and only deform outward rings.
					_append_quad_indices(terrain_indices, left_outer0, left_inner0, left_outer1, left_inner1)

				var right_inner_ring: Array = right_ring_ids[ring_i]
				var right_outer_ring: Array = right_ring_ids[ring_i + 1]
				var right_inner0 := int(right_inner_ring[span_idx])
				var right_inner1 := int(right_inner_ring[span_idx + 1])
				var right_outer0 := int(right_outer_ring[span_idx])
				var right_outer1 := int(right_outer_ring[span_idx + 1])
				if right_inner0 >= 0 and right_inner1 >= 0 and right_outer0 >= 0 and right_outer1 >= 0:
					_append_quad_indices(terrain_indices, right_inner0, right_outer0, right_inner1, right_outer1)

		if terrain_skirt_depth > 0.0001:
			_append_terrain_side_skirts(
				verts,
				normals,
				uvs,
				terrain_indices,
				left_ring_ids,
				terrain_subdiv_count,
				terrain_skirt_depth
			)
			_append_terrain_side_skirts(
				verts,
				normals,
				uvs,
				terrain_indices,
				right_ring_ids,
				terrain_subdiv_count,
				terrain_skirt_depth
			)


func _stabilize_terrain_side_chain(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	base_ids: PackedInt32Array,
	outer_ids: PackedInt32Array,
	outer_points: Array[Vector3],
	applied_widths: PackedFloat32Array
) -> void:
	var count := mini(base_ids.size(), outer_ids.size())
	if count <= 0:
		return

	# Keep topology continuous: missing rows get a collapsed outer vertex on the base edge.
	for i in range(count):
		var outer_idx := int(outer_ids[i])
		if outer_idx >= 0 and outer_idx < verts.size():
			outer_points[i] = verts[outer_idx]
			continue
		var base_idx := int(base_ids[i])
		if base_idx < 0 or base_idx >= verts.size():
			continue
		var p := verts[base_idx]
		var new_idx := verts.size()
		verts.push_back(p)
		normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(p.x, p.z) * uv_length_scale)
		outer_ids[i] = new_idx
		outer_points[i] = p
		if i < applied_widths.size():
			applied_widths[i] = 0.0

	var smooth_passes := maxi(0, terrain_chain_smooth_passes)
	if smooth_passes <= 0 or count < 3:
		return

	for _pass in range(smooth_passes):
		var next_points: Array[Vector3] = outer_points.duplicate()
		for i in range(1, count - 1):
			if i >= applied_widths.size():
				continue
			if applied_widths[i] <= 0.0001:
				continue
			var prev_idx := int(outer_ids[i - 1])
			var curr_idx := int(outer_ids[i])
			var next_idx := int(outer_ids[i + 1])
			if prev_idx < 0 or curr_idx < 0 or next_idx < 0:
				continue
			if prev_idx >= verts.size() or curr_idx >= verts.size() or next_idx >= verts.size():
				continue
			var prev_p: Vector3 = outer_points[i - 1]
			var curr_p: Vector3 = outer_points[i]
			var next_p: Vector3 = outer_points[i + 1]
			var smoothed := (prev_p + curr_p * 2.0 + next_p) * 0.25
			smoothed.y = curr_p.y
			next_points[i] = smoothed

		for i in range(count):
			outer_points[i] = next_points[i]
			var idx := int(outer_ids[i])
			if idx < 0 or idx >= verts.size():
				continue
			var p: Vector3 = outer_points[i]
			verts[idx] = p
			normals[idx] = Vector3.UP
			uvs[idx] = Vector2(p.x, p.z) * uv_length_scale


func _resolve_terrain_subdivisions_for_rows(rows: Array) -> int:
	var base_subdiv := maxi(1, terrain_subdivisions)
	if not terrain_adaptive_subdivisions_enabled:
		return base_subdiv

	var max_width := 0.0
	for row_raw in rows:
		var row: Dictionary = row_raw
		var left_w := maxf(0.0, float(row.get("terrain_left_width", terrain_left_width)))
		var right_w := maxf(0.0, float(row.get("terrain_right_width", terrain_right_width)))
		max_width = maxf(max_width, left_w)
		max_width = maxf(max_width, right_w)

	if max_width <= 0.0001:
		return base_subdiv

	var density_target := int(ceil(max_width * maxf(0.0, terrain_adaptive_subdivisions_per_meter)))
	var noise_target := 0
	if terrain_noise_enabled and terrain_noise_amplitude > 0.0001:
		var safe_frequency := maxf(0.0, terrain_noise_frequency)
		var nyquist_target := max_width * safe_frequency * 2.0
		noise_target = int(ceil(nyquist_target * maxf(0.1, terrain_adaptive_noise_quality)))
	var heightmap_target := 0
	if terrain_heightmap_enabled and terrain_heightmap_texture != null and absf(terrain_heightmap_amplitude) > 0.0001:
		var tex_freq := maxf(absf(terrain_heightmap_uv_scale.x), absf(terrain_heightmap_uv_scale.y))
		var tex_nyquist_target := max_width * tex_freq * 2.0
		heightmap_target = int(ceil(tex_nyquist_target * maxf(0.1, terrain_adaptive_noise_quality)))

	var adaptive_target := maxi(base_subdiv, maxi(density_target, maxi(noise_target, heightmap_target)))
	var hard_cap := maxi(base_subdiv, terrain_adaptive_subdivisions_max)
	return clampi(adaptive_target, 1, hard_cap)


func _append_terrain_side_skirts(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	ring_ids: Array,
	subdivisions: int,
	depth: float
) -> void:
	if depth <= 0.0001:
		return
	if ring_ids.size() < subdivisions + 1:
		return
	if subdivisions < 1:
		return
	var inner_ring: Array = ring_ids[0]
	var outer_ring: Array = ring_ids[subdivisions]
	if inner_ring.is_empty() or outer_ring.is_empty():
		return
	var row_count := inner_ring.size()
	if row_count < 2:
		return
	_soften_outer_area_for_skirt(verts, normals, ring_ids, subdivisions)

	var start_chain: Array = []
	var end_chain: Array = []
	for ring_i in range(subdivisions + 1):
		var ring: Array = ring_ids[ring_i]
		if ring.size() != row_count:
			return
		start_chain.push_back(int(ring[0]))
		end_chain.push_back(int(ring[row_count - 1]))

	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, inner_ring, depth)
	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, outer_ring, depth)
	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, start_chain, depth)
	_append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, end_chain, depth)


func _soften_outer_area_for_skirt(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	ring_ids: Array,
	subdivisions: int
) -> void:
	var slope_limit := clampf(terrain_skirt_soften_slope_deg, 0.0, 89.0)
	var max_drop := maxf(0.0, terrain_skirt_soften_max_drop)
	var soften_power := maxf(0.1, terrain_skirt_soften_power)
	var area_rings := maxi(1, terrain_skirt_soften_area_rings)
	var area_falloff := maxf(0.1, terrain_skirt_soften_area_falloff)
	var smooth_passes := maxi(0, terrain_skirt_soften_row_smooth_passes)
	if slope_limit <= 0.0001 or max_drop <= 0.0001:
		return
	if subdivisions < 1:
		return
	if ring_ids.size() < subdivisions + 1:
		return
	var outer_ring: Array = ring_ids[subdivisions]
	var inner_ring: Array = ring_ids[maxi(0, subdivisions - 1)]
	var count := mini(outer_ring.size(), inner_ring.size())
	if count <= 0:
		return
	var row_drop := PackedFloat32Array()
	row_drop.resize(count)
	for i in range(count):
		row_drop[i] = 0.0
		var outer_idx := int(outer_ring[i])
		var inner_idx := int(inner_ring[i])
		if outer_idx < 0 or inner_idx < 0:
			continue
		if outer_idx >= verts.size() or inner_idx >= verts.size():
			continue
		var outer_p := verts[outer_idx]
		var inner_p := verts[inner_idx]
		var edge := outer_p - inner_p
		var edge_xz := Vector2(edge.x, edge.z).length()
		if edge_xz <= 0.0001:
			continue
		var slope_deg := absf(rad_to_deg(atan2(edge.y, edge_xz)))
		if slope_deg >= slope_limit:
			continue
		var t := 1.0 - (slope_deg / slope_limit)
		t = pow(clampf(t, 0.0, 1.0), soften_power)
		row_drop[i] = max_drop * t

	if smooth_passes > 0 and count > 2:
		for _pass in range(smooth_passes):
			var smoothed := row_drop.duplicate()
			for i in range(1, count - 1):
				smoothed[i] = (row_drop[i - 1] + row_drop[i] * 2.0 + row_drop[i + 1]) * 0.25
			row_drop = smoothed

	for ring_offset in range(area_rings):
		var ring_idx := subdivisions - ring_offset
		if ring_idx < 0 or ring_idx >= ring_ids.size():
			break
		var ring: Array = ring_ids[ring_idx]
		var distance_factor := float(ring_offset + 1) / float(area_rings)
		var falloff := pow(distance_factor, area_falloff)
		for i in range(mini(count, ring.size())):
			var drop := row_drop[i] * falloff
			if drop <= 0.0001:
				continue
			var vi := int(ring[i])
			if vi < 0 or vi >= verts.size():
				continue
			var p := verts[vi]
			p.y -= drop
			verts[vi] = p
			if vi < normals.size():
				normals[vi] = Vector3.UP


func _append_terrain_skirt_from_index_chain(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	chain: Array,
	depth: float
) -> void:
	if chain.size() < 2:
		return
	var steps := maxi(1, terrain_skirt_segments)
	var outward := maxf(0.0, terrain_skirt_outward)
	var profile := maxf(0.1, terrain_skirt_profile)
	var levels: Array = []
	levels.resize(steps + 1)
	var top_level: Array = []
	top_level.resize(chain.size())
	var center := Vector3.ZERO
	var center_count := 0
	for i in range(chain.size()):
		var top_idx := int(chain[i])
		top_level[i] = top_idx
		if top_idx >= 0 and top_idx < verts.size():
			center += verts[top_idx]
			center_count += 1
	levels[0] = top_level
	if center_count <= 0:
		return
	center /= float(center_count)

	for step_i in range(1, steps + 1):
		var t := float(step_i) / float(steps)
		var depth_t := depth * pow(t, profile)
		var out_t := outward * sin(t * PI * 0.5)
		var level: Array = []
		level.resize(chain.size())
		for i in range(chain.size()):
			level[i] = -1
			var top_idx := int(top_level[i])
			if top_idx < 0 or top_idx >= verts.size():
				continue
			var top_p := verts[top_idx]
			var out_dir := _compute_skirt_outward_dir(verts, chain, i, center)
			var p := top_p + out_dir * out_t - Vector3.UP * depth_t
			var vi := verts.size()
			verts.push_back(p)
			var skirt_n := Vector3(out_dir.x, 0.35, out_dir.z)
			if skirt_n.length() < 0.001:
				skirt_n = Vector3.UP
			else:
				skirt_n = skirt_n.normalized()
			normals.push_back(skirt_n)
			uvs.push_back(Vector2(p.x, p.z) * uv_length_scale)
			level[i] = vi
		levels[step_i] = level

	for step_i in range(steps):
		var upper: Array = levels[step_i]
		var lower: Array = levels[step_i + 1]
		for i in range(chain.size() - 1):
			var up0 := int(upper[i])
			var up1 := int(upper[i + 1])
			var lo0 := int(lower[i])
			var lo1 := int(lower[i + 1])
			if up0 < 0 or up1 < 0 or lo0 < 0 or lo1 < 0:
				continue
			_append_quad_indices(terrain_indices, up0, lo0, up1, lo1)


func _compute_skirt_outward_dir(
	verts: PackedVector3Array,
	chain: Array,
	idx: int,
	center: Vector3
) -> Vector3:
	var curr_idx := int(chain[idx])
	if curr_idx < 0 or curr_idx >= verts.size():
		return Vector3.ZERO
	var curr := verts[curr_idx]
	var radial2 := Vector2(curr.x - center.x, curr.z - center.z)
	var radial := Vector3(radial2.x, 0.0, radial2.y)
	if radial.length() > 0.001:
		return radial.normalized()

	var prev_i := maxi(0, idx - 1)
	var next_i := mini(chain.size() - 1, idx + 1)
	var prev_idx := int(chain[prev_i])
	var next_idx := int(chain[next_i])
	if prev_idx >= 0 and prev_idx < verts.size() and next_idx >= 0 and next_idx < verts.size():
		var prev := verts[prev_idx]
		var next := verts[next_idx]
		var tan2 := Vector2(next.x - prev.x, next.z - prev.z)
		if tan2.length() > 0.001:
			var tn := tan2.normalized()
			var perp := Vector2(-tn.y, tn.x)
			return Vector3(perp.x, 0.0, perp.y).normalized()
	return Vector3.RIGHT


func _build_terrain_side_rings(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	base_ids: PackedInt32Array,
	outer_ids: PackedInt32Array,
	row_count: int,
	subdivisions: int,
	terrain_noise: FastNoiseLite,
	terrain_heightmap_image: Image
) -> Array:
	var rings: Array = []
	rings.resize(subdivisions + 1)
	for ring_i in range(subdivisions + 1):
		var ring: Array = []
		ring.resize(row_count)
		for row_i in range(row_count):
			ring[row_i] = -1
		rings[ring_i] = ring

	for row_i in range(row_count):
		var base_idx := int(base_ids[row_i])
		if base_idx >= 0 and base_idx < verts.size():
			var base_ring: Array = rings[0]
			base_ring[row_i] = base_idx
			rings[0] = base_ring

		var outer_idx := int(outer_ids[row_i])
		if base_idx < 0 or outer_idx < 0:
			continue
		if base_idx >= verts.size() or outer_idx >= verts.size():
			continue

		var base_point: Vector3 = verts[base_idx]
		var outer_point: Vector3 = verts[outer_idx]
		for ring_i in range(1, subdivisions + 1):
			var t := float(ring_i) / float(subdivisions)
			var p := base_point.lerp(outer_point, t)
			p.y = base_point.y + _terrain_noise_offset_y(p, t, terrain_noise, terrain_heightmap_image)
			var ring_idx := outer_idx
			if ring_i < subdivisions:
				ring_idx = verts.size()
				verts.push_back(p)
				normals.push_back(Vector3.UP)
				uvs.push_back(Vector2(p.x, p.z) * uv_length_scale)
			else:
				verts[outer_idx] = p
				normals[outer_idx] = Vector3.UP
				uvs[outer_idx] = Vector2(p.x, p.z) * uv_length_scale
			var ring_ids: Array = rings[ring_i]
			ring_ids[row_i] = ring_idx
			rings[ring_i] = ring_ids
	return rings


func _terrain_noise_offset_y(
	point: Vector3,
	ring_t: float,
	terrain_noise: FastNoiseLite,
	terrain_heightmap_image: Image
) -> float:
	var t := clampf(ring_t, 0.0, 1.0)
	if t <= 0.0001:
		return 0.0
	var total_offset := 0.0

	if terrain_noise != null and terrain_noise_amplitude > 0.0001:
		var falloff := maxf(0.0, terrain_noise_falloff)
		var weight := 1.0 if falloff <= 0.0001 else pow(t, falloff)
		total_offset += terrain_noise.get_noise_2d(point.x, point.z) * terrain_noise_amplitude * weight

	if terrain_heightmap_image != null and absf(terrain_heightmap_amplitude) > 0.0001:
		var h_falloff := maxf(0.0, terrain_heightmap_falloff)
		var h_weight := 1.0 if h_falloff <= 0.0001 else pow(t, h_falloff)
		total_offset += _sample_terrain_heightmap_value(terrain_heightmap_image, point) * terrain_heightmap_amplitude * h_weight

	match terrain_cut_fill_mode:
		TERRAIN_CUT_FILL_CUT_ONLY:
			return minf(total_offset, 0.0)
		TERRAIN_CUT_FILL_FILL_ONLY:
			return maxf(total_offset, 0.0)
	return total_offset


func _build_terrain_noise() -> FastNoiseLite:
	if not terrain_noise_enabled:
		return null
	if terrain_noise_amplitude <= 0.0001:
		return null
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = terrain_noise_seed
	terrain_noise.frequency = terrain_noise_frequency
	return terrain_noise


func _build_terrain_heightmap_image() -> Image:
	if not terrain_heightmap_enabled:
		if terrain_heightmap_invert:
			_debug_log("terrain heightmap invert ignored: Terrain Heightmap CPU is disabled")
		return null
	if terrain_heightmap_texture == null:
		if terrain_heightmap_invert:
			_debug_log("terrain heightmap invert ignored: no heightmap texture assigned")
		return null
	var image := terrain_heightmap_texture.get_image()
	if image == null:
		if terrain_heightmap_invert:
			_debug_log("terrain heightmap invert ignored: heightmap image could not be read")
		return null
	if image.is_empty():
		if terrain_heightmap_invert:
			_debug_log("terrain heightmap invert ignored: heightmap image is empty")
		return null
	if terrain_heightmap_invert and absf(terrain_heightmap_amplitude) <= 0.0001:
		_debug_log("terrain heightmap invert has no visible effect: amplitude is 0")
	return image


func _sample_terrain_heightmap_value(image: Image, point: Vector3) -> float:
	if image == null:
		return 0.0

	var uv := Vector2(point.x, point.z) * terrain_heightmap_uv_scale + terrain_heightmap_uv_offset
	uv.x = fposmod(uv.x, 1.0)
	uv.y = fposmod(uv.y, 1.0)
	var value := _sample_image_red_bilinear(image, uv)
	if terrain_heightmap_invert:
		value = 1.0 - value
	if terrain_heightmap_signed:
		value = value * 2.0 - 1.0
	return value


func _sample_image_red_bilinear(image: Image, uv: Vector2) -> float:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return 0.0
	if width == 1 and height == 1:
		return image.get_pixel(0, 0).r

	var fx := clampf(uv.x, 0.0, 1.0) * float(maxi(1, width - 1))
	var fy := clampf(uv.y, 0.0, 1.0) * float(maxi(1, height - 1))
	var x0 := clampi(int(floor(fx)), 0, width - 1)
	var y0 := clampi(int(floor(fy)), 0, height - 1)
	var x1 := clampi(x0 + 1, 0, width - 1)
	var y1 := clampi(y0 + 1, 0, height - 1)

	var tx := fx - float(x0)
	var ty := fy - float(y0)

	var c00 := image.get_pixel(x0, y0).r
	var c10 := image.get_pixel(x1, y0).r
	var c01 := image.get_pixel(x0, y1).r
	var c11 := image.get_pixel(x1, y1).r

	var a := lerpf(c00, c10, tx)
	var b := lerpf(c01, c11, tx)
	return lerpf(a, b, ty)


func _build_road_tri_xz_cache(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array
) -> Array:
	var out: Array = []
	_append_surface_tri_xz_cache(out, verts, lane_indices)
	_append_surface_tri_xz_cache(out, verts, shoulder_indices)
	_append_surface_tri_xz_cache(out, verts, sidewalk_indices)
	# Extra row envelope is conservative; skip it when clearance is zero
	# to avoid over-rejecting terrain growth in free areas.
	if terrain_road_clearance > 0.0001:
		_append_path_row_road_envelope_tri_xz_cache(out, verts, path_rows)
	return out


func _append_surface_tri_xz_cache(out: Array, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	if indices.is_empty():
		return
	var tri_count := indices.size() - (indices.size() % 3)
	for i in range(0, tri_count, 3):
		var ia := int(indices[i])
		var ib := int(indices[i + 1])
		var ic := int(indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
			continue
		_append_tri_to_xz_cache(out, verts[ia], verts[ib], verts[ic])


func _append_path_row_road_envelope_tri_xz_cache(
	out: Array,
	verts: PackedVector3Array,
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
			var l0 := int(e0[0])
			var r0 := int(e0[5])
			var l1 := int(e1[0])
			var r1 := int(e1[5])
			if l0 < 0 or r0 < 0 or l1 < 0 or r1 < 0:
				continue
			if l0 >= verts.size() or r0 >= verts.size() or l1 >= verts.size() or r1 >= verts.size():
				continue
			_append_tri_to_xz_cache(out, verts[l0], verts[r0], verts[l1])
			_append_tri_to_xz_cache(out, verts[l1], verts[r0], verts[r1])


func _append_tri_to_xz_cache(out: Array, a3: Vector3, b3: Vector3, c3: Vector3) -> void:
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var c := Vector2(c3.x, c3.z)
	var area2 := absf((b - a).cross(c - a))
	if area2 <= 0.0000001:
		return
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	var min_y := minf(a.y, minf(b.y, c.y))
	var max_y := maxf(a.y, maxf(b.y, c.y))
	out.push_back({
		"a": a,
		"b": b,
		"c": c,
		"min": Vector2(min_x, min_y),
		"max": Vector2(max_x, max_y),
	})


func _point_over_any_road_triangle_xz(point: Vector2, road_tris: Array, margin: float) -> bool:
	if road_tris.is_empty():
		return false
	for tri in road_tris:
		var min_v: Vector2 = tri["min"]
		var max_v: Vector2 = tri["max"]
		if point.x < min_v.x - margin or point.x > max_v.x + margin:
			continue
		if point.y < min_v.y - margin or point.y > max_v.y + margin:
			continue
		var a: Vector2 = tri["a"]
		var b: Vector2 = tri["b"]
		var c: Vector2 = tri["c"]
		var poly := PackedVector2Array([a, b, c])
		if Geometry2D.is_point_in_polygon(point, poly):
			return true
		if margin > 0.000001:
			var d0 := Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)
			if d0 <= margin:
				return true
			var d1 := Geometry2D.get_closest_point_to_segment(point, b, c).distance_to(point)
			if d1 <= margin:
				return true
			var d2 := Geometry2D.get_closest_point_to_segment(point, c, a).distance_to(point)
			if d2 <= margin:
				return true
	return false


func _segment_over_any_road_triangle_xz(a: Vector2, b: Vector2, road_tris: Array, margin: float = 0.0) -> bool:
	if road_tris.is_empty():
		return false
	var seg_min := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var seg_max := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var seg_mid := (a + b) * 0.5
	for tri in road_tris:
		var min_v: Vector2 = tri["min"]
		var max_v: Vector2 = tri["max"]
		if seg_max.x < min_v.x - margin or seg_min.x > max_v.x + margin:
			continue
		if seg_max.y < min_v.y - margin or seg_min.y > max_v.y + margin:
			continue
		var ta: Vector2 = tri["a"]
		var tb: Vector2 = tri["b"]
		var tc: Vector2 = tri["c"]
		var tri_poly := PackedVector2Array([ta, tb, tc])
		if Geometry2D.is_point_in_polygon(a, tri_poly):
			return true
		if Geometry2D.is_point_in_polygon(b, tri_poly):
			return true
		if Geometry2D.is_point_in_polygon(seg_mid, tri_poly):
			return true
		if _segments_intersect_2d_strict(a, b, ta, tb):
			return true
		if _segments_intersect_2d_strict(a, b, tb, tc):
			return true
		if _segments_intersect_2d_strict(a, b, tc, ta):
			return true
		if margin > 0.000001:
			if _segment_distance_2d(a, b, ta, tb) <= margin:
				return true
			if _segment_distance_2d(a, b, tb, tc) <= margin:
				return true
			if _segment_distance_2d(a, b, tc, ta) <= margin:
				return true
	return false


func _segment_distance_2d(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if hit != null:
		return 0.0
	var d0 := _distance_point_to_segment_2d(a0, b0, b1)
	var d1 := _distance_point_to_segment_2d(a1, b0, b1)
	var d2 := _distance_point_to_segment_2d(b0, a0, a1)
	var d3 := _distance_point_to_segment_2d(b1, a0, a1)
	return minf(minf(d0, d1), minf(d2, d3))


func _distance_point_to_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)


func _segments_intersect_2d_strict(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if hit == null:
		return false
	if typeof(hit) != TYPE_VECTOR2:
		return false
	var hp: Vector2 = hit
	if hp.distance_to(a0) <= 0.000001:
		return false
	if hp.distance_to(a1) <= 0.000001:
		return false
	if hp.distance_to(b0) <= 0.000001:
		return false
	if hp.distance_to(b1) <= 0.000001:
		return false
	return true


func _limit_terrain_growth_width_for_segment(
	verts: PackedVector3Array,
	base_point: Vector3,
	out_dir: Vector3,
	requested_width: float,
	prev_idx: int,
	curr_idx: int,
	outer_points: Array[Vector3],
	outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	road_tris: Array
) -> float:
	var width := maxf(0.0, requested_width)
	if width <= 0.0001:
		return 0.0
	if prev_idx < 0 or prev_idx >= outer_points.size():
		return width
	if curr_idx <= prev_idx:
		return width
	var prev_outer := outer_points[prev_idx]
	var scan_step := maxf(0.05, terrain_growth_scan_step)
	var probe_steps := maxi(2, mini(24, int(ceil(width / scan_step))))
	var step_len := width / float(probe_steps)
	var best := 0.0

	# Probe progressively and keep the furthest valid width.
	for probe_i in range(1, probe_steps + 1):
		var probe_w := step_len * float(probe_i)
		var probe_point := base_point + out_dir * probe_w
		if _is_terrain_growth_segment_valid(
			verts,
			prev_outer,
			probe_point,
			prev_idx,
			curr_idx,
			outer_points,
			outer_ids,
			base_ids,
			opposite_ids,
			road_tris
		):
			best = probe_w

	if best <= 0.0001:
		return 0.0
	if best >= width - 0.0001:
		return width

	var low := best
	var high := minf(width, best + step_len)
	while high < width:
		var high_point := base_point + out_dir * high
		if _is_terrain_growth_segment_valid(
			verts,
			prev_outer,
			high_point,
			prev_idx,
			curr_idx,
			outer_points,
			outer_ids,
			base_ids,
			opposite_ids,
			road_tris
		):
			low = high
			high = minf(width, high + step_len)
			continue
		break

	if low >= width - 0.0001:
		return width
	for _iter in range(8):
		var mid := (low + high) * 0.5
		var p_mid := base_point + out_dir * mid
		if _is_terrain_growth_segment_valid(
			verts,
			prev_outer,
			p_mid,
			prev_idx,
			curr_idx,
			outer_points,
			outer_ids,
			base_ids,
			opposite_ids,
			road_tris
		):
			low = mid
		else:
			high = mid
	return low if low > 0.0001 else 0.0


func _is_terrain_growth_segment_valid(
	verts: PackedVector3Array,
	seg_a: Vector3,
	seg_b: Vector3,
	prev_idx: int,
	curr_idx: int,
	outer_points: Array[Vector3],
	outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	road_tris: Array
) -> bool:
	# Keep detection on/inside the actual candidate extent.
	# Values > 1.0 can overreach and create false positives that stop terrain growth.
	var detection_width_scale := clampf(terrain_detection_width_scale, 0.1, 1.0)
	var base_prev_idx := int(base_ids[prev_idx]) if prev_idx >= 0 and prev_idx < base_ids.size() else -1
	var base_curr_idx := int(base_ids[curr_idx]) if curr_idx >= 0 and curr_idx < base_ids.size() else -1
	var detect_a := seg_a
	var detect_b := seg_b
	if base_prev_idx >= 0 and base_prev_idx < verts.size():
		var base_prev := verts[base_prev_idx]
		detect_a = base_prev + (seg_a - base_prev) * detection_width_scale
	if base_curr_idx >= 0 and base_curr_idx < verts.size():
		var base_curr := verts[base_curr_idx]
		detect_b = base_curr + (seg_b - base_curr) * detection_width_scale

	for k in range(curr_idx - 1):
		if k + 1 >= base_ids.size():
			break
		if k >= prev_idx - 1 and k <= curr_idx:
			continue
		var rb0 := int(base_ids[k])
		var rb1 := int(base_ids[k + 1])
		if rb0 < 0 or rb1 < 0:
			continue
		if rb0 >= verts.size() or rb1 >= verts.size():
			continue
		if _segments_intersect_xz(verts[rb0], verts[rb1], detect_a, detect_b):
			return false

	for k in range(curr_idx - 1):
		if k + 1 >= opposite_ids.size():
			break
		if k >= prev_idx - 1 and k <= curr_idx:
			continue
		var ro0 := int(opposite_ids[k])
		var ro1 := int(opposite_ids[k + 1])
		if ro0 < 0 or ro1 < 0:
			continue
		if ro0 >= verts.size() or ro1 >= verts.size():
			continue
		if _segments_intersect_xz(verts[ro0], verts[ro1], detect_a, detect_b):
			return false

	var seg_mid := (detect_a + detect_b) * 0.5
	var seg_q1 := detect_a.lerp(detect_b, 0.25)
	var seg_q3 := detect_a.lerp(detect_b, 0.75)
	var p_end := Vector2(detect_b.x, detect_b.z)
	var p_q1 := Vector2(seg_q1.x, seg_q1.z)
	var p_mid := Vector2(seg_mid.x, seg_mid.z)
	var p_q3 := Vector2(seg_q3.x, seg_q3.z)
	var p_a := Vector2(detect_a.x, detect_a.z)
	var road_clearance := maxf(0.0, terrain_road_clearance)
	if _point_over_any_road_triangle_xz(p_end, road_tris, road_clearance):
		return false
	if _point_over_any_road_triangle_xz(p_q1, road_tris, road_clearance):
		return false
	if _point_over_any_road_triangle_xz(p_mid, road_tris, road_clearance):
		return false
	if _point_over_any_road_triangle_xz(p_q3, road_tris, road_clearance):
		return false
	if _segment_over_any_road_triangle_xz(p_a, p_end, road_tris, road_clearance):
		return false
	if base_prev_idx >= 0 and base_curr_idx >= 0 and base_prev_idx < verts.size() and base_curr_idx < verts.size():
		if _terrain_quad_over_any_road_triangle_xz(
			verts[base_prev_idx],
			verts[base_curr_idx],
			detect_a,
			detect_b,
			road_tris,
			0.0
		):
			return false
	if _is_point_over_road_cross_xz(verts, detect_b, base_ids, opposite_ids, curr_idx):
		return false
	if _is_point_over_road_cross_xz(verts, seg_mid, base_ids, opposite_ids, curr_idx):
		return false

	return true


func _terrain_quad_over_any_road_triangle_xz(
	base_prev: Vector3,
	base_curr: Vector3,
	outer_prev: Vector3,
	outer_curr: Vector3,
	road_tris: Array,
	margin: float
) -> bool:
	if road_tris.is_empty():
		return false
	var prev_out := outer_prev - base_prev
	prev_out.y = 0.0
	var curr_out := outer_curr - base_curr
	curr_out.y = 0.0
	if prev_out.length() <= 0.0001 or curr_out.length() <= 0.0001:
		return false

	# Keep a tiny outward inset to avoid rejecting quads that only touch the road edge.
	# Clearance is handled by point/segment distance checks before this function.
	var edge_inset := 0.001
	var base_prev_p := Vector2(base_prev.x, base_prev.z) + Vector2(prev_out.x, prev_out.z).normalized() * edge_inset
	var base_curr_p := Vector2(base_curr.x, base_curr.z) + Vector2(curr_out.x, curr_out.z).normalized() * edge_inset
	var outer_curr_p := Vector2(outer_curr.x, outer_curr.z)
	var outer_prev_p := Vector2(outer_prev.x, outer_prev.z)
	var quad := PackedVector2Array([base_prev_p, base_curr_p, outer_curr_p, outer_prev_p])

	var q_min := Vector2(
		minf(base_prev_p.x, minf(base_curr_p.x, minf(outer_curr_p.x, outer_prev_p.x))),
		minf(base_prev_p.y, minf(base_curr_p.y, minf(outer_curr_p.y, outer_prev_p.y)))
	)
	var q_max := Vector2(
		maxf(base_prev_p.x, maxf(base_curr_p.x, maxf(outer_curr_p.x, outer_prev_p.x))),
		maxf(base_prev_p.y, maxf(base_curr_p.y, maxf(outer_curr_p.y, outer_prev_p.y)))
	)
	for tri in road_tris:
		var min_v: Vector2 = tri["min"]
		var max_v: Vector2 = tri["max"]
		if q_max.x < min_v.x - margin or q_min.x > max_v.x + margin:
			continue
		if q_max.y < min_v.y - margin or q_min.y > max_v.y + margin:
			continue
		var tri_poly := PackedVector2Array([tri["a"], tri["b"], tri["c"]])
		if _polygon_intersects_triangle_xz(quad, tri_poly):
			return true
	return false


func _polygon_intersects_triangle_xz(poly: PackedVector2Array, tri: PackedVector2Array) -> bool:
	for p in poly:
		if Geometry2D.is_point_in_polygon(p, tri):
			return true
	for t in tri:
		if Geometry2D.is_point_in_polygon(t, poly):
			return true
	for i in range(poly.size()):
		var a0 := poly[i]
		var a1 := poly[(i + 1) % poly.size()]
		for j in range(tri.size()):
			var b0 := tri[j]
			var b1 := tri[(j + 1) % tri.size()]
			var hit = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
			if hit != null:
				return true
	return false


func _is_point_over_road_cross_xz(
	verts: PackedVector3Array,
	point: Vector3,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	row_idx: int
) -> bool:
	if row_idx < 0 or row_idx >= base_ids.size() or row_idx >= opposite_ids.size():
		return false
	var b := int(base_ids[row_idx])
	var o := int(opposite_ids[row_idx])
	if b < 0 or o < 0:
		return false
	if b >= verts.size() or o >= verts.size():
		return false

	var base := verts[b]
	var opp := verts[o]
	var across := Vector2(opp.x - base.x, opp.z - base.z)
	var across_len := across.length()
	if across_len <= 0.0001:
		return false
	var across_n := across / across_len
	var rel := Vector2(point.x - base.x, point.z - base.z)
	var proj := rel.dot(across_n)
	# proj > 0 means candidate moved towards/over road interior.
	return proj > 0.01


func _segments_intersect_xz(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> bool:
	var p0 := Vector2(a0.x, a0.z)
	var p1 := Vector2(a1.x, a1.z)
	var q0 := Vector2(b0.x, b0.z)
	var q1 := Vector2(b1.x, b1.z)
	var hit = Geometry2D.segment_intersects_segment(p0, p1, q0, q1)
	if hit == null:
		return false
	if typeof(hit) != TYPE_VECTOR2:
		return false
	var hp: Vector2 = hit
	if hp.distance_to(p0) <= 0.0001:
		return false
	if hp.distance_to(p1) <= 0.0001:
		return false
	if hp.distance_to(q0) <= 0.0001:
		return false
	if hp.distance_to(q1) <= 0.0001:
		return false
	return true


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
	_add_surface(mesh, verts, normals, uvs, lane_indices, road_material_override if road_material_override != null else material_override)
	_add_surface(mesh, verts, normals, uvs, shoulder_indices, shoulder_material_override if shoulder_material_override != null else material_override)
	_add_surface(mesh, verts, normals, uvs, sidewalk_indices, sidewalk_material_override if sidewalk_material_override != null else material_override)
	_add_surface(
		mesh,
		verts,
		normals,
		uvs,
		terrain_indices,
		terrain_material_override if terrain_material_override != null else (sidewalk_material_override if sidewalk_material_override != null else material_override)
	)
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
	var surface_normals := _compute_surface_normals_from_indices(verts, indices, normals)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = surface_normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mat != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _compute_surface_normals_from_indices(
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


func _compute_row_out_dir(row_centers: Array[Vector3], idx: int) -> Vector3:
	if row_centers.size() < 2:
		return Vector3.FORWARD
	if idx <= 0:
		return (row_centers[1] - row_centers[0]).normalized()
	if idx >= row_centers.size() - 1:
		return (row_centers[row_centers.size() - 2] - row_centers[row_centers.size() - 1]).normalized()
	return (row_centers[idx + 1] - row_centers[idx - 1]).normalized()


func _add_socket_unique(sockets: Array[Dictionary], keys: Dictionary, row: Dictionary, is_endpoint: bool) -> void:
	var key := str(row["path_id"]) + ":" + str(row["row_idx"])
	if keys.has(key):
		return
	keys[key] = true

	var s := row.duplicate(true)
	s["is_endpoint"] = is_endpoint
	sockets.push_back(s)


func _augment_with_midpath_sockets(
	sockets: Array[Dictionary],
	keys: Dictionary,
	path_rows: Array,
	endpoint_count: int,
	path_weld_allow_midpath: Array,
	path_weld_snap: Array
) -> void:
	for i in range(endpoint_count):
		var ep: Dictionary = sockets[i]
		var ep_path_id: int = int(ep.get("path_id", -1))
		if not _is_path_allow_midpath(ep_path_id, path_weld_allow_midpath):
			continue
		var ep_pos: Vector3 = Vector3(ep.get("position", Vector3.ZERO))

		for path_id in range(path_rows.size()):
			if path_id == ep_path_id:
				continue
			if not _is_path_allow_midpath(path_id, path_weld_allow_midpath):
				continue
			var rows: Array[Dictionary] = path_rows[path_id]
			if rows.size() < 3:
				continue

			var pair_snap: float = maxf(
				_resolve_path_snap_for_id(ep_path_id, path_weld_snap),
				_resolve_path_snap_for_id(path_id, path_weld_snap)
			)
			var nearest_idx := _find_nearest_inner_row(rows, ep_pos, pair_snap)
			if nearest_idx < 0:
				continue

			_add_socket_unique(sockets, keys, rows[nearest_idx], false)


func _augment_with_midpath_pair_sockets(
	sockets: Array[Dictionary],
	keys: Dictionary,
	path_rows: Array,
	path_weld_allow_midpath: Array,
	path_weld_snap: Array
) -> void:
	for path_a in range(path_rows.size()):
		if not _is_path_allow_midpath(path_a, path_weld_allow_midpath):
			continue
		var rows_a: Array[Dictionary] = path_rows[path_a]
		if rows_a.size() < 3:
			continue

		for path_b in range(path_a + 1, path_rows.size()):
			if not _is_path_allow_midpath(path_b, path_weld_allow_midpath):
				continue
			var rows_b: Array[Dictionary] = path_rows[path_b]
			if rows_b.size() < 3:
				continue

			var pair_snap: float = maxf(
				_resolve_path_snap_for_id(path_a, path_weld_snap),
				_resolve_path_snap_for_id(path_b, path_weld_snap)
			)
			var pair_rows := _find_nearest_inner_row_pair(rows_a, rows_b, pair_snap * 2.5)
			if pair_rows.size() < 2:
				continue

			var a_idx := int(pair_rows[0])
			var b_idx := int(pair_rows[1])
			if a_idx <= 0 or a_idx >= rows_a.size() - 1:
				continue
			if b_idx <= 0 or b_idx >= rows_b.size() - 1:
				continue

			_add_socket_unique(sockets, keys, rows_a[a_idx], false)
			_add_socket_unique(sockets, keys, rows_b[b_idx], false)


func _find_nearest_inner_row(rows: Array[Dictionary], point: Vector3, max_distance: float) -> int:
	if rows.size() < 3:
		return -1

	var best := -1
	var best_dist := max_distance
	for i in range(1, rows.size() - 1):
		var p: Vector3 = Vector3(rows[i].get("position", Vector3.ZERO))
		var d := p.distance_to(point)
		if d <= best_dist:
			best_dist = d
			best = i
	return best


func _find_nearest_inner_row_pair(
	rows_a: Array[Dictionary],
	rows_b: Array[Dictionary],
	max_distance: float
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if rows_a.size() < 3 or rows_b.size() < 3:
		return out

	var best_a := -1
	var best_b := -1
	var best_dist := max_distance

	for i in range(1, rows_a.size() - 1):
		var pa: Vector3 = rows_a[i].get("position", Vector3.ZERO)
		for j in range(1, rows_b.size() - 1):
			var pb: Vector3 = rows_b[j].get("position", Vector3.ZERO)
			var d := pa.distance_to(pb)
			if d > best_dist:
				continue
			best_dist = d
			best_a = i
			best_b = j

	if best_a >= 0 and best_b >= 0:
		out.push_back(best_a)
		out.push_back(best_b)
	return out


func _build_open_distances(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := 0.0
	while d < length:
		out.push_back(d)
		d += sample_step
	out.push_back(length)
	if out.size() < 2:
		out = PackedFloat32Array([0.0, length])
	return out


func _build_open_distances_with_step(length: float, local_step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := maxf(local_step, 0.01)
	var d := 0.0
	while d < length:
		out.push_back(d)
		d += step
	out.push_back(length)
	if out.size() < 2:
		out = PackedFloat32Array([0.0, length])
	return out


func _compute_adaptive_local_step(path_adaptive_step_scale: float) -> float:
	var base_step: float = maxf(0.02, sample_step)
	var scale: float = maxf(0.1, path_adaptive_step_scale)
	return maxf(0.02, base_step * scale)


func _compute_adaptive_local_radius(
	local_step: float,
	path_adaptive_radius_scale: float
) -> float:
	# Keep the refinement/coarsening window tight around the anchor:
	# enough for one adjacent pair ("2 vertices"), not a wide area.
	var radius_scale: float = maxf(0.1, path_adaptive_radius_scale)
	return maxf(0.01, local_step * radius_scale)


func _apply_adaptive_anchor_offset(
	anchors: PackedFloat32Array,
	length: float,
	path_adaptive_advanced: bool,
	path_adaptive_offset: float
) -> PackedFloat32Array:
	if not path_adaptive_advanced:
		return anchors
	if is_zero_approx(path_adaptive_offset):
		return anchors

	var out := PackedFloat32Array()
	for a in anchors:
		out.push_back(clampf(a + path_adaptive_offset, 0.0, length))
	return out


func _build_open_distances_with_anchors(
	length: float,
	anchors: PackedFloat32Array,
	local_step: float,
	local_radius: float
) -> PackedFloat32Array:
	if anchors.is_empty() or local_radius <= 0.0:
		return _build_open_distances(length)

	var split_points: Array[float] = [0.0, length]
	for anchor in anchors:
		var a0: float = clamp(anchor - local_radius, 0.0, length)
		var a1: float = clamp(anchor + local_radius, 0.0, length)
		split_points.push_back(a0)
		split_points.push_back(a1)

	split_points.sort()
	var unique_points: Array[float] = []
	for p in split_points:
		if unique_points.is_empty() or absf(unique_points[unique_points.size() - 1] - p) > 0.001:
			unique_points.push_back(p)

	var out := PackedFloat32Array()
	for i in range(unique_points.size() - 1):
		var seg_start: float = unique_points[i]
		var seg_end: float = unique_points[i + 1]
		if seg_end - seg_start <= 0.0001:
			continue

		var seg_mid := (seg_start + seg_end) * 0.5
		var use_local := false
		for anchor in anchors:
			if absf(seg_mid - anchor) <= local_radius:
				use_local = true
				break

		var step := sample_step
		if use_local:
			step = local_step
		step = max(step, 0.01)

		if out.is_empty() or absf(out[out.size() - 1] - seg_start) > 0.001:
			out.push_back(seg_start)

		var d := seg_start + step
		while d < seg_end - 0.001:
			out.push_back(d)
			d += step

	if out.is_empty() or absf(out[out.size() - 1] - length) > 0.001:
		out.push_back(length)

	if out.size() < 2:
		return _build_open_distances(length)
	return out


func _collect_path_endpoints(paths: Array[Path3D], inv_global: Transform3D) -> Array:
	var out: Array = []
	out.resize(paths.size())
	for path_idx in range(paths.size()):
		var points: Array[Vector3] = []
		var path := paths[path_idx]
		if path == null or path.curve == null or path.curve.point_count < 2:
			out[path_idx] = points
			continue

		var curve := path.curve
		curve.bake_interval = max(sample_step, 0.01)
		var length := curve.get_baked_length()
		if length <= 0.0:
			out[path_idx] = points
			continue

		var path_to_mesh := inv_global * path.global_transform
		points.push_back(path_to_mesh * curve.sample_baked(0.0, true))
		points.push_back(path_to_mesh * curve.sample_baked(length, true))
		out[path_idx] = points

	return out


func _collect_adaptive_anchor_offsets(
	path_idx: int,
	curve: Curve3D,
	path_to_mesh: Transform3D,
	endpoint_positions_by_path: Array,
	max_snap_distance: float
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if curve == null or curve.point_count < 2:
		return out

	var mesh_to_path := path_to_mesh.affine_inverse()
	var max_snap_sq := max_snap_distance * max_snap_distance

	for other_idx in range(endpoint_positions_by_path.size()):
		if other_idx == path_idx:
			continue
		var points: Array = endpoint_positions_by_path[other_idx]
		for p in points:
			var endpoint_mesh: Vector3 = p
			var endpoint_path := mesh_to_path * endpoint_mesh
			var offset := 0.0
			if curve.has_method("get_closest_offset"):
				offset = curve.get_closest_offset(endpoint_path)
			else:
				offset = _approx_closest_offset(curve, endpoint_path, max(0.05, sample_step))
			var closest_mesh := path_to_mesh * curve.sample_baked(offset, true)
			var delta_xz := Vector2(closest_mesh.x - endpoint_mesh.x, closest_mesh.z - endpoint_mesh.z)
			if delta_xz.length_squared() <= max_snap_sq:
				out.push_back(offset)

	if out.is_empty():
		return out

	var sorted_offsets: Array[float] = []
	for off in out:
		sorted_offsets.push_back(off)
	sorted_offsets.sort()

	var unique := PackedFloat32Array()
	for off in sorted_offsets:
		if unique.is_empty() or absf(unique[unique.size() - 1] - off) > 0.001:
			unique.push_back(off)
	return unique


func _approx_closest_offset(curve: Curve3D, point: Vector3, step: float) -> float:
	var length := curve.get_baked_length()
	if length <= 0.0:
		return 0.0

	var d := 0.0
	var best_off := 0.0
	var best_dist := INF
	var s: float = max(step, 0.01)
	while d <= length:
		var p := curve.sample_baked(d, true)
		var dist := p.distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best_off = d
		d += s

	if best_off != length:
		var p_end := curve.sample_baked(length, true)
		var end_dist := p_end.distance_squared_to(point)
		if end_dist < best_dist:
			best_off = length

	return best_off


func _cluster_sockets(
	sockets: Array[Dictionary],
	min_paths: int,
	path_weld_snap: Array,
	snap_scale: float = 1.0
) -> Array:
	var clusters: Array = []
	var used: Dictionary = {}
	var scale := maxf(0.01, snap_scale)

	for i in range(sockets.size()):
		if used.has(i):
			continue

		var cluster: Array = [i]
		used[i] = true
		var changed := true
		while changed:
			changed = false
			for j in range(sockets.size()):
				if used.has(j):
					continue
				for idx in cluster:
					var a: Vector3 = sockets[idx]["position"]
					var b: Vector3 = sockets[j]["position"]
					var pair_snap := _resolve_socket_pair_snap_distance(sockets[idx], sockets[j], path_weld_snap)
					if a.distance_to(b) <= pair_snap * scale:
						cluster.push_back(j)
						used[j] = true
						changed = true
						break

		var path_set: Dictionary = {}
		for idx in cluster:
			path_set[sockets[idx]["path_id"]] = true
		if path_set.size() >= min_paths:
			clusters.push_back(cluster)

	return clusters


func _resolve_socket_pair_snap_distance(socket_a: Dictionary, socket_b: Dictionary, path_weld_snap: Array) -> float:
	var path_a := int(socket_a.get("path_id", -1))
	var path_b := int(socket_b.get("path_id", -1))
	var snap_a := float(socket_a.get("weld_snap_distance", _resolve_path_snap_for_id(path_a, path_weld_snap)))
	var snap_b := float(socket_b.get("weld_snap_distance", _resolve_path_snap_for_id(path_b, path_weld_snap)))
	return maxf(0.1, maxf(snap_a, snap_b))


func _path_has_weld_overrides(path: Path3D) -> bool:
	if path == null:
		return false
	if path.has_method("has_intersection_overrides"):
		return bool(path.call("has_intersection_overrides"))
	if path.has_method("has_weld_overrides"):
		return bool(path.call("has_weld_overrides"))
	return false


func _resolve_path_weld_endpoint_snap_distance(path: Path3D) -> float:
	var value := endpoint_snap_distance
	if _path_has_weld_overrides(path) and path.has_method("get_weld_endpoint_snap_distance"):
		value = float(path.call("get_weld_endpoint_snap_distance"))
	return maxf(0.1, value)


func _resolve_path_weld_allow_endpoint_to_midpath(path: Path3D) -> bool:
	if _path_has_weld_overrides(path) and path.has_method("get_weld_allow_endpoint_to_midpath"):
		return bool(path.call("get_weld_allow_endpoint_to_midpath"))
	return allow_endpoint_to_midpath


func _resolve_path_weld_strip_shoulder_sidewalk(path: Path3D) -> bool:
	if _path_has_weld_overrides(path) and path.has_method("get_weld_strip_shoulder_sidewalk_at_intersections"):
		return bool(path.call("get_weld_strip_shoulder_sidewalk_at_intersections"))
	return strip_shoulder_sidewalk_at_intersections


func _resolve_path_weld_intersection_strip_length(path: Path3D) -> float:
	var value := intersection_strip_length
	if _path_has_weld_overrides(path) and path.has_method("get_weld_intersection_strip_length"):
		value = float(path.call("get_weld_intersection_strip_length"))
	return maxf(0.0, value)


func _path_has_adaptive_sampling_overrides(path: Path3D) -> bool:
	if path == null:
		return false
	if path.has_method("has_intersection_overrides"):
		return bool(path.call("has_intersection_overrides"))
	if path.has_method("has_adaptive_sampling_overrides"):
		return bool(path.call("has_adaptive_sampling_overrides"))
	return false


func _resolve_path_adaptive_sampling_enabled(path: Path3D) -> bool:
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_enabled"):
		return bool(path.call("get_adaptive_sampling_enabled"))
	return adaptive_sampling_enabled


func _resolve_path_adaptive_sampling_advanced(path: Path3D) -> bool:
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_advanced"):
		return bool(path.call("get_adaptive_sampling_advanced")) or adaptive_sampling_advanced
	return adaptive_sampling_advanced


func _resolve_path_adaptive_sampling_step_scale(path: Path3D) -> float:
	var value: float = adaptive_sampling_step_scale
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_step_scale"):
		value = float(path.call("get_adaptive_sampling_step_scale"))
	return maxf(0.1, value)


func _resolve_path_adaptive_sampling_radius_scale(path: Path3D) -> float:
	var value: float = adaptive_sampling_radius_scale
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_radius_scale"):
		value = float(path.call("get_adaptive_sampling_radius_scale"))
	return maxf(0.1, value)


func _resolve_path_adaptive_sampling_offset(path: Path3D) -> float:
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_offset"):
		return float(path.call("get_adaptive_sampling_offset"))
	return adaptive_sampling_offset


func _resolve_path_snap_for_id(path_id: int, path_weld_snap: Array) -> float:
	if path_id >= 0 and path_id < path_weld_snap.size():
		return maxf(0.1, float(path_weld_snap[path_id]))
	return maxf(0.1, endpoint_snap_distance)


func _is_path_allow_midpath(path_id: int, path_weld_allow_midpath: Array) -> bool:
	if path_id >= 0 and path_id < path_weld_allow_midpath.size():
		return bool(path_weld_allow_midpath[path_id])
	return allow_endpoint_to_midpath


func _is_path_strip_enabled(path_id: int, path_weld_strip_enabled: Array) -> bool:
	if path_id >= 0 and path_id < path_weld_strip_enabled.size():
		return bool(path_weld_strip_enabled[path_id])
	return strip_shoulder_sidewalk_at_intersections


func _resolve_path_strip_length(path_id: int, _path_weld_snap: Array, path_weld_strip_length: Array) -> float:
	if path_id >= 0 and path_id < path_weld_strip_length.size():
		return maxf(0.0, float(path_weld_strip_length[path_id]))
	return maxf(0.0, intersection_strip_length)


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


func _resolve_path_terrain_left(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_terrain_widths(path, dist, length).x


func _resolve_path_terrain_right(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_terrain_widths(path, dist, length).y


func _resolve_path_terrain_widths(path: Path3D, dist: float, length: float) -> Vector2:
	var fallback := Vector2(maxf(0.0, terrain_left_width), maxf(0.0, terrain_right_width))
	if path == null:
		return fallback
	if path.has_method("has_terrain_overrides"):
		if not bool(path.call("has_terrain_overrides")):
			return fallback

	if path.has_method("get_terrain_widths_at_offset"):
		return _coerce_terrain_width_pair(path.call("get_terrain_widths_at_offset", dist), fallback)

	if path.has_method("get_terrain_widths_at_ratio"):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		return _coerce_terrain_width_pair(path.call("get_terrain_widths_at_ratio", ratio), fallback)

	var left := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_terrain_left_at_offset",
		"get_terrain_left_at_ratio",
		fallback.x
	)
	var right := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_terrain_right_at_offset",
		"get_terrain_right_at_ratio",
		fallback.y
	)
	return Vector2(left, right)


func _coerce_terrain_width_pair(raw_value: Variant, fallback: Vector2) -> Vector2:
	var left := fallback.x
	var right := fallback.y
	if raw_value is Vector2:
		var pair: Vector2 = raw_value
		left = pair.x
		right = pair.y
	elif raw_value is Array:
		var array_values: Array = raw_value
		if array_values.size() >= 1:
			left = float(array_values[0])
		if array_values.size() >= 2:
			right = float(array_values[1])
	elif raw_value is PackedFloat32Array:
		var packed_values: PackedFloat32Array = raw_value
		if packed_values.size() >= 1:
			left = packed_values[0]
		if packed_values.size() >= 2:
			right = packed_values[1]
	elif raw_value is Dictionary:
		var dict_values: Dictionary = raw_value
		left = float(dict_values.get("left", dict_values.get("x", left)))
		right = float(dict_values.get("right", dict_values.get("y", right)))
	return Vector2(maxf(0.0, left), maxf(0.0, right))


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


func _sample_curve_up_vector(curve: Curve3D, dist: float) -> Vector3:
	if curve != null and curve.has_method("sample_baked_up_vector"):
		var up: Vector3 = curve.sample_baked_up_vector(dist, true)
		if up.length() > 0.001:
			return up.normalized()
	return Vector3.UP


func _resolve_paths() -> Array[Path3D]:
	var out: Array[Path3D] = []
	var seen: Dictionary = {}
	for np in source_paths:
		if np == NodePath():
			continue
		var n := get_node_or_null(np)
		if n is Path3D:
			_push_unique_path(out, seen, n)

	if out.is_empty():
		for child in get_children():
			if child is Path3D:
				_push_unique_path(out, seen, child)

	if out.is_empty():
		var parent := get_parent()
		if parent != null:
			for sibling in parent.get_children():
				if sibling is Path3D:
					_push_unique_path(out, seen, sibling)

	return out


func _push_unique_path(out: Array[Path3D], seen: Dictionary, path: Path3D) -> void:
	if path == null:
		return
	var key := str(path.get_instance_id())
	if seen.has(key):
		return
	seen[key] = true
	out.push_back(path)


func _cleanup_legacy_generated_children() -> void:
	for child in get_children():
		if not (child is MeshInstance3D):
			continue
		if not child.name.begins_with("GeneratedSpline"):
			continue
		if child.name == MESH_NODE_NAME or child.name == LEGACY_MESH_NODE_NAME:
			continue
		child.queue_free()


func _assign_mesh(mesh: ArrayMesh) -> void:
	_debug_log("_assign_mesh called: surfaces=%s children_before=%s" % [mesh.get_surface_count(), get_child_count()])
	var mi := get_node_or_null(MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		mi = get_node_or_null(LEGACY_MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		_debug_log("creating MeshInstance3D node: " + MESH_NODE_NAME)
		mi = MeshInstance3D.new()
		mi.name = MESH_NODE_NAME
		add_child(mi)
		_debug_log("add_child done, children_after=%s" % [get_child_count()])
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
			_debug_log("owner set to edited scene root: " + str(mi.owner))
	mi.mesh = mesh
	_debug_log("mesh assigned to node: " + str(mi.name))
	var has_per_band_materials := (
		road_material_override != null
		or shoulder_material_override != null
		or sidewalk_material_override != null
		or terrain_material_override != null
		or outer_wall_material_override != null
	)
	mi.material_override = null if has_per_band_materials else material_override
	_debug_log("material_override set (per_band=%s)" % [has_per_band_materials])


func _clear_mesh_node() -> void:
	var mi := get_node_or_null(MESH_NODE_NAME)
	if mi != null:
		_debug_log("clearing node: " + MESH_NODE_NAME)
		mi.queue_free()
	var legacy := get_node_or_null(LEGACY_MESH_NODE_NAME)
	if legacy != null:
		_debug_log("clearing legacy node: " + LEGACY_MESH_NODE_NAME)
		legacy.queue_free()


func _build_signature() -> String:
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
	parts.append(str(terrain_left_width))
	parts.append(str(terrain_right_width))
	parts.append(str(terrain_road_clearance))
	parts.append(str(terrain_detection_width_scale))
	parts.append(str(terrain_growth_scan_step))
	parts.append(str(terrain_growth_max_delta_per_row))
	parts.append(str(terrain_skirt_depth))
	parts.append(str(terrain_skirt_segments))
	parts.append(str(terrain_skirt_outward))
	parts.append(str(terrain_skirt_profile))
	parts.append(str(terrain_skirt_soften_slope_deg))
	parts.append(str(terrain_skirt_soften_max_drop))
	parts.append(str(terrain_skirt_soften_power))
	parts.append(str(terrain_skirt_soften_area_rings))
	parts.append(str(terrain_skirt_soften_area_falloff))
	parts.append(str(terrain_skirt_soften_row_smooth_passes))
	parts.append(str(terrain_subdivisions))
	parts.append(str(terrain_adaptive_subdivisions_enabled))
	parts.append(str(terrain_adaptive_subdivisions_per_meter))
	parts.append(str(terrain_adaptive_noise_quality))
	parts.append(str(terrain_adaptive_subdivisions_max))
	parts.append(str(terrain_noise_enabled))
	parts.append(str(terrain_noise_amplitude))
	parts.append(str(terrain_noise_frequency))
	parts.append(str(terrain_noise_seed))
	parts.append(str(terrain_noise_falloff))
	parts.append(str(terrain_heightmap_enabled))
	parts.append(str(terrain_heightmap_texture))
	parts.append(str(terrain_heightmap_amplitude))
	parts.append(str(terrain_heightmap_signed))
	parts.append(str(terrain_heightmap_invert))
	parts.append(str(terrain_heightmap_uv_scale))
	parts.append(str(terrain_heightmap_uv_offset))
	parts.append(str(terrain_heightmap_falloff))
	parts.append(str(terrain_cut_fill_mode))
	parts.append(str(terrain_artifact_safe_stitch))
	parts.append(str(terrain_chain_smooth_passes))
	parts.append(str(terrain_boolean_fill_enabled))
	parts.append(str(terrain_boolean_padding))
	parts.append(str(terrain_boolean_base_height))
	parts.append(str(terrain_boolean_height_match_epsilon))
	parts.append(str(terrain_boolean_height_match_max_distance))
	parts.append(str(terrain_boolean_solver_mode))
	parts.append(str(terrain_boolean_clip_width_mode))
	parts.append(str(terrain_rect_fill_enabled))
	parts.append(str(terrain_rect_fill_cell_size))
	parts.append(str(terrain_rect_fill_max_cells))
	parts.append(str(terrain_rect_fill_padding))
	parts.append(str(terrain_rect_fill_base_height))
	parts.append(str(terrain_rect_fill_height_match_epsilon))
	parts.append(str(terrain_rect_fill_height_match_max_distance))
	parts.append(str(terrain_rect_fill_road_margin))
	parts.append(str(terrain_rect_fill_clip_width_mode))
	parts.append(str(terrain_material_override))
	parts.append(str(outer_wall_height))
	parts.append(str(outer_wall_material_override))
	parts.append(str(material_override))
	parts.append(str(uv_length_scale))
	parts.append(str(invert_faces))
	parts.append(str(endpoint_snap_distance))
	parts.append(str(allow_endpoint_to_midpath))
	parts.append(str(minimum_connections))
	parts.append(str(strip_shoulder_sidewalk_at_intersections))
	parts.append(str(intersection_strip_length))
	parts.append(str(adaptive_sampling_enabled))
	parts.append(str(adaptive_sampling_advanced))
	parts.append(str(adaptive_sampling_step_scale))
	parts.append(str(adaptive_sampling_radius_scale))
	parts.append(str(adaptive_sampling_offset))

	var paths := _resolve_paths()
	parts.append(str(paths.size()))
	for p in paths:
		parts.append(str(p.global_transform))
		if p.curve == null:
			parts.append("null_curve")
			continue
		if p.has_method("get_width_profile_signature"):
			parts.append(str(p.call("get_width_profile_signature")))
		if p.has_method("get_edge_profile_signature"):
			parts.append(str(p.call("get_edge_profile_signature")))
		parts.append(str(p.curve.point_count))
		for i in range(p.curve.point_count):
			parts.append(str(p.curve.get_point_position(i)))
			parts.append(str(p.curve.get_point_in(i)))
			parts.append(str(p.curve.get_point_out(i)))
			parts.append(str(p.curve.get_point_tilt(i)))

	return "|".join(parts)
