extends SceneTree
const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
var checks := 0
var failed := false

class Surface extends Node3D:
	var revision := 1
	var pending := false
	var data: Dictionary = {}
	func get_terrain_surface_data() -> Dictionary:
		return data
	func get_terrain_surface_revision() -> int:
		return revision
	func is_road_generation_pending() -> bool:
		return pending
	func strip(x0 := -3.0, x1 := 3.0, y := 0.0) -> void:
		data = {"vertices": PackedVector3Array([Vector3(x0,y,-9), Vector3(x1,y,-9), Vector3(x0,y,-11), Vector3(x1,y,-11)]),
			"indices": PackedInt32Array([0,1,2,1,3,2]), "lane_indices": PackedInt32Array([0,1,2,1,3,2])}
		revision += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := Surface.new()
	road.name = "Road"
	road.strip()
	world.add_child(road)
	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0,0,-20))
	road.add_child(path)
	var props := PROPS.new()
	props.name = "Props"
	props.source_paths = [NodePath("../Road/Path")]
	props.avoid_intersections = false
	props.spacing = 4.0
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(1,1,4)
	world.add_child(props)
	_check(_count(props) == 6, "Default keeps all placements")
	props.avoid_road_surface = true
	props.regenerate()
	_check(_count(props) == 4, "Full footprints detect crossing even when pivots are outside asphalt")
	_check(props.get_placement_rebuild_stats().road_surface_rejected == 2, "Reports skipped placements")
	props.regenerate()
	_check(_count(props) == 4, "Repeated regeneration retains exclusion")
	props.avoid_road_surface = false
	props.regenerate()
	_check(_count(props) == 6, "Opt-out restores every placement")
	props.avoid_road_surface = true
	props.render_mode = 1
	props.regenerate()
	_check(_count(props) == 4, "MultiMesh uses the same exclusion")
	props.render_mode = 0
	props.fit_segments_to_path = true
	props.follow_generated_road_edge = false
	props.regenerate()
	_check(_count(props) == 4, "Connected fence skips only its crossing segment")
	props.fit_segments_to_path = false
	props.custom_position = Vector3(5,0,0)
	props.regenerate()
	_check(_count(props) == 6, "Custom position moves model clear of asphalt")
	props.custom_position = Vector3.ZERO
	road.strip(-3,3,5)
	props._process(0.0)
	_check(_count(props) == 6, "Overhead road does not remove ground-level props; revision refreshes runtime")
	road.strip()
	road.data.lane_indices = PackedInt32Array()
	props.regenerate()
	_check(_count(props) == 6, "Shoulder-only triangles do not count as asphalt")
	road.strip()
	road.pending = true
	props.regenerate()
	_check(props._road_avoidance_pending and _count(props) == 6, "Pending final road preserves previous output")
	road.pending = false
	props._process(0.0)
	_check(not props._road_avoidance_pending and _count(props) == 4, "Deferred generation consumes completed asphalt")
	_check(not props._road_avoidance.changed(props), "Consumed road revision stays idle")
	world.transform = Transform3D(Basis(Vector3.UP,0.5).scaled(Vector3(-1.2,1,0.8)),Vector3(10,2,7))
	props.regenerate()
	_check(_count(props) == 4, "Mirrored, rotated and scaled parents preserve world-space exclusion")
	world.transform = Transform3D.IDENTITY
	var model := Node3D.new()
	model.position = Vector3(100,0,0)
	var child := MeshInstance3D.new()
	child.mesh = props.item_mesh
	child.position = Vector3(5,0,0)
	model.add_child(child)
	child.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	props.item_scene = packed
	props.custom_position = Vector3(-5,0,0)
	props.regenerate()
	_check(_count(props) == 4, "Scene child transforms and custom offset determine model footprint; root transform replaced")
	props.item_scene = null
	props.custom_position = Vector3.ZERO
	props.road_network_source = NodePath("../Missing")
	props.regenerate()
	_check(_count(props) == 6 and not props._get_configuration_warnings().is_empty(), "Missing road preserves placements with Inspector warning")
	world.free()
	await _real_road()
	print("PROP ROAD AVOIDANCE %s checks=%d" % ["FAIL" if failed else "PASS",checks])
	quit(1 if failed else 0)

func _real_road() -> void:
	var road := ROAD.new()
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	var path := Path3D.new()
	path.name = "Route"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0,0,-20))
	road.add_child(path)
	root.add_child(road)
	var props := PROPS.new()
	props.source_paths = [NodePath("../Route")]
	props.road_network_source = NodePath("..")
	props.spacing = 4.0
	props.item_mesh = BoxMesh.new()
	props.avoid_intersections = false
	props.avoid_road_surface = true
	road.add_child(props)
	_check(_count(props) == 0, "Real final asphalt excludes center placements")
	props.custom_position = Vector3(8,0,0)
	props.regenerate()
	_check(_count(props) == 6, "Real source allows outside placements")
	props.custom_position = Vector3.ZERO
	props.regenerate()
	_check(_count(props) == 0, "Placement reuse never replays stale accepted footprints")
	for mode in [0,1]:
		road.output_mode = mode
		road.regenerate()
		props.regenerate()
		_check(_count(props) == 0, "Exclusion works in road output mode %d" % mode)
	road.free()

func _count(props: Node) -> int:
	var output := props.get_node_or_null("GeneratedSplineProps")
	var total := 0
	if output != null:
		for child in output.get_children():
			total += child.multimesh.instance_count if child is MultiMeshInstance3D else 1
	return total

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
