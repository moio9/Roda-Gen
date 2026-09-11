# Incremental source generation

Enable `RoadNetworkCreator3D > Workflow > Incremental Generation Enabled` to
reuse unchanged source calculations. It is **off by default** and independent
of Runtime Output's Single Mesh / Spatial Chunks choice and prop MultiMesh mode.

## Implemented scope

The road sampler stores immutable, pre-weld cross-sections in blocks of 64 rows.
An unchanged path skips row construction entirely. After a control-point edit,
blocks whose inputs still match reuse their positions, frames, widths and lane
metadata; other blocks are reconstructed. This is source calculation reuse,
not just comparing already-generated final meshes.

Unchanged native paths also reuse their pre-weld index arrays and assembled row
metadata when path order, global vertex base and resolved weld settings match.
The assembly store is bounded separately; see **Road path assembly reuse** below.

Keys include exact sampling distances, transforms, native curve samples and
orientation support, resolved width/lane transitions and numeric easing-curve
data. Changed paths still need dependency queries, and Godot's native curve bake
remains authoritative. Arbitrary custom Path3D scripts bypass this cache because
their width/layout callbacks can change without a declared revision.

Junction discovery separately caches nearest-inner-row and nearest-row-pair
queries. It snapshots ordered positions before welding, preserves tie-breaking
and resolves results against the current row arrays. Hashes only locate entries;
exact input comparison is required before reuse. Welding never mutates cached
source data.

The road cache retains one completed source generation and discards removed
paths. Junction search retains at most 2,048 queries, evicting entries unused for
more than two builds. Clearing the generator's output also clears these caches.

### Junction geometry

Each unchanged weld cluster now replays a sparse geometry patch: changed road
vertices/normals/UVs, requested side-strip marks, ordered index substitutions and
optional fan center/triangles. It does not store copies of the whole mesh or old
global surface-index arrays. Stable path identities, row ordinals and edge slots
resolve every cached reference against the current assembly.

Inputs are checked against the geometry left by preceding clusters, in current
cluster order. Rebuilding from fresh pre-weld road sources means removed
junctions leave no old patches behind. Endpoint support includes both candidate
strip neighbors; endpoint-to-midpath support includes the entire target side
because the original weld searches all its adjacent pairs. Interior cross-section
slots are captured only where strip transforms can read/write them. Exact input
bytes, not just matching hashes, are required for a hit.

Index substitutions retain execution order: `B -> C; A -> B` is not treated as
`A -> C`. Replay uses one index pass with a transient dense lookup table. Fan
surface routing still accounts for global shoulder/sidewalk presence. Clustering,
its global 2.5x fallback, marking exclusions and final blocked-face redistribution
remain outside the cache. Storage is limited to 256 entries and 64 MiB of payload
(plus container overhead); entries unused for more than two builds expire.

### Indexed road surface normals

With incremental generation enabled, each stable indexed surface retains native
triangle adjacency and unflipped normals. Exact input blocks identify changed
positions/fallback normals; only affected triangle faces and their vertex normals
are recomputed. Coincident but disconnected vertices remain separate, and each
vertex sums its incident triangles in the original native order. Spatial output
can now consume CPU surfaces directly and reuse unchanged partition cells;
input validation and triangle classification still traverse the source. See the measured implementation
notes at the end of this document for bounds, fallback behavior and results.

### Terrain strips

With **Terrain Fill Algorithm = Disabled**, each complete path's side-terrain
strip can skip growth scans, smoothing, ring construction and skirt generation.
The key contains its exact post-weld road rows, normals/UVs, blocked edges,
terrain settings and all road triangles within its conservative growth bounds.
Adding/removing a nearby road invalidates affected strips; unrelated distant
strips can survive a local edit. Replayed indices are resolved against current
vertex offsets, including after path reorder. Skirt softening's changes to base
road vertices are replayed in the original path order as well.

Edited paths additionally reuse individual growth searches, 32-row smoothing
blocks, ring rows, skirt slope/drop values and skirt vertex columns. Growth keys
contain the incoming accepted outer point and recovery-limited requested width,
current/opposite bases, and all relevant earlier base edges and road triangles
inside conservative probe bounds. Width recovery still runs in original row
order: a changed result becomes the next query's input, propagating only while
the dependency changes. This is not permission to ignore earlier intersections.

Each smoothing pass checks a one-row halo around its output block; later passes
consume the previous pass's actual results. Ring keys use the resolved path-wide
subdivision count and exact noise settings. Skirt columns use directions freshly
resolved from the current whole-chain center, including the original neighbor
fallback. A local edit can therefore legitimately invalidate distant skirt
columns. Current vertex IDs and index order are assembled afresh, preserving
skirt softening that reaches the base-road vertices. Buffer/index assembly and
dependency inspection still visit the path; this reuses source calculations,
not unchanged final terrain mesh resources.

Whole-strip storage is limited to 64 entries and 64 MiB of serialized/array payload. Nested
stage storage has a separate 16,384-entry / 64 MiB payload limit. Both expire
entries unused for more than two builds, with additional container overhead.
Whole-strip hits retain their nested stage entries for the next local edit.
Hashes only locate entries; exact input bytes are compared before reuse.

`clear_source_generation_cache()` clears terrain entries immediately while idle,
or queues the clear for the next configuration after an active worker has joined.
The worker uses captured winding settings even if the Inspector changes them.

### Global Rectangle/Boolean fill

Rectangle and Boolean now reuse native clipping/offset/triangulation results,
complete overlapping-part clipping (including classification and winding
fallbacks), and root-polygon resampling/interior triangulation. Exact ordered
polygon inputs determine reuse; returned arrays are copied so downstream
winding changes cannot mutate stored results. Coarse hits retain nested native
entries beyond the idle expiry window. Cancellation is checked before replay.

Blend heights reuse the complete ordered cell neighborhood selected by the
original algorithm, including out-of-radius points used by its zero-weight
fallback. Exact-cell averaging still takes precedence. Each immutable-per-build
grid compares point values/order once per cell and assigns nonrecycled revision
IDs. Queries then compare ordered cell revisions; repeated region inspection is
shared within a build. Cell payloads use the same bounded stage storage. An
empty neighborhood retains an exact global boundary revision because the full
algorithm scans all points in that case.

Assign-only heights reuse nearest-neighbor searches whose previously visited
cell prefix is unchanged. Safe-distance termination, domain limits and ordered
ties are preserved. Exhausting an old grid does not prove that a newly expanded
grid is irrelevant: these searches must run again. Caller-owned grids without
builder revisions bypass nearest-query reuse. Public clearing and worker
cancellation preserve the same ownership rules as road-side terrain.

This is not yet fully local global terrain. Boundary extraction, seed-domain
construction, adaptive edge-conformity traversal and final vertex/index assembly
still run. Changing outer extrema can relocate an entire grid/radial domain;
changed global Delaunay point sets still need native triangulation. Reusing
polygons alone does not prove a total speedup, especially on small scenes.

### Separate TerrainTopologyBuilder3D

The separate terrain node has its own default-off
`incremental_generation_enabled` option; it does not inherit the road node's
toggle. It reuses nearest-road spatial queries, height fitting, triangle/road
edge crossing tests, near-ring/far-grid point masks, filtered/height-fitted triangle groups and unchanged complete
Delaunay point sets. It is still a
partial source implementation: road resampling after a signature change, point
enumeration/deduplication and final triangle traversal/emission remain global.
Unchanged collar blocks now retain subdivision, diagonal and height-fitting work.
Changed-set Delaunay and retained final mesh/collision/normal work have separate
opt-in implementations described later in this document.

Segment and road-edge cell revisions compare exact ordered values, not scene
IDs or old array offsets. Nearest queries validate their original searched
prefix, cell size and global maximum half-width (needed by the safe-distance
proof). Crossings validate every cell touched by the triangle's bounding box.
Repeated region checks share per-build support. Value storage is bounded by
65,536 entries / 64 MiB of payload, with two-build idle expiry; transient current
spatial-index/region storage and container overhead are additional. Revision IDs
are never recycled on clearing or eviction.

Height keys include the selected road/profile, exact edge-height lookup entry,
height/noise parameters and the actual configured noise resource values, so an
Inspector edit before the next noise configuration cannot poison later results.
Default terrain profiles now also invalidate profiles copied into road data.
Custom terrain subclasses and active height modifiers bypass source caching:
modifiers receive mutable builder/road-info objects and have no read-only
dependency contract. Their calls/side effects are not skipped.

Only the main thread accesses this cache. The Delaunay worker receives a copied
point array, and its result is cached after joining only if not discarded or
superseded. A rebuild request during multi-frame mesh assembly discards that
partial mesh before using new settings. Clear Generated also cancels a queued
restart. Persistent sampled roads and in-flight jobs hold separate deep copies
of road/profile values, so editing Inspector arrays cannot mutate a pending
job or leave its cached source data changed after restoring those arrays.
`clear_source_generation_cache()` is immediate when idle and deferred
until the next generation when work is pending.

`get_source_rebuild_stats()` returns copied counters plus `pending`. Counters
include `nearest_reused/rebuilt`, `distance_tests`, `heights_reused/rebuilt`,
`crossings_reused/rebuilt`, `edge_candidates_tested`, `delaunay_reused/rebuilt`,
`segments_checked`, `dependency_cells`, `regions_reused`, `modifier_bypass`
and `height_modifier_bypasses`, plus stage storage counters. These count actual
source work; final surfaces are still recreated.

`get_terrain_height_at_world()` returns `{hit: false, pending: true}` while a job
is pending, preventing a query from replacing that job's spatial context with
new roads. Once idle, moved roads refresh the spatial index even if the segment
count is unchanged. `is_terrain_generation_pending()` exposes this readiness
state, and `terrain_generation_completed` is emitted after the final completed
build (including an empty result), not between queued restarts. Spline props
defer explicit rebuilds without deleting old output and retry once idle. Terrain
completion also schedules terrain-only prop updates at runtime and when editor
automatic regeneration is enabled. Clear Generated cancels the prop request and
disconnects the listener until another explicit rebuild.

### Mesh prop placements

`SplinePropArray3D` also reuses whole unchanged-path placements when its explicit
**Road Network Source** points at this enabled road. Both individual mesh nodes
and MultiMesh use the same placement cache. Keys include exact curve/profile/
road data, transforms, range/span inputs, endpoint rejection zones and incoming
random-generator state. Replay restores the outgoing random state, so a changed
earlier path cannot silently shift later paths' randomness.

Changed paths now check blocks of 32 candidate spacing steps. The cache keeps
float64 jitter distances and checks native curve/banking and local lane-profile
support before reusing placements. Candidate distances preserve the original
repeated-addition order. Range dependencies are clipped to each block's possible
jitter/clamp interval, so a tail extension need not invalidate the prefix.
Incoming/outgoing RNG state crosses every block, including completely rejected
blocks. With matching geometry, endpoint-rejection decisions are rechecked at
all original candidate positions; distant endpoint edits need not rebuild a
block, while a changed decision invalidates it before random draws can diverge.
Cached and rebuilt placements feed the same per-path MultiMesh cell collection,
preserving batch order, names, transforms and bounds. They do not create a new
render batch for each placement-cache block.

Compatible native output is now reconciled after placement: unchanged nodes and
MultiMesh resources are retained, changed node properties/buffers are updated,
and obsolete nodes are removed before replacements claim their names. Current
mesh/material, parent ordering and persistence ownership remain authoritative.
Native state/property-schema checks and live MultiMesh-buffer comparison prevent
manual output changes from poisoning reuse. Node references are weak; only the
current output's snapshots are retained. Item Scene and custom source callbacks
still have their complete create/remove lifecycle. See `prop_rendering.md` for
output counters, exact eligibility and the real-editor ownership/save check.
Item Scene, randomized seeds and custom road/path/scatter scripts bypass this
cache. Ground snapping is eligible with the exact built-in, idle
`TerrainTopologyBuilder3D` script and no active height modifiers. Both whole-path
and block replay revalidate all consumed hit results against current terrain;
missing hits and slope rejection are dependencies too. The incoming/outgoing
per-side last-valid-height state is carried alongside RNG, including across empty
blocks. Provider identity and snap settings are part of the keys. This remains
safe with the terrain source cache disabled: no old terrain hit is assumed valid.
A transient, bounded 16,384-query memo avoids duplicate pure provider calls
within a build, then is discarded. Unknown providers, modifiers and scene scripts
keep their full query lifecycle. See `prop_rendering.md` for readiness and counters.

## Limits

Incremental rebuilding retains native dependency validation; it does not promise
fixed-radius changes or eliminate global assembly:

- Editing length can shift downstream arc-distance samples and UV phase. Legacy
  nonuniform widths depend on total path length; Curve Up frames can propagate
  along the curve. Rebuilding more than the adjacent control-point pair is valid.
- Adaptive sampling still resolves neighboring endpoints before comparing inputs.
- Junction clustering and exact dependency inspection still run. Geometry work
  is skipped on a hit, but patches and current index substitutions must be applied.
- Global terrain boundary/domain construction and adaptive edge traversal still
  run. Stable road normal layouts and unchanged partition cells reuse their
  calculations; complete source concatenation and combined overlay/marking-mesh
  publication remain. Paint and lane-overlay construction reuse unchanged blocks.
  Global clipping, root triangulation and height searches
  reuse unchanged inputs. Output classification still visits every triangle.
- Separate terrain source queries, filtered triangle groups, collars and output
  resources reuse unchanged support. Changed point sets may use local Delaunay
  updates, but ambiguous or unsupported edits fall back to full triangulation.
  Global source validation and index assembly remain. Arbitrary terrain modifiers and
  deformers remain non-incremental. Ground-snapped mesh props revalidate current
  terrain hits; they do not yet skip queries via terrain-region revision tokens.
  Road-side terrain strips and eligible mesh props reuse within-path calculations
  as well as entire unchanged paths.

## Inspection and full reference

```gdscript
road.incremental_generation_enabled = true
road.regenerate()
print(road.get_source_rebuild_stats())

# Force a cold incremental run, without deleting source scene data:
road.clear_source_generation_cache()
road.regenerate()

# Use the original full source path as the reference:
road.incremental_generation_enabled = false
road.regenerate()
```

