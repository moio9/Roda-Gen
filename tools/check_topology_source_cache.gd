extends "./check_road_terrain_cache.gd"

const TOPOLOGY = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
const ORIGINAL_MESH_SHA256 := "5017b1a6c77c73fbdc3046362726e266b84ae253a3897f1d94c0ccb8497bb7ce"

class DynamicModifier extends Node:
	var enabled := true
	var amount := 3.0
	var calls := 0
	func modify_height(_builder: Node, _point: Vector2, height: float, _road_info: Dictionary) -> float:
		calls += 1
		return height + amount

class CustomTerrain extends TOPOLOGY:
	pass


func _run() -> void:
	var scene := Node3D.new()
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.sample_step = 4
	var first := _path("First", Vector3(-40, 0, 0))
	var second := _path("Second", Vector3(50, 3, 0))
	road.add_child(first)
	road.add_child(second)
	scene.add_child(road)
	var terrain := TOPOLOGY.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/First"), NodePath("../Road/Second")])
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(0, 40)
	terrain.manual_size_xz = Vector2(160, 120)
	terrain.near_road_width = 12
	terrain.near_road_step = 6
	terrain.far_grid_step = 16
	terrain.generate_collision = true
	scene.add_child(terrain)
	root.add_child(scene)
	_build(terrain)
	var original := _terrain_geometry(terrain)
	_check(original.size() > 1, "fixture has actual separate terrain mesh and collision")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(original.slice(0, 1)))
	_check(digest.finish().hex_encode() == ORIGINAL_MESH_SHA256, "full mesh matches hash captured before source-cache implementation")
	terrain.incremental_generation_enabled = true
	_build(terrain)
	_check(original == _terrain_geometry(terrain), "cold cache preserves full mesh and actual collision")
	_build(terrain)
	var warm: Dictionary = terrain.get_source_rebuild_stats()
	_check(warm.nearest_reused == 0 and warm.nearest_rebuilt == 0, "warm triangle and collar replay skip nearest queries entirely")
	_check(warm.heights_reused == 0 and warm.heights_rebuilt == 0 and warm.collar_groups.triangles_reused > 0
		and warm.collar_groups.triangles_rebuilt == 0, "warm collar groups skip all repeated height fitting")
	_check(warm.delaunay_reused == 1 and warm.delaunay_rebuilt == 0, "unchanged point sets skip native Delaunay")
	_check(warm.triangle_groups.triangles_reused > 0 and warm.triangle_groups.triangles_rebuilt == 0
		and warm.crossings_reused == 0 and warm.crossings_rebuilt == 0, "warm triangle groups skip crossing queries entirely")
	_check(original == _terrain_geometry(terrain), "warm source replay preserves actual mesh/collision")
	for i in range(4):
		_build(terrain)
	_check(terrain.get_source_rebuild_stats().nearest_rebuilt == 0 and _terrain_geometry(terrain) == original,
		"nested revision entries remain valid beyond idle expiry on unchanged builds")
	var legacy_signature: String = terrain._build_signature()
	terrain.centered_triangulation_enabled = true
	_check(terrain._build_signature() != legacy_signature, "centering participates in editor regeneration signature")
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().delaunay_rebuilt == 1,
		"centering cannot reuse legacy triangulation indices for identical raw points")
	_assert_terrain_full_equal(terrain, "centered triangulation mesh and collision")
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().delaunay_reused == 1, "centered triangulation has its own warm cache")
	terrain.centered_triangulation_enabled = false
	_build(terrain)
	_check(_terrain_geometry(terrain) == original, "disabling centering restores exact legacy mesh and collision")
	first.curve.set_point_position(1, first.curve.get_point_position(1) + Vector3(4, 2, 0))
	_build(terrain)
	var local: Dictionary = terrain.get_source_rebuild_stats()
	_check(local.nearest_reused > 0 and local.nearest_rebuilt > 0, "local road edit keeps and rebuilds nearest-query prefixes")
	_check(local.heights_reused > 0 and local.heights_rebuilt > 0, "local road edit keeps and rebuilds heights")
	_check(local.triangle_groups.triangles_reused > 0 and local.triangle_groups.triangles_rebuilt > 0
		and local.crossings_rebuilt > 0, "local edit reuses filtered groups and evaluates crossings for changed groups")
	_check(_terrain_geometry(terrain) != original, "local edit changes actual terrain")
	_assert_terrain_full_equal(terrain, "local curve edit")
	print("TOPOLOGY_SOURCE_LOCAL ", local)
	first.curve.set_point_tilt(1, 0.25)
	_build(terrain)
	_assert_terrain_full_equal(terrain, "banked surface frame")
	terrain.left_profile_heights = PackedFloat32Array([0, 1, 4, 12, 18])
	_build(terrain)
	_check(terrain._get_cached_road_data().segments[0].terrain_profile.left_heights == terrain.left_profile_heights,
		"default profile edits refresh profiles copied into road segments")
	_assert_terrain_full_equal(terrain, "default terrain profile revision")
	first.shoulder_left_width += 1
	terrain.invalidate_road_data_cache()
	_build(terrain)
	_assert_terrain_full_equal(terrain, "explicit edge-width invalidation")
	terrain.source_paths.reverse()
	_build(terrain)
	_assert_terrain_full_equal(terrain, "path reordering and current path IDs")
	terrain.noise_seed = 911
	_build(terrain)
	_assert_terrain_full_equal(terrain, "new noise field")
	terrain.road_edge_height_snap_distance = 2.5
	terrain.terrain_edge_y_offset = 0.15
	_build(terrain)
	_assert_terrain_full_equal(terrain, "edge locking and exact edge lookup")
	terrain.near_road_step = 4
	terrain.far_grid_step = 12
	_build(terrain)
	_assert_terrain_full_equal(terrain, "resampled edge heights and spatial cell size")
	terrain.transform = Transform3D(Basis.from_euler(Vector3(0, 0.1, 0)).scaled(Vector3(-1, 1.2, 1.1)), Vector3(5, 1, -4))
	_build(terrain)
	_assert_terrain_full_equal(terrain, "mirrored/nonuniform terrain transform")
	terrain.invert_faces = not terrain.invert_faces
	_build(terrain)
	_assert_terrain_full_equal(terrain, "winding remains independent of source heights")
	var modifier := DynamicModifier.new()
	terrain.add_child(modifier)
	_build(terrain)
	var previous_calls := modifier.calls
	_build(terrain)
	_check(modifier.calls > previous_calls and terrain.get_source_rebuild_stats().height_modifier_bypasses > 0
		and not terrain.get_source_rebuild_stats().enabled,
		"custom modifiers execute during warm builds without a trusted revision contract")
	_assert_terrain_full_equal(terrain, "custom modifier bypass")
	modifier.amount = -4
	_build(terrain)
	_assert_terrain_full_equal(terrain, "custom modifier changes without a signature")
	modifier.free()
	_build(terrain)
	_assert_terrain_full_equal(terrain, "modifier removed")
	var world_probe := Vector3(0, 0, 40)
	first.position.x += 5
	var hit: Dictionary = terrain.get_terrain_height_at_world(world_probe)
	var new_data: Dictionary = terrain._get_cached_road_data()
	var local_probe: Vector3 = terrain.to_local(world_probe)
	var probe_xz := Vector2(local_probe.x, local_probe.z)
	var expected_info: Dictionary = terrain._nearest_road_info_spatial_uncached(probe_xz, new_data.segments)
	var expected_y: float = terrain._sample_height_from_road_info_uncached(probe_xz, expected_info)
	_check(hit.get("hit", false) and hit.y == terrain.to_global(Vector3(local_probe.x, expected_y, local_probe.z)).y,
		"live query refreshes same-count moved roads instead of mixing a stale spatial index")
	_build(terrain)
	_assert_terrain_full_equal(terrain, "regeneration after external live terrain queries")
	_test_query_support(terrain)
	terrain.clear_source_generation_cache()
	_check(terrain._source_cache._entries.is_empty() and not terrain._source_cache.spatial_ready, "idle clear releases queries and invalidates cell revision context")
	var probe := Vector2(0, 40)
	var data: Dictionary = terrain._get_cached_road_data()
	_check(terrain._nearest_road_info(probe, data.segments) == terrain._nearest_road_info_spatial_uncached(probe, data.segments),
		"queries after public clearing cannot use an empty cell-revision context")
	_build(terrain)
	terrain.centered_triangulation_enabled = true
	await _test_worker(terrain, first)
	terrain.centered_triangulation_enabled = false
	_build(terrain)
	_benchmark(terrain, first)
	terrain.generate_road_edge_collars = false
	terrain.auto_lane_profile_edge_collars = false
	terrain.add_road_boundary_support_points = true
	_build(terrain)
	_assert_terrain_full_equal(terrain, "native boundary support without collars")
	_check(terrain.get_source_rebuild_stats().point_groups.support_coordinates_reused > 0
		and terrain.get_source_rebuild_stats().point_groups.support_coordinates_rebuilt == 0,
		"warm complete mesh actually reuses boundary-support coordinates")
	first.curve.set_point_position(1, first.curve.get_point_position(1) + Vector3(1.25, 0.1, 0))
	terrain.invalidate_road_data_cache()
	_build(terrain)
	_check(terrain.get_source_rebuild_stats().point_groups.support_coordinates_reused > 0
		and terrain.get_source_rebuild_stats().point_groups.support_coordinates_rebuilt > 0,
		"edited complete support mesh mixes retained and rebuilt coordinates")
	_assert_terrain_full_equal(terrain, "edited native boundary support without collars")
	var custom := CustomTerrain.new()
	custom.generate_in_editor = false
	custom.threaded_triangulation_enabled = false
	custom.incremental_generation_enabled = true
	custom.source_paths.assign([NodePath("../Road/First")])
	custom.path_sample_step = 8
	custom.adaptive_path_sampling = false
	custom.near_road_width = 5
	custom.near_road_step = 10
	custom.far_grid_step = 30
	custom.auto_outer_padding = 20
	scene.add_child(custom)
	_build(custom)
	_check(not custom.get_source_rebuild_stats().enabled and custom.get_source_rebuild_stats().entries == 0,
		"custom terrain subclasses bypass source caches")
	scene.free()
	print("TOPOLOGY_SOURCE_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _build(terrain: Node) -> void:
	terrain.regenerate()
	while not terrain._mesh_build_state.is_empty():
		terrain._process_mesh_build()


func _terrain_geometry(terrain: Node) -> Array:
	var generated: MeshInstance3D = terrain.get_node_or_null("GeneratedTopologyTerrain")
	if generated == null or generated.mesh == null:
		return []
	var result: Array = []
	for surface in range(generated.mesh.get_surface_count()):
		result.append(var_to_bytes(generated.mesh.surface_get_arrays(surface)))
	var body: StaticBody3D = terrain.get_node_or_null("GeneratedTopologyTerrainCollision")
	if body != null:
		for child in body.get_children():
			if child is CollisionShape3D:
				result.append(child.shape.get_faces())
	return result


func _assert_terrain_full_equal(terrain: Node, label: String) -> void:
	var actual := _terrain_geometry(terrain)
	terrain.incremental_generation_enabled = false
	_build(terrain)
	_check(actual == _terrain_geometry(terrain), "exact full/source terrain mesh/collision: " + label)
	terrain.incremental_generation_enabled = true
	_build(terrain)
	_build(terrain)
	_check(actual == _terrain_geometry(terrain), "immutable warm terrain replay: " + label)


func _test_worker(terrain: Node, path: Path3D) -> void:
	terrain.threaded_triangulation_enabled = true
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	_check(terrain._triangulation_thread != null, "cold terrain starts a real Delaunay worker")
	_check(bytes_to_var(terrain._triangulation_job.cache_query.input)[1][1] == true,
		"worker cache query snapshots enabled centering")
	terrain.centered_triangulation_enabled = false
	_check(terrain.get_terrain_height_at_world(Vector3.ZERO) == {"hit": false, "pending": true},
		"height query cannot mutate a pending generation's spatial context")
	terrain.clear_source_generation_cache()
	path.curve.set_point_position(1, path.curve.get_point_position(1) + Vector3(0.5, 0.2, 0))
	terrain.invalidate_road_data_cache()
	terrain.regenerate()
	var deadline := Time.get_ticks_msec() + 20000
	while terrain._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not terrain._is_generation_thread_active(), "threaded restart and deferred cache clear finish")
	terrain.threaded_triangulation_enabled = false
	_assert_terrain_full_equal(terrain, "threaded restart and deferred clear")
	# Warm Delaunay enters main-thread, multi-frame assembly immediately.
	terrain.regenerate()
	_check(not terrain._mesh_build_state.is_empty(), "warm terrain has a real multi-frame mesh job")
	terrain._process_mesh_build()
	_check(not terrain._mesh_build_state.is_empty() and terrain._mesh_stream.target != null
		and terrain._mesh_stream._vertices.size() > 0, "restart fixture has already emitted a real buffered prefix")
	_check(terrain._mesh_build_state.cursor == terrain.MESH_BUILD_TRIANGLES_PER_FRAME * 3
		and terrain._triangle_cache.stats.candidates_bulk == terrain.MESH_BUILD_TRIANGLES_PER_FRAME,
		"bulk triangle replay stops at the original per-frame candidate budget")
	terrain.centered_triangulation_enabled = true
	terrain.noise_amplitude += 0.5
	terrain.regenerate()
	while terrain._is_generation_thread_active():
		terrain._process_mesh_build()
	_check(terrain._mesh_stream.target == null and terrain._mesh_stream._vertices.is_empty(),
		"completed restart releases old and new transient vertex streams")
	_assert_terrain_full_equal(terrain, "restart discards partially assembled old geometry")
	var snapshot := _terrain_geometry(terrain)
	var saved_profile: PackedFloat32Array = terrain.left_profile_heights.duplicate()
	terrain.regenerate()
	terrain.left_profile_heights[3] += 100
	while terrain._is_generation_thread_active():
		terrain._process_mesh_build()
	_check(_terrain_geometry(terrain) == snapshot, "in-flight sampled profiles are isolated from mutable Inspector arrays")
	terrain.left_profile_heights = saved_profile
	_build(terrain)
	_check(_terrain_geometry(terrain) == snapshot, "restoring Inspector arrays cannot leave a mutated persistent road snapshot")
	terrain.threaded_triangulation_enabled = true
	terrain.clear_source_generation_cache()
	terrain.regenerate()
	terrain.regenerate()
	terrain._clear_generated_from_button()
	deadline = Time.get_ticks_msec() + 20000
	while terrain._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not terrain._is_generation_thread_active() and terrain.get_node_or_null("GeneratedTopologyTerrain") == null,
		"Clear Generated cancels a previously queued restart and discards worker output")
	terrain.threaded_triangulation_enabled = false
	_build(terrain)
	_assert_terrain_full_equal(terrain, "fresh regeneration after Clear Generated")


