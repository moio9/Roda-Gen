@tool
extends RefCounted
## Final native topology output. Whole triangles belong to XZ centroid cells;
## native normals include complete smoothing support across cell borders.
const MESH_ROOT := "GeneratedTopologyTerrain"
const BODY_ROOT := "GeneratedTopologyTerrainCollision"
const MAX_CHUNKS := 4096
const MAX_SNAPSHOT_BYTES := 64 * 1024 * 1024

var stats: Dictionary = {}
var _records: Dictionary = {}
var _roots: Dictionary = {}
var _normal_cache = preload("./topology_normal_cache.gd").new()


func clear() -> void:
	_records.clear()
	_roots.clear()
	_normal_cache.clear()
	stats = {}


func publish(builder: Node3D, arrays: Array, cell_size: float, reuse: bool, collision: bool, material: Material) -> bool:
	var started := Time.get_ticks_usec()
	_reset_stats()
	var cells := _partition(arrays, maxf(8.0, cell_size))
	return _publish_cells(builder, cells, reuse, collision, material, started)


func publish_surface(builder: Node3D, surface: SurfaceTool, cell_size: float, reuse: bool, collision: bool, material: Material, local_normals: bool) -> bool:
	return _publish_source(builder, surface, surface.commit_to_arrays() if local_normals else [],
		cell_size, reuse, collision, material, local_normals)


func publish_raw(builder: Node3D, arrays: Array, cell_size: float, reuse: bool, collision: bool, material: Material, local_normals: bool) -> bool:
	# Internal native vertex/UV stream, not arbitrary custom SurfaceTool formats.
	return _publish_source(builder, null, arrays, cell_size, reuse, collision, material, local_normals)


func _publish_source(builder: Node3D, surface: SurfaceTool, arrays: Array, cell_size: float,
		reuse: bool, collision: bool, material: Material, local_normals: bool) -> bool:
	var started := Time.get_ticks_usec()
	_reset_stats()
	stats.source_surface_builds = int(surface != null)
	var cells: Dictionary = {}
	var fallback_full := false
	if local_normals:
		cells = _normal_cache.prepare(surface, arrays, maxf(8.0, cell_size), _partition_data)
		stats.source_surface_builds += _normal_cache.stats.get("source_surface_builds", 0)
	else:
		_normal_cache.clear()
	if cells.is_empty():
		fallback_full = true
		if surface == null:
			surface = SurfaceTool.new()
			surface.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
			stats.source_surface_builds += 1
		surface.generate_normals()
		cells = _partition(surface.commit_to_arrays(), maxf(8.0, cell_size))
	var normal_stats := {"full_calls": 0, "patch_calls": 0, "vertices_reused": 0, "vertices_rebuilt": 0}
	if local_normals:
		normal_stats.merge(_normal_cache.stats, true)
	else:
		normal_stats.fallback = "disabled_or_modifier"
	if fallback_full:
		normal_stats.full_calls += 1
	stats["normals"] = normal_stats
	return _publish_cells(builder, cells, reuse, collision, material, started)


func _reset_stats() -> void:
	stats = {"mesh_reused": 0, "mesh_rebuilt": 0, "collision_reused": 0,
		"collision_rebuilt": 0, "chunks": 0, "snapshot_bytes": 0, "fallback": "", "source_surface_builds": 0}


