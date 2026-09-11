@tool
extends Node3D
class_name SplinePropSpan3D

@export var enabled := true
@export var target_path: NodePath
@export_range(0.0, 100000.0, 0.1, "or_greater", "suffix:m") var start_offset := 0.0
@export_range(0.0, 100000.0, 0.1, "or_greater", "suffix:m") var end_offset := 20.0
@export var snap_handles_to_path := true
@export_range(-100.0, 100.0, 0.1, "or_greater", "or_less", "suffix:m") var lateral_offset := 0.0
@export_range(-100.0, 100.0, 0.1, "or_greater", "or_less", "suffix:m") var vertical_offset := 0.0
@export_group("Preview")
@export var show_preview := true
@export var preview_color := Color(0.12, 0.95, 0.55, 0.85)
@export_range(0.01, 8.0, 0.01, "or_greater", "suffix:m") var preview_width := 0.5
@export_range(0.01, 8.0, 0.01, "or_greater", "suffix:m") var preview_lift := 0.08
@export_range(0.1, 8.0, 0.1, "or_greater", "suffix:m") var preview_step := 1.0

const START_HANDLE_NAME := "StartHandle"
const END_HANDLE_NAME := "EndHandle"
const PREVIEW_NODE_NAME := "__SpanPreview"
## The inspector edits offsets in 0.1 m steps. Ignore sub-millimetre noise from
## projecting a handle back onto a baked curve, otherwise it can trigger an
## endless prop-array regeneration loop after a drag ends.
const OFFSET_SYNC_EPSILON := 0.001

var _last_offsets := Vector2(INF, INF)
var _last_start_handle_position := Vector3(INF, INF, INF)
var _last_end_handle_position := Vector3(INF, INF, INF)
var _syncing := false
var _preview_material: StandardMaterial3D
var _last_preview_signature := ""


func _ready() -> void:
	set_process(true)
	_ensure_handles()
	_update_handles_from_offsets()
	_update_preview()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_handles()
	var offsets := Vector2(start_offset, end_offset)
	if not _offsets_match(offsets, _last_offsets):
		_update_handles_from_offsets()
	elif _handles_were_moved():
		_update_offsets_from_handles()
	_update_preview()


func is_spline_prop_span() -> bool:
	return true


func get_range_for_path(path: Path3D) -> Dictionary:
	if not enabled or path == null:
		return {"ok": false}

	var span_path := _resolve_target_path()
	if span_path == null:
		return {"ok": false}
	if span_path != path:
		return {"ok": false}
	if path.curve == null:
		return {"ok": false}

	var length := maxf(0.0, path.curve.get_baked_length())
	var a := clampf(minf(start_offset, end_offset), 0.0, length)
	var b := clampf(maxf(start_offset, end_offset), 0.0, length)
	if b <= a + 0.0001:
		return {"ok": false}
	return {"ok": true, "range": Vector2(a, b)}


func _ensure_handles() -> void:
	if _find_handle(START_HANDLE_NAME) == null:
		var start := Marker3D.new()
		start.name = START_HANDLE_NAME
		add_child(start)
		_assign_editor_owner(start)
	if _find_handle(END_HANDLE_NAME) == null:
		var end := Marker3D.new()
		end.name = END_HANDLE_NAME
		add_child(end)
		_assign_editor_owner(end)


func _find_handle(handle_name: String) -> Marker3D:
	return get_node_or_null(handle_name) as Marker3D


func _resolve_target_path() -> Path3D:
	if target_path == NodePath():
		return null
	var node := get_node_or_null(target_path)
	return node as Path3D


func _update_handles_from_offsets() -> void:
	if _syncing:
		return
	var path := _resolve_target_path()
	if path == null or path.curve == null or path.curve.point_count < 2:
		_last_offsets = Vector2(start_offset, end_offset)
		return

	_syncing = true
	var length := maxf(0.0, path.curve.get_baked_length())
	start_offset = clampf(start_offset, 0.0, length)
	end_offset = clampf(end_offset, 0.0, length)
	var start := _find_handle(START_HANDLE_NAME)
	var end := _find_handle(END_HANDLE_NAME)
	if start != null:
		start.global_position = _offset_to_world(path, start_offset, length)
	if end != null:
		end.global_position = _offset_to_world(path, end_offset, length)
	_syncing = false
	_last_offsets = Vector2(start_offset, end_offset)
	_remember_handle_positions()


