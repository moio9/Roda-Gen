extends SceneTree
const TERRAIN = preload("../scripts/spline_road/terrain_final_road_surface.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _run() -> void:
	var road := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(0, 2, 0), Vector3(4, 6, 0), Vector3(0, 2, 4)]:
		st.add_vertex(point)
	road.mesh = st.commit()
	road.position = Vector3(10, 7, -3)
	root.add_child(road)
	var terrain := TERRAIN.new()
	terrain.terrain_edge_y_offset = 0.0
	terrain._cut.prepare(road, road.global_transform.affine_inverse())
	var hit: Dictionary = terrain._surface_at(Vector2(2, -0.5))
	_check(absf(hit.y - 4.0) < 0.00001, "Sample the final sloped road edge in terrain space")
	_check(absf(hit.distance - 0.5) < 0.00001, "Use distance to the final mesh")
	var seam: Vector3 = terrain._fit_seam(Vector3(2, -20, 0))
	_check(absf(seam.y - 4.0) < 0.00001, "Cut seam must meet road elevation")
	var far := Vector3(50, 23, 50)
	_check(terrain._fit(far) == far, "Keep the distant terrain profile unchanged")
	terrain.lock_height_to_road_edge = false
	_check(terrain._fit_seam(Vector3(2, -20, 0)).y == -20, "Respect disabled height fitting")
	terrain._cut.prepare(null, Transform3D.IDENTITY)
	terrain._surface_queries.clear()
	_check(terrain._surface_at(Vector2(2, 0)).is_empty(), "No stale height after road removal")
	terrain = null
	road.free()
	print("ROAD MESH TERRAIN ", "OK" if failures == 0 else "FAILED", " failures=", failures)
	quit(failures)
