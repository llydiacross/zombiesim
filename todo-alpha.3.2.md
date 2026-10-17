# Alpha 3.2 - Phased Implementation Plan

**Status: ACTIVE - MOTORWAY LIVE CHECKS ACCEPTED 2026-10-17; TWO CORRECTED BSPs STAGED AND WIRED; 336 CURRENT PREVIEW CELL MATERIALS/THUMBNAILS REFRESHED; STALE EDGE2 MATERIALS REMOVED; TARGETED SKYLINE FOOTPRINTS STAGED WITH TEMPORARY MODEL ALIASES; CELL HEALTH BATCH CONTROLS IMPLEMENTED; FOCUSED FIXTURES PASS; USER CONFIRMS CONTROLS VISIBLE/LEGIBLE AND SKYBOX WARNING CLEARED; NO BATCH STARTED; WORLD GENERATOR PAUSED; FULL-WORLD OUTPUTS DEFERRED; PHASE K/L CLOSURE DEFERRED; NOT RELEASED.**

## Current status - 2026-10-17

**Read this section before the dated implementation evidence below.** The user
accepts all live motorway gate/alignment checks and the current CSM checks for
now. This does not accept all of Alpha 3.2 or Phase J's complete runtime/output
integration. Dated sections below retain their checkpoint-specific status;
this 2026-10-17 snapshot supersedes older "pending" wording where it differs.

### Motorway and CSM acceptance

The user reports that all motorway gates work and the motorway pieces are
perfectly aligned in game. The same-map reload and read-only report for
`zz_preview_efee87b69fff-v1` confirmed both west triggers published,
`W_any`/`W_highway`/`W_road` available, and the west marker unblocked. The
server fixtures pass12/12 and GLua syntax passes277/0. This is user-confirmed
live acceptance; do not reopen alignment or require mathematical proof.

The user reports that CSM works fine and accepts its checks for now. No new
performance, lifecycle, or multiplayer measurements were made in this update.
Keep the documented technical limits deferred; do not resume CSM work unless
requested.

### Two-map staging and runtime-index update

The user-approved comparison BSPs `zz_preview_74c1b0c24754` for cell(22,18)
and `zz_preview_a30b0e90c7e2` for cell(17,4) are staged in both
`content/maps` and Garry's Mod `maps`, with hashes matching their isolated
build outputs. Staging did not clean other maps. A separate targeted runtime
map-name update followed.

`update_preview_runtime_map_names.ps1` generated the runtime map-name overlay:
only cell IDs113 and454 now point to the two staged names. It verified profile,
grid/seed, topology, entrances, gate directions, VMF/layout freshness and BSP
hash equality. The output changed only those two `cells[].map` fields; all
other cell data and the existing `mapManifestSha256`/`templatePlanSha256` were
preserved. The focused `test_preview_runtime_map_names.ps1` passes7 assertions,
and its generated candidate is byte-identical to the staged runtime JSON. A
hash-verified pre-update runtime JSON is retained beside the isolated corrected
BSPs for rollback. GMod remained closed at this staging checkpoint; a later
runtime load and skyline-manifest follow-up are recorded below. The previous
live motorway acceptance remains recorded separately.

This is a temporary two-cell routing update, not a full plan export. The full
corrected plan still contains27 recipe-name differences; only the two approved
targets are active. The existing revision hashes stay on the current
skybox/capture revision until the later all-map export. The user has paused
generator work; do not activate the other recipe changes now.

**Runtime skyline follow-up (2026-10-17):** after the new map names were loaded,
`cl_skybox` reported a missing footprint for `zz_preview_a30b0e90c7e2` on cell
validation. The targeted updater now emits both the runtime-index candidate and
a matching skyline candidate. The skyline candidate uses current VMF/layout
hashes, water sides and bounds for the two corrected names; recipe, snow, tower
and detail model arrays temporarily reuse each replaced recipe's existing
models. This avoids a broad skyline rebuild while the generator is paused.
Staged manifest validation covers all576 runtime cells, and the focused updater
regression passes9 assertions. A fresh same-map reload of
`zz_preview_9a00023600b3` completed; the user confirms the console warning is
gone. Exact new skyline models remain for the later all-map export.

### Preview cell materials and map thumbnails

Rendered the current 336-recipe base plan and the two corrected-cell plans,
then staged the runtime-specific set: 334 unchanged base-plan images plus the
two corrected map images for logical IDs113/454. All336 staged PNGs decode at
1728x1728 and their hashes match the render outputs. The active preview runtime
map-name set matches the staged filenames exactly. After that verification, all
336 stale `-edge2` cell images were removed.

Rebuilt preview map-browser thumbnails from the staged cell images. All336
preview cell thumbnails now match the runtime map names; the original preview
launcher thumbnail was restored and its hash verified unchanged. The existing
16 `map_layers` files had no `-edge2` names and were left unchanged. Satellite/
world-photo output and navmesh-backed cell wireframes remain deferred until
after the Cell Health Manager and full-map navmesh work. Temporary material
render folders were removed after staging to avoid duplicate copies.

No plan/runtime revision hashes, VMFs or BSPs changed during this material
refresh. GMod remained closed at this materials checkpoint, so the refreshed
materials and thumbnails were not live-loaded or visually reviewed then.

### Cell Health Manager and batch controls - 2026-10-17

`zombiesim_dev_cell_health` opens the preview-admin 24x24 logical-cell grid.
The scan uses non-empty `maps/<map>.nav` files, current-map identity plus basic
PNG signature/header/end-marker checks for both clear and atmospheric photos,
and no revision hashes. Cubemaps are initially `UNVERIFIED`; a user Yes after
manually running `buildcubemaps` and reloading the current map is persisted in
`garrysmod/data/zombiesim/cubemap_confirmations_preview.json` per preview BSP
name and displayed as `USER CONFIRMED`, not engine-verified. A No clears any
prior record, leaves the map incomplete, and continues.
The current capture manifest still names the old recipes for logical IDs113
and454, so those two photos remain incomplete until refreshed and imported.

The manager now has **START BATCH OF UNHEALTHY CELLS** plus unchecked-by-default
navmesh, world-photo and cubemap options. The client selection is server
recomputed from the same Cell Health contract. The union rule includes a cell
if any checked artifact is missing; each cell carries only its missing
selected work. Navmesh/cubemap work is deduplicated by map; photos stay per
logical cell. A single durable `ZM_WorldCapture` queue performs nav generation,
save, fresh reload and validation before the same cell's photos. It never runs
screenshots concurrently with native nav generation. The user runs
`buildcubemaps` manually from the native console; no Lua, bridge or external
input automation is used.

Partial photo imports now merge only valid previous images whose manifest map
name still matches the current runtime cell, replace freshly captured cells,
and drop stale map-name entries. The Satellite manifest remains incomplete
until both variants cover all576 cells. After a photo run completes and player
restoration is verified, the existing watcher
`bin/watch_world_capture.ps1 -RunId "<run-id>" -StagePreview` imports/stages
the images. Navmeshes remain in Garry's Mod `maps` until the separate navmesh
staging command runs.

Focused checks pass: Cell Health contract6/6; world-capture client7/7 and
server11/11; photo importer6/6; runtime/skyline updater9/9; GLua syntax281/0.
The latest source was loaded with a same-map reload of
`zz_preview_9a00023600b3`; a separate status request confirmed the preview
profile and same map afterward. The user confirms the controls are visible and
legible, the skyline warning is gone, and the live client suite passes7/7. No
batch has been started, so native navmesh, photo batch, cubemap and restoration
behavior remain unverified in-game.

### Next scope

The manager is ready for the user to start a selected unhealthy-cell batch.
All options default off; **do not start a batch unless the user presses Start**.
When a photo run completes, use the existing watcher to merge/stage its
captures; keep full-world generator revisions and other large output work
paused until separately approved. Previous Phase K/L closure remains deferred
and is not a prerequisite.

### Lessons for future agents

- Ordinary road drift came from replacing canonical 5x5 road slots with
  measured motorway-mouth placements. Do not add per-cell offsets, half-tile
  placement or road-mouth fitting; preserve the 640-unit road grid and use
  motorway leases only to reserve/suppress occupied slots.
- The west-gate refusal came from a geometry-center comparison that overruled
  world-data connectivity. A missing-route default did not fix the live
  failure. Keep `ZM_World`/`CanTravelToNeighbour` authoritative and keep
  geometry checks out of route access. See the implementation rule in
  [AGENTS.md](AGENTS.md).
- Do not reopen user-approved motorway alignment or demand mathematical
  proofs. The user's in-game visual acceptance is the acceptance evidence for
  alignment.

### Phase J lease-aware on-ramp road slots - 2026-10-16 (two layouts approved; isolated compile, staging and two-cell runtime mapping complete)

The normal complex planner now starts ordinary road branches from its canonical
5x5 tile placements and trusted motorway leases, not measured road mouths. When
an on-ramp road slot is leased by the motorway core, the on-ramp tile keeps its
authored yaw and moves to the outermost available 640-unit core road slot. If
the core branch has no remaining road slot, it becomes the first border
continuation; later roads continue in whole640 steps. Motorway-owned core road
slots are suppressed instead of emitting a second road instance over them.
Motorway assembly origins/yaws and motorway gate records are preserved.

The refreshed seed-1337 plan contains576 cells/336 recipes/96 motorway
contracts. All96 motor assembly arrays match the trusted plan, all480 ordinary
cell tile-placement arrays match, no road continuation is off the640 grid, and
the focused planner/VMF regression passes1058 assertions. In the user examples,
Cell(22,18) places `tile_road_onramp` at core slot(2,4); Cell(17,4) places it
at east slot(4,2) and west border slot(-1,2). Two complete-infill comparison
VMFs are under `generated/phase_j_grid_road_review_corrected/src`; the user
visually approved both. The user-edited reference VMFs under
`generated/phase_j_grid_road_review_focus/src` are preserved and must not be
overwritten. Isolated VBSP/portal preflight and fast VVIS/VRAD complete2/2,
with0 failures/incomplete stages and0 over-budget/invalid portal files. The
two BSPs from
`generated/phase_j_grid_road_review_corrected/build` were staged on 2026-10-17
to `content/maps` and the engine `maps` directory. SHA-256 matches the isolated
builds; `-MapsOnly` ran with cleanup disabled. The user's live motorway review
is accepted, and the two names are now wired to their logical cells by the
map-name-only runtime update described above. The full plan's other recipe
changes remain inactive while generator work is paused.

A previous broad motorway-only VMF emission stopped at recipe
`zz_preview_63daaa0c6288` (cell6,23), which has no unobstructed terrain tile for
the player start. It was not compiled, staged, or retried after this correction;
full-world VMF/compile acceptance remains pending. Do not reuse the earlier
ordinary-road `+640` shifts. The user has paused world-generator work; do not
retry this emission or start a broader refresh while that pause is in effect.

The user's live den check reported invalid map route data on
`zz_preview_efee87b69fff-v1`. After reload, the console identified the actual
veto as `Loaded gate does not match planned map data W`; the missing `route`
field was not the remaining blocker. Gate availability now uses
`CanTravelToNeighbour`/`ZM_World` exits only. Removed trigger-center validation,
the invalid-measured-gate state, and the runtime route default.
`motorwayGates` is an optional lookup for marker/arrival presentation, not a
travel requirement. The west-center-mismatch regression passes; server
transition fixtures pass12/12 and GLua syntax passes277/0. A same-map reload
completed in preview. The subsequent read-only gate report for
`zz_preview_efee87b69fff-v1`, logical cell18,6, shows both west lane triggers
published, `W_any`/`W_highway`/`W_road` available, and the west marker
unblocked. No new west center-mismatch log appeared. The user subsequently
confirmed that all gates work and motorway alignment is perfect, accepting the
live motorway checks.

### Phase J trusted-plan and lane-gate source update - 2026-10-16 (focused checks pass; no world outputs refreshed)

After the user-authored ramp `func_detail` edit changed face IDs, the active
refresh no longer calls `build_motorway_preview.ps1` or remeasures motorway
geometry. `bin/reuse_approved_preview_plan.ps1 -ValidateOnly` confirms the
same seed/grid and exact prior placements:576 cells,336 recipe names,96
approved motorway contracts (69 straight,27 complex) and214 reused directional
gate records (192 motorway,22 ordinary-road). It removes only the final
`-edge2` suffix, retains `-oceanw`, removes stale source fingerprints and the
insertion-seam spawn candidate, and verifies that tile placements, origins,
yaws, leases and grid shifts remain identical. The migrated plan and
required-map list have now been written. The installed runtime export hashes do not match
the current plan/manifest hashes. Cell-ID reconciliation finds eight stale
recipe names only on ordinary cells without `motorwayGates`; topology and
entrances agree for all576 cells. All96 current motorway assembly cells have
matching prior runtime gate records and active directions. Those eight
ordinary map names are not reused; the new runtime export will be regenerated
from the migrated plan.

The VMF writer now splits each motorway direction into two lane-tagged
triggers, one per carriageway; saved gate positions and the256 arrow/384 inward
arrival offsets are retained. Ordinary-road gates remain single and unchanged.
Runtime and client fixtures cover separate lane markers, legacy combined
markers, route colours and the 384-unit arrival. Checks pass: PowerShell parse,
56 lane-gate assertions, server transition fixtures13/13, client marker
fixtures11/11, GLua277/0, trusted-plan dry validation and `git diff --check`.
The user authorized the full preview VMF/skybox/runtime refresh, 339-map
compile and map-only staging on 2026-10-16. The full refresh is now underway.
Navmesh, Satellite/material capture, production and live visual acceptance
remain outside that authorization. The previous compile above does not contain
the new lane-specific trigger layout and is not Phase J acceptance. Motorway
alignment remains a visual in-game review, not a mathematical proof.

### Phase J refresh progress - 2026-10-16 (compiled; staging/visual pending; not accepted)

The user-authorized current-source refresh regenerated the seed-1337 preview
manifest and measured motorway assembly report. The matching plan contains576
cells,336 unique city recipes,96 motorway assembly contracts and3 reusable
safe-room maps (339 required maps). The user-labelled Cell15,11 (plan grid
14,23) selects a straight `roads/tile_road.vmf` center, the east road ramp and
the bridge continuation; it no longer inserts a crossjunction on the straight
route. East `onramp-e` motorway cells17,10 and6,23 carried a640-unit northward
shift in this earlier output; the newer lease-aware on-ramp road-slot
correction above supersedes that placement rule. The Army Base landmark cell
23,19 now uses `tiletemplates/army` for all three fallback building slots.

Focused checks pass: bridge-ramp layout12, Army pool9, on-ramp shift20 and
complex gates234. The full complete-infill measurement completed, and the
initializer preserved all existing artist-owned infill sources. Complete VMF
emission finished for336 recipes (335 refreshed,1 retained); required VMFs
pass336/336. Visibility preflight covers339 maps with0 over-budget and0 missing
or invalid portal files. Incremental VVIS/VRAD covers all339 required maps:
33 compiled,306 skipped as current,0 failed,0 incomplete. No skyline-model
refresh, runtime export, staging or live/visual review has run for this refresh.
This is not Phase J acceptance. Ask before further expensive skyline/material/
staging work; do not run navmesh or full Satellite capture without separate
approval.

The CSM caster filter now skips `models/zombiesim/skybox/` before model-mesh
measurement, clears stale skybox failure entries, and disables any matching
runtime entity while sun CSM is ready. GLua277/0 and the focused offline CSM
fixture suite pass. The fresh GMod session is still at `zn_preview_start`; the
bridge requires an admin in a generated cell, so no live CSM/foliage visual
check has occurred.

### Normal wide-motorway cell integration approved - 2026-10-15

The normal planner now emits every complex/mixed wide-motorway cell (schema-2
`motorwayAssembly` contracts, status `normal_complex_travel_pending`) from the
measured assembly report; plain straights keep the schema-1 reservation path.
All 27 complex/mixed cells of the matching preview world were built through
the normal generator (`build_motorway_cell_preview.ps1 -NormalComplex
-SkipInfill`, output `generated/phase_f_normal_complex_quick`). Excluding
infill, every previously approved fixture cell is instance-identical: 17,0;
13,18; 6,23; 15,23; 15,14; 6,7; 6,0; 17,2; 6,3; 17,4 (15,18 differs only
because its old fixture was the synthetic T). The user reviewed the four new
cells in Hammer++ and approved them: 0,7 ocean-west deadend, 12,7 on-ramp
south, 23,18 deadend west and 15,18 real crossroads.

Binding rules retained: normal road slots stay on the 5x5 grid and are never
moved; on-ramp/corner joins use native corner/768-straight/corner doglegs;
no bend connector pieces; standalone on-ramps stay as generated. The earlier
road/on-ramp shifts came from per-brush mouth matching, not ground-tile grid
placement, and were reverted. Remaining motorway geometry corrections are
**user-owned in Hammer**, not generator work. The synthetic T-junction is
explicitly skipped (the preview world contains no real T). Infill was skipped
for the quick review by request; the measured/complete infill pipeline is
already accepted and runs in the full batch. Full planning now requires
`-MotorwayAssemblyReport` whenever the world has complex motorway cells.

The Phase J source refresh and incremental compile are recorded above. Runtime/
skyline/materials, staging and visual review remain pending; ask before further
long processing. Phases K and L remain later. Ask before navmesh refresh or a
full Satellite capture.

### Resumed source work - normal straight core reservations

The user confirmed that there are no ordinary rectangular building assets;
physical/live validation of those helpers is deferred until they supply one.
Do not fabricate a building or block density/motorway delivery on that review.
CSM and its deferred backlog remain outside the immediate release work.

Normal `Get-CellTilePlacements` now reserves a plain wide straight's full
three-tile corridor before density decoration selection. Both orientations use
the same stripe constructor as accepted inspection: five owners, ten suppressed
slots, exact physical origins and ten remaining scenery slots. Legacy1x1
settings and ordinary roads retain their paths. Unexpected frame, orientation,
connections or canonical yaw fail explicitly.

Two fresh isolated recipes were generated through the **normal planner**, not
`-MotorwayCellInspection`, under `generated/phase_e_normal_straight_20261014`.
Each has25 slots, five wide emitting owners and ten suppressed records, with no
inspection metadata. The retained fixture manifest is legacy: that small output
does not demonstrate new density zoning. Production-helper density fixtures
separately exercise hard-tier decoration selection outside the reserved lanes.
Suppressed records retain the owner's repeated dimensions through planner
defaults; the actual builder ownership validator covers this contract.
Fresh motorway1082, density2633 and rectangle555 assertions pass; safe-zone
entrances retain12 orientation/water and2 rejection fixtures.
Normal VMF emission remains explicitly blocked by the existing inspection guard
until rings/gates/runtime are integrated; passing core planning is not a playable
preview or acceptance of Phase E. No compiled/staged/live output changed.

### Normal straight ring ownership slice

Normal straight plans now carry `motorwayAssembly` independently of diagnostic
`motorwayCellInspection`:27 exact core/border/outer leases, four ring owners,
the approved physical origins and a source fingerprint. Status explicitly
remains `normal_reservations_travel_pending`. This currently covers the accepted
inland plain-straight scope, not coast/den/landmark or complex arrangements.
Expanded rings must be enabled explicitly; an unexpanded normal plan now fails
rather than silently building a wide core into narrow boundaries.

Boundary wall-density adjacency consumes these normal leases. The builder's
ring resolver displaces only leased pieces and inserts the four approved wide
owners; protected neighbouring walls/corners retain their records and yaws.
Source fingerprint and shared ownership validation precede replacement. Layout
metadata preserves the normal contract when playable emission is enabled later.
The existing normal-wide builder guard still prevents compilation/emission
until measured gates/runtime travel are complete.

`build_motorway_cell_preview.ps1 -NormalPlanOnly` provides a repeatable isolated
expanded-settings check without legacy remapping, inspection emission or compile.
Fresh output under `generated/phase_e_normal_straight_rings_20261014` contains
two normal recipes, each with27 leases/four ring owners and no inspection tag.
It uses the retained legacy two-cell manifest: not new density-zoning evidence.
Fresh motorway1300 and density2633 assertions pass; ring fixtures cover all
56 input boundary slots in both orientations, preservation, stale-source
rejection and competing normal/inspection ownership. Editor diagnostics and
static checks remain distinct from compiled/live acceptance.

### Source-measured straight gate lanes

Normal straight assembly metadata now includes two source-measured gates.
Saved floor windings at sides120/126 and342/384 define the current canonical
straight carriageways:416 units each at deck68, centres-512/+528 in authored
coordinates. The older registry's252/258 references do not exist in the current
straight source; the straight-only registry was corrected without touching
the authored VMF, bridge mapping or approved geometry.

Gate derivation rotates those measured mouths through both normal orientations,
checks their border-stripe ends reach2240, and records actual lane extents,
arrow positions256 inward of gate2208 and arrival positions384 inward.
N/W lateral centres are-512/+528; S/E are-528/+512 in outward-right coordinates.
These asymmetric values must not be replaced with legacy+/-160 or a symmetric
nominal width. Source hash, flat contiguous floor mouths, matching deck and
approved finite border origins are validated; source/deck/boundary corruption
fails without a guessed fallback.

Fresh normal plans under `generated/phase_e_normal_straight_gates_20261014`
contain all four cardinal gate records across the two recipes. This is
source/plan evidence only: gate brushes, barricades, network marker lanes and
runtime arrival consumers are not yet switched to the new records. The normal
builder guard remains in place. No compile/staging/live changes ran.
Fresh motorway1352 and density2633 assertions pass; editor diagnostics and
status/highlight-order/whitespace checks pass.

### Measured gate geometry consumed by the VMF writer

Normal straight gate selection now remeasures the current source and compares
the planned gate records before use; mismatched lanes or active entrances fail
explicitly. The VMF writer consumes source-derived asymmetric opening extents
for its trigger brush (1456 across,64 deep), raises the existing112-high trigger
by the measured deck difference32, and serializes the arrival landmark at the
selected carriageway's1824-inward-axis position/Z72. The ordinary road's native
Z36 deck-relative placement is retained rather than guessed from the median.

