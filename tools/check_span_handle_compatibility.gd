extends SceneTree
## Exercise native handle conversion/synchronization callbacks. This is not
## physical mouse replay or an editor Undo/Redo test.
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
const SPAN = preload("../addons/scripts/spline_road/spline_prop_span.gd")
const DEFORMER = preload("../addons/scripts/spline_road/spline_mesh_deformer.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var road := ROAD.new()
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.3, 0.0)).scaled(Vector3(-1.2, 0.8, 1.1)), Vector3(20, 4, -10))
	var path := PROFILE.new()
	path.name = "Route"
	path.show_width_preview = false
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, 100))
	path.curve.set_point_tilt(0, 0.2)
	path.curve.set_point_tilt(1, 0.2)
	road.add_child(path)
	root.add_child(road)
	var span := SPAN.new()
	span.target_path = NodePath("../Route")
	span.start_offset = 10
	span.end_offset = 70
	span.show_preview = false
	road.add_child(span)
	_add_callback_fixture_handles(span)
	span._update_handles_from_offsets()
	_check(span.get_node("StartHandle").global_position.distance_to(_world(path, 10)) < 0.001,
		"prop start handle matches transformed path")
	_check(span.get_node("EndHandle").global_position.distance_to(_world(path, 70)) < 0.001,
		"prop end handle matches transformed path")
	span.get_node("StartHandle").global_position = _world(path, 25)
	_check(span._handles_were_moved(), "prop handle drag is detected")
	span._update_offsets_from_handles()
	_check(absf(span.start_offset - 25) < 0.001 and absf(span.end_offset - 70) < 0.001,
		"drag updates source offsets in path metres")
	var saved := Vector2(span.start_offset, span.end_offset)
	for repeat in range(20):
		span._update_handles_from_offsets()
		span._update_offsets_from_handles()
		_check(Vector2(span.start_offset, span.end_offset) == saved and not span._handles_were_moved(),
			"prop offset/handle roundtrip does not drift or retrigger " + str(repeat))
	span.get_node("StartHandle").global_position += Vector3(0.0001, 0, 0)
	_check(not span._handles_were_moved(), "sub-millimetre prop handle noise is ignored")
	span.start_offset = 80
	span.end_offset = 20
	_check(span.get_range_for_path(path).range == Vector2(20, 80), "reversed prop span remains a valid ordered range")
	span.start_offset = -10
	span.end_offset = 150
	_check(span.get_range_for_path(path).range == Vector2(0, 100), "prop range clamps to source curve")
	span.enabled = false
	_check(not span.get_range_for_path(path).ok, "disabled span does not participate")
	span.enabled = true
	span.target_path = NodePath("../Missing")
	_check(not span.get_range_for_path(path).ok, "missing source is rejected without geometry")
	var deformer := DEFORMER.new()
	deformer.source_path = NodePath("../Route")
	deformer.source_mesh = BoxMesh.new()
	deformer.source_mesh.size = Vector3(2, 1, 0.2)
	deformer.start_offset = 10
	deformer.span_length = 30
	deformer.generate_collision = true
	road.add_child(deformer)
	_add_callback_fixture_handles(deformer)
	deformer._update_span_handles_from_values()
	_check(deformer._resolve_curve_span(path) == Vector2(10, 40), "deformer explicit span is preserved")
	_check(deformer.get_node("StartHandle").global_position.distance_to(_world(path, 10)) < 0.001
		and deformer.get_node("EndHandle").global_position.distance_to(_world(path, 40)) < 0.001,
		"deformer handles follow the transformed source")
	deformer.get_node("StartHandle").global_position = _world(path, 60)
	deformer.get_node("EndHandle").global_position = _world(path, 25)
	deformer._update_span_values_from_handles()
	_check(absf(deformer.start_offset - 25) < 0.001 and absf(deformer.span_length - 35) < 0.001,
		"crossed deformer handles normalize start and span length")
	var deformer_saved := Vector2(deformer.start_offset, deformer.span_length)
	for repeat in range(20):
		deformer._update_span_handles_from_values()
		deformer._update_span_values_from_handles()
		_check(Vector2(deformer.start_offset, deformer.span_length) == deformer_saved
			and not deformer._span_handles_were_moved(), "deformer handle roundtrip is stable " + str(repeat))
	deformer.regenerate()
	_check(deformer.is_generated_output_current(), "deformer output is current after handle edit")
	var meshes := 0
	var shapes := 0
	for node: Node in deformer.find_children("*", "", true, false):
		if node is MeshInstance3D and node.mesh != null:
			meshes += int(node.mesh.get_surface_count() > 0)
		if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
			shapes += int(not node.shape.get_faces().is_empty())
	_check(meshes > 0 and shapes > 0, "edited deformer emits real mesh and collision")
	deformer.start_offset = 20
	deformer.span_length = 0
	deformer.end_trim = 10
	_check(deformer._resolve_curve_span(path) == Vector2(20, 90), "zero span uses remaining curve minus end trim")
	deformer.show_span_handles = false
	deformer._sync_span_handles()
	_check(not deformer.get_node("StartHandle").visible and not deformer.get_node("EndHandle").visible,
		"hidden handle option preserves hidden state")
	road.free()
	print("SPAN_HANDLE_COMPATIBILITY_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _add_callback_fixture_handles(parent: Node) -> void:
	# Runtime intentionally creates no handles. This callback-only test supplies
	# stand-ins explicitly; real editor creation is covered by editor tests.
	for label in ["StartHandle", "EndHandle"]:
		var marker := Marker3D.new()
		marker.name = label
		parent.add_child(marker)


func _world(path: Path3D, offset: float) -> Vector3:
	return path.to_global(path.curve.sample_baked(offset, true))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
