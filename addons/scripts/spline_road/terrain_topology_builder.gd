@tool
extends Node3D
class_name TerrainTopologyBuilder3D

signal terrain_generation_completed

const DELAUNAY_GEOMETRY = preload("./delaunay_geometry.gd")

# Practical terrain topology generator for spline roads in Godot 4.
#
# Main idea:
# 1) Build road masks in XZ from Path3D / SplinePathProfile3D.
# 2) Generate terrain points around those masks.
# 3) Run Godot Delaunay.
# 4) Filter triangles that fall inside/cross road masks.
# 5) Assign height from nearest road edge + left/right terrain profiles.
#
# This is NOT a perfect Constrained Delaunay implementation, because Godot does not
# ship a CDT solver. It is a stable no-dependency approximation that is much safer
# than spline-offset strips for roads, junctions and overlapping roads.

@export_group("Road Source")
## Path3D nodes that define the road centerlines used to cut and height-fit terrain.
@export var source_paths: Array[NodePath] = []
## Optional explicit RoadNetworkCreator3D source. When empty, the builder finds
## the nearest RoadNetworkCreator3D ancestor of each source path automatically.
@export var road_network_source: NodePath
## Last-resort width when neither a spline profile nor road network defaults exist.
@export_range(0.2, 80.0, 0.1) var fallback_road_width := 6.0
## Base road sampling distance. Lower values follow bends better and cost more.
@export_range(0.1, 20.0, 0.1) var path_sample_step := 1.5

@export_group("Fallback Road Orientation")
## Used only when road_network_source is empty or cannot resolve a RoadNetworkCreator3D.
## Existing scenes keep these values for backwards compatibility.
@export_enum("Curve Up", "World Up (Y)", "Bank Into Curve") var road_orientation_mode := 0
@export_range(0.0, 45.0, 0.1, "suffix:deg") var road_bank_max_degrees := 8.0
@export_range(0.0, 4.0, 0.01) var road_bank_strength := 1.0
@export_range(0.05, 30.0, 0.05, "suffix:m") var road_bank_sample_distance := 3.0

@export_group("Terrain Height")
## Terrain-specific final height adjustment. This is applied after matching the road surface.
@export_range(-20.0, 20.0, 0.01) var y_offset := 0.0

@export_group("Adaptive Sampling")
## Adds denser road samples on tight curves while keeping straights cheaper.
@export var adaptive_path_sampling := true
## Smallest sample spacing adaptive sampling may use on tight curves.
@export_range(0.2, 5.0, 0.05, "suffix:m") var adaptive_min_path_step := 0.45
## Largest sample spacing adaptive sampling may use on straights.
@export_range(0.5, 12.0, 0.05, "suffix:m") var adaptive_max_path_step := 2.5
## Turn angle that reaches full adaptive density. Lower values densify sooner.
@export_range(1.0, 45.0, 0.5, "suffix:deg") var adaptive_full_curve_angle_degrees := 10.0

@export_group("Terrain Bounds")
## Auto follows the road/modifier extents; Manual uses the explicit center/size.
@export_enum("Auto From Roads", "Manual Rect") var bounds_mode := 0
## Extra terrain padding around roads in Auto bounds mode.
@export_range(0.0, 500.0, 0.5) var auto_outer_padding := 80.0
@export var manual_center_xz := Vector2.ZERO
@export var manual_size_xz := Vector2(256.0, 256.0)

@export_group("Terrain Sampling")
## Spacing for the broad terrain grid away from roads.
@export_range(0.5, 100.0, 0.1) var far_grid_step := 16.0
## Spacing for terrain rings near roads. Lower values reduce gaps/faceting.
@export_range(0.25, 50.0, 0.1) var near_road_step := 3.0
## Distance from road edges where near-road terrain rings are generated.
@export_range(1.0, 200.0, 0.5) var near_road_width := 42.0
## Small clearance used by road mask point tests.
@export_range(0.0, 25.0, 0.1) var road_clearance := 0.12

@export_group("Road Cut")
## Adds support points just outside the road edge. Keep on when collars are off.
@export var add_road_boundary_support_points := true
@export var invert_faces := false

@export_group("Optional Collar")
## Builds explicit terrain strips from road edge to first terrain ring.
## Leave off on tight-angle roads if collars self-intersect.
@export var generate_road_edge_collars := true
## Directional lane width transitions need a constrained first terrain band.
## Godot's unconstrained Delaunay can otherwise leave wedges beside the road.
@export var auto_lane_profile_edge_collars := true
@export_range(0.1, 10.0, 0.05, "suffix:m") var road_edge_collar_lateral_step := 0.5
@export_range(0.0, 20.0, 0.05, "suffix:m") var road_edge_collar_max_width := 0.0

@export_group("Fine Tuning")
## Margin inside the road where terrain vertices/centroids are rejected.
@export_range(0.0, 2.0, 0.01) var road_interior_reject_margin := 0.08

@export_group("Height Profiles")
## Height used far away from roads when profiles blend out.
@export_range(-500.0, 500.0, 0.01) var base_height := 0.0
## Distances from the left road edge for the terrain height profile.
@export var left_profile_distances := PackedFloat32Array([0.0, 2.0, 8.0, 18.0, 32.0])
## Heights paired with left_profile_distances.
@export var left_profile_heights := PackedFloat32Array([0.0, -0.45, 2.0, 9.0, 16.0])
## Distances from the right road edge for the terrain height profile.
@export var right_profile_distances := PackedFloat32Array([0.0, 5.0, 16.0, 35.0, 55.0])
## Heights paired with right_profile_distances.
@export var right_profile_heights := PackedFloat32Array([0.0, -1.0, -7.0, -18.0, -18.0])
## Distance used to blend the profile back to base_height past its last key.
@export_range(0.0, 200.0, 0.5) var profile_to_base_blend_distance := 30.0
@export_range(0.1, 6.0, 0.01) var profile_power := 1.0
## Keeps terrain height near the road edge blended to the road surface.
@export var lock_height_to_road_edge := true
## Distance that snaps terrain exactly to the road edge height.
@export_range(0.0, 20.0, 0.01) var road_edge_height_snap_distance := 1.0
## Distance used to blend from road edge height back to terrain profile.
@export_range(0.0, 40.0, 0.01) var road_edge_height_blend_distance := 3.0
@export_range(-5.0, 5.0, 0.001) var terrain_edge_y_offset := -0.03

@export_group("Noise")
@export var noise_enabled := true
## Terrain noise height amplitude.
@export_range(0.0, 100.0, 0.01) var noise_amplitude := 1.4
@export_range(0.001, 2.0, 0.001) var noise_frequency := 0.035
## Distance from road edge before noise starts.
@export_range(0.0, 100.0, 0.1) var noise_start_distance_from_road := 5.0
## Distance over which noise fades in after noise_start_distance_from_road.
@export_range(0.1, 100.0, 0.1) var noise_fade_distance := 18.0
@export var noise_seed := 1337

@export_group("Output")
## Reuse unchanged source queries; final surfaces are still assembled in order.
@export var incremental_generation_enabled := false
@export var terrain_material_override: Material
## Generates a trimesh collision body for the terrain mesh.
@export var generate_collision := false
## Generates terrain automatically when running in editor/tool mode.
@export var generate_in_editor := true
@export var threaded_triangulation_enabled := true
## Center only Delaunay's calculation coordinates; output uses original sample positions.
## May avoid numerical overlaps, but can change diagonals. Off preserves legacy output.
@export var centered_triangulation_enabled := false
## Experimental: total regeneration can currently be slower than native full.
## Requires incremental_generation_enabled. Retriangulates affected cavities;
## may reorder triangle buffers. Full native generation remains the fallback.
@export var local_triangulation_enabled := false
## Optional spatial output retains unchanged native mesh/collision resources.
## More chunks can increase draw calls. Source filtering still runs globally;
## native normal calculation can reuse unchanged cells and rebuild local stars.
@export_enum("Single Mesh", "Spatial Chunks") var output_mode := 0
@export_range(8.0, 512.0, 1.0, "suffix:m") var output_chunk_size := 64.0
@export var auto_regenerate_in_editor := false
@export_range(0.0, 2.0, 0.01) var editor_regenerate_debounce_seconds := 0.35
@export_tool_button("Regenerate Terrain") var regenerate_action := regenerate
@export_tool_button("Clear Generated") var clear_generated_action := _clear_generated_from_button

@export_group("Debug")
@export var debug_logs := false
@export var debug_triangle_reject_stats := false

@export_group("Height Modifiers")
## Explicit modifier nodes. Usually optional when auto_find_height_modifiers is on.
@export var height_modifiers: Array[NodePath] = []
## Finds TerrainHeightModifier children/group nodes automatically.
@export var auto_find_height_modifiers := true
@export var search_modifier_children_recursively := true
## Lets modifiers add extra topology points so raised/flattened areas are smooth.
@export var add_modifier_resolution_points := true
## Expands terrain bounds so modifier terrain is included.
@export var expand_bounds_for_modifiers := true
@export var debug_modifier_logs := false

const BUILDER_VERSION := "terrain-topology-builder"
const GENERATED_MESH_NAME := "GeneratedTopologyTerrain"
const GENERATED_BODY_NAME := "GeneratedTopologyTerrainCollision"
const EPS := 0.00001
const POINT_MERGE_EPSILON := 0.05
const MIN_TRIANGLE_AREA_XZ := 0.01
const ADD_ROAD_EDGE_POINTS := true
const ADD_NEAR_ROAD_RINGS := true
const FILTER_TRIANGLES_INSIDE_ROADS := true
const FILTER_TRIANGLES_CROSSING_ROAD_EDGES := true
const SOFT_ROAD_CROSSING_FILTER := false
const ROAD_CROSSING_SAMPLE_CLEARANCE := 0.03
const STRICT_NO_OVERLAP_NEAR_ROADS := false
const STRICT_NO_OVERLAP_MARGIN := 0.0
const REJECT_ANY_TRIANGLE_VERTEX_INSIDE_ROAD := false
const SEPARATE_TRIANGLE_ROAD_CLEARANCE := false
const TRIANGLE_ROAD_CLEARANCE := 0.20
const REJECT_TRIANGLES_NEAR_ROAD_EDGE := false
const ROAD_EDGE_REJECT_DISTANCE := 0.06
const ROAD_EDGE_VERTEX_ALLOWANCE := 0.001
const AUTO_POINT_BUDGET_HARD_CAP := 180000
# Keep this aligned with RoadNetworkCreator3D. A wider tangent probe smooths
# the frame differently from the road mesh and separates the terrain on banks.
const ROAD_MESH_FRAME_TANGENT_SAMPLE_DISTANCE := 0.1

var _last_signature := ""
var _pending_time := 0.0
var _noise := FastNoiseLite.new()
var _tracked_noise: FastNoiseLite
var _noise_input := PackedByteArray()
var _active_height_modifiers: Array = []
var _modifier_effect_checked := 0
var _modifier_effect_changed := 0
var _modifier_effect_total_abs_delta := 0.0
var _modifier_effect_max_abs_delta := 0.0
var _triangle_reject_stats := {}
var _generation_point_budget := 0
var _normal_winding_fixes := 0
var _triangulation_thread: Thread
var _triangulation_job := {}
var _triangulation_restart_requested := false
var _triangulation_discard_result := false
var _mesh_build_state := {}

const MESH_BUILD_TRIANGLES_PER_FRAME := 256

# Rebuilt for every generation. The terrain point stages and triangle filters make
# many road-distance queries; keeping the road data spatially indexed avoids
# scanning every sampled road segment for each of those queries.
var _road_spatial_cells: Dictionary = {}
var _road_spatial_cell_size := 16.0
var _road_spatial_segment_count := 0
var _road_max_half_width := 0.0
var _road_edge_cells: Dictionary = {}
var _road_polygon_edges: Array = []
var _road_edge_y_lookup: Dictionary = {}
var _cached_road_signature := ""
var _cached_road_data: Dictionary = {}
var _active_generate_road_edge_collars := false
var _source_cache = preload("./topology_stage_cache.gd").new()
var _triangle_cache = preload("./topology_triangle_cache.gd").new()
var _collar_cache = preload("./topology_collar_cache.gd").new()
var _point_cache = preload("./topology_point_cache.gd").new()
var _path_cache = preload("./topology_path_cache.gd").new()
var _mesh_stream = preload("./topology_mesh_stream.gd").new()
var _last_triangle_reject_reason := ""
var _source_cache_clear_requested := false
var _local_delaunay = preload("./delaunay_cavity_cache.gd").new()
var _triangulation_context: Dictionary = {}
var _stage_times: Dictionary = {}
var _collar_sample_stats: Dictionary = {}
var _output_cache = preload("./topology_output_cache.gd").new()
var _output_context: Dictionary = {}
var _output_published := false


func _ready() -> void:
	set_process(true)
	_configure_noise()
	if Engine.is_editor_hint() and generate_in_editor and not source_paths.is_empty():
		if auto_regenerate_in_editor and _road_sources_pending():
			return
		_last_signature = _build_signature()
		regenerate()


func _exit_tree() -> void:
	_path_cache.clear()
	_mesh_stream.clear()
	_point_cache.clear()
	_collar_cache.clear()
	_triangle_cache.clear()
	_output_cache.clear()
	if _triangulation_thread != null:
		_triangulation_thread.wait_to_finish()
		_triangulation_thread = null
		_triangulation_job = {}
	_mesh_build_state = {}


func _process(delta: float) -> void:
	_poll_triangulation_thread()
	_process_mesh_build()
	if not Engine.is_editor_hint():
		return
	if _is_generation_thread_active():
		return
	if not auto_regenerate_in_editor:
		return
	var sig := _build_signature()
	if sig == _last_signature:
		_pending_time = 0.0
		return
	# Native road sampling changes the shared Curve3D bake interval. Wait for
	# its debounced/worker update before freezing terrain samples, so props see
	# the same road -> terrain sampling order after edits, Undo and full builds.
	if _road_sources_pending():
		return
	_pending_time -= delta
	if _pending_time <= 0.0:
		_last_signature = sig
		_pending_time = maxf(0.0, editor_regenerate_debounce_seconds)
		regenerate()


func _clear_generated_from_button() -> void:
	_path_cache.clear()
	_mesh_stream.clear()
	_point_cache.clear()
	_collar_cache.clear()
	_triangle_cache.clear()
	_triangulation_restart_requested = false
	_triangulation_discard_result = _is_generation_thread_active()
	_mesh_build_state = {}
	_clear_generated()


