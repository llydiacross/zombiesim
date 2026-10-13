# Alpha 3.2 - Phased Implementation Plan

**Status: PLANNING ONLY. All implementation phases are pending.**

Prepared on 2026-10-13 from the current authored assets and source, with the
design decisions below confirmed by the user. This replaces the initial feature
sketch; it does not authorize implementation, world regeneration, compilation,
staging, player-data changes, production rebuilding or publication.

Alpha 3.1.5 remains the active milestone. Follow its latest dated acceptance
notes and [AGENTS.md](AGENTS.md), not historical phase labels in document headers.
Complete or explicitly disposition its retained closure work before activating
3.2. Do not reopen accepted launcher, coast, movement or loot reviews merely to
fill historical gaps.

This is the master tracker for **new authored buildings/decorations/borders/
edges, density zoning, 3-wide motorway assemblies and CSM**. The existing
[CSM implementation tracker](docs/csm-implementation.md) remains the detailed
technical reference for the lighting track; the decisions here supersede its
earlier optional-overlay scope.

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
- Coast-band widths, distance metric and the exact district influence table are
  approval gates in Phase A. They are not guessed constants in this document.
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

- **Replacement-quality lighting is mandatory. An additive overlay is not an
  accepted shipping substitute.**
- Prove projected shadows on the actual GMod branch and a reversible strategy
  for baked direct sunlight while retaining an acceptable native/CSM-off image.
  If either gate fails, stop the CSM track and request a milestone scope decision.
  Do not mark it complete, enable an overlay or silently defer it.
- Start with one removable projector on an existing approved preview map.
  No broad rebuild is needed to discover API/caster/receiver support.
- Preserve existing weather/day-night, sky palettes, fog, cameras, launcher
  presentation, clothing/gore, snow/puddles and fires. CSM is not another owner
  of those systems.
- Initially off; no automatic enablement for existing quality-preset users.
  Maximum initial shipping design is three shadow-enabled projectors; no spread,
  further cascade, first-person proxy, skybox-lighting branch or mandatory NikNaks
  dependency without separate approval.
- A client preference must never change shared server lightmaps/lightstyles or
  another client's image. A separate two-client native-fallback check is required.

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
| 0 | Readiness, inventory and restoration baseline | Alpha 3.1.5 closure/disposition and explicit 3.2 start approval. |
| A | Density/coast design and fixture contract | Phase 0; approve coast bands/district mapping before integrating them. |
| B | Motorway assembly/port survey and placement contract | Phase 0; every shipping topology needs surveyed compatible parts. |
| C | CSM engine and replacement-lighting feasibility | Phase 0; explicit permission for live/light-changing probes. Can use existing maps independently of A/B. |
| D | World/planner source implementation | Accepted A/B; CSM can remain blocked, but that is not whole-milestone acceptance. |
| E | VMF/rings/gates and runtime travel integration | D and verified assembly contract. |
| F | Derived layout, skyline, map/capture and compatibility source | D/E; no broad material/capture job yet. |
| G | Small compiled geometry prototypes and travel review | D/E/F focused checks; separate approval for compile/staging. |
| H | CSM service, cascades and view integration | C go decision; approved metadata/lighting strategy. Final geometry review also uses G maps. |
| I | Matched integrated visual/performance/lifecycle acceptance | G/H and independent native fallback. |
| J | One approved full-preview closure batch | I, measured recipe budget and explicit expensive-work approval. |
| K | Documentation, packaging and milestone acceptance | J; production and publication remain separate decisions. |

Source-only work that does not depend on an outstanding live gate may be batched
with approval, but must not bypass phase dependencies or imply acceptance.

### Phase 0 - Readiness and exact source baseline

- [ ] Reconcile latest Alpha 3.1.5 acceptance/deferral notes and obtain start
      approval. Planning is not permission to activate the milestone.
- [ ] Record preview/city profile settings, seed, current matching manifest/plan,
      source hashes, current loaded map/cell/player state and restoration ledger.
