@tool
extends Node3D
class_name MountainTerrainStrip3D

# MountainTerrainStrip3D
# ------------------------------------------------------------
# Stable alternative to TerrainInfluencePath3D for mountain roads.
# It does NOT try to boolean/influence an existing terrain.
# It generates two controlled terrain strips beside a Path3D:
#   left side  = mountain / cliff / ditch
#   right side = shoulder / slope / valley
#
# Usage:
# 1. Add this node near your road Path3D / SplinePathProfile3D.
# 2. Set source_path to that Path3D.
# 3. Press Regenerate Strip or keep auto_regenerate_in_editor enabled.
# 4. Tune left_profile_* and right_profile_*.
#
# Important:
# - Profile distances are measured outward from the road edge, not from road center.
# - Distance 0.0 should usually have height 0.0 so it touches the road edge.
# - For very tight curves, auto_shrink_on_tight_curves narrows the outer terrain.
# - This is intentionally simpler and safer than the old influence/capsule method.

@export_group("Source")
@export var source_path: NodePath
@export var use_parent_path_if_empty := true
@export var use_source_width_profile := true
@export_range(0.2, 50.0, 0.1) var fallback_road_width := 6.0
@export_range(0.0, 5.0, 0.01) var road_edge_clearance := 0.03

@export_group("Generation")
@export_range(0.25, 20.0, 0.05, "suffix:m") var sample_step := 2.0
@export_range(0.0, 100.0, 0.05, "suffix:m") var cutback_start := 0.0
@export_range(0.0, 100.0, 0.05, "suffix:m") var cutback_end := 0.0
@export_range(-20.0, 20.0, 0.01, "suffix:m") var y_offset := 0.0
@export var generate_left_side := true
@export var generate_right_side := true
## Show the upper surface with Godot's clockwise front-face convention.
@export var invert_faces := true

@export_group("Left Profile - Mountain Side")
@export var left_profile_distances := PackedFloat32Array([0.0, 2.0, 8.0, 18.0, 30.0])
@export var left_profile_heights := PackedFloat32Array([0.0, -0.45, 2.0, 9.0, 16.0])
@export_range(0.0, 3.0, 0.01) var left_width_scale := 1.0
@export_range(0.0, 3.0, 0.01) var left_height_scale := 1.0

@export_group("Right Profile - Valley Side")
@export var right_profile_distances := PackedFloat32Array([0.0, 5.0, 16.0, 35.0])
@export var right_profile_heights := PackedFloat32Array([0.0, -1.0, -7.0, -18.0])
@export_range(0.0, 3.0, 0.01) var right_width_scale := 1.0
@export_range(0.0, 3.0, 0.01) var right_height_scale := 1.0

@export_group("Tight Curve Protection")
@export var auto_shrink_on_tight_curves := true
@export_range(5.0, 175.0, 1.0, "suffix:deg") var tight_curve_angle_degrees := 55.0
@export_range(0.05, 1.0, 0.01) var minimum_curve_width_scale := 0.28
@export_range(0, 8, 1) var shrink_smooth_passes := 2
@export_range(0.05, 30.0, 0.05, "suffix:m") var curvature_probe_distance := 4.0

@export_group("Noise")
@export var noise_enabled := true
@export_range(0.0, 10.0, 0.01, "suffix:m") var noise_amplitude := 0.45
@export_range(0.001, 2.0, 0.001) var noise_frequency := 0.055
@export var noise_seed := 1337
@export_range(0.0, 6.0, 0.01) var noise_edge_falloff := 1.4

@export_group("Mesh")
@export var material_override: Material
@export_range(0.001, 10.0, 0.001) var uv_length_scale := 0.08
@export_range(0.001, 10.0, 0.001) var uv_width_scale := 0.08
@export var create_collision := false
@export var cast_shadow := true

@export_group("Workflow")
@export var auto_regenerate_in_editor := true
@export_range(0.0, 2.0, 0.01, "suffix:s") var editor_regenerate_debounce_seconds := 0.25
@export_tool_button("Regenerate Strip") var regenerate_action := _regenerate_from_button
@export_tool_button("Clear Generated") var clear_generated_action := _clear_generated_from_button
@export var debug_logs := true

const GENERATED_NODE_NAME := "GeneratedMountainTerrainStrip"
const MIN_PROFILE_DISTANCE_STEP := 0.001
const MIN_SAMPLE_STEP := 0.05

var _last_signature := ""
var _pending_signature := ""
var _pending_time_left := 0.0