The existing four car/glass barricade composition now translates onto the two
measured carriageway centres for normal straights, preserving relative offsets,
models, yaw and vertical placement. Legacy gates retain256x64 triggers and
their exact old barricade values. This is a source-writer change behind the
normal-wide emission guard: runtime marker/arrival integration is still pending,
so no normal wide VMF/BSP was emitted or staged.

Fresh motorway1405/density2633 assertions pass, including all four cardinal
trigger extents, lane-edge containment, legacy dimensions/props, actual landmark
serialization, stale gate records, extra active entrances and inspection
no-gate isolation. Compiled collision and human barricade placement remain
part of the approved later playable-preview batch, not verified by these tests.
Fresh entrance `-FixturesOnly` passes12 orientation/water and2 rejection cases.
The full entrance suite stops on normal-wide planning because root settings
still disable expanded rings; its whole-preview baseline was not verified.
This is the explicit integration guard, not permission to enable production
settings or silently fall back to narrow motorways. Full-plan checks belong
to the isolated expanded-profile batch.

### What has actually been completed

**Complex travel preparation:** junction geometry approval is now explicit:
the user reviewed the refreshed crossroads and synthetic motorway T and found
no issues. This accepts those fixtures, not normal Phase E/live integration.

`Get-ZMComplexMotorwayGates` now measures candidate trigger/arrow/arrival
positions against saved flat source-floor windings, using a recorded source
coordinate frame rather than treating overview coordinates as cell-local.
Sources are hash-checked before and after measurement; missing support, gaps,
nonflat motorway mouths and stale inputs reject explicitly. Floor parsing is
local to each call and shared across samples, not repeated per rendered frame.
The helper preserves inspection status and does not authorize normal emission.

Ordinary-road gates use the existing arrow96/arrival128 inward spacing on the
south corner dogleg (live travel review pending). Its measured gate is `(0,-2720,36)`, arrow `(0,-2624,36)`
and arrival `(0,-2592,36)`; all remain on the centred approach before its turn.
Other motorway lanes retain256/384 insets. Runtime and VMF trigger helpers now
distinguish one-lane `road` metadata from two-lane motorway metadata, including
shared-map route/count rejection and unchanged native road barricades.
Fresh server markers12/12, client10/10, GLua275/0, motorway1529 and seven
whole-cell3436 pass. Runtime consumer fixtures are not a staged/live check.

The full density plan has69 plain straights and27 complex/mixed motorway cells.
Canonical standalone on-ramp approaches still include off-axis ordinary-road
mouths (single512 and one dual256), unlike the approved mixed1408-unit route.
Their ramp mouths also sit off the640 road grid (1920 from centre,960 to the
edge), so native corner/straight pieces cannot centre them. Generated bend
connectors were tried and rejected by the user on2026-10-15; never create bend
pieces and never move normal road positions. The user chose to leave standalone
on-ramps as they are for now and continue normal integration;
do not silently shift approved mixed owners or apply an incompatible connector.
Normal complex reservations/emission/export and the playable preview remain
unfinished. No installed BSP, runtime index or survivor state changed.

**Fresh junction coverage:** the matching retained full density plan contains
four `motorway-crossjunction` cells, zero `motorway-tjunction` cells and172
ordinary `road-tjunction` cells. The motorway T whole-cell fixture therefore
remains explicitly synthetic; do not claim it occurs in that generated world.
After the user raised coverage, the existing seven-cell current-source suite
was refreshed under `generated/phase_e_junction_cell_verification_20261014`:
3436 assertions and7/7 required VMFs pass, including byte-identical repeated
generation and exact physical owner/source/lease checks. Its obsolete negative
assertion that all mixed layouts must reject was updated to reject only a
missing measured transport case, preserving route-loss protection.
The exact crossroads and synthetic motorway T now both pass fresh VBSP,
portal budgets and VVIS/VRAD (preview fast preset, one compiler, zero failures
or incomplete stages). These are complete-cell diagnostic fixtures, not normal
generator/runtime gate integration or in-game acceptance. Other five cases
were structurally tested, not recompiled in this junction-only batch.

The user approved the corrected corner after terrain cleanup and explicitly
confirmed its missing infills are expected. All four mixed arrangement reviews
are now satisfied; retain that corner infill exception without reopening it.

**Latest mixed-layout correction:** the user chose to retain all four combined
layouts, then corrected bridge dominance and both ordinary-road ramp approaches.
Deadend/bridge assemblies now place the bridge at `(0,0,0)` and translate only
the terminal's frame around its exact measured seams. South/north terminals
are `(0,1280,0)` / `(16,-1280,0)`. Both ramp layouts keep every wide owner/yaw/
origin unchanged and snake from the central side-entry through two ordinary
corners and one768-unit straight section. The extra128 units were explicitly
approved to avoid shifting the motorway pieces. A source initializer creates
the editable connector once; saved-floor validation protects width256/deck36
and exact joins. Boundary mouths are centred, never based on ramp lateral1408.
The new `ordinaryRoadApproaches` contract is still inspection preparation:
normal mixed gate/arrival/runtime consumers remain pending. The south dogleg
is outside the old2208 gate axis; gate integration must consume actual road
geometry rather than publish a centred marker over empty ground.

Mixed fixtures now automatically run the approved complete rectangular-infill
workflow; existing corner exclusions and sub4/fractional limits stay protected.
Fresh motorway1529, density2633 and actual mixed infill27022 assertions pass.
The four current-source fixtures under
`generated/phase_e_mixed_centred_routes_20261014` pass VBSP, portal budgets and
VVIS/VRAD (preview fast preset).128 infill rectangles are emitted; existing
authored sources and both ramp layouts' wide transforms/hashes were independently
compared with prior outputs and match. Four new Hammer++ processes are verified;
old open/manual comparison fixtures were not overwritten or closed.
Human review approved both bridge/deadend arrangements, deadend/on-ramp and
the corner's connecting road. The remaining correction replaces only its
obsolete centre south-border straight at slot `(2,5)` with planned terrain.
Fresh output under `generated/phase_e_corner_terrain_cleanup_20261014`
passes the same four-map fast compile/portal checks and27022 infill assertions.
The three approved control VMFs are byte-identical; the approved corner row
is unchanged. The cleanup is verified in emitted metadata/VMF, not a new
Phase E or normal/live-travel acceptance. Do not repeat the three accepted
layout reviews.
The required ordinary border-showcase control was attempted in its own output
directory but stops in the existing normal-wide planner guard because root
settings disable expanded rings. That broader baseline is not a passing check;
the focused cleanup/actual infill and byte-identical accepted controls pass.
Do not weaken the guard or modify root settings to hide this validation limit.
No staging, profile/world index, player data or installed gameplay changed.

**Latest runtime integration:** normal straight runtime export now rederives
and validates the whole measured assembly before publishing profile/map-scoped
`motorwayGates`. Server arrows use measured lane coordinates and explicit gate
axis rather than the asymmetric AABB centre; arrivals use the same selected
carriageway with surface/deck and player-hull checks. Missing metadata retains
legacy behavior. Malformed, conflicting or mixed shared-map records are logged,
not published, and attempted travel reports an invalid-map-data error.
Fresh server markers10/10, client markers10/10 and GLua275/0 pass;
syntax/offline evidence is not live acceptance. Complete current-source straight
contracts now authorize normal emission: two actual normal recipes pass
VBSP/portal budgets/VVIS/VRAD and BSP checks for four gates/four arrivals.
The separate fresh crossroads fixture passes VBSP with the approved brush41926
repair. These are isolated outputs, not full-world rollout. The attempted
two-cell runtime export correctly failed the mandatory complete24x24 guard;
only exporter helper fixtures passed. Do not weaken that guard or claim a full
integration export exists.

The user's instruction is to continue through integration and the already
approved playable-preview batch without another small-slice "please continue"
handoff. Stop only for a concrete design decision/blocker or required human
review. The current matching density plan contains four retained mixed layouts:
logical17,-12 deadend-south/bridge-horizontal,
13,6 corner-north-east/onramp-s,6,11 deadend-north/onramp-e and
15,11 deadend-north/bridge-horizontal. These are not the seven accepted
single-assembly examples. Their retention policy is settled and measured mixed
inspection support is implemented. Neither silently discarding a route nor
staging diagnostic assemblies as normal travel is authorized. Finish normal
complex contracts/rings/gates/runtime integration after correction review,
without reopening approved artwork, yaws or retained single-piece limits.

| Area | Implemented/reviewed evidence | Current disposition |
| --- | --- | --- |
| Phase 0 readiness | Source inventory, matching installed baseline, persistence/restoration records and watcher-free live baseline. | Accepted; do not repeat readiness as a new prerequisite. |
| Phase A density design | Coastal low band, inland medium/high and district overrides; hard tagged-tier selection with untagged eligibility. | Accepted policy. |
| Phase B motorway fixtures | Eight authored pieces surveyed in four rotations; both straight complete cells and all seven complex complete-cell cases reviewed in Hammer. Seven complex U4/U8 outputs compiled, with portal checks and human review of the four refreshed affected cells. T-junction is explicitly synthetic. | Accepted with recorded limits; authored art/yaw and reviewed whole-cell arrangements are not awaiting another asset approval. |
| Ground/infill | Standard full/half/quarter bases, bounds-based exclusions, power-of-two patches U4..U512, explicit fractional/sub-U4 remainders. | Reviewed/accepted follow-up; not a new ground redesign task. |
| Phase D generator source | Density selection for scenery/boundaries, decoration-only motorway rules, occupied-route adjacency, fixed-landmark density exemptions, filename/content guard and adaptive variation cap. Isolated576-cell/335-recipe plan/layout checks pass; three changed den-entrance slots were approved. | Accepted on source/isolated-output evidence; not full deployed-world acceptance. |
| Phase E ordinary helpers | Rectangle1..3-per-axis occupancy, rotated frontage, filename/marker parsing and square compatibility fixtures. | Implemented supporting source only; no ordinary rectangular building content added. Do not expand building features as the next task. |
| Phase E motorway helpers | Straight core/border/outer owner/lease validation and explicit physical-origin VMF emission. Latest focused motorway1074 and rectangle555 assertions;18 retained straight transforms match. | Implemented in the isolated straight path, not normal motorway rollout. |
| C/H CSM and chest lamp | Default-off additive CSM runtime/Options, Low1/15Hz, Medium2/30Hz, High3/rendered-frame updates. The F chest lamp is unshadowed while CSM is off; only the local player's lamp shadows while CSM is ready. Sun coverage follows the local player. Runtime trees cast; bushes/hedges and high-poly non-foliage models are suppressed with original flags restored on CSM off. Static props remain unchanged. | Experimental CSM accepted; flashlight, player-centered anchor, and runtime caster-policy follow-ups are fixture-covered. Static hedge cost, shadow popping, and broader CSM work remain in the dedicated tracker. |
| Launcher side work | Globe controls/HD layers, space presentation, fog/strikes, G-Man carousel, looping sky inspection and music handling recorded separately with prior review. | Retain approved presentation; not unfinished motorway or CSM work. |
| Phase M safe-zone details | Experiment rejected; claim/reservation/emission integration and dedicated tests removed, authored assets preserved. | Cancelled, not pending redesign or integration. |

Physical landmarks are **density-exempt and not relocated** under the final
decision. Missing optional high-tier terrain/decorations retain bare terrain;
do not lower their tier or invent replacement art. Existing den access remains
separate from the rejected detail system.

### The two preview output tracks must not be confused

1. **Accepted whole-cell motorway fixtures:** the isolated inspection pipeline
   owns measured assemblies, explicit ring leases and infill. The final seven
   complex fixtures have compiler/portal and Hammer-review evidence. Their
   inspection mode deliberately emits no travel gates. Visual approval does
   not mean these fixtures are integrated in normal planning or live travel.
2. **Full density-preview rebuild:** under
   `generated/phase_m_preview_rebuild_20261014`, the retained plan has576 cells,
   335 recipes and three dens. Its compile report records338 maps,336 completed,
   two failed, zero incomplete; both failures reference crossroads brush41926.
   **Direct audit finds96 motorway cells, zero measured-assembly metadata,
   and all484 wide-source placement records still recorded as1x1 road/road-center
   placements.**
   The settings remap/compile therefore did not finish widened occupancy,
   ring ownership or travel integration. This output is unstaged and is not a
   ready3.2 world, even if the two compiler failures are repaired.

**Installed preview is still the old tuned world.** Read-only comparison of
`content/data_static/zombiesim_world_preview.json` finds311 distinct maps,
576/576 logical-cell map names matching
`generated/preview_variety_tuned_20261012/plan.json`, and0/576 matching the new
density-preview plan. The installed skyline has311 recipes and its plan SHA256
matches that tuned plan exactly. This verifies runtime mapping/skyline identity,
not a fresh hash audit of every installed BSP. The new generated density/wide
preview has not replaced the installed world.

The crossroads is the only failure recorded in that full compile. This does
not establish that all normal-generator joins/collision/travel were checked.
Conversely, old measured join residuals are **not new reported in-game bugs**.
Phase B explicitly retained connector/clearance limits; do not turn those
historical notes into a new prerequisite to re-author approved pieces or
silently erase the limits. No new connector geometry has been approved.
Integrate the reviewed arrangements, preserve their disposition, and present
any concrete unsupported normal-world combination with current source/output
evidence rather than requiring speculative new assets.

### What remains, in actual dependency order

1. **E - normal motorway integration:** carry the approved assembly/origin/
   occupied-slot/ring contract into normal planning and VMF emission; replace
   displaced boundary pieces explicitly, preserve coast/shell/shoulders and
   ordinary roads. Resolve actual supported combinations visibly. Add measured
   gate openings/decks/lane markers/arrivals and runtime metadata. Existing
   runtime arrows/arrivals still use the legacy160-unit lateral contract.
2. **F - matching derivatives:** teach layout/skyline/map artwork/runtime
   exports to consume actual emitted assemblies/transforms and revision keys;
   preserve existing profile/cell persistence protections.
3. **G - bounded playable preview:** fresh current-source fixtures, focused
   regressions, VBSP/portals then VVIS/VRAD, matching derivatives, backed-up
   staging and watcher-free GMod launch. Show the implementation and verify
   travel in the game; no repeated approval of unchanged authored assets.
4. **I - integrated review:** actual geometry/travel/lifecycle and visual review;
   matched performance requires agreed workload/budget, not proxy hook timing.
5. **J/K - final shared closure:** complete preview rollout and carried3.1.5
   artwork/wireframe/navmesh/Satellite/integration acceptance on the final
   revision. This is not a prerequisite to the first bounded game demonstration.
6. **L - documentation/package checks and milestone decision:** only after
   relevant integration evidence and user acceptance. Production/publication
   remain separate and version remains `in development`.

### Current permission and repair state

- User asked to continue across phases until an in-game demonstration is ready,
  paused for this audit, then explicitly resumed density/motorway work.
- The bounded isolated preview generation/compile/derivatives/backed-up staging/
  launch batch is explicitly approved. Do not ask again for that same batch.
  Full-world navmesh/Satellite closure, production and publication are not
  included in that approval.
- The user explicitly approved minimal repair of crossroads brush41926.
  A hash-verified original is retained under
  `generated/phase_e_crossroads_brush_repair_20261014`. The edit aligns inconsistent
  plane/winding vertices within that brush only; no surrounding art or VMX was
  changed. **It has not been compiled: the repair is attempted, not proven.**
  Old full-preview and accepted fixture reports predate this source edit.
- No new compile, regeneration, staging or game transition ran during this
  audit. No survivor data or preferences were changed.

### Corrections to recent assistant reports

- "Only the crossroads remains" is correct for the retained compile's failure
  list, **not** for all remaining implementation.
- "All motorway pieces need connecting assets before continuing" overstated
  historical limitations and reopened accepted work. Separate connector work
  remains deferred, not a newly authorized art task.
- Repeated rectangle/helper slices were source preparation, not installed
  rectangular buildings or completed normal motorway integration.
- The accurate next implementation is normal-generator integration of the
  reviewed motorway cells and their travel/derivative path, followed by the
  already-approved bounded playable review.

---

## Original plan and chronological evidence

Prepared on 2026-10-13 from the current authored assets and source, with the
design decisions below confirmed by the user. This replaces the initial feature
sketch. On 2026-10-13 the user moved unfinished Alpha 3.1.5 closure to the end of
3.2 to prioritize generator work. This is now the active scheduling tracker;
the ordering change does not run implementation or authorize world regeneration,
compilation, staging, player-data changes, production rebuilding or publication.
The user accepted Alpha 3.2 Phase B with its exact seam-clearance and
unsupported-connector limits recorded below, then authorized Phase D. Phase D
was accepted on 2026-10-14 after policy-v1 plan and isolated VMF/layout checks;
the user also approved three deterministic safe-zone entrance slot changes
against the older saved plan. This acceptance does not imply compiled, staged,
live or visual verification. Phase M0's earlier design approval was superseded
by the user's rejection of the safe-zone detail result on 2026-10-14.
Phase M is cancelled, not awaiting another review or redesign. The user instead
prefers large, interesting authored tiles with varied widths/heights placed
through the normal map pipeline. Preserve authored assets; do not invent a
replacement claim/halo system. Phase D's one isolated seed-1337 output
pass was explicitly approved; future broad regeneration,
compilation, staging and production operations still require approval.

Alpha 3.1.5's unfinished Phase D output acceptance and Phase I integration work
are carried into Phase J's shared output batch and Phase K below, not prerequisites
for generator work. Its accepted phases and current-cell projection remain
accepted; its milestone is not declared complete or released. Do not reopen
accepted launcher, coast, movement or loot reviews merely to fill historical gaps.

This is the master tracker for **new authored buildings/decorations/borders/
edges, density zoning and 3-wide motorway assemblies**, with the current
experimental CSM slice accepted by the user. All remaining CSM implementation,
validation and optimization is deferred to the existing
[CSM implementation tracker](docs/csm-implementation.md), outside Alpha 3.2's
completion requirements. This accepts the limited default-off additive
experiment, not seamless cascades or measured performance. Do not restart CSM
probes, reloads or benchmarks to advance this milestone.

## 1. Approved requirements and invariants

### 1.1 Density and scenery

- The number in a filename is a variant ID, not a density or height measurement.
  Density is the letter-count suffix: `a` = low, `aa` = medium, `aaa` = high.
  For example, `tile_building_6a.vmf` is low density.
- Apply the policy to buildings, decorations, border tiles and outer-edge tiles.
  Required topology/function is selected first: density must not turn a water
  boundary into a wall or a road continuation into decoration.
- The user's final clarification supersedes the earlier proposed classification
  requirement: **a piece without a density suffix is eligible at every density**.
  Untagged corners, `none` pieces and other functional assets need no invented
  tier metadata or separately authored density variants.
- Default target-tier selection:

  | Zone | Low | Medium | High |
  | --- | ---: | ---: | ---: |
  | Low | 100% | 0% | 0% |
  | Medium | 0% | 95% | 5% |
  | High | 0% | 5% | 95% |

- These are deterministic **target-tier probabilities**, not an assertion that
  a small cell, or a world with missing pools/untagged assets, realizes exactly
  those percentages. Test the selection thresholds exhaustively and report
  target-tier counts separately from actual tagged/untagged placements.
- If a selected optional building/decorative tier has no compatible asset,
  retain its terrain and report the shortage. Do not reroll into a forbidden
  tier, silently renormalize the mix or manufacture assets.
- If a required boundary cannot be satisfied by a permitted tagged or untagged
  functional asset, stop with an actionable cell/side/pool diagnostic. Removing
  a required boundary is not an acceptable missing-pool fallback.
- Preserve the existing route-adjacent highest-density wall exclusion, with the
  explicitly approved exception below. Determine adjacency from the complete
  widened route footprint, not just the old centerline:

  | Border/edge wall immediately beside a corridor | Target tier |
  | --- | --- |
  | Low-density zone | Low only |
  | Medium-density zone | Medium only |
  | High-density zone | Medium only |

  Untagged functional pieces remain eligible. Do not introduce low-tagged walls
  in high zones under this exception. Report constrained slots separately from
  the ordinary 95:5 distribution.
- Use distance inland from the actual ocean boundary, not distance from the
  world-map center or every map edge. Protect a low-density coastal band;
  density increases gradually inland. Important commercial/residential districts
  can raise inland density but cannot override the protected coastal band.
- Approved Phase A policy, 2026-10-13: cardinal land-cell steps from actual
  ocean-touching cells (distance0). Distances0-2 protected low,3-7 medium,8+
  high; for the current west ocean this is logical x. Commercial/financial
  profiles raise inland cells to high; settlement raises to at least medium.
  No named-district importance is inferred. Coast always wins.
- Keep occupancy probability, asset density class, physical height and danger/
  population difficulty distinct. This request changes scenery density; it does
  not authorize new loot, enemy, radiation or movement balancing.

### 1.2 Motorways

- Replace old 1-wide motorway geometry with the new 3-wide family throughout
  core, border and outer-edge continuations. Retain the authored
  [1x1 sources](tiletemplates/roads/motorway_1x1) as source assets, not automatic
  fallbacks. Incompatible new layouts must fail with evidence.
- Preserve the logical world grid and cell size: 640-unit tiles, 5x5 core,
  existing 7x7 border frame and enabled 9x9 outer frame, and the existing
  5760-unit expanded neighbour pitch. Preview stays 24x24; the already approved
  future production city remains 48x48. Do not enlarge logical cells to fit an
  awkward junction.
- A straight 3x1 piece is centered on the existing motorway axis: at canonical
  yaw 0 it is three tiles east/west and one tile north/south. Rotated footprints
  swap dimensions. Do not retain the old narrow instance under the new piece.
- Complex pieces share the user's authored motorway orientation, but their
  **port positions, deck heights, widths and required origin offsets still need
  surveying**. Prefer a centered feature with correctly rotated connectors;
  do not assume geometric center equals every route's connection center.
