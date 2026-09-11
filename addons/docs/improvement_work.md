# Roda-Gen workflow improvements

Implementation scope agreed in the project discussion:

- [x] Local rebuilding: changing a spline control point rebuilds affected road
  segments, nearby junctions and dependent terrain/props; unchanged portions are
  reused. Compare geometry against full generation and measure regeneration time.
- [x] Editor Undo/Redo: curve handles, width/lane values and transitions restore
  their actual source data in one coherent operation.
- [x] Optional MultiMesh props: individual nodes remain the default. Forward+
  automatic instancing remains useful; MultiMesh is an explicit alternative.
- [x] Runtime output: spatially divided output and a bake action that saves final
  geometry/collisions without requiring procedural regeneration in the game.
- [x] Road markings: solid/dashed/double lines and hatching that follow banking
  and lane entry/exit transitions.
- [x] Reusable presets: mountain, urban and highway road settings, materials and
  barriers, with local customization after application.
- [x] Cohesive generator components: road geometry, junctions and terrain fill,
  coordinated through the existing RoadNetworkCreator3D node/API.
- [x] Update the README Quick Start to use files actually included in the addon.

Compatibility gates: preserve existing scene properties, centerline and asymmetric
lane widths, banked surface frames, span handles, explicit terrain-cache
invalidation, optional MultiMesh mode, and generated-node cleanup/ownership.

Validation must include full-versus-incremental mesh/collision comparison, actual
editor undo/redo and rendered images of markings and lane transitions. Test scene
results are not a substitute for claiming performance on a consuming game map.

All eight requirements passed the final working-tree audit on 2026-09-12.
Incremental/local modes remain optional, with documented native fallbacks and
performance tradeoffs; this does not claim fixed-radius updates or faster
generation for every scene. No consuming-game map benchmark is claimed.
For requirement-by-requirement evidence and supported limits, see
[improvement_audit.md](improvement_audit.md).

## Chronological implementation evidence

The notes below describe successive checkpoints. Earlier limitations may have
been addressed in later entries; they are not the current feature inventory.

- Components extracted with byte-identical mesh arrays in all six baseline
  configurations: `tools/check_road_mesh_baseline.gd` and
  `tools/fixtures/road_mesh_baseline.json`. The coordinator went from 9,166 lines
  to about 3,600, retaining its serialized settings and existing API.
- Editor history integration is implemented. `ROAD_EDITOR_HISTORY_OK` verifies
  native Inspector width/tilt/lanes/transition fields, selection changes, merged
  slider edits, translation/rotation on all axes, cancellation and multi-point
  undo. Redo preserves the Curve identities created by first-time lane enable,
  including their resource history. The real Forward+ editor shows 7,907 changed
  pixels after widening, with Undo/Redo each matching their reference exactly.
  Controls use native edit signals, not physical mouse replay. See
  `editor_workflow.md`.
- Spatial output and a script-free road-node bake are implemented. The fixture
  preserves all 25 mesh/collision resources on unchanged regeneration; a local
  edit rebuilds 6 chunks and reuses 19. Complete-vs-chunk triangle attributes and
  collision faces match, including after saved-scene reload. Forward+ single,
  chunked and baked images have 0 changed pixels. Threaded output and real physics
  ray hits also match. The mirrored test fixture's source collision is one-sided
  from below; baking preserves that existing winding, not driving validation.
  See `runtime_output.md`.
- Local source rebuilding is partly implemented behind a default-off option.
  Unchanged road cross-sections and junction discovery queries skip construction;
  a local-edit fixture retained 267 rows and rebuilt 241. Full-reference mesh,
  collision and raw lane metadata comparisons pass, and actual Forward+ cached
  versus full images have 0 changed pixels. Global clustering, terrain
  boundary/domain construction and mesh finalization still run; fully local dependent
  terrain/props updates remain unfinished. See `source_regeneration.md`.
- Whole unchanged-path terrain strips now skip growth/smoothing/ring/skirt
  construction, including after a local edit elsewhere. Exact mesh and collision
  checks cover nearby blockers, base-road skirt patches, reorder, transforms,
  settings and threaded cancellation. Idle clearing releases storage immediately;
  active-worker clearing is deferred safely. Terrain winding is captured instead
  of rereading a mutable Inspector value during a job (reproduced before fixing).
- Compatible mesh props reuse whole-path placements and preserve the shared RNG
  sequence, while scene scripts/collisions and arbitrary ground providers retain
  the full workflow. A combined
  visible road/terrain/MultiMesh fixture skips all warm terrain/placement sampling
  and matches full reconstruction with 0 changed pixels, including after edits.
  Fully local separate/global terrain generation remains pending; the shared
  global fill now has partial source-stage reuse, described below.
