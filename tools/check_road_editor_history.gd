@tool
extends RefCounted
## Invoked by the editor plugin with -- --roda-editor-tests.

var _failed := false
var _tree: SceneTree


func run(plugin: EditorPlugin) -> void:
	_tree = plugin.get_tree()
	var scene: Node
	for frame in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "RoadEditingDemo":
			break
		await _tree.process_frame
	if scene == null or scene.name != "RoadEditingDemo":
		push_error("Open addons/scenes/road_editing_demo.tscn for the editor history check")
		_tree.quit(2)
		return
	var profile: Path3D = scene.get_node("Route")
	var history := plugin.get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(profile))
	var initial: Dictionary = profile.capture_editor_state()
	profile.select_point_index(0)
	EditorInterface.edit_node(profile)
	await _frames(5)
	var inspector_property := _find_property(EditorInterface.get_inspector(), "selected_point_lanes_right")
	_check(inspector_property != null, "Actual Inspector lane editor was not found")
	if inspector_property != null:
		inspector_property.emit_changed("selected_point_lanes_right", 3)
		await _frames(3)
		_check(profile.point_lanes_right == PackedInt32Array([3, 2, 2]), "Inspector did not change the target point")
		profile.select_point_index(1)
		undo.undo()
		await _frames(3)
		_check(profile.point_lanes_right == PackedInt32Array([1, 2, 2]), "Undo changed another point or lost original lanes")
		profile.select_point_index(2)
		undo.redo()
		await _frames(3)
		_check(profile.point_lanes_right == PackedInt32Array([3, 2, 2]), "Redo followed the current selection instead of the edited point")
		undo.undo()
		await _frames(3)

	# Use the native EditorProperty controls, not profile setters, so these
	# regressions include Inspector history hooks and a changed point selection.
	await _check_point_property(profile, undo, "selected_point_tilt", 0.37, "curve_tilt")
	await _check_point_property(profile, undo, "selected_point_lanes_left", 2, "point_lanes_left")
	await _check_point_property(profile, undo, "selected_point_lane_width", 4.25, "point_lane_widths")
	await _check_point_property(profile, undo, "selected_point_lane_transition_length", 17.5, "point_lane_transition_lengths")
	await _check_transition_picker(profile, history, undo)
	await _check_lane_enable(profile, undo)
	await _check_first_lane_enable(profile, history, undo)
	await _check_point_property(profile, undo, "selected_point_width", 9.25, "point_widths", false)
	await _check_merged_lane_width(profile, undo)
	profile.restore_editor_state(initial)
	profile.select_point_index(1)
	EditorInterface.edit_node(profile)
	await _frames(5)

	# Selecting a legacy width handle activates the profile's proper subgizmo.
	var handle: MeshInstance3D = profile.get_node("__WidthHandles/Handle_001")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(handle)
	await _frames(5)
	_check(profile in EditorInterface.get_selection().get_selected_nodes(), "Width handle selection did not activate the profile gizmo")
	var gizmo: EditorNode3DGizmo
	for candidate in profile.get_gizmos():
		if candidate is EditorNode3DGizmo and candidate.get_plugin() == plugin.profile_gizmo:
			gizmo = candidate
	_check(gizmo != null, "Actual editor profile gizmo was not registered")
	if gizmo == null:
		_tree.quit(1)
		return
	_check(gizmo.is_subgizmo_selected(1), "Width handle did not select its control point")
	var gizmo_plugin: EditorNode3DGizmoPlugin = plugin.profile_gizmo
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		var before: Dictionary = profile.capture_editor_state()
		var original: Transform3D = gizmo_plugin._get_subgizmo_transform(gizmo, 1)
		var moved := original
		moved.origin += axis * 3.0
		gizmo_plugin._set_subgizmo_transform(gizmo, 1, moved)
		gizmo_plugin._commit_subgizmos(gizmo, PackedInt32Array([1]), [original], false)
		await _frames(3)
		_check(profile.curve.get_point_position(1).distance_to(before.curve_points[1][0] + axis * 3.0) < 0.001, "Moving a handle did not move its curve point")
		EditorInterface.get_selection().clear()
		undo.undo()
		await _frames(3)
		_check(_same_curve(before, profile.capture_editor_state()), "Native move Undo did not restore source curve")
		undo.redo()
		await _frames(3)
		undo.undo()
		await _frames(3)

	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		var before: Dictionary = profile.capture_editor_state()
		var original: Transform3D = gizmo_plugin._get_subgizmo_transform(gizmo, 1)
		var rotated := original
		rotated.basis = Basis(axis, 0.35) * original.basis
		gizmo_plugin._set_subgizmo_transform(gizmo, 1, rotated)
		gizmo_plugin._commit_subgizmos(gizmo, PackedInt32Array([1]), [original], false)
		await _frames(3)
		for tangent in [1, 2]:
			var actual: Vector3 = profile.curve.get_point_in(1) if tangent == 1 else profile.curve.get_point_out(1)
			var expected: Vector3 = Basis(axis, 0.35) * before.curve_points[1][tangent]
			_check(actual.distance_to(expected) < 0.001, "Gizmo rotation did not rotate the source tangents")
		undo.undo()
		await _frames(3)
		_check(_same_curve(before, profile.capture_editor_state()), "Rotation Undo did not restore tangents around %s" % axis)
		undo.redo()
		await _frames(3)
		undo.undo()
		await _frames(3)
		_check(_same_curve(before, profile.capture_editor_state()), "Rotation Redo/Undo drifted around %s" % axis)

	var cancelled: Dictionary = profile.capture_editor_state()
	var cancel_before: Transform3D = gizmo_plugin._get_subgizmo_transform(gizmo, 1)
	var cancel_after := cancel_before
	cancel_after.origin += Vector3.ONE * 5.0
	gizmo_plugin._set_subgizmo_transform(gizmo, 1, cancel_after)
	gizmo_plugin._commit_subgizmos(gizmo, PackedInt32Array([1]), [cancel_before], true)
	_check(_same_curve(cancelled, profile.capture_editor_state()), "Cancelling a gizmo edit did not restore the curve")

	var multi_before: Dictionary = profile.capture_editor_state()
	var multi_transforms: Array[Transform3D] = []
	for index in [0, 1]:
		multi_transforms.append(gizmo_plugin._get_subgizmo_transform(gizmo, index))
	for index in [0, 1]:
		var moved := multi_transforms[index]
		moved.origin += Vector3(2, 1, 3)
		gizmo_plugin._set_subgizmo_transform(gizmo, index, moved)
	gizmo_plugin._commit_subgizmos(gizmo, PackedInt32Array([0, 1]), multi_transforms, false)
	await _frames(3)
	for index in [0, 1]:
		_check(profile.curve.get_point_position(index).distance_to(multi_before.curve_points[index][0] + Vector3(2, 1, 3)) < 0.001, "Multi-point manipulation drifted")
	undo.undo()
	await _frames(3)
	_check(_same_curve(multi_before, profile.capture_editor_state()), "One Undo did not restore the entire multi-point edit")

	profile.restore_editor_state(initial)
	if not _failed:
		print("ROAD_EDITOR_HISTORY_OK")
	_tree.quit(1 if _failed else 0)