func _update_offsets_from_handles() -> void:
	if _syncing:
		return
	if not snap_handles_to_path:
		_remember_handle_positions()
		return
	var path := _resolve_target_path()
	if path == null or path.curve == null or path.curve.point_count < 2:
		return

	var start := _find_handle(START_HANDLE_NAME)
	var end := _find_handle(END_HANDLE_NAME)
	if start == null or end == null:
		return

	var length := maxf(0.0, path.curve.get_baked_length())
	var new_start := _world_to_offset(path, start.global_position)
	var new_end := _world_to_offset(path, end.global_position)
	new_start = clampf(new_start, 0.0, length)
	new_end = clampf(new_end, 0.0, length)

	var start_changed := absf(new_start - start_offset) > OFFSET_SYNC_EPSILON
	var end_changed := absf(new_end - end_offset) > OFFSET_SYNC_EPSILON
	if not start_changed and not end_changed:
		_last_offsets = Vector2(start_offset, end_offset)
		_remember_handle_positions()
		return

	_syncing = true
	if start_changed:
		start_offset = new_start
		start.global_position = _offset_to_world(path, start_offset, length)
	if end_changed:
		end_offset = new_end
		end.global_position = _offset_to_world(path, end_offset, length)
	_syncing = false
	_last_offsets = Vector2(start_offset, end_offset)
	_remember_handle_positions()


func _offsets_match(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) <= OFFSET_SYNC_EPSILON and absf(a.y - b.y) <= OFFSET_SYNC_EPSILON


func _handles_were_moved() -> bool:
	var start := _find_handle(START_HANDLE_NAME)
	var end := _find_handle(END_HANDLE_NAME)
	if start == null or end == null:
		return false
	var epsilon_sq := OFFSET_SYNC_EPSILON * OFFSET_SYNC_EPSILON
	return (
		start.global_position.distance_squared_to(_last_start_handle_position) > epsilon_sq
		or end.global_position.distance_squared_to(_last_end_handle_position) > epsilon_sq
	)


func _remember_handle_positions() -> void:
	var start := _find_handle(START_HANDLE_NAME)
	var end := _find_handle(END_HANDLE_NAME)
	if start != null:
		_last_start_handle_position = start.global_position
	if end != null:
		_last_end_handle_position = end.global_position


func _world_to_offset(path: Path3D, world_pos: Vector3) -> float:
	if path == null or path.curve == null:
		return 0.0
	var curve := path.curve
	var local := path.to_local(world_pos)
	if curve.has_method("get_closest_offset"):
		return float(curve.get_closest_offset(local))
	return _approx_closest_offset(curve, local, 0.5)


func _offset_to_world(path: Path3D, dist: float, length: float) -> Vector3:
	if path == null or path.curve == null:
		return global_position
	var curve := path.curve
	var d := clampf(dist, 0.0, length)
	var center := path.to_global(curve.sample_baked(d, true))
	var tangent := _sample_tangent_world(path, d, length)
	var up := _sample_up_world(path, d)
	var right := up.cross(tangent).normalized()
	if right.length() < 0.001:
		right = Vector3.RIGHT
	return center + right * lateral_offset + up * vertical_offset


func _sample_tangent_world(path: Path3D, dist: float, length: float) -> Vector3:
	if path == null or path.curve == null:
		return Vector3.FORWARD
	var curve := path.curve
	var delta := 0.2
	var prev_dist := maxf(0.0, dist - delta)
	var next_dist := minf(length, dist + delta)
	if is_equal_approx(prev_dist, next_dist):
		if next_dist < length:
			next_dist = minf(length, next_dist + delta)
		elif prev_dist > 0.0:
			prev_dist = maxf(0.0, prev_dist - delta)
	var p0 := path.to_global(curve.sample_baked(prev_dist, true))
	var p1 := path.to_global(curve.sample_baked(next_dist, true))
	var tangent := (p1 - p0).normalized()
	if tangent.length() < 0.001:
		tangent = -path.global_transform.basis.z.normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	return tangent


func _sample_up_world(path: Path3D, dist: float) -> Vector3:
	if path != null and path.curve != null and path.curve.has_method("sample_baked_up_vector"):
		var up_local: Vector3 = path.curve.sample_baked_up_vector(dist, true)
		var up_world := (path.global_transform.basis * up_local).normalized()
		if up_world.length() > 0.001:
			return up_world
	return Vector3.UP


func _approx_closest_offset(curve: Curve3D, point: Vector3, step: float) -> float:
	if curve == null:
		return 0.0
	var length := maxf(0.0, curve.get_baked_length())
	if length <= 0.001:
		return 0.0
	var s := maxf(0.05, step)
	var best_dist := INF
	var best_offset := 0.0
	var d := 0.0
	while d <= length + 0.0001:
		var p := curve.sample_baked(d, true)
		var dist_sq := point.distance_squared_to(p)
		if dist_sq < best_dist:
			best_dist = dist_sq
			best_offset = d
		d += s
	return best_offset


