# Procedural road markings

Enable **RoadNetworkCreator3D > Road Markings > Enabled**, then regenerate the
road. Existing scenes keep markings disabled by default.

With the road's **Incremental Generation** enabled, unchanged paint construction
is reused in blocks of 32 row pairs. Exact welded vertices, lane layout, distance,
geometry settings and ordered junction exclusions are checked each generation.
Colors and material overrides are applied separately without rebuilding geometry.
The combined mesh is still recreated/uploaded; this does not reduce draw calls.
Retention is bounded to 4,096 blocks and an estimated 32 MiB payload, with native
reconstruction on capacity bypass. Disabling markings/incremental generation or
clearing the road source cache releases retained geometry.

Lane appearance rules invalidate only the paint blocks intersecting their
distance ranges. Moving or deleting a range also invalidates its old blocks.
Unrelated paths and blocks retain their paint. Rule-free rows use the native
construction path, including after the last local override is removed.

`tools/check_road_marking_cache.gd` compares actual surface arrays, order and
materials against the native row builder, including boundary edits and cache
lifecycle. The integrated editor workflow also checks local paint reuse,
Undo/Redo and exact full-reference rendering.

Open `addons/scenes/road_markings_demo.tscn` for a runnable example with banking,
a right-hand lane entering and leaving, eased transitions, double yellow center
lines, dashed lane separators, solid edge lines and white hatching.

For a stopping bay with its own surface material and optional transverse lines,
open `addons/scenes/lane_appearance_demo.tscn`.

## Per-lane appearance and stopping bays

On the **SplinePathProfile3D**, open **Road > Lane Appearance > Lane Appearance
Overrides**, add an array element, and create a **RoadLaneAppearance** resource.
Enable the path's **Lane Profile Enabled** to identify individual lanes in a
multi-lane road. These settings paint existing lanes; they do not add road width.

- **Side** selects left/right in the source spline's authored direction.
  **Lane** counts from the center outward, starting at **1**. A typical added
  bay on a one-lane side is lane **2**. This resource uses lane numbers; the
  network's material arrays still use zero-based array indices.
- **Start Offset / End Offset** limit the rule in metres along that path.
  End **0** means the path's end. Both default to 0 for the whole path; the
  selected lane is painted only where it actually exists. Bounds can fall
  between road samples. Disable **Enabled** to temporarily bypass a rule.
- **Inner Line Style / Outer Line Style** select Inherit, Off, Solid, Dashed,
  Double Solid or Double Dashed. Inner faces the road center; Outer controls
  the next separator or, when this is the outermost lane, the road edge.
  **Inherit** retains the normal network style. Dash length, phase, width,
  colors and paint material continue to use the network's marking settings.
- **Transition Hatching** can inherit, disable or enable diagonal paint on
  this lane's entry/exit tapers. It does not fill the entire lane with hatching.
- **Stop Line At Start / End** independently add a transverse stripe inside
  the selected interval and lane. **Stop Line Width** is its length along the
  spline. Put these bounds where the bay has reached the desired width; no
  stripe appears where the selected lane has zero width. The line uses the
  network's lane/edge paint color or material. This does not add STOP lettering.
- **Surface Material** optionally replaces the asphalt appearance on just this
  lane and interval. Empty inherits the road's per-lane/default material.

For example, select Right / Lane 2, choose Dashed inside and Solid outside,
disable transition hatching, and assign a different asphalt material. Add a
second resource on the same lane with Start 22 / End 62 and the stop-line
checkboxes enabled to draw transverse lines across the full-width bay.

Overlapping resources are resolved from last to first **per explicit style or
material**; Inherit/empty preserves earlier settings. A shared separator is
drawn once: the outer lane's Inner setting takes precedence over its neighbour's
Outer setting. For the central divider, right lane 1's Inner setting takes
precedence over left lane 1's Inner setting. One-way/junction suppression still
applies. Stop-line requests are combined; overlapping bars on the same lane are
merged rather than stacked.

**Road Markings > Enabled** on the network is still required for paint.
Appearance edits follow its automatic regeneration setting and do not require
**Apply Lane Changes**; that button applies lane geometry edits. If automatic
regeneration is disabled, regenerate the road explicitly. Rules are local to
their source path and are included in both runtime bake modes. An empty array
preserves existing road appearance.

### Editing ranges in the viewport

With **Show Lane Appearance Handles** enabled on the path, each appearance
resource gets a selectable range under `__LaneAppearanceHandles`. Select its
cyan **StartHandle** or orange **EndHandle** and move it along the lane. Selecting
the path, the range, a handle or the resource in the Inspector highlights the
affected lane interval. The handle Inspector also exposes **Offset** in metres.

The resource remains the authoritative storage. Numeric edits reposition the
handles, native transform Undo/Redo restores the same resource after selection
changes, and moving End to the source end restores the `End Offset = 0`
convention. Handles are editor helpers and are removed at runtime. Disable
**Show Lane Appearance Handles** to hide them without disabling the appearance.

### Appearance-only regeneration

