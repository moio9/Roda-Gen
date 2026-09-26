# Lateral road joins (experimental)

Open [lateral_join_playground.tscn](../scenes/examples/lateral_join_playground.tscn)
and press F6. The right example enables joining; the left keeps its original
edges. Both use independent main and extra-lane splines that can be moved and angled.
The [highway entry](../scenes/examples/highway_entry.tscn) also uses this feature.

## Setup

1. Put both `SplinePathProfile3D` sources in the same `RoadNetworkCreator3D`.
2. In **Weld > Lateral Join Layers**, check at least one of the same numbered
   boxes on both paths. The boxes are join channels only; they do not change
   physics collision layers. Existing scenes can keep using the same nonempty
   **Lateral Join Group** name instead.
3. Bring their facing **asphalt edges** together. The distance is measured at
   the lane edges, rather than at the outer edges of sidewalks or shoulders.
4. Adjust **Weld > Lateral Joins** on the network if needed. Defaults allow a
   0.35 m gap, 1 m overlap, 0.15 m vertical difference and 15 degrees of local
   tangent difference. These limits discover an initial facing-edge contact. Once
   found, the same pair can merge a deeper partial overlap toward an angled
   endpoint, while a lane remains exposed outside the other road. Measurements
   use the generator's local coordinates.

No checked layer and an empty group disable the feature for that path. Different groups without a shared layer, distant
edges, large height differences and transverse crossings remain independent.
This is geometric joining, not traffic direction or right-of-way logic.

Each path retains its own curve, lane counts, width transitions and outer-edge
settings. Moving a path away or clearing its group restores its complete edges.
The implementation lives in `scripts/spline_road/road_lateral_join.gd`; the
example scenes contain configuration and normal addon scripts only.

## Smooth endpoints

A full-width endpoint beside a continuing host road receives a curved extension.
The default **Lateral Join Transition Length** is 12 m; set it to zero for square
ends. The extension starts at zero width on the host asphalt edge and reaches
the original extra-lane width with an S-shaped easing. The outside shoulder,
sidewalk, curb, edge paint and wall follow the same generated cross sections.
The original full-width section and all authored source points remain intact.
At an angled endpoint, the default curve also matches the source direction and
its exact cross section. A distant endpoint outside the gap tolerance receives
no extension, even if its transition length is large.

- **Lateral Join Transition Subdivisions** controls curve resolution; sampling
  also respects the network's Sample Step.
- **Lateral Join Transition Profile** accepts a separate `Curve`: X is progress
  from the tip to the full-width attachment, Y is width fraction. Use a 0..1
  domain and range. Endpoints are fixed at zero/full width; null uses a cubic
  S curve with zero endpoint slopes. Custom endpoint slopes control how gently
  the transition connects.
- On each spline, **Lateral Join Start Transition Length** and **Lateral Join End
  Transition Length** override the length independently. `-1` inherits the
  network setting and `0` disables only that end.

The extension follows the host's sampled edge and is capped by the available
host length and endpoint-junction exclusions. Closed paths and source endpoints
already tapered to zero receive no additional extension. Source discovery is
independent of the order of the host and extra-lane paths. Transition information
is available in `get_source_rebuild_stats().lateral_joins.transitions`, including
whether the requested length was limited. Leave space around the authored path
for this additional geometry when sizing terrain bounds or placing props.

These are generated extra cross sections in the common addon, implemented in
`road_lateral_transition.gd`. They use their own width-easing profile: the
intersection's corner profile controls a different, quadratic corner construction.

## Generated result

- Small gaps receive asphalt strips between the actual sampled edges.
- Asphalt overlaps in a detected merge pair are clipped; the earlier resolved source owns the
  shared area. This avoids two coplanar asphalt layers.
