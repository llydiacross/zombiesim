# Todo Alpha 3.5

**Status: ACTIVE IMPLEMENTATION AND PREVIEW REVIEW (started 2026-11-02; updated 2026-11-03).**
Alpha 3.5 is the active tracker.
Unfinished work from [Alpha 3.3](docs/todo-alpha-3.3.md) and
[Alpha 3.4](docs/todo-alpha-3.4.md) is carried forward below; archiving those
plans does not mean either milestone is released or fully accepted. Their
dated evidence and completed work remain in the archives.

The user reports adding new tiles and generator variants; the notes below
preserve the requested direction. Authored or source-wired tiles are not
proof that matching plans, VMFs, compiled maps, materials or runtime data
have been refreshed or staged. The user's latest tile edits take precedence
over older inventories.

**Skyscraper naming update (user, 2026-11-03):** the user renamed and added
skyscrapers to better reflect their world role. The current source tree
includes `tile_skyscraper_destroyed_{1a,1aa,1aaa,2aa,2aaa}_2x.vmf` and
generic `tile_skyscraper_4aaa_2x.vmf` / `5aaa_2x.vmf`; older radioactive
filenames were removed or revised. Preserve these authored changes. The source
patterns now recognize the destroyed skyscrapers, the destroyed building
selection takes precedence over radioactive selection, and skyline extraction
accepts the destroyed tower names. The generic `4aaa`/`5aaa` skyscrapers remain
ordinary candidates. Focused selection, inventory and skyline regressions
pass. The later isolated preview is recorded below.

**Tile-wiring source progress (user decisions, 2026-11-03):** a current
working-tree snapshot contains 78 untracked tile VMFs. A normalized audit
matches 76 to settings patterns or explicit source references; the two
unmatched sources, ordinary and army night-road straights, are intentionally
not selected under the user's `dead_zone`-only rule below. This is a snapshot,
not a complete history or a claim that edited existing sources and every
companion VMX have been reviewed.

- Radioactive and destroyed profiles currently resolve to the existing
  `dead_zone` sky mapping. The user chose the four straight night-road pieces
  only for profiles using that dark sky: radioactive and destroyed roads are
  in their matching straight-road pools; ordinary and army versions remain
  inactive unless those profiles later use `dead_zone`.
- All four night-road VMFs now have one tile-local `zn_prefab_anchor` at
  `(0,0,44)`, with `instance_local=1` and the matching existing road tags:
  `road_carcrash`, `roadRadiationHazard`, `roadArmy` and `roadDestroyed`.
  The existing `tile_road_night.vmx` differs from its VMF and lacks the VMF's
  lamp entities; it was preserved unmodified and must not be treated as a
  synchronized companion without review.
- The user classified `tile_plaza_1a` as general open-ground decoration and
  generic/radioactive fence caps, corners and doubles as standalone open-
  terrain decoration candidates. The new radioactive `tile_edge_ra_wall_6aaa`
  is included in its explicit outer-edge pool.
- The user approved moving the west-facing Police Station 1x2 direction marker
  from X=-324 to X=-320. The VMF and VMX marker metadata now agree; geometry is
  unchanged.

Focused source checks pass: scenery density 3287 assertions; template inventory
97 assertions and 192 explicit paths; skyline extraction; and prefab-anchor
transforms 20 assertions. The inventory fixture checks anchor counts for
configured straight-road variants and the expected tags on all four night
pieces. The border showcase was updated for the current high-density corner
and empty-cell policy; its isolated non-motorway fixture passes 14 cells and
seven topologies. The excluded motorway is covered separately by trusted-plan
checks. Existing tile-ground alignment warnings were not repaired. The later
preview authorization below does not approve developer-zoo, Hammer, compile
or staging work.

**City-density design decision (user, 2026-11-03):** the new baseline is radial
from the logical-grid center, with low density at the center increasing
outward; keep three tiers and reuse the existing 3/8-cell cutoffs as radial
distances. Preserve the current protected-coast rule and district density
floors. A future destroyed-epicenter ring may override this baseline. Increase
low-tier building-template selection only, leaving medium/high selection
unchanged; when both compatible pools exist, favor low-tagged templates 2:1
over untagged ones. The initial source-only restriction was superseded by the
later isolated preview request below.

**Radial-density source slice:** generator manifests now emit policy v2 with
Euclidean distance from the logical-grid center and the agreed `<3`, `3-<8`,
and `8+` tiers. The protected-coast override and commercial/financial/
settlement floors remain. Existing policy-v1 manifests keep their previous
tiers and selection behavior. Policy-v2 tier-1 single- and multi-tile building
selection applies the 2:1 low-tagged/neutral preference only when both
compatible pools exist; decorations, `AnyTier` pools and medium/high choices
are unchanged. Focused scenery-density checks pass3373 assertions, including
serialization, radial coordinates, v1 compatibility and deterministic
selection ratios. This was source/fixture evidence at that checkpoint; the
later preview authorization and outputs are recorded below.

**Generation continuation and frontage decision (user, 2026-11-03):** finish
the remaining generation source work before producing the newly requested
isolated preview and opening it in the world viewer. Compilation, staging,
production, navmesh and Cell Health remain separately gated. Unmarked building
fronts are south, including templates with road-connection markers. When a
blocked ordinary building has no valid in-place rotation, replace it with
open terrain; retain and report important landmarks.

The planner now checks occupied frontage after building placement, protects
the replacement terrain from later decoration, and re-resolves shared road
connections. An even-width midpoint is clear when either central neighboring
tile is clear; rectangle rotations cannot overwrite another footprint.
Focused frontage repair89/89, rectangular footprints570/570, road
connections108/108 and scenery density3376/3376 pass. The isolated test plan
using the retained, matching pre-3.5 manifest/trusted motorway contracts
checked 1,611 entrances (including 85 road-adjacent multi-tile buildings),
with no blocked ordinary frontages or protected-landmark exceptions.
The multi-tile fixture passed seven authored recipes and 59 marked road
connections. These are isolated regression outputs, not the new world preview
or visual acceptance; candidate-layout warnings are not necessarily final
selected variants. No BSP was compiled or staged.

**Zone decisions and source status (user, 2026-11-03):** preserve gameplay
radiation exposure; radioactive scenery covers distance `<7` from detonations
and `<=2` from laboratories. Destruction covers `<=4` from detonations,
starting low-density and increasing in thirds. Army, fortified and industrial
zones use radius four, with lower density near their origins. Exact Army Base,
Bunker and safe-zone cells are protected; elsewhere destruction wins over
military/fortified and radioactive scenery. District weights influence
industrial origins and commercial spread. Compatible industrial/radioactive
decorations are preferred 80% of the time in industrial zones. Where the Army
Base and Iron Bunker den share logical `(23,9)`, the user chose army
surroundings while retaining the den and excluding industrial overlay.
Destroyed wall pools use explicit recorded density exceptions where authored
tiers are missing. Policy-v1/unversioned behavior is retained.

