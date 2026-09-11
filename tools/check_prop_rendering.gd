extends SceneTree

const PROP_SCRIPT = preload("../addons/scripts/spline_road/spline_prop_array.gd")

var _failed := false
var _reported_errors: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run with a real renderer (no --headless): the dummy renderer does not retain MultiMesh transforms.")
		quit(2)
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	scene.add_child(environment)
	# Keep a complete lighting setup even though the parity material is unshaded.
	# The custom Forward+ build expects a directional light for its SSS pass.
	scene.add_child(DirectionalLight3D.new())
	scene.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.4, 0.0)), Vector3(-20, 5, 30))
	var path := Path3D.new()
	path.name = "Route"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(-100, 0, -100), Vector3.ZERO, Vector3(15, 0, 25))
	path.curve.add_point(Vector3(0, 15, 0), Vector3(-20, 0, -20), Vector3(25, 0, 10))
	path.curve.add_point(Vector3(100, 0, 70), Vector3(-20, 0, -10))
	path.curve.set_point_tilt(1, 0.25)
	scene.add_child(path)
	var props := PROP_SCRIPT.new()
	props.name = "Props"
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(1, 3, 2)
	props.item_material_override = StandardMaterial3D.new()
	props.item_material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	props.item_material_override.albedo_color = Color(1.0, 0.5, 0.1)
	props.mesh_cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.source_paths = [NodePath("../Route")]
	props.placement_mode = 3
	props.spacing = 3.0
	props.multimesh_chunk_size = 40.0
	props.range_source_mode = 0
	props.ranges_mode = 2
	props.distance_ranges = PackedVector2Array([Vector2(60, 90)])
	props.intersection_clear_radius = 8.0
	props.random_seed = 12345
	props.longitudinal_jitter = 0.7
	props.lateral_jitter = 0.4
	props.vertical_jitter = 0.2
	props.yaw_jitter_degrees = 30.0
	props.random_uniform_scale_min = 0.7
	props.random_uniform_scale_max = 1.8
	props.transform = Transform3D(Basis.from_euler(Vector3(0.0, -0.3, 0.1)), Vector3(8, 2, -10))
	props.scale = Vector3(-1.2, -0.8, -1.5)
	scene.add_child(props)
	_check(props.render_mode == 0, "Existing scenes must default to individual nodes")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 210, 170)
	camera.look_at(Vector3(0, 5, 0))
	camera.far = 1000.0
	camera.current = true
	var individual_image := await _capture("/tmp/roda-props-individual.png", "individual")

	var individual := _collect_transforms(props, props)
	_check(individual.size() > 50, "Fixture should exercise many placements")
	var old_output := props.get_node("GeneratedSplineProps")
	var old_signature: String = props._build_signature()
	props.render_mode = 1
	_check(old_signature != props._build_signature(), "Render mode must invalidate generation")
	props.regenerate()
	_check(not is_instance_valid(old_output), "Mode switch must remove old output")
	var batches := _get_batches(props)
	_check(batches.size() > 1 and batches.size() < individual.size(), "Props must be split into spatial batches")
	_check(_same_transforms(individual, _collect_transforms(props, props)), "MultiMesh changed randomized world transforms")
	for batch in batches:
		_check(batch.material_override == props.item_material_override, "Material override was lost")
		_check(batch.cast_shadow == props.mesh_cast_shadows, "Shadow setting was lost")
		_check(batch.multimesh.mesh == props.item_mesh, "Batch must share the source mesh")
		var bounds := batch.multimesh.custom_aabb.grow(0.001)
		var mesh_bounds := props.item_mesh.get_aabb()
		for i in range(batch.multimesh.instance_count):
			var xform := batch.multimesh.get_instance_transform(i)
			for corner in range(8):
				_check(bounds.has_point(xform * mesh_bounds.get_endpoint(corner)), "Culling bounds exclude an instance corner")
	print("PROP_RENDERING_PARITY instances=%d batches=%d" % [individual.size(), batches.size()])
	var multimesh_image := await _capture("/tmp/roda-props-multimesh.png", "multimesh")
	_check_images(individual_image, multimesh_image)

	old_signature = props._build_signature()
	props.multimesh_chunk_size = 500.0
	_check(old_signature != props._build_signature(), "Chunk size must invalidate generation")
	props.regenerate()
	_check(_get_batches(props).size() < batches.size(), "Larger cells should combine batches")
	_check(_same_transforms(individual, _collect_transforms(props, props)), "Chunk size changed placement")

	# Another array sharing the parent must survive clear/regenerate operations.
	var other := PROP_SCRIPT.new()
	other.name = "OtherProps"
	other.item_mesh = props.item_mesh
	other.source_paths = [NodePath("../Route")]
	other.use_parent_as_generated_root = true
	other.render_mode = 1
	other.spacing = 20.0
	scene.add_child(other)
	var other_transforms := _collect_transforms(scene, other)
	props.use_parent_as_generated_root = true
	_check(not props.has_node("GeneratedSplineProps"), "Old child output survived switching parent")
	var parent_transforms := _collect_transforms(scene, props)
	props._clear_generated_from_button()
	_check(_collect_transforms(scene, props).is_empty(), "Clear left generated batches behind")
	_check(_same_transforms(other_transforms, _collect_transforms(scene, other)), "Clear removed another array's output")
	props.render_mode = 0
	props.regenerate()
	_check(_same_transforms(parent_transforms, _collect_transforms(scene, props)), "Parent output differs between modes")
	props.use_parent_as_generated_root = false
	_check(_same_transforms(individual, _collect_transforms(props, props)), "Switching back changed placement")

	# Item Scene takes priority even when Item Mesh and MultiMesh are selected.
	var source := Node3D.new()
	var body := StaticBody3D.new()
	source.add_child(body)
	body.owner = source
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	collision.owner = source
	var packed := PackedScene.new()
	_check(packed.pack(source) == OK, "Could not pack collision fixture")
	source.free()
	props.item_scene = packed
	props.render_mode = 1
	props.regenerate()
	_check(not props._get_configuration_warnings().is_empty(), "Scene fallback must be explained in the editor")
	_check(_get_batches(props).is_empty(), "Item Scene was incorrectly converted to MultiMesh")
	var generated := props.get_node("GeneratedSplineProps")
	_check(generated.get_child_count() == individual.size(), "Scene fallback changed instance count")
	for instance in generated.get_children():
		_check(instance.get_child(0) is StaticBody3D, "Scene collision body was lost")
		_check(instance.get_child(0).get_child(0) is CollisionShape3D, "Scene collision shape was lost")

	# Empty source paths must clear a previously generated MultiMesh.
	props.item_scene = null
	props.regenerate()
	path.curve.clear_points()
	props.regenerate()
	_check(not props.has_node("GeneratedSplineProps"), "Empty path left stale batches")
	scene.free()
	camera.free()
	if not _failed:
		print("PROP_RENDERING_OK")
	quit(1 if _failed else 0)


