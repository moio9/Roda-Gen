extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _run() -> void:
	var scene := (load("res://addons/scenes/examples/poiana_brasov.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in range(5):
		await process_frame
	var terrain := scene.get_node("Terrain")
	var road := scene.get_node("Road")
	var deadline := Time.get_ticks_msec() + 120000
	while terrain.is_terrain_generation_pending() or road.is_road_generation_pending():
		if Time.get_ticks_msec() > deadline:
			_check(false, "Generation timeout")
			quit(1)
			return
		await process_frame
	for path in ["Road/GeneratedSplineRoadWelded", "Road/GeneratedRoadMarkings", "Terrain/GeneratedTopologyTerrain"]:
		var node := scene.get_node_or_null(path) as MeshInstance3D
		_check(node != null and node.mesh != null and node.mesh.get_surface_count() > 0, "Missing output: " + path)
		if node != null and node.mesh != null:
			for surface in range(node.mesh.get_surface_count()):
				var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for v in vertices:
					if not v.is_finite():
						_check(false, "Nonfinite mesh: " + path)
						break
	_check_junction_overlap(scene)
	var asphalt: Mesh = scene.get_node("Road/GeneratedSplineRoadWelded").mesh
	var arrays := asphalt.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var first_junction_max_slope := 0.0
	var upward := 0
	var downward := 0
	for i in range(0, indices.size(), 3):
		var cross_y := (vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]]).y
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		var center := (a+b+c)/3.0
		if Vector2(center.x+45,center.z-100).length() <= 20:
			var normal := (b-a).cross(c-a)
			if normal.length() > 0.00001:
				first_junction_max_slope = maxf(first_junction_max_slope,
					rad_to_deg(atan2(Vector2(normal.x,normal.z).length(),absf(normal.y))))
		upward += int(cross_y < -0.0001)
		downward += int(cross_y > 0.0001)
	_check(first_junction_max_slope < 12.0, "First junction contains steep asphalt slivers")
	print("POIANA FIRST JUNCTION max_slope_degrees=", first_junction_max_slope)
	_check(upward > 0 and downward == 0, "Asphalt must face upward with back-face culling")
	_check(int(road.get_marking_stats().get("hatch_triangles",0)) > 0, "Missing widened-bend hatching")
	_check(scene.get_node("Road/GeneratedRoadMarkings").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Paint must not cast shadows")
	_check(terrain.source_paths.size() == 5 and terrain.height_modifiers.size() == 3, "Explicit road/modifier sources must survive save and reload")
	var mountain: Dictionary = terrain.get_terrain_height_at_world(Vector3(310,0,330))
	_check(float(mountain.get("y",0)) > 200, "Postavarul relief did not generate")
	var road_paths: Array[Path3D] = []
	for node in road.get_children():
		if node is Path3D:
			road_paths.append(node)
	var trees := 0
	var road_conflicts := 0
	for batch in scene.get_node("Forest").get_children():
		_check(batch is MultiMeshInstance3D and batch.multimesh != null, "Forest must use MultiMesh batches")
		if not batch is MultiMeshInstance3D:
			continue
	for placement: Vector4 in scene.get_node("Forest").tree_placements:
		var pos := Vector3(placement.x,placement.y,placement.z)
		_check(pos.is_finite(), "Nonfinite tree transform")
		trees += 1
		for path in road_paths:
			var closest := path.curve.get_closest_point(pos)
			if Vector2(pos.x,pos.z).distance_to(Vector2(closest.x,closest.z)) < 10.0:
				road_conflicts += 1
	_check(trees >= 2000 and road_conflicts == 0, "Forest density/road clearance failed")
	_check(_has_geometry(scene.get_node("Guardrail")), "Missing spline guardrail")
	_check(_has_geometry(scene.get_node("GuardrailPosts")), "Missing spline posts")
	for path in ["Resort/ParcareaMare", "Resort/LaculMiorita", "Resort/BisericaLemn", "Resort/PartiiSiTelecabina"]:
		_check(_has_geometry(scene.get_node(path)), "Missing landmark: " + path)
	print("POIANA CHECK ", "OK" if failures == 0 else "FAILED", " failures=",failures,
		" trees=",trees," road_conflicts=",road_conflicts," upward_triangles=",upward)
	scene.free()
	quit(0 if failures == 0 else 1)

func _has_geometry(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.instance_count > 0:
		return true
	for child in node.get_children():
		if _has_geometry(child):
			return true
	return false

# Independent polygon intersections detect actual area shared by the two meshes.
func _check_junction_overlap(scene: Node, max_overlap_area := 0.01) -> void:
	var road := scene.get_node("Road")
	var reports: Array = road.get_source_rebuild_stats().get("contour_junctions",[])
	var terrain_mesh: Mesh = scene.get_node("Terrain/GeneratedTopologyTerrain").mesh
	var road_mesh: Mesh = scene.get_node("Road/GeneratedSplineRoadWelded").mesh
	var road_triangles := _mesh_polygons(road_mesh)
	var terrain_triangles := _mesh_polygons(terrain_mesh)
	var overlap_area := 0.0
	for report in reports:
		if not report.get("ok",false):
			continue
		var center: Vector3 = report.center
		var region := Rect2(Vector2(center.x,center.z)-Vector2.ONE*22,Vector2.ONE*44)
		var near_roads: Array = []
		for triangle in road_triangles:
			if region.intersects(triangle.bounds):
				near_roads.append(triangle)
		for triangle in terrain_triangles:
			if not region.intersects(triangle.bounds):
				continue
			for asphalt in near_roads:
				if not triangle.bounds.intersects(asphalt.bounds):
					continue
				for polygon in Geometry2D.intersect_polygons(triangle.points,asphalt.points):
					var twice_area := 0.0
					for i in range(1,polygon.size()-1):
						twice_area += (polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0])
					overlap_area += absf(twice_area)*0.5
	print("POIANA JUNCTION terrain_overlap_area=",overlap_area)
	_check(overlap_area < max_overlap_area,"Terrain intersects final junction surfaces")

func _mesh_polygons(mesh: Mesh) -> Array:
	var result: Array = []
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0,count,3):
			var polygon := PackedVector2Array()
			for j in range(3):
				var v := vertices[indices[i+j] if not indices.is_empty() else i+j]
				polygon.append(Vector2(v.x,v.z))
			var bounds := Rect2(polygon[0],Vector2.ZERO).expand(polygon[1]).expand(polygon[2])
			result.append({"points":polygon,"bounds":bounds})
	return result