func _find_property(node: Node, property: String) -> EditorProperty:
	if node is EditorProperty and node.get_edited_property() == property:
		return node
	for child in node.get_children():
		var found := _find_property(child, property)
		if found != null:
			return found
	return null


func _check_point_property(profile: Path3D, undo: UndoRedo, property: String, value: Variant, source: String, lanes_enabled := true) -> void:
	var original: Dictionary = profile.capture_editor_state()
	profile.lane_profile_enabled = lanes_enabled
	profile.select_point_index(1)
	EditorInterface.edit_node(profile)
	await _frames(5)
	var before: Dictionary = profile.capture_editor_state()
	var control := _find_property(EditorInterface.get_inspector(), property)
	_check(control != null, "Actual Inspector control missing: %s" % property)
	if control == null:
		profile.restore_editor_state(original)
		return
	var history_position := undo.get_current_action()
	control.emit_changed(property, value)
	await _frames(3)
	var after: Dictionary = profile.capture_editor_state()
	var actual: Variant = after.curve_points[1][3] if source == "curve_tilt" else after[source][1]
	_check(is_equal_approx(float(actual), float(value)), "%s did not change point 1 source data" % property)
	_check(undo.get_current_action() == history_position + 1, "%s did not produce one history action" % property)
	profile.select_point_index(0)
	undo.undo()
	await _frames(3)
	_check(_same_profile(before, profile.capture_editor_state()), "%s Undo did not restore the complete profile" % property)
	profile.select_point_index(2)
	undo.redo()
	await _frames(3)
	_check(_same_profile(after, profile.capture_editor_state()), "%s Redo followed current selection or changed unrelated data" % property)
	undo.undo()
	await _frames(3)
	profile.restore_editor_state(original)
	print("EDITOR_FIELD_OK property=%s" % property)