func regenerate() -> void:
	if _is_generation_thread_active():
		_triangulation_restart_requested = true
		return
	_mesh_stream.clear()
	var stage_start := Time.get_ticks_usec()
	_stage_times = {}
	_collar_sample_stats = {}
	_output_published = false
	_output_context = {"chunked": output_mode == 1 and get_script().get_base_script() == null,
		"cell_size": output_chunk_size, "reuse": incremental_generation_enabled}
	_configure_noise()
	# Chunked output keeps the last complete result visible/physical while work
	# is pending. Publication replaces only changed cells; Clear still removes all.
	if not _output_context.chunked:
		_clear_generated()

	_log("VERSION: %s" % BUILDER_VERSION)
	_active_height_modifiers = _collect_height_modifiers()
	# Modifiers receive this builder and road-info Dictionaries. Without a
	# read-only dependency contract, their side effects cannot be replayed safely.
	_source_cache.configure(incremental_generation_enabled and get_script().get_base_script() == null
		and _active_height_modifiers.is_empty(), _source_cache_clear_requested)
	_triangle_cache.configure(_source_cache.enabled, _source_cache_clear_requested)
	_collar_cache.configure(_source_cache.enabled, _source_cache_clear_requested)
	_point_cache.configure(_source_cache.enabled, _source_cache_clear_requested)
	_path_cache.configure(_source_cache.enabled, _source_cache_clear_requested)
	_source_cache.stats["modifier_bypass"] = not _active_height_modifiers.is_empty()
	if _source_cache_clear_requested:
		_output_cache.clear()
	if _source_cache_clear_requested or not _source_cache.enabled or not local_triangulation_enabled:
		_local_delaunay.clear()
	_local_delaunay.stats = {}
	_source_cache_clear_requested = false
	_modifier_effect_checked = 0
	_modifier_effect_changed = 0
	_modifier_effect_total_abs_delta = 0.0
	_modifier_effect_max_abs_delta = 0.0
	_normal_winding_fixes = 0
	_triangle_reject_stats = {
		"area": 0,
		"edge": 0,
		"inside_centroid": 0,
		"inside_vertex": 0,
		"crossing": 0,
		"near_edge": 0,
	}

	# Multi-frame assembly owns frozen road/profile values, independent of
	# Inspector edits or modifier callbacks touching the persistent road cache.
	stage_start = _time_stage("setup_ms", stage_start)
	var road_data := _get_cached_road_data().duplicate(true)
	var road_rows: Array = road_data.get("rows", [])
	var road_segments: Array = road_data.get("segments", [])
	var road_polygons: Array = road_data.get("polygons", [])
	stage_start = _time_stage("road_data_ms", stage_start)
	if road_rows.is_empty() or road_segments.is_empty():
		_log("No valid road paths found.")
		_finish_generation_or_restart()
		return
	_active_generate_road_edge_collars = generate_road_edge_collars or (
		auto_lane_profile_edge_collars and _road_data_has_directional_lane_profile(road_data)
	)
	_build_road_spatial_index(road_segments, road_polygons)
	_build_road_edge_y_lookup(road_data)
	stage_start = _time_stage("spatial_ms", stage_start)
	_log("Road spatial index: %d segments, %d segment cells, %d road-edge cells, %d edge-y entries." % [road_segments.size(), _road_spatial_cells.size(), _road_edge_cells.size(), _road_edge_y_lookup.size()])

	var bounds := _compute_bounds(road_polygons)
	if expand_bounds_for_modifiers and not _active_height_modifiers.is_empty():
		bounds = _expand_bounds_for_height_modifiers(bounds, _active_height_modifiers)
	_generation_point_budget = _resolve_generation_point_budget(bounds, road_data)
	_log("Point budget from sampling: %d" % _generation_point_budget)
	var points := PackedVector2Array()
	var point_keys := {}
	var point_limit := _point_budget_limit()

	# Priority order matters. Road/bounds/grid points define the required
	# continuous topology. Modifier points are detail points and must not consume
	# the point budget before the base terrain coverage is complete.
	if ADD_ROAD_EDGE_POINTS:
		_add_road_boundary_points(points, point_keys, road_data, road_segments)
		_log("Point stage road boundary: %d / %d" % [points.size(), point_limit])
	if ADD_NEAR_ROAD_RINGS:
		_add_near_road_points(points, point_keys, road_data, road_segments)
		_log("Point stage near-road rings: %d / %d" % [points.size(), point_limit])
	_add_bounds_points(points, point_keys, bounds)
	_log("Point stage bounds: %d / %d" % [points.size(), point_limit])
	_add_far_grid_points(points, point_keys, bounds, road_segments)
	_log("Point stage far grid: %d / %d" % [points.size(), point_limit])
	if add_modifier_resolution_points and not _active_height_modifiers.is_empty():
		_add_modifier_resolution_points_around_modifiers(points, point_keys, road_segments, _active_height_modifiers)
		_log("Point stage modifier resolution: %d / %d" % [points.size(), point_limit])
	_log("Point stage final: %d / %d" % [points.size(), point_limit])
	stage_start = _time_stage("points_ms", stage_start)

	if points.size() < 3:
		_log("Not enough terrain points.")
		_finish_generation_or_restart()
		return
	if points.size() > point_limit:
		_log("Point count is high (%d). Increase steps or reduce bounds. Clamping is not applied because it would break topology." % points.size())

	_triangulation_context = {"centered": centered_triangulation_enabled,
		"local": local_triangulation_enabled and _source_cache.enabled,
		"canonical": local_triangulation_enabled and get_script().get_base_script() == null
			and _active_height_modifiers.is_empty()}
	var triangulation_query: Dictionary = _source_cache.query("topology_delaunay", [points,
		_triangulation_context.centered, _triangulation_context.local])
	var cached_triangles: Dictionary = _source_cache.lookup(triangulation_query)
	if not cached_triangles.is_empty():
		_source_cache.stats.delaunay_reused += 1
		_time_stage("triangulation_main_ms", stage_start)
		_finalize_triangulation(points, cached_triangles.result.duplicate(), road_segments, road_polygons, road_data)
		return
	if _triangulation_context.local:
		var patch: Dictionary = _local_delaunay.try_patch(points, _triangulation_context.centered)
		if not patch.is_empty():
			_source_cache.stats.delaunay_reused += 1
			_source_cache.store(triangulation_query, patch.indices.duplicate())
			_time_stage("triangulation_main_ms", stage_start)
			_finalize_triangulation(points, patch.indices, road_segments, road_polygons, road_data)
			return
	_source_cache.stats.delaunay_rebuilt += 1
	if threaded_triangulation_enabled:
		_start_triangulation(points, road_segments, road_polygons, road_data, triangulation_query)
		_time_stage("triangulation_dispatch_ms", stage_start)
		return
	var indices := DELAUNAY_GEOMETRY.triangulate(points, _triangulation_context.centered)
	if _source_cache.enabled:
		_source_cache.store(triangulation_query, indices.duplicate())
	_time_stage("triangulation_main_ms", stage_start)
	_finalize_triangulation(points, indices, road_segments, road_polygons, road_data)


func _start_triangulation(points: PackedVector2Array, road_segments: Array, road_polygons: Array, road_data: Dictionary, cache_query: Dictionary = {}) -> void:
	var thread_points := points.duplicate()
	var centered: bool = _triangulation_context.centered
	_triangulation_job = {
		"points": points,
		"road_segments": road_segments,
		"road_polygons": road_polygons,
		"road_data": road_data,
		"cache_query": cache_query,
	}
	_triangulation_discard_result = false
	_triangulation_thread = Thread.new()
	var error := _triangulation_thread.start(_triangulate_points_thread.bind(thread_points, centered))
	if error != OK:
		_log("Could not start triangulation thread (%s); using the main thread." % error_string(error))
		_triangulation_thread = null
		_triangulation_job = {}
		_finalize_triangulation(points, DELAUNAY_GEOMETRY.triangulate(points, centered), road_segments, road_polygons, road_data)
		return
	_log("Triangulating %d terrain points in background." % points.size())


static func _triangulate_points_thread(points: PackedVector2Array, centered := false) -> PackedInt32Array:
	return DELAUNAY_GEOMETRY.triangulate(points, centered)


func _poll_triangulation_thread() -> void:
	if _triangulation_thread == null:
		return
	if _triangulation_thread.is_alive():
		return
	var indices: PackedInt32Array = _triangulation_thread.wait_to_finish()
	_triangulation_thread = null
	var job := _triangulation_job
	_triangulation_job = {}
	if _triangulation_restart_requested:
		_triangulation_restart_requested = false
		_triangulation_discard_result = false
		regenerate()
		return
	if _triangulation_discard_result:
		_triangulation_discard_result = false
		return
	if _source_cache.enabled:
		_source_cache.store(job.get("cache_query", {}), indices.duplicate())
	_finalize_triangulation(job["points"], indices, job["road_segments"], job["road_polygons"], job["road_data"])


func _is_generation_thread_active() -> bool:
	return _triangulation_thread != null or not _mesh_build_state.is_empty()


func _finalize_triangulation(points: PackedVector2Array, indices: PackedInt32Array, road_segments: Array, road_polygons: Array, road_data: Dictionary) -> void:
	var stage_start := Time.get_ticks_usec()
	if _triangulation_context.get("local", false) and not _local_delaunay.matches(points, _triangulation_context.centered):
		_local_delaunay.accept_full(points, indices, _triangulation_context.centered)
	if _triangulation_context.get("canonical", false):
		indices = _canonical_triangle_order(indices)
	_time_stage("topology_finalize_ms", stage_start)
	if indices.size() < 3:
		_log("Delaunay failed or returned no triangles.")
		_finish_generation_or_restart()
		return
	_mesh_build_state = {
		"points": points,
		"indices": indices,
		"road_segments": road_segments,
		"road_polygons": road_polygons,
		"road_data": road_data,
		"surface_tool": _new_terrain_surface_tool(),
		"cursor": 0,
		"triangle_count": 0,
		"road_info_cache": {},
		"vertex_cache": {},
	}
	var group_start := Time.get_ticks_usec()
	_mesh_stream.begin(_mesh_build_state["surface_tool"], _source_cache.enabled)
	_mesh_build_state["triangle_groups"] = _triangle_cache.prepare(points, indices)
	_mesh_build_state["triangle_settings"] = _triangle_cache_settings()
	_time_stage("triangle_groups_ms", group_start)
	_log("Filtering and height-fitting %d triangles incrementally." % (indices.size() / 3))


func _new_terrain_surface_tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _canonical_triangle_order(indices: PackedInt32Array) -> PackedInt32Array:
	# Smooth-normal accumulation must see the same triangle order in the full
	# and local paths. This order is opt-in; legacy output remains untouched.
	var triangles: Array[Vector3i] = []
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		triangles.append(Vector3i(mini(a, mini(b, c)), a + b + c - mini(a, mini(b, c)) - maxi(a, maxi(b, c)), maxi(a, maxi(b, c))))
	triangles.sort()
	var result := PackedInt32Array()
	for triangle: Vector3i in triangles:
		result.append_array(PackedInt32Array([triangle.x, triangle.y, triangle.z]))
	return result


func _process_mesh_build() -> void:
	if _mesh_build_state.is_empty():
		return
	if _triangulation_restart_requested:
		# A requested rebuild must not finish old points with newly edited
		# Inspector settings or publish a mixed-generation mesh/cache result.
		_mesh_build_state = {}
		_triangulation_restart_requested = false
		regenerate()
		return
	var stage_start := Time.get_ticks_usec()
	var state := _mesh_build_state
	var points: PackedVector2Array = state["points"]
	var indices: PackedInt32Array = state["indices"]
	var road_segments: Array = state["road_segments"]
	var road_polygons: Array = state["road_polygons"]
	var st: SurfaceTool = state["surface_tool"]
	var road_info_cache: Dictionary = state["road_info_cache"]
	var vertex_cache: Dictionary = state["vertex_cache"]
	var cursor := int(state["cursor"])
	var end := mini(indices.size(), cursor + MESH_BUILD_TRIANGLES_PER_FRAME * 3)
	var tri_count := int(state["triangle_count"])
	var grouped: Dictionary = state["triangle_groups"]
	if not grouped.is_empty() and state["triangle_settings"] != _triangle_cache_settings():
		# Do not publish records assembled under more than one live setting set.
		# Sampled road/profile values remain owned by this job, as before.
		state["triangle_groups"] = {}
		grouped = {}
		_triangle_cache.stats.fallback = "settings_changed_during_assembly"
	var i := cursor
	while i < end:
		var triangle_index := i / 3
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		i += 3
		if ia < 0 or ib < 0 or ic < 0 or ia >= points.size() or ib >= points.size() or ic >= points.size():
			continue
		var a := points[ia]
		var b := points[ib]
		var c := points[ic]
		var group: Dictionary = {}
		var slot := 0
		if not grouped.is_empty():
			group = grouped.groups[grouped.ids[triangle_index]]
			slot = grouped.slots[triangle_index]
			if not group.has("hit"):
				var edge_heights: Array = []
				for point: Vector2 in group.points:
					var eps := maxf(0.0001, POINT_MERGE_EPSILON)
					edge_heights.append(_road_edge_y_lookup.get(Vector2i(roundi(point.x / eps), roundi(point.y / eps)), null))
				_triangle_cache.resolve(group, state["triangle_settings"], edge_heights, _source_cache)
			if group.hit and _mesh_stream.target != null:
				var count := mini(grouped.ends[triangle_index], end / 3) - triangle_index
				var replay: Dictionary = _triangle_cache.emit_run(group, slot, count, invert_faces, _mesh_stream, st)
				if not replay.is_empty():
					tri_count += replay.triangles
					_normal_winding_fixes += replay.winding
					for reason: String in replay.rejections:
						_triangle_reject_stats[reason] = int(_triangle_reject_stats.get(reason, 0)) + replay.rejections[reason]
					if not replay.last_reason.is_empty():
						_last_triangle_reject_reason = replay.last_reason
					i += (count - 1) * 3
					continue
		var accepted := false
		var va := Vector3.ZERO
		var vb := Vector3.ZERO
		var vc := Vector3.ZERO
		if not group.is_empty() and group.hit:
			_triangle_cache.stats.triangles_reused += 1
			accepted = group.accepted[slot] != 0
			if accepted:
				va = group.vertices[slot * 3]
				vb = group.vertices[slot * 3 + 1]
				vc = group.vertices[slot * 3 + 2]
			elif not group.reasons[slot].is_empty():
				_reject_triangle(group.reasons[slot])
		else:
			if not group.is_empty():
				_source_cache.begin_mesh_scope(group.scope)
			var a_road_info := _get_cached_road_info(ia, a, road_segments, road_info_cache)
			var b_road_info := _get_cached_road_info(ib, b, road_segments, road_info_cache)
			var c_road_info := _get_cached_road_info(ic, c, road_segments, road_info_cache)
			_last_triangle_reject_reason = ""
			accepted = _is_valid_triangle_2d(a, b, c, a_road_info, b_road_info, c_road_info, road_segments, road_polygons)
			if accepted:
				va = _get_cached_vertex(ia, a, a_road_info, vertex_cache)
				vb = _get_cached_vertex(ib, b, b_road_info, vertex_cache)
				vc = _get_cached_vertex(ic, c, c_road_info, vertex_cache)
			if not group.is_empty():
				_triangle_cache.record(group, slot, accepted, _last_triangle_reject_reason, va, vb, vc, _source_cache, invert_faces)
		if accepted:
			_add_terrain_triangle(st, va, vb, vc, a, b, c)
			tri_count += 1
	state["cursor"] = end
	state["triangle_count"] = tri_count
	_mesh_build_state = state
	stage_start = _time_stage("filter_emit_ms", stage_start)
	if end < indices.size():
		return

	if _active_generate_road_edge_collars:
		tri_count += _append_road_edge_collars(st, state["road_data"], road_segments)
	stage_start = _time_stage("collars_ms", stage_start)
	var raw_arrays: Array = _mesh_stream.take_arrays(st) if _output_context.get("chunked", false) else []
	if raw_arrays.is_empty():
		_mesh_stream.flush()
	stage_start = _time_stage("stream_flush_ms", stage_start)
	_mesh_build_state = {}
	if tri_count <= 0:
		_log("No valid terrain triangles after filtering.")
		_finish_generation_or_restart()
		return
	if _output_context.get("chunked", false):
		var local_normals: bool = _output_context.reuse and _active_height_modifiers.is_empty()
		var published: bool
		if raw_arrays.is_empty():
			published = _output_cache.publish_surface(self, st, _output_context.cell_size, _output_context.reuse,
				generate_collision, terrain_material_override, local_normals)
		else:
			published = _output_cache.publish_raw(self, raw_arrays, _output_context.cell_size, _output_context.reuse,
				generate_collision, terrain_material_override, local_normals)
		if published:
			_output_published = true
			_time_stage("chunk_publish_ms", stage_start)
			_finish_generation_or_restart()
			return
		# Unsupported streams/cell counts retain the full native output fallback.
		var fallback_stats: Dictionary = _output_cache.stats.duplicate()
		_clear_generated()
		_output_cache.stats = fallback_stats
		if not raw_arrays.is_empty():
			st.create_from_arrays(raw_arrays, Mesh.PRIMITIVE_TRIANGLES)
			_output_cache.stats.source_surface_builds = int(_output_cache.stats.get("source_surface_builds", 0)) + 1
	st.generate_normals()
	var mesh := st.commit()
	stage_start = _time_stage("normals_commit_ms", stage_start)
	if mesh == null or mesh.get_surface_count() <= 0:
		_log("No valid terrain triangles after filtering.")
		_finish_generation_or_restart()
		return

	var mi := MeshInstance3D.new()
	mi.name = GENERATED_MESH_NAME
	mi.mesh = mesh
	if terrain_material_override != null:
		mi.material_override = terrain_material_override
	add_child(mi)
	mi.owner = get_tree().edited_scene_root if Engine.is_editor_hint() and get_tree() != null else null
	stage_start = _time_stage("publish_ms", stage_start)

	if generate_collision:
		_create_collision(mesh)
	_time_stage("collision_ms", stage_start)
	_output_published = true

	if debug_triangle_reject_stats:
		_log("Triangle reject stats: %s" % str(_triangle_reject_stats))
	_log("Modifier height effect: checked=%d, changed=%d, total_abs_delta=%.3f, max_abs_delta=%.3f" % [_modifier_effect_checked, _modifier_effect_changed, _modifier_effect_total_abs_delta, _modifier_effect_max_abs_delta])
	_log("Normal winding corrections: %d" % _normal_winding_fixes)
	_log("Generated topology terrain: %d points, %d raw triangles, %d modifiers." % [points.size(), indices.size() / 3, _active_height_modifiers.size()])
	_finish_generation_or_restart()