func _ready() -> void:
	set_process(true)
	if Engine.is_editor_hint():
		_queue_regenerate()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not auto_regenerate_in_editor:
		return

	var sig := _build_signature()
	if sig == _last_signature:
		_pending_signature = ""
		_pending_time_left = 0.0
		return

	if sig != _pending_signature:
		_pending_signature = sig
		_pending_time_left = maxf(0.0, editor_regenerate_debounce_seconds)
		if _pending_time_left > 0.0001:
			return
	else:
		_pending_time_left = maxf(0.0, _pending_time_left - delta)
		if _pending_time_left > 0.0001:
			return

	_pending_signature = ""
	_pending_time_left = 0.0
	_last_signature = sig
	regenerate()


func _regenerate_from_button() -> void:
	_last_signature = ""
	regenerate()


func _clear_generated_from_button() -> void:
	_clear_generated()
	_last_signature = ""


func regenerate() -> void:
	var path := _get_source_path()
	if path == null:
		_debug_log("No source Path3D found. Set source_path or parent this node under a Path3D.")
		_clear_generated()
		return
	if path.curve == null or path.curve.point_count < 2:
		_debug_log("Source Path3D has no valid Curve3D with at least 2 points.")
		_clear_generated()
		return

	var curve := path.curve
	curve.bake_interval = maxf(MIN_SAMPLE_STEP, sample_step * 0.5)
	var length := curve.get_baked_length()
	if length <= 0.01:
		_debug_log("Source curve length is too small.")
		_clear_generated()
		return

	var start_d := clampf(cutback_start, 0.0, maxf(0.0, length - 0.01))
	var end_d := clampf(length - cutback_end, start_d + 0.01, length)
	if end_d - start_d < 0.1:
		_debug_log("cutback_start/cutback_end leave no usable curve length.")
		_clear_generated()
		return

	var left_profile := _build_profile(left_profile_distances, left_profile_heights)
	var right_profile := _build_profile(right_profile_distances, right_profile_heights)
	if generate_left_side and left_profile.size() < 2:
		_debug_log("Left profile needs at least 2 valid points.")
	if generate_right_side and right_profile.size() < 2:
		_debug_log("Right profile needs at least 2 valid points.")
	if (not generate_left_side or left_profile.size() < 2) and (not generate_right_side or right_profile.size() < 2):
		_clear_generated()
		return

	var rows := _sample_rows(path, curve, start_d, end_d)
	if rows.size() < 2:
		_debug_log("Not enough sampled rows.")
		_clear_generated()
		return

	var shrink_values := _compute_curve_shrink_values(rows)
	rows = _apply_shrink_smoothing_to_rows(rows, shrink_values)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tri_count := 0
	if generate_left_side and left_profile.size() >= 2:
		tri_count += _append_side(st, rows, left_profile, -1, left_width_scale, left_height_scale)
	if generate_right_side and right_profile.size() >= 2:
		tri_count += _append_side(st, rows, right_profile, 1, right_width_scale, right_height_scale)

	if tri_count <= 0:
		_debug_log("Generated 0 triangles.")
		_clear_generated()
		return

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		_clear_generated()
		return

	if material_override != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material_override)

	_clear_generated()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = GENERATED_NODE_NAME
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	_set_owner_for_editor(mesh_instance)

	if create_collision:
		mesh_instance.create_trimesh_collision()
		for child in mesh_instance.get_children():
			_set_owner_for_editor(child)

	_debug_log("Generated mountain terrain strip: rows=%d triangles=%d" % [rows.size(), tri_count])


func _get_source_path() -> Path3D:
	if not source_path.is_empty():
		var node := get_node_or_null(source_path)
		if node is Path3D:
			return node as Path3D

	if use_parent_path_if_empty:
		var parent := get_parent()
		if parent is Path3D:
			return parent as Path3D

	return null


