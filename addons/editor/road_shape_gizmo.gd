@tool
extends EditorNode3DGizmoPlugin
## Shape handles complement the point's normal move/rotate gizmo.
const HISTORY = preload("../scripts/spline_road/road_editor_history.gd")
const WIDTH_HANDLE = preload("../scripts/spline_road/spline_width_handle.gd")
const LEFT := 0
const RIGHT := 1
const TILT := 2
var _drags: Dictionary = {}


func _init() -> void:
	create_material("width", Color(0.15, 0.9, 1.0), false, true)
	create_material("tilt", Color(1.0, 0.65, 0.2), false, true)
	create_handle_material("shape_handles")


func _get_gizmo_name() -> String:
	return "Roda-Gen width and tilt"


func _get_priority() -> int:
	return 120


func _can_commit_handle_on_click() -> bool:
	# A click without motion must also clear its captured drag frame. The
	# commit callback skips history when the source data did not change.
	return true


func _has_gizmo(node: Node3D) -> bool:
	return _profile(node) != null


func _profile(node: Node3D) -> Path3D:
	if node is Path3D and node.has_method("set_point_lane_width_at_index"):
		return node
	if node.get_script() == WIDTH_HANDLE:
		return node._get_profile() as Path3D
	return null


func _point_index(node: Node3D, profile: Path3D) -> int:
	return int(node.point_index) if node != profile else int(profile.selected_point_index)


func _valid_point(profile: Path3D, index: int) -> bool:
	return profile != null and profile.curve != null and index >= 0 and index < profile.curve.point_count


func _extents(profile: Path3D, index: int) -> Vector2:
	if profile.lane_profile_enabled:
		return Vector2(profile._get_point_lane_count(index, true), profile._get_point_lane_count(index, false)) * profile._get_point_lane_width(index)
	return Vector2.ONE * float(profile._get_point_width(index)) * 0.5


func _frame(profile: Path3D, index: int) -> Transform3D:
	var key := profile.get_instance_id()
	if _drags.has(key) and _drags[key].index == index:
		var drag: Dictionary = _drags[key]
		var frame: Transform3D = drag.frame
		# The generated road may refresh asynchronously. Keep the drag plane
		# fixed and show the current tilt immediately, without feeding it back.
		if drag.kind == TILT:
			frame.basis *= Basis(Vector3.BACK, profile.curve.get_point_tilt(index) - drag.tilt)
		return frame
	return profile.get_point_editor_transform(index)


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	if not gizmo.get_node_3d() in EditorInterface.get_selection().get_selected_nodes():
		return
	var node := gizmo.get_node_3d()
	var profile := _profile(node)
	if profile == null:
		return
	var index := _point_index(node, profile)
	if not _valid_point(profile, index):
		return
	var frame := node.global_transform.affine_inverse() * profile.global_transform * _frame(profile, index)
	var extents := _extents(profile, index)
	var radius := maxf(1.5, maxf(extents.x, extents.y) + 1.0)
	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	for side in [LEFT, RIGHT]:
		if extents[side] <= 0.0:
			continue
		var tip := Vector3((-1.0 if side == LEFT else 1.0) * extents[side], 0, 0)
		handles.append(frame * tip)
		ids.append(index * 3 + side)
		gizmo.add_lines(PackedVector3Array([frame.origin, frame * tip]), get_material("width", gizmo))
	var arc := PackedVector3Array()
	for step in range(32):
		for end in [step, step + 1]:
			var angle := PI * float(end) / 32.0
			arc.append(frame * (Vector3(cos(angle), sin(angle), 0) * radius))
	gizmo.add_lines(arc, get_material("tilt", gizmo))
	gizmo.add_lines(PackedVector3Array([frame.origin, frame * (Vector3.UP * radius)]), get_material("tilt", gizmo))
	handles.append(frame * (Vector3.UP * radius))
	ids.append(index * 3 + TILT)
	gizmo.add_handles(handles, get_material("shape_handles", gizmo), ids)


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	var profile := _profile(gizmo.get_node_3d())
	var property := "Tilt (degrees)" if handle_id % 3 == TILT else "Road width (m)"
	if handle_id % 3 != TILT and profile != null and profile.lane_profile_enabled:
		property = "Lane width (m, all lanes)"
	return "Point %d — %s" % [handle_id / 3, property]


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var profile := _profile(gizmo.get_node_3d())
	var index := handle_id / 3
	if not _valid_point(profile, index):
		return 0.0
	if handle_id % 3 == TILT:
		return rad_to_deg(profile.curve.get_point_tilt(index))
	return profile._get_point_lane_width(index) if profile.lane_profile_enabled else profile._get_point_width(index)