func _finish_generation_or_restart() -> void:
	if _triangulation_restart_requested:
		_triangulation_restart_requested = false
		regenerate()
	else:
		if not _output_published and _output_context.get("chunked", false):
			_clear_generated()
		terrain_generation_completed.emit()


func _collect_height_modifiers(prepare_modifiers := true) -> Array:
	var out: Array = []
	var seen := {}

	_modifier_log("Modifier scan start...")

	for np in height_modifiers:
		var node := get_node_or_null(np)
		_try_add_height_modifier(node, out, seen, "exported height_modifiers", prepare_modifiers)

	if auto_find_height_modifiers:
		if search_modifier_children_recursively:
			_modifier_log("Modifier child recursive scan under builder...")
			_scan_modifier_children_recursive(self, out, seen, prepare_modifiers)
		else:
			_modifier_log("Modifier direct child scan under builder...")
			for child in get_children():
				_try_add_height_modifier(child, out, seen, "direct child", prepare_modifiers)

		if get_tree() != null:
			var group_nodes := get_tree().get_nodes_in_group("terrain_height_modifier")
			_modifier_log("Modifier group scan: terrain_height_modifier count=%d" % group_nodes.size())
			for node in group_nodes:
				_try_add_height_modifier(node, out, seen, "group terrain_height_modifier", prepare_modifiers)

	var names: Array[String] = []
	for m in out:
		if m != null:
			names.append(str(m.name))
	_modifier_log("Height modifiers ACCEPTED: %d %s" % [out.size(), str(names)])
	return out


func _scan_modifier_children_recursive(node: Node, out: Array, seen: Dictionary, prepare_modifiers: bool) -> void:
	for child in node.get_children():
		_try_add_height_modifier(child, out, seen, "recursive child of %s" % node.name, prepare_modifiers)
		_scan_modifier_children_recursive(child, out, seen, prepare_modifiers)


func _try_add_height_modifier(node: Node, out: Array, seen: Dictionary, source: String, prepare_modifiers: bool) -> void:
	if node == null:
		return
	if node == self:
		return
	var id := node.get_instance_id()
	if seen.has(id):
		return

	var has_modify := node.has_method("modify_height")
	var in_group := node.is_in_group("terrain_height_modifier")
	var type_ok := has_modify or in_group
	_modifier_log("Modifier candidate source=%s name=%s class=%s has_modify=%s in_group=%s" % [source, node.name, node.get_class(), str(has_modify), str(in_group)])
	if not type_ok:
		return

	var enabled_value = node.get("enabled")
	if enabled_value != null and bool(enabled_value) == false:
		_modifier_log("Modifier rejected disabled: %s" % node.name)
		return

	if prepare_modifiers and node.has_method("prepare_for_terrain_builder"):
		node.call("prepare_for_terrain_builder")

	seen[id] = true
	out.append(node)
	_modifier_log("Modifier accepted: %s path=%s" % [node.name, str(get_path_to(node))])


func _expand_bounds_for_height_modifiers(bounds: Rect2, modifiers: Array) -> Rect2:
	var out := bounds
	for modifier in modifiers:
		if modifier != null and modifier.has_method("get_bounds_in_builder_space"):
			var rect: Rect2 = modifier.call("get_bounds_in_builder_space", self)
			if rect.size.x > 0.001 and rect.size.y > 0.001:
				out = out.merge(rect)
				_modifier_log("Bounds expanded by modifier %s rect=%s" % [modifier.name, str(rect)])
	return out


func _add_modifier_resolution_points_around_modifiers(points: PackedVector2Array, point_keys: Dictionary, road_segments: Array, modifiers: Array) -> void:
	var before := points.size()
	for modifier in modifiers:
		if points.size() >= _point_budget_limit():
			return
		if modifier == null or not modifier.has_method("get_resolution_points_in_builder_space"):
			continue
		var arr: PackedVector2Array = modifier.call("get_resolution_points_in_builder_space", self)
		_modifier_log("Modifier %s resolution candidates=%d" % [modifier.name, arr.size()])
		for p in arr:
			if points.size() >= _point_budget_limit():
				return
			if not _is_inside_road_mask(p, road_segments, road_clearance * 0.5):
				_add_unique_point(points, point_keys, p)
	var added := points.size() - before
	_modifier_log("Modifier resolution points added: %d" % added)


func _apply_height_modifiers(p: Vector2, current_y: float, road_info: Dictionary) -> float:
	if _active_height_modifiers.is_empty():
		return current_y
	var y := current_y
	for modifier in _active_height_modifiers:
		if modifier == null or not modifier.has_method("modify_height"):
			continue
		_modifier_effect_checked += 1
		var before := y
		y = float(modifier.call("modify_height", self, p, y, road_info))
		var delta := absf(y - before)
		if delta > 0.0001:
			_modifier_effect_changed += 1
			_modifier_effect_total_abs_delta += delta
			_modifier_effect_max_abs_delta = maxf(_modifier_effect_max_abs_delta, delta)
	return y


func _modifier_log(message: String) -> void:
	if debug_logs and debug_modifier_logs:
		print("[TerrainTopologyBuilder3D] ", message)


func _get_cached_road_data() -> Dictionary:
	var road_signature := _build_road_signature()
	if road_signature == _cached_road_signature and not _cached_road_data.is_empty():
		_path_cache.retain_collection()
		_log("Road data cache hit.")
		return _cached_road_data
	var road_data := _collect_road_data()
	# Native collection owns its rows, segments and polygons, including detached
	# path-cache hits. Do not clone that entire value graph a second time here.
	# Subclasses may return borrowed data; the worker still receives its separate
	# frozen copy in regenerate(), regardless of this native collection shortcut.
	if get_script().get_base_script() != null:
		road_data = road_data.duplicate(true)
	_cached_road_signature = road_signature
	_cached_road_data = road_data
	# The same segment count does not prove that an old spatial index belongs
	# to these newly sampled roads (also used by external terrain-height queries).
	_road_spatial_cells.clear()
	_road_edge_cells.clear()
	_road_edge_y_lookup.clear()
	_source_cache.spatial_ready = false
	_log("Road data cache rebuilt.")
	return road_data


## Explicit edge rebuilds can intentionally leave the heavy-dependent revision
## unchanged so props and deformers are not regenerated. Terrain still needs to
## resample the live lane extents instead of reusing its previous road cutout.
func invalidate_road_data_cache() -> void:
	_cached_road_signature = ""
	_cached_road_data = {}
	if not _is_generation_thread_active():
		_road_spatial_cells.clear()
		_road_edge_cells.clear()
		_road_edge_y_lookup.clear()
		_source_cache.spatial_ready = false


func clear_source_generation_cache() -> void:
	if _is_generation_thread_active():
		_source_cache_clear_requested = true
	else:
		_path_cache.clear()
		_source_cache.clear()
		_triangle_cache.clear()
		_collar_cache.clear()
		_point_cache.clear()
		_mesh_stream.clear()
		_local_delaunay.clear()
		_output_cache.clear()


func get_source_rebuild_stats() -> Dictionary:
	var result: Dictionary = _source_cache.stats.duplicate(true)
	result["pending"] = _is_generation_thread_active()
	result["local_triangulation"] = _local_delaunay.stats.duplicate(true)
	result["stage_ms"] = _stage_times.duplicate()
	result["collar_samples"] = _collar_sample_stats.duplicate()
	result["output"] = _output_cache.stats.duplicate()
	result["triangle_groups"] = _triangle_cache.stats.duplicate()
	result["collar_groups"] = _collar_cache.stats.duplicate()
	result["point_groups"] = _point_cache.stats.duplicate(true)
	result["mesh_stream"] = _mesh_stream.stats.duplicate()
	result["path_samples"] = _path_cache.stats.duplicate(true)
	return result


func _time_stage(stage: String, started: int) -> int:
	var finished := Time.get_ticks_usec()
	_stage_times[stage] = float(_stage_times.get(stage, 0.0)) + float(finished - started) / 1000.0
	return finished


func _collect_road_data() -> Dictionary:
	_path_cache.begin_collection()
	var all_rows: Array = []
	var all_segments: Array = []
	var all_polygons: Array = []
	var path_id := 0

	for np in source_paths:
		var node := get_node_or_null(np)
		if node == null or not (node is Path3D):
			continue
		var path := node as Path3D
		var curve := path.curve
		if curve == null or curve.point_count <= 0:
			continue
		var length := curve.get_baked_length()
		if length <= 0.001:
			continue

		var bake_step := path_sample_step
		if adaptive_path_sampling:
			bake_step = minf(path_sample_step, adaptive_min_path_step)
		curve.bake_interval = maxf(0.05, bake_step)

		var path_transform := path.global_transform
		var builder_inverse := global_transform.affine_inverse()
		# Keep the legacy pre-bake length above: other generators may share this
		# Curve3D with a different bake interval. It is an exact cache dependency.
		var data: Dictionary = _path_cache.collect_path(self, path, curve, length, path_id, path_transform, builder_inverse)
		if data.rows.size() < 2:
			continue
		all_polygons.append(data.polygon)
		all_rows.append_array(data.rows)
		all_segments.append_array(data.segments)
		path_id += 1

	return {
		"rows": all_rows,
		"segments": all_segments,
		"polygons": all_polygons,
	}


func _get_adaptive_path_step(
	curve: Curve3D,
	dist: float,
	length: float,
	path_transform: Transform3D,
	builder_inverse: Transform3D
) -> float:
	if not adaptive_path_sampling:
		return maxf(0.1, path_sample_step)

	var min_step := maxf(0.1, adaptive_min_path_step)
	var max_step := maxf(min_step, adaptive_max_path_step)
	var probe := maxf(min_step, max_step * 0.75)

	var d0 := maxf(0.0, dist - probe)
	var d1 := clampf(dist, 0.0, length)
	var d2 := minf(length, dist + probe)

	if absf(d1 - d0) < 0.001 or absf(d2 - d1) < 0.001:
		return max_step

	var p0: Vector3 = builder_inverse * (path_transform * curve.sample_baked(d0, true))
	var p1: Vector3 = builder_inverse * (path_transform * curve.sample_baked(d1, true))
	var p2: Vector3 = builder_inverse * (path_transform * curve.sample_baked(d2, true))

	var a := Vector2(p1.x - p0.x, p1.z - p0.z)
	var b := Vector2(p2.x - p1.x, p2.z - p1.z)
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return max_step

	a = a.normalized()
	b = b.normalized()

	var angle := acos(clampf(a.dot(b), -1.0, 1.0))
	var full_angle := deg_to_rad(maxf(1.0, adaptive_full_curve_angle_degrees))
	var t := clampf(angle / full_angle, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)

	return lerpf(max_step, min_step, t)


func _sample_road_row(path: Path3D, curve: Curve3D, dist: float, length: float, path_id: int, path_transform: Transform3D, builder_inverse: Transform3D) -> Dictionary:
	var p_local := curve.sample_baked(dist, true)
	var p_world := path_transform * p_local
	var p := builder_inverse * p_world
	var right := Vector3.RIGHT
	var road_vertical_axis := Vector3.UP
	var road_surface_frame := _road_network_surface_frame(path, dist, builder_inverse)
	if not road_surface_frame.is_empty():
		p = road_surface_frame.get("center", p)
		right = road_surface_frame.get("right", right)
		road_vertical_axis = road_surface_frame.get("vertical", road_vertical_axis)
	else:
		var road_vertical_offset := _road_network_vertical_offset_in_builder_space()
		p += road_vertical_offset

	# Match RoadNetworkCreator3D's mesh-frame probe exactly. The terrain uses
	# this frame both for its cut outline and for sampling the road surface Y.
	if road_surface_frame.is_empty():
		var frame_probe := ROAD_MESH_FRAME_TANGENT_SAMPLE_DISTANCE
		var prev_dist := maxf(0.0, dist - frame_probe)
		var next_dist := minf(length, dist + frame_probe)
		if is_equal_approx(prev_dist, next_dist):
			if next_dist < length:
				next_dist = minf(length, next_dist + frame_probe)
			elif prev_dist > 0.0:
				prev_dist = maxf(0.0, prev_dist - frame_probe)

		var p_prev := builder_inverse * (path_transform * curve.sample_baked(prev_dist, true))
		var p_next := builder_inverse * (path_transform * curve.sample_baked(next_dist, true))
		var frame := _resolve_road_frame(curve, path_transform, builder_inverse, dist, length, p, p_prev, p_next)
		right = frame.get("right", right)
	var terrain_profile := _resolve_path_terrain_height_profile(path)
	var width := _resolve_path_width(path, dist, length)
	var lane_extents := _resolve_path_lane_extents(path, dist, length, width)
	var shoulder_left := _resolve_path_edge_width(path, dist, length, "get_shoulder_left_at_offset", "get_shoulder_left_at_ratio", "shoulder_left_width")
	var shoulder_right := _resolve_path_edge_width(path, dist, length, "get_shoulder_right_at_offset", "get_shoulder_right_at_ratio", "shoulder_right_width")
	var sidewalk_left := _resolve_path_edge_width(path, dist, length, "get_sidewalk_left_at_offset", "get_sidewalk_left_at_ratio", "sidewalk_left_width")
	var sidewalk_right := _resolve_path_edge_width(path, dist, length, "get_sidewalk_right_at_offset", "get_sidewalk_right_at_ratio", "sidewalk_right_width")
	var sidewalk_height := _resolve_path_edge_width(path, dist, length, "get_sidewalk_height_at_offset", "get_sidewalk_height_at_ratio", "sidewalk_height")
	var left_half := lane_extents.x + shoulder_left + sidewalk_left
	var right_half := lane_extents.y + shoulder_right + sidewalk_right
	var lateral_xz_scale := Vector2(right.x, right.z).length()
	var left_surface_raise := sidewalk_height if sidewalk_left > EPS else 0.0
	var right_surface_raise := sidewalk_height if sidewalk_right > EPS else 0.0
	var left3 := p - right * left_half
	left3 += road_vertical_axis * left_surface_raise
	var right3 := p + right * right_half
	right3 += road_vertical_axis * right_surface_raise

	return {
		"path_id": path_id,
		"dist": dist,
		"center": p,
		"center2": Vector2(p.x, p.z),
		"center_y": p.y,
		"left_y": left3.y,
		"right_edge_y": right3.y,
		"width": width,
		"left_half_xz": lateral_xz_scale * left_half,
		"right_half_xz": lateral_xz_scale * right_half,
		"left_surface_raise": left_surface_raise,
		"right_surface_raise": right_surface_raise,
		"right": right,
		"right2": Vector2(right.x, right.z),
		"left2": Vector2(left3.x, left3.z),
		"right_edge2": Vector2(right3.x, right3.z),
		"terrain_profile": terrain_profile,
		"directional_lane_profile": path.has_method("get_lane_layout_at_offset") and bool(path.get("lane_profile_enabled")),
	}