func _assign_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	if node == null:
		return
	var edited_root := get_tree().edited_scene_root
	if edited_root == null:
		return
	if not edited_root.is_ancestor_of(node):
		return
	node.owner = edited_root


func _update_preview() -> void:
	if not Engine.is_editor_hint():
		return

	var preview_node := _get_or_create_preview_node()
	if preview_node == null:
		return

	var sig := _build_preview_signature()
	if sig == _last_preview_signature:
		return
	_last_preview_signature = sig

	if not show_preview or not enabled:
		preview_node.visible = false
		preview_node.mesh = null
		return

	var path := _resolve_target_path()
	if path == null or path.curve == null or path.curve.point_count < 2:
		preview_node.visible = false
		preview_node.mesh = null
		return

	var length := maxf(0.0, path.curve.get_baked_length())
	var a := clampf(minf(start_offset, end_offset), 0.0, length)
	var b := clampf(maxf(start_offset, end_offset), 0.0, length)
	if b <= a + 0.0001:
		preview_node.visible = false
		preview_node.mesh = null
		return

	var step := maxf(0.1, preview_step)
	var samples:int = max(2, int(ceil((b - a) / step)) + 1)
	var half_width := maxf(0.01, preview_width) * 0.5
	var lift := maxf(0.0, preview_lift)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(samples * 2)
	normals.resize(samples * 2)
	uvs.resize(samples * 2)

	for i in range(samples):
		var t := float(i) / float(samples - 1)
		var d := lerpf(a, b, t)
		var center_world := _offset_to_world(path, d, length)
		var tangent := _sample_tangent_world(path, d, length)
		var up := _sample_up_world(path, d)
		var right := up.cross(tangent).normalized()
		if right.length() < 0.001:
			right = Vector3.RIGHT
		var base := center_world + up * lift
		var left_world := base - right * half_width
		var right_world := base + right * half_width

		var vi := i * 2
		verts[vi] = to_local(left_world)
		verts[vi + 1] = to_local(right_world)
		normals[vi] = Vector3.UP
		normals[vi + 1] = Vector3.UP
		uvs[vi] = Vector2(0.0, t)
		uvs[vi + 1] = Vector2(1.0, t)

	if samples >= 2:
		indices.resize((samples - 1) * 6)
		var write_idx := 0
		for i in range(samples - 1):
			var a0 := i * 2
			var b0 := a0 + 1
			var a1 := a0 + 2
			var b1 := a0 + 3
			indices[write_idx] = a0
			write_idx += 1
			indices[write_idx] = a1
			write_idx += 1
			indices[write_idx] = b0
			write_idx += 1
			indices[write_idx] = b0
			write_idx += 1
			indices[write_idx] = a1
			write_idx += 1
			indices[write_idx] = b1
			write_idx += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _get_preview_material())
	preview_node.mesh = mesh
	preview_node.visible = true


func _get_or_create_preview_node() -> MeshInstance3D:
	var node := get_node_or_null(PREVIEW_NODE_NAME) as MeshInstance3D
	if node == null:
		node = MeshInstance3D.new()
		node.name = PREVIEW_NODE_NAME
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_assign_editor_owner(node)
	return node


func _get_preview_material() -> StandardMaterial3D:
	if _preview_material == null:
		_preview_material = StandardMaterial3D.new()
		_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_preview_material.no_depth_test = false
	_preview_material.albedo_color = preview_color
	return _preview_material


func _build_preview_signature() -> String:
	var parts: Array[String] = [
		str(enabled),
		str(show_preview),
		str(start_offset),
		str(end_offset),
		str(snap_handles_to_path),
		str(lateral_offset),
		str(vertical_offset),
		str(preview_color),
		str(preview_width),
		str(preview_lift),
		str(preview_step),
		str(global_transform),
	]
	var path := _resolve_target_path()
	if path == null:
		parts.append("null_path")
		return "|".join(parts)
	parts.append(str(path.get_instance_id()))
	parts.append(str(path.global_transform))
	if path.curve == null:
		parts.append("null_curve")
		return "|".join(parts)
	parts.append(str(path.curve.point_count))
	for i in range(path.curve.point_count):
		parts.append(str(path.curve.get_point_position(i)))
		parts.append(str(path.curve.get_point_in(i)))
		parts.append(str(path.curve.get_point_out(i)))
		parts.append(str(path.curve.get_point_tilt(i)))
	return "|".join(parts)
