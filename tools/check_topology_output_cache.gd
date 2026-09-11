extends "./check_local_topology_output.gd"

class UnsupportedOutput extends "../addons/scripts/spline_road/topology_output_cache.gd":
	func _partition(_arrays: Array, _cell_size: float) -> Dictionary:
		return {}

class UngroupedTriangles extends "../addons/scripts/spline_road/topology_triangle_cache.gd":
	func prepare(_points: PackedVector2Array, _indices: PackedInt32Array) -> Dictionary:
		return {}

class UngroupedCollars extends "../addons/scripts/spline_road/topology_collar_cache.gd":
	func configure(_enabled: bool, clear_requested: bool) -> void:
		super.configure(false, clear_requested)

class UngroupedPoints extends "../addons/scripts/spline_road/topology_point_cache.gd":
	func configure(_enabled: bool, clear_requested: bool) -> void:
		super.configure(false, clear_requested)

class RebuiltGridCoordinates extends "../addons/scripts/spline_road/topology_point_cache.gd":
	func grid_block(x: float, z: float, bounds: Rect2, step: float, epsilon: float) -> Dictionary:
		var result := _build_grid_block(x, z, bounds, step, epsilon)
		stats.grid_blocks_rebuilt += 1
		stats.grid_coordinates_rebuilt += result.points.size()
		return result

class NativeEmission extends "../addons/scripts/spline_road/topology_mesh_stream.gd":
	func begin(surface: SurfaceTool, _enabled: bool) -> void:
		super.begin(surface, false)

class IndividualTriangleEmission extends "../addons/scripts/spline_road/topology_triangle_cache.gd":
	func emit_run(_group: Dictionary, _first: int, _count: int, _inverted: bool,
			_stream: RefCounted, _surface: SurfaceTool) -> Dictionary:
		return {}

var _last_chunk_ms := 0.0

class RoundtripStream extends "../addons/scripts/spline_road/topology_mesh_stream.gd":
	func take_arrays(_surface: SurfaceTool) -> Array:
		return []

class RebuiltNearCoordinates extends "../addons/scripts/spline_road/topology_point_cache.gd":
	func _near_reuse_enabled() -> bool:
		return false

class RebuiltBoundaryCoordinates extends "../addons/scripts/spline_road/topology_point_cache.gd":
	func _boundary_reuse_enabled() -> bool:
		return false

class RebuiltPathSamples extends "../addons/scripts/spline_road/topology_path_cache.gd":
	func configure(_enabled: bool, clear_requested: bool) -> void:
		super.configure(false, clear_requested)

class RebuiltPathAssembly extends "../addons/scripts/spline_road/topology_path_cache.gd":
	func _assembly_reuse_enabled() -> bool:
		return false

class RejectRawOutput extends "../addons/scripts/spline_road/topology_output_cache.gd":
	func publish_raw(_builder: Node3D, _arrays: Array, _cell_size: float, _reuse: bool,
			_collision: bool, _material: Material, _local_normals: bool) -> bool:
		stats = {"fallback": "test_direct_rejection"}
		return false


