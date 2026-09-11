extends SceneTree

const LOCAL = preload("./fixtures/incremental_delaunay_probe.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := LOCAL.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 98123
	var points := PackedVector2Array([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)])
	for i in range(180):
		points.append(Vector2(rng.randf_range(-95, 95), rng.randf_range(-95, 95)))
	_compare(cache, points, "cold random")
	_compare(cache, points, "warm random")
	_check(cache.stats.prefix_reused == points.size() and cache.stats.circle_tests == 0, "warm skips all insertion work")
	for i in range(20):
		points[40 + i * 3] += Vector2(0.17, -0.23)
		_compare(cache, points, "local random " + str(i))
		_check(cache.stats.prefix_reused == 40 + i * 3, "unchanged prefix retained")
		_check(cache.stats.insertions_reused > 0 and cache.stats.insertions_rebuilt > 0, "suffix has mixed local recompute and exact replay")
	_compare(cache, points.slice(0, 100), "remove suffix")
	_compare(cache, points, "append suffix")
	points.insert(80, Vector2(12.34, 34.56))
	_compare(cache, points, "insert point changes suffix indices")
	points.remove_at(55)
	_compare(cache, points, "remove point changes suffix indices")
	points.reverse()
	_compare(cache, points, "reverse insertion order")
	points[0] = Vector2(200, 200)
	_compare(cache, points, "changed bounding triangle")
	var grid := PackedVector2Array()
	for x in range(12):
		for y in range(12):
			grid.append(Vector2(x * 2, y * 2))
	_compare(cache, grid, "cocircular grid")
	grid[80] += Vector2(0.1, 0.3)
	_compare(cache, grid, "local grid edit")
	_compare(cache, grid, "warm grid edit")
	grid.append(grid[30])
	_compare(cache, grid, "duplicate point")
	_compare(cache, PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(2, 2), Vector2(3, 3)]), "collinear")
	_compare(cache, PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]), "coincident")
	_compare(cache, PackedVector2Array(), "empty resets")
	_compare(cache, points, "rebuild after empty")
	for trial in range(100):
		var samples := PackedVector2Array()
		var scale := pow(10.0, (trial % 7) - 3)
		var shift := Vector2(13.0, -23.0) * scale
		for i in range(rng.randi_range(6, 80)):
			samples.append(Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)) * scale + shift)
		_compare(cache, samples, "random scaled cold " + str(trial))
		var edited := rng.randi_range(0, samples.size() - 1)
		samples[edited] += Vector2(0.31, -0.21) * scale
		_compare(cache, samples, "random scaled edit " + str(trial))
		samples.insert(edited, samples[edited] + Vector2(0.04, 0.05) * scale)
		_compare(cache, samples, "random scaled insert " + str(trial))
		samples.remove_at(rng.randi_range(0, samples.size() - 1))
		_compare(cache, samples, "random scaled remove " + str(trial))
	cache.clear()
	_check(cache._operations.is_empty() and cache._triangles.is_empty() and cache._cells.is_empty(), "clear releases replay state")
	print("INCREMENTAL_DELAUNAY_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _compare(cache: RefCounted, points: PackedVector2Array, label: String) -> void:
	var reference := Geometry2D.triangulate_delaunay(points)
	var result: PackedInt32Array = cache.triangulate(points)
	_check(result == reference, "exact native indices/order: " + label)
	if result != reference:
		print("DELAUNAY_MISMATCH ", label, " actual=", result.slice(0, 18), " expected=", reference.slice(0, 18), " stats=", cache.stats)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
