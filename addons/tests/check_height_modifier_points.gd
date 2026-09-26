extends SceneTree
const MODIFIER = preload("../scripts/spline_road/terrain_height_modifier.gd")
var failures := 0
func _initialize():
	run.call_deferred()
func check(ok: bool, message: String):
	if not ok:
		push_error(message)
		failures += 1
func run():
	var builder := Node3D.new()
	root.add_child(builder)
	var m = MODIFIER.new()
	builder.add_child(m)
	m.curve = Curve3D.new()
	m.curve.add_point(Vector3(0, 10, 0))
	m.curve.add_point(Vector3(10, 10, 0))
	m.curve.add_point(Vector3(100, 10, 0))
	m.mode = 8
	m.radius = 5
	m.affect_near_roads = true
	check(is_equal_approx(m.modify_height(builder, Vector2(10, 0), 0, {}), 10), "Default Curve Y unchanged")
	m.select_point_index(1)
	m.selected_point_height_offset = 20
	m.selected_point_strength_scale = 0.5
	check(is_equal_approx(m.modify_height(builder, Vector2(10, 0), 0, {}), 25), "Settings at short-span control point")
	check(is_equal_approx(m.modify_height(builder, Vector2(5, 0), 0, {}), 17.5), "Interpolate along the first span")
	check(is_equal_approx(m.modify_height(builder, Vector2(55, 0), 0, {}), 17.5), "Interpolate along unequal second span")
	check(is_equal_approx(m.modify_height(builder, Vector2(100, 0), 0, {}), 10), "Unspecified endpoint retains defaults")
	var prep: int = m.get_distance_cache_stats().preparations
	var before: Dictionary = m.capture_editor_state()
	var replay := {}
	m.apply_editor_profile_change(before, "selected_point_height_offset", 30.0, 1, replay)
	check(is_equal_approx(m.modify_height(builder, Vector2(10, 0), 0, {}), 35), "Apply Inspector edit")
	check(m.get_distance_cache_stats().preparations == prep, "Height edits retain distance cache through editor history")
	m.select_point_index(2)
	m.restore_editor_state(before)
	check(is_equal_approx(m.modify_height(builder, Vector2(10, 0), 0, {}), 25), "Undo restores original point after selection changes")
	m.apply_editor_profile_change(before, "selected_point_height_offset", 30.0, 1, replay)
	check(is_equal_approx(m.modify_height(builder, Vector2(10, 0), 0, {}), 35), "Redo targets captured point")
	m.select_point_index(1)
	m.selected_point_radius = 20
	check(m.modify_height(builder, Vector2(10, 10), 0, {}) > 0, "Point radius expands candidate search beyond global radius")
	check(m.get_bounds_in_builder_space(builder).has_point(Vector2(10, 19)), "Point radius included in terrain bounds")
	m.selected_point_custom_radius = false
	check(m.modify_height(builder, Vector2(10, 10), 0, {}) == 0, "Reset radius restores global fallback")
	var snapshot: Dictionary = m.capture_editor_state()
	var frame: Transform3D = m.get_point_editor_transform(1)
	m.apply_point_editor_transform(1, frame, Transform3D(frame.basis, frame.origin + Vector3.UP * 4), snapshot.curve_points[1])
	check(m.curve.get_point_position(1).y == 14, "Gizmo translation moves the curve point")
	m.restore_editor_state(snapshot)
	check(m.curve.get_point_position(1).y == 10, "Cancel/Undo restores the curve")
	for property: Dictionary in m.get_property_list():
		if str(property.name).begins_with("selected_point_"):
			check((int(property.usage) & PROPERTY_USAGE_STORAGE) == 0, "Do not serialize selection proxies")
	m.point_strength_scales.clear()
	m.point_height_offsets.clear()
	m.mode = 7
	m.custom_profile_is_absolute_height = true
	m.profile_distances = PackedFloat32Array([0, 100])
	m.profile_heights = PackedFloat32Array([6, 6])
	check(m.modify_height(builder, Vector2(10, 0), 13, {}) == 6, "Absolute custom profile remains absolute")
	m.custom_profile_is_absolute_height = false
	check(m.modify_height(builder, Vector2(10, 0), 13, {}) == 19, "Relative custom profile remains additive")
	# Crossings must interpolate by traversal order rather than closest-offset ambiguity.
	m.curve.clear_points()
	m.curve.add_point(Vector3(-10, 0, 0))
	m.curve.add_point(Vector3(0, 0, 0))
	m.curve.add_point(Vector3(10, 0, 0))
	m.curve.add_point(Vector3(0, 0, 0))
	m.curve.add_point(Vector3(0, 0, 10))
	m._ensure_distance_cache(builder)
	check(m._control_offsets[3] > m._control_offsets[1], "Repeated positions retain distinct control offsets")
	m.curve.closed = true
	m._ensure_distance_cache(builder)
	check(m._control_offsets.size() == m.curve.point_count + 1, "Closed curve includes closing span")
	var state: Dictionary = m.capture_editor_state()
	m.curve.closed = false
	m.restore_editor_state(state)
	check(m.curve.closed, "History restores closed curve")
	print("HEIGHT POINTS failures=", failures)
	builder.free()
	quit(failures)
