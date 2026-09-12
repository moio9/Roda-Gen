extends "res://tools/build_poiana_brasov.gd"
## Builds a separate map-based 1:1 approach, retaining the stylized resort.
const ROUTE_OUTPUT := "res://addons/scenes/examples/poiana_brasov_centru.tscn"
const DATA_PATH := "res://tools/data/poiana_brasov_route.json"
var route_data: Dictionary
var top_geo: Dictionary
var main_path: Path3D
var city_height := 0.0
var route_curve: Curve3D
var smooth_heights := PackedFloat64Array()

func _run() -> void:
	rng.seed = 12092026
	route_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	top_geo = route_data.points[0]
	_prepare_heights()
	scene = (load("res://addons/scenes/examples/poiana_brasov.tscn") as PackedScene).instantiate()
	scene.name = "PoianaBrasovCentru"
	scene.set_script(null)
	road = scene.get_node("Road")
	terrain = scene.get_node("Terrain")
	_materials()
	road.road_orientation_mode = 1
	road.sample_step = 2.5
	road.allow_endpoint_to_midpath = true
	road.output_generate_collision = true
	road.markings_center_style = 3
	main_path = road.get_node("DrumulPoienii")
	var points: Array = []
	for data in route_data.points:
		points.append(_world(data, _smoothed_height(float(data.distance_m))))
	city_height = points.back().y
	# Flatten the final urban approach into the roundabout platform.
	for i in range(points.size()):
		var remain := float(route_data.route_length_m) - float(route_data.points[i].distance_m)
		points[i].y = lerpf(city_height, points[i].y, smoothstep(0.0, 180.0, remain))
	# The map starts next to the existing authored resort junction. Keep its socket
	# and approach tangent, transitioning to the mapped route over the first 100 m.
	for i in range(points.size()):
		var d := float(route_data.points[i].distance_m)
		if d > 100:
			break
		var straight := Vector3(-45,65,100) + Vector3(-0.263,0,-0.965) * d
		points[i] = straight.lerp(points[i], smoothstep(0.0,100.0,d))
	points.reverse()
	route_curve = _smooth_curve(points)
	var max_grade := 0.0
	for d in range(0,int(route_curve.get_baked_length())-3,3):
		var delta := route_curve.sample_baked(d+3)-route_curve.sample_baked(d)
		max_grade = maxf(max_grade,absf(delta.y)/maxf(0.001,Vector2(delta.x,delta.z).length()))
	print("BRASOV PROFILE max_grade_percent=",max_grade*100)
	if max_grade > 0.15:
		push_error("Smoothed route still contains excessive grade")
		quit(1)
		return
	main_path.curve = route_curve
	main_path.lane_profile_enabled = false
	main_path.point_widths = PackedFloat32Array([6.5])
	main_path.road_orientation_override_enabled = true
	main_path.road_orientation_mode = 1
	main_path.shoulder_left_width = 0.65
	main_path.shoulder_right_width = 0.65
	# Save the route provenance and datum alongside the editable spline.
	scene.set_meta("route_source", route_data.source_url)
	scene.set_meta("geometry_source", route_data.geometry_source)
	scene.set_meta("requested_endpoint_lat_lon", Vector2(route_data.requested_endpoint[0],route_data.requested_endpoint[1]))
	scene.set_meta("metres_per_map_metre", 1.0)
	scene.set_meta("elevation_datum_m", float(top_geo.elevation_m) - 65.0)
	_roundabout()
	_city_island_modifier()
	terrain.source_paths.clear()
	for path in road.get_children():
		if path is Path3D:
			terrain.source_paths.append(NodePath("../Road/" + str(path.name)))
	terrain.bounds_mode = 0
	terrain.auto_outer_padding = 170.0
	terrain.expand_bounds_for_modifiers = true
	terrain.path_sample_step = 7.5
	terrain.near_road_step = 22.0
	terrain.near_road_width = 40.0
	terrain.road_edge_collar_lateral_step = 2.0 # Full coverage, fewer redundant subdivisions over 12 km.
	terrain.far_grid_step = 90.0
	terrain.base_height = city_height + 45
	terrain.noise_amplitude = 2.0
	terrain.profile_to_base_blend_distance = 0.0 # Keep distant ground tied to road elevation along the 450 m descent.
	terrain.generate_in_editor = false # Embedded terrain opens immediately; explicit rebuild remains available.
	terrain.auto_regenerate_in_editor = false
	terrain.threaded_triangulation_enabled = true
	terrain.left_profile_distances = PackedFloat32Array([0,3,15,45,95])
	terrain.left_profile_heights = PackedFloat32Array([0,-0.4,3,12,20])
	terrain.right_profile_distances = PackedFloat32Array([0,3,15,45,95])
	terrain.right_profile_heights = PackedFloat32Array([0,-0.4,-2,-8,-15])
	# Keep guardrails out of the last city kilometre; retain the existing generators.
	scene.get_node("Guardrail").start_offset = 1000.0
	scene.get_node("Guardrail").curve_subdivision_step = 4.0
	scene.get_node("GuardrailPosts").start_offset = 1000.0
	scene.get_node("GuardrailPosts").spacing = 7.5
	var camera := scene.get_node("Camera")
	camera.set_script(load("res://addons/scenes/examples/brasov_route_camera.gd"))
	camera.set("route_path", NodePath("../Road/DrumulPoienii"))
	camera.set("focus", route_curve.sample_baked(180))
	camera.position = route_curve.sample_baked(180) + Vector3(-100,120,135)
	camera.far = 14000
	camera.set("example_title", "POIANA BRASOV - BRASOV CENTRU / traseu la scara 1:1\nDrum OSM; altitudini aproximative dupa profilul Rally-Maps")
	root.add_child(scene)
	print("BRASOV ROAD length=", route_curve.get_baked_length(), " contour=",road.get_source_rebuild_stats().get("contour_junctions",[]))
	terrain.debug_logs = true
	terrain.regenerate()
	var deadline := Time.get_ticks_msec() + 900000
	while terrain.is_terrain_generation_pending() or road.is_road_generation_pending():
		if Time.get_ticks_msec() > deadline:
			push_error("Brasov terrain generation timed out")
			quit(1)
			return
		await process_frame
	terrain.debug_logs = false
	print("BRASOV TERRAIN DONE")
	_index_ground()
	_refit_forest()
	_city_context()
	for frame in range(3):
		await process_frame
	for path in ["Road/GeneratedSplineRoadWelded", "Road/GeneratedRoadMarkings", "Terrain/GeneratedTopologyTerrain"]:
		_own_output(scene.get_node(path))
	var packed := PackedScene.new()
	var error := packed.pack(scene)
	if error == OK:
		error = ResourceSaver.save(packed, ROUTE_OUTPUT)
	print("BRASOV BUILD ",error," trees=",scene.get_node("Forest").tree_placements.size())
	scene.free()
	quit(0 if error == OK else 1)