- [ ] Inventory current working-tree assets, not only committed tiles. Identify
      additions, renames, missing explicit references, invalid filenames,
      companion VMX mismatches and discovery exclusions; ask about discrepancies.
- [ ] Inventory all generic and special-family pools by density and footprint.
      Report missing optional pools separately from required topology gaps.
- [ ] Preserve authored overhangs, current safe-zone detail work, unrelated API
      submodule changes and accepted presentation. No automatic source cleanup.
- [ ] Capture a small agreed native-lighting baseline and confirm watcher-free
      `-disableluarefresh` launch before future performance work.
- [ ] At actual milestone activation, update active tracker links and the single
      version/changelog source together; retain `in development`.

Exit: an agreed source inventory, safe restoration path and clear authorization.

### Phase A - Density zoning and deterministic selection contract

- [ ] Implement/test a pure filename classifier: numeric variant ignored;
      terminal letter token before optional footprint suffix determines class;
      no token means untagged/all-tier. Reject unsupported tagged classes visibly,
      rather than treating malformed names as universal.
- [ ] Define one authoritative `sceneryDensityTier` plus diagnostic source
      (coast band/district/override). Migrate/alias existing `buildingDensityTier`
      deliberately so filenames and existing consumers do not diverge.
- [ ] Draw a small coast-to-inland/district fixture. Approve low-band width,
      medium transition, high threshold, distance metric and important district
      mapping before generating a full world. Distinguish actual ocean from
      decorative water-border variants, lakes and arbitrary grid edges.
- [ ] Specify precedence: protected coast -> approved inland district influence
      -> inland baseline. Store resolved tier in generated data; consumers do
      not independently reinterpret environment tags.
- [ ] Define deterministic target-tier selection first, compatible template
      choice second. Untagged candidates may satisfy any selected tier within
      the correct functional pool. Empty optional pools keep terrain; required
      empty pools fail. Report untagged placements and shortages explicitly.
- [ ] Use a stable hash including seed, cell/recipe policy, ring, slot, role and
      variant; do not depend on filesystem enumeration or hash-table order.
- [ ] Define eligible neutral pieces within each functional pool, not one global
      untagged pool. Choose a target tier, then select from that tier plus the
      compatible untagged pieces. A neutral water pier cannot satisfy a missing
      land-wall pool. Report chosen target, actual tag and exclusion reason.
- [ ] Test roll boundaries (0, 94, 95, 99 for a 100-bucket roll), all tiers,
      neutral assets, footprints, special families, all missing-pool paths,
      route-adjacent exceptions and reproducibility.

Exit: approved density map/policy with exact selection tests. No scenery is
silently reclassified by its physical height or numeric filename.

### Phase B - Survey motorway puzzle pieces and reserve their envelopes

- [ ] Open requested authored/isolated fixtures in Hammer++ for the user.
      Preserve unsaved windows. Survey every VMF listed in section 2.
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
- [ ] Transform origin, footprint, envelope and ports through the same Source
      yaw convention. At 90/270 degrees width/height swap. Include the
      even-width 6x3 half-tile/origin-alignment case explicitly.
- [ ] Resolve all ordinary topologies plus motorway corner+onramp, single/dual
      ramps, bridge crossings, terminals and isolated motorway cells. Record
      unsupported combinations; do not fake them with crossed straight tiles.
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

Exit: Hammer-reviewed assembly/connector table, all four rotations and a
collision-free small arrangement for every supported topology.

### Phase C - Hard CSM feasibility before expensive lighting work

Follow CSM tracker Phase 0 and its caster/receiver matrix.

- [ ] Record branch/build, GPU/HDR, flashlight/projector settings, addons and
      native map lighting. Agree target hardware and maximum acceptable frame
      cost/frame-time tails before promising a quality preset.
- [ ] On an existing preview map, prove one removable orthographic shadowed
      projector against BSP/static/dynamic props, survivor/walkers, ragdolls/
      limbs, foliage, translucent surfaces and custom meshes as applicable.
- [ ] Verify flashlight coexistence, pool exhaustion, removal and exact native
      restoration. Unsupported pairs are documented, not masked by materials.
