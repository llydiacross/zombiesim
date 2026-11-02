# Todo Alpha 3.4 

**Status (user, 2026-11-01): Alpha 3.4 is now the primary focus; the remaining
Alpha 3.3 work is deferred.** Scope for this step: wire every new, improved
and renamed tile into the generator, generate fresh isolated preview data
(manifest, plan, layouts, VMFs), build the viewer and load that data into it
for review. The Satellite image is deferred until the preview world is
rebuilt. Compiling, staging, navmesh and Cell Health work need separate
approval.

## New-tile wiring (2026-11-01)

User decisions:

- **`ra_` buildings** (renamed `tile_ra_building_1a/1aa/1aaa`) are used only in
  radioactive cells, preferred over industrial when a tier-matching tile
  exists. The `radioactiveBuildings` pattern accepts both the old
  `building_ra`/`skyscraper_ra` names and the new `ra_building` names.
- **Industrial walls** (`edges/tile_edge_industrial_wall_*`,
  `border/tile_border_industrial_wall*`) are used on cells whose emitting core
  buildings are mostly industrial or warehouse tiles (`industry_majority`,
  `Get-ZMWallProfileKey` in `bin/outer_edges.psm1`). A cell's own profile pool
  (radioactive, military and so on) still wins.
- **Border walls** 2a/2aa/2aaa/3a/3aa/3aaa and corner 1aaa join the default
  border pools.
- **Outer-edge corners** now choose by density from all nine
  `tile_edge_wall_corner_{1,2,3}{a,aa,aaa}` (`cornerVariationTemplates`).
  A profile `cornerTemplate` still overrides them. Added edge walls
  3aaa-6aaa, `ra_wall_5a/5aa` and `army_wall_1aaa`.
- Deleted sources (`tile_edge_wall_corner.vmf`, `tile_edge_wall_ra_2a.vmf`) are
  no longer referenced. Decorations and landmark tiles are picked up by the
  existing patterns and globs.

**Verification follow-up (2026-11-02):** the fresh seed-1337 plan contains all
nine `tile_skyscraper_ra_*` templates. There are 33 explicit cross-tier
selections across those nine templates, all marked `anyTier` and confined to
radioactive/destroyed profiles; `tile_skyscraper_ra_3aaa_2x.vmf` appears four
times total (one cross-tier selection) in the current plan.

The blank neighbors at grid `(3,2)` / logical `(3,-10)` were caused by the east
safe-zone entrance suppressing border slots `(5,1..3)`, which also caused their
projected outer slots `(6,1..3)` to be omitted. Outer-edge generation now
backfills only those projected slots when the suppression comes from entrance
metadata. The regenerated layout has all three wall placements and 32 outer
placements total. All 394 required recipe VMFs exist; the complete-infill pass
refreshed the 26 trusted motorway recipes without pruning retained outputs.
Viewer `--stats` reports 576 cells, zero missing recipes/files, zero failed
sides or depth-limited instances; the target cell reports zero missing
instances in the viewer screenshot. `test_multi_tile_templates.ps1` passes
with matching standard fixture settings, expanded city settings and the
trusted plan.

The focused `test_outer_edges.ps1` suite now passes 1,753 assertions with the
current trusted preview plan. It permits shared recipe filenames only when
their core placements match, exercises a retained road cell for the military
profile case, and checks the current west-ocean outer tiles and shell bounds.
No VBSP compile, staging, Satellite refresh or human visual review has occurred;
those remain separate gates.

**Motorway bridge duplication (2026-11-02):** grid `(17,2)` / logical
`(17,-10)` emitted ordinary bridge tiles at `(1,2)` and `(3,2)` inside the
authored motorway bridge's leased footprint. The trusted grid owner now
suppresses those ordinary instances, retaining the approach bridges outside
the footprint, motorway transforms, continuations and gates. Both crossing
orientations are covered. The same correction applies to grid `(17,0)`,
`(1,7)`, `(6,11)`, `(15,17)` and `(15,23)`.

The approved isolated preview refresh changes only those six cell layouts;
all other cell layouts and every motorway assembly contract match the
pre-change plan. The builder's hash-verified previous-layout refresh now
accounts for the previous core instance count when instances are suppressed.
Exactly six VMFs changed; the other 388 recipe VMFs remain hash-identical,
complete infill is retained and no required cell VMF is missing. Bridge
ownership/generated-instance checks pass 99 assertions across six cells;
motorway infill scope passes 969 assertions. Fresh viewer statistics cover
576 cells with zero missing recipes/files, failed sides, depth-limited
instances or texture failures. After an approved viewer restart at grid
`(17,2)`, the user confirmed the corrected crossing looks correct. This is
viewer visual approval, not compiled or in-game verification. No compile,
staging or Satellite refresh ran.

# World Visualization Tool

