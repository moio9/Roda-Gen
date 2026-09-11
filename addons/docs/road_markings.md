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

`tools/check_road_marking_cache.gd` compares actual surface arrays, order and
materials against the native row builder, including boundary edits and cache
lifecycle. The integrated editor workflow also checks local paint reuse,
Undo/Redo and exact full-reference rendering.

Open `addons/scenes/road_markings_demo.tscn` for a runnable example with banking,
a right-hand lane entering and leaving, eased transitions, double yellow center
lines, dashed lane separators, solid edge lines and white hatching.

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
chunks. Source-level incremental rebuilding and per-chunk paint reuse are not
implemented yet.

## Validation

```sh
godot --headless --path . --script tools/check_road_markings.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_markings.gd
```

The geometry check covers all five styles, exact empty dash/double gaps,
negative phase, left/right lane transitions, one-way lanes, width-only changes,
banking, mirrored/non-uniform transforms, intersection exclusions, threaded
generation, disabling, unchanged road geometry and both bake modes.
The worker test also disables threading while a job is pending, changes paint
settings, and checks that the old snapshot is joined/discarded before the new
synchronous generation is configured.

The demonstration's measured maximum triangle-conformity error was about
0.016 mm. The rendered entry/exit views contain visible center and lane/hatch
paint; disabling paint removes it, and the baked entry view has zero changed
pixels compared with procedural output. Images are saved as
`/tmp/roda-markings-{overview,entry,exit,off,baked}.png`.

On the current custom Godot build, the MSAA render check emits three
RenderingDevice RID warnings (Compute/Shader/Sampler) when exiting. Geometry
checks and image parity pass; the warnings have not been independently traced.