func _own_output(node: Node) -> void:
	node.owner = scene
	for child in node.get_children():
		_own_output(child)

func _world(data: Dictionary, height: float) -> Vector3:
	return Vector3(-45 + (float(data.lon)-float(top_geo.lon))*111320*cos(deg_to_rad(float(top_geo.lat))),
		65 + height-float(top_geo.elevation_m), 100-(float(data.lat)-float(top_geo.lat))*111132)

func _raw_height(distance: float) -> float:
	var points: Array = route_data.points
	for i in range(1,points.size()):
		if distance <= float(points[i].distance_m):
			var a: Dictionary = points[i-1]
			var b: Dictionary = points[i]
			return lerpf(float(a.elevation_m),float(b.elevation_m),clampf(
				(distance-float(a.distance_m))/maxf(0.001,float(b.distance_m)-float(a.distance_m)),0,1))
	return float(points.back().elevation_m)

func _prepare_heights() -> void:
	# Smooth at uniform chainage, independent of OSM node density. Terrain DEM
	# spikes must not become sharp road ramps. Limit grade before making the spline.
	var count := ceili(float(route_data.route_length_m)/10.0)+1
	for i in range(count):
		var sum_ := 0.0
		var weight_sum := 0.0
		for j in range(-15,16):
			var weight := exp(-0.5*pow(float(j)/5.0,2))
			sum_ += _raw_height(clampf((i+j)*10.0,0,float(route_data.route_length_m)))*weight
			weight_sum += weight
		smooth_heights.append(sum_/weight_sum)
	for i in range(1,count):
		smooth_heights[i] = clampf(smooth_heights[i],smooth_heights[i-1]-1.0,smooth_heights[i-1]+1.0)
	for i in range(count-2,-1,-1):
		smooth_heights[i] = clampf(smooth_heights[i],smooth_heights[i+1]-1.0,smooth_heights[i+1]+1.0)

func _smoothed_height(distance: float) -> float:
	var index := mini(floori(distance/10.0),smooth_heights.size()-2)
	return lerpf(smooth_heights[index],smooth_heights[index+1],clampf(distance/10.0-index,0,1))

