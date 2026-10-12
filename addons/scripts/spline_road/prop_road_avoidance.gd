@tool
extends RefCounted
## Reject complete placements using the transformed base of the model bounds.
const QUERY = preload("./prop_road_edge_query.gd")
var _queries: Array = []
var _bounds := AABB()
var _has_bounds := false
var _signature := ""
var rejected := 0


func sources(props: Node3D) -> Array[Node3D]:
	var roads: Array[Node3D] = []
	if not props.road_network_source.is_empty():
		var road := props.get_node_or_null(props.road_network_source) as Node3D
		if road != null and road.has_method("get_terrain_surface_data"):
			roads.append(road)
		return roads
	for path in props._resolve_paths():
		var ancestor: Node = path.get_parent()
		while ancestor != null:
			if ancestor is Node3D and ancestor.has_method("get_terrain_surface_data"):
				if not roads.has(ancestor):
					roads.append(ancestor)
				break
			ancestor = ancestor.get_parent()
	return roads


func signature(props: Node3D) -> String:
	var parts: Array = []
	for road in sources(props):
		parts.append([road.get_instance_id(), road.global_transform,
			road.get_terrain_surface_revision() if road.has_method("get_terrain_surface_revision") else -1,
			road.is_road_generation_pending() if road.has_method("is_road_generation_pending") else false])
	return str(parts)


func changed(props: Node3D) -> bool:
	return signature(props) != _signature


func pending(props: Node3D) -> bool:
	for road in sources(props):
		if road.has_method("is_road_generation_pending") and road.is_road_generation_pending():
			return true
	return false


func clear(props: Node3D) -> void:
	rejected = 0
	_has_bounds = false
	_queries.clear()
	_signature = signature(props)


func prepare(props: Node3D) -> void:
	clear(props)
	if not props.avoid_road_surface:
		return
	for road in sources(props):
		var query := QUERY.new()
		query.configure(road, true)
		_queries.append(query)
	if props.item_scene != null:
		var model: Node = props.item_scene.instantiate()
		if model is Node3D:
			_measure(model, Transform3D.IDENTITY)
		model.free()
	elif props.item_mesh != null:
		_bounds = props.item_mesh.get_aabb()
		_has_bounds = true


func _measure(node: Node, local: Transform3D) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = local * node.mesh.get_aabb()
		_bounds = _bounds.merge(box) if _has_bounds else box
		_has_bounds = true
	for child in node.get_children():
		_measure(child, local * child.transform if child is Node3D else local)


func blocked(world: Transform3D, height_tolerance: float) -> bool:
	if not _has_bounds:
		return false
	var a := _bounds.position
	var b := _bounds.end
	var corners := world * PackedVector3Array([
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z),
		Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)])
	for query in _queries:
		if query.overlaps_footprint(corners, height_tolerance):
			rejected += 1
			return true
	return false
