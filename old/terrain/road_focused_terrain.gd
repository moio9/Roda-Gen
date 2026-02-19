@tool
extends Node3D

@export_group("Input")
@export var seam_source_mesh_nodes: Array[NodePath] = []

@export_group("Simple XZ Extrude")
@export_range(0.0, 200.0, 0.01) var xz_extrude_distance := 4.0
@export_range(0.0001, 1.0, 0.0001) var seam_weld_epsilon := 0.0005
@export_range(0.0, 1.0, 0.01) var boundary_min_normal_y := 0.25
@export_range(-50.0, 50.0, 0.01) var y_offset := 0.0
@export_range(0.0001, 10.0, 0.0001) var uv_scale := 0.03
@export var material_override: Material

@export_group("Compatibility")
@export var boundary_path: NodePath
@export var boundary_polygon_points: PackedVector2Array = PackedVector2Array()
@export var source_path_nodes: Array[NodePath] = []
@export_range(0.0, 100.0, 0.01) var obstacle_inset := 0.0
@export var close_open_chains := true

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_regenerate_in_editor := true
@export var regenerate_now := false: set = _set_regenerate_now
@export var debug_generation_logs := false

const MESH_NODE_NAME := "GeneratedRoadFocusedTerrain"

var _last_signature := ""


func _ready() -> void:
	set_process(true)
	if _can_generate():
		regenerate()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not auto_regenerate_in_editor:
		return
	if not _can_generate():
		return

	var sig := _build_signature()
	if sig == _last_signature:
		return
	_last_signature = sig
	regenerate()


func _set_regenerate_now(value: bool) -> void:
	regenerate_now = false
	if value and _can_generate():
		regenerate()


func _can_generate() -> bool:
	return not Engine.is_editor_hint() or generate_in_editor


func _debug_log(message: String) -> void:
	if not debug_generation_logs:
		return
	print("[RoadFocusedTerrain] " + message)


func regenerate() -> void:
	var collected := _collect_source_geometry()
	var source_vertices: PackedVector3Array = collected.get("vertices", PackedVector3Array())
	var source_indices: PackedInt32Array = collected.get("indices", PackedInt32Array())
	if source_vertices.is_empty() or source_indices.is_empty():
		_debug_log("No valid source triangles. Clearing generated mesh.")
		_clear_mesh()
		_last_signature = _build_signature()
		return

	var out_mesh := _build_extruded_mesh(collected)
	if out_mesh == null:
		_debug_log("Failed to build extruded mesh. Clearing generated mesh.")
		_clear_mesh()
		_last_signature = _build_signature()
		return

	_assign_mesh(out_mesh)
	_last_signature = _build_signature()