func _run() -> void:
	var scene := Node3D.new()
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.generate_in_editor = false
	road.debug_generation_logs = false
	scene.add_child(road)
	var terrain := TOPOLOGY.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.road_network_source = NodePath("../Road")
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(80, 20)
	terrain.manual_size_xz = Vector2(340, 220)
	terrain.near_road_width = 12
	terrain.near_road_step = 6
	terrain.far_grid_step = 12
	terrain.generate_collision = true
	terrain.incremental_generation_enabled = true
	terrain.output_mode = 1
	terrain.output_chunk_size = 48
	var large := OS.get_cmdline_user_args().has("--large")
	if large:
		terrain.centered_triangulation_enabled = true
		terrain.local_triangulation_enabled = true
		terrain.manual_center_xz = Vector2(350, 20)
		terrain.manual_size_xz = Vector2(950, 220)
	var path: Path3D
	for i in range(10 if large else 3):
		var other := PROFILE.new()
		other.name = "Path" + str(i)
		other.position.x = i * 85
		other.curve = Curve3D.new()
		for p in [Vector3(-35, 0, -30), Vector3(-20, 2, 0), Vector3(0, 4, 30), Vector3(20, 0, 60)]:
			other.curve.add_point(p, Vector3(0, 0, -10), Vector3(0, 0, 10))
		road.add_child(other)
		terrain.source_paths.append(NodePath("../Road/" + str(other.name)))
		if i == 0:
			path = other
	scene.add_child(terrain)
	root.add_child(scene)
	if DisplayServer.get_name() != "headless":
		_setup_visual(scene, terrain)
	_build(terrain)
	var initial := _ids(terrain)
	_check(initial.size() > 4, "actual terrain publishes several mesh/collision cells")
	await _compare_single(terrain, "cold", false)
	_initial_image = await _capture_output("chunks_initial")
	if OS.get_cmdline_user_args().has("--physics-only"):
		scene.free()
		quit(1 if _failed else 0)
		return
	_build(terrain)
	_check(_ids(terrain) == initial, "warm output retains node, mesh, collider and shape identities")
	_check(terrain.get_source_rebuild_stats().output.mesh_rebuilt == 0 and terrain.get_source_rebuild_stats().output.collision_rebuilt == 0,
		"warm output creates no mesh or collision resources")
	var warm_normals: Dictionary = terrain.get_source_rebuild_stats().output.normals
	var warm_groups: Dictionary = terrain.get_source_rebuild_stats().triangle_groups
	_check(warm_groups.triangles_reused > 0 and warm_groups.triangles_rebuilt == 0,
		"warm output skips all candidate triangle filtering and height fitting")
	_check(warm_groups.candidates_bulk == warm_groups.triangles_reused and warm_groups.runs_reused > 0,
		"warm output skips individual emission for every certified triangle candidate")
	var warm_collars: Dictionary = terrain.get_source_rebuild_stats().collar_groups
	_check(warm_collars.triangles_reused > 0 and warm_collars.triangles_rebuilt == 0,
		"warm output skips all collar block construction")
	var warm_points: Dictionary = terrain.get_source_rebuild_stats().point_groups
	_check(warm_points.bounds_coordinates_reused > 0 and warm_points.bounds_coordinates_rebuilt == 0
		and warm_points.edge_coordinates_reused > 0 and warm_points.edge_coordinates_rebuilt == 0,
		"warm output retains exact bounds and polygon contour coordinates")
	_check(warm_points.near_rows_reused > 0 and warm_points.near_rows_rebuilt == 0
		and warm_points.near_coordinates_reused > 0 and warm_points.near_coordinates_rebuilt == 0,
		"warm generation retains near-row selection and ring coordinates")
	_check(warm_points.candidates_reused > 0 and warm_points.candidates_rebuilt == 0,
		"warm point blocks skip every near-ring and grid road-mask query")
	_check(warm_points.grid_coordinates_reused > 0 and warm_points.grid_coordinates_rebuilt == 0,
		"warm generation does not enumerate grid coordinates again")
	var warm_stream: Dictionary = terrain.get_source_rebuild_stats().mesh_stream
	_check(warm_stream.vertices_bulk > 0 and warm_stream.flushes == 1 and not warm_stream.capacity_fallback,
		"warm output appends complete cached collar blocks and flushes one native stream")
	_check(warm_stream.direct_arrays and terrain.get_source_rebuild_stats().output.source_surface_builds == 0,
		"warm direct output never builds the complete source SurfaceTool")
	_check(warm_normals.full_calls == 0 and warm_normals.patch_calls == 0 and warm_normals.vertices_rebuilt == 0,
		"warm spatial output skips native normals and partitioning")
	var before_normals: Array = bytes_to_var(terrain._output_cache._normal_cache._input)[0]
	path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(0.25, 0.1, 0))
	road.regenerate()
	var started := Time.get_ticks_usec()
	_build(terrain)
	_last_chunk_ms = float(Time.get_ticks_usec() - started) / 1000.0
	var local: Dictionary = terrain.get_source_rebuild_stats().output
	_check(terrain.get_source_rebuild_stats().mesh_stream.direct_arrays and local.source_surface_builds == 0,
		"local direct output constructs only the dirty normal patch, not a complete source SurfaceTool")
	_check(local.mesh_reused > 0 and local.mesh_rebuilt > 0 and local.collision_reused > 0 and local.collision_rebuilt > 0,
		"local road edit mixes retained and replaced real mesh/collision resources")
	print("TOPOLOGY_OUTPUT_LOCAL ", local)
	print("TOPOLOGY_TRIANGLE_GROUPS_LOCAL ", terrain.get_source_rebuild_stats().triangle_groups)
	print("TOPOLOGY_COLLAR_GROUPS_LOCAL ", terrain.get_source_rebuild_stats().collar_groups)
	print("TOPOLOGY_POINT_GROUPS_LOCAL ", terrain.get_source_rebuild_stats().point_groups)
	print("TOPOLOGY_MESH_STREAM_LOCAL ", terrain.get_source_rebuild_stats().mesh_stream)
	var local_paths: Dictionary = terrain.get_source_rebuild_stats().path_samples
	_check(local_paths.paths_reused == terrain.source_paths.size() - 1 and local_paths.paths_rebuilt == 1,
		"local output edit resamples only the changed native path")
	_check(local_paths.polygons_reused == local_paths.paths_reused and local_paths.polygons_rebuilt == 1
		and local_paths.segments_reused == local_paths.rows_reused - local_paths.paths_reused,
		"local output edit retains complete contours and segments of unchanged paths")
	print("TOPOLOGY_PATH_SAMPLES_LOCAL ", local_paths)
	var local_points: Dictionary = terrain.get_source_rebuild_stats().point_groups
	_check(local_points.bounds_coordinates_reused > 0 and local_points.bounds_coordinates_rebuilt == 0
		and local_points.edge_coordinates_reused > 0 and local_points.edge_coordinates_rebuilt > 0,
		"local road edit retains bounds and unchanged contour edges")
	_check(local_points.near_rows_reused > 0 and local_points.near_rows_rebuilt > 0
		and local_points.near_coordinates_reused > 0 and local_points.near_coordinates_rebuilt > 0,
		"local edits reconstruct changed near-road coordinates but retain other paths")
	_check(local_points.candidates_reused > 0 and local_points.candidates_rebuilt > 0,
		"local edits retain unaffected near-ring/grid point masks")
	_check(local_points.grid_coordinates_reused > 0 and local_points.grid_coordinates_rebuilt == 0,
		"fixed-bounds road edit retains grid coordinates independently of changed masks")
	var local_collars: Dictionary = terrain.get_source_rebuild_stats().collar_groups
	_check(local_collars.triangles_reused > 0 and local_collars.triangles_rebuilt > 0,
		"local edit retains unaffected collar blocks")
	var local_groups: Dictionary = terrain.get_source_rebuild_stats().triangle_groups
	_check(terrain.get_source_rebuild_stats().mesh_stream.vertices_bulk == (local_collars.triangles_reused + local_groups.emission_triangles_reused) * 3,
		"every retained collar and triangle-run vertex reaches output through bulk append")
	_check(local_groups.candidates_bulk == local_groups.triangles_reused and local_groups.emission_triangles_reused > 0,
		"retained triangle candidates skip individual emission without changing global order")
	_check(local_groups.triangles_reused > 0 and local_groups.triangles_rebuilt > 0,
		"local edit retains unaffected filtered/height-fitted triangle groups")
	_check(local.normals.full_calls == 0 and local.normals.patch_calls == 1
		and local.normals.vertices_reused > 0 and local.normals.vertices_rebuilt > 0, "local output uses complete dirty-vertex normal stars, not a global normal pass")
	if OS.get_cmdline_user_args().has("--normal-benchmark"):
		_benchmark_normals(before_normals, bytes_to_var(terrain._output_cache._normal_cache._input)[0], terrain.output_chunk_size)
	if large:
		var topology: Dictionary = terrain.get_source_rebuild_stats().local_triangulation
		_check(topology.get("local_calls", 0) > 0 and topology.get("fallback", "") == "",
			"retained spatial output is exercised with an actual successful local triangulation")
	await _compare_single(terrain, "local edit", true)
	for stage: String in ["triangle", "collar", "point", "grid", "stream", "emission", "direct", "near", "boundary", "path", "assembly"]:
		if OS.get_cmdline_user_args().has("--" + stage + "-benchmark"):
			_benchmark_reuse_stage(terrain, path, road, stage)
	var current := _ids(terrain)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.15, 0.1)
	terrain.terrain_material_override = material
	_build(terrain)
	_check(_ids(terrain) == current, "material changes preserve geometry and physics resources")
	var first: MeshInstance3D = terrain.get_node("GeneratedTopologyTerrain").get_child(0)
	_check(first.material_override == material, "retained chunks receive the current material")
	first.position.y = 90
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.mesh_rebuilt == 1, "manual chunk transform mutation rebuilds only that cell")
	await _compare_single(terrain, "manual transform repair", false)
	first = terrain.get_node("GeneratedTopologyTerrain").get_child(0)
	first.mesh.clear_surfaces()
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.mesh_rebuilt == 1, "in-place mesh mutation is not hidden by an old fingerprint")
	first = terrain.get_node("GeneratedTopologyTerrain").get_child(0)
	first.mesh.surface_set_material(0, StandardMaterial3D.new())
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.mesh_rebuilt == 1, "manual mesh surface material cannot survive a retained fingerprint")
	var shape: CollisionShape3D = terrain.get_node("GeneratedTopologyTerrainCollision").get_child(0)
	shape.disabled = true
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.collision_rebuilt == 1, "manual collider mutation is repaired independently")
	shape = terrain.get_node("GeneratedTopologyTerrainCollision").get_child(0)
	shape.shape.set_faces(PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]))
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.collision_rebuilt == 1, "in-place collision resource mutation is revalidated")
	shape = terrain.get_node("GeneratedTopologyTerrainCollision").get_child(0)
	shape.shape.backface_collision = not shape.shape.backface_collision
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.collision_rebuilt == 1, "collision resource settings are revalidated as well as faces")
	await _compare_single(terrain, "resource repairs", false)
	var modifier := DynamicModifier.new()
	terrain.add_child(modifier)
	_build(terrain)
	var modifier_calls: int = modifier.calls
	current = _ids(terrain)
	_build(terrain)
	_check(modifier.calls > modifier_calls and _ids(terrain) == current,
		"unchanged modifier output can retain resources without skipping modifier callbacks")
	await _compare_single(terrain, "modifier output", false)
	modifier.free()
	_build(terrain)
	terrain.generate_collision = false
	_build(terrain)
	_check(terrain.get_node_or_null("GeneratedTopologyTerrainCollision") == null, "collision toggle removes every old shape")
	terrain.generate_collision = true
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().output.mesh_rebuilt == 0 and terrain.get_source_rebuild_stats().output.collision_rebuilt == _ids(terrain).size(),
		"re-enabling collisions preserves every mesh")
	terrain.output_chunk_size = 32
	_build(terrain)
	await _compare_single(terrain, "chunk size change", false)
	terrain.threaded_triangulation_enabled = true
	current = _ids(terrain)
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	_check(terrain._triangulation_thread != null and _ids(terrain) == current, "old complete output remains while an actual worker is pending")
	terrain.output_chunk_size = 48
	terrain.regenerate()
	await _wait_terrain(terrain)
	_check(terrain._output_context.cell_size == 48, "queued restart publishes the latest chunk size")
	terrain.threaded_triangulation_enabled = false
	await _compare_single(terrain, "worker restart", false)
	terrain.threaded_triangulation_enabled = true
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	terrain.regenerate()
	terrain._clear_generated_from_button()
	await _wait_terrain(terrain)
	_check(terrain.get_node_or_null("GeneratedTopologyTerrain") == null and terrain._output_cache._records.is_empty(),
		"Clear Generated cancels pending publication and releases output snapshots")
	_check(terrain._output_cache._normal_cache._cells.is_empty() and terrain._output_cache._normal_cache._order.is_empty(), "Clear Generated also releases all normal support")
	terrain.threaded_triangulation_enabled = false
	_build(terrain)
	terrain.output_mode = 0
	_build(terrain)
	_check(terrain.get_node("GeneratedTopologyTerrain") is MeshInstance3D and terrain._output_cache._records.is_empty(),
		"switching back to single mesh removes every retained chunk")
	terrain.output_mode = 1
	_build(terrain)
	terrain._output_cache = UnsupportedOutput.new()
	terrain.incremental_generation_enabled = false
	_build(terrain)
	_check(terrain.get_node("GeneratedTopologyTerrain") is MeshInstance3D
		and terrain.get_source_rebuild_stats().output.fallback == "unsupported_or_excessive_chunks", "unsupported partition falls back to a complete native mesh")
	await _compare_single(terrain, "partition fallback", false)
	terrain.incremental_generation_enabled = true
	terrain._output_cache = RejectRawOutput.new()
	_build(terrain)
	_check(terrain.get_node("GeneratedTopologyTerrain") is MeshInstance3D
		and terrain.get_source_rebuild_stats().mesh_stream.direct_arrays
		and terrain.get_source_rebuild_stats().output.fallback == "test_direct_rejection",
		"rejected direct publication materializes a complete native single-mesh fallback")
	await _compare_single(terrain, "direct output rejection fallback", false)
	terrain._output_cache = load("res://addons/scripts/spline_road/topology_output_cache.gd").new()
	terrain.incremental_generation_enabled = true
	_build(terrain)
	terrain.source_paths.clear()
	_build(terrain)
	_check(terrain.get_node_or_null("GeneratedTopologyTerrain") == null and terrain.get_node_or_null("GeneratedTopologyTerrainCollision") == null,
		"empty generation removes the previous complete output")
	scene.free()
	print("TOPOLOGY_OUTPUT_CACHE_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _ids(terrain: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: MeshInstance3D in terrain.get_node("GeneratedTopologyTerrain").get_children():
		var shape := terrain.get_node_or_null("GeneratedTopologyTerrainCollision/" + str(node.name)) as CollisionShape3D
		result[str(node.name)] = [node.get_instance_id(), node.mesh.get_instance_id(),
			shape.get_instance_id() if shape != null else 0, shape.shape.get_instance_id() if shape != null else 0]
	return result


func _compare_single(terrain: Node, label: String, render: bool) -> void:
	var reference := TOPOLOGY.new()
	for property: Dictionary in terrain.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			reference.set(property.name, terrain.get(property.name))
	reference.output_mode = 0
	reference.incremental_generation_enabled = false
	reference.threaded_triangulation_enabled = false
	reference.generate_in_editor = false
	reference.transform = terrain.transform
	for modifier: Node in terrain._active_height_modifiers:
		if modifier is DynamicModifier:
			var copy := DynamicModifier.new()
			copy.amount = modifier.amount
			reference.add_child(copy)
	terrain.get_parent().add_child(reference)
	var started := Time.get_ticks_usec()
	_build(reference)
	if label == "local edit":
		print("TOPOLOGY_OUTPUT_TOTAL_TIME chunked_local_ms=", _last_chunk_ms, " single_full_ms=", float(Time.get_ticks_usec() - started) / 1000.0)
	_check(_snapshot(terrain) == _snapshot(reference), "exact oriented positions/UVs/normals/collision versus single mesh: " + label)
	if label == "cold":
		var chunk_body: StaticBody3D = terrain.get_node("GeneratedTopologyTerrainCollision")
		var single_body: StaticBody3D = reference.get_node("GeneratedTopologyTerrainCollision")
		chunk_body.collision_layer = 8
		single_body.collision_layer = 16
		await physics_frame
		await physics_frame
		var queries := 0
		for shape: CollisionShape3D in chunk_body.get_children():
			var faces: PackedVector3Array = shape.shape.get_faces()
			var point: Vector3 = terrain.to_global((faces[0] + faces[1] + faces[2]) / 3.0)
			# Native ConcavePolygonShape3D is one-sided. Query its clockwise
			# front face for either invert_faces setting, not an assumed world up.
			var front: Vector3 = -(terrain.global_transform.basis * (faces[1] - faces[0]).cross(faces[2] - faces[0])).normalized()
			var ray := PhysicsRayQueryParameters3D.create(point + front * 10, point - front * 10, 8)
			ray.hit_back_faces = true
			var chunk_hit: Dictionary = terrain.get_world_3d().direct_space_state.intersect_ray(ray)
			ray.collision_mask = 16
			var single_hit: Dictionary = terrain.get_world_3d().direct_space_state.intersect_ray(ray)
			print("TOPOLOGY_PHYSICS_SAMPLE point=", point, " delta=", chunk_hit.position.distance_to(single_hit.position) if not chunk_hit.is_empty() and not single_hit.is_empty() else -1.0)
			_check(not chunk_hit.is_empty() and not single_hit.is_empty() and chunk_hit.position.distance_to(single_hit.position) < 0.0001,
				"live physics ray hits agree across chunk cells")
			queries += 1
			if queries >= 10:
				break
		chunk_body.collision_layer = 1
	if render and DisplayServer.get_name() != "headless":
		reference.visible = false
		var chunked := await _capture_output("chunks")
		var chunk_draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		terrain.visible = false
		reference.visible = true
		var single := await _capture_output("single")
		var single_draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var difference := _pixel_difference(chunked, single)
		_check(difference == 0, "actual chunked and single-mesh terrain renders match pixel-for-pixel")
		var pixels := chunked.get_data()
		var green := 0
		for i in range(0, pixels.size(), 4):
			if pixels[i + 1] > 30 and pixels[i + 1] > pixels[i] * 1.4 and pixels[i + 1] > pixels[i + 2] * 1.4:
				green += 1
		_check(green > 1000, "actual terrain is visible in the chunk render comparison")
		var edited := _pixel_difference(_initial_image, chunked)
		_check(edited > 100, "local road edit visibly changes the chunked terrain")
		print("TOPOLOGY_CHUNKS_RENDER changed_pixels=", difference, " edit_pixels=", edited, " chunk_draws=", chunk_draws, " single_draws=", single_draws)
		terrain.visible = true
	reference.free()


func _benchmark_normals(before: Array, after: Array, cell_size: float) -> void:
	var helper = load("res://addons/scripts/spline_road/topology_output_cache.gd")
	var cached = helper.new()
	var native = helper.new()
	var cached_parent := Node3D.new()
	var native_parent := Node3D.new()
	root.add_child(cached_parent)
	root.add_child(native_parent)
	cached_parent.visible = false
	native_parent.visible = false
	var timings := {"warm_cached": [], "warm_native": [], "local_cached": [], "local_native": []}
	for i in range(5):
		for pair: Array in [[cached, cached_parent, true, "cached"], [native, native_parent, false, "native"]]:
			_benchmark_publish(pair, before, cell_size)
			timings["warm_" + pair[3]].append(_benchmark_publish(pair, before, cell_size))
			timings["local_" + pair[3]].append(_benchmark_publish(pair, after, cell_size))
	for label: String in timings:
		timings[label].sort()
		print("TOPOLOGY_NORMAL_BENCH ", label, " median_ms=", timings[label][2])
	cached.clear()
	native.clear()
	cached_parent.free()
	native_parent.free()


func _benchmark_reuse_stage(terrain: Node, path: Path3D, road: Node, stage: String) -> void:
	var reference := TOPOLOGY.new()
	for property: Dictionary in terrain.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			reference.set(property.name, terrain.get(property.name))
	match stage:
		"triangle": reference._triangle_cache = UngroupedTriangles.new()
		"collar": reference._collar_cache = UngroupedCollars.new()
		"point": reference._point_cache = UngroupedPoints.new()
		"grid": reference._point_cache = RebuiltGridCoordinates.new()
		"stream": reference._mesh_stream = NativeEmission.new()
		"emission": reference._triangle_cache = IndividualTriangleEmission.new()
		"direct": reference._mesh_stream = RoundtripStream.new()
		"near": reference._point_cache = RebuiltNearCoordinates.new()
		"boundary": reference._point_cache = RebuiltBoundaryCoordinates.new()
		"path": reference._path_cache = RebuiltPathSamples.new()
		"assembly": reference._path_cache = RebuiltPathAssembly.new()
	var label_prefix := "TOPOLOGY_" + stage.to_upper() + "_BENCH"
	var stat_key: String = {"triangle": "triangle_groups", "collar": "collar_groups", "point": "point_groups",
		"grid": "point_groups", "stream": "mesh_stream", "emission": "triangle_groups", "direct": "output", "near": "point_groups", "boundary": "point_groups", "path": "path_samples", "assembly": "path_samples"}[stage]
	reference.generate_in_editor = false
	reference.threaded_triangulation_enabled = false
	terrain.get_parent().add_child(reference)
	_build(reference)
	_build(reference)
	var timings := {"warm_grouped": [], "warm_ungrouped": [], "local_grouped": [], "local_ungrouped": []}
	for edit in range(5):
		for pair: Array in [[terrain, "grouped"], [reference, "ungrouped"]]:
			var started := Time.get_ticks_usec()
			_build(pair[0])
			timings["warm_" + pair[1]].append(float(Time.get_ticks_usec() - started) / 1000.0)
		path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(0.25, 0.1, 0))
		road.regenerate()
		# Alternate timed build order; both nodes retain their independent caches.
		var pairs: Array = [[terrain, "grouped"], [reference, "ungrouped"]]
		if edit % 2 == 1:
			pairs.reverse()
		for pair: Array in pairs:
			var started := Time.get_ticks_usec()
			_build(pair[0])
			timings["local_" + pair[1]].append(float(Time.get_ticks_usec() - started) / 1000.0)
		_check(_snapshot(terrain) == _snapshot(reference), "distinct edit grouped vs ungrouped exact mesh/collision " + str(edit))
		_check(terrain._triangle_reject_stats == reference._triangle_reject_stats,
			"group replay preserves rejection counters " + str(edit))
		_check(terrain._normal_winding_fixes == reference._normal_winding_fixes,
			"stream output preserves winding correction counters " + str(edit))
		if stage == "direct":
			_check(terrain.get_source_rebuild_stats().output.source_surface_builds == 0
				and reference.get_source_rebuild_stats().output.source_surface_builds == 1,
				"isolated direct comparison skips exactly the full source materialization " + str(edit))
		if stage == "path" and edit >= 2:
			_check(terrain.get_source_rebuild_stats().path_samples.paths_reused == terrain.source_paths.size() - 1
				and terrain.get_source_rebuild_stats().path_samples.paths_rebuilt == 1,
				"alternating shared-curve variants retain all unchanged paths " + str(edit))
		if stage == "assembly" and edit >= 2:
			var retained: Dictionary = terrain.get_source_rebuild_stats().path_samples
			var rebuilt: Dictionary = reference.get_source_rebuild_stats().path_samples
			_check(retained.paths_reused == terrain.source_paths.size() - 1
				and rebuilt.paths_reused == retained.paths_reused,
				"isolated assembly comparison retains identical native path samples " + str(edit))
			_check(retained.polygons_reused == retained.paths_reused and rebuilt.polygons_reused == 0
				and rebuilt.polygons_rebuilt == terrain.source_paths.size(),
				"isolated assembly comparison skips only unchanged contour/segment assembly " + str(edit))
		print(label_prefix, "_STAGES edit=", edit, " grouped=", terrain.get_source_rebuild_stats().stage_ms,
			" ungrouped=", reference.get_source_rebuild_stats().stage_ms, " groups=", terrain.get_source_rebuild_stats()[stat_key])
	for label: String in timings:
		timings[label].sort()
		print(label_prefix, " ", label, " median_ms=", timings[label][2])
	reference.free()


func _benchmark_publish(pair: Array, arrays: Array, cell_size: float) -> float:
	var surface := SurfaceTool.new()
	surface.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	var started := Time.get_ticks_usec()
	pair[0].publish_surface(pair[1], surface, cell_size, true, true, null, pair[2])
	return float(Time.get_ticks_usec() - started) / 1000.0
