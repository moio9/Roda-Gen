extends SceneTree

const OUT_PATH := "res://road_capture.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := "res://addons/scenes/spline_road/spline_intersections_demo.tscn"
	var node_name := "Intersections"
	var use_existing_mesh := false
	var terrain_only := false
	if args.size() >= 1:
		scene_path = str(args[0])
	if args.size() >= 2:
		node_name = str(args[1])
	if args.size() >= 3:
		use_existing_mesh = str(args[2]).to_lower() in ["existing", "skip_regenerate"]
	if args.size() >= 4:
		terrain_only = str(args[3]).to_lower() == "terrain_only"

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Could not load scene: " + scene_path)
		quit(1)
		return

	var scene := packed.instantiate()
	var generator := _find_node_by_name(scene, node_name)
	if generator != null:
		if use_existing_mesh and _has_property(generator, "generate_in_editor"):
			generator.set("generate_in_editor", false)
		if _has_property(generator, "threaded_generation_enabled"):
			generator.set("threaded_generation_enabled", false)
		if _has_property(generator, "debug_generation_logs"):
			generator.set("debug_generation_logs", false)
	root.add_child(scene)
	await process_frame

	if generator != null and not use_existing_mesh:
		if generator.has_method("regenerate"):
			generator.call("regenerate")

	var wait_frames := 0
	while generator != null and generator.has_method("_is_generation_thread_active") and generator.call("_is_generation_thread_active"):
		await process_frame
		wait_frames += 1
		if wait_frames >= 1800:
			push_error("Timed out waiting for generated terrain.")
			quit(1)
			return
	await process_frame

	var mesh_node: MeshInstance3D = null
	if generator != null:
		mesh_node = _find_node_by_name(generator, "GeneratedTopologyTerrain") as MeshInstance3D
		if mesh_node == null:
			mesh_node = _find_node_by_name(generator, "GeneratedSplineRoadWelded") as MeshInstance3D
	if mesh_node == null:
		mesh_node = _find_node_by_name(scene, "GeneratedTopologyTerrain") as MeshInstance3D
	if mesh_node == null:
		mesh_node = _find_node_by_name(scene, "GeneratedSplineRoadWelded") as MeshInstance3D
	if mesh_node == null:
		push_error("No generated mesh found.")
		quit(1)
		return

	var img := _rasterize_scene_topdown(scene, Vector2i(1920, 1440), terrain_only)
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("Failed to save screenshot: " + str(err))
		quit(1)
		return
	print(OUT_PATH)
	quit()


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _global_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	var gt := mi.global_transform
	var out := AABB(gt * local.position, Vector3.ZERO)
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var p := local.position + Vector3(local.size.x * x, local.size.y * y, local.size.z * z)
				out = out.expand(gt * p)
	return out


func _rasterize_scene_topdown(scene: Node, image_size: Vector2i, terrain_only: bool = false) -> Image:
	var img := Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.035, 0.04, 0.045, 1.0))
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_nodes(scene, meshes)
	var terrain_meshes: Array[MeshInstance3D] = []
	var road_meshes: Array[MeshInstance3D] = []
	for mi in meshes:
		if mi.mesh == null:
			continue
		if mi.name == "GeneratedTopologyTerrain":
			terrain_meshes.push_back(mi)
		else:
			road_meshes.push_back(mi)
	var ordered: Array[MeshInstance3D] = []
	ordered.append_array(terrain_meshes)
	if terrain_only:
		for mi in road_meshes:
			if mi.name == "GeneratedSplineRoadWelded":
				ordered.push_back(mi)
	else:
		ordered.append_array(road_meshes)
	# Frame the image from the road, not from the very large terrain bounds.
	# The terrain is still rendered, but road-edge gaps become inspectable.
	var bounds_meshes := road_meshes if not road_meshes.is_empty() else ordered
	var points := PackedVector3Array()
	for mi in bounds_meshes:
		for si in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for p in verts:
				points.push_back(mi.global_transform * p)
	if points.is_empty():
		return img
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var pad := maxf(max_x - min_x, max_z - min_z) * 0.05
	min_x -= pad
	max_x += pad
	min_z -= pad
	max_z += pad
	var scale := minf(float(image_size.x - 1) / maxf(0.001, max_x - min_x), float(image_size.y - 1) / maxf(0.001, max_z - min_z))
	var offset_x := (float(image_size.x) - (max_x - min_x) * scale) * 0.5
	var offset_y := (float(image_size.y) - (max_z - min_z) * scale) * 0.5
	for mi in ordered:
		for si in range(mi.mesh.get_surface_count()):
			if terrain_only and mi.name == "GeneratedSplineRoadWelded" and si != 3:
				continue
			var arrays := mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var world_verts := PackedVector3Array()
			world_verts.resize(verts.size())
			for vi in range(verts.size()):
				world_verts[vi] = mi.global_transform * verts[vi]
			_draw_surface_topdown(img, world_verts, indices, si, mi.name, min_x, min_z, scale, offset_x, offset_y, image_size)
	return img


