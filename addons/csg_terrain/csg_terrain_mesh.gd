## Class responsible to deal with the mesh itself.
## This is what makes the terrain bend with the curves.
class_name CSGTerrainMesh

# Vertex grid in [x][z] plane.
var vertex_grid: Array = []

var uvs: PackedVector2Array = []
var indices: PackedInt32Array = []
var extra_vertices: PackedVector3Array = []
var extra_uvs: PackedVector2Array = []
var extra_indices: PackedInt32Array = []


## Main mesh manager. This is what external classes should call.
func update_mesh(mesh: ArrayMesh, path_list: Array[CSGTerrainPath], divs: int, size: float) -> void:
	# Recrieate all mesh arrays. Seems expensive but is the last of our problems.
	_create_mesh_arrays(divs, size)
	
	# Make the mesh follow each path, in tree order. 90% of the time is spent here.
	for path in path_list:
		if path.curve.bake_interval != (size / divs):
			path.curve.bake_interval = (size / divs)
		
		if path.width > 0:
			_follow_curve(path, divs, size)
	
	# Organize all the mesh at once. Again, seems expensive but is not an issue.
	_commit_mesh(size, divs, mesh)


## Create the terrain mesh according the vertex grid.
func _create_mesh_arrays(divs: int, size: float) -> void:
	# Vertex Grid follow the pattern [x][z]. The y axis is what will follow the curves.
	vertex_grid.clear()
	vertex_grid.resize(divs + 1)
	
	# Apply scale.
	var step: float = size / divs
	var center: Vector3 = Vector3(0.5 * size, 0, 0.5 * size)
	for x in range(divs + 1):
		var vertices_z: PackedVector3Array = []
		vertices_z.resize(divs + 1)
		for z in range(divs + 1):
			vertices_z[z] = Vector3(x * step, 0, z * step) - center
		vertex_grid[x] = vertices_z
	
	# Make uvs.
	uvs.clear()
	uvs.resize((divs + 1) * (divs + 1))
	var uv_step: float = 1.0 / divs
	var index: int = 0
	for x in range(divs + 1):
		for z in range(divs + 1):
			uvs[index] = Vector2(x * uv_step, z * uv_step)
			index += 1
	
	# Make quads with two triangles.
	indices.clear()
	indices.resize(divs * divs * 6)
	var row: int = 0
	var next_row: int = 0
	index = 0
	for x in range(divs):
		row = next_row
		next_row += divs + 1
		
		# Making the two triangles. Ways to make it more readable are welcomed.
		for z in range(divs):
			# First triangle vertices.
			indices[index] = z + row
			indices[index + 1] = z + row + 1
			indices[index + 2] = z + next_row + 1
			
			# Second triangle vertices.
			indices[index + 3] = z + row
			indices[index + 4] = z + next_row + 1
			indices[index + 5] = z + next_row
			
			index += 6

	extra_vertices.clear()
	extra_uvs.clear()
	extra_indices.clear()


## Finalize the mesh and aplly to the CSGMesh3D node.
func _commit_mesh(size: float, divs: int, mesh: ArrayMesh) -> void:
	# Mesh in ArrayMesh format.
	var surface_array: Array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	# Organize vertex matrix in format PackedVector3Array.
	var vert_list: PackedVector3Array = []
	for array in vertex_grid:
		vert_list.append_array(array)

	# Local remesh strip vertices.
	if extra_vertices.size() > 0 and extra_indices.size() > 0:
		var vertex_offset: int = vert_list.size()
		vert_list.append_array(extra_vertices)
		uvs.append_array(extra_uvs)
		for idx in extra_indices:
			indices.push_back(int(idx) + vertex_offset)

	surface_array[Mesh.ARRAY_VERTEX] = vert_list
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_TEX_UV2] = uvs
	surface_array[Mesh.ARRAY_INDEX] = indices
	
	# Make normals according Clever Normalization of a Mesh: https://iquilezles.org/articles/normals
	# Making manually because using surfacetool was 3-5 times slower.
	var normals: PackedVector3Array = []
	normals.resize(vert_list.size())
	
	for index in range(0, indices.size(), 3):
		# Vertices of the triangle.
		var a: Vector3 = vert_list[indices[index]]
		var b: Vector3 = vert_list[indices[index + 1]]
		var c: Vector3 = vert_list[indices[index + 2]]
		
		# Creating normal from edges.
		var edge1: Vector3 = b - a
		var edge2: Vector3 = c - a
		var normal: Vector3 = edge1.cross(edge2)
		
		# Adding normal to each vertex.
		normals[indices[index]] += normal
		normals[indices[index + 1]] += normal
		normals[indices[index + 2]] += normal
	
	# Normalize and apply.
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	
	surface_array[Mesh.ARRAY_NORMAL] = normals
	
	# Closing the shape because Godot 4.4 need this.
	_close_shape(size, divs, surface_array)
	
	# Commit to the main mash.
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)