- User confirmation,2026-10-13: every new motorway piece matches its1x1
  counterpart's canonical orientation in every circumstance. Existing topology/
  orientation yaw mappings are authoritative, not hypotheses requiring another
  asset review. Integration measurements concern dimensions, local port positions,
  decks and offsets; do not introduce new yaw corrections from bounds alone.
- Assemblies may reserve core/border/outer slots within the existing physical
  envelope. Every displaced ring instance needs an explicit compatible
  replacement. No implicit border suppression or geometry borrowing from a
  neighboring BSP is allowed.
- Motorway cells are decoration-only outside transport/required terrain and
  boundary geometry: no ordinary buildings, skyscrapers, physical landmark
  buildings, carparks or safe-zone entrances.
- Relocate affected physical landmarks/carparks/safe-zone access to compatible
  non-motorway cells. Preserve landmark identity, safe-zone identity and reachable
  road access. A landmark tied to a radiation source or other fixed location
  needs an explicit conflict decision, not an invisible move of gameplay data.
- Preserve the logical motorway/road travel graph. Wider geometry changes physical
  ports, not the meaning of a logical cell connection. New interchanges must
  match the requested connections without creating false exits.

### 1.3 CSM

- **User decision, 2026-10-14:** additive client-local projected shadows are
  accepted as the intended CSM direction. This explicitly supersedes the former
  replacement-quality requirement. Do not describe the projector as replacing
  the baked `light_environment`; keep that entity/lightmap unchanged. CSM stays
  client-local and off by default, with the original native image retained when
  disabled. The user now accepts the current experimental implementation with
  its weighted-overlap limitations. Further brightness, cascade, lifecycle,
  independent-client and performance checks are deferred to the CSM tracker.
- The removable one-projector probe has been completed and stopped. Its scoped
  visual evidence does not verify the new runtime/Options controls; no further
  probe or broad rebuild is required for this acceptance.
- Preserve existing weather/day-night, sky palettes, fog, cameras, launcher
  presentation, clothing/gore, snow/puddles and fires. CSM is not another owner
  of those systems.
- Initially off; no automatic enablement for existing quality-preset users.
  Maximum initial shipping design is three shadow-enabled projectors; no spread,
  further cascade, first-person proxy, skybox-lighting branch or mandatory NikNaks
  dependency without separate approval.
- A client preference must never change shared server lightmaps/lightstyles or
  another client's image. The separate two-client off/native-fallback check is
  retained in the deferred CSM backlog, not claimed as passed.

## 2. Source investigation and implementation ownership

These are source findings, not compiled-map or visual evidence.

| Surface / current owner | Finding and required work |
| --- | --- |
| [generator-settings.json](generator-settings.json) | Explicit motorway paths still reference removed root-level `roads/tile_motorway*` files. Border settings also reference deleted/renamed walls and corners. Update discovery, topology, transport and variation mappings from the surveyed inventory, not a bulk path substitution. |
| [generate_world_cells.ps1](bin/generate_world_cells.ps1) | Owns road/highway topology, districts, settlement placement, landmarks and safe zones. Produce one authoritative coast/district density field here or through a shared pure helper consumed here and by fixtures; relocate conflicting features before final reachability repair and serialization. |
| [plan_cell_templates.ps1](bin/plan_cell_templates.ps1) | `Get-BuildingDensityTier` uses tags/profiles, not an inland gradient. `Get-BuildingTemplatesForDensity` gives every building a nonzero weight, violating hard exclusions. Decorations and `Set-OpenTerrainFill` select from unfiltered pools. Single/multi-tile, commercial, industry, landmark and variant paths all need the same contract. |
| Same planner, transport branch | Places a single center template and one-tile arms, then adds onramp/deadend/bridge pieces through special cases. These cannot simply receive the larger VMFs without footprint reservations and explicit connector matching. |
| [build_cell_vmfs.ps1](bin/build_cell_vmfs.ps1) | `Get-PlacementFootprint` explicitly rejects nonsquare footprints and widths over 3. Border routes are single center slots. Generalize transported placement ownership/validation, emitted origins, ring reservations and layout metadata coherently. Keep existing square building behavior unchanged. |
| [outer_edges.psm1](bin/outer_edges.psm1) | Continues routes in one outer-ring slot, and checks wall adjacency using Manhattan distance to old route slots. Consume full occupied corridor slots and compatible transport continuations; preserve ocean omission and shell boundary rules. |
| [transition_gates.psm1](bin/transition_gates.psm1) and [sv_transitions.lua](gamemode/sv_transitions.lua) | Gate anchors remain axis-based; runtime motorway arrows use lateral +/-160 and arrivals use the old carriageway correction. Survey new deck/median/lane positions and publish validated geometry-derived anchors. Preserve paired arrows, colors, arrival yaw, behind-arrow arrival intent and hull safety. |
| [world.lua](gamemode/utils/world.lua), [export_runtime_world_data.ps1](bin/export_runtime_world_data.ps1) | Own profile/map resolution and generated compatibility. Carry validated density/transport/lighting data only where consumers need it, with schema/revision checks and explicit unavailable paths. |
| [build_cell_map_materials.ps1](bin/build_cell_map_materials.ps1), skyline model builder and world capture | Illustrated maps, wireframes, skyline/coast extraction and capture revisions must describe the same widened layout. Use generated placement metadata rather than draw a wider line over stale one-tile occupancy. |
| [CSM tracker](docs/csm-implementation.md) | Contains pinned upstream/API research, resource limits, proposed module boundaries, view lifecycle and a full validation matrix. Recheck actual owners before implementation; proposed files and `zn_test_csm` / `zombiesim_csm_status` are not implemented commands. |

### Authored asset inventory warnings

- New generic numeric variants include `tile_building_3a` through `6a`; these are
  low-density candidates under the approved naming rule.
- Current decorations contain low-tagged assets and a medium-tagged tree asset,
  but no high-tagged decoration asset. High-tier rolls may therefore retain
  terrain unless compatible untagged assets are available.
- `tile_industiral_3aaa.vmf` does not match the current industry discovery regex.
  `tile_border_wall_1bbvmf` has no `.vmf` extension. Treat these as inventory
  discrepancies for author confirmation; do not rename user's source files
  opportunistically. `bb` has two letters if the author confirms that name.
- The motorway folders contain orphan/old `.vmx` names; only existing `.vmf`
  files are candidates. Preserve companion/editor work; do not infer a usable
  bridge/deadend/onramp variant from a `.vmx` alone.
- Border corners now have tagged alternatives; outer corners include an untagged
  source. Special military/radioactive pools also need density-aware selection,
  with their existing functional identity preserved.

### New motorway inventory

All paths below are relative to [motorway_3x1](tiletemplates/roads/motorway_3x1).
The dimensions are authored naming/plane-point observations, **not verified
drivable connectors or exact compiled collision bounds**.

| VMF | Expected nominal footprint | Required survey |
| --- | --- | --- |
| `tile_motorway.vmf` | 3x1; plane points X +/-960, Y +/-320 | Deck, median, carriageway/lane centers, north/south ports. |
| `tile_motorway_road_bridge.vmf` | Unsuffixed wide bridge; coarse X +/-960, Y +/-320 | Which route is above/below; both port heights and ordinary-road approach. Do not assume a 3x1 filename parser identifies it. |
| `tile_motorway_corner_5x3.vmf` | 5x3 | Both curved route endpoints, canonical exit directions, shoulder envelope. |
| `tile_motorway_crossroads_6x3.vmf` | 6x3 | All ports, any grade separation, axis/origin offset for even-sized span. |
| `tile_motorway_tjunction_6x3.vmf` | 6x3 | Stem direction, ports/decks, closed side, centered/offset reservation. |
| `tile_motorway_deadend_3x3.vmf` | 3x3, with plane-point overhangs | Terminating direction, cap collision; coarse Z includes below-ground geometry. |
| `tile_motorway_onramp_3x4.vmf` | 3x4 | Motorway through ports, ramp mouth, city-road join and elevation. |
| `tile_motorway_onramp_dual_3x4.vmf` | 3x4 | Both road mouths and shared motorway ports; coarse Y exceeds nominal edge. |

Do not derive ports from the AABB alone. Plane points are not a complete VMF
solid/prop/displacement collision survey. Do not flatten every new deck to the
legacy 36/196 heights or move sources vertically to hide a mismatch.

## 3. Phase order and dependencies

Each phase needs focused static checks as its changes land, then its explicit
Hammer/live/human gate. Record those evidence types separately. User acceptance
is required to close a phase; an unexecuted gate remains pending or explicitly
deferred, never inferred from source completion.

| Phase | Purpose | Prerequisite / stop boundary |
| --- | --- | --- |
| 0 | Readiness, inventory and restoration baseline | User's generator-first scheduling decision; preserve 3.1.5 evidence/ledger without requiring its closure. |
| A | Density/coast design and fixture contract | Phase 0; approve coast bands/district mapping before integrating them. |
| B | Motorway assembly/port survey and placement contract | Phase 0; every shipping topology needs surveyed compatible parts. |
| D | World/planner source implementation | Accepted A/B; accepted on policy/source evidence, not whole-milestone acceptance. |
| M | Cancelled safe-zone detail experiment | User rejected the result; claim/reservation/emission changes removed. No further detail, coast or naval work scheduled here. |
| E | VMF/rings/gates and runtime travel integration | D and verified assembly contract; no safe-zone detail claim prerequisite. |
| F | Derived layout, skyline, map/capture and compatibility source | D/E; no broad material/capture job yet. |
| G | Small compiled geometry prototypes and travel review | D/E/F focused checks; separate approval for compile/staging. |
| C | CSM capability evidence (historical slice) | Current experiment accepted; remaining capability checks deferred to the CSM tracker. Not a generator prerequisite. |
| H | Experimental CSM service and Options | Current experiment accepted with retained unverified limits; further cascade/view work deferred. |
| I | Generator visual/performance/lifecycle acceptance | G; no deferred CSM gate or benchmark prerequisite. |
| J | One approved full-preview closure batch | I, measured recipe budget and explicit expensive-work approval. |
| K | Carried Alpha 3.1.5 closure and integrated acceptance | J; preserve accepted phases and explicit validation limits. |
| L | Documentation, packaging and milestone acceptance | K; production and publication remain separate decisions. |

**Remaining execution order: E -> F -> G -> I -> J -> K -> L.**
Phase letters are stable references, not the execution order. Generator work
comes first; 0/A/B/D are accepted, M is cancelled, and C/H's current experimental
scope is accepted. All remaining CSM work lives outside this schedule in its dedicated
tracker. Do not start it or old 3.1.5 closure opportunistically.
Focused checks needed to validate new generator changes still run in their phase.

Source-only work that does not depend on an outstanding live gate may be batched
with approval, but must not bypass phase dependencies or imply acceptance.

### Phase 0 - Readiness and exact source baseline

- [x] Reconcile latest Alpha 3.1.5 acceptance/deferral notes against the carried
      Phase K list. Do not require its expensive closure before generator work.
- [x] Record preview/city profile settings, seed, current matching manifest/plan,
      source hashes, current loaded map/cell/player state and restoration ledger.
- [x] Inventory current working-tree assets, not only committed tiles. Identify
      additions, renames, missing explicit references, invalid filenames,
      companion VMX mismatches and discovery exclusions; ask about discrepancies.
- [x] Inventory all generic and special-family pools by density and footprint.
      Report missing optional pools separately from required topology gaps.
- [x] Preserve authored overhangs, current safe-zone detail work, unrelated API
      submodule changes and accepted presentation. No automatic source cleanup.
- [x] Capture a small agreed native-lighting baseline and confirm watcher-free
      `-disableluarefresh` launch before future performance work.
- [x] At actual milestone activation, update active tracker links and the single
      version/changelog source together; retain `in development`.

Exit: an agreed source inventory, safe restoration path and clear authorization.

#### Phase 0 inventory evidence - 2026-10-13

The user authorized Phase 0. The [3.1.5 tracker](docs/todo-alpha.3.1.5.md)
is archived with rerooted links; its pending closure stays in J/K. No generator
logic, authored VMF/VMX, staged output, player data or API files were changed.

Read-only inventory hashed 158 current authored VMFs. Density/footprint counts
include all discovered sources, not merely candidates accepted by current regex:

| Family | Low | Medium | High | Untagged | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| Buildings | 27 | 9 | 5 | 0 | Includes square 2x2/3x3 and special families; industry typo still excluded from discovery. |
| Decorations | 7 | 2 | 0 | 0 | No high-tagged candidate; approved terrain shortage handling remains necessary. |
| Border | 4 | 4 | 2 | 13 | Tagged corners/walls plus neutral structural assets. |
| Edges | 4 | 5 | 3 | 3 | Untagged corner/none pieces stay eligible at all tiers. |

Rectangular named motorway sources: one 5x3, two 6x3, one 3x3 and two
3x4; straight/road-bridge sources are unsuffixed and require the explicit
Phase B contract rather than the inventory parser's default 1x1.

Resolved profile baseline:

- Preview: 24x24, seed 1337; currently staged runtime hashes match both
  `generated/preview_variety_tuned_20261012/plan.json` (311 recipes/576 cells)
  and its exact manifest. Use that baseline, not the root `bin` preview plan
  (179 recipes), for staged-world comparisons.
- City configuration: 48x48 future generation, not a rebuilt installed world.
  Existing production runtime was hashed and left untouched.
- Source settings SHA256:
  `696E5045DCD6204D4E1EB87C8D42A0F95A6126F01134792D745B028C74234226`.
- Matching staged plan SHA256:
  `F408C956FA1B077770858B7CEBF2B941C90ADEDE9F23AC63D68F1C2A3E18AF17`.
- `generated/phase_b_live_preview/staging-ledger.json` reports staged,
  5854 entries. All 16 original existing-file backup hashes verify. This is
  backup/restoration-path evidence, not a fresh hash audit of all staged maps.
- Garry's Mod is closed. Last heartbeat names `zn_preview_start` but is stale;
  no current player/logical cell or watcher-free running-process evidence is
  claimed. The small native-lighting baseline remains pending and no game was
  launched for this source-only inventory.

Thirteen configured required paths are missing: the old untagged border wall/
corner plus eleven root-level motorway topology/transport/variation references.
They need intentional Phase D remapping after the survey, not silent fallback.
Thirty-two orphan VMX companions were inventoried and preserved.

The formerly malformed border file is now `tile_border_wall_1bb.vmf`, a valid
medium-tagged name; the older section-2 warning is superseded for that file.
The user approved correcting `tile_industiral_3aaa.vmf` to
`tile_industrial_3aaa.vmf`, classified as high-density industry. The source was
renamed without a geometry edit; no same-name VMX existed to move.
Detailed per-source hashes,
pool membership, missing references and backup results are retained in the
session artifact `alpha32-phase0-inventory.json`.

#### Phase 0 focused tests and live baseline - 2026-10-13

- GLua syntax: 271 files checked, zero failures. No Lua behavior was changed.
- Existing tuned-plan variety check: 4807 assertions pass, 576 cells/
  311 recipes; all1104 cardinal adjacency pairs retain distinct filenames and
  actual planned layouts. This checks the existing tuned baseline, not generation
  of the new 3-wide motorway sources.
- GMod launched at `zn_preview_start` with main process21292 explicitly verified
  to contain `-disableluarefresh`. Chromium utility/renderer children are not the
  game process and do not need the game launch flag.
- First status dispatch preceded admin connection and was rejected; after the
  user confirmed Home ready, fresh client atmosphere and screenshot files arrived
  independently of the bridge acknowledgement. Active profile preview, clear
  synced weather, active/expected atmosphere `safe_zone`, inspection inactive.
- Read-only persistence report confirms loaded map `zn_preview_start`, active
  preview profile and health100. Client diagnostics report logical0,0 with no
  safe-zone id; this is the undeployed launcher state, not a deployed survivor
  location or a reason to repair saved coordinates. Raw persistence evidence
  remains in session storage; no deployment or teleport was requested.
- Native existing-launcher capture `alpha32_phase0_native_home` completed on
  frame818 at1366x768. Metadata records detail2, props1, sky light scale0.25,
  saved palette `default`, effective launcher sky `imported_tropo_night_2`,
  six palette meshes and unchanged baked lighting. The capture is pre-VGUI
  (`afterVGUI=false`), so it does not prove menu layout; the user separately
  confirmed the normal Home presentation looks correct and accepted this
  Phase0 baseline.
- Capture/metadata, fresh atmosphere report and persistence report were retained
  in session storage. No settings, lighting, survivor movement, generation,
  compilers, navmeshes or staging changed. GMod remains at the preview launcher.

Phase 0 is accepted by the user's continuation on2026-10-13 after the recorded
checks and baseline approval. Required asset mapping/connector gaps proceed
through A/B/D without a silent fallback. The baseline is an existing-launcher
reference, not a city-lighting, CSM feasibility or performance verdict.

### Phase A - Density zoning and deterministic selection contract

- [x] Implement/test a pure filename classifier: numeric variant ignored;
      terminal letter token before optional footprint suffix determines class;
      no token means untagged/all-tier. Reject unsupported tagged classes visibly,
      rather than treating malformed names as universal.
- [x] Define one authoritative `sceneryDensityTier` plus diagnostic source
      (coast band/district/override). Migrate/alias existing `buildingDensityTier`
      deliberately so filenames and existing consumers do not diverge.
- [x] Draw a small coast-to-inland/district fixture. Approve low-band width,
      medium transition, high threshold, distance metric and important district
      mapping before generating a full world. Distinguish actual ocean from
      decorative water-border variants, lakes and arbitrary grid edges.
- [x] Specify precedence: protected coast -> approved inland district influence
      -> inland baseline. Store resolved tier in generated data; consumers do
      not independently reinterpret environment tags.
- [x] Define deterministic target-tier selection first, compatible template
      choice second. Untagged candidates may satisfy any selected tier within
      the correct functional pool. Empty optional pools keep terrain; required
      empty pools fail. Report untagged placements and shortages explicitly.
- [x] Use a stable hash including seed, cell/recipe policy, ring, slot, role and
      variant; do not depend on filesystem enumeration or hash-table order.
- [x] Define eligible neutral pieces within each functional pool, not one global
      untagged pool. Choose a target tier, then select from that tier plus the
      compatible untagged pieces. A neutral water pier cannot satisfy a missing
      land-wall pool. Report chosen target, actual tag and exclusion reason.
- [x] Test roll boundaries (0, 94, 95, 99 for a 100-bucket roll), all tiers,
      neutral assets, footprints, special families, all missing-pool paths,
      route-adjacent exceptions and reproducibility.

Exit: approved density map/policy with exact selection tests. No scenery is
silently reclassified by its physical height or numeric filename.

#### Phase A pure policy slice - 2026-10-13

User approved three low columns, five medium columns, then high; cardinal
land-step distance from actual ocean; and commercial/financial/settlement
influence with protected coast precedence. The resulting12-column fixture was
explicitly approved: ordinary land/settlement `L L L M M M M M H H H H`,
commercial/financial `L L L H H H H H H H H H H`.

[scenery_density.psm1](bin/scenery_density.psm1) owns the pure classifier,
cardinal distance field, resolved tier/source, exact target rolls, versioned
selection hash and compatible-pool chooser. Required missing pools fail with
cell/side/pool context; optional shortages retain terrain with explicit status.
Duplicate paths/enumeration order cannot affect selection; unsupported tags
fail. Tests classify all88 current authored building/decor/border/edge VMFs.

The first focused run exposed empty-ocean-array parameter binding before the
intended diagnostic. Allowing that collection through to the explicit
actual-ocean check fixed it; the next run passed1487assertions. The final run,
including pinned hash and Turkish-locale regressions, passes1490assertions.
Editor diagnostics report no errors; milestone JSON/changelog grouping and
diff whitespace pass. Settings and tuned-plan hashes match the Phase0 baseline.

No normal generator/planner consumer imports the new policy yet, deliberately:
existing outputs and staged gameplay remain unchanged. Next Phase A work is
authoritative generated `sceneryDensityTier`/source/distance and deliberate
`buildingDensityTier` aliasing, with export/consumer fixtures. Phase D wires
all selection pools and aggregates diagnostics; D/E derive route adjacency
from widened occupied slots. The route-flag tests prove target exceptions,
not physical footprint detection. Phase A is not accepted or complete.

#### Phase A authoritative field/export slice - 2026-10-13

The earlier pure-only limitation is superseded for field migration, not for
placement enforcement. [generate_world_cells.ps1](bin/generate_world_cells.ps1)
now applies the approved zoning before serialization, using explicit west
ocean-touching cells at x=0 and the existing environment profile priority.
Stored cell fields are `sceneryDensityPolicyVersion=1`, `sceneryDensityTier`,
`sceneryDensitySource`, `sceneryInlandDistance`, plus an identical
`buildingDensityTier` alias. Manifest environment metadata declares version1.
Priority is unchanged: e.g. destroyed can precede commercial; no separate
tag-based district reinterpretation is introduced.

[plan_cell_templates.ps1](bin/plan_cell_templates.ps1) validates declared
metadata, uses the authoritative tier in existing recipe/filename/variant
paths and retains the density record on each planned cell.
[export_runtime_world_data.ps1](bin/export_runtime_world_data.ps1) validates
manifest policy and requires matching manifest/plan records before retaining
the same fields in runtime cells. Partial records, invalid source/band
combinations, unknown policies and divergent aliases fail explicitly.
Metadata-less legacy manifests keep their original tags/profiles/recipe policy
and emit a planner warning; no staged data is mutated or silently upgraded.

Fresh focused density tests pass2384assertions, including actual `Export-MapData`
serialization/reload of an isolated144-cell fixture, production planner density
consumption, runtime density helper matching, unchanged non-density fixture
fields, legacy compatibility, corrupt/partial/header cases, exact target rolls
and hash reproducibility. The fixture supplies map-cell inputs; it does not
generate a transport world, VMFs or BSPs. One first run lacked the exporter's
population fixture variable; adding the explicit variable fixed it. Its exact
temporary JSON is removed in `finally`. Existing skyscraper-selection regression
also passes (taper/frequency/height preference/recipe identity).

