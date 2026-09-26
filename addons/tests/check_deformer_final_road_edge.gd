extends SceneTree
const DEFORMER = preload("../scripts/spline_road/spline_mesh_deformer.gd")
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const CUT = preload("../scripts/spline_road/terrain_road_mesh_cut.gd")
var failed := false
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := ROAD.new()
	road.name = "Road"
	road.generate_in_editor = false
	road.debug_generation_logs = false
	road.road_orientation_mode = 1
	world.add_child(road)
	_set_surface(road, 7.0, true)
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, -20))
	path.curve.set_point_tilt(0, 0.4)
	path.curve.set_point_tilt(1, 0.4)
	road.add_child(path)
	var fence := DEFORMER.new()
	fence.source_mesh = BoxMesh.new()
	fence.source_mesh.size = Vector3(2, 1, 0.4)
	fence.placement_mode = 1
	fence.outward_offset = 0.25
	fence.vertical_offset = 0.5
	fence.generate_collision = true
	path.add_child(fence)
	var frame: Dictionary = fence._sample_frame_cached(path, 10.0, {}, -1)
	var expected_up := Vector3(-0.1, 1, 0).normalized()
	_check(frame.get("final_edge", false), "Deformer resolves final welded edge")
	_check(frame.up.distance_to(expected_up) < 0.0001, "Uses final bank instead of authored path tilt")
	_check(frame.center.distance_to(Vector3(7, 0.4, -10) + Vector3(1, 0.1, 0).normalized() * 0.2) < 0.0001, "Places full mesh thickness outside merged outline")
	_check(_bounds(fence).position.x > 7.0, "All fence vertices clear banked road")
	var output := fence.get_node("GeneratedSplineMeshes").get_child(0) as MeshInstance3D
	var shape := output.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
	_check(shape != null and (shape.shape as ConcavePolygonShape3D).get_faces() == output.mesh.get_faces(), "Collision uses the deformed output")
	var old_signature: String = fence._build_signature()
	_set_surface(road, 9.0, false)
	_check(fence._build_signature() != old_signature, "Road revision invalidates editor signature")
	fence._process(0.0)
	_check(absf(_bounds(fence).position.x - 9.25) < 0.0001, "Runtime rebuild follows edited outer edge")
	_check(not fence._road_edge.changed(road), "Revision is consumed without repeated rebuild")
	fence.follow_generated_road_edge = false
	fence.regenerate()
	_check(absf(_bounds(fence).position.x - 3.05) < 0.0001, "Opt-out preserves original centered-on-edge placement")
	fence.follow_generated_road_edge = true
	fence.edge_uses_total_road_width = false
	fence.regenerate()
	_check(absf(_bounds(fence).position.x - 3.05) < 0.0001, "Lane-only placement is unchanged")
	fence.edge_uses_total_road_width = true
	fence.placement_mode = 3
	fence.transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(2, 1, 3))
	fence.regenerate()
	_check(fence.get_node("GeneratedSplineMeshes").get_child_count() == 2, "Both edges produce output under a transformed deformer")
	var bounds := _bounds(fence)
	_check(absf(bounds.position.x + 3.65) < 0.0001 and absf(bounds.end.x - 9.65) < 0.0001, "Both sides honor thickness and clearance in world space")
	_quad(road, 9, 13, 0, 0, -9, -11)
	road._terrain_surface_revision += 1
	fence.regenerate()
	_check(_road_overlap_area(fence, road) < 0.0001, "No deformed fence slices cross the side-junction opening")
	fence.placement_mode = 0
	fence.regenerate()
	_check(absf(_bounds(fence).get_center().x) < 0.0001, "Center placement remains on authored path")
	world.free()
	print("DEFORMER FINAL ROAD EDGE %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)

func _set_surface(road: Node, edge: float, bank: bool) -> void:
	road._terrain_surface_data = {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	_quad(road, -3, 3, 0, 0)
	_quad(road, 3, edge, 0, 0.4 if bank else 0.0)
	_quad(road, -3, 20, 5, 5)
	road._terrain_surface_revision += 1

func _quad(road: Node, x0: float, x1: float, y0: float, y1: float, z0 := 0.0, z1 := -20.0) -> void:
	var data: Dictionary = road._terrain_surface_data
	var base: int = data.vertices.size()
	data.vertices.append_array(PackedVector3Array([Vector3(x0, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y0, z1), Vector3(x1, y1, z1)]))
	data.indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))

func _bounds(fence: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for output: MeshInstance3D in fence.get_node("GeneratedSplineMeshes").get_children():
		for surface in range(output.mesh.get_surface_count()):
			for p: Vector3 in output.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var world := output.to_global(p)
				bounds = AABB(world, Vector3.ZERO) if first else bounds.expand(world)
				first = false
	return bounds

func _road_overlap_area(fence: Node3D, road: Node3D) -> float:
	var cut := CUT.new()
	cut.append_surface(road._terrain_surface_data.vertices, road._terrain_surface_data.indices, road.global_transform)
	var area := 0.0
	for output: MeshInstance3D in fence.get_node("GeneratedSplineMeshes").get_children():
		var faces := output.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var points := PackedVector3Array()
			for k in range(3):
				var p: Vector3 = output.to_global(faces[i + k])
				p.y = 0
				points.append(p)
			for tri: PackedVector3Array in cut.intersect_surface(points[0], points[1], points[2]):
				area += absf((tri[1] - tri[0]).cross(tri[2] - tri[0]).y) * 0.5
	return area

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
