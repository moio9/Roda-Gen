@tool
extends RefCounted
## Explicit toolbar mode: normal viewport selection/navigation stays native.
const ACTIONS = preload("./road_section_actions.gd")
const SECTION = preload("../scripts/spline_road/road_lane_section.gd")
var actions := ACTIONS.new()
var toolbar: HBoxContainer
var toggle: Button
var status: Label
var popup: PopupMenu
var plugin: EditorPlugin
var context: Dictionary = {}
var _paths: Array[Path3D] = []
var _road_by_path: Dictionary = {}
var _highlight: MeshInstance3D
var _menu_actions: Dictionary = {}
var _left_captured := false
var curve_warnings := preload("./road_curve_warning_view.gd").new()


func setup(owner_plugin: EditorPlugin) -> void:
	plugin = owner_plugin
	toolbar = HBoxContainer.new()
	toggle = Button.new()
	toggle.text = "Road Sections"
	toggle.toggle_mode = true
	toggle.tooltip_text = "Click a lane to add a lane/bay or change its nearest marking. Escape leaves section editing."
	toggle.toggled.connect(_mode_changed)
	toolbar.add_child(toggle)
	curve_warnings.setup(plugin, toolbar)
	status = Label.new()
	status.text = "Click a lane to edit its section"
	toolbar.add_child(status)
	status.hide()
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
	popup = PopupMenu.new()
	popup.name = "RoadSectionMenu"
	popup.id_pressed.connect(_menu_selected)
	plugin.add_child(popup)
	selection_changed()


func cleanup() -> void:
	curve_warnings.cleanup()
	_clear_highlight()
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
	toolbar.queue_free()
	popup.queue_free()


func selection_changed() -> void:
	_paths.clear()
	_road_by_path.clear()
	for selected in EditorInterface.get_selection().get_selected_nodes():
		var node: Node = selected
		while node != null:
			if node is Path3D and node.has_method("get_lane_section_geometry"):
				_add_path(node)
				break
			if node.has_method("get_path_surface_frame") and node.has_method("_resolve_paths"):
				for path in node._resolve_paths():
					_add_path(path, node)
				break
			node = node.get_parent()
	toolbar.visible = not _paths.is_empty()
	curve_warnings.select_paths(_paths, _road_by_path)
	if _paths.is_empty():
		toggle.set_pressed_no_signal(false)
		status.hide()
	_clear_highlight()
	context.clear()
	popup.hide()


func _add_path(path: Path3D, road: Node = null) -> void:
	if not path.has_method("get_lane_section_geometry") or path in _paths:
		return
	_paths.append(path)
	if road == null:
		var root := EditorInterface.get_edited_scene_root()
		road = _find_road(root, path) if root != null else null
	_road_by_path[path.get_instance_id()] = road


func _find_road(node: Node, path: Path3D) -> Node:
	if node.has_method("get_path_surface_frame") and path in node._resolve_paths():
		return node
	for child in node.get_children():
		var found := _find_road(child, path)
		if found != null:
			return found
	return null


func _mode_changed(active: bool) -> void:
	status.visible = active
	status.text = "Click a lane to edit its section"
	if not active:
		_left_captured = false
		_clear_highlight()
		popup.hide()
		context.clear()


func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not toggle.button_pressed or not toolbar.visible:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle.button_pressed = false
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.alt_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not event.pressed:
		var captured := _left_captured
		_left_captured = false
		return EditorPlugin.AFTER_GUI_INPUT_STOP if captured else EditorPlugin.AFTER_GUI_INPUT_PASS
	_left_captured = true
	context = pick(camera, event.position)
	if context.is_empty():
		_clear_highlight()
		status.text = "Click the asphalt of the selected road"
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	_show_highlight()
	_open_menu()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


func pick(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var nearest := INF
	var result := {}
	for path in _paths:
		if not is_instance_valid(path) or path.curve == null or path.curve.point_count < 2:
			continue
		var road: Node = _road_by_path.get(path.get_instance_id())
		var length := path.curve.get_baked_length()
		var count := clampi(ceili(length / 1.5), 2, 8192)
		var previous := _cross_section(path, road, 0.0)
		for i in range(1, count + 1):
			var distance := length * i / count
			var current := _cross_section(path, road, distance)
			for triangle in [[previous.left, previous.right, current.left], [current.left, previous.right, current.right]]:
				var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, triangle[0], triangle[1], triangle[2])
				if hit == null or origin.distance_squared_to(hit) >= nearest:
					continue
				var segment: Vector3 = current.center - previous.center
				var weight := clampf((hit - previous.center).dot(segment) / maxf(0.00001, segment.length_squared()), 0.0, 1.0)
				var offset := lerpf(length * (i - 1) / count, distance, weight)
				var frame := _cross_section(path, road, offset)
				var lateral: float = (hit - frame.center).dot(frame.right_axis) / maxf(0.00001, frame.right_axis.length_squared())
				var side := -1 if lateral < 0.0 else 1
				var layout: Dictionary = path.get_lane_layout_at_offset(offset)
				var width := maxf(0.01, float(layout.lane_width))
				var lane := clampi(ceili(absf(lateral) / width), 1, 12) if path.lane_profile_enabled else 1
				var extent: float = layout.left_extent if side < 0 else layout.right_extent
				var inner := (lane - 1) * width if path.lane_profile_enabled else 0.0
				var outer := minf(lane * width, extent) if path.lane_profile_enabled else extent
				var field := "inner_line_style" if absf(lateral) - inner < outer - absf(lateral) else "outer_line_style"
				result = section_context(path, offset, side, lane, field)
				result.road = road
				nearest = origin.distance_squared_to(hit)
			previous = current
	return result


