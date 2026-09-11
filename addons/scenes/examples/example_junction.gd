@tool
extends MeshInstance3D
## Explicit example connector, separate from the generic endpoint weld.
@export_enum("Urban", "Highway") var layout := 0
@export var asphalt: Material
@export var sidewalk: Material
@export var paint: Material
@export_tool_button("Rebuild Connector") var rebuild_action := rebuild
var _surfaces: Dictionary = {}

func _surface(material: Material) -> SurfaceTool:
	if not _surfaces.has(material):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(material)
		_surfaces[material] = tool
	return _surfaces[material]

func _ready() -> void:
	rebuild()

func _polygon(points: PackedVector2Array, height: float, material: Material) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	var surface := _surface(material)
	for t in range(0, indices.size(), 3):
		var a := Vector3(points[indices[t]].x, height, points[indices[t]].y)
		var b := Vector3(points[indices[t + 1]].x, height, points[indices[t + 1]].y)
		var c := Vector3(points[indices[t + 2]].x, height, points[indices[t + 2]].y)
		# Godot front faces use clockwise winding as viewed from above.
		if (b - a).cross(c - a).y > 0:
			var swap := b
			b = c
			c = swap
		for vertex in [a, b, c]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(vertex.x, vertex.z))
			surface.add_vertex(vertex)

func _line(a: Vector2, b: Vector2, width := 0.12) -> void:
	var normal := (b - a).normalized().orthogonal() * width * 0.5
	_polygon(PackedVector2Array([a - normal, b - normal, b + normal, a + normal]), 0.025, paint)

func rebuild() -> void:
	mesh = ArrayMesh.new()
	_surfaces.clear()
	if layout == 0:
		_urban()
	else:
		_highway()
	for surface in _surfaces.values():
		surface.commit(mesh)
	_surfaces.clear()

func _urban() -> void:
	var outline := PackedVector2Array()
	for quadrant in range(4):
		var angle := quadrant * PI * 0.5
		var inner := PackedVector2Array([Vector2(3.75, -14)])
		for step in range(17):
			var theta := PI - step * PI / 32.0
			inner.append(Vector2(9.75, -9.75) + Vector2(cos(theta), sin(theta)) * 6.0)
		inner.append(Vector2(14, -3.75))
		var corner := inner.duplicate()
		corner.append(Vector2(14, -5.55))
		for step in range(17):
			var theta := PI * 0.5 + step * PI / 32.0
			corner.append(Vector2(9.75, -9.75) + Vector2(cos(theta), sin(theta)) * 4.2)
		corner.append(Vector2(5.55, -14))
		for i in range(inner.size()):
			outline.append(inner[i].rotated(angle))
		for i in range(corner.size()):
			corner[i] = corner[i].rotated(angle)
		_polygon(corner, 0.12, sidewalk)
		# Vertical curb faces along the curved inner edge.
		var curb := _surface(sidewalk)
		for i in range(inner.size() - 1):
			var a := inner[i].rotated(angle)
			var b := inner[i + 1].rotated(angle)
			var direction := (b - a).normalized().orthogonal()
			for vertex in [Vector3(a.x, 0, a.y), Vector3(a.x, 0.12, a.y), Vector3(b.x, 0.12, b.y),
					Vector3(a.x, 0, a.y), Vector3(b.x, 0.12, b.y), Vector3(b.x, 0, b.y)]:
				curb.set_normal(Vector3(direction.x, 0, direction.y))
				curb.set_uv(Vector2(vertex.x, vertex.z))
				curb.add_vertex(vertex)
		# Crossing lies inside the connector, before the unmarked central area.
		for stripe in range(7):
			var x := -3.0 + stripe * 0.9
			var rectangle := PackedVector2Array([Vector2(x, -13), Vector2(x + 0.45, -13),
				Vector2(x + 0.45, -10.5), Vector2(x, -10.5)])
			for i in range(rectangle.size()):
				rectangle[i] = rectangle[i].rotated(angle)
			_polygon(rectangle, 0.025, paint)
	_polygon(outline, 0.0, asphalt)

func _highway() -> void:
	# Main carriageway remains straight. Ramp arrives tangentially at x=7.5,z=20.
	# 80 m of full-width acceleration lane, followed by an 80 m taper.
	_polygon(PackedVector2Array([Vector2(7.5, 20), Vector2(11.25, 20),
		Vector2(11.25, 100), Vector2(7.5, 180)]), 0.0, asphalt)
	_line(Vector2(11.25, 20), Vector2(11.25, 100))
	_line(Vector2(11.25, 100), Vector2(7.5, 180))
	_line(Vector2(7.5, -190), Vector2(7.5, 20))
	_line(Vector2(7.5, 180), Vector2(7.5, 225))
	_line(Vector2(0, -190), Vector2(0, 225))
	for z in range(23, 174, 12):
		_line(Vector2(7.5, z), Vector2(7.5, minf(z + 5, 176)))
	for x in [-18.0, -25.5]:
		_line(Vector2(x, -190), Vector2(x, 225))
	var ramp := get_node("../Road/EntryRamp") as Path3D
	var length := ramp.curve.get_baked_length()
	var previous_left := Vector2.ZERO
	var previous_right := Vector2.ZERO
	var steps := ceili(length)
	for i in range(steps + 1):
		var distance := length * i / steps
		var center := ramp.curve.sample_baked(distance)
		var direction := (ramp.curve.sample_baked(minf(length, distance + 0.1)) -
			ramp.curve.sample_baked(maxf(0.0, distance - 0.1))).normalized()
		var right := Vector3.UP.cross(direction).normalized()
		var a := Vector2(center.x, center.z)
		var b := a + Vector2(right.x, right.z) * 3.75
		if i > 0:
			_line(previous_left, a)
			_line(previous_right, b)
		previous_left = a
		previous_right = b