func _collect_mesh_nodes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.push_back(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_nodes(child, out)


func _rasterize_mesh_topdown(mi: MeshInstance3D, image_size: Vector2i) -> Image:
	var mesh := mi.mesh
	var img := Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.035, 0.04, 0.045, 1.0))
	if mesh == null:
		return img

	var points := PackedVector3Array()
	var surface_vertices: Array = []
	var surface_indices: Array = []
	for si in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(si)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		if verts.is_empty():
			continue
		var world_verts := PackedVector3Array()
		world_verts.resize(verts.size())
		for vi in range(verts.size()):
			var wp := mi.global_transform * verts[vi]
			world_verts[vi] = wp
			points.push_back(wp)
		surface_vertices.push_back(world_verts)
		surface_indices.push_back(idx)

	if points.is_empty():
		return img

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var pad := maxf(max_x - min_x, max_z - min_z) * 0.05
	min_x -= pad
	max_x += pad
	min_z -= pad
	max_z += pad
	var scale := minf(float(image_size.x - 1) / maxf(0.001, max_x - min_x), float(image_size.y - 1) / maxf(0.001, max_z - min_z))
	var offset_x := (float(image_size.x) - (max_x - min_x) * scale) * 0.5
	var offset_y := (float(image_size.y) - (max_z - min_z) * scale) * 0.5

	# Draw terrain before road surfaces so the road remains readable.
	var order := [3, 4, 0, 1, 2]
	for si_raw in order:
		var si := int(si_raw)
		if si < 0 or si >= surface_vertices.size():
			continue
		_draw_surface_topdown(img, surface_vertices[si], surface_indices[si], si, mi.name, min_x, min_z, scale, offset_x, offset_y, image_size)
	for si in range(surface_vertices.size()):
		if order.has(si):
			continue
		_draw_surface_topdown(img, surface_vertices[si], surface_indices[si], si, mi.name, min_x, min_z, scale, offset_x, offset_y, image_size)
	return img


func _draw_surface_topdown(
	img: Image,
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	surface_index: int,
	mesh_name: String,
	min_x: float,
	min_z: float,
	scale: float,
	offset_x: float,
	offset_y: float,
	image_size: Vector2i
) -> void:
	var color := _surface_color(surface_index, mesh_name)
	var tri_count := indices.size() - (indices.size() % 3)
	if tri_count <= 0:
		tri_count = verts.size() - (verts.size() % 3)
	for i in range(0, tri_count, 3):
		var ia := int(indices[i]) if not indices.is_empty() else i
		var ib := int(indices[i + 1]) if not indices.is_empty() else i + 1
		var ic := int(indices[i + 2]) if not indices.is_empty() else i + 2
		if ia < 0 or ib < 0 or ic < 0 or ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
			continue
		var a := _project_topdown(verts[ia], min_x, min_z, scale, offset_x, offset_y, image_size)
		var b := _project_topdown(verts[ib], min_x, min_z, scale, offset_x, offset_y, image_size)
		var c := _project_topdown(verts[ic], min_x, min_z, scale, offset_x, offset_y, image_size)
		_fill_triangle_2d(img, a, b, c, color)


func _surface_color(surface_index: int, mesh_name: String) -> Color:
	if mesh_name == "GeneratedTopologyTerrain":
		return Color(0.18, 0.48, 0.20, 1.0)
	match surface_index:
		0:
			return Color(0.08, 0.085, 0.09, 1.0)
		1:
			return Color(0.46, 0.39, 0.30, 1.0)
		2:
			return Color(0.62, 0.62, 0.58, 1.0)
		3:
			return Color(0.18, 0.48, 0.20, 1.0)
		4:
			return Color(0.32, 0.18, 0.14, 1.0)
	return Color(0.8, 0.2, 0.8, 1.0)


func _project_topdown(p: Vector3, min_x: float, min_z: float, scale: float, offset_x: float, offset_y: float, image_size: Vector2i) -> Vector2:
	var x := offset_x + (p.x - min_x) * scale
	var y := float(image_size.y - 1) - (offset_y + (p.z - min_z) * scale)
	return Vector2(x, y)


func _fill_triangle_2d(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var min_px := clampi(int(floor(minf(a.x, minf(b.x, c.x)))), 0, img.get_width() - 1)
	var max_px := clampi(int(ceil(maxf(a.x, maxf(b.x, c.x)))), 0, img.get_width() - 1)
	var min_py := clampi(int(floor(minf(a.y, minf(b.y, c.y)))), 0, img.get_height() - 1)
	var max_py := clampi(int(ceil(maxf(a.y, maxf(b.y, c.y)))), 0, img.get_height() - 1)
	var area := _edge2(a, b, c)
	if absf(area) <= 0.00001:
		return
	for y in range(min_py, max_py + 1):
		for x in range(min_px, max_px + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var w0 := _edge2(b, c, p)
			var w1 := _edge2(c, a, p)
			var w2 := _edge2(a, b, p)
			if area < 0.0:
				w0 = -w0
				w1 = -w1
				w2 = -w2
			if w0 >= -0.001 and w1 >= -0.001 and w2 >= -0.001:
				img.set_pixel(x, y, color)


func _edge2(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)


func _has_property(node: Object, property_name: String) -> bool:
	for info in node.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false