func _collect_source_geometry() -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var weld_map: Dictionary = {}
	var edge_counts: Dictionary = {}
	var edge_normal_sums: Dictionary = {}
	var inv_global := global_transform.affine_inverse()
	var source_count := 0
	var tri_count := 0

	for mesh_instance in _resolve_source_mesh_instances():
		if mesh_instance.mesh == null:
			continue
		source_count += 1
		var source_mesh := mesh_instance.mesh
		var to_local := inv_global * mesh_instance.global_transform

		for surface_idx in range(source_mesh.get_surface_count()):
			var arrays := source_mesh.surface_get_arrays(surface_idx)
			if arrays.is_empty():
				continue

			var surface_vertices := PackedVector3Array()
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				surface_vertices = arrays[Mesh.ARRAY_VERTEX]
			if surface_vertices.is_empty():
				continue

			var surface_indices := PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				surface_indices = arrays[Mesh.ARRAY_INDEX]
			if surface_indices.is_empty():
				var tri_vertices := surface_vertices.size() - (surface_vertices.size() % 3)
				for i in range(0, tri_vertices, 3):
					if _append_source_triangle(
						surface_vertices,
						i,
						i + 1,
						i + 2,
						to_local,
						vertices,
						indices,
						weld_map,
						edge_counts,
						edge_normal_sums
					):
						tri_count += 1
			else:
				var tri_indices := surface_indices.size() - (surface_indices.size() % 3)
				for i in range(0, tri_indices, 3):
					if _append_source_triangle(
						surface_vertices,
						int(surface_indices[i]),
						int(surface_indices[i + 1]),
						int(surface_indices[i + 2]),
						to_local,
						vertices,
						indices,
						weld_map,
						edge_counts,
						edge_normal_sums
					):
						tri_count += 1

	var boundary_edges: Array = []
	for key in edge_counts.keys():
		if int(edge_counts[key]) != 1:
			continue
		var edge_normal: Vector3 = edge_normal_sums.get(key, Vector3.ZERO)
		if edge_normal.length_squared() < 0.000000001:
			continue
		if absf(edge_normal.normalized().y) < boundary_min_normal_y:
			continue
		boundary_edges.push_back(key)

	_debug_log(
		"collected sources=%d verts=%d tris=%d boundary_edges=%d"
		% [source_count, vertices.size(), tri_count, boundary_edges.size()]
	)
	return {
		"vertices": vertices,
		"indices": indices,
		"boundary_edges": boundary_edges,
	}


func _append_source_triangle(
	surface_vertices: PackedVector3Array,
	i0: int,
	i1: int,
	i2: int,
	to_local: Transform3D,
	out_vertices: PackedVector3Array,
	out_indices: PackedInt32Array,
	weld_map: Dictionary,
	edge_counts: Dictionary,
	edge_normal_sums: Dictionary
) -> bool:
	if i0 < 0 or i1 < 0 or i2 < 0:
		return false
	if i0 >= surface_vertices.size() or i1 >= surface_vertices.size() or i2 >= surface_vertices.size():
		return false

	var p0 := to_local * surface_vertices[i0]
	var p1 := to_local * surface_vertices[i1]
	var p2 := to_local * surface_vertices[i2]

	var w0 := _get_or_create_welded_vertex_id(p0, out_vertices, weld_map)
	var w1 := _get_or_create_welded_vertex_id(p1, out_vertices, weld_map)
	var w2 := _get_or_create_welded_vertex_id(p2, out_vertices, weld_map)
	if w0 == w1 or w1 == w2 or w2 == w0:
		return false

	var tri_n := (out_vertices[w1] - out_vertices[w0]).cross(out_vertices[w2] - out_vertices[w0])
	if tri_n.length_squared() < 0.000000000001:
		return false

	out_indices.push_back(w0)
	out_indices.push_back(w1)
	out_indices.push_back(w2)
	_count_edge(w0, w1, tri_n, edge_counts, edge_normal_sums)
	_count_edge(w1, w2, tri_n, edge_counts, edge_normal_sums)
	_count_edge(w2, w0, tri_n, edge_counts, edge_normal_sums)
	return true


func _get_or_create_welded_vertex_id(
	position: Vector3,
	out_vertices: PackedVector3Array,
	weld_map: Dictionary
) -> int:
	var eps := maxf(seam_weld_epsilon, 0.000001)
	var key := Vector3i(
		int(round(position.x / eps)),
		int(round(position.y / eps)),
		int(round(position.z / eps))
	)
	if weld_map.has(key):
		return int(weld_map[key])

	var id := out_vertices.size()
	out_vertices.push_back(position)
	weld_map[key] = id
	return id


func _count_edge(
	a: int,
	b: int,
	tri_normal: Vector3,
	edge_counts: Dictionary,
	edge_normal_sums: Dictionary
) -> void:
	if a == b:
		return
	var key := Vector2i(mini(a, b), maxi(a, b))
	edge_counts[key] = int(edge_counts.get(key, 0)) + 1
	edge_normal_sums[key] = edge_normal_sums.get(key, Vector3.ZERO) + tri_normal


