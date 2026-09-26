extends SceneTree
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const TERRAIN = preload("../scripts/spline_road/terrain_topology_builder.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _check_top_surface(mesh: Mesh, label: String) -> void:
	_check(mesh != null and mesh.get_surface_count() > 0, label + " has a surface")
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var front := 0
	var back := 0
	var used_vertices: Dictionary = {}
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in range(0, count - 2, 3):
		var ia := indices[i] if not indices.is_empty() else i
		var ib := indices[i + 1] if not indices.is_empty() else i + 1
		var ic := indices[i + 2] if not indices.is_empty() else i + 2
		used_vertices[ia] = true
		used_vertices[ib] = true
		used_vertices[ic] = true
		var y := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia]).y
		if y < -0.000001:
			front += 1
		elif y > 0.000001:
			back += 1
	_check(front > 0 and front > back * 10, label + " shows its front from above")
	var upward_normals := 0
	for index in used_vertices:
		if normals[index].y > 0.0:
			upward_normals += 1
	_check(not used_vertices.is_empty() and upward_normals > used_vertices.size() * 0.9, label + " lights from above")

func _road(name_: String, offset: Vector3) -> Node3D:
	var road := ROAD.new()
	road.name = name_
	road.position = offset
	road.rotation.y = 0.15
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.junction_geometry_mode = 1
	road.terrain_left_width = 4.0
	road.terrain_right_width = 4.0
	road.outer_wall_height = 2.0
	for i in range(3):
		var path := Path3D.new()
		path.name = "Arm%d" % i
		path.curve = Curve3D.new()
		path.curve.add_point(Vector3.ZERO)
		var angle := TAU * i / 3.0
		path.curve.add_point(Vector3(cos(angle)*22, 1.5, sin(angle)*22))
		road.add_child(path)
	return road

func _generate(terrain: Node3D) -> void:
	terrain.regenerate()
	while terrain.is_terrain_generation_pending():
		await process_frame

func _run() -> void:
	var scene := Node3D.new()
	var road := _road("Road", Vector3(-25, 3, 0))
	var other := _road("Other", Vector3(35, -2, 0))
	scene.add_child(road)
	scene.add_child(other)
	var terrain := TERRAIN.new()
	terrain.name = "Terrain"
	terrain.position = Vector3(3, -4, 5)
	terrain.bounds_mode = 1
	terrain.manual_size_xz = Vector2(140, 90)
	terrain.far_grid_step = 10.0
	terrain.near_road_step = 4.0
	terrain.near_road_width = 8.0
	terrain.generate_road_edge_collars = false
	terrain.auto_lane_profile_edge_collars = false
	terrain.terrain_edge_y_offset = 0.0
	terrain.noise_enabled = false
	terrain.incremental_generation_enabled = true
	for name_ in ["Road", "Other"]:
		for i in range(3):
			terrain.source_paths.append(NodePath("../%s/Arm%d" % [name_, i]))
	scene.add_child(terrain)
	root.add_child(scene)
	await _generate(terrain)
	_check(road.invert_faces and terrain.invert_faces, "New road and terrain face upward by default")
	_check_top_surface((road.get_node("GeneratedSplineRoadWelded") as MeshInstance3D).mesh, "Default road")
	_check_top_surface((terrain.get_node("GeneratedTopologyTerrain") as MeshInstance3D).mesh, "Default terrain")
	_check(terrain._final_road_networks().size() == 2, "Automatically resolve both source networks")
	_check(terrain._final_road_surface.active(), "Base terrain consumes final road geometry")
	_check(not terrain._active_generate_road_edge_collars, "No automatic collar when both options are disabled")
	var data: Dictionary = road.get_terrain_surface_data()
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var full_indices := 0
	for s in range(mesh.get_surface_count()):
		full_indices += mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()
	_check(data.indices.size() < full_indices, "Exclude built-in terrain and walls from the road mask")
	var triangles: int = terrain._final_road_surface._cut._triangles.size()
	var sample: Vector3 = terrain._final_road_surface._cut._triangles[0].points[0]
	var hit: Dictionary = terrain.get_terrain_height_at_world(terrain.to_global(sample))
	_check(absf(hit.y - terrain.to_global(sample).y) < 0.001, "World height query matches transformed final road")
	var signature: String = terrain._build_signature()
	road.junction_corner_radius += 2.0
	road.regenerate()
	_check(signature != terrain._build_signature(), "Junction-only edits invalidate terrain signature")
	await _generate(terrain)
	road.output_mode = 1
	other.output_mode = 1
	road.regenerate()
	other.regenerate()
	terrain.output_mode = 1
	await _generate(terrain)
	_check(road.get_node("GeneratedSplineRoadWelded").mesh == null, "Fixture really uses chunked road rendering")
	_check(terrain._final_road_surface.active(), "Final road fitting also works with chunked roads")
	_check(terrain.get_node_or_null("GeneratedTopologyTerrain") != null, "Chunked terrain is published")
	print("GENERAL TERRAIN networks=2 initial_mask_triangles=", triangles, " chunk_mask_triangles=", terrain._final_road_surface._cut._triangles.size())
	road.threaded_generation_enabled = true
	road.junction_corner_radius += 1.0
	road.regenerate()
	terrain.regenerate()
	_check(terrain._waiting_for_final_roads, "Terrain waits for a pending road worker")
	while terrain.is_terrain_generation_pending():
		await process_frame
	_check(terrain._final_road_surface.active(), "Deferred terrain rebuild completes after the road worker")
	var mask_count: int = terrain._final_road_surface._cut._triangles.size()
	var mixed := Path3D.new()
	mixed.name = "MixedPath"
	mixed.curve = Curve3D.new()
	mixed.curve.add_point(Vector3(-15, 0, 35))
	mixed.curve.add_point(Vector3(15, 0, 35))
	scene.add_child(mixed)
	terrain.source_paths.append(NodePath("../MixedPath"))
	await _generate(terrain)
	_check(terrain._final_road_surface._cut._triangles.size() > mask_count, "Mixed standalone paths retain a road cut beside final networks")
	road._clear_mesh_node()
	_check(road.get_terrain_surface_data().is_empty(), "Clearing the road drops final surface data")
	await process_frame
	scene.free()
	await process_frame
	# Plain paths outside a road network keep the existing terrain workflow.
	var standalone := Node3D.new()
	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(20, 0, 0))
	standalone.add_child(path)
	var fallback := TERRAIN.new()
	fallback.name = "Terrain"
	fallback.source_paths = [NodePath("../Path")]
	fallback.auto_outer_padding = 8
	fallback.near_road_width = 4
	fallback.near_road_step = 4
	fallback.generate_road_edge_collars = false
	fallback.auto_lane_profile_edge_collars = false
	standalone.add_child(fallback)
	root.add_child(standalone)
	await _generate(fallback)
	_check(not fallback._final_road_surface.active(), "Standalone paths retain path-based fallback")
	_check(fallback.get_node_or_null("GeneratedTopologyTerrain") != null, "Standalone terrain still generates")
	standalone.free()
	print("GENERAL TERRAIN ", "OK" if failures == 0 else "FAILED", " failures=", failures)
	quit(failures)
