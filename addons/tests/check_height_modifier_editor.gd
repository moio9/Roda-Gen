@tool
# Open tests/fixtures/height_modifier_editing.tscn with -- --roda-height-modifier-tests.
extends RefCounted
var tree: SceneTree
var failures := 0
func check(ok: bool, message: String):
	if not ok:
		push_error(message)
		failures += 1
func frames(count: int):
	for i in range(count):
		await tree.process_frame
func find_property(node: Node, property: String) -> EditorProperty:
	if node is EditorProperty and node.get_edited_property() == property:
		return node
	for child in node.get_children():
		var found := find_property(child, property)
		if found != null:
			return found
	return null
func run(plugin: EditorPlugin):
	tree = plugin.get_tree()
	var scene: Node
	for i in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "HeightEditing":
			break
		await tree.process_frame
	if scene == null or scene.name != "HeightEditing":
		push_error("HeightEditing fixture not open")
		tree.quit(2)
		return
	var m = scene.get_node("Modifier")
	EditorInterface.get_selection().add_node(m)
	EditorInterface.edit_node(m)
	m.select_point_index(1)
	await frames(10)
	var history := plugin.get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(m))
	for property in ["selected_point_radius", "selected_point_strength_scale", "selected_point_height_offset"]:
		m.select_point_index(1)
		await frames(5)
		var control := find_property(EditorInterface.get_inspector(), property)
		check(control != null, "Actual Inspector field: " + property)
		if control == null:
			continue
		var initial: Dictionary = m.capture_editor_state()
		control.emit_changed(property, 7.0)
		await frames(5)
		check(is_equal_approx(float(m.get(property)), 7), "Inspector updates selected point")
		m.select_point_index(2)
		undo.undo()
		await frames(5)
		check(m.capture_editor_state() == initial, "Inspector Undo preserves target after selection changes")
		undo.redo()
		await frames(5)
		m.select_point_index(1)
		check(is_equal_approx(float(m.get(property)), 7), "Inspector Redo targets original point")
		undo.undo()
		await frames(5)
	var gizmo: EditorNode3DGizmo
	for candidate in m.get_gizmos():
		if candidate is EditorNode3DGizmo and candidate.get_plugin() == plugin.profile_gizmo:
			gizmo = candidate
	check(gizmo != null, "Native point gizmo registered on height modifier")
	if gizmo != null:
		var original: Transform3D = plugin.profile_gizmo._get_subgizmo_transform(gizmo, 1)
		var restores: Array[Transform3D] = [original]
		var moved := original
		moved.origin.y += 3
		plugin.profile_gizmo._set_subgizmo_transform(gizmo, 1, moved)
		plugin.profile_gizmo._commit_subgizmos(gizmo, PackedInt32Array([1]), restores, false)
		check(m.curve.get_point_position(1).y == original.origin.y + 3, "Native gizmo moves point")
		undo.undo()
		await frames(3)
		check(m.curve.get_point_position(1).y == original.origin.y, "Native gizmo Undo")
		plugin.profile_gizmo._set_subgizmo_transform(gizmo, 1, moved)
		plugin.profile_gizmo._commit_subgizmos(gizmo, PackedInt32Array([1]), restores, true)
		check(m.curve.get_point_position(1).y == original.origin.y, "Native gizmo cancel")
	await frames(5)
	var handles: Node = m.get_node_or_null("__PointHandles")
	check(handles != null and handles.get_child_count() == m.curve.point_count, "One tree node per curve point")
	if handles != null:
		var handle: Node3D = handles.get_node("Handle_001")
		check(handle.owner == scene and handles.owner == scene, "Handles visible in edited scene tree")
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(handle)
		EditorInterface.edit_node(handle)
		await frames(5)
		check(handle in EditorInterface.get_selection().get_selected_nodes(), "Keep selected handle node in Inspector")
		var control := find_property(EditorInterface.get_inspector(), "modifier_height_offset")
		check(control != null, "Handle node exposes its own height setting")
		if control != null:
			var before: Dictionary = m.capture_editor_state()
			control.emit_changed("modifier_height_offset", 11.0)
			await frames(5)
			check(m.point_height_offsets[1] == 11, "Handle Inspector writes matching curve point")
			m.select_point_index(0)
			undo.undo()
			await frames(3)
			check(m.capture_editor_state() == before, "Handle Inspector Undo after changing selection")
			undo.redo()
			await frames(3)
			check(m.point_height_offsets[1] == 11, "Handle Inspector Redo")
			undo.undo()
			await frames(3)
		# Simulate native Node3D transform history, including rotations out of XZ.
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
			m.curve.set_point_out(1, Vector3(1, 2, 3))
			await frames(3)
			var before: Dictionary = m.capture_editor_state()
			var original: Transform3D = handle.transform
			var moved := original
			moved.origin += axis * 3
			moved.basis = Basis(axis, 0.3) * moved.basis
			history.create_action("Move height handle", UndoRedo.MERGE_DISABLE, handle)
			history.add_do_property(handle, "transform", moved)
			history.add_undo_property(handle, "transform", original)
			history.commit_action()
			await frames(5)
			check(m.curve.get_point_position(1).is_equal_approx(before.curve_points[1][0] + axis * 3), "Node transform moves source curve")
			check(handle.transform.is_equal_approx(moved), "Node transform stable during idle editor frames")
			undo.undo()
			await frames(5)
			check(m.curve.get_point_position(1).is_equal_approx(before.curve_points[1][0]), "Node translation Undo")
			check(m.curve.get_point_out(1).is_equal_approx(before.curve_points[1][2]), "Node tangent rotation Undo")
			undo.redo()
			await frames(5)
			check(handle.transform.is_equal_approx(moved), "Node transform Redo")
			undo.undo()
			await frames(3)
		var original_count: int = m.curve.point_count
		m.curve.add_point(Vector3(20, 0, 0))
		await frames(3)
		check(handles.get_child_count() == original_count + 1, "New curve point creates handle")
		m.curve.remove_point(original_count)
		await frames(3)
		check(handles.get_child_count() == original_count, "Removed curve point removes handle")
		EditorInterface.get_selection().clear()
		m.remove_child(handles)
		handles.queue_free()
		await frames(3)
		check(m.get_node("__PointHandles").get_child_count() == original_count, "Missing helper container is restored without a shape edit")
	print("HEIGHT EDITOR failures=", failures)
	tree.quit(failures)
