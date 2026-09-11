extends SceneTree

const CACHE = preload("../addons/scripts/spline_road/terrain_stage_cache.gd")
const TOPOLOGY_CACHE = preload("../addons/scripts/spline_road/topology_stage_cache.gd")
var failed := false
var checks := 0


class CollidingTopologyCache extends TOPOLOGY_CACHE:
	func _query_key(_input: PackedByteArray) -> String:
		return "forced-collision"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := CACHE.new()
	cache.configure(true, false)
	for i in range(cache.MAX_ENTRIES):
		cache.store(cache.query("pressure", [i]), i)
	_check(cache.stats.entries == cache.MAX_ENTRIES, "fixture fills actual bounded cache")
	_check(cache.lookup(cache.query("pressure", [0])).result == 0, "lookup refreshes oldest entry")
	var start := Time.get_ticks_usec()
	for i in range(512):
		cache.store(cache.query("pressure", [cache.MAX_ENTRIES + i]), cache.MAX_ENTRIES + i)
	var cache_ms := (Time.get_ticks_usec() - start) / 1000.0
	_check(cache.stats.entries == cache.MAX_ENTRIES and cache.stats.evicted == 512, "pressure preserves capacity and exact eviction count")
	_check(cache.lookup(cache.query("pressure", [0])).result == 0, "recently touched first entry survives")
	for i in range(1, 513):
		_check(cache.lookup(cache.query("pressure", [i])).is_empty(), "least recent entries evicted in order")
	_check(cache.lookup(cache.query("pressure", [513])).result == 513, "next untouched entry survives")
	var topology := TOPOLOGY_CACHE.new()
	topology.configure(true, false)
	for i in range(topology.MAX_ENTRIES):
		topology.remember_nearest(Vector2(i, 0), 10.0, i)
	topology.remember_nearest(Vector2.ZERO, 10.0, 99)
	start = Time.get_ticks_usec()
	for i in range(512):
		topology.remember_nearest(Vector2(topology.MAX_ENTRIES + i, 0), 10.0, i)
	var hints_ms := (Time.get_ticks_usec() - start) / 1000.0
	_check(topology._nearest_hints.size() == topology.MAX_ENTRIES, "hint capacity remains bounded")
	_check(topology.nearest_hint(Vector2.ZERO, 10.0).ring == 99, "refreshed hint survives pressure")
	for i in range(1, 513):
		_check(topology.nearest_hint(Vector2(i, 0), 10.0).is_empty(), "oldest hints are evicted")
	_check(topology.nearest_hint(Vector2(513, 0), 10.0).ring == 513, "next untouched hint survives")
	cache.clear()
	topology.clear()
	_check(cache.stats.entries == 0 and cache.stats.payload_bytes == 0 and topology._nearest_hints.is_empty(), "clear releases pressure state")
	var colliding := CollidingTopologyCache.new()
	colliding.configure(true, false)
	var first_query := colliding.query("height", [Vector2.ONE, 1.0])
	var second_query := colliding.query("height", [Vector2.ONE, 2.0])
	_check(first_query.key == second_query.key, "fixture forces a bucket collision")
	colliding.store(first_query, 10.0)
	_check(colliding.lookup(first_query).result == 10.0, "exact input in collided bucket is reusable")
	_check(colliding.lookup(second_query).is_empty(), "different bytes never reuse a colliding result")
	colliding.store(second_query, 20.0)
	_check(colliding.lookup(first_query).is_empty() and colliding.lookup(second_query).result == 20.0, "replacement only loses the old cached value")
	var first_revision: int = colliding._value_revision("segment", [1])
	var second_revision: int = colliding._value_revision("segment", [2])
	var rebuilt_revision: int = colliding._value_revision("segment", [1])
	_check(first_revision < second_revision and second_revision < rebuilt_revision, "collisions cannot alias spatial revision IDs")
	colliding.clear()
	_check(colliding._value_revision("segment", [1]) > rebuilt_revision, "public clear cannot recycle a dependency revision")
	topology.configure(true, true)
	for i in range(topology.MAX_TOPOLOGY_ENTRIES + 16):
		topology.store(topology.query("small-query", [i]), i)
	_check(topology.stats.entries == topology.MAX_TOPOLOGY_ENTRIES and topology.stats.evicted == 16, "topology small-query capacity remains bounded with exact eviction")
	_check(topology.lookup(topology.query("small-query", [0])).is_empty()
		and topology.lookup(topology.query("small-query", [16])).result == 16, "expanded topology capacity retains LRU semantics")
	_check(topology.stats.payload_bytes <= topology.MAX_PAYLOAD_BYTES, "topology keeps the unchanged payload ceiling")
	topology.clear()
	_check(topology.stats.entries == 0 and topology.stats.payload_bytes == 0, "expanded topology state is released by clear")
	var payload := PackedByteArray()
	payload.resize(topology.MAX_PAYLOAD_BYTES / 2)
	var payload_first := topology.query("payload-pressure", [1])
	var payload_second := topology.query("payload-pressure", [2])
	topology.store(payload_first, payload)
	topology.store(payload_second, payload)
	_check(topology.stats.entries == 1 and topology.stats.payload_bytes <= topology.MAX_PAYLOAD_BYTES,
		"byte ceiling evicts large records before the expanded entry ceiling")
	_check(topology.lookup(payload_first).is_empty() and topology.lookup(payload_second).result.size() == payload.size(),
		"payload-pressure eviction retains the latest exact result")
	topology.clear()
	print("TERRAIN_CACHE_PRESSURE_%s checks=%s eviction_ms=%s hints_ms=%s entries=%s inserts=512" % [
		"FAILED" if failed else "OK", checks, cache_ms, hints_ms, cache.MAX_ENTRIES])
	quit(1 if failed else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
