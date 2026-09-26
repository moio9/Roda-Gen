# Prop rendering

`SplinePropArray3D > Rendering > Render Mode` provides two output modes:

- **Individual Nodes** (default): keeps the existing MeshInstance3D or Item Scene
  output. Forward+ can automatically instance objects that share the same mesh
  and material, provided the material is opaque or alpha-tested.
- **MultiMesh (Item Mesh Only)**: groups repeated Item Mesh props into
  MultiMeshInstance3D nodes. Set Item Mesh and leave Item Scene empty to use it.
  Placement, ranges, road alignment, ground snapping, randomization, material
  overrides and shadow settings are shared with the individual mode.

Item Scene always takes priority and remains individual, including its scripts,
children and collisions. Selecting MultiMesh with Item Scene assigned shows an
editor warning explaining this fallback. MultiMesh output adds no collisions;
the existing Item Mesh output also has none.

`SplinePropArray3D > Custom Transform` provides **Position** in metres,
**Rotation Degrees** and **Scale** with X/Y/Z fields. The scale's link icon
changes all three axes together. These offsets apply to every instance in its
local axes after spline alignment. Position/rotation default to zero and scale
to one; the revert arrows reset each field. Existing saved transforms are kept.
It works with Item Scene, Item Mesh and MultiMesh; regenerate props after editing
it when automatic regeneration is off.

For a continuous fence or wall, enable **Placement > Fit Segments To Path**.
Each module fits between two shared samples of the selected edge, so curves,
varying road widths and grades do not leave the longitudinal gaps produced by
fixed pivot spacing. Set **Road Network Source** to the road generator to use
its bank and height. **Spacing** is the sampling interval along the source path;
choose approximately the module's intended length. The last module is shortened
to the range end. Manual/span ranges and intersection clearance still apply.

**Follow Generated Road Edge** is on by default for connected edge segments.
With Road Network Source and Edge Uses Total Road Width, it follows the outer
boundary of the final welded road, including lateral joins, and keeps the
module's width outside that boundary. Outward Offset then adds clearance from
the road to the inner face of the model. Separate parallel roads and bridges
at another height do not move the fence. If a rigid segment would cross the
road at a sharp turn or junction, that segment is omitted to leave the opening
clear. The fence updates after the road regenerates, also at runtime; in the
editor automatic updates still honor Auto Regenerate In Editor. Disable Follow
Generated Road Edge to use the authored path edge and pivot-based offsets.

Module length is measured from its mesh vertices after **Custom Transform**
rotation and scale, including meshes under an Item Scene's child transforms.
The resulting length axis must be local Z; use Rotation Degrees for models
authored along X. Position offsets move the shared edge samples. Fitting adjusts
only longitudinal scale and preserves the source scene's children and collisions.
It connects rigid modules; it does not bend or weld their geometry, so thick
modules can still show corner seams at sharp turns. Decorative overhangs count
towards the measured length.

Independent props aligned to the path use local `-Z` as forward and a proper
rotation basis; alignment no longer reflects the model. An intentional mirror
can still be authored through the custom scale. Existing assets that compensated
for the old reflection may need their custom rotation/scale adjusted.

Connected segments always align to their endpoints, ignore randomization and
bypass incremental placement/output reuse. Item Mesh supports either rendering
mode; Item Scene keeps individual nodes. Ordinary independent props retain their
existing placement behavior when the option is off.

`Multimesh Chunk Size` is the side length of world-space cells, in metres
(default 100). Each source path gets a batch per occupied cell. Visibility is
evaluated per batch, not per prop. Smaller cells allow finer culling but create
more batches. Bounds include each mesh's dimensions, rotation and scale.

Switch modes and press **Regenerate Props** when automatic regeneration is off.
The existing Clear Generated, parent output and scene persistence options work
in both modes.

MultiMesh can reduce node and rendering submission overhead, but is not a
guaranteed draw-call or FPS improvement over Forward+ automatic instancing.
Compare the same scene and camera with both modes: draw calls, CPU/GPU frame
time and visible geometry. Multiple surfaces, shadows and rendering passes can
still require additional draws. Shader-driven vertex displacement may need
larger bounds than the source mesh provides.

