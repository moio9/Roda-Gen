extends "../../addons/scripts/spline_road/road_mesh_builder.gd"
## Timing-only wrapper; all geometry still comes from the native implementation.
var normal_ms := 0.0
var normal_vertices := 0
var mesh_ms := 0.0
var force_full_normals := false


func reset_times() -> void:
	normal_ms = 0.0
	normal_vertices = 0
	mesh_ms = 0.0


func _compute_surface_normals_from_indices(verts: PackedVector3Array,
		indices: PackedInt32Array, fallback_normals: PackedVector3Array) -> PackedVector3Array:
	var started := Time.get_ticks_usec()
	var result := super._compute_surface_normals_full(verts, indices, fallback_normals) if force_full_normals \
		else super._compute_surface_normals_from_indices(verts, indices, fallback_normals)
	normal_ms += float(Time.get_ticks_usec() - started) / 1000.0
	normal_vertices += verts.size()
	return result


func _build_mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		lane_indices: PackedInt32Array, shoulder_indices: PackedInt32Array, sidewalk_indices: PackedInt32Array,
		terrain_indices: PackedInt32Array, wall_indices: PackedInt32Array) -> ArrayMesh:
	var started := Time.get_ticks_usec()
	var result := super._build_mesh(verts, normals, uvs, lane_indices, shoulder_indices,
		sidewalk_indices, terrain_indices, wall_indices)
	mesh_ms += float(Time.get_ticks_usec() - started) / 1000.0
	return result