Settings, tuned-plan and production runtime hashes remain unchanged; diff
whitespace passes. No Lua changed and no live reload was needed. Phase A's
source/fixture checklist is complete. Final editor diagnostics report no errors;
metadata grouping and whitespace pass; repeat fixture serialization is
byte-identical. The user accepted Phase A on this scoped evidence on2026-10-13
and chose Phase B's authored motorway connector survey next. Full regenerated
preview, actual placement exclusions and widened-footprint adjacency remain
D/E/G integration work; no expensive process or staging ran.

### Phase B - Survey motorway puzzle pieces and reserve their envelopes

- [x] Authored-asset trust decision: user confirmed all supplied motorway assets
      are correct and waived repeated individual asset inspection on2026-10-13.
      Measure integration metadata directly; use Hammer review for generated
      assemblies or a specific integration ambiguity only. Preserve sources
      and unsaved editor work.
- [ ] Record each piece's canonical orientation, intended origin, rectangular
      footprint, physical overhang/clearance envelope, solid/driveable regions,
      permitted underlay and local ports: position XYZ, outward cardinal,
      route type, carriageway width, surface Z, grade and pedestrian clearance.
- [ ] Keep the intended relationship explicit: wide straight centered on the
      old axis; junction centered only where its surveyed ports permit it;
      ordinary-road ramp attaches to its measured road mouth, not an assumed
      adjacent one-tile center.
- [ ] Build a minimal explicit transport registry for unsuffixed pieces and
      exceptional ports/envelopes. Use terminal `_WxH` parsing for rectangular
      sizes, retaining square `_2x`/`_3x` compatibility. Do not create a generic
      asset framework or duplicate size without consistency validation.
- [x] Transform origin, footprint, envelope and ports through the same Source
      yaw convention. At 90/270 degrees width/height swap. Include the
      even-width 6x3 half-tile/origin-alignment case explicitly.
- [ ] For any topology designated supported, validate full-solid joins,
      authored clearances and a collision-free small arrangement. A matching
      floor mouth alone is not a supported connection.
- [x] Record incompatible motorway combinations and ordinary-road approaches
      as unsupported/inspection-only when their connector assets are deferred.
      Do not fake them with crossed straight tiles or expose diagnostic
      assemblies as planner fallbacks.
- [ ] Connect transformed ports by solving translation and yaw; assert matching
      route types, lateral centers, width, grade/deck and heading. Agree numeric
      connection tolerances from authored/engine evidence, not arbitrary gaps.
- [ ] Define complete slot reservations across core/border/outer frames, one
      emitting owner per assembly and occupied non-emitting records. Account
      for multiple Z layers where a bridge legitimately overlaps a road.
- [ ] The registry/placement records must expose authored and rotated width/
      height, origin offset, placement owner, occupied slots/ring leases,
      clearances and transformed ports. Use Hammer units for physical positions,
      tile coordinates for reservations, and explicit local/world coordinate
      labels. Logical tile Y increases south; physical Source yaw is not the
      same transform as an unsigned logical-grid rotation.
- [ ] Identify missing approach/cap pieces and request authoring if needed.
      Never scale authored motorway geometry to force a fit.

Exit: measured connector table plus reviewed generated assemblies where needed,
all four rotations and a collision-free small arrangement for every supported
topology. Phase B was accepted with limits on2026-10-15: no measured motorway
or road connection is promoted to production support; exact floor matches
remain clearance-pending candidates, incompatible seams/approaches remain
unsupported, and all diagnostic placement records remain inspection-only.

#### Phase B initial saved-source measurements - 2026-10-13

**Current revision / human acceptance:** the user checked all nine complete
generated cells, edited the motorway sources and confirmed "Everything is now
perfect." The generated-cell visual review is accepted; preserve those edits
and do not repeat it. Source-backed bridge deck is now196.057; single ramp
road mouth Z80, outward grade-112/192; dual road mouths Z96/grade-0.5.
Dual upper carriageway face provenance is W3470/3518 and E3308/3314.
The ordinary road approach now ends at Z36 south and Z68/96 north.
Fresh survey5696/assembly1806 assertions pass with48exact,24diagnostic and
20pending road approaches across32rotations. Historical source numbers below
describe earlier revisions, not current contracts. Remaining connector,
grade/deck, unsupported-combination and compiled-clearance gates are not
accepted by this visual approval. Phase B remains active.
Current-source complete infill refresh is isolated from the reviewed VMFs.
It exposed the park's translated direction marker at Y-672: the ground was
correctly centered, but this semantic marker was already canonical before
translation. Only the marker is restored to the south midpoint Y-640;
building geometry and props remain unchanged.
Fresh current-source complete refresh at `generated/phase_b_approved_cells`
passes infill271950/complex3311/ground56/geometry614 assertions, with321editable
ground instances. Cleanup audit identifies75active sources and36unused
byte-identical defaults; do not retire them while reviewed/open historical
VMFs may still reference them. Protected generator settings, tuned plan and
both runtime exports match their retained hashes; no compiler/staging ran.

Remaining source-supported seam limits at yaw0 (the other cardinal rotations
preserve these same physical relationships): corner E second lane is16units
lateral from the straight; corner S second mouth is2units lateral and36units
narrower/noncardinal. Crossroads W second lane differs0.389units laterally.
T north has a noncardinal36-unit narrowing and2.00005-unit lane offset; T west
second lane differs16units and east differs0.001units. These are explicit
diagnostics, not authorized edits or an agreed numeric seam tolerance.
Ordinary road approaches remain provisional, including the single ramp's
Z80 mouth against the ordinary ramp's Z96/68 split and separate bridge deck/
route ownership. Combined corner+ramp and terminal+bridge fixtures still fail
explicitly instead of producing fake supported layouts. The user-approved
appearance must not be "corrected" by silently scaling, snapping or moving
these roadway surfaces. Settle connector policy before normal planner rollout.

#### Phase B separate connector authoring requirements - approved direction

**2026-10-14 ground policy correction (initial 16-unit minimum; superseded by the 2026-10-15 follow-up below):** the user rejected polygon/sliver
infills and chose standard640full/320x640half/320quarter ground bases plus
extra patches whose two dimensions are strict powers of two16..512.
All earlier polygon and arbitrary-decimal fill acceptance claims are superseded
as an implementation direction, not permission to change approved road art.
Only the shared standard ground classifier establishes coverage; generic
road/wall solids cannot carve structural cut-out fillers. Unknown/protected
ground remains explicitly reserved/review-required. Rectangle gaps consolidate
before standard/power-of-two subdivision. Fractional boundaries inset to
integer edges; remainder dimensions below16are left on the black floor.
There are no generated shape or `p` filenames.

Ground-only precision repair corrected39brushes across28sources, with
SHA256-backed originals and every other field unchanged. Fresh audit finds
zero recognized grid defects; this is not proof of alignment for the35
nonstandard/incomplete ground references. Removed61hashed shapes/12decimal
source files explicitly requested by the user, then archived76unused
unmodified rectangle defaults. All originals are restorable under
`generated/retired_terrain_infill`; no artist-owned sources were overwritten.
Old generated fixtures referencing retired sources must be regenerated before use.

Current fixture directory is `generated/phase_b_power2_infill_cells`:
30reusable source templates versus the previous75, with478integer rectangular
instances and36explicitly omitted sub16remainders. Strict powers-of-two sizing
requires more instances than arbitrary-size/polygon pieces; do not call this
an instance-count reduction. Fresh infill88367/complex3625/ground56assertions
pass, with PowerShell7/7 and protected-input hashes unchanged.
No current shape/decimal sources remain or are recreated by the tests.
Normal generator settings, installed runtime exports and production maps
remain untouched. Phase B and its connector/clearance gates stay active.
The next connector slice now has measured far endpoints:
ordinary road floor side54 spans X-128..128/Y-320..320/Z36;
ordinary bridge floor side276 has the same width/span at Z196. The approved
wide bridge road mouth remains Z196.057, a measured0.057difference rather
than an exact seam. Ordinary ramp sides1256/1267 retain north end Z68/96.
Evidence with source hashes and vertices is under
`generated/phase_b_power2_infill_cells/ordinary-road-endpoints.json`.
Do not elevate roads or relax the deck solver to conceal this difference;
separate connector/grade/clearance authoring remains the current Phase B gate.

The user chose **prepare exact requirements for separate connector/approach
pieces, keeping Phase B active**. This is permission for this handoff, not
permission to reshape the approved eight motorway sources or invent a seam
tolerance. No new connector geometry or normal-planner support is implemented.

**Coordinate and measurement contract**

- All coordinates below are local to the unchanged source at yaw0, in Hammer
  units, not logical cell indices or the spaced preview's world coordinates.
  X is east, Y north; Z is absolute authored deck height. Lane order is the
  explicit registry order, not driving direction.
- The source of truth is the current
  `generated/phase_b_approved_assemblies/assembly-report.json` registry:
  source SHA256, floor side ids and full `edges` retain provenance. Re-run
  [build_motorway_preview.ps1](bin/build_motorway_preview.ps1) in this isolated
  directory before authoring if sources change; never copy an old report's
  numbers into a newer source revision.
- A continuation's end must meet every actual source floor edge, not just the
  aggregate lane midpoint. Noncardinal/interleaved contours below cannot be
  represented faithfully by one width/heading tuple. Extend that contract
  explicitly before accepting such a connector, preserving the existing
  strict planar-port solver for the pieces it already supports.
- The far motorway endpoint must match the unmodified straight's two
  416-wide lanes at Z68, source centers X-512/+528 at local Y+/-320, with flat
  grade and opposed headings after the established rotation/translation.
  Its16-unit carriageway asymmetry is intentional. Join both lanes with one
  shared assembly transform; aligning lane1 alone is not acceptance.
- Shared standard ground remains Z0..32 and origin-centered on its declared
  complete ground footprint. The upper floor can be asymmetric without
  moving the ground or forcing a lane midpoint onto the320lattice.

**Measured requirements, not yet implemented assets**

| Requirement | Approved source endpoint(s), XYZ | Width/grade and provenance | Required separate piece |
| --- | --- | --- | --- |
| Corner east | Lane1 `(1600,-512,68)`; lane2 `(1600,512,68)` | Both416/flat; sides5556/5562 and4314/4320 | Two-lane transition to the straight pair; resolve the16-unit second-lane lateral mismatch without altering the corner. |
| Corner south | Lane1 `(-1152,-960,68)`; lane2 aggregate `(-114,-960,68)` |416 and380/flat;6594/6600 and6401/6443 | Contour-aware transition to two416 lanes; second lane is2units laterally offset and36units narrower than the aligned straight. Exact noncardinal contour below is mandatory. |
| Crossroads west | Lane1 `(-1920,-560,68)`; lane2 `(-1920,480.389,68)` | Both416/flat;4314/4320 and9565/9571 | Preserve the approved0.389-unit second-lane offset at the source; meet both exact far straight lanes. Do not treat it as a rounding repair. |
| T north | Lane1 aggregate `(-205.99995,960,68)`; lane2 `(832,960,68)` |380.0001 and416/flat;7463/7493 and6594/6600 | Contour-aware transition preserving the narrowed first lane and2.00005-unit second-lane offset. No rounding of306.00005 continuation placement. |
| T west | Lane1 `(-1920,-512,68)`; lane2 `(-1920,512,68)` | Both416 within recorded double arithmetic/flat;4314/4320 and5556/5562 | Same nominal16-unit spacing mismatch as corner east; reuse a connector only if full transformed contours, barriers and clearance also match. |
| T east | Lane1 `(1920,-512,68)`; lane2 `(1920,527.999,68)` | Both416 within recorded double arithmetic/flat;7164/7170 and7212/7218 | Preserve the0.001-unit source offset; either author an exact connector or obtain an explicit engine-supported precision policy. Do not silently relax the solver. |
| Single ramp north road | `(384,1280,80)` |256; outward grade `-112/192`; side2350 | Independent256-wide approach. Near mouth faces south with outward grade `+112/192`; transition to the measured ordinary-road end at its actual Z and flat grade. Current ordinary ramp's Z68/96 split is not a matching substitute. |
| Dual ramp north/south road | `(128,1280,96)` / `(128,-1280,96)` |256; outward grade-0.5;2350/3169 | Approach at each mouth with opposed heading and grade+0.5. Rotational reuse must be proven, not assumed. The ordinary ramp has one Z96 and one Z68 branch; only a matching branch may attach, with the other branch explicitly resolved. |
| Crossing bridge east/west road | `(960,0,196.057)` / `(-960,0,196.057)` |256/flat;738/642 | Elevated ordinary-road continuation with exact source deck. First measure the existing ordinary bridge's floor/curbs/collision; decide on a separate level connector or grade transition from that evidence. Do not move the wide bridge or assume a convenient target deck. |

**Exact exceptional contours**

- Corner south lane2, side6401: `(76,-960,68)` to
  `(-96.626,-960.387,68)`; side6443: `(-96,-960,68)` to
  `(-304,-960,68)`.
- T north lane1, side7463: `(-396,960,68)` to
  `(-223.374,960.38600000000008,68)`; side7493:
  `(-224,960,68)` to `(-15.9999,960,68)`.
- These saved edge fragments have overlapping lateral intervals and a small
  noncardinal retreat. A taper based solely on the aggregate380 width would
  conceal the contour rather than establish a physical seam. Validate the
  actual source floor union and connector's complementary footprint.
- Current ordinary ramp floor sides1172/1256/1267 have south mouth
  X-128..128/Y-320/Z36 and north split X-260..-4/Y320/Z68,
  X0..256/Y320/Z96. Their measured internal rise starts at Y128/Z36.
  Do not confuse these existing branches with an approved connector design.

**Authoring and integration gates**

1. Before drawing any piece, identify the exact source mouth and transformed
   intended neighboring slot, including core/border/outer leases. Establish
   required span from the two actual endpoints and measured obstacles; do not
   invent a640-unit length when the accepted assembly leaves another span.
   The road's final ordinary-road/bridge endpoint must be surveyed first.
2. Keep the connector separate under `tiletemplates/roads`, with an explicit
   rectangular footprint name and ground-centered origin. A road taper is not
   a ground patch. Preserve existing half/quarter/precise editable infill.
3. Measure the full connector winding/brush-entity/prop envelope, rail and curb
   endpoints, pedestrian width and player hull clearance. No roadway scaling,
   buried duplicate solids or collision overlap disguised by ground infill.
   A legitimate upper/lower bridge crossing needs layer-aware reservation and
   measured vertical separation, not a blanket XY overlap exemption.
4. Extend only the existing minimal motorway registry/assembly owner.
   Store source hashes, edge provenance, nominal/rotated footprint,
   transformed floor contours, grades and deck, all occupied non-emitting
   slots, and one emitting owner. Unsupported combinations remain explicit
   failures; a connector does not automatically resolve corner+ramp or
   terminal+bridge topology selection.
5. Focused tests must connect both lanes/entire branch and preserve exact
   opposing headings, widths, grades, heights and contour coverage at all
   four rotations. Test source/connector and connector/straight solid/prop
   interference, ground coverage and underpass layers, plus protected straight
   and previously exact seam controls. Preserve artist edits on regeneration.
   Continue explicit rejection of unknown faces/materials, displacement,
   nonfinite inputs and incompatible ports.
6. Use new bounded current-source whole-cell fixtures without overwriting
   reviewed/open VMFs. Request human review only for the newly authored
   connectors, not the already-approved motorway cells/assets.
7. Ask before the bundled VBSP/visibility/full compile. Static floor checks
   and Hammer appearance cannot establish player collision, ramp traversal or
   multiple-Z clearance. Phase B remains open until those requirements are
   satisfied or the user explicitly carries the named limits forward.

The user explicitly trusts their authored motorway assets. This supersedes the
individual-asset Hammer approval gate: do not ask them to re-approve all eight
VMFs. Measurements serve generator integration, not an asset correctness audit.
Preserve authored geometry; review generated combinations or concrete unresolved
connections rather than reopening known-good sources.

The user additionally confirmed every orientation matches the corresponding
1x1 tile in each circumstance. Preserve the existing topology-to-yaw mappings
for this family. Do not ask for another orientation confirmation or infer a
replacement rotation from the footprint/geometry. Port positions, wider
reservations and height compatibility still need direct integration measurements.

[survey_motorway_templates.ps1](bin/survey_motorway_templates.ps1) reuses the
existing skybox KeyValues parser and records saved Hammer++ face windings,
material/solid/side ids, source hashes, entities and explicitly unverified
filename footprints. It does not infer ports from bounding boxes, include
model collision bounds or reconstruct compiled solids. Full report retained in
session storage. [test_motorway_survey.ps1](tests/powershell/test_motorway_survey.ps1) passes
5214assertions across eight unchanged sources, including byte-identical repeat
reports, face records and protected deck/overhang observations.

Saved-winding envelope observations (not compiled collision):

| Piece | X | Y | Z |
| --- | --- | --- | --- |
| Straight | -960..960 | -320..320 | 0..96 |
| Road bridge | -960..960 | -320..320 | 0..268.375 |
| Corner5x3 | -1600..1600 | -960.387..960 | 0..96 |
| Crossroads6x3 | -1920..1920 | -960..960 | 0..288 |
| T-junction6x3 | -1920..1920 | -960.388..960 | ~0..288 |
| Deadend3x3 | -1120..1120 | -960..992 | -225.328..480 |
| Onramp3x4 | -960..960 | -1280..1280 | 0..288 |
| Dual onramp3x4 | -960..960 | -1296..1280 | ~0..288 |

Straight carriageway floor faces120/126/252/258 lie at Z68; surface spans
X-720..-304 and320..736 give centres-512/+528. User confirmed canonical
north/south orientation and preservation of the authored16-unit asymmetry.
These are not the old +/-160 placements and must inform later runtime gates.
Bridge crossing-road floor faces642/690/738 lie at Z232.375, across X-960..960,
Y-128..128; its underlying motorway retains the straight's Z68. No assumption
of the old36/196 deck pair is permitted.

Straight opened in Hammer after updater delay and its exact title was verified.
The attempted bridge window reports `Error`; it is not visual evidence.
Do not retry opening every asset or close editor windows unsolicited. No assets,
settings, plans, maps or staged outputs changed; no compilation ran. Next is
direct port/envelope extraction and source-grounded assembly metadata, then
rotation/connection/reservation fixtures. Phase B remains incomplete.

#### Phase B rectangular reservation/rotation slice - 2026-10-13

[motorway_geometry.psm1](bin/motorway_geometry.psm1) adds a bounded wide-family
footprint lookup: unsuffixed straight/road bridge are explicit3x1; the six
suffixed pieces parse their named rectangles without square clamping. Legacy
`motorway_1x1` paths are rejected, including the same-name straight. This is a
nominal footprint registry, not a finalized port/assembly registry.

All four cardinal Source yaws transform physical points and separate winding
envelopes without changing Z. Nominal reservation takes an explicit top-left
logical anchor, records authored/rotated dimensions, centre, physical origin
offset from that anchor and every occupied slot with one emitting owner.
Logical Y increases south; physical origin-offset Y is negative. Even-width
6x3 pieces and rotated3x4 ramps retain half-tile centre alignment rather than
rounding it away. The nominal rectangle does not absorb deadend/ramp overhangs:
the separate envelope rotates those unchanged.

[test_motorway_geometry.ps1](tests/powershell/test_motorway_geometry.ps1) passes614assertions
covering all eight pieces/four rotations, unique complete slot sets, ownership,
half-tile alignment, point/inverse transforms, overhang rotation, explicit
unsupported/legacy rejection and the actual existing planner yaw owner.
Editor diagnostics and diff whitespace pass.

No planner/builder imports this helper yet. It does not choose an assembly's
anchor, allocate ring leases or prove collision-free combinations; those need
the remaining connector positions/translation solver and layer-aware assembly
fixtures. Ports and any additional authored local-origin corrections remain
separate measured inputs. Existing settings, source geometry, generated maps
and staged gameplay are unchanged. Phase B remains in progress; no expensive
job or further asset-opening/re-approval ran.

#### Phase B straight/bridge surface ports and translation - 2026-10-13

The geometry module now extracts source-backed port records for the wide
straight and crossing bridge from explicit saved face ids, checking material,
horizontal surface, non-displacement status and exact segment continuity.
Each motorway carriageway floor is416units wide, Z68, centres X-512/+528,
at Y+/-320. The bridge retains those motorway ports and adds its central
ordinary-road floor ports X+/-960,Y0,Z232.375,width256. That256 width describes
the central floor only, not the higher surrounding curb/sidewalk surfaces.
Port records retain face-id provenance and zero outward grade for these flat
floors. Unknown complex-piece ports fail instead of using bounding boxes.

`Convert-ZMMotorwayPort` transforms position and heading through the same
physical yaw/translation convention. `Resolve-ZMMotorwayPortTranslation`
solves horizontal translation at an explicitly supplied existing yaw and Z;
it does not choose a new yaw or adjust elevation. Route type, surface width,
opposed headings, outward grade and deck height must match exactly. Exact
matching is intentionally limited to these shared planar straight/bridge
surfaces; no arbitrary numerical tolerance is imposed on remaining curved/
sloped mouths. Such source precision/compatibility needs separate evidence.

Fresh survey/port fixtures pass5245assertions; geometry fixtures614pass.
They join both straight carriageways simultaneously in all four rotations
and connect the bridge's underlying motorway surface at the same translation.
They reject width/type/heading/grade/deck mismatches and unrecorded complex
ports. Editor diagnostics report no errors. These are saved-source surface
and algebraic seam checks, not compiled collision or driveability acceptance.
All eight source hashes remain unchanged.

Complex junction/terminal/ramp port contracts, road approaches to the elevated
bridge, pedestrian clearance, layer-aware reservations and whole-cell assembly
fit remain open. The measured complex surfaces include small authored decimal
offsets; preserve them, do not snap/rotate assets or assume tolerance from their
AABB. No planner wiring, asset edits, regeneration, compilation, staging or
additional human asset review occurred.

#### Phase B generated assembly inspection gate - 2026-10-13

The user requested continuation through Phase B to an actual generated Hammer
preview, rather than stopping at successive helpers. The isolated inspection
generator is [build_motorway_preview.ps1](bin/build_motorway_preview.ps1):