func _resolve_road_frame(
	curve: Curve3D,
	path_transform: Transform3D,
	builder_inverse: Transform3D,
	dist: float,
	length: float,
	p: Vector3,
	p_prev: Vector3,
	p_next: Vector3
) -> Dictionary:
	var orientation_mode := _effective_road_orientation_mode()
	var bank_max_degrees := _effective_road_bank_max_degrees()
	var bank_strength := _effective_road_bank_strength()
	var bank_sample_distance := _effective_road_bank_sample_distance()
	var world_up := _world_up_in_builder_space()
	var tangent := p_next - p_prev
	if orientation_mode != 0:
		tangent.y = 0.0
	if tangent.length_squared() < 0.000001:
		tangent = p_next - p
		if orientation_mode != 0:
			tangent.y = 0.0
	if tangent.length_squared() < 0.000001:
		tangent = p - p_prev
		if orientation_mode != 0:
			tangent.y = 0.0
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.FORWARD
	else:
		tangent = tangent.normalized()

	var up := world_up
	if orientation_mode == 0 and curve.has_method("sample_baked_up_vector"):
		var up_world := path_transform.basis * curve.sample_baked_up_vector(dist, true)
		up = (builder_inverse.basis * up_world).normalized()
		if up.length_squared() < 0.000001:
			up = world_up
	var right := up.cross(tangent).normalized()
	if right.length_squared() < 0.000001:
		right = world_up.cross(tangent).normalized()
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	if orientation_mode == 0:
		up = tangent.cross(right).normalized()

	if orientation_mode == 2:
		var probe := maxf(0.05, bank_sample_distance)
		var prev_d := maxf(0.0, dist - probe)
		var next_d := minf(length, dist + probe)
		var bank_prev := builder_inverse * (path_transform * curve.sample_baked(prev_d, true))
		var bank_next := builder_inverse * (path_transform * curve.sample_baked(next_d, true))
		var prev_dir := p - bank_prev
		var next_dir := bank_next - p
		prev_dir.y = 0.0
		next_dir.y = 0.0
		if prev_dir.length_squared() > 0.000001 and next_dir.length_squared() > 0.000001:
			prev_dir = prev_dir.normalized()
			next_dir = next_dir.normalized()
			var signed_turn := atan2(prev_dir.cross(next_dir).y, prev_dir.dot(next_dir))
			var max_bank := deg_to_rad(maxf(0.0, bank_max_degrees))
			var bank_angle := clampf(-signed_turn * maxf(0.0, bank_strength), -max_bank, max_bank)
			if absf(bank_angle) > 0.000001:
				var roll := Basis(tangent, bank_angle)
				right = (roll * right).normalized()
				up = (roll * up).normalized()
	return {"right": right, "up": up}


func _world_up_in_builder_space() -> Vector3:
	var up := global_transform.basis.inverse() * Vector3.UP
	if up.length_squared() < 0.000001:
		return Vector3.UP
	return up.normalized()


func _resolve_path_width(path: Path3D, dist: float, length: float) -> float:
	if path.has_method("get_width_at_offset"):
		return maxf(0.05, float(path.call("get_width_at_offset", dist)))
	if path.has_method("get_width_at_ratio"):
		var ratio := 0.0 if length <= 0.001 else clampf(dist / length, 0.0, 1.0)
		return maxf(0.05, float(path.call("get_width_at_ratio", ratio)))
	return maxf(0.05, _road_network_default("road_width", fallback_road_width))


func _resolve_path_lane_extents(path: Path3D, dist: float, length: float, width: float) -> Vector2:
	var fallback := Vector2(width * 0.5, width * 0.5)
	var raw_value: Variant
	if path.has_method("get_lane_extents_at_offset"):
		raw_value = path.call("get_lane_extents_at_offset", dist)
	elif path.has_method("get_lane_extents_at_ratio"):
		var ratio := 0.0 if length <= 0.001 else clampf(dist / length, 0.0, 1.0)
		raw_value = path.call("get_lane_extents_at_ratio", ratio)
	else:
		return fallback
	if raw_value is Vector2:
		var pair: Vector2 = raw_value
		return Vector2(maxf(0.0, pair.x), maxf(0.0, pair.y))
	if raw_value is Dictionary:
		var values: Dictionary = raw_value
		return Vector2(
			maxf(0.0, float(values.get("left", values.get("x", fallback.x)))),
			maxf(0.0, float(values.get("right", values.get("y", fallback.y))))
		)
	return fallback


func _resolve_path_edge_width(path: Path3D, dist: float, length: float, offset_method: String, ratio_method: String, road_network_property := "") -> float:
	if path.has_method(offset_method):
		return maxf(0.0, float(path.call(offset_method, dist)))
	if path.has_method(ratio_method):
		var ratio := 0.0 if length <= 0.001 else clampf(dist / length, 0.0, 1.0)
		return maxf(0.0, float(path.call(ratio_method, ratio)))
	return maxf(0.0, _road_network_default(road_network_property, 0.0))


func _road_network_default(property_name: String, fallback: float) -> float:
	if property_name.is_empty() or road_network_source.is_empty():
		return fallback
	var road_network := get_node_or_null(road_network_source)
	if road_network == null:
		return fallback
	var value = road_network.get(property_name)
	if value == null:
		return fallback
	return float(value)


func _effective_road_orientation_mode() -> int:
	return int(_road_network_default("road_orientation_mode", road_orientation_mode))


func _effective_road_bank_max_degrees() -> float:
	return _road_network_default("road_bank_max_degrees", road_bank_max_degrees)


func _effective_road_bank_strength() -> float:
	return _road_network_default("road_bank_strength", road_bank_strength)


func _effective_road_bank_sample_distance() -> float:
	return _road_network_default("road_bank_sample_distance", road_bank_sample_distance)


func _road_network_vertical_offset_in_builder_space() -> Vector3:
	if road_network_source.is_empty():
		return Vector3.ZERO
	var road_network := get_node_or_null(road_network_source) as Node3D
	if road_network == null:
		return Vector3.ZERO
	var offset := _road_network_default("y_offset", 0.0)
	var world_offset := road_network.global_transform.basis * Vector3.UP * offset
	return global_transform.basis.inverse() * world_offset


func _road_network_surface_frame(path: Path3D, distance: float, builder_inverse: Transform3D) -> Dictionary:
	var road_network := _resolve_road_network_for_path(path)
	if road_network == null:
		return {}
	var raw_frame = road_network.call("get_path_surface_frame", path, distance)
	if not raw_frame is Dictionary:
		return {}
	var center_world: Vector3 = raw_frame.get("center", Vector3.ZERO)
	var right_world: Vector3 = raw_frame.get("right", Vector3.RIGHT)
	var vertical_world: Vector3 = raw_frame.get("vertical", Vector3.UP)
	var right := (builder_inverse.basis * right_world).normalized()
	var vertical := (builder_inverse.basis * vertical_world).normalized()
	if right.length_squared() <= EPS:
		right = Vector3.RIGHT
	if vertical.length_squared() <= EPS:
		vertical = Vector3.UP
	return {
		"center": builder_inverse * center_world,
		"right": right,
		"vertical": vertical,
	}


func _resolve_road_network_for_path(path: Path3D) -> Node:
	if not road_network_source.is_empty():
		var explicit_network := get_node_or_null(road_network_source)
		if explicit_network != null and explicit_network.has_method("get_path_surface_frame"):
			return explicit_network
	var node: Node = path
	while node != null:
		if node.has_method("get_path_surface_frame"):
			return node
		node = node.get_parent()
	return null


func _default_terrain_height_profile() -> Dictionary:
	return {
		"left_distances": left_profile_distances,
		"left_heights": left_profile_heights,
		"right_distances": right_profile_distances,
		"right_heights": right_profile_heights,
		"to_base_blend_distance": profile_to_base_blend_distance,
		"power": profile_power,
	}


func _resolve_path_terrain_height_profile(path: Path3D) -> Dictionary:
	var fallback := _default_terrain_height_profile()
	if path == null or not path.has_method("has_terrain_height_profile_override"):
		return fallback
	if not bool(path.call("has_terrain_height_profile_override")):
		return fallback
	if not path.has_method("get_terrain_height_profile_override"):
		return fallback
	var profile_raw = path.call("get_terrain_height_profile_override")
	if not (profile_raw is Dictionary):
		return fallback
	var profile: Dictionary = profile_raw
	var left_distances: PackedFloat32Array = profile.get("left_distances", PackedFloat32Array())
	var left_heights: PackedFloat32Array = profile.get("left_heights", PackedFloat32Array())
	var right_distances: PackedFloat32Array = profile.get("right_distances", PackedFloat32Array())
	var right_heights: PackedFloat32Array = profile.get("right_heights", PackedFloat32Array())
	if mini(left_distances.size(), left_heights.size()) < 2:
		return fallback
	if mini(right_distances.size(), right_heights.size()) < 2:
		return fallback
	return {
		"left_distances": left_distances,
		"left_heights": left_heights,
		"right_distances": right_distances,
		"right_heights": right_heights,
		"to_base_blend_distance": maxf(0.0, float(profile.get("to_base_blend_distance", profile_to_base_blend_distance))),
		"power": maxf(0.1, float(profile.get("power", profile_power))),
	}


func _compute_bounds(road_polygons: Array) -> Rect2:
	if bounds_mode == 1:
		var size := Vector2(maxf(1.0, manual_size_xz.x), maxf(1.0, manual_size_xz.y))
		return Rect2(manual_center_xz - size * 0.5, size)

	var has_point := false
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for poly in road_polygons:
		for p in poly:
			var v: Vector2 = p
			min_v.x = minf(min_v.x, v.x)
			min_v.y = minf(min_v.y, v.y)
			max_v.x = maxf(max_v.x, v.x)
			max_v.y = maxf(max_v.y, v.y)
			has_point = true

	if not has_point:
		return Rect2(Vector2(-64.0, -64.0), Vector2(128.0, 128.0))

	var pad := maxf(0.0, auto_outer_padding)
	min_v -= Vector2(pad, pad)
	max_v += Vector2(pad, pad)
	return Rect2(min_v, max_v - min_v)


func _point_budget_limit() -> int:
	if _generation_point_budget > 0:
		return _generation_point_budget
	return AUTO_POINT_BUDGET_HARD_CAP


func _resolve_generation_point_budget(bounds: Rect2, road_data: Dictionary) -> int:
	var rows: Array = road_data.get("rows", [])
	var road_boundary_estimate := rows.size() * 2
	if ADD_ROAD_EDGE_POINTS and add_road_boundary_support_points and not _active_generate_road_edge_collars:
		road_boundary_estimate += rows.size() * 2
	var near_estimate := 0
	if ADD_NEAR_ROAD_RINGS and not rows.is_empty():
		var lateral_step := maxf(0.25, near_road_step)
		var profile_width := _road_data_profile_max_distance(road_data)
		var max_d := maxf(lateral_step, maxf(near_road_width, profile_width))
		var min_ring_d := maxf(road_clearance, ROAD_EDGE_REJECT_DISTANCE + POINT_MERGE_EPSILON if REJECT_TRIANGLES_NEAR_ROAD_EDGE else road_clearance)
		var ring_count := maxi(1, int(floor(maxf(0.0, max_d - min_ring_d) / lateral_step)) + 1)
		near_estimate = rows.size() * ring_count * 2

	var far_step := maxf(0.25, far_grid_step)
	var grid_x := maxi(1, int(ceil(bounds.size.x / far_step)) + 1)
	var grid_z := maxi(1, int(ceil(bounds.size.y / far_step)) + 1)
	var far_grid_estimate := grid_x * grid_z
	var bounds_estimate := grid_x * 2 + grid_z * 2

	var required_base := road_boundary_estimate + near_estimate + bounds_estimate + far_grid_estimate
	var modifier_room := int(ceil(float(required_base) * 0.15))
	var target := maxi(200, required_base + modifier_room)
	return mini(target, AUTO_POINT_BUDGET_HARD_CAP)


func _road_data_profile_max_distance(road_data: Dictionary) -> float:
	var max_distance := maxf(_profile_max_distance(left_profile_distances), _profile_max_distance(right_profile_distances))
	for segment_raw in road_data.get("segments", []):
		var segment: Dictionary = segment_raw
		var profile: Dictionary = segment.get("terrain_profile", {})
		max_distance = maxf(max_distance, _profile_max_distance(profile.get("left_distances", PackedFloat32Array())))
		max_distance = maxf(max_distance, _profile_max_distance(profile.get("right_distances", PackedFloat32Array())))
	return max_distance


func _road_data_has_directional_lane_profile(road_data: Dictionary) -> bool:
	var rows: Array = road_data.get("rows", [])
	for row_value in rows:
		var row: Dictionary = row_value
		if bool(row.get("directional_lane_profile", false)):
			return true
	return false


func _add_far_grid_points(points: PackedVector2Array, point_keys: Dictionary, bounds: Rect2, road_segments: Array) -> void:
	var step := maxf(0.25, far_grid_step)
	if _point_cache.enabled and _source_cache.spatial_ready:
		var cursor_x := bounds.position.x
		var cursor_z := bounds.position.y
		while points.size() < _point_budget_limit():
			var block: Dictionary = _point_cache.grid_block(cursor_x, cursor_z, bounds, step, EPS)
			_add_masked_point_block(points, point_keys, block.points, road_segments, road_clearance)
			if block.done:
				return
			cursor_x = block.x
			cursor_z = block.z
		return
	var x0 := bounds.position.x
	var z0 := bounds.position.y
	var x1 := bounds.position.x + bounds.size.x
	var z1 := bounds.position.y + bounds.size.y
	var x := x0
	while x <= x1 + EPS:
		if points.size() >= _point_budget_limit():
			return
		var z := z0
		while z <= z1 + EPS:
			if points.size() >= _point_budget_limit():
				return
			var p := Vector2(x, z)
			if not _is_inside_road_mask(p, road_segments, road_clearance):
				_add_unique_point(points, point_keys, p)
			z += step
		x += step


func _add_masked_point_block(points: PackedVector2Array, point_keys: Dictionary, candidates: PackedVector2Array,
		road_segments: Array, clearance: float) -> void:
	if candidates.is_empty() or points.size() >= _point_budget_limit():
		return
	var accepted: PackedVector2Array = _point_cache.filter(candidates, clearance,
		[_road_spatial_cell_size, _road_max_half_width, fallback_road_width], _source_cache,
		func(point: Vector2, margin: float) -> bool: return _is_inside_road_mask(point, road_segments, margin))
	for point: Vector2 in accepted:
		if points.size() >= _point_budget_limit():
			return
		_add_unique_point(points, point_keys, point)


func _add_road_boundary_points(points: PackedVector2Array, point_keys: Dictionary, road_data: Dictionary, road_segments: Array) -> void:
	var rows: Array = road_data.get("rows", [])
	for row in rows:
		if points.size() >= _point_budget_limit():
			return
		var left2: Vector2 = row.get("left2", Vector2.ZERO)
		var right2: Vector2 = row.get("right_edge2", Vector2.ZERO)
		_add_unique_point(points, point_keys, left2)
		_add_unique_point(points, point_keys, right2)

	# Extra samples on road polygon edges. This reduces long triangles near bends.
	var polygons: Array = road_data.get("polygons", [])
	for poly in polygons:
		if points.size() >= _point_budget_limit():
			return
		_resample_polygon_points(points, point_keys, poly, maxf(0.25, near_road_step), road_segments)
		if add_road_boundary_support_points and not _active_generate_road_edge_collars:
			_add_polygon_boundary_support_points(points, point_keys, poly, maxf(0.25, near_road_step), road_segments)


