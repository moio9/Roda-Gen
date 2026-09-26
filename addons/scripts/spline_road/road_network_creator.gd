@tool
extends Node3D
class_name RoadNetworkCreator3D

const ROAD_PRESET_RESOURCE = preload("./road_preset.gd")

@export_group("Sources")
@export var source_paths: Array[NodePath] = []

@export_group("Road Presets")
@export_enum("Mountain", "Urban", "Highway", "Custom") var preset_selection := 0:
	set(value):
		preset_selection = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
@export var custom_preset: ROAD_PRESET_RESOURCE
## Apply edge settings to SplinePathProfile3D sources and use the road's orientation.
@export var preset_apply_path_settings := true
## Replace per-point widths, lane counts and transitions. Disable to keep your layout.
@export var preset_replace_lane_layout := true
## Replace only PresetBarriers created by an earlier preset. Manual siblings are kept.
@export var preset_replace_barriers := true
@export_tool_button("Apply Road Preset") var apply_preset_action := _apply_preset_from_button

@export_group("Road")
@export_range(0.2, 50.0, 0.1) var road_width := 6.0
@export_range(0.1, 10.0, 0.1) var sample_step := 0.5
@export_range(-5.0, 5.0, 0.01) var y_offset := 0.0
@export_subgroup("Edges")
@export_range(0.0, 15.0, 0.1) var shoulder_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var shoulder_right_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_right_width := 0.0
@export_range(0.0, 2.0, 0.01) var sidewalk_height := 0.12
@export_subgroup("Edge Materials")
@export var road_material_override: Material
@export var shoulder_material_override: Material
@export var sidewalk_material_override: Material
@export var terrain_material_override: Material
@export_subgroup("Per-Lane Materials")
## Optional materials for left lanes, ordered from the center outwards.
## Element 0 is lane 1, element 1 is lane 2, and so on. Empty elements keep the
## normal road material visible.
@export var left_lane_material_overrides: Array[Material] = []
## Optional materials for right lanes, ordered from the center outwards.
@export var right_lane_material_overrides: Array[Material] = []
## Small normal offset that prevents the per-lane material overlay from z-fighting.
@export_range(0.0, 0.05, 0.0001, "suffix:m") var lane_material_overlay_lift := 0.002
@export_subgroup("Outer Walls")
@export_range(0.0, 30.0, 0.1) var outer_wall_height := 0.0
@export var outer_wall_material_override: Material
@export_group("Mesh Orientation")
## Godot culls counterclockwise faces; the generated road top faces forward when inverted.
@export var invert_faces := true
@export_enum("Curve Up", "World Up (Y)", "Bank Into Curve") var road_orientation_mode := 0: set = _set_road_orientation_mode
@export_range(0.0, 45.0, 0.1, "suffix:deg") var road_bank_max_degrees := 8.0
@export_range(0.0, 4.0, 0.01) var road_bank_strength := 1.0
@export_range(0.05, 100.0, 0.05, "suffix:m") var road_bank_sample_distance := 3.0
@export var material_override: Material
@export_group("Road Markings", "markings_")
@export var markings_enabled := false
@export_enum("Off", "Solid", "Dashed", "Double Solid", "Double Dashed") var markings_center_style := 3
@export_enum("Off", "Solid", "Dashed", "Double Solid", "Double Dashed") var markings_lane_style := 2
@export_enum("Off", "Solid", "Dashed", "Double Solid", "Double Dashed") var markings_edge_style := 1
@export_range(0.02, 0.5, 0.01, "suffix:m") var markings_line_width := 0.12
@export_range(0.0, 1.0, 0.01, "suffix:m") var markings_double_gap := 0.12
@export_range(0.1, 30.0, 0.1, "suffix:m") var markings_dash_length := 3.0
@export_range(0.1, 30.0, 0.1, "suffix:m") var markings_dash_gap := 6.0
@export_range(-100.0, 100.0, 0.1, "suffix:m") var markings_dash_offset := 0.0
@export_range(0.0, 2.0, 0.01, "suffix:m") var markings_edge_inset := 0.2
## Lift above the actual road triangles; keep above any per-lane material overlay.
@export_range(0.001, 0.1, 0.001, "suffix:m") var markings_surface_lift := 0.008
## Additional clearance around the welded socket's width-dependent radius.
@export_range(0.0, 50.0, 0.1, "suffix:m") var markings_junction_clearance := 2.0
@export var markings_hatching_enabled := true
@export_range(0.2, 20.0, 0.1, "suffix:m") var markings_hatch_spacing := 3.0
@export_range(0.02, 1.0, 0.01, "suffix:m") var markings_hatch_width := 0.25
@export_range(15.0, 75.0, 1.0, "suffix:deg") var markings_hatch_angle := 45.0
@export var markings_center_color := Color(1.0, 0.8, 0.12)
@export var markings_line_color := Color(0.95, 0.95, 0.95)
@export var markings_hatch_color := Color(0.95, 0.95, 0.95)
## Optional shared paint material; UV.x is lateral distance, UV.y spline distance.
@export var markings_material_override: Material
@export_group("Terrain Fill")
@export_enum("Disabled", "Rectangle Fill", "Boolean Fill") var terrain_fill_algorithm := 0: set = _set_terrain_fill_algorithm
@export_enum("Cluster Rectangles", "Global Rectangle", "Convex Hull", "Grid Fill", "Radial Rings", "Hex Grid", "Diamond Grid", "Adaptive Triangles", "Adaptive Quadtree Error", "Center Rings Fill", "LOD Rings Adaptive", "Adaptive Delaunay") var terrain_fill_topology := 0: set = _set_terrain_fill_topology
@export_range(-100.0, 100.0, 0.01) var terrain_fill_base_height := 0.0
@export_range(0.001, 1.0, 0.001) var terrain_fill_height_match_epsilon := 0.05
@export_range(0.0, 200.0, 0.01) var terrain_fill_height_match_max_distance := 0.2
@export var terrain_fill_height_assign_only := false: set = _set_terrain_fill_height_assign_only
@export_range(0.2, 6.0, 0.01) var terrain_fill_height_blend_falloff := 2.0
@export_range(0.5, 200.0, 0.1) var terrain_fill_grid_tile_size := 8.0
@export_range(2, 128, 1) var terrain_fill_radial_ring_count := 10
@export_range(6, 256, 1) var terrain_fill_radial_sector_count := 36
@export_range(0.5, 200.0, 0.1) var terrain_fill_hex_radius := 6.0
@export_range(0.5, 200.0, 0.1) var terrain_fill_diamond_tile_size := 8.0
@export_range(1, 8, 1) var terrain_fill_adaptive_max_depth := 3
@export_range(0.25, 2.0, 0.01) var terrain_fill_adaptive_edge_factor := 0.8
@export_range(0.25, 4.0, 0.01) var terrain_fill_adaptive_area_factor := 1.0
@export_range(1, 10, 1) var terrain_fill_quadtree_max_depth := 5
@export_range(0.25, 200.0, 0.1) var terrain_fill_quadtree_min_cell_size := 6.0
@export_range(0.01, 20.0, 0.01) var terrain_fill_quadtree_error_threshold := 0.35
@export_range(0.5, 200.0, 0.1) var terrain_fill_lane_follow_width := 24.0
@export_range(1, 12, 1) var terrain_fill_lane_follow_bands := 3
@export_range(2, 20, 1) var terrain_fill_lod_ring_count := 8
@export_range(1.0, 3.0, 0.01) var terrain_fill_lod_band_growth := 1.4
@export_range(0.25, 20.0, 0.01) var terrain_fill_lod_edge_step_near := 1.0
@export_range(0.25, 80.0, 0.01) var terrain_fill_lod_edge_step_far := 8.0
@export_range(0.25, 20.0, 0.01) var terrain_fill_delaunay_step_near := 1.0
@export_range(0.25, 80.0, 0.01) var terrain_fill_delaunay_step_far := 7.0
@export_range(0.0, 0.45, 0.01) var terrain_fill_delaunay_jitter := 0.2
var terrain_fill_outer_padding := 0.0
@export_subgroup("Rectangle")
@export_range(0.1, 50.0, 0.1) var terrain_rect_fill_cell_size := 1.0
@export_range(0.0, 50.0, 0.1) var terrain_rect_fill_interior_point_step := 0.0
@export_range(0.0, 2.0, 0.001) var terrain_rect_fill_road_margin := 0.0
@export_group("Weld")
@export_subgroup("Lateral Joins")
## Joins source profiles with a shared Lateral Join Layer or legacy Group.
@export_range(0.0, 3.0, 0.01, "suffix:m") var lateral_join_max_gap := 0.35
## Maximum overlap for discovering a facing-edge contact. A detected merge pair
## can continue through a deeper partial overlap toward an angled endpoint.
@export_range(0.0, 3.0, 0.01, "suffix:m") var lateral_join_max_overlap := 1.0
@export_range(0.0, 1.0, 0.01, "suffix:m") var lateral_join_height_tolerance := 0.15
## Zero keeps authored heights. Positive values automatically align joining
## road rows to the host on every rebuild, preserving each row's banking.
@export_range(0.0, 10.0, 0.1, "suffix:m") var lateral_join_height_blend_width := 0.0
@export_range(0.0, 45.0, 0.5, "suffix:deg") var lateral_join_max_angle_degrees := 15.0
## Extend full-width endpoints alongside a continuing host road with a smooth taper.
## Zero keeps the original square ends. Does not alter source curves or widths.
@export_range(0.0, 200.0, 0.5, "suffix:m") var lateral_join_transition_length := 12.0
@export_range(4, 128, 1) var lateral_join_transition_subdivisions := 24
## Width fraction along the taper, from zero to full width. Null uses a tangent S curve.
@export var lateral_join_transition_profile: Curve
@export_subgroup("Junctions")
## Contour mode retains complete road cross sections and builds separate corner bands.
## Legacy is kept for existing scenes. Unsupported contour clusters fall back with diagnostics.
@export_enum("Legacy", "Contour (Experimental)") var junction_geometry_mode := 0
@export_range(0.0, 30.0, 0.25, "suffix:m") var junction_corner_radius := 6.0
@export_range(2, 64, 1) var junction_corner_subdivisions := 16
## 0 is a direct/chamfered connection; 1 is a quadratic rounded corner.
## Intermediate values blend the two outlines. Values outside 0..1 are clamped.
@export var junction_corner_profile: Curve
@export_range(0.1, 30.0, 0.1) var endpoint_snap_distance := 2.0
@export var allow_endpoint_to_midpath := true
@export_range(2, 8, 1) var minimum_connections := 2
@export var strip_shoulder_sidewalk_at_intersections := true
@export_range(0.0, 30.0, 0.001) var intersection_strip_length := 0.0
@export var adaptive_sampling_enabled := true
@export_subgroup("Adaptive Sampling", "adaptive_sampling_")
@export var adaptive_sampling_advanced := false: set = _set_adaptive_sampling_advanced
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_step_scale := 1.0
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_radius_scale := 1.0
@export_range(-10.0, 10.0, 0.01) var adaptive_sampling_offset := 0.0

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_regenerate_in_editor := true
@export_range(0.0, 2.0, 0.01, "suffix:s") var editor_regenerate_debounce_seconds := 0.25
@export var threaded_generation_enabled := true
@export var threaded_show_road_preview := true
## Reuse road blocks, junctions, path terrain strips and indexed surface normals.
## Spatial chunks consume CPU surfaces; partitioning and nonlocal work still run.
@export var incremental_generation_enabled := false
@export_tool_button("Regenerate Road") var regenerate_action := _regenerate_from_button
@export var debug_generation_logs := true
@export var profile_generation_timings := false
@export_group("Runtime Output")
## Single Mesh preserves the existing output. Spatial Chunks allow independent culling
## and retain mesh/collision resources for cells whose final geometry is unchanged.
@export_enum("Single Mesh", "Spatial Chunks") var output_mode := 0
## Cell size in the creator's local coordinates; triangles are not cut at boundaries.
@export_range(1.0, 1000.0, 1.0, "suffix:m") var output_chunk_size := 100.0
## Optional automatic static collision. Existing manually created collision is preserved.
@export var output_generate_collision := false
@export_flags_3d_physics var output_collision_layer := 1
@export_flags_3d_physics var output_collision_mask := 1
@export_file("*.tscn", "*.scn") var bake_output_path := ""
## Explicit opt-in; baking otherwise refuses to overwrite any existing file.
@export var bake_allow_overwrite := false
@export_tool_button("Bake Runtime Scene") var bake_runtime_action := _bake_runtime_from_button
@export_group("Terrain Influence Debug")
@export var terrain_influence_debug_draw := false: set = _set_terrain_influence_debug_draw
@export var terrain_influence_debug_color := Color(0.96, 0.32, 0.1, 1.0)
@export_range(0.0, 5.0, 0.01) var terrain_influence_debug_lift := 0.1

const MESH_NODE_NAME := "GeneratedSplineRoadWelded"
const LEGACY_MESH_NODE_NAME := "GeneratedSplineRoad"
const LANE_MATERIAL_OVERLAY_NODE_NAME := "GeneratedLaneMaterialOverlays"
const TERRAIN_INFLUENCE_DEBUG_NODE_NAME := "TerrainInfluenceDebugBands"
const STRIP_SIDE_BOTH := 0
const STRIP_SIDE_LEFT := -1
const STRIP_SIDE_RIGHT := 1
const TERRAIN_FILL_DISABLED := 0
const TERRAIN_FILL_RECTANGLE := 1
const TERRAIN_FILL_BOOLEAN := 2
const TERRAIN_FILL_TOPOLOGY_CLUSTER_RECTS := 0
const TERRAIN_FILL_TOPOLOGY_GLOBAL_RECT := 1
const TERRAIN_FILL_TOPOLOGY_CONVEX_HULL := 2
const TERRAIN_FILL_TOPOLOGY_GRID := 3
const TERRAIN_FILL_TOPOLOGY_RADIAL := 4
const TERRAIN_FILL_TOPOLOGY_HEX := 5
const TERRAIN_FILL_TOPOLOGY_DIAMOND := 6
const TERRAIN_FILL_TOPOLOGY_ADAPTIVE := 7
const TERRAIN_FILL_TOPOLOGY_QUADTREE_ERROR := 8
const TERRAIN_FILL_TOPOLOGY_LANE_FOLLOW := 9
const TERRAIN_FILL_TOPOLOGY_LOD_RINGS := 10
const TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY := 11
const ROAD_ORIENTATION_CURVE_UP := 0
const ROAD_ORIENTATION_WORLD_UP := 1
const ROAD_ORIENTATION_BANK_INTO_CURVE := 2
const TERRAIN_CUT_FILL_BALANCED := 0
const TERRAIN_CUT_FILL_CUT_ONLY := 1
const TERRAIN_CUT_FILL_FILL_ONLY := 2
const TERRAIN_RECT_FILL_MAX_TRIANGLES := 2500000
const TERRAIN_FILL_GRID_MAX_TILES := 12000
const TERRAIN_FILL_RADIAL_MAX_CELLS := 16000
const TERRAIN_FILL_HEX_MAX_CELLS := 14000
const TERRAIN_FILL_DIAMOND_MAX_CELLS := 14000
const TERRAIN_FILL_QUADTREE_MAX_CELLS := 18000
const TERRAIN_FILL_DELAUNAY_MAX_POINTS := 6000
const TERRAIN_RECT_FILL_INTERIOR_MAX_POINTS_PER_POLYGON := 5000
const TERRAIN_INFLUENCE_DEFAULT_WIDTH := 6.0
const TERRAIN_INFLUENCE_DEFAULT_BLEND := 3.0
const TERRAIN_INFLUENCE_DEFAULT_STRENGTH := 1.0

# Legacy terrain defaults kept internal (not exposed in Inspector).
var terrain_left_width := 0.0
var terrain_right_width := 0.0
var terrain_road_clearance := 0.02
var terrain_detection_width_scale := 1.0
var terrain_growth_scan_step := 0.25
var terrain_growth_max_delta_per_row := 1.25
var terrain_skirt_depth := 0.0
var terrain_skirt_segments := 3
var terrain_skirt_outward := 1.0
var terrain_skirt_profile := 1.4
var terrain_skirt_soften_slope_deg := 12.0
var terrain_skirt_soften_max_drop := 1.0
var terrain_skirt_soften_power := 1.2
var terrain_skirt_soften_area_rings := 3
var terrain_skirt_soften_area_falloff := 1.6
var terrain_skirt_soften_row_smooth_passes := 1
var terrain_subdivisions := 1
var terrain_adaptive_subdivisions_enabled := true
var terrain_adaptive_subdivisions_per_meter := 0.15
var terrain_adaptive_noise_quality := 1.5
var terrain_adaptive_subdivisions_max := 80
var terrain_noise_enabled := false
var terrain_noise_amplitude := 0.0
var terrain_noise_frequency := 0.06
var terrain_noise_seed := 1337
var terrain_noise_falloff := 1.5
var terrain_cut_fill_mode := 0
var terrain_artifact_safe_stitch := true
var terrain_chain_smooth_passes := 1
var uv_length_scale := 0.2
var _last_signature := ""
var _terrain_influence_strips: Array = []
var _terrain_influence_loops: Array = []
var _generation_thread: Thread
var _thread_regenerate_requested := false
var _thread_cancel_mutex := Mutex.new()
var _thread_cancel_token: Dictionary = {}
var _pending_regenerate_signature := ""
var _pending_regenerate_time_left := 0.0
var _output_ready := false
var _terrain_surface_data: Dictionary = {}
var _terrain_surface_revision := 0
var _marking_rows: Array = []
var _marking_exclusions: Dictionary = {}