```powershell
.\bin\build_motorway_preview.ps1 -WorldProfile preview
.\tests\powershell\test_motorway_geometry.ps1
.\tests\powershell\test_motorway_survey.ps1
.\tests\powershell\test_motorway_preview.ps1
```

Default output is `generated/phase_b_motorway`, not a normal recipe plan or
staged profile. An optional `-OutputDirectory` must stay below `generated`.
The overview `motorway_phase_b_preview.vmf` presents all eight canonical
pieces with straight continuations. Eight `<piece>-rotations.vmf` files each
present 0/90/180/270-degree cases. Every case has a saved Hammer camera.
The overview is arranged left/right, north-to-south:

| Row | Left | Right |
| --- | --- | --- |
| 1 | Straight | Crossing bridge |
| 2 | Corner | Crossroads |
| 3 | T-junction | Deadend |
| 4 | Single ramp | Dual ramp |

These are **generated integration fixtures**, not requests to re-approve
authored assets. No geometry, saved orientation or source companion changed.
The overview contains26instances: eight main pieces and eighteen motorway
continuations. Ordinary-road approaches are deliberately not fabricated.
Point targets identify the piece/mouth and exact, diagnostic or pending status;
inspect both carriageways at each seam, not just the initially aligned lane.
The exact overview was opened in installed Hammer++; PID2288 is responding
and its full window title resolves to this generated fixture. Existing editor
windows were preserved. Opening it is not human visual acceptance.

`Get-ZMMotorwayMouthRegistry` retains explicit source floor-face ids, complete
mouth edge endpoints, fractional coordinates, width, Z and outward grade.
Grade is derived from the saved floor plane, not hardcoded. Nonfinite, missing,
wrong-material, displacement and non-floor evidence fails explicitly. Edges
retain continuity gaps and common-cardinal/grade flags. The terminal exposes
only its southern motorway mouth, not a false through exit.

Across32rotation cases,40mouth joins satisfy exact floor position/width/grade/
planarity/continuity checks.32joins are explicitly diagnostic/unapproved, and
20ordinary-road mouths remain approach gates. Diagnostic continuations align
one lane in X/Y for inspection only: no scaling, Z correction, source snapping
or arbitrary tolerance. They are not normal planner fallbacks.

Concrete integration evidence requiring generated review:

| Piece/mouth at canonical yaw | Recorded residual/constraint |
| --- | --- |
| Corner east | Other carriageway differs16units |
| Corner south | Other lane differs2units in centre and36units in width; curved/non-cardinal edge |
| Crossroads west/east | Other carriageway differs48/47.611units |
| T north | Curved first lane is about36units narrower; other centre differs about2units |
| T west | Other carriageway differs16units |
| T east | Other carriageway differs0.001unit; tiny binary width residual retained separately |
| Dual ramp west | Source endpoint differs0.000152588unit; no invented acceptance tolerance |
| Existing ordinary road onramp | Floor faces1172/1256/1267: southern Z28, northern split Z56/Z88; not new ramp Z96 or bridge Z232.375 |

The last row is measured from world **and brush-entity** solids, with source
hash and exact vertices in `assembly-report.json`. The first extraction attempt
looked only at world solids and failed explicitly; including brush-entity
owners fixed it, then the actual generation/fixture checks passed. No road
approach was emitted to conceal the mismatched decks.

Each placement emits once; its occupied lease records are non-emitting.
The report includes authored/rotated rectangles, cell-local origins, transformed
winding envelopes and conservative core/border/outer tile coverage within the
5760frame. All current winding envelopes fit that frame at all four rotations.
Corner/T inspection continuations produce conservative positive-volume
envelope overlaps, explicitly marked for solid/clearance review. An AABB
intersection is not proof of collision; absence is not prop/displacement/
pedestrian clearance proof. No broad underlay permission is inferred.

Fresh checks: geometry614, source survey/mouths5662, generated preview1834
assertions pass. Preview tests parse the actual VMFs, resolve every instance
to the exact source, verify emitted transforms/cameras/owners/ring coverage,
repeat generation byte-identically and reject authored/staged output paths.
All eight motorway sources and the existing road approach retain their hashes.
Settings, tuned plan and both installed runtime exports retain the recorded
Phase0baseline hashes. No GLua changed, no compiler/world refresh/staging ran.

Phase B remains **in progress at its generated inspection gate**, not accepted.
Still required: human review of the generated joins, an evidence-based decimal
tolerance decision, approved road approaches/caps, real solid/pedestrian/
underlay clearance and supported whole-cell topology contracts. Corner+onramp
composition and isolated motorway caps remain unresolved; no crossed-straight
or legacy1x1 substitute is approved. Do not advance or wire diagnostic joins
into normal placement simply because the focused tests pass.

#### Phase B complete-cell inspection - 2026-10-13

**User clarification:** the requested Hammer preview is a complete generated
cell, not a catalogue of authored pieces. The earlier assembly overview is
diagnostic evidence only and does not satisfy that request. Do not reopen it
or individual assets for routine approval.

[build_motorway_cell_preview.ps1](bin/build_motorway_cell_preview.ps1) now
selects two real plain-straight cells from the matching tuned preview manifest,
preserving its seed1337, grid24 and neighbor/transport records. The scoped
fixture removes unrelated safe-zone map records, not actual saved world data.
It calls the normal planner and cell builder with an explicit
`-MotorwayCellInspection` opt-in:

```powershell
.\bin\build_motorway_cell_preview.ps1
.\tests\powershell\test_motorway_cells.ps1
```

| Complete cell | Logical / raw grid | Current generated VMF |
| --- | --- | --- |
| North-south motorway | (6,-11) / (6,1) | `generated/phase_b_motorway_cells/src/zz_preview_d99234eb1730-edge2-motorway3-inspect.vmf` |
| East-west motorway | (2,-5) / (2,7) | `generated/phase_b_motorway_cells/src/zz_preview_45f63957fce2-edge2-motorway3-inspect.vmf` |

These are normal sealed-cell shell, lighting, skybox-room and ring outputs,
with current authored scenery around an actual planned wide corridor, rather
than a road-only zoo. The straight remains on the existing cell axis at the
approved0/90yaws; nine3x1stripes reach the full5760visual footprint through
core, border and outer rings. Fifteen core slots and six slots in each ring
are explicitly reserved. Five core owners and four ring owners emit once,
with ten non-emitting core occupancy records; ring scenery/walls are suppressed
only where leased. Each cell emits64instances:15core,20border,28outer,
one separate skybox room. Ten core shoulder slots retain terrain/decorations;
building/macro insertions are replaced by planned terrain with explicit reasons.
This is not persistent landmark relocation or full Phase D density acceptance.

The fixture's own settings use retained1x1sources only for the intermediate
ordinary-axis plan and current tagged border walls/corner1a to repair stale
references locally. The final cell VMFs contain no1x1motorway, single-width
gate blocker, building or carpark fallback. Root settings remain unchanged.
Unsupported corner/ramp/bridge/coast/landmark cells fail explicitly. Inspection
plans cannot enter the builder without its opt-in and isolated cell/skybox
directories. Legacy narrow transition triggers are not emitted: these are
geometry inspection cells, not staged/live-travel-ready releases.

Fresh complete-cell suite568assertions passes, including actual VMF parsing,
source-path resolution, all25core slots,27corridor leases, axis/yaw/Z,
640-unit consecutive stripe spacing, exact ring instance counts, shell/cameras,
scenery exclusion and byte-identical repeat VMF/layout generation. Ordinary
planner/builder control cells still emit their original family and placement
origin formula. Required-cell check2/2passes. Existing geometry614,
source-mouth5662and assembly-preview1834assertions pass; changed PowerShell
parsers/editor diagnostics and diff checks are clean.

Both generated cells were opened in Hammer (PID11944north-south,
PID7972east-west), with responding windows showing their respective generated
cell paths. The user explicitly confirmed **both cells were inspected and
were fine**, then deliberately closed all editor windows. No crash diagnosis
or reopening is required. This accepts the two complete straight-cell visual
examples, not every complex topology or whole Phase B.

No compilation, visibility-budget refresh, world-wide regeneration, runtime
export, staging or gameplay change occurred. Source assets, root settings,
tuned baseline plan and both installed runtime exports retain their hashes.
Remaining Phase B integration covers complex whole-cell topology/approach/
clearance contracts; production/default activation and full density/boundary/
travel migration remain in their owning phases. Do not treat the accepted
straight examples as permission for legacy substitutions or complex seam
tolerances.

#### Phase B remaining complete-cell previews - 2026-10-13

The user requested non-straight cells after approving both straights. The
wrapper's `-Complex` mode now builds seven complete diagnostic cells through
the normal planner/builder under `generated/phase_b_complex_cells/src`.
Sources and existing yaw mappings remain unchanged:

| Piece | Logical coordinates | Complete-cell filename |
| --- | --- | --- |
| Corner, east/south | (15,2) | `zz_preview_2cbc234ca457-edge2-motorway3-inspect.vmf` |
| Crossroads | (6,-5) | `zz_preview_aef7409cec95-edge2-motorway3-inspect.vmf` |
| T-junction, north/east/west | synthetic, based on(15,6) | `zz_preview_f1c08df1f698-edge2-motorway3-inspect.vmf` |
| Southern terminal | (6,-12) | `zz_preview_f9d57317dae7-edge2-motorway3-inspect.vmf` |
| Bridge | (17,-10) | `zz_preview_a95ba5489149-edge2-motorway3-inspect.vmf` |
| West single ramp | (6,-9) | `zz_preview_5a9abd1896bf-edge2-motorway3-inspect.vmf` |
| East/west dual ramp | (17,-8) | `zz_preview_1d13f04e4234-edge2-motorway3-inspect.vmf` |

No T-junction exists in the current preview world: its separate fixture changes
only the scoped crossroads manifest and explicitly records that provenance,
not a claim of a real neighbor graph. Schema2 carries exact fractional XY,
unchanged yaw/Z0, emitting owners and conservative saved-winding leases across
all three rings. Ordinary approaches include brush-entity windings. Every
actual continuation/approach participates in positive-volume envelope overlap
reporting, and below-terrain/frame-overhang geometry is flagged.

`test_complex_motorway_cells.ps1`:2682assertions pass, required7/7, written
instances/layout hashes and byte-identical repeat outputs verified. Existing
straight/normal-control568, geometry614, source-mouth5662and assembly1834pass.
PowerShell parse/editor diagnostics and diff checks pass. No GLua changes.
Initial serialization used `R` on integer origins; explicit double conversion
fixes it without rounding fractional placement. The test's transformed-vertex
oracle now retains its vertex across PowerShell `switch`'s temporary `$_`.

**Still unresolved, not successful connection claims:**

- Two-lane seam residuals retain the measured exact/diagnostic classifications.
- Crossroads/T E/W arms end320units before the visual boundary without scaling;
  the T north envelope retains its0.388-unit source residual.
- Ordinary-road approaches stay at original Z, with deck/grade mismatches
  explicitly unapproved. Partial ring slots remain conservative reservations.
- Bridge `bridge-horizontal` retains existing yaw90, but measured motorway
  ports then run E/W while the source cell expects N/S. Resolve the integration
  contract; do not silently rotate user-trusted assets or discard this evidence.
- Real corner/ramp(13,6) and terminal/bridge(17,-12) combinations fail explicitly
  before geometry; both negative fixtures pass. They need a composition
  contract, not fallback to just one route.
- Conservative AABB overlap is not solid/prop/displacement/pedestrian clearance.
  The terminal's negative-Z geometry still needs shell/underlay review.

Human review has identified missing ground infill beside transport pieces and
inside the corner's reserved envelope. Whole-slot conservative scenery
suppression does not prove complete ground coverage; add a separate coverage
contract/regression without weakening building/prop exclusion. Half320x640
and quarter320x320 plain-ground fillers were initially discussed; the user
subsequently chose editable source templates with generated plain default
bases so artists can add decorations.

The user explicitly confirmed the dead-end piece is fine, with only missing
surrounding pieces in its complete-cell preview. Preserve the authored terminal
and its placement; address missing ground through generator infill, not an
asset redesign. This is scoped human approval of the terminal piece, not
complete-cell ground coverage, compiled clearance or whole Phase B acceptance.
The user also confirmed the T-section is fine, with black voids from missing
surrounding ground pieces. Preserve the T geometry/placement; its scoped visual
approval does not accept missing infill or change the explicitly synthetic
fixture provenance. Ground coverage remains a shared generator defect across
the reviewed complex cases, not a request to redesign each source.
The user confirmed the crossroads is fine except for missing ground. Preserve
its geometry/placement and record scoped visual approval of the crossroads,
not complete-cell infill or compiled/travel acceptance. Its screenshot shows
missing surrounding strips consistent with the shared ground-coverage issue.
The user then declared all Hammer VMF checks complete and requested continuation.
Do not reopen the original source/layout review. Missing ground remains an
explicit correction gate, not Phase B acceptance or permission to change the
approved motorway assets. No BSP/visibility
job, full-world regeneration, staging, runtime export or production change.
Phase B remains in progress; approved straights are not reopened.

#### Phase B editable ground infill - 2026-10-13

Created editable `tiletemplates/terrain/infill/tile_ground_half.vmf`320x640
and `tile_ground_quarter.vmf`320x320, canonical center0, ground Z0..32,
unchanged original grass/material/UV scale. Source initializer creates only
missing files and preserves all artist-owned edits. No decoration variants
or automatic discovery enabled; added props/details need independent clearance.

Shared infill owner projects each saved convex brush at the ground slab,
including brush entities, rather than treating whole scenery leases as ground
coverage. Underground footprints remain protected against filling depressions.
Every fully empty quarter slot gets exactly one editable template instance;
adjacent slots coalesce to halves with yaw0/90. Geometry is not scaled or moved
vertically; motorway sources, placement and scenery reservations stay unchanged.
Partial/curved/fractional slots are explicitly conservative review exclusions.
This is not full arbitrary-polygon ground coverage or a compiled collision claim.

Seven corrected complete previews are under `generated/phase_b_infill_cells`,
with91ground instances: corner4, crossroads17, T19, terminal18, single ramp19,
dual ramp14, bridge0(the measured slab does not expose a fully empty quarter).
The half/quarter selection fixture proves an isolated quarter hole emits the
quarter source even though the current complete-cell cases pair into halves.
Ground owners/area/source fingerprints are in actual layout metadata.

The first corrected Hammer comparison revealed remaining crossroads gaps:
whole empty quarter-slot coverage is insufficient for offset/narrow regions.
Do not call that cell fixed based on the quarter-slot test. Measure partial
uncovered polygons separately before selecting additional sizes or clipping.
The user explicitly confirmed the corrected corner is correct and perfect;
that corrected corner ground/layout review is accepted and must not be repeated.

Fresh infill22345assertions, complex2864, straight/normal-control568 and
required7/7pass. Repeat cell/layout outputs are byte-identical. Parse/editor
diagnostics pass; no Lua changes. Other corrected visual appearance, partial-gap
coverage and compiled clearance remain unverified. No BSP/nav/world/staging/
runtime/production work authorized or run.

#### Phase B measured-size patch correction - 2026-10-13

**Complete infill / cleanup / building-centering continuation:** user requested
retiring unused infills, opening every complete motorway cell for review, then
continuing Phase B. User additionally authorized repairing misaligned buildings
and the army-wall offset. This is not production activation or expensive work.

Complete polygon infill emits320instances across seven complex cells and uses
34active convex shape sources. Infill271563assertions pass: actual emitted
polygons, no positive ground/filler overlap beyond bounded floating arithmetic,
source prism plane/winding/half-space validity, and six full ground frames
at0/90/180/270. This is transformed emitted geometry, not four separately planned
topology examples; approved corner remains unchanged. Complete complex3309/
required7/7and repeat-output determinism pass. Initial actual-prism checks
exposed a shared-array reversal that flipped bottom/side windings; fixed by
cloning the top array, then explicitly repaired34byte-identical unmodified
defaults with verified originals retained. No artist-edit overwrite.

Exact polygon/dimension/origin identities survive JSON round trips. Translated
area/orientation and separating-axis arithmetic reject false microscopic slivers
without a fixed spatial tolerance; a real0.000001-unit strip remains detected.
Cleanup uses matching final layouts and actual VMF dependencies, plus authored
nested references.92unused defaults archived with verified originals and cleanup
ledger;76sources remain. Half/quarter, edited/unknown/VMX-owned sources protected.
Tagged `tile_ground_patch_u64_u320.vmf` is still used and retained. Cleanup
idempotence and current dependency resolution pass. Historical superseded
fixtures may require restoring their archived defaults; do not treat them as
the current inspection set.

All41building VMFs audited. Eight sources had small actual ground-plane errors
hidden by rounded saved windings; repaired only their standard ground geometry.
The2x park is a separate proven common offset:31nonoverlapping ground partitions
sum to the full1280x1280 footprint at X-640..640/Y-608..672. Moved its entire
source Y-32, preserving internal ground subdivision, props and locked textures.
Army-wall full640-square reference moved X-2.542. No building-body realignment
was inferred from props or decorative geometry. Known standard ground defects
now0; ground reference55assertions pass. Displaced/partial bases are not fully
validated automatically. Originals remain hash-backed; VMX companions untouched.

Opened nine exact complete-cell previews in Hammer: vertical/horizontal straight,
corner, crossroads, synthetic T, terminal, bridge, single and dual ramp. Native
document captions match9/9and all editors respond. Complex current sources are
under `generated/phase_b_complete_infill_cells/src`; straights remain under
`generated/phase_b_motorway_cells/src`. Opening is not human approval. Preserve
these editors and unsaved work; no new source edits while that review is active
unless the user explicitly redirects. Phase B is still in progress; actual
bridge/approach/seam/combined-topology and compiled/live gates remain.

**Subsequent ground-contract prerequisite, 2026-10-13:** user requires ground
standardization, origin centering and warnings wherever tile sources are used.
The reference is the current640x640/Z0..32 world box with known terrain top and
original placeholder side/bottom materials, not arbitrary grass-looking/world
geometry. Displacements, slopes/curves, props, elevated/brush-entity floors and
custom partial infill are separate. Complete declared rectangular ground
coverage establishes the source center; partial/asymmetric ground cannot.
Confirmed whole-source offsets move roads/props together with locked textures;
proven sub-unit ground-only defects update planes and saved windings only.
Normal generation warns but never edits source assets.

Shared `tile_ground_grid.psm1`, audit/explicit repair entrypoint
`repair_tile_ground_grid.ps1` and focused classification/origin fixtures added.
Verified original source backups live under `generated/tile_ground_grid_repair`.
Corrected T-junction common Y-0.388 offset; snapped31plain ground brushes across
T18, dual ramp12 and ordinary ramp1. No topology/yaw changes. Remaining north
continuation X306.00005 comes from lane alignment, not ground-centering error.
The army-wall tile's X2.542 reference offset remains an explicit warning and
review item; do not silently move its approved overhangs.

Fresh sized previews are isolated under `generated/phase_b_grid_infill_cells`.
T nonrectangular gaps64->12; all37sub-unit T slivers disappear. Accepted corner
and crossroads VMFs are byte-identical. Other nonrectangular fragments and
all-family/all-yaw complete-infill coverage remain open. A prior shaped-default
build failed because serialized polygon coordinates changed source identity;
invariant polygon coordinates now retain that identity, but the complete shape
workflow is not accepted or claimed passing yet. No BSP/nav/material/staging/
production/live work ran. Settings, tuned production-independent plan and both
runtime exports retain their recorded hashes.

Validation: ground fixtures53assertions, sized infill68339, complex-cell2843,
straight/normal controls568, measured geometry614 and source-mouth5662pass.
PowerShell parsing8/8 and diff checks pass. Actual generation emitted the
army-wall ground/origin warnings, proving pipeline wiring rather than just
an isolated diagnostic. Seven regenerated cells emit256ground instances.
No new Hammer visual approval or compiled clearance is claimed.

The user reported remaining crossroads voids in the first infill preview.
Measured rectangles include304x320,16x320and320x48, so no fixed320-wide
template can cover them without overlap. The user approved creating additional
precisely sized editable base sources, preserving existing templates.

The explicit `-SizedInfill` inspection workflow measures polygon differences,
creates missing rectangular patch defaults once, and rebuilds isolated cells.
34sources total (two base plus32measured patches) are artist-owned; filenames
encode physical unit dimensions rather than tile counts, preserving fractions.
No source is overwritten. Seven corrected cells under
`generated/phase_b_sized_infill_cells` emit261ground owners (91whole-slot
and170rectangular patches). Nonrectangular fragments remain disclosed.

The test now requires **zero uncovered polygon area across the entire actual
crossroads ground frame**, not merely coverage of wholly empty quarter slots.
Fresh sized infill67550assertions pass, including patch-source dimensions,
actual origins, original-ground exclusion, pairwise filler exclusion, exact
rectangular-fragment coverage, repeated-source preservation and324zero-gap
crossroads cases. Summed-area comparisons account for floating arithmetic only;
no spatial seam tolerance introduced. Invariant round-trip origins preserve
fractional coordinates. Straight/ordinary controls568pass. Final sized
complex-cell suite3204assertions, required7/7, repeat-output determinism,
PowerShell parsing and diff checks pass.

The user explicitly approved the corrected corner as correct and perfect.
Its actual VMF is byte-identical between the initial and sized infill previews;
do not reopen that review. The exact sized-infill crossroads was opened in
Hammer (PID3760, responding, full child document path verified); the user
confirmed the crossroads cell is great. Corrected crossroads ground/layout
review is accepted. Do not repeat either accepted corrected-cell review.
Other nonrectangular gaps and compiled clearance remain separate. No expensive compilation/staging/
world output job or production change ran.

#### Phase B refreshed rectangular-infill compile - 2026-10-14

The user requested completion of Phase B. Refreshed the seven current-source
complex cells in `generated/phase_b_power2_infill_cells` without changing
approved motorway sources, settings, normal planner selection or installed
runtime data. Fresh focused checks pass: geometry614, source survey5696,
assembly preview1806 and complete-cell/infill3625 assertions. Required-cell
validation finds all seven fixture VMFs.

