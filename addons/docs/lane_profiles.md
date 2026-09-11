# Directional lane profiles

`SplinePathProfile3D` can vary the number and width of traffic lanes at every spline control point. The road centerline stays fixed, so lanes can enter or leave independently on either side.

## Setup

1. Enable `Road > Directional Lanes > Lane Profile Enabled` once on the
   `SplinePathProfile3D`, or press `Enable Directional Lanes For Road` on any
   handle. This is a global road mode, not a per-point switch.
2. Select one of the generated width handles.
3. Set `Lanes Left`, `Lanes Right`, and `Lane Width` in the handle Inspector.
4. Set `Lane Transition Length` to limit the change to the last N metres before the point. Zero uses the complete incoming segment.
5. Edit `Lane Transition` to shape that distance with Godot's Bezier curve editor.
6. Press `Apply Lane Changes` once after editing the points. This rebuilds only
   a lightweight road preview (2 m sampling by default) and stays responsive
   even when the scene contains expensive props.
7. Press `Rebuild Road + Terrain` to close the terrain against the new road
   edges. This explicitly updates matching terrain builders even when their
   automatic editor regeneration is disabled.
8. Press `Rebuild Lane Dependents (Slow)` only when the layout is final. It also
   restores the road's normal sampling and refreshes edge props, terrain, and
   spline-deformed meshes.

The transition stored at point `i` controls the segment from point `i - 1` to point `i`. A lane added at the destination point grows from zero width at the outside road edge. Removing a lane performs the inverse transition.

The default transition is a smooth ease-in/ease-out curve. Its domain and output are interpreted as normalized `0..1` values.

## Compatibility

Per-lane materials on the road are applied as banked overlay strips. With
**Incremental Generation** enabled, unchanged 64-row blocks and indexed normals
are reused; material replacement does not rebuild the row geometry. The combined
overlay mesh is still uploaded, so this does not reduce draw calls. Custom path
scripts use native uncached construction. See
[source regeneration](source_regeneration.md#incremental-lane-material-overlay-rows)
for bounds, counters and native/editor comparison tests.

Lane profiles are disabled by default. Existing scenes continue using `default_width` and `point_widths` as a centered carriageway. Shoulder, sidewalk, terrain fitting, banking, welding, and road-edge consumers use the resulting asymmetric road extents automatically when lane profiles are enabled.

`Live Lane Regeneration` can be enabled for small scenes. It is disabled by
default because long roads with many edge-prop arrays are expensive to rebuild
for every Inspector edit.