func _test_query_support(terrain: Node) -> void:
	var data: Dictionary = terrain._get_cached_road_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	for i in range(30):
		var point := Vector2(rng.randf_range(-100, 100), rng.randf_range(-20, 110))
		var reference: Dictionary = terrain._nearest_road_info_spatial_uncached(point, data.segments)
		_check(terrain._nearest_road_info(point, data.segments) == reference, "nearest query matches original spatial stopping/order")
		var exposed: Dictionary = terrain._nearest_road_info(point, data.segments)
		exposed["road_y"] = 999
		if exposed.has("terrain_profile"):
			exposed.terrain_profile.left_heights = PackedFloat32Array([999, 999])
		_check(terrain._nearest_road_info(point, data.segments) == reference, "returned nearest data cannot mutate retained query results")
	var tri := PackedVector2Array([Vector2(-5, 30), Vector2(5, 30), Vector2(0, 45)])
	var crossing: bool = terrain._triangle_crosses_road_edges(tri[0], tri[1], tri[2], data.polygons)
	_check(crossing == terrain._triangle_crosses_road_edges_uncached(tri[0], tri[1], tri[2], data.polygons),
		"cached edge crossing agrees with original cell candidate test")
	var point := Vector2(250, 200)
	var info: Dictionary = terrain._nearest_road_info(point, data.segments)
	var previous_seed: int = terrain.noise_seed
	terrain.noise_seed += 177
	# Simulate an Inspector seed edit before the next noise configuration. The
	# in-flight function still samples the old FastNoiseLite, not the new export.
	var in_flight: float = terrain._sample_height_from_road_info(point, info)
	terrain._configure_noise()
	var configured: float = terrain._sample_height_from_road_info(point, info)
	_check(configured == terrain._sample_height_from_road_info_uncached(point, info),
		"actual noise resource parameters prevent stale in-flight height replay")
	_check(configured != in_flight, "noise fixture actually distinguishes old and new resources")
	terrain.noise_seed = previous_seed
	terrain._configure_noise()


func _benchmark(terrain: Node, path: Path3D) -> void:
	var original := path.curve.get_point_position(1)
	var results: Dictionary = {}
	for incremental in [false, true]:
		terrain.incremental_generation_enabled = incremental
		path.curve.set_point_position(1, original)
		terrain.clear_source_generation_cache()
		_build(terrain)
		var samples: Array = []
		for i in range(5):
			path.curve.set_point_position(1, original + Vector3(0.2 * (i + 1), 0.1 * (i + 1), 0))
			var started := Time.get_ticks_usec()
			_build(terrain)
			samples.append((Time.get_ticks_usec() - started) / 1000.0)
			if incremental:
				var stats: Dictionary = terrain.get_source_rebuild_stats()
				_check(stats.nearest_reused > 0 and stats.nearest_rebuilt > 0, "timed edit has mixed local query reuse and rebuild")
		samples.sort()
		results["local_ms" if incremental else "full_ms"] = samples[2]
	print("TOPOLOGY_SOURCE_DISTINCT_EDIT_MEDIAN ", results)
	_assert_terrain_full_equal(terrain, "last distinct timed edit")