Changing paint styles, colors, ranges or per-lane materials on a completed road
reuses its final asphalt triangles, lane rows and junction cuts. The main road
mesh, collision and final-road surface revision stay unchanged, so dependent
terrain and fences are not invalidated by these edits. Material-only rules do
not rebuild paint; paint-only edits do not rebuild the lane material overlays.
This also supports enabling/disabling markings on an already generated road.

Geometry, output configuration and junction-clearance changes still rebuild
the road. Junction clearance participates in lateral joining and preset barrier
exclusions. A pending worker must be cancelled/joined before the newest state
is generated. Explicit unchanged **Regenerate**, or clearing the source cache,
still permits a full rebuild. `get_appearance_update_stats()` reports which
route was used and the time spent on an appearance update.

Local material overlays sample only lanes with an assigned material and the
source segments intersecting their intervals. Original bracketing samples are
retained so clipping, UVs, bank and first-source ownership remain consistent.

## Controls

- **Center Style**, **Lane Style** and **Edge Style** independently support Off,
  Solid, Dashed, Double Solid and Double Dashed. A directional one-way profile
  omits the opposing center divider.
- **Line Width** is the width of each stripe. **Double Gap** is the clear space
  between a double line's stripes, not their center-to-center distance.
- **Dash Length/Gap/Offset** use distance along each source spline. Dash phase
  continues across sample rows, not restarted per triangle. Negative offsets
  are supported.
- **Edge Inset** keeps edge paint inside the lane surface. Separators follow
  the per-point lane width and are clipped before the outer edge stripe.
- **Hatching Enabled** fills the extra lane area during entry/exit transitions,
  independently on each side. Width-only changes with the same lane counts do
  not produce hatching. Spacing is measured along the spline; hatch width and
  angle control each diagonal stripe. This is a configurable visual treatment,
  not an assertion of compliance with a country's road-marking standards.
- Center, lane/edge and hatch colors are separate. **Material Override** replaces
  their generated paint materials with one custom material. UV.x is signed
  lateral distance; UV.y is distance along the source spline.
- **Surface Lift** offsets paint above the road triangles. If using raised
  per-lane material overlays, set it above the overlay lift and inspect the
  result; finer road sampling also reduces differences between those overlays
  and the triangulated road.
- **Junction Clearance** adds to the socket-width/strip-length clearance around
  welded connections. Ordinary line patterns stop there; intersection-specific
  arrows, crosswalks and connecting turn lanes are not generated.

## Surface alignment

The builder consumes the generator's sampled lane extents and lane-layout
snapshot. It clips every paint polygon to the actual road triangles in spline
distance/lateral coordinates, maps the clipped polygons to those triangles,
then applies the normal lift. Banking, asymmetric lane growth, varying lane
width and the generated road's sampling therefore affect the same surface.

Paint is stored in `GeneratedRoadMarkings`, with at most three material surfaces.
It has no collision or cast shadows and does not modify the road's main mesh.
Changing paint settings follows the normal road regeneration workflow, including
the profile's explicit **Apply Lane Changes** behavior. Threaded finalization
uses the captured road rows before assigning the finished paint.

**Bake Runtime Scene** includes the paint in both Single Mesh and Spatial Chunks
modes. Paint itself remains a separate mesh rather than being split into spatial
chunks. Incremental reuse happens in source-row blocks; the combined paint mesh
is still uploaded as one output.

## Validation

```sh
godot --headless --path . --script tools/check_road_markings.gd
godot --headless --path . --script addons/tests/check_lane_appearance.gd
godot --headless --path . --script addons/tests/check_appearance_optimization.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script addons/tests/render_lane_appearance.gd
godot --editor --path . addons/scenes/lane_appearance_demo.tscn -- --roda-lane-appearance-tests
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_markings.gd
```

The geometry check covers all five styles, exact empty dash/double gaps,
negative phase, left/right lane transitions, one-way lanes, width-only changes,
banking, mirrored/non-uniform transforms, intersection exclusions, threaded
generation, disabling, unchanged road geometry and both bake modes.
The worker test also disables threading while a job is pending, changes paint
settings, and checks that the old snapshot is joined/discarded before the new
synchronous generation is configured.

The lane-appearance check covers exact sub-row bounds, dash phase, shared-line
precedence, overlapping stop bars, path isolation, material ranges with zero
texture scale, worker snapshots, hatching overrides, serialization and chunked
baking. The editor check edits the native Inspector control and verifies automatic
regeneration, Undo/Redo and idle stability. The Forward+ check compares restored
and baked output against the original; the stopping-bay example had zero changed
pixels in both comparisons.

The demonstration's measured maximum triangle-conformity error was about
0.016 mm. The rendered entry/exit views contain visible center and lane/hatch
paint; disabling paint removes it, and the baked entry view has zero changed
pixels compared with procedural output. Images are saved as
`/tmp/roda-markings-{overview,entry,exit,off,baked}.png`.

On the current custom Godot build, the MSAA render check emits three
RenderingDevice RID warnings (Compute/Shader/Sampler) when exiting. Geometry
checks and image parity pass; the warnings have not been independently traced.