## Bend the terrain height to follow the curve.
func _follow_curve(path: CSGTerrainPath, divs: int, size: float) -> void:
	var width: int = maxi(path.width, 1)
	var smoothness: float = path.smoothness
	var flat_enabled: bool = path.flat_road_enabled
	var flat_strength: float = clampf(path.flat_road_strength, 0.0, 1.0)
	var flat_single_band: bool = path.flat_single_band_mode
	var curb_enabled: bool = path.curb_enabled
	var curb_height: float = maxf(0.0, path.curb_height)
	var curb_band_ratio: float = clampf(path.curb_band_ratio, 0.0, 0.49)
	var local_remesh_enabled: bool = path.local_remesh_enabled
	var local_remesh_depth: float = maxf(
		maxf(0.01, path.local_remesh_depth),
		maxf(0.01, path.local_remesh_extrude_y_down)
	)
	var local_remesh_extrude_y_up: float = maxf(0.0, path.local_remesh_extrude_y_up)
	var local_remesh_y_offset: float = path.local_remesh_y_offset
	var carve_enabled: bool = local_remesh_enabled and path.local_remesh_carve_enabled
	var carve_extra_depth: float = maxf(0.0, path.local_remesh_carve_extra_depth)
	var carve_width_scale: float = maxf(1.0, path.local_remesh_carve_width_scale)
	var carve_falloff: float = maxf(0.0, path.local_remesh_carve_falloff)
	var influence_scale := 1.0
	if carve_enabled:
		influence_scale = carve_width_scale + carve_falloff
	var influence_width := maxi(width, int(ceili(float(width) * influence_scale)) + 1)
	
	var pos: Vector3 = path.position
	var center: Vector3 = Vector3(0.5 * size, 0, 0.5 * size)
	var curve: Curve3D = path.curve
	var baked3D: PackedVector3Array = curve.get_baked_points()
	
	if baked3D.size() < 2: return
	
	# Project the curve baked points in the [x][z] plane.
	var baked2D: PackedVector2Array = []
	baked2D.resize(baked3D.size())
	for i in range(baked3D.size()):
		var point: Vector3 = baked3D[i]
		baked2D[i] = Vector2(point.x, point.z)
	
	# Dictionary with all vertices at "width" distance from the curve.
	var curve_vertices = {}
	for point in baked3D:
		var local_point: Vector3 = point + pos + center
		
		# Point in the vertex_grid.
		var grid_point: Vector3 = local_point * divs / size
		var grid_index: Vector2i = Vector2i(int(grid_point.x), int(grid_point.z))
		
		# Exprore the region around the point. Cut out points outside the grid.
		var range_min_x: int = -influence_width + 1 + grid_index.x
		range_min_x = clampi(range_min_x, 0, divs + 1)
		var range_max_x: int = influence_width + 2 + grid_index.x
		range_max_x = clampi(range_max_x, 0, divs + 1)
		var range_min_y: int = -influence_width + 1 + grid_index.y
		range_min_y = clampi(range_min_y, 0, divs + 1)
		var range_max_y: int = influence_width + 2 + grid_index.y
		range_max_y = clampi(range_max_y, 0, divs + 1)
		
		for i in range(range_min_x, range_max_x):
			for j in range(range_min_y, range_max_y):
				curve_vertices[Vector2i(i, j)] = true
	
	# Interpolate the height of the vertices.
	for grid_idx in curve_vertices:
		var vertex: Vector3 = vertex_grid[grid_idx.x][grid_idx.y]
		var old_vertex: Vector3 = vertex
		
		# Vertex in path space.
		var path_vertex: Vector3 = vertex - pos
		
		# Get the closest point on the 3D curve without considering the height.
		var closest: Vector3 = _get_closest_point_in_xz_plane(baked2D, baked3D, path_vertex)
		
		# Back to local space.
		closest += pos
		
		# Distance relative to path witdh.
		vertex.y = closest.y
		var dist = vertex.distance_to(closest)
		var denominator = width * size
		if denominator == null:
			denominator = 1.0
		denominator = float(denominator)
		if absf(denominator) < 0.000001:
			denominator = 1.0
		var dist_relative: float = (dist * float(divs)) / denominator
		
		# Quadratic smooth.
		var lerp_weight: float = dist_relative * dist_relative * smoothness
		lerp_weight = clampf(lerp_weight, 0, 1)
		var height: float = lerpf(closest.y, old_vertex.y, lerp_weight)

		if flat_enabled:
			if dist_relative <= 1.0:
				var target_height := closest.y
				if curb_enabled:
					var curb_inner := 1.0 - curb_band_ratio
					if dist_relative >= curb_inner:
						target_height += curb_height
				if flat_single_band:
					height = target_height
				else:
					height = lerpf(height, target_height, flat_strength)
			elif flat_single_band:
				height = old_vertex.y

		var height_before_carve := height
		if carve_enabled:
			var road_top := closest.y + local_remesh_y_offset + local_remesh_extrude_y_up
			var road_bottom := road_top - local_remesh_depth - carve_extra_depth
			var inner := carve_width_scale
			var outer := carve_width_scale + carve_falloff
			if dist_relative <= inner:
				height = minf(height, road_bottom)
			elif dist_relative < outer and outer > inner + 0.000001:
				var t := (dist_relative - inner) / (outer - inner)
				t = clampf(t, 0.0, 1.0)
				var s := t * t * (3.0 - 2.0 * t)
				var blended := lerpf(road_bottom, height_before_carve, s)
				height = minf(height, blended)
		vertex.y = height
		
		vertex_grid[grid_idx.x][grid_idx.y] = vertex

	if local_remesh_enabled:
		_append_local_road_strip(path, divs, size)
	
	# Update indices on affected vertices.
	for grid_idx in curve_vertices:
		_update_quad_indices(grid_idx, divs)


