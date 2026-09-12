extends SceneTree
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--user-scene" in OS.get_cmdline_user_args():
		await _user_scene()
		quit(failures)
		return
	for angles in [[0, 90, 180, 270], [0, 90, 180], [0, 75, 195, 280], [0, 180], [0, 70], [0, 90]]:
		var scene := Node3D.new()
		var road := ROAD.new()
		road.name = "Road"
		road.threaded_generation_enabled = false
		road.invert_faces = true
		road.allow_endpoint_to_midpath = false
		var midpath: bool = angles.size() == 2 and angles[1] == 90
		road.allow_endpoint_to_midpath = midpath
		road.junction_geometry_mode = 1
		road.sample_step = 0.75
		road.debug_generation_logs = false
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.09, 0.1, 0.12)
		road.road_material_override = material
		var curb := StandardMaterial3D.new()
		curb.albedo_color = Color(0.65, 0.62, 0.55)
		road.sidewalk_material_override = curb
		scene.add_child(road)
		for i in range(angles.size()):
			var path := PROFILE.new()
			path.name = "Arm%d" % i
			path.curve = Curve3D.new()
			var dir := Vector3(cos(deg_to_rad(angles[i])), 0, sin(deg_to_rad(angles[i])))
			path.curve.add_point(-dir * 65 if midpath and i == 0 else Vector3.ZERO)
			path.curve.add_point(dir * 65)
			path.sidewalk_left_width = 1.0 + i * 0.4
			path.sidewalk_right_width = 1.5 + i * 0.3
			path.shoulder_left_width = 0.4
			path.shoulder_right_width = 0.4
			path.sidewalk_height = 0.12 + i * 0.03
			path.show_width_preview = false
			road.add_child(path)
		root.add_child(scene)
		await process_frame
		var reports: Array = road._junction_builder.contour.reports
		print("CONTOUR FIXTURE ", angles, " ", reports)
		if reports.is_empty() or not reports[0].ok:
			failures += 1
		_check_mesh(road)
		var original := _mesh_digest(road)
		road.incremental_generation_enabled = true
		road.regenerate()
		if original != _mesh_digest(road):
			push_error("Contour cached/full output mismatch")
			failures += 1
		var profile := Curve.new()
		profile.add_point(Vector2(0, 0.35))
		profile.add_point(Vector2(1, 0.65))
		var signature: String = road._build_signature()
		road.junction_corner_profile = profile
		if signature == road._build_signature():
			failures += 1
		road.regenerate()
		if original == _mesh_digest(road):
			push_error("Profile failed to change the connector")
			failures += 1
		_check_mesh(road)
		road.junction_corner_profile = null
		road.regenerate()
		if "--screenshots" in OS.get_cmdline_user_args():
			await _capture(scene, road, "fixture_%d" % angles.size())
		scene.free()
		await process_frame
	print("CONTOUR CHECK ", "OK" if failures == 0 else "FAILED")
	quit(failures)

func _mesh_digest(road: Node3D) -> int:
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var arrays: Array = []
	for i in range(mesh.get_surface_count()):
		arrays.append(mesh.surface_get_arrays(i))
	return hash(arrays)

func _check_mesh(road: Node3D) -> void:
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for point in points:
			if not point.is_finite():
				push_error("Non-finite connector vertex")
				failures += 1
		for index in indices:
			if index < 0 or index >= points.size():
				push_error("Invalid connector index")
				failures += 1
			if road._junction_builder.contour.removed_vertices.has(index):
				push_error("Retired junction row is still referenced")
				failures += 1
	# Every retired original row must be absent from surviving triangles.
	var retired: Dictionary = road._junction_builder.contour.removed_vertices
	if retired.is_empty():
		push_error("No old junction rows removed")
		failures += 1

func _user_scene() -> void:
	# Temporary test artifact: same authored scene, paths remapped to this project.
	# Avoid launching the consuming game's autoloads/extensions or changing its files.
	var text := FileAccess.get_file_as_string("res://addons/scenes/spline_road/spline_intersections_demo.tscn")
	text = text.replace("res://addons/roda-gen/", "res://addons/")
	var regex := RegEx.new()
	regex.compile(' uid="[^"]*"')
	text = regex.sub(text, "", true)
	var file := FileAccess.open("/tmp/roda-contour-user-fixture.tscn", FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var packed := load("/tmp/roda-contour-user-fixture.tscn") as PackedScene
	var scene := packed.instantiate()
	var road := scene.get_node("Intersections")
	road.junction_geometry_mode = 1
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	root.add_child(scene)
	await process_frame
	print("USER CONTOUR ", road._junction_builder.contour.reports)
	for report in road._junction_builder.contour.reports:
		if not report.ok:
			failures += 1
	if "--screenshots" in OS.get_cmdline_user_args():
		if "--road-only" in OS.get_cmdline_user_args():
			var output := road.get_node("GeneratedSplineRoadWelded") as MeshInstance3D
			_hide_other_geometry(scene, output)
			var diagnostic := ArrayMesh.new()
			for surface in range(output.mesh.get_surface_count()):
				var mat := output.mesh.surface_get_material(surface)
				if mat == road.terrain_material_override or mat == road.outer_wall_material_override:
					continue
				diagnostic.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output.mesh.surface_get_arrays(surface))
				var solid := StandardMaterial3D.new()
				solid.albedo_color = Color(0.07, 0.08, 0.1) if mat == road.road_material_override else (Color(0.75, 0.73, 0.66) if mat == road.sidewalk_material_override else Color(0.4, 0.4, 0.4))
				diagnostic.surface_set_material(diagnostic.get_surface_count() - 1, solid)
			output.mesh = diagnostic
		await _capture(scene, road, "user")
		var camera := scene.get_node("ContourCamera") as Camera3D
		var index := 0
		for report in road._junction_builder.contour.reports:
			if not report.ok:
				continue
			var center: Vector3 = road.to_global(report.center)
			camera.position = center + Vector3(12, 48, 32)
			camera.look_at(center)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/roda-contour-user-detail%d.png" % index)
			index += 1
	scene.free()
	await process_frame

func _hide_other_geometry(node: Node, keep: Node) -> void:
	if node is GeometryInstance3D and node != keep:
		node.visible = false
	for child in node.get_children():
		_hide_other_geometry(child, keep)

func _capture(scene: Node3D, road: Node3D, label: String) -> void:
	root.size = Vector2i(1100, 800)
	var camera := Camera3D.new()
	camera.name = "ContourCamera"
	scene.add_child(camera)
	var output := road.get_node("GeneratedSplineRoadWelded") as MeshInstance3D
	var bounds := output.get_aabb()
	var center := output.to_global(bounds.get_center())
	var extent := maxf(bounds.size.x, bounds.size.z)
	camera.position = center + Vector3(extent * 0.25, extent * 0.85, extent * 0.65)
	camera.look_at(center)
	camera.current = true
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0.15, 0.2, 0.25)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color.WHITE
	resource.ambient_light_energy = 0.8
	environment.environment = resource
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, -0.3, 0)
	scene.add_child(light)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/roda-contour-%s.png" % label)