func _add_near_road_points(points: PackedVector2Array, point_keys: Dictionary, road_data: Dictionary, road_segments: Array) -> void:
	var grouped: bool = _point_cache.enabled and _source_cache.spatial_ready
	var rows: Array = road_data.get("rows", [])
	if rows.is_empty():
		return
	var lateral_step := maxf(0.25, near_road_step)
	var profile_width := _road_data_profile_max_distance(road_data)
	var max_d := maxf(lateral_step, maxf(near_road_width, profile_width))
	var band_distances := PackedFloat32Array()
	var min_ring_d := maxf(road_clearance, ROAD_EDGE_REJECT_DISTANCE + POINT_MERGE_EPSILON if REJECT_TRIANGLES_NEAR_ROAD_EDGE else road_clearance)
	var band_d := min_ring_d
	while band_d <= max_d + EPS:
		band_distances.push_back(band_d)
		band_d += lateral_step
	if band_distances.is_empty():
		band_distances.push_back(maxf(min_ring_d, lateral_step))
	if grouped:
		_add_cached_near_road_points(points, point_keys, rows, road_segments, band_distances, lateral_step)
		return

	# Add rings by distance first, then by row. Sequential row-first insertion can
			# spend the detail budget before later road sections get any near-road terrain samples.
	for d in band_distances:
		var last_sample_dist_by_path: Dictionary = {}
		for row_idx in range(rows.size()):
			var row: Dictionary = rows[row_idx]
			if points.size() >= _point_budget_limit():
				return
			# The contour may be fine, but terrain rings remain at near_road_step so
			# they do not consume the budget before later road sections are covered.
			var path_id := int(row.get("path_id", -1))
			var dist := float(row.get("dist", 0.0))
			var last_dist := float(last_sample_dist_by_path.get(path_id, -INF))
			if dist - last_dist < lateral_step and dist > 0.0001:
				continue
			last_sample_dist_by_path[path_id] = dist
			_add_near_road_points_for_row(points, point_keys, row, road_segments, d)


func _add_cached_near_road_points(points: PackedVector2Array, point_keys: Dictionary, rows: Array,
		road_segments: Array, bands: PackedFloat32Array, step: float) -> void:
	var blocks: Array[Dictionary] = []
	var last_by_path: Dictionary = {}
	for band in range(bands.size()):
		var cursor := 0
		var block_index := 0
		while cursor < rows.size():
			if points.size() >= _point_budget_limit():
				return
			var block: Dictionary
			if band == 0:
				var path_id := int(rows[cursor].get("path_id", -1))
				block = _point_cache.near_block(rows, cursor, float(last_by_path.get(path_id, -INF)), step, fallback_road_width)
				last_by_path[path_id] = block.last_dist
				blocks.append(block)
			else:
				block = blocks[block_index]
			cursor = block.next
			block_index += 1
			var candidates: PackedVector2Array = _point_cache.near_coordinates(block.frames, bands[band])
			_add_masked_point_block(points, point_keys, candidates, road_segments, road_clearance * 0.5)


func _add_near_road_points_for_row(
	points: PackedVector2Array,
	point_keys: Dictionary,
	row: Dictionary,
	road_segments: Array,
	d: float
) -> void:
	if points.size() >= _point_budget_limit():
		return
	var center2: Vector2 = row.get("center2", Vector2.ZERO)
	var right2: Vector2 = row.get("right2", Vector2.RIGHT)
	if right2.length() < 0.001:
		return
	right2 = right2.normalized()
	var left_half := float(row.get("left_half_xz", float(row.get("width", fallback_road_width)) * 0.5))
	var right_half := float(row.get("right_half_xz", float(row.get("width", fallback_road_width)) * 0.5))
	var left_p := center2 - right2 * (left_half + d)
	var right_p := center2 + right2 * (right_half + d)
	if not _is_inside_road_mask(left_p, road_segments, road_clearance * 0.5):
		_add_unique_point(points, point_keys, left_p)
	if points.size() >= _point_budget_limit():
		return
	if not _is_inside_road_mask(right_p, road_segments, road_clearance * 0.5):
		_add_unique_point(points, point_keys, right_p)


func _add_bounds_points(points: PackedVector2Array, point_keys: Dictionary, bounds: Rect2) -> void:
	if _point_cache.enabled:
		var axis := 0
		var cursor := bounds.position.x
		while points.size() < _point_budget_limit():
			var block: Dictionary = _point_cache.bounds_block(bounds, maxf(0.25, far_grid_step), EPS, axis, cursor)
			for point: Vector2 in block.points:
				if points.size() >= _point_budget_limit():
					return
				_add_unique_point(points, point_keys, point)
			if block.done:
				return
			axis = block.axis
			cursor = block.cursor
		return
	var x0 := bounds.position.x
	var z0 := bounds.position.y
	var x1 := bounds.position.x + bounds.size.x
	var z1 := bounds.position.y + bounds.size.y
	var step := maxf(0.25, far_grid_step)
	var x := x0
	while x <= x1 + EPS:
		if points.size() >= _point_budget_limit():
			return
		_add_unique_point(points, point_keys, Vector2(x, z0))
		_add_unique_point(points, point_keys, Vector2(x, z1))
		x += step
	var z := z0
	while z <= z1 + EPS:
		if points.size() >= _point_budget_limit():
			return
		_add_unique_point(points, point_keys, Vector2(x0, z))
		_add_unique_point(points, point_keys, Vector2(x1, z))
		z += step


func _resample_polygon_points(points: PackedVector2Array, point_keys: Dictionary, poly: PackedVector2Array, step: float, road_segments: Array) -> void:
	if poly.size() < 2:
		return
	if _point_cache.enabled:
		for first in range(0, poly.size(), _point_cache.CONTOUR_EDGES):
			if points.size() >= _point_budget_limit():
				return
			var last := mini(first + _point_cache.CONTOUR_EDGES, poly.size())
			var vertices := poly.slice(first, last)
			vertices.append(poly[last % poly.size()])
			var edge := 0
			var sample := 0
			while points.size() < _point_budget_limit():
				var block: Dictionary = _point_cache.contour_block(vertices, step, edge, sample)
				for point: Vector2 in block.points:
					if points.size() >= _point_budget_limit():
						return
					_add_unique_point(points, point_keys, point)
				if block.done:
					break
				edge = block.edge
				sample = block.sample
		return
	for i in range(poly.size()):
		if points.size() >= _point_budget_limit():
			return
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var len := a.distance_to(b)
		var n := maxi(1, int(ceil(len / maxf(0.05, step))))
		for j in range(n + 1):
			if points.size() >= _point_budget_limit():
				return
			var t := float(j) / float(n)
			var p := a.lerp(b, t)
			_add_unique_point(points, point_keys, p)


func _add_polygon_boundary_support_points(
	points: PackedVector2Array,
	point_keys: Dictionary,
	poly: PackedVector2Array,
	step: float,
	road_segments: Array
) -> void:
	if poly.size() < 2:
		return
	var distances := _road_boundary_support_distances()
	for i in range(poly.size()):
		if points.size() >= _point_budget_limit():
			return
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var edge := b - a
		var len := edge.length()
		if len <= EPS:
			continue
		var outward := _road_boundary_outward_normal(a, b, road_segments)
		if outward.length_squared() <= EPS:
			continue
		var n := maxi(1, int(ceil(len / maxf(0.05, step))))
		if _point_cache.enabled:
			_add_cached_boundary_edge_points(points, point_keys, a, b, n, road_segments, outward, distances)
			continue
		for j in range(n + 1):
			if points.size() >= _point_budget_limit():
				return
			var t := float(j) / float(n)
			var edge_point := a.lerp(b, t)
			for d in distances:
				if points.size() >= _point_budget_limit():
					return
				var support_point := edge_point + outward * float(d)
				if _is_inside_road_mask(support_point, road_segments, road_clearance * 0.5):
					continue
				_add_unique_point(points, point_keys, support_point)


func _add_cached_boundary_edge_points(points: PackedVector2Array, point_keys: Dictionary, a: Vector2, b: Vector2,
		subdivisions: int, road_segments: Array, outward := Vector2.ZERO, distances := PackedFloat32Array()) -> void:
	var cursor := 0
	while points.size() < _point_budget_limit():
		var block: Dictionary = _point_cache.edge_block(a, b, subdivisions, cursor, outward, distances)
		if distances.is_empty():
			for point: Vector2 in block.points:
				if points.size() >= _point_budget_limit():
					return
				_add_unique_point(points, point_keys, point)
		else:
			_add_masked_point_block(points, point_keys, block.points, road_segments, road_clearance * 0.5)
		if block.done:
			return
		cursor = block.next


func _road_boundary_support_distances() -> PackedFloat32Array:
	var distances := PackedFloat32Array()
	var first_d := maxf(road_clearance, ROAD_EDGE_REJECT_DISTANCE + POINT_MERGE_EPSILON if REJECT_TRIANGLES_NEAR_ROAD_EDGE else road_clearance)
	distances.push_back(first_d)
	return distances


func _road_boundary_outward_normal(a: Vector2, b: Vector2, road_segments: Array) -> Vector2:
	var edge := b - a
	if edge.length_squared() <= EPS:
		return Vector2.ZERO
	var normal := Vector2(-edge.y, edge.x).normalized()
	var probe_d := maxf(road_clearance, ROAD_EDGE_REJECT_DISTANCE + POINT_MERGE_EPSILON if REJECT_TRIANGLES_NEAR_ROAD_EDGE else road_clearance)
	var mid := (a + b) * 0.5
	var positive_d := _edge_distance_to_road(mid + normal * probe_d, road_segments)
	var negative_d := _edge_distance_to_road(mid - normal * probe_d, road_segments)
	if negative_d > positive_d:
		normal = -normal
	return normal


func _add_unique_point(points: PackedVector2Array, point_keys: Dictionary, p: Vector2) -> bool:
	if points.size() >= _point_budget_limit():
		return false
	var eps := maxf(0.0001, POINT_MERGE_EPSILON)
	var kx := roundi(p.x / eps)
	var kz := roundi(p.y / eps)
	var key := Vector2i(kx, kz)
	if point_keys.has(key):
		return false
	point_keys[key] = true
	points.push_back(p)
	return true


func _build_road_spatial_index(road_segments: Array, road_polygons: Array) -> void:
	_road_spatial_cells.clear()
	_road_edge_cells.clear()
	_road_polygon_edges.clear()
	_road_spatial_segment_count = road_segments.size()
	_road_max_half_width = 0.0
	# A bounded cell size keeps lookups local even when a scene uses a very coarse
	# far grid, while avoiding a huge number of sparse buckets for fine grids.
	_road_spatial_cell_size = clampf(far_grid_step, 4.0, 32.0)

	for segment_index in range(road_segments.size()):
		var segment: Dictionary = road_segments[segment_index]
		var a: Vector2 = segment.get("a", Vector2.ZERO)
		var b: Vector2 = segment.get("b", Vector2.ZERO)
		_road_max_half_width = maxf(_road_max_half_width, maxf(
			maxf(float(segment.get("left_half_xz_a", fallback_road_width * 0.5)), float(segment.get("left_half_xz_b", fallback_road_width * 0.5))),
			maxf(float(segment.get("right_half_xz_a", fallback_road_width * 0.5)), float(segment.get("right_half_xz_b", fallback_road_width * 0.5)))
		))
		_index_value_in_rect(_road_spatial_cells, segment_index, Rect2(a, Vector2.ZERO).expand(b))

	for poly in road_polygons:
		if poly.size() < 2:
			continue
		for i in range(poly.size()):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			var edge_index := _road_polygon_edges.size()
			_road_polygon_edges.append([a, b])
			_index_value_in_rect(_road_edge_cells, edge_index, Rect2(a, Vector2.ZERO).expand(b))
	_source_cache.prepare_segments(_road_spatial_cells, road_segments, _road_max_half_width)
	_source_cache.prepare_edges(_road_edge_cells, _road_polygon_edges)


func _index_value_in_rect(cells: Dictionary, value: int, rect: Rect2) -> void:
	var cell_size := _road_spatial_cell_size
	var min_cell_x := floori(rect.position.x / cell_size)
	var min_cell_z := floori(rect.position.y / cell_size)
	var max_cell_x := floori(rect.end.x / cell_size)
	var max_cell_z := floori(rect.end.y / cell_size)
	for x in range(min_cell_x, max_cell_x + 1):
		for z in range(min_cell_z, max_cell_z + 1):
			var key := Vector2i(x, z)
			if cells.has(key):
				var bucket: Array = cells[key]
				bucket.append(value)
			else:
				cells[key] = [value]


func _build_road_edge_y_lookup(road_data: Dictionary) -> void:
	_road_edge_y_lookup.clear()
	var rows: Array = road_data.get("rows", [])
	var polygons: Array = road_data.get("polygons", [])
	var eps := maxf(0.0001, POINT_MERGE_EPSILON)

	for row in rows:
		var left2: Vector2 = row.get("left2", Vector2.ZERO)
		var right2: Vector2 = row.get("right_edge2", Vector2.ZERO)
		var lk := Vector2i(roundi(left2.x / eps), roundi(left2.y / eps))
		_road_edge_y_lookup[lk] = float(row.get("left_y", row.get("center_y", 0.0)))
		var rk := Vector2i(roundi(right2.x / eps), roundi(right2.y / eps))
		_road_edge_y_lookup[rk] = float(row.get("right_edge_y", row.get("center_y", 0.0)))

	for poly in polygons:
		if poly.size() < 2:
			continue
		for i in range(poly.size()):
			var a = poly[i]
			var b = poly[(i + 1) % poly.size()]
			var a_key := Vector2i(roundi(a.x / eps), roundi(a.y / eps))
			var ya: float = _road_edge_y_lookup.get(a_key, base_height)
			var b_key := Vector2i(roundi(b.x / eps), roundi(b.y / eps))
			var yb: float = _road_edge_y_lookup.get(b_key, base_height)
			var length = a.distance_to(b)
			if length < eps:
				continue
			var n := maxi(1, int(ceil(length / maxf(0.25, near_road_step))))
			for j in range(1, n):
				var t := float(j) / float(n)
				var p = a.lerp(b, t)
				var k := Vector2i(roundi(p.x / eps), roundi(p.y / eps))
				if not _road_edge_y_lookup.has(k):
					_road_edge_y_lookup[k] = lerpf(ya, yb, t)