- [ ] Separately approve a reversible lighting experiment. Inspect effective
      LDR/HDR `_light`, `_ambient`, overrides, sun direction and baked results.
      `light_environment` inputs must not be assumed to remove compiled lightmaps.
- [ ] Demonstrate replacement direct lighting while preserving appropriate
      ambient, native client fallback and independent client settings. Any
      proposed relit-map variants require explicit map-art/package approval.
- [ ] If replacement/native fallback cannot both work acceptably, stop CSM and
      present evidence for a scope decision. No overlay acceptance by default.

Exit: actual-engine feasibility plus an approved replacement/native strategy,
or a documented CSM no-go. Do not allocate three lights before this gate.

### Phase D - World generation, density pools and motorway-only scenery

- [ ] Update settings/discovery from the approved inventory; validate every
      required explicit path before placement. No terrain fallback for a missing
      required motorway topology.
- [ ] Resolve density consistently across ordinary/special building pools,
      decorations, multi-tile features, open-terrain fill and recipe variants.
      Remove soft all-tier weighting where it violates hard exclusions.
- [ ] Extend corner selection to a validated variation pool where tagged corner
      alternatives exist; preserve a compatible single-corner setting for old
      fixtures. Do not silently discard the new tagged corners or borrow a
      differently oriented corner from another family.
- [ ] Decouple decoration placement from the presence of a building pool.
      A motorway cell with zero building candidates must still place decorations.
- [ ] Reserve transport assemblies before scenery. Prevent every building/
      skyscraper/commercial/industry/carpark/physical-landmark insertion path,
      including forced fixtures/late macro passes, on motorway cells.
- [ ] Deterministically relocate conflicting physical features in the world
      generator, before reachability/final serialization. Preserve IDs and
      associations; show old/new coordinates and reason. Validate road access,
      safe-zone spacing, destination capacity and density-compatible placement.
- [ ] Reject impossible/fixed-identity relocation with a clear decision gate;
      never drop landmarks, fabricate a safe zone or leave mismatched map labels.
- [ ] Keep recipe reuse deterministic: density and assembly/port signature
      participate in identity; absolute distance need not create a unique recipe
      when the resolved layout policy is identical.
- [ ] Preserve adaptive variation cap 4 and adjacent actual-layout checks.
      Review total recipe growth; the accepted previous 311-recipe preview is
      a comparison baseline, not a promise of the new map count.

Exit: focused planner fixtures prove density exclusions, decoration-only
motorways, deterministic relocation and unchanged intended travel graph.

### Phase E - Rectangular VMFs, ring leases and actual travel

- [ ] Generalize square-only planner/builder helpers together, while preserving
      existing 1x1/2x2/3x3 building frontage and emitting-instance semantics.
- [ ] Carry authored origin offsets explicitly; calculate physical instance
      position independently from a rectangle's integer reservation anchor.
      Validate footprint coverage, duplicate owners and every suppressed slot.
- [ ] Reserve the full 3-wide road continuation through both rings. Replace
      covered walls/corners only through an explicit boundary lease; preserve
      shoulder closures and no-gap connections to adjoining pieces.
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
- [ ] Resolve effective lighting provenance for the accepted CSM strategy:
      map identity/source-build key, direction, LDR/HDR direct/ambient and
      replacement eligibility. Missing/stale metadata yields visible CSM-off.

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

### Phase H - CSM service, cascades and view ownership

Follow CSM tracker Phases 1-3; its proposed files remain proposals until needed.

- [ ] Add one `ZM_CSM` owner, pure layout math and bounded projector resource
      ownership. Include dependencies before hooks; no editor entity framework.
- [ ] Implement explicit off/waiting/unsupported/ready/suspended/failed states,
      generation tokens, finite-value validation, idempotent cleanup and partial
      allocation rollback with visible errors.
- [ ] Consume the actual final gameplay camera and matching lighting metadata.
      Retain an exact native off path under the accepted replacement strategy.
- [ ] Accept one light before introducing contiguous 1/2/3 cascade records,
      stable light-space snapping, conservative depth/coverage and blending.
