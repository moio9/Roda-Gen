# Terrain Controls

This is the short guide for the terrain controls that usually matter while tuning a road scene.

## TerrainTopologyBuilder3D

### Road Source

- `source_paths`: road paths used as the terrain cut mask.
- `path_sample_step`: base spacing for road samples. Smaller values follow curves better and cost more.
- `road_orientation_mode`: how the road frame is oriented. `Bank Into Curve` is useful for banked roads.

### Road Source / Adaptive Sampling

- `adaptive_path_sampling`: adds denser samples on tight turns.
- `adaptive_min_path_step`: smallest spacing allowed on curves.
- `adaptive_max_path_step`: largest spacing allowed on straights.
- `adaptive_full_curve_angle_degrees`: lower values make the sampler densify sooner.

### Terrain Sampling

- `far_grid_step`: spacing far from roads.
- `near_road_step`: spacing near roads. Smaller values reduce holes and faceting near roads.
- `near_road_width`: how far the near-road rings extend.
- `road_clearance`: minimum terrain offset from the road boundary.

Detail is driven by the sampling steps above. The builder keeps only an internal hard cap as a safety limit.

### Road Cut

- `add_road_boundary_support_points`: adds no-collar support points just outside the road edge. Keep this on when collars are off.

Road edge points, near-road rings, inside-road filtering, and crossing filtering are internal safeguards now. They stay enabled to keep terrain from crossing over the road.

### Road Cut / Optional Collar

- `generate_road_edge_collars`: creates explicit edge strips. Prefer off when tight angles self-intersect.
- `road_edge_collar_lateral_step`: collar subdivision size.
- `road_edge_collar_max_width`: optional cap for collar width.

### Road Cut / Fine Tuning

- `road_interior_reject_margin`: extra margin for rejecting triangles inside the road mask. Increase carefully if terrain leaks over the road.

### Height Profiles

- `Road Network Source`: optional `RoadNetworkCreator3D` fallback for plain `Path3D` sources. It supplies the road width, shoulders and sidewalks when no spline profile exists.
- `TerrainTopologyBuilder3D` owns the default terrain-height profile used by every road.
- `SplinePathProfile3D > Terrain Height Profile > Override Enabled` replaces that default for just that spline. Per-spline values always take priority.
- `left_profile_distances` / `left_profile_heights`: default terrain profile on one side of the road.
- `right_profile_distances` / `right_profile_heights`: default terrain profile on the other side.
- Per-spline profile arrays are intentionally empty until enabled; an incomplete override falls back to the builder default.
- `lock_height_to_road_edge`: keeps terrain height blended back to the road edge.
- `road_edge_height_blend_distance`: smoother blend away from the road edge. Increase this if terrain walls form beside the road.

### Noise

- `noise_enabled`: terrain noise toggle.
- `noise_start_distance_from_road`: keeps noise away from the road edge.
- `noise_fade_distance`: fades noise in gradually.

### Incremental source work

- `centered_triangulation_enabled`: optional numerical conditioning under Output.
  Enable it and regenerate terrain to center only Delaunay's calculation points;
  final vertex coordinates still come from the original samples. It can change
  triangle connectivity and avoids the recorded numerical-overlap fixture, but
  is not a general robust-geometry solver. It defaults to off, preserving legacy
  output. If float32 translation would merge distinct samples, it keeps the
  original calculation coordinates instead. Cache entries and worker jobs include
  this setting; it is independent of incremental source reuse.