The bounded compile completed VBSP7/7 and then VVIS/VRAD7/7 under the fast
preview preset, with zero failed/incomplete maps. The portal-budget report
checks7/7 maps, zero over-budget/invalid files, and a maximum365 clusters/
1055 portals against limits1500/2700. Reports are retained alongside the
fixture outputs. This validates compiler stages and visibility budgets only;
it does not establish player collision, pedestrian/underlay clearance or
driveability.

An attempted Hammer++ refresh review opened the exact generated fixture paths,
but the seven-window launch did not remain stable: several editor processes
exited before all document captions could be verified. Known crash-recovery
prompts were declined without selecting recovery files. Therefore the new
rectangular-infill appearance has **no fresh human visual acceptance**.

Phase B is still **not complete**. The assembly report remains48 exact,
24 diagnostic lane joins and20 unapproved road approaches over32 rotations.
The missing connector geometry, unsupported topology policy, real solid/
prop/displacement/pedestrian clearance and refreshed visual review are not
resolved by compiling diagnostic cells. Preserve the approved source art and
keep those arrangements out of normal planner support until each contract is
closed. No world-wide generation, staging or production build ran.

#### Phase B decorative-ground infill correction - 2026-10-14

The initial rectangular patch minimum was 16 units. This sizing threshold is
superseded only by the user-approved U4/U8 follow-up below; the rectangular,
integer, bounds-exclusion and default-floor contracts remain.

The crossroads image first exposed generated ground overlapping authored
surfaces in `tiletemplates/decorations/tile_bushes_1aa.vmf`. The original
patch47 (`256x256`) and patch48 (`256x128`) crossed the concrete slab, solid1945
(240x384), and its adjacent16x384dirt lip, solid1946. After the slab was
protected, the regenerated16x256and16x128 edge patches still duplicated that
existing dirt lip. The user correctly identified both remaining strips as
unwanted.

The first infill correction protected only these two reviewed surfaces, using
fail-closed signatures for solid id, top material, six box windings, exact
bounds and Z0..32 height. It removed the specific overlap, but was deliberately
not a general solution; the user then directed that this must be based on
geometry bounds in the candidate region, not artist-selected textures.

#### Phase B regional brush-bounds infill correction - 2026-10-14

The source-specific exception is superseded. For each world or brush-entity
solid, the infill owner now checks its saved windings against the actual
Z0..32 fill slab. Solids with positive vertical overlap contribute a
conservative local XY bound from winding vertices clipped to the slab edges;
the bound is transformed by the source instance's cardinal yaw. Materials,
asset names and special solid IDs are not used. Recognized ground bases remain
the only eligible infill coverage sources; other geometry only excludes
overlapping candidate regions and never creates a polygon/decimal filler.
Brushes merely touching the slab boundary are not treated as positive-volume
overlaps. AABB exclusions are conservative authored-geometry checks, not
compiled collision/clearance proof.

The focused test changes the decorative floor to an arbitrary artist-selected
material and verifies the same geometric bound is retained. Complete-infill
regression passes68,868assertions; the seven-cell integration/repeatability
suite passes3,357. All344 emitted rectangles are integer-aligned, preserve the
existing full/half/quarter templates, use only power-of-two dimensions >=16
for extra patches, and do not intersect classified ground or regional brush
bounds. The prior seven-cell output had472 instances; the new bounds exclude
additional occupied regions without inventing irregular fillers.

Final isolated outputs are under
`generated/phase_b_regional_bounds_infill_20261014` and
`generated/phase_b_regional_bounds_complex_20261014`. All seven final layout
hashes match their actual VMFs. The user confirmed checking the open Hammer
cell previews and that they looked fine, then closed the editors; this run did
not reopen or compile them. The regenerated bounds outputs themselves have not
been compiled. Phase B remains open for connector/approach, clearance and
supported-topology contracts; no staging/production authorization is implied.

#### Phase B support-policy disposition - 2026-10-15

The user chose to defer connector assets and keep incompatible motorway
combinations and ordinary-road approaches unsupported. This supersedes the
earlier direction to prepare connector requirements as the immediate next
implementation slice; it does not approve changes to authored motorway sources.
The measured report now distinguishes 48 exact floor-mouth candidates
(full-solid and clearance validation pending), 24 unsupported mismatched
motorway mouths, and 20 unsupported ordinary-road approaches. Every generated
transport placement is marked `inspection_only`; exact surface matches are
not represented as clearance-validated, and unsupported diagnostics cannot
become planner fallbacks.

Fresh support-policy regressions pass: motorway preview1900 assertions and
complete complex-cell generation3487 assertions. They verify the explicit
dispositions against measured connections and emitted inspection instances.
Current complete-infill outputs in
`generated/phase_b_final_compile_20261015_f544a6d7d80f414eafde83d02f6032d9`
pass VBSP/VVIS/VRAD7/7; all seven are within the 1500-cluster/2700-portal
budgets (maximum370/1064). This compile proves neither collision clearance nor
live traversal. The user reviewed and accepted these seven exact fixtures in
Hammer++ and accepted Phase B with the explicit limits above. No staging,
production build, or publication is authorized.

#### Phase B accepted with limits; U4/U8 infill follow-up - 2026-10-15

The user accepted Phase B after reviewing the seven final bounds-based
complete-cell fixtures in Hammer++. Keep exact floor-mouth seams marked
clearance-pending, keep mismatched motorway mouths and ordinary-road approaches
unsupported, and keep all generated assembly placements `inspection_only`.
Compilation and visual review do not prove collision clearance or live travel.
This acceptance authorizes Phase D source work and focused tests, not staging,
production builds or broad generation.

After identifying a remaining narrow gap in the synthetic T-junction preview,
the user approved U4 and U8 rectangular infill globally for any
bounds-verified uncovered rectangle. Each extra patch dimension remains a
strict power of two from 4 through 512; no dimension below 4 or fractional
patch is emitted. Fractional and sub-4 remainders remain explicit and are left on
the default black floor. Coverage still requires a recognized standard ground
base, and authored brush bounds only exclude covered candidate regions; no
material-specific matching, polygon source or `tile_ground_shape_*` source is
reintroduced. Existing approved road geometry and Phase B connector limits
remain unchanged.

The focused U4/U8 regression passes 78,498 assertions. It verifies the
observed T-junction 13x256 gap decomposes into U8 + U4 with only a 1-unit
remainder left on the default floor. The complete-cell integration passes
3,579 assertions; the seven cells emit 390 integer-aligned rectangular
instances.
The isolated updated fixtures are under
`generated/phase_b_u4_u8_infill_20261015_176149103747430597768558764c2f0d`.
They pass VBSP/VVIS/VRAD 7/7 with no failures or incomplete stages. Portal
budgets pass 7/7 (maximum 365 clusters/1,055 portals against 1,500/2,700).
The four affected outputs—crossroads, synthetic T-junction, deadend and single
ramp—were opened at their exact refreshed paths and confirmed responsive. The
user reviewed and accepted their U4/U8 appearance. This completes the bounded
infill follow-up without reopening Phase B's connector/clearance limits. No
staging or production build ran.

### Phase C - CSM capability evidence (experiment accepted; remainder deferred)

Originally scheduled after generator prototype gate G under the generator-first
decision. On 2026-10-14 the user explicitly moved this feasibility work forward
to run alongside the isolated preview regeneration/compile. This changes only
the Phase C order. The user subsequently accepted the current experiment and
deferred further CSM work; this section retains scoped historical evidence.

Unfinished capability checks now belong to the
[deferred CSM backlog](docs/csm-implementation.md#deferred-backlog-transferred-from-alpha-32).
They are not prerequisites for any remaining Alpha 3.2 generator phase.

- [x] User approved advancing the capability-only one-projector probe; measure
      `ProjectedTexture:Update` operation timing without a performance claim.
      No baked-lighting or shared-server lighting change is authorized.
- [x] Additive client-only diagnostic source at
      `gamemode/tests/cl_csm_feasibility_probe.lua`, manually enabled only on
      a deployed `zz_preview_*` cell with `developer 1`. GLua syntax passes
      274/274. The live projector/caster/receiver and native-baseline checks
      remain separate.
- [x] **Live readiness result, 2026-10-14:** current client is on
      `zz_preview_a7477221a688-oceanw-edge2`, preview profile. `util.GetSunInfo`
      returned no enabled sun, so the first guarded start correctly created no
      projector. This recipe inherits `light_environment` from
      `celltemplates/template_border_s.vmf` (`angles 0 0 0`, `pitch -75`), and
      `shadow_control` separately declares angles `80 30 0`; do not conflate
      those directions or toggle either entity. The probe now has an explicit
      test-only `light_environment` fallback for the preview recipe family,
      derived via Source SDK 2013 `src/public/map_utils.cpp` at
      `b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474`; VDC's page was unavailable
      behind Anubis and TWHL documents that pitch overrides angle pitch. This
      related-branch formula is not GMod branch proof. The fallback probe was
      run and removed; the user confirmed localized light and sun-aligned
      shadows on the world brush/telephone pole and tree leaves. Final status
      reported `prop_dynamic` under the crosshair. This validates only the
      observed preview cell/surfaces, not all props or alpha-tested materials.
      `ProjectedTexture:Update` averaged0.134ms / max1.003ms across1718 calls
      (call timing only; no performance claim).
- [x] User decisions for the permanent chest lamp: F replaces the native
      flashlight bind in gameplay; the light has no model/battery, is visible
      to all clients, and has no separate Options toggle. The chest test proved
      the cone follows aim. The user selected a performance-first design:
      unshadowed cone on the permanent lamp; sun-direction CSM remains separate
      and off until explicitly enabled.
- [x] User CSM Options decision: client-local CSM enable toggle (default off)
      and one Low/Medium/High quality selector. The selected mapping is Low =
      1 cascade / 15 Hz, Medium = 2 / 30 Hz, High = 3 / rendered frame rate.
      These controls are now wired to the default-off CSM source prototype;
      existing graphics presets do not change them.
- [x] Implement permanent F-toggle replacement of the native flashlight bind
      on generated gameplay maps; F on/off was live-tested in preview and the
      server NWBool report matched both states. The lamp uses the survivor
      `ValveBiped.Bip01_Spine2` bone, no prop/battery/persistent preference,
      stays off by default, and is cleared on death. Lamp state replicates so
      every client renders it; each client chooses the nearest4 within2048 units.
      Following the user's performance choice all permanent cones are
      unshadowed. The single-client live cone and F state passed; multi-client
      visibility, max-four culling, map/death transitions and restoration still
      require validation.
- Historical, focus-unmatched 10-second hook profiles with the shadowed chest test showed
      22.5/59.8/26.6FPS on/off/on, then the permanent unshadowed transform-cached
      lamp measured59.5FPS with it on versus59.8FPS off (captured hook0.262ms/frame,
      0.675KiB/frame, correcting the earlier0.081ms summary). The user noted the game may have been unfocused; focus was
      unrecorded, so these are not causal or general GPU performance evidence.
- The temporary rate-limited CSM probe supports 15/30/60Hz `Update` calls.
      Bridge-started profiles reported44.37FPS with one projector at60Hz,
      59.80FPS after removal, and22.85/23.31FPS at15Hz. A foreground-window
      monitor during the latter run recorded GMod foreground in0 of159 samples.
      The bridge workflow therefore cannot establish foreground performance;
      all these FPS values remain focus-unmatched and must not drive tuning.
      The CSM hook averaged0.216ms/frame at60Hz and0.095ms/frame at15Hz in
      those respective runs, which excludes engine/GPU shadow rendering. The
      test probe was removed and status verified inactive/projector-invalid.
      `SetSkipShadowUpdates` previously produced visually stale/missing shadows;
      it remains disabled and is not an approved optimization.
Disposition: current experimental scope accepted by the user; full
caster/receiver, environment/HDR, coexistence, pool, native-restoration,
Low/Medium/High appearance and matched foreground checks remain unverified in
CSM tracker Phase 0. No baked/shared lighting experiment is authorized.

### Preview regeneration / compile batch - user authorized 2026-10-14

The user clarified that renamed sources and the Phase A density policy require a
complete preview-city regeneration, not only a multi-tile fixture update, and
authorized the isolated seed-1337 preview compile while CSM feasibility moves
forward. Output root:
`generated/phase_m_preview_rebuild_20261014`.

- [x] Generate a new 24x24/576-cell manifest and plan with the `preview`
      profile and seed1337. Policy version1 is present; density tiers are
      low72, medium120, high384. The plan contains335 recipes, including the
      accepted density policy and renamed current template inventory.
- [x] Plan variety passes4807 assertions; actual layouts pass5966;
      1104 cardinal pairs differ; required cell VMFs are335/335.
- [x] Build all335 city recipe VMFs and3 reusable safe-room VMFs in the isolated
      `src` directory. No normal `generated/src_preview`, content, or game maps
      were overwritten.
- [ ] Full fast-preset compile attempted for338 city/den maps.336 completed,
      zero were incomplete, and2 VBSP stages failed:
      `zz_preview_97dcc3127e09.vmf` and `zz_preview_99a2fd788b1e.vmf`. Both
      include `tile_motorway_crossroads_6x3.vmf`; VBSP reports brush41926
      bounds out of range, then `HashVec: point outside valid range`. No
      VVIS/VRAD ran for those maps, no artifacts were staged, and no full
      capture/material rollout ran. The exact logs and report are under the
      isolated output's `build/logs` and `build/compile-report.json`. The
      affected authored motorway VMF is user-modified and remains untouched.
      Repair decision is pending; do not claim a complete preview build.

### Phase D - World generation, density pools and motorway-only scenery

- [x] Update settings/discovery from the approved inventory; validate every
      required explicit path before placement. No terrain fallback for a missing
      required motorway topology.
  - **Completed source slice, 2026-10-15:** all five motorway topology paths and
    the bridge/single-ramp/dual-ramp paths now point to their exact approved
    `roads/motorway_3x1` assets. Retained 1x1 paths are explicit in the isolated
    inspection wrapper only. The active motorway variant pool is omitted because
    the approved inventory has no footprint-compatible 3x1 alternatives.
    Missing untagged border sources were removed from the wall pool; the
    compatible tagged corner is the single default. Planner preflight validates
    all 67 explicit tile paths and rejects missing required motorway keys or
    sources before creating placements; motorway roads and dead-end caps have
    no terrain fallback. `test_template_inventory.ps1` passes14/14;
    `test_motorway_cells.ps1` passes568/568; `test_motorway_geometry.ps1`
    passes614/614; `test_tile_ground_grid.ps1` passes56/56. The current
    user-edited T-junction also received a verified ground-only snap of one
    640x640 slab's 0.388-unit offset, with a SHA256-backed original in
    `generated/tile_ground_grid_repair`; no roadway or non-ground content was
    moved. The unrelated `test_outer_edges.ps1` prop-count assertion fails
    before planner invocation (expects2 dynamic props where its unchanged
    source has4); left untouched. No full-world regeneration, compile, staging
    or publication. This does not reopen Phase B's accepted connector policy.
- [ ] Resolve density consistently across ordinary/special building pools,
      decorations, multi-tile features, open-terrain fill and recipe variants.
      Remove soft all-tier weighting where it violates hard exclusions.
  - **Planner enforcement slice:** policy-v1 manifests now use deterministic
    hard tier filtering for ordinary single-tile buildings, decorations,
    optional multi-tile buildings and open-terrain fill. Untagged candidates
    remain neutral only inside their compatible family/footprint pool; an
    optional shortage keeps terrain rather than selecting a forbidden tier.
    Selection keys include the cell variant. Legacy manifests preserve their
    previous behavior. Decorations can be placed on a motorway cell without
    building candidates. Fresh `test_scenery_density.ps1` passes2501
    assertions; an isolated 576-cell policy-v1 planner run recorded8075
    selections and4023 optional shortages with zero tagged tier mismatches.
    This is a source/fixture slice, not full Phase D acceptance: special
    building pools and fixed-identity conflicts remain open. No broad world
    regeneration, compilation or staging was run.
- [x] Extend corner selection to a validated variation pool where tagged corner
      alternatives exist; preserve a compatible single-corner setting for old
      fixtures. Do not silently discard the new tagged corners or borrow a
      differently oriented corner from another family.
  - **Standard border-corner slice:** policy-v1 recipes select from the
    compatible low/medium standard corner pool. The approved explicit
    high-target exception maps to the medium `tile_border_wall_corner_1aa.vmf`
    because no high or neutral standard corner is authored. `cornerTemplate`
    remains the legacy single-corner source; profile-specific neutral corners
    and water corners are unchanged. Builder preflight validates source paths,
    target coverage and that each explicit fallback is a different tagged
    member of the same pool. Fresh `test_scenery_density.ps1` passes2501
    assertions for low/medium/high and legacy/profile cases; `test_template_inventory.ps1`
    passes14 assertions/70 configured paths. `test_border_showcase.ps1` builds
    an isolated36-cell/7-topology fixture and verifies the high-target corner
    and its explicit exception record in the emitted layout. Source bounds
    retain the same 640-unit tile envelope; the generated fixture checks all
    four canonical corner yaws. Temporary fixture output was removed. Visual
    acceptance remains pending. No preview-wide regeneration, compile or
    staging was run.
- [x] Enforce density for compatible special-landmark variants; keep fixed
      physical identities via the approved exemption when their pool lacks the
      required density tier.
  - Policy-v1 named-landmark templates now use hard density selection within
    their established footprint; legacy manifests keep first-template behavior.
    A read-only inventory audit found low-only pools for Hospital, Laboratory,
    Leisure, Petrol Station and Park's 1x1/2x2 variants; Bunker and Church have
    low/medium 1x1 options; only The Epicenter currently has a full three-tier
    3x3 pool. Density-incompatible names are now density-exempt fixed
    features (see the superseding policy below). This is the approved
    resolution for current content gaps; additional density variants remain
    optional authoring work and must not be fabricated by the generator.
  - [x] Fixed-identity conflicts are resolved by the approved density exemption:
    physical landmarks remain at their assigned cell and retain the legacy
    template when no compatible density variant exists. No landmark variants
    are fabricated or inferred.
  - [x] **Occupied-route adjacency (2026-10-14):** border and outer wall adjacency
    now comes from `Get-ZMRouteFootprintSlots`: `roads/` placements across
    their full emitting footprint, non-emitting occupied records, motorway
    assembly/occupied/external-occupied roles and motorway inspection leases
    for the matching rings, plus the existing edge/continuation slots. User
    decision: carpark lanes, entrances and endcaps are not corridors. Fixtures
    cover a widened 3x1 corridor end, non-emitting occupied slots, external
    occupied terrain-template slots, carpark/building/terrain controls, ring
    filtering and an outer wall beside a border-ring lease (with a no-lease
    control). Route slots are identical to the old regex for all 576 cells of
    the current preview plan. Density 2528, motorway cells 572, safe-zone
    entrances, frontage and border showcase pass. No regeneration, compile or
    staging was run.
  - **Boundary wall/outer-edge density slice:** policy-v1 recipes now select
    border and outer-edge wall variants deterministically from the already
    selected functional/profile pool. The existing route-adjacent aaa exclusion
    is retained, with density target roll and per-placement selection metadata.
    Road, ramp, bridge, water, carpark, corner, and entrance paths remain
    unchanged; metadata-less recipes preserve their prior selector. Recipe
    layout identity includes the map seed consumed by this wall policy,
    preventing cross-seed filename reuse for different emitted wall variants.
    Focused density fixtures cover all three zones, all border-ring sides,
    profile-neutral pools, route-adjacent behavior, shortages, deterministic
    repeats, outer-edge selection, legacy behavior, and seed-sensitive identity.
    No full-world regeneration, compilation, staging or visual review was run.
- [x] Decouple decoration placement from the presence of a building pool.
      A motorway cell with zero building candidates must still place decorations.
  - Covered by the policy-v1 planner fixture: a zero-building-candidate
    motorway recipe places eligible decorations without producing a building,
    while retaining hard density exclusions.
- [ ] Reserve transport assemblies before scenery. Prevent every building/
      skyscraper/commercial/industry/carpark/physical-landmark insertion path,
      including forced fixtures/late macro passes, on motorway cells.
  - **Motorway exclusion slice, 2026-10-15:** the planner now suppresses
    ordinary building selection on motorway cells while retaining the existing
    decoration-only path; ordinary-road building selection is fixture-protected.
    It fails explicitly for stale settlement occupancy, forced carparks,
    physical/forced multi-tile landmarks, and safe-zone identities or entrances
    instead of dropping them. Complete rectangular assembly reservation,
    connector ownership and ring leases remain Phase E work; this does not make
    inspection-only Phase B assemblies planner output.
- [x] ~~Deterministically relocate conflicting named landmarks~~ —
      **superseded 2026-10-15 by user decision: physical landmarks are
      density-exempt and are never relocated.**
  - Reason: the seed-1337 policy-v1 generator probe proved relocation
    impossible. Leisure, Park, Hospital, Laboratory and Petrol have only low
    (`_1a`) templates, tier-1 zones exist only within three cells of the west
    coast, and roughly 28 Leisure/33 Park identities saturated that band
    (Leisure at 23,17 had zero compatible destinations). The user chose the
    exemption over relocation, new content or weakened ordinary density.
  - Generator: `Get-LandmarkDensityShortages` is report-only. Identity, cell,
    labels, tags and safe-zone inputs are unchanged; each shortage records
    identity/label, cell, zone tier/source, required target tiers, available
    tags, footprint, `moved=false` and `density_exempt_fixed_landmark` in
    `generation.landmarkDensityShortages`. The relocation selector and
    spacing/oscillation code were removed. Planner: an incompatible landmark
    pool keeps its legacy first template with status `density_exempt_landmark`
    and a `[Planner][Density]` warning instead of throwing.
  - Evidence: `test_scenery_density.ps1` passes 2505 assertions (single
    Hospital shortage, unchanged landmark/safe-zone inputs, no shortage for a
    compatible coastal cell, planner exempt fallback);
    `test_safezone_entrances`, `test_motorway_cells` (572),
    `test_building_frontage` and `test_skyscraper_height` pass. The isolated
    seed-1337 generator probe succeeds with 66 shortages over 79 landmark cells.
    Radiation sources keep their existing deterministic assignment; an
    original source on a motorway still fails before mutation.
- [x] Never drop landmarks, fabricate a safe zone or leave mismatched map
      labels: the exemption retains every landmark where generated.
- [x] Keep recipe reuse deterministic: density and assembly/port signature
      participate in identity; absolute distance need not create a unique recipe
      when the resolved layout policy is identical.
  - `Assert-RecipeFilenameContentUnique` fails planning if one filename would
    carry different builder inputs; its message now names the differing nested
    paths. The seed-1337 probe exposed `sceneryDensitySelection.excludedCount`
    (pool-size diagnostics 11/10, 4/2) varying under an identical resolved
    template/tier/status at cells 4,0 and 5,8. Like `inlandDistance`, the
    pool diagnostics (`excludedCount`, `excludedTags`, `exclusionReason`) are
    excluded from the signature; they remain in the plan and `.layout.json`
    from the recipe's first cell. Isolated planner run then passes the guard.
- [x] Preserve adaptive variation cap 4 and adjacent actual-layout checks;
      review total recipe growth against the accepted 311-recipe baseline.
  - Isolated seed-1337 policy-v1 plan (`generated/identity_probe`, since
    removed): 576 cells, 335 recipes (+24 / +7.7% over 311), 64 variant
    files, 238 bases, zero adjacent identical filenames. Variant indices stay
    within 1-4, but the cap applies per resolved content class: one 68-cell
    base splits into three density/content classes for 10 files total.
    Placement statuses: 3913 selected, 4225 `shortage_keep_terrain`
    (3514 open-terrain fill, 711 decoration; 4174 at zone3/target3 because no
    `_1aaa` terrain/decoration templates exist), 28 `density_exempt_landmark`
    placements. **User decision 2026-10-15:** keep bare terrain for these
    tier-3 shortages; no lower-tier fallback. The user will author `_1aaa`
    open-terrain/decoration tiles later, so do not weaken density selection.
    `test_cell_variants.ps1` now checks emitted layout JSON against the complete
    route footprint and motorway leases. A synthetic plan/layout fixture passes
    and confirms the assertion rejects an `aaa` wall beside an outer-ring
    motorway lease.
  - **Isolated plan/layout validation (2026-10-14, user-approved):** a fresh
    seed-1337 preview manifest, policy-v1 plan, 335 recipe VMFs and 335 layout
    files were generated under
    `generated/phase_d_variant_probe_20261014` only. The plan contains576 cells,
    335 recipes (+24 / +7.7% over311), 238 base groups, 64 non-base variant
    recipes and variant indices0-4. The high-reuse 68-cell base emits10 unique
    files; no recipe exceeds the configured four candidate variants.
    `test_cell_variants.ps1` passes4807 plan assertions and5966 assertions with
    actual layout JSON, including1104 cardinal pairs with distinct filenames
    and emitted layouts. `check_required_cells.ps1` finds335 required,338
    authored and0 missing VMFs. This current plan records28 fixed-landmark
    density exemptions across Park, Leisure, Petrol Station, Church,
    Laboratory, Bunker and Hospital; no tier fallback or relocation occurred.
    Compared with the persisted pre-density plan, active entrances, road/
    transport topology, world coordinates and water sides match at all576
    cells; `safeZoneEntrance` and its suppressed border tiles differ at three
    cells (16,0;22,12;3,18), retained as a separate layout delta. A baseline
    comparison therefore reports those differences; the user explicitly chose
    to keep the new deterministic placements on 2026-10-14. The plan/layout
    adjacency checks pass. No compilation, staging or live/visual check was run.

Exit: focused planner fixtures prove density exclusions, decoration-only
motorways, density-exempt fixed landmarks and unchanged intended travel graph.

### Phase M - Safe-zone detail experiment (CANCELLED)

**User outcome, 2026-10-14:** the user reviewed the proposed treatment, disliked
the effect and rejected the idea. Do not continue M0-M6, request more detail
approval, or replace it with another complex neighboring-cell system.
The chosen direction is larger and more interesting authored tiles of varied
width/height, placed by the ordinary generator. Actual authored dimensions,
placement/frontage and capacity limits must be handled in the existing
footprint integration work, not inferred from the rejected claim rules.

Removed the optional detail settings handler, two-pass scenery reservations,
neighbor claims/diagnostics, detail-dependent recipe/variant signatures,
builder replacements/halo emission and dedicated detail tests. Existing den
entrances, identities, relocation, density, roads, coast and world bounds stay
unchanged. Preserve the user's VMF/VMX assets and old isolated outputs as rejected
inspection history, not stageable/current artifacts. No detail-bearing world
was staged, so installed maps or player data need no restoration for this removal.
The earlier default-disabled preview compile is separate and still has its
two motorway brush failures.

Phase E no longer depends on an M claim table. CSM remains separately deferred;
production, staging, expensive rebuilds and publication still require approval.

**Removal validation:** PowerShell parse/editor checks pass for the four affected
scripts, with no remaining detail integration symbols in executable PowerShell.
Current density/selection/recipe-identity fixtures pass 2,528 assertions.
Fresh ordinary entrance fixtures pass 12 orientation/water and two rejection
cases using `-FixturesOnly`; the full-preview entrance baseline was not rerun.
The restored ordinary variety/route checks pass 4,807 assertions on the retained
576-cell/335-recipe plan (1,104 adjacent pairs). That is validation of the
retained plan, not a fresh generated world or live acceptance. No Lua, authored
VMF/VMX, installed map, compiler job or player data changed in this removal.

<details>
<summary>Rejected experiment history (superseded; not an implementation checklist)</summary>

Added 2026-10-14 at the user's request from
[the safe-zone entrance design notes](docs/safezone_entrances/plan.md); it runs
after Phase D and before Phase E. It replaced the earlier "safe-zone detail
deferred" note for planning purposes. **The following design/source authorization
was later superseded by rejection; it is no longer current.** On 2026-10-14 the user
explicitly authorized two clearly marked source test VMFs (Default-den and
Hospital) under `tiletemplates/safezone_detail`; these are blockout test assets,
not release artwork, and must not become planner candidates until M1. This
does not authorize any edits to the previously preserved working
entrance/detail walls, compiles, skybox model builds, staging or visual
acceptance.

Current baseline (read before changing anything):

- `Get-SafeZoneEntrancePlan` in `bin/plan_cell_templates.ps1` owns entrance
  placement. One 3x3 template (`safezones/entrance_safezone_3x.vmf`, authored
  `W`-side/`E`-facing) occupies an edge slot (`N/E/S/W`) or a corner slot
  (`NW/NE/SW/SE`) spanning core tiles 0..1 or 3..4 and border ring -1 or 5.
  Its `suppressedBorderTiles`, `interiorTiles`, `yaw`, `frontage`, `slot`
  and `mode` are serialized on the recipe and included in recipe identity.
  Slots that cover a road gate or water are rejected; the cross-junction case
  uses corners only. `tests/powershell/test_safezone_entrances.ps1` covers it.
- Each cell's frame is tiles -2..6 (core 0..4, border ring -1/5, outer ring
  -2/6, owned by `bin/outer_edges.psm1`). Neighbouring frames abut at the 5760
  pitch; they do **not** overlap. A detail tile "in a neighbour" is therefore
  in that neighbour's own recipe/BSP and is seen from the entrance cell only
  through the skyline/skybox models, unless it sits in the entrance cell's own
  outer ring.