func _build_extruded_mesh(collected: Dictionary) -> ArrayMesh:
	var base_vertices: PackedVector3Array = collected.get("vertices", PackedVector3Array())
	var base_indices: PackedInt32Array = collected.get("indices", PackedInt32Array())
	var boundary_edges: Array = collected.get("boundary_edges", [])
	if base_vertices.is_empty() or base_indices.is_empty():
		return null

	var vertices := PackedVector3Array()
	vertices.resize(base_vertices.size())
	for i in range(base_vertices.size()):
		var p := base_vertices[i]
		p.y += y_offset
		vertices[i] = p

	var indices := PackedInt32Array()
	indices.append_array(base_indices)

	if xz_extrude_distance > 0.000001 and not boundary_edges.is_empty():
		var out_dirs := _compute_boundary_out_dirs(vertices, boundary_edges)
		var extruded_ids: Dictionary = {}
		for edge_variant in boundary_edges:
			var edge: Vector2i = edge_variant
			var a := edge.x
			var b := edge.y
			if a < 0 or b < 0:
				continue
			if a >= vertices.size() or b >= vertices.size():
				continue

			var a_out := _get_or_create_extruded_vertex_id(a, vertices, out_dirs, extruded_ids)
			var b_out := _get_or_create_extruded_vertex_id(b, vertices, out_dirs, extruded_ids)
			_append_oriented_triangle(indices, vertices, a, b, b_out, Vector3.UP)
			_append_oriented_triangle(indices, vertices, a, b_out, a_out, Vector3.UP)

	var normals := _compute_vertex_normals(vertices, indices)
	var safe_uv_scale := maxf(uv_scale, 0.000001)
	var uvs := PackedVector2Array()
	uvs.resize(vertices.size())
	for i in range(vertices.size()):
		var v := vertices[i]
		uvs[i] = Vector2(v.x, v.z) * safe_uv_scale

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material_override != null:
		mesh.surface_set_material(0, material_override)
	return mesh


func _compute_boundary_out_dirs(vertices: PackedVector3Array, boundary_edges: Array) -> Dictionary:
	var dirs: Dictionary = {}
	var boundary_ids: Dictionary = {}

	for edge_variant in boundary_edges:
		var edge: Vector2i = edge_variant
		boundary_ids[edge.x] = true
		boundary_ids[edge.y] = true

	if boundary_ids.is_empty():
		return dirs

	var center := Vector2.ZERO
	for id_variant in boundary_ids.keys():
		var id := int(id_variant)
		if id < 0 or id >= vertices.size():
			continue
		center += Vector2(vertices[id].x, vertices[id].z)
	center /= maxf(1.0, float(boundary_ids.size()))

	for edge_variant in boundary_edges:
		var edge: Vector2i = edge_variant
		var a := edge.x
		var b := edge.y
		if a < 0 or b < 0:
			continue
		if a >= vertices.size() or b >= vertices.size():
			continue

		var p0 := Vector2(vertices[a].x, vertices[a].z)
		var p1 := Vector2(vertices[b].x, vertices[b].z)
		var tangent := p1 - p0
		if tangent.length_squared() < 0.00000001:
			continue
		tangent = tangent.normalized()

		var n := Vector2(-tangent.y, tangent.x)
		var to_out := ((p0 + p1) * 0.5) - center
		if to_out.length_squared() < 0.00000001:
			to_out = n
		else:
			to_out = to_out.normalized()
		if n.dot(to_out) < 0.0:
			n = -n

		dirs[a] = dirs.get(a, Vector2.ZERO) + n
		dirs[b] = dirs.get(b, Vector2.ZERO) + n

	for id_variant in boundary_ids.keys():
		var id := int(id_variant)
		if id < 0 or id >= vertices.size():
			continue
		var d: Vector2 = dirs.get(id, Vector2.ZERO)
		if d.length_squared() < 0.00000001:
			d = Vector2(vertices[id].x, vertices[id].z) - center
		if d.length_squared() < 0.00000001:
			d = Vector2.RIGHT
		dirs[id] = d.normalized()

	return dirs