- [ ] Use original cleared static masks first. Dynamic masks require demonstrated
      need and at most three 1024-square slots plus one template (16 MiB nominal
      RGBA, excluding engine shadow maps). No per-frame parsing/file reads or
      unchanged-layout RT repainting.
- [ ] Suspend/scope captures and unsupported secondary views explicitly, restore
      main-view state on errors/cancel/return and preserve cache semantics.
      Launcher and native skybox remain initially off, with acceptable native
      appearance; optional support requires its own review.
- [ ] Test third-person/zoom, death/spectating, den entry/exit, cell reload,
      cleanup/reconnect, resize/FOV, sky inspection and map/Level capture.
- [ ] Test weather/snow/puddles, foliage, clothing/gore/limbs, fires/outlines,
      flashlight and two clients with independent CSM settings.
- [ ] Keep options/default off until appearance/cost approval. Add no silent
      global flashlight cvar changes, per-frame networking or hot-path allocations.

Exit: human-approved replacement lighting, stable cascade coverage, bounded
resources and independently acceptable native fallback.

### Phase I - Integrated quality, performance and failure acceptance

- [ ] Agree exact benchmark conditions and acceptance budget before sampling:
      map/logical cell, native/CSM state, lighting/HDR, weather, camera/resolution,
      foreground focus, quality, crowd/props/foliage and warm/cold state.
- [ ] Compare native, one, two and three cascades on matched workloads, including
      wide motorway junctions, low sun, tall buildings, dense borders and moving
      crowds. Record process frame-time median/p95/p99, resources/commit/heap and
      update/mask CPU separately; Lua-hook timing is not GPU shadow cost.
- [ ] Prove stationary-camera moving casters remain correct. Add shadow skipping
      or culling only if measured bottlenecks justify them, with coherent full
      generation freezing/invalidation and stale-work cancellation tests.
- [ ] Repeat enable/disable, travel and secondary-view cycles; verify no orphan
      projectors/models/material queues, persistent player changes or preference
      leaks. Do not mistake cache high-water admission for proven leakage.
- [ ] Review density gradient and district identity, motorway visual connectivity,
      native fallback, cascade seams/shimmer/acne and approved existing effects.
- [ ] Record unsupported modes and actual failures. Exceeding budget or breaking
      native replacement fallback blocks CSM acceptance.

Exit: accepted integrated prototypes with measurable budgets and retained limits.

### Phase J - Single separately approved full-preview closure

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

### Phase K - Documentation, package checks and milestone decision

- [ ] Update [docs.md](docs.md), [readme.md](readme.md), [AGENTS.md](AGENTS.md),
      the CSM tracker, version/changelog and relevant file instructions with the
      actual naming, footprint, density, diagnostics and supported commands.
- [ ] Mark the historical square-only rectangle deferral in
      [multi-tile design](docs/two_by_two_tile_templates_plan.md) superseded only
      when the rectangular implementation is accepted; retain useful history.
- [ ] Validate package allowlist/source ownership/licences, model companions,
      map/nav/runtime/material revisions and CSM resources. No new borrowed
      RealCSM assets or dependencies without licence approval.
- [ ] Record static, compiled, live, visual, performance and explicitly deferred
      acceptance separately. Request user milestone acceptance.
- [ ] Obtain separate approval for a 48x48 production rebuild and for publication.
      Package/mount/download verification and remaining release blockers do not
      vanish when preview is accepted. Do not change version to `released` early.

## 4. Focused validation and handoff commands

Run commands from the repository root. These are **future validation steps,
not commands run during planning**. Inspect each script's parameters and workload
before execution: some existing "tests" generate a full preview plan or model
outputs and are not fast unit checks.