func _sample_rows(path: Path3D, curve: Curve3D, start_d: float, end_d: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var length := curve.get_baked_length()
	var step := maxf(MIN_SAMPLE_STEP, sample_step)
	var count := int(ceil((end_d - start_d) / step)) + 1
	count = maxi(count, 2)

	var path_to_local := global_transform.affine_inverse() * path.global_transform

	for i in range(count):
		var t := 0.0 if count <= 1 else float(i) / float(count - 1)
		var dist := lerpf(start_d, end_d, t)
		var center := path_to_local * curve.sample_baked(dist, true)

		var prev_d := maxf(0.0, dist - 0.15)
		var next_d := minf(length, dist + 0.15)
		if is_equal_approx(prev_d, next_d):
			prev_d = maxf(0.0, dist - 0.5)
			next_d = minf(length, dist + 0.5)

		var p_prev := path_to_local * curve.sample_baked(prev_d, true)
		var p_next := path_to_local * curve.sample_baked(next_d, true)
		var tangent := p_next - p_prev
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent.y = 0.0
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()

		# For tangent +Z, this gives right +X.
		var right := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		var edges := _get_road_edges(path, dist, length)

		rows.append({
			"dist": dist,
			"center": center,
			"right": right,
			"left_edge": float(edges.x),
			"right_edge": float(edges.y),
			"curve_scale": 1.0,
		})

	return rows


func _get_road_edges(path: Path3D, dist: float, length: float) -> Vector2:
	var width := fallback_road_width
	var shoulder_left := 0.0
	var shoulder_right := 0.0
	var sidewalk_left := 0.0
	var sidewalk_right := 0.0

	if use_source_width_profile:
		if path.has_method("get_width_at_offset"):
			width = maxf(0.1, float(path.call("get_width_at_offset", dist)))
		elif path.has_method("get_width_at_ratio"):
			var ratio := clampf(dist / maxf(0.001, length), 0.0, 1.0)
			width = maxf(0.1, float(path.call("get_width_at_ratio", ratio)))

		if path.has_method("get_shoulder_left_at_offset"):
			shoulder_left = maxf(0.0, float(path.call("get_shoulder_left_at_offset", dist)))
		if path.has_method("get_shoulder_right_at_offset"):
			shoulder_right = maxf(0.0, float(path.call("get_shoulder_right_at_offset", dist)))
		if path.has_method("get_sidewalk_left_at_offset"):
			sidewalk_left = maxf(0.0, float(path.call("get_sidewalk_left_at_offset", dist)))
		if path.has_method("get_sidewalk_right_at_offset"):
			sidewalk_right = maxf(0.0, float(path.call("get_sidewalk_right_at_offset", dist)))

	var lane_extents := Vector2(width * 0.5, width * 0.5)
	if use_source_width_profile and path.has_method("get_lane_extents_at_offset"):
		var raw_extents: Variant = path.call("get_lane_extents_at_offset", dist)
		if raw_extents is Vector2:
			lane_extents = raw_extents
	var left_edge := maxf(0.05, lane_extents.x) + shoulder_left + sidewalk_left + maxf(0.0, road_edge_clearance)
	var right_edge := maxf(0.05, lane_extents.y) + shoulder_right + sidewalk_right + maxf(0.0, road_edge_clearance)
	return Vector2(left_edge, right_edge)


func _build_profile(distances: PackedFloat32Array, heights: PackedFloat32Array) -> Array[Dictionary]:
	var profile: Array[Dictionary] = []
	var count := mini(distances.size(), heights.size())
	if count <= 0:
		return profile

	for i in range(count):
		var d := maxf(0.0, float(distances[i]))
		var h := float(heights[i])
		profile.append({"d": d, "h": h})

	profile.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("d", 0.0)) < float(b.get("d", 0.0))
	)

	# Remove duplicate / nearly duplicate distances.
	var cleaned: Array[Dictionary] = []
	for item in profile:
		var d := float(item.get("d", 0.0))
		if cleaned.is_empty():
			cleaned.append(item)
			continue
		var prev_d := float(cleaned[cleaned.size() - 1].get("d", 0.0))
		if absf(d - prev_d) < MIN_PROFILE_DISTANCE_STEP:
			cleaned[cleaned.size() - 1] = item
		else:
			cleaned.append(item)

	# Force a road-edge point if the profile does not start at 0.
	if not cleaned.is_empty() and float(cleaned[0].get("d", 0.0)) > MIN_PROFILE_DISTANCE_STEP:
		cleaned.insert(0, {"d": 0.0, "h": 0.0})

	return cleaned


