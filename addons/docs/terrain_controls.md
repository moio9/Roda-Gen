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
Detail is driven by the sampling steps below. The builder keeps only an internal hard cap as a safety limit.
- `auto_point_budget_hard_cap`: maximum budget when auto expansion is enabled.

### Road Cut

- `add_road_edge_points`: adds points on the road edge.
- `add_road_boundary_support_points`: adds no-collar support points just outside the road edge. Keep this on when collars are off.
- `add_near_road_rings`: adds terrain rings outside the road.
- `filter_triangles_crossing_road_edges`: prevents terrain triangles from crossing over the road.
- `soft_road_crossing_filter`: advanced. Leave off for strict road cuts.

### Road Cut / Optional Collar

- `generate_road_edge_collars`: creates explicit edge strips. Prefer off when tight angles self-intersect.
- `road_edge_collar_lateral_step`: collar subdivision size.
- `road_edge_collar_max_width`: optional cap for collar width.

### Road Cut / Strictness

- `strict_no_overlap_near_roads`: rejects more triangles near roads.
- `reject_any_triangle_vertex_inside_road`: stricter vertex rejection.
- `triangle_road_clearance`: extra triangle clearance from the road mask.
- `road_edge_vertex_allowance`: lets edge vertices survive tiny numerical overlap.

### Height Profiles

- `left_profile_distances` / `left_profile_heights`: terrain profile on one side of the road.
- `right_profile_distances` / `right_profile_heights`: terrain profile on the other side.
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
- `filter_triangles_crossing_road_edges = true`
- `road_edge_height_blend_distance = 1.0` to `3.0`
- `protected_road_distance = 3.0`
- `road_protection_blend_distance = 8.0` to `15.0`
- `resolution_step = 2.0` to `4.0`
- `resolution_path_step = 2.0` to `4.0`
