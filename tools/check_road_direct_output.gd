extends SceneTree
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const OUTPUT = preload("../addons/scripts/spline_road/road_runtime_output.gd")
var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var road := ROAD.new()
	road.incremental_generation_enabled = true
	road.output_mode = 1
	var properties := ["road_material_override", "shoulder_material_override", "sidewalk_material_override",
		"terrain_material_override", "outer_wall_material_override"]
	for index in range(properties.size()):
		var material := StandardMaterial3D.new()
		material.resource_name = properties[index]
		material.albedo_color = Color(float(index + 1) / 5.0, 0.25, 0.5)
		road.set(properties[index], material)
	var builder: RefCounted = road._mesh_builder
	builder.configure(road)
	var output := OUTPUT.new()
	var vertices := PackedVector3Array([Vector3(-3.125, 0.4, -5), Vector3(2.234, 1.456, 0.13),
		Vector3(0.75, -0.124, 4.234), Vector3(75, 3, 60), Vector3(84, 1, 60), Vector3(80, 2, 80)])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var uvs := PackedVector2Array()
	for vertex: Vector3 in vertices:
		uvs.append(Vector2(vertex.x * 0.05, vertex.z * 0.05))
	# Every combination of empty/nonempty lane/shoulder/sidewalk/terrain/wall
	# slots verifies that CPU material indices use compact surface order.
	for mask in range(32):
		var arguments: Array = [vertices, normals, uvs]
		var surface_count := 0
		for slot in range(5):
			var present := (mask & (1 << slot)) != 0
			arguments.append(PackedInt32Array([0, 1, 2, 3, 4, 5]) if present else PackedInt32Array())
			surface_count += int(present)
		builder.direct_output_enabled = false
		var reference: ArrayMesh = builder._build_mesh.callv(arguments)
		builder.direct_output_enabled = true
		var direct: ArrayMesh = builder._build_mesh.callv(arguments)
		_check(reference.get_surface_count() == surface_count, "native upload count " + str(mask))
		_check(direct.get_surface_count() == 0 and output._surface_count(direct) == surface_count,
			"CPU-only surface count " + str(mask))
		for surface in range(surface_count):
			_check(output._source_material(direct, surface) == reference.surface_get_material(surface),
				"material routing follows nonempty surface order")
		for size in [1.0, 10.0, 64.0]:
			output._partition_active = false
			_check(var_to_bytes(output._partition(direct, size)) == var_to_bytes(output._partition(reference, size)),
				"CPU-only partition exactly matches uploaded reference " + str(mask) + "/" + str(size))
			output._partition_active = true
			for pass_index in range(2):
				_check(var_to_bytes(output._partition(direct, size)) == var_to_bytes(output._partition_native(reference, size)),
					"cached partition preserves sparse band slots " + str(mask) + "/" + str(size) + "/" + str(pass_index))
	# The normal mesh-return contract is unchanged outside the optimized route.
	var arguments: Array = [vertices, normals, uvs, PackedInt32Array([0, 1, 2]),
		PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	road.output_mode = 0
	builder.configure(road)
	var single: ArrayMesh = builder._build_mesh.callv(arguments)
	_check(single.get_surface_count() == 1 and not single.has_meta("_roda_direct_output"), "Single Mesh remains an actual uploaded mesh")
	_check(output._partition(single, 10).size() == 1, "legacy meshes without CPU metadata still partition")
	road.output_mode = 1
	road.incremental_generation_enabled = false
	builder.configure(road)
	var disabled: ArrayMesh = builder._build_mesh.callv(arguments)
	_check(disabled.get_surface_count() == 1 and not disabled.has_meta("_roda_direct_output"), "disabled incremental mode retains the native full path")
	road.free()
	print("ROAD_DIRECT_OUTPUT_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