Read stats after generation has completed. Source counters are `paths_reused`,
`blocks_rebuilt`, `blocks_reused`, `rows_rebuilt`, `rows_reused`,
`dependency_rows_checked` and `uncacheable_paths`; `source_ms` measures the sampler
stage, with `sampling_ms` and `assembly_ms` splitting its main costs. The nested
`assembly` counters report complete path/row assembly reuse, reconstruction,
bypasses and retained serialized payload bytes. `junction_search` contains point/pair query counters and actual
`distance_tests`. `terrain_strips` reports `strips_reused/rebuilt`,
`rows_reused/rebuilt`, `vertices_reused/built`, `growth_width_queries` and cache
size/eviction counters. Strip row/vertex counts describe buffer assembly, not
whether every inner calculation ran. Actual stage reuse is reported separately:
`growth_queries_reused`, `ring_rows_reused/rebuilt`,
`chain_blend_rows_reused/rebuilt`, `skirt_drops_reused/rebuilt`,
`skirt_blend_rows_reused/rebuilt` and `skirt_columns_reused/rebuilt`.
`growth_width_queries` counts executed growth searches, excluding cache hits.
`stages` exposes stage query, entry, payload and eviction counters.
For global fill, `fill_clips_reused/rebuilt` counts complete overlapping-part
clipping queries; `fill_polygons_reused/rebuilt` counts root triangulation.
`fill_triangles` counts emitted global triangles, distinguishing real fill from
fallback strips. `fill_heights_reused/rebuilt` and `nearest_queries_reused/rebuilt`
describe height work. `height_cell_points_checked` counts points inspected to
validate cell revisions, `height_dependency_cells` counts region cell visits,
and `height_regions_reused` counts shared per-build region inspections. The
legacy `nearest_dependency_points` remains zero on the cell-revision path.
`stages.geometry_2d` reports actual native operation reuse/rebuild separately.
The outer `terrain_strips.enabled` indicates the whole-strip algorithm only;
`terrain_strips.stages.enabled` also covers Rectangle/Boolean stage reuse.
While a worker owns terrain it returns `{pending: true}`
instead of reading the worker's mutable counters. Props expose separate
`get_placement_rebuild_stats()` with path/placement reuse, eligible
`blocks_rebuilt/reused` and `candidates_rebuilt/reused`, `sampling_steps`, outgoing
RNG state and explicit bypass reasons. `sampling_steps` counts actual placement
loop iterations (including bypassed paths). `dependency_rows_checked` counts
native geometry checks and `endpoint_queries_checked` counts rejection checks;
these checks still run on changed paths even when placement construction is
skipped. A wholly unchanged path skips both block checks and construction.

`junction_geometry` separately reports `clusters_rebuilt/reused`,
`support_vertices_checked`, `vertices_replayed`, `side_pairs_tested`,
`remap_index_visits`, `geometry_ms` and bounded cache usage. Its timing includes
dependency checking and patch replay, not only the skipped weld calculations.

These differ from `get_output_rebuild_stats()`, which reports
retained final mesh/collision resources. Neither stage alone measures total
regeneration time.

## Validation

```sh
godot --headless --path . --script tools/check_road_source_cache.gd
godot --headless --path . --script tools/check_road_junction_cache.gd
godot --headless --path . --script tools/check_road_junction_geometry_cache.gd
godot --headless --path . --script tools/check_road_terrain_cache.gd
godot --headless --path . --script tools/check_road_terrain_stages.gd
godot --headless --path . --script tools/check_road_global_terrain_cache.gd
godot --headless --path . --script tools/check_topology_source_cache.gd
godot --headless --path . --script tools/check_ground_prop_cache.gd
godot --headless --path . --script tools/check_prop_terrain_lifecycle.gd
godot --path . --rendering-method forward_plus --script tools/check_prop_output_cache.gd
godot --headless --path . --script tools/check_terrain_cache_pressure.gd
godot --headless --path . --script tools/check_road_runtime_output.gd -- --incremental
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_source_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/check_prop_source_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_terrain_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_global_terrain_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_topology_source_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_ground_prop_cache.gd
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_junction_cache.gd
```

The source test compares full/incremental mesh arrays, material colors, exact
collision faces and raw lane/marking metadata after edits. Its 91 checks cover
all orientation modes, tangent/tilt edits, lane data and easing resource edits,
legacy widths, mirrored/nonuniform transforms, adaptive endpoint changes,
junction appearance/removal, path reorder/insertion/deletion, closed curves,
custom-script bypass and threaded cancellation. Six pre-extraction geometry
baselines also match with junction caching cold and warm (138 junction checks).

The local-edit fixture reused 267 rows in five blocks while reconstructing 241
rows in four blocks, retaining the separate unchanged path. The synthetic
900-by-1,000 row-pair query skipped 900,000 distance tests on a hit: median full
query stage 118.727 ms versus 0.494 ms warm, including configuration and input
hashing. This is a query microbenchmark, not whole-road or game-map performance.

In the source fixture's five-run unchanged-road comparison, median sampler time
was **12.345 ms full / 2.675 ms warm**; total synchronous regeneration was
**50.107 ms full / 40.655 ms warm**. This includes final output construction and
shows why source-stage savings must not be presented as the total speedup. The
fixture is small and does not establish performance for a consuming terrain map.

The actual Forward+ source/full, warm-cache and edited/full-reference captures
matched with **0 changed pixels**; the edit visibly changes the road. Captures
are saved as `/tmp/roda-markings-source-*.png`. The custom Godot 4.7.2 build still
logs three Compute/Shader/Sampler RID warnings at renderer shutdown; these
comparisons do not identify their cause.

The terrain test passes 76 checks covering exact full/cached mesh arrays and concave collision,
local/distant edits, nearby road appearance/removal, path/row reorder, width and
global setting changes, adaptive subdivisions, mirrored/nonuniform transforms,
blocked junction edges, cache clearing and threaded cancellation. An isolated
regression first reproduced all three terrain index helpers reading a newer
Inspector winding value; the configured builder now retains its own winding.
An edit reused one 22-row strip (444 generated vertices) while rebuilding the
other. A five-run fixture measurement was **109.471 ms full / 8.549 ms warm**
total regeneration, not a map benchmark.

The within-path terrain suite passes 64 checks. A 122-row position-edit fixture
reuses 86 growth searches, 84 ring rows, 192 chain-blend rows across smoothing
passes and 10 skirt columns, while rebuilding their changed counterparts.
Tests cover incoming width state, earlier own/opposite-side edges entering probe
support, nearby road insertion/removal, smoothing halos, banking, row extension,
global subdivisions, noise changes, exact hash collision rejection, nested
cache retention and bounds/clearing. Full mesh arrays and collision faces match.
All six original mesh baselines remain byte-identical.

In a five-run sequence of **distinct** local tilt edits, total synchronous road
regeneration measured **738.460 ms full / 290.215 ms local**. The test asserts
these are not hits on previously cached whole strips; repeated toggles between
two old states would measure a different optimization. This includes source,
terrain, final surfaces and collision, but does not establish a game-map speedup.

The global terrain suite passes **216 checks** across Rectangle/Boolean and all
12 topology choices, requiring emitted global triangles (not side-strip
fallbacks). It compares exact full/local mesh arrays and collision after edits,
source reorder, offsets, height mode/radius changes and winding changes. Focused
cases cover equal-distance ties, closer point insertion, exhausted search-domain
expansion/shrinkage, exact-cell priority, zero-weight fallback, cell ID reuse
after eviction, caller-owned grids, immutable clipped/triangulated results,
nested retention and threaded clear/cancellation. The separate strip suites
still pass 76 and 64 checks, and the six original geometry hashes match.

Five distinct position edits in the global suite measured total synchronous
medians of **41.768 ms full / 42.360 ms local** at sample step 6 and
**272.324 ms full / 186.874 ms local** at sample step 1. Both include final mesh
and collision construction; mixed reused/rebuilt polygon assertions prevent a
historical whole-result hit from masquerading as local work. The small fixture
does not show a speedup. `--benchmark-only` (optionally `--dense`, `--profile`)
uses the initial fixture, before the matrix's cumulative edits/settings, so its
timings need not equal these full-suite values.

The Forward+ global fixture renders real Rectangle blend-height and Boolean
assign-only fill. Each local edit reuses 237 root polygons and rebuilds 35.
The emitted terrain contains 1,690 and 5,574 triangles respectively; both edited
images have **0 changed pixels** against full generation. The edits themselves
change 39,996 and 25,130 pixels. Captures are written to
`/tmp/roda-markings-global-terrain-{1,2}-{full,warm,edited,edited-full}.png`.
The custom engine still reports its known visibility-buffer setting warning
and three MSAA shutdown RID leaks; the fixture reports no script/render errors.
This verifies parity, not correction of preexisting full-generator surface
artifacts, map-scale performance or driving behavior.

The separate topology source suite passes **137 checks**. Its full initial mesh
matches the pre-change SHA-256
`5017b1a6c77c73fbdc3046362726e266b84ae253a3897f1d94c0ccb8497bb7ce`.
Exact mesh and actual trimesh-collision comparisons cover cold/warm/local builds,
banking, default profiles, explicit edge invalidation, reorder, noise, edge
locking, sampling changes, mirrored transforms and winding. It tests mutable
modifier bypass, moved same-count road queries, result immutability, cache
clearing, real threaded restarts, multi-frame profile isolation, actual noise
resource configuration and Clear Generated during a queued restart. The lane
profile regression also passes.

The initial separate-terrain edit reuses **3,754 nearest queries, 3,791 heights
and 433 crossing queries**, rebuilding 904, 866 and 712 respectively. A sequence
of five distinct position edits measured total synchronous medians of
**459.721 ms full / 445.190 ms local**, including point enumeration, native
triangulation, final mesh and collision. This modest fixture-level difference
is not evidence of a general or map-scale speedup; the remaining global work
still dominates. The timing drains multi-frame assembly synchronously, not
elapsed interactive frame scheduling.

The separate-terrain Forward+ edit reuses 3,152 nearest queries, 3,807 heights
and 703 crossing queries. Its image differs from full reconstruction by
**0 pixels**, while the edit changes 69,755 pixels. Captures are
`/tmp/roda-markings-topology-{full,warm,edited,edited-full}.png`. The custom
engine emits the same visibility-buffer and MSAA shutdown warnings noted above.
The existing full-generator endpoint/seam artifacts are preserved, not repaired
by this cache work.

The prop suite passes 179 checks in Forward+ (169 headless). It checks actual
within-path reuse after position/tilt edits in all
orientation modes, fractional spacing and float64 jitter larger than spacing,
tail clamping/extension, include/exclude/manual/span ranges, empty rejected
blocks, local lanes/easing, global legacy-width dependencies, endpoint rejection
and downstream RNG changes. Twelve deterministic mixed edits also match full
reconstruction. Real Forward+ checks cover exact mixed cached/rebuilt MultiMesh
cells, order, transforms and bounds; Item Scene collision fallback is retained.

The real-terrain ground-prop suite passes **85 checks**, covering strict/clamped
slopes, per-side last-valid-height/RNG propagation, missing terrain, terrain-only
changes and queued worker/multi-frame completion. Deferred rebuilds preserve
actual node identities, including Item Scene collisions and a requested output
parent change. The separate **31-check** deterministic provider suite verifies
switching/freeing providers while pending, stale completion, disabling snap,
invalid inputs and manual clearing. The rendered ground fixture reuses **64
placements** and rebuilds **198**; edited/full images differ by **0 pixels**, and
the edit changes **73,495 pixels**. Captures are
`/tmp/roda-markings-ground-props-{full,warm,edited,edited-full}.png`.

Cache-pressure regression covers **1,033 checks** at the actual 16,384-entry
limit. Eviction now obtains the oldest key without allocating a complete key
array on every insertion; order, recent-lookup refresh and clearing are unchanged.
An isolated 512-entry pressure insertion measured **172.087 ms before / 2.180 ms
after**; nearest-hint pressure measured **167.957 / 0.591 ms**. In the real ground
fixture, 128 center/normal queries under pressure measured **796.486 / 68.210 ms**
with identical source counts and results. This diagnostic can be repeated with
`tools/check_ground_prop_cache.gd -- --profile-ground`; it is not a frame-rate
measurement and does not replace the distinct-edit end-to-end benchmark.

The five-distinct-edit ground fixture keeps **terrain source caching enabled in
both variants** and toggles road/prop incremental reuse. Before the eviction fix,
median complete road + terrain + props regeneration was **15,505.418 ms with
road/prop reuse off / 15,776.454 ms on**. After the fix this is **1,611.281 /
1,664.417 ms**, with the prop-only portions **428.754 / 435.799 ms**. The eviction
fix removes a large capacity-related slowdown in both variants; the extra
placement reuse still does not improve end-to-end time on this fixture. All
samples synchronously drain multi-frame terrain work and include output
recreation. They are not interactive frame latency or consuming-map benchmarks.

Before native output retention, an interior-position edit reused 4 blocks/256 props and rebuilt 10 blocks/582
props in the long-path fixture. A seven-run headless individual-node tilt-edit
measurement was **20.630 ms full / 13.209 ms local / 4.794 ms unchanged** total
prop regeneration. Forward+ MultiMesh measured **14.870 ms full / 8.514 ms local /
0.829 ms unchanged** for the same seven-run tilt fixture. These include node or
batch recreation and dependency checking, not road or terrain regeneration, and
are not consuming-map or frame-rate benchmarks.

Native-output retention passes **249 Forward+ checks** (182 headless), including
exact unchanged node/MultiMesh identities, changed buffers, live mesh resizing,
shader-property schema changes, manual output mutations, source replacement and
parent ordering/renaming, container-state reset and duplicate-name fallback.
Scripted Item Scene fixtures verify their actual ready
and exit callbacks plus collisions. The separate real-editor test passes **31
checks** for retained ownership, saving/reloading generated versus transient
output, parent output and automatic-versus-explicit deferred terrain updates.
In the dedicated local fixture, **156 native nodes remain unchanged and 152 are
updated**, with no new nodes. In MultiMesh mode **7 resources remain unchanged
and 8 are rebuilt**. The rendered ground fixture retains one batch/resource and
updates three; its edited/full comparison remains **0 changed pixels**.

With retained output, the seven-run Forward+ tilt fixture measures **13.865 ms
full / 8.545 ms local / 1.035 ms unchanged** in MultiMesh mode, retaining 16
resources and rebuilding 5 on the local pass. Individual nodes measure
**20.227 / 18.637 / 10.424 ms**, retaining 686 unchanged nodes and updating
212 without creation. Exact-schema typed readers, shared schema revisions,
unchanged-entry retention and transform-only snapshot updates remove the earlier
individual-node regression (previously 23.126 / 29.938 / 18.693 ms). Full live-state
validation still runs; uncommon schemas use reflection. The local native pass
spends 5.712 ms validating/removing output and 2.818 ms committing it. A separate
195-check reader test validates each specialized property against reflection,
including missing mesh/metadata and multi-surface fallback. The output suite
also checks cached transform-only snapshots against full reflection. These
fixture gains are not a universal speedup guarantee. Run the source suite with
`-- --benchmark-individual` to measure both modes (184 checks, versus the normal
179-check Forward+ run). These totals include placement and output work, not road
or terrain regeneration, and are not FPS measurements.