See Godot's [automatic instancing documentation](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html#use-automatic-instancing)
and [MultiMesh documentation](https://docs.godotengine.org/en/stable/classes/class_multimesh.html).

Run the focused check with a real renderer (the headless dummy renderer does
not retain MultiMesh transforms):

```sh
godot --path . --rendering-method forward_plus --script tools/check_prop_rendering.gd
```

The check compares transforms, bounds, rendered pixels, output cleanup and scene
collision preservation. It prints draw-call counts for the same camera in both
modes and saves comparison images to `/tmp/roda-props-individual.png` and
`/tmp/roda-props-multimesh.png`.

The latest RX 6800 XT / custom Godot 4.7.2 check renders 148 placements in 11
MultiMesh batches with zero changed pixels. Individual uses 2 draws and MultiMesh
11 in this camera/setup; this is a concrete case where batching does not reduce
draw calls. The fixture includes a directional light for the custom renderer.

## Optional source placement reuse

Set **Road Network Source** to a `RoadNetworkCreator3D` with **Incremental
Generation Enabled** to reuse unchanged mesh-prop placements per source path
and in blocks of 32 candidate spacing steps inside edited paths.
This is independent of render mode. Compatible native output now also retains
unchanged MeshInstance3D nodes and MultiMesh batches/resources; changed transforms,
materials, shadows and batch buffers are updated, and obsolete output is removed.
Shared meshes, parent output and scene ownership are preserved.

Exact incoming/outgoing RNG state keeps later paths consistent when earlier
paths or blocks change length or reject different candidates. Native float64
curve samples, banking, lane transitions, span/manual ranges and endpoint
rejections are dependencies. Mixed reused/rebuilt blocks feed the same MultiMesh
cells, not one rendering batch per source block. Item Scene, randomized seeds
and custom scripts retain the uncached workflow.

Ground-snapped Item Mesh props can also reuse placements with the built-in
`TerrainTopologyBuilder3D`, while it is idle and has no active height modifiers.
Every consumed terrain hit is checked against the current provider before
replay, including missing hits and rejected slopes. Blocks carry each side's
last valid height as well as RNG state, preserving **Clamp to Last Valid** across
block boundaries. This does not require the terrain's own source-cache option.
Unknown/custom terrain providers retain their full query lifecycle. Repeated
pure queries within one build share at most 16,384 results; none are kept as
valid terrain samples across builds.

When a provider exposes `is_terrain_generation_pending()` and is busy, an
explicit prop rebuild waits without deleting existing nodes, collisions or
MultiMesh batches. It retries the latest configuration automatically once idle.
The built-in terrain's `terrain_generation_completed` signal also schedules
terrain-only updates at runtime, and in the editor when automatic regeneration
is enabled. An explicitly deferred rebuild still finishes with editor automatic
regeneration off. **Clear Generated** cancels the request and disconnects the
completion listener until the next explicit rebuild.

Native output retention requires compatible built-in source paths with distinct
names and the same
placement-cache eligibility described above. Item Scene, custom source callbacks
and randomized builds keep the original create/remove lifecycle. Changed native
nodes can be updated without detaching them from the scene. A MultiMesh resource
is retained only when its ordered transforms, mesh bounds and live buffer/state
still match; material/shadow-only changes do not rebuild its buffer. Native
property snapshots, shader-property schemas and metadata checks detect manual
changes to generated output. Such nodes are replaced rather than preserving
stale visibility, transforms or attached scripts/children. Manual buffer changes
rebuild the affected MultiMesh resource.

Only the current output's identities/snapshots are retained, with weak references
to nodes. Removed/replaced paths, output-parent changes and manual clearing release
obsolete entries. Cleanup of retained parent output also handles generator
renaming/reparenting using its previously recorded ownership. Persist Generated
in Scene updates ownership on retained nodes; disabling it removes ownership
instead of silently keeping those nodes in later source saves.

Inspect `get_placement_rebuild_stats()` for path/block/candidate/placement counts,
actual placement sampling, native dependency and endpoint checks, and bypass
reasons. `ground_queries_checked` counts replay validation, `ground_queries_sampled`
counts scatter-loop ground samples, `ground_provider_queries` counts real provider
calls, and `ground_results_reused` counts same-build memo hits. While
`pending_terrain` is true, other counters describe the last completed prop build.
`output_reuse_enabled` distinguishes native reconciliation from lifecycle fallback;
`output_nodes_reused`, `output_nodes_updated` and `output_nodes_created` count
unchanged, updated-in-place and new native nodes. `output_nodes_removed` counts
obsolete/replaced nodes removed during reconciliation, not wholesale root cleanup.
`output_buffers_reused/rebuilt` counts MultiMesh resource work. These output
counters do not count fallback Item Scene creation. `output_validate_ms` measures
live-state validation and obsolete-node removal; `output_commit_ms` measures
creation, updates, ordering and the root snapshot. Neither includes placement or
spec collection. State validation itself has a cost: retaining nodes is not a
guaranteed regeneration-time improvement.

Unchanged entries retain their existing snapshots. Native MeshInstance3D state
uses typed getters only when its complete stored-property schema exactly matches
the supported schema; extra surfaces, shader parameters or engine-added fields
use reflection. Schema revisions are shared per class. Transform-only updates
refresh only transform fields after full live-state validation. A separate
195-check test compares the fast reader and mutations against full reflection:

```sh
godot --headless --path . --script tools/check_prop_state_reader.gd
```
For the full-reference geometry/resource/GPU comparison, run:

```sh
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/check_prop_source_cache.gd
godot --headless --path . --script tools/check_ground_prop_cache.gd
godot --headless --path . --script tools/check_prop_terrain_lifecycle.gd
godot --path . --rendering-method forward_plus --script tools/check_prop_output_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_ground_prop_cache.gd
```

The check passes 179 assertions in Forward+ (169 headless), including mixed
within-path edits, fractional spacing/large jitter,
range/endpoint RNG propagation, lane/tilt changes and total regeneration timing.
Headless execution also tests ordinary nodes but skips GPU MultiMesh transform readback. See
`source_regeneration.md` for the combined road/terrain/props image comparison.
The ground suite adds 85 checks using actual terrain workers and collidable
scene props; 31 deterministic contract checks cover pending-provider transitions.
The ground Forward+ edited/full comparison has 0 changed pixels.
The native-output suite passes 249 checks in Forward+ (182 headless), including
actual node/resource identities, mixed cell updates, manual buffer/shader changes,
path replacement, container-state reset, duplicate-name fallback, parent ordering
and scripted-scene ready/exit callbacks. It also checks exact cached snapshots
after transform-only updates, renamed nodes, external scene paths and queued
deletions (including replacement survival on the next frame).
The real editor adds 31 ownership, source-save/reload and deferred-regeneration
checks. It saves only temporary test files:

```sh
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-prop-output-tests
```