- `incremental_generation_enabled`: optional reuse of nearest-road searches,
  height fitting, road-edge crossing tests, filtered triangle groups and unchanged
  Delaunay point arrays. Compatible triangle groups skip filtering/height fitting;
  collar blocks also skip lateral subdivision, diagonal selection and sampling.
  `get_source_rebuild_stats().triangle_groups` and `.collar_groups` report reuse
  and payload size. `.point_groups` reports near-ring/far-grid point-mask blocks;
  accepted proposals still pass through current ordered deduplication and budget
  checks, so these are not cached final point indices.
  Far-grid coordinate blocks also retain their exact continuation cursor;
  `.point_groups.grid_coordinates_reused` distinguishes this from road-mask reuse.
  Near-road rings also retain path-local row selection and coordinates in blocks
  of up to 32 rows. `.point_groups.near_rows_reused` and
  `.point_groups.near_coordinates_reused` report these separately; masks, ordered
  deduplication and the current point budget still apply to every emitted block.
  Outer bounds, polygon contours and boundary-support offsets also retain exact
  coordinate blocks. `.point_groups.bounds_coordinates_reused`,
  `.edge_coordinates_reused` and `.support_coordinates_reused` distinguish them.
  Support direction probes still use current roads, and support masks remain
  spatially validated; cached coordinates never imply cached final point indices.
  Native path samples, their contours and source segments can also be retained
  when another source path changes.
  `.path_samples.paths_reused`, `.paths_rebuilt`, `.rows_reused` and `.rows_rebuilt`
  distinguish actual resampling from reuse; `.collection_reused` reports the
  pre-existing whole-road-data shortcut.
  `.path_samples.segments_reused` / `.segments_rebuilt` and
  `.polygons_reused` / `.polygons_rebuilt` report assembly independently of rows.
  Exact curve/profile/transform inputs, including the pre-bake length, are checked.
  Custom path/frame callbacks bypass
  this optimization. These value-only snapshots cap at 512 entries / 64 MiB,
  expire after four idle generations and are not saved into scenes.
  Native vertex/UV assembly copies retained collars in bulk; `.mesh_stream`
  reports buffered vertices, bulk copies and capacity fallback. The transient
  buffer caps at 393,216 vertices and preserves the original normal-generation
  order. It is not draw-call batching and does not change output partitioning.
  Certified triangle groups also bulk-copy consecutive emission runs without
  exceeding the per-frame candidate budget; `.triangle_groups.candidates_bulk`
  counts skipped individual candidates, while `.emission_triangles_reused` under
  the same group counts accepted triangles copied to the stream.
  Spatial Chunks consumes native raw arrays directly when available:
  `.mesh_stream.direct_arrays` records this transfer and
  `.output.source_surface_builds` counts complete source SurfaceTool
  materializations. Warm/local-normal jobs avoid that whole-mesh conversion;
  cold/full-normal and unsupported-output paths retain native fallback.
  This is independent of the road node's option and defaults to off.
- `local_triangulation_enabled`: experimental affected-cavity triangulation, requiring
  `incremental_generation_enabled`. Unchanged triangles are retained as value
  data; source triangle assembly still runs globally. Native full
  triangulation (including its worker) remains the fallback for unsupported or
  ambiguous patches. External near-cocircular points now expand the patch with
  their incident triangles instead of immediately forcing a full call. The same
  eight-attempt and geometry/capacity checks still bound this operation. It can
  preserve more triangles while taking longer than native full triangulation;
  inspect the counters and measure your scene. This option uses deterministic triangle ordering for
  normal generation, so buffers may differ from the legacy mode. It is not a
  universal speedup: the optimized ten-road fixture is faster, but small fixtures
  can still be slower. Centering is an independent setting and can help or worsen
  different numerical cases; neither setting repairs all native degeneracies.
- `get_source_rebuild_stats()`: copied work/reuse counters and a `pending` flag.
- `clear_source_generation_cache()`: clear retained source results and output
  validation snapshots, immediately when idle or at the next generation if a
  job is pending. Existing output nodes remain until rebuild or Clear Generated.

Changed point sets use native full triangulation unless local triangulation is
enabled and its patch checks succeed. Single Mesh output still rebuilds completely;
the optional Spatial Chunks mode below retains unchanged final resources.
Custom terrain subclasses and active height modifiers retain the full workflow.
Terrain-height queries return `{hit: false, pending: true}` during generation;
consumers should retry after it finishes. `is_terrain_generation_pending()`
exposes readiness and `terrain_generation_completed` signals the final completed
build, including an empty result. `SplinePropArray3D` automatically retries an
explicitly deferred rebuild while retaining its old nodes/collisions/batches.
Terrain-only completion schedules prop updates at runtime and with editor auto
regeneration enabled. Clearing props cancels their pending request and listener.
Idle built-in terrain without active modifiers also supports ground-placement
reuse through current-hit validation; this is independent of this terrain's own
source-cache toggle. See `source_regeneration.md` for exact dependency rules,
validation and remaining work.

