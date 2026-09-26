extends SceneTree

const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")

var checks := 0
var failed := false

class Ground extends Node3D:
	func get_terrain_height_at_world(point: Vector3) -> Dictionary:
		return {"hit": true, "normal": Vector3(-0.2, 1, 0).normalized(), "y": point.x * 0.2}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var path := PROFILE.new()
	path.name = "Route"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -5))
	path.curve.add_point(Vector3(5, 2, -12), Vector3(-5, 0, 0), Vector3(5, 0, 0))
	path.curve.add_point(Vector3(17, 4, -9), Vector3(0, 0, -5))
	path.curve.set_point_tilt(0, 0.2)
	path.curve.set_point_tilt(1, -0.3)
	path.curve.set_point_tilt(2, 0.1)
	path.point_widths = PackedFloat32Array([4, 9, 5])
	world.add_child(path)
	var props := PROPS.new()
	props.name = "Fence"
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.4, 1, 2)
	props.source_paths = [NodePath("../Route")]
	props.fit_segments_to_path = true
	props.spacing = 2.3
	props.placement_mode = 1
	props.avoid_intersections = false
	props.ranges_mode = 0
	props.custom_scale = Vector3(0.7, 0.9, 1.2)
	props.custom_position = Vector3(0.2, 0.6, 0.15)
	props.transform = Transform3D(Basis.from_euler(Vector3(0.2, 0.3, 0.1)).scaled(Vector3(-1.2, 1.5, 0.8)), Vector3(3, 1, -2))
	world.add_child(props)
	var pieces := _pieces(props)
	_check(pieces.size() > 5, "Curved fixture generated modules")
	_check_chain(pieces, props, true)
	for piece: Node3D in pieces:
		_check(piece.global_basis.determinant() > 0, "Mirrored parent does not mirror the fitted world model")
	var before := _transforms(pieces)
	props.longitudinal_jitter = 3
	props.lateral_jitter = 2
	props.yaw_jitter_degrees = 60
	props.random_uniform_scale_max = 2
	props.regenerate()
	_check(before == _transforms(_pieces(props)), "Randomization cannot separate connected endpoints")

	props.range_source_mode = 0
	props.ranges_mode = 1
	props.distance_ranges = PackedVector2Array([Vector2(10, 16), Vector2(0, 4), Vector2(2, 5)])
	props.regenerate()
	_check(props._segment_fitter._intervals(props, path, path.curve.get_baked_length(), 0, 25, {}) == [Vector2(0, 5), Vector2(10, 16)], "Overlapping ranges merge; disjoint ranges stay separate")
	_check(_pieces(props).size() == 6, "Two three-module spans include shortened last modules")
	_check_chain(_pieces(props).slice(0, 3), props, true)
	_check_chain(_pieces(props).slice(3), props, true)
	props.ranges_mode = 2
	_check(props._segment_fitter._intervals(props, path, 25, 0, 25, {}) == [Vector2(5, 10), Vector2(16, 25)], "Exclusions split the fence without a bridging segment")

	props.ranges_mode = 0
	props.avoid_intersections = true
	props.intersection_clear_radius = 5
	props.regenerate()
	for piece: Node3D in _pieces(props):
		var endpoints := _endpoints(piece, props)
		for offset in [0.0, path.curve.get_baked_length()]:
			var endpoint := path.global_transform * path.curve.sample_baked(offset, true)
			var closest := Geometry3D.get_closest_point_to_segment(endpoint, endpoints[0], endpoints[1])
			_check(closest.distance_to(endpoint) > 4.999, "Full fitted segment respects endpoint clearance")

	props.avoid_intersections = false
	props.placement_mode = 3
	props.regenerate()
	pieces = _pieces(props)
	var per_side := ceili(path.curve.get_baked_length() / props.spacing)
	_check(pieces.size() == per_side * 2, "Both edges produce independent connected runs")
	_check_chain(pieces.slice(0, per_side), props, true)
	_check_chain(pieces.slice(per_side), props, true)
	props.render_mode = 1
	props.regenerate()
	var instance_count := 0
	for batch in props.get_node("GeneratedSplineProps").get_children():
		_check(batch is MultiMeshInstance3D, "Connected Item Mesh supports MultiMesh")
		instance_count += batch.multimesh.instance_count
	_check(instance_count == per_side * 2, "MultiMesh retains all fitted pieces")

	props.render_mode = 0
	props.placement_mode = 1
	props.item_scene = _scene_model()
	props.item_mesh = null
	props.custom_rotation_degrees = Vector3(0, 90, 0)
	props.regenerate()
	pieces = _pieces(props)
	_check_chain(pieces, props, true)
	_check(is_equal_approx(props._segment_fitter._max_z - props._segment_fitter._min_z, 2.8), "Length includes scene child transforms and custom rotation/scale")
	for piece: Node3D in pieces:
		_check(piece.has_node("Collision"), "Scene collisions preserved")

	props.item_scene = null
	props.item_mesh = BoxMesh.new()
	props.custom_transform = Transform3D.IDENTITY
	var ground := Ground.new()
	ground.name = "Ground"
	world.add_child(ground)
	props.terrain_height_source = NodePath("../Ground")
	props.snap_to_ground_enabled = true
	props.regenerate()
	pieces = _pieces(props)
	_check(not pieces.is_empty(), "Ground-snapped connected fence generated")
	_check_chain(pieces, props, true)
	for piece: Node3D in pieces:
		for point in _endpoints(piece, props):
			_check(absf(point.y - point.x * 0.2) < 0.0001, "Shared endpoint sits on provider height")
	world.free()
	if not failed:
		print("CONNECTED PROP SEGMENTS PASS checks=", checks)
	quit(1 if failed else 0)


func _scene_model() -> PackedScene:
	var model := Node3D.new()
	model.transform = Transform3D(Basis.IDENTITY, Vector3(20, 30, 40))
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(2, 1, 0.4)
	mesh.scale = Vector3(2, 1, 1)
	mesh.position = Vector3(3, 0.2, 0)
	model.add_child(mesh)
	mesh.owner = model
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = BoxShape3D.new()
	model.add_child(collision)
	collision.owner = model
	var packed := PackedScene.new()
	_check(packed.pack(model) == OK, "Scene fixture packed")
	model.free()
	return packed


func _pieces(props: Node3D) -> Array:
	var generated := props.get_node_or_null("GeneratedSplineProps")
	return generated.get_children() if generated != null else []


func _transforms(pieces: Array) -> Array:
	return pieces.map(func(piece: Node3D) -> Transform3D: return piece.global_transform)


func _endpoints(piece: Node3D, props: Node3D) -> Array[Vector3]:
	var inverse: Basis = props._segment_fitter._model_basis.inverse()
	return [piece.global_transform * (inverse * Vector3(0, 0, props._segment_fitter._max_z)),
		piece.global_transform * (inverse * Vector3(0, 0, props._segment_fitter._min_z))]


func _check_chain(pieces: Array, props: Node3D, expected: bool) -> void:
	for i in range(1, pieces.size()):
		var a := _endpoints(pieces[i - 1], props)[1]
		var b := _endpoints(pieces[i], props)[0]
		_check((a.distance_to(b) < 0.0001) == expected, "Adjacent fitted endpoints agree at %d (error=%s)" % [i, a.distance_to(b)])


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)