func _build_mesh_from_triangles(points: PackedVector2Array, indices: PackedInt32Array, road_segments: Array, road_polygons: Array, road_data: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tri_count := 0
	var road_info_cache: Dictionary = {}
	var vertex_cache: Dictionary = {}
	for i in range(0, indices.size(), 3):
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		if ia < 0 or ib < 0 or ic < 0 or ia >= points.size() or ib >= points.size() or ic >= points.size():
			continue
		var a := points[ia]
		var b := points[ib]
		var c := points[ic]
		var a_road_info := _get_cached_road_info(ia, a, road_segments, road_info_cache)
		var b_road_info := _get_cached_road_info(ib, b, road_segments, road_info_cache)
		var c_road_info := _get_cached_road_info(ic, c, road_segments, road_info_cache)
		if not _is_valid_triangle_2d(a, b, c, a_road_info, b_road_info, c_road_info, road_segments, road_polygons):
			continue

		var va := _get_cached_vertex(ia, a, a_road_info, vertex_cache)
		var vb := _get_cached_vertex(ib, b, b_road_info, vertex_cache)
		var vc := _get_cached_vertex(ic, c, c_road_info, vertex_cache)

		_add_terrain_triangle(st, va, vb, vc, a, b, c)
		tri_count += 1

	# Delaunay is not constrained by the road polygon. At concave turns it can
	# legitimately discard every triangle adjacent to the cut. Build this first
	# terrain band directly from consecutive road-edge samples so the road always
	# has a continuous terrain neighbour.
	if _active_generate_road_edge_collars:
		tri_count += _append_road_edge_collars(st, road_data, road_segments)

	if tri_count <= 0:
		return null

	st.generate_normals()
	return st.commit()


func _get_cached_road_info(point_index: int, p: Vector2, road_segments: Array, cache: Dictionary) -> Dictionary:
	if cache.has(point_index):
		_source_cache.capture_nearest_hint(p, _road_spatial_cell_size)
		return cache[point_index]
	var info := _nearest_road_info(p, road_segments)
	cache[point_index] = info
	return info


func _get_cached_vertex(point_index: int, p: Vector2, road_info: Dictionary, cache: Dictionary) -> Vector3:
	if cache.has(point_index):
		return cache[point_index]
	var vertex := _point_to_vertex_from_road_info(p, road_info)
	cache[point_index] = vertex
	return vertex


func _append_road_edge_collars(st: SurfaceTool, road_data: Dictionary, road_segments: Array) -> int:
	# The built-in height function is pure within this synchronous call. Adjacent
	# bands/rows share exact points; do not repeat their nearest/height queries.
	# Never retain this memo across frames or skip arbitrary subclass/modifier calls.
	var memoize := get_script().get_base_script() == null and _active_height_modifiers.is_empty()
	var samples: Dictionary = {}
	_collar_sample_stats = {"enabled": memoize, "reused": 0, "rebuilt": 0, "entries": 0}
	var rows: Array = road_data.get("rows", [])
	var road_polygons: Array = road_data.get("polygons", [])
	if rows.size() < 2:
		return 0
	# Delaunay is unconstrained around concave road turns. The coverage strip must
	# reach the first sampled terrain ring, otherwise rejected Delaunay triangles
	# leave a gap after the blend. Lateral subdivision keeps it smooth.
	var seam_width := maxf(road_clearance, ROAD_EDGE_REJECT_DISTANCE + POINT_MERGE_EPSILON)
	var shoulder_width := maxf(seam_width, road_edge_height_snap_distance)
	var collar_width := maxf(near_road_step, shoulder_width + maxf(0.0, road_edge_height_blend_distance))
	if road_edge_collar_max_width > 0.0:
		collar_width = minf(collar_width, maxf(seam_width, road_edge_collar_max_width))
	if collar_width <= EPS:
		return 0
	var band_count := maxi(1, int(ceil(collar_width / maxf(0.1, road_edge_collar_lateral_step))))
	var triangle_count := 0
	if memoize and _collar_cache.enabled and _source_cache.spatial_ready:
		var settings := var_to_bytes([_triangle_cache_settings(), invert_faces, collar_width, band_count])
		var cursor := 0
		while cursor < rows.size():
			var path_id := int(rows[cursor].get("path_id", -1))
			var path_end := cursor + 1
			while path_end < rows.size() and int(rows[path_end].get("path_id", -1)) == path_id:
				path_end += 1
			var path_start := cursor
			while cursor < path_end - 1:
				var end := mini(path_end - 1, cursor + _collar_cache.ROW_PAIRS)
				var shape: Array = []
				for row_index in range(cursor, end + 1):
					var row: Dictionary = rows[row_index]
					shape.append([row.get("left2", Vector2.ZERO), row.get("right2", Vector2.RIGHT), row.get("right_edge2", Vector2.ZERO)])
				var input := var_to_bytes([shape, settings])
				var key := Vector2i(path_id, (cursor - path_start) / _collar_cache.ROW_PAIRS)
				var cached: Dictionary = _collar_cache.lookup(key, input, _source_cache, _road_edge_y_lookup)
				if not cached.is_empty():
					if not _mesh_stream.append_block(st, cached.vertices, cached.uvs):
						for vertex_id in range(cached.vertices.size()):
							_add_vertex(st, cached.vertices[vertex_id], cached.points[vertex_id])
					triangle_count += int(cached.triangles)
				else:
					_collar_cache.begin(key, input, _source_cache)
					var added := _append_collar_rows(st, rows, cursor, end, collar_width, band_count, road_segments, road_polygons, samples, true)
					_collar_cache.finish(added, _source_cache)
					triangle_count += added
				cursor = end
			cursor = path_end
	else:
		triangle_count = _append_collar_rows(st, rows, 0, rows.size() - 1, collar_width, band_count, road_segments, road_polygons, samples, memoize)
	_collar_sample_stats.entries = samples.size()
	return triangle_count


func _append_collar_rows(st: SurfaceTool, rows: Array, start: int, end: int, collar_width: float, band_count: int,
		road_segments: Array, road_polygons: Array, samples: Dictionary, memoize: bool) -> int:
	var triangle_count := 0
	for i in range(start, end):
		var row0: Dictionary = rows[i]
		var row1: Dictionary = rows[i + 1]
		if int(row0.get("path_id", -1)) != int(row1.get("path_id", -1)):
			continue
		var right0: Vector2 = row0.get("right2", Vector2.RIGHT)
		var right1: Vector2 = row1.get("right2", Vector2.RIGHT)
		if right0.length_squared() <= EPS or right1.length_squared() <= EPS:
			continue
		right0 = right0.normalized()
		right1 = right1.normalized()
		var left0: Vector2 = row0.get("left2", Vector2.ZERO)
		var left1: Vector2 = row1.get("left2", Vector2.ZERO)
		var road_right0: Vector2 = row0.get("right_edge2", Vector2.ZERO)
		var road_right1: Vector2 = row1.get("right_edge2", Vector2.ZERO)
		for band_idx in range(band_count):
			var d0 := collar_width * float(band_idx) / float(band_count)
			var d1 := collar_width * float(band_idx + 1) / float(band_count)
			var left_inner0 := left0 - right0 * d0
			var left_inner1 := left1 - right1 * d0
			var left_outer0 := left0 - right0 * d1
			var left_outer1 := left1 - right1 * d1
			var right_inner0 := road_right0 + right0 * d0
			var right_inner1 := road_right1 + right1 * d0
			var right_outer0 := road_right0 + right0 * d1
			var right_outer1 := road_right1 + right1 * d1
			if memoize:
				triangle_count += _append_topology_quad_cached(st, left_inner0, left_inner1, left_outer0, left_outer1, road_segments, samples)
				triangle_count += _append_topology_quad_cached(st, right_inner0, right_outer0, right_inner1, right_outer1, road_segments, samples)
			else:
				triangle_count += _append_topology_quad(st, left_inner0, left_inner1, left_outer0, left_outer1, road_segments, road_polygons)
				triangle_count += _append_topology_quad(st, right_inner0, right_outer0, right_inner1, right_outer1, road_segments, road_polygons)
	return triangle_count


func _collar_vertex(p: Vector2, road_segments: Array, samples: Dictionary) -> Vector3:
	if _collar_cache.recording:
		var eps := maxf(0.0001, POINT_MERGE_EPSILON)
		var key := Vector2i(roundi(p.x / eps), roundi(p.y / eps))
		_collar_cache.capture_height(key, _road_edge_y_lookup.get(key, null))
	if samples.has(p):
		_source_cache.capture_nearest_hint(p, _road_spatial_cell_size)
		_collar_sample_stats.reused += 1
		# Dictionary equality treats signed zero coordinates as equal. Preserve
		# the caller's original coordinate bits, including on a memo hit.
		return Vector3(p.x, samples[p], p.y)
	var vertex := _point_to_vertex(p, road_segments)
	_collar_sample_stats.rebuilt += 1
	# A large collar cannot grow a second unbounded point set.
	if samples.size() < 16384:
		samples[p] = vertex.y
	return vertex


func _append_topology_quad_cached(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, road_segments: Array, samples: Dictionary) -> int:
	if _segments_intersect_strict(a, b, c, d) or _segments_intersect_strict(a, c, b, d):
		return 0
	var va := _collar_vertex(a, road_segments, samples)
	var vb := _collar_vertex(b, road_segments, samples)
	var vc := _collar_vertex(c, road_segments, samples)
	var vd := _collar_vertex(d, road_segments, samples)
	return _emit_topology_quad(st, a, b, c, d, va, vb, vc, vd)


func _append_topology_quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, road_segments: Array, _road_polygons: Array) -> int:
	if _segments_intersect_strict(a, b, c, d) or _segments_intersect_strict(a, c, b, d):
		return 0
	var va := _point_to_vertex(a, road_segments)
	var vb := _point_to_vertex(b, road_segments)
	var vc := _point_to_vertex(c, road_segments)
	var vd := _point_to_vertex(d, road_segments)
	return _emit_topology_quad(st, a, b, c, d, va, vb, vc, vd)


func _emit_topology_quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, va: Vector3, vb: Vector3, vc: Vector3, vd: Vector3) -> int:
	# Evaluate both diagonals. A lane transition can make one diagonal nearly
	# degenerate while the other still covers the complete road-to-terrain seam.
	var first_diagonal := [
		[a, b, c, va, vb, vc],
		[c, b, d, vc, vb, vd],
	]
	var second_diagonal := [
		[a, b, d, va, vb, vd],
		[a, d, c, va, vd, vc],
	]
	var first_score := _collar_triangle_set_score(first_diagonal)
	var second_score := _collar_triangle_set_score(second_diagonal)
	var chosen: Array = second_diagonal if second_score > first_score else first_diagonal
	var count := 0
	for triangle in chosen:
		var a2: Vector2 = triangle[0]
		var b2: Vector2 = triangle[1]
		var c2: Vector2 = triangle[2]
		if not _collar_triangle_is_safe(a2, b2, c2):
			continue
		count += _add_oriented_topology_triangle(st, triangle[3], triangle[4], triangle[5], a2, b2, c2)
	return count


func _collar_triangle_set_score(triangles: Array) -> float:
	var safe_count := 0
	var minimum_area := INF
	for triangle in triangles:
		var a: Vector2 = triangle[0]
		var b: Vector2 = triangle[1]
		var c: Vector2 = triangle[2]
		var area := absf(_cross2(b - a, c - a)) * 0.5
		minimum_area = minf(minimum_area, area)
		if _collar_triangle_is_safe(a, b, c):
			safe_count += 1
	# Complete coverage is more important than the diagonal's area. The area is
	# only a tie-breaker when both choices retain the same number of triangles.
	return float(safe_count) * 1000000.0 + minimum_area


func _collar_triangle_is_safe(a: Vector2, b: Vector2, c: Vector2) -> bool:
	# These vertices are derived directly from the sampled road boundary and its
	# outward frame. A nearest-road/intersection test is invalid here: on a tight
	# bend it can match another nearby road segment and remove the seam we are
	# explicitly constructing. Quad self-intersection is checked by the caller.
	return absf(_cross2(b - a, c - a)) * 0.5 >= MIN_TRIANGLE_AREA_XZ


func _add_oriented_topology_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, a2: Vector2, b2: Vector2, c2: Vector2) -> int:
	var normal_y := (b - a).cross(c - a).y
	if absf(normal_y) <= EPS:
		return 0
	var flip := normal_y < 0.0
	if invert_faces:
		flip = not flip
	if flip:
		_add_vertex(st, c, c2)
		_add_vertex(st, b, b2)
		_add_vertex(st, a, a2)
	else:
		_add_vertex(st, a, a2)
		_add_vertex(st, b, b2)
		_add_vertex(st, c, c2)
	return 1


func _add_terrain_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, a2: Vector2, b2: Vector2, c2: Vector2) -> void:
	# Every generated terrain triangle represents the upper surface. Its winding
	# must therefore have a positive Y component before normals are generated.
	# Delaunay can return the opposite 2D winding, which otherwise becomes a
	# down-facing, unlit patch after SurfaceTool.generate_normals().
	var flip := (b - a).cross(c - a).y < 0.0
	if flip:
		_normal_winding_fixes += 1
	if invert_faces:
		flip = not flip
	if _mesh_stream.target != null and not _collar_cache.recording:
		if _mesh_stream.append_triangle(st, a, b, c, a2, b2, c2, flip):
			return
	if flip:
		_add_vertex(st, c, c2)
		_add_vertex(st, b, b2)
		_add_vertex(st, a, a2)
	else:
		_add_vertex(st, a, a2)
		_add_vertex(st, b, b2)
		_add_vertex(st, c, c2)



func _add_vertex(st: SurfaceTool, v: Vector3, p2: Vector2) -> void:
	var uv := Vector2(p2.x * 0.05, p2.y * 0.05)
	if _collar_cache.recording:
		_collar_cache.capture_vertex(v, p2, uv)
	if _mesh_stream.target != null and _mesh_stream.append_vertex(st, v, uv):
		return
	st.set_uv(uv)
	st.add_vertex(v)


func _point_to_vertex(p: Vector2, road_segments: Array) -> Vector3:
	var y := _sample_height_at_point(p, road_segments)
	return Vector3(p.x, y, p.y)


func _point_to_vertex_from_road_info(p: Vector2, road_info: Dictionary) -> Vector3:
	return Vector3(p.x, _sample_height_from_road_info(p, road_info), p.y)


func _sample_height_at_point(p: Vector2, road_segments: Array) -> float:
	var nearest := _nearest_road_info(p, road_segments)
	return _sample_height_from_road_info(p, nearest)


## Includes both worker triangulation and main-thread multi-frame mesh assembly.
func _road_sources_pending() -> bool:
	var checked: Dictionary = {}
	for np: NodePath in source_paths:
		var path := get_node_or_null(np) as Path3D
		if path == null:
			continue
		var network := _resolve_road_network_for_path(path)
		if network == null or checked.has(network.get_instance_id()):
			continue
		checked[network.get_instance_id()] = true
		if network.has_method("is_road_generation_pending") and network.call("is_road_generation_pending"):
			return true
	return false


func is_terrain_generation_pending() -> bool:
	return _is_generation_thread_active() or (Engine.is_editor_hint() and auto_regenerate_in_editor \
		and _last_signature != _build_signature())


## Built-in idle height queries are value-only. Modifier/subclass callbacks
## require their full lifecycle until they expose a read-only dependency contract.
func supports_terrain_placement_cache() -> bool:
	return not is_terrain_generation_pending() and get_script().get_base_script() == null and _active_height_modifiers.is_empty()


## Samples the generated terrain function directly, without requiring a physics collider.
func get_terrain_height_at_world(world_position: Vector3) -> Dictionary:
	if is_terrain_generation_pending():
		# Do not replace the in-flight job's spatial support with freshly edited
		# roads. Callers can retain their last valid placement and retry on idle.
		return {"hit": false, "pending": true}
	var local_position := to_local(world_position)
	var road_data := _get_cached_road_data()
	var road_segments: Array = road_data.get("segments", [])
	if road_segments.is_empty():
		return {}
	if _road_spatial_cells.is_empty():
		_build_road_spatial_index(road_segments, road_data.get("polygons", []))
		_build_road_edge_y_lookup(road_data)
	var sample_xz := Vector2(local_position.x, local_position.z)
	var center_y := _sample_height_at_point(sample_xz, road_segments)
	var normal_local := _sample_terrain_normal_local(sample_xz, road_segments)
	var normal_world := (global_transform.basis * normal_local).normalized()
	if normal_world.length_squared() < 0.000001:
		normal_world = Vector3.UP
	return {
		"hit": true,
		"y": to_global(Vector3(local_position.x, center_y, local_position.z)).y,
		"normal": normal_world,
	}


func _sample_terrain_normal_local(p: Vector2, road_segments: Array) -> Vector3:
	var step := maxf(0.1, minf(1.0, near_road_step * 0.25))
	var left_y := _sample_height_at_point(p - Vector2(step, 0.0), road_segments)
	var right_y := _sample_height_at_point(p + Vector2(step, 0.0), road_segments)
	var back_y := _sample_height_at_point(p - Vector2(0.0, step), road_segments)
	var forward_y := _sample_height_at_point(p + Vector2(0.0, step), road_segments)
	return Vector3(left_y - right_y, step * 2.0, back_y - forward_y).normalized()