func _capture(output_path: String, mode: String) -> Image:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Renderer returned no image")
	if image != null and not image.is_empty():
		_check(image.save_png(output_path) == OK, "Could not save rendering comparison")
	print("PROP_RENDERING_DRAWS mode=%s calls=%d" % [mode, root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	return image


func _check_images(expected: Image, actual: Image) -> void:
	if expected == null or actual == null:
		return
	_check(expected.get_size() == actual.get_size(), "Rendered image sizes differ")
	var changed_pixels := 0
	var prop_pixels := 0
	for y in range(expected.get_height()):
		for x in range(expected.get_width()):
			var a := expected.get_pixel(x, y)
			var b := actual.get_pixel(x, y)
			if a.r > a.b + 0.1:
				prop_pixels += 1
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.02:
				changed_pixels += 1
	_check(prop_pixels > 100, "Camera did not render the prop fixture")
	_check(changed_pixels <= maxi(5, int(prop_pixels * 0.01)), "MultiMesh visibly differs from individual rendering")
	print("PROP_RENDERING_IMAGE prop_pixels=%d changed_pixels=%d" % [prop_pixels, changed_pixels])


func _get_batches(node: Node) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
		out.append_array(_get_batches(child))
	return out


func _collect_transforms(node: Node, props: Node) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for child in node.get_children():
		if child.get_meta("spline_prop_array_owner_path", "") == str(props.get_path()):
			if child is MultiMeshInstance3D:
				for i in range(child.multimesh.instance_count):
					out.append(child.global_transform * child.multimesh.get_instance_transform(i))
			elif child is Node3D:
				out.append(child.global_transform)
		out.append_array(_collect_transforms(child, props))
	return out


func _same_transforms(expected: Array[Transform3D], actual: Array[Transform3D]) -> bool:
	if expected.size() != actual.size():
		return false
	var remaining := actual.duplicate()
	for transform in expected:
		var found := -1
		for i in range(remaining.size()):
			var candidate: Transform3D = remaining[i]
			if (
				transform.origin.distance_to(candidate.origin) < 0.001
				and transform.basis.x.distance_to(candidate.basis.x) < 0.001
				and transform.basis.y.distance_to(candidate.basis.y) < 0.001
				and transform.basis.z.distance_to(candidate.basis.z) < 0.001
			):
				found = i
				break
		if found < 0:
			return false
		remaining.remove_at(found)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		if not _reported_errors.has(message):
			_reported_errors[message] = true
			push_error(message)
