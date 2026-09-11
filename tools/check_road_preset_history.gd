@tool
extends RefCounted
## Invoked by the real editor plugin with -- --roda-preset-tests.

var _failed := false
var _tree: SceneTree
const CONTROLLER := preload("../addons/scripts/spline_road/road_preset_controller.gd")


func run(plugin: EditorPlugin) -> void:
	_tree = plugin.get_tree()
	var scene: Node
	for i in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "RoadMarkingsDemo":
			break
		await _tree.process_frame
	if scene == null or scene.name != "RoadMarkingsDemo":
		push_error("Open addons/scenes/road_markings_demo.tscn for the preset history check")
		_tree.quit(2)
		return
	var road: Node = scene.get_node("Road")
	var profile: Path3D = road.get_node("Route")
	road.auto_regenerate_in_editor = false
	var before: Dictionary = profile.capture_editor_state()
	var before_material: Material = road.road_material_override
	var before_sidewalk: float = profile.sidewalk_left_width
	_check(road.apply_road_preset(CONTROLLER.BUILTINS[0]) == OK, "mountain preset creates a real editor action")
	var history := plugin.get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(road))
	var mountain: Node = road.get_node(CONTROLLER.NODE_NAME)
	var mountain_material: Material = road.road_material_override
	var sentinel := Node3D.new()
	sentinel.name = "LocallyEditedDetail"
	mountain.add_child(sentinel)
	sentinel.owner = scene
	mountain.get_child(0).height_scale = 1.33
	undo.undo()
	_check(not road.has_node(CONTROLLER.NODE_NAME), "single Undo removes the first preset container")
	_check(profile.capture_editor_state() == before, "single Undo restores original curve and lane arrays")
	_check(road.road_material_override == before_material and profile.sidewalk_left_width == before_sidewalk, "Undo restores original material identity and edges")
	undo.redo()
	_check(road.get_node(CONTROLLER.NODE_NAME) == mountain, "Redo reuses the original preset Nodes")
	_check(road.road_material_override == mountain_material, "Redo restores the same scene-local material")
	_check(mountain.get_node_or_null(NodePath(str(sentinel.name))) == sentinel, "Redo preserves a local detail in the preset container")
	_check(mountain.get_child(0).height_scale == 1.33, "Redo preserves local barrier edits")
	_check(road.apply_road_preset(CONTROLLER.BUILTINS[1]) == OK, "urban preset replaces only preset-owned barriers")
	var urban: Node = road.get_node(CONTROLLER.NODE_NAME)
	_check(urban != mountain and profile.sidewalk_left_width == 2.0, "urban state actually applies")
	undo.undo()
	_check(road.get_node(CONTROLLER.NODE_NAME) == mountain and sentinel.owner == scene, "Undo restores prior container identity and scene ownership")
	undo.redo()
	_check(road.get_node(CONTROLLER.NODE_NAME) == urban and urban.owner == scene, "Redo restores replacement ownership")
	_check(profile.capture_editor_state().curve_points == before.curve_points, "repeated history never moves or tilts source control points")
	for barrier in urban.get_children():
		_check(barrier.owner == scene, "editable barrier belongs to the scene")
		_check(barrier.get_node("StartHandle").owner == scene, "editable span handle belongs to the scene")
		_check(barrier.get_node("GeneratedSplineMeshes").owner == null, "generated heavy mesh is not persisted in source scene")
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "edited source scene packs")
	var file := "/tmp/roda-preset-editor-source-%s.tscn" % Time.get_ticks_usec()
	_check(ResourceSaver.save(packed, file) == OK, "edited source scene saves to a separate test file")
	var reloaded: Node = load(file).instantiate()
	var saved_road: Node = reloaded.get_node("Road")
	_check(saved_road.has_node(CONTROLLER.NODE_NAME), "saved source retains editable preset container")
	var saved_barrier: Node = saved_road.get_node(CONTROLLER.NODE_NAME).get_child(0)
	_check(saved_barrier.get_script() != null and saved_barrier.source_mesh != null, "saved source retains deformer script and module")
	_check(not saved_barrier.has_node("GeneratedSplineMeshes"), "source save does not embed the generated barrier mesh")
	reloaded.free()
	# History can arrive while a later terrain/wall job still owns its snapshots.
	var wall_before: float = profile.outer_wall_height
	profile.outer_wall_height = 0.3
	road.threaded_generation_enabled = true
	road.regenerate()
	_check(road._is_generation_thread_active(), "test starts a pending worker before Undo")
	undo.undo()
	_check(not road._is_generation_thread_active() and not road._thread_regenerate_requested, "Undo cancels/joins the pending worker before restoring settings")
	profile.outer_wall_height = wall_before
	road.threaded_generation_enabled = false
	undo.undo()
	_check(profile.capture_editor_state() == before and not road.has_node(CONTROLLER.NODE_NAME), "two Undos return to original source")
	undo.clear_history()
	print("ROAD_PRESET_HISTORY_%s" % ("FAILED" if _failed else "OK"))
	_tree.quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
