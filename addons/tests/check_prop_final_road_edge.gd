extends SceneTree

const PROPS = preload("../scripts/spline_road/spline_prop_array.gd")
const QUERY = preload("../scripts/spline_road/prop_road_edge_query.gd")
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")
var checks := 0
var failed := false

class Road extends Node3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var revision := 1

	func get_terrain_surface_data() -> Dictionary:
		return {"vertices": vertices, "indices": indices}

	func get_terrain_surface_revision() -> int:
		return revision

	func quad(x0: float, x1: float, y0: float, y1: float, z0 := 0.0, z1 := -20.0) -> void:
		var base := vertices.size()
		vertices.append_array(PackedVector3Array([
			Vector3(x0, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y0, z1), Vector3(x1, y1, z1)]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := Road.new()
	road.name = "Road"
	road.quad(-3, 3, 0, 0)
	road.quad(3, 7, 0, 0.4)
	road.quad(10, 15, 0, 0)
	road.quad(-3, 20, 5, 5)
	world.add_child(road)
	var query := QUERY.new()
	query.configure(road)
	var hit: Dictionary = query.edge_at(Vector3(0, 0, -10), Vector3.RIGHT)
	_check(not hit.is_empty() and hit.position.distance_to(Vector3(7, 0.4, -10)) < 0.0001,
		"Follows joined outer edge, ignoring separate road and overhead bridge")
	_check(hit.up.distance_to(Vector3(-0.1, 1, 0).normalized()) < 0.0001, "Uses final bank normal")
	hit = query.edge_at(Vector3(0, 5, -10), Vector3.RIGHT)
	_check(not hit.is_empty() and hit.position.distance_to(Vector3(20, 5, -10)) < 0.0001,
		"Bridge query stays on the bridge level")
	hit = query.edge_at(Vector3(0, 0, -10), Vector3.LEFT)
	_check(not hit.is_empty() and hit.position.distance_to(Vector3(-3, 0, -10)) < 0.0001, "Opposite edge remains on source side")
	_check(query.edge_at(Vector3(0, 20, -10), Vector3.RIGHT).is_empty(), "No false match far above surface")
	_check(query.overlaps_footprint(PackedVector3Array([
		Vector3(2, 0, -5), Vector3(4, 0, -5), Vector3(4, 0, -7), Vector3(2, 0, -7)])), "Rejects fence through merged asphalt")
	_check(not query.overlaps_footprint(PackedVector3Array([
		Vector3(8, 0.5, -5), Vector3(9, 0.5, -5), Vector3(9, 0.5, -7), Vector3(8, 0.5, -7)])), "Allows fence under a separate higher road")

	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, -20))
	world.add_child(path)
	var props := PROPS.new()
	props.name = "Fence"
	props.source_paths = [NodePath("../Path")]
	props.road_network_source = NodePath("../Road")
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.4, 1, 2)
	props.custom_position = Vector3(0, 0.5, 0)
	props.fit_segments_to_path = true
	props.placement_mode = 1
	props.spacing = 2
	props.outward_offset = 0.25
	props.avoid_intersections = false
	world.add_child(props)
	var generated := props.get_node("GeneratedSplineProps")
	_check(generated.get_child_count() == 10, "All modules follow the continuous joined edge")
	for piece: MeshInstance3D in generated.get_children():
		var bounds := piece.global_transform * piece.mesh.get_aabb()
		_check(bounds.position.x > 7.0, "Full tilted fence clears the joined road")
		var inner_foot := piece.global_transform * Vector3(-0.2, -0.5, 0)
		_check(absf(inner_foot.x - (7.0 + 0.25 / sqrt(1.01))) < 0.0001, "Clearance measured at the foot along the banked surface")
	var old_signature: String = props._build_signature()
	road.vertices.clear()
	road.indices.clear()
	road.quad(-3, 9, 0, 0)
	road.revision += 1
	_check(props._build_signature() != old_signature, "Final-road revision invalidates editor generation")
	props._process(0.0)
	generated = props.get_node("GeneratedSplineProps")
	for piece: MeshInstance3D in generated.get_children():
		var bounds := piece.global_transform * piece.mesh.get_aabb()
		_check(is_equal_approx(bounds.position.x, 9.25), "Runtime road edit moves the inner face to the new edge + clearance")
	_check(not props._segment_fitter.road_changed(props), "Road revision consumed without repeated rebuild")
	props.follow_generated_road_edge = false
	props.regenerate()
	for piece: MeshInstance3D in props.get_node("GeneratedSplineProps").get_children():
		_check(is_equal_approx(piece.global_position.x, 3.25), "Opt-out preserves authored edge placement")
	props.follow_generated_road_edge = true
	props.edge_uses_total_road_width = false
	props.regenerate()
	for piece: MeshInstance3D in props.get_node("GeneratedSplineProps").get_children():
		_check(is_equal_approx(piece.global_position.x, 3.25), "Lane-only placement remains explicit")
	props.edge_uses_total_road_width = true
	road.quad(9, 13, 0, 0, -9, -11)
	road.revision += 1
	props.regenerate()
	_check(props.get_node("GeneratedSplineProps").get_child_count() == 8,
		"Rigid chords crossing a side-junction opening are omitted")
	road.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(30, 4, -25))
	query.configure(road)
	hit = query.edge_at(road.global_transform * Vector3(0, 0, -5), road.global_basis * Vector3.RIGHT)
	_check(not hit.is_empty() and hit.position.distance_to(road.global_transform * Vector3(9, 0, -5)) < 0.0001,
		"Road surface and ray query share world coordinates")
	var actual_road := ROAD.new()
	actual_road.road_orientation_mode = 0
	world.add_child(actual_road)
	var profile := PROFILE.new()
	profile.curve = path.curve.duplicate()
	profile.curve.set_point_tilt(0, 0.4)
	profile.curve.set_point_tilt(1, 0.4)
	profile.road_orientation_override_enabled = true
	profile.road_orientation_mode = 1
	world.add_child(profile)
	var frame: Dictionary = actual_road.get_path_surface_frame(profile, 5)
	_check(frame.up.distance_to(Vector3.UP) < 0.0001, "Prop frame honors source path orientation override")
	profile.road_orientation_override_enabled = false
	frame = actual_road.get_path_surface_frame(profile, 5)
	_check(frame.up.angle_to(Vector3.UP) > 0.39, "Road Curve Up frame retains authored tilt without override")
	world.free()
	if not failed:
		print("PROP FINAL ROAD EDGE PASS checks=", checks)
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)
