extends SceneTree
## Recreates the authored, compressed Poiana Brasov example. No GIS/assets required.
## Run only to reset the example: this overwrites its scene, including manual edits.
const OUTPUT := "res://addons/scenes/examples/poiana_brasov.tscn"
const ROAD = preload("res://addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("res://addons/scripts/spline_road/spline_path_profile.gd")
const TERRAIN = preload("res://addons/scenes/examples/poiana_terrain.gd")
const MODIFIER = preload("res://addons/scripts/spline_road/terrain_height_modifier.gd")
const PROPS = preload("res://addons/scripts/spline_road/spline_prop_array.gd")
const DEFORMER = preload("res://addons/scripts/spline_road/spline_mesh_deformer.gd")
var scene: Node3D
var road: Node3D
var terrain: Node3D
var rng := RandomNumberGenerator.new()
var road_samples := PackedVector3Array()
var height_cells: Dictionary = {}
var reserved: Array[Rect2] = []
var mats: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	rng.seed = 12092026
	scene = Node3D.new()
	scene.name = "PoianaBrasov"
	scene.set_script(load("res://addons/scenes/examples/example_scene.gd"))
	_materials()
	_environment()
	_roads()
	_terrain()
	_barriers()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while terrain.is_terrain_generation_pending() or road.is_road_generation_pending():
		if Time.get_ticks_msec() > deadline:
			push_error("Poiana generation timed out")
			quit(1)
			return
		await process_frame
	_index_ground()
	_resort()
	_forest()
	for frame in range(3):
		await process_frame
	# Save native road/terrain outputs for immediate editor visibility.
	for path in ["Road/GeneratedSplineRoadWelded", "Road/GeneratedRoadMarkings", "Terrain/GeneratedTopologyTerrain"]:
		scene.get_node(path).owner = scene
	var packed := PackedScene.new()
	var result := packed.pack(scene)
	if result == OK:
		result = ResourceSaver.save(packed, OUTPUT)
	print("POIANA BUILD result=", result, " road_length=", road_samples.size() * 5,
		" markings=", road.get_marking_stats())
	scene.free()
	quit(0 if result == OK else 1)

func _add(node: Node, name_: String, parent: Node = null) -> Node:
	node.name = name_
	(parent if parent != null else scene).add_child(node, true)
	node.owner = scene
	return node

func _material(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func _materials() -> void:
	mats = {
		"asphalt": _material(Color("343b40")), "shoulder": _material(Color("827c67")),
		"paint": _material(Color("f5efdc")), "metal": _material(Color("a2aeb0"), 0.55),
		"wall": _material(Color("e5d9b9")), "wood": _material(Color("684738")),
		"roof": _material(Color("773e32")), "dark_roof": _material(Color("39434a")),
		"glass": _material(Color("547985"), 0.35), "water": _material(Color("387d80"), 0.25),
		"trunk": _material(Color("66503a")), "pine": _material(Color("264a37")),
		"pine_light": _material(Color("3d6240")), "grass": _material(Color("8a9854")),
		"blue": _material(Color("22649a")), "red": _material(Color("b94a35"))
	}

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a9c3ce")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c3d1da")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	_add(world, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color("fff1d5")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500
	_add(sun, "Sun")
	var camera := Camera3D.new()
	camera.set_script(load("res://addons/scenes/examples/example_camera.gd"))
	camera.position = Vector3(-520, 525, 575)
	camera.set("focus", Vector3(-20, 60, -20))
	camera.set("example_title", "POIANA BRASOV / Drumul Poienii - statiune - Postavarul\nInterpretare stilizata, scara comprimata")
	camera.far = 3000
	camera.fov = 53
	camera.current = true
	_add(camera, "Camera")

func _curve(points: Array, smooth := true) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	for i in range(points.size()):
		var tangent: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]) / 6.0 if smooth else Vector3.ZERO
		curve.add_point(points[i], -tangent, tangent)
	return curve

