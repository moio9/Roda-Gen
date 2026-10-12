extends SceneTree
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")
const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")
const SPAN = preload("../scripts/spline_road/spline_prop_span.gd")
const DEFORMER = preload("../scripts/spline_road/spline_mesh_deformer.gd")
const MODIFIER = preload("../scripts/spline_road/terrain_height_modifier.gd")
const APPEARANCE = preload("../scripts/spline_road/road_lane_appearance.gd")
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source := Node3D.new()
	var path := PROFILE.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, -20))
	path.point_widths = PackedFloat32Array([4, 8])
	var rule := APPEARANCE.new()
	rule.start_offset = 4
	rule.end_offset = 10
	path.lane_appearance_overrides.append(rule)
	source.add_child(path)
	_preview(path, "__WidthHandles")
	_preview(path, "__LaneAppearanceHandles")
	var props := PROPS.new()
	props.name = "Props"
	props.source_paths = [NodePath("../Path")]
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.2, 1, 2)
	props.fit_segments_to_path = true
	props.spacing = 2
	props.avoid_intersections = false
	source.add_child(props)
	var span := SPAN.new()
	span.name = "PropSpan"
	span.target_path = NodePath("../../Path")
	span.start_offset = 4
	span.end_offset = 10
	props.add_child(span)
	for name in ["StartHandle", "EndHandle", "__SpanPreview"]:
		_preview(span, name)
	var deformer := DEFORMER.new()
	deformer.name = "Deformer"
	deformer.source_path = NodePath("../Path")
	deformer.source_mesh = BoxMesh.new()
	deformer.start_offset = 4
	deformer.span_length = 6
	source.add_child(deformer)
	_preview(deformer, "StartHandle")
	_preview(deformer, "EndHandle")
	var modifier := MODIFIER.new()
	modifier.name = "Modifier"
	modifier.curve = path.curve.duplicate()
	modifier.point_height_offsets = PackedFloat32Array([2, 3])
	source.add_child(modifier)
	_preview(modifier, "__PointHandles")
	_preview(source, "UserDecoration")
	_owners(source, source)
	var packed := PackedScene.new()
	_check(packed.pack(source) == OK, "Fixture packs saved visible editor helpers")
	source.free()
	var runtime := packed.instantiate()
	_check(runtime.has_node("Props/PropSpan/StartHandle"), "Fixture really contains saved helpers before entering tree")
	root.add_child(runtime)
	path = runtime.get_node("Path")
	props = runtime.get_node("Props")
	span = props.get_node("PropSpan")
	deformer = runtime.get_node("Deformer")
	modifier = runtime.get_node("Modifier")
	_no_handles(runtime)
	_check(not span.is_processing() and not path.is_processing() and not modifier.is_processing(), "Editor-only polling is disabled at runtime")
	_check(span.start_offset == 4 and span.end_offset == 10, "Prop interval is preserved")
	_check(props.get_node("GeneratedSplineProps").get_child_count() == 3, "Runtime still generates the authored fence interval")
	_check(deformer.start_offset == 4 and deformer.span_length == 6 and deformer.has_node("GeneratedSplineMeshes"), "Deformed output and interval remain available")
	_check(path.point_widths == PackedFloat32Array([4,8]) and path.lane_appearance_overrides[0].start_offset == 4, "Road width and lane appearance data survive cleanup")
	_check(modifier.point_height_offsets == PackedFloat32Array([2,3]), "Terrain modifier data survives cleanup")
	_check(runtime.has_node("UserDecoration") and runtime.get_node("UserDecoration").visible, "Unrelated authored visuals remain untouched")
	span._ensure_handles()
	deformer._ensure_span_handles()
	props.regenerate()
	deformer.regenerate()
	_no_handles(runtime)
	await process_frame
	_no_handles(runtime)
	# A runtime-created default span also has data only.
	var fresh := PROPS.new()
	fresh.source_paths = [NodePath("../Path")]
	fresh.item_mesh = BoxMesh.new()
	runtime.add_child(fresh)
	_check(fresh.has_node("PropSpan") and fresh.get_node("PropSpan").get_child_count() == 0, "New runtime spans never create controls or preview meshes")
	runtime.free()
	print("RUNTIME EDITOR HANDLES %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)

func _preview(parent: Node, label: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = BoxMesh.new()
	parent.add_child(mesh)

func _owners(node: Node, scene: Node) -> void:
	for child in node.get_children():
		child.owner = scene
		_owners(child, scene)

func _no_handles(scene: Node) -> void:
	for path in ["Path/__WidthHandles", "Path/__LaneAppearanceHandles", "Modifier/__PointHandles",
		"Props/PropSpan/StartHandle", "Props/PropSpan/EndHandle", "Props/PropSpan/__SpanPreview",
		"Deformer/StartHandle", "Deformer/EndHandle"]:
		_check(not scene.has_node(path), "Runtime tree has no " + path)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