var _path_sampler := preload("./road_path_sampler.gd").new()
var _preset_controller := preload("./road_preset_controller.gd").new()
var _mesh_builder := preload("./road_mesh_builder.gd").new()
var _junction_builder := preload("./road_junction_builder.gd").new()
var _terrain_builder := preload("./road_terrain_builder.gd").new()
var _terrain_influence_builder := preload("./road_terrain_influence_builder.gd").new()
var _runtime_output := preload("./road_runtime_output.gd").new()
var _marking_builder := preload("./road_marking_builder.gd").new()
var _lateral_join := preload("./road_lateral_join.gd").new()
var _appearance_update := preload("./road_appearance_update.gd").new()
var _lane_overlay_cache := preload("./road_lane_overlay_cache.gd").new()


func _ready() -> void:
	set_process(true)
	if _can_generate():
		regenerate()
	else:
		_debug_log("_ready skipped regenerate: _can_generate() is false.")


func _process(_delta: float) -> void:
	_poll_threaded_generation()
	if not Engine.is_editor_hint():
		return
	if not auto_regenerate_in_editor:
		return
	if not _can_generate():
		return

	var sig := _build_signature()
	if sig == _last_signature:
		_pending_regenerate_signature = ""
		_pending_regenerate_time_left = 0.0
		return

	if sig != _pending_regenerate_signature:
		_pending_regenerate_signature = sig
		_pending_regenerate_time_left = maxf(0.0, editor_regenerate_debounce_seconds)
		if _is_generation_thread_active():
			_request_thread_regenerate_cancel()
		if _pending_regenerate_time_left > 0.0001:
			return
	else:
		_pending_regenerate_time_left = maxf(0.0, _pending_regenerate_time_left - _delta)
		if _pending_regenerate_time_left > 0.0001:
			return

	_pending_regenerate_signature = ""
	_pending_regenerate_time_left = 0.0
	_last_signature = sig
	regenerate()


## Dependents must also see edits waiting for the editor debounce, before a
## worker exists. Manual-only generators do not promise an automatic rebuild.
func is_road_generation_pending() -> bool:
	if _is_generation_thread_active() or _thread_regenerate_requested:
		return true
	return Engine.is_editor_hint() and auto_regenerate_in_editor and _can_generate() \
		and _last_signature != _build_signature()


func _exit_tree() -> void:
	_cancel_thread_job()
	_join_generation_thread()


func _regenerate_from_button() -> void:
	if _can_generate():
		_pending_regenerate_signature = ""
		_pending_regenerate_time_left = 0.0
		regenerate()


func _bake_runtime_from_button() -> void:
	var result := bake_runtime_scene(bake_output_path, bake_allow_overwrite)
	if result != OK:
		push_warning("Roda-Gen bake failed: %s. Set a new .tscn/.scn output path and wait for Regenerate Road to finish." % error_string(result))
	else:
		print("[Roda-Gen] Baked runtime road: ", bake_output_path)


func _apply_preset_from_button() -> void:
	var result := apply_road_preset()
	if result != OK:
		push_warning("Roda-Gen preset failed: %s. Check the source paths and preset; wait for active generation to finish." % error_string(result))


## Apply once, then edit the resulting settings/materials/barriers normally.
func apply_road_preset(preset: Resource = null) -> Error:
	return _preset_controller.apply(self, preset)


func _apply_road_preset_state(state: Dictionary) -> void:
	_preset_controller.apply_state(self, state)


## Saves this generator's final road/terrain/wall meshes, overlays, markings,
## preset-owned barriers and collisions. Leaves source intact; does not regenerate.
func bake_runtime_scene(path: String, allow_overwrite := false) -> Error:
	if path.is_empty() or not path.get_extension().to_lower() in ["tscn", "scn"]:
		return ERR_INVALID_PARAMETER
	if not _output_ready or _is_generation_thread_active() or _thread_regenerate_requested or not _pending_regenerate_signature.is_empty() or _last_signature != _build_signature():
		return ERR_BUSY
	if not _preset_controller.outputs_are_current(self):
		return ERR_BUSY
	var absolute_path := ProjectSettings.globalize_path(path).simplify_path()
	var ancestor: Node = self
	while ancestor != null:
		if not ancestor.scene_file_path.is_empty() and absolute_path == ProjectSettings.globalize_path(ancestor.scene_file_path).simplify_path():
			return ERR_INVALID_PARAMETER
		ancestor = ancestor.get_parent()
	if FileAccess.file_exists(path) and not allow_overwrite:
		return ERR_ALREADY_EXISTS
	var names: Array[String] = [MESH_NODE_NAME, LEGACY_MESH_NODE_NAME, LANE_MATERIAL_OVERLAY_NODE_NAME]
	if output_mode == 1:
		names = [_runtime_output.CHUNKS_NODE_NAME, LANE_MATERIAL_OVERLAY_NODE_NAME]
	names.append(_marking_builder.NODE_NAME)
	if _preset_controller.owned_container(self) != null:
		names.append(_preset_controller.NODE_NAME)
	var packed := _runtime_output.pack_output(self, names)
	if packed == null:
		return ERR_DOES_NOT_EXIST
	return ResourceSaver.save(packed, path)


## Output-stage metrics only; not a count of regenerated source segments.
func get_output_rebuild_stats() -> Dictionary:
	return _runtime_output.last_stats.duplicate()


## Source and CPU surface construction, separate from final output chunk reuse.
func get_source_rebuild_stats() -> Dictionary:
	var stats := _path_sampler.last_stats.duplicate(true)
	stats["junction_search"] = _junction_builder.last_stats.duplicate()
	stats["junction_geometry"] = _junction_builder.geometry_cache.last_stats.duplicate(true)
	stats["contour_junctions"] = _junction_builder.contour.reports.duplicate(true)
	stats["lateral_joins"] = _lateral_join.stats.duplicate(true)
	stats["surface_normals"] = _mesh_builder.normal_cache_stats.duplicate(true)
	# The worker updates strip counters. Do not read its mutable Dictionary until
	# its result has been joined, including the finished-but-not-yet-applied case.
	stats["terrain_strips"] = {"pending": true} if _is_generation_thread_active() else _terrain_builder.last_stats.duplicate(true)
	return stats


func clear_source_generation_cache() -> void:
	_appearance_update.invalidate()
	_path_sampler.clear_cache()
	_mesh_builder.clear_incremental_cache()
	_runtime_output.clear_partition_cache()
	_marking_builder.clear_cache()
	_lane_overlay_cache.clear()
	_junction_builder.clear_cache()
	if _is_generation_thread_active():
		_terrain_builder.request_incremental_cache_clear()
	else:
		_terrain_builder.clear_incremental_cache()


func get_appearance_update_stats() -> Dictionary:
	return _appearance_update.last_stats.duplicate()


func get_marking_stats() -> Dictionary:
	return _marking_builder.last_stats.duplicate()


func get_lane_overlay_stats() -> Dictionary:
	return _lane_overlay_cache.last_stats.duplicate()


func _set_terrain_influence_debug_draw(value: bool) -> void:
	terrain_influence_debug_draw = value
	if not value:
		_clear_terrain_influence_debug_node()
	_last_signature = ""
	if _can_generate():
		regenerate()


func _set_terrain_fill_algorithm(value: int) -> void:
	terrain_fill_algorithm = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_terrain_fill_topology(value: int) -> void:
	terrain_fill_topology = clampi(value, 0, TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY)
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_terrain_fill_height_assign_only(value: bool) -> void:
	terrain_fill_height_assign_only = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_adaptive_sampling_advanced(value: bool) -> void:
	adaptive_sampling_advanced = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_road_orientation_mode(value: int) -> void:
	road_orientation_mode = clampi(value, ROAD_ORIENTATION_CURVE_UP, ROAD_ORIENTATION_BANK_INTO_CURVE)
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "custom_preset" and preset_selection != 3:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "road_bank_max_degrees"
		or property.name == "road_bank_strength"
		or property.name == "road_bank_sample_distance"
	) and road_orientation_mode != ROAD_ORIENTATION_BANK_INTO_CURVE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "adaptive_sampling_step_scale"
		or property.name == "adaptive_sampling_radius_scale"
		or property.name == "adaptive_sampling_offset"
	) and not adaptive_sampling_advanced:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_topology"
		or property.name == "terrain_fill_base_height"
		or property.name == "terrain_fill_height_match_epsilon"
		or property.name == "terrain_fill_height_match_max_distance"
		or property.name == "terrain_fill_height_assign_only"
		or property.name == "terrain_fill_height_blend_falloff"
	) and terrain_fill_algorithm == TERRAIN_FILL_DISABLED:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_height_match_max_distance"
		or property.name == "terrain_fill_height_blend_falloff"
	) and terrain_fill_height_assign_only:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_grid_tile_size"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_GRID
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_radial_ring_count"
		or property.name == "terrain_fill_radial_sector_count"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_RADIAL
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_hex_radius"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_HEX
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_diamond_tile_size"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_DIAMOND
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_adaptive_max_depth"
		or property.name == "terrain_fill_adaptive_edge_factor"
		or property.name == "terrain_fill_adaptive_area_factor"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_ADAPTIVE
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_quadtree_max_depth"
		or property.name == "terrain_fill_quadtree_min_cell_size"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_QUADTREE_ERROR
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_quadtree_error_threshold"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_QUADTREE_ERROR
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_lane_follow_width"
		or property.name == "terrain_fill_lane_follow_bands"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_LANE_FOLLOW
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_lod_ring_count"
		or property.name == "terrain_fill_lod_band_growth"
		or property.name == "terrain_fill_lod_edge_step_near"
		or property.name == "terrain_fill_lod_edge_step_far"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_LOD_RINGS
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_fill_delaunay_step_near"
		or property.name == "terrain_fill_delaunay_step_far"
		or property.name == "terrain_fill_delaunay_jitter"
	) and (
		terrain_fill_algorithm == TERRAIN_FILL_DISABLED
		or terrain_fill_topology != TERRAIN_FILL_TOPOLOGY_ADAPTIVE_DELAUNAY
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_rect_fill_cell_size"
		or property.name == "terrain_rect_fill_interior_point_step"
		) and terrain_fill_algorithm != TERRAIN_FILL_RECTANGLE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_rect_fill_road_margin"
	) and terrain_fill_algorithm != TERRAIN_FILL_RECTANGLE:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _can_generate() -> bool:
	return not Engine.is_editor_hint() or generate_in_editor


func _debug_log(message: String) -> void:
	if not debug_generation_logs:
		return
	print("[SplineRoadWelded] " + message)


func _profile_start() -> int:
	if not profile_generation_timings:
		return 0
	return Time.get_ticks_usec()


func _profile_log(label: String, start_usec: int, extra: String = "") -> void:
	if not profile_generation_timings or start_usec <= 0:
		return
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	var suffix := ""
	if not extra.is_empty():
		suffix = " " + extra
	print("[SplineRoadWelded][profile] %s: %.2f ms%s" % [label, elapsed_ms, suffix])


func regenerate() -> void:
	# A running job still owns the component snapshots if threading was just
	# disabled in the Inspector. Cancel/join it before configuring a synchronous job.
	if _is_generation_thread_active():
		_request_thread_regenerate_cancel()
		_last_signature = _build_signature()
		_debug_log("regenerate() deferred while threaded finalize is running.")
		return
	if _appearance_update.try_refresh(self):
		return
	_output_ready = false
	_appearance_update.begin(self)
	_debug_log("regenerate() start on " + str(get_path()))
	var profile_total_start := _profile_start()
	var profile_cleanup_start := _profile_start()
	_cleanup_legacy_generated_children()
	_profile_log("main cleanup legacy nodes", profile_cleanup_start)

	var profile_resolve_start := _profile_start()
	var paths := _resolve_paths()
	_profile_log("main resolve paths", profile_resolve_start, "paths=%s source_paths=%s" % [paths.size(), source_paths.size()])
	_lateral_join.configure(self, paths)
	_debug_log("resolved paths: " + str(paths.size()) + " (source_paths=" + str(source_paths.size()) + ")")
	if paths.is_empty():
		if not source_paths.is_empty():
			push_warning("SplineRoadWelded: no valid Path3D found in source_paths.")
		_debug_log("no valid paths, clearing generated mesh node.")
		_clear_mesh_node()
		_clear_terrain_influence_debug_node()
		return

	_terrain_influence_strips = []
	_terrain_influence_loops = []
	_mesh_builder.configure(self)
	_junction_builder.configure(self)
	_terrain_builder.configure(self)
	_terrain_influence_builder.configure(self)
	_path_sampler.configure(self)
	_marking_builder.configure(self)
	var sampled := _path_sampler.sample_paths(paths, global_transform.affine_inverse())
	var verts: PackedVector3Array = sampled["verts"]
	var normals: PackedVector3Array = sampled["normals"]
	var uvs: PackedVector2Array = sampled["uvs"]
	var lane_indices: PackedInt32Array = sampled["lane_indices"]
	var shoulder_indices: PackedInt32Array = sampled["shoulder_indices"]
	var sidewalk_indices: PackedInt32Array = sampled["sidewalk_indices"]
	var terrain_indices: PackedInt32Array = sampled["terrain_indices"]
	var wall_indices: PackedInt32Array = sampled["wall_indices"]
	var sockets: Array[Dictionary] = sampled["sockets"]
	var socket_keys: Dictionary = sampled["socket_keys"]
	var path_rows: Array = sampled["path_rows"]
	var path_weld_snap: Array = sampled["path_weld_snap"]
	var path_weld_allow_midpath: Array = sampled["path_weld_allow_midpath"]
	var path_weld_strip_enabled: Array = sampled["path_weld_strip_enabled"]
	var path_weld_strip_length: Array = sampled["path_weld_strip_length"]
	# Retain lane layouts even when paint is disabled, so enabling it needs no
	# topology rebuild. Existing sampled layouts are reused when available.
	for path_id in range(path_rows.size()):
		for row: Dictionary in path_rows[path_id]:
			if not row.has("marking_layout"):
				row.marking_layout = paths[path_id].get_lane_layout_at_offset(row.distance) if paths[path_id].has_method("get_lane_layout_at_offset") else {"enabled": false}
	_marking_rows = path_rows
	_appearance_update.sampled(self)
	_marking_exclusions = {}
	_lateral_join.prepare(verts, path_rows)

	var profile_debug_visual_start := _profile_start()
	_update_terrain_influence_debug_visual()
	_profile_log("main terrain influence debug visual", profile_debug_visual_start)

	var profile_weld_start := _profile_start()
	var endpoint_count := sockets.size()
	if endpoint_count > 0:
		_augment_with_midpath_sockets(
			sockets,
			socket_keys,
			path_rows,
			endpoint_count,
			path_weld_allow_midpath,
			path_weld_snap
		)
	_augment_with_midpath_pair_sockets(
		sockets,
		socket_keys,
		path_rows,
		path_weld_allow_midpath,
		path_weld_snap
	)
	var paths_with_mid_intersections: Dictionary = {}
	for s in sockets:
		if not bool(s.get("is_endpoint", true)):
			paths_with_mid_intersections[int(s.get("path_id", -1))] = true
	var stripped_side_indices: Dictionary = {}

	if sockets.size() < minimum_connections:
		if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
			_append_lane_fallback_from_path_rows(lane_indices, path_rows)
		if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty() and _terrain_influence_strips.is_empty():
			_debug_log("no indices after fallback (low sockets branch), clearing mesh node.")
			_clear_mesh_node()
			return
		_debug_log(
			"assign mesh (low sockets): verts=%s lane=%s shoulder=%s sidewalk=%s terrain=%s wall=%s"
			% [verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), terrain_indices.size(), wall_indices.size()]
		)
		_profile_log("main weld/topology", profile_weld_start, "branch=low_sockets sockets=%s" % [sockets.size()])
		_finalize_generation(
			verts,
			normals,
			uvs,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			terrain_indices,
			wall_indices,
			path_rows
		)
		_profile_log("main regenerate total", profile_total_start, "branch=low_sockets")
		return

	var clusters := _cluster_sockets(sockets, minimum_connections, path_weld_snap, 1.0)
	if clusters.is_empty():
		clusters = _cluster_sockets(sockets, max(2, minimum_connections), path_weld_snap, 2.5)
	if clusters.is_empty():
		push_warning(
			"SplineRoadWelded: no weld clusters found; generating roads without intersections."
		)
		_debug_log(
			"assign mesh (no clusters): verts=%s lane=%s shoulder=%s sidewalk=%s terrain=%s wall=%s"
			% [verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), terrain_indices.size(), wall_indices.size()]
		)
		_profile_log("main weld/topology", profile_weld_start, "branch=no_clusters sockets=%s" % [sockets.size()])
		_finalize_generation(
			verts,
			normals,
			uvs,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			terrain_indices,
			wall_indices,
			path_rows
		)
		_profile_log("main regenerate total", profile_total_start, "branch=no_clusters")
		return

	_record_marking_junction_exclusions(sockets, clusters, path_rows)
	_junction_builder.geometry_cache.set_paths(paths)
	for cluster in clusters:
		_junction_builder.weld_cluster(
			verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices,
			sockets, cluster, path_rows, stripped_side_indices, path_weld_snap,
			path_weld_strip_enabled, path_weld_strip_length, paths_with_mid_intersections,
			invert_faces
		)
	if junction_geometry_mode == 1:
		_junction_builder.contour.remove_retired_triangles(terrain_indices, _junction_builder.contour.removed_vertices)
		_junction_builder.contour.remove_retired_triangles(wall_indices, _junction_builder.contour.removed_vertices)
		for region in _junction_builder.contour.regions:
			var path_id := int(region.path)
			if not _marking_exclusions.has(path_id):
				_marking_exclusions[path_id] = []
			_marking_exclusions[path_id].append(Vector2(float(region.from), float(region.to)))

	if strip_shoulder_sidewalk_at_intersections and not stripped_side_indices.is_empty():
		shoulder_indices = _move_blocked_triangles_to_lane(shoulder_indices, lane_indices, stripped_side_indices)
		sidewalk_indices = _move_blocked_triangles_to_lane(sidewalk_indices, lane_indices, stripped_side_indices)
	if junction_geometry_mode == 1:
		stripped_side_indices.merge(_junction_builder.contour.removed_vertices)

	if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
		_append_lane_fallback_from_path_rows(lane_indices, path_rows)
	if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty() and _terrain_influence_strips.is_empty():
		_debug_log("no indices after weld branch fallback, clearing mesh node.")
		_clear_mesh_node()
		return

	_debug_log(
		"assign mesh (welded): verts=%s lane=%s shoulder=%s sidewalk=%s terrain=%s wall=%s"
		% [verts.size(), lane_indices.size(), shoulder_indices.size(), sidewalk_indices.size(), terrain_indices.size(), wall_indices.size()]
	)
	_profile_log("main weld/topology", profile_weld_start, "branch=welded clusters=%s sockets=%s" % [clusters.size(), sockets.size()])
	_finalize_generation(
		verts,
		normals,
		uvs,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		terrain_indices,
		wall_indices,
		path_rows,
		stripped_side_indices
	)
	_profile_log("main regenerate total", profile_total_start, "branch=welded")