func _check_lane_enable(profile: Path3D, undo: UndoRedo) -> void:
	profile.select_point_index(1)
	EditorInterface.edit_node(profile)
	await _frames(5)
	for enabled in [false, true]:
		# Preserve populated custom storage across disable/re-enable as well as
		# checking the Inspector's visibility changes for the two workflows.
		profile.lane_profile_enabled = not enabled
		await _frames(5)
		var before: Dictionary = profile.capture_editor_state()
		var control := _find_property(EditorInterface.get_inspector(), "lane_profile_enabled")
		_check(control != null, "Actual lane profile toggle was not found")
		if control == null:
			return
		control.emit_changed("lane_profile_enabled", enabled)
		await _frames(5)
		var after: Dictionary = profile.capture_editor_state()
		_check(profile.lane_profile_enabled == enabled, "Inspector lane toggle was not applied")
		_check((_find_property(EditorInterface.get_inspector(), "selected_point_width") == null) == enabled, "Legacy width visibility did not follow the lane toggle")
		_check((_find_property(EditorInterface.get_inspector(), "selected_point_lane_width") != null) == enabled, "Directional width visibility did not follow the lane toggle")
		profile.select_point_index(0)
		undo.undo()
		await _frames(5)
		_check(_same_profile(before, profile.capture_editor_state()), "Lane toggle Undo lost custom lane storage")
		profile.select_point_index(2)
		undo.redo()
		await _frames(5)
		_check(_same_profile(after, profile.capture_editor_state()), "Lane toggle Redo changed custom lane storage")
		undo.undo()
		await _frames(3)
	profile.lane_profile_enabled = true
	print("EDITOR_FIELD_OK property=lane_profile_enabled directions=2")


func _check_merged_lane_width(profile: Path3D, undo: UndoRedo) -> void:
	profile.select_point_index(1)
	EditorInterface.edit_node(profile)
	await _frames(5)
	var before: Dictionary = profile.capture_editor_state()
	var position := undo.get_current_action()
	for width in [3.75, 4.0, 4.5]:
		var control := _find_property(EditorInterface.get_inspector(), "selected_point_lane_width")
		_check(control != null, "Native width slider disappeared during a merged edit")
		if control == null:
			return
		control.emit_changed("selected_point_lane_width", width, "", width < 4.5)
		await _frames(3)
	_check(undo.get_current_action() == position + 1, "Continuous Inspector edit did not merge into one action")
	var after: Dictionary = profile.capture_editor_state()
	_check(is_equal_approx(profile.point_lane_widths[1], 4.5), "Merged Inspector edit lost its final value")
	profile.select_point_index(0)
	undo.undo()
	await _frames(5)
	_check(_same_profile(before, profile.capture_editor_state()), "One Undo did not recover the merged edit's initial state")
	profile.select_point_index(2)
	undo.redo()
	await _frames(5)
	_check(_same_profile(after, profile.capture_editor_state()), "Merged Redo restored the first intermediate value or another point")
	undo.undo()
	await _frames(3)
	print("EDITOR_FIELD_OK property=selected_point_lane_width merged_updates=3")


func _check_transition_picker(profile: Path3D, history: EditorUndoRedoManager, undo: UndoRedo) -> void:
	profile.select_point_index(1)
	EditorInterface.edit_node(profile)
	await _frames(5)
	var before: Dictionary = profile.capture_editor_state()
	var control := _find_property(EditorInterface.get_inspector(), "selected_point_lane_transition")
	var picker := _find_resource_picker(control)
	_check(picker != null, "Actual transition EditorResourcePicker was not found")
	if picker == null:
		return
	var transition := Curve.new()
	transition.add_point(Vector2.ZERO, 0.0, 0.0)
	transition.add_point(Vector2(0.35, 0.1), 0.3, 0.3)
	transition.add_point(Vector2.ONE, 0.0, 0.0)
	# This is the native resource-picker signal emitted by Load/New/Paste.
	picker.edited_resource = transition
	picker.resource_changed.emit(transition)
	await _frames(5)
	_check(profile.point_lane_transition_curves[1] == transition, "Picker did not assign the actual Curve resource")
	var after: Dictionary = profile.capture_editor_state()
	profile.select_point_index(0)
	undo.undo()
	await _frames(5)
	_check(_same_profile(before, profile.capture_editor_state()), "Transition picker Undo lost the previous Curve identity")
	profile.select_point_index(2)
	undo.redo()
	await _frames(5)
	_check(_same_profile(after, profile.capture_editor_state()), "Transition picker Redo assigned another point or copied its resource")
	# Resource edits have their own native history. Switching point selection
	# must not replace their target resource with a deep-copied snapshot.
	EditorInterface.edit_resource(transition)
	await _frames(5)
	var resource_control := _find_property(EditorInterface.get_inspector(), "max_value")
	_check(resource_control != null, "Transition resource Inspector was not opened")
	if resource_control != null:
		var resource_undo := history.get_history_undo_redo(history.get_object_history_id(transition))
		resource_control.emit_changed("max_value", 1.5)
		await _frames(3)
		_check(is_equal_approx(transition.max_value, 1.5), "Native Curve Inspector did not edit the assigned resource")
		resource_undo.undo()
		await _frames(3)
		_check(is_equal_approx(transition.max_value, 1.0), "Native Curve resource Undo did not restore its range")
		resource_undo.redo()
		await _frames(3)
		_check(is_equal_approx(profile.point_lane_transition_curves[1].max_value, 1.5), "Resource Redo was disconnected from the assigned transition")
		resource_undo.undo()
		await _frames(3)
	EditorInterface.edit_node(profile)
	await _frames(5)
	undo.undo()
	await _frames(5)
	_check(_same_profile(before, profile.capture_editor_state()), "Transition assignment Undo after a resource edit lost the previous resource")
	print("EDITOR_FIELD_OK property=selected_point_lane_transition native_picker=true resource_history=true")