- Edited road-side terrain strips now reuse growth searches, 32-row smoothing
  blocks, noisy ring rows, skirt drops and skirt columns. Incoming accepted
  widths, earlier edges/nearby triangles, per-pass halos, path-wide subdivisions
  and current skirt-center directions are explicit dependencies. Source values
  are cached; vertex/index buffers are still assembled in the original order.
  The new 64-check suite passes exact mesh/collision comparisons, and the six
  original baselines remain byte-identical. The Forward+ edited fixture reuses
  51 growth searches and 60 ring rows and has 0 changed pixels against full
  generation. Nested caches retain bounded entries across unchanged-path hits.
- Global Rectangle/Boolean fill now reuses polygon clipping/classification,
  offsets, root resampling/triangulation and height searches. Exact ordered cell
  revisions avoid rescanning point dependencies for each query. Nearest-search
  reuse preserves safe-distance stopping, domain expansion and source-order
  ties; exhausted old domains are not treated as safe prefixes. Immutable
  results, bounded native/coarse cache retention and worker cancellation are
  covered by the 216-check global terrain suite. Full-versus-local comparisons exercise
  all 24 algorithm/topology combinations, with actual emitted global triangles
  rather than fallback strips. Forward+ edits retain 237 polygons and rebuild
  35, with 0 changed pixels against full reconstruction in both algorithms.
  Distinct-edit total regeneration measures 272.324/186.874 ms full/local on the
  dense fixture, but 41.768/42.360 ms on the small one; this is not a universal
  speedup. Global domain/adaptive/index work remains open.
- Separate TerrainTopologyBuilder now has a default-off source cache for nearest
  road queries, heights, edge crossings and unchanged native Delaunay inputs.
  Exact ordered cell revisions preserve spatial stopping and road-profile data.
  Pending queries cannot mutate an active job's spatial context; restarts discard
  partially assembled meshes, and Clear Generated cancels queued restarts.
  Custom terrain subclasses and active modifiers keep their full workflow.
  The 137-check suite preserves the pre-change full mesh hash and compares real
  mesh/collision arrays. A local fixture reuses 3,754 nearest queries, 3,791
  heights and 433 crossing queries. Forward+ edited/full images differ by 0
  pixels; the distinct-edit total median is 459.721/445.190 ms full/local, so
  there is not yet a substantial end-to-end speedup on this fixture.
  Point enumeration, changed-set triangulation and final assembly remain open.
- Mesh props now also reuse 32-candidate blocks inside edited paths. Native
  geometry/profile support, float64 jitter, local effective ranges and endpoint
  rejection decisions are checked, with incoming/outgoing RNG carried across
  rebuilt, reused and empty blocks. Mixed blocks preserve individual node names
  and shared per-path MultiMesh cells. The suite passes 179 Forward+ assertions
  (169 headless), plus the 91-check road-source regression. The long-path position-edit fixture reuses
  256 props and rebuilds 582; a rendered edit reuses 64 and rebuilds 198 with
  0 pixel differences from full reconstruction. Arbitrary scene/provider scripts
  still retain the full workflow; built-in ground support is described below.
- Ground-snapped mesh props now reuse whole paths and 32-candidate blocks with
  the built-in idle terrain, validating every consumed current hit (including
  misses/rejected slopes) and carrying per-side last-valid heights and RNG.
  A transient bounded memo shares only same-build pure queries. Busy terrain
  defers prop generation without deleting existing nodes, scene collisions or
  batches, then automatically retries the latest requested configuration.
  Terrain-only completion also schedules dependent updates; manual prop clearing
  cancels pending requests and disconnects completion. The real-worker lifecycle
  suite passes 85 checks, including Item Scene collisions and changing the output
  parent while pending. The local fixture reuses 260 placements and rebuilds 368.
  Forward+ edited/full images differ by 0 pixels (73,495 pixels change after the
  edit), with 64 placements reused and 198 rebuilt in the rendered fixture.
  Unknown/modified terrain and Item Scene still use the original query lifecycle.
  A separate 31-check contract suite covers switching/freeing pending providers,
  stale completion signals, disabling snap, removing inputs and manual clearing.
