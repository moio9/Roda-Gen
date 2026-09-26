extends SceneTree
const MODIFIER = preload("../scripts/spline_road/terrain_height_modifier.gd")
const REFERENCE = preload("fixtures/terrain_modifier_reference.gd")
var failures := 0
func _initialize():
	_run.call_deferred()
func _check(ok: bool, message: String):
	if not ok:
		push_error(message)
		failures += 1
func _compare(builder, modifier, reference, points: Array[Vector2]):
	for property: Dictionary in modifier.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			reference.set(property.name, modifier.get(property.name))
	reference.transform = modifier.transform
	reference.curve = modifier.curve.duplicate() if modifier.curve != null else null
	reference.prepare_for_terrain_builder()
	modifier.prepare_for_terrain_builder()
	modifier.get_bounds_in_builder_space(builder) # Every regeneration samples bounds before heights.
	for point in points:
		for road in [{}, {"edge_distance": 0.0}, {"edge_distance": 6.0}]:
			var expected: float = reference.modify_height(builder, point, 13.0, road)
			var actual: float = modifier.modify_height(builder, point, 13.0, road)
			_check(absf(expected - actual) < 0.00001, "Height parity at %s: %s != %s" % [point, expected, actual])
func _run():
	var parent := Node3D.new()
	root.add_child(parent)
	var builder := Node3D.new()
	parent.add_child(builder)
	builder.position = Vector3(3, -2, 7)
	builder.rotation.y = 0.15
	var m = MODIFIER.new()
	var reference = REFERENCE.new()
	parent.add_child(m)
	parent.add_child(reference)
	m.position = Vector3(-4, 9, 5)
	m.scale = Vector3(1.3, 0.9, 0.8)
	m.rotation.y = -0.3
	m.curve = Curve3D.new()
	m.curve.add_point(Vector3(-40, 1, -40), Vector3.ZERO, Vector3(20, 4, 0))
	m.curve.add_point(Vector3(40, 8, 40), Vector3(-20, 0, 0))
	m.curve.add_point(Vector3(-40, -3, 40))
	m.curve.add_point(Vector3(40, 14, -40))
	m.radius = 17.0
	var points: Array[Vector2] = [Vector2.ZERO, Vector2(-17, -17), Vector2(17, 17), Vector2(1000, 1000)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7345
	for i in range(80):
		points.append(Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70)))
	for mode in range(9):
		m.mode = mode
		_compare(builder, m, reference, points)
	var stats: Dictionary = m.get_distance_cache_stats()
	_check(stats.preparations == 1, "Mode/height changes reuse sampled geometry")
	_check(stats.queries_reused > 0, "Repeated vertices reuse distance results")
	var signature: String = m.get_modifier_signature()
	m.curve.set_point_position(1, m.curve.get_point_position(1) + Vector3(0, 3, 0))
	_check(signature != m.get_modifier_signature(), "Curve edits change generation signature")
	_compare(builder, m, reference, points)
	_check(m.get_distance_cache_stats().preparations == 2, "Curve edits invalidate geometry")
	m.position.x += 8
	_compare(builder, m, reference, points)
	builder.position.z += 7
	_compare(builder, m, reference, points)
	m.radius = 28
	_compare(builder, m, reference, points)
	m.distance_sample_step = 3.5
	_compare(builder, m, reference, points)
	m.curve = m.curve.duplicate()
	m.curve.set_point_out(0, Vector3(-4, 8, 25))
	_compare(builder, m, reference, points)
	m.curve = Curve3D.new()
	_compare(builder, m, reference, points)
	m.curve.add_point(Vector3(5, 12, 8))
	_compare(builder, m, reference, points)
	m.curve.add_point(Vector3(5, 20, 8))
	_compare(builder, m, reference, points)
	m.curve = null
	_compare(builder, m, reference, points)
	m.curve = Curve3D.new()
	m.curve.add_point(Vector3(-1, 2, -1))
	m.curve.add_point(Vector3(1, 6, 1))
	m.scale = Vector3(10000, 1, 10000)
	_compare(builder, m, reference, points)
	_check(not m._distance_overflow.is_empty(), "Oversized segments use bounded overflow storage")
	print("MODIFIER_CACHE failures=",failures," stats=",m.get_distance_cache_stats())
	parent.free()
	quit(1 if failures else 0)
