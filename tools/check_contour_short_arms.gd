extends SceneTree
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for x in [-24.0, -21.059439, -16.0, 0.0, 16.0, 21.0, 24.0]:
		var road := ROAD.new()
		road.threaded_generation_enabled = false
		road.debug_generation_logs = false
		road.sample_step = 0.75
		road.adaptive_sampling_enabled = false
		road.invert_faces = true
		road.junction_geometry_mode = 1
		road.junction_corner_subdivisions = 24
		var through := _path("Through", Vector3(-38, 0, 0), Vector3(38, 0, 0))
		var branch := _path("Branch", Vector3.ZERO, Vector3(0, 0, 38))
		branch.position = Vector3(x, 0, -0.19180036)
		branch.rotation.y = deg_to_rad(33.065)
		road.add_child(through)
		road.add_child(branch)
		var authored := branch.transform
		root.add_child(road)
		await process_frame
		var reports: Array = road.get_source_rebuild_stats().contour_junctions
		# This more acute, opposite-end placement remains outside the supported
		# outline solver. Require explicit rejection, not a squeezed sidewalk.
		if x == 24.0:
			_check(reports.size() == 1 and not reports[0].ok and reports[0].reason.contains("sidewalks"), "Explicit unsupported boundary")
			_check(not reports[0].arm_retreats.is_empty(), "Fallback identifies arm limits")
		else:
			_check(reports.size() == 1 and reports[0].ok, "Accepted position x=%s: %s" % [x, reports])
		_check(branch.transform == authored, "Authored transform unchanged")
		_check(branch.sidewalk_left_width == 2.0 and branch.sidewalk_right_width == 2.0, "Sidewalk settings preserved")
		if reports.size() == 1 and reports[0].ok:
			var limited := false
			for arm in reports[0].arm_retreats:
				limited = limited or arm.limited
				_check(arm.actual > 0.0, "Nonzero retained arm")
			if x == -21.059439:
				_check(limited, "Original regression uses a limited arm, not legacy")
			var cold := _digest(road)
			road.incremental_generation_enabled = true
			road.regenerate()
			_check(cold == _digest(road), "Cold/warm geometry parity")
		print("SHORT ARM x=", x, " accepted=", reports.size() == 1 and reports[0].ok)
		road.free()
		await process_frame
	# A rejected candidate must leave all supplied geometry untouched.
	var builder = preload("../addons/scripts/spline_road/road_contour_junction.gd").new()
	var configuration := ROAD.new()
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.ONE])
	var lane := PackedInt32Array([0, 1, 0])
	var rows: Array = [[{"position": Vector3.ZERO, "width": 7.0, "row_edges": [0, 0, 0, 1, 1, 1], "distance": 0.0},
		{"position": Vector3.RIGHT, "width": 7.0, "row_edges": [0, 0, 0, 1, 1, 1], "distance": 1.0}]]
	var sockets: Array[Dictionary] = [{"path_id": 0, "row_idx": 0, "position": Vector3.ZERO, "width": 7.0}]
	var accepted: bool = builder.build(configuration, vertices, normals, uvs, [lane, PackedInt32Array(), PackedInt32Array()], sockets, [0], rows)
	_check(not accepted, "Genuinely insufficient sampled length rejected")
	_check(vertices == PackedVector3Array([Vector3.ZERO, Vector3.RIGHT]) and lane == PackedInt32Array([0, 1, 0]), "Rejection is atomic")
	_check(builder.reports[0].reason.contains("path 0"), "Failure identifies constrained arm")
	configuration.free()
	print("CONTOUR SHORT ARMS ", "OK" if failures == 0 else "FAILED")
	quit(failures)

func _path(label: String, start: Vector3, end: Vector3) -> Path3D:
	var path := PROFILE.new()
	path.name = label
	path.curve = Curve3D.new()
	path.curve.add_point(start)
	path.curve.add_point(end)
	path.lane_profile_enabled = true
	path.default_lane_width = 3.25
	path.shoulder_left_width = 0.35
	path.shoulder_right_width = 0.35
	path.sidewalk_left_width = 2.0
	path.sidewalk_right_width = 2.0
	path.sidewalk_height = 0.15
	path.show_width_preview = false
	return path

func _digest(road: Node) -> int:
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var data: Array = []
	for i in range(mesh.get_surface_count()):
		data.append(mesh.surface_get_arrays(i))
	return hash(data)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1
