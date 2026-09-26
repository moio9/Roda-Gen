extends SceneTree
const TERRAIN = preload("../scripts/spline_road/terrain_topology_builder.gd")
const INFLUENCE = preload("../scripts/spline_road/terrain_influence_path.gd")
var failures := 0
func _initialize():
	_run.call_deferred()
func _check(ok: bool, message: String):
	if not ok:
		push_error(message)
		failures += 1
func _generate(t):
	t.regenerate()
	while t.is_terrain_generation_pending():
		await process_frame
func _run():
	var scene := Node3D.new()
	var path := INFLUENCE.new()
	path.name = "Influence"
	path.position = Vector3(10, 2, -5)
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(-12, 0, 0))
	path.curve.add_point(Vector3(12, 0, 0))
	path.influence_width = 8
	path.influence_blend = 4
	path.influence_profile_height = 8
	path.influence_use_profile_graph = true
	path.influence_profile_graph = Curve.new()
	path.influence_profile_graph.add_point(Vector2(0, 1))
	path.influence_profile_graph.add_point(Vector2(1, 1))
	path.generate_influence_surface = false
	scene.add_child(path)
	var terrain := TERRAIN.new()
	terrain.position = Vector3(3, -1, 1)
	terrain.name = "Terrain"
	terrain.source_paths = [NodePath("../Influence")]
	terrain.noise_enabled = false
	terrain.bounds_mode = 1
	terrain.manual_size_xz = Vector2(60, 60)
	terrain.far_grid_step = 4
	terrain.near_road_step = 2
	terrain.generate_road_edge_collars = false
	terrain.auto_lane_profile_edge_collars = false
	scene.add_child(terrain)
	root.add_child(scene)
	terrain._terrain_influences = null # Simulate a failed dependency during live reload.
	await _generate(terrain)
	_check(terrain._get_cached_road_data().segments.is_empty(), "Influence paths are not road masks")
	_check(terrain._terrain_influences.strips.size() == 1, "Influence is collected with Generate Surface disabled")
	var center := Vector3(10, 0, -5)
	var height: float = terrain.get_terrain_height_at_world(center).y
	_check(absf(height - 10) < 0.001, "Apply graph height in transformed terrain coordinates")
	var found := false
	var mesh = terrain.get_node("GeneratedTopologyTerrain").mesh
	for s in range(mesh.get_surface_count()):
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var world: Vector3 = terrain.to_global(v)
			if Vector2(world.x-center.x, world.z-center.z).length() < 0.001:
				found = true
				_check(absf(world.y - 10) < 0.001, "Generated mesh follows the influence, not only height queries")
	_check(found, "Add samples inside the influence rather than cutting a hole")
	var signature = terrain._build_signature()
	path.influence_strength = 0
	_check(signature != terrain._build_signature(), "Strength edits invalidate generation")
	await _generate(terrain)
	_check(absf(terrain.get_terrain_height_at_world(center).y + 1) < 0.001, "Zero strength restores baseline terrain")
	path.influence_strength = 1
	path.influence_profile_graph.set_point_value(0, 0.5)
	path.influence_profile_graph.set_point_value(1, 0.5)
	terrain.output_mode = 1
	await _generate(terrain)
	_check(absf(terrain.get_terrain_height_at_world(center).y - 6) < 0.001, "Graph edits affect chunked terrain too")
	# Height Modifiers must accept the same influence paths as Source Paths.
	terrain.source_paths = []
	terrain.height_modifiers = [NodePath("../Influence")]
	_check(terrain._has_terrain_sources(), "Height-modifier-only scenes can generate on editor startup")
	await _generate(terrain)
	_check(terrain._terrain_influences.strips.size() == 1, "Collect influences from Height Modifiers")
	_check(absf(terrain.get_terrain_height_at_world(center).y - 6) < 0.001, "Height Modifiers applies the same profile")
	signature = terrain._build_signature()
	path.influence_profile_height = 12
	_check(signature != terrain._build_signature(), "Height modifier influence edits invalidate regeneration")
	terrain.source_paths = [NodePath("../Influence")]
	await _generate(terrain)
	_check(terrain._terrain_influences.strips.size() == 1, "Deduplicate influences referenced in both lists")
	_check(absf(terrain.get_terrain_height_at_world(center).y - 8) < 0.001, "Apply modified profile once")
	print("TOPOLOGY INFLUENCES ", "OK" if failures == 0 else "FAILED", " failures=", failures, " initial_world_y=", height)
	scene.free()
	quit(failures)
