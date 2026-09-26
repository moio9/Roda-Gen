extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _rebuild(terrain: Node) -> void:
	var start := Time.get_ticks_msec()
	terrain.regenerate()
	while terrain.is_terrain_generation_pending():
		if Time.get_ticks_msec() - start > 90000:
			push_error("Terrain generation timed out")
			quit(1)
			return
		await process_frame
	print("Canyon rebuild ms=", Time.get_ticks_msec() - start)

func _run() -> void:
	_check_cache()
	root.size = Vector2i(1280, 900)
	var scene := load("res://addons/scenes/examples/canyon_road.tscn").instantiate() as Node3D
	var terrain := scene.get_node("Terrain")
	terrain.generate_on_ready = false
	root.add_child(scene)
	var camera := scene.get_node("Camera") as Camera3D
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	for i in range(5):
		await process_frame
	while scene.get_node("Road").is_road_generation_pending():
		await process_frame
	var material: Material = terrain.terrain_material_override
	var legacy := ShaderMaterial.new()
	legacy.shader = Shader.new()
	legacy.shader.code = """shader_type spatial;
varying vec3 p;
void vertex() { p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 float strata = sin(p.y * 0.9 + sin(p.x * 0.035) * 0.7);
 ALBEDO = mix(vec3(0.40,0.22,0.12), vec3(0.57,0.34,0.20), strata * 0.5 + 0.5) + sin(p.y * 3.6) * 0.012;
 ROUGHNESS = 0.95;
}
"""
	var samples: Array[Vector2] = []
	for x in range(-100, 101, 4):
		for z in range(-110, 151, 4):
			samples.append(Vector2(x, z))
	var base: PackedFloat32Array
	var detailed: PackedFloat32Array
	var road_data: Dictionary
	for enabled in [false, true]:
		terrain.rock_detail_enabled = enabled
		terrain.generate_collision = enabled
		terrain.terrain_material_override = material if enabled or legacy.shader.code.is_empty() else legacy
		await _rebuild(terrain)
		road_data = terrain._get_cached_road_data()
		if enabled:
			var output := terrain.get_node("GeneratedTopologyTerrain") as MeshInstance3D
			var collider := terrain.get_node("GeneratedTopologyTerrainCollision").get_child(0) as CollisionShape3D
			_check(collider.shape.get_faces() == output.mesh.get_faces(), "Collision must use the detailed mesh")
		for p in samples:
			var y: float = terrain._sample_height_at_point(p, road_data.segments)
			if enabled:
				detailed.append(y)
			else:
				base.append(y)
		if "--screenshots" in OS.get_cmdline_user_args():
			for view in ["overview", "wall"]:
				camera.position = Vector3(195, 215, 255)
				camera.look_at(Vector3(0, 15, 20))
				if view == "wall":
					var path := scene.get_node("Road/CanyonRoute") as Path3D
					var d := path.curve.get_baked_length() * 0.42
					var center := path.to_global(path.curve.sample_baked(d))
					var forward := (path.to_global(path.curve.sample_baked(d + 1.0)) - center).normalized()
					camera.global_position = center + Vector3.UP * 8.0
					camera.look_at(center + forward * 25.0 + forward.cross(Vector3.UP) * 26.0 + Vector3.UP * 18.0)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/roda-canyon-%s-%s.png" % ["after" if enabled else "before", view])
	var changed := 0
	var protected := 0
	var max_delta := 0.0
	for i in range(samples.size()):
		var info: Dictionary = terrain._nearest_road_info(samples[i], road_data.segments)
		var delta := absf(base[i] - detailed[i])
		max_delta = maxf(max_delta, delta)
		changed += int(delta > 0.05)
		if info.get("edge_distance", 999.0) <= 5.0:
			protected += 1
			_check(delta < 0.0001, "Rock detail changed the protected road seam")
	_check(changed > 200 and max_delta > 0.5, "Rock detail must visibly change the terrain")
	_check(protected > 0, "Fixture must cover road seams")
	# Isolate contour displacement from the vertical detail contribution.
	terrain.rock_height_amplitude = 0.0
	var lateral_changes := 0
	for i in range(0, samples.size(), 17):
		var y: float = terrain._sample_height_at_point(samples[i], road_data.segments)
		lateral_changes += int(absf(y - base[i]) > 0.05)
	_check(lateral_changes > 10, "Lateral contour detail must work without vertical relief")
	terrain.rock_detail_enabled = false
	for i in range(0, samples.size(), 17):
		_check(absf(terrain._sample_height_at_point(samples[i], road_data.segments) - base[i]) < 0.0001,
			"Disabling detail must restore the original surface")
	terrain.rock_detail_enabled = true
	terrain.rock_height_amplitude = 1.8
	var signature: String = terrain._build_signature()
	terrain.rock_detail_seed += 1
	_check(signature != terrain._build_signature(), "Rock edits must invalidate regeneration")
	terrain.rock_detail_seed -= 1
	await _rebuild(terrain)
	for i in range(0, samples.size(), 17):
		var p := samples[i]
		var query: Dictionary = terrain.get_terrain_height_at_world(terrain.to_global(Vector3(p.x, 0, p.y)))
		_check(query.hit and absf(query.y - detailed[i]) < 0.0001, "Repeat rebuild/height query must retain detail")
	print("CANYON DETAIL ", "OK" if failures == 0 else "FAILED", " changed=", changed, " protected=", protected, " max_delta=", max_delta)
	scene.free()
	quit(0 if failures == 0 else 1)

func _check_cache() -> void:
	var terrain := preload("res://addons/scripts/spline_road/terrain_topology_builder.gd").new()
	terrain._source_cache.configure(true, true)
	var info := {"edge_distance": 17.0, "side": 1, "road_y": 5.0}
	var point := Vector2(31.0, 19.0)
	var edits := {"rock_detail_enabled": true, "rock_lateral_amplitude": 9.0,
		"rock_height_amplitude": 2.0, "rock_detail_scale": 7.0,
		"rock_layer_amplitude": 1.5, "rock_layer_spacing": 2.0, "rock_detail_seed": 54}
	for property in edits:
		terrain.set(property, edits[property])
		terrain._configure_noise()
		var cached: float = terrain._sample_path_height_from_road_info(point, info)
		_check(is_equal_approx(cached, terrain._sample_height_from_road_info_uncached(point, info)),
			"Cached height must match fresh height after editing " + property)
		_check(cached == terrain._sample_path_height_from_road_info(point, info), "Repeated height query must be deterministic")
	_check(terrain._source_cache.stats.heights_reused >= edits.size(), "Fixture must exercise height cache reuse")
	terrain.free()