func _append_local_road_strip(path: CSGTerrainPath, divs: int, size: float) -> void:
	var curve: Curve3D = path.curve
	if curve == null:
		return

	var samples: PackedVector3Array = _sample_curve_points(curve, path.local_remesh_step)
	if samples.size() < 2:
		return

	var half_width := maxf(
		(float(maxi(path.width, 1)) * size) / float(divs),
		size / float(divs)
	)
	var y_offset: float = path.local_remesh_y_offset
	var extrude_y_up: float = maxf(0.0, path.local_remesh_extrude_y_up)
	var depth: float = maxf(
		maxf(0.01, path.local_remesh_depth),
		maxf(0.01, path.local_remesh_extrude_y_down)
	)
	var path_pos: Vector3 = path.position
	var u_accum := 0.0
	var tangents: Array[Vector3] = []
	var top_left_ids := PackedInt32Array()
	var top_right_ids := PackedInt32Array()
	var bottom_left_ids := PackedInt32Array()
	var bottom_right_ids := PackedInt32Array()

	for i in range(samples.size()):
		var center := samples[i] + path_pos
		var tangent := Vector3.ZERO
		if curve.closed:
			var prev_i := (i - 1 + samples.size()) % samples.size()
			var next_i := (i + 1) % samples.size()
			tangent = samples[next_i] - samples[prev_i]
		elif i == 0:
			tangent = samples[1] - samples[0]
		elif i == samples.size() - 1:
			tangent = samples[i] - samples[i - 1]
		else:
			tangent = samples[i + 1] - samples[i - 1]
		tangent.y = 0.0
		if tangent.length_squared() < 0.0000001:
			tangent = Vector3.FORWARD
		else:
			tangent = tangent.normalized()
		tangents.push_back(tangent)

		var side := Vector3(tangent.z, 0.0, -tangent.x)
		if side.length_squared() < 0.0000001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()

		var top_left := center + side * half_width
		var top_right := center - side * half_width
		top_left.y = center.y + y_offset + extrude_y_up
		top_right.y = center.y + y_offset + extrude_y_up
		var bottom_left := top_left - Vector3.UP * depth
		var bottom_right := top_right - Vector3.UP * depth

		if i > 0:
			var prev_center := samples[i - 1] + path_pos
			u_accum += center.distance_to(prev_center)

		var tl := extra_vertices.size()
		extra_vertices.push_back(top_left)
		extra_uvs.push_back(Vector2(u_accum, 0.0))
		var tr := extra_vertices.size()
		extra_vertices.push_back(top_right)
		extra_uvs.push_back(Vector2(u_accum, 1.0))
		var bl := extra_vertices.size()
		extra_vertices.push_back(bottom_left)
		extra_uvs.push_back(Vector2(u_accum, 0.0))
		var br := extra_vertices.size()
		extra_vertices.push_back(bottom_right)
		extra_uvs.push_back(Vector2(u_accum, 1.0))

		top_left_ids.push_back(tl)
		top_right_ids.push_back(tr)
		bottom_left_ids.push_back(bl)
		bottom_right_ids.push_back(br)

	var seg_count := samples.size() - 1
	if curve.closed:
		seg_count = samples.size()
	for i in range(seg_count):
		var i0 := i
		var i1 := (i + 1) % samples.size()
		var tl0 := int(top_left_ids[i0])
		var tr0 := int(top_right_ids[i0])
		var bl0 := int(bottom_left_ids[i0])
		var br0 := int(bottom_right_ids[i0])
		var tl1 := int(top_left_ids[i1])
		var tr1 := int(top_right_ids[i1])
		var bl1 := int(bottom_left_ids[i1])
		var br1 := int(bottom_right_ids[i1])

		# Top and bottom.
		_append_strip_oriented_triangle(tl0, tr0, tl1, Vector3.UP)
		_append_strip_oriented_triangle(tr0, tr1, tl1, Vector3.UP)
		_append_strip_oriented_triangle(bl0, bl1, br0, Vector3.DOWN)
		_append_strip_oriented_triangle(br0, bl1, br1, Vector3.DOWN)

		# Side walls.
		var left_out := ((extra_vertices[tl0] - extra_vertices[tr0]) + (extra_vertices[tl1] - extra_vertices[tr1])) * 0.5
		left_out.y = 0.0
		if left_out.length_squared() < 0.0000001:
			left_out = Vector3.LEFT
		else:
			left_out = left_out.normalized()
		var right_out := -left_out
		_append_strip_oriented_quad(tl0, tl1, bl0, bl1, left_out)
		_append_strip_oriented_quad(tr1, tr0, br1, br0, right_out)

	# End caps for open paths.
	if not curve.closed and samples.size() >= 2:
		var start_tan := tangents[0]
		start_tan.y = 0.0
		if start_tan.length_squared() < 0.0000001:
			start_tan = Vector3.FORWARD
		else:
			start_tan = start_tan.normalized()
		var end_tan := tangents[tangents.size() - 1]
		end_tan.y = 0.0
		if end_tan.length_squared() < 0.0000001:
			end_tan = Vector3.FORWARD
		else:
			end_tan = end_tan.normalized()

		var s_tl := int(top_left_ids[0])
		var s_tr := int(top_right_ids[0])
		var s_bl := int(bottom_left_ids[0])
		var s_br := int(bottom_right_ids[0])
		var e_tl := int(top_left_ids[top_left_ids.size() - 1])
		var e_tr := int(top_right_ids[top_right_ids.size() - 1])
		var e_bl := int(bottom_left_ids[bottom_left_ids.size() - 1])
		var e_br := int(bottom_right_ids[bottom_right_ids.size() - 1])
		_append_strip_oriented_quad(s_tl, s_tr, s_bl, s_br, -start_tan)
		_append_strip_oriented_quad(e_tr, e_tl, e_br, e_bl, end_tan)