**Isolated Alpha 3.5 preview underway:** the user approved fresh preview
generation and opening it in the world viewer, not compilation or staging.
The seed-1337 manifest has 576 cells, 571 road cells, 96 motorway cells,
11 dens and ten each Police and Fire landmarks. All ten districts have both
services. Its matching plan has 571 planned cells, five empty cells, 439 city
recipes and two standalone den recipes. A read-only check confirms both
service buildings are actually planned in every district and the shared
Army/den cell retains its entrance. Two candidate groups report that a
neighbouring matching layout could not be avoided within the variant cap;
22 density-exempt landmark shortages are reported rather than relocating
landmarks. The actual plan's frontage check passes 1,224 entrances, including
58 road-adjacent multi-tile buildings, with no blocked ordinary frontages or
reported blocked landmarks. Tower selection and shared-tower recipes pass.
Scenery zones now pass 1,595 assertions, including controlled selection of
the current themed building and decoration inventory; scenery density passes
3,381, template inventory 100 and motorway infill scope six. The planner
now records the manifest relative to its plan, including nested directories,
so the viewer can load the matching manifest; focused path tests pass. The
corrected plan passes 9,407 assertions, including all 96 trusted motorway
contracts and planned Police/Fire coverage in all ten districts. The
outer-edge unit checks pass 1,257 assertions; they now check the originally
converted props by model without rejecting the user's newly added fence props,
and verify the destroyed pool instead of the superseded radioactive fallback.
The first VMF build produced 439 city recipes and two reusable den VMFs; the
corrected-plan refresh found all 439 recipes unchanged. Across the emitted
layouts, all 24 west-ocean cells have nine ocean slots including both corners;
439 layouts have no duplicate or out-of-perimeter ring slots or missing
border/outer source templates. The 27 trusted complex-motorway recipes need
20 existing infill source templates, with none missing; seven below-four-unit
remainders in logical cell `(15,11)` remain on the default floor. Their final
134 emitted rectangles match the measurement pass. The final plan/layout,
VMF-hash, infill-source and motorway-contract checks pass 1,538 assertions;
all 439 required city VMFs exist. The viewer loads all 576 logical cells with
zero missing recipes/files, failed brush sides, failed props or texture
failures. An interactive overview opened and responded; it later closed
normally, and another viewer was observed responsive on the same plan at
grid `(18,1)`. Human visual review was pending at that checkpoint. Destroyed
wall pools use the authored destroyed pieces, but no destroyed corner
templates exist, so the existing default corner pools are retained for review.
No BSP, runtime export or map material was staged, and no in-game acceptance
is implied.

**Preview review and additional district tiles (user, 2026-11-03):** the user
reports all world changes in the first Alpha 3.5 viewer preview were successful.
Five further Army tiles and three fortified building tiles have since been
authored, along with edits to existing border, edge and terrain sources. The
user requested a refreshed generation and chose an 80/20 fortified/Army
building preference in fortified zones when both families are compatible.
Military cells retain their Army pool; compilation and staging remain separate
gates. The five Army sources and three fortified buildings are now wired.
Density and footprint eligibility are resolved before the preference, with
the compatible family used when the other is unavailable. Focused inventory,
Army selection, scenery-zone and density checks pass 105, 24, 1,628 and 3,386
assertions respectively; rectangular-footprint and road-connection checks pass
570 and 108. The isolated multi-tile fixture passes seven recipes and 89 marked
road connections, and the border showcase and 1,257 outer-edge unit assertions
pass.

The refreshed isolated preview is `generated/preview_alpha35_review_02`.
Its seed-1337 manifest is byte-identical to the approved first preview. The
plan has 571 planned cells, five empty cells, 439 city recipes, 96 unchanged
trusted motorway contracts and Police/Fire coverage in all ten districts.
Its tile-layout changes are confined to military and fortified profiles. All
eight new sources appear in their intended profiles; fortified cells contain
208 fortified and 51 Army building placements, and military cells contain 24
Army building placements. These are counts across logical cells, not a claim
that every selection had both compatible families. The exact plan passes 9,706
assertions and the frontage check covers 1,224 entrances without a blocked
ordinary building. Two neighbouring-layout candidate warnings remain.

All 439 required city VMFs and two reusable den VMFs were generated without
compilation. The 27 trusted motorway recipes use 134 infill rectangles matching
the measurement pass; all required infill sources already existed. Seven
sub-four-unit remainders remain on the default floor at logical `(15,11)`, as
in the approved first preview. The final infill/layout/VMF checks pass 1,538
assertions, all 826 non-motorway/den VMF and layout files remained unchanged
across the infill passes, and all 24 west-ocean cells retain their nine ocean
slots including corners. All 709 authored tile VMF/VMX files matched their
pre-build hashes. The viewer loaded 576 cells with no missing recipes/files,
failed sides, failed props or texture failures; a separate refreshed viewer
opened responsively in overview mode. The previously observed viewer was no
longer running afterward; its exit cause was not established. Human review of
this refreshed preview remains pending. No BSP, runtime export or map material
was compiled or staged, and no in-game acceptance is implied.

**Generator work completion (user, 2026-11-03):** the user confirms all
Alpha 3.5 generator changes are complete and wants work to continue on the
remaining milestone items. Generator source and isolated preview work are
accepted for progression. This does not imply a BSP compile, staged world,
in-game review, navmesh/Cell Health/Satellite work, production change or
publication.

The sections are grouped by workstream, not a newly approved implementation
order. Alpha 3.4's construction review was paused at the user's request;
confirm which workstream to resume before starting unrelated implementation.
Carry forward all explicit deferrals and obtain separate approval for
compilation, staging, navmesh, Cell Health, Satellite, production changes and
publication.

## World Generation Changes

