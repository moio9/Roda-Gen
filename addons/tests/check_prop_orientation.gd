extends SceneTree

const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")

func _initialize() -> void:
	var props := PROPS.new()
	var rng := RandomNumberGenerator.new()
	var checks := 0
	for tangent in [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN, Vector3(1, 0.4, -0.3).normalized()]:
		for up in [Vector3.UP, Vector3(0.3, 1, 0.2).normalized()]:
			var basis: Basis = props._build_spawn_basis(tangent, up, 1, rng)
			assert(is_equal_approx(basis.determinant(), 1.0), "Aligned props must not be mirrored")
			assert((-basis.z).distance_to(tangent) < 0.0001, "Local -Z must follow travel")
			assert(absf(basis.x.dot(basis.y)) < 0.0001, "Orientation axes must be perpendicular")
			checks += 3
	var forward: Basis = props._build_spawn_basis(Vector3.FORWARD, Vector3.UP, 1, rng)
	assert(forward.is_equal_approx(Basis.IDENTITY), "Forward-aligned asymmetric models keep their X side")
	props.yaw_offset_degrees = 90
	var yawed: Basis = props._build_spawn_basis(Vector3.FORWARD, Vector3.UP, -1, rng)
	assert(yawed.is_equal_approx(Basis(Vector3.UP, PI / 2)), "Yaw is a rotation, not a reflection")
	props.free()
	print("PROP ORIENTATION PASS checks=", checks + 2)
	quit()
