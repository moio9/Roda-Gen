# Contour junctions (experimental)

For a clean test scene, open
[junction_playground.tscn](../scenes/examples/junction_playground.tscn) and press F6.
Cross, T_Junction and Oblique are independent automatic road generators.
Each has its own editable Corner Profile Curve under Weld; their Path3D children
are the source roads. The ground is just a flat plane, with no terrain builder,
walls or custom connector meshes. RMB orbits, wheel zooms, WASD pans, R resets.

This is an opt-in geometry mode of the existing RoadNetworkCreator3D.
The original algorithm remains available as
**Weld → Junctions → Junction Geometry Mode → Legacy**. When lateral joining is
enabled, priority is decided at each local contact; a lateral join at one end
does not disable a transverse junction elsewhere on those paths.

The existing scenes/spline_road/spline_intersections_demo.tscn now opts into
**Contour (Experimental)**. Reload that scene and regenerate Intersections
to replace its previously saved mesh. No other existing scene is switched.

## Shape controls

- **Junction Corner Radius** controls requested retreat/rounding space in metres.
  It is not an exact circular radius: corners use sampled quadratic curves;
  two-arm connections use a cubic centerline.
- **Junction Corner Subdivisions** controls segments per corner.
- **Junction Corner Profile** accepts a Godot Curve. Create a Curve resource
  in the Inspector to edit the graph. X runs along the corner from 0 to 1;
  Y blends from a direct/chamfered connection (0) toward a curved outline (1).
  No Curve means fully curved. Values are clamped to 0–1.

Start with constant Y=1 for round corners, Y=0 for chamfers, or a gentle curve
between them. Subdivision changes smoothness, not the underlying profile.
Curve points/tangents participate in the editor regeneration signature.

## Geometry and limits

The builder retains full sampled cross sections outside a junction and removes
interior road triangles. Asphalt is triangulated as a continuous outline;
shoulders and sidewalks are separate bands. Sidewalk widths and heights blend
between actual connected edges instead of squeezing an entire cross section.
Two-arm joins and endpoint-to-midpath T connections use the same source roads.
Contour asphalt UV tiling follows the road's `uv_length_scale`, so the junction
uses the same texture density as the incoming lanes.

For sloped outlines with at least three arms, the builder uses a triangle fan
when the junction center lies strictly inside the polygon kernel. Its interior
height uses mean-value interpolation of the boundary, preserving planar slopes
and the retained cross sections. This avoids steep sliver faces from boundary-only
triangulation. Flat outlines and outlines that cannot safely support this fan keep
the existing polygon triangulation. This does not impose a maximum road grade.
The junction report's `interior_support` flag identifies the fan construction.

Asphalt and outer-sidewalk outlines are checked for self-intersection before
publishing. Each arm requests retreat based on its own width and is capped at
its own available sampled length, retaining at least one original end segment.
Retreat stops before an approach bends away from the local junction direction.
A nearby host endpoint outside the other road's asphalt remains a continuing arm.
If the candidate overlaps and an arm is limited, the builder retries with less
rounding space; otherwise it can try larger retreats, up to three retries.
Reports expose `requested_radius` and `fitted_radius`; the authored setting stays
unchanged. Junction-area shoulders and sidewalks are clipped against the actual
asphalt of the participating roads, including vertical curb faces, with a height
filter to avoid cutting bands on a different level.
This does not scale down the authored sidewalk widths. Unsupported or overlapping layouts
fall back to Legacy and emit a warning. This is not a highway merge solver.

Existing outer-wall heights, terrain settings and debug geometry remain intact;
this mode does not silently flatten terrain or remove authored walls. In the
legacy demo those settings can obscure the junction in the complete scene.
Terrain strips touching retired rows are suppressed, but no new automatic terrain
collar is constructed along the curved sidewalk perimeter in this first version.
`TerrainTopologyBuilder3D` automatically consumes the final road surface from
its resolved `RoadNetworkCreator3D` sources. This includes contour corners and
their final heights. No scene-specific script is needed. Road-only source arrays
exclude built-in terrain and outer walls and work with Single Mesh and Spatial
Chunks output. Plain paths without a road network retain path-based terrain.

Terrain adds final-road vertices as triangulation supports, clips crossing
triangles instead of rejecting them wholesale, and fits the cut seam height.
Both `generate_road_edge_collars` and `auto_lane_profile_edge_collars` must be
false to disable collars; their settings remain independent of junction fitting.
`terrain_edge_y_offset = 0.0` produces a flush height seam. Existing authored
offsets, height-lock and blend controls are respected.

A terrain rebuild waits for pending road generation. Final-road revisions and
transforms participate in editor regeneration signatures. While final-road
clipping is active, path-only incremental source caches are bypassed because
their triangle replay does not represent the clipped output; spatial output
resource reuse remains available. The XZ mask retains the existing ground-road
limitation and is not a stacked-bridge terrain solver. The former
`road_mesh_terrain.gd` and `poiana_terrain.gd` scripts are compatibility aliases
of the shared generator.

New corner triangles currently rebuild on every generation. Source caches remain
usable, but the legacy junction replay cache is bypassed for successful contour
clusters. The contour_junctions entry in get_source_rebuild_stats() reports
success, fallback reasons, chosen retreat and retry counts. The arm_retreats
list reports path, side, requested/actual retreat and whether the arm was limited.
Some acute near-end layouts can still be rejected; rejection is a limit of this
experimental outline solver, not proof that no geometric solution exists.

## Checks

    godot --headless --path . --script tools/check_contour_junctions.gd
    godot --headless --path . --script tools/check_contour_short_arms.gd
    godot --headless --path . --script tools/check_contour_junctions.gd -- --user-scene
    godot --path . --script tools/check_contour_junctions.gd -- --user-scene --screenshots --road-only

The user-scene check copies the authored demo to a temporary test artifact and
only remaps resource paths; it does not launch the consuming game's autoloads.
The optional road-only render hides other geometry and uses neutral materials
in memory for diagnosis. Original geometry/materials in the scene are not saved
or replaced by the test.