- Terrain cache eviction no longer copies all retained keys to remove one
  oldest entry. The pressure fixture verifies 1,033 assertions at the real
  16,384-entry limit, preserving lookup refresh, eviction order and clearing.
  Isolated 512-entry pressure insertion dropped from 172.087 to 2.180 ms;
  topology nearest-hint pressure dropped from 167.957 to 0.591 ms. Actual
  128-query center/normal sampling under pressure dropped from 796.486 to
  68.210 ms with identical source work/reuse/eviction counters. These are
  focused measurements. A separate five-distinct-edit full-pipeline measurement
  (road + terrain + props) drops from 15,776.454 to 1,664.417 ms with road/prop
  reuse enabled. Turning road/prop reuse off measures 1,611.281 ms after the fix,
  with terrain source caching still enabled in both variants: this fixes the
  capacity slowdown but does not yet demonstrate a placement-reuse speedup.
- Native prop output now retains unchanged nodes and MultiMesh resources, updates
  changed output in place and removes obsolete entries before creating replacements.
  Exact live state/schema checks guard manual changes; weak references and old
  ownership metadata handle clearing, freed nodes and renamed parent output.
  The native-output suite passes 249 Forward+ checks (182 headless), including
  actual scripted-scene ready/exit callbacks and collision fallback. The real
  editor adds 31 persistence/save/reload and deferred-regeneration checks.
  A local fixture preserves 156 native nodes and updates 152 without new nodes;
  MultiMesh preserves 7 resources and rebuilds 8. The rendered ground scene
  preserves one batch/resource and updates three, with 0 changed pixels against
  full reconstruction. Validation overhead remains part of total regeneration
  time; retaining identities alone is not evidence of a speedup. The current
  Forward+ tilt fixture measures 13.865/8.545 ms full/local in MultiMesh mode
  and 20.227/18.637 ms for individual nodes. Shared schema revisions, retained
  unchanged snapshots and exact-schema native readers remove the earlier
  individual-node regression. A separate 195-check test compares every fast-reader
  property mutation against full reflection; other schemas retain generic checks.
- Junction geometry is now cached per ordered cluster using sparse source-vertex
  patches, blocked-side marks, composed remaps and fan centers/triangles. Current
  path/row/edge addresses replace stale global vertex indices. Changed preceding
  clusters invalidate overlapping support; removed clusters leave no old patches.
  The 164-check suite covers actual endpoint fans/pairs, nearby T junctions,
  whole-side midpoint candidates, reorder, global fallback and material routing,
  plus full mesh/collision parity. Forward+ edited/full images differ by 0 pixels;
  the edit itself changes 174 pixels while only one of two fans is rebuilt.
  See `source_regeneration.md` and `tools/check_road_junction_geometry_cache.gd`.
- Road markings are implemented with triangle-clipped paint, independent styles,
  left/right entry/exit hatching and welded-junction exclusions. Geometry checks
  cover banked/mirrored roads, width-only changes and empty dash/double gaps.
  Forward+ entry/exit captures show the paint, and the baked image is identical.
  See `road_markings.md` and `tools/check_road_markings.gd`.
- Pending threaded results now block reconfiguration even after their worker
  stops or threading is disabled. The marking test covers cancellation followed
  by synchronous regeneration with new settings.
- Presets are implemented as editable one-shot resources with independent
  materials/easing, optional layout/barrier preservation and junction-aware
  barrier spans. Headless generation/bake tests and real editor Undo/Redo plus
  source save/reload pass. Each Forward+ preset/bake comparison has 0 changed
  pixels. Bake also refuses barriers whose lane layout is still deferred; the
  regression was reproduced before the guard and passes after it.
  See `road_presets.md` and `tools/check_road_presets.gd`.
- Complete local rebuilding, including separate/global terrain and final output
  assembly, remains pending; the first checklist item is deliberately still open.

## Remaining local-generation boundaries

- A test-only ordered Delaunay replay prototype passes 478 isolated native-index
  checks and 8 comparisons on actual terrain point sets. It fails the timing gate
  (79.249 ms replay versus 0.887 ms native on the measured small terrain), so it
  is kept under `tools/fixtures`, not integrated into the addon. Changed-point
  triangulation remains open; whole-suffix replay is not a viable optimization.
- A second, native local-cavity prototype passes 634 synthetic checks and 9 on
  the small actual-terrain fixture. At 3,000 synthetic points it measures
  7.103 ms local versus 20.784 ms full, but the small terrain remains slower.
  The uncentered ten-road gate fails because every edit falls back; its native reference
  has overlapping triangles. A seven-point standalone reproducer preserves
  this defect. Ordered replay remains outside the addon; geometric degeneracy,
  final mesh/collision ordering and real-terrain performance are not solved.