func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> void:
	var profile := _profile(gizmo.get_node_3d())
	var index := handle_id / 3
	if not _valid_point(profile, index):
		return
	var frame: Transform3D = profile.get_point_editor_transform(index)
	_drags[profile.get_instance_id()] = {
		"before": profile.capture_editor_state(), "frame": frame,
		"inverse": (profile.global_transform * frame).affine_inverse(),
		"index": index, "kind": handle_id % 3,
		"tilt": profile.curve.get_point_tilt(index), "angle": 0.0,
	}
	profile.select_point_index(index)


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var profile := _profile(gizmo.get_node_3d())
	if profile == null or not _drags.has(profile.get_instance_id()):
		return
	var drag: Dictionary = _drags[profile.get_instance_id()]
	if handle_id != drag.index * 3 + drag.kind or not _valid_point(profile, drag.index):
		return
	var inverse: Transform3D = drag.inverse
	var origin := inverse * camera.project_ray_origin(screen_pos)
	var direction := (inverse.basis * camera.project_ray_normal(screen_pos)).normalized()
	if drag.kind == TILT:
		if absf(direction.z) < 0.001:
			return
		var distance := -origin.z / direction.z
		if distance < 0.0:
			return
		var hit := origin + direction * distance
		if Vector2(hit.x, hit.y).length_squared() < 0.0001:
			return
		var angle := atan2(-hit.x, hit.y)
		var unwrapped := float(drag.angle) + wrapf(angle - float(drag.angle), -PI, PI)
		drag.angle = unwrapped
		profile.set_point_tilt_at_index(drag.index, float(drag.tilt) + unwrapped)
	else:
		# Closest point on the width axis to the mouse ray. Works from above
		# as well as oblique views, including scaled/rotated parent nodes.
		var denominator := 1.0 - direction.x * direction.x
		if denominator < 0.0001:
			return
		var extent := (origin.x - direction.x * origin.dot(direction)) / denominator
		extent *= -1.0 if drag.kind == LEFT else 1.0
		if profile.lane_profile_enabled:
			var count: int = profile._get_point_lane_count(drag.index, drag.kind == LEFT)
			if count <= 0:
				return
			profile.set_point_lane_width_at_index(drag.index, maxf(1.5, extent / count))
		else:
			profile.set_point_width_at_index(drag.index, maxf(0.1, extent * 2.0))
	_refresh(profile, gizmo.get_node_3d())


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, _restore: Variant, cancel: bool) -> void:
	var profile := _profile(gizmo.get_node_3d())
	if profile == null or not _drags.has(profile.get_instance_id()):
		return
	var drag: Dictionary = _drags[profile.get_instance_id()]
	_drags.erase(profile.get_instance_id())
	if cancel:
		profile.restore_editor_state(drag.before)
	else:
		var after: Dictionary = profile.capture_editor_state()
		if after != drag.before and HISTORY.manager != null:
			if drag.kind != TILT and profile.lane_profile_enabled:
				profile.apply_lane_changes()
			var history: Object = HISTORY.manager
			history.create_action("Edit road tilt" if drag.kind == TILT else "Edit road width", UndoRedo.MERGE_DISABLE, profile)
			history.add_do_method(profile, "restore_editor_state", after)
			history.add_undo_method(profile, "restore_editor_state", drag.before)
			history.commit_action(false)
	_refresh(profile, gizmo.get_node_3d())


func _refresh(profile: Path3D, node: Node3D) -> void:
	profile._rebuild_preview()
	node.update_gizmos()
