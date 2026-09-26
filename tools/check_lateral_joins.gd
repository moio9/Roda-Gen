extends SceneTree
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _path(label: String, x: float, from_z: float, to_z: float, left: int) -> Path3D:
	var path := PROFILE.new()
	path.name = label
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(x,0,from_z))
	path.curve.add_point(Vector3(x,0,to_z))
	path.lane_profile_enabled = true
	path.default_lanes_left = left
	path.default_lanes_right = 1
	path.default_lane_width = 3.0
	path.point_lanes_left = PackedInt32Array([left,left])
	path.point_lanes_right = PackedInt32Array([1,1])
	path.point_lane_widths = PackedFloat32Array([3,3])
	path.shoulder_left_width = 0.4
	path.shoulder_right_width = 0.4
	path.sidewalk_left_width = 1.0
	path.sidewalk_right_width = 1.0
	path.outer_wall_height = 0.8
	path.lateral_join_group = "test"
	path.show_width_preview = false
	return path

func _run() -> void:
	for distance in [0.0,0.2,-0.3]:
		var road := ROAD.new()
		road.threaded_generation_enabled = false
		road.debug_generation_logs = false
		road.sample_step = 1.3
		road.lateral_join_transition_length = 0.0
		road.adaptive_sampling_enabled = false
		road.allow_endpoint_to_midpath = false
		road.endpoint_snap_distance = 0.1
		road.invert_faces = true
		road.markings_enabled = true
		road.incremental_generation_enabled = true
		road.road_material_override = StandardMaterial3D.new()
		road.sidewalk_material_override = StandardMaterial3D.new()
		road.outer_wall_material_override = StandardMaterial3D.new()
		var main := _path("Main",0,0,40,1)
		var extra := _path("Extra",3+distance,10,30,0)
		road.add_child(main)
		road.add_child(extra)
		var authored := var_to_bytes([main.curve.get_point_position(0),extra.curve.get_point_position(0),extra.sidewalk_left_width])
		root.add_child(road)
		var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
		var stats: Dictionary = road.get_source_rebuild_stats().lateral_joins
		_check(stats.contacts > 0,"Lateral contact detected, gap=%s" % distance)
		_check(absf(stats.length-20) < 0.01,"Contact is the actual 20 m longitudinal overlap: %s" % stats)
		_check(absf(_area(mesh,road.road_material_override)-(300+20*distance)) < 0.02,"Asphalt union area without double layers, gap=%s area=%s" % [distance,_area(mesh,road.road_material_override)])
		_check(not _covers(mesh,road.sidewalk_material_override,Vector2(3.8,20)),"Main interior sidewalk removed")
		_check(not _covers(mesh,road.sidewalk_material_override,Vector2(2.2+distance,20)),"Extra interior sidewalk removed")
		_check(_covers(mesh,road.sidewalk_material_override,Vector2(-3.8,20)),"Main exterior sidewalk retained")
		_check(_covers(mesh,road.sidewalk_material_override,Vector2(6.8+distance,20)),"Extra exterior sidewalk retained")
		_check(_covers(mesh,road.sidewalk_material_override,Vector2(3.8,5)),"Sidewalk resumes outside contact")
		_check(not _wall_inside(mesh,road.outer_wall_material_override,1,5.0+distance,12,28),"Inner walls removed")
		_check(authored == var_to_bytes([main.curve.get_point_position(0),extra.curve.get_point_position(0),extra.sidewalk_left_width]),"Authored profiles unchanged")
		var digest := _digest(road)
		road.regenerate()
		_check(digest == _digest(road),"Warm source/marking caches retain joined geometry")
		_check(road.get_marking_stats().blocks_reused > 0,"Joined marking cache can reuse unchanged blocks")
		road.threaded_generation_enabled = true
		road.regenerate()
		while road.is_road_generation_pending():
			await process_frame
		_check(digest == _digest(road),"Threaded finalize retains lateral geometry and walls")
		road.threaded_generation_enabled = false
		extra.position.x = 5
		road.regenerate()
		_check(road.get_source_rebuild_stats().lateral_joins.contacts == 0,"Distant grouped roads stay separate")
		extra.position.x = 0
		extra.position.y = 3
		road.regenerate()
		_check(road.get_source_rebuild_stats().lateral_joins.contacts == 0,"Elevated road stays separate")
		extra.position.y = 0
		extra.lateral_join_group = "other"
		road.regenerate()
		_check(road.get_source_rebuild_stats().lateral_joins.contacts == 0,"Different groups stay separate")
		_check(_covers(road.get_node("GeneratedSplineRoadWelded").mesh,road.sidewalk_material_override,Vector2(3.8,20)),"Inner sidewalk restored after opt-out")
		main.lateral_join_group = ""
		extra.lateral_join_group = ""
		main.lateral_join_layers = 1
		extra.lateral_join_layers = 2
		road.regenerate()
		_check(road.get_source_rebuild_stats().lateral_joins.contacts == 0,"Different join layers stay separate")
		extra.lateral_join_layers = 3
		road.regenerate()
		_check(road.get_source_rebuild_stats().lateral_joins.contacts > 0,"Shared join layer joins with empty groups")
		main.lateral_join_layers = 0
		extra.lateral_join_layers = 0
		main.lateral_join_group = "test"
		extra.lateral_join_group = "test"
		extra.rotation.y = PI*0.5
		road.regenerate()
		_check(road.get_source_rebuild_stats().lateral_joins.contacts == 0,"Perpendicular crossing stays separate")
		print("LATERAL gap=",distance," ",stats)
		road.free()
		await process_frame
	await _playground()
	print("LATERAL JOINS ","OK" if failures == 0 else "FAILED", " failures=",failures)
	quit(0 if failures == 0 else 1)

