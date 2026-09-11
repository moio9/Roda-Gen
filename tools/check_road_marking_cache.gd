extends SceneTree
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const CACHE = preload("../addons/scripts/spline_road/road_marking_builder.gd")
const REFERENCE = preload("./fixtures/road_marking_rows_reference.gd")
class SmallEntries extends "../addons/scripts/spline_road/road_marking_builder.gd":
	func _cache_entry_limit() -> int: return 2
class SmallBytes extends "../addons/scripts/spline_road/road_marking_builder.gd":
	func _cache_byte_limit() -> int: return 128
class SmallVertices extends "../addons/scripts/spline_road/road_marking_builder.gd":
	func _cache_vertex_limit() -> int: return 1
var failed := false
var checks := 0
var vertices := PackedVector3Array()
var paths: Array = []
var exclusions: Dictionary = {}
var road := ROAD.new()
var cache := CACHE.new()
var reference := REFERENCE.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	road.incremental_generation_enabled = true
	road.markings_enabled = true
	road.markings_center_style = 3
	road.markings_dash_offset = -2.75
	reference.cache_enabled = false
	for path in range(3):
		var rows: Array = []
		for index in range(129):
			var phase := float(index) / 128.0
			var extent := Vector2(3.5, 3.5 + phase * 3.5)
			var base := vertices.size()
			vertices.append(Vector3(path * 100 - extent.x, index * 0.1 - extent.x * 0.15, index))
			vertices.append(Vector3(path * 100 + extent.y, index * 0.1 + extent.y * 0.15, index))
			rows.append({"distance": float(index), "lane_extents": extent,
				"row_edges": [base, base, base, base + 1, base + 1, base + 1],
				"marking_layout": {"enabled": true, "lane_width": 3.5, "transition": phase,
					"left_lanes_from": 1, "left_lanes_to": 1, "right_lanes_from": 1, "right_lanes_to": 2}})
		paths.append(rows)
	_compare("cold")
	var warm := _compare("warm")
	_check(cache.last_stats.blocks_reused == 12 and cache.last_stats.pairs_rebuilt == 0, "warm skips all row-pair paint construction")
	warm.clear_surfaces()
	_compare("consumer mesh mutation")
	for edit in range(5):
		vertices[64].y += 0.03
		_compare("shared boundary vertex edit " + str(edit))
		_check(cache.last_stats.blocks_rebuilt == 2 and cache.last_stats.blocks_reused == 10,
			"boundary row invalidates both neighboring blocks only")
	for style in range(5):
		road.markings_center_style = style
		road.markings_lane_style = style
		road.markings_edge_style = style
		_compare("all styles " + str(style))
		_compare("warm style " + str(style))
	exclusions[0] = [Vector2(20.1, 25.9), Vector2(60, 70)]
	_compare("junction exclusions")
	_check(cache.last_stats.blocks_rebuilt == 4 and cache.last_stats.blocks_reused == 8, "exclusions affect only their path")
	exclusions[0].reverse()
	_compare("exclusion clipping order")
	paths[0][33].marking_layout.right_lanes_to = 3
	_compare("lane-layout dictionary edited in place")
	_check(cache.last_stats.blocks_rebuilt == 1, "local lane layout invalidates owning block")
	road.markings_surface_lift += 0.001
	_compare("surface lift")
	road.markings_dash_offset += 0.25
	_compare("dash phase")
	road.markings_center_color = Color.BLUE
	_compare("color-only edit")
	_check(cache.last_stats.blocks_rebuilt == 0, "colors do not rebuild paint geometry")
	road.markings_material_override = StandardMaterial3D.new()
	_compare("material replacement")
	_check(cache.last_stats.blocks_rebuilt == 0, "material replacement does not rebuild paint geometry")
	paths.reverse()
	_compare("path order")
	# Global vertex indices change without changing actual welded vertex values.
	vertices.insert(0, Vector3(999, 999, 999))
	for rows: Array in paths:
		for row: Dictionary in rows:
			for edge in range(row.row_edges.size()):
				row.row_edges[edge] += 1
	_compare("global vertex index rebase")
	_check(cache.last_stats.blocks_rebuilt == 0, "rebased indices still reuse exact world geometry")
	paths[0][0].erase("marking_layout")
	_compare("missing layout row")
	paths.remove_at(0)
	_compare("removed path")
	_check(cache._cache.size() <= 8, "removed path releases obsolete blocks")
	for bounded in [SmallEntries.new(), SmallBytes.new(), SmallVertices.new()]:
		cache = bounded
		_compare("capacity bypass cold")
		_compare("capacity bypass warm")
		_check(cache.last_stats.bypassed > 0 and cache._cache.size() <= cache._cache_entry_limit()
			and cache.last_stats.cache_bytes <= cache._cache_byte_limit(), "bounded retention falls back without changing geometry")
	cache = CACHE.new()
	_compare("normal cache after pressure")
	cache.clear_cache()
	_check(cache._cache.is_empty(), "clear releases records")
	_compare("after clear")
	_check(cache.last_stats.blocks_reused == 0, "clear forces reconstruction")
	road._marking_builder = cache
	road.clear_source_generation_cache()
	_check(cache._cache.is_empty(), "public road cache clear also releases paint")
	_compare("after public clear")
	road.markings_enabled = false
	cache.configure(road)
	_check(cache._cache.is_empty(), "disabling markings releases geometry records")
	road.markings_enabled = true
	_compare("markings enabled again")
	road.incremental_generation_enabled = false
	_compare("disabled incremental mode")
	_check(cache._cache.is_empty(), "disabled mode releases records")
	road.incremental_generation_enabled = true
	paths.clear()
	_compare("empty output")
	_check(cache._cache.is_empty(), "empty source releases records")
	road.free()
	print("ROAD_MARKING_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _compare(label: String) -> ArrayMesh:
	cache.configure(road)
	reference.configure(road)
	var actual: ArrayMesh = cache.build(vertices, paths, exclusions)
	var expected: ArrayMesh = reference.build(vertices, paths, exclusions)
	_check(_snapshot(actual) == _snapshot(expected), "frozen native arrays/order/materials: " + label)
	_check(cache.last_stats.cache_bytes <= cache._cache_byte_limit(), "payload bound: " + label)
	return actual


func _snapshot(mesh: ArrayMesh) -> Array:
	var result: Array = []
	for surface in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface)
		result.append([mesh.surface_get_name(surface), var_to_bytes(mesh.surface_get_arrays(surface)),
			material == road.markings_material_override if road.markings_material_override != null else material.albedo_color])
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
