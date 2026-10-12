@tool
extends RefCounted
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const SECTION = preload("../scripts/spline_road/road_lane_section.gd")
var tree: SceneTree
var checks := 0
var failed := false

func run(plugin: EditorPlugin) -> void:
	tree = plugin.get_tree()
	var scene := EditorInterface.get_edited_scene_root()
	var profile: Path3D = scene.get_node("Route")
	profile.curve = Curve3D.new()
	for z in [0.0, -80.0, -160.0]:
		profile.curve.add_point(Vector3(0, 0, z))
		profile.curve.set_point_tilt(profile.curve.point_count - 1, 0.12)
	profile.lane_profile_enabled = true
	for i in range(3):
		profile.set_point_lane_count_at_index(i, true, 1)
		profile.set_point_lane_count_at_index(i, false, 1)
		profile.set_point_lane_width_at_index(i, 3.5)
	profile.apply_lane_changes()
	var road := ROAD.new()
	road.name = "Road"
	road.source_paths.assign([NodePath("../Route")])
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.incremental_generation_enabled = true
	road.debug_generation_logs = false
	road.invert_faces = true
	road.y_offset = 0.25
	road.markings_enabled = true
	scene.add_child(road)
	road.owner = scene
	road.regenerate()
	await _frames(6)
	var before_curve: Variant = profile.curve.get("_data").duplicate(true)
	var before_mesh := _mesh_bytes(road, "GeneratedSplineRoadWelded")
	var editor: RefCounted = plugin.section_editor
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(profile)
	EditorInterface.set_main_screen_editor("3D")
	await _frames(6)
	_check(editor.toolbar.visible, "Section toolbar appears for selected road")
	_check(not editor.toggle.button_pressed, "Normal selection remains default")
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var surface := _input_surface(viewport.get_parent().get_parent())
	_check(surface != null, "Native viewport input surface is available")
	if surface == null:
		tree.quit(1)
		return
	var frame: Dictionary = road.get_path_surface_frame(profile, 40.0)
	_aim(camera, frame)
	var target: Vector3 = frame.center + frame.right * 2.8
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(target)
	var hit: Dictionary = editor.pick(camera, click.position)
	_check(not hit.is_empty(), "Ray picks the banked road asphalt")
	if hit.is_empty():
		tree.quit(1)
		return
	_check(hit.side == 1 and hit.lane == 1 and hit.field == "outer_line_style", "Click resolves lane, side and nearest marking")
	_check(is_equal_approx(hit.start, 0.0) and is_equal_approx(hit.end, 80.0), "Section spans adjacent curve points")
	editor.toggle.button_pressed = true
	surface.gui_input.emit(click)
	await _frames(2)
	_check(editor.popup.visible and not editor.context.is_empty(), "Native viewport click opens section menu")
	_check(profile in selection.get_selected_nodes(), "Section mode preserves path selection")
	_check(is_instance_valid(editor._highlight) and editor._highlight.owner == null, "Selected lane highlight is transient")
	profile.hide()
	_check(editor._highlight.is_visible_in_tree(), "Section highlight remains visible for a hidden source path")
	profile.show()
	var history := plugin.get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(profile))
	var position := undo.get_current_action()
	_menu_action(editor, "bay")
	await _frames(7)
	_check(undo.get_current_action() == position + 1, "Preset produces one native Undo action")
	_check(profile.lane_appearance_overrides.size() == 1, "Bay creates one editable range resource")
	var bay: Resource = profile.lane_appearance_overrides[0]
	_check(bay is SECTION and bay.lane == 2 and bay.side == 1, "Bay is an outer lane on the clicked side")
	_check(is_equal_approx(profile.get_lane_extents_at_offset(0.0).y, 3.5) and is_equal_approx(profile.get_lane_extents_at_offset(80.0).y, 3.5), "Bay tapers back into existing road at both boundaries")
	_check(is_equal_approx(profile.get_lane_extents_at_offset(40.0).y, 7.0), "Bay plateau adds one lane")
	_check(is_equal_approx(profile.get_lane_extents_at_offset(120.0).y, 3.5) and is_equal_approx(profile.get_lane_extents_at_offset(40.0).x, 3.5), "Other section and opposite side stay unchanged")
	_check(profile.curve.get("_data") == before_curve, "Preset preserves curve points, tangents and tilt")
	var bay_mesh := _mesh_bytes(road, "GeneratedSplineRoadWelded")
	_check(bay_mesh != before_mesh and not bay_mesh.is_empty(), "Actual generated asphalt widens")
	var span := _span(profile, bay)
	_check(span != null and span.has_node("StartHandle") and span.has_node("EndHandle"), "Bay gets selectable Start/End handles")
	var start_frame: Dictionary = road.get_path_surface_frame(profile, 0.0)
	_check(span.get_node("StartHandle").global_position.distance_to(start_frame.center + start_frame.right * 3.5 + start_frame.up * 0.12) < 0.002, "Range handles follow the actual banked road even when it is a sibling node")
	selection.clear()
	selection.add_node(road)
	undo.undo()
	await _frames(5)
	_check(profile.lane_appearance_overrides.is_empty(), "Undo after selection change removes bay resource")
	_check(_mesh_bytes(road, "GeneratedSplineRoadWelded") == before_mesh, "Undo restores exact original road geometry")
	undo.redo()
	await _frames(5)
	_check(profile.lane_appearance_overrides[0] == bay, "Redo preserves resource identity")
	_check(_mesh_bytes(road, "GeneratedSplineRoadWelded") == bay_mesh, "Redo restores exact widened road geometry")
	# A local line edit keeps geometry/collision stable and replaces only paint.
	var context: Dictionary = editor.section_context(profile, 40.0, 1, 2, "inner_line_style")
	context.road = road
	var geometry_revision := road.get_terrain_surface_revision()
	var road_mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var paint_before := _mesh_bytes(road, "GeneratedRoadMarkings")
	_check(editor.actions.apply(profile, context, "line:1").is_empty(), "Solid marking action succeeds")
	await _frames(5)
	_check(road.get_node("GeneratedSplineRoadWelded").mesh == road_mesh and road.get_terrain_surface_revision() == geometry_revision, "Marking edit keeps asphalt mesh and geometry revision")
	_check(_mesh_bytes(road, "GeneratedRoadMarkings") != paint_before, "Solid versus dashed visibly changes actual paint mesh")
	_check(profile.lane_appearance_overrides[0].inner_line_style == 1 and bay.inner_line_style == 2, "Marking edit does not mutate resource retained by Undo")
	undo.undo()
	await _frames(5)
	_check(_mesh_bytes(road, "GeneratedRoadMarkings") == paint_before, "Marking Undo restores exact paint")
	_check(profile.lane_appearance_overrides[0] == bay, "Marking Undo restores original resource")
	_check(editor.actions.apply(profile, context, "stop_end").is_empty(), "Optional stop line can be toggled")
	await _frames(4)
	_check(profile.lane_appearance_overrides[0].stop_line_at_end, "Stop line is enabled only for selected lane")
	_check(_mesh_bytes(road, "GeneratedRoadMarkings") != paint_before, "Bay stop line produces visible paint at full width before the taper")
	undo.undo()
	await _frames(4)
	# Endpoint editing updates geometry too, and the incremental cache agrees
	# with a full uncached build after moving the section bounds.
	span = _span(profile, bay)
	span.set_offset(true, 55.0)
	road.regenerate()
	await _frames(4)
	_check(is_equal_approx(profile.get_lane_extents_at_offset(70.0).y, 3.5), "Moving EndHandle trims widened asphalt")
	var moved_mesh := _mesh_bytes(road, "GeneratedSplineRoadWelded")
	_check(moved_mesh != bay_mesh, "Moved endpoint invalidates source geometry cache")
	road.incremental_generation_enabled = false
	road.regenerate()
	_check(_mesh_bytes(road, "GeneratedSplineRoadWelded") == moved_mesh, "Cached and uncached section geometry match exactly")
	road.incremental_generation_enabled = true
	span.set_offset(true, 80.0)
	road.regenerate()
	context = editor.section_context(profile, 40.0, 1, 2, "outer_line_style")
	context.road = road
	_check(editor.actions.apply(profile, context, "lane").is_empty(), "Existing bay can become an additional lane")
	await _frames(4)
	_check(profile.lane_appearance_overrides.size() == 1 and profile.lane_appearance_overrides[0].resource_name == "Additional lane", "Conversion reuses the section instead of stacking lanes")
	undo.undo()
	await _frames(4)
	context = editor.section_context(profile, 40.0, 1, 2, "outer_line_style")
	context.road = road
	_check(editor.actions.apply(profile, context, "remove").is_empty(), "Extra section can be removed from menu")
	await _frames(4)
	_check(profile.lane_appearance_overrides.is_empty() and _mesh_bytes(road, "GeneratedSplineRoadWelded") == before_mesh, "Removing bay restores base road")
	undo.undo()
	await _frames(4)
	# Save/load round trip of the derived range resource, without saving scene.
	var copy: Resource = profile.lane_appearance_overrides[0].duplicate()
	_check(ResourceSaver.save(copy, "user://section.tres") == OK, "Section resource serializes")
	var loaded: Resource = ResourceLoader.load("user://section.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded is SECTION and loaded.geometry_snapshot() == copy.geometry_snapshot() and loaded.snapshot() == copy.snapshot(), "Section shape and paint survive reloading")
	context = editor.section_context(profile, 120.0, -1, 1, "outer_line_style")
	context.road = road
	_check(editor.actions.apply(profile, context, "lane").is_empty(), "Left-side additional lane succeeds")
	await _frames(4)
	_check(is_equal_approx(profile.get_lane_extents_at_offset(120.0).x, 7.0) and is_equal_approx(profile.get_lane_extents_at_offset(120.0).y, 3.5), "Left-side lane only widens the left")
	# Shared boundaries use the paint builder's actual owner, regardless of
	# which side of the line the user clicked.
	var rules_count: int = profile.lane_appearance_overrides.size()
	context = editor.section_context(profile, 40.0, 1, 1, "outer_line_style")
	context.road = road
	_check(editor.actions.apply(profile, context, "line:3").is_empty(), "Inner lane can edit its shared outside separator")
	await _frames(4)
	_check(profile.lane_appearance_overrides.size() == rules_count and profile.lane_appearance_overrides[0].inner_line_style == 3, "Shared separator updates outer lane owner without stacking rules")
	undo.undo()
	await _frames(4)
	context = editor.section_context(profile, 40.0, 1, 1, "inner_line_style")
	context.road = road
	editor.actions.apply(profile, context, "line:1")
	await _frames(4)
	var solid_center := _mesh_bytes(road, "GeneratedRoadMarkings")
	context = editor.section_context(profile, 40.0, -1, 1, "inner_line_style")
	context.road = road
	_check(editor.actions.apply(profile, context, "line:2").is_empty(), "Center marking can be changed from its left side")
	await _frames(4)
	_check(_mesh_bytes(road, "GeneratedRoadMarkings") != solid_center, "Existing right-side override cannot mask the center-line change")
	var center_rule: Resource = profile.lane_appearance_overrides[-1]
	_check(center_rule.start_offset == 0.0 and center_rule.end_offset == 80.0, "Shared marking stays within selected section")
	undo.undo()
	undo.undo()
	await _frames(4)
	if DisplayServer.get_name() != "headless":
		await _capture(profile, road, camera, editor)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	_check(editor.forward_input(camera, escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not editor.toggle.button_pressed, "Escape leaves section mode")
	selection.clear()
	await _frames(3)
	_check(not editor.toolbar.visible, "Section toolbar hides outside road selection")
	# The consuming Canyon scene starts with legacy widths and empty lane arrays.
	profile.lane_appearance_overrides.clear()
	profile.lane_profile_enabled = false
	profile.point_widths = PackedFloat32Array([6, 6, 6])
	profile.point_lanes_left.clear()
	profile.point_lanes_right.clear()
	profile.point_lane_widths.clear()
	profile.point_lane_transition_lengths.clear()
	profile.point_lane_transition_curves.clear()
	var legacy: Dictionary = profile.capture_editor_state()
	context = editor.section_context(profile, 40.0, 1, 1, "outer_line_style")
	context.road = road
	_check(editor.actions.apply(profile, context, "bay").is_empty(), "Legacy-width road accepts a section without manual lane conversion")
	await _frames(4)
	_check(profile.lane_profile_enabled and is_equal_approx(profile.get_width_at_offset(120.0), 6.0), "Automatic conversion preserves the original width outside the section")
	_check(is_equal_approx(profile.get_width_at_offset(40.0), 9.0), "Legacy road gains exactly one lane inside the bay")
	undo.undo()
	await _frames(4)
	_check(profile.capture_editor_state() == legacy and profile.lane_appearance_overrides.is_empty(), "Undo restores legacy mode and its empty authored lane arrays")
	print("ROAD SECTIONS EDITOR %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	tree.quit(1 if failed else 0)

func _menu_action(editor: RefCounted, action: String) -> void:
	for id in editor._menu_actions:
		if editor._menu_actions[id] == action:
			editor.popup.id_pressed.emit(id)
			editor.popup.hide()
			return
	_check(false, "Menu action exists: " + action)

func _span(profile: Path3D, rule: Resource) -> Node:
	var container := profile.get_node_or_null("__LaneAppearanceHandles")
	if container != null:
		for child in container.get_children():
			if child.appearance == rule:
				return child
	return null

func _mesh_bytes(road: Node, name: String) -> PackedByteArray:
	var node := road.get_node_or_null(name)
	if node == null or node.mesh == null:
		return PackedByteArray()
	var arrays := []
	for i in range(node.mesh.get_surface_count()):
		arrays.append(node.mesh.surface_get_arrays(i))
	return var_to_bytes(arrays)

func _aim(camera: Camera3D, frame: Dictionary) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 45.0
	camera.look_at_from_position(frame.center + frame.up * 22 + frame.right.cross(frame.up) * 35, frame.center, frame.up)

func _input_surface(node: Node) -> Control:
	for child in node.get_children():
		if child.get_class() == "Control" and not child.get_signal_connection_list("gui_input").is_empty():
			return child
	return null

func _capture(profile: Path3D, road: Node, camera: Camera3D, editor: RefCounted) -> void:
	var frame: Dictionary = road.get_path_surface_frame(profile, 40.0)
	var fix := _aim.bind(camera, frame)
	RenderingServer.frame_pre_draw.connect(fix)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(profile)
	await _frames(8)
	editor.toggle.button_pressed = true
	editor.context = editor.section_context(profile, 40.0, 1, 2, "inner_line_style")
	editor.context.road = road
	editor._show_highlight()
	await _frames(5)
	await RenderingServer.frame_post_draw
	EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png("/tmp/roda-road-section.png")
	RenderingServer.frame_pre_draw.disconnect(fix)

func _frames(count: int) -> void:
	for i in range(count):
		await tree.process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("ROAD SECTIONS EDITOR: " + message)