- Optional centered Delaunay calculations are integrated into the separate
  terrain builder, default off. Original sample coordinates feed final geometry;
  only the triangulation calculation is centered. The seven-point overlap
  reproducer then has nine triangles and zero measured overlap. Fifteen focused
  checks cover native default parity, input preservation, safe fallback, scene
  serialization and worker use. Centered cached/full Forward+ output differs by
  zero pixels. The centered ten-road cavity prototype now passes all six local
  edits, but its 50.700 ms local time is about equal to 50.613 ms native full.
  The numerical option is integrated. Local cavity integration is now opt-in,
  as described below; final mesh/collision resource retention is now available
  through a separate optional spatial-output mode, with global staging still open.
- `local_triangulation_enabled` is integrated for the separate terrain builder,
  requiring incremental source generation. The helper cannot perform native
  full fallback itself; accepted workers seed value-only, bounded support.
  Deterministic triangle ordering fixes accumulation-order normal differences.
  Actual small and ten-road fixtures preserve exact oriented positions, UVs,
  normals and concave collision triangles against uncached generation. The
  successful local Forward+ fixture has zero changed pixels against its full
  reference. Some markings-demo edits still fall back for degenerate triangles.
  Point enumeration, index ordering and final mesh/collision construction remain
  global, so this does not close the first checklist item. The initial ten-road
  total was approximately 2.65 s with reuse versus 2.35 s full. The follow-up
  below improves that fixture; local triangulation remains experimental/default
  off. Reused triangle counts alone are not a claim of faster total generation.
- Stage profiling identified repeated collar height sampling and cyclic source
  cache eviction as major topology costs. A per-call native-only collar memo
  preserves legacy mesh/collision and arbitrary callback dispatch. Topology keys
  use cheaper hash buckets with exact-byte collision validation, and topology
  allows 65,536 small records within the unchanged 64 MiB serialized-payload cap.
  The ten-road fixture now retains its source working set and measures about
  1.19 s local versus 1.48 s full (roughly 20% faster by median). This does not
  close global final-output assembly, prove gains on a game map or make the
  local option faster on every small fixture. Independent full output checks
  also cover consecutive edits without clearing local history.
- Global Rectangle/Boolean/Adaptive Delaunay domain construction and adaptive
  edge conformity still need topology work. Separate TerrainTopologyBuilder
  needs local point enumeration, broader changed-set triangulation coverage,
  collar/partition assembly and modifier dependency contracts. Both
  generators now reuse source queries, but complete buffer/index staging remains
  global. Separate topology Spatial Chunks retain unchanged final resources.
- Optional separate topology Spatial Chunks now retain real native mesh/collision
  resources, with exact array/state validation and independent collision reuse.
  The three-road edit retains 24/40 meshes and 26/40 shapes; the ten-road edit
  combines a successful local triangulation with 87/105 meshes and 91/105 shapes
  retained. Exact oriented mesh/face comparisons, zero-pixel opaque Forward+
  comparison, live Jolt ray checks and actual editor save/reload pass. Single
  Mesh remains default: the checked view has 35 draw calls chunked versus 2
  single. Resource retention is implemented, but source assembly and changed-output
  partition traversal remain global, so the first item stays open.
- Spatial output now also retains native normals outside complete dirty-vertex
  neighbourhoods. It preserves global contribution order and falls back for
  reordered or broad changes. The ten-road edit retains 56,465 emitted vertex
  normals and rebuilds 10,843; warm output skips normal work and partitioning.
  The 96-check normal suite and exact renderer/editor tests pass. Warm publication
  improves (56.937 versus 80.276 ms), while the checked edit's normal selection and
  validation adds about 19 ms. This localizes native normal work but does not
  remove global changed-input partition/dependency scans or close the first item.
- Ground-snapped props now reuse placement calculations, but current hits are
  still queried/revalidated; terrain-region revision tokens would avoid that
  repeated work. Compatible native nodes/batches now survive successful rebuilds;
  their live-state validation and global output-order reconciliation still run.
  Individual-node retention now beats reconstruction on the measured fixture,
  but validation still has a measurable cost and no universal speedup is claimed.
  Arbitrary terrain modifiers, providers and deformers need explicit dependency
  contracts before their work/side effects can safely be skipped.
- Grouped topology filtering/height fitting is now connected for native incremental
  terrain in both output modes. Spatial groups preserve global triangle order and
  the per-frame candidate budget; exact settings/edge-height/spatial dependencies
  guard reuse, including empty cells and point/query hits. Local ten-road edits
  retain 8,175 candidates and rebuild about 1,570. An isolated five-edit comparison
  with independent source-cached builders measures 879.161 ms grouped versus
  1,312.613 ms without grouping; warm regeneration is 547.070/1,079.575 ms.
  Mesh/collision and rejection counters match exactly. The 29-check group suite
  exercises real 4,096-entry/64-MiB pressure; 31 dependency, 137 existing source,
  52 Forward+ and 100 actual editor checks pass. The rendered local/full images
  differ by zero pixels. Global point/triangle traversal and modifier
  contracts remain open, and the small source fixture still has no total speedup.