| Area | Existing entry point / required use |
| --- | --- |
| All changed Lua | `.\bin\test_glua_syntax.ps1`; syntax only. |
| Existing square footprints/frontage | `.\bin\test_building_frontage.ps1` and `.\bin\test_multi_tile_templates.ps1`; both required for coupled frontage changes, but schedule their expensive paths with approval. |
| Borders/edges/coast | `.\bin\test_border_showcase.ps1`, `.\bin\test_outer_edges.ps1`, `.\bin\test_skybox_edges.ps1`; refresh stale asset fixtures and keep existing coast controls. |
| Planner/VMF regressions | `.\bin\test_phase_c2_layouts.ps1`, `.\bin\test_phase_e_layouts.ps1`, naming, player-start and safe-zone entrance suites as affected. Update semantic assertions for intended motorway exclusions; do not weaken connectivity checks. |
| Recipe variety | `.\bin\test_cell_variants.ps1 -PlanData <isolated-plan.json> -BaselinePlanData <previous-plan.json> -LayoutDirectory <isolated-src>`; distinguish unchanged graph assertions from explicitly approved feature relocations. |
| Compiled ports/gates | `.\bin\test_transition_gate_bsps.ps1` and `.\bin\test_outer_edge_bsps.ps1` against the exact current fixtures; extend for 3-wide openings/elevations. |
| Derived art/skyline | `.\bin\test_cell_map_artwork.ps1`, skyline manifest/height/tower suites as affected; tests are not human visual acceptance. |
| Packaging | `.\bin\test_workshop_packages.ps1`; do not upload. |
| Offline Lua logic | Existing `tests\glua\harness.py` workflow in README; strict feature-specific fixtures and relevant focused cases only. |
| Bridge | `.\bin\invoke_dev_bridge.ps1 -Command 'zombiesim_player_status'`; relevant registered suites/status only. Exit 2 means ask about paused/loading state. Never send `lua_*` or refresh through the bridge. |

Add only the small missing regression entry points needed by implementation,
for example a pure density selector fixture and a transport assembly/ports
fixture. Their future names/commands must be documented after they exist.
Do not duplicate the offline harness or create parallel generic test frameworks.

Minimum new regression matrix:

- Every density class/untagged token; numeric variants 1 and 6; rectangular/square
  suffixes; 95:5 threshold boundaries; unavailable pools; route exception;
  low coast protected from commercial override; deterministic output ordering.
- Buildings, decoration-only motorway with zero building pool, open fill,
  commercial/industry/skyscraper/landmark paths, both rings and their variants.
- All eight new motorway VMFs, four yaws, even-sized origin, surveyed connectors,
  bridge layers, ramp joins, ring reservations, ocean-side conflicts and deliberate
  incompatible assembly with explicit failure/no 1x1 fallback.
- No duplicate emitted instances, missing reserved owners, forbidden scenery,
  unrelated square-frontage regressions or stale recipe/layout signatures.
- Safe-zone/landmark relocation, fixed-feature conflict, no unreachable den,
  profile isolation, unchanged survivor/inventory data and revision reset rollback.
- CSM support/failure lifecycle, coherent cascade masks/depth, all view boundaries,
  exact off/native restoration, independent clients and resource limits.

## 5. Future-agent next action and stop conditions

At handoff, read this tracker, the latest active-milestone evidence and the CSM
subtracker. Do not start a build because new VMFs are present.

1. Confirm Alpha 3.1.5 closure/disposition and ask for 3.2 activation.
2. Start Phase 0 inventory and obtain author decisions on malformed/excluded
   assets without changing them.
3. Settle Phase A coast widths/district mapping and Phase B connector geometry
   through small explicit fixtures. No guessed motorway yaws, heights or origins.
4. Run Phase C only with approved bounded live/light-changing probes; replacement
   failure is a hard CSM stop.
5. Implement accepted contracts source-first, with each phase's focused checks.
   Obtain separate approval for G prototypes and J's bundled expensive work.

Stop and ask when a required topology/density boundary pool is missing, an
assembly cannot fit/connect within the current envelope, relocation would change
fixed gameplay identity, coast policy is ambiguous, CSM cannot meet replacement/
native fallback, or the recipe/performance/package budget exceeds approval.

Keep checkpoints after subsystem boundaries and failed validation loops with
the exact source/artifact, hypothesis, result and next discriminating check.
Record actual results here during implementation; every checkbox above remains
pending until the corresponding work and acceptance evidence exist.
