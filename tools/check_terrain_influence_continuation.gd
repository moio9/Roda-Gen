extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func rebuild(terrain: Node) -> void:
	terrain.regenerate()
	while not terrain._mesh_build_state.is_empty():
		terrain._process_mesh_build()

func height(terrain: Node, point: Vector3) -> float:
	return float(terrain.get_terrain_height_at_world(point).get("y", INF))

func _run() -> void:
	var scene: Node = load("res://addons/scenes/examples/terrain_spline_continuation.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var terrain: Node = scene.get_node("Terrain")
	var path: Path3D = scene.get_node("Terrain/BasinBoundary")
	rebuild(terrain)
	check(path.influence_use_profile_graph and path.influence_profile_graph != null, "demo has an editable cross-profile curve")
	check(absf(height(terrain, Vector3(80, 0, 0))) < 0.1, "profile raises crest to zero while floor stays deep")
	check(is_equal_approx(height(terrain, Vector3.ZERO), -35), "closed loop center is a floor, not an unaffected island")
	check(is_equal_approx(height(terrain, Vector3(140, 0, 0)), 0), "outside side keeps local behavior")
	for point in [Vector3(-140, 0, -140), Vector3(140, 0, -140), Vector3(-140, 0, 140), Vector3(140, 0, 140)]:
		check(is_equal_approx(height(terrain, point), 0), "exterior corner is not accidentally filled: " + str(point))
	var body: StaticBody3D = terrain.get_node("GeneratedTopologyTerrainCollision")
	var hit_floor := false
	for shape: Node in body.get_children():
		var faces: PackedVector3Array = shape.shape.get_faces()
		for i in range(0, faces.size(), 3):
			var hit = Geometry3D.segment_intersects_triangle(Vector3(1, 10, 2), Vector3(1, -80, 2), faces[i], faces[i+1], faces[i+2])
			if hit != null and absf(hit.y + 35) < 0.01:
				hit_floor = true
	check(hit_floor, "real collision triangles fill the center of the loop")
	if "--screenshot" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrain-spline-continuation.png")
	terrain.incremental_generation_enabled = true
	path.terrain_right_continuation = 0
	rebuild(terrain)
	check(is_equal_approx(height(terrain, Vector3.ZERO), 0), "disabling continuation restores local-only center")
	path.terrain_left_continuation = 1
	rebuild(terrain)
	check(is_equal_approx(height(terrain, Vector3(140, 0, 0)), -35), "left side extends outward beyond influence width")
	check(is_equal_approx(height(terrain, Vector3.ZERO), 0), "left continuation does not fill inward side")
	path.terrain_right_continuation = 1
	rebuild(terrain)
	check(is_equal_approx(height(terrain, Vector3.ZERO), -35), "warm regeneration observes mode edits")
	check(is_equal_approx(terrain._terrain_influences.sample_height(Vector2.ZERO, 7, 3), 7), "nearer road owns its region")
	var other: Path3D = path.get_script().new()
	other.name = "OtherSource"
	other.curve = Curve3D.new()
	other.curve.add_point(Vector3(-20, -12, 0))
	other.curve.add_point(Vector3(20, -12, 0))
	other.influence_profile_height = 0
	terrain.add_child(other)
	rebuild(terrain)
	check(is_equal_approx(height(terrain, Vector3.ZERO), -12), "nearer terrain spline takes over")
	check(is_equal_approx(height(terrain, Vector3(0, 0, 20)), 0), "local-only nearer spline blocks distant continuation")
	other.free()
	path.terrain_left_continuation = 0
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(0, -35, -100))
	path.curve.add_point(Vector3(0, -35, 100))
	rebuild(terrain)
	check(is_equal_approx(height(terrain, Vector3(140, 0, 0)), -35), "open spline extends right to bounds")
	check(is_equal_approx(height(terrain, Vector3(-140, 0, 0)), 0), "open spline leaves opposite side unchanged")
	path.curve.set_point_position(0, Vector3(0, -35, 100))
	path.curve.set_point_position(1, Vector3(0, -35, -100))
	rebuild(terrain)
	check(is_equal_approx(height(terrain, Vector3(-140, 0, 0)), -35), "reversing direction reverses continuation side")
	var signature: String = terrain._build_signature()
	path.terrain_right_continuation = 0
	check(signature != terrain._build_signature(), "mode edit invalidates editor regeneration signature")
	rebuild(terrain)
	var reference: float = terrain._terrain_influences.sampler.sample_prepared_height(Vector3(10, 0, 0), terrain._terrain_influences.strips)
	check(is_equal_approx(height(terrain, Vector3(10, 0, 0)), reference), "disabled continuation preserves original sampler")
	print("TERRAIN INFLUENCE CONTINUATION checks=%d failures=%d" % [checks, failures])
	scene.free()
	quit(1 if failures else 0)
