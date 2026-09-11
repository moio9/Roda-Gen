@tool
extends RefCounted
## Small code-native modules. +Z is longitudinal and y=0 is the road contact plane.

static func build(style: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Hard module edges: caps must not average their normals into the rail faces.
	tool.set_smooth_group(-1)
	match style:
		1:
			var section := PackedVector2Array([Vector2(0.02, 0.5), Vector2(0.10, 0.6), Vector2(0.03, 0.7), Vector2(0.10, 0.8), Vector2(0.02, 0.9), Vector2(-0.02, 0.9), Vector2(0.06, 0.8), Vector2(-0.01, 0.7), Vector2(0.06, 0.6), Vector2(-0.02, 0.5)])
			_extrude(tool, section, 4.0)
			_box(tool, Vector3(0.10, 0.82, 0.12), Vector3(-0.06, 0.41, 0.1))
			_box(tool, Vector3(0.10, 0.82, 0.12), Vector3(-0.06, 0.41, 2.1))
		2:
			var section := PackedVector2Array([Vector2(-0.325, 0), Vector2(-0.325, 0.18), Vector2(-0.14, 0.48), Vector2(-0.10, 0.90), Vector2(0.10, 0.90), Vector2(0.14, 0.48), Vector2(0.325, 0.18), Vector2(0.325, 0)])
			_extrude(tool, section, 4.0)
		3:
			_box(tool, Vector3(0.06, 0.94, 0.06), Vector3(0, 0.47, 0.04))
			_box(tool, Vector3(0.07, 0.07, 2.0), Vector3(0, 0.9, 1.0))
			_box(tool, Vector3(0.045, 0.045, 2.0), Vector3(0, 0.45, 1.0))
		_:
			return null
	tool.generate_normals()
	return tool.commit()


static func _box(tool: SurfaceTool, size: Vector3, position: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		tool.set_uv(uvs[index])
		tool.add_vertex(vertices[index] + position)


static func _extrude(tool: SurfaceTool, section: PackedVector2Array, length: float) -> void:
	var signed_area := 0.0
	for i in range(section.size()):
		signed_area += section[i].cross(section[(i + 1) % section.size()])
	for i in range(section.size()):
		var a := section[i]
		var b := section[(i + 1) % section.size()]
		var edge := b - a
		var outward := Vector3(edge.y, -edge.x, 0) * (1.0 if signed_area > 0 else -1.0)
		var p0 := Vector3(a.x, a.y, 0)
		var p1 := Vector3(b.x, b.y, 0)
		var p2 := Vector3(a.x, a.y, length)
		var p3 := Vector3(b.x, b.y, length)
		_triangle(tool, p0, p1, p2, outward)
		_triangle(tool, p2, p1, p3, outward)
	var cap := Geometry2D.triangulate_polygon(section)
	for i in range(0, cap.size(), 3):
		for z in [0.0, length]:
			var a := section[cap[i]]
			var b := section[cap[i + 1]]
			var c := section[cap[i + 2]]
			_triangle(tool, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3.FORWARD if z == 0.0 else Vector3.BACK)


static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var vertices := [a, c, b] if (b - a).cross(c - a).dot(outward) > 0.0 else [a, b, c]
	for point: Vector3 in vertices:
		tool.set_uv(Vector2(point.z, point.y))
		tool.add_vertex(point)