func _sample_height_from_road_info(p: Vector2, nearest: Dictionary) -> float:
	if not _source_cache.enabled or not _active_height_modifiers.is_empty():
		if _source_cache.stats.has("heights_rebuilt"):
			_source_cache.stats.heights_rebuilt += 1
			_source_cache.stats.height_modifier_bypasses += int(not _active_height_modifiers.is_empty())
		return _sample_height_from_road_info_uncached(p, nearest)
	var key := Vector2i(roundi(p.x / maxf(0.0001, POINT_MERGE_EPSILON)), roundi(p.y / maxf(0.0001, POINT_MERGE_EPSILON)))
	var query: Dictionary = _source_cache.query("height", [p, nearest, _road_edge_y_lookup.get(key, null),
		base_height, y_offset, _default_terrain_height_profile(), lock_height_to_road_edge,
		road_clearance, road_edge_height_snap_distance, road_edge_height_blend_distance, terrain_edge_y_offset,
		noise_enabled, noise_amplitude, noise_start_distance_from_road, noise_fade_distance,
		_noise_parameters()])
	var cached: Dictionary = _source_cache.lookup(query)
	if not cached.is_empty():
		_source_cache.stats.heights_reused += 1
		return cached.result
	_source_cache.stats.heights_rebuilt += 1
	var height := _sample_height_from_road_info_uncached(p, nearest)
	_source_cache.store(query, height)
	return height