The combined rendered fixture shows green terrain, white/yellow markings and red
mesh props, visibly changes after a CP edit and has **0 changed pixels** between
cached/full references. Its warm pass skips all growth queries for 98 terrain
rows/1,604 vertices and all placement sampling for 260 props. The local edit
reuses one prop block (64 placements) and rebuilds four (198 placements) within
the same path. Images: `/tmp/roda-markings-terrain-*.png`.
That edited capture also reuses 51 terrain growth searches and 60 ring rows
within the edited path, while rebuilding 145 searches and 138 ring rows. It
retains 60 skirt-drop values and six skirt columns. The full-reference image is
still identical, including existing source-terrain boundaries.

The junction geometry suite passes 164 checks: 100 ordered-remap comparisons,
explicit fan centers, endpoint pairs, neighboring T junctions/overlapping strips,
changed predecessors, a new target-side candidate far along the path, reordered
paths/vertex offsets, removed junctions, the global fallback switch and unrelated
sidewalk changes. Full mesh arrays and concave collision match throughout.
Cache bounds, idle expiration and exact-input checking are tested too.

In the separated-fan fixture, one CP edit rebuilt one cluster and retained the
other. Actual Forward+ images show 174 changed pixels after the edit, and 0
differences from the full reference; images are `/tmp/roda-junction-*.png`.
The small mixed-junction timing fixture measured **0.746 ms full / 0.605 ms warm**
for the weld stage. This is not total regeneration time or a large-map speedup;
checking whole target-side support can still dominate small welds. Original six
mesh baselines, terrain-cache and runtime bake/collision suites also pass.

## Changed-point Delaunay experiment (not enabled)

`tools/fixtures/incremental_delaunay_probe.gd` is a test-only ordered insertion
replay implementation. It is deliberately outside the addon and is not selected
by `incremental_generation_enabled`. The production builder still uses native
Geometry2D for changed point sets.