func _append_strip_oriented_quad(a: int, b: int, c: int, d: int, desired_normal: Vector3) -> void:
	_append_strip_oriented_triangle(a, b, c, desired_normal)
	_append_strip_oriented_triangle(c, b, d, desired_normal)


func _append_strip_oriented_triangle(a: int, b: int, c: int, desired_normal: Vector3) -> void:
	if a < 0 or b < 0 or c < 0:
		return
	if a >= extra_vertices.size() or b >= extra_vertices.size() or c >= extra_vertices.size():
		return
	if a == b or b == c or c == a:
		return

	var tri_n := (extra_vertices[b] - extra_vertices[a]).cross(extra_vertices[c] - extra_vertices[a])
	if tri_n.length_squared() < 0.000000000001:
		return
	if tri_n.dot(desired_normal) >= 0.0:
		extra_indices.push_back(a)
		extra_indices.push_back(b)
		extra_indices.push_back(c)
	else:
		extra_indices.push_back(a)
		extra_indices.push_back(c)
		extra_indices.push_back(b)


func _sample_curve_points(curve: Curve3D, step: float) -> PackedVector3Array:
	var out: PackedVector3Array = []
	var length: float = curve.get_baked_length()
	var sample_step := maxf(0.05, step)

	if length <= 0.0001:
		out = curve.get_baked_points()
		return out

	var d := 0.0
	while d < length:
		out.push_back(curve.sample_baked(d, true))
		d += sample_step
	if not curve.closed:
		out.push_back(curve.sample_baked(length, true))

	if out.size() < 2:
		out = curve.get_baked_points()

	return out


