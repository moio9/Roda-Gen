extends SceneTree

const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var road := _make_road()
	road.incremental_generation_enabled = "--incremental" in OS.get_cmdline_user_args()
	root.add_child(road)
	var full := _geometry(road)
	var full_collision := _collision_geometry(road)
	_check(not full.is_empty() and not full_collision.is_empty(), "full output has geometry and collision")
	road.output_mode = 1
	road.output_chunk_size = 25.0
	road.regenerate()
	var chunk_geometry := _geometry(road)
	if chunk_geometry != full:
		print("GEOMETRY_COUNTS full=%s chunks=%s" % [full.size(), chunk_geometry.size()])
		for i in range(mini(full.size(), chunk_geometry.size())):
			if full[i] != chunk_geometry[i]:
				print("FIRST_GEOMETRY_DIFF full=%s chunk=%s" % [bytes_to_var(full[i].hex_decode()), bytes_to_var(chunk_geometry[i].hex_decode())])
				break
	_check(chunk_geometry == full, "chunk triangles, normals, UVs and materials match single mesh")
	print("OUTPUT_STAGE initial_chunks=", road.get_output_rebuild_stats())
	_check(_collision_geometry(road) == full_collision, "chunk collision faces match single mesh")
	var before := _resource_ids(road)
	_check(before.size() > 3, "fixture creates spatially separate chunks")
	road.regenerate()
	_check(_resource_ids(road) == before, "unchanged chunk meshes and physics shapes are reused")
	print("OUTPUT_STAGE unchanged=", road.get_output_rebuild_stats())
	_check(int(road.get_output_rebuild_stats().get("rebuilt", -1)) == 0, "unchanged output rebuilds zero chunks")
	if road.incremental_generation_enabled:
		_check(road._runtime_output._partition_caches.size() == 5, "runtime retains all five partition surfaces")
		for surface: Dictionary in road.get_output_rebuild_stats().partition_surfaces:
			_check(surface.cells_rebuilt == 0 and surface.cells_reused > 0, "unchanged partition skips cell construction")
		road.clear_source_generation_cache()
		_check(road._runtime_output._partition_caches.is_empty(), "creator public clear drops partition stores")
		road.regenerate()
		_check(_resource_ids(road) == before, "clearing source caches still preserves unchanged output resources")
	var path := road.get_node("Remote") as Path3D
	path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(3, 1, 0))
	_check(road.bake_runtime_scene("/tmp/roda-stale-output.tscn") == ERR_BUSY, "stale source cannot be baked")
	road.regenerate()
	var changed_stats: Dictionary = road.get_output_rebuild_stats()
	print("OUTPUT_STAGE local_edit=", changed_stats)
	_check(int(changed_stats.get("rebuilt", 0)) > 0 and int(changed_stats.get("reused", 0)) > 0, "local edit rebuilds some chunks and retains others")
	var incremental := _geometry(road)
	var incremental_collision := _collision_geometry(road)
	# Material-only edits should not rebuild geometry or collision resources.
	var material_ids := _resource_ids(road)
	var replacement := StandardMaterial3D.new()
	replacement.resource_name = "UpdatedRoad"
	replacement.albedo_color = Color.DARK_RED
	road.road_material_override = replacement
	road.regenerate()
	_check(_resource_ids(road) == material_ids, "material replacement retains mesh and collision resources")
	for surface: Dictionary in road.get_output_rebuild_stats().partition_surfaces:
		_check(surface.cells_rebuilt == 0, "material-only edit reuses partition arrays")
	var baked_path := "/tmp/roda-runtime-%s.tscn" % Time.get_ticks_usec()
	_check(road.bake_runtime_scene(baked_path) == OK, "bake creates static packed scene")
	_check(road.bake_runtime_scene(baked_path) == ERR_ALREADY_EXISTS, "bake protects existing files")
	road.scene_file_path = "/tmp/roda-protected-source.tscn"
	_check(road.bake_runtime_scene(road.scene_file_path, true) == ERR_INVALID_PARAMETER, "bake cannot overwrite the editable source scene")
	road.scene_file_path = ""
	var packed := ResourceLoader.load(baked_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(packed != null, "saved bake reloads")
	if packed != null:
		var baked := packed.instantiate() as Node3D
		_check(baked.transform == road.transform, "bake keeps creator transform")
		_check(_geometry(baked) == _geometry(road), "bake retains triangles, attributes and materials")
		_check(_collision_geometry(baked) == _collision_geometry(road), "bake retains collision geometry")
		_check(_static_only(baked), "baked scene has no procedural scripts, Path3D or previews")
		var ray_target: Vector3 = road.get_path_surface_frame(path, 20.0).get("center", Vector3.ZERO)
		await physics_frame
		await physics_frame
		var source_hits := _physics_samples(road, ray_target)
		root.remove_child(road)
		root.add_child(baked)
		var saved_counts := _geometry(baked).size()
		await physics_frame
		await physics_frame
		var baked_hits := _physics_samples(baked, ray_target)
		_check(source_hits != [Vector3.INF, Vector3.INF], "physics probe actually hits the original road")
		_check(baked_hits == source_hits, "baked ray collision matches source from both directions")
		print("ROAD_RUNTIME_PHYSICS source=%s baked=%s" % [source_hits, baked_hits])
		_check(_geometry(baked).size() == saved_counts, "baked scene runs without regeneration")
		baked.free()
		root.add_child(road)
	# Rebuild single output from the changed source, independently of chunk resources.
	road.road_material_override = road.get_meta("original_road_material")
	road.output_mode = 0
	road.regenerate()
	_check(road.get_node_or_null("GeneratedRoadChunks") == null, "switch to single removes chunk output immediately")
	_check(road._runtime_output._partition_caches.is_empty(), "switch to single releases partition stores")
	_check(_geometry(road) == incremental, "local-edit chunk output equals fresh full generation")
	_check(_collision_geometry(road) == incremental_collision, "local-edit collisions equal fresh full generation")
	road.output_mode = 1
	road.threaded_generation_enabled = true
	road.regenerate()
	_check(road.bake_runtime_scene("/tmp/roda-in-progress-output.tscn") == ERR_BUSY, "threaded partial output cannot be baked")
	var deadline := Time.get_ticks_msec() + 15000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "threaded generation finishes")
	_check(_geometry(road) == incremental, "threaded chunk geometry matches synchronous full output")
	_check(_collision_geometry(road) == incremental_collision, "threaded chunk collision matches synchronous full output")
	road.output_mode = 0
	road.threaded_generation_enabled = false
	road.output_generate_collision = false
	road.regenerate()
	_check(_collision_geometry(road).is_empty(), "turning off automatic collision removes generated bodies")
	# A user's pre-existing body is retained and updated even with auto collision off.
	var instance := road.get_node("GeneratedSplineRoadWelded") as MeshInstance3D
	var user_body := StaticBody3D.new()
	user_body.name = "StaticBody3D"
	user_body.collision_layer = 16
	instance.add_child(user_body)
	var user_shape := CollisionShape3D.new()
	user_shape.name = "CollisionShape3D"
	user_body.add_child(user_shape)
	road.regenerate()
	_check(is_instance_valid(user_body) and user_body.collision_layer == 16 and user_shape.shape != null, "manual collision remains user-owned")
	road.output_mode = 1
	road.regenerate()
	_check(user_shape.shape == null, "inactive single mesh does not retain duplicate collision")
	_check(not _collision_geometry(road).is_empty(), "chunks inherit manually configured collision")
	for chunk: MeshInstance3D in road.get_node("GeneratedRoadChunks").get_children():
		_check(chunk.get_node("StaticBody3D").collision_layer == 16, "chunks inherit manual collision layer")
	road.source_paths.clear()
	for child in road.get_children():
		if child is Path3D:
			road.remove_child(child)
			child.free()
	road.regenerate()
	_check(road.get_node_or_null("GeneratedRoadChunks") == null, "empty source clears spatial output")
	road.free()
	print("ROAD_RUNTIME_OUTPUT_%s local_edit=%s baked=%s" % ["FAILED" if _failed else "OK", changed_stats, baked_path])
	quit(1 if _failed else 0)