- Native collar geometry now reuses eight-row-pair blocks with exact row/settings,
  nearest-road support and edge-height dependencies, including memo hits and
  signed zero. The ten-road edit retains 36/40 blocks and 11,951 collar triangles.
  Five distinct edits measure 665.474 ms with collar retention versus 911.326 ms
  with full collar construction, with all other caches identical; unchanged
  regeneration measures 290.281/546.082 ms. Mesh/collision and rejection counters
  match exactly. The 24-check helper suite covers real capacity/eviction limits,
  while 46 collar legacy-parity and 137 source checks pass. Forward+ passes 54
  checks with zero pixel differences; the real editor passes 103 and consecutive
  edits/worker lifecycle pass 49. This removes repeated
  collar construction, not global vertex emission or point/index staging, so the
  first checklist item remains open.
- Near-ring and far-grid road-mask checks now reuse blocks of up to 64 candidate
  points. Exact spatial support protects incoming/moved/wider roads; current
  ordered deduplication and budget checks still own final point indices. The
  ten-road edit reuses 3,488 candidates and reevaluates 832. With other caches
  identical, five-edit total medians are 580.150 ms cached versus 657.326 ms native
  masks; the point stage itself drops from about 109 to 32 ms. The 78-check suite
  covers budget cutoffs, order, spatial changes, hash collisions and real capacity
  pressure; all 137 source regressions still pass. Forward+ passes 56 checks with
  zero pixel differences, the actual editor passes 106 and consecutive edits/worker
  lifecycle pass 49. Coordinate enumeration,
  boundary/support sampling and global dedup/index/output staging remain open.
- Far-grid coordinate blocks now retain exact double-precision continuation state,
  preserving the original repeated-addition sequence and budget cutoffs. All
  1,520 grid coordinates in the ten-road fixture survive a fixed-bounds road edit.
  The expanded 136-check point suite and 137 source checks pass, as do independent
  edited mesh/collision comparisons. Forward+ passes 58 checks with zero pixel
  differences, the real editor passes 107 and consecutive edits/worker tests pass
  49. This localizes coordinate construction but
  shows no meaningful total speedup: 600.764/595.873 ms retained/rebuilt medians.
  Near-ring/boundary/support enumeration and global dedup/index/buffer staging
  remain unfinished.
- Native mesh assembly now buffers exact vertex/UV order and bulk-copies retained
  collars (35,853 vertices in 36 blocks after the ten-road edit). The bounded
  transient stream preserves native normals and falls back to individual emission
  after its 393,216-vertex cap. Isolated five-edit total medians are 574.077 ms
  buffered versus 598.051 ms native; unchanged medians are 174.292/188.664 ms.
  This affects generation CPU work, not rendering batches or draw counts. The
  stream helper passes 33 checks, collar helpers/comparisons 26/46, source/worker
  regression 139 and consecutive edits 49. The benchmark passes 70 exact-output
  checks, Forward+ passes 60 with zero changed pixels, and the real editor passes
  112 including Clear during a partially buffered job. Global point/triangle
  traversal, dedup/index mapping and output staging still prevent closing the
  first checklist item. See `source_regeneration.md` for limits and commands.
- Certified triangle groups now retain oriented emission arrays and copy only
  consecutive global-order runs, respecting the original 256-candidate frame cap.
  The ten-road edit skips individual emission for 8,175 candidates / 7,665 accepted
  triangles. Isolated local medians are 582.215 ms with runs versus 595.838 ms
  without; unchanged medians are 170.949/183.931 ms. The expanded group suite
  passes 159 checks, source/worker 140, consecutive edits 49, benchmark 72,
  Forward+ 62 with zero pixel differences, and the actual editor 113. Global
  coordinate construction, point dedup/index mapping and changed-output assembly
  remain open; the first checklist item is not complete.
- Native incremental Spatial Chunks now hands raw vertex/UV arrays directly to
  normal/output staging. Warm and local-normal jobs avoid constructing and
  extracting a complete source SurfaceTool; full and unsupported jobs retain
  exact native fallback. The isolated ten-road medians are 166.442/174.814 ms
  direct/round-trip unchanged and 590.389/593.779 ms after local edits. The latter
  is a small total difference, not a substantial speedup. Stream/normal/bound
  suites pass 40/248/17 checks, source/worker 140, consecutive edits 49 and the
  benchmark 81. Forward+ passes 66 with zero pixel differences; actual editor
  checks pass 114. Global coordinate/dedup/index and output partition work remain,
  so local rebuilding is still incomplete.
