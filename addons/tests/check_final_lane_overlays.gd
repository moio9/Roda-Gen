extends SceneTree
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
var failed := false
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var road := ROAD.new()
	road.generate_in_editor = false
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.road_orientation_mode = 1
	road.sample_step = 2.0
	road.incremental_generation_enabled = true
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color.BLUE
	road.left_lane_material_overrides.assign([red])
	road.right_lane_material_overrides.assign([blue])
	root.add_child(road)
	for x in [0.0, 2.0]:
		var path := PROFILE.new()
		path.show_width_preview = false
		path.curve = Curve3D.new()
		path.curve.add_point(Vector3(x, 0, 0))
		path.curve.add_point(Vector3(x, 0, -20))
		road.add_child(path)
		road.source_paths.append(road.get_path_to(path))
	_set_surface(road, 0.2)
	_check_mesh(road, 0.2, red, blue)
	_set_surface(road, 0.3)
	_check_mesh(road, 0.3, red, blue)
	_check(road.get_lane_overlay_stats().rows_rebuilt == 0, "Final road edit projects cached source rows onto new heights")
	road.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(-1.2, 1.0, 1.3)), Vector3(11, 3, -8))
	_check_mesh(road, 0.3, red, blue)
	road.invert_faces = false
	_check_mesh(road, 0.3, red, blue)
	road._terrain_surface_data.lane_indices = PackedInt32Array()
	_check(road._build_lane_material_overlay_mesh().get_surface_count() == 0, "An empty final asphalt surface emits no overlays")
	road.free()
	# Real generation must expose asphalt-only indices in single/chunk output.
	for mode in [0, 1]:
		var actual := ROAD.new()
		actual.generate_in_editor = false
		actual.threaded_generation_enabled = false
		actual.debug_generation_logs = false
		actual.output_mode = mode
		actual.shoulder_left_width = 1.0
		actual.left_lane_material_overrides.assign([red])
		var path := PROFILE.new()
		path.show_width_preview = false
		path.shoulder_left_width = 1.0
		path.curve = Curve3D.new()
		path.curve.add_point(Vector3.ZERO)
		path.curve.add_point(Vector3(0, 0, -10))
		actual.add_child(path)
		root.add_child(actual)
		actual.regenerate()
		var surface: Dictionary = actual.get_terrain_surface_data()
		_check(surface.has("lane_indices") and surface.lane_indices.size() < surface.indices.size(), "Snapshot distinguishes asphalt from shoulders, output mode %d" % mode)
		_check(actual.get_node("GeneratedLaneMaterialOverlays").mesh.get_surface_count() == 1, "Generation assigns projected overlay, output mode %d" % mode)
		actual.free()
	print("FINAL LANE OVERLAYS %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)

func _set_surface(road: Node, height: float) -> void:
	var vertices := PackedVector3Array([
		Vector3(-2, height - 0.2, 0), Vector3(4, height + 0.4, 0),
		Vector3(-2, height - 0.2, -20), Vector3(4, height + 0.4, -20),
		Vector3(-2, 5, 0), Vector3(4, 5, 0), Vector3(-2, 5, -20), Vector3(4, 5, -20),
		Vector3(-8, 0, 0), Vector3(-8, 0, -20)])
	var asphalt := PackedInt32Array([0, 1, 2, 1, 3, 2, 4, 5, 6, 5, 7, 6])
	road._terrain_surface_data = {"vertices": vertices, "lane_indices": asphalt, "indices": asphalt + PackedInt32Array([8, 0, 9, 0, 2, 9])}

func _check_mesh(road: Node3D, height: float, red: Material, blue: Material) -> void:
	var mesh: ArrayMesh = road._build_lane_material_overlay_mesh()
	_check(mesh.get_surface_count() == 2 and mesh.surface_get_material(0) == red and mesh.surface_get_material(1) == blue, "Material routing retained")
	var total_area := 0.0
	var max_height_error := 0.0
	var max_uv_error := 0.0
	var bad_ownership := false
	var outside := false
	var bad_winding := false
	var world_normal := (road.global_basis.inverse().transposed() * Vector3(-0.1, 1, 0)).normalized()
	for surface in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in range(0, ids.size(), 3):
			var triangle := PackedVector3Array()
			for k in range(3):
				var index := ids[i + k]
				var p: Vector3 = road.to_local(road.to_global(v[index]) - world_normal * road.lane_material_overlay_lift)
				triangle.append(p)
				max_height_error = maxf(max_height_error, absf(p.y - height - 0.1 * p.x))
				max_uv_error = maxf(max_uv_error, absf(uv[index].y + p.z * road.uv_length_scale))
				outside = outside or p.x < -2.0001 or p.x > 4.0001 or p.z < -20.0001 or p.z > 0.0001
			var cross_ := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
			total_area += absf(cross_.y) * 0.5
			var centroid := (triangle[0] + triangle[1] + triangle[2]) / 3.0
			var first: Path3D = road._resolve_paths()[0]
			var frame: Dictionary = road.get_path_surface_frame(first, -centroid.z)
			var lateral: float = (road.to_global(centroid) - frame.center).dot(frame.right)
			if absf(cross_.y) > 0.00001 and absf(lateral) < 2.99:
				bad_ownership = bad_ownership or ((surface == 1) != (lateral > 0.0))
			var world_cross := (road.global_basis * (triangle[1] - triangle[0])).cross(road.global_basis * (triangle[2] - triangle[0]))
			bad_winding = bad_winding or ((world_cross.dot(world_normal) > 0) == road.invert_faces)
	_check(absf(total_area - 120.0) < 0.001, "Each asphalt region covered once; no duplicate overlapping strips (area=%f)" % total_area)
	_check(max_height_error < 0.0001, "Overlay follows final bank/height and ignores overhead deck (error=%f)" % max_height_error)
	_check(max_uv_error < 0.0001, "Longitudinal texture scale survives clipping")
	_check(not outside, "No overlay outside final asphalt or on shoulder")
	_check(not bad_ownership, "First source owns overlaps even when next path's opposite side has another material")
	_check(not bad_winding, "Winding respects invert_faces under transformed parents")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
