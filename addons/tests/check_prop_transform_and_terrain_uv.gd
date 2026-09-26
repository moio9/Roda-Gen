extends SceneTree

const PROP_SCRIPT = preload("../scripts/spline_road/spline_prop_array.gd")
const TERRAIN_SCRIPT = preload("../scripts/spline_road/terrain_topology_builder.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var path := Path3D.new()
	path.name = "Route"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, 40))
	world.add_child(path)
	var props := PROP_SCRIPT.new()
	props.item_mesh = BoxMesh.new()
	props.source_paths = [NodePath("../Route")]
	props.spacing = 10.0
	props.ranges_mode = 0
	props.avoid_intersections = false
	world.add_child(props)
	props.regenerate()
	var before := _transforms(props)
	if not _check(before.size() >= 3, "Fixture needs at least three props"):
		return
	var old_signature: String = props._build_signature()
	var offset := Transform3D(Basis.from_euler(Vector3(0.1, 0.4, -0.2)).scaled(Vector3(1.2, 0.8, 1.1)), Vector3(2, 3, -1))
	props.custom_transform = offset
	if not _check(props._build_signature() != old_signature, "Custom transform did not invalidate generation"):
		return
	props.regenerate()
	var after := _transforms(props)
	if not _check(after.size() == before.size(), "Custom transform changed prop count"):
		return
	for i in range(before.size()):
		if not _check(after[i].is_equal_approx(before[i] * offset), "Custom transform mismatch at prop %d" % i):
			return

	var terrain := TERRAIN_SCRIPT.new()
	var uv2 := Vector2.ZERO
	var bx := Vector2(20, 0)
	var cz := Vector2(0, 1)
	var a := Vector3.ZERO
	var b := Vector3(20, 0, 0)
	var c := Vector3(0, 20, 1)
	var flat := terrain._terrain_triangle_uvs(a, b, Vector3(0, 0, 1), uv2, bx, cz)
	if not _check(flat[0].is_equal_approx(Vector2.ZERO)
			and flat[1].is_equal_approx(Vector2(1, 0))
			and flat[2].is_equal_approx(Vector2(0, 0.05)), "Flat UV changed"):
		return
	terrain.slope_aware_uvs = true
	var steep := terrain._terrain_triangle_uvs(a, b, c, uv2, bx, cz)
	if not _check(steep[0].distance_to(steep[2]) > 0.5, "Steep UV still compressed"):
		return
	var neighbor := terrain._terrain_triangle_uvs(a, c, Vector3(-20, 1, 0), uv2, cz, Vector2(-20, 0))
	if not _check(steep[0].is_equal_approx(neighbor[0]) and steep[2].is_equal_approx(neighbor[1]),
			"Adjacent terrain triangles have a UV seam"):
		return
	if not _check(terrain._terrain_triangle_uvs(a, b, Vector3(0, 0, 1), uv2, bx, cz) == flat,
			"Slope UV changed a flat triangle"):
		return
	print("PROP TRANSFORM AND TERRAIN UV OK placements=", before.size())
	world.free()
	terrain.free()
	quit()

func _transforms(props: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var generated := props.get_node_or_null("GeneratedSplineProps")
	if generated != null:
		for child in generated.get_children():
			if child is Node3D:
				result.append(child.transform)
	return result

func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
