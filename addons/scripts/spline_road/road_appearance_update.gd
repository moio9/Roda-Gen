@tool
extends RefCounted
## Retains only completed final-road paint inputs. A worker or topology rebuild
## invalidates these before any shared component state can be changed.
const APPEARANCE = preload("./road_lane_appearance.gd")
var generation_signature := ""
var _pending_geometry := ""
var _pending_paint := ""
var _geometry := ""
var _paint := ""
var _overlays := ""
var _vertices := PackedVector3Array()
var _indices := PackedInt32Array()
var last_stats: Dictionary = {}


func signature(road: Node) -> String:
	return _paint_signature(road) + "|" + _overlay_signature(road)


func _paint_signature(road: Node) -> String:
	var parts: Array = [road._marking_builder.signature(road)]
	for path in road._resolve_paths():
		parts.append(APPEARANCE.paint_rules(path.get_lane_appearance_overrides()) if path.has_method("get_lane_appearance_overrides") else [])
	return str(parts)


func _overlay_signature(road: Node) -> String:
	var parts: Array = [road.left_lane_material_overrides, road.right_lane_material_overrides, road.lane_material_overlay_lift]
	for path in road._resolve_paths():
		var rules: Array = []
		if path.has_method("get_lane_appearance_overrides"):
			for rule: Dictionary in path.get_lane_appearance_overrides():
				if rule.surface_material != null:
					rules.append([rule.side, rule.lane, rule.start, rule.end, rule.surface_material])
		parts.append(rules)
	return str(parts)


func invalidate() -> void:
	_geometry = ""
	_vertices = PackedVector3Array()
	_indices = PackedInt32Array()


func begin(road: Node) -> void:
	invalidate()
	_pending_geometry = _geometry_key(road)
	_pending_paint = _paint_signature(road)
	generation_signature = road._build_signature()
	last_stats = {"mode": "full"}


func complete(road: Node, vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	_geometry = _pending_geometry
	_paint = _pending_paint
	# Overlays are assigned on the main thread using the live material settings.
	_overlays = _overlay_signature(road)
	_vertices = vertices
	_indices = indices


func sampled(road: Node) -> void:
	# Lane profiles can initialize their per-point arrays while being sampled.
	# Record that normalized source state before a worker can be dispatched.
	_pending_geometry = _geometry_key(road)
	generation_signature = road._build_signature()


func try_refresh(road: Node) -> bool:
	if _geometry.is_empty() or not road._output_ready or road._is_generation_thread_active():
		return false
	if _geometry != _geometry_key(road):
		return false
	var paint := _paint_signature(road)
	var overlays := _overlay_signature(road)
	if paint == _paint and overlays == _overlays:
		return false # An explicit unchanged Regenerate still performs a full build.
	var started := Time.get_ticks_usec()
	var paint_changed := paint != _paint
	var overlays_changed := overlays != _overlays
	if overlays_changed:
		road._update_lane_material_overlay()
	if paint_changed:
		road._marking_builder.configure(road)
		road._marking_builder.assign(road, _vertices, road._marking_rows,
			road._marking_exclusions, road._lateral_join.marking_cuts, _indices)
	_paint = paint
	_overlays = overlays
	road._last_signature = road._build_signature()
	last_stats = {"mode": "appearance", "paint_updated": paint_changed,
		"overlays_updated": overlays_changed, "build_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	return true


func _geometry_key(road: Node) -> String:
	var parts: Array = [road._build_geometry_signature()]
	for path in road._resolve_paths():
		# Manual regeneration also applies unapplied lane edits. The editor's
		# polling signature deliberately hides those until Apply Lane Changes.
		if path.has_method("_build_live_lane_signature"):
			parts.append(path._build_live_lane_signature())
		if path.curve != null:
			parts.append([path.curve.bake_interval, path.curve.up_vector_enabled, path.curve.closed])
	return str(parts)