func _sample_height_from_road_info_uncached(p: Vector2, nearest: Dictionary) -> float:
	if nearest.is_empty():
		return base_height + _sample_noise(p, 999.0)

	var edge_d := maxf(0.0, float(nearest.get("edge_distance", 0.0)))
	var side := int(nearest.get("side", 1))
	var road_y := float(nearest.get("road_y", base_height))

	if not _road_edge_y_lookup.is_empty():
		var eps := maxf(0.0001, POINT_MERGE_EPSILON)
		var lk := Vector2i(roundi(p.x / eps), roundi(p.y / eps))
		var exact_y = _road_edge_y_lookup.get(lk, null)
		if exact_y != null:
			road_y = float(exact_y)
	var profile: Dictionary = nearest.get("terrain_profile", _default_terrain_height_profile())
	var left_distances: PackedFloat32Array = profile.get("left_distances", left_profile_distances)
	var left_heights: PackedFloat32Array = profile.get("left_heights", left_profile_heights)
	var right_distances: PackedFloat32Array = profile.get("right_distances", right_profile_distances)
	var right_heights: PackedFloat32Array = profile.get("right_heights", right_profile_heights)
	var profile_power_for_road := maxf(0.1, float(profile.get("power", profile_power)))
	var profile_blend_distance := maxf(0.0, float(profile.get("to_base_blend_distance", profile_to_base_blend_distance)))
	var profile_h := 0.0
	if side >= 0:
		profile_h = _sample_profile(left_distances, left_heights, edge_d)
	else:
		profile_h = _sample_profile(right_distances, right_heights, edge_d)

	if not is_equal_approx(profile_power_for_road, 1.0):
		var sign_v := signf(profile_h)
		profile_h = sign_v * pow(absf(profile_h), profile_power_for_road)

	var y := road_y + profile_h

	var max_profile_dist := _profile_max_distance(left_distances if side >= 0 else right_distances)
	if profile_blend_distance > 0.001 and edge_d > max_profile_dist:
		var t := clampf((edge_d - max_profile_dist) / profile_blend_distance, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		y = lerpf(y, base_height, t)

	y += _sample_noise(p, edge_d)
	y = _apply_height_modifiers(p, y, nearest)

	if lock_height_to_road_edge:
		# Keep the generated terrain exactly on the road at the seam, then blend
		# back to the terrain height over the full configured transition distance.
		# Applying this after noise/modifiers prevents raised modifiers from forming
		# a vertical, faceted wall next to the road.
		var flat_d := maxf(maxf(road_clearance, 0.05), road_edge_height_snap_distance)
		var blend_d := maxf(0.001, road_edge_height_blend_distance)
		var target_road_y := road_y + terrain_edge_y_offset
		if edge_d <= flat_d:
			y = target_road_y
		elif edge_d < flat_d + blend_d:
			var t_edge := clampf((edge_d - flat_d) / blend_d, 0.0, 1.0)
			t_edge = t_edge * t_edge * (3.0 - 2.0 * t_edge)
			y = lerpf(target_road_y, y, t_edge)
	return y + y_offset


func _sample_profile(distances: PackedFloat32Array, heights: PackedFloat32Array, d: float) -> float:
	var n := mini(distances.size(), heights.size())
	if n <= 0:
		return 0.0
	if n == 1 or d <= float(distances[0]):
		return float(heights[0])
	for i in range(n - 1):
		var d0 := float(distances[i])
		var d1 := float(distances[i + 1])
		if d <= d1:
			var span := maxf(0.0001, d1 - d0)
			var t := clampf((d - d0) / span, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(heights[i]), float(heights[i + 1]), t)
	return float(heights[n - 1])


func _profile_max_distance(distances: PackedFloat32Array) -> float:
	if distances.is_empty():
		return 0.0
	var m := 0.0
	for d in distances:
		m = maxf(m, float(d))
	return m


func _sample_noise(p: Vector2, edge_d: float) -> float:
	if not noise_enabled or noise_amplitude <= 0.0001:
		return 0.0
	var fade := clampf((edge_d - noise_start_distance_from_road) / maxf(0.001, noise_fade_distance), 0.0, 1.0)
	fade = fade * fade * (3.0 - 2.0 * fade)
	if fade <= 0.0001:
		return 0.0
	return _noise.get_noise_2d(p.x, p.y) * noise_amplitude * fade


func _configure_noise() -> void:
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.45
	_noise.fractal_lacunarity = 2.0


func _noise_parameters() -> PackedByteArray:
	if _tracked_noise != _noise:
		if is_instance_valid(_tracked_noise) and _tracked_noise.changed.is_connected(_noise_changed):
			_tracked_noise.changed.disconnect(_noise_changed)
		_tracked_noise = _noise
		_tracked_noise.changed.connect(_noise_changed)
		_noise_input = PackedByteArray()
	if _noise_input.is_empty():
		var values: Array = []
		for property: Dictionary in _noise.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				values.append([property.name, _noise.get(property.name)])
		_noise_input = var_to_bytes(values)
	return _noise_input


func _noise_changed() -> void:
	_noise_input = PackedByteArray()


func _triangle_cache_settings() -> PackedByteArray:
	# Global maximum width is a search bound, not a height/filter setting.
	# Mesh scopes certify the native stopping/radius tests at the current width.
	return var_to_bytes([base_height, y_offset, _default_terrain_height_profile(), lock_height_to_road_edge,
		road_clearance, road_edge_height_snap_distance, road_edge_height_blend_distance, terrain_edge_y_offset,
		noise_enabled, noise_amplitude, noise_start_distance_from_road, noise_fade_distance, _noise_parameters(),
		road_interior_reject_margin, fallback_road_width, _road_spatial_cell_size,
		_active_generate_road_edge_collars])


func _reject_triangle(reason: String) -> bool:
	_last_triangle_reject_reason = reason
	if _triangle_reject_stats.has(reason):
		_triangle_reject_stats[reason] = int(_triangle_reject_stats[reason]) + 1
	else:
		_triangle_reject_stats[reason] = 1
	return false


func _is_valid_triangle_2d(a: Vector2, b: Vector2, c: Vector2, a_road_info: Dictionary, b_road_info: Dictionary, c_road_info: Dictionary, road_segments: Array, road_polygons: Array) -> bool:
	var area := absf(_cross2(b - a, c - a)) * 0.5
	if area < MIN_TRIANGLE_AREA_XZ:
		return _reject_triangle("area")

	var tri_clearance := road_clearance
	if SEPARATE_TRIANGLE_ROAD_CLEARANCE:
		tri_clearance = TRIANGLE_ROAD_CLEARANCE

	# Reject only triangles that enter the road interior.
	if FILTER_TRIANGLES_INSIDE_ROADS:
		var centroid := (a + b + c) / 3.0
		var centroid_margin := STRICT_NO_OVERLAP_MARGIN if STRICT_NO_OVERLAP_NEAR_ROADS else maxf(road_interior_reject_margin, -tri_clearance)
		if _is_inside_road_interior(centroid, road_segments, centroid_margin):
			return _reject_triangle("inside_centroid")

	# Strict mode: reject if any triangle vertex enters the road area.
	var inside_count := 0
	var vertex_margin := STRICT_NO_OVERLAP_MARGIN if STRICT_NO_OVERLAP_NEAR_ROADS else road_interior_reject_margin
	if _road_info_is_inside_interior(a_road_info, vertex_margin):
		inside_count += 1
	if _road_info_is_inside_interior(b_road_info, vertex_margin):
		inside_count += 1
	if _road_info_is_inside_interior(c_road_info, vertex_margin):
		inside_count += 1
	if REJECT_ANY_TRIANGLE_VERTEX_INSIDE_ROAD:
		if inside_count >= 1:
			return _reject_triangle("inside_vertex")
	else:
		if inside_count >= 2:
			return _reject_triangle("inside_vertex")

	if REJECT_TRIANGLES_NEAR_ROAD_EDGE:
		if _road_info_is_rejected_near_edge(a_road_info):
			return _reject_triangle("near_edge")
		if _road_info_is_rejected_near_edge(b_road_info):
			return _reject_triangle("near_edge")
		if _road_info_is_rejected_near_edge(c_road_info):
			return _reject_triangle("near_edge")

	if FILTER_TRIANGLES_CROSSING_ROAD_EDGES:
		if _triangle_crosses_road_edges(a, b, c, road_polygons):
			if not SOFT_ROAD_CROSSING_FILTER:
				return _reject_triangle("crossing")
			var sample_clearance := maxf(ROAD_CROSSING_SAMPLE_CLEARANCE, (TRIANGLE_ROAD_CLEARANCE if SEPARATE_TRIANGLE_ROAD_CLEARANCE else road_clearance) * 0.35)
			if _triangle_samples_inside_road(a, b, c, road_segments, sample_clearance):
				return _reject_triangle("crossing")

	return true


func _road_info_edge_distance(road_info: Dictionary) -> float:
	if road_info.is_empty():
		return INF
	return float(road_info.get("edge_distance", INF))


func _road_info_is_rejected_near_edge(road_info: Dictionary) -> bool:
	var edge_distance := _road_info_edge_distance(road_info)
	var allowance := maxf(0.0, ROAD_EDGE_VERTEX_ALLOWANCE)
	if edge_distance < -maxf(allowance, EPS):
		return true
	# Without collars, edge-to-ring Delaunay triangles are the seam. Rejecting
	# outside-near-edge vertices here opens visible holes along tight road edges.
	if not _active_generate_road_edge_collars:
		return false
	if edge_distance <= allowance:
		return false
	return edge_distance <= ROAD_EDGE_REJECT_DISTANCE


func _road_info_is_inside_interior(road_info: Dictionary, interior_margin: float) -> bool:
	return _road_info_edge_distance(road_info) < -maxf(absf(interior_margin), EPS)


func _triangle_crosses_road_edges(a: Vector2, b: Vector2, c: Vector2, road_polygons: Array) -> bool:
	if not _source_cache.enabled or not _source_cache.spatial_ready or _road_edge_cells.is_empty():
		_source_cache.invalidate_mesh_scope()
		return _triangle_crosses_road_edges_uncached(a, b, c, road_polygons)
	var query: Dictionary = _source_cache.crossing_query(a, b, c, _road_spatial_cell_size)
	var cached: Dictionary = _source_cache.lookup(query)
	if not cached.is_empty():
		_source_cache.stats.crossings_reused += 1
		return cached.result
	_source_cache.stats.crossings_rebuilt += 1
	var result := _triangle_crosses_road_edges_uncached(a, b, c, road_polygons)
	_source_cache.store(query, result)
	return result


func _triangle_crosses_road_edges_uncached(a: Vector2, b: Vector2, c: Vector2, road_polygons: Array) -> bool:
	if not _road_edge_cells.is_empty():
		var min_x := minf(a.x, minf(b.x, c.x))
		var min_z := minf(a.y, minf(b.y, c.y))
		var max_x := maxf(a.x, maxf(b.x, c.x))
		var max_z := maxf(a.y, maxf(b.y, c.y))
		var cell_size := _road_spatial_cell_size
		var min_cell_x := floori(min_x / cell_size)
		var min_cell_z := floori(min_z / cell_size)
		var max_cell_x := floori(max_x / cell_size)
		var max_cell_z := floori(max_z / cell_size)
		var tested: Dictionary = {}
		for x in range(min_cell_x, max_cell_x + 1):
			for z in range(min_cell_z, max_cell_z + 1):
				var edge_indices = _road_edge_cells.get(Vector2i(x, z), null)
				if edge_indices == null:
					continue
				for edge_index in edge_indices:
					if tested.has(edge_index):
						continue
					tested[edge_index] = true
					if _source_cache.stats.has("edge_candidates_tested"):
						_source_cache.stats.edge_candidates_tested += 1
					var edge: Array = _road_polygon_edges[edge_index]
					var edge_a: Vector2 = edge[0]
					var edge_b: Vector2 = edge[1]
					if _segments_intersect_strict(a, b, edge_a, edge_b) or _segments_intersect_strict(b, c, edge_a, edge_b) or _segments_intersect_strict(c, a, edge_a, edge_b):
						return true
		return false

	var tri_edges := [[a, b], [b, c], [c, a]]
	for poly in road_polygons:
		if poly.size() < 3:
			continue
		for i in range(poly.size()):
			var p0: Vector2 = poly[i]
			var p1: Vector2 = poly[(i + 1) % poly.size()]
			for e in tri_edges:
				var a0: Vector2 = e[0]
				var a1: Vector2 = e[1]
				if _segments_intersect_strict(a0, a1, p0, p1):
					return true
	return false


func _triangle_samples_inside_road(a: Vector2, b: Vector2, c: Vector2, road_segments: Array, clearance: float) -> bool:
	# Optional soft crossing filter. Usually keep disabled for strict no-overlap mode.
	var samples := [
		(a + b + c) / 3.0,
		(a + b) * 0.5,
		(b + c) * 0.5,
		(c + a) * 0.5,
		a.lerp(b, 0.25),
		a.lerp(b, 0.75),
		b.lerp(c, 0.25),
		b.lerp(c, 0.75),
		c.lerp(a, 0.25),
		c.lerp(a, 0.75),
	]
	var margin := maxf(road_interior_reject_margin, clearance)
	for p in samples:
		if _is_inside_road_interior(p, road_segments, margin):
			return true
	return false


func _segments_intersect_strict(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	# Shared endpoints are allowed. They happen on road boundary points.
	if a.distance_to(c) <= POINT_MERGE_EPSILON or a.distance_to(d) <= POINT_MERGE_EPSILON:
		return false
	if b.distance_to(c) <= POINT_MERGE_EPSILON or b.distance_to(d) <= POINT_MERGE_EPSILON:
		return false

	var r := b - a
	var s := d - c
	var denom := _cross2(r, s)
	if absf(denom) < 0.000001:
		return false
	var t := _cross2(c - a, s) / denom
	var u := _cross2(c - a, r) / denom
	return t > 0.0001 and t < 0.9999 and u > 0.0001 and u < 0.9999


func _edge_distance_to_road(p: Vector2, road_segments: Array) -> float:
	var nearest := _nearest_road_info(p, road_segments)
	if nearest.is_empty():
		return INF
	return float(nearest.get("edge_distance", INF))

func _is_inside_road_mask(p: Vector2, road_segments: Array, clearance: float) -> bool:
	return _has_road_edge_within(p, road_segments, clearance, false)


func _is_inside_road_interior(p: Vector2, road_segments: Array, interior_margin: float) -> bool:
	return _has_road_edge_within(p, road_segments, -absf(interior_margin), true)


func _has_road_edge_within(p: Vector2, road_segments: Array, edge_threshold: float, strict: bool) -> bool:
	if road_segments.is_empty():
		_source_cache.invalidate_mesh_scope()
		return false
	if _road_spatial_cells.is_empty() or _road_spatial_segment_count != road_segments.size():
		_source_cache.invalidate_mesh_scope()
		for segment in road_segments:
			var fallback_edge_distance := _road_edge_distance_for_segment(p, segment)
			if _road_edge_matches_threshold(fallback_edge_distance, edge_threshold, strict):
				return true
		return false

	# Any matching segment must be within this centerline distance. Querying one
	# extra ring handles segments that sit on a cell boundary.
	var max_center_distance := maxf(0.0, _road_max_half_width + edge_threshold)
	var cell_size := _road_spatial_cell_size
	var cell_radius := maxi(0, int(ceil(max_center_distance / cell_size)) + 1)
	_source_cache.capture_search_radius(cell_size, edge_threshold, cell_radius)
	var center_cell_x := floori(p.x / cell_size)
	var center_cell_z := floori(p.y / cell_size)
	_source_cache.capture_bounds(Vector4i(center_cell_x - cell_radius, center_cell_z - cell_radius,
		center_cell_x + cell_radius, center_cell_z + cell_radius))
	var tested: Dictionary = {}
	for x in range(center_cell_x - cell_radius, center_cell_x + cell_radius + 1):
		for z in range(center_cell_z - cell_radius, center_cell_z + cell_radius + 1):
			var segment_indices = _road_spatial_cells.get(Vector2i(x, z), null)
			if segment_indices == null:
				continue
			for segment_index in segment_indices:
				if tested.has(segment_index):
					continue
				tested[segment_index] = true
				var edge_distance := _road_edge_distance_for_segment(p, road_segments[segment_index])
				if _road_edge_matches_threshold(edge_distance, edge_threshold, strict):
					return true
	return false


func _road_edge_matches_threshold(edge_distance: float, edge_threshold: float, strict: bool) -> bool:
	return edge_distance < edge_threshold if strict else edge_distance <= edge_threshold


func _road_edge_distance_for_segment(p: Vector2, segment: Dictionary) -> float:
	var a: Vector2 = segment.get("a", Vector2.ZERO)
	var b: Vector2 = segment.get("b", Vector2.ZERO)
	var ab: Vector2 = segment.get("ab", b - a)
	var len2 := float(segment.get("len2", ab.length_squared()))
	if len2 < 0.000001:
		return INF
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	var center := a + ab * t
	var side := _road_side_for_segment(segment, p, center)
	return p.distance_to(center) - _segment_half_xz(segment, t, side)


func _nearest_road_info(p: Vector2, road_segments: Array) -> Dictionary:
	if not _road_spatial_cells.is_empty() and _road_spatial_segment_count == road_segments.size():
		return _nearest_road_info_spatial(p, road_segments)
	_source_cache.invalidate_mesh_scope()
	return _nearest_road_info_linear(p, road_segments)


func _nearest_road_info_spatial(p: Vector2, road_segments: Array) -> Dictionary:
	if not _source_cache.enabled or not _source_cache.spatial_ready:
		_source_cache.invalidate_mesh_scope()
		return _nearest_road_info_spatial_uncached(p, road_segments)
	var defaults := [fallback_road_width, base_height, _default_terrain_height_profile()]
	var hint: Dictionary = _source_cache.nearest_hint(p, _road_spatial_cell_size)
	var query: Dictionary = {}
	if not hint.is_empty():
		query = _source_cache.nearest_query(p, _road_spatial_cell_size, _road_max_half_width, hint.ring, defaults)
	var cached: Dictionary = _source_cache.lookup(query)
	if not cached.is_empty():
		_source_cache.stats.nearest_reused += 1
		# Hints select a ring, not a result identity. Rebuild the certificate from
		# the exact matched result, even if another generation replaced the hint.
		var center := Vector2i(floori(p.x / _road_spatial_cell_size), floori(p.y / _road_spatial_cell_size))
		var distance := minf(minf(p.x - float(center.x - hint.ring) * _road_spatial_cell_size,
			float(center.x + hint.ring + 1) * _road_spatial_cell_size - p.x),
			minf(p.y - float(center.y - hint.ring) * _road_spatial_cell_size,
			float(center.y + hint.ring + 1) * _road_spatial_cell_size - p.y))
		_source_cache.remember_nearest(p, _road_spatial_cell_size, hint.ring, distance, cached.result.edge_distance)
		_source_cache.capture_nearest_hint(p, _road_spatial_cell_size)
		return cached.result.duplicate(true)
	_source_cache.stats.nearest_rebuilt += 1
	var trace: Dictionary = {}
	var result := _nearest_road_info_spatial_uncached(p, road_segments, trace)
	if result.is_empty():
		# With no valid candidate there is no finite spatial support proof. A
		# future valid road outside this search ring must not reuse an empty hit.
		_source_cache.invalidate_mesh_scope()
		return result
	if trace.has("ring"):
		query = _source_cache.nearest_query(p, _road_spatial_cell_size, _road_max_half_width, trace.ring, defaults)
		_source_cache.remember_nearest(p, _road_spatial_cell_size, trace.ring, trace.distance, trace.best)
		_source_cache.capture_nearest_hint(p, _road_spatial_cell_size)
		_source_cache.store(query, result.duplicate(true))
	return result


func _nearest_road_info_spatial_uncached(p: Vector2, road_segments: Array, trace: Dictionary = {}) -> Dictionary:
	var best := INF
	var best_info := {}
	var tested: Dictionary = {}
	var cell_size := _road_spatial_cell_size
	var center_cell_x := floori(p.x / cell_size)
	var center_cell_z := floori(p.y / cell_size)
	var ring := 0

	while true:
		var min_cell_x := center_cell_x - ring
		var min_cell_z := center_cell_z - ring
		var max_cell_x := center_cell_x + ring
		var max_cell_z := center_cell_z + ring
		for x in range(min_cell_x, max_cell_x + 1):
			for z in range(min_cell_z, max_cell_z + 1):
				if ring > 0 and x != min_cell_x and x != max_cell_x and z != min_cell_z and z != max_cell_z:
					continue
				var segment_indices = _road_spatial_cells.get(Vector2i(x, z), null)
				if segment_indices == null:
					continue
				for segment_index in segment_indices:
					if tested.has(segment_index):
						continue
					tested[segment_index] = true
					if _source_cache.stats.has("distance_tests"):
						_source_cache.stats.distance_tests += 1
					var segment: Dictionary = road_segments[segment_index]
					var a: Vector2 = segment.get("a", Vector2.ZERO)
					var b: Vector2 = segment.get("b", Vector2.ZERO)
					var ab: Vector2 = segment.get("ab", b - a)
					var len2 := float(segment.get("len2", ab.length_squared()))
					if len2 < 0.000001:
						continue
					var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
					var q := a + ab * t
					var center_dist := p.distance_to(q)
					var width := lerpf(float(segment.get("wa", fallback_road_width)), float(segment.get("wb", fallback_road_width)), t)
					var side := _road_side_for_segment(segment, p, q)
					var edge_dist := center_dist - _segment_half_xz(segment, t, side)
					if edge_dist < best:
						best = edge_dist
						best_info = {
							"center": q,
							"center_distance": center_dist,
							"edge_distance": edge_dist,
							"side": side,
							"road_y": _sample_segment_surface_y(segment, p, q, t, side),
							"width": width,
							"t": t,
							"path_id": int(segment.get("path_id", -1)),
							"terrain_profile": segment.get("terrain_profile", _default_terrain_height_profile()),
						}

		if best == INF and tested.size() == road_segments.size():
			# All indexed sources may have degenerate XZ projections. Expanding
			# forever cannot find another candidate once every segment was tested.
			return {}
		if best < INF:
			var min_x := float(min_cell_x) * cell_size
			var min_z := float(min_cell_z) * cell_size
			var max_x := float(max_cell_x + 1) * cell_size
			var max_z := float(max_cell_z + 1) * cell_size
			var distance_to_unsearched := minf(minf(p.x - min_x, max_x - p.x), minf(p.y - min_z, max_z - p.y))
			if distance_to_unsearched - _road_max_half_width >= best:
				trace["ring"] = ring
				trace["distance"] = distance_to_unsearched
				trace["best"] = best
				return best_info
		ring += 1

	# The loop returns as soon as the current best is provably final. Keep an
	# explicit fallback for GDScript's control-flow analyser.
	return best_info


func _nearest_road_info_linear(p: Vector2, road_segments: Array) -> Dictionary:
	var best := INF
	var best_info := {}
	for seg in road_segments:
		var a: Vector2 = seg.get("a", Vector2.ZERO)
		var b: Vector2 = seg.get("b", Vector2.ZERO)
		var ab: Vector2 = seg.get("ab", b - a)
		var len2 := float(seg.get("len2", ab.length_squared()))
		if len2 < 0.000001:
			continue
		var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var center_dist := p.distance_to(q)
		var width := lerpf(float(seg.get("wa", fallback_road_width)), float(seg.get("wb", fallback_road_width)), t)
		var side := _road_side_for_segment(seg, p, q)
		var edge_dist := center_dist - _segment_half_xz(seg, t, side)
		if edge_dist < best:
			best = edge_dist
			best_info = {
				"center": q,
				"center_distance": center_dist,
				"edge_distance": edge_dist,
				"side": side,
				"road_y": _sample_segment_surface_y(seg, p, q, t, side),
				"width": width,
				"t": t,
				"path_id": int(seg.get("path_id", -1)),
				"terrain_profile": seg.get("terrain_profile", _default_terrain_height_profile()),
			}
	return best_info


func _road_side_for_segment(segment: Dictionary, point: Vector2, center: Vector2) -> int:
	var direction: Vector2 = segment.get("direction", Vector2.RIGHT)
	return -1 if _cross2(direction, point - center) < 0.0 else 1


func _segment_half_xz(segment: Dictionary, t: float, side: int) -> float:
	var prefix := "left" if side >= 0 else "right"
	return lerpf(
		float(segment.get("%s_half_xz_a" % prefix, fallback_road_width * 0.5)),
		float(segment.get("%s_half_xz_b" % prefix, fallback_road_width * 0.5)),
		t
	)


func _sample_segment_surface_y(segment: Dictionary, point: Vector2, center: Vector2, t: float, side: int) -> float:
	var center_y := lerpf(float(segment.get("ay", base_height)), float(segment.get("by", base_height)), t)
	var right_a: Vector3 = segment.get("right_a", Vector3.RIGHT)
	var right_b: Vector3 = segment.get("right_b", Vector3.RIGHT)
	var right := right_a.lerp(right_b, t)
	var right_xz := Vector2(right.x, right.z)
	if right_xz.length_squared() <= 0.000000000001:
		return center_y
	# `point - center` is measured in XZ, while the profile is measured along
	# the 3D lateral road axis. Convert the horizontal projection back to that
	# axis before applying its Y component.
	var lateral := (point - center).dot(right_xz.normalized()) / right_xz.length()
	var prefix := "left" if side >= 0 else "right"
	var surface_raise := lerpf(
		float(segment.get("%s_surface_raise_a" % prefix, 0.0)),
		float(segment.get("%s_surface_raise_b" % prefix, 0.0)),
		t
	)
	return center_y + lateral * right.y + surface_raise


func _cross2(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _create_collision(mesh: ArrayMesh) -> void:
	var body := StaticBody3D.new()
	body.name = GENERATED_BODY_NAME
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	body.owner = get_tree().edited_scene_root if Engine.is_editor_hint() and get_tree() != null else null
	shape.owner = body.owner


func _clear_generated() -> void:
	_output_cache.clear()
	for child in get_children():
		if child.name == GENERATED_MESH_NAME or child.name == GENERATED_BODY_NAME:
			remove_child(child)
			child.free()


func _build_signature() -> String:
	var parts: Array[String] = []
	parts.append(str(incremental_generation_enabled))
	parts.append(_build_road_signature())
	parts.append(str(bounds_mode))
	parts.append(str(auto_outer_padding))
	parts.append(str(manual_center_xz))
	parts.append(str(manual_size_xz))
	parts.append(str(far_grid_step))
	parts.append(str(near_road_step))
	parts.append(str(near_road_width))
	parts.append(str(add_road_boundary_support_points))
	parts.append(str(generate_road_edge_collars))
	parts.append(str(auto_lane_profile_edge_collars))
	parts.append(str(road_edge_collar_lateral_step))
	parts.append(str(road_edge_collar_max_width))
	parts.append(str(road_clearance))
	parts.append(str(road_interior_reject_margin))
	parts.append(str(left_profile_distances))
	parts.append(str(left_profile_heights))
	parts.append(str(right_profile_distances))
	parts.append(str(right_profile_heights))
	parts.append(str(profile_to_base_blend_distance))
	parts.append(str(profile_power))
	parts.append(str(base_height))
	parts.append(str(lock_height_to_road_edge))
	parts.append(str(road_edge_height_snap_distance))
	parts.append(str(road_edge_height_blend_distance))
	parts.append(str(terrain_edge_y_offset))
	parts.append(str(threaded_triangulation_enabled))
	parts.append(str(centered_triangulation_enabled))
	parts.append(str(local_triangulation_enabled))
	parts.append(str(output_mode))
	parts.append(str(output_chunk_size))
	parts.append(str(noise_enabled))
	parts.append(str(noise_amplitude))
	parts.append(str(noise_frequency))
	parts.append(str(noise_start_distance_from_road))
	parts.append(str(noise_fade_distance))
	parts.append(str(noise_seed))
	parts.append(str(height_modifiers))
	parts.append(str(auto_find_height_modifiers))
	parts.append(str(add_modifier_resolution_points))
	for modifier in _collect_height_modifiers(false):
		parts.append(str(modifier.get_instance_id()))
		if modifier.has_method("get_modifier_signature"):
			parts.append(str(modifier.call("get_modifier_signature")))
	return "|".join(parts)


func _build_road_signature() -> String:
	var parts: Array[String] = []
	# Default terrain profiles are copied into sampled segment data too.
	parts.append(str(_default_terrain_height_profile()))
	parts.append(str(source_paths))
	parts.append(str(road_network_source))
	for property_name in ["road_width", "shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width", "sidewalk_height", "y_offset", "road_orientation_mode", "road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance"]:
		parts.append(str(_road_network_default(property_name, -1.0)))
	parts.append(str(global_transform))
	parts.append(str(fallback_road_width))
	parts.append(str(path_sample_step))
	parts.append(str(adaptive_path_sampling))
	parts.append(str(adaptive_min_path_step))
	parts.append(str(adaptive_max_path_step))
	parts.append(str(adaptive_full_curve_angle_degrees))
	parts.append(str(y_offset))
	parts.append(str(road_orientation_mode))
	parts.append(str(road_bank_max_degrees))
	parts.append(str(road_bank_strength))
	parts.append(str(road_bank_sample_distance))
	for np in source_paths:
		var n := get_node_or_null(np)
		if n == null:
			parts.append("missing")
			continue
		parts.append(str(n.get_instance_id()))
		parts.append(str(n.global_transform))
		if n is Path3D:
			var path := n as Path3D
			var path_road_network := _resolve_road_network_for_path(path)
			if path_road_network != null:
				parts.append(str(path_road_network.get_instance_id()))
				parts.append(str(path_road_network.global_transform))
				for property_name in ["road_width", "shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width", "sidewalk_height", "y_offset", "road_orientation_mode", "road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance"]:
					parts.append(str(path_road_network.get(property_name)))
			if path.curve == null:
				parts.append("null_curve")
				continue
			parts.append(str(path.curve.point_count))
			for i in range(path.curve.point_count):
				parts.append(str(path.curve.get_point_position(i)))
				parts.append(str(path.curve.get_point_in(i)))
				parts.append(str(path.curve.get_point_out(i)))
				parts.append(str(path.curve.get_point_tilt(i)))
			if n.has_method("get_dependent_width_profile_signature"):
				parts.append(str(n.call("get_dependent_width_profile_signature")))
			elif n.has_method("get_width_profile_signature"):
				parts.append(str(n.call("get_width_profile_signature")))
			if n.has_method("get_edge_profile_signature"):
				parts.append(str(n.call("get_edge_profile_signature")))
			if n.has_method("get_terrain_height_profile_signature"):
				parts.append(str(n.call("get_terrain_height_profile_signature")))
	return "|".join(parts)


func _log(message: String) -> void:
	if debug_logs:
		print("[TerrainTopologyBuilder3D] ", message)