## Get the closest point on the 2D curve and project on the 3D curve.
## Expensive, takes 50% of all time!
func _get_closest_point_in_xz_plane(
		baked_2D: PackedVector2Array,
		baked_3D: PackedVector3Array,
		vertex3D: Vector3) -> Vector3:
	
	var vertex2D = Vector2(vertex3D.x, vertex3D.z)
	
	# Get the closest baked point in xz plane.
	var idx: int = 0
	var dist: float = INF
	var old_dist: float = INF
	for i in range(1, baked_2D.size() - 1):
		dist = vertex2D.distance_squared_to(baked_2D[i])
		if dist < old_dist:
			old_dist = dist
			idx = i
	
	# Check next segment.
	var next_seg: Vector2 = Geometry2D.get_closest_point_to_segment(
		vertex2D, baked_2D[idx], baked_2D[idx + 1]) 
	var next_dist: float = vertex2D.distance_squared_to(next_seg)
	
	# Check previews segment.
	var prev_seg: Vector2 = Geometry2D.get_closest_point_to_segment(
		vertex2D, baked_2D[idx], baked_2D[idx - 1])
	var prev_dist: float = vertex2D.distance_squared_to(prev_seg)
	
	 # Project the closest 2D segment on the 3D curve.
	var closest_point: Vector3 = Vector3.ZERO
	if next_dist < prev_dist:
		closest_point = Geometry3D.get_closest_points_between_segments(
		baked_3D[idx], baked_3D[idx + 1],
		# Vertical axis that cross the curve.
		Vector3(next_seg.x, -65536, next_seg.y), Vector3(next_seg.x, 65536, next_seg.y))[0]
	else:
		closest_point = Geometry3D.get_closest_points_between_segments(
		baked_3D[idx], baked_3D[idx - 1],
		# Vertical axis that cross the curve.
		Vector3(prev_seg.x, -65536, prev_seg.y), Vector3(prev_seg.x, 65536, prev_seg.y))[0]
	
	return closest_point