### Spatial output

- `output_mode`: **Single Mesh** remains the default. **Spatial Chunks** assigns
  each complete triangle to an XZ cell by its centroid. With
  `incremental_generation_enabled`, unchanged cells retain their MeshInstance3D,
  ArrayMesh, CollisionShape3D and concave shape resources. Source local
  triangulation is independent; the two options can be combined.
- `output_chunk_size`: cell size in metres, default 64. Smaller cells can localize
  resource replacement but increase node and draw-call counts. This is not a
  batching optimization: the three-road opaque fixture renders 35 draw calls
  with chunks versus 2 with its single mesh.
- `get_source_rebuild_stats().output`: retained/rebuilt mesh and collision counts,
  cell count, geometry snapshot bytes, publication time and fallback reason.

In chunk mode `GeneratedTopologyTerrain` is a Node3D container of mesh cells;
`GeneratedTopologyTerrainCollision` remains a StaticBody3D with one shape per cell.
The last complete output stays visible/physical while a worker or multi-frame
build is pending. Clear Generated cancels that publication and removes all output;
an empty completed build also removes old output. Switching back to Single Mesh
restores the original MeshInstance3D hierarchy. Current material overrides are
applied even when geometry is retained. Retained nodes keep edited-scene ownership
and are saved like the existing generated terrain.

With incremental generation and no active modifiers, unchanged geometry skips
normal calculation and partitioning. Local edits recalculate native normals on
complete affected-vertex neighbourhoods, including neighbours across cell borders.
Cold builds, broad edits or reordered smoothing contributions use the full native
normal pass. `get_source_rebuild_stats().output.normals` reports these operations
and retained/rebuilt vertex-normal counts. Point enumeration, final vertex emission
and partition traversal for changed geometry remain global. Normal selection and
validation also have a cost, so local calculation is not always faster.
Custom terrain subclasses keep the single-mesh path; built-in height modifiers
still run their full callbacks before exact output comparisons. Transparent or
per-instance/AABB-dependent shaders can behave differently when output is split.
See `source_regeneration.md` for tested geometry, physics, rendering and bounds.

### Height Modifiers

- `auto_find_height_modifiers`: finds child/group modifiers automatically.
- `add_modifier_resolution_points`: lets modifiers add points so their shape is not faceted.
- `expand_bounds_for_modifiers`: extends terrain bounds to cover modifiers.

## TerrainHeightModifier3D

### Main Shape

- `mode`: modifier behavior. `CUSTOM_PROFILE` and `CURVE_Y` are the most useful for shaped terrain.
- `radius`: how far from the modifier path it affects terrain.
- `inner_radius`: full-strength core before falloff starts.
- `strength`: height amount for modes that use relative strength.
- `falloff_power`: higher values make the falloff sharper.

### Road Protection

- `affect_near_roads`: if off, the modifier avoids the road edge.
- `protected_road_distance`: no modifier effect this close to the road.
- `road_protection_blend_distance`: fade distance after the protected zone. Increase this to remove sharp walls near roads.
- `distance_sample_step`: modifier path sampling used for distance checks.

### Resolution Points

- `resolution_radius`: how far extra points are added around the modifier.
- `resolution_step`: spacing across the modifier. Smaller values make smoother modifier terrain.
- `resolution_path_step`: spacing along the modifier path.
- `resolution_radial_rings`: number of cross-section rings.
- `add_circle_resolution_points`: adds radial/circular samples. Useful for broad blobs, but can cost more.

## Good Starting Values

For road-adjacent raised terrain:

- `generate_road_edge_collars = false`
- `add_road_boundary_support_points = true`
- `road_edge_height_blend_distance = 1.0` to `3.0`
- `protected_road_distance = 3.0`
- `road_protection_blend_distance = 8.0` to `15.0`
- `resolution_step = 2.0` to `4.0`
- `resolution_path_step = 2.0` to `4.0`
