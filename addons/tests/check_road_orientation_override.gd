extends SceneTree

const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var road := ROAD.new()
	road.debug_generation_logs = false
	road.threaded_generation_enabled = false
	road.road_orientation_mode = 0
	var path := PROFILE.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(0,0,0))
	path.curve.add_point(Vector3(7,0,15))
	path.curve.add_point(Vector3(0,0,30))
	path.point_widths = PackedFloat32Array([6.0,6.0,6.0])
	path.road_orientation_override_enabled = true
	path.road_orientation_mode = 2
	path.road_bank_max_degrees = 8.0
	path.show_width_preview = false
	road.add_child(path)
	root.add_child(road)
	var banked := _max_height(road)
	path.road_orientation_mode = 1
	road.regenerate()
	var flat := _max_height(road)
	print("ROAD ORIENTATION OVERRIDE banked=",banked," flat=",flat)
	assert(banked > 0.05,"Path-level Bank Into Curve must affect generated asphalt")
	assert(flat < 0.001,"Path-level World Up must restore flat generated asphalt")
	quit()

func _max_height(road: Node3D) -> float:
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var result := 0.0
	for surface in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for point in vertices:
			result = maxf(result,absf(point.y))
	return result
