@tool
extends RefCounted
## Real edited-scene ownership/save checks; never saves the source demo scene.

const PROPS = preload("../addons/scripts/spline_road/spline_prop_array.gd")
var failed := false
var checks := 0


class PendingGround:
	extends Node3D
	signal terrain_generation_completed
	var pending := false
	var height := 5.0
	func is_terrain_generation_pending() -> bool:
		return pending
	func get_terrain_height_at_world(_point: Vector3) -> Dictionary:
		return {"hit": true, "normal": Vector3.UP, "y": height}


func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var scene: Node
	for i in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "RoadMarkingsDemo":
			break
		await tree.process_frame
	if scene == null or scene.name != "RoadMarkingsDemo":
		push_error("Open addons/scenes/road_markings_demo.tscn for prop output editor checks")
		tree.quit(2)
		return
	var road: Node = scene.get_node("Road")
	road.auto_regenerate_in_editor = false
	road.threaded_generation_enabled = false
	road.incremental_generation_enabled = true
	for i in range(20):
		await tree.process_frame
	var props := PROPS.new()
	props.name = "RetainedProps"
	props.auto_regenerate_in_editor = false
	props.road_network_source = NodePath("../Road")
	props.source_paths.assign([NodePath("../Road/Route")])
	props.item_mesh = BoxMesh.new()
	props.ranges_mode = 0
	props.avoid_intersections = false
	scene.add_child(props)
	props.owner = scene
	for mode in [0, 1]:
		props.render_mode = mode
		props.persist_generated_in_scene = false
		props.regenerate()
		props.regenerate()
		var nodes := _nodes(props)
		_check(not nodes.is_empty(), "editor fixture generates actual native output")
		var ids := _ids(nodes)
		var generated: Node = props.get_node("GeneratedSplineProps")
		_check(generated.owner == null and _owners_match(nodes, null), "transient output has no scene owner")
		props.persist_generated_in_scene = true
		props.regenerate()
		_check(_ids(_nodes(props)) == ids and props.get_node("GeneratedSplineProps") == generated,
			"persist toggle retains exact native nodes and generated root")
		_check(generated.owner == scene and _owners_match(nodes, scene), "retained output gains actual edited-scene ownership")
		_check_saved(scene, nodes.size())
		props.persist_generated_in_scene = false
		props.regenerate()
		_check(_ids(_nodes(props)) == ids and generated.owner == null and _owners_match(nodes, null),
			"transient toggle removes ownership without recreating output")
		_check_saved(scene, 0)
		props.use_parent_as_generated_root = true
		props.persist_generated_in_scene = true
		props.regenerate()
		nodes = _nodes(props)
		ids = _ids(nodes)
		props.regenerate()
		_check(_ids(_nodes(props)) == ids and _owners_match(nodes, scene), "parent output retains nodes and edited-scene ownership")
		props.persist_generated_in_scene = false
		props.regenerate()
		_check(_ids(_nodes(props)) == ids and _owners_match(nodes, null), "parent output persistence turns off without touching scene root ownership")
		props.use_parent_as_generated_root = false

	var ground := PendingGround.new()
	ground.name = "PendingGround"
	scene.add_child(ground)
	props.render_mode = 0
	props.terrain_height_source = NodePath("../PendingGround")
	props.snap_to_ground_enabled = true
	props.regenerate()
	var before: Transform3D = _nodes(props)[0].transform
	ground.height += 3
	ground.terrain_generation_completed.emit()
	_check(not props.get_placement_rebuild_stats().pending_terrain, "editor automatic regeneration off ignores unsolicited completion")
	props._process(0)
	_check(_nodes(props)[0].transform == before, "auto-off terrain notification does not move output")
	ground.pending = true
	props.regenerate()
	_check(props.get_placement_rebuild_stats().pending_terrain, "explicit editor rebuild can defer with automatic regeneration off")
	ground.pending = false
	ground.terrain_generation_completed.emit()
	props._process(0)
	_check(not props.get_placement_rebuild_stats().pending_terrain and _nodes(props)[0].transform != before,
		"explicit deferred rebuild completes in editor despite auto-off setting")
	props.auto_regenerate_in_editor = true
	props._clear_generated_from_button()
	ground.terrain_generation_completed.emit()
	props._process(0)
	_check(_nodes(props).is_empty(), "Clear Generated is not undone by editor polling or provider completion")
	props.queue_free()
	ground.queue_free()
	for i in range(20):
		await tree.process_frame
	print("PROP_OUTPUT_EDITOR_%s checks=%s" % ["FAILED" if failed else "OK", checks])
	tree.quit(1 if failed else 0)


func _check_saved(scene: Node, count: int) -> void:
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "edited source with retained output packs")
	var file := "/tmp/roda-prop-editor-output-%s.tscn" % Time.get_ticks_usec()
	_check(ResourceSaver.save(packed, file) == OK, "edited source saves to separate test file")
	var restored: Node = load(file).instantiate()
	var output: Node = restored.get_node_or_null("RetainedProps/GeneratedSplineProps")
	_check((output != null and output.get_child_count() == count) if count > 0 else output == null,
		"saved scene embeds exactly the requested generated output")
	restored.free()


func _nodes(props: Node) -> Array[Node]:
	var parent: Node = props.get_parent() if props.use_parent_as_generated_root else props.get_node_or_null("GeneratedSplineProps")
	var result: Array[Node] = []
	if parent != null:
		for child in parent.get_children():
			if props._is_generated_node_for_this_array(child):
				result.append(child)
	return result


func _ids(nodes: Array[Node]) -> Array:
	var result: Array = []
	for node in nodes:
		result.append(node.get_instance_id())
	return result


func _owners_match(nodes: Array[Node], owner: Node) -> bool:
	for node in nodes:
		if node.owner != owner:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
