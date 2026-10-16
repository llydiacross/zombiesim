# ZombieSim Generator Guide

This guide explains the city generator in normal game-making language. You do not need to be a programmer to adjust the safe settings. The main file is [generator-settings.json](generator-settings.json).

## Launcher maps and survivor slots

The `zn_preview_start` and `zn_city_start` launcher VMFs in [celltemplates/launchers](celltemplates/launchers) are hand-authored, not generated city recipes. Build them independently with `.\bin\test_launcher_parity.ps1` and `.\bin\build_launchers.ps1 -WorldProfile preview` (then `city`). This compiles and stages only the selected launcher into both `content/maps` and the engine's `garrysmod/maps`; do not run a world build for launcher-only edits. Both maps provide a `menu_camera`, a `menu_globe` position, a `credits_camera`, and four named dancer ragdolls.

The launcher holds players until a profile-scoped survivor slot is selected. The server keeps three slots per profile and migrates existing per-profile progress to slot 1 on first startup, after taking a database backup. Slot 1 needs an appearance choice before first deployment. [launcher_scene.json](content/data_static/launcher_scene.json) contains fictional geographic anchors and credits crawl text; editing it does not require recompiling maps. Read [readme.md](readme.md) for menu controls, test commands, and the current live-verification warning.

The generator creates a city plan, turns that plan into reusable 5-by-5 cell recipes, then creates VMF files for Hammer. It does not change the hand-authored tile templates in `tiletemplates`.

## Start Here

1. Make a copy of [generator-settings.json](generator-settings.json) before experimenting.
2. Change one group of settings at a time.
3. Make a preview first. The `preview` profile writes VMFs to `generated/src_preview`, separate from the `city` profile's `generated/src` folder.
4. Open the preview image or preview VMFs in Hammer and decide whether the change is worth keeping.

Settings use JSON. Text must be inside double quotes, items in a list need commas, and there must not be a comma after the final item in a list. Do not rename setting names unless this guide calls them advanced.


## Alpha 3.2 safe-zone detail outcome

The user rejected the automatic safe-zone detail treatment on 2026-10-14.
Phase M is cancelled. Detail claims, scenery reservations, neighbor propagation,
recipe-signature contributions and builder emission have been removed.
Existing den entrance generation is unchanged; the user's authored VMF/VMX
assets are preserved. Old isolated detail fixtures are rejected history, not
current outputs to stage. Do not resume or redesign that system.