- Added new decoration variants _ra_ and _industrial_ to be placed in industrial zones. Place these pieces over other decoration peices, favouring them all the time if not most of the time depending on how many assets are currently available.
- added new road variants with rigged up prefab anchors for spawning related road prefabs, these are just straight pieces for now
- Fortified zones need to decrease density the same as industrial zones, decreasing the density around the fortified areas so fortified zones do not appear in the middle of high density zones.
- Destroyed needs to take priority over radiation zones and destroyed zones need to originate around the epicenter, the epicenter also needs to decrease density around its origin.
- Landmarks which hold army bases are now "army" environment zones, their borders should use the army walls "the same as fortified", fortifieds hold bunkers. Same as the fortifized zones, the density around army zones needs to decrease to prevent them from appearing in high density areas.
- Density right now in the city ramps up from the ocean, the ocean areas being low density and then gradually as we go inland, the density increases. This was not was was originally intended with the idea of the city laying growing more in a circle the density should increase more uniformly from the center outwards rather than from the ocean inwards. The district needs again control how industrial, or how commercial an area of the city might be
- Sometimes the buildings front will be rotated to face a building directly cutting off access to that building. Its only in rare circumstances this happens where a buildings front is orientated into another building. Figure out a way to check if a building is facing into another building (a simple check after the buildings have been plased to check if the road connection entity is facing another building, if it is, keep rotating the building until it doesn't hit another building, or a border)
- Place a bit more low density buildings than we currently are, keep other density levels the same.
- Ensure amy bases are only placed in army zones and are using the correct army walls, and army buildings. Note: Special army buildigns are in the tiletemplates/army folder, these are buildings to be placed in army and fortified zones only.
- tile_armybase is the actual landmark for the armybase inside of a cell
- prefer _army_ decoration pieces and other buildings when placing in army zones to maintain thematic consistency.
- prefer _fortified_ decoration pieces and other buildings when placing in fortified zones to maintain thematic consistency.
- Destroyed areas are in a ring around the "Epicenter" or any other exploded nukes on the map. Destroyed areas take dominace over radiated structures. The Epicenter starts with low density, and the density gradually increases as you move away from the epicenter, creating a ring of destruction around it.
- Radiation zones take up less of the map. With settlement or (default) residential areas taking up more of the map. Industrial zones need to grow a bit larger, with their "density radius" expanding a bit bigger (maybe by 1 cell)
- More low residential buildings placed in low residential cells, more of a distance between medium density and high density residential areas to create a smoother transition between different density zones.
- Districts are less theoretical and actually reflect the chance of an industrial zone spawning. Commercial zones are still spread out through out the city, but can be influenced by be more common by the district they are in.

## Tile Changes & Additions

- New Radiation Tile Pieces
    - New Radiation Tile Road pieces, tile_ra_road and its variations for different road connections.
- New Army Tile Pieces
    - New Army Tile Road pieces, tile_army_road and its variations for different road connections rigged up with prefab anchors to spawn army related road prefabs
- New Factory Tile Pieces
    - New larger factory buildings. Place industry buildings more than usual in industiral zones.
    - Favour industrial decoration _industirial_ pieces and other buildings when placing in industrial zones to maintain thematic consistency.
- New Destroyed Tile Pieces

### Required: wire every new and renamed tile

The user explicitly requests **generator wiring**, not just an inventory.
The current working-tree snapshot contains 78 untracked tile VMFs across
`border`, `buildings`, `decorations`, `edges`, `roads` and `terrain`, as well
as edited and deleted tracked sources. This is a snapshot, not a complete
history of the user's work: re-inventory the current sources when implementation
starts, including additions or renames made later.

- [ ] Account for every added or renamed tile and its intended environment,
      density, footprint, role and selection owner. Include edited existing
      tiles and their dependencies in the impact review. Map old names to
      current sources where appropriate and inspect companion VMX metadata;
      preserve the user's authored files. An unassigned or incompatible new
      tile remains open unless the user explicitly agrees to exclude it.
- [ ] Wire every new or renamed tile into the appropriate generator pools,
      explicit landmark or topology mappings, and dependent consumers. An
      entry is not complete merely because a broad filename pattern matches:
      it must be reachable in its intended context, including role-specific
      pieces such as fence caps. The known families and intentions include:
  - **Destroyed:** `tiletemplates/buildings/tile_destroyed_*.vmf`,
    `tiletemplates/buildings/tile_skyscraper_destroyed_*.vmf`,
    `tiletemplates/decorations/tile_destroyed_*.vmf`,
    `tiletemplates/roads/tile_destroyed_road*.vmf`,
    `tiletemplates/border/tile_border_destroyed_wall_*.vmf` and
    `tiletemplates/edges/tile_edge_destroyed_wall_*.vmf`. Use these for the
    requested destruction around the Epicenter and other exploded nukes,
    respecting intended density/footprint and destroyed-over-radiation
    precedence in overlapping zones.
  - **Radiation:** `tiletemplates/buildings/tile_ra_building_*.vmf`,
    `tiletemplates/buildings/tile_skyscraper_ra_*.vmf`,
    `tiletemplates/roads/tile_ra_road*.vmf`,
    `tiletemplates/decorations/tile_ra_*.vmf`,
    `tiletemplates/terrain/tile_ra_*.vmf` and
    `tiletemplates/edges/tile_edge_ra_wall_*.vmf`. Wire the themed buildings,
    roads, scenery, terrain and walls into their intended radiation roles.
    The user also explicitly wants `_ra_` decoration variants preferred in
    industrial zones alongside `_industrial_` decorations; do not silently
    turn that request into a radioactive-only decoration rule. Confirm any
    unclear terrain or overlapping-zone use before implementation.
  - **Army and fortified:** `tiletemplates/buildings/tile_armybase_*.vmf`,
    `tiletemplates/buildings/tile_bunker_*.vmf`,
    `tiletemplates/army/*.vmf`,
    `tiletemplates/decorations/tile_army_*.vmf`,
    `tiletemplates/decorations/tile_fortified_*.vmf`,
    `tiletemplates/roads/tile_army_road*.vmf`,
    `tiletemplates/border/tile_border_army_*.vmf` and
    `tiletemplates/edges/tile_edge_army_*.vmf`. The army base is the army
    landmark; fortified zones hold bunkers. Prefer matching themed scenery,
    use the army walls for both zones, and restrict the special `army` folder
    buildings to army or fortified zones. Retain the army-road prefab intent.
  - **Industrial and factory:** `tiletemplates/buildings/tile_industrial_*.vmf`,
    `tiletemplates/decorations/tile_industrial_*.vmf` and
    `tiletemplates/terrain/tile_industrial_*.vmf`. Include the new larger
    factories and their actual footprints; place industry buildings more
    often and strongly prefer appropriate industrial decorations in
    industrial zones, with availability and fallback weights settled first.
  - **Other buildings and scenery:**
    `tiletemplates/buildings/tile_skyscraper_4aaa_2x.vmf` and
    `tiletemplates/buildings/tile_skyscraper_5aaa_2x.vmf` are ordinary
    skyscraper candidates;
    `tiletemplates/buildings/tile_policestation_1aaa_1x2.vmf` and
    `tiletemplates/buildings/tile_policestation_1aaa_2x.vmf` need the
    appropriate police-landmark and district handling with their footprints.
    The user classified `tiletemplates/decorations/tile_plaza_1a.vmf` as
    general open-ground decoration. Retain the separate police/fire-per-
    district requirements and existing controls.
- [ ] Complete the authored road-variant, connection-marker and companion-
      metadata audit. The four night variants are confirmed straight pieces;
      their intended profile pools and prefab anchors are source-wired and
      fixture-checked, but the existing `tile_road_night.vmx` remains
      unsynchronized and generated arrangements have not been reviewed in
      Hammer. Do not infer corners or junctions from filename suffixes.
      Preserve ordinary 640-unit road placement, approved motorway behavior
      and other road topologies.
- [x] Close the initially identified renamed-source gaps at source level:
      `destroyedBuildings` now matches `tile_skyscraper_destroyed_*`, destroyed
      candidates take precedence over radioactive selection, and the tower
      filter accepts destroyed skyscrapers. Destroyed border/edge pools use
      their matching pieces, and `tile_edge_ra_wall_6aaa` is in the explicit
      radioactive outer-edge pool. The stale radioactive-tower fixture now
      uses an extant source. Focused inventory, selection and skyline tests
      pass. This does not refresh or validate generated world outputs.
- [ ] Add focused positive and negative selection tests for every new or
      renamed family and all eligible variants: intended profiles and
      overlaps, tier/footprint, landmark, topology, rotations, prefab anchors,
      border/outer-edge roles and skyline extraction. Verify removed sources
      are not required by current settings or source-backed fixtures. Test
      reachability across controlled choices rather than requiring every
      variant to appear in one random plan, and protect existing neighboring
      pieces. Ask the user to resolve unclear placement, weights or overlaps
      instead of inventing an intention.

## World generation - consolidated work

The notes above are the user's requirements, not completed acceptance items.
Settle the unresolved measurements and overlaps before changing generation;
preserve authored VMFs/VMXs and approved motorway artwork.

- [ ] Complete and review the ocean-to-radial density change. Source now uses
      the approved radial baseline from the logical-grid center, with low
      density increasing outward and three tiers at the 3/8-cell cutoffs. The
      protected-coast override and current district floors remain. A future
      destroyed-epicenter ring is source-wired as recorded above. The matching
      isolated preview is authorized; generated-world review remains open.
      Low-tier single- and multi-tile buildings use the approved 2:1
      low-tagged-to-untagged preference when both are available; decorations,
      `AnyTier` pools and medium/high selections remain unchanged.
- [ ] Review the source-wired smaller radioactive scenery zone and wider
      settlement/residential space, district-weighted industrial origins and
      commercial spread in the isolated preview. Exposure remains unchanged.
- [ ] Give destroyed areas priority over radioactive structures. Model
      destruction around the Epicenter and any other exploded nukes: the
      Epicenter starts low-density and density rises with distance, producing
      a destruction ring. The overlap decisions are implemented as recorded
      above; generated-world review remains open.
- [ ] Lower density around fortified and army zones. Fortified zones hold
      bunkers; army-base landmarks form army environment zones with army walls
      and buildings. `tile_armybase` is the army-base landmark, and special
      `tiletemplates/army` buildings belong only in army or fortified zones.
      Keep army bases in army zones and preserve the army-only siren intent.
- [ ] Prefer matching `_army_`, `_fortified_` and `_industrial_` decorations
      and buildings in their zones. The user also requested `_ra_` and
      `_industrial_` decoration variants in industrial zones, strongly
      preferred when enough assets are available using the approved 80% weight.
      Carry forward the earlier building rule: radioactive cells use only
      radioactive buildings/skyscrapers, falling back to suitable
      terrain/detail when none exists; other environments may use untagged
      buildings and prefer matching tagged ones. Overlap decisions are
      implemented as recorded above.
- [ ] Complete the required new/renamed tile wiring and validation above;
      do not assume an old inventory or generated plan includes today's
      additions.
- [ ] Complete review of the source-wired building-front repair. The planner
      uses the authored front or the user's south default, keeps an existing
      clear placement, and otherwise tests safe in-place cardinal rotations.
      An unrepairable ordinary building becomes protected open terrain; an
      important landmark is retained and reported. Focused fixtures and the
      retained-manifest test plan pass as recorded above; review the matching
      new preview in the viewer before accepting generated behavior.
- [ ] Carry forward ordinary-road connection handling: `parking` and
      `dual_driveway` affect the adjacent road, including from 1x1 buildings;
      two driveways become dual, otherwise driveway beats parking and bus,
      and parking beats bus. The source and fixtures were wired previously,
      but authored parking markers and full integration still need checking.
      Keep ordinary roads on the 640-unit grid and retain approved motorway
      leases, gates and lane/arrival behavior.
- [ ] Retain the source-wired anti-grid road policy and empty-cell handling
      through the new plan. Check origin reachability, motorway controls,
      runtime exports, map/Cell Health presentation and travel; live
      empty-cell behavior remains unverified.
- [ ] Carry forward the Alpha 3.3 distribution requests: spread commercial
      buildings across districts and density tiers; make park landmarks less
      common and leisure more common; and provide at least one police and
      one fire station per district without relocating fixed landmarks or
      overriding safe-zone constraints. Park/leisure weighting and suitable
      commercial/police/fire tile patterns already have source work; confirm
      current placements and per-district counts rather than reimplementing
      them blindly.
- [ ] Preserve the restored ordinary-road on-ramp doglegs at logical
      `(13,18)` south and `(6,23)` east; the latter still needs Hammer and
      in-game review. Include the user's aesthetic 1x1 road redesign and its
      instance dependencies in the separately approved rebuild.
- [ ] Investigate the reported west-ocean beach seam and visible underside on
      the exact affected compiled cell. Trace the authored outer edge, shell
      floor/walls and skybox shoreline together; verify all west-ocean cells
      and corners, retained borders and a seamless `blendrocksand004a` join.
      The source-wired ocean pool and offline checks are not compiled or
      visual acceptance.
- [ ] Add focused selection, orientation, frontage, environment-overlap,
      district-count and protected-neighbour regressions. Review the matching
      regenerated world in the viewer and obtain the user's approval before
      compiling or staging. The previously viewed world was
      approved; today's source edits make older generated artifacts
      potentially stale, not newly approved outputs.

## Player structures and claims - carried from Alpha 3.4 Phase E

**Decisions retained:** a survivor owns a claim and the account's other
survivors have friend-level access; owners can add friends. Claim tokens are
tradable backpack items, cost 25 credits at den traders and may later be quest
rewards. Claims are unlimited apart from tokens. A visit by the owner or a
friend resets the 30-day expiry; after expiry contents remain in their boxes
and others may salvage the structure and loot it. Construction protection
extends 640 units beyond the claim, building uses existing scrap/wood/metal,
and zombies and other players can damage structures. Workbenches and other
interactive furniture are out of scope.

**Source/offline status:** `claimTiles` export, `ZM_World` claim lookup,
`ZM_ClaimService`, atomic token consumption and 30-day visits are implemented.
Claims are scoped by profile, logical cell and centred core tile, not BSP name.
The existing loot-findable Hammer is also sold by the General Trader; Reload
toggles build mode. Build speed rises from 1x at hammer level 8 to 2x at
level 30, and a mastercraft hammer halves each material cost, rounded up to
at least one. The 64-unit foundation/wall blueprint prototype uses atomic
first-contribution payment and fades in on completion. Its foundation costs
4 Wood and 2 Scrap, its wall 3 Wood and 1 Scrap, with provisional build times
of 6 and 4 seconds respectively. The recorded claim and construction
fixtures pass. The native claims suite now passes 3/3 after the approved
claim-only preview reload recorded below; the construction prototype has not
been live-tested. Pieces do not yet persist. The installed preview runtime
JSON was unchanged at the original source-only checkpoint.

**Installed-preview claim export preflight (2026-11-03):** an isolated
`claimTiles` export was generated from the retained Alpha 3.3 plan whose
manifest and plan hashes exactly match the installed preview. All non-claim
runtime fields match the installed JSON; the export adds claimable core tiles
to 571 cells (6,759 tiles). The new Alpha 3.5 viewer preview is not compiled
or staged and is deliberately not used to replace the installed runtime map.

**Approved claim-data reload (user, 2026-11-03):** after explicit approval,
`content/data_static/zombiesim_world_preview.json` was replaced with the exact
claim-only export above. Its verified pre-stage backup is
`generated/preview_alpha35_claim_preflight/zombiesim_world_preview.pre-claimTiles.json`
(SHA-256 `baaff72445c026a7ee09a98be6367fd01b05b91758d3baed548d5fcedeac5378`);
the staged file hash is
`f7ba3f66bf6e49a5b8bd2d90acc67da37c9ea805663984098c67990b9f80596a`.
GMod launched with `-disableluarefresh`; read-only status confirms
`zn_preview_start`/preview. The first native claims run exposed a test-fixture
path mismatch: it appended `.bsp`, unlike `ZM_World:GetMapTransitionPath`.
The stub was corrected to mirror the production map-name contract; focused
offline claim/world tests pass 12 cases, GLua syntax passes 407/0, and the
fresh native `zn_test_claims` suite passes 3/3. Its test-profile cleanup
passed, and no survivor was deployed or modified.

**Claim-review safety continuation (user resumed, 2026-11-03):** the bounded
preview review helper now rejects a target tile outside the same 1.5-tile
claim reach enforced by `ZM_ClaimService`, before writing temporary inventory.
The claim service exposes that reach check for both normal claims and review
preflight. A fault-injected SQL trigger verifies rollback preserves the
temporary items and review claim when a transaction step fails, then succeeds
on retry. Focused claim/world/construction fixtures pass 34/34, GLua syntax
passes 408/0, and `git diff --check` passes. The README documents the
development-only commands and their constraints. After the user's approval,
the updated Lua was loaded and native `zn_test_claims` passed 3/3.

**Authorized live-review attempt (user, 2026-11-03):** the existing preview
survivor was deployed from the launcher and its stored cell `(14,2)` was
confirmed read-only; that cell has radiation intensity 1, so it was not used
for review. The user approved a temporary move to zero-radiation cell
`(14,-7)`/ID134 and return. At ID134, the helper's preflight refused before
any write because tile `(1,-1)` was not claimable in the live `ZM_World`
index. After the user's approval,
a new read-only status command was loaded and queried cell134. Its 12 indexed
offsets exactly match the current source export; neither contains `(1,-1)`.
The original refusal was caused by selecting a non-exported tile, not a
mounted-data mismatch. No temporary inventory items or claim were created or
runtime data restaged. The survivor returned through the preview transition
to `(14,2)`/ID350; post-reload status confirms preview, alive, health100 and
the same cell. The user chose to leave hunger and thirst unrestored; no direct
stat edit was made. GMod's earlier crash remains unexplained; no cause is
inferred.

A read-only `zombiesim_dev_claim_review_status [cellId]` command now reports
the active preview data path, map, radiation and indexed claimable offsets
for the current or requested exported cell. Live query of cell134 confirmed
`data_static/zombiesim_world_preview.json`, zero radiation, map
`zz_preview_08960535c24e`, and exact source/index claim-tile agreement.
The player was at local position `(-640,640)` on that map, making `(-1,1)` an
exported, reachable candidate. The review start stopped before any write
because the backpack did not have two empty slots; it has not yet checked
whether that candidate has an existing claim. No item or claim was created.
The user chose not to restore hunger/thirst. Following the additional
preview-cell transitions, a read-only persistence report showed the survivor
back at cell350, alive and health100, with runtime hunger99.73 and thirst
99.6025. These values rose from the earlier reported 86.893/80.34 during the
transition; the cause is unverified, no cheat was changed, and no direct stat
edit was made. Focused claim-service fixtures pass 16/16, GLua syntax passes
408/0, and `git diff --check` passes. The user reports freeing two backpack
slots before restarting GMod; recheck the live inventory and candidate claim
row before the bounded review. Review protections and unpaid blueprints, then
roll back. The diagnostic performs no player-data writes.

**Dropped-crate collision follow-up (2026-11-03):** the user requested a
slightly smaller collision box and no crate left inside a player. The visible
crate and its height are unchanged; horizontal bounds are inset by one unit.
Creation now checks every player's world collision bounds with one unit of
clearance before an inventory transaction. A blocked saved crate remains in
storage and the existing 30-second maintenance pass retries it. After the
user-requested GMod restart, the native inventory suite passes 54/54 in the
preview launcher, including the collision and no-inventory-write cases.
Offline crate-restoration and claim/world/construction fixtures pass 36/36,
GLua syntax passes 408/0, and `git diff --check` passes. Actual player drop
interaction and visual review remain unverified.

**Review preflight after restart (2026-11-03):** a read-only database check
found three free stored backpack slots, no existing token or Hammer in the
selected preview survivor's inventory, and no claim row at cell134 tile
`(-1,1)`. After the user deployed, the approved preview transition brought
the survivor to ID134 at health100. Before starting the review, source and
stored-data checks showed this survivor is level1, but the temporary Hammer
requires level8 and Strength5. It cannot be equipped under the normal item
requirements; the only existing preview survivor is level1. The review was
not started and no temporary item, claim or blueprint was created.

The approved return to `(14,2)`/ID350 completed; a separate read-only report
confirms preview, alive and health100. The survivor's 17 inventory rows, three
weapon-slot rows, candidate-cell claim rows and owner friend rows match the
arrival snapshot. Hunger and thirst were left as-is, as requested. The user
subsequently set this survivor to level20; its saved base Strength is
5 and a shotgun is now selected. This is the new user-owned baseline, not
something to undo.

The review helper now checks the temporary Hammer's normal requirements and
confirms any previously selected weapon exists before writing. Its rollback
permits only the selection change caused by the temporary Hammer, restores
the previous selection and still rejects unrelated slot changes. Offline
claim/world/construction/crate fixtures pass 39/39, GLua syntax passes 408/0,
and scoped `git diff --check` passes.

The user approved another transition to ID134. The new pretravel and arrival
snapshots match for inventory, attributes, weapon slots, candidate-cell claims
and owner friends. Saved level was 21 and base Strength5; XP increased by35
during the transition for an unverified reason and was left unchanged.
After the user indicated readiness, the review start failed before committing
any temporary item: GMod `sql.Query` represents SQL NULL as the string
`"NULL"`, which the exact inventory writer rejected as invalid JSON. A
separate database comparison confirms inventory, weapon slots, candidate-cell
claims and owner friends still match the arrival snapshot; no review claim or
blueprint was created.

Source now distinguishes actual SQL NULL from the literal string by querying
`IS NULL` for exact item and weapon-slot snapshots, without changing ordinary
inventory reads. Invalid literal attribute data still blocks a write. The
offline SQL fixture now models GMod's stringified NULLs and covers both values,
selected-weapon restoration and rollback failures. Focused
claim/world/construction/crate fixtures pass 40/40, GLua syntax passes 408/0,
and scoped `git diff --check` passes. A new isolated native claims case covers
the exact SQL path but has not been live-loaded or run. The survivor remains
in preview cell `(14,-7)`/ID134; ask before reloading. The 180-second review,
actual selected-weapon restoration and live construction remain unverified.

**Construction review follow-up (2026-11-03):** removed the per-player
blueprint-count cap. E now gives an immediate one-second progress contribution,
then credits capped elapsed time while held. During claim review, only a
blueprint whose `ZM_ClaimReviewSessionId` exactly matches the active session
and whose player is the active review owner builds free; unrelated or inactive
session pieces still hit the paid-construction guard. Normal construction still
pays atomically. The overlapping top-centred HUD was replaced with a compact
upper-left panel and split placement/build instructions.
Focused construction fixtures pass 16/16, GLua syntax passes 408/0, and
`git diff --check` passes. This tests free review construction only, not payment.
The source has not been reloaded. A fresh read-only status confirmed preview
cell 134 on `zz_preview_08960535c24e`, but did not report review-session or
temporary-piece state. After approval, the guarded rollback refused before
writing because inventory changed outside the temporary review items. The
user authorized restoring the single confirmed stack difference; the read-only
report then matched its pre-review count. One rollback retry timed out without
acknowledgment. A later guarded check refused because weapon slots differed
outside the temporary Hammer. The user approved restoring the baseline weapon
selection; `zn_equip_item` selected the original M4A1 successfully. The next guarded rollback still refused because an additional backpack item
differed from the pre-review snapshot; the user chose to keep that Crowbar.

**Preview review cleanup continuation (user, 2026-11-03):** the user clarified
that preview is a test environment and exact inventory/player-data baselines
are not a priority unless a test requires them. The review cleanup now reads
current rows, removes only the session's temporary items and identity-checked
claim in one transaction, preserves unrelated inventory, claims and weapon
selection changes, and removes only tagged pieces. It still reports malformed
weapon state, replaced claims and transaction failures explicitly. Construction
now uses the crosshair's centre-of-mass aim; build mode in top-down and orbit
views aims at the cursor or screen-centre surface instead of the ordinary
horizontal weapon aim. The server still traces and validates the placement.
Focused claim/world/construction/camera fixtures pass 49/49, including
four wall edges on a completed foundation; GLua syntax passes 408/0.
The old retry timed out without acknowledgement; read-only checks subsequently
found no temporary Hammer, token or review-tile claim, but did not establish
whether the old in-memory session cleared. The latest source is not
covered by a live construction review. After the approved same-cell reload,
the survivor was alive at health100 in preview cell134 and the Crowbar remained;
the fresh native claims suite passes 4/4. The latest preview check found one
empty backpack slot and three occupied weapon slots; the helper needs two
empty backpack slots and equipping its Hammer also requires an available
weapon slot.
At that checkpoint, E progress, unlimited placement, the revised HUD, placement
and removal remained unreviewed live. Normal paid construction is not verified
by the free-review path.

**Construction review and next requests (user, 2026-11-03):** the user
reviewed the foundation/wall prototype in preview cell134 and reports that
building felt satisfying, E construction worked and the reviewed experience
worked well. The three-minute review expired while they were building, and
they report the temporary house disappeared. A subsequent rollback request
reported no active session; read-only checks found no temporary Hammer or
token and no review claim at tile `(-1,1)`. The Crowbar remains. An exact
over-12 placement count, individual camera modes, normal paid building and
multiplayer were not independently verified. Pieces are not yet persisted
across map loads.

The user requests a Q-key piece gallery with a selectable grid, additional
pieces including roofs and complex shapes, and construction sounds with
hammer-swing feedback. They selected full, half and triangular foundations
and floors; full/half walls, doorway and window frames; flat and sloped roofs
including corners; and stairs and ramps. Selecting a gallery item closes it.
Functional doors and windows remain separate. Preserve the approved prototype
foundation and wall presentation while adding the catalogue. Future timed
reviews should provide enough time for house-building and disclose cleanup.

**Construction catalogue source pass (2026-11-03):** the 16-piece wooden
catalogue, server-validated selection, Q/`+menu` gallery, shape-aware
blueprints and progress fills, multi-convex collision for complex pieces,
and contribution sounds/swing feedback are source-wired. The existing
64x64x16 foundation and 64x8x128 wall presentation is retained. New-piece
prices and times are provisional; normal payment still commits the material
cost atomically and now distinguishes a write failure from insufficient
materials. The bounded free-build review now expires after 30 minutes and
removes its session-owned house on cleanup. Client diagnostics report material
and frame-scoped draw status; gallery screenshots include VGUI.

Focused offline construction/claim/world fixtures pass 77/77 and GLua syntax
passes 410/0. After a user-approved same-map reload, a fresh client status on
`zz_preview_08960535c24e`/preview reported 16 non-error piece materials and a
valid beam texture; this does not prove their appearance. The approved
30-minute review started at approximately 09:39 on 2026-11-03: preview cell
134 tile (-1,1) was claimed with the temporary token, the review Hammer is
available, and the Crowbar remains. Successful cleanup removes the claim,
temporary Hammer and all session-owned pieces; timeout attempts the same.
Await the human review and
verify cleanup. Gallery focus/close, shape placement and appearance,
sound/swing, doorway/window pass-through, stairs/ramp walking, client/server
collision and performance remain unverified. Occupancy checks use component
bounds and can conservatively reject a non-box shape. Paid building, piece
persistence and multiplayer are also not live-verified. Ask before another
reload or review.

**Inventory/weapon-slot recovery during review (2026-11-03):** the user
reported the Hammer disappearing. Live inventory and slot data showed the
Hammer still in the backpack while slot 3 contained the Elite but referenced
the Hammer. The snapshot code could consequently hide both items; no separate
client screenshot proved that exact snapshot. The exact Elite was moved to
the backpack through the inventory service and the temporary Hammer was
equipped in slot 3, without cleaning up or restarting the review. The Crowbar
remains. The review was last confirmed active after the original wall-clock
estimate; its remaining time and the reason are unknown. A later read-only
report confirms the Hammer equipped, Elite and Crowbar in the backpack, and
the same preview cell, but does not itself establish whether the session is
still active.

Source now reconciles weapon-slot references with the physical equipped
container, shows all actual backpack items, and atomically saves weapon moves,
swaps and slot changes. An occupied slot rejects a backpack equip before
spawning a weapon; legacy references recover only into their intended empty
slot. Failure cases preserve prior items and selection, and firearm clip
handling and same-class restoration have focused coverage. Offline inventory
slot cases pass 22/22; the combined inventory/claim/world/construction/crate
run passes 100/100, GLua syntax 410/0, and `git diff --check` passes. These are
fixture/static results: the inventory fix has not been fresh-loaded, the
native inventory suite and client UI have not been retested, and the user has
chosen to keep the current structures and continue their review rather than
clean up and restart it. Cleanup or timeout *attempts* to remove its claim,
temporary items and all tagged structures; do not promise an expiry time.
Ask before cleanup or reload.

**Automatic multi-level snapping (2026-11-03):** the user reported being unable
to place another floor after stairs or attach a roof, and chose automatic
snapping rather than a height selector. Source now attaches floors and roofs
to finished stair/ramp landings and wall tops, extends matching floor/roof
edges, and stacks walls. Half floors align to their actual edge; triangular
floors can join diagonally or rotate to present a straight edge. Sloped roof
edges reject mismatched profiles. A landing floor's upper surface is 8 units
above the stair or ramp top. Client ghost and server placement share the
resolver, while the server retains its own trace and claim-footprint checks.
A live report followed: the user saw no ghost when trying to place a floor from
the top of the stairs. The aim into open air missed, or hit the ground far
below. The shared `PlacementTrace` now extends the finished piece underfoot
when a floor or roof is selected and the aim misses or lands more than 32 units
below the player's feet. For stairs, it uses their top end. Construction and
gallery fixtures pass 54/54, and GLua passes 410/0. A live check is pending.
The user confirmed stairs worked after placing a floor, then asked to place
stairs without a floor, like ramps. `PlacementTrace` now supports stairs and
ramps when standing on world ground or a finished level construction piece
while aiming into open air. Construction and gallery fixtures pass 58/58;
GLua passes 410/0. After user approval, the preview map
`zz_preview_08960535c24e` was reloaded; live ghost, placement and refund review
remain pending. This reload removed the transient structures.
The user chose full material refunds for removal. Paid cost is recorded when
charged, preserving mastercraft discounts; free-built pieces refund nothing.
The user subsequently confirmed stair placement, but reported disconnected
upper-floor blueprints that were hard to target and empty adjacent floor
positions that would not snap to the cursor.

**Cursor targeting and revised removal controls (2026-11-03, source only):**
the shared picker now intersects authored convex shapes rather than relying
on the small placeholder model, respects world/prop occlusion and shape holes,
and reaches 1024 units for deletion. Empty-space floor/roof aiming projects
the camera cursor onto the finished support's storey; the cursor's side selects
the extension edge without changing the existing floor height. This replaces
the old fabricated facing point and nearest-edge choice for synthetic traces.
The user explicitly replaced the earlier RMB removal/cycling controls:

- Delete enters delete mode. LMB toggles owned pieces into/out of a red
  selection, with no removal on click; Delete again confirms the selection.
- RMB only undoes an owned unfinished blueprint, never a finished piece and
  never catalogue cycling. Paid partial blueprints refund their recorded cost.
- One atomic inventory mutation refunds the entire confirmed batch, splitting
  grants by stack limits. Capacity/write failures retain all pieces, materials
  and selection. There is no fixed selection cap.
- Ghosts/gallery and E construction are suppressed during selection. Reload,
  weapon changes, death and lost build access cancel without deleting. Delete
  with an empty selection simply exits. Ownership/access are rechecked on
  selection and confirmation.

Related construction/entity/render/gallery/camera/claims/world fixtures pass
110/110; GLua syntax passes 410/0. Coverage includes cardinal shape picking,
holes/occlusion, floating blueprint reach, off-centre storey extension, the
camera-to-placement path, client input/focus/red tint and rollback after refund
capacity/write failures. The user approved reloading and clearing the current
structures. A separate post-reload status confirms
`zz_preview_0a9894c9058b-cp`/preview; a fresh 20:58 client report includes the
new delete-mode/count fields (off/zero) and valid construction materials.
That verifies loaded code, not interaction or appearance.
Cursor snapping, deletion/refunds, walking collision, roof appearance,
normal payment and multiplayer remain unverified live. Ask before reloading:
structures are transient. Do not assume the bounded review session remains
active or that its one-shot timer cannot remove them.
The requested human review was blocked by no claim access in current cell 133;
the user did not test any of the three new control/snapping paths. Read-only
claimability status lists ten tiles, including (-1,1). At their request one
claim token was granted after the first attempt failed with a full backpack
and they freed a slot; the successful inventory report verifies one token.
The user will claim their chosen tile here. No claim or travel was automated.

**Claim mode and map boxes (user request, 2026-11-03; source/offline only):**

- **Claim mode.** Using a claim token (double-click, or the context menu's
  **Claim land**) closes the inventory and enters claim mode. The current
  cell's claimable tiles are outlined on the ground, and the hovered tile shows
  free/far/mine/friend/other/lapsed. LMB claims it; RMB, Esc, death and safe
  zones cancel.
- **Server.** The server rate-limits the request and validates it through
  `ClaimTile`, with whole-number tiles −2..2 and the existing reach and token
  rules. A changed claim snapshot is sent on visits and claims.
- **Map boxes.** Bordered boxes mark claims on the HUD minimap and the world
  map's local view. On the grid/satellite views they show your own claims
  across cells and others' claims in the current cell.
- **Error fix.** The reported `sh_construction.lua:604` `GetPieceKind` nil
  error is fixed: traces skip pieces whose client accessors are not ready yet.
- **Static checks.** Claim/client/construction/gallery/world fixtures pass
  101/101, GLua syntax passes 411/0 and `git diff --check` passes.
- **Grid crash fix.** The world map's grid/satellite boxes crashed at
  `cl_claims.lua:452` because `cell and gridCoordinates( cell )` kept only
  the first return value; both coordinates are now read (client fixture 6/6,
  GLua 411/0).
- **User accepted (2026-11-03):** after a reload, the user tested building
  (including the latest delete-mode, blueprint-undo and floor-snapping
  changes) and said it works perfectly, and that the claim box shows clearly.
  They passed both areas. This is a single-player review; paid construction,
  zombie structure damage and multiplayer are not covered by it.

- [x] Match, back up, stage and reload the installed-preview `claimTiles`
      export; run the isolated native claim suite. The Alpha 3.5 viewer plan
      was not compiled or used as runtime data.
- [ ] Complete remaining live checks of build-mode protection, an exact
      over-12 placement count, individual camera modes and normal paid
      construction. The user approved the bounded free-build experience above;
      it does not verify paid construction or multiplayer.
- [ ] Complete and review claimed-tile boundary/placement and mutual
      player/zombie and player/player protection, including access changes,
      distance, death, disconnect, multiple players and transitions.
      Environmental damage remains unaffected. Adjacent expansion needs
      another token; roads, borders, buildings and occupied multi-tile
      footprints are not claimable.
- [ ] Review the new wooden catalogue and extend it to the agreed
      wood/stone/metal/concrete materials. The current prototype wall is 8 units
      thick; do not present it as the final requested 16-unit piece.
- [ ] Review zombie structure damage (user request, source/offline only).
      User decisions: a walker gives up hitting after 20 s and seeks a
      doorway; one walker breaks a wooden wall in 5 minutes; four visible
      damage stages; every piece takes damage with health scaled by wood
      cost; the Hammer repairs a damaged piece with E for free. Implemented in
      `sv_construction.lua` (damage/break/repair), the piece client (stages,
      marks, splinters) and `zn_walker_zombie` (blocker detection, siege,
      `CanReachTarget`, doorway seeking with 60 s memory, fallback to
      hitting). Construction41/41, render8/8, walker behaviour8/8 and
      GLua410/0 pass; `test_walker_preload` fails before and after (unchanged
      `sv_transitions.lua`). Limits: no structural support, wear not
      persisted, direct doorway approach may snag, mark visibility unverified.
      Live wear, breaking, repair and give-up remain unverified.
- [x] Review the preview **Free building** cheat (user request). A sixth
      persisted Cheats toggle (`freeBuild`, operator-gated in `sv_preview.lua`)
      lets `Contribute` skip `PayForPiece`; blueprints stay unpaid and
      removable. The user confirms the cheat works; fit of the sixth toggle in
      the Cheats window is not separately confirmed.
- [ ] Persist pieces, per-material health, repair, damage and destruction.
      Validate ownership, snapping, placement and atomic material costs on
      the server; interrupted/repeated input and failed writes must not
      duplicate pieces or items.
      **Source (2026-11-03, live unverified):** the server-only
      `construction_pieces` table stores each piece per profile/logical cell,
      including blueprints, the exact paid cost, completion, health and owner
      character key. Placement, payment (`extraSteps`), refunds/removal and
      breaking commit in the owning transaction. Damage/repair health
      flushes every 5 s and on cleanup/shutdown. Pieces restore when their
      cell loads (`OnPlayerReady`) and despawn on `PreCleanupMap`. A failed
      save rolls back the entity, items or row. Pieces survive a claim lapse;
      when a different owner claims the tile, `claimCreate` deletes them
      without refund. Persistence fixtures 7/7 (SQLite, real `sql.lua`)
      cover the round trip, reload idempotence, profile/cell isolation,
      failed payment/removal/placement writes, breaking and reclaim. With
      construction, claim service and claims client the total is 91/91, and
      GLua 411/0. The reload test awaits the user. Restore assumes one active
      cell per server.
- [ ] Add independently persisted storage boxes with no user-facing item-count
      cap, safe transaction/paging and secure access. Define reclaim and
      destruction behavior without losing existing box contents. Add doors,
      locks/keys or permissions, windows, barricades and curtains.
- [ ] Settle remaining PvP/raiding and offline-protection rules, door keys,
      airtightness and AI attack behavior. Test enclosure changes from missing
      or destroyed pieces and open doors/windows; muffle sound/light only when
      appropriate. Without curtains zombies try the front door first, then
      collectively try a wall after repeated inaccessible-door attempts.
      Obtain construction, damage, storage and multiplayer review.

## Viewer, prefabs and retained gameplay work

- [ ] Design the requested world-viewer editing of individual tile
      placements, rotations and offsets separately from its existing read-only
      preview. Saved edits must preserve generator footprints, leases,
      connections, gates and required-map validation, with an agreed path to
      apply them to the world. The viewer currently has no shadows or props;
      the requested shadows and optional prop rendering remain to be
      considered separately from the approved world view. Viewer output is
      not proof of VBSP, lighting, navmesh, travel or skybox-coast correctness.
- [ ] Retain the accepted prefab editor/world-integration limits: normal-world
      non-unit scaling remains blocked pending gameplay/client/server
      collision and PVS checks; independent-axis scaling remains deferred.
      A real-cell roadblock/gate set piece and accepted prefab loot reward,
      multiplayer/late joins and Hammer particle name fixups remain
      unverified. Keep `ZM_World` as the route authority.
- [ ] After the first real-cell set pieces are reviewed, consider the
      requested environment-specific road prefabs and motorway traffic
      patterns using the existing stable server-owned selection. All players
      on a server must see the same choice; do not silently substitute a
      default for a missing matching prefab.
- [ ] Keep guard kill/reward, deployed-guard and multiplayer testing deferred
      until the user asks to resume it. The editable-prop ground-shadow
      investigation was also explicitly deferred; do not restart it without
      agreement or treat projector status as visual acceptance.
- [ ] Review the slower Walker feel when a suitable navmesh is available,
      and perform the requested on-screen Walker capacity study with matched
      workloads before proposing culling, LOD or pathing changes. Player
      walk/sprint and stamina changes are already source-wired and
      user-approved. Phase B/C remain accepted with their recorded hearing,
      damage/armour, performance and multiplayer limits.
- [ ] If third-person object or prop disappearance is still reproducible,
      investigate camera/PVS culling separately from Walker despawn. The user
      accepted the bounded Walker review; do not assume both reports have the
      same cause or reopen that acceptance without new evidence.
- [ ] Preserve the user-approved fog, cloud, lightning, rain and skybox split
      presentations. Fog remains the user's least-priority presentation work.
      Remaining work includes the reported billboard z-fighting, the original
      skybox/world mismatch and double-fog seam if still reproducible,
      weather/capture and matched-performance checks, and the unverified
      reduced-lightning-flash mode. The proposed first-run photosensitivity
      prompt is deferred; do not reopen approved visuals.
- [ ] The user reports the calling-card system is perfect; do not repeat its
      approved presentation review. Actual purchases and multiplayer remain
      unverified, and quest reward integration is deferred until a quest
      owner exists. Preserve account/profile unlocks and survivor selections.
- [ ] Credits music was heard by the user. Dancer head tracking and another
      active dancer snapshot were explicitly deferred; resume only with
      agreement, then verify actual model axes, camera behavior, audio/exit
      cleanup and both launcher profiles.
- [ ] Investigate launcher UI ghosting reported and captured on 2026-11-03.
      Old Home, survivor-selection and Tools artwork overlaps the current
      Tools page; the user reports the duplicates are not clickable and
      survive map reloads, while fully closing GMod clears them. The affected
      process has `-disableluarefresh`, so hot reload alone is not an
      established cause. A fresh after-VGUI capture confirms the layering
      while the Tools diagnostic reports no open atlas workspace or cards.
      The added read-only `launcher.panels` report confirms old page roots stay
      visible and marked for deletion across fresh reports more than 12 seconds
      apart, including after the approved same-map reload and after closing
      `vgui_drawtree`. This is not just a one-frame deferred-deletion check.
      The reason the client retains them, and any connection to the earlier
      crash, remain unknown; do not mask a possible resource leak by hiding
      panels and declaring it fixed. The user approved a full restart and
      bounded clean-client Tools comparison. Diagnostics and all-page VGUI
      capture regressions pass 3/3; GLua 408/0 and diff checks pass. The wider
      creation-camera fixture run passes 8/9, with its warning-order assertion
      expecting `create_character` before the existing missing-`deploy_camera`
      warning; this is outside the diagnostic change.
      After the approved full restart, fresh screenshots and panel reports show
      a clean Tools page with exactly one current page root and no pending old
      page roots, including after a Home/Tools round trip. The user also reports
      the Tools views look normal and cannot currently reproduce the issue.
      This verifies recovery, not a permanent fix or the original trigger.
      Read-only diagnostics remain available for the next occurrence; no
      survivor deployment, claim-review mutation or world work ran in this
      investigation.
      Symptom fix: `ZM_LauncherMenu:DiscardPanel` now stops animations,
      disables input and hides an outgoing page root (also the replaced frame
      and the Tools workspace body) before the deferred `Remove()`, so a page
      whose deletion stalls can no longer paint over the current page. Focused
      regression passes, GLua 408/0. After an approved preview-launcher reload
      the user confirmed Home/Tools/Item Atlas/Play/Settings round trips show
      no ghosting, and the panel report lists exactly one page root. Why the
      engine sometimes defers deletion indefinitely remains unknown; if the
      `launcher.panels` report again shows hidden roots stuck in
      `markedForDeletion`, investigate that retention separately.

The accepted default-off CSM experiment keeps its remaining work deferred in
the [CSM tracker](docs/csm-implementation.md); this consolidation does not
reopen it.

## Asset staging and targeted refactors - carried from Alpha 3.4 Phase F

- [ ] Audit the user's sign/evacuation artwork and clothing sources, rights,
      ownership and build inputs. Propose bounded builds and hash-verified
      staging before processing; do not overwrite edited or unowned assets.
- [ ] Compare finite-number/vector/angle helpers by realm and semantics, and
      JSON readers by error and search-path behavior. Share only compatible
      implementations without losing load order or NaN guards.
- [ ] Inventory materializer/materialization names across commands,
      persistence, configuration and native consumers before any rename to
      spawner/spawning; define required migration or aliases first.
- [ ] Audit the exact root `garrysmod/data_static` files, ownership, hashes,
      read paths and package destinations before proposing any migration or
      cleanup. Do not alter shared files without approval and restoration.

## Output batch, integration and closure

- [ ] Present a costed preview-output proposal covering current source
      dependencies, matching plans/VMFs/BSPs, skyline models and temporary
      aliases, runtime maps, cell materials/thumbnails, revision hashes,
      package coverage, capture compatibility, restoration and human review.
      Obtain separate approval before generation, compilation or staging;
      production city and publication remain separately gated.
- [ ] Carry forward the deferred Alpha 3.2 and 3.1.5 output and integration
      work, including navmeshes, matching captured Satellite and wireframe
      materials, skyline/revision replacements and Cell Health. The prior
      Cell Health batch was cancelled; do not import partial results as a
      complete current world.
- [ ] Keep Cell Health user-started with categories unchecked by default.
      Reuse the existing capture queue, importer and watcher; navmesh work
      must save, reload and validate before photos. `buildcubemaps` is a
      manual native-console action: record user confirmation separately from
      engine verification. Launcher cubemaps and the city launcher Play/Back
      transition also remain unverified.
- [ ] Record focused automation, compiled/artifact checks, live paths, human
      review and retained limits separately. Do not mark a milestone accepted
      or released merely because its tracker moved or automated tests pass.