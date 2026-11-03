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
gates. Source wiring and the new isolated refresh are in progress.

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
fixtures pass, but the native claims suite and the prototype have not been
live-tested. Pieces do not yet persist, and the installed preview runtime
JSON was unchanged at the last checkpoint.

- [ ] When the user resumes this paused slice, verify that the intended
      `claimTiles` export matches the installed preview, back up the runtime
      JSON, and obtain approval before staging and reloading. Run the native
      claim suite and a bounded live review of claiming, build-mode protection,
      one foundation and one wall. Preserve survivor data and verify cleanup.
- [ ] Complete and review claimed-tile boundary/placement and mutual
      player/zombie and player/player protection, including access changes,
      distance, death, disconnect, multiple players and transitions.
      Environmental damage remains unaffected. Adjacent expansion needs
      another token; roads, borders, buildings and occupied multi-tile
      footprints are not claimable.
- [ ] Extend the reviewed prototype to snapped 64-unit foundations, 32-unit
      halves, 16-unit-thick walls, triangles, floors, roofs, door/window
      frames and agreed wood/stone/metal/concrete materials. The current
      prototype wall is 8 units thick; do not present it as the final
      requested 16-unit piece. Review a small prototype before a catalogue.
- [ ] Persist pieces, per-material health, repair, damage and destruction.
      Validate ownership, snapping, placement and atomic material costs on
      the server; interrupted/repeated input and failed writes must not
      duplicate pieces or items.
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