- **Lateral Join Height Blend Width** enables automatic height matching on each
  rebuild. The joining road's sampled cross sections move vertically to follow
  the host grade, and their banking eases into the host across this width. The
  source curves remain unchanged. Zero preserves authored heights, which is the
  default. A road that overlaps itself at a tight bend still needs a wider bend
  or narrower width.
- Inner shoulders, sidewalks, curb faces and outer walls are removed only over
  the common length. Oblique shoulders and sidewalks are additionally clipped
  against the other road's asphalt; surviving band overlaps are emitted once.
  The exterior sides retain their authored widths.
- A shared edge uses the network's **Markings Lane Style** exactly once. Its
  original edge paint is suppressed; normal edge paint resumes outside the join.
- Collision and the standalone terrain generator consume the resulting road
  surface, including filled gaps. Built-in terrain strips are blocked on interior
  side rows. Their transition resolution follows the road sampling distance.

Generation never rewrites either source curve or its width settings. Source and
marking caches include the necessary changes; threaded finalization uses the
same joined geometry. Changing a group or a network tolerance triggers the
normal editor rebuild.

## Current limits

This is a local, almost-parallel edge join, not arbitrary road polygon union.
A pair needs an initial edge contact; a road wholly buried inside another does
not create a merge by itself. Grouped shallow merges take priority over classic
intersection discovery only where the local asphalt edges meet, including when
source intersection overrides are enabled. Different ends of the same pair can
use lateral joining and a contour intersection at the same time.
Transverse intersections continue using the junction generator, and their
regions are excluded from lateral joining. Use shorter sample
steps for tight bends or short transitions. With height matching disabled, a
small allowed vertical difference is connected between the actual edge heights.
Height matching needs an initial facing-edge contact within the configured height
tolerance; stacked roads do not join merely because their XZ footprints overlap.

Connected `SplinePropArray3D` segments and edge-placed `SplineMeshDeformer3D`
outputs follow the final outline with `Follow Generated Road Edge` enabled.
Their thickness is placed outside the road and pieces crossing a junction opening
are omitted. Independent props still use their authored source paths and ranges.

Per-lane material strips are clipped to the final asphalt and projected onto its
height and bank. Source order owns overlapping strips; later paths cannot add a
second overlay on the same final triangle. Shoulders and sidewalks are excluded,
and elevated decks retain separate coverage. UVs keep the authored lane mapping.
New intersection/transition pavement outside all authored lane strips retains
the shared asphalt material. Projection accepts up to 0.75 m between the authored
strip and final surface; it does not attach strips to remote road decks.

## Verification

```sh
godot --headless --path . --script addons/tests/check_final_lane_overlays.gd
godot --headless --path . --script tools/check_lateral_joins.gd
godot --headless --path . --script tools/check_lateral_merge_angles.gd
godot --headless --path . --script tools/check_lateral_return_edits.gd
godot --path . --script tools/check_lateral_joins.gd -- --screenshots
```

Checks cover touching edges, gap fill, overlap area, interior/exterior sidewalks,
wall removal, authored-state preservation, warm cache parity, threaded output,
height/group/distance/angle rejection, smooth endpoint area, per-end controls,
custom profiles, short-host limits, source order and the editable example. The rendered
comparison is saved to `/tmp/roda-lateral-joins.png`, with an entry detail at
`/tmp/roda-lateral-join-detail.png`.

The angled-merge regression covers the shallow branch with intersection overrides,
deep partial overlap, asphalt/band overlap area, continuous entry sidewalks,
source order, reversed spline direction and warm/threaded parity. The parallel
endpoint checks use a fixed in-memory fixture so edits to the playground do not
change their expected geometry.

`check_lateral_return_edits.gd` repeatedly moves the second endpoint between a
parallel return and a transverse junction, then repeats the edits on the opposite
side. It checks independent contacts, cache/threaded parity, local junction fitting
and asphalt/sidewalk overlap. Add `-- --screenshots` with a real renderer to save
`/tmp/roda-return-junction.png` and `/tmp/roda-return-parallel.png`.