func _make_road() -> Node3D:
	var road := ROAD.new()
	road.name = "RuntimeRoad"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.sample_step = 2.0
	road.output_generate_collision = true
	road.output_collision_layer = 8
	road.output_collision_mask = 5
	road.road_orientation_mode = 2
	road.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.3, 0)).scaled(Vector3(-1.2, 0.8, 1.1)), Vector3(-15, 2, 8))
	for property in ["road_material_override", "shoulder_material_override", "sidewalk_material_override", "terrain_material_override", "outer_wall_material_override"]:
		var mat := StandardMaterial3D.new()
		mat.resource_name = property
		road.set(property, mat)
	road.set_meta("original_road_material", road.road_material_override)
	var overlay := StandardMaterial3D.new()
	overlay.resource_name = "LaneOverlay"
	road.left_lane_material_overrides = [overlay]
	for arm in range(4):
		var path := PROFILE.new()
		path.name = "Remote" if arm == 3 else "Arm%d" % arm
		path.show_width_preview = false
		path.curve = Curve3D.new()
		var angle := TAU * float(arm) / 3.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var offset := Vector3(260, 10, 0) if arm == 3 else Vector3.ZERO
		for point in range(3):
			path.curve.add_point(offset + direction * float(point * 28) + Vector3.UP * point,
				-direction * 7.0 if point > 0 else Vector3.ZERO,
				direction * 7.0 if point < 2 else Vector3.ZERO)
			path.curve.set_point_tilt(point, 0.07 * point)
		path.point_widths = PackedFloat32Array([6, 8, 7])
		path.shoulder_left_width = 0.5
		path.shoulder_right_width = 0.8
		path.sidewalk_left_width = 0.7
		path.sidewalk_right_width = 0.4
		path.outer_wall_height = 1.2
		path.terrain_override_enabled = true
		path.terrain_left_width = 7.0
		path.terrain_right_width = 6.0
		road.add_child(path)
		road.source_paths.append(NodePath(path.name))
	return road