func _publish_cells(builder: Node3D, cells: Dictionary, reuse: bool, collision: bool, material: Material, started: int) -> bool:
	if cells.is_empty() or cells.size() > MAX_CHUNKS:
		stats.fallback = "unsupported_or_excessive_chunks"
		return false
	var root := _root(builder, MESH_ROOT, false)
	var body: Node3D = _root(builder, BODY_ROOT, true) if collision else null
	if not collision:
		_remove(builder.get_node_or_null(BODY_ROOT))
	var retained: Dictionary = {}
	var next_records: Dictionary = {}
	for cell: Vector2i in cells:
		var chunk_name := "Chunk_%d_%d" % [cell.x, cell.y]
		retained[chunk_name] = true
		var chunk_arrays: Array = cells[cell]
		var input := var_to_bytes(chunk_arrays)
		var faces: PackedVector3Array = chunk_arrays[Mesh.ARRAY_VERTEX]
		var faces_input := var_to_bytes(faces)
		var previous: Dictionary = _records.get(cell, {}) if reuse else {}
		var instance := root.get_node_or_null(NodePath(chunk_name)) as MeshInstance3D
		var mesh_valid := instance != null and _matches_node(instance, previous.get("instance"), previous.get("instance_state", []))
		if mesh_valid:
			mesh_valid = instance.mesh != null and instance.mesh.get_surface_count() == 1 \
				and instance.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES \
				and instance.mesh.surface_get_material(0) == null and instance.mesh.custom_aabb == AABB() \
				and previous.get("input") == input \
				and var_to_bytes(instance.mesh.surface_get_arrays(0)) == previous.get("live_arrays")
		if not mesh_valid:
			_remove(root.get_node_or_null(NodePath(chunk_name)))
			instance = MeshInstance3D.new()
			instance.name = chunk_name
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk_arrays)
			instance.mesh = mesh
			root.add_child(instance)
			stats.mesh_rebuilt += 1
		else:
			stats.mesh_reused += 1
		instance.material_override = material
		_own(instance, builder)
		var shape: CollisionShape3D = body.get_node_or_null(NodePath(chunk_name)) as CollisionShape3D if body != null else null
		if body != null:
			var shape_valid := shape != null and _matches_node(shape, previous.get("shape"), previous.get("shape_state", []))
			if shape_valid:
				shape_valid = shape.shape is ConcavePolygonShape3D and previous.get("faces_input") == faces_input \
					and [shape.shape.margin, shape.shape.backface_collision] == previous.get("shape_settings") \
					and var_to_bytes(shape.shape.get_faces()) == previous.get("live_faces")
			if not shape_valid:
				_remove(body.get_node_or_null(NodePath(chunk_name)))
				shape = CollisionShape3D.new()
				shape.name = chunk_name
				shape.shape = instance.mesh.create_trimesh_shape()
				body.add_child(shape)
				stats.collision_rebuilt += 1
			else:
				stats.collision_reused += 1
			_own(shape, builder)
		var live_arrays := var_to_bytes(instance.mesh.surface_get_arrays(0))
		var live_faces := var_to_bytes(shape.shape.get_faces()) if shape != null else PackedByteArray()
		var size := input.size() + faces_input.size() + live_arrays.size() + live_faces.size()
		if reuse and int(stats.snapshot_bytes) + size <= MAX_SNAPSHOT_BYTES:
			next_records[cell] = {"input": input, "faces_input": faces_input,
				"instance": weakref(instance), "instance_state": _node_state(instance),
				"live_arrays": live_arrays, "shape": weakref(shape) if shape != null else null,
				"shape_state": _node_state(shape) if shape != null else [], "live_faces": live_faces,
				"shape_settings": [shape.shape.margin, shape.shape.backface_collision] if shape != null else []}
			stats.snapshot_bytes += size
	for parent: Node in [root, body]:
		if parent == null:
			continue
		for child: Node in parent.get_children():
			if not retained.has(str(child.name)):
				_remove(child)
	_records = next_records
	for parent: Node in [root, body]:
		if parent != null:
			_roots[str(parent.name)] = {"node": weakref(parent), "state": _node_state(parent)}
	stats.chunks = cells.size()
	stats.output_ms = float(Time.get_ticks_usec() - started) / 1000.0
	return true


func _partition(arrays: Array, cell_size: float) -> Dictionary:
	return _partition_data(arrays, cell_size).get("cells", {})