- Near-road row selection now runs once per job's lateral bands and retains
  path-local 32-row blocks plus exact ring coordinates. The first ten-road edit
  reuses 261/290 row selections and 2,520/2,800 coordinates. Repeated shared-curve
  baked-length changes correctly invalidate selection while unchanged coordinates
  survive. Isolated medians do not show a clear speedup (566.411/562.051 ms local,
  158.240/159.411 ms unchanged, retained/rebuilt). The point suite passes 180
  checks, source/worker 140, consecutive edits 49, output benchmark 78, Forward+
  68 with zero pixel differences, and actual editor 115. Boundary/support points,
  global validation/dedup/index and output partition work remain unfinished.
- Outer bounds, 16-edge contour groups and boundary-support coordinate blocks now
  retain exact native sampling order, with at most 64 proposals per result. Current
  support-direction probes and spatial mask validation remain authoritative. The
  ten-road edit reuses 198 bounds and 1,056 contour proposals, rebuilding 116;
  isolated medians are 566.493/570.156 ms local and 158.142/161.736 ms unchanged
  (retained/rebuilt). The boundary suite passes 373 checks, source/worker 146
  including complete support meshes without collars, consecutive edits 49,
  benchmark 80, Forward+ 70 with zero pixel differences, and actual editor 116.
  Source sampling/validation, support-direction probes, global dedup/index and
  output partitioning still prevent closing the full local-rebuilding item.
- Separate topology now retains native source-path samples using exact curve,
  frame, transform, live lane/transition and terrain-profile inputs. Shared-curve
  pre-bake lengths retain separate variants; after warm-up, the ten-road fixture
  samples one path / 29 rows and retains nine paths / 261 rows. Custom callbacks
  bypass reuse, current path IDs are assigned on replay, and the new value-only
  store caps at 512 entries / 64 MiB. Path tests pass 70, source/worker 146,
  consecutive edits 49, pressure 1,045, Forward+ 71 with zero pixel differences,
  and actual editor serialization/Clear 119. The isolated benchmark passes 84;
  local medians are 562.875/568.568 ms retained/rebuilt, a small improvement.
  Changed-path sampling, global source
  validation, polygon/segment assembly, deduplication/indexing and final output
  partition work remain, so local rebuilding is still incomplete.
- Native topology path entries now retain complete contours and source segments:
  the ten-road edit reuses nine polygons / 252 segments and rebuilds one / 28.
  The existing 512-entry / 64 MiB path-store limit includes the added payload.
  Native collections avoid an extra full deep copy, while fresh Inspector profile
  arrays are explicitly detached and the separate worker snapshot remains.
  Independent legacy collection/assembly comparisons pass 86 checks, source and
  Inspector/worker regressions 146, consecutive edits 49, Forward+ 72 with zero
  pixel differences and actual editor ownership/save/Clear 120. Changed-path
  sampling/assembly, global source/spatial validation, dedup/index mapping and
  changed-output traversal remain, so the full local-rebuilding item stays open.
  Isolated assembly medians are 570.286/575.318 ms local and 164.225/161.947 ms
  unchanged (retained/rebuilt); larger snapshot-copy costs mean no clear
  source-stage speedup, despite skipping unchanged assembly work.
- A grouped spatial-membership cache was tested and removed: its isolated local
  median was 577.550 ms versus 573.000 ms for native index construction. The
  investigation exposed and fixed an infinite nearest-search loop for entirely
  degenerate XZ segments. Empty results are not cached with a finite search scope,
  so later distant valid sources remain discoverable. The independent spatial
  regression suite passes 153 checks. Source indexing/validation is still global;
  this robustness fix does not close the local-rebuilding item.
- Actual automatic editor propagation now waits for debounced/worker road output
  before topology sampling, and ground queries recognize queued terrain edits.
  This fixes grounded-prop transform differences after Undo and versus a full
  build caused by shared-curve sampling order. The integrated markings-demo test
  passes 24 checks in both normal and threaded-road/reversed-node-order runs:
  automatic edit/Undo/Redo, exact full-reference geometry, distant resource reuse,
  and no false pending promise for manual-only generators. No manual regeneration
  is used between editor actions. The fixture has no junction and is not a game-map
  performance benchmark; the full local-rebuilding item remains open.