func _record_marking_junction_exclusions(sockets: Array[Dictionary], clusters: Array, path_rows: Array) -> void:
	# Also used by preset barrier spans, including presets with paint disabled.
	for cluster in clusters:
		for socket_index in cluster:
			var socket: Dictionary = sockets[socket_index]
			var path_id := int(socket.get("path_id", -1))
			var row_index := int(socket.get("row_idx", -1))
			if path_id < 0 or path_id >= path_rows.size() or row_index < 0 or row_index >= path_rows[path_id].size():
				continue
			var row: Dictionary = path_rows[path_id][row_index]
			var radius := maxf(float(socket.get("width", road_width)) * 0.75, float(socket.get("weld_strip_length", 0.0))) + markings_junction_clearance
			var offset := float(row.get("distance", 0.0))
			if not _marking_exclusions.has(path_id):
				_marking_exclusions[path_id] = []
			_marking_exclusions[path_id].append(Vector2(offset - radius, offset + radius))


func _finalize_generation(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	terrain_indices: PackedInt32Array,
	wall_indices: PackedInt32Array,
	path_rows: Array,
	blocked_side_vertices: Dictionary = {}
) -> void:
	var profile_finalize_start := _profile_start()
	_lateral_join.apply(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices,
		path_rows, _marking_exclusions, blocked_side_vertices)
	if not _path_rows_need_terrain_or_walls(path_rows):
		_finalize_generation_after_terrain_and_walls(
			verts,
			normals,
			uvs,
			lane_indices,
			shoulder_indices,
			sidewalk_indices,
			terrain_indices,
			wall_indices
		)
		_profile_log("main direct road-only finalize", profile_finalize_start, "verts=%s" % verts.size())
		return
	if threaded_generation_enabled and _start_threaded_finalize(
		verts,
		normals,
		uvs,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		terrain_indices,
		wall_indices,
		path_rows,
		blocked_side_vertices
	):
		_profile_log("main start threaded finalize", profile_finalize_start, "verts=%s terrain_indices=%s" % [verts.size(), terrain_indices.size()])
		if threaded_show_road_preview:
			var profile_preview_start := _profile_start()
			_assign_road_preview_mesh(
				verts,
				normals,
				uvs,
				lane_indices,
				shoulder_indices,
				sidewalk_indices
			)
			_profile_log("main road preview mesh", profile_preview_start)
		return
	var profile_prepare_start := _profile_start()
	_finalize_generation_prepare_terrain_and_walls(
		verts,
		normals,
		uvs,
		terrain_indices,
		path_rows,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		wall_indices,
		blocked_side_vertices
	)
	_profile_log("main terrain+walls finalize", profile_prepare_start, "terrain_tris=%s wall_tris=%s" % [terrain_indices.size() / 3, wall_indices.size() / 3])
	var profile_after_start := _profile_start()
	_finalize_generation_after_terrain_and_walls(
		verts,
		normals,
		uvs,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		terrain_indices,
		wall_indices
	)
	_profile_log("main final mesh apply pipeline", profile_after_start)


func _path_rows_need_terrain_or_walls(path_rows: Array) -> bool:
	if terrain_fill_algorithm != TERRAIN_FILL_DISABLED:
		return true
	if not _terrain_influence_strips.is_empty() or not _terrain_influence_loops.is_empty():
		return true
	for rows_value in path_rows:
		var rows: Array = rows_value
		for row_value in rows:
			var row: Dictionary = row_value
			if float(row.get("terrain_left_width", 0.0)) > 0.0001:
				return true
			if float(row.get("terrain_right_width", 0.0)) > 0.0001:
				return true
			if float(row.get("outer_wall_height", 0.0)) > 0.0001:
				return true
	return false


