extends SceneTree
const CUT = preload("res://addons/scripts/spline_road/terrain_road_mesh_cut.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1
func _run() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3.ZERO,Vector3(4,0,0),Vector3(0,0,4)]:
		st.add_vertex(v)
	var output := MeshInstance3D.new()
	output.mesh = st.commit()
	output.position = Vector3(7,2,-8)
	root.add_child(output)
	var cut := CUT.new()
	cut.prepare(output,output.global_transform.affine_inverse())
	var a := Vector3(-2,-10,-2)
	var b := Vector3(8,10,-2)
	var c := Vector3(-2,20,8)
	var remainder := cut.subtract(a,b,c)
	_check(is_equal_approx(_area(remainder),42.0),"Subtract only the covered area; preserve the surrounding terrain")
	for triangle in remainder:
		for v: Vector3 in triangle:
			_check(absf(v.y-(2*v.x+3*v.z))<0.0001,"Interpolate terrain elevation at each cut vertex")
	_check(cut.subtract(Vector3(0.5,0,0.5),Vector3(1,0,0.5),Vector3(0.5,0,1)).is_empty(),"Remove fully covered terrain")
	var outside := cut.subtract(Vector3(8,0,8),Vector3(10,0,8),Vector3(8,0,10))
	_check(is_equal_approx(_area(outside),2.0),"Leave terrain outside the road unchanged")
	cut.prepare(null,Transform3D.IDENTITY)
	_check(is_equal_approx(_area(cut.subtract(a,b,c)),50.0),"Clearing the road invalidates the previous cut")
	output.free()
	print("TERRAIN ROAD CUT ","OK" if failures==0 else "FAILED"," failures=",failures)
	quit(0 if failures==0 else 1)
func _area(triangles: Array) -> float:
	var area := 0.0
	for triangle in triangles:
		var a := Vector2(triangle[0].x,triangle[0].z)
		var b := Vector2(triangle[1].x,triangle[1].z)
		var c := Vector2(triangle[2].x,triangle[2].z)
		area += absf((b-a).cross(c-a))*0.5
	return area
