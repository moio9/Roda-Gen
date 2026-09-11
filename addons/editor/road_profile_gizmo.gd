@tool
extends EditorNode3DGizmoPlugin

const HISTORY = preload("../scripts/spline_road/road_editor_history.gd")
var _edits: Dictionary = {}


func _init() -> void:
	create_material("road_points", Color(1.0, 0.65, 0.2))
	create_material("road_selected_points", Color(0.2, 0.95, 1.0))


func _get_gizmo_name() -> String:
	return "Roda-Gen control points"


func _get_priority() -> int:
	return 100


func _has_gizmo(node: Node3D) -> bool:
	return node is Path3D and node.has_method("capture_editor_state")


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var profile: Path3D = gizmo.get_node_3d()
	if profile.curve == null:
		return
	for index in range(profile.curve.point_count):
		var frame: Transform3D = profile.get_point_editor_transform(index)
		var extent: float = maxf(0.3, float(profile._get_point_width(index)) * 0.5)
		var points := PackedVector3Array([
			frame * Vector3(-extent, 0, 0), frame * Vector3(extent, 0, 0),
			frame * Vector3(0, 0, -0.4), frame * Vector3(0, 0, 0.4),
		])
		var selected := gizmo.is_subgizmo_selected(index)
		gizmo.add_lines(points, get_material("road_selected_points" if selected else "road_points", gizmo))
		gizmo.add_collision_segments(points)


func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, screen_pos: Vector2) -> int:
	var profile: Path3D = gizmo.get_node_3d()
	if profile.curve == null:
		return -1
	var best := -1
	var best_distance := 12.0
	for index in range(profile.curve.point_count):
		var frame: Transform3D = profile.get_point_editor_transform(index)
		var world_position := profile.to_global(frame.origin)
		if camera.is_position_behind(world_position):
			continue
		var extent: float = maxf(0.3, float(profile._get_point_width(index)) * 0.5)
		var a := profile.to_global(frame * Vector3(-extent, 0, 0))
		var b := profile.to_global(frame * Vector3(extent, 0, 0))
		var closest := Geometry2D.get_closest_point_to_segment(screen_pos, camera.unproject_position(a), camera.unproject_position(b))
		var distance := closest.distance_to(screen_pos)
		if distance < best_distance:
			best = index
			best_distance = distance
	if best >= 0:
		profile.select_point_index(best)
	return best


func _subgizmos_intersect_frustum(gizmo: EditorNode3DGizmo, _camera: Camera3D, planes: Array[Plane]) -> PackedInt32Array:
	var profile: Path3D = gizmo.get_node_3d()
	var ids := PackedInt32Array()
	if profile.curve == null:
		return ids
	for index in range(profile.curve.point_count):
		var frame: Transform3D = profile.get_point_editor_transform(index)
		var world_position := profile.to_global(frame.origin)
		var inside := true
		for plane in planes:
			if plane.is_point_over(world_position):
				inside = false
				break
		if inside:
			ids.append(index)
	return ids


func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, id: int) -> Transform3D:
	return gizmo.get_node_3d().get_point_editor_transform(id)


func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, id: int, transform: Transform3D) -> void:
	var profile: Path3D = gizmo.get_node_3d()
	var key := profile.get_instance_id()
	if not _edits.has(key):
		_edits[key] = {"before": profile.capture_editor_state(), "transforms": {}}
		# Capture all selected-point frames before moving any point. A nearby
		# point's banking/orientation can change after the first point moves.
		for index in range(profile.curve.point_count):
			_edits[key].transforms[index] = profile.get_point_editor_transform(index)
	var edit: Dictionary = _edits[key]
	profile.apply_point_editor_transform(id, edit.transforms[id], transform, edit.before.curve_points[id])
	profile.update_gizmos()


func _commit_subgizmos(gizmo: EditorNode3DGizmo, _ids: PackedInt32Array, _restores: Array[Transform3D], cancel: bool) -> void:
	var profile: Path3D = gizmo.get_node_3d()
	var key := profile.get_instance_id()
	if not _edits.has(key):
		return
	var before: Dictionary = _edits[key].before
	_edits.erase(key)
	if cancel:
		profile.restore_editor_state(before)
		return
	var after: Dictionary = profile.capture_editor_state()
	var history: Object = HISTORY.manager
	history.create_action("Edit road control points", UndoRedo.MERGE_DISABLE, profile)
	history.add_do_method(profile, "restore_editor_state", after)
	history.add_undo_method(profile, "restore_editor_state", before)
	history.commit_action(false)