func _path(name_: String, points: Array, lane_width := 3.25) -> Path3D:
	var path := Path3D.new()
	path.set_script(PROFILE)
	path.curve = _curve(points)
	path.set("lane_profile_enabled", true)
	path.set("default_lane_width", lane_width)
	path.set("point_lane_widths", PackedFloat32Array([lane_width]))
	path.set("shoulder_left_width", 0.65)
	path.set("shoulder_right_width", 0.65)
	path.set("show_width_preview", false)
	_add(path, name_, road)
	for s in range(0, int(path.curve.get_baked_length()) + 1, 5):
		road_samples.append(path.curve.sample_baked(s))
	return path

func _roads() -> void:
	road = Node3D.new()
	road.set_script(ROAD)
	road.set("sample_step", 2.0)
	road.set("adaptive_sampling_enabled", false)
	road.set("threaded_generation_enabled", false)
	road.set("incremental_generation_enabled", true)
	road.set("debug_generation_logs", false)
	road.set("invert_faces", true)
	road.set("road_material_override", mats.asphalt)
	road.set("shoulder_material_override", mats.shoulder)
	road.set("markings_enabled", true)
	road.set("markings_center_color", Color("f5efdc"))
	road.set("markings_lane_style", 1)
	road.set("markings_hatch_width", 0.3)
	road.set("junction_geometry_mode", 1)
	road.set("junction_corner_radius", 4.0)
	_add(road, "Road")
	var approach := _path("DrumulPoienii", [Vector3(-280,8,-360), Vector3(-185,17,-315),
		Vector3(-90,24,-320), Vector3(-40,29,-260), Vector3(-95,35,-210),
		Vector3(-220,40,-190), Vector3(-245,44,-130), Vector3(-185,49,-90),
		Vector3(-70,54,-75), Vector3(-20,60,-20), Vector3(-60,64,45), Vector3(-45,65,100)])
	approach.set("point_lanes_right", PackedInt32Array([1,1,1,2,1,1,1,1,2,1,1,1]))
	_path("StradaPoianaSoarelui", [Vector3(-45,65,100), Vector3(0,65,155), Vector3(20,65,220), Vector3(0,65,280)])
	_path("SpreRasnov", [Vector3(-45,65,100), Vector3(-125,65,125), Vector3(-220,58,170), Vector3(-320,49,235)])
	_path("AccesParcareaMare", [Vector3(-125,65,125), Vector3(-125,65,100), Vector3(-105,65,85)], 2.75)
	_path("StradaValeaDraga", [Vector3(20,65,220), Vector3(65,65,215), Vector3(95,65,255)], 2.8)

func _modifier(name_: String, points: Array, radius_: float, mode_: int, inner := 0.0) -> void:
	var modifier := Path3D.new()
	modifier.set_script(MODIFIER)
	modifier.curve = _curve(points)
	modifier.set("mode", mode_)
	modifier.set("radius", radius_)
	modifier.set("inner_radius", inner)
	modifier.set("distance_sample_step", 15.0)
	modifier.set("resolution_path_step", 28.0)
	modifier.set("resolution_radius", radius_ * 0.8)
	modifier.set("resolution_step", 24.0)
	modifier.set("resolution_radial_rings", 4)
	modifier.set("road_protection_blend_distance", 18.0)
	if mode_ == 2:
		modifier.set("target_height", 65.0)
		modifier.set("strength", 1.0)
		modifier.set("affect_near_roads", true)
	_add(modifier, name_, terrain)

