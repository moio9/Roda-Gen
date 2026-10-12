@tool
extends RefCounted
## Native editor registration, camera-ray dragging and scene history.
var checks := 0
var failed := false
var tree: SceneTree
var camera: Camera3D
var shape: EditorNode3DGizmoPlugin


func run(plugin: EditorPlugin) -> void:
	tree = plugin.get_tree()
	shape = plugin.shape_gizmo
	var profile: Path3D = EditorInterface.get_edited_scene_root().get_node("Route")
	var initial: Dictionary = profile.capture_editor_state()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 700)
	viewport.own_world_3d = true
	plugin.add_child(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	var history := plugin.get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(profile))
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(profile)
	profile.select_point_index(1)
	await _frames(8)
	var gizmo := _gizmo(profile)
	_check(gizmo != null and profile in selection.get_selected_nodes(), "Shape gizmo registered on selected path")
	if gizmo == null:
		tree.quit(1)
		return
	for projection in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL]:
		camera.projection = projection
		camera.size = 35.0
		for side in [0, 1]:
			var before: Dictionary = profile.capture_editor_state()
			var position := undo.get_current_action()
			var frame: Transform3D = profile.global_transform * profile.get_point_editor_transform(1)
			_aim(frame)
			_drag(gizmo, 3 + side, frame * Vector3(-5 if side == 0 else 5, 0, 0))
			_check(is_equal_approx(profile._get_point_width(1), 10.0), "Width drag follows mouse ray in both projections and from both sides")
			_check(_same_curve(before, profile.capture_editor_state()), "Width drag preserves positions, tangents and tilt")
			shape._commit_handle(gizmo, 3 + side, false, 6.0, false)
			_check(undo.get_current_action() == position + 1, "Continuous drag commits exactly one history action")
			profile.select_point_index(2)
			_check(undo.undo(), "Width drag can be undone after selecting another point")
			_check(profile.capture_editor_state() == before, "Undo restores exact authored profile")
			_check(undo.redo(), "Width drag can be redone")
			_check(is_equal_approx(profile._get_point_width(1), 10.0), "Redo affects original point")
			undo.undo()
			profile.select_point_index(1)
			await _frames(3)
	# Real selectable scene-tree proxy uses the same controls and keeps selection.
	var proxy: Node3D = profile.get_node("__WidthHandles/Handle_001")
	selection.clear()
	selection.add_node(proxy)
	await _frames(5)
	gizmo = _gizmo(proxy)
	_check(gizmo != null and proxy in selection.get_selected_nodes(), "Shape gizmo registered on selected Handle_001")
	if gizmo == null:
		tree.quit(1)
		return
	var before: Dictionary = profile.capture_editor_state()
	var frame: Transform3D = profile.global_transform * profile.get_point_editor_transform(1)
	_aim(frame)
	var target := frame * (Basis(Vector3.BACK, 0.4) * Vector3(0, 5, 0))
	_drag(gizmo, 5, target)
	_check(is_equal_approx(profile.curve.get_point_tilt(1), 0.4), "Tilt drag changes bank by the requested angle")
	_check(_same_curve(before, profile.capture_editor_state(), false), "Tilt keeps source positions and tangents intact")
	shape._commit_handle(gizmo, 5, false, 0.0, false)
	await _frames(4)
	_check(proxy in selection.get_selected_nodes(), "Proxy stays selected after tilt drag")
	profile.select_point_index(2)
	undo.undo()
	_check(profile.capture_editor_state() == before, "Tilt Undo restores exact state after selection change")
	undo.redo()
	_check(is_equal_approx(profile.curve.get_point_tilt(1), 0.4), "Tilt Redo restores original point")
	undo.undo()
	# Cancel must restore data without adding history; crossing center clamps width.
	for kind in [0, 2]:
		before = profile.capture_editor_state()
		var position := undo.get_current_action()
		frame = profile.global_transform * profile.get_point_editor_transform(1)
		_aim(frame)
		_drag(gizmo, 3 + kind, frame * Vector3(5, 5, 0))
		if kind == 0:
			_check(is_equal_approx(profile._get_point_width(1), 0.1), "Width cannot flip after crossing center")
		shape._commit_handle(gizmo, 3 + kind, false, 0.0, true)
		_check(profile.capture_editor_state() == before, "Cancelling restores exact state")
		_check(undo.get_current_action() == position, "Cancelling does not add history")
	# Asymmetric lane layout: edge / lane count gives lane width, not total width.
	profile.lane_profile_enabled = true
	profile.set_point_lane_count_at_index(1, true, 2)
	profile.set_point_lane_count_at_index(1, false, 1)
	profile.set_point_lane_width_at_index(1, 3.5)
	profile.apply_lane_changes()
	await _frames(4)
	for side in [0, 1]:
		before = profile.capture_editor_state()
		frame = profile.global_transform * profile.get_point_editor_transform(1)
		_aim(frame)
		_drag(gizmo, 3 + side, frame * Vector3(-9 if side == 0 else 4.5, 0, 0))
		await _frames(3)
		_check(is_equal_approx(profile._get_point_lane_width(1), 4.5), "Asymmetric lane width uses the dragged side count")
		_check(profile.point_lanes_left == before.point_lanes_left and profile.point_lanes_right == before.point_lanes_right, "Width drag preserves lane counts")
		shape._commit_handle(gizmo, 3 + side, false, 3.5, false)
		_check(not profile.has_pending_lane_changes(), "Releasing lane width applies road changes without an Inspector button")
		undo.undo()
		_check(profile.capture_editor_state() == before, "Lane width Undo restores arrays and resources")
		await _frames(3)
	# Handles follow a rotated, non-uniformly scaled parent without moving the curve.
	profile.lane_profile_enabled = false
	profile.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.7, -0.2)).scaled(Vector3(1.3, 0.8, 1.6)), Vector3(8, 3, -12))
	await _frames(5)
	before = profile.capture_editor_state()
	frame = profile.global_transform * profile.get_point_editor_transform(1)
	_aim(frame)
	_drag(gizmo, 4, frame * Vector3(6, 0, 0))
	_check(is_equal_approx(profile._get_point_width(1), 12.0), "Width drag supports transformed parents")
	shape._commit_handle(gizmo, 4, false, 6.0, true)
	_check(profile.capture_editor_state() == before, "Transformed drag cancellation preserves source curve")
	frame = profile.global_transform * profile.get_point_editor_transform(1)
	_aim(frame)
	_drag(gizmo, 5, frame * (Basis(Vector3.BACK, -0.3) * Vector3(0, 5, 0)))
	_check(is_equal_approx(profile.curve.get_point_tilt(1), -0.3), "Tilt drag supports transformed parents")
	shape._commit_handle(gizmo, 5, false, 0.0, true)
	# A camera looking down the width axis must not cause huge widths/NaNs.
	frame = profile.global_transform * profile.get_point_editor_transform(1)
	camera.look_at_from_position(frame * Vector3(20, 0, 0), frame.origin, (profile.global_basis * Vector3.UP).normalized())
	before = profile.capture_editor_state()
	_drag(gizmo, 4, frame.origin)
	_check(profile.capture_editor_state() == before, "Near-parallel ray leaves width stable")
	shape._commit_handle(gizmo, 4, false, 6.0, true)
	selection.clear()
	profile.transform = Transform3D.IDENTITY
	profile.restore_editor_state(initial)
	await _check_viewport_input(plugin, profile, undo)
	profile.restore_editor_state(initial)
	viewport.queue_free()
	await _frames(3)
	print("ROAD SHAPE EDITOR %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	tree.quit(1 if failed else 0)


func _check_viewport_input(plugin: EditorPlugin, profile: Path3D, undo: UndoRedo) -> void:
	EditorInterface.set_main_screen_editor("3D")
	var selection := EditorInterface.get_selection()
	selection.clear()
	var proxy := profile.get_node("__WidthHandles/Handle_001")
	selection.add_node(proxy)
	await _frames(8)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var surface := _input_surface(viewport.get_parent().get_parent())
	_check(surface != null, "Native editor 3D input surface found")
	if surface == null:
		return
	var native_camera := viewport.get_camera_3d()
	var old_transform := native_camera.global_transform
	var old_projection := native_camera.projection
	var old_size := native_camera.size
	var frame: Transform3D = profile.global_transform * profile.get_point_editor_transform(1)
	native_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	native_camera.size = 30.0
	native_camera.look_at_from_position(frame * Vector3(1, 9, 22), frame.origin, frame.basis.y.normalized())
	var before: Dictionary = profile.capture_editor_state()
	var start := native_camera.unproject_position(frame * Vector3(3, 0, 0))
	var end := native_camera.unproject_position(frame * Vector3(5, 0, 0))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	var history_position := undo.get_current_action()
	surface.gui_input.emit(press)
	var click_release := InputEventMouseButton.new()
	click_release.button_index = MOUSE_BUTTON_LEFT
	click_release.position = start
	surface.gui_input.emit(click_release)
	_check(not shape._drags.has(profile.get_instance_id()), "Click without dragging clears its captured frame")
	_check(undo.get_current_action() == history_position, "Click without dragging does not add Undo history")
	surface.gui_input.emit(press)
	_check(shape._drags.has(profile.get_instance_id()), "Mouse press picks width handle instead of point move gizmo")
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.relative = end - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	surface.gui_input.emit(motion)
	_check(is_equal_approx(profile._get_point_width(1), 10.0), "Native viewport mouse motion widens the road")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = end
	surface.gui_input.emit(release)
	_check(not shape._drags.has(profile.get_instance_id()), "Mouse release commits and clears drag state")
	_check(_same_curve(before, profile.capture_editor_state()), "Native drag does not move or rotate the source point")
	undo.undo()
	_check(profile.capture_editor_state() == before, "Native viewport drag has exact Undo")
	# Tilt uses the same native input path, distinct from point/tangent rotation.
	start = native_camera.unproject_position(frame * Vector3(0, 4, 0))
	end = native_camera.unproject_position(frame * (Basis(Vector3.BACK, 0.35) * Vector3(0, 4, 0)))
	press.position = start
	surface.gui_input.emit(press)
	_check(shape._drags.has(profile.get_instance_id()), "Mouse press picks tilt handle")
	motion.position = end
	motion.relative = end - start
	surface.gui_input.emit(motion)
	_check(is_equal_approx(profile.curve.get_point_tilt(1), 0.35), "Native viewport mouse motion changes tilt")
	release.position = end
	surface.gui_input.emit(release)
	undo.undo()
	_check(profile.capture_editor_state() == before, "Native tilt drag has exact Undo")
	if DisplayServer.get_name() != "headless":
		await _capture_viewport(profile, native_camera, frame)
	native_camera.global_transform = old_transform
	native_camera.projection = old_projection
	native_camera.size = old_size
	selection.clear()
	await _frames(3)


func _capture_viewport(profile: Path3D, native_camera: Camera3D, frame: Transform3D) -> void:
	var road := preload("../scripts/spline_road/road_network_creator.gd").new()
	road.source_paths.assign([NodePath("../Route")])
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.markings_enabled = false
	road.invert_faces = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.28, 0.3)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road.road_material_override = material
	profile.get_parent().add_child(road)
	road.regenerate()
	var fix_camera := _fix_capture_camera.bind(native_camera, frame)
	RenderingServer.frame_pre_draw.connect(fix_camera)
	await _frames(10)
	await RenderingServer.frame_post_draw
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Graphical editor viewport renders shape controls")
	if image != null and not image.is_empty():
		image.save_png("/tmp/roda-shape-handles.png")
	RenderingServer.frame_pre_draw.disconnect(fix_camera)
	road.queue_free()


