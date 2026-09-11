@tool
extends "./check_road_editor_history.gd"
## Exercises the actual editor's 3D viewport. Does not save the source scene.

var _camera: Camera3D
var _viewport: SubViewport


func run(plugin: EditorPlugin) -> void:
	_tree = plugin.get_tree()
	if DisplayServer.get_name() == "headless":
		push_error("The graphical editor check must run without --headless.")
		_tree.quit(2)
		return
	var scene: Node
	for frame in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "RoadEditingDemo":
			break
		await _tree.process_frame
	if scene == null or scene.name != "RoadEditingDemo":
		push_error("Open addons/scenes/road_editing_demo.tscn for this check.")
		_tree.quit(2)
		return
	EditorInterface.set_main_screen_editor("3D")
	var profile: Path3D = scene.get_node("Route")
	var initial: Dictionary = profile.capture_editor_state()
	var original_orientation: int = profile.road_orientation_mode
	var original_orientation_override: bool = profile.road_orientation_override_enabled
	profile.road_orientation_override_enabled = true
	profile.road_orientation_mode = 1
	var road: Node3D = load("res://addons/scripts/spline_road/road_network_creator.gd").new()
	road.name = "VisualTestRoad"
	road.source_paths.assign([NodePath("../Route")])
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.invert_faces = true
	road.road_orientation_mode = 1
	road.markings_enabled = false
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.35, 0.38, 0.42)
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	asphalt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road.road_material_override = asphalt
	scene.add_child(road)
	road.regenerate()
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = Color(0.1, 0.12, 0.14)
	scene.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	scene.add_child(sun)
	await _frames(20)
	_viewport = EditorInterface.get_editor_viewport_3d(0)
	var original_debug_draw := _viewport.debug_draw
	_viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	_camera = _viewport.get_camera_3d()
	_check(_camera != null, "Editor 3D viewport has no camera")
	if _camera == null:
		_tree.quit(1)
		return
	RenderingServer.frame_pre_draw.connect(_fix_camera)
	var view_menu := _find_view_menu(EditorInterface.get_base_control())
	var original_view_options := {}
	_check(view_menu != null, "Native editor View menu was not found")
	if view_menu != null:
		for option in ["Orthogonal", "Transform Gizmo", "View Grid"]:
			original_view_options[option] = _view_option_checked(view_menu, option)
		_activate_view_option(view_menu, "Orthogonal", true)
		_activate_view_option(view_menu, "Transform Gizmo", false)
		_activate_view_option(view_menu, "View Grid", false)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(profile.get_node("__WidthHandles/Handle_001"))
	await _frames(10)
	var gizmo: EditorNode3DGizmo
	for candidate in profile.get_gizmos():
		if candidate is EditorNode3DGizmo and candidate.get_plugin() == plugin.profile_gizmo:
			gizmo = candidate
	_check(gizmo != null and gizmo.is_subgizmo_selected(1), "Visible control point was not selected by its legacy handle")
	if EditorInterface.get_inspector().has_method("expand_all_folding"):
		EditorInterface.get_inspector().expand_all_folding()
	EditorInterface.inspect_object(profile, "selected_point_lanes_right")
	var before := await _capture_editor("before")
	_check(_colored_pixels(before, false) > 100, "Orange profile preview is missing from the real editor viewport")
	_check(_colored_pixels(before, true) > 5, "Selected cyan control point is missing from the real editor viewport")
	var undo := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(profile))
	var control := _find_property(EditorInterface.get_inspector(), "selected_point_lanes_right")
	_check(control != null, "Selected point lane control is not present in the real editor Inspector")
	if control != null:
		control.emit_changed("selected_point_lanes_right", 4)
		await _frames(5)
		profile.apply_lane_changes()
		road.regenerate()
		var widened := await _capture_editor("widened")
		var changed := _changed_pixels(before, widened)
		_check(changed > 100, "Inspector lane edit did not visibly widen the road in the editor")
		undo.undo()
		await _frames(5)
		road.regenerate()
		var restored := await _capture_editor("undo")
		var restored_difference := _changed_pixels(before, restored)
		_check(restored_difference < 30, "Undo did not visually restore the editor road and its handles")
		undo.redo()
		await _frames(5)
		road.regenerate()
		var redone := await _capture_editor("redo")
		_check(_changed_pixels(widened, redone) < 30, "Redo did not visually restore the widened road")
		print("ROAD_EDITOR_IMAGE changed_pixels=%s undo_difference=%s redo_difference=%s orange_pixels=%s cyan_pixels=%s" % [changed, restored_difference, _changed_pixels(widened, redone), _colored_pixels(before, false), _colored_pixels(before, true)])
	profile.restore_editor_state(initial)
	profile.road_orientation_mode = original_orientation
	profile.road_orientation_override_enabled = original_orientation_override
	RenderingServer.frame_pre_draw.disconnect(_fix_camera)
	_viewport.debug_draw = original_debug_draw
	if view_menu != null:
		for option in original_view_options:
			_activate_view_option(view_menu, option, original_view_options[option])
	EditorInterface.get_selection().clear()
	EditorInterface.edit_node(null)
	await _frames(3)
	road.free()
	world_environment.free()
	sun.free()
	print("ROAD_EDITOR_VISUAL_%s" % ("FAILED" if _failed else "OK"))
	_tree.quit(1 if _failed else 0)


func _fix_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 78.0
	_camera.look_at_from_position(Vector3(70, 75, 90), Vector3(17, 0, 25))


func _find_view_menu(node: Node) -> PopupMenu:
	if node is PopupMenu:
		for index in range(node.item_count):
			if node.get_item_text(index).ends_with("Transform Gizmo"):
				return node
	for child in node.get_children(true):
		var found := _find_view_menu(child)
		if found != null:
			return found
	return null


func _activate_view_option(menu: PopupMenu, text: String, enabled: bool) -> void:
	for index in range(menu.item_count):
		if menu.get_item_text(index) in [text, "View " + text]:
			if menu.is_item_checked(index) != enabled:
				# Orthogonal/Perspective are separate radio entries, not a toggle.
				if text == "Orthogonal" and not enabled:
					_activate_view_option(menu, "Perspective", true)
				else:
					menu.id_pressed.emit(menu.get_item_id(index))
			return
	_check(false, "Native View menu option not found: " + text)


func _view_option_checked(menu: PopupMenu, text: String) -> bool:
	for index in range(menu.item_count):
		if menu.get_item_text(index) in [text, "View " + text]:
			return menu.is_item_checked(index)
	return false


func _capture_editor(label: String) -> Image:
	await _frames(6)
	var inspector := EditorInterface.get_inspector()
	var point_control := _find_property(inspector, "selected_point_lanes_right")
	if point_control != null:
		inspector.ensure_control_visible(point_control)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var rendered := _viewport.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty(), "Actual editor viewport returns pixels")
	_check(rendered.save_png("/tmp/roda-editor-%s.png" % label) == OK, "Editor viewport capture saves")
	var editor_window := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	_check(editor_window.save_png("/tmp/roda-editor-window-%s.png" % label) == OK, "Editor window capture saves")
	return rendered


func _colored_pixels(image: Image, cyan: bool) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if cyan:
				count += int(color.g > 0.5 and color.b > 0.5 and color.r < color.g * 0.65)
			else:
				count += int(color.r > 0.6 and color.g > 0.25 and color.g < color.r * 0.9 and color.b < color.g * 0.6)
	return count


func _changed_pixels(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return 9999999
	var changed := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			changed += int(maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b))) > 0.04)
	return changed
