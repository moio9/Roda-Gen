@tool
extends "../../scripts/spline_road/terrain_topology_builder.gd"
## The base terrain samples unjoined path edges. Clip both its collars and its
## triangulated surface against the final road so joined corners stay clear.
const CUT = preload("../../scripts/spline_road/terrain_road_mesh_cut.gd")
var _road_cut := CUT.new()

func regenerate() -> void:
	if not is_terrain_generation_pending():
		var road := get_node_or_null(road_network_source)
		var output: MeshInstance3D = road.get_node_or_null("GeneratedSplineRoadWelded") if road != null else null
		_road_cut.prepare(output, global_transform.affine_inverse())
	super.regenerate()

func _add_terrain_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		a2: Vector2, b2: Vector2, c2: Vector2) -> void:
	for triangle in _road_cut.subtract(a, b, c):
		super._add_terrain_triangle(st, triangle[0], triangle[1], triangle[2],
			Vector2(triangle[0].x, triangle[0].z), Vector2(triangle[1].x, triangle[1].z),
			Vector2(triangle[2].x, triangle[2].z))

func _add_oriented_topology_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		a2: Vector2, b2: Vector2, c2: Vector2) -> int:
	var count := 0
	for triangle in _road_cut.subtract(a, b, c):
		count += super._add_oriented_topology_triangle(st, triangle[0], triangle[1], triangle[2],
			Vector2(triangle[0].x, triangle[0].z), Vector2(triangle[1].x, triangle[1].z),
			Vector2(triangle[2].x, triangle[2].z))
	return count
