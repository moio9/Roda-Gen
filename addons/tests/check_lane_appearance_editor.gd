@tool
extends RefCounted
## Open lane_appearance_demo.tscn with -- --roda-lane-appearance-tests. Never saves it.
var failed := false
var checks := 0

func run(plugin: EditorPlugin) -> void:
	var scene := EditorInterface.get_edited_scene_root()
	var road: Node3D = scene.get_node("Road")
	var path: Path3D = scene.get_node("Road/Route")
	var rule: Resource = path.lane_appearance_overrides[0]
	await _settle(plugin, road)
	var initial := _mesh_bytes(road)
	EditorInterface.edit_node(path)
	for i in range(5):
		await plugin.get_tree().process_frame
	EditorInterface.edit_resource(rule)
	for i in range(5):
		await plugin.get_tree().process_frame
	_check(EditorInterface.get_inspector().get_edited_object() == rule, "Lane resource opens in the real Inspector")
	var exposed := {}
	for property in rule.get_property_list():
		exposed[property.name] = property
	_check(exposed.has("stop_line_at_end") and exposed.has("inner_line_style") and exposed.has("surface_material"), "Inspector exposes paint, stop lines and material")
	var manager := plugin.get_undo_redo()
	var property := _find_property(EditorInterface.get_inspector(), "inner_line_style")
	_check(property != null, "Native style control exists")
	if property == null:
		plugin.get_tree().quit(1)
		return
	property.emit_changed("inner_line_style", 0)
	await _settle(plugin, road)
	var changed := _mesh_bytes(road)
	_check(initial != changed, "Resource edit automatically regenerates paint without Apply Lane Changes")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(rule))
	_check(history.undo(), "Lane appearance edit can be undone")
	await _settle(plugin, road)
	_check(_mesh_bytes(road) == initial, "Undo restores exact generated paint")
	_check(history.redo(), "Lane appearance edit can be redone")
	await _settle(plugin, road)
	_check(_mesh_bytes(road) == changed, "Redo restores edited generated paint")
	var before: Object = road.get_node("GeneratedRoadMarkings").mesh
	await plugin.get_tree().create_timer(0.5).timeout
	_check(road.get_node("GeneratedRoadMarkings").mesh == before, "Idle editor does not regenerate repeatedly")
	history.undo()
	await _settle(plugin, road)
	await _check_range_handles(plugin, path, road)
	print("LANE APPEARANCE EDITOR %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	plugin.get_tree().quit(1 if failed else 0)

func _check_range_handles(plugin: EditorPlugin, path: Path3D, road: Node) -> void:
	var container := path.get_node_or_null("__LaneAppearanceHandles")
	_check(container != null, "Range container exists in the scene tree")
	if container == null:
		return
	var span: Node3D = container.get_node("Range_001")
	var start: Node3D = span.get_node("StartHandle")
	var end: Node3D = span.get_node("EndHandle")
	var scene := EditorInterface.get_edited_scene_root()
	_check(span.owner == scene and start.owner == scene and end.owner == scene, "Range markers are saved as selectable scene nodes")
	var original_start: float = span.appearance.start_offset
	var original_end: float = span.appearance.end_offset
	var revision: int = road.get_terrain_surface_revision()
	var before := _mesh_bytes(road)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(start)
	var manager := plugin.get_undo_redo()
	manager.create_action("Move lane appearance start", UndoRedo.MERGE_DISABLE, start)
	manager.add_do_property(start, "position", span.to_local(span._lane_points(25.0)[2]))
	manager.add_undo_property(start, "position", start.position)
	manager.commit_action()
	await _settle(plugin, road)
	_check(absf(span.appearance.start_offset - 25.0) < 0.01, "Start marker projects onto the banked lane")
	_check(EditorInterface.get_selection().get_selected_nodes().has(start), "Dragged marker stays selected")
	_check(span.get_node("__SelectedLane").visible, "Selected interval has a visible lane highlight")
	_check(road.get_terrain_surface_revision() == revision, "Range drag does not regenerate road geometry")
	await _capture_range_controls(plugin)
	var moved_start: float = span.appearance.start_offset
	var moves := manager.get_history_undo_redo(manager.get_object_history_id(start))
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(end)
	moves.undo()
	await _settle(plugin, road)
	_check(span.appearance.start_offset == original_start and _mesh_bytes(road) == before,
		"Native transform Undo restores exact resource value and paint after selection changes")
	moves.redo()
	await _settle(plugin, road)
	_check(span.appearance.start_offset == moved_start, "Native transform Redo restores exact moved distance")
	moves.undo()
	await _settle(plugin, road)
	manager.create_action("Move lane appearance end", UndoRedo.MERGE_DISABLE, end)
	manager.add_do_property(end, "position", span.to_local(span._lane_points(70.0)[2]))
	manager.add_undo_property(end, "position", end.position)
	manager.commit_action()
	await _settle(plugin, road)
	_check(absf(span.appearance.end_offset - 70.0) < 0.01, "End marker updates the resource")
	moves.undo()
	await _settle(plugin, road)
	_check(span.appearance.end_offset == original_end, "Undo preserves End=0 auto-end convention")
	var rules: Array = path.lane_appearance_overrides.duplicate()
	path.lane_appearance_overrides.clear()
	await _settle(plugin, road)
	_check(not container.visible and span.owner == null, "Removed ranges are hidden and excluded from serialization")
	path.lane_appearance_overrides.assign(rules)
	await _settle(plugin, road)
	_check(container.get_node("Range_001") == span and span.owner == scene, "Restoring ranges keeps native history targets alive")
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "Range controls pack with authored scene")
	var restored := packed.instantiate()
	var restored_span: Node = restored.get_node("Road/Route/__LaneAppearanceHandles/Range_001")
	_check(restored_span.appearance == restored.get_node("Road/Route").lane_appearance_overrides[0], "Serialization keeps proxy and path bound to the same resource")
	restored.free()
	await _settle(plugin, road)
	var signature: String = road._build_signature()
	var resource: Mesh = road.get_node("GeneratedRoadMarkings").mesh
	await plugin.get_tree().create_timer(0.5).timeout
	if road._build_signature() != signature:
		var next: String = road._build_signature()
		for i in range(mini(next.length(), signature.length())):
			if next[i] != signature[i]:
				print("RANGE IDLE DIFFERENCE before=", signature.substr(maxi(0, i - 70), 180), " after=", next.substr(maxi(0, i - 70), 180))
				break
	_check(road._build_signature() == signature and road.get_node("GeneratedRoadMarkings").mesh == resource,
		"Released range handles stay idle without projection drift")