The user instead prefers larger, interesting authored tiles with varied
width/height placed through the normal generator. Continue the existing
rectangular footprint and instance integration in
[Phase E](todo-alpha.3.2.md#phase-e---rectangular-vmfs-ring-leases-and-actual-travel);
inspect each actual asset's footprint, orientation and frontage before wiring
it. This direction does not authorize arbitrary geometry edits or broad builds.

Existing entrance fixtures remain available without a full-world planning pass:

```powershell
.\bin\test_safezone_entrances.ps1 -FixturesOnly
```

This runs the ordinary 12 orientation/water and two rejection cases only.
Omit the switch to retain the original full-preview entrance baseline as well.
Neither mode compiles or stages maps.

## Alpha 3.2 explicit rectangular occupancy

The planner's `Set-FootprintPlacement` and the builder's occupancy validator
accept explicit rectangles from1 through3 tiles per axis. Coordinates describe
the already-rotated reservation rectangle; its top-left logical tile is the
sole emitting owner. Other covered records retain that owner's ID, anchor,
template and yaw. Reused IDs fail before planner mutation; inconsistent
explicit dimensions/template/yaw or duplicate emitting IDs fail in the builder.
Older occupied records may omit repeated dimensions and use owner geometry.
The specialized wide motorway inspection path and its measured origins remain
separate and opt-in.

Frontage helpers consume authored dimensions and calculate rotated reservation
dimensions separately. At90/270 degrees the axes swap; authored road marker
coordinates still use the original width/height before rotating to a logical
tile. Both marked and generic candidates test the rotated rectangle for
availability. Building/landmark reservations, road caps and commercial access
use that same rectangle; commercial access cache keys distinguish dimensions
at a shared anchor. Existing square candidate ordering/targets are preserved.

```powershell
.\bin\test_rectangular_footprints.ps1
```

This fast test invokes the production planner/builder helpers with explicit
fixtures; it does not write maps or select new assets. A shared filename parser
recognizes `_WxH` authored dimensions and legacy square `_Wx` shorthand.
Width is authored local X and height is authored local Y, in640-unit tiles.
Ordinary multi-tile selection remains limited to three tiles per axis;
recognizing larger filenames does not authorize ordinary placement or replace
the specialized motorway path. Direction markers must be at the authored
edge midpoint: N/S use height, E/W use width. Zoo spacing uses both axes, and
multi-tile test expectations distinguish authored markers from rotated origins.
Density variants for named landmarks retain the same authored shape.

No new ordinary rectangular building asset exists in the inspected inventory,
so selection is fixture-verified, not a human-approved authored result.
Independent authored origins, matching small-output/physical validation and
ring/travel integration remain Phase E work. Do not infer arbitrary geometry
support or increase the existing limit from this filename contract.

## Alpha 3.2 straight motorway ownership contract

The immediate Phase E focus is motorway origin/ring/travel integration, not
additional ordinary building content. The retained rectangular helpers above
remain supporting source work.

`New-ZMStraightMotorwayStripe` now owns the shared approved3x1 stripe geometry.
The normal planner applies its five core stripes before density decorations:
15 occupied slots with five emitting owners, ten suppressed records and ten
free scenery slots. This is restricted to plain straight topology with wide
settings, the5x5 frame and the approved vertical0/horizontal90 mappings.
Legacy1x1 settings remain unchanged. The isolated inspector uses the same
constructor for core and rings, preserving its reviewed transforms.
Normal playable VMF output remains blocked until ring/gate/travel integration;
do not bypass the inspection guard to build a wide core with narrow boundaries.
Run `bin/test_scenery_density.ps1` for actual normal-planner reservation/density
interaction fixtures as well as `bin/test_motorway_geometry.ps1`.

Normal expanded straight plans carry a separate `motorwayAssembly` contract:
27 leases and four border/outer owners, source SHA256 and explicit
`normal_reservations_travel_pending` status. `Resolve-ZMNormalStraightMotorwayRings`
validates source/ownership before replacing only the leased boundary records.
Unleased corners/walls retain their authored records and yaws; route-adjacent
wall density consumes the same leases. Inland-straight limitations remain.
The normal builder still refuses emission until gates/runtime are implemented.

For a bounded normal-planner-only check, without VMFs/compile/staging:

```powershell
.\bin\build_motorway_cell_preview.ps1 -WorldProfile preview -NormalPlanOnly
```

This generates isolated expanded settings from the profile and retains wide
source mappings. It plans the existing vertical/horizontal two-cell fixture
without inspection metadata. Do not interpret its legacy manifest as new
density-zone output or enable the production outer-edge setting for this check.

Normal straight contracts also publish source-measured `gates`, not runtime
acceptance. `Get-ZMStraightMotorwayMouths` reads the canonical saved floor faces
through the existing mouth-registry validator. Current straight faces120/126
and342/384 form416-unit carriageways at Z68, centred-512/+528. Source hash
and border-stripe origin are checked before gate derivation. Both orientations
rotate these asymmetric centres into outward-right lane coordinates (N/W:
-512,+528; S/E:-528,+512). Gates remain at2208, measured mouths meet2240,
arrows are256 inward and arrivals384 inward. Metadata records lane extents
and the negative-right arrival lane. Brushes/props/runtime consumers remain
source-wired below; the normal-wide emission guard is unchanged.

The active Phase J refresh reuses the previously approved seed-1337 plan via
`bin/reuse_approved_preview_plan.ps1`. It verifies the matching seed/grid and
prior runtime gate records, removes only the retired `-edge2` recipe suffix,
and preserves each cell's tile placements, motorway origins/yaws, leases and
grid shifts. It removes stale source fingerprints and the old AABB-derived
inspection spawn candidate; no motorway source geometry, face ID or bounding
box is remeasured to plan or align these approved placements. The tool is for
this same approved plan, not for choosing a new world layout.

The VMF writer emits two separately named, lane-tagged `trigger_multiple`
entities per motorway-connected side, one trigger for each saved carriageway.
Each has its own carriageway-width bounds, arrow and barricades; the existing
256-unit arrow inset and 384-unit inward arrival remain unchanged. The arrival
landmark is written once per direction. Ordinary-road connections retain one
trigger and their existing bounds, arrows, barricades and arrival. A trusted
plan starts players on the nearest available terrain tile in the 640-unit grid;
the former measured insertion-seam spawn is not used.

Runtime export copies the trusted gate records from that same approved plan
instead of rederiving them from current tile sources. `ZM_Transitions` resolves
those records through `ZM_World:GetCellsForMap`; shared-map cells must agree.
At load time, a lane-tagged trigger is matched to its planned carriageway, then
arrows and arrivals use the saved lane coordinates and brush-only surface
traces. Arrival hull clearance and the client Global2 API are preserved.
Legacy maps without lane tags keep the existing combined-marker behavior.
Offline plan and gate fixtures do not establish compiled collision, live
traversal or visual alignment; the refreshed compiled maps and in-game sight
review remain separate checks.

`build_motorway_cell_preview.ps1 -Normal` and the source-survey helpers remain
diagnostic tools; they are not part of this trusted Phase J refresh and must not
be treated as mathematical proof of the user-approved motorway alignment.

`build_motorway_cell_preview.ps1 -Mixed` covers the four actual bend/deadend
plus bridge/on-ramp combinations. `Join-ZMMotorwayAssemblyCases` inserts the
transport piece into an unambiguous measured outgoing motorway mouth and
removes only internal continuations. Road headings select transport orientation;
the bridge's road axis is perpendicular to its motorway axis. Both authored
pieces and every logical route remain intact. Input assembly records are
unchanged; vertical correction is forbidden and seam residuals remain explicit.
Three insertion seams are exact. The north-east corner/south-ramp combination
retains a2-unit lane-centre difference and36-unit width difference.
These new arrangements are inspection candidates, not approved production
connections. They do not reopen the seven previously accepted examples.

Historical isolated inspection fixtures used a measured insertion-seam spawn
when no terrain slot was available. The active trusted plan strips that
candidate and uses a 640-grid terrain tile instead; it performs no AABB spawn
selection and does not claim full-height entity-clearance proof.

The user's mixed-layout corrections keep each bridge at physical `(0,0,0)`
and rebase its terminal around the exact insertion seam. South deadend origin
is `(0,1280,0)`; north is `(16,-1280,0)`, preserving the measured asymmetric
mouths. Ramp combinations retain their original wide owners, yaws and origins.
Both mixed ramp approaches now connect the centred side-entry to the offset
ordinary-road ramp through corner/straight/corner. The required lateral
distance1408 uses two standard corner mouths plus an explicitly approved
768-unit straight section. The source initializer reuses the rectangular
VMF transform for the original straight's longitudinal endpoints only;
width, deck and texture axes are unchanged. It creates
`tiletemplates/roads/connectors/tile_road_straight_768.vmf` once, never overwrites
an existing editable source, and is not an automatically discovered grid tile.
`Get-ZMOrdinaryRoadMouths` and `Get-ZMComplexMotorwayGates` remain optional
source-survey diagnostics. They can read saved floor windings and reject stale
source fingerprints; do not invoke that measurement path for the trusted
Phase J plan or use it to re-prove approved motorways. The active refresh uses
the prior exported road and motorway gate records, preserving the special
south outer-row gate and ordinary-road approach positions without recalculating
them. Compilation and live travel review are still required.

The approved south mixed-road approach uses gate Y-2720, arrow Y-2624 and
arrival Y-2592 at X0/deck36. Ordinary-road96/128 insets keep both points on the
centred approach before its corner; motorway256/384 insets remain unchanged.
Explicit `route = 'road'` metadata has one centred lane. Missing `route` remains
the existing two-lane motorway contract. Server publication/arrival validation
and trigger bounds handle both; road barricade composition stays native.
Shared-map route/count conflicts fail closed. Actual engine clearance/travel
and normal complex plan/export/emission remain separate pending gates.
Standalone ramp offsets are not automatically handled by the mixed1408 route.

`-Mixed` automatically enables complete rectangular infill, including the
measurement/create/re-emission pass. Existing corner-specific exclusions and
fractional/sub4 remainder policy are preserved. The old no-infill/off-centre
fixtures are superseded inspection history. Fresh corrected output under
`generated/phase_e_mixed_centred_routes_20261014` passes four-map VBSP,
portal budgets and VVIS/VRAD using the preview fast preset; mixed infill27022
assertions accounts for128 emitted rectangles. All four exact corrected VMFs
are opened in new Hammer++ windows for human review; prior windows are retained.
No preview world index or installed BSP was changed.

The subsequent human review approved both bridge/deadend arrangements,
deadend/on-ramp and the corner's connecting row. The obsolete ordinary straight
at the corner's south border slot `(2,5)` is now the existing planned terrain
source, using standard `zm_border_` ownership. Cleanup runs only on unleased
legacy transition-road records belonging to a centred mixed-road approach;
other sides, neighbours and nonmixed layouts are preserved. Fresh output under
`generated/phase_e_corner_terrain_cleanup_20261014` passes the same compile/
portal/infill checks, and the three approved control VMFs are byte-identical.
Normal runtime gates remain separate pending integration.

Fresh junction-only verification uses
`generated/phase_e_junction_cell_verification_20261014`: the seven complete-cell
suite passes3436 assertions; only its exact crossroads and explicitly synthetic
motorway T were freshly compiled through VBSP/portal budgets/VVIS/VRAD with
the preview fast preset. The matching full density plan has four motorway
crossroads but no motorway T cells; ordinary road T cells and on-ramp road
branches must not be misreported as the wide T source. The suite rejects
mixed layouts missing a measured transport record rather than rejecting
the now-supported combinations categorically. Normal/live integration remains
separate. The user approved final corner cleanup with missing infill explicitly
expected.

```powershell
.\bin\build_motorway_cell_preview.ps1 -Mixed -OutputDirectory .\generated\phase_e_mixed_centred_routes_20261014
.\bin\test_terrain_infill.ps1 -Mixed -OutputDirectory .\generated\phase_e_mixed_centred_routes_20261014
```

`Assert-ZMStraightMotorwayCellContract` in `bin/motorway_geometry.psm1` validates
the approved isolated inland-straight corridor before the builder replaces
border/outer placements. Vertical and horizontal cases have nine emitting
owners,27 exact leases and25 unique core records. Authored3x1 dimensions,
rotated reservations, physical origins and core/border/outer ownership agree;
occupied core slots cannot emit or reference another owner. Non-finite or
shifted origins, incomplete leases and duplicate owners fail explicitly.
Validation is read-only. Water/ocean borders and den entrances remain outside
this contract.

Core and ring instance emission now consumes each measured motorway owner's
`originCellLocal` XYZ directly, independently of its reservation anchor.
These are complete physical cell-local coordinates: do not rotate them again
or add a tile Z offset. The measured path requires its approved5x5/640-unit
frame and zero tile Z offset; other frames fail rather than silently moving
the geometry. Fractional coordinates are preserved with invariant-culture VMF
output. Ordinary placements retain centred origins and existing interior
integer rounding. Explicit origins remain limited to the isolated measured
motorway path; this does not authorize new ordinary authored offsets.

```powershell
.\bin\test_motorway_geometry.ps1
```

This source-only fixture exercises production corridor creation and validation,
including malformed-record rejection. It does not regenerate, compile or stage
maps. Normal-world enablement, complex assemblies, boundary closure and actual
travel remain Phase E/G gates; isolated lease validity is not physical approval.
The suite also tests the production core/ring instance writer's exact VMF
entity lines, independent fractional origins, invalid-frame rejection and
ordinary-placement compatibility. These are entity-output fixtures, not a
fresh complete-cell VMF or compiled geometry check.

## Alpha 3.2 scenery-density contract

The pure policy in [scenery_density.psm1](bin/scenery_density.psm1) is covered by
the fast, isolated regression:

```powershell
.\bin\test_scenery_density.ps1
```

This focused contract/planner regression is not full world regeneration or
proof of every placement exclusion. It runs the real manifest serializer with
explicit cell fixtures, reloads its temporary JSON and removes that file
afterward. The planner fixtures also exercise strict policy-v1 selection for
ordinary single-tile buildings, decorations, optional multi-tile buildings and
open-terrain fill, including decoration placement on a motorway cell with no
building candidates. Motorway fixtures also verify that ordinary building
selection remains active on ordinary roads, while motorway settlement
occupancy, building insertion, forced carparks, physical landmarks, multi-tile
landmarks and safe-zone entrances are rejected. Radiation-source relocation
fixtures verify that a source initially on a motorway fails without mutating its
identity or location; successful ordinary-road placement records the original
cell, destination, identity and reason in generation diagnostics. Special
named-landmark templates are selected by hard density compatibility within the
existing footprint; an unavailable required tier fails explicitly rather than
changing the landmark or footprint. Legacy manifests retain the previous
first-template behavior. Policy-v1 standard border and outer-edge walls also
select deterministically from their established profile-specific pools;
road-adjacent slots use the prescribed route target and existing high-tier
exclusion. Road, ramp, bridge, water, carpark, corner, and entrance behavior
remains owned by its existing functional selection path. Wall placements record
their selected target and exclusions in layout metadata. Complete occupied
route-footprint adjacency, unavailable-tier fixed identities, other fixed-
identity conflicts and full-world behavior remain tracked in
[Alpha 3.2](todo-alpha.3.2.md).

New manifest exports resolve the existing environment profile priority once,
then store `sceneryDensityPolicyVersion=1`, `sceneryDensityTier`,
`sceneryDensitySource`, `sceneryInlandDistance`, and the identical legacy
`buildingDensityTier` alias on each cell. The manifest environment header
declares policy version1. Higher-priority destroyed/safe-zone/etc. profiles
retain their existing precedence over commercial/financial tags; density does
not reinterpret tags separately from that profile resolution.

The planner consumes the stored result for recipe seeds, filename density and
variants, and copies the metadata into its plan. On policy-v1 manifests, its
optional scenery selectors apply hard tier compatibility: tagged candidates
must match the deterministically rolled target tier, while untagged candidates
remain neutral within their already-compatible family and footprint pool.
Selection is deterministic across candidate enumeration order and includes the
cell variant; a missing optional tier records a terrain-preserving shortage
instead of falling back to a forbidden tier. Legacy manifests keep their
existing selection behavior. Runtime export requires
manifest/plan metadata to match and retains those fields for diagnostics.
Consumers validate the policy, source/band consistency and alias rather than
recomputing density from local environment tags. Incomplete metadata, unsupported
versions and mismatched aliases fail explicitly. Legacy manifests without any
density policy retain their prior tag/profile-based behavior; the planner emits
a legacy warning. Regeneration, not loading old data, adopts the new zoning.
No existing plan or staged runtime is migrated in place.

Numeric template variants do not determine density. A terminal numeric variant
plus letter tag, before an optional footprint suffix, is classified by letter
count: one low, two medium, three high. Thus `6a` is low, `1bb` medium,
`1aaa_3x` high. Untagged pieces are neutral within their compatible functional
pool; they are not a global substitute for missing walls, corners or terrain.
Unsupported tags fail rather than becoming neutral. Classification does not
infer physical height or validate authored footprint geometry.

Approved zoning measures cardinal land-cell steps from explicit actual-ocean
boundary cells (distance zero), not decorative water, lakes or arbitrary grid
edges. Distances0-2 are protected low;3-7 medium;8+ high. In the current straight
west-ocean world this distance is logical x. Commercial/financial profiles raise
inland cells to high; settlement raises to at least medium. Coast always wins;
danger, radiation and occupancy do not participate. Missing ocean sources or
land disconnected from them fail explicitly.

The target-tier roll is low100%, medium95% medium/5% high, high95% high/5%
medium. Route-adjacent wall targets are low in low zones and medium otherwise.
Callers must derive that adjacency from complete occupied route footprints.
Selection accepts an already compatible family/footprint pool, sorts canonical
paths ordinally, and permits only the target tag or neutral. Optional shortages
report `shortage_keep_terrain`; required shortages fail with caller context.
Consumers must aggregate/report these diagnostics, not silently discard them.

The standard cell-border corner pool is an explicit exception to complete tier
coverage: policy-v1 recipes choose the low `1a` corner for low targets and the
medium `1aa` corner for medium targets. A high target explicitly falls back to
that medium corner because no compatible high standard corner is authored.
`cornerDensityFallbacks` must name a tagged member of
`cornerVariationTemplates`, and builder preflight rejects uncovered targets or
invalid fallbacks. This exception is limited to standard border corners;
profile-specific single neutral corners, water corners, legacy plans and their
single `cornerTemplate` setting retain their existing behavior.

`Get-ZMScenerySelectionHash` uses a versioned, length-framed SHA256 key containing
seed, cell/recipe policy, ring, slot, role, variant and separate tier/template
purpose. The policy-v1 planner selectors use the tier hash modulo100 for the
roll and the template hash for choice; changing enumeration order must not
change selection. Policy-v1 recipe layout identities also include the map seed,
which boundary-wall selection consumes, so different seeded wall layouts cannot
reuse one recipe filename. This does not mean every scenery family or
fixed-identity placement is already wired to the policy.

## Canonical Tile Orientations

For Alpha 3.2 wide-motorway integration, the user trusts the authored sources;
individual asset re-approval is not required. Use
`.\bin\survey_motorway_templates.ps1 -WorldProfile preview` for read-only saved
winding summaries and `.\bin\test_motorway_survey.ps1` for focused regression.
An optional `-Output <report.json>` records detailed winding/material/entity
evidence. This is not compiled collision, inferred drivable ports or prop bounds.
Review generated assemblies in Hammer when needed, not each known-good asset.
Preserve authored carriageway/deck offsets; the old narrow motorway measurements
do not apply to the new family.
The user confirms all new pieces match their1x1 counterparts' orientations in
every circumstance. Reuse the existing canonical topology/yaw mappings; wider
dimensions or asymmetric port positions do not authorize rotation changes.

[motorway_geometry.psm1](bin/motorway_geometry.psm1) provides wide-only nominal
footprint lookup, cardinal physical point/envelope transforms and occupied-slot
records from an explicit top-left logical anchor. Run
`.\bin\test_motorway_geometry.ps1` for focused geometry-contract checks.
At90/270 degrees width/height swap;6x3 and3x4 even spans keep half-tile centres.
Reservation `originOffset` is measured from the anchor tile's physical centre,
not an inferred correction to the authored VMF. Logical south means negative
physical Y. A separate envelope retains physical overhangs; nominal slots alone
are not collision validation or ring leases. These helpers are not yet wired
into placement; ports, alignment/anchor solving and Z-layer compatibility remain
Phase B integration work.

Straight and bridge port contracts now come from explicit source floor faces:
416-wide motorway carriageways at Z68, centres-512/+528; bridge central road
floor width256 at Z232.375. These are separate surface layers, not legacy
deck/arrival constants or full pedestrian-clearance envelopes.
`Get-ZMMotorwaySurfacePorts` rejects unrecorded complex-piece connectors;
`Convert-ZMMotorwayPort` preserves the mapped yaw and transforms heading/position.
`Resolve-ZMMotorwayPortTranslation` accepts a fixed world port and a moving
local port at an explicit yaw/existing Z, solves X/Y only and requires exact
type/width/opposed-heading/grade/deck compatibility. It never scales geometry,
changes yaw or hides a height mismatch. Exact comparison applies to the current
shared planar surfaces; no unproven curved-mouth tolerance is assumed.
The focused survey suite tests these measured seams in all four rotations.

For the generated Phase B integration inspection, run:

```powershell
.\bin\build_motorway_preview.ps1 -WorldProfile preview
.\bin\test_motorway_preview.ps1
```

The default isolated output is `generated/phase_b_motorway`: one overview of
all eight pieces, eight four-rotation fixtures with saved cameras, the raw
source survey and `assembly-report.json`. Output outside `generated` is rejected.
The overview's left/right rows are straight/bridge, corner/crossroads,
T/deadend and single/dual ramp. No normal recipe plan, settings or installed
world is regenerated.

`Get-ZMMotorwayMouthRegistry` records full-family floor-edge provenance, fractional
endpoints, measured outward grade and planar/continuity flags. The report
separates exact floor joins, inspection-only first-lane alignments with residuals,
and ordinary-road approach gates. Road approach source floors are recorded
separately, not forced onto unmatched ramp/bridge decks. Diagnostic seams never
count as successful planner fallback placements.

Placement records use explicit cell-local physical bounds and logical tile
leases for core/border/outer rings; only the placement owner emits an instance.
Nominal rectangles and saved winding envelopes are separate. Positive-volume
envelope overlaps remain clearance gates, not automatic underlay exceptions.
These fixtures do not establish compiled collision, prop/displacement bounds,
pedestrian clearance, approved tolerances or whole-cell topology support.
See the [Phase B tracker](todo-alpha.3.2.md) for precise remaining gates.

For cell-level inspection, `.\bin\build_motorway_cell_preview.ps1` creates two
complete straight-cell examples through the ordinary planner and VMF builder,
not through the asset-overview writer. Both scripts require an explicit
`-MotorwayCellInspection` mode; the wrapper supplies isolated settings, cell
and skybox output directories. Run `.\bin\test_motorway_cells.ps1` for actual
written-cell and normal-generation controls.

The default output is `generated/phase_b_motorway_cells`. North-south logical
(6,-11) and east-west logical(2,-5) retain the normal shell, scenery and9x9
frame. The axis stays unchanged while three-wide reservations replace15core,
6border and6outer slots, with nine emitting stripe owners. Ten surrounding
core slots contain terrain/decorations, never a building fallback. The border
writer uses each rectangular owner's center rather than emitting at its anchor
tile; ordinary1x1ring origins are unchanged.

Both complete straight-cell examples received human Hammer approval. Their
scoped fixture settings repair renamed source references without modifying
normal settings. No legacy narrow gates/blockers are emitted; complex/coastal/
landmark cells fail rather than masquerading as supported. This is isolated
geometry inspection, not full density/topology/clearance/live-travel acceptance.

`.\bin\build_motorway_cell_preview.ps1 -Complex` adds seven complete diagnostic
cells under `generated/phase_b_complex_cells`, leaving the approved straight
output unchanged. It generates a fresh measured assembly report, then passes
`-MotorwayAssemblyReport` to the normal planner's inspection pass. Schema2
emits measured transport owners at exact fractional XY/yaw/Z0, leases all
intersected core/border/outer slots and suppresses conflicting scenery. Ordinary
road approaches use their saved world/brush-entity windings, not guessed1x1
bounds. Every actual instance participates in conservative positive-volume
overlap diagnostics; source changes invalidate the report. Roads remain at
authored Z and unresolved height/grade/seam/partial-boundary issues remain
explicit; conservative AABB overlap is not a compiled collision verdict.
The default straight path remains schema1.

Run `.\bin\test_complex_motorway_cells.ps1` for seven-piece coverage, exact
written-source transforms, shell/skybox/scenery ownership, all-instance overlap
evidence, source fingerprints, repeat VMF/layout determinism and rejected mixed
topologies. The T-junction is labelled synthetic because the real matching
world has no T. Existing bridge yaw90 is preserved even though measured
motorway directions then disagree with the source N/S highway. Do not hide
that mismatch, ignore transport on corner/terminal cells, invent tolerance,
scale pieces or shift Z to claim support. Hammer review, approach/topology
resolution, shell/prop/displacement clearance and compilation remain gates.

### Rectangular ground infill

The user chose authored-size templates so artists can decorate infill areas.
`bin/create_terrain_infill_templates.ps1` initializes missing sources from the
existing grass slab; it never overwrites existing sources. The editable
`tiletemplates/terrain/infill/tile_ground_full.vmf` is640x640,
`tiletemplates/terrain/infill/tile_ground_half.vmf` uses X+/-160,Y+/-320,
and `tile_ground_quarter.vmf` uses X/Y+/-160. Both retain Z0..32, original
materials and UV scale. Rotation supplies the horizontal half. Preserve the
base ground brush/dimensions; review any added brush/prop detail for actual
bridge/ramp clearance before distribution. These templates are explicit infill
sources, not entries in the ordinary full-tile random terrain pool.

`bin/terrain_infill.psm1` now uses only the shared standard ground-base
classifier for coverage, not every brush intersecting Z0..32. Road, wall and
other structural geometry must not produce triangular cut-outs. Nonstandard
ground, displacement and wholly underground solids conservatively reserve the
declared source footprint for review; they are not treated as proven ground.
Empty quarter slots prefer a full640x640base, then half/quarter sources.
Scenery leases remain unchanged. Structural/model clearance remains separate.

The cell builder records emitted ground owners, area and source fingerprints
in `terrainInfill` layout metadata. Existing schema2inspection VMFs can refresh
from their verified old structure when infill instance counts change; ordinary
and schema1straight layouts keep their original structure. Run
`bin/test_terrain_infill.ps1` for base dimensions/materials/no-overwrite,
integer rectangle selection, positive-area exclusion, accounted ground/exclusions
and actual written-cell evidence. Corrected inspection output is isolated under
`generated/phase_b_infill_cells`; no whole-world generation or staging is needed.

Only schema-2 recipes with a measured `motorwayAssembly` or
`motorwayCellInspection` contract receive terrain infill. Ordinary preview
recipes are never passed through `Set-ZMInspectionTerrainInfill`. To avoid
reprocessing ordinary recipe VMFs during the infill stages, use
`-MotorwayOnlyInfill` for both builder passes and `-MotorwayOnly` for source
initialization. This mode selects the deduplicated measured motorway recipes,
preserves existing ordinary VMFs and safe-room maps, and rejects stale-output
pruning rather than deleting unrelated generated files. Run the ordinary
full-plan VMF build separately without infill switches first; the
motorway-only pass is not a replacement for full preview generation.

```powershell
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData <plan.json> -CellDirectory <generated-src> -SkyboxOutputDirectory <generated-skybox> -RefreshGenerated -MotorwayOnlyInfill -MeasureCompleteTerrainInfill
.\bin\create_terrain_infill_templates.ps1 -WorldProfile preview -PartialGapLayoutDirectory <generated-src> -CompletePatches -MotorwayOnly
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData <plan.json> -CellDirectory <generated-src> -SkyboxOutputDirectory <generated-skybox> -RefreshGenerated -MotorwayOnlyInfill -SizedTerrainInfill -CompleteTerrainInfill
.\bin\test_motorway_infill_scope.ps1
```

The original corner/crossroads reviews remain accepted. `-SizedInfill`
subtracts recognized axis-aligned ground bases from each quarter and uses
power-of-two rectangular sources for admissible gaps. The missing-only initializer accepts
`-PartialGapLayoutDirectory` to create those sources; add `-MotorwayOnly` to
restrict discovery to measured motorway layouts. An explicit second
inspection build uses `-SizedTerrainInfill`. Neither flag enables normal or
production generation. Names encode integer Hammer-unit dimensions
(`u304_u320`), not nominal tile-count suffixes. Decimal-sized and polygon
sources are prohibited. Legacy decimal/shape files are not selected.

No instance is scaled and no existing source is overwritten. The approved
corner review is not reopened; refreshed rectangular fixtures are isolated.
Rectangle patches stay disjoint from recognized ground and each other.
All emitted world edges are integer-aligned. Extra patch dimensions must each
be16,32,64,128,256or512; the standard full640/half320x640/quarter320bases are
explicit exceptions. Admissible gap interiors decompose into those reusable
sizes. Fractional boundaries are inset to integer edges rather than extended
into existing ground; any remainder thinner than16is left on the default black
floor and recorded, never turned into a thin or decimal-named source. Tests distinguish
actual ground from reported exclusions; accounted area is not a full-ground
or collision acceptance claim.

### Standard ground and source-origin checks

Every tile is centered at local `(0,0)` using its **declared ground footprint**,
not its props, overhangs, carriageways or the average of surviving grass pieces.
The current plain base is a640x640 world brush, bottom Z0/top Z32, six box faces,
four saved vertices per face, one known terrain top material and the original
`BUILDING_TEMPLATE/BUILDING_TEMPLATE028A` underneath/on its sides.
`bin/tile_ground_grid.psm1` recognizes the existing grass, dirt, debris, fence
and sand base materials explicitly. Material names alone do not identify ground.
Displacements, curved/sloped brushes, elevated floors, brush entities and
custom partial infill footprints are not automatically repaired under this rule.

Full-tile edges lie on the320-unit half-tile lattice; base-cell spacing is640.
The tool warns for deviations and reports source/solid/coordinates. Only
sub-unit errors with compatible box geometry and plane points qualify for
ground-only snapping. Snapping updates both planes and saved windings, never
scales an instance. Larger discrepancies require review.

Origin inference additionally requires a complete, nonoverlapping rectangular
set of640-unit bases matching the declared filename footprint (`NxM`, square
`Nx`, or the established `motorway_3x1` family). Partial/asymmetric layouts do
not establish an automatic center; they need an explicit reviewed reference.
An offset complete reference warns separately. An explicitly approved whole-
template translation moves brushes and entity origins together, keeps angles,
IDs and model paths, and locks UVs. Displacements/overlays reject this automated
translation rather than being partially moved.

Planner, cell/zoo builders and recursive compile/skyline source dependencies
share the warnings; each source revision warns once per module lifetime.
Generation never mutates authored assets. `repair_tile_ground_grid.ps1` is
report-only by default; explicit `-Apply` saves SHA256-verified original VMFs
under `generated/tile_ground_grid_repair`. `-CenterOrigin` is additionally
required for whole-template centering. Preserve companion VMXs/artist edits
and inspect changed source fixtures before compiled acceptance.

Correct source errors **before** measuring infill. The T-junction's shared
Y-0.388 offset was recentered with its roads/props; near-zero ground errors in
that source and both ramp sizes were snapped separately. Its remaining
306.00005-unit north-continuation offset is lane-derived, not proof that the
ground is still misaligned. Do not round that placement or silently alter yaw.

Partitioned plain bases may establish an origin when their nonoverlapping box
areas fill the complete declared rectangular footprint exactly (with only
double-summation roundoff accounted for). Their intentional internal edges are
not forced onto full-tile boundaries. Displaced bases remain read-only review.
Plane coordinates are audited separately from saved windings: rounded windings
can conceal tiny actual brush-plane errors.

The current building audit found no need to reposition ordinary building bodies.
Eight building sources had proven ground-plane-only discrepancies; those planes
and their windings were corrected with verified backups. The2x park was a
separate whole-source defect: its31plain ground partitions exactly filled1280x1280
at Y-608..672, proving a shared Y+32offset. The whole source moved Y-32 with
props and locked textures. The army-wall source similarly moved X-2.542.
Unknown/displaced/partial references are not silently treated as safe to snap.

### Rectangle consolidation and legacy infill retirement

As of2026-10-14, the polygon-generation approach is rejected. The retained
`-CompleteInfill` compatibility flag means consolidated **rectangles only**,
not guaranteed complete coverage. Its first pass measures admissible rectangles;
the initializer creates missing sources, and the second pass emits them.
Consolidation requires touching integer rectangles whose union remains an
axis-aligned rectangle within the5760cell frame, with unchanged area and no
ground overlap. Artist-edited or VMX-owned rectangular sources are not merged
away. Concave unions, angled fragments and fractional boundaries remain
review-required. Standard tiles are preferred for 320/640-grid rectangles;
other rectangles split into strict power-of-two sizes from 4 through 512 on
both axes, including U4/U8 for narrow bounds-verified gaps. Fractional or
sub-4 remainders stay on the default black floor. No source movement or
outward snapping tolerance is added.

Legacy polygon reader/writer helpers remain solely to identify archival
defaults. All61hashed shape and12decimal-named source files were explicitly
removed with verified backups on2026-10-14. The initializer cannot create
either kind of source, and the old
`-RepairUnmodifiedShapeWinding` option now fails with an explicit retirement
message. Tests inspect actual emitted six-faced rectangular sources, integer
edges, overlap exclusion and ground/review accounting at all four rotations.
They do not prove BSP collision, displaced/model coverage or travel.

`clean_terrain_infill_templates.ps1` accepts an explicit current layout set,
verifies matching VMF hashes and dependencies, and retains authored nested
references plus full/half/quarter base sources. Audit is default; `-Apply` archives
only unused byte-identical defaults with SHA256 verification. Unknown/edited
sources and sources with VMX companions remain. Archive and cleanup ledgers live
under `generated/retired_terrain_infill`; superseded fixture dependencies must
be restored from there or regenerated before further use.

### Canonical authored orientations

All template rotations are measured from these `$0^\circ$` authored orientations. Keep this reference when adding generator placement rules or diagnosing a rotated tile in Hammer:

| Template family | `$0^\circ$` authored direction |
| --- | --- |
| Straight road and motorway | South to north |
| Road and motorway corner | East to south |
| Road and motorway T-junction | East to west, with its connecting stem north |
| Bridge ramp | North to south, rising toward north |
| Motorway road bridge | Motorway east to west below; road north to south above |
| Building | Entrance on the south edge of its tile |
| Border wall | North to south, offset to the east tile edge |
| Border wall corner | North to east, at the north-east tile corner |
| Carpark entrance | Connective tip on the south tile edge; standard variants have local east and west lanes. At `$0^\circ$`, `_deadend_west` closes west and connects east, while `_deadend_east` closes east and connects west. |

Instance yaw follows Source's world-space rotation: positive yaw turns counter-clockwise in Hammer's XY plane. Convert logical north/east/south/west directions to physical yaw before rotating a marker or footprint; logical tile-grid rotation alone uses the opposite sign.

The generated border ring sits one tile outside the playable cell. Its corner instances use the Hammer-verified yaws `NW=0`, `NE=270`, `SE=180`, and `SW=90`, placing the authored corner against the level rather than toward the skybox.

### Tile Road Connections

Every building template has one `zn_tile_direction` point entity. Its `direction` identifies the local tile edge containing the entrance, and the point must sit at that edge's midpoint: `south` is `0 -320 32` (1x), `0 -640 32` (2x), `0 -960 32` (3x); `north` is `0 320 32` (1x), `0 640 32` (2x), `0 960 32` (3x); `east` is `320 0 32` (1x), `640 0 32` (2x), `960 0 32` (3x); `west` is `-320 0 32` (1x), `-640 0 32` (2x), `-960 0 32` (3x). The building is rotated so this tile edge aligns with an adjacent compatible ordinary road, motorway, or concrete path, if one is present, without changing which tile it occupies.

Add zero or more `zn_road_connection` points only where a generated road must physically connect. Each point must be centered on a single exterior footprint segment, and `connection_type` defaults to `none`. A `t_junction` point converts its exact adjacent compatible ordinary straight-road tile into a T-junction; a `bus` point converts it into `roads/tile_road_bus.vmf`, and a `driveway` point converts it into `roads/tile_road_driveway.vmf`. Multiple distinct points create multiple connections, each keeping its own requested type. The 2x commercial and hospital carpark-frontage templates each use one south-edge T-junction point. A motorway or concrete path is valid frontage but denies any of these connection requests and remains unchanged. A marked template is not placed when every requested connection cannot be satisfied. These markers are planning metadata and have no gameplay behavior.

Buildings and landmarks rotate their tile edge entrance toward a directly adjacent road, motorway, concrete path, or transport tile. A building next to a road corner's closed edge still faces the corner visually, although that edge is not a road connection.


### Carpark Endcap Orientation Contract

Carpark lanes that reach a cell edge receive a deadend cap in the normal generated border ring. The cap's **physical outer side** determines both its VMF and its `func_instance` `angles`; the local `carpark_lane_east` or `carpark_lane_west` role must not be used for either decision. A local west lane can, for example, terminate at the physical east border.

The tile grid uses `tileX` increasing east and `tileY` increasing south. Test the edge tile first, then place the cap one tile beyond that edge:

| Physical cap side | Edge-tile test | Outer cap coordinate | VMF | `angles` |
| --- | --- | --- | --- | --- |
| North | `tileY = 0` | `(tileX, -1)` | `carparks/tile_carpark_deadend_west.vmf` | `0 270 0` |
| East | `tileX = gridSize - 1` | `(gridSize, tileY)` | `carparks/tile_carpark_deadend_east.vmf` | `0 0 0` |
| South | `tileY = gridSize - 1` | `(tileX, gridSize)` | `carparks/tile_carpark_deadend_west.vmf` | `0 90 0` |
| West | `tileX = 0` | `(-1, tileY)` | `carparks/tile_carpark_deadend_east.vmf` | `0 180 0` |

These are output-instance angles, not rotations to bake into either source VMF. [carpark_endcaps.psm1](bin/carpark_endcaps.psm1) owns this table and is imported by both the regular VMF builder and the borderless carpark zoo. Do not duplicate or derive the table from lane roles elsewhere.

One-sided entrance variants use their own Hammer-verified file/yaw pairing because their suffix names the **local** lateral edge that is dead-ended: `tile_carpark_entrance_deadend_west.vmf` closes local west and leaves local east connected, while `tile_carpark_entrance_deadend_east.vmf` closes local east and leaves local west connected. The road connector remains on the authored south edge. The planner selects the suffix from the local closed lane and rotates the entry piece `$180^\circ$` from the carpark assembly yaw. This yields `_east` at `0 0 0` for the south-side short preview entries and `_west` at `0 180 0` for the north-side short fixture. Ordinary deadend-cap orientation remains unchanged. `tile_carpark_entrance_deadend.vmf` is different: it keeps the ordinary entrance-facing yaw but emits no lateral lane tiles.

An enabled lane is deterministically one or two straight tiles long according to `carparks.minimumLaneTiles` and `carparks.maximumLaneTiles`. Both enabled arms in one carpark use the same length. A short lane receives a `carpark_lane_endcap_east` or `carpark_lane_endcap_west` tile in the first unused in-grid space, selected through the same physical-side table. A full-length lane reaches the cell edge and receives the usual outer-border cap.

For the current preview seed, [carparks.vmf](celltemplates/dev/carparks.vmf) provides one repeatable Hammer check for each side:

| Zoo target | Physical side | Expected VMF and `angles` |
| --- | --- | --- |
| `zm_dev_carpark_0_carpark_endcap_3_-1` | North | `deadend_west`, `0 270 0` |
| `zm_dev_carpark_1_carpark_endcap_5_3` | East | `deadend_east`, `0 0 0` |
| `zm_dev_carpark_0_carpark_endcap_3_5` | South | `deadend_west`, `0 90 0` |
| `zm_dev_carpark_1_carpark_endcap_-1_3` | West | `deadend_east`, `0 180 0` |

After changing carpark placement code, refresh the zoo with `.\bin\build_tile_zoos.ps1 -RefreshPlan`, reopen it in Hammer, and inspect both the `file` and `angles` keyvalues against this table. Then rebuild preview source VMFs before compiling. When a carpark junction is on a bridge-ramp cell, the ramp moves to the first bridge-side tile so the junction connects to the highway.

The `cellPlanning.rotations` values in [generator-settings.json](generator-settings.json) rotate these authored orientations into the recipe's required exits. Do not infer a yaw from a filename alone; verify it against this table and the template in Hammer.

## World-Generation Profiles

`worldGeneration.profiles` in [generator-settings.json](generator-settings.json) defines every generated world. A profile owns its grid size, generated file prefix, layer-image setting, source VMF folder, compiler build folder, staged map folder, runtime-world JSON, and optional launcher thumbnail. The included `city` and `preview` entries are normal profiles; add another entry such as `coast` to build a separate custom city without adding another set of special-case settings.

`build_city.ps1` also stages generated in-game map materials in `content/materials/worlds/<profile>`. The composite world image and its exported layers are placed in `map_layers` with stable names: `world.png` for the composite and `<layer>.png` for every individual layer. One local schematic for each reusable city recipe is rendered in `cells` using the matching BSP name with a `.png` extension. Expanded maps use the generated layout metadata to render the 5-by-5 core inset within the complete 9-by-9 core/border/outer frame; omitted ocean-side outer bands use water rather than invented scenery. Each local map reflects its actual core, border and outer placements, dark asphalt roads with yellow dotted centerlines, road or motorway topology, blocked exits, building squares, and every carpark entrance, junction, lane, and endcap. Per-recipe and stitched wireframes project nav areas against the same authoritative neighbour pitch, keeping their core nav coverage inset consistently within that frame. Carparks use a lighter surface and outlined parking bays. It marks named landmarks at their exact planned tile positions; commercial-building tiles are marked `COM`, while a future dedicated `tile_market` remains a named `MKT` landmark. Satellite mode always renders the generated named-landmarks overlay above its satellite image and is stitched from the local recipe maps at the highest whole-cell resolution within the 4096px material limit. Each local recipe map is rendered at `-ResolutionScale` times the authored 48px-per-tile layout (4x, or 960px square, by default), so the stitched satellite downsamples from sharp source art and the client can draw individual cells at native resolution. `build_world_wireframe_material.ps1` likewise writes one per-recipe navmesh image into `cells_wireframe` alongside the stitched `map_layers/wireframe.png`, sized by `-CellImageSize`. Source map layers are replaced for each plan while the derived satellite is retained until the stitcher overwrites it. Profile generation automatically removes stale generated source world maps and layers, source VMFs, zoo VMFs, compiler artifacts, staged BSPs, cell maps, and map-layer PNGs; it does not touch authored templates or other profiles. Set `exportLayers` to `true` for any profile that needs the individual world layer images; the release build stops with an actionable error when they have not been generated.

The native client map opens with `M` or the `zombiesim_map` console command. It supports layer toggles, pan and deep zoom, selected-cell inspection, selected-cell right-click waypoints, and dynamic player and road-blockade overlays. Layer toggles are per render mode: the Layers list only offers the layers that view can use, and each mode stores its own toggle state. Atlas offers the full authored stack (terrain, districts, buildings, roads, motorways, metro, safe zones, landmarks, radiation, danger, and the map key) with stacking order controls. Satellite and Walkers omit terrain, buildings, roads, and motorways because the satellite image already contains them, and default to safe zones, landmarks, and the map key. Wireframe draws no map layers, title, or map key at all; it shows only a red cell-boundary grid over the wireframe, the player, the waypoint and its route, the selected cell, and safe-zone destinations, all drawn directly in Lua so they stay sharp at any zoom. A waypoint draws a route from the player that avoids blocked roads when a valid path exists. Satellite, Walkers, and Wireframe swap from the stitched atlas to per-cell images once the zoomed map exceeds the atlas resolution, so deep zoom stays sharp instead of magnifying the atlas; only cells inside the visible canvas are drawn. The title and map key remain fixed in the upper-left and upper-right corners while the world map is moved. It uses Derma and the staged material PNGs directly, so no HTML, CSS, or JavaScript needs to be packaged. Set `zombiesim_map_debug 1` to overlay the current zoom, map size, atlas width, and whether the view is drawing the stitched atlas or per-cell images.

Use `-WorldProfile <name>` with every generator script. Without it, the scripts use `worldGeneration.defaultProfile`, currently `city`. `-Preview` remains a compatibility alias for `-WorldProfile preview` on scripts that already supported it.

```json
"coast": {
	"filePrefix": "coast",
	"gridCells": 48,
	"exportLayers": false,
	"cellDirectory": "generated/src_coast",
	"buildDirectory": "generated/build_coast",
	"releaseMapDirectory": "content/maps/coast",
	"runtimeWorldData": "content/data_static/zombiesim_world_coast.json",
	"overrides": {
		"mapGeneration": {
			"road": { "growthDepth": 4 },
			"blockades": { "chance": 0.15 }
		},
		"cellPlanning": {
			"variants": { "usageThreshold": 8 }
		}
	},
	"thumbnail": {
		"map": "zn_coast",
		"source": "bin/coast_grid_48x48_seed_2026.png",
		"title": "COAST CITY",
		"showLogo": true
	}
}
```

The optional `overrides` object can replace any ordinary generator setting for that profile, including nested `mapGeneration`, `cellPlanning`, `vmfBuild`, `compilation`, `paths`, or `directions` settings. Objects merge recursively, while a scalar value or array replaces the shared value. Command-line parameters still take precedence for one run. Profiles cannot override `schemaVersion` or `worldGeneration` itself.

The profile name should match the `world_profile` key on its launcher map. After adding one, run the ordinary generator pipeline with `-WorldProfile coast`; the configured `filePrefix` keeps its manifests, template plans, required-recipe lists, source maps, build files, staged BSPs, and runtime data separate from all other profiles.

## Preview Workflow

Run these commands from the project root. This uses the small preview city and leaves production cell VMFs alone.

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 1337
.\bin\build_motorway_preview.ps1 -WorldProfile preview -OutputDirectory .\generated\measured-assemblies
.\bin\plan_cell_templates.ps1 -WorldProfile preview -MapData .\bin\preview_grid_24x24_seed_1337.json -MotorwayAssemblyReport .\generated\measured-assemblies\assembly-report.json
.\bin\build_cell_vmfs.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json -RefreshGenerated -PruneStaleGenerated
.\bin\expand_cell_filenames.ps1 -WorldProfile preview -PlanData .\bin\preview_grid_24x24_seed_1337_template_plan.json
.\bin\check_required_cells.ps1 -WorldProfile preview -RequiredCellList .\bin\preview_grid_24x24_seed_1337_required_cell_vmfs.txt
```

Normal wide (3x) motorway cells plan only from current measured assemblies (`-MotorwayAssemblyReport`) and require the expanded border/outer rings. Root settings keep `vmfBuild.outerEdges.enabled` false, so full-world preview batches use an isolated settings copy with it enabled and redirected profile paths. Full terrain infill is three passes: `build_cell_vmfs.ps1 ... -MeasureCompleteTerrainInfill`, `create_terrain_infill_templates.ps1 -PartialGapLayoutDirectory <src> -CompletePatches`, then `build_cell_vmfs.ps1 ... -SizedTerrainInfill -CompleteTerrainInfill`. An explicit `-ContentMapDirectory` (isolated batch) also disables copying and stale-map cleanup in the live engine `garrysmod/maps` folder unless `-StageEngineMaps` is passed; stage isolated outputs through a backed-up ledger instead.

`-WorldProfile preview` makes the map generator use `worldGeneration.profiles.preview.gridCells` and makes planning, building, and checking use the preview profile's configured folders when no explicit path is supplied. `-Preview` is accepted for existing command files and means the same thing.

## Tile Zoo And Dev Cells

Run the tile-zoo generator after adding, renaming, or moving a tile template. Use `-RefreshPlan` after changing placement logic so the street and carpark fixtures use a newly planned, but not VMF-generated, preview:

```powershell
.\bin\build_tile_zoos.ps1 -RefreshPlan
```

It writes one blank `zoo_<category>.vmf` grid for every direct `tiletemplates` category to `celltemplates/dev`. `streets.vmf` renders one distinct non-carpark road or motorway topology/orientation layout from the current preview plan, and every distinct real-preview layout in `carparks.vmf` renders the exact `tilePlacements` produced by `plan_cell_templates.ps1`. These fixtures exercise the same placement logic as normal generated cells without creating preview source VMFs.

`carparks.vmf` has two planner-derived inspection groups:

- The distinct carpark recipes in the current preview plan, including ordinary and bridge-ramp cases.
- The seven deterministic fixtures from [carpark_zoo_fixture_map.json](bin/carpark_zoo_fixture_map.json): ordinary carparks branching north, east, south, and west; a south branch joined to an east bridge ramp; a terminal one-tile entrance; and a one-sided short row. `build_tile_zoos.ps1` runs this logical map through the same planner and refreshes its derived [carpark_zoo_fixture_template_plan.json](bin/carpark_zoo_fixture_template_plan.json) on every zoo build. It asserts the expected lane counts, short-row caps, and one-sided physical yaw contract. Do not manually compose or rotate its VMF placements.

Use [zoo_carparks.vmf](celltemplates/dev/zoo_carparks.vmf) to inspect the individual authored carpark templates.

The fixture target prefixes are `zm_dev_carpark_fixture_vertical_east`, `vertical_west`, `horizontal_north`, `horizontal_south`, `horizontal_south_bridge_ramp_east`, `vertical_terminal_entrance`, and `horizontal_one_sided_east_short`; use these to frame a specific generated arrangement in Hammer. `zoo_manifest.json` records every zoo tile's grid coordinate. Building zoos are grouped by type and ordered by density tier. These are Hammer-only development cells and are not included in normal city generation or release builds.

`-Seed 1337` is a one-run override. It does not edit the settings file. Keep a seed you like so you can reproduce the same city after changing unrelated assets.

Every generator script also accepts `-SettingsPath <file>`. This lets you keep named presets, such as a testing copy or a large-city copy, without repeatedly editing the main settings file.

## Preview Compile Check

Before committing to the long VVIS and VRAD production compile, run the fast structural check below. It runs VBSP against every preview recipe, so it validates VMF syntax, referenced instances, skybox materials, brushes, props, and BSP generation. It does not calculate visibility or lightmaps.

```powershell
.\bin\build_city.ps1 -WorldProfile preview -VBSPOnly -OnlyRequiredMaps -CleanStagedCity
```

This uses the preview profile's `cellDirectory`, `buildDirectory`, `releaseMapDirectory`, and `runtimeWorldData`. It leaves the city profile's maps and runtime data untouched. Omit `-VBSPOnly` only when you want the slower preview VVIS and VRAD pass.

When the current source VMFs, BSPs, and `.prt` files have already passed the VBSP portal preflight, reuse them for a playable VVIS/VRAD-only preview release:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -CleanStagedCity
```

`-SkipVBSP` requires an existing `.bsp` and `.prt` for every required recipe, then runs VVIS and VRAD only. Keep `-SkipRecipeRefresh` with it so the release uses the exact VMFs that produced those portal files. Completed VVIS and VRAD stages are reused when their compiler logs are newer than their `.prt` or VVIS-log input; add `-Force` to run every requested stage again.

Recipe refreshes and compiles are incremental. `build_cell_vmfs.ps1` rewrites a generated VMF, or copies a standalone den template, only when the content differs; its summary reports `unchanged`. A map is recompiled, or its portal data refreshed, only when its BSP is missing or its VMF or any `func_instance` file it references (followed recursively; see `bin/vmf_source_dependencies.psm1`) is newer than the build output. Editing one tile therefore recompiles only the recipes that instance it.

Add `-PrioritizePortalCost` to that reuse build to run the maps with the most portals first. The queue uses portal count, then portal-cluster count, from each `.prt` header. It requires `-SkipVBSP`, since a normal VBSP pass has not yet generated portal data when its queue is ordered:

```powershell
.\bin\build_city.ps1 -WorldProfile preview -OnlyRequiredMaps -SkipRecipeRefresh -SkipVBSP -PrioritizePortalCost -CleanStagedCity
```

## Visibility Budget Check

Use the visibility-budget check after changing structural tile geometry. With `-RefreshPortalData`, it runs VBSP only for city recipes and standalone den maps whose portal data is missing, invalid, or older than the source VMF, then reads each generated `.prt` file to report its portal-cluster and portal counts without running VVIS or VRAD. Add `-ForcePortalData` when a full clean portal rebuild is required:

```powershell
.\bin\check_vis_budgets.ps1 -WorldProfile preview -RefreshPortalData
```

The configured diagnostic budgets are `1,500` portal clusters and `2,700` portals. These thresholds are not engine limits. They are configured under `compilation.visibilityBudget` in [generator-settings.json](generator-settings.json), can be overridden for one run with `-MaxPortalClusters` and `-MaxPortals`, and write `vis-budget-report.json` beside the preview BSPs. For every over-budget recipe, the report also ranks its instanced tiles by their aggregate non-`func_detail` brush-solid count and shows each tile's detail-solid, entity, and prop counts. This is a diagnostic lead rather than a portal attribution: open sightlines between tiles can also create high VVIS cost. The command exits nonzero for over-budget, missing, or invalid portal files.

## Selecting City Data In Hammer

Place exactly one `zn_world_profile` point entity in a launcher map and set its `world_profile` keyvalue. It is a dedicated ZombieSim entity, so other `info_target` or map-logic entities are ignored. Add [zombiesim.fgd](zombiesim.fgd) to the Hammer game configuration to expose it in the entity browser.

The built-in values are `city`, which loads `data_static/zombiesim_world.json`, and `preview`, which loads `data_static/zombiesim_world_preview.json`. The authored `zn_city_start` and `zn_preview_start` launcher VMFs live in `celltemplates/launchers`; their compiled distributable BSPs are staged under `content/maps`. Generated recipe and safe-room maps use `zz_<profile>_` basenames directly under `garrysmod/maps`, keeping them out of the gamemode's `^zn_` launcher-map list while distinguishing profiles. Launcher intermediate compiler artifacts belong in `generated/launcher_build`, not under `content`. A custom profile such as `coast` loads `data_static/zombiesim_world_coast.json`; profile names may only use lowercase letters, digits, `_`, and `-`. Its optional `start_delay` property is a non-negative number of seconds to wait before a first-time player changes level to the world-origin safe room, allowing an opening intro to play. The default is `0`.

The selected profile is retained when changing level to a city recipe or standalone safe-room map, where no selector entity is needed. A map containing conflicting `zn_world_profile` values is rejected so it cannot load ambiguous city data.

## Launcher Thumbnails

`build_launcher_thumbnails.ps1` writes map-menu thumbnails only for profiles with a `thumbnail` entry under `worldGeneration.profiles` in [generator-settings.json](generator-settings.json). By default it refreshes the built-in `city` and `preview` entries:

```powershell
.\bin\build_launcher_thumbnails.ps1
```

Use `-Profile` to refresh one or more named profiles, or `-AllProfiles` to refresh every configured entry that defines a thumbnail. A selected profile only writes its configured target map thumbnail.

```powershell
.\bin\build_launcher_thumbnails.ps1 -Profile coast
.\bin\build_launcher_thumbnails.ps1 -Profile city, coast
.\bin\build_launcher_thumbnails.ps1 -AllProfiles
```

Pass `-CellThumbnails` to additionally create the Garry's Mod map-browser thumbnail for every rendered recipe map in the selected profile. These thumbnails reuse the existing local cell-material images and are written to `content/maps/thumb/<map>.png`, matching the flat staged BSP basename. Recipe names include the profile so different worlds do not collide.

```powershell
.\bin\build_cell_map_materials.ps1 -WorldProfile preview
.\bin\build_launcher_thumbnails.ps1 -Profile preview -CellThumbnails
```

Use the default profiles to refresh both the `city` and `preview` map-browser thumbnails:

```powershell
.\bin\build_launcher_thumbnails.ps1 -CellThumbnails
```

To give a custom city its own launcher thumbnail, add a `thumbnail` object to its profile. `map` is the launcher BSP name without `.bsp`, `source` is an existing project-relative image path, and `title` and `showLogo` control the thumbnail overlay:

```json
"thumbnail": {
  "map": "zn_coast",
  "source": "bin/coast_grid_48x48_seed_2026.png",
  "title": "COAST CITY",
  "showLogo": true
}
```

The script writes the result as `content/maps/thumb/<map>.png`, so this example produces `content/maps/thumb/zn_coast.png`. Use `-SettingsPath` with a separate settings preset when the custom city does not use the main configuration.

## Standalone Dens

Safe-room entrance cells remain normal logical city cells. They are not replaced by safe-room maps and safe-room maps are not added to the city grid or its graph. The city recipe for the entrance coordinate continues to compile as normal and should contain a `tile_saferoom` entrance plus its level-changing entity. Planning separately assigns that entrance to a reusable standalone safe-room map such as `zn_den_ra` or `zn_den_md_hospital`.

`build_cell_vmfs.ps1 -RefreshGenerated` copies the selected den VMF and its optional VMX sidecar unchanged into the active source directory. `build_city.ps1` compiles and stages those den BSPs alongside city recipe BSPs. The runtime index exposes the selected standalone map as `safeZone.map`; future entrance entities can use `ZM_World:GetSafeZoneMap(cell)` to obtain its `city/<den-map>` transition name. The city-cell APIs continue to return the safe-zone entrance cell, never the den itself.

Safe-room templates are selected by semantic biome/profile tags, never by `environment.terrain`. `settlement` is deliberately excluded because it describes the city entrance context rather than the destination. `radioactive` therefore selects `cell_ra_safezone.vmf` even when its city entrance cell happens to use grassland, sandy, or dirt terrain. `gr` means the `grasslands` default den style. The active destination codes are `gr`, `co`, `fi`, `ra`, `fo`, `mi`, `md`, `es`, `rl`, `ss`, `rc`, and `pk`. The existing `st`, `sa`, and `di` placeholder pairs are retained for future semantic profiles, but are not selected from entrance context or terrain labels.

District safe-room placement first prefers an available `Hospital`, `Army Base`, or `Bunker` landmark cell; when none is available, it selects the usual generic safe-room entrance. A supported landmark at the entrance takes precedence over the generic biome map, choosing `cell_<biome>_safezone_hospital.vmf`, `cell_<biome>_safezone_army_base.vmf`, or `cell_<biome>_safezone_bunker.vmf`. All current biome and landmark templates are copies of `cell_gr_safezone.vmf` plus its VMX sidecar, ready for independent Hammer editing. When multiple supported landmarks occur, `Hospital`, then `Army Base`, then `Bunker` is the configured precedence order.

All entrances selecting the same biome and landmark variant point to one compiled destination BSP. `build_cell_vmfs.ps1 -RefreshGenerated` refreshes each selected reusable map from its template and removes obsolete `zn_den_*` source maps from the active source folder. Edit the templates in `celltemplates/safezones`, not the copied `generated/src*` build inputs; normal `build_city.ps1` runs this refresh before compiling.

## Compile Monitoring and Profiles

The compiler prints its current map, stage, elapsed stage time, and remaining map count. It writes a `compile-report.json` beside the intermediate BSPs, for example `generated/build_preview/compile-report.json` for a preview. Each map record includes its stage status, exit code, duration, and stdout/stderr log paths.

The default `compilation.activeProfile` is `stock-gmod`. Its VBSP, VVIS, and VRAD tools are resolved from Garry's Mod's `bin` directory and retain the existing `-game <garrysmod>` arguments. Set a longer or shorter one-run budget without editing the settings file:

```powershell
.\bin\compile_cell_vmfs.ps1 -Preview -VBSPOnly -VbspTimeoutSeconds 120 -DeferredGraceSeconds 180
```

When a stage reaches its timeout it is deferred, not killed, and the next map starts. After all normal work has started, the runner waits for `deferredGraceSeconds`, then records the remaining deferred work in the report. By default it returns an error while any map is failed or unfinished. Pass `-FinalizeWithIncomplete` to finish after writing the report without waiting further. That option does not stage an incomplete release through `build_city.ps1`; it stops before copying BSPs or writing runtime data.

To use another compiler suite, add a complete profile under `compilation.profiles`, then select it with `compilation.activeProfile` or `-CompilerProfile`. `toolDirectory` may be absolute or project-relative. Argument templates are JSON arrays and may use `{gameDirectory}`, `{mapVmf}`, and `{mapBsp}`:

```json
"my-compiler": {
	"toolDirectory": "C:\\Tools\\my-compiler",
	"executables": { "vbsp": "vbsp.exe", "vvis": "vvis.exe", "vrad": "vrad.exe" },
	"arguments": {
		"vbsp": ["-game", "{gameDirectory}", "{mapVmf}"],
		"vvis": ["-game", "{gameDirectory}", "{mapBsp}"],
		"vrad": ["-game", "{gameDirectory}", "{mapBsp}"]
	}
}
```

Hammer++ is an editor/orchestration tool and BSPSource is a decompiler, so neither is a drop-in compiler profile. Compatibility of third-party compiler suites, including HVAC/HAC-style tools, with Garry's Mod's Source branch is not established here. Keep them opt-in and validate a preview `-VBSPOnly` build before a full VVIS/VRAD pass.

## Production Release Workflow

After reviewing the preview, regenerate production recipes so they inherit the current base cell template, including its lighting and fog entities. Then build the release:

```powershell
.\bin\build_cell_vmfs.ps1 -WorldProfile city -PlanData .\bin\map_grid_48x48_seed_1337_template_plan.json -RefreshGenerated
.\bin\build_city.ps1 -WorldProfile city -MapData .\bin\map_grid_48x48_seed_1337.json -PlanData .\bin\map_grid_48x48_seed_1337_template_plan.json -CleanStagedCity
```

`build_city.ps1` runs the sequential VBSP, VVIS, and VRAD compiler pass for every VMF in the selected profile's `cellDirectory`, using that profile's `buildDirectory` as an intermediate folder. It copies only the recipe BSPs selected by the plan to the profile's `releaseMapDirectory` and writes the compact gameplay world index to its `runtimeWorldData` path.

The release script refreshes generated recipe VMFs first, so changes to the base cell template are included in the compile. Pass `-SkipRecipeRefresh` only when the selected source recipes have already been deliberately refreshed.

The BSP names identify reusable recipes, not coordinates. The runtime index maps every logical cell coordinate to its selected BSP name and contains its navigation graph, environment, safe zone, landmark, metro, and atmosphere data. Build a map transition name from `world.mapDirectory .. "/" .. cell.map`, which defaults to `city/<recipe>`. Read the staged index in Garry's Mod with `file.Read("data_static/zombiesim_world.json", "GAME")` after it is packaged at the addon root.

## What Is Safe To Change?

Safe first experiments are:

- `mapGeneration.seed`
- Each profile's `gridCells`
- Road, bridge, blockade, and carpark chances
- Building-density values
- District names, positions, radii, and colours
- City-name word lists
- `cellPlanning.variants.usageThreshold` and `maximumPerRecipe`
- `atmosphere.profiles` fog and colour-correction values
- `atmosphere.lightingProfiles` light colours and brightness

Advanced settings control how prefabs connect or rotate. Change those only after checking the result in Hammer:

- `directions`
- `cellPlanning.topologyTemplates`
- `cellPlanning.transportTemplates`
- `cellPlanning.rotations`
- `cellPlanning.templatePatterns`
- `cellPlanning.filenameAbbreviations`
- `vmfBuild.tileSize`

## How Settings Are Chosen

The default values come from [generator-settings.json](generator-settings.json). A command-line value takes priority for that one command. For example:

```powershell
.\bin\generate_world_cells.ps1 -WorldProfile preview -Seed 9001 -RoadDepth 5
```

uses seed `9001` and road depth `5` once, even if the JSON file says something else. The next run returns to the JSON defaults.

## `schemaVersion`

`schemaVersion` identifies the format of the settings file. Use `2` for named world-generation profiles. The scripts also accept version `1` settings files, translating their city and preview values for compatibility, but new profiles require version `2`.

## `paths`

These are project-relative folders and files. Use forward slashes or backslashes consistently. Paths are relative to the project root, not the `bin` folder.

| Setting | What it controls | Notes |
| --- | --- | --- |
| `templateDirectory` | The root folder containing hand-authored tile VMFs. | Default: `tiletemplates`. Do not point this at generated cell VMFs. |
| `baseCellTemplate` | The border/base VMF inserted behind generated prefab instances. | Default: `celltemplates/template_border_s.vmf`. It must exist and contain a `cameras` block. |
| `scriptOutputDirectory` | Folder for PNG previews, JSON plans, required-VMF lists, and filename keys. | Default: `bin`. |
| `safeZoneTemplateDirectory` | Complete standalone den-map templates. | Default: `celltemplates/safezones`. These are copied as whole VMFs, not assembled from tiles. |

## `worldGeneration`

`defaultProfile` is used when a generator command has no `-WorldProfile` argument. Every entry in `profiles` is a complete, isolated generated-world configuration.

| Profile setting | What it controls |
| --- | --- |
| `filePrefix` | Prefix for the profile's generated map image, manifest, template plan, required-recipe list, and filename key. |
| `gridCells` | Width and height in logical cells. The future release `city` is 48-by-48 (2304 cells); `preview` remains 24-by-24. Existing production exports are not resized until an explicitly approved rebuild. |
| `exportLayers` | Whether generation writes separate terrain, roads, buildings, highways, landmarks, safe zones, metro, grid, labels, and key PNG layers. |
| `cellDirectory` | Generated VMF source folder for this profile. |
| `buildDirectory` | Intermediate compiler output folder for this profile. |
| `releaseMapDirectory` | Staging folder for the profile's compiled BSPs; its leaf directory becomes the runtime map directory. |
| `runtimeWorldData` | Compact gameplay world index. Package it under `data_static` and select the matching profile with `zn_world_profile`. |
| `overrides` | Optional partial generator settings that recursively merge over the shared settings for this profile. |
| `thumbnail` | Optional map-menu image definition for `build_launcher_thumbnails.ps1`. |

## `compilation`

These settings control the profile-driven VMF compiler runner. Command-line timeout/profile parameters override them for one command.

| Setting | What it controls | Notes |
| --- | --- | --- |
| `activeProfile` | Compiler profile used when `-CompilerProfile` is omitted. | Default: `stock-gmod`. |
| `progressRefreshMilliseconds` | How often the active-stage progress display refreshes. | Keep at least `100`. Default: `1000`. |
| `maxParallelProcesses` | Maximum number of compiler processes scheduled at once. | Default: `4`; override per run with `-MaxParallelProcesses`. Stock Hammer's `-threads` switch has no numeric limit, so the runner uses this process cap. |
| `stageTimeoutSeconds.vbsp`, `.vvis`, `.vrad` | Soft timeout budget for each compiler stage. | A stage is deferred after this budget while the remaining queue continues. Defaults: `300`, `900`, `1800`. |
| `deferredGraceSeconds` | Extra wait after the normal queue for deferred compiler processes. | Default: `300`. |
| `stagePresets.fast` / `.final` | VVIS and VRAD argument arrays used by the selected build preset. | Preview defaults to `fast`; `city` defaults to `final`. Use `-Fast` or `-Final` to override. |
| `profiles.<name>.toolDirectory` | Folder containing that profile's executables. | Empty for the stock Garry's Mod `bin`; otherwise absolute or project-relative. |
| `profiles.<name>.executables` | Names or absolute paths for `vbsp`, `vvis`, and `vrad`. | All three keys are required, including VBSP-only runs. |
| `profiles.<name>.arguments` | Argument-template arrays for `vbsp`, `vvis`, and `vrad`. | Use the supported placeholders shown above. |

Compiler invocations run through a bounded process pool (`maxParallelProcesses`, default `4`). The installed stock Hammer tools expose `-threads` as a valueless switch rather than a numeric thread limit, so the runner does not append an unsupported thread count; pool size is the supported concurrency control. Timed-out stages remain counted against the pool while their process is still running; completed/deferred stages are recorded in `compile-report.json`.

## `directions` (Advanced)

The generator treats roads as a north, east, south, west grid. These settings define the shared vocabulary used by map generation and cell planning. They are not cosmetic labels.

| Setting | What it controls | Editing advice |
| --- | --- | --- |
| `cardinal` | The four valid direction codes and their order. | Keep `N`, `E`, `S`, `W` in clockwise order. Reordering changes turning logic and can change a seeded city. |
| `names` | Long names used for cell orientation, such as `north-east` and `missing-west`. | Keep keys matched to `cardinal`; values must match the rotation and filename tables. |
| `opposites` | The direction at the far end of a connection. | Every pair must agree: `N` maps to `S`, `E` maps to `W`, and vice versa. A mistake creates disconnected roads. |
| `linearTileYaw` | Hammer yaw for straight road pieces running toward each direction. | Default is `0` for north/south and `90` for east/west. Confirm a different value visually in Hammer before keeping it. |

## `mapGeneration`

This section creates the city-wide map layout and its PNG preview. A map cell is one playable VMF recipe. The selected profile's `gridCells` is the number of cells across and down, not the number of 640-unit chunks inside a cell.

### Basic Size And Seed

| Setting | What it controls | Good values |
| --- | --- | --- |
| `cellSizePixels` | Size of one cell in the PNG planning image. | `64` gives a 1536-by-1536 image for a 24-by-24 preview. This affects the picture, not Hammer tile size. |
| `seed` | Default random seed. The same seed and the same settings create the same layout. | Any whole number. Prefer passing `-Seed` for a temporary test. |
| `landmarks.maximumPerCell` | Maximum named landmarks on an eligible city cell. | `4` is the current limit. Icons use a two-column grid and the map tooltip lists every landmark on the cell. Keep it between `1` and `4`. |

### `road`

Road settings determine how far the road network grows and how tangled it becomes.

| Setting | What it controls | Lower value | Higher value |
| --- | --- | --- | --- |
| `widthPixels` | Width of ordinary roads in the PNG preview. | Thinner map drawing. | Thicker map drawing. This does not change the Hammer road prefab. |
| `growthDepth` | Maximum recursive depth for side-road growth. | Smaller, simpler street network. | More branches and more intersections. Large values can make a very busy city. |
| `branchChance` | Chance from `0` to `1` that a growing road creates a side branch. | Fewer side roads. | More connected, denser streets. |
| `turnChance` | Chance from `0` to `1` that a growing road turns at a growth step. | Straighter suburban roads. | More corners and irregular blocks. |
| `minimumSegmentSteps` | Shortest number of cells a growing road continues before it may end or branch. | Short local roads. | Longer road runs. Must be smaller than `maximumSegmentStepsExclusive`. |
| `maximumSegmentStepsExclusive` | First length the random road segment will not use. | Shorter maximum road run. | Longer maximum road run. The actual maximum is this value minus one. |
| `deadEndRepairRadius` | Furthest search distance, in map cells, used to connect repairable dead ends. | Keeps more dead ends. | Repairs more dead ends into connected roads. |
| `centralSpineChance` | Chance from `0` to `1` for each regular position on the central arterial to grow a north/south branch. | A cleaner main road. | More districts linked to the main road. |
| `maximumJunctionDegree` | Most connections allowed at one ordinary-road cell, from `2` to `4`. | `3` prevents four-way cross junctions. | `4` allows full intersections. |

After generating local roads, the generator checks every district center for a route to the origin road network. An isolated district receives a direct ordinary-road connection that respects `maximumJunctionDegree` and avoids highway cells. This guarantee also applies when highways and metro are disabled.

Run `bin/analyze_world_reachability.ps1` after generating a matching manifest and template plan to audit the origin-connected road/highway graph, cells without external recipe entrances, unreachable settlements/landmarks, and the number of recipe BSPs used exclusively by disconnected or no-entrance cells. It writes a report under `generated/reachability`. The audit is diagnostic only: do not prune recipe BSPs while logical cells still reference them in the runtime index. A cell with a usable local entrance is not classified as a no-entrance dead cell merely because it is not in the origin road component.

`mapGeneration.safeZones.minimumSpacingCells` sets the preferred Euclidean spacing between den entrances. Placement considers only reachable local-road candidates, tries the most constrained districts first, and maximizes separation before district-center and supported-landmark preferences. If a district has no candidate at the target distance, it falls back to its best available reachable location; the manifest records the target, actual minimum separation, and per-district fallback status.

For `bridge-ramp-*` recipes, the center follows the cell's road topology; a straight road keeps a straight center rather than gaining unconnected cross-junction arms. The ramp occupies the first tile along the bridge direction, and bridge road continues beyond it rather than capping perpendicular ordinary-road approaches with deadends. Carpark bridge-ramp variants retain their separately-planned carpark junction. Run `bin/test_phase_c2_layouts.ps1 -WorldProfile preview` after planner changes; also inspect regenerated recipes and the developer zoo in Hammer before shipping a visual change.

### `highways`

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables the deterministic interstate grid, its crossings, bridges, and district ramps. Set `false` for a local-road-only profile. |

### `bridges` And `blockades`

| Setting | What it controls | Range and warning |
| --- | --- | --- |
| `bridges.chance` | Chance for an eligible interstate crossing to become a bridge. | `0` to `1`. Use small values; `0.04` already produces occasional bridges. |
| `bridges.deadEndChance` | Chance that an eligible road dead end near a highway becomes a bridge connection. | `0` to `1`. Raising it can make highway areas much more accessible. |
| `blockades.chance` | Chance for an eligible ordinary-road connection to be blocked. | `0` to `1`. High values can make the city feel fragmented. Highways are not chosen for this rule. |

### `terrain` (Advanced)

Terrain values decide whether a map cell becomes grassland, sandy, or dirt. The generator calculates a weight for each terrain type, adds deterministic noise, then picks the largest weight. These values affect district appearance and which planner decorations/buildings are preferred later.

| Setting | What it controls |
| --- | --- |
| `minimumWeight` | Lowest allowed terrain weight after calculations. Keep above `0`. |
| `grassBaseWeight`, `sandBaseWeight`, `dirtBaseWeight` | Starting preference for each terrain type. Larger means more common before location effects. |
| `grassYWeight` | Grass change from top to bottom of the map. A negative value means less grass farther south. |
| `grassWestWeight` | Extra grass toward the west (left) side. |
| `sandCenterWeight` | Extra sand near the horizontal center of the map. |
| `sandNorthWeight` | Extra sand toward the north (top) side. |
| `dirtYWeight` | Extra dirt farther south (down). |
| `dirtEastWeight` | Extra dirt toward the east (right) side. |
| `noiseXMultiplier`, `noiseYMultiplier` | Deterministic variation pattern across the map. These are pattern controls, not probabilities. |
| `noiseModulo` | Repetition length for terrain variation. Must be a positive whole number, never `0`. |
| `sandNoiseMultiplier`, `dirtNoiseBaseline`, `dirtNoiseMultiplier` | Fine controls for how the noise shifts sand and dirt. Leave these alone unless deliberately tuning biome distribution. |

The default terrain recipe makes grass more common to the west/north, dirt more common to the south/east, and sand more likely near the center/north. Extreme numbers can make one terrain dominate the whole city.

### `metro`

| Setting | What it controls | Editing advice |
| --- | --- | --- |
| `enabled` | Enables the guided metro routes and stops. | Set `false` for a profile with no metro system. |
| `minimumStationSpacing` | Minimum straight-line distance, in map cells, between metro stops. | `6` avoids crowded labels. Lower values create more nearby stops. |
| `routeStopInterval` | Number of route cells between automatically considered metro stops. | Higher values make lines have fewer stops. Keep it a positive whole number. |
| `stopSuffixes` | Words used to name minor metro stops. | Add or replace simple names. Empty lists are invalid because a stop needs a name. |

### `settlements` And `population`

| Setting | What it controls |
| --- | --- |
| `settlements.minimumDensity` | Baseline chance for an eligible roadside district cell to become settled in `random` mode. |
| `settlements.districtCenterDensity` | Additional settlement chance at a district center in `random` mode. |
| `settlements.placementMode` | `random` uses the density values above. `hash_modulo` selects a stable sparse scattering based on each cell's coordinates and seed. |
| `settlements.spacing` | In `hash_modulo` mode, selects roughly one eligible cell in this many cells. Must be at least `2`. |
| `population.base` | Starting population used in the generator overview. |
| `population.perBuildingCell` | Population added for every settled city cell. |
| `population.seedVariation` | Deterministic seed-based population variation. Set `0` to disable it. |
| `population.roundToNearest` | Rounds the generated population to this interval. Use `1` to avoid rounding. |

### `radiation`

Radiation is a deterministic, source-centered fallout field. The first detonation is placed at `epicenterXFraction` across the map and at a seed-selected Y coordinate within the configured range. Larger maps add more deterministically placed sources, subject to `additionalSourceEveryGridCells` and `maximumSources`. Intensity decreases linearly with radial distance until it reaches `0` at the fallout radius. The generator exports a transparent `radiation` PNG layer, and the runtime applies radiation damage outside standalone safe rooms.

Every source cell is a special `The Epicenter` landmark, marked with an `EPI` map key and an `epicenter` environment tag. Cells at or above `destroyedThreshold` receive the `destroyed` environment tag. The planner gives these cells a high building density and prefers templates matching `destroyedBuildings` when they are available; until then, it falls back to ordinary building templates.

`cellMiles` supplies a lore scale for the grid. The displayed yield equivalence uses $Y = (R / R_{1\,MT})^3$, where $R$ is `falloutRadiusCells * cellMiles` and $R_{1\,MT}$ is `loreReferenceFalloutMilesAtOneMegaton`. With the preview defaults, a 9-cell radius at 4 miles per cell is 36 miles and produces a `27 MT` equivalence. This is a configurable lore approximation, not a physical fallout prediction: real deposition also depends on burst height, weapon design, wind, weather, terrain, and time.

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables radiation intensity, the fallout overlay, and runtime damage data. |
| `epicenterXFraction` | Horizontal source location. `0.6` places the detonation three-fifths of the way east. Must be greater than `0` and less than `1`. |
| `epicenterYMinimumFraction`, `epicenterYMaximumFraction` | Inclusive vertical range used to choose the source from the seed. Both must be from `0` through `1` and ordered low to high. |
| `falloutRadiusCells` | Fixed fallout radius in grid cells. Intensity is `0` beyond this distance from each epicenter. |
| `additionalSourceEveryGridCells` | Adds one possible source for each complete interval of grid width after the first source. |
| `maximumSources` | Upper limit on the total number of detonation sources. |
| `cellMiles` | Lore distance represented by one grid cell. |
| `loreReferenceFalloutMilesAtOneMegaton` | Lore reference radius representing 1 MT in the yield-equivalence calculation. |
| `destroyedThreshold` | Radiation intensity from greater than `0` to `1` at which a cell receives the `destroyed` tag and destroyed-city planning. |
| `damagePerSecondAtPeak` | Exported peak-rate metadata. The current player-damage loop instead applies the discrete intervals documented in the readme. |
| `overlayMaximumAlpha` | Opacity from `0` to `255` used by every discrete radiation grid cell. |

The top-right HUD radiation meter maps normalized in-game cell intensity (`0` to `1`) to a fictional `0`–`10 Sv` baseline, plus up to `10 Sv` of radiated-walker proximity (maximum `20 Sv`, the full bar). Proximity uses the strongest living radiated walker within 600 units with quadratic distance falloff; groups do not stack. The compact meter hides when its combined displayed value rounds to zero; it is not physically calibrated and must not be interpreted as a real-world dose or dose rate. There is no separate proximity panel. The world-map cell inspector continues to show cell intensity alone as a percentage. At combined readings of 15 Sv or lower, runtime damage retains the cell-only exposure intervals and Strength health floor. Strictly above 15 Sv, it instead deals 1 HP every 2 seconds without a health floor and can kill. The wearable radiation suit blocks both radiation damage policies and radiation camera/postprocessing effects; merely carrying it provides no protection. Grayscale/contrast and camera tremor are extreme-only, independently reducible, and do not control server damage. Equipment, threshold, cell, and den changes reset the relevant exposure timer.

The HUD damage indicator is driven by the server's post-damage event and is sent only when damage was actually applied. It points toward a nearby attacker, inflictor, or reliable impact position, and scales briefly with damage; when no reliable horizontal source exists (including ordinary radiation ticks), a subtle screen-edge pulse communicates damage without inventing a direction. Feedback is bounded to six directional entries, merges repeated hits from the same nearby source, and is hidden while menus or safe zones are active. `zn_test_damage_feedback` checks source selection and damage scaling; directional presentation still requires in-game verification.

### `danger`

Danger is a generated scalar for enemy scaling, stored on every world cell alongside, but independent from, its environment tags and radiation level. It begins at world `(0,0)` and progresses in nested right-facing chevrons using $d=x+|y|$. Safe-zone cells always have danger `0`. The generator exports a transparent `danger` layer that colors each cell outline by its discrete danger tier, leaving the filled building square visible.

The generated value is clamped to $0 \leq D \leq 1$ and classified in the manifest as `safe`, `low`, `moderate`, `high`, or `extreme`. Runtime consumers can read it through `ZM_World:GetDangerIntensity(...)` or `ply:GetDangerIntensity()` and combine it with `ZM_World:GetEnvironment(...)` tags when selecting enemy types, counts, or modifiers. The HUD panel above the minimap and the world-map inspector show danger on a 0–6 star scale matching the six generated non-safe levels; safe cells have zero filled stars. Radiation is visualized separately in the top-right HUD meter as a fictional Sv estimate, in the inspector as a percentage of normalized game intensity, and in the map as discrete grid-cell fills with fixed contamination colors.

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables danger generation and the danger overlay. |
| `tierCount` | Number of discrete danger bands expanding from world origin `(0,0)`. Must be from `2` through `12`. |

### `airports`

Airports are deterministic `AIR` landmarks on reachable roads outside the radiation field. Normal map sizes receive exactly one airport. Larger maps can receive additional airports only after `additionalAirportEveryGridCells`, and each one must be at least `minimumSeparationCells` away from every other airport. The planner uses an ordinary fallback until a template matching `tile_airport*.vmf` exists.

| Setting | What it controls |
| --- | --- |
| `enabled` | Enables airport placement. |
| `additionalAirportEveryGridCells` | Grid-width interval required before another airport may be considered. |
| `maximumAirports` | Hard limit on airport count. |
| `minimumSeparationCells` | Required Euclidean distance between airports in grid cells. |

### `cityNaming`

`prefixes` and `suffixes` build the city name from the seed. Add words without spaces if you want a single-name city, or use spaces deliberately for a two-word result. Keep both lists non-empty.

### `districts`

Each item creates a named district. District locations are authored for the normal 64-by-64 layout and are scaled automatically for other city sizes.

| Field | What it controls |
| --- | --- |
| `name` | District name shown on the PNG and used by metro stop naming. Use a distinct, readable name. |
| `x`, `y` | District center on the 64-by-64 reference grid. `x` increases east/right; `y` increases south/down. |
| `radius` | District size in map cells before scaling. Larger districts influence a wider part of the city. |
| `color` | PNG overlay colour as `[alpha, red, green, blue]`. Each number is `0` to `255`; alpha is transparency, where `0` is invisible and `255` is solid. |

Avoid placing two district centers at exactly the same coordinates. Their names still work, but labels and district-based systems become harder to understand.

### `deadZones`

Each dead-zone item has `x`, `y`, and `radius`, using the same 64-by-64 reference grid as districts. Dead zones are scaled with city size. They prevent normal district activity in their area and help shape the hostile parts of the city. Keep radii positive.

### `rendering`

| Setting | What it controls |
| --- | --- |
| `biomeOpacity` | Transparency of terrain colour on the planning image, from `0` to `255`. It changes only the image, not the game world. |

## `cellPlanning`

This section turns the wide city map into a 5-by-5 grid of Hammer prefab instances for each unique cell recipe.

### Basic Cell Size

| Setting | What it controls | Important note |
| --- | --- | --- |
| `cellTileGridSize` | Number of prefab spaces across and down inside one generated cell. | Default `5` gives 25 prefab spaces. Use an odd number so roads have a true center tile. Changing it requires source border templates sized for the same layout. |

### `safeZones`

These settings choose the reusable standalone den map and the entrance instance in the safe-zone cell's city recipe.

| Setting | What it controls |
| --- | --- |
| `defaultTemplate` | Standalone den VMF used for the origin and whenever no configured landmark override matches. |
| `landmarkPriority` | Ordered landmark names checked for an override when more than one occurs in the cell. |
| `landmarkTemplates` | Optional mapping from landmark names to standalone den VMF filenames. An unmapped landmark uses `defaultTemplate`. |
| `entrance.template` | Authored 3x3 city entrance VMF, currently `safezones/entrance_safezone_3x.vmf`. |
| `entrance.footprint` | Width and height in tiles; currently `3`. The planner requires a 5x5 playable grid. |
| `entrance.origin` | Authored frontage reference: the source tile faces west at yaw 0 and must be rotated to face its adjacent road. |

The planner places an edge-centred entrance on a roadless side, or at a corner when all four sides carry roads, reserving its playable tiles before buildings and suppressing the covered border tiles. The Storm Drain's missing-west T-junction takes slot `W`, yaw `180`, facing east across the centre road tile. A conflicting road gate, water border, or carpark endcap rules out that slot. Different entrance placements change recipe identity. Confirm every den template exists in `celltemplates/safezones` and the entrance exists in `tiletemplates/safezones`, then refresh the preview plan and recipes before compiling. Inspect the resulting `func_instance` and border seal in Hammer; VMF and VBSP checks alone do not establish visual correctness.

### `templatePatterns` (Advanced)

These regular-expression filters decide which VMF files from `templateDirectory` are eligible for each role. Paths are relative to `tiletemplates`, use `/`, and matching is case-insensitive.

| Setting | Eligible files |
| --- | --- |
| `genericBuildings` | Ordinary building and construction assets. Special landmarks are intentionally excluded. |
| `destroyedBuildings` | Optional destroyed building assets, such as `buildings/tile_destroyed_*.vmf`. They are selected for `destroyed` fallout-core cells when at least one matching template exists. |
| `warehouses` | Warehouse assets usable by generic building selection. |
| `commercial` | Commercial assets. They are only allowed in commercial profiles or a Market landmark cell. |
| `industry` | Industry assets (`buildings/tile_industry_*` or `buildings/tile_industrial_*`). They are only allowed on dirt terrain or radioactive profiles. Each needs a `zn_tile_direction` frontage marker. |
| `decorations` | Decoration assets. Dirt and radioactive cells prefer these more often. |
| `carparks` | Carpark variants. They are only considered next to ordinary straight roads, not landmarks. |

Do not remove the `.vmf` ending. A pattern that matches nothing can leave a profile without the prefabs you expected. A pattern that is too broad can accidentally select unfinished or special assets.

### Templates Used By Terrain And Transport

`terrainTemplates` maps terrain names to their fallback VMF. `default` is used for any terrain name without its own entry.

`topologyTemplates` maps road and motorway shapes to their center VMF:

- `road-straight`, `road-corner`, `road-tjunction`, `road-crossjunction`, and `road-deadend`
- `motorway-straight`, `motorway-corner`, `motorway-tjunction`, `motorway-crossjunction`, and `motorway-deadend`

`transportTemplates` chooses special pieces for bridges and highway ramps:

| Setting | Use |
| --- | --- |
| `bridge-ramp` | Center of a road-to-bridge approach. |
| `bridge` | Motorway bridge crossing center. |
| `onramp` | Single motorway ramp center. |
| `onramp-dual` | Motorway ramp center with two exits. |
| `bridgeRoad` | Road continuation across the bridge deck. |
| `roadDeadEnd` | Ground-side cap for a bridge approach. |

Every referenced VMF must exist below `tiletemplates`. Do not rotate source VMFs to fix a generated placement. Correct the matching yaw setting after checking the canonical prefab in Hammer.

The active motorway topology and motorway bridge/ramp settings reference the
approved wide sources under `roads/motorway_3x1`. Retained files under
`roads/motorway_1x1` are for isolated legacy inspection only; they are not
fallbacks for current motorway topology. The current wide-source inventory has
no footprint-compatible straight visual variants, so the active
`topologyVariants.templates` pool contains ordinary-road variants only.
Planning validates required motorway keys and explicit tile-template paths
before placing anything. A missing motorway source is an error, never terrain.

### `rotations` (Advanced)

All values are Hammer yaw angles in degrees. The generator rotates the generated `func_instance`, not the source tile VMF.

| Group | Meaning |
| --- | --- |
| `layout.road-deadend` | Yaw for a road dead end that opens toward each named direction. |
| `layout.motorway-deadend` | Equivalent yaw table for motorway dead ends. It is separate because the asset family may later use a different canonical orientation. |
| `layout.straight` | Yaw for vertical and horizontal straight roads. |
| `layout.corner` | Yaw for each two-direction road corner. |
| `layout.tjunction` | Yaw keyed by the missing direction of a T-junction. |
| `transport.bridge-vertical` and `transport.bridge-horizontal` | Center yaws for motorway bridge crossings. |
| `transport.bridgeRampByDirection` | Yaw for road ramps that face the bridge direction. |
| `transport.onrampByDirection` | Yaw for motorway on-ramps whose authored north-edge road connects toward each direction. |
| `transport.onrampRoadByDirection` | Yaw for the `tile_road_onramp` approach tile (city road on local south, ramp lanes on local north), so its ramp edge faces the motorway on-ramp opening. Always `onrampByDirection` + 180. |

Use only `0`, `90`, `180`, or `270` for the current square tiles. Test any change in a preview VMF in Hammer. A wrong yaw can make an apparently valid road point into a building or a cell border.

### `environment`

`profilePriority` decides which special identity a cell gets when it has more than one environment tag. The first matching item wins. For example, with the default order, `destroyed` wins over `radioactive` and `commercial` when a cell lies in the fallout core. Moving an item higher makes it override the entries below it.

`buildingDensity` is the chance from `0` to `1` that an eligible empty prefab space receives a building or decoration.

| Setting | Default effect |
| --- | --- |
| `grassland`, `sandy`, `dirt` | Density for those plain terrain profiles. |
| `parkland`, `recreation`, `settlement` | Density for these named profiles. Settlement is intentionally the densest listed profile. |
| `fallbackByTerrain` | Density for profiles without their own density entry, based on the terrain below them. `default` is the final fallback. |

`densityTiers` controls building height preference, not how many buildings appear. Tags in `highTags`, `mediumTags`, and `lowTags` override profile defaults. Then `highProfiles` produces tier 3, `mediumProfiles` produces tier 2, and all other profiles produce tier 1.

### `buildingSelection`

| Setting | What it controls |
| --- | --- |
| `maximumHeightTier` | Highest filename-derived building-height tier the weighting system considers. |
| `skyscraperCenterPercent` | Share of eligible automatic multi-tile building selection attempts preferring skyscrapers at the geometric world center (`40`). |
| `skyscraperEdgePercent` | Skyscraper selection share at any outer world edge (`5`). The center-to-edge taper uses smoothstep over normalized Chebyshev distance and rounds to whole percentages for deterministic selection. Must be between zero and the center percentage. |
| `minimumWeight` | Minimum chance weight for an allowed building asset. Keep at least `1`. |
| `baseWeight` | Starting preference for a building whose height matches the cell density tier. |
| `heightDistanceWeight` | How quickly preference drops when building height differs from the cell density tier. Higher numbers make districts specialize more strongly by height. |
| `commercialProfiles` | Profiles allowed to use commercial building assets, in addition to Market landmark cells. |
| `industryTerrains` | Terrain types allowed to use industry assets. |
| `industryProfiles` | Special profiles allowed to use industry assets. |

Army Base landmark cells use only VMFs under `tiletemplates/army` for fallback building slots, in addition to the Army-only landmark template. Military-profile cells use the same exclusive pool. If the Army folder has no VMFs, planning fails explicitly rather than falling back to generic buildings.

Building height is inferred from the letter count after the number in names such as `tile_building_1a.vmf`, `tile_building_1aa.vmf`, and `tile_building_1aaa.vmf`. Keep that naming convention for new ordinary building prefabs.

`tile_skyscraper_*_2x` templates are ordinary 2x2 buildings, not landmarks. Their center-to-edge selection uses a separate deterministic hash after the existing automatic multi-tile placement chance. The selected tower family retains district height preference and falls back to ordinary multi-tile candidates if its footprint cannot fit. Existing landmarks, forced fixtures, destroyed-only pools and placement exclusions remain authoritative. The percentages describe preferred macro selection attempts, not all buildings or terrain tiles; measure successful placements separately. Selection percentages and preference results do not enter recipe identity: the existing macro key records the realized template, footprint, anchor and rotation. Variant generation refreshes this key after placement so different actual tower layouts cannot share a BSP. Omitting both percentage settings disables automatic skyscraper selection. Report the unique required BSP count and time impact before broad compilation, and obtain approval for a material increase.

Run `.\bin\test_skyscraper_selection.ps1` for focused centrality, frequency, classification, height-weighting and recipe-identity checks. Pass `-PlanPath <preview-plan.json>` to additionally verify realized central-versus-outer tower concentration and shared-recipe consistency. Run `.\bin\test_building_frontage.ps1` and `.\bin\test_multi_tile_templates.ps1` for the placement paths affected by changing this building pool.

### `decorations` And `carparks`

| Setting | What it controls |
| --- | --- |
| `decorations.preferredTerrains` | Terrain types that prefer decoration placement over normal building placement. |
| `decorations.preferredProfiles` | Profiles with the same decoration preference. |
| `preferredChancePercent` | Decoration chance from `0` to `100` in preferred terrain/profile areas. |
| `standardChancePercent` | Decoration chance from `0` to `100` elsewhere. |
| `carparks.roadStraightChancePercent` | Optional extra chance from `0` to `100` that an eligible non-landmark straight-road recipe gets a carpark after coverage selection. Keep it at `0` for the most even distribution. |
| `carparks.coverageCellSpan` | World-grid width and height of each coverage region. The planner reserves carparks across each region in separate passes, preferring straight roads and using junctions only when needed. Junction carparks branch from a spare internal road arm and keep the central road exits intact. Keep it at least `1`; the current `3` spreads coverage more evenly than the former 4-cell regions. |
| `carparks.coverageCarparksPerRegion` | Number of eligible cells reserved per coverage region. The current value is `3`; selection is separation-aware, so a road-poor region can contribute fewer rather than cluster adjacent carparks. Keep it at least `1`. |
| `carparks.minimumCellSeparation` | Minimum Chebyshev distance between forced carpark cell coordinates. The current value is `2`, preventing side-by-side and diagonal carpark cells. Keep it at least `1`. |
| `carparks.minimumLaneTiles` | Minimum straight-tile length for each enabled carpark lane. The current value is `2`, so ordinary straight-road carparks use their full available lane length. Keep it at least `1`. |
| `carparks.maximumLaneTiles` | Maximum straight-tile length for each enabled carpark lane. It must be at least the minimum and no greater than the available distance to the cell edge. |

Carparks only replace an eligible building space beside a road. They do not overwrite roads, ramps, bridges, or landmarks. Before recipes are built, the planner makes separate world-wide coverage passes and reserves up to `coverageCarparksPerRegion` eligible cells per `coverageCellSpan` region. It rejects candidates closer than `minimumCellSeparation` under Chebyshev grid distance and prefers full straight-road layouts before compact junction sidecars. Forced straight-road coverage uses a through entrance and two full-length arms so it reads as a long carpark on the satellite. A junction carpark replaces an internal road-arm tile with a T-junction and occupies only adjacent free tiles, leaving the center intersection intact. Its one-sided lane is one tile long so it can terminate at the cell edge without cutting a perpendicular road. Reserved recipes use a stable `-cp.vmf` basename and the plan records each selected coordinate in `carparkCoverage`; planning fails if any reserved cell lacks a carpark entrance. The selected entrance layout and its lane length are deterministic for a recipe: through entrances create two arms, `_deadend_east` and `_deadend_west` create one, and the unsuffixed `_deadend` entrance creates no arms.

### `openTerrain` And `topologyVariants`

| Setting | What it controls |
| --- | --- |
| `openTerrain.maximumOpenTilePercent` | Highest share of a cell's 25 tiles that may stay plain `terrain` fill. After all other placement, the planner turns the excess into decoration templates in a seed-hashed order and skips tiles that a 1x1 building's frontage faces. The current `16` keeps every preview recipe at or below 4 open tiles (the Phase E target is a mean of 18% or lower and no recipe above 32%). |
| `topologyVariants.chancePercent` | Chance from `0` to `100` that an eligible plain straight road or motorway tile with a configured variant pool becomes an authored visual variant. Eligible tiles have role `road` and exactly the `road-straight` or `motorway-straight` template; ramps, bridges, junctions, gates, carparks and border tiles are never swapped. |
| `topologyVariants.templates` | Optional variant pools keyed by `road-straight` or `motorway-straight`. Each variant must keep the base piece's footprint, brushes and connections. The current active pool contains ordinary-road variants; add a motorway pool only when approved alternatives match the wide source footprint. Selection uses the cell seed and tile coordinates, so a stable seed gives the same plan. |

`bin/test_phase_e_layouts.ps1` checks these limits, the industrial selection, the variant share, orphan `.vmx` files, and, with `-Replan`, that re-planning gives the same plan.

### `variants`

Variants prevent a highly repeated recipe from making every intersection look identical.

| Setting | What it controls |
| --- | --- |
| `usageThreshold` | Default `15`. Frequently reused recipes receive `ceil(uses / usageThreshold)` layouts, up to the cap below. With neighbour avoidance enabled, less-used recipes retain their base layout and try alternatives only when an actual adjacent-layout conflict requires one. |
| `maximumPerRecipe` | Maximum candidate layouts per repeated base recipe. Default `4`. Frequent recipes prefer the least-used compatible variant; less-used recipes prefer their base layout so distant cells can reuse maps. Neighbourhood constraints take priority over perfectly even use. |
| `avoidAdjacentDuplicates` | Default `true`. Compare actual emitted tile layouts against all four cardinal neighbours, not just map filenames. Try another candidate when a layout repeats. If every candidate repeats, choose the fewest conflicts and emit an explicit warning: a limited authored pool cannot guarantee unlimited distinct geometry. |
| `suffix` | Letter before the variation number in filenames (up to `-v4`; retained base layouts have no variant suffix). Keep `x` free for the future `_2x` prefab-footprint convention. |

Variants preserve road topology and transport pieces. They vary non-transport placement choices such as buildings and decorations. They are deterministic: the same city seed and settings produce the same variant assignments.

With neighbour avoidance enabled, the final recipe hash includes its emitted
tile layout and placement seed. Different terrain-dependent building choices
must not accidentally share one BSP just because their coarse topology/profile
codes match. Context splits can therefore produce more unique BSPs than the
candidate variant count alone suggests.

`bin/test_cell_variants.ps1 -PlanData <plan> -BaselinePlanData <previous-plan>`
checks real layout differences at every adjacent pair and unchanged logical
connections, transport metadata and safe-zone footprints. Optional
`-LayoutDirectory <generated-src>` checks generated border/outer placements too.

### `landmarkTemplatePatterns`

This table maps landmark names produced by the map generator to VMF file patterns. The key must remain the landmark's exact display name, including spaces and capitalization, such as `Petrol Station` or `Army Base`.

If a landmark has no matching VMF, the planner uses the normal compatible layout instead. `Market` has a special fallback to the first eligible commercial template.

Policy-v1 generation keeps the landmark's selected footprint family and uses
hard density selection within its authored pool. Physical landmarks are
density-exempt fixed features: they are never moved to satisfy density. When a
named landmark's pool cannot serve every density target the cell can receive,
the generator leaves the identity, cell, labels and safe-zone inputs unchanged
and records a report-only shortage in `generation.landmarkDensityShortages`
(identity/label, cell, zone tier/source, required target tiers, available
template tags, footprint, `moved=false` and reason
`density_exempt_fixed_landmark`). The planner then keeps the landmark's legacy
first template, records placement status `density_exempt_landmark` and emits a
`[Planner][Density]` warning. Ordinary scenery remains under hard density.

### `filenameAbbreviations` (Advanced)

These tables shorten recipe filenames so they remain readable and practical in Garry's Mod map folders. They affect generated recipe filenames, the required-VMF list, and the filename key.

| Group | Example |
| --- | --- |
| `environmentProfiles` | `settlement` becomes `st`. |
| `topologies` | `road-crossjunction` becomes `rx`. |
| `orientations` | `missing-north` becomes `mn`. |
| `transportFeatures` | A bridge or on-ramp receives a compact transport segment. |
| `landmarks` | `petrol-station` becomes `ps`. |

`format` is the literal filename pattern: `zz_<worldProfile>_<environment>_<topology>-<orientation>[-<transport>]-d<density>_<landmarks>.vmf`. The `zz_<worldProfile>_` prefix is reserved for profile-specific generated recipe maps; standalone safe rooms use `zz_<worldProfile>_den_…`. The bracketed transport segment is removed when a cell has no bridge or ramp feature. Macro layouts append `-m<width><height>-<template>-p<x>-<y>-q<quarter-turn>`; for example, `m22-c2a-p0-3-q0` means the `commercial_2a` 2x2 prefab anchored at `(0,3)` with zero rotation. Keep every code short, lowercase, and unique within its group. Changing this pattern or its abbreviations changes VMF names; rebuild and update any compile or map-loading references afterwards.

### Complete Filename Reference

This is the complete current set of keys in `filenameAbbreviations`. The names on the left are generator values; the short forms on the right are the text placed in recipe filenames.

| Environment profile | Filename code | Environment profile | Filename code |
| --- | --- | --- | --- |
| `grassland` | `gr` | `sandy` | `sa` |
| `dirt` | `di` | `settlement` | `st` |
| `commercial` | `co` | `financial` | `fi` |
| `radioactive` | `ra` | `safe_zone` | `sz` |
| `fortified` | `fo` | `military` | `mi` |
| `medical` | `md` | `emergency_services` | `es` |
| `religious` | `rl` | `service_station` | `ss` |
| `recreation` | `rc` | `parkland` | `pk` |

| Topology | Filename code | Topology | Filename code |
| --- | --- | --- | --- |
| `open` | `o` | `road-straight` | `rs` |
| `road-corner` | `rc` | `road-tjunction` | `rt` |
| `road-crossjunction` | `rx` | `road-deadend` | `rd` |
| `road-isolated` | `ri` | `motorway-straight` | `ms` |
| `motorway-corner` | `mc` | `motorway-tjunction` | `mt` |
| `motorway-crossjunction` | `mx` | `motorway-deadend` | `md` |
| `motorway-isolated` | `mi` |  |  |

`road-isolated` and `motorway-isolated` are reserved names for a road/highway record with no live connections. They do not have center-template entries because there is no road surface to draw; the planner falls back to compatible terrain/building placement.

| Orientation | Filename code | Orientation | Filename code |
| --- | --- | --- | --- |
| `none` | `n` | `all` | `a` |
| `vertical` | `v` | `horizontal` | `h` |
| `north` | `n` | `east` | `e` |
| `south` | `s` | `west` | `w` |
| `north-east` | `ne` | `east-south` | `es` |
| `south-west` | `sw` | `north-west` | `nw` |
| `missing-north` | `mn` | `missing-east` | `me` |
| `missing-south` | `ms` | `missing-west` | `mw` |

| Landmark | Filename code | Landmark | Filename code |
| --- | --- | --- | --- |
| `none` | `n` | `church` | `ch` |
| `hospital` | `ho` | `police` | `po` |
| `fire` | `fi` | `petrol-station` | `ps` |
| `bank` | `ba` | `army-base` | `ab` |
| `laboratory` | `la` | `bunker` | `bu` |
| `market` | `ma` | `leisure` | `le` |
| `park` | `pk` |  |  |

| Transport key | Configured filename code | How the placeholder is filled |
| --- | --- | --- |
| `none` | empty | No transport filename segment is written. |
| `bridge-vertical` | `bv` | Written directly. |
| `bridge-horizontal` | `bh` | Written directly. |
| `bridge-ramp` | `br<direction>` | `<direction>` becomes the lower-case bridge direction, such as `brn`. |
| `onramp` | `o<direction>` | `<direction>` becomes the lower-case exit direction, such as `oe`. |
| `onramp-dual` | `od<directions>` | `<directions>` becomes both lower-case exits, such as `odns`. |

The exact display-name keys in `landmarkTemplatePatterns` are `Church`, `Hospital`, `Police`, `Fire`, `Petrol Station`, `Bank`, `Army Base`, `Laboratory`, `Bunker`, and `Market`. Each value is a file-search pattern for that landmark's authored VMF. Keep the capitalization and spacing of the key unchanged.

## `atmosphere`

Atmosphere has two layers. `profiles` is client-side fog and colour correction exported with runtime world data, so it can vary by the player's logical cell without recompiling a reusable BSP. `lightingProfiles` is baked into recipe VMFs for VRAD, so changing it requires a VMF refresh and map compile. The generator keeps the sun direction from the base cell template; only sky material, direct light, and ambient fill vary.

The exporter selects `safe_zone` for safe-zone entrances, `dead_zone` for dead zones, `inner_city` for commercial/financial recipes, `outskirts` for grassland/sandy terrain, and `suburbs` otherwise. These five profile ids are required and must remain exactly named as shown, but their values are intended to be tuned.

### `profiles`

Each item is a named client runtime profile. The profile array is compactly indexed in the exported world JSON, so preserve profile order when possible to keep output diffs understandable.

| Setting | What it controls | Tuning guidance |
| --- | --- | --- |
| `id` | Stable profile identifier used by the exporter. | Keep the five required ids: `outskirts`, `suburbs`, `inner_city`, `dead_zone`, and `safe_zone`. |
| `fog.color` | RGB fog colour as `[red, green, blue]`. | Each value is `0` through `255`. Match it broadly to the selected sky. |
| `fog.start` | Distance in Hammer units at which fog starts. | Lower values make nearby streets haze sooner. Keep it below `fog.end`. |
| `fog.end` | Distance in Hammer units at which full fog range is reached. | Keep enough visibility to read road exits and fight fairly. |
| `fog.maxDensity` | Maximum linear-fog density. | `0` is transparent and `1` is fully opaque. Typical values are `0.5` through `0.9`. |
| `fog.stormMultiplier` | Visibility multiplier at full future storm intensity. | Greater than `0` and at most `1`; lower values make storms shorten fog distances more. |
| `colorCorrection.brightness` | Additive client brightness adjustment. | Small changes such as `-0.05` to `0.05` are normally sufficient. |
| `colorCorrection.contrast` | Client contrast multiplier. | `1` is neutral. |
| `colorCorrection.colour` | Client colour saturation multiplier. | `1` is neutral; lower values desaturate the scene. |
| `colorCorrection.add` | RGB additive colour correction as three decimal values. | Keep values small; this is a tint, not a light source. |
| `colorCorrection.multiply` | RGB multiplicative colour correction as three decimal values. | `1, 1, 1` is neutral. Use restrained channel changes for temperature or contamination mood. |

Changing a fog or colour-correction value requires only a runtime-world export:

```powershell
.\bin\export_runtime_world_data.ps1
```

Run the matching `-WorldProfile` export for alternate profiles. Test through normal map travel because fog is applied for each player from the profile of their persisted logical cell.

### `lightingProfiles`

Each named baked-lighting profile supplies the values written into a generated recipe's `worldspawn` and `light_environment` entity.

| Setting | What it controls | Tuning guidance |
| --- | --- | --- |
| `<profile>.skyname` | Source sky material name written to `worldspawn`. | Use a skybox available in Garry's Mod. The default profile names are known Source sky materials. |
| `<profile>.ambient` | `light_environment` ambient RGBA colour as `[red, green, blue, brightness]`. | RGB values are `0` through `255`; tune brightness before making large hue changes. |
| `<profile>.light` | `light_environment` direct sun RGBA colour as `[red, green, blue, brightness]`. | RGB values are `0` through `255`. Keep the base-template sun pitch/yaw unchanged across profiles. |

### `environmentLightingProfiles`

This table maps each planned recipe environment profile to a named item in `lightingProfiles`; `default` handles every environment not explicitly listed. The default mappings give commercial/financial recipes `overcast_day`, sandy/dirt recipes `dusty_day`, and radioactive/destroyed recipes `dead_zone` lighting. Every mapped value must be a key in `lightingProfiles`.

After changing a baked-lighting value or mapping, regenerate the active source VMFs and compile the affected release. `build_city.ps1` performs the refresh automatically unless `-SkipRecipeRefresh` is supplied.

```powershell
.\bin\build_cell_vmfs.ps1 -RefreshGenerated
.\bin\build_city.ps1 -CleanStagedCity
```

Generated recipes receive one to three deterministic `env_cubemap` entities. After a light, sky, fog, or geometry change is compiled, launch representative maps and run `buildcubemaps`; that in-game capture step is separate from VBSP, VVIS, and VRAD.

## `vmfBuild`

| Setting | What it controls | Warning |
| --- | --- | --- |
| `tileSize` | Distance in Hammer units between the centers of neighbouring tile instances. | Default `640` must match the physical width of normal tiletemplate VMFs. Do not use this to correct a misplaced model inside a source prefab. |
| `tileZOffset` | Vertical offset, in Hammer units, applied to every generated tile instance. | Default `0`. A non-zero value moves all generated chunks up or down together. |
| `skybox3d` | Runtime 3D skybox. With `enabled: true`, `build_cell_vmfs.ps1` writes one shared room (`generated/skybox_<profile>/skybox_room.vmf`: a sealed TOOLSSKYBOX shell, a seabed ground brush at `cameraZ - 24`, and a `sky_camera`) and instances it into every city recipe as `zm_skybox_room`. Dens, safe-zone maps, and launchers do not get it. The settings are `enabled`; `scale` (sky_camera scale, `16`); `neighbourRadius` (how many cells out are modelled); `cameraZ` and `roomHeight` (the room above the playable cell box); `minBrushExtent` (brushes smaller than this are culled); `maxPartVertices` and `maxPartMaterials` (limits for splitting a model into parts; at most 60 materials per part); and `groundMaterial`. Snow overlay settings: `snowOverlay` (build per-recipe `<recipe>_s<N>` snow models), `snowMinNormalZ` (minimum face normal z for snow, `0.7`), `snowLift` (world units the snow is raised, `2`; larger lifts show as a slab at the cell edge), and `snowTextureWorldSize` (planar UV tile size, `256`). Set dressing settings: `detailProps` (emit the manifest `detail` table), `detailPropPattern` and `detailVehiclePattern` (model regexes for authored tile props and vehicles), `roadCarMaterial` (lane surface for generated wrecks, `CONCRETE/CONCRETEFLOOR037A`), `roadCarModels`, `roadCarSpacing` (`320`), `roadCarChance` (`0.35`), and `roofFireMinHeight` (lowest rooftop that can burn, `192`). | Build the models with `bin/build_skybox_models.ps1 -WorldProfile <profile>` after the recipe VMFs exist. It converts each unique recipe's brushes and displacements (not tile props) into models under `content/models/zombiesim/skybox/cells`, with wrapper VMTs in `content/materials/models/zombiesim/skybox`. It also writes the runtime manifest `content/data_static/zombiesim_skybox_<profile>.json`. `gamemode/cl_skybox.lua` draws the current cell's neighbours from that manifest in the 3D sky pass. Out-of-grid slots become a client-drawn coast: sea, sea wall, and foam. The snow models fade in with `ZM_Atmosphere.SnowCoverAmount` and draw with a small `render.DepthRange` bias. Skybox models are lit from the playable cell's lighting (`render.ComputeLighting` sampled on a ring near the cell edge) so the seam matches the lightmapped map; client convars `zombiesim_sky_matched_lighting` (default 1) and `zombiesim_sky_light_scale` (default 0.2) control this. Set dressing (authored props, generated road wrecks, and fire candidates) is drawn through one shared scaled model per prop type, within a per-frame draw budget scaled by `zombiesim_sky_props`; `zombiesim_sky_fires` toggles burning wrecks and rooftops with smoke plumes. Both are part of the quality presets. The module also draws a fog-coloured horizon wall and weather-driven clouds, and grades skybox fog so it is opaque at the wall. Every vertical room plane lies on VBSP's 1024-unit block grid so the room does not split the playable cell's leaves. Compilers find the models through the `_compile_game` overlay that `compile_cell_vmfs.ps1` writes; its mount.cfg adds `content`. |

### Alpha 3.1.5 outer edges (gated)

`vmfBuild.outerEdges.enabled` is currently false for ordinary builds. Isolated
preview fixtures enable it through a separate `-SettingsPath`; do not enable
it globally or promote city outputs before the milestone approval gates.
`wallVariationTemplates` and `cornerTemplate` define the default pieces.
`profileTemplates` independently replaces each piece kind: radioactive uses
`ra`; military/fortified use `army`; a missing tagged corner falls back to the
default corner. `_none` is an authored tile, not an omission.

The 5x5 core stays at +/-1600, the existing traversable border envelope at
+/-2240, and the new inaccessible scenery perimeter at tile coordinates -2..6,
nominally +/-2880. The visual neighbour pitch is 5760, but Phase B must regenerate
and wire matching skyline assets before rollout; Phase A does not change the
installed skyline. Outer fill is omitted only on the west 3D-skybox ocean
boundary (`x = 0`), including its NW/SW outer corners. The planner's
`skyboxOceanSides` is deliberately separate from `waterBorderSides`: the latter
continues selecting the previously authored border/water-corner tiles, unchanged.
Only reserved centre road/bridge corridors may continue on omitted sides.
Safe-zone suppression takes precedence.

Both border and outer straight-wall pools exclude terminal `_1aaa`/`_2aaa`
(and other numeric `aaa`) pieces in slots immediately cardinal-adjacent to a
road, motorway or bridge corridor. `a`/`aa`, diagonals, distant wall slots,
corners, water pieces and road sources are unchanged. Selection remains
deterministic; an adjacent pool containing only `aaa` fails explicitly.

Corridor adjacency uses the complete occupied route footprint
(`Get-ZMRouteFootprintSlots` in `bin/outer_edges.psm1`): every `roads/`
placement expanded across its emitting footprint, non-emitting occupied
records, `motorway_assembly`/`motorway_occupied`/`motorway_external_occupied`
roles and motorway inspection leases (core/border leases for the border ring,
border/outer leases for the outer ring), plus edge-connection and outer
continuation slots. Carpark lanes, entrances and endcaps are not corridors.

Authored north-facing straights use inward N180/E90/S0/W270. The separately
inspected NW-opening corner uses NW180/NE90/SE0/SW270. Do not rotate or trim
the source VMFs. The generator widens only the recognised source base shell:
land-facing sky seals at +/-3072 contain the approved brush overhangs; perimeter
clips begin at +/-2240 and stop access to scenery. On skybox-ocean sides, the
sky seal and black sealing floor retain the original 2240 boundary instead of
expanding into the rendered beach/ocean. The original shell ceiling is retained.
Phase C source generation places expanded road gates32 units inside this border
boundary (+/-2208), with corresponding inward arrival landmarks. Legacy ground
gate coordinates are retained. `bin/transition_gates.psm1` measures the continuous
central road deck from authored face windings: bridge196 versus ordinary road36
produces a160-unit lift for the trigger, barricades and arrival. Unsupported
source geometry fails explicitly. Expanded border gate slots use ordinary road
continuations instead of the old blocking transition-road variants; elevated
bridge corridors retain their bridge source. This is isolated source/structural
validation, not permission to stage a partial Phase C runtime closure. Ground
arrows and integrated travel acceptance remain Phase C work.

Expanded recipe names use the normal recipe hash without a test-only
`-edge2` revision suffix. West-ocean recipes retain the `-oceanw` distinction
so they cannot reuse inland scenery. When enabling or changing outer-edge
geometry, regenerate the plan and VMFs and rebuild every required preview BSP;
filename suffixes are not a substitute for compiling the current geometry.
The builder writes a sibling `.layout.json` containing core, original border
and outer placements, coast sides, bounds and the exact VMF hash.
Artwork/skyline consumers should use that generated metadata rather than
reconstructing a separate border policy. Expanded runtime exports require
matching generated layouts; legacy exports without bounds remain supported.
Expanded skyline manifests use schema 2 with shared `cellBounds`, the exact
`templatePlanSha256` and per-recipe `geometry` (VMF hash, water sides, coast and
visual extents). Legacy skyline schema 1 remains valid for legacy worlds only.
The client and package builder reject mixed revisions and mismatched coast/
plan metadata. The sky-room writer uses the same neighbour pitch as the model
builder. No expanded assets are installed merely by passing isolated checks.

The Storm Drain at grid `(0,12)` (logical `(0,0)`) keeps its original 21 border
pieces and west entrance suppression. Its new western edge layer is omitted,
not its old border. The renderer's west land rectangle ends at `x = -2240`
world units relative to the cell centre, not `-2880`. The additional 640-unit
band joins that border to the adjacent skybox ocean; no exposed gap is intended.
The physical west sky wall and floor must also stop at `x = -2240`: renderer
coordinates alone cannot conceal an expanded black floor. Inland sides retain
their 3072 shell clearance, and original border/core instances remain unchanged.

On omitted sides the client retains the original procedural beach beyond 2240
(explicitly approved 2026-10-06), with water filling the remaining space.
Full sea slots and omitted bands share sample cuts to avoid corner T-junctions;
sea height, beach width, foam and wall materials remain unchanged. Fog starts
its continuation at 2240, and lighting samples stay within the traversal
envelope rather than growing their count with the scenery ring.

Run `.\bin\test_skybox_edges.ps1 -BuildModels` for isolated source-transform,
snow/tower, dependency-hash, companion-cache and compiled-manifest checks.
It writes only under `generated\skybox_edges`. The source directory supplied
to `check_vis_budgets.ps1` is also forwarded to the compiler, so an isolated
portal refresh does not accidentally compile the normal profile directory.
`zn_test_skybox_geometry` runs the shared compatibility/cardinal/mixed-corner
mesh-cut suite without moving a player or changing live state.

`ZM_World:GetCellBounds()` exposes core/traversal/visual/pitch/coast/ceiling
values; `IsCoreSpawnPosition(position)` excludes border, scenery and sky-room
spawn candidates without trimming pursuit navigation. `GetCellSideExtent(cell,
side)` retains coast contact at 2240 on water-facing sides. Legacy searchable
prop behaviour stays unchanged until expanded-cell metadata is loaded.

Fifteen VBSP-incompatible trees/signs in four new tagged edge assets use
`prop_dynamic_override` instead of `prop_static`, preserving all other source
bytes. The user approved this fixed-dynamic correction. See the
[archived VDC documentation](https://web.archive.org/web/20241130040812/https://developer.valvesoftware.com/wiki/Prop_dynamic_override)
and [SDK props.cpp at b8cfb12](https://github.com/ValveSoftware/source-sdk-2013/blob/b8cfb12c0e083a2ef5b2f9f9b50f3902fa034474/src/game/server/props.cpp#L1988).
The live VDC pages were inaccessible. SDK evidence is not the exact GMod branch;
compiled BSP retention is verified, while actual appearance/collision and
representative performance still need client review.

### Tall Building Clearance

The authored city shell has a 4608-unit inner sky ceiling and a 4672-unit outer top, fitting the current 4384-unit skyscraper. The shared sky room uses `cameraZ = 5120`; its lowest outer brush plane is 5040, separate from the playable shell. The VMF builder measures the chosen base template's maximum brush-plane Z rather than assuming an old fixed shell height, and rejects sky-room overlap.

City map captures use the loaded skybox manifest's playable ceiling (`cameraZ - 128`, currently 4992), not a fixed 3600-unit camera below the tallest roof. Maps without a matching skybox manifest retain the existing fallback height. Source changes require rebuilding affected maps and their matching skybox manifest together before staging; do not pair a new manifest with old city BSPs.

Run `.\bin\test_skyscraper_height.ps1 -Compile` to generate isolated fixtures for all three tower variants and run VBSP under `generated/skyscraper_height`. This checks source/room/capture clearance and structural compilation, not visual placement, skyline cost or final lighting. Run the visibility-budget check against that exact fixture plan/list/source/build directory before a full lighting compile.

The skybox model builder also exports optional `towers` entries: `<recipe>_t<N>` models containing only authored `tile_skyscraper_*_2x` instances, with the same scaled placement, material mapping and UVs as the full recipe. These have independent build stamps and exclude ordinary terrain/roads and set dressing. `towerParts` and `towerTriangles` in the model report describe their geometry cost. Run `.\bin\test_skybox_towers.ps1` to verify tower-only extraction, exact transform/UV preservation, and empty-recipe handling.

`skybox3d.skylineRadius` (24 cells) controls tower-only coverage independently of the detailed `neighbourRadius` (2). The room expands on the same 1024-unit block grid to contain this coverage, with a hard Source-coordinate check. Coverage is bounded, not automatically expanded to every cell in a larger production world. `maxTowerModels` (128 parts) bounds both distant model creation and draws: nearest cells win, with deterministic coordinate/path tie-breaks. Towers in the current/detailed cells are excluded from this pass. Distant models use a separate long-range fog pass before the translucent nearby horizon, so its graduated haze blends over the towers rather than cutting off geometry drawn afterward; visual occlusion and weather matching still require live acceptance. `zombiesim_skybox_status` reports candidates, budget, omissions, missing assets, placements and frame draws. Weather and lighting sampling clamp both X/Y bounds to the manifest's playable cell span, not the enlarged sky room. Run `.\bin\test_skyscraper_height.ps1 -Compile` for the room-coverage and coordinate-limit regression in addition to tower clearance; these checks do not establish live visibility.

To prepare models without replacing a mounted manifest, pass `-OutputContentDirectory .\generated\skybox_preview\release_content` to `build_skybox_models.ps1`. Source material lookup still uses the installed content/mounted game assets; output models, wrappers and manifest go to the isolated directory. Validate that output with `.\bin\test_skybox_manifest.ps1 -WorldProfile preview -PlanData <matching-plan> -ContentDirectory .\generated\skybox_preview\release_content`. The check verifies exact recipe coverage, settings, nonempty model companions, tower presence and every preview viewpoint's distant-part budget. Once matching BSP compilation succeeds, copy the prepared models/materials to content and rerun the exporter with its default output to reuse the stamps, prune stale profile models and publish the manifest; never load a new camera manifest with old BSPs.

For fully isolated model intermediates also pass `-BuildDirectory` (for example
`.\generated\skybox_preview\model_build`). The builder uses the matching plan's
`cellDirectory`, not an unrelated profile source directory. Cache hashes include
the entire recursive VMF instance tree and footprint settings; missing nested
sources fail explicitly, and missing/empty MDL, VVD or DX90 VTX companions
invalidate base, snow and tower stamps.

When distant tower placements exist, the horizon uses a skyline-specific alpha gradient around eye level instead of the legacy near-opaque upper rings. Opaque towers draw first, then the haze blends over their bases. Drawing towers afterward produces hard bottom cutoffs; keeping the legacy upper-ring opacity hides the skyline. Views without distant placements retain the original gradient. `skylineHorizon` in the diagnostics identifies the active blend; actual skyline appearance must still be reviewed in game.

# Zombiesim Loot and loot spots

You can find all sorts of loot spots in the world which will give you awesome loot! The more danger your cell has, the better the loot!

### Recommended Item Weight Ranges (Rule of Thumb)

A clean standard baseline scale to use across your `loot.json` tables is a **1 to 100 relative weight scale**:

| Rarity Class | Item Weight | Expected Outcome in a Standard Table |
| --- | --- | --- |
| **Common** (Junk, Basic Ammo, Bandages) | **50 – 100** | Generates frequently; dominates low-danger areas. |
| **Uncommon** (Steel Pipe, Flashlight, Gasoline) | **20 – 49** | Moderate drops; noticeable but not everywhere. |
| **Rare** (Glock, 9mm, Shotgun) | **5 – 19** | Harder to find; usually requires high cell danger. |
| **Very Rare / Boss** (Katana, Desert Eagle) | **1 – 4** | Exciting jackpot loot; drops rarely. |

### Recommended Entity Loot Spots Weight Ranges (Rule of Thumb)

A clean standard baseline scale to use across your `entity_loot.json` tables is a **1 to 100 relative weight scale**:

| Rarity Class | Item Weight | Expected Outcome in a Standard Table |
| --- | --- | --- |
| **Common** (Trash Cans, Mail Boxes, Crates, Barrels) | **50 – 100** | Generates frequently; dominates low-danger areas. |
| **Uncommon** (Civilian Cars, Trucks, Corpses, Shelves) | **20 – 49** | Moderate; noticeable but not everywhere. |
| **Rare** (Police Cars, Military Vehicles, Ambluances) | **5 – 19** | Hard to find; usually requires high cell danger. |
| **Very Rare / Boss** ( Military Supply Crates, Caches, Steel Briefcase ) | **1 – 4** | Mythical; seen extremely rarely. |

# Common Problems

### The script says a settings file is missing

Run commands from the project root, or supply an explicit path:

```powershell
.\bin\generate_world_cells.ps1 -Preview -SettingsPath .\generator-settings.json
```

### The JSON will not load

Check for a missing comma, an extra comma after the final list item, curly quotation marks copied from a document, or a number that was placed inside quotes. Restore the backup if necessary.

### A generated VMF cannot find a tile

Check the relevant `terrainTemplates`, `topologyTemplates`, or `transportTemplates` path. It must exist below `templateDirectory`. Then check whether a `templatePatterns` filter accidentally excludes the new building or decoration.

### Roads look wrong in Hammer

Restore the canonical source VMF first. Then inspect the appropriate `rotations` entry and change the generated yaw only after verifying the source prefab's authored orientation. Do not move model offsets inside a native prefab to compensate for generator placement.

### Preview generation is too slow or produces too many recipes

Reduce `worldGeneration.profiles.preview.gridCells`, use a smaller `growthDepth`, lower `branchChance`, or raise `variants.usageThreshold`. Make one change, regenerate, and compare the preview key before changing more.