func _partition_data(arrays: Array, cell_size: float, allow_raw := false) -> Dictionary:
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null:
		return {}
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		return {}
	if not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array and not (allow_raw and arrays[Mesh.ARRAY_NORMAL] == null):
		return {}
	if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		return {}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if (vertices.size() != normals.size() and not (allow_raw and normals.is_empty())) or vertices.size() != uvs.size():
		return {}
	# Native topology emits only positions, smooth normals and UVs. Do not
	# silently lose any future/custom vertex stream that this splitter cannot copy.
	for slot in range(Mesh.ARRAY_MAX):
		if slot not in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX] and arrays[slot] != null:
			return {}
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	if count % 3 != 0:
		return {}
	var groups: Dictionary = {}
	for i in range(0, count, 3):
		var a := indices[i] if not indices.is_empty() else i
		var b := indices[i + 1] if not indices.is_empty() else i + 1
		var c := indices[i + 2] if not indices.is_empty() else i + 2
		if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size():
			return {}
		var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
		if not center.is_finite() or absf(center.x / cell_size) > 2000000000.0 or absf(center.z / cell_size) > 2000000000.0:
			return {}
		var cell := Vector2i(floori(center.x / cell_size), floori(center.z / cell_size))
		if not groups.has(cell):
			if groups.size() >= MAX_CHUNKS:
				return {}
			groups[cell] = []
		var ids: Array = groups[cell]
		ids.append(a)
		ids.append(b)
		ids.append(c)
	var result: Dictionary = {}
	for cell: Vector2i in groups:
		var ids: Array = groups[cell]
		var positions := PackedVector3Array()
		var output_normals := PackedVector3Array()
		var output_uvs := PackedVector2Array()
		positions.resize(ids.size())
		if not normals.is_empty():
			output_normals.resize(ids.size())
		output_uvs.resize(ids.size())
		for i in range(ids.size()):
			positions[i] = vertices[ids[i]]
			if not normals.is_empty():
				output_normals[i] = normals[ids[i]]
			output_uvs[i] = uvs[ids[i]]
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = positions
		output[Mesh.ARRAY_NORMAL] = output_normals if not normals.is_empty() else null
		output[Mesh.ARRAY_TEX_UV] = output_uvs
		result[cell] = output
	return {"cells": result, "groups": groups}


func _matches_node(node: Node, reference: Variant, state: Array, allow_children := false) -> bool:
	return reference is WeakRef and reference.get_ref() == node and not node.is_queued_for_deletion() \
		and node.get_script() == null and (allow_children or node.get_child_count() == 0) and _node_state(node) == state


func _node_state(node: Node) -> Array:
	var result: Array = []
	for property: Dictionary in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			result.append([property.name, node.get(property.name)])
	return result.duplicate(true)


func _root(builder: Node3D, root_name: String, body: bool) -> Node3D:
	var node := builder.get_node_or_null(NodePath(root_name)) as Node3D
	var native_class := "StaticBody3D" if body else "Node3D"
	var previous: Dictionary = _roots.get(root_name, {})
	if node == null or node.get_class() != native_class or not _matches_node(node, previous.get("node"), previous.get("state", []), true):
		_remove(builder.get_node_or_null(NodePath(root_name)))
		node = StaticBody3D.new() if body else Node3D.new()
		node.name = root_name
		builder.add_child(node)
	node.transform = Transform3D.IDENTITY
	node.visible = true
	if node is StaticBody3D:
		for exception: PhysicsBody3D in node.get_collision_exceptions():
			node.remove_collision_exception_with(exception)
		node.collision_layer = 1
		node.collision_mask = 1
		node.physics_material_override = null
		node.constant_linear_velocity = Vector3.ZERO
		node.constant_angular_velocity = Vector3.ZERO
	_own(node, builder)
	return node


func _own(node: Node, builder: Node) -> void:
	node.owner = builder.get_tree().edited_scene_root if Engine.is_editor_hint() and builder.is_inside_tree() else null


func _remove(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
