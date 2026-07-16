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