func _city_island_modifier() -> void:
	var pin := _world({"lat":route_data.requested_endpoint[0],"lon":route_data.requested_endpoint[1]},city_height-65+float(top_geo.elevation_m))
	var modifier := MODIFIER.new()
	modifier.name = "InsulaSensCentru"
	modifier.curve = _curve([pin+Vector3(-2,0,0),pin+Vector3(2,0,0)])
	modifier.mode = 2
	modifier.radius = 40
	modifier.inner_radius = 24
	modifier.target_height = city_height
	modifier.strength = 1
	modifier.affect_near_roads = true
	_add(modifier,modifier.name,terrain)
	terrain.height_modifiers.append(NodePath(modifier.name))

func _smooth_curve(points: Array, cyclic := false) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 1.0
	for i in range(points.size()):
		var a: Vector3 = points[maxi(i-1,0)]
		var b: Vector3 = points[mini(i+1,points.size()-1)]
		if cyclic and (i == 0 or i == points.size()-1):
			a = points[points.size()-2]
			b = points[1]
		var tangent := (b-a).normalized()
		var reach := minf(points[i].distance_to(a), points[i].distance_to(b))/3.0
		curve.add_point(points[i], -tangent*reach, tangent*reach)
	return curve

func _roundabout() -> void:
	var points: Array = []
	for data in route_data.roundabout.points:
		points.append(_world(data,city_height-65+float(top_geo.elevation_m)))
	# Put the closed spline seam opposite the incoming road, leaving a midpath socket.
	points.pop_back()
	var ordered: Array = []
	var offset := points.size()/2
	for i in range(points.size()):
		ordered.append(points[(i+offset)%points.size()])
	ordered.append(ordered[0])
	var path := PROFILE.new()
	path.name = "SensGiratoriuCentru"
	path.curve = _smooth_curve(ordered,true)
	path.point_widths = PackedFloat32Array([9.0])
	path.shoulder_left_width = 0.3
	path.shoulder_right_width = 0.3
	path.show_width_preview = false
	_add(path,path.name,road)

func _refit_forest() -> void:
	var forest := scene.get_node("Forest")
	var placements := PackedVector4Array()
	for p in forest.tree_placements:
		_try_tree(Vector3(p.x,0,p.z),p.w,placements)
	for d in range(1000,int(route_curve.get_baked_length())-120,12):
		var p := route_curve.sample_baked(d)
		var ahead := route_curve.sample_baked(d+4)
		var right := (ahead-p).normalized().cross(Vector3.UP).normalized()
		for side in [-1,1]:
			for ring in range(2):
				var q: Vector3 = p+right*side*rng.randf_range(15+ring*45,50+ring*60)
				_try_tree(q,rng.randf_range(0.8,1.5),placements)
	forest.tree_placements = placements
	forest.chunk_size = 220
	forest.rebuild()

func _try_tree(p: Vector3, scale_: float, placements: PackedVector4Array) -> void:
	var y := _height(p.x,p.z)
	p.y = y
	if not is_finite(y):
		return
	for child in road.get_children():
		if child is Path3D:
			var closest: Vector3 = child.curve.get_closest_point(p)
			if Vector2(p.x-closest.x,p.z-closest.z).length() < 12:
				return
	placements.append(Vector4(p.x,y,p.z,scale_))

func _city_context() -> void:
	var city := Node3D.new()
	_add(city,"BrasovCentru")
	var pin := _world({"lat":route_data.requested_endpoint[0],"lon":route_data.requested_endpoint[1]},city_height-65+float(top_geo.elevation_m))
	var island := CylinderMesh.new()
	island.top_radius = 9.5
	island.bottom_radius = 9.5
	island.height = 0.18
	_mesh("InsulaSens",island,pin+Vector3.UP*0.08,mats.grass,city)
	_label("BRASOV CENTRU",pin+Vector3.UP*16,city,48)
	# Simple roadside context, not surveyed buildings or footprints.
	for d in range(100,650,35):
		var p := route_curve.sample_baked(d)
		var tangent := (route_curve.sample_baked(d+4)-p).normalized()
		var right := tangent.cross(Vector3.UP).normalized()
		for side in [-1,1]:
			var q: Vector3 = p+right*side*rng.randf_range(20,32)
			var y := _height(q.x,q.z)
			if not is_finite(y):
				continue
			var height := rng.randf_range(6,11)
			var building := _box("Cladire",Vector3(10,height,14),Vector3(q.x,y+height/2,q.z),mats.wall,city)
			building.rotation.y = atan2(tangent.x,tangent.z)
			var roof := _box("Acoperis",Vector3(11,0.5,15),Vector3(q.x,y+height+0.25,q.z),mats.dark_roof,city)
			roof.rotation.y = building.rotation.y