func _terrain() -> void:
	terrain = Node3D.new()
	terrain.set_script(TERRAIN)
	terrain.set("road_network_source", NodePath("../Road"))
	var sources: Array[NodePath] = []
	for path in road.get_children():
		sources.append(NodePath("../Road/" + str(path.name)))
	terrain.set("source_paths", sources)
	terrain.set("path_sample_step", 4.0)
	terrain.set("adaptive_path_sampling", false)
	terrain.set("bounds_mode", 1)
	terrain.set("manual_center_xz", Vector2(0, 0))
	terrain.set("manual_size_xz", Vector2(900, 900))
	terrain.set("expand_bounds_for_modifiers", false)
	terrain.set("far_grid_step", 24.0)
	terrain.set("near_road_step", 10.0)
	terrain.set("near_road_width", 35.0)
	terrain.set("base_height", 55.0)
	terrain.set("left_profile_distances", PackedFloat32Array([0,3,15,45,95]))
	terrain.set("left_profile_heights", PackedFloat32Array([0,-0.4,3,12,18]))
	terrain.set("right_profile_distances", PackedFloat32Array([0,3,15,45,95]))
	terrain.set("right_profile_heights", PackedFloat32Array([0,-0.4,-2,-8,-12]))
	terrain.set("profile_to_base_blend_distance", 120.0)
	terrain.set("noise_amplitude", 3.0)
	terrain.set("noise_frequency", 0.018)
	terrain.set("invert_faces", true)
	terrain.set("threaded_triangulation_enabled", false)
	terrain.set("incremental_generation_enabled", true)
	terrain.set("auto_find_height_modifiers", false)
	var ground := ShaderMaterial.new()
	ground.shader = load("res://addons/scenes/examples/poiana_ground.gdshader")
	terrain.set("terrain_material_override", ground)
	_add(terrain, "Terrain")
	_modifier("Postavarul", [Vector3(310,160,-10), Vector3(320,210,170), Vector3(295,235,360)], 350, 8, 35)
	_modifier("CulmeaVestica", [Vector3(-365,105,-290), Vector3(-360,125,10), Vector3(-390,110,300)], 150, 8)
	_modifier("PoianaStatiunii", [Vector3(-85,65,85), Vector3(-15,65,170), Vector3(30,65,285)], 230, 2, 80)
	var modifier_paths: Array[NodePath] = [NodePath("Postavarul"), NodePath("CulmeaVestica"), NodePath("PoianaStatiunii")]
	terrain.set("height_modifiers", modifier_paths)

func _barriers() -> void:
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.15, 0.9, 0.15)
	var posts := Node3D.new()
	posts.set_script(PROPS)
	var post_paths: Array[NodePath] = [NodePath("../Road/DrumulPoienii")]
	posts.set("source_paths", post_paths)
	posts.set("road_network_source", NodePath("../Road"))
	posts.set("item_mesh", post_mesh)
	posts.set("item_material_override", mats.metal)
	posts.set("placement_mode", 3)
	posts.set("spacing", 5.0)
	posts.set("vertical_offset", 0.45)
	posts.set("outward_offset", 0.1)
	posts.set("start_offset", 8.0)
	posts.set("end_trim", 25.0)
	posts.set("ranges_mode", 0)
	posts.set("render_mode", 1)
	_add(posts, "GuardrailPosts")
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.12, 0.25, 5)
	var rail := Node3D.new()
	rail.set_script(DEFORMER)
	rail.set("source_path", NodePath("../Road/DrumulPoienii"))
	rail.set("source_mesh", rail_mesh)
	rail.set("road_network_source", NodePath("../Road"))
	rail.set("placement_mode", 3)
	rail.set("vertical_offset", 0.72)
	rail.set("outward_offset", 0.1)
	rail.set("start_offset", 8.0)
	rail.set("end_trim", 25.0)
	rail.set("deform_axis", 2)
	rail.set("curve_subdivision_step", 2.0)
	rail.set("material_override", mats.metal)
	_add(rail, "Guardrail")

# Query the actual generated triangles, so trees sit on the rendered surface.
func _index_ground() -> void:
	var mesh: Mesh = terrain.get_node("GeneratedTopologyTerrain").mesh
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count, 3):
			var tri := [vertices[indices[i] if not indices.is_empty() else i], vertices[indices[i+1] if not indices.is_empty() else i+1], vertices[indices[i+2] if not indices.is_empty() else i+2]]
			var bounds := Rect2(Vector2(tri[0].x, tri[0].z), Vector2.ZERO)
			for vertex: Vector3 in tri:
				bounds = bounds.expand(Vector2(vertex.x, vertex.z))
			for x in range(floori(bounds.position.x / 24), floori(bounds.end.x / 24) + 1):
				for z in range(floori(bounds.position.y / 24), floori(bounds.end.y / 24) + 1):
					var key := Vector2i(x,z)
					if not height_cells.has(key):
						height_cells[key] = []
					height_cells[key].append(tri)