The probe follows the operation ordering of Godot's
[Delaunay implementation](https://github.com/godotengine/godot/blob/master/core/math/delaunay_2d.h).
With unchanged bounds it restores the state before the first changed point,
uses a circumcircle spatial index, and replays cached triangle creation only
when the ordered cavity and coordinates match exactly. Coordinate remapping
handles shifted point indices while preserving native edge order; duplicates
use the stricter index-based comparison. Bounding-triangle changes reset replay.

The isolated suite passes **478 checks** against the complete native index array,
including exact triangle order, random edits, insertion/removal, grid ties,
duplicate/collinear points and coordinate scales from 0.001 to 1000. A separate
real-road probe captures the actual TerrainTopologyBuilder point sequence and
passes **8 exact native comparisons** across cold/warm generation and six CP
edits. These tests establish triangulation parity for their fixtures, not full
terrain integration or a local-output completion claim.

Performance fails the integration gate: on the 556–559-point terrain fixture,
native full triangulation has a six-edit upper-median time of **0.887 ms** versus
**79.249 ms** for ordered GDScript replay. The edited passes keep 16 prefix points,
reuse 79 suffix insertions and rebuild 461–464; undoing/replaying the suffix and
maintaining its index is still global work. Renumbering-aware cache keys improve
reuse counts but do not fix that cost. Do not enable this implementation as a
user-facing optimization. Further topology work must avoid whole-suffix replay
(for example, a certified local cavity update), then pass both geometric and
measured performance gates before integration. Point enumeration, final mesh
assembly and modifier dependencies remain separately open.

```sh
godot --headless --path . --script tools/check_incremental_delaunay.gd
godot --headless --path . --script tools/check_incremental_delaunay_terrain.gd
```

### Native local-cavity experiment (historical measurements)

The initial `tools/fixtures/local_delaunay_cavity_probe.gd` removed affected triangles,
triangulates only their local point set through native Geometry2D, and joins the
patch to retained triangles. It checks closed boundary loops, matching edges,
point coverage and empty circumcircles, expanding the patch for neighboring
dependencies. Hull changes, reordered inputs and uncertified external circle
ties fall back to the native full result. Internal ties participate in the
native subset call in their original relative input order.

Unlike ordered replay, this experiment compared **geometric triangle sets**, not
native triangle-array order. These measurements predate final-output integration
and do not include its deterministic ordering or mesh assembly. The fixture is
now a compatibility wrapper for the integrated helper described below.

The 634-check run (including 21 benchmark comparisons) exercises 399 successful
local patches across random edits, transformed grids, insertions and removals.
Seven-edit synthetic medians, including dependency/index updates and returned
indices but excluding the independent reference comparison:

| Points | Native full | Local cavity |
| --- | ---: | ---: |
| 300 | 0.310 ms | 0.827 ms |
| 1,000 | 2.494 ms | 2.021 ms |
| 3,000 | 20.784 ms | 7.103 ms |

The last 3,000-point edit retains 5,986 triangles and rebuilds 8 from 9 points.
These are synthetic triangulation results, not terrain-generation or FPS gains.
The small actual-terrain fixture passes 9 checks and performs six local patches,
retaining 417–419 triangles and rebuilding 650–654, but remains slower:
**18.814 ms local versus 0.870 ms native** (six-edit upper medians).

The uncentered ten-road/approximately 4,960-point terrain gate **fails**: all six
edits fall back after an unused patch point, and the test explicitly rejects
zero successful local patches. This case contains overlapping triangles in the
native reference, so a closed, non-overlapping cavity cannot be assumed. At
`(-17, -54)`, native incident triangles overlap by 286.840 square units. A reduced
seven-point fixture reproduces the defect without any road or cache code:
native Geometry2D emits 11 triangles (more than the planar maximum of 9), with
pairwise overlap up to 672.025 square units. Exact original float32 coordinates
and insertion order are saved in `tools/fixtures/native_delaunay_overlap.json`.
The reproducer reports a known defect; its success is not a local-cache pass.
Centering the calculation coordinates now avoids this recorded overlap, as
described below. A general robust handling strategy is not proven. Do not
integrate the cavity prototype based on its synthetic timing.

```sh
godot --headless --path . --script tools/check_local_delaunay_cavity.gd -- --benchmark
godot --headless --path . --script tools/check_incremental_delaunay_terrain.gd -- --cavity
# Known failing local-integration gate:
godot --headless --path . --script tools/check_incremental_delaunay_terrain.gd -- --cavity --large --inspect-overlap
godot --headless --path . --script tools/diagnose_native_delaunay_overlap.gd
```

### Optional centered triangulation

`TerrainTopologyBuilder3D.centered_triangulation_enabled` is now available under
Output and defaults to **false**. The shared value-only `delaunay_geometry.gd`
helper subtracts the bounds center before the native call and returns indices
into the original point array. Mesh/collision assembly therefore retains original
sample coordinates, not translated geometry. Translation is skipped if it would
merge distinct float32 samples or produce non-finite calculation coordinates.

This is a numerical-conditioning option, not a robust-predicate solver or a
universal terrain repair. It may change diagonals and triangle counts. In the
seven-point reproducer it reduces 11 overlapping triangles to 9, with **0 measured
overlap in the original geometry coordinates**. Merely scaling the same fixture
does not remove its overlaps. Existing endpoint/collar artifacts are not claimed
fixed; they remain visible in the comparison scene.

The option participates in the editor regeneration signature and Delaunay cache
key. Workers receive its captured value together with frozen points; the
main-thread path and thread-start fallback use the same helper. The focused
15-check test covers default native parity, input immutability, distinct-point
collision protection, scene serialization and actual worker output. The terrain
suite also checks cached/full mesh and collision equality, restoring exact legacy
output when disabled, and switching the option during a worker or mesh-assembly
restart. The centered Forward+ cached/full edited comparison has **0 changed
pixels**; its CP edit changes 69,707 pixels. This renderer run emits the existing
three Compute/Shader/Sampler shutdown RID warnings.

With a centered native reference, the ten-road cavity experiment now completes
all six local edits and passes 9 checks. It retains 9,020–9,031 triangles and
rebuilds 710–723 per edit. Its six-edit upper medians are **50.700 ms local versus
50.613 ms native full**: approximately equal, not a demonstrated speedup. This
reference is deliberately different from the uncentered legacy triangulation.
These are prototype-stage measurements, not current total generation timings.
Retaining final mesh/collision output and establishing real-terrain performance
remain open even with the opt-in integration below.

```sh
godot --headless --path . --script tools/check_centered_delaunay.gd
godot --path . --script tools/render_topology_source_cache.gd -- --centered
godot --headless --path . --script tools/check_incremental_delaunay_terrain.gd -- --cavity --large --conditioned
```

### Integrated opt-in local triangulation

Enable `local_triangulation_enabled` together with `incremental_generation_enabled`
on the separate terrain builder. Both default off. `delaunay_cavity_cache.gd`
owns value snapshots and bounded circle support; it has no dependency on `tools/`.
`try_patch` cannot run a full native triangulation: rejected patches return to
the existing synchronous/worker fallback, and only accepted worker results seed
the cache. Generation context captures centering/local settings, so queued
restarts cannot label an old result with newly edited settings. Public source
cache clearing also releases local support. Modifiers and custom terrain scripts
bypass local reuse and deterministic reordering.

Limits are 16,384 points, 32,768 retained triangles and 262,144 circle-cell links;
larger circles use a bounded-by-triangle-count overflow list. Unsupported point
counts fall back rather than retaining unbounded data. The standalone suite
passes 620 checks, including deferred-full behavior, immutable snapshots,
actual patches and capacity cleanup.

Local mode canonicalizes triangle emission order before normal generation in
both cached and uncached builds. This eliminated an observed 0.0000636 normal
delta caused by accumulation order. The integrated output test now requires
**exact oriented positions, UVs, normals and concave collision triangles** against
the uncached reference with the same local-mode ordering. Legacy mode retains
its original order and the 137-check source suite retains its original mesh hash.
The integrated output fixtures cover cold worker fallback, setting changes during
restart, Clear Generated and cache release. The expanded ten-road run passes
49 checks, including arbitrary-modifier callback and original-order fallback,
working-set retention and consecutive edits against independent full output.
The ten-road edits retain 9,020–9,025 triangles and rebuild 718–723 in the checked
three edits. These are triangulation counts, not retained renderer resources.

The dedicated Forward+ output fixture uses a successful local patch and compares
actual visible terrain/road images: **0 changed pixels** against the uncached
reference, with 17,953 pixels changed by the edit. In contrast, the markings
demo still falls back for degenerate patches, even on a small edit. Its zero-pixel
fallback comparison is not evidence of successful local triangulation; the
`render_topology_source_cache.gd -- --centered --local-topology` integration gate
deliberately reports that missing reuse. Centering the small isolated road can
also produce a worse native triangulation than its uncentered mode; do not infer
a universal conditioning benefit from the seven-point reproducer.

Whole point enumeration and canonical index ordering still run globally. Follow-up
triangle-group filtering and spatial mesh/collision/normal retention are described
below; final triangle traversal/emission still runs globally. The local option therefore does
not complete the full local-regeneration objective. In the three checked ten-road
edits, complete synchronous terrain regeneration (including point generation,
source validation, triangulation, mesh/collision construction, but excluding road
generation and image/reference comparison) measured 2631.486/2649.089/2646.869 ms
with reuse versus 2349.611/2350.642/2383.126 ms without it. Both variants used local
mode's canonical order and centering; the reference disabled incremental source
work. These pre-optimization timings recorded a total-generation regression;
the follow-up below improves it on this fixture. The option remains experimental
and off by default while final-output work is unfinished.

```sh
godot --headless --path . --script tools/check_local_topology_output.gd
godot --headless --path . --script tools/check_local_topology_output.gd -- --large
godot --path . --script tools/check_local_topology_output.gd
```

### Topology assembly costs and cache pressure

`get_source_rebuild_stats()` now includes `stage_ms`: setup, road-data extraction,
spatial support, points, main-thread triangulation, topology finalization,
filter/emission, collars, normal generation/mesh commit, publication and collision.
Worker dispatch has a separate timing; it is not the worker's execution time.
Filter timings accumulate active work across mesh-assembly frames, excluding
frame waits. A queued restart does not reset the active job's measurements.

The ten-road profile located approximately 1.25 s in collars and 1.14 s in
cached filtering/emission, versus only 0.05 s in triangulation. Built-in collars
now memoize shared sample heights during each synchronous collar call, up to
16,384 exact-coordinate keys. Nothing persists across calls/frames; custom
terrain scripts and arbitrary height modifiers retain their original quad/height
dispatch. Coordinates are reconstructed from the caller to preserve signed zero.
`collar_samples` reports reuse, evaluations and retained sample count. The focused
21-check test compares complete mesh/collision bytes with a subclass using the original
unmemoized dispatch, including curve, banking, noise and lateral-step edits,
modifier callback counts and the actual capacity boundary.

Topology source keys now use a native hash only to choose a bucket. Lookup still
compares the complete serialized input; forced collisions must miss/replace, never
return another input's result. Spatial revision IDs remain unique across collision,
eviction and clear. Other terrain-stage caches retain their original SHA-256 keys.

The old 16,384-entry limit cyclically evicted the ten-road working set: all 12,501
nearest searches and all 9,151 crossing tests were rebuilt on each local edit.
Topology now permits 65,536 smaller query records under the **unchanged 64 MiB
serialized-payload ceiling**. Other terrain-stage caches retain their 16,384-entry
limit; nearest hints remain independently limited to 16,384. This is bounded
additional retention, not constant memory or a solution for arbitrary scene size.
On the checked ten-road edits the cache retains about 37,170 records / 25.5 MiB
serialized payload, reuses about 11,282 nearest and 8,455 crossing results, and
rebuilds about 1,219 nearest and 696 crossings. Container overhead is additional.

After these changes the same isolated three-edit total-generation measurement is
1189.370/1189.314/1233.085 ms local versus 1481.280/1467.527/1487.065 ms full:
approximately **20% faster by median** on this fixture. Both paths benefit from
collar memoization. This does not demonstrate a speedup on a consuming game map,
and the small fixture can still be slower with incremental/local mode enabled.
In the default Single Mesh mode, final mesh/collision construction remains global;
triangle traversal also remains global with the optional mode below. Native
normal work can now be localized as described in the normal-support follow-up.
The output fixture additionally checks consecutive edits against an independent
full-generation node, keeping local history alive beyond idle expiry.
The final Forward+ run passes 49 checks with zero local/full changed pixels
(17,953 pixels changed by the edit). The cache-pressure suite passes 1,045 checks,
including forced hash collisions, actual 65,536-entry eviction and actual
64 MiB payload-pressure eviction. The 137-check source suite retains its original
pre-cache mesh hash and full-versus-incremental output comparisons.

```sh
godot --headless --path . --script tools/check_collar_sampling.gd
godot --headless --path . --script tools/check_terrain_cache_pressure.gd
```

### Retained final topology mesh and collision cells

`TerrainTopologyBuilder3D.output_mode = Spatial Chunks` is an additional opt-in
output mode, independent of local triangulation. Single Mesh remains the default.
`topology_output_cache.gd` receives the builder's SurfaceTool, partitions whole
triangles into XZ centroid cells with complete native normal support, and creates
ArrayMesh/concave collision resources only for changed cells. There is no complete
intermediate GPU mesh in this branch. `output_chunk_size` defaults to 64 metres;
each chunk's true AABB still contains all its triangle vertices, including
triangles spanning cell boundaries.

With incremental generation on, warm builds retain mesh nodes, mesh resources,
collider nodes and collision resources. Material-only changes update overrides
without replacing geometry/physics. A changed normal can replace a mesh without
replacing its unchanged collision. Reuse validates exact desired arrays, live
mesh arrays, face arrays, resource identity and native node state. Manual node
transforms, collider disabling, mesh-surface edits and concave-shape settings
cannot be hidden by an old fingerprint. Records refer weakly to nodes; discarded
cells and Clear release their validation state. Custom terrain scripts keep the
single-mesh path. Height modifiers still execute all source callbacks; identical
final output can be retained without replaying or skipping those callbacks.

Output roots keep the last complete generation while a real worker or multi-frame
assembly is pending. Restart captures current output settings; Clear cancels
publication and an empty final generation removes stale geometry. Switching to
Single Mesh removes chunk roots/state and restores the original hierarchy.
Generated children receive the actual edited-scene owner. The real editor check
passes 98 assertions covering warm identities, ownership, temporary scene save,
disk reload, exact mesh/collision bytes and nonserialization of runtime snapshots.

Partitioning is limited to 4,096 cells; unsupported streams/coordinates or excess
cells fall back to the complete native mesh. Retained geometry byte snapshots
have a separate 64 MiB limit; cells beyond that budget still render but are rebuilt
on later publication. Node-state/container overhead and generated output resources
are additional, not included in this byte counter. Disabling incremental work
does not retain geometry snapshots.

The three-road fixture uses 40 cells at 48 metres. Its local control-point edit
retains **24 meshes and 26 collision shapes**, rebuilding 16 meshes / 14 shapes.
Both its exact oriented position/UV/normal/face multiset and its opaque Forward+
image match the single-mesh reference: **0 changed pixels**, with 10,728 pixels
changed by the edit. Draw calls are **35 chunked versus 2 single** in that view:
this mode is not a promise of improved rendering performance. Front-face physics
rays over 20-metre segments compare actual Jolt hits on separate collision layers;
the largest observed three-road position delta is 0.0000324 m, below the test's
0.0001 m tolerance. Collision face arrays themselves remain exact. A ray from a
fixed world-up direction is not a valid hit requirement for both one-sided
`invert_faces` settings; the physics test follows each triangle's front normal.

The ten-road fixture combines a successful local triangulation with retained
final output: **87 of 105 meshes and 91 of 105 collision shapes** survive its
checked local edit. One isolated total terrain-generation measurement is
**1226.507 ms chunked local versus 1392.200 ms single full**, using an independent
uncached reference node. This is a fixture measurement, not a map-wide or general
speedup claim; publication also traverses and validates all current cells.
Point enumeration, final vertex emission and changed-output partition
traversal still need local affected-region work. Global road-integrated
terrain output is separate and the full local-regeneration checklist stays open.
The expanded output suite passes 45 checks on the ten-road headless fixture and
50 in the three-road Forward+ fixture, including modifier callbacks, actual
worker restart/cancel, mode/collision toggles and manual resource repair. The
11-check bounds suite exercises the actual 4,096-cell limit, extra vertex streams,
invalid indices/nonfinite coordinates and disabled-retention cleanup. Default
Single Mesh still passes the 137-check original source/mesh-hash regression suite.

```sh
godot --headless --path . --script tools/check_topology_output_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large
godot --headless --path . --script tools/check_topology_output_bounds.gd
godot --path . --script tools/check_topology_output_cache.gd
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-topology-output-tests
```

### Retained triangle emission runs

Certified triangle groups now retain oriented vertices/UVs and prefix offsets for
accepted vertices, winding corrections and rejection counts. The main-thread job
copies consecutive runs from these arrays. Spatial groups may interleave in the
global stream: run boundaries follow that stream, never group order. A run also
stops at the existing 256-candidate frame boundary. Rejected candidates consume
the same budget and update the same counters without emitting geometry.

Emission values share the triangle cache's existing 4,096-record/64-MiB bounds,
exact geometry/settings inputs and spatial dependency proof. No separate unbounded
snapshot store is added. A changed face orientation, old record without emission
arrays or unavailable/overflowed mesh stream uses individual triangle emission;
certified filtering/height fitting can still be reused. Native subclasses and
modifier callbacks remain on the original path. The copied `triangle_groups`
counters add `runs_reused`, `candidates_bulk` and `emission_triangles_reused` (the
last counts accepted triangles, not rejected candidates).

The ten-road edit consumes 8,175 retained candidates through 3,162 runs, emitting
7,665 accepted triangles in bulk while rebuilding 1,568 candidates. With collar
copies included, 58,848 of the 67,308 emitted vertices arrive in bulk. The isolated
five-distinct-edit comparison keeps every other cache and buffer enabled, disabling
only run replay in the reference. Total local medians are **582.215 ms with runs
versus 595.838 ms with individual triangle emission**; unchanged medians are
170.949/183.931 ms. This is a modest fixture-specific gain. Mapping candidate groups
and assembling/partitioning global output still run; this does not complete local
generation or reduce rendering draw calls.

The expanded 159-check group suite covers interleaved runs, frame budgets 1/2/4/256,
mixed/all-rejected slices, both face orientations, signed zero, shared-vertex
native normals, real entry/payload limits, immutable arrays and overflow
continuation. Existing source/worker tests pass 140 checks, including the exact
256-candidate cutoff after real warm emission. Consecutive edits pass 49, the
isolated benchmark 72, Forward+ 62 with zero changed pixels, and the actual editor
113 including emission reuse, serialization and clearing an unfinished job.

```sh
godot --headless --path . --script tools/check_topology_triangle_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --emission-benchmark
```

### Ordered local native normal support

Spatial Chunks with incremental generation and no active height modifiers now
uses `topology_normal_cache.gd`. The helper does not implement another floating-
point normal formula: it calls the same SurfaceTool native calculation on a
selected set of triangles. The upstream implementation smooths matching positions
within a smoothing group and accumulates their face contributions in triangle
order ([Godot SurfaceTool source](https://github.com/godotengine/godot/blob/master/scene/resources/surface_tool.cpp#L1078)).
This path is restricted to the native builder's unindexed, smooth-group-zero
stream; custom terrain scripts and modifier callbacks retain full native work.

An exact whole-input hit reuses completed normal/cell arrays and skips partition
traversal. For changed inputs, cell position sequences identify changed or
removed cells. Both old and new positions become dirty; every current triangle
touching any dirty position enters the native calculation, in original global
order. This includes the complete smoothing neighbourhood outside the changed
cells. Unaffected cells reuse their complete normal arrays. UV-only changes do
not recompute normals, but still update output attributes.

Unchanged cells must retain the same common global triangle subsequence, not just
identical cell-local geometry. A changed cross-cell contribution order triggers
full native calculation, as do cold/repartitioned inputs or a changed majority
of cells. This protects exact accumulation order rather than accepting a small
lighting error. Returned arrays cannot mutate the stored snapshot. Normal support
is limited to 393,216 unindexed vertices and 64 MiB of serialized snapshots, in
addition to the output cell limit; larger/unsupported input uses native fallback.
Clear, source-cache clear and editor shutdown release normal snapshots; they are
not serialized into saved scenes.

The focused suite passes **96 checks**, comparing raw position/UV/normal cells
byte-for-byte with independent full native calculations. It includes successive
shared-vertex edits, translated randomized merged/split vertices, removal and
duplicate multiplicity, degenerate triangles, UV-only changes, cross-cell order,
returned-value mutation and capacity recovery. Actual three-road and ten-road
fixtures additionally verify exact rendered mesh attributes/collision faces,
live physics, worker restart/cancel and editor persistence. Forward+ still has
**0 changed pixels**, with 10,728 changed by the edit and the same 35 versus 2
chunked/single draw calls in that view.

On the checked ten-road edit, **56,465 vertex normals are retained and 10,843
rebuilt** (counts include emitted duplicate vertices). A native patch containing
3,756 triangles replaces the full normal pass. Changed-input partition and
dependency/order validation still scan global data; this is not a fully local
geometry assembly pipeline.

The isolated five-run output-stage benchmark keeps geometry/collision retention
enabled in both variants and changes only local-normal support. Medians are
**56.937 ms cached versus 80.276 ms full-native** for unchanged input, but
**103.565 ms local versus 84.953 ms full-native** for the local edit. Thus warm
publication improves, while this edit's selection/validation overhead adds about
19 ms. The same run's complete terrain edit was **1251.967 ms chunked local versus
1381.685 ms independent single full**; this is a fixture-level result, not a
universal speedup. Source regeneration, changed partition traversal and normal
support bookkeeping remain optimization targets. Single Mesh retains its original
full native normal workflow.

```sh
godot --headless --path . --script tools/check_topology_normal_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --normal-benchmark
```

### Retained filtered and height-fitted triangle groups

Native incremental topology generation now uses `topology_triangle_cache.gd` in
both Single Mesh and Spatial Chunks output. Candidate triangles are grouped by
32-unit XZ centroid cells, split into at most 64 triangles each. The global
triangle-to-slot map preserves original evaluation/emission order and the existing
256-candidate frame budget. Misses are filled progressively, with no speculative
evaluation of later triangles. Only complete groups become persistent records.

Each record checks exact raw coordinates, all filter/height settings, configured
noise values and the exact edge-height lookup entries. Observed nearest-search,
interior-test and crossing rectangles retain ordered cell revisions, including
empty cells. Global maximum road half-width remains a dependency of nearest
safe stopping, now validated by captured native search inequalities rather than
unconditionally invalidating every mesh group on any width change (see **Local
terrain search certificates** below). Interleaved group scopes accumulate across frames; point-query
memo hits still capture support. Unsupported linear searches cannot certify reuse.
Changes to live height/filter settings during assembly disable group replay/storage
for the remainder of that job. Explicit regeneration still discards and restarts
the pending result. Custom builders and active modifiers use the full workflow.

Group records cap at 4,096 entries and 64 MiB of exact serialized payload, separate
from the source-query cap. Candidate staging caps at 262,144 triangles; oversized
or invalid streams use original filtering. Each dependency rectangle is limited
to 4,096 cells and each transient support memo to 256 rectangles. Container and
current-job staging memory are additional. Source-cache clear and Clear Generated
release retained groups; scene serialization never includes these runtime values.
`get_source_rebuild_stats().triangle_groups` exposes copied counters. Skipped
groups do not artificially increment nearest/height/crossing query counters;
triangle rejection reasons are replayed at their original slots.

The ten-road local edit retains **8,175 candidates and rebuilds 1,568**, with
259 reused and 56 rebuilt groups. An isolated five-distinct-edit benchmark uses
two independent builders with identical source/local-triangulation/output/normal
caching, differing only in triangle grouping, and alternates timed edit order:

| Total regeneration median | Grouped | Without grouping |
| --- | ---: | ---: |
| Unchanged | 547.070 ms | 1,079.575 ms |
| Local edit | 879.161 ms | 1,312.613 ms |

All five edits have exact mesh attributes and collision faces, with equal reject
counters. The three-road Forward+ test has zero changed pixels versus independent
Single Mesh output (the edit changes 10,728 pixels). Its 52 assertions include
real physics hits; the actual editor passes 100 save/reload/ownership/clear checks.
The group unit suite passes 29 checks, including actual entry/payload pressure;
31 support checks include non-exported noise changes and replacing the noise
resource. The existing 137 source checks still preserve the legacy mesh hash.
This fixture gain is not a universal speedup: the small source-suite edit remains
slower with the combined incremental pipeline. Point staging, global triangle
traversal and arbitrary modifier dependencies are still unfinished. Collar-block
construction now has its own retention, described below.

```sh
godot --headless --path . --script tools/check_topology_triangle_cache.gd
godot --headless --path . --script tools/check_topology_mesh_support.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --triangle-benchmark
```

### Retained road-edge collar blocks

Native incremental terrain now retains complete collar geometry in blocks of up
to eight consecutive row pairs within each source path. Path-local block keys
avoid shifting unrelated paths when an earlier road gains rows. Exact row-frame
and edge values, effective width/subdivision settings, height/noise settings and
face orientation form the input. Height sampling captures nearest-search spatial
support and every exact edge-height lookup, including absent entries. Sample-memo
hits also capture dependencies, so sharing an earlier block's height cannot hide
a nearby road edit. Edge heights are compared by serialized value, including
signed zero, rather than numerical equality.

`topology_collar_cache.gd` records vertices and UV input coordinates directly from
the original native emission path. Warm hits replay that same order without
repeating lateral subdivision, self-intersection/diagonal selection or sampling.
Only complete, spatially certified blocks are retained; oversized/unsupported
blocks keep native construction. Modifiers and custom terrain subclasses keep
their original callbacks. This does not change collar geometry or fix existing
seam artifacts: exact legacy output remains the reference.

The independent collar cache caps at 4,096 records and 64 MiB serialized payload.
Per-block capture caps at 262,144 vertices and 262,144 height-lookup entries;
container/current-job storage is additional. Clear Generated and idle source-cache
clearing release records; pending source-cache clearing remains deferred. Records
are value-only and do not survive scene serialization. Copied counters are exposed
under `get_source_rebuild_stats().collar_groups`; `collar_samples` now counts only
sampling actually performed for rebuilt blocks.

The ten-road edit retains **36 blocks / 11,951 collar triangles**, rebuilding four
blocks / 1,335 triangles. In a five-distinct-edit, alternating-order comparison,
both independent builders keep triangle/source/local-Delaunay/output/normal reuse;
only collar-block retention differs:

| Total regeneration median | Retained collars | Full collar construction |
| --- | ---: | ---: |
| Unchanged | 290.281 ms | 546.082 ms |
| Local edit | 665.474 ms | 911.326 ms |

The collar stage itself takes about 96 ms versus 303 ms on these edits. All five
edited outputs preserve exact mesh/collision attributes and rejection counters.
The 24-check helper test exercises exact dependencies, immutable replay, actual
entry/payload/vertex/proof limits, eviction and recovery. The expanded 46-check
collar suite compares native cached output to the legacy subclass path across
curve/bank/noise/subdivision/width/orientation/height-snap changes and warm replay,
with equal modifier callback counts. The existing 137 topology source checks pass.
The Forward+ suite passes 54 checks with zero changed pixels against independent
full output (the road edit changes 10,728 pixels). Actual editor ownership,
save/reload and Clear pass 103 checks, including non-serialization and release of
collar snapshots. The 49-check consecutive-edit/worker suite also preserves exact
mesh/collision output against an independently rebuilt reference.

Point enumeration, group/index mapping, final vertex emission and changed-output
partition traversal remain global. The first local-generation checklist item
therefore stays open; the small source fixture still has no total incremental
speedup, and these measurements are not a consuming-game-map performance claim.

```sh
godot --headless --path . --script tools/check_topology_collar_cache.gd
godot --headless --path . --script tools/check_collar_sampling.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --collar-benchmark
```

### Retained near-ring and far-grid point masks

`topology_point_cache.gd` filters blocks of up to 64 native candidate coordinates
against nearby roads. Exact candidate order, clearance, spatial-cell size, global
maximum road half-width and fallback width identify the input; captured segment
cell revisions certify the road-mask searches, including previously empty cells.
Only accepted proposals are stored. The caller still performs deduplication and
the shared point-budget checks in original priority order. A block may evaluate
up to 63 extra native candidates when a small budget ends inside it; those
proposals cannot bypass the budget or replace an earlier duplicate's coordinates.
Custom terrain and active modifiers keep original calls rather than block replay.

This cache uses the shared bounded stage store, with its own 16,384-entry/64-MiB
payload allowance and two-build idle expiry. Hash buckets always compare exact
serialized inputs; a matching bucket with changed spatial support counts as a
rebuild. Oversized blocks and uncertified linear dependencies are not retained.
`get_source_rebuild_stats().point_groups` reports block/candidate reuse, rebuilds
and storage. Public cache clearing and Clear Generated release its snapshots;
only generated scene output, not the point cache, is serialized.

On the ten-road local fixture, 61 blocks / **3,488 candidates** reuse mask results,
while 13 blocks / **832 candidates** are reevaluated. The point stage measures
about 32 ms versus 109 ms. A five-distinct-edit alternating-order benchmark uses
independent builders with all other caches identical:

| Total regeneration median | Point-mask blocks | Original point masks |
| --- | ---: | ---: |
| Unchanged | 183.538 ms | 282.863 ms |
| Local edit | 580.150 ms | 657.326 ms |

All five edits preserve exact mesh/collision attributes and triangle rejection
counters. The 78-check point suite verifies near-ring/grid/combined ordering at
11 budgets, warm replay, incoming/moved/wider roads, row reordering, returned-value
mutation, forced hash collisions and actual entry/payload pressure. Existing
137-check source regression preserves the original legacy mesh hash.
Forward+ passes 56 checks with zero changed pixels versus independent full output;
the visible edit changes 10,728 pixels. Actual editor save/reload/ownership/clear
passes 106 checks, including point-cache non-serialization and release. The
49-check consecutive-edit and worker lifecycle suite also passes exact output
comparisons without clearing the edited builder's cache history.

Near-ring coordinate enumeration, polygon boundary/support sampling, global
deduplication and index/buffer staging still run. This localizes road-mask work,
not the complete point-generation pipeline, and does not close the first local
generation checklist item. Timings are fixture measurements, not a universal or
consuming-map speedup claim.

```sh
godot --headless --path . --script tools/check_topology_point_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --point-benchmark
```

### Retained far-grid coordinate enumeration

Far-grid blocks now retain both their 64-or-fewer raw coordinates and their exact
continuation state. The cursor keeps separate double-precision X/Z values and
uses the original repeated additions; deriving coordinates from integer indices
or narrowing the cursor to Vector2 would change rounding. Bounds, step, epsilon
and starting cursor are exact input dependencies. The caller advances only while
the shared point budget permits and still evaluates/reuses road masks separately.
A moved road can therefore invalidate masks without reconstructing grid geometry.
These records share the existing bounded point-stage store and clearing lifecycle.

The fixed-bounds ten-road edit reuses all **24 blocks / 1,520 grid coordinates**.
The expanded 136-check point suite compares complete cold/warm streams with the
original loop for fractional steps, translated bounds, degenerate/inverted bounds,
signed zero, cursor mutation, budget cutoffs and deduplication. The 137 source
checks and five independent edited mesh/collision comparisons pass.
Forward+ passes 58 checks with zero pixel differences from full output; the
actual editor passes 107 checks and consecutive-edit/worker tests pass 49.

This step does **not** show a meaningful total timing gain on that fixture. The
isolated five-edit medians are 600.764 ms retained versus 595.873 ms rebuilding
coordinates, with all other caches identical; unchanged medians are
187.610/185.611 ms. The point stage is still around 32 ms in both variants.
Coordinate work is now retained, but cache validation has a cost. Near-ring and
boundary/support construction, deduplication, triangle/index traversal and final
buffer emission still need local staging; the first checklist item remains open.

```sh
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --grid-benchmark
```

### Bulk native mesh emission

`topology_mesh_stream.gd` buffers the current native job's unindexed vertices and
UVs, then transfers the arrays to SurfaceTool once. Retained collar records now
include the exact emitted UV values, so complete unchanged blocks append with
packed-array bulk copies instead of another per-vertex GDScript emission loop.
The global triangle order, face orientation and native smooth-normal accumulation
remain unchanged. This is CPU-side generation work, not rendering batching; draw
calls, output modes and material grouping are unaffected.

The stream is enabled only for the native builder with incremental generation and
no active height modifiers. Custom subclasses and modifier callbacks keep their
original workflow. The transient buffer caps at 393,216 vertices (7.5 MiB raw
vertex/UV payload, plus container/native-conversion overhead). On overflow it
replays the buffered prefix through the original immediate-mode calls and emits
the remainder natively. A mid-job `create_from_arrays()` cannot serve that
fallback: it closes SurfaceTool's begun state, preventing subsequent emission.
No stream survives completion, restart, Clear, tree exit or scene serialization.
Copied counters are available under `get_source_rebuild_stats().mesh_stream`;
`stream_flush_ms` measures the final transfer separately from triangle/collar work.
Collar UVs count toward the existing 64-MiB retained-payload bound; old records
without UVs miss safely rather than being replayed after an editor script reload.

The isolated ten-road comparison keeps all other caches identical and alternates
builder order across five distinct edits. Local edits bulk-copy **35,853 vertices
from 36 retained collar blocks**. Total regeneration medians:

| Regeneration | Buffered/bulk emission | Native individual emission |
| --- | ---: | ---: |
| Unchanged | 174.292 ms | 188.664 ms |
| Local edit | 574.077 ms | 598.051 ms |

Collar emission takes about 80 ms versus 97 ms; the final array transfer adds
about 5.6 ms. Exact mesh/collision arrays, rejection counters and winding-fix
counters match in all five edits (70 checks). This is a modest fixture-specific
gain, not evidence that regeneration is fully local or faster on every map.

The 33-check stream suite verifies both winding orders, exact raw arrays and
native normals, wrong-surface/malformed-block rejection, the real vertex cap,
overflow continuation, signed zero and clearing an unfinished stream. The collar
helper passes 26 checks including UV copy isolation and old-schema rejection;
46 legacy collar comparisons and 139 source/worker checks pass. A worker restart
test first emits a real buffered prefix, then verifies exact replacement output
and release of old/new stream storage. Consecutive edits and worker lifecycle pass
49 checks. Forward+ passes 60 checks with zero pixel differences from full output
(10,728 pixels change after the edit); actual editor tests pass 112 checks,
including save/reload, non-serialization, and Clear during an unfinished buffered
job while the previous complete mesh/collision output remains in place.

Global candidate traversal, near-ring/boundary/support coordinate construction,
ordered point deduplication, triangle/index mapping and changed-output buffer
partitioning remain. The first local-rebuilding checklist item is still open.

```sh
godot --headless --path . --script tools/check_topology_mesh_stream.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --stream-benchmark
godot --headless --path . --script tools/check_local_topology_output.gd -- --large
godot --path . --script tools/check_topology_output_cache.gd
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-topology-output-tests
```

### Direct raw-array publication

Native incremental Spatial Chunks jobs now transfer their completed vertex/UV
arrays directly to output/normal staging. They no longer populate a complete
SurfaceTool and immediately extract those same arrays again before determining
the changed normal domain. `take_arrays()` detaches the transient stream exactly
once; the transferred packed arrays remain independent of the next job.

Unchanged output and dirty-star normal patches do not materialize a complete
source SurfaceTool. Cold/repartitioned/full-normal jobs create one lazily, using
the same native normal calculation. Capacity overflow, disabled incremental
generation, modifiers, custom builders and Single Mesh retain their existing
paths. If direct chunk publication fails, the builder materializes the transferred
arrays before its complete native Single Mesh fallback; the geometry is not lost
with the detached stream. This introduces no additional retained geometry store
and does not change the stream, normal-cache or output-cache bounds.

`mesh_stream.direct_arrays` distinguishes the transfer from native flushing.
`output.source_surface_builds` counts complete source materializations (including
the builder's final fallback); native local-patch SurfaceTools are not complete
source materializations. On the ten-road local fixture the count is zero instead
of one, while the same 56,465 normal vertices and 87 mesh chunks remain reusable.
`stream_flush_ms` falls from roughly 6 ms to below 0.01 ms, but other stages still
dominate total time. In the isolated alternating five-edit comparison, unchanged
medians are **166.442 ms direct / 174.814 ms round-trip** and local-edit medians
are **590.389 / 593.779 ms**. The local total difference is small; this is evidence
of removed whole-source conversion, not a substantial overall speedup or proof
that output assembly is fully local. Both variants retain every other cache.

The stream suite passes 40 checks, including exact raw bits, signed zero,
one-time transfer, foreign-target rejection and next-job isolation. Normal tests
pass 248 checks, comparing lazy/direct and prebuilt native input over shared,
merged/split, translated, reordered and degenerate triangles. The 17 output-bound
checks include real 4,097-cell raw rejection with old output left intact and full
native fallback when local normals are disabled. Source/worker checks pass 140,
consecutive edits 49 and the isolated benchmark 81. Forward+ passes 66 with zero
pixel differences (10,728 pixels change after the road edit), including exact
Single Mesh geometry after a forced rejection of direct publication. Actual
editor save/reload, ownership and Clear pass 114 checks.

Near-ring/boundary/support point construction, global deduplication and index
mapping, and changed-output partition traversal still remain. The first local
rebuilding checklist item stays open.

```sh
godot --headless --path . --script tools/check_topology_mesh_stream.gd
godot --headless --path . --script tools/check_topology_normal_cache.gd
godot --headless --path . --script tools/check_topology_output_bounds.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --direct-benchmark
```

### Retained near-road selection and ring coordinates

Native incremental generation now selects near-road rows once for all lateral
bands. It works lazily in consecutive blocks of up to 32 rows within each path,
stopping when the current point budget is filled. Exact consumed row values,
incoming double-precision selected distance and lateral step identify the retained
selection. Invalid direction frames still advance that distance, matching the
original loop. Absolute row indices and path identities are not retained results;
the caller supplies current ordering and per-path continuation.

Selected center/right/left-width/right-width values form a separate coordinate
key with the exact ring distance. Unchanged blocks skip selection/normalization
and coordinate arithmetic; changed selection inputs can still produce reusable
coordinate blocks. Widths and continuation distances are not narrowed to packed
float32 vectors. Bands retain their original distance-first order, and every
block's at-most-64 candidates still goes through current spatial masks, ordered
deduplication and budget checks. Custom builders/modifiers keep native callbacks.
Both result types share the point cache's 16,384-entry/64-MiB/two-idle-build bounds,
clear lifecycle and non-serialized ownership; no extra persistent store is added.

In the first ten-road edit, 261 row selections are retained and 29 rebuilt;
**2,520 ring coordinates are retained and 280 reconstructed**. Path-local masking
blocks also retain 3,568 near/grid candidates and reevaluate 752 in that fixture.
The isolated five-edit comparison retains all other caches and uses the same
once-per-job selection/block layout in both variants, disabling only cross-job
near selection/coordinate retention in the reference. It does **not** demonstrate
a clear timing gain: total local medians are 566.411 ms retained versus
562.051 ms rebuilt, unchanged medians 158.240/159.411 ms. Both point stages are
around 29 ms. These numbers are not a before/after comparison against the old
per-band traversal, nor a consuming-map performance claim.

Repeated independent-builder edits exposed a real input change: unchanged paths'
final sampled distances alternated between 108.267562866211 and 108.106674194336.
The existing sampler reads baked length before applying its own bake interval;
road/terrain generators sharing a Curve3D can therefore supply different endpoint
distances. The selection cache conservatively reevaluates those blocks, while all
2,520 unchanged coordinates still survive. This change does not normalize that
source behavior or remove the distance dependency, which could alter legacy
sampling and budget results.

The expanded point suite passes 180 checks: native bit equality over fractional
widths/distances, invalid frames, interleaved/reordered paths, changed defaults,
all existing point-budget cases, immutable results, hash collisions, real shared
capacity limits and changed endpoint distances with reusable geometry. Source and
worker regression passes 140 checks; consecutive edits/worker lifecycle pass 49.
The isolated output benchmark passes 78 checks, Forward+ 68 with zero pixel
differences, and the actual editor 115 including warm retention, save/reload and
Clear. Boundary/support coordinate construction, global source-row validation,
point dedup/index mapping and output partition traversal remain; the first local
rebuilding checklist item stays open.

```sh
godot --headless --path . --script tools/check_topology_point_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --near-benchmark
```

### Retained outer bounds, contours and boundary-support coordinates

Native incremental point staging retains outer-rectangle coordinates in their
original paired X-then-Z order, using the exact double-precision continuation
cursor. Polygon contours are grouped into at most 16 consecutive edges, with
64-or-fewer emitted coordinates per result. A long edge carries an integer
subdivision cursor across results; polygon closure and repeated endpoints keep
the original sequence. Group hits skip edge-length/subdivision/interpolation work.

Boundary-support coordinates retain exact edge endpoints, subdivision count,
outward direction, distance array and linear sample/distance cursor. Outward
direction is still determined from current road probes before replay; accepted
support proposals use the existing spatially validated road-mask blocks. No
dependency on a moved/incoming/wider road is silently dropped. Plain contour
coordinates do not even add a zero offset, preserving native signed-zero bits.
All branches retain current ordered deduplication and point-budget checks; native
custom-builder/modifier paths remain unchanged. The records share the existing
16,384-entry/64-MiB point-stage store and its clearing/serialization lifecycle.

The ten-road local edit reuses **198 outer-boundary proposals and 1,056 contour
proposals**, reconstructing 116 contour proposals. These are raw proposals,
including repeated endpoints, not final deduplicated vertex counts. Isolated
five-edit medians with every other cache identical are **566.493 ms retained /
570.156 ms rebuilt**, with unchanged medians 158.142/161.736 ms. The point stage
is around 30/32 ms. This is a small fixture-specific gain, not a broad speedup.
The earlier per-edge-cache prototype was replaced with 16-edge groups after its
lookup overhead made this comparison slower (577.575/569.893 ms local medians).
The ten-road performance fixture uses collars, so it does not measure support
point performance; support correctness is exercised separately with collars off.

`check_topology_boundary_points.gd` passes 373 checks over fractional/translated/
degenerate bounds, long edges, multi-distance support order, block transitions,
signed zero, cache mutation/hash collisions, point budgets and changed road masks.
The expanded source suite passes 146 checks, including exact full mesh/collision
comparisons with support points enabled, warm replay and a local edit without
collars. Consecutive edits/worker tests pass 49; the isolated output benchmark
passes 80. Forward+ passes 70 with zero changed pixels against full generation
(10,728 pixels change after the edit); actual editor ownership, save/reload and
Clear pass 116 checks. Stats expose `bounds_coordinates_*`, `edge_coordinates_*`
and `support_coordinates_*` under `point_groups`.

This retains native contour/support coordinate construction, not all terrain
work. Source sampling/validation, current support-direction probes, global point
deduplication and index mapping, and changed-output partition traversal remain.
The complete local-rebuilding checklist item therefore stays open.

```sh
godot --headless --path . --script tools/check_topology_boundary_points.gd
godot --headless --path . --script tools/check_topology_source_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --boundary-benchmark
```

### Retained native source-path samples

`topology_path_cache.gd` now retains the sampled rows of unchanged native paths
when the aggregate road signature changes. The original per-path baked-length
read and subsequent bake-interval assignment remain in their original order.
Rows are keyed by exact serialized Curve3D data, closed/up-vector/bake settings,
the pre-bake length, native sampling controls, transforms, frame-provider/default
settings, live width/lane values, transition-curve data and resolved height
profiles. The native lane interpolation offsets are checked too. This does not
substitute a deferred lane-dependent revision for current lane extents.

Only plain Path3D and the exact bundled profile script are eligible. Custom path,
curve, transition or network scripts bypass path reuse; builder subclasses and
active height modifiers retain the existing complete fallback. Native network
scripts are resolved relative to the addon, without a preload cycle. Source-path
IDs are not retained: copied rows receive the current collection's IDs before the
existing polygon/segment assembly. Returned rows and nested profiles cannot
mutate the stored snapshots.

This is a separate value-only store with a 512-entry / 64 MiB payload cap and
four-idle-generation expiry. Other terrain stage stores keep their two-generation
expiry. Four generations allow both exact pre-bake-length variants of a shared
road/terrain Curve3D to survive intervening unchanged builds. Neither length is
rounded or ignored. Whole-collection cache hits touch current path entries so
ordinary warm generations do not expire all the samples before the next edit.
Disable, explicit cache clearing, editor Clear and exit release this store;
pending explicit clear is applied at the existing safe restart boundary.

`get_source_rebuild_stats().path_samples` reports `paths_reused`, `paths_rebuilt`,
`rows_reused`, `rows_rebuilt`, `uncacheable_paths`, `collection_reused`, entry count
and retained bytes. A whole-collection hit does not claim per-path resampling work.
The ten-road fixture retains nine paths / 261 rows and samples one path / 29 rows
after the exact variants are warm. Encountering the second shared-curve length
for the first time correctly requires another full set of samples.

An isolated five-edit comparison with every other cache identical passes 84
checks. Median local regeneration is **562.875 ms retained / 568.568 ms rebuilt**;
unchanged generations are 157.438/159.603 ms. The source stage after both variants
are populated is approximately 14-15 ms versus 17-20 ms. This is a small,
fixture-specific total improvement, not a general performance guarantee. An
earlier isolated run gave 571.421/574.142 ms local medians. The two-generation
expiry prototype discarded alternating variants too early; the final four-idle
policy is covered by explicit repeated-edit reuse assertions.

The dedicated path suite passes 70 checks, including all three native frame
modes, adaptive sampling, asymmetric lanes, in-place transition/profile changes,
explicit deferred-lane invalidation, source removal/reordering, transforms,
closed/up-vector settings, alternating pre-bake lengths, custom callbacks,
mutable results, forced hash collisions, capacity, idle expiry and clear. Every
collection is compared byte-for-byte with an uncached collection started from
the same pre-bake intervals. The source/worker suite passes 146 checks including
the captured legacy mesh hash; consecutive edits and worker restart pass 49.
Cache-pressure regressions pass 1,045 checks. Forward+ output passes 71 checks:
zero pixel differences against full generation, 10,728 pixels changed by the
edit, and matching live physics hits. Actual editor tests pass 119 checks,
including nonserialized path snapshots and Clear releasing them.

This only avoids resampling unchanged whole paths. Changed paths still sample
fully; aggregate signatures, source validation, polygon/segment assembly, ordered
point deduplication, global index mapping and changed-output partition traversal
remain. It changes neither draw-call batching nor the default output mode. The
complete local-rebuilding checklist item remains open.

```sh
godot --headless --path . --script tools/check_topology_path_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --path-benchmark
```

### Retained source contours/segments and owned native collections

Path entries now include each path's ordered contour and assembled segment
dictionaries, not just its sampled rows. The exact dependency key from the prior
step covers these values too. Replay copies the stored value graph and assigns
the current path ID to both rows and segments; no cached global array indices
are introduced. Missing assembly fields fall back to native assembly. Uncached
and custom-callback paths still run the original sampling and assembly sequence.

The ten-road local edit retains **nine polygons and 252 segments**, rebuilding
one polygon and 28 segments, alongside 261 retained / 29 rebuilt sampled rows.
The extra values share the existing path store's 512-entry / 64 MiB cap and
four-idle-generation lifetime. After both shared-curve variants are warm, the
fixture retains approximately 1.05 MB of path payload versus approximately
0.52 MB with rows alone. The additional memory is explicitly accounted for by
the same bounded store; there is no second contour/segment cache.

Native `_collect_road_data()` now hands off an owned collection without an extra
whole-collection deep copy inside `_get_cached_road_data()`. Fresh native rows
explicitly detach their height-profile dictionaries and packed Inspector arrays
before assembly. Replayed rows/segments are already deep copies of the retained
entry. This distinction matters: the first copy-elision prototype failed the
existing worker/Inspector test because fresh profiles still borrowed mutable
arrays. The corrected implementation passes that test. Builder subclasses keep
the defensive full collection copy, and `regenerate()` still freezes a separate
snapshot for the worker in all modes.

The dedicated suite now compares collection and assembly byte-for-byte against
`tools/fixtures/topology_source_legacy.gd`, an independent copy of the pre-cache
collection loop. It passes 86 checks, including returned contour/segment/profile
mutation, duplicate source paths with separate IDs, vertical paths whose contour
exists but whose XZ segment list is empty, row-only record fallback, borrowed
subclass collections, and fresh Inspector-array isolation. The complete source
suite again passes all 146 checks, including its original mesh hash and editing
then restoring Inspector arrays while a worker runs.

The final implementation also passes 49 consecutive-edit/worker-restart checks,
72 Forward+ output checks (zero differing pixels against full generation, 10,728
pixels changed by the local edit), and 120 actual editor checks covering complete
source snapshots, scene ownership, save/reload and Clear. Native physics hits
still match the full reference within the existing 0.0001 m tolerance.

New `.path_samples.segments_reused`, `.segments_rebuilt`, `.polygons_reused` and
`.polygons_rebuilt` counters distinguish assembly from sampling. The isolated
`--assembly-benchmark` keeps row reuse enabled in both builders and disables only
assembly retention in the reference, verifying equal mesh/collision output and
equal reused-path counts across consecutive edits.

The isolated benchmark passes 88 checks. Its five-edit medians are
570.286/575.318 ms for local regeneration and
164.225/161.947 ms unchanged (retained/rebuilt assembly). There is no clear
source-stage speedup: after warm-up that stage measures approximately 12-13 ms
retained versus 11-12 ms rebuilt, because copying the larger retained value graph
also costs time. The small total difference must not be advertised as a broad
performance gain. This benchmark isolates assembly retention; both sides use the
corrected owned-collection handoff, so it does not separately measure copy elision.

Changed paths still sample/assemble fully. Global source signatures, spatial
validation, point deduplication/index mapping and changed-output traversal remain
outside this reuse step; full local rebuilding remains unfinished.

```sh
godot --headless --path . --script tools/check_topology_path_cache.gd
godot --headless --path . --script tools/check_topology_source_cache.gd
godot --headless --path . --script tools/check_topology_output_cache.gd -- --large --assembly-benchmark
```

### Spatial-index experiment rejected; degenerate nearest search fixed

A prototype retained the cell memberships of 64-segment/path-local and
64-polygon-edge groups in the existing bounded path store. It preserved bucket
insertion order and remapped all current global IDs. The ten-road local edit
retained memberships for 252 segments and 522 edges, rebuilding 28 and 58, and
the isolated output comparison passed 88 checks. However, the five-edit medians
were **577.550 ms retained / 573.000 ms native**, with warm medians
162.506/159.252 ms. Serialization, lookups and remapping cost more than the saved
rectangle-to-cell work on this fixture. The prototype and its benchmark switch
were removed; production keeps the native index construction and all existing
source-cache bounds. These figures document a rejected experiment, not an
optimization currently available in the addon.

The experiment exposed an existing infinite loop when the indexed segment list
was nonempty but every segment had a degenerate XZ projection. No candidate could
set a finite best distance, so the expanding nearest search never satisfied its
distance-based stopping proof. It now returns an empty result after every indexed
segment has been tested without finding a candidate. Valid searches retain the
original spatial stopping proof: returning early merely because all old segments
have been visited would be unsafe for future roads outside a cached search ring.

Empty results are not stored as bounded nearest hits, and they invalidate the
current mesh dependency scope. A new valid road outside the old empty search area
must still be found. This also covers transitions from a valid cached source to
all-degenerate sources and then to a new valid source with a different path ID.

`check_topology_spatial_index.gd` passes 153 checks over fractional cell sizes,
local endpoint and width edits, height changes, inserted/reordered/removed paths,
empty/all-degenerate sources and subsequent distant valid sources. Cell and bucket
order are checked independently; indexed nearest queries are compared with full
linear search, and indexed crossings with full polygon-edge traversal. The
all-degenerate case was reproduced as a hanging process before the fix and now
completes in the normal test run.

After removing the prototype, the complete source suite passes 146 checks,
consecutive edits/worker restart pass 49, and Forward+ output passes 72 with zero
pixel differences versus full generation (10,728 pixels change after the local
edit). The final implementation contains no spatial-membership cache or new
persistent cache allocation.

This is a robustness fix, not completion of local source indexing. Global source
validation and index construction still remain in the local-rebuilding work.

```sh
godot --headless --path . --script tools/check_topology_spatial_index.gd
```

### Automatic editor dependency order

The integrated editor test exposed a real ordering defect: topology could start
sampling while the road was still waiting for its editor debounce. Both native
generators set the shared Curve3D bake interval, so grounded props could finish
with slightly different transforms after Undo or compared with a full build.

`RoadNetworkCreator3D.is_road_generation_pending()` now includes queued automatic
edits as well as active workers. Automatic topology generation waits for resolved
road sources, including sources found through path ancestry, before sampling.
The terrain pending API also includes queued editor edits, so ground queries and
props cannot consume that intermediate state. Manual-only generators do not
advertise a future automatic rebuild. Explicit regeneration remains explicit;
this is not a general scheduler for custom generators or arbitrary manual order.

`tools/check_incremental_workflow_editor.gd` opens the actual markings demo,
constructs a second distant path, chunked terrain and grounded mesh props, then
enables automatic generation after fixture setup. Native editor history changes
a control point; no manual road/terrain/prop regeneration occurs between the
edit, Undo and Redo. Each output must change, Undo/Redo must reproduce exact mesh,
collision and transform snapshots, and distant node/resource identities must
remain intact. A separately constructed, cache-disabled full reference must
match all three outputs. The saved demo is never modified.

The initial normal and threaded-road/reversed-node-order runs passed 24 checks.
The latter also verifies that dependents need not follow the road in scene order.
Reported edit time includes the 500 ms stability window and editor frame pacing;
it is a correctness-test elapsed time, not a regeneration benchmark.

```sh
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-incremental-workflow-tests
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-incremental-workflow-tests --workflow-threaded --workflow-reverse-order
```

This closes the automatic-propagation gap for the basic two-path fixture, not the
entire local-rebuilding item. The junction variant below extends its coverage;
neither fixture establishes performance on a consuming game map.

Regression reruns after this change: terrain/prop lifecycle 31 checks, grounded
prop cache 85, topology source/worker 146, large consecutive edits/worker restart
49, and actual editor chunk ownership/save/Clear 120. Forward+ chunk output passes
72 checks with zero pixel differences against the full reference (10,728 pixels
change after the edit); the fresh render was also visually inspected.

### Integrated junctions and both prop render modes

The `--workflow-junctions` variant adds two branches at each original path start,
creating two separated three-way fans. Native editor history moves the first
control point at the near junction. It must rebuild one junction and reuse the
other, while updating the road, lane markings, topology and ground-snapped props.
The identity snapshot explicitly covers each of road, terrain and prop output.
For MultiMesh it includes the batch node, MultiMesh resource and source mesh;
geometry comparison includes the actual instance buffer and bounds.

With `--workflow-capture`, a real Forward+ subviewport renders the edited scene
throughout the same automatic workflow. Initial/Undo and edited/Redo/full-reference
image data must be byte-identical, not merely within the changed-pixel threshold.
The normal Individual run and the threaded-road/reversed-order MultiMesh run each
pass 43 checks. The edit visibly changes 309 and 304 pixels respectively (RGB
threshold 0.02); full-reference comparisons report zero and pass exact byte
equality. The fresh images were inspected. The saved demo is untouched; captures
are written under `/tmp/roda-workflow-junction-*.png`.

In this fixture, one path / 98 road rows rebuild while five paths / 286 rows are
retained. Topology retains five paths / 102 rows and rebuilds one / 50 rows; prop
placement retains 25 placements and rebuilds 25. Individual output reuses 25 nodes;
MultiMesh reuses six buffers and rebuilds seven. The independent junction geometry
regression also passes 164 checks, including overlapping midpoint welds, fan/pair
changes, path reorder/removal and global fallback behavior.

```sh
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-incremental-workflow-tests --workflow-junctions --workflow-capture
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-incremental-workflow-tests --workflow-junctions --workflow-capture --workflow-multimesh --workflow-threaded --workflow-reverse-order
```

### Remaining road surface cost: measured baseline

`benchmark_road_mesh_stages.gd` uses a timing-only subclass of the native road mesh
builder, without replacing any geometry algorithm. Ten roads, five distinct local
edits and spatial mesh/collision output compare full and incremental source modes.
The original timing harness reported 10 checks, but its inherited snapshot helper
looked at the empty root mesh in Spatial Chunks mode. That was insufficient proof
of chunk geometry equality. The timing samples remain measurements; the corrected
chunk/shape comparison described below replaces that incomplete correctness gate.

An isolated run measured these medians in milliseconds:

| Mode | Complete road update | Source rows | Mesh construction | Surface normals |
| --- | ---: | ---: | ---: | ---: |
| Full source generation | 282.285 | 141.492 | 41.571 | 30.035 |
| Incremental source generation | 185.721 | 42.905 | 41.763 | 30.267 |

Normals are included in mesh construction, which is included in the total; these
columns are not additive. The cached mode retains 6,917 rows and rebuilds 413,
but both modes still process 131,940 normal vertices across surfaces per edit.
Thus source reuse already helps this fixture, but normal generation remains a
full-surface operation and takes about 16% of the incremental total. This is a
baseline identifying the next implementation target, not a newly enabled normal
cache or evidence that the full local-rebuilding item is complete.

```sh
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd
```

### Indexed normal reuse: implementation and verification

`road_normal_cache.gd` is now used by the road mesh builder under the existing
default-off Incremental Generation option. It retains ordered vertex-to-triangle
adjacency, face cross products and raw output normals. Exact float32 words are
compared in blocks of 256 vertices; signed zero is not silently equated. Changed
positions invalidate their incident faces, and those faces invalidate their
vertices. Fallback normal edits also invalidate affected vertices. Native winding,
degenerate-face rejection, accumulation order and upward-normal flipping remain
unchanged. Callers receive detached arrays so flipping cannot mutate the cache.

There are at most five surface stores, each capped at 131,072 vertices, 262,144
triangles and 12 MiB of packed payload (60 MiB across five stores, excluding small
container overhead). Native full computation handles capacity and nonfinite input
fallbacks. Non-float32 vector layouts bypass reuse. On a change to an existing
index layout, adjacency is discarded and that layout must repeat before it is
seeded again; a series of different topologies does not repeatedly build unused
adjacency. Cold/admission builds still have preparation cost, and dense changes
are not promised a speedup. Disabling incremental generation or using the public
source-cache clear releases the stores. Per-surface counters are exposed under
`get_source_rebuild_stats().surface_normals`.

The initial per-vertex input checker was slower than full normal generation
(77.689 ms normals, 237.089 ms total in the first prototype). It was replaced by
native packed-block comparisons. Final isolated comparisons keep incremental
source rows active in both variants and change only normal reuse:

| Normal calculation | Whole road update | Mesh construction | Normal stage |
| --- | ---: | ---: | ---: |
| Forced native full normals | 185.945 ms | 41.600 ms | 29.931 ms |
| Incremental normals | 166.069 ms | 22.364 ms | 9.970 ms |

These are five-edit medians for the existing ten-road fixture, not a consuming
map guarantee. The whole update is about 10.7% faster; normals are about 66.7%
faster. Of 131,940 surface-normal vertices, 125,290 are retained and 6,650 rebuilt
in the final sample. The three stores retain 7,385,772 bytes of packed payload.
The original comparison reported 25 checks with reuse enabled and 10 with native
normals. Its surface snapshot had the empty-root gap noted above; normal correctness
was separately covered by the independent normal suite and actual editor images.
The later corrected benchmark checks the generated chunk meshes and shapes.

The independent normal suite passes 189 checks: repeated local edits, changed
index order/count, disconnected coincident vertices, degenerate/invalid faces,
fallback edits, signed zero, mutation isolation, nonfinite/capacity behavior,
topology admission and public clear/disable. Existing source/worker regressions
pass 91, junction geometry 164 and all six stored mesh baseline hashes match.
Runtime chunk/bake checks pass, retaining 19 of 25 chunks after the local edit.
Both integrated editor variants pass 43 checks with byte-identical Undo/Redo/full
images (309 edited pixels for Individual, 304 for threaded/reversed MultiMesh).

```sh
godot --headless --path . --script tools/check_road_normal_cache.gd
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --full-normals
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd
```

This removes a measured full-surface normal rebuild for stable indexed layouts;
it does not close the full local-rebuilding item. Source/spatial validation,
complete surface upload and output partitioning remain, and changed index layouts
deliberately use the full fallback until admitted.

### Direct CPU surfaces for spatial output

Incremental Generation plus Spatial Chunks now sends the road's existing CPU
surface arrays and ordered materials directly to the chunk publisher. Previously
the same arrays were uploaded into a complete temporary ArrayMesh first, although
`GeneratedSplineRoadWelded.mesh` is intentionally null in this mode. The temporary
resource is now only a CPU-data carrier; only actual chunk meshes are uploaded.
Single Mesh and disabled Incremental Generation keep their native uploaded mesh
behavior. No extra persistent cache or user setting is introduced.

The CPU carrier records nonempty surface slots in exactly the original order.
Normal-cache slots use this CPU count rather than the carrier's zero GPU surface
count. Material references are carried separately, preserving lane/shoulder/
sidewalk/terrain/wall routing even when some surfaces are empty. Partitioning
continues to use pre-encoding CPU normals, avoiding an extra quantization pass.
Output metrics now separate `partition_ms` and `publish_ms` and expose actual
`source_surface_uploads` and `cpu_surfaces`.

`check_road_direct_output.gd` passes 243 checks over all 32 empty/nonempty surface
combinations, three cell sizes, exact partition arrays/order, material routing,
empty output, Single Mesh and disabled incremental mode. The incremental runtime
suite also passes complete-vs-chunk attributes/collisions, material replacement,
mode changes, saved bake reload and physics probes. Its five source surfaces now
incur zero temporary uploads; the local edit retains 19 of 25 chunk resources.

The benchmark has been corrected to traverse `GeneratedRoadChunks` and compare
every actual mesh array and concave collision face set by stable node path. It
also requires a nontrivial output snapshot, so an empty template can no longer
pass. Both native and CPU-carrier modes use the same input changes and normal
cache settings. The `--full-mesh-upload` flag retains the previous upload path for
controlled measurements; it is a test-only switch.

Fresh isolated five-edit medians, with source and normal caches enabled on both
sides, are 170.261 ms with the temporary upload and 165.129 ms with direct CPU
output (about 3.0% lower total time). Mesh construction falls from 24.290 to
18.073 ms. Both corrected benchmark variants pass 40 checks, including actual
chunk arrays and collision faces. Three temporary source surface uploads become
zero; this is a construction/upload optimization, not a draw-call reduction.

The Forward+ single/chunk/baked rendering regression also passes with incremental
generation enabled and explicitly checks that the chunk path uploads no temporary
source surfaces. Both image comparisons report zero changed pixels, with 15,013
foreground pixels; the fresh baked image was inspected. Draw counts remain 6 for
Single Mesh and 86 for chunks/baked output in this fixture.

The integrated editor variants passed 45 checks, explicitly distinguishing the
CPU-only local route from the native uploaded full reference. An initial run hit
the old 20-second test deadline; subsequent frame telemetry measured 22–23 editor
frames taking about 22 seconds. The correctness harness now uses a bounded
60-second deadline and reports frame counts. It does not change production
scheduling, and editor elapsed time is not used as the optimization benchmark.

```sh
godot --headless --path . --script tools/check_road_direct_output.gd
godot --headless --path . --script tools/check_road_runtime_output.gd -- --incremental
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --full-mesh-upload
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd
```

This eliminated an unnecessary global upload. The initial stage split measured
about 76–78 ms in partitioning versus 12–13 ms publishing the chunks, leading to
the following partition optimization. The full local-rebuilding item remains open.

### Road partition cell reuse

With Incremental Generation and Spatial Chunks enabled, `road_partition_cache.gd`
retains each indexed surface's completed cell arrays. Exact 256-vertex blocks
compare position, normal and UV bits. Changed triangles invalidate their old and
new cells; position changes recalculate their centroids, while normal/UV-only
changes keep centroid assignments. Unchanged cells skip index remapping and array
construction. Original triangle order, first-use vertex remapping and dictionary
cell insertion order are preserved, including cell merges, splits and removals.
Returned arrays are detached from retained state. Material references are still
applied by the publisher, outside this geometry cache.

Changed indices, vertex counts or chunk size trigger a complete new partition.
Malformed/unsupported input or capacity overflow bypasses reuse. If any surface
bypasses, the complete independent native partition is used, stores are released,
and statistics do not claim partial reuse. The road's public source-cache Clear,
empty output, disabled incremental generation and Single Mesh release the stores.
At most five stores are retained, each limited to 131,072 vertices, 131,072
triangles, 4,096 cells and a conservative 16 MiB retained-payload estimate. The
estimate includes input words, indices, triangle-cell records and cell arrays;
it is not allocator overhead, transient copies or peak process memory.

Fresh isolated five-edit medians on the ten-road fixture, with identical source,
normal and direct-output settings, are:

| Partition mode | Whole regeneration | Partition stage | Publish stage |
| --- | ---: | ---: | ---: |
| Complete native partition | 163.321 ms | 75.772 ms | 12.451 ms |
| Retained cell arrays | 107.951 ms | 23.871 ms | 12.338 ms |

This is about 34% lower total time on this fixture, not a consuming-map FPS claim.
The three surfaces reuse 271 cell arrays and rebuild 20; 2,952 of 58,560 triangle
centroids are recalculated. Their combined conservative retained-payload bound is
13,740,672 bytes. Input validation, triangle classification, complete CPU source
assembly and final output fingerprinting still run globally. A sampling/topology
change can require full partition reconstruction even when most published mesh
resources remain unchanged, as the runtime fixture demonstrates.

Validation:

- `check_road_partition_cache.gd`: 163 checks, exact native bytes/order, local and
  block-boundary edits, cell merges/splits/migrations, signed-zero bit changes,
  consumer mutation, incomplete index tails, empty inputs, every capacity bound,
  five-slot ownership, whole-native fallback and clearing/disable.
- `check_road_direct_output.gd`: 435 checks, including cold/warm cached partitions
  for all 32 empty/nonempty band combinations at three chunk sizes.
- Both isolated benchmark variants compare actual chunk arrays and collision
  faces by node path: 60 retained-partition checks and 40 native-reference checks.
- Incremental runtime/bake: attributes, materials, collisions, unchanged resource
  identities, public Clear, mode changes, saved reload and real physics hits pass.
- Road normal regressions pass 189 checks, source/worker regressions pass 91,
  and all six legacy full-mesh hashes remain unchanged.
- Actual threaded/reversed-order MultiMesh editor workflow: 45 checks, automatic
  edit/Undo/Redo and full-reference geometry, byte-identical comparison images.
  The edit changes 304 visible pixels; full-reference comparison changes zero.
  The fresh edited image was inspected. Editor timing is not the benchmark above.

```sh
godot --headless --path . --script tools/check_road_partition_cache.gd
godot --headless --path . --script tools/check_road_direct_output.gd
godot --headless --path . --script tools/check_road_runtime_output.gd -- --incremental
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --full-partition
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd
```

`--full-partition` is a benchmark-only override. No new user option or default
change is introduced, and this does not change draw calls or Forward+ instancing.
The full local-rebuilding checklist item remains open.

### Road path assembly reuse

Stage profiling after the partition optimization found another global cost:
assembling indices and row dictionaries still consumed about 30 ms despite most
source cross-sections being unchanged. Each eligible immutable source-path entry
now optionally retains the completed lane/shoulder/sidewalk indices and pre-weld
row metadata. A local edit rebuilds its path assembly, while unchanged paths skip
this construction. Changed-path 64-row source blocks continue to reuse their
existing sampling calculations independently of whole-path assembly.

The source entry itself certifies identical positions, widths, frames and lane
data. A separate exact assembly key includes path ordinal, global vertex base,
resolved endpoint snapping/midpath/strip settings, face winding and marking mode.
Changing earlier path lengths can shift later global indices and therefore
requires those assemblies to be rebuilt, even when their source rows are reused.
Adaptive distance changes, reorder/removal, transforms and custom dynamic scripts
retain their original invalidation/bypass behavior. Gap-closing curb triangles
and native row-direction calculation are unchanged.

The sampler no longer deep-copies every field of a source snapshot on every hit.
Packed vertex/normal/UV streams are appended by value; nested edge arrays and
marking dictionaries are copied at the assembly mutation boundary. Returned
cached assemblies are deep-copied, so welding or downstream consumers cannot
modify either retained assembly or pre-weld source rows.

At most one assembly per retained native source path is kept, with a per-path
16,384-row limit and a shared 32 MiB serialized-payload budget. This budget covers
assembly results and keys, not the already-existing source-block cache, allocator
overhead, temporary copies or peak process memory. Excess paths use native
assembly without retention. Removed/empty sources, disabled incremental mode and
public source-cache Clear release these entries. No new user-facing option is
introduced; the benchmark-only `--full-source-assembly` flag disables this store
while leaving source-row, normal and partition reuse enabled.

Fresh isolated five-edit medians for ten roads with otherwise identical settings:

| Assembly mode | Whole regeneration | Source stage | Assembly stage |
| --- | ---: | ---: | ---: |
| Complete native assembly | 108.964 ms | 43.949 ms | 30.654 ms |
| Retained unchanged-path assembly | 93.572 ms | 28.869 ms | 15.095 ms |

This is about 14% lower total time on this fixture. Nine complete path assemblies
(6,597 rows) are reused and one (733 rows) rebuilt; the retained serialized payload
is 5,043,800 bytes. It is not a consuming-map FPS or draw-call claim.

`check_road_path_assembly.gd` passes 95 checks against a frozen pre-change native
assembler: exact bytes/order, output mutation, consecutive edits, changed global
index bases, winding/weld settings, path overrides, curb gaps, markings,
transforms, removal/Clear/disable, custom callbacks, real aggregate byte pressure,
per-path row limits and recovery. Source/worker regressions pass 91 checks,
junction geometry 164, and all six legacy mesh hashes match. Incremental
runtime/bake checks pass attributes, materials, collision geometry and actual
physics hits. The threaded/reversed-order MultiMesh editor workflow passes 45
checks, including automatic edit/Undo/Redo, exact full geometry and byte-identical
comparison images. The edit changes 304 visible pixels; the full-reference image
comparison changes zero, and the fresh edited image was inspected.

Both benchmark modes compare actual generated chunk arrays and collision faces
by node path (60 native-assembly / 65 retained-assembly checks). Parallel
correctness runs are not used for the timing comparison.

```sh
godot --headless --path . --script tools/check_road_path_assembly.gd
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --full-source-assembly
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd
```

Complete changed-path assembly, packed source concatenation, dependency
validation/classification and dependent topology work remain. The full local
rebuilding checklist item is still open.

### Local terrain search certificates

The real editor workflow exposed an overly broad dependency: its local curve
edit changed the global maximum projected road half-width from
7.69994767904282 to 7.69998898506165. This search bound was embedded in every
triangle/collar input key, invalidating all 216 triangle groups and all 22 collar
groups even when their geometry and nearby source cells were unchanged.

The bound is no longer a blanket mesh-input identity. Each captured mesh scope
now also records the actual native nearest-search stopping inequality and
interior-search radius tests. Reuse requires those tests to remain valid at the
current global width, alongside the existing exact geometry/settings/edge-height
and ordered cell-revision checks, including empty cells. The nearest check repeats
`distance_to_unsearched - current_width >= best_edge_distance` in its original
floating-point order. Radius checks repeat the original ceiling calculation.
No road widths, vertices or height samples are rounded or quantized, and native
search traversal, tie handling and output ordering are unchanged.

Nearest point-memo hits capture the proof too. Query-cache hits reconstruct it
from the exact matched result and current ring: a hint alone is not a result
identity and may have been replaced by another generation. Missing/unsupported
proofs bypass reuse. Tests explicitly cover a far-away road becoming wide enough
to replace the previously nearest road: the old proof is rejected and the new
result matches complete linear search.

Scopes admit at most 4,096 search certificates, each four float64 values; overflow
prevents retention. The additional arrays are counted inside the existing 64 MiB
serialized group budgets, not a new unbounded cache. Existing Clear/disable and
worker-restart behavior remains. The triangle/collar stats now expose `misses`
split into absent entries, changed inputs, failed scopes and collar edge heights.

In the actual threaded/reversed-order MultiMesh editor workflow, the local edit
now reuses 103 triangle groups / 2,036 candidates and 11 collar groups / 4,672
triangles. All 45 checks pass: automatic dependent updates, Undo/Redo, distant
resource identities, full-reference geometry and byte-identical comparison
images. The edit changes 304 pixels; the full-reference comparison changes zero.
The fresh edited image was inspected.

A separate isolated six-road/two-junction benchmark compares the new certificates
with a strict-width reference that retains the previous global invalidation rule.
Both modes otherwise use the same source caches and record the new proof data;
this isolates the reuse decision rather than timing two unrelated implementations.
Five-edit terrain-generation medians are:

| Width validation | Total terrain | Filter/height/emit | Collars |
| --- | ---: | ---: | ---: |
| Strict global-width equality | 1,268.369 ms | 624.643 ms | 472.799 ms |
| Local search certificates | 927.361 ms | 415.490 ms | 325.318 ms |

The total is about 27% lower on this fixture, not an FPS or game-map claim. Each
edit compares actual terrain surface arrays and collision faces against an
independent uncached terrain generator. Its incoming shared-curve bake intervals
are restored to the same values before reference generation. Both runs pass
(5 strict / 10 local checks). The final local sample retains 103 triangle groups
and 12 collar groups; fixture sampling differs slightly from the editor run.

Mesh-support tests pass 59 checks, including exact threshold boundaries,
sub-float32 width changes, safe/unsafe outside-source widening, replaced hints,
the actual certificate capacity and malformed proofs. Triangle groups pass 159,
collars 26, spatial indexing 153, and source/worker regressions 146 with the
original full-terrain hash preserved.
The runtime chunk-output regression also passes 66 checks, covering actual
geometry/collision reuse and lifecycle behavior.

```sh
godot --headless --path . --script tools/check_topology_mesh_support.gd
godot --headless --path . --script tools/benchmark_topology_search_proofs.gd -- --strict-width
godot --headless --path . --script tools/benchmark_topology_search_proofs.gd
```

Changed geometry/dependencies still reconstruct their groups. Global source
validation, point/index assembly and triangulation fallbacks remain; the full
local-rebuilding item is still open.

## Incremental road paint construction

`road_marking_builder.gd` now reuses completed paint buckets in blocks of 32
consecutive row pairs under the existing road Incremental Generation opt-in.
Each block includes its shared boundary row. Its exact serialized input covers
distance, lane extents/layout, the actual welded surface vertices, geometry
settings and the path's complete ordered junction exclusions. Global vertex
renumbering alone does not invalidate identical paint; exclusion-order changes
do, preserving the native polygon clipping and triangle order. No coordinates
or dash phases are rounded. Material/color changes apply fresh materials without
repeating clipping, hatching or paint emission.

Private completed bucket arrays are immutable and appended by value into the
current combined output. Retention is limited to 4,096 blocks, 131,072 emitted
vertices per block and an estimated 32 MiB aggregate payload (serialized keys,
32 bytes per vertex and per-entry allowance). This is not an allocator/process
or peak-memory bound: old/new records and final output coexist during a build.
Capacity bypass runs native construction. Removed blocks are released at the
next build; public source Clear and disabling markings/incremental mode clear
the store. The final combined marking mesh is still recreated and uploaded.
This optimization does not change output chunks or draw-call behavior.

`check_road_marking_cache.gd` compares actual mesh arrays, surface order and
materials against a frozen native row-loop reference. It covers all five styles,
lane transitions, banked surface edits at shared block boundaries, dash phase,
exclusion ordering, mutable input dictionaries, color/material-only changes,
consumer mesh mutation, vertex rebasing, removal, reduced-capacity fallback and
public clear/disable lifecycle. Existing marking conformity tests still pass.

The actual threaded, reverse-order MultiMesh editor workflow passes **47 checks**:
the junction edit retains 10 paint blocks / 217 pairs and rebuilds 6 / 161,
using 739,160 estimated retained bytes. Undo/Redo and independent full-reference
geometry/images match exactly; the edit changes 304 rendered pixels, full versus
incremental changes zero.

The ten-road stage fixture now optionally enables real paint and compares its
actual arrays/materials in addition to chunk meshes and collision faces. Across
five edits it retains 218 blocks / 6,940 pairs, reconstructs 12 / 380 and retains
14,013,920 estimated bytes. Cached/native-paint runs pass 90/85 checks with all
other caches held alike. Observed medians were 79.406 versus 590.991 ms for paint
and 195.034 versus 712.937 ms for total regeneration. These are **non-isolated
observations**, not a controlled speedup claim: the user's separate Godot editor
and game were running and were left untouched. Correctness runs did not overlap
these measurements. No consuming-map FPS conclusion follows.

```sh
godot --headless --path . --script tools/check_road_marking_cache.gd
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --markings --full-markings
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --markings
```

Lane-material overlays and documented triangulation fallbacks remain the next
construction costs in the open local-rebuilding audit.

## Incremental lane-material overlay rows

Lane overlays now reuse blocks of 64 pre-index rows, using the existing road
Incremental Generation opt-in. A complete native source key skips dependency
sampling on unchanged paths. Changed paths validate each block's native spline
support, exact lane extent/width, distance, transforms and lift before replaying
positions, fallback normals and UVs. Frame distances are clamped exactly as in
`get_path_surface_frame`; width/layout queries receive the original float32
distance. Explicit width dependencies include disabled lane profiles, which can
still publish a per-lane overlay width. Custom path scripts bypass caching and
retain native callback execution.

The row loop is extracted without changing its calculations. Global row/triangle
order and inter-block seam indices remain native. Materials are routed every
build and are not baked into the geometry key. Winding changes reuse row data
but regenerate the index order. A separate mesh builder retains indexed normals
without overwriting the main road's normal-cache slots; it uses the existing
normal-cache limits and exact incident-face accumulation order.

The additional row store caps at 4,096 blocks and an estimated 32 MiB payload.
Its accounting includes exact path/block keys, packed attributes, float64 lane
width differences and an entry allowance; repeated shared path keys are counted
conservatively. This is not a peak/process-memory bound, and the independent
normal caches have their own limits. Capacity overflow falls back to native row
construction. Public source Clear, disabled incremental mode, removed paths/slots
and empty overlay output release the corresponding retained row records.
Final concatenation, index assembly and combined mesh upload remain global.
No new setting or draw-call optimization is introduced.

`tools/check_lane_overlay_cache.gd` passes **91 checks** against a frozen native
path-strip loop: actual mesh arrays and material identities, all orientation
modes, tilt, mirrored/nonuniform transforms, asymmetric/legacy widths, in-place
easing/layout edits, winding, lift, UV scale, sampling, material replacement and
mutation, sparse slots, source reorder/removal, custom callbacks, reduced cache
limits, public Clear and disable. Reference generation reads the same live
path inputs: cloning a profile would run its initialization synchronization and
could alter raw legacy width storage before comparison.

The real threaded, reverse-order MultiMesh editor workflow with `--workflow-lanes`
passes **49 checks**. Its local junction edit retains 18 blocks / 858 rows and
rebuilds 6 / 294; 244,656 estimated row-cache bytes are retained. Each of three
overlay surfaces retains 572 indexed normals and rebuilds 196. The edit changes
459 pixels, while Undo/Redo and independent full-reference rendering match exact
image bytes. Runtime bake/reload/native physics, all six baseline geometry hashes
and the 103-check paint-cache suite still pass.

The ten-road fixture observes actual overlay arrays/materials plus road chunk
meshes/collisions. Five local edits retain 226 blocks / 13,834 rows, rebuild
14 / 826 and check dependencies on 1,466 rows. Estimated row retention is
3,469,680 bytes. The paired runs pass 80 cached / 75 native-row checks, with
other source, normal and output caches held alike. Observed medians: 47.519 versus
265.181 ms for overlays, 149.209 versus 366.562 ms total. These measurements are
**not isolated** from the user's other open Godot editor; no correctness tests
overlapped them, but they are not a controlled map-performance claim.

```sh
godot --headless --path . --script tools/check_lane_overlay_cache.gd
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --lanes --full-lanes
godot --headless --path . --script tools/benchmark_road_mesh_stages.gd -- --lanes
godot --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-incremental-workflow-tests --workflow-junctions --workflow-capture --workflow-multimesh --workflow-threaded --workflow-reverse-order --workflow-lanes
```

The common editor terrain case still reports `cocircular_ambiguity` and uses
complete triangulation. Its safe-local scope and fallback behavior remain the
next audit item before claiming completion of local rebuilding.

## External circle-tie cavity expansion

The editor's `cocircular_ambiguity` fallback came from a near-cocircular point
outside the candidate patch. Instead of accepting an uncertified triangle or
immediately using full triangulation, the cavity now includes that point's
incident triangles and reruns the native patch with the original relative point
order. The existing boundary loops, edge multiplicities, used-point checks,
empty-circle checks and eight-attempt bound still apply. No point coordinates,
native tie rules or tolerance values change. Hull changes, input reordering,
conditioning changes, capacity, degeneracy and exhausted expansion still fall
back to native full triangulation, including the owner's worker path.

This only affects the existing experimental `local_triangulation_enabled`
option, which remains off by default. `external_ties` counts outside tie
candidates; `expansions`, `local_calls`, `triangles_reused/rebuilt` and `fallback`
report the actual outcome. A nonzero tie count is not itself proof of success:
require an empty fallback and retained triangles. In the deferred API,
`full_calls == 0` alone does not exclude a full call by the terrain owner.

The six-road fixture's first edit now retains 2,904 unfiltered triangles and
reconstructs 1,252, resolving three outside ties in four native patch calls and
five expansion steps. All five edits match both the complete native unfiltered
triangle set and actual independent full terrain mesh/collision output. The
controlled old-behavior switch `--strict-ties` reproduces the immediate full
fallback on the first edit. Cached/strict runs pass 20/15 checks respectively.

The actual threaded, reverse-order editor with MultiMesh and per-lane materials
passes **50 checks**, including genuine local tie resolution, distant resource
identity, automatic propagation, Undo/Redo and full-reference images. Its first
edit retains 2,902 triangles and rebuilds 1,252 (slightly different native source
sampling from the synchronous fixture); image differences against full remain
zero, with 459 pixels changed by the edit itself.

This change improves locality, **not the measured first-edit latency**. Paired
observations were 46.553 ms for the old fallback versus 127.001 ms for expanded
local triangulation on that edit. Five-edit medians were 58.996/59.691 ms for
triangulation and 911.028/914.303 ms for the complete terrain rebuild (old/new).
Repeated GDScript patch validation costs more than the native full call here.
The user's other Godot editor remained open, so these are non-isolated fixture
observations, not map/FPS claims. Correctness runs did not overlap measurements.

The cavity suite additionally covers larger interior-edit grids, near-grid
jitter, multiple scales, translated/centered inputs and native fallback parity,
while preserving the earlier random-test sequence with a separate stress RNG.
It passes 800 checks with 543 successful local patches; observed native fallbacks
include hull/conditioning changes and uncertified circles. The ten-road actual
output/worker/modifier regression passes 49 checks, source/worker checks 146 and
triangle-group checks 159. Their concurrent correctness-run timings are not used
as performance evidence.

```sh
godot --headless --path . --script tools/check_local_delaunay_cavity.gd
godot --headless --path . --script tools/check_local_topology_output.gd -- --large
godot --headless --path . --script tools/benchmark_topology_search_proofs.gd -- --strict-ties
godot --headless --path . --script tools/benchmark_topology_search_proofs.gd
```

Global input inspection, canonical index ordering and combined mesh publication
still run; this is not a promise that every arbitrary edit can be local or faster.