func _compute_curve_shrink_values(rows: Array[Dictionary]) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(rows.size())
	for i in range(rows.size()):
		values[i] = 1.0

	if not auto_shrink_on_tight_curves or rows.size() < 3:
		return values

	var limit_angle := deg_to_rad(maxf(1.0, tight_curve_angle_degrees))
	var min_scale := clampf(minimum_curve_width_scale, 0.01, 1.0)

	for i in range(1, rows.size() - 1):
		var prev_center: Vector3 = rows[i - 1].get("center", Vector3.ZERO)
		var curr_center: Vector3 = rows[i].get("center", Vector3.ZERO)
		var next_center: Vector3 = rows[i + 1].get("center", Vector3.ZERO)

		var a := curr_center - prev_center
		var b := next_center - curr_center
		a.y = 0.0
		b.y = 0.0
		if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
			values[i] = 1.0
			continue

		a = a.normalized()
		b = b.normalized()
		var dot_value := clampf(a.dot(b), -1.0, 1.0)
		var angle := acos(dot_value)
		var amount := clampf(angle / limit_angle, 0.0, 1.0)
		values[i] = lerpf(1.0, min_scale, amount)

	values[0] = values[1]
	values[values.size() - 1] = values[values.size() - 2]
	return values


func _apply_shrink_smoothing_to_rows(rows: Array[Dictionary], shrink_values: PackedFloat32Array) -> Array[Dictionary]:
	if shrink_values.size() != rows.size():
		return rows

	var values := shrink_values
	var passes := maxi(0, shrink_smooth_passes)
	for _pass in range(passes):
		var next_values := PackedFloat32Array()
		next_values.resize(values.size())
		for i in range(values.size()):
			if i == 0 or i == values.size() - 1:
				next_values[i] = values[i]
			else:
				next_values[i] = (values[i - 1] + values[i] * 2.0 + values[i + 1]) * 0.25
		values = next_values

	for i in range(rows.size()):
		rows[i]["curve_scale"] = clampf(values[i], 0.01, 1.0)
	return rows


func _append_side(
	st: SurfaceTool,
	rows: Array[Dictionary],
	profile: Array[Dictionary],
	side: int,
	width_scale: float,
	height_scale: float
) -> int:
	var grid: Array = []
	var uv_grid: Array = []
	var profile_count := profile.size()
	if rows.size() < 2 or profile_count < 2:
		return 0

	var max_profile_d := maxf(0.001, float(profile[profile_count - 1].get("d", 0.0)))

	for row in rows:
		var row_points: Array[Vector3] = []
		var row_uvs: Array[Vector2] = []
		var center: Vector3 = row.get("center", Vector3.ZERO)
		var right: Vector3 = row.get("right", Vector3.RIGHT)
		var dist_along := float(row.get("dist", 0.0))
		var edge := float(row.get("left_edge", 0.0)) if side < 0 else float(row.get("right_edge", 0.0))
		var curve_scale := float(row.get("curve_scale", 1.0))
		var side_width_scale := maxf(0.0, width_scale) * curve_scale

		for item in profile:
			var profile_d := float(item.get("d", 0.0))
			var profile_h := float(item.get("h", 0.0))
			var outward_d := profile_d * side_width_scale
			var offset := float(side) * (edge + outward_d)
			var noise_weight := _noise_weight(profile_d, max_profile_d)
			var h := profile_h * height_scale + _sample_noise(center, right, offset) * noise_weight
			var p := center + right * offset
			p.y += h + y_offset
			row_points.append(p)
			row_uvs.append(Vector2(profile_d * uv_width_scale, dist_along * uv_length_scale))

		grid.append(row_points)
		uv_grid.append(row_uvs)

	var triangles := 0
	for r in range(rows.size() - 1):
		var row0: Array = grid[r]
		var row1: Array = grid[r + 1]
		var uv0: Array = uv_grid[r]
		var uv1: Array = uv_grid[r + 1]

		for c in range(profile_count - 1):
			var a: Vector3 = row0[c]
			var b: Vector3 = row1[c]
			var cpos: Vector3 = row1[c + 1]
			var d: Vector3 = row0[c + 1]

			var auv: Vector2 = uv0[c]
			var buv: Vector2 = uv1[c]
			var cuv: Vector2 = uv1[c + 1]
			var duv: Vector2 = uv0[c + 1]

			# Right side with edge->outer order faces up with a,b,c.
			# Left side needs flipped winding because outward is negative right-vector.
			var flip := side < 0
			if invert_faces:
				flip = not flip

			_add_triangle(st, a, auv, b, buv, cpos, cuv, flip)
			_add_triangle(st, a, auv, cpos, cuv, d, duv, flip)
			triangles += 2

	return triangles