func _find_property(node: Node, property: String) -> EditorProperty:
	if node is EditorProperty and node.get_edited_property() == property:
		return node
	for child in node.get_children():
		var found := _find_property(child, property)
		if found != null:
			return found
	return null

func _capture_range_controls(plugin: EditorPlugin) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var fix_camera := func() -> void:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 90.0
		camera.look_at_from_position(Vector3(-38, 58, -8), Vector3(0, 0, -40))
	RenderingServer.frame_pre_draw.connect(fix_camera)
	for i in range(5):
		await plugin.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check(image.save_png("/tmp/roda-lane-range-handles.png") == OK, "Range controls render in editor viewport")
	RenderingServer.frame_pre_draw.disconnect(fix_camera)

func _settle(plugin: EditorPlugin, road: Node) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	for i in range(3):
		await plugin.get_tree().process_frame
	while road.is_road_generation_pending() and Time.get_ticks_msec() < deadline:
		await plugin.get_tree().process_frame
	_check(not road.is_road_generation_pending(), "Editor regeneration settles")

func _mesh_bytes(road: Node) -> PackedByteArray:
	var node := road.get_node_or_null("GeneratedRoadMarkings")
	var arrays := []
	if node != null:
		for surface in range(node.mesh.get_surface_count()):
			arrays.append(node.mesh.surface_get_arrays(surface))
	return var_to_bytes(arrays)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
