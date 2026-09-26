extends SceneTree

const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _path(name_: String, x: float, zs: Array[float], heights: Array[float]) -> Path3D:
	var path := PROFILE.new()
	path.name = name_
	path.curve = Curve3D.new()
	for i in range(zs.size()):
		path.curve.add_point(Vector3(x,heights[i],zs[i]))
	path.point_widths = PackedFloat32Array([6.0,6.0,6.0])
	path.lateral_join_layers = 1
	path.show_width_preview = false
	return path

func _run() -> void:
	var road := ROAD.new()
	road.debug_generation_logs = false
	road.threaded_generation_enabled = false
	road.sample_step = 0.5
	road.lateral_join_max_overlap = 2.0
	road.lateral_join_height_tolerance = 0.35
	road.lateral_join_height_blend_width = 3.0
	road.lateral_join_transition_length = 0.0
	road.allow_endpoint_to_midpath = false
	road.endpoint_snap_distance = 0.1
	road.invert_faces = true
	road.add_child(_path("Host",0.0,[0.0,20.0,40.0],[0.0,0.0,0.0]))
	var merge := _path("Merge",4.5,[10.0,20.0,30.0],[0.15,-0.12,0.15])
	road.add_child(merge)
	var authored := PackedFloat32Array([merge.curve.get_point_position(0).y,
		merge.curve.get_point_position(1).y,merge.curve.get_point_position(2).y])
	root.add_child(road)
	var stats: Dictionary = road.get_source_rebuild_stats().get("lateral_joins",{})
	assert(stats.get("contacts",0) > 0,"Bumpy extra road must make lateral contact")
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var seam_count := 0
	var outer_count := 0
	var outer_error := 0.0
	var seam_error := 0.0
	for surface in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if vertex.z > 12.0 and vertex.z < 28.0 and absf(vertex.x-3.0) < 0.0005:
				seam_count += 1
				seam_error = maxf(seam_error,absf(vertex.y))
			if vertex.z > 12.0 and vertex.z < 28.0 and vertex.x > 5.0:
				outer_count += 1
				outer_error = maxf(outer_error,absf(vertex.y))
	print("LATERAL HEIGHT SEAM contacts=", stats.contacts, " seam_vertices=", seam_count,
		" max_height_gap=", seam_error, " outer_vertices=", outer_count,
		" outer_height_error=", outer_error)
	assert(seam_count > 0,"Fixture must expose the shared asphalt edge")
	assert(seam_error < 0.001,"Joined edge must share the host height")
	assert(outer_count > 0 and outer_error < 0.001,"Joining road must follow the host grade across each row")
	for i in range(3):
		assert(is_equal_approx(merge.curve.get_point_position(i).y,authored[i]),"Source curve must remain authored")
	road.regenerate()
	var again: Dictionary = road.get_source_rebuild_stats().get("lateral_joins",{})
	assert(again.get("contacts",0) == stats.contacts,"Automatic height alignment must be stable on rebuild")
	quit()