func _add_triangle(
	st: SurfaceTool,
	p0: Vector3,
	uv0: Vector2,
	p1: Vector3,
	uv1: Vector2,
	p2: Vector3,
	uv2: Vector2,
	flip: bool
) -> void:
	if flip:
		st.set_uv(uv0)
		st.add_vertex(p0)
		st.set_uv(uv2)
		st.add_vertex(p2)
		st.set_uv(uv1)
		st.add_vertex(p1)
	else:
		st.set_uv(uv0)
		st.add_vertex(p0)
		st.set_uv(uv1)
		st.add_vertex(p1)
		st.set_uv(uv2)
		st.add_vertex(p2)


func _noise_weight(profile_d: float, max_profile_d: float) -> float:
	if not noise_enabled or noise_amplitude <= 0.0001:
		return 0.0
	var t := clampf(profile_d / maxf(0.001, max_profile_d), 0.0, 1.0)
	return pow(t, maxf(0.0, noise_edge_falloff))


func _sample_noise(center: Vector3, right: Vector3, offset: float) -> float:
	if not noise_enabled or noise_amplitude <= 0.0001:
		return 0.0
	var p := center + right * offset
	# Deterministic lightweight value noise. No dependency on FastNoiseLite.
	var x := p.x * noise_frequency + float(noise_seed) * 0.013
	var z := p.z * noise_frequency + float(noise_seed) * 0.017
	var n := sin(x * 12.9898 + z * 78.233) * 43758.5453
	var f = n - floor(n)
	return (f * 2.0 - 1.0) * noise_amplitude


func _clear_generated() -> void:
	var old := get_node_or_null(GENERATED_NODE_NAME)
	if old != null:
		remove_child(old)
		old.queue_free()


func _queue_regenerate() -> void:
	_last_signature = ""
	_pending_signature = ""
	_pending_time_left = 0.0


func _build_signature() -> String:
	var parts: Array[String] = []
	parts.append(str(source_path))
	parts.append(str(use_parent_path_if_empty))
	parts.append(str(use_source_width_profile))
	parts.append(str(fallback_road_width))
	parts.append(str(road_edge_clearance))
	parts.append(str(sample_step))
	parts.append(str(cutback_start))
	parts.append(str(cutback_end))
	parts.append(str(y_offset))
	parts.append(str(generate_left_side))
	parts.append(str(generate_right_side))
	parts.append(str(invert_faces))
	parts.append(str(left_profile_distances))
	parts.append(str(left_profile_heights))
	parts.append(str(left_width_scale))
	parts.append(str(left_height_scale))
	parts.append(str(right_profile_distances))
	parts.append(str(right_profile_heights))
	parts.append(str(right_width_scale))
	parts.append(str(right_height_scale))
	parts.append(str(auto_shrink_on_tight_curves))
	parts.append(str(tight_curve_angle_degrees))
	parts.append(str(minimum_curve_width_scale))
	parts.append(str(shrink_smooth_passes))
	parts.append(str(curvature_probe_distance))
	parts.append(str(noise_enabled))
	parts.append(str(noise_amplitude))
	parts.append(str(noise_frequency))
	parts.append(str(noise_seed))
	parts.append(str(noise_edge_falloff))
	parts.append(str(uv_length_scale))
	parts.append(str(uv_width_scale))
	parts.append(str(create_collision))
	parts.append(str(cast_shadow))
	parts.append(str(global_transform))

	var path := _get_source_path()
	if path != null:
		parts.append(str(path.get_path()))
		parts.append(str(path.global_transform))
		if path.curve != null:
			parts.append(str(path.curve.point_count))
			parts.append(str(path.curve.get_baked_length()))
			for i in range(path.curve.point_count):
				parts.append(str(path.curve.get_point_position(i)))
				parts.append(str(path.curve.get_point_in(i)))
				parts.append(str(path.curve.get_point_out(i)))
				parts.append(str(path.curve.get_point_tilt(i)))
		if path.has_method("get_dependent_width_profile_signature"):
			parts.append(str(path.call("get_dependent_width_profile_signature")))
		elif path.has_method("get_width_profile_signature"):
			parts.append(str(path.call("get_width_profile_signature")))
		if path.has_method("get_edge_profile_signature"):
			parts.append(str(path.call("get_edge_profile_signature")))

	return "|".join(parts)


func _set_owner_for_editor(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_tree().edited_scene_root
	if root != null and node != root:
		node.owner = root
	for child in node.get_children():
		_set_owner_for_editor(child)


func _debug_log(message: String) -> void:
	if debug_logs:
		print("[MountainTerrainStrip3D] ", message)