func _triangles(mesh: Mesh, material: Material) -> Array:
	var result: Array = []
	for surface in range(mesh.get_surface_count()):
		if mesh.surface_get_material(surface) != material:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			result.append(PackedVector3Array([vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]]))
	return result

func _area(mesh: Mesh, material: Material) -> float:
	var area := 0.0
	for t: PackedVector3Array in _triangles(mesh,material):
		var cross_ := (t[1]-t[0]).cross(t[2]-t[0])
		_check(cross_.y <= 0.00001,"Asphalt faces upward with inverted winding")
		area += absf(cross_.y)*0.5
	return area

func _covers(mesh: Mesh, material: Material, point: Vector2) -> bool:
	for t: PackedVector3Array in _triangles(mesh,material):
		if Geometry2D.is_point_in_polygon(point,PackedVector2Array([Vector2(t[0].x,t[0].z),Vector2(t[1].x,t[1].z),Vector2(t[2].x,t[2].z)])):
			return true
	return false

func _wall_inside(mesh: Mesh, material: Material, x0: float, x1: float, z0: float, z1: float) -> bool:
	for t: PackedVector3Array in _triangles(mesh,material):
		var p := (t[0]+t[1]+t[2])/3.0
		if p.x > x0 and p.x < x1 and p.z > z0 and p.z < z1:
			return true
	return false

func _digest(road: Node) -> int:
	var data: Array = []
	for name_ in ["GeneratedSplineRoadWelded","GeneratedRoadMarkings"]:
		var mesh: Mesh = road.get_node(name_).mesh
		for surface in range(mesh.get_surface_count()):
			data.append(mesh.surface_get_arrays(surface))
	return hash(data)

