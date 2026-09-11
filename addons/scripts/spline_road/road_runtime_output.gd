@tool
extends RefCounted
## Spatial output for the road generator, not a general-purpose mesh splitter.
## Preserves its vertex/normal/UV streams and assigns whole triangles by centroid.

const CHUNKS_NODE_NAME := "GeneratedRoadChunks"
const COLLISION_META := "roda_generated_collision"
var _fingerprints: Dictionary = {}
var last_stats: Dictionary = {}
var incremental_partition_enabled := true
var _partition_active := false
var _partition_caches: Array = []
var _partition_stats: Array = []


func clear(road: Node) -> void:
	var container := road.get_node_or_null(CHUNKS_NODE_NAME)
	if container != null:
		road.remove_child(container)
		container.queue_free()
	_fingerprints.clear()
	clear_partition_cache()
	last_stats = {}


func assign_chunks(road: Node3D, mesh: ArrayMesh, cell_size: float, template: MeshInstance3D) -> void:
	var started := Time.get_ticks_usec()
	_partition_active = bool(road.get("incremental_generation_enabled")) and incremental_partition_enabled
	if not _partition_active:
		clear_partition_cache()
	var cells := _partition(mesh, maxf(1.0, cell_size))
	var partition_finished := Time.get_ticks_usec()
	var container := road.get_node_or_null(CHUNKS_NODE_NAME) as Node3D
	if container == null:
		container = Node3D.new()
		container.name = CHUNKS_NODE_NAME
		road.add_child(container)
		_set_editor_owner(container, road)
	var retained: Dictionary = {}
	var rebuilt := 0
	var reused := 0
	for cell: Vector3i in cells:
		var chunk_name := "Chunk_%d_%d_%d" % [cell.x, cell.y, cell.z]
		var surfaces: Array = cells[cell]
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes(surfaces))
		var fingerprint := digest.finish()
		var instance := container.get_node_or_null(NodePath(chunk_name)) as MeshInstance3D
		if instance == null:
			instance = MeshInstance3D.new()
			instance.name = chunk_name
			container.add_child(instance)
			_set_editor_owner(instance, road)
		var changed: bool = instance.mesh == null or _fingerprints.get(chunk_name) != fingerprint
		if changed:
			var chunk_mesh := ArrayMesh.new()
			for arrays: Array in surfaces:
				if not arrays.is_empty():
					chunk_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			instance.mesh = chunk_mesh
			rebuilt += 1
		else:
			reused += 1
		# Materials may be edited in place; geometry and physics do not need rebuilding.
		var surface_index := 0
		for source_surface in range(surfaces.size()):
			if not surfaces[source_surface].is_empty():
				instance.mesh.surface_set_material(surface_index, _source_material(mesh, source_surface))
				surface_index += 1
		_copy_visual_settings(template, instance)
		instance.transform = template.transform
		var collision_template := template.get_node_or_null("StaticBody3D") as StaticBody3D
		if collision_template != null and collision_template.has_meta(COLLISION_META):
			collision_template = null
		sync_collision(instance, road, changed, collision_template)
		_fingerprints[chunk_name] = fingerprint
		retained[chunk_name] = true
	for child in container.get_children():
		if not retained.has(str(child.name)):
			_fingerprints.erase(str(child.name))
			container.remove_child(child)
			child.queue_free()
	last_stats = {
		"chunks": cells.size(), "rebuilt": rebuilt, "reused": reused,
		"source_surface_uploads": mesh.get_surface_count(),
		"cpu_surfaces": _surface_count(mesh),
		"partition_surfaces": _partition_stats.duplicate(true),
		"partition_ms": float(partition_finished - started) / 1000.0,
		"publish_ms": float(Time.get_ticks_usec() - partition_finished) / 1000.0,
		"output_ms": float(Time.get_ticks_usec() - started) / 1000.0,
	}


