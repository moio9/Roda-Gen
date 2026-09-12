@tool
extends EditorPlugin

const HISTORY = preload("../scripts/spline_road/road_editor_history.gd")
const PROFILE_GIZMO = preload("./road_profile_gizmo.gd")
var profile_gizmo: EditorNode3DGizmoPlugin
var _redirecting_selection := false
const POINT_PROPERTIES := {
	"point_width": "selected_point_width",
	"point_tilt": "selected_point_tilt",
	"lanes_left": "selected_point_lanes_left",
	"lanes_right": "selected_point_lanes_right",
	"lane_width": "selected_point_lane_width",
	"lane_transition_length": "selected_point_lane_transition_length",
	"lane_transition": "selected_point_lane_transition",
}


func _enter_tree() -> void:
	HISTORY.manager = get_undo_redo()
	profile_gizmo = PROFILE_GIZMO.new()
	add_node_3d_gizmo_plugin(profile_gizmo)
	EditorInterface.get_selection().selection_changed.connect(_handle_selection_changed)
	add_undo_redo_inspector_hook_callback(_inspector_history)
	if "--roda-editor-tests" in OS.get_cmdline_user_args():
		_run_editor_tests.call_deferred()
	if "--roda-preset-tests" in OS.get_cmdline_user_args():
		_run_preset_tests.call_deferred()
	if "--roda-editor-visual-tests" in OS.get_cmdline_user_args():
		_run_editor_visual_tests.call_deferred()
	if "--roda-prop-output-tests" in OS.get_cmdline_user_args():
		_run_prop_output_tests.call_deferred()
	if "--roda-terrain-startup-tests" in OS.get_cmdline_user_args():
		_run_terrain_startup_tests.call_deferred()
	if "--roda-topology-output-tests" in OS.get_cmdline_user_args():
		_run_topology_output_tests.call_deferred()
	if "--roda-incremental-workflow-tests" in OS.get_cmdline_user_args():
		_run_incremental_workflow_tests.call_deferred()


func _exit_tree() -> void:
	EditorInterface.get_selection().selection_changed.disconnect(_handle_selection_changed)
	remove_node_3d_gizmo_plugin(profile_gizmo)
	remove_undo_redo_inspector_hook_callback(_inspector_history)
	if HISTORY.manager == get_undo_redo():
		HISTORY.manager = null


func _inspector_history(history: Object, object: Object, property: String, value: Variant) -> void:
	var profile: Node
	var target_property := property
	var index := -1
	if object.has_method("capture_editor_state"):
		if not property in POINT_PROPERTIES.values() and property != "lane_profile_enabled":
			return
		profile = object as Node
		index = int(profile.get("selected_point_index"))
	elif object.has_method("_get_profile") and POINT_PROPERTIES.has(property):
		profile = object.call("_get_profile") as Node
		if profile == null or not profile.has_method("capture_editor_state"):
			return
		index = int(object.get("point_index"))
		target_property = POINT_PROPERTIES[property]
	else:
		return
	var before: Dictionary = profile.capture_editor_state()
	HISTORY.append_profile_change(history, profile, before, target_property, value, index)


func _handle_selection_changed() -> void:
	if _redirecting_selection:
		return
	var selection := EditorInterface.get_selection()
	var selected_handles: Dictionary = {}
	for node in selection.get_selected_nodes():
		if not node.has_method("_get_profile") or not node.has_meta("width_point_index"):
			continue
		var profile: Node = node.call("_get_profile")
		if profile == null or not profile.has_method("get_point_editor_transform"):
			continue
		if not selected_handles.has(profile):
			selected_handles[profile] = []
		selected_handles[profile].append(int(node.get("point_index")))
	if selected_handles.is_empty():
		return
	_redirecting_selection = true
	_redirect_handle_selection.call_deferred(selected_handles)


func _redirect_handle_selection(selected_handles: Dictionary) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	for profile: Node3D in selected_handles:
		if not is_instance_valid(profile):
			continue
		selection.add_node(profile)
		profile.update_gizmos()
		for gizmo in profile.get_gizmos():
			if gizmo is EditorNode3DGizmo and gizmo.get_plugin() == profile_gizmo:
				profile.clear_subgizmo_selection()
				for index in selected_handles[profile]:
					profile.select_point_index(index)
					profile.set_subgizmo_selection(gizmo, index, profile.get_point_editor_transform(index))
				break
		EditorInterface.edit_node(profile)
	_redirecting_selection = false


func _run_editor_tests() -> void:
	var tests: RefCounted = load("res://tools/check_road_editor_history.gd").new()
	await tests.run(self)


func _run_preset_tests() -> void:
	var tests: RefCounted = load("res://tools/check_road_preset_history.gd").new()
	await tests.run(self)


func _run_editor_visual_tests() -> void:
	var tests: RefCounted = load("res://tools/render_road_editor_history.gd").new()
	await tests.run(self)


func _run_prop_output_tests() -> void:
	var tests: RefCounted = load("res://tools/check_prop_output_editor.gd").new()
	await tests.run(self)


func _run_topology_output_tests() -> void:
	var tests: RefCounted = load("res://tools/check_topology_output_editor.gd").new()
	await tests.run(self)


func _run_incremental_workflow_tests() -> void:
	var tests: RefCounted = load("res://tools/check_incremental_workflow_editor.gd").new()
	await tests.run(self)


func _run_terrain_startup_tests() -> void:
	var tests: RefCounted = load("res://tools/check_terrain_startup_selection.gd").new()
	await tests.run(self)