func section_context(path: Path3D, offset: float, side: int, lane: int, field: String) -> Dictionary:
	var length := path.curve.get_baked_length()
	var offsets: PackedFloat32Array = path._control_point_offsets()
	if path.curve.closed:
		offsets.append(length)
	var start := 0.0
	var end := length
	for i in range(1, offsets.size()):
		if offset <= offsets[i]:
			start = offsets[i - 1]
			end = offsets[i]
			break
	var index := -1
	for i in range(path.lane_appearance_overrides.size() - 1, -1, -1):
		var rule: Resource = path.lane_appearance_overrides[i]
		if rule == null or not rule.enabled or rule.side != side or rule.lane != lane:
			continue
		var rule_end := minf(rule.end_offset, length) if rule.end_offset > 0.0 else length
		if rule.start_offset <= offset and offset < rule_end:
			start = maxf(0.0, rule.start_offset)
			end = rule_end
			index = i
			break
	return {"profile": path, "start": start, "end": end, "offset": offset, "side": side, "lane": lane,
		"field": field, "appearance_index": index}


func _cross_section(path: Path3D, road: Node, offset: float) -> Dictionary:
	var frame: Dictionary = road.get_path_surface_frame(path, offset) if is_instance_valid(road) else {}
	var transform := path.global_transform * path.curve.sample_baked_with_rotation(offset, true, true)
	var center: Vector3 = frame.get("center", transform.origin)
	var right: Vector3 = frame.get("right", -transform.basis.x)
	var up: Vector3 = frame.get("up", transform.basis.y)
	var extents: Vector2 = path.get_lane_extents_at_offset(offset)
	return {"center": center, "right_axis": right, "up": up,
		"left": center - right * extents.x, "right": center + right * extents.y}


func _open_menu() -> void:
	popup.clear()
	_menu_actions.clear()
	var side := "Left" if context.side < 0 else "Right"
	var line := "inner line" if context.field == "inner_line_style" else "outer line"
	status.text = "%s lane %d · %.1f–%.1f m · %s" % [side, context.lane, context.start, context.end, line]
	popup.add_separator(status.text)
	_item("Add lane on this side", "lane")
	_item("Stopping bay on this side", "bay")
	var rules: Array = context.profile.lane_appearance_overrides
	var rule: Resource = rules[context.appearance_index] if context.appearance_index >= 0 else null
	if rule is SECTION:
		_item("Remove this extra lane / bay", "remove")
	popup.add_separator("Selected marking: " + line)
	for pair in [["Solid", "line:1"], ["Dashed", "line:2"], ["No marking", "line:0"], ["Double solid", "line:3"], ["Inherit road style", "line:-1"]]:
		_item(pair[0], pair[1])
	popup.add_separator("Across this lane")
	_item("Stop line at start", "stop_start", true, rule != null and rule.stop_line_at_start)
	_item("Stop line at end", "stop_end", true, rule != null and rule.stop_line_at_end)
	popup.position = DisplayServer.mouse_get_position()
	popup.popup()


func _item(label: String, action: String, checkbox := false, checked := false) -> void:
	var id := _menu_actions.size()
	_menu_actions[id] = action
	if checkbox:
		popup.add_check_item(label, id)
		popup.set_item_checked(popup.get_item_index(id), checked)
	else:
		popup.add_item(label, id)


func _menu_selected(id: int) -> void:
	if context.is_empty() or not _menu_actions.has(id):
		return
	var error := actions.apply(context.profile, context, _menu_actions[id])
	status.text = error if not error.is_empty() else "Section updated · click another lane or line"
	_clear_highlight()


func _show_highlight() -> void:
	_clear_highlight()
	var profile: Path3D = context.profile
	var vertices := PackedVector3Array()
	var count := clampi(ceili((context.end - context.start) / 1.5), 1, 1024)
	var previous := PackedVector3Array()
	for i in range(count + 1):
		var offset := lerpf(context.start, context.end, float(i) / count)
		var frame := _cross_section(profile, context.get("road"), offset)
		var layout: Dictionary = profile.get_lane_layout_at_offset(offset)
		var extent: float = layout.left_extent if context.side < 0 else layout.right_extent
		var inner := minf(extent, (context.lane - 1) * layout.lane_width)
		var outer := minf(extent, context.lane * layout.lane_width)
		if not profile.lane_profile_enabled:
			inner = 0.0
			outer = extent
		var points := PackedVector3Array([frame.center + frame.up * 0.12 + frame.right_axis * context.side * inner,
			frame.center + frame.up * 0.12 + frame.right_axis * context.side * outer])
		if not previous.is_empty():
			for point in [previous[0], previous[1], points[0], points[0], previous[1], points[1]]:
				vertices.append(profile.to_local(point))
		previous = points
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.1, 0.8, 1.0, 0.35)
	mesh.surface_set_material(0, material)
	_highlight = MeshInstance3D.new()
	_highlight.mesh = mesh
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Source paths may be hidden while their generated road remains visible.
	# Keep this transient overlay independent of the source's visibility/parent.
	_highlight.top_level = true
	EditorInterface.get_edited_scene_root().add_child(_highlight)
	_highlight.global_transform = profile.global_transform # No owner: never saved.


func _clear_highlight() -> void:
	if is_instance_valid(_highlight):
		_highlight.queue_free()
	_highlight = null