func _partition(mesh: ArrayMesh, cell_size: float) -> Dictionary:
	_partition_stats.clear()
	var count := _surface_count(mesh)
	if not _partition_active or count > 5:
		clear_partition_cache()
		return _partition_native(mesh, cell_size)
	while _partition_caches.size() < count:
		_partition_caches.append(preload("./road_partition_cache.gd").new())
	_partition_caches.resize(count)
	var cells: Dictionary = {}
	var cpu: Array = mesh.get_meta("_roda_output_arrays", [])
	for surface in range(count):
		var source: Array = cpu[surface] if cpu.size() == count else mesh.surface_get_arrays(surface)
		var cache: RefCounted = _partition_caches[surface]
		var result: Dictionary = cache.partition(source, cell_size)
		_partition_stats.append(cache.stats.duplicate())
		if result.is_empty():
			# No partial cached output is published on fallback. Do not report
			# earlier surfaces as reused when the native pass rebuilds them all.
			_partition_caches.clear()
			for entry: Dictionary in _partition_stats:
				entry.cells_reused = 0
				entry.cells_rebuilt = 0
				entry.payload_bound = 0
				entry.native_fallback = true
			return _partition_native(mesh, cell_size)
		for cell: Vector3i in result.cells:
			if not cells.has(cell):
				var surfaces: Array = []
				surfaces.resize(count)
				for index in range(count):
					surfaces[index] = []
				cells[cell] = surfaces
			cells[cell][surface] = result.cells[cell]
	return cells


func clear_partition_cache() -> void:
	_partition_caches.clear()
	_partition_stats.clear()


func _partition_native(mesh: ArrayMesh, cell_size: float) -> Dictionary:
	var cells: Dictionary = {}
	var cpu_surfaces: Array = mesh.get_meta("_roda_output_arrays", [])
	var surface_count := _surface_count(mesh)
	for surface in range(surface_count):
		var source: Array = cpu_surfaces[surface] if cpu_surfaces.size() == surface_count else mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
		var triangle_count := indices.size() / 3
		var surface_cells: Dictionary = {}
		for triangle in range(triangle_count):
			var start := triangle * 3
			var center := (vertices[indices[start]] + vertices[indices[start + 1]] + vertices[indices[start + 2]]) / 3.0
			var cell := Vector3i(floori(center.x / cell_size), floori(center.y / cell_size), floori(center.z / cell_size))
			if not surface_cells.has(cell):
				surface_cells[cell] = {"remap": {}, "vertices": PackedVector3Array(),
					"normals": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}
			var data: Dictionary = surface_cells[cell]
			var remap: Dictionary = data["remap"]
			# Packed arrays have reference semantics; assign back after appending for clarity.
			var out_vertices: PackedVector3Array = data["vertices"]
			var out_normals: PackedVector3Array = data["normals"]
			var out_uvs: PackedVector2Array = data["uvs"]
			var out_indices: PackedInt32Array = data["indices"]
			for corner in range(3):
				var index := indices[start + corner]
				if not remap.has(index):
					remap[index] = out_vertices.size()
					out_vertices.append(vertices[index])
					out_normals.append(normals[index])
					out_uvs.append(uvs[index])
				out_indices.append(remap[index])
			data["vertices"] = out_vertices
			data["normals"] = out_normals
			data["uvs"] = out_uvs
			data["indices"] = out_indices
		for cell: Vector3i in surface_cells:
			if not cells.has(cell):
				var empty_surfaces: Array = []
				empty_surfaces.resize(surface_count)
				for i in range(empty_surfaces.size()):
					empty_surfaces[i] = []
				cells[cell] = empty_surfaces
			var data: Dictionary = surface_cells[cell]
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
			arrays[Mesh.ARRAY_NORMAL] = data["normals"]
			arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
			arrays[Mesh.ARRAY_INDEX] = data["indices"]
			cells[cell][surface] = arrays
	return cells


func _surface_count(mesh: ArrayMesh) -> int:
	return mesh.get_meta("_roda_output_arrays", []).size() if mesh.get_meta("_roda_direct_output", false) else mesh.get_surface_count()


func _source_material(mesh: ArrayMesh, surface: int) -> Material:
	return mesh.get_meta("_roda_output_materials")[surface] if mesh.get_meta("_roda_direct_output", false) else mesh.surface_get_material(surface)