func _finalize_generation_prepare_terrain_and_walls(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	wall_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	var profile_terrain_start := _profile_start()
	_append_terrain_with_mode(
		verts,
		normals,
		uvs,
		terrain_indices,
		path_rows,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		blocked_side_vertices,
		cancel_token
	)
	_profile_log("finalize terrain with mode", profile_terrain_start, "terrain_tris=%s" % [terrain_indices.size() / 3])
	if _is_generation_cancelled(cancel_token):
		return
	var profile_walls_start := _profile_start()
	_append_outer_walls_from_path_rows(verts, normals, uvs, wall_indices, path_rows)
	_profile_log("finalize outer walls", profile_walls_start, "wall_tris=%s" % [wall_indices.size() / 3])


func _finalize_generation_after_terrain_and_walls(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	terrain_indices: PackedInt32Array,
	wall_indices: PackedInt32Array,
	influence_already_applied := false
) -> void:
	var profile_over_road_start := _profile_start()
	var over_road_snap_context := _build_over_road_snap_context(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	_profile_log("main build over-road snap context", profile_over_road_start)
	if not influence_already_applied:
		var profile_influence_fill_start := _profile_start()
		_append_terrain_influence_fill_faces(verts, normals, uvs, terrain_indices)
		_profile_log("main terrain influence fill faces", profile_influence_fill_start, "terrain_tris=%s" % [terrain_indices.size() / 3])
		var profile_influence_apply_start := _profile_start()
		_apply_terrain_influence_strips_to_mesh(
			verts,
			terrain_indices,
			[],
			over_road_snap_context
		)
		_profile_log("main terrain influence apply to mesh", profile_influence_apply_start)
	var profile_reorient_start := _profile_start()
	var flipped_terrain_tris := _reorient_indices_to_desired_normal(terrain_indices, verts, _terrain_desired_normal())
	_profile_log("main terrain reorient", profile_reorient_start, "flipped=%s" % [flipped_terrain_tris])
	if flipped_terrain_tris > 0:
		_debug_log("terrain reorient flipped tris=%s" % [flipped_terrain_tris])
	var profile_build_mesh_start := _profile_start()
	var final_mesh := _build_mesh(
		verts,
		normals,
		uvs,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		terrain_indices,
		wall_indices
	)
	_profile_log("main build ArrayMesh", profile_build_mesh_start, "surfaces=%s uploads=%s verts=%s" % [_runtime_output._surface_count(final_mesh), final_mesh.get_surface_count(), verts.size()])
	var profile_assign_start := _profile_start()
	_assign_mesh(
		final_mesh
	)
	_profile_log("main assign mesh node", profile_assign_start)
	_marking_builder.assign(self, verts, _marking_rows, _marking_exclusions,
		_lateral_join.marking_cuts, lane_indices)
	_appearance_update.complete(self, verts, lane_indices)
	_last_signature = _appearance_update.generation_signature
	_output_ready = true
	_preset_controller.refresh_barriers(self)


func _assign_road_preview_mesh(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array
) -> void:
	# A road-only preview would discard/recreate unchanged terrain chunk resources.
	# Keep the previous complete spatial output visible until the worker finishes.
	if output_mode == 1:
		return
	if lane_indices.is_empty() and shoulder_indices.is_empty() and sidewalk_indices.is_empty():
		return
	var empty := PackedInt32Array()
	var profile_build_preview_start := _profile_start()
	var preview_mesh := _build_mesh(
		verts,
		normals,
		uvs,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		empty,
		empty
	)
	_profile_log("main build road preview ArrayMesh", profile_build_preview_start, "surfaces=%s" % [preview_mesh.get_surface_count()])
	_assign_mesh(preview_mesh)
	_debug_log("threaded road preview applied.")


func _start_threaded_finalize(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	terrain_indices: PackedInt32Array,
	wall_indices: PackedInt32Array,
	path_rows: Array,
	blocked_side_vertices: Dictionary = {}
) -> bool:
	if _is_generation_thread_active():
		return false
	if _generation_thread != null:
		_generation_thread.wait_to_finish()
		_generation_thread = null
		_clear_thread_cancel_token()
	var cancel_token := _create_thread_cancel_token()
	var job := {
		"verts": verts,
		"normals": normals,
		"uvs": uvs,
		"lane_indices": lane_indices,
		"shoulder_indices": shoulder_indices,
		"sidewalk_indices": sidewalk_indices,
		"terrain_indices": terrain_indices,
		"wall_indices": wall_indices,
		"path_rows": path_rows,
		"blocked_side_vertices": blocked_side_vertices,
		"terrain_influence_strips": _terrain_influence_strips.duplicate(true),
		"cancel_token": cancel_token,
	}
	_generation_thread = Thread.new()
	var err := _generation_thread.start(Callable(self, "_thread_finalize_generation_job").bind(job))
	if err != OK:
		push_warning("SplineRoadWelded: threaded finalize failed to start; fallback to main thread.")
		_generation_thread = null
		_clear_thread_cancel_token()
		return false
	_thread_regenerate_requested = false
	_last_signature = _build_signature()
	_debug_log("threaded finalize started.")
	return true


func _thread_finalize_generation_job(job: Dictionary) -> Dictionary:
	var profile_thread_total_start := _profile_start()
	var verts: PackedVector3Array = job.get("verts", PackedVector3Array())
	var normals: PackedVector3Array = job.get("normals", PackedVector3Array())
	var uvs: PackedVector2Array = job.get("uvs", PackedVector2Array())
	var lane_indices: PackedInt32Array = job.get("lane_indices", PackedInt32Array())
	var shoulder_indices: PackedInt32Array = job.get("shoulder_indices", PackedInt32Array())
	var sidewalk_indices: PackedInt32Array = job.get("sidewalk_indices", PackedInt32Array())
	var terrain_indices: PackedInt32Array = job.get("terrain_indices", PackedInt32Array())
	var wall_indices: PackedInt32Array = job.get("wall_indices", PackedInt32Array())
	var path_rows: Array = job.get("path_rows", [])
	var blocked_side_vertices: Dictionary = job.get("blocked_side_vertices", {})
	var terrain_influence_strips: Array = job.get("terrain_influence_strips", [])
	var cancel_token: Dictionary = job.get("cancel_token", {})
	var profile_prepare_start := _profile_start()
	_finalize_generation_prepare_terrain_and_walls(
		verts,
		normals,
		uvs,
		terrain_indices,
		path_rows,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		wall_indices,
		blocked_side_vertices,
		cancel_token
	)
	_profile_log("thread terrain+walls", profile_prepare_start, "terrain_tris=%s wall_tris=%s" % [terrain_indices.size() / 3, wall_indices.size() / 3])
	if _is_generation_cancelled(cancel_token):
		job["ok"] = false
		job["cancelled"] = true
		_profile_log("thread finalize total", profile_thread_total_start, "cancelled=true")
		return job
	var profile_over_road_start := _profile_start()
	var over_road_snap_context := _build_over_road_snap_context(
		verts,
		lane_indices,
		shoulder_indices,
		sidewalk_indices
	)
	_profile_log("thread build over-road snap context", profile_over_road_start)
	if _is_generation_cancelled(cancel_token):
		job["ok"] = false
		job["cancelled"] = true
		_profile_log("thread finalize total", profile_thread_total_start, "cancelled=true")
		return job
	var profile_influence_fill_start := _profile_start()
	_append_terrain_influence_fill_faces(verts, normals, uvs, terrain_indices, terrain_influence_strips, cancel_token)
	_profile_log("thread terrain influence fill faces", profile_influence_fill_start, "terrain_tris=%s strips=%s" % [terrain_indices.size() / 3, terrain_influence_strips.size()])
	if _is_generation_cancelled(cancel_token):
		job["ok"] = false
		job["cancelled"] = true
		_profile_log("thread finalize total", profile_thread_total_start, "cancelled=true")
		return job
	var profile_influence_apply_start := _profile_start()
	_apply_terrain_influence_strips_to_mesh(
		verts,
		terrain_indices,
		terrain_influence_strips,
		over_road_snap_context,
		cancel_token
	)
	_profile_log("thread terrain influence apply to mesh", profile_influence_apply_start)
	if _is_generation_cancelled(cancel_token):
		job["ok"] = false
		job["cancelled"] = true
		_profile_log("thread finalize total", profile_thread_total_start, "cancelled=true")
		return job
	job["ok"] = true
	job["influence_applied"] = true
	_profile_log("thread finalize total", profile_thread_total_start, "cancelled=false verts=%s terrain_tris=%s" % [verts.size(), terrain_indices.size() / 3])
	return job


func _poll_threaded_generation() -> void:
	if _generation_thread == null:
		return
	if _generation_thread.is_alive():
		return
	var result: Variant = _generation_thread.wait_to_finish()
	_generation_thread = null
	_clear_thread_cancel_token()
	if _thread_regenerate_requested:
		_thread_regenerate_requested = false
		_debug_log("threaded finalize result discarded; regenerate requested during job.")
		if Engine.is_editor_hint() and not _pending_regenerate_signature.is_empty():
			return
		if _can_generate():
			regenerate()
		return
	if typeof(result) != TYPE_DICTIONARY:
		push_warning("SplineRoadWelded: threaded finalize returned invalid result.")
		return
	if not _can_generate():
		_debug_log("threaded finalize ready but generation is currently disabled; result discarded.")
		return
	_apply_threaded_finalize_result(result)


func _apply_threaded_finalize_result(result: Dictionary) -> void:
	if bool(result.get("cancelled", false)):
		_debug_log("threaded finalize cancelled.")
		return
	if not bool(result.get("ok", false)):
		push_warning("SplineRoadWelded: threaded finalize reported failure.")
		return
	var verts: PackedVector3Array = result.get("verts", PackedVector3Array())
	var normals: PackedVector3Array = result.get("normals", PackedVector3Array())
	var uvs: PackedVector2Array = result.get("uvs", PackedVector2Array())
	var lane_indices: PackedInt32Array = result.get("lane_indices", PackedInt32Array())
	var shoulder_indices: PackedInt32Array = result.get("shoulder_indices", PackedInt32Array())
	var sidewalk_indices: PackedInt32Array = result.get("sidewalk_indices", PackedInt32Array())
	var terrain_indices: PackedInt32Array = result.get("terrain_indices", PackedInt32Array())
	var wall_indices: PackedInt32Array = result.get("wall_indices", PackedInt32Array())
	var influence_applied := bool(result.get("influence_applied", false))
	_finalize_generation_after_terrain_and_walls(
		verts,
		normals,
		uvs,
		lane_indices,
		shoulder_indices,
		sidewalk_indices,
		terrain_indices,
		wall_indices,
		influence_applied
	)
	_debug_log("threaded finalize applied.")


func _is_generation_thread_active() -> bool:
	# A finished worker still owns a result until the main thread joins/applies it.
	# Treat that pending result as active so a new job cannot overwrite its snapshot.
	return _generation_thread != null


func _join_generation_thread() -> void:
	if _generation_thread == null:
		return
	_generation_thread.wait_to_finish()
	_generation_thread = null
	_clear_thread_cancel_token()


func _request_thread_regenerate_cancel() -> void:
	_thread_regenerate_requested = true
	_cancel_thread_job()


func _create_thread_cancel_token() -> Dictionary:
	var token := {"cancelled": false}
	_thread_cancel_mutex.lock()
	_thread_cancel_token = token
	_thread_cancel_mutex.unlock()
	return token


func _cancel_thread_job() -> void:
	_thread_cancel_mutex.lock()
	if not _thread_cancel_token.is_empty():
		_thread_cancel_token["cancelled"] = true
	_thread_cancel_mutex.unlock()


func _clear_thread_cancel_token() -> void:
	_thread_cancel_mutex.lock()
	_thread_cancel_token = {}
	_thread_cancel_mutex.unlock()


func _is_generation_cancelled(cancel_token: Dictionary) -> bool:
	if cancel_token.is_empty():
		return false
	_thread_cancel_mutex.lock()
	var cancelled := bool(cancel_token.get("cancelled", false))
	_thread_cancel_mutex.unlock()
	return cancelled


func _cluster_has_midpath_socket(sockets: Array[Dictionary], cluster: Array) -> bool:
	return _junction_builder._cluster_has_midpath_socket(sockets, cluster)


func _weld_cluster_with_midpath_pairs(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary],
	cluster: Array,
	path_rows: Array,
	stripped_side_indices: Dictionary,
	path_weld_snap: Array,
	path_weld_strip_enabled: Array,
	path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary
) -> void:
	_junction_builder._weld_cluster_with_midpath_pairs(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, sockets, cluster, path_rows, stripped_side_indices, path_weld_snap, path_weld_strip_enabled, path_weld_strip_length, paths_with_mid_intersections)


func _weld_two_socket_cluster(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	sockets: Array[Dictionary],
	cluster: Array,
	path_rows: Array,
	stripped_side_indices: Dictionary,
	path_weld_snap: Array,
	path_weld_strip_enabled: Array,
	path_weld_strip_length: Array,
	paths_with_mid_intersections: Dictionary
) -> void:
	_junction_builder._weld_two_socket_cluster(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, sockets, cluster, path_rows, stripped_side_indices, path_weld_snap, path_weld_strip_enabled, path_weld_strip_length, paths_with_mid_intersections)


func _collapse_row_side_edges_to_lane(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	row_edges_raw: Array,
	strip_side: int = STRIP_SIDE_BOTH
) -> void:
	_junction_builder._collapse_row_side_edges_to_lane(verts, normals, uvs, row_edges_raw, strip_side)


func _strip_endpoint_rows_near_socket(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	path_rows: Array,
	socket: Dictionary,
	strip_length: float,
	strip_snap_distance: float,
	marked: Dictionary,
	focus_position: Vector3 = Vector3.ZERO,
	focus_path_id: int = -1,
	use_focus_side: bool = false
) -> void:
	_junction_builder._strip_endpoint_rows_near_socket(verts, normals, uvs, path_rows, socket, strip_length, strip_snap_distance, marked, focus_position, focus_path_id, use_focus_side)


func _resolve_strip_side_for_row(
	verts: PackedVector3Array,
	row_edges_raw: Array,
	focus_position: Vector3
) -> int:
	return _junction_builder._resolve_strip_side_for_row(verts, row_edges_raw, focus_position)


func _pick_adjacent_strip_row(rows_raw: Array, row_idx: int, focus_position: Vector3) -> int:
	return _junction_builder._pick_adjacent_strip_row(rows_raw, row_idx, focus_position)


func _mark_row_side_vertices_for_strip(
	marked: Dictionary,
	row_edges_raw: Array,
	strip_side: int = STRIP_SIDE_BOTH
) -> void:
	_junction_builder._mark_row_side_vertices_for_strip(marked, row_edges_raw, strip_side)


func _find_strip_focus_for_socket(sockets: Array[Dictionary], cluster: Array, socket_idx: int) -> Dictionary:
	return _junction_builder._find_strip_focus_for_socket(sockets, cluster, socket_idx)


func _move_blocked_triangles_to_lane(
	indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	blocked: Dictionary
) -> PackedInt32Array:
	return _junction_builder._move_blocked_triangles_to_lane(indices, lane_indices, blocked)


func _apply_row_edge_strip_transform(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	row_edges_raw: Array,
	end_a_idx: int,
	end_b_idx: int,
	end_a_pos: Vector3,
	end_b_pos: Vector3,
	uv_a_idx: int = -1,
	uv_b_idx: int = -1
) -> void:
	_junction_builder._apply_row_edge_strip_transform(verts, normals, uvs, row_edges_raw, end_a_idx, end_b_idx, end_a_pos, end_b_pos, uv_a_idx, uv_b_idx)


func _append_quad_indices(indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	if invert_faces:
		indices.push_back(a)
		indices.push_back(b)
		indices.push_back(c)
		indices.push_back(c)
		indices.push_back(b)
		indices.push_back(d)
	else:
		indices.push_back(a)
		indices.push_back(c)
		indices.push_back(b)
		indices.push_back(c)
		indices.push_back(d)
		indices.push_back(b)


func _terrain_desired_normal() -> Vector3:
	return Vector3.DOWN if invert_faces else Vector3.UP


func _append_terrain_triangle_indices(
	terrain_indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int
) -> void:
	_append_oriented_triangle(
		terrain_indices,
		verts,
		a,
		b,
		c,
		_terrain_desired_normal()
	)


func _append_terrain_quad_indices(
	terrain_indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	d: int
) -> void:
	_append_oriented_quad(
		terrain_indices,
		verts,
		a,
		b,
		c,
		d,
		_terrain_desired_normal()
	)


func _reorient_indices_to_desired_normal(
	indices: PackedInt32Array,
	verts: PackedVector3Array,
	desired_normal: Vector3
) -> int:
	if indices.size() < 3:
		return 0
	var tri_count := indices.size() - (indices.size() % 3)
	var flipped := 0
	for i in range(0, tri_count, 3):
		var ia := int(indices[i])
		var ib := int(indices[i + 1])
		var ic := int(indices[i + 2])
		if ia < 0 or ib < 0 or ic < 0:
			continue
		if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
			continue
		var tri_n := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		if tri_n.length_squared() <= 0.000000000001:
			continue
		if tri_n.dot(desired_normal) >= 0.0:
			continue
		indices[i + 1] = ic
		indices[i + 2] = ib
		flipped += 1
	return flipped


func _append_lane_fallback_from_path_rows(lane_indices: PackedInt32Array, path_rows: Array) -> void:
	for rows_raw in path_rows:
		var rows: Array[Dictionary] = rows_raw
		if rows.size() < 2:
			continue
		for i in range(rows.size() - 1):
			var row0: Dictionary = rows[i]
			var row1: Dictionary = rows[i + 1]
			var e0: Array = row0.get("row_edges", [])
			var e1: Array = row1.get("row_edges", [])
			if e0.size() < 4 or e1.size() < 4:
				continue
			_append_quad_indices(
				lane_indices,
				int(e0[2]),
				int(e0[3]),
				int(e1[2]),
				int(e1[3])
			)


func _append_triangle_to_outer_surface(
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	a: int,
	b: int,
	c: int
) -> void:
	if not sidewalk_indices.is_empty():
		sidewalk_indices.push_back(a)
		sidewalk_indices.push_back(b)
		sidewalk_indices.push_back(c)
		return
	if not shoulder_indices.is_empty():
		shoulder_indices.push_back(a)
		shoulder_indices.push_back(b)
		shoulder_indices.push_back(c)
		return
	lane_indices.push_back(a)
	lane_indices.push_back(b)
	lane_indices.push_back(c)


func _remap_index_in_all_surfaces(
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	from_idx: int,
	to_idx: int
) -> void:
	_remap_index_in_surface(lane_indices, from_idx, to_idx)
	_remap_index_in_surface(shoulder_indices, from_idx, to_idx)
	_remap_index_in_surface(sidewalk_indices, from_idx, to_idx)


func _remap_index_in_surface(indices: PackedInt32Array, from_idx: int, to_idx: int) -> void:
	for i in range(indices.size()):
		if indices[i] == from_idx:
			indices[i] = to_idx


func _append_terrain_with_mode(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	_terrain_builder._append_terrain_with_mode(verts, normals, uvs, terrain_indices, path_rows, lane_indices, shoulder_indices, sidewalk_indices, blocked_side_vertices, cancel_token)


func _path_rows_with_emergency_terrain_widths(path_rows: Array, width: float) -> Array:
	return _terrain_builder._path_rows_with_emergency_terrain_widths(path_rows, width)


func _append_terrain_from_rect_fill(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array,
	cancel_token: Dictionary = {}
) -> void:
	_terrain_builder._append_terrain_from_rect_fill(verts, normals, uvs, terrain_indices, lane_indices, shoulder_indices, sidewalk_indices, path_rows, cancel_token)


func _append_terrain_from_boolean_fill(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array,
	cancel_token: Dictionary = {}
) -> void:
	_terrain_builder._append_terrain_from_boolean_fill(verts, normals, uvs, terrain_indices, lane_indices, shoulder_indices, sidewalk_indices, path_rows, cancel_token)


func _extract_road_boundary_loops_xz(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array
) -> Dictionary:
	return _terrain_builder._extract_road_boundary_loops_xz(verts, lane_indices, shoulder_indices, sidewalk_indices)


func _build_path_row_boundary_polygons_xz(verts: PackedVector3Array, path_rows: Array) -> Array:
	return _terrain_builder._build_path_row_boundary_polygons_xz(verts, path_rows)


func _build_path_row_boundary_polygons_xz_mode(
	verts: PackedVector3Array,
	path_rows: Array,
	lane_only: bool
) -> Array:
	return _terrain_builder._build_path_row_boundary_polygons_xz_mode(verts, path_rows, lane_only)


func _count_boundary_edges_from_surface(indices: PackedInt32Array, edge_counts: Dictionary) -> void:
	_terrain_builder._count_boundary_edges_from_surface(indices, edge_counts)


func _register_boundary_edge(a: int, b: int, edge_counts: Dictionary) -> void:
	_terrain_builder._register_boundary_edge(a, b, edge_counts)


func _append_boundary_neighbor(adjacency: Dictionary, from_idx: int, to_idx: int) -> void:
	_terrain_builder._append_boundary_neighbor(adjacency, from_idx, to_idx)


func _edge_key_from_indices(a: int, b: int) -> String:
	return _terrain_builder._edge_key_from_indices(a, b)


func _edge_key_to_indices(key: String) -> Vector2i:
	return _terrain_builder._edge_key_to_indices(key)


func _compact_polygon2d_xz(poly: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	return _terrain_builder._compact_polygon2d_xz(poly, epsilon)


func _resample_polygon_edges_for_boolean_fill(poly: PackedVector2Array, max_edge_len: float) -> PackedVector2Array:
	return _terrain_builder._resample_polygon_edges_for_boolean_fill(poly, max_edge_len)


func _clip_fill_parts_by_polygon(
	fill_parts: Array,
	clip_poly: PackedVector2Array,
	cancel_token: Dictionary = {}
) -> Array:
	return _terrain_builder._clip_fill_parts_by_polygon(fill_parts, clip_poly, cancel_token)


func _classify_fill_part_against_clip_polygon(
	part: PackedVector2Array,
	clip: PackedVector2Array,
	clip_box: Dictionary,
	clip_edge_lookup: Dictionary = {}
) -> int:
	return _terrain_builder._classify_fill_part_against_clip_polygon(part, clip, clip_box, clip_edge_lookup)


func _build_outer_rect_fill_parts_from_boundary_points(boundary_points: Array) -> Array:
	return _terrain_builder._build_outer_rect_fill_parts_from_boundary_points(boundary_points)


func _append_terrain_influence_boundary_points(boundary_points: Array) -> void:
	_terrain_builder._append_terrain_influence_boundary_points(boundary_points)


func _build_over_road_snap_context(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array
) -> Dictionary:
	return _terrain_builder._build_over_road_snap_context(verts, lane_indices, shoulder_indices, sidewalk_indices)


func _build_loop_boundary_segments_xz(loops: Array) -> Array:
	return _terrain_builder._build_loop_boundary_segments_xz(loops)


func _build_segment_spatial_hash_2d(segments: Array, cell_size: float, max_dist: float) -> Dictionary:
	return _terrain_builder._build_segment_spatial_hash_2d(segments, cell_size, max_dist)


func _sample_nearest_segment_height_2d(
	point: Vector2,
	segments: Array,
	grid: Dictionary,
	cell_size: float,
	max_dist: float
) -> Dictionary:
	return _terrain_builder._sample_nearest_segment_height_2d(point, segments, grid, cell_size, max_dist)


func _collect_terrain_influence_over_road_loops() -> Array:
	return _terrain_builder._collect_terrain_influence_over_road_loops()


func _collect_terrain_influence_over_road_snap_zones() -> Array:
	return _terrain_builder._collect_terrain_influence_over_road_snap_zones()


func _build_effective_road_clip_parts(road_parts: Array) -> Array:
	return _terrain_builder._build_effective_road_clip_parts(road_parts)


func _collect_terrain_influence_seed_boxes() -> Array:
	return _terrain_builder._collect_terrain_influence_seed_boxes()


func _build_outer_rect_fill_parts_from_road_parts(
	road_parts: Array,
	boundary_points: Array,
	cancel_token: Dictionary = {}
) -> Array:
	return _terrain_builder._build_outer_rect_fill_parts_from_road_parts(road_parts, boundary_points, cancel_token)


func _build_fill_parts_cluster_rectangles(road_parts: Array, boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_cluster_rectangles(road_parts, boundary_points)


func _build_fill_parts_convex_hull(road_parts: Array, boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_convex_hull(road_parts, boundary_points)


func _build_fill_parts_grid(boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_grid(boundary_points)


func _build_fill_parts_radial(boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_radial(boundary_points)


func _build_fill_parts_hex_grid(boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_hex_grid(boundary_points)


func _build_fill_parts_diamond_grid(boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_diamond_grid(boundary_points)


func _build_fill_parts_error_quadtree(
	road_parts: Array,
	boundary_points: Array,
	cancel_token: Dictionary = {}
) -> Array:
	return _terrain_builder._build_fill_parts_error_quadtree(road_parts, boundary_points, cancel_token)


func _quadtree_cell_has_height_error(
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	error_threshold: float,
	height_sample_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> bool:
	return _terrain_builder._quadtree_cell_has_height_error(min_x, max_x, min_z, max_z, boundary_height_map, boundary_points, base_y, error_threshold, height_sample_cache, boundary_height_lookup)


func _sample_quadtree_error_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	height_sample_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> float:
	return _terrain_builder._sample_quadtree_error_height(point, boundary_height_map, boundary_points, base_y, height_sample_cache, boundary_height_lookup)


func _quadtree_cell_should_split(
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float,
	road_loops: Array,
	road_boxes: Array
) -> bool:
	return _terrain_builder._quadtree_cell_should_split(min_x, max_x, min_z, max_z, road_loops, road_boxes)


func _polygon_has_point_inside_rect_xz(
	poly: PackedVector2Array,
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float
) -> bool:
	return _terrain_builder._polygon_has_point_inside_rect_xz(poly, min_x, max_x, min_z, max_z)


func _polygon_edges_intersect_rect_xz(
	poly: PackedVector2Array,
	c0: Vector2,
	c1: Vector2,
	c2: Vector2,
	c3: Vector2
) -> bool:
	return _terrain_builder._polygon_edges_intersect_rect_xz(poly, c0, c1, c2, c3)


func _build_fill_parts_lane_follow(_road_parts: Array, boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_lane_follow(_road_parts, boundary_points)


func _build_fill_parts_lod_rings(road_parts: Array, boundary_points: Array) -> Array:
	return _terrain_builder._build_fill_parts_lod_rings(road_parts, boundary_points)


func _build_fill_parts_adaptive_delaunay(
	road_parts: Array,
	boundary_points: Array,
	cancel_token: Dictionary = {}
) -> Array:
	return _terrain_builder._build_fill_parts_adaptive_delaunay(road_parts, boundary_points, cancel_token)


func _add_unique_fill_point(
	point: Vector2,
	points: PackedVector2Array,
	point_keys: Dictionary,
	quant_step: float
) -> void:
	_terrain_builder._add_unique_fill_point(point, points, point_keys, quant_step)


func _polygon_bbox_xz(poly: PackedVector2Array) -> Dictionary:
	return _terrain_builder._polygon_bbox_xz(poly)


func _bbox_overlaps_or_touches(a: Dictionary, b: Dictionary, gap: float) -> bool:
	return _terrain_builder._bbox_overlaps_or_touches(a, b, gap)


func _union_find_find(parent: Array, i: int) -> int:
	return _terrain_builder._union_find_find(parent, i)


func _union_find_union(parent: Array, a: int, b: int) -> void:
	_terrain_builder._union_find_union(parent, a, b)


func _filter_parts_outside_clip(
	parts: Array,
	clip_a: PackedVector2Array,
	clip_b: PackedVector2Array
) -> Array:
	return _terrain_builder._filter_parts_outside_clip(parts, clip_a, clip_b)


func _polygon_probe_point(poly: PackedVector2Array) -> Vector2:
	return _terrain_builder._polygon_probe_point(poly)


func _polygon_parts_total_area_abs_xz(parts: Array) -> float:
	return _terrain_builder._polygon_parts_total_area_abs_xz(parts)


func _polygon_area_abs_xz(poly: PackedVector2Array) -> float:
	return _terrain_builder._polygon_area_abs_xz(poly)


func _resolve_rect_fill_interior_point_step(base_edge_len: float) -> float:
	return _terrain_builder._resolve_rect_fill_interior_point_step(base_edge_len)


func _triangulate_fill_polygon_for_rect_mode(
	poly_raw: PackedVector2Array,
	base_edge_len: float,
	cancel_token: Dictionary = {}
) -> Array:
	return _terrain_builder._triangulate_fill_polygon_for_rect_mode(poly_raw, base_edge_len, cancel_token)


func _triangulate_fill_polygon_points(poly: PackedVector2Array) -> Array:
	return _terrain_builder._triangulate_fill_polygon_points(poly)


func _pick_largest_polygon_part_xz(parts: Array) -> PackedVector2Array:
	return _terrain_builder._pick_largest_polygon_part_xz(parts)


func _sample_boolean_fill_vertex_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	default_y: float,
	boundary_height_lookup: Dictionary = {}
) -> float:
	return _terrain_builder._sample_boolean_fill_vertex_height(point, boundary_height_map, boundary_points, default_y, boundary_height_lookup)


func _resolve_effective_fill_height_match_distance() -> float:
	return _terrain_builder._resolve_effective_fill_height_match_distance()


func _build_fill_heightmap_image() -> Image:
	return _terrain_builder._build_fill_heightmap_image()


func _build_boundary_height_lookup(boundary_points: Array) -> Dictionary:
	return _terrain_builder._build_boundary_height_lookup(boundary_points)


func _collect_boundary_point_ids_in_radius(
	point: Vector2,
	boundary_height_lookup: Dictionary,
	radius: float
) -> Array:
	return _terrain_builder._collect_boundary_point_ids_in_radius(point, boundary_height_lookup, radius)


func _find_nearest_boundary_points(
	point: Vector2,
	boundary_points: Array,
	boundary_height_lookup: Dictionary,
	needed: int
) -> Dictionary:
	return _terrain_builder._find_nearest_boundary_points(point, boundary_points, boundary_height_lookup, needed)


func _find_nearest_boundary_points_full_scan(point: Vector2, boundary_points: Array) -> Dictionary:
	return _terrain_builder._find_nearest_boundary_points_full_scan(point, boundary_points)


func _sample_fill_vertex_height(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	heightmap_image: Image,
	boundary_height_lookup: Dictionary = {}
) -> float:
	return _terrain_builder._sample_fill_vertex_height(point, boundary_height_map, boundary_points, base_y, heightmap_image, boundary_height_lookup)


func _min_distance_to_road_loops_xz(
	point: Vector2,
	road_loops: Array,
	road_distance_lookup: Dictionary = {},
	max_search_dist: float = INF
) -> float:
	return _terrain_builder._min_distance_to_road_loops_xz(point, road_loops, road_distance_lookup, max_search_dist)


func _build_road_loop_distance_lookup(road_loops: Array, cell_size_hint: float) -> Dictionary:
	return _terrain_builder._build_road_loop_distance_lookup(road_loops, cell_size_hint)


func _build_polygon_edge_lookup(poly: PackedVector2Array) -> Dictionary:
	return _terrain_builder._build_polygon_edge_lookup(poly)


func _build_2d_segment_distance_lookup(segments: Array, cell_size_hint: float) -> Dictionary:
	return _terrain_builder._build_2d_segment_distance_lookup(segments, cell_size_hint)


func _min_distance_to_segment_lookup(point: Vector2, lookup: Dictionary, max_search_dist: float) -> float:
	return _terrain_builder._min_distance_to_segment_lookup(point, lookup, max_search_dist)


func _collect_segment_lookup_ids_for_box(lookup: Dictionary, box: Dictionary) -> Array:
	return _terrain_builder._collect_segment_lookup_ids_for_box(lookup, box)


func _segment_lookup_max_radius_cells(grid: Dictionary) -> int:
	return _terrain_builder._segment_lookup_max_radius_cells(grid)


func _collect_segment_lookup_source_ids(point: Vector2, lookup: Dictionary, radius: float) -> Array:
	return _terrain_builder._collect_segment_lookup_source_ids(point, lookup, radius)


func _fill_edge_height_cache_key(a: Vector2, b: Vector2) -> String:
	return _terrain_builder._fill_edge_height_cache_key(a, b)


func _fill_vertex_cache_key(point: Vector2) -> Vector2i:
	return _terrain_builder._fill_vertex_cache_key(point)


func _sample_fill_vertex_height_cached(
	point: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	heightmap_image: Image,
	fill_vertex_height_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> float:
	return _terrain_builder._sample_fill_vertex_height_cached(point, boundary_height_map, boundary_points, base_y, heightmap_image, fill_vertex_height_cache, boundary_height_lookup)


func _get_or_create_fill_vertex(
	point: Vector2,
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	fill_vertex_index_cache: Dictionary
) -> int:
	return _terrain_builder._get_or_create_fill_vertex(point, y, verts, normals, uvs, fill_vertex_index_cache)


func _get_fill_edge_midpoint_height(
	a: Vector2,
	b: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	heightmap_image: Image,
	edge_midpoint_height_cache: Dictionary,
	boundary_height_lookup: Dictionary = {}
) -> float:
	return _terrain_builder._get_fill_edge_midpoint_height(a, b, boundary_height_map, boundary_points, base_y, heightmap_image, edge_midpoint_height_cache, boundary_height_lookup)


func _fill_triangle_has_split_edge(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	edge_midpoint_height_cache: Dictionary
) -> bool:
	return _terrain_builder._fill_triangle_has_split_edge(a, b, c, edge_midpoint_height_cache)


func _fill_topology_uses_adaptive_triangulation() -> bool:
	return _terrain_builder._fill_topology_uses_adaptive_triangulation()


func _get_fill_adaptive_max_depth() -> int:
	return _terrain_builder._get_fill_adaptive_max_depth()


func _precompute_fill_split_edges(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	road_loops: Array,
	heightmap_image: Image,
	base_edge_len: float,
	edge_midpoint_height_cache: Dictionary,
	depth: int,
	boundary_height_lookup: Dictionary = {}
) -> bool:
	return _terrain_builder._precompute_fill_split_edges(a, b, c, boundary_height_map, boundary_points, base_y, road_loops, heightmap_image, base_edge_len, edge_midpoint_height_cache, depth, boundary_height_lookup)


func _should_subdivide_fill_triangle(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	_road_loops: Array,
	_heightmap_image: Image,
	base_edge_len: float,
	depth: int
) -> bool:
	return _terrain_builder._should_subdivide_fill_triangle(a, b, c, _road_loops, _heightmap_image, base_edge_len, depth)


func _append_fill_triangle_adaptive(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	boundary_height_map: Dictionary,
	boundary_points: Array,
	base_y: float,
	road_loops: Array,
	heightmap_image: Image,
	y_a: float,
	y_b: float,
	y_c: float,
	base_edge_len: float,
	tri_limit: int,
	tri_stats: Dictionary,
	edge_midpoint_height_cache: Dictionary,
	fill_vertex_index_cache: Dictionary,
	depth: int,
	boundary_height_lookup: Dictionary = {}
) -> void:
	_terrain_builder._append_fill_triangle_adaptive(a, b, c, verts, normals, uvs, terrain_indices, boundary_height_map, boundary_points, base_y, road_loops, heightmap_image, y_a, y_b, y_c, base_edge_len, tri_limit, tri_stats, edge_midpoint_height_cache, fill_vertex_index_cache, depth, boundary_height_lookup)


func _append_terrain_from_path_rows(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	path_rows: Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	blocked_side_vertices: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	_terrain_builder._append_terrain_from_path_rows(verts, normals, uvs, terrain_indices, path_rows, lane_indices, shoulder_indices, sidewalk_indices, blocked_side_vertices, cancel_token)


func _stabilize_terrain_side_chain(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	base_ids: PackedInt32Array,
	outer_ids: PackedInt32Array,
	outer_points: Array[Vector3],
	applied_widths: PackedFloat32Array
) -> void:
	_terrain_builder._stabilize_terrain_side_chain(verts, normals, uvs, base_ids, outer_ids, outer_points, applied_widths)


func _resolve_terrain_subdivisions_for_rows(rows: Array) -> int:
	return _terrain_builder._resolve_terrain_subdivisions_for_rows(rows)


func _append_terrain_side_skirts(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	ring_ids: Array,
	subdivisions: int,
	depth: float
) -> void:
	_terrain_builder._append_terrain_side_skirts(verts, normals, uvs, terrain_indices, ring_ids, subdivisions, depth)


func _soften_outer_area_for_skirt(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	ring_ids: Array,
	subdivisions: int
) -> void:
	_terrain_builder._soften_outer_area_for_skirt(verts, normals, ring_ids, subdivisions)


func _append_terrain_skirt_from_index_chain(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	chain: Array,
	depth: float
) -> void:
	_terrain_builder._append_terrain_skirt_from_index_chain(verts, normals, uvs, terrain_indices, chain, depth)


func _compute_skirt_outward_dir(
	verts: PackedVector3Array,
	chain: Array,
	idx: int,
	center: Vector3
) -> Vector3:
	return _terrain_builder._compute_skirt_outward_dir(verts, chain, idx, center)


func _build_terrain_side_rings(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	base_ids: PackedInt32Array,
	outer_ids: PackedInt32Array,
	row_count: int,
	subdivisions: int,
	terrain_noise: FastNoiseLite,
	cancel_token: Dictionary = {}
) -> Array:
	return _terrain_builder._build_terrain_side_rings(verts, normals, uvs, base_ids, outer_ids, row_count, subdivisions, terrain_noise, cancel_token)


func _terrain_noise_offset_y(
	point: Vector3,
	ring_t: float,
	terrain_noise: FastNoiseLite
) -> float:
	return _terrain_builder._terrain_noise_offset_y(point, ring_t, terrain_noise)


func _build_terrain_noise() -> FastNoiseLite:
	return _terrain_builder._build_terrain_noise()


func _build_road_tri_xz_cache(
	verts: PackedVector3Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	path_rows: Array
) -> Array:
	return _terrain_builder._build_road_tri_xz_cache(verts, lane_indices, shoulder_indices, sidewalk_indices, path_rows)


func _append_surface_tri_xz_cache(out: Array, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	_terrain_builder._append_surface_tri_xz_cache(out, verts, indices)


func _append_path_row_road_envelope_tri_xz_cache(
	out: Array,
	verts: PackedVector3Array,
	path_rows: Array
) -> void:
	_terrain_builder._append_path_row_road_envelope_tri_xz_cache(out, verts, path_rows)


func _append_tri_to_xz_cache(out: Array, a3: Vector3, b3: Vector3, c3: Vector3) -> void:
	_terrain_builder._append_tri_to_xz_cache(out, a3, b3, c3)


func _point_over_any_road_triangle_xz(point: Vector2, road_tris: Array, margin: float) -> bool:
	return _terrain_builder._point_over_any_road_triangle_xz(point, road_tris, margin)


func _segment_over_any_road_triangle_xz(a: Vector2, b: Vector2, road_tris: Array, margin: float = 0.0) -> bool:
	return _terrain_builder._segment_over_any_road_triangle_xz(a, b, road_tris, margin)


func _segment_distance_2d(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	return _terrain_builder._segment_distance_2d(a0, a1, b0, b1)


func _distance_point_to_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	return _terrain_builder._distance_point_to_segment_2d(point, a, b)


func _segments_intersect_2d_strict(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	return _terrain_builder._segments_intersect_2d_strict(a0, a1, b0, b1)


func _limit_terrain_growth_width_for_segment(
	verts: PackedVector3Array,
	base_point: Vector3,
	out_dir: Vector3,
	requested_width: float,
	prev_idx: int,
	curr_idx: int,
	outer_points: Array[Vector3],
	outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	road_tris: Array
) -> float:
	return _terrain_builder._limit_terrain_growth_width_for_segment(verts, base_point, out_dir, requested_width, prev_idx, curr_idx, outer_points, outer_ids, base_ids, opposite_ids, road_tris)


func _is_terrain_growth_segment_valid(
	verts: PackedVector3Array,
	seg_a: Vector3,
	seg_b: Vector3,
	prev_idx: int,
	curr_idx: int,
	outer_points: Array[Vector3],
	outer_ids: PackedInt32Array,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	road_tris: Array
) -> bool:
	return _terrain_builder._is_terrain_growth_segment_valid(verts, seg_a, seg_b, prev_idx, curr_idx, outer_points, outer_ids, base_ids, opposite_ids, road_tris)


func _terrain_quad_over_any_road_triangle_xz(
	base_prev: Vector3,
	base_curr: Vector3,
	outer_prev: Vector3,
	outer_curr: Vector3,
	road_tris: Array,
	margin: float
) -> bool:
	return _terrain_builder._terrain_quad_over_any_road_triangle_xz(base_prev, base_curr, outer_prev, outer_curr, road_tris, margin)


func _polygon_intersects_triangle_xz(poly: PackedVector2Array, tri: PackedVector2Array) -> bool:
	return _terrain_builder._polygon_intersects_triangle_xz(poly, tri)


func _is_point_over_road_cross_xz(
	verts: PackedVector3Array,
	point: Vector3,
	base_ids: PackedInt32Array,
	opposite_ids: PackedInt32Array,
	row_idx: int
) -> bool:
	return _terrain_builder._is_point_over_road_cross_xz(verts, point, base_ids, opposite_ids, row_idx)


func _segments_intersect_xz(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> bool:
	return _terrain_builder._segments_intersect_xz(a0, a1, b0, b1)


func _append_outer_walls_from_path_rows(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	wall_indices: PackedInt32Array,
	path_rows: Array
) -> void:
	_mesh_builder._append_outer_walls_from_path_rows(verts, normals, uvs, wall_indices, path_rows)


func _append_outer_wall_segment(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	wall_indices: PackedInt32Array,
	top_idx_0: int,
	top_idx_1: int,
	inner_idx_0: int,
	inner_idx_1: int,
	wall_height: float
) -> void:
	_mesh_builder._append_outer_wall_segment(verts, normals, uvs, wall_indices, top_idx_0, top_idx_1, inner_idx_0, inner_idx_1, wall_height)


func _append_oriented_quad(
	indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	d: int,
	desired_normal: Vector3
) -> void:
	_mesh_builder._append_oriented_quad(indices, verts, a, b, c, d, desired_normal)


func _append_oriented_triangle(
	indices: PackedInt32Array,
	verts: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	desired_normal: Vector3
) -> void:
	_mesh_builder._append_oriented_triangle(indices, verts, a, b, c, desired_normal)


func _build_mesh(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	lane_indices: PackedInt32Array,
	shoulder_indices: PackedInt32Array,
	sidewalk_indices: PackedInt32Array,
	terrain_indices: PackedInt32Array,
	wall_indices: PackedInt32Array
) -> ArrayMesh:
	return _mesh_builder._build_mesh(verts, normals, uvs, lane_indices, shoulder_indices, sidewalk_indices, terrain_indices, wall_indices)


func _add_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	mat: Material,
	force_upward_normals: bool = false
) -> void:
	_mesh_builder._add_surface(mesh, verts, normals, uvs, indices, mat, force_upward_normals)


func _compute_surface_normals_from_indices(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	fallback_normals: PackedVector3Array
) -> PackedVector3Array:
	return _mesh_builder._compute_surface_normals_from_indices(verts, indices, fallback_normals)


func _force_normals_upward(surface_normals: PackedVector3Array) -> void:
	_mesh_builder._force_normals_upward(surface_normals)


func _compute_row_out_dir(row_centers: Array[Vector3], idx: int) -> Vector3:
	if row_centers.size() < 2:
		return Vector3.FORWARD
	if idx <= 0:
		return (row_centers[1] - row_centers[0]).normalized()
	if idx >= row_centers.size() - 1:
		return (row_centers[row_centers.size() - 2] - row_centers[row_centers.size() - 1]).normalized()
	return (row_centers[idx + 1] - row_centers[idx - 1]).normalized()


func _add_socket_unique(sockets: Array[Dictionary], keys: Dictionary, row: Dictionary, is_endpoint: bool) -> void:
	_junction_builder._add_socket_unique(sockets, keys, row, is_endpoint)


func _augment_with_midpath_sockets(
	sockets: Array[Dictionary],
	keys: Dictionary,
	path_rows: Array,
	endpoint_count: int,
	path_weld_allow_midpath: Array,
	path_weld_snap: Array
) -> void:
	_junction_builder._augment_with_midpath_sockets(sockets, keys, path_rows, endpoint_count, path_weld_allow_midpath, path_weld_snap)


func _augment_with_midpath_pair_sockets(
	sockets: Array[Dictionary],
	keys: Dictionary,
	path_rows: Array,
	path_weld_allow_midpath: Array,
	path_weld_snap: Array
) -> void:
	_junction_builder._augment_with_midpath_pair_sockets(sockets, keys, path_rows, path_weld_allow_midpath, path_weld_snap)


func _find_nearest_inner_row(rows: Array[Dictionary], point: Vector3, max_distance: float) -> int:
	return _junction_builder._find_nearest_inner_row(rows, point, max_distance)


func _find_nearest_inner_row_pair(
	rows_a: Array[Dictionary],
	rows_b: Array[Dictionary],
	max_distance: float
) -> PackedInt32Array:
	return _junction_builder._find_nearest_inner_row_pair(rows_a, rows_b, max_distance)


func _build_open_distances(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := 0.0
	while d < length:
		out.push_back(d)
		d += sample_step
	out.push_back(length)
	if out.size() < 2:
		out = PackedFloat32Array([0.0, length])
	return out


func _build_open_distances_with_step(length: float, local_step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := maxf(local_step, 0.01)
	var d := 0.0
	while d < length:
		out.push_back(d)
		d += step
	out.push_back(length)
	if out.size() < 2:
		out = PackedFloat32Array([0.0, length])
	return out


func _compute_adaptive_local_step(path_adaptive_step_scale: float, generation_step := -1.0) -> float:
	var base_step: float = maxf(0.02, generation_step if generation_step > 0.0 else sample_step)
	var scale: float = maxf(0.1, path_adaptive_step_scale)
	return maxf(0.02, base_step * scale)


func _compute_adaptive_local_radius(
	local_step: float,
	path_adaptive_radius_scale: float
) -> float:
	# Keep the refinement/coarsening window tight around the anchor:
	# enough for one adjacent pair ("2 vertices"), not a wide area.
	var radius_scale: float = maxf(0.1, path_adaptive_radius_scale)
	return maxf(0.01, local_step * radius_scale)


func _apply_adaptive_anchor_offset(
	anchors: PackedFloat32Array,
	length: float,
	path_adaptive_advanced: bool,
	path_adaptive_offset: float
) -> PackedFloat32Array:
	if not path_adaptive_advanced:
		return anchors
	if is_zero_approx(path_adaptive_offset):
		return anchors

	var out := PackedFloat32Array()
	for a in anchors:
		out.push_back(clampf(a + path_adaptive_offset, 0.0, length))
	return out


func _build_open_distances_with_anchors(
	length: float,
	anchors: PackedFloat32Array,
	local_step: float,
	local_radius: float,
	base_step := -1.0
) -> PackedFloat32Array:
	var resolved_base_step := maxf(0.01, base_step if base_step > 0.0 else sample_step)
	if anchors.is_empty() or local_radius <= 0.0:
		return _build_open_distances_with_step(length, resolved_base_step)

	var split_points: Array[float] = [0.0, length]
	for anchor in anchors:
		var a0: float = clamp(anchor - local_radius, 0.0, length)
		var a1: float = clamp(anchor + local_radius, 0.0, length)
		split_points.push_back(a0)
		split_points.push_back(a1)

	split_points.sort()
	var unique_points: Array[float] = []
	for p in split_points:
		if unique_points.is_empty() or absf(unique_points[unique_points.size() - 1] - p) > 0.001:
			unique_points.push_back(p)

	var out := PackedFloat32Array()
	for i in range(unique_points.size() - 1):
		var seg_start: float = unique_points[i]
		var seg_end: float = unique_points[i + 1]
		if seg_end - seg_start <= 0.0001:
			continue

		var seg_mid := (seg_start + seg_end) * 0.5
		var use_local := false
		for anchor in anchors:
			if absf(seg_mid - anchor) <= local_radius:
				use_local = true
				break

		var step := resolved_base_step
		if use_local:
			step = local_step
		step = max(step, 0.01)

		if out.is_empty() or absf(out[out.size() - 1] - seg_start) > 0.001:
			out.push_back(seg_start)

		var d := seg_start + step
		while d < seg_end - 0.001:
			out.push_back(d)
			d += step

	if out.is_empty() or absf(out[out.size() - 1] - length) > 0.001:
		out.push_back(length)

	if out.size() < 2:
		return _build_open_distances_with_step(length, resolved_base_step)
	return out


func _collect_path_endpoints(paths: Array[Path3D], inv_global: Transform3D) -> Array:
	var out: Array = []
	out.resize(paths.size())
	for path_idx in range(paths.size()):
		var points: Array[Vector3] = []
		var path := paths[path_idx]
		if path == null or _path_is_terrain_influence_only(path) or path.curve == null or path.curve.point_count < 2:
			out[path_idx] = points
			continue

		var curve := path.curve
		curve.bake_interval = max(sample_step, 0.01)
		var length := curve.get_baked_length()
		if length <= 0.0:
			out[path_idx] = points
			continue

		var path_to_mesh := inv_global * path.global_transform
		points.push_back(path_to_mesh * curve.sample_baked(0.0, true))
		points.push_back(path_to_mesh * curve.sample_baked(length, true))
		out[path_idx] = points

	return out


func _collect_adaptive_anchor_offsets(
	path_idx: int,
	curve: Curve3D,
	path_to_mesh: Transform3D,
	endpoint_positions_by_path: Array,
	max_snap_distance: float
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if curve == null or curve.point_count < 2:
		return out

	var mesh_to_path := path_to_mesh.affine_inverse()
	var max_snap_sq := max_snap_distance * max_snap_distance

	for other_idx in range(endpoint_positions_by_path.size()):
		if other_idx == path_idx:
			continue
		var points: Array = endpoint_positions_by_path[other_idx]
		for p in points:
			var endpoint_mesh: Vector3 = p
			var endpoint_path := mesh_to_path * endpoint_mesh
			var offset := 0.0
			if curve.has_method("get_closest_offset"):
				offset = curve.get_closest_offset(endpoint_path)
			else:
				offset = _approx_closest_offset(curve, endpoint_path, max(0.05, sample_step))
			var closest_mesh := path_to_mesh * curve.sample_baked(offset, true)
			var delta_xz := Vector2(closest_mesh.x - endpoint_mesh.x, closest_mesh.z - endpoint_mesh.z)
			if delta_xz.length_squared() <= max_snap_sq:
				out.push_back(offset)

	if out.is_empty():
		return out

	var sorted_offsets: Array[float] = []
	for off in out:
		sorted_offsets.push_back(off)
	sorted_offsets.sort()

	var unique := PackedFloat32Array()
	for off in sorted_offsets:
		if unique.is_empty() or absf(unique[unique.size() - 1] - off) > 0.001:
			unique.push_back(off)
	return unique


func _approx_closest_offset(curve: Curve3D, point: Vector3, step: float) -> float:
	var length := curve.get_baked_length()
	if length <= 0.0:
		return 0.0

	var d := 0.0
	var best_off := 0.0
	var best_dist := INF
	var s: float = max(step, 0.01)
	while d <= length:
		var p := curve.sample_baked(d, true)
		var dist := p.distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best_off = d
		d += s

	if best_off != length:
		var p_end := curve.sample_baked(length, true)
		var end_dist := p_end.distance_squared_to(point)
		if end_dist < best_dist:
			best_off = length

	return best_off


func _cluster_sockets(
	sockets: Array[Dictionary],
	min_paths: int,
	path_weld_snap: Array,
	snap_scale: float = 1.0
) -> Array:
	return _junction_builder._cluster_sockets(sockets, min_paths, path_weld_snap, snap_scale)


func _resolve_socket_pair_snap_distance(socket_a: Dictionary, socket_b: Dictionary, path_weld_snap: Array) -> float:
	return _junction_builder._resolve_socket_pair_snap_distance(socket_a, socket_b, path_weld_snap)


func _path_has_weld_overrides(path: Path3D) -> bool:
	if path == null:
		return false
	if path.has_method("has_intersection_overrides"):
		return bool(path.call("has_intersection_overrides"))
	if path.has_method("has_weld_overrides"):
		return bool(path.call("has_weld_overrides"))
	return false


func _resolve_path_weld_endpoint_snap_distance(path: Path3D) -> float:
	var value := endpoint_snap_distance
	if _path_has_weld_overrides(path) and path.has_method("get_weld_endpoint_snap_distance"):
		value = float(path.call("get_weld_endpoint_snap_distance"))
	return maxf(0.1, value)


func _resolve_path_weld_allow_endpoint_to_midpath(path: Path3D) -> bool:
	if _path_has_weld_overrides(path) and path.has_method("get_weld_allow_endpoint_to_midpath"):
		return bool(path.call("get_weld_allow_endpoint_to_midpath"))
	return allow_endpoint_to_midpath


func _resolve_path_weld_strip_shoulder_sidewalk(path: Path3D) -> bool:
	if _path_has_weld_overrides(path) and path.has_method("get_weld_strip_shoulder_sidewalk_at_intersections"):
		return bool(path.call("get_weld_strip_shoulder_sidewalk_at_intersections"))
	return strip_shoulder_sidewalk_at_intersections


func _resolve_path_weld_intersection_strip_length(path: Path3D) -> float:
	var value := intersection_strip_length
	if _path_has_weld_overrides(path) and path.has_method("get_weld_intersection_strip_length"):
		value = float(path.call("get_weld_intersection_strip_length"))
	return maxf(0.0, value)


func _path_has_adaptive_sampling_overrides(path: Path3D) -> bool:
	if path == null:
		return false
	if path.has_method("has_intersection_overrides"):
		return bool(path.call("has_intersection_overrides"))
	if path.has_method("has_adaptive_sampling_overrides"):
		return bool(path.call("has_adaptive_sampling_overrides"))
	return false


func _resolve_path_adaptive_sampling_enabled(path: Path3D) -> bool:
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_enabled"):
		return bool(path.call("get_adaptive_sampling_enabled"))
	return adaptive_sampling_enabled


func _resolve_path_adaptive_sampling_advanced(path: Path3D) -> bool:
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_advanced"):
		return bool(path.call("get_adaptive_sampling_advanced")) or adaptive_sampling_advanced
	return adaptive_sampling_advanced


func _resolve_path_adaptive_sampling_step_scale(path: Path3D) -> float:
	var value: float = adaptive_sampling_step_scale
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_step_scale"):
		value = float(path.call("get_adaptive_sampling_step_scale"))
	return maxf(0.1, value)


func _resolve_path_adaptive_sampling_radius_scale(path: Path3D) -> float:
	var value: float = adaptive_sampling_radius_scale
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_radius_scale"):
		value = float(path.call("get_adaptive_sampling_radius_scale"))
	return maxf(0.1, value)


func _resolve_path_adaptive_sampling_offset(path: Path3D) -> float:
	if _path_has_adaptive_sampling_overrides(path) and path.has_method("get_adaptive_sampling_offset"):
		return float(path.call("get_adaptive_sampling_offset"))
	return adaptive_sampling_offset


func _resolve_path_snap_for_id(path_id: int, path_weld_snap: Array) -> float:
	return _junction_builder._resolve_path_snap_for_id(path_id, path_weld_snap)


func _is_path_allow_midpath(path_id: int, path_weld_allow_midpath: Array) -> bool:
	return _junction_builder._is_path_allow_midpath(path_id, path_weld_allow_midpath)


func _is_path_strip_enabled(path_id: int, path_weld_strip_enabled: Array) -> bool:
	return _junction_builder._is_path_strip_enabled(path_id, path_weld_strip_enabled)


func _resolve_path_strip_length(path_id: int, _path_weld_snap: Array, path_weld_strip_length: Array) -> float:
	return _junction_builder._resolve_path_strip_length(path_id, _path_weld_snap, path_weld_strip_length)


func _resolve_path_width(path: Path3D, dist: float, length: float) -> float:
	var width := road_width
	if path != null and path.has_method("get_width_at_offset"):
		width = float(path.call("get_width_at_offset", dist))
	elif path != null and path.has_method("get_width_at_ratio"):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		width = float(path.call("get_width_at_ratio", ratio))
	return max(0.1, width)


func _resolve_path_lane_extents(path: Path3D, dist: float, length: float) -> Vector2:
	var width := _resolve_path_width(path, dist, length)
	var fallback := Vector2(width * 0.5, width * 0.5)
	if path == null:
		return fallback
	var raw_value: Variant
	if path.has_method("get_lane_extents_at_offset"):
		raw_value = path.call("get_lane_extents_at_offset", dist)
	elif path.has_method("get_lane_extents_at_ratio"):
		var ratio := clampf(dist / maxf(length, 0.0001), 0.0, 1.0)
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


## Returns the generated road's world-space frame at a spline distance.
## Consumers such as SplinePropArray3D use this to sit on banked shoulders/sidewalks.


func get_path_surface_frame(path: Path3D, distance: float) -> Dictionary:
	if path == null or path.curve == null or path.curve.point_count < 2:
		return {}
	var curve := path.curve
	var length := maxf(0.0, curve.get_baked_length())
	if length <= 0.001:
		return {}
	var dist := clampf(distance, 0.0, length)
	var path_to_mesh := global_transform.affine_inverse() * path.global_transform
	var center_mesh := path_to_mesh * curve.sample_baked(dist, true)
	var probe := 0.1
	var prev_dist := maxf(0.0, dist - probe)
	var next_dist := minf(length, dist + probe)
	if is_equal_approx(prev_dist, next_dist):
		if next_dist < length:
			next_dist = minf(length, next_dist + probe)
		elif prev_dist > 0.0:
			prev_dist = maxf(0.0, prev_dist - probe)
	var prev_mesh := path_to_mesh * curve.sample_baked(prev_dist, true)
	var next_mesh := path_to_mesh * curve.sample_baked(next_dist, true)
	var frame := _resolve_road_frame(curve, path_to_mesh, dist, length, center_mesh, prev_mesh, next_mesh, path)
	var right_mesh: Vector3 = frame.get("right", Vector3.RIGHT)
	var up_mesh: Vector3 = frame.get("up", Vector3.UP)
	center_mesh.y += y_offset
	return {
		"center": global_transform * center_mesh,
		"right": (global_transform.basis * right_mesh).normalized(),
		"up": (global_transform.basis * up_mesh).normalized(),
		# Road edge raises and y_offset are applied in this mesh-local vertical axis.
		"vertical": (global_transform.basis * Vector3.UP).normalized(),
	}


func _resolve_path_shoulder_left(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_shoulder_left_at_offset",
		"get_shoulder_left_at_ratio",
		shoulder_left_width
	)


func _resolve_path_shoulder_right(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_shoulder_right_at_offset",
		"get_shoulder_right_at_ratio",
		shoulder_right_width
	)


func _resolve_path_sidewalk_left(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_left_at_offset",
		"get_sidewalk_left_at_ratio",
		sidewalk_left_width
	)


func _resolve_path_sidewalk_right(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_right_at_offset",
		"get_sidewalk_right_at_ratio",
		sidewalk_right_width
	)


func _resolve_path_terrain_left(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_terrain_widths(path, dist, length).x


func _resolve_path_terrain_right(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_terrain_widths(path, dist, length).y


func _resolve_path_terrain_widths(path: Path3D, dist: float, length: float) -> Vector2:
	var fallback := Vector2(maxf(0.0, terrain_left_width), maxf(0.0, terrain_right_width))
	if path == null:
		return fallback
	if path.has_method("has_terrain_overrides"):
		if not bool(path.call("has_terrain_overrides")):
			return fallback

	if path.has_method("get_terrain_widths_at_offset"):
		return _coerce_terrain_width_pair(path.call("get_terrain_widths_at_offset", dist), fallback)

	if path.has_method("get_terrain_widths_at_ratio"):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		return _coerce_terrain_width_pair(path.call("get_terrain_widths_at_ratio", ratio), fallback)

	var left := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_terrain_left_at_offset",
		"get_terrain_left_at_ratio",
		fallback.x
	)
	var right := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_terrain_right_at_offset",
		"get_terrain_right_at_ratio",
		fallback.y
	)
	return Vector2(left, right)


func _coerce_terrain_width_pair(raw_value: Variant, fallback: Vector2) -> Vector2:
	var left := fallback.x
	var right := fallback.y
	if raw_value is Vector2:
		var pair: Vector2 = raw_value
		left = pair.x
		right = pair.y
	elif raw_value is Array:
		var array_values: Array = raw_value
		if array_values.size() >= 1:
			left = float(array_values[0])
		if array_values.size() >= 2:
			right = float(array_values[1])
	elif raw_value is PackedFloat32Array:
		var packed_values: PackedFloat32Array = raw_value
		if packed_values.size() >= 1:
			left = packed_values[0]
		if packed_values.size() >= 2:
			right = packed_values[1]
	elif raw_value is Dictionary:
		var dict_values: Dictionary = raw_value
		left = float(dict_values.get("left", dict_values.get("x", left)))
		right = float(dict_values.get("right", dict_values.get("y", right)))
	return Vector2(maxf(0.0, left), maxf(0.0, right))


func _resolve_path_sidewalk_height(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_height_at_offset",
		"get_sidewalk_height_at_ratio",
		sidewalk_height
	)


func _resolve_path_outer_wall_height(path: Path3D, dist: float, length: float) -> float:
	return _resolve_path_component_width(
		path,
		dist,
		length,
		"get_outer_wall_height_at_offset",
		"get_outer_wall_height_at_ratio",
		outer_wall_height
	)


func _path_is_terrain_influence_only(path: Path3D) -> bool:
	if path == null:
		return false
	if path.has_method("is_terrain_influence_path"):
		return bool(path.call("is_terrain_influence_path"))
	return false


func _build_terrain_influence_strip(
	path: Path3D,
	curve: Curve3D,
	path_to_mesh: Transform3D,
	distances: PackedFloat32Array
) -> Dictionary:
	return _terrain_influence_builder._build_terrain_influence_strip(path, curve, path_to_mesh, distances)


func _build_capsule_loop_xz(
	centers: PackedVector3Array,
	left_edge: PackedVector3Array,
	right_edge: PackedVector3Array,
	band_count: int
) -> PackedVector2Array:
	return _terrain_influence_builder._build_capsule_loop_xz(centers, left_edge, right_edge, band_count)


func _semicircle_profile_t(t: float, curve: float = 1.0) -> float:
	return _terrain_influence_builder._semicircle_profile_t(t, curve)


func _terrain_influence_cross_profile(
	dist_t: float,
	curve: float,
	graph_samples: PackedFloat32Array = PackedFloat32Array()
) -> float:
	return _terrain_influence_builder._terrain_influence_cross_profile(dist_t, curve, graph_samples)


func _smooth_open_edge_chain(points: PackedVector3Array, blend: float) -> PackedVector3Array:
	return _terrain_influence_builder._smooth_open_edge_chain(points, blend)


func _append_terrain_influence_fill_faces(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	strips: Array = [],
	cancel_token: Dictionary = {}
) -> void:
	_terrain_influence_builder._append_terrain_influence_fill_faces(verts, normals, uvs, terrain_indices, strips, cancel_token)


func _append_terrain_influence_loop_vertices(
	strip: Dictionary,
	loop: PackedVector2Array,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	force_flat_edge: bool = false,
	cancel_token: Dictionary = {}
) -> PackedInt32Array:
	return _terrain_influence_builder._append_terrain_influence_loop_vertices(strip, loop, verts, normals, uvs, force_flat_edge, cancel_token)


func _append_terrain_influence_loop_triangulation(
	loop: PackedVector2Array,
	local_to_global: PackedInt32Array,
	verts: PackedVector3Array,
	terrain_indices: PackedInt32Array,
	cancel_token: Dictionary = {}
) -> void:
	_terrain_influence_builder._append_terrain_influence_loop_triangulation(loop, local_to_global, verts, terrain_indices, cancel_token)


func _append_terrain_influence_loop_bridge(
	inner_map: PackedInt32Array,
	outer_map: PackedInt32Array,
	verts: PackedVector3Array,
	terrain_indices: PackedInt32Array,
	cancel_token: Dictionary = {}
) -> void:
	_terrain_influence_builder._append_terrain_influence_loop_bridge(inner_map, outer_map, verts, terrain_indices, cancel_token)


func _append_terrain_influence_loop_fill(
	strip: Dictionary,
	loop_raw: PackedVector2Array,
	inner_loop_raw: PackedVector2Array,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	terrain_indices: PackedInt32Array,
	cancel_token: Dictionary = {}
) -> void:
	_terrain_influence_builder._append_terrain_influence_loop_fill(strip, loop_raw, inner_loop_raw, verts, normals, uvs, terrain_indices, cancel_token)


func _sample_terrain_influence_centerline_height(strip: Dictionary, point: Vector2) -> float:
	return _terrain_influence_builder._sample_terrain_influence_centerline_height(strip, point)


func _sample_terrain_influence_centerline_base_height(strip: Dictionary, point: Vector2) -> float:
	return _terrain_influence_builder._sample_terrain_influence_centerline_base_height(strip, point)


func _sample_terrain_influence_projection(strip: Dictionary, point: Vector2) -> Dictionary:
	return _terrain_influence_builder._sample_terrain_influence_projection(strip, point)


func _build_terrain_influence_segment_lookup(strip: Dictionary) -> Dictionary:
	return _terrain_influence_builder._build_terrain_influence_segment_lookup(strip)


func _apply_terrain_influence_strips_to_mesh(
	verts: PackedVector3Array,
	terrain_indices: PackedInt32Array,
	strips: Array = [],
	over_road_snap_context: Dictionary = {},
	cancel_token: Dictionary = {}
) -> void:
	_terrain_influence_builder._apply_terrain_influence_strips_to_mesh(verts, terrain_indices, strips, over_road_snap_context, cancel_token)


func _closest_point_param_on_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	return _terrain_influence_builder._closest_point_param_on_segment_2d(point, a, b)


func _to_packed_float32_array(value: Variant) -> PackedFloat32Array:
	if value is PackedFloat32Array:
		return value as PackedFloat32Array
	var out := PackedFloat32Array()
	if value is Array:
		var source: Array = value
		out.resize(source.size())
		for i in range(source.size()):
			out[i] = float(source[i])
	return out


func _resolve_path_component_width(
	path: Path3D,
	dist: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	fallback: float
) -> float:
	var value := maxf(0.0, fallback)
	if path != null and path.has_method(offset_method):
		value = float(path.call(offset_method, dist))
	elif path != null and path.has_method(ratio_method):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		value = float(path.call(ratio_method, ratio))
	return maxf(0.0, value)


func _resolve_path_component_scalar(
	path: Path3D,
	dist: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	fallback: float
) -> float:
	var value := fallback
	if path != null and path.has_method(offset_method):
		value = float(path.call(offset_method, dist))
	elif path != null and path.has_method(ratio_method):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clamp(dist / length, 0.0, 1.0)
		value = float(path.call(ratio_method, ratio))
	return value


func _sample_curve_up_vector(curve: Curve3D, dist: float) -> Vector3:
	if curve != null and curve.has_method("sample_baked_up_vector"):
		var up: Vector3 = curve.sample_baked_up_vector(dist, true)
		if up.length() > 0.001:
			return up.normalized()
	return Vector3.UP


func _resolve_road_frame(
	curve: Curve3D,
	path_to_mesh: Transform3D,
	dist: float,
	length: float,
	p_mesh: Vector3,
	p_prev_mesh: Vector3,
	p_next_mesh: Vector3,
	path: Path3D = null
) -> Dictionary:
	var orientation_mode := road_orientation_mode
	var bank_max := road_bank_max_degrees
	var bank_strength := road_bank_strength
	var bank_probe := road_bank_sample_distance
	if path != null and path.has_method("has_orientation_overrides") and path.has_orientation_overrides():
		orientation_mode = path.get_road_orientation_mode()
		bank_max = path.get_road_bank_max_degrees()
		bank_strength = path.get_road_bank_strength()
		bank_probe = path.get_road_bank_sample_distance()
	var world_up := _world_up_in_mesh_space()
	var tangent := p_next_mesh - p_prev_mesh
	# Explicitly closed World Up paths need the same cross section at both ends.
	# One-sided probes leave a wedge at the loop seam, especially far from origin.
	if orientation_mode == ROAD_ORIENTATION_WORLD_UP and length > 0.2 and curve.point_count > 2 \
			and curve.get_point_position(0).is_equal_approx(curve.get_point_position(curve.point_count-1)) \
			and (dist < 0.1 or dist > length-0.1):
		var wrapped := fposmod(dist,length)
		tangent = path_to_mesh.basis * (curve.sample_baked(fposmod(wrapped+0.1,length),true) \
			- curve.sample_baked(fposmod(wrapped-0.1,length),true))
	if orientation_mode != ROAD_ORIENTATION_CURVE_UP:
		tangent.y = 0.0
	if tangent.length_squared() <= 0.000000000001:
		tangent = p_next_mesh - p_mesh
		if orientation_mode != ROAD_ORIENTATION_CURVE_UP:
			tangent.y = 0.0
	if tangent.length_squared() <= 0.000000000001:
		tangent = p_mesh - p_prev_mesh
		if orientation_mode != ROAD_ORIENTATION_CURVE_UP:
			tangent.y = 0.0
	if tangent.length_squared() <= 0.000000000001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()

	var up_mesh := world_up
	if orientation_mode == ROAD_ORIENTATION_CURVE_UP:
		var up_local := _sample_curve_up_vector(curve, dist)
		up_mesh = (path_to_mesh.basis * up_local).normalized()
		if up_mesh.length_squared() <= 0.000000000001:
			up_mesh = world_up

	var right := up_mesh.cross(tangent).normalized()
	if right.length_squared() <= 0.000000000001:
		right = world_up.cross(tangent).normalized()
	if right.length_squared() <= 0.000000000001:
		right = Vector3.RIGHT

	if orientation_mode == ROAD_ORIENTATION_CURVE_UP:
		up_mesh = tangent.cross(right).normalized()
		if up_mesh.length_squared() <= 0.000000000001:
			up_mesh = world_up
	else:
		up_mesh = world_up

	if orientation_mode == ROAD_ORIENTATION_BANK_INTO_CURVE:
		var bank_angle := _compute_curve_bank_angle(curve, path_to_mesh, dist, length,
			bank_max, bank_strength, bank_probe)
		if absf(bank_angle) > 0.00001:
			var roll := Basis(tangent, bank_angle)
			right = (roll * right).normalized()
			up_mesh = (roll * up_mesh).normalized()

	return {
		"tangent": tangent,
		"right": right,
		"up": up_mesh,
	}


func _world_up_in_mesh_space() -> Vector3:
	var up := global_transform.basis.inverse() * Vector3.UP
	if up.length_squared() <= 0.000000000001:
		return Vector3.UP
	return up.normalized()


func _compute_curve_bank_angle(
	curve: Curve3D,
	path_to_mesh: Transform3D,
	dist: float,
	length: float,
	max_degrees: float = -1.0,
	strength: float = -1.0,
	sample_distance: float = -1.0
) -> float:
	if curve == null or length <= 0.0001:
		return 0.0
	if max_degrees < 0.0:
		max_degrees = road_bank_max_degrees
	if strength < 0.0:
		strength = road_bank_strength
	if sample_distance < 0.0:
		sample_distance = road_bank_sample_distance
	var probe := maxf(0.05, sample_distance)
	var prev_dist := maxf(0.0, dist - probe)
	var next_dist := minf(length, dist + probe)
	if is_equal_approx(prev_dist, next_dist):
		return 0.0
	var prev_p := path_to_mesh * curve.sample_baked(prev_dist, true)
	var curr_p := path_to_mesh * curve.sample_baked(dist, true)
	var next_p := path_to_mesh * curve.sample_baked(next_dist, true)
	var prev_dir := curr_p - prev_p
	var next_dir := next_p - curr_p
	prev_dir.y = 0.0
	next_dir.y = 0.0
	if prev_dir.length_squared() <= 0.000000000001 or next_dir.length_squared() <= 0.000000000001:
		return 0.0
	prev_dir = prev_dir.normalized()
	next_dir = next_dir.normalized()
	var signed_turn := atan2(prev_dir.cross(next_dir).y, prev_dir.dot(next_dir))
	var max_bank := deg_to_rad(maxf(0.0, max_degrees))
	return clampf(-signed_turn * maxf(0.0, strength), -max_bank, max_bank)


func _resolve_paths() -> Array[Path3D]:
	var out: Array[Path3D] = []
	var seen: Dictionary = {}
	for np in source_paths:
		if np == NodePath():
			continue
		var n := get_node_or_null(np)
		if n is Path3D:
			_push_unique_path(out, seen, n)

	if out.is_empty():
		for child in get_children():
			if child is Path3D:
				_push_unique_path(out, seen, child)

	if out.is_empty():
		var parent := get_parent()
		if parent != null:
			for sibling in parent.get_children():
				if sibling is Path3D:
					_push_unique_path(out, seen, sibling)

	return out


func _push_unique_path(out: Array[Path3D], seen: Dictionary, path: Path3D) -> void:
	if path == null:
		return
	var key := str(path.get_instance_id())
	if seen.has(key):
		return
	seen[key] = true
	out.push_back(path)


func _cleanup_legacy_generated_children() -> void:
	for child in get_children():
		if not (child is MeshInstance3D):
			continue
		if not child.name.begins_with("GeneratedSpline"):
			continue
		if child.name == MESH_NODE_NAME or child.name == LEGACY_MESH_NODE_NAME:
			continue
		child.queue_free()


## Value arrays in road-local coordinates, excluding built-in terrain and walls.
func get_terrain_surface_data() -> Dictionary:
	return _terrain_surface_data.duplicate(true)

func get_terrain_surface_revision() -> int:
	return _terrain_surface_revision

func _assign_mesh(mesh: ArrayMesh) -> void:
	_terrain_surface_data = mesh.get_meta("_roda_terrain_surface", {})
	mesh.remove_meta("_roda_terrain_surface")
	_terrain_surface_revision += 1
	var profile_total_start := _profile_start()
	_debug_log("_assign_mesh called: surfaces=%s uploads=%s children_before=%s" % [_runtime_output._surface_count(mesh), mesh.get_surface_count(), get_child_count()])
	var profile_node_start := _profile_start()
	var mi := get_node_or_null(MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		mi = get_node_or_null(LEGACY_MESH_NODE_NAME) as MeshInstance3D
	if mi == null:
		_debug_log("creating MeshInstance3D node: " + MESH_NODE_NAME)
		mi = MeshInstance3D.new()
		mi.name = MESH_NODE_NAME
		add_child(mi)
		_debug_log("add_child done, children_after=%s" % [get_child_count()])
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
			_debug_log("owner set to edited scene root: " + str(mi.owner))
	_profile_log("assign mesh resolve/create node", profile_node_start)
	var profile_mesh_set_start := _profile_start()
	mi.mesh = mesh if output_mode == 0 else null
	_profile_log("assign mesh set mesh", profile_mesh_set_start, "surfaces=%s" % [mesh.get_surface_count()])
	_debug_log("mesh assigned to node: " + str(mi.name))
	var profile_collision_start := _profile_start()
	_sync_generated_collision_shape(mi, mi.mesh)
	_profile_log("assign mesh sync collision", profile_collision_start)
	var has_per_band_materials := (
		road_material_override != null
		or shoulder_material_override != null
		or sidewalk_material_override != null
		or terrain_material_override != null
		or outer_wall_material_override != null
	)
	mi.material_override = null if has_per_band_materials else material_override
	_debug_log("material_override set (per_band=%s)" % [has_per_band_materials])
	if output_mode == 1:
		_runtime_output.assign_chunks(self, mesh, output_chunk_size, mi)
		_debug_log("spatial output: %s" % _runtime_output.last_stats)
	else:
		_runtime_output.clear(self)
	_update_lane_material_overlay()
	_profile_log("assign mesh total", profile_total_start, "per_band=%s" % [has_per_band_materials])


func _update_lane_material_overlay() -> void:
	var overlay_mesh := _build_lane_material_overlay_mesh()
	var overlay := get_node_or_null(LANE_MATERIAL_OVERLAY_NODE_NAME) as MeshInstance3D
	if overlay_mesh == null or overlay_mesh.get_surface_count() <= 0:
		if overlay != null:
			overlay.mesh = null
		return
	if overlay == null:
		overlay = MeshInstance3D.new()
		overlay.name = LANE_MATERIAL_OVERLAY_NODE_NAME
		add_child(overlay)
		if Engine.is_editor_hint():
			overlay.owner = get_tree().edited_scene_root
	overlay.mesh = overlay_mesh
	overlay.material_override = null


func _build_lane_material_overlay_mesh() -> ArrayMesh:
	_lane_overlay_cache.begin(self)
	if not _has_lane_material_overrides():
		_lane_overlay_cache.finish()
		return null
	var paths := _resolve_paths()
	if paths.is_empty():
		_lane_overlay_cache.finish()
		return null
	var mesh := ArrayMesh.new()
	var inv_global := global_transform.affine_inverse()
	if _terrain_surface_data.has("lane_indices"):
		_append_final_lane_material_surfaces(mesh, paths, inv_global)
	else:
		_append_lane_material_side_surfaces(mesh, paths, inv_global, true, left_lane_material_overrides)
		_append_lane_material_side_surfaces(mesh, paths, inv_global, false, right_lane_material_overrides)
	_lane_overlay_cache.finish()
	return mesh


func _append_final_lane_material_surfaces(mesh: ArrayMesh, paths: Array[Path3D], inv_global: Transform3D) -> void:
	if preload("./road_lane_material_overrides.gd").has_overrides(paths):
		preload("./road_lane_material_overrides.gd").new().append_surfaces(self, mesh, paths, inv_global)
		return
	var projector := preload("./road_lane_overlay_projector.gd").new()
	projector.configure(_terrain_surface_data, global_transform)
	var buckets: Array[Dictionary] = []
	for left_side in [true, false]:
		var materials := left_lane_material_overrides if left_side else right_lane_material_overrides
		for lane in range(materials.size()):
			if materials[lane] != null:
				buckets.append({"left": left_side, "lane": lane, "material": materials[lane],
					"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
					"uvs": PackedVector2Array(), "indices": PackedInt32Array()})
	# Source order owns overlaps, independent of material/side grouping.
	for path in paths:
		if path == null or path.curve == null or path.curve.point_count < 2 or _path_is_terrain_influence_only(path):
			continue
		for bucket in buckets:
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var indices := PackedInt32Array()
			_append_lane_material_path_strip(vertices, normals, uvs, indices, path, inv_global, bucket.left, bucket.lane)
			for i in range(0, indices.size(), 3):
				var points := PackedVector3Array()
				var texcoords := PackedVector2Array()
				for corner in range(3):
					var index := indices[i + corner]
					var up := (global_basis * normals[index]).normalized()
					points.append(global_transform * vertices[index] - up * lane_material_overlay_lift)
					texcoords.append(uvs[index])
				for triangle: Dictionary in projector.project(points, texcoords, lane_material_overlay_lift):
					_append_projected_lane_triangle(bucket, triangle, inv_global)
	for bucket in buckets:
		_lane_overlay_cache.mesh_builder._add_surface(mesh, bucket.vertices, bucket.normals,
			bucket.uvs, bucket.indices, bucket.material, true)


func _append_projected_lane_triangle(bucket: Dictionary, triangle: Dictionary, inv_global: Transform3D) -> void:
	var tri: PackedVector3Array = triangle.vertices
	var local := PackedVector3Array([inv_global * tri[0], inv_global * tri[1], inv_global * tri[2]])
	if (local[1] - local[0]).cross(local[2] - local[0]).length_squared() < 0.0000000001:
		return
	var corners := [0, 1, 2]
	if ((tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(triangle.normal) > 0.0) == invert_faces:
		corners = [0, 2, 1]
	for corner in corners:
		bucket.indices.append(bucket.vertices.size())
		bucket.vertices.append(local[corner])
		bucket.normals.append((global_basis.transposed() * triangle.normal).normalized())
		bucket.uvs.append(triangle.uvs[corner])


func _has_lane_material_overrides() -> bool:
	if preload("./road_lane_material_overrides.gd").has_overrides(_resolve_paths()):
		return true
	for material in left_lane_material_overrides:
		if material != null:
			return true
	for material in right_lane_material_overrides:
		if material != null:
			return true
	return false


func _append_lane_material_side_surfaces(
	mesh: ArrayMesh,
	paths: Array[Path3D],
	inv_global: Transform3D,
	left_side: bool,
	materials: Array[Material]
) -> void:
	for lane_index in range(materials.size()):
		var lane_material := materials[lane_index]
		if lane_material == null:
			continue
		var overlay_vertices := PackedVector3Array()
		var overlay_normals := PackedVector3Array()
		var overlay_uvs := PackedVector2Array()
		var overlay_indices := PackedInt32Array()
		for path in paths:
			if path == null or path.curve == null or path.curve.point_count < 2 or _path_is_terrain_influence_only(path):
				continue
			_append_lane_material_path_strip(
				overlay_vertices,
				overlay_normals,
				overlay_uvs,
				overlay_indices,
				path,
				inv_global,
				left_side,
				lane_index
			)
		_lane_overlay_cache.mesh_builder._add_surface(mesh, overlay_vertices, overlay_normals, overlay_uvs, overlay_indices, lane_material, false)


func _append_lane_material_path_strip(
	vertices: PackedVector3Array,
	normals_out: PackedVector3Array,
	uvs_out: PackedVector2Array,
	indices: PackedInt32Array,
	path: Path3D,
	inv_global: Transform3D,
	left_side: bool,
	lane_index: int
) -> void:
	var curve := path.curve
	var length := curve.get_baked_length()
	if length <= 0.001:
		return
	var distances := _lane_material_sample_distances(path)
	if distances.size() < 2:
		return
	var data := _lane_overlay_cache.rows(path, inv_global, left_side, lane_index, distances, length)
	var base := vertices.size()
	vertices.append_array(data.vertices)
	normals_out.append_array(data.normals)
	uvs_out.append_array(data.uvs)
	for row_index in range(data.widths.size() - 1):
		if maxf(data.widths[row_index], data.widths[row_index + 1]) <= 0.0001:
			continue
		var index := base + row_index * 2
		_append_quad_indices(indices, index, index + 1, index + 2, index + 3)


func _lane_material_sample_distances(path: Path3D) -> PackedFloat32Array:
	var generation_step := sample_step
	if path.has_method("get_road_generation_sample_step"):
		generation_step = maxf(0.01, float(path.call("get_road_generation_sample_step", sample_step)))
	return _build_open_distances_with_step(path.curve.get_baked_length(), generation_step)


func _build_lane_material_rows_native(path: Path3D, inv_global: Transform3D,
		left_side: bool, lane_index: int, distances: PackedFloat32Array, length: float) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals_out := PackedVector3Array()
	var uvs_out := PackedVector2Array()
	var widths := PackedFloat64Array()
	for distance in distances:
		var dist := float(distance)
		var frame := get_path_surface_frame(path, dist)
		if frame.is_empty():
			continue
		var center_world: Vector3 = frame.get("center", Vector3.ZERO)
		var right_world: Vector3 = frame.get("right", Vector3.RIGHT)
		var up_world: Vector3 = frame.get("up", Vector3.UP)
		var extents := _resolve_path_lane_extents(path, dist, length)
		var side_extent := extents.x if left_side else extents.y
		var local_lane_width := _resolve_lane_material_width(path, dist, side_extent)
		var inner_distance := minf(side_extent, float(lane_index) * local_lane_width)
		var outer_distance := minf(side_extent, float(lane_index + 1) * local_lane_width)
		var direction := -right_world if left_side else right_world
		var inner_world := center_world + direction * inner_distance + up_world * lane_material_overlay_lift
		var outer_world := center_world + direction * outer_distance + up_world * lane_material_overlay_lift
		var left_world := outer_world if left_side else inner_world
		var right_edge_world := inner_world if left_side else outer_world
		var normal_local := (inv_global.basis * up_world).normalized()
		vertices.push_back(inv_global * left_world)
		vertices.push_back(inv_global * right_edge_world)
		normals_out.push_back(normal_local)
		normals_out.push_back(normal_local)
		uvs_out.push_back(Vector2(0.0, dist * uv_length_scale))
		uvs_out.push_back(Vector2(1.0, dist * uv_length_scale))
		widths.push_back(outer_distance - inner_distance)
	return {"vertices": vertices, "normals": normals_out, "uvs": uvs_out, "widths": widths}


func _resolve_lane_material_width(path: Path3D, distance: float, side_extent: float) -> float:
	if path.has_method("get_lane_layout_at_offset"):
		var layout_raw = path.call("get_lane_layout_at_offset", distance)
		if layout_raw is Dictionary:
			return maxf(0.01, float(layout_raw.get("lane_width", side_extent)))
	return maxf(0.01, side_extent)


func _sync_generated_collision_shape(mi: MeshInstance3D, _mesh: ArrayMesh) -> void:
	if mi != null:
		_runtime_output.sync_collision(mi, self)


func _clear_mesh_node() -> void:
	_terrain_surface_data = {}
	_terrain_surface_revision += 1
	_output_ready = false
	clear_source_generation_cache()
	_runtime_output.clear(self)
	_marking_builder.clear(self)
	_marking_rows = []
	_marking_exclusions = {}
	var mi := get_node_or_null(MESH_NODE_NAME)
	if mi != null:
		_debug_log("clearing node: " + MESH_NODE_NAME)
		mi.queue_free()
	var legacy := get_node_or_null(LEGACY_MESH_NODE_NAME)
	if legacy != null:
		_debug_log("clearing legacy node: " + LEGACY_MESH_NODE_NAME)
		legacy.queue_free()
	var lane_overlay := get_node_or_null(LANE_MATERIAL_OVERLAY_NODE_NAME)
	if lane_overlay != null:
		lane_overlay.queue_free()
	_clear_terrain_influence_debug_node()


func _update_terrain_influence_debug_visual() -> void:
	if not terrain_influence_debug_draw or _terrain_influence_strips.is_empty():
		_clear_terrain_influence_debug_node()
		return
	var mi := get_node_or_null(TERRAIN_INFLUENCE_DEBUG_NODE_NAME) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = TERRAIN_INFLUENCE_DEBUG_NODE_NAME
		add_child(mi)
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
	var debug_mesh := ImmediateMesh.new()
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	debug_mesh.surface_set_color(terrain_influence_debug_color)
	for strip_raw in _terrain_influence_strips:
		var strip: Dictionary = strip_raw
		var band_left_edges: Array = strip.get("band_left_edges", [])
		var band_right_edges: Array = strip.get("band_right_edges", [])
		for edge_raw in band_left_edges:
			var edge: PackedVector3Array = edge_raw
			_append_debug_line_chain(debug_mesh, edge, false)
		for edge_raw in band_right_edges:
			var edge: PackedVector3Array = edge_raw
			_append_debug_line_chain(debug_mesh, edge, false)
		var loop: PackedVector2Array = strip.get("loop", PackedVector2Array())
		if loop.size() >= 3:
			var avg_y := 0.0
			var points: PackedVector3Array = strip.get("points", PackedVector3Array())
			if not points.is_empty():
				for p in points:
					avg_y += p.y
				avg_y /= float(points.size())
			for i in range(loop.size()):
				var a := loop[i]
				var b := loop[(i + 1) % loop.size()]
				debug_mesh.surface_add_vertex(Vector3(a.x, avg_y + terrain_influence_debug_lift, a.y))
				debug_mesh.surface_add_vertex(Vector3(b.x, avg_y + terrain_influence_debug_lift, b.y))
	debug_mesh.surface_end()
	mi.mesh = debug_mesh
	mi.material_override = null
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _append_debug_line_chain(debug_mesh: ImmediateMesh, edge: PackedVector3Array, closed: bool) -> void:
	if edge.size() < 2:
		return
	var lift_vec := Vector3.UP * terrain_influence_debug_lift
	for i in range(edge.size() - 1):
		debug_mesh.surface_add_vertex(edge[i] + lift_vec)
		debug_mesh.surface_add_vertex(edge[i + 1] + lift_vec)
	if closed:
		debug_mesh.surface_add_vertex(edge[edge.size() - 1] + lift_vec)
		debug_mesh.surface_add_vertex(edge[0] + lift_vec)


func _clear_terrain_influence_debug_node() -> void:
	var node := get_node_or_null(TERRAIN_INFLUENCE_DEBUG_NODE_NAME)
	if node != null:
		node.queue_free()


func _build_signature() -> String:
	return _build_geometry_signature() + "|" + _appearance_update.signature(self)


func _build_geometry_signature() -> String:
	var parts: Array[String] = [str(global_transform), str(uv_length_scale)]
	parts.append(str([lateral_join_max_gap, lateral_join_max_overlap,
		lateral_join_height_tolerance, lateral_join_height_blend_width, lateral_join_max_angle_degrees,
		lateral_join_transition_length, lateral_join_transition_subdivisions]))
	if lateral_join_transition_profile != null:
		for i in range(lateral_join_transition_profile.point_count):
			parts.append(str([lateral_join_transition_profile.get_point_position(i),
				lateral_join_transition_profile.get_point_left_tangent(i),
				lateral_join_transition_profile.get_point_right_tangent(i)]))
	# Junction clearance also controls lateral weld exclusion regions and barriers.
	parts.append(str(markings_junction_clearance))
	parts.append(str(output_mode))
	parts.append(str(output_chunk_size))
	parts.append(str(output_generate_collision))
	parts.append(str(output_collision_layer))
	parts.append(str(output_collision_mask))
	parts.append(str(road_width))
	parts.append(str(sample_step))
	parts.append(str(threaded_generation_enabled))
	parts.append(str(threaded_show_road_preview))
	parts.append(str(incremental_generation_enabled))
	parts.append(str(y_offset))
	parts.append(str(shoulder_left_width))
	parts.append(str(shoulder_right_width))
	parts.append(str(sidewalk_left_width))
	parts.append(str(sidewalk_right_width))
	parts.append(str(sidewalk_height))
	parts.append(str(road_material_override))
	parts.append(str(shoulder_material_override))
	parts.append(str(sidewalk_material_override))
	parts.append(str(terrain_material_override))
	parts.append(str(terrain_fill_algorithm))
	parts.append(str(terrain_fill_topology))
	parts.append(str(terrain_fill_base_height))
	parts.append(str(terrain_fill_height_match_epsilon))
	parts.append(str(terrain_fill_height_assign_only))
	if not terrain_fill_height_assign_only:
		parts.append(str(terrain_fill_height_match_max_distance))
		parts.append(str(terrain_fill_height_blend_falloff))
	parts.append(str(terrain_fill_grid_tile_size))
	parts.append(str(terrain_fill_radial_ring_count))
	parts.append(str(terrain_fill_radial_sector_count))
	parts.append(str(terrain_fill_hex_radius))
	parts.append(str(terrain_fill_diamond_tile_size))
	parts.append(str(terrain_fill_adaptive_max_depth))
	parts.append(str(terrain_fill_adaptive_edge_factor))
	parts.append(str(terrain_fill_adaptive_area_factor))
	parts.append(str(terrain_fill_quadtree_max_depth))
	parts.append(str(terrain_fill_quadtree_min_cell_size))
	parts.append(str(terrain_fill_quadtree_error_threshold))
	parts.append(str(terrain_fill_lane_follow_width))
	parts.append(str(terrain_fill_lane_follow_bands))
	parts.append(str(terrain_fill_lod_ring_count))
	parts.append(str(terrain_fill_lod_band_growth))
	parts.append(str(terrain_fill_lod_edge_step_near))
	parts.append(str(terrain_fill_lod_edge_step_far))
	parts.append(str(terrain_fill_delaunay_step_near))
	parts.append(str(terrain_fill_delaunay_step_far))
	parts.append(str(terrain_fill_delaunay_jitter))
	parts.append("outer")
	parts.append(str(terrain_rect_fill_cell_size))
	parts.append(str(terrain_rect_fill_interior_point_step))
	parts.append(str(TERRAIN_RECT_FILL_MAX_TRIANGLES))
	parts.append(str(terrain_rect_fill_road_margin))
	parts.append("outer")
	parts.append(str(outer_wall_height))
	parts.append(str(outer_wall_material_override))
	parts.append(str(material_override))
	parts.append(str(invert_faces))
	parts.append(str(road_orientation_mode))
	if road_orientation_mode == ROAD_ORIENTATION_BANK_INTO_CURVE:
		parts.append(str(road_bank_max_degrees))
		parts.append(str(road_bank_strength))
		parts.append(str(road_bank_sample_distance))
	parts.append(str(endpoint_snap_distance))
	parts.append(str(allow_endpoint_to_midpath))
	parts.append(str(minimum_connections))
	parts.append(str(strip_shoulder_sidewalk_at_intersections))
	parts.append(str(intersection_strip_length))
	parts.append(str(junction_geometry_mode))
	parts.append(str(junction_corner_radius))
	parts.append(str(junction_corner_subdivisions))
	if junction_corner_profile != null:
		for i in range(junction_corner_profile.point_count):
			parts.append(str([junction_corner_profile.get_point_position(i),
				junction_corner_profile.get_point_left_tangent(i), junction_corner_profile.get_point_right_tangent(i)]))
	parts.append(str(adaptive_sampling_enabled))
	parts.append(str(adaptive_sampling_advanced))
	parts.append(str(adaptive_sampling_step_scale))
	parts.append(str(adaptive_sampling_radius_scale))
	parts.append(str(adaptive_sampling_offset))
	parts.append(str(terrain_influence_debug_draw))
	parts.append(str(terrain_influence_debug_color))
	parts.append(str(terrain_influence_debug_lift))

	var paths := _resolve_paths()
	parts.append(str(paths.size()))
	for p in paths:
		parts.append(str(p.get_instance_id()))
		parts.append(str(p.global_transform))
		if p.has_method("get_lateral_join_group"):
			parts.append(p.get_lateral_join_group())
		if p.has_method("get_lateral_join_layers"):
			parts.append(str(p.get_lateral_join_layers()))
		if p.has_method("get_lateral_transition_length"):
			parts.append(str([p.get_lateral_transition_length(false),p.get_lateral_transition_length(true)]))
		if p.has_method("get_orientation_profile_signature"):
			parts.append(p.get_orientation_profile_signature())
		if _path_is_terrain_influence_only(p):
			parts.append("terrain_influence_path")
			if p.has_method("get_terrain_influence_width_profile_signature"):
				parts.append(str(p.call("get_terrain_influence_width_profile_signature")))
			if p.has_method("get_terrain_influence_width"):
				parts.append(str(p.call("get_terrain_influence_width")))
			if p.has_method("should_generate_terrain_influence_surface"):
				parts.append(str(p.call("should_generate_terrain_influence_surface")))
			if p.has_method("should_clip_base_terrain_by_influence_loop"):
				parts.append(str(p.call("should_clip_base_terrain_by_influence_loop")))
			if p.has_method("get_over_road_edge_snap_band"):
				parts.append(str(p.call("get_over_road_edge_snap_band")))
			if p.has_method("get_terrain_influence_flatten_blend"):
				parts.append(str(p.call("get_terrain_influence_flatten_blend")))
			if p.has_method("get_terrain_influence_flatten_strength"):
				parts.append(str(p.call("get_terrain_influence_flatten_strength")))
			if p.has_method("get_terrain_influence_band_count"):
				parts.append(str(p.call("get_terrain_influence_band_count")))
			if p.has_method("get_terrain_influence_height_profile_signature"):
				parts.append(str(p.call("get_terrain_influence_height_profile_signature")))
			if p.has_method("get_terrain_influence_profile_signature"):
				parts.append(str(p.call("get_terrain_influence_profile_signature")))
			if p.has_method("get_terrain_influence_profile_curve"):
				parts.append(str(p.call("get_terrain_influence_profile_curve")))
			if p.has_method("get_terrain_influence_profile_height"):
				parts.append(str(p.call("get_terrain_influence_profile_height")))
			if p.has_method("has_adaptive_sampling_overrides"):
				parts.append(str(p.call("has_adaptive_sampling_overrides")))
			if p.has_method("get_adaptive_sampling_enabled"):
				parts.append(str(p.call("get_adaptive_sampling_enabled")))
			if p.has_method("get_adaptive_sampling_advanced"):
				parts.append(str(p.call("get_adaptive_sampling_advanced")))
			if p.has_method("get_adaptive_sampling_step_scale"):
				parts.append(str(p.call("get_adaptive_sampling_step_scale")))
			if p.has_method("get_adaptive_sampling_radius_scale"):
				parts.append(str(p.call("get_adaptive_sampling_radius_scale")))
			if p.has_method("get_adaptive_sampling_offset"):
				parts.append(str(p.call("get_adaptive_sampling_offset")))
		if p.curve == null:
			parts.append("null_curve")
			continue
		if p.has_method("get_width_profile_signature"):
			parts.append(str(p.call("get_width_profile_signature")))
		if p.has_method("get_edge_profile_signature"):
			parts.append(str(p.call("get_edge_profile_signature")))
		parts.append(str(p.curve.point_count))
		for i in range(p.curve.point_count):
			parts.append(str(p.curve.get_point_position(i)))
			parts.append(str(p.curve.get_point_in(i)))
			parts.append(str(p.curve.get_point_out(i)))
			parts.append(str(p.curve.get_point_tilt(i)))

	return "|".join(parts)