- The automatic workflow now also covers two junction fans with lane markings,
  topology and ground-snapped props. A local endpoint edit rebuilds one fan and
  reuses the other. Normal Individual and threaded/reversed-order MultiMesh runs
  each pass 43 checks, including per-generator distant identities, exact geometry
  and byte-identical editor images for Undo/Redo and a separate full reference.
  The edit changes 309/304 visible pixels respectively. Junction regressions pass
  164 checks. A new isolated ten-road benchmark identifies remaining full-surface
  normal work: 30.267 ms of a 185.721 ms incremental update, processing all 131,940
  surface-normal vertices despite retaining 6,917 of 7,330 source rows. Native
  full surface/marking snapshots match all five edits (10 checks). This identifies
  a concrete remaining rebuild cost; no road-normal cache is implemented yet.
- Indexed road normals now retain native face/vertex adjacency under Incremental
  Generation. Exact 256-vertex input blocks isolate local edits while preserving
  native accumulation order and signed-zero inputs. Five stores cap at 12 MiB
  each; topology changes use full computation until the new layout repeats.
  The final ten-road comparison, with source caches enabled on both sides, lowers
  normals from 29.931 to 9.970 ms and the whole update from 185.945 to 166.069 ms.
  It retains 125,290 of 131,940 normal vertices and passes 25 exact/reuse checks.
  Normal regressions pass 189, source/worker 91, junction geometry 164, six legacy
  hashes match, runtime chunk/bake passes, and both real editor render variants
  pass 43 checks with exact Undo/Redo/full-reference images. Surface upload,
  output partitioning and global validation still keep local rebuilding open.
- Incremental Spatial Chunks now consumes CPU surfaces/materials directly, avoiding
  the temporary complete-mesh upload. All 32 combinations of empty/nonempty bands
  pass 243 material/partition checks; native Single Mesh/default behavior remains.
  The benchmark was corrected: its previous inherited snapshot saw the empty root
  mesh in chunk mode, so the earlier timing runs did not themselves prove chunk
  geometry equality. It now checks actual chunk arrays and collision faces by
  node path and passes 40 checks in both controlled modes. Fresh total medians are
  170.261 ms with the temporary upload and 165.129 ms without (about 3% lower),
  with three temporary surface uploads reduced to zero. Runtime/bake and real
  Forward+ comparisons pass with zero changed pixels; draw counts stay 6/86/86.
  Editor variants pass 45 checks, with a 60-second correctness deadline to tolerate
  measured slow editor frame pacing. Partition construction remains global and
  costs approximately 76–78 ms here, so full local rebuilding remains open.
- Incremental Spatial Chunks now retains unchanged per-surface cell arrays and
  rebuilds only cells touched by changed positions/normals/UVs on stable indices.
  Triangle and cell insertion order match the independent native partition.
  Five stores have conservative 16 MiB retained-payload limits each; topology or
  chunk-size changes repartition, capacity overflow uses the complete native
  pass. Clear, disable and Single Mesh release stores. Partition regressions pass
  163 checks, sparse-band/direct-output checks 435, runtime/bake passes, and the
  actual threaded/reversed-order MultiMesh editor passes 45 checks with exact
  Undo/Redo/full-reference images. Isolated ten-road medians fall from 163.321 to
  107.951 ms total, with partitioning falling from 75.772 to 23.871 ms. Both runs
  check actual chunk arrays/collision faces (40 native / 60 cached checks).
  The local edit reuses 271 surface-cell arrays and rebuilds 20. Complete source
  assembly, global validation/classification and dependent topology work remain;
  the full local-rebuilding item is still open. Draw-call behavior is unchanged.
- Unchanged native road paths now also reuse complete pre-weld indices and row
  dictionaries. Exact source identity plus path/global index placement, winding
  and resolved weld settings govern reuse. Mutable consumers receive detached
  data. The additional store caps at 16,384 rows per path and 32 MiB aggregate
  serialized payload; overflow bypasses, and Clear/disable/removal release it.
  Independent frozen-assembly tests pass 95 checks, source/worker 91, junctions
  164, six legacy hashes match, runtime/bake passes and the actual threaded
  MultiMesh editor passes 45 checks with exact Undo/Redo/full-reference images.
  Isolated ten-road medians fall from 108.964 to 93.572 ms total and from 30.654
  to 15.095 ms for assembly. Nine path assemblies / 6,597 rows are reused; one /
  733 rows is rebuilt, with 5,043,800 retained serialized bytes. Both benchmarks
  check actual chunk arrays/collision faces (60 native / 65 retained checks).
  Changed-path assembly, source concatenation and dependent terrain/global
  validation remain, so full local rebuilding is still open.
