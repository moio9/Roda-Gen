extends SceneTree

const LOCAL = preload("./fixtures/local_delaunay_cavity_probe.gd")
var failed := false
var checks := 0
var patched := 0
var fallbacks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := LOCAL.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 712451
	var points := PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)])
	for i in range(300):
		points.append(Vector2(rng.randf_range(-95, 95), rng.randf_range(-95, 95)))
	_compare(cache, points, "cold")
	_compare(cache, points, "warm")
	for i in range(40):
		points[40 + i] += Vector2(0.11, -0.13)
		_compare(cache, points, "local edit " + str(i))
		if cache.stats.full_calls == 0:
			_check(cache.stats.triangles_reused > 0 and cache.stats.triangles_rebuilt > 0, "mixed retained/rebuilt output")
	points.insert(90, Vector2(4.1, 3.7))
	_compare(cache, points, "insertion")
	points.remove_at(60)
	_compare(cache, points, "removal")
	points[0] = Vector2(-120, -120)
	_compare(cache, points, "hull changes")
	_check(cache.stats.full_calls == 1, "hull edit uses full native")
	points.reverse()
	_compare(cache, points, "input reordering")
	_check(cache.stats.fallback == "reordered_points", "reordering is not confused with an unchanged input")
	var grid := PackedVector2Array()
	for x in range(12):
		for y in range(12):
			grid.append(Vector2(x, y))
	_compare(cache, grid, "grid cold")
	grid[60] += Vector2(0.03, 0.01)
	_compare(cache, grid, "grid edit")
	_check(cache.stats.full_calls == 1 or cache.stats.ambiguous_circles > 0, "grid ties are explicitly handled")
	for trial in range(40):
		var lattice := PackedVector2Array()
		var scale := pow(10.0, (trial % 5) - 2)
		var transform := Transform2D(0.07 * trial, Vector2(7, -9))
		for x in range(10):
			for y in range(10):
				lattice.append(transform * (Vector2(x, y) * scale))
		_compare(cache, lattice, "transformed grid cold " + str(trial))
		lattice[55] += Vector2(0.03, 0.01) * scale
		_compare(cache, lattice, "transformed grid local " + str(trial))
		lattice.insert(30, transform * (Vector2(3.4, 3.6) * scale))
		_compare(cache, lattice, "transformed grid insertion " + str(trial))
	_check(patched > 10, "suite exercises actual successful local patches")
	# Interior edits in larger tied lattices, mixed with irregular samples.
	# Translation/centering are explicit and must match the same native mode.
	var stress_rng := RandomNumberGenerator.new()
	stress_rng.seed = 99117
	for trial in range(36):
		cache.condition_native = trial % 2 == 0
		var lattice := PackedVector2Array()
		var scale := pow(10.0, trial % 4 - 1)
		var offset := Vector2(317, -241) if trial % 3 == 0 else Vector2.ZERO
		for x in range(18):
			for y in range(18):
				var point := Vector2(x, y)
				if trial % 3 == 1 and x > 0 and x < 17 and y > 0 and y < 17:
					point += Vector2(stress_rng.randf_range(-0.03, 0.03), stress_rng.randf_range(-0.03, 0.03))
				lattice.append(point * scale + offset)
		_compare(cache, lattice, "tie stress cold " + str(trial))
		for edit in range(4):
			lattice[(7 + edit) * 18 + 8] += Vector2(0.03, 0.01) * scale
			_compare(cache, lattice, "tie stress edit " + str(trial) + ":" + str(edit))
	cache.condition_native = false
	for trial in range(80):
		var samples := PackedVector2Array()
		for i in range(rng.randi_range(30, 150)):
			samples.append(Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50)))
		_compare(cache, samples, "random cold " + str(trial))
		for edit in range(4):
			samples[rng.randi_range(0, samples.size() - 1)] += Vector2(0.2, -0.3)
			_compare(cache, samples, "random local " + str(trial) + ":" + str(edit))
	if OS.get_cmdline_user_args().has("--benchmark"):
		_benchmark(rng)
	cache.clear()
	_check(cache._index._triangles.is_empty() and cache._by_point.is_empty(), "clear releases geometry/index")
	var deferred := LOCAL.new()
	_check(deferred.try_patch(points, false).is_empty() and deferred.stats.full_calls == 0,
		"cold probe defers native full work to the owner")
	deferred.accept_full(points, Geometry2D.triangulate_delaunay(points), false)
	_check(deferred.matches(points, false), "accepted native result establishes a matching snapshot")
	var saved := points.duplicate()
	points[40] += Vector2(0.01, -0.02)
	_check(not deferred.matches(points, false) and deferred.matches(saved, false), "snapshot owns immutable point values")
	var direct: Dictionary = deferred.try_patch(points, false)
	_check(not direct.is_empty() and deferred.stats.full_calls == 0, "successful local patch never invokes full native triangulation")
	_check(_canonical(direct.indices) == _canonical(Geometry2D.triangulate_delaunay(points)), "deferred API preserves native geometry")
	var too_many := PackedVector2Array()
	too_many.resize(LOCAL.MAX_POINTS + 1)
	_check(deferred.try_patch(too_many, false).is_empty() and deferred.stats.fallback == "capacity"
		and deferred._index._triangles.is_empty(), "point capacity fallback releases all persistent support")
	_check(deferred._index._links == 0, "clearing releases bounded circle-cell links")
	print("LOCAL_DELAUNAY_CAVITY_%s checks=%d patched=%d fallbacks=%s" % ["FAILED" if failed else "OK", checks, patched, fallbacks])
	quit(1 if failed else 0)


func _benchmark(rng: RandomNumberGenerator) -> void:
	for count in [300, 1000, 3000]:
		var points := PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)])
		for i in range(count - 4):
			points.append(Vector2(rng.randf_range(-95, 95), rng.randf_range(-95, 95)))
		var cache := LOCAL.new()
		cache.triangulate(points)
		var full_times: Array[float] = []
		var local_times: Array[float] = []
		for i in range(7):
			points[40 + i] += Vector2(0.011, -0.013)
			var started := Time.get_ticks_usec()
			var full := Geometry2D.triangulate_delaunay(points)
			full_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
			started = Time.get_ticks_usec()
			var local: PackedInt32Array = cache.triangulate(points)
			local_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
			_check(_canonical(full) == _canonical(local), "benchmark retains native geometry")
		full_times.sort()
		local_times.sort()
		print("CAVITY_TIMING points=", count, " full_ms=", full_times[3], " local_ms=", local_times[3], " stats=", cache.stats)


func _compare(cache: RefCounted, points: PackedVector2Array, label: String) -> void:
	var full := preload("../addons/scripts/spline_road/delaunay_geometry.gd").triangulate(points, cache.condition_native)
	var local: PackedInt32Array = cache.triangulate(points)
	if not cache.stats.fallback.is_empty():
		fallbacks[cache.stats.fallback] = int(fallbacks.get(cache.stats.fallback, 0)) + 1
	var expected := _canonical(full)
	var actual := _canonical(local)
	_check(expected == actual, "native triangle set: " + label)
	if expected != actual:
		print("CAVITY_MISMATCH label=", label, " native=", full.size(), " local=", local.size(), " stats=", cache.stats)
	if cache.stats.full_calls == 0 and cache.stats.local_calls > 0:
		patched += 1


func _canonical(indices: PackedInt32Array) -> Array:
	var result: Array = []
	for i in range(0, indices.size(), 3):
		var triangle := [indices[i], indices[i + 1], indices[i + 2]]
		triangle.sort()
		result.append(str(triangle))
	result.sort()
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
