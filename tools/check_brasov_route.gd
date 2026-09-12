extends "res://tools/check_poiana_brasov.gd"
const SCENE_PATH := "res://addons/scenes/examples/poiana_brasov_centru.tscn"

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "Missing extended route scene")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	var route: Path3D = scene.get_node("Road/DrumulPoienii")
	var curve := route.curve
	var length := curve.get_baked_length()
	_check(length > 11500 and length < 12200, "Mapped route length changed unexpectedly")
	_check(curve.get_point_position(curve.point_count-1).distance_to(Vector3(-45,65,100)) < 0.01, "Route no longer meets Poiana junction")
	_check(scene.get_meta("requested_endpoint_lat_lon").distance_to(Vector2(45.64564291258261,25.589722446492228)) < 0.00001, "Requested destination changed")
	var ring: Curve3D = scene.get_node("Road/SensGiratoriuCentru").curve
	_check(ring.get_point_position(0).distance_to(ring.get_point_position(ring.point_count-1)) < 0.001, "Roundabout is not closed")
	_check(ring.get_closest_point(curve.get_point_position(0)).distance_to(curve.get_point_position(0)) < 0.05, "Approach does not meet roundabout")
	var max_grade := 0.0
	for d in range(0,int(length)-3,3):
		var a := curve.sample_baked(d)
		var b := curve.sample_baked(d+3)
		var horizontal := Vector2(b.x-a.x,b.z-a.z).length()
		if horizontal > 0.0001:
			max_grade = maxf(max_grade,absf(b.y-a.y)/horizontal)
	_check(max_grade < 0.15, "Route contains an excessive local vertical grade")
	# Saved outputs must be usable before any tool script runs.
	for path in ["Road/GeneratedSplineRoadWelded", "Road/GeneratedRoadMarkings", "Terrain/GeneratedTopologyTerrain"]:
		var output: MeshInstance3D = scene.get_node(path)
		_check(output.mesh != null and output.mesh.get_surface_count() > 0, "Missing saved output: " + path)
		for surface in range(output.mesh.get_surface_count()):
			var vertices: PackedVector3Array = output.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in vertices:
				if not v.is_finite():
					_check(false, "Nonfinite generated geometry: " + path)
					break
	var island: MeshInstance3D = scene.get_node("BrasovCentru/InsulaSens")
	var ground: Mesh = scene.get_node("Terrain/GeneratedTopologyTerrain").mesh
	var island_ground_y := _mesh_height(ground,Vector2(island.position.x,island.position.z))
	_check(is_finite(island_ground_y) and absf(island_ground_y-(island.position.y-0.08)) < 0.1,
		"Roundabout island terrain must be flat beneath the island")
	var road := scene.get_node("Road")
	_check(road.road_orientation_mode == 1, "Mapped road must use World Up")
	_check(road.output_generate_collision, "Road collision is disabled")
	_check(scene.has_node("Road/GeneratedSplineRoadWelded/StaticBody3D"), "Road collision must survive scene serialization")
	_check(not scene.get_node("Terrain").generate_in_editor, "Large embedded terrain should not rebuild merely when opening the scene")
	root.add_child(scene)
	for frame in range(4):
		await physics_frame
	# Float32 polygon clipping at coordinates 5 km from the origin leaves
	# millimetre boundary slivers; retain a small absolute area tolerance.
	_check_junction_overlap(scene,0.05)
	var loop_length := ring.get_baked_length()
	var seam := ring.sample_baked(0,true)
	var after := ring.sample_baked(0.1,true)
	var before := ring.sample_baked(loop_length-0.1,true)
	var first_frame: Dictionary = road._resolve_road_frame(ring,Transform3D.IDENTITY,0,loop_length,seam,seam,after)
	var last_frame: Dictionary = road._resolve_road_frame(ring,Transform3D.IDENTITY,loop_length,loop_length,seam,before,seam)
	var ground_builder := scene.get_node("Terrain")
	var ground_first: Dictionary = ground_builder._resolve_road_frame(ring,Transform3D.IDENTITY,Transform3D.IDENTITY,0,loop_length,seam,seam,after)
	var ground_last: Dictionary = ground_builder._resolve_road_frame(ring,Transform3D.IDENTITY,Transform3D.IDENTITY,loop_length,loop_length,seam,before,seam)
	_check(first_frame.right.distance_to(last_frame.right) < 0.00001,"Road loop cross sections do not meet")
	_check(ground_first.right.distance_to(ground_last.right) < 0.00001 and ground_first.right.distance_to(first_frame.right) < 0.00001,
		"Terrain loop seam must match the road")
	var ray_misses := 0
	for d in range(40,int(length)-40,73):
		var p := route.to_global(curve.sample_baked(d))
		var query := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*2)
		if scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			ray_misses += 1
	for d in range(1,40,2):
		var p := route.to_global(curve.sample_baked(d))
		var query := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*2)
		if scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			ray_misses += 1
	for d in range(0,int(ring.get_baked_length()),5):
		var p := ring.sample_baked(d)
		var query := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*2)
		if scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			ray_misses += 1
	_check(ray_misses == 0, "Road/roundabout collision has gaps along the centerline")
	_check(scene.get_node("Road/GeneratedRoadMarkings").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Road paint must not cast shadows")
	var camera := scene.get_node("Camera")
	camera.touring = true
	camera.distance = length-60
	camera._process(0.1)
	_check(camera.position.is_finite() and camera.focus.is_finite(), "Route tour produced invalid camera transform")
	camera.touring = false
	camera.transform = camera.initial_transform
	camera.focus = camera.initial_focus
	print("BRASOV CHECK ","OK" if failures == 0 else "FAILED", " failures=",failures,
		" length_m=",length," max_grade_percent=",max_grade*100," collision_misses=",ray_misses,
		" trees=",scene.get_node("Forest").tree_placements.size())
	scene.free()
	quit(0 if failures == 0 else 1)

func _mesh_height(mesh: Mesh, p: Vector2) -> float:
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for i in range(0,ids.size() if not ids.is_empty() else v.size(),3):
			var a := v[ids[i] if not ids.is_empty() else i]
			var b := v[ids[i+1] if not ids.is_empty() else i+1]
			var c := v[ids[i+2] if not ids.is_empty() else i+2]
			var aa := Vector2(a.x,a.z)
			var ab := Vector2(b.x-a.x,b.z-a.z)
			var ac := Vector2(c.x-a.x,c.z-a.z)
			var denominator := ab.cross(ac)
			if absf(denominator) < 0.00001:
				continue
			var u := (p-aa).cross(ac)/denominator
			var w := ab.cross(p-aa)/denominator
			if u >= -0.0001 and w >= -0.0001 and u+w <= 1.0001:
				return a.y*(1-u-w)+b.y*u+c.y*w
	return NAN