- Safe zones are one den per district plus the fixed origin Storm Drain
  (`generate_world_cells.ps1`; logical 0,0 on the west skybox ocean). Den cell
  templates exist for hospital, army base, bunker and default. Laboratory and
  The Epicenter are landmarks, not dens; the Epicenter is a centred exclusive
  3x3 footprint and currently blocks entrance slots.
- `tiletemplates/safezone_detail/` now contains two untagged test blockouts:
  `tile_safezone_detail_default_test.vmf` and
  `tile_safezone_detail_hospital_test.vmf`. They are not mapped in
  `generator-settings.json` and cannot be selected by normal planning. The
  existing `tiletemplates/coast/` directory remains empty. Coast piers already
  exist only as border water pieces
  (`border/tile_border_water_pier_*.vmf`). The client skybox ocean/shoreline is
  drawn by `cl_skybox.lua` (`Skybox.ClassifyEdge`: everything west of the grid
  is ocean). `bin/build_skybox_models.ps1` already converts tile VMFs to
  skyline models.

Stop and ask when: a required detail family has no authored asset; a claim
would cover a gate, motorway, water band or another identity's footprint; the
orientation of a detail piece relative to its entrance is ambiguous; or recipe
growth exceeds the reviewed budget below.

- **M0 - Superseded design contract and authoring brief.**
      Express everything in logical tile coordinates and cardinal directions.
  - **User decision, 2026-10-14:** entrance-detail claims are one tile deep.
    Neighboring claims use the neighboring cell's outer ring only; exact
    NW corner mapping is approved using each recipe's local coordinates:
    entrance-cell outer tiles `(-2,-1..1)` and `(-1..1,-2)`; W-neighbor
    east-outer column `(6,-1..1)`; N-neighbor south-outer row `(-1..1,6)`; NW
    diagonal neighbor SE outer tile `(6,6)`. The user approved the mirrored
    rotations for all other corners and edges:
    - `NE`: own `x=6,y=-1..1` and `y=-2,x=3..5`; E-neighbor
      `x=-2,y=-1..1`; N-neighbor `y=6,x=3..5`; NE-diagonal SW outer tile
      `(-2,6)`.
    - `SW`: own `x=-2,y=3..5` and `y=6,x=-1..1`; W-neighbor
      `x=6,y=3..5`; S-neighbor `y=-2,x=-1..1`; SW-diagonal NE outer tile
      `(6,-2)`.
    - `SE`: own `x=6,y=3..5` and `y=6,x=3..5`; E-neighbor
      `x=-2,y=3..5`; S-neighbor `y=-2,x=3..5`; SE-diagonal NW outer tile
      `(-2,-2)`.
    - Edge slots claim only their facing neighbor, never diagonals: N own row
      `y=-2,x=1..3` and N-neighbor row `y=6,x=1..3`; E own column
      `x=6,y=1..3` and E-neighbor column `x=-2,y=1..3`; S own row
      `y=6,x=1..3` and S-neighbor row `y=-2,x=1..3`; W own column
      `x=-2,y=1..3` and W-neighbor column `x=6,y=1..3`.
    Every neighboring claim is in its recipient recipe's outer ring, one tile
    deep. Corner diagonal claims are one tile. Claims remain subject to the
    approved priority/drop policy below.
  - **User decision, 2026-10-14:** Laboratory and The Epicenter detail is
    landmark-driven, independent of whether the cell has an active safe-zone
    entrance. Their claims follow the landmark identity/footprint.
  - **User decision, 2026-10-14:** The Epicenter's centered 3x3 landmark gets
    its detail ring plus claims in the outer-ring corners of the eight
    surrounding cells. Approved mapping: own-cell halo around (1..3,1..3) at
    x=0/4,y=1..3 and y=0/4,x=1..3; neighbor bands N(y=6,x=1..3),
    E(x=-2,y=1..3), S(y=-2,x=1..3), W(x=6,y=1..3); diagonal outer corners
    NW(6,6), NE(-2,6), SW(6,-2), SE(-2,-2).
  - **User decision, 2026-10-14:** active dens use the associated Hospital,
    Army Base or Bunker detail family; dens without one of those identities use
    the default-den family.
  - **User decision, 2026-10-14:** new detail assets are untagged and
    density-neutral; no tier-specific detail variants are required.
  - **User decision, 2026-10-14:** Storm Drain receives north/south flank
    detail and pipes west into the existing coast only. New piers/harbors and
    distant naval silhouettes are out of scope for this phase. Pipes terminate
    flush at the existing beach/shell boundary and do not extend into the
    3D-skybox sea.
  - **User decision, 2026-10-14:** all future detail VMFs use the entrance
    tile's W/E-facing canonical orientation; the builder rotates instances for
    their target sides.
  - **User decision, 2026-10-14:** claims lose to gates/transport, water/coast,
    safe-zone entrances, landmarks and other higher-priority identities. Record
    the conflict and drop the detail claim; never relocate it to another slot.
  - **User decision, 2026-10-14:** detail assets are visual-only and add no
    player-accessible routes, gates or road connections. Preserve existing
    traversal behavior.
  - **User decision, 2026-10-14:** rotate each detail asset so its authored
    front faces its source entrance/landmark. For diagonal claims, use the
    nearest cardinal facing and resolve equal-distance ties horizontally.
  - [x] Define all slot claim coordinates and rings. The user approved the
    NW and N-edge examples, their E/S/W and NE/SW/SE rotations, and the
    separate centered Epicenter mapping listed above.
  - [x] Agree family ownership: active Hospital/Army Base/Bunker dens use
    their landmark family; other dens use default. Laboratory and Epicenter
    details follow landmark identity even without a safe-zone entrance.
    Laboratory claims anchor to the actual 2x2 footprint; neighboring claims
    are allowed only when that footprint touches the cell edge.
    Storm Drain gets north/south flank details and westward pipes flush with
    the existing shore; no new coast structures or distant ships.
    Laboratory detail claims anchor to its actual 2x2 landmark footprint;
    neighbor claims extend only when that footprint touches a cell edge.
  - [x] Confirm common asset contract: 1x1 tiles; W/E canonical orientation;
    untagged/density-neutral; continuous perimeter walls without openings;
    visual-only with no new travel/gates/road markers. Higher-priority claims
    win; record and drop conflicts, never relocate them.
  - [x] User visual review of the exact Hammer++ test fixture before wiring
    claims.
    User-authorized Default-den and Hospital test blockouts now exist at
    `tiletemplates/safezone_detail/tile_safezone_detail_default_test.vmf` and
    `tiletemplates/safezone_detail/tile_safezone_detail_hospital_test.vmf`.
    They have no route markers or density suffix and normal planner settings do
    not select them. The user later revised the Default-den source for a more
    generic environmental fit and approved removing exact duplicate brush 18;
    that brush was removed from both the VMF and its byte-identical VMX companion.
    Current sources pass balanced-brace, globally unique-ID, six-sided-solid,
    unique-bounds, CRLF and route-marker checks; their material resolves from
    the mounted `garrysmod_dir.vpk`. `test_tile_ground_grid.ps1` passes56.
    A refreshed isolated developer zoo at
    `generated/phase_m_safezone_detail_followup_20261014/dev/zoo_safezone_detail.vmf`
    instances Default-den (`zm_dev_zoo_0`) and Hospital (`zm_dev_zoo_1`) and is
    open responsively in Hammer++. The original blockouts were visually
    accepted; the revised Default-den appearance has not received a new human
    acceptance. No VBSP/VVIS/VRAD compile or staging was run. Remaining family
    art is user-authored.
- **M1 - Removed generator claims (historical source/fixtures).**
  - Compute claims once in world generation/planning after safe-zone and
    entrance selection, before ordinary scenery, as deterministic data keyed by
    logical cell and tile. Priority: gates/transport assemblies > water/coast
    bands > safe-zone entrance > landmark footprints > entrance detail >
    ordinary scenery. A losing claim is recorded in diagnostics and dropped,
    never silently moved into a gate or onto another identity.
  - Reject claims into motorway cells and into Phase E ring leases; keep the
    claim table available to Phase E so its leases can assert no overlap.
  - Neighbours outside the grid get no claim; the own outer ring still can.
  - **User decision, 2026-10-14:** if the requested family lacks an authored
    asset, record a `missing_asset` diagnostic and skip only that claim; do not
    fail planning or substitute another family's asset.
  - Serialize claims on both the source and receiving recipes (identity,
    source cell/slot, tiles, yaw). Include them in recipe identity so a
    neighbour with detail never shares a filename with one without.
  - Fixtures: every corner and edge slot, all four neighbours plus diagonal,
    grid boundary, ocean side, motorway neighbour, gate conflict, two
    entrances claiming the same tile, deterministic repeat, legacy plan with no
    claims unchanged.
  - **Implementation progress, 2026-10-14:** when detail claims are enabled,
    the planner first assembles transport, entrance, landmark and other
    higher-priority placements without ordinary scenery, resolves claims, then
    replans ordinary scenery with accepted incoming tiles reserved. Single-tile
    buildings/decorations and open-terrain fill avoid reserved core tiles;
    ordinary multi-tile building candidates whose footprint intersects a
    reservation are excluded. Recipe filenames and variant layouts use the
    reserved result. The test-only Laboratory alias to the Default-den blockout
    exercises core reservations without adding a production family asset.
    The now-retired dedicated claim suite passed43 assertions;
    `test_safezone_entrances.ps1` passes with claim-aware variation at963
    assertions (16 cells,11 recipes,22 adjacent pairs),32 claims and two
    ordinary-scenery slots reserved. The updated test tiles pass structural
    checks and `test_tile_ground_grid.ps1`56. An isolated tile zoo was opened
    responsively in Hammer++; the revised Default-den appearance remains
    unaccepted by a fresh human review. No preview-wide VMF refresh, compile or
    staging occurred at this source-check boundary. Subsequently the user
    confirmed that building1b was renamed; the fixture now uses existing
    `buildings/tile_building_2aa_2x.vmf`. Its isolated multi-tile run completion
    remains unverified. The later approved preview batch and its two VBSP
    failures are recorded above; no staging or M1 acceptance is implied.
- **M2 - Removed builder emission.** The former plan was to emit claimed tiles through the existing
      `func_instance` path with the canonical yaw table; suppress the border/
      outer pieces they replace exactly as entrances already do. Validate all
      four rotations in a developer zoo (`build_tile_zoos.ps1`) before any
      preview-wide refresh.
  - **Source slice implemented, 2026-10-14:** the builder now applies accepted
    incoming claims to core terrain and border/outer scenery through its
    existing instance writer. Layout placements retain claim provenance, yaw
    and identity. Unclaimed neighboring pieces remain unchanged. Duplicate,
    stale/missing slot, protected core/road/coast/lease and invalid-facing
    claims fail explicitly. Outer claims require matching expanded settings.
    Approved entrance halos fill only projected outer omissions; suppressed
    entrance border/core geometry remains owned by the entrance.
  - Fresh focused emission fixtures pass698 assertions: E0/N90/W180/S270,
    core/border/outer origins, exact instance counts, neighbor preservation,
    conflicts, input-plan isolation and byte-identical repeated builds.
    Pure claim checks pass45 assertions, including absent/null optional
    collections. Five synthetic VMFs (control plus four facings) are retained under
    `generated/phase_m_detail_emission_20261014/src`. The planner-to-builder
    The now-removed detail-only entrance fixture passed963 variant
    assertions and emits all32 planned claim records, reserving two scenery
    slots. It skips the full-world entrance/orientation/rejection checks.
    No compiler, staging, full world regeneration or in-game check ran.
    M1 and M2 are not user-accepted; revised Default-den and four-facing Hammer
    review remain open. The old multi-tile run remains unverified.
- **M3 - Cancelled Storm Drain and centred landmarks.** Former proposal: Storm Drain detail on its
      north/south flanks only, preserving the approved west beach/ocean join
      and the physical shell. Epicenter: speculative centred ring around its
      exclusive 3x3 and the matching corners of neighbouring cells; no
      safe-zone behaviour is implied.
- **M4 - Cancelled skybox coast detail.** Former proposal: add piers/harbours to the skybox
      shoreline. Prefer authored `tiletemplates/coast` VMFs converted by
      `build_skybox_models.ps1` into models placed deterministically along the
      west ocean edge by `cl_skybox.lua`, using one shared placement owner.
      Keep to existing render phases and the shared frame budget. Bridge the
      authored beach and skybox shoreline without changing their accepted
      continuity.
- **M5 - Cancelled distant naval presence.** Former proposal: destroyers/other vessels as distant
      skybox models offshore (west ocean), static or slow drift, never
      reachable or interactive. Settle asset source and licence first (authored
      coast VMF->model, or mounted Valve models referenced in place; no copied
      Valve content). Bound model count and draw cost; measure with a matched
      sample before claiming performance.
- **M6 - Cancelled budgets and gates.** Former proposal: report recipe growth caused by claims
      against the reviewed preview baseline (311 recipes) before any build.
      Bundle compiles, skyline model builds and staging into Phase G/J's
      approved expensive batch; do not start them here. Visual acceptance is
      human review in Hammer++ and in game.

Former exit (cancelled): user-approved claim contract and authored families; fixtures prove
deterministic claims, conflict resolution and identity; Hammer zoo review of
all rotations. Compiled/in-game review is carried into G/J.

</details>

### Phase E - Rectangular VMFs, ring leases and actual travel

**Immediate focus clarified, 2026-10-14:** continue the motorway-specific
origin, ring and travel path. Retain the completed ordinary rectangle helper
work below, but do not expand building content or general-building features
as the next slice. CSM remains deferred and Phase M remains cancelled.