func _check_first_lane_enable(profile: Path3D, history: EditorUndoRedoManager, undo: UndoRedo) -> void:
	var original: Dictionary = profile.capture_editor_state()
	var legacy := original.duplicate()
	legacy.lane_profile_enabled = false
	legacy.point_widths = PackedFloat32Array([6.0, 10.5, 14.0])
	for property in ["point_lanes_left", "point_lanes_right"]:
		legacy[property] = PackedInt32Array()
	for property in ["point_lane_widths", "point_lane_transition_lengths"]:
		legacy[property] = PackedFloat32Array()
	var curves: Array[Curve] = []
	legacy.point_lane_transition_curves = curves
	profile.restore_editor_state(legacy)
	profile.select_point_index(1)
	EditorInterface.edit_node(profile)
	await _frames(5)
	_check(not profile._has_lane_profile_storage(), "First-enable fixture already has lane storage")
	var control := _find_property(EditorInterface.get_inspector(), "lane_profile_enabled")
	_check(control != null, "First-enable Inspector toggle was not found")
	if control == null:
		profile.restore_editor_state(original)
		return
	control.emit_changed("lane_profile_enabled", true)
	await _frames(5)
	var after: Dictionary = profile.capture_editor_state()
	_check(profile.point_lane_widths.size() == 3 and profile.point_lane_transition_curves.size() == 3, "First enable did not seed lanes from legacy widths")
	_check(profile.point_lanes_left[1] + profile.point_lanes_right[1] == 3, "Legacy middle width was not converted to three lanes")
	var seeded_transition: Curve = profile.point_lane_transition_curves[1]
	EditorInterface.edit_resource(seeded_transition)
	await _frames(5)
	var resource_control := _find_property(EditorInterface.get_inspector(), "max_value")
	_check(resource_control != null, "Seeded transition resource Inspector was not found")
	var resource_undo := history.get_history_undo_redo(history.get_object_history_id(seeded_transition))
	if resource_control != null:
		resource_control.emit_changed("max_value", 1.75)
		await _frames(3)
		resource_undo.undo()
		await _frames(3)
	EditorInterface.edit_node(profile)
	await _frames(5)
	undo.undo()
	await _frames(5)
	_check(_same_profile(legacy, profile.capture_editor_state()), "First-enable Undo did not recover empty legacy lane storage")
	undo.redo()
	await _frames(5)
	_check(_same_profile(after, profile.capture_editor_state()), "First-enable Redo replaced seeded transition resources and broke their editor history")
	if resource_control != null:
		resource_undo.redo()
		await _frames(3)
		_check(is_equal_approx(profile.point_lane_transition_curves[1].max_value, 1.75), "Seeded Curve resource Redo no longer affects the road after lane-enable replay")
		resource_undo.undo()
		await _frames(3)
	undo.undo()
	await _frames(3)
	profile.restore_editor_state(original)
	print("EDITOR_FIELD_OK property=lane_profile_enabled legacy_conversion=true seeded_resource_identity=true")


func _find_resource_picker(node: Node) -> EditorResourcePicker:
	if node == null:
		return null
	if node is EditorResourcePicker:
		return node
	for child in node.get_children():
		var found := _find_resource_picker(child)
		if found != null:
			return found
	return null


func _same_profile(a: Dictionary, b: Dictionary) -> bool:
	if not _same_curve(a, b) or a.curve != b.curve:
		return false
	for property in a:
		if property in ["curve", "curve_points"]:
			continue
		if a[property] != b[property]:
			push_error("Profile difference: %s before=%s after=%s" % [property, a[property], b[property]])
			return false
	return true


func _same_curve(a: Dictionary, b: Dictionary) -> bool:
	if a.curve_points.size() != b.curve_points.size():
		return false
	for index in range(a.curve_points.size()):
		for component in range(3):
			if a.curve_points[index][component].distance_to(b.curve_points[index][component]) > 0.001:
				return false
		if absf(a.curve_points[index][3] - b.curve_points[index][3]) > 0.001:
			return false
	return true


func _frames(count: int) -> void:
	for frame in range(count):
		await _tree.process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
