extends SceneTree
const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")
const SPAN = preload("../scripts/spline_road/spline_prop_span.gd")
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := Node3D.new()
	road.name = "Road"
	world.add_child(road)
	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, -20))
	road.add_child(path)
	var props := PROPS.new()
	props.source_paths = [NodePath("../Road/Path")]
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.2, 1, 2)
	props.fit_segments_to_path = true
	props.placement_mode = 1
	props.spacing = 2
	props.avoid_intersections = false
	world.add_child(props)
	var span := props.get_node_or_null("PropSpan") as Node3D
	_check(span != null, "Single explicit sibling source creates default span")
	if span == null:
		world.free()
		quit(1)
		return
	_check(span._resolve_target_path() == path, "Span targets the same road as the array")
	_check(is_equal_approx(span.end_offset, 20.0), "Default range covers full path")
	_check(span.get_node("StartHandle").global_position.distance_to(path.to_global(Vector3.ZERO)) < 0.001, "Start handle lies on source start")
	_check(span.get_node("EndHandle").global_position.distance_to(path.to_global(Vector3(0, 0, -20))) < 0.001, "End handle lies on source end")
	_check(props.get_node("GeneratedSplineProps").get_child_count() == 10, "Default span retains full connected fence")
	span.get_node("StartHandle").global_position = path.to_global(Vector3(0, 0, -4))
	span.get_node("EndHandle").global_position = path.to_global(Vector3(0, 0, -10))
	span._update_offsets_from_handles()
	props.regenerate()
	_check(absf(span.start_offset - 4) < 0.001 and absf(span.end_offset - 10) < 0.001, "Dragging endpoints updates min/max offsets")
	_check(props.get_node("GeneratedSplineProps").get_child_count() == 3, "Dragged span limits connected fence length")
	var signature: String = props._build_signature()
	for repeat in range(20):
		props._ensure_default_span()
		span._update_offsets_from_handles()
	_check(props._build_signature() == signature and props.get_node("PropSpan") == span, "Stationary handles retain range, identity and signature")
	props.fit_segments_to_path = false
	props.regenerate()
	_check(props.get_node("GeneratedSplineProps").get_child_count() == 4, "Span also limits independent props")
	var nested := PROPS.new()
	path.add_child(nested)
	_check(nested.source_paths == [NodePath("..")] and nested.get_node("PropSpan")._resolve_target_path() == path, "Direct Path3D child keeps automatic source and handles")
	var late := PROPS.new()
	world.add_child(late)
	_check(not late.has_node("PropSpan"), "No guessed span before a source is assigned")
	late.source_paths = [NodePath("../Road/Path")]
	late.regenerate()
	_check(late.has_node("PropSpan"), "Assigning Source Paths after ready creates handles on regeneration")
	var other := path.duplicate() as Path3D
	other.name = "Other"
	for child in other.get_children():
		child.free()
	road.add_child(other)
	var explicit := PROPS.new()
	explicit.source_paths = [NodePath("../../Other")]
	path.add_child(explicit)
	_check(explicit.get_node("PropSpan")._resolve_target_path() == other, "Explicit source overrides parent path")
	for config in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		var manual := PROPS.new()
		manual.source_paths = [NodePath("../Road/Path")]
		manual.ranges_mode = config.x
		manual.range_source_mode = config.y
		manual.distance_ranges = PackedVector2Array([Vector2(2, 8)])
		world.add_child(manual)
		_check(not manual.has_node("PropSpan") and manual.distance_ranges == PackedVector2Array([Vector2(2, 8)]), "Authored manual/disabled/excluded range semantics remain unchanged " + str(config))
	var multi := PROPS.new()
	multi.source_paths = [NodePath("../Road/Path"), NodePath("../Road/Other")]
	world.add_child(multi)
	_check(not multi.has_node("PropSpan"), "Multiple sources do not get an ambiguous automatic span")
	var authored := PROPS.new()
	authored.source_paths = [NodePath("../Road/Path")]
	var custom := SPAN.new()
	custom.name = "CustomRange"
	custom.target_path = NodePath("../../Road/Path")
	custom.start_offset = 3
	custom.end_offset = 9
	authored.add_child(custom)
	world.add_child(authored)
	_check(not authored.has_node("PropSpan") and custom.start_offset == 3 and custom.end_offset == 9, "Saved custom spans are preserved")
	world.free()
	print("PROP DEFAULT SPAN %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