func _geometry(node: Node) -> Array[String]:
	var triangles: Array[String] = []
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material: Material = node.get_active_material(surface)
			for i in range(0, indices.size(), 3):
				var triangle: Array = [material.resource_name if material != null else ""]
				for corner in range(3):
					var index := indices[i + corner]
					triangle.append([vertices[index], normals[index], uvs[index]])
				triangles.append(var_to_bytes(triangle).hex_encode())
	for child in node.get_children():
		triangles.append_array(_geometry(child))
	triangles.sort()
	return triangles


func _collision_geometry(node: Node) -> Array[String]:
	var triangles: Array[String] = []
	if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
		var vertices: PackedVector3Array = node.shape.get_faces()
		for i in range(0, vertices.size(), 3):
			triangles.append(var_to_bytes(vertices.slice(i, i + 3)).hex_encode())
	for child in node.get_children():
		triangles.append_array(_collision_geometry(child))
	triangles.sort()
	return triangles


func _resource_ids(road: Node) -> Dictionary:
	var ids: Dictionary = {}
	for chunk: MeshInstance3D in road.get_node("GeneratedRoadChunks").get_children():
		var body := chunk.get_node("StaticBody3D") as StaticBody3D
		_check(body.collision_layer == 8 and body.collision_mask == 5, "chunk collision filters are retained")
		ids[str(chunk.name)] = [chunk.get_instance_id(), chunk.mesh.get_instance_id(), body.get_node("CollisionShape3D").shape.get_instance_id()]
	return ids


func _static_only(node: Node) -> bool:
	if node.get_script() != null or node is Path3D or "Preview" in str(node.name) or "Handle" in str(node.name):
		return false
	for child in node.get_children():
		if not _static_only(child):
			return false
	return true


func _physics_samples(output: Node3D, target: Vector3) -> Array[Vector3]:
	var hits: Array[Vector3] = []
	# A bake must preserve source sidedness, including inverted/mirrored geometry.
	for direction in [1.0, -1.0]:
		var query := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 20.0 * direction, target - Vector3.UP * 20.0 * direction, 8)
		query.hit_back_faces = true
		var hit := output.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and output.is_ancestor_of(hit.get("collider")):
			hits.append(hit.get("position"))
		else:
			hits.append(Vector3.INF)
	return hits


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("ROAD_RUNTIME_OUTPUT: " + message)
