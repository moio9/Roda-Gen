extends SceneTree
const CACHE = preload("../addons/scripts/spline_road/road_normal_cache.gd")
const BUILDER = preload("../addons/scripts/spline_road/road_mesh_builder.gd")
var failed := false
var checks := 0
var native := BUILDER.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var fallback := PackedVector3Array()
	for z in range(33):
		for x in range(33):
			vertices.append(Vector3(x, sin(x * 0.13) * cos(z * 0.07), z))
			fallback.append(Vector3(0.1, 1, 0.2))
	for z in range(32):
		for x in range(32):
			var a := z * 33 + x
			indices.append_array(PackedInt32Array([a, a + 1, a + 33, a + 1, a + 34, a + 33]))
	var cache := CACHE.new()
	_compare(cache, vertices, indices, fallback, "cold")
	_compare(cache, vertices, indices, fallback, "warm")
	_check(cache.stats.patch_calls == 1 and cache.stats.vertices_rebuilt == 0, "unchanged normals skip computation")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1737
	for edit in range(40):
		var vertex := rng.randi_range(0, vertices.size() - 1)
		vertices[vertex] += Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.2, 0.2), 0)
		_compare(cache, vertices, indices, fallback, "local edit " + str(edit))
		_check(cache.stats.patch_calls == 1 and cache.stats.vertices_rebuilt < 20,
			"local normal patch does not rebuild unrelated vertices")
	# Duplicate/cancelled faces, invalid indices and incomplete final triangles.
	indices.append_array(PackedInt32Array([0, 33, 1, 0, 1, 33, -1, 1, 2, 99999, 0, 1, 0, 0, 1, 7]))
	_compare(cache, vertices, indices, fallback, "changed topology with invalid/degenerate faces")
	vertices[0] = vertices[1]
	_compare(cache, vertices, indices, fallback, "collapse formerly valid triangles")
	vertices[0] = Vector3.ZERO
	_compare(cache, vertices, indices, fallback, "restore degenerate triangles")
	indices.reverse()
	_compare(cache, vertices, indices, fallback, "changed triangle order")
	vertices.append(vertices[0])
	fallback.append(Vector3.LEFT)
	_compare(cache, vertices, indices, fallback, "new disconnected vertex at an existing position")
	_compare(cache, vertices, indices, fallback, "stable changed topology seeds adjacency")
	fallback[fallback.size() - 1] = Vector3.RIGHT
	_compare(cache, vertices, indices, fallback, "isolated fallback normal edit")
	_check(cache.stats.vertices_rebuilt == 1, "coincident but unconnected vertices do not share normals")
	_compare(cache, vertices, indices, PackedVector3Array(), "fallback removed")
	_compare(cache, vertices, indices, PackedVector3Array([Vector3.RIGHT]), "wrong-size fallback is ignored")
	_compare(cache, vertices, indices, fallback, "fallback restored")
	vertices[0] = Vector3(-0.0, 0.0, 0.0)
	_compare(cache, vertices, indices, fallback, "signed zero inputs")
	var result: PackedVector3Array = cache.compute(vertices, indices, fallback, native._compute_surface_normals_full)
	result.fill(Vector3.DOWN)
	_compare(cache, vertices, indices, fallback, "consumer cannot mutate retained normals")
	cache.clear()
	_compare(cache, vertices, indices, fallback, "explicit clear")
	_check(cache.stats.full_calls == 1, "clear removes retained adjacency")
	indices.resize(indices.size() - 3)
	_compare(cache, vertices, indices, fallback, "first topology change defers adjacency")
	_check(cache.stats.fallback == "topology_warmup" and cache._offsets.is_empty(), "changed topology uses native fallback without rebuilding adjacency")
	indices.resize(indices.size() - 3)
	_compare(cache, vertices, indices, fallback, "consecutive topology change defers again")
	_check(cache.stats.fallback == "topology_warmup" and cache._offsets.is_empty(), "unstable topology cannot allocate adjacency every edit")
	_compare(cache, vertices, indices, fallback, "repeated topology is admitted")
	_compare(cache, vertices, indices, fallback, "admitted topology reuses normals")
	_check(cache.stats.patch_calls == 1 and cache.stats.vertices_rebuilt == 0, "stable topology eventually resumes reuse")
	vertices[0] = Vector3(INF, 0, 0)
	cache.compute(vertices, indices, fallback, native._compute_surface_normals_full)
	_check(cache.stats.fallback == "nonfinite" and cache.stats.payload_bytes == 0,
		"nonfinite data bypasses persistent storage")
	vertices[0] = Vector3.ZERO
	_compare(cache, vertices, indices, fallback, "finite source after unsafe source")
	var huge := PackedVector3Array()
	huge.resize(CACHE.MAX_VERTICES + 1)
	huge.fill(Vector3.ZERO)
	_compare(cache, huge, PackedInt32Array(), PackedVector3Array(), "vertex capacity fallback")
	_check(cache.stats.fallback == "capacity" and cache.stats.payload_bytes == 0, "capacity fallback releases old storage")
	var too_many := PackedInt32Array()
	too_many.resize((CACHE.MAX_TRIANGLES + 1) * 3)
	too_many.fill(-1)
	_compare(cache, PackedVector3Array(), too_many, PackedVector3Array(), "triangle capacity fallback")
	_check(cache.stats.fallback == "capacity", "triangle ceiling enforced")
	huge.resize(CACHE.MAX_VERTICES)
	too_many.resize(220000 * 3)
	_compare(cache, huge, too_many, PackedVector3Array(), "payload capacity fallback")
	_check(cache.stats.fallback == "capacity", "byte ceiling enforced before adjacency allocation")
	_compare(cache, PackedVector3Array(), PackedInt32Array(), PackedVector3Array(), "empty mesh")
	_compare(cache, PackedVector3Array(), PackedInt32Array(), PackedVector3Array(), "empty warm mesh")
	var road: Node3D = load("res://addons/scripts/spline_road/road_network_creator.gd").new()
	road.incremental_generation_enabled = true
	var builder: RefCounted = road._mesh_builder
	builder.configure(road)
	for slot in range(6):
		builder._normal_surface_slot = slot
		var actual: PackedVector3Array = builder._compute_surface_normals_from_indices(vertices, indices, fallback)
		_check(var_to_bytes(actual) == var_to_bytes(native._compute_surface_normals_full(vertices, indices, fallback)),
			"surface slot produces native normals " + str(slot))
	_check(builder._normal_caches.size() == 5 and builder.normal_cache_stats.size() == 5, "surface stores and telemetry are capped at five")
	road.clear_source_generation_cache()
	_check(builder._normal_caches.is_empty() and builder.normal_cache_stats.is_empty(), "public road clear releases normal stores")
	builder._normal_surface_slot = 0
	builder._compute_surface_normals_from_indices(vertices, indices, fallback)
	road.incremental_generation_enabled = false
	builder.configure(road)
	_check(builder._normal_caches.is_empty() and not builder.normal_cache_enabled, "disabling incremental generation releases normal stores")
	road.free()
	print("ROAD_NORMAL_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _compare(cache: RefCounted, vertices: PackedVector3Array, indices: PackedInt32Array,
		fallback: PackedVector3Array, label: String) -> void:
	var expected: PackedVector3Array = native._compute_surface_normals_full(vertices, indices, fallback)
	var actual: PackedVector3Array = cache.compute(vertices, indices, fallback, native._compute_surface_normals_full)
	_check(var_to_bytes(actual) == var_to_bytes(expected), "native normal bytes match: " + label)
	_check(cache.stats.payload_bytes <= CACHE.MAX_BYTES, "payload bounded: " + label)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