- [ ] Generalize square-only planner/builder helpers together, while preserving
      existing 1x1/2x2/3x3 building frontage and emitting-instance semantics.
  - **First source slice, 2026-10-14:** the builder accepts explicit rectangular
    occupancy dimensions from1 through3 per axis, matching the existing planner
    reservation helper instead of rejecting non-square placements. Each
    footprint still has one emitting anchor. Planner reservations reject an
    empty/reused placement ID before mutation; the builder rejects duplicate
    emitting IDs and stale template/yaw/explicit dimensions on occupied records.
    Legacy occupied records without repeated dimensions retain owner-derived
    geometry, including the accepted isolated straight motorway fixtures.
    `test_rectangular_footprints.ps1` passes342 assertions across1x1/2x2/3x3
    controls and1x2/2x1/2x3/3x2 rectangles at all four supplied yaws, with
    exact coverage/counts, corruption and atomic-rejection cases. Current
    density/frontage/recipe fixtures2528 and ordinary entrance12+2 pass.
    The current builder validator also passes all576 retained ordinary cells
    and two retained straight motorway inspection cells; these are retained
    plan compatibility checks, not fresh VMF/compiled/live acceptance.
    This does not enable rectangular filename selection or author new assets:
    rotation-aware frontage/marker candidates, ordinary template naming/limits,
    independent authored origins and ring/travel integration remain unfinished.
    The normal square1x1/2x2/3x3 selection and specialized motorway opt-in remain
    unchanged. No world regeneration, compiler, staging or live reload ran.
  - **Rotation/frontage source slice, 2026-10-14:** marked road candidates now
    test the actual rotated rectangle before accepting an anchor, while mapping
    authored edge markers using the unrotated dimensions. Generic road-facing
    candidates also use the template's authored direction to choose the correct
    orientation. Selected building, forced-fixture and landmark reservations
    use rotated dimensions; landmark road caps and commercial access checks use
    the same dimensions. Commercial access cache keys separate differing
    rectangles at one anchor. Existing square candidate order/targets match
    the committed helper in24 paired marked/generic scenarios; an initial
    unmarked-square tie-order discrepancy was corrected before completion.
    Fresh rectangle/ownership/frontage fixtures475, density/recipe2529 and
    ordinary entrance12+2 pass. Rectangle frontage cases cover all four yaws,
    two off-centre markers with distinct types/targets, unmarked frontage,
    protected-slot rejection, input isolation and builder-valid reservations.
    Square1x1/2x2/3x3 marked controls and malformed-marker rejection pass.
    Filename selection and authored direction-marker inventory validation remain
    square-only; no new rectangular authored asset is selectable yet. The first
    checkbox stays open pending that integration and its matching small-output
    fixtures. Full building-frontage/multi-tile generation tests are not run
    in this source-only pass; expensive generation/compile/live gates remain.
  - **Filename/inventory source slice, 2026-10-14:** shared footprint parsing
    recognizes explicit `_WxH` and legacy square `_Wx`. Ordinary selection
    still enforces the existing maximum3; forced oversized rectangles fail
    explicitly. Direction-marker inventory validation uses authored height for
    N/S and width for E/W. Height-tier selection and compact macro naming
    understand rectangular suffixes. Zoo/test helpers reuse the parser, zoo
    spacing accounts for both axes, and multi-tile physical assertions use
    authored dimensions for markers but rotated dimensions for occupancy/origin.
    No new rectangle building source exists in the inspected inventory and no
    authored asset, source mapping or settings were changed. Fresh filename/
    marker/frontage/ownership fixtures555 and density2529/entrance12+2 pass;
    marker fixtures cover seven square/rectangle shapes and all four authored
    directions with invalid-midpoint rejection. Named-landmark density variants
    cannot substitute a transposed authored shape. Temporary marker fixtures
    are cleaned. Full frontage/multi-tile output generation and compiled/live
    checks still await the approved batch; the first checkbox remains open for
    end-to-end output verification, not further speculative geometry authoring.
- [ ] Carry authored origin offsets explicitly; calculate physical instance
      position independently from a rectangle's integer reservation anchor.
      Validate footprint coverage, duplicate owners and every suppressed slot.
  - **Motorway origin emission source slice, 2026-10-14:** the straight
    inspection plan already carried `originCellLocal`, but core/ring VMF
    emission recalculated its origin from the rectangle centre. Both emission
    paths now use one production instance writer that consumes the recorded
    finite XYZ directly for measured motorway owners. Explicit origins retain
    fractional coordinates independent of integer reservation anchors, with
    invariant-culture output; they are not rotated again or shifted by a
    separate tile Z offset. Unsupported cell frame/pitch/Z offset, missing/
    non-finite origins and attempted occupied-slot emission fail explicitly.
    The existing isolated-mode guard remains; ordinary tiles retain their
    centred formula, legacy interior integer rounding and metadata.
    Focused motorway1074 assertions and rectangle555 pass. Motorway output
    fixtures exercise all18 straight core/border/outer owners plus independent
    fractional XYZ, rejection and224 exact ordinary entity controls. All18
    retained straight VMF transforms match the new writer; ordinary entrances
    12+2 pass. No full map generation, compiler, staging or live reload ran.
    This closes the recorded-origin-to-instance gap in the isolated path only;
    normal planner enablement, complex assembly origin/lease integration and
    fresh physical/live verification remain open. The checkbox is not complete
    or accepted.
- [ ] Reserve the full 3-wide road continuation through both rings. Replace
      covered walls/corners only through an explicit boundary lease; preserve
      shoulder closures and no-gap connections to adjoining pieces.
  - **Straight motorway ownership source slice, 2026-10-14:** extracted the
    builder's straight inspection lease checks into a shared motorway contract
    and strengthened it before any ring replacement. Both orientations require
    nine distinct emitting owners,27 exact core/border/outer leases and25 unique
    core records. Each owner must match its anchor, authored3x1/rotated footprint,
    yaw, ring and finite approved physical origin; every suppressed core slot
    must retain its owner/template/yaw and remain non-emitting. Corrupt origin,
    owner, lease, ring, dimension, yaw or suppressed-slot records fail without
    mutating the input. Ocean/water/den cells remain explicitly unsupported by
    this inland-straight contract, not silently opted in.
    Focused motorway geometry710 assertions, rectangle555 and ordinary entrance
    12+2 pass. Both retained straight inspection plans pass27 leases each;
    retained-plan compatibility is not fresh output or physical acceptance.
    This consolidates the approved isolated corridor contract; it does not yet
    enable wide motorways in normal planning, solve complex joins or accept
    Phase E. No authored assets, maps, compiler, staging or live state changed.
- [ ] Protect ocean omission, retained authored coast/entrance/beach and the
      physical shell. Check the floor/walls as well as skybox coordinates.
      Do not reintroduce the exposed-west-floor defect.
- [ ] Preserve skybox/ceiling clearance for elevated bridge/ramp/junction pieces
      and authored below-ground geometry. An AABB fit alone does not prove
      player clearance, closure or lack of z-fighting.
- [ ] Derive transition trigger opening, obstruction/blocker coverage, arrow
      lanes and safe arrivals from the measured route ports/surfaces. Keep
      ordinary-road behavior unchanged; eliminate dependency on legacy median/
      lane widths for the new motorway family.
- [ ] Publish validated layout/port metadata to the existing world owner where
      needed, registering client/shared includes and network strings correctly.
- [ ] Test all sides, both travel directions, elevated joins, blocked exits,
      hull-obstructed arrival fallback, same-BSP logical travel and den access.
      Verify persisted logical destination and map via `zombiesim_player_status`.

Exit: complete widened core/ring geometry and safe travel fixtures. Actual
travel and physical continuity remain live gates in Phase G.

### Phase F - Derivatives, revisions and persistence compatibility

- [ ] Extend emitted layout metadata/validation for rectangular assemblies,
      occupied slots, ring replacements, port heights and scenery density.
- [ ] Make illustrated cell/world artwork, wireframes and dynamic gate/loot/
      player marker projection consume the authoritative unchanged cell bounds.
      Draw actual widened occupancy, retaining den-specific projection.
- [ ] Ensure skyline extraction includes the real motorway/border/edge sources,
      their rotation/elevation and approved current-cell roof-fire provenance.
      No phantom motorway buildings or stale narrow shoulder scenery.
- [ ] Version affected generator/cache contracts and source hashes. Runtime
      exports, skyline, illustrated materials and compiled maps must match.
      Old Satellite is compatibility-gated until a complete matching recapture.
- [ ] Reuse profile/logical-cell loot revision backup/reset behavior; verify
      changed geometry resets only the affected cell once and fault paths remain
      atomic. Do not mass-wipe survivor inventory/characters.
- [ ] Plan migrated den access/restoration for saved survivors if safe-zone
      coordinates move. Stable den IDs are essential; do not reinterpret an old
      saved city coordinate or move a deployed survivor during a source check.
CSM-specific lighting provenance (map/build key, direction and effective
LDR/HDR direct/ambient metadata) is deferred to the
[CSM metadata contract](docs/csm-implementation.md#53-lighting-metadata).
It does not block generator derivatives or require relighting maps.

Exit: small derivative/compatibility fixtures pass; full skyline/material/
Satellite generation remains deferred to the approved batch.

### Phase G - Isolated compiled geometry and live travel prototypes

- [ ] Request approval for a bounded compile/staging pass. Name affected fixture
      maps first; resolve source dependencies and use incremental builds.
- [ ] Compile straight, corner, T, cross, terminal, single/dual onramp and bridge
      cases plus ordinary-road, coast, safe-zone and legacy square-building
      controls. Cover all cardinals in structural fixtures, not one screenshot.
- [ ] Run VBSP/portal budgets first and correct leaks/failed topology before
      VVIS/VRAD. Record complete compiler stages; no success-shaped timeout.
- [ ] Open exact generated VMFs in Hammer++ and obtain human arrangement review.
      Compare surveyed ports with emitted instances and compiled collision.
- [ ] Stage only the approved matching preview artifacts with verified backups.
      Reload through an approved `changelevel`, not Lua autorefresh.
- [ ] Exercise actual on-foot ramps/bridges and motorway gate arrivals in a
      deployed city cell. Review paired arrows, blockers, shoulders, seams,
      decoration placement, coast continuity and all relocated access points.
- [ ] Restore/verify original profile, logical cell, preferences and player data.

Exit: accepted small physical/travel prototypes. No full world rollout yet.

### Phase H - Experimental CSM service and Options (accepted limited scope)

The user accepts the current client-local prototype and Options controls as an
experiment. They remain off by default. This acceptance retains the lack of
runtime/Options live review and does not assert seamless cascade coverage,
complete lifecycle isolation or performance acceptance. Remaining work is
owned only by [CSM tracker Phases 1-5](docs/csm-implementation.md#6-implementation-phases-and-acceptance-checklist).

- [x] Implement the user-approved F-toggle chest lamp replacing the native
      flashlight bind in gameplay cells. It is a networked, light-only
      `ValveBiped.Bip01_Spine2` cone with no battery or model, visible to all
      clients and reset on death. After performance testing, every permanent
      chest cone is unshadowed; each client renders at most the nearest four
      active lamps within2048 units. Static GLua syntax passes274/274. A live
      preview test confirmed F turns the cone on and off and the user confirmed
      its chest placement/aim-follow behavior in the companion feasibility test.
      State sync with a second client, transition/death cleanup and four-player
      culling remain unverified.
- [x] Add `zombiesim_csm_enabled` (default off) and the client-local
      Low/Medium/High selector to Options. The selected tiers are Low =
      1 cascade / 15 Hz, Medium = 2 / 30 Hz, High = 3 / every rendered frame.
      Existing graphics presets do not enable or alter CSM.
- [x] Add one `ZM_CSM` client owner, sent and included before Options. It
      supports generated preview/city cells, owns up to three
      `ProjectedTexture`s, uses `render.GetViewSetup(true)` for the current
      view, and removes its projectors when disabled or outside supported
      contexts. The `effects/flashlight001` texture and template-derived
      sunlight direction reuse the reviewed probe path.
- [x] Implement off/waiting/unsupported/ready/suspended/failed status,
      finite-vector/angle guards, idempotent teardown and rollback on partial
      projector allocation/update errors. Options displays the current state and
      an explicit unsupported reason.
- [x] Preserve an exact source-level native-off path: CSM off removes every
      owned projector and changes no map light, lightstyle or shared setting.
      The on path is client-local and additive.
- [x] Add the requested initial three-tier projected-light prototype. Each
      tier uses nested extents and normalized brightness weights. These layers
      currently overlap without seam-blending masks; they are an experimental
      first implementation, not accepted contiguous cascade coverage.
- [x] Suspend the prototype during launcher, sky-inspection and world-capture
      contexts; the hook also skips depth and skybox callbacks. Actual secondary
      view restoration and native skybox behavior remain deferred live checks.
- [x] User accepts this experimental implementation and moves remaining
      cascade correctness, view/lifecycle/isolation fixtures and resource/cost
      work to the dedicated CSM tracker. No further probe/reload is required.

Disposition: accepted experimental slice with the limits above; no CSM
hardening prerequisite for I/J/K/L. Retain default off, client-local additive
lighting and unchanged global flashlight/server lighting settings.

### Phase I - Generator quality, performance and failure acceptance

- [ ] Agree exact benchmark conditions and acceptance budget before sampling:
      map/logical cell, native lighting (CSM off), HDR, weather, camera/resolution,
      foreground focus, quality, crowd/props/foliage and warm/cold state.
- [ ] Compare generator baseline and changed geometry on matched workloads,
      including wide motorway junctions, tall buildings, dense borders and moving
      crowds. Record process frame-time median/p95/p99, resources/commit/heap and
      relevant generator/runtime CPU separately; hook timing is not full render cost.
- [ ] Repeat travel and secondary-view cycles; verify no orphan
      models/material queues, persistent player changes or preference
      leaks. Do not mistake cache high-water admission for proven leakage.
- [ ] Review density gradient and district identity, motorway visual connectivity,
      coast/den continuity and approved existing effects with CSM off.
- [ ] Record unsupported generator modes and actual failures; resolve budget,
      geometry/travel and native-presentation regressions before acceptance.

All CSM-specific mode comparisons, moving-caster correctness, shadow-update
optimization, projector-cycle isolation and resource budgets are deferred to
[CSM testing/performance](docs/csm-implementation.md#7-test-diagnostic-and-performance-specification).

Exit: accepted integrated prototypes with measurable budgets and retained limits.

### Phase J - Single separately approved full-preview closure

- [ ] Include carried Alpha 3.1.5 Phase D generated artwork, stitched previews,
      wireframes, navmesh refresh and complete clear/atmospheric Satellite in
      this one final-revision batch. Do not first rebuild/capture an obsolete
      3.1.5 world and repeat it after the generator changes.
- [ ] Present a batch proposal: matching input hashes/settings, predicted recipe
      count, affected map list, compiler/model/material/nav/capture work, runtime/
      package byte budgets, estimated cost and verified restoration closure.
- [ ] Ask before full preview regeneration, compiler runs, full skyline/materials,
      navmesh refresh or complete Satellite capture. Bundle dependent work once.
- [ ] Resolve settings through the profile resolver; use isolated preview output
      roots and stable seed 1337. Do not reuse stale 3.1.5 plans with new sources.
- [ ] Generate map/plan -> VMFs/layouts -> VBSP/portal checks -> accepted lighting
      compile variants/full VVIS/VRAD -> skyline/runtime/materials -> navmesh ->
      revision-matching complete capture/import, respecting actual dependencies.
      Skip VBSP only with unchanged source/instances and `-SkipRecipeRefresh`.
- [ ] Validate every required map and all perimeter/corner/port cases, full recipe
      variation policy, relocated features/reachability, closure and source hashes.
- [ ] Stage matching artifacts together with GMod safely unloaded; verify content
      and engine hashes, backup ledger, destination loading and persistence.
- [ ] Preserve stale imagery as incompatible, never relabel it or enable partial
      Satellite as complete. Verify fresh nav/capture and restored survivor state.
- [ ] Obtain final full-preview human review. Production city remains untouched.

Exit: complete accepted preview integration, not authorization for publication.

**Phase J progress, 2026-10-15:** the isolated batch
`generated/phase_j_preview_20261015` (seed 1337, outerEdges via an isolated
settings copy and measured assembly report) planned 336 recipes plus 3 dens.
VBSP passed for 339/339 maps, visibility budgets passed, and the fast-preset
VVIS/VRAD compile completed 339/339 with 0 failed and 0 incomplete. Skyline,
runtime export, cell artwork and stitched illustrated `satellite.png` were
built. Generator fixes made during the batch:
- infill templates now accept non-motorway layouts (3 new patch templates);
- the cubemap anchor is clamped below VBSP's 126-character patch-name limit
  for 3x epicenter blends;
- `build_city.ps1` no longer cleans or stages the live engine maps folder for
  an isolated `-ContentMapDirectory` build.

That last leak deleted or overwrote 190 ledger-staged engine BSPs and copied
in 339 untracked copies. All of them were restored from hash-verified ledger
sources before proper staging. Staging went through the Phase B ledger:
9667 entries and 339 content/engine maps hash-verify. GMod was relaunched with
`-disableluarefresh` for human review.

Cleanup (user directive): 1153 stale preview maps/navs, 6660 stale skybox
model files, 490 stale artwork files and all superseded `generated/` batches,
including `workshop`, were deleted (33 GB). The old staging ledger and its
backups are retired, so the Phase J world is the installed baseline.

Still open:
- full-preview human review;
- navmesh refresh (per-cell wireframes depend on it) and the complete
  Satellite capture, both still require approval;
- the perimeter/variation validation listed above.

Crossroads load fix: the four motorway crossroads cells (6,4), (17,-5), (6,-5)
and (15,6) failed in game with "Map coordinate extents are too large". A
0.39-unit sloped sliver brush in the crossroads tile made VBSP report
"bounds out of range" (only a warning), which stretched the map's world bounds
to -65536. The user's Hammer save had already removed that brush from the
source. Replanning changed only those four cells' source hashes; all recipes
were unchanged. The four maps were recompiled (fast VBSP/VVIS/VRAD,
extents +/-10240) and staged into both map folders, with hashes verified.
`compile_cell_vmfs.ps1` now fails a map (`failed-bounds-out-of-range`) and
deletes its BSP when VBSP logs that warning. The T-junction tile still has a
similar sliver (id 41926); it is unused in the world and left for the user to
fix in Hammer.

In-game review fixes (2026-10-15, source only; full recompile and visual
re-check pending). The user reviewed the motorways in game and reported:
- **Misaligned motorways.** Complex pieces were centred, so even-span pieces
  sat half a slot off and their straights left cells 304/320/640 off centre.
  The whole assembly now moves in 320 steps until its arms leave on the centre
  line, and continuation straights snap to whole 640 slots (`gridSnap` in each
  contract). (13,6) moves 640 north. Small authored mouth jogs (14-48 units)
  remain for Hammer.
- **Black strip past the outer ring.** On land sides, the sky seal and black
  floor now end at 2880/2944 instead of 3072/3136. Ocean sides are unchanged.
- **Missing gates.** Recipes shared by cells with different road blockades
  only had the first cell's gates (49 recipes / 98 cells affected). Maps now
  get a gate on every road connection (`gateDirections`), and runtime blocks
  them per cell.
- **Trees on roads and motorways.** Trees now need natural, level ground
  across a 192-unit canopy ring; otherwise they become shrubs.

Focused checks pass: motorway geometry 1529, outer edges 1602, skybox edges
529, complex cells 2919, gates 232 (south mixed gate now at the standard
-2208), GLua 275/0. The user rule is to verify by sight in game, not with
geometry proofs.

### Phase K - Carried Alpha 3.1.5 closure (deferred after 2026-10-17)

**Deferred by the user on 2026-10-17; not part of the immediate active sequence.**
The user's sequence is Cell Health Manager, then all-map navmeshes and
screenshots. The detailed carried-closure checklist has been removed from this
active plan; its evidence remains in the archived Alpha 3.1.5 tracker.
Historical cross-reference:
[Alpha 3.1.5 Phase D](docs/todo-alpha.3.1.5.md#phase-d---full-footprint-minimap-world-artwork-and-satellite-capture)
and [Phase I](docs/todo-alpha.3.1.5.md#phase-i---integrated-acceptance-and-separately-approved-city-rollout).
Use the final matching 3.2 geometry and artifacts, not stale 3.1.5 outputs.

This deferral does not accept or discard the carried Phase D/I closure. Reopen it
only if the user restores that scope. Production/city rebuild and Workshop
publication remain separately gated.

### Phase L - Final acceptance and documentation (after all-map outputs)

After the Cell Health Manager and the user-requested full-map navmesh/screenshot
batch, reconcile the docs, package checks, evidence boundaries and final
milestone decision against the outputs actually produced. Keep production
rebuild, Workshop publication, and release status separately gated; Alpha 3.2
remains `in development` until the user accepts the milestone.

## 4. Validation for the revised focus

The broad generator validation matrix is not active while the user has paused
world-generator work. Do not rerun historical density, layout, frontage,
motorway-geometry, or full-preview suites merely because their entries remain
in older dated notes.

- **Cell Health Manager:** implemented as a read-only preview admin grid;
  offline contract tests4/4 and GLua syntax281/0 pass. Live panel review is
  still required. Keep the basic file/photo checks, no revision hashes, and
  cubemaps explicitly unverified/incomplete; do not add build or repair work.
- **Final map outputs:** after the Cell Health Manager, produce the matching
  full-map runtime export, navmeshes, and all-map screenshots the user requested.
  Verify the revision hashes and actual coverage before staging or visual review.
- Use the README and existing build/stage scripts for exact commands. Ask again
  before any substantially broader job than that final approved output batch.

## 5. Handoff and stop conditions

The user has explicitly paused world-generator work after accepting the live
motorway checks. The two corrected BSPs are staged, and the targeted runtime
map-name overlay routes IDs113/454 to them. Do not resume broad Phase E/J
planning or regenerate the full preview now. Preserve the temporary revision
hashes; refresh the matching full plan/runtime/skybox hashes only during the
final all-map output phase.

The Cell Health Manager contract and preview developer panel are implemented.
Use `zombiesim_dev_cell_health` and `zombiesim_dev_test_cell_health_client` in
a running preview admin client to inspect the UI and actual mounted files.
Record human UI review separately from the passing offline fixtures and syntax
check. Only after that review proceed to the full-map navmesh and screenshot
batch; no broader generator work is authorized.

The lengthy Phase K/L closure lists are deferred until after the selected
sequence; their historical requirements remain in the archived tracker.
The user has not accepted the Alpha 3.2 milestone or release. CSM's current
checks are accepted for now; unverified performance/lifecycle/multiplayer
limits remain deferred, not new work.

Preserve source assets, user data, and restoration requirements. Production
rebuild and publication remain separately gated. Dated history below is
reference, not the active sequence.

Keep checkpoints after future subsystem boundaries or failed validation loops.
Record the exact source/artifact, hypothesis, result, and next discriminating
check. Distinguish user acceptance from automated evidence and unrun tests.