## There are two ways to triangularize a quad. To better follow the path, convex in y will be used.
func _update_quad_indices(idx: Vector2i, divs: int) -> void:
	var x: int = idx.x
	if (x + 1) > divs: return
	var z: int = idx.y
	if (z + 1) > divs: return
	# Make faces with two triangles.
	var row: int = x * (divs + 1)
	var next_row: int = row + divs + 1
	var index: int = 6 * (x * divs + z)
	 
	# There are two ways to triangularize a quad. Each one with one diagonal.
	# Getting the middle point of each diagonal.
	var diagonal_1: Vector3 = 0.5 * (vertex_grid[x][z] + vertex_grid[x + 1][z + 1])
	var diagonal_2: Vector3 = 0.5 * (vertex_grid[x + 1][z] + vertex_grid[x][z + 1])
	
	# The diagonal with the upper middle point will be convex in y.
	if diagonal_1.y >= diagonal_2.y:
		# First triangle vertices.
		indices[index] = z + row
		indices[index + 1] = z + row + 1
		indices[index + 2] = z + next_row + 1
		
		# Second triangle vertices.
		indices[index + 3] = z + row
		indices[index + 4] = z + next_row + 1
		indices[index + 5] = z + next_row
	else:
		# First triangle vertices.
		indices[index] = z + next_row
		indices[index + 1] = z + row
		indices[index + 2] = z + row + 1
		
		# Second triangle vertices.
		indices[index + 3] = z + next_row
		indices[index + 4] = z + row + 1
		indices[index + 5] = z + next_row + 1