**Decisions (user, 2026-10-31):** start after the Alpha 3.3 west-ocean
fixture review. Build a native C++ raylib/CMake application (matching the
Walker toolchain) in a root subfolder. Convert tile VMF brushes directly
through one shared converter that can also feed prefab-editor reference
models; do not depend on compiled `.mdl` tiles. Begin read-only from the
generated plan/`layout.json` placements. Design editing separately, because
saved edits must pass the generator's footprint, lease, connection, gate and
required-map validation. The viewer does not replace VBSP/visibility,
lighting, navmesh, gate or in-game skybox-coast checks.

- Create a visualization tool which can quickly display an entire world. Such as "Preview" or "city".
    - Uses the buildings tiles, exported into models
    - Uses the road tiles, exported into models
    - Doesn't render the ocean or the mountain or what surrounds the map, is just a visual tool to quickly see what a map might look like quickly

- The visualisation tool needs to be outside of garry's mod, as it should not depend on the game engine for rendering and should be able to quickly display the world independently. Realistically it should be a standalone application or a lightweight engine capable of loading and rendering the exported models efficiently in a sub folder on root.

- The world visualization tool loads the worlds json file, then parses the data to determine the placement of buildings and roads. It uses this information to load the corresponding exported models and render them in the visualization environment, providing a quick and accurate representation of the world layout.

- We can edit things inside of the visusalization tool such as specific tile placements, rotations, and offsets, allowing for quick adjustments and experimentation with the world layout without modifying the original game files. This will allow us control over the generated world layout, as after we launch the game. We will not generate a new world. We will need tools to modify the current world and ensure everything remains consistent, no errors appear from our changes or anything else, and that all elements according to the game's requirements work correctly

- You can pan, zoom, and rotate the view within the visualization tool, allowing for a comprehensive examination of the world layout from different angles and perspectives.

- Lighting should be implemented in the visualization tool to provide realistic shading and shadows for the buildings and roads, enhancing the visual clarity and depth perception of the world layout.

- You can only fly around the world in the visualization tool, meaning you can move freely in all directions without being constrained by the terrain or other physical limitations. This allows for a complete and unobstructed view of the world layout from any angle. There is no need for collision detection or terrain interaction within the visualization tool.

- It is just a preview of the geometry, if it is not too complex, you could try reading the prop entities and display them too, providing a more complete representation of the world layout without affecting the original game files.

**Status (2026-11-01):** `world-viewer/` (see its README) builds
`bin/zombiesim-world-viewer.exe` and loads the generated preview recipe VMFs
with recursive `func_instance` expansion. Textures (T) come from each
material's `$basetexture` via the mounted GMod/Source VPKs: 218 materials,
216 textured, 0 failures; only water without a base texture stays flat.
Lit (L) and night (N) modes read `light`/`light_spot`/`light_environment`
entities: 198 cells have lights, most 27 at cell (18,1). Limits: no shadows
or bounce (not VRAD), max 8 lights per 640-unit grid cell, no props, decals
or blend/water shaders. Agent screenshots checked; user review pending.

## Compile-fidelity contract (proposal, 2026-11-01, not yet approved)

Goal: the viewer must show exactly what VBSP is about to receive, so a world
can be reviewed before the multi-hour compile instead of after it.

- **Read the generated VMFs, not just the plan.** The plan/`layout.json` does
  not describe everything the builder emits: motorway assemblies and their
  restored ordinary-road doglegs, terrain infill, border/outer rings, gates,
  den copies and the shell are all added by `build_cell_vmfs.ps1`. Reading
  the plan alone would recreate generator logic and could drift from it.
  The viewer instead loads each generated recipe VMF in the profile's
  `src` directory and expands every `func_instance` recursively, with the
  same origin/angle transforms Source applies, down to brushes (and
  optionally props).
- **Plan/runtime JSON as overlays only.** Logical cell grid, recipe-to-cell
  mapping, districts, environment profiles, landmarks, safe zones, gates and
  motorway leases come from the matching plan and runtime export. They are
  labels and colouring, never a second source of geometry.
- **Provenance stamp.** Each viewer session records the hashes of every
  generated VMF and its recursive instance dependencies (reuse
  `bin/vmf_source_dependencies.psm1`), plus the plan/manifest/settings
  hashes. The viewer shows "matches compile input" or lists stale/missing
  recipes. Optionally the compile can refuse, or warn, when a VMF differs
  from the last reviewed stamp.
- **Fast path.** Plan + VMF build is roughly 20 minutes for the whole preview
  world; compile is hours. Cache converted tile meshes keyed by the source
  tile hash, so only changed tiles are reconverted.
- **Generation-review aids.** Colour cells by district/profile/landmark and
  show per-district counts of commercial, leisure, park, police and fire
  placements, so the distribution goals below can be checked at a glance.