func _height(x: float, z: float) -> float:
	var p := Vector2(x,z)
	for tri in height_cells.get(Vector2i(floori(x/24),floori(z/24)), []):
		var a := Vector2(tri[0].x,tri[0].z)
		var b := Vector2(tri[1].x,tri[1].z)
		var c := Vector2(tri[2].x,tri[2].z)
		var den := (b-a).cross(c-a)
		if absf(den) < 0.0001:
			continue
		var v := (p-a).cross(c-a) / den
		var w := (b-a).cross(p-a) / den
		if v >= -0.0001 and w >= -0.0001 and v+w <= 1.0001:
			return tri[0].y * (1-v-w) + tri[1].y*v + tri[2].y*w
	return NAN

func _mesh(name_: String, mesh: Mesh, position_: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position_
	node.material_override = material
	_add(node, name_, parent)
	return node

func _box(name_: String, size: Vector3, position_: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(name_, mesh, position_, material, parent)

func _label(text_: String, position_: Vector3, parent: Node, size := 36) -> void:
	var label := Label3D.new()
	label.text = text_
	label.font_size = size
	label.pixel_size = 0.075
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("fff6da")
	label.outline_modulate = Color("263e39")
	label.outline_size = 10
	label.position = position_
	label.no_depth_test = false
	_add(label, "Label", parent)

func _roof(width: float, depth: float, rise: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(-width/2,0,-depth/2), Vector3(width/2,0,-depth/2), Vector3(0,rise,-depth/2),
		Vector3(-width/2,0,depth/2),Vector3(width/2,0,depth/2),Vector3(0,rise,depth/2)]
	for i in [0,1,2, 3,5,4, 0,2,5, 0,5,3, 1,4,5, 1,5,2]:
		st.add_vertex(p[i])
	st.generate_normals()
	return st.commit()

func _chalet(name_: String, x: float, z: float, size: Vector3, angle := 0.0, dark := false) -> void:
	var y := _height(x,z)
	if is_nan(y):
		return
	var group := Node3D.new()
	group.position = Vector3(x,y,z)
	group.rotation.y = deg_to_rad(angle)
	_add(group, name_, scene.get_node("Resort"))
	reserved.append(Rect2(Vector2(x-size.x*0.8,z-size.z*0.8),Vector2(size.x*1.6,size.z*1.6)))
	_box("Foundation", Vector3(size.x+1.0,2.5,size.z+1.0), Vector3(0,0.35,0), mats.shoulder, group)
	_box("Walls", size, Vector3(0,size.y/2+1.0,0), mats.wall, group)
	_box("TimberFloor", Vector3(size.x+0.12,1.0,size.z+0.12), Vector3(0,size.y-0.8,0), mats.wood, group)
	_mesh("PitchedRoof", _roof(size.x+2.0,size.z+2.0, size.x*0.3), Vector3(0,size.y+1.0,0), mats.dark_roof if dark else mats.roof, group)
	for side in [-1,1]:
		for floor_ in range(maxi(1,int(size.y/3.1))):
			for column in range(maxi(2,int(size.x/3.2))):
				var wx := -size.x/2 + 1.6 + column*3.2
				_box("Window",Vector3(1.25,1.5,0.12),Vector3(wx,2.8+floor_*3.0,side*(size.z/2+0.08)),mats.glass,group)

func _resort() -> void:
	var resort := _add(Node3D.new(), "Resort") as Node3D
	_chalet("HotelMontan", -38,175,Vector3(24,15,17),-15,true)
	_chalet("CabanaLac", -68,259,Vector3(23,8,15),12)
	_chalet("HotelBradul", 57,165,Vector3(30,14,19),0,true)
	_chalet("CabanaBazaPartiei", 111,245,Vector3(22,7,14),-12)
	_chalet("PensiunePoiana", -148,161,Vector3(16,9,13),-15)
	_chalet("PensiunePadure", -182,195,Vector3(19,9,14),-20)
	_chalet("CabanaVale", -28,310,Vector3(18,8,14),-5)
	_chalet("CabanaSoarelui", 45,300,Vector3(17,8,13),20)
	# Timber church silhouette: nave, narrow bell tower and pointed spire.
	_chalet("BisericaLemn", -15,247,Vector3(8,7,18),0,true)
	var church := resort.get_node("BisericaLemn")
	_box("BellTower",Vector3(4,17,4),Vector3(0,10,-6),mats.wood,church)
	var spire := CylinderMesh.new()
	spire.top_radius = 0
	spire.bottom_radius = 3.3
	spire.height = 10
	spire.radial_segments = 4
	_mesh("Spire",spire,Vector3(0,23.5,-6),mats.dark_roof,church)
	_box("Cross",Vector3(0.2,2,0.2),Vector3(0,29.5,-6),mats.wood,church)
	_box("CrossArm",Vector3(1.2,0.2,0.2),Vector3(0,29.8,-6),mats.wood,church)
	_parking(resort)
	_lake(resort)
	_ski_area(resort)
	_label("POIANA BRASOV",Vector3(-30,108,132),resort,54)
	_label("Drumul Poienii",Vector3(-160,66,-180),resort)
	_label("spre Brasov",Vector3(-280,24,-363),resort,28)
	_label("spre Rasnov",Vector3(-317,65,244),resort,28)
	_label("Postavarul",Vector3(295,255,350),resort,44)

func _parking(parent: Node) -> void:
	var group := _add(Node3D.new(), "ParcareaMare",parent)
	reserved.append(Rect2(-122,52,61,55))
	_box("Asphalt",Vector3(56,0.18,45),Vector3(-92,65.15,78),mats.asphalt,group)
	# Clear centre aisle with two rows of perpendicular bays.
	for row in [-1,1]:
		for i in range(17):
			var stripe := _box("BayStripe",Vector3(0.13,0.015,6),Vector3(-117+i*3.0,65.255,78+row*15.5),mats.paint,group)
			stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if i < 16 and i % 3 != 0:
				var car := _add(Node3D.new(),"Car",group) as Node3D
				car.position = Vector3(-115.5+i*3,65.28,78+row*15.5)
				_box("Body",Vector3(1.8,0.85,4.0),Vector3(0,0.65,0),mats.red if i%2==0 else mats.blue,car)
				_box("Cabin",Vector3(1.65,0.65,2.0),Vector3(0,1.35,-0.1),mats.glass,car)
	_box("Bus",Vector3(2.7,2.9,10),Vector3(-72,66.7,80),mats.blue,group)
	_box("BusWindows",Vector3(2.75,1,7.7),Vector3(-72,67.1,80),mats.glass,group)
	_label("P  Parcarea Mare",Vector3(-95,76,52),group,28)

func _lake(parent: Node) -> void:
	var lake := _add(Node3D.new(),"LaculMiorita",parent)
	reserved.append(Rect2(-104,194,56,42))
	for material in [mats.shoulder,mats.water]:
		var disk := CylinderMesh.new()
		disk.height = 0.12
		disk.top_radius = 1
		disk.bottom_radius = 1
		disk.radial_segments = 48
		var water: bool = material == mats.water
		var node := _mesh("Water" if water else "Shore",disk,Vector3(-78,65.12 if water else 65.02,215),material,lake)
		node.scale = Vector3(23 if water else 25,1,15 if water else 17)
	_box("Pontoon",Vector3(4,0.3,10),Vector3(-78,65.4,231),mats.wood,lake)
	_label("Lacul Miorita",Vector3(-78,73,215),lake,26)

func _ski_area(parent: Node) -> void:
	var group := _add(Node3D.new(),"PartiiSiTelecabina",parent)
	# Summer clearings draped over the same terrain as the forest.
	for route in [[Vector2(92,280),Vector2(285,326),20.0,"Stadion"], [Vector2(92,190),Vector2(270,139),15.0,"Bradul"]]:
		var a: Vector2 = route[0]
		_label(str(route[3]),Vector3(a.x,_height(a.x,a.y)+8,a.y),group,28)
	var start := Vector3(115,_height(115,266)+11,266)
	var end := Vector3(295,_height(295,326)+14,326)
	for i in range(5):
		var pos := start.lerp(end,i/4.0)
		var ground := _height(pos.x,pos.z)
		_box("Pylon",Vector3(0.8,pos.y-ground,0.8),Vector3(pos.x,(pos.y+ground)/2,pos.z),mats.metal,group)
		_box("Crossbeam",Vector3(7,0.5,0.6),pos,mats.metal,group)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for side in [-2.6,2.6]:
		st.add_vertex(start+Vector3(side,0,0))
		st.add_vertex(end+Vector3(side,0,0))
	_mesh("Cables",st.commit(),Vector3.ZERO,mats.dark_roof,group)
	for i in range(7):
		var pos := start.lerp(end,(i+0.5)/7.0)
		_box("Cabin",Vector3(2.2,2.6,2.2),pos+Vector3(2.6,-2.5,0),mats.red,group)
		_box("CabinGlass",Vector3(2.25,1.2,2.25),pos+Vector3(2.6,-2.0,0),mats.glass,group)

func _forest() -> void:
	var forest := _add(Node3D.new(),"Forest")
	var transforms: Array[Transform3D] = []
	for attempt in range(5500):
		var x := rng.randf_range(-430,430)
		var z := rng.randf_range(-430,430)
		var p := Vector2(x,z)
		if Rect2(-130,48,270,282).has_point(p):
			continue
		var blocked := false
		for area in reserved:
			if area.grow(4).has_point(p):
				blocked = true
		for corridor in [[Vector2(92,280),Vector2(285,326),25.0], [Vector2(92,190),Vector2(270,139),20.0]]:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,corridor[0],corridor[1])) < float(corridor[2]):
				blocked = true
		if blocked:
			continue
		for road_point in road_samples:
			if p.distance_squared_to(Vector2(road_point.x,road_point.z)) < 13.0*13.0:
				blocked = true
				break
		if blocked:
			continue
		var y := _height(x,z)
		if is_nan(y):
			continue
		var scale_ := rng.randf_range(0.75,1.5)
		transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_),Vector3(x,y-0.2,z)))
		if transforms.size() >= 2800:
			break
	# One shared low-poly pine mesh, spatial MultiMesh batches for culling.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.34
	trunk.height = 4.0
	trunk.radial_segments = 6
	st.append_from(trunk,0,Transform3D(Basis.IDENTITY,Vector3(0,2,0)))
	var tree := st.commit()
	tree.surface_set_material(0,mats.trunk)
	for tier in range(3):
		var cone := CylinderMesh.new()
		cone.top_radius = 0
		cone.bottom_radius = 3.4-tier*0.8
		cone.height = 6.0-tier*0.8
		cone.radial_segments = 7
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(cone,0,Transform3D(Basis.IDENTITY,Vector3(0,5+tier*2.0,0)))
		st.commit(tree)
		tree.surface_set_material(tier+1,mats.pine if tier%2==0 else mats.pine_light)
	var placements := PackedVector4Array()
	for transform_ in transforms:
		var p := transform_.origin
		placements.append(Vector4(p.x,p.y,p.z,transform_.basis.get_scale().x))
	forest.set_script(load("res://addons/scenes/examples/poiana_forest.gd"))
	forest.set("tree_mesh",tree)
	forest.set("tree_placements",placements)
	forest.call("rebuild")
	print("POIANA FOREST trees=",placements.size()," batches=",forest.get_child_count())
