# Current improvement requirements audit

This checks the original eight-item scope in [improvement_work.md](improvement_work.md)
against the current working tree. Earlier implementation notes are chronological
evidence, not a current feature inventory. **All eight requirements passed the
final working-tree audit on 2026-09-12**, with the opt-in scope and limitations below.

| Requirement | Current status | Evidence inspected/rerun |
| --- | --- | --- |
| Local rebuilding of road, junctions and dependent terrain/props | Implemented and verified in opt-in modes | Source/path assembly, paint blocks, lane-overlay rows/normals, partitions, junction geometry, terrain groups/collars and prop placements reuse unchanged inputs. The actual editor workflow with per-lane materials passes 50 geometry, identity and edit/Undo/Redo checks with zero full-reference pixel differences. Its external circle ties now resolve locally; unsupported cases retain native fallback. Distinct-edit timings and their limitations are recorded in source_regeneration.md. |
| Coherent editor Undo/Redo | Implemented; fresh check passed | `check_road_editor_history.gd` uses actual Inspector edit signals and registered gizmo callbacks in `road_editing_demo.tscn`; verifies original point selection, lane conversion, easing-resource identity, merged edits, axis movement/rotation and cancellation. `ROAD_EDITOR_HISTORY_OK`. |
| Optional MultiMesh alongside existing Forward+ behavior | Implemented; fresh real-renderer check passed | `check_prop_rendering.gd`: 148 placements, 11 spatial batches, identical transforms/bounds and 0 changed pixels; Individual remains default. Item Scene retains scripts/collisions. In this fixture Individual uses 2 draws, MultiMesh 11. |
| Runtime chunks and script-free bake | Implemented; fresh check passed | `check_road_runtime_output.gd -- --incremental`: complete/chunk geometry and collision parity, 19 of 25 chunks retained after edit, material-only reuse, mode cleanup, stale/active-worker rejection, saved bake reload and native physics-hit parity. Scope is this road and its preset-owned barriers, not a whole-map exporter. |
| Banked road markings with lane transitions | Implemented; fresh check passed | `check_road_markings.gd`: all five styles, dash/double gaps, hatching on both sides, one-way lanes, width-only changes, banking, transformed sources, junction exclusions, worker cancellation and bake modes. Maximum conformity error 0.00001525878906 m in this fixture. Bounded 32-pair paint reuse now also matches native arrays/materials and actual editor rendering. |
| Mountain/urban/highway presets, editable after application | Implemented; fresh checks passed | `check_road_presets.gd` and actual `--roda-preset-tests` editor run: all built-ins/custom resource, independent materials/curves, curve preservation, editable barriers, openings/collisions, bake, one-action history, Node identity and temporary source save/reload. |
| Cohesive generator components without scene/API breakage | Implemented; fresh compatibility checks passed | Existing coordinator delegates sampling, mesh/normal construction, junctions, terrain, markings and output. `check_road_mesh_baseline.gd` matches all six original hashes. `check_lane_profile.gd` preserves legacy/asymmetric lanes and banked frames. |
| README Quick Start references included resources | Updated and checked | All 13 fully qualified addon file paths in the README exist; the plugin is enabled in `project.godot`. The incremental overview now includes implemented separate terrain and ground-snapped props instead of saying they are absent. |

Additional compatibility gates:

- `check_span_handle_compatibility.gd` adds 56 passing checks for prop/deformer
  handles: mirrored/nonuniform world transforms, offset edits, crossed ranges,
  repeated synchronization without drift, projection-noise tolerance, disabled
  and missing paths, explicit/remainder spans, hidden handles and real deformed
  mesh/collision output. These invoke native callbacks directly; they do not
  claim physical mouse replay or editor-history coverage for those handles.
- `check_ground_prop_cache.gd` freshly passes 85 checks, including real terrain
  workers and grounded placement/cache lifecycle behavior.
- The latest integrated editor run uses threaded roads, reversed generator order
  and actual MultiMesh buffers plus per-lane materials. It changes 459 visible pixels on edit and matches
  the independent full-reference image exactly. No manual regeneration occurs
  between edit, Undo and Redo.
- The real-renderer prop fixture now includes a directional light, removing its
  missing-light SSS diagnostic on the custom engine. Geometry and image parity
  are unchanged. This is a test-scene correction, not an engine renderer fix.

## Local scope and completion audit

The requirement is reuse of unaffected construction with full-reference parity;
it does not mean that all dependency inspection or triangle traversal can vanish.
The common editor case now resolves external near-cocircular ties by bounded
cavity expansion. It retains 2,902 triangles and reconstructs 1,252, with exact
independent full-reference rendering. A separate five-edit fixture also matches
the complete unfiltered native triangle set and actual mesh/collision output.
Unsupported geometry, expansion limits and custom modifiers/scripts retain
documented native fallback behavior. The first tied edit is locally constructed
but measured slower than native full triangulation; the experimental option
remains disabled by default. See the detailed timing limits in source_regeneration.md.

The eight explicit requirements and compatibility gates were checked together
against the final tree, not inferred from the earlier seven-item status.
No required construction feature remains missing. Global dependency inspection
and output concatenation remain necessary; the implemented feature does not
promise constant-radius work, zero full fallbacks or universal speedups.

Paint construction now retains unchanged blocks under the existing road opt-in.
The combined paint mesh is still recreated/uploaded: this is source-work reuse,
not retained paint output chunks or a draw-call optimization. Exact ordered
exclusions can invalidate all paint blocks on an affected path.

Lane overlays now retain 64-row construction blocks and independently cached
indexed normals. Actual arrays/materials match a frozen native row-loop reference
(91 checks). The editor junction edit retains 18 blocks / 858 rows, rebuilding
6 / 294. Final index concatenation and combined mesh publication still run;
this is not retained per-lane output chunks or a draw-call optimization.

Performance claims remain limited to the specific measurements documented in
[source_regeneration.md](source_regeneration.md), not the user's consuming game
map. Non-isolated observations are explicitly labeled. Timings printed by the
parallel final correctness checks were not used as performance evidence.

Final refresh logs are `/tmp/roda-final-{presets,markings,spans,ground-props,runtime,baseline,lanes,markings-render}.log`,
plus `/tmp/roda-audit-{editor-history,preset-history,prop-rendering}.log`.
The final integrated editor evidence is `/tmp/roda-overlay-editor.log` (50 checks);
source/cavity/overlay regression and paired measurement logs are identified in
the corresponding source-regeneration sections. Scripts above are the durable
reproduction entry points. Editor history uses `road_editing_demo.tscn`; preset
and integrated-workflow editor checks use `road_markings_demo.tscn`. Temporary
save/bake files are test artifacts, not edits to the included source scenes.

Final visual inspection covered both lane-entry/exit paint images. The real
marking renderer reports zero changed pixels between live and saved/reloaded
baked output. The custom Godot 4.7.2 engine still prints a missing debug-setting
warning and three renderer RID warnings on that MSAA fixture's shutdown; tests
complete successfully with no script errors. This audit does not claim those
engine diagnostics were fixed. The other open Godot project was left untouched.

Existing exported road/profile property names remain available; the inspected
export diff adds settings and extends one bank-probe range without removing a
legacy setting. Six unchanged native geometry hashes and the lane/span/editor
tests supply behavioral compatibility evidence. README's 13 referenced addon
paths exist and the editor plugin is enabled. No commit or deployment is part
of this local implementation handoff.
