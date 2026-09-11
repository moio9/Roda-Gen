extends SceneTree

const DEMO := preload("../addons/scenes/road_markings_demo.tscn")
const CONTROLLER := preload("../addons/scripts/spline_road/road_preset_controller.gd")
const PRESET := preload("../addons/scripts/spline_road/road_preset.gd")
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := DEMO.instantiate()
	root.add_child(scene)
	var road: Node3D = scene.get_node("Road")
	var path: Path3D = road.get_node("Route")
	var original_curve: Array = path.capture_editor_state().curve_points
	var manual := Node3D.new()
	manual.name = "ManualFurniture"
	road.add_child(manual)
	var previous_material: Material
	var barrier_counts: Array[int] = []
	for index in range(3):
		var preset: Resource = CONTROLLER.BUILTINS[index]
		road.preset_selection = index
		_check(road.apply_road_preset() == OK, "builtin applies: " + preset.display_name)
		_check(path.capture_editor_state().curve_points == original_curve, "preset leaves positions, tangents and tilts intact")
		_check(path.lane_profile_enabled, "preset enables editable directional lanes")
		_check(is_equal_approx(path.default_lane_width, preset.lane_width), "lane width is applied")
		_check(path.point_lanes_left[1] == preset.lanes_left and path.point_lanes_right[1] == preset.lanes_right, "per-point lanes are replaced")
		_check(is_equal_approx(path.point_lane_transition_lengths[1], preset.lane_transition_length), "transition distances apply")
		_check(path.point_lane_transition_curves[1] != preset.lane_transition_curve, "point easing is not the template resource")
		_check(path.point_lane_transition_curves[1] != path.point_lane_transition_curves[2], "points have independently editable easing")
		_check(is_equal_approx(path.sidewalk_left_width, preset.sidewalk_left_width), "path edges receive preset widths")
		_check(is_equal_approx(road.road_width, (preset.lanes_left + preset.lanes_right) * preset.lane_width), "plain-path width fallback applies")
		_check(road.road_material_override != preset.road_material_override, "road material is a local copy")
		_check(road.road_material_override != previous_material, "preset application uses fresh material instances")
		_check(is_instance_valid(manual) and manual.get_parent() == road, "manual siblings survive")
		previous_material = road.road_material_override
		var container: Node = road.get_node(CONTROLLER.NODE_NAME)
		barrier_counts.append(container.get_child_count())
		_check(container.get_child_count() == (2 if index == 2 else 1), "correct outer/center barrier count")
		for barrier in container.get_children():
			_check(barrier._get_source_path() == path, "barrier resolves the unchanged source path")
			_check(barrier.source_mesh.get_surface_count() > 0, "barrier source module is generated")
			_check(barrier._last_generated_vertex_count > 0, "barrier is actually deformed")
			_check(barrier.start_offset >= preset.barrier_end_clearance, "barrier respects endpoint clearance")
			_check(barrier._last_signature == barrier._build_signature(), "barrier finishes current")
		_check_bake(road, index)
		# Editing local output never mutates the template or gets reset on regenerate.
		var original_color: Color = preset.road_material_override.albedo_color
		road.road_material_override.albedo_color = Color(0.15, 0.05, 0.07)
		var barrier: Node = container.get_child(0)
		barrier.height_scale = 1.25
		barrier.start_offset += 1.0
		road.regenerate()
		_check(preset.road_material_override.albedo_color == original_color, "template material stays unchanged")
		_check(road.road_material_override.albedo_color == Color(0.15, 0.05, 0.07), "local material edits persist")
		_check(road.get_node(CONTROLLER.NODE_NAME) == container and barrier.height_scale == 1.25, "regenerate preserves editable barrier identity and settings")
		_check(barrier._last_signature == barrier._build_signature(), "normal road rebuild updates owned barriers")
		barrier.start_offset += 0.5
		_check(road.bake_runtime_scene("/tmp/roda-presets-stale-%s.tscn" % Time.get_ticks_usec()) == ERR_BUSY, "bake refuses a stale barrier")
		road.regenerate()
	# A second road must not share local material edits.
	var other_scene := DEMO.instantiate()
	root.add_child(other_scene)
	var other: Node = other_scene.get_node("Road")
	_check(other.apply_road_preset(CONTROLLER.BUILTINS[2]) == OK, "another road accepts the same preset")
	_check(other.road_material_override != road.road_material_override, "different roads do not share mutable material instances")
	other_scene.free()
	var layout_before: Dictionary = path.capture_editor_state()
	var barriers_before: Node = road.get_node(CONTROLLER.NODE_NAME)
	road.preset_replace_lane_layout = false
	road.preset_replace_barriers = false
	road.preset_apply_path_settings = false
	var sidewalk_before: float = path.sidewalk_left_width
	_check(road.apply_road_preset(CONTROLLER.BUILTINS[1]) == OK, "material/settings-only preset applies")
	_check(path.capture_editor_state() == layout_before, "keep-layout preserves every per-point lane/transition field")
	_check(path.sidewalk_left_width == sidewalk_before, "keep-path-settings preserves source edges")
	_check(road.get_node(CONTROLLER.NODE_NAME) == barriers_before, "keep-barriers does not replace the container")
	road.preset_replace_lane_layout = true
	road.preset_replace_barriers = true
	road.preset_apply_path_settings = true
	# Plain paths are not silently given a script; default road dimensions still work.
	var branch := Path3D.new()
	branch.name = "PlainBranch"
	branch.curve = Curve3D.new()
	branch.curve.add_point(Vector3(-35, 0, 0))
	branch.curve.add_point(Vector3.ZERO)
	road.add_child(branch)
	var custom: Resource = CONTROLLER.BUILTINS[0].duplicate(true)
	custom.markings_enabled = false
	custom.barrier_generate_collision = true
	var custom_file := "/tmp/roda-custom-preset-%s.tres" % Time.get_ticks_usec()
	_check(ResourceSaver.save(custom, custom_file) == OK, "custom resource saves")
	road.preset_selection = 3
	road.custom_preset = load(custom_file)
	_check(road.apply_road_preset() == OK, "saved custom preset applies through Inspector selection")
	_check(branch.get_script() == null, "plain Path3D keeps its original script identity")
	_check(road._marking_exclusions.size() == 2, "junction clearances exist even when markings are off")
	for barrier in road.get_node(CONTROLLER.NODE_NAME).get_children():
		var source_index: int = 0 if barrier._get_source_path() == path else 1
		for exclusion: Vector2 in road._marking_exclusions.get(source_index, []):
			_check(barrier.start_offset >= exclusion.y - 0.001 or barrier.start_offset + barrier.span_length <= exclusion.x + 0.001, "barrier does not block the junction")
		_check(_count_shapes(barrier) > 0, "custom preset collision is generated")
	_check_bake(road, 3)
	# Overlapping/noisy exclusions and short paths cannot generate negative spans.
	_check(CONTROLLER.allowed_spans(100, 2, [Vector2(10, 30), Vector2(20, 40), Vector2(60, 70)]) == [Vector2(2, 10), Vector2(40, 60), Vector2(70, 98)], "overlapping junction intervals are subtracted")
	_check(CONTROLLER.allowed_spans(3, 2, []).is_empty(), "too-short path skips barriers")
	var invalid := PRESET.new()
	invalid.lanes_left = 0
	invalid.lanes_right = 0
	_check(road.apply_road_preset(invalid) == ERR_INVALID_PARAMETER, "invalid preset is refused")
	invalid.lanes_right = 1
	invalid.barrier_end_clearance = NAN
	_check(road.apply_road_preset(invalid) == ERR_INVALID_PARAMETER, "non-finite preset value is refused")
	_check(road.apply_road_preset(Resource.new()) == ERR_INVALID_PARAMETER, "unrelated resource is refused")
	var reserved := road.get_node(CONTROLLER.NODE_NAME)
	reserved.remove_meta(CONTROLLER.OWNED_META)
	_check(road.apply_road_preset(CONTROLLER.BUILTINS[0]) == ERR_ALREADY_EXISTS, "unowned reserved name is not overwritten")
	reserved.set_meta(CONTROLLER.OWNED_META, true)
	# Lane drafts deliberately do not trigger heavy consumers. Bake must not
	# treat the old barrier as current just because its applied revision is stable.
	path.point_lanes_right[1] += 1
	road.regenerate()
	_check(road.bake_runtime_scene("/tmp/roda-preset-lane-draft-%s.tscn" % Time.get_ticks_usec()) == ERR_BUSY, "bake rejects barriers deferred during lane editing")
	path.rebuild_lane_dependents()
	road.regenerate()
	_check(road.bake_runtime_scene("/tmp/roda-preset-lane-applied-%s.tscn" % Time.get_ticks_usec()) == OK, "dependent rebuild makes barrier bake current again")
	scene.free()
	print("ROAD_PRESETS_%s barrier_counts=%s" % ["FAILED" if _failed else "OK", barrier_counts])
	quit(1 if _failed else 0)