- Terrain triangle/collar scopes now certify native search stopping and radius
  tests at the current global road width. A tiny maximum-width change previously
  invalidated every group; unchanged groups can now replay without rounding any
  geometry or weakening spatial dependency checks. Unsafe far-road widening is
  explicitly rejected. Proofs cap at 4,096 tests inside existing group budgets;
  cache misses now report their reason. Mesh-support tests pass 59, triangle
  groups 159, collars 26, spatial indexing 153 and source/worker 146. The real
  threaded MultiMesh editor passes 45 checks with exact images and reuses 103
  triangle / 11 collar groups after the local edit. Isolated six-road terrain
  medians drop from 1,268.369 to 927.361 ms (about 27%) against a controlled strict
  global-width reference; all five edits match independent full mesh/collision
  output. Global validation, point/index assembly and triangulation fallback
  still leave the full local-rebuilding item open.
- Road paint now reuses unchanged 32-row-pair blocks under the existing road
  incremental opt-in. Exact welded vertices, distances, lane layouts/settings
  and ordered junction exclusions govern reuse; materials/colors apply without
  repeating geometry construction. The bounded store clears on public source
  Clear, removal and disable. Frozen-native array/material checks pass 103,
  the real threaded MultiMesh editor passes 47 with exact Undo/Redo/full images,
  runtime/bake/physics passes and all six original geometry hashes remain intact.
  The editor edit reuses 10 paint blocks and rebuilds 6; the ten-road fixture
  reuses 218 and rebuilds 12 (90 cached / 85 native-paint checks). Timing runs
  were not isolated from the user's other editor/game; their observations and
  limits are documented in source_regeneration.md, not claimed as map FPS gains.
  Combined paint upload, lane-material overlays and triangulation fallbacks
  remain; the full local-rebuilding requirement stays open.
- Per-lane material overlays now reuse 64-row source blocks plus indexed normals
  in a separate surface cache. Live materials, native row/index order, disabled
  legacy lane widths, banked transforms and custom-path callbacks are preserved.
  Row retention is bounded to 4,096 entries / estimated 32 MiB, with native
  overflow fallback and public Clear/disable/removal cleanup. Frozen-native
  array/material checks pass 91; the actual threaded MultiMesh editor with lane
  materials passes 49, including exact Undo/Redo/full-reference images. Its edit
  retains 18 blocks and rebuilds 6. Runtime bake/physics, six baseline hashes and
  all 103 paint-cache checks pass. The ten-road fixture retains 226 of 240 blocks
  (80 cached / 75 native-row checks). Non-isolated timing observations and limits
  are recorded in source_regeneration.md. Combined publication and the editor's
  cocircular triangulation fallback still leave the local-rebuilding audit open.
- External near-cocircular points now expand the affected triangulation cavity
  through their incident triangles, retaining native ordering and all existing
  boundary/circle/capacity/eight-attempt checks. The common six-road edit retains
  2,904 triangles and rebuilds 1,252 instead of falling back to a full call.
  Complete unfiltered native sets plus actual terrain meshes/collisions match on
  all five edits (20 new / 15 strict-reference checks). The actual threaded
  MultiMesh/per-lane-material editor passes 50 checks with local tie resolution,
  exact images, Undo/Redo and distant identities. Stress tests pass 800 with 543
  local patches; large terrain output/worker checks pass 49, source 146 and
  triangle groups 159. Local tie expansion is not a measured latency win: the
  first triangulation took 127.001 ms versus 46.553 ms with the old full fallback.
  It remains inside the default-off experimental local option; numerical and
  capacity fallbacks remain supported. Targeted construction work is validated;
  the overall eight-requirement completion audit remains to be performed.
- Final requirement-by-requirement audit passed on 2026-09-12. Fresh checks cover
  actual editor Inspector/gizmo history, preset history and source ownership,
  all presets/customization, real Forward+ Individual/MultiMesh rendering,
  markings and entry/exit images, identical rendered bake, runtime saved reload
  and physics, all six legacy hashes, lane compatibility, 56 span-handle checks
  and 85 grounded-prop checks. The final integrated editor's 50 checks and local
  source/cavity/overlay comparisons were inspected against the final code.
  README paths/defaults and existing exported road/profile properties were
  checked. No required item remains open; retained native fallbacks, global
  validation/publication and experimental-local latency costs are documented
  limitations, not an unimplemented promised feature. Changes remain in the
  user's working tree; no commit, deployment or consuming-project edit was made.
