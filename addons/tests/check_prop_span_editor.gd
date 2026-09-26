@tool
extends RefCounted
## Open the consuming scene with -- --roda-prop-span-tests. Never saves it.
const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")
var checks := 0
var failed := false


func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var scene: Node
	var props: Node3D
	for frame in range(600):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null:
			props = scene.get_node_or_null("SplinePropArray3D") as Node3D
			if props != null and props.has_node("PropSpan/EndHandle"):
				break
		await tree.process_frame
	if props == null or not props.has_node("PropSpan/EndHandle"):
		push_error("Open the scene containing a single-source SplinePropArray3D at its root")
		tree.quit(2)
		return
	var span: Node3D = props.get_node("PropSpan")
	var path: Path3D = span._resolve_target_path()
	var start: Marker3D = span.get_node("StartHandle")
	var end: Marker3D = span.get_node("EndHandle")
	_check(span.owner == scene and start.owner == scene and end.owner == scene,
		"Range and handles belong to the actual edited scene")
	_check(start.is_visible_in_tree() and end.is_visible_in_tree(), "Both markers are visible")
	_check(path == props._resolve_paths()[0], "Range uses the array's explicit source")
	var original := Vector2(span.start_offset, span.end_offset)
	var original_count := props.get_node("GeneratedSplineProps").get_child_count()
	var length := path.curve.get_baked_length()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(start)
	start.global_position = path.to_global(path.curve.sample_baked(length * 0.25, true))
	end.global_position = path.to_global(path.curve.sample_baked(length * 0.65, true))
	for frame in range(10):
		await tree.process_frame
	_check(absf(span.start_offset - length * 0.25) < 0.02 and absf(span.end_offset - length * 0.65) < 0.02,
		"Editor polling consumes the dragged min/max markers")
	_check(EditorInterface.get_selection().get_selected_nodes().has(start), "Start marker remains selected after regeneration")
	_check(props.get_node("GeneratedSplineProps").get_child_count() < original_count, "Dragged range reduces the real scene's fence")
	var signature: String = props._build_signature()
	for frame in range(20):
		await tree.process_frame
	_check(props._build_signature() == signature, "Released markers do not cause repeated generation")
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "Edited scene can be packed in memory")
	var restored := packed.instantiate()
	var restored_span: Node = restored.get_node_or_null("SplinePropArray3D/PropSpan")
	_check(restored_span != null and restored_span.has_node("StartHandle") and restored_span.has_node("EndHandle"),
		"Both handles survive scene serialization")
	if restored_span != null:
		_check(Vector2(restored_span.start_offset, restored_span.end_offset).distance_to(Vector2(span.start_offset, span.end_offset)) < 0.001,
			"Authored range survives scene serialization")
	restored.free()
	# Source assignment after _ready, even with automatic mesh generation off.
	var late := PROPS.new()
	late.generate_in_editor = false
	late.auto_regenerate_in_editor = false
	scene.add_child(late)
	late.owner = scene
	late.source_paths = [late.get_path_to(path)]
	for frame in range(3):
		await tree.process_frame
	_check(late.has_node("PropSpan/EndHandle") and late.get_node("PropSpan/EndHandle").owner == scene,
		"Late Inspector source assignment creates selectable handles")
	late.free()
	span.start_offset = original.x
	span.end_offset = original.y
	span._update_handles_from_offsets()
	props.regenerate()
	print("PROP SPAN EDITOR %s checks=%d original=%d" % ["FAIL" if failed else "PASS", checks, original_count])
	tree.quit(1 if failed else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