func _fix_capture_camera(native_camera: Camera3D, frame: Transform3D) -> void:
	native_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	native_camera.size = 24.0
	native_camera.look_at_from_position(frame * Vector3(1, 9, 22), frame.origin, frame.basis.y.normalized())


func _input_surface(node: Node) -> Control:
	# The native viewport owns a plain Control input overlay next to its
	# SubViewportContainer. C++ custom Callables do not expose a method name.
	for child in node.get_children():
		if child.get_class() == "Control" and not child.get_signal_connection_list("gui_input").is_empty():
			return child
	return null


func _drag(gizmo: EditorNode3DGizmo, id: int, world_target: Vector3) -> void:
	shape._begin_handle_action(gizmo, id, false)
	var position := camera.unproject_position(world_target)
	# Repeated events at the same cursor must not compound the edit.
	for i in range(3):
		shape._set_handle(gizmo, id, false, camera, position)


func _aim(frame: Transform3D) -> void:
	camera.look_at_from_position(frame * Vector3(1, 9, 22), frame.origin, frame.basis.y.normalized())


func _gizmo(node: Node3D) -> EditorNode3DGizmo:
	for gizmo in node.get_gizmos():
		if gizmo.get_plugin() == shape:
			return gizmo
	return null


func _same_curve(a: Dictionary, b: Dictionary, include_tilt := true) -> bool:
	for i in range(a.curve_points.size()):
		for component in range(4 if include_tilt else 3):
			if a.curve_points[i][component] != b.curve_points[i][component]:
				return false
	return true


func _frames(count: int) -> void:
	for i in range(count):
		await tree.process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("ROAD SHAPE EDITOR: " + message)