- Not replaced by the viewer: VBSP/portal budgets, VVIS/VRAD, lighting,
  navmesh, gate travel, skybox coast and in-game review.

# Generation changes (after the visualization tool)

**Requested (user, 2026-11-01):** do these after the viewer exists, and use
it to confirm the distribution before compiling. The running Cell Health
batch was cancelled at the user's request because the world will be
regenerated anyway. It stopped at 1048 of 1142 results, in its
navmesh-generation phase; status then reported `cancelled` and inactive. The
server restored map `zz_preview_49d203952b23-v1`, and the read-only database
shows the Doctor survivor back at preview (3,-2) with health 100. Its partial
results are superseded and will not be imported.
Root causes are not yet investigated; settings such as
`commercialSpreadChancePercent`/`commercialSpreadProfiles`, the `parkland`
weights and the `Police`/`Fire`/`Leisure`/`Park` landmark patterns in
`generator-settings.json` are starting points, not conclusions.

- [ ] **Commercial spread:** the world map shows very few commercial
      buildings. Spread commercial buildings more evenly across the map.
      Settle the target measure (per district, per density tier or a minimum
      spacing) before changing weights.
      Measured on the current preview plan (571 cells: 71 low, 120 medium,
      380 high density): all 18 commercial placements are in low-density
      cells within 2 cells of the ocean. All three commercial tiles
      (`tile_commercial_1a`, `_2a_2x`, `_3a_2x`) carry the single-letter
      low-density tag, and ordinary building selection only accepts
      untagged tiles or tiles matching the cell's target tier. Medium (`aa`)
      or high (`aaa`) commercial tiles would become eligible inland. Their frequency still depends on the
      55% spread roll, the share of the mixed building pool and the road-
      frontage swap; check it in the viewer.
      Update 2026-11-01: the user added `tile_commercial_2aa_2x` and
      `tile_commercial_3aaa_2x`; the `commercial` pattern already matches them,
      so medium/high cells can now select commercial art. Count it in the viewer.
- [ ] **Fewer park landmarks, more leisure:** the `park` landmark is too
      common (37 landmark cells against 27 leisure). Make park landmarks
      rarer and give many of those slots to Leisure landmarks (user,
      2026-11-01). The `parkland` environment profile and its building
      density are out of scope unless the user asks otherwise.
      Source wired: `mapGeneration.landmarks.commonWeights` (Leisure1.0,
      Park0.35) drives one weighted pick per common landmark in
      `generate_world_cells.ps1`. Isolated seed-1337 manifests: equal
      weights are byte-identical to the old uniform pick; the weighted run
      gives Park37->22, Leisure27->42, all other landmark counts unchanged
      (86 landmark cells, 11 safe zones). One featured cell still gets a
      Park. Not regenerated, compiled or staged; check in the viewer.
- [x] **Cell-map/Satellite road-piece render fix (source):** the user
      reported the LAB marker on a road and grey/background blocks on roads.
      `build_cell_map_materials.ps1` coloured road pieces by planner role,
      so `carpark_road_junction` (54 placements) drew as carpark grey,
      `building_road_junction` (58: driveway/T/bus) and `bridge_ramp` (11)
      as background, and `landmark_road_junction` (11) as landmark orange
      and as a landmark-marker anchor (Laboratory at (14,22)/(5,23), Leisure
      at (14,20)). Ordinary `roads/*` templates now always render as road
      and never anchor markers. `test_cell_map_artwork.ps1` covers all four
      roles and the anchor; it fails against the old renderer. Preview cell
      materials and the Satellite atlas have not been rebuilt or staged.
- [ ] **Police and fire stations:** guarantee at least one police station
      and at least one fire station in every district. Decide how this
      interacts with existing landmark density shortages, safe zones and
      fixed landmarks (which are never relocated).
      Current plan: one police and two fire landmark cells. No
      `tile_police*`/`tile_fire*` VMF exists yet, so those landmarks get no
            dedicated building; at least one of each is needed for this item. Landmark tiles are
      density-exempt (leisure/park `_1a` tiles already appear in high-density
      cells), so density variants change which art is used, not how many
      landmarks exist. The count is set by manifest landmark generation.
      Update 2026-11-01: `tile_policestation_1a/1aa/1aaa` and
      `tile_firestation_1a/1aa/1aaa` now exist and match the Police/Fire
      landmark globs, so landmark cells get dedicated buildings. The
      one-per-district guarantee is still open.
- [ ] Carry over from Alpha 3.3: the approved `_ra_` radioactive building
      preference and the restored on-ramp doglegs at (13,18) and (6,23)
      ride along with this regeneration; (6,23) still needs Hammer and
      in-game review.
- [ ] Review the regenerated world in the viewer (per-district counts and
      visual spread) and get user approval before compiling, staging,
      navmesh and the Cell Health photo batch.