func _get_or_create_extruded_vertex_id(
	base_vertex_id: int,
	vertices: PackedVector3Array,
	out_dirs: Dictionary,
	extruded_ids: Dictionary
) -> int:
	if extruded_ids.has(base_vertex_id):
		return int(extruded_ids[base_vertex_id])

	var out_2d: Vector2 = out_dirs.get(base_vertex_id, Vector2.RIGHT)
	var out_3d := Vector3(out_2d.x, 0.0, out_2d.y) * xz_extrude_distance
	var id := vertices.size()
	vertices.push_back(vertices[base_vertex_id] + out_3d)
	extruded_ids[base_vertex_id] = id
	return id


func _append_oriented_triangle(
	indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	desired_normal: Vector3
) -> void:
	if a < 0 or b < 0 or c < 0:
		return
	if a >= verts.size() or b >= verts.size() or c >= verts.size():
		return
	if a == b or b == c or c == a:
		return

	var tri_n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if tri_n.length_squared() < 0.000000000001:
		return
	if tri_n.dot(desired_normal) >= 0.0:
		indices.push_back(a)
		indices.push_back(b)
		indices.push_back(c)
	else:
		indices.push_back(a)
		indices.push_back(c)
		indices.push_back(b)


func _compute_vertex_normals(
	vertices: PackedVector3Array,
	indices: PackedInt32Array
) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())

	var tri_count := indices.size() - (indices.size() % 3)
	for i in range(0, tri_count, 3):
		var a := int(indices[i])
		var b := int(indices[i + 1])
		var c := int(indices[i + 2])
		if a < 0 or b < 0 or c < 0:
			continue
		if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
			continue

		var n := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if n.length_squared() < 0.000000000001:
			continue
		normals[a] = normals[a] + n
		normals[b] = normals[b] + n
		normals[c] = normals[c] + n

	for i in range(normals.size()):
		if normals[i].length_squared() < 0.000000000001:
			normals[i] = Vector3.UP
		else:
			normals[i] = normals[i].normalized()
	return normals


func _resolve_source_mesh_instances() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for np in seam_source_mesh_nodes:
		var node := get_node_or_null(np)
		if node is MeshInstance3D:
			out.push_back(node as MeshInstance3D)
	return out


func _assign_mesh(mesh: ArrayMesh) -> void:
	var mi := get_node_or_null(MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MESH_NODE_NAME
		add_child(mi)
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
	mi.mesh = mesh
	mi.material_override = material_override


func _clear_mesh() -> void:
	var mi := get_node_or_null(MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		return
	mi.mesh = null
	mi.material_override = material_override


func _build_signature() -> String:
	var parts: Array[String] = []
	parts.append(str(seam_source_mesh_nodes))
	parts.append(str(xz_extrude_distance))
	parts.append(str(seam_weld_epsilon))
	parts.append(str(boundary_min_normal_y))
	parts.append(str(y_offset))
	parts.append(str(uv_scale))
	parts.append(str(material_override))

	for mesh_instance in _resolve_source_mesh_instances():
		parts.append(str(mesh_instance.global_transform))
		if mesh_instance.mesh == null:
			parts.append("null_mesh")
			continue
		var mesh := mesh_instance.mesh
		parts.append(str(mesh.get_rid()))
		parts.append(str(mesh.get_surface_count()))
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			if arrays.is_empty():
				parts.append("empty_surface")
				continue
			var surface_vertices := PackedVector3Array()
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				surface_vertices = arrays[Mesh.ARRAY_VERTEX]
			var surface_indices := PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				surface_indices = arrays[Mesh.ARRAY_INDEX]
			parts.append(str(surface_vertices.size()))
			parts.append(str(surface_indices.size()))

	return "|".join(parts)