func _check_bake(road: Node, index: int) -> void:
	for mode in [0, 1]:
		road.output_mode = mode
		road.regenerate()
		var file := "/tmp/roda-preset-%s-%s-%s.tscn" % [index, mode, Time.get_ticks_usec()]
		_check(road.bake_runtime_scene(file) == OK, "preset road bakes in output mode %s" % mode)
		if not FileAccess.file_exists(file):
			continue
		var baked: Node = load(file).instantiate()
		_check(baked.has_node(CONTROLLER.NODE_NAME), "baked scene includes preset-owned barriers")
		_check(_geometry(baked.get_node(CONTROLLER.NODE_NAME)) == _geometry(road.get_node(CONTROLLER.NODE_NAME)), "baked barrier geometry is identical")
		_check(_count_shapes(baked.get_node(CONTROLLER.NODE_NAME)) == _count_shapes(road.get_node(CONTROLLER.NODE_NAME)), "bake preserves barrier collision")
		_check_plain(baked)
		baked.free()
	road.output_mode = 0
	road.regenerate()


func _geometry(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			result.append(var_to_bytes(node.mesh.surface_get_arrays(surface)))
	for child in node.get_children():
		result.append_array(_geometry(child))
	return result


func _count_shapes(node: Node) -> int:
	var count := int(node is CollisionShape3D and node.shape != null)
	for child in node.get_children():
		count += _count_shapes(child)
	return count


func _check_plain(node: Node) -> void:
	_check(node.get_script() == null and not node is Path3D and not node is Marker3D, "bake contains no generator scripts or editing handles")
	for child in node.get_children():
		_check_plain(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
