extends SceneTree

const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results: Dictionary = {}
	for topology in [-1, 0, 2, 3, 8, 11]:
		var road := ROAD.new()
		road.name = "BaselineRoad"
		road.threaded_generation_enabled = false
		road.debug_generation_logs = false
		road.sample_step = 2.0
		road.road_orientation_mode = 2
		road.shoulder_left_width = 0.5
		road.shoulder_right_width = 0.7
		road.sidewalk_left_width = 0.8
		road.sidewalk_right_width = 0.6
		road.outer_wall_height = 0.5
		road.terrain_left_width = 8.0
		road.terrain_right_width = 8.0
		road.terrain_fill_algorithm = 0 if topology == -1 else 1
		road.terrain_fill_topology = maxi(0, topology)
		road.terrain_rect_fill_cell_size = 8.0
		road.terrain_fill_quadtree_max_depth = 2
		road.terrain_fill_delaunay_step_near = 4.0
		road.terrain_fill_delaunay_step_far = 8.0
		for arm in range(3):
			var path := PROFILE.new()
			path.name = "Arm%d" % arm
			path.curve = Curve3D.new()
			var angle := TAU * float(arm) / 3.0
			var direction := Vector3(cos(angle), 0, sin(angle))
			path.curve.add_point(Vector3.ZERO, Vector3.ZERO, direction * 8.0)
			path.curve.add_point(direction * 35.0 + Vector3.UP * arm, -direction * 8.0)
			path.point_widths = PackedFloat32Array([6.0, 8.0])
			path.shoulder_left_width = 0.5
			path.shoulder_right_width = 0.7
			path.sidewalk_left_width = 0.8
			path.sidewalk_right_width = 0.6
			path.outer_wall_height = 0.5
			path.terrain_override_enabled = true
			path.terrain_left_width = 8.0
			path.terrain_right_width = 8.0
			road.add_child(path)
			road.source_paths.append(NodePath(path.name))
		root.add_child(road)
		var generated := road.get_node_or_null("GeneratedSplineRoadWelded") as MeshInstance3D
		if generated == null or generated.mesh == null:
			push_error("Baseline road did not generate for topology %d" % topology)
			quit(1)
			return
		var surfaces: Array = []
		for surface in range(generated.mesh.get_surface_count()):
			surfaces.append(generated.mesh.surface_get_arrays(surface))
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes(surfaces))
		results[str(topology)] = {
			"sha256": digest.finish().hex_encode(),
			"surfaces": surfaces.size(),
			"faces": generated.mesh.get_faces().size() / 3,
		}
		road.free()
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--save":
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
	elif args.size() == 2 and args[0] == "--compare":
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		if not _same_results(expected, results):
			push_error("ROAD_BASELINE_MISMATCH expected=%s actual=%s" % [expected, results])
			quit(1)
			return
	print("ROAD_BASELINE_OK ", JSON.stringify(results))
	quit(0)


func _same_results(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.size() != actual.size():
		return false
	for key in expected:
		if not actual.has(key):
			return false
		if expected[key]["sha256"] != actual[key]["sha256"]:
			return false
		for field in ["surfaces", "faces"]:
			if int(expected[key][field]) != int(actual[key][field]):
				return false
	return true