# CSG meshes must be closed in Godot 4.4, this is the price for fast CSG.
# Making a cube bellow the tarrain.
func _close_shape(size: float, divs: int, surface_array: Array):
	# Add 4 bottom vertices for the floor of the box.
	var center: Vector3 = Vector3(0.5 * size, 0, 0.5 * size)
	var bottom_y := -size
	
	var floor_verts: PackedVector3Array = []
	floor_verts.resize(4)
	floor_verts[0] = Vector3(0, bottom_y, 0) - center # x0, z0
	floor_verts[1] = Vector3(0, bottom_y, size) - center # x0, z1
	floor_verts[2] = Vector3(size, bottom_y, 0 ) - center # x1, z0
	floor_verts[3] = Vector3(size, bottom_y, size) - center # x1, z1
	
	var vert_list: PackedVector3Array = surface_array[Mesh.ARRAY_VERTEX]
	var floor_idx_start: int = vert_list.size()
	vert_list.append_array(floor_verts)
	
	# Bottom floor triangles (facing -Y, so clockwise from top view: 0, 1, 3 then 0, 3, 2)
	indices.push_back(floor_idx_start + 0)
	indices.push_back(floor_idx_start + 2)
	indices.push_back(floor_idx_start + 1)
	indices.push_back(floor_idx_start + 1)
	indices.push_back(floor_idx_start + 2)
	indices.push_back(floor_idx_start + 3)
	
	# Side walls. We need to connect the terrain boundary to the bottom floor.
	var step := size / divs
	
	# Left Wall (x=0, facing -X)
	for i in range(divs):
		var top0 := i # x=0, z=i
		var top1 := i + 1 # x=0, z=i+1
		
		# Corresponding bottom points (interpolated along z edge x=0)
		var b0 := Vector3(0, bottom_y, i * step) - center
		var b1 := Vector3(0, bottom_y, (i + 1) * step) - center
		
		var idx_b0 := vert_list.size()
		vert_list.push_back(b0)
		var idx_b1 := vert_list.size()
		vert_list.push_back(b1)
		
		# Winding for -X: top0, idx_b0, top1  and  idx_b0, idx_b1, top1
		indices.push_back(top0)
		indices.push_back(idx_b0)
		indices.push_back(top1)
		indices.push_back(idx_b0)
		indices.push_back(idx_b1)
		indices.push_back(top1)

	# Right Wall (x=divs, facing +X)
	var x_offset := divs * (divs + 1)
	for i in range(divs):
		var top0 := x_offset + i
		var top1 := x_offset + i + 1
		
		var b0 := Vector3(size, bottom_y, i * step) - center
		var b1 := Vector3(size, bottom_y, (i + 1) * step) - center
		
		var idx_b0 := vert_list.size()
		vert_list.push_back(b0)
		var idx_b1 := vert_list.size()
		vert_list.push_back(b1)
		
		# Winding for +X: top0, top1, idx_b0  and  top1, idx_b1, idx_b0
		indices.push_back(top0)
		indices.push_back(top1)
		indices.push_back(idx_b0)
		indices.push_back(top1)
		indices.push_back(idx_b1)
		indices.push_back(idx_b0)

	# Up Wall (z=0, facing -Z)
	for i in range(divs):
		var top0 := i * (divs + 1) # x=i, z=0
		var top1 := (i + 1) * (divs + 1) # x=i+1, z=0
		
		var b0 := Vector3(i * step, bottom_y, 0) - center
		var b1 := Vector3((i + 1) * step, bottom_y, 0) - center
		
		var idx_b0 := vert_list.size()
		vert_list.push_back(b0)
		var idx_b1 := vert_list.size()
		vert_list.push_back(b1)
		
		# Winding for -Z: top0, top1, idx_b0  and  top1, idx_b1, idx_b0
		indices.push_back(top0)
		indices.push_back(top1)
		indices.push_back(idx_b0)
		indices.push_back(top1)
		indices.push_back(idx_b1)
		indices.push_back(idx_b0)

	# Down Wall (z=divs, facing +Z)
	for i in range(divs):
		var top0 := i * (divs + 1) + divs # x=i, z=divs
		var top1 := (i + 1) * (divs + 1) + divs # x=i+1, z=divs
		
		var b0 := Vector3(i * step, bottom_y, size) - center
		var b1 := Vector3((i + 1) * step, bottom_y, size) - center
		
		var idx_b0 := vert_list.size()
		vert_list.push_back(b0)
		var idx_b1 := vert_list.size()
		vert_list.push_back(b1)
		
		# Winding for +Z: top0, idx_b0, top1  and  idx_b0, idx_b1, top1
		indices.push_back(top0)
		indices.push_back(idx_b0)
		indices.push_back(top1)
		indices.push_back(idx_b0)
		indices.push_back(idx_b1)
		indices.push_back(top1)

	# Re-apply updated vertex list
	surface_array[Mesh.ARRAY_VERTEX] = vert_list
	surface_array[Mesh.ARRAY_INDEX] = indices
	
	# Simple UVs for new vertices.
	var new_count = vert_list.size() - floor_idx_start
	var new_uvs: PackedVector2Array = []
	new_uvs.resize(new_count)
	for i in range(new_count):
		new_uvs[i] = Vector2.ZERO
	
	var uvs_list: PackedVector2Array = surface_array[Mesh.ARRAY_TEX_UV]
	uvs_list.append_array(new_uvs)
	surface_array[Mesh.ARRAY_TEX_UV] = uvs_list
	surface_array[Mesh.ARRAY_TEX_UV2] = uvs_list

	# Recompute normals for the final closed mesh to keep winding-consistent lighting.
	surface_array[Mesh.ARRAY_NORMAL] = _compute_surface_normals(vert_list, indices)


func _compute_surface_normals(verts: PackedVector3Array, tri_indices: PackedInt32Array) -> PackedVector3Array:
	var out: PackedVector3Array = []
	out.resize(verts.size())
	for i in range(out.size()):
		out[i] = Vector3.ZERO

	var tri_count := tri_indices.size() - (tri_indices.size() % 3)
	for i in range(0, tri_count, 3):
		var ia := int(tri_indices[i])
		var ib := int(tri_indices[i + 1])
		var ic := int(tri_indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
			continue
		var n := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		if n.length_squared() <= 0.000000000001:
			continue
		out[ia] += n
		out[ib] += n
		out[ic] += n

	for i in range(out.size()):
		if out[i].length_squared() > 0.000000000001:
			out[i] = out[i].normalized()
		else:
			out[i] = Vector3.UP
	return out