func sync_collision(instance: MeshInstance3D, road: Node3D, geometry_changed := true, template: StaticBody3D = null) -> void:
	var body := instance.get_node_or_null("StaticBody3D") as StaticBody3D
	var requested := bool(road.get("output_generate_collision")) or template != null
	if not requested and body != null and body.has_meta(COLLISION_META):
		instance.remove_child(body)
		body.queue_free()
		return
	if body == null:
		if not requested or instance.mesh == null:
			return
		body = StaticBody3D.new()
		body.name = "StaticBody3D"
		body.set_meta(COLLISION_META, true)
		instance.add_child(body)
		_set_editor_owner(body, road)
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		body.add_child(shape)
		_set_editor_owner(shape, road)
	if body.has_meta(COLLISION_META):
		if template != null:
			body.transform = template.transform
			body.collision_layer = template.collision_layer
			body.collision_mask = template.collision_mask
			body.physics_material_override = template.physics_material_override
			body.constant_linear_velocity = template.constant_linear_velocity
			body.constant_angular_velocity = template.constant_angular_velocity
		else:
			body.transform = Transform3D.IDENTITY
			body.collision_layer = int(road.get("output_collision_layer"))
			body.collision_mask = int(road.get("output_collision_mask"))
			body.physics_material_override = null
			body.constant_linear_velocity = Vector3.ZERO
			body.constant_angular_velocity = Vector3.ZERO
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	if body.has_meta(COLLISION_META):
		var shape_template := template.get_node_or_null("CollisionShape3D") as CollisionShape3D if template != null else null
		shape_node.transform = shape_template.transform if shape_template != null else Transform3D.IDENTITY
		shape_node.disabled = shape_template.disabled if shape_template != null else false
	if instance.mesh == null or instance.mesh.get_surface_count() == 0:
		shape_node.shape = null
	elif geometry_changed or shape_node.shape == null:
		shape_node.shape = instance.mesh.create_trimesh_shape()


func _set_editor_owner(node: Node, road: Node) -> void:
	if Engine.is_editor_hint() and road.is_inside_tree():
		node.owner = road.get_tree().edited_scene_root


func pack_output(road: Node3D, output_names: Array[String]) -> PackedScene:
	var root := Node3D.new()
	root.name = str(road.name) + "Baked"
	# Keep the creator's transform relative to its parent. No source paths or scripts.
	root.transform = road.transform
	root.visible = road.visible
	var has_geometry := false
	for output_name in output_names:
		var source := road.get_node_or_null(NodePath(output_name))
		if source == null:
			continue
		var copy := _copy_output_node(source)
		if copy != null:
			root.add_child(copy)
			_own_subtree(copy, root)
			has_geometry = true
	if not has_geometry:
		root.free()
		return null
	var packed := PackedScene.new()
	var result := packed.pack(root)
	root.free()
	return packed if result == OK else null


func _copy_output_node(source: Node) -> Node3D:
	var copy: Node3D
	if source is MeshInstance3D:
		if source.mesh == null:
			return null
		var instance := MeshInstance3D.new()
		instance.mesh = source.mesh
		_copy_visual_settings(source, instance)
		for i in range(source.get_surface_override_material_count()):
			instance.set_surface_override_material(i, source.get_surface_override_material(i))
		copy = instance
	elif source is StaticBody3D:
		var body := StaticBody3D.new()
		body.collision_layer = source.collision_layer
		body.collision_mask = source.collision_mask
		body.physics_material_override = source.physics_material_override
		body.constant_linear_velocity = source.constant_linear_velocity
		body.constant_angular_velocity = source.constant_angular_velocity
		copy = body
	elif source is CollisionShape3D:
		var shape := CollisionShape3D.new()
		shape.shape = source.shape
		shape.disabled = source.disabled
		copy = shape
	elif source.get_class() == "Node3D":
		copy = Node3D.new()
	else:
		return null
	copy.name = source.name
	copy.transform = source.transform
	copy.visible = source.visible
	for child in source.get_children():
		var child_copy := _copy_output_node(child)
		if child_copy != null:
			copy.add_child(child_copy)
	return copy


func _copy_visual_settings(source: GeometryInstance3D, target: GeometryInstance3D) -> void:
	for property in ["visible", "layers", "material_override", "material_overlay", "cast_shadow",
		"gi_mode", "gi_lightmap_scale", "extra_cull_margin", "ignore_occlusion_culling",
		"transparency", "sorting_offset", "sorting_use_aabb_center", "visibility_range_begin",
		"visibility_range_end", "visibility_range_begin_margin", "visibility_range_end_margin",
		"visibility_range_fade_mode", "lod_bias"]:
		target.set(property, source.get(property))


func _own_subtree(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_own_subtree(child, root)