func _playground() -> void:
	var scene := load("res://addons/scenes/examples/lateral_join_playground.tscn").instantiate() as Node3D
	# Use a fixed parallel fixture even when the editable playground has been changed.
	var fixture := scene.get_node("Joined")
	fixture.junction_geometry_mode = 0
	for path in [fixture.get_node("Main"),fixture.get_node("ExtraLane")]:
		path.intersection_override_enabled = false
		path.lateral_join_start_transition_length = -1.0
		path.lateral_join_end_transition_length = -1.0
		path.curve = Curve3D.new()
		path.curve.bake_interval = 2.0
	var fixture_main := fixture.get_node("Main")
	fixture_main.curve.add_point(Vector3(0,0,-40))
	fixture_main.curve.add_point(Vector3(0,0,40))
	var fixture_extra := fixture.get_node("ExtraLane")
	fixture_extra.curve.add_point(Vector3(3.2,0,-22))
	fixture_extra.curve.add_point(Vector3(3.2,0,22))
	root.size = Vector2i(1200,900)
	root.add_child(scene)
	var camera := scene.get_node("Camera") as Camera3D
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	await process_frame
	_check(scene.get_node("Separate").get_source_rebuild_stats().lateral_joins.contacts == 0,"Playground separate case")
	_check(scene.get_node("Joined").get_source_rebuild_stats().lateral_joins.length > 43.9,"Playground joined case")
	var road := scene.get_node("Joined")
	var extra := road.get_node("ExtraLane")
	var authored := var_to_bytes([extra.curve.get_point_position(0),extra.curve.get_point_position(1),
		extra.point_lanes_right,extra.point_lane_widths,extra.sidewalk_right_width])
	var transitions: Array = road.get_source_rebuild_stats().lateral_joins.transitions
	_check(transitions.size() == 2,"Full-width extra lane gets a transition at both ends")
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	_check(absf(_area(mesh,road.road_material_override)-659.2) < 0.03,"S tapers add the exact union area with no overlap")
	_check(_covers(mesh,road.road_material_override,Vector2(3.4,-31)),"Curved entry adds asphalt outside the source endpoint")
	_check(not _covers(mesh,road.road_material_override,Vector2(3.7,-31)),"Entry eases in instead of forming a straight wedge")
	_check(_covers(mesh,road.sidewalk_material_override,Vector2(5.5,-28)),"Exterior sidewalk follows the taper")
	_check(not _covers(mesh,road.sidewalk_material_override,Vector2(3.9,-28)),"No old host sidewalk underneath taper asphalt")
	var digest := _digest(road)
	road.regenerate()
	_check(digest == _digest(road),"Smooth endpoint geometry is stable with warm caches")
	extra.lateral_join_start_transition_length = 0.0
	road.regenerate()
	_check(road.get_source_rebuild_stats().lateral_joins.transitions.size() == 1,"Per-end override disables only the entry")
	extra.lateral_join_start_transition_length = 6.0
	road.regenerate()
	mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	_check(absf(_area(mesh,road.road_material_override)-649.6) < 0.03,"Per-end length changes generated taper geometry")
	extra.lateral_join_start_transition_length = -1.0
	var profile := Curve.new()
	profile.add_point(Vector2(0,0),0,0)
	profile.add_point(Vector2(0.5,0.2),0,0)
	profile.add_point(Vector2(1,1),0,0)
	road.lateral_join_transition_profile = profile
	road.regenerate()
	_check(_digest(road) != digest,"Custom Curve changes the taper")
	road.lateral_join_transition_profile = null
	road.regenerate()
	_check(_digest(road) == digest,"Clearing custom Curve restores default smooth shape")
	extra.lateral_join_start_transition_length = 100.0
	road.regenerate()
	transitions = road.get_source_rebuild_stats().lateral_joins.transitions
	var limited := false
	for transition: Dictionary in transitions:
		if not transition.end:
			limited = transition.limited and absf(transition.length-17.5) < 0.03
	_check(limited,"Long transition is capped by the available host length: %s" % [transitions])
	extra.lateral_join_start_transition_length = -1.0
	road.move_child(extra,0)
	road.regenerate()
	_check(road.get_source_rebuild_stats().lateral_joins.transitions.size() == 2,"Host discovery works when extra lane is the first source")
	_check(absf(_area(road.get_node("GeneratedSplineRoadWelded").mesh,road.road_material_override)-659.2) < 0.03,"Source order does not change smooth asphalt union")
	road.move_child(extra,1)
	road.regenerate()
	_check(authored == var_to_bytes([extra.curve.get_point_position(0),extra.curve.get_point_position(1),
		extra.point_lanes_right,extra.point_lane_widths,extra.sidewalk_right_width]),"Transition controls leave authored source geometry intact")
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/roda-lateral-joins.png")
		camera.position = Vector3(34,30,-12)
		camera.look_at(Vector3(20,0,-28))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/roda-lateral-join-detail.png")
	print("SMOOTH ENDPOINTS ",road.get_source_rebuild_stats().lateral_joins.transitions)
	scene.free()
	await process_frame
