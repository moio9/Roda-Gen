# Contour junctions (experimental)

For a clean test scene, open
[junction_playground.tscn](../scenes/examples/junction_playground.tscn) and press F6.
Cross, T_Junction and Oblique are independent automatic road generators.
Each has its own editable Corner Profile Curve under Weld; their Path3D children
are the source roads. The ground is just a flat plane, with no terrain builder,
walls or custom connector meshes. RMB orbits, wheel zooms, WASD pans, R resets.

This is an opt-in geometry mode of the existing RoadNetworkCreator3D.
Socket discovery and clustering remain unchanged. The original algorithm is
still available as **Weld → Junction Geometry Mode → Legacy**.

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
If necessary, the builder attempts larger retreats up to three times; short arms
stay at their individual limits while longer arms can supply more space.
This does not scale down the authored sidewalk widths. Unsupported or overlapping layouts
fall back to Legacy and emit a warning. This is not a highway merge solver.

Existing outer-wall heights, terrain settings and debug geometry remain intact;
this mode does not silently flatten terrain or remove authored walls. In the
legacy demo those settings can obscure the junction in the complete scene.
Terrain strips touching retired rows are suppressed, but no new automatic terrain
collar is constructed along the curved sidewalk perimeter in this first version.
The standalone TerrainTopologyBuilder3D still derives its road mask from paths;
it does not yet consume the new corner outline.

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
